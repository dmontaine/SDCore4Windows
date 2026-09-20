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

# --- mutants, on synthetic lists: the live tree is never written -----------
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
