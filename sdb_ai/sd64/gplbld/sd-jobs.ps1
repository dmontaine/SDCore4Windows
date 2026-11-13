# sd-jobs.ps1 - the administrator's scheduled jobs, on Windows Task Scheduler
#
# 13 Nov 26 Windows port - RELEASE_1.1 202: the definitions named radmin-<nonce> are the remote administration broker's one-shot jobs
# (sd-radmin.ps1 writes one, REMOTE.SDSYS RUN deletes it as it starts): job-list and job-run do not see them, they do not count towards
# the 32, and job-set refuses a name that starts radmin-.
#
# 10 Nov 26 (RELEASE_1.1 222, the owner's sitting on cycle 20261110-215945) - job-set gives a new definition the owner Administrators, as the
# folder has, and checks the result before it says created.  The file used to take its creator's owner, ace\SDSYS, so set.job run called the
# job it had just made damaged and every run of it was refused at LOGIN; the dry run skips ACLs, so the guard could not see it (now its T9).
#
# 10 Nov 26 Windows port - from Linux 944d6ed3, 5162a5d1, d049d8bb (S.102 stages 2 to 4), carry area 14.  The Windows shape of the job verbs
# of Linux's root helper (gplbld/sd-elevate there: job-set, job-delete, job-list, job-run), with Task Scheduler in place of systemd timers:
#
#   sd-jobs.ps1 job-set NAME JOB SCHEDULE...   defines or replaces a job: its definition, then the task \SD\sdcore-job-NAME
#   sd-jobs.ps1 job-delete NAME                removes the task, then the definition
#   sd-jobs.ps1 job-list                       the defined jobs, one line each ("job NAME: SCHEDULE: COMMAND (JOB)" or "damaged NAME: WHY")
#   sd-jobs.ps1 job-run NAME                   starts the job's task now, exactly as its trigger would
#   sd-jobs.ps1 job-state NAME                 "next=..." and "last=..." from Task Scheduler (read only)
#   sd-jobs.ps1 job-purge                      the uninstaller's: removes every job's task, then the definitions and their directory
#
# Called by SET.JOB (gpl.bp/set_job) from the administrator's session, which is elevated already (an SDSYS session is elevated or it is
# nothing), so nothing here asks for elevation: it REFUSES unless the caller is the local Windows account SDSYS with an elevated token,
# which is Linux's job_caller ("sudo says the caller is sdsys") in a Windows shape.
#
# job-purge ALONE IS NOT SET.JOB'S.  The uninstaller (sd.iss RemoveScheduledJobs) runs it as the administrator who is uninstalling, who is
# not SDSYS, so it asks for an elevated Administrators token and no more.  It only removes, as Linux's deletesdcore.sh does (S.102 stage
# 3: the timers and units first, then /etc/sdcore/jobs.d): a task left behind would start a program that is gone.  Its success line is
# "sd-jobs: the scheduled jobs are removed"; anything it had to leave is named, and the exit is then 1.
#
# THE COMMAND IS CHOSEN FROM A LIST THIS SCRIPT OWNS, by an id, and is never text a caller supplies: backup-all (backup.account all) and
# update-accounts (update.accounts all).  THE SCHEDULE IS ONE OF FIVE SHAPES turned into a Task Scheduler trigger here: every
# 5|10|15|20|30 minutes, hourly, daily HH:MM, weekly mon..sun HH:MM, monthly 1..28 HH:MM (the machine's time).  THE NAME is 1 to 32
# characters, a lower case letter first, then lower case letters, digits and dashes, not ending in a dash; at most 32 jobs.
#
# THE DEFINITIONS are plain files in <ProgramData>\SD\sd-jobs, a directory SYSTEM and Administrators only (inheritance removed; the data
# tree above grants sdusers Modify).  This script makes it on first use, and refuses to use one that is a link, or owned or open to
# anybody else - so an SD user who made it first gains nothing.  The kernel (K$JOB.MARK, gplsrc/win32jobmark.c) reads the same
# directory under the same rule, named the same way: from the registry ([Environment]::GetFolderPath), never from SD_CONFIG.
#
# THE TASK runs <app>\usr\bin\sd.exe -job NAME <command> in <ProgramData>\SD\sdsys as the local account SDSYS, "whether the user is
# logged on or not" WITHOUT A STORED PASSWORD (LogonType S4U) and at the highest run level, so its process is an elevated batch logon of
# SDSYS: what K$JOB.MARK asks for.  No missed run is made up (StartWhenAvailable false, Linux's Persistent=false), and a run still going
# when the next is due is not doubled (IgnoreNew).
#
# THE SUCCESS LINES SET.JOB ANCHORS ON: "sd-jobs: job NAME is scheduled: SCHEDULE", "sd-jobs: job NAME deleted", "sd-jobs: job NAME
# started"; "no job named NAME; nothing was changed|started" is exit 0, as on Linux.  Every refusal is "sd-jobs: <why>" and exit 1.
# The lines that describe what is about to be done ("sd-jobs: job-set NAME: ...", "sd-jobs: then: ...") say nothing about the outcome.
#
# -DryRun (with -TestJobsDir, a scratch folder) is for gplbld/test-jobs-helper-units.ps1: it skips the caller and ACL tests, works on
# the scratch folder, and NEVER touches Task Scheduler - the task it would register is printed instead.  Without -DryRun, -TestJobsDir
# is refused.
#
# NOTHING IS SCHEDULED AS DELIVERED.  A job exists only after an administrator defines one.

param(
    [Parameter(Position = 0)][string]$Action = '',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Words = @(),
    [switch]$DryRun,
    [string]$TestJobsDir = ''
)

# Windows PowerShell's own module folders, as gpl.bp/ps_scripto sets them for SD's scripts: started by hand from a PowerShell 7 window this
# would inherit PowerShell 7's, where Get-Acl (below) fails to load (RELEASE_1.1 111; held by test-psmodulepath-units.ps1).
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"

$ErrorActionPreference = 'Stop'
$Prog = 'sd-jobs'

# BEGIN jobs_functions
$JobMax = 32
$JobKeys = @('name', 'job', 'command', 'schedule')
$JobTaskPath = '\SD\'

function Get-JobCommand([string]$id) {
    # The SD command line a job id stands for; '' for any other id.
    switch -CaseSensitive ($id) {
        'backup-all'      { return 'backup.account all' }
        'update-accounts' { return 'update.accounts all' }
    }
    return ''
}

function Test-JobName([string]$n) {
    return ($n -cmatch '^[a-z]([a-z0-9-]{0,30}[a-z0-9])?$')
}

function Test-JobTime([string]$t) {
    return ($t -cmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$')
}

function Get-JobSchedule([string[]]$w) {
    # @{ Sched = the schedule in its one spelling; Trigger = the Task Scheduler trigger XML } or $null for anything else.
    if ($null -eq $w) { $w = @() }
    $w = @($w | Where-Object { $_ -ne '' })
    $start = '2026-01-01T'
    $on = '<Enabled>true</Enabled>'
    if ($w.Count -lt 1) { return $null }
    switch -CaseSensitive ($w[0]) {
        'every' {
            if ($w.Count -ne 3 -or $w[2] -cne 'minutes' -or ($w[1] -cnotmatch '^(5|10|15|20|30)$')) { return $null }
            return @{ Sched = "every $($w[1]) minutes"
                      Trigger = "<TimeTrigger><Repetition><Interval>PT$($w[1])M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><StartBoundary>${start}00:00:00</StartBoundary>$on</TimeTrigger>" }
        }
        'hourly' {
            if ($w.Count -ne 1) { return $null }
            return @{ Sched = 'hourly'
                      Trigger = "<TimeTrigger><Repetition><Interval>PT1H</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><StartBoundary>${start}00:00:00</StartBoundary>$on</TimeTrigger>" }
        }
        'daily' {
            if ($w.Count -ne 2 -or -not (Test-JobTime $w[1])) { return $null }
            return @{ Sched = "daily $($w[1])"
                      Trigger = "<CalendarTrigger><StartBoundary>$start$($w[1]):00</StartBoundary>$on<ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>" }
        }
        'weekly' {
            $days = @{ mon = 'Monday'; tue = 'Tuesday'; wed = 'Wednesday'; thu = 'Thursday'; fri = 'Friday'; sat = 'Saturday'; sun = 'Sunday' }
            if ($w.Count -ne 3 -or ($w[1] -cnotmatch '^(mon|tue|wed|thu|fri|sat|sun)$') -or -not (Test-JobTime $w[2])) { return $null }
            return @{ Sched = "weekly $($w[1]) $($w[2])"
                      Trigger = "<CalendarTrigger><StartBoundary>$start$($w[2]):00</StartBoundary>$on<ScheduleByWeek><DaysOfWeek><$($days[$w[1]]) /></DaysOfWeek><WeeksInterval>1</WeeksInterval></ScheduleByWeek></CalendarTrigger>" }
        }
        'monthly' {
            if ($w.Count -ne 3 -or ($w[1] -cnotmatch '^([1-9]|1[0-9]|2[0-8])$') -or -not (Test-JobTime $w[2])) { return $null }
            $months = '<January /><February /><March /><April /><May /><June /><July /><August /><September /><October /><November /><December />'
            return @{ Sched = "monthly $($w[1]) $($w[2])"
                      Trigger = "<CalendarTrigger><StartBoundary>$start$($w[2]):00</StartBoundary>$on<ScheduleByMonth><DaysOfMonth><Day>$($w[1])</Day></DaysOfMonth><Months>$months</Months></ScheduleByMonth></CalendarTrigger>" }
        }
    }
    return $null
}

function Get-JobText([string]$n, [string]$id, [string]$sched) {
    # The definition file: LF line ends, ASCII, nothing a caller typed but the name (checked) and the schedule (re-spelt by Get-JobSchedule).
    $lines = @('# an SD scheduled job, written by sd-jobs.ps1 job-set; changed only by sd-jobs.ps1 job-set and job-delete',
               "name=$n", "job=$id", "command=$(Get-JobCommand $id)", "schedule=$sched")
    return (($lines -join "`n") + "`n")
}

function Get-JobTaskXml([string]$n, [string]$id, [hashtable]$s, [string]$userSid, [string]$sdExe, [string]$workDir) {
    $e = { param($t) [Security.SecurityElement]::Escape($t) }
    $cmd = Get-JobCommand $id
    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>SD scheduled job $n`: $cmd ($($s.Sched)); written by sd-jobs.ps1 job-set, changed only by sd-jobs.ps1</Description></RegistrationInfo>
  <Triggers>$($s.Trigger)</Triggers>
  <Principals><Principal id="Author"><UserId>$(& $e $userSid)</UserId><LogonType>S4U</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author"><Exec><Command>$(& $e $sdExe)</Command><Arguments>-job $n $cmd</Arguments><WorkingDirectory>$(& $e $workDir)</WorkingDirectory></Exec></Actions>
</Task>
"@
}

function Test-JobAdminPath([string]$path, [bool]$wantDir) {
    # The kernel's win32_job_admin_path(): not a link, the right kind, owned by SYSTEM or Administrators, nobody else allowed anything.
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    if ($wantDir -ne $item.PSIsContainer) { return $false }
    $ok = @('S-1-5-18', 'S-1-5-32-544')
    try {
        $acl = Get-Acl -LiteralPath $path
        $owner = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { return $false }
    if ($ok -notcontains $owner) { return $false }
    foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        if ($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        if ($ok -notcontains $r.IdentityReference.Value) { return $false }
    }
    return $true
}

function Read-JobRows([string]$dir, [scriptblock]$safe) {
    # One row per entry of the directory: @{ Kind = 'JOB' or 'BAD'; Name; Why or the four fields }.  $safe is the file test (the ACL in
    # earnest, everything in a dry run).
    $rows = @()
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return ,$rows }
    foreach ($it in @(Get-ChildItem -LiteralPath $dir -Force | Sort-Object Name)) {
        $n = $it.Name
        if ($n.StartsWith('.')) { continue }
        if ($n.StartsWith('radmin-')) { continue }      # 13 Nov 26 - the remote administration broker's one-shot jobs (RELEASE_1.1 202)
        if (-not (Test-JobName $n)) { $rows += @{ Kind = 'BAD'; Name = $n; Why = 'not a job name' }; continue }
        if ($it.PSIsContainer -or ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $rows += @{ Kind = 'BAD'; Name = $n; Why = 'not a plain file' }; continue }
        if (-not (& $safe $it.FullName)) { $rows += @{ Kind = 'BAD'; Name = $n; Why = 'not the administrators'' file' }; continue }
        $raw = [IO.File]::ReadAllBytes($it.FullName)
        $f = @{}
        $good = ($raw.Length -le 4096) -and ($raw -notcontains 0)
        if ($good) {
            foreach ($line in ([Text.Encoding]::ASCII.GetString($raw) -split "`n")) {
                $line = $line.TrimEnd("`r")
                if ($line -eq '' -or $line.StartsWith('#')) { continue }
                $k = $line.IndexOf('=')
                if ($k -lt 1) { $good = $false; continue }
                $key = $line.Substring(0, $k)
                if (($JobKeys -cnotcontains $key) -or $f.ContainsKey($key)) { $good = $false }
                $f[$key] = $line.Substring($k + 1)
            }
        }
        foreach ($key in $JobKeys) { if (-not $f.ContainsKey($key)) { $good = $false } }
        if (-not $good) { $rows += @{ Kind = 'BAD'; Name = $n; Why = 'damaged' }; continue }
        $rows += @{ Kind = 'JOB'; Name = $n; FName = $f['name']; FJob = $f['job']; FCmd = $f['command']; FSched = $f['schedule'] }
    }
    return ,$rows
}

function Format-JobListLine([hashtable]$row) {
    # One line of job-list.  A definition that does not agree with this script's own tables is shown as damaged.
    if ($row.Kind -eq 'BAD') { return "damaged $($row.Name): $($row.Why)" }
    $cmd = Get-JobCommand $row.FJob
    $s = Get-JobSchedule (@($row.FSched -split ' '))
    if (($row.FName -ceq $row.Name) -and ($cmd -ne '') -and ($row.FCmd -ceq $cmd) -and ($null -ne $s) -and ($s.Sched -ceq $row.FSched)) {
        return "job $($row.Name): $($row.FSched): $($row.FCmd) ($($row.FJob))"
    }
    return "damaged $($row.Name): the definition does not agree with the helper"
}
# END jobs_functions

function Out-Line([string]$t) { [Console]::Out.WriteLine($t) }
function Exit-Refused([string]$why) {
    [Console]::Out.WriteLine("${Prog}: $why")
    exit 1
}

try {
    # ---------------------------------------------------------------- where, and who is asking
    if ($TestJobsDir -ne '' -and -not $DryRun) { Exit-Refused '-TestJobsDir is for a dry run only' }
    $base = [Environment]::GetFolderPath('CommonApplicationData')
    if ($base -eq '') { Exit-Refused 'the ProgramData folder could not be named' }
    $jobsDir = Join-Path $base 'SD\sd-jobs'
    if ($DryRun) {
        if ($TestJobsDir -eq '') { Exit-Refused 'a dry run takes -TestJobsDir' }
        $jobsDir = $TestJobsDir
        $safe = { param($p) $true }
    } else {
        $safe = { param($p) Test-JobAdminPath $p $false }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent()
        # job-purge is the uninstaller's and only removes, so any elevated administrator may ask for it.  Every other verb is SDSYS's alone.
        if ($Action -cne 'job-purge') {
            try {
                $sdsysSid = (New-Object Security.Principal.NTAccount("$([Environment]::MachineName)\SDSYS")).Translate([Security.Principal.SecurityIdentifier]).Value
            } catch { Exit-Refused 'there is no local account SDSYS' }
            if ($me.User.Value -ne $sdsysSid) { Exit-Refused 'the scheduled jobs are the administrator''s (the Windows account SDSYS); this was asked for by another account' }
        }
        if (-not ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.SecurityIdentifier]'S-1-5-32-544')) { Exit-Refused 'this session is not elevated' }
    }
    $sdExe = Join-Path $PSScriptRoot 'usr\bin\sd.exe'
    $workDir = Join-Path $base 'SD\sdsys'

    switch -CaseSensitive ($Action) {
        'job-set' {
            if ($Words.Count -lt 3) { Exit-Refused 'job-set takes a name, a job and a schedule: job-set NAME JOB every 15 minutes | hourly | daily 02:30 | weekly sun 03:00 | monthly 1 04:00' }
            $n = $Words[0]; $id = $Words[1]
            if (-not (Test-JobName $n)) { Exit-Refused 'a job name is 1 to 32 characters: a lower case letter first, then lower case letters, digits and dashes, not ending in a dash' }
            if ($n.StartsWith('radmin-')) { Exit-Refused 'a job name that starts radmin- is the remote administration broker''s; choose another' }
            if ((Get-JobCommand $id) -eq '') { Exit-Refused 'the command of a job is one of backup-all and update-accounts; it is not text a caller supplies' }
            $s = Get-JobSchedule ($Words[2..($Words.Count - 1)])
            if ($null -eq $s) { Exit-Refused 'the schedule is none of: every 5|10|15|20|30 minutes, hourly, daily HH:MM, weekly mon|tue|wed|thu|fri|sat|sun HH:MM, monthly D HH:MM (D 1 to 28)' }
            $cmd = Get-JobCommand $id
            Out-Line "${Prog}: job-set ${n}: runs `"$cmd`" ($id) $($s.Sched), definition in $jobsDir\$n"
            Out-Line "${Prog}: then: task ${JobTaskPath}sdcore-job-$n, as SDSYS, elevated, no stored password: $sdExe -job $n $cmd"

            # The directory: made here the first time, SYSTEM and Administrators only, owned by Administrators; refused in any other state.
            if (-not $DryRun) {
                if (-not (Test-Path -LiteralPath $jobsDir)) {
                    # Made WITH its ACL, in one call, so there is no moment at which it inherits the data tree's sdusers Modify.
                    $ds = New-Object Security.AccessControl.DirectorySecurity
                    $ds.SetAccessRuleProtection($true, $false)
                    $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
                    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
                        $ds.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
                            (New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
                    }
                    $ds.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
                    [IO.Directory]::CreateDirectory($jobsDir, $ds) | Out-Null
                }
                if (-not (Test-JobAdminPath $jobsDir $true)) { Exit-Refused "$jobsDir is a link, or is owned by or open to somebody other than SYSTEM and Administrators; it was left as it is" }
            } elseif (-not (Test-Path -LiteralPath $jobsDir -PathType Container)) {
                New-Item -ItemType Directory -Path $jobsDir | Out-Null
            }

            $target = Join-Path $jobsDir $n
            $existed = Test-Path -LiteralPath $target
            if ($existed) {
                $it = Get-Item -LiteralPath $target -Force
                if ($it.PSIsContainer -or ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Exit-Refused "$n is not a plain file; it was left as it is" }
                if (-not $DryRun -and -not (Test-JobAdminPath $target $false)) { Exit-Refused "$n is not the administrators' file; it was left as it is" }
            } else {
                $count = @(Get-ChildItem -LiteralPath $jobsDir -Force | Where-Object { (Test-JobName $_.Name) -and -not $_.Name.StartsWith('radmin-') }).Count
                if ($count -ge $JobMax) { Exit-Refused "there are already $JobMax jobs; delete one first" }
            }
            $tmp = Join-Path $jobsDir ".new.$PID"
            # No backup copy is kept.  [NullString]::Value and not $null: PowerShell hands $null to a String parameter as '', and Replace
            # answers "The path is not of a legal form" to that.  A write that fails leaves no .new file behind to be listed as damaged.
            try {
                [IO.File]::WriteAllText($tmp, (Get-JobText $n $id $s.Sched), [Text.Encoding]::ASCII)
                if (-not $DryRun) {
                    # A new file takes its CREATOR as owner (SDSYS here), which Test-JobAdminPath and the kernel's win32_job_admin_path() both
                    # refuse.  The owner becomes Administrators, as the folder's is (an elevated token may give that group); only the owner part
                    # is written, so the file's access rules stay the ones it inherits from the folder.
                    $fsec = (Get-Item -LiteralPath $tmp -Force).GetAccessControl([Security.AccessControl.AccessControlSections]::Owner)
                    $fsec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
                    (Get-Item -LiteralPath $tmp -Force).SetAccessControl($fsec)
                }
                if ($existed) { [IO.File]::Replace($tmp, $target, [NullString]::Value) } else { [IO.File]::Move($tmp, $target) }
            } finally {
                if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            }
            if (-not $DryRun -and -not (Test-JobAdminPath $target $false)) { Exit-Refused "job $n was written, but it is not the administrators' file (SYSTEM or Administrators must own it and nobody else be allowed anything); job-delete removes it" }
            Out-Line "${Prog}: job $n $(if ($existed) { 'replaced' } else { 'created' })"

            if ($DryRun) {
                Out-Line "${Prog}: dry run: the task is not registered; it would be:"
                Out-Line (Get-JobTaskXml $n $id $s 'S-1-5-21-0-0-0-0' $sdExe $workDir)
                Out-Line "${Prog}: job $n is scheduled: $($s.Sched)"
                exit 0
            }
            try {
                $xml = Get-JobTaskXml $n $id $s $sdsysSid $sdExe $workDir
                Register-ScheduledTask -TaskName "sdcore-job-$n" -TaskPath $JobTaskPath -Xml $xml -Force | Out-Null
            } catch {
                Out-Line "${Prog}: the definition of $n is written, but its task could not be registered ($($_.Exception.Message)); nothing will run until job-set succeeds"
                exit 1
            }
            Out-Line "${Prog}: job $n is scheduled: $($s.Sched)"
            exit 0
        }

        'job-delete' {
            if ($Words.Count -ne 1) { Exit-Refused 'job-delete takes the name of one job' }
            $n = $Words[0]
            if (-not (Test-JobName $n)) { Exit-Refused 'a job name is 1 to 32 characters: a lower case letter first, then lower case letters, digits and dashes, not ending in a dash' }
            Out-Line "${Prog}: job-delete ${n}: first: the task ${JobTaskPath}sdcore-job-$n is removed"
            Out-Line "${Prog}: then: removes $jobsDir\$n"
            if (-not $DryRun) {
                if ((Test-Path -LiteralPath $jobsDir) -and -not (Test-JobAdminPath $jobsDir $true)) { Exit-Refused "$jobsDir is a link, or is owned by or open to somebody other than SYSTEM and Administrators; it was left as it is" }
                $t = Get-ScheduledTask -TaskPath $JobTaskPath -TaskName "sdcore-job-$n" -ErrorAction SilentlyContinue
                if ($null -ne $t) { Unregister-ScheduledTask -TaskPath $JobTaskPath -TaskName "sdcore-job-$n" -Confirm:$false }
            }
            $target = Join-Path $jobsDir $n
            if (-not (Test-Path -LiteralPath $target)) {
                Out-Line "${Prog}: no job named $n; nothing was changed"
                exit 0
            }
            $it = Get-Item -LiteralPath $target -Force
            if ($it.PSIsContainer -or ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Exit-Refused "$n is not a plain file; it was left as it is" }
            Remove-Item -LiteralPath $target -Force
            Out-Line "${Prog}: job $n deleted"
            exit 0
        }

        'job-list' {
            if ($Words.Count -ne 0) { Exit-Refused 'job-list takes nothing' }
            Out-Line "${Prog}: job-list: the definitions in $jobsDir"
            if (-not $DryRun -and (Test-Path -LiteralPath $jobsDir) -and -not (Test-JobAdminPath $jobsDir $true)) { Exit-Refused "$jobsDir is a link, or is owned by or open to somebody other than SYSTEM and Administrators" }
            $rows = Read-JobRows $jobsDir $safe
            foreach ($r in $rows) { Out-Line (Format-JobListLine $r) }
            if ($rows.Count -eq 0) { Out-Line "${Prog}: no job is defined" }
            exit 0
        }

        'job-run' {
            if ($Words.Count -ne 1) { Exit-Refused 'job-run takes the name of one job' }
            $n = $Words[0]
            if (-not (Test-JobName $n)) { Exit-Refused 'a job name is 1 to 32 characters: a lower case letter first, then lower case letters, digits and dashes, not ending in a dash' }
            Out-Line "${Prog}: job-run ${n}: starts the task ${JobTaskPath}sdcore-job-$n, only when $jobsDir\$n is a job job-list shows"
            if (-not $DryRun -and (Test-Path -LiteralPath $jobsDir) -and -not (Test-JobAdminPath $jobsDir $true)) { Exit-Refused "$jobsDir is a link, or is owned by or open to somebody other than SYSTEM and Administrators; nothing was started" }
            $state = 'absent'
            foreach ($r in (Read-JobRows $jobsDir $safe)) {
                if ($r.Name -ceq $n) { $state = if ((Format-JobListLine $r).StartsWith("job ${n}: ")) { 'job' } else { 'damaged' } }
            }
            if ($state -eq 'damaged') { Exit-Refused "job $n is damaged; nothing was started (job-set writes it again, job-delete removes it)" }
            if ($state -eq 'absent') { Out-Line "${Prog}: no job named $n; nothing was started"; exit 0 }
            if ($DryRun) { Out-Line "${Prog}: dry run: the task is not started"; Out-Line "${Prog}: job $n started"; exit 0 }
            $t = Get-ScheduledTask -TaskPath $JobTaskPath -TaskName "sdcore-job-$n" -ErrorAction SilentlyContinue
            if ($null -eq $t) { Out-Line "${Prog}: no job named $n; nothing was started"; exit 0 }
            try { Start-ScheduledTask -TaskPath $JobTaskPath -TaskName "sdcore-job-$n" } catch { Exit-Refused "Task Scheduler did not start job ${n}: $($_.Exception.Message)" }
            Out-Line "${Prog}: job $n started"
            exit 0
        }

        'job-state' {
            # Read only, and what Task Scheduler says; "next=not scheduled" and "last=never" for a task it does not know.
            if ($Words.Count -ne 1 -or -not (Test-JobName $Words[0])) { Exit-Refused 'job-state takes the name of one job' }
            $n = $Words[0]
            $next = 'not scheduled'; $last = 'never'
            if (-not $DryRun) {
                $t = Get-ScheduledTask -TaskPath $JobTaskPath -TaskName "sdcore-job-$n" -ErrorAction SilentlyContinue
                if ($null -ne $t) {
                    $i = Get-ScheduledTaskInfo -TaskPath $JobTaskPath -TaskName "sdcore-job-$n"
                    if ($null -ne $i.NextRunTime -and $i.NextRunTime.Year -gt 2000) { $next = $i.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss') }
                    if ($t.State -eq 'Running') { $last = 'running now' }
                    elseif ($null -ne $i.LastRunTime -and $i.LastRunTime.Year -gt 2000 -and $i.LastTaskResult -ne 267011) {
                        $last = "$($i.LastRunTime.ToString('yyyy-MM-dd HH:mm:ss')) (result $($i.LastTaskResult))"
                    }
                }
            }
            Out-Line "next=$next"
            Out-Line "last=$last"
            exit 0
        }

        'job-purge' {
            # The uninstaller's (sd.iss RemoveScheduledJobs).  The tasks go FIRST - a task left behind would start a program that is gone -
            # then the definitions, which are SD's and belong to nothing once SD is gone.  Nothing here deletes a directory's contents
            # wholesale: this script makes only plain files in the directory, so only plain files are taken from it.
            if ($Words.Count -ne 0) { Exit-Refused 'job-purge takes nothing' }
            Out-Line "${Prog}: job-purge: first: every task ${JobTaskPath}sdcore-job-* is removed"
            Out-Line "${Prog}: then: removes the definitions in $jobsDir, and the directory"
            $left = 0
            if ($DryRun) {
                Out-Line "${Prog}: dry run: no task is removed"
            } else {
                foreach ($t in @(Get-ScheduledTask -TaskPath $JobTaskPath -TaskName 'sdcore-job-*' -ErrorAction SilentlyContinue)) {
                    try {
                        Unregister-ScheduledTask -TaskPath $JobTaskPath -TaskName $t.TaskName -Confirm:$false
                        Out-Line "${Prog}: task $($t.TaskName) removed"
                    } catch {
                        $left++
                        Out-Line "${Prog}: task $($t.TaskName) could not be removed ($($_.Exception.Message)); it was left as it is"
                    }
                }
                # The task folder, when nothing is left in it: job-set made it, by registering the first job there.  Left when it holds anything.
                try {
                    $svc = New-Object -ComObject Schedule.Service
                    $svc.Connect()
                    $tf = $svc.GetFolder($JobTaskPath.TrimEnd('\'))
                    if ($tf.GetTasks(1).Count -eq 0 -and $tf.GetFolders(0).Count -eq 0) { $svc.GetFolder('\').DeleteFolder($JobTaskPath.Trim('\'), 0) }
                } catch { }
            }
            if (Test-Path -LiteralPath $jobsDir) {
                $d = Get-Item -LiteralPath $jobsDir -Force
                if ((-not $d.PSIsContainer) -or ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (-not $DryRun -and -not (Test-JobAdminPath $jobsDir $true))) {
                    $left++
                    Out-Line "${Prog}: $jobsDir is a link, or is owned by or open to somebody other than SYSTEM and Administrators; it was left as it is"
                } else {
                    $kept = 0
                    foreach ($it in @(Get-ChildItem -LiteralPath $jobsDir -Force)) {
                        if ($it.PSIsContainer) { $kept++; Out-Line "${Prog}: $($it.Name) is not a plain file; it was left as it is"; continue }
                        Remove-Item -LiteralPath $it.FullName -Force
                    }
                    if ($kept -eq 0) { [IO.Directory]::Delete($jobsDir, $false) } else { $left += $kept }
                }
            }
            if ($left -gt 0) { Out-Line "${Prog}: not everything was removed; see the lines above"; exit 1 }
            Out-Line "${Prog}: the scheduled jobs are removed"
            exit 0
        }

        default {
            Out-Line "${Prog}: usage: sd-jobs.ps1 job-set NAME JOB SCHEDULE... | job-delete NAME | job-list | job-run NAME | job-state NAME | job-purge"
            exit 2
        }
    }
}
catch {
    Out-Line "${Prog}: $($_.Exception.Message)"
    exit 1
}
