#!/usr/bin/env python3
"""test-groupacctroot-units.py - the installer locks group_accounts as it locks user_accounts (RELEASE_1.1 161), as invariants.

  python gplbld/test-groupacctroot-units.py
  python gplbld/test-groupacctroot-units.py --selftest

No install, no elevation, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

20 Oct 26 Windows port.  Linux mails T1610 and T1625 of 19 Oct (981a36a, 2a81059) found that a group account's record files were
left writable by every SD user, and told us to look for the SHAPE.  Here it was the container: sd.iss SecureAccountDirs named
user_accounts only, so group_accounts kept the data tree's inheritable sdusers Modify, and a group account whose own create-time
stamp failed (message 10055) was never repaired.  This reads sd.iss, secure-account-dirs.ps1 and create_account as TEXT:

  I1  sd.iss locks the group_accounts container and re-applies its directories (both scripts named for that root)
  I2  ... with the group prefix sdg_, passed to secure-account-dirs.ps1 as -GroupPrefix
  I3  ... and user_accounts is still done, with sdu_
  S1  secure-account-dirs.ps1 takes -GroupPrefix, default sdu_ (every older caller unchanged)
  S2  ... and builds each directory's group from it, not from a literal
  S3  ... and skips a reparse point before it reads or stamps anything (Linux mail T1625: a repair must not be aimed by the people it repairs)
  C1  create_account writes ACC$GROUP for a GROUP account as downcase("sdg_" : acc.name), the name the prefix must match

--selftest breaks each fact in turn and requires the check to say so.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ISS = os.path.join(HERE, "sd.iss")
PS1 = os.path.join(HERE, "secure-account-dirs.ps1")
CRA = os.path.join(HERE, "..", "sdsys", "gpl.bp", "create_account")


def slurp(p):
    with open(p, encoding="latin-1") as f:
        return f.read()


def iss_function(iss, name):
    m = re.search(r"^function %s\b.*?^end;" % re.escape(name), iss, re.S | re.M)
    return m.group(0) if m else ""


def checks(iss, ps1, cra):
    res = []

    def ck(name, ok, detail=""):
        res.append((name, bool(ok), detail))

    dirs = iss_function(iss, "SecureAccountDirs")
    root = iss_function(iss, "SecureAccountRoot")
    ck("I1 SecureAccountDirs locks the group_accounts root",
       re.search(r"SecureAccountRoot\([^;]*group_accounts[^;]*;", dirs, re.S) is not None, "no group_accounts call")
    ck("I2 ... with sdg_, passed to the script as -GroupPrefix",
       re.search(r"group_accounts'\)\s*,\s*'sdg_'", dirs) is not None and "-GroupPrefix" in root,
       "sdg_ %s, -GroupPrefix %s" % ("sdg_" in dirs, "-GroupPrefix" in root))
    ck("I3 ... and user_accounts is still done, with sdu_",
       re.search(r"user_accounts'\)\s*,\s*'sdu_'", dirs) is not None)
    ck("I4 ... and the helper runs both scripts (container, then per account)",
       "secure-accounts" in dirs + root or ("Container" in root and "PerAccount" in root))

    ck("S1 secure-account-dirs.ps1 takes -GroupPrefix, default sdu_",
       re.search(r"\[string\]\$GroupPrefix\s*=\s*'sdu_'", ps1) is not None)
    ck("S2 ... and builds the group from it",
       re.search(r"\$group\s*=\s*\$GroupPrefix\s*\+\s*\$name", ps1) is not None and "$group = 'sdu_'" not in ps1)

    refl = ps1.find("[IO.FileAttributes]::ReparsePoint")
    looks = ps1.find("if (-not (Test-LooksLikeAccount")
    ck("S3 ... and skips a reparse point before it reads or stamps anything",
       0 <= refl < looks and "continue" in ps1[refl:looks], "reparse test at %d, voc test at %d" % (refl, looks))

    ck("C1 create_account names a GROUP account's group downcase(\"sdg_\" : acc.name)",
       re.search(r'group_name\s*=\s*downcase\("sdg_"\s*:\s*acc\.name\)', cra) is not None)
    return res


def selftest():
    iss, ps1, cra = slurp(ISS), slurp(PS1), slurp(CRA)
    base = checks(iss, ps1, cra)
    bad = [n for n, ok, _ in base if not ok]
    if bad:
        print("selftest: the real files already fail: %s" % bad)
        return False
    mutants = [
        ("sd.iss: group_accounts not locked",
         iss.replace("ExpandConstant('{#DataDir}\\group_accounts'), 'sdg_'", "ExpandConstant('{#DataDir}\\user_accounts'), 'sdg_'"), ps1, cra, "I1"),
        ("sd.iss: group root done with sdu_",
         iss.replace("group_accounts'), 'sdg_'", "group_accounts'), 'sdu_'"), ps1, cra, "I2"),
        ("sd.iss: -GroupPrefix never passed", iss.replace("' -GroupPrefix '", "' -Nothing '"), ps1, cra, "I2"),
        ("sd.iss: user_accounts dropped",
         iss.replace("ExpandConstant('{#DataDir}\\user_accounts'), 'sdu_'", "ExpandConstant('{#DataDir}\\other'), 'sdu_'"), ps1, cra, "I3"),
        ("script: no -GroupPrefix", iss, ps1.replace("[string]$GroupPrefix = 'sdu_',", ""), cra, "S1"),
        ("script: default changed", iss, ps1.replace("$GroupPrefix = 'sdu_'", "$GroupPrefix = 'sdg_'"), cra, "S1"),
        ("script: group from a literal", iss, ps1.replace("$group = $GroupPrefix + $name", "$group = 'sdu_' + $name"), cra, "S2"),
        ("script: reparse points not skipped", iss, ps1.replace("[IO.FileAttributes]::ReparsePoint", "[IO.FileAttributes]::Hidden"), cra, "S3"),
        ("script: reparse skip after the voc test",
         iss, ps1.replace("if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)", "if ($false)")
         + "\nif ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }\n", cra, "S3"),
        ("create_account: another prefix", iss, ps1, cra.replace('downcase("sdg_" : acc.name)', 'downcase("grp_" : acc.name)'), "C1"),
    ]
    ok = True
    for name, i, p, c, want in mutants:
        if (i, p, c) == (iss, ps1, cra):
            print("  [FAIL] selftest: %s (the mutation changed nothing)" % name)
            ok = False
            continue
        failed = [n.split()[0] for n, passed, _ in checks(i, p, c) if not passed]
        caught = want in failed
        print("  [%s] selftest: %s%s" % ("PASS" if caught else "FAIL", name, "" if caught else " (NOT CAUGHT; failed: %s)" % failed))
        ok = ok and caught
    return ok


def main():
    for p in (ISS, PS1, CRA):
        if not os.path.isfile(p):
            print("test-groupacctroot-units: CANNOT RUN - %s missing" % os.path.normpath(p))
            return 2
    print("test-groupacctroot-units: reading %s, %s and %s" % tuple(os.path.normpath(p) for p in (ISS, PS1, CRA)))
    if "--selftest" in sys.argv:
        return 0 if selftest() else 1
    res = checks(slurp(ISS), slurp(PS1), slurp(CRA))
    failed = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    print("\ntest-groupacctroot-units: %d passed, %d failed" % (len(res) - failed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
