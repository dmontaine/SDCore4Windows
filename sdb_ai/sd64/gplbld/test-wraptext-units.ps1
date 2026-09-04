# test-wraptext-units.ps1 - Write-Wrapped, the text wrapper finish-install.ps1
# uses for everything it says on the page that ends an install.
#
#   powershell -File test-wraptext-units.ps1
#
# Exit 0 every check passed, 1 a check failed, 2 the test could not be run.
#
# PRE_RELEASE_FIXES 155.  The owner's complaint was that the password page's
# formatting is inconsistent, and one cause was that the per-step $Purpose lines
# were handed to Write-Host as ONE LINE EACH: the console wrapped them wherever
# it happened to end, which on his screen broke "its" across two lines mid-word.
# Write-Wrapped is the fix, and this drives it.
#
# ***THE REASON THIS EXISTS AS A STANDING CHECK IS A BUG IT ALREADY CAUGHT.***
# The first version of the wrapper split on -split '\s+', which silently
# collapsed every DOUBLE space in the file - the two after a full stop, and the
# two on each side of "modify.password sdsys" that set the command off from its
# sentence.  That is a formatting regression introduced by the fix for a
# formatting complaint, it would have shipped looking fine to a compiler, and
# nothing else in the tree reads that page.
#
# NO INSTALL, NO ELEVATION, NO RUN TOKEN, NO SD.  It lifts the function out of
# the shipped script BY AST, so the thing under test is the shipped copy and
# cannot drift from a second copy pasted in here.
#
# NOT INSTALLED AND NOT SHIPPED - it must be on assert-current.ps1's
# $neverShipped list, or it reports the tree stale because it exists.
# finish-install.ps1 itself is NOT on that list and must not be: it ships.

$ErrorActionPreference = 'Stop'

$script:fails = 0
$script:count = 0

function Note {
    param([string]$What, $Expected, $Got)
    $script:count++
    $ok = ([string]$Expected -ceq [string]$Got)
    if (-not $ok) { $script:fails++ }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
                  $(if ($ok) { 'PASS' } else { 'FAIL' }), $What, $Expected, $Got)
}

$src = Join-Path $PSScriptRoot 'finish-install.ps1'
Write-Output "test-wraptext-units: subject $src"
if (-not (Test-Path -LiteralPath $src)) {
    Write-Output 'test-wraptext-units: refusing - finish-install.ps1 is not there'
    exit 2
}

$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$t, [ref]$e)
if ($e.Count) {
    Write-Output "test-wraptext-units: refusing - finish-install.ps1 has $($e.Count) parse error(s)"
    $e | ForEach-Object { Write-Output ("  line " + $_.Extent.StartLineNumber + ": " + $_.Message) }
    exit 2
}

# ***LIFTED BY AST, AND THE NULL CASE IS REFUSED OUT LOUD.***  A FindAll that
# matched nothing would leave every check below comparing against an error and
# could score however the comparison fell - so finding exactly one is a
# precondition, not a check.
$fn = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $n.Name -eq 'Write-Wrapped' }, $true))
if ($fn.Count -ne 1) {
    Write-Output "test-wraptext-units: refusing - expected 1 Write-Wrapped in finish-install.ps1, found $($fn.Count)"
    exit 2
}
. ([scriptblock]::Create($fn[0].Extent.Text))
Write-Output "test-wraptext-units: lifted Write-Wrapped ($($fn[0].Extent.Text.Length) chars)"
Write-Output ''

# Write-Wrapped writes to the host, so capture stream 6 and split it back.
function Wrap {
    param([string]$Text, [string]$Indent = '', [int]$Width = 74)
    $raw = Write-Wrapped -Text $Text -Indent $Indent -Width $Width 6>&1 | Out-String
    return @($raw -split "`r?`n" | Where-Object { $_ -ne '' })
}

# --------------------------------------------------------------- the width
# The real string from finish-install.ps1's 2-of-2 call - the one that broke.
$purpose = 'This is where SD puts you when you run it as administrator.  It is a ' +
           'different account from the one above and needs its own password.'

$lines = Wrap -Text $purpose
Note 'it wraps at all (more than one line)' $true ($lines.Count -gt 1)
$longest = ($lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
Note 'no line exceeds the width' $true ($longest -le 74)
# ZERO IS SUSPICIOUS, NOT CLEAN: a wrapper that emitted nothing would satisfy
# "no line exceeds the width" perfectly.
Note 'and it emitted something' $true ($longest -gt 0)
# ***A "no word is broken across lines" ROW WAS WRITTEN HERE AND REMOVED, AND
# THE REASON IS WORTH THE COMMENT.***  It was `-match '\w-?\r?\n\w'`, which
# matches a letter, a newline and a letter - i.e. EVERY correctly wrapped pair
# of lines.  It went red against a wrapper that was working, on its first run.
# That is the same class as anchoring a check on a string the failure also
# carries: a pattern that cannot distinguish the two outcomes is not a check.
# The property it was reaching for - that no token is split - is exactly what
# the round trip below proves, by comparing the whole token sequence.
Note 'the text survives the round trip' `
     (($purpose -replace '\s+', ' ')) (($lines -join ' ') -replace '\s+', ' ')

# ------------------------------------------------------ the gaps, which is
# the check the first version of this wrapper failed.
Write-Output ''
Note 'two spaces after a full stop survive' 'Alpha beta.  Gamma delta.' `
     ((Wrap -Text 'Alpha beta.  Gamma delta.') -join '')
Note 'the double-spaced command keeps both gaps' 'Change it with  modify.password sdsys  from inside SD.' `
     ((Wrap -Text 'Change it with  modify.password sdsys  from inside SD.') -join '')
# A gap AT a line break is dropped, which is where a gap should disappear.
$brk = Wrap -Text ('word. ' * 30) -Width 30
Note 'a wrapped line never ends in a space' $false `
     ([bool](@($brk | Where-Object { $_ -ne $_.TrimEnd() }).Count))

# ------------------------------------------------------------- the indent
Write-Output ''
$ind = Wrap -Text $purpose -Indent '  '
$longestIndented = ($ind | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
Note 'the indent counts AGAINST the width, not on top of it' $true ($longestIndented -le 74)
Note 'every indented line carries the indent' $true `
     (@($ind | Where-Object { $_.StartsWith('  ') }).Count -eq $ind.Count)

# ------------------------------------------------------------ the null case
Write-Output ''
# A caller that passed an empty string must not silently print nothing: the step
# would lose its explanation and look deliberate.
Note 'empty input says so rather than printing nothing' '(no text supplied)' `
     ((Wrap -Text '') -join '')
Note 'whitespace-only input says so too' '(no text supplied)' `
     ((Wrap -Text "   `t  ") -join '')

# ------------------------------------------- a word longer than the width
# It cannot be wrapped, and it must not be dropped or truncated.
$long = 'A ' + ('x' * 90) + ' end'
$lw = Wrap -Text $long -Width 40
Note 'an over-long word is emitted whole, not truncated' $true `
     ([bool](($lw -join "`n") -match ('x' * 90)))

Write-Output ''
Write-Output ("test-wraptext-units: {0} passed, {1} failed" -f ($count - $fails), $fails)
if ($fails) { exit 1 }
exit 0
