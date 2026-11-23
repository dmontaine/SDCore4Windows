/* WIN32LOCALSDSYS.C
 * SDSYS reached from this computer by the Windows users the administrator lists (RELEASE_1.1 339, Linux S.267).
 * Copyright (c) Donald Montaine
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
 * 18 Nov 26 Windows port - written for RELEASE_1.1 339.  win32localsdsys.h describes it; .claude/localsdsys/DESIGN.md has the
 *           measurements it rests on (M1-M13) and what would falsify each step (F1-F8).  NOT RUN ON AN INSTALL: the ancestry, sshd's
 *           event and the TCP row are read as DESIGN.md section 4.2 plans them, and the VM witness (W0 first) is what measures them.
 * 19 Nov 26 Windows port - RELEASE_1.1 339: the ssh chain rule follows W0's measurement on OpenSSH 10 (sit5): conhost.exe and
 *           sshd-session.exe join cmd.exe and sshd.exe, every one by full path (system directory, or the sshd service's own image
 *           folder), and A may be sshd-session.exe from that folder.  base_name() went with the name tests.  The TCP row's owner is
 *           NOT changed: W0 listed no port-22 row (the session was ::1), so whose the connection is stays to be measured.
 * 19 Nov 26 Windows port - RELEASE_1.1 339 (VM sit7): the door refused every sd-sdsys "no-session" while nothing else read
 *           OpenSSH/Operational, and admitted 6 of 6 while a probe queried it continuously (event queryable 22-38 ms after its own
 *           time, sd.exe 55-80 ms after it; W0's refusal had sd.exe 60 ms after it).  S9 now waits for sshd's record, up to
 *           SDL_EVENT_WAIT_MS, asking every SDL_EVENT_STEP_MS; what it accepts is unchanged.  The TCP row's owner was measured the
 *           same sitting (probe-tcp22): the sshd SERVICE owns the established ::1 row, so S10 stands.  sdl_ssh_evidence returns
 *           which step refused (STEP) for the service's log: S2, S7, S9 and S10 all answer no-session.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Compiled into sd.exe (the MSYS2 build: gpl.src) and into the SD service (sdsvc.exe, native).  It includes no SD header and
 * hands no Windows type across its interface.  Every answer is read from the operating system by the process that asks; nothing a
 * caller passes counts but the pid it asks about.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* winsock2.h for iphlpapi's row types only: no ws2_32 function is called (ntohs and inet_pton would need ws2_32, which sd.exe does
   not link; win32peer.c swaps the port bytes by hand for the same reason). */
#include <winsock2.h>
#include <windows.h>
#include <iphlpapi.h>
#include <aclapi.h>
#include <sddl.h>
#include <userenv.h>
#include <lm.h>
#include <ntsecapi.h>
#include <tlhelp32.h>
#include <winevt.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#include "win32localsdsys.h"

#ifndef STATUS_SUCCESS
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
#endif

/* A port as the TCP table holds it (network order in the low 16 bits) in host order. */
/* sshd's Accepted record is not queryable the instant it is written (sit7: 22-38 ms with a reader polling, longer without one), and
   sd.exe asks the door some 60 ms after it: S9 asks again every SDL_EVENT_STEP_MS until SDL_EVENT_WAIT_MS has passed. */
#define SDL_EVENT_WAIT_MS 3000
#define SDL_EVENT_STEP_MS 50
#define SDL_PORT(x)((unsigned short)((((x) & 0xFF) << 8) | (((x) >> 8) & 0xFF)))

/* ======================================================================
   Pure: the name rule and the list text                                  */

int sdl_name_ok(const char* name) {
  size_t i, n;
  int dots = 1;

  if (name == NULL)
    return 0;
  n = strlen(name);
  if (n < 1 || n > SDL_NAME_MAX)
    return 0;
  for (i = 0; i < n; i++) {
    unsigned char c = (unsigned char)name[i];
    if (c < 33 || c >= 127)
      return 0;
    if (strchr("\"/\\[]:;|=,+*?<>@", c) != NULL)
      return 0;
    if (c != '.')
      dots = 0;
  }
  return dots ? 0 : 1;
}

/* "S-1-5-21-<n>-<n>-<n>-<n>", digits only: a local or domain account's form.  1 or 0. */
static int sid_form_ok(const char* s) {
  const char* p;
  int parts = 0;

  if (strncmp(s, "S-1-5-21-", 9) != 0)
    return 0;
  p = s + 9;
  while (*p != '\0') {
    int digits = 0;
    while (*p >= '0' && *p <= '9') {
      p++;
      digits++;
    }
    if (digits == 0 || digits > 10)
      return 0;
    parts++;
    if (*p == '-')
      p++;
    else if (*p != '\0')
      return 0;
  }
  return parts == 4;
}

int sdl_parse(const char* text, size_t len, sdl_list* out) {
  size_t i = 0;

  out->n = 0;
  for (i = 0; i < len; i++) {
    unsigned char c = (unsigned char)text[i];
    if ((c < 32 && c != '\n' && c != '\r') || c > 126)
      return -1;
  }
  i = 0;
  while (i < len) {
    char line[SDL_NAME_MAX + SDL_SID_MAX + 8];
    size_t k = 0;
    char* sp;
    int j;

    while (i < len && text[i] != '\n') {
      if (k + 1 >= sizeof(line))
        return -1;
      line[k++] = text[i++];
    }
    if (i < len)
      i++;   /* the LF */
    if (k > 0 && line[k - 1] == '\r')
      k--;
    line[k] = '\0';
    if (k == 0)
      continue;
    sp = strchr(line, ' ');
    if (sp == NULL || strchr(sp + 1, ' ') != NULL)
      return -1;
    *sp = '\0';
    if (!sdl_name_ok(line) || !sid_form_ok(sp + 1) || strlen(sp + 1) >= SDL_SID_MAX)
      return -1;
    for (j = 0; j < out->n; j++)
      if (strcmp(out->sid[j], sp + 1) == 0)
        return -1;
    if (out->n >= SDL_MAX_NAMES)
      return -1;
    strcpy(out->name[out->n], line);
    strcpy(out->sid[out->n], sp + 1);
    out->n++;
  }
  return out->n;
}

/* ======================================================================
   The list files                                                          */

int sdl_list_path(const char* kind, char* out, size_t outlen) {
  char base[MAX_PATH];
  DWORD blen = sizeof(base);
  int k;

  if (strcmp(kind, "ssh") != 0 && strcmp(kind, "api") != 0)
    return 0;
  if (!GetAllUsersProfileDirectoryA(base, &blen) || base[0] == '\0')
    return 0;
  k = snprintf(out, outlen, "%s\\SD\\sd-tls\\sdsys-local-%s", base, kind);
  return (k > 0 && (size_t)k < outlen) ? 1 : 0;
}

/* 1 when the object's DACL allows nobody but SYSTEM and Administrators (a NULL DACL is everyone: 0), and, when WANT_OWNER, its owner
   is one of the two.  win32tls.c's win32_admin_only() asks the same of the DACL; it is not in the service's link, so it is here too. */
static int admin_only(HANDLE h, int want_owner) {
  PACL dacl = NULL;
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  WORD i;
  int ok = 1;

  if (GetSecurityInfo(h, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | OWNER_SECURITY_INFORMATION, &owner, NULL, &dacl, NULL,
                      &sd) != ERROR_SUCCESS)
    return 0;
  if (dacl == NULL)
    ok = 0;
  for (i = 0; ok && dacl != NULL && i < dacl->AceCount; i++) {
    ACE_HEADER* hdr;
    PSID sid;
    if (!GetAce(dacl, i, (LPVOID*)&hdr)) {
      ok = 0;
      break;
    }
    if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE)
      continue;   /* a deny only narrows */
    sid = (PSID)&((ACCESS_ALLOWED_ACE*)hdr)->SidStart;
    if (!IsWellKnownSid(sid, WinLocalSystemSid) && !IsWellKnownSid(sid, WinBuiltinAdministratorsSid))
      ok = 0;
  }
  if (ok && want_owner) {
    if (owner == NULL || (!IsWellKnownSid(owner, WinLocalSystemSid) && !IsWellKnownSid(owner, WinBuiltinAdministratorsSid)))
      ok = 0;
  }
  LocalFree(sd);
  return ok;
}

int sdl_read(const char* path, int check_acl, sdl_list* out, const char** why) {
  char dir[MAX_PATH];
  char* slash;
  DWORD attr;
  HANDLE h;
  BY_HANDLE_FILE_INFORMATION fi;
  char buf[SDL_FILE_MAX];
  DWORD got = 0;
  int n;

  out->n = 0;
  *why = "list-unsafe";
  if (path == NULL || strlen(path) >= sizeof(dir))
    return -1;

  /* The folder: not a link, and (production) open to SYSTEM and Administrators only. */
  strcpy(dir, path);
  slash = strrchr(dir, '\\');
  if (slash == NULL)
    return -1;
  *slash = '\0';
  attr = GetFileAttributesA(dir);
  if (attr == INVALID_FILE_ATTRIBUTES || !(attr & FILE_ATTRIBUTE_DIRECTORY) || (attr & FILE_ATTRIBUTE_REPARSE_POINT))
    return -1;
  if (check_acl) {
    h = CreateFileA(dir, READ_CONTROL, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE)
      return -1;
    n = admin_only(h, 0);
    CloseHandle(h);
    if (!n)
      return -1;
  }

  /* The file: absent is the empty list, as delivered. */
  attr = GetFileAttributesA(path);
  if (attr == INVALID_FILE_ATTRIBUTES) {
    DWORD e = GetLastError();
    if (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND) {
      *why = "list-empty";
      return 0;
    }
    return -1;
  }
  if ((attr & FILE_ATTRIBUTE_DIRECTORY) || (attr & FILE_ATTRIBUTE_REPARSE_POINT))
    return -1;
  h = CreateFileA(path, GENERIC_READ | READ_CONTROL, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (h == INVALID_HANDLE_VALUE)
    return -1;
  if (!GetFileInformationByHandle(h, &fi) || fi.nNumberOfLinks != 1 || fi.nFileSizeHigh != 0 || fi.nFileSizeLow >= SDL_FILE_MAX ||
      (fi.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) || (check_acl && !admin_only(h, 1))) {
    CloseHandle(h);
    return -1;
  }
  if (!ReadFile(h, buf, fi.nFileSizeLow, &got, NULL) || got != fi.nFileSizeLow) {
    CloseHandle(h);
    return -1;
  }
  CloseHandle(h);
  n = sdl_parse(buf, got, out);
  if (n < 0) {
    out->n = 0;
    return -1;
  }
  if (n == 0)
    *why = "list-empty";
  else
    *why = "";
  return n;
}

/* ======================================================================
   The account a listed SID is now                                         */

static const char* const never_names[] = {"sdsys", "sdradmin", "sdrunin", "sdrelay", NULL};

int sdl_account_ok(const char* sidtext, char* name_now, size_t nlen, const char** why) {
  PSID sid = NULL;
  char acct[256], dom[256], comp[MAX_COMPUTERNAME_LENGTH + 1];
  DWORD alen = sizeof(acct), dlen = sizeof(dom), clen = sizeof(comp);
  SID_NAME_USE use;
  DWORD rid;
  WCHAR wname[256];
  USER_INFO_1* ui = NULL;
  LOCALGROUP_USERS_INFO_0* groups = NULL;
  DWORD gread = 0, gtotal = 0, i;
  int in = 0, k;

  if (nlen > 0)
    name_now[0] = '\0';
  *why = "no-user";
  if (!ConvertStringSidToSidA(sidtext, &sid))
    return 0;
  if (!LookupAccountSidA(NULL, sid, acct, &alen, dom, &dlen, &use) || use != SidTypeUser || !GetComputerNameA(comp, &clen) ||
      lstrcmpiA(dom, comp) != 0) {
    LocalFree(sid);
    return 0;   /* gone, not a user, or not an account of THIS computer (T0745 Q4: local accounts only) */
  }
  rid = *GetSidSubAuthority(sid, (DWORD)(*GetSidSubAuthorityCount(sid) - 1));
  LocalFree(sid);
  *why = "not-sd-user";
  if (rid < 1000)
    return 0;
  for (k = 0; never_names[k] != NULL; k++)
    if (lstrcmpiA(acct, never_names[k]) == 0)
      return 0;
  if (MultiByteToWideChar(CP_ACP, 0, acct, -1, wname, (int)(sizeof(wname) / sizeof(wname[0]))) == 0)
    return 0;
  if (NetUserGetInfo(NULL, wname, 1, (LPBYTE*)&ui) != NERR_Success)
    return 0;
  k = (ui->usri1_flags & UF_ACCOUNTDISABLE) ? 1 : 0;
  NetApiBufferFree(ui);
  if (k)
    return 0;
  if (NetUserGetLocalGroups(NULL, wname, 0, LG_INCLUDE_INDIRECT, (LPBYTE*)&groups, MAX_PREFERRED_LENGTH, &gread, &gtotal) !=
      NERR_Success)
    return 0;
  for (i = 0; i < gread; i++)
    if (lstrcmpiW(groups[i].lgrui0_name, L"sdusers") == 0)
      in = 1;
  NetApiBufferFree(groups);
  if (!in)
    return 0;
  snprintf(name_now, nlen, "%s", acct);
  *why = "";
  return 1;
}

int sdl_api_listed(const char* sid, char* name_now, size_t nlen, const char** why) {
  char path[MAX_PATH];
  sdl_list l;
  int i, n;

  if (nlen > 0)
    name_now[0] = '\0';
  if (!sdl_list_path("api", path, sizeof(path))) {
    *why = "list-unsafe";
    return 0;
  }
  n = sdl_read(path, 1, &l, why);
  if (n <= 0)
    return 0;
  if (sid == NULL || sid[0] == '\0') {
    *why = "peer-unknown";
    return 0;
  }
  for (i = 0; i < l.n; i++)
    if (strcmp(l.sid[i], sid) == 0)
      return sdl_account_ok(sid, name_now, nlen, why);
  *why = "not-listed";
  return 0;
}

/* ======================================================================
   Tokens and processes                                                    */

typedef struct {
  DWORD pid;
  DWORD ppid;
  FILETIME created;
  WCHAR image[MAX_PATH];
  char sid[SDL_SID_MAX];   /* the token's user */
  LUID logon;              /* the token's logon session */
  int system;              /* the token's user is LocalSystem */
} proc_info;

/* The token user's SID as text and the token's logon session.  1 or 0. */
static int token_facts(HANDLE tok, char* sid, size_t slen, LUID* logon, int* system) {
  BYTE ubuf[256];
  TOKEN_STATISTICS ts;
  DWORD got = 0;
  LPSTR text = NULL;

  if (!GetTokenInformation(tok, TokenUser, ubuf, sizeof(ubuf), &got))
    return 0;
  if (!ConvertSidToStringSidA(((TOKEN_USER*)ubuf)->User.Sid, &text))
    return 0;
  snprintf(sid, slen, "%s", text);
  LocalFree(text);
  if (system != NULL)
    *system = IsWellKnownSid(((TOKEN_USER*)ubuf)->User.Sid, WinLocalSystemSid) ? 1 : 0;
  if (!GetTokenInformation(tok, TokenStatistics, &ts, sizeof(ts), &got))
    return 0;
  *logon = ts.AuthenticationId;
  return 1;
}

/* A process read through ONE handle: its creation time, image and token.  The parent pid comes from the snapshot.  1 or 0. */
static int proc_read(DWORD pid, DWORD ppid, proc_info* pi) {
  HANDLE hp, tok = NULL;
  FILETIME ex, kt, ut;
  DWORD ilen = MAX_PATH;
  DWORD code = 0;
  int ok = 0;

  memset(pi, 0, sizeof(*pi));
  pi->pid = pid;
  pi->ppid = ppid;
  hp = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (hp == NULL)
    return 0;
  if (GetExitCodeProcess(hp, &code) && code == STILL_ACTIVE && GetProcessTimes(hp, &pi->created, &ex, &kt, &ut) &&
      QueryFullProcessImageNameW(hp, 0, pi->image, &ilen) && OpenProcessToken(hp, TOKEN_QUERY, &tok)) {
    ok = token_facts(tok, pi->sid, sizeof(pi->sid), &pi->logon, &pi->system);
    CloseHandle(tok);
  }
  CloseHandle(hp);
  return ok;
}

static int ft_before(const FILETIME* a, const FILETIME* b) {
  return CompareFileTime(a, b) < 0;
}

/* The parent of PID from a snapshot of the process table; 0 when it is not there. */
static DWORD parent_of(HANDLE snap, DWORD pid) {
  PROCESSENTRY32W pe;

  pe.dwSize = sizeof(pe);
  if (!Process32FirstW(snap, &pe))
    return 0;
  do {
    if (pe.th32ProcessID == pid)
      return pe.th32ParentProcessID;
  } while (Process32NextW(snap, &pe));
  return 0;
}

/* A service's process: its pid and image, from the Service Control Manager.  1 or 0. */
static int service_proc(const char* name, proc_info* pi) {
  SC_HANDLE scm, svc;
  SERVICE_STATUS_PROCESS ss;
  DWORD need = 0;
  int ok = 0;

  scm = OpenSCManagerA(NULL, NULL, SC_MANAGER_CONNECT);
  if (scm == NULL)
    return 0;
  svc = OpenServiceA(scm, name, SERVICE_QUERY_STATUS);
  if (svc != NULL) {
    if (QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO, (LPBYTE)&ss, sizeof(ss), &need) && ss.dwCurrentState == SERVICE_RUNNING &&
        ss.dwProcessId != 0)
      ok = proc_read(ss.dwProcessId, 0, pi);
    CloseServiceHandle(svc);
  }
  CloseServiceHandle(scm);
  return ok;
}

/* The logon session's own SID equals SID, and its type.  1 or 0. */
static int logon_facts(LUID* logon, const char* sid, int* same_user, ULONG* type) {
  PSECURITY_LOGON_SESSION_DATA d = NULL;
  LPSTR text = NULL;

  if (LsaGetLogonSessionData(logon, &d) != STATUS_SUCCESS || d == NULL)
    return 0;
  *type = d->LogonType;
  *same_user = 0;
  if (d->Sid != NULL && ConvertSidToStringSidA(d->Sid, &text)) {
    *same_user = (strcmp(text, sid) == 0) ? 1 : 0;
    LocalFree(text);
  }
  LsaFreeReturnBuffer(d);
  return 1;
}

/* ======================================================================
   The API's loopback peer                                                 */

static char peer_sid[SDL_SID_MAX] = "";
static const char* peer_why = "peer-unknown";

const char* sdl_peer_sid(void) {
  return peer_sid;
}

const char* sdl_peer_why(void) {
  return peer_why;
}

int sdl_sid_name(const char* sidtext, char* name, size_t nlen) {
  PSID sid = NULL;
  char acct[256], dom[256];
  DWORD alen = sizeof(acct), dlen = sizeof(dom);
  SID_NAME_USE use;
  int ok = 0;

  if (nlen > 0)
    name[0] = '\0';
  if (sidtext == NULL || sidtext[0] == '\0' || !ConvertStringSidToSidA(sidtext, &sid))
    return 0;
  if (LookupAccountSidA(NULL, sid, acct, &alen, dom, &dlen, &use)) {
    snprintf(name, nlen, "%s", acct);
    ok = 1;
  }
  LocalFree(sid);
  return ok;
}

void sdl_peer_record(unsigned long peer_v4, unsigned short our_port, unsigned short peer_port) {
  PMIB_TCPTABLE_OWNER_MODULE tbl = NULL;
  DWORD size = 0, rc, i, pid = 0;
  LARGE_INTEGER conn_created;
  HANDLE hp = NULL, tok = NULL;
  FILETIME created, ex, kt, ut, cft;
  LUID logon;
  ULONG type = 0;
  int same = 0, system = 0;
  char sid[SDL_SID_MAX];

  peer_sid[0] = '\0';
  peer_why = "peer-unknown";
  conn_created.QuadPart = 0;
  if ((peer_v4 & 0xFF) != 127)
    return;   /* not loopback (the first byte, in network order): no program of this computer to name */

  rc = GetExtendedTcpTable(NULL, &size, FALSE, AF_INET, TCP_TABLE_OWNER_MODULE_ALL, 0);
  if (rc != ERROR_INSUFFICIENT_BUFFER && rc != NO_ERROR)
    return;
  tbl = (PMIB_TCPTABLE_OWNER_MODULE)HeapAlloc(GetProcessHeap(), 0, size);
  if (tbl == NULL)
    return;
  if (GetExtendedTcpTable(tbl, &size, FALSE, AF_INET, TCP_TABLE_OWNER_MODULE_ALL, 0) == NO_ERROR) {
    for (i = 0; i < tbl->dwNumEntries; i++) {
      MIB_TCPROW_OWNER_MODULE* r = &tbl->table[i];
      if (SDL_PORT(r->dwLocalPort) == peer_port && SDL_PORT(r->dwRemotePort) == our_port && r->dwLocalAddr == peer_v4 &&
          r->dwState == MIB_TCP_STATE_ESTAB) {
        pid = r->dwOwningPid;
        conn_created = r->liCreateTimestamp;
        break;
      }
    }
  }
  HeapFree(GetProcessHeap(), 0, tbl);
  if (pid == 0 || conn_created.QuadPart == 0)
    return;

  /* T0745 Q8 (a): the HANDLE first, and everything after through it, so the pid cannot be recycled under the reads. */
  hp = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (hp == NULL)
    return;
  if (!GetProcessTimes(hp, &created, &ex, &kt, &ut) || !OpenProcessToken(hp, TOKEN_QUERY, &tok)) {
    CloseHandle(hp);
    return;
  }
  CloseHandle(hp);

  /* T0745 Q8 (b): a process younger than the connection did not make it (its pid was reused after the creator exited while a child
     kept the socket). */
  cft.dwLowDateTime = conn_created.LowPart;
  cft.dwHighDateTime = (DWORD)conn_created.HighPart;
  if (!ft_before(&created, &cft)) {
    CloseHandle(tok);
    peer_why = "other-session";
    return;
  }
  if (!token_facts(tok, sid, sizeof(sid), &logon, &system)) {
    CloseHandle(tok);
    return;
  }
  CloseHandle(tok);
  if (system)
    return;   /* a service's own program is nobody's login */
  if (!logon_facts(&logon, sid, &same, &type))
    return;
  if (!same) {
    peer_why = "other-user";   /* the login behind it is not that user's (Linux: the audit login uid) */
    return;
  }
  snprintf(peer_sid, sizeof(peer_sid), "%s", sid);
  peer_why = "";
}

/* ======================================================================
   The ssh door's evidence                                                 */

/* A literal loopback address as sshd writes it: dotted 127.0.0.0/8, ::1, ::ffff:127.x.x.x.  Never a host name.  Fills the TCP row's
   family and address for the established-connection test.  1 or 0. */
/* Dotted 127.a.b.c, four decimal parts 0-255, nothing else: its four bytes.  1 or 0. */
static int dotted_127(const char* a, BYTE* four) {
  int b[4];
  char tail;

  if (strspn(a, "0123456789.") != strlen(a) || sscanf(a, "%d.%d.%d.%d%c", &b[0], &b[1], &b[2], &b[3], &tail) != 4 || b[0] != 127 ||
      b[1] < 0 || b[1] > 255 || b[2] < 0 || b[2] > 255 || b[3] < 0 || b[3] > 255)
    return 0;
  four[0] = 127;
  four[1] = (BYTE)b[1];
  four[2] = (BYTE)b[2];
  four[3] = (BYTE)b[3];
  return 1;
}

/* Only the three spellings a loopback peer has are taken (sshd writes ::1 for "localhost", DESIGN.md M13); anything else, an
   address of this computer's network included, is not-local.  No general IPv6 parser is needed for that, so none is used. */
static int loopback_literal(const char* a, int* v6, BYTE* addr16) {
  memset(addr16, 0, 16);
  if (dotted_127(a, addr16)) {
    *v6 = 0;
    return 1;
  }
  *v6 = 1;
  if (strcmp(a, "::1") == 0) {
    addr16[15] = 1;
    return 1;
  }
  if ((strncmp(a, "::ffff:", 7) == 0 || strncmp(a, "::FFFF:", 7) == 0) && dotted_127(a + 7, addr16 + 12)) {
    addr16[10] = 0xff;
    addr16[11] = 0xff;
    return 1;
  }
  return 0;
}

/* The connection REMOTE:RPORT is still established at the sshd service (which owns every port-22 row, DESIGN.md M9).  1 or 0. */
static int tcp_established(int v6, const BYTE* addr16, unsigned short rport, DWORD sshd_pid) {
  DWORD size = 0, rc, i;
  void* tbl;
  int found = 0;

  rc = GetExtendedTcpTable(NULL, &size, FALSE, v6 ? AF_INET6 : AF_INET, TCP_TABLE_OWNER_PID_ALL, 0);
  if (rc != ERROR_INSUFFICIENT_BUFFER && rc != NO_ERROR)
    return 0;
  tbl = HeapAlloc(GetProcessHeap(), 0, size);
  if (tbl == NULL)
    return 0;
  if (GetExtendedTcpTable(tbl, &size, FALSE, v6 ? AF_INET6 : AF_INET, TCP_TABLE_OWNER_PID_ALL, 0) == NO_ERROR) {
    if (v6) {
      PMIB_TCP6TABLE_OWNER_PID t = (PMIB_TCP6TABLE_OWNER_PID)tbl;
      for (i = 0; i < t->dwNumEntries && !found; i++) {
        MIB_TCP6ROW_OWNER_PID* r = &t->table[i];
        if (memcmp(r->ucRemoteAddr, addr16, 16) == 0 && SDL_PORT(r->dwRemotePort) == rport && r->dwOwningPid == sshd_pid &&
            r->dwState == MIB_TCP_STATE_ESTAB)
          found = 1;
      }
    } else {
      PMIB_TCPTABLE_OWNER_PID t = (PMIB_TCPTABLE_OWNER_PID)tbl;
      DWORD want;
      memcpy(&want, addr16, 4);
      for (i = 0; i < t->dwNumEntries && !found; i++) {
        MIB_TCPROW_OWNER_PID* r = &t->table[i];
        if (r->dwRemoteAddr == want && SDL_PORT(r->dwRemotePort) == rport && r->dwOwningPid == sshd_pid &&
            r->dwState == MIB_TCP_STATE_ESTAB)
          found = 1;
      }
    }
  }
  HeapFree(GetProcessHeap(), 0, tbl);
  return found;
}

/* "...SystemTime='2026-11-18T10:25:33.1234567Z'..." as a FILETIME (UTC).  1 or 0. */
static int event_time(const WCHAR* xml, FILETIME* ft) {
  const WCHAR* p = wcsstr(xml, L"SystemTime='");
  SYSTEMTIME st;
  int y, mo, d, h, mi, s;

  if (p == NULL) {
    p = wcsstr(xml, L"SystemTime=\"");
    if (p == NULL)
      return 0;
  }
  p += 12;
  if (swscanf(p, L"%4d-%2d-%2dT%2d:%2d:%2d", &y, &mo, &d, &h, &mi, &s) != 6)
    return 0;
  memset(&st, 0, sizeof(st));
  st.wYear = (WORD)y;
  st.wMonth = (WORD)mo;
  st.wDay = (WORD)d;
  st.wHour = (WORD)h;
  st.wMinute = (WORD)mi;
  st.wSecond = (WORD)s;
  return SystemTimeToFileTime(&st, ft) ? 1 : 0;
}

/* sshd's own record: the newest OpenSSH/Operational event 4 WRITTEN BY process A (its ProcessID, which the event system stamps; an
   event a user writes carries the user's own pid, DESIGN.md M12 and F4), at or after A was made, whose text is "Accepted <method>
   for <user> from <addr> port <n>".  Fills USER, ADDR and PORT.  1 or 0. */
static int sshd_accepted(DWORD a_pid, const FILETIME* a_created, char* user, size_t ulen, char* addr, size_t alen,
                         unsigned short* port) {
  WCHAR q[160];
  EVT_HANDLE res, ev = NULL;
  DWORD returned = 0, used = 0, props = 0;
  WCHAR* xml = NULL;
  int ok = 0;

  swprintf(q, sizeof(q) / sizeof(q[0]), L"*[System[(EventID=4) and Execution[@ProcessID=%lu]]]", (unsigned long)a_pid);
  res = EvtQuery(NULL, L"OpenSSH/Operational", q, EvtQueryChannelPath | EvtQueryReverseDirection);
  if (res == NULL)
    return 0;
  while (!ok && EvtNext(res, 1, &ev, INFINITE, 0, &returned) && returned == 1) {
    used = 0;
    if (!EvtRender(NULL, ev, EvtRenderEventXml, 0, NULL, &used, &props) && GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
      xml = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, used + sizeof(WCHAR));
      if (xml != NULL && EvtRender(NULL, ev, EvtRenderEventXml, used, xml, &used, &props)) {
        FILETIME et;
        const WCHAR* p = wcsstr(xml, L"Accepted ");
        /* 18 Nov 26: event_time() reads whole seconds, so A's creation time is compared at the same resolution (truncated to its
           second); otherwise an event written in the second A was made would read as older than A and a real login be refused. */
        ULARGE_INTEGER ac;
        FILETIME a_sec;
        ac.LowPart = a_created->dwLowDateTime;
        ac.HighPart = a_created->dwHighDateTime;
        ac.QuadPart -= ac.QuadPart % 10000000ULL;
        a_sec.dwLowDateTime = ac.LowPart;
        a_sec.dwHighDateTime = ac.HighPart;
        if (p != NULL && event_time(xml, &et) && !ft_before(&et, &a_sec)) {
          WCHAR method[32], wuser[128], waddr[64];
          unsigned int n = 0;
          if (swscanf(p, L"Accepted %31ls for %127ls from %63ls port %u", method, wuser, waddr, &n) == 4 && n > 0 && n < 65536) {
            if (WideCharToMultiByte(CP_ACP, 0, wuser, -1, user, (int)ulen, NULL, NULL) > 0 &&
                WideCharToMultiByte(CP_ACP, 0, waddr, -1, addr, (int)alen, NULL, NULL) > 0) {
              *port = (unsigned short)n;
              ok = 1;
            }
          }
        }
      }
      if (xml != NULL)
        HeapFree(GetProcessHeap(), 0, xml);
      xml = NULL;
    }
    EvtClose(ev);
    ev = NULL;
  }
  EvtClose(res);
  return ok;
}

/* The SID of a local account named NAME (sshd may write "user" or "computer\user").  1 or 0. */
static int name_sid(const char* name, char* sid, size_t slen) {
  BYTE sbuf[SECURITY_MAX_SID_SIZE];
  DWORD sl = sizeof(sbuf);
  char dom[256];
  DWORD dl = sizeof(dom);
  SID_NAME_USE use;
  LPSTR text = NULL;
  char comp[MAX_COMPUTERNAME_LENGTH + 1];
  DWORD cl = sizeof(comp);
  char full[300];
  const char* bs = strrchr(name, '\\');

  if (!GetComputerNameA(comp, &cl))
    return 0;
  snprintf(full, sizeof(full), "%s\\%s", comp, bs ? bs + 1 : name);
  if (!LookupAccountNameA(NULL, full, sbuf, &sl, dom, &dl, &use) || use != SidTypeUser)
    return 0;
  if (!ConvertSidToStringSidA((PSID)sbuf, &text))
    return 0;
  snprintf(sid, slen, "%s", text);
  LocalFree(text);
  return 1;
}

/* This process's own folder plus NAME (sd.exe beside sdsvc.exe and beside itself).  1 or 0. */
static int own_dir_file(const WCHAR* name, WCHAR* out, size_t outlen) {
  WCHAR me[MAX_PATH];
  DWORD n = GetModuleFileNameW(NULL, me, MAX_PATH);
  WCHAR* s;

  if (n == 0 || n >= MAX_PATH)
    return 0;
  s = wcsrchr(me, L'\\');
  if (s == NULL)
    return 0;
  *s = L'\0';
  if (wcslen(me) + 1 + wcslen(name) + 1 > outlen)
    return 0;
  swprintf(out, outlen, L"%ls\\%ls", me, name);
  return 1;
}

#define SDL_STEP(t) do { if (step != NULL) *step = (t); } while (0)

int sdl_ssh_evidence(unsigned long pid, char* name, size_t nlen, char* sid_out, size_t slen, const char** why, const char** step) {
  char path[MAX_PATH];
  int waited;
  sdl_list l;
  proc_info p, cur, a, svc;
  HANDLE snap;
  WCHAR sdexe[MAX_PATH], sys[MAX_PATH];
  ULONG type = 0;
  int same = 0, listed = 0, i, hops;
  DWORD ppid;
  char evuser[128], evaddr[64], evsid[SDL_SID_MAX];
  unsigned short evport = 0;
  int v6 = 0;
  BYTE addr16[16];

  if (nlen > 0)
    name[0] = '\0';
  if (slen > 0)
    sid_out[0] = '\0';

  /* S1: the list, FIRST. */
  SDL_STEP("S1 the ssh list");
  if (!sdl_list_path("ssh", path, sizeof(path))) {
    *why = "list-unsafe";
    return -1;
  }
  if (sdl_read(path, 1, &l, why) <= 0)
    return -1;

  snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) {
    SDL_STEP("S2 no process snapshot");
    *why = "no-session";
    return -1;
  }

  /* S2: the process and its token. */
  SDL_STEP("S2 the asker's process and token");
  if (!proc_read((DWORD)pid, parent_of(snap, (DWORD)pid), &p)) {
    CloseHandle(snap);
    *why = "no-login";
    return -1;
  }

  /* S3, S4: its user on the list, and an account that may be answered. */
  SDL_STEP("S3-S4 the user listed, an account that may be answered");
  for (i = 0; i < l.n; i++)
    if (strcmp(l.sid[i], p.sid) == 0)
      listed = 1;
  if (!listed) {
    CloseHandle(snap);
    *why = "not-listed";
    return -1;
  }
  if (!sdl_account_ok(p.sid, name, nlen, why)) {
    CloseHandle(snap);
    return -1;
  }

  /* S6: the logon session is that user's own, and sshd's kind (network for a key, network-cleartext for a password; F2). */
  SDL_STEP("S6 the logon session");
  if (!logon_facts(&p.logon, p.sid, &same, &type)) {
    CloseHandle(snap);
    *why = "no-login";
    return -1;
  }
  if (!same) {
    CloseHandle(snap);
    *why = "other-user";
    return -1;
  }
  if (type != Network && type != NetworkCleartext) {
    CloseHandle(snap);
    *why = "not-ssh";
    return -1;
  }

  /* S7: the process is SD's own sd.exe, and its ancestry runs only through sshd's own chain for that logon, each parent made
     before its child, up to the first SYSTEM process.
     19 Nov 26 - RELEASE_1.1 339 (VM sit5 W0, F1 FALSIFIED on OpenSSH 10): the chain measured was sd.exe <- cmd.exe <- conhost.exe <-
     sshd-session.exe (the user) <- sshd-session.exe (SYSTEM: A) <- sshd.exe (the service), every OpenSSH image in the service's own
     folder (C:\Program Files\OpenSSH from the MSI, not System32).  So the user's part may hold cmd.exe and conhost.exe from the
     system directory and sshd.exe or sshd-session.exe from the sshd SERVICE's image folder - each compared by FULL path, never by
     name alone - and nothing else (a second sd.exe, a shell, a debugger stays session-unsafe). */
  SDL_STEP("S7 the asker is not SD's own sd.exe");
  if (!own_dir_file(L"sd.exe", sdexe, MAX_PATH) || lstrcmpiW(p.image, sdexe) != 0) {
    CloseHandle(snap);
    *why = "session-unsafe";
    return -1;
  }
  if (GetSystemDirectoryW(sys, MAX_PATH) == 0) {
    CloseHandle(snap);
    SDL_STEP("S7 no system directory");
    *why = "no-session";
    return -1;
  }
  /* The sshd service, read first now: its image's folder is where sshd's own processes must come from. */
  SDL_STEP("S8 the sshd service");
  if (!service_proc(SDL_SSHD_SVC, &svc)) {
    CloseHandle(snap);
    *why = "not-ssh";
    return -1;
  }
  WCHAR sshdir[MAX_PATH], want_cmd[MAX_PATH], want_con[MAX_PATH], want_sshd[MAX_PATH], want_sess[MAX_PATH];
  lstrcpynW(sshdir, svc.image, MAX_PATH);
  {
    WCHAR* slash = wcsrchr(sshdir, L'\\');
    if (slash == NULL) {
      CloseHandle(snap);
      *why = "not-ssh";
      return -1;
    }
    *slash = L'\0';
  }
  swprintf(want_cmd, MAX_PATH, L"%ls\\cmd.exe", sys);
  swprintf(want_con, MAX_PATH, L"%ls\\conhost.exe", sys);
  swprintf(want_sshd, MAX_PATH, L"%ls\\sshd.exe", sshdir);
  swprintf(want_sess, MAX_PATH, L"%ls\\sshd-session.exe", sshdir);
  cur = p;
  for (hops = 0;; hops++) {
    ppid = cur.ppid;
    if (hops > 8 || ppid == 0) {
      CloseHandle(snap);
      SDL_STEP("S7 the chain has no SYSTEM process within 8 parents");
      *why = "no-session";
      return -1;
    }
    if (!proc_read(ppid, parent_of(snap, ppid), &a)) {
      CloseHandle(snap);
      SDL_STEP("S7 a parent in the chain could not be read (gone?)");
      *why = "no-session";
      return -1;
    }
    if (!ft_before(&a.created, &cur.created)) {
      CloseHandle(snap);
      SDL_STEP("S7 a parent in the chain was not made before its child");
      *why = "no-session";
      return -1;
    }
    if (a.system)
      break;   /* A: the first SYSTEM process up the chain */
    SDL_STEP("S7 a process in the chain is another user's, another logon's, or not sshd's own image");
    if (strcmp(a.sid, p.sid) != 0 || a.logon.LowPart != p.logon.LowPart || a.logon.HighPart != p.logon.HighPart) {
      CloseHandle(snap);
      *why = "session-unsafe";
      return -1;
    }
    if (lstrcmpiW(a.image, want_cmd) != 0 && lstrcmpiW(a.image, want_con) != 0 && lstrcmpiW(a.image, want_sshd) != 0 &&
        lstrcmpiW(a.image, want_sess) != 0) {
      CloseHandle(snap);
      *why = "session-unsafe";   /* a second sd.exe, a shell, a debugger, an image from elsewhere: not sshd's own chain */
      return -1;
    }
    cur = a;
  }

  /* S8: A is sshd itself - the sshd service's image or (OpenSSH 10) sshd-session.exe from the service's folder, SYSTEM, a child of
     the running sshd service, made after it. */
  SDL_STEP("S8 A is not sshd's own process under the sshd service");
  if ((lstrcmpiW(a.image, svc.image) != 0 && lstrcmpiW(a.image, want_sess) != 0) || a.ppid != svc.pid ||
      !ft_before(&svc.created, &a.created)) {
    CloseHandle(snap);
    *why = "not-ssh";
    return -1;
  }
  CloseHandle(snap);

  /* S9: sshd's own Accepted record, written by A, for this user.
     19 Nov 26 (sit7): waited for, because the event log has not made it queryable yet when sd.exe asks (see SDL_EVENT_WAIT_MS).
     The record that is accepted is the same one; only WHEN it is looked for changes. */
  for (waited = 0; !sshd_accepted(a.pid, &a.created, evuser, sizeof(evuser), evaddr, sizeof(evaddr), &evport);
       waited += SDL_EVENT_STEP_MS) {
    if (waited >= SDL_EVENT_WAIT_MS) {
      SDL_STEP("S9 no Accepted record written by A within the wait");
      *why = "no-session";
      return -1;
    }
    SleepEx(SDL_EVENT_STEP_MS, FALSE); /* not Sleep(): linuxlb.c defines SD's own Sleep() and this file links into sd.exe too */
  }
  if (!name_sid(evuser, evsid, sizeof(evsid)) || strcmp(evsid, p.sid) != 0) {
    SDL_STEP("S9 sshd's Accepted record names another user");
    *why = "no-session";
    return -1;
  }

  /* S10: from a literal loopback address, and that connection still established at sshd (the sshd service owns the row: sit7). */
  SDL_STEP("S10 sshd's record is not from a loopback address");
  if (!loopback_literal(evaddr, &v6, addr16)) {
    *why = "not-local";
    return -1;
  }
  if (!tcp_established(v6, addr16, evport, svc.pid)) {
    SDL_STEP("S10 the connection is not established at the sshd service");
    *why = "no-session";
    return -1;
  }

  snprintf(sid_out, slen, "%s", p.sid);
  SDL_STEP("");
  *why = "";
  return 0;
}

/* ======================================================================
   The SDSYS process the service started                                  */

int sdl_ssh_self(unsigned long pid, char* name, size_t nlen, const char** why) {
  HANDLE tok = NULL, snap;
  TOKEN_SOURCE src;
  TOKEN_ELEVATION el;
  DWORD got = 0, ppid;
  char me_sid[SDL_SID_MAX], sdsys_sid[SDL_SID_MAX], sid[SDL_SID_MAX];
  LUID logon;
  int system = 0;
  proc_info me, svc;

  if (nlen > 0)
    name[0] = '\0';
  *why = "no-session";
  if (pid == 0)
    return -1;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_QUERY_SOURCE, &tok))
    return -1;
  if (!token_facts(tok, me_sid, sizeof(me_sid), &logon, &system) ||
      !GetTokenInformation(tok, TokenSource, &src, sizeof(src), &got) ||
      !GetTokenInformation(tok, TokenElevation, &el, sizeof(el), &got)) {
    CloseHandle(tok);
    return -1;
  }
  CloseHandle(tok);
  /* SDSYS, from the SD service's S4U logon (win32s4ulogon.c's source name), elevated. */
  if (!name_sid("SDSYS", sdsys_sid, sizeof(sdsys_sid)) || strcmp(me_sid, sdsys_sid) != 0 ||
      strncmp(src.SourceName, "SDsessn", 7) != 0 || !el.TokenIsElevated)
    return -1;
  /* A child of the running SD service, made after it. */
  snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE)
    return -1;
  ppid = parent_of(snap, GetCurrentProcessId());
  CloseHandle(snap);
  if (!service_proc(SDL_SVC_NAME, &svc) || ppid != svc.pid || !proc_read(GetCurrentProcessId(), ppid, &me) ||
      !ft_before(&svc.created, &me.created))
    return -1;
  /* And the login it was started for passes every question again, asked by this process. */
  return sdl_ssh_evidence(pid, name, nlen, sid, sizeof(sid), why, NULL);
}

/* END-CODE */
