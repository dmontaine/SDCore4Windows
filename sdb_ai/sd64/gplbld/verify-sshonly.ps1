# verify-sshonly.ps1 - prove the ssh-only account model, PROJECT_STATUS.md 5.6.2.
#
#   powershell -File verify-sshonly.ps1             run the whole test, clean up
#   powershell -File verify-sshonly.ps1 -Keep       leave the probe account behind
#   powershell -File verify-sshonly.ps1 -RetestSsh  re-run only the key login
#   powershell -File verify-sshonly.ps1 -Cleanup    remove a probe left by -Keep
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run (not elevated, no sshd, no ssh client).
#
# WHY THIS EXISTS AS A TRACKED SCRIPT RATHER THAN A HANDFUL OF TYPED COMMANDS.
# 5.6.2 is decided, built and shipped in the installer, and until this runs it
# is entirely unproven.  The risk it carries is that it fails CLOSED: if
# Win32-OpenSSH needs a logon right that deny-logon.ps1 removes, then every
# account SD creates is locked out of the machine altogether and nobody can
# reach SD at all.  That has to be answered on a clean machine as well as this
# one - PROJECT_STATUS.md 7 step 2 - so the test is a file, not a session.
#
# THE EXPERIMENT IS A LADDER, THEN A TREATMENT.  Section 1 climbs three rungs,
# adding EXACTLY ONE GROUP AT A TIME, so that each refusal is attributable to
# the membership that was missing and to nothing else:
#
#   rung 1  no SD group           ssh refused AT THE DOOR by sshd's AllowGroups
#   rung 2  + sdssh               sshd ADMITS it; SD refuses - "Error 5 getting
#                                 semaphores", because the semaphore DACL names
#                                 sdusers and this token has not got it
#   rung 3  + sdusers             admitted.  This is the control.
#
# Sections 2-4 then add sdsshonly and test the deny rights - the treatment -
# against a control that can actually log in.
#
# WHY THE LADDER EXISTS, and it is a correction rather than an elaboration.
# Until 22 Aug 2026 there was one gate and one control, and the control WAS
# RUNG 2: in sdssh, never in sdusers.  So it could not log in, every ssh check
# in the file failed with Error 5, and the runs from b1 to b4 all exited 1
# having measured NOTHING about 5.6.2 - while the deny-rights rows they were
# supposed to support passed all along, by LogonUser, unnoticed underneath.
#
# THE FAILURE WAS THE FINDING.  "Error 5" was not a broken control; it was a
# SECOND GATE nobody had written a check for.  An account can satisfy sshd
# completely and still not reach SD.  That is a real property with a real
# failure mode - an account made by hand, given ssh, and left out of sdusers
# looks entirely set up and cannot run SD - so it is now rung 2 rather than an
# obstacle to get past.
#
# WHAT MAKES THE TWO REFUSALS TELLABLE APART is that they come from different
# components and do not look alike; SshVerdict below classifies them, and the
# raw text is printed either way.  Without that, rung 2 would restate rung 1.
#
# THE GROUPS ARE MEASURED, NOT ASSUMED.  sddefs.h:189 defines SD_USERS_GROUP as
# "sdusers"; sdsem.c:183 creates the semaphores with it as their DACL; sshd's
# AllowGroups names sdssh.  Neither is inferred from a comment in sd.iss.
#
# THREE MEASUREMENTS, because they cover different halves of what sshd does:
#
#   LogonUser()      the mechanism.  Win32-OpenSSH authenticates a PASSWORD
#                    with LOGON32_LOGON_NETWORK_CLEARTEXT (8) and a KEY with
#                    S4U, and neither is an interactive logon - which is why
#                    SeDenyNetworkLogonRight must not be set.  Calling it
#                    directly separates "the rights do what we think" from
#                    "sshd works", so a failure says which one broke.
#   ssh + password   the truth, and the case that matters: CREATE.ACCOUNT gives
#                    an account a password, not a key.  Automated through
#                    SSH_ASKPASS - see SshPassword below.
#   ssh + key        the S4U path.  Kept, but NOT decisive, and the comment on
#                    the key rows explains why.
#
# WHAT THIS SCRIPT STILL CANNOT PROVE, AND WHY IT NEEDS TWO MACHINES.  Remote
# Desktop denial.  SeDenyRemoteInteractiveLogonRight has no LogonUser type to
# test it with - RDP is logon type 10 and LogonUser cannot produce one - so
# only a real Remote Desktop connection exercises it.  The right is confirmed
# APPLIED by the secedit dump below, but never OBSERVED refusing a session.
#
# DO NOT TRY IT AGAINST THE MACHINE ITSELF - measured, not assumed.  On
# 14 Aug 2026, three attempts all answered "could not connect to another
# console session ... you already have a console session in progress", error
# 0x708: localhost with the signed-in user's credentials, localhost with the
# probe's, and the machine's own LAN address with the probe's.  The refusal
# comes BEFORE any credential prompt, so the account offered is irrelevant and
# so is how the machine is addressed.  RDP was enabled throughout.
#
# Run this with -Keep on the machine under test and RDP to it FROM A DIFFERENT
# MACHINE.  That is the only arrangement that reaches the logon check.
#
# DO NOT TRY TO DIAGNOSE THIS BY RUNNING "sshd -d" YOURSELF.  It was tried on
# 14 Aug 2026 and it cannot work: sshd must run as SYSTEM to build a user
# token, so an sshd started from an elevated administrator prompt answers
#   debug1: get_user_token - unable to generate user token ... as i am not
#   running as system
# for EVERY account, and the resulting log looks like a total authentication
# failure that has nothing to do with what is being tested.  The installed
# service runs as SYSTEM and is the only sshd whose verdict means anything; its
# reasons are in the OpenSSH/Operational event log.
#
# THE PROBE ACCOUNT IS A REAL WINDOWS ACCOUNT.  It is created with a random
# password from an alphabet chosen below, it is deleted at the end of a normal
# run, and cleanup refuses to touch any account that does not carry this
# script's marker in its description - so pointing it at a real account does
# nothing.

param(
    [string]$Account = 'sdsshprobe',
    [string]$Group   = 'sdsshonly',
    # 22 Aug 26 - THE GROUP sshd's AllowGroups NAMES.  Rung 1 of section 1.
    [string]$SshGroup = 'sdssh',
    # 22 Aug 26 - THE GROUP THE SEMAPHORE DACL NAMES.  Rung 2.  Measured, not
    # assumed: sddefs.h:189 defines SD_USERS_GROUP as "sdusers", sdsem.c:183
    # creates Global\sd_sem_716d0302_<n> with w32sem_create(name,
    # SD_USERS_GROUP, ...), and win32sem.c hands that straight to
    # build_descriptor() as the semaphore's DACL.  w32sem_open asks for
    # SEMAPHORE_ALL_ACCESS, so a token without the group is refused there.
    [string]$UsersGroup = 'sdusers',
    [switch]$Keep,
    [switch]$Cleanup,
    [switch]$RetestSsh
)

$ErrorActionPreference = 'Stop'

# 22 Aug 26 - A TRANSCRIPT, LIKE EVERY OTHER VERIFIER.  This was the ONLY one of
# the twenty-four without a Start-Transcript, and it is the one that keeps
# failing - so the single verifier under active investigation was the single one
# leaving no record.
#
# IT LOOKED LIKE IT HAD ONE, WHICH IS WHY IT SURVIVED.  Run through
# VerifyInstall1, the handover passes -Quiet and VerifyInstall2 redirects each
# step into its own file, so a log exists and nothing seems missing.  Run
# VerifyInstall2 DIRECTLY - which is exactly what a declined handover UAC prompt
# leaves you doing - and there is no -Quiet, so the output goes to a console
# that then closes.  The b3 run of 22 Aug lost its detail that way: the summary
# said exit 1 and nothing anywhere said why.
#
# A verifier's own transcript is thin under -Quiet, because a transcript records
# what reaches the HOST and -Quiet sends that to a file instead.  That is the
# documented cost in VerifyInstall2's header and it is fine: the two capture the
# same run by different routes, and between them one of them always has it.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-sshonly-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

$MARKER  = 'SD ssh-only verification probe - safe to delete'
$workdir = Join-Path $env:TEMP 'sd-sshonly-probe'
$keyfile = Join-Path $workdir 'probe_ed25519'
$askpass = Join-Path $workdir 'askpass.cmd'
$homedir = Join-Path $env:SystemDrive ('Users\' + $Account)

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check    = $step
        Expected = $expected
        Observed = $got
        Result   = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $step, $expected, $got)
}

# ---------------------------------------------------------- native commands --
# EVERY external program goes through here, and the reason is a PowerShell 5.1
# trap that cost this script its first run.  Redirecting a native program's
# stderr inline - "prog 2>&1" - wraps each stderr LINE in an ErrorRecord, and
# under $ErrorActionPreference = 'Stop' an ErrorRecord is a TERMINATING error.
# ssh prints "Warning: Permanently added 'localhost' to the list of known
# hosts" to stderr ON A SUCCESSFUL LOGIN, so the first run of this script died
# on a success message and reported FAILED.  Start-Process keeps the two
# streams in separate files and hands back a real exit code, which is what was
# wanted in the first place.  Stdin comes from an empty file, so anything that
# decides to prompt gets EOF and fails instead of hanging the run for ever.
# 15 Aug 26 - $StdIn EXISTS BECAUSE OF ForceCommand.  An empty stdin file was
# right while ssh ran a command and exited.  With the ssh-only model's global
# ForceCommand applied, sshd DISCARDS the client's command and runs SD instead,
# so ssh now opens an interactive SD session - and EOF at SD's ":" prompt is
# PROJECT_STATUS.md section 6's "leave a prompt unanswered and SD spins at full
# CPU".  Both verification scripts hung on it, 15 Aug 2026, with no timeout to
# save them: ConnectTimeout covers the TCP connect, not the session.  Feeding
# "OFF" logs the session off and lets ssh exit.
function Invoke-Native {
    param([string]$Exe, [string[]]$CmdArgs, [string]$StdIn = '')

    $so = Join-Path $workdir 'native.out'
    $se = Join-Path $workdir 'native.err'
    $si = Join-Path $workdir 'native.in'
    if ($StdIn -eq '') { Set-Content -Path $si -Value $null -Encoding ascii }
    else { [IO.File]::WriteAllText($si, $StdIn) }

    $p = Start-Process -FilePath $Exe -ArgumentList $CmdArgs -NoNewWindow -Wait -PassThru `
             -RedirectStandardOutput $so -RedirectStandardError $se -RedirectStandardInput $si

    $outTxt = ''
    $errTxt = ''
    if (Test-Path $so) { $outTxt = ((Get-Content $so) -join "`n").Trim() }
    if (Test-Path $se) { $errTxt = ((Get-Content $se) -join "`n").Trim() }

    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $outTxt; Err = $errTxt }
}

# ------------------------------------------------------------------ ssh log --
# Both login helpers share this.  LogLevel=ERROR silences the known-hosts
# warning that comes with StrictHostKeyChecking=no; it is only noise, but it is
# noise on stderr, and stderr on a SUCCESSFUL login is what broke the first run.
$sshCommon = @(
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=NUL',
    '-o', 'ConnectTimeout=20',
    '-o', 'LogLevel=ERROR')

# 15 Aug 26 - TWO PROOFS OF ADMISSION, BECAUSE ForceCommand MAY OR MAY NOT BE
# APPLIED.  Without it, ssh runs "whoami" and the account name comes back, which
# is what this always tested.  With it, sshd runs SD instead and the account
# name never appears - so the proof becomes SD's own login banner.  Both count
# as admitted: the question this asks is whether the account got IN, not what it
# landed on.  Keeping both means the script works either side of
# allow-ssh-groups.ps1, which is a manual step (PROJECT_STATUS.md header).
$sdBanner = 'String Database'

function SshResult($r) {
    if ($r.ExitCode -eq 0 -and $r.Out -match [regex]::Escape($Account)) { return 'admitted' }
    if ($r.Out -match $sdBanner) { return 'admitted' }
    $why = ($r.Out + ' ' + $r.Err).Trim() -replace '\s+', ' '
    if ($why -eq '') { $why = 'no output, exit ' + $r.ExitCode }
    return ('refused: ' + $why)
}

# 22 Aug 26 - WHICH GATE REFUSED, not merely that something did.  The ladder in
# section 1 turns one refusal into three distinct answers, and it can only do
# that because THE TWO REFUSALS DO NOT LOOK ALIKE.  Measured on the b4 run:
#
#   in no SD group    ssh: "Permission denied (publickey,password,keyboard-interactive)"
#   in sdssh, not sdusers  SD:  "Error 5 getting semaphores"
#
# The first is sshd turning the connection away at the door, before SD is
# reached at all.  The second is sshd ADMITTING it - AllowGroups is satisfied -
# and SD then failing to open its semaphores, because their DACL names sdusers
# and this token has not got it.  Two different components saying no.
#
# WITHOUT THIS the two rungs would both read "refused" and the second would be
# a restatement of the first, proving nothing.  The raw text is printed either
# way, so a change in anybody's wording is visible rather than silently
# reclassified.
# Write-Host, NOT Write-Output, AND THAT IS NOT A STYLE CHOICE - 22 Aug 2026.
# EVERYTHING A POWERSHELL FUNCTION WRITES TO THE OUTPUT STREAM IS PART OF WHAT
# IT RETURNS.  The first version of this used Write-Output for the diagnostic
# line, so it returned an ARRAY - the message and the verdict - and both gate
# rows failed with "got System.Object[]" while the underlying ssh attempts had
# been perfectly correct.  Measured on the b5 run.
#
# Write-Host goes to the host instead, so it is displayed and NOT returned.  It
# is still captured both ways that matter: Start-Transcript records what reaches
# the host, and VerifyInstall2's -Quiet redirect uses *> which takes stream 6
# with everything else.
function SshVerdict {
    $r = SshPassword
    Write-Host ("  ssh said: " + $r)
    if ($r -eq 'admitted')             { return 'admitted' }
    if ($r -match 'getting semaphores'){ return 'refused by SD' }
    return 'refused at the door'
}

# THE TEST THAT MATTERS, and it is automated rather than typed.
#
# ssh takes no password on the command line, by design.  It does however honour
# SSH_ASKPASS with SSH_ASKPASS_REQUIRE=force - measured on this client,
# OpenSSH_for_Windows_9.5, 14 Aug 2026 - so the password can be handed over by
# a helper program instead of by a person.  That matters for more than
# convenience: the password was first tested by hand, three attempts were
# logged as "Failed password", and the cause was almost certainly transcription
# of a 36 character random string rather than anything about the design.  A
# test a human can mistype is a test that reports failures that did not happen.
#
# THE PASSWORD DOES NOT GO IN THE HELPER FILE.  It travels in an environment
# variable that is removed in the finally block, so a crash cannot leave a
# password sitting in a file in TEMP.
function SshPassword {
    Set-Content -Path $askpass -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
    $env:SSH_ASKPASS = $askpass
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $env:DISPLAY = 'localhost:0'
    try {
        $r = Invoke-Native $sshExe.Source ($sshCommon + @(
            '-o', 'PreferredAuthentications=password',
            '-o', 'NumberOfPasswordPrompts=1',
            ($Account + '@localhost'), 'whoami')) -StdIn "OFF`n"
    } finally {
        Remove-Item Env:\SSH_ASKPASS, Env:\SSH_ASKPASS_REQUIRE, Env:\DISPLAY -ErrorAction SilentlyContinue
        Remove-Item $askpass -ErrorAction SilentlyContinue
    }
    return (SshResult $r)
}

# NOT DECISIVE, and here is why it is kept anyway.
#
# A Windows account that has never logged on has NO USER PROFILE, and
# Win32-OpenSSH resolves "AuthorizedKeysFile .ssh/authorized_keys" relative to
# the user's home directory.  So a key planted for a brand new account is never
# read, and the login is refused - which is what happened on the first run of
# this script, identically before and after the account joined sdsshonly.
#
# This is NOT an artefact of the test.  An account CREATE.ACCOUNT has just made
# has never logged on either, so key-only access to a new SD account cannot
# work until somebody has authenticated with a password once.  The row stays in
# the table to record that, and -RetestSsh confirms it after a password login.
function SshKey {
    $r = Invoke-Native $sshExe.Source ($sshCommon + @(
        '-i', ('"' + $keyfile + '"'),
        '-o', 'IdentitiesOnly=yes',
        '-o', 'BatchMode=yes',
        '-o', 'PreferredAuthentications=publickey',
        ($Account + '@localhost'), 'whoami')) -StdIn "OFF`n"
    return (SshResult $r)
}

# ---------------------------------------------------------------- LogonUser --
# There is no cmdlet for this.  LogonUser is the same call Win32-OpenSSH makes,
# so testing it directly is testing the thing itself rather than a proxy for it.
$logonSig = @'
using System;
using System.Runtime.InteropServices;

public class SdLogon {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out IntPtr token);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr handle);

    // 0 on success, otherwise the Win32 error.  1385 is
    // ERROR_LOGON_TYPE_NOT_GRANTED, which is what a deny right looks like.
    public static int Try(string user, string pass, int logonType) {
        IntPtr token = IntPtr.Zero;
        bool ok = LogonUser(user, ".", pass, logonType, 0, out token);
        if (!ok) return Marshal.GetLastWin32Error();
        CloseHandle(token);
        return 0;
    }
}
'@

$LOGON_INTERACTIVE       = 2
$LOGON_NETWORK           = 3
$LOGON_NETWORK_CLEARTEXT = 8

function LogonResult($user, $pass, $type) {
    $rc = [SdLogon]::Try($user, $pass, $type)
    if ($rc -eq 0) { return 'admitted' }
    if ($rc -eq 1385) { return 'refused 1385' }
    return ("refused " + $rc)
}

# ------------------------------------------------------------------ cleanup --
# Write-Host THROUGHOUT, AND IT IS LOAD BEARING HERE - 22 Aug 2026.  This
# function RETURNS A BOOLEAN THE CALLER BRANCHES ON, and everything a
# PowerShell function writes to the output stream is part of what it returns.
# With Write-Output the refusal path returned @("cleanup: REFUSING...", $false)
# - a NON-EMPTY ARRAY - and "if ($ok)" is TRUE for one.  So -Cleanup pointed at
# an account without this script's marker printed REFUSING and then EXITED 0,
# reporting success for a refusal.
#
# The protection itself always worked - the account is not touched - but the
# exit code said the opposite, which is the half a caller reads.  Found by
# sweeping for the same fault after SshVerdict above hit it; nothing else in
# the file returns a value it also prints around.
function Remove-Probe {
    $u = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
    if ($null -eq $u) {
        Write-Host "cleanup: no local user $Account"
    } elseif ($u.Description -ne $MARKER) {
        # Refusing here is the point.  An account this script did not create is
        # somebody's real account, whatever it happens to be called.
        Write-Host "cleanup: REFUSING to remove $Account - it does not carry this script's marker"
        return $false
    } else {
        Remove-LocalUser -Name $Account
        Write-Host "cleanup: removed local user $Account"
    }

    if (Test-Path $homedir) {
        Remove-Item -Recurse -Force $homedir -ErrorAction SilentlyContinue
        Write-Host "cleanup: removed $homedir"
    }
    if (Test-Path $workdir) {
        Remove-Item -Recurse -Force $workdir -ErrorAction SilentlyContinue
        Write-Host "cleanup: removed $workdir (key material)"
    }
    return $true
}

# -------------------------------------------------------------------- start --
try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output "verify-sshonly: not elevated - creating an account and setting user rights both need it"
        exit 2
    }

    if ($Cleanup) {
        $ok = Remove-Probe
        if ($ok) { exit 0 } else { exit 1 }
    }

    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($null -eq $svc -or $svc.Status -ne 'Running') {
        Write-Output "verify-sshonly: sshd is not running - run install-ssh.ps1 first"
        exit 2
    }
    $sshExe = (Get-Command ssh -ErrorAction SilentlyContinue)
    $keygenExe = (Get-Command ssh-keygen -ErrorAction SilentlyContinue)
    if ($null -eq $sshExe -or $null -eq $keygenExe) {
        Write-Output "verify-sshonly: no ssh client on PATH"
        exit 2
    }

    if ($RetestSsh) {
        $u = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
        if ($null -eq $u -or $u.Description -ne $MARKER) {
            Write-Output "verify-sshonly: no probe account to retest - run with -Keep first"
            exit 2
        }
        if (-not (Test-Path $keyfile)) {
            Write-Output ("verify-sshonly: the key from the -Keep run is gone (" + $keyfile + ")")
            exit 2
        }
        $sid = $u.SID.Value
        $hasProfile = Test-Path ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $sid)
        Write-Output ("  user profile exists for " + $Account + ": " + $hasProfile)
        Note 'retest: ssh with a key' 'admitted' (SshKey) $true
        if ($fatal) { exit 1 }
        exit 0
    }

    if (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue) {
        Write-Output "verify-sshonly: $Account already exists - run with -Cleanup first"
        exit 2
    }

    Add-Type -TypeDefinition $logonSig -Language CSharp | Out-Null

    # Invoke-Native keeps its stream files here, so it has to exist before the
    # first external command.
    if (Test-Path $workdir) { Remove-Item -Recurse -Force $workdir }
    New-Item -ItemType Directory -Path $workdir | Out-Null

    # A password nobody chose and nobody keeps.  The alphabet excludes I, l, 1,
    # O and 0 so that a human reading it off a console cannot transcribe it
    # wrongly, and excludes every character cmd.exe treats specially so that
    # the SSH_ASKPASS helper cannot mangle it.  Both of those are lessons from
    # the first run rather than caution for its own sake.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 20
    ([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $plain = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    $plain = $plain + '-Aa9'     # guarantees the complexity policy is satisfied
    $secure = ConvertTo-SecureString $plain -AsPlainText -Force
    $env:SDPROBEPW = $plain      # how SshPassword hands it to ssh; cleared below

    Write-Output ""
    Write-Output "=== 1. the gate ladder: one membership at a time ====================="
    Write-Output "  Each rung adds exactly ONE group and shows exactly ONE gate."

    # -NoPassword/-Disabled is deliberately NOT used here: this mirrors an
    # account that SET_PASSWD has already enabled, which is the state
    # CREATE.ACCOUNT leaves behind.  New-LocalUser joins NO group at all, not
    # even Users, which is where rung 1 starts.
    New-LocalUser -Name $Account -Password $secure -Description $MARKER `
        -AccountNeverExpires -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    Write-Output "  created local user $Account (random password, not stored)"

    # --- RUNG 1: no SD group at all -------------------------------------
    # sshd's AllowGroups has nothing to match, so the connection is turned away
    # AT THE DOOR and SD is never reached.
    Write-Output ""
    Write-Output "  rung 1: in no SD group"
    Note ('gate: ssh refused without ' + $SshGroup) 'refused at the door' (SshVerdict) $true

    # --- RUNG 2: + sdssh, and NOT sdusers -------------------------------
    # 22 Aug 26 - THIS RUNG IS THE b1-b3 FAILURE TURNED INTO AN ASSERTION.
    # Every run since the gate was added reported "Error 5 getting semaphores"
    # here and called it a broken control.  It is not broken - it is a SECOND
    # GATE, and nothing in the suite covered it: sshd ADMITS this account,
    # because AllowGroups is satisfied, and SD then refuses because the
    # semaphore DACL names sdusers and this token has not got it.
    #
    # WHY IT IS WORTH A CHECK RATHER THAN A STEP TO HURRY PAST: "an account
    # outside sdusers cannot reach SD at all, even over ssh" is a real property
    # of the product with a real failure mode - an account created by hand,
    # given ssh access, and left out of sdusers looks completely set up and
    # cannot run SD.  The message it produces is the one to recognise.
    if (-not (Get-LocalGroup -Name $SshGroup -ErrorAction SilentlyContinue)) {
        # NOT a failure of 5.6.2 - the group is the installer's to create, so a
        # missing one means the test cannot be run rather than that the design
        # is wrong.  Exit 2 says so, and the probe is removed on the way out.
        Write-Output ("verify-sshonly: the group " + $SshGroup + " does not exist - sshd's AllowGroups")
        Write-Output "  names it, so nothing can log in over ssh and there is no ladder to climb."
        Write-Output "  Run allow-ssh-groups.ps1, or install SD, and try again."
        Remove-Probe
        exit 2
    }
    Add-LocalGroupMember -Group $SshGroup -Member $Account
    Write-Output ""
    Write-Output ("  rung 2: added " + $Account + " to " + $SshGroup + " (still NOT in " + $UsersGroup + ")")
    Note ('gate: ssh admitted by sshd, refused by SD without ' + $UsersGroup) `
        'refused by SD' (SshVerdict) $true

    # --- RUNG 3: + sdusers - and now it is the control -------------------
    # ONE membership is the only thing that differs from rung 2, which is what
    # makes the admission below attributable to it and nothing else.
    if (-not (Get-LocalGroup -Name $UsersGroup -ErrorAction SilentlyContinue)) {
        Write-Output ("verify-sshonly: the group " + $UsersGroup + " does not exist - SD's semaphores")
        Write-Output "  and data tree are granted to it, so no account can run SD and there is"
        Write-Output "  no control to be had.  Install SD and try again."
        Remove-Probe
        exit 2
    }
    Add-LocalGroupMember -Group $UsersGroup -Member $Account
    Write-Output ""
    Write-Output ("  rung 3: added " + $Account + " to " + $UsersGroup + " - now an SD-shaped account")

    Note 'control: LogonUser INTERACTIVE'       'admitted' (LogonResult $Account $plain $LOGON_INTERACTIVE)       $true
    Note 'control: LogonUser NETWORK_CLEARTEXT' 'admitted' (LogonResult $Account $plain $LOGON_NETWORK_CLEARTEXT) $true
    Note 'control: ssh with a password'         'admitted' (SshPassword)                                          $true

    # Key material, for the non-decisive key rows.
    $r = Invoke-Native $keygenExe.Source @('-t', 'ed25519', '-f', ('"' + $keyfile + '"'), '-N', '""', '-C', '"sd ssh-only probe"', '-q')
    $r = Invoke-Native $keygenExe.Source @('-y', '-f', ('"' + $keyfile + '"'))
    if ($r.Out -notlike 'ssh-ed25519*') {
        Write-Output ("verify-sshonly: could not generate a passphraseless key - " + $r.Out + $r.Err)
        Remove-Probe
        exit 2
    }

    # sshd refuses a key file that anyone but the owner, SYSTEM or
    # Administrators can write - hence /inheritance:r rather than /grant alone,
    # the same rule as the data tree in 5.7.
    $sshdir = Join-Path $homedir '.ssh'
    New-Item -ItemType Directory -Path $sshdir -Force | Out-Null
    $ak = Join-Path $sshdir 'authorized_keys'
    Get-Content ($keyfile + '.pub') | Set-Content -Path $ak -Encoding ascii

    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    $null = Invoke-Native $icacls @(('"' + $homedir + '"'), '/inheritance:r',
        '/grant', '*S-1-5-18:(OI)(CI)F', '/grant', '*S-1-5-32-544:(OI)(CI)F',
        '/grant', ($Account + ':(OI)(CI)M'))
    $null = Invoke-Native $icacls @(('"' + $ak + '"'), '/inheritance:r',
        '/grant', '*S-1-5-18:F', '/grant', '*S-1-5-32-544:F',
        '/grant', ($Account + ':R'))

    # 22 Aug 26 - THE LABEL NO LONGER SAYS "no profile yet", because it is no
    # longer reliably true.  It was written when the control's PASSWORD login
    # was being refused by the gate above, so nothing had ever created a
    # profile by this point.  Now that the control is admitted, the password
    # login immediately before this may well have made one.  The row stays
    # non-decisive either way: what it records is that key-only access to a
    # never-logged-on account cannot work, and -RetestSsh is what confirms it
    # after a password login.
    Note 'control: ssh with a key' 'admitted' (SshKey) $false

    Write-Output ""
    Write-Output "=== 2. treatment: the group, the deny rights, and the account in it ====="

    if (-not (Get-LocalGroup -Name $Group -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $Group -Description 'SD accounts restricted to ssh' | Out-Null
        Write-Output "  created group $Group"
    } else {
        Write-Output "  group $Group already exists"
    }

    $denyScript = Join-Path $PSScriptRoot 'deny-logon.ps1'
    & $denyScript $Group
    if ($LASTEXITCODE -ne 0) {
        Write-Output "verify-sshonly: deny-logon.ps1 failed - stopping before anything is concluded"
        Remove-Probe
        exit 1
    }

    Add-LocalGroupMember -Group $Group -Member $Account
    Write-Output ("  added " + $Account + " to " + $Group)

    # Read the policy back.  secedit writes resolvable local groups BY NAME and
    # not by SID, so a check that greps for the SID reports "absent" when it is
    # present - PROJECT_STATUS.md 4 records that going wrong once already.
    $inf = Join-Path $workdir 'rights.inf'
    $r = Invoke-Native (Join-Path $env:SystemRoot 'System32\secedit.exe') @(
        '/export', '/areas', 'USER_RIGHTS', '/cfg', ('"' + $inf + '"'), '/quiet')
    if (-not (Test-Path $inf)) {
        Write-Output ("verify-sshonly: secedit wrote no policy file - exit " + $r.ExitCode + " " + $r.Err)
        Note 'policy: readable' 'exported' ('secedit exit ' + $r.ExitCode) $true
        $policy = @()
    } else {
        $policy = Get-Content $inf -Encoding Unicode
    }
    foreach ($right in @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight')) {
        $line = ($policy | Where-Object { $_ -match ('^' + $right + '\s*=') })
        $has = ($line -match [regex]::Escape($Group))
        Note ('policy: ' + $right) 'contains the group' $(if ($has) { 'contains the group' } else { 'ABSENT: ' + $line }) $true
    }
    $netline = ($policy | Where-Object { $_ -match '^SeDenyNetworkLogonRight\s*=' })
    $netbad = ($netline -match [regex]::Escape($Group))
    Note 'policy: SeDenyNetworkLogonRight' 'does NOT contain the group' $(if ($netbad) { 'CONTAINS IT - ssh will break' } else { 'does NOT contain the group' }) $true

    Write-Output ""
    Write-Output "=== 3. the questions the design turns on ==============================="

    # The console is refused...
    Note 'ssh-only: LogonUser INTERACTIVE'       'refused 1385' (LogonResult $Account $plain $LOGON_INTERACTIVE)       $true
    # ...and every route sshd uses is not.
    Note 'ssh-only: LogonUser NETWORK_CLEARTEXT' 'admitted'     (LogonResult $Account $plain $LOGON_NETWORK_CLEARTEXT) $true
    Note 'ssh-only: LogonUser NETWORK'           'admitted'     (LogonResult $Account $plain $LOGON_NETWORK)           $true
    # THIS IS THE ONE.  If it fails while the control passed, 5.6.2 is wrong.
    Note 'ssh-only: ssh with a password'         'admitted'     (SshPassword)                                          $true
    Note 'ssh-only: ssh with a key'              'admitted'     (SshKey)                                               $false

    Write-Output ""
    Write-Output "=== 4. does BUILTIN\Users membership matter? ==========================="
    Write-Output "  It does not, and the ladder in section 1 is what showed that."
    Write-Output "  This section used to ASK the question, because an SD account is in"
    Write-Output "  sdusers, sdu_<name> and $Group and nothing else - so if ssh only worked"
    Write-Output "  once Users was added, CREATE.ACCOUNT would have to add it too."
    Write-Output ""
    Write-Output "  22 Aug 26 - IT WAS ASKED THE WRONG WAY ROUND FOR AS LONG AS IT EXISTED."
    Write-Output "  Every run from b1 to b4 added Users here and STILL got Error 5, because"
    Write-Output "  the probe was not in sdusers and nothing in the file put it there.  The"
    Write-Output "  row was non-decisive, so it failed quietly and answered nothing.  Rung 3"
    Write-Output "  now grants sdusers and the login is admitted; adding Users on top of"
    Write-Output "  that changes nothing, which is the actual answer."

    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $Account -ErrorAction SilentlyContinue
    # STILL NOT DECISIVE, and now for a better reason than before: sdusers is
    # what carries this, so a change here would be a curiosity rather than a
    # failure of 5.6.2.  It is kept as a control on rung 3 - if adding a group
    # that should not matter DID matter, the ladder would be measuring
    # something other than what it claims.
    Note 'in Users as well: ssh still admitted' 'admitted' (SshPassword) $false

    Write-Output ""
    Write-Output "=== summary ============================================================"
    $results | Format-Table -AutoSize -Wrap | Out-String | Write-Output

    if ($Keep) {
        Write-Output "-Keep given, so the probe account survives.  It is a REAL Windows account:"
        Write-Output ("  user     " + $Account)
        Write-Output ("  password " + $plain)
        Write-Output ("  key      " + $keyfile)
        Write-Output ""
        Write-Output "  The one thing no script can do, because RDP has no LogonUser type:"
        Write-Output ("    mstsc /v:localhost      - sign in as " + $Account + ", expect refusal")
        Write-Output ""
        Write-Output "  A password login creates the user profile that key authentication needs,"
        Write-Output "  so if a password login has now succeeded, this should now pass:"
        Write-Output ("    powershell -File verify-sshonly.ps1 -RetestSsh")
        Write-Output ""
        Write-Output ("  Remove it with:  powershell -File verify-sshonly.ps1 -Cleanup")
    } else {
        Write-Output ""
        Remove-Probe
    }

    Write-Output ""
    Write-Output ("The " + $Group + " group and its deny rights are LEFT IN PLACE - that is what the")
    Write-Output ("installer does, and CREATE.ACCOUNT needs the group to exist.  To undo:")
    Write-Output ("  Remove-LocalGroup -Name " + $Group + "   (the rights go with the SID)")

    if ($fatal) { exit 1 }
    exit 0
}
catch {
    Write-Output ("verify-sshonly: FAILED - " + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    # NOT silenced.  The first version piped this to Out-Null, so a failed run
    # cleaned up and said nothing, leaving the reader to guess whether a real
    # Windows account had been left behind.
    Write-Output "--- cleaning up after the failure ---"
    try { Remove-Probe } catch { Write-Output ("cleanup itself failed: " + $_.Exception.Message) }
    exit 1
}
finally {
    Remove-Item Env:\SDPROBEPW -ErrorAction SilentlyContinue
}
