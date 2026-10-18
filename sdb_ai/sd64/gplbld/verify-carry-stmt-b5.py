#!/usr/bin/env python3
#
# sandbox-stmt-b5.py - 1.2-0 bundle B-5 (openQM new and extended BASIC statements).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-stmt-b5.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for 1.2-0 bundle B-5: SSELECT ... RIGHT.ALIGNED / DESCENDING (243, 367), SSELECTN (209).
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets.  The ids 9, 10, 100 and abc are written
# to a scratch file; each row selects them a different way and prints the ids in list order, joined with /.
# The plain SSELECT is the CONTROL: it must give the old left-aligned order.  The clauses go BEFORE `to n`:
# after it the list-number expression reads the clause word as part of itself (measured; "Unassigned variable").

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

SETUP = ("execute 'CREATE.FILE zzb5f' capturing junk\n"
         "open 'zzb5f' to fv else stop\n"
         "write 'a' on fv, '9'\nwrite 'a' on fv, '10'\nwrite 'a' on fv, '100'\nwrite 'a' on fv, 'abc'\n")
COLLECT = ("x = ''\nloop\n   readnext id from %s else exit\n   x := id : '/'\nrepeat\n")

CASES = [
    ("CONTROL: plain SSELECT sorts left aligned (the old order)",
     SETUP + "sselect fv\n" + COLLECT % "0", "10/100/9/abc/"),
    ("243: RIGHT.ALIGNED sorts numbers by value, text after",
     SETUP + "sselect fv right.aligned\n" + COLLECT % "0", "9/10/100/abc/"),
    ("367: DESCENDING reverses the left aligned order",
     SETUP + "sselect fv descending\n" + COLLECT % "0", "abc/9/100/10/"),
    ("243+367: RIGHT.ALIGNED DESCENDING",
     SETUP + "sselect fv right.aligned descending\n" + COLLECT % "0", "abc/100/10/9/"),
    ("243+367: DESCENDING RIGHT.ALIGNED, the other order, is the same",
     SETUP + "sselect fv descending right.aligned\n" + COLLECT % "0", "abc/100/10/9/"),
    ("243 with TO: the clause before TO, the list goes to list 3",
     SETUP + "sselect fv right.aligned to 3\n" + COLLECT % "3", "9/10/100/abc/"),
    ("209: SSELECTN sorts into a numbered list",
     SETUP + "sselectn fv to 2\n" + COLLECT % "2", "10/100/9/abc/"),
    ("209: SSELECTN takes the clauses as well",
     SETUP + "sselectn fv right.aligned to 2\n" + COLLECT % "2", "9/10/100/abc/"),
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
    say("sandbox-stmt-b5: CANNOT RUN - " + msg)
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
        bail("usage: sandbox-stmt-b5.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-stmt-b5: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-stmt-b5: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for i, (_, body, _w) in enumerate(CASES):
        nm = "zzb5%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write("   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'C%02d[':x:']'\nend\n" % i)
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        say("\n--- the statements ------------------------------------------------------------")
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

    say("\nsandbox-stmt-b5: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
