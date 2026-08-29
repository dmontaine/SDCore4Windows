<#
.SYNOPSIS
    Checks PRE_RELEASE_FIXES.md against itself and against every document that
    cites it.  No install, no elevation, no run number - it reads files.

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
      6  Every "PRE_RELEASE <n>" cited in PROJECT_STATUS.md, HISTORY.md and the
         gplbld scripts names an id the table actually has.  A citation of an id
         that does not exist is how a solved item comes back to life.

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

$fixFile = Join-Path $Root 'PRE_RELEASE_FIXES.md'
Write-Host "test-fixlist-units: root    $Root"
Write-Host "test-fixlist-units: subject $fixFile"

if (-not (Test-Path -LiteralPath $fixFile)) {
    Write-Host "  FAIL  $fixFile is not there - nothing was measured" -ForegroundColor Red
    exit 2
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
        Note $false ("table id $n appears twice") 'an id must be unique in the index'
    } else {
        $rows[$n] = [pscustomobject]@{ Id = $n; Done = $done; What = $cells[3] }
        $null = $order.Add($n)
    }
}

# REFUSE THE NULL CASE.  No table means every check below passes vacuously.
if ($rows.Count -eq 0) {
    Write-Host '  FAIL  no index table found - every check below would have passed by measuring nothing' -ForegroundColor Red
    exit 2
}
Write-Host ("test-fixlist-units: index table has " + $rows.Count + " row(s), ids " +
            (($order | Sort-Object) -join ',').Substring(0, [Math]::Min(60, (($order | Sort-Object) -join ',').Length)) + '...')

# --- the detail sections ---------------------------------------------------

$sections = @{}
foreach ($l in $lines) {
    if ($l -match '^##\s+(\d+)\.\s*(.+)$') {
        $n = [int]$Matches[1]
        $title = $Matches[2]
        if ($sections.ContainsKey($n)) {
            Note $false ("section id $n appears twice") 'a detail section must be unique'
        } else {
            $sections[$n] = $title
        }
    }
}
Write-Host ("test-fixlist-units: " + $sections.Count + " detail section(s)")

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
        Note $false ("section $n has no row in the index table") 'the table is the index; add a row'
        continue
    }
    Note $true "section $n has a table row" ''

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
         ("section $n and its row describe the same defect") `
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
         ("section $n does not contradict row $n") `
         ("the section heading says DONE but the row is still open - one of them is wrong")
    if ($rows[$n].Done -and -not $secDone) { $script:silentDone += $n }
}

# --- 5  the declared next free id ------------------------------------------

$declared = $null
foreach ($l in $lines) {
    if ($l -match '(?i)NEXT\s+FREE\s+ID[^0-9]*(\d+)') { $declared = [int]$Matches[1]; break }
}
$maxId = ($rows.Keys | Measure-Object -Maximum).Maximum
Note ($null -ne $declared) 'the file declares NEXT FREE ID' 'no "NEXT FREE ID: n" line - the next session will derive it and get it wrong'
if ($null -ne $declared) {
    Note ($declared -eq $maxId + 1) "NEXT FREE ID is max+1" "declared $declared, table max is $maxId"
}

# --- 6  citations elsewhere ------------------------------------------------

$cited = @{}
$scanned = 0
$targets = @()
foreach ($rel in @('PROJECT_STATUS.md', 'HISTORY.md')) {
    $p = Join-Path $Root $rel
    if (Test-Path -LiteralPath $p) { $targets += $p }
}
$gplbld = Join-Path $Root 'sdb_ai\sd64\gplbld'
if (Test-Path -LiteralPath $gplbld) {
    $targets += @(Get-ChildItem -LiteralPath $gplbld -Filter '*.ps1' | ForEach-Object { $_.FullName })
}
foreach ($p in $targets) {
    $scanned++
    $txt = Get-Content -LiteralPath $p -Raw
    foreach ($m in [regex]::Matches($txt, 'PRE_RELEASE(?:_FIXES\.md)?\s+(\d{1,3})\b')) {
        $n = [int]$m.Groups[1].Value
        if (-not $cited.ContainsKey($n)) { $cited[$n] = @() }
        if ($cited[$n] -notcontains $p) { $cited[$n] += $p }
    }
}
Note ($scanned -gt 0) "scanned $scanned file(s) for citations" 'nothing scanned - check 6 would pass by measuring nothing'
Note ($cited.Count -gt 0) ("found citations of " + $cited.Count + " distinct id(s)") 'no citations found at all - the regex or the tree is wrong'

foreach ($n in ($cited.Keys | Sort-Object)) {
    Note ($rows.ContainsKey($n)) `
         ("PRE_RELEASE $n is cited and exists in the table") `
         ("cited in " + (($cited[$n] | ForEach-Object { Split-Path $_ -Leaf }) -join ', ') + " but the table has no row $n")
}

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
$openIds = @($rows.Values | Where-Object { -not $_.Done } | ForEach-Object { $_.Id } | Sort-Object)
Write-Host ("test-fixlist-units: " + $openIds.Count + " entr(y/ies) OPEN in the index: " + ($openIds -join ', '))
Write-Host ("test-fixlist-units: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
exit 0
