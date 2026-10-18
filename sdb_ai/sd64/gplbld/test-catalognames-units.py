#!/usr/bin/env python3
#
# test-catalognames-units.py - no two programs in sdsys/gpl.bp are catalogued under the same name, and every function bcomp
# knows by name is catalogued by exactly one program.  Read off the source.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-catalognames-units.py [--selftest]
#
# No sudo, no install, no sd.  Exit 0 every check held, 1 one did not.  --selftest plants a duplicate in a copy of the
# sources and expects it to be caught.
#
# START-HISTORY:
# 15 Oct 26 dm  Written after the MERGELIST() function of QM4 gaps bundle Q-2 was given the catalogue name !mergelist, which
#               the subroutine in _mergelist already held.  The sandbox build compiles the programs in the order the
#               directory is read, and the last to be catalogued wins, so the same tree gave a working MERGELIST() in one
#               directory and the subroutine in a copy of it: a regression run on a snapshot failed six rows that the live
#               tree passed.  A catalogue name is compared without regard to case, as the catalogue is.
# END-HISTORY
#
# WHAT IT CHECKS
#   1. no catalogue name ($catalog or $catalogue, at the start of a line) is given by two programs.
#   2. each call name in bcomp's builtin.functions.load table (the functions SD writes in BASIC and the compiler knows by
#      name) is the catalogue name of exactly one program.

import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)

passed = failed = 0


def say(s=""):
    print(s)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def catalog_names(bpdir):
    """{lower case catalogue name: [program, ...]} for every program in bpdir that has a $catalog line."""
    names = {}
    for prog in sorted(os.listdir(bpdir)):
        path = os.path.join(bpdir, prog)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            for line in f.read().decode("latin-1").splitlines():
                m = re.match(r"\$catalog(?:ue)?[ \t]+(\S+)", line, re.I)
                if m:
                    names.setdefault(m.group(1).lower(), []).append(prog)
    return names


def builtin_call_names(bcomp):
    """The call names (second field) of the rows bf.rows is given in builtin.functions.load."""
    with open(bcomp, "rb") as f:
        text = f.read().decode("latin-1")
    return re.findall(r'bf\.rows\s*:?=\s*(?:@fm:)?"[^,"]+,([^,"]+),', text)


def run(bpdir, bcomp):
    names = catalog_names(bpdir)
    dups = {n: p for n, p in names.items() if len(p) > 1}
    row("no catalogue name is given by two programs (%d names read)" % len(names), not dups,
        "; ".join("%s: %s" % (n, " ".join(p)) for n, p in sorted(dups.items())))
    calls = builtin_call_names(bcomp)
    row("builtin.functions.load names at least one function (%d read)" % len(calls), len(calls) > 0, "the pattern found no rows")
    for c in calls:
        owners = names.get(c.lower(), [])
        row("the built-in function's call name %s is catalogued by one program" % c, len(owners) == 1, "held by %r" % (owners,))


def selftest():
    global passed, failed
    bpdir = os.path.join(SD64, "sdsys", "gpl.bp")
    bcomp = os.path.join(bpdir, "bcomp")
    tmp = tempfile.mkdtemp(prefix="catnames.")
    try:
        copy = os.path.join(tmp, "bp")
        os.mkdir(copy)
        for n in os.listdir(bpdir):
            if os.path.isfile(os.path.join(bpdir, n)):
                shutil.copy(os.path.join(bpdir, n), os.path.join(copy, n))
        say("--selftest: a planted duplicate must be caught, a planted missing owner must be caught")
        with open(os.path.join(copy, "zzdup"), "w") as f:
            f.write("subroutine zzdup\n$catalog !SORTCOMPARE\nend\n")
        p0, f0 = passed, failed
        run(copy, bcomp)
        caught = failed > f0
        passed, failed = p0, f0
        row("SELFTEST: two programs holding !sortcompare is reported", caught)
        os.remove(os.path.join(copy, "zzdup"))
        os.remove(os.path.join(copy, "sortcompare"))
        p0, f0 = passed, failed
        run(copy, bcomp)
        caught = failed > f0
        passed, failed = p0, f0
        row("SELFTEST: a built-in function whose program is gone is reported", caught)
    finally:
        shutil.rmtree(tmp)


def main():
    say("test-catalognames-units: reading %s" % os.path.join(SD64, "sdsys", "gpl.bp"))
    if "--selftest" in sys.argv:
        selftest()
    else:
        run(os.path.join(SD64, "sdsys", "gpl.bp"), os.path.join(SD64, "sdsys", "gpl.bp", "bcomp"))
    say("\ntest-catalognames-units: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
