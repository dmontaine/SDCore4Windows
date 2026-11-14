/* WIN32RUNIN.C
 * RUN.IN ... DEBUG on Windows, sd.exe's half: the debugged child's door, and the SDSYS session's end of a run.
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
 * 13 Nov 26 Windows port - written.  RELEASE_1.1 253(b); win32runin.h has the design and the wire.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * windows.h and NO SD header, the rule every win32*.c file follows.  sd.exe links this (gpl.src);
 * gplbld/test-runindebug-units.py also builds it natively beside the service's half.
 *
 * THE CHILD'S DOOR (win32_runin_child_verify) READS THE PROCESS TOKEN AND NOTHING ELSE.  A command line and an
 * environment are what anybody may type; the token is what the kernel gave the process.  Every test is of something
 * the service did (sdsvc/sdrunin.c) and none trusts that it did it: the user, elevation, privileges, integrity, the
 * Administrators group.  A failure says which.
 *
 * THE SESSION'S END (win32_runin_open and the rest).  As win32auditpipe.c: the pipe's OWNER must be LocalSystem (a
 * non-administrator cannot make an object owned by SYSTEM, and the name is open to anybody while the service is down),
 * and the client offers only SECURITY_IDENTIFICATION, so the service can learn who asks and cannot act as them.  The
 * pipe is not overlapped; reads are asked with PeekNamedPipe first, so the relay never waits on the child.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "win32runin.h"

#define RUNIN_PIPE_ACCESS (FILE_READ_DATA | FILE_WRITE_DATA | READ_CONTROL | SYNCHRONIZE)
#define RUNIN_ANSWER_MS 30000 /* the service logs the child on and starts it before it answers */

static HANDLE runin_pipe = INVALID_HANDLE_VALUE;

static void say(char* why, int whylen, const char* text) {
  if ((why != NULL) && (whylen > 0))
    snprintf(why, (size_t)whylen, "%s", text);
}

/* ======================================================================
   The child's door                                                         */

int win32_runin_child_verify(char* groups, int glen, char* why, int whylen) {
  HANDLE tok = NULL;
  BYTE ubuf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  BYTE* gbuf = NULL;
  BYTE pbuf[64];
  BYTE ibuf[sizeof(TOKEN_MANDATORY_LABEL) + SECURITY_MAX_SID_SIZE];
  TOKEN_ELEVATION elev;
  TOKEN_GROUPS* tg;
  TOKEN_MANDATORY_LABEL* tml;
  DWORD n = 0;
  DWORD i;
  DWORD rid;
  char name[257];
  char dom[257];
  char host[MAX_COMPUTERNAME_LENGTH + 1];
  DWORD nl;
  DWORD dl;
  DWORD hl = sizeof(host);
  SID_NAME_USE use;
  int used = 0;
  int ok = 0;

  if ((groups != NULL) && (glen > 0))
    groups[0] = '\0';
  say(why, whylen, "");

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
    say(why, whylen, "the process token cannot be read");
    return 0;
  }
  if (!GetComputerNameA(host, &hl)) {
    say(why, whylen, "the computer name cannot be read");
    goto done;
  }

  /* 1. THE USER: the local account the service logs on, by name, on this machine. */
  nl = sizeof(name);
  dl = sizeof(dom);
  if (!GetTokenInformation(tok, TokenUser, ubuf, sizeof(ubuf), &n) ||
      !LookupAccountSidA(NULL, ((TOKEN_USER*)ubuf)->User.Sid, name, &nl, dom, &dl, &use) ||
      (lstrcmpiA(name, SD_RUNIN_ACCOUNT) != 0) || (lstrcmpiA(dom, host) != 0)) { /* not _stricmp: not in the MSYS2 runtime */
    say(why, whylen, "this process is not the run.in account " SD_RUNIN_ACCOUNT " of this machine");
    goto done;
  }

  /* 2. NOT ELEVATED. */
  n = 0;
  if (!GetTokenInformation(tok, TokenElevation, &elev, sizeof(elev), &n) || elev.TokenIsElevated) {
    say(why, whylen, "the process token is elevated");
    goto done;
  }

  /* 3. NO PRIVILEGE AT ALL: the service removed them, not disabled them. */
  n = 0;
  if (!GetTokenInformation(tok, TokenPrivileges, pbuf, sizeof(pbuf), &n) ||
      (((TOKEN_PRIVILEGES*)pbuf)->PrivilegeCount != 0)) {
    say(why, whylen, "the process token holds a privilege");
    goto done;
  }

  /* 4. MEDIUM INTEGRITY OR LOWER. */
  n = 0;
  if (!GetTokenInformation(tok, TokenIntegrityLevel, ibuf, sizeof(ibuf), &n)) {
    say(why, whylen, "the process integrity cannot be read");
    goto done;
  }
  tml = (TOKEN_MANDATORY_LABEL*)ibuf;
  rid = *GetSidSubAuthority(tml->Label.Sid, (DWORD)(*GetSidSubAuthorityCount(tml->Label.Sid) - 1));
  if (rid > SECURITY_MANDATORY_MEDIUM_RID) {
    say(why, whylen, "the process integrity is above Medium");
    goto done;
  }

  /* 5. THE GROUPS: no enabled Administrators; the enabled groups of this machine are handed back by name. */
  n = 0;
  (void)GetTokenInformation(tok, TokenGroups, NULL, 0, &n);
  if ((n == 0) || ((gbuf = (BYTE*)malloc(n)) == NULL) || !GetTokenInformation(tok, TokenGroups, gbuf, n, &n)) {
    say(why, whylen, "the process groups cannot be read");
    goto done;
  }
  tg = (TOKEN_GROUPS*)gbuf;
  for (i = 0; i < tg->GroupCount; i++) {
    if (!(tg->Groups[i].Attributes & SE_GROUP_ENABLED) || (tg->Groups[i].Attributes & SE_GROUP_USE_FOR_DENY_ONLY))
      continue;
    if (IsWellKnownSid(tg->Groups[i].Sid, WinBuiltinAdministratorsSid)) {
      say(why, whylen, "the process token has the Administrators group enabled");
      goto done;
    }
    nl = sizeof(name);
    dl = sizeof(dom);
    if (!LookupAccountSidA(NULL, tg->Groups[i].Sid, name, &nl, dom, &dl, &use))
      continue;
    if ((lstrcmpiA(dom, host) != 0) || ((use != SidTypeAlias) && (use != SidTypeGroup)))
      continue;
    if ((groups != NULL) && (glen > 0) && (used + (int)strlen(name) + 2 < glen)) {
      used += snprintf(groups + used, (size_t)(glen - used), "%s%s", (used > 0) ? "," : "", name);
    }
  }
  ok = 1;

done:
  if (gbuf != NULL)
    free(gbuf);
  CloseHandle(tok);
  return ok;
}

/* ======================================================================
   The SDSYS session's end of a run                                         */

static BOOL runin_owner_is_system(HANDLE h) {
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  BOOL is_system = FALSE;

  if (GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, &sd) == ERROR_SUCCESS)
    is_system = (owner != NULL) && IsWellKnownSid(owner, WinLocalSystemSid);
  if (sd != NULL)
    LocalFree(sd);
  return is_system;
}

int win32_runin_is_open(void) {
  return runin_pipe != INVALID_HANDLE_VALUE;
}

void win32_runin_close(void) {
  if (runin_pipe != INVALID_HANDLE_VALUE)
    CloseHandle(runin_pipe);
  runin_pipe = INVALID_HANDLE_VALUE;
}

int win32_runin_open(const char* request, char* answer, int alen) {
  return win32_runin_open_to(SD_RUNIN_PIPE, 1, request, answer, alen);
}

int win32_runin_open_to(const char* pipe_name, int need_system_owner, const char* request, char* answer, int alen) {
  HANDLE h;
  DWORD mode = PIPE_READMODE_BYTE;
  DWORD n = 0;
  DWORD waited = 0;
  DWORD avail;
  int len;
  int got = 0;
  char c;

  say(answer, alen, "");
  if (runin_pipe != INVALID_HANDLE_VALUE) {
    say(answer, alen, "a run is already open in this session");
    return -1;
  }
  len = (request == NULL) ? 0 : (int)strlen(request);
  if ((len == 0) || (len >= RUNIN_LINE_MAX) || (request[len - 1] != '\n')) {
    say(answer, alen, "the request is not one line");
    return -1;
  }

  h = CreateFileA(pipe_name, RUNIN_PIPE_ACCESS, 0, NULL, OPEN_EXISTING,
                  SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    if (GetLastError() == ERROR_PIPE_BUSY) {
      say(answer, alen, "the SD service is serving as many runs as it takes; try again when one ends");
    } else if (GetLastError() == ERROR_ACCESS_DENIED) {
      say(answer, alen, "the SD service refused this session (an elevated administrator's session is needed)");
    } else {
      snprintf(answer, (size_t)alen, "the SD service's run.in pipe cannot be opened (error %lu): is the service running?",
               (unsigned long)GetLastError());
    }
    return -1;
  }
  if (need_system_owner && !runin_owner_is_system(h)) {
    CloseHandle(h);
    say(answer, alen, "the run.in pipe is not the SD service's (its owner is not LocalSystem); nothing was sent");
    return -1;
  }
  (void)SetNamedPipeHandleState(h, &mode, NULL, NULL);

  if (!WriteFile(h, request, (DWORD)len, &n, NULL) || (n != (DWORD)len)) {
    CloseHandle(h);
    say(answer, alen, "the request could not be sent to the SD service");
    return -1;
  }

  /* The answer line, a byte at a time so that nothing of the child's screen after it is taken. */
  for (;;) {
    avail = 0;
    if (!PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL)) {
      CloseHandle(h);
      if (got > 0) {
        answer[(got < alen) ? got : alen - 1] = '\0';
        if (strncmp(answer, "ER ", 3) == 0) {
          memmove(answer, answer + 3, strlen(answer + 3) + 1);
          return -1;
        }
      }
      say(answer, alen, "the SD service ended the run before it answered");
      return -1;
    }
    if (avail == 0) {
      if (waited >= RUNIN_ANSWER_MS) {
        CloseHandle(h);
        say(answer, alen, "the SD service did not answer");
        return -1;
      }
      SleepEx(20, FALSE); /* not Sleep(): linuxlb.c defines SD's own Sleep(), and kernel32's stub would clash at link (13 Nov 26) */
      waited += 20;
      continue;
    }
    if (!ReadFile(h, &c, 1, &n, NULL) || (n != 1)) {
      CloseHandle(h);
      say(answer, alen, "the SD service's answer could not be read");
      return -1;
    }
    if (c == '\n')
      break;
    if ((got + 1 < alen) && ((unsigned char)c >= 32))
      answer[got++] = c;
    if (got + 1 >= RUNIN_LINE_MAX) {
      CloseHandle(h);
      say(answer, alen, "the SD service's answer is too long");
      return -1;
    }
  }
  answer[got] = '\0';

  /* Anchored on the success wording, and refused on anything else. */
  if (strncmp(answer, "OK ", 3) == 0) {
    memmove(answer, answer + 3, strlen(answer + 3) + 1);
    runin_pipe = h;
    return 0;
  }
  CloseHandle(h);
  if (strncmp(answer, "ER ", 3) == 0)
    memmove(answer, answer + 3, strlen(answer + 3) + 1);
  else if (answer[0] == '\0')
    say(answer, alen, "the SD service gave an empty answer");
  return -1;
}

int win32_runin_read(char* buf, int len) {
  DWORD avail = 0;
  DWORD n = 0;

  if (runin_pipe == INVALID_HANDLE_VALUE)
    return -1;
  if (!PeekNamedPipe(runin_pipe, NULL, 0, NULL, &avail, NULL))
    return -1; /* broken: the child has ended and the service has closed the run */
  if (avail == 0)
    return 0;
  if (avail > (DWORD)len)
    avail = (DWORD)len;
  if (!ReadFile(runin_pipe, buf, avail, &n, NULL))
    return -1;
  return (int)n;
}

int win32_runin_write(const char* buf, int len) {
  DWORD n = 0;

  if (runin_pipe == INVALID_HANDLE_VALUE)
    return -1;
  if (len <= 0)
    return 0;
  if (!WriteFile(runin_pipe, buf, (DWORD)len, &n, NULL) || (n != (DWORD)len))
    return -1;
  return 0;
}

/* END-CODE */
