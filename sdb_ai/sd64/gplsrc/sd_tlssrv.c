/* SD_TLSSRV.C
 * TLS for the SD API transport: the server's relay process.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * START-HISTORY:
 * 15 Sep 26 Windows port - adopted from SD Core for Linux S.19 (RELEASE_1.1
 *           41), with the two things Windows has no equivalent for taken out
 *           and said so below: the drop to nobody, and the owner/mode check on
 *           the identity, which the DACL walk in win32tls.c replaces.
 * 15 Sep 26 dm S.19: created.  See sd_tls.h.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * sd_tls_relay_start() is called by start_connection() with descriptor 0 the
 * client's connection.  It forks:
 *
 *   the relay    keeps the connection, loads the server identity, does the
 *                TLS handshake, sends sd the 32-byte channel binding, then
 *                copies bytes both ways until either side ends.
 *   sd           gets one end of a socketpair as descriptors 0 and 1, reads
 *                the binding, and carries on exactly as before.
 *
 * THE RELAY RUNS AS LocalSystem, AND THAT IS A GAP LINUX DOES NOT HAVE.  On
 * Linux the relay reads the identity as root and becomes nobody before it
 * parses one byte from the network, so a flaw in the TLS code hands nobody
 * root.  Here sd -n is fork()ed by sdwind, itself the service's child, and
 * Windows has no setuid: a Cygwin process cannot shed its token.  So the
 * relay parses network bytes with the token it was born with, which is the
 * same token the API session itself runs with today (PROJECT_STATUS.md,
 * "A REMOTE API SESSION STILL RUNS AS LocalSystem").  Recorded in
 * RELEASE_1.1 41 rather than papered over; closing it means a restricted
 * token for the whole session, which is that entry's other half.
 *
 * THE IDENTITY is one file, <identity_dir>/api.pem, holding the private key
 * and a self-signed certificate.  One file, written to a temporary name and
 * renamed, so two first connections at once cannot leave a key beside the
 * other's certificate.  It is refused unless the DIRECTORY EXISTS and both it
 * and the file grant access to nobody but SYSTEM and Administrators
 * (win32tls.c).  The relay never creates the directory: its parent,
 * C:\ProgramData\SD, is writable by every SD user, so a directory made here
 * would inherit their Modify - and one made by them first would be theirs.
 * gplbld/secure-tls.ps1 creates it at install time with the right ACL, the
 * same shape as secure-reclaim.ps1.
 *
 * END-DESCRIPTION
 */

#include "sd_tls.h"

#include <stdbool.h>                  /* not from sd_tls.h - see there */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <syslog.h>
#include <unistd.h>

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#define RELAY_BUFFER 16384
#define RELAY_EXIT_IDENTITY 2
#define RELAY_EXIT_PRIVILEGE 3
#define RELAY_EXIT_HANDSHAKE 4
#define RELAY_EXIT_BINDING 5

static unsigned char server_binding[SD_TLS_BINDING_BYTES];
static bool have_binding = false;

static bool write_all(int fd, const void* buf, size_t len) {
  const char* p = buf;

  while (len > 0) {
    ssize_t n = write(fd, p, len);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      return false;
    p += n;
    len -= (size_t)n;
  }
  return true;
}

/* ======================================================================
   The identity                                                           */

/* Windows port: Linux tests st_uid against geteuid() and the mode bits.
   Neither is real here (noacl mount - see the description block), so the
   type comes from stat() and the access question goes to the DACL. */
static bool private_to_me(const char* path, const struct stat* st,
                          bool is_dir, char* errmsg, size_t errlen) {
  if (is_dir ? !S_ISDIR(st->st_mode) : !S_ISREG(st->st_mode)) {
    snprintf(errmsg, errlen, "%.300s is not a %s", path,
             is_dir ? "directory" : "regular file");
    return false;
  }
  return win32_admin_only(path, errmsg, errlen) != 0;
}

static bool create_identity(const char* path, EVP_PKEY** pkey_out,
                            X509** cert_out, char* errmsg, size_t errlen) {
  EVP_PKEY* pkey = NULL;
  X509* cert = NULL;
  X509_NAME* name = NULL;
  unsigned char serial[8];
  char tmp[4096];
  int fd = -1;
  FILE* fp = NULL;
  bool ok = false;

  pkey = EVP_PKEY_Q_keygen(NULL, NULL, "ED25519");
  cert = X509_new();
  if (pkey == NULL || cert == NULL) {
    sd_tls_error_text("cannot generate the server key", errmsg, errlen);
    goto done;
  }

  if (RAND_bytes(serial, sizeof(serial)) != 1) {
    sd_tls_error_text("cannot generate a serial number", errmsg, errlen);
    goto done;
  }
  serial[0] &= 0x7F;
  {
    BIGNUM* bn = BN_bin2bn(serial, sizeof(serial), NULL);
    bool set = bn != NULL &&
               BN_to_ASN1_INTEGER(bn, X509_get_serialNumber(cert)) != NULL;
    BN_free(bn);
    if (!set) {
      sd_tls_error_text("cannot set the serial number", errmsg, errlen);
      goto done;
    }
  }

  /* BUILD the name rather than borrow the certificate's own.  OpenSSL 4 returns
     X509_get_subject_name() as const X509_NAME* (OpenSSL 3 did not), so writing
     entries into the borrowed pointer discards the const qualifier - a warning
     the free check test-tls-relay.py caught on the Linux port when its build box
     moved to libssl 4 (mailbox 15 Sep 2026; SDCore4Linux c773008).  It is latent
     here only while the Windows build links OpenSSL 3.x, and make carries no
     -Werror, so it never broke the binary - but building the name is correct on
     both.  X509_set_subject_name and X509_set_issuer_name both COPY it, so it is
     freed unconditionally at done:. */
  name = X509_NAME_new();
  if (name == NULL) {
    sd_tls_error_text("cannot allocate the certificate name", errmsg, errlen);
    goto done;
  }
  if (X509_set_version(cert, 2) != 1 ||
      X509_gmtime_adj(X509_getm_notBefore(cert), -86400L) == NULL ||
      X509_time_adj_ex(X509_getm_notAfter(cert), 36500, 0, NULL) == NULL ||
      X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
                                 (const unsigned char*)"SD Core API", -1, -1,
                                 0) != 1 ||
      X509_set_subject_name(cert, name) != 1 ||
      X509_set_issuer_name(cert, name) != 1 ||
      X509_set_pubkey(cert, pkey) != 1 ||
      X509_sign(cert, pkey, NULL) <= 0) {
    sd_tls_error_text("cannot build the server certificate", errmsg, errlen);
    goto done;
  }

  if (snprintf(tmp, sizeof(tmp), "%s.XXXXXX", path) >= (int)sizeof(tmp)) {
    snprintf(errmsg, errlen, "identity path too long");
    goto done;
  }
  fd = mkstemp(tmp);               /* mode 0600 */
  if (fd < 0) {
    snprintf(errmsg, errlen, "cannot create %.300s: %s", tmp, strerror(errno));
    goto done;
  }
  fp = fdopen(fd, "w");
  if (fp == NULL) {
    snprintf(errmsg, errlen, "cannot open %.300s: %s", tmp, strerror(errno));
    close(fd);
    unlink(tmp);
    goto done;
  }
  if (PEM_write_PrivateKey(fp, pkey, NULL, NULL, 0, NULL, NULL) != 1 ||
      PEM_write_X509(fp, cert) != 1 || fflush(fp) != 0 ||
      fsync(fileno(fp)) != 0) {
    sd_tls_error_text("cannot write the server identity", errmsg, errlen);
    fclose(fp);
    unlink(tmp);
    goto done;
  }
  fclose(fp);
  if (rename(tmp, path) != 0) {
    snprintf(errmsg, errlen, "cannot rename %.300s: %s", tmp, strerror(errno));
    unlink(tmp);
    goto done;
  }

  syslog(LOG_INFO, "SD API TLS: created server identity %s", path);
  ok = true;

done:
  X509_NAME_free(name);   /* copied into the cert; NULL-safe on early failures */
  if (ok) {
    *pkey_out = pkey;
    *cert_out = cert;
  } else {
    EVP_PKEY_free(pkey);
    X509_free(cert);
  }
  return ok;
}

static bool load_identity(SSL_CTX* ctx, const char* dir, char* errmsg,
                          size_t errlen) {
  char path[4096];
  struct stat st;
  EVP_PKEY* pkey = NULL;
  X509* cert = NULL;
  int fd;
  bool ok = false;

  if (snprintf(path, sizeof(path), "%s/%s", dir, SD_TLS_IDENTITY_FILE) >=
      (int)sizeof(path)) {
    snprintf(errmsg, errlen, "identity path too long");
    return false;
  }

  /* NO mkdir - the description block says why.  Absent means the installer
     step did not run, and the answer is to run it, not to make a directory
     here with whatever ACL the parent hands down. */
  if (lstat(dir, &st) != 0) {
    snprintf(errmsg, errlen,
             "%s is missing: the installer creates it (secure-tls.ps1); "
             "until it exists no API connection is accepted", dir);
    return false;
  }
  if (!private_to_me(dir, &st, true, errmsg, errlen))
    return false;

  fd = open(path, O_RDONLY | O_NOFOLLOW);
  if (fd < 0 && errno == ENOENT) {
    if (!create_identity(path, &pkey, &cert, errmsg, errlen))
      return false;
  } else if (fd < 0) {
    snprintf(errmsg, errlen, "cannot open %.300s: %s", path, strerror(errno));
    return false;
  } else {
    FILE* fp;

    if (fstat(fd, &st) != 0 ||
        !private_to_me(path, &st, false, errmsg, errlen)) {
      close(fd);
      return false;
    }
    fp = fdopen(fd, "r");
    if (fp == NULL) {
      close(fd);
      snprintf(errmsg, errlen, "cannot read %.300s", path);
      return false;
    }
    pkey = PEM_read_PrivateKey(fp, NULL, NULL, NULL);
    cert = PEM_read_X509(fp, NULL, NULL, NULL);
    fclose(fp);
    if (pkey == NULL || cert == NULL) {
      sd_tls_error_text("cannot parse the server identity", errmsg, errlen);
      goto done;
    }
  }

  if (SSL_CTX_use_certificate(ctx, cert) != 1 ||
      SSL_CTX_use_PrivateKey(ctx, pkey) != 1 ||
      SSL_CTX_check_private_key(ctx) != 1) {
    sd_tls_error_text("the server identity does not load", errmsg, errlen);
    goto done;
  }
  ok = true;

done:
  EVP_PKEY_free(pkey);
  X509_free(cert);
  return ok;
}

/* ======================================================================
   drop_privilege()  -  NOT ON THIS PLATFORM

   Linux has "root -> nobody, for good" here: getpwnam("nobody"), setgroups,
   setgid, setuid, then a check that root cannot be regained, then
   PR_SET_NO_NEW_PRIVS.  None of it exists under the MSYS2 runtime in a
   useful form - Cygwin's setuid() can only switch to a user it holds a
   token for, and a LocalSystem process fork()ed by the service has none to
   switch to.  The relay therefore keeps the token it started with.  The
   description block at the top records what that costs.                  */

/* ======================================================================
   relay()  -  copy both ways until either side ends                      */

static bool ssl_write_all(SSL* ssl, const char* p, int len) {
  while (len > 0) {
    int n = SSL_write(ssl, p, len);
    int e;

    if (n > 0) {
      p += n;
      len -= n;
      continue;
    }
    e = SSL_get_error(ssl, n);
    if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE)
      continue;
    if (e == SSL_ERROR_SYSCALL && errno == EINTR)
      continue;
    return false;
  }
  return true;
}

static void relay(SSL* ssl, int net_fd, int app_fd) {
  char buf[RELAY_BUFFER];

  for (;;) {
    struct pollfd p[2];

    p[0].fd = net_fd;
    p[0].events = POLLIN;
    p[0].revents = 0;
    p[1].fd = app_fd;
    p[1].events = POLLIN;
    p[1].revents = 0;

    /* Decrypted bytes OpenSSL already holds are invisible to poll(). */
    if (SSL_pending(ssl) > 0) {
      p[0].revents = POLLIN;
    } else if (poll(p, 2, -1) < 0) {
      if (errno == EINTR)
        continue;
      return;
    }

    if (p[0].revents & (POLLIN | POLLHUP | POLLERR)) {
      int n = SSL_read(ssl, buf, sizeof(buf));
      if (n <= 0) {
        int e = SSL_get_error(ssl, n);
        if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE)
          continue;
        return;
      }
      if (!write_all(app_fd, buf, (size_t)n))
        return;
    }

    if (p[1].revents & (POLLIN | POLLHUP | POLLERR)) {
      ssize_t n = read(app_fd, buf, sizeof(buf));
      if (n < 0 && errno == EINTR)
        continue;
      if (n <= 0)
        return;
      if (!ssl_write_all(ssl, buf, (int)n))
        return;
    }
  }
}

static void relay_process(const char* dir, int timeout_ms, int app_fd) {
  char err[512];
  SSL_CTX* ctx;
  SSL* ssl;
  unsigned char binding[SD_TLS_BINDING_BYTES];
  const int net_fd = 0;

  signal(SIGPIPE, SIG_IGN);
  signal(SIGCHLD, SIG_DFL);
  signal(SIGHUP, SIG_DFL);
  signal(SIGTERM, SIG_DFL);
  signal(SIGINT, SIG_DFL);
  close(1);                        /* the same connection as 0 */

  ctx = SSL_CTX_new(TLS_server_method());
  if (ctx == NULL || !sd_tls_restrict_ctx(ctx)) {
    sd_tls_error_text("cannot set up TLS", err, sizeof(err));
    syslog(LOG_ERR, "SD API TLS: %s", err);
    _exit(RELAY_EXIT_IDENTITY);
  }
  /* No resumption: every session is a full handshake with its own binding. */
  SSL_CTX_set_num_tickets(ctx, 0);
  SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_OFF);

  if (!load_identity(ctx, dir, err, sizeof(err))) {
    syslog(LOG_ERR, "SD API TLS: %s", err);
    _exit(RELAY_EXIT_IDENTITY);
  }

  /* Linux drops to nobody here (RELAY_EXIT_PRIVILEGE); see drop_privilege()
     above for why this port cannot.  The exit code is kept so the numbers
     mean the same thing on both. */

  ssl = SSL_new(ctx);
  if (ssl == NULL || SSL_set_fd(ssl, net_fd) != 1) {
    sd_tls_error_text("cannot set up TLS", err, sizeof(err));
    syslog(LOG_ERR, "SD API TLS: %s", err);
    _exit(RELAY_EXIT_HANDSHAKE);
  }

  if (!sd_tls_handshake(ssl, net_fd, timeout_ms, true, err, sizeof(err))) {
    syslog(LOG_INFO, "SD API TLS: connection refused: %s", err);
    _exit(RELAY_EXIT_HANDSHAKE);
  }

  if (!sd_tls_export_binding(ssl, binding) ||
      !write_all(app_fd, binding, sizeof(binding))) {
    syslog(LOG_ERR, "SD API TLS: cannot hand over the channel binding");
    _exit(RELAY_EXIT_BINDING);
  }

  relay(ssl, net_fd, app_fd);
  (void)SSL_shutdown(ssl);
  _exit(0);
}

/* ======================================================================
   sd_tls_relay_start()                                                   */

int sd_tls_relay_start(const char* identity_dir, int timeout_ms,
                       char* errmsg, size_t errlen) {
  int sp[2];
  pid_t pid;
  size_t got = 0;

  /* STDERR MAY BE THE CONNECTION TOO.  sdclient@.service sets only
     StandardInput=socket, and systemd's StandardOutput/StandardError default
     to inherit - so descriptor 2 is the client's socket.  Left there, anything
     either process wrote to stderr would reach the client as plaintext in the
     middle of the TLS stream, and sd would hold the connection open after the
     relay ended.  Pointed at /dev/null before the fork, for both processes;
     the relay reports through syslog. */
  {
    struct stat s0;
    struct stat s2;

    if (fstat(0, &s0) == 0 && fstat(2, &s2) == 0 && s0.st_dev == s2.st_dev &&
        s0.st_ino == s2.st_ino) {
      int null_fd = open("/dev/null", O_WRONLY);
      if (null_fd < 0 || dup2(null_fd, 2) < 0) {
        snprintf(errmsg, errlen, "cannot detach stderr from the connection");
        return false;
      }
      if (null_fd != 2)
        close(null_fd);
    }
  }

  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0) {
    snprintf(errmsg, errlen, "socketpair: %s", strerror(errno));
    return false;
  }

  pid = fork();
  if (pid < 0) {
    snprintf(errmsg, errlen, "fork: %s", strerror(errno));
    close(sp[0]);
    close(sp[1]);
    return false;
  }
  if (pid == 0) {
    close(sp[0]);
    relay_process(identity_dir, timeout_ms, sp[1]);
    _exit(1);                      /* not reached */
  }

  /* sd: its connection becomes the socketpair.  Closing its copies of the
     network descriptor matters - when the relay ends, the client must see
     the connection close, not a socket sd still holds open. */
  close(sp[1]);
  if (dup2(sp[0], 0) < 0 || dup2(sp[0], 1) < 0) {
    snprintf(errmsg, errlen, "dup2: %s", strerror(errno));
    return false;
  }
  if (sp[0] > 1)
    close(sp[0]);

  /* The binding is the relay's first 32 bytes.  End of file here is every
     refusal: no identity, a failed handshake, a client that never spoke. */
  while (got < SD_TLS_BINDING_BYTES) {
    struct pollfd p;
    ssize_t n;
    int pr;

    p.fd = 0;
    p.events = POLLIN;
    p.revents = 0;
    pr = poll(&p, 1, timeout_ms + 5000);
    if (pr < 0 && errno == EINTR)
      continue;
    if (pr <= 0) {
      snprintf(errmsg, errlen, "TLS relay did not answer");
      return false;
    }
    n = read(0, server_binding + got, SD_TLS_BINDING_BYTES - got);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0) {
      snprintf(errmsg, errlen,
               "TLS relay ended before the session started (see syslog)");
      return false;
    }
    got += (size_t)n;
  }

  have_binding = true;
  return true;
}

const unsigned char* sd_tls_server_binding(void) {
  return have_binding ? server_binding : NULL;
}

/* END-CODE */
