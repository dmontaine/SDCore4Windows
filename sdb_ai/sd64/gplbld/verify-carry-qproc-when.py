#!/usr/bin/env python3
#
# sandbox-qproc-when.py - 1.2-0 bundle A-3, sheet 543 / 572: WHEN clause operators and more than one
#                         exploded sort (BY.EXP / BY.EXP.DSND).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-qproc-when.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written (sheet 543, 572).
# END-HISTORY
#
# One record m1, an association AS of three multivalued fields (values separated by value marks):
#   vals  Apple ] banana ] Cherry     num  3 ] 2 ] 1     tag  (null) ] x ] y
#
#   1  WHEN tag (no operator = not null): x and y only; control WHEN tag NE "" prints the same
#   2  WHEN vals BETWEEN "B" "D": case-sensitive, so Cherry only; control NO.CASE BETWEEN gives banana, Cherry
#   3  WHEN vals UNLIKE "A..." NO.CASE: Apple is removed whatever its case; control: UNLIKE with the right case
#   4  BY.EXP vals BY.EXP num (same association): accepted, num breaks ties of vals
#   5  BY.EXP vals BY.EXP.DSND num: second key descending
#   6  BY.EXP with a second BY.EXP on a field outside the association: refused with message 11247
#   7  CONTROL: one BY.EXP and one BY in the association behave as before

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
    say("sandbox-qproc-when: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    if not quiet:
        say("    > " + " | ".join(cmds))
        for line in out.splitlines():
            if line.strip() and not line.startswith(":") and not line.startswith("exit "):
                say("      | " + line.rstrip()[:130])
    return out


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("ascii"))


def after(out, cmd):
    """What the session printed after the echo of cmd, up to the next prompt echo."""
    return out.split(cmd, 1)[-1]


def words(text, universe):
    return [w for w in re.findall(r"[A-Za-z]+", text) if w in universe]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-qproc-when.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    vm = "\xfd"

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    names = {"Apple", "banana", "Cherry"}
    try:
        say("--- setup ----------------------------------------------------------------------")
        # the value mark is byte 253 (0xFD) in an SD directory record; write() is ASCII only, so bytes here
        made.append("zzqwm1")
        with open(os.path.join(bp, "zzqwm1"), "wb") as f:
            f.write(b"Apple\xfdbanana\xfdCherry\n3\xfd2\xfd1\n\xfdx\xfdy\n")
        # dictionary: D / field no / conv / name / format / S or M / association
        for i, nm in ((1, "vals"), (2, "num"), (3, "tag")):
            prog("zzqwd%d" % i, "D\n%d\n\n%s\n10L\nM\nAS\n" % (i, nm))
        prog("zzqwd4", "D\n4\n\nother\n10L\nM\nOA\n")
        cmds = ["DELETE.FILE DICT zzqw", "DELETE.FILE zzqw", "CREATE.FILE zzqw", "COPY FROM BP TO zzqw zzqwm1,m1"]
        for i, nm in ((1, "vals"), (2, "num"), (3, "tag"), (4, "other")):
            cmds.append("COPY FROM BP TO DICT zzqw zzqwd%d,%s" % (i, nm))
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: all 5 COPY commands each copied one record", copied == 5, "copied lines: %d" % copied)

        say("\n--- leg 1: WHEN with no operator is 'not null' ------------------------------------")
        c1, c2 = 'LIST zzqw tag WHEN tag NE "" ID.SUP', "LIST zzqw tag WHEN tag ID.SUP"
        out = sess(box, c1, c2)
        ctl = [w for w in re.findall(r"(?m)^\s*([xy])\s*$", after(out, c1).split(c2)[0])]
        got = [w for w in re.findall(r"(?m)^\s*([xy])\s*$", after(out, c2))]
        row("CONTROL: WHEN tag NE \"\" lists x and y", ctl == ["x", "y"], "got %r" % ctl)
        row("THE ROW: WHEN tag lists x and y and not the null value", got == ["x", "y"], "got %r" % got)

        say("\n--- leg 2: WHEN BETWEEN is case sensitive, NO.CASE is not ------------------------")
        c1 = 'LIST zzqw vals WHEN vals BETWEEN "B" "D" ID.SUP'
        c2 = 'LIST zzqw vals WHEN vals BETWEEN NO.CASE "B" "D" ID.SUP'
        out = sess(box, c1, c2)
        a = words(after(out, c1).split(c2)[0], names)
        b = words(after(out, c2), names)
        row("THE ROW: BETWEEN \"B\" \"D\" lists Cherry only", a == ["Cherry"], "got %r" % a)
        row("CONTROL: with NO.CASE banana is in as well", sorted(b) == ["Cherry", "banana"], "got %r" % b)

        say("\n--- leg 3: WHEN UNLIKE NO.CASE ------------------------------------------------------")
        c1 = 'LIST zzqw vals WHEN vals UNLIKE "A..." ID.SUP'
        c2 = 'LIST zzqw vals WHEN vals UNLIKE NO.CASE "a..." ID.SUP'
        out = sess(box, c1, c2)
        a = words(after(out, c1).split(c2)[0], names)
        b = words(after(out, c2), names)
        row("CONTROL: UNLIKE \"A...\" removes Apple", a == ["banana", "Cherry"], "got %r" % a)
        row("THE ROW: UNLIKE NO.CASE \"a...\" removes Apple too", b == ["banana", "Cherry"], "got %r" % b)

        say("\n--- leg 4/5: two exploded sorts in one association ------------------------------------")
        # vals / num pairs: Apple 3, banana 2, Cherry 1; with two sorts the values are distinct, so the
        # second key decides nothing - put num first to see it order the rows: BY.EXP num BY.EXP vals
        c1 = "LIST zzqw vals num BY.EXP num BY.EXP vals ID.SUP"
        c2 = "LIST zzqw vals num BY.EXP vals BY.EXP.DSND num ID.SUP"
        out = sess(box, c1, c2)
        a = words(after(out, c1).split(c2)[0], names)
        b = words(after(out, c2), names)
        row("THE ROW: BY.EXP num BY.EXP vals is accepted and sorts by num: Cherry banana Apple",
            a == ["Cherry", "banana", "Apple"] and "Only one exploded" not in out, "got %r" % a)
        row("THE ROW: BY.EXP vals BY.EXP.DSND num is accepted, and sorts by vals, bytewise, so capitals first: Apple Cherry banana",
            b == ["Apple", "Cherry", "banana"], "got %r" % b)

        say("\n--- leg 6: a second exploded sort outside the association is refused -----------------")
        c1 = "LIST zzqw vals BY.EXP vals BY.EXP other ID.SUP"
        out = sess(box, c1)
        row("THE ROW: message 11247 and no list", "same association" in after(out, c1) and not words(after(out, c1), names),
            "output: %r" % after(out, c1)[:200])

        say("\n--- leg 7: control, one BY.EXP and one BY ------------------------------------------")
        c1 = "LIST zzqw vals num BY.EXP.DSND num BY vals ID.SUP"
        out = sess(box, c1)
        a = words(after(out, c1), names)
        row("CONTROL: BY.EXP.DSND num BY vals: Apple banana Cherry", a == ["Apple", "banana", "Cherry"], "got %r" % a)
    finally:
        for n in made:
            p = os.path.join(bp, n)
            if os.path.exists(p):
                os.remove(p)
        sess(box, "DELETE.FILE DICT zzqw", "DELETE.FILE zzqw", quiet=True)

    say("\nsandbox-qproc-when: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
