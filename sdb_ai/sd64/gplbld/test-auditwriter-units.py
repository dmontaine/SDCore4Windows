#!/usr/bin/env python3
"""test-auditwriter-units.py - the SD service is the audit trail's one writer (RELEASE_1.1 247, the Windows form of Linux W.11 F4),
and LOCK.TRACER's file is written by it alone (RELEASE_1.1 182).

  python sdb_ai/sd64/gplbld/test-auditwriter-units.py
  python sdb_ai/sd64/gplbld/test-auditwriter-units.py --selftest

WHAT IT RUNS.  The service's half (gplsrc/sdsvc/sdaudit.c, with gplsrc/win32audit.c's rotation) and a session's half
(gplsrc/win32auditpipe.c) are compiled NATIVELY with the UCRT64 gcc - the toolchain sdsvc.exe is built with - beside a test main,
and run UNELEVATED: the test serves a pipe of its own name (\\\\.\\pipe\\sd-audit-test-<pid>-a) over a temporary system directory
and talks to it with the real client code.  Nothing here needs SD, an install, the service or elevation.  What it cannot show is
the shipped arrangement - the pipe owned by LocalSystem, sessions of four kinds (console, ssh, API, job) reaching it, the
performance on the sign-on path, a member of sdusers who is not the server's user: those are the installed-system checks the
row names as owed (design-audit-writer-20261113.md).

  T7  a name somebody made first is refused (FILE_FLAG_FIRST_PIPE_INSTANCE): the server does not share it
  T1  the line's user= and pid= are the KERNEL's (the test's own DOMAIN\\name and pid), uid= the claim
  T2  a CR/LF in the text cannot start a second line (the server cleans what the session did not)
  T3  the text is an argument, never the format
  T4  a record from a session of another tree is answered N and not written; the same tree spelt differently is taken
  T5  a pipe whose owner is not LocalSystem gets nothing from a client that requires it (the squat defence)
  T6  no ACE but the server's own grants FILE_CREATE_PIPE_INSTANCE, WRITE_DAC or WRITE_OWNER on the pipe
  T9  LOCK.TRACER: no file, no line and no file made; with the file, the line exactly (value marks and all) after the sender has
      gone; a line holding a second line break is refused
  T10 a trail of AUDIT_ROTATE_BYTES is rotated before the next record (win32_audit_rotate), and the new trail's DACL is protected
  T8  the bound: one user's records past AUDIT_RATE_MAX in a window are dropped, and stopping writes ONE line saying how many
  T11 a missing trail is made with secure-audit.ps1's DACL (protected; members append only), never the directory's

The TEXT rows (W) read the shipped wiring the native build cannot see: audit_message() asks the service first, outside
ERRLOG_SEM, and appends itself only when that fails; the shipped wrappers require a LocalSystem owner; the client asks only
identification; the server reverts after impersonating and never goes on as the client; sdsvc.c starts the writer before
"sd -start" and stops it after the last "sd -stop"; lock_trace() never writes the file itself; the Makefile and gpl.src build both
halves.  W0 compiles win32auditpipe.c with the MSYS2 gcc, as sd.exe does.

Exit 0 every row held, 1 a row failed, 2 no UCRT64 gcc.  --selftest mutates the source (each text must match once), rebuilds,
and needs a red row for every mutant.
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

# The files the native build takes, by their path under gplsrc (the copies keep the layout, so the relative includes hold).
BUILT = ["win32auditpipe.c", "win32auditpipe.h", "win32audit.c", "win32audit.h", "sdsvc/sdaudit.c", "sdsvc/sdaudit.h"]
# The files only the text rows read.
TEXTS = ["k_error.c", "op_lock.c", "op_kernel.c", "sdsvc/sdsvc.c", "../Makefile", "../gpl.src"]

MAIN = r'''
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include "gplsrc/win32auditpipe.h"
#include "gplsrc/sdsvc/sdaudit.h"

static int fails = 0;
static char dir[MAX_PATH], trail[MAX_PATH], ltrace[MAX_PATH], pipe_a[MAX_PATH], pipe_b[MAX_PATH], me[300];
static DWORD mypid;
static int taken = 0; /* records of ours the server has taken in this window */
static const char* const grant[] = {"Authenticated Users", NULL};

static void row(const char* id, int ok, const char* what, const char* detail) {
  if (!ok)
    fails++;
  printf("  [%s] %s %s%s%.*s\n", ok ? "PASS" : "FAIL", id, what, (detail && *detail) ? " -- " : "",
         detail ? (int)strcspn(detail, "\r\n") : 0, detail ? detail : ""); /* the detail up to its line break */
  fflush(stdout);
}

static void tlog(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  printf("      server: ");
  vprintf(fmt, ap);
  printf("\n");
  va_end(ap);
  fflush(stdout);
}

static long file_text(const char* path, char* buf, long cap) {
  FILE* f = fopen(path, "rb");
  long n;
  if (f == NULL) { buf[0] = 0; return -1; }
  n = (long)fread(buf, 1, cap - 1, f);
  fclose(f);
  buf[n] = 0;
  return n;
}

static int count_of(const char* hay, const char* needle) {
  int n = 0;
  const char* p = hay;
  size_t l = strlen(needle);
  while ((p = strstr(p, needle)) != NULL) { n++; p += l; }
  return n;
}

static int lines_of(const char* buf) { return count_of(buf, "\n"); }

static const char* last_line(const char* buf) {
  size_t n = strlen(buf);
  const char* p;
  if (n < 2) return buf;
  p = buf + n - 2;
  while ((p > buf) && (*(p - 1) != '\n')) p--;
  return p;
}

/* the line's stamp is "yyyy-mm-dd hh:mm:ss " and then exactly want */
static int stamped(const char* line, const char* want) {
  int i;
  for (i = 0; i < 19; i++) {
    char c = line[i];
    if ((i == 4) || (i == 7)) { if (c != '-') return 0; }
    else if (i == 10) { if (c != ' ') return 0; }
    else if ((i == 13) || (i == 16)) { if (c != ':') return 0; }
    else if (!isdigit((unsigned char)c)) return 0;
  }
  return (line[19] == ' ') && (strcmp(line + 20, want) == 0);
}

static void my_name(void) {
  HANDLE tok;
  BYTE buf[512];
  DWORD n = 0, nl = 128, dl = 128;
  char name[128], dom[128];
  SID_NAME_USE use;
  char* p;
  OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok);
  GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &n);
  CloseHandle(tok);
  LookupAccountSidA(NULL, ((TOKEN_USER*)buf)->User.Sid, name, &nl, dom, &dl, &use);
  snprintf(me, sizeof(me), "%s%s%s", dom, dom[0] ? "\\" : "", name);
  for (p = me; *p; p++)
    if (!(isalnum((unsigned char)*p) || *p == '.' || *p == '_' || *p == '-' || *p == '\\' || *p == '$')) *p = '?';
}

static int rec_send(const char* who, const char* sysdir, const char* text) {
  int r = win32_audit_pipe_to(pipe_a, 0, sysdir, who, text);
  if (r == 0) taken++;
  return r;
}

static void write_bytes(const char* path, const char* data, long len, const char* mode) {
  FILE* f = fopen(path, mode);
  if (f) { fwrite(data, 1, len, f); fclose(f); }
}

/* T6 / T11: walk a DACL.  owner_sid: the one SID allowed everything (NULL: SYSTEM and Administrators are). */
static int dacl_ok(PACL dacl, PSID owner_sid, DWORD forbidden, DWORD required, char* why, size_t whysz) {
  ACL_SIZE_INFORMATION info;
  DWORD i;
  int members = 0;
  if (dacl == NULL) { snprintf(why, whysz, "no DACL"); return 0; }
  GetAclInformation(dacl, &info, sizeof(info), AclSizeInformation);
  for (i = 0; i < info.AceCount; i++) {
    ACE_HEADER* h;
    ACCESS_ALLOWED_ACE* a;
    PSID sid;
    if (!GetAce(dacl, i, (void**)&h)) continue;
    if (h->AceType != ACCESS_ALLOWED_ACE_TYPE) continue;
    a = (ACCESS_ALLOWED_ACE*)h;
    sid = (PSID)&a->SidStart;
    if ((owner_sid != NULL) && EqualSid(sid, owner_sid)) continue;
    if ((owner_sid == NULL) && (IsWellKnownSid(sid, WinLocalSystemSid) || IsWellKnownSid(sid, WinBuiltinAdministratorsSid))) continue;
    members++;
    if (a->Mask & forbidden) { snprintf(why, whysz, "ACE %lu grants 0x%08lx, which includes 0x%08lx", (unsigned long)i, (unsigned long)a->Mask, (unsigned long)(a->Mask & forbidden)); return 0; }
    if ((a->Mask & required) != required) { snprintf(why, whysz, "ACE %lu grants 0x%08lx without 0x%08lx", (unsigned long)i, (unsigned long)a->Mask, (unsigned long)required); return 0; }
  }
  snprintf(why, whysz, "%lu ACEs, %d of them members'", (unsigned long)info.AceCount, members);
  return members > 0;
}

int main(int argc, char** argv) {
  static char buf[2 * 1024 * 1024 + 4096], before[2 * 1024 * 1024 + 4096];
  char want[1024], why[256], other[MAX_PATH + 16], line[256];
  HANDLE sq;
  long n0, n1;
  int r, i, lines0, sent, ok;

  if (argc < 2) return 3;
  snprintf(dir, sizeof(dir), "%s", argv[1]);
  snprintf(trail, sizeof(trail), "%s\\audit", dir);
  snprintf(ltrace, sizeof(ltrace), "%s\\locktrace", dir);
  mypid = GetCurrentProcessId();
  snprintf(pipe_a, sizeof(pipe_a), "\\\\.\\pipe\\sd-audit-test-%lu-a", (unsigned long)mypid);
  snprintf(pipe_b, sizeof(pipe_b), "\\\\.\\pipe\\sd-audit-test-%lu-b", (unsigned long)mypid);
  my_name();
  printf("    system directory %s; pipes %s and %s; this process is %s, pid %lu\n", dir, pipe_a, pipe_b, me, (unsigned long)mypid);

  /* T7: a squatter made the name first, with room for more instances; the server must not share it */
  sq = CreateNamedPipeA(pipe_b, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED, PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                        PIPE_UNLIMITED_INSTANCES, 64, AUDIT_PIPE_MAX, 0, NULL);
  r = sdaudit_start(pipe_b, dir, grant, tlog);
  row("T7", (sq != INVALID_HANDLE_VALUE) && (r != 0), "a pipe name somebody else made first is refused, not shared", (r == 0) ? "the server STARTED on a squatted name" : "");
  if (r == 0) sdaudit_stop();
  if (sq != INVALID_HANDLE_VALUE) CloseHandle(sq);

  write_bytes(trail, "", 0, "wb");
  r = sdaudit_start(pipe_a, dir, grant, tlog);
  row("T0", r == 0, "the server starts on a fresh name", "");
  if (r != 0) { printf("    nothing else can run\n"); return 1; }

  /* T1 */
  r = rec_send("7", dir, "t1 record");
  file_text(trail, buf, sizeof(buf));
  snprintf(want, sizeof(want), "user=%s uid=7 pid=%lu t1 record\r\n", me, (unsigned long)mypid);
  row("T1", (r == 0) && (lines_of(buf) == 1) && stamped(last_line(buf), want), "the line says user= and pid= from the kernel and uid= as claimed", last_line(buf));

  /* T2 */
  lines0 = lines_of(buf);
  r = rec_send("1", dir, "user=SYSTEM uid=0 pid=4\r\n2026-01-01 00:00:00 user=X uid=1 pid=1 forged");
  file_text(trail, buf, sizeof(buf));
  snprintf(want, sizeof(want), "user=%s uid=1 pid=%lu user=SYSTEM uid=0 pid=4??2026-01-01 00:00:00 user=X uid=1 pid=1 forged\r\n", me, (unsigned long)mypid);
  row("T2", (r == 0) && (lines_of(buf) == lines0 + 1) && stamped(last_line(buf), want), "a line break in the text is '?': one record, one line, the stamp first", last_line(buf));

  /* T3 */
  r = rec_send("?", dir, "fmt %s%n%x%p end");
  file_text(trail, buf, sizeof(buf));
  snprintf(want, sizeof(want), "user=%s uid=? pid=%lu fmt %%s%%n%%x%%p end\r\n", me, (unsigned long)mypid);
  row("T3", (r == 0) && stamped(last_line(buf), want), "the text is an argument, not the format (and uid=? for no claim)", last_line(buf));

  /* T4 */
  n0 = file_text(trail, before, sizeof(before));
  snprintf(other, sizeof(other), "%s-other", dir);
  r = rec_send("7", other, "t4 another tree");
  i = win32_audit_pipe_to(pipe_a, 0, dir, "7x", "t4 bad claim");
  n1 = file_text(trail, buf, sizeof(buf));
  row("T4a", (r != 0) && (i != 0) && (n1 == n0), "another tree's record, and a claim that is not a number, are not taken and not written", "");
  for (i = 0; dir[i]; i++) other[i] = (char)toupper((unsigned char)dir[i]);
  other[i] = 0;
  strcat(other, "\\");
  for (i = 0; other[i]; i++) if (other[i] == '\\' && i > 2) { other[i] = '/'; break; }
  r = rec_send("7", other, "t4 same tree spelt differently");
  file_text(trail, buf, sizeof(buf));
  row("T4b", (r == 0) && (strstr(last_line(buf), "t4 same tree spelt differently") != NULL), "the same tree in other case, with / and a trailing separator, is taken", other);

  /* T5 */
  n0 = file_text(trail, before, sizeof(before));
  {
    char m[256];
    int len = snprintf(m, sizeof(m), "%s7\t%s\tt5 squat", AUDIT_MAGIC, dir);
    r = audit_pipe_send(pipe_a, 1, m, len, 1, NULL);
  }
  i = win32_audit_pipe_to(pipe_a, 1, dir, "7", "t5 squat");
  n1 = file_text(trail, buf, sizeof(buf));
  row("T5", (r == -2) && (i != 0) && (n1 == n0), "a pipe not owned by LocalSystem gets nothing from a client that requires it", "");

  /* T6 */
  {
    HANDLE h = CreateFileA(pipe_a, READ_CONTROL | SYNCHRONIZE, 0, NULL, OPEN_EXISTING, SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL);
    PACL dacl = NULL;
    PSECURITY_DESCRIPTOR sd = NULL;
    BYTE ub[512];
    DWORD n = 0;
    HANDLE tok;
    ok = 0;
    snprintf(why, sizeof(why), "could not open the pipe (error %lu)", (unsigned long)GetLastError());
    OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok);
    GetTokenInformation(tok, TokenUser, ub, sizeof(ub), &n);
    CloseHandle(tok);
    if ((h != INVALID_HANDLE_VALUE) && (GetSecurityInfo(h, SE_KERNEL_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, &dacl, NULL, &sd) == ERROR_SUCCESS))
      ok = dacl_ok(dacl, ((TOKEN_USER*)ub)->User.Sid, FILE_CREATE_PIPE_INSTANCE | WRITE_DAC | WRITE_OWNER | FILE_WRITE_ATTRIBUTES, FILE_WRITE_DATA, why, sizeof(why));
    if (sd) LocalFree(sd);
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    row("T6", ok, "only the server's own user may make an instance of the name or change the pipe's security", why);
  }

  /* T9 */
  {
    char lt[128];
    char lt2[128];
    int len, len2;
    DeleteFileA(ltrace);
    len = snprintf(lt, sizeof(lt), "1700000000\xfd" "3\xfd" "C:/x/f\xfd" "id1\xfd" "1\xfd" "prog\xfd" "1A\xfd" "12\n");
    r = win32_locktrace_pipe_to(pipe_a, 0, dir, lt, len);
    Sleep(400);
    row("T9a", (r == 0) && (GetFileAttributesA(ltrace) == INVALID_FILE_ATTRIBUTES), "with no locktrace file, a lock line makes none", "");
    write_bytes(ltrace, "", 0, "wb");
    r = win32_locktrace_pipe_to(pipe_a, 0, dir, lt, len);
    for (i = 0; i < 40; i++) { if (file_text(ltrace, buf, sizeof(buf)) == len) break; Sleep(50); }
    row("T9b", (r == 0) && (file_text(ltrace, buf, sizeof(buf)) == len) && (memcmp(buf, lt, len) == 0), "with the file, the line arrives exactly, after a sender that did not wait", "");
    len2 = snprintf(lt2, sizeof(lt2), "1700000001\xfd" "3\xfd" "f\n1700000002\xfd" "3\xfd" "forged\n");
    r = win32_locktrace_pipe_to(pipe_a, 0, dir, lt2, len2);
    Sleep(400);
    row("T9c", (file_text(ltrace, buf, sizeof(buf)) == len), "a lock line holding a second line break is refused", "");
  }

  /* T10 */
  {
    static char fill[64 * 1024];
    WIN32_FIND_DATAA fd;
    HANDLE fh;
    char pat[MAX_PATH + 8], found[MAX_PATH] = "";
    long rotated_size = 0;
    PSECURITY_DESCRIPTOR sd = NULL;
    SECURITY_DESCRIPTOR_CONTROL ctl = 0;
    DWORD rev;
    memset(fill, 'x', sizeof(fill));
    fill[sizeof(fill) - 1] = '\n';
    for (i = 0; i < (int)(AUDIT_ROTATE_BYTES / sizeof(fill)) + 1; i++) write_bytes(trail, fill, sizeof(fill), "ab");
    r = rec_send("7", dir, "t10 after rotation");
    snprintf(pat, sizeof(pat), "%s\\audit.*", dir);
    if ((fh = FindFirstFileA(pat, &fd)) != INVALID_HANDLE_VALUE) { /* "audit.*" also matches "audit" itself */
      do {
        if (strncmp(fd.cFileName, "audit.", 6) == 0) { snprintf(found, sizeof(found), "%s", fd.cFileName); rotated_size = (long)fd.nFileSizeLow; }
      } while (FindNextFileA(fh, &fd));
      FindClose(fh);
    }
    n1 = file_text(trail, buf, sizeof(buf));
    snprintf(want, sizeof(want), "user=%s uid=7 pid=%lu t10 after rotation\r\n", me, (unsigned long)mypid);
    row("T10a", (r == 0) && found[0] && (rotated_size >= AUDIT_ROTATE_BYTES) && (lines_of(buf) == 1) && stamped(buf, want), "a full trail is rotated before the next record, which starts the new one", found);
    if (GetNamedSecurityInfoA(trail, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, NULL, NULL, &sd) == ERROR_SUCCESS)
      GetSecurityDescriptorControl(sd, &ctl, &rev);
    row("T10b", (ctl & SE_DACL_PROTECTED) != 0, "the new trail carries the old one's DACL, protected from the directory's", "");
    if (sd) LocalFree(sd);
  }

  /* T8 */
  {
    int before_rate = taken;
    sent = AUDIT_RATE_MAX - before_rate + 3;
    ok = 1;
    for (i = 0; i < sent; i++) {
      snprintf(line, sizeof(line), "rate-%d", i);
      if (rec_send("7", dir, line) != 0) ok = 0;
    }
    file_text(trail, buf, sizeof(buf));
    snprintf(why, sizeof(why), "sent %d, %d before in this window; %d written", sent, before_rate, count_of(buf, " rate-"));
    row("T8a", ok && (count_of(buf, " rate-") == AUDIT_RATE_MAX - before_rate), "past AUDIT_RATE_MAX in a window, a user's records are dropped (and answered as taken)", why);
  }

  sdaudit_stop();
  file_text(trail, buf, sizeof(buf));
  snprintf(want, sizeof(want), "user=%s uid=? pid=%lu audit rate limit dropped=3 taken=%d limit=%d window=%d\r\n", me, (unsigned long)mypid, AUDIT_RATE_MAX, AUDIT_RATE_MAX, AUDIT_RATE_WINDOW);
  row("T8b", (count_of(buf, "audit rate limit") == 1) && stamped(last_line(buf), want), "stopping writes ONE line saying how many were dropped", last_line(buf));

  /* T11 */
  DeleteFileA(trail);
  r = sdaudit_start(pipe_a, dir, grant, tlog);
  i = rec_send("7", dir, "t11 made the trail");
  sdaudit_stop();
  {
    PACL dacl = NULL;
    PSECURITY_DESCRIPTOR sd = NULL;
    SECURITY_DESCRIPTOR_CONTROL ctl = 0;
    DWORD rev;
    ok = 0;
    snprintf(why, sizeof(why), "no trail");
    if ((GetFileAttributesA(trail) != INVALID_FILE_ATTRIBUTES) &&
        (GetNamedSecurityInfoA(trail, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, &dacl, NULL, &sd) == ERROR_SUCCESS)) {
      GetSecurityDescriptorControl(sd, &ctl, &rev);
      ok = (ctl & SE_DACL_PROTECTED) && dacl_ok(dacl, NULL, FILE_WRITE_DATA | FILE_READ_DATA | DELETE | WRITE_DAC | WRITE_OWNER, FILE_APPEND_DATA, why, sizeof(why));
    }
    if (sd) LocalFree(sd);
    row("T11", (r == 0) && (i == 0) && ok, "a missing trail is made protected, members append only (secure-audit.ps1's DACL)", why);
  }

  printf("    %d rows failed\n", fails);
  return fails ? 1 : 0;
}
'''

# T-rows the main prints, for the null case
T_ROWS = ["T7", "T0", "T1", "T2", "T3", "T4a", "T4b", "T5", "T6", "T9a", "T9b", "T9c", "T10a", "T10b", "T8a", "T8b", "T11"]


def read(rel):
    with open(os.path.join(SRC, rel), encoding="latin-1", newline="") as f:
        return f.read()


def body(text, head):
    i = text.find(head)
    if i < 0:
        return ""
    j = text.find("\n}\n", i)
    return text[i:j + 3] if j >= 0 else ""


def text_rows(t):
    rows = []
    ke = body(t["k_error.c"], "void audit_message(char* msg) {")
    p = ke.find("  if (win32_audit_pipe(sd_sysdir(), who, pmsg) == 0)\n    return;")
    s = ke.find("StartExclusive(ERRLOG_SEM, 67)")
    a = ke.find("win32_audit_append(path, buff, bytes)")
    rows.append(("W1", "audit_message() asks the service first, OUTSIDE ERRLOG_SEM, returns when it took the record, and appends itself only after",
                 0 < p < s < a and ke.count("win32_audit_pipe(") == 1, "pipe %d, semaphore %d, append %d" % (p, s, a)))
    rows.append(("W1b", "the record handed over carries the job suffix the fallback line carries",
                 'snprintf(pmsg, sizeof(pmsg), "%s%s%s", msg, jkey, sd_job_active);' in ke, ""))
    cl = t["win32auditpipe.c"]
    wa = body(cl, "int win32_audit_pipe(const char* sysdir, const char* who, const char* text) {")
    wl = body(cl, "void win32_locktrace_pipe(const char* sysdir, const char* line, int len) {")
    rows.append(("W2", "the shipped wrappers send to SD_AUDIT_PIPE and require a LocalSystem owner",
                 "win32_audit_pipe_to(SD_AUDIT_PIPE, 1, sysdir, who, text)" in wa and "win32_locktrace_pipe_to(SD_AUDIT_PIPE, 1, sysdir, line, len)" in wl, ""))
    rows.append(("W3", "the client asks only identification of the server, and checks the owner before writing",
                 "FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION" in cl and "SECURITY_IMPERSONATION" not in cl and "SECURITY_DELEGATION" not in cl
                 and 0 < cl.find("if (need_system_owner && !pipe_owner_is_system(h))") < cl.find("pipe_io(h, ev, TRUE"), ""))
    sv = t["sdsvc/sdaudit.c"]
    ci = body(sv, "static BOOL audit_client_identity(")
    i1, i2, i3 = ci.find("ImpersonateNamedPipeClient(h)"), ci.find("OpenThreadToken("), ci.find("if (!RevertToSelf())")
    rows.append(("W4", "the server reverts straight after reading the token, and a failed revert ends the process",
                 0 < i1 < i2 < i3 and "ExitProcess(1)" in ci[i3:i3 + 300], "%d %d %d" % (i1, i2, i3)))
    rows.append(("W4b", "the server never takes the user or the pid from the message: pid from the pipe, user from the token",
                 "if (!GetNamedPipeClientProcessId(h, &pid))" in sv and "audit_format_line(line, sizeof(line), user, who, pid, msg)" in sv, ""))
    sc = t["sdsvc/sdsvc.c"]
    mn = body(sc, "static void WINAPI svc_main(DWORD argc, LPSTR *argv) {")
    st, rs = mn.find("svc_audit_start();"), mn.find('run_sd("-start", &rc)')
    last_stop = mn.rfind('run_sd("-stop", &rc);')
    rows.append(("W5", "sdsvc starts the writer before \"sd -start\", stops it after the last \"sd -stop\", and on all three failure paths",
                 0 < st < rs and 0 < last_stop < mn.rfind("sdaudit_stop();") and mn.count("sdaudit_stop();") == 4, "start %d, sd -start %d, stops %d" % (st, rs, mn.count("sdaudit_stop();"))))
    ol = body(t["op_lock.c"], "Private void lock_trace(int code, int16_t file_id, const char* id, int16_t id_len) {")
    rows.append(("W6", "lock_trace() sends its line to the service and never opens the file itself",
                 "win32_locktrace_pipe(sd_sysdir(), buff, bytes);" in ol and "open(" not in ol and "win32_audit_append" not in ol and "fopen" not in ol, ""))
    ok = t["op_kernel.c"]
    ok = ok[ok.find("    case K_LOCK_TRACE: {"):]
    ok = ok[:ok.find("    case K_PROFILER:")]
    rows.append(("W7", "K_LOCK_TRACE: only an administrator changes it; ON makes the file through win32_locktrace_create()",
                 0 < ok.find("!MY_ADMIN()") < ok.find("win32_locktrace_create(lt_path) == 0") and ok.count("sysseg->lock_trace = 1;") == 1, ""))
    mk = t["../Makefile"]
    rows.append(("W8", "the Makefile builds sdaudit.c and win32audit.c into sdsvc.exe; gpl.src puts win32auditpipe into sd",
                 "$(SVCDIR)/sdsvc.c $(SVCDIR)/sdaudit.c $(GPLSRC)win32audit.c" in mk and "-luserenv" in mk and "win32auditpipe" in t["../gpl.src"].split(), ""))
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
    cmd = [UCRT_CC, "-std=gnu17", "-O2", "-Wall", "-o", exe, "t.c", "gplsrc/sdsvc/sdaudit.c", "gplsrc/win32audit.c", "gplsrc/win32auditpipe.c",
           "-ladvapi32", "-luserenv"]
    r = subprocess.run(cmd, cwd=work, capture_output=True, text=True, env=dict(os.environ, PATH=UCRT_BIN.replace("/", BS) + ";" + os.environ.get("PATH", "")))
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def run(exe, work, quiet=False):
    sysdir = tempfile.mkdtemp(prefix="sys-", dir=work)  # a fresh one each run: a trail made in T11 is append-only to us
    try:
        r = subprocess.run([exe, sysdir], capture_output=True, text=True, timeout=120)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        out = "TIMEOUT after 120 s"
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
    for rel in ("win32auditpipe.c", "win32auditpipe.h"):
        with open(os.path.join(d, rel), "w", encoding="latin-1", newline="") as f:
            f.write(t[rel])
    r = subprocess.run([BASH, "-lc", 'cd "%s" && gcc -std=gnu17 -O2 -Wall -Wformat=2 -Wno-format-nonliteral -fsyntax-only win32auditpipe.c' % to_msys(d)],
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
    ("win32auditpipe.c", "the client skips the owner check", "  if (need_system_owner && !pipe_owner_is_system(h)) {", "  if (0) {"),
    ("win32auditpipe.c", "the shipped wrapper does not require LocalSystem", "return win32_audit_pipe_to(SD_AUDIT_PIPE, 1, sysdir, who, text);",
     "return win32_audit_pipe_to(SD_AUDIT_PIPE, 0, sysdir, who, text);"),
    ("sdsvc/sdaudit.c", "the server takes a pid it was not given by the pipe", "  if (!GetNamedPipeClientProcessId(h, &pid))\n    pid = 0;", "  pid = 4;"),
    ("sdsvc/sdaudit.c", "the server writes the claim as the user", "audit_format_line(line, sizeof(line), user, who, pid, msg)",
     "audit_format_line(line, sizeof(line), who, who, pid, msg)"),
    ("sdsvc/sdaudit.c", "the server does not clean the text", "  audit_clean(msg);\n", "\n"),
    ("sdsvc/sdaudit.c", "the server writes another tree's record", "  if (!audit_same_dir(dir)) {", "  if (0) {"),
    ("sdsvc/sdaudit.c", "the first instance is made without FILE_FLAG_FIRST_PIPE_INSTANCE", "(first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0)", "(first ? 0 : 0)"),
    ("sdsvc/sdaudit.c", "members may make an instance of the name",
     "#define AUDIT_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)",
     "#define AUDIT_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE | FILE_CREATE_PIPE_INSTANCE)"),
    ("sdsvc/sdaudit.c", "no rate bound", "  if (s->count >= AUDIT_RATE_MAX) {", "  if (0) {"),
    ("sdsvc/sdaudit.c", "a lock line with two line breaks is written",
     "    if ((line[i] == '\\n') || (line[i] == '\\r') || (line[i] == '\\0'))\n      return AUDIT_ANSWER_FAILED;\n", "\n"),
    ("sdsvc/sdaudit.c", "the lock trace file is made when missing", "ok = audit_append(lpath, FALSE, line, len);", "ok = audit_append(lpath, TRUE, line, len);"),
    ("sdsvc/sdaudit.c", "no rotation as the server writes", "    if (size.QuadPart >= (ULONGLONG)AUDIT_ROTATE_BYTES) {", "    if (0) {"),
    ("sdsvc/sdaudit.c", "a missing trail is made with the directory's DACL", "    sa.lpSecurityDescriptor = audit_trail_sd;", "    sa.lpSecurityDescriptor = NULL;"),
    ("win32audit.c", "the rotation leaves the new trail's DACL unprotected",
     "                              DACL_SECURITY_INFORMATION |\n                                  PROTECTED_DACL_SECURITY_INFORMATION,",
     "                              DACL_SECURITY_INFORMATION,"),
    ("k_error.c", "audit_message() appends before it asks the service",
     "  if (win32_audit_pipe(sd_sysdir(), who, pmsg) == 0)\n    return;\n", "  (void)0;\n"),
    ("sdsvc/sdaudit.c", "the server goes on after a failed revert", "      ExitProcess(1);\n", "\n"),
    ("sdsvc/sdsvc.c", "the service starts SD before the writer", "  svc_audit_start();\n", "\n"),
    ("op_lock.c", "lock_trace() writes nothing to the service", "  win32_locktrace_pipe(sd_sysdir(), buff, bytes);", "  (void)buff;"),
]


def main():
    print("test-auditwriter-units: sources under %s" % SRC)
    if not os.path.isfile(UCRT_CC):
        print("NO TREE: no UCRT64 gcc at %s" % UCRT_CC)
        return 2
    t = {rel: read(rel) for rel in BUILT + TEXTS}
    work = tempfile.mkdtemp(prefix="auditwriter-")
    try:
        ok, msg = msys_compile(work, t)
        if ok is None:
            print("  [skip] W0 no MSYS2 bash: win32auditpipe.c not compiled as sd.exe compiles it")
            bad = 0
        else:
            print("  [%s] W0 win32auditpipe.c compiles with the MSYS2 gcc, as sd.exe builds it%s" % ("PASS" if ok else "FAIL", "" if ok else " -- " + msg[:1500]))
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
