# upgrade-nocase.ps1 - convert an upgraded machine's existing files to case
# insensitive record ids.  RELEASE_1.1 5 D2.  Runs at UPGRADE only (a fresh
# install makes every file NOCASE by construction); the installer calls it from
# sd.iss beside upgrade-dicts.ps1.
#
# It drives  sd -internal RUN gpl.bp UPGRADE_NOCASE , which walks every
# account's files by path, and:
#   - scans each file READ ONLY for a fold-pair (two record ids differing only
#     by case) FIRST, and converts nothing until the file is proven clean;
#   - converts the clean ones to NOCASE;
#   - leaves a file that holds a pair exactly as it is and NAMES the pair, so no
#     conversion can ever lose a record;
#   - leaves indexed files for manual CONFIGURE.FILE (rebuilding an AK by path
#     is unsafe), naming them.
#
# ***THE FULL REPORT IS WRITTEN TO C:\ProgramData\SD\nocase-upgrade.log*** so an
# administrator can read, after a hidden install, exactly which files held a
# duplicate and which record ids they were.  A run that found duplicates is NOT
# a failure - the files are safe - but it exits 2 so the installer can point the
# administrator at the log.
#
# Exit 0 clean (converted what it could, no duplicates), 2 completed but some
# files hold a case-only duplicate and were left (see the log), 1 a real
# failure, 3 SD would not start.

[CmdletBinding()]
param(
    [string] $AppDir = '',
    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $DataDir 'nocase-upgrade.log'

function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

# The verdict, read from the program's own output.  Kept a pure function of the
# text so test-upgradenocase-units.ps1 can drive it with no SD.  UPGRADE_NOCASE
# prints, on the positive path, its last line "COMPLETE" and a
# "Converted N of M file(s)..." line (sysmsg 10179); a warning block
# "WARNING: F file(s) hold D record id(s)..." (10178) when it left duplicates;
# and "... could not be read or rebuilt" (10183) on a real trouble.
function Get-NocaseVerdict([string] $Text) {
    $complete = $Text -match '(?m)^\s*COMPLETE\s*$'
    $converted = -1; $scanned = -1
    $m = [regex]::Match($Text, 'Converted\s+(\d+)\s+of\s+(\d+)\s+file')
    if ($m.Success) { $converted = [int]$m.Groups[1].Value; $scanned = [int]$m.Groups[2].Value }
    # 10178: "WARNING: <files> file(s) hold <ids> record id(s) that differ..."
    $dupFiles = 0; $dupIds = 0
    $m = [regex]::Match($Text, 'WARNING:\s+(\d+)\s+file\(s\)\s+hold\s+(\d+)\s+record id')
    if ($m.Success) { $dupFiles = [int]$m.Groups[1].Value; $dupIds = [int]$m.Groups[2].Value }
    $couldNot = ($Text -match 'could not be read or rebuilt')
    return [pscustomobject]@{
        Complete = $complete
        Converted = $converted
        Scanned = $scanned
        DupFiles = $dupFiles
        DupIds = $dupIds
        HadTrouble = $couldNot
    }
}

# The units test dot-sources this file for Get-NocaseVerdict with $SkipRun set,
# so nothing below - including the sd.exe check - runs under test.
if ($SkipRun) { return }

if (-not $AppDir) { $AppDir = $PSScriptRoot }
Say ("=== upgrade-nocase {0}  AppDir={1}  DataDir={2}" -f (Get-Date -Format 's'), $AppDir, $DataDir)
if (-not $AppDir) { Say 'upgrade-nocase: no -AppDir and PSScriptRoot empty; cannot find sd.exe'; exit 1 }
$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) { Say "upgrade-nocase: no sd.exe at $sd"; exit 1 }

function Invoke-Sd {
    param([string[]] $SdArgs, [int] $TimeoutMs = 1800000)   # up to 30 min: user data can be large
    $out = Join-Path $env:TEMP ("sd-nocase-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-nocase-err-$PID.txt")
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru `
                       -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    $exited = $p.WaitForExit($TimeoutMs)
    $text = ''
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) { $text += (Get-Content $f -Raw); Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    if (-not $exited) { return [pscustomobject]@{ Code = 1; Text = "sd $SdArgs did not finish in $($TimeoutMs/1000)s" } }
    return [pscustomobject]@{ Code = $p.ExitCode; Text = "$text".Trim() }
}
function Test-SdRunning { return $null -ne (Get-Process sdwind -ErrorAction SilentlyContinue) }
function Wait-SdRunning {
    param([int] $TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) { if (Test-SdRunning) { return $true }; Start-Sleep -Milliseconds 500 }
    return (Test-SdRunning)
}

$weStartedIt = $false
$result = 1
try {
    if (-not (Test-SdRunning)) {
        $r = Invoke-Sd @('-start')
        if (-not (Wait-SdRunning)) {
            Say 'upgrade-nocase: SD would not start, so no file was converted'
            Say ("  sd -start exited {0}: {1}" -f $r.Code, $r.Text)
            $result = 3
            throw 'no server'
        }
        $weStartedIt = $true
    }

    Say 'upgrade-nocase: sd -internal RUN gpl.bp UPGRADE_NOCASE NO.PAGE'
    $w = Invoke-Sd @('-internal', 'RUN', 'gpl.bp', 'UPGRADE_NOCASE', 'NO.PAGE')
    Say ("  exit {0}" -f $w.Code)
    Say '  --- report ---'
    foreach ($l in ("$($w.Text)" -split "`r?`n")) { if ($l.Trim()) { Say ("  | " + $l) } }
    Say '  --- end ---'

    $v = Get-NocaseVerdict $w.Text
    Say ("upgrade-nocase: complete={0} converted={1}/{2} dupFiles={3} dupIds={4} trouble={5}" -f
         $v.Complete, $v.Converted, $v.Scanned, $v.DupFiles, $v.DupIds, $v.HadTrouble)

    if (-not $v.Complete) {
        Say 'upgrade-nocase: UPGRADE_NOCASE did not reach COMPLETE'
        throw 'incomplete'
    }
    if ($v.HadTrouble) {
        Say 'upgrade-nocase: one or more files could not be read or rebuilt (see the report)'
        throw 'file trouble'
    }
    if ($v.DupFiles -gt 0) {
        Say ("upgrade-nocase: DONE with a WARNING - {0} file(s) hold {1} record id(s) that differ only by case and were left unchanged." -f
             $v.DupFiles, $v.DupIds)
        Say ("  The full list is in {0}. Rename or delete one id of each pair, then convert that file with CONFIGURE.FILE NO.CASE." -f $LogFile)
        $result = 2
    }
    else {
        Say ("upgrade-nocase: DONE - converted {0} of {1} file(s); no duplicates found." -f $v.Converted, $v.Scanned)
        $result = 0
    }
}
catch {
    if ($result -ne 3) { $result = 1 }
    Say "upgrade-nocase: FAILED - $($_.Exception.Message)"
}
finally {
    if ($weStartedIt) { $null = Invoke-Sd @('-stop') }
}

exit $result
