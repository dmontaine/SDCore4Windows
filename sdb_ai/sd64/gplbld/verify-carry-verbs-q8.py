#!/usr/bin/env python3
#
# sandbox-verbs-q8.py - QM4 gaps bundle Q-8 (commands): MOVE.LIST.  (LIST.PHANTOMS is in sandbox-listu-a5.py, where a phantom
# is already running.)  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-verbs-q8.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-8: MOVE.LIST.  EXECUTE.LIST added the same day.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT A PROGRAM FOUND IN THE NUMBERED LISTS AFTER THE COMMAND RAN: a probe makes list 0 with three ids,
# the verb moves it, and a second probe reads every numbered list to the end and prints the ids it found in each.  A list is
# judged by what comes out of it, so a list that was not moved, or was moved and not cleared, shows.  The select lists belong
# to the process, so each case is one session.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
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
    say("sandbox-verbs-q8: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("latin-1"))


def lists(out):
    """{list number: the ids} from the L<n>[...] lines the drain probe printed."""
    return {int(m.group(1)): m.group(2) for m in re.finditer(r"(?m)^L(\d+)\[(.*)\]\s*$", out)}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-verbs-q8.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-verbs-q8: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-verbs-q8: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    try:
        prog("zzq8mk", "   formlist 'a':@fm:'b':@fm:'c' to 0\nend\n")
        prog("zzq8mk2", "   formlist 'x':@fm:'y' to 7\n   formlist 'a':@fm:'b':@fm:'c' to 0\n   readnext first from 0 else null\nend\n")
        prog("zzq8dr", ("   for n = 0 to 10\n      ids = ''\n      loop\n         readnext id from n else exit\n         ids<-1> = id\n      repeat\n"
                        "      if ids # '' then crt 'L':n:'[':change(ids, @fm, ','):']'\n   next n\n   crt 'DRAINED'\nend\n"))
        prog("zzq8pr", "   crt 'P[':field(@sentence, ' ', 4):']'\nend\n")
        prog("zzq8pq", "   crt 'Q[':field(@sentence, ' ', 4):']'\nend\n")
        out = sess(box, "BASIC bp zzq8mk zzq8mk2 zzq8dr zzq8pr zzq8pq")
        row("setup: the five probes compiled", re.search(r"(?m)^Compiled 5 program\(s\) with no errors", out) is not None, out[-300:])

        say("\n--- MOVE.LIST ------------------------------------------------------------------------")
        out = sess(box, "RUN bp zzq8mk", "RUN bp zzq8dr")
        row("CONTROL: the probe makes list 0 with a, b, c and the drain finds it there", lists(out) == {0: "a,b,c"}, repr(lists(out)))
        out = sess(box, "RUN bp zzq8mk", "MOVE.LIST 0 TO 4", "RUN bp zzq8dr")
        row("THE ROW: MOVE.LIST 0 TO 4 puts a, b, c in list 4 and leaves list 0 empty", lists(out) == {4: "a,b,c"}, repr(lists(out)))
        out = sess(box, "RUN bp zzq8mk", "MOVE.LIST 0 TO 5 KEEP", "RUN bp zzq8dr")
        row("KEEP leaves the source: both list 0 and list 5 hold a, b, c", lists(out) == {0: "a,b,c", 5: "a,b,c"}, repr(lists(out)))
        out = sess(box, "RUN bp zzq8mk", "move.list 0 to 6", "RUN bp zzq8dr")
        row("lower case is the same (the command word, TO)", lists(out) == {6: "a,b,c"}, repr(lists(out)))
        out = sess(box, "RUN bp zzq8mk2", "MOVE.LIST 0 TO 3", "RUN bp zzq8dr")
        row("the items already read are not moved: list 0 had a read, so list 3 gets b, c; list 7 is untouched",
            lists(out) == {3: "b,c", 7: "x,y"}, repr(lists(out)))
        out = sess(box, "RUN bp zzq8mk2", "MOVE.LIST 0 TO 7", "RUN bp zzq8dr")
        row("a list that is moved onto one that is active replaces it", lists(out) == {7: "b,c"}, repr(lists(out)))
        out = sess(box, "RUN bp zzq8mk", "MOVE.LIST 0 TO 0", "RUN bp zzq8dr")
        row("a list moved to itself is left alone", lists(out) == {0: "a,b,c"}, repr(lists(out)))
        out = sess(box, "MOVE.LIST 8 TO 9", "RUN bp zzq8dr")
        row("an empty list moved gives an empty list", lists(out) == {}, repr(lists(out)))

        say("\n--- EXECUTE.LIST ---------------------------------------------------------------------------")

        def seen(out, tag):
            return re.findall(r"(?m)^%s\[([^\]]*)\]\s*$" % tag, out)

        def order(out):
            return [(m.group(1), m.group(2)) for m in re.finditer(r"(?m)^([PQ])\[([^\]]*)\]\s*$", out)]

        out = sess(box, "RUN bp zzq8mk", "EXECUTE.LIST RUN bp zzq8pr ()")
        row("EXECUTE.LIST runs the command for each id of the list, in order, with () replaced by the id", seen(out, "P") == ["a", "b", "c"], repr(out[-300:]))
        out = sess(box, "RUN bp zzq8mk", "EXECUTE.LIST RUN bp zzq8pr () ; RUN bp zzq8pq ()")
        row("two commands separated by a semicolon run, both, for each id in turn: a a, b b, c c",
            order(out) == [("P", "a"), ("Q", "a"), ("P", "b"), ("Q", "b"), ("P", "c"), ("Q", "c")], repr(order(out)))
        out = sess(box, "RUN bp zzq8mk", "EXECUTE.LIST RUN bp zzq8pr ()()")
        row("every () of a command is replaced", seen(out, "P") == ["aa", "bb", "cc"], repr(seen(out, "P")))
        out = sess(box, "RUN bp zzq8mk", "EXECUTE.LIST RUN bp zzq8pr ()", "RUN bp zzq8dr")
        row("the ids are all used up: list 0 is empty after it", lists(out) == {}, repr(lists(out)))
        out = sess(box, "EXECUTE.LIST RUN bp zzq8pr ()")
        row("with no active list nothing is run, and nothing is said", seen(out, "P") == [] and "needed" not in out, repr(out[-200:]))
        out = sess(box, "RUN bp zzq8mk", "EXECUTE.LIST")
        row("EXECUTE.LIST with no command is refused (A command is needed after EXECUTE.LIST)", "A command is needed after EXECUTE.LIST" in out, repr(out[-200:]))
        out = sess(box, "RUN bp zzq8mk", "EXECUTE.LIST ; ;")
        row("a line of only semicolons is no command either", "A command is needed after EXECUTE.LIST" in out, repr(out[-200:]))

        say("\n--- MOVE.LIST: what it refuses ----------------------------------------------------------")
        for cmd, want in [("MOVE.LIST 11 TO 0", "Select list number missing or invalid"), ("MOVE.LIST 0 TO 11", "Select list number missing or invalid"),
                          ("MOVE.LIST", "Select list number missing or invalid"), ("MOVE.LIST 0 TO", "Select list number missing or invalid"),
                          ("MOVE.LIST 0 INTO 4", "Unexpected token (INTO)"), ("MOVE.LIST 0 TO 4 STAY", "Unexpected token (STAY)"),
                          ("MOVE.LIST 0 TO 4 KEEP MORE", "Unexpected token (MORE)")]:
            out = sess(box, "RUN bp zzq8mk", cmd, "RUN bp zzq8dr")
            row("%s is refused with %r and moves nothing" % (cmd, want), want in out and lists(out) == {0: "a,b,c"}, repr(out[-200:]))
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-verbs-q8: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
