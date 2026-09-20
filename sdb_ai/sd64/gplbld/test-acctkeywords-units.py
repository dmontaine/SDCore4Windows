#!/usr/bin/env python3
"""Free guard: no harness script may hand CREATE.ACCOUNT or MODIFY.ACCOUNT a
keyword the product now REFUSES.  RELEASE_1.1 64 and 76.

WHY IT EXISTS, AND IT IS A DEFECT THAT ALREADY HAPPENED.  64 abolished the
tiers, and createa's keyword cases answer sysmsg 2018 - the unrecognised-token
message - for standard / programmer / administrator.  2018 STOPS THE WHOLE
COMMAND, so a verifier whose fixture line still carries one of those words
makes no account at all and fails at its first step.  Eleven call sites in ten
scripts were left carrying PROGRAMMER or ADMINISTRATOR for a day; none of them
is a tier test, they are ordinary verifiers that happened to name a level when
creating their throwaway account.  Nothing could report it: the wording lint
proves REGISTERED PHRASES are gone, never that a command still parses, and no
suite has run since 64 landed (it cannot - the elevated driver is owed its own
re-aim, RELEASE_1.1 76).  Each one would have cost a step of a ~20-minute
elevated run to discover.

***IT DERIVES THE REFUSED SET FROM `createa` RATHER THAN HOLDING A LIST.***
The arms are read out of sdsys/gpl.bp/createa: a "case upcase(token) = 'X'"
whose body reaches "stop sysmsg(2018" is a refused keyword.  So a keyword
retired tomorrow is covered the day it is retired, and a list in here could
not go stale against the product.  A control refuses the null case - if no
refused arm is found, the parse has gone blind and that is a FAIL, not an
empty pass.

WHAT IT CANNOT SEE, SAID OUT LOUD.  It reads one line at a time, so a command
assembled across several lines, or a keyword held in a variable, is invisible
to it.  It also says nothing about whether the ACCEPTED keywords are the right
ones for a given test - that is the reader's job, the same limit
test-sysmsg-units states about direction.

DECLARED EXCEPTIONS.  A script that tests the refusal must name the keyword,
so the two that do are declared by name and are ASSERTED to still contain one -
a declaration that has gone stale is a FAIL, not a silent skip.

Exit 0 all green, 1 on any red, 2 if it could not measure.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__)).replace(os.sep, "/")
SD64 = os.path.dirname(HERE)
CREATEA = SD64 + "/sdsys/gpl.bp/createa"

# THE MUTANT CONTROL RUNS ON A COPY, NEVER ON THE LIVE FILES.  Point it at a
# directory of copies with a bad line planted and the matching row must go RED:
#     python test-acctkeywords-units.py --gplbld C:/path/to/copies
# The refused keywords still come from the real createa, because the product
# is not what is being mutated.
for _i, _a in enumerate(sys.argv):
    if _a == "--gplbld" and _i + 1 < len(sys.argv):
        HERE = sys.argv[_i + 1].replace(os.sep, "/").rstrip("/")

# Scripts that must name a refused keyword because refusing it is their subject.
# Each is asserted to still carry one; a stale entry fails.
DECLARED = {
    "verify-routes.ps1":
        "step 2 drives the create-time 2018 refusal and reads it back",
}

# ***THE PARTITION'S SECOND HALF, AND IT IS NOT A WAY TO HIDE A RED ROW.***
# These do not carry a keyword by accident: their whole subject is the
# administrator ACCOUNT that 64 abolished, so deleting the word would leave a
# rig measuring something that cannot exist.  64 names each of them under
# "verifiers that retire or are rewritten" and RELEASE_1.1 76 tracks the work.
# They print as PEND, loudly, with the entry that owes them; a PEND that has
# stopped naming a refused keyword has been dealt with and its line here must
# go, which is a FAIL rather than a quiet pass.
#
# ***verify-privundetermined.ps1 LEFT THIS TABLE ON 20 Sep 2026, AND THE ROW
# ABOVE IS WHAT MADE IT LEAVE.***  Its Step 8 - the ADMINISTRATOR-tier
# composition - was retired and its body deleted, so the file stopped naming a
# refused keyword, and this guard went RED on the same run naming the stale
# declaration.  That is the half of the partition nobody writes tests for, and
# it worked on its first real use: the fix landed and the declaration would
# otherwise have sat here claiming work that was already done.
PENDING = {
    "verify-sshadmin.ps1":
        "the subject is an SD administrator account - RELEASE_1.1 64, 76",
    "verify-apiremote.ps1":
        "its admin leg creates one - RELEASE_1.1 64, 76",
}

passed = 0
failed = 0


def row(ok, text):
    global passed, failed
    if ok:
        passed += 1
        print("[PASS] " + text)
    else:
        failed += 1
        print("[FAIL] " + text)


def refused_keywords(path):
    """The tokens createa answers with sysmsg 2018.

    An arm runs from its "case upcase(token) = 'X'" line to the next "case"
    line; if any line of its body stops with 2018, X is refused.  Comment
    lines (BASIC's leading *) are skipped, so the paragraphs that EXPLAIN the
    refusal cannot be mistaken for it.
    """
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    out = []
    pending = None
    case_rx = re.compile(r"^\s*case\s+upcase\(token\)\s*=\s*'([^']+)'", re.I)
    stop_rx = re.compile(r"^\s*stop\s+sysmsg\(\s*2018\b", re.I)
    for line in lines:
        m = case_rx.match(line)
        if m:
            pending = m.group(1).upper()
            continue
        if pending is None:
            continue
        if re.match(r"^\s*case\b", line, re.I):
            pending = None                # a different arm began
            continue
        if line.strip().startswith("*"):
            continue                      # comment inside the arm
        if stop_rx.match(line):
            out.append(pending)
            pending = None
    return out


def command_lines(text):
    """(lineno, line) for lines that build an account command in a literal."""
    hits = []
    lit = re.compile(r"""['"]\s*(?:CREATE|MODIFY)\.ACCOUNT""", re.I)
    for i, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith("#"):
            continue
        if lit.search(line):
            hits.append((i, line))
    return hits


def main():
    print("gplbld          :", HERE)
    print("createa         :", CREATEA)

    if not os.path.isfile(CREATEA):
        print("REFUSED: no createa to read the refused keywords from")
        return 2

    refused = refused_keywords(CREATEA)
    print("refused keywords:", ", ".join(refused) if refused else "(none)")
    if not refused:
        print("REFUSED: createa named no 2018 keyword arm - the parse is blind, "
              "and an empty set would pass every file vacuously")
        return 2
    row(True, "createa names %d refused keyword(s): %s"
        % (len(refused), ", ".join(refused)))

    scripts = sorted(
        f for f in os.listdir(HERE)
        if f.lower().endswith(".ps1")
    )
    print("scripts scanned :", len(scripts))
    if not scripts:
        print("REFUSED: no .ps1 files beside this script")
        return 2

    # NOT PRECEDED BY "$": K$ADMINISTRATOR is the kernel key that GATES the
    # verb, not the keyword the verb refuses, and a line naming it is prose
    # about the gate.  Measured - verify-doors-admin.ps1:195 is exactly that.
    word = re.compile(r"(?<![$\w])(%s)\b"
                      % "|".join(re.escape(k) for k in refused), re.I)

    total_cmds = 0
    offenders = []
    declared_seen = {}
    for name in scripts:
        with open(os.path.join(HERE, name), "r",
                  encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for lineno, line in command_lines(text):
            total_cmds += 1
            m = word.search(line)
            if not m:
                continue
            if name in DECLARED or name in PENDING:
                declared_seen.setdefault(name, (lineno, m.group(1)))
                continue
            offenders.append((name, lineno, m.group(1), line.strip()))

    # CONTROL: a scan that found no account commands at all proves nothing.
    row(total_cmds > 0,
        "the scan found account-command lines to judge: %d" % total_cmds)

    for name, why in sorted(DECLARED.items()):
        if not os.path.isfile(os.path.join(HERE, name)):
            row(False, "declared exception %s is not there any more - "
                       "remove the declaration" % name)
            continue
        if name in declared_seen:
            lineno, kw = declared_seen[name]
            row(True, "declared: %s:%d still names %s (%s)"
                % (name, lineno, kw, why))
        else:
            row(False, "declared exception %s no longer names a refused "
                       "keyword - the declaration is stale (%s)" % (name, why))

    for name, why in sorted(PENDING.items()):
        if not os.path.isfile(os.path.join(HERE, name)):
            row(False, "pending rewrite %s is not there any more - remove the "
                       "line for it" % name)
            continue
        if name in declared_seen:
            lineno, kw = declared_seen[name]
            print("[PEND] %s:%d still names %s - owed 64's rewrite (%s)"
                  % (name, lineno, kw, why))
        else:
            row(False, "pending rewrite %s no longer names a refused keyword - "
                       "it has been dealt with, so remove its line here (%s)"
                % (name, why))

    if offenders:
        for name, lineno, kw, line in offenders:
            row(False, "%s:%d hands the account verb %s, which createa "
                       "refuses with 2018: %s" % (name, lineno, kw, line[:100]))
    else:
        row(True, "no undeclared script hands a refused keyword to "
                  "CREATE.ACCOUNT or MODIFY.ACCOUNT")

    print()
    print("PASSED - %d of %d" % (passed, passed + failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
