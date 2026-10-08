#!/usr/bin/env python3
"""test-auditwords-units.py - every word SD writes to the audit trail is lower case.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-auditwords-units.py
    python3 .../test-auditwords-units.py --selftest        (mutants: each breakage must be caught)
    python3 .../test-auditwords-units.py --root DIR        (a gpl.bp directory to read instead)

Exit 0 every row passed, 1 a row failed, 2 it measured nothing.  NO INSTALL, NO SUDO, NO SD.

THE RULE (owner, 7 Oct 2026, in chat: "all command words ought to be lower case, rule", then "rule from long
ago ... lower case everywhere", then, asked whether the audit trail's own event names were an exception: "All
lower case").  An audit record is  <event words> key=value key=value ...  and the EVENT WORDS - the command
(create.account, modify.account route, remote.api) and the event name (elevation granted, api refused, login)
- are lower case.  What follows a key= is data and stays as it is: an account name in the case the port
registers it, the text of a reason=, what a caller typed in command=.

WHAT IS CHECKED, by reading gpl.bp (the only place BASIC writes the trail: kernel(K$AUDIT, ...)):
  A  every audit call's event words, the tokens before the first key=, hold no upper-case letter
  B  where the event words continue in a variable (remote.api <action>, modify.account route <word>), the
     variable is passed through downcase() or every literal assigned to it in that program is lower case
  C  create.account's type= value is passed through downcase() (it is a keyword of the command)
  D  the NULL CASE: fewer than 20 call sites seen is a broken reader, not a pass
Comment lines (a leading *) are not code and are not read.
"""
import glob
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GPLBP = os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp"))
CALL = re.compile(r"kernel\(\s*K\$AUDIT\s*,\s*'([^']*)'\s*(:\s*)?([^)]*)")
passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def code_lines(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f, 1):
            s = line.strip()
            if s.startswith("*") or s.startswith("!") or "$define" in line:
                continue
            yield n, line


def sites(root):
    out = []
    for p in sorted(glob.glob(os.path.join(root, "*"))):
        if not os.path.isfile(p):
            continue
        for n, line in code_lines(p):
            m = CALL.search(line)
            if m:
                out.append((os.path.basename(p), n, m.group(1), m.group(3).strip(), line.rstrip()))
    return out


def head_of(lit):
    words = []
    for t in lit.split(" "):
        if t == "" or "=" in t:
            break
        words.append(t)
    return " ".join(words)


def lower_literals_only(root, prog, var):
    """True when every  var = '<literal>'  in prog assigns a lower-case literal (and there is at least one)."""
    seen = 0
    pat = re.compile(r"\b" + re.escape(var) + r"\s*=\s*'([^']*)'")
    for n, line in code_lines(os.path.join(root, prog)):
        for m in pat.finditer(line):
            seen += 1
            if re.search(r"[A-Z]", m.group(1)):
                return False
    return seen > 0


def numeric_only(root, prog, var):
    """True when var is only ever a count: every assignment is  var = <digits>,  var += ...  or  var = var + ...
    (and there is at least one).  A count is not a command word, so it needs no downcase()."""
    seen = 0
    pat = re.compile(r"\b" + re.escape(var) + r"\s*(\+=|=)\s*([^\n;]*)")
    for n, line in code_lines(os.path.join(root, prog)):
        for m in pat.finditer(line):
            op, rhs = m.group(1), m.group(2).strip()
            if op == "+=" or re.fullmatch(r"\d+", rhs) or re.match(re.escape(var) + r"\s*\+", rhs):
                seen += 1
            else:
                return False
    return seen > 0


def run(root):
    global passed, failed
    passed = failed = 0
    ss = sites(root)
    print("reading %s: %d audit call sites" % (root, len(ss)))
    if len(ss) < 20:
        print("test-auditwords-units: NOTHING MEASURED - %d call sites (a reader that sees almost none is broken)" % len(ss))
        return 2
    bad_head = [(p, n, head_of(lit)) for p, n, lit, rest, raw in ss if re.search(r"[A-Z]", head_of(lit))]
    row("A every audit call's event words are lower case (%d sites)" % len(ss), not bad_head, repr(bad_head[:4]))
    bad_var = []
    for p, n, lit, rest, raw in ss:
        if "=" in lit or not lit.endswith(" ") or not rest:
            continue                      # the head is complete in the literal
        expr = rest.lstrip(": ").strip()
        if expr.startswith("downcase(") or re.match(r"(dcount|len|count)\(", expr):
            continue                      # downcased, or a count (a number is not a command word)
        ident = re.match(r"[A-Za-z_][A-Za-z0-9_.$]*", expr)
        if not ident or not (lower_literals_only(root, p, ident.group(0)) or numeric_only(root, p, ident.group(0))):
            bad_var.append((p, n, expr[:40]))
    row("B an event word continued in a variable is downcase()d, a count, or only ever assigned lower-case literals",
        not bad_var, repr(bad_var[:4]))
    typed = [(p, n) for p, n, lit, rest, raw in ss if lit.startswith("create.account")]
    if typed:
        ok_c = all("downcase(acc.type)" in raw for p, n, lit, rest, raw in ss if lit.startswith("create.account"))
        row("C create.account's type= value is downcase(acc.type)", ok_c, "sites: %r" % typed)
    else:
        row("C (not applicable: this tree writes no create.account audit line)", True)
    row("D the reader saw %d sites, not nothing" % len(ss), len(ss) >= 20)
    print("test-auditwords-units: %d passed, %d failed" % (passed, failed))
    return 0 if failed == 0 else 1


def selftest():
    import shutil
    base = tempfile.mkdtemp(prefix="auditwords-")
    caught = missed = 0
    try:
        def mutant(name, prog, old, new, expect_fail=True):
            nonlocal caught, missed
            d = os.path.join(base, name)
            shutil.copytree(GPLBP, d)
            p = os.path.join(d, prog)
            with open(p, encoding="utf-8", errors="replace") as f:
                t = f.read()
            if t.count(old) != 1:
                print("  [MISSED] %s: the text to change occurs %d times, not once" % (name, t.count(old)))
                missed += 1
                return
            with open(p, "w", encoding="utf-8") as f:
                f.write(t.replace(old, new))
            sys.stdout = open(os.devnull, "w")
            try:
                rc = run(d)
            finally:
                sys.stdout = sys.__stdout__
            got = (rc != 0)
            if got == expect_fail:
                print("  [%s] %s (exit %d)" % ("caught" if expect_fail else "ok", name, rc))
                caught += 1
            else:
                print("  [MISSED] %s: exit %d" % (name, rc))
                missed += 1

        sys.stdout = open(os.devnull, "w")
        try:
            rc0 = run(GPLBP)
        finally:
            sys.stdout = sys.__stdout__
        print("selftest: the real directory first (must pass): exit %d" % rc0)
        if rc0 != 0:
            return 1
        # 8 Oct 26 - FOUR MUTANTS RE-AIMED AT THIS PORT'S LINES: Linux's name text that exists only in its source (login's
        # 'initial.account', cproc's 'reason=sdsys login', delacc's PAL-24 comment).  The checker above is Linux's, untouched.
        mutant("event-name-upper", "login", "'login account=' : audit.account)", "'LOGIN account=' : audit.account)")
        mutant("command-upper", "delacc", "'delete.account account='", "'DELETE.ACCOUNT account='")
        mutant("label-half-upper", "login", "'elevation granted account=SDSYS'", "'ELEVATION granted account=SDSYS'")
        mutant("variable-not-downcased", "remoteapi", "'remote.api ' : downcase(action)", "'remote.api ' : action")
        mutant("route-word-assigned-upper", "modifya", "route.said = 'none'", "route.said = 'NONE'")
        mutant("type-value-not-downcased", "createa", "downcase(acc.type)", "acc.type")
        # controls: these must NOT be flagged
        mutant("control-upper-in-reason-text", "cproc", "' reason=not in the register')", "' reason=NOT in the register')", expect_fail=False)
        mutant("control-upper-in-a-comment", "delacc", "*  7 Oct 26 - the verb is lower case (owner's rule 7 Oct; Linux T1730).",
               "* DELETE.ACCOUNT in a comment is not code.", expect_fail=False)
        print("selftest: %d mutants/controls behaved, %d did not" % (caught, missed))
        return 0 if missed == 0 else 1
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    root = GPLBP
    if "--root" in sys.argv:
        root = sys.argv[sys.argv.index("--root") + 1]
    sys.exit(run(root))
