# verify-pygate.ps1 - does the Python gate refuse a real NON-ADMINISTRATOR, and
# admit the same account once its os.users record says it may?  RELEASE_1.1 23,
# and the only witness RELEASE_1.1 21's two new codes can have.
#
#   VerifyInstall2.ps1 -Run <token> -Only verify-pygate      the only supported way
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# ***WHAT IT MEASURES, AND WHY NOTHING ELSE COULD.***  sdpy_session.c decides
# once per session whether a Python helper may be started: an administrator
# always may, otherwise OS.USERS field 2 decides (section 8 constraint 4).
# Every run of verify-pyapi is ELEVATED, so USR_ADMIN takes the first branch
# and the os.users branch - the reason the gate exists - is never entered.
# Exercising it needs a session that is genuinely NOT an administrator, which
# on this machine means a throwaway account reached over ssh: sshd builds the
# token itself, and for a non-member of Administrators it is an ordinary one.
#
# ***THE SHAPE IS A CONTROLLED TRIPLE***: one account, one compiled program,
# and ONLY the os.users record varies between legs.
#
#   leg  os.users\<account>       may_start_helper()   PY_INITIALIZE
#   A    absent                   refused, answered    -12041  SD_PyErr_NotPermitted
#   B    "yes" - no newline       refused, UNDETERMINED (PRIV_MALFORMED)
#                                                      -12042  SD_PyErr_PrivUnknown
#   C    "yes" NL "yes" NL        admitted             0, and SDPY-42 comes back
#
# A and C are the gate doing its job in both directions; a gate that refuses
# everybody passes A and fails C, and one that admits everybody does the
# reverse.  B is RELEASE_1.1 21's third code, reachable only by a record
# op_sh.c cannot parse, and it is the one leg where the errlog is decisive:
# the refusal must be logged as undetermined (PRE_RELEASE 96), the way
# OS.EXECUTE's is.
#
# ***WHY THE EXPECTED VALUE ON LEG A IS THE FINDING THIS FILE WAS WRITTEN
# FOR.***  As the gate shipped on 12 Sep 2026 it called the WHOLE of
# os_permitted(), whose first test answers TRUE on HDR_INTERNAL - and the
# opcode that starts the helper executes inside !PY_INITIALIZE, which is
# $internal (flags word 0x22 in the shipped object).  So leg A would have
# printed PYGATE-INIT=0 and leg C would have looked identical to it: the gate
# admitted every user, and every elevated run agreed with it.  RELEASE_1.1 23
# split os_permitted() so the Python gate asks tests 2 and 3 only; this is the
# run-time witness, and test-privwhy-units is the free one.
#
# ***THE DECISIVE STRING ON LEG C IS ONE ONLY PYTHON CAN PRODUCE.***  SDPY-42
# requires CPython to have evaluated 6*7 and the bytes to have come home; it
# cannot appear in an echoed command, a refusal or an error text.  On legs A
# and B its ABSENCE is decisive for the same reason.  The status codes are
# scored too, but a leg that scored only on a code could be satisfied by the
# wrong refusal.
#
# ***TWO CONTROLS THAT MAKE A REFUSAL MEAN SOMETHING***, copied from
# verify-sdsysgate: Get-LocalUser must confirm the account exists - SD's own
# wording is not evidence, a verb that refused still echoes the name - and
# the account must be confirmed NOT in Administrators, or a refusal proves
# nothing and an admission looks like the defect.  And a third of this file's
# own: the record must be ABSENT after CREATE.ACCOUNT, because CREATEA writes
# one automatically for ADMINISTRATOR-tier accounts (PRE_RELEASE 2) and leg A
# is meaningless if it wrote one here.
#
# ***WHAT WOULD FALSIFY LEG C WITHOUT SAYING ANYTHING ABOUT THE GATE, SAID
# OUT LOUD.***  Nothing before this file had established that a
# non-administrator can start sdpy.exe at all.  A -12040 on leg C means the
# helper did not start - the binary, python3.dll, or CreateProcess as this
# user - and is reported as that, not as a gate failure.  A -12042 on leg C
# means the record could not be READ by the account (secure-osusers.ps1 grants
# sdusers RX; CREATEA puts the account in sdusers) and is reported as that.
#
# ***IT MUST RUN ELEVATED AND LIVES IN VerifyInstall2, AND THAT IS FORCED***:
# CREATE.ACCOUNT and DELETE.ACCOUNT need an elevated SDSYS session, and
# writing under sdsys\os.users needs Administrators (that ACL is the whole of
# the protection, op_sh.c's banner says).  The session it MEASURES is ssh's,
# a fresh logon with the account's own token whatever the parent is.
#
# PROGRAMMER, NOT STANDARD, and it is load-bearing: STANDARD has no 'basic'
# or 'run' (sdtestuser.ps1's header has the measurement), so the probe could
# not be compiled.  It is still a real non-administrator - the tier that
# LOGIN elevates is ADMINISTRATOR, and this is not it.
#
# THE PREFIX IS SINGLE-USE, like every account-creating verifier here.  It is
# the Windows account name AND the os.users record name op_sh.c looks up
# verbatim, so a leftover from an earlier run would be measured instead of a
# fresh one; both are refused up front.

[CmdletBinding()]
param(
    # NOT Mandatory, DELIBERATELY.  A Mandatory parameter with nothing to bind
    # makes PowerShell's BINDER prompt, which inside a runner is a hang rather
    # than an error - the trap that cost a run on 28 Aug 2026.  The refusal
    # below is the guard, and it must be reachable.
    [string] $Prefix = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdpyExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sdpy.exe'
$sysdir  = Join-Path $env:ProgramData  'SD\sdsys'
$osUsers = Join-Path $sysdir 'os.users'
$errlog  = Join-Path $sysdir 'errlog'

# ------------------------------------------------------------- the reporter

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($step, $expected, $got, $decisive) {
    # ***A COLLECTION IS NOT AN OBSERVATION.***  Measured on b141, 13 Sep 2026:
    # Invoke-Leg both printed and RETURNED, so PowerShell folded its
    # Write-Output lines into the return value - nothing was printed, and
    # "$a -match 'x'" ran on an ARRAY, which returns the matching ELEMENTS.
    # Every leg row then passed with an Observed of {SD Core for Windows...}
    # or {}, and was right only because ($true -eq <non-empty array>) is true
    # and ($true -eq @()) is false - checked afterwards, both directions.  A
    # verdict that is correct by accident with its evidence unprinted is the
    # instrument rule's exact subject, so this refuses the shape outright.
    if (($null -ne $got) -and (($got -is [array]) -or ($got -is [System.Collections.ICollection]))) {
        throw ("Note '{0}': Observed is a collection of {1} - a pattern was matched against an array, not a transcript.  Broken instrument, not a result." -f $step, @($got).Count)
    }
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $step; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
}

# ------------------------------------------------------------- preconditions

if ($Prefix -eq '') {
    Write-Output 'verify-pygate: refusing - no -Prefix was given.'
    Write-Output '  It names the throwaway account AND its os.users record, and must come from'
    Write-Output '  the run token, so a second run on the same machine cannot measure the'
    Write-Output '  first run''s leftovers.  Run it the supported way:'
    Write-Output ''
    Write-Output '      C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\VerifyInstall2.ps1 -Run <token> -Only verify-pygate'
    Write-Output ''
    exit 2
}
# -cnotmatch, CASE SENSITIVE.  -notmatch is not, so 'SdPyG' would pass a check
# whose message promises lower case - measured on this file's first dry run.
if ($Prefix -cnotmatch '^[a-z][a-z0-9_]*$') {
    Write-Output ("verify-pygate: refusing - -Prefix is '{0}'." -f $Prefix)
    Write-Output '  Lower case letters, digits and underscore only, starting with a letter: it'
    Write-Output '  becomes a Windows account name and an os.users record name.'
    exit 2
}

$account = $Prefix.ToLower()
$record  = Join-Path $osUsers $account

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-pygate: this needs an ELEVATED session and this one is not.'
    Write-Output '  It creates and removes an account through an SDSYS session, and writes'
    Write-Output '  under sdsys\os.users, which is writable only by administrators.'
    Write-Output '  Run it from VerifyInstall2, or from an ELEVATED PowerShell.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-pygate: the installed tree does not match source - run a cycle first.'
    Write-Output '  This measures op_sh.c and sdpy_session.c, which are C: a stale install'
    Write-Output '  answers for the gate the change replaced.'
    exit 2
}

foreach ($p in @($sdExe, $osUsers)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("verify-pygate: {0} does not exist - nothing could be measured." -f $p)
        exit 2
    }
}
if (-not (Test-Path -LiteralPath $sdpyExe)) {
    Write-Output ("verify-pygate: NO HELPER at {0}." -f $sdpyExe)
    Write-Output '  That is RELEASE_1.1 19''s shape, not a gate fault: with no helper every'
    Write-Output '  leg answers -12040 and the gate is never the thing being measured.'
    exit 2
}

if ($null -ne (Get-LocalUser -Name $account -ErrorAction SilentlyContinue)) {
    Write-Output ("verify-pygate: refusing - the Windows account '{0}' already exists." -f $account)
    Write-Output '  The prefix is single-use.  Measuring a leftover account would be measuring'
    Write-Output '  the previous run, and it may not even be a non-administrator any more.'
    Write-Output '  Remove it, or use a fresh -Run token.'
    exit 2
}
if (Test-Path -LiteralPath (Join-Path $sysdir ('accounts\' + $account.ToUpper()))) {
    Write-Output ("verify-pygate: refusing - {0} is still in the ACCOUNTS register from an earlier run." -f $account.ToUpper())
    Write-Output '  Use a fresh -Run token.'
    exit 2
}
if (Test-Path -LiteralPath $record) {
    Write-Output ("verify-pygate: refusing - {0} already exists." -f $record)
    Write-Output '  Leg A needs the record ABSENT, and a record that was there before this run'
    Write-Output '  is somebody''s decision, not this test''s to overwrite.  Use a fresh -Run token.'
    exit 2
}

# ***ECHO THE REAL INPUTS, NOT THE INTENDED ONES.***  A probe whose arguments
# were clobbered reported a pass on 23 Aug 2026 and the echoed line is what
# caught it.
Write-Output ("verify-pygate: as {0}, ELEVATED" -f $id.Name)
Write-Output ("  sd       {0}" -f $sdExe)
Write-Output ("  sdpy     {0}   ({1} bytes)" -f $sdpyExe, (Get-Item -LiteralPath $sdpyExe).Length)
Write-Output ("  os.users {0}" -f $osUsers)
Write-Output ("  errlog   {0}" -f $errlog)
Write-Output ("  account  {0}   (from -Prefix '{1}')" -f $account, $Prefix)
Write-Output ("  record   {0}" -f $record)
Write-Output ''

# ------------------------------------------------------------- SD, elevated

# Piped stdin, inside a job with a timeout.  Start-Process
# -RedirectStandardInput hands sd.exe a FILE HANDLE and SD answers
# ":Process terminated" and runs nothing - written down 14 Aug 2026 and paid
# for again on 29 Aug.  Nothing here may use it.
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
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** It leaves the session's user-table slot and locks behind, so"
        $out += "*** sdwind will not shut down and cycle.ps1 will refuse to start."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# ------------------------------------------------------------- the errlog

# Read it with FileShare::ReadWrite - the daemon holds it open across its own
# write, and a plain Get-Content intermittently answers "in use by another
# process" rather than the contents.  Lifted from verify-privundetermined.ps1.
function Get-ErrlogText {
    if (-not (Test-Path -LiteralPath $errlog)) { return '' }
    $fs = [System.IO.File]::Open($errlog, [System.IO.FileMode]::Open,
                                 [System.IO.FileAccess]::Read,
                                 [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}

# THE DELTA, AND IT REFUSES TO GUESS.  log_message() trims the front off errlog
# when it reaches sysseg->errlog bytes (k_error.c), so the only safe delta is
# one where the old text is still a PREFIX of the new.  Otherwise Ok=$false
# and the caller reports "rotated" rather than a number nobody can stand
# behind.  Same function as verify-privundetermined.ps1's.
function Get-ErrlogDelta([string]$before) {
    $after = Get-ErrlogText
    if ($after.Length -ge $before.Length -and $after.StartsWith($before, [System.StringComparison]::Ordinal)) {
        return @{ Ok = $true; Text = $after.Substring($before.Length) }
    }
    return @{ Ok = $false; Text = '' }
}

# ------------------------------------------------------------- one leg

# Run the compiled probe as the test account, print EVERYTHING it said, and
# leave the text in $script:legText ($null if the leg could not run).  The
# null case is refused here, once: over ssh the same silence has causes that
# are nothing to do with the gate - a refused password, sshd down,
# ForceCommand not starting SD.
#
# ***IT RETURNS NOTHING, AND THAT IS THE FIX FOR b141.***  This function used
# to "return $text", and in PowerShell a function's Write-Output lines ARE its
# return value - so every line below was captured into the caller's variable
# instead of reaching the transcript, and the caller matched patterns against
# an array.  The rows still came out right (see Note), but the raw output the
# instrument rule demands was never printed.  A function that prints must not
# also return; the text travels through script scope instead.
function Invoke-Leg([string]$label) {
    $script:legText = $null
    $r = $null
    try {
        $r = Invoke-SdAsTestUser -Name $script:account -Password $script:password `
                 -Commands @('RUN BP PYGATE')
    } catch {
        Write-Output ("verify-pygate: could not drive SD as {0} - {1}" -f $script:account, $_.Exception.Message)
        return
    }
    $text = ($r.Out | Out-String)
    Write-Output ("  ssh exit {0}, {1} characters of output" -f $r.ExitCode, $text.Length)
    if ($r.Err -ne '') {
        Write-Output '  --- ssh stderr ---'
        foreach ($l in ($r.Err -split "`n")) {
            if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
        }
    }
    Write-Output '  --- the session said, in full (rule: print the raw output every time): ---'
    Write-Output $text
    Write-Output '  --- end ---'
    Note ("{0}: the session produced output" -f $label) $true ($text.Trim().Length -gt 0) $true
    if ($text.Trim().Length -eq 0) {
        Write-Output ("verify-pygate: {0} said nothing - it never ran, so nothing was measured." -f $label)
        return
    }
    # A PROGRAM THAT DID NOT REACH ITS LAST LINE IS SCORED AS A FAILURE, NOT
    # REFUSED: the ssh route has already been proved by the compile step, so a
    # missing PYGATE-DONE here is an observation about the product - a PY_*
    # that aborted the caller - and hiding it behind exit 2 would hide that.
    Note ("{0}: the probe ran to its last line (PYGATE-DONE)" -f $label) $true ($text -match 'PYGATE-DONE') $true
    $script:legText = $text
}

# ------------------------------------------------------------- the account

$password = New-SdTestPassword
$created  = $false
$wroteRecord = $false

try {
    Write-Output '=== 1. a real non-administrator account ==========================='

    $mk  = New-SdTestUserScript -Name $account -Password $password
    $out = Invoke-SD $mk
    Write-Output '  --- CREATE.ACCOUNT said: ---'
    Write-Output $out

    # ***THE CONTROL IS WINDOWS, NOT SD's OWN WORDING.***  A verb that refused
    # still echoes the account name, so reading the transcript for it is the
    # false-positive shape CLAUDE.md names.  Get-LocalUser is independent of
    # anything SD printed.
    $lu = Get-LocalUser -Name $account -ErrorAction SilentlyContinue
    $created = ($null -ne $lu)
    Note 'the account exists in Windows' $true $created $true
    if (-not $created) {
        Write-Output 'verify-pygate: the account was not created - nothing below could measure anything.'
        exit 2
    }

    # AND IT MUST NOT BE AN ADMINISTRATOR, or the whole test is inverted: an
    # administrator is SUPPOSED to be admitted on the USR_ADMIN branch, so a
    # refusal would prove nothing and an admission would look like the defect.
    $admins = @()
    try {
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
                    ForEach-Object { ($_.Name -split '\\')[-1].ToLower() })
    } catch {
        Write-Output ('verify-pygate: could not read the Administrators group - ' + $_.Exception.Message)
        Write-Output '  That check is the one that makes a refusal meaningful, so this refuses too.'
        exit 2
    }
    Note 'the Administrators group was readable' $true ($admins.Count -gt 0) $true
    Note 'the account is NOT an administrator' $false ($admins -contains $account) $true
    Write-Output ("  Administrators has {0} member(s); '{1}' among them: {2}" -f
                  $admins.Count, $account, ($admins -contains $account))

    # THE THIRD CONTROL.  CREATEA writes an os.users record ("yes","yes") only
    # for an account asked for one - grant.os.access, reached by the SH-ON and
    # OS-ON keywords.  This account is created with neither and must have got
    # none, or leg A is measuring a record instead of its absence.  A record
    # here is a product change nobody asked for, and the run cannot proceed on
    # its premise, so it is scored AND refused.
    #
    # 19 Sep 26 - the two paragraphs here used to say "for every
    # ADMINISTRATOR-tier account (PRE_RELEASE 2) ... this one is PROGRAMMER".
    # RELEASE_1.1 64 abolished the tiers and refuses both keywords; the premise
    # is unchanged and its REASON is now the keyword, not the level.
    $recordAfterCreate = (Test-Path -LiteralPath $record)
    Note 'CREATE.ACCOUNT with no SH-ON/OS-ON wrote NO os.users record (leg A''s premise)' $false $recordAfterCreate $true
    if ($recordAfterCreate) {
        Write-Output ("verify-pygate: {0} exists straight after CREATE.ACCOUNT." -f $record)
        Write-Output '  CREATEA writes one only where SH-ON or OS-ON was asked for, and this'
        Write-Output '  account was created with neither.  CREATEA has changed.'
        Write-Output '  Leg A cannot be measured on this premise, so nothing below runs.'
        exit 2
    }

    $acctDir = Get-SdTestUserHome -Name $account
    $bp      = Join-Path $acctDir 'BP'
    Note 'the account directory exists' $true (Test-Path -LiteralPath $acctDir) $true
    Note 'the account has a BP file' $true (Test-Path -LiteralPath $bp) $true
    if (-not (Test-Path -LiteralPath $bp)) {
        Write-Output ("verify-pygate: no BP at {0} - the probe has nowhere to go." -f $bp)
        exit 2
    }
    Write-Output ("  account directory: {0}" -f $acctDir)
    Write-Output ''

    # --------------------------------------------------------- the probe

    Write-Output '=== 2. the probe, planted and compiled as the account ============='

    # WRITTEN STRAIGHT INTO THE FILE SYSTEM.  BP is a DIRECTORY file, so each
    # record is a file on disk and a probe can be placed without driving ED
    # through a pipe.  latin-1 and LF to match the BASIC sources this tree
    # ships - NOT Set-Content (verify-nocase.ps1 is the precedent).
    #
    # The deffuns are declared here rather than $include SDPYFUNC.H, so the
    # probe tests the CATALOGUED programs; verify-pyapi drives the include.
    #
    # PY_INITIALIZE IS CALLED TWICE ON PURPOSE.  RELEASE_1.1 21 found that a
    # refused session's SECOND call returned a bare -12040 while the first
    # returned the real reason; INIT2 must equal INIT on every leg.
    #
    # PY_IS_INITIALIZED asks nothing and starts nothing (op_sdext.c), so on a
    # refused leg it answers 0 without touching the gate.
    $probeSrc = Join-Path $bp 'PYGATE'
    $probeObj = Join-Path $acctDir 'bp.out\PYGATE'
    $src = @(
        '* PYGATE - written by gplbld/verify-pygate.ps1.  Safe to delete.'
        "deffun PY_INITIALIZE() calling '!PY_INITIALIZE'"
        "deffun PY_IS_INITIALIZED() calling '!PY_IS_INITIALIZED'"
        "deffun PY_RUNSTRING(s) calling '!PY_RUNSTRING'"
        "deffun PY_GETATTR(o) calling '!PY_GETATTR'"
        "deffun PY_FINALIZE() calling '!PY_FINALIZE'"
        '   st = PY_INITIALIZE()'
        "   crt 'PYGATE-INIT=':st"
        '   st2 = PY_INITIALIZE()'
        "   crt 'PYGATE-INIT2=':st2"
        '   ii = PY_IS_INITIALIZED()'
        "   crt 'PYGATE-ISINIT=':ii"
        "   rs = PY_RUNSTRING(""zz_gate = 'SDPY-' + str(6*7)"")"
        "   crt 'PYGATE-RUN=':rs"
        "   vv = PY_GETATTR('zz_gate')"
        "   crt 'PYGATE-ATTR=':vv"
        '   fs = PY_FINALIZE()'
        "   crt 'PYGATE-FIN=':fs"
        "   crt 'PYGATE-DONE'"
    ) -join "`n"
    [System.IO.File]::WriteAllText($probeSrc, $src + "`n",
                                   [System.Text.Encoding]::GetEncoding('iso-8859-1'))
    Note 'the probe source was planted in BP' $true (Test-Path -LiteralPath $probeSrc) $true

    # COMPILED OVER ssh AS THE ACCOUNT, in its own session, so a compile
    # failure is not tangled with leg A's transcript.  The object's existence
    # is the check, not BASIC's wording.
    $r = $null
    try {
        $r = Invoke-SdAsTestUser -Name $account -Password $password -Commands @('BASIC BP PYGATE')
    } catch {
        Write-Output ("verify-pygate: could not drive SD as {0} - {1}" -f $account, $_.Exception.Message)
        exit 2
    }
    $ctext = ($r.Out | Out-String)
    Write-Output ("  ssh exit {0}, {1} characters of output" -f $r.ExitCode, $ctext.Length)
    if ($r.Err -ne '') {
        Write-Output '  --- ssh stderr ---'
        foreach ($l in ($r.Err -split "`n")) {
            if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
        }
    }
    Write-Output '  --- BASIC said: ---'
    Write-Output $ctext
    Note 'the compile session produced output' $true ($ctext.Trim().Length -gt 0) $true
    $built = (Test-Path -LiteralPath $probeObj)
    Note 'the probe compiled (object in bp.out)' $true $built $true
    if (-not $built) {
        Write-Output ("verify-pygate: no object at {0} - the probe cannot run, so the gate cannot be measured." -f $probeObj)
        if ($ctext.Trim().Length -eq 0) {
            Write-Output '  The compile session said NOTHING: a refused password, sshd down, or'
            Write-Output '  ForceCommand not starting SD - none of them is the gate.'
        }
        exit 2
    }
    Write-Output ''

    # --------------------------------------------------------- leg A

    Write-Output '=== 3. leg A - record ABSENT: refused, -12041 ======================'
    Note 'leg A: the os.users record is absent' $false (Test-Path -LiteralPath $record) $true
    Invoke-Leg 'leg A'
    $a = $script:legText
    if ($null -eq $a) { exit 2 }

    # ***THE MEASUREMENT.***  -12041 is SD_PyErr_NotPermitted: the gate ran,
    # completed, and said no.
    Note 'leg A: PY_INITIALIZE = -12041 (not permitted)'           $true ($a -match 'PYGATE-INIT=-12041')  $true
    Note 'leg A: the second PY_INITIALIZE gave the SAME answer (21)' $true ($a -match 'PYGATE-INIT2=-12041') $true
    Note 'leg A: PY_IS_INITIALIZED = 0 (no helper was started)'    $true ($a -match 'PYGATE-ISINIT=0')     $true
    Note 'leg A: PY_RUNSTRING = -12041 (still refused)'            $true ($a -match 'PYGATE-RUN=-12041')   $true
    # THE DECISIVE ABSENCE.  If CPython evaluated 6*7 for this session, the
    # gate admitted a non-administrator with no record - the 12 Sep defect.
    Note 'leg A: SDPY-42 does NOT appear (no interpreter ran)'      $false ($a -match 'SDPY-42')            $true
    # DISQUALIFIERS: the helper was never the thing being asked.
    Note 'leg A: no -12040 (helper would not start) anywhere'      $false ($a -match '-12040')             $true
    Note 'leg A: no -12042 (undetermined) anywhere'                $false ($a -match '-12042')             $true
    if ($a -match 'PYGATE-INIT=0') {
        Write-Output ''
        Write-Output '  *** PY_INITIALIZE RETURNED 0 WITH NO os.users RECORD.  THE GATE ADMITTED A'
        Write-Output '  *** NON-ADMINISTRATOR.  That is the 12 Sep 2026 shape - RELEASE_1.1 23:'
        Write-Output '  *** sd_os_permitted() going through os_permitted()''s HDR_INTERNAL test.'
        Write-Output '  *** test-privwhy-units guards the split; check it against this tree.'
    }
    Write-Output ''

    # --------------------------------------------------------- leg B

    Write-Output '=== 4. leg B - record MALFORMED: refused, -12042, and LOGGED ========'
    # One field and no newline, which op_sh.c reads as PRIV_MALFORMED ("the
    # os.users record has no second field").  NOT "yes<LF>" - that has a
    # second field which is empty, and empty is an ANSWERED no (-12041).
    [System.IO.File]::WriteAllText($record, 'yes', [System.Text.Encoding]::GetEncoding('iso-8859-1'))
    $wroteRecord = $true
    $bytesB = (Get-Item -LiteralPath $record).Length
    Write-Output ("  wrote {0}: 'yes' with no newline ({1} bytes)" -f $record, $bytesB)
    Note 'leg B: the malformed record is in place (3 bytes)' 3 $bytesB $true

    $logBefore = Get-ErrlogText
    Write-Output ("  errlog is {0} bytes before" -f $logBefore.Length)

    Invoke-Leg 'leg B'
    $b = $script:legText
    if ($null -eq $b) { exit 2 }

    Note 'leg B: PY_INITIALIZE = -12042 (permission undetermined)'  $true ($b -match 'PYGATE-INIT=-12042')  $true
    Note 'leg B: the second PY_INITIALIZE gave the SAME answer (21)' $true ($b -match 'PYGATE-INIT2=-12042') $true
    Note 'leg B: SDPY-42 does NOT appear'                           $false ($b -match 'SDPY-42')            $true
    Note 'leg B: no -12041 anywhere (it is undetermined, not a no)' $false ($b -match '-12041')             $true
    Note 'leg B: no -12040 anywhere'                                $false ($b -match '-12040')             $true

    # THE LOG.  PRE_RELEASE 96: an undetermined answer refuses but must not be
    # silent.  Same helper as OS.EXECUTE's line, so the wording is
    # priv_why_text(PRIV_MALFORMED) exactly.
    $delta = Get-ErrlogDelta $logBefore
    if ($delta.Ok) {
        Write-Output ("  errlog grew by {0} bytes" -f $delta.Text.Length)
        foreach ($l in ($delta.Text -split "`n")) {
            if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
        }
        Note 'leg B: errlog carries "PRIVILEGE CHECK UNDETERMINED Python helper start"' $true `
             ($delta.Text -match 'PRIVILEGE CHECK UNDETERMINED Python helper start: the os\.users record has no second field') $true
    } else {
        Write-Output '  errlog ROTATED under the measurement - the delta cannot be read.'
        Note 'leg B: errlog delta was readable (not rotated)' $true $false $true
    }
    Write-Output ''

    # --------------------------------------------------------- leg C

    Write-Output '=== 5. leg C - record "yes","yes": admitted, SDPY-42 comes home ===='
    [System.IO.File]::WriteAllText($record, "yes`nyes`n", [System.Text.Encoding]::GetEncoding('iso-8859-1'))
    $bytesC = (Get-Item -LiteralPath $record).Length
    Write-Output ("  wrote {0}: yes<LF>yes<LF> ({1} bytes)" -f $record, $bytesC)
    Note 'leg C: the permitting record is in place (8 bytes)' 8 $bytesC $true

    Invoke-Leg 'leg C'
    $c = $script:legText
    if ($null -eq $c) { exit 2 }

    Note 'leg C: PY_INITIALIZE = 0'                                 $true ($c -match 'PYGATE-INIT=0')       $true
    Note 'leg C: the second PY_INITIALIZE = 0 as well'              $true ($c -match 'PYGATE-INIT2=0')      $true
    Note 'leg C: PY_IS_INITIALIZED = 1'                             $true ($c -match 'PYGATE-ISINIT=1')     $true
    Note 'leg C: PY_RUNSTRING = 0'                                  $true ($c -match 'PYGATE-RUN=0')        $true
    # ***THE DECISIVE ROW.***  Only CPython can have produced these bytes.
    Note 'leg C: PY_GETATTR read back SDPY-42 - CPython ran for a non-administrator' $true ($c -match 'PYGATE-ATTR=SDPY-42') $true
    Note 'leg C: PY_FINALIZE = 0'                                   $true ($c -match 'PYGATE-FIN=0')        $true
    Note 'leg C: no -12040 anywhere'                                $false ($c -match '-12040')             $true
    Note 'leg C: no -12041 anywhere'                                $false ($c -match '-12041')             $true
    Note 'leg C: no -12042 anywhere'                                $false ($c -match '-12042')             $true

    # NAME THE CAUSE WHEN IT IS NOT THE GATE.  The header says which two
    # outcomes on this leg are findings about something else.
    if ($c -match 'PYGATE-INIT=-12040') {
        Write-Output ''
        Write-Output '  *** -12040 ON THE PERMITTED LEG: THE HELPER DID NOT START FOR THIS USER.'
        Write-Output '  *** The gate said yes (or it would be -12041/-12042).  This is about'
        Write-Output '  *** sdpy.exe as a non-administrator - the binary, python3.dll on this'
        Write-Output '  *** account''s PATH, or CreateProcess - and is a NEW entry, not a gate'
        Write-Output '  *** failure.  The header predicted this as the one falsifier.'
    }
    if ($c -match 'PYGATE-INIT=-12042') {
        Write-Output ''
        Write-Output '  *** -12042 ON THE PERMITTED LEG: THE RECORD COULD NOT BE READ AS THIS'
        Write-Output '  *** USER (the errlog line names which call).  secure-osusers.ps1 grants'
        Write-Output '  *** sdusers RX and CREATEA joins the account to sdusers - one of those'
        Write-Output '  *** did not hold.  A finding about the ACL, not the gate.'
        $late = Get-ErrlogDelta $logBefore
        if ($late.Ok) {
            foreach ($l in ($late.Text -split "`n")) {
                if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
            }
        }
    }

} finally {
    Write-Output ''
    Write-Output '=== 6. cleanup ======================================================'
    if ($wroteRecord) {
        try {
            if (Test-Path -LiteralPath $record) { Remove-Item -LiteralPath $record -Force }
        } catch {
            Write-Output ('  could not remove the os.users record - ' + $_.Exception.Message)
        }
        if (Test-Path -LiteralPath $record) {
            Write-Output ("  *** THE RECORD {0} IS STILL THERE - remove it before the next run." -f $record)
        } else {
            Write-Output ("  os.users record removed: {0}" -f $record)
        }
    }
    if ($created) {
        try {
            $rmOut = Invoke-SD (Remove-SdTestUserScript -Name $account)
            Write-Output '  --- DELETE.ACCOUNT said: ---'
            Write-Output $rmOut
        } catch {
            Write-Output ('  DELETE.ACCOUNT failed - ' + $_.Exception.Message)
        }
        $still = Get-LocalUser -Name $account -ErrorAction SilentlyContinue
        if ($null -ne $still) {
            Write-Output ("  *** THE ACCOUNT '{0}' IS STILL THERE - remove it before the next run." -f $account)
        } else {
            Write-Output ("  '{0}' is gone." -f $account)
        }
    }
}

# ------------------------------------------------------------------ verdict

Write-Output ''
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

$decisive = @($results | Where-Object { $_.Decisive -eq 'yes' })
$failed   = @($decisive | Where-Object { $_.Result -eq 'FAIL' })
Write-Output ("verify-pygate: {0} decisive check(s), {1} failed." -f $decisive.Count, $failed.Count)

# REFUSE A RUN THAT SCORED THE WRONG NUMBER OF THINGS.  An empty decisive list
# would print "0 failed" and exit 0 - the suite row this project has already
# been given once, on a suite that had never run a step - and a run that never
# reached leg C measured half a gate.  The roster is EXACT, not a floor: 6
# controls, 3 probe rows, then 10 + 9 + 12 across the legs.  A row added or
# removed without this number moving is refused loudly here rather than
# passing by a count nobody re-derived.
$roster = 40
if ($decisive.Count -ne $roster) {
    Write-Output ("verify-pygate: {0} decisive check(s) ran and the roster is {1} - the legs did not all run, or a row moved.  Not a pass." -f $decisive.Count, $roster)
    exit 2
}

if ($fatal) { exit 1 }
exit 0
