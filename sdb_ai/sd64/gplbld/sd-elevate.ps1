# sd-elevate.ps1 - the unelevated half of an SD administrator session
#
# Called by SD (GPL.BP/ELEVATE) in three modes:
#
#   -Start   launch the elevated helper.  THIS IS WHERE UAC PROMPTS.
#   -Run     hand a script to the helper and return its exit code
#   -Stop    tell the helper to exit
#
# Exit codes, chosen to match the convention !create_user and !os_group
# already use so callers need learn nothing new:
#
#   0  done
#   1  the operation failed
#   5  not elevated / elevation refused or unavailable
#   9  no helper is running for this user
#
# 29 Aug 26 - ONE HELPER PER USER, NOT PER SESSION.  PRE_RELEASE_FIXES 56.
# With an administrator elevated AT LOGIN, a helper scoped to one sd.exe meant
# ONE UAC PROMPT PER COMMAND; the pipe is now "sd-elev-<logname>" and a second
# session finds the first one's helper and asks for nothing.  Every mode sends
# its pid on PING so the helper knows who is using it, and -Stop deregisters
# one session rather than stopping the helper others still need.  The DACL is
# unchanged and is what keeps users apart - a wider NAME is not a wider reach.
#
# PROJECT_STATUS.md 7 step 4.  Owner's decisions, 16 Aug 2026: elevation comes
# from entering SDSYS and nowhere else, and admins are highly trusted - this
# raises the floor rather than trying to constrain the machine's owner.
#
# WHY -Start CANNOT WORK OVER ssh, AND WHY THAT IS THE POINT.  UAC renders its
# consent dialog on the interactive desktop and an ssh session has none, so
# Start-Process -Verb RunAs fails there.  That keeps administrator work off ssh
# exactly as 5.6.2 requires, enforced by Windows rather than by a test in SD
# that could drift.  A remote-control tool (AnyDesk, RDP) works, but only if it
# is installed as a SERVICE - a per-user install cannot show the secure desktop
# and the operator sees a frozen screen.
#
# WHY -Run VERIFIES THE HELPER FIRST.  The reply to a request is an exit code,
# and an exit code from something that is not elevated would tell SD an account
# was created when nothing happened.  PING answers "ELEVATED" or the connection
# is not trusted.

param(
    [switch]$Start,
    [switch]$Run,
    [switch]$Stop,
    [Parameter(Mandatory = $true)][string]$PipeName,
    [int]$OwnerPid = 0,
    [string]$Script = '',
    [string]$LogFile = ''
)

$ErrorActionPreference = 'Stop'

# 16 Aug 26 - WHERE THE HELPER LOGS, AND WHY SD DOES NOT PASS IT.  Nothing in
# BASIC can name this file: the installed tree maps only /dev/shm, so "/" is
# C:\Program Files\SD and there is no POSIX path for the data tree at all.
# Deriving it here from %ProgramData% is how the INSTALLER names it too - its
# DataDir is {commonappdata}\SD - so the two cannot drift, and !elevate needs
# no change.
#
# ONLY IF IT ALREADY EXISTS, which is the load-bearing half.  The installer
# creates it through secure-log.ps1 with an ACL that keeps every SD user out.
# Creating it here instead would inherit the data tree's Modify for all of
# sdusers, and a log of privileged work that its own subjects can rewrite is
# worse than no log.  So: no file, no logging.
#
# WHY IT LOGS BY DEFAULT AT ALL.  Two defects on 16 Aug 2026 - the helper
# unable to run any script it was sent, and LIST.GRANTS refusing itself - were
# both diagnosed only because -LogFile was passed BY HAND during the
# investigation.  A user meeting either of them had nothing to look at.  The
# volume is a few lines per SDSYS entry.
#
# IT MUST NEVER LOG SCRIPT CONTENTS - only the path and the exit code, as the
# helper does.  !set_passwd travels this same path and its script carries a new
# Windows password in clear.
if ($LogFile -eq '') {
    $default = Join-Path $env:ProgramData 'SD\sd-elevate.log'
    if (Test-Path -LiteralPath $default) { $LogFile = $default }
}

function Send-Request([string]$message, [int]$timeoutMs = 10000) {
    # Returns the reply line, or $null if no helper answered.
    try {
        $c = New-Object System.IO.Pipes.NamedPipeClientStream(
            '.', $PipeName, 'InOut')
        $c.Connect($timeoutMs)
        $w = New-Object IO.StreamWriter($c)
        $w.AutoFlush = $true
        $r = New-Object IO.StreamReader($c)
        $w.WriteLine($message)
        $reply = $r.ReadLine()
        $c.Dispose()
        return $reply
    } catch {
        return $null
    }
}

function Test-Helper {
    # Short timeout: this asks "is one there", not "wait for one".
    #
    # 29 Aug 26 - AND IT REGISTERS THIS SESSION WHILE IT ASKS.  PRE_RELEASE 56
    # widened the helper from one-per-session to one-per-user, so a session
    # that finds an existing helper must tell it so - otherwise the helper
    # exits when whichever session happened to START it goes, and takes every
    # other session's privilege with it.  PING is the only message every mode
    # sends, which is why the registration rides on it rather than on a
    # message of its own.
    #
    # A BARE PING STILL WORKS and registers nothing, so a diagnostic probe of
    # "is something elevated on this pipe" does not extend the helper's life.
    $msg = 'PING'
    if ($OwnerPid -gt 0) { $msg = "PING $OwnerPid" }
    return ((Send-Request $msg 1500) -eq 'ELEVATED')
}

try {
    if ($Start) {
        # Already elevated - the installer's own account step, a bootstrap, or
        # an administrator who deliberately opened an elevated terminal.  There
        # is nothing to launch and nothing to prompt for, and saying so lets
        # !ps_script run the script itself as it always has.
        $elevated = ([Security.Principal.WindowsPrincipal](
            [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($elevated) { exit 0 }

        if (Test-Helper) { exit 0 }   # one is already serving this session

        if ($OwnerPid -le 0) { exit 1 }

        $helper = Join-Path $PSScriptRoot 'sd-elevate-helper.ps1'
        if (-not (Test-Path -LiteralPath $helper)) { exit 1 }

        $args = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                  '-File', "`"$helper`"", '-PipeName', $PipeName,
                  '-OwnerPid', $OwnerPid)
        if ($LogFile -ne '') { $args += @('-LogFile', "`"$LogFile`"") }

        try {
            Start-Process powershell -Verb RunAs -WindowStyle Hidden `
                -ArgumentList $args | Out-Null
        } catch {
            # Declined at the UAC prompt, or no interactive desktop to show it
            # on.  Both are "not elevated", which is what the caller acts on.
            exit 5
        }

        # Wait for it to come up.  It has a UAC prompt to get past first, so
        # this is generous; the loop exits as soon as PING is answered.
        for ($i = 0; $i -lt 40; $i++) {
            if (Test-Helper) { exit 0 }
            Start-Sleep -Milliseconds 500
        }
        exit 5
    }

    if ($Run) {
        if ($Script -eq '') { exit 1 }
        if (-not (Test-Helper)) { exit 9 }

        $reply = Send-Request $Script 300000
        if ($null -eq $reply) { exit 1 }

        $code = 0
        if ([int]::TryParse($reply, [ref]$code)) { exit $code }
        exit 1
    }

    if ($Stop) {
        if (-not (Test-Helper)) { exit 0 }   # nothing to stop is success

        # 29 Aug 26 - STOP DEREGISTERS THIS SESSION; THE HELPER DECIDES WHETHER
        # TO EXIT.  PRE_RELEASE 56 made the helper serve every session of one
        # user, so CPROC's elevate('STOP') on the way out of SDSYS must not be
        # able to take the privilege away from sessions still using it.  The
        # helper drops this pid and exits only when its last owner has gone.
        #
        # A BARE STOP still stops it outright, which is what a diagnostic or a
        # cleanup wants, and is what this sent before there was anything to
        # deregister.
        $msg = 'STOP'
        if ($OwnerPid -gt 0) { $msg = "STOP $OwnerPid" }
        Send-Request $msg 5000 | Out-Null
        exit 0
    }

    exit 1
}
catch {
    exit 1
}
