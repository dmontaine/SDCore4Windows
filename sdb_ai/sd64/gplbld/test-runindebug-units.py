#!/usr/bin/env python3
"""test-runindebug-units.py - run.in WITH debug on Windows (RELEASE_1.1 253(b)): the SD service starts the debugged program as a
separate, unelevated sd.exe, and the administrator's elevated SDSYS session only shows the debugger.

  python sdb_ai/sd64/gplbld/test-runindebug-units.py
  python sdb_ai/sd64/gplbld/test-runindebug-units.py --selftest

WHAT IT RUNS (N rows).  The service's half (gplsrc/sdsvc/sdrunin.c, with gplsrc/win32s4ulogon.c) and sd.exe's half
(gplsrc/win32runin.c) are compiled NATIVELY with the UCRT64 gcc - the toolchain sdsvc.exe is built with - beside a test main, and run
UNELEVATED in a temporary directory.  Nothing here needs SD, an install, the service, SeTcb or elevation:

  N1  the request: a well-formed line is read field by field; every other shape is refused (magic, field count, an upper-case or
      dotted or slashed word, the administrator account sdsys, a blank in the terminal, a size outside 20/10 to 999, 65 characters)
  N2  the register: the account's record must be a plain file, not SUSPENDED, and give the group sdu_<account>, or sdg_<account> for a
      group account (RELEASE_1.1 287; case aside; LF, CRLF and field marks all read); a missing account, a directory in its place,
      another account's group and any other prefix are refused
  N3  the child's environment: TERM, LINES, COLUMNS and the store are the run's, once each; SD_SESSION, SD_PHANTOM_NONCE and an
      SD_RUNIN_STORE the block already had are gone; everything else is kept
  N4  a run's store: a new directory, its DACL protected; SYSTEM, Administrators and this process's user, and the logon SID with
      add/read/write/delete FILES but not FILE_ADD_SUBDIRECTORY, WRITE_DAC, WRITE_OWNER or DELETE on the directory (no junction can be
      made in it); the base holds only SYSTEM, Administrators and this user
  N4b a base that is a JUNCTION (somebody made it while the service was not looking) is moved aside and a real one made; nothing is
      made in, or done to, what the junction pointed at
  N5  removing a store removes its files and a junction in it AS A LINK: what the junction pointed at is untouched
  N5b a directory in a store is never walked (its contents stay; the store is then left)
  N6  every privilege is REMOVED from a token (this process's own, duplicated) and the count read back is 0
  N7  the service refuses a session that is not an elevated administrator's ("not an elevated administrator"); run elevated, the
      refusal is the logon's instead (no SeTcb: "could not be logged on").  No store is made for a refused run.
  N7b a client that requires the LocalSystem owner refuses this test's pipe (the squat defence) before sending anything
  N7c the pipe's DACL: this process's user full, Administrators read and write only - nobody else, and no FILE_CREATE_PIPE_INSTANCE,
      WRITE_DAC or WRITE_OWNER for them
  N8  the child's door refuses this process: it is not the run.in account

WHAT IT CANNOT SHOW (the design's falsifiers F1-F6, owed in an elevated VM): that the S4U logon carries the added groups (F2); that
an MSYS2 sd.exe starts as that token from the service and enters the account (F1); what the child can and cannot open (F3); that a
plain user cannot reach it (F4); a hostile child against the debugger (F5); the one-process job against SD (F6); the relay on a real
terminal.

THE TEXT ROWS (W) read the shipped wiring the native build cannot run: the token's order in run_start (logon with two groups, primary,
privileges removed, checked, store, job of one process, created SUSPENDED, put in the job, resumed); the asker's check (impersonate,
read, revert at once, a failed revert ends the service); the serve order (asker, words, register, run); sd.c's door (asked of the
token before anything, only "debug <file> <program>", CN_PORT); $pdbg for the child; the kernel keys' gates; the client's
identification-only, owner-checked open; LOGIN's child (its group and sdusers in the token, every gate off, ri.active 2); CPROC's
child abort and paragraphs; the debugger's relay (source from the child, no AI); PDBG's SOURCE; install-service.ps1's sdrunin; the
Makefile, gpl.src and sdsvc.c wiring; the two key numbers.  W0 compiles win32runin.c and win32s4ulogon.c with the MSYS2 gcc, as sd.exe
does.

Exit 0 every row held, 1 a row failed, 2 no UCRT64 gcc.  --selftest mutates the sources (each text must match once), rebuilds when a
built file changed, and needs a red row for every mutant.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
SRC = os.path.join(SD64, "gplsrc")
UCRT_BIN = "C:/msys64/ucrt64/bin"
UCRT_CC = UCRT_BIN + "/gcc.exe"
BASH = "C:/msys64/usr/bin/bash.exe"
BS = chr(92)

# Built natively, by their path under gplsrc (copies keep the layout, so the relative includes hold).
BUILT = ["win32runin.c", "win32runin.h", "win32s4u.h", "win32s4ulogon.c", "sdsvc/sdrunin.c", "sdsvc/sdrunin.h"]
# Read as text only (paths relative to gplsrc).
TEXTS = ["sd.c", "op_debug.c", "op_kernel.c", "keys.h", "sdsvc/sdsvc.c", "../Makefile", "../gpl.src", "../sdsys/gpl.bp/login",
         "../sdsys/gpl.bp/cproc", "../sdsys/gpl.bp/debug", "../sdsys/gpl.bp/pdbg", "../sdsys/gpl.bp/int$keys.h",
         "../gplbld/install-service.ps1"]

T_ROWS = ["N1", "N2", "N3", "N4", "N4b", "N5", "N5b", "N6", "N7", "N7b", "N7c", "N8"]

MAIN = r'''
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>

#include "gplsrc/win32runin.h"
#include "gplsrc/win32s4u.h"
#include "gplsrc/sdsvc/sdrunin.h"

static char T[MAX_PATH];

static void row(const char* id, int ok, const char* what, const char* detail) {
  printf("  [%s] %s %s%s%s\n", ok ? "PASS" : "FAIL", id, what, (!ok && detail && *detail) ? " -- " : "", (!ok && detail) ? detail : "");
  fflush(stdout);
}

static void tlog(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  printf("    log: ");
  vprintf(fmt, ap);
  printf("\n");
  va_end(ap);
  fflush(stdout);
}

static void P(char* out, const char* rel) { snprintf(out, MAX_PATH, "%.200s\\%.40s", T, rel); }

static int wfile(const char* path, const char* data, size_t len) {
  FILE* f = fopen(path, "wb");
  if (f == NULL) return 0;
  fwrite(data, 1, len, f);
  fclose(f);
  return 1;
}

static int exists(const char* p) { return GetFileAttributesA(p) != INVALID_FILE_ATTRIBUTES; }

static int is_reparse(const char* p) {
  DWORD a = GetFileAttributesA(p);
  return (a != INVALID_FILE_ATTRIBUTES) && (a & FILE_ATTRIBUTE_REPARSE_POINT);
}

static int junction(const char* link, const char* target) {
  char cmd[3 * MAX_PATH];
  snprintf(cmd, sizeof(cmd), "cmd /c mklink /J \"%s\" \"%s\" >nul 2>nul", link, target);
  system(cmd);
  return is_reparse(link);
}

static BYTE own_user[SECURITY_MAX_SID_SIZE];
static BYTE own_logon[SECURITY_MAX_SID_SIZE];
static BYTE sys_sid[SECURITY_MAX_SID_SIZE];
static BYTE adm_sid[SECURITY_MAX_SID_SIZE];

static int my_sids(void) {
  HANDLE tok;
  BYTE buf[8192];
  DWORD n = 0, i;
  TOKEN_GROUPS* tg;
  int got = 0;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) return 0;
  if (GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &n)) CopySid(sizeof(own_user), own_user, ((TOKEN_USER*)buf)->User.Sid);
  n = 0;
  if (GetTokenInformation(tok, TokenGroups, buf, sizeof(buf), &n)) {
    tg = (TOKEN_GROUPS*)buf;
    for (i = 0; i < tg->GroupCount; i++)
      if (tg->Groups[i].Attributes & SE_GROUP_LOGON_ID) { CopySid(sizeof(own_logon), own_logon, tg->Groups[i].Sid); got = 1; break; }
  }
  CloseHandle(tok);
  n = sizeof(sys_sid); CreateWellKnownSid(WinLocalSystemSid, NULL, sys_sid, &n);
  n = sizeof(adm_sid); CreateWellKnownSid(WinBuiltinAdministratorsSid, NULL, adm_sid, &n);
  return got;
}

static int elevated(void) {
  HANDLE tok;
  TOKEN_ELEVATION el;
  DWORD n = 0;
  int e = 0;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
    if (GetTokenInformation(tok, TokenElevation, &el, sizeof(el), &n)) e = el.TokenIsElevated ? 1 : 0;
    CloseHandle(tok);
  }
  return e;
}

/* ---------------------------------------------------------------- N1 */
static void n1(void) {
  static const struct { const char* line; int ok; const char* what; } pc[] = {
    {"SDRUNIN1 good\tbp\tprog\twindows\t140\t43", 1, "well formed"},
    {"SDRUNIN2 good\tbp\tprog\twindows\t140\t43", 0, "another magic"},
    {"SDRUNIN1 good\tbp\tprog\twindows\t140", 0, "five fields"},
    {"SDRUNIN1 good\tbp\tprog\twindows\t140\t43\tx", 0, "seven fields"},
    {"SDRUNIN1 Good\tbp\tprog\twindows\t140\t43", 0, "upper-case account"},
    {"SDRUNIN1 good\tbp/x\tprog\twindows\t140\t43", 0, "slash"},
    {"SDRUNIN1 good\tbp\t.prog\twindows\t140\t43", 0, "leading dot"},
    {"SDRUNIN1 good\tbp\tprog\\x\twindows\t140\t43", 0, "backslash"},
    {"SDRUNIN1 sdsys\tbp\tprog\twindows\t140\t43", 0, "sdsys"},
    {"SDRUNIN1 good\tbp\tprog\twin dows\t140\t43", 0, "blank in term"},
    {"SDRUNIN1 good\tbp\tprog\twindows\t19\t43", 0, "19 columns"},
    {"SDRUNIN1 good\tbp\tprog\twindows\t140\t1000", 0, "1000 rows"},
    {"SDRUNIN1 good\tbp\tprog\twindows\t14x\t43", 0, "size not digits"},
    {"SDRUNIN1 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\tbp\tprog\twindows\t140\t43", 0, "65 characters"},
  };
  char bad[1024] = "";
  char why[256];
  SDRUNIN_REQ rq;
  size_t i;
  int ok = 1;
  for (i = 0; i < sizeof(pc) / sizeof(pc[0]); i++) {
    int rc = sdrunin_parse(pc[i].line, &rq, why, sizeof(why));
    if ((rc == 0) != (pc[i].ok != 0)) { ok = 0; strncat(bad, pc[i].what, sizeof(bad) - strlen(bad) - 3); strcat(bad, "; "); }
    if (pc[i].ok && rc == 0 && (strcmp(rq.account, "good") || strcmp(rq.file, "bp") || strcmp(rq.program, "prog") ||
                                strcmp(rq.term, "windows") || rq.cols != 140 || rq.rows != 43)) { ok = 0; strcat(bad, "fields wrong; "); }
  }
  row("N1", ok, "the request is read word by word and every other shape is refused", bad);
}

/* ---------------------------------------------------------------- N2 */
static void n2(void) {
  char sys[MAX_PATH], acc[MAX_PATH], p[MAX_PATH], g[80], why[256], bad[1024] = "";
  static const struct { const char* name; const char* data; size_t len; int ok; const char* anchor; } rc[] = {
    {"good", "C:\\a\\good\n\nsdu_good\n\n\n", 0, 1, ""},
    {"crlf", "C:\\a\\crlf\r\n\r\nSDU_CRLF\r\n\r\n\r\n", 0, 1, ""},
    {"fm", "C:\\a\\fm\xfe\xfesdu_fm\xfe\xfe", 0, 1, ""},
    {"susp", "C:\\a\n\nsdu_susp\n\nSUSPENDED\n", 0, 0, "suspended"},
    {"wrong", "C:\\a\n\nsdu_other\n\n\n", 0, 0, "not sdu_wrong or sdg_wrong"},
    {"nogroup", "C:\\a\n\n\n\n\n", 0, 0, "not sdu_nogroup"},
    {"grpacc", "C:\\a\\grpacc\n\nsdg_grpacc\n\n\n", 0, 1, ""},
    {"grpwrong", "C:\\a\n\nsdg_other\n\n\n", 0, 0, "not sdu_grpwrong or sdg_grpwrong"},
    {"grpodd", "C:\\a\n\nsdx_grpodd\n\n\n", 0, 0, "not sdu_grpodd"},
  };
  size_t i;
  int ok = 1, r;
  P(sys, "sys");
  CreateDirectoryA(sys, NULL);
  snprintf(acc, sizeof(acc), "%s\\accounts", sys);
  CreateDirectoryA(acc, NULL);
  for (i = 0; i < sizeof(rc) / sizeof(rc[0]); i++) {
    snprintf(p, sizeof(p), "%s\\%s", acc, rc[i].name);
    wfile(p, rc[i].data, strlen(rc[i].data));
  }
  snprintf(p, sizeof(p), "%s\\dir", acc);
  CreateDirectoryA(p, NULL);
  for (i = 0; i < sizeof(rc) / sizeof(rc[0]); i++) {
    r = sdrunin_register(sys, rc[i].name, g, sizeof(g), why, sizeof(why));
    if ((r == 0) != (rc[i].ok != 0) || (!rc[i].ok && strstr(why, rc[i].anchor) == NULL)) {
      ok = 0; snprintf(bad + strlen(bad), sizeof(bad) - strlen(bad), "%s: rc %d [%s]; ", rc[i].name, r, why);
    }
  }
  r = sdrunin_register(sys, "good", g, sizeof(g), why, sizeof(why));
  if (r != 0 || lstrcmpiA(g, "sdu_good") != 0) { ok = 0; strcat(bad, "good's group; "); }
  r = sdrunin_register(sys, "grpacc", g, sizeof(g), why, sizeof(why));
  if (r != 0 || lstrcmpiA(g, "sdg_grpacc") != 0) { ok = 0; strcat(bad, "grpacc's group; "); }
  r = sdrunin_register(sys, "nobody", g, sizeof(g), why, sizeof(why));
  if (r == 0 || strstr(why, "is not a registered account") == NULL) { ok = 0; strcat(bad, "missing account; "); }
  r = sdrunin_register(sys, "dir", g, sizeof(g), why, sizeof(why));
  if (r == 0 || strstr(why, "not a plain file") == NULL) { ok = 0; snprintf(bad + strlen(bad), sizeof(bad) - strlen(bad), "dir [%s]; ", why); }
  row("N2", ok, "the register: a plain record, not suspended, group sdu_<account> or (a group account) sdg_<account>; anything else refused", bad);
}

/* ---------------------------------------------------------------- N3 */
static int count_var(const WCHAR* blk, const WCHAR* name, const WCHAR* value) {
  const WCHAR* p;
  size_t nl = wcslen(name);
  int n = 0;
  for (p = blk; *p; p += wcslen(p) + 1) {
    if ((_wcsnicmp(p, name, nl) == 0) && (p[nl] == L'=')) {
      if ((value == NULL) || (wcscmp(p + nl + 1, value) == 0)) n++;
    }
  }
  return n;
}

static void n3(void) {
  static const WCHAR src[] = L"Path=C:\\x\0TERM=xterm\0=C:=C:\\\0sd_session=1\0LINES=5\0SD_RUNIN_STORE=evil\0SD_PHANTOM_NONCE=abc\0Other=1\0";
  WCHAR* e = (WCHAR*)sdrunin_env(src, "C:\\store", "windows", 140, 43);
  char bad[512] = "";
  int ok = (e != NULL);
  if (e) {
    const WCHAR* p;
    int drive = 0;
    for (p = e; *p; p += wcslen(p) + 1) if (wcscmp(p, L"=C:=C:\\") == 0) drive = 1;
    if (count_var(e, L"Path", L"C:\\x") != 1) { ok = 0; strcat(bad, "Path; "); }
    if (count_var(e, L"Other", L"1") != 1) { ok = 0; strcat(bad, "Other; "); }
    if (!drive) { ok = 0; strcat(bad, "=C:; "); }
    if (count_var(e, L"TERM", NULL) != 1 || count_var(e, L"TERM", L"windows") != 1) { ok = 0; strcat(bad, "TERM; "); }
    if (count_var(e, L"LINES", NULL) != 1 || count_var(e, L"LINES", L"43") != 1) { ok = 0; strcat(bad, "LINES; "); }
    if (count_var(e, L"COLUMNS", NULL) != 1 || count_var(e, L"COLUMNS", L"140") != 1) { ok = 0; strcat(bad, "COLUMNS; "); }
    if (count_var(e, L"SD_RUNIN_STORE", NULL) != 1 || count_var(e, L"SD_RUNIN_STORE", L"C:\\store") != 1) { ok = 0; strcat(bad, "store; "); }
    if (count_var(e, L"SD_SESSION", NULL) != 0) { ok = 0; strcat(bad, "SD_SESSION kept; "); }
    if (count_var(e, L"SD_PHANTOM_NONCE", NULL) != 0) { ok = 0; strcat(bad, "SD_PHANTOM_NONCE kept; "); }
    free(e);
  }
  row("N3", ok, "the child's environment: the run's TERM, LINES, COLUMNS and store once each; SD_SESSION and a nonce gone", bad);
}

/* ---------------------------------------------------------------- N4, N5 */
static int dacl_check(const char* path, int want_logon, char* bad, size_t badlen) {
  PACL dacl = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  SECURITY_DESCRIPTOR_CONTROL ctl = 0;
  DWORD rev = 0, i;
  int ok = 1, dir_ace = 0, file_ace = 0;
  if (GetNamedSecurityInfoA(path, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, &dacl, NULL, &sd) != ERROR_SUCCESS || dacl == NULL) {
    snprintf(bad, badlen, "no DACL on %s", path);
    return 0;
  }
  GetSecurityDescriptorControl(sd, &ctl, &rev);
  if (!(ctl & SE_DACL_PROTECTED)) { ok = 0; strncat(bad, "not protected; ", badlen - strlen(bad) - 1); }
  for (i = 0; i < dacl->AceCount; i++) {
    ACCESS_ALLOWED_ACE* a = NULL;
    PSID s;
    if (!GetAce(dacl, i, (void**)&a)) continue;
    if (a->Header.AceType != ACCESS_ALLOWED_ACE_TYPE) { ok = 0; strncat(bad, "an ACE that is not an allow; ", badlen - strlen(bad) - 1); continue; }
    s = (PSID)&a->SidStart;
    if (EqualSid(s, sys_sid) || EqualSid(s, adm_sid) || EqualSid(s, own_user)) continue;
    if (want_logon && EqualSid(s, own_logon)) {
      if (a->Header.AceFlags == 0) {
        dir_ace++;
        if (!(a->Mask & FILE_ADD_FILE) || (a->Mask & (FILE_ADD_SUBDIRECTORY | WRITE_DAC | WRITE_OWNER | DELETE | GENERIC_ALL)))
          { ok = 0; snprintf(bad + strlen(bad), badlen - strlen(bad), "the logon's directory grant is %08lx; ", (unsigned long)a->Mask); }
      } else if (a->Header.AceFlags == (INHERIT_ONLY_ACE | OBJECT_INHERIT_ACE)) {
        file_ace++;
      } else {
        ok = 0; strncat(bad, "a logon ACE with other flags; ", badlen - strlen(bad) - 1);
      }
      continue;
    }
    ok = 0;
    strncat(bad, "an ACE for somebody else; ", badlen - strlen(bad) - 1);
  }
  if (want_logon && (dir_ace != 1 || file_ace != 1)) { ok = 0; snprintf(bad + strlen(bad), badlen - strlen(bad), "logon ACEs %d/%d; ", dir_ace, file_ace); }
  LocalFree(sd);
  return ok;
}

static char store1[MAX_PATH];

static void n4(void) {
  char base[MAX_PATH], why[256], bad[1024] = "";
  int ok;
  P(base, "runin");
  ok = (sdrunin_store_make(base, own_logon, store1, sizeof(store1), why, sizeof(why)) == 0) && exists(store1);
  if (!ok) snprintf(bad, sizeof(bad), "not made [%s]; ", why);
  if (ok && !dacl_check(store1, 1, bad + strlen(bad), sizeof(bad) - strlen(bad))) ok = 0;
  if (!dacl_check(base, 0, bad + strlen(bad), sizeof(bad) - strlen(bad))) ok = 0;
  row("N4", ok, "a store: protected; SYSTEM, Administrators, this user; the logon may not make a directory or change the ACL", bad);
}

static void n4b(void) {
  char target[MAX_PATH], sent[MAX_PATH], link[MAX_PATH], path[MAX_PATH], pat[MAX_PATH], why[256], bad[512] = "";
  WIN32_FIND_DATAA fd;
  HANDLE f;
  int ok = 1;
  P(target, "target");
  CreateDirectoryA(target, NULL);
  snprintf(sent, sizeof(sent), "%s\\sentinel.txt", target);
  wfile(sent, "x", 1);
  P(link, "runin2");
  if (!junction(link, target)) { row("N4b", 0, "a junction as the base is moved aside", "could not make a junction to test with"); return; }
  if (sdrunin_store_make(link, own_logon, path, sizeof(path), why, sizeof(why)) != 0) { ok = 0; snprintf(bad, sizeof(bad), "store not made [%s]; ", why); }
  if (is_reparse(link) || !exists(link)) { ok = 0; strcat(bad, "the base is still a link; "); }
  if (!exists(sent)) { ok = 0; strcat(bad, "the sentinel went; "); }
  snprintf(pat, sizeof(pat), "%s\\r*", target);
  f = FindFirstFileA(pat, &fd);
  if (f != INVALID_HANDLE_VALUE) { ok = 0; strcat(bad, "a store was made in the target; "); FindClose(f); }
  snprintf(pat, sizeof(pat), "%s.untrusted-*", link);
  f = FindFirstFileA(pat, &fd);
  if (f == INVALID_HANDLE_VALUE) { ok = 0; strcat(bad, "nothing moved aside; "); } else FindClose(f);
  row("N4b", ok, "a base that is a junction is moved aside; nothing is made in what it pointed at", bad);
}

static void n5(void) {
  char t2[MAX_PATH], s2[MAX_PATH], p[MAX_PATH], bad[512] = "";
  int ok = 1;
  if (store1[0] == '\0') { row("N5", 0, "removing a store", "no store from N4"); return; }
  P(t2, "target2");
  CreateDirectoryA(t2, NULL);
  snprintf(s2, sizeof(s2), "%s\\sentinel2.txt", t2);
  wfile(s2, "y", 1);
  snprintf(p, sizeof(p), "%s\\f1.txt", store1); wfile(p, "1", 1);
  snprintf(p, sizeof(p), "%s\\f2.txt", store1); wfile(p, "2", 1); SetFileAttributesA(p, FILE_ATTRIBUTE_READONLY);
  snprintf(p, sizeof(p), "%s\\j", store1);
  if (!junction(p, t2)) { row("N5", 0, "removing a store", "could not make a junction to test with"); return; }
  sdrunin_store_remove(store1);
  if (exists(store1)) { ok = 0; strcat(bad, "the store is still there; "); }
  if (!exists(s2)) { ok = 0; strcat(bad, "the junction's target lost its file; "); }
  row("N5", ok, "removing a store takes its files and a junction as a link; what the junction pointed at is untouched", bad);
}

static void n5b(void) {
  char base[MAX_PATH], path[MAX_PATH], p[MAX_PATH], keep[MAX_PATH], why[256], bad[512] = "";
  int ok = 1;
  P(base, "runin");
  if (sdrunin_store_make(base, own_logon, path, sizeof(path), why, sizeof(why)) != 0) { row("N5b", 0, "a directory in a store", why); return; }
  snprintf(p, sizeof(p), "%s\\sub", path); CreateDirectoryA(p, NULL);
  snprintf(keep, sizeof(keep), "%s\\keep.txt", p); wfile(keep, "k", 1);
  sdrunin_store_remove(path);
  if (!exists(keep)) { ok = 0; strcat(bad, "the directory was walked; "); }
  row("N5b", ok, "a directory in a store is never walked", bad);
}

/* ---------------------------------------------------------------- N6 */
static void n6(void) {
  HANDLE tok = NULL, dup = NULL;
  BYTE buf[8192];
  DWORD n = 0, before = 0, after = 99;
  char why[256] = "", d[400];
  int r = 0;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_DUPLICATE | TOKEN_QUERY, &tok) &&
      DuplicateTokenEx(tok, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation, TokenPrimary, &dup)) {
    if (GetTokenInformation(dup, TokenPrivileges, buf, sizeof(buf), &n)) before = ((TOKEN_PRIVILEGES*)buf)->PrivilegeCount;
    r = sdrunin_strip_privileges(dup, why, sizeof(why));
    n = 0;
    if (GetTokenInformation(dup, TokenPrivileges, buf, sizeof(buf), &n)) after = ((TOKEN_PRIVILEGES*)buf)->PrivilegeCount;
  }
  snprintf(d, sizeof(d), "before %lu, after %lu, returned %d [%s]", (unsigned long)before, (unsigned long)after, r, why);
  printf("    N6: %s\n", d);
  row("N6", r == 1 && before > 0 && after == 0, "every privilege is removed and the count read back is 0", d);
  if (dup) CloseHandle(dup);
  if (tok) CloseHandle(tok);
}

/* ---------------------------------------------------------------- N7 */
static void n7(void) {
  char name[128], sys[MAX_PATH], base[MAX_PATH], ans[512], pat[MAX_PATH], bad[1024] = "";
  const char* req = "SDRUNIN1 good\tbp\tprog\twindows\t140\t43\n";
  const char* want;
  WIN32_FIND_DATAA fd;
  HANDLE f, h;
  int rc, el = elevated();
  snprintf(name, sizeof(name), "\\\\.\\pipe\\sd-runin-test-%lu", (unsigned long)GetCurrentProcessId());
  P(sys, "sys");
  P(base, "runin3");
  if (sdrunin_start(name, sys, base, "C:\\no\\such\\sd.exe", tlog) != 0) {
    row("N7", 0, "the service refuses the asker", "sdrunin_start failed");
    row("N7b", 0, "owner check", "not reached");
    row("N7c", 0, "pipe DACL", "not reached");
    return;
  }
  rc = win32_runin_open_to(name, 0, req, ans, sizeof(ans));
  want = el ? "could not be logged on" : "not an elevated administrator";
  printf("    N7: this process is %s; the answer: rc %d [%s]\n", el ? "ELEVATED" : "not elevated", rc, ans);
  snprintf(pat, sizeof(pat), "%s\\r*", base);
  f = FindFirstFileA(pat, &fd);
  if (f != INVALID_HANDLE_VALUE) { strcat(bad, "a store was made; "); FindClose(f); }
  if (rc == 0 || strstr(ans, want) == NULL) snprintf(bad + strlen(bad), sizeof(bad) - strlen(bad), "wanted \"%s\"; ", want);
  row("N7", bad[0] == '\0', el ? "run elevated: the run is refused at the logon (no SeTcb), and no store is made"
                                : "a session that is not an elevated administrator's is refused, and no store is made", bad);

  rc = win32_runin_open_to(name, 1, req, ans, sizeof(ans));
  row("N7b", rc != 0 && strstr(ans, "owner is not LocalSystem") != NULL, "a client that requires a LocalSystem owner sends nothing to another's pipe", ans);

  bad[0] = '\0';
  /* 13 Nov 26: the one instance can still be busy with N7b's client (ERROR_PIPE_BUSY), so wait for it, once; the error is printed. */
  h = CreateFileA(name, READ_CONTROL, 0, NULL, OPEN_EXISTING, 0, NULL);
  if (h == INVALID_HANDLE_VALUE && GetLastError() == ERROR_PIPE_BUSY && WaitNamedPipeA(name, 5000))
    h = CreateFileA(name, READ_CONTROL, 0, NULL, OPEN_EXISTING, 0, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    char e[96];
    snprintf(e, sizeof(e), "the pipe could not be opened to read it (error %lu)", (unsigned long)GetLastError());
    row("N7c", 0, "the pipe's DACL", e);
  } else {
    PSID owner = NULL;
    PACL dacl = NULL;
    PSECURITY_DESCRIPTOR sd = NULL;
    DWORD i, grant = FILE_READ_DATA | FILE_WRITE_DATA;
    int own = 0, adm = 0, other = 0;
    if (GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, NULL, &dacl, NULL, &sd) == ERROR_SUCCESS && dacl) {
      for (i = 0; i < dacl->AceCount; i++) {
        ACCESS_ALLOWED_ACE* a = NULL;
        if (!GetAce(dacl, i, (void**)&a)) continue;
        if (EqualSid((PSID)&a->SidStart, own_user)) own++;
        else if (EqualSid((PSID)&a->SidStart, adm_sid)) {
          adm++;
          if (((a->Mask & grant) != grant) || (a->Mask & (FILE_CREATE_PIPE_INSTANCE | WRITE_DAC | WRITE_OWNER | FILE_WRITE_ATTRIBUTES)))
            snprintf(bad + strlen(bad), sizeof(bad) - strlen(bad), "Administrators %08lx; ", (unsigned long)a->Mask);
        } else other++;
      }
      if (!owner || !EqualSid(owner, own_user)) strcat(bad, "owner is not this process's user; ");
      if (own != 1 || adm != 1 || other != 0) snprintf(bad + strlen(bad), sizeof(bad) - strlen(bad), "ACEs own %d adm %d other %d; ", own, adm, other);
      LocalFree(sd);
    } else strcat(bad, "no DACL; ");
    CloseHandle(h);
    row("N7c", bad[0] == '\0', "the pipe: its owner this process's user, Administrators read and write only, nobody else", bad);
  }
  sdrunin_stop();
}

/* ---------------------------------------------------------------- N8 */
static void n8(void) {
  char groups[512], why[256];
  int r = win32_runin_child_verify(groups, sizeof(groups), why, sizeof(why));
  row("N8", r == 0 && strstr(why, "not the run.in account") != NULL, "the child's door refuses a process that is not the run.in account", why);
}

int main(int argc, char** argv) {
  if (argc < 2) { printf("usage: t <tempdir>\n"); return 2; }
  snprintf(T, sizeof(T), "%s", argv[1]);
  if (!my_sids()) printf("    (no logon SID read for this process)\n");
  n1(); n2(); n3(); n4(); n4b(); n5(); n5b(); n6(); n7(); n8();
  return 0;
}
'''


def read(rel):
    with open(os.path.join(SRC, rel), encoding="latin-1", newline="") as f:
        return f.read()


def body(text, head, end="\n}\n"):
    i = text.find(head)
    if i < 0:
        return ""
    j = text.find(end, i)
    return text[i:j + len(end)] if j >= 0 else ""


def order(text, needles):
    """Positions of each needle in text, each searched after the one before; -1 where missing."""
    out, at = [], 0
    for n in needles:
        p = text.find(n, at)
        out.append(p)
        if p >= 0:
            at = p + len(n)
    return out


def text_rows(t):
    rows = []
    sr = t["sdsvc/sdrunin.c"]
    rs = body(sr, "static int run_start(")
    pos = order(rs, ["win32_s4u_logon_groups(SD_RUNIN_ACCOUNT, groups)", "DuplicateTokenEx(imp,", "sdrunin_strip_privileges(prim,",
                     "runin_token_ok(prim,", "sdrunin_store_make(runin_base,", "CreateJobObjectA(", "JOB_OBJECT_LIMIT_ACTIVE_PROCESS | JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE",
                     "ActiveProcessLimit = 1;", "CreateProcessAsUserA(prim,", "AssignProcessToJobObject(run->job, pi.hProcess)", "ResumeThread(pi.hThread);"])
    rows.append(("W1", "run_start: logon with groups, primary, privileges removed, checked, store, job of ONE process, created, put in the job, resumed - in that order",
                 all(p >= 0 for p in pos), "%s" % pos))
    rows.append(("W1b", "the child is created SUSPENDED and with exactly two groups added (sdusers, the account's)",
                 "CREATE_SUSPENDED | CREATE_NO_WINDOW" in rs and "groups[0] = RUNIN_USERS_GROUP;\n  groups[1] = group;\n  groups[2] = NULL;" in rs, ""))
    st = body(sr, "int sdrunin_strip_privileges(")
    rows.append(("W2", "privileges are REMOVED (never disabled or enabled) and the count is read back; nothing in the service raises integrity",
                 "tp->Privileges[i].Attributes = SE_PRIVILEGE_REMOVED;" in st and "(tp->PrivilegeCount != 0)" in st
                 and "SE_PRIVILEGE_ENABLED" not in sr and "SetTokenInformation" not in sr, ""))
    co = body(sr, "static int runin_client_ok(")
    i1, i2, i3 = co.find("ImpersonateNamedPipeClient(h)"), co.find("OpenThreadToken("), co.find("if (!RevertToSelf())")
    rows.append(("W3", "the asker: impersonate, read the token, revert at once (a failed revert ends the service); elevated, High, Administrators enabled",
                 0 < i1 < i2 < i3 and "ExitProcess(1)" in co[i3:i3 + 300] and "!el.TokenIsElevated" in co and "rid < SECURITY_MANDATORY_HIGH_RID" in co
                 and "WinBuiltinAdministratorsSid" not in co and "EqualSid(tg->Groups[i].Sid, (PSID)runin_admins_sid)" in co and "SE_GROUP_USE_FOR_DENY_ONLY" in co,
                 "%d %d %d" % (i1, i2, i3)))
    so = body(sr, "static void runin_serve_one(")
    p = order(so, ["runin_client_ok(h,", "sdrunin_parse(line,", "sdrunin_register(runin_sysdir,", "run_start(&rq, group, &run,", "runin_relay(h, &run);", "run_end(&run);"])
    rows.append(("W4", "serve: the asker first, then the words, then the register, then the run; the run is always ended", all(x >= 0 for x in p), "%s" % p))
    to = body(sr, "static int runin_token_ok(")
    rows.append(("W5", "the token is checked: not elevated, integrity Medium or lower, no Administrators enabled, sdusers and the account's group present, a logon SID",
                 "el.TokenIsElevated" in to and "if (rid > SECURITY_MANDATORY_MEDIUM_RID) {" in to and "EqualSid(tg->Groups[i].Sid, (PSID)runin_admins_sid)" in to
                 and "if (!have_users || !have_acct) {" in to and "if (!have_logon) {" in to, ""))
    rows.append(("W6", "the pipe: own user all, Administrators the grant (no create-instance, WRITE_DAC, WRITE_OWNER), first instance FIRST_PIPE_INSTANCE, remote refused",
                 "#define RUNIN_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)" in sr
                 and "SetEntriesInAclA(2, ea, NULL, &runin_pipe_acl)" in sr and "((i == 0) ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0)" in sr
                 and "PIPE_REJECT_REMOTE_CLIENTS" in sr and "SetSecurityDescriptorOwner(runin_pipe_sd, (PSID)runin_own_sid, FALSE)" in sr, ""))
    dg = re.search(r"#define RUNIN_STORE_DIR_GRANT\s*\\\s*\n\s*\(([^)]*)\)", sr)
    dgt = dg.group(1) if dg else ""
    rows.append(("W7", "the store's grant to the child names no FILE_ADD_SUBDIRECTORY, WRITE_DAC, WRITE_OWNER, DELETE or GENERIC on the directory",
                 bool(dgt) and not re.search(r"FILE_ADD_SUBDIRECTORY|WRITE_DAC|WRITE_OWNER|\bDELETE\b|GENERIC", dgt), dgt))
    sd = t["sd.c"]
    door = body(sd, "Private void runin_door(void) {")
    cl = sd[sd.find("Private bool comlin("):]
    p = order(cl, ['!stricmp(argv[arg], "-RUNIN")', "runin_account = argv[arg];", "  if (runin_account != NULL)\n    runin_door();\n", "  /* Start connection */"])
    pd = order(door, ["(connection_type != CN_CONSOLE)) {", "if (!win32_runin_child_verify(groups, sizeof(groups), why, sizeof(why))) {", 'strcmp(cmd[0], "debug") != 0',
                      "unsetenv(RUNIN_STORE_ENV);", "connection_type = CN_PORT;"])
    rows.append(("W8", "sd.c: -RUNIN is let through only by runin_door, before the connection starts: other entry modes refused, the TOKEN asked first, only "
                 "\"debug <file> <program>\", the store taken out of the environment, then CN_PORT", all(x >= 0 for x in p + pd) and "exit(1);" in door,
                 "%s %s" % (p, pd)))
    rows.append(("W9", "op_debug.c: run.in's child takes $pdbg (the debugger is in another process)",
                 'k_call((is_phantom || is_sdApiSrvr || (runin_account != NULL)) ? "$pdbg" : "$debug", 5, NULL, 0);' in t["op_debug.c"], ""))
    ok_ = t["op_kernel.c"]
    rk = body(ok_, "Private void runin_debug_key(")
    kc = ok_[ok_.find("    case K_RUNIN_CHILD:"):ok_.find("    case K_RUNIN_DEBUG:")]
    rows.append(("W10", "the keys: a run only from a $internal program holding the administrator flag, never in a child, an API session or a phantom; the child's answer only in the child",
                 "if (!(process.program.flags & HDR_INTERNAL) || !MY_PRIV(USR_ADMIN) || (runin_account != NULL) ||" in rk and "is_sdApiSrvr || is_phantom" in rk
                 and "if ((runin_account != NULL) && (process.program.flags & HDR_INTERNAL)) {" in kc, ""))
    wc = t["win32runin.c"]
    op = body(wc, "int win32_runin_open_to(")
    rows.append(("W11", "the client offers identification only, checks the owner before it writes, and the shipped open requires LocalSystem",
                 "SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION" in op and "SECURITY_IMPERSONATION" not in wc
                 and 0 < op.find("if (need_system_owner && !runin_owner_is_system(h)) {") < op.find("WriteFile(h, request")
                 and "return win32_runin_open_to(SD_RUNIN_PIPE, 1, request, answer, alen);" in wc, ""))
    lg = t["../sdsys/gpl.bp/login"]
    lc = lg[lg.find("      case runin.info # ''"):lg.find("      case kernel(K$FORCED.ACCOUNT,0) # ''")]
    ln = lg[lg.find("   if runin.info # '' then\n      void kernel(K$VOC.EDIT,  0)"):]
    ln = ln[:ln.find("   end\n") + 7]
    rows.append(("W12", "LOGIN: the child enters only when its token holds the account's group and sdusers; every gate and the flag off; ri.active 2; the common is CPROC's",
                 "if runin.group = '' or not(index(runin.groups, ',' : runin.group : ',', 1)) or not(index(runin.groups, ',sdusers,', 1)) then" in lc
                 and "goto terminate.connection" in lc and all(s in ln for s in ["void kernel(K$VOC.EDIT,  0)", "void kernel(K$BP.EDIT,   0)", "void kernel(K$DICT.EDIT, 0)",
                                                                                   "void kernel(K$SH, 0)", "void kernel(K$OS.EXEC, 0)", "void kernel(K$ADMINISTRATOR, 0)", "ri.active = 2"])
                 and "   common /$runin/ ri.active, ri.path, ri.account.path, ri.who, ri.sw, ri.account\n" in lg
                 and "if not(kernel(K$INTERNAL,-1)) and runin.info = '' then\n        if not(is_grp_member(lgn.id,'sdusers')) then" in lg, ""))
    cp = t["../sdsys/gpl.bp/cproc"]
    a = cp.find("         if ri.active = 2 then\n            void kernel(K$AUDIT, 'run.in child end account=' : ri.account : ' reason=abort')\n            goto abort.cproc\n         end\n")
    b = cp.find("         if ri.active then\n            gosub revert.account")
    rows.append(("W13", "CPROC: the child's abort ends it before any way back; MASTER.LOGIN and the account's LOGIN are not run in it; a run left open is ended",
                 0 < a < b and "      if ri.active # 2 then\n         openpath @sdsys:@ds:'voc' to sdvoc.f on error null" in cp
                 and "if login.voc.id # \"\" and ri.active # 2 then" in cp and "            void kernel(K$RUNIN.DEBUG, 'C')\n            dbg.relay = ''" in cp, "%d %d" % (a, b)))
    dbg = t["../sdsys/gpl.bp/debug"]
    rel = dbg[dbg.find("   if relay.on then\n      * 13 Nov 26 Windows port (RELEASE_1.1 253(b)): run.in's child names the source"):]
    rel = rel[:rel.find("   end else\n")]
    rows.append(("W14", "the debugger: in a relay the source comes from the child ('SOURCE') and no name it gave is opened; no AI; relay.on only for a cross-process stop with dbg.relay",
                 bool(rel) and "out.msg = 'SOURCE'" in rel and "gosub send.message" in rel and "openpath" not in rel
                 and "if full.screen and not(relay.on) then call $tk_ai('usable', '', ai.ok, ai.pm)" in dbg and "relay.on = phantom and (dbg.relay # '')" in dbg, ""))
    pg = t["../sdsys/gpl.bp/pdbg"]
    rows.append(("W15", "PDBG: the child talks through the run's store (DR.START) and reads the source itself for 'SOURCE'",
                 "         case msg.type = 'SOURCE'\n            src.path = debug.info(3, 0)" in pg and "openpath runin.info<2> to dbg.store else" in pg
                 and "id = 'DR.START'" in pg, ""))
    ins = t["../gplbld/install-service.ps1"]
    fn = ins[ins.find("function Install-RuninAccount {"):ins.find("function Remove-RuninAccount {")]
    dm = re.search(r"\$RuninDescription = '([^']*)'", ins)
    rows.append(("W16", "install-service.ps1: sdrunin, described in 48 characters or fewer, taken out of every group and never put in one, the four logons denied, made before "
                 "the service, removed on both exits",
                 "$RuninAccount = 'sdrunin'" in ins and dm is not None and len(dm.group(1)) <= 48 and "foreach ($g in @(Get-LocalGroup))" in fn
                 and "Remove-LocalGroupMember" in fn and "Add-LocalGroupMember" not in fn and "[SdLsaRights]::Add($u.SID.Value, [string[]]$RelayDenies)" in fn
                 and "$script:RuninAccountOk = $true" in fn and 0 < ins.find("\nInstall-RuninAccount\n") < ins.find('sc.exe" create')
                 and len(re.findall(r"Remove-RuninAccount(?!\s*\{)", ins)) >= 2, ""))
    mk, gs, sv = t["../Makefile"], t["../gpl.src"].split(), t["sdsvc/sdsvc.c"]
    mn = body(sv, "static void WINAPI svc_main(DWORD argc, LPSTR *argv) {")
    rows.append(("W17", "built and started: the Makefile builds sdrunin.c and win32s4ulogon.c into sdsvc.exe; gpl.src puts win32s4ulogon and win32runin into sd; "
                 "the service starts the broker before \"sd -start\" and stops it wherever it stops the audit writer",
                 "$(SVCDIR)/sdrunin.c $(GPLSRC)win32s4ulogon.c -lsecur32 -lbcrypt" in mk and "win32s4ulogon" in gs and "win32runin" in gs
                 and 0 < mn.find("  svc_runin_start();") < mn.find('run_sd("-start", &rc)') and mn.count("sdrunin_stop();") == mn.count("sdaudit_stop();") == 4, ""))
    kh, ik = t["keys.h"], t["../sdsys/gpl.bp/int$keys.h"]
    rows.append(("W18", "the two keys are 84 and 85 in keys.h and in int$keys.h",
                 re.search(r"#define K_RUNIN_CHILD\s+84\b", kh) and re.search(r"#define K_RUNIN_DEBUG\s+85\b", kh)
                 and re.search(r"\$define K\$RUNIN\.CHILD\s+84\b", ik) and re.search(r"\$define K\$RUNIN\.DEBUG\s+85\b", ik), ""))
    return rows


def to_msys(p):
    p = p.replace(BS, "/")
    return "/" + p[0].lower() + p[2:] if len(p) > 1 and p[1] == ":" else p


def build(work, t, exe):
    for rel in BUILT:
        dst = os.path.join(work, "gplsrc", rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="latin-1", newline="") as f:
            f.write(t[rel])
    with open(os.path.join(work, "t.c"), "w", newline="\n") as f:
        f.write(MAIN)
    cmd = [UCRT_CC, "-std=gnu17", "-O2", "-Wall", "-o", exe, "t.c", "gplsrc/sdsvc/sdrunin.c", "gplsrc/win32s4ulogon.c", "gplsrc/win32runin.c",
           "-lsecur32", "-lbcrypt", "-ladvapi32", "-luserenv"]
    r = subprocess.run(cmd, cwd=work, capture_output=True, text=True, env=dict(os.environ, PATH=UCRT_BIN.replace("/", BS) + ";" + os.environ.get("PATH", "")))
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def run(exe, work, quiet=False):
    tmp = tempfile.mkdtemp(prefix="n-", dir=work)
    try:
        r = subprocess.run([exe, tmp], capture_output=True, text=True, timeout=180)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        out = "TIMEOUT after 180 s"
    if not quiet:
        print(out.rstrip())
    seen = re.findall(r"^\s+\[(?:PASS|FAIL)\] (\S+)", out, re.M)
    bad = len(re.findall(r"^\s+\[FAIL\]", out, re.M))
    missing = [x for x in T_ROWS if x not in seen]
    if missing:
        if not quiet:
            print("  [FAIL] NULL CASE: rows that never ran: %s" % ", ".join(missing))
        bad += len(missing)
    return bad


def msys_compile(work, t):
    if not os.path.isfile(BASH):
        return None, "no MSYS2 bash"
    d = os.path.join(work, "msys")
    os.makedirs(d, exist_ok=True)
    for rel in ("win32runin.c", "win32runin.h", "win32s4ulogon.c", "win32s4u.h"):
        with open(os.path.join(d, rel), "w", encoding="latin-1", newline="") as f:
            f.write(t[rel])
    r = subprocess.run([BASH, "-lc", 'cd "%s" && gcc -std=gnu17 -O2 -Wall -Wformat=2 -Wno-format-nonliteral -fsyntax-only win32runin.c win32s4ulogon.c' % to_msys(d)],
                       capture_output=True, text=True, env=dict(os.environ, MSYSTEM="MSYS"))
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def check(t, work, exe_cache, quiet=False):
    bad = 0
    for rid, what, ok, detail in text_rows(t):
        bad += 0 if ok else 1
        if not quiet:
            print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", rid, what, (" -- " + detail) if (detail and not ok) else ""))
    key = tuple(t[r] for r in BUILT)
    if key not in exe_cache:
        exe = os.path.join(work, "t%d.exe" % len(exe_cache))
        ok, msg = build(work, t, exe)
        exe_cache[key] = exe if ok else None
        if not ok and not quiet:
            print("  [FAIL] BUILD: " + msg[:2000])
    exe = exe_cache[key]
    if exe is None:
        return bad + 1
    return bad + run(exe, work, quiet)


MUTANTS = [
    # native: the build and the N rows must see these
    ("sdsvc/sdrunin.c", "privileges are disabled, not removed", "    tp->Privileges[i].Attributes = SE_PRIVILEGE_REMOVED;", "    tp->Privileges[i].Attributes = 0;"),
    ("sdsvc/sdrunin.c", "the child may make a directory (a junction) in its store", "  (FILE_LIST_DIRECTORY | FILE_ADD_FILE | FILE_TRAVERSE",
     "  (FILE_LIST_DIRECTORY | FILE_ADD_FILE | FILE_ADD_SUBDIRECTORY | FILE_TRAVERSE"),
    ("sdsvc/sdrunin.c", "a base that is a link is used", "    if ((attr & FILE_ATTRIBUTE_DIRECTORY) && !(attr & FILE_ATTRIBUTE_REPARSE_POINT) &&",
     "    if ((attr & FILE_ATTRIBUTE_DIRECTORY) &&"),
    ("sdsvc/sdrunin.c", "the asker is not asked", "  if (!runin_client_ok(h, who, sizeof(who), why, sizeof(why))) {", "  if (0) {"),
    ("sdsvc/sdrunin.c", "the register's group is not checked", "  if ((_stricmp(group, want) != 0) && (_stricmp(group, want_g) != 0)) {", "  if (0) {"),
    # 13 Nov 26 (RELEASE_1.1 287): a group account's sdg_ group refused again, as before the fix
    ("sdsvc/sdrunin.c", "a group account's sdg_ group is refused", "  if ((_stricmp(group, want) != 0) && (_stricmp(group, want_g) != 0)) {", "  if (_stricmp(group, want) != 0) {"),
    ("sdsvc/sdrunin.c", "a suspended account is entered", '  if (_stricmp(suspended, "SUSPENDED") == 0) {', "  if (0) {"),
    ("sdsvc/sdrunin.c", "SD_SESSION reaches the child", ' L"SD_SESSION",\n', "\n"),
    ("sdsvc/sdrunin.c", "the administrator account may be debugged in", '  if (strcmp(field[0], "sdsys") == 0) {', "  if (0) {"),
    ("win32runin.h", "a word may start with a dot", "  if (!(((*w >= 'a') && (*w <= 'z')) || ((*w >= '0') && (*w <= '9'))))\n    return 0;\n", ""),
    ("win32runin.c", "the client does not check the owner", "  if (need_system_owner && !runin_owner_is_system(h)) {", "  if (0) {"),
    ("win32runin.c", "the child's door does not ask who the token is", "(lstrcmpiA(name, SD_RUNIN_ACCOUNT) != 0) || ", ""),
    ("win32runin.c", "the client offers impersonation", "SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION", "SECURITY_SQOS_PRESENT | SECURITY_IMPERSONATION"),
    ("sdsvc/sdrunin.c", "the pipe lets Administrators make an instance of it",
     "#define RUNIN_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)",
     "#define RUNIN_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE | FILE_CREATE_PIPE_INSTANCE)"),
    # text: the W rows must see these
    ("sdsvc/sdrunin.c", "the job allows more than one process", "JOB_OBJECT_LIMIT_ACTIVE_PROCESS | JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE", "JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE"),
    ("sdsvc/sdrunin.c", "the child runs before it is in its job", "CREATE_SUSPENDED | CREATE_NO_WINDOW", "CREATE_NO_WINDOW"),
    ("sdsvc/sdrunin.c", "a third group is added", "  groups[2] = NULL;", '  groups[2] = "Users";'),
    ("sdsvc/sdrunin.c", "a failed revert goes on", "      ExitProcess(1);\n", "\n"),
    ("sdsvc/sdrunin.c", "integrity above Medium is allowed", "  if (rid > SECURITY_MANDATORY_MEDIUM_RID) {", "  if (0) {"),
    ("sdsvc/sdrunin.c", "the token's groups are not checked", "  if (!have_users || !have_acct) {", "  if (0) {"),
    ("sd.c", "runin_door is not called", "  if (runin_account != NULL)\n    runin_door();\n", "\n"),
    ("sd.c", "the door does not ask the token", "  if (!win32_runin_child_verify(groups, sizeof(groups), why, sizeof(why))) {", "  if (0) {"),
    ("sd.c", "the child may run any command", 'strcmp(cmd[0], "debug") != 0', "0"),
    ("op_debug.c", "the child debugs in its own process", "(is_phantom || is_sdApiSrvr || (runin_account != NULL))", "(is_phantom || is_sdApiSrvr)"),
    ("op_kernel.c", "a program without the administrator flag may start a run",
     "if (!(process.program.flags & HDR_INTERNAL) || !MY_PRIV(USR_ADMIN) || (runin_account != NULL) ||",
     "if (!(process.program.flags & HDR_INTERNAL) || (runin_account != NULL) ||"),
    ("../sdsys/gpl.bp/login", "the child enters without its group",
     "         if runin.group = '' or not(index(runin.groups, ',' : runin.group : ',', 1)) or not(index(runin.groups, ',sdusers,', 1)) then",
     "         if runin.group = '' then"),
    ("../sdsys/gpl.bp/login", "the child keeps the account's SH", "      void kernel(K$SH, 0)\n      void kernel(K$OS.EXEC, 0)\n      void kernel(K$ADMINISTRATOR, 0)\n",
     "      void kernel(K$OS.EXEC, 0)\n      void kernel(K$ADMINISTRATOR, 0)\n"),
    ("../sdsys/gpl.bp/cproc", "the child's abort goes back somewhere",
     "         if ri.active = 2 then\n            void kernel(K$AUDIT, 'run.in child end account=' : ri.account : ' reason=abort')\n            goto abort.cproc\n         end\n", ""),
    ("../sdsys/gpl.bp/cproc", "the account's LOGIN runs in the child", "if login.voc.id # \"\" and ri.active # 2 then", "if login.voc.id # \"\" then"),
    ("../sdsys/gpl.bp/debug", "the elevated session opens the child's source", "   if relay.on then\n      * 13 Nov 26 Windows port (RELEASE_1.1 253(b)): run.in's child names",
     "   if 0 then\n      * 13 Nov 26 Windows port (RELEASE_1.1 253(b)): run.in's child names"),
    ("../sdsys/gpl.bp/debug", "the AI is offered for the child", "if full.screen and not(relay.on) then call $tk_ai", "if full.screen then call $tk_ai"),
    ("../sdsys/gpl.bp/pdbg", "PDBG does not answer SOURCE", "         case msg.type = 'SOURCE'\n", "         case msg.type = 'SOURCEX'\n"),
    ("../gplbld/install-service.ps1", "sdrunin is put in a group", "    $script:RuninAccountOk = $true\n",
     "    Add-LocalGroupMember -Group 'Users' -Member $u.SID\n    $script:RuninAccountOk = $true\n"),
    ("../Makefile", "the broker is not built into the service", "$(SVCDIR)/sdrunin.c $(GPLSRC)win32s4ulogon.c -lsecur32 -lbcrypt", "$(GPLSRC)win32s4ulogon.c -lsecur32 -lbcrypt"),
    ("sdsvc/sdsvc.c", "the service never starts the broker", "  svc_runin_start(); /*", "  (void)0; /*"),
]


def main():
    print("test-runindebug-units: sources under %s" % SRC)
    if not os.path.isfile(UCRT_CC):
        print("NO TREE: no UCRT64 gcc at %s" % UCRT_CC)
        return 2
    t = {rel: read(rel) for rel in BUILT + TEXTS}
    work = tempfile.mkdtemp(prefix="runindebug-")
    try:
        ok, msg = msys_compile(work, t)
        if ok is None:
            print("  [skip] W0 no MSYS2 bash: win32runin.c and win32s4ulogon.c not compiled as sd.exe compiles them")
            bad = 0
        else:
            print("  [%s] W0 win32runin.c and win32s4ulogon.c compile with the MSYS2 gcc, as sd.exe builds them%s" % ("PASS" if ok else "FAIL", "" if ok else " -- " + msg[:1500]))
            bad = 0 if ok else 1
        cache = {}
        bad += check(t, work, cache)
        print("%d rows failed" % bad)
        if bad:
            return 1
        if "--selftest" in sys.argv[1:]:
            holes = 0
            for rel, name, old, new in MUTANTS:
                if t[rel].count(old) != 1:
                    print("  [FAIL] %s: the text to mutate matches %d times in %s" % (name, t[rel].count(old), rel))
                    holes += 1
                    continue
                mt = dict(t)
                mt[rel] = t[rel].replace(old, new, 1)
                caught = check(mt, work, cache, quiet=True) > 0
                print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, "" if caught else ": NOT CAUGHT"))
                holes += 0 if caught else 1
            print("self-test: %d mutants, %d not caught" % (len(MUTANTS), holes))
            return 1 if holes else 0
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
