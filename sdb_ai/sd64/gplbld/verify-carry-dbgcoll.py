#!/usr/bin/env python3
#
# sandbox-dbgcoll.py - the debugger shows a data collection and the element a path names.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-dbgcoll.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built, which is how the same script is run against an OLD tree to
# prove it can fail.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for openQM sheet item 530 ("diving into a collection from the debugger caused a fatal
#               error").  SD had the opposite fault: the debugger program knew no variable type 19, so a collection
#               variable showed nothing.  It now shows the kind, the number of elements and the JSON text, and
#               /name{path} and DUMP name{path} show the element the path names (op_debug.c DEBUG.INFO code 6,
#               op_coll.c coll_debug_find, the debug program).
# END-HISTORY
#
# HOW IT DRIVES THE DEBUGGER.  A program compiled with BASIC ... DEBUGGING and holding a DEBUG statement stops at the
# debugger's ">" prompt; the session's next lines are the debugger commands, the last one R (run on).  It is not full
# screen, because the sandbox session has no terminal.  Each reply is the text after the ">" line that echoes its command
# (spaces are dropped in the echo, so the two are compared without them) up to the next prompt.
#
# THE INSTRUMENT.  The commands sent and the reply to each are printed.  The control rows are the debugger working at
# all: a string and an integer.  If the prompt never appears, or fewer replies than commands come back, the run stops
# with exit 2 and no verdict - a run that never reached the debugger would otherwise pass over nothing.

import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
PROG = "zzdbc" + "%05d" % (os.getpid() % 100000)
passed = failed = 0

SOURCE = """   c = jparse('{"name":"Acme","n":5,"on":true,"off":false,"none":null,"sub":{"x":"deep"},"a":[1,2,{"k":"v"}],"e":[],"o":{}}')
   s = 'plain'
   i = 5
   big = collection()
   for j = 1 to 3000
      big{'k':j} = j
   next j
   cyc = collection()
   cyc{'me'} = cyc
   debug
   crt 'after the debugger'
end
"""

FULL = '{"a":[1,2,{"k":"v"}],"e":[],"n":5,"name":"Acme","none":null,"o":{},"off":false,"on":true,"sub":{"x":"deep"}}'


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
    say("sandbox-dbgcoll: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d lines sent: %s ..." % (len(cmds), " | ".join(cmds[:3])))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-dbgcoll.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    d1, d2, d3 = (os.path.join(box, "dbgdump%d.txt" % n) for n in (1, 2, 3))
    say("sandbox-dbgcoll: sandbox %s" % box)
    say("sandbox-dbgcoll: tree    %s" % os.path.dirname(HERE))
    say("sandbox-dbgcoll: program %s" % PROG)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-dbgcoll: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    with open(os.path.join(sysd, "bp", PROG), "w") as f:
        f.write(SOURCE)
    # (label, debugger command, regex the reply must match, regex it must not match or None)
    rows = [
        ("CONTROL: a string variable is shown", "/s", r'^String \(5 bytes\): "plain"$', None),
        ("CONTROL: an integer variable is shown", "/i", r"^Integer: 5$", None),
        ("/* shows every variable of the program, the name first and then what /name shows: the string",
         "/*", r'(?im)^s  String \(5 bytes\): "plain"$', None),
        ("...the integer", "/*", r"(?im)^i  Integer: 5$", None),
        ("...a collection, with its element count", "/*", r"(?im)^c  Collection \(9 elements\)", None),
        ("...and the loop variable, which has its own value", "/*", r"(?im)^j  Integer: 3000$", None),
        ("a collection shows its kind, its element count and its JSON text, names in order",
         "/c", r"^Collection \(9 elements\): " + re.escape(FULL) + "$", None),
        ("an element that is an array shows as an array", "/c{a}", r'^Array \(3 elements\): \[1,2,\{"k":"v"\}\]$', None),
        ("a path goes through an array and a collection: a/3/k", "/c{a/3/k}", r'^String \(1 bytes\): "v"$', None),
        ("an array element that is a number", "/c{a/1}", r"^Integer: 1$", None),
        ("a position past the end of the array is not found", "/c{a/4}", r"^Element not found in the collection$", None),
        ("an empty array", "/c{e}", r"^Array \(0 elements\): \[\]$", None),
        ("an empty collection", "/c{o}", r"^Collection \(0 elements\): \{\}$", None),
        ("a JSON true is said to be Boolean: true", "/c{on}", r"^Boolean: true$", None),
        ("a JSON false is Boolean: false", "/c{off}", r"^Boolean: false$", None),
        ("a JSON null is Null", "/c{none}", r"^Null$", None),
        ("names in quotes and slashes between them", "/c{'sub'/'x'}", r'^String \(4 bytes\): "deep"$', None),
        ("a comma between the names does as well", "/c{sub,x}", r'^String \(4 bytes\): "deep"$', None),
        ("the path is case sensitive: NAME is not name", "/c{NAME}", r"^Element not found in the collection$", None),
        ("...and the variable name is not: C{name} finds the variable c", "/C{name}", r'^String \(4 bytes\): "Acme"$', None),
        ("an empty path is not found", "/c{}", r"^Element not found in the collection$", None),
        ("a path on a variable that is not a collection is refused", "/s{x}", r"^Index not allowed with scalar variable$", None),
        ("an index on a collection is refused", "/c(1)", r"^Index not allowed with scalar variable$", None),
        ("a collection that contains itself says so and does not stop the debugger",
         "/cyc", r"^Collection \(1 element\): \(cannot be shown\)$", None),
        ("...and a path through it still finds its way", "/cyc{me/me/me}", r"^Collection \(1 element\): \(cannot be shown\)$", None),
        ("a large collection is cut off, with dots", "/big", r'^Collection \(3000 elements\): \{"k1":1,.*\.\.\.$', None),
        ("...and one of its elements is found", "/big{k1500}", r"^Integer: 1500$", None),
        ("DUMP of an element writes no reply of its own", "DUMP c{sub} " + d1, r"^$", None),
        ("DUMP of the whole collection", "DUMP c " + d2, r"^$", None),
        ("DUMP of a large one", "DUMP big " + d3, r"^$", None),
    ]
    cmds = [r[1] for r in rows]
    try:
        for p in (d1, d2, d3):
            if os.path.exists(p):
                os.remove(p)
        out = sess(box, "BASIC bp %s DEBUGGING" % PROG, "RUN bp %s" % PROG, *cmds, "R")
        clean = re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None
        row("setup: the program compiled with no errors, in debug mode", clean, out[-300:])
        if not clean:
            bail("the program did not compile")
        marks = [m.start() for m in re.finditer(r":RUN bp %s\s*$" % PROG, out, re.M)]
        seg = out[marks[-1]:] if marks else ""
        parts = re.split(r"(?m)^>", seg)[1:]
        if not parts:
            bail("the debugger prompt never appeared - the program did not stop at DEBUG:\n" + out[-600:])
        replies = []
        for part in parts:
            lines = part.split("\n")
            # an error reply starts with the bell (the debugger's beep), which is not part of the text
            replies.append((lines[0].replace(" ", ""), "\n".join(lines[1:]).replace("\x07", "").strip()))
        if len(replies) < len(cmds):
            bail("only %d replies came back for %d debugger commands:\n%s" % (len(replies), len(cmds), out[-800:]))
        say("\n--- the debugger, command by command ----------------------------------------")
        for (label, cmd, want, notwant), (echo, reply) in zip(rows, replies):
            shown = reply if len(reply) < 160 else reply[:110] + " ... " + reply[-30:]
            say("    %-34s -> %s" % (cmd if len(cmd) < 34 else cmd[:31] + "...", shown))
            if echo != cmd.replace(" ", ""):
                row(label, False, "the reply was matched to %r, not to the command sent %r" % (echo, cmd))
                continue
            ok = re.search(want, reply, re.M | re.S) is not None and not (notwant and re.search(notwant, reply, re.M | re.S))
            row(label, ok, "wanted /%s/, got %r" % (want, reply[:300]))
        say("\n--- the files DUMP wrote -----------------------------------------------------")

        def slurp(p):
            try:
                with open(p, "rb") as fh:
                    return fh.read().decode("latin-1")
            except OSError:
                return None

        t1, t2, t3 = slurp(d1), slurp(d2), slurp(d3)
        say("    %s: %r" % (os.path.basename(d1), t1 if t1 is None or len(t1) < 100 else t1[:80] + "..."))
        row("DUMP c{sub} wrote the JSON of the element", t1 is not None and t1.strip() == '{"x":"deep"}', repr(t1))
        row("DUMP c wrote the JSON of the whole collection", t2 is not None and t2.strip() == FULL, repr(t2 and t2[:200]))
        try:
            whole = json.loads(t3) if t3 else None   # names are kept sorted bytewise, so the order is not assumed
        except ValueError:
            whole = None
        row("DUMP of the large collection wrote ALL of it as JSON (3000 elements, the last one there), not the cut-off text",
            isinstance(whole, dict) and len(whole) == 3000 and whole.get("k3000") == 3000 and "..." not in t3,
            "%s bytes, parsed: %s" % (len(t3) if t3 else None, whole is not None))
        row("the program ran on after the last command (R)", "after the debugger" in out, out[-200:])
    finally:
        say("\n--- cleanup ---------------------------------------------------------------")
        for p in (d1, d2, d3, os.path.join(sysd, "bp", PROG), os.path.join(sysd, "bp.out", PROG)):
            if os.path.exists(p):
                os.remove(p)
        left = [p for p in (d1, d2, d3, os.path.join(sysd, "bp", PROG)) if os.path.exists(p)]
        row("cleanup: no fixture is left", not left, " ".join(left))

    say("\nsandbox-dbgcoll: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
