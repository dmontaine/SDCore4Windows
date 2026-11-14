#!/usr/bin/env python3
"""test-accnamecase-units.py - account names are lower case in the account verbs (RELEASE_1.1 288, 13 Nov 2026).

Linux's MODIFY.ACCOUNT downcases the account name (13 Sep 26, plan M); here CREATE.ACCOUNT and DELETE.ACCOUNT did, while
MODIFY.ACCOUNT and GRANT/REVOKE upcased it, so their messages and audit lines named ZZWITSH (found in the VM sitting, 13 Nov).
FREE CHECK: the source read as text; no install, no sd.

  A1  each of create_account, delacc, modifya and granta sets acc.name = downcase(acc.name), and none sets it with upcase
  A2  modifya's literal account tests are lower case ('sdsys', 'sdradmin'), and the suspend-yourself test compares with
      downcase(@logname) and downcase(@who), never upcase
  CONTROL  the four programs were found and read (a check over nothing must fail)

  python sdb_ai/sd64/gplbld/test-accnamecase-units.py
  python sdb_ai/sd64/gplbld/test-accnamecase-units.py --selftest   (mutants in memory, each must turn its row red)
Exit 0 every row held, 1 a row failed, 2 a program could not be read.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp"))
PROGS = ("create_account", "delacc", "modifya", "granta")


def code(text):
    """the program without whole-line comments and without trailing ';*' comments"""
    out = []
    for line in text.split("\n"):
        if line.lstrip().startswith("*"):
            continue
        out.append(line.split(";*")[0])
    return "\n".join(out)


def checks(src):
    rows = []
    c = {k: code(v) for k, v in src.items()}
    down = [p for p in PROGS if re.search(r"^\s*acc\.name = downcase\(acc\.name\)", c[p], re.M)]
    up = [p for p in PROGS if re.search(r"^\s*acc\.name = upcase\(acc\.name\)", c[p], re.M)]
    rows.append(("A1", down == list(PROGS) and not up, "acc.name = downcase(acc.name) in %s; upcase in %s" % (down, up)))
    m = c["modifya"]
    lit_ok = "if acc.name = 'sdsys' then" in m and "if acc.name = 'sdradmin' then" in m
    lit_bad = re.findall(r"acc\.name = '[A-Z][A-Z.]*'", m)
    self_ok = "(acc.name = downcase(@logname)) or (acc.name = downcase(@who))" in m and not re.search(r"acc\.name = upcase\(@(logname|who)\)", m)
    rows.append(("A2", lit_ok and not lit_bad and self_ok, "lower literals %s, upper literals %s, suspend-yourself test %s" % (lit_ok, lit_bad, self_ok)))
    return rows


def load():
    src = {}
    for p in PROGS:
        path = os.path.join(BP, p)
        with open(path, encoding="latin-1") as f:
            src[p] = f.read()
    return src


def run(src):
    print("reading %s from %s" % (", ".join(PROGS), BP))
    print("  [%s] CONTROL the four programs were read (%s characters)" % ("PASS" if all(src.values()) else "FAIL", sum(len(v) for v in src.values())))
    bad = 0 if all(src.values()) else 1
    for name, ok, detail in checks(src):
        print("  [%s] %s  %s" % ("PASS" if ok else "FAIL", name, detail))
        bad += 0 if ok else 1
    print("test-accnamecase-units: %s" % ("every row held" if bad == 0 else "%d row(s) failed" % bad))
    return 1 if bad else 0


def selftest(src):
    if any(not ok for _, ok, _ in checks(src)):
        print("  [FAIL] the real files do not pass; no mutant run")
        return 1
    mutants = [
        ("modifya upcases again", "A1", "modifya", "acc.name = downcase(acc.name)", "acc.name = upcase(acc.name)"),
        ("granta upcases again", "A1", "granta", "acc.name = downcase(acc.name)", "acc.name = upcase(acc.name)"),
        ("delacc keeps the case typed", "A1", "delacc", "acc.name = downcase(acc.name)", "acc.name = acc.name"),
        ("modifya tests 'SDSYS'", "A2", "modifya", "if acc.name = 'sdsys' then", "if acc.name = 'SDSYS' then"),
        ("modifya tests 'SDRADMIN'", "A2", "modifya", "if acc.name = 'sdradmin' then", "if acc.name = 'SDRADMIN' then"),
        ("suspend-yourself compares upper case", "A2", "modifya", "(acc.name = downcase(@logname))", "(acc.name = upcase(@logname))"),
    ]
    missed = 0
    for what, row, prog, old, new in mutants:
        if src[prog].count(old) != 1:
            print("  [MISSED] %s: the text is in %s %d times, wanted once" % (what, prog, src[prog].count(old)))
            missed += 1
            continue
        m = dict(src)
        m[prog] = src[prog].replace(old, new, 1)
        red = [n for n, ok, _ in checks(m) if not ok]
        if row in red:
            print("  [caught] %s by %s" % (what, row))
        else:
            print("  [MISSED] %s: red %s, wanted %s" % (what, red, row))
            missed += 1
    print("self-test: %d mutants, %d not caught" % (len(mutants), missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    try:
        s = load()
    except OSError as e:
        print("COULD NOT RUN: %s" % e)
        sys.exit(2)
    sys.exit(selftest(s) if "--selftest" in sys.argv else run(s))
