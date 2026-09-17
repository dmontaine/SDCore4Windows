#!/usr/bin/env python3
r"""test-kernelkeys-units.py - the kernel key numbers are ONE FACT IN TWO FILES.
Free: no install, no elevation, no run token, no SD.  RELEASE_1.1 55.

WHAT IT GUARDS.  A KERNEL() key has a number in C (gplsrc/keys.h, K_NAME) and
the same number in BASIC (sdsys/gpl.bp/int$keys.h, K$NAME), and the two are
kept in step BY HAND.  Nothing the compiler runs compares them: BCOMP resolves
K$WHATEVER to whatever number the equate says and op_kernel.c switches on
whatever number the C header says, so a pair that disagrees COMPILES CLEANLY
AND CALLS THE WRONG KEY.

That is the same shape as BCOMP's intrinsic list (test-intrinsics-units.py):
two tables, matched by hand, where the failure is silent and lands somewhere
else entirely.  It was written when RELEASE_1.1 55 added the 66th pair,
K_HANDOFF / K$HANDOFF - a key whose 0 means "no session was started", so a
misrouted one would look like a login that failed for no reason.

WHAT IT FOUND WHEN IT WAS FIRST RUN: nothing.  All 66 shared names already
agreed.  That is the answer a guard over a hand-kept list wants on day one,
and it is why the mutant below is the row that matters - a check that has
never been seen to fail is not yet a check.

THE PARTITION IS THE POINT, not the comparison.  Every name in either file is
one of: shared and equal, a declared ALIAS (one key, two spellings), or a
declared NON-KEY (a name in that file that is not a kernel key at all).  A
name that is none of those fails, so a new key cannot be added to one file
only, and a new NON-KEY cannot appear without somebody saying what it is.

Exit 0 every row passed, 1 a row failed, 2 the sources are not there or
cannot be parsed - never a vacuous pass.

SD_KEYS_C and SD_KEYS_BASIC override the two paths, which is how the mutant
control drives it against copies rather than the live tree.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KEYS_C = os.environ.get("SD_KEYS_C") or os.path.join(HERE, "..", "gplsrc", "keys.h")
KEYS_B = (os.environ.get("SD_KEYS_BASIC")
          or os.path.join(HERE, "..", "sdsys", "gpl.bp", "int$keys.h"))

# One key, two spellings: BASIC name -> C name.  K$IS.SDVBSRVR predates the
# 2024 VBSRVR -> APISRVR rebrand, which renamed the C side and left the BASIC
# equate alone.  Same number, and that is what this file checks.
ALIASES = {
    "IS_SDVBSRVR": "IS_SDAPISRVR",
}

# Names that match the equate pattern in int$keys.h and are NOT kernel keys.
# Each says what it really is, because the point of declaring them is that
# somebody had to look.
NOT_KEYS_BASIC = {
    "USERS_UID":   "field position inside K$USERS's result, not a key",
    "USERS_PID":   "field position inside K$USERS's result, not a key",
    "USERS_IP":    "field position inside K$USERS's result, not a key",
    "USERS_FLAGS": "field position inside K$USERS's result, not a key",
    "USERS_PUID":  "field position inside K$USERS's result, not a key",
    "USERS_UNAME": "field position inside K$USERS's result, not a key",
    "USERS_DEV":   "field position inside K$USERS's result, not a key",
    "USERS_LOGIN": "field position inside K$USERS's result, not a key",
    "LOGOUT":      "a phantom action code, a different key space",
    "EXIT_ABORT":  "an exit-status code, a different key space",
}

# Names in keys.h that deliberately have no BASIC equate.
NOT_KEYS_C = {}

checks = 0
fails = 0


def check(ok, text):
    global checks, fails
    checks += 1
    if ok:
        print("  [PASS] %s" % text)
    else:
        fails += 1
        print("  [FAIL] %s" % text)


def cannot(text):
    print("test-kernelkeys-units: CANNOT RUN - %s" % text)
    sys.exit(2)


def parse_c(path):
    out = {}
    with open(path, encoding="latin-1") as f:
        for line in f:
            m = re.match(r"\s*#define\s+K_([A-Z0-9_]+)\s+(\d+)\s*$", line)
            if m:
                out[m.group(1)] = int(m.group(2))
    return out


def parse_basic(path):
    out = {}
    with open(path, encoding="latin-1") as f:
        for line in f:
            m = re.match(r"\s*\$define\s+K\$([A-Z0-9_.]+)\s+(\d+)", line)
            if m:
                out[m.group(1).replace(".", "_")] = int(m.group(2))
    return out


def main():
    for p in (KEYS_C, KEYS_B):
        if not os.path.isfile(p):
            cannot("%s is not there" % os.path.normpath(p))

    c = parse_c(KEYS_C)
    b = parse_basic(KEYS_B)
    print("test-kernelkeys-units")
    print("  C     %s: %d K_ defines" % (os.path.normpath(KEYS_C), len(c)))
    print("  BASIC %s: %d K$ defines" % (os.path.normpath(KEYS_B), len(b)))

    # CONTROL, FIRST.  A regex that stopped matching would otherwise report a
    # perfectly consistent pair of empty tables.
    check(len(c) >= 50 and len(b) >= 50,
          "control: both files parsed as real key tables (%d and %d, want "
          ">= 50 each)" % (len(c), len(b)))
    if len(c) < 50 or len(b) < 50:
        cannot("the parse found almost nothing, so nothing below measures "
               "anything")

    # Map each BASIC name to the C name it should equal.
    paired = {}          # C name -> (basic name, c number, basic number)
    unclassified_b = []
    for name, num in sorted(b.items()):
        cname = ALIASES.get(name, name)
        if name in NOT_KEYS_BASIC:
            continue
        if cname in c:
            paired[cname] = (name, c[cname], num)
        else:
            unclassified_b.append(name)

    unclassified_c = sorted(set(c) - set(paired) - set(NOT_KEYS_C))

    check(not unclassified_b,
          "every BASIC K$ name is a key, an alias or a declared non-key "
          "(unclassified: %s)" % (", ".join(unclassified_b) or "none"))
    check(not unclassified_c,
          "every C K_ name has a BASIC equate or is declared C-only "
          "(unclassified: %s)" % (", ".join(unclassified_c) or "none"))

    # THE ROW THIS FILE EXISTS FOR.
    wrong = [(cn, bn, cv, bv) for cn, (bn, cv, bv) in sorted(paired.items())
             if cv != bv]
    check(not wrong,
          "all %d shared keys carry the SAME number in both files%s"
          % (len(paired),
             "" if not wrong else
             " - " + ", ".join("K_%s=%d but K$%s=%d" % (cn, cv, bn, bv)
                               for cn, bn, cv, bv in wrong)))

    # A number used twice in C is a switch where one arm is unreachable.
    bynum = {}
    for name, num in c.items():
        bynum.setdefault(num, []).append(name)
    dup = {n: sorted(v) for n, v in bynum.items() if len(v) > 1}
    check(not dup, "no number is defined twice in C (%s)" % (dup or "none"))

    # Same for BASIC, ignoring the declared non-keys, which legitimately reuse
    # small numbers in their own key spaces.
    bynum = {}
    for name, num in b.items():
        if name in NOT_KEYS_BASIC:
            continue
        bynum.setdefault(num, []).append(name)
    dup = {n: sorted(v) for n, v in bynum.items() if len(v) > 1}
    check(not dup, "no number is defined twice in BASIC (%s)" % (dup or "none"))

    print("")
    print("test-kernelkeys-units: %d checks, %d failed" % (checks, fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
