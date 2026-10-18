#!/usr/bin/env python3
"""test-newvocmods-units.py - NEWVOC.MODS in bbproc (QM4 Fixes item 501), as invariants.

  python gplbld/test-newvocmods-units.py
  python gplbld/test-newvocmods-units.py --selftest

No install, no elevation, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

18 Oct 26 Windows port - ADAPTED FROM LINUX ddd991e, NOT COPIED.  Linux's guard also reads deletesdcore.sh and installsdcore.sh,
which save newvoc.mods across a delete and put it back before bootstrap pass 1 (rows D1-D3 and I1-I4 there).  This tree has
neither script: the installer is sd.iss, whose upgrade.iss replaces shipped files and leaves the user's own, and bbproc runs when
the tree is staged (stage.py --bootstrap), not on the user's machine.  So only the bbproc half is carried, as rows B1-B3:
  bbproc opens @sdsys:@ds:'newvoc.mods' AFTER the VOC is filled from voc_template, so a record there wins, and writes it to the VOC.
It reads bbproc as TEXT.  --selftest breaks each fact in turn and requires the check to say so.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BBPROC = os.path.join(HERE, "..", "sdsys", "gpl.bp", "bbproc")


def slurp(p):
    with open(p, encoding="latin-1") as f:
        return f.read()


def checks(bbproc):
    res = []

    def ck(name, ok, detail=""):
        res.append((name, bool(ok), detail))

    tmpl = bbproc.find("select voc_t.f to 2")
    mods = bbproc.find("openpath @sdsys:@ds:'newvoc.mods'")
    wr = bbproc.find("write voc_item on voc, id", mods) if mods >= 0 else -1
    ck("B1 bbproc opens @sdsys:@ds:'newvoc.mods'", mods >= 0)
    ck("B2 ... after the VOC is filled from voc_template", 0 <= tmpl < mods, "template at %d, mods at %d" % (tmpl, mods))
    ck("B3 ... and writes its records to the VOC", wr > mods >= 0)
    return res


def selftest():
    b = slurp(BBPROC)
    base = checks(b)
    bad = [n for n, ok, _ in base if not ok]
    if bad:
        print("selftest: the real file already fails: %s" % bad)
        return False
    mutants = [
        ("bbproc: no newvoc.mods", b.replace("openpath @sdsys:@ds:'newvoc.mods'", "openpath @sdsys:@ds:'newvoc.none'"), "B1"),
        ("bbproc: applied before the template", b.replace("openpath @sdsys:@ds:'newvoc.mods' to voc_m.f", "openpath @sdsys:@ds:'newvoc.zzz' to voc_m.f").replace("select voc_t.f to 2", "openpath @sdsys:@ds:'newvoc.mods' to x.f else null\nselect voc_t.f to 2", 1), "B2"),
        ("bbproc: never written", b.replace("      write voc_item on voc, id\n    end\n    goto voc_mod_nxt", "      null\n    end\n    goto voc_mod_nxt"), "B3"),
    ]
    ok = True
    for name, text, want in mutants:
        res = checks(text)
        failed = [n.split()[0] for n, passed, _ in res if not passed]
        caught = want in failed
        print("  [%s] selftest: %s%s" % ("PASS" if caught else "FAIL", name, "" if caught else " (NOT CAUGHT; failed: %s)" % failed))
        ok = ok and caught
    return ok


def main():
    if not os.path.isfile(BBPROC):
        print("test-newvocmods-units: CANNOT RUN - %s missing" % os.path.normpath(BBPROC))
        return 2
    print("test-newvocmods-units: reading %s" % os.path.normpath(BBPROC))
    if "--selftest" in sys.argv:
        return 0 if selftest() else 1
    res = checks(slurp(BBPROC))
    failed = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    print("\ntest-newvocmods-units: %d passed, %d failed" % (len(res) - failed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
