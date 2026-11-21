#!/usr/bin/env python3
"""test-accwaits-units.py - RELEASE_1.1 373: account making says what it is doing before each wait over 2 s.

WHY (VM sit12, 21 Nov 2026).  remote.sdsys on took about 10 s with no word before the wait.  The owner's rule of 12 Nov: anything over 2 s
says first what it is doing.  Making the Windows account runs PowerShell twice - create_user, then the password write inside !set_passwd -
and neither said anything.  Message 12944, "Making the change (a few seconds)...", is the line the other verbs use.

THE RULES, read from the programs themselves:
  W1  gpl.bp/create_account displays sysmsg(12944) before it calls create_user(acc.uname), in the same branch (the one create_user call).
  W2  gpl.bp/set_passwd displays sysmsg(12944) AFTER the last password read (input pw2 HIDDEN) and BEFORE the ps_script(ps) that sets the
      password: a line printed before the prompts would announce a wait the person has not started, and one after the script would be late.
  W3  message 12944 is there and says "a few seconds".
THE NULL CASE IS REFUSED (a program that is not found is exit 2).  --selftest breaks each rule in memory; each break must turn its row red;
the live files are not written (SHA-256 before and after).

  python gplbld/test-accwaits-units.py            exit 0 all rows passed, 1 a row failed, 2 it could not run
  python gplbld/test-accwaits-units.py --selftest
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp"))
MSG = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys", "messages", "12944"))
FILES = {"create": os.path.join(BP, "create_account"), "passwd": os.path.join(BP, "set_passwd"), "msg": MSG}


def read(p):
    with open(p, "rb") as f:
        return f.read().decode("utf-8", errors="replace").replace("\r\n", "\n")


def code(t):
    """SD BASIC without whole-line comments and ;* tails."""
    return "\n".join(ln.split(";*")[0] for ln in t.split("\n") if not re.match(r"^\s*(\*|!|rem\b)", ln, re.I))


def rows(t):
    out = []
    c = code(t["create"])
    i_w = c.find("display sysmsg(12944)")
    i_u = c.find("create_user(acc.uname)")
    out.append(("W1", "create_account displays 12944 before it calls create_user(acc.uname)",
                i_w >= 0 and i_u > i_w and c.count("create_user(acc.uname)") == 1 and i_u - i_w < 400))
    p = code(t["passwd"])
    last_pw = p.rfind("input pw2 HIDDEN")
    i_w2 = p.find("display sysmsg(12944)")
    i_ps = p.find("stat = ps_script(ps)")
    out.append(("W2", "set_passwd displays 12944 after the last password read and before ps_script(ps)",
                last_pw >= 0 and i_w2 > last_pw and 0 < i_ps - i_w2 < 200))
    m = t["msg"]
    out.append(("W3", "message 12944 says a few seconds", "a few seconds" in m))
    return out


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()[:12]


def main():
    missing = [p for p in FILES.values() if not os.path.isfile(p)]
    if missing:
        print("test-accwaits-units: cannot run - not found: " + ", ".join(missing))
        return 2
    t = {k: read(p) for k, p in FILES.items()}
    bad = 0
    for k, what, ok in rows(t):
        print("  [%s] %s %s" % ("PASS" if ok else "FAIL", k, what))
        bad += (not ok)
    print("test-accwaits-units: %d rows, %d failed" % (3, bad))
    return 1 if bad else 0


MUTANTS = [
    ("create_account loses its wait line", "create", "         display sysmsg(12944)   ;* Making the change (a few seconds)...\n         if not(create_user", "         if not(create_user", "W1"),
    ("create_account says it after create_user", "create", "         display sysmsg(12944)   ;* Making the change (a few seconds)...\n         if not(create_user(acc.uname)) then",
     "         if not(create_user(acc.uname)) then", "W1"),
    ("set_passwd loses its wait line", "passwd", "   display sysmsg(12944)   ;* Making the change (a few seconds)...\n   stat = ps_script(ps)", "   stat = ps_script(ps)", "W2"),
    ("set_passwd says it before the prompts", "passwd", "   display sysmsg(12944)   ;* Making the change (a few seconds)...\n   stat = ps_script(ps)",
     "   stat = ps_script(ps)", "W2"),
    ("message 12944 changes its words", "msg", "a few seconds", "a while", "W3"),
]


def selftest():
    live = {k: p for k, p in FILES.items()}
    before = {k: sha(p) for k, p in live.items() if os.path.isfile(p)}
    t = {k: read(p) for k, p in FILES.items()}
    print("live files, SHA-256 before: " + " ".join("%s %s" % (k, v) for k, v in before.items()))
    ok0 = all(ok for _, _, ok in rows(t))
    print("  [%s] control: the unbroken text passes every row" % ("PASS" if ok0 else "FAIL"))
    caught = missed = 0
    for name, key, old, new, row in MUTANTS:
        n = t[key].count(old)
        if n != 1:
            print("  [FAIL] %s: the planted text was found %d times (want 1)" % (name, n))
            missed += 1
            continue
        m = dict(t)
        m[key] = t[key].replace(old, new, 1)
        if name == "set_passwd says it before the prompts":
            # the same line, moved up in front of the first prompt
            m[key] = m[key].replace("   crt sysmsg(10920)  ;* the rule, said before it is applied\n",
                                    "   display sysmsg(12944)\n   crt sysmsg(10920)  ;* the rule, said before it is applied\n", 1)
        if name == "create_account says it after create_user":
            # the same line, moved down to after the user is made
            m[key] = m[key].replace("         crt sysmsg(10007,acc.uname)", "         display sysmsg(12944)\n         crt sysmsg(10007,acc.uname)", 1)
        red = [r for r, _, ok in rows(m) if not ok]
        if row in red:
            caught += 1
            print("  [pass] %s: caught by %s" % (name, row))
        else:
            missed += 1
            print("  [FAIL] %s: NOT caught (red: %s)" % (name, red))
    after = {k: sha(p) for k, p in live.items() if os.path.isfile(p)}
    print("live files unchanged: %s" % (before == after))
    print("%d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if (ok0 and not missed and before == after) else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv[1:] else main())
