# probe-tasklock.ps1 - PRE_RELEASE_FIXES 24.  Does "sd -cleanup" now release a
# DEAD session's task lock?  ORDINARY, UNELEVATED PowerShell; it raises one
# elevation for the cleanup itself, which check_admin() requires.
#
# THE SHAPE, AND STEP 4 IS WHAT MAKES STEP 5 MEAN ANYTHING.
#   1 baseline    no task locks held at all, or the readings below are noise
#   2 hold        a background session takes LOCK 5 and naps
#   3 confirm     LIST.LOCKS shows it - else the program never locked
#   4 kill+check  kill the process, and the lock must STILL be held.  If the
#                 kill released it, cleanup is not what frees it and step 5
#                 would score a pass for something it did not do.
#   5 cleanup     sd -cleanup, elevated.  THE DECISIVE ROW: now free.
$ErrorActionPreference = 'Stop'

$sdExe = 'C:\Program Files\SD\usr\bin\sd.exe'
$bpDir = 'C:\ProgramData\SD\user_accounts\don\bp'
$prog  = 'ZZTLOCK'
$src   = Join-Path $bpDir $prog
$lockNo = 5
$none  = 'No task locks reserved by any user'

Write-Output ('sd.exe    : ' + $sdExe)
Write-Output ('program   : ' + $src)
Write-Output ('lock      : ' + $lockNo)
Write-Output ('free text : "' + $none + '"')
Write-Output ''

function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($e,$t) $t | & $e } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $o = Receive-Job $job } else { $o = '<TIMEOUT>'; Stop-Job $job }
    Remove-Job $job -Force
    return (($o | Out-String) -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '')
}
function Get-Locks { return (Invoke-SD @('LIST.LOCKS')) }
function Locks-Free([string]$t) { return ($t -match [regex]::Escape($none)) }

$basic = @(
    "* ZZTLOCK - PRE_RELEASE_FIXES 24 probe.  Planted and removed by",
    "* probe-tasklock.ps1.  Takes a task lock and then waits to be killed.",
    "      LOCK $lockNo",
    "      CRT 'PROBE-LOCKED'",
    "      FOR ZZI = 1 TO 600",
    "         NAP 1000",
    "      NEXT ZZI",
    "      CRT 'PROBE-TIMEOUT'",
    "      END"
) -join "`n"

$bg = $null
try {
    Write-Output '--- the BASIC under test ---'
    $basic -split "`n" | ForEach-Object { Write-Output ('  | ' + $_) }
    Write-Output ''

    [System.IO.File]::WriteAllText($src, $basic + "`n", [System.Text.Encoding]::ASCII)
    $cmp = Invoke-SD @("LOGTO DON", "BASIC BP $prog")
    $compiled = ($cmp -match '0 error\(s\)')
    Write-Output ('[1] compiled                     : ' + $compiled + '   (must be True)')
    if (-not $compiled) {
        ($cmp -split "`n") | Where-Object { $_.Trim() -ne '' } | ForEach-Object { Write-Output ('  | ' + $_) }
        Write-Output 'REFUSED: the probe did not compile.'
        exit 2
    }

    $base = Get-Locks
    $baseFree = Locks-Free $base
    Write-Output ('[1] baseline: no locks held      : ' + $baseFree + '   (must be True)')
    if (-not $baseFree) {
        ($base -split "`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 8 | ForEach-Object { Write-Output ('  | ' + $_) }
        Write-Output 'REFUSED: locks are already held, so nothing below could be attributed to this probe.'
        exit 2
    }

    # --- 2. hold it from a background session ------------------------------
    $before = @(Get-Process -Name sd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    # The body goes in a FILE and the launcher PIPES it: sd.exe with a
    # redirected file handle on stdin prints "Process terminated" and runs
    # nothing, so the pipe is required rather than tidier.
    $bodyFile = Join-Path $env:TEMP ('zztl-body-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.txt')
    $launcher = Join-Path $env:TEMP ('zztl-run-'  + [guid]::NewGuid().ToString('N').Substring(0,8) + '.ps1')
    [System.IO.File]::WriteAllText($bodyFile, "`nLOGTO DON`nTERM 200,9999`nRUN BP $prog`nOFF`n", [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllText($launcher,
        ("`$b = Get-Content -LiteralPath '" + $bodyFile + "' -Raw`r`n" +
         "`$b | & '" + $sdExe + "' | Out-Null`r`n"), [System.Text.Encoding]::ASCII)
    $bg = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher)
    Write-Output ('[2] background launcher pid      : ' + $bg.Id)

    $held = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 1000
        if (-not (Locks-Free (Get-Locks))) { $held = $true; break }
    }
    $now = @(Get-Process -Name sd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $new = @($now | Where-Object { $before -notcontains $_ })
    Write-Output ('[3] sd.exe pid(s) started        : ' + ($new -join ', '))
    $lockTxt = Get-Locks
    Write-Output ('[3] the lock is held             : ' + $held + '   (must be True)')
    ($lockTxt -split "`n") | Where-Object { $_ -match 'ock|ser|\d' -and $_ -notmatch '^:' -and $_.Trim() -ne '' } |
        Select-Object -Last 6 | ForEach-Object { Write-Output ('    | ' + $_) }
    if (-not $held) { Write-Output 'REFUSED: the probe never took the lock, so nothing below was measured.'; exit 2 }
    if ($new.Count -eq 0) { Write-Output 'REFUSED: no new sd.exe to kill - cannot make a DEAD session.'; exit 2 }

    # --- 4. kill it, and the lock must SURVIVE -----------------------------
    foreach ($pid2 in $new) { & taskkill.exe /F /PID $pid2 2>&1 | ForEach-Object { Write-Output ('    | ' + $_) } }
    if ($bg -and -not $bg.HasExited) { Stop-Process -Id $bg.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    $afterKill = Get-Locks
    $stillHeld = -not (Locks-Free $afterKill)
    Write-Output ('[4] lock SURVIVES the kill       : ' + $stillHeld + '   (must be True - this is the control)')
    if (-not $stillHeld) {
        Write-Output 'REFUSED: the kill released the lock by itself, so step 5 would prove nothing about cleanup.'
        exit 2
    }

    # --- 5. sd -cleanup, elevated. THE DECISIVE ROW ------------------------
    $log = Join-Path $env:TEMP ('sdcleanup-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.txt')
    Write-Output ''
    Write-Output ('[5] running: "' + $sdExe + '" -cleanup   (ELEVATED - a UAC prompt is coming)')
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',
                            ('& ' + "'" + $sdExe + "'" + ' -cleanup *> ' + "'" + $log + "'"))
    Write-Output ('    cleanup exit code            : ' + $p.ExitCode)
    if (Test-Path -LiteralPath $log) {
        (Get-Content -LiteralPath $log) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 8 |
            ForEach-Object { Write-Output ('    | ' + $_) }
        Remove-Item -LiteralPath $log -Force
    }

    Start-Sleep -Seconds 1
    $final = Get-Locks
    $freed = Locks-Free $final
    Write-Output ''
    Write-Output ('[5] lock released by sd -cleanup : ' + $freed + '   (THE DECISIVE ONE - must be True)')
    ($final -split "`n") | Where-Object { $_ -match 'ock' } | Select-Object -Last 4 | ForEach-Object { Write-Output ('    | ' + $_) }

    Write-Output ''
    if ($freed) { Write-Output 'PASS - PRE_RELEASE 24 is fixed on this install: a dead session''s task lock is released.'; exit 0 }
    Write-Output 'FAIL - the task lock survived sd -cleanup, which is the defect 24 describes.'
    exit 1
}
finally {
    Write-Output ''
    Write-Output '--- cleanup ---'
    foreach ($leftover in @($src, (Join-Path 'C:\ProgramData\SD\user_accounts\don\bp.out' $prog))) {
        if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Force -ErrorAction SilentlyContinue }
    }
    Write-Output ('  source removed : ' + (-not (Test-Path -LiteralPath $src)))
    Write-Output ('  locks now      : ' + $(if (Locks-Free (Get-Locks)) { 'none held' } else { 'SOMETHING IS STILL HELD - look' }))
}
