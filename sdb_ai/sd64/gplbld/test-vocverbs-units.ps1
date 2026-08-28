# test-vocverbs-units.ps1 - drive verify-vocverbs.ps1's matchers against
# synthetic transcripts of a FIXED build and a DEFECTIVE one, and require every
# pattern to tell them apart.
#
#   powershell -File test-vocverbs-units.ps1
#
# Exit 0 every row passed, 1 a row failed.  It needs no install, no elevation
# and no SD: it touches nothing but the verifier's own text.
#
# WHY IT EXISTS.  verify-vocverbs.ps1 costs an elevated run on a current
# install, and its whole value is in wording - a pattern that also matches the
# refusal is "a false positive with a check's name on it" (CLAUDE.md).  The
# patterns are the part that can be checked for nothing, so they are.
#
# ***THE NEGATIVE ROWS ARE THE POINT.***  Every check appears twice: once
# against output a fixed build produces, once against output the DEFECT
# produces.  A pattern that matches both is not a check, and only the pair
# shows that.  The defect transcripts are written from the pre-fix code paths -
# CPROC:1119's double-read failure, QSELECT's one-argument sysmsg, DELETEF's
# 6146 prompt and 6135/6140 pair, DELETEI's unfolded name.
#
# ***AND IT LIFTS THE FUNCTIONS BY AST RATHER THAN COPYING THEM.***  A copied
# matcher passes for ever after the original changes.  If the lift finds fewer
# functions than it asked for, that is a failure and not a skip: an embedded
# BOM makes ParseFile return 0 errors and silently lose a function, which is
# exactly how a green run can mean nothing (CLAUDE.md, "verify a script loads").
$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot 'verify-vocverbs.ps1'

$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $target).Path, [ref]$t, [ref]$e)
if ($e.Count -ne 0) { throw "parse errors: $($e.Count)" }
$want = @('Test-Say','Get-SayCount')
$fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
       Where-Object { $want -contains $_.Name }
if ($fns.Count -ne $want.Count) { throw "lifted $($fns.Count) of $($want.Count) functions" }
foreach ($f in $fns) { . ([scriptblock]::Create($f.Extent.Text)) }
Write-Output ("lifted: " + (($fns | ForEach-Object { $_.Name }) -join ', '))
Write-Output ''

$Prefix = 'zzprf'; $vocSent = 'zzprfd'; $sysPtr = 'ZZPRFF'; $wFile = 'zzprfw'
$fail = 0
function T($name, $expected, $got) {
    $ok = ($expected -eq $got)
    if (-not $ok) { $script:fail++ }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if($ok){'PASS'}else{'FAIL'}), $name, $expected, $got)
}

# ---- entry 5 -------------------------------------------------------------
# FIXED build: .D ZZPRFD folds down and prompts naming the lower-case record.
$fix5 = @(
  '.L zzprfd', 'zzprfd', '001  S', '002  WHO',
  ".D ZZPRFD", "Delete VOC record 'zzprfd'? Y",
  '.L zzprfd', "'zzprfd' not found in VOC",
  '.D zzprfnosuch', "'zzprfnosuch' not found in VOC") -join "`n"
# DEFECTIVE build: both reads fail, 5043 names the record AS TYPED (upper),
# and the stale voc.rec then drives a prompt on the UNKNOWN name instead.
$bad5 = @(
  '.L zzprfd', 'zzprfd', '001  S', '002  WHO',
  ".D ZZPRFD", "'ZZPRFD' not found in VOC",
  '.L zzprfd', 'zzprfd', '001  S', '002  WHO',
  '.D zzprfnosuch', "Delete VOC record 'zzprfnosuch'? Y") -join "`n"

T 'e5 fixture anchor matches'        $true  (Test-Say $fix5 '^[ \t]*001[ \t]+S[ \t]*\r?$')
T 'e5 prompt: fixed'                 $true  (Test-Say $fix5 ("Delete VOC record '" + [regex]::Escape($vocSent) + "'"))
T 'e5 prompt: defect'                $false (Test-Say $bad5 ("Delete VOC record '" + [regex]::Escape($vocSent) + "'"))
T 'e5 disqualifier: fixed'           $false (Test-Say $fix5 ("'" + [regex]::Escape($vocSent.ToUpper()) + "' not found in VOC"))
T 'e5 disqualifier: defect'          $true  (Test-Say $bad5 ("'" + [regex]::Escape($vocSent.ToUpper()) + "' not found in VOC"))
T 'e5 gone-after: fixed'             $true  (Test-Say $fix5 ("'" + [regex]::Escape($vocSent) + "' not found in VOC"))
T 'e5 gone-after: defect'            $false (Test-Say $bad5 ("'" + [regex]::Escape($vocSent) + "' not found in VOC"))
T 'e5 prompt count: fixed'           1      (Get-SayCount $fix5 'Delete VOC record')
T 'e5 prompt count: defect'          1      (Get-SayCount $bad5 'Delete VOC record')

# ---- entry 13 ------------------------------------------------------------
$fix13 = "395 record(s) selected to select list 0"
$bad13 = "395 record(s) selected to select list "
$nil13 = "0 record(s) selected to select list 0"
T 'e13 number: fixed'                $true  (Test-Say $fix13 '\d+ record\(s\) selected to select list \d+')
T 'e13 number: defect'               $false (Test-Say $bad13 '\d+ record\(s\) selected to select list \d+')
T 'e13 dangling: fixed'              $false (Test-Say $fix13 'selected to select list[ \t]*\r?$')
T 'e13 dangling: defect'             $true  (Test-Say $bad13 'selected to select list[ \t]*\r?$')
T 'e13 null case caught'             $true  (Test-Say $nil13 '(^|[ \t])0 record\(s\) selected')
T 'e13 null case not falsely caught' $false (Test-Say $fix13 '(^|[ \t])0 record\(s\) selected')

# ---- entry 14 ------------------------------------------------------------
$fix14 = @('001  F', '002  @SDSYS/messages',
  'WARNING: The data part of this file is in the system account',
  'NO.QUERY was given and the data part of this file is in the system account, so the VOC reference is deleted and the file itself is left where it is.',
  'DICT part of file does not exist', "VOC entry 'ZZPRFF' deleted",
  "'ZZPRFF' not found in VOC") -join "`n"
$bad14 = @('001  F', '002  @SDSYS/messages',
  'WARNING: The data part of this file is in the system account',
  'Delete the file from the system account (Y/N)? N',
  'DICT part of file does not exist', "VOC entry 'ZZPRFF' deleted",
  "'ZZPRFF' not found in VOC") -join "`n"
T 'e14 pointer anchor'               $true  (Test-Say $fix14 '^[ \t]*002[ \t]+@SDSYS/messages[ \t]*\r?$')
T 'e14 10117: fixed'                 $true  (Test-Say $fix14 'NO\.QUERY was given and the data part of this file is in the system account')
T 'e14 10117: defect'                $false (Test-Say $bad14 'NO\.QUERY was given and the data part of this file is in the system account')
T 'e14 6146 absent: fixed'           $false (Test-Say $fix14 'Delete the file from the system account')
T 'e14 6146 absent: defect'          $true  (Test-Say $bad14 'Delete the file from the system account')
T 'e14 voc deleted'                  $true  (Test-Say $fix14 ("VOC entry '" + [regex]::Escape($sysPtr) + "' deleted"))

# ---- entry 15 ------------------------------------------------------------
$fix15 = @('Unrecognised index name (zzprfnope)', 'Deleted index F1', 'File has no indices') -join "`n"
$bad15 = @('Unrecognised index name (zzprfnope)', 'Unrecognised index name (f1)', 'Number of indices = 1') -join "`n"
T 'e15 control as typed'             $true  (Test-Say $fix15 ('Unrecognised index name \(' + [regex]::Escape($Prefix + 'nope') + '\)'))
T 'e15 control not upcased'          $false (Test-Say $fix15 ('Unrecognised index name \(' + [regex]::Escape(($Prefix + 'nope').ToUpper()) + '\)'))
T 'e15 deleted: fixed'               $true  (Test-Say $fix15 'Deleted index F1')
T 'e15 deleted: defect'              $false (Test-Say $bad15 'Deleted index F1')
T 'e15 disqualifier: fixed'          $false (Test-Say $fix15 'Unrecognised index name \(f1\)')
T 'e15 disqualifier: defect'         $true  (Test-Say $bad15 'Unrecognised index name \(f1\)')
T 'e15 after-state: fixed'           $true  (Test-Say $fix15 'File has no indices')
T 'e15 after-state: defect'          $false (Test-Say $bad15 'File has no indices')

# ---- entry 26 ------------------------------------------------------------
$fix26 = @("Created DATA part as C:\ProgramData\SD\sdsys\ZZPRFW",
  "DATA portion 'ZZPRFW' deleted", "DICT portion 'ZZPRFW.DIC' deleted",
  "VOC entry 'zzprfw' deleted") -join "`n"
$bad26 = @("Created DATA part as C:\ProgramData\SD\sdsys\ZZPRFW",
  "OK to delete DATA portion 'ZZPRFW'? N",
  "OK to delete DICT portion 'ZZPRFW.DIC'? N") -join "`n"
T 'e26 data prompt: fixed'           $false (Test-Say $fix26 'OK to delete DATA portion')
T 'e26 data prompt: defect'          $true  (Test-Say $bad26 'OK to delete DATA portion')
T 'e26 dict prompt: defect'          $true  (Test-Say $bad26 'OK to delete DICT portion')
T 'e26 data deleted: fixed'          $true  (Test-Say $fix26 ("DATA portion '" + [regex]::Escape($wFile.ToUpper()) + "' deleted"))
T 'e26 dict deleted: fixed'          $true  (Test-Say $fix26 ("DICT portion '" + [regex]::Escape($wFile.ToUpper() + '.DIC') + "' deleted"))
T 'e26 voc deleted: fixed'           $true  (Test-Say $fix26 ("VOC entry '" + [regex]::Escape($wFile) + "' deleted"))
T 'e26 voc deleted: defect'          $false (Test-Say $bad26 ("VOC entry '" + [regex]::Escape($wFile) + "' deleted"))

# ---- the case-sensitivity claim itself ----------------------------------
T 'case: upper pattern does not match lower text' $false (Test-Say "'zzprfd' not found in VOC" "'ZZPRFD' not found in VOC")
T 'case: lower pattern does not match upper text' $false (Test-Say "'ZZPRFD' not found in VOC" "'zzprfd' not found in VOC")
T 'null text is not a match'                      $false (Test-Say '' 'anything')
T 'null text counts zero'                         0      (Get-SayCount '' 'anything')

Write-Output ''
if ($fail -gt 0) { Write-Output ("FAILED: " + $fail + " row(s)"); exit 1 }
Write-Output 'all rows passed'
exit 0
