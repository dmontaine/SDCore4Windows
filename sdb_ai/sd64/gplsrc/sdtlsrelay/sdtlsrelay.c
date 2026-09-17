/* SDTLSRELAY.C
 * The API's TLS relay, as a NATIVE Windows program.
 * Copyright (c) String Database
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
 * 16 Sep 26 Windows port - written for RELEASE_1.1 43.  Replaces the fork()ed
 *           relay_process() in sd_tlssrv.c, which parsed an unauthenticated
 *           peer's bytes as LocalSystem.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * ONE PROCESS PER CONNECTION, THE LINUX SHAPE.  sd (LocalSystem, in the
 * session process sdwind forked for this connection) starts this program with
 * the token of a bare local account - no groups, every privilege removed,
 * integrity Low - and exactly two inherited handles: the accepted connection,
 * and one end of the socketpair sd keeps as its own descriptors 0 and 1.  The
 * relay owns the network socket and the TLS state; sd's I/O code never
 * changes.  When either side ends, the other is closed and the process exits.
 *
 *   sdtlsrelay.exe <net handle> <sp handle> <timeout ms>
 *
 * WHY NATIVE AND NOT THE MSYS2 RUNTIME sd IS BUILT WITH, MEASURED 16 Sep
 * 2026 (PROJECT_STATUS.md HANDOFF 78's box): an MSYS2 process at Low cannot
 * start while a Medium-or-higher process of the same runtime - sd - holds the
 * runtime's object directory (0xC0000142), and a spawned Cygwin child can
 * adopt neither an inherited socket (EINVAL) nor an inherited pipe (EBADF) as
 * a Cygwin descriptor.  So the socket, the channel to sd and the relay loop
 * are all Winsock, and OpenSSL is the UCRT64 static build the client DLL
 * already links (gplsrc/sdclilib/Makefile).  Nothing of the MSYS2 runtime is
 * in this process - stage.py's import check says so on every build.
 *
 * THE TWO SOCKETS ARE NON-BLOCKING AND CANNOT BE MADE BLOCKING.  Cygwin sets
 * every socket it creates non-blocking at the Winsock level and emulates
 * blocking itself; FIONBIO 0 on an inherited one answers WSAEOPNOTSUPP
 * (gplbld/probe-cygsock.c).  The accepted connection and the socketpair end
 * are both Cygwin's, so every wait here is WSAPoll, and every OpenSSL call is
 * written for WANT_READ / WANT_WRITE.  gplbld/probe-relaysp.c measured the
 * loop below minus TLS: both directions, 256 KiB through a full send buffer,
 * EOF propagated.
 *
 * THE IDENTITY ARRIVES OVER THE SOCKETPAIR, NOT FROM THE FILE.  The file is
 * readable by SYSTEM and Administrators only (win32tls.c), which this process
 * is not.  Linux reads it as root and then drops; a spawn cannot inherit an
 * open descriptor the way a fork does, so sd sends the PEM bytes as the first
 * frame - see sd_tls.h for the protocol - and they are wiped here as soon as
 * OpenSSL has them.  Nothing is written to disk and nothing is logged: the
 * process has nowhere to log TO at Low, so a failure before the handshake is
 * reported back to sd in the status frame (sd puts it in syslog), and a
 * failure after it is an exit sd sees as end of file.
 *
 * END-DESCRIPTION
 */

/* winsock2.h/windows.h BEFORE the OpenSSL headers: wincrypt.h defines
   X509_NAME and friends, and openssl/types.h undefines them - in that order
   only.  No SD header is included, so win32tls.c's rule is kept. */
#include <winsock2.h>
#include <windows.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#include "../sd_tls.h"                /* the wire constants and the protocol */

#define RELAY_BUFFER 16384

static SOCKET net_sock = INVALID_SOCKET;
static SOCKET sp_sock = INVALID_SOCKET;

/* ======================================================================
   Waiting on a non-blocking socket                                       */

static ULONGLONG now_ms(void) { return GetTickCount64(); }

/* WSAPoll for events on s, until deadline (0 = for ever).  Returns 1 ready,
   0 timed out, -1 failed. */
static int wait_for(SOCKET s, SHORT events, ULONGLONG deadline) {
  WSAPOLLFD p;
  int timeout, r;

  p.fd = s;
  p.events = events;
  p.revents = 0;
  if (deadline == 0) {
    timeout = -1;
  } else {
    ULONGLONG now = now_ms();
    if (now >= deadline)
      return 0;
    timeout = (int)(deadline - now);
  }
  r = WSAPoll(&p, 1, timeout);
  if (r < 0)
    return -1;
  if (r == 0)
    return 0;
  return 1;
}

/* recv exactly len bytes, or fail.  0 for a clean EOF before len, -1 error. */
static int recv_all(SOCKET s, unsigned char* buf, size_t len,
                    ULONGLONG deadline) {
  size_t got = 0;
  while (got < len) {
    int n = recv(s, (char*)buf + got, (int)(len - got), 0);
    if (n > 0) {
      got += (size_t)n;
      continue;
    }
    if (n == 0)
      return 0;
    if (WSAGetLastError() != WSAEWOULDBLOCK)
      return -1;
    if (wait_for(s, POLLRDNORM, deadline) != 1)
      return -1;
  }
  return 1;
}

/* send the whole buffer, waiting for room as needed. */
static int send_all(SOCKET s, const unsigned char* buf, size_t len) {
  size_t sent = 0;
  while (sent < len) {
    int n = send(s, (const char*)buf + sent, (int)(len - sent), 0);
    if (n >= 0) {
      sent += (size_t)n;
      continue;
    }
    if (WSAGetLastError() != WSAEWOULDBLOCK)
      return 0;
    if (wait_for(s, POLLWRNORM, 0) != 1)
      return 0;
  }
  return 1;
}

/* ======================================================================
   The status frame back to sd (sd_tls.h)                                 */

static void tls_error_text(const char* what, char* errmsg, size_t errlen) {
  char detail[256];
  unsigned long e = ERR_get_error();

  if (e != 0) {
    ERR_error_string_n(e, detail, sizeof(detail));
    snprintf(errmsg, errlen, "%s: %s", what, detail);
  } else {
    snprintf(errmsg, errlen, "%s", what);
  }
  ERR_clear_error();
}

/* Report a refusal to sd and exit with the same number.  Never returns. */
static void refuse(int status, const char* text) {
  unsigned char hdr[3];
  size_t len = strlen(text);

  if (len > 0xFFFF)
    len = 0xFFFF;
  hdr[0] = (unsigned char)status;
  hdr[1] = (unsigned char)(len >> 8);
  hdr[2] = (unsigned char)(len & 0xFF);
  if (sp_sock != INVALID_SOCKET) {
    (void)send_all(sp_sock, hdr, sizeof(hdr));
    (void)send_all(sp_sock, (const unsigned char*)text, len);
    (void)shutdown(sp_sock, SD_BOTH);
    closesocket(sp_sock);
  }
  if (net_sock != INVALID_SOCKET)
    closesocket(net_sock);
  ExitProcess((UINT)status);
}

/* ======================================================================
   The identity: PEM bytes from sd, parsed from memory, then wiped         */

static int load_identity(SSL_CTX* ctx, ULONGLONG deadline, char* err,
                         size_t errlen) {
  unsigned char lenbuf[4];
  uint32_t len;
  unsigned char* pem;
  BIO* bio;
  EVP_PKEY* pkey = NULL;
  X509* cert = NULL;
  int ok = 0;

  if (recv_all(sp_sock, lenbuf, sizeof(lenbuf), deadline) != 1) {
    snprintf(err, errlen, "sd did not send the server identity");
    return 0;
  }
  len = ((uint32_t)lenbuf[0] << 24) | ((uint32_t)lenbuf[1] << 16) |
        ((uint32_t)lenbuf[2] << 8) | (uint32_t)lenbuf[3];
  if (len == 0 || len > SD_RELAY_IDENTITY_MAX) {
    snprintf(err, errlen, "server identity frame of %lu bytes refused",
             (unsigned long)len);
    return 0;
  }
  pem = malloc(len);
  if (pem == NULL) {
    snprintf(err, errlen, "out of memory");
    return 0;
  }
  if (recv_all(sp_sock, pem, len, deadline) != 1) {
    snprintf(err, errlen, "sd did not send the whole server identity");
    free(pem);
    return 0;
  }

  bio = BIO_new_mem_buf(pem, (int)len);
  if (bio != NULL) {
    pkey = PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL);
    cert = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    BIO_free(bio);
  }
  OPENSSL_cleanse(pem, len);          /* OpenSSL holds the key now */
  free(pem);

  if (pkey == NULL || cert == NULL) {
    tls_error_text("cannot parse the server identity", err, errlen);
  } else if (SSL_CTX_use_certificate(ctx, cert) != 1 ||
             SSL_CTX_use_PrivateKey(ctx, pkey) != 1 ||
             SSL_CTX_check_private_key(ctx) != 1) {
    tls_error_text("the server identity does not load", err, errlen);
  } else {
    ok = 1;
  }
  EVP_PKEY_free(pkey);
  X509_free(cert);
  return ok;
}

/* ======================================================================
   The handshake, with a deadline (sd_tls.c's shape, WSAPoll for poll)    */

static int handshake(SSL* ssl, int timeout_ms, char* err, size_t errlen) {
  ULONGLONG deadline = now_ms() + (ULONGLONG)timeout_ms;

  for (;;) {
    int r = SSL_accept(ssl);
    int e;
    SHORT events;

    if (r == 1)
      return 1;
    e = SSL_get_error(ssl, r);
    if (e == SSL_ERROR_WANT_READ) {
      events = POLLRDNORM;
    } else if (e == SSL_ERROR_WANT_WRITE) {
      events = POLLWRNORM;
    } else if (e == SSL_ERROR_SYSCALL && ERR_peek_error() == 0) {
      snprintf(err, errlen, "TLS handshake: connection closed by peer");
      return 0;
    } else {
      tls_error_text("TLS handshake", err, errlen);
      return 0;
    }
    switch (wait_for(net_sock, events, deadline)) {
      case 1:
        break;
      case 0:
        snprintf(err, errlen, "TLS handshake: no answer within %d ms",
                 timeout_ms);
        return 0;
      default:
        snprintf(err, errlen, "TLS handshake: WSAPoll failed (%d)",
                 WSAGetLastError());
        return 0;
    }
  }
}

/* ======================================================================
   relay()  -  copy both ways until either side ends                      */

/* SSL_write the whole buffer over the non-blocking connection. */
static int ssl_write_all(SSL* ssl, const unsigned char* p, int len) {
  while (len > 0) {
    int n = SSL_write(ssl, p, len);
    int e;

    if (n > 0) {
      p += n;
      len -= n;
      continue;
    }
    e = SSL_get_error(ssl, n);
    if (e == SSL_ERROR_WANT_WRITE) {
      if (wait_for(net_sock, POLLWRNORM, 0) != 1)
        return 0;
    } else if (e == SSL_ERROR_WANT_READ) {
      if (wait_for(net_sock, POLLRDNORM, 0) != 1)
        return 0;
    } else {
      return 0;
    }
  }
  return 1;
}

static void relay(SSL* ssl) {
  unsigned char buf[RELAY_BUFFER];

  for (;;) {
    WSAPOLLFD p[2];

    p[0].fd = net_sock;
    p[0].events = POLLRDNORM;
    p[0].revents = 0;
    p[1].fd = sp_sock;
    p[1].events = POLLRDNORM;
    p[1].revents = 0;

    /* Decrypted bytes OpenSSL already holds are invisible to WSAPoll. */
    if (SSL_pending(ssl) > 0) {
      p[0].revents = POLLRDNORM;
    } else if (WSAPoll(p, 2, -1) < 0) {
      return;
    }

    if (p[0].revents & (POLLRDNORM | POLLHUP | POLLERR)) {
      int n = SSL_read(ssl, buf, (int)sizeof(buf));
      if (n <= 0) {
        int e = SSL_get_error(ssl, n);
        if (e != SSL_ERROR_WANT_READ && e != SSL_ERROR_WANT_WRITE)
          return;                      /* close_notify, reset, or a fault */
      } else if (!send_all(sp_sock, buf, (size_t)n)) {
        return;
      }
    }

    if (p[1].revents & (POLLRDNORM | POLLHUP | POLLERR)) {
      int n = recv(sp_sock, (char*)buf, (int)sizeof(buf), 0);
      if (n == 0)
        return;                        /* sd ended the session */
      if (n < 0) {
        if (WSAGetLastError() == WSAEWOULDBLOCK)
          continue;
        return;
      }
      if (!ssl_write_all(ssl, buf, n))
        return;
    }
  }
}

/* ====================================================================== */

int main(int argc, char* argv[]) {
  WSADATA wsa;
  char err[512];
  SSL_CTX* ctx;
  SSL* ssl;
  int timeout_ms;
  int type, tl;
  unsigned char preamble[1 + SD_TLS_BINDING_BYTES];

  if (argc != 4) {
    fprintf(stderr, "sdtlsrelay is started by sd for each API connection; "
                    "it is not a command\n");
    return SD_RELAY_EXIT_USAGE;
  }
  net_sock = (SOCKET)(uintptr_t)strtoull(argv[1], NULL, 10);
  sp_sock = (SOCKET)(uintptr_t)strtoull(argv[2], NULL, 10);
  timeout_ms = atoi(argv[3]);
  if (timeout_ms <= 0)
    timeout_ms = SD_TLS_HANDSHAKE_MS;

  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
    return SD_RELAY_EXIT_USAGE;

  /* Both handles must be sockets, or nothing below can be trusted - and a
     wrong handle is sd's bug, so say so on the channel if that one works. */
  tl = sizeof(type);
  if (getsockopt(sp_sock, SOL_SOCKET, SO_TYPE, (char*)&type, &tl) != 0) {
    sp_sock = INVALID_SOCKET;
    refuse(SD_RELAY_EXIT_USAGE, "the socketpair handle is not a socket");
  }
  tl = sizeof(type);
  if (getsockopt(net_sock, SOL_SOCKET, SO_TYPE, (char*)&type, &tl) != 0)
    refuse(SD_RELAY_EXIT_USAGE, "the connection handle is not a socket");

  /* Non-blocking, whoever made them.  sd's sockets already are and refuse
     to be anything else (WSAEOPNOTSUPP, ignored here); a harness that hands
     over plain blocking sockets - test-tlsrelay-units.py - would otherwise
     defeat every deadline below, because recv() would sleep in the kernel
     instead of answering WSAEWOULDBLOCK to a WSAPoll'd loop. */
  {
    u_long nb = 1;
    (void)ioctlsocket(net_sock, FIONBIO, &nb);
    nb = 1;
    (void)ioctlsocket(sp_sock, FIONBIO, &nb);
  }

  ctx = SSL_CTX_new(TLS_server_method());
  if (ctx == NULL ||
      !SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION) ||
      !SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION)) {
    tls_error_text("cannot set up TLS", err, sizeof(err));
    refuse(SD_RELAY_EXIT_IDENTITY, err);
  }
  /* No resumption: every session is a full handshake with its own binding. */
  SSL_CTX_set_num_tickets(ctx, 0);
  SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_OFF);
  /* Non-blocking writes: a retried SSL_write may be shorter and may come
     from a different address once the caller's buffer has moved on. */
  SSL_CTX_set_mode(ctx, SSL_MODE_ENABLE_PARTIAL_WRITE |
                            SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);

  if (!load_identity(ctx, now_ms() + (ULONGLONG)timeout_ms, err, sizeof(err)))
    refuse(SD_RELAY_EXIT_IDENTITY, err);

  ssl = SSL_new(ctx);
  if (ssl == NULL || SSL_set_fd(ssl, (int)net_sock) != 1) {
    tls_error_text("cannot set up TLS", err, sizeof(err));
    refuse(SD_RELAY_EXIT_HANDSHAKE, err);
  }

  if (!handshake(ssl, timeout_ms, err, sizeof(err)))
    refuse(SD_RELAY_EXIT_HANDSHAKE, err);

  /* RFC 9266 tls-exporter, 32 bytes - the value SCRAM's c= must carry. */
  preamble[0] = SD_RELAY_OK;
  if (SSL_version(ssl) != TLS1_3_VERSION ||
      SSL_export_keying_material(ssl, preamble + 1, SD_TLS_BINDING_BYTES,
                                 SD_TLS_BINDING_LABEL,
                                 strlen(SD_TLS_BINDING_LABEL), NULL, 0,
                                 0) != 1) {
    tls_error_text("cannot derive the channel binding", err, sizeof(err));
    refuse(SD_RELAY_EXIT_BINDING, err);
  }
  if (!send_all(sp_sock, preamble, sizeof(preamble)))
    refuse(SD_RELAY_EXIT_BINDING, "cannot hand over the channel binding");
  OPENSSL_cleanse(preamble, sizeof(preamble));

  relay(ssl);
  (void)SSL_shutdown(ssl);
  SSL_free(ssl);
  SSL_CTX_free(ctx);
  closesocket(net_sock);
  closesocket(sp_sock);
  return 0;
}

/* END-CODE */
