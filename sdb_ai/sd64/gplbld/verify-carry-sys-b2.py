#!/usr/bin/env python3
#
# sandbox-sys-b2.py - 1.2-0 bundle B-2 (openQM SYSTEM() / FILEINFO() / GETPU() key values).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-sys-b2.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for 1.2-0 bundle B-2: SYSTEM(35) users, SYSTEM(1016) users available, SYSTEM(1045) start
#               time as a Unix epoch value, SYSTEM(1047) a GUID.
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets.  Every row's expression uses only the
# key under test and a CONTROL key SD already had (1013, the user limit), so a row cannot pass by printing nothing.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

# (label, BASIC statements one per line leaving the value in x, wanted regular expression for the whole bracket)
CASES = [
    ("CONTROL: SYSTEM(1013) is the user limit, a positive number", "x = system(1013) > 0", r"1"),
    ("35: at least this session is counted", "x = system(35) >= 1", r"1"),
    ("35 and 1016 add up to the user limit", "x = (system(35) + system(1016)) = system(1013)", r"1"),
    ("1045: started after 2020 and not in the future (Unix epoch)",
     "t = system(1045)\nx = (t > 1577836800) and (t <= system(1005) - 732 * 86400 + 86400)", r"1"),
    ("1045 is not later than this session's login time, taken from key 1030 (same clock, days from 1967)",
     "x = (system(1045) <= system(1030) - 732 * 86400 + 86400)", r"1"),
    ("1047: a GUID has 36 characters", "x = len(system(1047))", r"36"),
    ("1047: in the 8-4-4-4-12 shape", "g = system(1047)\nx = (g[9,1]:g[14,1]:g[19,1]:g[24,1])", r"----"),
    ("1047: two calls give two values", "x = (system(1047) # system(1047))", r"1"),
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
    say("sandbox-sys-b2: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-sys-b2.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-sys-b2: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-sys-b2: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for i, (_, body, _w) in enumerate(CASES):
        nm = "zzb2%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write("   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'C%02d[':x:']'\nend\n" % i)
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        say("\n--- the keys ------------------------------------------------------------------")
        for i, (label, _body, want) in enumerate(CASES):
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            row("%s: wanted /%s/" % (label, want), got is not None and re.fullmatch(want, got) is not None,
                "got %r" % got if m else "no output")
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-sys-b2: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
