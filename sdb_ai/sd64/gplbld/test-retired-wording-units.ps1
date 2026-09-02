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

$scriptLineCount = 0
foreach ($sf in $scriptFiles) {
    $n = 0
    foreach ($rawLine in (Get-Content -LiteralPath $sf.Path)) {
        $n++
        $t = $rawLine
        if ($sf.Strip -eq 'ps1') {
            $i = $t.IndexOf('#'); if ($i -ge 0) { $t = $t.Substring(0, $i) }
        } elseif ($sf.Strip -eq 'iss') {
            if ($t -match '^\s*;') { $t = '' }
            else { $i = $t.IndexOf('//'); if ($i -ge 0) { $t = $t.Substring(0, $i) } }
        }
        if ($t.Trim().Length -gt 0) {
            [void]$corpus.Add(@{ File = $sf.Name; Line = $n; Text = $t })
            $scriptLineCount++
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

Write-Host ''
Write-Host '=== 1. THE MACHINERY CANARY: the scan finds what is there and only what is there ==='
$present = Find-Any 'the'
$absent  = Find-Any 'zqxjkvbwp_absent_canary_9137'
Check ("a token known present ('the') is found ($($present.Count) hit(s))") ($present.Count -gt 0) $null
Check ("a nonsense token is NOT found ($($absent.Count) hit(s))") ($absent.Count -eq 0) ($absent -join ', ')

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
