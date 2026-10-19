#!/usr/bin/env python3
#
# sandbox-cll.py - OPTION COMMAND.LEVEL.LOCKS (openQM 4, QM4 gaps 231 and 428).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-cll.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  k_release() offers the last reference to a file variable to park_fvar() (op_lock.c), which keeps the file
#               open for its locks under the option; k_return() lets them go when the program is back at the command processor.
# END-HISTORY
#
# THE INSTRUMENT.  A lock is seen where a person would see it, in the output of LIST.READU, which a program runs with EXECUTE ...
# CAPTURING after the subroutine has returned (and which the session runs after the program has ended).  Each program prints a
# tag word before the captured list, so a verdict is anchored on the lines of that run.  The record ids are distinctive words.
# The control is the option off: the lock is gone when the subroutine has returned, as it always was.

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
    say("sandbox-cll: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-cll.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-cll: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-cll: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    fil = "zzcl" + RUN
    lk, lkc, inner, mn, mclose, mexe = ("zzcm%s%s" % (RUN, c) for c in "lcibxe")
    # a subroutine that opens the file to a LOCAL variable and takes an update lock on the record it is given
    progs = {
        lk: ("subroutine %s(id)\n   open '%s' to f else crt 'OPEN-FAILED' ; return\n   readu r from f, id else null\n   return\nend\n" % (lk, fil)),
        # the same, but it closes the file on purpose before it returns
        lkc: ("subroutine %s(id)\n   open '%s' to f else crt 'OPEN-FAILED' ; return\n   readu r from f, id else null\n   close f\n   return\nend\n" % (lkc, fil)),
        # the EXECUTEd program: takes a lock in a subroutine and shows the locks
        # (the lock table keeps record ids in upper case, so the captured list is searched in upper case)
        inner: ("   call %s('wordinner')\n   execute 'LIST.READU' capturing out\n   out = upcase(out)\n   crt 'INNER-SEES ':(if index(out, 'WORDINNER', 1) then 'inner' else 'no-inner'):' ':"
                "(if index(out, 'WORDOUTER', 1) then 'outer' else 'no-outer')\nend\n") % lk,
        mn: ("   call %s('wordsub')\n   execute 'LIST.READU' capturing out\n   out = upcase(out)\n   crt 'AFTER-SUB ':(if index(out, 'WORDSUB', 1) then 'LOCKED' else 'FREE')\nend\n") % lk,
        mclose: ("   call %s('wordclose')\n   execute 'LIST.READU' capturing out\n   out = upcase(out)\n   crt 'AFTER-CLOSE ':(if index(out, 'WORDCLOSE', 1) then 'LOCKED' else 'FREE')\nend\n") % lkc,
        mexe: ("   call %s('wordouter')\n   execute 'RUN bp %s'\n   execute 'LIST.READU' capturing out\n   out = upcase(out)\n"
               "   crt 'OUTER-SEES ':(if index(out, 'WORDOUTER', 1) then 'outer' else 'no-outer'):' ':(if index(out, 'WORDINNER', 1) then 'inner' else 'no-inner')\nend\n") % (lk, inner),
    }
    for name, body in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(body)

    say("\n--- OPTION COMMAND.LEVEL.LOCKS ---------------------------------------------------------------------------")
    names = list(progs)
    out = sess(box, "DELETE.FILE %s" % fil, "CREATE.FILE %s" % fil, *(["BASIC bp %s" % n for n in names] +
               ["CATALOG bp %s" % lk, "CATALOG bp %s" % lkc]))
    row("setup: all six programs compiled with no errors", len(re.findall(r"Compiled 1 program\(s\) with no errors", out)) == len(names), out[-900:])

    o = sess(box, "RUN bp %s" % mn)
    row("CONTROL, the option off: when the subroutine has returned its file variable is gone and so is the lock",
        re.search(r"(?m)^AFTER-SUB FREE\s*$", o) is not None, o[-400:])

    o = sess(box, "OPTION COMMAND.LEVEL.LOCKS", "RUN bp %s" % mn, "LIST.READU")
    row("the option on: the lock is still held when the subroutine has returned", re.search(r"(?m)^AFTER-SUB LOCKED\s*$", o) is not None, o[-500:])
    after = o.split("AFTER-SUB", 1)[-1]
    row("...and when the program is back at the command processor it is released (LIST.READU does not show it)",
        "WORDSUB" not in after.upper().split("LIST.READU", 1)[-1], after[-400:])

    o = sess(box, "OPTION COMMAND.LEVEL.LOCKS", "RUN bp %s" % mclose)
    row("the option on, a file closed on purpose with CLOSE is released at once", re.search(r"(?m)^AFTER-CLOSE FREE\s*$", o) is not None, o[-400:])

    o = sess(box, "OPTION COMMAND.LEVEL.LOCKS", "RUN bp %s" % mexe)
    row("an EXECUTEd program sees its own lock and the caller's", re.search(r"(?m)^INNER-SEES inner outer\s*$", o) is not None, o[-500:])
    row("back from the EXECUTE the caller's lock is held and the executed program's is released",
        re.search(r"(?m)^OUTER-SEES outer no-inner\s*$", o) is not None, o[-500:])

    sess(box, "DELETE.CATALOG %s" % lk, "DELETE.CATALOG %s" % lkc, "DELETE.FILE %s" % fil)
    say("")
    say("sandbox-cll: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
