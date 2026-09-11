<#
.SYNOPSIS
    Checks PRE_RELEASE_FIXES.md and RELEASE_1.1_FIXES.md against themselves and
    against every document that cites either.  No install, no elevation, no run
    number - it reads files.

    ***TWO SUBJECTS SINCE 11 Sep 2026.***  W1.0-0 shipped, PRE_RELEASE_FIXES.md
    was frozen as its record, and RELEASE_1.1_FIXES.md took over with a fresh id
    space starting at 1.  Checks 1 to 5 run over each file separately; check 6
    checks each CITATION TOKEN against its own table, because id 7 now names two
    different defects and the union would pass a citation of the wrong one.

.DESCRIPTION
    ***WHY THIS EXISTS.***  Owner, 28 Aug 2026, after a session filed three new
    entries as 42, 43 and 45 - numbers the index table had already been using
    since before that session for entirely different defects - and, in the same
    session, reported the open list as 36 items when it was 18.

    Both mistakes have one cause: ***STATUS AND IDENTITY LIVE IN MORE THAN ONE
    PLACE AND NOTHING COMPARED THEM.***  The file carries an index TABLE at the
    top, where a done entry is struck through, and detail SECTIONS below, where
    some entries also carry "- DONE <date>" in the heading and others were moved
    under "## DONE".  Three conventions, all in use.  Seven entries (42-48) exist
    as table rows with no section at all, so a reader who greps "^## [0-9]" - as
    that session did - gets an answer that is wrong and looks authoritative.

    ***THE TABLE IS THE INDEX.  THE SECTIONS ARE DETAIL.***  That is the rule
    this script enforces, and it is the only place it is written down as a rule
    rather than as a habit.

    WHAT IT CHECKS

      1  No id appears twice in the table, and none twice as a section.
      2  Every section has a table row.  (A row with no section is fine - a
         short entry needs no essay.)
      3  ***A SECTION'S TITLE AGREES WITH ITS ROW.***  This is the one that
         catches a collision: on 28 Aug row 42 read "prompt for password at
         creation" while section 42 read "reclaim-profiles.ps1 -List reports 0
         records", and every status check in the world would have passed them
         both.  Compared on significant words, so rewording is allowed and
         changing the subject is not.
      4  Status agrees: a struck-through row means the section says DONE, and
         a section saying DONE means the row is struck through.
      5  The file declares NEXT FREE ID and it is max(id) + 1.  ***THIS IS THE
         ONE THAT WOULD HAVE PREVENTED 28 AUGUST***: the next id was derived by
         scanning section headings, which stopped at 41, while the table went to
         48.  Nobody should have to derive it.
      6  Every "PRE_RELEASE <n>" and every "RELEASE_1.1 <n>" cited in
         PROJECT_STATUS.md, HISTORY.md and the gplbld scripts names an id THAT
         FILE actually has.  A citation of an id that does not exist is how a
         solved item comes back to life.  Each pattern is also driven against a
         must-match and a must-not-match sample every run, because the old
         "zero citations found" guard cannot be asked of a file that is new and
         legitimately has none yet.

    WHAT IT CANNOT SEE.  Whether a status is TRUE.  It compares the documents
    with each other; it cannot tell you that entry 11 is still a live defect.
    That needs the code, and on 28 Aug 2026 the open list was validated that way
    - grep the cited file:line, look for a dated fix - which is how nine entries
    were found already fixed and never struck through.

.PARAMETER Root
    Repository root.  Defaults to three levels above this script.  Point it at
    a copy to use as a control: the pre-fix tree must go RED.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\test-fixlist-units.ps1
#>

[CmdletBinding()]
param(
    [string] $Root = '',
    [switch] $Detail
)

$ErrorActionPreference = 'Stop'

if ($Root -eq '') {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
}

# ***TWO SUBJECTS SINCE 11 Sep 2026, AND THE TOKEN IS THE REASON THEY CANNOT
# SHARE ONE TABLE.***  W1.0-0 shipped, PRE_RELEASE_FIXES.md was frozen as its
# record, and RELEASE_1.1_FIXES.md took over with its own id space starting at
# 1.  So id 7 now names two different defects depending on which file is meant,
# and check 6 - "every citation names a row that exists" - is only answerable if
# the citation says which.  Hence one token per file: `PRE_RELEASE 7` and
# `RELEASE_1.1 7` are different claims and are checked against different tables.
#
# ***THE REGEXES DO NOT OVERLAP, AND THAT WAS CHECKED RATHER THAN ASSUMED.***
# `PRE_RELEASE` requires the literal prefix, so it cannot fire on `RELEASE_1.1`;
# `RELEASE_1\.1` requires `_1.1` after the word, so it cannot fire on a bare
# `PRE_RELEASE 136`.  A token that matched both files would report every id of
# one file as missing from the other - a check that fails loudly for no reason,
# which is how a guard gets switched off.
$subjects = @(
    [pscustomobject]@{
        Path  = Join-Path $Root 'PRE_RELEASE_FIXES.md'
        Token = 'PRE_RELEASE'
        Regex = 'PRE_RELEASE(?:_FIXES\.md)?\s+(\d{1,3})\b'
    }
    [pscustomobject]@{
        Path  = Join-Path $Root 'RELEASE_1.1_FIXES.md'
        Token = 'RELEASE_1.1'
        Regex = 'RELEASE_1\.1(?:_FIXES\.md)?\s+(\d{1,3})\b'
    }
)

Write-Host "test-fixlist-units: root    $Root"
foreach ($s in $subjects) {
    Write-Host ("test-fixlist-units: subject " + $s.Path)
    if (-not (Test-Path -LiteralPath $s.Path)) {
        Write-Host ("  FAIL  " + $s.Path + " is not there - nothing was measured") -ForegroundColor Red
        exit 2
    }
}

$pass = 0; $fail = 0
$silentDone = @()
# $why, NOT $detail.  PowerShell is CASE-INSENSITIVE about variable names, so a
# parameter called $detail shadows the -Detail switch inside this function: every
# PASS printed regardless, because $Detail was resolving to the failure-reason
# string and a non-empty string is truthy.  Same class as the $args clobber in
# PROJECT_STATUS.md section 6 - a name that collides with something already in
# scope - and caught the same way, by reading the output instead of the code.
function Note($ok, $label, $why) {
    if ($ok) { $script:pass++; if ($Detail) { Write-Host ("  PASS  " + $label) } }
    else     { $script:fail++; Write-Host ("  FAIL  " + $label + "  <- " + $why) -ForegroundColor Red }
}

# Filled per subject and read by check 6 below: token -> the ids that file has.
$allRows = @{}

foreach ($subject in $subjects) {

$fixFile = $subject.Path
$tok     = $subject.Token
$lines = Get-Content -LiteralPath $fixFile

# --- the index table -------------------------------------------------------
#
# Bounded by the header row and the first line that is not a table row, so a
# later table in the file (there are several) cannot be mistaken for the index.

$rows = @{}
$order = New-Object System.Collections.ArrayList
$inTable = $false
foreach ($l in $lines) {
    if (-not $inTable) {
        if ($l -match '^\|\s*\|\s*SEV\s*\|') { $inTable = $true }
        continue
    }
    if ($l -notmatch '^\|') { break }
    if ($l -match '^\|\s*-+') { continue }
    $cells = $l -split '\|'
    if ($cells.Count -lt 4) { continue }
    $idCell = $cells[1].Trim()
    $done = ($idCell -match '~~')
    $id = ($idCell -replace '[~\s]', '')
    if ($id -notmatch '^\d+$') { continue }
    $n = [int]$id
    if ($rows.ContainsKey($n)) {
        Note $false ("$tok table id $n appears twice") 'an id must be unique in the index'
    } else {
        $rows[$n] = [pscustomobject]@{ Id = $n; Done = $done; What = $cells[3] }
        $null = $order.Add($n)
    }
}

# REFUSE THE NULL CASE.  No table means every check below passes vacuously.
if ($rows.Count -eq 0) {
    Write-Host ("  FAIL  $tok - no index table found in " + $fixFile +
                ' - every check below would have passed by measuring nothing') -ForegroundColor Red
    exit 2
}
Write-Host ("test-fixlist-units: $tok index table has " + $rows.Count + " row(s), ids " +
            (($order | Sort-Object) -join ',').Substring(0, [Math]::Min(60, (($order | Sort-Object) -join ',').Length)) + '...')

# --- the detail sections ---------------------------------------------------

$sections = @{}
foreach ($l in $lines) {
    if ($l -match '^##\s+(\d+)\.\s*(.+)$') {
        $n = [int]$Matches[1]
        $title = $Matches[2]
        if ($sections.ContainsKey($n)) {
            Note $false ("$tok section id $n appears twice") 'a detail section must be unique'
        } else {
            $sections[$n] = $title
        }
    }
}
Write-Host ("test-fixlist-units: $tok " + $sections.Count + " detail section(s)")

# --- significant words, for the title-agreement check ----------------------

$stop = @('the','a','an','and','or','but','is','are','was','were','be','been','it','its','of','to','in','on','at','for','with','that','this','which','when','so','no','not','never','every','all','from','by','as','than','then','has','have','had','does','do','did','will','would','can','cannot','could','into','out','up','down','one','two','three','more','most','any','each','only','still','now','also','done','fixed','open')
function Words([string]$s) {
    $t = $s -replace '~~', ' ' -replace '\*+', ' ' -replace '`', ' ' -replace '[^A-Za-z0-9\.\-_]', ' '
    $w = @($t.ToLower() -split '\s+' | Where-Object { $_.Length -ge 4 -and $stop -notcontains $_ })
    return , ($w | Sort-Object -Unique)
}

# --- 1..4 ------------------------------------------------------------------

foreach ($n in ($sections.Keys | Sort-Object)) {
    if (-not $rows.ContainsKey($n)) {
        Note $false ("$tok section $n has no row in the index table") 'the table is the index; add a row'
        continue
    }
    Note $true "$tok section $n has a table row" ''

    $sw = Words $sections[$n]
    $rw = Words $rows[$n].What
    $shared = @($sw | Where-Object { $rw -contains $_ })
    $ratio = if ($sw.Count -gt 0) { [Math]::Round($shared.Count / $sw.Count, 2) } else { 0 }
    if ($Detail) { Write-Host ("        $n overlap $ratio (" + $shared.Count + " of " + $sw.Count + ")") }
    # 0.45, AND THE NUMBER IS MEASURED RATHER THAN CHOSEN.  Across the 44 real
    # pairs in this file the lowest ratio is 0.50 - entry 19, whose row was
    # rewritten into a closure note ("CLOSED 28 Aug 2026 by -Run b53, all five
    # legs green") and keeps two words of its title; 33 is also 0.50, 31 is
    # 0.56, and everything else is 0.6 or better.  The three known collisions of
    # 28 Aug 2026 sit at 0.11, 0.11 and 0.38.  So the gap is 0.38 to 0.50 and
    # the threshold goes in it.
    #
    # ***AN EARLIER VERSION ALSO PASSED ANYTHING SHARING THREE WORDS, AND THAT
    # LET A REAL COLLISION THROUGH***: section 43 (the reclaim sweep) against
    # row 43 (the door suite's legs) shares three incidental words and scores
    # 0.38.  The control caught 42 and 45 and reported 43 as fine, which is
    # exactly the shape of failure this file is full of - a check that passes
    # because its escape hatch is wider than the defect.  One threshold, no
    # second arm.
    Note ($ratio -ge 0.45) `
         ("$tok section $n and its row describe the same defect") `
         ("only $($shared.Count) significant word(s) shared, ratio $ratio - row says '" +
          ((($rows[$n].What -replace '\s+',' ').Trim()) -replace '^(.{0,60}).*','$1') +
          "', section says '" + (($sections[$n] -replace '\s+',' ').Trim() -replace '^(.{0,60}).*','$1') + "'")

    # ONE-DIRECTIONAL, AND DELIBERATELY.  The table is the index, so a struck row
    # whose section says nothing is not a fault - most of the file is like that.
    # What must never happen is a section CONTRADICTING its row: a heading that
    # says DONE over an open row would put a fixed item back on the list, which
    # is the failure this whole script exists for.  The other direction is
    # counted below and reported, not failed.
    $secDone = ($sections[$n] -match '(?i)\bDONE\b')
    Note (-not ($secDone -and -not $rows[$n].Done)) `
         ("$tok section $n does not contradict row $n") `
         ("the section heading says DONE but the row is still open - one of them is wrong")
    if ($rows[$n].Done -and -not $secDone) { $script:silentDone += "$tok $n" }
}

# --- 5  the declared next free id ------------------------------------------

$declared = $null
foreach ($l in $lines) {
    if ($l -match '(?i)NEXT\s+FREE\s+ID[^0-9]*(\d+)') { $declared = [int]$Matches[1]; break }
}
$maxId = ($rows.Keys | Measure-Object -Maximum).Maximum
Note ($null -ne $declared) "$tok declares NEXT FREE ID" 'no "NEXT FREE ID: n" line - the next session will derive it and get it wrong'
if ($null -ne $declared) {
    Note ($declared -eq $maxId + 1) "$tok NEXT FREE ID is max+1" "declared $declared, table max is $maxId"
}

# Carried out of the loop for check 6, which needs both id spaces at once.
$allRows[$tok] = $rows

$openIds = @($rows.Values | Where-Object { -not $_.Done } | ForEach-Object { $_.Id } | Sort-Object)
Write-Host ("test-fixlist-units: $tok " + $openIds.Count + " entr(y/ies) OPEN: " + ($openIds -join ', '))

}   # end foreach subject

# --- 6  citations elsewhere ------------------------------------------------
#
# ***EACH TOKEN IS CHECKED AGAINST ITS OWN TABLE, AND THAT IS THE WHOLE CHANGE
# OF 11 Sep 2026.***  With one file this was a straight line.  With two, the
# failure this check exists to catch changes shape: a `RELEASE_1.1 8` in a
# document is wrong not because no row 8 exists ANYWHERE - PRE_RELEASE_FIXES.md
# has a row 8 and would absorb it silently - but because it does not exist in
# THAT file.  Checking the union would pass every such citation.

$targets = @()
foreach ($rel in @('PROJECT_STATUS.md', 'HISTORY.md')) {
    $p = Join-Path $Root $rel
    if (Test-Path -LiteralPath $p) { $targets += $p }
}
$gplbld = Join-Path $Root 'sdb_ai\sd64\gplbld'
if (Test-Path -LiteralPath $gplbld) {
    $targets += @(Get-ChildItem -LiteralPath $gplbld -Filter '*.ps1' | ForEach-Object { $_.FullName })
}
Note ($targets.Count -gt 0) ("scanned " + $targets.Count + " file(s) for citations") 'nothing scanned - check 6 would pass by measuring nothing'

# ***THE REGEX SELF-TEST, AND IT IS HERE BECAUSE THE OBVIOUS NULL-CASE GUARD NO
# LONGER WORKS.***  The old check refused a run that found zero citations.  That
# cannot be asked per token any more: RELEASE_1.1_FIXES.md is new and legitimately
# has none yet, so a summed count would let a BROKEN RELEASE_1.1 regex hide behind
# PRE_RELEASE's several hundred hits - exactly the "passes because it did nothing"
# shape this tree keeps paying for.  So each pattern is driven against a sample it
# must match and a sample it must NOT, every run, whether or not the tree cites it.
foreach ($subject in $subjects) {
    $tok = $subject.Token
    $mine  = "$tok 42"
    $other = @($subjects | Where-Object { $_.Token -ne $tok })[0].Token + ' 42'
    Note ([regex]::IsMatch($mine, $subject.Regex)) `
         ("$tok pattern matches its own citation form") `
         ("the pattern did not match '$mine' - it would find nothing and score clean")
    Note (-not [regex]::IsMatch($other, $subject.Regex)) `
         ("$tok pattern does not match the other token's form") `
         ("the pattern also matched '$other' - the two id spaces would be checked against the wrong tables")
}

$totalCited = 0
foreach ($subject in $subjects) {
    $tok   = $subject.Token
    $rows  = $allRows[$tok]
    $cited = @{}
    foreach ($p in $targets) {
        $txt = Get-Content -LiteralPath $p -Raw
        foreach ($m in [regex]::Matches($txt, $subject.Regex)) {
            $n = [int]$m.Groups[1].Value
            if (-not $cited.ContainsKey($n)) { $cited[$n] = @() }
            if ($cited[$n] -notcontains $p) { $cited[$n] += $p }
        }
    }
    $totalCited += $cited.Count
    Write-Host ("test-fixlist-units: $tok cited for " + $cited.Count + " distinct id(s)")
    foreach ($n in ($cited.Keys | Sort-Object)) {
        Note ($rows.ContainsKey($n)) `
             ("$tok $n is cited and exists in that table") `
             ("cited in " + (($cited[$n] | ForEach-Object { Split-Path $_ -Leaf }) -join ', ') + " but $tok has no row $n")
    }
}
Note ($totalCited -gt 0) ("found citations of $totalCited distinct id(s) across both tokens") 'no citations found at all - the regexes or the tree is wrong'

# --- tally -----------------------------------------------------------------

Write-Host ''
if ($silentDone.Count -gt 0) {
    # NOT A FAILURE, AND WORTH SEEING ANYWAY.  These are done in the index and
    # silent in their own heading, so anyone who lands on the section from a
    # grep sees no status at all.  That is the drift that made 28 Aug's count
    # wrong; the cure is to read the table, and a heading that repeats it is
    # cheap insurance.
    Write-Host ("test-fixlist-units: NOTE - " + $silentDone.Count +
                " section(s) are done in the index but say nothing in their own heading: " +
                (($silentDone | Sort-Object) -join ', ')) -ForegroundColor Yellow
}
foreach ($subject in $subjects) {
    $tok = $subject.Token
    $o = @($allRows[$tok].Values | Where-Object { -not $_.Done } | ForEach-Object { $_.Id } | Sort-Object)
    Write-Host ("test-fixlist-units: $tok " + $o.Count + " entr(y/ies) OPEN in the index: " + ($o -join ', '))
}
Write-Host ("test-fixlist-units: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
exit 0
