#!/usr/bin/env python3
#
# sandbox-qproc-q20.py - QM4 gaps bundle Q-20 (query processor keywords): MEDIAN and RPT.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-qproc-q20.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-20.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT LIST printed for a file whose values are known.  The values are chosen so that the median
# is not the average (150, 40, 30, 20, 10: average 50, median 30), so a row cannot pass on the wrong statistic, and
# each leg has the neighbouring keyword's result as its CONTROL.
#
#   1  MEDIAN of an odd number of values, with AVERAGE beside it as the control
#   2  MEDIAN of an even number (the mean of the two in the middle), negative values, a value that is not a number
#   3  MEDIAN with a null: counted as zero, and left out with NO.NULLS
#   4  MEDIAN at a breakpoint (the subtotal line) and at the end of the report
#   5  RPT repeats a single valued field on every line of a multivalued report; the control does not

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
    say("sandbox-qproc-q20: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    if not quiet:
        for line in out.splitlines():
            if line.strip() and not line.startswith(":") and not line.startswith("exit "):
                say("      | " + line.rstrip()[:130])
    return out


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("latin-1"))   # a value mark is the byte 253


def after_rule(out, cmd):
    """The line after the ===== rule that LIST prints above a report's totals, for the command cmd."""
    part = out.split(cmd, 1)[-1]
    lines = part.splitlines()
    for i, ln in enumerate(lines):
        if ln.strip().startswith("====") and i + 1 < len(lines):
            return lines[i + 1].strip()
    return None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-qproc-q20.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-qproc-q20: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-qproc-q20: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    def make_file(fname, recs, dict_items):
        """recs: (id, field1, field2, field3); dict_items: (n, name, format, S or M)"""
        for rid, *flds in recs:
            prog("zzq20" + fname + rid, "\n".join(flds) + "\n")
        for n, nm, fmt, sm in dict_items:
            prog("zzq20d%s%d" % (fname, n), "D\n%d\n\n%s\n%s\n%s\n" % (n, nm, fmt, sm))
        cmds = ["DELETE.FILE DICT %s" % fname, "DELETE.FILE %s" % fname, "CREATE.FILE %s" % fname]
        for rid, *_ in recs:
            cmds.append("COPY FROM BP TO %s zzq20%s%s,%s" % (fname, fname, rid, rid))
        for n, nm, fmt, sm in dict_items:
            cmds.append("COPY FROM BP TO DICT %s zzq20d%s%d,%s" % (fname, fname, n, nm))
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        return copied == len(recs) + len(dict_items), copied

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        # zzq20a: name, num, grp.  150 40 30 20 10: the average is 50, the median 30.  Group a is r1 and r2, b the rest.
        ok, n = make_file("zzq20a", [("r1", "alpha", "150", "a"), ("r2", "bravo", "40", "a"), ("r3", "charlie", "30", "b"),
                                      ("r4", "delta", "20", "b"), ("r5", "echo", "10", "b")],
                          [(1, "name", "10L", "S"), (2, "num", "10R", "S"), (3, "grp", "10L", "S")])
        row("setup: the five records and three dictionary items of zzq20a were copied", ok, "copied %d" % n)

        say("\n--- leg 1: MEDIAN of an odd number of values -----------------------------------")
        out = sess(box, "LIST zzq20a AVERAGE num ID.SUP", "LIST zzq20a MEDIAN num ID.SUP")
        row("CONTROL: AVERAGE of 150 40 30 20 10 is 50", after_rule(out, "LIST zzq20a AVERAGE num ID.SUP") == "50", "got %r" % after_rule(out, "LIST zzq20a AVERAGE num ID.SUP"))
        got = after_rule(out, "LIST zzq20a MEDIAN num ID.SUP")
        row("THE ROW: MEDIAN of the same values is 30", got == "30", "got %r" % got)
        row("MEDIAN still lists the field's own values (150 appears, 5 records listed)",
            re.search(r"(?m)^\s*150\s*$", out.split("LIST zzq20a MEDIAN num ID.SUP", 1)[-1]) is not None and "5 record(s) listed" in out.split("LIST zzq20a MEDIAN num ID.SUP", 1)[-1],
            "values or the record count missing")

        say("\n--- leg 2: an even number, negative values, a value that is not a number ---------")
        ok, n = make_file("zzq20b", [("r1", "alpha", "150", "a"), ("r2", "bravo", "40", "a"), ("r3", "charlie", "30", "b"),
                                      ("r4", "delta", "20", "b"), ("r5", "echo", "10", "b"), ("r6", "foxtrot", "60", "b")],
                          [(1, "name", "10L", "S"), (2, "num", "10R", "S"), (3, "grp", "10L", "S")])
        row("setup: zzq20b has six records", ok, "copied %d" % n)
        out = sess(box, "LIST zzq20b MEDIAN num ID.SUP")
        got = after_rule(out, "LIST zzq20b MEDIAN num ID.SUP")
        row("six values 150 60 40 30 20 10: the median is the mean of 40 and 30 = 35", got == "35", "got %r" % got)
        ok, n = make_file("zzq20c", [("r1", "alpha", "150", "a"), ("r2", "bravo", "40", "a"), ("r3", "charlie", "30", "b"),
                                      ("r4", "delta", "20", "b"), ("r5", "echo", "10", "b"), ("r6", "foxtrot", "-10", "b")],
                          [(1, "name", "10L", "S"), (2, "num", "10R", "S"), (3, "grp", "10L", "S")])
        row("setup: zzq20c holds a negative value", ok, "copied %d" % n)
        out = sess(box, "LIST zzq20c MEDIAN num ID.SUP")
        got = after_rule(out, "LIST zzq20c MEDIAN num ID.SUP")
        row("six values 150 40 30 20 10 -10: sorted numerically -10 10 20 30 40 150, median 25", got == "25", "got %r" % got)
        ok, n = make_file("zzq20d", [("r1", "alpha", "150", "a"), ("r2", "bravo", "40", "a"), ("r3", "charlie", "30", "b"),
                                      ("r4", "delta", "20", "b"), ("r5", "echo", "10", "b"), ("r6", "foxtrot", "abc", "b")],
                          [(1, "name", "10L", "S"), (2, "num", "10R", "S"), (3, "grp", "10L", "S")])
        out = sess(box, "LIST zzq20d MEDIAN num ID.SUP")
        got = after_rule(out, "LIST zzq20d MEDIAN num ID.SUP")
        row("a value that is not a number (abc) is ignored: the median is 30", got == "30", "got %r" % got)

        say("\n--- leg 3: a null is zero, unless NO.NULLS --------------------------------------")
        ok, n = make_file("zzq20e", [("r1", "alpha", "150", "a"), ("r2", "bravo", "40", "a"), ("r3", "charlie", "30", "b"),
                                      ("r4", "delta", "20", "b"), ("r5", "echo", "10", "b"), ("r6", "foxtrot", "", "b")],
                          [(1, "name", "10L", "S"), (2, "num", "10R", "S"), (3, "grp", "10L", "S")])
        row("setup: zzq20e has a record with a null num", ok, "copied %d" % n)
        out = sess(box, "LIST zzq20e MEDIAN num ID.SUP", "LIST zzq20e MEDIAN num NO.NULLS ID.SUP")
        got = after_rule(out, "LIST zzq20e MEDIAN num ID.SUP")
        row("six values with a null as zero: 0 10 20 30 40 150, median 25", got == "25", "got %r" % got)
        got = after_rule(out, "LIST zzq20e MEDIAN num NO.NULLS ID.SUP")
        row("with NO.NULLS the null is left out: 10 20 30 40 150, median 30", got == "30", "got %r" % got)

        say("\n--- leg 4: MEDIAN at a breakpoint ------------------------------------------------")
        out = sess(box, "LIST zzq20a BY grp BREAK.ON grp MEDIAN num ID.SUP", "LIST zzq20a BY grp BREAK.ON grp AVERAGE num ID.SUP")
        med, ctl = out.split("LIST zzq20a BY grp BREAK.ON grp AVERAGE num ID.SUP")[0], out.split("LIST zzq20a BY grp BREAK.ON grp AVERAGE num ID.SUP")[-1]
        # the subtotal lines are the numbers on their own line after a line of dashes, then the grand figure after the ====
        subs_m = re.findall(r"(?m)^\*\*\s+-{3,}\s*\n\s*(?:\S+\s+)?(\d+(?:\.\d+)?)\s*$", med)
        subs_a = re.findall(r"(?m)^\*\*\s+-{3,}\s*\n\s*(?:\S+\s+)?(\d+(?:\.\d+)?)\s*$", ctl)
        row("CONTROL: AVERAGE per group: a is (150+40)/2 = 95, b is (30+20+10)/3 = 20", subs_a[:2] == ["95", "20"], "got %r" % subs_a)
        row("THE ROW: MEDIAN per group: a is the mean of 150 and 40 = 95, b is 20", subs_m[:2] == ["95", "20"], "got %r" % subs_m)
        got = after_rule(med, "BREAK.ON grp MEDIAN num ID.SUP")
        row("and the whole report still ends with the median 30", got == "30", "got %r" % got)

        say("\n--- leg 5: RPT -------------------------------------------------------------------")
        ok, n = make_file("zzq20f", [("r1", "alpha", "11" + chr(253) + "12" + chr(253) + "13"), ("r2", "bravo", "21" + chr(253) + "22")],
                          [(1, "name", "10L", "S"), (2, "num", "10R", "M")])
        row("setup: zzq20f has a multivalued num", ok, "copied %d" % n)
        out = sess(box, "LIST zzq20f name num ID.SUP", "LIST zzq20f name RPT num ID.SUP")
        parts = out.split("LIST zzq20f name RPT num ID.SUP")
        before = parts[0].split("LIST zzq20f name num ID.SUP")[-1]
        row("CONTROL: without RPT alpha appears once, on the first of its three lines", len(re.findall(r"alpha", before)) == 1 and len(re.findall(r"bravo", before)) == 1,
            "alpha %d, bravo %d" % (len(re.findall(r"alpha", before)), len(re.findall(r"bravo", before))))
        after = parts[-1]
        row("THE ROW: with RPT alpha is on all three lines and bravo on both of its two",
            len(re.findall(r"alpha", after)) == 3 and len(re.findall(r"bravo", after)) == 2 and "13" in after,
            "alpha %d, bravo %d" % (len(re.findall(r"alpha", after)), len(re.findall(r"bravo", after))))
        out = sess(box, "LIST zzq20f name num RPT ID.SUP")
        row("RPT on the multivalued item itself is accepted (it is then treated as single valued)", "2 record(s) listed" in out and "not found" not in out.lower(),
            "no record count or an error")

        say("\n--- leg 6: MODE and RANGE (16 Oct 26, sheet 231) -----------------------------------")
        # zzq20a: num 150 40 30 20 10 (range 140), grp a a b b b (mode b); zzq20e has a null num; zzq20c a negative one
        out = sess(box, "LIST zzq20a RANGE num ID.SUP", "LIST zzq20a MODE grp ID.SUP", "LIST zzq20a MODE num ID.SUP")
        got = after_rule(out, "LIST zzq20a RANGE num ID.SUP")
        row("THE ROW: RANGE of 150 40 30 20 10 is the largest less the smallest, 140", got == "140", "got %r" % got)
        got = after_rule(out, "LIST zzq20a MODE grp ID.SUP")
        row("THE ROW: MODE of the groups a a b b b is b", got == "b", "got %r" % got)
        got = after_rule(out, "LIST zzq20a MODE num ID.SUP")
        row("MODE with no value repeated gives one of them (the first, 150)", got in ("150", "40", "30", "20", "10"), "got %r" % got)
        out = sess(box, "LIST zzq20c RANGE num ID.SUP")
        got = after_rule(out, "LIST zzq20c RANGE num ID.SUP")
        row("RANGE with a negative value: 150 less -10 is 160", got == "160", "got %r" % got)
        out = sess(box, "LIST zzq20e RANGE num ID.SUP", "LIST zzq20e RANGE num NO.NULLS ID.SUP", "LIST zzq20e MODE num ID.SUP", "LIST zzq20e MODE num NO.NULLS ID.SUP")
        got = after_rule(out, "LIST zzq20e RANGE num ID.SUP")
        row("RANGE counts a null as zero: 150 less 0 is 150", got == "150", "got %r" % got)
        got = after_rule(out, "LIST zzq20e RANGE num NO.NULLS ID.SUP")
        row("RANGE with NO.NULLS leaves it out: 150 less 10 is 140", got == "140", "got %r" % got)
        out = sess(box, "LIST zzq20d RANGE num ID.SUP")
        got = after_rule(out, "LIST zzq20d RANGE num ID.SUP")
        row("RANGE ignores a value that is not a number (abc): 150 less 10 is 140", got == "140", "got %r" % got)
        out = sess(box, "LIST zzq20a BY grp BREAK.ON grp RANGE num ID.SUP", "LIST zzq20a BY grp BREAK.ON grp MODE name ID.SUP")
        rng, mod = out.split("LIST zzq20a BY grp BREAK.ON grp MODE name ID.SUP")[0], out.split("LIST zzq20a BY grp BREAK.ON grp MODE name ID.SUP")[-1]
        subs = re.findall(r"(?m)^\*\*\s+-{3,}\s*\n\s*(?:\S+\s+)?(\d+(?:\.\d+)?)\s*$", rng)
        row("RANGE per group: a is 150 less 40 = 110, b is 30 less 10 = 20", subs[:2] == ["110", "20"], "got %r" % subs)
        row("MODE at a breakpoint is shown too: each group has one name each, so any of its own", "alpha" in mod or "bravo" in mod or "charlie" in mod, mod[-300:])
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, *["DELETE.FILE DICT zzq20%s" % c for c in "abcdef"], *["DELETE.FILE zzq20%s" % c for c in "abcdef"], quiet=True)

    say("\nsandbox-qproc-q20: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
