#!/usr/bin/env python3
"""test-failaudit-units.py - a refused API login is audited BEFORE the failed-credential delay (S.60).

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-failaudit-units.py
  python3 .../test-failaudit-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 4 Oct 26.

THE DEFECT (measured on Debian 13 and Fedora 44, 4 Oct 2026): scram.bad.cred in APISRVR did "sleep 3" and then went to
exit.vb.scram.fail, the one place a refused login is written to the audit trail.  A client that dropped the connection
during those three seconds ended the process before the audit line was written: five of five drops at 0.6-2.5 s left no
record, while a client that waited left one.  Anyone guessing passwords over the API could therefore choose not to be
recorded.  The fix keeps the delay and takes it AFTER the record.

***WHAT THIS IS AND IS NOT.***  It reads sdsys/gpl.bp/apisrvr as text and cannot say the audit line is written; that is
measured on an install by witness-release-run.sh row A3d (the client is killed during the delay and the line must still
appear).  It says the ordering is still written, so a later edit that moves the sleep back above the record fails here
before anyone installs it.  --selftest mutates the source four ways and requires each to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APISRVR = os.path.abspath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp", "apisrvr"))


def code_lines(src):
    """[(line number, text)] with full-line comments dropped: a rule that exists only in a comment is no rule."""
    out = []
    for i, line in enumerate(src.splitlines(), 1):
        if line.lstrip().startswith("*"):
            continue
        out.append((i, line))
    return out


def find(lines, pattern, start=0):
    for n, line in lines:
        if n >= start and re.search(pattern, line):
            return n
    return None


def checks(src):
    lines = code_lines(src)
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    sleeps = [n for n, l in lines if re.match(r"\s*sleep\b", l)]
    init = find(lines, r"^scram\.fail\.delay\s*=\s*0\b")
    loop = find(lines, r"^loop\s*$")
    bad = find(lines, r"^scram\.bad\.cred:")
    exitl = find(lines, r"^exit\.vb\.scram\.fail:")
    setd = find(lines, r"^\s*scram\.fail\.delay\s*=\s*config\('PWDELAY'\)", bad or 0)
    audit = find(lines, r"kernel\(K\$AUDIT,\s*'api refused user='", exitl or 0)
    wait_if = find(lines, r"^\s*if scram\.fail\.delay\s*>\s*0\s+then", exitl or 0)
    wait = find(lines, r"^\s*sleep scram\.fail\.delay\b", exitl or 0)
    ret = find(lines, r"^\s*return\s*$", exitl or 0)

    ck("the delay variable is initialised before the main loop", init and loop and init < loop,
       "init %s, loop %s" % (init, loop))
    ck("scram.bad.cred and exit.vb.scram.fail are both there", bad and exitl and bad < exitl,
       "bad %s, exit %s" % (bad, exitl))
    ck("scram.bad.cred SETS the delay (PWDELAY, 3 by default) and does not sleep itself",
       setd and setd < (exitl or 0) and not any(bad < n < exitl for n in sleeps if bad and exitl),
       "set at %s; sleeps %s" % (setd, sleeps))
    ck("exactly one sleep in the file, and it is the delay after the record", len(sleeps) == 1 and sleeps[0] == wait,
       "sleeps at %s, wait at %s" % (sleeps, wait))
    ck("the audit record is written first, the wait after it",
       audit and wait and audit < wait, "audit %s, wait %s" % (audit, wait))
    ck("the wait is inside the 'if delay > 0' guard and the exit still returns after it",
       wait_if and wait and ret and wait_if < wait < ret, "if %s, wait %s, return %s" % (wait_if, wait, ret))
    ck("the delay is cleared after it is taken (a later refusal does not wait twice)",
       find(lines, r"^\s*scram\.fail\.delay\s*=\s*0\b", wait or 0) is not None)
    return out


def mutants(src):
    res = []
    # 1 the old form: sleep 3 in scram.bad.cred, ahead of the exit, and no delay machinery
    old = src.replace("               scram.fail.delay = config('PWDELAY')\n", "               sleep 3\n", 1)
    res.append(("the sleep is back in scram.bad.cred above the record", old))
    # 2 the wait is moved above the audit write
    m = re.search(r"(               \* The wait comes AFTER the record.*?\n               end\n)", src, re.S)
    if m:
        block = m.group(1)
        moved = src.replace(block, "", 1).replace(
            "               if scram.refuse.reason # '' then\n                  if scram.audit.name = ''",
            block + "               if scram.refuse.reason # '' then\n                  if scram.audit.name = ''", 1)
        res.append(("the wait is moved above the audit write", moved))
    # 3 the init is gone (an unassigned variable on the first refusal)
    res.append(("the delay variable is never initialised",
                re.sub(r"^scram\.fail\.delay = 0[^\n]*\n", "", src, count=1, flags=re.M)))
    # 4 the delay is dropped altogether (no longer slows a guesser)
    res.append(("the delay is never set, so nothing waits",
                src.replace("               scram.fail.delay = config('PWDELAY')\n", "", 1)))
    return res


def main():
    if not os.path.isfile(APISRVR):
        print("test-failaudit-units: CANNOT RUN - no apisrvr at %s" % APISRVR)
        return 2
    src = open(APISRVR).read()
    if "--selftest" in sys.argv:
        base = checks(src)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated source already fails:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(src)
        for name, msrc in ms:
            if msrc == src:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n for n, ok, _ in checks(msrc) if not ok]
            if caught:
                print("  [caught] %s  (%d check(s) failed)" % (name, len(caught)))
            else:
                print("  [MISSED] %s" % name)
                bad += 1
        print("test-failaudit-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    print("apisrvr : %s" % APISRVR)
    res = checks(src)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail) + ")"))
        fails += 0 if ok else 1
    print("test-failaudit-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
