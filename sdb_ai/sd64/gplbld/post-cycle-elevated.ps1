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
#
# ---------------------------------------------------------------------------
# ARGUMENTS ARE SPLATTED FROM A HASHTABLE, AND THE FIRST VERSION OF THIS FILE
# GOT IT WRONG IN A WAY THAT LOOKED LIKE AN SD BUG.  19 Aug 2026.  It held
# Args = @('-Prefix', $TierPrefix) and invoked "& $path @($s.Args)".
#
#   @(...) IS AN ARRAY SUBEXPRESSION, NOT SPLATTING.  Splatting is @name on a
#   VARIABLE.  So the whole array was passed as ONE positional argument and
#   stringified: verify-tiers.ps1 ran with $Prefix = "-Prefix sdtierg", and
#   tried to create SD accounts called "-Prefix sdtierg1".
#
#   AND ARRAY SPLATTING WOULD NOT HAVE FIXED IT EITHER.  "& $path @a" on an
#   array passes the elements POSITIONALLY - "-Prefix" binds to $Prefix as a
#   positional value, not as a parameter name, giving $Prefix = "-Prefix".
#   Only a HASHTABLE splat binds by name.  Measured, all three forms:
#       & $p @($a)               ->  Prefix = [-Prefix sdtierg]
#       & $p @a   (array)        ->  Prefix = [-Prefix]
#       & $p @h   (hashtable)    ->  Prefix = [sdtierg]      <- the correct one
#
# WHAT IT COST, and it is the reason this comment is long: verify-tiers.ps1
# reported all three tiers holding 429 VOC records with none of the 18
# capabilities withheld and all 10 administration verbs present - which reads
# exactly like the silent tier-filter failure PROJECT_STATUS.md 5.12 warns
# about, the one where a STANDARD account quietly gets the full VOC.  It was
# nothing of the sort.  CREATE.ACCOUNT had refused the malformed name, LOGTO
# had left the session in SDSYS, and 429 is simply how many records
# voc_template holds.  THE PARAMETER NAMES ARE VALIDATED BELOW so that a
# repeat stops here instead of three sections later wearing a disguise.

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

# An account name is an OS user name.  Anything with a space or a leading dash
# is a mangled argument, not a name - see the header.
foreach ($p in @(@{ N = 'TierPrefix'; V = $TierPrefix }, @{ N = 'Account'; V = $Account })) {
    if ($p.V -notmatch '^[A-Za-z][A-Za-z0-9_.]*$') {
        Write-Output ("post-cycle-elevated: -{0} is '{1}', which is not a usable account name." -f $p.N, $p.V)
        Write-Output '  Letters, digits, dot and underscore only, starting with a letter.'
        exit 2
    }
}

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$summary = Join-Path $logDir ('post-cycle-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

# Name => hashtable of parameters, splatted by NAME.  An empty hashtable means
# "no arguments", which splats correctly too.
$steps = @(
    @{ Name = 'verify-fold.ps1';          P = @{} },
    @{ Name = 'verify-createaccount.ps1'; P = @{ Account = $Account } },
    @{ Name = 'verify-tiers.ps1';         P = @{ Prefix  = $TierPrefix } }
)

$lines = @()
foreach ($s in $steps) {
    $path = Join-Path $PSScriptRoot $s.Name
    $shown = ($s.P.GetEnumerator() | ForEach-Object { '-' + $_.Key + ' ' + $_.Value }) -join ' '
    Write-Output ''
    Write-Output ('===== ' + $s.Name + ' ' + $shown + ' =====')
    $splat = $s.P
    & $path @splat
    $code = $LASTEXITCODE
    $lines += ('{0,-28} {1,-22} exit {2}' -f $s.Name, $shown, $code)
}

Write-Output ''
Write-Output '===== post-cycle summary ====='
$lines | ForEach-Object { Write-Output $_ }
$lines | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ''
Write-Output ("summary written to: " + $summary)
