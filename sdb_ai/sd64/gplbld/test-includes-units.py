"""Every NAME$THING constant a gpl.bp program uses is defined by a header it includes.

WHY THIS EXISTS.  1 Oct 2026, the cycle STOPPED in the bootstrap on
    WARNING: K$ADMINISTRATOR is not assigned a value
in the new SET.BACKUP.DIRECTORY verb.  K$ADMINISTRATOR is defined in int$keys.h and the
verb included keys.h but not int$keys.h.  That is the ERRGEN trap (PROJECT_STATUS.md 6):
an undefined $define is NOT a compile error in SD BASIC - the compiler treats the name as a
variable, prints that warning, reports "0 error(s)" and would ship an object that fails at
RUN time with "Unassigned variable".  bootstrap.py refuses the build on the warning, which
is right, but it finds it only inside a cycle - an install's worth of time - and bbcmp, which
compiles the same source without complaint, does not warn at all.

So this finds it in a second, from the source: for each program, every constant of the form
UPPERCASE$something that the code (not a comment, not a string) uses must be defined - with
$define or #define - in a header the program includes, directly or through that header's own
includes, or in the program itself.  Both include forms are followed:
    $include int$keys.h              and           $include syscom keys.h

A source check: no SD, no install, no elevation.  The mutants run on synthetic text.
Identical in both Windows trees.

  python gplbld/test-includes-units.py

Exit 0 all checks passed, 1 a program uses a constant nothing defines, 2 the tree is not there.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(ROOT, "gpl.bp")
SYS = os.path.join(ROOT, "syscom")

INC = re.compile(r"^\s*\$include\s+(\S+)(?:[ \t]+(\S+))?", re.M | re.I)
DEF = re.compile(r"^\s*[$#]define\s+(\S+)", re.M | re.I)
EQU = re.compile(r"^\s*equate\s+(\S+)", re.M | re.I)
USED = re.compile(r"(?<![A-Za-z0-9_.$@!])([A-Z][A-Z0-9.]*\$[A-Za-z0-9.$]+)(?![A-Za-z0-9_])")

failures = 0
passes = 0


def check(label, ok, detail=""):
    global failures, passes
    if ok:
        passes += 1
        print("  [PASS] " + label)
    else:
        failures += 1
        print("  [FAIL] " + label + ("  " + detail if detail else ""))


def read(p):
    with open(p, "rb") as f:
        return f.read().decode("latin-1").replace("\r\n", "\n")


def find_header(name, dirs):
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if fn.lower() == name.lower():
                return os.path.join(d, fn)
    return None


def resolve(m):
    """$include <file> (looked for in gpl.bp then syscom) or $include <directory> <file>."""
    if m.group(2):
        return find_header(m.group(2), [os.path.join(ROOT, m.group(1))])
    return find_header(m.group(1), [GPL, SYS])


def defined_in(path, seen):
    if path in seen:
        return set()
    seen.add(path)
    t = read(path)
    out = set(m.group(1).upper() for m in DEF.finditer(t))
    for m in INC.finditer(t):
        h = resolve(m)
        if h:
            out |= defined_in(h, seen)
    return out


def code_only(t):
    keep = []
    for l in t.split("\n"):
        if l.startswith("*"):
            continue
        l = re.sub(r"'[^']*'", "''", l)
        l = re.sub(r'"[^"]*"', '""', l)
        l = re.sub(r";\*.*$", "", l)
        keep.append(l)
    return "\n".join(keep)


def undefined_in(text):
    """The constants this program text uses that no header it includes (nor it) defines."""
    defs = set()
    seen = set()
    for m in INC.finditer(text):
        h = resolve(m)
        if h:
            defs |= defined_in(h, seen)
    defs |= set(m.group(1).upper() for m in DEF.finditer(text))
    defs |= set(m.group(1).upper() for m in EQU.finditer(text))
    used = set(u.upper() for u in USED.findall(code_only(text)))
    return sorted(u for u in used if u not in defs)


print("test-includes-units: reading " + GPL)
if not os.path.isdir(GPL) or not os.path.isdir(SYS):
    print("test-includes-units: gpl.bp or syscom not found - nothing measured.")
    sys.exit(2)

programs = sorted(fn for fn in os.listdir(GPL)
                  if not os.path.isdir(os.path.join(GPL, fn)) and not fn.lower().endswith(".h"))
check("CONTROL: a real number of programs was found (%d)" % len(programs), len(programs) > 100)

# THE MUTANTS FIRST, so a scanner that finds nothing cannot pass for a clean tree.
check("MUTANT: K$ADMINISTRATOR with only keys.h included is caught (the 1 Oct 2026 failure)",
      undefined_in("$include keys.h\n   x = kernel(K$ADMINISTRATOR, -1)\n") == ["K$ADMINISTRATOR"])
check("CONTROL: the same line with int$keys.h included is clean",
      undefined_in("$include keys.h\n$include int$keys.h\n   x = kernel(K$ADMINISTRATOR, -1)\n") == [])
check("CONTROL: the two-word include form is followed ($include syscom err.h defines ER$ARGS)",
      undefined_in("$include syscom err.h\n   x = ER$ARGS\n") == [])
check("CONTROL: a constant in a comment or a string is not a use",
      undefined_in("* K$ADMINISTRATOR\n   x = 'K$ADMINISTRATOR'   ;* K$ADMINISTRATOR\n") == [])
check("CONTROL: a $define in the program itself counts",
      undefined_in("$define MY$CONST 5\n   x = MY$CONST\n") == [])

bad = {}
for fn in programs:
    miss = undefined_in(read(os.path.join(GPL, fn)))
    if miss:
        bad[fn] = miss
for fn, miss in bad.items():
    print("    %-18s uses %s" % (fn, ", ".join(miss[:8])))
check("no program uses a constant that none of its headers defines", not bad,
      "%d program(s): %s" % (len(bad), ", ".join(sorted(bad))))

print("")
if passes == 0:
    print("test-includes-units: VOID - no check ran.")
    sys.exit(2)
if failures:
    print("test-includes-units: %d passed, %d failed." % (passes, failures))
    sys.exit(1)
print("test-includes-units: %d passed, 0 failed." % passes)
sys.exit(0)
