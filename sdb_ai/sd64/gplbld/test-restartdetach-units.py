#!/usr/bin/env python3
"""test-restartdetach-units.py - RELEASE_1.1 340: a restart asked for from inside SD is handed to Task Scheduler.

    python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-restartdetach-units.py [--selftest]

18 Nov 2026 01:25: remote.api on's restart stopped SD and never started it - restart-sd.ps1 ran as a child of (or in the helper tied
to) the session its own stop ends.  FREE: reads two files.  Exit 0 every check passed, 1 a check failed, 2 it could not run.
  D1  remoteapi's run.restart calls restart-sd.ps1 -Detach
  D2  -Detach registers \\SD\\sdcore-restart in the vetted \\SD folder (sd-taskfolder.ps1), a task of the name deleted first, as SYSTEM
      (S-1-5-18, service account, highest), one action: this script with -FromTask; it is started, and success is anchored on the task
      seen running or just run; a failure says SD was NOT restarted and exits 1
  D3  -Detach returns before any stop; -FromTask writes its lines to <ProgramData>\\SD\\restart-sd.log and then does the ordinary restart
  D4  (RELEASE_1.1 361) -Detach waits for the task's result; a failure exits 1 after the task's own lines, and run.restart shows them
  D5  (RELEASE_1.1 361, sit8) the wait ends when the stop begins; the own-window host sd.exe is not counted as SD running
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
FILES = {"ra": os.path.join(SD64, "sdsys", "gpl.bp", "remoteapi"), "rs": os.path.join(HERE, "restart-sd.ps1")}


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1", newline="") as f:
                raw[k] = f.read().replace("\r\n", "\n")
        except OSError:
            raw[k] = None
    return raw


def code_ps(t):
    return "\n".join(l for l in (t or "").split("\n") if not l.lstrip().startswith("#"))


def checks(raw):
    rows = []
    ra = raw["ra"] or ""
    rr = ra[ra.find("\nrun.restart:"):]
    rows.append(("D1", "remoteapi's run.restart calls restart-sd.ps1 -Detach",
                 "kernel(K$WINPATH, '/restart-sd.ps1') : char(39) : ' -Detach'" in rr))
    rs = code_ps(raw["rs"])
    i = rs.find("if ($Detach) {")
    d = rs[i:rs.find("\nif ($FromTask) {", i)] if i >= 0 else ""
    rows.append(("D2", "-Detach: a vetted \\SD task as SYSTEM, deleted first, one action this script -FromTask, started, anchored on its state",
                 ". (Join-Path $PSScriptRoot 'sd-taskfolder.ps1')" in d and "$folder = Initialize-SdTaskFolder $tsSvc" in d
                 and "try { $folder.DeleteTask('sdcore-restart', 0) } catch { }" in d and "$def.Principal.UserId = 'S-1-5-18'" in d
                 and "$def.Principal.LogonType = 5" in d and "$def.Principal.RunLevel = 1" in d
                 and "'\" -FromTask'" in d and "$task.Run($null)" in d and "$t.State -eq 4" in d
                 and d.count("SD was NOT restarted") == 3 and d.count("exit 1") == 4 and "exit 0" in d))   # 19 Nov 26 (361): + the task's failure, + still running
    # D4, 19 Nov 26 - RELEASE_1.1 361 (VM sit7: "ran (status 0)" twice and no restart): -Detach waits for the task's own result and a
    # failure exits 1 with the task's lines before its verdict; run.restart takes those lines (ps_script_out) and shows them on a non-zero exit.
    w = d[d.find("$deadline = (Get-Date).AddSeconds(180)"):]
    rows.append(("D4", "-Detach waits up to 180 s for the task's LastTaskResult (not 0x41301/0x41303), a non-zero result exits 1 after the task's "
                 "lines; run.restart shows the lines when the exit is not 0",
                 "$deadline = (Get-Date).AddSeconds(180)" in d and "$r = [int]$t.LastTaskResult" in w and "$r -ne 267009 -and $r -ne 267011" in w
                 and 0 < w.find("$new | ForEach-Object") < w.find("if ($result -ne 0) {") < w.find("the restart task FAILED")
                 and "rs.res = ps_script_out(ps, @true)" in rr and "if rc # 0 then" in rr and "display rs.res<rs.i>" in rr))
    # D5, 20 Nov 26 - RELEASE_1.1 361 (VM sit8, measured: SD left stopped): the wait ends once the service leaves Running (before the task
    # check, so the waiting session is free to end), and the own-window host sd.exe (parent conhost or explorer, or parent of an sd.exe) is
    # not counted as SD still running.
    gp = rs[rs.find("function Get-SdProcs {"):rs.find("function Report(")]
    hp = rs[rs.find("function Get-SdHostPids {"):rs.find("function Report(")]
    rows.append(("D5", "-Detach returns 0 once the SD service is not Running, before reading the task; Get-SdProcs leaves out the own-window "
                 "host sd.exe (parent conhost.exe or explorer.exe, or parent of another sd.exe); an unreadable table excuses nothing",
                 0 < w.find("if ($svc -and $svc.Status -ne 'Running') {") < w.find("$t = $folder.GetTask('sdcore-restart')")
                 and "exit 0" in w[w.find("if ($svc -and $svc.Status -ne 'Running') {"):w.find("$t = $folder.GetTask('sdcore-restart')")]
                 and "$hosts = Get-SdHostPids" in gp and "-not ($_.Name -eq 'sd' -and $hosts -contains $_.Id)" in gp
                 and "$pn -eq 'conhost.exe' -or $pn -eq 'explorer.exe' -or $parentsOfSd -contains [int]$q.ProcessId" in hp
                 and "catch { return @() }" in hp and "-OperationTimeoutSec 15" in hp))
    stop = rs.find("sc.exe\" stop $SvcName")
    ft = rs.find("if ($FromTask) {")
    rows.append(("D3", "-Detach returns before any stop; -FromTask logs to ProgramData\\SD\\restart-sd.log, before the ordinary restart",
                 0 <= i < ft < stop and "Start-Transcript -Path (Join-Path $env:ProgramData 'SD\\restart-sd.log') -Append" in rs[ft:stop]))
    return rows


MUTANTS = [
    ("remote.api restarts in its own session again", "ra", " : ' -Detach'   ;*", "   ;*"),
    ("the task runs as the caller", "rs", "$def.Principal.UserId = 'S-1-5-18'", "$def.Principal.UserId = $env:USERNAME"),
    ("an old task of the name is kept", "rs", "        try { $folder.DeleteTask('sdcore-restart', 0) } catch { }\n", ""),
    ("success is not anchored", "rs", "if ($t.State -eq 4 -or", "if ($true -or"),
    ("the task does not run -FromTask", "rs", "'\" -FromTask'", "'\"'"),
    ("-FromTask writes no log", "rs", "try { Start-Transcript -Path (Join-Path $env:ProgramData 'SD\\restart-sd.log') -Append | Out-Null } catch { }", "$null = 0"),
    ("-Detach reports success without the task's result (361)", "rs", "$r -ne 267009 -and $r -ne 267011", "$true"),
    ("remote.api drops the script's lines again (361)", "ra", "rs.res = ps_script_out(ps, @true)", "rs.res = ps_script(ps)"),
    ("-Detach keeps waiting through the stop (361 sit8)", "rs", "if ($svc -and $svc.Status -ne 'Running') {", "if ($false) {"),
    ("the window host counts as SD running again (361 sit8)", "rs", "-not ($_.Name -eq 'sd' -and $hosts -contains $_.Id)", "$true"),
    ("a session's own parent would excuse it (361 sit8)", "rs", "$pn -eq 'conhost.exe' -or $pn -eq 'explorer.exe' -or", "$pn -ne '' -or"),
]


def main():
    raw = load()
    missing = [FILES[k] for k in FILES if raw[k] is None]
    if missing:
        print("test-restartdetach-units: CANNOT RUN - missing %s" % ", ".join(missing))
        return 2
    print("test-restartdetach-units: %s, %s" % (FILES["ra"], FILES["rs"]))
    rows = checks(raw)
    for n, w, ok in rows:
        print("  [%s] %s %s" % ("PASS" if ok else "FAIL", n, w))
    bad = [r for r in rows if not r[2]]
    if "--selftest" in sys.argv:
        if bad:
            print("test-restartdetach-units: CANNOT SELFTEST - the live files already fail")
            return 1
        missed = 0
        for what, key, old, new in MUTANTS:
            if old not in raw[key]:
                print("  [MUTANT CANNOT APPLY] %s" % what)
                missed += 1
                continue
            m = dict(raw)
            m[key] = raw[key].replace(old, new, 1)
            red = [r[0] for r in checks(m) if not r[2]]
            print("  [%s] %s%s" % ("CAUGHT" if red else "MISSED", what, (" by " + ", ".join(red)) if red else ""))
            missed += 0 if red else 1
        print("test-restartdetach-units --selftest: %d of %d mutants caught" % (len(MUTANTS) - missed, len(MUTANTS)))
        if missed:
            return 1
    print("test-restartdetach-units: %d checks, %d failed" % (len(rows), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
