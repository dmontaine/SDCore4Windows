# test-sdprocess-units.ps1 - "is SD running?" must not be decided by process NAME.
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-sdprocess-units.ps1
#
# ORDINARY UNELEVATED PROMPT.  No install, no SD, no elevation.  Exit 0 all passed, 1 something failed, 2 could
# not set up.  Everything it makes is under %TEMP%\test-sdprocess-<pid> and is removed at the end.
#
# WHY IT EXISTS (multi-user PROJECT_STATUS entry 124, 5-6 Oct 2026).  SD Core Solo's daemon is also called
# sdwind.exe, and both products are meant to run at the same time.  cycle.ps1 step 1 counted Solo's daemon as a
# leftover of THIS product, stopped, and advised Stop-Process on it; about thirty other scripts decided "SD is up"
# or "SD is stopped" the same way.  Every `Get-Process ... sdwind ...` in gplbld now carries a filter that leaves
# out an sdwind with sd-solo.exe beside it.  This guard (1) fails on a NEW bare one, (2) runs the filter on real
# processes both ways, and (3) proves the scan can fail on a mutant.
#
# NOT SHIPPED - assert-current exempts test-* scripts by name.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$work = Join-Path $env:TEMP ('test-sdprocess-' + $PID)
$script:pass = 0; $script:fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $what" } else { $script:fail++; Write-Host "  [FAIL] $what $detail" }
}
Write-Host "test-sdprocess-units: scripts in $here"

# A line decides by name when it calls Get-Process with sdwind among the names and does not name sd-solo.exe.
function Get-BareLines([string]$path) {
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        $n++
        if ($line.TrimStart().StartsWith('#')) { continue }
        if ($line -match 'Get-Process' -and $line -match '(?i)(?<![A-Za-z-])sdwind(?![A-Za-z-])' -and $line -notmatch 'sd-solo\.exe') {
            [pscustomobject]@{ File = (Split-Path -Leaf $path); Line = $n; Text = $line.Trim() }
        }
    }
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
$started = @()
try {
    # --- 1. no script decides by name -------------------------------------------------------------------
    Write-Host ''; Write-Host '1. every Get-Process ... sdwind in gplbld excludes Solo'
    $files = @(Get-ChildItem -LiteralPath $here -Filter '*.ps1' | Where-Object { $_.Name -ne 'test-sdprocess-units.ps1' })
    $bare = @($files | ForEach-Object { Get-BareLines $_.FullName })
    Check ("scanned {0} scripts" -f $files.Count) ($files.Count -gt 50)
    $withCalls = @($files | Where-Object { (Select-String -LiteralPath $_.FullName -Pattern 'Get-Process.*sdwind' -Quiet) })
    Check ("CONTROL: {0} scripts do call Get-Process with sdwind (the scan has something to judge)" -f $withCalls.Count) ($withCalls.Count -ge 20)
    Check 'no script decides by name alone' ($bare.Count -eq 0) (($bare | Select-Object -First 5 | ForEach-Object { "$($_.File):$($_.Line)" }) -join ', ')

    # --- 2. the filter itself, on real processes -------------------------------------------------------
    Write-Host ''; Write-Host '2. the filter, on real processes'
    $sample = Select-String -LiteralPath (Join-Path $here 'restart-sd.ps1') -Pattern 'Where-Object \{ \$_\.Name -ne ''sdwind''.*?\) \}' | Select-Object -First 1
    Check 'found the filter text in restart-sd.ps1' ($null -ne $sample)
    $m = [regex]::Match($sample.Line, 'Where-Object \{ \$_\.Name -ne ''sdwind''.*?\)\) \}')
    $filterText = $m.Value
    Check 'extracted the exact filter' ($filterText -ne '') $sample.Line
    $filter = [scriptblock]::Create($filterText.Substring('Where-Object '.Length).Trim().TrimStart('{').TrimEnd('}'))

    $ping = Join-Path $env:SystemRoot 'System32\PING.EXE'
    $full = Join-Path $work 'full'; $solo = Join-Path $work 'solo'
    New-Item -ItemType Directory -Path $full, $solo -Force | Out-Null
    Copy-Item $ping (Join-Path $full 'sdwind.exe'); Copy-Item $ping (Join-Path $solo 'sdwind.exe')
    Copy-Item $ping (Join-Path $solo 'sd-solo.exe')          # the marker: only its presence matters
    $pF = Start-Process -FilePath (Join-Path $full 'sdwind.exe') -ArgumentList '-n', '120', '127.0.0.1' -PassThru -WindowStyle Hidden
    $pS = Start-Process -FilePath (Join-Path $solo 'sdwind.exe') -ArgumentList '-n', '120', '127.0.0.1' -PassThru -WindowStyle Hidden
    $started = @($pF, $pS)
    Start-Sleep -Milliseconds 1500
    $all = @(Get-Process -Name sdwind -ErrorAction SilentlyContinue)
    Check 'CONTROL: both fake daemons are running and visible by name' (($all.Id -contains $pF.Id) -and ($all.Id -contains $pS.Id))
    $kept = @($all | Where-Object $filter)
    Check 'the filter keeps the daemon with no sd-solo.exe beside it' ($kept.Id -contains $pF.Id)
    Check 'the filter drops the daemon with sd-solo.exe beside it' (-not ($kept.Id -contains $pS.Id))
    # a process whose path cannot be read must COUNT (the old behaviour), never be excused
    $fake = [pscustomobject]@{ Name = 'sdwind'; Path = $null }
    Check 'a process whose path is unreadable still counts' (@($fake | Where-Object $filter).Count -eq 1)
    $other = [pscustomobject]@{ Name = 'sd'; Path = (Join-Path $solo 'sdwind.exe') }
    Check 'a process that is not sdwind is never excused by the marker' (@($other | Where-Object $filter).Count -eq 1)

    # --- 3. the scan can fail ---------------------------------------------------------------------------
    Write-Host ''; Write-Host '3. mutant: a script with the filter stripped'
    $mut = Join-Path $work 'mutant.ps1'
    $src = [System.IO.File]::ReadAllText((Join-Path $here 'restart-sd.ps1'))
    $stripped = $src.Replace($filterText, 'Where-Object { $true }')
    Check 'the mutant really differs from the live script' ($stripped -ne $src)
    [System.IO.File]::WriteAllText($mut, $stripped)
    Check 'MUTANT: the scan flags a script whose filter was removed' (@(Get-BareLines $mut).Count -ge 1)
    Check 'CONTROL: the live script is not flagged' (@(Get-BareLines (Join-Path $here 'restart-sd.ps1')).Count -eq 0)
}
catch {
    Write-Host "test-sdprocess-units: STOPPED - $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($script:fail -gt 0) { exit 1 }
    exit 2
}
finally {
    foreach ($p in $started) { try { if ($p -and -not $p.HasExited) { $p.Kill() } } catch { } }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
if ($script:pass -eq 0) { Write-Host 'test-sdprocess-units: VOID - no check ran.'; exit 2 }
if ($script:fail -gt 0) { Write-Host "test-sdprocess-units: FAILED - $($script:pass) passed, $($script:fail) failed."; exit 1 }
Write-Host "test-sdprocess-units: PASSED - $($script:pass) of $($script:pass) checks passed."
exit 0
