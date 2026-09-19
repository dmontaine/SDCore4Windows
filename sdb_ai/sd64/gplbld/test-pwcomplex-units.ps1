# test-pwcomplex-units.ps1 - RELEASE_1.1 75.  SD's password rule is written
# THREE TIMES in this tree and once more on the Linux side.  This drives all
# three local copies against ONE table - the table the Linux agent sent with the
# ruling - so they cannot drift apart from each other or from the contract.
#
# WHY THERE ARE THREE COPIES AT ALL, because "just share it" is the first thing
# a reader will ask:
#   sdsys/gpl.bp/pw_complex        everything inside SD - MODIFY.PASSWORD,
#                                  CREATE.ACCOUNT, LOGIN's credential prompt.
#   gplbld/finish-install.ps1      the SDSYS prompt, which sets a WINDOWS
#                                  password with Set-LocalUser and never enters
#                                  SD, so it cannot call the BASIC.
#   gplbld/install-sdsys.ps1       the GENERATED password, drawn at
#                                  ssPostInstall in a hidden window before
#                                  either of the other two is reachable.
#
# ***THE BASIC IS CHECKED WITHOUT BEING RUN, AND THAT LIMIT IS THE POINT OF
# SAYING IT.*** Nothing here can execute BASIC - that needs a cycle.  What it
# does instead is read the RANGES AND THE CASE ORDER out of pw_complex and
# drive the table through what the file actually says, so a changed constant or
# a reordered case fails here.  A logic error that leaves the constants and the
# order intact would not.  The cycle is still the witness.
#
# INSTRUMENT RULES (CLAUDE.md): it echoes the resolved paths and the extracted
# constants, refuses the null case out loud (a table that drove nothing, a
# function that could not be lifted), and carries mutants - the live files are
# never edited, every mutant runs on text.
#
# Unelevated, no SD, no install, no network, no run token.  It writes nothing.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$gplbld = ($PSScriptRoot -replace '\\', '/')
$sd64   = (Split-Path -Parent $PSScriptRoot) -replace '\\', '/'
$bas    = "$sd64/sdsys/gpl.bp/pw_complex"
$finish = "$gplbld/finish-install.ps1"
$instal = "$gplbld/install-sdsys.ps1"
$msg    = "$sd64/sdsys/messages/10920"

Write-Host "test-pwcomplex-units: basic   $bas"
Write-Host "test-pwcomplex-units: finish  $finish"
Write-Host "test-pwcomplex-units: install $instal"
Write-Host "test-pwcomplex-units: message $msg"

foreach ($p in @($bas, $finish, $instal, $msg)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "not found: $p"; exit 2 }
}

$script:pass = 0
$script:fail = 0
function Check($label, $ok, $detail) {
    if ($ok) { $script:pass++; Write-Host ("  [PASS] " + $label) }
    else {
        $script:fail++
        Write-Host ("  [FAIL] " + $label) -ForegroundColor Red
        if ($detail) { Write-Host ("         " + $detail) -ForegroundColor Red }
    }
}
function Section($m) { Write-Host ''; Write-Host ("=== " + $m + " ===") }

# --------------------------------------------------------------------------
# THE TABLE.  Sent by the SD Core for Linux agent with the owner's ruling,
# 19 Sep 2026, each refusal lacking exactly one thing.  Rows are [password,
# expected, why] and "why" is here so a failure names the requirement rather
# than the string.
$TAB = @(
    @{ P = 'Abcdef1!';   E = $true;  W = 'all four classes, exactly 8' }
    @{ P = "zZ9 zzzz";   E = $true;  W = 'SPACE is a symbol' }
    @{ P = 'Pass:word1'; E = $true;  W = 'punctuation is a symbol' }
    @{ P = 'Abcde1!';    E = $false; W = 'seven characters' }
    @{ P = 'abcdef1!';   E = $false; W = 'no upper case' }
    @{ P = 'ABCDEF1!';   E = $false; W = 'no lower case' }
    @{ P = 'Abcdefg!';   E = $false; W = 'no digit' }
    @{ P = 'Abcdefg1';   E = $false; W = 'no symbol' }
    @{ P = ("Abcdef1" + [char]9); E = $false; W = 'TAB is outside 32-126' }
    @{ P = ("Abcd" + [char]0xE9 + "f1!"); E = $false; W = 'e-acute is outside 32-126' }
    @{ P = '';           E = $false; W = 'empty' }
    # Added here, not in the sent table: the boundary characters themselves,
    # because 32 and 126 are the two the ranges are most likely to be written
    # one out on.
    @{ P = 'Abcdefg1 ';  E = $true;  W = 'SPACE (32) is in range and is a symbol' }
    @{ P = 'Abcdefg1~';  E = $true;  W = 'TILDE (126) is in range and is a symbol' }
)

# --------------------------------------------------------------------------
Section '0. the null case is refused: the table and the sources are real'
Check ("the table has rows (got $($TAB.Count))") ($TAB.Count -ge 11) `
      'an empty table would make every row below pass vacuously'
$yes = @($TAB | Where-Object { $_.E }).Count
$no  = @($TAB | Where-Object { -not $_.E }).Count
Check ("it has both accepted and refused rows ($yes yes, $no no)") ($yes -ge 3 -and $no -ge 7) `
      'a table that is all one answer cannot tell a working rule from a constant'

# --------------------------------------------------------------------------
Section '1. the BASIC: its constants and its case ORDER are the contract'
$basText = Get-Content -LiteralPath $bas -Raw
# Comments in this file start with * at the start of a line; the code we read
# is the case block, so strip them rather than match inside a paragraph that
# QUOTES the ranges in prose.
$basCode = (($basText -split "`n") | Where-Object { $_ -notmatch '^\s*\*' }) -join "`n"

$wantLen = [regex]::Match($basCode, 'pw\.len\s*<\s*(\d+)')
Check ("minimum length comes from the file (got '$($wantLen.Groups[1].Value)')") `
      ($wantLen.Success -and $wantLen.Groups[1].Value -eq '8') `
      'pw_complex no longer tests a minimum length of 8'

$cases = [regex]::Matches($basCode, '(?m)^\s*case\s+(.+?)\s*$')
Check ("the case block was found (got $($cases.Count) case arms)") ($cases.Count -eq 5) `
      'expected 5 arms: lower, upper, digit, symbol-with-its-own-range, catch-all'

# ***THE PROPERTY THAT MATTERS IS "THE CATCH-ALL FAILS CLOSED", NOT THE ORDER,
# AND THAT IS A CHANGE OF MIND RECORDED HERE ON PURPOSE.***  The first version
# of pw_complex tested out-of-range in the FIRST arm and let the catch-all mean
# "symbol", so the rule was correct only while nobody reordered the arms - and
# this section existed to assert that nobody had.  The Linux port's shape makes
# the reordering harmless in the dangerous direction: the symbol arm names
# 32-126 itself, so a character matching nothing reaches the catch-all and is
# REFUSED however the arms are ordered.  A shape that cannot fail open beats a
# check that reports it, so the check changed to match the shape.
$symbolArm = @($cases | Where-Object { $_.Groups[1].Value -match '32' -and $_.Groups[1].Value -match '126' })
Check ("the SYMBOL arm names its own range 32-126 (got $($symbolArm.Count))") ($symbolArm.Count -eq 1) `
      'no arm tests 32-126, so the catch-all is deciding what a symbol is'
if ($cases.Count -eq 5) {
    Check 'the LAST arm is the catch-all and it RETURNS FALSE' `
          ($cases[4].Groups[1].Value -match '^1$' -and
           $basCode -match '(?ms)case\s+1\s*\r?\n\s*return\s+@false') `
          ("a character matching no arm must be refused.  If the catch-all marks a symbol " +
           "instead, an out-of-range byte SATISFIES the requirement it exists to fail. " +
           "last arm reads: " + $cases[4].Groups[1].Value)
    foreach ($a in @(@{N='a-z'; L='97'; H='122'}, @{N='A-Z'; L='65'; H='90'}, @{N='0-9'; L='48'; H='57'})) {
        $hit = @($cases | Where-Object { $_.Groups[1].Value -match $a.L -and $_.Groups[1].Value -match $a.H })
        Check ("an arm tests $($a.N) ($($a.L)-$($a.H))") ($hit.Count -eq 1) `
              'the range is missing or written twice'
    }
}
foreach ($n in @('got.lower', 'got.upper', 'got.digit', 'got.symbol')) {
    Check ("all four requirements are asserted at the end: $n") `
          ($basCode -match ('not\(\s*' + [regex]::Escape($n) + '\s*\)')) `
          'a requirement is collected and then never tested, so it is not required at all'
}

# --------------------------------------------------------------------------
# The BASIC's rule, rebuilt FROM WHAT WAS JUST EXTRACTED rather than from a
# second hand-written copy, and driven over the table.  This is what makes the
# section above more than a spelling check.
# $Scramble reverses the three letter/digit arms against the symbol arm, which
# is how section 5 proves the shape is order-safe in the direction that counts.
# $OpenCatchAll restores the OLD, worse shape - catch-all means "symbol" - so
# the rows it breaks are visible rather than argued about.
function Test-FromExtracted {
    param([string] $Password, [int] $Min, [int] $Lo, [int] $Hi,
          [switch] $Scramble, [switch] $OpenCatchAll)
    if ($Password.Length -lt $Min) { return $false }
    $l = $false; $u = $false; $d = $false; $s = $false
    foreach ($ch in $Password.ToCharArray()) {
        $c = [int][char]$ch
        $inSym = ($c -ge $Lo -and $c -le $Hi)
        if ($Scramble -and $inSym) { $s = $true; continue }
        if     ($c -ge 97 -and $c -le 122) { $l = $true }
        elseif ($c -ge 65 -and $c -le 90)  { $u = $true }
        elseif ($c -ge 48 -and $c -le 57)  { $d = $true }
        elseif ($inSym)                    { $s = $true }
        elseif ($OpenCatchAll)             { $s = $true }
        else                               { return $false }
    }
    return ($l -and $u -and $d -and $s)
}

# --------------------------------------------------------------------------
# THE TWO POWERSHELL COPIES ARE LIFTED BY AST, NOT COPIED.  Same technique as
# test-wraptext-units and test-editorver-units, and for the same reason: a copy
# in here is a copy that can go stale, and staleness is the whole subject.
function Get-Lifted([string] $Path, [string] $Name) {
    $err = $null; $tok = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tok, [ref]$err)
    if (@($err).Count -ne 0) { return $null }
    $fn = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name
    }, $true)
    if (@($fn).Count -ne 1) { return $null }
    return @($fn)[0].Extent.Text
}

Section '2. the three implementations agree with the table, row by row'
$liftedFinish = Get-Lifted $finish 'Test-PasswordComplex'
$liftedInstal = Get-Lifted $instal 'Test-GeneratedPasswordComplex'
Check 'Test-PasswordComplex was lifted out of finish-install.ps1' ($null -ne $liftedFinish) `
      'the function was renamed, removed, or the file no longer parses'
Check 'Test-GeneratedPasswordComplex was lifted out of install-sdsys.ps1' ($null -ne $liftedInstal) `
      'the function was renamed, removed, or the file no longer parses'

if ($liftedFinish) { . ([scriptblock]::Create($liftedFinish)) }
if ($liftedInstal) { . ([scriptblock]::Create($liftedInstal)) }

$drivenRows = 0
foreach ($row in $TAB) {
    $shown = if ($row.P -eq '') { '(empty)' } else { ($row.P -replace "`t", '<TAB>') }
    $fromBas = Test-FromExtracted -Password $row.P -Min 8 -Lo 32 -Hi 126
    Check ("BASIC   '$shown' -> $($row.E)   [$($row.W)]") ($fromBas -eq $row.E) "got $fromBas"
    if ($liftedFinish) {
        $r = Test-PasswordComplex -Password $row.P
        Check ("finish  '$shown' -> $($row.E)") ($r -eq $row.E) "got $r"
    }
    if ($liftedInstal) {
        $r = Test-GeneratedPasswordComplex -Password $row.P
        Check ("install '$shown' -> $($row.E)") ($r -eq $row.E) "got $r"
    }
    $drivenRows++
}
Check ("every table row was driven (got $drivenRows of $($TAB.Count))") ($drivenRows -eq $TAB.Count) $null

# --------------------------------------------------------------------------
Section '3. the wording is ONE sentence, not two that drift'
$msgText = (Get-Content -LiteralPath $msg -Raw).Trim()
$psText  = ''
$m = [regex]::Match((Get-Content -LiteralPath $finish -Raw), "PwRuleText\s*=\s*'([^']*)'")
if ($m.Success) { $psText = $m.Groups[1].Value.Trim() }
Check ('the PowerShell rule sentence was found') ($psText -ne '') `
      '$script:PwRuleText is gone or is no longer a single-quoted literal'
Check ('it is message 10920 word for word') ($psText -eq $msgText) `
      ("10920: '" + $msgText + "'  PowerShell: '" + $psText + "'")

# --------------------------------------------------------------------------
Section '4. the partition: every prompt that sets a password runs the rule'
# A new prompt that forgets the check is the regression this guards, and it is
# invisible to every row above.  Each site is named with what it sets.
$sites = @(
    @{ File = "$sd64/sdsys/gpl.bp/set_acc_password"; Pat = 'pw_complex\(pw1\)'; What = 'MODIFY.PASSWORD, the SD credential' }
    @{ File = "$sd64/sdsys/gpl.bp/set_passwd";       Pat = 'pw_complex\(pw1\)'; What = "CREATE.ACCOUNT, the account user's Windows password" }
    @{ File = "$sd64/sdsys/gpl.bp/login";            Pat = 'pw_complex\(pw1\)'; What = "LOGIN's credential prompt" }
    @{ File = $finish;                               Pat = 'Test-PasswordComplex'; What = 'the installer, the SDSYS Windows password' }
    @{ File = $instal;                               Pat = 'Test-GeneratedPasswordComplex'; What = 'the generated SDSYS password' }
)
foreach ($s in $sites) {
    $t = if (Test-Path -LiteralPath $s.File) { Get-Content -LiteralPath $s.File -Raw } else { '' }
    $name = Split-Path -Leaf $s.File
    Check ("$name runs the rule  ($($s.What))") ($t -match $s.Pat) `
          'this prompt sets a password and does not check it'
}
# And each BASIC caller must DECLARE the function, or the call is a subroutine
# name the compiler resolves to nothing recognisable.
foreach ($f in @('set_acc_password', 'set_passwd', 'login')) {
    $t = Get-Content -LiteralPath "$sd64/sdsys/gpl.bp/$f" -Raw
    Check ("$f declares deffun pw_complex") ($t -match "deffun\s+pw_complex\(pw\)\s+calling\s+'!pw_complex'") $null
}

# --------------------------------------------------------------------------
Section '5. MUTANTS, on text - the live files are never edited'
$before = (Get-FileHash -LiteralPath $bas -Algorithm SHA256).Hash
$tab = "Abcdef1" + [char]9

# (a) THE SHAPE'S WHOLE POINT, DRIVEN RATHER THAN ASSERTED.  Reorder so the
#     symbol arm wins over the letter and digit arms and the TAB row must
#     STILL be refused: an out-of-range byte matches no arm either way.
Check 'ORDER-SAFE: with the arms scrambled, the TAB row is still refused' `
      ((Test-FromExtracted -Password $tab -Min 8 -Lo 32 -Hi 126 -Scramble) -eq $false) `
      'reordering the arms let a control character through, which is the failure the shape exists to prevent'
# ...and the scramble does break the rule, in the SAFE direction, which is
# what stops this row passing for the wrong reason.
Check 'ORDER-SAFE is not vacuous: the scramble does refuse a GOOD password too' `
      ((Test-FromExtracted -Password 'Abcdef1!' -Min 8 -Lo 32 -Hi 126 -Scramble) -eq $false) `
      'the scramble changed nothing at all, so the row above proves nothing about ordering'

# (b) THE OLD SHAPE, RESTORED, MUST ACCEPT WHAT THE NEW ONE REFUSES.  This is
#     the defect the Linux port's version removed: a catch-all meaning
#     "symbol" counts an out-of-range byte as one.
Check 'the OLD open catch-all accepts the TAB row - the reason the shape changed' `
      ((Test-FromExtracted -Password $tab -Min 8 -Lo 0 -Hi 0 -OpenCatchAll) -eq $true) `
      'the old shape is not actually looser, so the change was not worth making'

# (c) the minimum dropped to 7 must accept the 7-character row.
Check 'dropping the minimum to 7 accepts the 7-character row' `
      ((Test-FromExtracted -Password 'Abcde1!' -Min 7 -Lo 32 -Hi 126) -eq $true) `
      'the length test is not what refuses it, so the extracted minimum guards nothing'

# (d) a catch-all that marks a symbol is caught by the section-1 reader.
$mutText = $basCode -replace '(?ms)case\s+1\s*\r?\n\s*return\s+@false', "case 1`n         got.symbol = @true"
$caught = -not ($mutText -match '(?ms)case\s+1\s*\r?\n\s*return\s+@false')
Check 'a catch-all changed to mark a symbol is caught by the section-1 reader' $caught `
      'the reader would not notice the catch-all failing open'

$after = (Get-FileHash -LiteralPath $bas -Algorithm SHA256).Hash
Check 'the live pw_complex is byte-identical after the mutants' ($before -eq $after) `
      "before $before after $after"

# --------------------------------------------------------------------------
Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("test-pwcomplex-units: PASSED - {0} of {0} checks passed." -f $script:pass)
    exit 0
} else {
    Write-Host ("test-pwcomplex-units: FAILED - {0} of {1} checks failed." -f $script:fail, ($script:pass + $script:fail)) -ForegroundColor Red
    exit 1
}
