# test-retired-wording-units.ps1 - guard against a reworded phrase being fixed
# in one copy and left standing in another.  PRE_RELEASE_FIXES 121 was exactly
# that: 116 reworded remove-ssh.ps1's paragraph and left message 10148 still
# saying "SD will refuse to install here again" - the wording 116 had just
# retired.  The miss was found on a screen, which cost a cycle and a ~19-minute
# ssh reinstall (122); this finds it off disk in a second, with no install.
#
# 1 Sep 26 Windows port.  Written for the CLASS, not the one instance: a
# user-visible phrase that has been deliberately retired must not reappear
# anywhere in the shipped text - the message files, the installer script, and
# the gplbld scripts' own output.  When you rework wording, register the old
# phrase and its replacement in $RETIRED IN THE SAME COMMIT, and this fails the
# next time the old phrasing creeps back into any copy.
#
# INSTRUMENT RULES (CLAUDE.md), because a scan that finds nothing looks
# identical to a scan that ran against nothing:
#   - it ECHOES the corpus it built (file counts, resolved root) and the phrases;
#   - it REFUSES the null case out loud - too few files, or a replacement string
#     that is itself missing, is a FAIL, not a quiet pass;
#   - it carries a MACHINERY CANARY - a token known present must be found and a
#     nonsense token must not - so "0 violations" cannot come from a dead scan.
#
# Comments are stripped before scanning (# for .ps1; a leading ; and // for
# .iss), because this tree's habit is to QUOTE the retired wording in a comment
# beside the fix - remove-ssh.ps1:123 does exactly that - and an un-stripped
# scan would cry wolf on the documentation of the very fix it guards.  The cost
# is a rare false NEGATIVE (a retired phrase hidden after a # inside a string),
# which is the safe direction for a lint to err.  test-*/verify-* scripts are
# NOT in the corpus: they are dev tooling, and this file itself holds every
# retired phrase as a literal.
#
# Matching is case-INSENSITIVE on purpose - it is the more expansive choice, and
# comment-stripping is what makes it safe.  Message files are matched whole (one
# message is one unit), so a message hit is reported by file name; a script hit
# carries its line number.
#
# Unelevated, no SD, no install, no network, no run token.  It writes nothing.
# NOT a verifier: it makes no claim about the installed tree, so it is not named
# verify-* and belongs in neither post-cycle runner.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# Forward slashes so no path carries a backslash, per CLAUDE.md's inline rule.
$gplbld = ($PSScriptRoot -replace '\\', '/')
$sd64   = (Split-Path -Parent $PSScriptRoot) -replace '\\', '/'
$msgDir = "$sd64/sdsys/messages"

Write-Host "test-retired-wording-units: gplbld   $gplbld"
Write-Host "test-retired-wording-units: messages $msgDir"

# --------------------------------------------------------------------------
# THE REGISTER.  One row per retirement.  Retired = must not appear anywhere;
# Replacement = must appear somewhere (the positive control that proves the fix
# is real and the scan reaches it).  Ref names the PRE_RELEASE_FIXES entry.
$RETIRED = @(
    # 130 - the account this described could never exist: LOGIN demands a
    # credential on every login and ends the session without one, so there was
    # no way to REACH a passwordless account that "works only at this computer".
    # Registered because the claim had SEVEN copies across messages, sd.iss and
    # hard-coded crt lines, which is how one gets missed.
    @{ Ref = '130'
       Retired     = 'set no password for now'
       Replacement = 'A password is required' }
    @{ Ref = '130b'
       Retired     = 'works only at this computer'
       Replacement = 'cannot be used at all' }
    # 130c/130d - TWO COPIES THE FIRST SWEEP MISSED, found on a screen rather
    # than by grep.  They said the same false thing in different words, so
    # searching for "no password" and "works only at this computer" walked
    # straight past them.  THE LESSON IS ABOUT THE LINT ITSELF: it proves the
    # PHRASES registered here are gone, never that the CLAIM is - a copy worded
    # differently escapes it, and only reading the screen caught these.
    @{ Ref = '130c'
       Retired     = 'NOT NEED ONE HERE'
       Replacement = 'PASSWORD IS REQUIRED even here' }
    @{ Ref = '130d'
       Retired     = 'not need one at this machine'
       Replacement = 'will not let a session go on without it' }
    # 130e - the TENTH copy, in the /SILENT refusal, which nobody had looked at
    # because that dialog only fires on a silent install.  Found on the third
    # sweep, after two "that is all of them" claims.  THE PATTERN IS THE POINT:
    # each earlier sweep searched for the WORDING of the copies already found;
    # only searching for the CLAIM - "don't need", "need not", "without a
    # password" - turned up the outlier.
    @{ Ref = '130e'
       Retired     = 'used only at this computer from a session run as administrator'
       Replacement = 'cannot be used AT ALL' }
    # 129 - "the ssh-only model" is 124's retired premise in compressed form.
    # 124 registered the long phrase; this said the same thing in four words and
    # sat in the very page 124 had corrected, which is how it survived.
    @{ Ref = '129'
       Retired     = 'ssh-only model'
       Replacement = 'confining ssh to SD Core' }
    @{ Ref = '129b'
       Retired     = 'THE COST, SAID PLAINLY: scp and sftp'
       Replacement = 'ONLY IF YOU INSTALL THE SERVER' }
    @{ Ref = '117'
       Retired     = 'ssh is now limited to members of "sdusers"'
       Replacement = 'ssh is now limited to members of "sdssh"' }
    @{ Ref = '121'
       Retired     = 'refuse to install here again'
       Replacement = 'running the SD INSTALLER on this machine' }
    @{ Ref = '124'
       Retired     = 'sign in over ssh and nothing else'
       Replacement = 'sign in over ssh, or over the' }
)

# --------------------------------------------------------------------------
# THE CORPUS, read once into memory.
#   messages/*   : pure user text, each file scanned whole (Line = 0).
#   sd.iss, *.ps1: scanned with line-comments stripped (test-*/verify-* excluded).
if (-not (Test-Path -LiteralPath $msgDir)) {
    Write-Host "messages directory not found: $msgDir"
    exit 2
}

$corpus = New-Object System.Collections.ArrayList   # each: @{ File; Line; Text }

$msgFiles = @(Get-ChildItem -LiteralPath $msgDir -File)
foreach ($f in $msgFiles) {
    $raw = Get-Content -LiteralPath $f.FullName -Raw
    if ($null -eq $raw) { $raw = '' }
    [void]$corpus.Add(@{ File = $f.Name; Line = 0; Text = $raw })
}

$scriptFiles = @()
$issPath = "$gplbld/sd.iss"
if (Test-Path -LiteralPath $issPath) { $scriptFiles += @{ Path = $issPath; Name = 'sd.iss'; Strip = 'iss' } }
foreach ($f in (Get-ChildItem -LiteralPath $gplbld -File -Filter '*.ps1')) {
    if ($f.Name -like 'test-*' -or $f.Name -like 'verify-*') { continue }
    $scriptFiles += @{ Path = $f.FullName; Name = $f.Name; Strip = 'ps1' }
}

# 02 Sep 26 - PRE_RELEASE 131 (a).  PASCAL { } COMMENTS, AND WHY "HAS A BRACE"
# IS NOT THE TEST.  Inno's own CONSTANTS are braced too - {app}, {tmp}, {sys},
# {#AppName}, a GUID - so a naive strip would delete shipped text and turn this
# lint into a silent liar, which is the failure it exists to prevent.
#
# MEASURED ON THIS FILE RATHER THAN ASSUMED: inside [Code], every brace span
# that CONTAINS WHITESPACE is prose and every constant has none.  So whitespace
# is the test, and it errs toward NOT stripping - a space-less comment stays in
# the corpus and can at worst raise a loud false positive, never hide shipped
# wording.  {# is a preprocessor directive and is never a comment.
#
# The scope is [Code] only.  sd.iss:876 discusses "{" and "}" inside a ";"
# comment ABOVE [Code], and that line is already stripped by the ";" rule - so
# confining this to [Code] sidesteps it instead of parsing around it.
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

# 02 Sep 26 - THE SECOND PASCAL COMMENT FORM, AND LEAVING IT OUT WOULD HAVE BEEN
# FIXING THE INSTANCE INSTEAD OF THE CLASS.  PRE_RELEASE 131 named "{ }" because
# that is what was tripped over, but Inno Pascal has two, and sd.iss uses
# "(* *)" for nearly every function header - 28 blocks of prose that were all
# still in the corpus after the brace fix.  A retirement documented in one of
# those would raise the same false positive the brace strip exists to prevent.
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

$scriptLineCount = 0
$flatCount       = 0
foreach ($sf in $scriptFiles) {
    $n            = 0
    $inCode       = $false
    $inComment    = $false
    $inParen      = $false
    $issLines     = New-Object System.Collections.ArrayList
    foreach ($rawLine in (Get-Content -LiteralPath $sf.Path)) {
        $n++
        $t = $rawLine
        if ($sf.Strip -eq 'ps1') {
            $i = $t.IndexOf('#'); if ($i -ge 0) { $t = $t.Substring(0, $i) }
        } elseif ($sf.Strip -eq 'iss') {
            if     ($t -match '^\s*\[Code\]')      { $inCode = $true }
            elseif ($t -match '^\s*\[[A-Za-z]+\]') { $inCode = $false }
            if ($t -match '^\s*;') { $t = '' }
            else { $i = $t.IndexOf('//'); if ($i -ge 0) { $t = $t.Substring(0, $i) } }
            if ($inCode) {
                $t = Remove-ParenStarComment $t ([ref]$inParen)
                $t = Remove-PascalComment    $t ([ref]$inComment)
            }
            [void]$issLines.Add(@{ Line = $n; Text = $t })
        }
        if ($t.Trim().Length -gt 0) {
            [void]$corpus.Add(@{ File = $sf.Name; Line = $n; Text = $t })
            $scriptLineCount++
        }
    }

    # 02 Sep 26 - PRE_RELEASE 131 (b), AND THIS IS THE HALF THAT MATTERS.
    # sd.iss builds its dialogue as
    #     'the options page offers to install ' +
    #     'one. It is downloaded from Windows Update ...'
    # so a phrase straddling the break IS ON SCREEN and is on NO SINGLE LINE.
    # A line-by-line scan reports it absent - and "retired phrase absent" then
    # becomes a lie about wording that is shipping, with nothing in the output
    # to tell that apart from a genuine absence.
    #
    # Adjacent concatenated literals are joined into one extra corpus entry,
    # keyed to the run's FIRST line so the per-line report still locates a hit.
    # A run of one line adds nothing the per-line pass has not already got, so
    # it is skipped and the corpus does not double.  A #13#10 between fragments
    # becomes a newline rather than nothing, so a phrase cannot be invented
    # across a paragraph break that the reader sees as two.
    if ($sf.Strip -eq 'iss') {
        $runText = ''; $runStart = 0; $runLines = 0
        foreach ($e in $issLines) {
            if ($runLines -eq 0) { $runStart = $e.Line }
            foreach ($m in [regex]::Matches($e.Text, "'((?:[^']|'')*)'")) {
                $runText += $m.Groups[1].Value.Replace("''", "'")
            }
            if ($e.Text -match '#13') { $runText += "`n" }
            $runLines++
            if ($e.Text.TrimEnd() -notmatch '\+\s*$') {
                if ($runLines -ge 2 -and $runText.Trim().Length -gt 0) {
                    [void]$corpus.Add(@{ File = $sf.Name; Line = $runStart; Text = $runText })
                    $flatCount++
                }
                $runText = ''; $runLines = 0
            }
        }
    }
}

Write-Host ("test-retired-wording-units: corpus = {0} message file(s) + {1} script file(s), {2} non-blank script line(s) after comment-strip" -f `
    $msgFiles.Count, $scriptFiles.Count, $scriptLineCount)
Write-Host ("test-retired-wording-units: {0} retired phrase(s) registered" -f $RETIRED.Count)
Write-Host ''

# Every location, case-insensitive, where $phrase occurs in the corpus.  A
# message is reported by file; a script line carries its number.
function Find-Any([string]$phrase) {
    $hits = New-Object System.Collections.ArrayList
    foreach ($c in $corpus) {
        if ($c.Text.IndexOf($phrase, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            if ($c.Line -gt 0) { [void]$hits.Add(("{0}:{1}" -f $c.File, $c.Line)) }
            else               { [void]$hits.Add($c.File) }
        }
    }
    return @($hits.ToArray())
}

$pass = 0; $fail = 0
function Check($name, $ok, $detail) {
    if ($ok) { $script:pass++; Write-Host ("  [PASS] {0}" -f $name) }
    else     { $script:fail++; Write-Host ("  [FAIL] {0}{1}" -f $name, $(if ($detail) { " -- $detail" } else { '' })) }
}

# --------------------------------------------------------------------------
Write-Host '=== 0. the null case is refused: the corpus is real ==='
Check ("at least 100 message files were read (got $($msgFiles.Count))") ($msgFiles.Count -ge 100) $null
Check ("at least one script file was read (got $($scriptFiles.Count))") ($scriptFiles.Count -ge 1) $null
Check ("script lines survived the comment-strip (got $scriptLineCount)") ($scriptLineCount -ge 1) $null
# A flattening that silently flattened NOTHING looks identical to one that
# worked - PRE_RELEASE 131 says so in as many words - so it is asserted, not
# assumed.
Check ("the .iss concatenation flattening produced entries (got $flatCount)") ($flatCount -ge 1) `
      'nothing was flattened, so a phrase split across a + break would still read as absent'

Write-Host ''
Write-Host '=== 1. THE MACHINERY CANARY: the scan finds what is there and only what is there ==='
$present = Find-Any 'the'
$absent  = Find-Any 'zqxjkvbwp_absent_canary_9137'
Check ("a token known present ('the') is found ($($present.Count) hit(s))") ($present.Count -gt 0) $null
Check ("a nonsense token is NOT found ($($absent.Count) hit(s))") ($absent.Count -eq 0) ($absent -join ', ')

# 02 Sep 26 - PRE_RELEASE 131's THREE CONTROLS, one per way this can go wrong.
# The first two FAILED before the fix and pass after; the third guards the fix
# itself, because over-stripping would be worse than the bug it repairs.
$straddle = Find-Any 'offers to install one'
Check ("a phrase STRADDLING a '+' break is found ($($straddle.Count) hit(s))") ($straddle.Count -gt 0) `
      'sd.iss renders this across 1771-1772 and no single line carries it - the flattening is not working'
$inBrace = Find-Any 'Lower case for the reason given at code 0'
Check ("text inside a Pascal { } comment is stripped ($($inBrace.Count) hit(s))") ($inBrace.Count -eq 0) `
      ("a retirement documented beside its fix would raise a false positive: " + ($inBrace -join ', '))
$inParenC = Find-Any 'THE OTHER BRANCH, AND THE TWO ARE EXHAUSTIVE'
Check ("text inside a Pascal (* *) comment is stripped ($($inParenC.Count) hit(s))") ($inParenC.Count -eq 0) `
      ("sd.iss uses (* *) for nearly every function header: " + ($inParenC -join ', '))
$const = Find-Any '{app}'
Check ("an Inno constant is NOT mistaken for a comment ($($const.Count) hit(s))") ($const.Count -gt 0) `
      'the brace strip is eating shipped text, which is a worse fault than the one it fixes'

Write-Host ''
Write-Host '=== 2. every retired phrase is GONE, and its replacement is present ==='
foreach ($e in $RETIRED) {
    $bad  = Find-Any $e.Retired
    $good = Find-Any $e.Replacement
    Check ("[$($e.Ref)] retired phrase absent: `"$($e.Retired)`"") ($bad.Count -eq 0) ("still in " + ($bad -join ', '))
    Check ("[$($e.Ref)] replacement present : `"$($e.Replacement)`"") ($good.Count -gt 0) 'the replacement wording is missing everywhere - is the fix in?'
}

Write-Host ''
if ($fail -gt 0) {
    Write-Host ("test-retired-wording-units: FAILED - {0} passed, {1} failed" -f $pass, $fail)
    exit 1
}
Write-Host ("test-retired-wording-units: PASSED - {0} of {0} checks passed." -f $pass)
exit 0
