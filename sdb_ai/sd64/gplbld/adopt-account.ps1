#
# adopt-account.ps1 - give the installing user an SD account
#
# Run once by the installer, with the name of whoever authenticated the UAC
# prompt.  Without it SD installs perfectly and then refuses the person who
# installed it: every SD account brings its own Windows account, and theirs
# existed first, so "sd" answers "Account DON not in register".  See
# PROJECT_STATUS.md 7 step 1f.
#
# CREATE.ACCOUNT USER <name> ADOPT is the sanctioned door.  It attaches an SD
# account to an operating system account that is already there, creating no
# user and setting no password, and it is gated on K$INTERNAL - so it is
# reachable from "sd -internal", which is what the install uses.
#
# AND SINCE 21 AUG 2026 ON A ONE-SHOT MARKER AS WELL, WHICH THIS SCRIPT WRITES.
# Owner's ruling: "-internal is an unpublished development flag, never exposed
# to customers - so gating ADOPT on K$INTERNAL is not install-only.  ADOPT must
# be usable during installation and not afterwards."
#
# THAT REVERSES THE PARAGRAPH THAT STOOD HERE, and it is worth saying which one.
# It read: the gate is not a wall and is not meant to be; an elevated
# administrator can type the verb themselves and give another administrator an
# account; owner's position, 15 Aug 2026, that this is fine as long as it stays
# undocumented.  It is no longer fine.  The keyword is now refused - as an
# unrecognised token, so it still tells nobody it exists - unless the marker is
# there, and the marker exists for the length of one call from this script.
#
# THE MARKER IS NOT A SECRET AND DOES NOT NEED TO BE.  The data tree grants
# sdusers Modify, so an ordinary user can create the file; it buys them nothing,
# because K$INTERNAL still means "sd -internal", which forces SDSYS, which LOGIN
# refuses without an elevated session.  What the marker adds is a window in
# time, not a second identity test.
#
# AND SINCE 21 AUG 2026 IT IS A WINDOW FOR ONE NAME.  The file is
# 'sdsys\$adopt.<user>', so a marker authorises adopting that account and no
# other.  Owner's ruling: the project AS DELIVERED must enforce that SD account
# setup happens in SD - a generic marker re-opened the verb for every name, and
# an elevated administrator forging one afterwards is degrading their own
# install, which is their right and is not what this defends against.
#
# IT IS REMOVED TWICE OVER.  CREATEA deletes it when it accepts the keyword, and
# the finally below deletes it whatever happened - because the failure that
# matters here is the one where it survives the install and leaves the door
# propped open for the life of the machine.
#
# THREE THINGS KILLED THE LAST STEP THAT TRIED THIS, the SDSYS password step
# whose gravestone is at the bottom of gplbld/sd.iss.  All three are handled
# here, and a change that reintroduces any of them will fail the same silent
# way:
#
#   * sd -internal NEEDS A RUNNING SERVER, and the installer starts none.  So
#     this starts SD if it is not up, and stops it again only if it was the one
#     that started it - the machine is left as it was found.
#   * IT NEEDS AN ELEVATED TOKEN.  The password step was a "postinstall"
#     checkbox, which Inno runs as the original user, so it ran unelevated and
#     could not have reached SDSYS even with a server up.  sd.iss calls this
#     from [Code] at ssPostInstall instead, which has Setup's own elevated
#     token.
#   * ITS OUTPUT HAS TO SURVIVE.  The old step used "nowait", so the console
#     carrying the error vanished before anyone could read it.  Everything here
#     is captured and summarised for the installer log.
#
# EXIT CODES, and sd.iss reports each one differently:
#   0  the account was created
#   2  the account was already there - the reinstall case, not a failure
#   3  SD would not start, so the verb was never run
#   1  the verb ran and refused, or something was missing
#

[CmdletBinding()]
param(
    # Whoever is being given the account.  The installer passes {username},
    # which Inno documents as the user who authenticated the elevation prompt -
    # the right one, and not necessarily the one who double-clicked.
    [Parameter(Mandatory = $true)]
    [string] $User,

    # Where SD's program files are.  The installer passes {app}; running it by
    # hand, the default below works it out.
    #
    # NOT "= $PSScriptRoot" HERE, AND THAT COST A WHOLE INSTALL.  Measured
    # 15 Aug 2026: in a script with [CmdletBinding()] and a mandatory parameter,
    # $PSScriptRoot evaluates to the EMPTY STRING in a param default - the same
    # script without them resolves it correctly.  So this ran on a real install
    # with AppDir empty, Join-Path threw "cannot bind argument to parameter
    # 'Path'", and PowerShell exited 1 with nothing to read.  It never showed in
    # testing because every run by hand passed -AppDir.  It is assigned in the
    # BODY instead, where $PSScriptRoot is populated.
    [string] $AppDir = '',

    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Stop'

# EVERYTHING SAID HERE IS ALSO WRITTEN TO A FILE, because the installer calls
# this through Exec with SW_HIDE and nothing survives otherwise.  Measured
# 15 Aug 2026: the step did not create the account on a real install and left
# no trace at all to work from - the same silent failure as the OpenSSH brace
# bug and the SDSYS password step before it.  A log costs nothing and is the
# difference between "it did not work" and knowing why.
$LogFile = Join-Path $DataDir 'adopt-account.log'

function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }

Say "=== adopt-account $User, AppDir=$AppDir, DataDir=$DataDir"

if (-not $AppDir) {
    Say "adopt-account: no -AppDir given and PSScriptRoot is empty; cannot find sd.exe"
    exit 1
}

$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) {
    Say "adopt-account: no sd.exe at $sd"
    exit 1
}

# An ACCOUNTS record is one file per account, keyed by the UPPERCASED name -
# checked on this machine rather than assumed: SDSYS, SDACCT2..SDACCT5 sit
# beside directories named sdacct2..sdacct5 in lower case.
$record = Join-Path $DataDir ('sdsys\accounts\' + $User.ToUpper())

function Invoke-Sd {
    <#
      Run one SD command and return its exit code and output.

      NEVER "Start-Process -Wait" here.  sdwind inherits sd's handles and
      outlives it, so anything waiting for the output streams to close waits
      for the daemon instead - measured twice on 15 Aug 2026, in bash and in
      PowerShell, both times while SD had in fact done its job
      (PROJECT_STATUS.md 6).  Waiting on the PROCESS is what works.
    #>
    param([string[]] $SdArgs)

    $out = Join-Path $env:TEMP ("sd-adopt-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-adopt-err-$PID.txt")
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru `
                       -RedirectStandardOutput $out -RedirectStandardError $err
    $exited = $p.WaitForExit(120000)
    $text = ''
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) {
            $text += (Get-Content $f -Raw)
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $exited) {
        return [pscustomobject]@{ Code = 1; Text = "sd $SdArgs did not finish within two minutes" }
    }
    return [pscustomobject]@{ Code = $p.ExitCode; Text = $text.Trim() }
}

function Test-SdRunning {
    return $null -ne (Get-Process sdwind -ErrorAction SilentlyContinue)
}

function Wait-SdRunning {
    <#
      WAIT FOR sdwind RATHER THAN LOOKING ONCE.

      "sd -start" forks the daemon and returns as soon as it has done so, so
      sdwind appears in the process table a moment AFTER sd.exe exits.  Looking
      immediately wins that race on an idle machine and loses it on a busy one.

      Measured 15 Aug 2026 with a VirtualBox guest running on the same host:
      sd -start printed "SD (64 Bit) has been started" and exited 0, this
      script reported "SD would not start", and the install finished leaving
      the installing user with no SD account - which is the one thing 7 step 1f
      exists to provide.  The failure was silent apart from a line in
      adopt-account.log, and the closing dialog then told the user to run the
      verb by hand.
    #>
    param([int] $TimeoutSeconds = 20)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-SdRunning) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (Test-SdRunning)
}

# --- the reinstall case, answered before anything is started ----------------
#
# Checked on disk rather than by running the verb, so a reinstall costs nothing
# and touches nothing.  The verb would answer "Account already exists" anyway;
# this way the installer never starts a server to be told so.
if (Test-Path $record) {
    Say "adopt-account: $User already has an SD account; nothing to do"
    exit 2
}

# --- make sure there is a server ---------------------------------------------

$weStartedIt = $false
if (-not (Test-SdRunning)) {
    $r = Invoke-Sd @('-start')
    if (-not (Wait-SdRunning)) {
        Say "adopt-account: SD would not start, so no account was made"
        Say ("  sd -start exited {0}: {1}" -f $r.Code, $r.Text)
        exit 3
    }
    $weStartedIt = $true
}

try {
    # --- open the door, for one call -----------------------------------------
    #
    # Single quotes: in double quotes PowerShell would read $adopt as a variable
    # and expand it to nothing, leaving the marker at sdsys\ - which is a
    # directory, so New-Item would fail and ADOPT would be refused.  The name is
    # CREATEA's, at the adopt.marker assignment.
    #
    # THE NAME IS IN THE PATH, NOT IN THE CONTENT - 21 Aug 2026.  This used to
    # be a bare 'sdsys\$adopt' and said so here: content "would have to be
    # parsed by the verb to mean anything, and a mismatch on case or a domain
    # prefix would break the install for no gain".  The parsing objection was
    # right and is answered by putting the name in the FILE NAME instead; the
    # "no gain" was overruled by the owner on 21 Aug 2026 - the project as
    # delivered must enforce that SD account setup happens in SD, and a generic
    # marker re-opens the verb for every name rather than for one.
    #
    # NEITHER SIDE CAN DRIFT: the name written here and the name CREATEA tests
    # are the same $User this script was invoked with, downcased on both sides.
    # CREATEA does it at the adopt.marker assignment in the USER arm.
    #
    # WHAT IS IN IT IS STILL FOR A HUMAN.  A marker that outlives its window is
    # a hole, so anybody who finds one should be able to tell at a glance what
    # wrote it and when.
    $marker = Join-Path $DataDir ('sdsys\$adopt.' + $User.ToLower())

    # CAUGHT RATHER THAN LEFT TO $ErrorActionPreference, which is Stop: an
    # uncaught throw here would leave the finally to run with $result never
    # assigned, and "exit $result" would then fail on its own account and bury
    # the real reason.  Without the marker the verb is refused, so there is no
    # point running it - say so and stop.
    $markerOk = $true
    try {
        Set-Content -LiteralPath $marker -Encoding utf8 -Value @(
            "Written by adopt-account.ps1 for $User at $(Get-Date -Format 's').",
            "It permits ONE 'CREATE.ACCOUNT USER $User ADOPT' and is deleted on use.",
            'It authorises that name only - the name is part of this file name.',
            'If this file is still here, the install did not finish - delete it.')
    }
    catch {
        $markerOk = $false
        Say "adopt-account: could not write $marker - $($_.Exception.Message)"
    }

    if (-not $markerOk) {
        Say "adopt-account: without the marker ADOPT is refused, so it was not run"
        $result = 1
    }
    else {
        # --- the verb --------------------------------------------------------
        #
        # Separate arguments, not one string: the same shape PROJECT_STATUS.md 7
        # step 0 records for every other -internal command, and not piped,
        # because a piped session has its own traps.
        $r = Invoke-Sd @('-internal', 'CREATE.ACCOUNT', 'USER', $User, 'ADOPT')

        # JUDGED ON THE RECORD, NOT ON THE EXIT STATUS.  CREATE.ACCOUNT reports
        # failure through @system.return.code and a message; the process status
        # is not a reliable summary of it.  The account either exists afterwards
        # or it does not.
        if (Test-Path $record) {
            Say "adopt-account: $User now has an SD account"
            if ($r.Text) { Say $r.Text }
            $result = 0
        }
        else {
            Say "adopt-account: CREATE.ACCOUNT USER $User ADOPT did not create an account"
            Say $r.Text
            $result = 1
        }
    }
}
finally {
    # SHUT THE DOOR, whatever happened above.  CREATEA deletes the marker when
    # it accepts the keyword, so on the ordinary path this finds nothing; what
    # it is here for is every other path - the verb refused, sd never ran, the
    # process was killed.  A marker left behind is the one failure mode that
    # matters, because nothing later would notice it.
    #
    # ERRORS SWALLOWED DELIBERATELY.  Being unable to remove it is worth
    # recording but must not change the exit code: the account either exists or
    # it does not, and that is what sd.iss reports on.
    if ($marker -and (Test-Path -LiteralPath $marker)) {
        try {
            Remove-Item -LiteralPath $marker -Force -ErrorAction Stop
            Say "adopt-account: removed the one-shot ADOPT marker"
        }
        catch {
            Say "adopt-account: COULD NOT REMOVE $marker - delete it by hand"
        }
    }

    # Leave the machine as it was found.  An install that silently leaves a
    # daemon running is a surprise, and a reinstall over a running system must
    # not stop somebody else's server.
    if ($weStartedIt) {
        $null = Invoke-Sd @('-stop')
    }
}

exit $result
