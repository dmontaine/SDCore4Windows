# verify-sshadmin.ps1 - prove that an SD ADMINISTRATOR gets no ssh session at
# all, and that a non-administrator still does.
#
#   powershell -File verify-sshadmin.ps1 -Prefix sdsshadm<run>
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# RUN IT ELEVATED.  CREATE.ACCOUNT is gated on K$ADMINISTRATOR, and this makes
# two accounts.  VerifyInstall2 is already elevated, so it costs no extra UAC
# prompt; run by hand it needs an elevated PowerShell.
#
# WHAT IT MEASURES.  PRE_RELEASE_FIXES.md 167 and PROJECT_STATUS.md 5.25.
# Owner's ruling, 5 Sep 2026: remote ssh and API access is TOTALLY DENIED to
# administrators - administration happens at the console or through a remote
# desktop installed as a service.  LOGIN refuses the session outright when
# sd_admin_tier(@logname) is true and kernel(K$INTERACTIVE, 0) is false.
#
#   ADMINISTRATOR over ssh   REFUSED, message 10174, no session      <- the gate
#   PROGRAMMER over ssh      ADMITTED, runs a command                <- the CONTROL
#
# ***THE CONTROL IS THE WHOLE REASON THIS IS TWO ACCOUNTS AND NOT ONE.***  A
# refusal on the first leg has causes that have nothing to do with the gate -
# sshd stopped, ForceCommand not starting SD, a password rejected, the host key
# changed - and EVERY ONE of them would make leg A look like a pass.  The
# second leg is what tells "the gate refused an administrator" from "ssh is
# broken on this machine".  Without it a green here would mean nothing, which
# is the trap CLAUDE.md's instrument rules name.
#
# WHY IT NEEDS NO SECOND MACHINE.  q14 was parked for weeks as "it needs the VM
# rig".  It does not: sshd runs on this host, and 167's own measurement was
# taken by ssh'ing to it, so ssh to localhost exercises exactly the path that
# was defective.  The token an ssh logon carries is built by sshd the same way
# whether the client is across the network or on the box - S-1-5-2 NETWORK and
# no S-1-5-4 INTERACTIVE - which is the thing under test.
#
# ***IT CREATES A REAL LOCAL ADMINISTRATOR, BRIEFLY, AND THAT IS DELIBERATE.***
# CREATE.ACCOUNT ... ADMINISTRATOR adds the Windows account to S-1-5-32-544
# (CREATEA:872), so leg A's account is a Windows administrator as well as an SD
# one - which is the state the defect was measured in.  verify-tiers.ps1 already
# makes one for the same reason.  Both accounts are removed in a finally block,
# and if removal fails the account is NAMED on the transcript rather than left
# silently behind.
#
# ANCHORED ON THE AUDIT TRAIL, NOT ON THE SCREEN.  The decisive reading is
# LOGIN's own record - "LOGIN REFUSED account=SDSYS reason=administrator on a
# session with no interactive desktop" - because it is written on the refusal
# path and nowhere else.  Message 10174's text is recorded too, and scored, but
# a screen can be empty for a dozen reasons; the audit line cannot be written by
# a session that never reached the gate.

[CmdletBinding()]
param(
    # Derived from -Run by the runner.  A FIXED prefix passes once and fails
    # every later run - PRE_RELEASE 54 - which is why this goes through
    # VerifyInstall2 rather than being called by hand with a constant.
    # Lower case only: it becomes a Windows account name.
    [string]$Prefix = ''

    # NO -HelperPipe, DELIBERATELY, and test-elevonce-units.ps1 is why this
    # sentence exists.  One was declared here in the first draft and never used:
    # this step launches no elevated child - the runner is already elevated and
    # Invoke-SD runs in-process - so there was nothing for a pipe to serve.
    # That guard's bidirectional check caught it in a second, which is exactly
    # the shape it was written for.  verify-sdsysgate.ps1 takes none either, for
    # the same reason.  If this ever DOES start an elevated child, add the
    # parameter AND the name to $helperAware in elevate-once.ps1, together.
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

Write-Output 'verify-sshadmin - PRE_RELEASE_FIXES.md 167, PROJECT_STATUS.md 5.25'
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
    Write-Output 'verify-sshadmin: this needs an ELEVATED PowerShell - CREATE.ACCOUNT is gated on K$ADMINISTRATOR.'
    exit 2
}

# Where LOGIN writes its refusals.
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

# ------------------------------------------------------------- local driver
# Piped stdin, in a job with a timeout.  Start-Process -RedirectStandardInput
# hands sd.exe a FILE HANDLE and SD answers ":Process terminated" and runs
# nothing - written down 14 Aug 2026 and paid for again on 29 Aug.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    if ($null -eq $commands -or $commands.Count -eq 0) {
        throw 'Invoke-SD: no commands given; that would start a session, measure nothing and look like a pass.'
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

$adminAcct = ($Prefix + 'a')
$progAcct  = ($Prefix + 'p')
$adminPw   = New-SdTestPassword
$progPw    = New-SdTestPassword
$madeAdmin = $false
$madeProg  = $false

try {
    Write-Output '=== 1. two accounts: one ADMINISTRATOR, one PROGRAMMER ============'

    # ADMINISTRATOR is matched on the token TEXT (CREATEA:1524) and cannot be
    # abbreviated.  SSH so the account may be reached at all.
    $outA = Invoke-SD @(('CREATE.ACCOUNT USER ' + $adminAcct + ' ADMINISTRATOR SSH'), $adminPw, $adminPw)
    Write-Output '  --- CREATE.ACCOUNT (administrator) said: ---'
    Write-Output $outA

    $outP = Invoke-SD (New-SdTestUserScript -Name $progAcct -Password $progPw)
    Write-Output '  --- CREATE.ACCOUNT (programmer) said: ---'
    Write-Output $outP

    # ***THE CONTROL IS WINDOWS, NOT SD's WORDING.***  A verb that refused still
    # echoes the account name it was given, so reading the transcript back for
    # it is the false-positive shape CLAUDE.md names.
    $madeAdmin = ($null -ne (Get-LocalUser -Name $adminAcct -ErrorAction SilentlyContinue))
    $madeProg  = ($null -ne (Get-LocalUser -Name $progAcct  -ErrorAction SilentlyContinue))
    Note 'the administrator account exists in Windows' $true $madeAdmin $true
    Note 'the programmer account exists in Windows'    $true $madeProg  $true
    if (-not ($madeAdmin -and $madeProg)) {
        Write-Output 'verify-sshadmin: an account was not created - nothing below could measure anything.'
        exit 2
    }

    # AND THE ADMINISTRATOR ONE MUST REALLY BE ONE, or leg A proves nothing: a
    # refusal of a non-administrator is not the rule under test.
    $admins = @()
    try {
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
                    ForEach-Object { ($_.Name -split '\\')[-1].ToLower() })
    } catch {
        Write-Output ('verify-sshadmin: could not read the Administrators group - ' + $_.Exception.Message)
        exit 2
    }
    Note 'Administrators was readable'                  $true ($admins.Count -gt 0)        $true
    Note 'the admin account IS a Windows administrator' $true ($admins -contains $adminAcct) $true
    Note 'the control account is NOT'                   $false ($admins -contains $progAcct) $true
    Write-Output ''

    # --------------------------------------------------------- the measurement

    Write-Output '=== 2. the audit trail, before ===================================='
    $before = [IO.File]::ReadAllText($audit)
    Write-Output ("  audit is {0} bytes before" -f $before.Length)
    Write-Output ''

    Write-Output '=== 3. LEG A - the ADMINISTRATOR tries to ssh in =================='
    $ra = $null
    try {
        $ra = Invoke-SdAsTestUser -Name $adminAcct -Password $adminPw -Commands @('WHO')
    } catch {
        Write-Output ("verify-sshadmin: could not drive ssh as {0} - {1}" -f $adminAcct, $_.Exception.Message)
        exit 2
    }
    $textA = ($ra.Out | Out-String)
    Write-Output ("  ssh exit {0}, {1} characters of output" -f $ra.ExitCode, $textA.Length)
    Write-Output '  --- the session said: ---'
    Write-Output $textA
    if ($ra.Err -ne '') {
        Write-Output '  --- ssh stderr ---'
        Write-Output $ra.Err
    }
    Write-Output ''

    Write-Output '=== 4. LEG B - the CONTROL, a PROGRAMMER, over the same route ====='
    $rb = $null
    try {
        $rb = Invoke-SdAsTestUser -Name $progAcct -Password $progPw -Commands @('WHO')
    } catch {
        Write-Output ("verify-sshadmin: could not drive ssh as {0} - {1}" -f $progAcct, $_.Exception.Message)
        exit 2
    }
    $textB = ($rb.Out | Out-String)
    Write-Output ("  ssh exit {0}, {1} characters of output" -f $rb.ExitCode, $textB.Length)
    Write-Output '  --- the session said: ---'
    Write-Output $textB
    Write-Output ''

    # ***THE CONTROL IS SCORED FIRST, AND IT GATES EVERYTHING.***  If a
    # non-administrator cannot get in either, ssh is broken on this machine and
    # leg A's refusal says nothing about the gate.
    Write-Output '=== 5. the verdict ================================================'
    $controlRan = ($textB -match '(?i)\b' + [regex]::Escape($progAcct) + '\b')
    Note 'CONTROL: a non-administrator still gets a session' $true $controlRan $true
    if (-not $controlRan) {
        Write-Output 'verify-sshadmin: the CONTROL did not get in, so ssh itself is suspect.'
        Write-Output '  Leg A is NOT scored below - a refusal here would prove nothing about the gate.'
        exit 2
    }

    # Leg A, on the SUCCESS WORDING of the refusal - a phrase that appears only
    # when the gate fired.  10174 opens "An administrator may not sign in over
    # ssh or the API"; nothing on the admitted path prints it.
    $sawMsg = ($textA -match '(?i)may not sign in over ssh')
    Note 'the refusal message (10174) was shown' $true $sawMsg $true

    # AND THE DISQUALIFIER.  A live session answers WHO with the account name
    # and a user number.  If that appears, the gate did not fire, whatever else
    # was printed.
    $reachedSdsys = ($textA -match '(?i)\bSDSYS\b\s*$' -or
                     $textA -match '(?i)\b' + [regex]::Escape($adminAcct) + '\b')
    Note 'the administrator did NOT reach a session' $false $reachedSdsys $true

    Write-Output ''
    Write-Output '=== 6. the audit trail, after - THE DECISIVE READING =============='
    $after = [IO.File]::ReadAllText($audit)
    $tail  = $after.Substring([Math]::Min($before.Length, $after.Length))
    Write-Output ("  audit grew by {0} bytes" -f ($after.Length - $before.Length))
    Write-Output '  --- what LOGIN wrote ---'
    foreach ($l in ($tail -split "`r?`n")) {
        if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
    }

    # Written on the refusal path and nowhere else.  LOGIN sets
    # audit.reason = 'administrator on a session with no interactive desktop'
    # and terminate.connection writes "LOGIN REFUSED account=... reason=...".
    $auditSaysRefused = ($tail -match '(?i)LOGIN REFUSED' -and
                         $tail -match '(?i)no interactive desktop')
    Note 'the audit records the refusal, with the reason' $true $auditSaysRefused $true

    # A trail that did not move at all means the session never reached LOGIN -
    # which is not the gate working, it is the measurement failing.
    Note 'the audit trail actually moved' $true (($after.Length - $before.Length) -gt 0) $true

} finally {
    Write-Output ''
    Write-Output '=== cleanup ======================================================='
    foreach ($acct in @($adminAcct, $progAcct)) {
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
            # NAMED, LOUDLY.  One of these is a local ADMINISTRATOR with a
            # generated password; leaving it behind silently is the worst
            # outcome this script can have.
            Write-Output ''
            Write-Output ('  *** verify-sshadmin: ACCOUNT STILL EXISTS: ' + $acct)
            Write-Output  '  *** Remove it by hand.  In an ELEVATED PowerShell:'
            Write-Output ('  ***   Remove-LocalUser -Name ' + $acct)
            Write-Output  '  *** If it was the administrator one, check it is out of Administrators too.'
        }
    }
}

Write-Output ''
Write-Output ("verify-sshadmin: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
