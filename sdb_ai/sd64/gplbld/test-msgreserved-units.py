"""A message number reserved by the other port has not been re-allocated here.

WHY THIS EXISTS, AND IT IS A CLASS THE TREE COULD NOT SEE BEFORE.  The two SD
ports share one message-number space and neither can read the other's tree.  An
ALLOCATION on one side is invisible to the other - that much was always known,
and it is why the ports tell each other before taking a number.  A DELETION is
invisible in exactly the same way, and that is the half nobody had written
down: RELEASE_1.1 64 deleted sdsys/messages/10174 and 10175 with the
administrator-route refusals they carried, so 10174 now reads FREE in every
scan of this tree - while it is live on Linux, carrying apisrvr's remote-SDSYS
refusal, and has been all along.

  A number freed by a deletion is more dangerous than one never used,
  because both sides' scans report it available and both are right
  about their own tree.          -- SD Core for Linux agent, 19 Sep 2026

So a session here that allocates by `ls sdsys/messages | sort -n` would take
10174 back in good faith and the two ports would ship different text under one
id.  Nothing in either tree could report it.  The Linux agent asked for the
number to be recorded as spoken for on 19 Sep 2026; this file is that record,
and it is a check rather than a sentence because a sentence in a document is
what the allocator would not be reading.

WHAT IT DOES NOT CLAIM.  It asserts only that the ids listed below are absent
here.  It cannot see the Linux tree, so it can say nothing about numbers we
have taken and they have not heard of - that direction is still covered by
telling them, which is the mailbox rule in CLAUDE.md.  Reservations are added
here when the other port asks for one, in the same commit as the reply.

It is a data check: no SD, no install, no elevation, no cycle, and it never
writes to the tree - the mutants run on synthetic id lists so the live
directory is only ever read.

  python gplbld/test-msgreserved-units.py

Exit 0 all checks passed, 1 a check failed, 2 the messages directory is not
there to measure.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MESSAGES = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys", "messages"))

# ***THESE TABLES COME FROM THE OTHER PORT'S MAIL AND MUST NEVER BE DERIVED
# FROM THE LOCAL CLONE OF IT.***  Asked by the Linux agent on 20 Sep 2026, and
# it is the right question: there IS a clone of their tree beside this
# repository, nothing pulls it, and on that day it was 22 commits and one day
# behind.  A table built by reading it would have reported 10919-10922 FREE -
# which is exactly the failure these tables exist to prevent, arriving through
# the back door.  gplbld/scan-msgdiff.py reads that clone and is a REPORT for a
# person to judge; what a person concludes is typed in here by hand, from what
# the other port SAID.  Do not wire the two together.
#
# id -> (who holds it, when it was reserved, what it says there)
#
# 10174 was OURS until RELEASE_1.1 64 (commit e0c8d90, 18 Sep 2026) deleted it
# with the tiers.  Linux never deleted theirs and asked on 19 Sep 2026 to keep
# it rather than renumber a refusal they ship.
RESERVED = {
    "10174": ("SD Core for Linux", "19 Sep 2026",
              "apisrvr's refusal of a REMOTE session claiming SDSYS"),
    # ***THE 10176-10181 COLLISION IS SETTLED AND THIS BLOCK IS WHAT IT BECAME
    # - 20 Sep 2026, the two agents deciding it under the owner's delegation
    # ("decide between the two how to synchronize the two systems").***  THE
    # LINUX PORT MOVED; we keep 10176-10181, which are now simply ours and
    # appear in neither table.  Their six are at 10190-10195 (SDCore4Linux
    # 348a5f4) and must stay ABSENT here.
    #
    # WHY THEY MOVED AND NOT US, recorded because the reasoning is the useful
    # part: their cycle was owed anyway so their re-witness was FREE, while our
    # elevated half cannot run at all until RELEASE_1.1 76, itself parked
    # behind 78.  Our 27 real sites we could not re-prove beat their 44 they
    # could re-prove for nothing.  Not a count contest - a question of which
    # port could prove its own tree today.
    #
    # ***DECLARED ON THEIR REPORT, NOT ON OUR OWN READ, AND THAT IS STATED
    # RATHER THAN GLOSSED.***  The clone of their tree on this disk is not
    # pulled (the owner's checkout, his call), so it still shows the old
    # numbers.  What this table asserts is only what it can: that 10190-10195
    # have no record HERE.
    "10190": ("SD Core for Linux", "20 Sep 2026", "root is not SD's administrator"),
    "10191": ("SD Core for Linux", "20 Sep 2026", "SD administration needs a local session"),
    "10192": ("SD Core for Linux", "20 Sep 2026", "Account %1 is no longer suspended"),
    "10193": ("SD Core for Linux", "20 Sep 2026", "Account %1 is now suspended"),
    "10194": ("SD Core for Linux", "20 Sep 2026", "%1 is not suspended; nothing changed"),
    "10195": ("SD Core for Linux", "20 Sep 2026", "sdsys without an sdsys login"),
}

# ***A COLLISION IS AN ID LIVE IN BOTH TREES WITH DIFFERENT TEXT, WHICH IS A
# DIFFERENT FACT FROM A RESERVATION AND MUST NOT BE FILED AS ONE***: a reserved
# id is absent here and must stay absent, a collided id is present here and
# should not be.  The two assert OPPOSITE things, which is why the table below
# exists at all rather than being folded into RESERVED.
#
# ***IT IS EMPTY, AND IT IS EMPTY BECAUSE THE ONE COLLISION THIS PROJECT HAS
# EVER HAD WAS FOUND AND SETTLED IN ONE NIGHT - 20 Sep 2026, RELEASE_1.1 79.***
# The history is worth the paragraph because an empty table looks like a table
# nothing has ever used:
#
#   The guard was written to stop a FUTURE collision.  Its first real use found
#   one already on disk - 10177, live in both ports with different text.
#   Reporting it sent the Linux agent to look at the RANGE rather than the id,
#   and it was SIX: 10176-10181, two contiguous blocks allocated in the same
#   week, ours the case-insensitivity conversion and theirs their teardown's.
#   Neither port could see the other and neither did anything wrong.
#
#   The two agents settled it under the owner's delegation - "decide between
#   the two how to synchronize the two systems" - and the LINUX PORT MOVED, to
#   10190-10195 (SDCore4Linux 348a5f4), because their cycle was owed anyway so
#   their re-witness was free, while this tree's elevated half cannot run at
#   all until RELEASE_1.1 76.  Their six are in RESERVED above; ours are now
#   simply ours and appear in neither table.
#
# SO A ROW HERE IS FOR A COLLISION THAT CANNOT BE SETTLED AT ONCE.  Put the id
# here, with both texts and our wiring, and the check below will fail the
# moment our record stops existing - a stale declaration is a FAIL, not a quiet
# pass, the same demand test-acctkeywords-units.py makes of its own PENDING.
#
# id -> (what OUR record says, who wires it here, what THEIRS says)
COLLISION = {
}

# NOT CLAIMED BY EITHER PORT, recorded so a later session does not have to ask
# again: 10175 was deleted here by 64 and measured free on the Linux side too,
# so it is the one id both ports know to be free.  10913, 10914 and 10915 were
# deleted on the Linux side on 14 Sep when MODIFY.PASSWORD stopped driving
# passwd(1); they are not claimed and were never ours.
FREE_BOTH_SIDES = ("10175",)

# An id we expect to be PRESENT, so that "10174 is absent" is known to mean
# absent rather than "this script is looking at nothing".  Its neighbour.
CONTROL_PRESENT = "10173"

passed = 0
failed = 0


def check(label, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + label)
    else:
        failed += 1
        print("  [FAIL] " + label + ("  " + detail if detail else ""))


def reallocated(reserved, present):
    """Reserved ids that this tree has records for, sorted.  The whole
    decision, isolated so the mutants below can drive it on a list."""
    return sorted(i for i in reserved if i in present)


def stale_collisions(collision, present):
    """Declared collisions this tree no longer has a record for, sorted.  The
    opposite assertion to reallocated(), isolated for the same reason: so the
    mutant below can drive it on a list the live tree never sees."""
    return sorted(i for i in collision if i not in present)


def message_ids(directory):
    """Every numeric record id in a messages directory."""
    return set(e for e in os.listdir(directory)
               if e.isdigit() and os.path.isfile(os.path.join(directory, e)))


print("test-msgreserved-units: no id reserved by the other port has been")
print("  re-allocated in this tree.")
print("  messages " + MESSAGES)

if not os.path.isdir(MESSAGES):
    print("")
    print("test-msgreserved-units: " + MESSAGES + " is not there - nothing to")
    print("  measure.  This is the source tree's own sdsys/messages, so a")
    print("  missing one means the path above is wrong, not that the check")
    print("  passed.")
    sys.exit(2)

present = message_ids(MESSAGES)

# --- controls: the reader can see this tree at all -------------------------
check("CONTROL: the messages tree has a full set of records (150+)",
      len(present) >= 150,
      "found %d - is the path right?" % len(present))
check("CONTROL: a known-present id (%s) is seen" % CONTROL_PRESENT,
      CONTROL_PRESENT in present,
      "if this is absent, an absent 10174 proves nothing")

# --- the real question -----------------------------------------------------
bad = reallocated(RESERVED, present)
for i in sorted(RESERVED):
    who, when, what = RESERVED[i]
    print("  reserved %s by %s, %s - %s" % (i, who, when, what))
check("no reserved id has a record here (%d reserved, %d records)"
      % (len(RESERVED), len(present)),
      bad == [],
      "re-allocated: " + ", ".join(bad) + " - pick another number and tell the "
      "other port")

# --- the declared collisions, which must still BE collisions ---------------
#
# THE ASSERTION IS THE OTHER WAY ROUND FROM A RESERVATION, and that is the
# whole reason these are two tables.  A reserved id must be ABSENT here; a
# collided id must be PRESENT, because the declaration says so.  If ours has
# gone - renumbered, deleted, moved - the row is stale and this must go red
# rather than pass for the wrong reason.
for i in sorted(COLLISION):
    ours, wired, theirs = COLLISION[i]
    print("  COLLISION %s - LIVE IN BOTH TREES WITH DIFFERENT TEXT" % i)
    print("     here  : %s" % ours)
    print("     wired : %s" % wired)
    print("     Linux : %s" % theirs)
stale = stale_collisions(COLLISION, present)
check("every declared collision still has a record here (%d declared)"
      % len(COLLISION),
      stale == [],
      "no longer present: " + ", ".join(stale) + " - if it was renumbered, say "
      "so in COLLISION and tell the other port; a stale declaration is a FAIL, "
      "not a quiet pass")

# THE PARTITION.  An id cannot be both reserved and collided: the first says
# "absent here", the second says "present here", and a number in both tables
# would make one of the two checks above meaningless whichever way it went.
overlap = sorted(set(RESERVED) & set(COLLISION))
check("RESERVED and COLLISION do not name the same id",
      overlap == [], "in both tables: " + ", ".join(overlap))
check("nothing recorded as free on BOTH sides is claimed in either table",
      all(i not in RESERVED and i not in COLLISION for i in FREE_BOTH_SIDES),
      "FREE_BOTH_SIDES contradicts a claim above")
check("an id recorded as free on both sides really is free here (%s)"
      % ", ".join(FREE_BOTH_SIDES),
      all(i not in present for i in FREE_BOTH_SIDES),
      "one of them has acquired a record here - it is no longer free, and the "
      "other port is still being told that it is")

# --- mutants, on synthetic lists: the live tree is never written -----------
# ***THE MUTANT DRIVES A SYNTHETIC TABLE, NOT THE LIVE ONE, AND THE REASON IS
# THAT THE LIVE ONE WENT EMPTY.***  While COLLISION held six rows the obvious
# mutant - remove them from `present` and expect them reported - worked.  The
# night the collision was settled the table emptied, and that same mutant
# started comparing [] against [] and PASSING WITH NOTHING DRIVEN: the vacuous
# pass section 0 forbids, arriving by the table it guards being fixed.  A
# synthetic row cannot empty.
_synth = {"19998": ("ours", "wired here", "theirs")}
check("MUTANT: a declared collision whose record has gone is caught",
      stale_collisions(_synth, present) == ["19998"],
      "the staleness check would not notice our record disappearing")
check("CONTROL: a declared collision that IS present is not reported stale",
      stale_collisions(_synth, present | set(_synth)) == [],
      "the staleness check cries stale over a record that is there")
check("CONTROL: an empty collision table reports nothing stale",
      stale_collisions({}, set()) == [],
      "an empty table must not manufacture a finding")
check("MUTANT: a reserved id present in the tree is caught",
      reallocated(RESERVED, present | set(RESERVED)) == sorted(RESERVED),
      "the detector missed a planted re-allocation")
check("MUTANT: an unreserved id present in the tree is not reported",
      reallocated(RESERVED, present | set(["19999"])) == [],
      "the detector cried re-allocation over a number nobody reserved")
check("CONTROL: the detector answers nothing for an empty reservation table",
      reallocated({}, present) == [],
      "an empty table must not manufacture a finding")

print("")
print("test-msgreserved-units: %d passed, %d failed." % (passed, failed))
sys.exit(1 if failed else 0)
