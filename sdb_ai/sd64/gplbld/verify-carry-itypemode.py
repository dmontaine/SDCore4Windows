#!/usr/bin/env python3
#
# sandbox-itypemode.py - compiler modes in front of a dictionary I-type expression (QM4 Fixes item 489).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-itypemode.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or absent).
# Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  gpl.bp/icomp: $MODE name{,name} ; in front of the expression.
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE LIST PRINTED FOR THE RECORDS (as sandbox-dict-a2.py's is): each I-type is read by LIST over two
# records, and each row names the value that comes out.  The mode rows are paired with the SAME expression without the mode, which
# gives another value, so that a mode that does nothing cannot pass; and the value a mode gives is the value a PROGRAM gives with
# the same $MODE (an oracle program prints it), not one worked out here.
#
#   r1  F1 = aaaaaaaaa      r2  F1 = abababab
#   INDEX.OVERLAP, COUNT.OVERLAP, CHANGE.NO.OVERLAP, NOCASE.STRINGS, TIME.MS (against SYSTEM(1020)), COMPATIBLE.APPEND (accepted),
#   a comma list, two $MODE statements, a mode turned off with a minus, a mode I-types cannot use (an error that names it), and an
#   I-type used by another I-type (an error).

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
    say("sandbox-itypemode: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("ascii"))


def values(out):
    """The values LIST printed for records r1 and r2, as a [r1, r2] pair; None if neither row is there."""
    got = {}
    for ln in out.splitlines():
        m = re.match(r"^(r[12])\b\s*(.*?)\s*$", ln.strip())
        if m:
            got[m.group(1)] = m.group(2)
    if not got:
        return None
    return [got.get("r1"), got.get("r2")]


ORACLE = """$mode %s
   x = %s
   crt 'ORA[=':x:']'
end
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-itypemode.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-itypemode: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-itypemode: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    def ditem(name, expr):
        prog("zzimd" + name, "I\n%s\n\n%s\n14L\nS\n" % (expr, name))

    items = {
        "idx0": "INDEX(F1,'aa',3)",
        "idx1": "$MODE INDEX.OVERLAP;INDEX(F1,'aa',3)",
        "cnt0": "COUNT(F1,'aa')",
        "cnt1": "$MODE COUNT.OVERLAP;COUNT(F1,'aa')",
        "chg0": "CHANGE(F1,'aa','xx',0,3)",
        "chg1": "$MODE CHANGE.NO.OVERLAP;CHANGE(F1,'aa','xx',0,3)",
        "nc0": "INDEX(F1,'AA',1)",
        "nc1": "$MODE NOCASE.STRINGS;INDEX(F1,'AA',1)",
        "both": "$MODE INDEX.OVERLAP,COUNT.OVERLAP;COUNT(F1,'aa')",
        "two": "$MODE INDEX.OVERLAP;$MODE COUNT.OVERLAP;COUNT(F1,'aa')",
        "neg": "$MODE COUNT.OVERLAP,-COUNT.OVERLAP;COUNT(F1,'aa')",
        "compat": "$MODE COMPATIBLE.APPEND;COUNT(F1,'aa')",
        "bad": "$MODE UV.LOCATE;COUNT(F1,'aa')",
        "nest": "TRANS(zzimf, @ID, idx1, 'X')",
        "tms0": "TIME()*1000 - SYSTEM(1020)",
        "tms1": "$MODE TIME.MS;TIME()*1000 - SYSTEM(1020)",
    }

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        prog("zzimr1", "aaaaaaaaa\n")
        prog("zzimr2", "abababab\n")
        prog("zzimf1", "D\n1\n\nF1\n10L\nS\n")
        for n, e in items.items():
            ditem(n, e)
        # the oracle: the same expressions in a program with the same $MODE
        oracles = {"idx1": ("INDEX.OVERLAP", "index('aaaaaaaaa', 'aa', 3)"), "cnt1": ("COUNT.OVERLAP", "count('aaaaaaaaa', 'aa')"),
                   "chg1": ("CHANGE.NO.OVERLAP", "change('aaaaaaaaa', 'aa', 'xx', 0, 3)"),
                   "chg0": ("DEFAULT", "change('aaaaaaaaa', 'aa', 'xx', 0, 3)"),
                   "nc1": ("NOCASE.STRINGS", "index('aaaaaaaaa', 'AA', 1)")}
        # NOCASE.STRINGS is a directive in a program, not a $MODE name: the oracle uses it as one
        prog("zzimo1", ORACLE % ("INDEX.OVERLAP", oracles["idx1"][1]))
        prog("zzimo2", ORACLE % ("COUNT.OVERLAP", oracles["cnt1"][1]))
        prog("zzimo3", ORACLE % ("CHANGE.NO.OVERLAP", oracles["chg1"][1]))
        prog("zzimo4", "   x = %s\n   crt 'ORA[=':x:']'\nend\n" % oracles["chg0"][1])
        prog("zzimo5", "$nocase.strings\n   x = %s\n   crt 'ORA[=':x:']'\nend\n" % oracles["nc1"][1])
        cmds = ["DELETE.FILE DICT zzimf", "DELETE.FILE zzimf", "CREATE.FILE zzimf",
                "COPY FROM BP TO zzimf zzimr1,r1", "COPY FROM BP TO zzimf zzimr2,r2", "COPY FROM BP TO DICT zzimf zzimf1,f1"]
        for n in items:
            cmds.append("COPY FROM BP TO DICT zzimf zzimd%s,%s" % (n, n))
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: all %d COPY commands each copied one record" % (len(cmds) - 3), copied == len(cmds) - 3, "copied lines: %d" % copied)
        out = sess(box, *["BASIC bp zzimo%d" % i for i in range(1, 6)] + ["RUN bp zzimo%d" % i for i in range(1, 6)], quiet=True)
        ora = re.findall(r"(?m)^ORA\[=(.*)\]\s*$", out)
        row("the oracle programs ran (five values from programs with the same modes)", len(ora) == 5, "got %r" % ora)
        o_idx, o_cnt, o_chg1, o_chg0, o_nc = ora if len(ora) == 5 else ("?",) * 5
        say("    program values: INDEX.OVERLAP %s  COUNT.OVERLAP %s  CHANGE.NO.OVERLAP %s  CHANGE plain %s  NOCASE INDEX %s" %
            (o_idx, o_cnt, o_chg1, o_chg0, o_nc))

        def get(item):
            return values(sess(box, "LIST zzimf %s" % item))

        say("\n--- the overlap modes, each against the same expression without it ---------------------------------------")
        a, b = get("idx0"), get("idx1")
        row("CONTROL  INDEX(F1,'aa',3) without the mode is not what the mode gives", a is not None and b is not None and a[0] != b[0], "%r %r" % (a, b))
        row("489  $MODE INDEX.OVERLAP;INDEX(...) gives what a program with the mode gives (%s)" % o_idx, b is not None and b[0] == o_idx, "got %r" % b)
        a, b = get("cnt0"), get("cnt1")
        row("CONTROL  COUNT(F1,'aa') without the mode is not what the mode gives", a is not None and b is not None and a[0] != b[0], "%r %r" % (a, b))
        row("489  $MODE COUNT.OVERLAP;COUNT(...) gives what a program with the mode gives (%s)" % o_cnt, b is not None and b[0] == o_cnt, "got %r" % b)
        a, b = get("chg0"), get("chg1")
        row("CONTROL  CHANGE without the mode gives what a program without it gives (%s)" % o_chg0, a is not None and a[0] == o_chg0, "got %r" % a)
        row("489  $MODE CHANGE.NO.OVERLAP;CHANGE(...) gives what a program with the mode gives (%s), which is not the plain value" % o_chg1,
            b is not None and b[0] == o_chg1 and o_chg1 != o_chg0, "got %r" % b)

        say("\n--- NOCASE.STRINGS, a list of modes, two statements, a minus -----------------------------------------------")
        a, b = get("nc0"), get("nc1")
        row("CONTROL  INDEX(F1,'AA',1) is case sensitive without the mode", a is not None and a[0] == "0", "got %r" % a)
        row("489  $MODE NOCASE.STRINGS;INDEX(F1,'AA',1) ignores case, as a program with the directive does (%s)" % o_nc,
            b is not None and b[0] == o_nc and o_nc != "0", "got %r" % b)
        b = get("both")
        row("489  two modes in one list: INDEX.OVERLAP,COUNT.OVERLAP", b is not None and b[0] == o_cnt, "got %r" % b)
        b = get("two")
        row("489  two $MODE statements, each ended by a semicolon", b is not None and b[0] == o_cnt, "got %r" % b)
        a = get("cnt0")
        b = get("neg")
        row("489  COUNT.OVERLAP,-COUNT.OVERLAP: a minus turns the mode off again", b is not None and a is not None and b[0] == a[0], "got %r want %r" % (b, a))
        b = get("compat")
        row("489  COMPATIBLE.APPEND is accepted (an I-type has no append to change)", b is not None and a is not None and b[0] == a[0], "got %r" % b)

        say("\n--- TIME.MS ---------------------------------------------------------------------------------------------------")
        best0 = best1 = None
        for _ in range(3):
            v0, v1 = get("tms0"), get("tms1")
            if v0 and v1 and v0[0] and v1[0]:
                x0, x1 = abs(float(v0[0])), abs(float(v1[0]))
                best0 = x0 if best0 is None else max(best0, x0)
                best1 = x1 if best1 is None else max(best1, x1)
        say("    TIME()*1000 - SYSTEM(1020): without the mode up to %s ms off, with it up to %s" % (best0, best1))
        row("CONTROL  plain TIME() is whole seconds: it differs from SYSTEM(1020) by the milliseconds (more than 5 at least once in 3 tries)",
            best0 is not None and best0 > 5, "up to %r" % best0)
        row("489  $MODE TIME.MS;TIME() is the time to the millisecond: within a few ms of SYSTEM(1020) every time",
            best1 is not None and best1 <= 5, "up to %r" % best1)

        say("\n--- what an I-type may not do ---------------------------------------------------------------------------------")
        out = sess(box, "LIST zzimf bad")
        row("489  a mode that is not allowed names itself in the error: 'UV.LOCATE is not a mode that an I-type can use'",
            "UV.LOCATE is not a mode that an I-type can use" in out, repr(out[-300:]))
        out = sess(box, "LIST zzimf nest")
        row("489  an I-type that is used by another cannot set modes", "cannot set compiler modes" in out, repr(out[-300:]))
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zzimf", "DELETE.FILE zzimf", quiet=True)

    say("\nsandbox-itypemode: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
