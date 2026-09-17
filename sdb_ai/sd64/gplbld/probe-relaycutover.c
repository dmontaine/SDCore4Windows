/* probe-relaycutover.c - the RELAY under test for RELEASE_1.1 55 direction (a),
 * parity build.  Does a native relay switch its APP side from the socketpair it
 * uses during SCRAM (to the LocalSystem front) to the authenticated session's
 * named pipe, at the clean post-SCRAM boundary, WITHOUT LOSING BYTES?
 *
 * 17 Sep 26 Windows port.  Owner chose to ship 55 at Linux parity (HISTORY.md,
 * RELEASE_1.1_FIXES.md 55): the LocalSystem front does relay(43)+SCRAM as now,
 * then spawns the session AS the user over the crux-(1) named pipe, and to keep
 * no SYSTEM in the authenticated data path the front LEAVES it - the relay's
 * app side must cut over from the front to the session.  This measures the one
 * unmeasured piece of that build: the cutover's byte integrity.
 *
 * The relay is native and its net and app channels are native sockets, so this
 * says nothing about the Cygwin fd layer - crux (1) already proved the session
 * (Cygwin) can use the pipe.  Here BOTH the front and the session are played by
 * the parent (probe-relaycutover-drive.exe), and this relay is the process
 * under test.
 *
 * Launched:  probe-relaycutover.exe --hello                       exit 7
 *            probe-relaycutover.exe --relay <net> <appA> <pipe>
 * <net> and <appA> are inherited native SOCKET handles (the client connection
 * and the phase-A channel to the front); <pipe> is the name the session will
 * connect to after auth.  The relay:
 *   PHASE A : pump net<->appA (the SCRAM window)
 *   CUTOVER : on appA EOF (the front closing to signal auth done), STOP reading
 *             net (so any client bytes already arrived stay in the kernel
 *             buffer, unlost), create the pipe as server, wait for the session
 *             to connect, then make the pipe the app side
 *   PHASE B : pump net<->pipe until either ends
 * Exit 0 on a clean phase B EOF, 3 if the cutover or a pump leg failed, 2 for a
 * setup failure.  It reports through the pipe's own traffic and its exit code;
 * the driver judges byte integrity.
 *
 * Build NATIVE, from gplbld in an MSYS2 UCRT64 bash (no msys-2.0):
 *   gcc -O2 -Wall -o probe-relaycutover.exe probe-relaycutover.c -lws2_32
 */
#include <winsock2.h>
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUFSZ 16384

/* Pump src->dst once when src is readable.  Returns bytes moved, 0 on src EOF,
   -1 on error.  src is a SOCKET, dst is written with a writer callback so the
   same loop serves both a socket dst (phase A) and a pipe dst (phase B). */
static int sock_to_sock(SOCKET src, SOCKET dst) {
  char buf[BUFSZ];
  int n = recv(src, buf, sizeof buf, 0), off, w;
  if (n == 0)
    return 0;
  if (n < 0)
    return (WSAGetLastError() == WSAEWOULDBLOCK) ? 1 : -1;
  for (off = 0; off < n;) {
    w = send(dst, buf + off, n - off, 0);
    if (w <= 0)
      return -1;
    off += w;
  }
  return n;
}
static int sock_to_pipe(SOCKET src, HANDLE dst) {
  char buf[BUFSZ];
  int n = recv(src, buf, sizeof buf, 0), off;
  DWORD w;
  if (n == 0)
    return 0;
  if (n < 0)
    return (WSAGetLastError() == WSAEWOULDBLOCK) ? 1 : -1;
  for (off = 0; off < n;) {
    if (!WriteFile(dst, buf + off, n - off, &w, NULL) || w == 0)
      return -1;
    off += (int)w;
  }
  return n;
}
static int pipe_to_sock(HANDLE src, SOCKET dst) {
  char buf[BUFSZ];
  DWORD n = 0;
  int off, w;
  if (!ReadFile(src, buf, sizeof buf, &n, NULL))
    return (GetLastError() == ERROR_BROKEN_PIPE) ? 0 : -1;
  if (n == 0)
    return 0;
  for (off = 0; off < (int)n;) {
    w = send(dst, buf + off, (int)n - off, 0);
    if (w <= 0)
      return -1;
    off += w;
  }
  return (int)n;
}

int main(int argc, char** argv) {
  WSADATA wsa;
  SOCKET net, appA;
  HANDLE pipe;
  const char* pipename;
  WSAPOLLFD p[2];
  int r, in_phase_a = 1;

  if (argc >= 2 && strcmp(argv[1], "--hello") == 0)
    return 7;
  if (argc < 5 || strcmp(argv[1], "--relay") != 0) {
    fprintf(stderr, "usage: %s --relay <net> <appA> <pipename>\n", argv[0]);
    return 2;
  }
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
    return 2;
  net = (SOCKET)(uintptr_t)_strtoui64(argv[2], NULL, 10);
  appA = (SOCKET)(uintptr_t)_strtoui64(argv[3], NULL, 10);
  pipename = argv[4];

  /* PHASE A: pump net <-> appA until the front closes appA (EOF = auth done). */
  while (in_phase_a) {
    p[0].fd = net;
    p[0].events = POLLRDNORM;
    p[0].revents = 0;
    p[1].fd = appA;
    p[1].events = POLLRDNORM;
    p[1].revents = 0;
    r = WSAPoll(p, 2, 15000);
    if (r <= 0)
      return 2;
    if (p[1].revents & (POLLRDNORM | POLLHUP)) {
      r = sock_to_sock(appA, net); /* front -> client */
      if (r == 0) {
        in_phase_a = 0; /* the cutover signal */
        break;
      }
      if (r < 0)
        return 3;
    }
    if (p[0].revents & (POLLRDNORM | POLLHUP)) {
      r = sock_to_sock(net, appA); /* client -> front */
      if (r <= 0)
        return 3;
    }
  }

  /* CUTOVER.  Do NOT read net now - any client bytes already waiting stay in
     the socket's receive buffer, unlost, until phase B resumes reading. */
  closesocket(appA);
  pipe = CreateNamedPipeA(pipename, PIPE_ACCESS_DUPLEX,
                          PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
                          65536, 65536, 0, NULL);
  if (pipe == INVALID_HANDLE_VALUE)
    return 3;
  if (!ConnectNamedPipe(pipe, NULL) &&
      GetLastError() != ERROR_PIPE_CONNECTED) {
    CloseHandle(pipe);
    return 3;
  }

  /* PHASE B: pump net <-> pipe.  net is a socket (WSAPoll); the pipe is drained
     by a short read whenever the socket is idle - a byte pipe with WSAPoll on
     one side is the shape the product relay would use (overlapped in earnest;
     here a poll on the socket plus a peeked pipe keeps it single-threaded). */
  for (;;) {
    DWORD avail = 0;
    p[0].fd = net;
    p[0].events = POLLRDNORM;
    p[0].revents = 0;
    r = WSAPoll(p, 1, 200);
    if (r < 0)
      return 3;
    if (r > 0 && (p[0].revents & (POLLRDNORM | POLLHUP))) {
      r = sock_to_pipe(net, pipe); /* client -> session */
      if (r == 0)
        break; /* client closed: clean end */
      if (r < 0)
        return 3;
    }
    if (PeekNamedPipe(pipe, NULL, 0, NULL, &avail, NULL) && avail > 0) {
      r = pipe_to_sock(pipe, net); /* session -> client */
      if (r == 0)
        break;
      if (r < 0)
        return 3;
    } else if (GetLastError() == ERROR_BROKEN_PIPE) {
      break; /* session closed */
    }
  }
  FlushFileBuffers(pipe);
  CloseHandle(pipe);
  closesocket(net);
  WSACleanup();
  return 0;
}
/* END-CODE */
