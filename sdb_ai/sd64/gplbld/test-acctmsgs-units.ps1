# test-acctmsgs-units.ps1 - drive verify-acctmsgs.ps1's password chooser with
# policy values this machine does not have, and read the policy this one does.
#
#   powershell -File test-acctmsgs-units.ps1
#
# Exit 0 every row passed, 1 a row failed.  Needs no SD and no account.  It
# reads the password policy and CHANGES NOTHING.
#
# WHY IT EXISTS.  Entry 22's "Windows refused" arm recorded SKIP on 28 Aug 2026
# because the password it sent was a GUESS - 150 characters, on the reasoning
# that 127 is a hard SAM limit - and Set-LocalUser accepted it.  The replacement
# picks the password FROM THE POLICY, and that choice is now the part most worth
# testing, because it is the part that decides whether the arm measures anything
# at all.  A machine with no rule in force cannot exercise the interesting
# branches, so they are driven with synthetic values instead.
#
# ***THE "accepted" EXPECTATION IS A ROW, NOT A COMMENT.***  With no rule in
# force the chooser must say so and expect acceptance - a chooser that always
# claimed "refused" would turn every SKIP into a silent failure to notice.
#
# Get-PasswordPolicy is exercised for real but only REPORTED, not asserted:
# what it returns depends on the host, and unelevated it may legitimately fail
# to read anything.  The row that matters is that it returns the shape the
# chooser expects and does not throw.

$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot 'verify-acctmsgs.ps1'

$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$t, [ref]$e)
if ($e.Count -ne 0) { throw "parse errors in ${target}: $($e.Count)" }

# REFUSE THE NULL CASE: an embedded BOM makes ParseFile return 0 errors and
# silently lose a function, so lifting fewer than asked for is a failure.
$want = @('Select-RefusedPassword', 'Get-PasswordPolicy')
$fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
       Where-Object { $want -contains $_.Name }
if ($fns.Count -ne $want.Count) { throw "lifted $($fns.Count) of $($want.Count) functions" }
foreach ($f in $fns) { . ([scriptblock]::Create($f.Extent.Text)) }
Write-Output ("lifted: " + (($fns | ForEach-Object { $_.Name }) -join ', '))
Write-Output ''

$fail = 0
function T($name, $expected, $got) {
    $ok = ($expected -eq $got)
    if (-not $ok) { $script:fail++ }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if($ok){'PASS'}else{'FAIL'}), $name, $expected, $got)
}

# --- a minimum length in force: one character short, whatever else is set ----
foreach ($min in @(2, 8, 14, 20)) {
    $c = Select-RefusedPassword $min 0
    T ("min $min -> length is min-1")        ($min - 1) $c.Password.Length
    T ("min $min -> expects refusal")        'refused'  $c.Expect
}

# LENGTH WINS OVER COMPLEXITY, because a length rule is arithmetic and a
# complexity rule is a judgement about character classes.
$c = Select-RefusedPassword 14 1
T 'min 14 + complexity -> still the length branch' 13 $c.Password.Length
T 'min 14 + complexity -> expects refusal'         'refused' $c.Expect

# --- complexity alone ---------------------------------------------------------
$c = Select-RefusedPassword 0 1
T 'complexity only -> 14 characters'            14 $c.Password.Length
T 'complexity only -> one character class'      $true ($c.Password -cmatch '^[a-z]+$')
T 'complexity only -> expects refusal'          'refused' $c.Expect
# min 1 is below the length branch's threshold of 2, so complexity must still
# fire - and the result must not be SHORTER than the minimum, or it would be
# refused for the wrong reason and the evidence would name the wrong rule.
$c = Select-RefusedPassword 1 1
T 'min 1 + complexity -> complexity branch'     $true ($c.Password -cmatch '^[a-z]+$')
T 'min 1 + complexity -> not short of the min'  $true ($c.Password.Length -ge 1)

# --- no rule in force ---------------------------------------------------------
foreach ($p in @(@(0,0), @(0,-1), @(-1,-1), @(1,0))) {
    $c = Select-RefusedPassword $p[0] $p[1]
    T ("min $($p[0]) cx $($p[1]) -> the 150-character attempt") 150 $c.Password.Length
    T ("min $($p[0]) cx $($p[1]) -> expects ACCEPTANCE")        'accepted' $c.Expect
}

# --- the seed cannot be overrun ----------------------------------------------
$c = Select-RefusedPassword 100000 0
T 'an absurd minimum does not throw'            $true ($c.Password.Length -gt 0)

# --- every chosen password is safe to send down the pipe ---------------------
# SD reads it with "input HIDDEN" on a line, and Invoke-SD joins commands with
# LF - so anything containing a newline would desynchronise the whole session,
# and anything past TERM's 200 columns could be truncated into a DIFFERENT
# password than the one printed.
foreach ($p in @(@(14,1), @(0,1), @(0,0), @(8,0))) {
    $c = Select-RefusedPassword $p[0] $p[1]
    T ("min $($p[0]) cx $($p[1]) -> no newline in the password") $false ($c.Password -match "[\r\n]")
    T ("min $($p[0]) cx $($p[1]) -> fits in 200 columns")        $true  ($c.Password.Length -le 200)
}

# --- the real policy, reported and shape-checked, never asserted -------------
Write-Output ''
$pol = Get-PasswordPolicy
Write-Output ("this host: minimum length " + $pol.MinLength + ", complexity " +
              $pol.Complexity + ", read by " + $pol.Source)
T 'Get-PasswordPolicy returns a MinLength'   $true ($null -ne $pol.MinLength)
T 'Get-PasswordPolicy returns a Complexity'  $true ($null -ne $pol.Complexity)
T 'Get-PasswordPolicy names its source'      $true ([string]$pol.Source -ne '')
$live = Select-RefusedPassword $pol.MinLength $pol.Complexity
Write-Output ("arm B would send " + $live.Password.Length + " characters and expect it to be " +
              $live.Expect + " - " + $live.Why)

Write-Output ''
if ($fail -gt 0) { Write-Output ("FAILED: " + $fail + " row(s)"); exit 1 }
Write-Output 'all rows passed'
exit 0
