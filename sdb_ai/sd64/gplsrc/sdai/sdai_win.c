/* SDAI_WIN.C
 * sd-ai.exe: the Windows facts - the caller, the gate group, DPAPI, private files, atomic replace, locks, the event log.
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
 * 13 Nov 26 Windows port - New (RELEASE_1.1 246): the C helper replaces the Python one (gplbld/sd-ai's peer, in_group, is_sdsys, is_admin,
 *           may_ask, dpapi, acl_sids, private_file, private_create, replace, Locked and event_log, rule for rule).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Linux's form is the template; each of these is forced by the operating system:
 *   THE CALLER (Linux: SO_PEERCRED).  ImpersonateNamedPipeClient at IDENTIFICATION level (the client asks for no more), the thread token read,
 *     and RevertToSelf; if the revert fails the process ends rather than go on as anyone else.  LocalSystem, LocalService and NetworkService
 *     are never a caller.  Nothing the caller wrote names the caller.
 *   THE GATE (Linux: getgrouplist).  NetLocalGroupGetMembers of sdaiusers, read at each request, the caller's own SID among the members; every
 *     doubt is no.
 *   THE ADMINISTRATOR (Linux: sdsys or root).  The local account SDSYS, elevated, may ask without the gate and change the settings; another
 *     ELEVATED caller with Administrators enabled may change the settings (owner, 13 Nov 2026, Q6) and asks only with the gate.
 *   THE KEY (Linux: a 0600 file).  A DPAPI blob in THIS ACCOUNT'S user scope (no CRYPTPROTECT_LOCAL_MACHINE: owner, Q4), no UI, the entropy
 *     "sd-ai key <provider>", in a file whose list allows only this account and SYSTEM; a key file that grants anyone else is refused, not
 *     repaired.  The blobs the Python helper wrote are the same and read here unchanged.
 *   LOCKS (Linux: flock).  LockFileEx on byte 0, tried for ten seconds as msvcrt.locking did.
 *
 * END-DESCRIPTION
 */

#include "sdai.h"

#include <aclapi.h>
#include <lm.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wincrypt.h>

#define GATE_GROUP L"sdaiusers"   /* the right to use the provider's API: a Windows group, as sdapi and sdfiles are */
#define ADMIN_USER L"SDSYS"       /* may ask without the gate, and read the connection details through status */
#define SID_SYSTEM "S-1-5-18"

wchar_t* u2w(const char* s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  wchar_t* w;
  if (n <= 0)
    n = 1;
  w = (wchar_t*)calloc((size_t)n + 1, sizeof(wchar_t));
  if (w == NULL)
    ExitProcess(9);
  MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  return w;
}

char* w2u(const wchar_t* s) {
  int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, NULL, 0, NULL, NULL);
  char* u;
  if (n <= 0)
    n = 1;
  u = (char*)calloc((size_t)n + 1, 1);
  if (u == NULL)
    ExitProcess(9);
  WideCharToMultiByte(CP_UTF8, 0, s, -1, u, n, NULL, NULL);
  return u;
}

wchar_t* wjoin(const wchar_t* dir, const char* name) {
  wchar_t* wn = u2w(name);
  size_t a = wcslen(dir), b = wcslen(wn);
  wchar_t* out = (wchar_t*)calloc(a + b + 2, sizeof(wchar_t));
  if (out == NULL)
    ExitProcess(9);
  wcscpy(out, dir);
  if (a > 0 && dir[a - 1] != L'\\' && dir[a - 1] != L'/')
    wcscat(out, L"\\");
  wcscat(out, wn);
  free(wn);
  return out;
}

wchar_t* wdirname(const wchar_t* path) {
  wchar_t* d = _wcsdup(path);
  wchar_t* s1;
  wchar_t* s2;
  if (d == NULL)
    ExitProcess(9);
  s1 = wcsrchr(d, L'\\');
  s2 = wcsrchr(d, L'/');
  if (s2 > s1)
    s1 = s2;
  if (s1 != NULL)
    *s1 = L'\0';
  else
    wcscpy(d, L".");
  return d;
}

static int sid_text(PSID sid, char* out, size_t n) {
  LPSTR s = NULL;
  if (sid == NULL || !IsValidSid(sid) || !ConvertSidToStringSidA(sid, &s))
    return 0;
  snprintf(out, n, "%s", s);
  LocalFree(s);
  return 1;
}

static BYTE* token_info(HANDLE tok, TOKEN_INFORMATION_CLASS cls) {
  DWORD need = 0;
  BYTE* buf;
  GetTokenInformation(tok, cls, NULL, 0, &need);
  if (need == 0)
    return NULL;
  buf = (BYTE*)malloc(need);
  if (buf == NULL)
    return NULL;
  if (!GetTokenInformation(tok, cls, buf, need, &need)) {
    free(buf);
    return NULL;
  }
  return buf;
}

/* A caller from a token handle; 0 when any part cannot be read. */
static int read_token(HANDLE tok, caller_t* c) {
  BYTE* tu = token_info(tok, TokenUser);
  BYTE* te;
  BYTE* tg;
  BYTE admins[SECURITY_MAX_SID_SIZE];
  DWORD alen = sizeof admins;
  PSID user;
  memset(c, 0, sizeof *c);
  if (tu == NULL)
    return 0;
  user = ((TOKEN_USER*)tu)->User.Sid;
  if (!sid_text(user, c->sid, sizeof c->sid) || GetLengthSid(user) > sizeof c->psid) {
    free(tu);
    return 0;
  }
  CopySid(sizeof c->psid, c->psid, user);
  free(tu);
  te = token_info(tok, TokenElevation);
  c->elevated = (te != NULL) && ((TOKEN_ELEVATION*)te)->TokenIsElevated != 0;
  free(te);
  c->admins = 0;
  tg = token_info(tok, TokenGroups);
  if (tg != NULL && CreateWellKnownSid(WinBuiltinAdministratorsSid, NULL, admins, &alen)) {
    TOKEN_GROUPS* g = (TOKEN_GROUPS*)tg;
    DWORD i;
    for (i = 0; i < g->GroupCount; i++) {
      DWORD a = g->Groups[i].Attributes;
      if (EqualSid(g->Groups[i].Sid, admins) && (a & SE_GROUP_ENABLED) && !(a & SE_GROUP_USE_FOR_DENY_ONLY))
        c->admins = 1;
    }
  }
  free(tg);
  return 1;
}

int own_sid(char* out, size_t n, PSID* psid) {
  static caller_t me;
  static int have = 0;
  if (!have) {
    HANDLE tok;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
      return 0;
    have = read_token(tok, &me);
    CloseHandle(tok);
    if (!have)
      return 0;
  }
  if (out != NULL)
    snprintf(out, n, "%s", me.sid);
  if (psid != NULL)
    *psid = (PSID)me.psid;
  return 1;
}

int caller_from_pipe(HANDLE h, caller_t* c) {
  HANDLE tok = NULL;
  int ok = 0;
  if (!ImpersonateNamedPipeClient(h))
    return 0;
  if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok) || OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, FALSE, &tok)) {
    ok = read_token(tok, c);
    CloseHandle(tok);
  }
  if (!RevertToSelf())
    ExitProcess(5); /* never go on as anyone else */
  if (!ok)
    return 0;
  if (strcmp(c->sid, "S-1-5-18") == 0 || strcmp(c->sid, "S-1-5-19") == 0 || strcmp(c->sid, "S-1-5-20") == 0)
    return 0; /* LocalSystem, LocalService, NetworkService: never a person, never SDSYS */
  return 1;
}

int account_sid(const wchar_t* name, BYTE* sid, DWORD n) {
  wchar_t dom[256];
  DWORD dlen = 256;
  DWORD slen = n;
  SID_NAME_USE use;
  return LookupAccountNameW(NULL, name, sid, &slen, dom, &dlen, &use) ? 1 : 0;
}

static const wchar_t* gate_group(void) {
#ifdef SDAI_TESTS
  /* THE TEST BUILD ONLY (test-aihelper-units.py builds it with -DSDAI_TESTS; the Makefile's sd-ai target never does): the gate is a group
     the test names, so that a row can rely on a group the caller is, or is not, a member of. */
  static wchar_t g[128];
  if (GetEnvironmentVariableW(L"SD_AI_TEST_GATE", g, 128) > 0 && g[0] != L'\0')
    return g;
#endif
  return GATE_GROUP;
}

int in_group(const BYTE* sid, const wchar_t* group) {
  DWORD_PTR resume = 0;
  for (;;) {
    BYTE* buf = NULL;
    DWORD read = 0, total = 0, i;
    NET_API_STATUS rc = NetLocalGroupGetMembers(NULL, group, 0, &buf, MAX_PREFERRED_LENGTH, &read, &total, &resume);
    int found = 0;
    if (rc != NERR_Success && rc != ERROR_MORE_DATA) {
      if (buf != NULL)
        NetApiBufferFree(buf);
      return 0;
    }
    for (i = 0; buf != NULL && i < read; i++) {
      PSID m = ((LOCALGROUP_MEMBERS_INFO_0*)buf)[i].lgrmi0_sid;
      if (m != NULL && IsValidSid(m) && EqualSid(m, (PSID)sid))
        found = 1;
    }
    if (buf != NULL)
      NetApiBufferFree(buf);
    if (found)
      return 1;
    if (rc == NERR_Success)
      return 0;
  }
}

int is_sdsys(const caller_t* c) {
  wchar_t name[MAX_COMPUTERNAME_LENGTH + 16];
  DWORD n = MAX_COMPUTERNAME_LENGTH + 1;
  BYTE want[SECURITY_MAX_SID_SIZE];
  if (c == NULL || !c->elevated)
    return 0;
  if (!GetComputerNameW(name, &n))
    return 0;
  wcscat(name, L"\\");
  wcscat(name, ADMIN_USER);
  if (!account_sid(name, want, sizeof want))
    return 0;
  return EqualSid((PSID)want, (PSID)c->psid) ? 1 : 0;
}

int is_admin(const caller_t* c) { return c != NULL && (is_sdsys(c) || (c->elevated && c->admins)); }

/* S.163: SDSYS may always ask; anyone else only as a member of the gate group - another Windows administrator too (owner, Q6). */
int may_ask(const caller_t* c) { return c != NULL && (is_sdsys(c) || in_group(c->psid, gate_group())); }

/* ---------------------------------------------------------------- the key at rest */

int dpapi(const BYTE* in, DWORD n, const char* entropy, int protect, BYTE** out, DWORD* outn) {
  DATA_BLOB din, ent, dout;
  BOOL ok;
  din.cbData = n;
  din.pbData = (BYTE*)in;
  ent.cbData = (DWORD)strlen(entropy);
  ent.pbData = (BYTE*)entropy;
  memset(&dout, 0, sizeof dout);
  if (protect)
    ok = CryptProtectData(&din, NULL, &ent, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &dout);
  else
    ok = CryptUnprotectData(&din, NULL, &ent, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &dout);
  if (!ok)
    return 0;
  *out = (BYTE*)malloc(dout.cbData ? dout.cbData : 1);
  if (*out == NULL) {
    LocalFree(dout.pbData);
    return 0;
  }
  memcpy(*out, dout.pbData, dout.cbData);
  *outn = dout.cbData;
  SecureZeroMemory(dout.pbData, dout.cbData);
  LocalFree(dout.pbData);
  return 1;
}

int path_exists(const wchar_t* path) { return GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES; }

int path_isfile(const wchar_t* path) {
  DWORD a = GetFileAttributesW(path);
  return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

int path_plain_file(const wchar_t* path) {
  DWORD a = GetFileAttributesW(path);
  return a != INVALID_FILE_ATTRIBUTES && !(a & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE));
}

/* True when the file is plain (not a link or other reparse point) and every ALLOW entry of its list names this account or SYSTEM.  A list that
   cannot be read, no list (everyone), or an entry of a kind not known here is no.  A DENY entry takes nothing away from who may NOT read it. */
int private_file(const wchar_t* path) {
  PACL dacl = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  ACL_SIZE_INFORMATION info;
  PSID me;
  BYTE system[SECURITY_MAX_SID_SIZE];
  DWORD slen = sizeof system;
  DWORD i;
  int ok = 1;
  if (!path_plain_file(path) || !own_sid(NULL, 0, &me) || !CreateWellKnownSid(WinLocalSystemSid, NULL, system, &slen))
    return 0;
  if (GetNamedSecurityInfoW(path, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, &dacl, NULL, &sd) != ERROR_SUCCESS)
    return 0;
  if (dacl == NULL || !GetAclInformation(dacl, &info, sizeof info, AclSizeInformation))
    ok = 0;
  for (i = 0; ok && i < info.AceCount; i++) {
    ACE_HEADER* hdr = NULL;
    PSID s;
    if (!GetAce(dacl, i, (LPVOID*)&hdr)) {
      ok = 0;
      break;
    }
    if (hdr->AceType == ACCESS_DENIED_ACE_TYPE)
      continue;
    if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE) { /* anything but a plain ALLOW: not a list this helper can judge */
      ok = 0;
      break;
    }
    s = (PSID) & ((ACCESS_ALLOWED_ACE*)hdr)->SidStart;
    if (!EqualSid(s, me) && !EqualSid(s, (PSID)system))
      ok = 0;
  }
  if (sd != NULL)
    LocalFree(sd);
  return ok;
}

HANDLE private_create(const wchar_t* path) {
  char me[192];
  char sddl[512];
  wchar_t* w;
  PSECURITY_DESCRIPTOR psd = NULL;
  SECURITY_ATTRIBUTES sa;
  HANDLE h;
  if (!own_sid(me, sizeof me, NULL))
    return INVALID_HANDLE_VALUE;
  snprintf(sddl, sizeof sddl, "O:%sD:P(A;;FA;;;SY)(A;;FA;;;%s)", me, me);
  w = u2w(sddl);
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(w, SDDL_REVISION_1, &psd, NULL)) {
    free(w);
    return INVALID_HANDLE_VALUE;
  }
  free(w);
  sa.nLength = sizeof sa;
  sa.lpSecurityDescriptor = psd;
  sa.bInheritHandle = FALSE;
  h = CreateFileW(path, GENERIC_WRITE, 0, &sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  LocalFree(psd);
  return h;
}

/* os.replace, tried a few times: a file another request is reading cannot be replaced for that moment. */
int replace_file(const wchar_t* tmp, const wchar_t* path) {
  int attempt;
  for (attempt = 0; attempt < 20; attempt++) {
    DWORD e;
    if (MoveFileExW(tmp, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
      return 1;
    e = GetLastError();
    if (e != ERROR_ACCESS_DENIED && e != ERROR_SHARING_VIOLATION && e != ERROR_LOCK_VIOLATION)
      return 0;
    SleepEx(50, FALSE);
  }
  return 0;
}

int read_file(const wchar_t* path, size_t max, char** data, size_t* n) {
  HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  char* buf;
  size_t got = 0;
  if (h == INVALID_HANDLE_VALUE) {
    DWORD e = GetLastError();
    return (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND) ? 1 : -1;
  }
  buf = (char*)malloc(max + 1);
  if (buf == NULL) {
    CloseHandle(h);
    return -1;
  }
  while (got < max) {
    DWORD k = 0;
    DWORD want = (DWORD)(((max - got) > 65536) ? 65536 : (max - got));
    if (!ReadFile(h, buf + got, want, &k, NULL)) {
      CloseHandle(h);
      free(buf);
      return -1;
    }
    if (k == 0)
      break;
    got += k;
  }
  CloseHandle(h);
  buf[got] = '\0';
  *data = buf;
  *n = got;
  return 0;
}

HANDLE lock_open(const wchar_t* path) {
  HANDLE h = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  int tries;
  if (h == INVALID_HANDLE_VALUE)
    return h;
  for (tries = 0; tries < 10; tries++) {
    OVERLAPPED ov;
    memset(&ov, 0, sizeof ov);
    if (LockFileEx(h, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0, &ov))
      return h;
    SleepEx(1000, FALSE);
  }
  CloseHandle(h);
  return INVALID_HANDLE_VALUE;
}

void lock_close(HANDLE h) {
  OVERLAPPED ov;
  if (h == INVALID_HANDLE_VALUE)
    return;
  memset(&ov, 0, sizeof ov);
  UnlockFileEx(h, 0, 1, 0, &ov);
  CloseHandle(h);
}

/* One line to the Application event log, source sd-ai (install-aihelper.ps1 registers it): the service that cannot start is not silent. */
void event_log(const char* text) {
  HANDLE h = RegisterEventSourceW(NULL, L"sd-ai");
  wchar_t* w;
  LPCWSTR arr[1];
  if (h == NULL)
    return;
  w = u2w(text);
  arr[0] = w;
  ReportEventW(h, EVENTLOG_ERROR_TYPE, 0, 1, NULL, 1, 0, arr, NULL);
  DeregisterEventSource(h);
  free(w);
}

/* END-CODE */
