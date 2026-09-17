/* WIN32RELAY.C
 * Native Windows half of the API's TLS relay: start sdtlsrelay.exe as the
 * bare relay account, at Low integrity, with exactly two inherited handles.
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
 * 17 Sep 26 Windows port - RELEASE_1.1 55: a THIRD inherited descriptor, the
 *           control socketpair the front uses to have the relay stand up the
 *           authenticated session's pipe.  It is passed the same way as the
 *           other two and for the same reason (sd_tls.h's control section).
 * 16 Sep 26 Windows port - written for RELEASE_1.1 43.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * This file includes windows.h and NO SD header, as win32tls.c, win32s4u.c
 * and win32sem.c do and for the same reason.  Its interface is in sd_tls.h
 * with no Windows type in it; sd_tlssrv.c calls it with Cygwin descriptors.
 *
 * THE DROP, IN ORDER.  sd - LocalSystem, in the session process - is the
 * only party that can do any of this, which is why the relay is spawned and
 * not fork()ed: Cygwin's seteuid to another account needs SeTcb (gplbld/
 * probe-svcimp), and a Cygwin child cannot start at Low while sd holds the
 * runtime (probe-lowmsys).  So:
 *
 *   1. win32_s4u_logon(SD_RELAY_ACCOUNT)   the bare account's token, minted
 *                                          on sd's own SeTcb - no password
 *                                          exists for it, none is needed
 *   2. DuplicateTokenEx -> primary         CreateProcessAsUser wants one
 *   3. AdjustTokenPrivileges, REMOVED      every privilege, permanently -
 *                                          removed, not disabled, so the
 *                                          child cannot re-enable one
 *   4. TokenIntegrityLevel = Low           RELEASE_1.1 53: at Medium an
 *                                          ordinary account can open the SD
 *                                          runtime's shared section for
 *                                          write; at Low it cannot
 *   5. CreateProcessAsUser, SeAssignPrimaryToken, which LocalSystem holds
 *
 * Every step measured by gplbld/probe-relaydrop.c iteration 5, owner-
 * elevated: child ran as the bare account, privilege count 0, Low.
 *
 * THE HANDLE LIST IS CORRECTNESS, NOT HYGIENE.  Every socket handle Cygwin
 * creates carries HANDLE_FLAG_INHERIT (measured, gplbld/probe-relaysp.c), so
 * bInheritHandles=TRUE on its own would copy EVERY socket sd holds into the
 * relay - and a socket with a live handle in another process does not close.
 * In that probe's first run the relay had inherited the client's own end,
 * and the client's close never reached sd.  PROC_THREAD_ATTRIBUTE_HANDLE_LIST
 * names the three the relay may have, and nothing else crosses.
 *
 * WHERE THE RELAY IS: beside sd.exe, from GetModuleFileName - the native
 * answer exepath.c's header names.  exe_directory() is not used because it
 * answers a POSIX path and this is a native CreateProcess (the trap
 * sdpy_session.c paid for), and because its bool is sd.h's int16_t, which
 * this file may not include.
 *
 * END-DESCRIPTION
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <userenv.h>
#include <io.h>                        /* _get_osfhandle: a Cygwin fd's HANDLE */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "win32s4u.h"                  /* win32_s4u_logon(); no SD header */

/* Declared in sd_tls.h; repeated so this file includes no SD header. */
int win32_relay_spawn(const char* account, int net_fd, int sp_fd, int ctl_fd,
                      int timeout_ms, void** proc, char* why, size_t whylen);
int win32_relay_exit_code(void* proc, int wait_ms);

#define RELAY_EXE_NAME "sdtlsrelay.exe"        /* SD_RELAY_EXE in sd_tls.h */

/* ====================================================================== */

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

/* Remove EVERY privilege from the token.  SE_PRIVILEGE_REMOVED, not
   disabled: a disabled privilege can be enabled again by the holder. */
static int strip_privileges(HANDLE tok, char* why, size_t whylen) {
  BYTE buf[8192];
  DWORD len = 0;
  TOKEN_PRIVILEGES* tp;
  DWORD i;

  if (!GetTokenInformation(tok, TokenPrivileges, buf, sizeof(buf), &len)) {
    win_error("GetTokenInformation(privileges)", why, whylen);
    return 0;
  }
  tp = (TOKEN_PRIVILEGES*)buf;
  for (i = 0; i < tp->PrivilegeCount; i++)
    tp->Privileges[i].Attributes = SE_PRIVILEGE_REMOVED;
  if (tp->PrivilegeCount > 0 &&
      !AdjustTokenPrivileges(tok, FALSE, tp, 0, NULL, NULL)) {
    win_error("AdjustTokenPrivileges(remove all)", why, whylen);
    return 0;
  }
  /* AdjustTokenPrivileges can return TRUE having done only part of the job;
     ask again rather than believe it. */
  len = 0;
  if (!GetTokenInformation(tok, TokenPrivileges, buf, sizeof(buf), &len) ||
      ((TOKEN_PRIVILEGES*)buf)->PrivilegeCount != 0) {
    snprintf(why, whylen, "the relay token still holds %lu privilege(s)",
             (unsigned long)((TOKEN_PRIVILEGES*)buf)->PrivilegeCount);
    return 0;
  }
  return 1;
}

/* Low integrity, S-1-16-4096. */
static int set_low_integrity(HANDLE tok, char* why, size_t whylen) {
  PSID low = NULL;
  TOKEN_MANDATORY_LABEL tml;
  int ok;

  if (!ConvertStringSidToSidA("S-1-16-4096", &low)) {
    win_error("ConvertStringSidToSid(Low)", why, whylen);
    return 0;
  }
  tml.Label.Attributes = SE_GROUP_INTEGRITY;
  tml.Label.Sid = low;
  ok = SetTokenInformation(tok, TokenIntegrityLevel, &tml,
                           sizeof(tml) + GetLengthSid(low));
  if (!ok)
    win_error("SetTokenInformation(Low)", why, whylen);
  LocalFree(low);
  return ok;
}

/* The relay's path: beside this executable.  dir gets the directory, which
   is also the child's working directory - a place the bare account can at
   least read (Program Files grants Users), where sd's own cwd may not be. */
static int relay_path(char* dir, size_t dirlen, char* out, size_t outlen,
                      char* why, size_t whylen) {
  DWORD n = GetModuleFileNameA(NULL, dir, (DWORD)dirlen);
  char* slash;

  if (n == 0 || n >= dirlen) {
    win_error("GetModuleFileName", why, whylen);
    return 0;
  }
  slash = strrchr(dir, '\\');
  if (slash == NULL) {
    snprintf(why, whylen, "cannot find the directory of %s", dir);
    return 0;
  }
  *slash = '\0';
  if (snprintf(out, outlen, "%s\\%s", dir, RELAY_EXE_NAME) >= (int)outlen) {
    snprintf(why, whylen, "relay path too long");
    return 0;
  }
  if (GetFileAttributesA(out) == INVALID_FILE_ATTRIBUTES) {
    snprintf(why, whylen, "%s is missing: was the install complete?", out);
    return 0;
  }
  return 1;
}

static int dup_inheritable(HANDLE h, HANDLE* out, const char* what, char* why,
                           size_t whylen) {
  if (!DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), out, 0,
                       TRUE, DUPLICATE_SAME_ACCESS)) {
    win_error(what, why, whylen);
    return 0;
  }
  return 1;
}

/* ======================================================================
   win32_relay_spawn()                                                    */

int win32_relay_spawn(const char* account, int net_fd, int sp_fd, int ctl_fd,
                      int timeout_ms, void** proc, char* why, size_t whylen) {
  char dir[MAX_PATH];
  char exe[MAX_PATH + 32];
  char cmd[MAX_PATH + 160];
  HANDLE imp = NULL;
  HANDLE prim = NULL;
  HANDLE net = INVALID_HANDLE_VALUE;
  HANDLE sp = INVALID_HANDLE_VALUE;
  HANDLE ctl = INVALID_HANDLE_VALUE;
  HANDLE netInh = NULL;
  HANDLE spInh = NULL;
  HANDLE ctlInh = NULL;
  HANDLE list[3];
  STARTUPINFOEXA six;
  PROCESS_INFORMATION pi;
  SIZE_T alen = 0;
  void* env = NULL;
  int ok = 0;

  *proc = NULL;
  ZeroMemory(&six, sizeof(six));
  ZeroMemory(&pi, sizeof(pi));

  if (!relay_path(dir, sizeof(dir), exe, sizeof(exe), why, whylen))
    return 0;

  net = (HANDLE)_get_osfhandle(net_fd);
  sp = (HANDLE)_get_osfhandle(sp_fd);
  ctl = (HANDLE)_get_osfhandle(ctl_fd);
  if (net == INVALID_HANDLE_VALUE || sp == INVALID_HANDLE_VALUE ||
      ctl == INVALID_HANDLE_VALUE) {
    snprintf(why, whylen,
             "no Windows handle behind descriptor %d, %d or %d", net_fd, sp_fd,
             ctl_fd);
    return 0;
  }

  /* 1-4: the token. */
  imp = (HANDLE)win32_s4u_logon(account);
  if (imp == NULL) {
    snprintf(why, whylen,
             "cannot log the relay account %s on: does it exist (install-service.ps1), "
             "and is this process LocalSystem?", account);
    return 0;
  }
  if (!DuplicateTokenEx(imp, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation,
                        TokenPrimary, &prim)) {
    win_error("DuplicateTokenEx(primary)", why, whylen);
    goto done;
  }
  if (!strip_privileges(prim, why, whylen) ||
      !set_low_integrity(prim, why, whylen))
    goto done;

  /* The three handles, and ONLY the three (description block). */
  if (!dup_inheritable(net, &netInh, "DuplicateHandle(connection)", why,
                       whylen) ||
      !dup_inheritable(sp, &spInh, "DuplicateHandle(socketpair)", why, whylen) ||
      !dup_inheritable(ctl, &ctlInh, "DuplicateHandle(control)", why, whylen))
    goto done;
  list[0] = netInh;
  list[1] = spInh;
  list[2] = ctlInh;

  InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
  six.lpAttributeList =
      (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, alen);
  if (six.lpAttributeList == NULL ||
      !InitializeProcThreadAttributeList(six.lpAttributeList, 1, 0, &alen) ||
      !UpdateProcThreadAttribute(six.lpAttributeList, 0,
                                 PROC_THREAD_ATTRIBUTE_HANDLE_LIST, list,
                                 sizeof(list), NULL, NULL)) {
    win_error("PROC_THREAD_ATTRIBUTE_HANDLE_LIST", why, whylen);
    goto done;
  }
  six.StartupInfo.cb = sizeof(six);
  six.StartupInfo.lpDesktop = (char*)"winsta0\\default";

  snprintf(cmd, sizeof(cmd), "\"%s\" %llu %llu %llu %d", exe,
           (unsigned long long)(uintptr_t)netInh,
           (unsigned long long)(uintptr_t)spInh,
           (unsigned long long)(uintptr_t)ctlInh, timeout_ms);

  /* The account's own environment block: without one the child has no
     SystemRoot, and the UCRT refuses to start. */
  if (!CreateEnvironmentBlock(&env, prim, FALSE))
    env = NULL;

  /* 5. */
  if (!CreateProcessAsUserA(prim, exe, cmd, NULL, NULL, TRUE,
                            CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT |
                                (env ? CREATE_UNICODE_ENVIRONMENT : 0),
                            env, dir, &six.StartupInfo, &pi)) {
    win_error("CreateProcessAsUser(sdtlsrelay)", why, whylen);
    goto done;
  }
  CloseHandle(pi.hThread);
  *proc = (void*)pi.hProcess;
  ok = 1;

done:
  /* The child holds its own copies now; sd keeps none of the inheritable
     duplicates, or the connection would stay open after the relay ends. */
  if (netInh)
    CloseHandle(netInh);
  if (spInh)
    CloseHandle(spInh);
  if (ctlInh)
    CloseHandle(ctlInh);
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

/* ======================================================================
   win32_relay_exit_code()                                                */

int win32_relay_exit_code(void* proc, int wait_ms) {
  HANDLE h = (HANDLE)proc;
  DWORD code = 0;
  int result = -1;

  if (h == NULL)
    return -1;
  if (WaitForSingleObject(h, (DWORD)(wait_ms < 0 ? 0 : wait_ms)) ==
          WAIT_OBJECT_0 &&
      GetExitCodeProcess(h, &code))
    result = (int)code;
  CloseHandle(h);
  return result;
}

/* END-CODE */
