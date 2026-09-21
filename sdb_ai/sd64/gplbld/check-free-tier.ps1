<#
.SYNOPSIS
    Runs every free guard - each gplbld/test-*-units.ps1 or .py - one process apiece.
    No install, no elevation, no run number.  THE LIST IS THE DIRECTORY.

.DESCRIPTION
    21 Sep 26, owner: cut the bookkeeping.  CLAUDE.md used to name the free tier by
    hand (52 names and a count word that had to be re-derived), so every new guard
    was a second edit and a place to be wrong.  Now a guard is free by being a
    test-*-units.* file: writing one needs no registration anywhere.

    THE ONE DECLARED EXCEPTION is in $NeedsBuild below, with its reason.  A test that
    cannot run on a clean checkout belongs there, not skipped silently: a test that
    passed because nothing was there to drive is a vacuous pass.

    EXIT CODES
      0  every guard exited 0 (or 2, listed below - see next line)
      1  at least one guard failed
      2  the guard list did not resolve, or the directory is not gplbld
    A guard that itself exits 2 is reported as NO TREE, not as a failure: it read
    something a fresh checkout or a stale shell cannot (test-sysmsg-units needs the
    installed messages; test-tlsrelay-units needs bin\).  The summary counts them
    apart, so a run of 51 passes and one NO TREE is not read as 52 passes.

    -List   print the resolved guard list and exit 0.
    -Only   run just the named guards (names may omit the extension).
#>
param(
    [switch]$List,
    [string[]]$Only = @()
)
# 'Continue', NOT 'Stop': in Windows PowerShell 5.1 a native command's stderr line
# becomes a terminating error under Stop once its output is redirected, so one
# Python warning would abort the whole run.  Every result here is checked by hand.
$ErrorActionPreference = 'Continue'
$G = $PSScriptRoot

$NeedsBuild = @{
    'test-sdpy-units.ps1' = 'drives sdpy.exe, which build-sdpy.ps1 builds; exits 2 on a clean checkout'
}

$all = @(Get-ChildItem -LiteralPath $G -File |
         Where-Object { $_.Name -match '^test-.*-units\.(ps1|py)$' } | Sort-Object Name)
$tests = @($all | Where-Object { -not $NeedsBuild.ContainsKey($_.Name) })
if ($tests.Count -lt 40) {
    Write-Host ("REFUSED: only {0} test-*-units files under {1}; expected well over 40." -f $tests.Count, $G)
    exit 2
}
if ($Only.Count -gt 0) {
    $want = @($Only | ForEach-Object { $_ -replace '\.(ps1|py)$', '' })
    $unknown = @($want | Where-Object { $n = $_; -not ($tests | Where-Object { ($_.BaseName) -eq $n }) })
    if ($unknown.Count -gt 0) {
        Write-Host ('REFUSED: no such guard: ' + ($unknown -join ', '))
        exit 2
    }
    $tests = @($tests | Where-Object { $want -contains $_.BaseName })
}
Write-Host ("free guards: {0}   (excluded by declaration: {1})" -f $tests.Count, (($NeedsBuild.Keys) -join ', '))
if ($List) { $tests | ForEach-Object { $_.Name }; exit 0 }

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $env:LOCALAPPDATA ('SD-verify\free-' + $stamp)
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Write-Host ("logs: {0}" -f $logDir)

$ok = 0; $noTree = @(); $fail = @()
$whole = [Diagnostics.Stopwatch]::StartNew()
foreach ($t in $tests) {
    $log = Join-Path $logDir ($t.Name + '.log')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if ($t.Extension -eq '.py') { & python $t.FullName *> $log } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $t.FullName *> $log
    }
    $rc = $LASTEXITCODE
    $sw.Stop()
    $bytes = (Get-Item -LiteralPath $log).Length
    $verdict = if ($rc -eq 0) { 'ok' } elseif ($rc -eq 2) { 'NO TREE' } else { 'FAIL' }
    # A guard that exits 0 and printed nothing measured nothing.
    if ($rc -eq 0 -and $bytes -eq 0) { $verdict = 'FAIL (exit 0, no output)'; $rc = 1 }
    Write-Host ('{0,-8} {1,-40} {2,5:N1}s  exit {3}' -f $verdict, $t.Name, $sw.Elapsed.TotalSeconds, $rc)
    if ($verdict -eq 'ok') { $ok++ } elseif ($verdict -eq 'NO TREE') { $noTree += $t.Name } else { $fail += $t.Name }
}
$whole.Stop()
Write-Host ''
Write-Host ('SUMMARY: {0} passed, {1} no-tree, {2} failed, of {3}, in {4:N0}s' -f
    $ok, $noTree.Count, $fail.Count, $tests.Count, $whole.Elapsed.TotalSeconds)
if ($noTree.Count -gt 0) { Write-Host ('  no tree (exit 2, not a failure): ' + ($noTree -join ', ')) }
if ($fail.Count -gt 0)   { Write-Host ('  FAILED: ' + ($fail -join ', ')); exit 1 }
exit 0
