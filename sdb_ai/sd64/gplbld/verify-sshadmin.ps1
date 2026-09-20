# verify-sshadmin.ps1 - the ssh door, END TO END: an account's route keyword decides
# whether sshd lets it in, from loopback and from this machine's own LAN address.
#
#   powershell -ExecutionPolicy Bypass -File verify-sshadmin.ps1 -Prefix sdsshadm<run>
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# ***THE NAME IS HISTORICAL AND KEPT ON PURPOSE.***  This file was written to prove that an
# SD ADMINISTRATOR gets no ssh session (PRE_RELEASE_FIXES 167, RELEASE_1.1 58).  RELEASE_1.1
# 64 abolished the administrator account type, so that subject no longer exists and the
# script died at its first step ("CREATE.ACCOUNT ... ADMINISTRATOR" is refused with 2018).
# ***REWRITTEN 20 Sep 2026 ON THE OWNER'S RULING ("rewrite")*** to the subject that is left
# and that nothing else measures: the REAL ssh door.  verify-routes.ps1 proves sdssh
# membership is SET correctly; verify-apiadmin.ps1 proves the API's door; this drives a real
# ssh.exe to a real sshd and asks whether the session opens.  The file name stays because the
# runner's table, the scope guards and the record all name it.
#
# THE MODEL (RELEASE_1.1 64, 68): one administrator, SDSYS; every other account is ordinary,
# with its routes said at create time - SSH, API, BOTH or NONE, and silence means BOTH.  A
# route keyword is a promise about sshd's AllowGroups, and this is the only thing that checks
# the promise where it is kept.
#
#   SSH account  via loopback    ADMITTED, runs a command      <- the CONTROL, and it gates the rest
#   SSH account  via the LAN IP  ADMITTED, runs a command      <- a remote address is not a refusal
#   NONE account via loopback    REFUSED by sshd               <- the keyword decides
#   NONE account via the LAN IP  REFUSED by sshd
#   API  account via loopback    REFUSED by sshd               <- API TAKES ssh AWAY, on the real door
#
# ***THE PAIR IS THE INSTRUMENT.***  The SSH account and the NONE account are made the same
# way, offered the same kind of password and reached by the same two addresses - so the only
# variable between "admitted" and "refused" is the keyword.  A single leg cannot show that: a
# door that admitted everything and a door that refused everything would each pass one of them.
#
# ***A SESSION THAT NEVER STARTED MUST NOT SCORE.***  A refused leg is anchored on POSITIVE
# evidence of sshd's refusal - a non-zero ssh exit AND its own wording on stderr - never on the
# absence of a session, because an ssh that never connected (a stopped sshd, a down adapter)
# looks identical to one that was turned away.  The CONTROL's banner over the same transport is
# what proves ssh works on this machine at all, and if it does not get in the run exits 2 and
# scores no refusal, because a dead ssh server would otherwise pass every refused leg.
#
# WHY IT NEEDS NO SECOND MACHINE.  ssh to one of this machine's OWN LAN addresses leaves and
# returns over the interface, and sshd then reports SSH_CLIENT as that address rather than
# 127.0.0.1.  A routable address is required and its absence is refused out loud: without one
# there is no remote leg.
#
# RUN IT ELEVATED, AND SDSYS MUST BE SIGNED IN.  It makes three accounts through the SDSYS
# seat (sdsys-seat.ps1, RELEASE_1.1 76), which registers a task for the OS SDSYS account and so
# needs an elevated caller.  VerifyInstall2 is already elevated.
#
# ANCHORED ON THE AUDIT TRAIL AS WELL AS THE SCREEN.  The SSH account's admission must be in
# LOGIN's record (so the trail is live); the NONE and API accounts must have NO admission and
# NO refusal there, because sshd refuses before LOGIN is ever reached - an entry for either
# would mean sshd let the account through and SD caught it one layer later.

[CmdletBinding()]
param(
    # Derived from -Run by the runner.  A FIXED prefix passes once and fails
    # every later run - PRE_RELEASE 54 - which is why this goes through
    # VerifyInstall2 rather than being called by hand with a constant.
    # Lower case only: it becomes a Windows account name.
    [string]$Prefix = ''

    # NO -HelperPipe, DELIBERATELY, and test-elevonce-units.ps1 is why this
    # sentence exists.  This step launches no elevated child - the runner is already
    # elevated and Invoke-SD runs through the seat - so there is nothing for a pipe
    # to serve.  If this ever DOES start an elevated child, add the parameter AND the
    # name to $helperAware in elevate-once.ps1, together.
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }

. (Join-Path $here 'sdtestuser.ps1')

$sd64  = Split-Path $here -Parent
$sdExe = Join-Path $sd64 'bin\sd.exe'

$pass = 0
$fail = 0

function Note([string]$name, $expected, $got, [bool]$decisive) {
    $ok = ($expected -eq $got)
    if ($decisive) {
        if ($ok) { $script:pass++ } else { $script:fail++ }
    }
    $tag = if ($ok) { 'PASS' } else { if ($decisive) { 'FAIL' } else { 'note' } }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $tag, $name, $expected, $got)
}

Write-Output 'verify-sshadmin - the ssh door, end to end (rewritten 20 Sep 2026; the name is historical)'
Write-Output ("  prefix : {0}" -f $Prefix)
Write-Output ("  sd.exe : {0}" -f $sdExe)

# ---------------------------------------------------------------- refusals
# Every one of these is "the test could not be run", not "the product failed".

if ($Prefix -eq '') {
    Write-Output 'verify-sshadmin: no -Prefix. The runner derives it from -Run; a fixed one passes once (PRE_RELEASE 54).'
    exit 2
}
if ($Prefix -cne $Prefix.ToLower()) {
    Write-Output "verify-sshadmin: -Prefix must be lower case - it becomes a Windows account name."
    exit 2
}
if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output ("verify-sshadmin: no sd.exe at {0} - nothing could be measured." -f $sdExe)
    exit 2
}
if ($null -eq (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
    Write-Output 'verify-sshadmin: no ssh.exe on PATH - the whole measurement is over ssh.'
    exit 2
}
$elevated = ([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
Note 'this process is elevated' $true $elevated $false
if (-not $elevated) {
    Write-Output 'verify-sshadmin: this needs an ELEVATED PowerShell - the SDSYS seat registers a task for another account.'
    exit 2
}

# Where LOGIN writes its records.
$dataDir = Join-Path $env:ProgramData 'SD'
$audit   = Join-Path $dataDir 'sdsys\audit'
if (-not (Test-Path -LiteralPath $audit)) {
    # Some installs name it differently; find it rather than guess, and refuse
    # rather than score a leg whose evidence cannot be read.
    $found = Get-ChildItem -Path (Join-Path $dataDir 'sdsys') -Filter 'audit*' -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($null -ne $found) { $audit = $found.FullName }
}
Write-Output ("  audit  : {0}" -f $audit)
if (-not (Test-Path -LiteralPath $audit)) {
    Write-Output 'verify-sshadmin: the audit trail does not exist - the decisive reading is unavailable.'
    exit 2
}
Write-Output ''

# The daemon holds the audit trail open across its own writes, so it is read with
# FileShare::ReadWrite (lifted from verify-privundetermined.ps1).
function Get-AuditText {
    $fs = [System.IO.File]::Open($audit, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}

# ------------------------------------------------------------- local driver
# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT (sdsys-seat.ps1; verify-createaccount was the
# pilot).  THE "LOGTO SDSYS" PREFIX THIS USED TO SEND IS REFUSED (10002) FROM ANY SESSION THAT
# DID NOT START AS THE OS SDSYS ACCOUNT with an elevated, interactive token.  So the commands
# go to a task inside SDSYS's own live session and the text comes back through a file.  A seat
# that did not run THROWS rather than returning ''.  SDSYS must be signed in.
. (Join-Path $here 'sdsys-seat.ps1')
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 180) {
    if ($null -eq $commands -or $commands.Count -eq 0) {
        throw 'Invoke-SD: no commands given; that would start a session, measure nothing and look like a pass.'
    }
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec)
}

# PROVE THE SEAT BEFORE MAKING ANYTHING, so a missing SDSYS session is exit 2 and leaves no
# account behind, not a thrown error at the first CREATE.ACCOUNT that reads as a product failure.
Assert-SdSeat -Label 'verify-sshadmin'

$sshAcct   = ($Prefix + 's')
$apiAcct   = ($Prefix + 'a')
$noneAcct  = ($Prefix + 'n')
$sshPw     = New-SdTestPassword
$apiPw     = New-SdTestPassword
$nonePw    = New-SdTestPassword

# One ssh leg: prints EVERYTHING (the instrument rule) and returns the pieces the verdict reads.
#
# ***IT PRINTS WITH Write-Host AND NEVER Write-Output, AND THE FIRST VERSION DID NOT.***  In
# PowerShell a function's Write-Output lines ARE its return value, so every line printed here was
# folded into the caller's variable with the object at the end: $leg became an ARRAY, ".Ran" was not
# a property of it, and the owner's b202 run died with "The property 'Ran' cannot be found" on the
# first leg.  This is memory note ps-function-output-trap's FOURTH occurrence and verify-pygate's
# Invoke-Leg records the same defect (b141).  Write-Host reaches the transcript and the step log
# (the runner captures every stream) without touching the return value.
function Invoke-Leg([string]$Label, [string]$Acct, [string]$Pw, [string]$SshHost) {
    Write-Host ('=== ' + $Label + ' ===')
    $r = $null
    try {
        $r = Invoke-SdAsTestUser -Name $Acct -Password $Pw -Commands @('WHO') -SshHost $SshHost
    } catch {
        Write-Host ("verify-sshadmin: could not drive ssh as {0} to {1} - {2}" -f $Acct, $SshHost, $_.Exception.Message)
        exit 2
    }
    $text = ($r.Out | Out-String)
    Write-Host ("  ssh exit {0}, {1} characters of output" -f $r.ExitCode, $text.Length)
    Write-Host '  --- the session said: ---'
    Write-Host $text
    if ($r.Err -ne '') {
        # PRINTED, BECAUSE b121 THREW IT AWAY: "ssh exit 255" arrived with no reason attached.
        Write-Host '  --- ssh stderr ---'
        Write-Host $r.Err
    }
    Write-Host ''
    return [pscustomobject]@{
        Text   = $text
        Err    = "$($r.Err)"
        Exit   = $r.ExitCode
        Banner = [bool]($text -match '(?i)SD Core for Windows')
        # THE ANSWER TO WHO NAMES THE ACCOUNT, so this anchors on a session that RAN as it.
        Ran    = [bool]($text -match ('(?i)\b' + [regex]::Escape($Acct) + '\b'))
        Denied = [bool](($r.ExitCode -ne 0) -and ("$($r.Err)" -match '(?i)permission denied|not allowed'))
    }
}

$madeSsh = $false; $madeApi = $false; $madeNone = $false

try {
    Write-Output '=== 1. three accounts: SSH, API and NONE ============================'

    # ***THE CONTROL IS WINDOWS, NOT SD's WORDING.***  A verb that refused still echoes the
    # account name it was given, so reading the transcript back for it is the false-positive
    # shape CLAUDE.md names.
    $outS = Invoke-SD (New-SdTestUserScript -Name $sshAcct -Password $sshPw)
    Write-Output '  --- CREATE.ACCOUNT (SSH) said: ---'
    Write-Output $outS
    $outA = Invoke-SD @(('CREATE.ACCOUNT USER ' + $apiAcct + ' API'), $apiPw, $apiPw)
    Write-Output '  --- CREATE.ACCOUNT (API) said: ---'
    Write-Output $outA
    $outN = Invoke-SD @(('CREATE.ACCOUNT USER ' + $noneAcct + ' NONE'), $nonePw, $nonePw)
    Write-Output '  --- CREATE.ACCOUNT (NONE) said: ---'
    Write-Output $outN

    $madeSsh  = ($null -ne (Get-LocalUser -Name $sshAcct  -ErrorAction SilentlyContinue))
    $madeApi  = ($null -ne (Get-LocalUser -Name $apiAcct  -ErrorAction SilentlyContinue))
    $madeNone = ($null -ne (Get-LocalUser -Name $noneAcct -ErrorAction SilentlyContinue))
    Note 'the SSH account exists in Windows'  $true $madeSsh  $true
    Note 'the API account exists in Windows'  $true $madeApi  $true
    Note 'the NONE account exists in Windows' $true $madeNone $true
    if (-not ($madeSsh -and $madeApi -and $madeNone)) {
        Write-Output 'verify-sshadmin: an account was not created - nothing below could measure anything.'
        exit 2
    }

    # THE FIXTURE MUST BE WHAT IT CLAIMS, or the legs below measure a mislabelled account: each
    # account holds exactly the route it was made with.  (verify-routes.ps1 owns this as a
    # subject; here it is a precondition, so it is scored as one.)
    function InGroup($group, $user) {
        $m = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -like ('*\' + $user) }
        return [bool]$m
    }
    Note 'fixture: the SSH account is in sdssh'      $true  (InGroup 'sdssh' $sshAcct)  $true
    Note 'fixture: the SSH account is NOT in sdapi'  $false (InGroup 'sdapi' $sshAcct)  $true
    Note 'fixture: the API account is NOT in sdssh'  $false (InGroup 'sdssh' $apiAcct)  $true
    Note 'fixture: the API account is in sdapi'      $true  (InGroup 'sdapi' $apiAcct)  $true
    Note 'fixture: the NONE account is in neither'   $false ((InGroup 'sdssh' $noneAcct) -or (InGroup 'sdapi' $noneAcct)) $true
    Write-Output ''

    # --------------------------------------------------------- the measurement

    Write-Output '=== 2. the audit trail, before ===================================='
    $before = Get-AuditText
    Write-Output ("  audit is {0} bytes before" -f $before.Length)
    Write-Output ''

    # ***A NON-LOOPBACK ADDRESS FOR THIS SAME MACHINE.***  ssh to it and the packet leaves and
    # returns over the interface, so sshd reports SSH_CLIENT as that address rather than
    # 127.0.0.1.  ***AN ADDRESS IS NOT A ROUTE, AND b121 PAID FOR THAT DISTINCTION.***  The first
    # version took the first non-loopback IPv4 it found: 10.0.0.13 on an Ethernet adapter whose
    # status was Disconnected - the address is still configured on a down interface - so ssh
    # answered 255 and the leg measured nothing.  Require the adapter to be Up AND port 22 to
    # actually accept a connection.
    $lanIp = ''
    $candidates = @()
    try {
        $candidates = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                        Where-Object { $_.IPAddress -notlike '127.*' -and
                                       $_.IPAddress -notlike '169.254.*' })
    } catch { }
    foreach ($c in $candidates) {
        $status = ''
        try { $status = (Get-NetAdapter -InterfaceIndex $c.InterfaceIndex -ErrorAction Stop).Status } catch { }
        $reach = $false
        if ($status -eq 'Up') {
            try {
                $reach = (Test-NetConnection -ComputerName $c.IPAddress -Port 22 `
                              -WarningAction SilentlyContinue -ErrorAction Stop).TcpTestSucceeded
            } catch { }
        }
        Write-Output ("  candidate {0,-16} adapter={1,-14} port22={2}" -f
                      $c.IPAddress, $(if ($status) { $status } else { '?' }), $reach)
        if ($reach -and -not $lanIp) { $lanIp = $c.IPAddress }
    }
    Write-Output ("  non-loopback address for the REMOTE legs: {0}" -f
                  $(if ($lanIp) { $lanIp } else { '<none>' }))

    # REFUSE THE NULL CASE.  With no reachable routable address there is no remote leg, and the
    # loopback legs alone would show a door that works with nothing showing what a remote
    # address does.
    if (-not $lanIp) {
        Write-Output 'verify-sshadmin: no non-loopback IPv4 address on this machine accepts a connection on port 22.'
        Write-Output '  The REMOTE legs cannot be driven, so the door cannot be measured end to end.'
        Write-Output '  This is NOT a product failure - it is a network the test cannot use.'
        exit 2
    }
    Write-Output ''

    $legSLocal = Invoke-Leg 'LEG 1 - the SSH account over LOOPBACK - the CONTROL, MUST BE ADMITTED' $sshAcct $sshPw 'localhost'

    # ***THE CONTROL IS SCORED FIRST, AND IT GATES EVERYTHING.***  If an SSH account cannot get in
    # over loopback, ssh is broken on this machine and every refusal below would say nothing
    # about the keyword.
    $controlRan = ($legSLocal.Ran -and $legSLocal.Banner)
    Note 'CONTROL: the SSH account gets a session over loopback' $true $controlRan $true
    if (-not $controlRan) {
        Write-Output 'verify-sshadmin: the CONTROL did not get in, so ssh itself is suspect.'
        Write-Output '  The refused legs are NOT run - a refusal here would prove nothing about the keyword.'
        exit 2
    }

    $legSLan   = Invoke-Leg ('LEG 2 - the SAME account via ' + $lanIp + ' - MUST BE ADMITTED') $sshAcct $sshPw $lanIp
    $legNLocal = Invoke-Leg 'LEG 3 - the NONE account over LOOPBACK - MUST BE REFUSED' $noneAcct $nonePw 'localhost'
    $legNLan   = Invoke-Leg ('LEG 4 - the NONE account via ' + $lanIp + ' - MUST BE REFUSED') $noneAcct $nonePw $lanIp
    $legALocal = Invoke-Leg 'LEG 5 - the API account over LOOPBACK - MUST BE REFUSED (API takes ssh away)' $apiAcct $apiPw 'localhost'

    Write-Output '=== 5. the verdict ================================================'
    Note 'the SSH account is ADMITTED from this machine''s LAN address too (remote is allowed)' $true ($legSLan.Ran -and $legSLan.Banner) $true

    foreach ($x in @(
        @{ N = 'NONE over loopback'; L = $legNLocal },
        @{ N = 'NONE over the LAN address'; L = $legNLan },
        @{ N = 'API over loopback'; L = $legALocal })) {
        # ANCHORED ON POSITIVE EVIDENCE OF THE REFUSAL: a non-zero exit AND sshd's own wording.
        Note ($x.N + ': sshd refused it before authentication') $true $x.L.Denied $true
        Note ($x.N + ': it reached no session') $false $x.L.Ran $true
        Note ($x.N + ': SD was never reached (no banner)') $false $x.L.Banner $true
    }

    # ***THE DISCRIMINATOR IS THE KEYWORD.***  The SSH account and the NONE account differ in
    # nothing else, and were reached the same two ways.
    Note 'the KEYWORD decided, over both addresses: SSH in, NONE out' $true `
         (($legSLocal.Ran -and $legSLan.Ran) -and -not ($legNLocal.Ran -or $legNLan.Ran)) $true

    Write-Output ''
    Write-Output '=== 6. the audit trail, after - THE DECISIVE READING =============='
    $after = Get-AuditText
    $tail  = $after.Substring([Math]::Min($before.Length, $after.Length))
    Write-Output ("  audit grew by {0} bytes" -f ($after.Length - $before.Length))
    Write-Output '  --- what LOGIN wrote ---'
    foreach ($l in ($tail -split "`r?`n")) {
        if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
    }

    # sshd refuses BEFORE authentication for the NONE and API accounts, and LOGIN runs only after
    # it, so neither an admission nor a refusal line can exist for them.  Their PRESENCE is the
    # regression: sshd let the account through and SD caught it one layer later.
    Note 'the audit has NO admission for the NONE account' $false ($tail -match ('(?i)LOGIN account=' + [regex]::Escape($noneAcct))) $true
    Note 'the audit has NO admission for the API account'  $false ($tail -match ('(?i)LOGIN account=' + [regex]::Escape($apiAcct)))  $true
    Note 'the audit has NO refusal for either (sshd refused first)' $false `
         ($tail -match ('(?i)LOGIN REFUSED account=(' + [regex]::Escape($noneAcct) + '|' + [regex]::Escape($apiAcct) + ')')) $true

    # ***THE CONTROL IS WHAT MUST BE IN THE TRAIL, AND IT IS WHAT KEEPS THE ABSENCES HONEST.***
    # An absence also holds when the audit file is not being written at all.  The SSH account DID
    # authenticate, so its line must be present: that proves the trail is live.
    Note 'the audit records the SSH account''s admission (so the trail is live)' $true `
         ($tail -match ('(?i)LOGIN account=' + [regex]::Escape($sshAcct))) $true
    Note 'the audit trail actually moved' $true (($after.Length - $before.Length) -gt 0) $true

} finally {
    Write-Output ''
    Write-Output '=== cleanup ======================================================='
    foreach ($acct in @($sshAcct, $apiAcct, $noneAcct)) {
        $exists = ($null -ne (Get-LocalUser -Name $acct -ErrorAction SilentlyContinue))
        if (-not $exists) { continue }
        try {
            $rm = Invoke-SD (Remove-SdTestUserScript -Name $acct)
            Write-Output ("  DELETE.ACCOUNT {0}:" -f $acct)
            Write-Output $rm
        } catch {
            Write-Output ("  DELETE.ACCOUNT {0} threw: {1}" -f $acct, $_.Exception.Message)
        }
        $still = ($null -ne (Get-LocalUser -Name $acct -ErrorAction SilentlyContinue))
        if ($still) {
            # NAMED, LOUDLY: an account with a generated password left behind silently is the
            # worst outcome this script can have.
            Write-Output ''
            Write-Output ('  *** verify-sshadmin: ACCOUNT STILL EXISTS: ' + $acct)
            Write-Output  '  *** Remove it by hand.  In an ELEVATED PowerShell:'
            Write-Output ('  ***   Remove-LocalUser -Name ' + $acct)
        }
    }
}

Write-Output ''
Write-Output ("verify-sshadmin: {0} passed, {1} failed" -f $pass, $fail)
if (($pass + $fail) -eq 0) { Write-Output 'verify-sshadmin: COULD NOT RUN - no decisive check ran'; exit 2 }
if ($fail -gt 0) { exit 1 }
exit 0
