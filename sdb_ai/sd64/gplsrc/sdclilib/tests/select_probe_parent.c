/* probe_parent.c - NATIVE UCRT64 side of the step 11 transport probe.
 *
 * Stands in for SDConnectLocal(): it is a native Windows process spawning an
 * MSYS2/Cygwin child, which is exactly the arrangement sdclilib.dll and sd.exe
 * are in (PROJECT_STATUS.md 5.3, two toolchains on purpose).
 *
 * It gives the child TWO transports at once so the run carries its own control:
 *
 *   - anonymous pipes handed over as the child's STANDARD HANDLES, which is
 *     the proposed fix: Cygwin sets those descriptors up itself at startup,
 *     sees FILE_TYPE_PIPE, and installs its pipe handler.
 *   - a NAMED pipe whose name is passed as an argument, which is what
 *     SDConnectLocal does today and what the child injects with
 *     cygwin_attach_handle_to_fd().
 *
 * Build:  /c/msys64/ucrt64/bin/gcc -Wall -o probe_parent.exe probe_parent.c
 */

#include <stdio.h>
#include <string.h>
#include <windows.h>

int main(int argc, char **argv) {
  SECURITY_ATTRIBUTES sa;
  HANDLE inRd = NULL, inWr = NULL;      /* parent writes inWr -> child fd 0 */
  HANDLE outRd = NULL, outWr = NULL;    /* child fd 1 -> parent reads outRd */
  HANDLE named;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  char cmd[1024];
  char pipe_name[128];
  DWORD wrote = 0;
  BOOL connected;

  if (argc < 3) {
    printf("usage: probe_parent <child.exe> <logfile>\n");
    return 90;
  }

  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = NULL;
  sa.bInheritHandle = TRUE;

  if (!CreatePipe(&inRd, &inWr, &sa, 0) || !CreatePipe(&outRd, &outWr, &sa, 0)) {
    printf("CreatePipe failed %lu\n", (unsigned long)GetLastError());
    return 91;
  }
  /* The parent's own ends must NOT be inheritable, or the child holds a copy
     and the pipe never reports EOF when the parent closes it. */
  SetHandleInformation(inWr,  HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(outRd, HANDLE_FLAG_INHERIT, 0);

  snprintf(pipe_name, sizeof(pipe_name), "\\\\.\\pipe\\~SDProbe%lu",
           (unsigned long)GetCurrentProcessId());
  named = CreateNamedPipeA(pipe_name, PIPE_ACCESS_DUPLEX,
                           PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                           1, 4096, 4096, 0, NULL);
  if (named == INVALID_HANDLE_VALUE) {
    printf("CreateNamedPipe failed %lu\n", (unsigned long)GetLastError());
    return 92;
  }

  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput  = inRd;
  si.hStdOutput = outWr;
  si.hStdError  = GetStdHandle(STD_ERROR_HANDLE);

  snprintf(cmd, sizeof(cmd), "\"%s\" %s \"%s\"", argv[1], pipe_name, argv[2]);

  memset(&pi, 0, sizeof(pi));
  if (!CreateProcessA(argv[1], cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
    printf("CreateProcess failed %lu\n", (unsigned long)GetLastError());
    return 93;
  }
  printf("parent: spawned %s (pid %lu)\n", argv[1], (unsigned long)pi.dwProcessId);

  /* Our copies of the child's ends, or nothing ever sees EOF. */
  CloseHandle(inRd);
  CloseHandle(outWr);

  /* The child opens the named pipe during its phase 1, after its first
     select(), so this returns about 200ms in. */
  connected = ConnectNamedPipe(named, NULL);
  printf("parent: ConnectNamedPipe %s\n",
         (connected || GetLastError() == ERROR_PIPE_CONNECTED) ? "ok" : "FAILED");

  /* Both descriptors have now been measured EMPTY.  Put a byte in each. */
  Sleep(1500);
  WriteFile(inWr, "HELLO-INHERITED", 15, &wrote, NULL);
  printf("parent: wrote %lu bytes to the inherited pipe\n", (unsigned long)wrote);
  WriteFile(named, "HELLO-NAMED", 11, &wrote, NULL);
  printf("parent: wrote %lu bytes to the named pipe\n", (unsigned long)wrote);

  WaitForSingleObject(pi.hProcess, 15000);
  printf("parent: child finished\n");

  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  CloseHandle(inWr);
  CloseHandle(outRd);
  CloseHandle(named);
  return 0;
}
