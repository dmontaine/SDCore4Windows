# verify-dictrename.ps1 - an UPGRADED dictionary gives up its old upper-case ids
# instead of keeping them beside the lower-case ones.  RELEASE_1.1_FIXES.md 5,
# stage 2b, plan step 4.  ***ELEVATED POWERSHELL.***
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-dictrename.ps1
#
# Exit 0 every check passed, 1 a check failed, 2 the fixture could not be built
# (never a FAIL).
#
# WHAT IT MEASURES.  Stage 2b renamed the shipped dictionary ids to lower case
# (gplbld\FILES_DICTS: TYPE -> type, @ID -> @id, ...).  WRITE_INSTALL_DICTS
# MERGES record by record, and on an upgrade upgrade-dicts.ps1 runs it against a
# dictionary that still holds the old upper-case ids - so without the stage 2b
# change it writes 'type' BESIDE 'TYPE', the twin update.voc was changed to
# avoid for VOC in stage 1.  It now deletes any existing id that differs from a
# shipped one only in case, after writing the shipped one.
#
# ***NOTHING ELSE REACHES THAT BRANCH, SO THIS FORCES THE STATE.***  A first
# install's dictionaries never hold an upper-case id, and a real upgrade needs
# the installer run over the top (verify-upgrade.ps1, which cycle.ps1 cannot
# do).  So it plants the old ids in SDSYS's DICT VOC - TYPE and @ID, copies of
# type and @id - and runs the INSTALLED upgrade-dicts.ps1, the very script the
# installer runs at an upgrade, then reads the stored ids back.
#
# ***THE CONTROL IS zzdrkeep***, planted with them: an id that folds to no
# shipped record, standing for an administrator's own dictionary item.  A
# replace that took too much deletes it; it must survive, and the record count
# must fall by exactly the two planted twins.
#
# STORED IDS ARE READ CASE-SENSITIVELY from LIST DICT VOC's rows (-cmatch at
# the start of a line), because a query folds and NTFS folds: a case-blind
# check passes whichever id is stored.  The heading line ("@ID.......") and the
# echoed command (":LIST ...") cannot match a row pattern.
#
# IT MUST RUN ELEVATED: it drives an SDSYS session (LOGTO SDSYS from an
# unelevated pipe hangs at UAC - verify-pyapi.ps1) and upgrade-dicts.ps1 runs
# sd -internal.  It changes shipped state only by re-running the upgrade step,
# which rewrites the same 78 records the install wrote and recompiles them.
#
# NEVER RUN RED.  assert-current refuses it on an install without stage 2b, so
# the old WRITE_INSTALL_DICTS cannot be driven through it; the red half is the
# source reading in RELEASE_1.1 5 (WRITE_INSTALL_DICTS:107 wrote, nothing
# deleted).

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-dictrename: refusing - see assert-current above'
    exit 2
}

$wid = [Security.Principal.WindowsIdentity]::GetCurrent()
$wpr = New-Object Security.Principal.WindowsPrincipal($wid)
if (-not $wpr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-dictrename: this needs an ELEVATED session and this one is not.'
    Write-Output '  It drives an SDSYS session and runs upgrade-dicts.ps1 (sd -internal).'
    exit 2
}

$appDir   = Join-Path $env:ProgramFiles 'SD'
$sdExe    = Join-Path $appDir 'usr\bin\sd.exe'
$upScript = Join-Path $appDir 'upgrade-dicts.ps1'
$shipped  = Join-Path $appDir 'gplbld\FILES_DICTS'
$dataDir  = Join-Path $env:ProgramData 'SD'
$upLog    = Join-Path $dataDir 'upgrade-dicts.log'

# The planted twins: old id -> the shipped id it copies.  And the control.
$plants = @(
    [pscustomobject]@{ Old = 'TYPE'; New = 'type' },
    [pscustomobject]@{ Old = '@ID';  New = '@id'  })
$keep = 'zzdrkeep'

Write-Output '=== inputs (rule 1: what it actually used) ================================'
Write-Output ("  sd.exe            : " + $sdExe)
Write-Output ("  upgrade-dicts.ps1 : " + $upScript)
Write-Output ("  shipped records   : " + $shipped)
Write-Output ("  planted twins     : " + (($plants | ForEach-Object { $_.Old + ' (copy of ' + $_.New + ')' }) -join ', '))
Write-Output ("  control           : " + $keep + ' (copy of f1; folds to no shipped id)')

foreach ($p in @($sdExe, $upScript, $shipped)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Output "  missing: $p"; exit 2 }
}
$shippedCount = @(Get-ChildItem -LiteralPath $shipped -File).Count
Write-Output ("  shipped record count: " + $shippedCount)
if ($shippedCount -eq 0) { Write-Output '  no shipped records - nothing would be measured'; exit 2 }

$results = New-Object System.Collections.ArrayList
function Row([string]$name, [bool]$ok, [string]$detail) {
    $null = $results.Add([pscustomobject]@{ Name = $name; Ok = $ok })
    if ($ok) { Write-Output "  [PASS] $name" }
    else     { Write-Output "  [FAIL] $name"; Write-Output "         $detail" }
}

function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else {
        Stop-Job $job; $out = Receive-Job $job
        $out += ''; $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# A LIST DICT row for exactly this id: the id at the start of a line, two or
# more spaces, then the D/I/PH type column.  Case-sensitive.
function Test-DictRow([string]$text, [string]$id) {
    return ($text -cmatch ('(?m)^' + [regex]::Escape($id) + '\s{2,}(D|I|PH)\s'))
}
function Get-Listed([string]$text) {
    $m = [regex]::Match($text, '(?m)^(\d+) record\(s\) listed')
    if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}

$logExisted = Test-Path -LiteralPath $upLog
$exit = 2
# Cleanup deletes only what this run planted.  Before the plant, an upper-case
# id in DICT VOC is not ours to remove.
$planted = $false
try {
    # ---- before ------------------------------------------------------------
    Write-Output ''
    Write-Output '=== before: SDSYS DICT VOC as installed ==================================='
    $b = Invoke-SD @('LIST DICT VOC')
    Write-Output $b
    $beforeCount = Get-Listed $b
    Write-Output ("  records listed: " + $beforeCount)
    $setupOk = ($beforeCount -gt 0)
    foreach ($p in $plants) {
        if (-not (Test-DictRow $b $p.New)) { Write-Output ("  no stored '" + $p.New + "' row - not a stage 2b install"); $setupOk = $false }
        if (Test-DictRow $b $p.Old)        { Write-Output ("  '" + $p.Old + "' is already stored - residue of an earlier run; it is planted again below") }
    }
    if (-not $setupOk) { Write-Output '  the dictionary is not what this test assumes - nothing measured'; exit 2 }

    # ---- plant -------------------------------------------------------------
    Write-Output ''
    Write-Output '=== plant: the old upper-case ids, and the control ========================'
    $cmds = @()
    foreach ($p in $plants) { $cmds += ('COPY FROM DICT VOC TO DICT VOC ' + $p.New + ',' + $p.Old + ' OVERWRITING') }
    $cmds += ('COPY FROM DICT VOC TO DICT VOC f1,' + $keep + ' OVERWRITING')
    $cmds += 'LIST DICT VOC'
    foreach ($c in $cmds) { Write-Output ("  SD: " + $c) }
    $planted = $true
    $pl = Invoke-SD $cmds
    Write-Output $pl
    $copied = [regex]::Matches($pl, '(?m)^1 record\(s\) copied').Count
    $plantedCount = Get-Listed $pl
    Write-Output ("  copy success lines: " + $copied + " of 3; records listed: " + $plantedCount)
    $plantOk = ($copied -eq 3)
    foreach ($id in @($plants.Old) + @($keep)) {
        if (-not (Test-DictRow $pl $id)) { Write-Output "  '$id' is not stored after the plant"; $plantOk = $false }
    }
    if (-not $plantOk) { Write-Output '  the plant did not take - nothing below would be measured'; exit 2 }

    # ---- the upgrade step --------------------------------------------------
    Write-Output ''
    Write-Output '=== run: the installed upgrade-dicts.ps1 =================================='
    Write-Output ("  powershell -ExecutionPolicy Bypass -File " + $upScript + " -AppDir " + $appDir)
    # NO 2>&1: in Windows PowerShell 5.1 a native command's stderr redirected
    # under ErrorActionPreference Stop becomes a terminating error.  The script
    # writes everything it has to say to stdout (Say -> Write-Output).
    $ErrorActionPreference = 'Continue'
    $upOut = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $upScript -AppDir $appDir)
    $upCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $upText = ($upOut | ForEach-Object { "$_" }) -join "`n"
    Write-Output $upText
    Write-Output ("  upgrade-dicts exit: " + $upCode)

    # ---- after -------------------------------------------------------------
    Write-Output ''
    Write-Output '=== after =================================================================='
    $a = Invoke-SD @('LIST DICT VOC', 'LIST VOC WITH TYPE = "V" AND @ID = "who"', 'LIST VOC WITH type = "V" AND @id = "who"')
    Write-Output $a
    $afterCount = Get-Listed $a
    Write-Output ("  DICT VOC records: before " + $beforeCount + ", planted " + $plantedCount + ", after " + $afterCount)

    $done = [regex]::Match($upText, '(?m)DONE - (\d+) dictionary record\(s\) written and compiled')
    Row 'upgrade-dicts exited 0' ($upCode -eq 0) "exit $upCode"
    Row "upgrade-dicts wrote and compiled all $shippedCount shipped records" `
        ($done.Success -and ([int]$done.Groups[1].Value -eq $shippedCount)) 'no DONE line with the shipped count'
    foreach ($p in $plants) {
        Row ("WRITE_INSTALL_DICTS reported replacing '" + $p.Old + "' by '" + $p.New + "'") `
            ($upText -cmatch ('(?m)REPLACED OLD ID: voc\.dic ' + [regex]::Escape($p.Old) + ' BY ' + [regex]::Escape($p.New) + '\s*$')) 'no REPLACED OLD ID line'
        Row ("'" + $p.Old + "' is no longer stored") (-not (Test-DictRow $a $p.Old)) 'the old upper-case id survived beside the new one'
        Row ("'" + $p.New + "' is still stored") (Test-DictRow $a $p.New) 'the shipped id is gone'
    }
    Row "CONTROL: '$keep' (folds to no shipped id) survived" (Test-DictRow $a $keep) 'a record that is not a twin was deleted'
    Row 'CONTROL: nothing but the twins was reported replaced' `
        ([regex]::Matches($upText, '(?m)REPLACED OLD ID: ').Count -eq $plants.Count) 'a REPLACED line for something that was not planted'
    Row 'CONTROL: the record count fell by exactly the planted twins' `
        (($plantedCount -gt 0) -and ($afterCount -eq ($plantedCount - $plants.Count))) "planted $plantedCount, after $afterCount"
    $listedWho = [regex]::Matches($a, '(?m)^1 record\(s\) listed').Count
    Row 'a query naming TYPE and @ID, and one naming type and @id, each found who' ($listedWho -eq 2) "1-record lines: $listedWho of 2 (the LIST DICT VOC count is not one of them)"

    $exit = $(if (@($results | Where-Object { -not $_.Ok }).Count -gt 0) { 1 } else { 0 })
}
finally {
    Write-Output ''
    Write-Output '=== cleanup ================================================================'
    if (-not $planted) {
        Write-Output '  nothing was planted - nothing to remove'
        $c = ''
    } else {
        $c = Invoke-SD @('LIST DICT VOC')
    }
    $del = @()
    foreach ($id in @($plants.Old) + @($keep)) {
        # Only an id that is STORED exactly is deleted, so a DELETE that folded
        # could never reach the shipped lower-case record.
        if (Test-DictRow $c $id) { $del += ('DELETE DICT VOC ' + $id) }
    }
    if ($del.Count -gt 0) {
        foreach ($d in $del) { Write-Output ("  SD: " + $d) }
        $dout = Invoke-SD ($del + @('LIST DICT VOC'))
        Write-Output $dout
        $c = $dout
    } else { Write-Output '  nothing planted is still stored' }
    $left = @(@($plants.Old) + @($keep) | Where-Object { Test-DictRow $c $_ })
    $gone = ($left.Count -eq 0)
    Write-Output ("  still stored after cleanup: " + $(if ($gone) { '(none)' } else { $left -join ', ' }))
    if (-not $gone) { Write-Output '  [FAIL] cleanup: planted records remain in SDSYS DICT VOC'; if ($exit -eq 0) { $exit = 1 } }
    if (-not $logExisted -and (Test-Path -LiteralPath $upLog)) {
        Remove-Item -LiteralPath $upLog -Force -ErrorAction SilentlyContinue
        Write-Output ("  removed " + $upLog + " (this run created it; its content is printed above)")
    }
}

$pass = @($results | Where-Object { $_.Ok }).Count
$fail = @($results | Where-Object { -not $_.Ok }).Count
Write-Output ''
Write-Output ("verify-dictrename: $pass passed, $fail failed")
if (($pass + $fail) -eq 0 -and $exit -ne 2) { Write-Output 'verify-dictrename: COULD NOT RUN - no check ran'; exit 2 }
exit $exit
