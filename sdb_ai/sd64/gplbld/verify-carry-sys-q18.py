#!/usr/bin/env python3
#
# sandbox-sys-q18.py - QM4 gaps bundle Q-18 (SYSTEM() keys): 14 (type-ahead count), 19 and 21 (unique values), 45 (program
# name), 1048 (rolling sequence number), 1049 (HUSH), 1067 (default group size).  1086 (case sensitivity) is read back in
# sandbox-func-q1.py with the CASING statement.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-sys-q18.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-18.
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets.  A key whose value is a number the machine chooses
# (a time, a counter) is judged by a relation the program computes - two calls differ, the second is one more than the
# first - and prints 1 or 0, so the row cannot pass on a value that merely looks right.  @NAME@ in a body is the program's
# own name.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

CASES = []


def case(label, body, want):
    CASES.append((label, body, want))


case("SYSTEM(14) is a number, never negative (the count of waiting characters, a snapshot on a pipe)",
     "n = system(14)\nx = (n >= 0) : '/' : (n = int(n))", "1/1")
case("SYSTEM(19) is two five digit numbers, the date and the time of day",
     "v = system(19)\nx = len(v[1,10]) : '/' : (v[1,5] = int(date())) : '/' : (v[6,5] + 0 <= 86400)", "10/1/1")
case("SYSTEM(19) gives a different value every time, a letter on the end when the second repeats",
     "dim s(6)\nfor i = 1 to 6\n   s(i) = system(19)\nnext i\nsame = 0\nfor i = 1 to 5\n   for j = i + 1 to 6\n      if s(i) = s(j) then same += 1\n   next j\nnext i\n"
     "x = same : '/' : (s(1)[1,10] # '') : '/' : (index(s(2) : s(3) : s(4) : s(5) : s(6), 'a', 1) >= 0)", "0/1/1")
case("SYSTEM(21) is the date and a sequence number, the second call one more than the first",
     "a = system(21)\nb = system(21)\nx = len(a) : '/' : (a[1,5] = int(date())) : '/' : (b[6,5] + 0 = a[6,5] + 1) : '/' : (a[6,5] + 0 >= 1)", "10/1/1/1")
case("SYSTEM(45) is the pathname of a program run from a source file, which ends in its name (a catalogued one gives its name)",
     "p = system(45)\nx = (right(downcase(p), len('@NAME@')) = '@NAME@') : '/' : (p[1,1] = '/')", "1/1")
case("SYSTEM(1048) is a sequence number: the second call is one more than the first",
     "a = system(1048)\nb = system(1048)\nx = (a >= 1) : '/' : (b = a + 1)", "1/1")
case("SYSTEM(1049) is false by default, true under HUSH ON and false again after HUSH OFF",
     "a = system(1049)\nhush on\nb = system(1049)\nhush off\nx = a : '/' : b : '/' : system(1049)", "0/1/0")
case("SYSTEM(1067) is the default group size of a dynamic file in bytes", "x = system(1067)", "1024")


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
    say("sandbox-sys-q18: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def source(i, nm, body):
    lines = ["   x = ''"]
    lines += ["   " + ln for ln in body.replace("@NAME@", nm).split("\n")]
    lines.append("   crt 'C%02d[':x:']'" % i)
    lines.append("end")
    return "\n".join(lines) + "\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-sys-q18.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-sys-q18: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-sys-q18: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for i, (_label, body, _w) in enumerate(CASES):
        nm = "zzq18%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(source(i, nm, body))
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        if os.environ.get("SDSUITE_RAW"):
            say(out)
        say("\n--- the SYSTEM() keys ---------------------------------------------------------")
        for i, (label, _body, want) in enumerate(CASES):
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            row("%s: wanted %r" % (label, want), got == want, "got %r" % got if m else "no output")
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-sys-q18: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
