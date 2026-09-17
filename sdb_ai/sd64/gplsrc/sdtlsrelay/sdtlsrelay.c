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
 * 17 Sep 26 Windows port - RELEASE_1.1 55: a THIRD inherited socket, the
 *           control channel to the front, and one more argument.  The relay
 *           holds it here; acting on it - standing up the handover pipe and
 *           cutting the app side over to it - is the next slice.
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
 * integrity Low - and exactly three inherited handles: the accepted
 * connection, one end of the socketpair sd keeps as its own descriptors 0 and
 * 1, and one end of a second socketpair, the CONTROL channel.  The relay owns
 * the network socket and the TLS state; sd's I/O code never changes.  When
 * either side ends, the other is closed and the process exits.
 *
 *   sdtlsrelay.exe <net handle> <sp handle> <control handle> <timeout ms>
 *
 * THE CONTROL CHANNEL (RELEASE_1.1 55, protocol in sd_tls.h).  The app side
 * above is the session's byte stream and has to stay one, so the handover -
 * the one thing the front says to the relay that is not a session byte -
 * travels on its own socketpair.  It is silent for the whole of the SCRAM
 * window; the front speaks on it once, if the login succeeds.
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
#include <sddl.h>                     /* the handover pipe's DACL, in SDDL */

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
static SOCKET ctl_sock = INVALID_SOCKET;   /* the front's control channel */

/* ======================================================================
   NO USER32 IN THIS PROCESS, AND THIS IS WHY THE FIRST INSTALL DIED.

   The static libcrypto imports three USER32 functions for its fatal-error
   path - OPENSSL_isservice() asks GetProcessWindowStation() and
   GetUserObjectInformationW() whether it may pop a MessageBoxW().  Nothing
   here ever reaches that path, but the IMPORT is enough: USER32's own
   initialisation connects the process to a window station, and the bare
   account's token - a fresh S4U logon session, in session 0 - has no right
   to the service's WinSta0\Default.  USER32 cannot connect, the loader gives
   up, and the process is dead before main(): STATUS_DLL_INIT_FAILED,
   0xC0000142.  Measured on the second cycle of this build, 16 Sep 2026
   (syslog: "relay could not initialise (0xC0000142)"), and reproduced
   unelevated by gplbld/probe-user32desk.c: on an unreachable desktop a
   USER32 importer dies exactly so while a non-importer runs.
   probe-relaychild.exe, which proved the spawn, never imported USER32.

   So the three imports are satisfied HERE instead of by libuser32.a.  A
   MinGW call to a dllimport function goes through the pointer __imp_<name>;
   defining those pointers in this object means the linker never pulls the
   import library's members, and USER32 leaves the import table - which
   stage.py's NATIVE_ONLY check now requires.  The stubs answer "no window
   station", which OPENSSL_isservice() reads as "a service": no message box,
   the text goes to stderr, which is where a headless process wants it. */

static HWINSTA WINAPI stub_GetProcessWindowStation(void) { return NULL; }
static BOOL WINAPI stub_GetUserObjectInformationW(HANDLE h, int i, PVOID p,
                                                  DWORD n, LPDWORD need) {
  (void)h; (void)i; (void)p; (void)n;
  if (need) *need = 0;
  return FALSE;
}
static int WINAPI stub_MessageBoxW(HWND w, LPCWSTR t, LPCWSTR c, UINT u) {
  (void)w; (void)t; (void)c; (void)u;
  return 0;
}
void* __imp_GetProcessWindowStation = (void*)stub_GetProcessWindowStation;
void* __imp_GetUserObjectInformationW = (void*)stub_GetUserObjectInformationW;
void* __imp_MessageBoxW = (void*)stub_MessageBoxW;

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
  if (ctl_sock != INVALID_SOCKET)
    closesocket(ctl_sock);
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
   THE HANDOVER (RELEASE_1.1 55): the relay becomes the pipe's SERVER

   WHY THE SERVER IS HERE AND NOT IN THE FRONT.  A named pipe instance dies
   with its last SERVER handle, and the front exits as soon as the handover is
   done - that is the whole point of 55, no LocalSystem left in the
   authenticated data path.  So the end that has to outlive the front is the
   end that lives here.

   WHAT THE DACL IS FOR.  The only party that ever opens the CLIENT end is the
   front, which is LocalSystem; it then hands the handle to the session it
   spawned, and an inherited handle carries its access rather than being
   re-checked.  So SYSTEM alone is both necessary and sufficient, and the
   session's own account needs no ACE.  Single instance on top of that: once
   the front has connected, nothing else can.

   MEASURED BEFORE IT WAS BUILT, because it decides the topology rather than a
   detail inside it: gplbld/probe-lowpipe.c ran this create under a token at
   integrity Low with EVERY PRIVILEGE REMOVED - the relay's own shape - and it
   succeeded, with a Medium control beside it so a failure would have been
   attributable.  That probe is the same user, not the bare account in its
   session-0 logon session, so the remainder closes on the cycle.            */

static HANDLE handover_pipe = INVALID_HANDLE_VALUE;

/* Defined with the rest of the pump, below. */
static int ssl_write_all(SSL* ssl, const unsigned char* p, int len);

/* One control frame to the front: opcode, u16 length, payload (sd_tls.h). */
static int ctl_send(unsigned char op, const char* text) {
  unsigned char hdr[3];
  size_t len = text ? strlen(text) : 0;

  if (len > SD_RELAY_CTL_MAX)
    len = SD_RELAY_CTL_MAX;
  hdr[0] = op;
  hdr[1] = (unsigned char)((len >> 8) & 0xFF);
  hdr[2] = (unsigned char)(len & 0xFF);
  if (ctl_sock == INVALID_SOCKET)
    return 0;
  if (!send_all(ctl_sock, hdr, sizeof(hdr)))
    return 0;
  if (len > 0 && !send_all(ctl_sock, (const unsigned char*)text, len))
    return 0;
  return 1;
}

/* One control frame from the front.  1 got one, 0 the front closed the
   channel, -1 it is unusable.  text is NUL-terminated on 1.               */
static int ctl_recv(unsigned char* op, char* text, size_t textlen, size_t* got,
                    ULONGLONG deadline) {
  unsigned char hdr[3];
  size_t len;
  int r;

  r = recv_all(ctl_sock, hdr, sizeof(hdr), deadline);
  if (r != 1)
    return r == 0 ? 0 : -1;
  len = ((size_t)hdr[1] << 8) | hdr[2];
  if (len > SD_RELAY_CTL_MAX || len >= textlen)
    return -1;
  if (len > 0 && recv_all(ctl_sock, (unsigned char*)text, len, deadline) != 1)
    return -1;
  text[len] = '\0';
  *op = hdr[0];
  *got = len;
  return 1;
}

/* Create the handover pipe.  name is the frame's payload: the pipe's name, a
   NUL, and the SID that may open the client end.  Non-zero with the pipe
   standing, zero with err - and err goes back to the front, which fails the
   login rather than handing a session a channel nothing is listening on. */
static int make_handover_pipe(const char* name, size_t framelen, char* err,
                              size_t errlen) {
  SECURITY_ATTRIBUTES sa;
  PSECURITY_DESCRIPTOR sd = NULL;
  PSID parsed = NULL;
  const char* sid;
  char sddl[320];
  size_t prefixlen = strlen(SD_RELAY_PIPE_PREFIX);
  size_t namelen = strlen(name);

  if (handover_pipe != INVALID_HANDLE_VALUE) {
    snprintf(err, errlen, "a handover pipe already stands on this connection");
    return 0;
  }
  /* The front is the only writer on this channel, so these are bounds on a
     bug rather than on an attacker - and they also refuse the empty name and
     the missing SID that a truncated frame would otherwise present as a
     valid request. */
  if (strncmp(name, SD_RELAY_PIPE_PREFIX, prefixlen) != 0 ||
      name[prefixlen] == '\0') {
    snprintf(err, errlen, "the handover pipe name does not begin with %s",
             SD_RELAY_PIPE_PREFIX);
    return 0;
  }
  if (namelen + 1 >= framelen) {
    snprintf(err, errlen, "the handover request carries no SID");
    return 0;
  }
  sid = name + namelen + 1;
  /* Parsed before it reaches the SDDL, so a malformed one is refused as a
     SID instead of becoming whatever text it happens to be. */
  if (!ConvertStringSidToSidA(sid, &parsed)) {
    snprintf(err, errlen, "the handover request's SID does not parse");
    return 0;
  }
  LocalFree(parsed);
  if (snprintf(sddl, sizeof(sddl), "D:(A;;GA;;;%s)", sid) >= (int)sizeof(sddl)) {
    snprintf(err, errlen, "the handover request's SID is too long");
    return 0;
  }
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(
          sddl, SDDL_REVISION_1, &sd, NULL)) {
    snprintf(err, errlen, "cannot build the handover pipe's DACL (error %lu)",
             (unsigned long)GetLastError());
    return 0;
  }
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;
  sa.bInheritHandle = FALSE;

  handover_pipe =
      CreateNamedPipeA(name, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                       PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
                       RELAY_BUFFER * 4, RELAY_BUFFER * 4, 0, &sa);
  LocalFree(sd);
  if (handover_pipe == INVALID_HANDLE_VALUE) {
    snprintf(err, errlen, "cannot create %.200s (error %lu)", name,
             (unsigned long)GetLastError());
    return 0;
  }
  return 1;
}

/* Wait for the front's client end.  It has almost always connected already -
   the front opens it the moment it is told READY, and only then closes the
   app side - so ERROR_PIPE_CONNECTED is the normal answer, not an error. */
static int connect_handover(int timeout_ms) {
  OVERLAPPED ov;
  HANDLE ev = CreateEventA(NULL, TRUE, FALSE, NULL);
  DWORD unused = 0;
  int ok = 0;

  if (ev == NULL)
    return 0;
  ZeroMemory(&ov, sizeof(ov));
  ov.hEvent = ev;
  if (ConnectNamedPipe(handover_pipe, &ov)) {
    ok = 1;
  } else {
    DWORD e = GetLastError();
    if (e == ERROR_PIPE_CONNECTED) {
      ok = 1;
    } else if (e == ERROR_IO_PENDING) {
      if (WaitForSingleObject(ev, (DWORD)timeout_ms) == WAIT_OBJECT_0)
        ok = GetOverlappedResult(handover_pipe, &ov, &unused, FALSE) ? 1 : 0;
      else
        CancelIo(handover_pipe);
    }
  }
  CloseHandle(ev);
  return ok;
}

/* ======================================================================
   PHASE B: the client <-> the session, with the front gone

   ONE THREAD, TWO KINDS OF HANDLE, AND THAT IS THE WHOLE DIFFICULTY.  The
   network side is a socket and the session side is a pipe, and no single
   Windows wait covers both as they are: WSAPoll takes sockets only, and
   WaitForMultipleObjects takes kernel objects only.  So the socket is given
   an event with WSAEventSelect and the pipe is read with OVERLAPPED I/O, and
   one WaitForMultipleObjects covers both.

   gplbld/probe-relaycutover.c measured the cutover with a 200 ms poll and a
   PeekNamedPipe instead, and said in its own text that the product would use
   overlapped I/O.  It would have worked - and it would have put up to 200 ms
   on every response an API client waits for, which is a performance
   regression against what the socketpair does today.

   FD_READ IS EDGE-TRIGGERED AND THIS IS THE PART THAT HANGS IF IT IS GOT
   WRONG.  It re-arms when a recv on the socket answers WSAEWOULDBLOCK, not
   when data remains.  SSL_read may return a whole record while more bytes sit
   in the socket, so a single SSL_read per signal can leave data unread with
   no further event coming.  The cure is to drain: keep calling SSL_read until
   it answers WANT_READ, which is precisely OpenSSL telling us its recv got
   WSAEWOULDBLOCK and the event is armed again.  SSL_pending is checked too,
   for bytes OpenSSL has decrypted and is holding.                          */

static int pipe_write_all(HANDLE pipe, const unsigned char* buf, size_t len) {
  OVERLAPPED ov;
  HANDLE ev = CreateEventA(NULL, TRUE, FALSE, NULL);
  size_t off = 0;
  int ok = 1;

  if (ev == NULL)
    return 0;
  while (off < len) {
    DWORD wrote = 0;
    ZeroMemory(&ov, sizeof(ov));
    ov.hEvent = ev;
    ResetEvent(ev);
    if (!WriteFile(pipe, buf + off, (DWORD)(len - off), &wrote, &ov)) {
      if (GetLastError() != ERROR_IO_PENDING) {
        ok = 0;
        break;
      }
      if (!GetOverlappedResult(pipe, &ov, &wrote, TRUE)) {
        ok = 0;
        break;
      }
    }
    if (wrote == 0) {
      ok = 0;
      break;
    }
    off += wrote;
  }
  CloseHandle(ev);
  return ok;
}

/* Drain everything readable from the TLS side into the pipe.  0 means the
   client ended or the connection failed; 1 means drained for now.         */
static int drain_net_to_pipe(SSL* ssl, HANDLE pipe) {
  unsigned char buf[RELAY_BUFFER];

  for (;;) {
    int n = SSL_read(ssl, buf, (int)sizeof(buf));
    if (n > 0) {
      if (!pipe_write_all(pipe, buf, (size_t)n))
        return 0;
      continue;
    }
    {
      int e = SSL_get_error(ssl, n);
      if (e == SSL_ERROR_WANT_READ || e == SSL_ERROR_WANT_WRITE)
        return 1;                      /* armed again; nothing more for now */
      return 0;                        /* close_notify, reset, or a fault */
    }
  }
}

static void relay_phase_b(SSL* ssl, HANDLE pipe) {
  WSAEVENT netev = WSACreateEvent();
  HANDLE readev = CreateEventA(NULL, TRUE, FALSE, NULL);
  HANDLE waits[2];
  OVERLAPPED ov;
  unsigned char buf[RELAY_BUFFER];
  int pending = 0;

  if (netev == WSA_INVALID_EVENT || readev == NULL)
    goto done;
  if (WSAEventSelect(net_sock, netev, FD_READ | FD_CLOSE) != 0)
    goto done;

  /* Drain before waiting, for what arrived during the cutover.
     DEFENSIVE, AND SAY SO: removing this line was run as a mutant against
     test-tlsrelay-units.py's handover rows and they all still passed, which
     means WSAEventSelect does signal FD_READ for data already waiting in the
     SOCKET - so the measured path does not need it.  The case it covers is
     the other one: bytes OpenSSL has already pulled off the socket and is
     holding, where the socket is empty and no FD_READ is ever coming.  That
     needs two TLS records to arrive in one segment at a particular moment,
     which the test cannot produce to order, so this is reasoning rather than
     a measurement and is kept on those terms. */
  if (!drain_net_to_pipe(ssl, pipe))
    goto done;

  for (;;) {
    DWORD w;

    if (!pending) {
      DWORD got = 0;
      ZeroMemory(&ov, sizeof(ov));
      ov.hEvent = readev;
      ResetEvent(readev);
      if (!ReadFile(pipe, buf, (DWORD)sizeof(buf), &got, &ov) &&
          GetLastError() != ERROR_IO_PENDING)
        goto done;                     /* the session ended */
      pending = 1;
    }

    waits[0] = (HANDLE)netev;
    waits[1] = readev;
    w = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
    if (w != WAIT_OBJECT_0 && w != WAIT_OBJECT_0 + 1)
      goto done;

    /* The net side.  WSAEnumNetworkEvents resets the event and says which
       bits fired; asking with a zero wait covers the case where the pipe
       woke us and the socket fired as well. */
    if (WaitForSingleObject((HANDLE)netev, 0) == WAIT_OBJECT_0) {
      WSANETWORKEVENTS ne;
      if (WSAEnumNetworkEvents(net_sock, netev, &ne) != 0)
        goto done;
      if (ne.lNetworkEvents & (FD_READ | FD_CLOSE)) {
        if (!drain_net_to_pipe(ssl, pipe))
          goto done;
      }
    }

    /* The session side. */
    if (pending && WaitForSingleObject(readev, 0) == WAIT_OBJECT_0) {
      DWORD got = 0;
      int ok = GetOverlappedResult(pipe, &ov, &got, FALSE);
      pending = 0;
      if (!ok || got == 0)
        goto done;                     /* ERROR_BROKEN_PIPE: session ended */
      if (!ssl_write_all(ssl, buf, (int)got))
        goto done;
    }
  }

done:
  if (pending)
    CancelIo(pipe);
  if (readev != NULL)
    CloseHandle(readev);
  if (netev != WSA_INVALID_EVENT)
    WSACloseEvent(netev);
  /* GRACEFULLY, and this is a measured lesson rather than tidiness: a
     forcible DisconnectNamedPipe makes the far side read ECOMM(70) instead of
     end of file, and probe-sessionpipe's leg 4 failed exactly that way until
     it was fixed.  The session must see EOF. */
  FlushFileBuffers(pipe);
  CloseHandle(pipe);
  handover_pipe = INVALID_HANDLE_VALUE;
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

/* PHASE A - the front is the app side.  Everything here behaved this way
   before RELEASE_1.1 55 and still does for a connection that never
   authenticates; what 55 adds is the third descriptor and one exit.

   READING THE NET STOPS AT THE HANDOVER REQUEST, NOT AT THE CUTOVER.  Once
   the front has asked for the pipe, SCRAM is finished and every byte the
   client sends next belongs to the session.  Forwarding one of those to the
   front would lose it: the front is about to exit and will never read it.
   The front still has the server-final to flush, so the OTHER direction -
   app side to client - keeps running until the front closes it.
   probe-relaycutover measured the byte that arrives during the switch coming
   out at the session; stopping one step earlier makes that window smaller
   still.                                                                   */

static void relay(SSL* ssl) {
  unsigned char buf[RELAY_BUFFER];
  int reading_net = 1;                 /* until the handover is asked for */
  int ctl_open = 1;                    /* until the front closes it */

  for (;;) {
    WSAPOLLFD p[3];
    int nfds = 2;

    p[0].fd = net_sock;
    p[0].events = POLLRDNORM;
    p[0].revents = 0;
    p[1].fd = sp_sock;
    p[1].events = POLLRDNORM;
    p[1].revents = 0;
    p[2].fd = ctl_sock;
    p[2].events = POLLRDNORM;
    p[2].revents = 0;
    if (ctl_open)
      nfds = 3;

    /* Decrypted bytes OpenSSL already holds are invisible to WSAPoll. */
    if (reading_net && SSL_pending(ssl) > 0) {
      p[0].revents = POLLRDNORM;
    } else {
      /* A net side nobody is reading must not be polled either, or the loop
         spins on a readable socket it has decided to leave alone. */
      if (!reading_net)
        p[0].events = 0;
      if (WSAPoll(p, nfds, -1) < 0)
        return;
    }

    if (reading_net && (p[0].revents & (POLLRDNORM | POLLHUP | POLLERR))) {
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
      if (n == 0) {
        /* THE FRONT HAS FINISHED.  With a pipe standing this is the cutover
           signal; without one it is what it has always been, the end of the
           session. */
        if (handover_pipe == INVALID_HANDLE_VALUE)
          return;
        closesocket(sp_sock);
        sp_sock = INVALID_SOCKET;
        if (!connect_handover(SD_TLS_HANDSHAKE_MS)) {
          CloseHandle(handover_pipe);
          handover_pipe = INVALID_HANDLE_VALUE;
          return;
        }
        relay_phase_b(ssl, handover_pipe);
        return;
      }
      if (n < 0) {
        if (WSAGetLastError() == WSAEWOULDBLOCK)
          continue;
        return;
      }
      if (!ssl_write_all(ssl, buf, n))
        return;
    }

    if (ctl_open && (p[2].revents & (POLLRDNORM | POLLHUP | POLLERR))) {
      unsigned char op = 0;
      char text[SD_RELAY_CTL_MAX + 1];
      char err[512];
      size_t textlen = 0;
      int r = ctl_recv(&op, text, sizeof(text), &textlen, now_ms() + 5000);

      if (r != 1) {
        /* The front closed or broke the channel.  No handover is coming; the
           connection carries on as a pre-55 one and ends when sd does. */
        ctl_open = 0;
        continue;
      }
      if (op != SD_RELAY_CTL_PIPE) {
        (void)ctl_send(SD_RELAY_CTL_FAILED, "unknown control opcode");
        continue;
      }
      if (!make_handover_pipe(text, textlen, err, sizeof(err))) {
        (void)ctl_send(SD_RELAY_CTL_FAILED, err);
        continue;
      }
      if (!ctl_send(SD_RELAY_CTL_READY, NULL)) {
        CloseHandle(handover_pipe);    /* the front will never open it */
        handover_pipe = INVALID_HANDLE_VALUE;
        return;
      }
      reading_net = 0;
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

  if (argc != 5) {
    fprintf(stderr, "sdtlsrelay is started by sd for each API connection; "
                    "it is not a command\n");
    return SD_RELAY_EXIT_USAGE;
  }
  net_sock = (SOCKET)(uintptr_t)strtoull(argv[1], NULL, 10);
  sp_sock = (SOCKET)(uintptr_t)strtoull(argv[2], NULL, 10);
  ctl_sock = (SOCKET)(uintptr_t)strtoull(argv[3], NULL, 10);
  timeout_ms = atoi(argv[4]);
  if (timeout_ms <= 0)
    timeout_ms = SD_TLS_HANDSHAKE_MS;

  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
    return SD_RELAY_EXIT_USAGE;

  /* All three handles must be sockets, or nothing below can be trusted - and
     a wrong handle is sd's bug, so say so on the channel if that one works.
     The app side is asked first because it is the one the answer travels on;
     a handover the relay could not have performed is worth refusing HERE,
     where the front can still read the reason, rather than at the cutover an
     authenticated session later waits on for ever. */
  tl = sizeof(type);
  if (getsockopt(sp_sock, SOL_SOCKET, SO_TYPE, (char*)&type, &tl) != 0) {
    sp_sock = INVALID_SOCKET;
    refuse(SD_RELAY_EXIT_USAGE, "the socketpair handle is not a socket");
  }
  tl = sizeof(type);
  if (getsockopt(net_sock, SOL_SOCKET, SO_TYPE, (char*)&type, &tl) != 0)
    refuse(SD_RELAY_EXIT_USAGE, "the connection handle is not a socket");
  tl = sizeof(type);
  if (getsockopt(ctl_sock, SOL_SOCKET, SO_TYPE, (char*)&type, &tl) != 0) {
    ctl_sock = INVALID_SOCKET;
    refuse(SD_RELAY_EXIT_USAGE, "the control handle is not a socket");
  }

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
    nb = 1;
    (void)ioctlsocket(ctl_sock, FIONBIO, &nb);
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
  closesocket(ctl_sock);
  return 0;
}

/* END-CODE */
