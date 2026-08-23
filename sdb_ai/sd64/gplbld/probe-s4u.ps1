# probe-s4u.ps1 - build and run probe-s4u.c AS THIS USER AND AS LocalSystem.
#
#   powershell -File probe-s4u.ps1              both runs, needs elevation
#   powershell -File probe-s4u.ps1 -SelfOnly    the caller's run only
#   powershell -File probe-s4u.ps1 -Account don a different target account
#
# Exit 0 the probe ran, 2 it could not be set up.  Like probe-keys.ps1 and
# probe-console.ps1 there is nothing here to pass or fail: it is an instrument,
# and a person reads what it prints.  It is not in VerifyInstall1 or
# VerifyInstall2 for that reason.
#
# WHAT IT IS FOR.  PROJECT_STATUS.md section 7 step 14, shape (b): SCRAM means
# the server never holds the password, so the only passwordless route to a
# user's token is S4U - and step 14 records that S4U yields an identification
# -level token, which CreateProcessAsUser will not take, unless the caller
# holds SeTcbPrivilege.  probe-s4u.c's header has the full reasoning.
#
# BOTH RUNS OR NEITHER, AND THAT IS THE WHOLE POINT OF THIS SCRIPT.
#
# The question is what the SERVICE can do.  sdwind runs as LocalSystem, which
# holds SeTcbPrivilege; an elevated administrator does NOT hold it.  So:
#
#   the caller's run    is the CONTROL and is expected to FAIL
#   the LocalSystem run is the MEASUREMENT and is the one step 14 needs
#
# A LocalSystem success on its own would be indistinguishable from "every
# token works here and S4U had nothing to do with it".  The failing control
# beside it is what makes the reading mean something, which is the lesson
# probe-console.c paid for.
#
# THE LocalSystem RUN GOES THROUGH schtasks, NOT PsExec.  Nothing binary may
# be downloaded into this project (see .gitignore's header), and schtasks is
# already on the machine.  A scheduled task registered /RU SYSTEM, run once,
# then deleted - and because a task's output goes nowhere, the probe writes to
# a file which this script then prints.
#
# TWO POWERSHELL TRAPS PAID FOR HERE ON THE FIRST ELEVATED RUN, 23 Aug 2026.
# Both cost the whole measurement and neither announced itself.
#
# 1. `schtasks /Delete` FOR A TASK THAT IS NOT THERE KILLED THE SCRIPT.  The
#    tidy-up before /Create is meant to be a no-op on a clean machine, but a
#    native command writing to stderr under $ErrorActionPreference = 'Stop'
#    becomes a TERMINATING NativeCommandError in PowerShell 5.1 - and `2>$null`
#    does not help, it is the redirection itself that wraps each stderr line in
#    an ErrorRecord.  The script exited 1 immediately after printing RUN 2's
#    banner, with no error text anywhere, which reads exactly like the probe
#    finding nothing.  Every schtasks call now goes through Invoke-Schtasks.
#
# 2. `& $exe` LOST ABOUT TEN LINES OF THE PROBE'S OUTPUT.  Not reordered -
#    GONE, including the whole VERDICT block, while lines either side of it
#    survived.  PowerShell decodes a native program's stdout itself, and this
#    one writes unbuffered.  So the output is no longer captured that way:
#    BOTH runs now redirect to a file with cmd.exe and the file is printed.
#    The two halves being symmetric is worth something on its own - a paired
#    measurement should not have one half read through a different instrument.
#
# NOT INSTALLED AND NOT SHIPPED - it must be on assert-current.ps1's
# $neverShipped list, along with the source and the .exe, or it reports the
# tree stale because it exists.

param(
    [string]$Account = '',
    [switch]$SelfOnly
)

$ErrorActionPreference = 'Stop'

# Every schtasks call goes through here - see trap 1 in the header.  The
# exit code is what decides, and stderr is returned rather than thrown so a
# failure can be PRINTED instead of vanishing.
function Invoke-Schtasks {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out  = & schtasks.exe @Arguments 2>&1
        $code = $LASTEXITCODE
        return [pscustomobject]@{ Code = $code; Output = $out }
    } finally {
        $ErrorActionPreference = $saved
    }
}

# Run the probe with its output redirected BY cmd, then print the file - see
# trap 2 in the header.  Returns the probe's exit code.
function Invoke-Probe {
    param([string]$Exe, [string]$Target, [string]$OutFile)
    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force
    }
    $cmdline = '"{0}" {1} > "{2}" 2>&1' -f $Exe, $Target, $OutFile
    & cmd.exe /c $cmdline
    $code = $LASTEXITCODE
    if (Test-Path -LiteralPath $OutFile) {
        Get-Content -LiteralPath $OutFile | ForEach-Object { Write-Host $_ }
        Remove-Item -LiteralPath $OutFile -Force
    } else {
        Write-Host "probe-s4u: no output file at $OutFile"
    }
    return $code
}

# ---------------------------------------------------------------------------
# Build, with probe-console.ps1's PATH trap carried over verbatim.
# ---------------------------------------------------------------------------
$ccW = 'C:\msys64\usr\bin\gcc.exe'
if (-not (Test-Path -LiteralPath $ccW)) {
    Write-Host "probe-s4u: no MSYS2 compiler at $ccW"
    exit 2
}

$src = Join-Path $PSScriptRoot 'probe-s4u.c'
$exe = Join-Path $PSScriptRoot 'probe-s4u.exe'

# THE COMPILER'S OWN DIRECTORY MUST BE ON PATH, and this is not optional: gcc
# itself resolves fine by full path, but the subprograms it spawns - cc1.exe,
# in usr/lib/gcc/x86_64-pc-cygwin/... - find their DLLs through PATH, and
# without it the build dies with
#   "cc1.exe: error while loading shared libraries: ?: cannot open shared
#    object file"
# which names no file and reads like a broken toolchain.  probe-console.ps1
# carries the same note and the Makefile carries it for UCRT_BIN.
$saved = $env:PATH
$env:PATH = 'C:\msys64\usr\bin;' + $env:PATH
try {
    Write-Host 'probe-s4u: building with the MSYS2 compiler...'
    # The same warning flags sd itself is built with (Makefile, "sd:" target),
    # so a warning here is a warning that would show up in the real build.
    # -lsecur32 carries LsaLogonUser and LsaRegisterLogonProcess; the token
    # and SID calls are in advapi32.
    & $ccW -std=gnu17 -Wall -Wformat=2 -Wno-format-nonliteral -O1 `
           -o $exe $src -lsecur32 -ladvapi32
    if ($LASTEXITCODE -ne 0) {
        Write-Host "probe-s4u: build failed (exit $LASTEXITCODE)"
        exit 2
    }
} finally {
    $env:PATH = $saved
}

# ---------------------------------------------------------------------------
# The target account.
#
# DEFAULTS TO WHOEVER IS RUNNING THIS, and that default is load-bearing for
# the LocalSystem run: a scheduled task running as SYSTEM would otherwise
# default to SYSTEM itself, which is not a measurement of anything - S4U for
# the account you already are proves nothing about standing in someone else's
# shoes.  So the name is resolved HERE, in the caller's session, and passed
# down.
# ---------------------------------------------------------------------------
if ($Account -eq '') {
    $Account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
}
Write-Host "probe-s4u: target account $Account"

$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr  = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------------------------
# Run 1 - the caller.  The control.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '==========================================================='
Write-Host " RUN 1 of 2 - as the caller ($($id.Name))"
if ($elevated) { Write-Host ' This token IS elevated.' }
else           { Write-Host ' This token is NOT elevated.' }
Write-Host ' EXPECTED TO FAIL.  It is the control, not the measurement.'
Write-Host '==========================================================='
$selfCode = Invoke-Probe -Exe $exe -Target $Account `
                        -OutFile (Join-Path $env:TEMP ('probe-s4u-self-{0}.txt' -f $PID))
Write-Host ''
Write-Host "probe-s4u: run 1 exit $selfCode"

if ($SelfOnly) {
    Write-Host ''
    Write-Host 'probe-s4u: -SelfOnly, so the LocalSystem run was skipped.'
    Write-Host 'THE CONTROL ALONE DECIDES NOTHING - step 14 needs the other half.'
    exit $selfCode
}

if (-not $elevated) {
    Write-Host ''
    Write-Host 'probe-s4u: not elevated, so the LocalSystem run cannot be set up.'
    Write-Host 'Registering a task to run as SYSTEM needs an administrator.'
    Write-Host 'THE CONTROL ALONE DECIDES NOTHING - re-run this elevated.'
    exit 2
}

# ---------------------------------------------------------------------------
# Run 2 - LocalSystem.  The measurement.
#
# schtasks and not Register-ScheduledTask: the latter is a module that has to
# be present, this is a command that always is, and the whole run is three
# calls.  /RU SYSTEM with no /RP is what makes it LocalSystem.
#
# THE OUTPUT FILE MUST BE SOMEWHERE SYSTEM CAN WRITE, which the caller's own
# temp directory is NOT if the caller is not an administrator by default -
# C:\Windows\Temp is writable by SYSTEM and readable here, and it is where a
# service would put such a thing anyway.
# ---------------------------------------------------------------------------
$taskName = 'SDProbeS4U'
$outFile  = Join-Path $env:SystemRoot ('Temp\probe-s4u-{0}.txt' -f $PID)

# cmd.exe wraps it only to redirect: schtasks runs one program and gives it no
# way to redirect on its own.  The quoting below is what schtasks wants - the
# whole /TR value in one pair of quotes, inner quotes doubled - and it is the
# part that breaks first if this is edited.
$inner = '"{0}" {1} > "{2}" 2>&1' -f $exe, $Account, $outFile
$tr    = 'cmd.exe /c {0}' -f $inner

if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force }

Write-Host ''
Write-Host '==========================================================='
Write-Host ' RUN 2 of 2 - as LocalSystem, the identity sdwind runs as'
Write-Host ' THIS IS THE MEASUREMENT.'
Write-Host '==========================================================='

# A task left over from an interrupted run would make /Create fail; delete
# first and ignore the "not found" that is the normal case.  THAT IGNORING IS
# WHAT TRAP 1 IN THE HEADER IS ABOUT - the not-found message goes to stderr,
# and read directly it terminates this script.
Invoke-Schtasks /Delete /TN $taskName /F | Out-Null

$created = Invoke-Schtasks /Create /TN $taskName /TR $tr /SC ONCE /ST 00:00 `
                           /RU SYSTEM /RL HIGHEST /F
if ($created.Code -ne 0) {
    Write-Host 'probe-s4u: could not register the SYSTEM task:'
    $created.Output | ForEach-Object { Write-Host "  $_" }
    exit 2
}

$started = Invoke-Schtasks /Run /TN $taskName
if ($started.Code -ne 0) {
    Write-Host 'probe-s4u: the SYSTEM task would not start:'
    $started.Output | ForEach-Object { Write-Host "  $_" }
    Invoke-Schtasks /Delete /TN $taskName /F | Out-Null
    exit 2
}

# /Run returns as soon as the task is STARTED, so the file is not there yet.
# Poll on the task's own state rather than on the file: a file that exists is
# not a file that is finished being written, and the probe takes a second or
# two because it waits on a child process of its own.
$deadline = (Get-Date).AddSeconds(90)
$running  = $true
while ($running -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $q = Invoke-Schtasks /Query /TN $taskName /FO LIST
    if ($q.Code -ne 0) { break }
    $status = ($q.Output | Where-Object { $_ -match '^Status:' }) -join ' '
    if ($status -notmatch 'Running') { $running = $false }
}

Invoke-Schtasks /Delete /TN $taskName /F | Out-Null

Write-Host ''
if (Test-Path -LiteralPath $outFile) {
    Get-Content -LiteralPath $outFile | ForEach-Object { Write-Host $_ }
    Remove-Item -LiteralPath $outFile -Force
} else {
    Write-Host 'probe-s4u: the SYSTEM run produced no output file.'
    Write-Host "Expected it at $outFile"
    Write-Host 'Nothing can be concluded from run 1 alone.'
    exit 2
}

Write-Host ''
Write-Host '==========================================================='
Write-Host ' READ THE TWO VERDICTS TOGETHER.'
Write-Host ' Run 1 (caller, no SeTcbPrivilege) is expected to be refused.'
Write-Host ' Run 2 (LocalSystem) is the answer to step 14 shape (b).'
Write-Host ' If BOTH succeeded, SeTcbPrivilege is not the discriminator and'
Write-Host ' the reason needs finding before either shape is chosen.'
Write-Host '==========================================================='
exit 0
