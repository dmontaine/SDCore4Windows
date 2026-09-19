"""RELEASE_1.1 72 - no PowerShell command line interpolates a BASIC variable
inside a DOUBLE-quoted string without somebody having declared it.

WHY THIS EXISTS.  A PowerShell double-quoted string EXPANDS "$name"; a
single-quoted one is literal.  This tree builds PowerShell command lines by
concatenating BASIC literals around BASIC variables, and where the variable
lands inside a double-quoted region, a "$" in its value is expanded away -
silently, leaving a SHORTER string that the command then acts on.  Reported by
the SD Core for Linux port, who lost a cycle to the POSIX form of it: their
set.owner built a command line containing an unquoted $hold, the shell expanded
it to nothing, and the helper chowned the account directory instead.

WHAT IT COST HERE: nothing yet, and that is the point of guarding it now.  The
one route a value with a "$" could reach was createa's secure.account.dir,
which interpolated the account pathname - CONFIG('USRDIR') plus a name, or on
the OTHER arm a pathname the administrator types - into

    & icacls.exe "<pathname>" /inheritance:r

so a USRDIR with a "$" segment would have had icacls strip inherited ACEs from
whatever shorter path remained.  That site is fixed structurally (single
quotes, embedded quotes doubled, cred_set:192's shape) and this guard is what
stops it, or another like it, coming back.

***THIS IS A REGISTER, NOT A PROOF.***  The declared sites below are the ones
that exist today.  Each takes an OS user or group name and the argument for
their safety is that such a name is validated before it gets here - an argument
this file does NOT re-check and does not assert.  What it asserts is that the
set has not GROWN: a new unsafe interpolation cannot appear without somebody
adding it here and saying what it takes.

It reads source only: no SD, no install, no elevation, no cycle.

  python gplbld/test-psinterp-units.py

Exit 0 all checks passed, 1 a check failed, 2 the tree could not be read.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BPDIR = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp"))

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


def strip_basic(line):
    """Drop SD BASIC comments: a whole line starting * or !, and a trailing ;*.

    The same rule gplbld/strip-comments.ps1 applies for its 'basic' kind, and it
    matters for the same reason: this tree quotes the very spelling it warns
    about in the comment beside the fix.
    """
    lead = line.lstrip()
    if lead.startswith("*") or lead.startswith("!"):
        return ""
    i = line.find(";*")
    return line[:i] if i >= 0 else line


# A BASIC literal that ENDS with a double quote, immediately followed by a
# concatenation - which is exactly "open a double-quoted PowerShell region, then
# interpolate".  The closing half (: '" ...) is deliberately NOT counted: every
# such region has exactly one opening, so counting both would double every site.
OPEN = re.compile(r"\"'\s*:\s*([A-Za-z_][A-Za-z0-9_.$]*)")

# A file is in scope if it hands a built string to PowerShell at all.
#
# OS.EXECUTE IS ANCHORED AT THE START OF A STATEMENT, and that is measured
# rather than tidiness: BCOMP is the compiler that IMPLEMENTS the statement, so
# it carries "st.os.execute" as a label and a dispatch entry.  Unanchored, it
# pulled BCOMP into the corpus, whose "LDSTR    \"" : oconv(...)" is an assembly
# listing and has nothing to do with PowerShell - a false positive that would
# have had to be declared as a non-site, which is how a register rots.
RUNS_PS = re.compile(r"ps_script\s*\(|^\s*os\.execute\b",
                     re.IGNORECASE | re.MULTILINE)


def sites(path):
    """[(line number, variable)] for every double-quoted interpolation."""
    out = []
    with open(path, encoding="ISO-8859-1") as f:
        for n, raw in enumerate(f, 1):
            for m in OPEN.finditer(strip_basic(raw)):
                out.append((n, m.group(1)))
    return out


def builders():
    """gpl.bp files that build a command line for PowerShell."""
    found = []
    for name in sorted(os.listdir(BPDIR)):
        p = os.path.join(BPDIR, name)
        if not os.path.isfile(p):
            continue
        with open(p, encoding="ISO-8859-1") as f:
            body = "".join(strip_basic(l) + "\n" for l in f)
        if RUNS_PS.search(body):
            found.append(name)
    return found


# ***THE DECLARED SET.***  file -> sorted list of the variables interpolated
# inside a double-quoted PowerShell string, one entry per site.  Measured
# 19 Sep 2026.  A new entry needs a line here saying what the variable can hold.
#
#   create_user, delete_user, is_sd_user, is_user, profile_dir : username
#   is_group, os_group                                         : group, member
#
# All are OS account or group names on their way to a Local* cmdlet.  Windows
# permits "$" in a local account name, so these are not "$"-free by
# construction; they are "$"-free because SD validates the names it accepts.
# ***THAT VALIDATION IS NOT RE-CHECKED HERE*** - see the header.
#
# createa is ABSENT ON PURPOSE and the check below asserts it: its two sites
# were the reachable ones and 72 rewrote them with single quotes.
DECLARED = {
    "create_user": ["username"],
    "delete_user": ["username"],
    "is_group":    ["group"],
    "is_sd_user":  ["username"],
    "is_user":     ["username"],
    "os_group":    ["group", "group", "group", "group", "group", "member", "member"],
    "profile_dir": ["username"],
}

if not os.path.isdir(BPDIR):
    print("gpl.bp not found: " + BPDIR)
    sys.exit(2)

print("test-psinterp-units: gpl.bp " + BPDIR)
print("")

print("=== 0. the null case is refused: the scan ran against something ===")
files = builders()
check("gpl.bp files that build a PowerShell command line (%d)" % len(files),
      len(files) >= 10, "found: " + repr(files))

found = {}
for name in files:
    s = sites(os.path.join(BPDIR, name))
    if s:
        found[name] = s
total = sum(len(v) for v in found.values())
check("CONTROL: the detector found interpolation sites at all (%d)" % total,
      total >= 5, "it found none, so every row below would pass vacuously")

print("")
print("=== 1. the set of double-quoted interpolations is the declared one ===")
got = dict((k, sorted(v for _, v in s)) for k, s in found.items())
extra = sorted(set(got) - set(DECLARED))
missing = sorted(set(DECLARED) - set(got))
check("no UNDECLARED file interpolates inside double quotes",
      extra == [],
      "declare these, with what the variable can hold: " + repr(
          [(f, found[f]) for f in extra]))
check("every declared file still has its sites",
      missing == [],
      "these are declared and no longer found - delete the row if the fix is "
      "real, because a stale declaration hides the next one: " + repr(missing))
for name in sorted(set(got) & set(DECLARED)):
    check("%s: %s" % (name, ", ".join(got[name])),
          got[name] == DECLARED[name],
          "declared %s, found %s at %s" % (DECLARED[name], got[name],
                                           found[name]))

print("")
print("=== 2. createa's two sites are gone and stay gone (the 72 fix) ===")
ca = sites(os.path.join(BPDIR, "createa"))
check("createa interpolates nothing inside a double-quoted string",
      ca == [],
      "72 rewrote secure.account.dir with single quotes; this is back: " + repr(ca))
with open(os.path.join(BPDIR, "createa"), encoding="ISO-8859-1") as f:
    catext = f.read()
check("createa still builds the icacls path as a PowerShell LITERAL",
      "sad.path" in catext and "char(39)" in catext,
      "the single-quoting went away, so the pathname is unquoted or "
      "double-quoted again")

print("")
print("=== 3. MUTANT: the pre-72 line is detected ===")
# The exact line 72 replaced.  A detector that cannot see it proves nothing
# about the rows above.  Run on TEXT, never on the live file.
mutant = """secure.account.dir:
   sad.ps := '& icacls.exe "' : pathname : '" /inheritance:r'
   sad.ps := ' /grant "' : sad.group : ':(OI)(CI)(M)" | Out-Null; '
"""
hits = [m.group(1) for line in mutant.splitlines()
        for m in OPEN.finditer(strip_basic(line))]
check("the two pre-72 icacls lines are seen (%s)" % ", ".join(hits),
      hits == ["pathname", "sad.group"],
      "the detector would not have caught 72 itself")

# And the comment form must NOT be seen, or every fix documented beside itself
# raises a false positive - PRE_RELEASE 131's lesson, in this file's terms.
commented = '*   the old line was \'& icacls.exe "\' : pathname : \'" ...\''
hits2 = [m.group(1) for m in OPEN.finditer(strip_basic(commented))]
check("the same line INSIDE a comment is not counted (%d hit(s))" % len(hits2),
      hits2 == [],
      "a fix documented beside itself would read as the defect it repairs")

print("")
print("test-psinterp-units: %d passed, %d failed." % (passed, failed))
sys.exit(1 if failed else 0)
