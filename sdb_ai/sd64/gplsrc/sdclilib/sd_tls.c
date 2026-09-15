/* SD_TLS.C  (native client library)
 * TLS 1.3 for the SD API client, Windows/Winsock side.
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
 * 15 Sep 26 Windows port - written for RELEASE_1.1 41 (Linux S.19).  See
 *           sd_tls.h.
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
 * until the signature has verified.  Same reasoning as the server's sd_tls.c
 * and Linux's; only the I/O primitives differ (Winsock, no signals).
 *
 * WHAT THAT DOES NOT COVER, recorded in RELEASE_1.1 41: a man in the middle
 * who poses as the server can collect a client proof and try to crack the
 * password offline.  Pinning the server's key on first use would close that.
 *
 * OpenSSL is STATIC-LINKED into the DLL (Makefile), so the client stays a
 * single file that can be copied beside an application - the property bcrypt
 * (not a crypto library) was chosen to preserve for SCRAM (VENDORING.md).
 *
 * END-DESCRIPTION
 */

#include "sd_tls.h"

#include <ws2tcpip.h>
#include <stdlib.h>
#include <string.h>

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/ssl.h>

struct SD_TLS_CLIENT {
  SSL_CTX* ctx;
  SSL* ssl;
  SOCKET fd;
  unsigned char binding[SD_TLS_BINDING_BYTES];
};

/* "what: <first OpenSSL error>", queue cleared. */
static void tls_error_text(const char* what, char* errmsg, size_t errlen) {
  char detail[256];
  unsigned long e = ERR_get_error();

  if (errmsg == NULL || errlen == 0)
    return;
  if (e != 0) {
    ERR_error_string_n(e, detail, sizeof(detail));
    _snprintf(errmsg, errlen, "%s: %s", what, detail);
    errmsg[errlen - 1] = '\0';
  } else {
    _snprintf(errmsg, errlen, "%s", what);
    errmsg[errlen - 1] = '\0';
  }
  ERR_clear_error();
}

/* SSL_connect with a deadline, the socket non-blocking for the handshake and
   restored to blocking after.  Winsock uses ioctlsocket(FIONBIO) and select()
   where the POSIX build uses fcntl() and poll(). */
static int handshake(SSL* ssl, SOCKET fd, int timeout_ms, char* errmsg,
                     size_t errlen) {
  u_long nonblock = 1;
  u_long blocking = 0;
  DWORD deadline = GetTickCount() + (DWORD)timeout_ms;
  int ok = 0;

  if (ioctlsocket(fd, FIONBIO, &nonblock) != 0) {
    _snprintf(errmsg, errlen, "cannot make the connection non-blocking");
    errmsg[errlen - 1] = '\0';
    return 0;
  }

  for (;;) {
    int r = SSL_connect(ssl);
    int e;
    fd_set rfds, wfds;
    struct timeval tv;
    DWORD now;
    long left;
    int sel;

    if (r == 1) {
      ok = 1;
      break;
    }

    e = SSL_get_error(ssl, r);
    FD_ZERO(&rfds);
    FD_ZERO(&wfds);
    if (e == SSL_ERROR_WANT_READ) {
      FD_SET(fd, &rfds);
    } else if (e == SSL_ERROR_WANT_WRITE) {
      FD_SET(fd, &wfds);
    } else if (e == SSL_ERROR_SYSCALL && ERR_peek_error() == 0) {
      _snprintf(errmsg, errlen, "TLS handshake: connection closed by server");
      errmsg[errlen - 1] = '\0';
      break;
    } else {
      tls_error_text("TLS handshake", errmsg, errlen);
      break;
    }

    now = GetTickCount();
    left = (long)(deadline - now);       /* GetTickCount wraps ~49 days; the
                                            handshake window is 10 s */
    if (left <= 0) {
      _snprintf(errmsg, errlen, "TLS handshake: no answer within %d ms",
                timeout_ms);
      errmsg[errlen - 1] = '\0';
      break;
    }
    tv.tv_sec = left / 1000;
    tv.tv_usec = (left % 1000) * 1000;
    sel = select(0, &rfds, &wfds, NULL, &tv);   /* nfds ignored on Winsock */
    if (sel == 0) {
      _snprintf(errmsg, errlen, "TLS handshake: no answer within %d ms",
                timeout_ms);
      errmsg[errlen - 1] = '\0';
      break;
    }
    if (sel == SOCKET_ERROR) {
      _snprintf(errmsg, errlen, "TLS handshake: select failed (%d)",
                WSAGetLastError());
      errmsg[errlen - 1] = '\0';
      break;
    }
  }

  (void)ioctlsocket(fd, FIONBIO, &blocking);
  return ok;
}

SD_TLS_CLIENT* sd_tls_client_start(SOCKET fd, int timeout_ms, char* errmsg,
                                   size_t errlen) {
  SD_TLS_CLIENT* c = calloc(1, sizeof(*c));

  if (c == NULL) {
    if (errmsg && errlen)
      _snprintf(errmsg, errlen, "out of memory");
    return NULL;
  }
  c->fd = fd;

  c->ctx = SSL_CTX_new(TLS_client_method());
  if (c->ctx == NULL ||
      !SSL_CTX_set_min_proto_version(c->ctx, TLS1_3_VERSION) ||
      !SSL_CTX_set_max_proto_version(c->ctx, TLS1_3_VERSION)) {
    tls_error_text("cannot set up TLS", errmsg, errlen);
    goto fail;
  }

  /* NOT VERIFIED, DELIBERATELY - see the description block.  The SCRAM
     exchange bound to this session is what proves which server this is. */
  SSL_CTX_set_verify(c->ctx, SSL_VERIFY_NONE, NULL);

  c->ssl = SSL_new(c->ctx);
  if (c->ssl == NULL || SSL_set_fd(c->ssl, (int)fd) != 1) {
    tls_error_text("cannot set up TLS", errmsg, errlen);
    goto fail;
  }

  if (!handshake(c->ssl, fd, timeout_ms, errmsg, errlen))
    goto fail;

  if (SSL_version(c->ssl) != TLS1_3_VERSION ||
      SSL_export_keying_material(c->ssl, c->binding, SD_TLS_BINDING_BYTES,
                                 SD_TLS_BINDING_LABEL,
                                 strlen(SD_TLS_BINDING_LABEL), NULL, 0, 0)
          != 1) {
    tls_error_text("cannot derive the channel binding", errmsg, errlen);
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
      continue;                       /* blocking socket: retry */
    ERR_clear_error();
    return -1;
  }
}

int sd_tls_client_pending(SD_TLS_CLIENT* c) {
  return SSL_pending(c->ssl);
}

/* The whole buffer, or 0.  No SIGPIPE handling: Windows send() raises no
   signal, and a write to a closed connection returns an error the caller
   already treats as a lost connection. */
int sd_tls_client_write(SD_TLS_CLIENT* c, const void* buf, int len) {
  const char* p = buf;

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
    ERR_clear_error();
    return 0;
  }
  return 1;
}

const unsigned char* sd_tls_client_binding(SD_TLS_CLIENT* c) {
  return c->binding;
}

/* base64(gs2-header + binding) - SCRAM's c= value (RFC 5802 section 7).
   Identical to the server's sd_tls_cbind_attr(). */
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
