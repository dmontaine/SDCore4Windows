# test-upgradenocase-units.ps1 - drive Get-NocaseVerdict, the decision inside
# gplbld/upgrade-nocase.ps1 (RELEASE_1.1 5 D2's upgrade-conversion step),
# against fixtures.  No SD, no install, no elevation.
#
#   powershell -ExecutionPolicy Bypass -File ...\test-upgradenocase-units.ps1
#
# WHY THIS EXISTS.  upgrade-nocase.ps1 runs HIDDEN inside the installer, and its
# whole job is to tell three outcomes apart that all "finish": a clean
# conversion, a conversion that LEFT some files because they hold a case-only
# duplicate record id (a warning the administrator must see, exit 2), and a run
# that hit trouble (exit 1).  UPGRADE_NOCASE prints a similar block of text in
# each case.  Reaching any of them on a real machine costs an upgrade; here it
# costs a second, and a mutant control proves the verdict is not vacuous.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkipRun = $true
. (Join-Path $here 'upgrade-nocase.ps1')

$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name$(if($detail){"  ->  $detail"})" }
}

Check 'the function was lifted from upgrade-nocase.ps1' `
      ($null -ne (Get-Command Get-NocaseVerdict -ErrorAction SilentlyContinue))
if (-not (Get-Command Get-NocaseVerdict -ErrorAction SilentlyContinue)) {
    Write-Host 'test-upgradenocase-units: could not load Get-NocaseVerdict'; exit 1
}

# --- a clean run: converted everything, no duplicates ----------------------
$clean = @'
Checking every file for record ids that differ only by case...

Converted 37 of 37 file(s) to case insensitive ids.
COMPLETE
'@
$v = Get-NocaseVerdict $clean
Check 'clean: reaches COMPLETE'            $v.Complete
Check 'clean: converted 37 of 37'          ($v.Converted -eq 37 -and $v.Scanned -eq 37)
Check 'clean: no duplicate files'          ($v.DupFiles -eq 0 -and $v.DupIds -eq 0)
Check 'clean: no trouble'                  (-not $v.HadTrouble)

# --- a run that left duplicates (the warning path, exit 2) -----------------
$dup = @'
Checking every file for record ids that differ only by case...
WARNING: 2 file(s) hold 3 record id(s) that differ only by case. They were NOT converted:
File: C:\ProgramData\SD\user_accounts\acme\customers
      Jack / JACK
      smith / Smith
File: C:\ProgramData\SD\user_accounts\acme\parts
      widget / WIDGET
Rename or delete one id of each pair, then convert that file with CONFIGURE.FILE NO.CASE.
Converted 40 of 42 file(s) to case insensitive ids.
COMPLETE
'@
$v = Get-NocaseVerdict $dup
Check 'dup: reaches COMPLETE'              $v.Complete
Check 'dup: names 2 files with duplicates' ($v.DupFiles -eq 2) "got $($v.DupFiles)"
Check 'dup: counts 3 duplicate ids'        ($v.DupIds -eq 3) "got $($v.DupIds)"
Check 'dup: converted 40 of 42'            ($v.Converted -eq 40 -and $v.Scanned -eq 42)
Check 'dup: no trouble'                    (-not $v.HadTrouble)

# --- a run that hit trouble (exit 1) ---------------------------------------
$trouble = @'
Checking every file for record ids that differ only by case...
2 file(s) could not be read or rebuilt; see the lines above.
Converted 5 of 42 file(s) to case insensitive ids.
COMPLETE
'@
$v = Get-NocaseVerdict $trouble
Check 'trouble: HadTrouble is set'         $v.HadTrouble
Check 'trouble: still parses the counts'   ($v.Converted -eq 5 -and $v.Scanned -eq 42)

# --- an incomplete run (never reached COMPLETE) ----------------------------
$incomplete = @'
Checking every file for record ids that differ only by case...
Converted 3 of 42 file(s) to case insensitive ids.
'@
$v = Get-NocaseVerdict $incomplete
Check 'incomplete: Complete is false'      (-not $v.Complete)

# --- MUTANT CONTROL: the warning path must NOT read as clean ---------------
# If the verdict ignored the WARNING line, the dup fixture would look like a
# clean run and the installer would never surface it.  Assert the two verdicts
# actually differ where it matters.
$vc = Get-NocaseVerdict $clean
$vd = Get-NocaseVerdict $dup
Check 'MUTANT: clean and dup verdicts differ on DupFiles' `
      ($vc.DupFiles -ne $vd.DupFiles) "clean=$($vc.DupFiles) dup=$($vd.DupFiles)"

Write-Host ''
Write-Host "test-upgradenocase-units: $pass passed, $fail failed."
if ($fail) { exit 1 } else { exit 0 }
