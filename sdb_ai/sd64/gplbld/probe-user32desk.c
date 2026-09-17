/* probe-user32desk.c - UNELEVATED: does sdtlsrelay.exe start when its process
 * has NO reachable desktop - the condition it meets on every install?
 *
 * 16 Sep 26 Windows port, RELEASE_1.1 43.  The second cycle of the relay build
 * installed clean, the account minted, CreateProcessAsUser succeeded - and the
 * relay died before its first instruction: syslog (the Application event log,
 * provider sd_Log) said "relay could not initialise (0xC0000142)".  Its imports
 * were all system DLLs, and probe-relaychild.exe with the SAME spawn had run at
 * Low as the bare account (iteration 5).  The one difference in the import
 * tables: the static OpenSSL pulled USER32 (GetProcessWindowStation,
 * GetUserObjectInformationW, MessageBoxW - OPENSSL_isservice/showfatal), and
 * USER32's own initialisation connects the process to a window station.  A bare
 * account's token from a fresh S4U logon session has no right to session 0's
 * WinSta0\Default; USER32 cannot connect; STATUS_DLL_INIT_FAILED.
 *
 * RUN 1 (the unfixed relay, 16 Sep 22:50): on winsta0\default relay exit 6 and
 * probe-relaysp-child exit 7 (their usage codes); on winsta0\zz-no-such-desktop
 * the relay died 0xC0000142 and the child still exited 7.  MECHANISM REPRODUCED
 * without a bare account.  The relay then had its three USER32 imports
 * satisfied by local stubs (sdtlsrelay.c), and this probe became the
 * regression check below.
 *
 * WHAT IT MEASURES NOW, all under a Low copy of the caller's own token:
 *   control A  whoami.exe (imports USER32) on the unreachable desktop dies
 *              0xC0000142 - so the desktop really is unreachable and really
 *              kills a USER32 importer.  Without this row a relay that "ran"
 *              could have run because the desktop was fine.
 *   control B  whoami.exe on winsta0\default exits 0.
 *   subject    sdtlsrelay.exe (no args, usage exit 6) on BOTH desktops exits
 *              6 - it no longer needs a desktop to start.
 *   import     objdump is not run here; stage.py's NATIVE_ONLY refuses a relay
 *              that imports USER32, on every build.
 *
 * Build and run from gplbld in MSYS2's MSYS bash:
 *   gcc -O2 -Wall -o probe-user32desk.exe probe-user32desk.c -ladvapi32
 *   ./probe-user32desk.exe
 * Exit 0 the relay starts without a desktop (controls held), 1 it does not,
 * 2 could not run (a control did not behave).
 */
#include <windows.h>
#include <sddl.h>
#include <sys/cygwin.h>
#include <stdio.h>
#include <string.h>

static DWORD run(HANDLE tok, const char* exe, const char* args, const char* desk,
                 const char* cwd) {
  char cmd[MAX_PATH * 2];
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  DWORD code = 0xFFFFFFF0UL;
  snprintf(cmd, sizeof cmd, "\"%s\" %s", exe, args);
  ZeroMemory(&si, sizeof si);
  si.cb = sizeof si;
  si.lpDesktop = (char*)desk;
  if (!CreateProcessAsUserA(tok, exe, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                            NULL, cwd, &si, &pi)) {
    printf("    CreateProcessAsUser FAILED %lu\n", (unsigned long)GetLastError());
    return code;
  }
  if (WaitForSingleObject(pi.hProcess, 15000) == WAIT_TIMEOUT) {
    TerminateProcess(pi.hProcess, 99);
    code = 0xFFFFFFF1UL;
  } else {
    GetExitCodeProcess(pi.hProcess, &code);
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return code;
}

static const char* tag(DWORD c) {
  return c == 0xC0000142UL ? "  = DLL INIT FAILED" : "";
}

int main(int argc, char** argv) {
  char self[MAX_PATH], dir[MAX_PATH], relay[MAX_PATH + 40];
  const char* whoami = "C:\\Windows\\System32\\whoami.exe";
  const char* good = "winsta0\\default";
  const char* bad = "winsta0\\zz-no-such-desktop";
  HANDLE t, low;
  PSID lowsid = NULL;
  TOKEN_MANDATORY_LABEL tml;
  DWORD a, b, r_good, r_bad;
  char* slash;
  (void)argc;

  cygwin_conv_path(CCP_POSIX_TO_WIN_A, argv[0], self, sizeof self);
  snprintf(dir, sizeof dir, "%s", self);
  slash = strrchr(dir, '\\');
  if (slash) *slash = '\0';
  snprintf(relay, sizeof relay, "%s\\..\\bin\\sdtlsrelay.exe", dir);
  printf("probe-user32desk\n  subject           : %s\n  control (USER32)  : %s\n", relay, whoami);
  if (GetFileAttributesA(relay) == INVALID_FILE_ATTRIBUTES) {
    printf("COULD NOT RUN: build the relay first (make sdtlsrelay)\n");
    return 2;
  }
  if (!OpenProcessToken(GetCurrentProcess(),
                        TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ADJUST_DEFAULT |
                            TOKEN_ASSIGN_PRIMARY, &t) ||
      !DuplicateTokenEx(t, 0, NULL, SecurityImpersonation, TokenPrimary, &low) ||
      !ConvertStringSidToSidA("S-1-16-4096", &lowsid)) {
    printf("COULD NOT RUN: token %lu\n", (unsigned long)GetLastError());
    return 2;
  }
  tml.Label.Attributes = SE_GROUP_INTEGRITY;
  tml.Label.Sid = lowsid;
  if (!SetTokenInformation(low, TokenIntegrityLevel, &tml, sizeof tml + GetLengthSid(lowsid))) {
    printf("COULD NOT RUN: Low label %lu\n", (unsigned long)GetLastError());
    return 2;
  }

  a = run(low, whoami, "", bad, dir);
  printf("  control A  whoami on %s : exit 0x%08lx%s\n", bad, (unsigned long)a, tag(a));
  b = run(low, whoami, "", good, dir);
  printf("  control B  whoami on %s            : exit 0x%08lx%s\n", good, (unsigned long)b, tag(b));
  r_good = run(low, relay, "", good, dir);
  printf("  subject    relay  on %s            : exit %lu (0x%08lx)%s (usage is 6)\n", good,
         (unsigned long)r_good, (unsigned long)r_good, tag(r_good));
  r_bad = run(low, relay, "", bad, dir);
  printf("  subject    relay  on %s : exit %lu (0x%08lx)%s (usage is 6)\n", bad,
         (unsigned long)r_bad, (unsigned long)r_bad, tag(r_bad));

  if (a != 0xC0000142UL || b != 0) {
    printf("VERDICT: COULD NOT RUN - the controls did not behave (A 0x%08lx, B 0x%08lx); the desktop trick does not hold here\n",
           (unsigned long)a, (unsigned long)b);
    return 2;
  }
  if (r_good == 6 && r_bad == 6) {
    printf("VERDICT: THE RELAY STARTS WITHOUT A REACHABLE DESKTOP (a USER32 importer beside it died)\n");
    return 0;
  }
  printf("VERDICT: THE RELAY NEEDS A DESKTOP - it would die on every install (0xC0000142 in syslog)\n");
  return 1;
}
