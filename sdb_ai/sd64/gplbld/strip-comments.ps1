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

# 20 Sep 26 - POWERSHELL'S "<# #>" BLOCK, AND THE ORDER OF THE TWO RULES IS THE
# WHOLE PROBLEM.  RELEASE_1.1 81.  Neither rule is safe run before the other as
# a separate pass, which is why this is ONE left-to-right machine and not a
# third Remove-* function stacked in front of the hash truncation:
#
#   * HASH FIRST eats the block's own opener.  "<#" contains a "#", so
#     truncating at the first "#" leaves "<" and the block is never seen.
#   * BLOCK FIRST eats the rest of the FILE the moment an ordinary "#" comment
#     mentions "<#" - which this tree's comments do, because they document this
#     very gap.  test-logtoreaim-units.ps1:146-148 is exactly that line, and it
#     would have opened a block running to the next "#>" anywhere below.
#
# SO THE MACHINE DECIDES AT EACH "#" WHICH RULE IT IS UNDER: preceded by "<" it
# opens a block, otherwise it ends the line and everything after it goes.  A "#"
# mentioned inside a line comment is therefore never read as an opener, because
# the line comment has already ended the line.
#
# The same string caveat as "hash": a "<#" inside a string literal opens a
# block.  Bounded by the caller's own controls, which is this file's standing
# policy, and test-retired-wording-units' control would report it as an
# over-strip rather than as a silent pass.
function Remove-HashComment([string]$line, [ref]$inBlock) {
    $out = ''
    $i   = 0
    while ($i -lt $line.Length) {
        if ($inBlock.Value) {
            $j = $line.IndexOf('#>', $i)
            if ($j -lt 0) { return $out }          # block runs past end of line
            $inBlock.Value = $false
            $i = $j + 2
            continue
        }
        $h = $line.IndexOf('#', $i)
        if ($h -lt 0) { $out += $line.Substring($i); break }
        if ($h -gt $i -and $line[$h - 1] -eq '<') {
            $out += $line.Substring($i, $h - 1 - $i)   # text before the "<#"
            $inBlock.Value = $true
            $i = $h + 1
            continue
        }
        # NO THIRD BRANCH FOR "$h -eq $i WITH A '<' BEHIND IT".  A first draft
        # had one and it is unreachable: the loop only re-enters this arm just
        # after an opener (previous char "#") or just after a closer (previous
        # char ">"), so the character before $i is never "<".  Left as a note
        # rather than as code, because a branch nothing can reach is a branch
        # nothing can test.
        $out += $line.Substring($i, $h - $i)            # line comment: rest goes
        break
    }
    return $out
}

# THE KINDS ARE NAMED BY WHAT THEY COMMENT WITH, NOT BY EXTENSION, and "hash"
# covers .py: it takes "#" to end of line and nothing else.
#
# 20 Sep 26 - "hashblock" IS THE .ps1 KIND, AND THE SENTENCE THAT USED TO STAND
# HERE WAS FALSIFIED BY MEASUREMENT.  RELEASE_1.1 81.  It read: *"hash covers
# .ps1 AND .py deliberately ... neither caller has a file where the difference
# would show"*.  A caller does.  test-retired-wording-units.ps1 strips every
# non-test, non-verify gplbld .ps1 with "hash", and 655 LINES of "<# #>" prose
# across 19 files were reaching its corpus as live script text - in a tree whose
# documented habit is to QUOTE the retired wording in a comment beside the fix,
# which is the exact shape PRE_RELEASE 131 created this file to stop.
#
# ***THE WRONG KIND IS REFUSED RATHER THAN LEFT TO THE CALLER'S JUDGEMENT.***
# "hash" is the obvious name, and a later caller reaching for it with a .ps1 in
# hand would silently reinstate this defect.  Get-StrippedLines throws on that
# pair, so the mistake is loud at the call site instead of quiet in the answer.
# The other direction is NOT policed: "hashblock" on a .py file is harmless
# unless a literal contains "<#", and a rule for that would add a failure mode
# to prevent a hypothetical.
#
# WHAT IS DELIBERATELY NOT DONE: a "#" inside a string literal still ends the
# line.  Doing it properly means a string parser per language, and the cost of
# being wrong is bounded by the callers' own controls rather than by this file.
# Inno's ";" is honoured ONLY at the start of a line, because "[Files]" entries
# separate their parameters with ";" and a mid-line rule would eat every Source
# line in the installer.
#
# 19 Sep 26 - "basic" JOINS THEM, FOR sdsys/gpl.bp.  RELEASE_1.1 69.  A claim
# that is wrong in a shipped message is usually wrong in a hard-coded crt line
# too, and the wording lint could not see gpl.bp at all: 69's fourth copy sat in
# set_acc_password and was found by reading, which is the third time this tree
# has found a copy that way.
#
# TWO FORMS, AND BOTH ARE NEEDED.  A line whose first non-blank character is "*"
# or "!" is a whole-line comment (SD BASIC takes either, and "!!" is the
# commented-out-code habit in this tree).  ";*" starts a trailing comment, and
# that is the form that MATTERS here, because this tree's habit is to echo a
# message's own text after the call that displays it -
# "display sysmsg(10170) ;* Every registered account will have its VOC updated".
# Left in, every such line would read as a second copy of the message and the
# lint would report retired wording alive in a file that merely mentions it.
#
# NO "REM": measured on 19 Sep 2026, sdsys/gpl.bp has none.  The same string
# caveat as "hash" applies - a ";*" inside a literal ends the line - and the
# caller's own controls bound it, which is this file's standing policy.
function Get-StrippedLines {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [ValidateSet('iss', 'hash', 'hashblock', 'basic')] [string] $Kind
    )

    # 20 Sep 26 - RELEASE_1.1 81.  BEFORE Test-Path, so a missing .ps1 refuses
    # too: a caller that got the Kind wrong should hear about the Kind, not be
    # handed an empty result it will read as "no hits".
    if ($Kind -eq 'hash' -and [System.IO.Path]::GetExtension($Path) -eq '.ps1') {
        throw ("strip-comments: Kind 'hash' cannot read a .ps1 - it has no idea of " +
               "PowerShell's <# #> block, so the prose inside one would be returned as " +
               "live script text.  Use 'hashblock'.  (" + $Path + ")")
    }

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
    $inBlock   = $false

    foreach ($rawLine in (Get-Content -LiteralPath $Path)) {
        $n++
        $t = [string]$rawLine
        if ($Kind -eq 'hash') {
            $i = $t.IndexOf('#'); if ($i -ge 0) { $t = $t.Substring(0, $i) }
        } elseif ($Kind -eq 'hashblock') {
            $t = Remove-HashComment $t ([ref]$inBlock)
        } elseif ($Kind -eq 'basic') {
            $lead = $t.TrimStart()
            if ($lead.StartsWith('*') -or $lead.StartsWith('!')) {
                $t = ''
            } else {
                $i = $t.IndexOf(';*'); if ($i -ge 0) { $t = $t.Substring(0, $i) }
            }
        } else {
            # 04 Sep 26 - A SECTION HEADER IS THE WHOLE LINE, AND LEAVING THAT
            # UNANCHORED COST A DIAGNOSIS.  PRE_RELEASE_FIXES 70.  These two
            # tests used to match a PREFIX, so any line beginning with a
            # bracketed word left [Code] - and this tree writes about VOC
            # records "marked [locked]", which is exactly that shape.  One
            # comment line wrapped so that "[locked] on everything but a verb"
            # started it, Pascal stripping switched off for the remaining 2,400
            # lines, and test-retired-wording-units' own canary went red naming
            # a comment 1,300 lines further on - a true report of a fault whose
            # cause was nowhere near it.
            #
            # ANCHORED AT BOTH ENDS, WHICH IS MEASURED RATHER THAN ASSUMED:
            # every one of sd.iss's eleven real section lines is a bare [Word]
            # with nothing after it, and the ONLY line in the file that matched
            # the old pattern with trailing text was the prose above.
            if     ($t -match '^\s*\[Code\]\s*$')      { $inCode = $true }
            elseif ($t -match '^\s*\[[A-Za-z]+\]\s*$') { $inCode = $false }
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
        # 20 Sep 26 - RELEASE_1.1 81.  THE TWO ValidateSets MUST BE ADDED TO
        # TOGETHER, and this file has already paid for forgetting: a Kind added
        # to Get-StrippedLines and not to this wrapper made every caller of the
        # wrapper throw on a Kind the other function accepted.
        [Parameter(Mandatory = $true)] [ValidateSet('iss', 'hash', 'hashblock', 'basic')] [string] $Kind
    )
    return (((Get-StrippedLines -Path $Path -Kind $Kind) | ForEach-Object { $_.Text }) -join "`n")
}
