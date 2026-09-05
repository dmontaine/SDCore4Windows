# verify-doors.ps1 - the UNELEVATED half of the SUSPENDED door test.  It
# measures the three doors and creates nothing.  PRE_RELEASE 19's last row and
# PRE_RELEASE 38.
#
#   powershell -File verify-doors.ps1 -Prefix sddr1 -Password '<pw>' -Phase Control
#   powershell -File verify-doors.ps1 -Prefix sddr1 -Password '<pw>' -Phase Refused
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.  verify-doors-admin.ps1 is the other half and prints these
# commands with the password filled in.
#
# ***IT REFUSES TO RUN ELEVATED, AND THAT IS THE POINT OF THE FILE.***
# CPROC's logto.authorised puts the suspension test AFTER two privileged
# bypasses (CPROC:3729 elevated, CPROC:3755 elevation just obtained) - a
# recorded judgement call at CPROC:3765, not an oversight.  An elevated session
# therefore ENTERS a suspended account, correctly.  verify-tiers.ps1 section 6
# says so in its own output and declines to test the door for exactly this
# reason; this file is the session that can.
#
# ***THE THREE DOORS, AND WHAT EACH ONE'S REFUSAL ACTUALLY LOOKS LIKE.***
#
#   LOGIN   LOGIN:477 -> 10107.  ssh AUTHENTICATES FINE - suspension moves no
#           Windows group, so sdssh still admits the account and sshd's
#           ForceCommand still starts SD.  It is SD that says no, so the
#           evidence is 10107 IN THE SESSION OUTPUT, not an ssh failure.  A run
#           where ssh itself failed would be measuring the wrong thing.
#   logto   CPROC:3776 -> 10107, from this unelevated session.
#   API     APISRVR:507 -> 10003, and ***10003 IS DELIBERATELY WHAT "no such
#           account" AND "not granted" ALSO ANSWER***, so no wording can
#           identify it.  Only the CONTROLLED PAIR can: the same account, the
#           same password, the same call, admitted in the Control phase and
#           refused in the Refused phase.  The one variable between the two runs
#           is the suspension.  This file says that out loud rather than
#           pretending the refusal identifies itself.
#
# ***WHICH IS WHY THE Control PHASE IS NOT A FORMALITY.***  If a door refuses
# before the suspension, its refusal afterwards proves nothing at all - and the
# likeliest causes are mundane: a wrong password, or the caller not being in the
# account's group.  A failed Control phase is a stop, not a curiosity.
#
# IT CHANGES NOTHING.  No account, no group, no sd.conf, no service.  The only
# side effect is a profile directory Windows creates when the account signs in
# over ssh for the first time, which the admin half's Remove phase reports.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [Parameter(Mandatory = $true)] [string] $Password,
    [Parameter(Mandatory = $true)] [ValidateSet('Control', 'Refused')] [string] $Phase,
    [int]    $Port      = 4243,
    # 04 Sep 26 - PRE_RELEASE_FIXES 161, and this one mattered MORE than
    # verify-tierapi's identical default.  That step refuses out loud when the
    # binary is missing; THIS one Skips door 3 and still exits 0, so on b116 the
    # API door went untested in both phases inside a green step.  "make sd" now
    # builds sd-connect.exe beside the 32-bit DLL, derived from $PSScriptRoot
    # rather than pointing at a deleted repository.
    [string] $SdConnect = (Join-Path $PSScriptRoot '..\bin\client32\sd-connect.exe')
)

$ErrorActionPreference = 'Stop'

$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$accts  = Join-Path $env:ProgramData  'SD\sdsys\accounts'
$acct   = $Prefix + 'a'
$acctU  = $acct.ToUpper()

# ***THE SECOND ACCOUNT, AND IT IS WHAT MAKES THE logto DOOR MEASURABLE AT
# ALL.***  28 Aug 2026, PRE_RELEASE 44.  `A` signs in over ssh and issues
# `LOGTO B` from inside that session.  The point is the TOKEN: Windows fixes
# group membership at logon, so the session that CREATED B - and was added to
# `sdu_B` a moment later - cannot carry that SID, and its chdir into B's
# directory is denied with 5161 even though SD's own authorisation passed.
# A fresh ssh logon carries the group, so this is the only session that can
# reach the door.  The door table in PRE_RELEASE_FIXES.md specified this shape
# before it was built; the first implementation ran LOGTO in the caller's own
# session and scored a false pass for a day.
$helper  = $Prefix + 'b'
$helperU = $helper.ToUpper()

$workdir = Join-Path $env:TEMP 'sd-doors-probe'
$askpass = Join-Path $workdir 'askpass.cmd'

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

function Skip($step, $why) {
    $null = $results.Add([pscustomobject]@{
        Check = $step; Expected = 'measured'; Observed = 'NOT MEASURED'
        Result = 'SKIP'; Decisive = 'no' })
    Write-Output ("  [SKIP] {0}: {1}" -f $step, $why)
}

# 24 Aug 26 - THE VERDICT LINE.  Kept BYTE-FOR-BYTE IDENTICAL to the other
# copies; test-verdict-units.ps1 asserts that across all of them.
function Write-Verdict($name) {
    $all      = @($script:results)
    $decisive = @($all | Where-Object { $_.Decisive -eq 'yes' })
    $failed   = @($decisive | Where-Object { $_.Result -ne 'PASS' })

    Write-Output ""
    if ($decisive.Count -eq 0) {
        Write-Output ("{0}: FAILED - NO DECISIVE CHECK RAN, so this run proves nothing." -f $name)
        Write-Output ("  {0} row(s) recorded, none of them decisive." -f $all.Count)
        $script:fatal = $true
        return
    }
    if ($failed.Count -gt 0) {
        Write-Output ("{0}: FAILED - {1} of {2} decisive checks failed:" -f $name, $failed.Count, $decisive.Count)
        $failed | ForEach-Object { Write-Output ("    " + $_.Check) }
        $script:fatal = $true
        return
    }
    Write-Output ("{0}: PASSED - {1} of {1} decisive checks passed, {2} row(s) in all." -f
                  $name, $decisive.Count, $all.Count)
}

function Test-Say([string]$text, [string]$pattern) {
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return ([regex]::IsMatch($text, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline))
}

# ------------------------------------------------------------------ Invoke-SD
#
# ***NO "LOGTO SDSYS" PREAMBLE, UNLIKE EVERY OTHER VERIFIER.***  That is
# administrator-only, and this session is deliberately not.  The session starts
# in the caller's own account and the LOGTO under test is the only one issued.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** Stop-Process the sdwind PID it names."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# COPIED FROM verify-sshonly.ps1 UNCHANGED.  Start-Process keeps stdout and
# stderr in separate files and hands back a real exit code: under
# ErrorActionPreference Stop an ErrorRecord from a native exe is TERMINATING,
# and ssh writes "Warning: Permanently added ..." to stderr ON SUCCESS.
# Stdin comes from a file so anything that prompts gets EOF rather than hanging.
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

# ***ONE ssh SESSION, USED BY TWO DOORS.***  The LOGIN door signs in as the
# account under test; the logto door signs in as the helper and drives SD down
# stdin.  sshd's ForceCommand starts SD either way, so the remote "command" is
# decoration and stdin is the real input - which is why $StdIn carries the SD
# lines and the argument stays 'whoami'.
#
# The askpass file is written and deleted around every call, and the password
# lives in an environment variable of THIS process only.
function Invoke-SshSession([string]$User, [string]$Pw, [string]$StdIn) {
    $sshCommon = @('-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=NUL',
                   '-o', 'ConnectTimeout=20', '-o', 'LogLevel=ERROR')
    $env:SDPROBEPW = $Pw
    Set-Content -Path $askpass -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
    $env:SSH_ASKPASS = $askpass
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $env:DISPLAY = 'localhost:0'
    try {
        return Invoke-Native $sshExe.Source ($sshCommon + @(
                   '-o', 'PreferredAuthentications=password',
                   '-o', 'NumberOfPasswordPrompts=1',
                   ($User + '@localhost'), 'whoami')) -StdIn $StdIn
    } finally {
        Remove-Item Env:\SSH_ASKPASS, Env:\SSH_ASKPASS_REQUIRE, Env:\DISPLAY, Env:\SDPROBEPW `
                    -ErrorAction SilentlyContinue
        Remove-Item $askpass -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------- preconditions

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-doors: this must run UNELEVATED and this session is elevated.'
    Write-Output '  CPROC:3765 puts the suspension test AFTER the elevated bypass, so an'
    Write-Output '  elevated session ENTERS a suspended account - correctly.  Measuring the'
    Write-Output '  logto door from here would report the design working as a fault, which is'
    Write-Output '  the exact mistake verify-tiers.ps1 section 6 declines to make.'
    Write-Output '  Run verify-doors-admin.ps1 elevated; run THIS in an ordinary prompt.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1') -Quiet | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-doors: the installed tree does not match source - run a cycle first.'
    exit 2
}

foreach ($n in @($acctU, $helperU)) {
    if (-not (Test-Path -LiteralPath (Join-Path $accts $n))) {
        Write-Output ("verify-doors: no ACCOUNTS record for {0}." -f $n)
        Write-Output '  Run verify-doors-admin.ps1 -Phase Create, ELEVATED, first - it makes'
        Write-Output ('  BOTH accounts: {0} is the one under test and {1} is the helper whose' -f $acctU, $helperU)
        Write-Output '  ssh session carries the group SID this one cannot (PRE_RELEASE 44).'
        exit 2
    }
}

$sshExe = Get-Command ssh.exe -ErrorAction SilentlyContinue
if ($null -eq $sshExe) {
    Write-Output 'verify-doors: ssh.exe is not on PATH - the LOGIN door cannot be measured.'
    exit 2
}
if (-not (Test-Path -LiteralPath $workdir)) { New-Item -ItemType Directory -Path $workdir | Out-Null }

$expect = $(if ($Phase -eq 'Control') { 'admitted' } else { 'refused' })

Write-Output ("verify-doors: as {0}, UNELEVATED, -Phase {1}" -f $id.Name, $Phase)
Write-Output ("  account  {0}   (the one under test)" -f $acct)
Write-Output ("  helper   {0}   (its ssh session issues the LOGTO - PRE_RELEASE 44)" -f $helper)
Write-Output ("  expecting every door to be {0}" -f $expect.ToUpper())
Write-Output ("  ssh      {0}" -f $sshExe.Source)
Write-Output ("  api      {0}  ->  127.0.0.1:{1}" -f $SdConnect, $Port)
Write-Output ''

# ============================================================ door 1: LOGIN

Write-Output '=== door 1: LOGIN (ssh) - LOGIN:477 -> 10107 =============================='

# ***SUSPENSION MOVES NO WINDOWS GROUP***, so ssh authenticates in BOTH phases
# and sshd's ForceCommand starts SD in both.  The difference is what SD says.
$r = Invoke-SshSession $acct $Password "OFF`n"
$sshText = ($r.Out + "`n" + $r.Err)
Write-Output ("  ssh exit {0}" -f $r.ExitCode)
Write-Output '  --- ssh said: ---'
foreach ($line in ($sshText -split "`n")) { Write-Output ("  | " + $line.TrimEnd()) }
Write-Output ''

$sshSuspended = Test-Say $sshText 'is suspended'

if ($Phase -eq 'Control') {
    # ADMITTED means SD came up: either whoami answered, or SD's banner did.
    $ok = ($r.ExitCode -eq 0) -or (Test-Say $sshText 'SD Core for Windows') -or
          (Test-Say $sshText ([regex]::Escape($acct)))
    Note 'ssh: the account is admitted before suspension' $true $ok $true
    Note 'ssh: SD did NOT say "is suspended"' $false $sshSuspended $true
} else {
    # ***THE ANCHOR IS SD'S WORDING, NOT AN ssh FAILURE.***  ssh failing would
    # mean the account had lost a Windows group, which is a different defect
    # and would score a false pass on "refused".
    Note 'ssh: SD refused it with 10107 "is suspended"' $true $sshSuspended $true
}

# ============================================================ door 2: logto

Write-Output '=== door 2: logto - CPROC:3776 -> 10107 ==================================='

# ***THE MEASUREMENT IS THE HELPER'S ssh SESSION, NOT THIS ONE.***  PRE_RELEASE
# 44: this process's token was built at logon and cannot carry `sdu_<acct>`,
# which was created minutes ago, so its chdir into the account is denied with
# 5161 no matter what SD authorises.  The helper signs in fresh and its token
# carries the group.  Both are run, and only the helper's is decisive - the
# local one stays as a NON-DECISIVE witness of 44 in the same transcript, so
# the reason the door needs two accounts is visible rather than remembered.
Write-Output ('  the LOGTO is issued from ' + $helper + "'s ssh session - see PRE_RELEASE 44")
Write-Output ''

$rl = Invoke-SshSession $helper $Password ("TERM 200,9999`nLOGTO " + $acctU + "`nWHO`nOFF`n")
$out = ($rl.Out + "`n" + $rl.Err)
Write-Output ("  ssh exit {0}   (as {1})" -f $rl.ExitCode, $helper)
Write-Output '  --- SD said, in the helper session: ---'
foreach ($line in ($out -split "`n")) { Write-Output ("  | " + $line.TrimEnd()) }
Write-Output ''

$logtoSuspended = Test-Say $out 'is suspended'

# ***THE ANCHOR IS WHO'S ANSWER, NOT THE NAME ANYWHERE IN THE TEXT.***  The
# session ECHOES what it is fed, so ':LOGTO SDDRB50A' puts the account name in
# the transcript whether the LOGTO landed or not, and the old
# "Test-Say $out $acctU" therefore reported success on the failure path.
#
# MEASURED ON THE -Run b50 CONTROL LEG, 28 Aug 2026: SD printed 5161 "Unable
# to change to new directory", WHO answered "91 DON" - the session never left
# DON - and this check said PASS.  It also said PASS on sddr2 the same day,
# which is what "logto ADMITTED" in PROJECT_STATUS rests on.
#
# newvoc/who is "Verb to show user number and account", so WHO's answer is
# "<number> <ACCOUNT>" and the account must be the second field on a line whose
# first field is a number.  Nothing the caller typed can produce that shape:
# the echo is ":LOGTO <ACCT>", which does not begin with a digit.
#
# ***AND THE FIRST FIX ANCHORED THAT ON `\s*$`, WHICH WAS THE SAME TRAP FROM
# THE OTHER SIDE.***  Measured on -Run b52: the LOGTO SUCCEEDED and WHO
# answered "91 SDDRB52A from SDDRB52B" - the "from <account>" clause appears
# ONLY when the session has logto'd, so an end-of-line anchor matched only the
# case where it had NOT.  The original check matched the name anywhere and
# passed on the failure path; its replacement matched only at end of line and
# failed on the success path.  ***BOTH WERE WRITTEN FROM A TRANSCRIPT OF THE
# WRONG PATH*** - the lesson is not "anchor tighter", it is LOOK AT THE OUTPUT
# THE TOOL PRINTS WHEN IT SUCCEEDS.
$logtoEntered = $false
$logtoFromHelper = $false
foreach ($l in ($out -split "`n")) {
    if ($l -match ('^\s*\d+\s+' + [regex]::Escape($acctU) + '\b')) { $logtoEntered = $true }
    # ***THE "from" CLAUSE IS THE STRONGER EVIDENCE AND IT IS FREE.***  It says
    # the session ARRIVED here rather than started here, which is the entire
    # claim the Control leg makes.  A session that had simply begun in the
    # account would print the account and no "from".
    if ($l -match ('^\s*\d+\s+' + [regex]::Escape($acctU) + '\s+from\s+' + [regex]::Escape($helperU) + '\b')) {
        $logtoFromHelper = $true
    }
}

# ***CONTROL: THE FAILURE WORDING IS A DISQUALIFIER IN ITS OWN RIGHT.***  5161
# is the chdir failing AFTER the register and group checks have both passed,
# so it is not a refusal and none of the "was NOT refused" rows below see it.
# A leg where the positive anchor matched AND this matched is not a pass.
$logtoNoDir = Test-Say $out 'Unable to change to new directory'

if ($Phase -eq 'Control') {
    Note 'logto: entered the account before suspension' $true $logtoEntered $true
    Note ('logto: WHO says it arrived from ' + $helperU) $true $logtoFromHelper $true
    Note 'logto: SD did NOT report 5161 "Unable to change to new directory"' `
         $false $logtoNoDir $true
    Note 'logto: SD did NOT say "is suspended"' $false $logtoSuspended $true
    # THE OTHER REFUSAL THIS COULD BE.  If the helper is not in the account's
    # group, logto is refused for a reason that has nothing to do with the
    # suspension - and would be refused in the second phase too.
    Note 'logto: it was NOT refused for group membership' $false `
         (Test-Say $out 'not allowed in requested account') $true
} else {
    Note 'logto: refused with 10107 "is suspended"' $true $logtoSuspended $true
    Note 'logto: it was NOT the group-membership refusal instead' $false `
         (Test-Say $out 'not allowed in requested account') $true
    # ***AND NOT 5161 EITHER.***  A suspended account is refused at
    # logto.authorised (CPROC:2679), BEFORE the chdir at :2691, so a Refused
    # leg that reports 5161 has been stopped by the token rather than by the
    # suspension - the same false pass as the Control leg's, wearing the other
    # face.
    Note 'logto: it was NOT 5161 instead of the suspension' $false $logtoNoDir $true
}

# ***THE NON-DECISIVE WITNESS FOR PRE_RELEASE 44.***  The same LOGTO from THIS
# session, whose token predates the group.  It is expected to fail, it decides
# nothing, and it is here so the transcript carries the evidence for why the
# helper exists - a comment saying so would be a claim, and this is a
# measurement.
$local = Invoke-SD @(('LOGTO ' + $acctU), 'WHO')
$localEntered = $false
foreach ($l in ($local -split "`n")) {
    if ($l -match ('^\s*\d+\s+' + [regex]::Escape($acctU) + '\s*$')) { $localEntered = $true }
}
Write-Output '  --- and the same LOGTO from THIS session, for comparison: ---'
foreach ($line in ($local -split "`n")) { Write-Output ("  | " + $line.TrimEnd()) }
Write-Output ''
# ***THE 5161 CLAIM IS CONTROL-ONLY, AND THE b53 RUN IS WHY.***  In the
# Refused phase this session's LOGTO is stopped by the SUSPENSION at
# logto.authorised (CPROC:2679) and never reaches the chdir at :2691, so 5161
# correctly does NOT appear - and the row asserting it did printed a [FAIL]
# inside an otherwise green leg.  Non-decisive, so it changed no verdict, but a
# failure line in a passing run is noise that teaches people to skim.
#
# **IT WAS ALSO A SECOND WITNESS TO THE ORDERING**, which is why the refusal
# half of every door is trustworthy: the suspension is checked BEFORE the
# token-dependent chdir, so the Refused leg cannot be fooled by 44.
#
# 31 Aug 26 - ***THE PHASE SPLIT IS GONE: BOTH PHASES NOW BEHAVE THE SAME FOR
# THIS CALLER, AND PRE_RELEASE 91 IS WHY.***  91 put a test on the PERSON in
# logto.authorised ABOVE the SUSPENDED block, so an administrator as themselves
# is admitted there exactly as an elevated session always was.  DON therefore
# never reaches the suspension in either phase and is stopped by the
# token-dependent chdir in both.  Measured on -Run b84 and again on b85: WHO
# answered "107 DON" and the leg saw 5161, not 10107.  PRE_RELEASE_FIXES 92.
#
# ***THE ORDERING CLAIM IS NOT LOST, AND THAT IS WHAT MAKES THIS SAFE TO
# RETIRE HERE.***  It is still made at the decisive row above - "logto: it was
# NOT 5161 instead of the suspension" - on the HELPER, which is a caller the
# suspension does apply to.  This row was the SECOND witness to it, on a caller
# that can no longer reach the test at all.
#
# ***AND THIS IS NOT ENTRY 64's FORBIDDEN FLIP.***  That is changing $true to
# $false on the SAME observation, which leaves a row passing without measuring
# anything.  The SUBJECT changed here: DON is an administrator who now
# legitimately gets past the suspension, so the row measures what he actually
# does - and gains the disqualifier below, which nothing had before.
Note ('PRE_RELEASE 44: this session''s own LOGTO reports 5161') $true `
     (Test-Say $local 'Unable to change to new directory') $false

# ***THE CONTROL, AND IT IS THE HALF THAT EARNS ITS PLACE.***  If 10107 ever
# appears here, 91's administrator bypass has regressed and DON is being
# refused by the suspension again - which is the one way this row could go back
# to reading FAIL for a reason that matters.  Non-decisive like its neighbours,
# because this session is the witness and the helper is the measurement.
Note ('PRE_RELEASE 92: and NOT by the suspension - 91''s bypass admitted it') $false `
     (Test-Say $local 'is suspended') $false
# THIS ONE HOLDS IN BOTH PHASES: whatever stopped it, this session never got in.
Note ('PRE_RELEASE 44: this session''s own LOGTO did NOT enter') $false $localEntered $false

# ============================================================== door 3: API

Write-Output '=== door 3: the API - APISRVR:507 -> 10003 ================================'

$tcp = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet
if (-not (Test-Path -LiteralPath $SdConnect)) {
    Skip 'API door' ("sd-connect.exe not found at " + $SdConnect)
} elseif (-not $tcp) {
    Skip 'API door' ("nothing is listening on 127.0.0.1:" + $Port + " - APIPORT is off")
} else {
    # sd-connect exits 0 for a connect, 1 for a refusal, 2 for bad usage.  ***2
    # IS A BROKEN CALL AND MUST NEVER BE READ AS A REFUSAL*** - that is
    # verify-tierapi.ps1's rule and the same trap applies here, where a refusal
    # is what the Refused phase is hoping to see.
    $o  = & $SdConnect '127.0.0.1' "$Port" $acct $Password $acctU 2>&1
    $rc = $LASTEXITCODE
    Write-Output ("  sd-connect exit {0}" -f $rc)
    foreach ($line in (($o -join "`n") -split "`n")) { Write-Output ("  | " + $line.TrimEnd()) }
    Write-Output ''

    if ($rc -eq 2) {
        Skip 'API door' 'sd-connect rejected its arguments - a bug in this call, not a refusal'
    } elseif ($Phase -eq 'Control') {
        Note 'API: connected before suspension' 0 $rc $true
    } else {
        Note 'API: refused after suspension' 1 $rc $true
        Write-Output '  NOTE: APISRVR:507 answers 10003, which is ALSO what "no such account"'
        Write-Output '  and "not granted" answer - deliberately.  Nothing in this refusal'
        Write-Output '  identifies the suspension.  What identifies it is the CONTROL run:'
        Write-Output '  same account, same password, same call, admitted then refused, with the'
        Write-Output '  suspension the only thing changed in between.'
    }
}

# ---------------------------------------------------------------------- report

Write-Output ''
$results | Format-Table -AutoSize -Wrap | Out-String | Write-Output

$skipped = @($results | Where-Object { $_.Result -eq 'SKIP' })
if ($skipped.Count -gt 0) {
    Write-Output ("{0} row(s) were NOT MEASURED and are not counted as passes:" -f $skipped.Count)
    $skipped | ForEach-Object { Write-Output ('    ' + $_.Check) }
}

if ($Phase -eq 'Control') {
    Write-Output ''
    if ($fatal) {
        Write-Output '  *** STOP.  A door refused BEFORE the suspension, so its refusal after'
        Write-Output '  one would prove nothing.  The likeliest causes are mundane: the wrong'
        Write-Output '  password, or the caller not in the account group.  Fix that first.'
    } else {
        Write-Output '  NEXT - ELEVATED:'
        Write-Output ('    ' + (Join-Path $PSScriptRoot 'verify-doors-admin.ps1') + ' -Prefix ' + $Prefix + ' -Phase Suspend')
    }
} else {
    Write-Output ''
    Write-Output '  NEXT - ELEVATED, to take the fixture away:'
    Write-Output ('    ' + (Join-Path $PSScriptRoot 'verify-doors-admin.ps1') + ' -Prefix ' + $Prefix + ' -Phase Remove')
}

Write-Verdict 'verify-doors'

if ($fatal) { exit 1 }
exit 0
