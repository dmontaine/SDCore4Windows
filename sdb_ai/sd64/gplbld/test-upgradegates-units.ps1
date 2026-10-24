# test-upgradegates-units.ps1 - drive Get-GatesVerdict, the decision inside gplbld/upgrade-gates.ps1 (RELEASE_1.1 170, the step
# that carries each account's SH and OS.EXECUTE grant from sdsys\os.users to the register), against fixtures.  No SD, no
# install, no elevation.
#
#   powershell -ExecutionPolicy Bypass -File ...\test-upgradegates-units.ps1
#
# WHY THIS EXISTS.  upgrade-gates.ps1 runs HIDDEN inside the installer and its failure is silent in the worst direction: an
# account whose grant was not carried reads as denied the next morning, with the installer having reported success.  The
# verdict has to tell four outcomes apart - a walk that set accounts, a walk that found them already right, a repeat that did
# nothing on purpose, and a refusal or partial write that must NOT read as success - and the program's COMPLETE line alone does
# not (a half-written run that stops before the marker prints no COMPLETE, but a run that cannot open the register could
# still print other text).  Anchored on the wording the program prints on its positive path, with the failure wording as a
# disqualifier (CLAUDE.md, "A check must anchor on the SUCCESS wording").

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkipRun = $true
. (Join-Path $here 'upgrade-gates.ps1')

$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name$(if($detail){"  ->  $detail"})" }
}

Check 'the function was lifted from upgrade-gates.ps1' `
      ($null -ne (Get-Command Get-GatesVerdict -ErrorAction SilentlyContinue))
if (-not (Get-Command Get-GatesVerdict -ErrorAction SilentlyContinue)) {
    Write-Host 'test-upgradegates-units: could not load Get-GatesVerdict'; exit 1
}

# --- a clean first walk: three accounts set, one already right ----------------------------------------------------------------
$clean = @'
OS-access gates: set for 3 existing account(s) from os.users; 1 already right; 0 failed
COMPLETE
'@
$v = Get-GatesVerdict $clean
Check 'clean: reaches COMPLETE'               $v.Complete
Check 'clean: set 3, kept 1, failed 0'        ($v.Set -eq 3 -and $v.Kept -eq 1 -and $v.Failed -eq 0)
Check 'clean: not a repeat, not refused'      ((-not $v.Repeat) -and (-not $v.Refused))

# --- a repeat: the marker is there and nothing was done on purpose -----------------------------------------------------------
$repeat = @'
The OS-access gates were set for the existing accounts by an earlier install; nothing changed.
COMPLETE
'@
$v = Get-GatesVerdict $repeat
Check 'repeat: reaches COMPLETE'              $v.Complete
Check 'repeat: is recognised as a repeat'     $v.Repeat
Check 'repeat: reports no counts'             ($v.Set -eq -1)

# --- a write that failed: no COMPLETE, and the failure wording ----------------------------------------------------------------
$partial = @'
Cannot write the register record of jack
OS-access gates: set for 2 existing account(s) from os.users; 0 already right; 1 failed
The gates were NOT all set, so the marker is not written and the next install repeats this.
'@
$v = Get-GatesVerdict $partial
Check 'partial: does NOT reach COMPLETE'      (-not $v.Complete)
Check 'partial: counts the failure'           ($v.Failed -eq 1)
Check 'partial: is flagged refused'           $v.Refused

# --- no register -------------------------------------------------------------------------------------------------------------------
$noreg = 'Cannot open the account register: the OS-access gates were NOT set.'
$v = Get-GatesVerdict $noreg
Check 'no register: does NOT reach COMPLETE'  (-not $v.Complete)
Check 'no register: is flagged refused'       $v.Refused

# --- a COMPLETE line with the failure wording beside it must still be refused ------------------------------------------------------
$both = $partial + "`nCOMPLETE"
$v = Get-GatesVerdict $both
Check 'COMPLETE beside a failure is still refused' ($v.Complete -and $v.Refused -and $v.Failed -eq 1)

# --- MUTANT CONTROL: the failure verdict must differ from the clean one where it matters ----------------------------------------
$vc = Get-GatesVerdict $clean
$vp = Get-GatesVerdict $partial
Check 'MUTANT: clean and partial verdicts differ on Failed' ($vc.Failed -ne $vp.Failed) "clean=$($vc.Failed) partial=$($vp.Failed)"
Check 'MUTANT: clean and partial verdicts differ on Refused' ($vc.Refused -ne $vp.Refused)

# --- the edit gates verdict (UPGRADE_EDITGATES, S.64) ------------------------------------------------------------------------------
Check 'the edit gates function was lifted too' ($null -ne (Get-Command Get-EditGatesVerdict -ErrorAction SilentlyContinue))
$eclean = @'
Edit gates: switched on for 4 existing account(s); 1 already had all three set; 0 failed
COMPLETE
'@
$ev = Get-EditGatesVerdict $eclean
Check 'edit gates clean: COMPLETE, set 4, kept 1, failed 0' ($ev.Complete -and $ev.Set -eq 4 -and $ev.Kept -eq 1 -and $ev.Failed -eq 0 -and -not $ev.Refused)
$erepeat = @'
The edit gates were set for the existing accounts by an earlier install; nothing changed.
COMPLETE
'@
$ev = Get-EditGatesVerdict $erepeat
Check 'edit gates repeat: recognised, no counts' ($ev.Complete -and $ev.Repeat -and $ev.Set -eq -1)
$epartial = @'
Cannot write the register record of jack
Edit gates: switched on for 2 existing account(s); 0 already had all three set; 1 failed
The gates were NOT all set, so the marker is not written and the next install repeats this.
'@
$ev = Get-EditGatesVerdict $epartial
Check 'edit gates partial: not complete, one failure, refused' ((-not $ev.Complete) -and $ev.Failed -eq 1 -and $ev.Refused)
$ev = Get-EditGatesVerdict ($epartial + "`nCOMPLETE")
Check 'edit gates: COMPLETE beside a failure is still refused' ($ev.Complete -and $ev.Refused)
Check 'MUTANT: the SH-gates verdict does not read the edit gates line as its own count' `
      ((Get-GatesVerdict $eclean).Set -eq -1)

Write-Host ''
Write-Host "test-upgradegates-units: $pass passed, $fail failed."
if ($fail) { exit 1 } else { exit 0 }
