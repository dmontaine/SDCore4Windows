/* probe-pipestd.c - UNELEVATED: does a NATIVE named-pipe end handed to a
 * raw-spawned CYGWIN session on its STANDARD HANDLES select() correctly when
 * empty, so sd's poll-driven input layer does not spin?  The corrected
 * RELEASE_1.1 55 crux-(1) channel (probe-sessionpipe used the always-ready
 * cygwin_attach_handle_to_fd path; see the child's header and sd.c:460).
 *
 * The parent stands in for sd's front/relay: it creates a native duplex named
 * pipe (server), opens the client end itself (inheritable), and raw-spawns
 * probe-pipestd-child.exe with the client handle on hStdInput/hStdOutput -
 * exactly how the shipping SDLocal path (-C1!0) hands a native pipe to a Cygwin
 * sd.  Then, driving the server end:
 *   - it waits for the child's "READY" line (so the child's EMPTY-poll really
 *     is empty - nothing is sent before the child has polled)
 *   - greeting, ack, a 32 KiB ping-pong, graceful close for EOF
 * Exit 0 when the child reported the empty-poll NOT ready and every leg held;
 * 1 when the child hit the always-ready trap or a leg failed; 2 setup.
 *
 * Unelevated: the fd wrap and its select behaviour are token-independent (a
 * native pipe as a std handle is wrapped by GetFileType, not the token), same
 * reasoning as probe-sessionsp.
 *
 * Build from gplbld in MSYS2's MSYS bash:
 *   gcc -O2 -Wall -o probe-pipestd.exe probe-pipestd.c -lcygwin
 *   ./probe-pipestd.exe    (probe-pipestd-child.exe must be beside it)
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define BURST 8192

static int pingpong(HANDLE pipe, long base, long len) {
  char out[8192], in[8192];
  long i, got = 0;
  DWORD w = 0;
  for (i = 0; i < len; i++)
    out[i] = (char)('A' + ((base + i) % 26));
  if (!WriteFile(pipe, out, (DWORD)len, &w, NULL) || (long)w != len)
    return 0;
  while (got < len) {
    DWORD n = 0;
    long k;
    if (!ReadFile(pipe, in + got, (DWORD)(len - got), &n, NULL) || n == 0)
      return 0;
    for (k = 0; k < (long)n; k++)
      if (in[got + k] != out[got + k])
        return 0;
    got += n;
  }
  return 1;
}

static void dump_report(const char* winpath) {
  FILE* f = fopen(winpath, "r");
  char line[1024];
  if (!f) {
    printf("  (no report at %s)\n", winpath);
    return;
  }
  printf("  --- session's report ---\n");
  while (fgets(line, sizeof line, f))
    printf("  %s", line);
  printf("  --- end report ---\n");
  fclose(f);
}

int main(void) {
  char dir[MAX_PATH], childexe[MAX_PATH + 40], reportwin[MAX_PATH + 40];
  char reportfwd[MAX_PATH + 40], cmd[MAX_PATH * 3], pipename[128], buf[64];
  HANDLE server = INVALID_HANDLE_VALUE, client = INVALID_HANDLE_VALUE,
         client_in = NULL, client_out = NULL, nulErr = NULL, list[3];
  SECURITY_ATTRIBUTES sa;
  STARTUPINFOEXA six;
  PROCESS_INFORMATION pi;
  SIZE_T alen = 0;
  DWORD n = 0, code = 1, tick;
  int ready_ok = 0, ack_ok = 0, bulk_ok = 0, child_ok = 0;
  char* slash;
  int round;
  long total = 0;

  setvbuf(stdout, NULL, _IONBF, 0);
  if (GetModuleFileNameA(NULL, dir, sizeof dir) == 0)
    return 2;
  slash = strrchr(dir, '\\');
  if (slash)
    *slash = '\0';
  snprintf(childexe, sizeof childexe, "%s\\probe-pipestd-child.exe", dir);
  snprintf(reportwin, sizeof reportwin, "%s\\probe-pipestd-report.txt", dir);
  snprintf(reportfwd, sizeof reportfwd, "%s", reportwin);
  for (slash = reportfwd; *slash; slash++)
    if (*slash == '\\')
      *slash = '/';
  printf("probe-pipestd PARENT (native pipe server -> Cygwin session on std handles)\n");
  printf("child exe : %s\n", childexe);
  if (GetFileAttributesA(childexe) == INVALID_FILE_ATTRIBUTES) {
    printf("COULD NOT RUN: build probe-pipestd-child.exe first\n");
    return 2;
  }
  DeleteFileA(reportwin);

  tick = GetTickCount();
  snprintf(pipename, sizeof pipename, "\\\\.\\pipe\\sd-pipestd-%lu-%lu",
           (unsigned long)GetCurrentProcessId(), (unsigned long)tick);

  server = CreateNamedPipeA(pipename, PIPE_ACCESS_DUPLEX,
                            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
                            65536, 65536, 0, NULL);
  if (server == INVALID_HANDLE_VALUE) {
    printf("COULD NOT RUN: CreateNamedPipe %lu\n", (unsigned long)GetLastError());
    return 2;
  }
  /* The client end, inheritable - this is what the session gets as std handles,
     opened by the front (not the session), exactly as the product front would
     hand a native pipe to the spawned session. */
  sa.nLength = sizeof sa;
  sa.lpSecurityDescriptor = NULL;
  sa.bInheritHandle = TRUE;
  client = CreateFileA(pipename, GENERIC_READ | GENERIC_WRITE, 0, &sa,
                       OPEN_EXISTING, 0, NULL);
  if (client == INVALID_HANDLE_VALUE) {
    printf("COULD NOT RUN: CreateFile(client) %lu\n",
           (unsigned long)GetLastError());
    return 2;
  }

  nulErr = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &sa,
                       OPEN_EXISTING, 0, NULL);

  /* TWO handles for the duplex client end, one per std descriptor - win32pipe.c:
     0 and 1 are closed independently by the Cygwin runtime, and sharing one
     handle means the first close pulls it out from under the second (and, as
     this probe first measured, confuses the fhandler's read after a write). */
  if (!DuplicateHandle(GetCurrentProcess(), client, GetCurrentProcess(),
                       &client_in, 0, TRUE, DUPLICATE_SAME_ACCESS) ||
      !DuplicateHandle(GetCurrentProcess(), client, GetCurrentProcess(),
                       &client_out, 0, TRUE, DUPLICATE_SAME_ACCESS)) {
    printf("COULD NOT RUN: DuplicateHandle(client) %lu\n",
           (unsigned long)GetLastError());
    return 2;
  }
  CloseHandle(client);
  client = INVALID_HANDLE_VALUE;

  ZeroMemory(&six, sizeof six);
  ZeroMemory(&pi, sizeof pi);
  six.StartupInfo.cb = sizeof six;
  six.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  six.StartupInfo.hStdInput = client_in;
  six.StartupInfo.hStdOutput = client_out;
  six.StartupInfo.hStdError = nulErr;
  list[0] = client_in;
  list[1] = client_out;
  list[2] = nulErr;
  InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
  six.lpAttributeList =
      (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, alen);
  if (!six.lpAttributeList ||
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
  CloseHandle(client_in); /* the child holds its own copies now */
  CloseHandle(client_out);
  client_in = client_out = NULL;

  /* Wait for the child's READY - proves it finished the empty-poll before we
     send anything. */
  memset(buf, 0, sizeof buf);
  if (ReadFile(server, buf, sizeof buf - 1, &n, NULL) && n >= 6 &&
      memcmp(buf, "READY\n", 6) == 0)
    ready_ok = 1;
  printf("child READY  : %s\n", ready_ok ? "OK" : "NOT RECEIVED");

  printf("parent: writing greeting...\n");
  WriteFile(server, "RELAY->SESSION hello\n", 21, &n, NULL);
  printf("parent: greeting written (%lu); reading ack...\n", (unsigned long)n);
  memset(buf, 0, sizeof buf);
  if (ReadFile(server, buf, sizeof buf - 1, &n, NULL) && n > 0) {
    buf[strcspn(buf, "\r\n")] = '\0';
    ack_ok = (strcmp(buf, "SESSION->RELAY ack") == 0);
  }
  printf("leg ack      : %s (got %lu bytes)\n", ack_ok ? "OK" : "FAILED",
         (unsigned long)n);

  if (ack_ok) {
    printf("parent: bulk round, writing %d...\n", BURST);
    bulk_ok = 1;
    for (round = 0; round < 4; round++) {
      if (!pingpong(server, total, BURST)) {
        bulk_ok = 0;
        break;
      }
      total += BURST;
      printf("parent: round %d done (%ld)\n", round, total);
    }
    printf("leg bulk     : %ld bytes round-tripped -> %s\n", total,
           bulk_ok ? "OK" : "FAILED");
  }

  FlushFileBuffers(server);
  CloseHandle(server);
  server = INVALID_HANDLE_VALUE;

  if (WaitForSingleObject(pi.hProcess, 10000) == WAIT_OBJECT_0 &&
      GetExitCodeProcess(pi.hProcess, &code)) {
    child_ok = (code == 0);
    printf("session exit : %lu %s\n", (unsigned long)code,
           child_ok ? "OK" : "- FAIL (see report; exit 3 = empty-poll trap or a leg)");
  } else {
    printf("session exit : did NOT end within 10 s\n");
    TerminateProcess(pi.hProcess, 99);
  }
  CloseHandle(pi.hProcess);
  if (nulErr)
    CloseHandle(nulErr);
  if (six.lpAttributeList) {
    DeleteProcThreadAttributeList(six.lpAttributeList);
    HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
  }
  dump_report(reportwin);

  if (ready_ok && ack_ok && bulk_ok && child_ok) {
    printf("\nVERDICT: PASS - a native pipe on the session's std handles selects "
           "correctly when empty (no always-ready trap) and carries the traffic. "
           "This is the mechanism sd's session must use: the front opens the "
           "client end and hands it to the spawned session as std handles, NOT "
           "cygwin_attach_handle_to_fd.\n");
    return 0;
  }
  printf("\nVERDICT: FAIL (ready=%d ack=%d bulk=%d exit=%d) - if the child's "
         "report shows EMPTY-POLL ALWAYS-READY, even std handles hit the trap "
         "and the named pipe cannot serve sd's session I/O.\n",
         ready_ok, ack_ok, bulk_ok, child_ok);
  return 1;
}
/* END-CODE */
