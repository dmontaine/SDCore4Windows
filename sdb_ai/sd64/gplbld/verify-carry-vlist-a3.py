#!/usr/bin/env python3
#
# sandbox-vlist-a3.py - 1.2-0 bundle A-3, sheet 579 and 580: the vertical report's $VLIST control record
#                       (name format, data format, FIT; dictionary then VOC) and the separator that tells a
#                       wrapped line from the next value of a multivalued item.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-vlist-a3.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 579 / 580.  DRAFT: not run (the design session could not start a sandbox).
# END-HISTORY
#
# THE INSTRUMENT IS WHAT LIST ... VERT PRINTED for one record.  The colon is found by its column, so the
# fill character of the name format does not matter.  Every row has a control: the same command with no
# $VLIST record, or a $VLIST record that must be ignored.
#
#   1  no $VLIST: name column is 12 wide; a multivalued item and a wrapped line (580)
#   2  $VLIST in the dictionary: name format 6.L, data format 20L (the 10T item no longer wraps)
#   3  a right justified item keeps its own format under the data format
#   4  name format FIT fits the longest display name
#   5  $VLIST in the VOC applies; a dictionary $VLIST wins over it
#   6  a $VLIST whose field 1 is not X is ignored

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
    say("sandbox-vlist-a3: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    if not quiet:
        for line in out.splitlines():
            if line.strip() and not line.startswith(":") and not line.startswith("exit "):
                say("      | " + line.rstrip()[:130])
    return out


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("ascii"))


def after(out, cmd):
    """The lines printed after the echo of cmd."""
    return out.split(cmd)[-1].splitlines()


def colon_col(lines, head):
    """Column of the first ' : ' on the first line that starts with head, else None."""
    for ln in lines:
        if ln.startswith(head):
            return ln.find(" : ")
    return None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-vlist-a3.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-vlist-a3: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-vlist-a3: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        # r1: F1 name, F2 two values (one, two), F3 text that wraps in 10T, F4 number 7
        prog("zzvlmk", "   open 'zzvl' to f else stop 'no file'\n"
                       "   write 'alpha':@fm:'one':@vm:'two':@fm:'aaaa bbbb cccc dddd':@fm:'7' to f, 'r1'\n"
                       "   crt 'MADE'\nend\n")
        dicts = [("name", "1", "10L", "S"), ("mv", "2", "10L", "M"), ("txt", "3", "10T", "S"),
                 ("longnamefield", "4", "5R", "S")]
        for i, (nm, loc, fm, sm) in enumerate(dicts):
            prog("zzvld%d" % i, "D\n%s\n\n%s\n%s\n%s\n" % (loc, nm, fm, sm))
        prog("zzvlA", "X\n6.L\n20L\n")        # name 6, data 20
        prog("zzvlF", "X\nFIT\n\n")           # FIT
        prog("zzvlV", "X\n8.L\n\n")           # name 8 (VOC)
        prog("zzvlN", "D\n6.L\n\n")           # not type X
        cmds = ["DELETE.FILE DICT zzvl", "DELETE.FILE zzvl", "CREATE.FILE zzvl", "BASIC bp zzvlmk", "RUN bp zzvlmk"]
        for i, (nm, *_r) in enumerate(dicts):
            cmds.append("COPY FROM BP TO DICT zzvl zzvld%d,%s" % (i, nm))
        out = sess(box, *cmds, quiet=True)
        row("setup: the record was written", "MADE" in out, "no MADE")
        row("setup: 4 dictionary items copied", len(re.findall(r"(?m)^1 record\(s\) copied\.", out)) == 4)

        say("\n--- leg 1: default format, and the separator (580) ----------------------------")
        cmd = "LIST zzvl VERT name mv txt ID.SUP"
        lines = after(sess(box, cmd), cmd)
        row("CONTROL: the name column is 12 wide (colon at column 12)", colon_col(lines, "name") == 12, "got %r" % colon_col(lines, "name"))
        row("first value of mv is on the mv line", any(re.match(r"mv\S*\s* : one\s*$", l) for l in lines), "no mv : one line")
        row("580 THE ROW: the second value of mv repeats the colon", any(re.match(r"\s+ : two\s*$", l) for l in lines),
            "no ' : two' continuation line")
        row("580 THE ROW: a wrapped line has no colon (blank separator)",
            any(re.match(r"\s+cccc dddd\s*$", l) for l in lines) and not any(": cccc" in l for l in lines),
            "wrapped line missing or carries a colon")
        row("CONTROL: the text wraps at 10 (aaaa bbbb on the first line)", any(re.search(r": aaaa bbbb\s*$", l) for l in lines))

        say("\n--- leg 2: $VLIST in the dictionary -----------------------------------------------")
        sess(box, "COPY FROM BP TO DICT zzvl zzvlA,$VLIST", quiet=True)
        lines = after(sess(box, cmd), cmd)
        row("THE ROW: name format 6.L puts the colon at column 6", colon_col(lines, "name") == 6, "got %r" % colon_col(lines, "name"))
        row("THE ROW: data format 20L stops txt wrapping", any(re.search(r": aaaa bbbb cccc dddd\s*$", l) for l in lines))
        row("a name longer than the width is cut, not wrapped (no text mark lines)",
            not any(re.match(r"\s+: ", l) and "name" in l for l in lines))

        say("\n--- leg 3: a right justified item keeps its own format ----------------------------")
        cmd3 = "LIST zzvl VERT longnamefield ID.SUP"
        lines = after(sess(box, cmd3), cmd3)
        row("the 5R item is still right justified under data format 20L (value after 4 pad spaces)",
            any(re.search(r":\s{5}7\s*$", l) for l in lines), "no ':     7' line")

        say("\n--- leg 4: FIT -----------------------------------------------------------------------")
        sess(box, "COPY FROM BP TO DICT zzvl zzvlF,$VLIST OVERWRITING", quiet=True)   # the 6.L record of leg 2 is still there
        cmd4 = "LIST zzvl VERT name longnamefield ID.SUP"
        lines = after(sess(box, cmd4), cmd4)
        row("THE ROW: the colon is at column 13, the length of longnamefield", colon_col(lines, "name") == 13,
            "got %r" % colon_col(lines, "name"))

        say("\n--- leg 5: VOC $VLIST, and the dictionary wins -------------------------------------")
        sess(box, "DELETE DICT zzvl $VLIST", "COPY FROM BP TO VOC zzvlV,$VLIST", quiet=True)
        lines = after(sess(box, cmd), cmd)
        row("THE ROW: with no dictionary record the VOC record gives 8", colon_col(lines, "name") == 8, "got %r" % colon_col(lines, "name"))
        sess(box, "COPY FROM BP TO DICT zzvl zzvlA,$VLIST", quiet=True)
        lines = after(sess(box, cmd), cmd)
        row("THE ROW: a dictionary record wins over the VOC record (6, not 8)", colon_col(lines, "name") == 6, "got %r" % colon_col(lines, "name"))

        say("\n--- leg 6: field 1 is not X -------------------------------------------------------")
        sess(box, "DELETE DICT zzvl $VLIST", "DELETE VOC $VLIST", "COPY FROM BP TO DICT zzvl zzvlN,$VLIST", quiet=True)
        lines = after(sess(box, cmd), cmd)
        row("a $VLIST that is not type X is ignored (12)", colon_col(lines, "name") == 12, "got %r" % colon_col(lines, "name"))
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE VOC $VLIST", "DELETE.FILE DICT zzvl", "DELETE.FILE zzvl", quiet=True)

    say("\nsandbox-vlist-a3: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
