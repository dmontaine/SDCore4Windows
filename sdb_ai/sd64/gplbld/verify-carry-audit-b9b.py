#!/usr/bin/env python3
#
# sandbox-audit-b9b.py - 1.2-0 bundle B-9, the second sitting of the bug-fix audit against the openQM release notes (sheet 274, 342, 382).
#                        What the notes say was broken in QM is tried here, to see whether SD has the same defect.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-audit-b9b.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written.
# END-HISTORY
#
# THE INSTRUMENT.  Each probe prints a tagged line with what it saw; the rows compare it with the healthy answer.  A row that fails is a
# defect found in SD, which the entry in PROJECT_STATUS names.  274: !SORT of a select list variable (QM reported an error).  382: a matrix
# redimensioned many times to many sizes (QM had a memory alignment fault).  342: a public variable inherited from a parent class that also
# has a public function of the same name (QM searched the inherited classes wrongly).  The class probe first checks that the sandbox compiles
# the two class modules at all: if it does not, the row says so and it is not counted as a pass for 342.

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
    say("sandbox-audit-b9b: CANNOT RUN - " + msg)
    sys.exit(2)


def session(box, *cmds):
    say("    > " + " | ".join(cmds))
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"), env=env,
                       capture_output=True, text=True, errors="replace", timeout=300)
    return ANSI.sub("", p.stdout + p.stderr)


def tag(out, name):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % name, out)
    return None if m is None else m.group(1)


SORTP = (
    "   execute 'DELETE.FILE zzab1' capturing j\n   execute 'CREATE.FILE zzab1' capturing j\n"
    "   open 'zzab1' to f else stop 'no f'\n"
    "   for each id in 'pear':@fm:'apple':@fm:'fig':@fm:'cherry' delimiter @fm ; write 'x' on f, id ; next id\n"
    "   selectv f to lv\n"
    "   call !sort(lv, out, 'A')\n"
    "   crt 'SORTED[':convert(@fm, ' ', out):']'\n"
    "   crt 'ST[':status():']'\n"
    "   dyn = 'pear':@fm:'apple':@fm:'fig'\n   call !sort(dyn, o2, 'A')\n   crt 'DYN[':convert(@fm, ' ', o2):']'\n"
    "   call !sort(dyn, o3, 'D')\n   crt 'DESC[':convert(@fm, ' ', o3):']'\n"
    "   dup = 'b':@fm:'a':@fm:'b':@fm:''\n   call !sort(dup, o4, 'UN')\n   crt 'UN[':convert(@fm, ' ', o4):']'\n"
    "   num = '10':@fm:'9':@fm:'100'\n   call !sort(num, o5, 'AR')\n   crt 'NUM[':convert(@fm, ' ', o5):']'\n"
    "   e = ''\n   call !sort(e, o6, 'A')\n   crt 'EMPTY[':o6:']'\n"
    "   crt 'END'\nend\n")

REDIMP = (
    "   dim a(5)\n   for i = 1 to 5 ; a(i) = 'row':i ; next i\n"
    "   ok = 1\n"
    "   for n = 1 to 400\n      k = mod(n * 37, 301) + 1\n      redim a(k)\n"
    "      if k >= 1 then a(k) = 'v':n\n"
    "      if k >= 1 and a(k) # 'v':n then ok = 0\n"
    "   next n\n"
    "   crt 'REDIM[':ok:']'\n   crt 'END'\nend\n")

TRGP = ("subroutine zzabtrg(mode, id, rec, onerr)\n   crt 'TRG[':mode:']'\n   return\nend\n")
TRGUSE = ("   execute 'DELETE.FILE zzab2' capturing j\n   execute 'CREATE.FILE zzab2' capturing j\n"
          "   open 'zzab2' to f else stop 'no f'\n   write 'hello' on f, 'r1'\n   close f\n"
          "   execute 'SET.TRIGGER zzab2 zzabtrg READ' capturing st\n   crt 'SET[':convert(@fm, '|', st):']'\n"
          "   open 'zzab2' to g else stop 'no g'\n   read rec from g, 'r1' else rec = '?'\n   crt 'GOT[':rec:']'\n"
          "   crt 'END'\nend\n")

KRUN = "   crt 'KRAN[ok]'\nend\n"
KMAKE = ("   open 'VOC' to v else stop 'no voc'\n   read r from v, 'zzabkrun' else stop 'no local entry'\n"
         "   crt 'ENTRY[':convert(@fm, '|', r):']'\n"
         "   write 'K':@fm:'1':@fm:r on v, 'zzabkv'\n   crt 'MADE'\nend\n")

BASEP = ("class zzabbase\n   public tag\n   public function who()\n      return 'base'\n   end\n"
         "   public subroutine create.object\n      tag = 'basetag'\n   end\nend\n")
DERP = ("class zzabder inherits zzabbase\n   public function who()\n      return 'derived'\n   end\nend\n")
USEP = ("   o = object('zzabder')\n   crt 'WHO[':o->who():']'\n   crt 'TAG[':o->tag:']'\n   crt 'END'\nend\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-audit-b9b.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-audit-b9b: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-audit-b9b: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = ("zzabsort", "zzabredim", "zzabbase", "zzabder", "zzabuse", "zzabtrg", "zzabtu", "zzabkrun", "zzabkmk")
    try:
        for nm, text in (("zzabsort", SORTP), ("zzabredim", REDIMP), ("zzabbase", BASEP), ("zzabder", DERP), ("zzabuse", USEP),
                         ("zzabtrg", TRGP), ("zzabtu", TRGUSE), ("zzabkrun", KRUN), ("zzabkmk", KMAKE)):
            with open(os.path.join(sysd, "bp", nm), "w") as fh:
                fh.write(text)
        out = session(box, "BASIC bp zzabsort zzabredim")
        row("setup: the two probes compile with no errors", "Compiled 2 program(s) with no errors" in out, out[-500:])

        out = session(box, "RUN bp zzabsort")
        row("274: the run reached its end (no error from !SORT of a select list variable)", re.search(r"(?m)^END\s*$", out) is not None,
            out[-400:])
        row("274: !SORT of a select list variable returns the ids sorted", tag(out, "SORTED") == "apple cherry fig pear",
            repr(tag(out, "SORTED")))

        row("CONTROL: !SORT of an ordinary dynamic array, ascending", tag(out, "DYN") == "apple fig pear", repr(tag(out, "DYN")))
        row("CONTROL: ... descending", tag(out, "DESC") == "pear fig apple", repr(tag(out, "DESC")))
        row("CONTROL: ... unique, nulls omitted", tag(out, "UN") == "a b", repr(tag(out, "UN")))
        row("CONTROL: ... right aligned numbers", tag(out, "NUM") == "9 10 100", repr(tag(out, "NUM")))
        row("CONTROL: ... an empty list stays empty", tag(out, "EMPTY") == "", repr(tag(out, "EMPTY")))

        out = session(box, "RUN bp zzabredim")
        row("382: a matrix redimensioned 400 times keeps its elements and nothing faults", tag(out, "REDIM") == "1" and
            re.search(r"(?m)^END\s*$", out) is not None, out[-400:])

        out = session(box, "BASIC bp zzabbase zzabder zzabuse", "CATALOG bp zzabbase", "CATALOG bp zzabder")
        compiled = "Compiled 3 program(s) with no errors" in out
        if not compiled:
            row("342: the class probes compile (they must, or 342 is untested)", False, out[-600:])
        else:
            out = session(box, "RUN bp zzabuse")
            row("342: the derived class's function wins and the parent's public variable is reached", tag(out, "WHO") == "derived" and
                tag(out, "TAG") == "basetag", "WHO=%r TAG=%r %s" % (tag(out, "WHO"), tag(out, "TAG"), out[-300:]))

        out = session(box, "BASIC bp zzabtrg zzabtu", "CATALOG bp zzabtrg LOCAL")
        row("317: the locally catalogued trigger and its driver compile", "Compiled 2 program(s) with no errors" in out, out[-500:])
        out = session(box, "RUN bp zzabtu")
        row("317: a read trigger that is catalogued LOCAL runs when a record is read (no fatal error)",
            re.search(r"(?m)^END\s*$", out) is not None and tag(out, "GOT") == "hello" and tag(out, "TRG") is not None,
            "SET=%r GOT=%r TRG=%r %s" % (tag(out, "SET"), tag(out, "GOT"), tag(out, "TRG"), out[-300:]))

        out = session(box, "BASIC bp zzabkrun zzabkmk", "CATALOG bp zzabkrun LOCAL", "RUN bp zzabkmk")
        row("263: a locally catalogued program is entered in the VOC and a K entry is built over it",
            "MADE" in out and tag(out, "ENTRY") is not None, out[-500:])
        out2 = session(box, "zzabkrun")
        row("CONTROL: the locally catalogued program runs by its own name", tag(out2, "KRAN") == "ok" or "KRAN[ok]" in out2, out2[-300:])
        out3 = session(box, "zzabkv")
        row("263: a K entry whose fields 3 onwards are a V entry for a locally catalogued program runs it", "KRAN[ok]" in out3,
            "entry %r; %s" % (tag(out, "ENTRY"), out3[-300:]))
    finally:
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        session(box, "DELETE.FILE zzab1", "DELETE.FILE zzab2","DELETE.CATALOG zzabkrun", "DELETE VOC zzabkv", "DELETE VOC zzabkrun", "DELETE.CATALOG zzabbase","DELETE.CATALOG zzabder")

    say("\nsandbox-audit-b9b: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
