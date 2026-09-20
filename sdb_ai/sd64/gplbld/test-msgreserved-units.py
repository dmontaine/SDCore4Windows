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

# id -> (who holds it, when it was reserved, what it says there)
#
# 10174 was OURS until RELEASE_1.1 64 (commit e0c8d90, 18 Sep 2026) deleted it
# with the tiers.  Linux never deleted theirs and asked on 19 Sep 2026 to keep
# it rather than renumber a refusal they ship.
RESERVED = {
    "10174": ("SD Core for Linux", "19 Sep 2026",
              "apisrvr's refusal of a REMOTE session claiming SDSYS"),
}

# ***AND THE THING THIS GUARD WAS BUILT TO PREVENT HAS ALREADY HAPPENED ONCE -
# FOUND 20 Sep 2026, THE NIGHT THE GUARD WAS WRITTEN.***  A COLLISION is an id
# that is LIVE IN BOTH TREES WITH DIFFERENT TEXT, which is a different fact
# from a reservation and must not be filed as one: a reserved id is absent here
# and must stay absent, a collided id is present here and should not be.
#
# 10177 is the first.  Linux held it, orphaned; their 19 Sep teardown deleted it
# as dead text; four hours later their owner's ruling gave it a caller and it
# was restored WITH ITS ORIGINAL BYTES.  Ours has been live for days on an
# entirely different subject.  Neither port could see the other, and neither did
# anything wrong.
#
# ***IT IS DECLARED, NOT FIXED, AND THE DECLARATION IS ASSERTED SO IT CANNOT GO
# STALE QUIETLY.***  Renumbering a shipped record is the owner's call, not this
# agent's, so the guard's job is to keep the collision visible and to fail the
# moment the declaration stops being true - if our record disappears or is
# renumbered, the row below is wrong and this test goes red asking for it to be
# updated.  A declaration nobody re-checks is how a PENDING becomes a place to
# hide; test-acctkeywords-units.py makes the same demand of its own.
#
# ***AND IT IS NOT ONE ID, IT IS SIX - 10176 THROUGH 10181, A WHOLE
# CONTIGUOUS BLOCK, CONFIRMED 20 Sep 2026 BY READING BOTH TREES.***  The Linux
# agent went looking at the range rather than the id after we reported 10177,
# and the two ports allocated two blocks of six in the same week: ours is the
# case-insensitivity conversion (RELEASE_1.1 5 / D2), theirs is their
# teardown's - root refused, sdsys local-only, the three suspension messages,
# and the sdsys-without-a-login refusal.  All six of ours are WIRED, and four
# of the six have verifiers, so none of them is cheap to move either.
#
# ***CHECKED HERE BEFORE IT WAS BELIEVED, WHICH IS THIS TREE'S RULE FOR A LINUX
# REPORT.***  gplbld/scan-msgdiff.py compares the two trees on this disk and
# found five of the six directly; the sixth (10181) is newer than the local
# Linux clone, so it rests on their report rather than on our own read, and
# that is said rather than glossed.
#
# id -> (what OUR record says, who wires it here, what THEIRS says)
COLLISION = {
    "10176": ("Record ids are case insensitive in every file, so CASE is not accepted",
              "sdsys/gpl.bp/configf and createf, witnessed by gplbld/verify-twins.ps1",
              "This is a root session, and root is not SD's administrator"),
    "10177": ("'%1' and '%2' differ only by case in %3 - CONFIGURE.FILE's twin refusal",
              "sdsys/gpl.bp/configf:385, witnessed by gplbld/verify-twins.ps1",
              "SD administration needs a local session - CPROC's refusal of a "
              "remote sdsys session (Linux S.35, 20 Sep 2026)"),
    "10178": ("WARNING: %1 file(s) hold %2 record id(s) that differ only by case",
              "sdsys/gpl.bp/upgrade_nocase, witnessed by gplbld/verify-nocaseupgrade.ps1",
              "Account %1 is no longer suspended"),
    "10179": ("Converted %1 of %2 file(s) to case insensitive ids",
              "sdsys/gpl.bp/upgrade_nocase, witnessed by gplbld/verify-nocaseupgrade.ps1",
              "Account %1 is now suspended"),
    "10180": ("Checking every file for record ids that differ only by case...",
              "sdsys/gpl.bp/upgrade_nocase",
              "%1 is not suspended; nothing changed"),
    # ***THE ONE ROW WE HAVE NOT SEEN OURSELVES.***  The Linux clone on this
    # disk is older than their tree and does not carry a 10181 at all, so this
    # row is THEIR report, not our measurement.  It is declared anyway because
    # leaving it out would make the block look like five.
    "10181": ("Rename or delete one id of each pair, then convert that file with "
              "CONFIGURE.FILE NO.CASE",
              "sdsys/gpl.bp/upgrade_nocase",
              "This session runs as sdsys but the machine was not logged in as "
              "sdsys - REPORTED by the Linux port, newer than our clone of it"),
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
check("MUTANT: a declared collision whose record has gone is caught",
      stale_collisions(COLLISION, present - set(COLLISION)) == sorted(COLLISION),
      "the staleness check would not notice our record disappearing")
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
