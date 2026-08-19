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
# THAT GATE IS NOT A WALL, AND IT IS NOT MEANT TO BE.  An elevated
# administrator can type "sd -internal CREATE.ACCOUNT USER x ADOPT" themselves
# and give another administrator an account.  Owner's position, 15 Aug 2026:
# that is fine, and it stays UNDOCUMENTED - it is not in the changelog and not
# in the installer's closing dialog.  Somebody who has found it already knows
# what they are doing; what the gate stops is an ordinary console session
# quietly adopting somebody's existing Windows login.
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
    # --- the verb ------------------------------------------------------------
    #
    # Separate arguments, not one string: the same shape PROJECT_STATUS.md 7
    # step 0 records for every other -internal command, and not piped, because
    # a piped session has its own traps.
    $r = Invoke-Sd @('-internal', 'CREATE.ACCOUNT', 'USER', $User, 'ADOPT')

    # JUDGED ON THE RECORD, NOT ON THE EXIT STATUS.  CREATE.ACCOUNT reports
    # failure through @system.return.code and a message; the process status is
    # not a reliable summary of it.  The account either exists afterwards or it
    # does not.
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
finally {
    # Leave the machine as it was found.  An install that silently leaves a
    # daemon running is a surprise, and a reinstall over a running system must
    # not stop somebody else's server.
    if ($weStartedIt) {
        $null = Invoke-Sd @('-stop')
    }
}

exit $result
