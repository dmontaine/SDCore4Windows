# probe-sdsysvoc.ps1 - does SDSYS's own VOC hold every record voc_template seeded it with?
#
#   powershell -ExecutionPolicy Bypass -File probe-sdsysvoc.ps1
#
# Exit 0 every seed record is in SDSYS's VOC, 1 one is missing, 2 could not run.
# ***ELEVATED*** - it runs in the SDSYS seat (sdsys-seat.ps1), which needs SDSYS signed in.
#
# 21 Sep 2026, RELEASE_1.1 99.  voc_template stopped being installed: stage.py copies it
# into the staged tree, BBPROC copies its records into SDSYS's dynamic VOC during the
# bootstrap, and stage.py then deletes the directory.  The installed system has no copy
# left to compare against, so this asks SDSYS's VOC itself, using the SOURCE directory
# as the list of what must be there.  READ-ONLY: only COUNT statements run.
#
# THE INSTRUMENT RULES: it prints the source path and the record count it is holding
# the VOC to; every id is checked with COUNT VOC WITH @ID = "<id>" and scored on the
# tool's own "1 record(s) counted" wording (never on the id it echoed); the number of
# result lines must equal the number of COUNT statements sent, or it refuses (a session
# that stopped part way must not score as a run of clean rows); and it refuses when it
# was given nothing to check.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say([string]$m) { Write-Host $m }
function Bail([int]$code, [string]$why) {
    Say ''
    if ($code -eq 0)     { Say "probe-sdsysvoc: PASSED - $why" }
    elseif ($code -eq 1) { Say "probe-sdsysvoc: FAILED - $why" }
    else                 { Say "probe-sdsysvoc: COULD NOT RUN - $why" }
    exit $code
}

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Bail 2 'this needs an ELEVATED PowerShell - the SDSYS seat registers a task.'
}

$seedDir = (Resolve-Path -LiteralPath (Join-Path $Gplbld '..\sdsys\voc_template')).Path
$seedFiles = @(Get-ChildItem -LiteralPath $seedDir -Force -File | ForEach-Object { $_.Name })
Say "probe-sdsysvoc: seed directory $seedDir"
Say "probe-sdsysvoc: seed records   $($seedFiles.Count)"
if ($seedFiles.Count -lt 300) {
    Bail 2 "the seed directory holds $($seedFiles.Count) record(s), expected 400 or more - nothing was checked."
}

# Only ids a COUNT statement can name plainly.  The rest are %-encoded file names
# (ids with characters NTFS cannot hold) or punctuation-only ids; they are counted and
# said, not silently dropped.
$plain = @($seedFiles | Where-Object { $_ -match '^[A-Za-z0-9._$]+$' })
$skipped = @($seedFiles | Where-Object { $_ -notmatch '^[A-Za-z0-9._$]+$' })
Say "probe-sdsysvoc: named checks   $($plain.Count) plain ids, $($skipped.Count) skipped (encoded or punctuation ids)"

& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }

. (Join-Path $Gplbld 'sdsys-seat.ps1')
Assert-SdSeat -Label 'probe-sdsysvoc'

# THE CONTROL: an id that is in no VOC must count 0, or "1 record(s) counted" proves
# nothing.  It goes LAST so the per-id indexing below is unchanged.
$controlId = 'zz-not-a-voc-record'
$commands = @('COUNT VOC') + @($plain | ForEach-Object { ('COUNT VOC WITH @ID = "{0}"' -f $_) }) +
            @(('COUNT VOC WITH @ID = "{0}"' -f $controlId))
Say "probe-sdsysvoc: sending $($commands.Count) COUNT statements through the seat"
$out = Invoke-SdSeatText -Commands $commands -TimeoutSec 240

$counts = @([regex]::Matches($out, '(?m)^(\d+) record\(s\) counted') | ForEach-Object { [int]$_.Groups[1].Value })
if ($counts.Count -ne $commands.Count) {
    Say $out
    Bail 2 "sent $($commands.Count) COUNT statements and read $($counts.Count) result line(s) - the session stopped part way; the raw output is above."
}

$total = $counts[0]
$controlCount = $counts[$counts.Count - 1]
Say ''
Say "control: COUNT VOC WITH @ID = `"$controlId`" answered $controlCount (must be 0)"
if ($controlCount -ne 0) {
    Bail 2 "the control id counted $controlCount, so this COUNT cannot tell a present record from an absent one - no row below means anything."
}
Say "SDSYS's VOC holds $total record(s); the seed directory held $($seedFiles.Count)."
$missing = @()
for ($i = 0; $i -lt $plain.Count; $i++) {
    $n = $counts[$i + 1]
    if ($n -ne 1) { $missing += ('{0} (counted {1})' -f $plain[$i], $n) }
}
Say "plain ids present: $($plain.Count - $missing.Count) of $($plain.Count)"
if ($missing.Count -gt 0) {
    foreach ($m in $missing) { Say "  MISSING  $m" }
    Bail 1 "$($missing.Count) seeded record(s) are not in SDSYS's VOC."
}
if ($total -lt $seedFiles.Count) {
    Bail 1 "SDSYS's VOC holds $total record(s), fewer than the $($seedFiles.Count) it was seeded with."
}
Bail 0 "every one of the $($plain.Count) plain seed ids is in SDSYS's VOC, and its total ($total) is not below the seed's $($seedFiles.Count); $($skipped.Count) encoded ids not individually checked."
