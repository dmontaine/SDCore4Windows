# set-start-default.ps1 - where new sessions start, as the installer was told (the home/prompt question).
#
#   powershell -ExecutionPolicy Bypass -File set-start-default.ps1 -AppDir <app> -DataDir <data>
#
# 10 Nov 2026, RELEASE_1.1 210: the Windows half of Linux e0e38810 (installsdcore.sh START-ASK / START-SET; owner, 3 Nov 2026,
# "the home/prompt question").  The home screen is the delivered start and needs nothing: an absent sdsys\start.default means the
# home screen.  sd.iss runs this script only when the person chose the command prompt (the task "startprompt"), and only on a fresh
# install - an upgrade skips the tasks page and keeps the start.default the site already has, which is Linux's "offers what the
# site had".  The answer is applied with SD's own verb, SET.START.DEFAULT TERMINAL, from an -internal session (as Linux runs
# "sd -internal set.start.default terminal"), so the audit line is the verb's.
#
# THE VERDICT IS DRAWN FROM THE FILE THE VERB WRITES, NOT FROM ANY EXIT CODE (the instrument rule): sdsys\start.default's first line
# must be exactly 'terminal' afterwards.  Exit codes, each reported differently by sd.iss:
#   0  start.default says terminal
#   3  SD would not start, so the verb was never run
#   1  anything else (the verb refused, the file says something else, no sd.exe)

[CmdletBinding()]
param(
    [string] $AppDir = '',
    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Stop'

# The same PowerShell 7 module-path guard as every installer script (RELEASE_1.1 110, 111; test-psmodulepath-units.ps1).
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"

$LogFile = Join-Path $DataDir 'set-start-default.log'
function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

# What the file says now, the first line trimmed and lower case; '' when there is no file.
function Get-StartDefault([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $first = @(Get-Content -LiteralPath $Path -TotalCount 1)
    if ($first.Count -eq 0) { return '' }
    return $first[0].Trim().ToLower()
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }
$sd = Join-Path $AppDir 'usr\bin\sd.exe'
$startFile = Join-Path $DataDir 'sdsys\start.default'
Say "=== set-start-default AppDir=$AppDir, DataDir=$DataDir, file=$startFile, before='$(Get-StartDefault $startFile)'"
if (-not (Test-Path $sd)) { Say "set-start-default: no sd.exe at $sd"; exit 1 }

. (Join-Path $PSScriptRoot 'internal-marker.ps1')

function Invoke-Sd {
    param([string[]] $SdArgs)
    # NEVER "Start-Process -Wait": sdwind inherits sd's handles and outlives it (attach-account.ps1 Invoke-Sd).  Waiting on the PROCESS works.
    $out = Join-Path $env:TEMP ("sd-start-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-start-err-$PID.txt")
    $marked = $false
    if (@($SdArgs).Count -gt 0 -and $SdArgs[0] -ieq '-internal') {
        $marked = Set-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') -Writer 'set-start-default'
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
    return [pscustomobject]@{ Code = $p.ExitCode; Text = "$text".Trim() }
}

function Test-SdRunning {
    # Same test as attach-account.ps1 and make-shared.ps1: an sdwind beside sd-solo.exe is Solo's server, not this product's.
    return $null -ne ((Get-Process sdwind -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'sdwind' -or -not ($_.Path -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $_.Path) 'sd-solo.exe'))) }))
}

if ((Get-StartDefault $startFile) -eq 'terminal') {
    Say 'set-start-default: start.default already says terminal; nothing to do'
    exit 0
}

$weStartedIt = $false
if (-not (Test-SdRunning)) {
    $r = Invoke-Sd @('-start')
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not (Test-SdRunning)) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-SdRunning)) {
        Say 'set-start-default: SD would not start, so SET.START.DEFAULT was not run'
        Say ('  sd -start exited {0}: {1}' -f $r.Code, $r.Text)
        exit 3
    }
    $weStartedIt = $true
}

$result = 1
try {
    $r = Invoke-Sd @('-internal', 'SET.START.DEFAULT', 'TERMINAL')
    Say "set-start-default: ran SET.START.DEFAULT TERMINAL (sd exit $($r.Code))"
    if ($r.Text) { Say $r.Text }
    $after = Get-StartDefault $startFile
    if ($after -eq 'terminal') {
        Say "set-start-default: start.default says terminal: new sessions start at the command prompt"
        $result = 0
    } else {
        Say "set-start-default: start.default says '$after', not terminal: new sessions still start at the home screen"
        $result = 1
    }
}
finally {
    if ($weStartedIt) { $null = Invoke-Sd @('-stop') }
}
exit $result
