<#
.SYNOPSIS
    Drives Get-CoverageVerdict, the coverage decision inside
    verify-basicfuncs.ps1.  Free: no install, no elevation, no run token, no SD.

.DESCRIPTION
    RELEASE_1.1_FIXES.md 17 / BUGS_FROM_LINUX_PORT.md bug 8.  basicfuncs.sb used
    to close its exclusion list with "Everything else in BCOMP's intrinsics table
    is exercised below" - prose, which cannot be wrong out loud.  The claim is
    now mechanical, and THIS is what keeps the mechanism honest.

    ***WHY IT NEEDS ITS OWN TEST.***  The verdict it guards is reached only
    inside verify-basicfuncs.ps1, which refuses without an install that matches
    source, and whose interesting cases cannot be reached at all on a healthy
    tree: a clean tree has nothing unaccounted, nothing double-claimed and no
    stray label, so every row that matters is unreachable exactly when the tree
    is in the state you want it in.  Here they are all driven directly.

    ***IT LIFTS THE FUNCTION OUT BY AST*** rather than keeping a copy, so the
    thing under test is the thing that ships in the verifier and cannot drift
    from it.

    ***AND IT CARRIES A LIVE CONTROL PLUS A MUTANT.***  The live row runs the
    real BCOMP against the real basicfuncs.sb and requires a clean partition.
    The mutant rows take that same real text, break one thing in memory - a
    dropped declaration, a double claim - and require the verdict to go red
    NAMING the name.  Nothing on disk is touched.

.OUTPUTS
    Exit 0 every row passed, 1 a row failed.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifier = Join-Path $here 'verify-basicfuncs.ps1'
$probe    = Join-Path $here 'basicfuncs.sb'
$bcomp    = Join-Path $here '..\sdsys\gpl.bp\BCOMP'

$pass = 0
$fail = 0

function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}

# --- lift Get-CoverageVerdict out of the verifier ---------------------------
if (-not (Test-Path -LiteralPath $verifier)) {
    Write-Host "test-basicfuncscov-units: COULD NOT RUN - no $verifier"
    exit 1
}
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
           ($verifier -replace '\\', '/'), [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host "test-basicfuncscov-units: COULD NOT RUN - $verifier has $($errors.Count) parse error(s)"
    exit 1
}
$fn = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq 'Get-CoverageVerdict' }, $true)
if ($fn.Count -ne 1) {
    Write-Host "test-basicfuncscov-units: COULD NOT RUN - found $($fn.Count) Get-CoverageVerdict in $verifier, expected 1"
    exit 1
}
. ([scriptblock]::Create($fn[0].Extent.Text))

Write-Host 'test-basicfuncscov-units: driving Get-CoverageVerdict'
Write-Host ''

# --- fixtures ---------------------------------------------------------------
#
# A miniature BCOMP carrying BOTH tables, because telling them apart is the
# thing that was got wrong when this was first measured by hand.
$fakeBcomp = @'
   intrinsics = "ABS"                 ; intrinsic.opcodes = OP.ABS
   intrinsics<-1> = "ALPHA"           ; intrinsic.opcodes<-1> = OP.ALPHA
   intrinsics<-1> = "ARG"             ; intrinsic.opcodes<-1> = OP.ARG
   intrinsics<-1> = "ARG.COUNT"       ; intrinsic.opcodes<-1> = OP.ARGCT
   intrinsics<-1> = "CHANGE"          ; intrinsic.opcodes<-1> = OP.CHANGE
   intrinsics<-1> = "KEYIN"           ; intrinsic.opcodes<-1> = OP.KEYIN
   int.intrinsics = "ABORT.CAUSE"         ; int.intrinsic.opcodes = OP.ABTCAUSE
   int.intrinsics<-1> = "PHANTOM"         ; int.intrinsic.opcodes<-1> = OP.PHANTOM
'@

$cleanProbe = @'
* NOT.TESTED: KEYIN ARG ARG.COUNT
program p
   n = 'ABS' ; g = abs(-3) ; w = 3 ; gosub check
   n = 'ALPHA.yes' ; g = alpha('a') ; w = 1 ; gosub check
   n = 'CHANGE' ; g = change('aa','a','Z') ; w = 'ZZ' ; gosub check
   n = 'OP.add' ; g = 1 + 1 ; w = 2 ; gosub check
end
'@

$v = Get-CoverageVerdict $fakeBcomp $cleanProbe
Row 'the internal table is excluded: 6 known, not 8' ($v.Known -eq 6) "got $($v.Known)"
Row 'a clean fixture accounts for everything' `
    ($v.Unaccounted.Count -eq 0 -and $v.Both.Count -eq 0 -and $v.StrayLabels.Count -eq 0 -and $v.DeclaredUnknown.Count -eq 0) `
    "unaccounted=$($v.Unaccounted -join ',') both=$($v.Both -join ',') stray=$($v.StrayLabels -join ',') unknown=$($v.DeclaredUnknown -join ',')"
Row 'exercised 3, declared 3' ($v.Exercised -eq 3 -and $v.Declared -eq 3) `
    "exercised=$($v.Exercised) declared=$($v.Declared)"
Row 'an OP. label is an operator case, not a stray' ($v.OperatorLabels -eq 1) `
    "operator labels=$($v.OperatorLabels)"

# ARG.COUNT must not be read as ARG - longest match wins.
$argProbe = @'
* NOT.TESTED: KEYIN ARG CHANGE ALPHA
program p
   n = 'ARG.COUNT' ; g = arg.count() ; w = 1 ; gosub check
   n = 'ABS' ; g = abs(-1) ; w = 1 ; gosub check
end
'@
$v = Get-CoverageVerdict $fakeBcomp $argProbe
Row 'ARG.COUNT is not read as ARG (longest match wins)' `
    ($v.Unaccounted.Count -eq 0 -and $v.Both.Count -eq 0) `
    "unaccounted=$($v.Unaccounted -join ',') both=$($v.Both -join ',')"

# V2 - neither exercised nor declared.
$v2 = Get-CoverageVerdict $fakeBcomp @'
* NOT.TESTED: KEYIN ARG ARG.COUNT
program p
   n = 'ABS' ; g = abs(-3) ; w = 3 ; gosub check
   n = 'ALPHA' ; g = alpha('a') ; w = 1 ; gosub check
end
'@
Row 'V2 names an intrinsic that is neither exercised nor declared' `
    ($v2.Unaccounted -contains 'CHANGE' -and $v2.Unaccounted.Count -eq 1) `
    "unaccounted=$($v2.Unaccounted -join ',')"

# V3 - claimed both ways.  This is the shape DELETE had.
$v3 = Get-CoverageVerdict $fakeBcomp @'
* NOT.TESTED: KEYIN ARG ARG.COUNT CHANGE
program p
   n = 'ABS' ; g = abs(-3) ; w = 3 ; gosub check
   n = 'ALPHA' ; g = alpha('a') ; w = 1 ; gosub check
   n = 'CHANGE' ; g = change('aa','a','Z') ; w = 'ZZ' ; gosub check
end
'@
Row 'V3 names an intrinsic claimed BOTH ways' `
    ($v3.Both -contains 'CHANGE' -and $v3.Both.Count -eq 1) "both=$($v3.Both -join ',')"

# V4 - a declaration BCOMP has never heard of.  Prose on a declaration line
# lands here, which is how thirteen English words were caught while the header
# was being written.
$v4 = Get-CoverageVerdict $fakeBcomp @'
* NOT.TESTED: KEYIN ARG ARG.COUNT CHANGE
* NOT.TESTED: name below, reads every case label
program p
   n = 'ABS' ; g = abs(-3) ; w = 3 ; gosub check
   n = 'ALPHA' ; g = alpha('a') ; w = 1 ; gosub check
end
'@
Row 'V4 names declared words BCOMP does not know' `
    ($v4.DeclaredUnknown -contains 'name' -and $v4.DeclaredUnknown -contains 'below,') `
    "declaredUnknown=$($v4.DeclaredUnknown -join ',')"

# V5 - a label naming a function this tree does not have.  ADDS had this shape.
$v5 = Get-CoverageVerdict $fakeBcomp @'
* NOT.TESTED: KEYIN ARG ARG.COUNT CHANGE ALPHA
program p
   n = 'ABS' ; g = abs(-3) ; w = 3 ; gosub check
   n = 'ADDS.via.SUM' ; g = sum(v) ; w = 6 ; gosub check
end
'@
Row 'V5 names a case label that matches no intrinsic' `
    ($v5.StrayLabels -contains 'ADDS.via.SUM' -and $v5.StrayLabels.Count -eq 1) `
    "stray=$($v5.StrayLabels -join ',')"

# A comment quoting a case label is not coverage.  basicfuncs.sb really does
# carry one of these, explaining the INMAT relabelling.
$vc = Get-CoverageVerdict $fakeBcomp @'
* NOT.TESTED: KEYIN ARG ARG.COUNT CHANGE
* this used to read n = 'ALPHA.yes' and the code never called it
program p
   n = 'ABS' ; g = abs(-3) ; w = 3 ; gosub check
end
'@
Row 'a case label inside a comment is not counted as coverage' `
    ($vc.Unaccounted -contains 'ALPHA') "unaccounted=$($vc.Unaccounted -join ',')"

# ***THE COUNT TRAP.***  These sets are keyed by BASIC function names and BCOMP
# really has an intrinsic called COUNT, so $h.Count resolves to the VALUE OF
# THAT KEY instead of the tally - the tally came back as "True".  Every fixture
# above passed while it was broken, because none of them has a COUNT in it.
# This row pins the shape rather than the one site.
$countBcomp = @'
   intrinsics = "ABS"                 ; intrinsic.opcodes = OP.ABS
   intrinsics<-1> = "COUNT"           ; intrinsic.opcodes<-1> = OP.COUNT
   intrinsics<-1> = "KEYS"            ; intrinsic.opcodes<-1> = OP.KEYS
'@
$vk = Get-CoverageVerdict $countBcomp @'
* NOT.TESTED: KEYS
program p
   n = 'ABS' ; g = abs(-3) ; w = 3 ; gosub check
   n = 'COUNT' ; g = count('aa','a') ; w = 2 ; gosub check
end
'@
Row 'a key called COUNT does not shadow the tally' `
    ($vk.Exercised -is [int] -and $vk.Exercised -eq 2) "Exercised=$($vk.Exercised) type=$($vk.Exercised.GetType().Name)"
Row 'a key called KEYS does not shadow the key walk' `
    ($vk.Known -eq 3 -and $vk.Unaccounted.Count -eq 0) `
    "known=$($vk.Known) unaccounted=$($vk.Unaccounted -join ',')"

# The null case: no table, so every other row would pass vacuously.  V1 in the
# caller is what refuses it; here we only prove the count really is 0.
$vn = Get-CoverageVerdict 'nothing resembling a table' $cleanProbe
Row 'no table parses as 0 known, so V1 can refuse it' ($vn.Known -eq 0) "known=$($vn.Known)"

# --- the live control -------------------------------------------------------
Write-Host ''
if ((Test-Path -LiteralPath $bcomp) -and (Test-Path -LiteralPath $probe)) {
    $bText = Get-Content -LiteralPath $bcomp -Raw
    $pText = Get-Content -LiteralPath $probe -Raw
    $live  = Get-CoverageVerdict $bText $pText
    Write-Host ("  live: BCOMP {0} known, {1} exercised, {2} declared" -f $live.Known, $live.Exercised, $live.Declared)
    Row 'LIVE: the real tree has a clean partition' `
        ($live.Unaccounted.Count -eq 0 -and $live.Both.Count -eq 0 -and
         $live.StrayLabels.Count -eq 0 -and $live.DeclaredUnknown.Count -eq 0) `
        ("unaccounted=$($live.Unaccounted -join ',') both=$($live.Both -join ',') " +
         "stray=$($live.StrayLabels -join ',') unknown=$($live.DeclaredUnknown -join ',')")
    Row 'LIVE: exercised + declared accounts for every intrinsic' `
        (($live.Exercised + $live.Declared) -eq $live.Known) `
        "$($live.Exercised) + $($live.Declared) vs $($live.Known)"

    # MUTANT 1: drop one real declaration and require V2 to name it.
    $mut1 = $pText -replace 'NOT\.TESTED: CHGPHANT CONFIG UMASK CATALOGUED DIR', 'NOT.TESTED: CHGPHANT CONFIG UMASK CATALOGUED'
    $m1 = Get-CoverageVerdict $bText $mut1
    Row 'MUTANT: dropping DIR from the declarations turns V2 red, naming DIR' `
        ($mut1 -ne $pText -and $m1.Unaccounted -contains 'DIR') `
        "changed=$($mut1 -ne $pText) unaccounted=$($m1.Unaccounted -join ',')"

    # MUTANT 2: declare something that is also tested and require V3 to name it.
    $mut2 = $pText -replace 'NOT\.TESTED: KEYIN KEYINC', 'NOT.TESTED: ABS KEYIN KEYINC'
    $m2 = Get-CoverageVerdict $bText $mut2
    Row 'MUTANT: declaring ABS untested turns V3 red, naming ABS' `
        ($mut2 -ne $pText -and $m2.Both -contains 'ABS') `
        "changed=$($mut2 -ne $pText) both=$($m2.Both -join ',')"

    # The file on disk is untouched - these were all string mutations.
    Row 'MUTANT: nothing on disk was modified' `
        ((Get-Content -LiteralPath $probe -Raw) -eq $pText) 'basicfuncs.sb changed under the test'
} else {
    Row 'LIVE: the real BCOMP and probe are readable' $false "missing $bcomp or $probe"
}

Write-Host ''
Write-Host "test-basicfuncscov-units: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
