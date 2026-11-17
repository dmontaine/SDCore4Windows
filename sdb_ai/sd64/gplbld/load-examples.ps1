# load-examples.ps1 - put the example programs into every account's examples.bp, at install and at upgrade.
#
#   powershell -ExecutionPolicy Bypass -File load-examples.ps1 -AppDir <app> -DataDir <data>
#
# 16 Nov 2026, from Linux cc7e41c6 (S.261).  The Windows half of Linux's EXAMPLES block (installsdcore.sh, after SHARED-CONTENT): LOAD.EXAMPLES
# reads sdsys\examples (one file to a program) and gives every registered account in service its own examples.bp, compiled.  It is
# idempotent: the shipped programs are replaced and any other program in the file is kept, so an upgrade refreshes every kept account and
# loses nothing.  Made from load-help.ps1.
#
# Called by sd.iss after SharedDocs.  NEVER STOPS THE INSTALL: the exit code says what happened and sd.iss puts one line in the closing box
# only for 1 and 3.
#   0  loaded (the success line LOAD.EXAMPLES prints, message 15124, names one account or more)
#   2  nothing to load: sdsys\examples is empty
#   3  SD would not start
#   1  anything else
#
# THE VERDICT IS DRAWN FROM WHAT LOAD.EXAMPLES SAYS ON ITS SUCCESS PATH (message 15124 with a count of 1 or more), never from its exit code
# (sd exits 0 when a verb refuses) or from the words "examples.bp", which its failure messages (15123) carry as well.  A program that did
# not compile is named in the log (15126) and does not change the code: the accounts were given the file.

[CmdletBinding()]
param(
    [string] $AppDir = '',
    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Continue'
$LogFile = Join-Path $DataDir 'load-examples.log'
function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }
Say "=== load-examples AppDir=$AppDir, DataDir=$DataDir  $(Get-Date -Format 's')"
$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) { Say "load-examples: no sd.exe at $sd"; exit 1 }
$exDir = Join-Path $DataDir 'sdsys\examples'
$exCount = @(Get-ChildItem -LiteralPath $exDir -File -ErrorAction SilentlyContinue).Count
Say "load-examples: $exDir holds $exCount file(s)"
if ($exCount -eq 0) { Say 'load-examples: there are no example programs to load'; exit 2 }

. (Join-Path $PSScriptRoot 'internal-marker.ps1')

function Invoke-Sd {
    param([string[]] $SdArgs)
    $out = Join-Path $env:TEMP ("sd-examples-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-examples-err-$PID.txt")
    $marked = $false
    if (@($SdArgs).Count -gt 0 -and $SdArgs[0] -ieq '-internal') {
        $marked = Set-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') -Writer 'load-examples'
    }
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    # Every account compiles 28 programs on a first install: allow ten minutes, not load-help's two.
    $exited = $p.WaitForExit(600000)
    if ($marked) { $null = Remove-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') }
    $text = ''
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) { $text += (Get-Content $f -Raw); Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    if (-not $exited) { return [pscustomobject]@{ Code = 1; Text = "sd $SdArgs did not finish within ten minutes" } }
    return [pscustomobject]@{ Code = $p.ExitCode; Text = $text.Trim() }
}

function Test-SdRunning {
    # Same test as make-shared.ps1: an sdwind beside sd-solo.exe is Solo's server, not this product's.
    return $null -ne ((Get-Process sdwind -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'sdwind' -or -not ($_.Path -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $_.Path) 'sd-solo.exe'))) }))
}

$weStartedIt = $false
if (-not (Test-SdRunning)) {
    $r = Invoke-Sd @('-start')
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not (Test-SdRunning)) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-SdRunning)) {
        Say 'load-examples: SD would not start, so the example programs were not loaded'
        Say ('  sd -start exited {0}: {1}' -f $r.Code, $r.Text)
        exit 3
    }
    $weStartedIt = $true
}

$result = 1
try {
    Say 'load-examples: running LOAD.EXAMPLES (every account in service; up to a few minutes)'
    $r = Invoke-Sd @('-internal', 'LOAD.EXAMPLES')
    if ($r.Text) { Say $r.Text }
    $ok = $r.Text -match '(?m)^Example programs in examples\.bp of [1-9][0-9]* account\(s\)'
    if ($ok) { Say 'load-examples: the example programs are in the accounts'; $result = 0 }
    else     { Say ('load-examples: LOAD.EXAMPLES did not report success (exit {0})' -f $r.Code); $result = 1 }
}
finally {
    if ($weStartedIt) { $null = Invoke-Sd @('-stop') }
}
exit $result
