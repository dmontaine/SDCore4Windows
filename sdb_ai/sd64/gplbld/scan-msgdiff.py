"""Compare the two ports' 10000-range message records, first line only.

WHY THIS EXISTS.  The two SD ports share one message-number space and neither
can see the other's tree, so a number allocated on both sides for different
things is invisible to both.  On 20 Sep 2026 that had already happened SIX
TIMES - 10176 to 10181, two contiguous blocks allocated in the same week - and
nothing in either project could report it.  The Linux agent proposed this scan
and both ports keep a copy.  RELEASE_1.1 79 is the entry.

***IT IS A REPORT, NOT A GUARD, AND THE DIFFERENCE IS DELIBERATE.***  Most
differences between the trees are CORRECT: the same message in platform
wording ("Linux user" against "Windows account"), or one side's copy
lengthened.  "Differs" is not "collides" - a collision is two different
MEANINGS on one number - and no scan can tell them apart.  So this prints and a
person judges.  The judgement, once made, is recorded in
test-msgreserved-units.py's COLLISION table, which IS a guard.

***AND IT IS NOT IN THE FREE TIER, FOR A REASON WORTH READING BEFORE ADDING
IT.***  It reads a CLONE of the Linux port that sits beside this repository,
and nothing pulls that clone.  A tier member reading a stale checkout would
answer confidently about a tree that moved on - which is the class of failure
this project's section 0 exists to stop.  ***SO IT PRINTS THE COMMIT IT
ACTUALLY READ, EVERY RUN, AND SAYS THAT THE ANSWER IS ABOUT THAT COMMIT.***
Five of the six collisions were found here directly; the sixth (10181) is
newer than the clone and came from the Linux agent's own report, which is
exactly the limit this paragraph describes, met on the first run.

  python gplbld/scan-msgdiff.py

Exit 0 the comparison ran, 2 one of the two trees is not on this disk.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WIN_REPO = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir, os.pardir))
LIN_REPO = os.path.normpath(os.path.join(WIN_REPO, os.pardir, "SDCore4Linux"))
WIN = os.path.join(WIN_REPO, "sdb_ai", "sd64", "sdsys", "messages")
LIN = os.path.join(LIN_REPO, "sdb_ai", "sd64", "sdsys", "messages")


def head1(path):
    """The first non-blank line of a message record, as text."""
    try:
        with open(path, "rb") as f:
            raw = f.read(400)
    except OSError:
        return "(unreadable)"
    for line in raw.decode("utf-8", "replace").splitlines():
        if line.strip():
            return line.strip()
    return "(empty)"


def ids(d):
    if not os.path.isdir(d):
        return set()
    return set(e for e in os.listdir(d)
               if e.isdigit() and os.path.isfile(os.path.join(d, e)))


def git_head(path):
    try:
        out = subprocess.run(["git", "-C", path, "log", "--oneline", "-1"],
                             capture_output=True, text=True, timeout=30)
        return out.stdout.strip() or "(no git answer)"
    except Exception as exc:
        return "(git failed: %s)" % exc


print("scan-msgdiff: first-line comparison of the 10000-range message records")
print("  windows : " + WIN)
print("            " + git_head(WIN_REPO))
print("  linux   : " + LIN)
print("            " + git_head(LIN_REPO))
print("")
print("  ***THE LINUX SIDE IS A CLONE AND NOTHING PULLS IT.***  Every answer")
print("  below is about the commit printed above, not about their tree as it")
print("  is now.  Pull it first, or say which commit you read.")
print("")

if not os.path.isdir(LIN):
    print("the Linux port is not on this disk at " + LIN + " - nothing to")
    print("compare.  That is not a clean result: it means this scan could not")
    print("run, NOT that the two trees agree.")
    sys.exit(2)

w, l = ids(WIN), ids(LIN)
if not w or not l:
    print("one of the two trees has no message records - nothing to compare.")
    sys.exit(2)

w10 = sorted((i for i in w if i.startswith("10")), key=int)
l10 = sorted((i for i in l if i.startswith("10")), key=int)
both = sorted(set(w10) & set(l10), key=int)
print("10000-range records: windows %d, linux %d, in both %d"
      % (len(w10), len(l10), len(both)))
print("  only here : " + ", ".join(sorted(set(w10) - set(l10), key=int)))
print("  only there: " + ", ".join(sorted(set(l10) - set(w10), key=int)))
print("")

diff = []
for i in both:
    a, b = head1(os.path.join(WIN, i)), head1(os.path.join(LIN, i))
    if a != b:
        diff.append((i, a, b))

print("%d of %d shared ids differ on their first line:" % (len(diff), len(both)))
for i, a, b in diff:
    print("")
    print("  " + i)
    print("    here : " + a[:110])
    print("    there: " + b[:110])

print("")
print("READ THESE BY HAND.  'Differs' is not 'collides' - most are the same")
print("message in platform wording.  A COLLISION is two different MEANINGS on")
print("one number; when you find one, declare it in COLLISION in")
print("gplbld/test-msgreserved-units.py, which is the part that then guards it.")
