# probe-nolockmsg.ps1 - PRE_RELEASE_FIXES 12.  A WRITE inside a transaction
# with no lock held must report message 10151, not 1407's "(Possible full
# disk?)".  ORDINARY, UNELEVATED PowerShell.
#
# THE ANCHORS ARE THE POINT (CLAUDE.md, "anchor on the SUCCESS wording").
#   success      : "no lock is held on it" - appears ONLY in 10151.
#   disqualifier : "Possible full disk"    - means 1407 rendered, so the branch
#                  did not fire.  A run matching BOTH is not a pass either.
#   null case    : PROBE-OPENED must appear, or the program never ran and the
#                  absence of the disk wording would mean nothing.
#                  PROBE-WROTE-OK must NOT appear - if the WRITE succeeded then
#                  no lock was required and this measured the wrong thing.
$ErrorActionPreference = 'Stop'

# NOT SDSYS's bp: that is administrator-only and an unelevated WriteAllText
# there fails with "Access to the path ... is denied", which is the data-tree
# hardening working.  An ordinary account's bp is writable, and the account is
# also the more honest place to measure a defect an application would meet.
$sdExe   = 'C:\Program Files\SD\usr\bin\sd.exe'
$account = 'DON'
$bpDir   = 'C:\ProgramData\SD\user_accounts\don\bp'
$prog    = 'ZZNOLOCK'
$file    = 'ZZNOLKF'
$src     = Join-Path $bpDir $prog

Write-Output ('sd.exe   : ' + $sdExe)
Write-Output ('bp       : ' + $bpDir)
Write-Output ('program  : ' + $src)
Write-Output ('test file: ' + $file)
Write-Output ''
if (-not (Test-Path -LiteralPath $sdExe)) { Write-Output 'REFUSED: no sd.exe'; exit 2 }
if (-not (Test-Path -LiteralPath $bpDir)) { Write-Output 'REFUSED: no sdsys bp directory'; exit 2 }

function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    # An administrator's local session lands in SDSYS (PRE_RELEASE 56), so the
    # LOGTO is what puts this in an ordinary account's BP rather than SDSYS's.
    $body = "`n" + ((@("LOGTO $account", 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    if ($body.Contains([char]13)) { Write-Output 'REFUSED: CR in the SD body'; exit 2 }
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $o = Receive-Job $job } else { $o = '<TIMEOUT>'; Stop-Job $job }
    Remove-Job $job -Force
    return (($o | Out-String) -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '')
}

# LF only.  Written with WriteAllText because Set-Content appends a CRLF
# terminator and SD then takes the \r as a line of its own.
$basic = @(
    "* ZZNOLOCK - PRE_RELEASE_FIXES 12 probe.  Planted and removed by",
    "* probe-nolockmsg.ps1.  A WRITE inside a transaction with no lock held.",
    "      OPEN '$file' TO F.ZZ ELSE",
    "         CRT 'PROBE-NOOPEN'",
    "         STOP",
    "      END",
    "      CRT 'PROBE-OPENED'",
    "      BEGIN TRANSACTION",
    "      WRITE 'probe' ON F.ZZ, 'R1'",
    "      COMMIT",
    "      END TRANSACTION",
    "      CRT 'PROBE-WROTE-OK'",
    "      END"
) -join "`n"

try {
    Write-Output '--- the BASIC under test ---'
    $basic -split "`n" | ForEach-Object { Write-Output ('  | ' + $_) }
    Write-Output ''

    [System.IO.File]::WriteAllText($src, $basic + "`n", [System.Text.Encoding]::ASCII)
    Write-Output ('planted  : ' + (Test-Path -LiteralPath $src) + '  (' + (Get-Item -LiteralPath $src).Length + ' bytes)')

    $mk = Invoke-SD @('WHO', "CREATE.FILE $file")
    Write-Output '--- WHO + CREATE.FILE ---'
    ($mk -split "`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 6 | ForEach-Object { Write-Output ('  | ' + $_) }

    $out = Invoke-SD @("BASIC BP $prog", "RUN BP $prog")
    Write-Output ''
    Write-Output '--- BASIC BP / RUN BP ---'
    ($out -split "`n") | Where-Object { $_.Trim() -ne '' } | ForEach-Object { Write-Output ('  | ' + $_) }
    Write-Output ''

    # --- the readings -----------------------------------------------------
    $ran      = $out -match 'PROBE-OPENED'
    $wroteOk  = $out -match 'PROBE-WROTE-OK'
    $newMsg   = $out -match 'no lock is held on it'
    $oldMsg   = $out -match 'Possible full disk'
    $says3023 = $out -match '3023'

    Write-Output '--- readings ---'
    Write-Output ('  PROBE-OPENED (the program ran)        : ' + $ran      + '   (must be True)')
    Write-Output ('  PROBE-WROTE-OK (write was allowed)    : ' + $wroteOk  + '   (must be False)')
    Write-Output ('  "no lock is held on it"  [10151]      : ' + $newMsg   + '   (must be True)')
    Write-Output ('  "Possible full disk"     [1407]       : ' + $oldMsg   + '   (must be False)')
    Write-Output ('  error number 3023 shown               : ' + $says3023)
    Write-Output ''

    if (-not $ran) {
        Write-Output 'REFUSED: the probe never opened the file, so nothing below was measured.'
        exit 2
    }
    if ($wroteOk) {
        Write-Output 'REFUSED: the WRITE succeeded, so no lock was required and this is the wrong measurement.'
        exit 2
    }
    $pass = ($newMsg -and (-not $oldMsg))
    if ($pass) {
        Write-Output 'PASS - PRE_RELEASE 12 is fixed on this install: the missing lock is named and the disk is not.'
        exit 0
    }
    Write-Output 'FAIL - the write refusal did not render message 10151.'
    exit 1
}
finally {
    Write-Output ''
    Write-Output '--- cleanup ---'
    $rm = Invoke-SD @("DELETE.FILE $file no.query")
    ($rm -split "`n") | Where-Object { $_ -match 'eleted|not found' } | Select-Object -First 3 |
        ForEach-Object { Write-Output ('  | ' + $_) }
    if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Force }
    foreach ($leftover in @("$src.OUT", (Join-Path 'C:\ProgramData\SD\sdsys\bp.out' $prog))) {
        if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Force }
    }
    Write-Output ('  source removed : ' + (-not (Test-Path -LiteralPath $src)))
}
