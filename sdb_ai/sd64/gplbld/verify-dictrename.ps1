# verify-dictrename.ps1 - an UPGRADED dictionary gives up its old upper-case ids
# instead of keeping them beside the lower-case ones - and, on a case-insensitive
# dictionary, instead of DELETING them.  RELEASE_1.1_FIXES.md 5, stage 2b plan
# step 4, and D2.  ***ELEVATED POWERSHELL.***
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-dictrename.ps1
#
# Exit 0 every check passed, 1 a check failed, 2 the fixture could not be built
# (never a FAIL).
#
# WHAT IT MEASURES.  Stage 2b renamed the shipped dictionary ids to lower case
# (gplbld\FILES_DICTS: TYPE -> type, @ID -> @id, ...).  WRITE_INSTALL_DICTS
# MERGES record by record, and on an upgrade upgrade-dicts.ps1 runs it against a
# dictionary that may still hold the old upper-case ids, so for each shipped
# record it deletes any existing id that differs from it only in case.
#
# ***14 Sep 2026 - REBUILT FOR D2, OWNER'S RULING ("retire and replace").***
# The first version planted TWINS - TYPE beside type - and D2 made every hashed
# file case insensitive, so a twin cannot be written (b161: the plant did not
# take and the step exited 2).  What CAN exist is a dictionary converted to
# NOCASE while it still stored the old spellings: ONE record, stored 'TYPE'.
# And on that state the 2b code DELETED the item: it wrote 'type', which on a
# NOCASE file updates the record still stored as TYPE, then deleted 'TYPE' -
# the only copy.  Measured 14 Sep 2026 on a scratch NOCASE file (write TYPE,
# write type, delete TYPE: 0 records).  Owner: "fix it now".  WRITE_INSTALL_DICTS
# now deletes first and writes after on a NOCASE dictionary.  This is its
# witness: the plant is that exact state, and the item must come back RENAMED.
#
# THE PLANT, AND WHY IN THAT ORDER.  For TYPE and @ID: copy the shipped record
# to a scratch id, DELETE the shipped id, copy the scratch id back under the
# upper-case id, delete the scratch id.  No step deletes a record it has just
# written.  A precondition row proves TYPE and @ID stored, type and @id not.
#
# ***THE CONTROLS.***  (1) D2 itself: COPY f1 to F1 without OVERWRITING must be
# refused as "already exists" - on a case-sensitive dictionary it would make a
# twin.  (2) zzdrkeep, an id that folds to no shipped record, standing for an
# administrator's own item: it must survive.  (3) the record count must be the
# same after the upgrade as after the plant - renamed, not added, not lost.
#
# STORED IDS ARE READ CASE-SENSITIVELY from LIST DICT VOC's rows (-cmatch at the
# start of a line).  A full LIST walks the file and prints each id as stored;
# the heading line ("@id.......") and the echoed command cannot match a row.
#
# ***CLEANUP NEVER DELETES A SHIPPED NAME, IN ANY CASE.***  On a NOCASE file
# "DELETE DICT VOC TYPE" deletes 'type'.  If type or @id is not stored lower at
# the end - a plant that was never upgraded, or a pre-fix install that deleted
# them - cleanup runs the installed upgrade-dicts.ps1 again (twice at most):
# with the fix it renames; without it, the first run deletes and the second
# writes the item back.  Only zzdrkeep and the zzdrtmp scratch ids are deleted
# by name, and they fold to nothing shipped.
#
# IT MUST RUN ELEVATED, AND SDSYS MUST BE SIGNED IN: it drives an SDSYS session
# through the SDSYS seat (sdsys-seat.ps1, RELEASE_1.1 76) and upgrade-dicts.ps1
# runs sd -internal.  It changes shipped state only by re-running the upgrade step,
# which rewrites the same 78 records the install wrote and recompiles them.
#
# NEVER RUN RED AS A SCRIPT.  assert-current refuses it on an install without
# the fix; the red half is the scratch-file measurement above and the reading
# of WRITE_INSTALL_DICTS:125-133 before it, in RELEASE_1.1 5.

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

# The planted old spellings: old id -> the shipped id it replaces.  And the control.
$plants = @(
    [pscustomobject]@{ Old = 'TYPE'; New = 'type'; Tmp = 'zzdrtmp1' },
    [pscustomobject]@{ Old = '@ID';  New = '@id';  Tmp = 'zzdrtmp2' })
$keep = 'zzdrkeep'

Write-Output '=== inputs (rule 1: what it actually used) ================================'
Write-Output ("  sd.exe            : " + $sdExe)
Write-Output ("  upgrade-dicts.ps1 : " + $upScript)
Write-Output ("  shipped records   : " + $shipped)
Write-Output ("  planted           : " + (($plants | ForEach-Object { $_.Old + ' (stored alone, in place of ' + $_.New + ')' }) -join ', '))
Write-Output ("  controls          : " + $keep + ' (copy of f1; folds to no shipped id); COPY f1,F1 refused')
Write-Output ("  upgrade log       : " + $upLog)

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

# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT (sdsys-seat.ps1; verify-createaccount
# was the pilot).  THE "LOGTO SDSYS" PREFIX THIS USED TO SEND IS REFUSED (10002)
# FROM ANY SESSION THAT DID NOT START AS THE OS SDSYS ACCOUNT with an elevated,
# interactive token, and an elevated Don is not one.  So the commands go to a task
# inside SDSYS's own live session and the text comes back through a file; the TERM
# line this sent first is added by the helper.  A seat that did not run THROWS
# rather than returning ''.  SDSYS must be signed in: `query session` shows its
# row.  upgrade-dicts.ps1 (Invoke-Upgrade below) is the shipped step and still
# runs sd -internal from this elevated shell, exactly as the installer does.
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 180) {
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec)
}

# The installed upgrade step, exactly as the installer runs it.  NO 2>&1: in
# Windows PowerShell 5.1 a native command's stderr redirected under
# ErrorActionPreference Stop becomes a terminating error.  The script writes
# everything it has to say to stdout (Say -> Write-Output).
function Invoke-Upgrade {
    Write-Output ("  powershell -ExecutionPolicy Bypass -File " + $upScript + " -AppDir " + $appDir)
    $ErrorActionPreference = 'Continue'
    $o = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $upScript -AppDir $appDir)
    $c = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    return [pscustomobject]@{ Text = (($o | ForEach-Object { "$_" }) -join "`n"); Code = $c }
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
function Test-ShippedLower([string]$text) {
    foreach ($p in $plants) {
        if (-not (Test-DictRow $text $p.New) -or (Test-DictRow $text $p.Old)) { return $false }
    }
    return $true
}

# 20 Sep 26 - RELEASE_1.1 76: PROVE THE SDSYS SEAT BEFORE PLANTING ANYTHING, so a
# missing SDSYS session is exit 2 ("could not run") and leaves no plant behind,
# not a thrown error at the first SD call that reads as a product failure.
Assert-SdSeat -Label 'verify-dictrename'

$logExisted = Test-Path -LiteralPath $upLog
$exit = 2
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
    if (-not (Test-ShippedLower $b)) { Write-Output '  type and @id are not both stored lower (and alone) - not a 2b install, or residue of an earlier run'; $setupOk = $false }
    if (Test-DictRow $b $keep) { Write-Output ("  '" + $keep + "' is already stored - residue of an earlier run"); $setupOk = $false }
    if (-not $setupOk) { Write-Output '  the dictionary is not what this test assumes - nothing measured'; exit 2 }

    # ---- control: D2 refuses a twin ------------------------------------------
    Write-Output ''
    Write-Output '=== control: a twin cannot be written ====================================='
    $tw = Invoke-SD @('COPY FROM DICT VOC TO DICT VOC f1,F1', 'LIST DICT VOC')
    Write-Output $tw
    Row 'CONTROL: COPY f1 to F1 is refused as already existing (D2 - no twin)' `
        (($tw -match "Record 'F1' already exists") -and ($tw -match '(?m)^0 record\(s\) copied')) 'COPY did not refuse - the dictionary is not case insensitive'
    Row 'CONTROL: and the dictionary still holds exactly the records it had' ((Get-Listed $tw) -eq $beforeCount) ("before " + $beforeCount + ", now " + (Get-Listed $tw))

    # ---- plant -------------------------------------------------------------
    Write-Output ''
    Write-Output '=== plant: the old upper-case spellings, one record each, and the control =='
    $cmds = @()
    foreach ($p in $plants) {
        $cmds += ('COPY FROM DICT VOC TO DICT VOC ' + $p.New + ',' + $p.Tmp)
        $cmds += ('DELETE DICT VOC ' + $p.New)
        $cmds += ('COPY FROM DICT VOC TO DICT VOC ' + $p.Tmp + ',' + $p.Old)
        $cmds += ('DELETE DICT VOC ' + $p.Tmp)
    }
    $cmds += ('COPY FROM DICT VOC TO DICT VOC f1,' + $keep)
    $cmds += 'LIST DICT VOC'
    foreach ($c in $cmds) { Write-Output ("  SD: " + $c) }
    $planted = $true
    $pl = Invoke-SD $cmds
    Write-Output $pl
    $copied = [regex]::Matches($pl, '(?m)^1 record\(s\) copied').Count
    $wantCopied = 2 * $plants.Count + 1
    $plantedCount = Get-Listed $pl
    Write-Output ("  copy success lines: " + $copied + " of " + $wantCopied + "; records listed: " + $plantedCount)
    $plantOk = ($copied -eq $wantCopied) -and ($plantedCount -eq ($beforeCount + 1))
    foreach ($p in $plants) {
        if (-not (Test-DictRow $pl $p.Old)) { Write-Output ("  '" + $p.Old + "' is not stored after the plant"); $plantOk = $false }
        if (Test-DictRow $pl $p.New)        { Write-Output ("  '" + $p.New + "' is still stored after the plant"); $plantOk = $false }
        if (Test-DictRow $pl $p.Tmp)        { Write-Output ("  '" + $p.Tmp + "' was left behind"); $plantOk = $false }
    }
    if (-not (Test-DictRow $pl $keep)) { Write-Output "  '$keep' is not stored after the plant"; $plantOk = $false }
    Row ('precondition: ' + (($plants | ForEach-Object { $_.Old }) -join ' and ') + ' stored alone, count ' + ($beforeCount + 1)) $plantOk 'the plant did not take'
    if (-not $plantOk) { Write-Output '  nothing below would be measured'; exit 2 }

    # ---- the upgrade step --------------------------------------------------
    Write-Output ''
    Write-Output '=== run: the installed upgrade-dicts.ps1 =================================='
    $up = Invoke-Upgrade
    Write-Output $up.Text
    Write-Output ("  upgrade-dicts exit: " + $up.Code)

    # ---- after -------------------------------------------------------------
    Write-Output ''
    Write-Output '=== after =================================================================='
    $a = Invoke-SD @('LIST DICT VOC', 'LIST VOC WITH TYPE = "V" AND @ID = "who"', 'LIST VOC WITH type = "V" AND @id = "who"')
    Write-Output $a
    $afterCount = Get-Listed $a
    Write-Output ("  DICT VOC records: before " + $beforeCount + ", planted " + $plantedCount + ", after " + $afterCount)

    $done = [regex]::Match($up.Text, '(?m)DONE - (\d+) dictionary record\(s\) written and compiled')
    Row 'upgrade-dicts exited 0' ($up.Code -eq 0) "exit $($up.Code)"
    Row "upgrade-dicts wrote and compiled all $shippedCount shipped records" `
        ($done.Success -and ([int]$done.Groups[1].Value -eq $shippedCount)) 'no DONE line with the shipped count'
    foreach ($p in $plants) {
        Row ("WRITE_INSTALL_DICTS reported replacing '" + $p.Old + "' by '" + $p.New + "'") `
            ($up.Text -cmatch ('(?m)REPLACED OLD ID: voc\.dic ' + [regex]::Escape($p.Old) + ' BY ' + [regex]::Escape($p.New) + '\s*$')) 'no REPLACED OLD ID line'
        # DECISIVE, AND THE ROW THE PRE-FIX CODE FAILS: the item must still exist.
        Row ("'" + $p.New + "' is stored - the item was renamed, not deleted") (Test-DictRow $a $p.New) 'the shipped item is GONE - the write-then-delete order removed it'
        Row ("'" + $p.Old + "' is no longer stored") (-not (Test-DictRow $a $p.Old)) 'the old upper-case spelling survived'
    }
    Row "CONTROL: '$keep' (folds to no shipped id) survived" (Test-DictRow $a $keep) 'a record that is not a renamed id was deleted'
    Row 'CONTROL: nothing but the planted ids was reported replaced' `
        ([regex]::Matches($up.Text, '(?m)REPLACED OLD ID: ').Count -eq $plants.Count) 'a REPLACED line for something that was not planted'
    Row 'CONTROL: the record count is unchanged by the upgrade (renamed, not added, not lost)' `
        (($plantedCount -gt 0) -and ($afterCount -eq $plantedCount)) "planted $plantedCount, after $afterCount"
    $listedWho = [regex]::Matches($a, '(?m)^1 record\(s\) listed').Count
    Row 'a query naming TYPE and @ID, and one naming type and @id, each found who' ($listedWho -eq 2) "1-record lines: $listedWho of 2 (the LIST DICT VOC count is not one of them)"

    $exit = $(if (@($results | Where-Object { -not $_.Ok }).Count -gt 0) { 1 } else { 0 })
}
finally {
    Write-Output ''
    Write-Output '=== cleanup ================================================================'
    if (-not $planted) {
        Write-Output '  nothing was planted - nothing to remove'
    } else {
        # 1. The shipped items, restored by the upgrade step itself - never by a
        #    DELETE of any spelling of a shipped name.
        $c = Invoke-SD @('LIST DICT VOC')
        $tries = 0
        while ((-not (Test-ShippedLower $c)) -and ($tries -lt 2)) {
            $tries++
            Write-Output ("  type/@id not both stored lower - running upgrade-dicts to restore (" + $tries + " of 2)")
            $r = Invoke-Upgrade
            Write-Output $r.Text
            Write-Output ("  upgrade-dicts exit: " + $r.Code)
            $c = Invoke-SD @('LIST DICT VOC')
        }
        # 2. Our own scratch ids, by their exact lower names only.
        $del = @()
        foreach ($id in @($keep) + @($plants.Tmp)) { if (Test-DictRow $c $id) { $del += ('DELETE DICT VOC ' + $id) } }
        if ($del.Count -gt 0) {
            foreach ($d in $del) { Write-Output ("  SD: " + $d) }
            $c = Invoke-SD ($del + @('LIST DICT VOC'))
            Write-Output $c
        }
        $left = @(@($keep) + @($plants.Tmp) | Where-Object { Test-DictRow $c $_ })
        $shippedOk = Test-ShippedLower $c
        Write-Output ("  still stored after cleanup: " + $(if ($left.Count -eq 0) { '(none)' } else { $left -join ', ' }))
        Write-Output ("  type and @id stored lower after cleanup: " + $shippedOk)
        if ($left.Count -gt 0) { Write-Output '  [FAIL] cleanup: planted records remain in SDSYS DICT VOC'; if ($exit -eq 0) { $exit = 1 } }
        if (-not $shippedOk) {
            Write-Output ('  [FAIL] cleanup: SDSYS DICT VOC does not hold type and @id - run ' + $upScript + ' elevated to restore them')
            if ($exit -eq 0) { $exit = 1 }
        }
    }
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
