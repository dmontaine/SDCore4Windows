# attach-account.ps1 - give the INSTALLING Windows user their regular SD
# account, at install time, through CREATE.ACCOUNT's one install-only door.
#
# 18 Sep 26 Windows port - RELEASE_1.1 66.  THE OWNER'S REQUIREMENT, VERBATIM:
# "during the install, the regular sd account for the installer needs to be
# created as well since you can't create an account later because sd only
# recognizes accounts it creates."  The second half is measured in the verb:
# CREATEA refuses every existing Windows account with 10038, and under 64
# nothing else gives one an SD account - so the person who installed SD would
# have NO account of their own, ever, unless the install makes it.
#
# THIS IS ADOPT'S OLD JOB WITH 64'S ANSWER, NOT ADOPT BACK.  The old keyword
# minted an ADMINISTRATOR out of the installing user; 64 forbids that, and
# this mints an ORDINARY account - no tier, the route keyword said like
# anybody's.  The mechanism is the one the tree already paid for, restored:
# an internal-only, marker-gated keyword that a console session can never
# type.  See CREATEA's ATTACH case for the verb's half and its gating record.
#
# NO ROUTE KEYWORD IS PASSED, AND THAT IS A CHANGE - RELEASE_1.1 68, 19 Sep
# 2026.  It used to pass BOTH because the keyword was REQUIRED (10082): the old
# adopt call passed none and the 15:07:23 install measured what that cost - the
# verb stopped at "Say who may reach this account" with nobody to answer.  68
# made silence mean BOTH, on the owner's ruling that "every non-sdsys account
# has the potential to have ssh and api access by default, but it is the admins
# choice if it should stay on".  So the account still gets both routes; the
# difference is that the DEFAULT says so rather than this line.
# MODIFY.ACCOUNT narrows it any time afterwards, from the SDSYS session, and
# widens it again - the owner was explicit that it is a two-way door.
#
# THE POINT OF DROPPING IT IS PARITY, NOT TIDINESS.  Linux's teardown deleted
# the route grammar outright, so BOTH is an "Unexpected token" there; with 68
# both ports run the identical install line, which is what the owner asked for
# when he said the solution must be the same on the two systems.
#
# ***IT WILL FAIL AGAINST A PRE-68 TREE***, stopping at 10082 with nobody to
# answer - the exact 15:07:23 failure above, arrived at from the other side.
# The verb and this script have to move together.
#
# NO PASSWORD IS SET, AND NONE IS NEEDED FOR THE CONSOLE.  ATTACH touches
# nothing about the Windows account - the person's Windows password is their
# password.  An SD credential (the API's gate, $cred) is not written either;
# LOGIN's require.credential offers to set one at their first elevated
# interactive sign-in, and MODIFY.PASSWORD sets one any time.
#
# Owner's ruling on the flag this runs under: "-internal is an unpublished
# development flag, never exposed to the user" - and the marker narrows even
# that: sdsys\$attach.<user>, written immediately before the call and deleted
# on acceptance or in the finally below.  Without the marker ATTACH is an
# unrecognised token, so it still tells nobody it exists - unless the marker
# is there, and the marker exists for the length of one call from this
# script.  A marker authorises attaching that account and no other, because
# the name is part of the file name.
#
# THREE THINGS KILLED THE STEP THAT TRIED THIS ORIGINALLY, the SDSYS password
# step whose gravestone is at the bottom of gplbld/sd.iss.  All three are
# handled here, and a change that reintroduces any of them will fail the same
# silent way:
#
#   * sd -internal NEEDS A RUNNING SERVER, and the installer starts none.  So
#     this starts SD if it is not up, and stops it again only if it was the one
#     that started it - the machine is left as it was found.
#   * IT NEEDS AN ELEVATED TOKEN.  sd.iss calls this from [Code] at
#     ssPostInstall, which has Setup's own elevated token.
#
#     18 Sep 26 - THAT SENTENCE WAS WRITTEN BEFORE IT WAS TRUE, AND WAS READ AS
#     A DESCRIPTION OF THE TREE.  For one install it was not: this script was
#     untracked, unstaged, unshipped and uncalled, sd.iss and stage.py had zero
#     mentions of it, and the 22:51 cycle compiled the ATTACH keyword into
#     CREATEA and shipped a verb nothing could reach.  The install ran clean and
#     made no account; only the empty accounts register said so.  It is true as
#     of the wiring below it in RELEASE_1.1 66 - AttachInstallerAccount in
#     sd.iss, called at ssPostInstall, and this file in stage.py's ship list.
#     Kept as a caution: a header describing the caller is a claim about a file
#     this one cannot see, and it goes stale silently.
#   * ITS OUTPUT HAS TO SURVIVE.  Everything here is captured and summarised
#     for the installer log.
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
    # script without them resolves it correctly.  It is assigned in the BODY
    # instead, where $PSScriptRoot is populated.
    [string] $AppDir = '',

    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Stop'

# EVERYTHING SAID HERE IS ALSO WRITTEN TO A FILE, because the installer calls
# this through Exec with SW_HIDE and nothing survives otherwise.  Measured
# 15 Aug 2026: the step did not create the account on a real install and left
# no trace at all to work from.  A log costs nothing and is the difference
# between "it did not work" and knowing why.
$LogFile = Join-Path $DataDir 'attach-account.log'

function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }

Say "=== attach-account $User, AppDir=$AppDir, DataDir=$DataDir"

if (-not $AppDir) {
    Say "attach-account: no -AppDir given and PSScriptRoot is empty; cannot find sd.exe"
    exit 1
}

$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) {
    Say "attach-account: no sd.exe at $sd"
    exit 1
}

# An ACCOUNTS record is one file per account, keyed by the name in LOWER case.
#
# IT DOES NOT MATTER FOR THE LOOKUP, and that was measured: a directory-file
# record is a file on NTFS, so the read is case-insensitive.  It matters for
# what gets WRITTEN, and for this test being able to say which case it expects
# to see.
#
# INVARIANT FOR THE SAME REASON AS THE MARKER BELOW: SD folds with the
# lc_chars[]/uc_chars[] ASCII maps, and .ToLower() on a Turkish locale sends
# "I" to a dotless U+0131.  This one decides the reinstall case, so a mismatch
# would make the installer try to attach an account already there.
$record = Join-Path $DataDir ('sdsys\accounts\' + $User.ToLowerInvariant())

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

    $out = Join-Path $env:TEMP ("sd-attach-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-attach-err-$PID.txt")
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru `
                       -RedirectStandardOutput $out -RedirectStandardError $err
    # 26 Aug 26 - TOUCH THE HANDLE OR ExitCode COMES BACK $null.  See the same
    # line and its measurement in upgrade-dicts.ps1's Invoke-Sd.  A diagnostic
    # that prints a blank is not one.
    $null = $p.Handle
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
      the installing user with no SD account - which is the one thing this
      step exists to provide.
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
    Say "attach-account: $User already has an SD account; nothing to do"
    exit 2
}

# --- make sure there is a server ---------------------------------------------

$weStartedIt = $false
if (-not (Test-SdRunning)) {
    $r = Invoke-Sd @('-start')
    if (-not (Wait-SdRunning)) {
        Say "attach-account: SD would not start, so no account was made"
        Say ("  sd -start exited {0}: {1}" -f $r.Code, $r.Text)
        exit 3
    }
    $weStartedIt = $true
}

try {
    # --- open the door, for one call -----------------------------------------
    #
    # Single quotes: in double quotes PowerShell would read $attach as a
    # variable and expand it to nothing.  The name is CREATEA's, at the
    # attach.marker assignment in its USER arm.
    #
    # THE NAME IS IN THE PATH, NOT IN THE CONTENT - the owner's 21 Aug 2026
    # ruling, carried across from the ADOPT marker: the project as delivered
    # must enforce that SD account setup happens in SD, and a generic marker
    # re-opens the verb for every name rather than for one.
    #
    # NEITHER SIDE CAN DRIFT: the name written here and the name CREATEA tests
    # are the same $User this script was invoked with, downcased on both sides.
    # CREATEA does it at the attach.marker assignment in the USER arm.
    #
    # AND "Invariant" IS WHAT MAKES THAT TRUE.  SD's downcase() is a fixed
    # ASCII byte map, lc_chars[], built A-Z -> a-z at ctype.c:61 and identity
    # everywhere else.  .ToLower() is CULTURE-SENSITIVE: on a Turkish or Azeri
    # locale "I" folds to a dotless U+0131, which is not what CREATEA will look
    # for.  The names valid_os_name permits are ASCII only, so the invariant
    # fold matches SD's map exactly.
    #
    # WHAT IS IN IT IS STILL FOR A HUMAN.  A marker that outlives its window is
    # a hole, so anybody who finds one should be able to tell at a glance what
    # wrote it and when.
    $marker = Join-Path $DataDir ('sdsys\$attach.' + $User.ToLowerInvariant())

    # CAUGHT RATHER THAN LEFT TO $ErrorActionPreference, which is Stop: an
    # uncaught throw here would leave the finally to run with $result never
    # assigned, and "exit $result" would then fail on its own account and bury
    # the real reason.  Without the marker the verb is refused, so there is no
    # point running it - say so and stop.
    $markerOk = $true
    try {
        Set-Content -LiteralPath $marker -Encoding utf8 -Value @(
            "Written by attach-account.ps1 for $User at $(Get-Date -Format 's').",
            "It permits ONE 'CREATE.ACCOUNT USER $User ATTACH' and is deleted on use.",
            'It authorises that name only - the name is part of this file name.',
            'If this file is still here, the install did not finish - delete it.')
    }
    catch {
        $markerOk = $false
        Say "attach-account: could not write $marker - $($_.Exception.Message)"
    }

    if (-not $markerOk) {
        Say "attach-account: without the marker ATTACH is refused, so it was not run"
        $result = 1
    }
    else {
        # --- the verb --------------------------------------------------------
        #
        # Separate arguments, not one string: the same shape PROJECT_STATUS.md 7
        # step 0 records for every other -internal command, and not piped,
        # because a piped session has its own traps.
        $r = Invoke-Sd @('-internal', 'CREATE.ACCOUNT', 'USER', $User, 'ATTACH')

        # JUDGED ON THE RECORD, NOT ON THE EXIT STATUS.  CREATE.ACCOUNT reports
        # failure through @system.return.code and a message; the process status
        # is not a reliable summary of it.  The account either exists afterwards
        # or it does not.
        if (Test-Path $record) {
            Say "attach-account: $User now has an SD account"
            if ($r.Text) { Say $r.Text }
            $result = 0
        }
        else {
            Say "attach-account: CREATE.ACCOUNT USER $User ATTACH did not create an account"
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
            Say "attach-account: removed the one-shot ATTACH marker"
        }
        catch {
            Say "attach-account: COULD NOT REMOVE $marker - delete it by hand"
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
