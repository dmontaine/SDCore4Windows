# test-diffcapture-units.ps1 - drive diff-capture.ps1 against built fixtures.
#
#   powershell -ExecutionPolicy Bypass -File test-diffcapture-units.ps1
#
# Free: no install, no elevation, no run token.  It writes its fixtures to a
# temp directory and removes them.
#
# ***EVERY REFUSAL IS PROVED RED BEFORE THE GREEN CASE IS BELIEVED.***  A diff
# tool's failure mode is not a wrong answer, it is a CONFIDENT EMPTY ONE: two
# captures with no manifest section compare equal, report zero disappearances
# and exit 0.  That is the shape PROJECT_STATUS's instrument rules call a test
# that passes because it did nothing, so the three refusals are the point of
# this file and the happy path is the easy part.

$ErrorActionPreference = 'Continue'

$here   = $PSScriptRoot
$script = Join-Path $here 'diff-capture.ps1'
if (-not (Test-Path -LiteralPath $script)) { Write-Output ('MISSING: ' + $script); exit 2 }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('diffcap-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$pass = 0
$fail = 0

function Check {
    param([string] $Name, [int] $Got, [int] $Want)
    if ($Got -eq $Want) {
        Write-Output ('  [PASS] {0,-52} rc={1} (want {2})' -f $Name, $Got, $Want)
        $script:pass++
    } else {
        Write-Output ('  [FAIL] {0,-52} rc={1} (want {2})' -f $Name, $Got, $Want)
        $script:fail++
    }
}

function New-Capture {
    # Builds a capture-state-shaped file.  $Rows is the D/F body of the one
    # tree; $Extra is appended inside the manifest section.
    param(
        [string]   $Path,
        [string[]] $Rows,
        [switch]   $NoManifest,
        [string]   $Extra = '',
        [string]   $Tree  = 'C:\Program Files\SD'
    )
    $b = New-Object System.Collections.ArrayList
    [void]$b.Add('capture-state: label   fixture')
    [void]$b.Add('capture-state: elevated True')
    [void]$b.Add('')
    [void]$b.Add('=== SD trees ====================================================')
    [void]$b.Add('  PRESENT  C:\Program Files\SD  (3 entries)')
    if (-not $NoManifest) {
        [void]$b.Add('')
        [void]$b.Add('=== SD tree manifest (PRE_RELEASE 134) ==========================')
        [void]$b.Add('  Diff a before-capture against an after-capture.  Every line that')
        [void]$b.Add('')
        [void]$b.Add('  --- ' + $Tree)
        [void]$b.Add('      ' + $Rows.Count + ' entries (0 directories, ' + $Rows.Count + ' files)')
        foreach ($r in $Rows) { [void]$b.Add('      ' + $r) }
        if ($Extra -ne '') { [void]$b.Add($Extra) }
    }
    [void]$b.Add('')
    [void]$b.Add('=== installed SD product ========================================')
    [void]$b.Add('  SD Core W1.0-0  ver=W1.0-0')
    $b | Out-File -FilePath $Path -Encoding utf8
}

function Run-Diff {
    param([string] $Before, [string] $After, [string[]] $ExtraArgs = @())
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script,
           '-Before', $Before, '-After', $After) + $ExtraArgs
    & powershell.exe @a | Out-Null
    return $LASTEXITCODE
}

Write-Output 'test-diffcapture-units: driving diff-capture.ps1 against fixtures'
Write-Output ('  script  : ' + $script)
Write-Output ('  fixtures: ' + $tmp)
Write-Output ''

$rows3 = @('F \a.txt', 'F \b.txt', 'D \sdsys\cat')

# --- 1. IDENTICAL CAPTURES PASS --------------------------------------------
$p1 = Join-Path $tmp 'same-before.txt'
$p2 = Join-Path $tmp 'same-after.txt'
New-Capture -Path $p1 -Rows $rows3
New-Capture -Path $p2 -Rows $rows3
Check '1: identical manifests pass' (Run-Diff $p1 $p2) 0

# --- 2. A DISAPPEARANCE FAILS ----------------------------------------------
# This is 120 and 132 in miniature: a preserved directory that ships empty is
# gone after the reinstall and nothing else changed.
$p3 = Join-Path $tmp 'gone-after.txt'
New-Capture -Path $p3 -Rows @('F \a.txt', 'F \b.txt')
Check '2: a directory that vanished is caught' (Run-Diff $p1 $p3) 1

# --- 3. AN ADDITION ALONE PASSES -------------------------------------------
# The invariant is one-directional: files the site adds are not violations.
$p4 = Join-Path $tmp 'added-after.txt'
New-Capture -Path $p4 -Rows ($rows3 + @('F \sdsys\cat\newthing'))
Check '3: an addition alone is not a violation' (Run-Diff $p1 $p4) 0

# --- 4. NO MANIFEST IS REFUSED, NOT PASSED ---------------------------------
# The confident-empty case.  Two summary-only captures have nothing to compare
# and would otherwise report zero disappearances and exit 0.
$p5 = Join-Path $tmp 'nomanifest-a.txt'
$p6 = Join-Path $tmp 'nomanifest-b.txt'
New-Capture -Path $p5 -Rows $rows3 -NoManifest
New-Capture -Path $p6 -Rows $rows3 -NoManifest
Check '4: two summary-only captures are REFUSED' (Run-Diff $p5 $p6) 2

# --- 4a. ONE SIDE MISSING ITS MANIFEST IS ALSO REFUSED ---------------------
Check '4a: one side without a manifest is REFUSED' (Run-Diff $p1 $p5) 2

# --- 5. NOT COMPARABLE IS REFUSED ------------------------------------------
# A subtree readable before and denied after appears as mass deletion; the
# capture says so and this must not diff it anyway.
$p7 = Join-Path $tmp 'notcomparable.txt'
New-Capture -Path $p7 -Rows $rows3 -Extra '      NOT COMPARABLE: 3 path(s) could not be read'
Check '5: a NOT COMPARABLE capture is REFUSED' (Run-Diff $p1 $p7) 2

# --- 6. A MISSING FILE IS REFUSED ------------------------------------------
Check '6: a capture file that is not there is REFUSED' (Run-Diff $p1 (Join-Path $tmp 'nope.txt')) 2

# --- 7. A WHOLE TREE DISAPPEARING FAILS ------------------------------------
$p8 = Join-Path $tmp 'othertree.txt'
New-Capture -Path $p8 -Rows $rows3 -Tree 'C:\ProgramData\SD'
Check '7: a whole tree gone is caught' (Run-Diff $p1 $p8) 1

# --- 8. -Expected SUPPRESSES A NAMED DISAPPEARANCE -------------------------
# 134 names classes that are expected to differ.  Declaring one must change the
# verdict, or the switch is decoration.
Check '8: -Expected turns case 2 green' (Run-Diff $p1 $p3 @('-Expected', '\sdsys\cat')) 0

# --- 9. -Expected DOES NOT SUPPRESS ANYTHING ELSE --------------------------
# The control on 8: the same flag naming a DIFFERENT path must leave it red.
Check '9: -Expected for another path leaves it red' (Run-Diff $p1 $p3 @('-Expected', '\sdsys\prt')) 1

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ''
Write-Output '=============================================================='
Write-Output ('{0} of {1} checks passed.' -f $pass, ($pass + $fail))

# REFUSE THE NULL CASE: a run that asserted nothing must not be a pass.
if (($pass + $fail) -eq 0) {
    Write-Output 'test-diffcapture-units: REFUSED - no checks ran at all.'
    exit 2
}
if ($fail -gt 0) {
    Write-Output 'test-diffcapture-units: FAILED'
    exit 1
}
Write-Output 'test-diffcapture-units: PASSED - the three refusals fire, and a'
Write-Output '  disappearance is caught while an addition is not.'
exit 0
