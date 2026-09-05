# elevate-once.ps1 - ONE UAC consent for a whole verify run
#
# 4 Sep 26 - PRE_RELEASE 165, on the owner's ruling "do the elevate fix before
# 1.0".  DOT-SOURCED, NOT RUN:
#
#     . (Join-Path $PSScriptRoot 'elevate-once.ps1')
#
# WHY THIS FILE EXISTS AT ALL, AND IT IS NOT "THREE CALLERS WANTED THE SAME
# THING".  verify-doors-suite.ps1 and verify-sdsyswrite.ps1 had already grown
# Start-ElevationHelper / Stop-ElevationHelper independently, and THE TWO COPIES
# HAD DRIFTED APART IN THE TWO PLACES THAT DECIDE WHETHER THE MECHANISM WORKS:
#
#   * doors-suite used a RANDOM pipe name ('sddoors-' + guid), so SD's own
#     elevate('START') inside LOGTO SDSYS could not find it and prompted again.
#     sdsyswrite used SD's name and SD shared it.  SD'S NAME IS RIGHT and is
#     what this file uses - gpl.bp/ELEVATE:121 builds 'sd-elev-' : @logname.
#   * doors-suite sent a BARE -Stop, which stops the helper outright.
#     sdsyswrite sent -Stop -OwnerPid $PID, which deregisters one session.
#     Neither is right for a step that ADOPTED somebody else's helper: both
#     take the privilege away from the run that is still using it.
#
# That is the defect class PRE_RELEASE 46 was, and the reason stale-binaries.ps1
# and suite-only.ps1 exist: one fact, one copy.
#
# ***THE 300-SECOND CLAIM THAT PARKED THIS FOR A WEEK IS FALSE, AND IT WAS
# MEASURED RATHER THAN RE-READ.***  PROJECT_STATUS.md 24, HISTORY.md and
# verify-doors-suite.ps1's own header all said sd-elevate.ps1 "hard-codes a
# 300-second per-request timeout" which VerifyInstall2's ~15-minute half could
# not fit inside - so the door legs went through the helper and the handover
# could not, and taking the suite to one prompt "means editing a shipped file".
#
# sd-elevate.ps1:162 passes 300000 to Send-Request, and Send-Request passes its
# timeout to $c.Connect() AND TO NOTHING ELSE.  The reply read is
# StreamReader.ReadLine() on a pipe with no ReadTimeout set: unbounded.
# Measured 4 Sep 2026 with a server that replied 6 s after a 1.5 s connect
# timeout - the reply arrived intact at 6025 ms - against a control on a pipe
# with no server at all, which refused at 1497 ms.  The control is what makes
# the first leg mean anything: it proves the number is live rather than dead.
#
# SO NOTHING SHIPPED NEEDS EDITING AND NO CYCLE IS OWED FOR IT.  sd-elevate.ps1
# and sd-elevate-helper.ps1 are untouched by PRE_RELEASE 165; they are called
# exactly as SD calls them.
#
# WHAT THE CALLER MUST NOT DO, AND IT IS THE ONE TRAP HERE.  VerifyInstall1 runs
# its steps IN-PROCESS (VerifyInstall1.ps1:1013, "& $path @splat"), so every
# step shares the runner's $PID.  The helper's owner set is keyed by pid
# (sd-elevate-helper.ps1:85), so a step that sends -Stop -OwnerPid $PID removes
# THE RUNNER'S registration, the set empties, and the helper exits - taking the
# consent with it and prompting again at the next step.  Hence:
#
#   ***A SCRIPT THAT ADOPTED A PIPE MUST NEVER STOP IT.***  Stop-SdElevationHelper
#   below is a no-op unless this process started the helper itself, and that is
#   enforced here rather than remembered at five call sites.

# NO FILE-SCOPE Set-StrictMode.  It leaks through dot-source and binds the
# CALLER's whole script, which is a behaviour change none of these five files
# asked for; it goes in each function instead.
#
# ***EVERY PRINT IN THIS FILE IS Write-Host, AND THAT IS LOAD-BEARING RATHER
# THAN A STYLE.***  A PowerShell function's return value is its whole OUTPUT
# stream, so a function that Write-Outputs AND returns hands the caller an
# ARRAY with the value on the end.  Both functions here return a hashtable, and
# the first draft of this file used Write-Output and did exactly that:
# test-elevonce-units.ps1 went red on its first run with "The property 'Active'
# cannot be found on this object".  verify-doors-suite.ps1:170 records the same
# trap costing it a unit-test failure, thirty lines below its own warning about
# it, and verify-sdsyswrite.ps1 already uses Write-Host here for this reason.
#
# NOTHING IS LOST BY IT.  Write-Host goes to the INFORMATION stream, which
# Start-Transcript records and which VerifyInstall1's handover captures with
# "*>&1 | Tee-Object" (VerifyInstall1.ps1:1224).  DO NOT "tidy" these back.

# State lives in ONE hashtable rather than three loose variables, because a
# dot-sourced $script: variable lands in the CALLER's script scope and three of
# them can drift out of step with each other.  Reason is kept so the caller can
# print WHY a route was taken - a fallback nobody can see is the thing the
# instrument rules forbid.
$script:sdElev = @{
    Pipe    = ''
    Started = $false
    Reason  = 'not started'
}

# gpl.bp/ELEVATE:121 builds the name as 'sd-elev-' : @logname.  Using the same
# one is not tidiness: it is what lets SD's own elevate('START'), fired by a
# LOGTO SDSYS inside a verifier, find this helper and ask for nothing.
function Get-SdElevPipeName {
    Set-StrictMode -Version Latest
    return ('sd-elev-' + $env:USERNAME)
}

# Read-only view, for callers that report and for test-elevonce-units.ps1.
# A CLONE, so a caller cannot edit the live state by holding the return value.
function Get-SdElevationState {
    Set-StrictMode -Version Latest
    return @{
        Pipe    = $script:sdElev.Pipe
        Started = $script:sdElev.Started
        Reason  = $script:sdElev.Reason
        Active  = (-not [string]::IsNullOrEmpty($script:sdElev.Pipe))
    }
}

# Start a helper, or adopt one a parent has already started.
#
# RETURNS A HASHTABLE, NOT A BOOL.  A PowerShell function's return value is its
# whole output stream, so one that prints AND returns hands the caller an array
# with the value on the end - the trap that already cost verify-doors-suite a
# unit-test failure.  Everything printed here is Write-Host (see the header) and
# the VERDICT is read from the hashtable, so the two cannot be confused.
function Start-SdElevationHelper {
    param(
        # A pipe name a parent process is already serving.  When set, nothing is
        # started, nothing prompts, and Stop is a no-op for the rest of this
        # process's life.
        [string] $Adopt = '',

        # Printed in the consent warning so the person approving knows what for.
        [string] $Purpose = 'this run',

        # Set to skip the helper entirely and leave every caller on its own
        # Start-Process -Verb RunAs.  The route the suite went green on.
        [switch] $NoHelper
    )
    Set-StrictMode -Version Latest

    $script:sdElev = @{ Pipe = ''; Started = $false; Reason = '' }

    if ($NoHelper) {
        $script:sdElev.Reason = '-NoHelper: a UAC prompt per elevated step, the route the suite went green on'
        Write-Host ('  ' + $script:sdElev.Reason)
        return (Get-SdElevationState)
    }

    if ($Adopt -ne '') {
        # ADOPTION IS NOT VERIFIED HERE, DELIBERATELY.  Test-Helper lives inside
        # sd-elevate.ps1 and answering "is one there" costs a pipe round trip;
        # the caller that passed this name started it and checked. If it has
        # since died, Invoke-ElevatedScript below gets exit 9 ("no helper is
        # running for this user") and falls back to a prompt, saying so.
        $script:sdElev.Pipe    = $Adopt
        $script:sdElev.Started = $false
        $script:sdElev.Reason  = ('adopted the pipe already serving this run: ' + $Adopt)
        Write-Host ('  elevation: ' + $script:sdElev.Reason)
        Write-Host '  no consent is needed here, and this step will NOT stop it.'
        return (Get-SdElevationState)
    }

    $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
    if (-not (Test-Path -LiteralPath $elev)) {
        $script:sdElev.Reason = ('no sd-elevate.ps1 at ' + $elev + ' - a UAC prompt per elevated step')
        Write-Host ('  ' + $script:sdElev.Reason)
        return (Get-SdElevationState)
    }

    $pipe = Get-SdElevPipeName

    # RULE 1 OF THE INSTRUMENT SECTION: print the real command line, resolved,
    # before it runs.  A helper that did not start is diagnosed from this line.
    Write-Host ''
    Write-Host ('  *** ONE UAC PROMPT IS COMING, AND IT IS THE ONLY ONE ' + $Purpose + ' ASKS FOR.')
    Write-Host ('      ' + $elev + ' -Start -PipeName ' + $pipe + ' -OwnerPid ' + $PID)

    try {
        & $elev -Start -PipeName $pipe -OwnerPid $PID | Out-Null
        $rc = $LASTEXITCODE
    } catch {
        $script:sdElev.Reason = ('sd-elevate.ps1 threw: ' + $_.Exception.Message)
        Write-Host ('  ' + $script:sdElev.Reason + ' - a UAC prompt per elevated step.')
        return (Get-SdElevationState)
    }

    if ($rc -ne 0) {
        # 5 is sd-elevate.ps1's "not elevated / refused or unavailable"; 9 is
        # "no helper"; 1 is a failure to launch.  Naming them beats a bare code.
        $what = switch ($rc) {
            5       { 'consent was refused, or there is no desktop to show it on' }
            9       { 'no helper is running for this user' }
            default { 'it failed to launch' }
        }
        $script:sdElev.Reason = ("the helper did not start (exit {0}): {1}" -f $rc, $what)
        Write-Host ('  ' + $script:sdElev.Reason)
        Write-Host '  Falling back to a UAC prompt per elevated step; the run still happens.'
        return (Get-SdElevationState)
    }

    $script:sdElev.Pipe    = $pipe
    $script:sdElev.Started = $true
    $script:sdElev.Reason  = ('started the helper on ' + $pipe)
    Write-Host ('  helper is serving on pipe ' + $pipe + '; SD will share it.')
    Write-Host '  Every elevated step below is covered by the consent just given.'
    return (Get-SdElevationState)
}

# ***A NO-OP UNLESS THIS PROCESS STARTED IT.***  See the header: steps run
# in-process and share the runner's pid, so a -Stop from an adopting step
# empties the owner set and kills the helper the run is still using.
function Stop-SdElevationHelper {
    Set-StrictMode -Version Latest

    if ([string]::IsNullOrEmpty($script:sdElev.Pipe)) { return }

    if (-not $script:sdElev.Started) {
        Write-Host ('  leaving the adopted helper running (pipe ' + $script:sdElev.Pipe +
                      ') - it belongs to the caller.')
        $script:sdElev.Pipe   = ''
        $script:sdElev.Reason = 'released an adopted pipe without stopping it'
        return
    }

    $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
    if (Test-Path -LiteralPath $elev) {
        # BARE -Stop, WITHOUT -OwnerPid, AND THAT IS THE RIGHT ONE HERE.  A
        # deregistering stop removes one pid; every step shared this pid, so the
        # two are the same thing at this point - except that a bare STOP also
        # clears a registration a step leaked by dying before its own cleanup.
        try { & $elev -Stop -PipeName $script:sdElev.Pipe | Out-Null } catch { }
        Write-Host ('  elevation helper stopped (pipe ' + $script:sdElev.Pipe + ').')
    }
    $script:sdElev.Pipe    = ''
    $script:sdElev.Started = $false
    $script:sdElev.Reason  = 'stopped'
}

# Run a PowerShell script file elevated: through the helper when one is serving,
# otherwise Start-Process -Verb RunAs exactly as before.
#
# -Visible is what lets the -ThenElevated handover keep its window.  The helper
# runs what it is sent HIDDEN (sd-elevate-helper.ps1:244), which is right for a
# three-second account write and wrong for a fifteen-minute suite the owner
# watches.  So for -Visible the helper is sent a WRAPPER whose only job is to
# Start-Process the real launcher with a normal window: the wrapper is already
# elevated, so its child inherits the elevated token and NO consent is asked.
#
# RETURNS A HASHTABLE.  Ok says whether the child ran at all, which is a
# different question from ExitCode - a declined prompt and a step that exited 1
# must never collide on one number, which is the fault VerifyInstall1.ps1:1200
# records costing a run.
function Invoke-ElevatedScript {
    param(
        [string] $Launcher = '',
        [string] $Why      = '',
        [switch] $Visible,

        # Drop -NonInteractive from the child.  ***NOT COSMETIC.***  Under
        # -NonInteractive a Read-Host THROWS rather than waiting - measured, and
        # VerifyInstall1.ps1:340 records the message - so a child that might ask
        # a person something must not carry it.  The -ThenElevated handover is
        # the case: VerifyInstall2 ran with -Command and no -NonInteractive
        # before this file existed, and quietly gaining one here would turn a
        # question into a stack trace an hour into an elevated run.
        [switch] $Interactive
    )
    Set-StrictMode -Version Latest

    # REFUSE THE NULL CASE OUT LOUD.  An empty path here would reach
    # Start-Process as a missing argument and produce a binding error that names
    # no element, or reach the helper as a path it reports "no such script" for
    # - both of which read as a measurement rather than a refusal.
    if ([string]::IsNullOrEmpty($Launcher)) {
        Write-Host '  REFUSING to elevate: no launcher path was given. Nothing was run.'
        return @{ Ok = $false; ExitCode = 2; Route = 'refused'; Reason = 'empty launcher path' }
    }
    if (-not (Test-Path -LiteralPath $Launcher)) {
        Write-Host ('  REFUSING to elevate: ' + $Launcher + ' is not there. Nothing was run.')
        return @{ Ok = $false; ExitCode = 2; Route = 'refused'; Reason = 'launcher does not exist' }
    }

    if ($Why -ne '') { Write-Host ('      elevated: ' + $Why) }

    $psArgs = @('-NoProfile')
    if (-not $Interactive) { $psArgs += '-NonInteractive' }
    $psArgs += @('-ExecutionPolicy', 'Bypass', '-File', $Launcher)

    # REFUSE THE NULL CASE IN THE ARGUMENT LIST TOO.  An empty element makes
    # Start-Process reject the WHOLE list with a message that names none of them
    # - the fault verify-doors-suite.ps1 records, where a clobbered $args meant
    # setup ran with no switches at all and the verdict passed trivially.
    $empties = @(0..($psArgs.Count - 1) | Where-Object { [string]::IsNullOrEmpty($psArgs[$_]) })
    if ($empties.Count -gt 0) {
        Write-Host ('  REFUSING to elevate: argv element(s) ' + ($empties -join ', ') + ' are empty.')
        return @{ Ok = $false; ExitCode = 2; Route = 'refused'; Reason = 'empty argv element' }
    }

    # ---------------------------------------------------------------- helper
    if (-not [string]::IsNullOrEmpty($script:sdElev.Pipe)) {
        $elev = Join-Path $PSScriptRoot 'sd-elevate.ps1'
        $send = $Launcher

        if ($Visible) {
            # The wrapper runs INSIDE the elevated helper, so this Start-Process
            # carries no -Verb: there is no elevation transition and no prompt.
            # No -WindowStyle either, so it gets an ordinary visible console.
            #
            # SINGLE-QUOTED PATHS, which process no escapes, so a backslash in a
            # Windows path is literal.  An apostrophe would break it, and %TEMP%
            # under a user whose name contains one is the case that would do it
            # - so it is refused rather than generated wrong.
            if (@($psArgs | Where-Object { $_ -match "'" }).Count -gt 0) {
                Write-Host '  REFUSING to elevate: an argument contains an apostrophe.'
                return @{ Ok = $false; ExitCode = 2; Route = 'refused'; Reason = 'apostrophe in an argument' }
            }
            # ***BUILT FROM $psArgs, NOT WRITTEN OUT AGAIN.***  The wrapper's
            # child must carry the SAME switches the -Verb RunAs route would
            # have given it, -NonInteractive included or excluded - a second
            # hand-typed list is how the two routes come to measure different
            # things while both reporting success.
            $inner = '@(' + (($psArgs | ForEach-Object { "'" + $_ + "'" }) -join ',') + ')'
            $wrapper = [System.IO.Path]::ChangeExtension($Launcher, '.visible.ps1')
            $ws = @(
                "`$p = Start-Process -FilePath 'powershell.exe' -Wait -PassThru ``",
                "        -ArgumentList $inner",
                "exit `$p.ExitCode"
            ) -join "`r`n"
            [System.IO.File]::WriteAllText($wrapper, $ws + "`r`n", [System.Text.Encoding]::ASCII)
            $send = $wrapper
        }

        Write-Host ('      via helper: ' + $send)
        try {
            & $elev -Run -PipeName $script:sdElev.Pipe -OwnerPid $PID -Script $send | Out-Null
            $rc = $LASTEXITCODE
        } catch {
            return @{ Ok = $false; ExitCode = 2; Route = 'helper'
                      Reason = ('sd-elevate.ps1 -Run threw: ' + $_.Exception.Message) }
        }

        # 9 is "no helper is running for this user" - it died between the start
        # and now.  That is a route failure, not the child's verdict, so it falls
        # through to a prompt rather than being reported as an exit code.
        if ($rc -eq 9) {
            Write-Host '  the helper has gone (exit 9) - asking for consent for this step instead.'
            $script:sdElev.Pipe   = ''
            $script:sdElev.Reason = 'the helper disappeared mid-run'
        } else {
            return @{ Ok = $true; ExitCode = $rc; Route = 'helper'; Reason = 'ran through the resident helper' }
        }
    }

    # ------------------------------------------------------------ -Verb RunAs
    Write-Host '      EXPECT A UAC PROMPT NOW.'
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs `
                 -Verb RunAs -Wait -PassThru -ErrorAction Stop
    } catch {
        # Declining UAC throws here rather than returning a code, and the message
        # is the SAME as a desktop-less shell gets when no prompt could be shown
        # at all (PROJECT_STATUS.md 4.0.1).  Name both; they are not
        # distinguishable from the exception.
        return @{ Ok = $false; ExitCode = 2; Route = 'runas'
                  Reason = ('elevation did not happen - ' + $_.Exception.Message +
                            ' (declined, or no desktop to show the prompt on)') }
    }
    return @{ Ok = $true; ExitCode = $p.ExitCode; Route = 'runas'; Reason = 'ran through its own UAC prompt' }
}
