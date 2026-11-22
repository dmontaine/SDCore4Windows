#!/usr/bin/env python3
"""test-credown-units.py - cred-own: a person changes their OWN SD password through the SD service (RELEASE_1.1 379, the Windows
form of Linux's "sudo sd-elevate cred-own", agreed with the Linux audit session in mail 2026-11-22T1900).

  python sdb_ai/sd64/gplbld/test-credown-units.py
  python sdb_ai/sd64/gplbld/test-credown-units.py --selftest

WHAT IT RUNS.  The service's half (gplsrc/sdsvc/sdcredown.c) and the session's half (gplsrc/win32credown.c) are COPIED to a
temporary tree and compiled NATIVELY with the UCRT64 gcc - the toolchain sdsvc.exe is built with - beside a test main, and run
UNELEVATED: the test serves a pipe of its own name over a temporary system directory (accounts\\<me>, $cred) and talks to it with
the real client code, as the Windows user running the test (its account is that user's name in lower case).  Nothing here needs
SD, an install, the service or elevation.  What it cannot show is the shipped arrangement: the pipe owned by LocalSystem, sdusers
granted, an ordinary user's MODIFY.PASSWORD through K$CRED.OWN on an install, the audit line in the real trail - the row's owed
witness.

Rows (C = the compiled code, run; W = the shipped wiring, read):
  C1  query with no record answers "OK none"
  C2  set with no credential yet and no current key writes the record (six lines, read back) and audits "cred-own set account=<me>"
  C3  query answers the record's salt and iterations
  C4  verify with a wrong key is refused ("not correct") and audited; C5 the right key is answered OK
  C6  set without the current key, when there is a credential, is refused and the record is unchanged
  C7  set with a wrong current key is refused and the record is unchanged (the PROOF is checked at the write)
  C8  set with the right current key writes the new keys
  C9  the account is the TOKEN's: the request names none, and sdsys is refused (the administrator's own path)
  C10 a register group that is not sdu_<me> (a group account's sdg_) is refused; C11 a SUSPENDED account is refused
  C12 bad input is refused: version 1, iterations 1000, a 31-byte StoredKey, a salt that is not base64, too many lines, a long line
  C13 the squat defence: a client that requires a LocalSystem owner sends NOTHING to this (user-owned) pipe - the record is unchanged
  C14 the pipe's DACL: no ACE but the owner's grants FILE_CREATE_PIPE_INSTANCE, WRITE_DAC or WRITE_OWNER; the owner is the server's
  W1  sdsvc.c starts cred-own and stops it BEFORE the audit writer at every stop site; it passes sdusers and sdaudit_write
  W2  the shipped client wrapper requires a LocalSystem owner and asks identification only
  W3  the server reverts after impersonating and never goes on as the client; it takes the account from the token, not the request
  W4  K_CRED_OWN is 86 in gplsrc/keys.h and K$CRED.OWN 86 in GPL.BP/INT$KEYS.H; op_kernel.c answers only a $internal program
  W5  set_acc_password asks the service only for a session that is not elevated (self.svc), and only for its own account
  W6  the Makefile builds sdcredown.c into sdsvc.exe and gpl.src lists win32credown (sd.exe)

Exit 0 every row held, 1 a row failed, 2 no UCRT64 gcc.  --selftest mutates the COPIED sources (the live files are never touched;
their SHA-256 is compared before and after), rebuilds, and needs a red row for every mutant.
"""
import hashlib
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

BUILT = ["win32credown.c", "win32credown.h", "sdsvc/sdcredown.c", "sdsvc/sdcredown.h"]

MAIN = r'''
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <string.h>
#include "sdcredown.h"
#include "../win32credown.h"

static char g_sysdir[MAX_PATH];
static char g_pipe[MAX_PATH];
static char g_me[80];
static char g_last_audit[600];
static int g_audits = 0;
static int g_fail = 0;

static int t_audit(const char* user, unsigned long pid, const char* msg) {
  (void)user; (void)pid;
  snprintf(g_last_audit, sizeof(g_last_audit), "%s", msg);
  g_audits++;
  return 0;
}
static void t_log(const char* fmt, ...) { (void)fmt; }

static void row(const char* id, int ok, const char* what, const char* got) {
  printf("%s %s %s%s%s\n", ok ? "PASS" : "FAIL", id, what, got ? "  | got: " : "", got ? got : "");
  if (!ok) g_fail++;
}

static void write_file(const char* path, const char* text) {
  FILE* f = fopen(path, "wb");
  if (f) { fputs(text, f); fclose(f); }
}
static void read_file(const char* path, char* buf, size_t n) {
  FILE* f = fopen(path, "rb");
  size_t k = 0;
  buf[0] = 0;
  if (f) { k = fread(buf, 1, n - 1, f); fclose(f); }
  buf[k] = 0;
}

#define SALT "QUFBQUFBQUFBQUFBQUFBQQ=="
#define K1 "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE="
#define K2 "QkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI="
#define K3 "Q0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0M="
#define K4 "RERERERERERERERERERERERERERERERERERERERE" "REQ="
#define K31 "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQQ=="

static int ask(const char* req, char* ans) {
  return win32_credown_ask_to(g_pipe, 0, req, ans, 512);
}
static void set_req(char* out, size_t n, const char* cur, const char* ver, const char* salt, const char* iter, const char* sk,
                    const char* svk) {
  snprintf(out, n, "SDCREDOWN1 set\n%s\n%s\nSCRAM-SHA-256\n%s\n%s\n%s\n%s\nEND\n", cur, ver, salt, iter, sk, svk);
}

int main(int argc, char** argv) {
  char path[MAX_PATH], cred[MAX_PATH], reg[MAX_PATH], ans[512], buf[4096], req[2048], name[200];
  DWORD nl = sizeof(name);
  int i;
  const char* grant[] = {"Users", NULL};

  if (argc < 3) return 9;
  snprintf(g_sysdir, sizeof(g_sysdir), "%s", argv[1]);
  snprintf(g_pipe, sizeof(g_pipe), "%s", argv[2]);
  GetUserNameA(name, &nl);
  if (sdcredown_account(name, g_me, sizeof(g_me)) != 0) { printf("FAIL setup the test user's name is not an account name\n"); return 1; }
  printf("INFO sysdir=%s pipe=%s user=%s account=%s\n", g_sysdir, g_pipe, name, g_me);

  snprintf(path, sizeof(path), "%s\\accounts", g_sysdir); CreateDirectoryA(path, NULL);
  snprintf(path, sizeof(path), "%s\\$cred", g_sysdir); CreateDirectoryA(path, NULL);
  snprintf(reg, sizeof(reg), "%s\\accounts\\%s", g_sysdir, g_me);
  snprintf(buf, sizeof(buf), "x\r\nx\r\nsdu_%s\r\nx\r\n\r\n", g_me);
  write_file(reg, buf);
  snprintf(cred, sizeof(cred), "%s\\$cred\\%s", g_sysdir, g_me);
  DeleteFileA(cred);

  if (sdcredown_start(g_pipe, g_sysdir, grant, t_audit, t_log) != 0) { printf("FAIL setup the server did not start\n"); return 1; }

  /* C1 */
  i = ask("SDCREDOWN1 query\nEND\n", ans);
  row("C1", i == 0 && strcmp(ans, "OK none") == 0, "query with no record answers OK none", ans);

  /* C2 */
  set_req(req, sizeof(req), "", "2", SALT, "600000", K1, K2);
  i = ask(req, ans);
  read_file(cred, buf, sizeof(buf));
  snprintf(path, sizeof(path), "2\r\nSCRAM-SHA-256\r\n%s\r\n600000\r\n%s\r\n%s\r\n", SALT, K1, K2);
  snprintf(name, sizeof(name), "cred-own set account=%s", g_me);
  row("C2", i == 0 && strncmp(ans, "OK SD password set for ", 23) == 0 && strcmp(buf, path) == 0 && strcmp(g_last_audit, name) == 0,
      "set with no credential writes the six-line record and audits it", ans);

  /* C3 */
  i = ask("SDCREDOWN1 query\nEND\n", ans);
  row("C3", i == 0 && strcmp(ans, "OK salt " SALT " iter 600000") == 0, "query answers salt and iterations", ans);

  /* C4, C5 */
  i = g_audits;
  ask("SDCREDOWN1 verify\n" K3 "\nEND\n", ans);
  row("C4", strstr(ans, "ER the current password is not correct") == ans && g_audits == i + 1 &&
      strstr(g_last_audit, "cred-own refused account=") == g_last_audit, "verify with a wrong key is refused and audited", ans);
  ask("SDCREDOWN1 verify\n" K1 "\nEND\n", ans);
  row("C5", strcmp(ans, "OK the current password is correct") == 0, "verify with the right key", ans);

  /* C6, C7 */
  set_req(req, sizeof(req), "", "2", SALT, "600000", K3, K4);
  ask(req, ans);
  read_file(cred, buf, sizeof(buf));
  row("C6", strncmp(ans, "ER ", 3) == 0 && strstr(ans, "current one is required") && strstr(buf, K1) && !strstr(buf, K3),
      "set without the current key is refused, record unchanged", ans);
  set_req(req, sizeof(req), K2, "2", SALT, "600000", K3, K4);
  ask(req, ans);
  read_file(cred, buf, sizeof(buf));
  row("C7", strstr(ans, "ER the current password is not correct") == ans && strstr(buf, K1) && !strstr(buf, K3),
      "set with a wrong current key is refused, record unchanged", ans);

  /* C8 */
  set_req(req, sizeof(req), K1, "2", SALT, "600000", K3, K4);
  ask(req, ans);
  read_file(cred, buf, sizeof(buf));
  row("C8", strncmp(ans, "OK SD password set for ", 23) == 0 && strstr(buf, K3) && strstr(buf, K4) && !strstr(buf, K1),
      "set with the right current key writes the new keys", ans);

  /* C9: the account is the token's; sdsys is refused */
  {
    char am[600];
    sdcredown_handle(g_sysdir, "sdsys", "SDCREDOWN1 query\nEND\n", ans, sizeof(ans), am, sizeof(am));
    row("C9", strncmp(ans, "ER sdsys sets passwords as the administrator", 44) == 0 &&
        strncmp(SD_CREDOWN_PIPE, "\\\\.\\pipe\\", 9) == 0, "sdsys is refused (the token's account, never the request's)", ans);
  }

  /* C10, C11 */
  snprintf(buf, sizeof(buf), "x\r\nx\r\nsdg_%s\r\nx\r\n\r\n", g_me);
  write_file(reg, buf);
  ask("SDCREDOWN1 query\nEND\n", ans);
  row("C10", strstr(ans, "is not a user's own account") != NULL, "a group account's register group is refused", ans);
  snprintf(buf, sizeof(buf), "x\r\nx\r\nsdu_%s\r\nx\r\nSUSPENDED\r\n", g_me);
  write_file(reg, buf);
  ask("SDCREDOWN1 query\nEND\n", ans);
  row("C11", strstr(ans, "is suspended") != NULL, "a suspended account is refused", ans);
  snprintf(buf, sizeof(buf), "x\r\nx\r\nsdu_%s\r\nx\r\n\r\n", g_me);
  write_file(reg, buf);

  /* C12 */
  {
    int bad = 0;
    char long_line[400];
    set_req(req, sizeof(req), K3, "1", SALT, "600000", K1, K2); ask(req, ans); bad += (strncmp(ans, "ER record version", 17) == 0);
    /* 1000: four digits, so only the 4096 floor can refuse it (100 was also refused by the length test, and hid the floor) */
    set_req(req, sizeof(req), K3, "2", SALT, "1000", K1, K2); ask(req, ans); bad += (strncmp(ans, "ER iterations", 13) == 0);
    set_req(req, sizeof(req), K3, "2", SALT, "600000", K31, K2); ask(req, ans); bad += (strncmp(ans, "ER StoredKey", 12) == 0);
    set_req(req, sizeof(req), K3, "2", "not*base64!!", "600000", K1, K2); ask(req, ans); bad += (strncmp(ans, "ER the salt", 11) == 0);
    ask("SDCREDOWN1 set\na\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nEND\n", ans); bad += (strncmp(ans, "ER ", 3) == 0);
    memset(long_line, 'A', 300); long_line[300] = 0;
    snprintf(req, sizeof(req), "SDCREDOWN1 verify\n%s\nEND\n", long_line); ask(req, ans); bad += (strstr(ans, "over 256") != NULL);
    read_file(cred, buf, sizeof(buf));
    snprintf(name, sizeof(name), "%d of 6 refused", bad);
    row("C12", bad == 6 && strstr(buf, K3), "bad input is refused (version, iterations, key size, salt, lines, length)", name);
  }

  /* C13: the squat defence - this pipe is owned by the test user, not LocalSystem */
  set_req(req, sizeof(req), K3, "2", SALT, "600000", K1, K2);
  i = win32_credown_ask_to(g_pipe, 1, req, ans, sizeof(ans));
  read_file(cred, buf, sizeof(buf));
  row("C13", i == -1 && strstr(ans, "not the service's") && strstr(buf, K3) && !strstr(buf, K1) && !strstr(buf, K2),
      "a client requiring a LocalSystem owner sends nothing to a pipe that is not the service's", ans);

  /* C14: the pipe's DACL */
  {
    HANDLE h = CreateFileA(g_pipe, READ_CONTROL, 0, NULL, OPEN_EXISTING, 0, NULL);
    PSID owner = NULL; PACL dacl = NULL; PSECURITY_DESCRIPTOR sd = NULL;
    HANDLE tok; BYTE tu[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE]; DWORD n = 0;
    int ok = 0, bad_ace = 0, aces = 0; DWORD k;
    if ((h != INVALID_HANDLE_VALUE) &&
        GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, NULL, &dacl, NULL, &sd)
          == ERROR_SUCCESS && OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok) &&
        GetTokenInformation(tok, TokenUser, tu, sizeof(tu), &n)) {
      ok = EqualSid(owner, ((TOKEN_USER*)tu)->User.Sid);
      for (k = 0; dacl && k < dacl->AceCount; k++) {
        ACCESS_ALLOWED_ACE* ace;
        if (!GetAce(dacl, k, (void**)&ace)) continue;
        aces++;
        if (EqualSid((PSID)&ace->SidStart, owner)) continue;
        if (ace->Mask & (FILE_CREATE_PIPE_INSTANCE | WRITE_DAC | WRITE_OWNER | GENERIC_ALL | GENERIC_WRITE)) bad_ace++;
      }
    }
    snprintf(name, sizeof(name), "owner ok=%d, %d ace(s), %d too wide", ok, aces, bad_ace);
    row("C14", ok && aces >= 3 && bad_ace == 0, "the pipe: owned by the server's user; no other ACE may make instances or change it", name);
    if (sd) LocalFree(sd);
    if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
  }

  sdcredown_stop();
  printf("DONE %d failed\n", g_fail);
  return g_fail ? 1 : 0;
}
'''

# (id, file under gplsrc or sd64, pattern that must match, why)
TEXT_ROWS = [
    ("W1a", "gplsrc/sdsvc/sdsvc.c", r"sdcredown_start\(SD_CREDOWN_PIPE, sysdir, credown_grant, sdaudit_write, svc_log\)",
     "the service starts cred-own over SD_CREDOWN_PIPE with the audit writer"),
    ("W1b", "gplsrc/sdsvc/sdsvc.c", r'credown_grant\[\] = \{"sdusers", NULL\}', "every SD user (sdusers) may open the pipe"),
    ("W2a", "gplsrc/win32credown.c", r"return win32_credown_ask_to\(SD_CREDOWN_PIPE, 1, ", "the shipped wrapper requires a LocalSystem owner"),
    ("W2b", "gplsrc/win32credown.c", r"SECURITY_SQOS_PRESENT \| SECURITY_IDENTIFICATION", "the client asks identification only"),
    ("W3a", "gplsrc/sdsvc/sdcredown.c", r"if \(!RevertToSelf\(\)\) \{[^}]*ExitProcess\(1\);", "a failed revert ends the service"),
    ("W3b", "gplsrc/sdsvc/sdcredown.c", r"return sdcredown_account\(name, account, acclen\) == 0;", "the account is the token user's name"),
    ("W4a", "gplsrc/keys.h", r"#define K_CRED_OWN +86\b", "K_CRED_OWN is 86"),
    ("W4b", "sdsys/gpl.bp/int$keys.h", r"\$define K\$CRED\.OWN +86\b", "K$CRED.OWN is 86"),
    ("W4c", "gplsrc/op_kernel.c", r"if \(!\(process\.program\.flags & HDR_INTERNAL\)\) \{\s*k_put_c_string\(\"ER\" FIELD_MARK_STRING \"only MODIFY",
     "only a $internal program may ask"),
    ("W5a", "sdsys/gpl.bp/set_acc_password",
     r"self\.svc = not\(kernel\(K\$OS\.ELEVATED, 0\)\) and not\(preauth<1> = 1 and preauth<3> = 1\)",
     "the service is asked only by a session that is not elevated"),
    ("W5b", "sdsys/gpl.bp/set_acc_password", r"if self\.svc and not\(own\) then\s*stop sysmsg\(2001\)",
     "and only for its own account"),
    ("W6a", "Makefile", r"\$\(SVCDIR\)/sdcredown\.c", "sdsvc.exe builds sdcredown.c"),
    ("W6b", "gpl.src", r"(?m)^win32credown$", "sd.exe builds win32credown.c"),
]


def text_rows(root):
    fails = 0
    for rid, rel, pat, why in TEXT_ROWS:
        path = os.path.join(root, rel.replace("/", os.sep))
        try:
            text = open(path, encoding="latin-1").read()
        except OSError:
            text = ""
        ok = re.search(pat, text) is not None
        print(("PASS" if ok else "FAIL") + " " + rid + " " + why + ("" if ok else "  | not found in " + rel))
        fails += 0 if ok else 1
    # W1c: every sdaudit_stop() in sdsvc.c is preceded by sdcredown_stop()
    svc = open(os.path.join(root, "gplsrc", "sdsvc", "sdsvc.c"), encoding="latin-1").read()
    stops = len(re.findall(r"sdaudit_stop\(\);", svc))
    before = len(re.findall(r"sdcredown_stop\(\);[^\n]*\n\s*sdaudit_stop\(\);", svc))
    ok = stops > 0 and stops == before
    print(("PASS" if ok else "FAIL") + " W1c cred-own stops before the audit writer at every stop site  | %d of %d" % (before, stops))
    fails += 0 if ok else 1
    return fails


def build_and_run(srcroot, work):
    """Copy the built files under srcroot/gplsrc into work, add the main, compile natively, run.  Returns (fails, output)."""
    for rel in BUILT:
        dst = os.path.join(work, "gplsrc", rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(srcroot, "gplsrc", rel.replace("/", os.sep)), dst)
    svcdir = os.path.join(work, "gplsrc", "sdsvc")
    with open(os.path.join(svcdir, "testmain.c"), "w", encoding="ascii", newline="\n") as f:
        f.write(MAIN)
    exe = os.path.join(work, "credown-test.exe")
    env = dict(os.environ)
    env["PATH"] = UCRT_BIN.replace("/", os.sep) + os.pathsep + env.get("PATH", "")
    cmd = [UCRT_CC, "-std=gnu17", "-Wall", "-Wformat=2", "-O1", "testmain.c", "sdcredown.c", os.path.join("..", "win32credown.c"),
           "-ladvapi32", "-o", exe]
    cp = subprocess.run(cmd, cwd=svcdir, env=env, capture_output=True, text=True)
    out = "BUILD: " + " ".join(cmd) + "\n" + cp.stdout + cp.stderr
    if cp.returncode != 0 or not os.path.exists(exe):
        return 1, out + "FAIL build exit %d\n" % cp.returncode
    # A warning in a SHIPPED file fails (the test's own main is allowed its snprintf truncation notes).
    shipped_warn = [l for l in cp.stderr.splitlines() if "warning:" in l and not l.startswith("testmain.c")]
    if shipped_warn:
        out += "FAIL build warnings in shipped files: " + "; ".join(shipped_warn[:3]) + "\n"
    sysdir = os.path.join(work, "sys")
    os.makedirs(sysdir, exist_ok=True)
    pipe = "\\\\.\\pipe\\sd-cred-own-test-%d-%d" % (os.getpid(), abs(hash(work)) % 100000)
    rp = subprocess.run([exe, sysdir, pipe], env=env, capture_output=True, text=True, timeout=120)
    out += rp.stdout + rp.stderr
    fails = len(re.findall(r"(?m)^FAIL", out))
    passes = len(re.findall(r"(?m)^PASS C", out))
    if passes < 14:
        out += "FAIL only %d of 14 compiled rows ran (the null case)\n" % passes
        fails += 1
    return fails, out


def sha(paths):
    h = {}
    for p in paths:
        with open(p, "rb") as f:
            h[p] = hashlib.sha256(f.read()).hexdigest()
    return h


MUTANTS = [
    ("verify always matches", "sdsvc/sdcredown.c", "  return d == 0;\n}", "  return 1;\n}", "C4"),
    ("sdsys not refused", "sdsvc/sdcredown.c", 'if (strcmp(account, "sdsys") == 0) {', 'if (strcmp(account, "sdsys-x") == 0) {', "C9"),
    ("group not checked", "sdsvc/sdcredown.c", "if (_stricmp(group, want) != 0) {", "if (0) {", "C10"),
    ("suspension not checked", "sdsvc/sdcredown.c", 'if (_stricmp(field, "SUSPENDED") == 0) {', "if (0) {", "C11"),
    ("no proof at the write", "sdsvc/sdcredown.c", "    if (!cr_same(cur, old_sk)) {", "    if (0) {", "C7"),
    ("iterations unchecked", "sdsvc/sdcredown.c", "(it < 4096)", "(it < 1)", "C12"),
    ("owner not checked", "win32credown.c", "if (need_system_owner && !credown_owner_is_system(h)) {", "if (0) {", "C13"),
    ("grant may make instances", "sdsvc/sdcredown.c",
     "#define CREDOWN_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA",
     "#define CREDOWN_PIPE_GRANT (WRITE_DAC | FILE_READ_DATA | FILE_WRITE_DATA", "C14"),
]


def main():
    if not os.path.exists(UCRT_CC):
        print("test-credown-units: no UCRT64 gcc at " + UCRT_CC)
        return 2
    print("test-credown-units: tree " + SD64)
    selftest = "--selftest" in sys.argv[1:]
    live = [os.path.join(SRC, r.replace("/", os.sep)) for r in BUILT]
    before = sha(live)

    work = tempfile.mkdtemp(prefix="credown-")
    try:
        fails, out = build_and_run(SD64, work)
        print(out.rstrip())
    finally:
        shutil.rmtree(work, ignore_errors=True)
    fails += text_rows(SD64)

    if selftest:
        caught = 0
        for name, rel, old, new, want in MUTANTS:
            mroot = tempfile.mkdtemp(prefix="credown-m-")
            try:
                for r in BUILT:
                    d = os.path.join(mroot, "gplsrc", r.replace("/", os.sep))
                    os.makedirs(os.path.dirname(d), exist_ok=True)
                    shutil.copyfile(os.path.join(SRC, r.replace("/", os.sep)), d)
                target = os.path.join(mroot, "gplsrc", rel.replace("/", os.sep))
                text = open(target, encoding="latin-1").read()
                if text.count(old) != 1:
                    print("SELFTEST FAIL mutant '%s': its text is in %s %d times, not once" % (name, rel, text.count(old)))
                    fails += 1
                    continue
                with open(target, "w", encoding="latin-1", newline="") as f:
                    f.write(text.replace(old, new))
                work = os.path.join(mroot, "w")
                os.makedirs(work)
                m_fails, m_out = build_and_run(mroot, work)
                red = re.search(r"(?m)^FAIL " + re.escape(want) + r" ", m_out) is not None
                print("SELFTEST %s mutant '%s' -> row %s %s" % ("caught" if red else "MISSED", name, want, "red" if red else "green"))
                caught += 1 if red else 0
                fails += 0 if red else 1
            finally:
                shutil.rmtree(mroot, ignore_errors=True)
        print("SELFTEST %d of %d mutants caught" % (caught, len(MUTANTS)))

    after = sha(live)
    if before != after:
        print("FAIL the live sources changed during the run")
        fails += 1
    print("test-credown-units: %s (%d failed)" % ("PASSED" if fails == 0 else "FAILED", fails))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
