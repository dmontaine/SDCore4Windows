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

THE THREE PHASES, AND WHY THE THIRD IS DIFFERENT.

  1  an entry whose OPENING status is contradicted later in itself.
  2  the task table against the entries, both directions.  THIS ONE DECIDES -
     it is the only phase that sets a non-zero exit.
  3  an entry that records a person SEEING something and later denies anyone
     has.  Added 26 Aug 2026.

PHASE 3 EXISTS BECAUSE PHASES 1 AND 2 COMPARE STATUS WORDS AND THIS FAULT HAS
NONE.  Item 5 read "UNSEEN: nobody has looked at this page" sixty-nine lines
below its own record of the owner cycling and CHOOSING stand-alone, which can
only be done on that page.  Both sentences are factual, neither is a status
claim, and the entry scored clean while contradicting itself.  The owner caught
it by reading - the thing this file exists to make unnecessary.

AND THE LIMIT IS WORTH KNOWING BEFORE TRUSTING ANY OF IT: every phase compares
this file against ITSELF.  The same session found "guest X is still running"
and "X has never had OpenSSH", both false against VirtualBox and perfectly
consistent on the page.  A RIG IS STATE - read it off VBoxManage.  No checker
over a document can know what a machine is doing.
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

# 26 Aug 26 - THE START HERE BLOCK NEEDS BOUNDING FOR THE SAME REASON SECTION 7
# DOES, and it was never done.  A "> ### N." item's range ran to the NEXT such
# item, and the LAST one has none - so it ran to the first section 7 step,
# swallowing about seven thousand lines of unrelated file.  Item 5 was reported
# holding 110 observation lines and a denial 5,800 lines outside itself.
#
# PHASE 1 SURVIVED THIS BY LUCK, WHICH IS WHY IT WENT UNSEEN.  It only asks
# which status word comes FIRST, so a range far too wide rarely changes its
# answer.  Phase 3 compares an observation against a later denial and a wide
# range is exactly what breaks it.  Found on phase 3's first run, 26 Aug 2026.
sh_a = sh_b = None
for i, ln in enumerate(lines):
    if ln.startswith("## NEXT SESSION: START HERE"):
        sh_a = i
    elif sh_a is not None and sh_b is None and i > sh_a and ln.startswith("## "):
        sh_b = i
if sh_a is None or sh_b is None:
    print("REFUSING - could not bound the START HERE block (found %r..%r)."
          % (sh_a, sh_b))
    print("  Its heading may have been renamed; fix this rather than scanning")
    print("  to the end of the file, which is what this replaced.")
    sys.exit(2)
print("START HERE spans lines %d..%d" % (sh_a + 1, sh_b + 1))

starts = []
sec7_entry = set()
sh_entry = set()
for i, ln in enumerate(lines):
    if re.match(r"^> ### \d+[a-z]?\. ", ln):
        starts.append(i)                       # START HERE items, anywhere
        if sh_a < i < sh_b:
            sh_entry.add(i)
    elif sec7_a < i < sec7_b and re.match(r"^\d+\. \*\*", ln):
        starts.append(i)                       # numbered steps, section 7 only
        sec7_entry.add(i)
starts = sorted(set(starts))
starts.append(len(lines))


# EVERY HEADING IS A BOUNDARY, which is the general form of a fix that was
# made twice by hand and was still wrong the second time.  Hard-coding "section
# 7 ends at section 8" fixed section 7; adding "START HERE ends at the next ##"
# fixed most of START HERE and still let item 5 run 1,200 lines past itself,
# because the heading that actually ends it - DOCUMENTATION DECISIONS - is
# INSIDE the blockquote and reads "> ##", which neither rule matched.
#
# So the rule is now the obvious one: an entry ends at the next entry OR at the
# next heading of any kind, whichever comes first.  A third block, or a
# blockquoted heading nobody thought about, needs no new special case.
BOUNDARY = re.compile(r"^>? *#{2,} ")
bounds = [i for i, ln in enumerate(lines) if BOUNDARY.match(ln)]


def bound(a, nxt):
    """End of the entry beginning at line index `a`, clamped to its section.

    The last entry in any block has no next entry inside that block, so an
    unclamped range runs on into whatever follows and the entry inherits its
    words.  Section 7 was bitten over section 8's preamble on 26 Aug 2026;
    START HERE over 7,000 lines the same day; item 5 over 1,200 more after the
    first repair.  Three of the same fault is what made this general.
    """
    for i in bounds:
        if i > a:
            return min(nxt, i)
    return nxt

print("entries found: %d" % (len(starts) - 1))
print("")

flagged = 0
for k in range(len(starts) - 1):
    a = starts[k]
    b = bound(a, starts[k + 1])
    # The range is clamped to the entry's own section by bound() - see its
    # docstring for the two times an unclamped one cried wolf.  A checker that
    # cries wolf on whichever entry is last teaches the reader to skip its
    # output, which is the one thing this file cannot afford: PROJECT_STATUS
    # tells every session to run it before answering "what is left".
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
# PHASE 3 - AN ENTRY THAT RECORDS SOMETHING HAPPENING AND THEN DENIES IT
# ===========================================================================
#
# WHY THIS EXISTS.  Phases 1 and 2 compare STATUS words - open against closed.
# On 26 Aug 2026 item 5 was found saying, 69 lines below its own record of the
# owner cycling and CHOOSING stand-alone:
#
#     UNSEEN: nobody has looked at this page.
#
# Choosing stand-alone cannot be done anywhere but on that page.  Both
# sentences are FACTUAL - neither carries a status word - so phases 1 and 2
# scored the entry clean while it contradicted itself.  The owner caught it by
# reading, which is the thing this file exists to make unnecessary.
#
# THE SHAPE IT LOOKS FOR, and the direction matters.  An entry that records an
# OBSERVATION and then, LATER, denies anyone has made it.  A denial that comes
# FIRST and is answered later is the "was open, then closed" narration phase 1
# already ranks, so it is deliberately not flagged twice.
#
# WHAT IT CANNOT DO, said plainly because the same session found a second stale
# fact this would never catch: it compares the file against ITSELF.  "guest X
# is still running" and "X has never had OpenSSH" were both false against
# VirtualBox and perfectly consistent on the page.  A RIG IS STATE - read it
# off VBoxManage.  No checker over this file can know that.
#
# AND IT RANKS, IT DOES NOT DECIDE.  It cannot tell whether the observation and
# the denial are about the same subject - that is the reader's job - so it
# never touches the exit code.  A phase that failed a build on a guess would be
# the same overconfidence it is looking for.

# DENIALS ABOUT SEEING, AND NOTHING ELSE.  The first cut also matched "nothing
# has run it" and reported SEVEN entries on a clean file, every one of them
# legitimate - they say nothing has run some verifier, which is true, and no
# regex can tell that "it" is a different subject from the run recorded higher
# up.  A phase that cries wolf seven times is a phase that gets skipped, which
# is the failure mode phase 1's own clamp was repaired for.
#
# SEEING IS THE DISCRIMINATOR, AND IT IS NOT A TRICK TO FIT ONE CASE.  Anything
# that RUNS leaves a transcript, an exit code and a PASS count, so "has it run"
# is answered by evidence, and phases 1 and 2 already police that claim.  The
# only things here that CANNOT be settled that way are the ones a person has to
# look at: a wizard page, a dialog's wrapping, whether a checkbox appeared.
# That is where "nobody has looked" gets written, and where it goes stale in
# silence the moment somebody looks - because looking leaves no artefact.
#
# The fault, 26 Aug 2026: item 5 said "UNSEEN: nobody has looked at this page"
# 69 lines below its own record of the owner CHOOSING stand-alone, which can
# only be done on that page.
DENY_PAT = re.compile(
    r"(\bnobody has (?:ever )?(?:looked|seen|read|watched|opened)\b"
    r"|\bno one has (?:ever )?(?:looked|seen|read|watched|opened)\b"
    r"|\bnobody has yet (?:looked|seen|read|watched)\b"
    r"|\bnever been (?:seen|looked at|read|watched)\b"
    r"|\bhas never been (?:seen|looked at|read|watched)\b"
    r"|\bnever once (?:seen|looked)\b)", re.I)

# THE BANNER FORM, CASE-SENSITIVE AND WITH ITS COLON.  A bare case-insensitive
# \bUNSEEN\b was both false hits left on the repaired file - "the firewall
# defect sat unseen for eight days" and "Unseen for eight days because...",
# both PAST TENSE and both resolved.  Prose uses the word to narrate; this file
# uses "***UNSEEN:***" as a live marker, and only the marker is a denial.
#
# It is kept even though it is redundant against the real fault - that entry
# read "UNSEEN: nobody has looked at this page", which the first alternative
# above catches on its own - because the marker can be written without the
# sentence after it, and then nothing else would match.
DENY_BANNER = re.compile(r"UNSEEN:")

# EVIDENCE THAT A PERSON WAS AT THE SCREEN.  Paired with the denial above, so
# it is about people and not about runs: a bare timestamp proves a PROGRAM ran,
# which says nothing about whether anyone looked, and including it was what
# dragged in most of the seven false hits.  These are the phrases this file
# actually uses when a human drove something.
OBSERVE_PAT = re.compile(
    r"(\bthe owner (?:cycled|chose|drove|clicked|ticked|looked|watched|saw)\b"
    r"|\bdriven by a person\b|\ba person at the wizard\b"
    r"|\bread on screen\b|\bwas driven by\b"
    r"|\bhe (?:chose|cycled|clicked|ticked|looked|watched|saw)\b)", re.I)

print("")
print("=" * 70)
print("PHASE 3: entries that record something happening and then deny it")
print("")

# A DENIAL BEING QUOTED IS NOT A DENIAL BEING MADE, and on the first run this
# was three of the eight hits: an entry recording that it USED to say "UNSEEN",
# one cross-referencing item 5's "UNSEEN", and one quoting "the installer had
# never been run" immediately before answering "It had."  Struck text is the
# same case - the project marks withdrawn claims with ~~.
#
# So quoted and struck spans are blanked before matching.  This is deliberately
# done on the DENIAL side only: an observation inside quotes is still evidence
# the thing happened, and blanking it would lose true positives.
QUOTED = re.compile(r'"[^"]*"' r"|~~.*?~~" r"|“[^”]*”")

# AND A QUOTATION THAT WRAPS IS STILL A QUOTATION.  This file is hard-wrapped
# at about 78 columns, so a quoted sentence routinely opens on one line and
# closes on the next, leaving an ODD number of quote marks on each.  The pair
# rule above sees neither half.  It cost the one remaining false hit on the
# repaired file: the correction to item 5 quotes the wording it withdrew, and
# was reported as making the very claim it was retracting.
#
# An unbalanced quote means the rest of that line is inside it, so blank from
# the last mark to end of line.  Same treatment for a line that CLOSES a
# quotation opened earlier - blank from the start.  Cheap, and it errs toward
# ignoring a denial rather than inventing one, which is the safe direction for
# a phase that only ranks.
def _unwrap(text):
    if text.count('"') % 2:
        text = text[:text.rindex('"')]
    if text.count("”") and not text.count("“"):
        text = text[text.index("”") + 1:]
    return text


def deny_hit(text):
    clean = QUOTED.sub(" ", _unwrap(text))
    return DENY_PAT.search(clean) or DENY_BANNER.search(clean)


pairs = []
for k in range(len(starts) - 1):
    a = starts[k]
    b = bound(a, starts[k + 1])
    obs, den = [], []
    for i in range(a, b):
        if OBSERVE_PAT.search(lines[i]):
            obs.append(i)
        if deny_hit(lines[i]):
            den.append(i)
    if not obs or not den:
        continue
    # THE DENIAL MUST COME AFTER AN OBSERVATION.  Otherwise it is an entry that
    # opened "nobody has" and later recorded the run - ordinary narration, and
    # phase 1's business.
    last_den = den[-1]
    earlier = [o for o in obs if o < last_den]
    if not earlier:
        continue
    pairs.append((a, earlier[0], last_den, len(obs)))

for n, (a, o, d, nobs) in enumerate(pairs, 1):
    print("  [%2d] line %-6d %s" % (n, a + 1, lines[a].strip()[:66]))
    print("       RECORDS   line %d: %s" % (o + 1, lines[o].strip()[:84]))
    print("       yet DENIES line %d: %s" % (d + 1, lines[d].strip()[:84]))
    print("       (%d observation line(s) in this entry)" % nobs)
    print("")

print("%d entr(ies) RECORD AN OBSERVATION AND LATER DENY ONE." % len(pairs))
print("This ranks for reading; it does not decide, and it CANNOT tell whether")
print("the two sentences are about the same subject.  Read each pair.")
if len(pairs) == 0:
    print("")
    print("ZERO IS SUSPICIOUS, NOT CLEAN - confirm both patterns still match")
    print("something at all:")
    tot_o = sum(1 for ln in lines if OBSERVE_PAT.search(ln))
    tot_d = sum(1 for ln in lines if deny_hit(ln))
    print("  observation lines in the whole file: %d" % tot_o)
    print("  denial lines in the whole file:      %d" % tot_d)
    if tot_o == 0 or tot_d == 0:
        print("  ONE OF THE PATTERNS MATCHES NOTHING - this phase measured nothing.")

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
        entry_at["7." + m.group(1)] = (a, bound(a, starts[k + 1]))
        continue
    m = re.match(r"^> ### (\d+[a-z]?)\. ", lines[a])
    if m:
        entry_at["H." + m.group(1)] = (a, bound(a, starts[k + 1]))

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
