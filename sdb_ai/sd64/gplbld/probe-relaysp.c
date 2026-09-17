/* probe-relaysp.c - UNELEVATED: does a Cygwin socketpair() end, handed to the
 * NATIVE relay as an inherited handle, work as a Winsock SOCKET - pollable
 * beside the accepted network socket, both directions, EOF propagated?
 *
 * 16 Sep 26 Windows port, RELEASE_1.1 43, product-build open point (c): "the
 * relay multiplexes a pollable socket with non-pollable pipes - a thread per
 * direction or overlapped I/O, and this one has no Linux answer to copy."  That
 * is only true if the relay<->sd channel has to be a pipe.  It was made a pipe
 * in iteration 3 because a NATIVE pipe end adopted into Cygwin read EBADF; the
 * shape nobody measured is the one sd already has - sd keeps its socketpair
 * end as descriptors 0 and 1 (Linux's shape, what sd_tlssrv.c and sd's SIGIO
 * code already run on) and the relay gets the OTHER END as a SOCKET.  msys-2.0
 * builds AF_UNIX on loopback TCP, so the handle should be a real socket.
 *
 * If it is, the product relay is Linux's relay() with WSAPoll in place of
 * poll(): one loop, two sockets, no threads, and sd_tls_relay_start()'s
 * sd-side code (the socketpair, the dup2 to 0 and 1, the 32-byte binding
 * preamble read) survives unchanged.  Falsified-if: the child's getsockopt on
 * the socketpair end answers WSAENOTSOCK, or WSAPoll refuses it, or bytes do
 * not cross in both directions, or sd does not see EOF when the client closes.
 *
 * What runs: an MSYS2 parent (standing in for sd) makes a Cygwin socketpair
 * and a Cygwin-accepted loopback TCP connection, hands the relay end and the
 * accepted socket to probe-relaysp-child.exe launched at LOW integrity under a
 * copy of its own token (no privilege needed; iteration 3/5 own the account
 * switch), and then drives traffic as the network and as sd:
 *   1. network -> relay -> sd : one line, sent 1500 ms late so the child's
 *                              first wait is on two EMPTY sockets
 *   2. sd -> relay -> network : one line
 *   3. sd -> relay -> network : 256 KiB, poll-driven, so the relay's
 *                              WSAEWOULDBLOCK/POLLWRNORM path is exercised
 *   4. the network closes     : sd's read must return EOF, the child exit 0
 * The child reports over a Cygwin pipe (the iteration-5 channel, proven).
 *
 * Build and run from gplbld in MSYS2's MSYS bash (-lcygwin first, as ever):
 *   gcc -O2 -Wall -o probe-relaysp.exe probe-relaysp.c probe-relaysp-cyg.c probe-cygsock-cyg.c -lcygwin -ladvapi32
 *   ./probe-relaysp.exe          (probe-relaysp-child.exe must be built beside it)
 * Exit 0 every leg, 1 a leg failed (read which), 2 could not run.
 *
 * MEASURED 16 Sep 2026, unelevated.  RUN 1: legs 1-3 OK, LEG 4 FAILED - the
 * child's WSAPoll slept 10 s after the network end closed, and its direct
 * recv() said 10035: THE FIN NEVER ARRIVED.  Cause, printed by run 2: every
 * Cygwin socket handle carries HANDLE_FLAG_INHERIT, so bInheritHandles=TRUE
 * had copied the CLIENT END into the child too, and a socket with a live
 * handle elsewhere does not close.  RUNS 2 AND 3, with the inheritance
 * restricted to the three named handles (PROC_THREAD_ATTRIBUTE_HANDLE_LIST):
 * exit 0 - socketpair end SO_TYPE SOCK_STREAM, WSAPoll accepts it, both
 * directions, 262144 of 262144 bulk bytes intact, EOF reached sd (read 0) and
 * the child exited 0.  Run 1 is the control that says the handle list is not
 * optional in the product: without it the Low relay holds every socket sd
 * holds, and a client's close never reaches sd.
 */
#include <windows.h>
#include <sddl.h>
#include <sys/cygwin.h>
#include <io.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int cyg_pair(int* accepted, int* client);
long cyg_osfhandle(int fd);
int cyg_close(int fd);
long cyg_send(int fd, const char* s);
long cyg_recv(int fd, char* buf, long n, int secs);
int cyg_socketpair(int* sd_end, int* relay_end);
long cyg_write(int fd, const char* s);
long cyg_read_wait(int fd, char* buf, long n, int ms);
long cyg_bulk(int wr_fd, int rd_fd, long total, int* pattern_ok);

#define BULK_BYTES (256L * 1024L)

static int dup_inh(HANDLE h, HANDLE* out) {
  return DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), out, 0,
                         TRUE, DUPLICATE_SAME_ACCESS);
}

int main(int argc, char** argv) {
  char self[MAX_PATH], dir[MAX_PATH], childexe[MAX_PATH + 32],
       cmd[MAX_PATH * 3];
  HANDLE t, low, netInh, spInh, repW;
  PSID lowsid = NULL;
  TOKEN_MANDATORY_LABEL tml;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  int acc, cli, sd_end, relay_end, rep[2], rc;
  char* slash;
  int leg1 = 0, leg2 = 0, leg3 = 0, leg4 = 0;

  cygwin_conv_path(CCP_POSIX_TO_WIN_A, argv[0], self, sizeof self);
  snprintf(dir, sizeof dir, "%s", self);
  slash = strrchr(dir, '\\');
  if (slash)
    *slash = '\0';
  snprintf(childexe, sizeof childexe, "%s\\probe-relaysp-child.exe", dir);
  printf("probe-relaysp PARENT (MSYS2, standing in for sd)\n");
  printf("child exe : %s\n", childexe);
  if (GetFileAttributesA(childexe) == INVALID_FILE_ATTRIBUTES) {
    printf("COULD NOT RUN: build probe-relaysp-child.exe first\n");
    return 2;
  }

  if (!OpenProcessToken(GetCurrentProcess(),
                        TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ADJUST_DEFAULT |
                            TOKEN_ASSIGN_PRIMARY, &t) ||
      !DuplicateTokenEx(t, 0, NULL, SecurityImpersonation, TokenPrimary, &low) ||
      !ConvertStringSidToSidA("S-1-16-4096", &lowsid)) {
    printf("COULD NOT RUN: token setup %lu\n", (unsigned long)GetLastError());
    return 2;
  }
  tml.Label.Attributes = SE_GROUP_INTEGRITY;
  tml.Label.Sid = lowsid;
  if (!SetTokenInformation(low, TokenIntegrityLevel, &tml,
                           sizeof tml + GetLengthSid(lowsid))) {
    printf("COULD NOT RUN: Low label %lu\n", (unsigned long)GetLastError());
    return 2;
  }

  rc = cyg_socketpair(&sd_end, &relay_end);
  if (rc != 0) {
    printf("COULD NOT RUN: socketpair errno %d\n", -rc);
    return 2;
  }
  if (cyg_pair(&acc, &cli) != 0 || pipe(rep) != 0) {
    printf("COULD NOT RUN: loopback pair / report pipe errno %d\n", errno);
    return 2;
  }
  if (!dup_inh((HANDLE)cyg_osfhandle(acc), &netInh) ||
      !dup_inh((HANDLE)cyg_osfhandle(relay_end), &spInh) ||
      !dup_inh((HANDLE)_get_osfhandle(rep[1]), &repW)) {
    printf("COULD NOT RUN: DuplicateHandle %lu\n", (unsigned long)GetLastError());
    return 2;
  }
  printf("socketpair: sd end fd %d, relay end fd %d -> handle %ld -> inheritable %llu\n",
         sd_end, relay_end, cyg_osfhandle(relay_end),
         (unsigned long long)(uintptr_t)spInh);
  printf("network   : accepted fd %d -> handle %ld -> inheritable %llu\n", acc,
         cyg_osfhandle(acc), (unsigned long long)(uintptr_t)netInh);

  /* RUN 1 FOUND LEG 4 FAILING WITH THE FIN NEVER ARRIVING: the child's direct
     recv on the network socket said 10035 after sd's stand-in had close()d the
     client end.  Cygwin's socket handles are INHERITABLE, so a plain
     bInheritHandles=TRUE gave the child a copy of EVERY one - the client end
     included - and a socket with a live handle in another process does not
     close.  Printed here so the run shows it, and the product does what
     sdclilib already does (HISTORY.md, PROC_THREAD_ATTRIBUTE_HANDLE_LIST):
     inherit exactly the three handles named. */
  {
    DWORD fl;
    int fds[4] = {cli, sd_end, acc, relay_end};
    const char* nm[4] = {"client end", "sd end", "accepted", "relay end"};
    int i;
    for (i = 0; i < 4; i++) {
      fl = 0;
      GetHandleInformation((HANDLE)cyg_osfhandle(fds[i]), &fl);
      printf("inherit   : %-10s handle %ld HANDLE_FLAG_INHERIT=%d\n", nm[i],
             cyg_osfhandle(fds[i]), (fl & HANDLE_FLAG_INHERIT) ? 1 : 0);
    }
  }

  snprintf(cmd, sizeof cmd, "\"%s\" --relay %llu %llu %llu", childexe,
           (unsigned long long)(uintptr_t)netInh,
           (unsigned long long)(uintptr_t)spInh,
           (unsigned long long)(uintptr_t)repW);
  printf("spawning  : %s  (Low copy of own token, handle list of 3)\n", cmd);
  {
    STARTUPINFOEXA six;
    SIZE_T alen = 0;
    HANDLE list[3];
    list[0] = netInh;
    list[1] = spInh;
    list[2] = repW;
    ZeroMemory(&six, sizeof six);
    six.StartupInfo.cb = sizeof six;
    InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
    six.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(
        GetProcessHeap(), 0, alen);
    if (!six.lpAttributeList ||
        !InitializeProcThreadAttributeList(six.lpAttributeList, 1, 0, &alen) ||
        !UpdateProcThreadAttribute(six.lpAttributeList, 0,
                                   PROC_THREAD_ATTRIBUTE_HANDLE_LIST, list,
                                   sizeof list, NULL, NULL)) {
      printf("COULD NOT RUN: attribute list %lu\n", (unsigned long)GetLastError());
      return 2;
    }
    if (!CreateProcessAsUserA(low, childexe, cmd, NULL, NULL, TRUE,
                              CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT,
                              NULL, dir, &six.StartupInfo, &pi)) {
      printf("COULD NOT RUN: CreateProcessAsUser %lu\n",
             (unsigned long)GetLastError());
      return 2;
    }
    DeleteProcThreadAttributeList(six.lpAttributeList);
    HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
  }
  (void)si;
  /* The child is now the only holder of the relay end and the connection -
     exactly what sd_tls_relay_start() does with close(sp[1]) and the dup2. */
  CloseHandle(netInh);
  CloseHandle(spInh);
  CloseHandle(repW);
  close(rep[1]);
  printf("parent    : closed relay end (%d) and its fd of the connection (%d)\n",
         cyg_close(relay_end), cyg_close(acc));

  /* Leg 1: network -> sd, sent late so the child is waiting on empty sockets. */
  Sleep(1500);
  {
    char rb[64] = {0};
    long rn;
    printf("parent    : sent %ld bytes on the network end (1500 ms late)\n",
           cyg_send(cli, "HELLO-from-network"));
    rn = cyg_read_wait(sd_end, rb, sizeof rb - 1, 10000);
    leg1 = rn > 0 && strcmp(rb, "HELLO-from-network") == 0;
    printf("leg 1     : sd read %ld [%s] %s\n", rn, rn > 0 ? rb : "",
           leg1 ? "OK" : "FAILED");
  }

  /* Leg 2: sd -> network. */
  {
    char rb[64] = {0};
    long rn;
    printf("parent    : sd wrote %ld bytes\n", cyg_write(sd_end, "HELLO-from-sd"));
    rn = cyg_recv(cli, rb, sizeof rb - 1, 10);
    leg2 = rn > 0 && strcmp(rb, "HELLO-from-sd") == 0;
    printf("leg 2     : network read %ld [%s] %s\n", rn, rn > 0 ? rb : "",
           leg2 ? "OK" : "FAILED");
  }

  /* Leg 3: bulk sd -> network, single-threaded and poll-driven, so the
     relay's send side must block-and-retry rather than lose bytes. */
  {
    int pat = 0;
    long got = cyg_bulk(sd_end, cli, BULK_BYTES, &pat);
    leg3 = got == BULK_BYTES && pat;
    printf("leg 3     : bulk sd -> network %ld of %ld bytes, pattern %s: %s\n",
           got, BULK_BYTES, pat ? "intact" : "CORRUPT", leg3 ? "OK" : "FAILED");
  }

  /* Leg 4: the network closes; sd must see EOF and the child must exit 0. */
  {
    char rb[8];
    long rn;
    DWORD code = 99;
    cyg_close(cli);
    rn = cyg_read_wait(sd_end, rb, sizeof rb, 10000);
    printf("parent    : after network close, sd read %ld (0 is EOF)\n", rn);
    WaitForSingleObject(pi.hProcess, 15000);
    GetExitCodeProcess(pi.hProcess, &code);
    printf("child exit: %lu\n", (unsigned long)code);
    leg4 = rn == 0 && code == 0;
    printf("leg 4     : EOF to sd and child exit 0: %s\n", leg4 ? "OK" : "FAILED");
    if (code == 3)
      printf("            exit 3 = the child said a handle was NOT a socket\n");
  }
  cyg_close(sd_end);

  {
    static char pb[65536];
    ssize_t n, tot = 0;
    int isLow, isSock;
    while (tot < (ssize_t)sizeof pb - 1 &&
           (n = read(rep[0], pb + tot, sizeof pb - 1 - (size_t)tot)) > 0)
      tot += n;
    pb[tot > 0 ? tot : 0] = '\0';
    printf("--- child report (%zd bytes over the pipe) ---\n%s---\n", tot, pb);
    if (!tot) {
      printf("VERDICT: COULD NOT RUN - the child reported nothing\n");
      return 2;
    }
    isLow = strstr(pb, "integrity level   : Low") != NULL;
    isSock = strstr(pb, "VERDICT socketpair end is a SOCKET: YES") != NULL;
    printf("low=%d socket=%d leg1=%d leg2=%d leg3=%d leg4=%d\n", isLow, isSock,
           leg1, leg2, leg3, leg4);
    if (isLow && isSock && leg1 && leg2 && leg3 && leg4) {
      printf("VERDICT: A CYGWIN SOCKETPAIR END IS A POLLABLE SOCKET IN THE NATIVE LOW RELAY - "
             "both directions, %ld bytes bulk, EOF propagated\n", BULK_BYTES);
      return 0;
    }
    if (!isSock) {
      printf("VERDICT: FALSIFIED - the socketpair end is not a Winsock socket; "
             "the relay<->sd channel stays a pipe\n");
      return 1;
    }
    printf("VERDICT: A LEG FAILED\n");
    return 1;
  }
}
