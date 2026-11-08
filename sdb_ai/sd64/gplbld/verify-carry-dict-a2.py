#!/usr/bin/env python3
#
# sandbox-dict-a2.py - 1.2-0 bundle A-2 (openQM features after 2.6.6, the dictionary compilers):
#                      does ICOMP do what each item says, against records in a real file?
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-dict-a2.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree
# (it must be empty or absent).  Needs no install, no sudo.  Exit 0 every row passed, 1 a row failed,
# 2 it could not run.
#
# START-HISTORY:
# 27 Oct 26 dm  S.87 batch 10: legs 1 (IF without ELSE or THEN), 3 (format string with no operator) and 4 (hyphenated item names) keep only their controls; the three forms were removed from ICOMP.
# 10 Oct 26 dm  Written for 1.2-0 bundle A-2.
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE LIST PRINTED FOR THE RECORDS, not the compiler's silence: each item is
# an I-type read by LIST over two records whose values are known, and each row names the value that
# comes out.  CONTROLS: an expression that was already legal gives the same answer it always did, so
# a row cannot pass because LIST printed nothing.
#
# Legs and openQM reference numbers (column A of the spreadsheet):
#   1  IF with no ELSE, and with no THEN (36)
#   2  a field named by its number, F4 (547)
#   3  a value followed by a format string with no operator (564)
#   4  an item named with a hyphen (423), and A-B still a subtraction
#   5  TRANS() of an A, S item (182)
#   6  divide by zero in a dictionary expression is zero (48) - the kernel's op_arith.c

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
    say("sandbox-dict-a2: CANNOT RUN - " + msg)
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
                say("      | " + line.rstrip()[:120])
    return out


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("ascii"))


def values(out, item):
    """The values LIST printed for records r1 and r2, by record id, as a (r1, r2) pair; None if neither row is there."""
    got = {}
    for ln in out.splitlines():
        m = re.match(r"^(r[12])\b\s*(.*?)\s*$", ln.strip())
        if m:
            got[m.group(1)] = m.group(2)
    if not got:
        return None
    return [got.get("r1"), got.get("r2")]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-dict-a2.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-dict-a2: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-dict-a2: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    def ditem(name, expr):
        prog("zzd2" + name, "I\n%s\n\n%s\n12R\nS\n" % (expr, name))

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        # r1: F1=10 F2=0 F3=abc F4=7 F5=3     r2: F1=1 F2=2 F3=xyz F4=5 F5=4
        prog("zzd2r1", "10\n0\nabc\n7\n3\n")
        prog("zzd2r2", "1\n2\nxyz\n5\n4\n")
        for n in (1, 2, 3, 5):
            prog("zzd2f%d" % n, "D\n%d\n\nF%d\n8R\nS\n" % (n, n))
        ditem("t48", "F1 / F2")
        ditem("tsub", "F1-F2")
        ditem("tctl", "IF F1 > 5 THEN 'big' ELSE 'small'")
        ditem("t182", "TRANS(zzd2b, F3, QA, 'X')")
        ditem("t182c", "TRANS(zzd2b, F3, QI, 'X')")
        # 16 Oct 26, ref 104: field 8 of an A item that begins IF is an implied A-correlative.  The control is the same
        # expression with the type letter and a semicolon in front (it always worked); the third item is a plain conversion code.
        prog("zzd2tia", "A\n1\n\ntia\n8L\nS\n\nIF 1 > \"5\" THEN \"big\" ELSE \"small\"\n")
        prog("zzd2tib", "A\n1\n\ntib\n8L\nS\n\nA;IF 1 > \"5\" THEN \"big\" ELSE \"small\"\n")
        prog("zzd2tic", "A\n3\n\ntic\n8L\nS\n\nMCU\n")
        prog("zzd2b1", "FOUND\n")
        prog("zzd2b2", "OTHER\n")
        prog("zzd2qa", "A\n1\n\nQA\n8L\nS\n")             # A item, no correlative, field 1
        prog("zzd2qi", "I\n'<':@RECORD<1>:'>'\n\nQI\n12L\nS\n")   # I item (control)
        cmds = ["DELETE.FILE DICT zzd2a", "DELETE.FILE zzd2a", "DELETE.FILE DICT zzd2b", "DELETE.FILE zzd2b",
                "CREATE.FILE zzd2a", "CREATE.FILE zzd2b",
                "COPY FROM BP TO zzd2a zzd2r1,r1", "COPY FROM BP TO zzd2a zzd2r2,r2",
                "COPY FROM BP TO zzd2b zzd2b1,abc", "COPY FROM BP TO zzd2b zzd2b2,xyz",
                "COPY FROM BP TO DICT zzd2b zzd2qa,qa", "COPY FROM BP TO DICT zzd2b zzd2qi,qi"]
        for n in (1, 2, 3):
            cmds.append("COPY FROM BP TO DICT zzd2a zzd2f%d,f%d" % (n, n))
        for t in ("t48", "tsub", "tctl", "t182", "t182c", "tia", "tib", "tic"):
            cmds.append("COPY FROM BP TO DICT zzd2a zzd2%s,%s" % (t, t))
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: all %d COPY commands each copied one record" % (len(cmds) - 4 - 2), copied == len(cmds) - 6,
            "copied lines: %d" % copied)

        def check(label, item, want, why=""):
            out = sess(box, "LIST zzd2a %s" % item)
            got = values(out, item)
            row("%s: %s gives %r, %r" % (label, item, want[0], want[1]), got == list(want), "got %r" % got)

        say("\n--- leg 1: IF THEN ELSE (ref 36: IF without ELSE or THEN was retired 27 Oct 26, S.87 batch 10) ------------")
        check("CONTROL: IF THEN ELSE as before", "tctl", ("big", "small"))

        say("\n--- leg 2: (F4 naming field 4 with no D item, ref 547, was retired 27 Oct 26) ---------------------------")

        say("\n--- leg 3: (a value and a format string with no operator, ref 564, was retired 27 Oct 26) ---------------")

        say("\n--- leg 4: F1-F2 is a subtraction (hyphenated item names, ref 423, were retired 27 Oct 26) -----------------")
        check("CONTROL: F1-F2 is a subtraction", "tsub", ("10", "-1"))

        say("\n--- leg 5: TRANS() of an A item (ref 182) ----------------------------------------------")
        check("THE ROW: qa is an A item, field 1, no correlative", "t182", ("FOUND", "OTHER"))
        check("CONTROL: qi is an I item, as it always could be", "t182c", ("<FOUND>", "<OTHER>"))

        say("\n--- leg 6: divide by zero in a dictionary expression (ref 48, kernel op_arith.c) -----------")
        check("THE ROW: F1/F2 with F2 = 0 is zero; with F2 = 2 it is the quotient", "t48", ("0", "0.5"))

        say("\n--- leg 7: an IF expression in field 8 of an A item is an implied A-correlative (ref 104) --------")
        check("CONTROL: A;IF ... always worked", "tib", ("big", "small"))
        check("THE ROW: IF ... with no A; in front gives the same", "tia", ("big", "small"))
        check("CONTROL: a plain conversion code in field 8 is still a conversion code (MCU on field 3)", "tic", ("ABC", "XYZ"))
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zzd2a", "DELETE.FILE zzd2a", "DELETE.FILE DICT zzd2b", "DELETE.FILE zzd2b", quiet=True)

    say("\nsandbox-dict-a2: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
