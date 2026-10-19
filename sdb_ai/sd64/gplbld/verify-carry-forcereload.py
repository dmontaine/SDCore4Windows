#!/usr/bin/env python3
#
# sandbox-forcereload.py - OPTION FORCE.RELOAD (openQM 4 release item, sheet 37).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-forcereload.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  process_events() (kernel.c): with the option set, the unload event also marks every referenced
#               cached object stale; op_call() / the indirect CALL replace a stale link variable's object.
# END-HISTORY
#
# The verdicts: a program calls a subroutine through a link variable (CALL @sub), then writes a new version of the
# subroutine's source and compiles and catalogues it from inside the same session, then calls through the SAME
# variable again.  Option off (the control): the variable still holds the old object, the answer is the old
# version.  Option on: the answer is the new version.  Further rows: a subroutine that is not changed still
# answers, with the option on, through its link on every call, and a second variable that was never called is
# unaffected.

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
    say("sandbox-forcereload: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def driver(sub, other):
    # writes version 1 of the subroutine, compiles and catalogues it, calls it through the link variable, writes
    # version 2, compiles and catalogues it, calls through the same variable twice, and through a variable that
    # has never been called (the "other" subroutine, never changed)
    return """   open 'bp' to f else crt 'NO-BP' ; stop
   sub = '%(s)s'
   oth = '%(o)s'
   gosub put1
   execute 'BASIC bp %(s)s'
   execute 'CATALOG bp %(s)s LOCAL'
   call @sub(r)
   crt 'ST1 ':r
   call @oth(r)
   crt 'OT1 ':r
   gosub put2
   execute 'BASIC bp %(s)s'
   execute 'CATALOG bp %(s)s LOCAL'
   call @sub(r)
   crt 'ST2 ':r
   call @sub(r)
   crt 'ST3 ':r
   call @oth(r)
   crt 'OT2 ':r
   stop
put1: write 'subroutine %(s)s(r)':@fm:"   r = 'ONE'":@fm:'   return':@fm:'end':@fm to f, '%(s)s'
   return
put2: write 'subroutine %(s)s(r)':@fm:"   r = 'TWO'":@fm:'   return':@fm:'end':@fm to f, '%(s)s'
   return
end
""" % {"s": sub, "o": other}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-forcereload.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-forcereload: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-forcereload: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    oth = "zzfro" + RUN
    s_off, s_on = "zzfrs" + RUN + "a", "zzfrs" + RUN + "b"
    d_off, d_on = "zzfrd" + RUN + "a", "zzfrd" + RUN + "b"
    progs = {
        oth: "   subroutine %s(r)\n   r = 'OTHER'\n   return\nend\n" % oth,
        d_off: driver(s_off, oth),
        d_on: driver(s_on, oth),
    }
    for name, text in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(text)

    say("\n--- OPTION FORCE.RELOAD ---------------------------------------------------------------------------------")
    out = sess(box, "BASIC bp %s" % oth, "CATALOG bp %s LOCAL" % oth, "BASIC bp %s" % d_off, "BASIC bp %s" % d_on)
    row("setup: the drivers and the other subroutine compiled with no errors",
        out.count("Compiled 1 program(s) with no errors") == 3 and "added to local catalogue" in out, out[-800:])   # (three compiles, one catalogue)

    o = sess(box, "RUN bp %s" % d_off)
    row("CONTROL, option off: the first call answers ONE", re.search(r"(?m)^ST1 ONE\s*$", o) is not None, o[-600:])
    row("CONTROL, option off: after the subroutine is recompiled and catalogued the link variable still answers ONE",
        re.search(r"(?m)^ST2 ONE\s*$", o) is not None and re.search(r"(?m)^ST3 ONE\s*$", o) is not None
        and "ST2 TWO" not in o, o[-600:])

    o = sess(box, "OPTION FORCE.RELOAD", "RUN bp %s" % d_on)
    row("option on: the first call answers ONE", re.search(r"(?m)^ST1 ONE\s*$", o) is not None, o[-600:])
    row("option on: after the subroutine is recompiled and catalogued the link variable answers TWO, and again TWO",
        re.search(r"(?m)^ST2 TWO\s*$", o) is not None and re.search(r"(?m)^ST3 TWO\s*$", o) is not None, o[-600:])
    row("option on: a subroutine that was not changed still answers through its link before and after",
        re.search(r"(?m)^OT1 OTHER\s*$", o) is not None and re.search(r"(?m)^OT2 OTHER\s*$", o) is not None, o[-600:])
    row("OPTION lists FORCE.RELOAD",
        "FORCE.RELOAD" in sess(box, "OPTION"), "")

    say("")
    say("sandbox-forcereload: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
