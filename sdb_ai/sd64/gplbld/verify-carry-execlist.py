#!/usr/bin/env python3
#
# sandbox-execlist.py - $MODE EXECUTE.CLEARLIST (openQM 4 release item, sheet 521).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-execlist.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 27 Oct 26 dm  S.87 batch 3: PASSLIST with no variable (a clause that did nothing) is refused now, so the PASSLIST row passes a list variable (FORMLISTV ... TO pl,
#               PASSLIST pl).  This suite goes with the mode itself in a later batch.
# 14 Oct 26 dm  New.  bcomp (st.execute.options) emits CLEARSELECT 0 before the EXECUTE opcode under the mode, unless a
#               PASSLIST clause (with or without a variable) was given.
# END-HISTORY
#
# The executed program prints SELECTINFO(0, 1) - whether list 0 is active inside the command - so each verdict is the
# state the executed command saw, and the mode-off program is the control.

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
    say("sandbox-execlist: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-execlist.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-execlist: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-execlist: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    probe = "zzxp" + RUN
    body = "   formlist 'x1':@fm:'x2' to 0\n   execute 'RUN bp %s'\n" % probe
    progs = {
        probe: "   crt 'ACTIVE=':selectinfo(0, 1)\nend\n",
        "zzxoff" + RUN: "   formlist 'x1':@fm:'x2' to 0\n   crt 'TAG=OFF'\n   execute 'RUN bp %s'\nend\n" % probe,
        "zzxon" + RUN: "$mode execute.clearlist\n   formlist 'x1':@fm:'x2' to 0\n   crt 'TAG=ON'\n   execute 'RUN bp %s'\nend\n" % probe,
        "zzxpass" + RUN: "$mode execute.clearlist\n   formlistv 'x1':@fm:'x2' to pl\n   crt 'TAG=PASS'\n   execute 'RUN bp %s' passlist pl\nend\n" % probe,
        "zzxcap" + RUN: ("$mode execute.clearlist\n   formlist 'x1':@fm:'x2' to 0\n   crt 'TAG=CAP'\n"
                         "   execute 'RUN bp %s' capturing out\n   crt 'CAPTURED ':trim(out)\nend\n" % probe),
    }
    for name, text in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(text)

    say("\n--- $MODE EXECUTE.CLEARLIST -----------------------------------------------------------------------------")
    names = list(progs)
    out = sess(box, *["BASIC bp %s" % n for n in names])
    row("setup: the programs compiled with no errors", len(re.findall(r"Compiled 1 program\(s\) with no errors", out)) == len(names), out[-600:])

    def seen(prog, tag):
        o = sess(box, "RUN bp %s" % prog)
        m = re.search(r"TAG=%s\s+ACTIVE=(\d)" % tag, o)
        return (m.group(1) if m else None), o

    v, o = seen("zzxoff" + RUN, "OFF")
    row("CONTROL, the mode off: the executed command is given the active list 0 (as it always was)", v == "1", o[-300:])
    v, o = seen("zzxon" + RUN, "ON")
    row("the mode on: the default select list is cleared before the command runs", v == "0", o[-300:])
    v, o = seen("zzxpass" + RUN, "PASS")
    row("the mode on with PASSLIST: the list is passed in", v == "1", o[-300:])
    o = sess(box, "RUN bp zzxcap" + RUN)
    row("the mode on with CAPTURING: cleared as well, and the output is captured (the program prints CAPTURED ACTIVE=0)",
        re.search(r"(?m)^CAPTURED ACTIVE=0\s*$", o) is not None, o[-300:])

    say("")
    say("sandbox-execlist: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
