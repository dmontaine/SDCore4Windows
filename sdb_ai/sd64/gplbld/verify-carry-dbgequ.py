#!/usr/bin/env python3
#
# sandbox-dbgequ.py - $MODE DEBUG.EQUATES (openQM 4 QM4 gap 218).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-dbgequ.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  bcomp (emit.equate.table) writes the equate and $DEFINE tokens behind the symbol table of a debug
#               object compiled with the mode; op_debug.c key 7 returns them; gpl.bp/debug (equate.resolve) lets the
#               display, SET and WATCH commands take a token for what it stands for.
# END-HISTORY
#
# The debugger is driven as sandbox-dbgcoll.py drives it: a program compiled BASIC ... DEBUGGING with a DEBUG statement, the
# session's next lines being the debugger's commands, each reply matched to the command that produced it (the echo, spaces
# dropped).  THE INSTRUMENT.  The commands sent and the reply to each are printed.  The control rows are the debugger working at
# all (a variable shown by its own name), and the same program compiled WITHOUT the mode, where a token is not a variable.
# If the prompt never appears, or fewer replies than commands come back, the run stops with exit 2 and no verdict.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
PROG, PLAIN = "zzdeq" + RUN, "zzdep" + RUN
passed = failed = 0

BODY = """$define LIMIT 100
   dim m(3,2)
   dyn = 'a':@fm:'bb':@vm:'cc':@fm:'d'
   total = 7
   m(2,1) = 'mm'
   equate TOT to total
   equate ELEM to m(2,1)
   equate FLD to dyn<2>
   equate NAMEC to 'hello'
   equate NUMC to 42
   equate CR to char(9)
   debug
   total = 8
   crt 'after total=':total
end
"""


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
    say("sandbox-dbgequ: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d lines sent: %s ..." % (len(cmds), " | ".join(cmds[:3])))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def drive(box, prog, rows):
    """Compile prog for the debugger, run it, send each row's command, and check each reply.  rows are
    (label, command, regex the reply must match)."""
    cmds = [r[1] for r in rows]
    out = sess(box, "BASIC bp %s DEBUGGING" % prog, "RUN bp %s" % prog, *cmds, "R")
    clean = re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None
    row("setup: %s compiled with no errors, in debug mode" % prog, clean, out[-300:])
    if not clean:
        bail("the program did not compile")
    marks = [m.start() for m in re.finditer(r":RUN bp %s\s*$" % prog, out, re.M)]
    seg = out[marks[-1]:] if marks else ""
    parts = re.split(r"(?m)^>", seg)[1:]
    if not parts:
        bail("the debugger prompt never appeared - the program did not stop at DEBUG:\n" + out[-600:])
    replies = []
    for part in parts:
        lines = part.split("\n")
        replies.append((lines[0].replace(" ", ""), "\n".join(lines[1:]).replace("\x07", "").strip()))
    if len(replies) < len(cmds):
        bail("only %d replies came back for %d debugger commands:\n%s" % (len(replies), len(cmds), out[-800:]))
    for (label, cmd, want), (echo, reply) in zip(rows, replies):
        shown = reply if len(reply) < 160 else reply[:110] + " ... " + reply[-30:]
        say("    %-24s -> %s" % (cmd, shown))
        if echo != cmd.replace(" ", ""):
            row(label, False, "the reply was matched to %r, not to the command sent %r" % (echo, cmd))
            continue
        row(label, re.search(want, reply, re.M | re.S) is not None, "wanted /%s/, got %r" % (want, reply[:300]))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-dbgequ.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-dbgequ: sandbox %s" % box)
    say("sandbox-dbgequ: tree    %s" % os.path.dirname(HERE))
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-dbgequ: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    with open(os.path.join(sysd, "bp", PROG), "w") as f:
        f.write("$mode debug.equates\n" + BODY)
    with open(os.path.join(sysd, "bp", PLAIN), "w") as f:
        f.write(BODY)
    try:
        say("\n--- $MODE DEBUG.EQUATES ---------------------------------------------------------------------------------")
        out = drive(box, PROG, [
            ("CONTROL: a variable is shown by its own name", "/total", r"^Integer: 7$"),
            ("a token equated to a variable shows that variable", "/TOT", r"^Integer: 7$"),
            ("...whatever case it is typed in", "/tot", r"^Integer: 7$"),
            ("a token equated to a matrix element shows the element", "/ELEM", r'^String \(2 bytes\): "mm"$'),
            ("a token equated to a field of a dynamic array shows the field", "/FLD", r'^String \(5 bytes\): "bb.cc"$'),
            ("a token equated to a string is shown with its value", "/NAMEC", r"^NAMEC = hello$"),
            ("a token equated to a number is shown with its value", "/NUMC", r"^NUMC = 42$"),
            ("a $DEFINE token is shown with its value", "/LIMIT", r"^LIMIT = 100$"),
            ("a token equated to CHAR(n) is shown with its value", "/CR", r"^CR = CHAR\(9\)$"),
            ("SET through a token sets the variable", "SET TOT = 9", r"^$"),
            ("...and the variable has the value", "/total", r"^Integer: 9$"),
            ("...and so does the token", "/TOT", r"^Integer: 9$"),
            ("a token that stands for a number may be the value of a SET (QM4 Fixes 239)", "SET TOT = NUMC", r"^$"),
            ("...and the variable has the number", "/total", r"^Integer: 42$"),
            ("a $DEFINE token may be the value", "SET TOT = LIMIT", r"^$"),
            ("...and the variable has it", "/total", r"^Integer: 100$"),
            ("a token that stands for a string may be the value", "SET TOT = NAMEC", r"^$"),
            ("...and the variable has the string", "/total", r'^String \(5 bytes\): "hello"$'),
            ("a token that stands for CHAR(n) may be the value", "SET TOT = CR", r"^$"),
            ("...and the variable has one byte", "/total", r"^String \(1 bytes?\)"),
            ("a token that stands for a variable is not a value", "SET TOT = ELEM", r"^Illegal value$"),
            ("CONTROL: a plain number is still taken as it was", "SET TOT = 9", r"^$"),
            ("SET of a token of a constant is refused", "SET NUMC = 3", r"^Variable not defined$"),
            ("WATCH of a token of a constant is refused", "W NUMC", r"^Variable not defined$"),
            ("an unknown name is still not defined", "/NOSUCH", r"^Variable not defined$"),
            ("WATCH through a token is accepted", "W TOT", r"^$"),
            ("...and the program stops when the variable behind the token changes", "R", r"Watched variable TOT has changed"),
        ])
        row("the program ran on after the last command (R), with the value the program gave the variable", "after total=8" in out, out[-200:])

        say("\n--- the same program compiled without the mode ------------------------------------------------------------")
        drive(box, PLAIN, [
            ("CONTROL: a variable is shown by its own name", "/total", r"^Integer: 7$"),
            ("without the mode a token is not a variable", "/TOT", r"^Variable not defined$"),
            ("...and a $DEFINE token is not either", "/LIMIT", r"^Variable not defined$"),
        ])
    finally:
        say("\n--- cleanup ---------------------------------------------------------------")
        for n in (PROG, PLAIN):
            for p in (os.path.join(sysd, "bp", n), os.path.join(sysd, "bp.out", n)):
                if os.path.exists(p):
                    os.remove(p)
        left = [p for n in (PROG, PLAIN) for p in (os.path.join(sysd, "bp", n),) if os.path.exists(p)]
        row("cleanup: no fixture is left", not left, " ".join(left))

    say("\nsandbox-dbgequ: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
