/* SDAI_HTTPS.C
 * sd-ai.exe: the one outward call - TCP, TLS by the static OpenSSL, HTTP/1.1.
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
 * 13 Nov 26 Windows port - New (RELEASE_1.1 246): the C helper replaces the Python one (gplbld/sd-ai's https_call: ssl.create_default_context
 *           and http.client), design .claude/design-ai-helper-20261113.md 3.5 option A and Q2 (OpenSSL, so SET.AI CA keeps Linux's meaning).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHAT PYTHON'S DEFAULT CONTEXT DID, AND THIS DOES (there is no flag, setting or code path that does less):
 *   - THE CERTIFICATE IS VERIFIED (SSL_VERIFY_PEER) against the ca-file when one is set - the administrator's file ALONE, as Linux's
 *     create_default_context(cafile=...) - or else the Windows ROOT store, each certificate the store does not bar from server
 *     authentication (Python's load_default_certs on Windows).  X509_STRICT and PARTIAL_CHAIN as Python 3.13's default context.
 *   - THE HOST NAME IS CHECKED (SSL_set1_host, or the address for an IP), and SNI sent.  TLS 1.2 or later.
 *   - NO REDIRECT IS FOLLOWED: there is no code here that reads Location; a 3xx is a status like any other, refused by the caller.
 *   - NO PROXY: a direct connection (owner, Q7), as Linux.
 *   - The key goes only into the headers of this one request to the provider's own host.
 *   - Connect and handshake within CONNECT_TIMEOUT_MS; then each read and write within timeout_ms (a socket timeout, as Python's).
 *   - At most RAW_CAP + 1 bytes of the answer are read (the caller refuses the + 1).  Content-Length, chunked, or to the close.
 *
 * NO USER32: the static libcrypto imports three USER32 functions for a message box; they are satisfied here (sdtlsrelay.c's measurement,
 * 16 Sep 2026), so the service's restricted token never has to reach a window station, and stage.py's NATIVE_ONLY refuses USER32.
 *
 * END-DESCRIPTION
 */

#include "sdai.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wincrypt.h>

#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

static HWINSTA WINAPI stub_GetProcessWindowStation(void) { return NULL; }
static BOOL WINAPI stub_GetUserObjectInformationW(HANDLE h, int i, PVOID p, DWORD n, LPDWORD need) {
  (void)h;
  (void)i;
  (void)p;
  (void)n;
  if (need)
    *need = 0;
  return FALSE;
}
static int WINAPI stub_MessageBoxW(HWND w, LPCWSTR t, LPCWSTR c, UINT u) {
  (void)w;
  (void)t;
  (void)c;
  (void)u;
  return 0;
}
void* __imp_GetProcessWindowStation = (void*)stub_GetProcessWindowStation;
void* __imp_GetUserObjectInformationW = (void*)stub_GetUserObjectInformationW;
void* __imp_MessageBoxW = (void*)stub_MessageBoxW;

/* May the store's certificate serve as an anchor for a server's certificate?  Python's rule: the enhanced key usage property, then the
   extension; "not found" is every use, an empty list is none. */
static int usage_ok(PCCERT_CONTEXT c, DWORD flag) {
  DWORD size = 0;
  CERT_ENHKEY_USAGE* u;
  DWORD i;
  int ok = 0;
  if (!CertGetEnhancedKeyUsage(c, flag, NULL, &size))
    return (GetLastError() == (DWORD)CRYPT_E_NOT_FOUND) ? 1 : 0;
  u = (CERT_ENHKEY_USAGE*)malloc(size ? size : 1);
  if (u == NULL)
    return 0;
  if (!CertGetEnhancedKeyUsage(c, flag, u, &size)) {
    DWORD e = GetLastError();
    free(u);
    return (e == (DWORD)CRYPT_E_NOT_FOUND) ? 1 : 0;
  }
  for (i = 0; i < u->cUsageIdentifier; i++) {
    if (u->rgpszUsageIdentifier[i] != NULL && strcmp(u->rgpszUsageIdentifier[i], szOID_PKIX_KP_SERVER_AUTH) == 0)
      ok = 1;
  }
  free(u);
  return ok;
}

static int load_windows_roots(X509_STORE* store) {
  HCERTSTORE hs = CertOpenSystemStoreW(0, L"ROOT");
  PCCERT_CONTEXT c = NULL;
  int added = 0;
  if (hs == NULL)
    return 0;
  while ((c = CertEnumCertificatesInStore(hs, c)) != NULL) {
    const unsigned char* p;
    X509* x;
    if (c->dwCertEncodingType != X509_ASN_ENCODING)
      continue;
    if (!usage_ok(c, CERT_FIND_PROP_ONLY_ENHKEY_USAGE_FLAG) || !usage_ok(c, CERT_FIND_EXT_ONLY_ENHKEY_USAGE_FLAG))
      continue;
    p = c->pbCertEncoded;
    x = d2i_X509(NULL, &p, (long)c->cbCertEncoded);
    if (x != NULL) {
      if (X509_STORE_add_cert(store, x))
        added++;
      X509_free(x);
    }
  }
  ERR_clear_error(); /* a duplicate certificate is an error to X509_STORE_add_cert and nothing to us */
  CertCloseStore(hs, 0);
  return added;
}

static void set_timeout(SOCKET s, int ms) {
  DWORD t = (DWORD)((ms > 0) ? ms : 1);
  setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char*)&t, sizeof t);
  setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char*)&t, sizeof t);
}

/* A TCP connection to host:port, each address given CONNECT_TIMEOUT_MS (socket.create_connection).  HC_OK, HC_NET or HC_TIMEOUT. */
static int tcp_connect(const char* host, int port, SOCKET* out) {
  struct addrinfo hints, *res = NULL, *ai;
  char ps[16];
  int rc = HC_NET;
  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  snprintf(ps, sizeof ps, "%d", port);
  if (getaddrinfo(host, ps, &hints, &res) != 0)
    return HC_NET;
  for (ai = res; ai != NULL; ai = ai->ai_next) {
    SOCKET s = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    u_long nb = 1;
    fd_set wf, ef;
    struct timeval tv;
    int err = 0;
    int elen = sizeof err;
    if (s == INVALID_SOCKET)
      continue;
    ioctlsocket(s, FIONBIO, &nb);
    if (connect(s, ai->ai_addr, (int)ai->ai_addrlen) == SOCKET_ERROR && WSAGetLastError() != WSAEWOULDBLOCK) {
      closesocket(s);
      continue;
    }
    FD_ZERO(&wf);
    FD_ZERO(&ef);
    FD_SET(s, &wf);
    FD_SET(s, &ef);
    tv.tv_sec = CONNECT_TIMEOUT_MS / 1000;
    tv.tv_usec = (CONNECT_TIMEOUT_MS % 1000) * 1000;
    switch (select(0, NULL, &wf, &ef, &tv)) {
      case 0:
        rc = HC_TIMEOUT;
        closesocket(s);
        continue;
      case SOCKET_ERROR:
        closesocket(s);
        continue;
    }
    if (FD_ISSET(s, &ef) || getsockopt(s, SOL_SOCKET, SO_ERROR, (char*)&err, &elen) != 0 || err != 0) {
      closesocket(s);
      rc = HC_NET;
      continue;
    }
    nb = 0;
    ioctlsocket(s, FIONBIO, &nb);
    *out = s;
    freeaddrinfo(res);
    return HC_OK;
  }
  freeaddrinfo(res);
  return rc;
}

typedef struct {
  SSL* ssl;
  char buf[16384];
  size_t pos, len;
  int eof;
  int err; /* HC_* of the read that failed */
  ULONGLONG started;
  int timeout_ms;
} conn_t;

static int io_failure(conn_t* c) {
  if (WSAGetLastError() == WSAETIMEDOUT || (GetTickCount64() - c->started) + 50 >= (ULONGLONG)c->timeout_ms)
    return HC_TIMEOUT;
  return HC_NET;
}

static int fill(conn_t* c) {
  int n;
  if (c->eof)
    return 0;
  c->started = GetTickCount64();
  n = SSL_read(c->ssl, c->buf, (int)sizeof c->buf);
  if (n > 0) {
    c->pos = 0;
    c->len = (size_t)n;
    return 1;
  }
  switch (SSL_get_error(c->ssl, n)) {
    case SSL_ERROR_ZERO_RETURN:
      c->eof = 1;
      return 0;
    case SSL_ERROR_SYSCALL:
      if (ERR_peek_error() == 0 && WSAGetLastError() == 0) {
        c->eof = 1; /* the peer closed the connection */
        return 0;
      }
      c->err = io_failure(c);
      return -1;
    default:
      c->err = (WSAGetLastError() == WSAETIMEDOUT) ? HC_TIMEOUT : HC_NET;
      return -1;
  }
}

/* One header line (without the CRLF) into out; 1 a line, 0 the end of the data, -1 a failure or a line of more than 65536 (http.client's limit). */
static int read_line(conn_t* c, sbuf* out) {
  out->n = 0;
  out->p[0] = '\0';
  for (;;) {
    while (c->pos < c->len) {
      char ch = c->buf[c->pos++];
      if (ch == '\n') {
        if (out->n > 0 && out->p[out->n - 1] == '\r')
          out->p[--out->n] = '\0';
        return 1;
      }
      sb_add(out, &ch, 1);
      if (out->n > 65536) {
        c->err = HC_NET;
        return -1;
      }
    }
    {
      int f = fill(c);
      if (f < 0)
        return -1;
      if (f == 0)
        return out->n > 0 ? 1 : 0;
    }
  }
}

/* Up to want bytes of the body onto out; 0 at the end of the data, -1 a failure. */
static int read_some(conn_t* c, sbuf* out, size_t want) {
  size_t k;
  if (c->pos >= c->len) {
    int f = fill(c);
    if (f <= 0)
      return f;
  }
  k = c->len - c->pos;
  if (k > want)
    k = want;
  sb_add(out, c->buf + c->pos, k);
  c->pos += k;
  return 1;
}

static int ieq_prefix(const char* line, const char* name) {
  size_t n = strlen(name);
  return _strnicmp(line, name, n) == 0 && line[n] == ':';
}

static const char* hvalue(const char* line) {
  const char* v = strchr(line, ':') + 1;
  while (*v == ' ' || *v == '\t')
    v++;
  return v;
}

static int read_response(conn_t* c, http_resp* r) {
  sbuf line;
  sbuf body;
  long long clen = -1;
  int chunked = 0;
  int headers = 0;
  sb_init(&line);
  sb_init(&body);
  for (;;) { /* the status line, past any 1xx */
    int code;
    if (read_line(c, &line) <= 0)
      return (c->err != 0) ? c->err : HC_NET;
    if (strncmp(line.p, "HTTP/", 5) != 0 || strchr(line.p, ' ') == NULL)
      return HC_NET;
    code = atoi(strchr(line.p, ' ') + 1);
    if (code < 100 || code > 999)
      return HC_NET;
    r->status = code;
    for (;;) {
      int k = read_line(c, &line);
      if (k < 0)
        return c->err;
      if (k == 0 || line.n == 0)
        break;
      if (++headers > 100)
        return HC_NET; /* http.client's limit */
      if (strchr(line.p, ':') == NULL)
        continue;
      if (ieq_prefix(line.p, "Content-Length"))
        clen = _atoi64(hvalue(line.p));
      else if (ieq_prefix(line.p, "Transfer-Encoding") && strstr(hvalue(line.p), "chunked") != NULL)
        chunked = 1;
      else if (ieq_prefix(line.p, "Retry-After")) {
        snprintf(r->retry_after, sizeof r->retry_after, "%s", hvalue(line.p));
        r->has_retry_after = 1;
      }
    }
    if (code >= 200)
      break;
    headers = 0;
    clen = -1;
    chunked = 0;
  }
  if (r->status == 204 || r->status == 304) {
    r->body = body.p;
    r->len = 0;
    return HC_OK;
  }
  if (chunked) {
    for (;;) {
      long long size;
      if (read_line(c, &line) <= 0)
        break;
      size = strtoll(line.p, NULL, 16);
      if (size <= 0) {
        while (read_line(c, &line) > 0 && line.n > 0) /* the trailer */
          ;
        break;
      }
      while (size > 0 && body.n <= RAW_CAP) {
        size_t before = body.n;
        size_t want = (size_t)size;
        int k;
        if (want > RAW_CAP + 1 - body.n)
          want = RAW_CAP + 1 - body.n;
        k = read_some(c, &body, want);
        if (k < 0)
          return c->err;
        if (k == 0)
          break;
        size -= (long long)(body.n - before);
      }
      if (body.n > RAW_CAP)
        break;
      if (read_line(c, &line) < 0) /* the CRLF after the chunk */
        return c->err;
    }
  } else {
    while (body.n <= RAW_CAP && (clen < 0 || (long long)body.n < clen)) {
      size_t want = RAW_CAP + 1 - body.n;
      int k;
      if (clen >= 0 && (long long)want > clen - (long long)body.n)
        want = (size_t)(clen - (long long)body.n);
      k = read_some(c, &body, want);
      if (k < 0)
        return c->err;
      if (k == 0)
        break;
    }
  }
  if (body.n > RAW_CAP + 1)
    body.n = RAW_CAP + 1;
  r->body = body.p;
  r->len = body.n;
  return HC_OK;
}

int https_call(const char* host, int port, const char* method, const char* path, const char* headers, const char* body, size_t blen,
               const char* ca_file, int timeout_ms, http_resp* r) {
  static int wsa = 0;
  SSL_CTX* ctx = NULL;
  SSL* ssl = NULL;
  SOCKET s = INVALID_SOCKET;
  X509_VERIFY_PARAM* vp;
  struct in6_addr a6;
  struct in_addr a4;
  int is_ip;
  int rc;
  sbuf req;
  conn_t c;

  memset(r, 0, sizeof *r);
  if (!wsa) {
    WSADATA wd;
    if (WSAStartup(MAKEWORD(2, 2), &wd) != 0)
      return HC_NET;
    wsa = 1;
  }

  ctx = SSL_CTX_new(TLS_client_method());
  if (ctx == NULL || !SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION)) {
    rc = HC_TLS;
    goto done;
  }
  SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
  SSL_CTX_set_options(ctx, SSL_OP_IGNORE_UNEXPECTED_EOF | SSL_OP_NO_COMPRESSION);
  X509_VERIFY_PARAM_set_flags(SSL_CTX_get0_param(ctx), X509_V_FLAG_X509_STRICT | X509_V_FLAG_PARTIAL_CHAIN);
  if (ca_file != NULL && ca_file[0] != '\0') {
    if (SSL_CTX_load_verify_file(ctx, ca_file) != 1) {
      rc = HC_TLS;
      goto done;
    }
  } else if (load_windows_roots(SSL_CTX_get_cert_store(ctx)) == 0) {
    rc = HC_CERT; /* no anchor at all: nothing could be accepted */
    goto done;
  }

  rc = tcp_connect(host, port, &s);
  if (rc != HC_OK)
    goto done;
  set_timeout(s, CONNECT_TIMEOUT_MS);

  ssl = SSL_new(ctx);
  if (ssl == NULL || SSL_set_fd(ssl, (int)s) != 1) {
    rc = HC_TLS;
    goto done;
  }
  vp = SSL_get0_param(ssl);
  is_ip = (inet_pton(AF_INET, host, &a4) == 1) || (inet_pton(AF_INET6, host, &a6) == 1);
  if (is_ip) {
    if (!X509_VERIFY_PARAM_set1_ip_asc(vp, host)) {
      rc = HC_TLS;
      goto done;
    }
  } else {
    X509_VERIFY_PARAM_set_hostflags(vp, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
    if (!SSL_set1_host(ssl, host) || !SSL_set_tlsext_host_name(ssl, host)) {
      rc = HC_TLS;
      goto done;
    }
  }
  {
    ULONGLONG t0 = GetTickCount64();
    WSASetLastError(0);
    if (SSL_connect(ssl) != 1) {
      if (SSL_get_verify_result(ssl) != X509_V_OK)
        rc = HC_CERT;
      else if (WSAGetLastError() == WSAETIMEDOUT || GetTickCount64() - t0 + 50 >= CONNECT_TIMEOUT_MS)
        rc = HC_TIMEOUT;
      else
        rc = HC_TLS;
      goto done;
    }
  }
  set_timeout(s, timeout_ms);

  sb_init(&req);
  sb_printf(&req, "%s %s HTTP/1.1\r\n", method, path);
  if (port == 443)
    sb_printf(&req, "Host: %s\r\n", host);
  else
    sb_printf(&req, "Host: %s:%d\r\n", host, port);
  sb_puts(&req, "Accept-Encoding: identity\r\n");
  sb_puts(&req, headers);
  if (body != NULL)
    sb_printf(&req, "Content-Length: %u\r\n", (unsigned)blen);
  sb_puts(&req, "Connection: close\r\n\r\n");
  if (body != NULL)
    sb_add(&req, body, blen);
  {
    size_t done = 0;
    while (done < req.n) {
      int n;
      WSASetLastError(0);
      n = SSL_write(ssl, req.p + done, (int)(req.n - done));
      if (n <= 0) {
        rc = (WSAGetLastError() == WSAETIMEDOUT) ? HC_TIMEOUT : HC_NET;
        SecureZeroMemory(req.p, req.n);
        goto done;
      }
      done += (size_t)n;
    }
  }
  SecureZeroMemory(req.p, req.n); /* the key was in it */
  free(req.p);

  memset(&c, 0, sizeof c);
  c.ssl = ssl;
  c.timeout_ms = timeout_ms;
  WSASetLastError(0);
  rc = read_response(&c, r);

done:
  if (ssl != NULL) {
    SSL_shutdown(ssl);
    SSL_free(ssl);
  }
  if (s != INVALID_SOCKET)
    closesocket(s);
  if (ctx != NULL)
    SSL_CTX_free(ctx);
  ERR_clear_error();
  return rc;
}

/* END-CODE */
