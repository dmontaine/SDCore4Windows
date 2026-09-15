/* SD_TLS.C
 * TLS for the SD API transport: shared settings, the handshake, the channel
 * binding, and the client.
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
 * 15 Sep 26 Windows port - adopted from SD Core for Linux S.19 unchanged in
 *           substance: this file is POSIX and the MSYS2 runtime has all of it
 *           (poll, fcntl, pthread_sigmask, sigtimedwait, clock_gettime).  It
 *           is linked into sd.exe only.  The NATIVE client library's copy is
 *           gplsrc/sdclilib/sd_tls.c - Winsock, no signals.  RELEASE_1.1 41.
 * 15 Sep 26 dm S.19: created.  See sd_tls.h.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * THE CLIENT DOES NOT VERIFY THE SERVER'S CERTIFICATE, AND THAT IS NOT WHAT
 * AUTHENTICATES THE SERVER.  The SCRAM login that follows is bound to this TLS
 * session: the client's proof covers the tls-exporter value its own end
 * computed, and the server's signature can be produced only by a holder of
 * the account's ServerKey.  A man in the middle has two TLS sessions with two
 * different exporter values, so the server refuses the relayed proof and the
 * client refuses the relayed signature - and the client sends no request
 * until the signature has verified.
 *
 * WHAT THAT DOES NOT COVER, recorded in PROJECT_STATUS S.19: a man in the
 * middle who poses as the server can collect a client proof and try to crack
 * the password offline.  Pinning the server's key on first use would close
 * that, which is why the server's identity is persistent (sd_tlssrv.c).
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
#include <time.h>

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

struct SD_TLS_CLIENT {
  SSL_CTX* ctx;
  SSL* ssl;
  int fd;
  unsigned char binding[SD_TLS_BINDING_BYTES];
};

static long now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long)ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

/* ======================================================================
   sd_tls_error_text()  -  "what: <first OpenSSL error>", queue cleared    */

void sd_tls_error_text(const char* what, char* errmsg, size_t errlen) {
  char detail[256];
  unsigned long e = ERR_get_error();

  if (errmsg == NULL || errlen == 0)
    return;
  if (e != 0) {
    ERR_error_string_n(e, detail, sizeof(detail));
    snprintf(errmsg, errlen, "%s: %s", what, detail);
  } else {
    snprintf(errmsg, errlen, "%s", what);
  }
  ERR_clear_error();
}

/* ======================================================================
   sd_tls_restrict_ctx()  -  TLS 1.3 only, both ends                      */

int sd_tls_restrict_ctx(void* vctx) {
  SSL_CTX* ctx = (SSL_CTX*)vctx;

  /* 1.3 ONLY.  Nothing that speaks this protocol predates this change, so
     there is no older client to keep, and 1.3 is where the exporter RFC 9266
     binds to is defined without further conditions. */
  if (!SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION))
    return false;
  if (!SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION))
    return false;
  return true;
}

/* ======================================================================
   sd_tls_handshake()  -  SSL_accept/SSL_connect with a deadline

   A peer that connects and says nothing must not hold the process for ever:
   the descriptor is non-blocking for the handshake and restored after.   */

int sd_tls_handshake(void* vssl, int fd, int timeout_ms, int server,
                     char* errmsg, size_t errlen) {
  SSL* ssl = (SSL*)vssl;
  int flags = fcntl(fd, F_GETFL);
  long deadline = now_ms() + timeout_ms;
  bool ok = false;

  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    snprintf(errmsg, errlen, "cannot make the connection non-blocking: %s",
             strerror(errno));
    return false;
  }

  for (;;) {
    int r = server ? SSL_accept(ssl) : SSL_connect(ssl);
    int e;
    struct pollfd p;
    long left;
    int pr;

    if (r == 1) {
      ok = true;
      break;
    }

    e = SSL_get_error(ssl, r);
    if (e == SSL_ERROR_WANT_READ) {
      p.events = POLLIN;
    } else if (e == SSL_ERROR_WANT_WRITE) {
      p.events = POLLOUT;
    } else if (e == SSL_ERROR_SYSCALL && ERR_peek_error() == 0) {
      snprintf(errmsg, errlen, "TLS handshake: connection closed by peer");
      break;
    } else {
      sd_tls_error_text("TLS handshake", errmsg, errlen);
      break;
    }

    left = deadline - now_ms();
    if (left <= 0) {
      snprintf(errmsg, errlen, "TLS handshake: no answer within %d ms",
               timeout_ms);
      break;
    }
    p.fd = fd;
    p.revents = 0;
    pr = poll(&p, 1, (int)left);
    if (pr < 0 && errno != EINTR) {
      snprintf(errmsg, errlen, "TLS handshake: poll failed: %s",
               strerror(errno));
      break;
    }
    if (pr == 0) {
      snprintf(errmsg, errlen, "TLS handshake: no answer within %d ms",
               timeout_ms);
      break;
    }
  }

  (void)fcntl(fd, F_SETFL, flags);
  return ok;
}

/* ======================================================================
   sd_tls_export_binding()  -  RFC 9266 tls-exporter, 32 bytes            */

int sd_tls_export_binding(void* vssl, unsigned char* out) {
  SSL* ssl = (SSL*)vssl;

  if (SSL_version(ssl) != TLS1_3_VERSION)
    return false;
  return SSL_export_keying_material(ssl, out, SD_TLS_BINDING_BYTES,
                                    SD_TLS_BINDING_LABEL,
                                    strlen(SD_TLS_BINDING_LABEL),
                                    NULL, 0, 0) == 1;
}

/* ======================================================================
   sd_tls_cbind_attr()  -  base64(gs2-header + binding)

   The value of SCRAM's c= attribute (RFC 5802 section 7) for this binding.
   Both ends compute it; the server compares the client's copy with its own. */

char* sd_tls_cbind_attr(const unsigned char* binding) {
  unsigned char raw[sizeof(SD_TLS_GS2_HEADER) - 1 + SD_TLS_BINDING_BYTES];
  size_t hdr = sizeof(SD_TLS_GS2_HEADER) - 1;
  char* out;

  if (binding == NULL)
    return NULL;
  memcpy(raw, SD_TLS_GS2_HEADER, hdr);
  memcpy(raw + hdr, binding, SD_TLS_BINDING_BYTES);

  out = malloc(((sizeof(raw) + 2) / 3) * 4 + 1);
  if (out == NULL)
    return NULL;
  EVP_EncodeBlock((unsigned char*)out, raw, (int)sizeof(raw));
  return out;
}

/* ======================================================================
   Client                                                                 */

SD_TLS_CLIENT* sd_tls_client_start(int fd, int timeout_ms,
                                   char* errmsg, size_t errlen) {
  SD_TLS_CLIENT* c = calloc(1, sizeof(*c));

  if (c == NULL) {
    snprintf(errmsg, errlen, "out of memory");
    return NULL;
  }
  c->fd = fd;

  c->ctx = SSL_CTX_new(TLS_client_method());
  if (c->ctx == NULL || !sd_tls_restrict_ctx(c->ctx)) {
    sd_tls_error_text("cannot set up TLS", errmsg, errlen);
    goto fail;
  }

  /* NOT VERIFIED, DELIBERATELY - see the description block above.  The
     server's certificate is self-signed and generated at its first
     connection; the SCRAM exchange bound to this session is what proves
     which server this is. */
  SSL_CTX_set_verify(c->ctx, SSL_VERIFY_NONE, NULL);

  c->ssl = SSL_new(c->ctx);
  if (c->ssl == NULL || SSL_set_fd(c->ssl, fd) != 1) {
    sd_tls_error_text("cannot set up TLS", errmsg, errlen);
    goto fail;
  }

  if (!sd_tls_handshake(c->ssl, fd, timeout_ms, false, errmsg, errlen))
    goto fail;

  if (!sd_tls_export_binding(c->ssl, c->binding)) {
    sd_tls_error_text("cannot derive the channel binding", errmsg, errlen);
    goto fail;
  }

  return c;

fail:
  if (c->ssl != NULL)
    SSL_free(c->ssl);
  if (c->ctx != NULL)
    SSL_CTX_free(c->ctx);
  free(c);
  return NULL;
}

/* > 0 bytes read, 0 the server closed the session, < 0 an error */
int sd_tls_client_read(SD_TLS_CLIENT* c, void* buf, int len) {
  for (;;) {
    int n = SSL_read(c->ssl, buf, len);
    int e;

    if (n > 0)
      return n;
    e = SSL_get_error(c->ssl, n);
    if (e == SSL_ERROR_ZERO_RETURN)
      return 0;
    if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE)
      continue;
    if (e == SSL_ERROR_SYSCALL && errno == EINTR)
      continue;
    ERR_clear_error();
    return -1;
  }
}

/* Bytes already decrypted and held by OpenSSL, which select() and poll() on
   the descriptor cannot see.  A caller that waits for readability must check
   this first, or it waits for data it already has. */
int sd_tls_client_pending(SD_TLS_CLIENT* c) {
  return SSL_pending(c->ssl);
}

/* The whole buffer (non-zero), or 0.

   SIGPIPE IS HELD OFF FOR THE WRITE.  SSL_write() uses write(), which on a
   connection the peer has closed raises SIGPIPE and ends the process -
   WRITE.SOCKET's plain path uses MSG_NOSIGNAL for the same reason (op_skt.c,
   issue #89).  A SIGPIPE this write raised is consumed; one that was already
   pending is left alone. */
int sd_tls_client_write(SD_TLS_CLIENT* c, const void* buf, int len) {
  const char* p = buf;
  sigset_t pipe_only;
  sigset_t old_mask;
  sigset_t pending;
  bool was_pending;
  int ok = 1;

  sigemptyset(&pipe_only);
  sigaddset(&pipe_only, SIGPIPE);
  sigpending(&pending);
  was_pending = sigismember(&pending, SIGPIPE) == 1;
  pthread_sigmask(SIG_BLOCK, &pipe_only, &old_mask);

  while (len > 0) {
    int n = SSL_write(c->ssl, p, len);
    int e;

    if (n > 0) {
      p += n;
      len -= n;
      continue;
    }
    e = SSL_get_error(c->ssl, n);
    if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE)
      continue;
    if (e == SSL_ERROR_SYSCALL && errno == EINTR)
      continue;
    ERR_clear_error();
    ok = 0;
    break;
  }

  if (!ok && !was_pending) {
    struct timespec no_wait = {0, 0};
    (void)sigtimedwait(&pipe_only, NULL, &no_wait);
  }
  pthread_sigmask(SIG_SETMASK, &old_mask, NULL);
  return ok;
}

const unsigned char* sd_tls_client_binding(SD_TLS_CLIENT* c) {
  return c->binding;
}

int sd_tls_client_peer_sha256(SD_TLS_CLIENT* c, unsigned char* out) {
  X509* cert = SSL_get1_peer_certificate(c->ssl);
  unsigned int n = 0;
  bool ok;

  if (cert == NULL)
    return false;
  ok = X509_digest(cert, EVP_sha256(), out, &n) == 1 && n == 32;
  X509_free(cert);
  return ok;
}

const char* sd_tls_client_version(SD_TLS_CLIENT* c) {
  return SSL_get_version(c->ssl);
}

/* Sends close_notify and frees; the caller closes the descriptor. */
void sd_tls_client_end(SD_TLS_CLIENT* c) {
  if (c == NULL)
    return;
  (void)SSL_shutdown(c->ssl);
  SSL_free(c->ssl);
  SSL_CTX_free(c->ctx);
  ERR_clear_error();
  free(c);
}

/* END-CODE */
