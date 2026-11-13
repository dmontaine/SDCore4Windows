/* sdaudit.c - the audit trail's writer, in the SD service
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
 * 13 Nov 26 Windows port - written.  RELEASE_1.1 247, the Windows form of Linux W.11 F4 (sdlnxd.c's audit writer,
 *           options C1 and C2), and RELEASE_1.1 182, LOCK.TRACER's file (Linux 7f7a4fd4).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY.  Sessions run as the person using them, and until now each appended to the audit trail itself, so the file
 * had to take an append from every member of sdusers - and a member could add a line that named any user, user
 * number or pid.  Now a session hands the record to this service (win32auditpipe.c) over the named pipe
 * SD_AUDIT_PIPE, and this writes it with the user and the pid the KERNEL gives for the session: the token of the
 * thread that opened the pipe (ImpersonateNamedPipeClient, at identification level, then RevertToSelf) and
 * GetNamedPipeClientProcessId().  The text is the session's and goes after those fields; the SD user number (uid=)
 * is the one field still taken from the session, as on Linux.
 *
 * Everything that arrives is input from any member of sdusers, in a LocalSystem process: the buffers are fixed, a
 * message is read whole or dropped, the format is never the sender's, the path comes from the machine's sd.conf
 * and never from the message, and a bad message is dropped and counted - it never ends the service.
 *
 * THE PIPE.  Owned by this process's user (LocalSystem, set explicitly: LocalSystem's default owner is
 * Administrators, and a session checks for SYSTEM).  DACL: SYSTEM full control; Administrators and the grant
 * accounts read and write data, read the owner and attributes, and NOT FILE_CREATE_PIPE_INSTANCE, so a member
 * cannot add an instance of the name while this serves it.  The first instance is made with
 * FILE_FLAG_FIRST_PIPE_INSTANCE: if somebody made the name while the service was down, this refuses to serve it
 * (and says so) rather than share it.  Remote clients are refused.  AUDIT_INSTANCES threads each serve one
 * instance; a session that finds all of them busy tries four times and then writes the record itself.
 *
 * THE TRAIL.  Linux's option C2: one user (by SID) may add AUDIT_RATE_MAX records in AUDIT_RATE_WINDOW seconds,
 * the rest are dropped and the end of the window writes one line saying how many; the trail is rotated by size as
 * this writes, with win32audit.c's rotation (the same one "sd -start" uses), which copies the DACL to the new file.
 * A missing trail is made with secure-audit.ps1's DACL (SYSTEM and Administrators full control, the grant accounts
 * append only), never the data tree's inherited one.  A link in place of the trail is not written through.
 *
 * NOT ERRLOG_SEM.  That is SD's semaphore and this is not an SD process.  It is not needed: this writes under its
 * own critical section, and a session appending for itself (option C1) holds the file open without
 * FILE_SHARE_DELETE, so a rotation that meets it fails and is tried again a minute later - the trail stays whole.
 *
 * LOCK.TRACER.  A line is appended to <sysdir>\locktrace only if that file is there (LOCK.TRACER ON makes it); this
 * never makes it.  The line is the session's, as on Linux, where every session appends to a 0620 file: it must be
 * one line ending in a newline, and nothing is stamped.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <userenv.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>

#include "../win32audit.h"
#include "../win32auditpipe.h"
#include "sdaudit.h"

#define AUDIT_INSTANCES 4
#define AUDIT_GRANT_MAX 4
#define AUDIT_MSG_MAX 1900      /* bytes of text kept, Linux's number */
#define AUDIT_RATE_SLOTS 128    /* users whose current window is remembered */
#define AUDIT_SID_TEXT 192
#define AUDIT_NAME_TEXT 260     /* DOMAIN\name: two 127-byte names, a separator, or a SID's text */
#define AUDIT_LINE_MAX (AUDIT_MSG_MAX + 512)
#define AUDIT_READ_MS 2000
#define AUDIT_ANSWER_MS 500
#define AUDIT_CLOSE_MS 1000
#define AUDIT_STOP_MS 5000

/* What a member may do to the pipe.  Not FILE_CREATE_PIPE_INSTANCE (FILE_APPEND_DATA on a pipe), not WRITE_DAC,
   not WRITE_OWNER, not FILE_WRITE_ATTRIBUTES.                                                                   */
#define AUDIT_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)

/* What a member may do to a trail this makes: secure-audit.ps1's (AD,RA,S). */
#define AUDIT_TRAIL_GRANT (FILE_APPEND_DATA | FILE_READ_ATTRIBUTES | SYNCHRONIZE)

typedef struct {
  char sid[AUDIT_SID_TEXT];   /* the user's SID as text; "" = the slot is free */
  char user[AUDIT_NAME_TEXT]; /* DOMAIN\name, for the line that reports a flood */
  DWORD pid;                  /* the last sender's */
  ULONGLONG start;            /* audit_clock() when this window began */
  unsigned long count;        /* records taken in this window */
  unsigned long dropped;
} AUDIT_RATE;

static CRITICAL_SECTION audit_cs;
static BOOL audit_running = FALSE;
static HANDLE audit_stop_event = NULL;
static HANDLE audit_threads[AUDIT_INSTANCES];
static HANDLE audit_pipes[AUDIT_INSTANCES];
static int audit_nthreads = 0;
static char audit_pipe_name[MAX_PATH];
static char audit_dir[MAX_PATH];
static PSECURITY_DESCRIPTOR audit_pipe_sd = NULL;
static PACL audit_pipe_acl = NULL;
static PSECURITY_DESCRIPTOR audit_trail_sd = NULL;
static PACL audit_trail_acl = NULL;
static BYTE audit_own_sid[SECURITY_MAX_SID_SIZE];
static BYTE audit_system_sid[SECURITY_MAX_SID_SIZE];
static BYTE audit_admins_sid[SECURITY_MAX_SID_SIZE];
static BYTE audit_grant_sids[AUDIT_GRANT_MAX][SECURITY_MAX_SID_SIZE];
static int audit_ngrant = 0;
static sdaudit_log_fn audit_log = NULL;

static AUDIT_RATE audit_rate[AUDIT_RATE_SLOTS];
static ULONGLONG audit_rotate_after = 0;

static unsigned long audit_taken = 0;         /* records written */
static unsigned long audit_dropped = 0;       /* messages refused: not ours, no identity, malformed */
static unsigned long audit_foreign = 0;       /* records from a session of another tree (answered N) */
static unsigned long audit_unwritten = 0;     /* records accepted and not appended */
static unsigned long audit_limited = 0;       /* records dropped by the per-user bound */
static unsigned long audit_rotate_failed = 0; /* rotations that were due and could not be done */
static unsigned long audit_traced = 0;        /* LOCK.TRACER lines appended */

static void audit_nolog(const char* fmt, ...) {
  (void)fmt;
}

/* Seconds on a clock the wall clock cannot set back, plus one so that 0 can mean "none". */
static ULONGLONG audit_clock(void) {
  return GetTickCount64() / 1000 + 1;
}

/* ======================================================================
   The system directory                                                    */

int sdaudit_sysdir(char* out, int outsz) {
  char conf[MAX_PATH];
  char rec[512];
  char section[33] = "";
  DWORD n = sizeof(conf);
  FILE* f;
  char* p;
  int found = 0;

  if ((out == NULL) || (outsz <= 0))
    return -1;
  *out = '\0';
  if (!GetAllUsersProfileDirectoryA(conf, &n))
    return -1;
  if (strlen(conf) + strlen("\\SD\\sd.conf") + 1 > sizeof(conf))
    return -1;
  strcat(conf, "\\SD\\sd.conf");

  if ((f = fopen(conf, "r")) == NULL)
    return -1;
  /* config.c config_sysdir_scan(), the session's reading: the LAST SDSYS= of the [sd] section. */
  while (fgets(rec, sizeof(rec), f) != NULL) {
    rec[strcspn(rec, "\r\n")] = '\0';
    if ((rec[0] == '#') || (rec[0] == '\0'))
      continue;
    if (rec[0] == '[') {
      if ((p = strchr(rec, ']')) != NULL)
        *p = '\0';
      snprintf(section, sizeof(section), "%.32s", rec + 1);
      continue;
    }
    if ((_stricmp(section, "SD") == 0) && (strncmp(rec, "SDSYS=", 6) == 0) && (rec[6] != '\0') &&
        ((int)strlen(rec + 6) < outsz)) {
      strcpy(out, rec + 6);
      found = 1;
    }
  }
  fclose(f);
  return found ? 0 : -1;
}

/* A path as a comparison wants it: back slashes, no trailing separator or blank. */
static void audit_dir_key(const char* in, char* out, size_t outsz) {
  size_t n;
  char* p;

  snprintf(out, outsz, "%s", in);
  for (p = out; *p != '\0'; p++) {
    if (*p == '/')
      *p = '\\';
  }
  n = strlen(out);
  while ((n > 3) && ((out[n - 1] == '\\') || (out[n - 1] == ' ')))
    out[--n] = '\0';
}

/* Is the system directory a session names the one this service writes under?  The answer only decides whether
   this writes the record or the session does; the path written is always this service's own.                  */
static BOOL audit_same_dir(const char* claimed) {
  char a[MAX_PATH];
  char b[MAX_PATH];

  audit_dir_key(claimed, a, sizeof(a));
  audit_dir_key(audit_dir, b, sizeof(b));
  return _stricmp(a, b) == 0;
}

/* ======================================================================
   Who sent it                                                             */

/* DOMAIN\name for a SID, safe to put on a line; a small cache so that a burst does not ask for every record. */
static void audit_user_name(PSID sid, const char* sidtext, char* out, size_t outsz) {
  static struct {
    char sid[AUDIT_SID_TEXT];
    ULONGLONG at;
    char name[AUDIT_NAME_TEXT];
  } cache[8];
  static int next = 0;
  ULONGLONG now = audit_clock();
  char name[128];
  char dom[128];
  DWORD nl = sizeof(name);
  DWORD dl = sizeof(dom);
  SID_NAME_USE use;
  char* p;
  int i;

  EnterCriticalSection(&audit_cs);
  for (i = 0; i < 8; i++) {
    if ((cache[i].at != 0) && (strcmp(cache[i].sid, sidtext) == 0) && (now - cache[i].at < 60)) {
      snprintf(out, outsz, "%s", cache[i].name);
      LeaveCriticalSection(&audit_cs);
      return;
    }
  }
  LeaveCriticalSection(&audit_cs);

  if (LookupAccountSidA(NULL, sid, name, &nl, dom, &dl, &use))
    snprintf(out, outsz, "%s%s%s", dom, (dom[0] != '\0') ? "\\" : "", name);
  else
    snprintf(out, outsz, "%s", sidtext);
  /* One token on the line, as Linux's: the trail's readers split on blanks. */
  for (p = out; *p != '\0'; p++) {
    if (!(isalnum((unsigned char)*p) || (*p == '.') || (*p == '_') || (*p == '-') || (*p == '\\') || (*p == '$')))
      *p = '?';
  }

  EnterCriticalSection(&audit_cs);
  snprintf(cache[next].sid, sizeof(cache[next].sid), "%s", sidtext);
  snprintf(cache[next].name, sizeof(cache[next].name), "%s", out);
  cache[next].at = now;
  next = (next + 1) % 8;
  LeaveCriticalSection(&audit_cs);
}

/* The user of the session on the other end, from the kernel and never from the message.  The token is the one the
   session's thread opened the pipe with, captured at identification level; the process's own token is the second
   choice.  FALSE when neither can be had: the record is then not written here.                                  */
static BOOL audit_client_identity(HANDLE h, DWORD pid, char* sidtext, size_t sidsz, char* user, size_t usersz) {
  HANDLE tok = NULL;
  HANDLE proc;
  BYTE buf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  DWORD n = 0;
  char* text = NULL;

  if (ImpersonateNamedPipeClient(h)) {
    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok))
      tok = NULL;
    if (!RevertToSelf()) {
      /* Never go on as somebody else in a LocalSystem process. */
      audit_log("audit writer: RevertToSelf failed (error %lu) - the service ends", (unsigned long)GetLastError());
      ExitProcess(1);
    }
  }
  if ((tok == NULL) && (pid != 0)) {
    if ((proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) != NULL) {
      if (!OpenProcessToken(proc, TOKEN_QUERY, &tok))
        tok = NULL;
      CloseHandle(proc);
    }
  }
  if (tok == NULL)
    return FALSE;

  if (!GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &n) ||
      !ConvertSidToStringSidA(((TOKEN_USER*)buf)->User.Sid, &text)) {
    CloseHandle(tok);
    return FALSE;
  }
  snprintf(sidtext, sidsz, "%s", text);
  LocalFree(text);
  audit_user_name(((TOKEN_USER*)buf)->User.Sid, sidtext, user, usersz);
  CloseHandle(tok);
  return TRUE;
}

/* ======================================================================
   Writing                                                                 */

/* Open a file of the system directory to append.  A link in its place is not written through.  create_missing:
   make a missing one with the trail's DACL (the audit trail); otherwise a missing file stays missing (locktrace). */
static HANDLE audit_open_append(const char* path, BOOL create_missing) {
  SECURITY_ATTRIBUTES sa;
  BY_HANDLE_FILE_INFORMATION info;
  HANDLE h;

  h = CreateFileA(path, FILE_APPEND_DATA | FILE_READ_ATTRIBUTES | SYNCHRONIZE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                  NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if ((h == INVALID_HANDLE_VALUE) && create_missing && (GetLastError() == ERROR_FILE_NOT_FOUND)) {
    ZeroMemory(&sa, sizeof(sa));
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = audit_trail_sd;
    sa.bInheritHandle = FALSE;
    h = CreateFileA(path, FILE_APPEND_DATA | FILE_READ_ATTRIBUTES | SYNCHRONIZE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    &sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
  }
  if (h == INVALID_HANDLE_VALUE)
    return h;
  if (!GetFileInformationByHandle(h, &info) ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
    CloseHandle(h);
    return INVALID_HANDLE_VALUE;
  }
  return h;
}

static BOOL audit_append(const char* path, BOOL create_missing, const char* data, DWORD len) {
  HANDLE h;
  DWORD written = 0;
  BOOL ok;

  if ((h = audit_open_append(path, create_missing)) == INVALID_HANDLE_VALUE)
    return FALSE;
  ok = WriteFile(h, data, len, &written, NULL) && (written == len);
  CloseHandle(h);
  return ok;
}

/* Rotate the trail first when it has reached AUDIT_ROTATE_BYTES (C2), then append one finished line.  Called with
   audit_cs held.  A rotation that fails is counted and not tried again for a minute: the trail stays whole and
   keeps growing, as at "sd -start".                                                                             */
static BOOL audit_emit_line(const char* line, int len) {
  char path[MAX_PATH];
  char rotated[MAX_PATH + 32];
  WIN32_FILE_ATTRIBUTE_DATA fa;
  ULARGE_INTEGER size;
  SYSTEMTIME st;
  ULONGLONG now = audit_clock();

  if (snprintf(path, sizeof(path), "%s\\audit", audit_dir) >= (int)sizeof(path)) {
    audit_unwritten++;
    return FALSE;
  }
  if ((now >= audit_rotate_after) && GetFileAttributesExA(path, GetFileExInfoStandard, &fa) &&
      !(fa.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
    size.LowPart = fa.nFileSizeLow;
    size.HighPart = fa.nFileSizeHigh;
    if (size.QuadPart >= (ULONGLONG)AUDIT_ROTATE_BYTES) {
      GetLocalTime(&st);
      snprintf(rotated, sizeof(rotated), "%s.%04d%02d%02d-%02d%02d%02d", path, st.wYear, st.wMonth, st.wDay,
               st.wHour, st.wMinute, st.wSecond);
      if (win32_audit_rotate(path, rotated) != 0) {
        audit_rotate_failed++;
        audit_rotate_after = now + 60;
      }
    }
  }
  if (!audit_append(path, TRUE, line, (DWORD)len)) {
    audit_unwritten++;
    return FALSE;
  }
  audit_taken++;
  return TRUE;
}

/* One line of the trail: the time, the stamp (user, the claimed SD user number, pid), then the text as an ARGUMENT,
   never as the format.  0 when it does not fit.                                                                   */
static int audit_format_line(char* line, size_t linesz, const char* user, const char* who, DWORD pid, const char* msg) {
  SYSTEMTIME st;
  int len;

  GetLocalTime(&st);
  len = snprintf(line, linesz, "%04d-%02d-%02d %02d:%02d:%02d user=%s uid=%s pid=%lu %s\r\n", st.wYear, st.wMonth,
                 st.wDay, st.wHour, st.wMinute, st.wSecond, user, who, (unsigned long)pid, msg);
  if ((len <= 0) || (len >= (int)linesz))
    return 0;
  return len;
}

/* ======================================================================
   The bound (Linux's option C2)                                           */

/* ONE line, in the trail's own shape, saying that a user sent more than the bound allows in a window. */
static void audit_rate_note(const AUDIT_RATE* s) {
  char msg[128];
  char line[512];
  int len;

  snprintf(msg, sizeof(msg), "audit rate limit dropped=%lu taken=%lu limit=%d window=%d", s->dropped, s->count,
           AUDIT_RATE_MAX, AUDIT_RATE_WINDOW);
  len = audit_format_line(line, sizeof(line), s->user, "?", s->pid, msg);
  if (len > 0)
    (void)audit_emit_line(line, len);
  else
    audit_unwritten++;
}

static void audit_rate_close(AUDIT_RATE* s) {
  if (s->dropped > 0)
    audit_rate_note(s);
  s->dropped = 0;
}

/* May this user add a record now?  Called with audit_cs held. */
static BOOL audit_rate_take(const char* sid, const char* user, DWORD pid) {
  ULONGLONG now = audit_clock();
  AUDIT_RATE* s = NULL;
  AUDIT_RATE* oldest = &audit_rate[0];
  int i;

  for (i = 0; i < AUDIT_RATE_SLOTS; i++) {
    if ((audit_rate[i].sid[0] != '\0') && (strcmp(audit_rate[i].sid, sid) == 0)) {
      s = &audit_rate[i];
      break;
    }
  }
  if (s == NULL) {
    for (i = 0; i < AUDIT_RATE_SLOTS; i++) {
      if (audit_rate[i].sid[0] == '\0') {
        s = &audit_rate[i];
        break;
      }
      if (audit_rate[i].start < oldest->start)
        oldest = &audit_rate[i];
    }
    if (s == NULL) { /* the table is full: the oldest window goes, with its line */
      audit_rate_close(oldest);
      s = oldest;
    }
    memset(s, 0, sizeof(*s));
    snprintf(s->sid, sizeof(s->sid), "%s", sid);
    s->start = now;
  } else if (now - s->start >= AUDIT_RATE_WINDOW) {
    audit_rate_close(s);
    s->start = now;
    s->count = 0;
  }
  snprintf(s->user, sizeof(s->user), "%s", user);
  s->pid = pid;
  if (s->count >= AUDIT_RATE_MAX) {
    s->dropped++;
    audit_limited++;
    return FALSE;
  }
  s->count++;
  return TRUE;
}

/* The lines for the windows that are over (all of them on the way out), and the slots they free. */
static void audit_rate_sweep(BOOL all) {
  ULONGLONG now = audit_clock();
  int i;

  EnterCriticalSection(&audit_cs);
  for (i = 0; i < AUDIT_RATE_SLOTS; i++) {
    if (audit_rate[i].sid[0] == '\0')
      continue;
    if (all || (now - audit_rate[i].start >= AUDIT_RATE_WINDOW)) {
      audit_rate_close(&audit_rate[i]);
      if (now - audit_rate[i].start >= AUDIT_RATE_WINDOW)
        audit_rate[i].sid[0] = '\0';
    }
  }
  LeaveCriticalSection(&audit_cs);
}

/* ======================================================================
   One message                                                             */

/* The text kept to one line: a control byte, DEL or an SD mark becomes '?' (the session did this too; a message
   need not have come from SD).                                                                                  */
static void audit_clean(char* msg) {
  char* p;

  for (p = msg; *p != '\0'; p++) {
    if (((unsigned char)*p < 32) || ((unsigned char)*p == 127) || ((unsigned char)*p >= 248))
      *p = '?';
  }
}

/* SDAUDIT1 <who>\t<sysdir>\t<text> */
static char audit_take_record(HANDLE h, char* p, DWORD pid) {
  char who[16];
  char sidtext[AUDIT_SID_TEXT];
  char user[AUDIT_NAME_TEXT];
  char line[AUDIT_LINE_MAX];
  char* dir;
  char* msg;
  char* tab;
  int len;
  int i;
  BOOL ok;

  if ((p[0] == '?') && (p[1] == '\t')) {
    strcpy(who, "?");
    dir = p + 2;
  } else {
    for (i = 0; (i < 9) && isdigit((unsigned char)p[i]); i++)
      who[i] = p[i];
    if ((i == 0) || (p[i] != '\t'))
      return AUDIT_ANSWER_FAILED;
    who[i] = '\0';
    dir = p + i + 1;
  }
  if ((tab = strchr(dir, '\t')) == NULL)
    return AUDIT_ANSWER_FAILED;
  *tab = '\0';
  msg = tab + 1;

  if (!audit_same_dir(dir)) {
    EnterCriticalSection(&audit_cs);
    audit_foreign++;
    LeaveCriticalSection(&audit_cs);
    return AUDIT_ANSWER_NOT_MINE; /* a session of another tree: it writes its own trail */
  }
  if (*msg == '\0')
    return AUDIT_ANSWER_FAILED;
  audit_clean(msg);
  if (strlen(msg) > AUDIT_MSG_MAX)
    msg[AUDIT_MSG_MAX] = '\0';

  if (!audit_client_identity(h, pid, sidtext, sizeof(sidtext), user, sizeof(user)))
    return AUDIT_ANSWER_FAILED;

  EnterCriticalSection(&audit_cs);
  if (!audit_rate_take(sidtext, user, pid)) {
    LeaveCriticalSection(&audit_cs);
    return AUDIT_ANSWER_TAKEN; /* dropped by the bound: counted, and the end of the window says how many */
  }
  len = audit_format_line(line, sizeof(line), user, who, pid, msg);
  ok = (len > 0) && audit_emit_line(line, len);
  if (len == 0)
    audit_unwritten++;
  LeaveCriticalSection(&audit_cs);
  return ok ? AUDIT_ANSWER_TAKEN : AUDIT_ANSWER_FAILED;
}

/* SDLOCKT1 <sysdir>\t<line> - n is the length of what follows the magic */
static char audit_take_locktrace(char* p, DWORD n) {
  char lpath[MAX_PATH];
  char* tab;
  char* line;
  DWORD len;
  DWORD i;
  BOOL ok;

  if ((tab = memchr(p, '\t', n)) == NULL)
    return AUDIT_ANSWER_FAILED;
  *tab = '\0';
  line = tab + 1;
  len = n - (DWORD)(line - p);
  if (!audit_same_dir(p))
    return AUDIT_ANSWER_NOT_MINE;
  /* One line: it ends in a newline and holds no other line break and no nul. */
  if ((len < 2) || (line[len - 1] != '\n'))
    return AUDIT_ANSWER_FAILED;
  for (i = 0; i + 1 < len; i++) {
    if ((line[i] == '\n') || (line[i] == '\r') || (line[i] == '\0'))
      return AUDIT_ANSWER_FAILED;
  }
  if (snprintf(lpath, sizeof(lpath), "%s\\locktrace", audit_dir) >= (int)sizeof(lpath))
    return AUDIT_ANSWER_FAILED;

  EnterCriticalSection(&audit_cs);
  ok = audit_append(lpath, FALSE, line, len);
  if (ok)
    audit_traced++;
  LeaveCriticalSection(&audit_cs);
  return ok ? AUDIT_ANSWER_TAKEN : AUDIT_ANSWER_FAILED;
}

/* One overlapped read or write on an instance, given ms to finish; cancelled and FALSE if it does not. */
static BOOL audit_io(HANDLE h, HANDLE ev, BOOL writing, void* buf, DWORD len, DWORD* done, DWORD ms) {
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

static void audit_serve_one(HANDLE h, HANDLE ev) {
  char buf[AUDIT_PIPE_MAX + 1];
  DWORD n = 0;
  DWORD pid = 0;
  size_t magic;
  char answer = AUDIT_ANSWER_FAILED;

  /* A message is read whole or not at all: one larger than AUDIT_PIPE_MAX fails here (ERROR_MORE_DATA). */
  if (!audit_io(h, ev, FALSE, buf, AUDIT_PIPE_MAX, &n, AUDIT_READ_MS) || (n == 0)) {
    EnterCriticalSection(&audit_cs);
    audit_dropped++;
    LeaveCriticalSection(&audit_cs);
    return;
  }
  buf[n] = '\0';
  if (!GetNamedPipeClientProcessId(h, &pid))
    pid = 0;

  magic = strlen(AUDIT_MAGIC);
  if ((n > magic) && (memcmp(buf, AUDIT_MAGIC, magic) == 0) && (strlen(buf) == n)) {
    answer = audit_take_record(h, buf + magic, pid);
  } else if ((n > strlen(LOCKTRACE_MAGIC)) && (memcmp(buf, LOCKTRACE_MAGIC, strlen(LOCKTRACE_MAGIC)) == 0)) {
    answer = audit_take_locktrace(buf + strlen(LOCKTRACE_MAGIC), n - (DWORD)strlen(LOCKTRACE_MAGIC));
  }
  if (answer == AUDIT_ANSWER_FAILED) {
    EnterCriticalSection(&audit_cs);
    audit_dropped++;
    LeaveCriticalSection(&audit_cs);
  }

  (void)audit_io(h, ev, TRUE, &answer, 1, &n, AUDIT_ANSWER_MS); /* fails harmlessly if the sender did not wait */
  /* Wait for the sender to close (it reads the answer first): DisconnectNamedPipe throws away what it has not read. */
  (void)audit_io(h, ev, FALSE, buf, 1, &n, AUDIT_CLOSE_MS);
}

static DWORD WINAPI audit_thread(LPVOID arg) {
  int slot = (int)(INT_PTR)arg;
  HANDLE h = audit_pipes[slot];
  HANDLE ev;
  HANDLE waits[2];
  OVERLAPPED ov;
  DWORD n;
  DWORD w;
  BOOL connected;

  if ((ev = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL)
    return 1;
  waits[0] = ev;
  waits[1] = audit_stop_event;

  while (WaitForSingleObject(audit_stop_event, 0) != WAIT_OBJECT_0) {
    ZeroMemory(&ov, sizeof(ov));
    ov.hEvent = ev;
    ResetEvent(ev);
    connected = ConnectNamedPipe(h, &ov);
    if (!connected) {
      switch (GetLastError()) {
        case ERROR_PIPE_CONNECTED:
          connected = TRUE;
          break;
        case ERROR_IO_PENDING:
          for (;;) {
            w = WaitForMultipleObjects(2, waits, FALSE, 1000);
            if (w == WAIT_TIMEOUT) {
              if (slot == 0)
                audit_rate_sweep(FALSE);
              continue;
            }
            if (w == WAIT_OBJECT_0)
              connected = GetOverlappedResult(h, &ov, &n, FALSE);
            else {
              CancelIoEx(h, &ov);
              (void)GetOverlappedResult(h, &ov, &n, TRUE);
            }
            break;
          }
          break;
        case ERROR_NO_DATA: /* came and went before we looked */
          break;
        default:
          Sleep(100);
          break;
      }
    }
    if (connected && (WaitForSingleObject(audit_stop_event, 0) != WAIT_OBJECT_0))
      audit_serve_one(h, ev);
    DisconnectNamedPipe(h);
  }

  CloseHandle(ev);
  return 0;
}

/* ======================================================================
   Starting and stopping                                                   */

/* first: the SID with full control (the pipe: this process's own user, LocalSystem in the service; a trail: SYSTEM) */
static BOOL audit_make_acl(PACL* acl, PSID first, DWORD admin_rights, DWORD member_rights) {
  EXPLICIT_ACCESSA ea[2 + AUDIT_GRANT_MAX];
  int n = 0;
  int i;

  ZeroMemory(ea, sizeof(ea));
  ea[n].grfAccessPermissions = FILE_ALL_ACCESS;
  ea[n].Trustee.ptstrName = (LPSTR)first;
  n++;
  ea[n].grfAccessPermissions = admin_rights;
  ea[n].Trustee.ptstrName = (LPSTR)audit_admins_sid;
  n++;
  for (i = 0; i < audit_ngrant; i++) {
    ea[n].grfAccessPermissions = member_rights;
    ea[n].Trustee.ptstrName = (LPSTR)audit_grant_sids[i];
    n++;
  }
  for (i = 0; i < n; i++) {
    ea[i].grfAccessMode = SET_ACCESS;
    ea[i].grfInheritance = NO_INHERITANCE;
    ea[i].Trustee.TrusteeForm = TRUSTEE_IS_SID;
    ea[i].Trustee.TrusteeType = TRUSTEE_IS_UNKNOWN;
  }
  return SetEntriesInAclA((ULONG)n, ea, NULL, acl) == ERROR_SUCCESS;
}

static PSECURITY_DESCRIPTOR audit_make_sd(PACL acl, BOOL own_owner) {
  PSECURITY_DESCRIPTOR sd = LocalAlloc(LPTR, SECURITY_DESCRIPTOR_MIN_LENGTH);

  if (sd == NULL)
    return NULL;
  if (!InitializeSecurityDescriptor(sd, SECURITY_DESCRIPTOR_REVISION) || !SetSecurityDescriptorDacl(sd, TRUE, acl, FALSE) ||
      !SetSecurityDescriptorControl(sd, SE_DACL_PROTECTED, SE_DACL_PROTECTED) ||
      (own_owner && !SetSecurityDescriptorOwner(sd, (PSID)audit_own_sid, FALSE))) {
    LocalFree(sd);
    return NULL;
  }
  return sd;
}

static BOOL audit_own_user(void) {
  HANDLE tok;
  BYTE buf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  DWORD n = 0;
  BOOL ok;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
    return FALSE;
  ok = GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &n) &&
       CopySid(sizeof(audit_own_sid), (PSID)audit_own_sid, ((TOKEN_USER*)buf)->User.Sid);
  CloseHandle(tok);
  return ok;
}

static void audit_release(void) {
  int i;

  for (i = 0; i < AUDIT_INSTANCES; i++) {
    if ((audit_pipes[i] != NULL) && (audit_pipes[i] != INVALID_HANDLE_VALUE))
      CloseHandle(audit_pipes[i]);
    audit_pipes[i] = NULL;
  }
  if (audit_stop_event != NULL)
    CloseHandle(audit_stop_event);
  audit_stop_event = NULL;
  if (audit_pipe_sd != NULL)
    LocalFree(audit_pipe_sd);
  if (audit_pipe_acl != NULL)
    LocalFree(audit_pipe_acl);
  if (audit_trail_sd != NULL)
    LocalFree(audit_trail_sd);
  if (audit_trail_acl != NULL)
    LocalFree(audit_trail_acl);
  audit_pipe_sd = NULL;
  audit_pipe_acl = NULL;
  audit_trail_sd = NULL;
  audit_trail_acl = NULL;
  DeleteCriticalSection(&audit_cs);
}

static HANDLE audit_make_instance(BOOL first) {
  SECURITY_ATTRIBUTES sa;

  ZeroMemory(&sa, sizeof(sa));
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = audit_pipe_sd;
  sa.bInheritHandle = FALSE;
  return CreateNamedPipeA(audit_pipe_name,
                          PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0),
                          PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                          PIPE_UNLIMITED_INSTANCES, 64, AUDIT_PIPE_MAX, 0, &sa);
}

int sdaudit_start(const char* pipe_name, const char* sysdir, const char* const* grant, sdaudit_log_fn log) {
  DWORD n;
  char dom[128];
  DWORD dl;
  SID_NAME_USE use;
  int i;

  audit_log = (log != NULL) ? log : audit_nolog;
  if (audit_running)
    return 0;
  if ((pipe_name == NULL) || (sysdir == NULL) || (*sysdir == '\0') || (strlen(pipe_name) >= sizeof(audit_pipe_name)) ||
      (strlen(sysdir) >= sizeof(audit_dir) - 16)) {
    audit_log("audit writer: not started - no pipe name or system directory");
    return -1;
  }
  strcpy(audit_pipe_name, pipe_name);
  strcpy(audit_dir, sysdir);
  InitializeCriticalSection(&audit_cs);
  memset(audit_rate, 0, sizeof(audit_rate));
  ZeroMemory(audit_pipes, sizeof(audit_pipes));
  audit_taken = audit_dropped = audit_foreign = audit_unwritten = audit_limited = audit_rotate_failed = 0;
  audit_traced = 0;
  audit_rotate_after = 0;
  audit_nthreads = 0;

  n = sizeof(audit_system_sid);
  if (!CreateWellKnownSid(WinLocalSystemSid, NULL, (PSID)audit_system_sid, &n)) {
    audit_log("audit writer: not started - no SID for SYSTEM");
    audit_release();
    return -1;
  }
  n = sizeof(audit_admins_sid);
  if (!CreateWellKnownSid(WinBuiltinAdministratorsSid, NULL, (PSID)audit_admins_sid, &n) || !audit_own_user()) {
    audit_log("audit writer: not started - no SID for Administrators or for this process's user");
    audit_release();
    return -1;
  }
  audit_ngrant = 0;
  for (i = 0; (grant != NULL) && (grant[i] != NULL) && (audit_ngrant < AUDIT_GRANT_MAX); i++) {
    n = SECURITY_MAX_SID_SIZE;
    dl = sizeof(dom);
    if (LookupAccountNameA(NULL, grant[i], (PSID)audit_grant_sids[audit_ngrant], &n, dom, &dl, &use))
      audit_ngrant++;
    else
      audit_log("audit writer: no account %s - it is not given the pipe (error %lu)", grant[i],
                (unsigned long)GetLastError());
  }

  /* The pipe: this process's own user all (LocalSystem in the service - and the only one that may make another
     instance of the name), Administrators as a member.  A trail made here: SYSTEM and Administrators all, as
     secure-audit.ps1 sets them (owner, 16 Aug 2026: administrators are trusted).                               */
  if (!audit_make_acl(&audit_pipe_acl, (PSID)audit_own_sid, AUDIT_PIPE_GRANT, AUDIT_PIPE_GRANT) ||
      ((audit_pipe_sd = audit_make_sd(audit_pipe_acl, TRUE)) == NULL) ||
      !audit_make_acl(&audit_trail_acl, (PSID)audit_system_sid, FILE_ALL_ACCESS, AUDIT_TRAIL_GRANT) ||
      ((audit_trail_sd = audit_make_sd(audit_trail_acl, FALSE)) == NULL)) {
    audit_log("audit writer: not started - could not build the security descriptors (error %lu)",
              (unsigned long)GetLastError());
    audit_release();
    return -1;
  }

  if ((audit_stop_event = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL) {
    audit_release();
    return -1;
  }

  for (i = 0; i < AUDIT_INSTANCES; i++) {
    audit_pipes[i] = audit_make_instance(i == 0);
    if (audit_pipes[i] == INVALID_HANDLE_VALUE) {
      audit_log("audit writer: not started - %s could not be made (error %lu%s)", audit_pipe_name,
                (unsigned long)GetLastError(),
                (i == 0) ? "; another process may hold the name - sessions write the trail themselves" : "");
      audit_pipes[i] = NULL;
      audit_release();
      return -1;
    }
  }
  for (i = 0; i < AUDIT_INSTANCES; i++) {
    audit_threads[i] = CreateThread(NULL, 0, audit_thread, (LPVOID)(INT_PTR)i, 0, NULL);
    if (audit_threads[i] == NULL)
      break;
    audit_nthreads++;
  }
  if (audit_nthreads == 0) {
    audit_release();
    return -1;
  }

  audit_running = TRUE;
  audit_log("audit writer: serving %s with %d instance(s), writing %s\\audit (and %s\\locktrace when it is there); "
            "%d account(s) besides Administrators may send",
            audit_pipe_name, audit_nthreads, audit_dir, audit_dir, audit_ngrant);
  return 0;
}

void sdaudit_stop(void) {
  int i;

  if (!audit_running)
    return;
  SetEvent(audit_stop_event);
  if (WaitForMultipleObjects((DWORD)audit_nthreads, audit_threads, TRUE, AUDIT_STOP_MS) == WAIT_TIMEOUT)
    audit_log("audit writer: a serving thread did not end in %d seconds", AUDIT_STOP_MS / 1000);
  for (i = 0; i < audit_nthreads; i++)
    CloseHandle(audit_threads[i]);
  audit_nthreads = 0;

  audit_rate_sweep(TRUE);
  audit_log("audit writer: stopped - written %lu, dropped by the bound %lu, refused %lu, other tree %lu, "
            "not written %lu, rotations failed %lu, lock trace lines %lu",
            audit_taken, audit_limited, audit_dropped, audit_foreign, audit_unwritten, audit_rotate_failed,
            audit_traced);
  audit_running = FALSE;
  audit_release();
}

/* END-CODE */
