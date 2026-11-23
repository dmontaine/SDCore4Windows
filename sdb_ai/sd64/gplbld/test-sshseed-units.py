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

22 Nov 26 - RELEASE_1.1 393 (owner: "Yes, reset them"; Linux S.310).  -FirstInstall now also EMPTIES every route group that
was already there (a silent uninstall keeps them, so a "fresh" install inherited old members).  S1 now reads the new
order (the FirstInstall arm FIRST, then the not-new arm, then the seed); S4 checks that all six groups are noted when they
already existed and that the FirstInstall arm empties each through Clear-Group, which removes by ADSI and reads back.
MUTANTS added: no Clear-Group loop; one group not noted; Clear-Group that does not remove.
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
    i_first = c.find('    if ($FirstInstall) {\n        Say "$SshGroup starts empty')
    i_new = c.find("} elseif (-not $sshIsNew) {")
    i_seed = c.find("$members = Get-Members $SeedFrom")
    if not (0 <= i_first < i_new < i_seed):
        out.append("the seed is not behind a FirstInstall arm (positions %d, %d, %d)" % (i_first, i_new, i_seed))
    elif "Add-LocalGroupMember" in c[i_first:i_new]:
        out.append("the FirstInstall arm adds members")
    return out


GROUPS = ("SshGroup", "ApiGroup", "FilesGroup", "FilesWriteGroup", "FilesAdminGroup", "AiGroup")


def reset_problems(t):
    c = code(t)
    out = []
    for g in GROUPS:
        if not re.search(r"Ensure-Group \$%s \$\w+\n\s*(?:\$sshIsNew = \$script:GroupCreated\n\s*)?if \(-not \$script:GroupCreated\) \{ \$existed \+= \$%s \}" % (g, g), c):
            out.append("%s is not noted when it already existed" % g)
    i = c.find("    if ($FirstInstall) {\n        if ($existed.Count -eq 0) {")
    j = c.find('    if ($FirstInstall) {\n        Say "$SshGroup starts empty')
    if not (0 <= i < j) or "foreach ($g in $existed) { Clear-Group $g }" not in c[i:j]:
        out.append("the FirstInstall arm does not empty every group that existed, before the sdssh arm")
    f = c.find("function Clear-Group([string]$name) {")
    body = c[f:c.find("\n}\n", f)] if f >= 0 else ""
    if "$g.psbase.Invoke('Remove', $p)" not in body or "Get-AdsiMemberPaths" not in body or "$script:failed = $true" not in body:
        out.append("Clear-Group does not remove each member by ADSI and fail on what is left")
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

p = reset_problems(st)
row(not p, "S4 (393) under -FirstInstall every route group that already existed is emptied (Clear-Group, by ADSI, read back) before anyone is granted", "; ".join(p))

old = st.replace('    if ($FirstInstall) {\n        Say "$SshGroup starts empty', '    if ($false) {\n        Say "$SshGroup starts empty')
row(script_problems(old) != [], "MUTANT: a script whose seed is not behind -FirstInstall is caught")
old2 = re.sub(r'\n    if \(\$FirstInstall\) \{\n        Say "\$SshGroup starts empty[^\n]*\n    \} elseif', "\n    if", st)
row(script_problems(old2) != [], "MUTANT: the script with no FirstInstall arm before the seed is caught")
mut = it.replace("    Args := Args + ' -FirstInstall';", "    Args := Args;")
row(iss_problems(mut) != [], "MUTANT: an sd.iss that lost the flag is caught")
m3 = st.replace("foreach ($g in $existed) { Clear-Group $g }", "")
row(reset_problems(m3) != [], "MUTANT (393): a FirstInstall arm that empties nothing is caught")
m4 = st.replace("    if (-not $script:GroupCreated) { $existed += $AiGroup }\n", "")
row(reset_problems(m4) != [], "MUTANT (393): a group left out of the reset (sdaiusers) is caught")
m5 = st.replace("$g.psbase.Invoke('Remove', $p)", "$null = $p")
row(reset_problems(m5) != [], "MUTANT (393): a Clear-Group that removes nobody is caught")
row(all(m != st for m in (old, old2, m3, m4, m5)) and mut != it,
    "CONTROL: each mutant changed its copy (the anchors were found in the live files)")

print("test-sshseed-units: %d passed, %d failed" % (passes, fails))
sys.exit(1 if fails else 0)
