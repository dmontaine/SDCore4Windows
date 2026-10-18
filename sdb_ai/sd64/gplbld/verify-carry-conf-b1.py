#!/usr/bin/env python3
#
# sandbox-conf-b1.py - 1.2-0 bundle B-1 (openQM configuration parameters and command line options).  No install,
#                      no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-conf-b1.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for 1.2-0 bundle B-1: the INTPREC default 11 (6), SORTMEM default 4096 kb (535), the new
#               INVCASE parameter (399) and `sd -status` (511).
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets (CONFIG() reads), and, for -status, the
# sandbox's own bin/sd run against the sandbox's own shared memory (SD_CONFIG points at its config).  A CONTROL on
# each: FSYNC, a parameter that already existed, must read back its default (0).

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

CASES = [
    ("CONTROL: FSYNC, an existing parameter, reads its default", "x = config('FSYNC')", "0"),
    ("6: INTPREC defaults to 11", "x = config('INTPREC')", "11"),
    ("535: SORTMEM defaults to 4096 (kb)", "x = config('SORTMEM')", "4096"),
    ("399: INVCASE exists and defaults to 0", "x = config('INVCASE')", "0"),
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
    say("sandbox-conf-b1: CANNOT RUN - " + msg)
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
        bail("usage: sandbox-conf-b1.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-conf-b1: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-conf-b1: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for i, (_, body, _w) in enumerate(CASES):
        nm = "zzb1%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write("   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'C%02d[':x:']'\nend\n" % i)
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        say("\n--- the parameters ------------------------------------------------------------")
        for i, (label, _body, want) in enumerate(CASES):
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            row("%s: wanted %r" % (label, want), got == want, "got %r" % got if m else "no output")

        say("\n--- sd -status ----------------------------------------------------------------")
        env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
        p = subprocess.run([os.path.join(sysd, "bin", "sd"), "-status"], capture_output=True, text=True, env=env, timeout=60)
        say("    " + p.stdout.replace("\n", "\n    ").rstrip())
        row("511: -status names the version", re.search(r"(?m)^SD \(\S+\)$", p.stdout) is not None, p.stdout[:80])
        row("511: -status shows a start time from this year or later",
            re.search(r"(?m)^Started   20(2[6-9]|[3-9]\d)-\d\d-\d\d \d\d:\d\d:\d\d$", p.stdout) is not None, p.stdout[:120])
        row("511: -status counts the process counts and the limit",
            re.search(r"(?m)^Users     \d+ interactive, \d+ phantom, \d+ API, limit \d+$", p.stdout) is not None, p.stdout[:160])
        row("511: -status does not claim SD is inactive", "not active" not in p.stdout)
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-conf-b1: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
