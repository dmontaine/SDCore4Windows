/* probe-relaylocal.c - UNELEVATED rehearsal of probe-relaydrop iteration 5.
 *
 * 16 Sep 26 Windows port, RELEASE_1.1 43.  Everything the elevated parent does
 * except the account switch, which iteration 3 already proved: an MSYS2 parent
 * (standing in for sd) makes a Cygwin-accepted socket and two Cygwin pipes,
 * launches the NATIVE probe-relaychild.exe under a LOW-integrity copy of the
 * caller's own token (no privilege needed), sends PING 1500 ms late, and checks
 * PONG, the child's RELAYED/GOT line, and that the child really ran at Low and
 * really waited.  It also keeps a Medium MSYS2 process - itself - alive for the
 * whole run, which is the condition that killed the MSYS2 child.
 *
 * Build and run from gplbld in MSYS2's MSYS bash (-lcygwin first, as ever):
 *   gcc -O2 -Wall -o probe-relaylocal.exe probe-relaylocal.c probe-cygsock-cyg.c -lcygwin -ladvapi32 -luserenv
 *   ./probe-relaylocal.exe          (probe-relaychild.exe must be built beside it)
 * Exit 0 all legs, 1 a leg failed, 2 could not run.
 *
 * MEASURED 16 Sep 2026, twice: exit 0.  Child at Low (0x1000); WSAPoll waited
 * 1500 ms on the Cygwin-accepted socket; PING read, PONG received by the
 * parent; RELAYED:PING-from-parent|GOT:PLAINTEXT-to-relay over the pipes.
 * NOT covered, by design: the child held the caller's 5 ordinary privileges
 * (the token is not stripped) and ran as the caller - the account switch and
 * strip are the elevated probe's, and iteration 3 proved them.  Its file create
 * in gplbld was refused (Medium directory, Low process) - expected.
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

static int dup_inh(HANDLE h, HANDLE* out) {
  return DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), out, 0,
                         TRUE, DUPLICATE_SAME_ACCESS);
}

int main(int argc, char** argv) {
  char self[MAX_PATH], dir[MAX_PATH], childexe[MAX_PATH + 32],
       cmd[MAX_PATH * 3];
  HANDLE t, low, sockInh, upW, downR;
  PSID lowsid = NULL;
  TOKEN_MANDATORY_LABEL tml;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  int acc, cli, up[2], down[2];
  char* slash;

  cygwin_conv_path(CCP_POSIX_TO_WIN_A, argv[0], self, sizeof self);
  snprintf(dir, sizeof dir, "%s", self);
  slash = strrchr(dir, '\\');
  if (slash)
    *slash = '\0';
  snprintf(childexe, sizeof childexe, "%s\\probe-relaychild.exe", dir);
  printf("child exe : %s\n", childexe);
  if (GetFileAttributesA(childexe) == INVALID_FILE_ATTRIBUTES) {
    printf("COULD NOT RUN: build probe-relaychild.exe first\n");
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

  if (cyg_pair(&acc, &cli) != 0 ||
      !dup_inh((HANDLE)cyg_osfhandle(acc), &sockInh) || pipe(up) != 0 ||
      pipe(down) != 0 || !dup_inh((HANDLE)_get_osfhandle(up[1]), &upW) ||
      !dup_inh((HANDLE)_get_osfhandle(down[0]), &downR)) {
    printf("COULD NOT RUN: socket/pipe setup errno %d win %lu\n", errno,
           (unsigned long)GetLastError());
    return 2;
  }
  snprintf(cmd, sizeof cmd, "\"%s\" --child \"%s\" %llu %llu %llu", childexe,
           dir, (unsigned long long)(uintptr_t)sockInh,
           (unsigned long long)(uintptr_t)upW, (unsigned long long)(uintptr_t)downR);
  printf("spawning  : %s  (Low copy of own token)\n", cmd);
  ZeroMemory(&si, sizeof si);
  si.cb = sizeof si;
  if (!CreateProcessAsUserA(low, childexe, cmd, NULL, NULL, TRUE,
                            CREATE_NO_WINDOW, NULL, dir, &si, &pi)) {
    printf("COULD NOT RUN: CreateProcessAsUser %lu\n", (unsigned long)GetLastError());
    return 2;
  }
  CloseHandle(sockInh);
  CloseHandle(upW);
  CloseHandle(downR);
  close(up[1]);
  close(down[0]);
  printf("parent    : closed its Cygwin fd of the connection (%d)\n", cyg_close(acc));
  printf("parent    : wrote %zd bytes sd->relay\n",
         write(down[1], "PLAINTEXT-to-relay", 18));
  close(down[1]);
  Sleep(1500);
  printf("parent    : sent %ld bytes PING (1500 ms late)\n",
         cyg_send(cli, "PING-from-parent"));
  char rb[64] = {0};
  long rn = cyg_recv(cli, rb, sizeof rb - 1, 10);
  int pong = rn > 0 && strcmp(rb, "PONG-from-child") == 0;
  printf("parent    : recv %ld [%s]\n", rn, rn > 0 ? rb : "");
  WaitForSingleObject(pi.hProcess, 30000);
  DWORD code = 99;
  GetExitCodeProcess(pi.hProcess, &code);
  printf("child exit: %lu\n", (unsigned long)code);

  static char pb[16384];
  ssize_t n, tot = 0;
  while (tot < (ssize_t)sizeof pb - 1 &&
         (n = read(up[0], pb + tot, sizeof pb - 1 - (size_t)tot)) > 0)
    tot += n;
  pb[tot > 0 ? tot : 0] = '\0';
  printf("--- child report (%zd bytes over the pipe) ---\n%s---\n", tot, pb);

  int isLow = strstr(pb, "integrity level   : Low") != NULL;
  int piped = strstr(pb, "RELAYED:PING-from-parent") && strstr(pb, "GOT:PLAINTEXT-to-relay");
  int waited = 0;
  char* w = strstr(pb, "socket wait");
  if (w) {
    char* a = strstr(w, "after ");
    if (a)
      waited = atoi(a + 6);
  }
  printf("low=%d pong=%d piped=%d waited_ms=%d\n", isLow, pong, piped, waited);
  if (!tot) {
    printf("VERDICT: COULD NOT RUN - the child reported nothing\n");
    return 2;
  }
  if (isLow && pong && piped && waited >= 500) {
    printf("VERDICT: NATIVE LOW RELAY HANDOVER WORKED (same account)\n");
    return 0;
  }
  printf("VERDICT: A LEG FAILED\n");
  return 1;
}
