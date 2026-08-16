/* sdsvc.c - the Windows service that starts SD at boot
 *
 * Copyright (c) String Database
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * START-HISTORY:
 * 15 Aug 26 Windows port - written.  Owner's decision: SD runs as a service,
 *           started by the installer, so it is up after every restart.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY THIS IS A SEPARATE PROGRAM, AND A NATIVE ONE.
 *
 * A Windows service must call StartServiceCtrlDispatcher and answer the
 * service control manager within its start timeout.  sd.exe cannot do it:
 * it is built against the MSYS2 POSIX runtime, and linuxlb.c records the
 * decision not to drag windows.h into that half of the tree - IsElevated()
 * uses getgrouplist() rather than GetTokenInformation() for exactly this
 * reason.  Overriding that in passing to add a service entry point would be
 * the wrong way to settle it.
 *
 * PROJECT_STATUS.md 5.3 already keeps two toolchains on purpose: the server
 * on the MSYS2 runtime, the client DLL native UCRT64.  Win32 service code
 * belongs on the native side, so this is built with the UCRT64 compiler
 * beside sdclilib.dll and never sees the POSIX runtime at all.
 *
 * WHAT IT DOES, AND WHAT IT DELIBERATELY DOES NOT.
 *
 * It owns the LIFECYCLE only: "sd -start" when Windows starts the service,
 * "sd -stop" when Windows stops it.  It does NOT run the database, and SD's
 * processes are not its children - "sd -start" forks sdwind, which outlives
 * it, which is the whole reason this waits on the PROCESS and never on its
 * output streams (PROJECT_STATUS.md 6).
 *
 * IT IS NOT THE SERVICE ACCOUNT MODEL IN 5.7, and must not be mistaken for
 * it.  That one has a dedicated service identity owning the data tree, with
 * sessions spawned under it and users reaching them over a named pipe, and it
 * is stage 2.  This runs sdwind under whatever identity the service is
 * configured with and changes nothing about who owns the files.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <stdio.h>

#define SVC_NAME "SD"

static SERVICE_STATUS_HANDLE svc_status_handle = NULL;
static SERVICE_STATUS svc_status;
static HANDLE svc_stop_event = NULL;

/* ======================================================================
   Where sd.exe is.

   Derived from our own path rather than from PATH or the registry: the
   service is started by the SCM with an unpredictable working directory and
   a minimal environment, and sdsvc.exe is installed in the same directory as
   sd.exe.  Anything that depends on PATH would work when tested by hand and
   fail at boot, which is the worst way round.                            */

static BOOL sd_exe_path(char *buf, DWORD len) {
  DWORD n;
  char *slash;

  n = GetModuleFileNameA(NULL, buf, len);
  if (n == 0 || n >= len)
    return FALSE;

  slash = strrchr(buf, '\\');
  if (slash == NULL)
    return FALSE;
  *slash = '\0';

  if (strlen(buf) + strlen("\\sd.exe") + 1 > len)
    return FALSE;
  strcat(buf, "\\sd.exe");

  return TRUE;
}

/* ======================================================================
   Run "sd <arg>" and wait for THE PROCESS to exit.

   Not for its output.  sdwind inherits sd.exe's handles and outlives it, so
   anything waiting on the streams waits for the daemon instead and the
   service would never finish starting - measured twice on 15 Aug 2026 in
   other callers, and recorded in PROJECT_STATUS.md 6.  Nothing is
   redirected here, so there are no handles to wait on.                   */

static BOOL run_sd(const char *arg, DWORD *exit_code) {
  char exe[MAX_PATH];
  char cmd[MAX_PATH + 32];
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;

  if (!sd_exe_path(exe, sizeof(exe)))
    return FALSE;

  if (snprintf(cmd, sizeof(cmd), "\"%s\" %s", exe, arg) >= (int)sizeof(cmd))
    return FALSE;

  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  ZeroMemory(&pi, sizeof(pi));

  if (!CreateProcessA(NULL, cmd, NULL, NULL, FALSE,
                      CREATE_NO_WINDOW, NULL, NULL, &si, &pi))
    return FALSE;

  WaitForSingleObject(pi.hProcess, INFINITE);
  GetExitCodeProcess(pi.hProcess, exit_code);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  return TRUE;
}

/* ====================================================================== */

static void report(DWORD state, DWORD win32_exit, DWORD wait_hint) {
  static DWORD checkpoint = 1;

  svc_status.dwCurrentState = state;
  svc_status.dwWin32ExitCode = win32_exit;
  svc_status.dwWaitHint = wait_hint;

  svc_status.dwControlsAccepted =
      (state == SERVICE_START_PENDING)
          ? 0
          : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);

  if (state == SERVICE_RUNNING || state == SERVICE_STOPPED)
    svc_status.dwCheckPoint = 0;
  else
    svc_status.dwCheckPoint = checkpoint++;

  if (svc_status_handle != NULL)
    SetServiceStatus(svc_status_handle, &svc_status);
}

static void WINAPI svc_ctrl(DWORD ctrl) {
  switch (ctrl) {
    case SERVICE_CONTROL_STOP:
    case SERVICE_CONTROL_SHUTDOWN:
      report(SERVICE_STOP_PENDING, NO_ERROR, 30000);
      if (svc_stop_event != NULL)
        SetEvent(svc_stop_event);
      break;

    default:
      break;
  }
}

static void WINAPI svc_main(DWORD argc, LPSTR *argv) {
  DWORD rc = 0;

  (void)argc;
  (void)argv;

  svc_status_handle = RegisterServiceCtrlHandlerA(SVC_NAME, svc_ctrl);
  if (svc_status_handle == NULL)
    return;

  ZeroMemory(&svc_status, sizeof(svc_status));
  svc_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;

  /* 30 seconds is generous: sd -start forks sdwind and returns.  It is a wait
     HINT, not a limit, and understating it makes the SCM report a hang.    */
  report(SERVICE_START_PENDING, NO_ERROR, 30000);

  svc_stop_event = CreateEventA(NULL, TRUE, FALSE, NULL);
  if (svc_stop_event == NULL) {
    report(SERVICE_STOPPED, GetLastError(), 0);
    return;
  }

  /* A NON-ZERO EXIT IS NOT ALWAYS A FAILURE.  "sd -start" exits 1 when SD is
     already running, which at boot means somebody started it by hand first -
     the service's job is done either way.  Reporting a failure there would
     leave a red service on a working system.  A start that could not run at
     all is the real failure, and that is what CreateProcess reports.       */
  if (!run_sd("-start", &rc)) {
    report(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR, 0);
    return;
  }

  report(SERVICE_RUNNING, NO_ERROR, 0);

  WaitForSingleObject(svc_stop_event, INFINITE);

  /* Stopping the service stops SD.  Sessions attached to the shared segment
     are ended by this, which is why "sd -stop" prints what it prints - see
     PROJECT_STATUS.md 7 step 1d.  At shutdown that is what is wanted; the
     alternative, leaving the daemon behind, orphans the segment.          */
  run_sd("-stop", &rc);

  CloseHandle(svc_stop_event);
  svc_stop_event = NULL;

  report(SERVICE_STOPPED, NO_ERROR, 0);
}

/* ======================================================================
   Entry point.

   The SCM runs this with no arguments.  Run from a command line it says so
   rather than appearing to do nothing, because a service binary launched by
   hand otherwise sits for 30 seconds and exits 1067 with no explanation.  */

int main(int argc, char *argv[]) {
  SERVICE_TABLE_ENTRYA table[] = {{(LPSTR)SVC_NAME, svc_main}, {NULL, NULL}};

  (void)argc;
  (void)argv;

  if (!StartServiceCtrlDispatcherA(table)) {
    if (GetLastError() == ERROR_FAILED_SERVICE_CONTROLLER_CONNECT) {
      fprintf(stderr,
              "sdsvc is the SD service and is started by Windows, not by "
              "hand.\n"
              "  net start %s      start SD now\n"
              "  net stop %s       stop it\n"
              "The installer creates the service; sd -start and sd -stop do "
              "the same job\n"
              "in one session without involving Windows.\n",
              SVC_NAME, SVC_NAME);
      return 1;
    }
    return 1;
  }

  return 0;
}

/* END-CODE */
