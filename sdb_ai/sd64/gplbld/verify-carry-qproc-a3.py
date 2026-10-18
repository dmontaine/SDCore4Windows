#!/usr/bin/env python3
#
# sandbox-qproc-a3.py - 1.2-0 bundle A-3 (openQM features after 2.6.6, the query processor): does each
#                       keyword and option do what the release note says, on a real file?  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-qproc-a3.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 10 Oct 26 dm  Written for 1.2-0 bundle A-3.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT LIST/SELECT PRINTED for a file of five records whose values are known.  Each leg
# has a CONTROL that shows the old behaviour (or the neighbouring keyword's), so a row cannot pass because
# the command printed nothing.
#
#   1  CSV 3 quotes every item (ref 26)
#   2  ABSENT.IGNORE (25)
#   3  SORTED.SAMPLE (438), with SAMPLE as its control
#   4  COL.HDR.SPACE (467)
#   5  FROM NONE (378)
#   6  BREAK.ON 'N' resets the page number (16), and 'L' with 'U' (40)
#   7  NO.PAGE on SELECT (379)
#   8  SEARCH FOR (190), SEARCH ALL (221)
#   9  REPORTING (416)
#  10  SELECT with a bare field name (39)
#  11  REFORMAT with @RECORD (546)

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
    say("sandbox-qproc-a3: CANNOT RUN - " + msg)
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


def ids_in(out):
    """Record ids (r1..r5) in the order printed."""
    return re.findall(r"(?m)^(r[1-9])\b", out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-qproc-a3.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-qproc-a3: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-qproc-a3: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        # r1..r5: F1 = name, F2 = number (50 40 30 20 10), F3 = group (a a b b b)
        data = [("r1", "alpha", "50", "a"), ("r2", "bravo", "40", "a"), ("r3", "charlie", "30", "b"),
                ("r4", "delta", "20", "b"), ("r5", "echo", "10", "b")]
        for rid, n, num, g in data:
            prog("zzq3" + rid, "%s\n%s\n%s\n" % (n, num, g))
        for i, nm in ((1, "name"), (2, "num"), (3, "grp")):
            prog("zzq3d%d" % i, "D\n%d\n\n%s\n10L\nS\n" % (i, nm))
        cmds = ["DELETE.FILE DICT zzq3", "DELETE.FILE zzq3", "CREATE.FILE zzq3"]
        for rid, *_ in data:
            cmds.append("COPY FROM BP TO zzq3 zzq3%s,%s" % (rid, rid))
        for i, nm in ((1, "name"), (2, "num"), (3, "grp")):
            cmds.append("COPY FROM BP TO DICT zzq3 zzq3d%d,%s" % (i, nm))
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: all 8 COPY commands each copied one record", copied == 8, "copied lines: %d" % copied)

        say("\n--- leg 1: CSV 3 (ref 26) -------------------------------------------------------")
        out = sess(box, "LIST zzq3 name num CSV 1 ID.SUP", "LIST zzq3 name num CSV 3 ID.SUP")
        parts = out.split("LIST zzq3 name num CSV 3")
        row("CONTROL: CSV 1 leaves a number unquoted", re.search(r'(?m)^alpha,50\s*$', parts[0]) is not None, "no alpha,50")
        row("THE ROW: CSV 3 quotes the name and the number", len(parts) > 1 and re.search(r'(?m)^"alpha","50"\s*$', parts[1]) is not None,
            "no \"alpha\",\"50\" line")

        say("\n--- leg 2: ABSENT.IGNORE (ref 25) ---------------------------------------------")
        out = sess(box, "LIST zzq3 name WITH name = 'zzz' ID.SUP", "LIST zzq3 'r1' 'nosuch' name",
                   "LIST zzq3 'r1' 'nosuch' name ABSENT.IGNORE")
        parts = re.split(r"(?m)^LIST zzq3 'r1' 'nosuch' name", out)
        row("CONTROL: without it the unfound id is reported", len(parts) > 1 and "'nosuch' not found" in parts[1], "no report")
        row("THE ROW: with ABSENT.IGNORE it is not", len(parts) > 2 and "not found" not in parts[2] and "alpha" in parts[2],
            "report still there, or the record missing")

        say("\n--- leg 3: SORTED.SAMPLE (ref 438) ---------------------------------------------")
        out = sess(box, "LIST zzq3 name BY num SAMPLE 2", "LIST zzq3 name BY num SORTED.SAMPLE 2")
        parts = re.split(r"(?m)^LIST zzq3 name BY num SORTED\.SAMPLE 2", out)
        a, b = ids_in(parts[0]), ids_in(parts[1]) if len(parts) > 1 else []
        row("CONTROL: SAMPLE 2 takes the first two records and then sorts them: r2 r1", a == ["r2", "r1"], "got %r" % a)
        row("THE ROW: SORTED.SAMPLE 2 sorts and then takes two: r5 r4", b == ["r5", "r4"], "got %r" % b)

        say("\n--- leg 4: COL.HDR.SPACE (ref 467) -----------------------------------------------")
        out = sess(box, "LIST zzq3 name ID.SUP", "LIST zzq3 name ID.SUP COL.HDR.SPACE")
        parts = re.split(r"(?m)^LIST zzq3 name ID\.SUP COL\.HDR\.SPACE", out)

        def gap(text):
            lines = text.splitlines()
            for i, ln in enumerate(lines):
                if ln.strip().upper().startswith("NAME.."):
                    return i, lines
            return None, lines
        i0, l0 = gap(parts[0])
        i1, l1 = gap(parts[1]) if len(parts) > 1 else (None, [])
        row("CONTROL: with no keyword the first data row follows the headings directly",
            i0 is not None and l0[i0 + 1].strip() == "alpha", "line after heading: %r" % (l0[i0 + 1] if i0 is not None else None))
        row("THE ROW: with COL.HDR.SPACE there is a blank line between them",
            i1 is not None and l1[i1 + 1].strip() == "" and l1[i1 + 2].strip() == "alpha",
            "lines after heading: %r" % (l1[i1 + 1:i1 + 3] if i1 is not None else None))

        say("\n--- leg 5: FROM NONE (ref 378) ------------------------------------------------")
        out = sess(box, "SELECT zzq3 WITH num > 25", "LIST zzq3 name ID.SUP FROM NONE")
        row("THE ROW: FROM NONE ignores the active list and lists all five",
            len(re.findall(r"(?m)^(alpha|bravo|charlie|delta|echo)\s*$", out)) == 5, "wrong count")
        out = sess(box, "SELECT zzq3 WITH num > 25", "LIST zzq3 name ID.SUP")
        row("CONTROL: without it the active list (three records) is used",
            len(re.findall(r"(?m)^(alpha|bravo|charlie)\s*$", out)) == 3 and "delta" not in out, "wrong records")

        say("\n--- leg 6: BREAK.ON 'N' (ref 16) --------------------------------------------------")
        # the new page asks "Action (Abort/Quit/Next/Suppress pagination)"; an empty line answers it
        out = sess(box, "LIST zzq3 BY grp BREAK.ON \"'P'\" grp name HEADING \"Page 'P'\"", "", "",
                   "LIST zzq3 BY grp BREAK.ON \"'N'\" grp name HEADING \"Page 'P'\"", "", "")
        parts = re.split(r"(?m)^:LIST zzq3 BY grp BREAK\.ON \"'N'\" grp name", out)
        pages0 = re.findall(r"(?m)(?:^|: )Page\s+(\d+)\s*$", parts[0])
        pages1 = re.findall(r"(?m)(?:^|: )Page\s+(\d+)\s*$", parts[1]) if len(parts) > 1 else []
        row("CONTROL: 'P' starts a new page and the numbers run on: 1 2", pages0 == ["1", "2"], "got %r" % pages0)
        row("THE ROW: 'N' starts a new page numbered 1 again: 1 1", pages1 == ["1", "1"], "got %r" % pages1)

        say("\n--- leg 7: NO.PAGE on SELECT (ref 379) ----------------------------------------")
        out = sess(box, "SELECT zzq3 WITH num > 25 NO.PAGE")
        row("SELECT accepts NO.PAGE", re.search(r"(?i)3 record\(s\) selected", out) is not None, "no 'selected' line")

        say("\n--- leg 8: SEARCH FOR (ref 190) and SEARCH ALL (ref 221) ---------------------------")
        out = sess(box, 'SEARCH zzq3 FOR "alp" "ech"', 'SEARCH zzq3 FOR "r3"', 'SEARCH zzq3 ALL FOR "r3"')
        sel = re.findall(r"(?m)^(\d+) record\(s\) selected to list 0", out)
        row("SEARCH FOR with two strings selects alpha and echo: 2 records", sel[:1] == ["2"], "selected lines: %r" % sel)
        row("CONTROL: 'r3' occurs only in a record id, so without ALL nothing matches: 0", sel[1:2] == ["0"], "selected lines: %r" % sel)
        row("THE ROW: with ALL the id is searched too: 1", sel[2:3] == ["1"], "selected lines: %r" % sel)

        say("\n--- leg 9: REPORTING on COUNT (ref 416) -------------------------------------------")
        prog("zzq3mk", "   open 'zzq3r' to f else stop 'no file'\n   for i = 1 to 2500\n      write 'x' to f, 'k':i\n   next i\nend\n")
        out = sess(box, "CREATE.FILE zzq3r", "BASIC bp zzq3mk", "RUN bp zzq3mk", "COUNT zzq3r", "COUNT zzq3r WITH @ID > 'a' REPORTING")
        row("setup: 2500 records were written", re.search(r"(?m)^2500 record\(s\) counted", out) is not None, "no 2500 line")
        parts = out.split("COUNT zzq3r WITH @ID > 'a' REPORTING")
        tail = parts[-1]
        ex = re.findall(r"(?m)^(\d+) record\(s\) examined", tail)
        row("THE ROW: REPORTING says 1000 and 2000 records examined", ex == ["1000", "2000"], "examined lines: %r" % ex)
        row("CONTROL: and the plain COUNT before it printed none", "examined" not in parts[0].split("COUNT zzq3r WITH")[0].split("COUNT zzq3r")[-1], "examined seen early")
        sess(box, "DELETE.FILE DICT zzq3r", "DELETE.FILE zzq3r", quiet=True)

        say("\n--- leg 10: SELECT with a bare field name is SAVING MULTIVALUED (ref 39) ------------")
        prog("zzq3ls", "   loop\n      readnext x else exit\n      crt 'L[':x:']'\n   repeat\nend\n")
        out = sess(box, "BASIC bp zzq3ls", "SELECT zzq3 WITH num > 25", "RUN bp zzq3ls", "SELECT zzq3 WITH num > 25 name", "RUN bp zzq3ls")
        parts = out.split("SELECT zzq3 WITH num > 25 name")
        ctl = re.findall(r"(?m)^L\[(.*)\]\s*$", parts[0])
        got = re.findall(r"(?m)^L\[(.*)\]\s*$", parts[-1])
        row("CONTROL: a plain SELECT leaves the record ids on the list: r1 r2 r3", ctl == ["r1", "r2", "r3"], "got %r" % ctl)
        row("THE ROW: SELECT ... name leaves the values of name: alpha bravo charlie", got == ["alpha", "bravo", "charlie"], "got %r" % got)

        say("\n--- leg 11: REFORMAT with @RECORD (ref 546) -------------------------------------------")
        out = sess(box, "CREATE.FILE zzq3o", "REFORMAT zzq3 name @RECORD TO zzq3o",
                   "COPY FROM zzq3o TO BP alpha", "DELETE.FILE DICT zzq3o", "DELETE.FILE zzq3o")
        cp = os.path.join(bp, "alpha")
        made.append("alpha")
        body = open(cp, "rb").read().decode("ascii", "replace").splitlines() if os.path.exists(cp) else None
        row("THE ROW: the first item is the new record's id (alpha); @RECORD supplies its fields: alpha 50 a",
            body == ["alpha", "50", "a"], "got %r" % (body,))
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zzq3", "DELETE.FILE zzq3", quiet=True)

    say("\nsandbox-qproc-a3: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
