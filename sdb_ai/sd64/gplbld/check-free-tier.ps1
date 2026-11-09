<#
.SYNOPSIS
    Runs every free guard - each gplbld/test-*-units.ps1 or .py - one process apiece, several at a time.
    No install, no elevation, no run number.  THE LIST IS THE DIRECTORY.

.DESCRIPTION
    21 Sep 26, owner: cut the bookkeeping.  CLAUDE.md used to name the free tier by
    hand (52 names and a count word that had to be re-derived), so every new guard
    was a second edit and a place to be wrong.  Now a guard is free by being a
    test-*-units.* file: writing one needs no registration anywhere.

    THE ONE DECLARED EXCEPTION is in $NeedsBuild below, with its reason.  A test that
    cannot run on a clean checkout belongs there, not skipped silently: a test that
    passed because nothing was there to drive is a vacuous pass.

    9 Nov 26, owner: "have the suites been optimized for speed" (Linux cut its time by a third with
    --jobs).  -Jobs N runs N guards at once (default 8; -Jobs 1 is the old one-after-another run).  Measured on
    this machine, 105 guards: 102 s serial, 42 s at 4, 30 s at 8 (32 logical processors).  The
    free guards need no install, so they are independent of each other - EXCEPT that a guard which
    breaks a copy of a file must never touch the live one, or its neighbour reads the broken file
    (memory: mutant-control-vs-background-jobs).  So the run compares the working tree BEFORE and AFTER
    (git status and diff, when the folder is a git tree) and fails if they differ: a guard that left
    the tree changed, or changed it for a moment and put it back while another read it, shows up as a
    FAIL of the whole run, not as a mysterious red guard.  A guard that fails in a parallel run is not
    believed until it is run again with -Jobs 1 -Only <name>.

    EXIT CODES
      0  every guard exited 0 (or 2, listed below - see next line)
      1  at least one guard failed, or the tree changed during the run
      2  the guard list did not resolve, or the directory is not gplbld
    A guard that itself exits 2 is reported as NO TREE, not as a failure: it read
    something a fresh checkout or a stale shell cannot (test-sysmsg-units needs the
    installed messages; test-tlsrelay-units needs bin\).  The summary counts them
    apart, so a run of 51 passes and one NO TREE is not read as 52 passes.

    -List   print the resolved guard list and exit 0.
    -Only   run just the named guards (names may omit the extension).
    -Jobs   how many guards at once (1 to 16; default 8).
#>
param(
    [switch]$List,
    [string[]]$Only = @(),
    [ValidateRange(1, 16)][int]$Jobs = 8
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
Write-Host ("free guards: {0}   (excluded by declaration: {1})   at once: {2}" -f $tests.Count, (($NeedsBuild.Keys) -join ', '), $Jobs)
if ($List) { $tests | ForEach-Object { $_.Name }; exit 0 }

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $env:LOCALAPPDATA ('SD-verify\free-' + $stamp)
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Write-Host ("logs: {0}" -f $logDir)

# The tree as it is now: what git says is changed, and what the changes are.  Empty when this is not a git tree.
function Get-TreeState {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    $st = (& git -C $G status --porcelain 2>$null) -join "`n"
    $df = (& git -C $G diff 2>$null) -join "`n"
    return ($st + "`n--`n" + $df)
}
$treeBefore = Get-TreeState

$ok = 0; $noTree = @(); $fail = @()
$whole = [Diagnostics.Stopwatch]::StartNew()
$py = (Get-Command python -ErrorAction SilentlyContinue).Source

function Start-Guard($t) {
    $out = Join-Path $logDir ($t.Name + '.log')
    $err = Join-Path $logDir ($t.Name + '.err')
    if ($t.Extension -eq '.py') {
        $p = Start-Process -FilePath $py -ArgumentList @('"' + $t.FullName + '"') -NoNewWindow -PassThru `
             -RedirectStandardOutput $out -RedirectStandardError $err
    } else {
        $p = Start-Process -FilePath 'powershell.exe' -NoNewWindow -PassThru `
             -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $t.FullName + '"')) `
             -RedirectStandardOutput $out -RedirectStandardError $err
    }
    $null = $p.Handle      # PowerShell 5.1: ExitCode is only readable if the handle was taken while the process ran
    return [pscustomobject]@{ Test = $t; Proc = $p; Out = $out; Err = $err; Start = Get-Date }
}

function Finish-Guard($r) {
    $t = $r.Test
    $rc = $r.Proc.ExitCode
    $secs = ((Get-Date) - $r.Start).TotalSeconds
    # stdout and stderr were kept apart so that neither could cut the other; the log is both, as the serial run's was
    if (Test-Path -LiteralPath $r.Err) {
        $e = Get-Content -LiteralPath $r.Err -Raw -ErrorAction SilentlyContinue
        if ($e) { Add-Content -LiteralPath $r.Out -Value $e }
        Remove-Item -LiteralPath $r.Err -Force -ErrorAction SilentlyContinue
    }
    $bytes = (Get-Item -LiteralPath $r.Out).Length
    $verdict = if ($rc -eq 0) { 'ok' } elseif ($rc -eq 2) { 'NO TREE' } else { 'FAIL' }
    # A guard that exits 0 and printed nothing measured nothing.
    if ($rc -eq 0 -and $bytes -eq 0) { $verdict = 'FAIL (exit 0, no output)'; $rc = 1 }
    Write-Host ('{0,-8} {1,-40} {2,5:N1}s  exit {3}' -f $verdict, $t.Name, $secs, $rc)
    if ($verdict -eq 'ok') { $script:ok++ } elseif ($verdict -eq 'NO TREE') { $script:noTree += $t.Name } else { $script:fail += $t.Name }
}

$queue = New-Object System.Collections.Queue
foreach ($t in $tests) { $queue.Enqueue($t) }
$running = New-Object System.Collections.ArrayList
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($queue.Count -gt 0 -and $running.Count -lt $Jobs) { [void]$running.Add((Start-Guard $queue.Dequeue())) }
    $done = @($running | Where-Object { $_.Proc.HasExited })
    foreach ($d in $done) { Finish-Guard $d; $running.Remove($d) }
    if ($done.Count -eq 0) { Start-Sleep -Milliseconds 100 }
}
$whole.Stop()

$treeAfter = Get-TreeState
$treeChanged = ($null -ne $treeBefore) -and ($treeBefore -ne $treeAfter)
Write-Host ''
Write-Host ('SUMMARY: {0} passed, {1} no-tree, {2} failed, of {3}, in {4:N0}s, {5} at once' -f
    $ok, $noTree.Count, $fail.Count, $tests.Count, $whole.Elapsed.TotalSeconds, $Jobs)
if ($noTree.Count -gt 0) { Write-Host ('  no tree (exit 2, not a failure): ' + ($noTree -join ', ')) }
if ($null -eq $treeBefore) { Write-Host '  tree check: not a git tree, not compared' }
elseif ($treeChanged)      { Write-Host '  TREE CHANGED DURING THE RUN: a guard left the working tree different (or changed it while another read it). Run again with -Jobs 1.' }
else                       { Write-Host '  tree check: the working tree is the same after the run as before' }
if ($fail.Count -gt 0)   { Write-Host ('  FAILED: ' + ($fail -join ', ')) }
if ($fail.Count -gt 0 -or $treeChanged) { exit 1 }
exit 0
