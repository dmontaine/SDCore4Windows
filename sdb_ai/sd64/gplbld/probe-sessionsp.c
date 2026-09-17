/* probe-sessionsp.c - UNELEVATED rehearsal: can a CYGWIN session that is
 * SPAWNED (CreateProcess), not fork()ed, use an inherited socketpair end -
 * placed on its standard handles - as the working bidirectional stream sd
 * needs on descriptors 0 and 1?
 *
 * 17 Sep 26 Windows port, RELEASE_1.1 55 direction (a), crux (1).  The owner
 * chose (a): spawn the authenticated API session AS THE USER
 * (CreateProcessAsUser) instead of fork()ing it from the LocalSystem daemon.
 * The one unproven crux is the connection handover.  sd's only channel to its
 * TLS relay is one end of a Cygwin socketpair(), which sd keeps on 0/1
 * (sd_tlssrv.c).  A fork() carries that fd across for free; a SPAWN does not,
 * and CreateProcessAsUser is a raw Win32 spawn - the runtime hands over
 * nothing, so the only thing that can reach the session is what is on its
 * inherited STANDARD HANDLES.  This measures whether that is enough.
 *
 * The account is NOT the variable under test - the Cygwin fd layer does not
 * depend on the token, and RELEASE_1.1 43 already spawned a Cygwin/native
 * child under a foreign S4U token (probe-relaydrop iteration 5).  What was
 * never measured is a SPAWNED CYGWIN child wrapping a socketpair end from its
 * std handles into a usable stream.  So this runs UNELEVATED with a plain
 * CreateProcess (same token): if the fd handover fails here it fails under
 * CreateProcessAsUser too, and if it holds here the only thing left to confirm
 * is that the user-token switch (already proven for the spawn itself) does not
 * disturb it - a small owner-elevated follow-up, not another design question.
 * This is the probe-relaysp / probe-relaylocal pattern: rehearse the fd layer
 * cheaply, leave the elevated confirmation to the owner.
 *
 * WHAT RUNS.  The parent stands in for sd's front and its relay: it makes a
 * Cygwin socketpair, raw-spawns probe-sessionsp-child.exe (a Cygwin program,
 * the session) with the session end on hStdInput/hStdOutput and the inheritance
 * restricted to exactly that handle and a NUL for stderr
 * (PROC_THREAD_ATTRIBUTE_HANDLE_LIST - without it every socket the parent holds
 * would cross, and the client's close would never reach the session, the trap
 * probe-relaysp measured), then drives the OTHER end as the relay would:
 *   1. RELAY->SESSION greeting line        - the session's READ leg
 *   2. SESSION->RELAY ack line             - the session's WRITE leg
 *   3. 256 KiB pushed and its echo drained - BULK, the full-buffer path
 *   4. the parent closes its end           - EOF, which sd must see as read 0
 * Exit 0 when the session read, wrote, echoed every byte in order and exited 0
 * on the clean EOF; 1 when a leg failed (the falsified-if: a spawned Cygwin
 * session cannot use the handed-over socketpair end); 2 when it could not run.
 * The child's own report file is echoed to stdout, so the verdict shows what
 * the session actually observed, not just the parent's conclusion.
 *
 * Build from gplbld in MSYS2's MSYS bash, -lcygwin first (this file mixes
 * windows.h with the Cygwin helpers in probe-sessionsp-cyg.c, each in its own
 * translation unit):
 *   gcc -O2 -Wall -o probe-sessionsp.exe probe-sessionsp.c probe-sessionsp-cyg.c -lcygwin
 *   ./probe-sessionsp.exe        (probe-sessionsp-child.exe must be built beside it)
 */
#include <windows.h>
#include <sys/cygwin.h>
#include <stdio.h>
#include <string.h>

/* Implemented in probe-sessionsp-cyg.c (the Cygwin translation unit). */
int cyg_socketpair(int* session_end, int* relay_end);
long cyg_osfhandle(int fd);
int cyg_close(int fd);
long cyg_write_line(int fd, const char* s);
long cyg_read_wait(int fd, char* buf, long n, int ms);
long cyg_bulk_echo(int fd, int* pattern_ok);
int cyg_fork_exec(int session_end, int relay_end, const char* exe,
                  const char* report);
int cyg_waitpid(int pid);

#define BULK_BYTES (256L * 1024L)

static int dup_inh(HANDLE h, HANDLE* out) {
  return DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), out, 0,
                         TRUE, DUPLICATE_SAME_ACCESS);
}

/* Legs 1-3, identical for both the spawn test and the fork control: greet on
   the relay end, read the ack, push and drain 256 KiB.  Leg 4 (close the end
   and read the child's exit) differs per mode and stays in main. */
static void drive_relay(int relay_end, int* ack_ok, int* bulk_ok) {
  char ackbuf[128];
  long r, echoed;
  int pat = 0;
  *ack_ok = 0;
  *bulk_ok = 0;
  r = cyg_write_line(relay_end, "RELAY->SESSION hello\n");
  printf("leg 1 greeting : wrote %ld bytes to the session\n", r);
  memset(ackbuf, 0, sizeof ackbuf);
  r = cyg_read_wait(relay_end, ackbuf, sizeof ackbuf - 1, 5000);
  if (r > 0) {
    ackbuf[strcspn(ackbuf, "\r\n")] = '\0';
    *ack_ok = (strcmp(ackbuf, "SESSION->RELAY ack") == 0);
    printf("leg 2 ack      : got \"%s\" %s\n", ackbuf,
           *ack_ok ? "OK" : "- UNEXPECTED");
  } else {
    printf("leg 2 ack      : FAILED r=%ld (%s)\n", r,
           r == -110 ? "timeout" : r == 0 ? "session closed early" : "error");
  }
  if (*ack_ok) {
    echoed = cyg_bulk_echo(relay_end, &pat);
    *bulk_ok = (echoed == BULK_BYTES && pat);
    printf("leg 3 bulk     : %ld of %ld bytes echoed, pattern %s -> %s\n",
           echoed, BULK_BYTES, pat ? "intact" : "CORRUPT",
           *bulk_ok ? "OK" : "FAILED");
  }
}

/* Echo the child's report file to stdout - the session's own observations. */
static void dump_report(const char* winpath) {
  FILE* f = fopen(winpath, "r");
  char line[1024];
  if (!f) {
    printf("  (no report file at %s)\n", winpath);
    return;
  }
  printf("  --- session's report ---\n");
  while (fgets(line, sizeof line, f))
    printf("  %s", line);
  if (line[strlen(line) - 1] != '\n')
    printf("\n");
  printf("  --- end report ---\n");
  fclose(f);
}

int main(int argc, char** argv) {
  char self[MAX_PATH], dir[MAX_PATH], childexe[MAX_PATH + 40];
  char reportwin[MAX_PATH + 40], reportfwd[MAX_PATH + 40], cmd[MAX_PATH * 3];
  HANDLE sessionH, sessionInh = NULL, nulErr = NULL;
  HANDLE list[2];
  STARTUPINFOEXA six;
  PROCESS_INFORMATION pi;
  SIZE_T alen = 0;
  SECURITY_ATTRIBUTES sa;
  int session_end = -1, relay_end = -1, rc;
  char* slash;
  DWORD code = 1;
  int ack_ok = 0, bulk_ok = 0, child_ok = 0;
  int forkctl = (argc >= 2 && strcmp(argv[1], "--forkctl") == 0);

  if (GetModuleFileNameA(NULL, self, sizeof self) == 0) {
    printf("COULD NOT RUN: GetModuleFileName %lu\n",
           (unsigned long)GetLastError());
    return 2;
  }
  snprintf(dir, sizeof dir, "%s", self);
  slash = strrchr(dir, '\\');
  if (slash)
    *slash = '\0';
  snprintf(childexe, sizeof childexe, "%s\\probe-sessionsp-child.exe", dir);
  snprintf(reportwin, sizeof reportwin, "%s\\probe-sessionsp-report.txt", dir);
  /* Forward slashes for the Cygwin child's fopen (mixed paths are accepted,
     but this keeps the arg free of a backslash the shell need not see). */
  snprintf(reportfwd, sizeof reportfwd, "%s", reportwin);
  for (slash = reportfwd; *slash; slash++)
    if (*slash == '\\')
      *slash = '/';

  printf("probe-sessionsp PARENT (MSYS2, standing in for sd's front + relay)\n");
  printf("mode      : %s\n", forkctl
             ? "FORK+EXEC CONTROL (sd's handover today - must PASS)"
             : "SPAWN TEST (CreateProcess, direction (a)'s handover)");
  printf("child exe : %s\n", childexe);
  printf("report    : %s\n", reportwin);
  if (GetFileAttributesA(childexe) == INVALID_FILE_ATTRIBUTES) {
    printf("COULD NOT RUN: build probe-sessionsp-child.exe first\n");
    return 2;
  }
  DeleteFileA(reportwin);

  rc = cyg_socketpair(&session_end, &relay_end);
  if (rc != 0) {
    printf("COULD NOT RUN: socketpair failed (%d)\n", rc);
    return 2;
  }

  /* THE CONTROL: hand the same child the same socketpair end the way sd does
     today - fork(), dup2 to 0/1, execl.  If this PASSES and the spawn test
     FAILS, the child code is sound and the difference is spawn-vs-fork. */
  if (forkctl) {
    int pid = cyg_fork_exec(session_end, relay_end, childexe, reportfwd);
    if (pid < 0) {
      printf("COULD NOT RUN: fork/exec %d\n", -pid);
      return 2;
    }
    cyg_close(session_end);
    session_end = -1;
    drive_relay(relay_end, &ack_ok, &bulk_ok);
    cyg_close(relay_end);
    relay_end = -1;
    code = (DWORD)cyg_waitpid(pid);
    child_ok = ((int)code == 0);
    printf("leg 4 EOF+exit : session exited %d %s\n", (int)code,
           child_ok ? "OK (clean EOF)" : "- did not reach a clean EOF");
    dump_report(reportwin);
    if (ack_ok && bulk_ok && child_ok) {
      printf("\nCONTROL PASS - the fork()+exec handover works, so the child "
             "code is sound and a FAIL of the spawn test is spawn-vs-fork, not "
             "the harness.\n");
      return 0;
    }
    printf("\nCONTROL FAILED (ack=%d bulk=%d exit=%d) - the harness itself is "
           "suspect; do not read the spawn test's FAIL as a product finding "
           "until this passes.\n",
           ack_ok, bulk_ok, child_ok);
    return 1;
  }

  sessionH = (HANDLE)cyg_osfhandle(session_end);
  if (sessionH == INVALID_HANDLE_VALUE || sessionH == NULL) {
    printf("COULD NOT RUN: no Windows handle behind the socketpair end\n");
    return 2;
  }

  /* The session end, inheritable, for the child's std handles. */
  if (!dup_inh(sessionH, &sessionInh)) {
    printf("COULD NOT RUN: DuplicateHandle(session end) %lu\n",
           (unsigned long)GetLastError());
    return 2;
  }
  /* An inheritable NUL for the child's stderr (USESTDHANDLES needs all three,
     and the child reports to a file, not stderr). */
  sa.nLength = sizeof sa;
  sa.lpSecurityDescriptor = NULL;
  sa.bInheritHandle = TRUE;
  nulErr = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &sa,
                       OPEN_EXISTING, 0, NULL);
  if (nulErr == INVALID_HANDLE_VALUE) {
    printf("COULD NOT RUN: open NUL %lu\n", (unsigned long)GetLastError());
    return 2;
  }

  ZeroMemory(&six, sizeof six);
  ZeroMemory(&pi, sizeof pi);
  six.StartupInfo.cb = sizeof six;
  six.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  six.StartupInfo.hStdInput = sessionInh;  /* fd 0 = the socketpair end */
  six.StartupInfo.hStdOutput = sessionInh; /* fd 1 = the same end (sd's dup2) */
  six.StartupInfo.hStdError = nulErr;

  /* Exactly the two handles cross, nothing else - the correctness point from
     win32relay.c, not hygiene: bInheritHandles alone copies every inheritable
     socket the parent holds. */
  list[0] = sessionInh;
  list[1] = nulErr;
  InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
  six.lpAttributeList =
      (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, alen);
  if (six.lpAttributeList == NULL ||
      !InitializeProcThreadAttributeList(six.lpAttributeList, 1, 0, &alen) ||
      !UpdateProcThreadAttribute(six.lpAttributeList, 0,
                                 PROC_THREAD_ATTRIBUTE_HANDLE_LIST, list,
                                 sizeof list, NULL, NULL)) {
    printf("COULD NOT RUN: handle list %lu\n", (unsigned long)GetLastError());
    return 2;
  }

  snprintf(cmd, sizeof cmd, "\"%s\" --stdio \"%s\"", childexe, reportfwd);
  if (!CreateProcessA(childexe, cmd, NULL, NULL, TRUE,
                      CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT, NULL, dir,
                      &six.StartupInfo, &pi)) {
    printf("COULD NOT RUN: CreateProcess %lu\n", (unsigned long)GetLastError());
    return 2;
  }
  CloseHandle(pi.hThread);
  /* The child holds the session end now.  The parent must let go of it, or the
     socketpair never sees the session's EOF and vice versa. */
  CloseHandle(sessionInh);
  sessionInh = NULL;
  cyg_close(session_end);
  session_end = -1;

  /* Drive the relay end, in order, no deadlock (ping, pong, then bulk). */
  drive_relay(relay_end, &ack_ok, &bulk_ok);

  /* Leg 4: close the relay end; the session's read() must return 0. */
  cyg_close(relay_end);
  relay_end = -1;

  if (WaitForSingleObject(pi.hProcess, 10000) == WAIT_OBJECT_0 &&
      GetExitCodeProcess(pi.hProcess, &code)) {
    child_ok = (code == 0);
    printf("leg 4 EOF+exit : session exited %lu %s\n", (unsigned long)code,
           child_ok ? "OK (clean EOF)" : "- did not reach a clean EOF");
  } else {
    printf("leg 4 EOF+exit : session did NOT exit within 10 s (EOF not seen)\n");
    TerminateProcess(pi.hProcess, 99);
  }
  CloseHandle(pi.hProcess);

  dump_report(reportwin);

  if (six.lpAttributeList) {
    DeleteProcThreadAttributeList(six.lpAttributeList);
    HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
  }
  if (nulErr && nulErr != INVALID_HANDLE_VALUE)
    CloseHandle(nulErr);

  if (ack_ok && bulk_ok && child_ok) {
    printf("\nVERDICT: PASS - a SPAWNED Cygwin session used the handed-over "
           "socketpair end on 0/1 as a working stream, both directions and a "
           "clean EOF.  Crux (1) of direction (a) holds at the fd layer; the "
           "only follow-up is the owner-elevated CreateProcessAsUser-as-user "
           "confirmation.\n");
    return 0;
  }
  printf("\nVERDICT: FAIL - the spawned Cygwin session could not use the "
         "handed-over socketpair end (ack=%d bulk=%d exit=%d).  This is the "
         "falsified-if: under (a) the session needs a different channel than an "
         "inherited socketpair on its std handles.\n",
         ack_ok, bulk_ok, child_ok);
  return 1;
}
/* END-CODE */
