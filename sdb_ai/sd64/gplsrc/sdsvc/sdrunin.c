/* sdrunin.c - run.in's debugged child, started by the SD service
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
 * 13 Nov 26 Windows port - RELEASE_1.1 287: a GROUP account's register group is sdg_<account>, and it was refused (only sdu_ was
 *           accepted), so run.in WITH debug could not be used in any group account.  Either of SD's own two names for that account
 *           is accepted now; any other group is still refused.
 * 13 Nov 26 Windows port - written.  RELEASE_1.1 253(b): run.in WITH debug, the Windows form of Linux's
 *           "run.in account debug file program" (.claude/design-runin-debug-20261113.md, section 6).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY THE SERVICE.  The debugged program must run in a process whose token never held elevation (../win32runin.h says
 * why), as the account's own sessions would run it.  Making that token takes SeTcb - an S4U logon with groups added -
 * and starting a process with it takes SeAssignPrimaryToken; LocalSystem has both, and the SD service is the one
 * LocalSystem process SD has that lives as long as SD does.  The SDSYS session asks over SD_RUNIN_PIPE.
 *
 * WHO MAY ASK.  An ELEVATED member of Administrators, read from the token of the thread that wrote the request
 * (ImpersonateNamedPipeClient at identification level, then RevertToSelf before anything else; a revert that fails ends
 * the service, which must never go on as somebody else).  The pipe's DACL already lets nobody else open it, and an
 * unelevated administrator's token holds Administrators for deny only, so this is the second of two locks.  The asker is
 * more privileged than anything this makes, so the check cannot be a way up; it exists so that the run is ONLY reachable
 * from an administrator's elevated session (owner, 13 Nov: nothing new is reachable unless an administrator uses DEBUG
 * under run.in).
 *
 * WHAT IT BELIEVES OF THE REQUEST.  Words, checked again here (runin_plain_word); the account's group is the register's,
 * read by this process, and must be sdu_<account> (a user account) or sdg_<account> (a group account); the store is made
 * here; no path comes from the wire.
 *
 * THE CHILD'S TOKEN, IN ORDER (the order is what test-runindebug-units.py holds):
 *   1. win32_s4u_logon_groups(SD_RUNIN_ACCOUNT, {sdusers, sdu_<account>})   the bare account, plus the two groups a
 *                                    session of that account has: sdusers reaches SD's shared segment and data tree,
 *                                    sdu_<account> the account's directory.  Nothing else is added.
 *   2. DuplicateTokenEx -> primary    CreateProcessAsUser wants one
 *   3. every privilege REMOVED        not disabled: nothing in the child can enable one again
 *   4. checked, not assumed           not elevated, integrity Medium or lower (Low is measured fatal to an MSYS2
 *                                    process here, RELEASE_1.1 53), no Administrators enabled, both groups present
 *                                    and enabled (design falsifier F2, asked of every run), the logon SID found
 *   5. the store                      a directory only this logon and administrators may use (sdrunin_store_make)
 *   6. a job of ONE process           JOB_OBJECT_LIMIT_ACTIVE_PROCESS 1 and KILL_ON_JOB_CLOSE: the child cannot start
 *                                    another process, and the run's end ends it.  Design falsifier F6 is whether SD
 *                                    needs a second one for anything a debugged program does; if it does, the limit
 *                                    goes, never the token.
 *   7. CreateProcessAsUser, SUSPENDED, then AssignProcessToJobObject, then ResumeThread
 *
 * THE CHILD'S SCREEN AND KEYBOARD are the client end of a private pipe (only SYSTEM may open its name), handed over as
 * its standard handles, one duplicate per descriptor (win32session.c's shape, measured by probe-pipestd).  This relays
 * between that pipe and the asker's: the child's bytes to the asker, the asker's to the child.  The run ends when the
 * child's end closes (it has exited) or the asker's does (the job is terminated).  Then the store is removed.
 *
 * NOTHING HERE IS FATAL TO THE SERVICE.  A run that cannot start is answered "ER <reason>" and logged; the serving
 * thread goes back to waiting.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <userenv.h>
#include <bcrypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>

#include "../win32runin.h"
#include "../win32s4u.h"
#include "sdrunin.h"

#define RUNIN_INSTANCES 2
#define RUNIN_REQUEST_MS 10000  /* the request line must arrive within this */
#define RUNIN_WRITE_MS 60000    /* a write to the asker that takes longer ends the run */
#define RUNIN_KEY_MS 5000       /* a write of keys to the child that takes longer is dropped */
#define RUNIN_FLUSH_MS 3000     /* the child's last screen, read by the asker before the pipe is let go */
#define RUNIN_DRAIN_MS 5000     /* what the child wrote after the asker went, read and thrown away */
#define RUNIN_STOP_MS 8000
#define RUNIN_IO 4096
#define RUNIN_REGISTER_MAX 65536

/* What an administrator may do to the pipe: read and write data, read its owner and attributes.  Not
   FILE_CREATE_PIPE_INSTANCE, WRITE_DAC or WRITE_OWNER. */
#define RUNIN_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)

/* What the child's logon may do to its store: list it, add, read, write and delete FILES in it.  NOT
   FILE_ADD_SUBDIRECTORY - a junction is a directory, so no link out of the store can be made - and not WRITE_DAC,
   WRITE_OWNER or DELETE on the directory itself. */
#define RUNIN_STORE_DIR_GRANT                                                                                          \
  (FILE_LIST_DIRECTORY | FILE_ADD_FILE | FILE_TRAVERSE | FILE_READ_ATTRIBUTES | FILE_READ_EA | FILE_DELETE_CHILD |    \
   READ_CONTROL | SYNCHRONIZE)
#define RUNIN_STORE_FILE_GRANT (FILE_GENERIC_READ | FILE_GENERIC_WRITE | DELETE)

typedef struct {
  HANDLE job;
  HANDLE proc;
  HANDLE srv;            /* the service's end of the child's screen and keyboard (overlapped) */
  DWORD pid;
  char store[MAX_PATH];
} RUNIN_RUN;

static CRITICAL_SECTION runin_cs;
static BOOL runin_running = FALSE;
static HANDLE runin_stop_event = NULL;
static HANDLE runin_threads[RUNIN_INSTANCES];
static HANDLE runin_pipes[RUNIN_INSTANCES];
static int runin_nthreads = 0;
static char runin_pipe_name[MAX_PATH];
static char runin_sysdir[MAX_PATH];
static char runin_base[MAX_PATH];
static char runin_sd_exe[MAX_PATH];
static PSECURITY_DESCRIPTOR runin_pipe_sd = NULL;
static PACL runin_pipe_acl = NULL;
static BYTE runin_system_sid[SECURITY_MAX_SID_SIZE];
static BYTE runin_admins_sid[SECURITY_MAX_SID_SIZE];
static BYTE runin_own_sid[SECURITY_MAX_SID_SIZE];
static BOOL runin_sids_ok = FALSE;

static void runin_nolog(const char* fmt, ...) {
  (void)fmt;
}

/* Never NULL: the parts the test drives on their own (sdrunin_store_make) log before sdrunin_start() was ever called. */
static sdrunin_log_fn runin_log = runin_nolog;

static void say(char* why, size_t whylen, const char* fmt, ...) {
  va_list ap;

  if ((why == NULL) || (whylen == 0))
    return;
  va_start(ap, fmt);
  vsnprintf(why, whylen, fmt, ap);
  va_end(ap);
}

static BOOL runin_well_known_sids(void) {
  HANDLE tok;
  BYTE buf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  DWORD n;
  BOOL ok;

  if (runin_sids_ok)
    return TRUE;
  n = sizeof(runin_system_sid);
  if (!CreateWellKnownSid(WinLocalSystemSid, NULL, (PSID)runin_system_sid, &n))
    return FALSE;
  n = sizeof(runin_admins_sid);
  if (!CreateWellKnownSid(WinBuiltinAdministratorsSid, NULL, (PSID)runin_admins_sid, &n))
    return FALSE;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
    return FALSE;
  ok = GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &n) &&
       CopySid(sizeof(runin_own_sid), (PSID)runin_own_sid, ((TOKEN_USER*)buf)->User.Sid);
  CloseHandle(tok);
  runin_sids_ok = ok;
  return ok;
}

/* ======================================================================
   The request                                                              */

int sdrunin_parse(const char* line, SDRUNIN_REQ* rq, char* why, size_t whylen) {
  char copy[RUNIN_LINE_MAX + 1];
  char* field[6];
  char* p;
  int i;

  memset(rq, 0, sizeof(*rq));
  if ((line == NULL) || (strlen(line) >= sizeof(copy)) || (strncmp(line, RUNIN_MAGIC, strlen(RUNIN_MAGIC)) != 0)) {
    say(why, whylen, "the request is not a run.in request");
    return -1;
  }
  strcpy(copy, line + strlen(RUNIN_MAGIC));
  p = copy;
  for (i = 0; i < 6; i++) {
    field[i] = p;
    p = strchr(p, '\t');
    if (i < 5) {
      if (p == NULL) {
        say(why, whylen, "the request has %d of its 6 fields", i + 1);
        return -1;
      }
      *(p++) = '\0';
    } else if (p != NULL) {
      say(why, whylen, "the request has more than 6 fields");
      return -1;
    }
  }
  if (!runin_plain_word(field[0], RUNIN_WORD_MAX) || !runin_plain_word(field[1], RUNIN_WORD_MAX) ||
      !runin_plain_word(field[2], RUNIN_WORD_MAX)) {
    say(why, whylen, "the account, the file and the program must each be a plain word");
    return -1;
  }
  if (strcmp(field[0], "sdsys") == 0) {
    say(why, whylen, "run.in works in the other accounts");
    return -1;
  }
  if (!runin_term_word(field[3])) {
    say(why, whylen, "the terminal type is not a plain name");
    return -1;
  }
  rq->cols = runin_size(field[4], RUNIN_MIN_COLS);
  rq->rows = runin_size(field[5], RUNIN_MIN_ROWS);
  if ((rq->cols == 0) || (rq->rows == 0)) {
    say(why, whylen, "the screen size is not %d to %d by %d to %d", RUNIN_MIN_COLS, RUNIN_MAX_SIZE, RUNIN_MIN_ROWS,
        RUNIN_MAX_SIZE);
    return -1;
  }
  strcpy(rq->account, field[0]);
  strcpy(rq->file, field[1]);
  strcpy(rq->program, field[2]);
  strcpy(rq->term, field[3]);
  return 0;
}

/* Field n (1-based) of a register record as a directory file holds it: fields end at a field mark or a line break (mark
   mapping), a CR before a line feed is dropped, and only the first value is taken. */
static void register_field(const char* rec, int n, char* out, size_t outlen) {
  const char* p = rec;
  size_t k = 0;
  int f = 1;

  out[0] = '\0';
  while ((*p != '\0') && (f < n)) {
    if ((*p == '\xfe') || (*p == '\n'))
      f++;
    p++;
  }
  if (f != n)
    return;
  while ((*p != '\0') && (*p != '\xfe') && (*p != '\n') && (*p != '\xfd') && (k + 1 < outlen)) {
    if (*p != '\r')
      out[k++] = *p;
    p++;
  }
  out[k] = '\0';
  while ((k > 0) && (out[k - 1] == ' '))
    out[--k] = '\0';
}

int sdrunin_register(const char* sysdir, const char* account, char* group, size_t grouplen, char* why,
                     size_t whylen) {
  char path[MAX_PATH];
  char want[RUNIN_WORD_MAX + 8];
  char want_g[RUNIN_WORD_MAX + 8];
  char suspended[64];
  char* rec = NULL;
  HANDLE h;
  BY_HANDLE_FILE_INFORMATION info;
  DWORD n = 0;
  int rc = -1;

  group[0] = '\0';
  if (!runin_plain_word(account, RUNIN_WORD_MAX) ||
      (snprintf(path, sizeof(path), "%s\\accounts\\%s", sysdir, account) >= (int)sizeof(path))) {
    say(why, whylen, "no register record can be named for that account");
    return -1;
  }
  h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
                  FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    DWORD attr = GetFileAttributesA(path);

    if ((attr != INVALID_FILE_ATTRIBUTES) && (attr & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)))
      say(why, whylen, "the register record of %s is not a plain file", account);
    else
      say(why, whylen, "%s is not a registered account", account);
    return -1;
  }
  if (!GetFileInformationByHandle(h, &info) ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) ||
      (info.nFileSizeHigh != 0) || (info.nFileSizeLow > RUNIN_REGISTER_MAX)) {
    say(why, whylen, "the register record of %s is not a plain file", account);
    goto done;
  }
  if ((rec = (char*)malloc(info.nFileSizeLow + 1)) == NULL) {
    say(why, whylen, "no memory");
    goto done;
  }
  if (!ReadFile(h, rec, info.nFileSizeLow, &n, NULL) || (n != info.nFileSizeLow)) {
    say(why, whylen, "the register record of %s could not be read", account);
    goto done;
  }
  rec[n] = '\0';

  register_field(rec, 5, suspended, sizeof(suspended)); /* ACC$SUSPENDED */
  if (_stricmp(suspended, "SUSPENDED") == 0) {
    say(why, whylen, "account %s is suspended", account);
    goto done;
  }
  register_field(rec, 3, group, grouplen); /* ACC$GROUP */
  snprintf(want, sizeof(want), "%s%s", RUNIN_GROUP_PREFIX, account);
  snprintf(want_g, sizeof(want_g), "%s%s", RUNIN_GROUP_PREFIX_GROUP, account);
  if ((_stricmp(group, want) != 0) && (_stricmp(group, want_g) != 0)) {
    say(why, whylen, "the register gives account %s the group \"%.80s\", not %s or %s", account, group, want, want_g);
    group[0] = '\0';
    goto done;
  }
  rc = 0;

done:
  if (rec != NULL)
    free(rec);
  CloseHandle(h);
  return rc;
}

/* ======================================================================
   The environment                                                          */

static int env_dropped(const WCHAR* var) {
  static const WCHAR* drop[] = {L"TERM", L"LINES", L"COLUMNS", L"" RUNIN_STORE_ENV, L"SD_SESSION",
                                L"SD_PHANTOM_NONCE", NULL};
  const WCHAR* eq;
  size_t len;
  int i;

  if (var[0] == L'=')
    return 0; /* the per-drive current directories: kept as they are */
  if ((eq = wcschr(var, L'=')) == NULL)
    return 1;
  len = (size_t)(eq - var);
  for (i = 0; drop[i] != NULL; i++) {
    if ((wcslen(drop[i]) == len) && (_wcsnicmp(var, drop[i], len) == 0))
      return 1;
  }
  return 0;
}

void* sdrunin_env(const void* src, const char* store, const char* term, int cols, int rows) {
  char add[4][MAX_PATH + 32];
  WCHAR wadd[4][MAX_PATH + 32];
  const WCHAR* p;
  WCHAR* out;
  WCHAR* q;
  size_t total = 1;
  size_t n;
  int i;

  if ((store == NULL) || (term == NULL))
    return NULL;
  snprintf(add[0], sizeof(add[0]), "TERM=%s", term);
  snprintf(add[1], sizeof(add[1]), "LINES=%d", rows);
  snprintf(add[2], sizeof(add[2]), "COLUMNS=%d", cols);
  if (snprintf(add[3], sizeof(add[3]), "%s=%s", RUNIN_STORE_ENV, store) >= (int)sizeof(add[3]))
    return NULL;
  for (i = 0; i < 4; i++) {
    if (MultiByteToWideChar(CP_ACP, 0, add[i], -1, wadd[i], MAX_PATH + 32) == 0)
      return NULL;
    total += wcslen(wadd[i]) + 1;
  }
  for (p = (const WCHAR*)src; (p != NULL) && (*p != L'\0'); p += wcslen(p) + 1) {
    if (!env_dropped(p))
      total += wcslen(p) + 1;
  }

  if ((out = (WCHAR*)malloc(total * sizeof(WCHAR))) == NULL)
    return NULL;
  q = out;
  for (p = (const WCHAR*)src; (p != NULL) && (*p != L'\0'); p += wcslen(p) + 1) {
    if (!env_dropped(p)) {
      n = wcslen(p) + 1;
      memcpy(q, p, n * sizeof(WCHAR));
      q += n;
    }
  }
  for (i = 0; i < 4; i++) {
    n = wcslen(wadd[i]) + 1;
    memcpy(q, wadd[i], n * sizeof(WCHAR));
    q += n;
  }
  *q = L'\0';
  return out;
}

/* ======================================================================
   The store                                                                */

/* SYSTEM, Administrators and this process's own user (LocalSystem in the service, the test's user in the test) full
   control, inherited; with logon, the child's two entries (see RUNIN_STORE_DIR_GRANT). */
static PACL store_acl(PSID logon) {
  DWORD size = sizeof(ACL) + 5 * (sizeof(ACCESS_ALLOWED_ACE) + SECURITY_MAX_SID_SIZE);
  PACL acl = (PACL)LocalAlloc(LPTR, size);
  DWORD inh = OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE;

  if ((acl == NULL) || !InitializeAcl(acl, size, ACL_REVISION) ||
      !AddAccessAllowedAceEx(acl, ACL_REVISION, inh, FILE_ALL_ACCESS, (PSID)runin_system_sid) ||
      !AddAccessAllowedAceEx(acl, ACL_REVISION, inh, FILE_ALL_ACCESS, (PSID)runin_admins_sid) ||
      (!EqualSid((PSID)runin_own_sid, (PSID)runin_system_sid) &&
       !AddAccessAllowedAceEx(acl, ACL_REVISION, inh, FILE_ALL_ACCESS, (PSID)runin_own_sid)) ||
      ((logon != NULL) && (!AddAccessAllowedAceEx(acl, ACL_REVISION, 0, RUNIN_STORE_DIR_GRANT, logon) ||
                           !AddAccessAllowedAceEx(acl, ACL_REVISION, OBJECT_INHERIT_ACE | INHERIT_ONLY_ACE,
                                                  RUNIN_STORE_FILE_GRANT, logon)))) {
    if (acl != NULL)
      LocalFree(acl);
    return NULL;
  }
  return acl;
}

static BOOL random_hex(char* out, size_t outlen, int bytes) {
  unsigned char b[16];
  int i;

  if ((bytes > 16) || ((size_t)(bytes * 2 + 1) > outlen))
    return FALSE;
  if (BCryptGenRandom(NULL, b, (ULONG)bytes, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
    return FALSE;
  for (i = 0; i < bytes; i++)
    snprintf(out + (2 * i), 3, "%02x", b[i]);
  return TRUE;
}

/* The base: a directory, not a link, owned by SYSTEM, Administrators or this process's user, with the protected DACL
   above.  One that is not - made by somebody else while the service was not looking: the data tree gives sdusers
   Modify - is moved aside, never used. */
static int store_base_ready(const char* base, char* why, size_t whylen) {
  DWORD attr = GetFileAttributesA(base);
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR osd = NULL;
  PACL acl = NULL;
  SECURITY_ATTRIBUTES sa;
  SECURITY_DESCRIPTOR sd;
  char aside[MAX_PATH + 48];
  char tag[17];
  BOOL ours = FALSE;
  DWORD rc;

  if (attr != INVALID_FILE_ATTRIBUTES) {
    if ((attr & FILE_ATTRIBUTE_DIRECTORY) && !(attr & FILE_ATTRIBUTE_REPARSE_POINT) &&
        (GetNamedSecurityInfoA(base, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, &osd) ==
         ERROR_SUCCESS) &&
        (owner != NULL) &&
        (EqualSid(owner, (PSID)runin_system_sid) || EqualSid(owner, (PSID)runin_admins_sid) ||
         EqualSid(owner, (PSID)runin_own_sid)))
      ours = TRUE;
    if (osd != NULL)
      LocalFree(osd);
    if (!ours) {
      if (!random_hex(tag, sizeof(tag), 8) ||
          (snprintf(aside, sizeof(aside), "%s.untrusted-%s", base, tag) >= (int)sizeof(aside)) ||
          !MoveFileExA(base, aside, 0)) {
        say(why, whylen, "%s is not SD's own and could not be moved aside (error %lu)", base,
            (unsigned long)GetLastError());
        return -1;
      }
      runin_log("run.in debug: %s was not SD's own (a link, or owned by somebody else); moved aside to %s", base,
                aside);
      attr = INVALID_FILE_ATTRIBUTES;
    }
  }

  if ((acl = store_acl(NULL)) == NULL) {
    say(why, whylen, "the store's access list could not be built (error %lu)", (unsigned long)GetLastError());
    return -1;
  }
  if (attr == INVALID_FILE_ATTRIBUTES) {
    if (!InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION) || !SetSecurityDescriptorDacl(&sd, TRUE, acl, FALSE) ||
        !SetSecurityDescriptorControl(&sd, SE_DACL_PROTECTED, SE_DACL_PROTECTED)) {
      LocalFree(acl);
      say(why, whylen, "the store's security descriptor could not be built");
      return -1;
    }
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = &sd;
    sa.bInheritHandle = FALSE;
    if (!CreateDirectoryA(base, &sa) && (GetLastError() != ERROR_ALREADY_EXISTS)) {
      say(why, whylen, "%s could not be made (error %lu)", base, (unsigned long)GetLastError());
      LocalFree(acl);
      return -1;
    }
  }
  /* Made or found ours: its DACL is set again, whoever changed it. */
  rc = SetNamedSecurityInfoA((LPSTR)base, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
                             NULL, NULL, acl, NULL);
  LocalFree(acl);
  if (rc != ERROR_SUCCESS) {
    say(why, whylen, "%s's access list could not be set (error %lu)", base, (unsigned long)rc);
    return -1;
  }
  return 0;
}

int sdrunin_store_make(const char* store_base, void* logon_sid, char* path, size_t pathlen, char* why, size_t whylen) {
  SECURITY_ATTRIBUTES sa;
  SECURITY_DESCRIPTOR sd;
  PACL acl;
  char tag[33];
  int ok = -1;

  path[0] = '\0';
  if (!runin_well_known_sids()) {
    say(why, whylen, "the well-known SIDs could not be made");
    return -1;
  }
  if ((logon_sid == NULL) || !IsValidSid((PSID)logon_sid)) {
    say(why, whylen, "no logon SID for the store");
    return -1;
  }
  if (store_base_ready(store_base, why, whylen) != 0)
    return -1;
  if (!random_hex(tag, sizeof(tag), 16) ||
      (snprintf(path, pathlen, "%s\\r%s", store_base, tag) >= (int)pathlen)) {
    say(why, whylen, "the store's name could not be made");
    path[0] = '\0';
    return -1;
  }
  if ((acl = store_acl((PSID)logon_sid)) == NULL) {
    say(why, whylen, "the store's access list could not be built");
    path[0] = '\0';
    return -1;
  }
  if (InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION) && SetSecurityDescriptorDacl(&sd, TRUE, acl, FALSE) &&
      SetSecurityDescriptorControl(&sd, SE_DACL_PROTECTED, SE_DACL_PROTECTED)) {
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = &sd;
    sa.bInheritHandle = FALSE;
    /* A NEW directory or nothing: a name that is there already is not this run's. */
    if (CreateDirectoryA(path, &sa))
      ok = 0;
    else
      say(why, whylen, "the store %s could not be made (error %lu)", path, (unsigned long)GetLastError());
  }
  LocalFree(acl);
  if (ok != 0)
    path[0] = '\0';
  return ok;
}

void sdrunin_store_remove(const char* path) {
  char pattern[MAX_PATH + 4];
  char full[MAX_PATH * 2];
  WIN32_FIND_DATAA fd;
  HANDLE f;

  if ((path == NULL) || (path[0] == '\0') || (snprintf(pattern, sizeof(pattern), "%s\\*", path) >= (int)sizeof(pattern)))
    return;
  f = FindFirstFileA(pattern, &fd);
  if (f != INVALID_HANDLE_VALUE) {
    do {
      if ((strcmp(fd.cFileName, ".") == 0) || (strcmp(fd.cFileName, "..") == 0))
        continue;
      if (snprintf(full, sizeof(full), "%s\\%s", path, fd.cFileName) >= (int)sizeof(full))
        continue;
      if (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
        /* A link is removed as a link.  RemoveDirectory on a junction takes the junction, not what it points at. */
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
          RemoveDirectoryA(full);
        else
          DeleteFileA(full);
      } else if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        RemoveDirectoryA(full); /* nobody may make one here; an empty one goes, a full one is never walked */
      } else {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_READONLY)
          SetFileAttributesA(full, FILE_ATTRIBUTE_NORMAL);
        DeleteFileA(full);
      }
    } while (FindNextFileA(f, &fd));
    FindClose(f);
  }
  RemoveDirectoryA(path);
}

/* ======================================================================
   The token                                                                */

int sdrunin_strip_privileges(void* token, char* why, size_t whylen) {
  HANDLE tok = (HANDLE)token;
  BYTE buf[8192];
  DWORD len = 0;
  TOKEN_PRIVILEGES* tp = (TOKEN_PRIVILEGES*)buf;
  DWORD i;

  if (!GetTokenInformation(tok, TokenPrivileges, buf, sizeof(buf), &len)) {
    say(why, whylen, "the token's privileges could not be read (error %lu)", (unsigned long)GetLastError());
    return 0;
  }
  for (i = 0; i < tp->PrivilegeCount; i++)
    tp->Privileges[i].Attributes = SE_PRIVILEGE_REMOVED;
  if ((tp->PrivilegeCount > 0) && !AdjustTokenPrivileges(tok, FALSE, tp, 0, NULL, NULL)) {
    say(why, whylen, "the token's privileges could not be removed (error %lu)", (unsigned long)GetLastError());
    return 0;
  }
  /* AdjustTokenPrivileges can return TRUE having done only part of the job: ask again rather than believe it. */
  len = 0;
  if (!GetTokenInformation(tok, TokenPrivileges, buf, sizeof(buf), &len) || (tp->PrivilegeCount != 0)) {
    say(why, whylen, "the token still holds %lu privilege(s)", (unsigned long)tp->PrivilegeCount);
    return 0;
  }
  return 1;
}

static BOOL group_sid(const char* name, BYTE* sid) {
  char dom[256];
  DWORD n = SECURITY_MAX_SID_SIZE;
  DWORD dl = sizeof(dom);
  SID_NAME_USE use;

  return LookupAccountNameA(NULL, name, (PSID)sid, &n, dom, &dl, &use);
}

/* Step 4: what the token IS, read back.  logon gets the logon SID. */
static int runin_token_ok(HANDLE tok, const char* group, BYTE* logon, char* why, size_t whylen) {
  TOKEN_ELEVATION el;
  BYTE ibuf[sizeof(TOKEN_MANDATORY_LABEL) + SECURITY_MAX_SID_SIZE];
  TOKEN_MANDATORY_LABEL* tml = (TOKEN_MANDATORY_LABEL*)ibuf;
  BYTE* gbuf = NULL;
  TOKEN_GROUPS* tg;
  BYTE users[SECURITY_MAX_SID_SIZE];
  BYTE acct[SECURITY_MAX_SID_SIZE];
  BOOL have_users = FALSE;
  BOOL have_acct = FALSE;
  BOOL have_logon = FALSE;
  DWORD n = 0;
  DWORD rid;
  DWORD i;
  int ok = 0;

  if (!GetTokenInformation(tok, TokenElevation, &el, sizeof(el), &n) || el.TokenIsElevated) {
    say(why, whylen, "the child's token would be elevated");
    return 0;
  }
  n = 0;
  if (!GetTokenInformation(tok, TokenIntegrityLevel, ibuf, sizeof(ibuf), &n)) {
    say(why, whylen, "the child's integrity could not be read");
    return 0;
  }
  rid = *GetSidSubAuthority(tml->Label.Sid, (DWORD)(*GetSidSubAuthorityCount(tml->Label.Sid) - 1));
  if (rid > SECURITY_MANDATORY_MEDIUM_RID) {
    say(why, whylen, "the child's integrity would be above Medium (is %s in Administrators?)", SD_RUNIN_ACCOUNT);
    return 0;
  }
  if (!group_sid(RUNIN_USERS_GROUP, users) || !group_sid(group, acct)) {
    say(why, whylen, "the groups %s and %s could not be looked up", RUNIN_USERS_GROUP, group);
    return 0;
  }
  n = 0;
  (void)GetTokenInformation(tok, TokenGroups, NULL, 0, &n);
  if ((n == 0) || ((gbuf = (BYTE*)malloc(n)) == NULL) || !GetTokenInformation(tok, TokenGroups, gbuf, n, &n)) {
    say(why, whylen, "the child's groups could not be read");
    goto done;
  }
  tg = (TOKEN_GROUPS*)gbuf;
  for (i = 0; i < tg->GroupCount; i++) {
    DWORD a = tg->Groups[i].Attributes;
    BOOL enabled = (a & SE_GROUP_ENABLED) && !(a & SE_GROUP_USE_FOR_DENY_ONLY);

    if (enabled && EqualSid(tg->Groups[i].Sid, (PSID)runin_admins_sid)) {
      say(why, whylen, "the child's token would hold Administrators (is %s in that group?)", SD_RUNIN_ACCOUNT);
      goto done;
    }
    if (enabled && EqualSid(tg->Groups[i].Sid, (PSID)users))
      have_users = TRUE;
    if (enabled && EqualSid(tg->Groups[i].Sid, (PSID)acct))
      have_acct = TRUE;
    if ((a & SE_GROUP_LOGON_ID) && !have_logon) {
      have_logon = CopySid(SECURITY_MAX_SID_SIZE, (PSID)logon, tg->Groups[i].Sid);
    }
  }
  if (!have_users || !have_acct) {
    say(why, whylen, "the logon did not put %s%s%s in the child's token (design falsifier F2)",
        have_users ? "" : RUNIN_USERS_GROUP, (!have_users && !have_acct) ? " and " : "", have_acct ? "" : group);
    goto done;
  }
  if (!have_logon) {
    say(why, whylen, "the child's token has no logon SID");
    goto done;
  }
  ok = 1;

done:
  if (gbuf != NULL)
    free(gbuf);
  return ok;
}

/* ======================================================================
   Starting and ending a run                                                */

static void run_end(RUNIN_RUN* run) {
  DWORD code = 0;

  if (run->job != NULL)
    TerminateJobObject(run->job, 1);
  if (run->proc != NULL) {
    WaitForSingleObject(run->proc, 5000);
    GetExitCodeProcess(run->proc, &code);
    CloseHandle(run->proc);
  }
  if (run->job != NULL)
    CloseHandle(run->job);
  if (run->srv != NULL)
    CloseHandle(run->srv);
  if (run->store[0] != '\0')
    sdrunin_store_remove(run->store);
  runin_log("run.in debug: run of pid %lu ended (exit %lu); its store is removed", (unsigned long)run->pid,
            (unsigned long)code);
  memset(run, 0, sizeof(*run));
}

static int run_start(const SDRUNIN_REQ* rq, const char* group, RUNIN_RUN* run, char* why, size_t whylen) {
  const char* groups[3];
  HANDLE imp = NULL;
  HANDLE prim = NULL;
  HANDLE cli = INVALID_HANDLE_VALUE;
  HANDLE inh[3] = {NULL, NULL, NULL};
  BYTE logon[SECURITY_MAX_SID_SIZE];
  char ioname[96];
  char tag[33];
  char cmd[MAX_PATH + 512];
  char dir[MAX_PATH];
  char* slash;
  PSECURITY_DESCRIPTOR iosd = NULL;
  SECURITY_ATTRIBUTES sa;
  OVERLAPPED ov;
  STARTUPINFOEXA six;
  PROCESS_INFORMATION pi;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION jl;
  SIZE_T alen = 0;
  void* env = NULL;
  void* newenv = NULL;
  int i;
  int ok = 0;

  memset(run, 0, sizeof(*run));
  ZeroMemory(&six, sizeof(six));
  ZeroMemory(&pi, sizeof(pi));
  six.StartupInfo.cb = sizeof(six);

  /* 1. */
  groups[0] = RUNIN_USERS_GROUP;
  groups[1] = group;
  groups[2] = NULL;
  imp = (HANDLE)win32_s4u_logon_groups(SD_RUNIN_ACCOUNT, groups);
  if (imp == NULL) {
    say(why, whylen,
        "the account %s could not be logged on with the groups %s and %s (install-service.ps1 makes the account; the "
        "SD service, LocalSystem, is the only process that may do this)",
        SD_RUNIN_ACCOUNT, RUNIN_USERS_GROUP, group);
    return 0;
  }
  /* 2. */
  if (!DuplicateTokenEx(imp, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation, TokenPrimary, &prim)) {
    say(why, whylen, "DuplicateTokenEx failed (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  /* 3. */
  if (!sdrunin_strip_privileges(prim, why, whylen))
    goto done;
  /* 4. */
  if (!runin_token_ok(prim, group, logon, why, whylen))
    goto done;
  /* 5. */
  if (sdrunin_store_make(runin_base, (void*)logon, run->store, sizeof(run->store), why, whylen) != 0)
    goto done;

  /* The child's screen and keyboard: a pipe whose name only SYSTEM may open. */
  if (!random_hex(tag, sizeof(tag), 16) ||
      (snprintf(ioname, sizeof(ioname), "\\\\.\\pipe\\sd-runin-io-%s", tag) >= (int)sizeof(ioname)) ||
      !ConvertStringSecurityDescriptorToSecurityDescriptorA("D:P(A;;GA;;;SY)", SDDL_REVISION_1, &iosd, NULL)) {
    say(why, whylen, "the child's pipe could not be named");
    goto done;
  }
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = iosd;
  sa.bInheritHandle = FALSE;
  run->srv = CreateNamedPipeA(ioname, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                              PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 65536,
                              65536, 0, &sa);
  if (run->srv == INVALID_HANDLE_VALUE) {
    run->srv = NULL;
    say(why, whylen, "the child's pipe could not be made (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  cli = CreateFileA(ioname, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
  if (cli == INVALID_HANDLE_VALUE) {
    say(why, whylen, "the child's end of its pipe could not be opened (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  ZeroMemory(&ov, sizeof(ov));
  if ((ov.hEvent = CreateEventA(NULL, TRUE, FALSE, NULL)) != NULL) {
    if (!ConnectNamedPipe(run->srv, &ov) && (GetLastError() == ERROR_IO_PENDING))
      WaitForSingleObject(ov.hEvent, 1000);
    CloseHandle(ov.hEvent);
  }
  /* One inheritable duplicate per descriptor (win32session.c: one handle shared by 0 and 1 breaks the runtime's pipe
     handler and its select). */
  for (i = 0; i < 3; i++) {
    if (!DuplicateHandle(GetCurrentProcess(), cli, GetCurrentProcess(), &inh[i], 0, TRUE, DUPLICATE_SAME_ACCESS)) {
      say(why, whylen, "the child's handles could not be made (error %lu)", (unsigned long)GetLastError());
      goto done;
    }
  }
  six.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  six.StartupInfo.hStdInput = inh[0];
  six.StartupInfo.hStdOutput = inh[1];
  six.StartupInfo.hStdError = inh[2];
  six.StartupInfo.lpDesktop = (char*)"winsta0\\default";
  /* Exactly these three cross, nothing else of the service's (win32relay.c's correctness point). */
  InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
  six.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, alen);
  if ((six.lpAttributeList == NULL) || !InitializeProcThreadAttributeList(six.lpAttributeList, 1, 0, &alen) ||
      !UpdateProcThreadAttribute(six.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inh, sizeof(inh), NULL,
                                 NULL)) {
    if (six.lpAttributeList != NULL) {
      HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
      six.lpAttributeList = NULL;
    }
    say(why, whylen, "the child's handle list could not be made (error %lu)", (unsigned long)GetLastError());
    goto done;
  }

  /* The account's own environment block, less what the run sets, plus TERM, LINES, COLUMNS and the store. */
  if (!CreateEnvironmentBlock(&env, prim, FALSE))
    env = NULL;
  if ((newenv = sdrunin_env(env, run->store, rq->term, rq->cols, rq->rows)) == NULL) {
    say(why, whylen, "the child's environment could not be made");
    goto done;
  }

  /* 6. */
  if ((run->job = CreateJobObjectA(NULL, NULL)) == NULL) {
    say(why, whylen, "the child's job could not be made (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  ZeroMemory(&jl, sizeof(jl));
  jl.BasicLimitInformation.LimitFlags =
      JOB_OBJECT_LIMIT_ACTIVE_PROCESS | JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
  jl.BasicLimitInformation.ActiveProcessLimit = 1;
  if (!SetInformationJobObject(run->job, JobObjectExtendedLimitInformation, &jl, sizeof(jl))) {
    say(why, whylen, "the child's job limits could not be set (error %lu)", (unsigned long)GetLastError());
    goto done;
  }

  /* The child: sd.exe -RUNIN <account>, DEBUG file program as its one command.  Its working directory is sd.exe's own,
     which the account can read; LOGIN changes to the account's. */
  snprintf(dir, sizeof(dir), "%s", runin_sd_exe);
  if ((slash = strrchr(dir, '\\')) != NULL)
    *slash = '\0';
  if (snprintf(cmd, sizeof(cmd), "\"%s\" -RUNIN %s -QUIET -TERM %s debug %s %s", runin_sd_exe, rq->account, rq->term,
               rq->file, rq->program) >= (int)sizeof(cmd)) {
    say(why, whylen, "the child's command line is too long");
    goto done;
  }
  /* 7. */
  if (!CreateProcessAsUserA(prim, runin_sd_exe, cmd, NULL, NULL, TRUE,
                            CREATE_SUSPENDED | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                            newenv, dir, &six.StartupInfo, &pi)) {
    say(why, whylen, "the child could not be started (CreateProcessAsUser error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  if (!AssignProcessToJobObject(run->job, pi.hProcess)) {
    say(why, whylen, "the child could not be put in its job (error %lu); it was not let run", (unsigned long)GetLastError());
    TerminateProcess(pi.hProcess, 1);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    goto done;
  }
  ResumeThread(pi.hThread);
  CloseHandle(pi.hThread);
  run->proc = pi.hProcess;
  run->pid = pi.dwProcessId;
  ok = 1;

done:
  /* The child holds its own copies; the service keeps none of the client end, or the child's exit would never reach
     the relay as the end of its pipe. */
  for (i = 0; i < 3; i++) {
    if (inh[i] != NULL)
      CloseHandle(inh[i]);
  }
  if (cli != INVALID_HANDLE_VALUE)
    CloseHandle(cli);
  if (six.lpAttributeList != NULL) {
    DeleteProcThreadAttributeList(six.lpAttributeList);
    HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
  }
  if (newenv != NULL)
    free(newenv);
  if (env != NULL)
    DestroyEnvironmentBlock(env);
  if (iosd != NULL)
    LocalFree(iosd);
  if (prim != NULL)
    CloseHandle(prim);
  if (imp != NULL)
    CloseHandle(imp);
  if (!ok)
    run_end(run);
  return ok;
}

/* ======================================================================
   Who asks                                                                 */

/* An elevated administrator, from the token of the thread that wrote the request.  who gets DOMAIN\name. */
static int runin_client_ok(HANDLE h, char* who, size_t wholen, char* why, size_t whylen) {
  HANDLE tok = NULL;
  TOKEN_ELEVATION el;
  BYTE ubuf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  BYTE ibuf[sizeof(TOKEN_MANDATORY_LABEL) + SECURITY_MAX_SID_SIZE];
  TOKEN_MANDATORY_LABEL* tml = (TOKEN_MANDATORY_LABEL*)ibuf;
  BYTE* gbuf = NULL;
  TOKEN_GROUPS* tg;
  char name[128];
  char dom[128];
  DWORD nl = sizeof(name);
  DWORD dl = sizeof(dom);
  SID_NAME_USE use;
  DWORD n = 0;
  DWORD rid;
  DWORD i;
  BOOL admin = FALSE;
  int ok = 0;

  snprintf(who, wholen, "?");
  if (ImpersonateNamedPipeClient(h)) {
    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok))
      tok = NULL;
    if (!RevertToSelf()) {
      /* Never go on as somebody else in a LocalSystem process. */
      runin_log("run.in debug: RevertToSelf failed (error %lu) - the service ends", (unsigned long)GetLastError());
      ExitProcess(1);
    }
  }
  if (tok == NULL) {
    say(why, whylen, "the asker could not be identified");
    return 0;
  }
  if (GetTokenInformation(tok, TokenUser, ubuf, sizeof(ubuf), &n) &&
      LookupAccountSidA(NULL, ((TOKEN_USER*)ubuf)->User.Sid, name, &nl, dom, &dl, &use))
    snprintf(who, wholen, "%s\\%s", dom, name);

  n = 0;
  if (!GetTokenInformation(tok, TokenElevation, &el, sizeof(el), &n) || !el.TokenIsElevated) {
    say(why, whylen, "the asker is not an elevated administrator's session");
    goto done;
  }
  n = 0;
  if (!GetTokenInformation(tok, TokenIntegrityLevel, ibuf, sizeof(ibuf), &n)) {
    say(why, whylen, "the asker's integrity could not be read");
    goto done;
  }
  rid = *GetSidSubAuthority(tml->Label.Sid, (DWORD)(*GetSidSubAuthorityCount(tml->Label.Sid) - 1));
  if (rid < SECURITY_MANDATORY_HIGH_RID) {
    say(why, whylen, "the asker is not an elevated administrator's session");
    goto done;
  }
  n = 0;
  (void)GetTokenInformation(tok, TokenGroups, NULL, 0, &n);
  if ((n == 0) || ((gbuf = (BYTE*)malloc(n)) == NULL) || !GetTokenInformation(tok, TokenGroups, gbuf, n, &n)) {
    say(why, whylen, "the asker's groups could not be read");
    goto done;
  }
  tg = (TOKEN_GROUPS*)gbuf;
  for (i = 0; i < tg->GroupCount; i++) {
    if (EqualSid(tg->Groups[i].Sid, (PSID)runin_admins_sid) && (tg->Groups[i].Attributes & SE_GROUP_ENABLED) &&
        !(tg->Groups[i].Attributes & SE_GROUP_USE_FOR_DENY_ONLY))
      admin = TRUE;
  }
  if (!admin) {
    say(why, whylen, "the asker is not an elevated administrator's session");
    goto done;
  }
  ok = 1;

done:
  if (gbuf != NULL)
    free(gbuf);
  CloseHandle(tok);
  return ok;
}

/* ======================================================================
   The pipe                                                                 */

/* One overlapped read or write on h, given ms (INFINITE allowed) to finish, and ended at once by the stop event. */
static BOOL runin_io(HANDLE h, HANDLE ev, BOOL writing, void* buf, DWORD len, DWORD* done, DWORD ms) {
  OVERLAPPED ov;
  HANDLE waits[2];
  BOOL ok;
  DWORD w;

  *done = 0;
  ZeroMemory(&ov, sizeof(ov));
  ov.hEvent = ev;
  ResetEvent(ev);
  ok = writing ? WriteFile(h, buf, len, NULL, &ov) : ReadFile(h, buf, len, NULL, &ov);
  if (!ok && (GetLastError() != ERROR_IO_PENDING))
    return FALSE;
  waits[0] = ev;
  waits[1] = runin_stop_event;
  w = WaitForMultipleObjects(2, waits, FALSE, ms);
  if (w != WAIT_OBJECT_0) {
    CancelIoEx(h, &ov);
    (void)GetOverlappedResult(h, &ov, done, TRUE);
    *done = 0;
    return FALSE;
  }
  return GetOverlappedResult(h, &ov, done, FALSE);
}

static BOOL runin_write_all(HANDLE h, HANDLE ev, const char* buf, DWORD len, DWORD ms) {
  DWORD n;

  while (len > 0) {
    if (!runin_io(h, ev, TRUE, (void*)buf, len, &n, ms) || (n == 0))
      return FALSE;
    buf += n;
    len -= n;
  }
  return TRUE;
}

static DWORD WINAPI runin_flush_thread(LPVOID arg) {
  FlushFileBuffers((HANDLE)arg);
  return 0;
}

/* The child's last screen reaches the asker before the pipe is let go: FlushFileBuffers waits until the asker has read
   everything, and is given RUNIN_FLUSH_MS to do it. */
static void runin_flush(HANDLE h) {
  HANDLE t = CreateThread(NULL, 0, runin_flush_thread, (LPVOID)h, 0, NULL);

  if (t == NULL)
    return;
  if (WaitForSingleObject(t, RUNIN_FLUSH_MS) == WAIT_TIMEOUT) {
    CancelSynchronousIo(t);
    WaitForSingleObject(t, 1000);
  }
  CloseHandle(t);
}

/* Between the asker's pipe h and the child's run->srv, until the child's end closes or the asker's does. */
static void runin_relay(HANDLE h, RUNIN_RUN* run) {
  OVERLAPPED ovc;
  OVERLAPPED ovk;
  HANDLE evc = CreateEventA(NULL, TRUE, FALSE, NULL);
  HANDLE evk = CreateEventA(NULL, TRUE, FALSE, NULL);
  HANDLE evw = CreateEventA(NULL, TRUE, FALSE, NULL);
  HANDLE waits[3];
  char cbuf[RUNIN_IO];
  char kbuf[RUNIN_IO];
  BOOL cpend = FALSE;
  BOOL kpend = FALSE;
  BOOL child_done = FALSE;
  BOOL asker_gone = FALSE;
  ULONGLONG drain_until = 0;
  DWORD n;
  DWORD nw;
  DWORD w;
  DWORD nwait;
  DWORD ms;

  if ((evc == NULL) || (evk == NULL) || (evw == NULL))
    goto out;

  while (!child_done) {
    if (!cpend) {
      ZeroMemory(&ovc, sizeof(ovc));
      ovc.hEvent = evc;
      ResetEvent(evc);
      if (!ReadFile(run->srv, cbuf, sizeof(cbuf), NULL, &ovc) && (GetLastError() != ERROR_IO_PENDING)) {
        child_done = TRUE; /* every copy of the child's end is closed: it has exited */
        break;
      }
      cpend = TRUE;
    }
    if (!asker_gone && !kpend) {
      ZeroMemory(&ovk, sizeof(ovk));
      ovk.hEvent = evk;
      ResetEvent(evk);
      if (!ReadFile(h, kbuf, sizeof(kbuf), NULL, &ovk) && (GetLastError() != ERROR_IO_PENDING)) {
        asker_gone = TRUE;
      } else {
        kpend = TRUE;
      }
      if (asker_gone) {
        TerminateJobObject(run->job, 1);
        drain_until = GetTickCount64() + RUNIN_DRAIN_MS;
      }
    }

    nwait = 0;
    waits[nwait++] = evc;
    waits[nwait++] = runin_stop_event;
    if (kpend)
      waits[nwait++] = evk;
    ms = INFINITE;
    if (asker_gone) {
      ULONGLONG now = GetTickCount64();
      ms = (now >= drain_until) ? 0 : (DWORD)(drain_until - now);
    }
    w = WaitForMultipleObjects(nwait, waits, FALSE, ms);

    if (w == WAIT_OBJECT_0) {                     /* the child wrote, or its end closed */
      cpend = FALSE;
      if (!GetOverlappedResult(run->srv, &ovc, &n, FALSE) || (n == 0)) {
        child_done = TRUE;
      } else if (!asker_gone) {
        if (!runin_write_all(h, evw, cbuf, n, RUNIN_WRITE_MS)) {
          asker_gone = TRUE;
          TerminateJobObject(run->job, 1);
          drain_until = GetTickCount64() + RUNIN_DRAIN_MS;
        }
      }
    } else if (w == WAIT_OBJECT_0 + 1) {          /* the service is stopping */
      TerminateJobObject(run->job, 1);
      break;
    } else if ((w == WAIT_OBJECT_0 + 2) && kpend) { /* the asker typed, or went */
      kpend = FALSE;
      if (!GetOverlappedResult(h, &ovk, &n, FALSE) || (n == 0)) {
        asker_gone = TRUE;
        TerminateJobObject(run->job, 1);
        drain_until = GetTickCount64() + RUNIN_DRAIN_MS;
      } else {
        (void)runin_write_all(run->srv, evw, kbuf, n, RUNIN_KEY_MS);
      }
    } else if (w == WAIT_TIMEOUT) {               /* the asker went and the child has had its time to end */
      break;
    } else {
      TerminateJobObject(run->job, 1);
      break;
    }
  }

  if (cpend) {
    CancelIoEx(run->srv, &ovc);
    (void)GetOverlappedResult(run->srv, &ovc, &nw, TRUE);
  }
  if (kpend) {
    CancelIoEx(h, &ovk);
    (void)GetOverlappedResult(h, &ovk, &nw, TRUE);
  }
  if (!asker_gone)
    runin_flush(h);

out:
  if (evc != NULL)
    CloseHandle(evc);
  if (evk != NULL)
    CloseHandle(evk);
  if (evw != NULL)
    CloseHandle(evw);
}

static void runin_answer(HANDLE h, HANDLE ev, const char* fmt, ...) {
  char line[RUNIN_LINE_MAX];
  va_list ap;
  DWORD n;
  int len;

  va_start(ap, fmt);
  len = vsnprintf(line, sizeof(line) - 1, fmt, ap);
  va_end(ap);
  if ((len < 0) || (len >= (int)sizeof(line) - 1))
    len = (int)sizeof(line) - 2;
  line[len++] = '\n';
  (void)runin_io(h, ev, TRUE, line, (DWORD)len, &n, 2000);
  /* Read before the pipe is let go: DisconnectNamedPipe throws away what the asker has not read, so a refusal would reach
     it as "ended before it answered" (measured by test-runindebug-units.py N7 before this line was here). */
  runin_flush(h);
}

static void runin_serve_one(HANDLE h, HANDLE ev) {
  char line[RUNIN_LINE_MAX + 1];
  char who[260];
  char why[400];
  char group[RUNIN_WORD_MAX + 8];
  SDRUNIN_REQ rq;
  RUNIN_RUN run;
  ULONGLONG until = GetTickCount64() + RUNIN_REQUEST_MS;
  DWORD got = 0;
  DWORD n;
  char* nl = NULL;

  memset(&run, 0, sizeof(run));
  /* The request, one line, read whole and bounded.  ImpersonateNamedPipeClient needs something read first. */
  while (got < RUNIN_LINE_MAX) {
    ULONGLONG now = GetTickCount64();

    if ((now >= until) || !runin_io(h, ev, FALSE, line + got, RUNIN_LINE_MAX - got, &n, (DWORD)(until - now)) ||
        (n == 0))
      return;
    got += n;
    line[got] = '\0';
    if ((nl = memchr(line, '\n', got)) != NULL)
      break;
  }
  if ((nl == NULL) || ((DWORD)(nl - line) + 1 != got) || (strlen(line) != got)) {
    runin_answer(h, ev, "ER the request is not one line, or more was sent before the answer");
    return;
  }
  *nl = '\0';

  if (!runin_client_ok(h, who, sizeof(who), why, sizeof(why))) {
    runin_log("run.in debug: refused %s: %s", who, why);
    runin_answer(h, ev, "ER %s", why);
    return;
  }
  if ((sdrunin_parse(line, &rq, why, sizeof(why)) != 0) ||
      (sdrunin_register(runin_sysdir, rq.account, group, sizeof(group), why, sizeof(why)) != 0)) {
    runin_log("run.in debug: refused %s: %s", who, why);
    runin_answer(h, ev, "ER %s", why);
    return;
  }
  if (!run_start(&rq, group, &run, why, sizeof(why))) {
    runin_log("run.in debug: could not start for %s, account %s: %s", who, rq.account, why);
    runin_answer(h, ev, "ER %s", why);
    return;
  }
  runin_log("run.in debug: %s debugs %s %s in account %s; the child is pid %lu as %s with %s and %s, store %s", who,
            rq.file, rq.program, rq.account, (unsigned long)run.pid, SD_RUNIN_ACCOUNT, RUNIN_USERS_GROUP, group,
            run.store);
  runin_answer(h, ev, "OK %lu\t%s", (unsigned long)run.pid, run.store);
  runin_relay(h, &run);
  run_end(&run);
}

static DWORD WINAPI runin_thread(LPVOID arg) {
  int slot = (int)(INT_PTR)arg;
  HANDLE h = runin_pipes[slot];
  HANDLE ev;
  HANDLE waits[2];
  OVERLAPPED ov;
  DWORD n;
  DWORD w;
  BOOL connected;

  if ((ev = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL)
    return 1;
  waits[0] = ev;
  waits[1] = runin_stop_event;

  while (WaitForSingleObject(runin_stop_event, 0) != WAIT_OBJECT_0) {
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
          w = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
          if (w == WAIT_OBJECT_0) {
            connected = GetOverlappedResult(h, &ov, &n, FALSE);
          } else {
            CancelIoEx(h, &ov);
            (void)GetOverlappedResult(h, &ov, &n, TRUE);
          }
          break;
        case ERROR_NO_DATA:
          break;
        default:
          Sleep(100);
          break;
      }
    }
    if (connected && (WaitForSingleObject(runin_stop_event, 0) != WAIT_OBJECT_0))
      runin_serve_one(h, ev);
    DisconnectNamedPipe(h);
  }
  CloseHandle(ev);
  return 0;
}

/* ======================================================================
   Starting and stopping                                                    */

static void runin_release(void) {
  int i;

  for (i = 0; i < RUNIN_INSTANCES; i++) {
    if ((runin_pipes[i] != NULL) && (runin_pipes[i] != INVALID_HANDLE_VALUE))
      CloseHandle(runin_pipes[i]);
    runin_pipes[i] = NULL;
  }
  if (runin_stop_event != NULL)
    CloseHandle(runin_stop_event);
  runin_stop_event = NULL;
  if (runin_pipe_sd != NULL)
    LocalFree(runin_pipe_sd);
  if (runin_pipe_acl != NULL)
    LocalFree(runin_pipe_acl);
  runin_pipe_sd = NULL;
  runin_pipe_acl = NULL;
  DeleteCriticalSection(&runin_cs);
}

int sdrunin_start(const char* pipe_name, const char* sysdir, const char* store_base, const char* sd_exe,
                  sdrunin_log_fn log) {
  EXPLICIT_ACCESSA ea[2];
  SECURITY_ATTRIBUTES sa;
  char why[400];
  int i;

  runin_log = (log != NULL) ? log : runin_nolog;
  if (runin_running)
    return 0;
  if ((pipe_name == NULL) || (sysdir == NULL) || (store_base == NULL) || (sd_exe == NULL) ||
      (strlen(pipe_name) >= sizeof(runin_pipe_name)) || (strlen(sysdir) >= sizeof(runin_sysdir) - 80) ||
      (strlen(store_base) >= sizeof(runin_base) - 40) || (strlen(sd_exe) >= sizeof(runin_sd_exe))) {
    runin_log("run.in debug: not started - no pipe name, system directory, store or sd.exe");
    return -1;
  }
  strcpy(runin_pipe_name, pipe_name);
  strcpy(runin_sysdir, sysdir);
  strcpy(runin_base, store_base);
  strcpy(runin_sd_exe, sd_exe);
  InitializeCriticalSection(&runin_cs);
  ZeroMemory(runin_pipes, sizeof(runin_pipes));
  runin_nthreads = 0;

  if (!runin_well_known_sids()) {
    runin_log("run.in debug: not started - the well-known SIDs could not be made");
    runin_release();
    return -1;
  }
  /* The store's base is made (or put right) now, so that the first run does not find somebody else's. */
  if (store_base_ready(runin_base, why, sizeof(why)) != 0) {
    runin_log("run.in debug: not started - %s", why);
    runin_release();
    return -1;
  }

  /* The pipe: this process's own user all (LocalSystem - and the only one that may make another instance of the name),
     Administrators read and write.  Nobody else is in it. */
  ZeroMemory(ea, sizeof(ea));
  ea[0].grfAccessPermissions = FILE_ALL_ACCESS;
  ea[0].Trustee.ptstrName = (LPSTR)runin_own_sid;
  ea[1].grfAccessPermissions = RUNIN_PIPE_GRANT;
  ea[1].Trustee.ptstrName = (LPSTR)runin_admins_sid;
  for (i = 0; i < 2; i++) {
    ea[i].grfAccessMode = SET_ACCESS;
    ea[i].grfInheritance = NO_INHERITANCE;
    ea[i].Trustee.TrusteeForm = TRUSTEE_IS_SID;
    ea[i].Trustee.TrusteeType = TRUSTEE_IS_UNKNOWN;
  }
  runin_pipe_sd = LocalAlloc(LPTR, SECURITY_DESCRIPTOR_MIN_LENGTH);
  if ((SetEntriesInAclA(2, ea, NULL, &runin_pipe_acl) != ERROR_SUCCESS) || (runin_pipe_sd == NULL) ||
      !InitializeSecurityDescriptor(runin_pipe_sd, SECURITY_DESCRIPTOR_REVISION) ||
      !SetSecurityDescriptorDacl(runin_pipe_sd, TRUE, runin_pipe_acl, FALSE) ||
      !SetSecurityDescriptorControl(runin_pipe_sd, SE_DACL_PROTECTED, SE_DACL_PROTECTED) ||
      !SetSecurityDescriptorOwner(runin_pipe_sd, (PSID)runin_own_sid, FALSE)) {
    runin_log("run.in debug: not started - the pipe's security descriptor could not be built (error %lu)",
              (unsigned long)GetLastError());
    runin_release();
    return -1;
  }
  if ((runin_stop_event = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL) {
    runin_release();
    return -1;
  }
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = runin_pipe_sd;
  sa.bInheritHandle = FALSE;
  for (i = 0; i < RUNIN_INSTANCES; i++) {
    runin_pipes[i] = CreateNamedPipeA(runin_pipe_name,
                                      PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | ((i == 0) ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0),
                                      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                                      RUNIN_INSTANCES, 65536, 4096, 0, &sa);
    if (runin_pipes[i] == INVALID_HANDLE_VALUE) {
      runin_log("run.in debug: not started - %s could not be made (error %lu%s)", runin_pipe_name,
                (unsigned long)GetLastError(), (i == 0) ? "; another process may hold the name" : "");
      runin_pipes[i] = NULL;
      runin_release();
      return -1;
    }
  }
  for (i = 0; i < RUNIN_INSTANCES; i++) {
    runin_threads[i] = CreateThread(NULL, 0, runin_thread, (LPVOID)(INT_PTR)i, 0, NULL);
    if (runin_threads[i] == NULL)
      break;
    runin_nthreads++;
  }
  if (runin_nthreads == 0) {
    runin_release();
    return -1;
  }
  runin_running = TRUE;
  runin_log("run.in debug: serving %s with %d instance(s); the child is %s as %s, stores under %s", runin_pipe_name,
            runin_nthreads, runin_sd_exe, SD_RUNIN_ACCOUNT, runin_base);
  return 0;
}

void sdrunin_stop(void) {
  int i;

  if (!runin_running)
    return;
  SetEvent(runin_stop_event);
  if (WaitForMultipleObjects((DWORD)runin_nthreads, runin_threads, TRUE, RUNIN_STOP_MS) == WAIT_TIMEOUT)
    runin_log("run.in debug: a serving thread did not end in %d seconds", RUNIN_STOP_MS / 1000);
  for (i = 0; i < runin_nthreads; i++)
    CloseHandle(runin_threads[i]);
  runin_nthreads = 0;
  runin_running = FALSE;
  runin_release();
  runin_log("run.in debug: stopped");
}

/* END-CODE */
