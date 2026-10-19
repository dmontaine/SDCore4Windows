#!/usr/bin/env python3
#
# sandbox-sselectv.py - 1.2-0 bundle B-5, sheet 209: SSELECTV file TO listvar {RIGHT.ALIGNED} {DESCENDING} - the sorted select
#                       into a select list VARIABLE, as SSELECT is into a numbered list.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-sselectv.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 209.
# END-HISTORY
#
# THE INSTRUMENT.  A session piped to `sd -internal` (as sandbox-input.py).  Two files hold ids that sort differently as text and as
# numbers; every probe prints the ids it reads back from the list variable.  Controls: SELECTV (unsorted) and SSELECT to a list
# number are as they were, and SSELECTN (the other half of the item, built 11 Oct) still works.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
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


def bail(msg):
    say("sandbox-sselectv: CANNOT RUN - " + msg)
    sys.exit(2)


def session(box, *cmds):
    say("    > " + " | ".join(cmds))
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"), env=env,
                       capture_output=True, text=True, errors="replace", timeout=180)
    return ANSI.sub("", p.stdout + p.stderr)


def tag(out, name):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % name, out)
    return None if m is None else m.group(1)


DRAIN = ("   %s = ''\n   loop\n      readnext id from lv else exit\n      %s := id : ' '\n   repeat\n")

PROG = (
    "   for t = 1 to 2\n      nm = 'zzsv':t\n      execute 'DELETE.FILE ':nm capturing j\n      execute 'CREATE.FILE ':nm capturing j\n"
    "      open nm to f else stop 'no f'\n"
    "      if t = 1 then\n         ids = 'pear':@fm:'apple':@fm:'fig':@fm:'cherry'\n"
    "      end else\n         ids = '10':@fm:'9':@fm:'1':@fm:'100'\n      end\n"
    "      for i = 1 to dcount(ids, @fm) ; write 'r' on f, ids<i> ; next i\n   next t\n"
    "   open 'zzsv1' to f1 else stop 'no f1'\n   open 'zzsv2' to f2 else stop 'no f2'\n"
    "   sselectv f1 to lv\n" + DRAIN % ("r", "r") + "   crt 'A[':trim(r):']'\n"
    "   sselectv f1 to lv descending\n" + DRAIN % ("r", "r") + "   crt 'D[':trim(r):']'\n"
    "   sselectv f2 to lv\n" + DRAIN % ("r", "r") + "   crt 'T[':trim(r):']'\n"
    "   sselectv f2 to lv right.aligned\n" + DRAIN % ("r", "r") + "   crt 'R[':trim(r):']'\n"
    "   sselectv f2 to lv right.aligned descending\n" + DRAIN % ("r", "r") + "   crt 'RD[':trim(r):']'\n"
    "   sselectv f2 descending right.aligned to lv\n" + DRAIN % ("r", "r") + "   crt 'BEF[':trim(r):']'\n"
    "   sselectv ('pear':@fm:'apple':@fm:'fig') to lv\n" + DRAIN % ("r", "r") + "   crt 'DYN[':trim(r):']'\n"
    "   selectv f1 to lv\n   cnt = 0\n   loop\n      readnext id from lv else exit\n      cnt += 1\n   repeat\n   crt 'UNSORTED[':cnt:']'\n"
    "   sselectn f1 to 5\n   n5 = 0\n   loop\n      readnext id from 5 else exit\n      n5 += 1\n   repeat\n   crt 'SSELECTN[':n5:']'\n"
    "   crt 'END'\nend\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-sselectv.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-sselectv: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-sselectv: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        for nm, text in (("zzsv", PROG), ("zzsvbad", "   open 'zzsv1' to f else stop\n   sselectv f\nend\n")):
            with open(os.path.join(sysd, "bp", nm), "w") as fh:
                fh.write(text)
            made.append(nm)
        out = session(box, "BASIC bp zzsv")
        row("setup: the probe compiles with no errors", "Compiled 1 program(s) with no errors" in out, out[-600:])
        out = session(box, "BASIC bp zzsvbad")
        row("209: SSELECTV without TO is a compile error", "Compiled 1 program(s) with no errors" not in out, out[-300:])
        out = session(box, "RUN bp zzsv")
        row("the run reached its end", re.search(r"(?m)^END\s*$", out) is not None, out[-500:])
        row("209: SSELECTV sorts the ids (left aligned, ascending)", tag(out, "A") == "apple cherry fig pear", repr(tag(out, "A")))
        row("209: ... DESCENDING reverses it", tag(out, "D") == "pear fig cherry apple", repr(tag(out, "D")))
        row("CONTROL: numbers sort as text without RIGHT.ALIGNED (1 10 100 9)", tag(out, "T") == "1 10 100 9", repr(tag(out, "T")))
        row("209: RIGHT.ALIGNED sorts them as numbers (1 9 10 100)", tag(out, "R") == "1 9 10 100", repr(tag(out, "R")))
        row("209: RIGHT.ALIGNED DESCENDING (100 10 9 1)", tag(out, "RD") == "100 10 9 1", repr(tag(out, "RD")))
        row("209: the clauses may come before TO", tag(out, "BEF") == "100 10 9 1", repr(tag(out, "BEF")))
        row("209: a dynamic array can be sorted into a list variable", tag(out, "DYN") == "apple fig pear", repr(tag(out, "DYN")))
        row("CONTROL: SELECTV still gives the four ids", tag(out, "UNSORTED") == "4", repr(tag(out, "UNSORTED")))
        row("CONTROL: SSELECTN to a numbered list still gives the four ids", tag(out, "SSELECTN") == "4", repr(tag(out, "SSELECTN")))
    finally:
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        session(box, "DELETE.FILE zzsv1", "DELETE.FILE zzsv2")

    say("\nsandbox-sselectv: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
