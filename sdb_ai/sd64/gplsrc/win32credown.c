/* WIN32CREDOWN.C
 * A session's half of cred-own: hand the person's own-password request to the SD service.
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
 * 21 Nov 26 Windows port - written.  RELEASE_1.1 379 (Linux sd-elevate cred-own); win32credown.h has the wire and the reasons.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * windows.h and NO SD header, as win32auditpipe.c: the two cannot share a translation unit.  sd.exe links this (gpl.src;
 * op_kernel.c's K_CRED_OWN calls it); gplbld/test-credown-units.py also builds it natively beside the service's half.
 *
 * WHAT THE CLIENT DOES NOT TRUST, as win32auditpipe.c: the pipe's OWNER must be LocalSystem before one byte is written (the
 * request carries the person's stored keys, and the name is open to anybody while the service is down), and the server is given
 * SECURITY_IDENTIFICATION only, so it can learn who the session is and cannot act as it.  The request is wiped from this
 * process's own buffer before returning.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <aclapi.h>
#include <stdio.h>
#include <string.h>

#include "win32credown.h"

/* Read the answer, write the request, read the owner.  NOT GENERIC_WRITE (its FILE_APPEND_DATA is FILE_CREATE_PIPE_INSTANCE). */
#define CREDOWN_PIPE_ACCESS (FILE_READ_DATA | FILE_WRITE_DATA | READ_CONTROL | SYNCHRONIZE)

#define CREDOWN_BUSY_TRIES 10   /* the service serves one request at a time */
#define CREDOWN_BUSY_WAIT_MS 500
#define CREDOWN_WRITE_MS 3000
#define CREDOWN_ANSWER_MS 20000 /* the service may ask a domain controller for the caller's name */

static BOOL credown_owner_is_system(HANDLE h) {
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  BOOL is_system = FALSE;

  if (GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, &sd) == ERROR_SUCCESS)
    is_system = (owner != NULL) && IsWellKnownSid(owner, WinLocalSystemSid);
  if (sd != NULL)
    LocalFree(sd);
  return is_system;
}

/* One overlapped read or write, given ms to finish; cancelled and FALSE if it does not. */
static BOOL credown_io(HANDLE h, HANDLE ev, BOOL writing, void* buf, DWORD len, DWORD* done, DWORD ms) {
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

static void credown_say(char* answer, int alen, const char* text) {
  if ((answer != NULL) && (alen > 0))
    snprintf(answer, (size_t)alen, "%s", text);
}

int win32_credown_ask_to(const char* pipe_name, int need_system_owner, const char* request, char* answer, int alen) {
  HANDLE h = INVALID_HANDLE_VALUE;
  HANDLE ev;
  DWORD done = 0;
  DWORD got = 0;
  DWORD len;
  char buf[CREDOWN_ANSWER_MAX];
  char* nl;
  int tries;
  BOOL ok;

  credown_say(answer, alen, "");
  if ((pipe_name == NULL) || (request == NULL) || ((len = (DWORD)strlen(request)) == 0) || (len > CREDOWN_REQUEST_MAX)) {
    credown_say(answer, alen, "the request is empty or too long");
    return -1;
  }

  for (tries = 0; tries < CREDOWN_BUSY_TRIES; tries++) {
    h = CreateFileA(pipe_name, CREDOWN_PIPE_ACCESS, 0, NULL, OPEN_EXISTING,
                    FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL);
    if (h != INVALID_HANDLE_VALUE)
      break;
    if (GetLastError() != ERROR_PIPE_BUSY) {
      credown_say(answer, alen, "the SD service is not running, or this account may not ask it (it is not an SD user)");
      return -1;
    }
    (void)WaitNamedPipeA(pipe_name, CREDOWN_BUSY_WAIT_MS);
  }
  if (h == INVALID_HANDLE_VALUE) {
    credown_say(answer, alen, "the SD service is busy; try again in a moment");
    return -1;
  }

  if (need_system_owner && !credown_owner_is_system(h)) {
    CloseHandle(h); /* somebody else's pipe under the service's name: not one byte to it */
    credown_say(answer, alen, "the pipe under the SD service's name is not the service's; nothing was sent");
    return -1;
  }

  if ((ev = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL) {
    CloseHandle(h);
    credown_say(answer, alen, "no event could be made");
    return -1;
  }

  ok = credown_io(h, ev, TRUE, (void*)request, len, &done, CREDOWN_WRITE_MS) && (done == len);
  if (ok) {
    /* The answer is one line; the service closes after it. */
    while (got < sizeof(buf) - 1) {
      if (!credown_io(h, ev, FALSE, buf + got, (DWORD)(sizeof(buf) - 1 - got), &done, CREDOWN_ANSWER_MS) || (done == 0))
        break;
      got += done;
      buf[got] = '\0';
      if (strchr(buf, '\n') != NULL)
        break;
    }
  }
  CloseHandle(ev);
  CloseHandle(h);

  buf[got] = '\0';
  if ((nl = strpbrk(buf, "\r\n")) != NULL)
    *nl = '\0';
  if (!ok || (buf[0] == '\0')) {
    credown_say(answer, alen, "the SD service gave no answer");
    return -1;
  }
  credown_say(answer, alen, buf);
  SecureZeroMemory(buf, sizeof(buf));
  return 0;
}

int win32_credown_ask(const char* request, char* answer, int alen) {
  return win32_credown_ask_to(SD_CREDOWN_PIPE, 1, request, answer, alen);
}

/* END-CODE */
