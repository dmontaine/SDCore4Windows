#!/usr/bin/env python3
#
# sandbox-pgheading.py - OPTION PAGINATE.ON.HEADING (openQM 4 release item, sheet 154).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-pgheading.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  op_tio.c hf_paginate(): on the display unit a heading or footing enables pagination unless
#               RUN.NO.PAGE is set without PAGINATE.ON.HEADING, or RUN ... NO.PAGE was given (PU_HF_NO_PAGE,
#               K$PAGINATE 2 / 3 from cproc).
# END-HISTORY
#
# The terminal is made 10 lines high (TERM 80,10).  A program that sets a heading and writes 30 lines then either
# reaches its END marker (pagination stayed off) or stops at the end-of-page prompt, where the session's input ends
# and the marker never appears.  Each case is its own session so that a stopped one hides nothing.
# The no-option run is the control: a heading has always enabled pagination, and still does.

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
    say("sandbox-pgheading: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


HEAD = """   heading 'HDG'
   for i = 1 to 30
      crt 'LINE':i
   next i
   crt 'END-REACHED'
end
"""
NOHEAD = """   for i = 1 to 30
      crt 'LINE':i
   next i
   crt 'END-REACHED'
end
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-pgheading.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-pgheading: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-pgheading: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    ph, pn = "zzpg%sh" % RUN, "zzpg%sn" % RUN
    with open(os.path.join(sysd, "bp", ph), "w") as fh:
        fh.write(HEAD)
    with open(os.path.join(sysd, "bp", pn), "w") as fh:
        fh.write(NOHEAD)

    say("\n--- compile, and the option is listed ----------------------------------------------------------------------")
    out = sess(box, "BASIC bp %s" % ph, "BASIC bp %s" % pn, "OPTION PAGINATE.ON.HEADING", "OPTION")
    row("setup: both programs compiled with no errors",
        len(re.findall(r"Compiled 1 program\(s\) with no errors", out)) == 2, out[-500:])
    row("the option is accepted and listed by name", "PAGINATE.ON.HEADING" in out.split("OPTION PAGINATE.ON.HEADING", 1)[-1],
        out[-400:])

    say("\n--- the cases ---------------------------------------------------------------------------------------------")
    term = "TERM 80,10"
    o = sess(box, term, "RUN bp %s" % ph)
    # (a piped session answers each prompt by itself at the end of its input, so the run does reach its end: the verdict
    # is whether the page prompt appeared)
    row("CONTROL, no options: a heading enables pagination, the run stops at the page prompt",
        "LINE1" in o and "Press RETURN to continue" in o, o[-400:])
    o = sess(box, "OPTION RUN.NO.PAGE", term, "RUN bp %s" % ph)
    row("RUN.NO.PAGE alone: a heading does not enable pagination, the run reaches its end",
        "END-REACHED" in o, o[-400:])
    o = sess(box, "OPTION RUN.NO.PAGE", "OPTION PAGINATE.ON.HEADING", term, "RUN bp %s" % ph)
    row("RUN.NO.PAGE and PAGINATE.ON.HEADING: the heading enables pagination, the run stops",
        "LINE1" in o and "Press RETURN to continue" in o, o[-400:])
    o = sess(box, "OPTION RUN.NO.PAGE", "OPTION PAGINATE.ON.HEADING", term, "RUN bp %s NO.PAGE" % ph)
    row("both options and RUN ... NO.PAGE: pagination never occurs, the run reaches its end",
        "END-REACHED" in o, o[-400:])
    o = sess(box, "OPTION PAGINATE.ON.HEADING", term, "RUN bp %s NO.PAGE" % ph)
    row("PAGINATE.ON.HEADING without RUN.NO.PAGE, RUN ... NO.PAGE given: still no pagination",
        "END-REACHED" in o, o[-400:])
    o = sess(box, "OPTION RUN.NO.PAGE", "OPTION PAGINATE.ON.HEADING", term,
             "RUN bp %s NO.PAGE" % ph, "RUN bp %s" % ph)
    row("RUN ... NO.PAGE does not outlive its run: the next plain RUN paginates again",
        o.count("END-REACHED") == 2 and o.find("END-REACHED") != -1 and o.find("Press RETURN to continue") > o.find("END-REACHED"),
        o[-500:])
    o = sess(box, "OPTION RUN.NO.PAGE", "OPTION PAGINATE.ON.HEADING", term, "RUN bp %s" % pn)
    row("a program with no heading is not paginated under RUN.NO.PAGE, with the option on",
        "END-REACHED" in o, o[-400:])

    say("")
    say("sandbox-pgheading: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
