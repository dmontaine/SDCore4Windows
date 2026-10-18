#!/usr/bin/env python3
"""test-newvocmods-units.py - NEWVOC.MODS across an upgrade (QM4 Fixes item 501), as invariants.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-newvocmods-units.py
  python3 .../test-newvocmods-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

WHAT THIS IS AND IS NOT.  It reads deletesdcore.sh, installsdcore.sh and gpl.bp/bbproc as TEXT.  It cannot run an
upgrade.  What it says is that the chain is still written and in the right order:
  deletesdcore.sh  saves @SDSYS/newvoc.mods to /home/sd, and not on a DELETE cycle, before it removes the sdsys directory;
  installsdcore.sh puts it back from /home/sd to the sdsys directory BEFORE "Bootstrap pass 1" (bbproc runs in pass 1);
  bbproc           opens @sdsys:@ds:'newvoc.mods' AFTER the VOC is filled from voc_template, so a record there wins.
That bbproc really writes the record into SDSYS's VOC is tested by sandbox-oq2.py (row 501), which builds a sandbox with a
newvoc.mods present before pass 1.  --selftest breaks each fact in turn and requires the check to say so.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DELETE = os.path.join(REPO, "deletesdcore.sh")
INSTALL = os.path.join(REPO, "installsdcore.sh")
BBPROC = os.path.join(REPO, "sdb_ai", "sd64", "sdsys", "gpl.bp", "bbproc")


def slurp(p):
    with open(p, encoding="latin-1") as f:
        return f.read()


def checks(delete, install, bbproc):
    res = []

    def ck(name, ok, detail=""):
        res.append((name, bool(ok), detail))

    # deletesdcore.sh
    save = delete.find('"$sdsysdir/newvoc.mods" "$acct_path/"')
    rmsys = delete.find('sudo rm -fr "$sdsysdir"')
    ck("D1 deletesdcore.sh copies @SDSYS/newvoc.mods to the account path", save >= 0)
    ck("D2 ... before it removes the sdsys directory", 0 <= save < rmsys, "save at %d, rm at %d" % (save, rmsys))
    blk = delete[max(0, save - 200):save + 60] if save >= 0 else ""
    ck("D3 ... only when the cycle is not DELETE", '"$keep_accts" != "DELETE"' in blk)
    # installsdcore.sh
    rest = install.find('sudo mv "/home/sd/newvoc.mods" "$sdsysdir/"')
    pass1 = install.find('echo "Bootstrap pass 1."')
    ck("I1 installsdcore.sh moves /home/sd/newvoc.mods back into the sdsys directory", rest >= 0)
    ck("I2 ... before bootstrap pass 1", 0 <= rest < pass1, "restore at %d, pass 1 at %d" % (rest, pass1))
    ck("I3 ... owned sdsys:sdusers", 'chown -R sdsys:sdusers "$sdsysdir/newvoc.mods"' in install)
    ck("I4 ... and only when the saved copy is there", 'if [ -d "/home/sd/newvoc.mods" ]' in install)
    # bbproc
    tmpl = bbproc.find("select voc_t.f to 2")
    mods = bbproc.find("openpath @sdsys:@ds:'newvoc.mods'")
    wr = bbproc.find("write voc_item on voc, id", mods) if mods >= 0 else -1
    ck("B1 bbproc opens @sdsys:@ds:'newvoc.mods'", mods >= 0)
    ck("B2 ... after the VOC is filled from voc_template", 0 <= tmpl < mods, "template at %d, mods at %d" % (tmpl, mods))
    ck("B3 ... and writes its records to the VOC", wr > mods >= 0)
    return res


def selftest():
    d, i, b = slurp(DELETE), slurp(INSTALL), slurp(BBPROC)
    base = checks(d, i, b)
    bad = [n for n, ok, _ in base if not ok]
    if bad:
        print("selftest: the real files already fail: %s" % bad)
        return False
    cp_line = 'sudo cp -a "$sdsysdir/newvoc.mods" "$acct_path/"'
    mv_line = '    sudo mv "/home/sd/newvoc.mods" "$sdsysdir/"'
    mutants = [
        ("delete: no save", lambda: (d.replace('"$sdsysdir/newvoc.mods" "$acct_path/"', "x"), i, b), "D1"),
        ("delete: save moved after the rm of sdsys", lambda: (d.replace(cp_line, "true") + "\n" + cp_line + "\n", i, b), "D2"),
        ("delete: saves on DELETE too", lambda: (d.replace('[ "$keep_accts" != "DELETE" ] && [ -d "$sdsysdir/newvoc.mods" ]', '[ -d "$sdsysdir/newvoc.mods" ]'), i, b), "D3"),
        ("install: no restore", lambda: (d, i.replace('sudo mv "/home/sd/newvoc.mods" "$sdsysdir/"', "true"), b), "I1"),
        ("install: restore moved after pass 1", lambda: (d, i.replace(mv_line, "    true").replace('echo "Bootstrap pass 1."', 'echo "Bootstrap pass 1."\n' + mv_line, 1), b), "I2"),
        ("install: wrong owner", lambda: (d, i.replace('chown -R sdsys:sdusers "$sdsysdir/newvoc.mods"', "true"), b), "I3"),
        ("bbproc: no newvoc.mods", lambda: (d, i, b.replace("openpath @sdsys:@ds:'newvoc.mods'", "openpath @sdsys:@ds:'newvoc.none'")), "B1"),
        ("bbproc: applied before the template", lambda: (d, i, b.replace("openpath @sdsys:@ds:'newvoc.mods' to voc_m.f", "openpath @sdsys:@ds:'newvoc.zzz' to voc_m.f").replace("select voc_t.f to 2", "openpath @sdsys:@ds:'newvoc.mods' to x.f else null\nselect voc_t.f to 2", 1)), "B2"),
        ("bbproc: never written", lambda: (d, i, b.replace("      write voc_item on voc, id\n    end\n    goto voc_mod_nxt", "      null\n    end\n    goto voc_mod_nxt")), "B3"),
    ]
    ok = True
    for name, make, want in mutants:
        res = checks(*make())
        failed = [n.split()[0] for n, passed, _ in res if not passed]
        caught = bool(failed) if want is None else (want in failed)
        print("  [%s] selftest: %s%s" % ("PASS" if caught else "FAIL", name, "" if caught else " (NOT CAUGHT; failed: %s)" % failed))
        ok = ok and caught
    return ok


def main():
    for p in (DELETE, INSTALL, BBPROC):
        if not os.path.isfile(p):
            print("test-newvocmods-units: CANNOT RUN - %s missing" % p)
            return 2
    if "--selftest" in sys.argv:
        return 0 if selftest() else 1
    res = checks(slurp(DELETE), slurp(INSTALL), slurp(BBPROC))
    failed = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    print("\ntest-newvocmods-units: %d passed, %d failed" % (len(res) - failed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
