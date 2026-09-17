/* WIN32SESSION.C
 * Spawn an authenticated API session AS the user, over a named pipe.
 * RELEASE_1.1 55, direction (a), Linux parity.  See win32session.h.
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
 * 17 Sep 26 Windows port - written for RELEASE_1.1 55.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * windows.h and NO SD header, the rule every win32*.c file follows (sd.h's
 * Private/STRING/Sleep macros collide with windows.h), so malloc not k_alloc.
 * The token work is win32relay.c's, MINUS the privilege strip and the Low
 * integrity drop: this is the user's own session and keeps the user's own
 * rights, the way a Linux setuid session keeps the user's uid and groups.
 *
 * END-DESCRIPTION
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <userenv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "win32s4u.h"     /* win32_s4u_logon(); no SD header */
#include "win32session.h"

static void win_error(const char* what, char* why, size_t whylen) {
  DWORD e = GetLastError();
  char* text = NULL;
  size_t n;
  FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                     FORMAT_MESSAGE_IGNORE_INSERTS,
                 NULL, e, 0, (LPSTR)&text, 0, NULL);
  snprintf(why, whylen, "%s: error %lu %s", what, (unsigned long)e,
           text ? text : "");
  if (text)
    LocalFree(text);
  for (n = 0; n < whylen && why[n]; n++)
    if (why[n] == '\r' || why[n] == '\n')
      why[n] = ' ';
}

/* The session runs sd itself - the front IS sd, so its own image is the one to
   start.  A native CreateProcess wants a Windows path; GetModuleFileName gives
   one (exe_directory() would answer a POSIX path, the trap sdpy_session.c and
   win32relay.c both record). */
static int self_path(char* out, size_t outlen, char* why, size_t whylen) {
  DWORD n = GetModuleFileNameA(NULL, out, (DWORD)outlen);
  if (n == 0 || n >= outlen) {
    win_error("GetModuleFileName", why, whylen);
    return 0;
  }
  return 1;
}

/* One inheritable duplicate of h in this process. */
static int dup_inh(HANDLE h, HANDLE* out) {
  return DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), out, 0,
                         TRUE, DUPLICATE_SAME_ACCESS);
}

int win32_session_spawn(const char* username, const char* pipename,
                        void** proc, unsigned long* pid, char* why,
                        size_t whylen) {
  char exe[MAX_PATH];
  char cmd[MAX_PATH + 32];
  HANDLE imp = NULL;
  HANDLE prim = NULL;
  HANDLE client = INVALID_HANDLE_VALUE;
  HANDLE in = NULL;
  HANDLE out = NULL;
  HANDLE nul = INVALID_HANDLE_VALUE;
  HANDLE list[3];
  SECURITY_ATTRIBUTES sa;
  STARTUPINFOEXA six;
  PROCESS_INFORMATION pi;
  SIZE_T alen = 0;
  void* env = NULL;
  int ok = 0;

  *proc = NULL;
  if (pid)
    *pid = 0;
  ZeroMemory(&six, sizeof six);
  ZeroMemory(&pi, sizeof pi);
  six.StartupInfo.cb = sizeof six;

  if ((username == NULL) || (*username == '\0') || (pipename == NULL) ||
      (*pipename == '\0')) {
    snprintf(why, whylen, "win32_session_spawn: empty username or pipe name");
    return 0;
  }
  if (!self_path(exe, sizeof exe, why, whylen))
    return 0;

  /* The client end.  NOT overlapped: the session reads and writes it as
     ordinary descriptors 0 and 1 through Cygwin's fhandler_pipe, and
     overlapped-ness is a property of the handle, not of the pipe - the
     relay's server end is overlapped and this one need not be. */
  client = CreateFileA(pipename, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                       OPEN_EXISTING, 0, NULL);
  if (client == INVALID_HANDLE_VALUE) {
    char what[512];
    snprintf(what, sizeof what, "open the handover pipe %.300s", pipename);
    win_error(what, why, whylen);
    return 0;
  }

  /* The user's token, minted on the front's SeTcb - no password.  Impersonation
     level from S4U; CreateProcessAsUser wants a primary token. */
  imp = (HANDLE)win32_s4u_logon(username);
  if (imp == NULL) {
    snprintf(why, whylen,
             "cannot log the user %s on by S4U: does the account exist, and is "
             "this process LocalSystem (SeTcb)?",
             username);
    return 0;
  }
  if (!DuplicateTokenEx(imp, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation,
                        TokenPrimary, &prim)) {
    win_error("DuplicateTokenEx(primary)", why, whylen);
    goto done;
  }

  /* The pipe on the session's std handles: TWO inheritable copies, one per
     descriptor (win32pipe.c - sharing one handle across 0 and 1 breaks the
     Cygwin fhandler and its select), handed over as std handles the way the
     shipping -C1!0 path does; the session then reads/writes 0/1 directly with
     working select (probe-pipestd), NOT cygwin_attach_handle_to_fd. */
  if (!dup_inh(client, &in) || !dup_inh(client, &out)) {
    win_error("DuplicateHandle(pipe)", why, whylen);
    goto done;
  }
  /* An inheritable NUL for stderr - the session's diagnostics go to syslog, not
     a descriptor, and USESTDHANDLES needs all three set. */
  sa.nLength = sizeof sa;
  sa.lpSecurityDescriptor = NULL;
  sa.bInheritHandle = TRUE;
  nul = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &sa, OPEN_EXISTING,
                    0, NULL);
  if (nul == INVALID_HANDLE_VALUE) {
    win_error("open NUL", why, whylen);
    goto done;
  }

  six.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  six.StartupInfo.hStdInput = in;
  six.StartupInfo.hStdOutput = out;
  six.StartupInfo.hStdError = nul;
  /* Exactly these three cross, nothing else (win32relay.c's correctness point:
     bInheritHandles alone would copy every inheritable handle the front holds,
     including the relay's and the pipe's server end). */
  list[0] = in;
  list[1] = out;
  list[2] = nul;
  InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
  six.lpAttributeList =
      (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, alen);
  if (six.lpAttributeList == NULL ||
      !InitializeProcThreadAttributeList(six.lpAttributeList, 1, 0, &alen) ||
      !UpdateProcThreadAttribute(six.lpAttributeList, 0,
                                 PROC_THREAD_ATTRIBUTE_HANDLE_LIST, list,
                                 sizeof list, NULL, NULL)) {
    win_error("PROC_THREAD_ATTRIBUTE_HANDLE_LIST", why, whylen);
    goto done;
  }

  /* NO privilege strip and NO integrity drop - the user's own session, the
     user's own rights (win32session.h).  -H: a pre-authenticated API session
     whose I/O is already on 0/1; -N is the API connection type.  NOT -A:
     sd.c folds the option letter with UpperCase() and -A is already "query
     account", so a session spawned with it would ask for an account name and
     never set api_preauth. */
  if (snprintf(cmd, sizeof cmd, "\"%s\" -N -H", exe) >= (int)sizeof cmd) {
    snprintf(why, whylen, "session command line too long");
    goto done;
  }

  /* The user's own environment, or the UCRT child has no SystemRoot and will
     not start (the win32relay.c lesson). */
  if (!CreateEnvironmentBlock(&env, prim, FALSE))
    env = NULL;

  six.StartupInfo.lpDesktop = (char*)"winsta0\\default";
  if (!CreateProcessAsUserA(prim, exe, cmd, NULL, NULL, TRUE,
                            CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT |
                                (env ? CREATE_UNICODE_ENVIRONMENT : 0),
                            env, NULL, &six.StartupInfo, &pi)) {
    win_error("CreateProcessAsUser(session)", why, whylen);
    goto done;
  }
  CloseHandle(pi.hThread);
  *proc = (void*)pi.hProcess;
  if (pid)
    *pid = pi.dwProcessId;
  ok = 1;

done:
  /* The child holds its own copies now; the front keeps none of them, and
     none of the client end either.  A copy left open here would mean the
     session's close never reaches the relay and the connection would hang
     rather than end. */
  if (client != INVALID_HANDLE_VALUE)
    CloseHandle(client);
  if (in)
    CloseHandle(in);
  if (out)
    CloseHandle(out);
  if (nul != INVALID_HANDLE_VALUE)
    CloseHandle(nul);
  if (six.lpAttributeList) {
    DeleteProcThreadAttributeList(six.lpAttributeList);
    HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
  }
  if (env)
    DestroyEnvironmentBlock(env);
  if (prim)
    CloseHandle(prim);
  if (imp)
    CloseHandle(imp);
  return ok;
}

void win32_session_close(void* proc) {
  if (proc)
    CloseHandle((HANDLE)proc);
}

/* END-CODE */
