#!/usr/bin/env python3
#
# sandbox-vert-fmt.py - 1.2-0 bundle A-3, sheet 160: the FMT qualifier of VERTICALLY.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-vert-fmt.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for 1.2-0 bundle A-3, sheet 160.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT LIST PRINTED for one record (r1) of a file with three dictionary items:
#   head   display name "a.very.long.heading" (19), format 10L
#   n      display name "n", format 10L
#   num    display name "num", format 4R (right justified in the dictionary)
# Values: head = alpha, n = beta, num = 50.  Each leg has a CONTROL (plain VERTICALLY, and a tabular LIST) so a
# row cannot pass on an empty report.
#
#   1  CONTROL: plain VERTICALLY keeps the 12 character name column and truncates the heading
#   2  FMT "25L": the whole heading, padded to 25
#   3  FMT "FIT": a column exactly as wide as the longest heading (19), the short one padded to 19
#   4  FMT ,"12R": name column unchanged, data format applied to head and n, NOT to the 4R item
#   5  an item's own FMT keeps it (head FMT "6L")
#   6  FMT "FIT","12R" both parts; a lower case fit
#   7  FMT with nothing usable after it is refused with 7265; VERTICALLY alone followed by a field still works

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
    say("sandbox-vert-fmt: CANNOT RUN - " + msg)
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
    """The output of one command: the text between its echo and the next echoed LIST."""
    parts = re.split(r"(?m)^" + re.escape(cmd) + r"\s*(?:Page \d+)?\s*$", out)     # the heading line ends with the page number
    if len(parts) < 2:
        return ""
    return re.split(r"(?m)^LIST zzvf", parts[1])[0]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-vert-fmt.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-vert-fmt: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-vert-fmt: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        prog("zzvfr1", "alpha\nbeta\n50\n")
        prog("zzvfd1", "D\n1\n\na.very.long.heading\n10L\nS\n")
        prog("zzvfd2", "D\n2\n\nn\n10L\nS\n")
        prog("zzvfd3", "D\n3\n\nnum\n4R\nS\n")
        cmds = ["DELETE.FILE DICT zzvf", "DELETE.FILE zzvf", "CREATE.FILE zzvf",
                "COPY FROM BP TO zzvf zzvfr1,r1",
                "COPY FROM BP TO DICT zzvf zzvfd1,head", "COPY FROM BP TO DICT zzvf zzvfd2,n",
                "COPY FROM BP TO DICT zzvf zzvfd3,num"]
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: all 4 COPY commands each copied one record", copied == 4, "copied lines: %d" % copied)

        say("\n--- leg 1: the control ----------------------------------------------------------")
        c1 = "LIST zzvf head n num VERTICALLY"
        out = sess(box, c1)
        b = after(out, c1)
        row("CONTROL: the heading is cut to 12 and the value follows ' : '",
            re.search(r"(?m)^a\.very\.long\. : alpha\s*$", b) is not None, "no 'a.very.long. : alpha'")
        row("CONTROL: the short heading is padded to 12", re.search(r"(?m)^n\.{11} : beta\s*$", b) is not None, "no 'n' line")

        say("\n--- leg 2: FMT \"25L\" ------------------------------------------------------------")
        c2 = 'LIST zzvf head n num VERTICALLY FMT "25L"'
        out = sess(box, c2)
        b = after(out, c2)
        row("THE ROW: the whole heading, padded to 25", re.search(r"(?m)^a\.very\.long\.heading {6} : alpha\s*$", b) is not None,
            "no padded heading line")
        row("THE ROW: the short heading padded to 25", re.search(r"(?m)^n {24} : beta\s*$", b) is not None, "no 'n' line")

        say("\n--- leg 3: FMT \"FIT\" -------------------------------------------------------------")
        c3 = 'LIST zzvf head n num VERTICALLY FMT "FIT"'
        out = sess(box, c3)
        b = after(out, c3)
        row("THE ROW: FIT is the longest heading (19): no padding on it", re.search(r"(?m)^a\.very\.long\.heading : alpha\s*$", b) is not None,
            "no fitted line")
        row("THE ROW: and the short one is padded to 19", re.search(r"(?m)^n {18} : beta\s*$", b) is not None, "no 'n' line")
        c3b = 'LIST zzvf n ID.SUP VERTICALLY FMT "fit"'
        out = sess(box, c3b)
        row("THE ROW: fit in lower case, one short heading: width 1", re.search(r"(?m)^n : beta\s*$", after(out, c3b)) is not None,
            "no 'n : beta'")

        say("\n--- leg 4: FMT ,\"12R\" (data format only) -------------------------------------------")
        c4 = 'LIST zzvf head n num VERTICALLY FMT ,"12R"'
        out = sess(box, c4)
        b = after(out, c4)
        row("THE ROW: name column unchanged (12), head formatted 12R: 7 spaces before alpha",
            re.search(r"(?m)^a\.very\.long\. :  {7}alpha\s*$", b) is not None or re.search(r"(?m)^a\.very\.long\. : {8}alpha\s*$", b) is not None,
            "no right justified alpha")
        row("THE ROW: n formatted 12R too", re.search(r"(?m)^n\.{11} : {9}beta\s*$", b) is not None, "no right justified beta")
        row("THE ROW: the dictionary's 4R item is NOT given the data format (4 wide: two spaces, 50)",
            re.search(r"(?m)^num\.{9} : {3}50\s*$", b) is not None, "num line wrong")

        say("\n--- leg 5: an item's own FMT wins -------------------------------------------------")
        c5 = 'LIST zzvf head FMT "6L" n VERTICALLY FMT ,"12R"'
        out = sess(box, c5)
        b = after(out, c5)
        row("THE ROW: head keeps its own 6L, n takes 12R", re.search(r"(?m)^a\.very\.long\. : alpha\s*$", b) is not None
            and re.search(r"(?m)^n\.{11} : {9}beta\s*$", b) is not None, "lines wrong")

        say("\n--- leg 6: both parts ---------------------------------------------------------------")
        c6 = 'LIST zzvf head n VERTICALLY FMT "FIT","12R"'
        out = sess(box, c6)
        b = after(out, c6)
        row("THE ROW: fitted name (19) and right justified data (12)",
            re.search(r"(?m)^a\.very\.long\.heading : {9}alpha\s*$", b) is not None
            or re.search(r"(?m)^a\.very\.long\.heading :  {7}alpha\s*$", b) is not None, "no fitted + right line")

        say("\n--- leg 7: refusals and the keyword on its own ------------------------------------------")
        c7 = "LIST zzvf VERTICALLY FMT head"
        out = sess(box, c7)
        b = after(out, c7)
        row("THE ROW: FMT with no format string is refused with 7265",
            "Format specification not found where expected" in out and "alpha" not in out, "no refusal")
        c8 = "LIST zzvf VERTICALLY head"
        out = sess(box, c8)
        row("CONTROL: VERTICALLY followed by a field still lists it (the look-ahead gives the token back)",
            re.search(r"(?m)^a\.very\.long\. : alpha\s*$", after(out, c8)) is not None, "field lost")
        c9 = "LIST zzvf head n"
        out = sess(box, c9)
        row("CONTROL: a tabular LIST is untouched (no ' : ' column)", " : " not in after(out, c9) and "alpha" in after(out, c9),
            "tabular report changed")
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zzvf", "DELETE.FILE zzvf", quiet=True)

    say("\nsandbox-vert-fmt: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
