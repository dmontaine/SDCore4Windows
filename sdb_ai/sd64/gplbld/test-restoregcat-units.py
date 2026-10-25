#!/usr/bin/env python3
"""test-restoregcat-units.py - RESTORE.ACCOUNT looks a call name up in the global catalogue in LOWER case.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-restoregcat-units.py
  python3 .../test-restoregcat-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 18 Oct 26.

THE DEFECT (found by the docs workflow, 18 Oct 2026, from the source): gcat.restore in sdsys/gpl.bp/restorea did
`call.name = upcase(...)` and then `read gobj from gcat.f, call.name`.  The global catalogue keeps its names in lower case
(stage 3a), so the read never found an entry: "a different program is already there, left alone" (13017) could not fire, the
archive's program overwrote the one on the system, and the re-catalogued message named the program in capitals.

***WHAT THIS IS AND IS NOT.***  It reads restorea as text.  It cannot say a different program is left alone; that needs a
restore into a real account, which needs root (witness-backup.sh).  It says the lookup name is made lower case and that
the name the catalogue is read, written and reported under is that one, so putting the upcase back fails here first.
--selftest mutates the source three ways and requires each to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESTOREA = os.path.abspath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp", "restorea"))


def body(src):
    """The code lines of the gcat.restore subroutine, comments dropped: from its label to the next label in column 0."""
    lines = src.splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith("gcat.restore:")), None)
    if start is None:
        return None
    out = []
    for l in lines[start + 1:]:
        if re.match(r"^[A-Za-z][\w.]*:\s*$", l):
            break
        if l.lstrip().startswith("*"):
            continue
        out.append(l)
    return out


def checks(src):
    b = body(src)
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    ck("gcat.restore is there", b is not None)
    if b is None:
        return out
    text = "\n".join(b)
    assign = [l for l in b if re.match(r"\s*call\.name\s*=", l)]
    ck("call.name is assigned once", len(assign) == 1, "%d assignments" % len(assign))
    ck("...from downcase(): the catalogue's names are lower case", len(assign) == 1 and "downcase(" in assign[0] and "upcase(" not in assign[0],
       assign)
    ck("no upcase() anywhere in the subroutine except the one that compares CATALOG's reply without regard to case",
       [l for l in b if "upcase(" in l and "index(" not in l] == [], [l for l in b if "upcase(" in l])
    ck("the catalogue is read under call.name itself", re.search(r"read gobj from gcat\.f, call\.name then", text) is not None)
    ck("a different program already there is reported (13017) with call.name", re.search(r"sysmsg\(13017, call\.name\)", text) is not None)
    ck("CATALOG is given call.name", re.search(r"cmd = 'CATALOG '.*:call\.name:", text) is not None)
    return out


def mutants(src):
    res = []
    res.append(("the upcase() is back", src.replace("call.name = downcase(trim(field(val, '=', 1)))",
                                                    "call.name = upcase(trim(field(val, '=', 1)))", 1)))
    res.append(("the name is used as the archive wrote it", src.replace("call.name = downcase(trim(field(val, '=', 1)))",
                                                                        "call.name = trim(field(val, '=', 1))", 1)))
    res.append(("the catalogue is read under an upper-case copy", src.replace("read gobj from gcat.f, call.name then",
                                                                              "read gobj from gcat.f, upcase(call.name) then", 1)))
    return res


def main():
    if not os.path.isfile(RESTOREA):
        print("test-restoregcat-units: CANNOT RUN - no restorea at %s" % RESTOREA)
        return 2
    src = open(RESTOREA).read()
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
        print("test-restoregcat-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    print("restorea : %s" % RESTOREA)
    res = checks(src)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail) + ")"))
        fails += 0 if ok else 1
    print("test-restoregcat-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
