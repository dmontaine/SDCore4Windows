#!/usr/bin/env python3
#
# sandbox-chained.py - OPTION CHAINED.SELECT (openQM 4 release items, sheet 79 and 314).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-chained.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  cproc, at the end of a command: under the option a GET.LIST, QSELECT, SEARCH, SELECT, SSELECT or
#               SELECTINDEX that left an active list chains to the first command in the data queue; one that made no
#               list clears the queue.
# END-HISTORY
#
# Every verdict is anchored on a word printed only on the path it names (CHAINED-RAN is printed by the program the
# queued command runs) and on @DATA.PENDING after the select.

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
    say("sandbox-chained: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def empty(out, tag):
    """The queue was empty after the select: @DATA.PENDING is the queued text, so it prints as nothing (or 0)."""
    return re.search(r"(?m)^%s pending=0?\s*$" % re.escape(tag), out) is not None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-chained.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-chained: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-chained: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    mark = "zzcm" + RUN
    progs = {
        mark: "   crt 'CHAINED-RAN'\nend\n",
        "zzcoff" + RUN: """   data 'RUN bp %(m)s'
   execute 'SELECT bp'
   crt 'OFF-AFTER pending=':@data.pending
   cleardata
end
""" % {"m": mark},
        "zzcon" + RUN: """   execute 'OPTION CHAINED.SELECT'
   data 'RUN bp %(m)s'
   execute 'SELECT bp'
   crt 'ON-AFTER pending=':@data.pending
end
""" % {"m": mark},
        "zzcnone" + RUN: """   execute 'OPTION CHAINED.SELECT'
   data 'RUN bp %(m)s'
   execute 'SELECT bp WITH @ID = "zz.no.such.record.zz"'
   crt 'NONE-AFTER pending=':@data.pending
end
""" % {"m": mark},
        "zzcssel" + RUN: """   execute 'OPTION CHAINED.SELECT'
   data 'RUN bp %(m)s'
   execute 'SSELECT bp'
   crt 'SSELECT-AFTER pending=':@data.pending
end
""" % {"m": mark},
    }
    for name, body in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(body)

    say("\n--- OPTION CHAINED.SELECT ------------------------------------------------------------------------------")
    names = list(progs)
    out = sess(box, *["BASIC bp %s" % n for n in names])
    row("setup: the programs compiled with no errors", len(re.findall(r"Compiled 1 program\(s\) with no errors", out)) == len(names), out[-600:])

    def run(prog):
        o = sess(box, "RUN bp %s" % prog)
        return o

    o = run("zzcoff" + RUN)
    row("CONTROL, option off: a SELECT that finds records does not run the queued command",
        "CHAINED-RAN" not in o and "OFF-AFTER pending=RUN bp" in o, o[-400:])
    o = run("zzcon" + RUN)
    row("option on: a SELECT that finds records runs the first queued command, and the queue is empty after it",
        "CHAINED-RAN" in o and empty(o, "ON-AFTER"), o[-400:])
    row("...and it ran before the program's next statement (CHAINED-RAN is printed ahead of ON-AFTER)",
        o.find("CHAINED-RAN") != -1 and o.find("CHAINED-RAN") < o.find("ON-AFTER"), o[-400:])
    o = run("zzcnone" + RUN)
    row("option on: a SELECT that finds nothing runs nothing and clears the data queue",
        "CHAINED-RAN" not in o and empty(o, "NONE-AFTER"), o[-400:])
    o = run("zzcssel" + RUN)
    row("option on: SSELECT chains as well", "CHAINED-RAN" in o and empty(o, "SSELECT-AFTER"), o[-400:])

    say("")
    say("sandbox-chained: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
