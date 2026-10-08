"""RESTORE.ACCOUNT LATEST picks the newest backup made on this computer that holds the account.

WHY THIS EXISTS.  Owner's request, 2 Oct 2026: restore the most recent backup without
typing its name, on both ports.  sdsys/gpl.bp/restorea is SHARED with SD Core for Linux
byte for byte, so the rule has to live in one place and not drift.  backupa writes
SD-<host>-<what>-<yyyymmdd-hhmmss>.zip; the file name is a first cut (pick()), and since
5 Oct 2026 (owner) each zip it admits is OPENED and the newest whose MANIFEST holds every
named account is chosen (choose()): a newer backup that lacks the account is reported
(13049), and none that holds it is 13047.  Both are modelled here.

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


def choose(files, manifests, host, names, want_all, by_manifest=True, warn_on=True, unreadable_holds=False):
    """The whole rule, 5 Oct 2026.  manifests: {file: [accounts] or None when it cannot be read}.
    Returns (best, newest_of_anything_made_here, warning, nothing).  ALL: the name is the test."""
    host = host.lower()
    cands, newest, nstamp = [], "", ""
    for fid in files:
        n = fid.lower()
        if len(n) < 26 or n[:3] != "sd-" or n[-4:] != ".zip":
            continue
        core = n[3:-4]
        stamp = core[-15:]
        if not (len(stamp) == 15 and stamp[8] == "-" and is_digits(stamp[:8]) and is_digits(stamp[9:])):
            continue
        rest = core[:-16]
        if rest[:len(host) + 1] != host + "-":
            continue
        what = rest[len(host) + 1:]
        if what == "":
            continue
        if stamp > nstamp:
            newest, nstamp = fid, stamp
        if want_all:
            ok = (what == "all")
        elif what == "all" or (len(what) > 8 and what.endswith("accounts") and is_digits(what[:-8])):
            ok = True
        else:
            ok = all(("-" + what + "-").find("-" + a + "-") >= 0 for a in names)
        if ok:
            cands.append((stamp, fid))
    best = ""
    for stamp, fid in sorted(cands, reverse=True):
        if want_all:
            best = fid
            break
        if not by_manifest:
            best = fid
            break
        m = manifests.get(fid)
        if m is None:
            if unreadable_holds:
                best = fid
                break
            continue
        if all(a in m for a in names):
            best = fid
            break
    warning = bool(best) and not want_all and best != newest and warn_on
    return best, newest, warning, best == ""


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

# THE WHOLE RULE (5 Oct 2026, owner): the name is a first cut, the MANIFEST decides.
MF = {   # what each zip really holds
    "SD-ace-don-20261001-144419.zip": ["don"],
    "SD-ace-don-20261002-002457.zip": ["don"],
    "SD-ace-sam-20261002-090000.zip": ["sam"],
    "SD-ace-don-sam-20261001-120000.zip": ["don", "sam"],
    "SD-ace-all-20261001-080000.zip": ["don", "sam", "zed"],
    "SD-ace-5accounts-20260930-010101.zip": ["don", "a", "b", "c", "d"],
    "SD-ace-undon-20261004-000000.zip": ["undon"],
}
DEL_OLD, DEL_ALL = "SD-ace-don-20261001-000000.zip", "SD-ace-all-20261005-000000.zip"
FILES2 = [DEL_OLD, DEL_ALL]
MF2 = {DEL_OLD: ["don"], DEL_ALL: ["sam"]}      # the ALL zip was made after don was deleted
UNR_OLD, UNR_NEW = "SD-ace-don-20261001-000000.zip", "SD-ace-don-20261005-000000.zip"
FILES3 = [UNR_OLD, UNR_NEW]
MF3 = {UNR_OLD: ["don"], UNR_NEW: None}         # the newest cannot be read


def rule(files, mf, names, want_all, **kw):
    return choose(files, mf, "ace", names, want_all, **kw)


r = rule(FILES, MF, ["don"], False)
check("the newest zip that HOLDS don, and a warning: a newer backup (undon's) does not",
      r[0] == "SD-ace-don-20261002-002457.zip" and r[1] == "SD-ace-undon-20261004-000000.zip" and r[2] is True, str(r))
r = rule(FILES, MF, ["undon"], False)
check("the newest backup of anything holds it: no warning", r[0] == "SD-ace-undon-20261004-000000.zip" and r[2] is False, str(r))
r = rule(FILES, MF, ["zed"], False)
check("zed is only in the ALL zip, which is older than the newest backup: chosen, with a warning",
      r[0] == "SD-ace-all-20261001-080000.zip" and r[2] is True, str(r))
r = rule(FILES, MF, ["ghost"], False)
check("nothing holds ghost although an all and an N-accounts zip are admitted by name: 13047", r[3] is True and r[0] == "", str(r))
r = rule(FILES, MF, ["don", "sam"], False)
check("don and sam together: the zip that holds both, newest of them",
      r[0] == "SD-ace-don-sam-20261001-120000.zip" and r[2] is True, str(r))
r = rule(FILES2, MF2, ["don"], False)
check("an ALL zip made after don was deleted does not hide the older zip that holds him",
      r[0] == DEL_OLD and r[1] == DEL_ALL and r[2] is True, str(r))
check("(the name-only rule of 2 Oct picked the ALL zip there)", pick(FILES2, "ace", ["don"], False) == DEL_ALL)
r = rule(FILES3, MF3, ["don"], False)
check("a zip that cannot be read is skipped, and the warning says the newest was not usable",
      r[0] == UNR_OLD and r[1] == UNR_NEW and r[2] is True, str(r))
r = rule(FILES2, MF2, [], True)
check("ALL takes the newest zip made with ALL by name, no manifest asked, no warning",
      r[0] == DEL_ALL and r[2] is False, str(r))
r = rule(["SD-ace-sam-20261001-000000.zip"], {"SD-ace-sam-20261001-000000.zip": ["sam"]}, ["don"], False)
check("no backup holds don and the only zip is sam's: 13047", r[3] is True, str(r))
check("no backups at all: 13047", rule([], {}, ["don"], False)[3] is True)
check("another computer's newest zip is neither chosen nor the 'newest' to warn about",
      rule(FILES + ["SD-other-sam-20270101-000000.zip"], dict(MF, **{"SD-other-sam-20270101-000000.zip": ["sam"]}),
           ["don"], False)[1] == "SD-ace-undon-20261004-000000.zip")

# MUTANTS on the whole rule: each is a plausible edit to the BASIC.
check("MUTANT: the name alone decides (manifests ignored) is caught",
      rule(FILES2, MF2, ["don"], False, by_manifest=False)[0] != DEL_OLD)
check("MUTANT: no warning when a newer backup lacks the account is caught",
      rule(FILES, MF, ["don"], False, warn_on=False)[2] is not True)
check("MUTANT: an unreadable zip counted as holding the account is caught",
      rule(FILES3, MF3, ["don"], False, unreadable_holds=True)[0] != UNR_OLD)

# The BASIC says the same things.
src = read("gpl.bp", "restorea")
m16, m47, m48, m49 = read("messages", "13016"), read("messages", "13047"), read("messages", "13048"), read("messages", "13049")
archive_bas = read("gpl.bp", "acc_archive")
accarchive_py = None
# WINDOWS: the archive tool is sd-account-archive.ps1, not Linux's sd-accarchive (5 Oct 2026).
_p = os.path.join(HERE, "sd-account-archive.ps1")
if os.path.isfile(_p):
    with open(_p, "rb") as _f:
        accarchive_py = _f.read().decode("latin-1")
if None in (src, m16, m47, m48, m49, archive_bas, accarchive_py):
    print("test-restorelatest-units: restorea or its messages not found - nothing more measured.")
    sys.exit(2 if passes == 0 else 1)

block = src.split("upcase(zip.path) = 'LATEST'", 1)[-1].split("\n   end else", 1)[0] if "upcase(zip.path) = 'LATEST'" in src else ""
check("CONTROL: restorea has the LATEST block", block != "")
check("it reads this computer's name from !acc_os_info (key 'host')", "'host'" in block and "!acc_os_info" in block)
check("it lists the saved backup directory (openpath + select)", "openpath bak.dir" in block and "select lat.f" in block)
check("it keeps only SD-*.zip names", "'sd-'" in block and "'.zip'" in block)
check("it orders by the stamp, newest first", "lat.stamps<k> > lat.top" in block and "lat.stamps<lat.pick> = ''" in block)
check("it tracks the newest backup of anything made here, before the name cut",
      "lat.stamp > lat.nstamp" in block and block.index("lat.stamp > lat.nstamp") < block.index("lat.ok = @false"))
check("it OPENS each zip the name admits (the manifest only, nothing unpacked)",
      "call !acc_archive('MANIFEST'" in block and "lat.err = ''" in block)
check("a zip holds the account only when its manifest lists every name (whole [account x] lines)",
      "lat.line[1, 9] = '[account '" in block and "locate names<k> in lat.have<1> setting x else lat.holds = @false" in block)
check("ALL decides by name and leaves before any manifest is asked",
      "if all then" in block and block.index("lat.best = lat.id") < block.index("call !acc_archive('MANIFEST'"))
check("it warns (13049) only when the chosen zip is not the newest here, and not for ALL",
      "if not(all) and lat.best # lat.newest then" in block and "sysmsg(13049, lat.newest" in block)
check("message 13049 has its three placeholders", all(p in m49 for p in ("%1", "%2", "%3")))
check("the archive helper has a MANIFEST mode, and the archive script a Manifest mode",
      "md = 'MANIFEST'" in archive_bas and "'ACC-ARCHIVE MANIFEST OK'" in archive_bas
      and "'Manifest' {" in accarchive_py and "function Read-ZipManifest" in accarchive_py)
check("it ignores another computer's zips", "lat.rest[1, len(lat.host) + 1] # lat.host : '-'" in block)
check("it matches each account as a whole hyphen-delimited name",
      "index('-' : lat.what : '-', '-' : names<k> : '-', 1)" in block)
check("ALL takes only zips made with all", "lat.ok = (lat.what = 'all')" in block)
check("it says which zip it chose (13048) and refuses when none (13047)",
      "sysmsg(13048" in block and "sysmsg(13047" in block)
check("the unpack still checks the manifest (nothing changed by the name alone)", "13013" in src)
check("message 13016 shows both LATEST forms", "restore.account latest name" in m16 and "restore.account latest all" in m16)
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
