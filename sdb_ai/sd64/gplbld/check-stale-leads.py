"""Find entries whose OPENING status claim is contradicted LATER IN THE SAME ENTRY.

THE FAULT THIS LOOKS FOR, seen three times on 26 Aug 2026:

  - section 4's ssh-options bullet opened "What is still unseen is the limitssh
    task..." and was corrected four paragraphs down.
  - section 7 step 3's limitssh bullet, same shape.
  - section 7 step 14 opened "WHAT IS STILL A DECISION, AND IT IS THE OWNER'S"
    and said "SHAPE (b) IS CHOSEN AND BUILT - OWNER, 23 Aug 2026" 48 lines
    later.

A reader - human or agent - reads top-down and stops at the first status
sentence.  When a correction is appended rather than the lead being struck, the
entry lies to everyone who does not read all of it.

WHAT IT IS NOT.  This does not decide staleness; it RANKS entries for reading.
An entry can legitimately narrate "this was open, then it closed".  The output
is a worklist, and every hit is read by hand.  Saying so matters because a
script that reported these as defects would be the same overconfidence it is
looking for.
"""

import io
import os
import re
import sys

DOC = os.path.join("C:" + os.sep, "Users", "dmont", "Projects", "sd4windows",
                   "PROJECT_STATUS.md")

# Wording that asserts something is NOT done.
OPEN_PAT = re.compile(
    r"\b(still (a )?(decision|open|unproven|unseen|not|needs|to do)"
    r"|is still the owner|remains open|NOT VERIFIED|never been (run|measured|seen)"
    r"|has never run|nothing has run it|not yet (approved|made|built|run)"
    r"|is the owner's (call|decision)|untested|unmeasured|unverified)\b",
    re.I)

# Wording that asserts it IS done.
CLOSE_PAT = re.compile(
    r"\b(CLOSED|DONE|BUILT AND VERIFIED|IS CHOSEN AND BUILT|chosen and built"
    r"|owner chose|VERIFIED ON A MACHINE|PROVEN ON A MACHINE|is closed"
    r"|struck|WITHDRAWN|SUPERSEDED|no longer|removed from this project)\b")

with io.open(DOC, encoding="utf-8", newline="") as fh:
    lines = fh.read().split("\n")

# Entry starts: section 7's numbered steps, and START HERE's "### N." items.
#
# SECTION 7 IS BOUNDED DELIBERATELY.  Matching "^N. **" across the whole file
# also catches section 6's numbered traps, and one of them - the Memory
# Integrity caution, "it is the owner's call, and an agent must not make it" -
# read as an open task and was swept into step 7's range by an entry boundary
# 1,087 lines wide.  A standing caution is not outstanding work.
sec7_a = sec7_b = None
for i, ln in enumerate(lines):
    if ln.startswith("## 7. Next steps"):
        sec7_a = i
    elif ln.startswith("## 8. Open questions"):
        sec7_b = i
if sec7_a is None or sec7_b is None or sec7_b <= sec7_a:
    print("REFUSING - could not bound section 7 (found %r..%r).  The headings")
    print("  may have been renamed; fix this rather than scanning everything.")
    sys.exit(2)
print("section 7 spans lines %d..%d" % (sec7_a + 1, sec7_b + 1))

starts = []
for i, ln in enumerate(lines):
    if re.match(r"^> ### \d+[a-z]?\. ", ln):
        starts.append(i)                       # START HERE items, anywhere
    elif sec7_a < i < sec7_b and re.match(r"^\d+\. \*\*", ln):
        starts.append(i)                       # numbered steps, section 7 only
starts = sorted(set(starts))
starts.append(len(lines))

print("entries found: %d" % (len(starts) - 1))
print("")

flagged = 0
for k in range(len(starts) - 1):
    a, b = starts[k], starts[k + 1]
    title = lines[a].strip()[:72]
    opens, closes = [], []
    for i in range(a, b):
        if OPEN_PAT.search(lines[i]):
            opens.append(i)
        if CLOSE_PAT.search(lines[i]):
            closes.append(i)
    if not opens or not closes:
        continue

    # THE DISCRIMINATOR IS WHICH KIND COMES FIRST, NOT WHETHER BOTH EXIST.
    # The first version compared opens[0] against closes[-1] independently, so
    # an entry FIXED by moving its closure to the head still flagged - the kept
    # reasoning below it contains open-words that precede the trailing closure.
    # It reported 14 before and 14 after four repairs.  AN INSTRUMENT THAT
    # CANNOT SHOW IMPROVEMENT CANNOT CONFIRM A FIX, which is this project's
    # own rule turned on the tool itself.
    #
    # What actually matters is what a reader hits FIRST.  An entry that opens
    # with a closure and then narrates the history is correct; one that opens
    # with "still a decision" and closes 338 lines later is the fault.
    first_status = min(opens[0], closes[0])
    leads_open = (first_status == opens[0]) and (opens[0] not in closes)
    if not leads_open:
        continue
    last_close = closes[-1]
    if last_close < opens[0]:
        continue
    gap = last_close - opens[0]
    flagged += 1
    print("  [%2d] line %-6d gap %-4d %s" % (flagged, a + 1, gap, title))
    print("       LEADS OPEN  line %d: %s"
          % (opens[0] + 1, lines[opens[0]].strip()[:88]))
    print("       but CLOSES  line %d: %s"
          % (last_close + 1, lines[last_close].strip()[:88]))
    print("")

print("=" * 70)
print("%d entr(ies) LEAD WITH AN OPEN CLAIM AND CLOSE LATER." % flagged)
print("This ranks for reading; it does not decide.  An entry may legitimately")
print("narrate 'this was open, then it closed' - but it must SAY SO FIRST.")
if flagged == 0:
    print("")
    print("ZERO IS SUSPICIOUS, NOT CLEAN.  Confirm the patterns still match")
    print("something by checking the entry count above is non-zero.")
