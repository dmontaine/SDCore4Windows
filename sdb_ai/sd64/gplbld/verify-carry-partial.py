#!/usr/bin/env python3
#
# sandbox-partial.py - $MODE PARTIAL.EXPRESSIONS (openQM 4 release item, sheet 417).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-partial.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  bcomp (expr.common): under the mode AND and OR are compiled as DUP, a conditional jump over the
#               right hand side and the operator, so the right hand side is not evaluated when the left settles it.
# END-HISTORY
#
# The verdicts: (1) a run time error the full evaluation raises is avoided, (2) an expression's VALUE is the same with
# the mode on and off for every combination of operands (the truth table, nesting, left-to-right grouping), (3) a side
# effect (a counter changed by a subroutine through COMMON) happens only where the expression needed it, and the
# mode-off program shows the same expression doing it every time.

import itertools
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
    say("sandbox-partial: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


# every combination of a, b, c through the expressions below; each result is printed with its label
TABLE = """   for a = 0 to 1
      for b = 0 to 1
         for c = 0 to 1
            r1 = (a and b)
            r2 = (a or b)
            r3 = (a and b or c)
            r4 = (a or b and c)
            r5 = ((a or b) and c)
            r6 = (a and (b or c))
            r7 = (not(a) and b)
            r8 = (a and b and c)
            r9 = (a or b or c)
            r10 = (if a and b then 1 else 0)
            crt 'T ':a:b:c:' ':r1:r2:r3:r4:r5:r6:r7:r8:r9:r10
         next c
      next b
   next a
"""

SIDE = """   common /sd/ cnt
   cnt = 0
   x = 0
   if x = 1 and bump() then crt 'S1-THEN' else crt 'S1-ELSE'
   x = 1
   if x = 1 or bump() then crt 'S2-THEN' else crt 'S2-ELSE'
   crt 'COUNT-AFTER-SHORT ':cnt
   x = 1
   if x = 1 and bump() then crt 'S3-THEN' else crt 'S3-ELSE'
   crt 'COUNT-AFTER-FULL ':cnt
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-partial.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-partial: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-partial: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    bump = "zzpb" + RUN
    idx_on, idx_off = "zzpion" + RUN, "zzpioff" + RUN
    tab_on, tab_off = "zzpton" + RUN, "zzptoff" + RUN
    side_on, side_off = "zzpson" + RUN, "zzpsoff" + RUN
    idx_body = """   s = 'x'
   idx = 'abc'
   if idx matches '1-2N' and s<idx> # 0 then crt 'IDX-THEN' else crt 'IDX-ELSE'
   crt 'IDX-DONE'
end
"""
    progs = {
        # the called subroutine counts calls in common and answers true
        bump: "   function %s()\n   common /sd/ cnt\n   cnt += 1\n   return(1)\nend\n" % bump,
        idx_on: "$mode partial.expressions\n" + idx_body,
        idx_off: idx_body,
        tab_on: "$mode partial.expressions\n" + TABLE + "end\n",
        tab_off: TABLE + "end\n",
        side_on: "$mode partial.expressions\n   deffun bump()\n" + SIDE + "end\n",
        side_off: "   deffun bump()\n" + SIDE + "end\n",
    }
    for name, text in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(text)
    # the side effect program calls the function by its catalogued name bump
    # (the function is catalogued under that name below)
    with open(os.path.join(sysd, "bp", side_on), "w") as fh:
        fh.write(progs[side_on].replace("bump()", "%s()" % bump))
    with open(os.path.join(sysd, "bp", side_off), "w") as fh:
        fh.write(progs[side_off].replace("bump()", "%s()" % bump))

    say("\n--- $MODE PARTIAL.EXPRESSIONS ---------------------------------------------------------------------------")
    out = sess(box, "BASIC bp %s" % bump, "CATALOG bp %s LOCAL" % bump,
               *["BASIC bp %s" % n for n in (idx_on, idx_off, tab_on, tab_off, side_on, side_off)])
    row("setup: every program compiled with no errors", out.count("Compiled 1 program(s) with no errors") == 7, out[-800:])

    o_off = sess(box, "RUN bp %s" % idx_off)
    o_on = sess(box, "RUN bp %s" % idx_on)
    row("CONTROL, the mode off: S<idx> with a non-numeric idx is evaluated and stops the program with a run time error",
        "IDX-DONE" not in o_off and "IDX-ELSE" not in o_off and "IDX-THEN" not in o_off and "on-numeric" in o_off, o_off[-300:])
    row("the mode on: the test of S<idx> is skipped and the program carries on (IDX-ELSE then IDX-DONE)",
        "IDX-ELSE" in o_on and "IDX-DONE" in o_on and "IDX-THEN" not in o_on, o_on[-300:])

    t_off = sess(box, "RUN bp %s" % tab_off)
    t_on = sess(box, "RUN bp %s" % tab_on)
    lines_off = re.findall(r"(?m)^T (\d{3}) (\d+)\s*$", t_off)
    lines_on = re.findall(r"(?m)^T (\d{3}) (\d+)\s*$", t_on)
    row("CONTROL: the truth table has all eight rows of operands (a, b, c) in the mode-off run",
        len(lines_off) == 8 and sorted(x[0] for x in lines_off) == sorted("".join(p) for p in itertools.product("01", repeat=3)),
        t_off[-500:])
    row("the mode on gives every one of the ten expressions the same value as the mode off, for all eight rows",
        lines_on == lines_off and len(lines_on) == 8, "on=%r off=%r" % (lines_on, lines_off))

    s_off = sess(box, "RUN bp %s" % side_off)
    s_on = sess(box, "RUN bp %s" % side_on)
    row("CONTROL, the mode off: the function is called by every one of the three tests (count 3 after them)",
        re.search(r"(?m)^COUNT-AFTER-FULL 3\s*$", s_off) is not None and re.search(r"(?m)^COUNT-AFTER-SHORT 2\s*$", s_off) is not None,
        s_off[-400:])
    row("the mode on: the first test (false AND f()) and the second (true OR f()) do not call it, the third does",
        re.search(r"(?m)^COUNT-AFTER-SHORT 0\s*$", s_on) is not None and re.search(r"(?m)^COUNT-AFTER-FULL 1\s*$", s_on) is not None
        and "S1-ELSE" in s_on and "S2-THEN" in s_on and "S3-THEN" in s_on, s_on[-400:])

    say("")
    say("sandbox-partial: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
