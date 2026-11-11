#!/usr/bin/env python3
"""test-sqescape-units.py - no program of sdsys/gpl.bp writes a quote inside a string by doubling it.

WHY (S.214, 11 Nov 2026; found by the Windows agent, mail T0452).  SD BASIC has no '' escape: the tokeniser
(op_str3.c, op_rmvtkn) ends a string at its own delimiter, so  'The program''s screen'  is two strings side by
side.  Some statements refuse that (SCREEN TEXT: "Unrecognized statement", which stopped a Windows bootstrap);
others compile it and display the wrong text.  Two in Core were found by grep (debug:1785 and edit:413).
The fix is a string with the OTHER delimiter:  "The program's screen".

THE RULE.  Outside comments, a string that closes (', " or \\ delimiter) is never followed IMMEDIATELY by
' or ".  An empty string '' on its own is fine (it is followed by a space, an operator, a bracket or the line's end).

It reads files; no SD, no install, no sudo.  Controls: a planted doubled quote in either kind of string must be refused,
and the legal shapes (empty strings, a quote of the other kind inside, adjacent only through an operator) must pass.
Exit 0 all rows passed, 1 a row failed, 2 it could not run.

  python3 gplbld/test-sqescape-units.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys"))
GPLBP = os.path.join(SDSYS, "gpl.bp")
passed = failed = 0

COMMENT_LINE = re.compile(r"^\s*(\*|!|rem\b|rem$)", re.I)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def text(p):
    with open(p, "rb") as f:
        return f.read().replace(b"\r\n", b"\n").decode("latin-1")


def doubled(line):
    """Return the column (1-based) of the first string that closes and is followed at once by ' or ", else 0."""
    if COMMENT_LINE.match(line):
        return 0
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c in "'\"\\":
            j = line.find(c, i + 1)
            if j < 0:
                return 0          # unterminated on this line: not this check's business
            if j + 1 < n and line[j + 1] in "'\"":
                return j + 2
            i = j + 1
            continue
        if c == ";" and i + 1 < n and line[i + 1] == "*":
            return 0              # a ;* tail is a comment
        i += 1
    return 0


def scan(files):
    hits = []
    for p in files:
        for no, ln in enumerate(text(p).split("\n"), 1):
            col = doubled(ln)
            if col:
                hits.append("%s:%d:%d  %s" % (os.path.basename(p), no, col, ln.strip()[:100]))
    return hits


def main():
    if not os.path.isdir(GPLBP):
        print("test-sqescape-units: cannot run - %s is not a directory" % GPLBP)
        return 2
    files = sorted(os.path.join(GPLBP, f) for f in os.listdir(GPLBP)
                   if os.path.isfile(os.path.join(GPLBP, f)))
    # the null case: the scan must have read programs and lines
    nlines = sum(len(text(p).split("\n")) for p in files)
    row("read %d files, %d lines of gpl.bp" % (len(files), nlines), len(files) > 100 and nlines > 50000)

    # controls: the detector sees the fault and leaves the legal shapes alone
    bad = ["screen text 'The program''s screen' at 1,1",
           'x = "say ""hi"""',
           "a = 'a' ; b = ''''",
           "msg = 'distribution''s package manager.'"]
    good = ["x = ''",
            "x = '' : y = ''",
            "x = 'it' : y = \"it's\"",
            "x = 'say \"hi\"'",
            "x = 'a' : 'b'",
            "x = 'a' : '' : 'b'",
            "x = 'a' : y = 'b'",
            "* a comment with 'it''s' in it",
            "x = 1 ;* tail 'it''s'",
            "x = 'trailing' ;* 'a''b'"]
    for s in bad:
        row("control refused: " + s, doubled(s) > 0)
    for s in good:
        row("control accepted: " + s, doubled(s) == 0)

    hits = scan(files)
    row("no doubled quote in any string of gpl.bp (%d found)" % len(hits), not hits, "; ".join(hits[:6]))
    for h in hits[:40]:
        print("      " + h)

    print("test-sqescape-units: %d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
