/* WIN32AUDITPIPE.C
 * A session's half of the audit trail's writer: hand a record to the service.
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
 * 13 Nov 26 Windows port - written.  RELEASE_1.1 247 (Linux W.11 F4: k_error.c audit_to_daemon()) and RELEASE_1.1
 *           182 (LOCK.TRACER, Linux 7f7a4fd4).  win32auditpipe.h has the wire and the reasons.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * windows.h and NO SD header, as win32audit.c and win32sem.c: the two cannot share a translation unit.  sd.exe
 * links this (gpl.src); gplbld/test-auditwriter-units.py also builds it natively beside the service's half.
 *
 * WHAT THE CLIENT DOES NOT TRUST.  The pipe's name is open to anybody while the service is down, so a session
 * that found a pipe would hand its records to whoever made it.  So it asks two things of the pipe before it
 * writes: that its OWNER is LocalSystem (a non-administrator cannot make an object owned by SYSTEM - the service
 * sets that owner explicitly), and only SECURITY_IDENTIFICATION, so even a server that passed that test can learn
 * who the session is and cannot act as it.
 *
 * WHY IT WAITS FOR AN ANSWER, WHERE LINUX SENDS A DATAGRAM AND GOES.  Two reasons, both Windows ones.  The service
 * reads the session's token while the session is still connected, so the identity on the line is the one that
 * opened the pipe and not a later holder of a re-used pid.  And a record the service did not take is appended by
 * the session itself (option C1), which needs to know.  A LOCK.TRACER line has no fallback and does not wait.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <string.h>

#include "win32auditpipe.h"

/* What a session asks of the pipe: read the answer, write the record, read the owner.  NOT GENERIC_WRITE, whose
   FILE_APPEND_DATA is FILE_CREATE_PIPE_INSTANCE on a pipe - the service grants no member that, so asking for it
   would be refused.                                                                                              */
#define AUDIT_PIPE_ACCESS (FILE_READ_DATA | FILE_WRITE_DATA | READ_CONTROL | SYNCHRONIZE)

#define AUDIT_BUSY_TRIES 4     /* Linux's four short retries */
#define AUDIT_BUSY_WAIT_MS 20
#define AUDIT_WRITE_MS 500
#define AUDIT_ANSWER_MS 2000   /* the service may ask a domain controller for a name it has not seen */

/* ====================================================================== */

static BOOL pipe_owner_is_system(HANDLE h) {
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  BOOL is_system = FALSE;

  if (GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, &sd) ==
      ERROR_SUCCESS) {
    is_system = (owner != NULL) && IsWellKnownSid(owner, WinLocalSystemSid);
  }
  if (sd != NULL)
    LocalFree(sd);
  return is_system;
}

/* One overlapped read or write, given ms to finish; cancelled and FALSE if it does not. */
static BOOL pipe_io(HANDLE h, HANDLE ev, BOOL writing, void* buf, DWORD len, DWORD* done, DWORD ms) {
  OVERLAPPED ov;
  BOOL ok;

  *done = 0;
  ZeroMemory(&ov, sizeof(ov));
  ov.hEvent = ev;
  ResetEvent(ev);
  ok = writing ? WriteFile(h, buf, len, NULL, &ov) : ReadFile(h, buf, len, NULL, &ov);
  if (!ok && (GetLastError() != ERROR_IO_PENDING))
    return FALSE;
  if (WaitForSingleObject(ev, ms) != WAIT_OBJECT_0) {
    CancelIoEx(h, &ov);
    (void)GetOverlappedResult(h, &ov, done, TRUE);
    *done = 0;
    return FALSE;
  }
  return GetOverlappedResult(h, &ov, done, FALSE);
}

int audit_pipe_send(const char* name, int need_system_owner, const char* msg, int len, int want_answer,
                    char* answer) {
  HANDLE h = INVALID_HANDLE_VALUE;
  HANDLE ev;
  DWORD done;
  char reply = 0;
  int tries;
  BOOL ok;

  if ((name == NULL) || (msg == NULL) || (len <= 0) || (len > AUDIT_PIPE_MAX))
    return -1;

  for (tries = 0; tries < AUDIT_BUSY_TRIES; tries++) {
    h = CreateFileA(name, AUDIT_PIPE_ACCESS, 0, NULL, OPEN_EXISTING,
                    FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL);
    if (h != INVALID_HANDLE_VALUE)
      break;
    if (GetLastError() != ERROR_PIPE_BUSY)
      return -1; /* no service: the caller writes the record itself */
    (void)WaitNamedPipeA(name, AUDIT_BUSY_WAIT_MS);
  }
  if (h == INVALID_HANDLE_VALUE)
    return -1;

  if (need_system_owner && !pipe_owner_is_system(h)) {
    CloseHandle(h); /* somebody else's pipe under the service's name: not one byte to it */
    return -2;
  }

  if ((ev = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL) {
    CloseHandle(h);
    return -1;
  }

  ok = pipe_io(h, ev, TRUE, (void*)msg, (DWORD)len, &done, AUDIT_WRITE_MS) && (done == (DWORD)len);
  if (ok && want_answer)
    ok = pipe_io(h, ev, FALSE, &reply, 1, &done, AUDIT_ANSWER_MS) && (done == 1);

  CloseHandle(ev);
  CloseHandle(h);

  if (answer != NULL)
    *answer = ok ? reply : 0;
  return ok ? 0 : -1;
}

/* ====================================================================== */

int win32_audit_pipe_to(const char* name, int need_system_owner, const char* sysdir, const char* who,
                        const char* text) {
  char msg[AUDIT_PIPE_MAX];
  char answer = 0;
  int len;

  if ((sysdir == NULL) || (*sysdir == '\0') || (who == NULL) || (text == NULL))
    return -1;

  len = snprintf(msg, sizeof(msg), "%s%s\t%s\t%s", AUDIT_MAGIC, who, sysdir, text);
  if (len <= 0)
    return -1;
  if (len >= (int)sizeof(msg))
    len = (int)sizeof(msg) - 1; /* the text is cut, as Linux cuts a datagram */

  if (audit_pipe_send(name, need_system_owner, msg, len, 1, &answer) != 0)
    return -1;
  return (answer == AUDIT_ANSWER_TAKEN) ? 0 : -1;
}

int win32_audit_pipe(const char* sysdir, const char* who, const char* text) {
  return win32_audit_pipe_to(SD_AUDIT_PIPE, 1, sysdir, who, text);
}

int win32_locktrace_pipe_to(const char* name, int need_system_owner, const char* sysdir, const char* line, int len) {
  char msg[AUDIT_PIPE_MAX];
  int head;

  if ((sysdir == NULL) || (*sysdir == '\0') || (line == NULL) || (len <= 0))
    return -1;

  head = snprintf(msg, sizeof(msg), "%s%s\t", LOCKTRACE_MAGIC, sysdir);
  if ((head <= 0) || (head + len > (int)sizeof(msg)))
    return -1; /* a line that does not fit is not cut: a cut one would lose its newline */
  memcpy(msg + head, line, len); /* the line holds value marks: bytes, not a C string */

  return audit_pipe_send(name, need_system_owner, msg, head + len, 0, NULL);
}

void win32_locktrace_pipe(const char* sysdir, const char* line, int len) {
  (void)win32_locktrace_pipe_to(SD_AUDIT_PIPE, 1, sysdir, line, len);
}

/* ======================================================================
   win32_locktrace_create()  -  LOCK.TRACER ON: an empty trace only the service and the administrator can use

   Linux makes it mode 0620 in the system directory's group so that every session appends to it.  Here no session
   does - the service is the file's one writer - so the DACL is SYSTEM and Administrators, full control, and
   nothing for sdusers, protected so the directory's rights are not inherited back on top.  CREATE_ALWAYS empties
   an existing trace; the descriptor of an existing file is not replaced by CreateFile, so it is set on the handle
   afterwards either way.  A link or a directory in its place is refused, as Linux's O_NOFOLLOW refuses a link.  */

int win32_locktrace_create(const char* path) {
  PSECURITY_DESCRIPTOR sd = NULL;
  SECURITY_ATTRIBUTES sa;
  PACL dacl = NULL;
  BOOL present = FALSE;
  BOOL defaulted = FALSE;
  BY_HANDLE_FILE_INFORMATION info;
  DWORD attrs;
  HANDLE h;
  int status = -1;

  if ((path == NULL) || (*path == '\0'))
    return -1;

  attrs = GetFileAttributesA(path);
  if ((attrs != INVALID_FILE_ATTRIBUTES) && (attrs & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)))
    return -1;

  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA("D:P(A;;FA;;;SY)(A;;FA;;;BA)", SDDL_REVISION_1, &sd,
                                                            NULL))
    return -1;
  if (!GetSecurityDescriptorDacl(sd, &present, &dacl, &defaulted) || !present || (dacl == NULL)) {
    LocalFree(sd);
    return -1;
  }

  ZeroMemory(&sa, sizeof(sa));
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;
  sa.bInheritHandle = FALSE;

  h = CreateFileA(path, GENERIC_WRITE | WRITE_DAC | FILE_READ_ATTRIBUTES, FILE_SHARE_READ, &sa, CREATE_ALWAYS,
                  FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (h != INVALID_HANDLE_VALUE) {
    if (GetFileInformationByHandle(h, &info) && !(info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
        (SetSecurityInfo(h, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, NULL,
                         NULL, dacl, NULL) == ERROR_SUCCESS))
      status = 0;
    CloseHandle(h);
  }

  LocalFree(sd);
  return status;
}

/* END-CODE */
