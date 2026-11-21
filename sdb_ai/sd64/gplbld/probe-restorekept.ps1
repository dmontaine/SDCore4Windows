# probe-restorekept.ps1 - run the REAL restore (run-restore-kept.ps1 -> sdsvc.exe -restore-kept -> sd-restore-kept.ps1) on a machine that has SD Core
#
#   powershell -ExecutionPolicy Bypass -File <this file> -Bundle <folder with sdsvc.exe and the four scripts>      ELEVATED, on the machine to test
#
# RELEASE_1.1 370, 21 Nov 2026.  Not an installer test: it makes a scratch "program folder" from the bundle (sdsvc.exe built with sdrestore.c,
# run-restore-kept.ps1, sd-restore-kept.ps1, sd-jobs.ps1, sd-taskfolder.ps1), writes THREE job definitions the way a Keep leaves them (two good, one
# damaged) into <ProgramData>\SD\sd-jobs, runs run-restore-kept.ps1 exactly as the installer does, and READS what is left:
#   - the output of the run (the "RESTORE ..." lines and "sdrestore: child exit 0"),
#   - the tasks \SD\sdcore-job-zzr1 and -zzr2 in Task Scheduler: present, run as SDSYS, S4U, highest run level; zzr3 (damaged) absent,
#   - that the SYSTEM task, the result folder and the scratch folder are gone,
# then removes what it made.  It never touches a job it did not make (names zzr1..zzr3).  The remote administration half is NOT run here (no note).
# Exit 0 only when every check below passed; 1 otherwise; 2 it could not run.

param([string]$Bundle = '', [string]$Report = '')

$ErrorActionPreference = 'Continue'
function Say([string]$t) { Write-Host $t }
if ($Report -eq '') { $Report = $(if (Test-Path -LiteralPath '\\vboxsvr\xfer') { '\\vboxsvr\xfer\probe-restorekept-' } else { Join-Path $env:TEMP 'probe-restorekept-' }) + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt' }
try { Start-Transcript -LiteralPath $Report -Force | Out-Null } catch { }
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say ('=== probe-restorekept ' + (Get-Date -Format s) + '  machine ' + $env:COMPUTERNAME + '  caller ' + $me.Name + '  elevated ' + $elevated + '  report ' + $Report)
if (-not $elevated) { Say 'REFUSED: run elevated.'; exit 2 }
if ($Bundle -eq '' -or -not (Test-Path -LiteralPath $Bundle)) { Say "REFUSED: -Bundle $Bundle is not there."; exit 2 }
$need = 'sdsvc.exe', 'run-restore-kept.ps1', 'sd-restore-kept.ps1', 'sd-jobs.ps1', 'sd-taskfolder.ps1'
foreach ($n in $need) { Say ('bundle         : ' + $n + '  ' + $(if (Test-Path -LiteralPath (Join-Path $Bundle $n)) { (Get-Item -LiteralPath (Join-Path $Bundle $n)).Length.ToString() + ' bytes' } else { 'MISSING' })) }
if (@($need | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Bundle $_)) }).Count) { Say 'REFUSED: the bundle is incomplete.'; exit 2 }
$u = Get-LocalUser -Name SDSYS -ErrorAction SilentlyContinue
if ($null -eq $u) { Say 'REFUSED: no local account SDSYS (is SD Core installed?).'; exit 2 }
Say ('SDSYS          : ' + $u.SID.Value + ' enabled ' + $u.Enabled)

$app = Join-Path $env:ProgramData 'SDtestapp'
$jobsDir = Join-Path $env:ProgramData 'SD\sd-jobs'
$madeDir = $false
if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
New-Item -ItemType Directory -Force -Path $app | Out-Null
# The REAL layout: sdsvc.exe in <app>\usr\bin, the scripts in <app> (the first version of this probe put them all in one folder and hid a bug).
New-Item -ItemType Directory -Force -Path (Join-Path $app 'usr\bin') | Out-Null
foreach ($n in $need) {
    $dst = $(if ($n -eq 'sdsvc.exe') { Join-Path $app 'usr\bin\sdsvc.exe' } else { Join-Path $app $n })
    Copy-Item -LiteralPath (Join-Path $Bundle $n) -Destination $dst -Force
}
Say ('scratch app    : ' + $app)

# --- the definitions a Keep leaves: written as an elevated administrator into an administrators-only folder ----------------------------
if (-not (Test-Path -LiteralPath $jobsDir)) {
    $ds = New-Object Security.AccessControl.DirectorySecurity
    $ds.SetAccessRuleProtection($true, $false)
    $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) { $ds.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow'))) }
    $ds.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    [IO.Directory]::CreateDirectory($jobsDir, $ds) | Out-Null
    $madeDir = $true
}
function Def([string]$n, [string]$job, [string]$cmd, [string]$sched) {
    $t = "# an SD scheduled job, written by sd-jobs.ps1 job-set; changed only by sd-jobs.ps1 job-set and job-delete`nname=$n`njob=$job`ncommand=$cmd`nschedule=$sched`n"
    [IO.File]::WriteAllText((Join-Path $jobsDir $n), $t, (New-Object Text.ASCIIEncoding))
}
Def 'zzr1' 'backup-all' 'backup.account all' 'daily 03:30'
Def 'zzr2' 'update-accounts' 'update.accounts all' 'every 20 minutes'
[IO.File]::WriteAllText((Join-Path $jobsDir 'zzr3'), "x=1`n", (New-Object Text.ASCIIEncoding))
Say ('definitions    : ' + ((Get-ChildItem -LiteralPath $jobsDir | Where-Object { $_.Name -like 'zzr*' } | ForEach-Object { $_.Name + ' owner ' + (Get-Acl -LiteralPath $_.FullName).Owner }) -join '; '))
foreach ($t in @('zzr1', 'zzr2', 'zzr3')) { Unregister-ScheduledTask -TaskPath '\SD\' -TaskName "sdcore-job-$t" -Confirm:$false -ErrorAction SilentlyContinue }
Say ('tasks before   : ' + @(Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-job-zzr*' -ErrorAction SilentlyContinue).Count + ' (must be 0)')

# --- the run, exactly as the installer runs it ---------------------------------------------------------------------------------------
Say ''
Say '=========================================================================='
Say ' run-restore-kept.ps1 -AppDir (the installer''s call)'
Say '=========================================================================='
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$out = Join-Path $env:TEMP 'restore-kept-probe.txt'
Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
& cmd.exe /c ('""' + $ps + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $app 'run-restore-kept.ps1') + '" -AppDir "' + $app + '" > "' + $out + '" 2>&1"')
Say ('exit ' + $LASTEXITCODE)
$text = if (Test-Path -LiteralPath $out) { @(Get-Content -LiteralPath $out) } else { @() }
$text | ForEach-Object { Say "  | $_" }

# --- what is left -----------------------------------------------------------------------------------------------------------------
Say ''
Say '=========================================================================='
Say ' CHECKS'
Say '=========================================================================='
$joined = $text -join "`n"
$sdsysSid = $u.SID.Value
$checks = New-Object System.Collections.ArrayList
function Check([string]$what, [bool]$ok, [string]$detail = '') { [void]$checks.Add([pscustomobject]@{ What = $what; Ok = $ok }); Say (('  [' + $(if ($ok) { 'PASS' } else { 'FAIL' }) + '] ' + $what) + $(if (-not $ok -and $detail) { '   <- ' + $detail } else { '' })) }
Check 'the run printed "sdrestore: child exit 0" (the helper ran to its end)' ($joined -match 'sdrestore: child exit 0')
Check 'the child ran as the account SDSYS (RESTORE start line names it)' ($joined -match ('RESTORE start: \S*SDSYS ')) ($joined)
Check 'zzr1 and zzr2 were reported "scheduled again", zzr3 "NOT scheduled again"' (($joined -match 'RESTORE job zzr1: scheduled again') -and ($joined -match 'RESTORE job zzr2: scheduled again') -and ($joined -match 'RESTORE job zzr3: NOT scheduled again'))
Check 'the summary says "RESTORE jobs: 2 scheduled again, 1 NOT."' ($joined -match 'RESTORE jobs: 2 scheduled again, 1 NOT\.')
Check 'no note, so remote administration says "none to restore."' ($joined -match 'RESTORE remote-admin: none to restore')
foreach ($n in 'zzr1', 'zzr2') {
    $t = Get-ScheduledTask -TaskPath '\SD\' -TaskName "sdcore-job-$n" -ErrorAction SilentlyContinue
    $d = if ($t) { $t.Principal.UserId + ' ' + $t.Principal.LogonType + ' ' + $t.Principal.RunLevel + ' ' + $t.State } else { 'ABSENT' }
    Say ("  task \SD\sdcore-job-$n : $d")
    $who = ''
    if ($t) { try { $who = (New-Object Security.Principal.NTAccount($t.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value } catch { $who = $t.Principal.UserId } }
    Check "the task sdcore-job-$n exists and runs as SDSYS, S4U, highest run level" (($null -ne $t) -and ($who -eq $sdsysSid -or $t.Principal.UserId -match 'SDSYS') -and ([string]$t.Principal.LogonType -eq 'S4U') -and ([string]$t.Principal.RunLevel -eq 'Highest')) $d
}
Check 'the damaged definition zzr3 got no task' (@(Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-job-zzr3' -ErrorAction SilentlyContinue).Count -eq 0)
Check 'the SYSTEM task SDRestoreKept is gone' (@(Get-ScheduledTask -TaskName 'SDRestoreKept' -ErrorAction SilentlyContinue).Count -eq 0)
Check 'the result folder <ProgramData>\SDrestore is gone' (-not (Test-Path -LiteralPath (Join-Path $env:ProgramData 'SDrestore')))

# --- clean up what this made --------------------------------------------------------------------------------------------------
foreach ($t in @('zzr1', 'zzr2', 'zzr3')) {
    Unregister-ScheduledTask -TaskPath '\SD\' -TaskName "sdcore-job-$t" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $jobsDir $t) -Force -ErrorAction SilentlyContinue
}
if ($madeDir -and -not @(Get-ChildItem -LiteralPath $jobsDir -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $jobsDir -Force -ErrorAction SilentlyContinue }
Remove-Item -LiteralPath $app -Recurse -Force -ErrorAction SilentlyContinue
Say ''
Say ('cleanup        : zzr tasks ' + @(Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-job-zzr*' -ErrorAction SilentlyContinue).Count + ', zzr definitions ' + @(Get-ChildItem -LiteralPath $jobsDir -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'zzr*' }).Count + ', scratch app ' + (Test-Path -LiteralPath $app) + ', the sd-jobs folder I made removed ' + ($madeDir -and -not (Test-Path -LiteralPath $jobsDir)))
$failed = @($checks | Where-Object { -not $_.Ok }).Count
Say ''
Say ('RESULT: ' + ($checks.Count - $failed) + ' of ' + $checks.Count + ' checks passed' + $(if ($failed) { ', ' + $failed + ' FAILED' } else { '' }))
try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 }
exit 0
