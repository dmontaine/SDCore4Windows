# post-cycle-elevated.ps1 - the three ELEVATED verifiers, in one command
#
#   Run from an ELEVATED PowerShell.  Nothing else here needs elevation.
#
# WHY IT EXISTS.  19 Aug 2026: an agent shell cannot raise a UAC prompt -
# Start-Process -Verb RunAs returns "The operation was canceled by the user"
# without ever showing one, because a detached process has no desktop to
# display consent on.  So every elevated step has to be started by a human,
# and three separate hand-run commands is exactly the shape cycle.ps1 was
# written to get rid of (CLAUDE.md, "Do not hand-run the steps").
#
# It runs each verifier WITHOUT -Keep, so each removes what it made and the
# tree is left clean.  -Keep is the stronger run - it leaves the accounts to be
# read back independently - but it then owes a -Cleanup and three interactive
# DELETE.ACCOUNTs, and verify-createaccount.ps1 already reads its account's
# directory back case-exactly before removing it.
#
# The summary is written to a file as well as the screen, because an elevated
# window does not paste its output back into the session that asked for it.

param(
    [string]$TierPrefix = 'sdtierg',   # MUST be one nobody has used - see PROJECT_STATUS.md
    [string]$Account    = 'sdacct14'   # likewise; sdacct1..13 are spent
)

$ErrorActionPreference = 'Continue'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'post-cycle-elevated: this needs an ELEVATED PowerShell.'
    exit 2
}

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$summary = Join-Path $logDir ('post-cycle-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

$steps = @(
    @{ Name = 'verify-fold.ps1';          Args = @() },
    @{ Name = 'verify-createaccount.ps1'; Args = @('-Account', $Account) },
    @{ Name = 'verify-tiers.ps1';         Args = @('-Prefix', $TierPrefix) }
)

$lines = @()
foreach ($s in $steps) {
    $path = Join-Path $PSScriptRoot $s.Name
    Write-Output ''
    Write-Output ('===== ' + $s.Name + ' ' + ($s.Args -join ' ') + ' =====')
    & $path @($s.Args)
    $code = $LASTEXITCODE
    $lines += ('{0,-28} exit {1}' -f ($s.Name + ' ' + ($s.Args -join ' ')), $code)
}

Write-Output ''
Write-Output '===== post-cycle summary ====='
$lines | ForEach-Object { Write-Output $_ }
$lines | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ''
Write-Output ("summary written to: " + $summary)
