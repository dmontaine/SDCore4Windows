# verify-nonet.ps1 - prove SDNet is gone and that nothing that shares its
# neighbourhood went with it.  PROJECT_STATUS.md section 8.
#
#   powershell -File verify-nonet.ps1
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# WHAT WAS REMOVED, 18 Aug 2026, on the owner's instruction.  SD could open a
# file held on another SD server by putting "server;file" in a VOC entry:
# op_dio1.c split the name on the semicolon and called net_open(), which read
# the server's user name and password from sd.conf - obscured with a letter
# substitution, not encrypted - and connected on port 4245.  There was no way to
# switch it off; the NETFILES parameter was read at startup and consulted by
# nothing.  qmclient and the API are a different mechanism, are unchanged, and
# stay protected by requiring an ssh tunnel.
#
# THE CONTROLS ARE THE POINT OF THIS SCRIPT.  Proving three verbs are absent is
# easy and proves little - a botched removal that took APISRVR or the catalogue
# with it would pass every "is it gone?" check ever written.  So the file layer
# is asked what SURVIVED as well as what went.
#
# WHY THE SEMICOLON CASE IS NOT EXERCISED HERE, deliberately.  Reaching it needs
# a VOC F-pointer whose path contains a ";", and SDSYS's VOC is a DYNAMIC file -
# a directory of %0/%1 buckets - so a record cannot be planted from PowerShell,
# and writing one through SD needs ED, which is interactive and cannot be driven
# down a pipe (see verify-fold.ps1's header for what that costs).  The branch
# that read the semicolon is deleted outright rather than disabled, so what is
# checked here is that the programs and catalogue entries behind it are gone and
# that ordinary file access is untouched.
#
# UNLOCK RIDES ALONG because it shipped in the same cycle, not because it is
# related.  Section 3 says so.

param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-nonet-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys = Join-Path $env:ProgramData 'SD\sdsys'
$gcat  = Join-Path $sdsys 'gcat'
$bpout = Join-Path $sdsys 'gpl.bp.out'

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

# Bounded - see verify-fold.ps1 for why, and for what a timed-out call leaves
# behind.  Nothing here should ever prompt; the timeout is the safety net.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 45) {
    # LOGIN re-inits terminal geometry on every account switch (LOGIN:201-209),
    # so the initial TERM below is wiped by any LOGTO in $commands.  Full
    # write-up in verify-tiers.ps1's Invoke-SD.
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += "*** SD did not finish in $TimeoutSec s - Stop-Process the sdwind PID."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-nonet: refusing - see above'
    exit 2
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-nonet: this needs an ELEVATED PowerShell - it works in SDSYS.'
    exit 2
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 1. The compiled programs are gone, and the API server is not =========='

# gcat and GPL.BP.OUT are directory files, so an entry is a file on disk and its
# presence is a fact rather than a parsed screen.
foreach ($n in @('DELSRVR', 'SETSRVR', 'LISTSRVR')) {
    Note "gcat has no `$$n"      $false (Test-Path -LiteralPath (Join-Path $gcat ('$' + $n)))
    Note "GPL.BP.OUT has no $n"  $false (Test-Path -LiteralPath (Join-Path $bpout $n))
}

# THE CONTROL.  APISRVR is the API's own server and lives beside the three that
# went; if the removal had been done by pattern rather than by name it would
# have taken this too, and every check above would still pass.
Note 'gcat still has $APISRVR'     $true (Test-Path -LiteralPath (Join-Path $gcat '$APISRVR'))
Note 'gpl.bp.out still has APISRVR' $true (Test-Path -LiteralPath (Join-Path $bpout 'APISRVR'))

# And the catalogue as a whole is still populated - a removal that emptied it
# would also pass "is DELSRVR absent?".
$gcatCount = @(Get-ChildItem -LiteralPath $gcat -File -ErrorAction SilentlyContinue).Count
Write-Output ("  gcat holds $gcatCount entries")
Note 'gcat is still populated (>100)' $true ($gcatCount -gt 100)

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 2. The verbs are gone from SDSYS, and ordinary files still open ======='

# LIST VOC reports a missing record as  'NAME' not found
$out = Invoke-SD @("LIST VOC 'SET.SERVER' 'DELETE.SERVER' 'LIST.SERVERS' 'UNLOCK'")
foreach ($v in @('SET.SERVER', 'DELETE.SERVER', 'LIST.SERVERS')) {
    Note "$v is not in the VOC" $true ($out -match ("'" + [regex]::Escape($v) + "' not found"))
}

# THE CONTROL for the same command: UNLOCK was in the same VOC and must remain.
Note 'UNLOCK is still in the VOC' $false ($out -match "'UNLOCK' not found")

# And file access itself still works, which is what the removed code sat in the
# middle of - op_dio1's open path.
$out = Invoke-SD @('COUNT VOC')
Note 'COUNT VOC still works' $true ($out -match 'record\(s\) counted')

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 3. UNLOCK, which shipped in the same cycle and is unrelated ==========='

# Its VOC entry held the DESCRIPTION where the type code belongs, so SD did not
# see it as a verb at all.  Field 1 must now be V.
# CT prints each field, usually with a line number ("0001 V"), but the width of
# that number is not worth depending on - match a line that is a bare V with an
# optional leading number.  The raw output is printed either way, so a miss is
# diagnosable rather than mysterious.
# 22 Aug 26 - THE COLON WAS MISSING, so this could never match and had been
# failing every run since it was written.  The comment above says CT prints
# "0001 V"; this SD prints "1: V", with a colon, which the pattern did not
# allow - it wanted digits, whitespace, V.  Found on the first run of this file
# under post-cycle-elevated.ps1: the raw output printed directly beneath the
# FAIL said "1: V" in as many words, which is the whole reason the script
# prints it.  verify-lcnames.ps1:767 makes the same check against COPYP and had
# the colon all along, so the two now agree.
#
# The digit is left optional rather than pinned to 1: the field number is what
# it is, and this check is about the TYPE CODE, not about which line it lands on.
$out = Invoke-SD @('CT VOC UNLOCK')
Note 'CT VOC UNLOCK shows a V type code' $true ($out -match '(?m)^\s*\d*:?\s*V\s*$')
Note 'and no longer the description text' $false ($out -match 'Verb to unlock records')
Write-Output '  --- CT VOC UNLOCK said: ---'
Write-Output $out

# Behaviour, relative rather than against a hardcoded message: an unknown verb
# and UNLOCK must not produce the same answer.
$unknown = Invoke-SD @('ZZNOSUCHVERB')
$unlock  = Invoke-SD @('UNLOCK')
Note 'UNLOCK answers differently from an unknown verb' $false ($unlock -eq $unknown)

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== Summary =============================================================='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
Write-Output ("  {0} of {1} checks passed" -f $passed, $results.Count)

try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 } else { exit 0 }
