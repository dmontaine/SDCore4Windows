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
    [switch] $NoHelper
)

$ErrorActionPreference = 'Continue'

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$results = New-Object System.Collections.ArrayList
$script:failed = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

function Skip($check, $why) {
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = 'n/a'; Observed = $why })
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
$script:helperPipe = ''

function Start-ElevationHelper {
    if ($NoHelper) { return }
    $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
    if (-not (Test-Path -LiteralPath $elev)) {
        Write-Host '  no sd-elevate.ps1 beside this script - falling back to a prompt per leg'
        return
    }
    # gpl.bp/ELEVATE:121 - 'sd-elev-' : @logname.  Same name, so SD's own
    # elevate('START') inside LOGTO SDSYS finds this one and asks for nothing.
    $pipe = 'sd-elev-' + $env:USERNAME
    Write-Host ('      ' + $elev + ' -Start -PipeName ' + $pipe + ' -OwnerPid ' + $PID)
    Write-Host '  APPROVE THE UAC PROMPT.  It is the consent LOGTO SDSYS asks for, once.' -ForegroundColor Yellow
    & $elev -Start -PipeName $pipe -OwnerPid $PID | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("  the helper did not start (exit {0}) - falling back to a prompt per leg." -f $LASTEXITCODE)
        return
    }
    $script:helperPipe = $pipe
    Write-Host ('  helper is serving on pipe ' + $pipe + '; SD will share it.')
}

function Stop-ElevationHelper {
    if ([string]::IsNullOrEmpty($script:helperPipe)) { return }
    $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
    & $elev -Stop -PipeName $script:helperPipe -OwnerPid $PID | Out-Null
    Write-Host ('  elevation helper stopped (pipe ' + $script:helperPipe + ').')
    $script:helperPipe = ''
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
        if ([string]::IsNullOrEmpty($script:helperPipe)) {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
                    -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                                    '-File', $launcher)
            $null = $p
        } else {
            $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
            & $elev -Run -PipeName $script:helperPipe -OwnerPid $PID -Script $launcher | Out-Null
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
$p = @($results | Where-Object { $_.Expected -ne 'n/a' -and $_.Expected -eq $_.Observed }).Count
$f = @($results | Where-Object { $_.Expected -ne 'n/a' -and $_.Expected -ne $_.Observed }).Count
$s = @($results | Where-Object { $_.Expected -eq 'n/a' }).Count
Write-Host ("verify-sdsyswrite: {0} PASS / {1} FAIL / {2} SKIP" -f $p, $f, $s)
Write-Host ''
Write-Host 'A FAIL on the two unelevated write rows is PRE_RELEASE 68 and 73, not a' -ForegroundColor Yellow
Write-Host 'broken probe - provided the two control rows passed.  Read those first.' -ForegroundColor Yellow

if ($script:failed) { exit 1 }
exit 0
