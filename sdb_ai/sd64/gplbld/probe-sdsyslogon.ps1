<#
.SYNOPSIS
    WHY CAN THE SDSYS ACCOUNT NOT SIGN IN AT THE CONSOLE?  RELEASE_1.1 78.

    ***CLOSED 20 SEP 2026 - NOT A DEFECT.  SDSYS SIGNS IN AT THE CONSOLE; THE
    OWNER HAD BEEN CHOOSING THE WRONG LOGIN NAME.***  The premise below is
    false.  What answered it, unelevated and in seconds, was
    Microsoft-Windows-TerminalServices-LocalSessionManager/Operational: its
    "User:" field names the account that AUTHENTICATED (Id 21 logon, Id 25
    reconnect, Id 41 arbitration).  Winlogon's "Authentication stopped.
    Result 0" says a credential was accepted and NOT whose.  This script never
    read that log.  Kept as the record; see RELEASE_1.1_FIXES.md 78 before
    running it for a "cannot sign in" report - ask which login name was used.

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

# =======================================================================
# WINLOGON'S OWN VERDICT ON THE SIGN-IN, AND IT RUNS BEFORE THE ELEVATION GATE
# BECAUSE IT NEEDS NO ELEVATION.
#
# ***ADDED 20 Sep 2026, AND IT REVERSES WHAT THE 19 Sep RUN WAS READ TO
# MEAN.***  Microsoft-Windows-Winlogon/Operational logs id 1 "Authentication
# started" and id 2 "Authentication stopped. Result <n>" for every console
# sign-in.  All ten of the owner's SDSYS attempts logged **Result 0**.
#
# ***AND RESULT 0 IS SUCCESS, WHICH IS CALIBRATED RATHER THAN ASSUMED.***  The
# log on this machine reaches back to 25 Aug 2026 and holds 62 rows of Result 0
# and 8 of **Result 1326** - ERROR_LOGON_FAILURE, "the user name or password is
# incorrect".  ***EVERY 1326 IS FOLLOWED WITHIN SECONDS BY A RESULT 0***
# (18 Sep 18:05:46 and :48 both 1326, then 18:06:01 Result 0), which is a
# person mistyping and then getting it right.  A month of the owner's own
# working sign-ins are Result 0.  So the value is not a guess: the failure
# value exists, it is different, and it is present in this very log.
#
# THAT IS WHY IT IS PRINTED EVEN WHEN THE SECURITY LOG CANNOT BE READ.
# "Winlogon says the authentication SUCCEEDED and LSA recorded no logon" is a
# completely different finding from "the sign-in was refused", and the 19 Sep
# run could not tell them apart because it never read this log.  ***AN
# UNELEVATED RUN USED TO PRINT NOTHING BUT A REFUSAL***, so the one piece of
# evidence that needed no elevation was the one nobody could get.
function Show-WinlogonAuth([int]$Minutes) {
    Head 'what WINLOGON says about the sign-in (no elevation needed)'
    $since = (Get-Date).AddMinutes(-$Minutes)
    try {
        $auth = @(Get-WinEvent -FilterHashtable @{
                      LogName = 'Microsoft-Windows-Winlogon/Operational'; Id = 1, 2 } `
                  -MaxEvents 400 -ErrorAction Stop | Sort-Object TimeCreated)
        $inWin = @($auth | Where-Object { $_.TimeCreated -ge $since })
        # THE CALIBRATION IS TAKEN FROM THE WHOLE LOG, NOT FROM THE WINDOW,
        # because a window with no failure in it cannot calibrate anything.
        $res = @{}
        foreach ($e in ($auth | Where-Object { $_.Id -eq 2 })) {
            $v = 'unparsed'
            if ($e.Message -match 'Result\s+(\S+?)\.?\s*$') { $v = $Matches[1] }
            if (-not $res.ContainsKey($v)) { $res[$v] = 0 }
            $res[$v] = $res[$v] + 1
        }
        if ($auth.Count -gt 0) {
            Say ("this log reaches back to {0:yyyy-MM-dd HH:mm} and holds {1} authentication row(s)" -f
                 $auth[0].TimeCreated, $auth.Count)
        } else {
            Say 'this log holds no authentication rows at all - nothing below is measurable.'
            return
        }
        # ***THE CONTROL, AND IT REFUSES THE NULL CASE OUT LOUD.***  Without a
        # known FAILURE value in this log, Result 0 means nothing and this
        # section must say so rather than report a success it cannot recognise.
        $sawFailure = @($res.Keys | Where-Object { $_ -ne '0' -and $_ -ne 'unparsed' })
        foreach ($k in ($res.Keys | Sort-Object)) {
            $what = if ($k -eq '0') { 'success' }
                    elseif ($k -eq '1326') { 'ERROR_LOGON_FAILURE - bad user name or password' }
                    else { 'a non-zero result, i.e. a failure' }
            Say ("  Result {0,-6} {1,4} time(s)   {2}" -f $k, $res[$k], $what)
        }
        if ($sawFailure.Count -eq 0) {
            Say '  CONTROL MISSING: this log holds no FAILED authentication, so "Result 0"'
            Say '  cannot be read as success here - it is simply the only value seen.'
        } else {
            Say '  CONTROL PRESENT: a failing Result exists in this log and differs from 0,'
            Say '  so Result 0 on a row below really is Winlogon reporting SUCCESS.'
        }
        Say ("{0} authentication row(s) inside the last {1} minute(s):" -f $inWin.Count, $Minutes)
        foreach ($s in @($inWin | Where-Object { $_.Id -eq 1 })) {
            $stop = $inWin | Where-Object { $_.Id -eq 2 -and $_.TimeCreated -ge $s.TimeCreated } |
                    Select-Object -First 1
            $v = '(no stop row)'
            if ($stop -and $stop.Message -match 'Result\s+(\S+?)\.?\s*$') { $v = 'Result ' + $Matches[1] }
            Say ('  {0:HH:mm:ss}  authentication started  ->  {1}' -f $s.TimeCreated, $v)
        }
        if ($inWin.Count -eq 0) {
            Say '  NONE - so no console sign-in was attempted in this window at all,'
            Say '  whatever the tables below say.'
        }
    } catch {
        # Same trap as the Security section below: a FilterHashtable that
        # matches nothing THROWS, so "this machine has never logged a console
        # authentication" and "this log is unreadable" would otherwise share a
        # branch and both print as a fault.
        if ($_.Exception.Message -match 'No events were found') {
            Say 'this log holds no authentication rows at all - nothing here is measurable.'
        } else {
            Say ('Winlogon/Operational could not be read: ' + $_.Exception.Message)
        }
    }
}

$pr = New-Object Security.Principal.WindowsPrincipal(
          [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Show-WinlogonAuth $Minutes
    Write-Output ''
    Write-Output 'probe-sdsyslogon: the rest of this needs an ELEVATED PowerShell - the Security'
    Write-Output '  log, the user-rights assignment and the profile ACL are all elevated reads.'
    Write-Output '  The section above is the whole of what an ordinary prompt can measure, and'
    Write-Output '  on the 19 Sep evidence it is the section that matters most.'
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
# ***THE NAME THIS TABLE PRINTED WAS THE WRONG ONE, AND IT MADE THE TABLE
# USELESS FOR THE ONE QUESTION IT EXISTS TO ANSWER - MEASURED 20 Sep 2026.***
# A 4624 message carries "Account Name:" TWICE: once under Subject, which is
# who REQUESTED the logon, and once under New Logon, which is who logged ON.
# A console sign-in is requested by Winlogon, so Subject is the machine
# account - and a single -match takes the FIRST one, so every row in the
# owner's 19 Sep run printed "ACE$".  All 37 of them, for every account on the
# machine including his own.
#
# ***SO THE CLOSING ADVICE WAS UNFOLLOWABLE***: it says "if it holds rows for
# ANOTHER account at that minute, say which", and the table could not name any
# account but the machine's.  A reader acting on it would go looking at the
# computer account, which is not what logged on.  (4625 is the same shape -
# Subject, then "Account For Which Logon Failed" - so the last match is the
# right one on both ids.)
# ***IT RETURNS ONE STRING AND IS NAMED IN THE SINGULAR, BECAUSE THE PLURAL
# VERSION OF IT WAS WRONG AND THE DRIVER CAUGHT IT.***  The first form returned
# "@($name)" and every caller wrote "(Get-LogonNames $m)[0]" - but PowerShell
# UNROLLS a one-element array on return, so the caller got the STRING and "[0]"
# indexed its first CHARACTER.  It printed "S" for SDSYS and "D" for Don.
# Same family as this tree's "a function that returns a value prints nothing"
# rule: what a function hands back is not always the shape it was written as.
function Get-LogonName([string]$msg) {
    $m = [regex]::Matches($msg, '(?m)^\s*Account Name:\s*(\S.*)$')
    if ($m.Count -eq 0) { return '?' }
    # The LAST is New Logon / the account that failed.  The first is kept only
    # when it is the only one, so a message shaped differently still says
    # something rather than nothing.
    return $m[$m.Count - 1].Groups[1].Value.Trim()
}
$bothNames = 0
$byMin = $all | Group-Object { '{0:HH:mm}' -f $_.TimeCreated } | Sort-Object Name
foreach ($g in $byMin) {
    $names = ($g.Group | ForEach-Object {
        $mm = [regex]::Matches($_.Message, '(?m)^\s*Account Name:\s*(\S.*)$')
        if ($mm.Count -gt 1) { $bothNames++ }
        Get-LogonName $_.Message
    } | Sort-Object -Unique) -join ', '
    Say ('{0}  {1,3} row(s)  {2}' -f $g.Name, $g.Count, $names)
}
# THE INSTRUMENT SAYS WHAT IT DID.  If this count is 0 on a machine with
# console sign-ins, the extraction above is reading a message shape this
# script has not seen, and the names beside it are not to be trusted.
Say ("{0} of {1} row(s) carried BOTH a Subject and a New Logon account name - the one printed above is the New Logon one" -f
     $bothNames, $all.Count)

# THE SAME SECTION AN UNELEVATED RUN GETS, printed here for an elevated one so
# that one run carries both halves and they can be read against each other.
Show-WinlogonAuth $Minutes

# =======================================================================
# EVERY Security EVENT, OF ANY ID, IN THE MINUTE AROUND EACH AUTHENTICATION.
#
# ***THIS IS THE SECTION THE 20 Sep FINDING ASKS FOR, AND IT EXISTS BECAUSE
# EVERY TABLE ABOVE FILTERS BY ID.***  The tables above ask for 4624/4625 and
# friends, so they can only ever answer "was there a logon".  Winlogon now says
# the credential was ACCEPTED while those tables stay empty - and the next
# question is not "was there a logon" but "what did LSA do AT ALL", which no
# id-filtered query can answer.  4672 (special privileges), 4648 (explicit
# credentials), 5379 (credential-manager read), 4798, an audit-policy change:
# any of them would narrow this, and all of them are invisible above.
#
# IT IS ANCHORED ON THE AUTHENTICATION TIMES RATHER THAN ON THE WINDOW, so it
# prints a readable handful instead of an hour of noise, and it says out loud
# when it has nothing to anchor on.
Head 'every Security event, ANY id, around each authentication'
try {
    $anchors = @(Get-WinEvent -FilterHashtable @{
                     LogName = 'Microsoft-Windows-Winlogon/Operational'; Id = 1
                     StartTime = $since } -ErrorAction Stop | Sort-Object TimeCreated)
} catch { $anchors = @() }
if ($anchors.Count -eq 0) {
    Say 'no authentication in the window to anchor on, so there is nothing to print here.'
    Say 'That is not a clean result - it means no console sign-in was attempted.'
} else {
    foreach ($a in $anchors) {
        $t0 = $a.TimeCreated.AddSeconds(-30)
        $t1 = $a.TimeCreated.AddSeconds(30)
        Say ('--- {0:HH:mm:ss} +/- 30s' -f $a.TimeCreated)
        $near = @()
        $readFailed = $false
        try {
            $near = @(Get-WinEvent -FilterHashtable @{
                          LogName = 'Security'; StartTime = $t0; EndTime = $t1 } `
                      -ErrorAction Stop | Sort-Object TimeCreated)
        } catch {
            # ***"No events were found" IS AN EXCEPTION, NOT AN EMPTY RESULT,
            # AND TREATING IT AS A READ FAILURE WOULD DESTROY THIS SECTION'S
            # WHOLE POINT - measured 20 Sep 2026 while driving this code.***
            # Get-WinEvent THROWS when a FilterHashtable matches nothing, so a
            # bare catch turns "the log is genuinely silent in this minute" -
            # the finding - into "could not be read", which reads as an
            # instrument fault.  The two must not share a branch.
            #
            # ***AND THIS SECTION MUST STAY BELOW THE ELEVATION GATE BECAUSE OF
            # IT.***  Measured the same day: an UNELEVATED prompt asking for the
            # Security log gets the very same "No events were found" message
            # rather than an access error - so out here the branch below would
            # report a silent log on a run that was never allowed to look.  The
            # gate is what makes "empty" mean empty.  Do not move it up.
            if ($_.Exception.Message -match 'No events were found') {
                $near = @()
            } else {
                $readFailed = $true
                Say ('    COULD NOT READ the Security log: ' + $_.Exception.Message)
            }
        }
        # THE NULL CASE IS SAID, NOT LEFT AS A BLANK.  An empty minute in the
        # Security log around an authentication Winlogon called successful is
        # itself the finding, and a silent gap here would read as "nothing to
        # report".
        if ($readFailed) {
            Say '    (no verdict for this minute - the read failed, which is not the same'
            Say '     as the log being silent)'
        } elseif ($near.Count -eq 0) {
            Say '    NOTHING - the Security log has no event of any id in this minute.'
            Say '    Read with the WINLOGON section above: an authentication Winlogon'
            Say '    called successful, and LSA recorded nothing at all.'
        } else {
            Say ('    {0} event(s):' -f $near.Count)
            foreach ($e in $near) {
                $who  = Get-LogonName $e.Message
                # TaskDisplayName is EMPTY on some providers - measured on this
                # machine's Application log - so the provider is the fallback
                # rather than a blank column that says nothing.
                $task = $e.TaskDisplayName
                if ([string]::IsNullOrWhiteSpace($task)) { $task = $e.ProviderName }
                Say ('    {0:HH:mm:ss}  id {1,-6} {2,-28} {3}' -f
                     $e.TimeCreated, $e.Id, $task, $who)
            }
        }
    }
}

# Winlogon's own notifications, which mark a session starting and ending even
# when no credential was ever validated - the pairs the owner's attempts left.
#
# ***AND THE 6000 PAIR THE 19 Sep RUN SINGLED OUT IS NOISE - MEASURED
# 20 Sep 2026.***  Its text is "The winlogon notification subscriber
# <SessionEnv> was unavailable to handle a notification event".  SessionEnv is
# Remote Desktop Configuration, and RDP is OFF on this machine
# (fDenyTSConnections 1, TermService stopped), so that subscriber is
# unavailable at EVERY session transition - twenty rows in 150 minutes,
# bracketing the working sign-ins exactly as they bracket the failing ones.
# ***THE TEXT IS PRINTED NOW AND NOT ONLY THE ID***, because an id with no
# text is what made it look like a lead.
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
        Say ('{0:HH:mm:ss}  id {1}  {2}' -f $e.TimeCreated, $e.Id,
             ((($e.Message -replace "`r?`n", ' ') -replace '\s+', ' ')))
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
    # ***AND THE THIRD READING IS THE ONE THE 19 Sep RUN ACTUALLY PRODUCED, SO
    # IT IS NAMED HERE RATHER THAN LEFT TO BE INFERRED.***  If the WINLOGON
    # section above shows an authentication in the same minute with Result 0,
    # then the credential WAS accepted and LSA still wrote nothing - which is
    # neither "nobody tried" nor "it was refused", and rules out the password,
    # the deny rights and the sign-in screen all at once.  The next place to
    # look is between authentication and session creation: the profile, the
    # shell, and whatever a Security-log read around that exact second shows.
    Write-Output '  BUT IF WINLOGON ABOVE REPORTS Result 0 IN THAT SAME MINUTE, read neither'
    Write-Output '  of those: the credential was ACCEPTED and no logon was recorded, which is'
    Write-Output '  a third answer and the one that needs the next measurement.'
    Write-Output '  Try the sign-in, then run this again within the window.'
    exit 2
}
Write-Output 'probe-sdsyslogon: read the rows above; this script concludes nothing on its own.'
exit 0
