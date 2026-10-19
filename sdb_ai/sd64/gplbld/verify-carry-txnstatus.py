#!/usr/bin/env python3
#
# sandbox-txnstatus.py - 1.2-0 bundle B-5, sheet 19: STATUS() immediately after END TRANSACTION is 0 when the transaction committed and
#                        ER_ROLLBACK (1021) when it was rolled back, by ROLLBACK or by running into END TRANSACTION.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-txnstatus.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 19.
# END-HISTORY
#
# THE INSTRUMENT.  A session piped to `sd -internal` (as sandbox-sselectv.py).  Every case sets STATUS() to a value that is neither 0 nor
# 1021 (a failed READ of a missing record gives 3006) before the transaction, so a status that is simply left over cannot pass; the record
# is read back after each transaction, so "committed" is shown by the data, not only by the number.

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
    say("sandbox-txnstatus: CANNOT RUN - " + msg)
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


# Each case: poison STATUS() with a failed read (3006), run the transaction, print STATUS() at once, then the record.
PROG = (
    "   execute 'DELETE.FILE zzts' capturing j\n   execute 'CREATE.FILE zzts' capturing j\n"
    "   open 'zzts' to f else stop 'no f'\n"
    "   write 'old' on f, 'c'\n   write 'old' on f, 'r'\n   write 'old' on f, 'e'\n   write 'old' on f, 'n'\n"
    # commit
    "   read x from f, 'nosuch' else null\n"
    "   begin transaction\n      readu x from f, 'c' else null\n      write 'new' on f, 'c'\n      commit\n   end transaction\n"
    "   s = status()\n   read v from f, 'c' else v = '?'\n   crt 'COMMIT[':s:']'\n   crt 'COMMITDATA[':v:']'\n"
    # rollback statement
    "   read x from f, 'nosuch' else null\n"
    "   begin transaction\n      readu x from f, 'r' else null\n      write 'new' on f, 'r'\n      rollback\n   end transaction\n"
    "   s = status()\n   read v from f, 'r' else v = '?'\n   crt 'ROLLBACK[':s:']'\n   crt 'ROLLBACKDATA[':v:']'\n"
    # run into END TRANSACTION
    "   read x from f, 'nosuch' else null\n"
    "   begin transaction\n      readu x from f, 'e' else null\n      write 'new' on f, 'e'\n   end transaction\n"
    "   s = status()\n   read v from f, 'e' else v = '?'\n   crt 'FALL[':s:']'\n   crt 'FALLDATA[':v:']'\n"
    # commit on one branch, the other branch falls through (a conditional)
    "   for k = 1 to 2\n      read x from f, 'nosuch' else null\n"
    "      begin transaction\n         readu x from f, 'n' else null\n         write 'new':k on f, 'n'\n"
    "         if k = 1 then commit\n"
    "      end transaction\n      crt 'COND':k:'[':status():']'\n   next k\n"
    # a nested transaction: the inner one commits, the outer one is rolled back
    "   read x from f, 'nosuch' else null\n"
    "   begin transaction\n      readu x from f, 'c' else null\n      write 'outer' on f, 'c'\n"
    "      begin transaction\n         readu x from f, 'r' else null\n         write 'inner' on f, 'r'\n         commit\n      end transaction\n"
    "      crt 'INNER[':status():']'\n"
    "      rollback\n   end transaction\n   crt 'OUTER[':status():']'\n"
    # controls: STATUS() after an ordinary failed read is still the read's code
    "   read x from f, 'nosuch' else null\n   crt 'CTRL[':status():']'\n"
    "   crt 'END'\nend\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-txnstatus.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-txnstatus: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-txnstatus: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        with open(os.path.join(sysd, "bp", "zzts"), "w") as fh:
            fh.write(PROG)
        made.append("zzts")
        out = session(box, "BASIC bp zzts")
        row("setup: the probe compiles with no errors", "Compiled 1 program(s) with no errors" in out, out[-600:])
        out = session(box, "RUN bp zzts")
        row("the run reached its end", re.search(r"(?m)^END\s*$", out) is not None, out[-500:])
        row("CONTROL: STATUS() after a failed read is still its code (3006)", tag(out, "CTRL") == "3006", repr(tag(out, "CTRL")))
        row("19: STATUS() after a committed transaction is 0", tag(out, "COMMIT") == "0", repr(tag(out, "COMMIT")))
        row("... and the commit really wrote the record", tag(out, "COMMITDATA") == "new", repr(tag(out, "COMMITDATA")))
        row("19: STATUS() after ROLLBACK is 1021", tag(out, "ROLLBACK") == "1021", repr(tag(out, "ROLLBACK")))
        row("... and the record is as it was", tag(out, "ROLLBACKDATA") == "old", repr(tag(out, "ROLLBACKDATA")))
        row("19: STATUS() after running into END TRANSACTION is 1021", tag(out, "FALL") == "1021", repr(tag(out, "FALL")))
        row("... and the record is as it was (the implied roll-back)", tag(out, "FALLDATA") == "old", repr(tag(out, "FALLDATA")))
        row("19: a conditional COMMIT: 0 when it ran", tag(out, "COND1") == "0", repr(tag(out, "COND1")))
        row("19: ... and 1021 when it did not", tag(out, "COND2") == "1021", repr(tag(out, "COND2")))
        row("19: the inner transaction of a nested pair committed: 0", tag(out, "INNER") == "0", repr(tag(out, "INNER")))
        row("19: the outer one, rolled back: 1021", tag(out, "OUTER") == "1021", repr(tag(out, "OUTER")))
    finally:
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        session(box, "DELETE.FILE zzts")

    say("\nsandbox-txnstatus: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
