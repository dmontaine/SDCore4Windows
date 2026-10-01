"""The backup/restore helpers must not assume @ds is a backslash.

WHY THIS EXISTS.  1 Oct 2026, the owner's first BACKUP.ACCOUNT on an installed
Solo stopped with "Could not read USRDIR for the backup (C:\\Users\\Don\\SDCoreSolo\\
user_accounts)".  @ds is "/" in this port (gplsrc/sddefs.h, DS) and config('USRDIR')
is a NATIVE Windows path with backslashes, so counting @ds in it always answered 0.
The comment in the neighbouring acc_archive even called @ds "the Windows separator".
Nothing could have caught it before an SD session ran it: bbcmp compiles it either
way, and the PowerShell half's unit test used backslash paths only.

Two helpers had the assumption and both are guarded here, because fixing the first
alone would have failed one step later (acc_tree_count hands acc_archive a MIXED path,
"C:\\...\\user_accounts/sduser", and check.full wants a drive letter, a colon and @ds):

  acc_os_info  - USRDIR's backslashes become @ds BEFORE the separators are counted;
  acc_archive  - norm.path makes every "/" AND every "\\" into @ds.

A source check on the shipped BASIC: no SD, no install, no elevation.  The mutants run
on synthetic text.  Identical in both Windows trees.

  python gplbld/test-accseparator-units.py

Exit 0 all checks passed, 1 a check failed, 2 the tree is not there to read.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GPL = os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp"))

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


def read(name):
    p = os.path.join(GPL, name)
    if not os.path.isfile(p):
        return None
    with open(p, "rb") as f:
        return f.read().decode("latin-1").replace("\r\n", "\n")


def code_only(t):
    """Drop BASIC comment lines (column-1 asterisk), so a comment cannot satisfy a check."""
    return "\n".join(l for l in t.split("\n") if not l.startswith("*"))


def os_info_problems(t):
    c = code_only(t)
    m = re.search(r"usr\.dir = config\('USRDIR'\)(.*?)n = count\(usr\.dir, @ds\)", c, re.S)
    if not m:
        return ["acc_os_info no longer reads USRDIR and then counts @ds in it"]
    between = m.group(1)
    if "convert('\\', @ds, usr.dir)" not in between:
        return ["USRDIR's backslashes are not made @ds before the separators are counted"]
    return []


def norm_path_problems(t):
    c = code_only(t)
    m = re.search(r"^norm\.path:\n(.*?)\n\s*return", c, re.S | re.M)
    if not m:
        return ["acc_archive has no norm.path routine"]
    body = m.group(1)
    if "convert('/\\', @ds : @ds, np)" not in body:
        return ["norm.path does not make BOTH '/' and '\\' into @ds"]
    return []


print("test-accseparator-units: reading " + GPL)
info = read("acc_os_info")
arch = read("acc_archive")
if info is None or arch is None:
    print("test-accseparator-units: acc_os_info or acc_archive not found - nothing measured.")
    sys.exit(2)

check("CONTROL: both helpers have code to check", len(code_only(info)) > 200 and len(code_only(arch)) > 200)
p = os_info_problems(info)
check("acc_os_info normalises USRDIR's separators before counting", p == [], "; ".join(p))
p = norm_path_problems(arch)
check("acc_archive's norm.path converts both separators to @ds", p == [], "; ".join(p))

# MUTANTS on synthetic text: each is the code as it stood on 1 Oct 2026, or a plausible tidy-up.
good_info = "   usr.dir = config('USRDIR')\n   usr.dir = convert('\\', @ds, usr.dir)\n   n = count(usr.dir, @ds)\n"
check("CONTROL: correct synthetic acc_os_info passes", os_info_problems(good_info) == [])
check("MUTANT: acc_os_info as it stood (no conversion) is caught",
      os_info_problems("   usr.dir = config('USRDIR')\n   n = count(usr.dir, @ds)\n") != [])
check("MUTANT: the conversion only in a comment is caught",
      os_info_problems("   usr.dir = config('USRDIR')\n* usr.dir = convert('\\', @ds, usr.dir)\n   n = count(usr.dir, @ds)\n") != [])
check("MUTANT: the conversion placed AFTER the count is caught",
      os_info_problems("   usr.dir = config('USRDIR')\n   n = count(usr.dir, @ds)\n   usr.dir = convert('\\', @ds, usr.dir)\n") != [])
good_np = "norm.path:\n   if np = '' then return\n   np = convert('/\\', @ds : @ds, np)\n   return\n"
check("CONTROL: correct synthetic norm.path passes", norm_path_problems(good_np) == [])
check("MUTANT: norm.path as it stood (only '/' converted) is caught",
      norm_path_problems("norm.path:\n   if np = '' then return\n   np = convert('/', @ds, np)\n   return\n") != [])

print("")
if passes == 0:
    print("test-accseparator-units: VOID - no check ran.")
    sys.exit(2)
if failures:
    print("test-accseparator-units: %d passed, %d failed." % (passes, failures))
    sys.exit(1)
print("test-accseparator-units: %d passed, 0 failed." % passes)
sys.exit(0)
