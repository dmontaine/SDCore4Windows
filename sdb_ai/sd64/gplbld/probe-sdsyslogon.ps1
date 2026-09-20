<#
.SYNOPSIS
    WHY CAN THE SDSYS ACCOUNT NOT SIGN IN AT THE CONSOLE?  RELEASE_1.1 78.

.DESCRIPTION
    ***THIS STOPPED BEING A TEST-RIG QUESTION THE MOMENT IT WAS MEASURED.***
    RELEASE_1.1 64 made the Windows SDSYS account the ONLY administrator SD
    has, and PROJECT_STATUS.md 5.25 rules that administration happens at the
    console, in a session where UAC can render.  So if SDSYS cannot sign in
    interactively, this product cannot be administered on this machine at all
    except through the install's own "sd -internal" door - and that door is
    gated on K$INTERNAL, not available to a person.

    WHAT IS ALREADY MEASURED, 19 Sep 2026, and it is why this file exists:

      - the owner switched user to SDSYS SEVERAL TIMES.  Each attempt appeared
        to accept the password and begin entering, then terminated and returned
        him to his own session with no desktop ever shown.
      - "net user SDSYS" reads Account active YES, no logon script, no user
        profile path, no home directory, Workstations allowed All, Logon hours
        All.  Nothing in the account object forbids it.
      - SDSYS is in sdusers and Administrators, and NOT in sdsshonly - which is
        the only group the installer gives the deny rights to (sd.iss:2331,
        deny-logon.ps1).  The owner's own account is in sdusers too and signs
        in fine, so sdusers cannot be carrying a deny right.
      - C:\Users\SDSYS EXISTS and its ProfileList entry is present and points at
        it.  No .bak entry, so this is not the classic corrupt-profile case.
      - ***AND THE PROFILE SERVICE LOGGED NOTHING FOR ANY OF THE ATTEMPTS.***
        Its Operational log's last entry is 18:15:43, which matches a PROBE
        SPAWN, and there are 0 entries after 19:05 while the attempts happened
        at 19:10-19:14.  So the session ends BEFORE a profile is loaded.
      - "Last logon" on the account reads 19:00:56, which is also a probe spawn
        (probe-sdsysseat-20260919-190055.log), NOT an interactive sign-in.  A
        LogonUser/batch logon as SDSYS works; the console one does not.

    WHAT IS NOT MEASURED IS THE CAUSE, and every remaining candidate needs an
    ELEVATED read: the Security log's 4624/4625 rows with their Status and
    SubStatus, the local user-rights assignment, and the ACL on the profile
    directory.  That is all this script does - it READS.  It changes nothing,
    creates nothing and signs nobody in.

    ***IT REFUSES THE NULL CASE.***  If the Security log holds no logon row for
    the account inside the window, it says so and stops rather than concluding
    from an empty set - "nothing was attempted" and "the attempt was refused"
    are different answers.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\probe-sdsyslogon.ps1

    ELEVATED PowerShell.  Run it AFTER a failed sign-in attempt, so the window
    below covers it.  No password is asked for.
#>

[CmdletBinding()]
param(
    [string] $Account = 'SDSYS',
    # How far back to read the Security log.  The attempt must be inside it.
    [int]    $Minutes = 60,

    # ***-Watch REMOVES THE COORDINATION PROBLEM, WHICH IS WHAT COST THE FIRST
    # THREE RUNS.***  Twice the owner ran this on a window with no attempt in
    # it, because the attempt has to happen BEFORE the read and the sign-in
    # screen is not where the command is.  With -Watch the script takes a
    # baseline, tells him to go and try it NOW, and polls until something
    # happens - so the evidence cannot fall outside the window.  Minutes.
    [int]    $Watch = 0
)

$ErrorActionPreference = 'Stop'
function Say([string]$t)  { Write-Output ('  ' + $t) }
function Head([string]$t) { Write-Output ''; Write-Output ('== ' + $t) }

Write-Output 'probe-sdsyslogon: RELEASE_1.1 78 - why does the console sign-in end before the desktop?'
Write-Output ('  script  : ' + $PSCommandPath)
Write-Output ('  account : ' + $Account)
Write-Output ('  window  : the last ' + $Minutes + ' minutes')

$pr = New-Object Security.Principal.WindowsPrincipal(
          [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'probe-sdsyslogon: this needs an ELEVATED PowerShell - the Security log, the'
    Write-Output '  user-rights assignment and the profile ACL are all elevated reads.'
    exit 2
}

$u = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
if ($null -eq $u) { Write-Output ("probe-sdsyslogon: there is no local {0} account." -f $Account); exit 2 }
$sid = $u.SID.Value
Say ('SID     : ' + $sid)

# --------------------------------------------------------------------- watch
if ($Watch -gt 0) {
    Head ("WATCHING - go and try the sign-in NOW ({0} minute(s))" -f $Watch)
    Write-Output ''
    Write-Output '  1. Ctrl+Alt+Del  ->  Switch user'
    Write-Output ('  2. choose {0}, type its password, let it do whatever it does' -f $Account)
    Write-Output '  3. come back to this session - this window is watching and will say'
    Write-Output '     what the operating system recorded while you were away.'
    Write-Output ''

    # The baseline is a RECORD ID, not a time: clocks and log latency both
    # wander, and "newer than record N" cannot miss an event that arrived
    # while this was starting.
    $baseSec = 0
    try { $baseSec = (Get-WinEvent -LogName Security -MaxEvents 1 -ErrorAction Stop).RecordId } catch { }
    $baseApp = 0
    try { $baseApp = (Get-WinEvent -LogName Application -MaxEvents 1 -ErrorAction Stop).RecordId } catch { }
    Say ("baseline: Security record {0}, Application record {1}" -f $baseSec, $baseApp)
    if ($baseSec -eq 0) { Say 'REFUSED: no baseline from the Security log - the watch would prove nothing'; exit 2 }

    $deadline = (Get-Date).AddMinutes($Watch)
    $found = @()
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        try {
            $new = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4624, 4625, 4634, 4648 } `
                        -MaxEvents 60 -ErrorAction Stop |
                     Where-Object { $_.RecordId -gt $baseSec })
        } catch { $new = @() }
        # Only a row naming a REAL user is interesting; the machine account
        # logs on constantly and would end the watch immediately.
        $user = @($new | Where-Object { $_.Message -notmatch ('(?m)^\s*Account Name:\s*' +
                                        [regex]::Escape($env:COMPUTERNAME) + '\$') })
        if ($user.Count -gt 0) { $found = $user; break }
    }

    if ($found.Count -eq 0) {
        Say ("nothing but machine-account activity in {0} minute(s)." -f $Watch)
        Say 'THE OPERATING SYSTEM RECORDED NO LOGON ROW AT ALL - and what that MEANS'
        Say 'depends entirely on the audit-policy section below.  With failure auditing ON'
        Say 'it says LSA never saw a credential, and the fault is at the sign-in screen.'
        Say 'With failure auditing OFF it says nothing whatever: a refused sign-in would'
        Say 'leave no trace either.  Read that section before drawing the conclusion.'
    } else {
        Say ("{0} row(s) arrived while watching:" -f $found.Count)
        foreach ($e in ($found | Sort-Object TimeCreated)) {
            $who = '?'
            if ($e.Message -match '(?m)^\s*Account Name:\s*(\S.*)$') { $who = $Matches[1].Trim() }
            $type = ''
            if ($e.Message -match '(?m)^\s*Logon Type:\s*(\d+)') { $type = 'type ' + $Matches[1] }
            $st = ''
            if ($e.Message -match '(?m)^\s*Status:\s*(\S+)')     { $st = ' status ' + $Matches[1] }
            if ($e.Message -match '(?m)^\s*Sub Status:\s*(\S+)') { $st += ' sub ' + $Matches[1] }
            $what = switch ($e.Id) { 4624 {'LOGON OK'} 4625 {'LOGON FAILED'} 4634 {'logoff'}
                                     4648 {'explicit-credential logon'} default {'id ' + $e.Id} }
            Write-Output ('  {0:HH:mm:ss}  {1,-26} {2,-22} {3}{4}' -f $e.TimeCreated, $what, $who, $type, $st)
        }
    }
    Write-Output ''
    Say 'the tables below cover the ordinary window as well'
}

# ---------------------------------------------------------------- audit policy
# ***READ THIS BEFORE BELIEVING ANY ABSENCE BELOW, AND IT IS A CORRECTION THIS
# SCRIPT OWED.***  The 19 Sep run concluded "LSA never validated a credential"
# from the fact that no 4625 appeared for the owner's attempts.  That inference
# is only sound if FAILURE auditing is ON.  4624s are plainly audited - the
# probe spawns produced dozens - but success and failure are separate settings
# in the same subcategory, and a machine with Success-only auditing records a
# refused sign-in NOWHERE.  So the absence of a 4625 would mean nothing at all,
# and the conclusion drawn from it would have been an instrument fault of
# exactly the kind CLAUDE.md's rule 3 describes: a confident verdict from a
# probe that never reached the condition it claimed to measure.
Head 'is a FAILED logon even audited on this machine?'
$auditOk = $false
try {
    $ap = & "$env:SystemRoot\System32\auditpol.exe" /get /subcategory:"Logon","Logoff","Account Lockout" 2>&1
    foreach ($l in $ap) {
        $t = ([string]$l).TrimEnd()
        if ($t -match '\S') { Say $t }
    }
    $logonRow = $ap | Where-Object { $_ -match '^\s+Logon\s{2,}' }
    if ($logonRow) {
        $auditOk = ([string]$logonRow -match 'Failure')
        if ($auditOk) {
            Say 'FAILURE auditing is ON, so an absent 4625 really does mean no refusal was recorded.'
        } else {
            Say '*** FAILURE AUDITING IS OFF FOR "Logon". ***  A refused sign-in is recorded'
            Say 'NOWHERE on this machine, so an absent 4625 proves NOTHING - it cannot tell a'
            Say 'refusal from an attempt that never happened.  Turn it on for the length of one'
            Say 'attempt, elevated, and the next run can read the refusal:'
            Say '    auditpol /set /subcategory:"Logon" /failure:enable'
            Say 'and afterwards, to leave the machine as it was:'
            Say '    auditpol /set /subcategory:"Logon" /failure:disable'
        }
    } else {
        Say 'REFUSED: auditpol printed no Logon row - the audit policy could not be read, so'
        Say 'nothing below can be concluded from an absence.'
    }
} catch {
    Say ('auditpol could not be run: ' + $_.Exception.Message)
}

# --------------------------------------------------------------- user rights
Head 'the local user-rights assignment - who is DENIED an interactive logon'

# secedit is the only built-in route to the rights database; deny-logon.ps1's
# own header says so.  Export, read, and resolve every SID to a name, because
# "S-1-5-21-...-2545" tells a reader nothing.
$cfg = Join-Path $env:TEMP ('sdrights-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.inf')
$log = [System.IO.Path]::ChangeExtension($cfg, '.log')
& "$env:SystemRoot\System32\secedit.exe" /export /areas USER_RIGHTS /cfg $cfg /log $log /quiet | Out-Null
if (-not (Test-Path -LiteralPath $cfg)) {
    Say 'secedit wrote no export - the rights could not be read, so nothing here is measured'
} else {
    $wanted = @('SeDenyInteractiveLogonRight', 'SeInteractiveLogonRight',
                'SeDenyRemoteInteractiveLogonRight', 'SeDenyBatchLogonRight',
                'SeBatchLogonRight')
    $lines = Get-Content -LiteralPath $cfg -Encoding Unicode
    $seen = 0

    # The SIDs this account is judged by: its own, and every group it is in.
    # A deny right on ANY of them lands on the account.
    $mySids = @($sid)
    foreach ($g in (Get-LocalGroup)) {
        try {
            if (Get-LocalGroupMember -Group $g.Name -ErrorAction Stop |
                Where-Object { $_.SID.Value -eq $sid }) { $mySids += $g.SID.Value }
        } catch { }
    }
    Say ('judged by ' + $mySids.Count + ' SID(s): its own and its groups')

    foreach ($w in $wanted) {
        $row = $lines | Where-Object { $_ -match ('^\s*' + $w + '\s*=') }
        if ($null -eq $row) { Say ("{0,-34} (not assigned to anybody)" -f $w); continue }
        $seen++
        $vals = @(($row -split '=', 2)[1].Trim() -split ',' | ForEach-Object { $_.Trim() })

        # ***THE VERDICT FIRST, THE LIST SECOND.***  The first version of this
        # printed 47 raw SIDs on one line and left the reader to find the one
        # that mattered by eye - which is rule 1 of the instrument section
        # failing in the other direction: everything shown, nothing said.
        $hit = @()
        foreach ($v in $vals) {
            $bare = $v.TrimStart('*')
            if ($mySids -contains $bare) { $hit += $bare }
        }
        $named = @(); $dead = 0
        foreach ($v in $vals) {
            if (-not $v.StartsWith('*')) { $named += $v; continue }
            try {
                $named += (New-Object Security.Principal.SecurityIdentifier($v.Substring(1))
                          ).Translate([Security.Principal.NTAccount]).Value
            } catch { $dead++ }
        }
        Say ("{0,-34} {1} entr(y/ies): {2}{3}" -f $w, $vals.Count,
             $(if ($named.Count) { $named -join ' ; ' } else { '(none that resolve)' }),
             $(if ($dead) { "  + $dead SID(s) that no longer resolve (deleted accounts)" } else { '' }))
        if ($hit.Count) {
            Say ("   *** {0} APPLIES TO {1}, through SID {2} ***" -f $w, $Account, ($hit -join ', '))
        } else {
            Say ("   {0} does NOT apply to {1} - neither its SID nor any group it is in" -f $w, $Account)
        }
    }
    if ($seen -eq 0) { Say 'REFUSED: not one of these rights was found in the export - the parse is blind' }
    Remove-Item -LiteralPath $cfg -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------- profile
Head 'the profile directory this account would load'

$dir = Join-Path $env:SystemDrive ('Users\' + $Account)
Say ('path    : ' + $dir + '   exists=' + (Test-Path -LiteralPath $dir))
if (Test-Path -LiteralPath $dir) {
    try {
        $acl = Get-Acl -LiteralPath $dir
        Say ('owner   : ' + $acl.Owner)
        foreach ($r in $acl.Access) {
            Say ('  {0,-45} {1,-20} {2}' -f $r.IdentityReference, $r.FileSystemRights, $r.AccessControlType)
        }
        $mine = $acl.Access | Where-Object { $_.IdentityReference -match ([regex]::Escape($Account) + '$') }
        Say ('THE ROW THAT MATTERS: does ' + $Account + ' itself appear? ' + [bool]$mine)
    } catch {
        Say ('the ACL could not be read even elevated: ' + $_.Exception.Message)
    }
}

# -------------------------------------------------------------- security log
Head ('what the Security log says about ' + $Account + "'s logons")

$since = (Get-Date).AddMinutes(-$Minutes)
$rows = @()
try {
    $rows = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; StartTime = $since
                                             Id = 4624, 4625, 4634, 4647, 4648 } -ErrorAction Stop |
            Where-Object { $_.Message -match ([regex]::Escape($Account)) }
} catch {
    Say ('the Security log could not be read: ' + $_.Exception.Message)
}

# ***THE REFUSAL NO LONGER EXITS HERE, AND THE 19 Sep RUN IS WHY.***  It did,
# and it skipped the two tables below - which are the only things that can tell
# "nobody signed in" from "somebody did and it was not this account".  A null
# case must REFUSE THE VERDICT, not suppress the evidence: the exit code is
# still 2 at the end, after everything has been printed.
$nothingForAccount = ($rows.Count -eq 0)
if ($nothingForAccount) {
    Say ("NO logon row for {0} in the last {1} minutes." -f $Account, $Minutes)
    Say '"Nothing was attempted" and "the attempt was refused" are different answers,'
    Say 'and an empty set cannot tell them apart - so read the unfiltered table below'
    Say 'before concluding anything.  This run will exit 2.'
}

Say ("{0} row(s) in the window" -f $rows.Count)
foreach ($r in ($rows | Sort-Object TimeCreated)) {
    $type = ''
    if ($r.Message -match '(?m)^\s*Logon Type:\s*(\d+)')  { $type = 'type ' + $Matches[1] }
    $status = ''
    if ($r.Message -match '(?m)^\s*Status:\s*(\S+)')      { $status = ' status ' + $Matches[1] }
    if ($r.Message -match '(?m)^\s*Sub Status:\s*(\S+)')  { $status += ' sub ' + $Matches[1] }
    $what = switch ($r.Id) {
        4624 { 'LOGON OK' } 4625 { 'LOGON FAILED' } 4634 { 'logoff' }
        4647 { 'user-initiated logoff' } 4648 { 'explicit-credential logon' }
        default { 'id ' + $r.Id }
    }
    Write-Output ('  {0:HH:mm:ss}  {1,-26} {2}{3}' -f $r.TimeCreated, $what, $type, $status)
}

# ***AND THE SAME WINDOW WITHOUT THE NAME FILTER, WHICH IS THE ROW THAT
# MATTERED ON 19 Sep 2026.***  The first run showed 112 rows naming SDSYS and
# NOT ONE of them inside the minutes the owner was trying to sign in - every
# row belonged to a probe spawn.  An absence measured through a filter is not
# an absence: if a console attempt had been logged under a slightly different
# name, or as a failure that names nobody, the filtered table could not show
# it.  So the unfiltered count is printed beside it, and the two together are
# what say "the operating system never began a logon" rather than "this script
# did not find one".
Head 'every logon row in the window, WHOEVER it names'
$all = @()
try {
    $all = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; StartTime = $since
                                            Id = 4624, 4625 } -ErrorAction Stop
} catch { Say ('could not be read: ' + $_.Exception.Message) }
# ***COMPARE LIKE WITH LIKE.***  The first version printed "98 logon row(s) in
# total, of which 112 name SDSYS" - a subset larger than its set, and therefore
# a sentence that cannot be true.  $rows counts five event ids (logons, logoffs
# and explicit-credential rows); $all counts two.  The count that belongs here
# is how many of THESE rows name the account.
$allNamed = @($all | Where-Object { $_.Message -match ([regex]::Escape($Account)) })
Say ("{0} logon row(s) (4624/4625) in the window, of which {1} name {2}" -f `
     $all.Count, $allNamed.Count, $Account)
$byMin = $all | Group-Object { '{0:HH:mm}' -f $_.TimeCreated } | Sort-Object Name
foreach ($g in $byMin) {
    $names = ($g.Group | ForEach-Object {
        if ($_.Message -match '(?m)^\s*Account Name:\s*(\S.*)$') { $Matches[1].Trim() } else { '?' }
    } | Sort-Object -Unique) -join ', '
    Say ('{0}  {1,3} row(s)  {2}' -f $g.Name, $g.Count, $names)
}

# Winlogon's own notifications, which mark a session starting and ending even
# when no credential was ever validated - the pairs the owner's attempts left.
Head 'Winlogon notifications in the window (a session began and ended)'
# ***NOT FilterHashtable WITH ProviderName.***  Measured twice on 19 Sep 2026,
# the second time in this very script: "@{LogName='Application';
# ProviderName='Microsoft-Windows-Winlogon'}" answers "The specified providers
# do not write events to any of the specified logs" on this machine, while
# reading the log and filtering in the pipeline returns the same events
# perfectly.  The first time it happened I worked around it and then wrote the
# failing form in here anyway.
try {
    $wl = @(Get-WinEvent -LogName Application -MaxEvents 400 -ErrorAction Stop |
            Where-Object { $_.ProviderName -eq 'Microsoft-Windows-Winlogon' -and
                           $_.TimeCreated -ge $since })
    Say ("{0} row(s)" -f $wl.Count)
    foreach ($e in ($wl | Sort-Object TimeCreated | Select-Object -Last 20)) {
        Say ('{0:HH:mm:ss}  id {1}' -f $e.TimeCreated, $e.Id)
    }
} catch { Say ('none, or unreadable: ' + $_.Exception.Message) }

Write-Output ''
Write-Output 'READ IT LIKE THIS.  A 4625 names the refusal in its Status/Sub Status'
Write-Output '  (0xC000006D with sub 0xC0000064 is a bad user name, 0xC000006A a bad'
Write-Output '  password, 0xC0000413 a deny right, 0xC000015B "the user has not been'
Write-Output '  granted the requested logon type").  A 4624 of TYPE 2 or 11 followed'
Write-Output '  seconds later by a 4634 is the shape the owner described: admitted,'
Write-Output '  then the session ended before a desktop - and that points at the shell'
Write-Output '  or the profile rather than at the credential.'
Write-Output ''
if ($nothingForAccount) {
    Write-Output ('probe-sdsyslogon: NOTHING WAS MEASURED ABOUT ' + $Account.ToUpper() +
                  ' - no logon row for it in the window.')
    Write-Output '  If the unfiltered table above is empty for the minute you tried, the'
    Write-Output '  operating system never began a logon at all, and the next place to look'
    Write-Output '  is the sign-in screen rather than anything SD installed.  If it holds'
    Write-Output '  rows for ANOTHER account at that minute, say which - that is a different'
    Write-Output '  and more interesting answer.'
    Write-Output '  Try the sign-in, then run this again within the window.'
    exit 2
}
Write-Output 'probe-sdsyslogon: read the rows above; this script concludes nothing on its own.'
exit 0
