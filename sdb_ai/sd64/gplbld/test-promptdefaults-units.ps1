<#
.SYNOPSIS
    Every prompt that takes Enter as an answer must SAY so.  Free: no install,
    no elevation, no run token, no SD.

.DESCRIPTION
    RELEASE_1.1_FIXES.md 6.  A prompt fix has two halves in two files: the
    default lives in `gpl.bp/<PROG>` as `if x = '' then x = 'N'`, and the
    marker `(y/<n>)?` lives in `sdsys/messages/<id>`.  ***EITHER HALF WORKS
    ALONE AND BOTH ARE WRONG ALONE***: a default with no marker leaves the user
    guessing what Enter does, and a marker with no default promises a behaviour
    the code has not got.

    ***THAT IS NOT HYPOTHETICAL.***  Entry 6 recorded seven prompts as fixed and
    the shipped `changelog` told users all seven end `(y/<n>)`. Message **6131**
    never got it - measured 12 Sep 2026, last touched 19 Aug while the other six
    were touched by `ffea2f9` on 11 Sep. **The code default was there, the
    wording was not, and the changelog had been ahead of the tree for a day.**

    ***THE SET IS DERIVED, NOT LISTED, AND THAT IS THE POINT.***  A hand list is
    a second copy of a fact - the shape CLAUDE.md's own free-tier list and
    `stage.py`/`sd.iss` both got wrong. This walks `gpl.bp`, finds every prompt
    loop that defaults an empty answer, and reads the message id off the
    `sysmsg()` call beside it. **Add a defaulted prompt and it is checked from
    that moment, with nobody updating anything.**

    `test-retired-wording-units` cannot see this class: nothing was RETIRED, an
    addition simply never arrived.

.OUTPUTS
    Exit 0 every derived prompt carries both halves, 1 one does not.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdsys    = Join-Path $here '..\sdsys'
$bpDir    = Join-Path $sdsys 'gpl.bp'
$msgDir   = Join-Path $sdsys 'messages'

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}

# ---------------------------------------------------------------------------
# THE DECISION, lifted by the test below and by nothing else yet.
#
# Given one program's text, return every prompt in it that defaults an empty
# answer, as @{ Msg = '6131'; Var = 'yn'; Line = 202; Default = 'N' }.
#
# 13 Sep 26 - RELEASE_1.1 33.  ANY DEFAULT LETTER, NOT ONLY N.  DELETEF's 6133
# now defaults to C (cancel) on the owner's ruling, and a walk that matched only
# 'N' would have skipped exactly the prompt with the least obvious default - so
# its marker would go unchecked while this file reported every prompt covered.
# The marker required is the default's own letter in angle brackets.
#
# It walks BACKWARDS from the default to the sysmsg() that asked the question,
# rather than forwards from the message.  Forwards fails: the fixes carry long
# comment blocks between the display and the default, and an earlier attempt
# at this capped the look-ahead and reported three false misses.
function Get-DefaultedPrompts([string]$programText) {
    $lines = $programText -split "`r?`n"
    $out = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], "if\s+(\w[\w.]*)\s*=\s*''\s*then\s+\1\s*=\s*'([A-Za-z])'")
        if (-not $m.Success) { continue }
        if ($lines[$i] -match '^\s*\*') { continue }      # a comment, not code
        $var = $m.Groups[1].Value
        $dflt = $m.Groups[2].Value.ToUpper()
        # ***AND IT MUST BE AN ANSWER.***  Matching any letter picked up
        # QDISP:652, "if dsp.class = '' then dsp.class = 'D'" - an ordinary
        # variable default, not a prompt - the first time it ran.  Every real
        # prompt reads its answer with "input <var>" shortly before defaulting
        # it (measured across all 22: yn, s, reply, response, n), so that is the
        # test.  Same window as the display search below.
        $isAnswer = $false
        for ($k = $i - 1; $k -ge [Math]::Max(0, $i - 60); $k--) {
            if ($lines[$k] -match '^\s*\*') { continue }
            if ($lines[$k] -match ('^\s*input\s+' + [regex]::Escape($var) + '\b')) { $isAnswer = $true; break }
        }
        if (-not $isAnswer) { continue }
        # Back up to the question this answers.
        #
        # ***DO NOT STOP AT "loop".***  The first version did, and it lost
        # LOGIN:1728 - whose sysmsg(5049) is displayed BEFORE the loop it is
        # asked inside, which is an ordinary shape and not an exception.
        # Distance is the only limit, and a site with no sysmsg in reach is
        # reported as indirect rather than as a failure.
        # ***ANCHOR ON THE NEAREST "display", NOT ON THE NEAREST sysmsg.***
        # Looking for a sysmsg alone reaches PAST the question actually being
        # asked: QPROC's get.label.yn displays a "txt" parameter, and the walk
        # attributed it to an unrelated sysmsg(7278) sixty lines up - a
        # confident answer about the wrong message.  The display that precedes
        # the input IS the question; whether it names a sysmsg is then what
        # separates a traceable prompt from an indirect one.
        $msg = ''
        for ($j = $i - 1; $j -ge [Math]::Max(0, $i - 60); $j--) {
            if ($lines[$j] -match '^\s*\*') { continue }
            # "crt" as well as "display" - SETPTR:557 asks with crt, and
            # recognising only one of the two output verbs made a perfectly
            # traceable prompt look indirect.
            if ($lines[$j] -notmatch '^\s*(display|crt)\b') { continue }
            $s = [regex]::Match($lines[$j], 'sysmsg\(\s*(\d+)')
            if ($s.Success) { $msg = $s.Groups[1].Value }
            break
        }
        $out += [pscustomobject]@{ Msg = $msg; Var = $var; Line = $i + 1; Default = $dflt }
    }
    return , $out
}

Write-Host 'test-promptdefaults-units: every defaulted prompt must show its default'
Write-Host ''

# --- fixtures, driving the decision directly --------------------------------

$fix = @'
program p
   loop
      display sysmsg(6131, file.name) :
      input yn
      yn = upcase(yn[1,1])
* a comment block long enough to defeat a fixed look-ahead window
* second line
* third line
      if yn = '' then yn = 'N'
   until yn = 'Y' or yn = 'N'
   repeat
'@
$r = Get-DefaultedPrompts $fix
Row 'a default is found across an intervening comment block' `
    ($r.Count -eq 1 -and $r[0].Msg -eq '6131') "got $($r.Count): $($r | ForEach-Object { $_.Msg })"

$otherVar = @'
program p
   display sysmsg(5040, at.command) :
   prompt ""
   input s
   if s = '' then s = 'N'
'@
$r = Get-DefaultedPrompts $otherVar
Row 'a default on a variable not called yn is still found' `
    ($r.Count -eq 1 -and $r[0].Msg -eq '5040' -and $r[0].Var -eq 's') `
    "got $($r.Count): msg=$($r[0].Msg) var=$($r[0].Var)"

$commented = @'
program p
   display sysmsg(9999, x) :
   input yn
*  if yn = '' then yn = 'N'
'@
Row 'a default that is only in a comment does not count' `
    ((Get-DefaultedPrompts $commented).Count -eq 0) 'a commented-out default was counted'

$none = @'
program p
   display sysmsg(2050, x) :
   input yn
   until yn = 'Y'
'@
Row 'a prompt with no default is not reported as one' `
    ((Get-DefaultedPrompts $none).Count -eq 0) 'found a default that is not there'

# 13 Sep 26 - RELEASE_1.1 33: a default that is not N is still a default.
$cancel = @'
program p
   loop
      display sysmsg(6133) :
      input yn
      yn = upcase(yn)
      if yn = '' then yn = 'C'
   until yn = 'Y'
   repeat
'@
$r = Get-DefaultedPrompts $cancel
Row 'a default to C is found, and its letter is recorded' `
    ($r.Count -eq 1 -and $r[0].Msg -eq '6133' -and $r[0].Default -eq 'C') `
    "got $($r.Count): msg=$($r[0].Msg) default=$($r[0].Default)"
$notPrompt = @'
show.line:
   dsp.class = line[1,1]
   if dsp.class = '' then dsp.class = 'D'
'@
Row 'a variable default that no input reads is not a prompt (QDISP:652, real text)' `
    ((Get-DefaultedPrompts $notPrompt).Count -eq 0) 'an ordinary default was counted as a prompt'
Row 'the marker a C default needs is <c>, and <n> does not satisfy it' `
    (('Delete it (y/n/<c>)?' -match ('<' + $r[0].Default.ToLower() + '>')) -and
     -not ('Delete it (y/<n>)?' -match ('<' + $r[0].Default.ToLower() + '>'))) `
    'the marker check does not follow the default letter'

# --- the live walk ----------------------------------------------------------

Write-Host ''
if (-not (Test-Path -LiteralPath $bpDir)) {
    Row 'LIVE: gpl.bp is readable' $false "no $bpDir"
} else {
    $found = @()
    foreach ($f in (Get-ChildItem -LiteralPath $bpDir -File)) {
        foreach ($p in (Get-DefaultedPrompts (Get-Content -LiteralPath $f.FullName -Raw))) {
            $found += [pscustomobject]@{ Prog = $f.Name; Msg = $p.Msg; Var = $p.Var; Line = $p.Line; Default = $p.Default }
        }
    }

    Write-Host ("  derived from gpl.bp: " + $found.Count + " defaulted prompt(s)")
    foreach ($p in ($found | Sort-Object Msg)) {
        Write-Host ("    {0,-6} {1}:{2}  (`${3}, default {4})" -f $p.Msg, $p.Prog, $p.Line, $p.Var, $p.Default)
    }

    # REFUSE THE NULL CASE.  Entry 6 fixed seven; a walk that finds almost none
    # has stopped matching, and every row below it would pass by measuring
    # nothing.
    Row 'LIVE: the walk found the prompts it should have' ($found.Count -ge 7) `
        "found $($found.Count), expected at least the 7 of RELEASE_1.1 6"

    # ***INDIRECT PROMPTS ARE A REAL CATEGORY, NOT A FAILURE, AND THEY ARE
    # DECLARED SO A NEW ONE CANNOT APPEAR IN SILENCE.***  These sites default an
    # answer to a question whose TEXT came from somewhere else - a shared
    # yes/no subroutine, or a prompt string passed in - so this guard cannot
    # reach the wording from here.  Each is listed with the reason; the
    # partition below is what makes the list self-policing.
    $declaredIndirect = @{
        'ED'    = 'the shared yes.no subroutine - six callers supply the text (:1080, :1135, :1189, :1340, :2066, :2603)'
        'QPROC' = 'get.label.yn displays a "txt" parameter, supplied by its caller at :867'
    }
    $indirect = @($found | Where-Object { $_.Msg -eq '' })
    $undeclared = @($indirect | Where-Object { -not $declaredIndirect.ContainsKey($_.Prog) })
    foreach ($p in $indirect) {
        if ($declaredIndirect.ContainsKey($p.Prog)) {
            Write-Host ("    indirect: {0}:{1} - {2}" -f $p.Prog, $p.Line, $declaredIndirect[$p.Prog])
        }
    }
    Row 'LIVE: every untraced default is a DECLARED indirect prompt' ($undeclared.Count -eq 0) `
        ("undeclared: " + (($undeclared | ForEach-Object { $_.Prog + ':' + $_.Line }) -join ', ') +
         " - a new prompt whose text comes from its caller; classify it or trace it")

    $noMarker = @()
    $noFile   = @()
    foreach ($p in $found) {
        if ($p.Msg -eq '') { continue }
        $mf = Join-Path $msgDir $p.Msg
        if (-not (Test-Path -LiteralPath $mf)) { $noFile += $p; continue }
        # ***THE MARKER IS "<n>", NOT "(y/<n>)".***  Requiring the two-way form
        # reported SETFILE's 2060 as a defect, and it is not one: it reads
        # "Overwrite (y/<n>/q)?" - a three-way prompt that marks its default
        # perfectly well.  What matters is that the default ARM is the one shown
        # in angle brackets.  13 Sep 26: and that arm is the DEFAULT'S OWN LETTER
        # (RELEASE_1.1 33 - 6133 defaults to C), so <n> no longer stands in for all.
        $want = '<' + $p.Default.ToLower() + '>'
        if ((Get-Content -LiteralPath $mf -Raw) -notmatch [regex]::Escape($want)) { $noMarker += $p }
    }
    Row 'LIVE: every defaulted prompt has a message file' ($noFile.Count -eq 0) `
        ("missing: " + (($noFile | ForEach-Object { $_.Msg }) -join ', '))

    # THE ROW THIS FILE EXISTS FOR.
    Row 'LIVE: every defaulted prompt SAYS Enter is the default' ($noMarker.Count -eq 0) `
        ("no (y/<n>) in message(s): " +
         (($noMarker | ForEach-Object { $_.Msg + ' (' + $_.Prog + ':' + $_.Line + ')' }) -join ', '))

    # --- mutants, in memory; nothing on disk is touched ---------------------
    $deleteF = Join-Path $bpDir 'DELETEF'
    if (Test-Path -LiteralPath $deleteF) {
        $orig = Get-Content -LiteralPath $deleteF -Raw
        # 13 Sep 26 - the mutant breaks the EMPTY test, not the letter: any letter
        # is now a default, so the old 'N' -> 'Q' mutant would still be found.
        $mut  = $orig -replace "if yn = '' then yn = 'N'", "if yn = 'x' then yn = 'N'"
        $m    = Get-DefaultedPrompts $mut
        Row 'MUTANT: breaking the default makes the walk stop finding it' `
            ($mut -ne $orig -and $m.Count -lt (Get-DefaultedPrompts $orig).Count) `
            "changed=$($mut -ne $orig) before=$((Get-DefaultedPrompts $orig).Count) after=$($m.Count)"
        Row 'MUTANT: nothing on disk was modified' `
            ((Get-Content -LiteralPath $deleteF -Raw) -eq $orig) 'DELETEF changed under the test'
    }

    # A marker mutant, to prove the marker row can go red at all.
    $anyMsg = @($found | Where-Object { $_.Msg -ne '' } | Select-Object -First 1)
    if ($anyMsg.Count -eq 1) {
        $txt = Get-Content -LiteralPath (Join-Path $msgDir $anyMsg[0].Msg) -Raw
        $stripped = $txt -replace '\s*\(y/<n>\)\?', '?'
        Row 'MUTANT: stripping (y/<n>) from a message is detectable' `
            ($txt -match '\(y/<n>\)' -and $stripped -notmatch '\(y/<n>\)') `
            "message $($anyMsg[0].Msg) did not carry the marker to begin with"
    }
}

Write-Host ''
Write-Host "test-promptdefaults-units: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
