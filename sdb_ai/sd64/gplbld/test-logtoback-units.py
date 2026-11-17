"""test-logtoback-units.py - the administrator's way back to SDSYS with LOGTO (RELEASE_1.1 310), held in the source.

    python test-logtoback-units.py              the checks
    python test-logtoback-units.py --selftest   each mutant below must turn a check red (the live files are not touched)

Owner, 15 Nov 2026: "the admin needs to be able to logto a users account and then log back to sdsys without having to log out
each time".  Linux b9e63f17 (S.246) asks K$ADMINISTRATOR, which its LOGTO keeps; Windows clears that flag leaving SDSYS, so the
Windows form asks kernel key 174, K$OS.SDSYS.USER (agreed with Linux, mail T1625): the process token is the LOCAL account SDSYS
by SID, an interactive logon, elevated.  These checks hold that the gate is exactly that and nothing wider:

  K1  keys.h and int$keys.h both define the key as 174
  K2  op_kernel.c answers it from win32_sdsys_desktop_ok() and reads no argument
  W1  win32_sdsys_desktop_ok() compares the token's user with the LOCAL SDSYS by SID (EqualSid), as win32_job_token_ok() does
  W2  ...requires INTERACTIVE, refuses NETWORK, and requires BUILTIN\\Administrators enabled
  C1  cproc refuses LOGTO SDSYS unless the key says yes, before any register read (the refusal is 10002, audited)
  C2  ...run.in's refusal (15073) comes BEFORE it, so a run cannot come back this way
  C3  ...the way back enters @sdsys itself (never a register path) and is the only thing that skips logto.authorised

It cannot say the key answers 1 for a real SDSYS desktop and 0 for anything else: that is the VM witness the row owes.
Exit 0 all pass, 1 a check failed, 2 could not run.

START-HISTORY:
15 Nov 26  New (RELEASE_1.1 310).
END-HISTORY
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.normpath(os.path.join(HERE, os.pardir))
FILES = {
    "keys": "gplsrc/keys.h",
    "intkeys": "sdsys/gpl.bp/int$keys.h",
    "opk": "gplsrc/op_kernel.c",
    "jm": "gplsrc/win32jobmark.c",
    "cproc": "sdsys/gpl.bp/cproc",
}


def load():
    out = {}
    for k, rel in FILES.items():
        p = os.path.join(SD, rel)
        if not os.path.isfile(p):
            print("CANNOT RUN: %s not found" % p)
            sys.exit(2)
        with open(p, encoding="latin-1") as f:
            out[k] = f.read().replace("\r\n", "\n")
    return out


def code_c(s):
    return re.sub(r"/\*.*?\*/", "", s, flags=re.S)


def code_b(s):
    return "\n".join(re.sub(r"\s*;\*.*$", "", ln) for ln in s.split("\n") if not ln.lstrip().startswith("*"))


def between(s, a, b):
    i = s.find(a)
    if i < 0:
        return ""
    j = s.find(b, i + len(a))
    return s[i:j if j > 0 else len(s)]


def checks(s):
    rows = []

    def ck(name, ok, why=""):
        rows.append((name, bool(ok), why))

    ck("K1 keys.h K_OS_SDSYS_USER and int$keys.h K$OS.SDSYS.USER are both 174",
       re.search(r"^#define K_OS_SDSYS_USER\s+174\b", s["keys"], re.M) and re.search(r"^\s*\$define K\$OS\.SDSYS\.USER\s+174\b", s["intkeys"], re.M))
    opk = code_c(s["opk"])
    case = between(opk, "case K_OS_SDSYS_USER:", "break;")
    ck("K2 op_kernel.c answers K_OS_SDSYS_USER from win32_sdsys_desktop_ok() and reads no argument",
       "result.data.value = win32_sdsys_desktop_ok(" in case and "k_get" not in case and "descr" not in case, case[:120])
    jm = code_c(s["jm"])
    fn = between(jm, "int win32_sdsys_desktop_ok(char *why, size_t whylen)\n{", "\nint win32_job_admin_path")
    ck("W1 win32_sdsys_desktop_ok() compares the process user with the LOCAL SDSYS by SID",
       'snprintf(acct, sizeof(acct), "%s\\\\SDSYS", comp);' in fn and "LookupAccountNameA(NULL, acct" in fn and "use != SidTypeUser" in fn
       and "if (!EqualSid(user, (PSID)sbuf)) {" in fn and "OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)" in fn)
    ck("W2 ...and requires an interactive, non-network, elevated token, every failure answering 0",
       "member(WinInteractiveSid, &inter)" in fn and "member(WinNetworkSid, &net)" in fn and "member(WinBuiltinAdministratorsSid, &admins)" in fn
       and "if (!inter || net) {" in fn and "if (!admins) {" in fn and fn.count("return 1;") == 1)
    cp = code_b(s["cproc"])
    lg = between(cp, "\nint.logto:", "\nlogto.authorised:")
    ri = lg.find("if ri.active then")
    # 17 Nov 26 - four-version audit round 1 (P-3266): Linux's forms - the name compared lower case, 10002 shown a line at a time
    # (lg.msg), and Linux's audit words.
    gate = lg.find("into.sdsys = (downcase(new.account) = \"sdsys\")")
    refuse = lg.find("if into.sdsys and not(kernel(K$OS.SDSYS.USER, -1)) then")
    msg = lg.find("lg.msg = sysmsg(10002)", refuse)
    audit = lg.find("void kernel(K$AUDIT, 'logto refused account=sdsys reason=sdsys is entered by its own session only')", refuse)
    reg = lg.find("openpath @sdsys:@ds:'accounts' to acc.f then")
    ck("C1 cproc refuses LOGTO SDSYS unless K$OS.SDSYS.USER, before the register is read (10002, audited)",
       0 <= gate < refuse < msg < audit < reg and lg.count("K$OS.SDSYS.USER") == 1, "gate %d refuse %d msg %d audit %d reg %d" % (gate, refuse, msg, audit, reg))
    ck("C2 ...run.in's refusal (15073) comes before it", 0 <= ri < refuse and "display sysmsg(15073" in lg[ri:refuse])
    back = lg.find("if into.sdsys then\n      acc.rec = @sdsys\n      new.account = 'sdsys'\n   end")
    auth = lg.find("if into.sdsys then logto.ok = @true else gosub logto.authorised")
    ck("C3 ...the way back enters @sdsys itself after the register read, and only into.sdsys skips logto.authorised",
       reg < back < auth and lg.count("gosub logto.authorised") == 1 and lg.count("logto.ok = @true") == 1, "back %d auth %d" % (back, auth))
    return rows


MUTANTS = [
    ("cproc", "the gate is not asked", "if into.sdsys and not(kernel(K$OS.SDSYS.USER, -1)) then", "if into.sdsys and @false then"),
    ("cproc", "the way back takes the register's path", "      acc.rec = @sdsys\n      new.account = 'sdsys'", "      new.account = 'sdsys'"),
    ("cproc", "every account skips the group test", "if into.sdsys then logto.ok = @true else gosub logto.authorised", "logto.ok = @true"),
    ("jm", "a network logon is let in", "    if (!inter || net) {", "    if (!inter) {"),
    ("jm", "an unelevated token is let in", "    if (!admins) {\n        snprintf(why, whylen, \"the process is not elevated\");\n        return 0;\n    }\n    return 1;\n}\n\nint win32_job_admin_path",
     "    return 1;\n}\n\nint win32_job_admin_path"),
    ("jm", "any account named SDSYS (no SID test)", "    if (!EqualSid(user, (PSID)sbuf)) {\n        snprintf(why, whylen, \"the process is not the local account SDSYS\");\n        return 0;\n    }\n    if (!member(WinNetworkSid",
     "    if (!member(WinNetworkSid"),
    ("opk", "the key reads a caller's argument", "      result.data.value = win32_sdsys_desktop_ok(sdsys_why, sizeof(sdsys_why)) ? 1 : 0;", "      k_get_int(descr);\n      result.data.value = 1;"),
]


def main():
    s = load()
    if "--selftest" in sys.argv:
        base_red = [r[0] for r in checks(s) if not r[1]]
        if base_red:
            print("CANNOT SELFTEST: the live files already fail %s; a mutant could not be told from them" % base_red)
            return 2
        bad = 0
        for key, what, old, new in MUTANTS:
            if old not in s[key]:
                print("  [MUTANT CANNOT APPLY] %s: %s" % (key, what))
                bad += 1
                continue
            m = dict(s)
            m[key] = s[key].replace(old, new, 1)
            red = [r[0] for r in checks(m) if not r[1]]
            print("  [%s] %s: %s%s" % ("CAUGHT" if red else "MISSED", key, what, (" -> " + red[0][:40]) if red else ""))
            if not red:
                bad += 1
        print("test-logtoback-units --selftest: %d of %d mutants caught" % (len(MUTANTS) - bad, len(MUTANTS)))
        return 1 if bad else 0
    rows = checks(s)
    for name, ok, why in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, ("   <- " + why) if (not ok and why) else ""))
    if len(rows) != 7:
        print("CANNOT RUN: expected 7 checks, made %d" % len(rows))
        return 2
    failed = sum(1 for r in rows if not r[1])
    print("test-logtoback-units: %d checks, %d failed" % (len(rows), failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
