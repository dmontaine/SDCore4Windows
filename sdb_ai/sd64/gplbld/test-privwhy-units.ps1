# test-privwhy-units.ps1 - guard PRE_RELEASE_FIXES.md 96's tri-state
#
#   powershell -File test-privwhy-units.ps1
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# WHAT IT GUARDS, AND WHY IT IS NOT THE COMPILER'S JOB.  Entry 96 made the
# three privilege predicates say WHY they answered, through a PRIV_WHY
# out-parameter, because "no" and "I could not tell" had been the same FALSE.
# The compiler catches most of what can go wrong afterwards - -Wall is on, so
# an enum member with no case in priv_why_text() warns, and a caller using the
# old zero-argument form will not compile.
#
# IT CANNOT CATCH THE ONE THAT MATTERS: a NEW failure exit added to a predicate
# that returns FALSE without setting *why.  That compiles cleanly, warns about
# nothing, and silently reintroduces exactly the defect 96 was filed for - the
# refusal goes back to stating a reason nobody established.  There is no
# run-time symptom to notice either, because the fault paths need an induced
# name-service failure to reach.
#
# SO THE RULE IS STRUCTURAL: inside IsAdmin(), IsElevated() and os_permitted(),
# every "return FALSE" must have "*why =" within the few lines above it.
#
# ONE SITE IS EXEMPT AND IT IS NAMED, NOT PATTERN-MATCHED.  os_permitted()'s
# open() failure assigns *why only when errno is not ENOENT, because a missing
# os.users record is the DESIGNED no - that file's own banner says "MISSING
# FILE OR MISSING RECORD MEANS NO... the safe direction".  It still matches the
# rule, since the assignment is there; the conditional is the point, so the
# check asserts the ENOENT test is present rather than allowing a bare return.

$ErrorActionPreference = 'Stop'

$sd64   = Split-Path $PSScriptRoot -Parent
$hdr    = Join-Path $sd64 'gplsrc\linuxlb.h'
$lib    = Join-Path $sd64 'gplsrc\linuxlb.c'
$sh     = Join-Path $sd64 'gplsrc\op_sh.c'
$kerr   = Join-Path $sd64 'gplsrc\k_error.c'

$pass = 0
$fail = 0

function Check($name, $expected, $got) {
    $ok = ($expected -eq $got)
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $expected, $got)
}

foreach ($p in @($hdr, $lib, $sh, $kerr)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("test-privwhy-units: {0} does not exist - nothing could be measured." -f $p)
        exit 2
    }
}

Write-Output 'test-privwhy-units - PRE_RELEASE_FIXES.md 96, the privilege tri-state'
Write-Output ("  header: {0}" -f $hdr)
Write-Output ''

$hdrText  = Get-Content -LiteralPath $hdr -Raw
$libText  = Get-Content -LiteralPath $lib -Raw
$shText   = Get-Content -LiteralPath $sh  -Raw
$kerrText = Get-Content -LiteralPath $kerr -Raw

# --- 1. The enum, and priv_why_text() covering all of it.
Write-Output '=== the PRIV_WHY enum and its text mapping ==='

$enumBlock = [regex]::Match($hdrText, 'typedef enum \{(.*?)\} PRIV_WHY;', 'Singleline')
Check 'the PRIV_WHY enum is in linuxlb.h' $true $enumBlock.Success
if (-not $enumBlock.Success) {
    Write-Output 'test-privwhy-units: no enum to check against - refusing to report on nothing.'
    exit 2
}

$members = @([regex]::Matches($enumBlock.Groups[1].Value, '\bPRIV_[A-Z_]+') |
             ForEach-Object { $_.Value } | Select-Object -Unique)
Check 'the enum has more than the ANSWERED member' $true ($members.Count -gt 1)
Write-Output ("       members: {0}" -f ($members -join ', '))

# PRIV_ANSWERED must be the zero value: every caller tests "why != PRIV_ANSWERED".
Check 'PRIV_ANSWERED is defined as 0' $true `
      ($enumBlock.Groups[1].Value -match 'PRIV_ANSWERED\s*=\s*0')

$textFn = [regex]::Match($libText, 'char\*\s*priv_why_text\(PRIV_WHY why\)\s*\{(.*?)\n\}', 'Singleline')
Check 'priv_why_text() is in linuxlb.c' $true $textFn.Success
if ($textFn.Success) {
    $cases = @([regex]::Matches($textFn.Groups[1].Value, 'case\s+(PRIV_[A-Z_]+)\s*:') |
               ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $missing = @($members | Where-Object { $cases -notcontains $_ })
    $extra   = @($cases   | Where-Object { $members -notcontains $_ })
    Check 'every enum member has a case in priv_why_text' 0 $missing.Count
    if ($missing.Count -gt 0) { Write-Output ("       missing: {0}" -f ($missing -join ', ')) }
    Check 'priv_why_text has no case for a non-member' 0 $extra.Count
}

# --- 2. THE RULE THIS FILE EXISTS FOR.
Write-Output ''
Write-Output '=== every failure exit sets *why ==='

# Pull a function body by brace matching, so a nested "}" cannot end it early.
function Get-Body([string]$text, [string]$signature) {
    $i = $text.IndexOf($signature)
    if ($i -lt 0) { return $null }
    $open = $text.IndexOf('{', $i)
    if ($open -lt 0) { return $null }
    $depth = 0
    for ($j = $open; $j -lt $text.Length; $j++) {
        if ($text[$j] -eq '{') { $depth++ }
        elseif ($text[$j] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $text.Substring($open, $j - $open + 1) }
        }
    }
    return $null
}

$predicates = @(
    @{ Name = 'IsAdmin';      Text = $libText; Sig = 'bool IsAdmin(PRIV_WHY* why)' },
    @{ Name = 'IsElevated';   Text = $libText; Sig = 'bool IsElevated(PRIV_WHY* why)' },
    @{ Name = 'os_permitted'; Text = $shText;  Sig = 'Private bool os_permitted(PRIV_WHY* why) {' }
)

$checkedReturns = 0
foreach ($p in $predicates) {
    $body = Get-Body $p.Text $p.Sig
    Check ("{0}() body was found and takes PRIV_WHY*" -f $p.Name) $true ($null -ne $body)
    if ($null -eq $body) { continue }

    # It must set the default before doing anything, or an exit that forgets
    # to assign would inherit whatever the caller's variable happened to hold.
    Check ("{0}() sets PRIV_ANSWERED up front" -f $p.Name) $true `
          ($body -match '\*why\s*=\s*PRIV_ANSWERED')

    $lines = $body -split "`r?`n"
    $bad = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch 'return\s+FALSE\s*;') { continue }
        $checkedReturns++
        $lo = [Math]::Max(0, $i - 4)
        $window = ($lines[$lo..$i] -join "`n")
        if ($window -notmatch '\*why\s*=') { $bad += ($lines[$i].Trim()) }
    }
    Check ("{0}(): every 'return FALSE' assigns *why nearby" -f $p.Name) 0 $bad.Count
    foreach ($b in $bad) { Write-Output ("       unguarded: {0}" -f $b) }
}

# REFUSE THE NULL CASE.  If the shapes above ever stop matching, every loop
# runs zero times and every count is 0 - which would read as a clean pass.
Check 'some return-FALSE sites were actually examined' $true ($checkedReturns -ge 8)
Write-Output ("       examined {0} 'return FALSE' site(s)" -f $checkedReturns)

# --- 3. The ENOENT discrimination, which is deliberate and easy to "tidy" away.
Write-Output ''
Write-Output '=== os.users: a missing record is the designed NO, not a failure ==='
$osBody = Get-Body $shText 'Private bool os_permitted(PRIV_WHY* why) {'
if ($null -ne $osBody) {
    Check 'the open() failure tests errno against ENOENT' $true `
          ($osBody -match 'errno\s*!=\s*ENOENT')
    Check 'it assigns PRIV_OPEN_FAILED for other errno values' $true `
          ($osBody -match 'PRIV_OPEN_FAILED')
}

# --- 4. The logging helper is where the linker needs it, not beside the
#        predicates.  linuxlb.o is linked into sdfix/sdtic/sdconv/sdidx, which
#        do not carry log_message - putting it back would break those links.
Write-Output ''
Write-Output '=== the log helper stays out of linuxlb.c ==='
Check 'priv_log_undetermined is defined in k_error.c' $true `
      ($kerrText -match 'void priv_log_undetermined\(char\* what, PRIV_WHY why\)')
Check 'linuxlb.c does not define it' $false `
      ($libText -match 'void priv_log_undetermined\(char\* what, PRIV_WHY why\)\s*\{')
Check 'it uses log_message, not log_printf' $true `
      ($kerrText -match 'priv_log_undetermined[\s\S]{0,900}?log_message\(msg\)')

Write-Output ''
Write-Output ("test-privwhy-units: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
