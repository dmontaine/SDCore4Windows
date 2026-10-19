#!/usr/bin/env python3
#
# sandbox-openzero.py - $MODE OPEN.FAIL.ZERO.FVAR (openQM 4 release item, sheet 514).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-openzero.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built, which is how the same script is run against an OLD tree to
# prove it can fail.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  The compiler emits SETFLAGS 0x100 before OPEN and OPENPATH under the mode (bcomp, open.common);
#               open_file() takes P_OPEN_ZERO and leaves the integer 0 in the file variable of a failed open.
# END-HISTORY
#
# Every verdict is anchored on a word the program prints only on the path it names, and the run refuses a reply
# that is a compile or run-time error.

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
    say("sandbox-openzero: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


SHOW = """   if unassigned(f) then crt 'FV-%(tag)s UNASSIGNED' else crt 'FV-%(tag)s VALUE ':f
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-openzero.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-openzero: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-openzero: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    zon, zoff, zsub = ("zzoz%s%s" % (RUN, c) for c in "nof")
    nofile = "zznofile" + RUN
    progs = {
        # the mode on: OPEN and OPENPATH that fail, and one that works
        zon: """$mode open.fail.zero.fvar
   open '%(nf)s' to f else
%(a)s   end
   openpath '/nonexistent/%(nf)s' to g else
      if unassigned(g) then crt 'FV-PATH UNASSIGNED' else crt 'FV-PATH VALUE ':g
   end
   open 'bp' to h then
      read r from h, 'zznosuchrecord' else crt 'GOOD-OPEN-READS'
   end else
      crt 'GOOD-OPEN-FAILED'
   end
   open '%(nf)s' to k else
      crt 'ELSE-TAKEN'
   end
end
""" % {"nf": nofile, "a": "      if unassigned(f) then crt 'FV-OPEN UNASSIGNED' else crt 'FV-OPEN VALUE ':f\n"},
        # the mode off: the file variable is as it always was
        zoff: """   open '%(nf)s' to f else
      if unassigned(f) then crt 'FV-OPEN UNASSIGNED' else crt 'FV-OPEN VALUE ':f
   end
   openpath '/nonexistent/%(nf)s' to g else
      if unassigned(g) then crt 'FV-PATH UNASSIGNED' else crt 'FV-PATH VALUE ':g
   end
end
""" % {"nf": nofile},
    }
    for name, body in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(body)

    say("\n--- $MODE OPEN.FAIL.ZERO.FVAR ---------------------------------------------------------------------------")
    out = sess(box, "BASIC bp %s" % zon, "BASIC bp %s" % zoff, "RUN bp %s" % zon, "RUN bp %s" % zoff)
    row("setup: both programs compiled with no errors", len(re.findall(r"Compiled 1 program\(s\) with no errors", out)) == 2, out[-500:])
    on_out, off_out = out.split("RUN bp %s" % zon, 1)[-1].split("RUN bp %s" % zoff, 1) if "RUN bp %s" % zoff in out else (out, "")
    row("the mode on: a failed OPEN leaves the file variable 0", "FV-OPEN VALUE 0" in on_out and "FV-OPEN UNASSIGNED" not in on_out, on_out[-400:])
    row("the mode on: a failed OPENPATH leaves it 0 as well", "FV-PATH VALUE 0" in on_out, on_out[-400:])
    row("the mode on: the ELSE clause is still the one taken", "ELSE-TAKEN" in on_out, on_out[-400:])
    row("the mode on: an OPEN that works is a file the program can read (the success path is not touched)",
        "GOOD-OPEN-READS" in on_out and "GOOD-OPEN-FAILED" not in on_out, on_out[-400:])
    row("CONTROL, the mode off: a failed OPEN leaves the file variable unassigned, as it always did",
        "FV-OPEN UNASSIGNED" in off_out and "FV-OPEN VALUE" not in off_out, off_out[-400:])
    row("CONTROL, the mode off: and so does a failed OPENPATH", "FV-PATH UNASSIGNED" in off_out, off_out[-400:])

    say("")
    say("sandbox-openzero: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
