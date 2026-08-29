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
    [int] $Port = 4243,

    # ***THREE UAC PROMPTS BECOME ONE - OWNER'S RULING, 28 Aug 2026.***  The
    # default routes the three elevated legs through ONE resident elevated
    # helper (sd-elevate.ps1, which SD's own ELEVATE verb uses), so consent is
    # given once at the start instead of once per leg.
    #
    # ***-NoHelper KEEPS THE PROVEN PATH, AND THAT IS THE POINT OF THE SWITCH.***
    # The Start-Process -Verb RunAs route is what -Run b53 went green on. A
    # rework of how a suite elevates should not be the only way to run it the
    # week it lands, so the old mechanism stays reachable and stays tested -
    # test-doorsargv-units.ps1 drives BOTH.
    [switch] $NoHelper
)

$ErrorActionPreference = 'Stop'

$admin   = Join-Path $PSScriptRoot 'verify-doors-admin.ps1'
$measure = Join-Path $PSScriptRoot 'verify-doors.ps1'
$acct    = $Prefix + 'a'
# The helper account - PRE_RELEASE 44.  Its ssh session is the only one whose
# token can carry sdu_<acct>, so it is the only session that can reach the
# logto door.  verify-doors-admin.ps1 creates and removes it.
$helper  = $Prefix + 'b'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# ***CREATED LATER, AND NAMED SO TWO RUNS CANNOT COLLIDE.***  Both halves were
# defects, found 28 Aug 2026 by running the suite twice inside one second:
#
#   1. $stamp is yyyyMMdd-HHmmss, so a second run in the SAME SECOND hit
#      "An item with the specified name ... already exists" and died with an
#      unhandled exception - exit 1 from a script whose refusal code is 2.
#   2. It was created HERE, above the residue check, and the refusal path exits
#      before the try/finally that removes it.  FOUR leaked directories were on
#      disk when this was found, one per refused run.
#
# ***THE SECOND ONE MATTERS MORE THAN IT LOOKS NOW.***  With the helper route
# this directory holds the Create launcher, and that launcher carries the
# password.  On the refusal path it was empty, so nothing leaked - but a
# directory that outlives the run is the wrong place to keep that property by
# luck.  So: unique name, and created only when there is something to put in
# it.
$work = Join-Path $env:TEMP ('sd-doors-suite-' + $stamp + '-' +
                             [guid]::NewGuid().ToString('N').Substring(0, 6))

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
# THE HELPER ROUTE.  One consent for the whole run.
#
# ***IT REUSES sd-elevate.ps1 RATHER THAN GROWING A SECOND ELEVATION HELPER.***
# That file ships and SD's ELEVATE verb drives it, so it is the most exercised
# elevation path in the project; a gplbld-local twin would be a second copy of
# security-sensitive code with nothing comparing them, which is the defect
# class PRE_RELEASE 46 was.  Nothing here modifies it - it is called exactly as
# SD calls it, and editing it would make the tree stale and cost a cycle.
#
# ***THE 300-SECOND PER-REQUEST TIMEOUT IS WHY ONLY THE DOOR LEGS GO THIS WAY.***
# sd-elevate.ps1 hard-codes it, each door leg finishes well inside it, and
# VerifyInstall1's own elevation of VerifyInstall2 does NOT - that half runs 19
# verifiers. So the suite run goes from FOUR prompts to TWO, not to one, and
# taking it to one means changing a shipped file.  Owner's call, not assumed.
$script:helperPipe = ''

function Start-ElevationHelper {
    $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
    if (-not (Test-Path -LiteralPath $elev)) {
        Write-Output ('  no sd-elevate.ps1 beside this script - falling back to a prompt per leg')
        return $false
    }
    $pipe = 'sddoors-' + [guid]::NewGuid().ToString('N')
    Write-Output ''
    Write-Output '  *** ONE UAC PROMPT IS COMING, AND IT IS THE ONLY ONE THIS STEP ASKS FOR.'
    Write-Output ('      {0} -Start -PipeName {1} -OwnerPid {2}' -f $elev, $pipe, $PID)
    & $elev -Start -PipeName $pipe -OwnerPid $PID | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        Write-Output ("  the helper did not start (exit {0}) - falling back to a prompt per leg." -f $rc)
        Write-Output '  5 means consent was refused or unavailable; anything else is a failure to launch.'
        return $false
    }
    $script:helperPipe = $pipe
    Write-Output ('  helper is serving on pipe {0}; the three elevated legs need no further consent.' -f $pipe)
    return $true
}

function Stop-ElevationHelper {
    if ([string]::IsNullOrEmpty($script:helperPipe)) { return }
    $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
    & $elev -Stop -PipeName $script:helperPipe | Out-Null
    Write-Output ('  elevation helper stopped (pipe {0}).' -f $script:helperPipe)
    $script:helperPipe = ''
}

# ***THE LAUNCHER IS SELF-CONTAINED HERE, BECAUSE THE HELPER PASSES NO
# ARGUMENTS*** - it runs a script path with Get-Content | Invoke-Expression.
# So the password is baked in rather than passed, and the old comment that said
# "the launcher carries no secret" had it backwards:
#
#   MEASURED 28 Aug 2026.  A command line IS readable by any same-user process
#   - Win32_Process.CommandLine returned the marker argument verbatim - while a
#   file in %TEMP% carries SYSTEM, Administrators and the user and nobody else.
#   The same three principals either way, except the file can be DELETED, and
#   $work is removed in the finally below whatever happens.  So this is not a
#   step down from passing it as an argument; it is a step up.
# ***THIS FUNCTION MUST NOT PRINT, AND THE FIRST VERSION DID.***  The block at
# the top of this file says why: a PowerShell function's return value is its
# whole OUTPUT STREAM, so one that Write-Outputs AND returns hands the caller an
# ARRAY with the value on the end.  The refusal path did exactly that and the
# unit test caught it by failing to bind an array to a [bool] parameter - the
# warning was thirty lines above the code that ignored it.  The reason goes in
# a script-scope variable and the CALLER prints it.
$script:launcherError = ''
function New-SelfContainedLauncher([string]$Phase, [string]$Password, [string]$Out) {
    $script:launcherError = ''
    $launcher = Join-Path $work ("helper-" + $Phase + ".ps1")
    # ***REFUSE THE QUOTING HAZARD OUT LOUD RATHER THAN GENERATING A BROKEN
    # SCRIPT.***  Every value below is embedded in a single-quoted PowerShell
    # string, which processes no escapes - so a backslash in a path is safe and
    # an apostrophe is not.  The generated alphabet has none, and this asserts
    # that rather than trusting it.
    foreach ($v in @($admin, $Prefix, $Phase, $Password, $Out)) {
        if ($v -match "'") {
            $script:launcherError = 'a value contains an apostrophe and would break the launcher quoting'
            return ''
        }
    }
    $call = "& '$admin' -Prefix '$Prefix' -Phase '$Phase'"
    if ($Password -ne '') { $call += " -Password '$Password'" }
    $call += " *> '$Out'"
    Set-Content -LiteralPath $launcher -Encoding ascii -Value @($call, 'exit $LASTEXITCODE')
    return $launcher
}

function Invoke-PhaseViaHelper([string]$Phase, [string]$Password, [string]$Out) {
    $launcher = New-SelfContainedLauncher $Phase $Password $Out
    if ([string]::IsNullOrEmpty($launcher)) {
        Write-Output ('  REFUSING - ' + $script:launcherError + '.')
        Write-Output '  Nothing was measured by this leg.'
        $script:phaseExit = 2
        return
    }

    # RULE 1: say what is really being sent.  The launcher's CONTENTS are not
    # printed - the Create one carries the password - but its path and the
    # command shape are, with the secret masked.
    $shown = "& '$admin' -Prefix '$Prefix' -Phase '$Phase'"
    if ($Password -ne '') { $shown += " -Password '<password>'" }
    Write-Output ('      via helper: ' + $shown)
    Write-Output ('      launcher  : ' + $launcher)

    $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
    & $elev -Run -PipeName $script:helperPipe -Script $launcher | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -eq 9) {
        Write-Output '  the helper is gone - it answers 9 when no elevated server is on the pipe.'
        Write-Output '  Nothing was measured by this leg.'
        $script:phaseExit = 2
        return
    }
    $script:phaseExit = $rc
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
    if ([string]::IsNullOrEmpty($script:helperPipe)) {
        Write-Output '  *** A UAC PROMPT IS COMING.  It is this suite asking, not something else.'
    }
    Write-Output ("      {0} -Prefix {1} -Phase {2}" -f $admin, $Prefix, $Phase)
    Write-Output ("      output -> {0}" -f $out)

    # ***THE HELPER ROUTE WHEN ONE IS SERVING, THE PROVEN ROUTE OTHERWISE.***
    # Which one ran is printed above by each, so a transcript never leaves it
    # ambiguous which mechanism produced the exit code.
    # ***IsNullOrEmpty, NOT -ne ''.***  An UNSET variable is $null, and
    # "$null -ne ''" is TRUE - so a plain comparison sends an uninitialised
    # run down the helper branch.  Caught by the unit test, which lifts this
    # function without the initialiser above it; the same shape as the
    # "an empty Get-Content is null, not ''" trap already in the record.
    if (-not [string]::IsNullOrEmpty($script:helperPipe)) {
        Invoke-PhaseViaHelper $Phase $Password $out
        if (Test-Path -LiteralPath $out) {
            foreach ($line in (Get-Content -LiteralPath $out)) { Write-Output ('  | ' + $line) }
        } else {
            Write-Output '  | (no output file - the child did not start)'
        }
        return
    }

    # ***ONE EMPTY ELEMENT REJECTS THE WHOLE LIST.***  Start-Process's
    # -ArgumentList carries [ValidateNotNullOrEmpty()], and on a COLLECTION
    # that validates every ELEMENT, not just the collection: a single '' fails
    # with "The argument is null or empty" and NOTHING ELEVATES.  Suspend and
    # Remove take no password - verify-doors-admin.ps1:58 defaults it - so the
    # pair is OMITTED rather than passed empty.  This is the idiom
    # sd-elevate.ps1:118 already uses for its optional -LogFile.
    #
    # Measured 28 Aug 2026 on the -Run b50 suite run: Create carried a
    # password and elevated; Suspend and Remove carried '' and died here, so
    # the account was left unsuspended and the Refused leg could not run.
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
                '-Admin',  $admin,
                '-Prefix', $Prefix,
                '-Phase',  $Phase,
                '-Out',    $out)
    if ($Password -ne '') { $psArgs += @('-Password', $Password) }

    # RULE 1: print the arguments really being passed, and REFUSE THE NULL
    # CASE OUT LOUD rather than leaving it to a parameter-binding message that
    # names no element.  The count is printed because an array built with '+'
    # is exactly where an element goes missing or gets folded in two.
    $shown = $psArgs.Clone()
    if ($Password -ne '') { $shown[$shown.Count - 1] = '<password>' }
    Write-Output ("      argv ({0}): {1}" -f $psArgs.Count, ($shown -join ' '))

    $empties = @(0..($psArgs.Count - 1) | Where-Object { [string]::IsNullOrEmpty($psArgs[$_]) })
    if ($empties.Count -gt 0) {
        Write-Output ('  REFUSING - argv element(s) ' + ($empties -join ', ') +
                      ' are empty; Start-Process would reject the entire list.')
        Write-Output '  Nothing was measured by this leg.'
        $script:phaseExit = 2
        return
    }

    $script:phaseExit = 2
    try {
        $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
                 -ArgumentList $psArgs
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
Write-Output ("  account   {0}   (suspended and measured)" -f $acct)
Write-Output ("  helper    {0}   (ssh's in and issues the LOGTO - PRE_RELEASE 44)" -f $helper)
Write-Output ("  logs      {0}" -f $logDir)
Write-Output '  three elevated phases, two ordinary ones, and THREE UAC prompts'
Write-Output '  TWO accounts are created and TWO profile directories are left behind'
Write-Output ''

# ***BOTH NAMES MUST BE WHOLLY FREE, AND ALL FOUR THINGS ARE CHECKED FOR
# EACH.***  The profile directory is the one that bites: the other three are
# cleared by DELETE.ACCOUNT and it is not.  28 Aug 2026 - the helper name is
# checked here as well, because a run that found `a` free and `b` taken would
# create the first account and then stop, leaving a live one behind.
$taken = @()
foreach ($n in @($acct, $helper)) {
    if (Get-LocalUser  -Name $n            -ErrorAction SilentlyContinue) { $taken += ($n + ': a Windows user') }
    if (Get-LocalGroup -Name ('sdu_' + $n) -ErrorAction SilentlyContinue) { $taken += ($n + ': an sdu_ group') }
    if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $n.ToUpper()))) {
        $taken += ($n + ': an ACCOUNTS record')
    }
    if (Test-Path -LiteralPath (Join-Path $env:SystemDrive ('Users\' + $n))) {
        $taken += ($n + ': a Windows PROFILE DIRECTORY (PRE_RELEASE 35/36 - only a restart releases it)')
    }
}
if ($taken.Count -gt 0) {
    Write-Output ("verify-doors-suite: {0} is not free - it already has:" -f $Prefix)
    $taken | ForEach-Object { Write-Output ('    ' + $_) }
    Write-Output ''
    Write-Output '  A PREFIX IS SINGLE-USE, AND IT COVERS BOTH ITS NAMES.  Each account signs'
    Write-Output '  in over ssh and leaves a profile Windows will not overwrite; a rebuilt'
    Write-Output '  account gets a SUFFIXED home, which puts an unmeasured variable into a test'
    Write-Output '  whose whole point is that the suspension is the only thing that changes.'
    Write-Output '  Use a fresh -Run token.  NOTHING WAS CREATED.'
    exit 2
}
Write-Output ("  {0} and {1} are both free: no Windows user, no sdu_ group, no ACCOUNTS record, no profile" -f $acct, $helper)

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

# THE WORK DIRECTORY, made only now that the run is really going ahead - see
# the comment where $work is named.  Everything that writes into it runs below
# this line, and the finally removes it.
New-Item -ItemType Directory -Path $work | Out-Null

# ***START THE HELPER BEFORE ANYTHING IS CREATED.***  If consent is refused
# this falls back to a prompt per leg rather than failing the run: the point of
# the helper is fewer prompts, and a run that cannot have fewer should still be
# able to happen.
if (-not $NoHelper) {
    if (-not (Start-ElevationHelper)) { $script:helperPipe = '' }
} else {
    Write-Output '  -NoHelper: a UAC prompt per elevated leg, the route -Run b53 went green on.'
}

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
    # ***$work GOES FIRST AND IT CARRIES THE SECRET.***  The helper route bakes
    # the password into the Create launcher, so this removal is not tidiness -
    # it is the deletion the measurement above relies on when it argues a file
    # beats a command line.  Recurse/Force, and in finally so a step that dies
    # outright does not leave it.
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Stop-ElevationHelper
}

# ------------------------------------------------------------------- report

Write-Output ''
$legs | Format-Table -AutoSize | Out-String | Write-Output

if ($stopped -ne '') {
    Write-Output ('  STOPPED: ' + $stopped)
}
Write-Output ("  The profile directories C:\Users\{0} and C:\Users\{1} are expected to remain - PRE_RELEASE 35/36." -f $acct, $helper)
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
