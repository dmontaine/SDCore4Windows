/* SD_TLSSRV.C
 * TLS for the SD API transport: sd's side of the relay.
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
 * 16 Sep 26 Windows port - RELEASE_1.1 43: the relay is no longer fork()ed
 *           here.  It is sdtlsrelay/sdtlsrelay.c, a NATIVE program that
 *           win32relay.c starts as the bare account SD_RELAY_ACCOUNT, every
 *           privilege removed, at Low integrity.  This file keeps what only
 *           LocalSystem can do - read (or create) the identity, mint the
 *           token, spawn - and then reads the binding exactly as before.
 *           relay_process(), relay() and the drop_privilege() note are gone
 *           with the fork.
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
 * client's connection.  On Linux it forks; here it SPAWNS, and the shape is
 * otherwise Linux's:
 *
 *   the relay    sdtlsrelay.exe, per connection, gets the connection and one
 *                end of a socketpair, does the TLS handshake, sends sd the
 *                channel binding, then copies bytes both ways until either
 *                side ends.  It runs as SD_RELAY_ACCOUNT at Low with no
 *                privilege - the Linux "nobody" - so a flaw in the TLS code
 *                hands an attacker a bare account, not LocalSystem.
 *   sd           keeps the other end of the socketpair as descriptors 0 and
 *                1, reads the binding, and carries on exactly as before.
 *
 * WHAT THIS REPLACES.  Until 16 Sep 2026 the relay was fork()ed here and so
 * parsed an unauthenticated peer's bytes with the session's LocalSystem
 * token - "THE RELAY RUNS AS LocalSystem, AND THAT IS A GAP LINUX DOES NOT
 * HAVE", this block used to say.  Windows has no setuid, so the drop is done
 * BEFORE the process exists: sd mints the bare account's token on its own
 * SeTcb, strips it, labels it Low and starts the relay under it
 * (win32relay.c).  Every step of that was measured before it was built -
 * RELEASE_1.1 43 lists the probes.
 *
 * THE IDENTITY is one file, <identity_dir>/api.pem, holding the private key
 * and a self-signed certificate.  One file, written to a temporary name and
 * renamed, so two first connections at once cannot leave a key beside the
 * other's certificate.  It is refused unless the DIRECTORY EXISTS and both it
 * and the file grant access to nobody but SYSTEM and Administrators
 * (win32tls.c).  Nothing here creates the directory: its parent,
 * C:\ProgramData\SD, is writable by every SD user, so a directory made here
 * would inherit their Modify - and one made by them first would be theirs.
 * gplbld/secure-tls.ps1 creates it at install time with the right ACL, the
 * same shape as secure-reclaim.ps1.
 *
 * THE RELAY CANNOT READ THAT FILE, AND MUST NOT BE ABLE TO.  So sd reads it
 * - as LocalSystem, the way Linux's relay reads it as root before dropping -
 * and sends the bytes down the socketpair as the first frame (sd_tls.h).  A
 * spawn cannot inherit an open file the way a fork does, which is why the
 * bytes travel rather than a descriptor.
 *
 * END-DESCRIPTION
 */

#include "sd_tls.h"

#include <stdbool.h>                  /* not from sd_tls.h - see there */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <syslog.h>
#include <unistd.h>

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

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

/* read exactly len bytes from fd 0 within deadline_ms of waiting per byte
   group; false on EOF, error or timeout, with errmsg saying which.        */
static bool read_all_timed(unsigned char* buf, size_t len, int timeout_ms,
                           const char* what, char* errmsg, size_t errlen) {
  size_t got = 0;

  while (got < len) {
    struct pollfd p;
    ssize_t n;
    int pr;

    p.fd = 0;
    p.events = POLLIN;
    p.revents = 0;
    pr = poll(&p, 1, timeout_ms);
    if (pr < 0 && errno == EINTR)
      continue;
    if (pr <= 0) {
      snprintf(errmsg, errlen, "TLS relay did not answer (%s)", what);
      return false;
    }
    n = read(0, buf + got, len - got);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0) {
      snprintf(errmsg, errlen, "TLS relay ended before the session started (%s)",
               what);
      return false;
    }
    got += (size_t)n;
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

static bool create_identity(const char* path, char* errmsg, size_t errlen) {
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
  EVP_PKEY_free(pkey);
  X509_free(cert);
  return ok;
}

/* The identity file's BYTES, checked - the directory and file ACLs, and that
   OpenSSL can parse a key and a certificate out of them, so a corrupt file is
   refused here with a syslog line rather than by a relay that has nowhere to
   say so.  *pem is malloc'd; the caller wipes and frees it.               */
static bool load_identity(const char* dir, unsigned char** pem, size_t* pemlen,
                          char* errmsg, size_t errlen) {
  char path[4096];
  struct stat st;
  int fd;
  unsigned char* buf = NULL;
  size_t got = 0;
  BIO* bio;
  EVP_PKEY* pkey = NULL;
  X509* cert = NULL;
  bool ok = false;

  *pem = NULL;
  *pemlen = 0;

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
    if (!create_identity(path, errmsg, errlen))
      return false;
    fd = open(path, O_RDONLY | O_NOFOLLOW);
  }
  if (fd < 0) {
    snprintf(errmsg, errlen, "cannot open %.300s: %s", path, strerror(errno));
    return false;
  }
  if (fstat(fd, &st) != 0 || !private_to_me(path, &st, false, errmsg, errlen)) {
    close(fd);
    return false;
  }
  if (st.st_size <= 0 || st.st_size > SD_RELAY_IDENTITY_MAX) {
    snprintf(errmsg, errlen, "%.300s is %ld bytes, which is not an identity",
             path, (long)st.st_size);
    close(fd);
    return false;
  }
  buf = malloc((size_t)st.st_size);
  if (buf == NULL) {
    snprintf(errmsg, errlen, "out of memory");
    close(fd);
    return false;
  }
  while (got < (size_t)st.st_size) {
    ssize_t n = read(fd, buf + got, (size_t)st.st_size - got);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      break;
    got += (size_t)n;
  }
  close(fd);
  if (got != (size_t)st.st_size) {
    snprintf(errmsg, errlen, "cannot read %.300s", path);
    goto done;
  }

  bio = BIO_new_mem_buf(buf, (int)got);
  if (bio != NULL) {
    pkey = PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL);
    cert = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    BIO_free(bio);
  }
  if (pkey == NULL || cert == NULL) {
    sd_tls_error_text("cannot parse the server identity", errmsg, errlen);
    goto done;
  }
  if (X509_check_private_key(cert, pkey) != 1) {
    sd_tls_error_text("the server identity's key and certificate do not match",
                      errmsg, errlen);
    goto done;
  }
  ok = true;

done:
  EVP_PKEY_free(pkey);
  X509_free(cert);
  if (ok) {
    *pem = buf;
    *pemlen = got;
  } else if (buf != NULL) {
    OPENSSL_cleanse(buf, got);
    free(buf);
  }
  return ok;
}

/* ======================================================================
   sd_tls_relay_start()                                                   */

/* What a relay exit code means, for the syslog line when the preamble is cut
   short.  The numbers are Linux's (sd_tls.h). */
static const char* relay_exit_text(int code) {
  switch (code) {
    case -1:
      return "still running";
    case 0:
      return "exited 0 without answering";
    case SD_RELAY_EXIT_IDENTITY:
      return "refused the server identity";
    case SD_RELAY_EXIT_HANDSHAKE:
      return "TLS handshake failed";
    case SD_RELAY_EXIT_BINDING:
      return "could not derive the channel binding";
    case SD_RELAY_EXIT_USAGE:
      return "was started wrongly (a bug in sd, not the peer)";
    case (int)0xC0000142:
      return "could not initialise (0xC0000142: a DLL it needs is missing)";
    default:
      return "exited with an unexpected code";
  }
}

int sd_tls_relay_start(const char* identity_dir, int timeout_ms,
                       char* errmsg, size_t errlen) {
  int sp[2];
  unsigned char* pem = NULL;
  size_t pemlen = 0;
  unsigned char hdr[4];
  unsigned char status;
  void* proc = NULL;
  char why[512];

  /* STDERR MAY BE THE CONNECTION TOO.  sdclient@.service sets only
     StandardInput=socket, and systemd's StandardOutput/StandardError default
     to inherit - so descriptor 2 is the client's socket.  Left there, anything
     sd wrote to stderr would reach the client as plaintext in the middle of
     the TLS stream, and sd would hold the connection open after the relay
     ended.  Pointed at /dev/null before the handover.  (Here sdwind dup2s the
     connection to 0 and 1 only, so this is the Linux shape kept for the day
     it is not.) */
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

  /* The identity, read here as LocalSystem - the one thing the relay may not
     do for itself.  Every refusal is syslogged: an operator seeing "no API
     connection is accepted" needs the reason, and the relay has no log. */
  if (!load_identity(identity_dir, &pem, &pemlen, why, sizeof(why))) {
    syslog(LOG_ERR, "SD API TLS: %s", why);
    snprintf(errmsg, errlen, "%s", why);
    return false;
  }

  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0) {
    snprintf(errmsg, errlen, "socketpair: %s", strerror(errno));
    goto fail_pem;
  }

  /* The spawn: token minted, stripped, Low, two handles inherited and no
     other (win32relay.c).  Descriptor 0 is the connection until the dup2
     below. */
  if (!win32_relay_spawn(SD_RELAY_ACCOUNT, 0, sp[1], timeout_ms, &proc, why,
                         sizeof(why))) {
    syslog(LOG_ERR, "SD API TLS: cannot start the relay: %s", why);
    snprintf(errmsg, errlen, "cannot start the TLS relay (see syslog)");
    close(sp[0]);
    close(sp[1]);
    goto fail_pem;
  }

  /* sd: its connection becomes the socketpair.  Closing its copies of the
     network descriptor matters - when the relay ends, the client must see
     the connection close, not a socket sd still holds open. */
  close(sp[1]);
  if (dup2(sp[0], 0) < 0 || dup2(sp[0], 1) < 0) {
    snprintf(errmsg, errlen, "dup2: %s", strerror(errno));
    close(sp[0]);
    (void)win32_relay_exit_code(proc, 0);
    goto fail_pem;
  }
  if (sp[0] > 1)
    close(sp[0]);

  /* First frame, sd -> relay: the identity (sd_tls.h).  Then it is wiped
     here; the relay wipes its copy once OpenSSL holds the key. */
  hdr[0] = (unsigned char)((pemlen >> 24) & 0xFF);
  hdr[1] = (unsigned char)((pemlen >> 16) & 0xFF);
  hdr[2] = (unsigned char)((pemlen >> 8) & 0xFF);
  hdr[3] = (unsigned char)(pemlen & 0xFF);
  if (!write_all(0, hdr, sizeof(hdr)) || !write_all(0, pem, pemlen)) {
    snprintf(errmsg, errlen, "cannot hand the relay the server identity");
    (void)win32_relay_exit_code(proc, 0);
    goto fail_pem;
  }
  OPENSSL_cleanse(pem, pemlen);
  free(pem);
  pem = NULL;

  /* The relay's answer: one status byte, then the binding - Linux's 32-byte
     preamble, one byte later.  Anything but SD_RELAY_OK is a refusal with its
     reason attached, and EOF is a relay that died before it could say. */
  if (!read_all_timed(&status, 1, timeout_ms + 5000, "status", errmsg, errlen)) {
    int code = win32_relay_exit_code(proc, 1000);
    syslog(LOG_INFO, "SD API TLS: relay %s (code %d)", relay_exit_text(code),
           code);
    return false;
  }
  if (status != SD_RELAY_OK) {
    unsigned char lenbuf[2];
    char text[512];
    size_t len;

    text[0] = '\0';
    if (read_all_timed(lenbuf, 2, 2000, "refusal", why, sizeof(why))) {
      len = ((size_t)lenbuf[0] << 8) | lenbuf[1];
      if (len >= sizeof(text))
        len = sizeof(text) - 1;
      if (read_all_timed((unsigned char*)text, len, 2000, "refusal", why,
                         sizeof(why)))
        text[len] = '\0';
      else
        text[0] = '\0';
    }
    (void)win32_relay_exit_code(proc, 1000);
    syslog(LOG_INFO, "SD API TLS: connection refused: %s",
           text[0] ? text : relay_exit_text((int)status));
    snprintf(errmsg, errlen, "%s", text[0] ? text : relay_exit_text((int)status));
    return false;
  }
  if (!read_all_timed(server_binding, SD_TLS_BINDING_BYTES, timeout_ms,
                      "binding", errmsg, errlen)) {
    (void)win32_relay_exit_code(proc, 1000);
    return false;
  }

  /* The relay lives as long as the connection does; sd needs no handle to
     it.  When this process ends, its socketpair end closes and the relay
     ends; when the relay ends, descriptor 0 reads EOF and the session ends. */
  (void)win32_relay_exit_code(proc, 0);
  have_binding = true;
  return true;

fail_pem:
  if (pem != NULL) {
    OPENSSL_cleanse(pem, pemlen);
    free(pem);
  }
  return false;
}

const unsigned char* sd_tls_server_binding(void) {
  return have_binding ? server_binding : NULL;
}

/* END-CODE */
