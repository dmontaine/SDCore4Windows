#!/usr/bin/env python3
#
# sandbox-selectv-mode.py - openQM sheet 85: under $MODE SELECTV the list variable of SELECT and the FROM list of READNEXT are
#                           optional, and left out they are the program's own default select list variable.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-selectv-mode.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for sheet 85 (the sheet's text is cut off after "defaulting to an internal variable that is loca";
#               the behaviour is the manual's, SELECT / SELECTV, "If the TO clause is omitted, a default select list variable
#               is used", with the program-local scope the cut-off word is taken to be).
# END-HISTORY
#
# THE INSTRUMENT.  A session piped to `sd -internal` (as sandbox-sselectv.py).  Programs print tagged lines read back by name.
# The controls are the same statements WITHOUT the mode: SELECT then READNEXT still go through list 0 (an EXECUTE-made list is
# read by a plain READNEXT), and SELECTV with no TO is still a compile error.  The files hold 4 ids (zzsm1) and 2 (zzsm2); a
# list 0 made with FORMLIST holds q1 and q2, ids that are in no file, so a row can tell which list was read by the id it got.

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
    say("sandbox-selectv-mode: CANNOT RUN - " + msg)
    sys.exit(2)


def session(box, *cmds):
    say("    > " + " | ".join(cmds))
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"), env=env,
                       capture_output=True, text=True, errors="replace", timeout=240)
    return ANSI.sub("", p.stdout + p.stderr)


def tag(out, name):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % name, out)
    return None if m is None else m.group(1)


def ids(out, name):
    v = tag(out, name)
    return None if v is None else sorted(v.split())


FOUR = ["apple", "cherry", "fig", "pear"]

# Both files are made by every probe that needs them
SETUP = (
    "   for t = 1 to 2\n      nm = 'zzsm':t\n      execute 'DELETE.FILE ':nm capturing j\n      execute 'CREATE.FILE ':nm capturing j\n"
    "      open nm to f else stop 'no f'\n"
    "      if t = 1 then ids = 'pear':@fm:'apple':@fm:'fig':@fm:'cherry' else ids = 'x1':@fm:'x2'\n"
    "      for i = 1 to dcount(ids, @fm) ; write 'r' on f, ids<i> ; next i\n   next t\n"
    "   open 'zzsm1' to f1 else stop 'no f1'\n   open 'zzsm2' to f2 else stop 'no f2'\n")

# Read every id of the DEFAULT list into r (no FROM), and print it under the tag
DRAIN = "   r = ''\n   loop\n      readnext id else exit\n      r := id : ' '\n   repeat\n   crt '%s[':trim(r):']'\n"

# THE MODE ON
PROG_MODE = (
    "$mode selectv\n" + SETUP +
    # A: READNEXT before any SELECT: there is no list, so ELSE (and no abort for an unassigned variable)
    "   readnext id then crt 'A[THEN]' else crt 'A[ELSE]'\n"
    # A2: the exploded forms before any SELECT: ELSE, and the positions are zero
    "   v = 99 ; s = 99\n   readnext id, v, s then crt 'A2[THEN]' else crt 'A2[ELSE:':v:':':s:']'\n"
    # B: SELECT with no TO, then READNEXT with no FROM
    "   select f1\n" + DRAIN % "B" +
    # C: SELECTV with no TO is the same
    "   selectv f1\n" + DRAIN % "C" +
    # D: the explicit forms are as they were
    "   select f1 to lv\n   r = ''\n   loop\n      readnext id from lv else exit\n      r := id : ' '\n   repeat\n   crt 'D[':trim(r):']'\n"
    # E: list 0 is NOT what a bare READNEXT reads: the default variable is empty (drained by C), list 0 holds q1 q2
    "   formlist 'q1':@fm:'q2' to 0\n"
    "   readnext id then crt 'E1[':id:']' else crt 'E1[ELSE]'\n"
    "   readnext id from 0 then crt 'E2[':id:']' else crt 'E2[ELSE]'\n"
    "   clearselect 0\n"
    # F: a second SELECT replaces the default list
    "   select f1\n   readnext id else stop\n   select f2\n" + DRAIN % "F" +
    # G: a partly read list, then the exploded form takes the next id and zeroes the positions
    "   select f1\n   v = 99 ; s = 99\n   readnext id, v, s then crt 'G[':(id # ''):':':v:':':s:']' else crt 'G[ELSE]'\n"
    "   select f2\n"      # (replaces it, so the rest of f1 is not left active)
    # H: SSELECTV with no TO is sorted, into the default variable
    "   sselectv f1\n" + DRAIN % "H" +
    # I: SSELECT is still SSELECT (it is SELECT that the mode changes): it makes list 0, and a bare READNEXT does not see it
    "   sselect f1\n   readnext id then crt 'I1[':id:']' else crt 'I1[ELSE]'\n"
    "   readnext id from 0 then crt 'I2[':id:']' else crt 'I2[ELSE]'\n   clearselect 0\n"
    # J: a LOCAL SUBROUTINE shares its program's default list
    "   select f2\n   gosub zdrain\n   crt 'J[':trim(r):']'\n"
    # K: the statement still takes a THEN / ELSE and an ON ERROR clause with the variable left out
    "   select f1 on error crt 'K[error]'\n   readnext id then crt 'K[ok]' else crt 'K[ELSE]'\n"
    "   crt 'END'\n   stop\n\n"
    "local subroutine zdrain\n   r = ''\n   loop\n      readnext id else exit\n      r := id : ' '\n   repeat\n   return\nend\n")

# THE MODE ON, AND PICK.SELECT: the active list 0 moves into the default variable, the file is ignored
PROG_PICK = (
    "$mode selectv, pick.select\n" + SETUP +
    "   formlist 'q1':@fm:'q2' to 0\n   select f1\n" + DRAIN % "P" +
    "   select f1\n" + DRAIN % "P2" + "   crt 'END'\nend\n")

# THE MODE OFF: the controls
PROG_OFF = (
    SETUP +
    "   select f1\n   r = ''\n   loop\n      readnext id else exit\n      r := id : ' '\n   repeat\n   crt 'O1[':trim(r):']'\n"
    "   formlist 'q1':@fm:'q2' to 0\n   readnext id then crt 'O2[':id:']' else crt 'O2[ELSE]'\n   clearselect 0\n"
    "   selectv f2 to lv\n   readnext id from lv then crt 'O3[':id:']' else crt 'O3[ELSE]'\n"
    "   crt 'END'\nend\n")

# A subroutine called by the main program: its default list is its own
PROG_CALLER = (
    "$mode selectv\n" + SETUP +
    "   select f1\n   call zzsmsub(got)\n   crt 'SUB[':got:']'\n" + DRAIN % "MAIN" + "   crt 'END'\nend\n")
PROG_SUB = (
    "$mode selectv\nsubroutine zzsmsub(got)\n   readnext id then got = 'read ':id else got = 'ELSE'\n   return\nend\n")

# Compile-error controls
BAD_OFF = "   open 'zzsm1' to f else stop\n   selectv f\nend\n"            # no mode: SELECTV with no TO is still refused
BAD_SS_OFF = "   open 'zzsm1' to f else stop\n   sselectv f\nend\n"
GOOD_MODE_SS = "$mode selectv\n   open 'zzsm1' to f else stop\n   sselectv f\nend\n"


def compiled(out):
    return "Compiled 1 program(s) with no errors" in out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-selectv-mode.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-selectv-mode: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-selectv-mode: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    progs = (("zzsmon", PROG_MODE), ("zzsmpick", PROG_PICK), ("zzsmoff", PROG_OFF), ("zzsmcall", PROG_CALLER),
             ("zzsmsub", PROG_SUB), ("zzsmbad", BAD_OFF), ("zzsmbad2", BAD_SS_OFF), ("zzsmgood", GOOD_MODE_SS))
    try:
        for nm, text in progs:
            with open(os.path.join(sysd, "bp", nm), "w") as fh:
                fh.write(text)
            made.append(nm)
        out = session(box, "BASIC bp zzsmon")
        row("setup: the probe with the mode compiles with no errors", compiled(out), out[-700:])
        out = session(box, "BASIC bp zzsmpick")
        row("setup: the PICK.SELECT probe compiles", compiled(out), out[-500:])
        out = session(box, "BASIC bp zzsmoff")
        row("setup: the no-mode control compiles", compiled(out), out[-500:])
        out = session(box, "BASIC bp zzsmsub", "CATALOG bp zzsmsub LOCAL", "BASIC bp zzsmcall")
        row("setup: the caller and its subroutine compile", compiled(out) and "with errors" not in out, out[-600:])
        out = session(box, "BASIC bp zzsmbad")
        row("CONTROL: SELECTV with no TO and NO mode is still a compile error", not compiled(out), out[-300:])
        out = session(box, "BASIC bp zzsmbad2")
        row("CONTROL: SSELECTV with no TO and NO mode is still a compile error", not compiled(out), out[-300:])
        out = session(box, "BASIC bp zzsmgood")
        row("85: SSELECTV with no TO compiles under the mode", compiled(out), out[-300:])

        out = session(box, "RUN bp zzsmon")
        row("the mode probe reached its end", re.search(r"(?m)^END\s*$", out) is not None, out[-700:])
        row("85: READNEXT before any SELECT takes ELSE (no abort for the unassigned default variable)", tag(out, "A") == "ELSE", repr(tag(out, "A")))
        row("85: ... and so does the exploded form, which sets both positions to zero", tag(out, "A2") == "ELSE:0:0", repr(tag(out, "A2")))
        row("85: SELECT file with no TO, READNEXT with no FROM, reads the four ids", ids(out, "B") == FOUR, repr(tag(out, "B")))
        row("85: SELECTV file with no TO is the same", ids(out, "C") == FOUR, repr(tag(out, "C")))
        row("CONTROL: SELECT file TO var and READNEXT FROM var are as they were", ids(out, "D") == FOUR, repr(tag(out, "D")))
        row("85: a bare READNEXT does not read list 0 (the default variable is empty)", tag(out, "E1") == "ELSE", repr(tag(out, "E1")))
        row("CONTROL: READNEXT FROM 0 still reads list 0 (the instrument can tell the lists apart)", tag(out, "E2") == "q1", repr(tag(out, "E2")))
        row("85: a second SELECT replaces the default list", ids(out, "F") == ["x1", "x2"], repr(tag(out, "F")))
        row("85: READNEXT id, v, s with no FROM reads the default list and zeroes the positions", tag(out, "G") == "1:0:0", repr(tag(out, "G")))
        row("85: SSELECTV with no TO sorts into the default variable", tag(out, "H") == "apple cherry fig pear", repr(tag(out, "H")))
        row("CONTROL: SSELECT is still SSELECT - it makes list 0, which a bare READNEXT does not read", tag(out, "I1") == "ELSE", repr(tag(out, "I1")))
        row("CONTROL: ... and READNEXT FROM 0 gets its first sorted id", tag(out, "I2") == "apple", repr(tag(out, "I2")))
        row("85: a LOCAL SUBROUTINE shares the default list of its program", ids(out, "J") == ["x1", "x2"], repr(tag(out, "J")))
        row("85: SELECT with no TO still takes ON ERROR", tag(out, "K") == "ok", repr(tag(out, "K")))

        out = session(box, "RUN bp zzsmpick")
        row("85 + PICK.SELECT: the active list 0 moves into the default variable (q1 q2, the file ignored)", ids(out, "P") == ["q1", "q2"], repr(tag(out, "P")))
        row("85 + PICK.SELECT: with no list 0 active the file is selected", ids(out, "P2") == FOUR, repr(tag(out, "P2")))

        out = session(box, "RUN bp zzsmoff")
        row("CONTROL, no mode: SELECT then a bare READNEXT reads list 0 as it always did", ids(out, "O1") == FOUR, repr(tag(out, "O1")))
        row("CONTROL, no mode: a list made for list 0 by FORMLIST is read by a bare READNEXT", tag(out, "O2") == "q1", repr(tag(out, "O2")))
        row("CONTROL, no mode: SELECT f TO lv; READNEXT FROM lv is untouched", tag(out, "O3") in ("x1", "x2"), repr(tag(out, "O3")))

        out = session(box, "RUN bp zzsmcall")
        row("85: a called subroutine has a default list of its own (it finds none)", tag(out, "SUB") == "ELSE", repr(tag(out, "SUB")))
        row("85: ... and the caller's list is whole after the call", ids(out, "MAIN") == FOUR, repr(tag(out, "MAIN")))
    finally:
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        session(box, "DELETE.CATALOG zzsmsub LOCAL", "DELETE.FILE zzsm1", "DELETE.FILE zzsm2")

    say("\nsandbox-selectv-mode: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
