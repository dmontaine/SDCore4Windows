# load-help.ps1 - load the context help the [?] buttons show, at install and at upgrade.
#
#   powershell -ExecutionPolicy Bypass -File load-help.ps1 -AppDir <app> -DataDir <data>
#
# 26 Oct 2026, RELEASE_1.1 184.  The Windows half of Linux's "Loading the context help into the shared account" (installsdcore.sh,
# SHARED-CONTENT): LOAD.HELP reads sdsys\helptext (one file to a setting) and writes the records of the file context.help in the
# shared account.  It is idempotent: the shipped records are replaced and any the administrator added are kept, so an upgrade
# refreshes the help and loses nothing.  Until this release neither the text nor this step shipped, so every [?] box was empty.
#
# Called by sd.iss right after make-shared.ps1.  NEVER STOPS THE INSTALL: the exit code says what happened and sd.iss only logs it.
#   0  loaded (the success line LOAD.HELP prints is in the output)
#   2  nothing to load into: there is no shared account, or sdsys\helptext is empty
#   3  SD would not start
#   1  anything else
#
# THE VERDICT IS DRAWN FROM WHAT LOAD.HELP SAYS ON ITS SUCCESS PATH (messages 12844), never from its exit code or from the words it
# also prints on failure (12840-12843): the verb's exit code is not trustworthy (sd exits 0 when a verb refuses), and the file name
# context.help appears in the failure text as well.

[CmdletBinding()]
param(
    [string] $AppDir = '',
    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Continue'
$LogFile = Join-Path $DataDir 'load-help.log'
function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }
Say "=== load-help AppDir=$AppDir, DataDir=$DataDir  $(Get-Date -Format 's')"
$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) { Say "load-help: no sd.exe at $sd"; exit 1 }
$helpDir = Join-Path $DataDir 'sdsys\helptext'
$helpCount = @(Get-ChildItem -LiteralPath $helpDir -File -ErrorAction SilentlyContinue).Count
Say "load-help: $helpDir holds $helpCount file(s)"
if ($helpCount -eq 0) { Say 'load-help: there is no help text to load'; exit 2 }

. (Join-Path $PSScriptRoot 'internal-marker.ps1')

function Invoke-Sd {
    param([string[]] $SdArgs)
    $out = Join-Path $env:TEMP ("sd-help-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-help-err-$PID.txt")
    $marked = $false
    if (@($SdArgs).Count -gt 0 -and $SdArgs[0] -ieq '-internal') {
        $marked = Set-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') -Writer 'load-help'
    }
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    $exited = $p.WaitForExit(120000)
    if ($marked) { $null = Remove-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') }
    $text = ''
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) { $text += (Get-Content $f -Raw); Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    if (-not $exited) { return [pscustomobject]@{ Code = 1; Text = "sd $SdArgs did not finish within two minutes" } }
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
        Say 'load-help: SD would not start, so the help was not loaded'
        Say ('  sd -start exited {0}: {1}' -f $r.Code, $r.Text)
        exit 3
    }
    $weStartedIt = $true
}

$result = 1
try {
    $r = Invoke-Sd @('-internal', 'LOAD.HELP')
    if ($r.Text) { Say $r.Text }
    $ok   = $r.Text -match 'Context help in the shared account: \d+ new, \d+ changed, \d+ already current'
    $none = $r.Text -match 'There is no shared account' -or $r.Text -match 'help text directory .* is missing or empty'
    if ($ok -and -not $none) { Say 'load-help: the context help is loaded'; $result = 0 }
    elseif ($none)           { Say 'load-help: nothing to load into (no shared account, or no help text)'; $result = 2 }
    else                     { Say ('load-help: LOAD.HELP did not report success (exit {0})' -f $r.Code); $result = 1 }
}
finally {
    if ($weStartedIt) { $null = Invoke-Sd @('-stop') }
}
exit $result
