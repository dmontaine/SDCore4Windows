<#
.SYNOPSIS
    Free-tier guard: every password a gplbld script GENERATES for SD must satisfy SD's
    own complexity rule.  RELEASE_1.1 83.  No install, no elevation, no run token.

.DESCRIPTION
    ***WHAT IT CATCHES.***  RELEASE_1.1 75 (19 Sep 2026) made SD refuse a password
    lacking any of lower, upper, digit and symbol (gpl.bp/pw_complex).  A refused
    password does not fail: CREATE.ACCOUNT and MODIFY.PASSWORD RE-PROMPT, and each
    re-prompt eats the next piped line - the confirmation, then OFF - until SD sits at
    EOF, where it spins.  So a verifier that feeds SD a weak password HANGS, for the
    full timeout, and reads as a product failure.  Nothing in the tree reported it:
    the wording lint proves phrases, the acctkeywords guard proves keywords, and no
    suite had run since 75 landed.  It was found by the owner's first elevated run of
    the converted verifiers (20 Sep 2026): accountacl hung on a random Windows-side
    password and apiname on its API password.

    Two shapes were in the tree, NINETEEN SITES IN ELEVEN FILES (measured by running
    this guard against a reconstruction of the pre-fix tree, which it fails; an earlier
    hand count of "17 in 14" from a grep was wrong):

      GeneratePassword(24, 6)                     with no suffix.  Refused 5.7 % of the
                                                  time (measured: 1,140 of 20,000, all but
                                                  eight for want of a digit).  A flake,
                                                  which is worse than a certainty.
      base64 alphanumerics + 'aA1'                NO SYMBOL, refused EVERY time.

    ***HOW IT DECIDES, AND WHY IT IS STATIC.***  It finds every assignment to a
    variable named like a password whose right-hand side is a generator (GeneratePassword,
    a base64-alphanumeric build, or a GUID build) and unions the character classes of the
    STRING LITERALS THAT ARE OPERANDS OF THE TOP-LEVEL "+" CHAIN.  Those are the only
    characters the expression GUARANTEES; the random part guarantees nothing.
    ***NOT EVERY LITERAL IN THE EXPRESSION*** - the base64 shape carries the regex
    '[^A-Za-z0-9]', whose characters look like a symbol, an upper and a lower and a
    digit, and counting them would pass exactly the shape that fails 100 % of the time.
    A control below plants that trap on purpose.

    ***IT IS A RULE COPY, TIED TO THE BASIC.***  The classes are SD's, copied from
    gpl.bp/pw_complex (length >= 8; lower 97-122, upper 65-90, digit 48-57, anything else
    printable 32-126 is a symbol; all four required).  The header of
    test-pwcomplex-units.ps1 is where the BASIC is tied to the other copies; here the
    ranges are ALSO asserted present in the BASIC source, so a change to the rule fails
    this file loudly instead of leaving a stale copy.

    ***IT DOES NOT PROVE A PASSWORD IS SAFE FOR ITS CONTEXT*** - cmd, bash -lc, an ssh
    askpass helper.  That is why the symbol used for the SD credentials is '-'.

    Exit 0 all checks passed, 1 a check failed, 2 it could not measure.
#>

param([string]$Gplbld = '')

$ErrorActionPreference = 'Stop'
if ($Gplbld -eq '') { $Gplbld = Split-Path -Parent $PSCommandPath }
$Gplbld = $Gplbld.TrimEnd('\', '/')

$script:pass = 0
$script:fail = 0
$script:calls = 0
function Check([string]$label, [bool]$ok, [string]$detail = '') {
    $script:calls++
    if ($ok) { $script:pass++; Write-Output ('  [PASS] ' + $label) }
    else     { $script:fail++; Write-Output ('  [FAIL] ' + $label + '   <- ' + $detail) }
}

Write-Output 'test-pwgen-units: generated passwords vs SD''s pw_complex (RELEASE_1.1 75, 83)'
Write-Output ('  gplbld : ' + $Gplbld)
if (-not (Test-Path -LiteralPath $Gplbld)) { Write-Output 'REFUSED: gplbld not found.'; exit 2 }

# --- the rule, and its tie to the BASIC ----------------------------------
function Get-GuaranteedClasses([string[]]$literals) {
    $l = $false; $u = $false; $d = $false; $s = $false; $bad = $false
    foreach ($lit in $literals) {
        foreach ($ch in $lit.ToCharArray()) {
            $c = [int]$ch
            if     ($c -ge 97 -and $c -le 122) { $l = $true }
            elseif ($c -ge 65 -and $c -le 90)  { $u = $true }
            elseif ($c -ge 48 -and $c -le 57)  { $d = $true }
            elseif ($c -ge 32 -and $c -le 126) { $s = $true }
            else { $bad = $true }
        }
    }
    $missing = @()
    if (-not $l) { $missing += 'lower' }
    if (-not $u) { $missing += 'upper' }
    if (-not $d) { $missing += 'digit' }
    if (-not $s) { $missing += 'symbol' }
    return @{ Missing = $missing; Ok = ($missing.Count -eq 0 -and -not $bad); NonPrintable = $bad }
}

$bp = Join-Path $Gplbld '../sdsys/gpl.bp/pw_complex'
if (-not (Test-Path -LiteralPath $bp)) { Write-Output ('REFUSED: ' + $bp + ' not found - cannot tie the rule to SD''s BASIC.'); exit 2 }
$bpText = [IO.File]::ReadAllText($bp)
Check 'the BASIC still says: length below 8 is refused' ($bpText -match 'pw\.len\s*<\s*8') 'the minimum changed - re-derive this file''s rule'
Check 'the BASIC still says: lower is 97-122' ($bpText -match 'pw\.c\s*>=\s*97\s+and\s+pw\.c\s*<=\s*122') 'the lower range changed'
Check 'the BASIC still says: upper is 65-90' ($bpText -match 'pw\.c\s*>=\s*65\s+and\s+pw\.c\s*<=\s*90') 'the upper range changed'
Check 'the BASIC still says: digit is 48-57' ($bpText -match 'pw\.c\s*>=\s*48\s+and\s+pw\.c\s*<=\s*57') 'the digit range changed'
Check 'the BASIC still says: other printable 32-126 is a symbol' ($bpText -match 'pw\.c\s*>=\s*32\s+and\s+pw\.c\s*<=\s*126') 'the symbol range changed'
Check 'the BASIC still requires all four classes' (($bpText -match 'not\(got\.lower\)') -and ($bpText -match 'not\(got\.upper\)') -and ($bpText -match 'not\(got\.digit\)') -and ($bpText -match 'not\(got\.symbol\)')) 'a class is no longer required'

# --- the finder -----------------------------------------------------------
function Get-PlusOperands($node) {
    if ($node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
        $node.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) {
        # @() ON EACH SIDE: a one-element result is UNROLLED on return, so the
        # callee hands back a bare AST node and "+" on it throws op_Addition.
        $l = @(Get-PlusOperands $node.Left)
        $r = @(Get-PlusOperands $node.Right)
        return @($l + $r)
    }
    return @($node)
}

# Returns @( @{ Var; Line; Shape; Literals } ) for every password generator in the text.
function Find-Generators([string]$text, [string]$file) {
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tok, [ref]$err)
    $found = @()
    $assigns = $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
    foreach ($a in $assigns) {
        if ($a.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
        $var = $a.Left.VariablePath.UserPath
        if ($var -notmatch '(?i)pw|pass') { continue }
        $rhsText = $a.Right.Extent.Text
        $shape = ''
        if     ($rhsText -match 'GeneratePassword\s*\(') { $shape = 'GeneratePassword' }
        elseif ($rhsText -match 'ToBase64String' -and $rhsText -match '-replace' -and $rhsText -match 'A-Za-z0-9') { $shape = 'base64-alnum' }
        elseif ($rhsText -match 'NewGuid\s*\(' -and $var -match '(?i)pw$') { $shape = 'guid' }
        if ($shape -eq '') { continue }
        # ***THE FIRST DRAFT WRAPPED THIS IN A PipelineAst AND EXTRACTED NOTHING.***
        # For "$x = expr" the assignment's Right IS a CommandExpressionAst; only a
        # pipeline on the right ("$x = a | b") makes it a PipelineAst.  With no
        # literals extracted every generator reported "missing all four classes", and
        # the bare-GeneratePassword control PASSED BY COINCIDENCE - "all four missing"
        # is also what nothing-extracted looks like.  It was the OTHER controls, the
        # ones expecting a pass, that gave it away.  Both shapes are handled.
        $expr = $null
        if ($a.Right -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $expr = $a.Right.Expression
        } elseif ($a.Right -is [System.Management.Automation.Language.PipelineAst] -and
                  $a.Right.PipelineElements.Count -eq 1 -and
                  $a.Right.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $expr = $a.Right.PipelineElements[0].Expression
        }
        $lits = @()
        if ($null -ne $expr) {
            foreach ($op in (Get-PlusOperands $expr)) {
                if ($op -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $lits += [string]$op.Value }
            }
        }
        $found += @{ File = $file; Var = $var; Line = $a.Extent.StartLineNumber; Shape = $shape; Literals = $lits }
    }
    return $found
}

# --- CONTROLS: the finder and the rule, on planted snippets ----------------
Write-Output ''
Write-Output '== controls: planted snippets'
$snip = {
    param($code)
    $g = @(Find-Generators $code 'snippet')
    if ($g.Count -ne 1) { return @{ N = $g.Count; Ok = $null; Missing = @() } }
    $r = Get-GuaranteedClasses $g[0].Literals
    return @{ N = 1; Ok = $r.Ok; Missing = $r.Missing }
}
$b64 = '$pw = ([Convert]::ToBase64String($bytes) -replace ''[^A-Za-z0-9]'', '''')'
$c = & $snip '$winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6)'
Check 'CONTROL: a bare GeneratePassword(24, 6) is FOUND and FAILS (all four classes unguaranteed)' ($c.N -eq 1 -and $c.Ok -eq $false -and $c.Missing.Count -eq 4) "N=$($c.N) Ok=$($c.Ok) missing=$($c.Missing -join '+')"
$c = & $snip ($b64 + " + 'aA1'")
Check 'CONTROL: base64 alphanumerics + ''aA1'' FAILS for want of a SYMBOL - the regex literal is NOT counted' ($c.N -eq 1 -and $c.Ok -eq $false -and ($c.Missing -join '+') -eq 'symbol') "N=$($c.N) Ok=$($c.Ok) missing=$($c.Missing -join '+')"
$c = & $snip '$winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6) + ''aA'''
Check 'CONTROL: GeneratePassword + ''aA'' FAILS for want of a digit and a symbol' ($c.N -eq 1 -and $c.Ok -eq $false -and ($c.Missing -join '+') -eq 'digit+symbol') ($c.Missing -join '+')
$c = & $snip '$winPw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + ''aA1!'''
Check 'CONTROL: GeneratePassword(20, 4) + ''aA1!'' is FOUND and PASSES' ($c.N -eq 1 -and $c.Ok -eq $true) "N=$($c.N) Ok=$($c.Ok) missing=$($c.Missing -join '+')"
$c = & $snip ($b64 + " + '-aA1'")
Check 'CONTROL: base64 alphanumerics + ''-aA1'' PASSES (the fix)' ($c.N -eq 1 -and $c.Ok -eq $true) "N=$($c.N) Ok=$($c.Ok) missing=$($c.Missing -join '+')"
$c = & $snip '$pw = ''Pd-'' + [guid]::NewGuid().ToString(''N'').Substring(0, 12) + ''!7'''
Check 'CONTROL: ''Pd-'' + guid + ''!7'' (profiledir''s shape, a prefix AND a suffix) PASSES' ($c.N -eq 1 -and $c.Ok -eq $true) "N=$($c.N) Ok=$($c.Ok) missing=$($c.Missing -join '+')"
$c = & $snip '$notASecret = [System.Web.Security.Membership]::GeneratePassword(24, 6)'
Check 'CONTROL: a variable that is not named like a password is NOT scanned (scope of the finder)' ($c.N -eq 0) "N=$($c.N)"

# --- the live tree --------------------------------------------------------
Write-Output ''
Write-Output '== the live tree'
$files = @(Get-ChildItem -LiteralPath $Gplbld -Filter '*.ps1' -File | Where-Object { $_.Name -notlike 'test-*' } | Sort-Object Name)
Write-Output ('  scripts scanned : ' + $files.Count)
if ($files.Count -lt 100) { Write-Output 'REFUSED: fewer than 100 scripts - the directory is wrong.'; exit 2 }

$all = @()
foreach ($f in $files) { $all += @(Find-Generators ([IO.File]::ReadAllText($f.FullName)) $f.Name) }
$byShape = @{}; foreach ($g in $all) { $byShape[$g.Shape] = 1 + [int]$byShape[$g.Shape] }
Write-Output ('  generators found: ' + $all.Count + '   (' + (($byShape.Keys | Sort-Object | ForEach-Object { $_ + '=' + $byShape[$_] }) -join ', ') + ')')
Check 'the finder found generators at all (>= 25 in the tree as measured 20 Sep 2026)' ($all.Count -ge 25) ("found " + $all.Count + ' - a finder that finds nothing passes everything')
foreach ($s in 'GeneratePassword', 'base64-alnum', 'guid') {
    Check ("the finder found at least one '" + $s + "' generator") ([int]$byShape[$s] -ge 1) 'a shape vanished, so its check is vacuous'
}

$weak = @()
foreach ($g in $all) {
    $r = Get-GuaranteedClasses $g.Literals
    if (-not $r.Ok) { $weak += ('{0}:{1}  ${2}  ({3})  missing: {4}' -f $g.File, $g.Line, $g.Var, $g.Shape, ($r.Missing -join '+')) }
}
Check ('EVERY generator guarantees lower, upper, digit and symbol (' + $all.Count + ' checked)') ($weak.Count -eq 0) ("`n      " + ($weak -join "`n      "))

Write-Output ''
if ($script:pass + $script:fail -lt $script:calls) {
    Write-Output ('REFUSED: the counters do not add up ({0} + {1} < {2}).' -f $script:pass, $script:fail, $script:calls); exit 2
}
Write-Output ('test-pwgen-units: {0} passed, {1} failed.' -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
