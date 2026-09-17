/* probe-killzero.c - RELEASE_1.1 37: what does the MSYS2 runtime's kill(pid, 0)
 * answer for a session that has been KILLED, and does the answer depend on who
 * asks or on whether somebody still holds a handle to the dead process?
 *
 * 17 Sep 26 Windows port.  sdwind.c:262 decides "lost user" with
 *   kill(pid, 0) && errno != EPERM
 * and clopts.c:360 (sd -cleanup) with the same test.  On 15 Sep a killed
 * session's slot and record lock survived 5 m 45 s across the daemon's tick,
 * and neither site logged anything - so either kill() said "alive" to both,
 * or the daemon said "lost" and cleanup then disagreed.  This prints, for one
 * pid, everything both sites would need to know:
 *
 *   runtime    the msys-2.0.dll this process loaded - it MUST be SD's own
 *              (C:\Program Files\SD\usr\bin), because kill() consults the
 *              process table of the runtime it runs under, and a probe under
 *              C:\msys64's runtime would be asking a different table
 *   kill       kill(pid, 0): rc and errno, named
 *   /proc      whether /proc/<pid> exists - the runtime's own pid table
 *   native     OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION): does Windows
 *              still have a process OBJECT for the pid, is it STILL_ACTIVE or
 *              exited (and with what code), and what image it is.  A process
 *              that has been terminated keeps its object for as long as any
 *              handle to it is open - a Stop-Process caller's, a Get-Process
 *              object's - and that is the case this probe exists to tell
 *              apart from a live one.
 *
 * The driver (probe-killzero.ps1) runs it three ways - unelevated, elevated,
 * and as SYSTEM through a scheduled task, the daemon's own token - against a
 * session it started and killed, first WHILE it holds a handle to the dead
 * process and again AFTER releasing it, with a live pid and an absent pid as
 * controls.  Falsified-if kill() answers the same for a dead pid as for a
 * live one in the daemon's shape.
 *
 * Build from gplbld in MSYS2's MSYS bash (no -l needed):
 *   gcc -O2 -Wall -o probe-killzero.exe probe-killzero.c
 * and RUN it with SD's usr\bin first on PATH and no msys-2.0.dll beside it.
 *   probe-killzero.exe <pid> [<pid> ...]
 * Exit 0 printed, 2 could not (no pid, or the wrong runtime loaded).
 */
#include <windows.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/cygwin.h>

static const char* errname(int e) {
  switch (e) {
    case 0: return "0";
    case ESRCH: return "ESRCH";
    case EPERM: return "EPERM";
    case EINVAL: return "EINVAL";
    default: return "other";
  }
}

static void native(int pid) {
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  DWORD code = 0, err = GetLastError();
  char img[MAX_PATH] = "?";
  DWORD n = sizeof img;
  if (!h) {
    printf("  native    : OpenProcess FAILED %lu%s\n", (unsigned long)err,
           err == ERROR_INVALID_PARAMETER ? " (no such process object)" : err == ERROR_ACCESS_DENIED ? " (access denied)" : "");
    return;
  }
  if (!GetExitCodeProcess(h, &code)) code = 0xFFFFFFFF;
  if (!QueryFullProcessImageNameA(h, 0, img, &n)) strcpy(img, "(image unreadable)");
  if (code == STILL_ACTIVE)
    printf("  native    : process object EXISTS, STILL_ACTIVE, image %s\n", img);
  else
    printf("  native    : process object EXISTS but EXITED, code 0x%08lx, image %s - a TERMINATED process whose object some handle still keeps\n",
           (unsigned long)code, img);
  CloseHandle(h);
}

int main(int argc, char** argv) {
  char dll[MAX_PATH] = "?";
  HMODULE m = GetModuleHandleA("msys-2.0.dll");
  int i, ok = 1;

  if (m) GetModuleFileNameA(m, dll, sizeof dll);
  printf("probe-killzero\n");
  printf("  runtime   : %s\n", dll);
  printf("  as        : uid %d, euid %d, pid %d\n", (int)getuid(), (int)geteuid(), (int)getpid());
  if (strstr(dll, "\\SD\\usr\\bin\\") == NULL) {
    printf("REFUSED: this is not SD's runtime - kill() would consult the wrong process table.  Put C:\\Program Files\\SD\\usr\\bin first on PATH.\n");
    return 2;
  }
  if (argc < 2) { printf("usage: probe-killzero.exe <pid> [<pid> ...]\n"); return 2; }

  /* THIS RUNTIME'S pids ARE ITS OWN, NOT WINDOWS'S - measured 17 Sep 2026:
     three probe runs printed pids 883, 884, 885.  So uptr->pid is a Cygwin
     pid, kill() wants a Cygwin pid, and a Windows pid handed to it answers
     ESRCH for a process that is alive and well.  An argument written w<N> is
     a Windows pid and is converted here with cygwin_winpid_to_pid(), which
     can only succeed while the process lives - so a driver captures the
     Cygwin pid BEFORE it kills anything. */
  for (i = 1; i < argc; i++) {
    int pid, rc;
    char proc[64];
    if (argv[i][0] == 'w') {
      int win = atoi(argv[i] + 1);
      pid = (int)cygwin_winpid_to_pid(win);
      printf("== winpid %d -> cygwin pid %d%s\n", win, pid, pid < 0 ? " (no such Cygwin process in this runtime)" : "");
      if (pid < 0) { native(win); continue; }
    } else {
      pid = atoi(argv[i]);
    }
    if (pid <= 0) { printf("== pid %s: not a number\n", argv[i]); ok = 0; continue; }
    printf("== cygwin pid %d\n", pid);
    errno = 0;
    rc = kill(pid, 0);
    printf("  kill(pid,0): rc %d errno %d %s  -> sdwind.c:262 reads this as %s\n", rc, errno, errname(errno),
           (rc == 0 || errno == EPERM) ? "ALIVE" : "LOST");
    snprintf(proc, sizeof proc, "/proc/%d/winpid", pid);
    {
      FILE* f = fopen(proc, "r");
      int win = -1;
      if (f) { if (fscanf(f, "%d", &win) != 1) win = -1; fclose(f); }
      printf("  /proc     : %s%s", f ? "present" : "absent", f ? ", winpid " : "\n");
      if (f) { printf("%d\n", win); if (win > 0) native(win); }
    }
  }
  return ok ? 0 : 2;
}
