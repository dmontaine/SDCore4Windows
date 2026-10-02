"""RESTORE.ACCOUNT LATEST picks the newest backup made on this computer that holds the account.

WHY THIS EXISTS.  Owner's request, 2 Oct 2026: restore the most recent backup without
typing its name, on both ports.  sdsys/gpl.bp/restorea is SHARED with SD Core for Linux
byte for byte, so the rule has to live in one place and not drift.  The choice is made from
the FILE NAME alone (backupa writes SD-<host>-<what>-<yyyymmdd-hhmmss>.zip), which is what
this guard models.

WHAT IT PROVES AND WHAT IT DOES NOT.  A Python model of the rule is run over names, with
mutants, and the BASIC text is checked for the same elements (the model and the BASIC are
two copies of one rule, so each element the model relies on is looked for in the source).
THE BASIC ITSELF HAS NOT BEEN RUN BY THIS GUARD: bbcmp compiles it (checked by hand, 2 Oct
2026, with a HEAD control), and a cycle plus a real LATEST restore is what runs it.

  python gplbld/test-restorelatest-units.py

Exit 0 all checks passed, 1 a check failed, 2 the tree is not there to read.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.join(os.path.dirname(HERE), "sdsys")

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


def read(*parts):
    p = os.path.join(SDSYS, *parts)
    if not os.path.isfile(p):
        return None
    with open(p, "rb") as f:
        return f.read().decode("latin-1").replace("\r\n", "\n")


def is_digits(s):
    return s.isdigit()


def pick(files, host, names, want_all, newest=True, own_host=True, whole_name=True):
    """The rule in restorea's LATEST block, as a function of the file names."""
    host = host.lower()
    best, bstamp = "", ""
    for fid in files:
        n = fid.lower()
        if len(n) < 26:
            continue
        if n[:3] != "sd-" or n[-4:] != ".zip":
            continue
        core = n[3:-4]
        stamp = core[-15:]
        if not (len(stamp) == 15 and stamp[8] == "-" and is_digits(stamp[:8]) and is_digits(stamp[9:])):
            continue
        rest = core[:-16]
        if own_host and rest[:len(host) + 1] != host + "-":
            continue
        what = rest[len(host) + 1:] if own_host else rest.split("-", 1)[-1]
        if what == "":
            continue
        if want_all:
            ok = (what == "all")
        elif what == "all":
            ok = True
        elif len(what) > 8 and what.endswith("accounts") and is_digits(what[:-8]):
            ok = True
        else:
            if whole_name:
                ok = all(("-" + what + "-").find("-" + a + "-") >= 0 for a in names)
            else:
                ok = all(what.find(a) >= 0 for a in names)
        if ok and ((stamp > bstamp) if newest else (stamp < bstamp or bstamp == "")):
            best, bstamp = fid, stamp
    return best


FILES = [
    "SD-ace-don-20261001-144419.zip",
    "SD-ace-don-20261002-002457.zip",       # newest don-only
    "SD-ace-sam-20261002-090000.zip",       # newer, but another account
    "SD-ace-don-sam-20261001-120000.zip",   # two accounts, older than the newest don
    "SD-other-don-20261003-000000.zip",     # another computer's
    "SD-ace-all-20261001-080000.zip",
    "SD-ace-5accounts-20260930-010101.zip",
    "SD-ace-undon-20261004-000000.zip",     # 'undon' must not match 'don'
    "notes.txt",
    "SD-ace-don-2026100-002457.zip",        # malformed stamp
]

print("test-restorelatest-units: RESTORE.ACCOUNT LATEST")
check("the newest zip that holds don, from this computer",
      pick(FILES, "ace", ["don"], False) == "SD-ace-don-20261002-002457.zip", pick(FILES, "ace", ["don"], False))
check("another account's newer zip is not chosen for don",
      pick(FILES, "ace", ["sam"], False) == "SD-ace-sam-20261002-090000.zip")
check("don and sam together: only the zip naming both qualifies (or an all / N-accounts zip)",
      pick(FILES, "ace", ["don", "sam"], False) == "SD-ace-don-sam-20261001-120000.zip",
      pick(FILES, "ace", ["don", "sam"], False))
check("ALL takes the newest zip made with ALL", pick(FILES, "ace", [], True) == "SD-ace-all-20261001-080000.zip")
check("another computer's zip is ignored even though it is the newest",
      pick(FILES, "ace", ["don"], False) != "SD-other-don-20261003-000000.zip")
check("a name that only contains the account ('undon') does not match 'don'",
      pick(FILES, "ace", ["don"], False) != "SD-ace-undon-20261004-000000.zip")
check("a computer with no backups finds nothing", pick(FILES, "nobody", ["don"], False) == "")
check("no zip for 'zed' qualifies except the all and N-accounts ones, newest of them",
      pick(FILES, "ace", ["zed"], False) == "SD-ace-all-20261001-080000.zip", pick(FILES, "ace", ["zed"], False))
check("a file that is not a backup name is skipped", pick(["notes.txt", "x.zip"], "ace", ["don"], False) == "")
check("host match is case-insensitive", pick(FILES, "ACE", ["don"], False) == "SD-ace-don-20261002-002457.zip")

# MUTANTS on the model: each is a plausible edit to the BASIC.
check("MUTANT: oldest instead of newest is caught",
      pick(FILES, "ace", ["don"], False, newest=False) != "SD-ace-don-20261002-002457.zip")
check("MUTANT: any computer's zips is caught",
      pick(FILES, "ace", ["don"], False, own_host=False) != "SD-ace-don-20261002-002457.zip")
check("MUTANT: substring instead of whole account name is caught",
      pick(FILES, "ace", ["don"], False, whole_name=False) != "SD-ace-don-20261002-002457.zip")

# The BASIC says the same things.
src = read("gpl.bp", "restorea")
m16, m47, m48 = read("messages", "13016"), read("messages", "13047"), read("messages", "13048")
if None in (src, m16, m47, m48):
    print("test-restorelatest-units: restorea or its messages not found - nothing more measured.")
    sys.exit(2 if passes == 0 else 1)

block = src.split("upcase(zip.path) = 'LATEST'", 1)[-1].split("end else", 1)[0] if "upcase(zip.path) = 'LATEST'" in src else ""
check("CONTROL: restorea has the LATEST block", block != "")
check("it reads this computer's name from !acc_os_info (key 'host')", "'host'" in block and "!acc_os_info" in block)
check("it lists the saved backup directory (openpath + select)", "openpath bak.dir" in block and "select lat.f" in block)
check("it keeps only SD-*.zip names", "'sd-'" in block and "'.zip'" in block)
check("it orders by the stamp, newest wins", "lat.stamp > lat.bstamp" in block)
check("it ignores another computer's zips", "lat.rest[1, len(lat.host) + 1] # lat.host : '-'" in block)
check("it matches each account as a whole hyphen-delimited name",
      "index('-' : lat.what : '-', '-' : names<k> : '-', 1)" in block)
check("ALL takes only zips made with all", "lat.ok = (lat.what = 'all')" in block)
check("it says which zip it chose (13048) and refuses when none (13047)",
      "sysmsg(13048" in block and "sysmsg(13047" in block)
check("the unpack still checks the manifest (nothing changed by the name alone)", "13013" in src)
check("message 13016 shows both LATEST forms", "RESTORE.ACCOUNT LATEST name" in m16 and "RESTORE.ACCOUNT LATEST ALL" in m16)
check("message 13047 and 13048 exist with their placeholders", "%1" in m47 and "%2" in m47 and "%1" in m48)
check("the bare-name branch is kept for everything but LATEST", "end else" in src and "if index(zip.path, '/', 1) = 0" in src)

print("")
if passes == 0:
    print("test-restorelatest-units: VOID - no check ran.")
    sys.exit(2)
if failures:
    print("test-restorelatest-units: %d passed, %d failed." % (passes, failures))
    sys.exit(1)
print("test-restorelatest-units: %d passed, 0 failed." % passes)
sys.exit(0)
