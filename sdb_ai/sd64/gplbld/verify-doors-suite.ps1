# verify-doors-suite.ps1 - drives the whole SUSPENDED door pair as ONE step, so
# VerifyInstall1 can carry it.  PRE_RELEASE_FIXES.md 38.
#
#   powershell -File verify-doors-suite.ps1 -Prefix sddrb50
#
# Exit 0 every leg passed, 1 a leg failed, 2 it could not be run.
#
# ***WHY IT LIVES IN VerifyInstall1 AND NOT VerifyInstall2, WHICH IS THE ONLY
# PLACE IT CAN LIVE.***  The five phases need ALTERNATING tokens:
#
#   Create (elevated) -> Control (ORDINARY) -> Suspend (elevated)
#     -> Refused (ORDINARY) -> Remove (elevated)
#
# VerifyInstall2 is the elevated runner, and an elevated parent CANNOT make an
# ordinary child - VerifyInstall1.ps1:70 records the measurement and the reason:
# runas /trustlevel yields a RESTRICTED token, not this user's normal one, and
# the logto door answered by the wrong token is precisely the false pass
# verify-tiers section 6 declines to produce.  VerifyInstall1 is unelevated and
# already raises elevated children (verify-osusers does it on its own account),
# so the ordinary half is the parent and the elevated phases are the children.
# That is the only arrangement of the two that works.
#
# ***IT COSTS THREE UAC PROMPTS, AND SAYS SO BEFORE EACH.***  Owner's rule,
# 22 Aug 2026: "Say so before elevating.  A suite that silently demands consent
# five times is worse than one that asks for a command."
#
# ***THE ELEVATED CHILD REDIRECTS ITS OWN OUTPUT, BECAUSE Start-Process CANNOT
# DO BOTH.***  -Verb RunAs needs UseShellExecute, which is incompatible with
# -RedirectStandardOutput; without a redirect the child's window closes and its
# evidence is gone, leaving an exit code and nothing to read - which is the
# instrument rule's null case.  So a tiny launcher script does the redirect
# inside the child, and this file prints what came back.
#
# ***THE PASSWORD IS NOT IN THE LAUNCHER AND NOT IN THE TRANSCRIPT.***  It goes
# to the child as an ARGUMENT, and verify-doors-admin.ps1 does not print it
# when it was supplied, exactly so this file can capture that output to a file.
# The launcher on disk carries no secret; the child's command line carries it
# for the seconds the child lives, which is the same exposure the hand-run path
# already has when it prints the next command.
#
# ***A PREFIX IS SINGLE-USE, AND THAT IS CHECKED RATHER THAN REMEMBERED.***
# The Control leg signs in over ssh, which creates a Windows profile that
# DELETE.ACCOUNT cannot remove while its registry hive is mounted
# (PRE_RELEASE 35/36).  Windows will not put a new profile where one already
# sits and hands out a SUFFIXED home instead - an unmeasured variable in a test
# whose whole point is that the suspension is the only thing that changes.  So
# this refuses a name with any residue, BEFORE creating anything.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [int] $Port = 4243
)

$ErrorActionPreference = 'Stop'

$admin   = Join-Path $PSScriptRoot 'verify-doors-admin.ps1'
$measure = Join-Path $PSScriptRoot 'verify-doors.ps1'
$acct    = $Prefix + 'a'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$work = Join-Path $env:TEMP ('sd-doors-suite-' + $stamp)
New-Item -ItemType Directory -Path $work | Out-Null

$legs = New-Object System.Collections.ArrayList

# ***NOTHING HERE RETURNS A VALUE, AND THAT IS DELIBERATE.***  A PowerShell
# function's return value is its whole OUTPUT STREAM, so a function that both
# Write-Outputs and returns hands the caller an ARRAY of the printed lines with
# the value on the end.  "if (-not (Add-Leg ...))" would then be testing a
# non-empty array, which is always true - the branch never fires and nothing
# looks wrong, because the lines still appear on screen.  So these set a
# script-scope variable, exactly as Note sets $script:fatal in the other two
# files, and the callers read that.
$script:legPass   = $false
$script:phaseExit = 2

function Add-Leg($name, $expected, $got) {
    $pass = ($expected -eq $got)
    $null = $legs.Add([pscustomobject]@{
        Leg = $name; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    Write-Output ("  [{0}] {1}: expected exit {2}, got {3}" -f
                  $(if ($pass) { 'PASS' } else { 'FAIL' }), $name, $expected, $got)
    $script:legPass = $pass
}

# ---------------------------------------------------------------------------
# THE ELEVATED LEG.  Returns the child's exit code, and prints what it did.
function Invoke-ElevatedPhase([string]$Phase, [string]$Password) {
    $out      = Join-Path $logDir ("verify-doors-admin-{0}-{1}.log" -f $Phase.ToLower(), $stamp)
    $launcher = Join-Path $work ("launch-" + $Phase + ".ps1")

    # THE LAUNCHER CARRIES NO SECRET - the password arrives as its argument.
    $body = @(
        'param([string]$Admin,[string]$Prefix,[string]$Phase,[string]$Password,[string]$Out)',
        '& $Admin -Prefix $Prefix -Phase $Phase -Password $Password *> $Out',
        'exit $LASTEXITCODE'
    )
    Set-Content -LiteralPath $launcher -Value $body -Encoding ascii

    Write-Output ''
    Write-Output ("  --- {0} (ELEVATED) --------------------------------------------" -f $Phase.ToUpper())
    Write-Output '  *** A UAC PROMPT IS COMING.  It is this suite asking, not something else.'
    Write-Output ("      {0} -Prefix {1} -Phase {2}" -f $admin, $Prefix, $Phase)
    Write-Output ("      output -> {0}" -f $out)

    $script:phaseExit = 2
    try {
        $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList @(
                 '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
                 '-Admin',    $admin,
                 '-Prefix',   $Prefix,
                 '-Phase',    $Phase,
                 '-Password', $Password,
                 '-Out',      $out)
        $script:phaseExit = $p.ExitCode
    } catch {
        Write-Output ('  elevation did not happen: ' + $_.Exception.Message)
        Write-Output '  Nothing was measured by this leg.'
        $script:phaseExit = 2
        return
    }

    # ***PRINT WHAT IT DID, ALWAYS.***  A leg whose evidence is only on disk is
    # one nobody reads until it has already been believed.
    if (Test-Path -LiteralPath $out) {
        foreach ($line in (Get-Content -LiteralPath $out)) { Write-Output ('  | ' + $line) }
    } else {
        Write-Output '  | (no output file - the child did not start)'
    }
}

# ---------------------------------------------------------------------------
# THE ORDINARY LEG.  Runs IN THIS PROCESS, which is the whole reason this file
# is the parent: the token must be the one the user really has.
function Invoke-OrdinaryPhase([string]$Phase, [string]$Password) {
    Write-Output ''
    Write-Output ("  --- {0} (UNELEVATED, in this process) -------------------------" -f $Phase.ToUpper())
    & $measure -Prefix $Prefix -Password $Password -Phase $Phase -Port $Port |
        ForEach-Object { Write-Output ('  | ' + $_) }
    $script:phaseExit = $LASTEXITCODE
}

# ------------------------------------------------------------- preconditions

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-doors-suite: this must run UNELEVATED and this session is elevated.'
    Write-Output '  The Control and Refused legs run IN THIS PROCESS and need an ordinary'
    Write-Output '  token; CPROC:3765 puts the suspension test after the elevated bypass, so'
    Write-Output '  an elevated session ENTERS a suspended account - correctly - and measuring'
    Write-Output '  the logto door from here would report the design working as a fault.'
    Write-Output '  It raises its own elevated children for the three admin phases.'
    exit 2
}

foreach ($p in @($admin, $measure)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("verify-doors-suite: {0} is missing." -f $p)
        exit 2
    }
}

Write-Output ("verify-doors-suite: as {0}, UNELEVATED" -f $id.Name)
Write-Output ("  account   {0}" -f $acct)
Write-Output ("  logs      {0}" -f $logDir)
Write-Output '  three elevated phases, two ordinary ones, and THREE UAC prompts'
Write-Output ''

# ***THE NAME MUST BE WHOLLY FREE, AND ALL FOUR ARE CHECKED.***  The profile
# directory is the one that bites: the other three are cleared by
# DELETE.ACCOUNT and it is not.
$taken = @()
if (Get-LocalUser  -Name $acct              -ErrorAction SilentlyContinue) { $taken += 'a Windows user' }
if (Get-LocalGroup -Name ('sdu_' + $acct)   -ErrorAction SilentlyContinue) { $taken += 'an sdu_ group' }
if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $acct.ToUpper()))) {
    $taken += 'an ACCOUNTS record'
}
if (Test-Path -LiteralPath (Join-Path $env:SystemDrive ('Users\' + $acct))) {
    $taken += 'a Windows PROFILE DIRECTORY (PRE_RELEASE 35/36 - only a restart releases it)'
}
if ($taken.Count -gt 0) {
    Write-Output ("verify-doors-suite: {0} is not free - it already has:" -f $acct)
    $taken | ForEach-Object { Write-Output ('    ' + $_) }
    Write-Output ''
    Write-Output '  A PREFIX IS SINGLE-USE.  The Control leg signs in over ssh and leaves a'
    Write-Output '  profile Windows will not overwrite; a rebuilt account gets a SUFFIXED home,'
    Write-Output '  which puts an unmeasured variable into a test whose whole point is that the'
    Write-Output '  suspension is the only thing that changes.  Use a fresh -Run token.'
    Write-Output '  NOTHING WAS CREATED.'
    exit 2
}
Write-Output ("  {0} is free: no Windows user, no sdu_ group, no ACCOUNTS record, no profile" -f $acct)

# ***THE SAME ALPHABET AS verify-doors-admin.ps1 AND verify-createaccount.ps1:403.***
# Nothing cmd.exe treats specially, because it passes through the SSH_ASKPASS
# helper, where a "^" is eaten and ssh is handed a password that is not the
# account's.  verify-doors-admin re-checks it against that mechanism before it
# creates anything, so this is not the only guard.
$alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$bytes = New-Object byte[] 20
([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
$pw = (-join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })) + '-Aa9'

# --------------------------------------------------------------------- run

$created = $false
$stopped = ''

try {
    Invoke-ElevatedPhase 'Create' $pw
    if ($script:phaseExit -eq 0) { $created = $true }
    Add-Leg 'Create (elevated)' 0 $script:phaseExit
    if (-not $script:legPass) {
        $stopped = 'Create did not build the fixture, so nothing could be measured.'
    }

    if ($stopped -eq '') {
        Invoke-OrdinaryPhase 'Control' $pw
        Add-Leg 'Control (ordinary token)' 0 $script:phaseExit
        if (-not $script:legPass) {
            # ***THIS IS A STOP, NOT A CURIOSITY.***  A door that refuses BEFORE
            # the suspension makes its refusal after one worthless, so the
            # Refused leg must not be allowed to score.
            $stopped = 'A door was refused BEFORE the suspension, so its later refusal would prove nothing.'
        }
    }

    if ($stopped -eq '') {
        Invoke-ElevatedPhase 'Suspend' ''
        Add-Leg 'Suspend (elevated)' 0 $script:phaseExit
        if (-not $script:legPass) {
            $stopped = 'The account was not suspended, so the Refused leg would be measuring the unsuspended account.'
        }
    }

    if ($stopped -eq '') {
        Invoke-OrdinaryPhase 'Refused' $pw
        Add-Leg 'Refused (ordinary token)' 0 $script:phaseExit
    }
}
finally {
    # ***THE FIXTURE COMES DOWN WHATEVER HAPPENED.***  A live account with a
    # known password outliving a failed run is worse than a failed run.  This
    # is in finally so it also covers a step that dies outright, which a
    # try/catch would not.
    if ($created) {
        Invoke-ElevatedPhase 'Remove' ''
        Add-Leg 'Remove (elevated)' 0 $script:phaseExit
    } else {
        Write-Output ''
        Write-Output '  Create left nothing behind, so there is nothing to remove.'
    }
    $pw = ''
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------- report

Write-Output ''
$legs | Format-Table -AutoSize | Out-String | Write-Output

if ($stopped -ne '') {
    Write-Output ('  STOPPED: ' + $stopped)
}
Write-Output ("  The profile directory C:\Users\{0} is expected to remain - PRE_RELEASE 35/36." -f $acct)
Write-Output '  It is not a failure of this run, and the name cannot be used again until a restart.'

$all    = @($legs)
$failed = @($all | Where-Object { $_.Result -ne 'PASS' })

Write-Output ''
if ($all.Count -eq 0) {
    Write-Output 'verify-doors-suite: FAILED - NO LEG RAN, so this run proves nothing.'
    exit 1
}
# ***A RUN THAT STOPPED EARLY IS NOT A PASS EVEN IF EVERY LEG IT REACHED
# PASSED.***  Remove alone can be green while nothing was measured.
if ($stopped -ne '') {
    Write-Output ("verify-doors-suite: FAILED - the sequence stopped after {0} leg(s)." -f $all.Count)
    exit 1
}
if ($failed.Count -gt 0) {
    Write-Output ("verify-doors-suite: FAILED - {0} of {1} legs failed:" -f $failed.Count, $all.Count)
    $failed | ForEach-Object { Write-Output ('    ' + $_.Leg) }
    exit 1
}
if ($all.Count -ne 5) {
    Write-Output ("verify-doors-suite: FAILED - {0} legs ran, not the five the pair is." -f $all.Count)
    exit 1
}
Write-Output ("verify-doors-suite: PASSED - all {0} legs green, both tokens exercised." -f $all.Count)
exit 0
