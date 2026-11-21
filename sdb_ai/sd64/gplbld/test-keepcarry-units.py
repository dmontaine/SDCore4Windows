#!/usr/bin/env python3
# test-keepcarry-units.py - free guard for what an uninstall that KEEPS the data leaves for the reinstall (sd.iss, sd-jobs.ps1).
#
# 21 Nov 26 - RELEASE_1.1 368, 369 (the three-layer audit's layer B, Linux's cells S5, S6, S13 and R3: "settings do not change after
# delete and install if the user chooses keep data").  Pinned here, from the text of sd.iss and sd-jobs.ps1:
#   G  the six gate groups (sdssh, sdapi, sdfiles, sdfileswrite, sdfilesadmin, sdaiusers) are NOT removed by RemoveSdGroups, which keeps
#      sdsshonly only (its deny rights are why: owner 2 Sep 2026); RemoveRouteGroups removes them, never on a silent uninstall, and is
#      called in exactly three places - after the accounts sweep removed the accounts, where no data tree is left, and with the
#      database deleted - so a Keep with the accounts kept keeps them, and the reinstall (sync-route-groups.ps1 seeds only a group it made)
#      changes nobody's access.
#   J  the uninstaller runs job-unschedule, not job-purge (the tasks go, the definitions stay in the kept tree); job-unschedule never
#      touches the definitions; KeptJobCount counts only plain files that are not radmin- or dot names.
#   R  the uninstall notes that remote administration was on (SaveRadminNote: only the word on, HKLM64 beside the API's note) BEFORE
#      RemoveRemoteAdmin takes the state file; the note is cleared when no database survives and spent by the reinstall whatever it said.
#   M  the closing page says what the reinstall found: the groups kept or recreated, the jobs kept and not scheduled, remote administration
#      off and once on - and nothing about any of it on an upgrade, where no uninstall ran.
#
# Free: reads two files.  --selftest breaks a copy of the text in memory, one thing at a time, and each break must turn a named row red;
# the live files are not written (their SHA-256 is printed before and after).
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ISS = os.path.join(HERE, "sd.iss")
JOBS = os.path.join(HERE, "sd-jobs.ps1")


def read(p):
    with open(p, encoding="utf-8", errors="replace", newline="") as f:
        return f.read().replace("\r\n", "\n")


def code_only(s):
    """sd.iss less its comments: (* *) blocks and { text } ones; an Inno constant such as {app} has no space after the brace, so it stays."""
    s = re.sub(r"\(\*.*?\*\)", "", s, flags=re.S)
    return re.sub(r"\{\s[^}]*\}", "", s)


def proc(code, name):
    """The text of a procedure or function, from its header to the first line that is exactly 'end;'."""
    m = re.search(r"^(?:procedure|function) " + re.escape(name) + r"\b[^\n]*\n", code, re.M)
    if not m:
        return ""
    j = code.find("\nend;", m.end())
    return code[m.start(): j + 5] if j > 0 else code[m.start():]


def in_order(text, *needles):
    pos = -1
    for n in needles:
        i = text.find(n, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


SIX = ["sdssh", "sdapi", "sdfiles", "sdfileswrite", "sdfilesadmin", "sdaiusers"]


def rows_for(iss_raw, jobs_raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    code = code_only(iss_raw)
    jobs = jobs_raw

    # ---- the null case: the pieces are really there ---------------------------------------------------------------------------
    names = ["RemoveSdGroups", "RemoveRouteGroups", "OfferAccountRemoval", "CurUninstallStepChanged", "RemoveScheduledJobs",
             "SaveRadminNote", "RadminNoteClear", "RadminNoteSaysOn", "KeptJobCount", "InitializeSetup"]
    missing = [n for n in names if proc(code, n) == ""]
    ck("N0", "sd.iss holds every procedure this guard reads (a guard that read nothing would pass)", not missing and len(code) > 100000, "missing: %s" % missing)

    rsg = proc(code, "RemoveSdGroups")
    rrg = proc(code, "RemoveRouteGroups")
    oar = proc(code, "OfferAccountRemoval")
    cus = proc(code, "CurUninstallStepChanged")
    rsj = proc(code, "RemoveScheduledJobs")
    srn = proc(code, "SaveRadminNote")
    kjc = proc(code, "KeptJobCount")
    isetup = proc(code, "InitializeSetup")

    # ---- G -------------------------------------------------------------------------------------------------------------------------
    ck("G1", "RemoveSdGroups removes sdsshonly and none of the six gate groups, after its silent-uninstall exit",
       in_order(rsg, "if UninstallSilent then", "Exit;", "localgroup sdsshonly /delete")
       and not any(("localgroup %s /delete" % g) in rsg for g in SIX), "")
    ck("G2", "RemoveRouteGroups removes the six gate groups once each in the whole file, and none of sdsshonly or sdusers, after a silent-uninstall exit",
       in_order(rrg, "if UninstallSilent then", "Exit;", *["localgroup %s /delete" % g for g in SIX])
       and all(code.count("'localgroup %s /delete'" % g) == 1 for g in SIX)
       and "sdsshonly" not in rrg and "sdusers" not in rrg, "")
    calls = [m.start() for m in re.finditer(r"^\s*RemoveRouteGroups;", code, re.M)]
    ck("G3", "RemoveRouteGroups is called in exactly three places", len(calls) == 3, "%d calls" % len(calls))
    ck("G4", "...once in OfferAccountRemoval, only when the accounts sweep returned 0 (the accounts, and so their memberships, are gone)",
       re.search(r"if Code = 0 then\s*\n\s*RemoveRouteGroups;", oar) is not None and oar.count("RemoveRouteGroups;") == 1, "")
    tg = cus[cus.find("if not DirExists(DataPath) then"): cus.find("Exit;", cus.find("if not DirExists(DataPath) then") + 40)] if "if not DirExists(DataPath) then" in cus else ""
    ck("G5", "...once where no data tree is left, after the accounts question and before sdusers goes",
       in_order(tg, "OfferAccountRemoval;", "RemoveRouteGroups;", "RemoveSdUsersGroup;"), "")
    ck("G6", "...and once with the database deleted, together with sdusers, after the accounts question",
       re.search(r"if UsersGroupGoes then\s*\n\s*begin\s*\n\s*RemoveRouteGroups;\s*\n\s*RemoveSdUsersGroup;", cus) is not None
       and in_order(cus, "OfferAccountRemoval;", "if UsersGroupGoes then"), "")
    ck("G7", "a Keep with the accounts kept calls none of them: RemoveSdGroups is the only route-group call outside those three and it takes sdsshonly alone",
       cus.count("RemoveSdGroups;") == 1 and "RemoveRouteGroups;" not in cus[:cus.find("if not DirExists(DataPath) then")], "")

    # ---- J -------------------------------------------------------------------------------------------------------------------------
    ck("J1", "RemoveScheduledJobs runs the helper's job-unschedule, not job-purge", "job-unschedule" in rsj and "job-purge" not in rsj, "")
    ck("J2", "sd-jobs.ps1: job-unschedule is spared the SDSYS test with job-purge, takes the tasks and leaves the definitions (keepDefs)",
       "if ($Action -cne 'job-purge' -and $Action -cne 'job-unschedule') {" in jobs
       and "$keepDefs = ($Action -ceq 'job-unschedule')" in jobs
       and "if ((-not $keepDefs) -and (Test-Path -LiteralPath $jobsDir)) {" in jobs
       and "the scheduled tasks are removed; the definitions are kept" in jobs, "")
    ck("J3", "KeptJobCount counts plain files only, not radmin- ones and not dot names (the helper's .new temporary)",
       "FILE_ATTRIBUTE_DIRECTORY) = 0" in kjc and "'radmin-'" in kjc and "Copy(FR.Name, 1, 7)" in kjc and "Copy(FR.Name, 1, 1) <> '.'" in kjc
       and "'{#DataDir}\\sd-jobs\\'" in kjc, "")

    # ---- R -------------------------------------------------------------------------------------------------------------------------
    ck("R1", "SaveRadminNote notes remote administration only when the state file says on, in HKLM64 beside the API's note, and clears the note otherwise",
       "'{#DataDir}\\remote-admin\\state'" in srn and "Trim(String(S)) = 'on'" in srn
       and "RegWriteStringValue(HKLM64, ApiNoteKey, 'RemoteAdmin', 'on')" in srn and "RadminNoteClear" in srn
       and "RegDeleteValue(HKLM64, ApiNoteKey, 'RemoteAdmin')" in proc(code, "RadminNoteClear")
       and "(V = 'on')" in proc(code, "RadminNoteSaysOn"), "")
    first = cus[:cus.find("Exit;")] if "Exit;" in cus else cus
    ck("R2", "at usUninstall the note is written after the jobs' tasks go and BEFORE RemoveRemoteAdmin takes the state file",
       in_order(first, "RemoveScheduledJobs;", "SaveRadminNote;", "RemoveRemoteAdmin;"), "")
    ck("R3", "the note is cleared where no database survives: the tree-gone path and the database-deleted path",
       "RadminNoteClear;" in tg and re.search(r"RemoveSdUsersGroup;\s*\n\s*RadminNoteClear;", cus[cus.find("if UsersGroupGoes then"):]) is not None, "")

    # ---- M -------------------------------------------------------------------------------------------------------------------------
    ck("M1", "Setup samples whether sdssh existed before any file was written (net localgroup sdssh, exit 0), next to DataTreeWasAbsent",
       in_order(isetup, "DataTreeWasAbsent :=", "RouteGroupsKept := Exec(ExpandConstant('{sys}\\net.exe'), 'localgroup sdssh'", "(GroupCode = 0)", "DataTreeBeforeHome :="), "")
    ck("M2", "the kept-database box says the groups were kept, or recreated, by what Setup found",
       code.count("if RouteGroupsKept then") == 2 and "Your database was kept, and so were its Windows groups:" in code
       and "Your database was kept, but its Windows groups were recreated:" in code
       and "ssh, API, files and AI access are as they were." in code
       and "API access is NOT restored." in code, "")
    ck("M3", "the jobs and remote administration warnings are built only when this was not an upgrade; the note is spent whatever it said",
       re.search(r"KeptMsg := '';\s*\n\s*KeptCount := 0;\s*\n\s*RestoredMsg := '';\s*\n\s*if not TrueUpgrade then\s*\n\s*begin\s*\n\s*KeptJobs := KeptJobCount;", code) is not None
       and "SCHEDULED JOB(S) WERE KEPT, BUT THIS INSTALLER COULD NOT " in code
       and "REMOTE ADMINISTRATION IS OFF. It was on before the uninstall," in code
       and re.search(r"end;\s*\n\s*RadminNoteClear;", code) is not None, "")
    ck("M4", "KeptMsg reaches the closing page through WarnReport, and is no longer part of FinishReport",
       "WarnReport := WarnReport + MarkWarn(KeptMsg);" in code
       and "AccessMsg +\n             RestoredMsg +\n             'SD Core''s own system files were replaced.'" in code, "")
    # ---- W: the owner's rule (chat, 21 Nov 26): "If there are warnings they should not be buried in other text.  They need to be explicit,
    # stand out so that they can not be missed." -------------------------------------------------------------------------------------
    srep = proc(code, "ShowFinishedReport")
    ck("W1", "the Finished page draws WarnReport FIRST, directly under 'SD Core is installed.' and above the sign-out line",
       in_order(code, "ShowFinishedReport('SD Core is installed.' + #13#10#13#10 +", "WarnReport +", "'You must sign out or restart before using SD Core.'"), "")
    ck("W2", "a paragraph that starts with !! is drawn bold and red, with the font set before the caption so the height is measured bold",
       "if Copy(Chunk, 1, 2) = '!!' then" in srep and "Para[N].Font.Style := [fsBold];" in srep and "Para[N].Font.Color := clRed;" in srep
       and srep.find("Para[N].Font.Color := clRed;") < srep.find("Para[N].Caption := Chunk;"), "")
    ck("W3", "the marks are taken out of what goes to the log and the scrolling memo (whose text keeps the warning's capital letters)",
       "StringChange(Plain, '!!', '');" in srep and "Plain + #13#10#13#10, True);" in srep and "Memo.Text := Plain;" in srep and "Memo.Text := Msg;" not in srep, "")
    mw = proc(code, "MarkWarn")
    ck("W4", "MarkWarn marks every non-empty paragraph of its text",
       "Result := Result + '!!' + Chunk + #13#10#13#10;" in mw and "if Trim(Chunk) <> '' then" in mw, "")
    ck("W5", "the groups-recreated and the missing-firewall-rule warnings go to WarnReport too, marked, and not to FinishReport",
       "WarnReport := WarnReport + MarkWarn('WARNING: THE WINDOWS GROUPS THAT SAY WHO MAY USE ssh" in code
       and "SetLength(AccessMsg, 0);" in code
       and "WarnReport := WarnReport + MarkWarn('WARNING: NO FIREWALL RULE LETS OTHER COMPUTERS REACH THE SD CORE API." in code
       and "ApiRuleMsg := #13#10#13#10" not in code, "")
    ck("W6", "the warning block opens with a heading in capitals that says the settings are not on and that these are the steps",
       "'WARNING: SETTINGS YOU HAD BEFORE THE UNINSTALL ARE NOT ON NOW, AND THIS INSTALLER COULD NOT TURN THEM ON AGAIN. '" in code and "'DO THESE STEPS:'" in code, "")
    # ---- S: the owner's rule (chat, 21 Nov 26): what cannot be put back is warned about during the install WITH THE EXACT STEPS -------
    ck("S1", "the jobs line and the remote administration line each give the steps (sign in to Windows as SDSYS, start SD Core, type), the jobs' lines from KeptJobSteps and the other the command remote.sdsys on",
       code.count("sign in to Windows as SDSYS, start SD Core and type:") == 2 and "+ KeptJobSteps + #13#10#13#10;" in code
       and "'    remote.sdsys on' + #13#10#13#10;" in code, "")
    sjw = proc(code, "SafeJobWord")
    kjs = proc(code, "KeptJobSteps")
    ck("S2", "SafeJobWord lets through only lower case letters, digits and a hyphen, and with Extra a space, a colon and a full stop",
       "(C >= 'a') and (C <= 'z')" in sjw and "(C >= '0') and (C <= '9')" in sjw and "(C = '-')" in sjw
       and "(Extra and ((C = ' ') or (C = ':') or (C = '.')))" in sjw and "Length(S) <= 40" in sjw, "")
    ck("S3", "KeptJobSteps prints set.job change NAME JOB SCHEDULE only for a plain name, the job backup-all or update-accounts and a plain schedule; anything else is named as damaged, never echoed from the file",
       "if SafeJobWord(Name, False) and ((JobId = 'backup-all') or (JobId = 'update-accounts')) and SafeJobWord(Sched, True) then" in kjs
       and "'    set.job change ' + Name + ' ' + JobId + ' ' + Sched" in kjs
       and "its definition is damaged" in kjs and "Copy(Line, 1, 4) = 'job='" in kjs and "Copy(Line, 1, 9) = 'schedule='" in kjs
       and "FILE_ATTRIBUTE_DIRECTORY) = 0" in kjs and "'radmin-'" in kjs, "")
    return rows


MUTANTS = [
    # (name, file, old, new, row that must go red)
    ("RemoveSdGroups takes sdssh again", "iss", "  Exec(Net, 'localgroup sdsshonly /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);\nend;",
     "  Exec(Net, 'localgroup sdsshonly /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);\n  Exec(Net, 'localgroup sdssh /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);\nend;", "G1"),
    ("RemoveRouteGroups loses its silent exit", "iss", "begin\n  if UninstallSilent then\n    Exit;\n\n  Net := ExpandConstant('{sys}\\net.exe');\n  Exec(Net, 'localgroup sdssh /delete',",
     "begin\n  Net := ExpandConstant('{sys}\\net.exe');\n  Exec(Net, 'localgroup sdssh /delete',", "G2"),
    ("a fourth call of RemoveRouteGroups", "iss", "  RecordDatabaseChoice(DataPath, DbDelete, DbFailed, ConfDelete, ConfFailed);\n",
     "  RecordDatabaseChoice(DataPath, DbDelete, DbFailed, ConfDelete, ConfFailed);\n  RemoveRouteGroups;\n", "G3"),
    ("the sweep's removal no longer waits for Code = 0", "iss", "  if Code = 0 then\n    RemoveRouteGroups;", "  RemoveRouteGroups;", "G4"),
    ("the tree-gone call moves before the accounts question", "iss", "      OfferAccountRemoval;\n    RemoveRouteGroups;", "      RemoveRouteGroups;\n    OfferAccountRemoval;", "G5"),
    ("the delete path forgets RemoveRouteGroups", "iss", "    RemoveRouteGroups;\n    RemoveSdUsersGroup;\n    RadminNoteClear;", "    RemoveSdUsersGroup;\n    RadminNoteClear;", "G6"),
    ("the uninstaller purges the jobs again", "iss", "Script + '\" job-unschedule'", "Script + '\" job-purge'", "J1"),
    ("job-unschedule takes the definitions", "jobs", "if ((-not $keepDefs) -and (Test-Path -LiteralPath $jobsDir)) {", "if (Test-Path -LiteralPath $jobsDir) {", "J2"),
    ("KeptJobCount counts directories", "iss", "if ((FR.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0) and\n           (Copy(FR.Name, 1, 7) <> 'radmin-')", "if (True) and\n           (Copy(FR.Name, 1, 7) <> 'radmin-')", "J3"),
    ("the note is written whatever the state says", "iss", "and (Trim(String(S)) = 'on') then", "then", "R1"),
    ("the note is written after RemoveRemoteAdmin", "iss", "    SaveRadminNote;   { 21 Nov 26 - RELEASE_1.1 369(a): BEFORE RemoveRemoteAdmin, which takes the state file away }\n    RemoveRemoteAdmin;",
     "    RemoveRemoteAdmin;\n    SaveRadminNote;", "R2"),
    ("the tree-gone path keeps the note", "iss", "    RadminNoteClear;   { 21 Nov 26 - RELEASE_1.1 369(a): nor the accounts remote administration concerned }\n", "", "R3"),
    ("Setup stops sampling the group", "iss", "RouteGroupsKept := Exec(", "RouteGroupsKept := not Exec(", "M1"),
    ("the box claims recreation whatever Setup found", "iss", "        if RouteGroupsKept then\n          AccessMsg :=\n            'Your database was kept, and so were its Windows groups:' + #13#10#13#10\n        else\n",
     "        if False then\n          AccessMsg :=\n            'Your database was kept, and so were its Windows groups:' + #13#10#13#10\n        else\n", "M2"),
    ("the jobs line is built on an upgrade too", "iss", "RestoredMsg := '';\n      if not TrueUpgrade then\n      begin\n        KeptJobs := KeptJobCount;", "RestoredMsg := '';\n      if True then\n      begin\n        KeptJobs := KeptJobCount;", "M3"),
    ("KeptMsg is dropped from the page", "iss", "WarnReport := WarnReport + MarkWarn(KeptMsg);", "", "M4"),
    ("the remote administration warning loses its command", "iss", "'    remote.sdsys on' + #13#10#13#10;", "'' + #13#10#13#10;", "S1"),
    ("the jobs warning loses its steps", "iss", "#13#10#13#10 + KeptJobSteps + #13#10#13#10;", "#13#10#13#10 + #13#10#13#10;", "S1"),
    ("the warnings are drawn after the sign-out line", "iss", "      WarnReport +\n      'You must sign out or restart before using SD Core.' + #13#10#13#10 +", "      'You must sign out or restart before using SD Core.' + #13#10#13#10 +\n      WarnReport +", "W1"),
    ("a warning paragraph is no longer red", "iss", "      Para[N].Font.Color := clRed;\n", "", "W2"),
    ("the scrolling memo shows the marks", "iss", "Memo.Text := Plain;", "Memo.Text := Msg;", "W3"),
    ("MarkWarn marks nothing", "iss", "Result := Result + '!!' + Chunk + #13#10#13#10;", "Result := Result + Chunk + #13#10#13#10;", "W4"),
    ("the missing-firewall-rule warning goes back into the text", "iss", "WarnReport := WarnReport + MarkWarn('WARNING: NO FIREWALL RULE LETS OTHER COMPUTERS REACH THE SD CORE API.", "ApiRuleMsg := #13#10#13#10 + ('WARNING: NO FIREWALL RULE LETS OTHER COMPUTERS REACH THE SD CORE API.", "W5"),
    ("the warning block loses its heading", "iss", "'DO THESE STEPS:'", "'THESE:'", "W6"),
    ("SafeJobWord lets capitals through", "iss", "if not (((C >= 'a') and (C <= 'z')) or", "if not (((C >= 'A') and (C <= 'z')) or", "S2"),
    ("KeptJobSteps trusts any job id", "iss", "and ((JobId = 'backup-all') or (JobId = 'update-accounts')) and SafeJobWord(Sched, True) then", "and SafeJobWord(Sched, True) then", "S3"),
]


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def selftest():
    iss, jobs = read(ISS), read(JOBS)
    before = (sha(ISS), sha(JOBS))
    print("live files, SHA-256 before: sd.iss %s  sd-jobs.ps1 %s" % (before[0][:12], before[1][:12]))
    base = rows_for(iss, jobs)
    bad = [r[0] for r in base if not r[2]]
    ok = not bad
    print("  [%s] control: the unbroken text passes every row%s" % ("PASS" if ok else "FAIL", "" if ok else " - red: %s" % bad))
    for name, which, old, new, row in MUTANTS:
        src = iss if which == "iss" else jobs
        n = src.count(old)
        if n != 1:
            print("  [FAIL] mutant '%s': its anchor text occurs %d times (needs exactly 1)" % (name, n))
            ok = False
            continue
        m_iss, m_jobs = (iss.replace(old, new), jobs) if which == "iss" else (iss, jobs.replace(old, new))
        red = [r[0] for r in rows_for(m_iss, m_jobs) if not r[2]]
        hit = row in red
        print("  [%s] mutant '%s' turns %s red%s" % ("PASS" if hit else "FAIL", name, row, "" if hit else " (red rows: %s)" % red))
        ok = ok and hit
    after = (sha(ISS), sha(JOBS))
    same = before == after
    print("  [%s] the live files are unchanged (SHA-256 after: %s %s)" % ("PASS" if same else "FAIL", after[0][:12], after[1][:12]))
    print("test-keepcarry-units --selftest: %s (%d mutants)" % ("PASSED" if ok and same else "FAILED", len(MUTANTS)))
    return 0 if ok and same else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    for p in (ISS, JOBS):
        if not os.path.isfile(p):
            print("test-keepcarry-units: NO TREE - %s is not here" % p)
            return 2
    rows = rows_for(read(ISS), read(JOBS))
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "  <- " + detail))
        bad += 0 if ok else 1
    if len(rows) < 15:
        print("test-keepcarry-units: FAILED - only %d rows (the null case)" % len(rows))
        return 1
    print("test-keepcarry-units: %d rows, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
