#!/usr/bin/env python3
#
# sandbox-pickrn.py - $MODE PICK.READNEXT (openQM 4 release item, sheet 418).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-pickrn.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  bcomp (st.readnext) emits SETFLAGS 0x200 before READNEXT / composite READNEXT under the mode;
#               readnext() in op_dio4.c leaves the id variable alone when it takes the ELSE clause.
# END-HISTORY
#
# Each program prints a word on the path it names, with the value of the id variable after it; the mode-off program
# is the control: the same statements give the null string, as they always did.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
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
    say("sandbox-pickrn: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


BODY = """   id = 'KEEP'
   readnext id else crt 'A-INACTIVE-ELSE [':id:']'
   formlist 'x1':@fm:'x2' to 3
   id = 'KEEP'
   n = 0
   loop
      readnext id from 3 else exit
      n += 1
   repeat
   crt 'B-EXHAUSTED N=':n:' [':id:']'
   formlist 'y1' to 4
   id = 'KEEP'
   readnext id from 4 then crt 'D-THEN [':id:']' else crt 'D-ELSE [':id:']'
   crt 'END'
end
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-pickrn.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-pickrn: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-pickrn: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    pon, poff = "zzrn%son" % RUN, "zzrn%sof" % RUN
    with open(os.path.join(sysd, "bp", pon), "w") as fh:
        fh.write("$mode pick.readnext\n" + BODY)
    with open(os.path.join(sysd, "bp", poff), "w") as fh:
        fh.write(BODY)

    say("\n--- $MODE PICK.READNEXT -----------------------------------------------------------------------------------")
    out = sess(box, "BASIC bp %s" % pon, "BASIC bp %s" % poff, "RUN bp %s" % pon, "RUN bp %s" % poff)
    row("setup: both programs compiled with no errors",
        len(re.findall(r"Compiled 1 program\(s\) with no errors", out)) == 2, out[-500:])
    tail = out.split("RUN bp %s" % pon, 1)[-1]
    on_out, off_out = tail.split("RUN bp %s" % poff, 1) if ("RUN bp %s" % poff) in tail else (tail, "")
    row("the mode on: READNEXT with no active list takes ELSE and leaves the variable as it was",
        "A-INACTIVE-ELSE [KEEP]" in on_out, on_out[-500:])
    row("the mode on: a select list read to its end leaves the last id in the variable (two found, then ELSE)",
        "B-EXHAUSTED N=2 [x2]" in on_out, on_out[-500:])
    row("the mode on: an item is still delivered by the THEN clause", "D-THEN [y1]" in on_out, on_out[-500:])
    row("CONTROL, the mode off: the same statements leave the null string, as they always did",
        "A-INACTIVE-ELSE []" in off_out and "B-EXHAUSTED N=2 []" in off_out and "D-THEN [y1]" in off_out, off_out[-500:])

    say("")
    say("sandbox-pickrn: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
