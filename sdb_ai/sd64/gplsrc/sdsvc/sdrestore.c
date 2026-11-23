/* SDRESTORE.C
 * "sdsvc.exe -restore-kept": put back, AS SDSYS, what an uninstall that kept the data took away.
 * Copyright (c) Donald Montaine
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
 * 21 Nov 26 Windows port - RELEASE_1.1 370 (owner, 21 Nov 2026: "put back exactly as it was ... or warn with the exact steps", and "Yes, build it"
 *           to an installer helper that does it as SDSYS).
 * END-HISTORY
 *
 * WHY.  Windows registers a Task Scheduler task that runs as SDSYS (S4U, highest run level: the administrator's scheduled jobs, remote
 * administration's broker task) only for SDSYS itself (row 280).  An uninstall that keeps the database has to remove those tasks, so the
 * reinstall has to make them again, and the installer is an administrator, not SDSYS.  MEASURED on a VM, 21 Nov 2026 (probe-sdsys-taskreg.ps1):
 * an administrator and SYSTEM are refused, but a process holding the S4U token of SDSYS that a LocalSystem process minted registers the task and
 * runs sd-jobs.ps1 job-set.  The SD service already makes that token for the local SDSYS door (sdsyslocal.c, win32s4ulogon.c); this is the
 * same thing for one fixed purpose, and it is in sdsvc.exe so that no new program is built, staged or checked.
 *
 * FIXED PURPOSE, AND NOTHING THE CALLER SAYS REACHES IT.  The only argument is -restore-kept (sdsvc.c's main).  It runs ONLY
 *     powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<program folder>\sd-restore-kept.ps1"
 * as SDSYS, with the script found in the program folder two levels above this program (<program folder>\usr\bin\sdsvc.exe; Program Files:
 * administrators only) and refused unless it is a plain file; a program anywhere else is refused.  It refuses
 * unless it is LocalSystem (a task the installer registers, run once), unless its result folder <ProgramData>\SDrestore is a real folder owned by
 * Administrators or SYSTEM (the installer makes it with an administrators-only ACL; an ordinary user who made it first owns it and is refused), and
 * unless the S4U token it gets is an ELEVATED one.  The script's output goes to <ProgramData>\SDrestore\result.txt, opened here with CREATE_NEW
 * and inherited, so SDSYS writes through a handle SYSTEM opened and no link planted there can aim SYSTEM's write anywhere.  The child is in a job
 * object that ends it if this process ends, and is ended after 180 seconds.  Everything the script restores it checks itself (sd-restore-kept.ps1):
 * a definition is given to the same validating verb as an administrator's own set.job, and remote administration is reopened only from a note an
 * administrator wrote.
 *
 * THE RESULT FILE says what happened in lines the installer anchors on; the last line is "sdrestore: child exit N" and is written only when the child
 * ran to its end, so a file without it means the restore did not finish.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <aclapi.h>
#include <userenv.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#include "../win32s4u.h"
#include "sdrestore.h"

#define SR_ACCOUNT "SDSYS"
#define SR_TIMEOUT_MS 180000

/* Append one line to the result handle (and to stderr, which a task throws away but a person at a prompt sees). */
static void sr_line(HANDLE out, const char* fmt, ...) {
  char buf[600];
  DWORD wrote = 0;
  va_list ap;
  int n;

  va_start(ap, fmt);
  n = vsnprintf(buf, sizeof(buf) - 2, fmt, ap);
  va_end(ap);
  if (n < 0)
    n = 0;
  if (n > (int)sizeof(buf) - 3)
    n = (int)sizeof(buf) - 3;
  buf[n++] = '\r';
  buf[n++] = '\n';
  if (out != INVALID_HANDLE_VALUE && out != NULL)
    WriteFile(out, buf, (DWORD)n, &wrote, NULL);
  fwrite(buf, 1, (size_t)n, stderr);
}

/* 1 when the process token's user is LocalSystem. */
static int sr_is_system(void) {
  HANDLE tok = NULL;
  BYTE ubuf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  BYTE sys[SECURITY_MAX_SID_SIZE];
  DWORD n = 0, slen = sizeof(sys);
  int ok = 0;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
    return 0;
  if (GetTokenInformation(tok, TokenUser, ubuf, sizeof(ubuf), &n) && CreateWellKnownSid(WinLocalSystemSid, NULL, sys, &slen) &&
      EqualSid(((TOKEN_USER*)ubuf)->User.Sid, (PSID)sys))
    ok = 1;
  CloseHandle(tok);
  return ok;
}

/* 1 when path is a real directory (not a link) owned by Administrators or SYSTEM. */
static int sr_dir_trusted(const WCHAR* path, const char** why) {
  DWORD attr = GetFileAttributesW(path);
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  BYTE admins[SECURITY_MAX_SID_SIZE], sys[SECURITY_MAX_SID_SIZE];
  DWORD alen = sizeof(admins), slen = sizeof(sys);
  int ok = 0;

  if (attr == INVALID_FILE_ATTRIBUTES || !(attr & FILE_ATTRIBUTE_DIRECTORY)) {
    *why = "the result folder is not there";
    return 0;
  }
  if (attr & FILE_ATTRIBUTE_REPARSE_POINT) {
    *why = "the result folder is a link";
    return 0;
  }
  if (GetNamedSecurityInfoW(path, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, &sd) != ERROR_SUCCESS || owner == NULL) {
    *why = "the result folder's owner could not be read";
    return 0;
  }
  if (CreateWellKnownSid(WinBuiltinAdministratorsSid, NULL, admins, &alen) && CreateWellKnownSid(WinLocalSystemSid, NULL, sys, &slen) &&
      (EqualSid(owner, (PSID)admins) || EqualSid(owner, (PSID)sys)))
    ok = 1;
  else
    *why = "the result folder is owned by somebody other than Administrators or SYSTEM";
  LocalFree(sd);
  return ok;
}

int sdrestore_main(void) {
  WCHAR pdata[MAX_PATH], rdir[MAX_PATH], rfile[MAX_PATH];
  WCHAR exe[MAX_PATH], appdir[MAX_PATH], script[MAX_PATH], sysdir[MAX_PATH], ps[MAX_PATH], cmd[2 * MAX_PATH + 160];
  WCHAR* slash;
  const char* why = "";
  HANDLE out = INVALID_HANDLE_VALUE, nul = INVALID_HANDLE_VALUE, imp = NULL, prim = NULL, job = NULL;
  SECURITY_ATTRIBUTES sa;
  STARTUPINFOW si;
  PROCESS_INFORMATION pi;
  TOKEN_ELEVATION el;
  DWORD n = 0, sattr, code = 1, w;
  void* env = NULL;
  int rc = 2, started = 0;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION jl;

  ZeroMemory(&pi, sizeof(pi));

  if (!sr_is_system()) {
    fprintf(stderr, "sdsvc -restore-kept: refused, this is not LocalSystem (the installer runs it as a one-time SYSTEM task).\n");
    return 2;
  }

  /* <ProgramData>\SDrestore: the installer made it, administrators only; the variable is SYSTEM's own, not a caller's. */
  n = GetEnvironmentVariableW(L"ProgramData", pdata, MAX_PATH);
  if (n == 0 || n >= MAX_PATH - 32) {
    fprintf(stderr, "sdsvc -restore-kept: refused, ProgramData is not known.\n");
    return 2;
  }
  swprintf(rdir, MAX_PATH, L"%ls\\SDrestore", pdata);
  swprintf(rfile, MAX_PATH, L"%ls\\result.txt", rdir);
  if (!sr_dir_trusted(rdir, &why)) {
    fprintf(stderr, "sdsvc -restore-kept: refused, %s.\n", why);
    return 2;
  }

  ZeroMemory(&sa, sizeof(sa));
  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;
  out = CreateFileW(rfile, GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
  if (out == INVALID_HANDLE_VALUE) {
    fprintf(stderr, "sdsvc -restore-kept: refused, %ls could not be created (error %lu; it must not exist).\n", rfile, (unsigned long)GetLastError());
    return 2;
  }
  nul = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);

  /* The script beside this program, as a plain file. */
  SetLastError(0);
  if (GetModuleFileNameW(NULL, exe, MAX_PATH) == 0 || GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
    sr_line(out, "sdrestore: NOT RUN, this program's own path could not be read");
    goto done;
  }
  wcscpy(appdir, exe);
  if ((slash = wcsrchr(appdir, L'\\')) != NULL)
    *slash = L'\0';
  /* sdsvc.exe is installed in <program folder>\usr\bin and the scripts in <program folder> itself, so the program folder is two levels
     up.  Anywhere else is refused: the script is looked for at ONE fixed place relative to this file, never beside whatever it was copied to.
     (Found at the first real build, 21 Nov 26: the VM test had put the exe and the scripts in one folder, which the install never does.) */
  {
    const WCHAR* tail = L"\\usr\\bin";
    size_t len = wcslen(appdir), tl = wcslen(tail);
    if (len <= tl || _wcsicmp(appdir + len - tl, tail) != 0) {
      sr_line(out, "sdrestore: NOT RUN, this program is not in <program folder>\\usr\\bin (it is in %ls)", appdir);
      goto done;
    }
    appdir[len - tl] = L'\0';
  }
  swprintf(script, MAX_PATH, L"%ls\\sd-restore-kept.ps1", appdir);
  sattr = GetFileAttributesW(script);
  if (sattr == INVALID_FILE_ATTRIBUTES || (sattr & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) {
    sr_line(out, "sdrestore: NOT RUN, %ls is not a plain file", script);
    goto done;
  }
  if (GetSystemDirectoryW(sysdir, MAX_PATH) == 0) {
    sr_line(out, "sdrestore: NOT RUN, the system folder is not known");
    goto done;
  }
  swprintf(ps, MAX_PATH, L"%ls\\WindowsPowerShell\\v1.0\\powershell.exe", sysdir);
  swprintf(cmd, 2 * MAX_PATH + 160, L"\"%ls\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%ls\"", ps, script);

  /* SDSYS, by S4U (SeTcb: LocalSystem), made primary, and ELEVATED or nothing. */
  imp = (HANDLE)win32_s4u_logon(SR_ACCOUNT);
  if (imp == NULL) {
    sr_line(out, "sdrestore: NOT RUN, the account %s could not be logged on by S4U (is it there?)", SR_ACCOUNT);
    goto done;
  }
  if (!DuplicateTokenEx(imp, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation, TokenPrimary, &prim)) {
    sr_line(out, "sdrestore: NOT RUN, DuplicateTokenEx failed (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  if (!GetTokenInformation(prim, TokenElevation, &el, sizeof(el), &n) || !el.TokenIsElevated) {
    sr_line(out, "sdrestore: NOT RUN, the S4U logon of %s is not elevated", SR_ACCOUNT);
    goto done;
  }

  if (!CreateEnvironmentBlock(&env, prim, FALSE))
    env = NULL;

  /* The job: this process's end ends the child. */
  job = CreateJobObjectA(NULL, NULL);
  ZeroMemory(&jl, sizeof(jl));
  jl.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
  if (job == NULL || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &jl, sizeof(jl))) {
    sr_line(out, "sdrestore: NOT RUN, the job could not be made (error %lu)", (unsigned long)GetLastError());
    goto done;
  }

  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = nul;
  si.hStdOutput = out;
  si.hStdError = out;
  si.lpDesktop = (WCHAR*)L"winsta0\\default"; /* as the SDSYS door, and the probe: an S4U child starts with it */
  if (!CreateProcessAsUserW(prim, ps, cmd, NULL, NULL, TRUE, CREATE_SUSPENDED | CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, env, appdir, &si, &pi)) {
    si.lpDesktop = NULL;
    if (!CreateProcessAsUserW(prim, ps, cmd, NULL, NULL, TRUE, CREATE_SUSPENDED | CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, env, appdir, &si, &pi)) {
      sr_line(out, "sdrestore: NOT RUN, the child could not be started as %s (CreateProcessAsUser error %lu)", SR_ACCOUNT, (unsigned long)GetLastError());
      goto done;
    }
  }
  started = 1;
  if (!AssignProcessToJobObject(job, pi.hProcess)) {
    sr_line(out, "sdrestore: NOT RUN, the child could not be put in its job (error %lu); it was not let run", (unsigned long)GetLastError());
    TerminateProcess(pi.hProcess, 1);
    goto done;
  }
  ResumeThread(pi.hThread);

  w = WaitForSingleObject(pi.hProcess, SR_TIMEOUT_MS);
  if (w == WAIT_TIMEOUT) {
    TerminateProcess(pi.hProcess, 1);
    sr_line(out, "sdrestore: the child did not finish in %d seconds and was ended", SR_TIMEOUT_MS / 1000);
    goto done;
  }
  if (w != WAIT_OBJECT_0 || !GetExitCodeProcess(pi.hProcess, &code))
    code = 1;
  sr_line(out, "sdrestore: child exit %lu", (unsigned long)code);
  rc = (code == 0) ? 0 : 1;

done:
  if (started) {
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
  }
  if (env != NULL)
    DestroyEnvironmentBlock(env);
  if (job != NULL)
    CloseHandle(job);
  if (prim != NULL)
    CloseHandle(prim);
  if (imp != NULL)
    CloseHandle(imp);
  if (nul != INVALID_HANDLE_VALUE)
    CloseHandle(nul);
  if (out != INVALID_HANDLE_VALUE)
    CloseHandle(out);
  return (rc == 2) ? 1 : rc;
}

/* END-CODE */
