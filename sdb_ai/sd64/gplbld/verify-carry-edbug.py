#!/usr/bin/env python3
#
# sandbox-edbug.py - three defects the openQM release notes list for the ED editor and the debugger, tested to be
# ABSENT from SD (sheet items 264, 327 and 335).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-edbug.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  264: ED's L command with no text as its first use; 327: the debugger showing an element of a
#               two dimensional matrix (column index out of range); 335: the debugger finding variables of common
#               blocks, in the program and in a subroutine it calls.  All three were fixed upstream in the
#               openQM 4 releases; each row's control shows what a failure would look like.
# END-HISTORY
#
# HOW IT DRIVES THEM.  Through a pipe session (sandbox-fromtree.py sess): ED reads its commands from the lines that
# follow it, the debugger from the lines after a program that holds a DEBUG statement.  Every verdict is anchored on
# the debugger's or the editor's own reply text and the run refuses to count a reply that is an error message.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
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
    say("sandbox-edbug: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d lines sent: %s ..." % (len(cmds), " | ".join(cmds[:3])))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-edbug.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-edbug: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-edbug: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    rec, main_p, sub_p, fix = ("zze%s%s" % (RUN, c) for c in "rmsf")
    files = {
        fix: """   open 'bp' to f else stop 'no bp'
   write 'alpha':@fm:'beta':@fm:'gamma' on f, '%s'
   crt 'EDBUG FIXTURE DONE'
end
""" % rec,
        sub_p: """   subroutine %s
   common /cb2/ cx
   common /cb3/ cy, cz
   cy = 'cy in sub'
   debug
   return
end
""" % sub_p,
        main_p: """   common /cb2/ cx
   dim mm(5,2)
   dim sq(3,4)
   mm(5,2) = 'five-two'
   mm(4,1) = 'four-one'
   sq(3,4) = 'three-four'
   cx = 'common x'
   call %s
   crt 'END'
end
""" % sub_p,
    }
    for name, body in files.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(body)

    say("\n--- 264: ED's L command with no text as its first use --------------------------------------------------")
    out = sess(box, "BASIC bp %s" % fix, "RUN bp %s" % fix, "ED bp %s" % rec, "L", "L", "Q")
    row("setup: the fixture made the record", "EDBUG FIXTURE DONE" in out, out[-300:])
    row("CONTROL: the editor opened the record (3 lines)", re.search(r"(?m)^3 line\(s\)$", out) is not None, out[-300:])
    row("L alone as the first command goes to a line and does not stop ED with an error",
        re.search(r"(?m)^0001: alpha$", out) is not None and "Unable" not in out and "rror" not in out.split("3 line(s)")[-1],
        out.split("3 line(s)")[-1][:300])

    say("\n--- 327: the debugger shows elements of a two dimensional matrix -----------------------------------------")
    out = sess(box, "BASIC bp %s DEBUGGING" % sub_p, "CATALOG bp %s LOCAL" % sub_p, "BASIC bp %s DEBUGGING" % main_p,
               "RUN bp %s" % main_p, "/cx", "/cy", "/cz", "Q")
    row("setup: both programs compiled and the debugger started in the subroutine",
        out.count("with no errors") >= 2 and re.search(r"(?m)^>/cx$", out) is not None, out[-500:])
    # the main program's own matrix cannot be asked from inside the subroutine, so ask from the main program too
    out2 = sess(box, "BASIC bp %s DEBUGGING" % main_p, "RUN bp %s" % main_p, "/mm(5,2)", "/mm(4,1)", "/sq(3,4)", "/mm(1,1)",
                "/mm(6,1)", "/mm(1,3)", "Q")
    # the main program stops in the subroutine's DEBUG first, so these go to the subroutine's frame: use a second run
    # with the CALL taken out
    body = files[main_p].replace("   call %s\n" % sub_p, "   debug\n")
    with open(os.path.join(sysd, "bp", main_p), "w") as fh:
        fh.write(body)
    out2 = sess(box, "BASIC bp %s DEBUGGING" % main_p, "RUN bp %s" % main_p, "/mm(5,2)", "/mm(4,1)", "/sq(3,4)",
                "/mm(1,1)", "/mm(6,1)", "/mm(1,3)", "Q")
    row("a 5 by 2 matrix: the last element (5,2) is shown, not 'column index out of range'",
        re.search(r'(?m)^String \(8 bytes\): "five-two"$', out2) is not None, out2[-600:])
    row("...and an element in the middle of it (4,1)", re.search(r'(?m)^String \(8 bytes\): "four-one"$', out2) is not None, out2[-600:])
    row("a 3 by 4 matrix: the last element (3,4)", re.search(r'(?m)^String \(10 bytes\): "three-four"$', out2) is not None, out2[-600:])
    row("an element never assigned says so", re.search(r"(?m)^Unassigned$", out2) is not None, out2[-600:])
    row("CONTROL: a row past the end says the row is out of range", re.search(r"(?m)^\x07?Row index out of range\s*$", out2) is not None, out2[-600:])   # (a bell comes first)
    row("CONTROL: a column past the end says the column is out of range (the message the defect gave for a good one)",
        re.search(r"(?m)^\x07?Column index out of range\s*$", out2) is not None, out2[-600:])

    say("\n--- 335: the debugger finds variables in common blocks -------------------------------------------------")
    row("a named common block's variable of the calling program, seen from the subroutine's debug stop",
        re.search(r'(?m)^>/cx\nString \(8 bytes\): "common x"$', out) is not None, out[-700:])
    row("a block the subroutine declared itself (assigned there)",
        re.search(r'(?m)^>/cy\nString \(9 bytes\): "cy in sub"$', out) is not None, out[-700:])
    row("a variable of that block never assigned reads as 0, as common variables start", re.search(r"(?m)^>/cz\nInteger: 0$", out) is not None, out[-700:])

    say("\n--- 375: ED in edit values mode shows the field and value positions before the line number (16 Oct 26) ---")
    evrec, evmk, evopt = "zzev" + RUN, "zzevm" + RUN, "zzevo" + RUN
    with open(os.path.join(sysd, "bp", evmk), "w") as fh:
        fh.write("   open 'bp' to f else stop 'no bp'\n   write 'alpha':@fm:'b1':@vm:'b2a':@sm:'b2b':@vm:'b3':@fm:'gamma' on f, '%s'\n"
                 "   crt 'EVFIX DONE'\nend\n" % evrec)
    with open(os.path.join(sysd, "bp", evopt), "w") as fh:
        fh.write("   write 'X':@fm:'NO.EV.POSITION' on @voc, '$ED.OPTIONS'\n   crt 'OPT SET'\nend\n")
    evcmds = ["ED bp %s" % evrec, "L", "L", "EV", "L", "L", "EV", "L", "QV", "QV", "Q"]
    out = sess(box, "BASIC bp %s" % evmk, "RUN bp %s" % evmk, *evcmds)
    row("setup: the fixture made the record", "EVFIX DONE" in out, out[-300:])
    row("CONTROL: outside EV a line number has no prefix (0002: is the second line, with its values)", re.search(r"(?m)^0002: b1", out) is not None, out[-400:])
    row("in EV on line 2 a value is shown as field.line: 2.0001 is the first value", re.search(r"(?m)^2\.0001: b1$", out) is not None, out[-600:])
    row("...and the second value, 2.0002", re.search(r"(?m)^2\.0002: b2a", out) is not None, out[-600:])
    row("in EV on a value (subvalues) the line is field.value.line: 2.2.0001 is the first subvalue of value 2",
        re.search(r"(?m)^2\.2\.0001: b2a$", out) is not None, out[-600:])
    out = sess(box, "BASIC bp %s" % evopt, "RUN bp %s" % evopt, *evcmds)
    row("with NO.EV.POSITION in $ED.OPTIONS the values are numbered as before: 0001: b1", re.search(r"(?m)^0001: b1$", out) is not None
        and re.search(r"(?m)^2\.0001", out) is None, out[-600:])
    sess(box, "DELETE VOC $ED.OPTIONS")
    for nm in (evmk, evopt):
        for d in ("bp", "bp.out"):
            pth = os.path.join(sysd, d, nm)
            if os.path.exists(pth):
                os.remove(pth)

    say("")
    say("sandbox-edbug: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
