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
 * 03 Sep 26 Windows port - run gplbld/reconcile-accounts.ps1 as well, so the
 *           account register and os.users lose the records whose Windows
 *           account was removed from outside SD.  PRE_RELEASE_FIXES.md 93 and
 *           65.  run_sweep() and sweep_script_path() take the script name and
 *           a label now; nothing else about either changed.
 * 28 Aug 26 Windows port - run gplbld/reclaim-profiles.ps1 before "sd -start",
 *           so the profiles DELETE_USER could not remove are reclaimed on the
 *           boot that finally unmounts their hives.  PRE_RELEASE_FIXES.md 36.
 * 16 Aug 26 Windows port - do not report RUNNING without checking that sdwind
 *           is actually up; log to ProgramData\SD\sdsvc.log; clear the segment
 *           behind a failed start; drop CREATE_NO_WINDOW
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
 * THE TWO THINGS IT DOES BESIDES THE LIFECYCLE, AND WHY THEY ARE HERE.
 *
 * BOTH ARE THE SAME SHAPE: a state Windows can reach WITHOUT SD BEING TOLD,
 * which SD therefore cannot prevent and must instead detect and repair, at the
 * one moment that reliably happens - service start, which is every boot, as
 * LocalSystem, which is the token both repairs need.
 *
 * 03 Sep 26 Windows port, PRE_RELEASE_FIXES.md 93 and 65 - THE REGISTER.  A
 * Windows account can be removed from outside SD (net user /delete, an AD
 * removal, a decommission script) and nothing in SD is consulted, so
 * @SDSYS/ACCOUNTS and @SDSYS/OS.USERS keep records for accounts that are gone.
 * LIST ACCOUNTS and LIST OS.USERS then answer wrongly, which PROJECT_STATUS.md
 * 5.23 makes a blocking defect, and CREATE.ACCOUNT refuses to recreate the name
 * with "Account already exists" - true of the record and false of the world.
 * Measured immediately after a GREEN 41-step suite run: 14 of 15 records named
 * an account that no longer existed.  reconcile-accounts.ps1 removes the record
 * and the account directory together, on the owner's ruling that deletion takes
 * the data and SUSPENDED is the keep-it path.
 *
 * 28 Aug 26 Windows port, PRE_RELEASE_FIXES.md 36.  Deleting a Windows account
 * cannot delete its profile while Windows still has that profile's registry
 * hive mounted - the hive locks a file inside the directory - so gpl.bp/
 * DELETE_USER keeps both halves of the profile and records the pair under
 * ProgramData\SD\profile-reclaim.  Something has to come back for them, and
 * the only moment the lock is reliably gone is a boot.
 *
 * THIS IS THE ONLY THING SD RUNS AT EVERY BOOT, which is the whole reason the
 * sweep hangs off it: the service is start=auto and runs as LocalSystem, so it
 * is elevated - and removing a directory under C:\Users and a key under HKLM
 * both need that.  The alternative considered and rejected was Windows' own
 * "delete profiles older than N days on restart" policy: it is machine-wide
 * rather than scoped to SD, its granularity is days so it does not cure the
 * symptom, and it ages profiles off a recorded unload time that our case - a
 * hive that never unloaded cleanly - is least likely to carry.
 *
 * IT IS BEST EFFORT AND NEVER BLOCKS SD.  The sweep is not part of starting the
 * database, so a sweep that fails, hangs or is missing entirely must not stop
 * SD coming up.  It is given a bounded wait, the SCM is kept patient while it
 * runs, and its exit code is logged either way.  What it did is in its own log,
 * ProgramData\SD\reclaim-profiles.log - a service has nobody watching, so the
 * script writes its own record rather than relying on being seen.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#define SVC_NAME "SD"
#define SDWIND_EXE "sdwind.exe"

/* How long to wait for sdwind after "sd -start" returns.  sd -start forks the
   daemon and exits, so the daemon appears a moment later, not instantly.     */
#define SDWIND_WAIT_TRIES 20
#define SDWIND_WAIT_MS 500

/* AND HOW LONG TO WAIT BEFORE BELIEVING IT.  16 Aug 26 Windows port: the first
   version of this check asked whether sdwind EXISTED and was satisfied by the
   first poll, 500ms in.  sdwind did exist - it starts, fails to attach, and
   exits - so the service reported RUNNING off a process that was already on
   its way out, and, far worse, skipped the cleanup below and left the segment
   for the installer to trip over.  Existence is not survival.               */
#define SDWIND_SETTLE_MS 5000

/* How long to let the profile reclaim sweep run before giving up on WAITING
   for it.  Not a kill: the process is left to finish and write its own log,
   because a sweep interrupted half way through a Remove-Item is worse than a
   sweep nobody waited for.  Generous, because it deletes directories on a
   machine that has just booted and may be busy, and cheap, because the usual
   case is an empty store and an exit within a second.                       */
#define SWEEP_WAIT_MS 120000
#define SWEEP_SCRIPT "reclaim-profiles.ps1"

/* 03 Sep 26 Windows port - THE SECOND SWEEP.  PRE_RELEASE_FIXES.md 93 and 65:
   the account register and the shell-access list keep records for Windows
   accounts that have been removed from outside SD, so LIST ACCOUNTS and LIST
   OS.USERS answer wrongly and CREATEA refuses to recreate the name.  Same
   shape and same reason as the profile reclaim above - an external condition
   SD cannot prevent, swept at service start - so it hangs off the same
   moment, with the same "nothing here is fatal" contract.                 */
#define RECONCILE_SCRIPT "reconcile-accounts.ps1"

static SERVICE_STATUS_HANDLE svc_status_handle = NULL;
static SERVICE_STATUS svc_status;
static HANDLE svc_stop_event = NULL;

/* ======================================================================
   Saying anything at all.

   16 Aug 26 Windows port.  A service has no console, no standard output that
   goes anywhere, and no user to read one.  On 16 Aug 2026 this service started
   nothing, reported RUNNING, and left NO record of any kind - the failure had
   to be reconstructed afterwards from file ownership in the shm directory.

   ProgramData\SD is the right home for it: the service runs as LocalSystem and
   can write there, adopt-account.log is already beside it, and Program Files
   is the wrong place for something that changes.  Best effort throughout - a
   service that cannot open its log must still try to run SD.                */

static void svc_log(const char* fmt, ...) {
  char path[MAX_PATH];
  DWORD n;
  SYSTEMTIME st;
  FILE* f;
  va_list ap;

  n = GetEnvironmentVariableA("ProgramData", path, sizeof(path));
  if (n == 0 || n >= sizeof(path))
    strcpy(path, "C:\\ProgramData");

  if (strlen(path) + strlen("\\SD\\sdsvc.log") + 1 > sizeof(path))
    return;
  strcat(path, "\\SD\\sdsvc.log");

  f = fopen(path, "a");
  if (f == NULL)
    return;

  GetLocalTime(&st);
  fprintf(f, "%04d-%02d-%02d %02d:%02d:%02d  ", st.wYear, st.wMonth, st.wDay,
          st.wHour, st.wMinute, st.wSecond);

  va_start(ap, fmt);
  vfprintf(f, fmt, ap);
  va_end(ap);

  fputc('\n', f);
  fclose(f);
}

/* ======================================================================
   Is the daemon actually there?

   16 Aug 26 Windows port - THE ONLY HONEST TEST THAT SD STARTED, and the
   reason this function exists rather than a check of the exit code: on
   16 Aug 2026 "sd -start" exited reporting SUCCESS while starting nothing, so
   a service that trusted its child's status reported a healthy SD on a machine
   where SD was not running.  Every other caller in this project already looks
   for sdwind instead - verify-createaccount.ps1 does, and PROJECT_STATUS.md 6
   says to.  This is that check, in C.                                       */

static BOOL sdwind_running(void) {
  HANDLE snap;
  PROCESSENTRY32 pe;
  BOOL found = FALSE;

  snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE)
    return FALSE;

  pe.dwSize = sizeof(pe);
  if (Process32First(snap, &pe)) {
    do {
      if (_stricmp(pe.szExeFile, SDWIND_EXE) == 0) {
        found = TRUE;
        break;
      }
    } while (Process32Next(snap, &pe));
  }

  CloseHandle(snap);
  return found;
}

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
   And where a shipped sweep script is.

   03 Sep 26 Windows port - IT TAKES THE NAME NOW, because there are two of
   them.  PRE_RELEASE_FIXES.md 93 and 65.  Nothing else about it changed.

   28 Aug 26 Windows port.  The shipped .ps1 files live in the install root and
   this program lives two directories below it - sd.iss puts the binaries in
   {app}\usr\bin and everything else in {app} - so this walks up two levels
   from our own directory rather than from PATH or the registry, for exactly
   the reason sd_exe_path() gives: anything that depends on the environment
   works when tested by hand and fails at boot.

   FAILS RATHER THAN GUESSES.  A tree that is not the shape this expects makes
   this return FALSE and the caller skip the sweep with a line in the log,
   which is the safe direction - the alternative is running an arbitrary
   .ps1 found somewhere else, as LocalSystem.                              */

static BOOL sweep_script_path(char *buf, DWORD len, const char *script) {
  DWORD n;
  char *slash;
  int i;

  n = GetModuleFileNameA(NULL, buf, len);
  if (n == 0 || n >= len)
    return FALSE;

  /* sdsvc.exe, then bin, then usr.  Three cuts to reach {app}. */
  for (i = 0; i < 3; i++) {
    slash = strrchr(buf, '\\');
    if (slash == NULL)
      return FALSE;
    *slash = '\0';
  }

  if (strlen(buf) + 1 + strlen(script) + 1 > len)
    return FALSE;
  strcat(buf, "\\");
  strcat(buf, script);

  return TRUE;
}

/* ======================================================================
   Run "sd <arg>" and wait for THE PROCESS to exit.

   Not for its output.  sdwind inherits sd.exe's handles and outlives it, so
   anything waiting on the streams waits for the daemon instead and the
   service would never finish starting - measured twice on 15 Aug 2026 in
   other callers, and recorded in PROJECT_STATUS.md 6.  Nothing is
   redirected here, so there are no handles to wait on.                   */

/* Where the child's own words go.  Separate from sdsvc.log because this one is
   written by sd and sdwind rather than by us, and because sdwind inherits the
   handle and keeps it open for as long as it runs.                          */

static HANDLE open_child_log(void) {
  char path[MAX_PATH];
  DWORD n;
  SECURITY_ATTRIBUTES sa;
  HANDLE h;

  n = GetEnvironmentVariableA("ProgramData", path, sizeof(path));
  if (n == 0 || n >= sizeof(path))
    strcpy(path, "C:\\ProgramData");
  if (strlen(path) + strlen("\\SD\\sdsvc-sd.log") + 1 > sizeof(path))
    return INVALID_HANDLE_VALUE;
  strcat(path, "\\SD\\sdsvc-sd.log");

  ZeroMemory(&sa, sizeof(sa));
  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;

  /* FULL SHARING IS NOT OPTIONAL.  sdwind inherits this handle and holds it
     for its whole life, and "sd -stop" is later given a handle to the same
     file - without sharing, the second open fails and the log goes quiet at
     exactly the point it matters.                                           */

  h = CreateFileA(path, FILE_APPEND_DATA,
                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, &sa,
                  OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);

  return h;
}

static BOOL run_sd(const char *arg, DWORD *exit_code) {
  char exe[MAX_PATH];
  char cmd[MAX_PATH + 32];
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  SECURITY_ATTRIBUTES sa;
  HANDLE log;
  HANDLE nul;
  BOOL ok;

  if (!sd_exe_path(exe, sizeof(exe)))
    return FALSE;

  if (snprintf(cmd, sizeof(cmd), "\"%s\" %s", exe, arg) >= (int)sizeof(cmd))
    return FALSE;

  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  ZeroMemory(&pi, sizeof(pi));

  /* 16 Aug 26 Windows port - CAPTURE WHAT THE CHILD SAYS.  Until now nothing
     did, and on 16 Aug 2026 that cost two runs: sd -start printed that SD had
     started, sdwind then died saying whatever it says, and NONE of it reached
     any log, console or event.  sdwind.c now reports its startup failures on
     stderr precisely so that something can read them - this is that something.

     REDIRECTING IS SAFE HERE, and PROJECT_STATUS.md 6's warning does not
     apply: the trap is waiting on the child's STREAMS, because sdwind inherits
     them and outlives sd.  This waits on the PROCESS HANDLE only, so an
     inherited handle blocks nobody.  A file, never a pipe, for the same
     reason.                                                                 */

  /* 16 Aug 26 Windows port - EVERY ONE OF THESE THREE HANDLES MUST BE
     INHERITABLE, and the first attempt got NUL wrong: it was opened with NULL
     security attributes, so bInheritHandle defaulted to FALSE and the child was
     handed a stdin it could not have.  STARTF_USESTDHANDLES is all-or-nothing -
     one bad handle and the child's whole stdio is unusable - so sdsvc-sd.log
     was created and stayed EMPTY through two runs while sd and sdwind wrote
     into nothing.  An empty log read exactly like a silent program, which is
     the failure this logging existed to end.                                 */

  ZeroMemory(&sa, sizeof(sa));
  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;

  log = open_child_log();
  nul = CreateFileA("NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    &sa, OPEN_EXISTING, 0, NULL);

  if (log != INVALID_HANDLE_VALUE && nul != INVALID_HANDLE_VALUE) {
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = nul;   /* not NULL: a child handed no stdin can misread EOF */
    si.hStdOutput = log;
    si.hStdError = log;
  }

  /* 16 Aug 26 Windows port - CREATE_NO_WINDOW REMOVED, and it is a candidate
     cause rather than tidying.  sd -start reaches the daemon through fork() and
     daemon() on the MSYS2 runtime (sysseg.c), and those care about the console
     and session the process finds itself in.  The same "sd -start", as the same
     LocalSystem in the same session 0, started SD when launched from PowerShell
     with an inherited console and did NOT when launched by this service with
     CREATE_NO_WINDOW.  There is no window to suppress in session 0 anyway - no
     user can see one - so the flag was buying nothing.  If the service now
     works, this is why; if it does not, sdsvc.log says how far it got.       */

  ok = CreateProcessA(NULL, cmd, NULL, NULL, TRUE, /* inherit the log handle */
                      0, NULL, NULL, &si, &pi);

  /* Ours to close either way.  sdwind keeps its own inherited copies, which is
     what lets it go on writing after we have let go.                        */
  if (log != INVALID_HANDLE_VALUE)
    CloseHandle(log);
  if (nul != INVALID_HANDLE_VALUE)
    CloseHandle(nul);

  if (!ok)
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

/* ======================================================================
   Reclaim the profiles the delete path had to leave behind.

   28 Aug 26 Windows port, PRE_RELEASE_FIXES.md 36.  See the description at the
   top of this file for why it is here at all.  This function is about one
   thing: doing it without ever putting SD's start-up at risk.

   NOTHING HERE IS FATAL.  No script, no PowerShell, a non-zero exit, a sweep
   that outlasts its wait - every one of them logs a line and returns.  A
   database that will not start because a housekeeping script was missing would
   be a far worse defect than the one this fixes.

   AND THE SCM IS KEPT PATIENT WHILE IT RUNS.  A service that goes quiet for a
   minute is killed and reported as hung, so the wait is a loop that renews the
   START_PENDING hint rather than a single long block.  The usual case is an
   empty store and an exit inside a second; the loop matters on the boot after
   a suite run left two dozen directories behind.

   ITS OWN LOG, NOT OURS.  reclaim-profiles.ps1 writes
   ProgramData\SD\reclaim-profiles.log and says what it measured, refused and
   removed.  This records only that it ran and what it exited with, which is
   the part that belongs to the service.                                   */

static void run_sweep(const char *script_name, const char *what) {
  char script[MAX_PATH];
  char cmd[MAX_PATH * 2 + 160];
  char shell[MAX_PATH];
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  DWORD n;
  DWORD rc = 0;
  DWORD waited = 0;
  DWORD w;

  if (!sweep_script_path(script, sizeof(script), script_name)) {
    svc_log("%s skipped: could not work out where %s is from our own path",
            what, script_name);
    return;
  }

  if (GetFileAttributesA(script) == INVALID_FILE_ATTRIBUTES) {
    /* An install predating this, or a partial one.  Said plainly and once. */
    svc_log("%s skipped: no %s", what, script);
    return;
  }

  n = GetEnvironmentVariableA("SystemRoot", shell, sizeof(shell));
  if (n == 0 || n >= sizeof(shell))
    strcpy(shell, "C:\\Windows");
  if (strlen(shell) + strlen("\\System32\\WindowsPowerShell\\v1.0\\powershell.exe") + 1 >
      sizeof(shell)) {
    svc_log("%s skipped: cannot build the PowerShell path", what);
    return;
  }
  strcat(shell, "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");

  /* -ExecutionPolicy Bypass because this is a .ps1 FILE and a machine policy
     would otherwise refuse it - the same reason every shipped script is
     launched this way from sd.iss.  Both paths are quoted: the default install
     location contains a space.                                            */
  if (snprintf(cmd, sizeof(cmd),
               "\"%s\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%s\"",
               shell, script) >= (int)sizeof(cmd)) {
    svc_log("%s skipped: command line too long", what);
    return;
  }

  /* Rule 1 of the instrument section in CLAUDE.md: the command actually run,
     resolved, not the one intended.                                        */
  svc_log("%s: %s", what, cmd);

  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  ZeroMemory(&pi, sizeof(pi));

  if (!CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
    svc_log("%s: could not start it - CreateProcess error %lu", what,
            (unsigned long)GetLastError());
    return;
  }

  for (;;) {
    w = WaitForSingleObject(pi.hProcess, 1000);
    if (w == WAIT_OBJECT_0)
      break;

    waited += 1000;
    if (waited >= SWEEP_WAIT_MS) {
      /* Left running on purpose - see SWEEP_WAIT_MS.  It writes its own log,
         so nothing is lost by not waiting; SD is what must not wait.       */
      svc_log("%s: still running after %d seconds - going on without it "
              "(it writes its own log in ProgramData\\SD, which says what "
              "it did)",
              what, SWEEP_WAIT_MS / 1000);
      CloseHandle(pi.hProcess);
      CloseHandle(pi.hThread);
      return;
    }

    report(SERVICE_START_PENDING, NO_ERROR, 30000); /* keep the SCM patient */
  }

  GetExitCodeProcess(pi.hProcess, &rc);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  /* 0 nothing pending, 1 something still pending, 2 could not be attempted.
     None of the three is a reason not to start SD, and 1 is a state rather
     than a fault - a hive still up at this boot comes down at the next, and
     a register record the reconcile REFUSED is one a person has to look at
     rather than one the service can do anything about.                    */
  svc_log("%s: exited with %lu", what, (unsigned long)rc);
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
  int i;
  int alive = 0;

  (void)argc;
  (void)argv;

  svc_log("service starting");

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

  /* 28 Aug 26 Windows port - BEFORE SD, NOT AFTER.  PRE_RELEASE_FIXES.md 36.
     Two reasons, and the second is the one that decides it: the hives whose
     locks this is waiting on are down at boot and there is no reason to give
     anything a chance to reload one; and a profile directory in the way is
     what makes the NEXT CREATE.ACCOUNT refuse, so clearing it before the
     database is reachable means nobody meets the refusal for a directory that
     was about to go anyway.  It cannot fail SD - see run_sweep().          */
  run_sweep(SWEEP_SCRIPT, "profile reclaim");

  /* 03 Sep 26 Windows port - AND THE REGISTER, PRE_RELEASE_FIXES.md 93 and 65.
     BEFORE SD FOR A THIRD REASON, ON TOP OF THE TWO ABOVE: the register is a
     directory file, so this removes records by removing FILES, and doing that
     under a running SD would pull them out from under an open cursor.

     AFTER THE PROFILE RECLAIM, NOT BEFORE IT, AND THE ORDER IS LOAD-BEARING.
     A deleted account can leave a profile directory that only the reclaim can
     take, and the reclaim's own refusal table rejects any record whose SID
     still resolves to a live local account.  Running the register reconcile
     first would change nothing about that - it removes SD's records, not
     Windows accounts - but the reclaim is the older and more dangerous of the
     two, and giving it the boot's first attempt keeps its behaviour exactly
     as it was measured.                                                    */
  run_sweep(RECONCILE_SCRIPT, "register reconcile");

  /* A NON-ZERO EXIT IS NOT ALWAYS A FAILURE.  "sd -start" exits 1 when SD is
     already running, which at boot means somebody started it by hand first -
     the service's job is done either way.  Reporting a failure there would
     leave a red service on a working system.  A start that could not run at
     all is the real failure, and that is what CreateProcess reports.       */
  if (!run_sd("-start", &rc)) {
    svc_log("could not run \"sd -start\" at all - CreateProcess error %lu",
            (unsigned long)GetLastError());
    report(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR, 0);
    return;
  }
  svc_log("\"sd -start\" exited with %lu", (unsigned long)rc);

  /* 16 Aug 26 Windows port - AND NEITHER IS A ZERO EXIT A SUCCESS, which is
     the whole lesson of 16 Aug 2026: "sd -start" reported success, started
     nothing, and this service reported RUNNING on the strength of it.  So ask
     the question that actually matters.                                     */

  for (i = 0; i < SDWIND_WAIT_TRIES; i++) {
    if (sdwind_running())
      break;
    report(SERVICE_START_PENDING, NO_ERROR, 30000); /* keep the SCM patient */
    Sleep(SDWIND_WAIT_MS);
  }

  /* AND THEN CHECK IT IS STILL THERE.  See SDWIND_SETTLE_MS - a daemon that
     starts and immediately exits satisfies "is it running?" for a moment, and
     that moment was enough to make this service lie on 16 Aug 2026.         */

  if (sdwind_running()) {
    svc_log("%s appeared; waiting %d seconds to see whether it stays",
            SDWIND_EXE, SDWIND_SETTLE_MS / 1000);
    report(SERVICE_START_PENDING, NO_ERROR, 30000);
    Sleep(SDWIND_SETTLE_MS);
  }

  if (!sdwind_running()) {
    svc_log("SD did not start: %s is not running (see sdsvc-sd.log for what "
            "sd -start and %s said)", SDWIND_EXE, SDWIND_EXE);

    /* DO NOT LEAVE THE WRECKAGE.  A failed "sd -start" has already created the
       shared segment and the semaphores, and under LocalSystem they belong to
       SYSTEM - after which every ordinary session dies "Error 116 getting
       semaphores" rather than "SD has not been started".  That is what broke
       the installer's own account step on 16 Aug 2026 and left the installing
       user with no SD account.  A service that cannot start SD must at least
       leave the machine as it found it.                                     */

    run_sd("-stop", &rc);
    svc_log("cleared the half-started segment: \"sd -stop\" exited with %lu",
            (unsigned long)rc);

    report(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR, 0);
    return;
  }

  svc_log("SD is running (%s is up); service reporting RUNNING", SDWIND_EXE);
  report(SERVICE_RUNNING, NO_ERROR, 0);

  /* 16 Aug 26 Windows port - WATCH IT, DO NOT JUST WAIT.  This used to be a
     bare WaitForSingleObject(INFINITE), so when the daemon died the service sat
     reporting RUNNING for ever over a machine with no SD - which is what
     "Get-Service SD: Running / sdwind: 0" was, twice, on 16 Aug 2026.

     It also pins the failure in time.  sdwind was seen alive at 5 seconds old
     and gone a second or two later on two separate installs, with nothing
     watching in between; now the service says exactly how long it lasted, in
     its own log, with no test harness anywhere near it.                     */

  for (;;) {
    if (WaitForSingleObject(svc_stop_event, 1000) == WAIT_OBJECT_0)
      break; /* asked to stop - the normal path, below */

    alive++;

    if (!sdwind_running()) {
      svc_log("%s has GONE after %d seconds - SD is not running any more",
              SDWIND_EXE, alive);

      /* Same reason as the start-up failure above: do not leave a segment
         nobody can use, or the next ordinary session meets "Error 116 getting
         semaphores" instead of a machine it can start SD on.                */
      run_sd("-stop", &rc);
      svc_log("cleared up after it: \"sd -stop\" exited with %lu",
              (unsigned long)rc);

      report(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR, 0);
      CloseHandle(svc_stop_event);
      svc_stop_event = NULL;
      return;
    }
  }

  /* Stopping the service stops SD.  Sessions attached to the shared segment
     are ended by this, which is why "sd -stop" prints what it prints - see
     PROJECT_STATUS.md 7 step 1d.  At shutdown that is what is wanted; the
     alternative, leaving the daemon behind, orphans the segment.          */
  run_sd("-stop", &rc);
  svc_log("service stopping: \"sd -stop\" exited with %lu", (unsigned long)rc);

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
