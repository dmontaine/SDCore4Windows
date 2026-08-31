# test-tiercounts-units.ps1 - the three tier VOC counts, checked against the
# DIRECTORY and against each other.  No install, no elevation, no account.
#
# START-HISTORY:
# 28 Aug 2026  Written after -Run b52 step 19.  verify-tierapi.ps1 carried
#              ADMINISTRATOR = 417 while verify-tiers.ps1 carried 416, and the
#              tree said 416.  PRE_RELEASE 25 removed encrypt.field on 28 Aug
#              and only one of the two files was re-derived, so the pair
#              disagreed about one fact for a day and it took a suite step to
#              find out.
# END-HISTORY
#
# ***ONE FACT LIVED IN TWO FILES AND NOTHING COMPARED THEM.***  That is the
# whole defect.  Fixing the constant fixes this instance; this file fixes the
# class, and it costs no cycle, no elevation and no run token - so there is no
# reason for the next drift to reach a suite step either.
#
# ***IT DOES NOT COMPARE THE FILES TO EACH OTHER AND STOP THERE.***  Two files
# agreeing on a wrong number is exactly as broken as two files disagreeing, and
# a test that only cross-checked them would go green on it.  So the counts are
# RE-DERIVED FROM sdsys/newvoc, and each file is checked against that.
#
# THE ARITHMETIC, which is verify-tiers.ps1's and is quoted rather than
# invented here:
#
#   base           = names in newvoc, less "%t" and the two list records
#   ADMINISTRATOR  = base + (TIER.ADD.ADMINISTRATOR lines - 1) + 4
#   PROGRAMMER     = base                                     + 4
#   STANDARD       = base - (TIER.OMIT.STANDARD  lines - 1)    + 4
#
# The "+ 4" is the four records every account gets that are not in newvoc; it
# is the same in all three sums, so it cancels out of any comparison BETWEEN
# tiers and is only load-bearing for the absolute numbers.

[CmdletBinding()]
param(
    # ***-Dir EXISTS SO THIS FILE CAN HAVE A POSITIVE CONTROL, AND THIS SESSION
    # IS WHY.***  Two checks were shipped hours apart that were wrong in
    # OPPOSITE directions - one matched the account name anywhere and passed on
    # the failure path, its replacement anchored on end-of-line and failed on
    # the success path - and both were written from a transcript of the path
    # they were not meant to catch.  A test nobody has watched fail is in the
    # same position.  Point this at a directory holding copies of the two
    # verifiers and it reads those instead; newvoc is always read from the real
    # tree, since the tree is the thing being compared against.
    [string] $Dir = ''
)

$ErrorActionPreference = 'Stop'

$pass = 0
$fail = 0

function Note([bool]$ok, [string]$what, [string]$detail = '') {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    $line = "  [{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $what
    if ($detail -ne '') { $line += " -- $detail" }
    Write-Output $line
}

Write-Output ''
Write-Output 'test-tiercounts-units: the tier VOC counts, against the tree and each other'

# --- 1. RE-DERIVE FROM THE DIRECTORY ----------------------------------------
$newvoc = Join-Path $PSScriptRoot '..\sdsys\newvoc'
if (-not (Test-Path -LiteralPath $newvoc)) {
    Write-Output ''
    Write-Output ("REFUSING - no newvoc directory at {0}, so nothing could be derived." -f $newvoc)
    exit 2
}
$names = @(Get-ChildItem -LiteralPath $newvoc -File)
$addAdmin = Join-Path $newvoc 'TIER.ADD.ADMINISTRATOR'
$omitStd  = Join-Path $newvoc 'TIER.OMIT.STANDARD'
foreach ($f in @($addAdmin, $omitStd)) {
    if (-not (Test-Path -LiteralPath $f)) {
        Write-Output ("REFUSING - {0} is missing; the arithmetic cannot be done." -f $f)
        exit 2
    }
}
$addLines  = @(Get-Content -LiteralPath $addAdmin).Count
$omitLines = @(Get-Content -LiteralPath $omitStd).Count

# ***THE NULL CASE, REFUSED OUT LOUD.***  An empty directory or an unreadable
# list record would make every sum below equal 4 and the file would then be
# comparing two verifiers against nonsense.
Note ($names.Count -gt 100) 'newvoc has a plausible number of names' ("{0} names" -f $names.Count)
Note ($addLines  -gt 1) 'TIER.ADD.ADMINISTRATOR is not empty' ("{0} lines" -f $addLines)
Note ($omitLines -gt 1) 'TIER.OMIT.STANDARD is not empty'     ("{0} lines" -f $omitLines)
if ($names.Count -le 100 -or $addLines -le 1 -or $omitLines -le 1) {
    Write-Output ''
    Write-Output 'REFUSING - the directory did not answer, so nothing below would mean anything.'
    exit 2
}

$base     = $names.Count - 3
$derived  = @{
    'STANDARD'      = $base - ($omitLines - 1) + 4
    'PROGRAMMER'    = $base                    + 4
    'ADMINISTRATOR' = $base + ($addLines  - 1) + 4
}
Write-Output ''
Write-Output ("  newvoc {0} names, base {1}; TIER.ADD.ADMINISTRATOR {2}, TIER.OMIT.STANDARD {3}" -f
              $names.Count, $base, $addLines, $omitLines)
Write-Output ("  derived: STANDARD {0}, PROGRAMMER {1}, ADMINISTRATOR {2}" -f
              $derived['STANDARD'], $derived['PROGRAMMER'], $derived['ADMINISTRATOR'])

# ***THE ARITHMETIC CHECKS ITSELF.***  ADMINISTRATOR minus PROGRAMMER must be
# the number of verbs TIER.ADD.ADMINISTRATOR adds, and PROGRAMMER minus
# STANDARD the number TIER.OMIT.STANDARD takes away.  Two independent routes to
# the same numbers, so a typo in one sum cannot pass quietly.
Note (($derived['ADMINISTRATOR'] - $derived['PROGRAMMER']) -eq ($addLines - 1)) `
     'ADMINISTRATOR - PROGRAMMER is what TIER.ADD.ADMINISTRATOR adds' `
     ("{0} = {1}" -f ($derived['ADMINISTRATOR'] - $derived['PROGRAMMER']), ($addLines - 1))
Note (($derived['PROGRAMMER'] - $derived['STANDARD']) -eq ($omitLines - 1)) `
     'PROGRAMMER - STANDARD is what TIER.OMIT.STANDARD removes' `
     ("{0} = {1}" -f ($derived['PROGRAMMER'] - $derived['STANDARD']), ($omitLines - 1))

# --- 2. READ WHAT EACH VERIFIER CLAIMS, BY PARSING IT ------------------------
# Read with the PARSER rather than a regex: a number in a COMMENT must not be
# mistaken for the constant, and this file's whole subject is stale numbers in
# comments.  Each verifier holds its tiers as a list of objects with a Tier
# name and a count property - Voc in one, Count in the other.
function Get-ClaimedCounts([string]$Path, [string]$CountKey) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
               ($Path -replace '\\', '/'), [ref]$t, [ref]$e)
    if ($e.Count -ne 0) { throw ("{0} has {1} parse error(s)" -f $Path, $e.Count) }
    $out = @{}
    foreach ($h in $ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)) {
        $tier = $null; $cnt = $null
        foreach ($pair in $h.KeyValuePairs) {
            $k = $pair.Item1.Extent.Text.Trim("'", '"', ' ')
            $v = $pair.Item2.Extent.Text.Trim("'", '"', ' ')
            if ($k -eq 'Tier')      { $tier = $v }
            if ($k -eq $CountKey)   { $cnt  = $v }
        }
        if ($null -ne $tier -and $null -ne $cnt -and $cnt -match '^\d+$') { $out[$tier] = [int]$cnt }
    }
    return $out
}

$files = @(
    @{ Name = 'verify-tiers.ps1';   Key = 'Count' },
    @{ Name = 'verify-tierapi.ps1'; Key = 'Voc'   }
)
$readFrom = $(if ($Dir -ne '') { $Dir } else { $PSScriptRoot })
Write-Output ''
Write-Output ("  verifiers read from: {0}" -f $readFrom)
foreach ($f in $files) {
    $p = Join-Path $readFrom $f.Name
    if (-not (Test-Path -LiteralPath $p)) { Note $false ("{0} exists" -f $f.Name); continue }
    $claimed = Get-ClaimedCounts $p $f.Key
    Note ($claimed.Keys.Count -eq 3) ("{0}: three tiers found by the parser" -f $f.Name) `
         ("got {0}: {1}" -f $claimed.Keys.Count, (($claimed.Keys | Sort-Object) -join ', '))
    foreach ($tier in @('STANDARD', 'PROGRAMMER', 'ADMINISTRATOR')) {
        if (-not $claimed.ContainsKey($tier)) { Note $false ("{0}: {1} present" -f $f.Name, $tier); continue }
        Note ($claimed[$tier] -eq $derived[$tier]) ("{0}: {1}" -f $f.Name, $tier) `
             ("claims {0}, tree says {1}" -f $claimed[$tier], $derived[$tier])
    }
}

# ---------------------------------------------------------------------------
# 31 Aug 26 - AND THE LIST ITSELF, NOT ONLY THE COUNTS.  PRE_RELEASE 89/90.
#
# ***THIS GUARD PASSED WHILE THE SUITE FAILED, AND THAT IS THE HOLE IT LEAVES.***
# append.sd.path was added to TIER.ADD.ADMINISTRATOR; the two COUNT constants
# were re-derived and this test went green, because counts were all it read.
# verify-tiers.ps1 carries a THIRD copy - $AdminVerbs, an independent
# transcription of the record - and nothing compared it, so the drift surfaced
# 20 minutes into a suite run as "add list length: expected 23, got 24".
#
# verify-tiers.ps1 compares $AdminVerbs against the INSTALLED record, which is
# right for a verifier and useless before a cycle.  This compares it against
# SOURCE, which is what makes it free.
$tiersPath = Join-Path $PSScriptRoot 'verify-tiers.ps1'
$addRecSrc = Join-Path $PSScriptRoot '..\sdsys\newvoc\TIER.ADD.ADMINISTRATOR'

if ((Test-Path -LiteralPath $tiersPath) -and (Test-Path -LiteralPath $addRecSrc)) {
    $tok = $null; $errs = $null
    $tAst = [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path $tiersPath), [ref]$tok, [ref]$errs)
    $assign = $tAst.Find({
        param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$AdminVerbs'
    }, $true)

    if ($null -eq $assign) {
        # REFUSE THE NULL CASE: not finding the list must not read as agreement.
        Note $false 'verify-tiers.ps1: $AdminVerbs found' 'no such assignment - it was renamed or removed'
    } else {
        $claimed  = @(& ([scriptblock]::Create($assign.Right.Extent.Text)))
        $shipped  = @(Get-Content -LiteralPath $addRecSrc | Select-Object -Skip 1)
        $diff     = @(Compare-Object $shipped $claimed -SyncWindow 100)
        Note ($claimed.Count -gt 0) 'verify-tiers.ps1: $AdminVerbs is not empty' "$($claimed.Count) name(s)"
        Note ($diff.Count -eq 0) 'verify-tiers.ps1: $AdminVerbs matches source TIER.ADD.ADMINISTRATOR' `
             $(if ($diff.Count -eq 0) { "$($claimed.Count) names agree" }
               else { ($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ' })
    }
}

Write-Output ''
if ($fail -eq 0 -and $pass -gt 0) {
    Write-Output ("test-tiercounts-units: PASSED - {0} of {0} checks passed." -f $pass)
    exit 0
}
Write-Output ("test-tiercounts-units: FAILED - {0} passed, {1} failed." -f $pass, $fail)
Write-Output '  A count that disagrees with the tree is the VERIFIER being stale, not the'
Write-Output '  product: re-derive it from newvoc rather than copying the other file.'
exit 1
