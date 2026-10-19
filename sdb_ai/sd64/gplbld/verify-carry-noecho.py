#!/usr/bin/env python3
#
# sandbox-noecho.py - 1.2-0 bundle B-5, sheet 168: INPUT, INPUT @ and INPUTFIELD take NO.ECHO, which suppresses the echo
#                     of what is typed (the new line at the end is still echoed).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-noecho.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 168.
# END-HISTORY
#
# THE INSTRUMENT.  As sandbox-input.py: a session piped to `sd -internal`, where SD's own echo is the only echo, so what an
# INPUT displayed is what the output holds.  A probe asks for a word with each form and prints the value it got; the word
# is one that appears nowhere else in the output (zq7secret), so its absence from the screen is evidence of no echo and its
# presence in the value, GOT[...], is evidence that the input was still taken.  Controls: the same word typed into a plain
# INPUT, an INPUT HIDDEN (asterisks) and an INPUT @ without the option IS echoed (and its asterisks shown).

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
WORD = "zq7secret"
passed = failed = 0
PROG = "zznoecho"


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
    say("sandbox-noecho: CANNOT RUN - " + msg)
    sys.exit(2)


def session(box, *cmds):
    say("    > [sd -internal] " + " | ".join(repr(c) for c in cmds))
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body,
                       cwd=os.path.join(box, "sys"), env=env, capture_output=True, text=True,
                       errors="replace", timeout=180)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def got(out, name):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % name, out)
    return m.group(1) if m else None


def after_marker(out, marker):
    """The text between marker line `marker` and the next marker line: what that one INPUT put on the screen."""
    m = re.search(r"(?ms)^%s\s*$(.*?)^(?:M\d|END)\b" % marker, out)
    if m is None:
        return None
    # the probe's own result line, A[value], carries the word: it is not echo
    return re.sub(r"(?m)^[A-H]\[.*\]\s*$", "", m.group(1))


PROGTEXT = (
    "   crt 'M0'\n   input a\n   crt 'A[':a:']'\n"
    "   crt 'M1'\n   input b no.echo\n   crt 'B[':b:']'\n"
    "   crt 'M2'\n   input c hidden\n   crt 'C[':c:']'\n"
    "   crt 'M3'\n   input d hidden no.echo\n   crt 'D[':d:']'\n"
    "   crt 'M4'\n   input @(0,5) : e, 20\n   crt 'E[':e:']'\n"
    "   crt 'M5'\n   input @(0,6) : f, 20 no.echo\n   crt 'F[':f:']'\n"
    "   crt 'M6'\n   input @(0,7) : g, 20 hidden no.echo\n   crt 'G[':g:']'\n"
    "   crt 'M7'\n   input h, 4 no.echo upcase\n   crt 'H[':h:']'\n"
    "   crt 'END'\nend\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-noecho.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-noecho: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-noecho: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    src = os.path.join(sysd, "bp", PROG)
    try:
        with open(src, "w") as f:
            f.write(PROGTEXT)
        out = session(box, "BASIC bp " + PROG)
        compiled = re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None
        row("setup: the probe compiles with no errors (NO.ECHO is accepted by INPUT and INPUT @)", compiled, out[-400:])
        if not compiled:
            bail("the probe did not compile")

        out = session(box, "RUN bp " + PROG, WORD + "1", WORD + "2", WORD + "3", WORD + "4", WORD + "5", WORD + "6", WORD + "7", "abcdef")
        row("the run reached its end", re.search(r"(?m)^END\s*$", out) is not None, out[-400:])
        for tg, n in (("A", 1), ("B", 2), ("C", 3), ("D", 4), ("E", 5), ("F", 6), ("G", 7)):
            row("%s: the value was taken (%s%d)" % (tg, WORD, n), got(out, tg) == WORD + str(n), repr(got(out, tg)))
        row("H: the value was taken, cut to 4 and put in upper case (UPCASE still works with NO.ECHO)", got(out, "H") == "ABCD", repr(got(out, "H")))

        s0, s1, s2, s3 = (after_marker(out, "M%d" % i) or "" for i in range(4))
        s4, s5, s6, s7 = (after_marker(out, "M%d" % i) or "" for i in range(4, 8))
        row("CONTROL: a plain INPUT echoes what is typed", WORD + "1" in s0, repr(s0))
        row("168: INPUT ... NO.ECHO does not echo it", WORD + "2" not in s1 and s1.strip() != "", repr(s1))
        row("CONTROL: INPUT HIDDEN echoes asterisks and not the text", "*" in s2 and WORD + "3" not in s2, repr(s2))
        row("168: HIDDEN NO.ECHO shows neither the text nor asterisks", WORD + "4" not in s3 and "*" not in s3, repr(s3))
        row("CONTROL: INPUT @ echoes what is typed", WORD + "5" in s4, repr(s4))
        row("168: INPUT @ ... NO.ECHO does not echo it", WORD + "6" not in s5, repr(s5))
        row("168: INPUT @ ... HIDDEN NO.ECHO shows neither the text nor asterisks, as INPUT does", WORD + "7" not in s6 and "*" not in s6, repr(s6))
    finally:
        for d in ("bp", "bp.out"):
            p = os.path.join(sysd, d, PROG)
            if os.path.exists(p):
                os.remove(p)

    say("\nsandbox-noecho: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
