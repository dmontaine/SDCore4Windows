/* probe-relaysp-child.c - the NATIVE relay stand-in for probe-relaysp.c: does
 * a Cygwin socketpair() end, handed over as an inherited handle, work as a
 * Winsock SOCKET in the relay - pollable with WSAPoll beside the accepted
 * network socket?
 *
 * 16 Sep 26 Windows port, RELEASE_1.1 43, product-build open point (c).  Every
 * earlier probe handed the relay<->sd channel over as two Cygwin pipe()s,
 * because a NATIVE pipe end adopted into Cygwin read EBADF (iteration 3).  A
 * pipe is not pollable, so the product relay would need a thread per direction
 * or overlapped I/O - the one open point with no Linux answer to copy.  Nobody
 * measured the third shape: sd keeps the socketpair it has today (Linux's
 * shape, and what sd's SIGIO code already runs on) and the relay gets the OTHER
 * END as a SOCKET.  msys-2.0 implements AF_UNIX over loopback TCP, so the
 * handle SHOULD be a real socket - this measures it rather than assumes it.
 *
 * Launched by probe-relaysp.exe at Low integrity:
 *   probe-relaysp-child.exe --hello                    exit 7: it initialised
 *   probe-relaysp-child.exe --relay <net> <sp> <report>
 * <net> is an inherited duplicate of a Cygwin-ACCEPTED TCP socket (the client
 * connection, as sd holds it); <sp> is an inherited duplicate of one end of a
 * Cygwin socketpair(); <report> is an inherited Cygwin pipe write end.  The
 * child answers the socket question, then runs THE RELAY LOOP THE PRODUCT
 * WOULD RUN, minus TLS: WSAPoll on both, copy net->sp and sp->net until either
 * side ends.  Exit 0 when both were sockets and the loop ended on EOF; 3 when
 * one handle was not a SOCKET (the falsified-if); 2 for anything else.
 *
 * Build NATIVE, from gplbld in an MSYS2 UCRT64 bash:
 *   gcc -O2 -Wall -o probe-relaysp-child.exe probe-relaysp-child.c -lws2_32
 * then check objdump -p shows no msys-2.0.dll.
 */
#include <winsock2.h>
#include <windows.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static HANDLE report = NULL;

static void say(const char* fmt, ...) {
  va_list ap;
  char line[1024];
  int n;
  DWORD w;
  va_start(ap, fmt);
  n = vsnprintf(line, sizeof line - 1, fmt, ap);
  va_end(ap);
  if (n < 0 || !report)
    return;
  if (n > (int)sizeof line - 2)
    n = (int)sizeof line - 2;
  line[n++] = '\n';
  WriteFile(report, line, (DWORD)n, &w, NULL);
}

static const char* integrity_level(void) {
  static char out[64];
  HANDLE t;
  BYTE buf[256];
  DWORD len = 0, rid;
  snprintf(out, sizeof out, "unknown");
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t))
    return out;
  if (GetTokenInformation(t, TokenIntegrityLevel, buf, sizeof buf, &len)) {
    PSID s = ((TOKEN_MANDATORY_LABEL*)buf)->Label.Sid;
    rid = *GetSidSubAuthority(s, *GetSidSubAuthorityCount(s) - 1);
    snprintf(out, sizeof out, "%s (0x%lx)",
             rid < SECURITY_MANDATORY_LOW_RID      ? "Untrusted"
             : rid < SECURITY_MANDATORY_MEDIUM_RID ? "Low"
             : rid < SECURITY_MANDATORY_HIGH_RID   ? "Medium"
             : rid < SECURITY_MANDATORY_SYSTEM_RID ? "High"
                                                   : "System",
             (unsigned long)rid);
  }
  CloseHandle(t);
  return out;
}

/* THE QUESTION: is this handle a socket Winsock will work with?  Three
   independent answers, printed each: getsockopt(SO_TYPE) (10038 WSAENOTSOCK is
   the no), WSAPoll on it, and a zero-timeout WSARecv (10035 says non-blocking
   and empty, the accepted-socket behaviour probe-cygsock measured). */
static int is_socket(const char* label, SOCKET s) {
  int type = -1, tl = sizeof type, ok = 1;
  WSAPOLLFD p;
  char b[8];
  int r;

  if (getsockopt(s, SOL_SOCKET, SO_TYPE, (char*)&type, &tl) == 0)
    say("  %-10s SO_TYPE          : %d (%s)", label, type,
        type == SOCK_STREAM ? "SOCK_STREAM" : "not a stream");
  else {
    say("  %-10s SO_TYPE          : FAILED err %d%s", label, WSAGetLastError(),
        WSAGetLastError() == WSAENOTSOCK ? " = WSAENOTSOCK, NOT A SOCKET" : "");
    ok = 0;
  }
  p.fd = s;
  p.events = POLLRDNORM;
  p.revents = 0;
  r = WSAPoll(&p, 1, 0);
  say("  %-10s WSAPoll(0 ms)    : %d revents=0x%x err=%d", label, r, p.revents,
      r < 0 ? WSAGetLastError() : 0);
  if (r < 0)
    ok = 0;
  r = recv(s, b, sizeof b, 0);
  say("  %-10s recv(empty)      : %d err=%d%s", label, r,
      r < 0 ? WSAGetLastError() : 0,
      r < 0 && WSAGetLastError() == WSAEWOULDBLOCK ? " = non-blocking, empty"
                                                    : "");
  return ok;
}

/* The product's relay() loop, minus TLS: copy both ways until either side
   ends.  Returns 0 on a clean EOF, 2 on an error. */
static int relay(SOCKET net, SOCKET sp) {
  char buf[16384];
  long net_to_sp = 0, sp_to_net = 0;
  int rounds = 0;

  for (;;) {
    WSAPOLLFD p[2];
    int r, i;

    p[0].fd = net;
    p[0].events = POLLRDNORM;
    p[0].revents = 0;
    p[1].fd = sp;
    p[1].events = POLLRDNORM;
    p[1].revents = 0;
    r = WSAPoll(p, 2, 10000);
    if (r < 0) {
      say("  relay WSAPoll FAILED err %d", WSAGetLastError());
      return 2;
    }
    if (r == 0) {
      /* DIAGNOSTIC, kept from run 1: the network side had closed and WSAPoll
         did not wake.  recv() directly on each socket tells "the FIN never
         arrived" (10035) from "it arrived and WSAPoll did not report it" (0).
         Run 1 said 10035 - the parent's spawn had let the child inherit the
         client end itself (see probe-relaysp.c); with the handle list the
         line is not reached. */
      int n1, e1, n2, e2;
      n1 = recv(net, buf, sizeof buf, 0);
      e1 = n1 < 0 ? WSAGetLastError() : 0;
      n2 = recv(sp, buf, sizeof buf, 0);
      e2 = n2 < 0 ? WSAGetLastError() : 0;
      say("  relay WSAPoll: 10 s with nothing to do - giving up; direct recv "
          "net=%d err=%d, sp=%d err=%d (0 = EOF was there, 10035 = nothing)",
          n1, e1, n2, e2);
      return 2;
    }
    rounds++;
    for (i = 0; i < 2; i++) {
      SOCKET from = p[i].fd, to = i == 0 ? sp : net;
      int n;
      if (!(p[i].revents & (POLLRDNORM | POLLHUP | POLLERR)))
        continue;
      n = recv(from, buf, sizeof buf, 0);
      if (n == 0) {
        say("  relay: %s ended (EOF) after %d poll rounds; net->sp %ld bytes, "
            "sp->net %ld bytes", i == 0 ? "net" : "sp", rounds, net_to_sp,
            sp_to_net);
        return 0;
      }
      if (n < 0) {
        if (WSAGetLastError() == WSAEWOULDBLOCK)
          continue;
        say("  relay: recv on %s FAILED err %d", i == 0 ? "net" : "sp",
            WSAGetLastError());
        return 2;
      }
      {
        int off = 0;
        while (off < n) {
          int w = send(to, buf + off, n - off, 0);
          if (w < 0) {
            if (WSAGetLastError() == WSAEWOULDBLOCK) {
              WSAPOLLFD wp;
              wp.fd = to;
              wp.events = POLLWRNORM;
              wp.revents = 0;
              WSAPoll(&wp, 1, 5000);
              continue;
            }
            say("  relay: send to %s FAILED err %d", i == 0 ? "sp" : "net",
                WSAGetLastError());
            return 2;
          }
          off += w;
        }
      }
      if (i == 0)
        net_to_sp += n;
      else
        sp_to_net += n;
      /* Short messages are echoed; bulk is counted (the tally is in the EOF
         line), or 256 KiB of pattern buries the verdict. */
      if (n < 64) {
        buf[n] = '\0';
        say("  relay: %s -> %s %d bytes [%s]", i == 0 ? "net" : "sp",
            i == 0 ? "sp" : "net", n, buf);
      }
    }
  }
}

int main(int argc, char* argv[]) {
  SOCKET net, sp;
  WSADATA wsa;
  int rc, netok, spok;

  if (argc == 2 && strcmp(argv[1], "--hello") == 0)
    return 7;
  if (argc != 5 || strcmp(argv[1], "--relay") != 0) {
    printf("usage: probe-relaysp-child.exe --hello | --relay <net> <sp> <report>\n");
    return 2;
  }
  net = (SOCKET)(uintptr_t)strtoull(argv[2], NULL, 10);
  sp = (SOCKET)(uintptr_t)strtoull(argv[3], NULL, 10);
  report = (HANDLE)(uintptr_t)strtoull(argv[4], NULL, 10);

  say("probe-relaysp-child (native)");
  say("  integrity level   : %s", integrity_level());
  say("  handles           : net %llu, sp %llu, report %llu",
      (unsigned long long)net, (unsigned long long)sp,
      (unsigned long long)(uintptr_t)report);
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    say("REFUSED: WSAStartup failed %d", WSAGetLastError());
    CloseHandle(report);
    return 2;
  }
  netok = is_socket("net", net);
  spok = is_socket("socketpair", sp);
  say("  VERDICT socketpair end is a SOCKET: %s", spok ? "YES" : "NO");
  if (!netok || !spok) {
    say("CHILD DONE exit 3 - a handle was not a socket, the relay loop is not attempted");
    CloseHandle(report);
    return 3;
  }
  rc = relay(net, sp);
  closesocket(net);
  closesocket(sp);
  say("CHILD DONE exit %d", rc);
  CloseHandle(report);
  return rc;
}
