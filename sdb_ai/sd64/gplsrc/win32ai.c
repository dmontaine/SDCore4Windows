/* WIN32AI.C
 * The named-pipe transport of the in-SD AI helper (op_ai.c), the Windows half.
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
 * 13 Nov 26 Windows port - written for RELEASE_1.1 246 (Linux's AI helper,
 *           S.69 step 2, design .claude/design-ai-helper-20261113.md 3.2, 3.6).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Linux's op_ai.c talks to its helper on the Unix socket /run/sd-ai/sock.  The
 * Windows helper (gplbld/sd-ai, Python, the service sd-ai running as the
 * virtual account NT SERVICE\sd-ai) listens on the pipe \\.\pipe\sd-ai.  The
 * protocol is Linux's byte for byte: one JSON line each way.  This file is the
 * part that differs, and only that part.
 *
 * WHAT IT ADDS THAT LINUX DOES NOT NEED:
 *   - THE CLIENT OPENS AT IDENTIFICATION LEVEL (SECURITY_SQOS_PRESENT |
 *     SECURITY_IDENTIFICATION).  The helper asks the pipe who called
 *     (ImpersonateNamedPipeClient, Linux's SO_PEERCRED) and can read the
 *     caller's token but never act as the caller.
 *   - THE ACCESS ASKED FOR IS NARROW (AI_ACCESS): read, write, the attributes
 *     and the owner, NOT GENERIC_WRITE, whose FILE_APPEND_DATA is
 *     FILE_CREATE_PIPE_INSTANCE on a pipe.  The helper's pipe grants sdusers
 *     and Administrators exactly AI_ACCESS, so asking for more is refused.
 *   - THE SERVER IS CHECKED BEFORE A BYTE IS SENT: the pipe object's owner must
 *     be NT SERVICE\sd-ai.  While the service is stopped any user may create
 *     \\.\pipe\sd-ai (the pipe namespace is global, unlike Linux's root-owned
 *     /run/sd-ai), and every prompt sent to it would be theirs to read.  The
 *     helper sets its own account as the owner when it makes the pipe.
 *   - THE HANDLE IS PUT IN NON-BLOCKING MODE (PIPE_NOWAIT) and kept OUT of the
 *     MSYS2 descriptor table: there select() reports a pipe permanently ready
 *     (win32peer.h).  Readiness is PeekNamedPipe's answer, never select()'s.
 *
 * windows.h and NO SD header, the rule every win32*.c file follows.
 *
 * END-DESCRIPTION
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <aclapi.h>
#include <string.h>
#include <strings.h>

#include "win32ai.h"

#define AI_SLOTS 4
#define AI_CHUNK 4096
#define AI_SERVICE_ACCOUNT "NT SERVICE\\sd-ai"
#define AI_PIPE_PREFIX "\\\\.\\pipe\\"

/* FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE = 0x00120183.
   FILE_WRITE_ATTRIBUTES is what SetNamedPipeHandleState needs; READ_CONTROL is what the owner check needs.  The helper's DACL
   grants this mask and no more (gplbld/sd-ai, PIPE_CLIENT_MASK), and the two must stay equal. */
#define AI_ACCESS (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)

static HANDLE slots[AI_SLOTS] = {NULL, NULL, NULL, NULL};

static HANDLE slot_handle(int slot) {
  if (slot < 0 || slot >= AI_SLOTS)
    return NULL;
  return slots[slot];
}

/* Is the pipe's owner the service's own account?  Every doubt is no: an account that cannot be looked up (the service is not
   installed), an owner that cannot be read, or any other owner. */
static int owned_by_service(HANDLE h) {
  BYTE want[SECURITY_MAX_SID_SIZE];
  DWORD wlen = sizeof want;
  char dom[256];
  DWORD dlen = sizeof dom;
  SID_NAME_USE use;
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  int ok;

  if (!LookupAccountNameA(NULL, AI_SERVICE_ACCOUNT, (PSID)want, &wlen, dom, &dlen, &use))
    return 0;
  if (GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, &sd) != ERROR_SUCCESS)
    return 0;
  ok = (owner != NULL) && IsValidSid(owner) && EqualSid(owner, (PSID)want);
  if (sd != NULL)
    LocalFree(sd);
  return ok;
}

int win32_ai_open(const char* pipe, int check_owner, int wait_ms) {
  HANDLE h = INVALID_HANDLE_VALUE;
  DWORD mode;
  int tries;
  int slot;

  if (pipe == NULL || strncasecmp(pipe, AI_PIPE_PREFIX, strlen(AI_PIPE_PREFIX)) != 0)
    return WIN32_AI_NONE;
  for (slot = 0; slot < AI_SLOTS; slot++) {
    if (slots[slot] == NULL)
      break;
  }
  if (slot >= AI_SLOTS)
    return WIN32_AI_NONE;

  for (tries = 0; tries < 2; tries++) {
    h = CreateFileA(pipe, AI_ACCESS, 0, NULL, OPEN_EXISTING, SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL);
    if (h != INVALID_HANDLE_VALUE)
      break;
    if (GetLastError() != ERROR_PIPE_BUSY || tries > 0)
      return WIN32_AI_NONE;
    if (!WaitNamedPipeA(pipe, (DWORD)((wait_ms > 0) ? wait_ms : 1)))
      return WIN32_AI_NONE;
  }
  if (h == INVALID_HANDLE_VALUE)
    return WIN32_AI_NONE;

  if (GetFileType(h) != FILE_TYPE_PIPE) {
    CloseHandle(h);
    return WIN32_AI_NONE;
  }
  /* BEFORE ANYTHING IS WRITTEN: is this the service's pipe? */
  if (check_owner && !owned_by_service(h)) {
    CloseHandle(h);
    return WIN32_AI_NOTOURS;
  }
  mode = PIPE_READMODE_BYTE | PIPE_NOWAIT;
  if (!SetNamedPipeHandleState(h, &mode, NULL, NULL)) {
    CloseHandle(h);
    return WIN32_AI_NONE;
  }
  slots[slot] = h;
  return slot;
}

int win32_ai_write(int slot, const char* buf, int len, int wait_ms) {
  HANDLE h = slot_handle(slot);
  int done = 0;
  int idle = 0;
  DWORD want;
  DWORD n;

  if (h == NULL || len < 0)
    return 0;
  while (done < len) {
    want = (DWORD)(((len - done) > AI_CHUNK) ? AI_CHUNK : (len - done));
    n = 0;
    if (!WriteFile(h, buf + done, want, &n, NULL))
      return 0;
    if (n > 0) {
      done += (int)n;
      idle = 0;
      continue;
    }
    if (idle >= wait_ms)
      return 0;
    Sleep(10);
    idle += 10;
  }
  return 1;
}

int win32_ai_avail(int slot) {
  HANDLE h = slot_handle(slot);
  DWORD avail = 0;
  DWORD e;

  if (h == NULL)
    return -2;
  if (!PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL)) {
    e = GetLastError();
    if (e == ERROR_BROKEN_PIPE || e == ERROR_PIPE_NOT_CONNECTED || e == ERROR_NO_DATA)
      return -1;
    return -2;
  }
  return (avail > 0x7fffffffUL) ? 0x7fffffff : (int)avail;
}

int win32_ai_read(int slot, char* buf, int len) {
  HANDLE h = slot_handle(slot);
  DWORD n = 0;
  DWORD e;

  if (h == NULL || len <= 0)
    return -1;
  if (!ReadFile(h, buf, (DWORD)len, &n, NULL)) {
    e = GetLastError();
    if (e == ERROR_BROKEN_PIPE || e == ERROR_PIPE_NOT_CONNECTED || e == ERROR_NO_DATA)
      return 0;
    return -1;
  }
  return (int)n;
}

void win32_ai_close(int slot) {
  HANDLE h = slot_handle(slot);

  if (h != NULL) {
    CloseHandle(h);
    slots[slot] = NULL;
  }
}

/* END-CODE */
