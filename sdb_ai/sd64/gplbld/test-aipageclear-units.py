#!/usr/bin/env python3
"""test-aipageclear-units.py - a tool page's body clear stops above the AI line (RELEASE_1.1 389, Linux S.305's defect).

S.305 moved the AI line up a row to put a rule under it.  Fourteen pages cleared their body with a height counted from the window,
chh = ctx<TK.C.H> - 5 (tool_query - 4), which since then covers the line, and $tk_frame writes the line only when it changed, so the
line vanished whenever such a page drew itself again (F5, a change of view, after a command).  Linux found it in its batch regression
(mail 2026-11-22T2220Z) and fixed each page with
    chh = (if ctx<TK.C.AIROW> then ctx<TK.C.BODYH> else ctx<TK.C.H> - 5)
This guard holds every gpl.bp/tool_* page to that: a line that sets chh from ctx<TK.C.H> alone is a FAIL.  Its own control: a copy of a
fixed page with the old line put back must fail (the mutant row), and the live files are not touched.  Linux's test-aipage-units AP17
holds the same; this is the Windows form, the same file in both Windows products.

Exit 0 every row passed, 1 a row failed, 2 nothing to read.

START-HISTORY:
22 Nov 26  Written for RELEASE_1.1 389.
END-HISTORY
"""
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GPLBP = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp"))
BAD = re.compile(r"^\s*chh\s*=\s*ctx<TK\.C\.H>\s*-\s*\d+\s*(;\*.*)?$")
GOOD = re.compile(r"^\s*chh\s*=\s*\(if ctx<TK\.C\.AIROW> then ctx<TK\.C\.BODYH> else ctx<TK\.C\.H> - \d+\)")
passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def scan(path):
    """(bad lines, good lines) of one page, each as 'line-number: text'."""
    bad, good = [], []
    with open(path, encoding="latin-1") as h:
        for n, line in enumerate(h, 1):
            line = line.rstrip("\r\n")
            if BAD.match(line):
                bad.append("%d: %s" % (n, line.strip()))
            elif GOOD.match(line):
                good.append("%d: %s" % (n, line.strip()))
    return bad, good


print("test-aipageclear-units: " + GPLBP)
pages = sorted(f for f in os.listdir(GPLBP) if f.startswith("tool_")) if os.path.isdir(GPLBP) else []
if not pages:
    print("test-aipageclear-units: CANNOT RUN - no gpl.bp/tool_* pages under " + GPLBP)
    sys.exit(2)
fixed = 0
for p in pages:
    bad, good = scan(os.path.join(GPLBP, p))
    fixed += len(good)
    row("%s: no body clear counted from the window alone" % p, not bad, "; ".join(bad))
# The null case: the fourteen fixed lines must be there to be held (a rename of the variable would otherwise pass every page).
row("the AI-aware clear is present on at least 14 pages (found %d)" % fixed, fixed >= 14)

# The mutant: a fixed page with the old line put back must be caught, read from a copy (the live file is not touched).
src = next((os.path.join(GPLBP, p) for p in pages if scan(os.path.join(GPLBP, p))[1]), None)
if src is None:
    row("mutant: a page to copy", False, "no fixed page found")
else:
    with open(src, encoding="latin-1") as h:
        text = h.read()
    mutant = re.sub(r"chh = \(if ctx<TK\.C\.AIROW> then ctx<TK\.C\.BODYH> else ctx<TK\.C\.H> - (\d+)\)", r"chh = ctx<TK.C.H> - \1", text, count=1)
    fd, tmp = tempfile.mkstemp(suffix="-" + os.path.basename(src))
    try:
        with os.fdopen(fd, "w", encoding="latin-1", newline="") as h:
            h.write(mutant)
        bad, _ = scan(tmp)
        row("mutant: %s with the old clear put back is caught" % os.path.basename(src), mutant != text and len(bad) == 1, "bad lines %d" % len(bad))
    finally:
        os.remove(tmp)

print("test-aipageclear-units: %d passed, %d failed" % (passed, failed))
sys.exit(0 if failed == 0 else 1)
