# strip-comments.ps1 - remove line and block comments from a build script, so a
# scanner can tell a USE of a name from a REMARK about one.  Dot-sourced; it
# defines functions and runs nothing.
#
# 02 Sep 26 Windows port - PRE_RELEASE_FIXES 143.  IT EXISTS BECAUSE THE SAME
# DEFECT ARRIVED TWICE FROM DIFFERENT DIRECTIONS, and the second time the fix
# and its own documentation cancelled each other:
#
#   * PRE_RELEASE 131 - test-retired-wording-units.ps1 scanned sd.iss WITHOUT
#     stripping, and this tree's habit is to QUOTE the retired wording in a
#     comment beside the fix.  The lint cried wolf on the documentation of the
#     very fix it guards.  It grew the two Pascal strippers below.
#   * PRE_RELEASE 143 - assert-current.ps1 decides whether a gplbld script SHIPS
#     by looking for a quote or a slash before its name in stage.py or sd.iss.
#     sd.iss:4569 names probe-taskdialog.iss with no separator on purpose, and
#     then the NEXT SENTENCE quotes "gplbld/probe-taskdialog.iss" to explain why
#     that spelling is wrong - so the explanation re-tripped the trap it
#     documents, and the 21:28:26 cycle reported the probe as shipping when
#     C:\Program Files\SD does not contain it.
#
# ***SO THE STRIPPER IS SHARED RATHER THAN COPIED.***  suite-only.ps1 is the
# precedent and the reasoning is identical: two copies of a scanner that
# disagree would answer DIFFERENT questions about the same file, and this tree
# has already paid for that shape (CRED_SET/MODIFYA, api-firewall/ssh-firewall).
# gplbld/test-stripcomments-units.ps1 drives every branch with no install, no
# elevation and no run token.
#
# ***THE TWO CALLERS ERR IN OPPOSITE DIRECTIONS, WHICH IS WHY THIS FILE DOES NOT
# DECIDE ANYTHING.***  For the wording lint, over-stripping hides a retired
# phrase - a false NEGATIVE, and its header calls that the safe way for a lint
# to fail.  For assert-current, over-stripping hides a real ship line and yields
# a false CURRENT, which its header calls the expensive direction.  A shared
# stripper cannot be tuned for both, so it strips conservatively and EACH CALLER
# CARRIES ITS OWN CONTROL: assert-current asserts a known-shipping name still
# matches after the strip, and refuses if it does not.
#
# NO Set-StrictMode AT FILE SCOPE.  A dot-sourced file's file-scope strict mode
# binds the CALLER, so a strict setting here would silently change how both
# callers behave - the trap suite-only.ps1 records, and which
# test-stripcomments-units.ps1 tests for from a lax process.

# 02 Sep 26 - PASCAL "{ }", AND "HAS A BRACE" IS NOT THE TEST.  Inno's own
# CONSTANTS are braced - {app}, {tmp}, {sys}, {#AppName}, a GUID - so a naive
# strip would delete SHIPPED text and turn a scanner into a silent liar, which
# is the failure it exists to prevent.
#
# MEASURED ON sd.iss RATHER THAN ASSUMED: inside [Code], every brace span that
# CONTAINS WHITESPACE is prose and every constant has none.  So whitespace is
# the test, and it errs toward NOT stripping - a space-less comment stays in the
# text and can at worst raise a loud false positive, never hide shipped wording.
# "{#" is a preprocessor directive and is never a comment.
function Remove-PascalComment([string]$line, [ref]$inComment) {
    $out = ''
    $i   = 0
    while ($i -lt $line.Length) {
        if ($inComment.Value) {
            $j = $line.IndexOf('}', $i)
            if ($j -lt 0) { return $out }
            $inComment.Value = $false
            $i = $j + 1
            continue
        }
        $b = $line.IndexOf('{', $i)
        if ($b -lt 0) { $out += $line.Substring($i); break }
        $isDirective = (($b + 1) -lt $line.Length -and $line[$b + 1] -eq '#')
        $close = $line.IndexOf('}', $b)
        if ($close -ge 0) {
            $inner = $line.Substring($b + 1, $close - $b - 1)
            if ((-not $isDirective) -and $inner -match '\s') {
                $out += $line.Substring($i, $b - $i)          # prose: drop it
            } else {
                $out += $line.Substring($i, $close - $i + 1)  # constant: keep it
            }
            $i = $close + 1
        } else {
            if ($isDirective) { $out += $line.Substring($i); break }
            $out += $line.Substring($i, $b - $i)
            $inComment.Value = $true                          # block comment opens
            break
        }
    }
    return $out
}

# 02 Sep 26 - THE SECOND PASCAL COMMENT FORM.  Inno Pascal has two, and sd.iss
# uses "(* *)" for nearly every function header - 28 blocks of prose.
#
# THIS ONE NEEDS NO HEURISTIC, WHICH IS WHY IT IS SHORTER.  "(*" and "*)" are
# unambiguous - no Inno constant looks like them - so unlike the brace case
# there is nothing to tell apart and no whitespace test to get wrong.  It runs
# as its own pass BEFORE the brace pass, so each is a state machine with one
# delimiter to think about rather than one machine with two.
function Remove-ParenStarComment([string]$line, [ref]$inComment) {
    $out = ''
    $i   = 0
    while ($i -lt $line.Length) {
        if ($inComment.Value) {
            $j = $line.IndexOf('*)', $i)
            if ($j -lt 0) { return $out }
            $inComment.Value = $false
            $i = $j + 2
            continue
        }
        $b = $line.IndexOf('(*', $i)
        if ($b -lt 0) { $out += $line.Substring($i); break }
        $close = $line.IndexOf('*)', $b + 2)
        $out += $line.Substring($i, $b - $i)
        if ($close -ge 0) {
            $i = $close + 2
        } else {
            $inComment.Value = $true
            break
        }
    }
    return $out
}

# THE KINDS ARE NAMED BY WHAT THEY COMMENT WITH, NOT BY EXTENSION, and "hash"
# covers .ps1 AND .py deliberately: both take "#" to end of line and neither
# caller has a file where the difference would show.  Naming it for the syntax
# stops a third caller assuming a Python-specific rule that is not here.
#
# WHAT IS DELIBERATELY NOT DONE: a "#" inside a string literal still ends the
# line.  Doing it properly means a string parser per language, and the cost of
# being wrong is bounded by the callers' own controls rather than by this file.
# Inno's ";" is honoured ONLY at the start of a line, because "[Files]" entries
# separate their parameters with ";" and a mid-line rule would eat every Source
# line in the installer.
function Get-StrippedLines {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [ValidateSet('iss', 'hash')] [string] $Kind
    )

    $result = New-Object System.Collections.ArrayList
    # NO UNARY COMMA ON EITHER RETURN, AND IT WAS THERE FOR ONE RUN.  The comma
    # was meant to stop PowerShell unrolling an empty result; what it did was
    # hand the caller a one-element array CONTAINING the array, so
    # "foreach ($e in (Get-StrippedLines ...))" iterated ONCE with $e.Line an
    # array of every line number.  Get-StrippedText survived it only because the
    # pipeline unrolled one level - exactly the accident that hides in a helper
    # until a second caller arrives.  Callers wrap with @() instead.
    if (-not (Test-Path -LiteralPath $Path)) { return $result.ToArray() }

    $n         = 0
    $inCode    = $false
    $inComment = $false
    $inParen   = $false

    foreach ($rawLine in (Get-Content -LiteralPath $Path)) {
        $n++
        $t = [string]$rawLine
        if ($Kind -eq 'hash') {
            $i = $t.IndexOf('#'); if ($i -ge 0) { $t = $t.Substring(0, $i) }
        } else {
            if     ($t -match '^\s*\[Code\]')      { $inCode = $true }
            elseif ($t -match '^\s*\[[A-Za-z]+\]') { $inCode = $false }
            if ($t -match '^\s*;') { $t = '' }
            else { $i = $t.IndexOf('//'); if ($i -ge 0) { $t = $t.Substring(0, $i) } }
            if ($inCode) {
                $t = Remove-ParenStarComment $t ([ref]$inParen)
                $t = Remove-PascalComment    $t ([ref]$inComment)
            }
        }
        [void]$result.Add(@{ Line = $n; Text = $t })
    }

    return $result.ToArray()
}

# The whole-file form, for a caller that wants to run one regex over a script
# rather than walk it.  Newlines are kept so that a pattern cannot be formed
# across two lines that the file keeps apart.
function Get-StrippedText {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [ValidateSet('iss', 'hash')] [string] $Kind
    )
    return (((Get-StrippedLines -Path $Path -Kind $Kind) | ForEach-Object { $_.Text }) -join "`n")
}
