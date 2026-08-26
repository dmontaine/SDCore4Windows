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

# Defaults to the repository's own PROJECT_STATUS.md, resolved from THIS file's
# location rather than a hard-coded path, so a clone or a moved tree still
# works.  An explicit path may be passed instead - that is how the control test
# runs it against a deliberately corrupted copy, which is the only way anyone
# has seen this script FAIL rather than merely pass.
if len(sys.argv) > 1:
    DOC = sys.argv[1]
else:
    DOC = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       os.pardir, os.pardir, os.pardir, "PROJECT_STATUS.md")
    DOC = os.path.normpath(DOC)

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
sec7_entry = set()
for i, ln in enumerate(lines):
    if re.match(r"^> ### \d+[a-z]?\. ", ln):
        starts.append(i)                       # START HERE items, anywhere
    elif sec7_a < i < sec7_b and re.match(r"^\d+\. \*\*", ln):
        starts.append(i)                       # numbered steps, section 7 only
        sec7_entry.add(i)
starts = sorted(set(starts))
starts.append(len(lines))

print("entries found: %d" % (len(starts) - 1))
print("")

flagged = 0
for k in range(len(starts) - 1):
    a, b = starts[k], starts[k + 1]
    # 26 Aug 26 - CLAMP A SECTION 7 ENTRY TO SECTION 7.  The LAST step in the
    # section has no next entry inside it, so its range ran to the END OF THE
    # FILE and it inherited every status word in sections 8 and 9.  Diagnosed
    # the day step 18 was added - the checker reported it "leads with a
    # closure" over a match inside section 8's preamble - and the diagnosis was
    # written down without the code being changed, so it fired again on the
    # very next edit to that entry, this time over "The LEFT ARROW in a Windows
    # console is closed" 546 lines outside the section.
    #
    # A CHECKER THAT CRIES WOLF ON WHICHEVER ENTRY IS LAST TEACHES THE READER
    # TO SKIP ITS OUTPUT, which is the one thing this file cannot afford:
    # PROJECT_STATUS tells every session to run it before answering "what is
    # left".  Clamping is done here rather than by adding sec7_b to `starts`,
    # because a boundary in that list would also be walked as an entry.
    if a in sec7_entry:
        b = min(b, sec7_b)
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

# ===========================================================================
# PHASE 2 - THE TASK TABLE AGAINST THE ENTRIES, IN BOTH DIRECTIONS
# ===========================================================================
#
# The owner asked for a table at the top so nobody searches history to learn
# what is done.  A hand-kept table is ANOTHER place status is stated, which is
# exactly what rotted in phase 1 - so it is checked rather than trusted.
#
# THE DIRECTION THAT MATTERS MOST IS "TABLE SAYS OPEN, ENTRY SAYS CLOSED":
# that is work finished and never ticked off, which is what made step 14 read
# as an outstanding decision for two days.

print("")
print("=" * 70)
print("PHASE 2: the task table against the entries")
print("")

# Map an entry ID to its start line.  7.N is a section 7 step; H.N a START HERE
# item.  Built from the SAME `starts` list phase 1 used, so the two phases
# cannot disagree about where an entry begins.
entry_at = {}
for k in range(len(starts) - 1):
    a = starts[k]
    m = re.match(r"^(\d+)\. \*\*", lines[a])
    if m and sec7_a < a < sec7_b:
        # CLAMP TO SECTION 7'S END.  The LAST step has no next entry inside
        # section 7, so starts[k+1] is a START HERE item or end-of-file and its
        # range swallowed section 8's preamble - which says "Closed and
        # superseded material is in HISTORY", so the last step was reported as
        # leading with a closure it does not contain.  Found by step 18 being
        # added on 26 Aug 2026; step 17 had never tripped it because section
        # 8's first closure word happens to sit further from it.
        entry_at["7." + m.group(1)] = (a, min(starts[k + 1], sec7_b))
        continue
    m = re.match(r"^> ### (\d+[a-z]?)\. ", lines[a])
    if m:
        entry_at["H." + m.group(1)] = (a, starts[k + 1])

# Table rows: | <mark> | **<ID>** | ... |
TICK_MARK = "✅"
ROW = re.compile(r"^\|\s*([^|\s]*)\s*\|\s*\*\*([0-9]+\.[0-9a-z]+|H\.[0-9a-z]+"
                 r"|7\.[0-9]+)\*\*\s*\|")
rows = []
for i, ln in enumerate(lines):
    m = ROW.match(ln)
    if m and m.group(1) in ("✅", "⬜", "➖", "◐"):
        rows.append((i, m.group(1), m.group(2)))

print("  table rows found: %d   entries indexed: %d" % (len(rows), len(entry_at)))
if not rows:
    print("  REFUSING - no task table rows parsed.  Either the table is gone or")
    print("  its row format changed; fix this rather than reporting a clean run.")
    sys.exit(2)

problems = []
seen_ids = set()
for ln_i, mark, eid in rows:
    seen_ids.add(eid)

    # THE ROW'S OWN WORDS, NOT ONLY ITS MARK.  A ticked row that reads as open
    # is a stale lead paragraph one line long, and the checks below compare the
    # mark against the ENTRY and never against the row.
    #
    # ***AND IT IS A PARTIAL GUARD. SAID PLAINLY BECAUSE IT WAS ADDED IN
    # RESPONSE TO THREE ROWS IT DOES NOT CATCH.*** Closing item 4 on 25 Aug 2026
    # ticked 7.3, H.4 and H.4a and left them reading "one bullet open",
    # "sshNoServer with a bridged NIC" and "the seven steps need a person at
    # the wizard".  OPEN_PAT is tuned for entry prose - "still a decision",
    # "never been run" - and matches none of those, so all three had to be
    # rewritten by hand.
    #
    # It is kept because it costs nothing and does catch a row that says "still
    # open" or "not yet built".  ***DO NOT READ A CLEAN PHASE 2 AS PROOF THAT
    # EVERY TICKED ROW READS AS DONE.***  Broadening the pattern to catch prose
    # like "needs a person" would flag legitimate open and partly rows, and a
    # false positive here trains people to ignore the whole run.
    if mark == TICK_MARK:
        m = OPEN_PAT.search(lines[ln_i])
        if m:
            problems.append(
                "row %d: %s is ticked DONE but the ROW ITSELF still reads as "
                "open - %r" % (ln_i + 1, eid, m.group(0)))
    if eid not in entry_at:
        problems.append("row %d: ID %s has NO ENTRY in the file" % (ln_i + 1, eid))
        continue
    a, b = entry_at[eid]
    o = [i for i in range(a, b) if OPEN_PAT.search(lines[i])]
    c = [i for i in range(a, b) if CLOSE_PAT.search(lines[i])]
    if not o and not c:
        continue
    first_is_open = bool(o) and (not c or o[0] < c[0])
    if mark == "✅" and first_is_open:
        problems.append(
            "row %d: %s is ticked DONE but its entry leads with an open claim "
            "(line %d)" % (ln_i + 1, eid, o[0] + 1))
    if mark == "⬜" and c and not first_is_open:
        problems.append(
            "row %d: %s is marked OPEN but its entry leads with a closure "
            "(line %d) - FINISHED WORK NEVER TICKED OFF" % (ln_i + 1, eid, c[0] + 1))
    # PARTLY IS A CLAIM WITH TEETH, not a way to silence the two checks above.
    # It asserts the entry holds BOTH a closure and something still open, so an
    # entry with only one of them is drift: either it finished (tick it) or
    # nothing in it is done (mark it open).
    if mark == "◐":
        if not c:
            problems.append(
                "row %d: %s is marked PARTLY but its entry contains no closure "
                "at all - mark it open" % (ln_i + 1, eid))
        if not o:
            problems.append(
                "row %d: %s is marked PARTLY but its entry contains nothing "
                "still open - tick it off" % (ln_i + 1, eid))

for eid in sorted(entry_at):
    if eid not in seen_ids:
        problems.append("entry %s (line %d) has NO ROW in the task table"
                        % (eid, entry_at[eid][0] + 1))

if problems:
    print("")
    for p in problems:
        print("  DRIFT: " + p)
    print("")
    print("  %d disagreement(s) between the table and the entries." % len(problems))
    sys.exit(1)

print("  every row agrees with its entry, and every entry has a row.")
