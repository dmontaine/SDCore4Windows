#!/usr/bin/env python3
#
# sandbox-dbgcase.py - the debugger stops at each CASE condition (openQM 4, QM4 Fixes 97).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-dbgcase.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  bcomp (st.begin) emits a debug stop before each CASE condition of a program compiled for the debugger.
# END-HISTORY
#
# THE INSTRUMENT.  The program is compiled BASIC ... DEBUGGING, run, and stepped by line (S) in the debugger, which prints the
# line it has reached.  Each reply is matched to the command that produced it.  Before the change a step from BEGIN CASE went
# straight to the statement of the chosen case, and never showed a condition; the controls are a case chosen first (its
# condition and then its statement) and the same program with no debugger stop requested (it still runs to its end).

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
SECOND, FIRST = "zzdcs" + RUN, "zzdcf" + RUN
passed = failed = 0

BODY = """   x = %d
   debug
   begin case
      case x = 1
         crt 'ONE'
      case x = 2
         crt 'TWO'
      case x = 3 ; crt 'THREE'
      case 1
         crt 'OTHER'
   end case
   crt 'END'
end
"""


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
    say("sandbox-dbgcase: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def stops(box, prog, n):
    """Run prog for the debugger, step by line n times, then run on; return the line number each step reached and the whole output."""
    out = sess(box, "BASIC bp %s DEBUGGING" % prog, "RUN bp %s" % prog, *(["S"] * n + ["R"]))
    if re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is None:
        bail("the program did not compile:\n" + out[-400:])
    seg = out[out.rfind(":RUN bp %s" % prog):]
    first = re.search(r"(?m)^\s*(\d+):", seg)
    after = re.split(r"(?m)^>S\s*$", seg)[1:]
    lines = [int(m.group(1)) if (m := re.search(r"(?m)^\s*(\d+):", part)) else None for part in after]
    return (int(first.group(1)) if first else None), lines, seg


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-dbgcase.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-dbgcase: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-dbgcase: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    for nm, x in ((SECOND, 2), (FIRST, 1)):
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(BODY % x)
    try:
        say("\n--- the second case is the one chosen -----------------------------------------------------------------")
        first, lines, seg = stops(box, SECOND, 3)
        say("    stopped at line %s, then stepped to %s" % (first, lines))
        row("CONTROL: the debugger stops at line 3, BEGIN CASE, after the DEBUG statement", first == 3, seg[-300:])
        row("a step shows the first condition, line 4 (case x = 1), before anything of that case runs", lines[:1] == [4], seg[-300:])
        row("a step from it shows the second condition, line 6 (case x = 2), tried because the first was false", lines[1:2] == [6], seg[-300:])
        row("a step from it shows line 7, the statement of the case that was chosen", lines[2:3] == [7], seg[-300:])
        row("CONTROL: R then runs it to the end (TWO and END are printed, ONE is not)",
            re.search(r"(?m)^TWO\s*$", seg) is not None and re.search(r"(?m)^END\s*$", seg) is not None and re.search(r"(?m)^ONE\s*$", seg) is None, seg[-300:])

        say("\n--- the first case is the one chosen --------------------------------------------------------------------")
        first, lines, seg = stops(box, FIRST, 2)
        say("    stopped at line %s, then stepped to %s" % (first, lines))
        row("the first condition (line 4) and then its own statement (line 5): the second condition is never shown",
            lines[:2] == [4, 5], seg[-300:])
    finally:
        for nm in (SECOND, FIRST):
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-dbgcase: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
