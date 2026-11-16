"""test-removesdaccounts-units.py - what a full uninstall's account sweep (remove-sdaccounts.ps1) must remove, read off the source.

WHY IT EXISTS.  Three fixes of 15 Nov 2026 found by the VM round 2 uninstalls had no guard:
  RELEASE_1.1 319  the kept installing administrator's own group sdu_<Keep> was the one SD object left;
  RELEASE_1.1 322  the groups of GROUP accounts (sdg_<name>, no Windows user) were never reached; the owner: "uninstall should
                   probably remove everything if asked to remove accounts";
  RELEASE_1.1 323  a profile whose hive was loaded was left, and "It goes at the next restart" was not true after an uninstall
                   (the SD service whose sweep does that is removed by the same uninstall).

WHAT IT CHECKS (R rows) and how it was proved: each row is a text test of the script; --selftest makes one mutant per property in a
copy held in memory and the row must go red.  The live file is never written.  Free: no SD, no elevation.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "remove-sdaccounts.ps1")


def fn_body(t, name):
    i = t.find("function " + name)
    if i < 0:
        return ""
    depth, j, started = 0, t.find("{", i), False
    while 0 <= j < len(t):
        if t[j] == "{":
            depth += 1
            started = True
        elif t[j] == "}":
            depth -= 1
            if started and depth == 0:
                return t[i:j + 1]
        j += 1
    return ""


def checks(t):
    rows = []
    rows.append(("R1 (319)", "after the removals the kept account's own group sdu_<Keep> is removed, and only that group of the kept account",
                 "$keptGroup = 'sdu_' + $Keep" in t and "Remove-LocalGroup -Name $keptGroup -ErrorAction Stop" in t))
    sweep = t[t.find("$sdGroups = @(Get-LocalGroup"):]
    rows.append(("R2 (322)", "every group named sdu_* or sdg_* WITH the description os_group gives ('SD account group') is removed after the accounts; "
                 "both conditions, so somebody else's sd-like group stays; a failure is counted as left",
                 "($_.Name -like 'sdu_*' -or $_.Name -like 'sdg_*') -and $_.Description -eq 'SD account group'" in sweep
                 and "Remove-LocalGroup -Name $g.Name -ErrorAction Stop" in sweep and "$null = $left.Add('group ' + $g.Name)" in sweep
                 and 0 < t.find("$keptGroup = 'sdu_' + $Keep") < t.find("$sdGroups = @(Get-LocalGroup")))
    rows.append(("R3 (322)", "the report-only run lists the same SD account groups", "$grpNow = @(Get-LocalGroup" in t
                 and t.count("($_.Name -like 'sdu_*' -or $_.Name -like 'sdg_*') -and $_.Description -eq 'SD account group'") == 2))
    fb = fn_body(t, "Register-ProfileReclaim")
    rows.append(("R4 (323)", "a profile Windows will not remove now is queued: Register-ProfileReclaim is called in that catch and its one line is said",
                 "Say ('            ' + (Register-ProfileReclaim $sid $path))" in t and t.find("Register-ProfileReclaim $sid $path") > t.find("profile LEFT BEHIND")))
    rows.append(("R5 (323)", "the task: only a local account's SID (S-1-5-21 and four parts), SYSTEM, at startup, highest, the command encoded; it removes the "
                 "profile only when NOT loaded and deletes itself only then (a still-loaded one keeps it for the next boot)",
                 "if ($sid -notmatch '^S-1-5-21(-\\d+){4}$')" in fb and "New-ScheduledTaskTrigger -AtStartup" in fb
                 and "New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest" in fb and "-EncodedCommand " in fb
                 and "if ($p -and -not $p.Loaded) { Remove-CimInstance -InputObject $p }" in fb
                 and "if (-not $p -or -not $p.Loaded) { Unregister-ScheduledTask" in fb))
    rows.append(("R6 (323)", "Register-ProfileReclaim prints nothing (it only returns its line: the folded-output trap) and says it was NOT queued when it fails",
                 bool(fb) and not re.search(r"\b(Say|Write-Output|Write-Host)\b", fb) and "It was NOT queued for removal" in fb
                 and "It goes at the next restart (task" in fb))
    return rows


MUTANTS = [
    ("the kept group stays", "R1 (319)", "Remove-LocalGroup -Name $keptGroup -ErrorAction Stop", "Write-Verbose $keptGroup"),
    ("any sd-like group is removed", "R2 (322)", "-and $_.Description -eq 'SD account group' })\nif", "})\nif"),
    ("sdg_ groups are not swept", "R2 (322)", "($_.Name -like 'sdu_*' -or $_.Name -like 'sdg_*') -and $_.Description -eq 'SD account group' })\nif ($sdGroups",
     "($_.Name -like 'sdu_*') -and $_.Description -eq 'SD account group' })\nif ($sdGroups"),
    ("the report does not list the groups", "R3 (322)", "$grpNow = @(Get-LocalGroup", "$grpNow = @(@()"),
    ("a left-behind profile is not queued", "R4 (323)", "                Say ('            ' + (Register-ProfileReclaim $sid $path))\n", ""),
    ("any SID is put in the task", "R5 (323)", "if ($sid -notmatch '^S-1-5-21(-\\d+){4}$')", "if ($false)"),
    ("a loaded profile is removed", "R5 (323)", "if ($p -and -not $p.Loaded) { Remove-CimInstance -InputObject $p }", "if ($p) { Remove-CimInstance -InputObject $p }"),
    ("the task runs at logon instead", "R5 (323)", "New-ScheduledTaskTrigger -AtStartup", "New-ScheduledTaskTrigger -AtLogOn"),
    ("the function prints", "R6 (323)", "    $name = 'SD profile cleanup ' + $sid\n", "    $name = 'SD profile cleanup ' + $sid\n    Say $name\n"),
]


def run(t, quiet=False):
    bad = 0
    for rid, what, ok in checks(t):
        if not ok:
            bad += 1
        if not quiet:
            print("  [%s] %s %s" % ("PASS" if ok else "FAIL", rid, what))
    return bad


def main():
    print("test-removesdaccounts-units: %s" % SRC)
    if not os.path.isfile(SRC):
        print("NO TREE: no %s" % SRC)
        return 2
    t = open(SRC, encoding="utf-8-sig").read().replace("\r\n", "\n")
    if "--selftest" in sys.argv[1:]:
        if run(t, True):
            print("selftest: the live file already fails; fix that first")
            return 1
        missed = 0
        for name, rid, old, new in MUTANTS:
            if t.count(old) != 1:
                print("  [CANNOT] %s: the text occurs %d times" % (name, t.count(old)))
                missed += 1
                continue
            m = t.replace(old, new)
            failed = [r for r, _, ok in checks(m) if not ok]
            hit = rid in failed
            if not hit:
                missed += 1
            print("  [%s] %s is caught by %s (failed: %s)" % ("pass" if hit else "MISS", name, rid, ", ".join(failed) or "none"))
        print("selftest: %d mutants, %d not caught" % (len(MUTANTS), missed))
        return 1 if missed else 0
    bad = run(t)
    print("test-removesdaccounts-units: %d passed, %d failed" % (len(checks(t)) - bad, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
