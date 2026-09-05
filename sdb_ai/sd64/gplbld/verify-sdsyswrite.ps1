# verify-sdsyswrite.ps1 - can SDSYS reached by LOGTO write the protected stores?
#
#   powershell -ExecutionPolicy Bypass -File verify-sdsyswrite.ps1 -Prefix sdswa1
#
# PRE_RELEASE_FIXES 73, and it is the class-fix for 68 and 72 rather than a test
# of either.  RUN IT FROM AN ORDINARY, UNELEVATED PowerShell.
#
# ===========================================================================
# WHAT THIS EXISTS TO CATCH, AND WHY NOTHING ELSE DID
# ===========================================================================
#
# SD reaches SDSYS two ways, and the access model documents both (LOGIN:396-399,
# the owner's own words): "by starting SD in an elevated session or by logging to
# SD after logging into their personal account".  ABOUT TWENTY VERIFIERS ISSUE
# LOGTO SDSYS, so the route is exercised constantly - but ALL BUT ONE GATE ON
# ELEVATION, so the SD PROCESS is elevated and a write to a store locked away
# from sdusers succeeds.  The one without a gate, verify-lcnames.ps1, only READS
# the VOC.
#
# AND THE ONE VERIFIER COVERING modify.password NEVER COMPLETES ONE.
# verify-setpw.ps1 makes four assertions, all about argument parsing, and its
# control supplies "definitely-not-the-password" on purpose - so authentication
# always fails and CRED_SET is never called.  It proves the parser and never
# exercises the write.
#
# SO NO VERIFIER HAD EVER MADE A SUCCESSFUL ADMINISTRATIVE *WRITE* FROM A SESSION
# THAT REACHED SDSYS BY LOGTO FROM AN UNELEVATED START.  That is the whole hole,
# and 68 lived in it: the Windows half of setting a password goes through
# PS_SCRIPT:166 -> elevate('RUN'), which the ELEVATED HELPER runs, while the
# credential half is a plain openpath/write by the SD process itself
# (CRED_SET:68, :114) - and secure-cred.ps1 grants sdusers NOTHING on $cred.
#
# THE FLAG AND THE TOKEN DISAGREE, WHICH IS WHY NOTHING REFUSES EARLIER.
# CPROC:2769 sets K$ADMINISTRATOR on the logto, while USR_ADMIN was seeded from
# the real process token at start (kernel.c:241).  SD is correctly convinced it
# is administrator for everything routed through the helper; only file I/O
# notices that the token never changed.
#
# 30 Aug 26 - THE THIRD STORE IS A POSITIVE CONTROL ON THE SESSION, AND WITHOUT
# IT THE OTHER TWO ROWS ARE AMBIGUOUS.  A session that can write NOTHING scores
# identically to one that cannot write THOSE TWO STORES, and only the second is
# 68.  The three ACLs differ on purpose: secure-cred.ps1 grants sdusers nothing,
# secure-osusers.ps1 read-only, secure-audit.ps1 "(AD,RA,S)" - so the audit trail
# SHOULD take a write from the same session, and step 6 is where that is proved.
# A failure there is a finding about the session rather than about $cred.
#
# ===========================================================================
# WHY IT IS SHAPED LIKE THIS
# ===========================================================================
#
# IT MUST RUN UNELEVATED AND IT MUST ALSO DO ELEVATED WORK, and those cannot be
# the same process.  An elevated parent CANNOT make an ordinary child - CLAUDE.md
# section 4.0.1: "runas /trustlevel yields a RESTRICTED token rather than the
# user's own" - so the measurement has to start unelevated and reach UP.  That is
# the door suite's shape (PRE_RELEASE 48) and it is copied rather than reinvented:
# one consent to sd-elevate.ps1 -Start, then a resident helper serves every
# elevated leg over a named pipe.
#
# THE PIPE NAME IS SD'S OWN AND THAT IS DELIBERATE.  gpl.bp/ELEVATE:121 builds
# 'sd-elev-' : @logname, so starting the helper on that name means SD's own
# elevate('START') inside LOGTO SDSYS finds one already serving and
# short-circuits (sd-elevate.ps1:128).  ONE CONSENT FOR THE WHOLE RUN instead of
# one per leg - and the run is still watched, which is what section "run
# standing procedures exactly as written" asks for.
#
# THE THROWAWAY ACCOUNT IS CREATED FROM THE ELEVATED SIDE ON PURPOSE.  Creating
# it from the unelevated side is the very thing 68 breaks, so setup would fail
# for the reason under test and the run would prove nothing.  Worse, per 72 a
# failed create leaves a Windows account in NO GROUP, which no sweep can find -
# so a verifier that created its account the broken way would litter the machine
# once per run with an unconfined login.
#
# ===========================================================================
# WHAT A RED ROW MEANS
# ===========================================================================
#
# Today, on an install with 68 unfixed, THE UNELEVATED WRITE ROWS ARE EXPECTED TO
# FAIL.  That is the point: this script is written to go red now and green when
# 68 is fixed.  A green run before the fix means the probe is broken, not that
# the product is well.
#
# THE CONTROLS ARE WHAT MAKE THE RED ROWS MEAN ANYTHING, and there are three:
#   1. the unelevated session REACHED SDSYS and can act there (a read succeeds),
#      so a failed write is about the ACL and not about a session that never
#      arrived;
#   2. the same write from an ELEVATED session SUCCEEDS, so the probe can see a
#      success at all - the exact gap that let verify-setpw pass for weeks;
#   3. setup and cleanup are reported, so a run that did nothing cannot score.

param(
    # Throwaway account.  LOWER CASE ONLY - CREATEA downcases the user name and
    # the directory takes it verbatim, so a mixed-case prefix names a directory
    # the sdu_ group derivation cannot match.  Single use: pick a fresh one.
    [Parameter(Mandatory = $true)] [string] $Prefix,

    # Fall back to a UAC prompt per elevated leg instead of a resident helper.
    [switch] $NoHelper,

    # 04 Sep 26 - PRE_RELEASE 165.  A pipe VerifyInstall1 is already serving.
    #
    # ***WITHOUT THIS, THIS STEP KILLED THE RUN'S CONSENT.***  It starts its
    # helper on SD's own pipe name, "sd-elev-<username>" - the same one the
    # runner now uses - so -Start found the runner's helper and returned 0, and
    # then Stop-ElevationHelper sent "-Stop -OwnerPid $PID".  Steps run
    # IN-PROCESS, so that pid IS the runner's; the helper's owner set emptied
    # and it exited, and every elevated thing after this step asked for consent
    # again.  Adopting means using it and NOT stopping it.
    [string] $HelperPipe = ''
)

$ErrorActionPreference = 'Continue'

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$results = New-Object System.Collections.ArrayList
$script:failed = $false

# 30 Aug 26 - EVERY ROW CARRIES ITS OWN VERDICT, AND THAT IS NOT TIDINESS.
# The first version derived the tally by testing Expected -ne 'n/a', which
# compares a BOOLEAN to a STRING: PowerShell converts the string to the left
# operand's type, [bool]'n/a' is $true, so every "expected True" row read as a
# skip.  THE FIRST REAL RUN REPORTED "2 PASS / 0 FAIL / 5 SKIP" ON A RUN WITH
# FIVE PASSES AND TWO GENUINE FAILURES - a false green on the one line a human
# reads, on a script written to catch false greens.  The exit code was right the
# whole time, which is what makes it the dangerous kind of wrong.
function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Verdict = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

function Skip($check, $why) {
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = 'n/a'; Observed = $why; Verdict = 'SKIP'
    })
    Write-Host ("  [SKIP] {0}: {1}" -f $check, $why) -ForegroundColor Yellow
}

function Fail($msg) {
    Write-Host ''
    Write-Host ('verify-sdsyswrite: ' + $msg) -ForegroundColor Red
    exit 2
}

function Step($n, $t) {
    Write-Host ''
    Write-Host ("== [$n] $t") -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# THE GATE.  Refuse elevation outright, exactly as VerifyInstall1 does and for a
# sharper version of its reason: an elevated run has the token that makes every
# write under test succeed, so it would pass every row and prove the opposite of
# what it claims.
if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'verify-sdsyswrite: this is an ELEVATED PowerShell and these checks need an ordinary one.'
    Write-Host ''
    Write-Host '  The whole question is whether a session that reached SDSYS by LOGTO from an'
    Write-Host '  UNELEVATED start can write $cred and os.users.  Elevated, the process token'
    Write-Host '  already grants both, so every row would pass and mean nothing.'
    exit 2
}

if (-not (Test-Path -LiteralPath $sdExe)) { Fail ("no sd.exe at " + $sdExe) }

# assert-current, for the reason every other verifier calls it: a result off a
# tree that source has moved past is not a result.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'assert-current refuses - run gplbld/cycle.ps1 first.' }

if ($Prefix -cne $Prefix.ToLower()) { Fail ("-Prefix must be lower case: " + $Prefix) }

$acct = $Prefix
$pw   = 'Sd73-' + ([guid]::NewGuid().ToString('N').Substring(0, 12)) + '!aQ'

Write-Host ''
Write-Host '=== verify-sdsyswrite: the protected stores from a LOGTO-reached SDSYS ===' -ForegroundColor Cyan
Write-Host ('  sd.exe        : ' + $sdExe)
Write-Host ('  account       : ' + $acct)
Write-Host ('  this process  : pid ' + $PID + ', UNELEVATED (checked above)')
Write-Host ('  helper        : ' + $(if ($NoHelper) { 'DISABLED (-NoHelper): expect one UAC prompt per elevated leg' }
                                     elseif ($HelperPipe -ne '') { 'ADOPTED from the runner: ' + $HelperPipe + ' - no consent here, and this step will not stop it' }
                                     else { 'sd-elevate.ps1, one consent for the run' }))

# ---------------------------------------------------------------------------
# SD, driven the way every other verifier drives it: a piped body ending in OFF.
# NOT "echo CMD | sd" - that shape hung a session on 23 Aug 2026 and cost an
# elevation to clear the stray sd.exe.  The leading and trailing newlines and the
# closing OFF are what make it terminate.
#
# TERM AFTER EVERY LOGTO, because LOGTO resets it - the full write-up is in
# verify-tiers.ps1's Invoke-SD.
function Invoke-SD([string[]]$commands) {
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + (($expanded + @('OFF')) -join "`n") + "`n"
    $out  = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

function Said($what, $text) {
    Write-Host ''
    Write-Host ('  --- ' + $what + ' -----------------------------------------') -ForegroundColor DarkGray
    ($text -split "`n") | ForEach-Object { Write-Host ('  | ' + $_) -ForegroundColor DarkGray }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# The elevation helper, on SD'S OWN PIPE NAME so SD shares it.
# 04 Sep 26 - PRE_RELEASE 165.  THE MACHINERY MOVED TO elevate-once.ps1 AND IS
# NO LONGER A SECOND COPY.  What was here started a helper on SD's own pipe and
# stopped it with -Stop -OwnerPid $PID; verify-doors-suite.ps1 had its own
# version that used a RANDOM pipe and a BARE -Stop.  Two copies of
# security-sensitive lifetime logic that had already drifted apart in both of
# the places that decide whether it works - see the module's header.
#
# A script-scope pipe variable IS KEPT, because Invoke-SDElevated and
# Invoke-PSElevated below branch on it and their call sites are unchanged.  It is
# now a mirror of the module's state rather than the state itself.
#
# ***IT IS $script:elevPipe AND NOT $script:helperPipe, AND THE NAME IS
# LOAD-BEARING. MEASURED ON b119.***  PowerShell variable names are
# CASE-INSENSITIVE, so the parameter -HelperPipe and a variable spelt
# $script:helperPipe are THE SAME VARIABLE: this file bound the runner's pipe and
# then assigned '' to "its own" variable, wiping it.  It then started a second
# helper on SD's own pipe name - after verify-doors-suite had already killed the
# runner's the same way - and b119 asked for three consents instead of one, while
# passing every check.  See verify-doors-suite.ps1's copy of this note for the
# full account; test-elevonce-units.ps1 now refuses both spellings in one file.
. (Join-Path $PSScriptRoot 'elevate-once.ps1')
$script:elevPipe = ''

function Start-ElevationHelper {
    $st = Start-SdElevationHelper -Adopt $HelperPipe -Purpose 'this step' -NoHelper:$NoHelper
    $script:elevPipe = $st.Pipe
}

function Stop-ElevationHelper {
    # ***A NO-OP ON AN ADOPTED PIPE, AND THAT IS THE WHOLE FIX.***  The module
    # decides, not this file: it stops only what this process started.
    Stop-SdElevationHelper
    $script:elevPipe = (Get-SdElevationState).Pipe
}

# Run an SD script ELEVATED.  Start-Process -Verb RunAs when there is no helper;
# through the helper otherwise.  The output comes back through a file because a
# window that closes is the same as no report at all.
function Invoke-SDElevated([string[]]$commands, [string]$why) {
    $work = Join-Path $env:TEMP ('sdsw-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $work
    try {
        $sdIn  = Join-Path $work 'in.txt'
        $sdOut = Join-Path $work 'out.txt'
        $expanded = New-Object System.Collections.ArrayList
        foreach ($c in $commands) {
            $null = $expanded.Add($c)
            if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
        }
        # The body is written as a file and PIPED by the launcher - sd.exe must
        # have a PIPE on stdin, not a redirected file handle, or it prints
        # "Process terminated" and runs nothing.
        #
        # LF ONLY, AND WRITTEN WITHOUT Set-Content.  MEASURED 30 Aug 2026: joined
        # with CRLF, SD TAKES THE \r AS A LINE OF ITS OWN, so every command is
        # followed by an empty one.  The transcript shows it plainly - a ":"
        # prompt with nothing on it after each line - and the damage is not
        # cosmetic: the blanks push the ANSWERS one out of step, so
        # "New Windows password:" was fed the empty line, "Repeat password:" got
        # the first password, the second fell through to the command prompt as
        # "<password> is not in your VOC", and CREATE.ACCOUNT refused with "The
        # two passwords did not match, or none was entered".
        #
        # Set-Content is avoided for the same reason twice over: it appends a
        # terminator of its own, and on Windows that terminator is CRLF - so
        # joining with "`n" and then writing with Set-Content still ends the
        # body with a stray \r.  WriteAllText puts down exactly these bytes.
        $body = (($expanded + @('OFF')) -join "`n") + "`n"
        # THE GUARD IS THE FIX, NOT THE JOIN ABOVE.  A stray \r anywhere in this
        # body silently feeds SD an extra blank line per command and pushes every
        # ANSWER one out of step - which presents as "the two passwords did not
        # match" and looks like a password problem.  Assert it mechanically.
        if ($body.Contains([char]13)) {
            Fail 'the SD body contains a CR - it would feed a blank line per command (see the comment above)'
        }
        [System.IO.File]::WriteAllText($sdIn, $body, [System.Text.Encoding]::ASCII)

        # The LAUNCHER is PowerShell source, so its own line endings are free -
        # but it reads the body -Raw and pipes it, so whatever bytes went into
        # $sdIn are what sd.exe sees.  & on the quoted exe path, because a quoted
        # path at the start of a line is a string expression and runs nothing.
        $launcher = Join-Path $work 'run.ps1'
        $ls = @(
            ('$b = Get-Content -LiteralPath ' + "'" + $sdIn + "'" + ' -Raw'),
            ('$o = $b | & ' + "'" + $sdExe + "'"),
            ('$o | Out-File -LiteralPath ' + "'" + $sdOut + "'" + ' -Encoding utf8')
        ) -join "`r`n"
        [System.IO.File]::WriteAllText($launcher, $ls + "`r`n", [System.Text.Encoding]::ASCII)

        Write-Host ('      elevated: ' + $why)
        if ([string]::IsNullOrEmpty($script:elevPipe)) {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
                    -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                                    '-File', $launcher)
            $null = $p
        } else {
            $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
            & $elev -Run -PipeName $script:elevPipe -OwnerPid $PID -Script $launcher | Out-Null
        }

        if (Test-Path -LiteralPath $sdOut) {
            return ((Get-Content -LiteralPath $sdOut) -join "`n")
        }
        return ''
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# THE AUDIT TRAIL HAS TO BE READ FROM THE ELEVATED SIDE, AND THAT IS THE ACL
# TALKING RATHER THAN CAUTION.  secure-audit.ps1 grants sdusers "(AD,RA,S)" -
# AppendData, ReadAttributes, Synchronize - and deliberately NOT ReadData, so
# that an ordinary SD user cannot read back the refusal reasons and enumerate
# accounts with them (PROJECT_STATUS.md, the SCRAM audit entry).
#
# SO THE SESSION UNDER TEST CAN APPEND AND CANNOT VERIFY, and the leg is three
# steps rather than one: measure ELEVATED, append UNELEVATED, measure ELEVATED
# again.  A one-step version would have to read from the unelevated side, which
# the ACL forbids - it would fail on a working product.
function Invoke-PSElevated([string]$body, [string]$why) {
    $work = Join-Path $env:TEMP ('sdsw-ps-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $work
    try {
        $res      = Join-Path $work 'result.txt'
        $launcher = Join-Path $work 'probe.ps1'
        # $OUT is substituted, not passed: the elevated child gets no arguments
        # through the helper pipe, which takes a script path and nothing else.
        $src = $body.Replace('$OUT', ("'" + $res + "'"))
        [System.IO.File]::WriteAllText($launcher, $src + "`r`n", [System.Text.Encoding]::ASCII)

        Write-Host ('      elevated: ' + $why)
        if ([string]::IsNullOrEmpty($script:elevPipe)) {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
                    -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                                    '-File', $launcher)
            $null = $p
        } else {
            $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
            & $elev -Run -PipeName $script:elevPipe -OwnerPid $PID -Script $launcher | Out-Null
        }
        if (Test-Path -LiteralPath $res) { return ((Get-Content -LiteralPath $res) -join "`n") }
        return ''
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Reads the audit file's length and whether $token appears in it, ELEVATED.
# .Contains() rather than Select-String -SimpleMatch or a -match: an
# interpolated pattern silently changes what is searched for and reports a
# PRESENT string as absent, which here would read as "the append never landed".
function Get-AuditState([string]$path, [string]$token, [string]$why) {
    $out = Invoke-PSElevated @"
`$p = '$path'
`$t = '$token'
`$exists = Test-Path -LiteralPath `$p
`$len = -1
`$hit = `$false
if (`$exists) {
    `$len = (Get-Item -LiteralPath `$p).Length
    `$txt = [System.IO.File]::ReadAllText(`$p)
    `$hit = `$txt.Contains(`$t)
}
@(('exists=' + `$exists), ('len=' + `$len), ('token=' + `$hit)) |
    Out-File -LiteralPath `$OUT -Encoding ascii
"@ $why
    $st = [pscustomobject]@{ Exists = $false; Length = -1; Token = $false; Raw = $out }
    foreach ($line in ($out -split "`n")) {
        $l = $line.Trim()
        if ($l -like 'exists=*') { $st.Exists = ($l.Substring(7) -eq 'True') }
        if ($l -like 'len=*')    { $st.Length = [int64]$l.Substring(4) }
        if ($l -like 'token=*')  { $st.Token  = ($l.Substring(6) -eq 'True') }
    }
    return $st
}

# ---------------------------------------------------------------------------
# ANCHORS.  Match the wording the tool prints on the POSITIVE path, never the
# argument passed in - the account name appears in the echoed command, in the
# refusal and in the error framing, so matching on it reports success three ways
# on the failure path.  That trap is written up in CLAUDE.md.
#
# THE VERB IS MODIFY.PASSWORD AND THERE IS NO set.password.  Only
# voc_template carries it, so it is SDSYS-only - which is what makes it the right
# probe here.  gpl.bp/SET_ACC_PASSWORD:252 prints the success line.
$pwOkRx = 'Password set for account'
#
# AND THE DISQUALIFIERS, because a run can fail THREE ways and two of them are
# not the write.  SET_ACC_PASSWORD:143-149 opens $cred to READ before it writes -
# and secure-cred.ps1 grants sdusers nothing, so an unelevated session cannot
# even open it and stops at :149 with a message that never mentions writing.
# CREATEA's 10122 ("could not be written") is a DIFFERENT path, the one the owner
# met on 30 Aug; both are 68 and they present differently, so both are matched.
$pwFailRx = 'Unable to set password for|Cannot open the \$CRED register|Password not changed'
#
# A row where the success anchor matches AND a disqualifier matches is not a
# pass either - that is the shape that reported "confirmed" on a refused step on
# 23 Aug 2026.
function Test-PasswordSet($text) {
    if ($text -match $pwFailRx) { return $false }
    return ($text -match $pwOkRx)
}

try {
    Step 0 'the elevation helper'
    Start-ElevationHelper

    # -----------------------------------------------------------------------
    Step 1 'SETUP, elevated: create the throwaway account'
    # Elevated on purpose - see the header.  Creating it unelevated is the thing
    # under test, and per 72 a failed create leaves an unconfined Windows account
    # that no sweep can find.
    $mk = Invoke-SDElevated @('LOGTO SDSYS',
                              ('CREATE.ACCOUNT USER ' + $acct + ' NONE'),
                              $pw, $pw) ('create.account user ' + $acct + ' none')
    Said 'setup output' $mk

    $rec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $acct.ToUpper())
    $made = Test-Path -LiteralPath $rec
    Note 'SETUP: the account exists afterwards' $true $made
    if (-not $made) {
        Fail ('setup did not create ' + $acct + ' - nothing below would mean anything. Read the output above.')
    }

    # -----------------------------------------------------------------------
    Step 2 'CONTROL: the unelevated session reaches SDSYS and can act there'
    # Without this a failed write below is indistinguishable from a session that
    # never arrived - the vacuous-pass shape the instrument section is about.
    $reach = Invoke-SD @('LOGTO SDSYS', 'COUNT ACCOUNTS')
    Said 'unelevated LOGTO SDSYS + COUNT ACCOUNTS' $reach
    $reached = ($reach -match 'record\(s\) counted')
    Note 'control: unelevated session reached SDSYS and read it' $true $reached
    if (-not $reached) {
        Fail 'the unelevated session did not reach SDSYS, so the write rows below measure nothing.'
    }

    # -----------------------------------------------------------------------
    Step 3 'THE MEASUREMENT: $cred, written from the unelevated SDSYS'
    # TWO INPUTS, NOT THREE.  SET_ACC_PASSWORD:159 asks for the CURRENT password
    # only when "own and has.cred", and an administrator resetting someone
    # else's is not own - :156 says so in as many words.
    $sp = Invoke-SD @('LOGTO SDSYS', ('MODIFY.PASSWORD ' + $acct), $pw, $pw)
    Said 'unelevated MODIFY.PASSWORD' $sp
    $credOkUnelevated = Test-PasswordSet $sp
    # EXPECTED TRUE, AND RED TODAY - that is what this file is for.  68 makes it
    # fail, either at the $cred OPEN (:149) or at the write.
    Note 'unelevated SDSYS can write $cred' $true $credOkUnelevated

    # -----------------------------------------------------------------------
    Step 4 'THE SECOND STORE: os.users, from the unelevated SDSYS'
    # secure-osusers.ps1 grants sdusers (OI)(CI)(RX) - read only - and MODIFYA
    # writes the file with plain BASIC I/O, so this should fail the same way.
    # REASONED, NOT PREVIOUSLY MEASURED: this row is the measurement.
    $os = Invoke-SD @('LOGTO SDSYS', ('MODIFY.ACCOUNT ' + $acct + ' OS-ON'))
    Said 'unelevated MODIFY.ACCOUNT OS-ON' $os
    $osRec = Join-Path $env:ProgramData ('SD\sdsys\os.users\' + $acct)
    $osWritten = Test-Path -LiteralPath $osRec
    Note 'unelevated SDSYS can write os.users' $true $osWritten

    # -----------------------------------------------------------------------
    Step 5 'CONTROL: the same $cred write from an ELEVATED session SUCCEEDS'
    # THIS IS THE ROW verify-setpw NEVER HAD.  A refusal above is only evidence
    # if this probe could have seen a success; without this row a broken probe
    # scores the same as a broken product.
    $spe = Invoke-SDElevated @('LOGTO SDSYS', ('MODIFY.PASSWORD ' + $acct), $pw, $pw) `
                             ('modify.password ' + $acct + ' (positive control)')
    Said 'elevated MODIFY.PASSWORD' $spe
    $credOkElevated = Test-PasswordSet $spe
    Note 'control: elevated SDSYS CAN write $cred' $true $credOkElevated

    if ((-not $credOkUnelevated) -and $credOkElevated) {
        Write-Host ''
        Write-Host 'FINDING: PRE_RELEASE 68 is live on this install.' -ForegroundColor Red
        Write-Host 'The same command in the same account succeeds elevated and is refused' -ForegroundColor Red
        Write-Host 'from a session that reached SDSYS by LOGTO.  The Windows half goes' -ForegroundColor Red
        Write-Host 'through the elevated helper (PS_SCRIPT:166); the credential half is a' -ForegroundColor Red
        Write-Host 'plain write by the SD process, whose token never changed.' -ForegroundColor Red
    }

    # -----------------------------------------------------------------------
    Step 6 'THE POSITIVE CONTROL ON THE SESSION: the audit trail, appended unelevated'
    # WITHOUT THIS ROW THE TWO FAILURES ABOVE ARE AMBIGUOUS.  A session that
    # cannot write ANYTHING scores exactly the same as one that cannot write
    # THOSE TWO STORES, and only the second is 68.  secure-audit.ps1 grants
    # sdusers AppendData while secure-cred.ps1 grants nothing and
    # secure-osusers.ps1 grants read-only, so this write SHOULD succeed from the
    # same session - and if it does not, the finding is about the session rather
    # than about $cred.
    #
    # THE TRIGGER IS A REFUSED LOGTO, AND IT IS CHOSEN FOR THREE REASONS.
    # CPROC:2738 calls kernel(K$AUDIT, 'LOGTO REFUSED account=<NAME> reason=not
    # in the register') - so it needs no program compiled into the account, it
    # is a refusal and therefore changes nothing else, and the record carries a
    # name THIS RUN chose.  That last one is what makes the leg decisive: size
    # alone cannot tell our append from a concurrent one.
    #
    # K$AUDIT IS UNGATED (op_kernel.c:652, "Returns 0 always - there is no
    # failure a caller could sensibly act on"), so nothing here depends on the
    # administrator flag the LOGTO set.
    $auditPath  = Join-Path $env:ProgramData 'SD\sdsys\audit'
    $auditToken = 'ZZAUD' + ([guid]::NewGuid().ToString('N').Substring(0, 12)).ToUpper()
    Write-Host ('      audit file : ' + $auditPath)
    Write-Host ('      probe name : ' + $auditToken + '   (upper case - CPROC upcases it)')

    $before = Get-AuditState $auditPath $auditToken 'read the audit trail BEFORE'
    Write-Host ('      before     : exists=' + $before.Exists + ' len=' + $before.Length +
                ' token=' + $before.Token)

    Note 'control: the audit trail exists' $true $before.Exists
    if (-not $before.Exists) {
        Write-Host ''
        Write-Host '  The audit trail is not there, so the rows below would compare nothing' -ForegroundColor Yellow
        Write-Host '  against nothing.  That is a finding about the install, not about 68.' -ForegroundColor Yellow
    }

    # THE NEGATIVE CONTROL.  A token already present would score the decisive row
    # PASS before anything was written.  It is a fresh GUID per run so it cannot
    # pre-exist - and asserting that is the difference between knowing and
    # assuming, which is the whole subject of this file.
    Note 'control: the probe name is ABSENT from the trail beforehand' $false $before.Token

    # AND THE ACL ITSELF, ECHOED RATHER THAN DESCRIBED - the shape of this leg
    # only makes sense if sdusers really does hold AD without RD.
    $acl = & icacls.exe $auditPath 2>&1
    Said 'icacls on the audit trail' (($acl | Out-String).Trim())

    $canRead = $true
    try { $null = [System.IO.File]::ReadAllText($auditPath) } catch { $canRead = $false }
    Note 'control: this unelevated process CANNOT read the trail (AD without RD)' $false $canRead

    $ap = Invoke-SD @('LOGTO SDSYS', ('LOGTO ' + $auditToken))
    Said 'unelevated LOGTO SDSYS then LOGTO <unregistered>' $ap

    $after = Get-AuditState $auditPath $auditToken 'read the audit trail AFTER'
    Write-Host ('      after      : exists=' + $after.Exists + ' len=' + $after.Length +
                ' token=' + $after.Token)

    $grew = ($after.Length -gt $before.Length)
    Note 'the unelevated SDSYS session appended to the audit trail (it grew)' $true $grew
    Note 'the append is THIS run''s, by name (the DECISIVE one)' $true $after.Token

    if ($grew -and (-not $after.Token)) {
        Write-Host ''
        Write-Host '  The trail grew but does not carry this run''s name, so something else' -ForegroundColor Yellow
        Write-Host '  wrote it.  Size alone is not evidence here - read the decisive row.' -ForegroundColor Yellow
    }
    if (-not $grew) {
        Write-Host ''
        Write-Host '  NOTHING WAS APPENDED, so this row measured the PROBE and not the' -ForegroundColor Yellow
        Write-Host '  product.  Check the SD output above actually reached SDSYS and that' -ForegroundColor Yellow
        Write-Host '  the LOGTO was refused with 10003 - a name that IS in the register' -ForegroundColor Yellow
        Write-Host '  takes a different branch and audits nothing.' -ForegroundColor Yellow
    }
    if ($after.Token -and (-not $credOkUnelevated)) {
        Write-Host ''
        Write-Host 'AND THAT IS THE POINT OF THIS STEP: the same unelevated session that' -ForegroundColor Cyan
        Write-Host 'could not write $cred DID write the audit trail.  The session is not' -ForegroundColor Cyan
        Write-Host 'inert - the two failures above are about those two stores.' -ForegroundColor Cyan
    }
}
finally {
    Step 9 'CLEANUP'
    if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $acct.ToUpper()))) {
        $rm = Invoke-SDElevated @('LOGTO SDSYS', ('DELETE.ACCOUNT ' + $acct), 'Y') `
                                ('delete.account ' + $acct)
        Said 'cleanup output' $rm
    }
    $left = Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $acct.ToUpper()))
    Note 'CLEANUP: the throwaway account is gone' $false $left
    $winLeft = $null -ne (Get-LocalUser -Name $acct -ErrorAction SilentlyContinue)
    Note 'CLEANUP: no Windows account left behind' $false $winLeft
    Stop-ElevationHelper
}

Write-Host ''
Write-Host '=== summary ===' -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-String | Write-Host
# COUNTED FROM THE VERDICT EACH ROW RECORDED, never re-derived by comparing
# Expected to Observed here - see the note on Note() above.
$p = @($results | Where-Object { $_.Verdict -eq 'PASS' }).Count
$f = @($results | Where-Object { $_.Verdict -eq 'FAIL' }).Count
$s = @($results | Where-Object { $_.Verdict -eq 'SKIP' }).Count
# AND THE TALLY MUST ACCOUNT FOR EVERY ROW.  If it does not, the counting is
# wrong and the line above is not to be believed - which is exactly what
# happened on the first run.
if (($p + $f + $s) -ne $results.Count) {
    Write-Host ("verify-sdsyswrite: TALLY IS BROKEN - {0}+{1}+{2} != {3} rows. Do not trust the summary." -f
                $p, $f, $s, $results.Count) -ForegroundColor Red
    exit 2
}
Write-Host ("verify-sdsyswrite: {0} PASS / {1} FAIL / {2} SKIP" -f $p, $f, $s)
Write-Host ''
Write-Host 'A FAIL on the two unelevated write rows is PRE_RELEASE 68 and 73, not a' -ForegroundColor Yellow
Write-Host 'broken probe - provided the control rows passed.  Read those first.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'READ STEP 6 BEFORE BELIEVING EITHER VERDICT.  It is the positive control on' -ForegroundColor Yellow
Write-Host 'the SESSION: the audit trail is the one protected store sdusers may append' -ForegroundColor Yellow
Write-Host 'to, so a session that reached SDSYS should write it.  If step 6 is GREEN the' -ForegroundColor Yellow
Write-Host 'session works and any failure above is about $cred and os.users.  If step 6' -ForegroundColor Yellow
Write-Host 'is RED the session itself is the problem and the rows above say nothing.' -ForegroundColor Yellow

if ($script:failed) { exit 1 }
exit 0
