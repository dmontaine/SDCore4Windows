#!/usr/bin/env python3
#
# sandbox-epoch.py - sheet 124 and the epoch family of openQM 4: EPOCH(), MVDATE(), MVTIME(), MVDATE.TIME(), MVEPOCH(time.string) and
#                    MVEPOCH(date, time).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-epoch.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 124 and the epoch functions.
# END-HISTORY
#
# THE INSTRUMENT.  One probe program prints, for fixed epoch values, what each function gives; the expected values are worked out here
# in Python from the zone database (zoneinfo), independently of the C code.  The zone is the process's (the TZ variable): the program
# runs once under UTC, once under Asia/Kathmandu (+5:45, no summer time) and once under America/Los_Angeles (summer time), so a result
# that ignores the zone, or applies a fixed offset, cannot pass in all three.  1234567890 is the manual's example (15020 / 15021).

import os
import re
import subprocess
import sys
import time
from datetime import datetime
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
EPOCHS = (1234567890, 1247000000, 1700000000, 0, -86400, 2147483647, -2147483648)


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
    say("sandbox-epoch: CANNOT RUN - " + msg)
    sys.exit(2)


def session(box, tz, *cmds):
    say("    > [TZ=%s] %s" % (tz, " | ".join(cmds)))
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"), TZ=tz)
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"), env=env,
                       capture_output=True, text=True, errors="replace", timeout=180)
    return ANSI.sub("", p.stdout + p.stderr)


def tag(out, name):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % name, out)
    return None if m is None else m.group(1)


def expect(e, tz):
    """MVDATE, MVTIME for epoch e in zone tz, worked out from the zone database."""
    dt = datetime.fromtimestamp(e, ZoneInfo(tz))
    days = (dt.date() - datetime(1967, 12, 31).date()).days
    secs = dt.hour * 3600 + dt.minute * 60 + dt.second
    return days, secs


PROG = (
    "   ep = ''\n"
    + "".join("   e = %d\n   crt 'D%d[':mvdate(e):']'\n   crt 'T%d[':mvtime(e):']'\n   crt 'DT%d[':mvdate.time(e):']'\n"
               "   crt 'R%d[':mvepoch(mvdate(e), mvtime(e)):']'\n   crt 'S%d[':mvepoch(mvdate.time(e)):']'\n" % ((e,) + (i,) * 5)
               for i, e in enumerate(EPOCHS))
    + "   crt 'NOW[':epoch():']'\n"
    "   crt 'NULL1[':mvepoch(''):']'\n"
    "   crt 'NULL2[':mvepoch('abc'):']'\n"
    "   crt 'NULL3[':mvepoch(15020, 90000):']'\n"
    "   crt 'NULL4[':mvdate(99999999999):']'\n"
    "   crt 'NULL5[':mvepoch('15020'):']'\n"
    "   e = 1234567890\n   crt 'FRAC[':mvepoch(mvdate(e), mvtime(e) + 0.75):']'\n"
    "   crt 'SYS[':system(1035) - epoch():']'\n"
    "   crt 'END'\nend\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-epoch.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-epoch: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-epoch: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        for nm, text in (("zzep", PROG),
                         ("zzepbad", "   x = mvepoch()\nend\n"),
                         ("zzepbad2", "   x = mvdate(1, 2)\nend\n")):
            with open(os.path.join(sysd, "bp", nm), "w") as fh:
                fh.write(text)
            made.append(nm)
        out = session(box, "UTC", "BASIC bp zzep")
        row("setup: the probe compiles with no errors", "Compiled 1 program(s) with no errors" in out, out[-600:])
        out = session(box, "UTC", "BASIC bp zzepbad")
        row("MVEPOCH() with no argument is a compile error", "Compiled 1 program(s) with no errors" not in out, out[-300:])
        out = session(box, "UTC", "BASIC bp zzepbad2")
        row("MVDATE() with two arguments is a compile error", "Compiled 1 program(s) with no errors" not in out, out[-300:])

        for tz in ("UTC", "Asia/Kathmandu", "America/Los_Angeles"):
            out = session(box, tz, "RUN bp zzep")
            row("[%s] the run reached its end" % tz, re.search(r"(?m)^END\s*$", out) is not None, out[-500:])
            for i, e in enumerate(EPOCHS):
                days, secs = expect(e, tz)
                row("[%s] MVDATE(%d) = %d" % (tz, e, days), tag(out, "D%d" % i) == str(days), repr(tag(out, "D%d" % i)))
                row("[%s] MVTIME(%d) = %d" % (tz, e, secs), tag(out, "T%d" % i) == str(secs), repr(tag(out, "T%d" % i)))
                row("[%s] MVDATE.TIME(%d) = %d_%d" % (tz, e, days, secs), tag(out, "DT%d" % i) == "%d_%d" % (days, secs),
                    repr(tag(out, "DT%d" % i)))
                row("[%s] MVEPOCH(date, time) gives %d back" % (tz, e), tag(out, "R%d" % i) == str(e), repr(tag(out, "R%d" % i)))
                row("[%s] MVEPOCH(date_time) gives %d back" % (tz, e), tag(out, "S%d" % i) == str(e), repr(tag(out, "S%d" % i)))
            now = tag(out, "NOW")
            row("[%s] EPOCH() is the clock, whatever the zone" % tz, now is not None and now.isdigit() and abs(int(now) - time.time()) < 300,
                repr(now))
            row("[%s] EPOCH() is SYSTEM(1035)" % tz, tag(out, "SYS") in ("0", "1", "-1"), repr(tag(out, "SYS")))
            row("[%s] MVEPOCH of a null string is the null string" % tz, tag(out, "NULL1") == "", repr(tag(out, "NULL1")))
            row("[%s] MVEPOCH of text is the null string" % tz, tag(out, "NULL2") == "", repr(tag(out, "NULL2")))
            row("[%s] a time of 90000 seconds is refused" % tz, tag(out, "NULL3") == "", repr(tag(out, "NULL3")))
            row("[%s] an epoch beyond 32 bits gives the null string" % tz, tag(out, "NULL4") == "", repr(tag(out, "NULL4")))
            row("[%s] a time.string with no underscore is refused" % tz, tag(out, "NULL5") == "", repr(tag(out, "NULL5")))
            row("[%s] a fraction of a second is cut off" % tz, tag(out, "FRAC") == "1234567890", repr(tag(out, "FRAC")))
    finally:
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-epoch: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
