#!/usr/bin/env python3
#
# sandbox-dbgwatch.py - 1.2-0 bundle A-12, sheet 45: the debugger's WATCH var op value stops the program only when the new value meets the
#                       condition.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-dbgwatch.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 45.
# END-HISTORY
#
# THE INSTRUMENT.  As sandbox-dbgcoll.py: a program compiled `BASIC ... DEBUGGING` with a DEBUG statement; the session's next lines are the
# debugger's commands.  The program assigns n = 1 to 10 in a loop (and s = 'stop' at i = 5).  Each case arms a WATCH, then sends one R for every
# stop it expects plus one: if the program stops more or less often than expected, the R lines run out or are left over, and the run never
# reaches "after the debugger", so a wrong count cannot pass.  The values shown at each stop are read from the debugger's own reply.  The
# unconditional WATCH (ten stops) is the control; a condition that is never true must not stop at all.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
PROG = "zzdbw" + "%05d" % (os.getpid() % 100000)
passed = failed = 0

SOURCE = """   n = 0
   s = 'a'
   debug
   for i = 1 to 10
      n = i
      if i = 5 then s = 'stop'
   next i
   crt 'after the debugger'
end
"""

# (label, debugger commands before the first R, values the stops must show, in order; n or s)
CASES = [
    ("CONTROL: WATCH n with no condition stops on every assignment", ["W n"], [("N", str(i)) for i in range(1, 11)]),
    ("45: WATCH n > 7 stops for 8, 9 and 10 only", ["W n > 7"], [("N", "8"), ("N", "9"), ("N", "10")]),
    ("45: WATCH n >= 9", ["W n >= 9"], [("N", "9"), ("N", "10")]),
    ("45: WATCH n = 4 stops once", ["W n = 4"], [("N", "4")]),
    ("45: WATCH n EQ 4 (the word form)", ["W n EQ 4"], [("N", "4")]),
    ("45: WATCH n # 3 stops for everything but 3", ["W n # 3"], [("N", str(i)) for i in range(1, 11) if i != 3]),
    ("45: WATCH n NE 3", ["W n NE 3"], [("N", str(i)) for i in range(1, 11) if i != 3]),
    ("45: WATCH n < 3 and the word LT", ["W n < 3"], [("N", "1"), ("N", "2")]),
    ("45: WATCH n LT 3", ["W n LT 3"], [("N", "1"), ("N", "2")]),
    ("45: WATCH n <= 2", ["W n <= 2"], [("N", "1"), ("N", "2")]),
    ("45: WATCH n GT 8", ["W n GT 8"], [("N", "9"), ("N", "10")]),
    ("45: WATCH n GE 10", ["W n GE 10"], [("N", "10")]),
    ("45: WATCH n LE 1", ["W n LE 1"], [("N", "1")]),
    ("45: a condition that is never true does not stop at all", ["W n = 99"], []),
    ("45: a string compares as text: WATCH s = stop", ["W s = stop"], [("S", "stop")]),
    ("45: a quoted value: WATCH s = 'stop'", ["W s = 'stop'"], [("S", "stop")]),
    ("45: MATCHES: WATCH s MATCHES 's0X'", ["W s MATCHES 's0X'"], [("S", "stop")]),
    ("45: UNWATCH clears the condition as well as the watch", ["W n > 2", "UW"], []),
    ("45: a second WATCH n replaces the condition (unconditional again)", ["W n > 8", "W n"], [("N", str(i)) for i in range(1, 11)]),
    ("45: a new condition replaces the old one", ["W n > 8", "W n < 2"], [("N", "1")]),
    ("45: an operator that is not one is refused and nothing is watched", ["W n ~~ 3"], []),
    ("45: an operator with no value is refused and nothing is watched", ["W n >"], []),
]


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
    say("sandbox-dbgwatch: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d lines sent: %s" % (len(cmds), " | ".join(cmds[:4])))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def stops(out):
    """The (variable, value) of each stop the debugger reported, in order."""
    found = []
    lines = out.replace("\x07", "").split("\n")
    for i, ln in enumerate(lines):
        m = re.search(r"Watched variable (\S+) has changed", ln)
        if not m:
            continue
        val = None
        for nxt in lines[i + 1:i + 6]:
            v = re.search(r"Integer: (-?\d+)", nxt) or re.search(r'String \(\d+ bytes\): "(.*)"', nxt)
            if v:
                val = v.group(1)
                break
        found.append((m.group(1), val))
    return found


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-dbgwatch.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-dbgwatch: sandbox %s" % box)
    say("sandbox-dbgwatch: program %s" % PROG)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-dbgwatch: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    with open(os.path.join(sysd, "bp", PROG), "w") as f:
        f.write(SOURCE)
    try:
        out = sess(box, "BASIC bp %s DEBUGGING" % PROG)
        clean = re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None
        row("setup: the program compiled with no errors, in debug mode", clean, out[-300:])
        if not clean:
            bail("the program did not compile")
        for label, cmds, want in CASES:
            out = sess(box, "RUN bp %s" % PROG, *(cmds + ["R"] * (len(want) + 1)))
            if not re.search(r"(?m)^>", out):
                bail("the debugger prompt never appeared - the program did not stop at DEBUG:\n" + out[-600:])
            got = stops(out)
            say("    %-70s stops: %s" % (label[:70], got))
            ok = got == want and "after the debugger" in out
            row(label, ok, "wanted %s, got %s, ran to the end: %s" % (want, got, "after the debugger" in out))
        out = sess(box, "RUN bp %s" % PROG, "W n ~~ 3", "R")
        row("45: the refusal is the debugger's 'Unrecognised command'", "Unrecognised command" in out.replace("\x07", ""), out[-300:])
    finally:
        for p in (os.path.join(sysd, "bp", PROG), os.path.join(sysd, "bp.out", PROG)):
            if os.path.exists(p):
                os.remove(p)

    say("\nsandbox-dbgwatch: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
