# probe-sdsys-taskreg.ps1 - can the INSTALL register a Task Scheduler task that runs as SDSYS?   (RELEASE_1.1 370, owner 21 Nov 2026)
#
#   powershell -ExecutionPolicy Bypass -File <this file> -Exe <probe-s4u-cmd.exe>        in an ELEVATED PowerShell, on the machine to test
#   powershell -ExecutionPolicy Bypass -File <this file> -WriteOnly -WorkDir <scratch>   writes the child scripts and stops (no elevation)
#
# WHY.  Windows registers a task that runs as SDSYS (S4U, highest run level - what SET.JOB makes) only for SDSYS itself (row 280, measured for
# an administrator; HISTORY Solo 74 measured the same for SYSTEM and a Solo user).  So the installer cannot give a kept job, or remote
# administration's broker task, its task back after a Keep reinstall, and a warning with the exact steps is all it can print.  The owner asked
# (21 Nov): is there no way to become SDSYS during the install?  Two ways need ONE fact: does Task Scheduler accept a registration from a
# process that holds the S4U token of SDSYS which a LocalSystem process minted (the SD service already mints it for the local SDSYS door,
# gplsrc/sdsvc/sdsyslocal.c)?  This measures it, with its controls, in one run.  Nothing here changes SD: it makes and removes its own task folder
# \SDprobe, one SYSTEM task SDProbeSdsysTaskReg, one job definition zzprobe (the real helper, sd-jobs.ps1), and the folder <ProgramData>\SDprobe.
#
# THREE RUNS OF THE SAME REGISTRATION, because a success with no refused control beside it proves nothing (probe-s4u.c's rule):
#   CONTROL A  as THIS elevated administrator (not SDSYS)                        expected REFUSED  (row 280)
#   CONTROL B  as LocalSystem, directly                                          expected REFUSED  (Solo 74)
#   MEASURED   as SDSYS, in a process LocalSystem started with SDSYS's S4U token (probe-s4u-cmd.exe = probe-s4u.c with its argv[2] child)
# and, in the MEASURED process, the REAL helper too: sd-jobs.ps1 job-set / job-state / job-delete of a job named zzprobe, which is what a restore
# step would run.  A refused control makes the measurement mean something; a control that REGISTERS is said out loud and the verdict says so.
#
# THE REAL INPUTS ARE PRINTED (account, SID, the exe's path and size, the work folder, each command line) and the results are the children's own
# lines "RESULT <what>[<tag>]: ..." so nothing is believed on an exit code.  NOT RUN is never a pass: a child that printed nothing is NOT RUN.
#
# Needs: the SD Core install (C:\Program Files\SD\sd-jobs.ps1) and its Windows account SDSYS.  The exe is built on the host, never committed:
#   see the commit that added this file (gcc -static from probe-s4u.c).  Exit 0 the three runs completed and the controls held; 1 the controls
#   did not hold or the measurement was refused; 2 it could not run.  It is on assert-current's never-shipped list by its name (probe-).

param(
    [string]$Exe = '',
    [string]$Account = 'SDSYS',
    [string]$WorkDir = '',
    [string]$Report = '',
    [switch]$WriteOnly
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($WorkDir -eq '') { $WorkDir = Join-Path $env:ProgramData 'SDprobe' }
$Ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$TaskName = 'SDProbeSdsysTaskReg'

# ---------------------------------------------------------------------------------------------------------------------------------
# The three scripts that run elsewhere (as SDSYS, as SYSTEM).  Single-quoted here-strings, so nothing is expanded here; @@WORK@@ and
# @@ACCOUNT@@ are replaced below.
# ---------------------------------------------------------------------------------------------------------------------------------
$ChildRaw = @'
# child-raw.ps1 - the bare registration: S4U, highest run level, as the account, into \SDprobe\.  Run by the probe three ways (-Tag).
param([string]$Tag = 'x')
$ErrorActionPreference = 'Continue'
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
$work = '@@WORK@@'
$log = Join-Path $work "child-raw-$Tag.log"
function L([string]$t) { [Console]::Out.WriteLine($t); try { Add-Content -LiteralPath $log -Value $t } catch { } }
function Clip([string]$s) { $s = ($s -replace '\s+', ' ').Trim(); if ($s.Length -gt 220) { $s.Substring(0, 220) } else { $s } }
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.SecurityIdentifier]'S-1-5-32-544')
$il = (@(& whoami.exe /groups 2>&1) | Where-Object { "$_" -match 'Mandatory Label' } | ForEach-Object { ("$_" -split '\s{2,}')[0].Trim() }) -join ''
L ("RESULT who[$Tag]: " + $me.Name + ' ' + $me.User.Value + ' admin-role=' + $isAdmin + ' ' + $il)
try {
    $sid = (New-Object Security.Principal.NTAccount("$env:COMPUTERNAME\@@ACCOUNT@@")).Translate([Security.Principal.SecurityIdentifier]).Value
} catch { L ("RESULT raw[$Tag]: NOT RUN no account @@ACCOUNT@@ (" + (Clip $_.Exception.Message) + ')'); exit 3 }
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>probe-sdsys-taskreg $Tag; removed at once</Description></RegistrationInfo>
  <Triggers><TimeTrigger><StartBoundary>2099-01-01T03:00:00</StartBoundary><Enabled>true</Enabled></TimeTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$sid</UserId><LogonType>S4U</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><Enabled>true</Enabled></Settings>
  <Actions Context="Author"><Exec><Command>cmd.exe</Command><Arguments>/c exit 0</Arguments></Exec></Actions>
</Task>
"@
$name = "zzprobe-$Tag"
try {
    Register-ScheduledTask -TaskName $name -TaskPath '\SDprobe\' -Xml $xml -Force -ErrorAction Stop | Out-Null
    $t = Get-ScheduledTask -TaskPath '\SDprobe\' -TaskName $name -ErrorAction Stop
    L ("RESULT raw[$Tag]: REGISTERED as " + $t.Principal.UserId + ' logon=' + $t.Principal.LogonType + ' run=' + $t.Principal.RunLevel + ' state=' + $t.State)
    Unregister-ScheduledTask -TaskPath '\SDprobe\' -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    $left = Get-ScheduledTask -TaskPath '\SDprobe\' -TaskName $name -ErrorAction SilentlyContinue
    L ("RESULT raw-removed[$Tag]: " + $(if ($null -eq $left) { 'yes' } else { 'NO, the task is still there' }))
} catch {
    L ("RESULT raw[$Tag]: REFUSED " + ('0x{0:X8}' -f $_.Exception.HResult) + ' ' + (Clip $_.Exception.Message))
}
'@

$ChildJobs = @'
# child-jobs.ps1 - the REAL helper as the account: sd-jobs.ps1 job-set zzprobe, job-state, job-delete.  What a restore step would run.
$ErrorActionPreference = 'Continue'
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
$work = '@@WORK@@'
$log = Join-Path $work 'child-jobs-sdsys.log'
function L([string]$t) { [Console]::Out.WriteLine($t); try { Add-Content -LiteralPath $log -Value $t } catch { } }
function Clip([string]$s) { $s = ($s -replace '\s+', ' ').Trim(); if ($s.Length -gt 200) { $s.Substring(0, 200) } else { $s } }
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
L ('RESULT who[jobs]: ' + $me.Name + ' ' + $me.User.Value)
$jobs = Join-Path $env:ProgramFiles 'SD\sd-jobs.ps1'
if (-not (Test-Path -LiteralPath $jobs)) { L ('RESULT jobs: NOT RUN no ' + $jobs); exit 3 }
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
foreach ($step in @(@('job-set', 'zzprobe', 'backup-all', 'daily', '03:00'), @('job-state', 'zzprobe'), @('job-delete', 'zzprobe'))) {
    $o = @(& $ps -NoProfile -ExecutionPolicy Bypass -File $jobs @step 2>&1)
    $code = $LASTEXITCODE
    $last = if ($o.Count) { Clip ("$($o[$o.Count - 1])") } else { '(no output)' }
    L ('RESULT jobs[' + $step[0] + ']: exit ' + $code + ' ' + $last)
}
'@

$AsSystem = @'
# as-system.ps1 - run by the SYSTEM task.  CONTROL B, then the MEASUREMENT twice (bare registration, then the real helper), each as the account.
$ErrorActionPreference = 'Continue'
$dir = '@@WORK@@'
$res = Join-Path $dir 'system-run.txt'
function W([string]$t) { Add-Content -LiteralPath $res -Value $t }
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
W ('=== as-system ' + (Get-Date -Format s) + ' running as ' + $me.Name + ' ' + $me.User.Value)
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
W '--- CONTROL B: the bare registration run directly as SYSTEM (expected REFUSED)'
@(& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'child-raw.ps1') -Tag system 2>&1) | ForEach-Object { W ('  ' + $_) }
$exe = Join-Path $dir 'probe-s4u-cmd.exe'
foreach ($n in @('raw', 'jobs')) {
    $cmdfile = Join-Path $dir "cmd-$n.txt"
    $of = Join-Path $dir "probe-$n.txt"
    if (Test-Path -LiteralPath $of) { Remove-Item -LiteralPath $of -Force }
    W ('--- MEASUREMENT [' + $n + ']: ' + $exe + ' @@ACCOUNT@@ ' + $cmdfile + '   (SYSTEM mints the S4U token of @@ACCOUNT@@; the child runs under it)')
    W ('    child command line: ' + ((Get-Content -LiteralPath $cmdfile -TotalCount 1) -join ''))
    & cmd.exe /c "$exe @@ACCOUNT@@ $cmdfile > $of 2>&1"
    W ('    probe exit ' + $LASTEXITCODE)
    if (Test-Path -LiteralPath $of) { @(Get-Content -LiteralPath $of) | ForEach-Object { W ('  | ' + $_) } } else { W '  | (no output file: nothing ran)' }
}
W ('=== as-system finished ' + (Get-Date -Format s))
'@

foreach ($v in 'ChildRaw', 'ChildJobs', 'AsSystem') {
    Set-Variable -Name $v -Value ((Get-Variable -Name $v -ValueOnly).Replace('@@WORK@@', $WorkDir).Replace('@@ACCOUNT@@', $Account))
}

function Write-Ascii([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.ASCIIEncoding)) }

if ($WriteOnly) {
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    Write-Ascii (Join-Path $WorkDir 'child-raw.ps1') $ChildRaw
    Write-Ascii (Join-Path $WorkDir 'child-jobs.ps1') $ChildJobs
    Write-Ascii (Join-Path $WorkDir 'as-system.ps1') $AsSystem
    Write-Host "probe-sdsys-taskreg: -WriteOnly wrote child-raw.ps1, child-jobs.ps1 and as-system.ps1 into $WorkDir (account $Account); nothing was run"
    exit 0
}

# ---------------------------------------------------------------------------------------------------------------------------------
# The run.
# ---------------------------------------------------------------------------------------------------------------------------------
function Say([string]$t) { Write-Host $t }
function Invoke-Schtasks {
    # schtasks writes "not found" to stderr, which kills a script that reads it under Stop in PowerShell 5.1 (probe-s4u.ps1, trap 1).
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & schtasks.exe @args 2>&1; return [pscustomobject]@{ Code = $LASTEXITCODE; Output = @($o | ForEach-Object { "$_" }) } }
    finally { $ErrorActionPreference = $saved }
}

if ($Report -eq '') {
    $Report = $(if (Test-Path -LiteralPath '\\vboxsvr\xfer') { '\\vboxsvr\xfer\probe-sdsys-taskreg-' } else { Join-Path $env:TEMP 'probe-sdsys-taskreg-' }) + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'
}
try { Start-Transcript -LiteralPath $Report -Force | Out-Null } catch { Say "probe-sdsys-taskreg: no transcript ($($_.Exception.Message)); the screen is the record" }

Say ('=== probe-sdsys-taskreg ' + (Get-Date -Format s) + '  report: ' + $Report)
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$os = try { (Get-CimInstance Win32_OperatingSystem) } catch { $null }
Say ('machine        : ' + $env:COMPUTERNAME + '   caller ' + $me.Name + ' ' + $me.User.Value + '   elevated ' + $elevated)
Say ('windows        : ' + $(if ($os) { $os.Caption + ' build ' + $os.BuildNumber } else { '(unreadable)' }))
if (-not $elevated) { Say 'REFUSED: run this in an ELEVATED PowerShell.'; Stop-Transcript | Out-Null; exit 2 }
if ($Exe -eq '') { $Exe = Join-Path $here 'probe-s4u-cmd.exe' }
Say ('exe            : ' + $Exe + '   exists ' + (Test-Path -LiteralPath $Exe) + $(if (Test-Path -LiteralPath $Exe) { '   ' + (Get-Item -LiteralPath $Exe).Length + ' bytes' } else { '' }))
if (-not (Test-Path -LiteralPath $Exe)) { Say 'REFUSED: no probe-s4u-cmd.exe (build it on the host from probe-s4u.c; see this file''s header).'; Stop-Transcript | Out-Null; exit 2 }
$u = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
if ($null -eq $u) { Say "REFUSED: there is no local account $Account on this machine (is SD Core installed?)."; Stop-Transcript | Out-Null; exit 2 }
Say ('account        : ' + $u.Name + ' ' + $u.SID.Value + '   enabled ' + $u.Enabled)
$admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue | ForEach-Object { $_.SID.Value })
Say ('account is an administrator: ' + ($admins -contains $u.SID.Value))
$jobsPs1 = Join-Path $env:ProgramFiles 'SD\sd-jobs.ps1'
Say ('sd-jobs.ps1    : ' + $jobsPs1 + '   exists ' + (Test-Path -LiteralPath $jobsPs1))
Say ('work folder    : ' + $WorkDir)

# --- the work folder: SYSTEM and Administrators full, the account modify (its child writes its log there), nobody else ---------------
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$ds = New-Object Security.AccessControl.DirectorySecurity
$ds.SetAccessRuleProtection($true, $false)
$inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
    $ds.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
}
$ds.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($u.SID, 'Modify', $inh, 'None', 'Allow')))
$ds.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
[IO.Directory]::CreateDirectory($WorkDir, $ds) | Out-Null
Copy-Item -LiteralPath $Exe -Destination (Join-Path $WorkDir 'probe-s4u-cmd.exe') -Force
Write-Ascii (Join-Path $WorkDir 'child-raw.ps1') $ChildRaw
Write-Ascii (Join-Path $WorkDir 'child-jobs.ps1') $ChildJobs
Write-Ascii (Join-Path $WorkDir 'as-system.ps1') $AsSystem
$rawCmd = $Ps + ' -NoProfile -ExecutionPolicy Bypass -File ' + (Join-Path $WorkDir 'child-raw.ps1') + ' -Tag sdsys'
$jobsCmd = $Ps + ' -NoProfile -ExecutionPolicy Bypass -File ' + (Join-Path $WorkDir 'child-jobs.ps1')
Write-Ascii (Join-Path $WorkDir 'cmd-raw.txt') ($rawCmd + "`r`n")
Write-Ascii (Join-Path $WorkDir 'cmd-jobs.txt') ($jobsCmd + "`r`n")
Say ('written        : ' + ((Get-ChildItem -LiteralPath $WorkDir | ForEach-Object { $_.Name }) -join ', '))
Say ('raw child cmd  : ' + $rawCmd)
Say ('jobs child cmd : ' + $jobsCmd)

# --- CONTROL A ---------------------------------------------------------------------------------------------------------------------
Say ''
Say '=========================================================================='
Say " CONTROL A - the bare registration as THIS administrator ($($me.Name)); expected REFUSED"
Say '=========================================================================='
$a = @(& $Ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $WorkDir 'child-raw.ps1') -Tag admin 2>&1 | ForEach-Object { "$_" })
$a | ForEach-Object { Say "  $_" }

# --- CONTROL B and the MEASUREMENT: one SYSTEM task -------------------------------------------------------------------------------
Say ''
Say '=========================================================================='
Say ' CONTROL B (as SYSTEM) and the MEASUREMENT (SDSYS, S4U token minted by SYSTEM)'
Say '=========================================================================='
$resFile = Join-Path $WorkDir 'system-run.txt'
$tr = $Ps + ' -NoProfile -ExecutionPolicy Bypass -File ' + (Join-Path $WorkDir 'as-system.ps1')
Invoke-Schtasks /Delete /TN $TaskName /F | Out-Null
$c = Invoke-Schtasks /Create /TN $TaskName /TR $tr /SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F
Say ('schtasks create : exit ' + $c.Code + '  ' + ($c.Output -join ' '))
if ($c.Code -ne 0) { Say 'NOT RUN: the SYSTEM task could not be registered.'; Stop-Transcript | Out-Null; exit 2 }
$r = Invoke-Schtasks /Run /TN $TaskName
Say ('schtasks run    : exit ' + $r.Code + '  ' + ($r.Output -join ' '))
$deadline = (Get-Date).AddSeconds(240)
$started = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    $q = Invoke-Schtasks /Query /TN $TaskName /FO LIST
    $status = (($q.Output | Where-Object { $_ -match '^Status:' }) -join ' ')
    if ($status -match 'Running') { $started = $true; continue }
    if ($started -or (Test-Path -LiteralPath $resFile)) {
        if ((Test-Path -LiteralPath $resFile) -and ((Get-Content -LiteralPath $resFile -Raw) -match 'as-system finished')) { break }
    }
}
$sys = if (Test-Path -LiteralPath $resFile) { @(Get-Content -LiteralPath $resFile) } else { @() }
$sys | ForEach-Object { Say $_ }
if ($sys.Count -eq 0) { Say 'NOT RUN: the SYSTEM task wrote nothing (no result file).' }

# --- cleanup, and what is left ---------------------------------------------------------------------------------------------------
Say ''
Say '=========================================================================='
Say ' CLEANUP'
Say '=========================================================================='
Invoke-Schtasks /Delete /TN $TaskName /F | Out-Null
foreach ($t in @(Get-ScheduledTask -TaskPath '\SDprobe\' -ErrorAction SilentlyContinue)) {
    Unregister-ScheduledTask -TaskPath '\SDprobe\' -TaskName $t.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}
try { $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $svc.GetFolder('\').DeleteFolder('SDprobe', 0) } catch { }
$leftTasks = @(Get-ScheduledTask -TaskPath '\SDprobe\' -ErrorAction SilentlyContinue).Count
$leftJobTask = @(Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-job-zzprobe' -ErrorAction SilentlyContinue).Count
$jobDefDir = Join-Path $env:ProgramData 'SD\sd-jobs'
$leftJobDef = Test-Path -LiteralPath (Join-Path $jobDefDir 'zzprobe')
if ($leftJobTask) { Unregister-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-job-zzprobe' -Confirm:$false -ErrorAction SilentlyContinue }
if ($leftJobDef) { Remove-Item -LiteralPath (Join-Path $jobDefDir 'zzprobe') -Force -ErrorAction SilentlyContinue }
Say ('left over before cleanup: tasks in \SDprobe\ ' + $leftTasks + ', the zzprobe job task ' + $leftJobTask + ', the zzprobe job definition ' + $leftJobDef)
Say ('after cleanup           : SYSTEM task ' + (@(Invoke-Schtasks /Query /TN $TaskName).Where({ $_.Code -eq 0 }).Count) + ' (0 = gone), \SDprobe\ tasks ' + @(Get-ScheduledTask -TaskPath '\SDprobe\' -ErrorAction SilentlyContinue).Count + ', zzprobe job task ' + @(Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-job-zzprobe' -ErrorAction SilentlyContinue).Count + ', zzprobe definition ' + (Test-Path -LiteralPath (Join-Path $jobDefDir 'zzprobe')))
$logsKept = Join-Path $env:TEMP ('sdprobe-logs-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $logsKept | Out-Null
Get-ChildItem -LiteralPath $WorkDir -Filter '*.log' -ErrorAction SilentlyContinue | Copy-Item -Destination $logsKept -Force
Get-ChildItem -LiteralPath $WorkDir -Filter 'probe-*.txt' -ErrorAction SilentlyContinue | Copy-Item -Destination $logsKept -Force
Say ('child logs and the probe''s own output copied to ' + $logsKept)
Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Say ('work folder removed: ' + (-not (Test-Path -LiteralPath $WorkDir)))

# --- the verdict, from the children's own RESULT lines ---------------------------------------------------------------------------------
function Pick([string[]]$lines, [string]$key) { @($lines | Where-Object { $_ -match [regex]::Escape($key) } | Select-Object -First 1) -join '' }
$all = @($a) + @($sys)
$ctlA = Pick $all 'RESULT raw[admin]:'
$ctlB = Pick $all 'RESULT raw[system]:'
$mRaw = Pick $all 'RESULT raw[sdsys]:'
$mSet = Pick $all 'RESULT jobs[job-set]:'
$mDel = Pick $all 'RESULT jobs[job-delete]:'
Say ''
Say '=========================================================================='
Say ' VERDICT'
Say '=========================================================================='
Say ('  CONTROL A  admin, bare registration     : ' + $(if ($ctlA) { $ctlA } else { 'NOT RUN (no RESULT line)' }))
Say ('  CONTROL B  SYSTEM, bare registration    : ' + $(if ($ctlB) { $ctlB } else { 'NOT RUN (no RESULT line)' }))
Say ('  MEASURED   SDSYS (S4U), bare            : ' + $(if ($mRaw) { $mRaw } else { 'NOT RUN (no RESULT line: see the probe output above - did the S4U token or the child fail?)' }))
Say ('  MEASURED   SDSYS (S4U), real helper     : ' + $(if ($mSet) { $mSet } else { 'NOT RUN (no RESULT line)' }))
Say ('                                  delete  : ' + $(if ($mDel) { $mDel } else { 'NOT RUN' }))
$controlsHeld = ($ctlA -match 'REFUSED') -and ($ctlB -match 'REFUSED')
$bare = $mRaw -match 'REGISTERED'
$helper = $mSet -match 'is scheduled'
Say ''
if (-not $controlsHeld) {
    Say '  A CONTROL DID NOT REFUSE (or did not run), so the measurement does not isolate what the SDSYS token adds.  Read the control lines above before anything else.'
}
if ($bare -and $controlsHeld) {
    Say '  ANSWER: YES for the bare registration.  An administrator and SYSTEM are refused; a process holding the S4U token of the account that SYSTEM minted is accepted.'
    Say $(if ($helper) { '  AND the real helper (sd-jobs.ps1 job-set) scheduled and removed the job as that process: a restore step run that way would work.' } else { '  BUT the real helper did not report "is scheduled": read its line above before building on this.' })
} elseif ($mRaw -match 'REFUSED') {
    Say '  ANSWER: NO.  Task Scheduler refused the registration even from the S4U token minted by SYSTEM.  The install cannot do it that way; the sign-in hook or the password remain.'
} else {
    Say '  ANSWER: NOT MEASURED.  The measured child printed no result; nothing can be concluded.'
}
Say ('report: ' + $Report)
try { Stop-Transcript | Out-Null } catch { }
if (-not $controlsHeld -or -not ($mRaw)) { exit 1 }
exit 0
