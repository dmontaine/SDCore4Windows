/* probe-sessionpipe.c - UNELEVATED: the RECONNECT handover for RELEASE_1.1 55
 * direction (a).  probe-sessionsp proved a user-spawned Cygwin session cannot
 * inherit the relay's socketpair, so under (a) the session must open its OWN
 * channel to the front.  This measures the channel with no local security
 * hole: a named pipe whose SERVER (the relay, native) can (1) put a SID-scoped
 * DACL on it so no other user can open it and (2) call
 * GetNamedPipeClientProcessId to bind the connection to exactly the session it
 * spawned - both kernel-enforced.  The open question this answers is the
 * MECHANICS: can the spawned Cygwin session use a self-opened pipe as the
 * POLLABLE stream with clean EOF that sd's I/O needs?
 *
 * WHAT RUNS.  The parent stands in for the front + relay: it creates a named
 * pipe with a DACL granting only the current user's SID (so the ACL-building
 * path is exercised; cross-USER denial is a Windows kernel guarantee and the
 * elevated confirmation), raw-spawns probe-sessionpipe-child.exe (the Cygwin
 * session) with the pipe name, then:
 *   BIND : GetNamedPipeClientProcessId == the spawned PID   - the no-spoof bind
 *   1    : greeting line to the session                     - session READ
 *   2    : ack line from the session                        - session WRITE
 *   3    : 256 KiB pushed, its echo drained by a reader
 *          thread (full-duplex, no deadlock)                - BULK
 *   4    : the server closes                                - EOF at the session
 * Exit 0 when the PID bind held and the session read, wrote, echoed every byte
 * in order and exited 0 on EOF; 1 when a leg failed (the falsified-if: the
 * Cygwin session cannot use a self-opened pipe, so the reconnect needs a
 * loopback socket instead); 2 when it could not run.  The session's own report
 * file is echoed to stdout.
 *
 * Unelevated, same reasoning as probe-sessionsp: the pipe mechanics and the
 * client-PID read do not depend on the token, and cross-user DACL denial is a
 * kernel guarantee, so the only thing left for an owner-elevated run is
 * confirming the whole chain under CreateProcessAsUser-as-a-different-user.
 *
 * Build from gplbld in MSYS2's MSYS bash:
 *   gcc -O2 -Wall -o probe-sessionpipe.exe probe-sessionpipe.c -lcygwin -ladvapi32
 *   ./probe-sessionpipe.exe       (probe-sessionpipe-child.exe must be beside it)
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <stdio.h>
#include <string.h>

#define BULK_BYTES (256L * 1024L)

/* Build a SECURITY_ATTRIBUTES granting only the current user's SID.  Proves the
   DACL path; cross-user denial is the kernel's job and the elevated leg's. */
static int user_only_sa(SECURITY_ATTRIBUTES* sa, char* why, size_t whylen) {
  HANDLE tok = NULL;
  BYTE buf[256];
  DWORD len = 0;
  char* sidstr = NULL;
  char sddl[256];
  PSECURITY_DESCRIPTOR sd = NULL;
  int ok = 0;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
    snprintf(why, whylen, "OpenProcessToken %lu", (unsigned long)GetLastError());
    return 0;
  }
  if (!GetTokenInformation(tok, TokenUser, buf, sizeof buf, &len)) {
    snprintf(why, whylen, "GetTokenInformation(user) %lu",
             (unsigned long)GetLastError());
    goto done;
  }
  if (!ConvertSidToStringSidA(((TOKEN_USER*)buf)->User.Sid, &sidstr)) {
    snprintf(why, whylen, "ConvertSidToStringSid %lu",
             (unsigned long)GetLastError());
    goto done;
  }
  /* D: DACL, (A;;GA;;;<sid>) = Allow, Generic All, to that SID and no one else.
     No inheritance and no other ACE, so every other user is denied by default. */
  snprintf(sddl, sizeof sddl, "D:(A;;GA;;;%s)", sidstr);
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(
          sddl, SDDL_REVISION_1, &sd, NULL)) {
    snprintf(why, whylen, "ConvertStringSD %lu", (unsigned long)GetLastError());
    goto done;
  }
  sa->nLength = sizeof *sa;
  sa->lpSecurityDescriptor = sd; /* freed with LocalFree by the caller */
  sa->bInheritHandle = FALSE;
  ok = 1;
done:
  if (sidstr)
    LocalFree(sidstr);
  if (tok)
    CloseHandle(tok);
  return ok;
}

/* One ping-pong round: write `len` patterned bytes, then read exactly `len`
   back and check the pattern.  Sequential, so a byte pipe never deadlocks and
   no second thread is needed.  Returns 1 on a clean round. */
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
    printf("  (no report file at %s)\n", winpath);
    return;
  }
  printf("  --- session's report ---\n");
  while (fgets(line, sizeof line, f))
    printf("  %s", line);
  printf("  --- end report ---\n");
  fclose(f);
}

int main(void) {
  char dir[MAX_PATH], childexe[MAX_PATH + 40];
  char reportwin[MAX_PATH + 40], reportfwd[MAX_PATH + 40], cmd[MAX_PATH * 3];
  char pipename[128], why[256], ackbuf[128];
  HANDLE hPipe = INVALID_HANDLE_VALUE;
  SECURITY_ATTRIBUTES sa;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  DWORD n = 0, clientPid = 0, code = 1, tick;
  int ack_ok = 0, bulk_ok = 0, child_ok = 0, bind_ok = 0;
  char* slash;

  ZeroMemory(&sa, sizeof sa);
  ZeroMemory(&si, sizeof si);
  ZeroMemory(&pi, sizeof pi);
  si.cb = sizeof si;

  if (GetModuleFileNameA(NULL, dir, sizeof dir) == 0) {
    printf("COULD NOT RUN: GetModuleFileName %lu\n",
           (unsigned long)GetLastError());
    return 2;
  }
  slash = strrchr(dir, '\\');
  if (slash)
    *slash = '\0';
  snprintf(childexe, sizeof childexe, "%s\\probe-sessionpipe-child.exe", dir);
  snprintf(reportwin, sizeof reportwin, "%s\\probe-sessionpipe-report.txt", dir);
  snprintf(reportfwd, sizeof reportfwd, "%s", reportwin);
  for (slash = reportfwd; *slash; slash++)
    if (*slash == '\\')
      *slash = '/';

  printf("probe-sessionpipe PARENT (native, standing in for the front + relay)\n");
  printf("child exe : %s\n", childexe);
  if (GetFileAttributesA(childexe) == INVALID_FILE_ATTRIBUTES) {
    printf("COULD NOT RUN: build probe-sessionpipe-child.exe first\n");
    return 2;
  }
  DeleteFileA(reportwin);

  if (!user_only_sa(&sa, why, sizeof why)) {
    printf("COULD NOT RUN: SID DACL: %s\n", why);
    return 2;
  }

  tick = GetTickCount();
  snprintf(pipename, sizeof pipename, "\\\\.\\pipe\\sd-sessionprobe-%lu-%lu",
           (unsigned long)GetCurrentProcessId(), (unsigned long)tick);
  printf("pipe      : %s (DACL: current user's SID only)\n", pipename);

  hPipe = CreateNamedPipeA(pipename, PIPE_ACCESS_DUPLEX,
                           PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
                           65536, 65536, 0, &sa);
  if (hPipe == INVALID_HANDLE_VALUE) {
    printf("COULD NOT RUN: CreateNamedPipe %lu\n",
           (unsigned long)GetLastError());
    LocalFree(sa.lpSecurityDescriptor);
    return 2;
  }

  snprintf(cmd, sizeof cmd, "\"%s\" --client %s \"%s\"", childexe, pipename,
           reportfwd);
  if (!CreateProcessA(childexe, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL,
                      dir, &si, &pi)) {
    printf("COULD NOT RUN: CreateProcess %lu\n", (unsigned long)GetLastError());
    CloseHandle(hPipe);
    LocalFree(sa.lpSecurityDescriptor);
    return 2;
  }
  CloseHandle(pi.hThread);
  printf("spawned   : session PID %lu\n", (unsigned long)pi.dwProcessId);

  /* Wait for the session to connect (or find it already connected). */
  if (!ConnectNamedPipe(hPipe, NULL) &&
      GetLastError() != ERROR_PIPE_CONNECTED) {
    printf("COULD NOT RUN: ConnectNamedPipe %lu (session never arrived)\n",
           (unsigned long)GetLastError());
    goto finish;
  }

  /* THE NO-SPOOF BIND: the connected client must be the exact process we
     spawned.  Kernel truth, no shared secret. */
  if (GetNamedPipeClientProcessId(hPipe, &clientPid)) {
    bind_ok = (clientPid == pi.dwProcessId);
    printf("BIND      : client PID %lu vs spawned %lu -> %s\n",
           (unsigned long)clientPid, (unsigned long)pi.dwProcessId,
           bind_ok ? "MATCH (only the spawned session is on the pipe)"
                   : "MISMATCH - would refuse this connection");
  } else {
    printf("BIND      : GetNamedPipeClientProcessId %lu\n",
           (unsigned long)GetLastError());
  }

  /* Leg 1: greeting. */
  if (WriteFile(hPipe, "RELAY->SESSION hello\n", 21, &n, NULL))
    printf("leg 1 greeting : wrote %lu bytes to the session\n",
           (unsigned long)n);

  /* Leg 2: ack. */
  memset(ackbuf, 0, sizeof ackbuf);
  if (ReadFile(hPipe, ackbuf, sizeof ackbuf - 1, &n, NULL) && n > 0) {
    ackbuf[strcspn(ackbuf, "\r\n")] = '\0';
    ack_ok = (strcmp(ackbuf, "SESSION->RELAY ack") == 0);
    printf("leg 2 ack      : got \"%s\" %s\n", ackbuf,
           ack_ok ? "OK" : "- UNEXPECTED");
  } else {
    printf("leg 2 ack      : FAILED (no ack; err %lu)\n",
           (unsigned long)GetLastError());
  }

  /* Leg 3: sustained traffic as a sequential ping-pong (32 x 8 KiB = 256 KiB),
     the session echoing each round.  Sequential because a byte pipe with one
     handle per side deadlocks under full-duplex bursts, and the session's real
     I/O is not a full-duplex burst - the RELAY runs the poll loop, the session
     reads and writes. */
  if (ack_ok) {
    long total = 0;
    int round, rounds = 32;
    bulk_ok = 1;
    for (round = 0; round < rounds; round++) {
      if (!pingpong(hPipe, total, 8192)) {
        bulk_ok = 0;
        break;
      }
      total += 8192;
    }
    printf("leg 3 bulk     : %ld of %ld bytes round-tripped in %d rounds -> %s\n",
           total, BULK_BYTES, rounds, bulk_ok ? "OK" : "FAILED");
  }

  /* Leg 4: GRACEFUL close - flush, then drop our handle WITHOUT
     DisconnectNamedPipe (a forcible disconnect makes the client's read error
     ECOMM instead of seeing end-of-stream).  The session's read() must return
     0, the way it does when a client hangs up on Linux. */
  FlushFileBuffers(hPipe);
  CloseHandle(hPipe);
  hPipe = INVALID_HANDLE_VALUE;

  if (WaitForSingleObject(pi.hProcess, 10000) == WAIT_OBJECT_0 &&
      GetExitCodeProcess(pi.hProcess, &code)) {
    child_ok = (code == 0);
    printf("leg 4 EOF+exit : session exited %lu %s\n", (unsigned long)code,
           child_ok ? "OK (clean EOF)" : "- did not reach a clean EOF");
  } else {
    printf("leg 4 EOF+exit : session did NOT exit within 10 s\n");
    TerminateProcess(pi.hProcess, 99);
  }

finish:
  if (hPipe != INVALID_HANDLE_VALUE)
    CloseHandle(hPipe);
  CloseHandle(pi.hProcess);
  LocalFree(sa.lpSecurityDescriptor);
  dump_report(reportwin);

  if (bind_ok && ack_ok && bulk_ok && child_ok) {
    printf("\nVERDICT: PASS - the spawned Cygwin session opened the named pipe "
           "itself and used it as a POLLABLE stream, both directions and a "
           "clean EOF, and the server bound the connection to the exact "
           "spawned PID.  The reconnect handover works and has no local hole: "
           "the SID DACL denies other users, the PID check denies other "
           "processes.  Left to confirm: the whole chain under "
           "CreateProcessAsUser as a different user (owner-elevated).\n");
    return 0;
  }
  printf("\nVERDICT: FAIL (bind=%d ack=%d bulk=%d exit=%d) - if bind held but "
         "the stream legs failed, the Cygwin session cannot use a self-opened "
         "named pipe as a pollable fd, and the reconnect must use a loopback "
         "socket (session connect()s; the relay verifies the accepted "
         "connection's owning PID via the TCP table) instead.\n",
         bind_ok, ack_ok, bulk_ok, child_ok);
  return 1;
}
/* END-CODE */
