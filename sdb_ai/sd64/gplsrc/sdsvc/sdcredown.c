/* sdcredown.c - cred-own in the SD service: a person changes their own SD password
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
 * 21 Nov 26 Windows port - written.  RELEASE_1.1 379, the Windows form of Linux's "sudo sd-elevate cred-own" (gplbld/sd-elevate
 *           cred_own(), d147a5c), agreed with the Linux audit session (mail 2026-11-22T1900).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY THE SERVICE.  $cred is SYSTEM and Administrators only, so an unelevated session can neither read nor write its own record,
 * and a standard Windows user could never change its own SD password.  Linux lets every SD user run one root helper on ONE record,
 * the caller's; the SD service is the LocalSystem process SD already has, so it serves that door here (../win32credown.h has the
 * wire).  The Linux audit session's conditions a-e (mail 2026-11-22T1900, d corrected in T0320), which are this file's rules:
 *
 *   a. WHO is the token's.  The account is the Windows user of the thread that opened the pipe (ImpersonateNamedPipeClient at
 *      identification level, then RevertToSelf; a revert that fails ends the service), lower case.  Nothing in the request names
 *      an account.  sdsys is refused: it sets passwords as the administrator, with MODIFY.PASSWORD in its own elevated session.
 *   b. PROOF.  When the record holds a credential, the caller must send its exact stored key: it cannot read $cred, so arriving
 *      with it proves the password.  Checked at the write itself (verify is only the early answer), compared in constant time,
 *      and the record is read back after the write.
 *   c. ONE RECORD.  Only <sysdir>\$cred\<account>, and only for an account whose register record is a plain file, not
 *      SUSPENDED, whose group is sdu_<account> (a person's own account, as Linux's register check).
 *   d. AUDIT.  The service writes the lines (sdaudit_write), lower case before each "=": "cred-own set account=<a>" and
 *      "cred-own refused account=<a> mode=<m> reason=<why>".  A query that only answers is not audited.  NOT LINUX'S (Linux's
 *      correction, mail 2026-11-22T0320, of its T1900 condition d): Linux's cred_own() writes one SYSLOG line on a successful set
 *      and nothing to SD's audit trail, and a refusal only to stderr.  This is a difference from the template, the stricter
 *      one, made on that wrong word and flagged in the parity audit; Linux row S.298 is open to gain the same lines.
 *   e. DELIVERED ON, as Linux's: it changes nothing but the caller's own password, after proving the current one.
 *
 * WHO MAY OPEN THE PIPE.  The server's own user, Administrators, and the grants (sdusers in the service), each with read, write and
 * read-attributes only (never FILE_CREATE_PIPE_INSTANCE, WRITE_DAC or WRITE_OWNER); no remote client.  The pipe is owned by the
 * server's user, LocalSystem in the service, which is what the session checks before it sends a key.  One instance, one request at
 * a time: a password change is rare, and a request must arrive within CREDOWN_REQUEST_MS.
 *
 * Everything that arrives is input from any member of sdusers, in a LocalSystem process: the buffers are fixed and bounded, every
 * line is checked as Linux's helper checks it (lengths, record version, mechanism, base64 sizes, iteration range).
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include "../win32credown.h"
#include "sdcredown.h"

#define CREDOWN_REQUEST_MS 10000 /* the whole request must arrive within this */
#define CREDOWN_WRITE_MS 5000
#define CREDOWN_LINGER_MS 3000   /* the client reads its answer and closes */
#define CREDOWN_STOP_MS 8000
#define CREDOWN_FILE_MAX 65536   /* a register or $cred record bigger than this is not one */
#define CREDOWN_NAME_MAX 64

/* What a granted account may do to the pipe.  Not FILE_CREATE_PIPE_INSTANCE, WRITE_DAC or WRITE_OWNER. */
#define CREDOWN_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)

static BOOL cr_running = FALSE;
static HANDLE cr_stop_event = NULL;
static HANDLE cr_thread = NULL;
static HANDLE cr_pipe = INVALID_HANDLE_VALUE;
static PSECURITY_DESCRIPTOR cr_pipe_sd = NULL;
static char cr_pipe_name[MAX_PATH];
static char cr_sysdir[MAX_PATH];
static sdcredown_audit_fn cr_audit = NULL;
static sdcredown_log_fn cr_log = NULL;
static unsigned long cr_set = 0;
static unsigned long cr_refused = 0;

static void cr_nolog(const char* fmt, ...) {
  (void)fmt;
}

static void say(char* out, size_t outlen, const char* fmt, ...) {
  va_list ap;

  if ((out == NULL) || (outlen == 0))
    return;
  va_start(ap, fmt);
  vsnprintf(out, outlen, fmt, ap);
  va_end(ap);
}

/* ======================================================================
   Words and keys                                                          */

int sdcredown_account(const char* user_name, char* out, size_t outlen) {
  size_t n;
  size_t i;
  char c;

  if ((user_name == NULL) || (out == NULL) || ((n = strlen(user_name)) == 0) || (n > CREDOWN_NAME_MAX) || (n + 1 > outlen) ||
      (user_name[0] == '.'))
    return -1;
  for (i = 0; i < n; i++) {
    c = user_name[i];
    if ((c >= 'A') && (c <= 'Z'))
      c = (char)(c - 'A' + 'a'); /* English only: ASCII folding, no locale */
    if (!(((c >= 'a') && (c <= 'z')) || ((c >= '0') && (c <= '9')) || (c == '.') || (c == '_') || (c == '-')))
      return -1;
    out[i] = c;
  }
  out[n] = '\0';
  return 0;
}

/* Base64 of between min and max bytes, as sd-elevate's cred_b64. */
static BOOL cr_b64(const char* s, size_t min, size_t max) {
  size_t n = strlen(s);
  size_t i;
  size_t pad = 0;
  size_t bytes;

  if ((n == 0) || (n % 4 != 0))
    return FALSE;
  for (i = 0; i < n; i++) {
    char c = s[i];
    if (c == '=') {
      if (i < n - 2)
        return FALSE; /* padding only at the end */
      pad++;
      continue;
    }
    if (pad != 0)
      return FALSE; /* nothing after padding */
    if (!(((c >= 'A') && (c <= 'Z')) || ((c >= 'a') && (c <= 'z')) || ((c >= '0') && (c <= '9')) || (c == '+') || (c == '/')))
      return FALSE;
  }
  bytes = (n / 4) * 3 - pad;
  return (bytes >= min) && (bytes <= max);
}

/* Equal in time that does not depend on where they differ. */
static BOOL cr_same(const char* a, const char* b) {
  size_t na = strlen(a);
  size_t nb = strlen(b);
  size_t i;
  unsigned char d = (unsigned char)(na != nb);

  for (i = 0; i < na; i++)
    d |= (unsigned char)(a[i] ^ ((i < nb) ? b[i] : 0));
  return d == 0;
}

/* ======================================================================
   Records                                                                 */

/* A record file read whole: a plain file (not a link or a directory) of at most CREDOWN_FILE_MAX bytes.  1 read, 0 not there,
   -1 there but not a plain file or unreadable. */
static int cr_read_file(const char* path, char* buf, size_t buflen) {
  HANDLE h;
  BY_HANDLE_FILE_INFORMATION info;
  DWORD n = 0;
  int rc = -1;

  buf[0] = '\0';
  h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    DWORD e = GetLastError();
    return ((e == ERROR_FILE_NOT_FOUND) || (e == ERROR_PATH_NOT_FOUND)) ? 0 : -1;
  }
  if (GetFileInformationByHandle(h, &info) &&
      !(info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) && (info.nFileSizeHigh == 0) &&
      (info.nFileSizeLow < buflen) && ReadFile(h, buf, info.nFileSizeLow, &n, NULL) && (n == info.nFileSizeLow)) {
    buf[n] = '\0';
    rc = 1;
  }
  CloseHandle(h);
  return rc;
}

/* Line n (1-based) of a record: a field mark or a line feed ends a field, a CR is dropped, the first value only (as sdrunin.c's
   register_field and the session's directory-file reading). */
static void cr_field(const char* rec, int n, char* out, size_t outlen) {
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

/* ======================================================================
   One request                                                             */

int sdcredown_handle(const char* sysdir, const char* account, const char* request, char* answer, size_t alen, char* audit_msg,
                     size_t amlen) {
  static char rec[CREDOWN_FILE_MAX];
  char req[CREDOWN_REQUEST_MAX + 1];
  char* line[12];
  int nl = 0;
  char mode[16] = "?";
  char path[MAX_PATH];
  char cdir[MAX_PATH];
  char cfile[MAX_PATH];
  char tmp[MAX_PATH];
  char group[CREDOWN_NAME_MAX + 16];
  char want[CREDOWN_NAME_MAX + 8];
  char field[CREDOWN_LINE_MAX + 2];
  char old_ver[16] = "";
  char old_sk[CREDOWN_LINE_MAX + 2] = "";
  char old_salt[CREDOWN_LINE_MAX + 2] = "";
  char old_iter[CREDOWN_LINE_MAX + 2] = "";
  char why[256] = "";
  char data[8 * (CREDOWN_LINE_MAX + 2)];
  const char* cur;
  const char* ver;
  const char* mech;
  const char* salt;
  const char* iter;
  const char* sk;
  const char* svk;
  char* p;
  int i;
  int got;
  int has_cred;
  DWORD attr;
  HANDLE h;
  DWORD w = 0;
  long it;
  BOOL ok;

  say(answer, alen, "ER the request could not be read");
  say(audit_msg, amlen, "");
  if ((sysdir == NULL) || (account == NULL) || (request == NULL) || (strlen(request) > CREDOWN_REQUEST_MAX))
    goto refuse;

  /* The lines: "SDCREDOWN1 <mode>", the data lines, "END". */
  strcpy(req, request);
  for (p = req; (p != NULL) && (*p != '\0') && (nl < (int)(sizeof(line) / sizeof(line[0]))); nl++) {
    line[nl] = p;
    if ((p = strchr(p, '\n')) != NULL)
      *(p++) = '\0';
    if ((i = (int)strlen(line[nl])) > 0 && (line[nl][i - 1] == '\r'))
      line[nl][i - 1] = '\0';
  }
  if ((p != NULL) && (*p != '\0')) {
    say(why, sizeof(why), "the request has too many lines");
    goto refuse;
  }
  if ((nl < 2) || (strncmp(line[0], CREDOWN_MAGIC, strlen(CREDOWN_MAGIC)) != 0) || (strcmp(line[nl - 1], "END") != 0)) {
    say(why, sizeof(why), "the request is not a cred-own request");
    goto refuse;
  }
  snprintf(mode, sizeof(mode), "%.15s", line[0] + strlen(CREDOWN_MAGIC));
  if ((strcmp(mode, "query") != 0) && (strcmp(mode, "verify") != 0) && (strcmp(mode, "set") != 0)) {
    say(why, sizeof(why), "cred-own takes query, verify or set");
    snprintf(mode, sizeof(mode), "?");
    goto refuse;
  }
  for (i = 1; i < nl - 1; i++) {
    if (strlen(line[i]) > CREDOWN_LINE_MAX) {
      say(why, sizeof(why), "an input line is over %d characters", CREDOWN_LINE_MAX);
      goto refuse;
    }
  }

  /* a. WHO: the token's account, never the request's.  sdsys is the administrator's own path. */
  if (strcmp(account, "sdsys") == 0) {
    say(why, sizeof(why), "sdsys sets passwords as the administrator (MODIFY.PASSWORD), not here");
    goto refuse;
  }

  /* c. ONE RECORD, of a person's own registered account. */
  if (snprintf(path, sizeof(path), "%s\\accounts\\%s", sysdir, account) >= (int)sizeof(path)) {
    say(why, sizeof(why), "no register record can be named for %s", account);
    goto refuse;
  }
  if ((got = cr_read_file(path, rec, sizeof(rec))) != 1) {
    say(why, sizeof(why), (got == 0) ? "'%s' is not in the SD account register" : "the register record of %s is not a plain file",
        account);
    goto refuse;
  }
  cr_field(rec, 5, field, sizeof(field)); /* ACC$SUSPENDED */
  if (_stricmp(field, "SUSPENDED") == 0) {
    say(why, sizeof(why), "account '%s' is suspended", account);
    goto refuse;
  }
  cr_field(rec, 3, group, sizeof(group)); /* ACC$GROUP */
  snprintf(want, sizeof(want), "sdu_%s", account);
  if (_stricmp(group, want) != 0) {
    say(why, sizeof(why), "'%s' is not a user's own account (register group is not %s)", account, want);
    goto refuse;
  }

  snprintf(cdir, sizeof(cdir), "%s\\$cred", sysdir);
  attr = GetFileAttributesA(cdir);
  if ((attr == INVALID_FILE_ATTRIBUTES) || !(attr & FILE_ATTRIBUTE_DIRECTORY) || (attr & FILE_ATTRIBUTE_REPARSE_POINT)) {
    say(why, sizeof(why), "the credential register does not exist");
    goto refuse;
  }
  if (snprintf(cfile, sizeof(cfile), "%s\\%s", cdir, account) >= (int)sizeof(cfile)) {
    say(why, sizeof(why), "no credential record can be named for %s", account);
    goto refuse;
  }
  if ((got = cr_read_file(cfile, rec, sizeof(rec))) < 0) {
    say(why, sizeof(why), "the credential record of %s is not a plain file", account);
    goto refuse;
  }
  if (got == 1) {
    cr_field(rec, 1, old_ver, sizeof(old_ver));
    cr_field(rec, 3, old_salt, sizeof(old_salt));
    cr_field(rec, 4, old_iter, sizeof(old_iter));
    cr_field(rec, 5, old_sk, sizeof(old_sk));
  }
  has_cred = (strcmp(old_ver, "2") == 0) && (old_sk[0] != '\0');
  SecureZeroMemory(rec, sizeof(rec));

  if (strcmp(mode, "query") == 0) {
    /* Salt and iterations are not secret: SCRAM sends both to any client. */
    if (nl != 2) {
      say(why, sizeof(why), "query takes no lines");
      goto refuse;
    }
    if (has_cred)
      say(answer, alen, "OK salt %s iter %s", old_salt, old_iter);
    else
      say(answer, alen, "OK none");
    SecureZeroMemory(old_sk, sizeof(old_sk));
    SecureZeroMemory(req, sizeof(req));
    return 0;
  }

  if (strcmp(mode, "verify") == 0) {
    if (nl != 3) {
      say(why, sizeof(why), "verify wants exactly one line");
      goto refuse;
    }
    if (!has_cred) {
      say(why, sizeof(why), "'%s' has no SD password to check against", account);
      goto refuse;
    }
    if ((line[1][0] == '\0') || !cr_same(line[1], old_sk)) {
      say(why, sizeof(why), "the current password is not correct");
      goto refuse;
    }
    say(answer, alen, "OK the current password is correct");
    SecureZeroMemory(old_sk, sizeof(old_sk));
    SecureZeroMemory(req, sizeof(req));
    return 0;
  }

  /* set: current stored key, version, mechanism, salt, iterations, stored key, server key. */
  if (nl != 9) {
    say(why, sizeof(why), "set wants exactly seven lines");
    goto refuse;
  }
  cur = line[1];
  ver = line[2];
  mech = line[3];
  salt = line[4];
  iter = line[5];
  sk = line[6];
  svk = line[7];
  if (strcmp(ver, "2") != 0) {
    say(why, sizeof(why), "record version must be 2");
    goto refuse;
  }
  if (strcmp(mech, "SCRAM-SHA-256") != 0) {
    say(why, sizeof(why), "mechanism must be SCRAM-SHA-256");
    goto refuse;
  }
  if (!cr_b64(salt, 8, 64)) {
    say(why, sizeof(why), "the salt is not base64 of 8-64 bytes");
    goto refuse;
  }
  for (i = 0; iter[i] != '\0'; i++) {
    if ((iter[i] < '0') || (iter[i] > '9'))
      break;
  }
  it = (iter[i] == '\0') ? strtol(iter, NULL, 10) : -1;
  if ((i < 4) || (i > 8) || (it < 4096) || (it > 10000000)) {
    say(why, sizeof(why), "iterations are outside 4096-10000000");
    goto refuse;
  }
  if (!cr_b64(sk, 32, 32)) {
    say(why, sizeof(why), "StoredKey is not base64 of 32 bytes");
    goto refuse;
  }
  if (!cr_b64(svk, 32, 32)) {
    say(why, sizeof(why), "ServerKey is not base64 of 32 bytes");
    goto refuse;
  }

  /* b. PROOF at the write. */
  if (has_cred) {
    if (cur[0] == '\0') {
      say(why, sizeof(why), "'%s' has a password; the current one is required", account);
      goto refuse;
    }
    if (!cr_same(cur, old_sk)) {
      say(why, sizeof(why), "the current password is not correct");
      goto refuse;
    }
  }
  SecureZeroMemory(old_sk, sizeof(old_sk));

  /* Through a new file in $cred (it takes $cred's inherited DACL) and a rename over the record; then read back. */
  snprintf(data, sizeof(data), "%s\r\n%s\r\n%s\r\n%s\r\n%s\r\n%s\r\n", ver, mech, salt, iter, sk, svk);
  if (snprintf(tmp, sizeof(tmp), "%s\\.cred-own.%lu.%llu", cdir, (unsigned long)GetCurrentThreadId(),
               (unsigned long long)GetTickCount64()) >= (int)sizeof(tmp)) {
    say(why, sizeof(why), "no temporary record can be named");
    goto refuse;
  }
  h = CreateFileA(tmp, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    say(why, sizeof(why), "a temporary record could not be made in the credential register (error %lu)",
        (unsigned long)GetLastError());
    goto refuse;
  }
  ok = WriteFile(h, data, (DWORD)strlen(data), &w, NULL) && (w == (DWORD)strlen(data)) && FlushFileBuffers(h);
  CloseHandle(h);
  SecureZeroMemory(data, sizeof(data));
  if (!ok || !MoveFileExA(tmp, cfile, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileA(tmp);
    say(why, sizeof(why), "writing the credential record of %s failed", account);
    goto refuse;
  }
  if (cr_read_file(cfile, rec, sizeof(rec)) != 1) {
    say(why, sizeof(why), "the record did not read back as written");
    goto refuse;
  }
  cr_field(rec, 5, field, sizeof(field));
  ok = cr_same(field, sk);
  cr_field(rec, 6, field, sizeof(field));
  ok = ok && cr_same(field, svk);
  SecureZeroMemory(rec, sizeof(rec));
  SecureZeroMemory(field, sizeof(field));
  SecureZeroMemory(req, sizeof(req));
  if (!ok) {
    say(why, sizeof(why), "the record did not read back as written");
    goto refuse;
  }
  say(answer, alen, "OK SD password set for %s", account);
  say(audit_msg, amlen, "cred-own set account=%s", account);
  return 0;

refuse:
  SecureZeroMemory(req, sizeof(req));
  SecureZeroMemory(rec, sizeof(rec));
  SecureZeroMemory(old_sk, sizeof(old_sk));
  SecureZeroMemory(data, sizeof(data));
  if (why[0] == '\0')
    say(why, sizeof(why), "the request could not be read");
  say(answer, alen, "ER %s", why);
  say(audit_msg, amlen, "cred-own refused account=%s mode=%s reason=%s", (account != NULL) ? account : "?", mode, why);
  return -1;
}

/* ======================================================================
   The pipe                                                                */

static BOOL cr_io(HANDLE h, HANDLE ev, BOOL writing, void* buf, DWORD len, DWORD* done, DWORD ms) {
  OVERLAPPED ov;
  HANDLE wait[2];
  BOOL ok;

  *done = 0;
  ZeroMemory(&ov, sizeof(ov));
  ov.hEvent = ev;
  ResetEvent(ev);
  ok = writing ? WriteFile(h, buf, len, NULL, &ov) : ReadFile(h, buf, len, NULL, &ov);
  if (!ok && (GetLastError() != ERROR_IO_PENDING))
    return FALSE;
  wait[0] = ev;
  wait[1] = cr_stop_event;
  if (WaitForMultipleObjects(2, wait, FALSE, ms) != WAIT_OBJECT_0) {
    CancelIoEx(h, &ov);
    (void)GetOverlappedResult(h, &ov, done, TRUE);
    *done = 0;
    return FALSE;
  }
  return GetOverlappedResult(h, &ov, done, FALSE);
}

/* The caller's DOMAIN\name (for the audit line) and its account (from the name), from the token the client opened the pipe
   with.  FALSE when it cannot be had. */
static BOOL cr_client(HANDLE h, char* user, size_t userlen, char* account, size_t acclen) {
  HANDLE tok = NULL;
  BYTE buf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  DWORD n = 0;
  char name[256];
  char dom[256];
  DWORD nl = sizeof(name);
  DWORD dl = sizeof(dom);
  SID_NAME_USE use;
  char* p;

  if (!ImpersonateNamedPipeClient(h))
    return FALSE;
  if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok))
    tok = NULL;
  if (!RevertToSelf()) {
    /* Never go on as somebody else in a LocalSystem process. */
    cr_log("cred-own: RevertToSelf failed (error %lu) - the service ends", (unsigned long)GetLastError());
    ExitProcess(1);
  }
  if (tok == NULL)
    return FALSE;
  if (!GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &n) ||
      !LookupAccountSidA(NULL, ((TOKEN_USER*)buf)->User.Sid, name, &nl, dom, &dl, &use) || (use != SidTypeUser)) {
    CloseHandle(tok);
    return FALSE;
  }
  CloseHandle(tok);
  snprintf(user, userlen, "%s%s%s", dom, (dom[0] != '\0') ? "\\" : "", name);
  for (p = user; *p != '\0'; p++) { /* one token on the audit line */
    if (!(((*p >= 'A') && (*p <= 'Z')) || ((*p >= 'a') && (*p <= 'z')) || ((*p >= '0') && (*p <= '9')) || (*p == '.') ||
          (*p == '_') || (*p == '-') || (*p == '\\') || (*p == '$')))
      *p = '?';
  }
  return sdcredown_account(name, account, acclen) == 0;
}

static void cr_serve_one(HANDLE h, HANDLE ev) {
  char req[CREDOWN_REQUEST_MAX + 1];
  char answer[CREDOWN_ANSWER_MAX];
  char audit_msg[512];
  char user[600] = "?";
  char account[CREDOWN_NAME_MAX + 1] = "";
  DWORD got = 0;
  DWORD done = 0;
  DWORD pid = 0;
  ULONGLONG until = GetTickCount64() + CREDOWN_REQUEST_MS;
  BOOL whole = FALSE;
  int len;

  (void)GetNamedPipeClientProcessId(h, &pid);
  req[0] = '\0';
  while ((got < CREDOWN_REQUEST_MAX) && (GetTickCount64() < until)) {
    if (!cr_io(h, ev, FALSE, req + got, (DWORD)(CREDOWN_REQUEST_MAX - got), &done,
               (DWORD)(until - GetTickCount64() + 1)) ||
        (done == 0))
      break;
    got += done;
    req[got] = '\0';
    if ((got >= 4) && (strcmp(req + got - 4, "END\n") == 0) && ((got == 4) || (req[got - 5] == '\n'))) {
      whole = TRUE;
      break;
    }
  }

  if (!whole) {
    snprintf(answer, sizeof(answer), "ER the request did not arrive whole");
    snprintf(audit_msg, sizeof(audit_msg), "cred-own refused account=? mode=? reason=the request did not arrive whole");
  } else if (!cr_client(h, user, sizeof(user), account, sizeof(account))) {
    snprintf(answer, sizeof(answer), "ER the caller's Windows user could not be named");
    snprintf(audit_msg, sizeof(audit_msg), "cred-own refused account=? mode=? reason=the caller's Windows user could not be named");
  } else {
    (void)sdcredown_handle(cr_sysdir, account, req, answer, sizeof(answer), audit_msg, sizeof(audit_msg));
  }
  SecureZeroMemory(req, sizeof(req));

  if (strncmp(answer, "OK SD password set", 18) == 0)
    cr_set++;
  else if (strncmp(answer, "ER", 2) == 0)
    cr_refused++;
  if ((audit_msg[0] != '\0') && (cr_audit != NULL) && (cr_audit(user, (unsigned long)pid, audit_msg) != 0))
    cr_log("cred-own: the audit line could not be written: user=%s pid=%lu %s", user, (unsigned long)pid, audit_msg);

  len = (int)strlen(answer);
  answer[len++] = '\n';
  (void)cr_io(h, ev, TRUE, answer, (DWORD)len, &done, CREDOWN_WRITE_MS);
  /* Let the client read it and close (a read that ends when it does), then let it go. */
  (void)cr_io(h, ev, FALSE, req, 1, &done, CREDOWN_LINGER_MS);
}

static DWORD WINAPI cr_thread_main(LPVOID arg) {
  HANDLE ev;
  HANDLE wait[2];
  OVERLAPPED ov;
  BOOL connected;
  DWORD w;

  (void)arg;
  if ((ev = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL)
    return 1;
  for (;;) {
    ZeroMemory(&ov, sizeof(ov));
    ov.hEvent = ev;
    ResetEvent(ev);
    connected = ConnectNamedPipe(cr_pipe, &ov);
    if (!connected) {
      DWORD e = GetLastError();
      if (e == ERROR_PIPE_CONNECTED) {
        connected = TRUE;
      } else if (e == ERROR_IO_PENDING) {
        wait[0] = ev;
        wait[1] = cr_stop_event;
        w = WaitForMultipleObjects(2, wait, FALSE, INFINITE);
        if (w != WAIT_OBJECT_0) {
          CancelIoEx(cr_pipe, &ov);
          break; /* stopping */
        }
        connected = GetOverlappedResult(cr_pipe, &ov, &w, FALSE);
      }
    }
    if (WaitForSingleObject(cr_stop_event, 0) == WAIT_OBJECT_0)
      break;
    if (connected)
      cr_serve_one(cr_pipe, ev);
    DisconnectNamedPipe(cr_pipe);
  }
  CloseHandle(ev);
  return 0;
}

/* The pipe's descriptor: owned by this process's user, which alone has full control; Administrators and each grant read, write
   and read attributes.  Protected (no inherited ACE).  NULL when it cannot be made. */
static PSECURITY_DESCRIPTOR cr_make_sd(const char* const* grant) {
  HANDLE tok = NULL;
  BYTE buf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  DWORD n = 0;
  char* own = NULL;
  char sddl[2048];
  size_t used;
  PSECURITY_DESCRIPTOR sd = NULL;
  int i;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
    return NULL;
  if (!GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &n) || !ConvertSidToStringSidA(((TOKEN_USER*)buf)->User.Sid, &own)) {
    CloseHandle(tok);
    return NULL;
  }
  CloseHandle(tok);
  used = (size_t)snprintf(sddl, sizeof(sddl), "O:%sD:P(A;;GA;;;%s)(A;;0x%lx;;;BA)", own, own, (unsigned long)CREDOWN_PIPE_GRANT);
  LocalFree(own);
  for (i = 0; (grant != NULL) && (grant[i] != NULL); i++) {
    BYTE sid[SECURITY_MAX_SID_SIZE];
    char dom[256];
    DWORD sl = sizeof(sid);
    DWORD dl = sizeof(dom);
    SID_NAME_USE use;
    char* text = NULL;

    if (!LookupAccountNameA(NULL, grant[i], sid, &sl, dom, &dl, &use) || !ConvertSidToStringSidA((PSID)sid, &text)) {
      cr_log("cred-own: the account %s could not be found; it is not granted the pipe", grant[i]);
      continue;
    }
    used += (size_t)snprintf(sddl + used, (used < sizeof(sddl)) ? sizeof(sddl) - used : 0, "(A;;0x%lx;;;%s)",
                             (unsigned long)CREDOWN_PIPE_GRANT, text);
    LocalFree(text);
  }
  if (used >= sizeof(sddl))
    return NULL;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(sddl, SDDL_REVISION_1, &sd, NULL))
    return NULL;
  return sd;
}

int sdcredown_start(const char* pipe_name, const char* sysdir, const char* const* grant, sdcredown_audit_fn audit,
                    sdcredown_log_fn log) {
  SECURITY_ATTRIBUTES sa;

  cr_log = (log != NULL) ? log : cr_nolog;
  if (cr_running)
    return 0;
  if ((pipe_name == NULL) || (sysdir == NULL) || (strlen(pipe_name) >= sizeof(cr_pipe_name)) ||
      (strlen(sysdir) >= sizeof(cr_sysdir))) {
    cr_log("cred-own: not started - no pipe name or system directory");
    return -1;
  }
  strcpy(cr_pipe_name, pipe_name);
  strcpy(cr_sysdir, sysdir);
  cr_audit = audit;

  if ((cr_pipe_sd = cr_make_sd(grant)) == NULL) {
    cr_log("cred-own: not started - the pipe's security descriptor could not be made (error %lu)", (unsigned long)GetLastError());
    return -1;
  }
  ZeroMemory(&sa, sizeof(sa));
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = cr_pipe_sd;
  sa.bInheritHandle = FALSE;
  /* FIRST_PIPE_INSTANCE: a name somebody made first is refused, never shared. */
  cr_pipe = CreateNamedPipeA(cr_pipe_name, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                             PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1,
                             CREDOWN_ANSWER_MAX, CREDOWN_REQUEST_MAX, 0, &sa);
  if (cr_pipe == INVALID_HANDLE_VALUE) {
    cr_log("cred-own: not started - %s could not be made (error %lu; another process may hold the name)", cr_pipe_name,
           (unsigned long)GetLastError());
    LocalFree(cr_pipe_sd);
    cr_pipe_sd = NULL;
    return -1;
  }
  if (((cr_stop_event = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL) ||
      ((cr_thread = CreateThread(NULL, 0, cr_thread_main, NULL, 0, NULL)) == NULL)) {
    cr_log("cred-own: not started - no thread (error %lu)", (unsigned long)GetLastError());
    if (cr_stop_event != NULL)
      CloseHandle(cr_stop_event);
    cr_stop_event = NULL;
    CloseHandle(cr_pipe);
    cr_pipe = INVALID_HANDLE_VALUE;
    LocalFree(cr_pipe_sd);
    cr_pipe_sd = NULL;
    return -1;
  }
  cr_running = TRUE;
  cr_log("cred-own: serving %s over %s\\$cred", cr_pipe_name, cr_sysdir);
  return 0;
}

void sdcredown_stop(void) {
  if (!cr_running)
    return;
  SetEvent(cr_stop_event);
  if (WaitForSingleObject(cr_thread, CREDOWN_STOP_MS) == WAIT_TIMEOUT)
    cr_log("cred-own: the serving thread did not end in %d seconds", CREDOWN_STOP_MS / 1000);
  CloseHandle(cr_thread);
  cr_thread = NULL;
  CloseHandle(cr_pipe);
  cr_pipe = INVALID_HANDLE_VALUE;
  CloseHandle(cr_stop_event);
  cr_stop_event = NULL;
  LocalFree(cr_pipe_sd);
  cr_pipe_sd = NULL;
  cr_running = FALSE;
  cr_log("cred-own: stopped - passwords set %lu, refused %lu", cr_set, cr_refused);
}

/* END-CODE */
