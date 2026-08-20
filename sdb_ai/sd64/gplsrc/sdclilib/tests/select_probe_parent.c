/* Modifications Copyright (c) 2026 Donald Montaine
 *
 * This library is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at
 * your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser
 * General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <https://www.gnu.org/licenses/>.
 *
 * Linking exception (additional permission under GNU LGPL version 3
 * section 7): as a special exception, the copyright holders give you
 * permission to link this library with independent modules to produce an
 * executable, regardless of the license terms of these independent modules,
 * and to copy and distribute the resulting executable under terms of your
 * choice, provided that you also meet, for each linked independent module,
 * the terms and conditions of the license of that module.  An independent
 * module is a module which is not derived from or based on this library.
 */

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
#include <stdlib.h>
#include <string.h>
#include <windows.h>

int main(int argc, char **argv) {
  SECURITY_ATTRIBUTES sa;
  HANDLE inRd = NULL, inWr = NULL;      /* parent writes inWr -> child fd 0 */
  HANDLE outRd = NULL, outWr = NULL;    /* child fd 1 -> parent reads outRd */
  HANDLE named;
  STARTUPINFOA si;
  STARTUPINFOEXA six;
  PROCESS_INFORMATION pi;
  char cmd[1024];
  char pipe_name[128];
  DWORD wrote = 0;
  BOOL connected;

  if (argc < 3) {
    printf("usage: probe_parent <child.exe> <logfile>\n");
    return 90;
  }

  memset(&six, 0, sizeof(six));

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

  /* EXACTLY TWO HANDLES ARE INHERITED, and this is the pattern sdclilib.dll
     ships rather than the textbook one.  bInheritHandles = TRUE inherits EVERY
     inheritable handle the process owns, and this code runs inside somebody
     else's application - which may hold inheritable handles to files, sockets
     or registry keys.  A long-lived sd.exe child holding copies of those keeps
     files locked for its whole life, and the owner would have no way to see
     why.  PROC_THREAD_ATTRIBUTE_HANDLE_LIST restricts inheritance to the list
     given, so bInheritHandles = TRUE means "these two" instead of "everything".

     The listed handles must still be inheritable in their own right, which is
     what SECURITY_ATTRIBUTES.bInheritHandle above does; the list narrows, it
     does not grant. */
  {
    SIZE_T attr_size = 0;
    HANDLE inherit[2];
    inherit[0] = inRd;
    inherit[1] = outWr;

    InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
    six.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(attr_size);
    if (six.lpAttributeList == NULL ||
        !InitializeProcThreadAttributeList(six.lpAttributeList, 1, 0, &attr_size) ||
        !UpdateProcThreadAttribute(six.lpAttributeList, 0,
                                   PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                   inherit, sizeof(inherit), NULL, NULL)) {
      printf("attribute list failed %lu\n", (unsigned long)GetLastError());
      return 94;
    }
  }

  memset(&si, 0, sizeof(si));
  /* sizeof the EXTENDED struct, not this one - CreateProcess reads cb to decide
     how much of it to trust, and EXTENDED_STARTUPINFO_PRESENT with a plain
     STARTUPINFO cb makes it ignore the attribute list. */
  si.cb = sizeof(STARTUPINFOEXA);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput  = inRd;
  si.hStdOutput = outWr;
  /* Not a pipe: SD's diagnostics must not land in the protocol channel.  A GUI
     host has no stderr and the child simply gets none, which is harmless. */
  si.hStdError  = GetStdHandle(STD_ERROR_HANDLE);
  six.StartupInfo = si;

  snprintf(cmd, sizeof(cmd), "\"%s\" %s \"%s\"", argv[1], pipe_name, argv[2]);

  memset(&pi, 0, sizeof(pi));
  if (!CreateProcessA(argv[1], cmd, NULL, NULL, TRUE,
                      EXTENDED_STARTUPINFO_PRESENT, NULL, NULL,
                      &six.StartupInfo, &pi)) {
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

  if (six.lpAttributeList != NULL) {
    DeleteProcThreadAttributeList(six.lpAttributeList);
    free(six.lpAttributeList);
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  CloseHandle(inWr);
  CloseHandle(outRd);
  CloseHandle(named);
  return 0;
}
