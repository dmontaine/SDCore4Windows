"""test-sshseed-units.py - a FIRST install makes sdssh EMPTY; only an upgrade seeds it from sdusers.

    python C:\\Users\\Don\\Projects\\SDCore4Windows\\sdb_ai\\sd64\\gplbld\\test-sshseed-units.py

ORDINARY UNELEVATED PROMPT.  Reads text only; runs nothing, installs nothing.  Exit 0 all passed, 1 something failed,
2 a file it reads is missing.

WHY IT EXISTS (18 Nov 26, four-version audit round 2; Linux's mail 2026-11-18T0220, item 1).  sync-route-groups.ps1
seeded sdssh from sdusers whenever this run created the group.  On a FIRST install sd.iss's [Run] step has just put the
installing user in sdusers (localgroup sdusers "{username}" /add), and SyncRouteGroups runs after it at ssPostInstall,
so a fresh install delivered the installing user with ssh ON, unasked.  Linux Core makes sdssh empty and its ATTACH
turns nothing on; the owner's rule is delivered closed, the administrator opens it (the wizard's "open every access
gate" box, attach-account.ps1 -OpenGates, is the person asking).  The fix: sd.iss passes -FirstInstall when
DataTreeWasAbsent (sampled before any file is written), and the script then leaves a new sdssh empty.

What is checked: S1 the script declares -FirstInstall and its seed branch is reached only when it is NOT given (the
FirstInstall arm comes before the seeding arm and says so); S2 sd.iss's SyncRouteGroups adds -FirstInstall exactly when
DataTreeWasAbsent, and the attach step runs after it; S3 the order in sd.iss is still [Run]'s sdusers add, then the
route groups.  MUTANTS (text copies, the live files only read): the script as it was at HEAD before this fix (no
-FirstInstall arm) is caught; an sd.iss whose SyncRouteGroups lost the flag is caught.  NOT checked: what Windows does at
an install - that is a cycle (a fresh install's sdssh has no members; an upgrade from a tree with no sdssh seeds it).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "sync-route-groups.ps1")
ISS = os.path.join(HERE, "sd.iss")

fails = 0
passes = 0


def row(ok, label, detail=""):
    global fails, passes
    if ok:
        passes += 1
        print("  [PASS] " + label)
    else:
        fails += 1
        print("  [FAIL] " + label + ("  " + detail if detail else ""))


def read(p):
    if not os.path.isfile(p):
        print("test-sshseed-units: cannot read " + p)
        sys.exit(2)
    with open(p, "rb") as f:
        return f.read().decode("utf-8", "replace").replace("\r\n", "\n")


def code(t):
    return "\n".join(l for l in t.split("\n") if not l.lstrip().startswith("#"))


def script_problems(t):
    c = code(t)
    out = []
    if not re.search(r"param\(\[switch\]\$Check,\s*\[switch\]\$FirstInstall\)", c):
        out.append("no -FirstInstall switch")
    i_new = c.find("if (-not $sshIsNew) {")
    i_first = c.find("} elseif ($FirstInstall) {")
    i_seed = c.find("$members = Get-Members $SeedFrom")
    if not (0 <= i_new < i_first < i_seed):
        out.append("the seed is not behind a FirstInstall arm (positions %d, %d, %d)" % (i_new, i_first, i_seed))
    elif "Add-LocalGroupMember" in c[i_first:c.find("} else {", i_first)]:
        out.append("the FirstInstall arm adds members")
    return out


def iss_problems(t):
    out = []
    i = t.find("function SyncRouteGroups: String;")
    j = t.find("\nend;", i)
    body = t[i:j]
    if i < 0:
        return ["no SyncRouteGroups"]
    if not re.search(r"if DataTreeWasAbsent then\s*\n\s*Args := Args \+ ' -FirstInstall';", body):
        out.append("SyncRouteGroups does not pass -FirstInstall on DataTreeWasAbsent")
    if "Exec(Ps, Args," not in body:
        out.append("SyncRouteGroups does not run the arguments it built")
    s = t.find("RouteMsg := SyncRouteGroups;")
    a = t.find("AttachCode := AttachInstallerAccount;")
    if not (0 < s < a):
        out.append("the attach step does not run after the route groups (%d, %d)" % (s, a))
    return out


print("test-sshseed-units: script " + SCRIPT)
print("test-sshseed-units: installer " + ISS)
st = read(SCRIPT)
it = read(ISS)
p = script_problems(st)
row(not p, "S1 sync-route-groups.ps1 leaves a NEW sdssh empty under -FirstInstall; the seed from sdusers is only the other arm", "; ".join(p))
p = iss_problems(it)
row(not p, "S2 sd.iss passes -FirstInstall exactly when the data tree was absent before the run, and attaches the installing user after it", "; ".join(p))
r = it.find('Parameters: "localgroup sdusers ""{username}"" /add"')
row(r > 0 and it.find("[Run]") < r < it.find("[UninstallRun]"),
    "S3 the installing user is put in sdusers by [Run] (which is why a first install must not seed): found at offset %d" % r)

old = st.replace("    } elseif ($FirstInstall) {\n", "    } elseif ($false) {\n")
row(script_problems(old) != [], "MUTANT: a script whose seed is not behind -FirstInstall is caught")
old2 = re.sub(r"\n    \} elseif \(\$FirstInstall\) \{\n[^\n]*\n", "\n", st)
row(script_problems(old2) != [], "MUTANT: the script as it was before the fix (no FirstInstall arm) is caught")
mut = it.replace("    Args := Args + ' -FirstInstall';", "    Args := Args;")
row(iss_problems(mut) != [], "MUTANT: an sd.iss that lost the flag is caught")
row(old2 != st and mut != it and old != st, "CONTROL: each mutant changed its copy (the anchors were found in the live files)")

print("test-sshseed-units: %d passed, %d failed" % (passes, fails))
sys.exit(1 if fails else 0)
