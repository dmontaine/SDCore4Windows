# test-jobs-helper-units.ps1 - drive sd-jobs.ps1, the job helper of SET.JOB (the administrator's scheduled jobs on Task Scheduler).
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-jobs-helper-units.ps1
#
# 10 Nov 26 Windows port - for Linux's test-jobs-elevate-units.py (S.102 stages 2 to 4), carry area 14.  Linux cuts the job functions out of sd-elevate and
# runs them on scratch files; this does the same with sd-jobs.ps1's "# BEGIN jobs_functions" region, then runs the whole script in its dry run
# (-DryRun -TestJobsDir <scratch>), which works on the scratch folder and NEVER touches Task Scheduler.  Free: no install, no elevation, no sd.
#
# WHAT IT CANNOT SHOW: that Task Scheduler accepts the task's XML and runs it as SDSYS with no stored password, that the run's token carries what
# K$JOB.MARK asks for, and the real directory's ACL - the installed system's witness (a real job-set, job-run and job-delete as SDSYS, elevated).
# Linux rows that cannot hold here: the systemd unit text and OnCalendar spellings (the trigger XML takes their place: rows S), root-ownership and
# mode tests of the definitions (the ACL test, Test-JobAdminPath, is the kernel's rule and is read, not driven, because a passing ACL needs a file
# owned by Administrators), and sudo's SUDO_USER caller test (the caller test is the token's SID, read in the script's main line; rows C).
#
# Rows P and T7, T8 are job-purge, the uninstaller's verb (sd.iss RemoveScheduledJobs; Linux's deletesdcore.sh, S.102 stage 3).  The dry run takes the
# scratch definitions and their folder and asks Task Scheduler nothing, so THAT THE TASKS AND THE \SD TASK FOLDER GO is the uninstall's own witness.
#
# Exit 0 every row passed, 1 a row failed, 2 it could not run.  Fewer than 40 rows is a failure.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $here 'sd-jobs.ps1'
Write-Output "test-jobs-helper-units: subject $subject"
if (-not (Test-Path -LiteralPath $subject)) { Write-Output "test-jobs-helper-units: CANNOT RUN - $subject is missing"; exit 2 }
$text = [IO.File]::ReadAllText($subject)

$script:rows = @()
function Row([string]$label, [bool]$ok, [string]$detail = '') { $script:rows += , @($label, $ok, $detail) }

# ---------------------------------------------------------------- the functions, cut out as Linux's test cuts sd-elevate's
$b = $text.IndexOf('# BEGIN jobs_functions'); $e = $text.IndexOf('# END jobs_functions')
if ($b -lt 0 -or $e -lt $b) { Write-Output 'test-jobs-helper-units: CANNOT RUN - the jobs_functions markers are not in the script'; exit 2 }
. ([scriptblock]::Create($text.Substring($b, $e - $b)))
$want = 'Get-JobCommand', 'Test-JobName', 'Test-JobTime', 'Get-JobSchedule', 'Get-JobText', 'Get-JobTaskXml', 'Test-JobAdminPath', 'Read-JobRows', 'Format-JobListLine'
$missing = @($want | Where-Object { -not (Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue) })
Row 'F1 the region defines the nine job functions' ($missing.Count -eq 0) ($missing -join ',')
Row 'F2 the job limit is 32, the definition keys are name, job, command and schedule, the tasks live under \SD\' (($JobMax -eq 32) -and (($JobKeys -join ',') -ceq 'name,job,command,schedule') -and ($JobTaskPath -ceq '\SD\')) "$JobMax $($JobKeys -join ',') $JobTaskPath"

# J: the job ids are the helper's own two
Row 'J1 backup-all is backup.account all' ((Get-JobCommand 'backup-all') -ceq 'backup.account all')
Row 'J2 update-accounts is update.accounts all' ((Get-JobCommand 'update-accounts') -ceq 'update.accounts all')
foreach ($id in 'shell', 'Backup-All', '', 'check-masters', 'backup-all;x') { Row "J3 '$id' is no job id" ((Get-JobCommand $id) -eq '') }

# N: the name rule
foreach ($n in 'a', 'nightly', 'a-1', ('a' * 32), 'backup-2') { Row "N1 '$n' is a job name" (Test-JobName $n) }
foreach ($n in '', 'A', 'Nightly', '1a', 'a-', ('a' * 33), 'a_b', 'a.b', 'a b', '-a') { Row "N2 '$n' is not a job name" (-not (Test-JobName $n)) }

# S: the five schedule shapes, their one spelling and their triggers
$cases = @(
    @('every 15 minutes', 'every 15 minutes', '<Interval>PT15M</Interval>'),
    @('every 5 minutes', 'every 5 minutes', '<Interval>PT5M</Interval>'),
    @('hourly', 'hourly', '<Interval>PT1H</Interval>'),
    @('daily 02:30', 'daily 02:30', '<StartBoundary>2026-01-01T02:30:00</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>'),
    @('weekly sun 03:00', 'weekly sun 03:00', '<DaysOfWeek><Sunday /></DaysOfWeek><WeeksInterval>1</WeeksInterval>'),
    @('weekly mon 23:59', 'weekly mon 23:59', '<DaysOfWeek><Monday /></DaysOfWeek>'),
    @('monthly 28 04:00', 'monthly 28 04:00', '<DaysOfMonth><Day>28</Day></DaysOfMonth><Months><January />')
)
foreach ($c in $cases) {
    $s = Get-JobSchedule ($c[0] -split ' ')
    Row "S1 '$($c[0])' is spelt '$($c[1])' with the trigger $($c[2].Substring(0, [Math]::Min(40, $c[2].Length)))..." (($null -ne $s) -and ($s.Sched -ceq $c[1]) -and $s.Trigger.Contains($c[2])) $(if ($null -ne $s) { $s.Trigger } else { 'null' })
}
$s = Get-JobSchedule @('monthly', '1', '04:00')
Row 'S2 a monthly trigger names all twelve months' (($null -ne $s) -and ([regex]::Matches($s.Trigger, '<(January|February|March|April|May|June|July|August|September|October|November|December) />').Count -eq 12))
foreach ($bad in 'every 7 minutes', 'every 5 minute', 'every 60 minutes', 'hourly 01:00', 'daily 24:00', 'daily 2:30', 'daily 02.30', 'weekly Sun 03:00', 'weekly sun',
                 'weekly sunday 03:00', 'monthly 29 04:00', 'monthly 0 04:00', 'monthly 01 04:00', 'yearly', '', 'daily 02:30 extra') {
    Row "S3 '$bad' is no schedule" ($null -eq (Get-JobSchedule ($bad -split ' ')))
}

# X: the task the helper would register
$s = Get-JobSchedule @('daily', '02:30')
$xmlText = Get-JobTaskXml 'nightly' 'backup-all' $s 'S-1-5-21-1-2-3-1001' 'C:\Program Files\SD & Co\usr\bin\sd.exe' 'C:\ProgramData\SD\sdsys'
$x = $null
try { $x = [xml]$xmlText } catch { }
Row 'X1 the task XML is well-formed (a path holding & is escaped)' ($null -ne $x) $xmlText.Substring(0, [Math]::Min(200, $xmlText.Length))
if ($null -ne $x) {
    $ns = New-Object Xml.XmlNamespaceManager($x.NameTable); $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
    $v = { param($p) $n = $x.SelectSingleNode($p, $ns); if ($null -eq $n) { '<none>' } else { $n.InnerText } }
    Row 'X2 the task runs as the SID it is given, with no stored password (S4U), elevated (HighestAvailable)' (((& $v '//t:Principal/t:UserId') -ceq 'S-1-5-21-1-2-3-1001') -and ((& $v '//t:Principal/t:LogonType') -ceq 'S4U') -and ((& $v '//t:Principal/t:RunLevel') -ceq 'HighestAvailable') -and ($xmlText -notmatch '<Password'))
    Row 'X3 a missed run is not made up and a run still going is not doubled' (((& $v '//t:Settings/t:StartWhenAvailable') -ceq 'false') -and ((& $v '//t:Settings/t:MultipleInstancesPolicy') -ceq 'IgnoreNew'))
    Row 'X4 the action is sd.exe -job NAME and the job''s own command, in the SDSYS directory' (((& $v '//t:Exec/t:Command') -ceq 'C:\Program Files\SD & Co\usr\bin\sd.exe') -and ((& $v '//t:Exec/t:Arguments') -ceq '-job nightly backup.account all') -and ((& $v '//t:Exec/t:WorkingDirectory') -ceq 'C:\ProgramData\SD\sdsys')) (& $v '//t:Exec/t:Arguments')
    Row 'X5 the trigger is the schedule''s' ($xmlText.Contains($s.Trigger))
}

# D: the definition text
$d = Get-JobText 'nightly' 'backup-all' 'daily 02:30'
Row 'D1 the definition is a comment line, then name, job, command and schedule, LF line ends' ($d -ceq "# an SD scheduled job, written by sd-jobs.ps1 job-set; changed only by sd-jobs.ps1 job-set and job-delete`nname=nightly`njob=backup-all`ncommand=backup.account all`nschedule=daily 02:30`n") $d

# ---------------------------------------------------------------- the whole script, in its dry run, on a scratch folder
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("jobs-helper-" + [Guid]::NewGuid().ToString('N'))
$jd = Join-Path $tmp 'sd-jobs'
Write-Output "test-jobs-helper-units: scratch $jd"
function Run-Helper([string[]]$words, [switch]$NoDry) {
    $a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $subject)
    if (-not $NoDry) { $a += @('-DryRun', '-TestJobsDir', $jd) }
    $a += $words
    $ErrorActionPreference = 'Continue'      # the helper prints on stdout only; stderr is not merged (a native stderr line would be an ErrorRecord in 5.1)
    $o = & powershell.exe @a | ForEach-Object { "$_" }
    return @{ Rc = $LASTEXITCODE; Out = @($o); Cmd = ($a -join ' ') }
}
function Has($r, [string]$line) { return (@($r.Out) -ccontains $line) }
try {
    $r = Run-Helper @('job-set', 'nightly', 'backup-all', 'daily', '02:30')
    Write-Output "  ran: $($r.Cmd) -> exit $($r.Rc)"
    Row 'R1 job-set makes the definition and says created, then is scheduled (exit 0)' (($r.Rc -eq 0) -and (Has $r 'sd-jobs: job nightly created') -and (Has $r 'sd-jobs: job nightly is scheduled: daily 02:30')) ($r.Out -join ' | ')
    $f = Join-Path $jd 'nightly'
    Row 'R2 the definition written is exactly Get-JobText''s, in ASCII' ((Test-Path -LiteralPath $f) -and ([IO.File]::ReadAllText($f) -ceq (Get-JobText 'nightly' 'backup-all' 'daily 02:30')))
    Row 'R3 the description lines come first and say what is about to be done' ((@($r.Out)[0] -clike 'sd-jobs: job-set nightly: runs "backup.account all" (backup-all) daily 02:30*') -and (@($r.Out)[1] -clike 'sd-jobs: then: task \SD\sdcore-job-nightly*')) (@($r.Out)[0..1] -join ' | ')
    Row 'R4 the dry run says it registers nothing' (Has $r 'sd-jobs: dry run: the task is not registered; it would be:')
    $r = Run-Helper @('job-list')
    Row 'R5 job-list shows the job in SET.JOB''s shape' (($r.Rc -eq 0) -and (Has $r 'job nightly: daily 02:30: backup.account all (backup-all)')) ($r.Out -join ' | ')
    $r = Run-Helper @('job-set', 'nightly', 'update-accounts', 'every', '15', 'minutes')
    Row 'R6 job-set on an existing name replaces it' (($r.Rc -eq 0) -and (Has $r 'sd-jobs: job nightly replaced') -and (Has $r 'sd-jobs: job nightly is scheduled: every 15 minutes')) ($r.Out -join ' | ')
    $r = Run-Helper @('job-run', 'nightly')
    Row 'R7 job-run of a job says started (the dry run starts nothing)' (($r.Rc -eq 0) -and (Has $r 'sd-jobs: job nightly started') -and (Has $r 'sd-jobs: dry run: the task is not started')) ($r.Out -join ' | ')
    $r = Run-Helper @('job-run', 'other')
    Row 'R8 job-run of no such job: nothing was started, exit 0' (($r.Rc -eq 0) -and (Has $r 'sd-jobs: no job named other; nothing was started')) ($r.Out -join ' | ')
    $r = Run-Helper @('job-state', 'nightly')
    Row 'R9 job-state answers next= and last= (the dry run asks Task Scheduler nothing)' (($r.Rc -eq 0) -and (Has $r 'next=not scheduled') -and (Has $r 'last=never')) ($r.Out -join ' | ')

    foreach ($c in @(@(@('job-set', 'Nightly', 'backup-all', 'hourly'), 'a job name is'), @(@('job-set', 'nightly', 'shell', 'hourly'), 'the command of a job is one of'),
                     @(@('job-set', 'nightly', 'backup-all', 'daily', '25:00'), 'the schedule is none of'), @(@('job-set', 'nightly', 'backup-all'), 'job-set takes'),
                     @(@('job-delete', 'a-'), 'a job name is'), @(@('job-run'), 'job-run takes'), @(@('job-list', 'x'), 'job-list takes nothing'))) {
        $r = Run-Helper $c[0]
        $hit = @($r.Out | Where-Object { $_ -clike "sd-jobs: $($c[1])*" }).Count -gt 0
        Row "R10 refused, exit 1, with sd-jobs: $($c[1]) ...: $($c[0] -join ' ')" (($r.Rc -eq 1) -and $hit) ($r.Out -join ' | ')
    }
    $r = Run-Helper @('frobnicate')
    Row 'R11 an unknown verb is a usage error (exit 2)' ($r.Rc -eq 2) ($r.Out -join ' | ')

    # damaged definitions
    [IO.File]::WriteAllText($f, "name=nightly`njob=backup-all`ncommand=backup.account all`nschedule=daily 02:31:00`n", [Text.Encoding]::ASCII)
    $r = Run-Helper @('job-list')
    Row 'R12 a definition whose schedule the helper would not have written is damaged (does not agree)' (Has $r 'damaged nightly: the definition does not agree with the helper') ($r.Out -join ' | ')
    $r = Run-Helper @('job-run', 'nightly')
    Row 'R13 a damaged job is not started (exit 1)' (($r.Rc -eq 1) -and (Has $r 'sd-jobs: job nightly is damaged; nothing was started (job-set writes it again, job-delete removes it)')) ($r.Out -join ' | ')
    [IO.File]::WriteAllText($f, "name=nightly`njob=backup-all`ncommand=backup.account all`nschedule=daily 02:30`nschedule=daily 02:30`n", [Text.Encoding]::ASCII)
    $r = Run-Helper @('job-list')
    Row 'R14 a doubled line is damaged' (Has $r 'damaged nightly: damaged') ($r.Out -join ' | ')
    [IO.File]::WriteAllText($f, "name=nightly`njob=backup-all`ncommand=sh -c x`nschedule=daily 02:30`n", [Text.Encoding]::ASCII)
    $r = Run-Helper @('job-list')
    Row 'R15 a command that is not the job id''s own is damaged' (Has $r 'damaged nightly: the definition does not agree with the helper') ($r.Out -join ' | ')
    [IO.File]::WriteAllText((Join-Path $jd 'Bad'), "x`n", [Text.Encoding]::ASCII)
    New-Item -ItemType Directory -Path (Join-Path $jd 'adir') | Out-Null
    $r = Run-Helper @('job-list')
    Row 'R16 a file whose name is not a job name, and a directory under a job name, are listed as damaged' ((Has $r 'damaged Bad: not a job name') -and (Has $r 'damaged adir: not a plain file')) ($r.Out -join ' | ')
    $r = Run-Helper @('job-delete', 'adir')
    Row 'R17 job-delete leaves a directory under a job name as it is (exit 1)' (($r.Rc -eq 1) -and (Test-Path -LiteralPath (Join-Path $jd 'adir'))) ($r.Out -join ' | ')
    $r = Run-Helper @('job-set', 'nightly', 'backup-all', 'daily', '02:30')
    Row 'R18 job-set writes a damaged definition again' (($r.Rc -eq 0) -and ([IO.File]::ReadAllText($f) -ceq (Get-JobText 'nightly' 'backup-all' 'daily 02:30'))) ($r.Out -join ' | ')
    $r = Run-Helper @('job-delete', 'nightly')
    Row 'R19 job-delete removes the definition and says deleted' (($r.Rc -eq 0) -and (Has $r 'sd-jobs: job nightly deleted') -and -not (Test-Path -LiteralPath $f)) ($r.Out -join ' | ')
    $r = Run-Helper @('job-delete', 'nightly')
    Row 'R20 job-delete of no such job: nothing was changed, exit 0' (($r.Rc -eq 0) -and (Has $r 'sd-jobs: no job named nightly; nothing was changed')) ($r.Out -join ' | ')

    # the limit: 32 jobs (Bad is not a job name and is not counted; adir is taken out first)
    Remove-Item -LiteralPath (Join-Path $jd 'adir') -Force
    1..32 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $jd ("j$_")), (Get-JobText "j$_" 'backup-all' 'hourly'), [Text.Encoding]::ASCII) }
    $r = Run-Helper @('job-set', 'one-more', 'backup-all', 'hourly')
    Row 'R21 a 33rd job is refused' (($r.Rc -eq 1) -and (@($r.Out | Where-Object { $_ -clike 'sd-jobs: there are already 32 jobs*' }).Count -eq 1) -and -not (Test-Path -LiteralPath (Join-Path $jd 'one-more'))) ($r.Out -join ' | ')

    # P: job-purge, the uninstaller's verb.  The dry run takes the scratch definitions and asks Task Scheduler nothing.  The folder holds j1..j32 and Bad.
    $r = Run-Helper @('job-purge', 'x')
    Row 'P1 job-purge takes nothing (exit 1), and then removes nothing' (($r.Rc -eq 1) -and (Has $r 'sd-jobs: job-purge takes nothing') -and (Test-Path -LiteralPath (Join-Path $jd 'j1'))) ($r.Out -join ' | ')
    New-Item -ItemType Directory -Path (Join-Path $jd 'adir') | Out-Null
    $r = Run-Helper @('job-purge')
    Write-Output "  ran: $($r.Cmd) -> exit $($r.Rc); left in the folder: $((@(Get-ChildItem -LiteralPath $jd -Force | ForEach-Object { $_.Name })) -join ',')"
    Row 'P2 job-purge takes every plain file, leaves a directory and the folder holding it, and does not say removed (exit 1)' (($r.Rc -eq 1) -and (Has $r 'sd-jobs: adir is not a plain file; it was left as it is') -and (Has $r 'sd-jobs: not everything was removed; see the lines above') -and -not (Has $r 'sd-jobs: the scheduled jobs are removed') -and (Test-Path -LiteralPath (Join-Path $jd 'adir')) -and (@(Get-ChildItem -LiteralPath $jd -Force -File).Count -eq 0)) ($r.Out -join ' | ')
    Remove-Item -LiteralPath (Join-Path $jd 'adir') -Force
    [IO.File]::WriteAllText((Join-Path $jd 'nightly'), (Get-JobText 'nightly' 'backup-all' 'hourly'), [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $jd 'Bad'), "x`n", [Text.Encoding]::ASCII)
    $r = Run-Helper @('job-purge')
    Write-Output "  ran: $($r.Cmd) -> exit $($r.Rc); the folder is there: $(Test-Path -LiteralPath $jd)"
    Row 'P3 job-purge removes the definitions and their folder and says so; the dry run removes no task (exit 0)' (($r.Rc -eq 0) -and (Has $r 'sd-jobs: dry run: no task is removed') -and (Has $r 'sd-jobs: the scheduled jobs are removed') -and -not (Test-Path -LiteralPath $jd)) ($r.Out -join ' | ')
    $r = Run-Helper @('job-purge')
    Row 'P4 job-purge with no folder: exit 0 and the same success line' (($r.Rc -eq 0) -and (Has $r 'sd-jobs: the scheduled jobs are removed')) ($r.Out -join ' | ')

    # C: the real (not dry) run refuses a test folder before it does anything
    $r = Run-Helper @('-TestJobsDir', $jd, 'job-list') -NoDry
    Row 'C1 -TestJobsDir without -DryRun is refused (exit 1) before anything is asked of Windows' (($r.Rc -eq 1) -and (Has $r 'sd-jobs: -TestJobsDir is for a dry run only')) ($r.Out -join ' | ')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# T: what the text says (the parts a dry run cannot reach)
$main = $text.Substring($e)
$setBlock = $main.Substring($main.IndexOf("'job-set' {"), $main.IndexOf("'job-delete' {") - $main.IndexOf("'job-set' {"))
Row 'T1 job-set''s dry run exits before Register-ScheduledTask, and the dry run reaches no other scheduler cmdlet' (($setBlock.IndexOf('if ($DryRun) {') -lt $setBlock.IndexOf('Register-ScheduledTask')) -and ($setBlock.IndexOf('if ($DryRun) {') -gt 0))
Row 'T2 the caller must be the local SDSYS by SID and elevated (S-1-5-32-544 in the token), outside the dry run' ($main.Contains('Translate([Security.Principal.SecurityIdentifier]).Value') -and $main.Contains('if ($me.User.Value -ne $sdsysSid)') -and $main.Contains("IsInRole([Security.Principal.SecurityIdentifier]'S-1-5-32-544')"))
Row 'T3 the real directory is named from the registry (GetFolderPath CommonApplicationData), never from SD_CONFIG or %ProgramData%' ($main.Contains("[Environment]::GetFolderPath('CommonApplicationData')") -and -not $text.Contains('$env:SD_CONFIG') -and -not $text.Contains('$env:ProgramData'))
Row 'T4 the directory is made WITH its ACL (protected, SYSTEM and Administrators, owner Administrators) and checked by Test-JobAdminPath before use' ($main.Contains('SetAccessRuleProtection($true, $false)') -and $main.Contains('[IO.Directory]::CreateDirectory($jobsDir, $ds)') -and $main.Contains("SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))") -and $main.Contains('if (-not (Test-JobAdminPath $jobsDir $true))'))
# 10 Nov 26 (the owner's sitting on cycle 20261110-215945): job-set wrote the file with no owner, so it took its creator's, ace\SDSYS, and set.job run
# called the job it had just made damaged; every run of it was refused at LOGIN.  The dry run skips ACLs, so only the text can hold this.
$iOwn = $setBlock.IndexOf('GetAccessControl([Security.AccessControl.AccessControlSections]::Owner)')
$iMove = $setBlock.IndexOf('[IO.File]::Move($tmp, $target)')
$iPost = $setBlock.IndexOf('if (-not $DryRun -and -not (Test-JobAdminPath $target $false)) { Exit-Refused "job $n was written')
$iSaid = $setBlock.IndexOf('Out-Line "${Prog}: job $n $(if ($existed)')
Row 'T9 job-set makes the new file the administrators'' (owner Administrators, only the owner part written) BEFORE it is moved into place, then checks the result with Test-JobAdminPath and refuses before it says created' (($iOwn -gt 0) -and ($iOwn -lt $iMove) -and $setBlock.Contains('$fsec.SetOwner((New-Object Security.Principal.SecurityIdentifier(''S-1-5-32-544'')))') -and ($iPost -gt $iMove) -and ($iSaid -gt $iPost)) "own $iOwn move $iMove check $iPost said $iSaid"
$adm = $text.Substring($text.IndexOf('function Test-JobAdminPath'), $text.IndexOf('function Read-JobRows') - $text.IndexOf('function Test-JobAdminPath'))
Row 'T5 the ACL rule is the kernel''s: no reparse point, the right kind, owner SYSTEM or Administrators, no other allowed SID' ($adm.Contains('ReparsePoint') -and $adm.Contains("@('S-1-5-18', 'S-1-5-32-544')") -and $adm.Contains('if ($ok -notcontains $owner)') -and $adm.Contains('if ($ok -notcontains $r.IdentityReference.Value)'))
Row 'T6 the task XML has no Password element and the principal is S4U at the highest run level' ($text.Contains('<LogonType>S4U</LogonType><RunLevel>HighestAvailable</RunLevel>') -and -not $text.Contains('<Password>'))
$iPurgeIf = $main.IndexOf("if (`$Action -cne 'job-purge') {"); $iSdsys = $main.IndexOf('if ($me.User.Value -ne $sdsysSid)'); $iRole = $main.IndexOf("IsInRole([Security.Principal.SecurityIdentifier]'S-1-5-32-544')")
Row 'T7 job-purge alone is spared the SDSYS test (the test sits under "if ($Action -cne ''job-purge'')"); the elevation test follows it for every verb' (($iPurgeIf -gt 0) -and ($iPurgeIf -lt $iSdsys) -and ($iSdsys -lt $iRole) -and ([regex]::Matches($main, [regex]::Escape("-cne 'job-purge'")).Count -eq 1)) "$iPurgeIf $iSdsys $iRole"
$iP = $main.IndexOf("'job-purge' {"); $iD = $main.IndexOf('default {')
$purge = if ($iP -gt 0 -and $iD -gt $iP) { $main.Substring($iP, $iD - $iP) } else { '' }
Row 'T8 job-purge''s dry run reaches no scheduler cmdlet, the tasks go before the definitions, and nothing in it deletes recursively' (($purge -ne '') -and ($purge.IndexOf('if ($DryRun) {') -gt 0) -and ($purge.IndexOf('if ($DryRun) {') -lt $purge.IndexOf('Get-ScheduledTask')) -and ($purge.IndexOf('Unregister-ScheduledTask') -lt $purge.IndexOf('Remove-Item')) -and (-not $purge.Contains('-Recurse')) -and $purge.Contains('[IO.Directory]::Delete($jobsDir, $false)')) "purge block $($purge.Length) characters"

$fails = 0
foreach ($row in $script:rows) {
    $tag = if ($row[1]) { 'PASS' } else { 'FAIL' }
    if (-not $row[1]) { $fails++ }
    $tail = if (-not $row[1] -and $row[2]) { "  <- $($row[2])" } else { '' }
    Write-Output "  [$tag] $($row[0])$tail"
}
if ($script:rows.Count -lt 40) { Write-Output "test-jobs-helper-units: FAILED - only $($script:rows.Count) rows (the null case)"; exit 1 }
Write-Output "test-jobs-helper-units: $($script:rows.Count - $fails) passed, $fails failed"
if ($fails -gt 0) { exit 1 }
exit 0
