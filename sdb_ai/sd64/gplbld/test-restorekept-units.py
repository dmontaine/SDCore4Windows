#!/usr/bin/env python3
# test-restorekept-units.py - free guard for "put back, AS SDSYS, what a Keep uninstall took away" (RELEASE_1.1 370).
#
# 21 Nov 26.  The owner: a Keep must put the system back exactly as it was ("Yes, build it" to an installer helper that does it as SDSYS).
# MEASURED on a VM that day (probe-sdsys-taskreg.ps1): an administrator and SYSTEM are refused registering a task that runs as SDSYS, but a SYSTEM
# task that mints SDSYS's S4U token registers it.  The pieces, all pinned here:
#   C  gplsrc/sdsvc/sdrestore.c (in sdsvc.exe, "sdsvc.exe -restore-kept"): selected only by that one argument; refuses unless LocalSystem; the result
#      folder must be a real folder owned by Administrators or SYSTEM and the result file is created with CREATE_NEW and inherited; the child is
#      FIXED (the system's powershell on the script beside the exe), nothing from an argument or the environment reaches it; ELEVATED or nothing; in
#      a job that ends with this process; ended after 180 s; the last line "sdrestore: child exit N" only when it ran to its end.
#   S  sd-restore-kept.ps1 (runs as SDSYS): refuses anyone else; jobs go to sd-jobs.ps1 job-list then job-set, judged on the helper's own success
#      wording; remote administration only from a note in Registry64 that only SYSTEM, Administrators and TrustedInstaller can write, equal to
#      "on", deleted whatever it said, then remote-admin.ps1 -On judged on "remote-admin: open".  Run for real on fixtures with -DryRun.
#   R  run-restore-kept.ps1 (the installer's, elevated): an administrators-only folder, ONE SYSTEM task running sdsvc.exe -restore-kept, removed after.
#   P  sd.iss RunRestoreKept and what it does with the answer: only what did NOT come back is warned about (red block), with the reason and the exact
#      steps; what did is one plain line; no result counts as nothing restored; the note is read BEFORE it is spent.
#
# Free: reads files and runs the script's dry run on scratch fixtures; touches nothing of SD.  --selftest breaks copies in memory (and a scratch
# copy of the script for the dry-run rows) and each break must turn a named row red; the live files are not written (SHA-256 shown).
import hashlib
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.dirname(HERE)
FILES = {
    "c": os.path.join(SD, "gplsrc", "sdsvc", "sdrestore.c"),
    "svc": os.path.join(SD, "gplsrc", "sdsvc", "sdsvc.c"),
    "make": os.path.join(SD, "Makefile"),
    "sk": os.path.join(HERE, "sd-restore-kept.ps1"),
    "rk": os.path.join(HERE, "run-restore-kept.ps1"),
    "iss": os.path.join(HERE, "sd.iss"),
    "stage": os.path.join(HERE, "stage.py"),
}


def read(p):
    with open(p, encoding="utf-8", errors="replace", newline="") as f:
        return f.read().replace("\r\n", "\n")


def strip_c(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def code_iss(s):
    s = re.sub(r"\(\*.*?\*\)", "", s, flags=re.S)
    return re.sub(r"\{\s[^}]*\}", "", s)


def in_order(text, *needles):
    pos = -1
    for n in needles:
        i = text.find(n, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def between(t, a, b):
    i = t.find(a)
    if i < 0:
        return ""
    j = t.find(b, i + len(a))
    return t[i:j] if j > i else t[i:]


def powershell(args, timeout=60):
    p = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass"] + args, capture_output=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace").replace("\r\n", "\n")


LIST = [
    "sd-jobs: job-list: the definitions in C:/ProgramData/SD/sd-jobs",
    "job nightly: daily 03:00: backup.account all (backup-all)",
    "job hourly-upd: every 15 minutes: update.accounts all (update-accounts)",
    "damaged oddone: damaged",
    "job weekly1: weekly sun 03:00: backup.account all (backup-all)",
    "job evil: daily 03:00: rm -rf (backup-all; calc)",
]


def dry(script_text, state, lines=LIST):
    with tempfile.TemporaryDirectory() as d:
        sp = os.path.join(d, "sd-restore-kept.ps1")
        lp = os.path.join(d, "list.txt")
        with open(sp, "w", encoding="ascii", newline="\n") as f:
            f.write(script_text)
        with open(lp, "w", encoding="ascii", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        rc, out = powershell(["-File", sp, "-DryRun", "-ListFile", lp, "-NoteState", state])
    return rc, out


def noteacl(script_text):
    """Test-NoteWriters on fixtures: Users with SetValue is untrusted; Administrators/SYSTEM full and Users read are trusted."""
    blk = between(script_text, "# BEGIN restore_functions", "# END restore_functions")
    body = blk + r"""
function New-Rule($who, $rights) { [pscustomobject]@{ IdentityReference = (New-Object Security.Principal.NTAccount($who)); RegistryRights = [Security.AccessControl.RegistryRights]$rights; AccessControlType = 'Allow' } }
$t1 = Test-NoteWriters @((New-Rule 'BUILTIN\Administrators' 'FullControl'), (New-Rule 'NT AUTHORITY\SYSTEM' 'FullControl'), (New-Rule 'BUILTIN\Users' 'ReadKey'))
$t2 = Test-NoteWriters @((New-Rule 'BUILTIN\Administrators' 'FullControl'), (New-Rule 'BUILTIN\Users' 'SetValue'))
$t3 = Test-NoteWriters @((New-Rule 'BUILTIN\Administrators' 'FullControl'), (New-Rule 'NT AUTHORITY\Authenticated Users' 'WriteKey'))
[Console]::Out.WriteLine('T1 ' + $t1.Trusted + ' T2 ' + $t2.Trusted + ' T3 ' + $t3.Trusted)
"""
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "t.ps1")
        with open(p, "w", encoding="ascii", newline="\n") as f:
            f.write(body)
        rc, out = powershell(["-File", p])
    return out.strip()


def rows_for(t):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    c = strip_c(t["c"])
    svc = strip_c(t["svc"])
    sk = t["sk"]
    rk = t["rk"]
    iss = code_iss(t["iss"])

    ck("N0", "every file this guard reads is there and not empty (a guard that read nothing would pass)",
       all(len(v) > 500 for v in t.values()), "")

    # ---- C -------------------------------------------------------------------------------------------------------------------------------
    ck("C1", "sdsvc.exe selects the restore only for the one argument -restore-kept (argc == 2), before it connects to the service manager",
       in_order(svc, 'if (argc == 2 && strcmp(argv[1], "-restore-kept") == 0)', "return sdrestore_main();", "StartServiceCtrlDispatcherA(table)"), "")
    main = between(c, "int sdrestore_main(void) {", "done:")
    ck("C2", "it refuses unless it is LocalSystem, before it makes or opens anything",
       in_order(main, "if (!sr_is_system())", "return 2;", "sr_dir_trusted(", "CreateFileW(rfile") and "WinLocalSystemSid" in c, "")
    ck("C3", "the result folder must be a real folder owned by Administrators or SYSTEM, and the result file is created with CREATE_NEW and inherited",
       "FILE_ATTRIBUTE_REPARSE_POINT" in between(c, "static int sr_dir_trusted", "int sdrestore_main")
       and "OWNER_SECURITY_INFORMATION" in c and "WinBuiltinAdministratorsSid" in c
       and "CreateFileW(rfile, GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_NEW" in main and "sa.bInheritHandle = TRUE;" in main, "")
    ck("C4", "the child is FIXED: powershell from the system folder on sd-restore-kept.ps1 beside this program, as a plain file; no argv, no caller's text, only ProgramData read from the environment",
       "argv" not in c and c.count("GetEnvironmentVariableW") == 1 and 'L"ProgramData"' in c
       and 'L"%ls\\\\sd-restore-kept.ps1"' in c and r'WindowsPowerShell\\v1.0\\powershell.exe' in c
       and "FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT" in main
       and '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File' in c, "")
    ck("C8", "the script is found at ONE fixed place: the program folder two levels above sdsvc.exe (<program folder>\\usr\\bin), and a program anywhere else is refused",
       'L"\\\\usr\\\\bin"' in main and "_wcsicmp(appdir + len - tl, tail) != 0" in main and "this program is not in <program folder>" in main
       and in_order(main, "_wcsicmp(appdir + len - tl, tail)", "appdir[len - tl] = L'\\0';", 'swprintf(script, MAX_PATH, L"%ls\\\\sd-restore-kept.ps1", appdir);'), "")
    ck("C5", "SDSYS by S4U, made primary, and ELEVATED or nothing: the elevation test comes before the process is created",
       in_order(main, 'win32_s4u_logon(SR_ACCOUNT)', "DuplicateTokenEx(", "TokenElevation", "TokenIsElevated", "CreateProcessAsUserW"), "")
    ck("C6", "the child is in a job that ends with this process, is ended after 180 seconds, and the last line is written only when it finished",
       "JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE" in main and "#define SR_TIMEOUT_MS 180000" in c and "WaitForSingleObject(pi.hProcess, SR_TIMEOUT_MS)" in main
       and in_order(main, "ResumeThread(pi.hThread);", "WaitForSingleObject", 'sr_line(out, "sdrestore: child exit %lu"'), "")
    ck("C7", "the Makefile builds sdrestore.c into sdsvc.exe, and sdsvc.c includes its header",
       "$(SVCDIR)/sdrestore.c" in between(t["make"], "sdsvc:", "-o $(GPLBIN)sdsvc.exe") and '#include "sdrestore.h"' in t["svc"], "")

    # ---- S -------------------------------------------------------------------------------------------------------------------------------
    ck("S1", "sd-restore-kept.ps1 refuses anyone but the local SDSYS with an elevated token, before any helper is run",
       in_order(sk, "$me.User.Value -ne $sdsysSid", "RESTORE refused: this is not the local account SDSYS", "-not $elevated",
                "RESTORE refused: this session is not elevated", "job-list"), "")
    ck("S2", "jobs: job-list, then the same validating verb as set.job (job-set), judged on the helper's own wording and never on the name being in the output",
       in_order(sk, "job-list", "'job-set', $j.Name, $j.Job", "is scheduled: ") and "sd-jobs: job ' + [regex]::Escape($j.Name) + ' is scheduled: " in sk
       and "could not be registered" in sk, "")
    ck("S3", "remote administration: the note is read in Registry64, trusted only if only SYSTEM, Administrators and TrustedInstaller can write the key, must be exactly 'on', and is deleted whatever it said",
       "RegistryView]::Registry64" in sk and "Test-NoteWriters (" in sk and "[string]$v -ceq 'on'" in sk
       and in_order(sk, "-ceq 'on'", "remote-admin.ps1", "DeleteValue('RemoteAdmin', $false)") and "S-1-5-80-956008885" in sk, "")
    ck("S4", "remote administration is reopened by remote-admin.ps1 -On, judged on 'remote-admin: open' and exit 0; a failure says so and leaves it off",
       "-File $ra -On" in sk and "'^remote-admin: open'" in sk and "$code -eq 0" in sk and "RESTORE remote-admin: NOT opened - exit" in sk, "")

    # ---- R -------------------------------------------------------------------------------------------------------------------------------
    ck("R1", "run-restore-kept.ps1: elevated only, the folder made with a protected administrators-only ACL, ONE SYSTEM task running sdsvc.exe -restore-kept, removed after",
       in_order(rk, "not elevated", "SetAccessRuleProtection($true, $false)", "S-1-5-18", "S-1-5-32-544", "New-ScheduledTaskAction -Execute $svc -Argument '-restore-kept'",
                "NT AUTHORITY\\SYSTEM", "Start-ScheduledTask", "Unregister-ScheduledTask", "Remove-Item -LiteralPath $work") and "-RunLevel Highest" in rk
       and "$svc = Join-Path $AppDir 'usr\\bin\\sdsvc.exe'" in rk, "")
    ck("R2", "stage.py ships both scripts to the program folder", "'run-restore-kept.ps1', 'sd-restore-kept.ps1'," in t["stage"], "")

    # ---- D: the script run for real (dry run) on fixtures ----------------------------------------------------------------------------------
    rc, out = dry(sk, "on")
    ck("D1", "dry run, note on: each plain definition becomes a job-set with its job and schedule; a damaged one and a line that is not a job are NOT scheduled; the summary counts them",
       rc == 0 and "RESTORE would run: sd-jobs.ps1 job-set nightly backup-all daily 03:00" in out
       and "RESTORE would run: sd-jobs.ps1 job-set hourly-upd update-accounts every 15 minutes" in out
       and "RESTORE would run: sd-jobs.ps1 job-set weekly1 backup-all weekly sun 03:00" in out
       and "RESTORE job oddone: NOT scheduled again - its definition is damaged" in out
       and "RESTORE jobs: 3 scheduled again, 1 NOT." in out and "evil" not in out, out[-400:])
    ck("D2", "dry run, note on: remote administration is reopened; then done",
       "RESTORE would run: remote-admin.ps1 -On" in out and "RESTORE remote-admin: open" in out and out.rstrip().endswith("RESTORE done"), "")
    _, off = dry(sk, "off")
    _, unt = dry(sk, "untrusted")
    _, non = dry(sk, "none")
    ck("D3", "dry run, note off or none: nothing to restore for remote administration, and no remote-admin.ps1 is run",
       "RESTORE remote-admin: none to restore" in off and "remote-admin.ps1" not in off and "RESTORE remote-admin: none to restore." in non and "remote-admin.ps1" not in non, "")
    ck("D4", "dry run, an untrusted note: not used, said so, and no remote-admin.ps1 is run",
       "RESTORE remote-admin: NOT opened - the note is not trusted" in unt and "remote-admin.ps1" not in unt.replace("RESTORE remote-admin: NOT opened", ""), unt[-200:])
    _, empty = dry(sk, "on", lines=["sd-jobs: job-list: the definitions in x", "sd-jobs: no job is defined"])
    ck("D5", "dry run, no definitions: 'none to restore', never 'N scheduled again'", "RESTORE jobs: none to restore." in empty and "scheduled again," not in empty, "")
    ck("D6", "the note's writers test: Users with read only is trusted; Users with SetValue or Authenticated Users with WriteKey is not",
       noteacl(sk) == "T1 True T2 False T3 False", noteacl(sk))

    # ---- P -------------------------------------------------------------------------------------------------------------------------------
    run = between(iss, "function RunRestoreKept: String;", "\nend;")
    ck("P1", "the installer runs run-restore-kept.ps1 hidden, waits, captures its output to a file in Setup's temp folder and reads it back",
       "run-restore-kept.ps1" in run and "ewWaitUntilTerminated" in run and "restore-kept.txt" in run and "LoadStringFromFile(OutFile, S)" in run, "")
    blk = between(iss, "KeptMsg := '';\n      KeptCount := 0;", "RadminNoteClear;")
    ck("P2", "it captures the note BEFORE the restore (RadminWas) and spends it after; the restore runs only after a Keep and only if there was something to restore",
       in_order(blk, "if not TrueUpgrade then", "RadminWas := RadminNoteSaysOn;", "if (KeptJobs > 0) or RadminWas then", "RestoreText := RunRestoreKept;")
       and iss.count("RadminNoteClear;") >= 3, "")
    ck("P3", "a result counts only with 'sdrestore: child exit 0'; remote administration only with 'RESTORE remote-admin: open'; jobs only with at least one and none NOT",
       "RestoreRan := Pos('sdrestore: child exit 0', RestoreText) > 0;" in blk and "Pos('RESTORE remote-admin: open', RestoreText) > 0" in blk
       and "(JobsDone >= 1) and (JobsNot = 0)" in blk, "")
    ck("P4", "what came back is one plain line each; what did not is a numbered warning with the restore's own reason lines and the exact steps",
       "Remote administration: on again, as it was before the uninstall." in blk and "scheduled again, as they were before the uninstall." in blk
       and "could not turn it on again:" in blk and "KeptJobSteps" in blk and "'    remote.sdsys on'" in blk
       and "RestoreLines(RestoreText, 'RESTORE job ', ': NOT scheduled again')" in blk, "")
    ck("P5", "RestoreLines keeps only printable ASCII from the helper's output; the page draws RestoredMsg",
       "(Line[I] >= ' ') and (Line[I] <= '~')" in iss and "AccessMsg +\n             RestoredMsg +" in iss, "")
    return rows


MUTANTS = [
    ("sdsvc selects the restore for any argument count", "svc", 'argc == 2 && strcmp(argv[1], "-restore-kept") == 0', 'strcmp(argv[1], "-restore-kept") == 0', "C1"),
    ("the restore no longer refuses a non-SYSTEM caller", "c", "if (!sr_is_system()) {", "if (0) {", "C2"),
    ("the result file may already exist", "c", "&sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL", "&sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL", "C3"),
    ("the child's command comes from the command line", "c", 'swprintf(script, MAX_PATH, L"%ls\\\\sd-restore-kept.ps1", appdir);',
     'swprintf(script, MAX_PATH, L"%ls", GetCommandLineW());', "C4"),
    ("the elevation test is gone", "c", "|| !el.TokenIsElevated", "|| 0", "C5"),
    ("the script is looked for beside the exe, wherever it is", "c", "_wcsicmp(appdir + len - tl, tail) != 0", "0", "C8"),
    ("the installer runs sdsvc.exe from the program folder's root", "rk", "$svc = Join-Path $AppDir 'usr\\bin\\sdsvc.exe'", "$svc = Join-Path $AppDir 'sdsvc.exe'", "R1"),
    ("the wait has no limit", "c", "#define SR_TIMEOUT_MS 180000", "#define SR_TIMEOUT_MS INFINITE", "C6"),
    ("sdrestore.c is not built", "make", "$(SVCDIR)/sdrestore.c ", "", "C7"),
    ("the script no longer checks who runs it", "sk", "$me.User.Value -ne $sdsysSid", "$false", "S1"),
    ("a job is judged scheduled on the name alone", "sk", "' is scheduled: ')", "'')", "S2"),
    ("the note is not required to be 'on'", "sk", "[string]$v -ceq 'on'", "$true", "S3"),
    ("remote-admin success is any output", "sk", "'^remote-admin: open'", "'.'", "S4"),
    ("the folder is not protected", "rk", "$ds.SetAccessRuleProtection($true, $false)", "", "R1"),
    ("the scripts are not staged", "stage", "'run-restore-kept.ps1', 'sd-restore-kept.ps1',", "", "R2"),
    ("a job line that is not a job is scheduled", "sk", "' \\((backup-all|update-accounts)\\)$'", "' \\((.*)\\)$'", "D1"),
    ("an untrusted note falls through unsaid", "sk", "'^untrusted' {", "'^untrustedX' {", "D4"),
    ("the writers test trusts everybody", "sk", "if ($ok -notcontains $sid) { return @{ Trusted = $false; Who = [string]$r.IdentityReference } }", "", "D6"),
    ("the installer does not read the restore result", "iss", "RestoreRan := Pos('sdrestore: child exit 0', RestoreText) > 0;", "RestoreRan := True;", "P3"),
    ("the note is captured after the restore", "iss", "if (KeptJobs > 0) or RadminWas then\n          RestoreText := RunRestoreKept;",
     "if (KeptJobs > 0) or RadminNoteSaysOn then\n          RestoreText := RunRestoreKept;\n        RadminWas := RadminNoteSaysOn;", "P2"),
]


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()[:12]


def selftest():
    base = {k: read(v) for k, v in FILES.items()}
    before = {k: sha(v) for k, v in FILES.items()}
    print("live files, SHA-256 before: " + " ".join("%s %s" % (k, h) for k, h in before.items()))
    bad = [r[0] for r in rows_for(base) if not r[2]]
    ok = not bad
    print("  [%s] control: the unbroken text passes every row%s" % ("PASS" if ok else "FAIL", "" if ok else " - red: %s" % bad))
    for name, which, old, new, row in MUTANTS:
        n = base[which].count(old)
        if n != 1:
            print("  [FAIL] mutant '%s': its anchor occurs %d times (needs exactly 1)" % (name, n))
            ok = False
            continue
        m = dict(base)
        m[which] = base[which].replace(old, new)
        red = [r[0] for r in rows_for(m) if not r[2]]
        hit = row in red
        print("  [%s] mutant '%s' turns %s red%s" % ("PASS" if hit else "FAIL", name, row, "" if hit else " (red rows: %s)" % red))
        ok = ok and hit
    after = {k: sha(v) for k, v in FILES.items()}
    print("  [%s] the live files are unchanged" % ("PASS" if before == after else "FAIL"))
    print("test-restorekept-units --selftest: %s (%d mutants)" % ("PASSED" if ok and before == after else "FAILED", len(MUTANTS)))
    return 0 if ok and before == after else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    for k, p in FILES.items():
        if not os.path.isfile(p):
            print("test-restorekept-units: NO TREE - %s is not here" % p)
            return 2
    rows = rows_for({k: read(v) for k, v in FILES.items()})
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "  <- " + str(detail)))
        bad += 0 if ok else 1
    if len(rows) < 20:
        print("test-restorekept-units: FAILED - only %d rows (the null case)" % len(rows))
        return 1
    print("test-restorekept-units: %d rows, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
