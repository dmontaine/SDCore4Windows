# diff-capture.ps1 - compare two capture-state -Manifest files and say what
# stopped existing.
#
#   powershell -ExecutionPolicy Bypass -File diff-capture.ps1 `
#       -Before state-first-....txt -After state-after-....txt
#
# ===========================================================================
# WHAT IT IS FOR
# ===========================================================================
#
# PRE_RELEASE_FIXES 134, the owner's invariant: "all the system files and
# directories that existed when sd was first installed need to exist after it
# is reinstalled."  capture-state -Manifest emits the two trees as sorted,
# root-relative D/F lines precisely so two captures can be diffed - and then
# nothing diffed them.  Reading 3,754 lines by eye is not a measurement, and
# the entries this serves (120, 132) are about directories that went missing
# QUIETLY.
#
# ***THE COMPARISON IS ONE-DIRECTIONAL AND THAT IS THE INVARIANT, NOT A
# SHORTCUT.*** A line in AFTER that is not in BEFORE is a file the site or the
# install added, which the invariant permits; a line in BEFORE that is not in
# AFTER is the violation.  Additions are counted and listed separately so the
# reader can see them, but only DISAPPEARANCES set the exit code.
#
# ===========================================================================
# THE THREE WAYS THIS COULD LIE, AND WHAT STOPS EACH
# ===========================================================================
#
# 1. ***A CAPTURE THAT COULD NOT READ A SUBTREE.***  capture-state marks such a
#    tree NOT COMPARABLE, because a subtree readable BEFORE and denied AFTER
#    appears here as hundreds of deleted files and reads as catastrophic data
#    loss.  This script REFUSES a pair where either side carries that mark
#    rather than printing a diff nobody should trust.
#
# 2. ***A MANIFEST THAT IS NOT THERE AT ALL.***  capture-state's -Manifest is
#    off by default, so the commonest mistake is diffing two captures that have
#    only the summary.  Parsing that yields zero lines on both sides, zero
#    disappearances, and a confident green.  Refused by name.
#
# 3. ***A TREE PRESENT ON ONE SIDE ONLY.***  If BEFORE has both trees and AFTER
#    has one, the missing tree is the finding - and comparing only the trees
#    they share would hide exactly that.  Reported, and fatal.
#
# It reads files the host can see.  The captures come back over the xfer share,
# so on this machine they are in C:\Users\dmont\sdxfer.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Before,
    [Parameter(Mandatory = $true)] [string] $After,

    # Paths whose disappearance is expected and is not a violation.  134 names
    # three classes that need settling before a diff is read as a verdict; this
    # is how one is declared, and every use of it is PRINTED so a suppressed
    # line is never a silent one.
    [string[]] $Expected = @()
)

$ErrorActionPreference = 'Stop'

function Read-Manifest {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Error = ("not found: " + $Path) }
    }
    $lines = Get-Content -LiteralPath $Path

    $inManifest = $false
    $tree       = $null
    $trees      = @{}
    $notCmp     = New-Object System.Collections.ArrayList

    foreach ($l in $lines) {
        if ($l -match '^=== SD tree manifest') { $inManifest = $true; continue }
        if ($inManifest -and $l -match '^=== ') { $inManifest = $false; continue }
        if (-not $inManifest) { continue }

        if ($l -match '^\s*NOT COMPARABLE') { [void]$notCmp.Add($l.Trim()); continue }
        if ($l -match '^\s*---\s+(.+?)\s*$') {
            $tree = $Matches[1]
            if (-not $trees.ContainsKey($tree)) { $trees[$tree] = New-Object System.Collections.ArrayList }
            continue
        }
        # A manifest row: six spaces, D or F, one space, then a root-relative
        # path.  Anchored on the LETTER so the section's own prose cannot be
        # mistaken for an entry.
        if ($null -ne $tree -and $l -match '^\s{4,}([DF])\s(.+)$') {
            [void]$trees[$tree].Add($Matches[1] + ' ' + $Matches[2])
        }
    }

    return @{ Trees = $trees; NotComparable = $notCmp }
}

Write-Host ('diff-capture: before  ' + $Before)
Write-Host ('diff-capture: after   ' + $After)

$b = Read-Manifest -Path $Before
$a = Read-Manifest -Path $After

foreach ($side in @(@('BEFORE', $b), @('AFTER', $a))) {
    if ($side[1].ContainsKey('Error')) {
        Write-Host ('diff-capture: REFUSED - ' + $side[0] + ' ' + $side[1].Error) -ForegroundColor Red
        exit 2
    }
}

# --- REFUSAL 2: NO MANIFEST -------------------------------------------------
$bCount = ($b.Trees.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
$aCount = ($a.Trees.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
if ($null -eq $bCount) { $bCount = 0 }
if ($null -eq $aCount) { $aCount = 0 }
Write-Host ('diff-capture: before has ' + $b.Trees.Count + ' tree(s), ' + $bCount + ' entries')
Write-Host ('diff-capture: after  has ' + $a.Trees.Count + ' tree(s), ' + $aCount + ' entries')

if ($bCount -eq 0 -or $aCount -eq 0) {
    Write-Host 'diff-capture: REFUSED - a side has NO manifest rows.' -ForegroundColor Red
    Write-Host 'capture-state -Manifest is OFF by default; a capture without it has only' -ForegroundColor Yellow
    Write-Host 'the summary, and diffing two of those finds nothing and looks green.' -ForegroundColor Yellow
    exit 2
}

# --- REFUSAL 1: NOT COMPARABLE ---------------------------------------------
if ($b.NotComparable.Count -gt 0 -or $a.NotComparable.Count -gt 0) {
    Write-Host 'diff-capture: REFUSED - a capture is marked NOT COMPARABLE.' -ForegroundColor Red
    $b.NotComparable | ForEach-Object { Write-Host ('  before: ' + $_) }
    $a.NotComparable | ForEach-Object { Write-Host ('  after : ' + $_) }
    Write-Host 'A subtree readable before and denied after shows here as mass deletion.' -ForegroundColor Yellow
    Write-Host 'Re-capture ELEVATED on both sides, then diff.' -ForegroundColor Yellow
    exit 2
}

# --- REFUSAL 3: A TREE ON ONE SIDE ONLY ------------------------------------
$onlyBefore = @($b.Trees.Keys | Where-Object { -not $a.Trees.ContainsKey($_) })
$onlyAfter  = @($a.Trees.Keys | Where-Object { -not $b.Trees.ContainsKey($_) })
if ($onlyBefore.Count -gt 0) {
    Write-Host ('diff-capture: A WHOLE TREE IS GONE: ' + ($onlyBefore -join ', ')) -ForegroundColor Red
    exit 1
}
if ($onlyAfter.Count -gt 0) {
    Write-Host ('diff-capture: note - a tree exists only AFTER: ' + ($onlyAfter -join ', '))
}

# --- THE COMPARISON --------------------------------------------------------
$totalGone  = 0
$totalAdded = 0
$suppressed = 0

foreach ($tree in ($b.Trees.Keys | Sort-Object)) {
    $bs = [System.Collections.Generic.HashSet[string]]::new([string[]]$b.Trees[$tree])
    $as = [System.Collections.Generic.HashSet[string]]::new([string[]]$a.Trees[$tree])

    $gone  = @($b.Trees[$tree] | Where-Object { -not $as.Contains($_) })
    $added = @($a.Trees[$tree] | Where-Object { -not $bs.Contains($_) })

    # An expected disappearance is REMOVED FROM THE VERDICT AND PRINTED, never
    # silently dropped.
    $kept = New-Object System.Collections.ArrayList
    foreach ($g in $gone) {
        $match = $false
        foreach ($e in $Expected) { if ($g -like ('* ' + $e) -or $g -like ('* ' + $e + '\*')) { $match = $true; break } }
        if ($match) { $suppressed++; Write-Host ('  EXPECTED-GONE  ' + $tree + '  ' + $g) -ForegroundColor DarkYellow }
        else { [void]$kept.Add($g) }
    }

    Write-Host ''
    Write-Host ('--- ' + $tree)
    Write-Host ('    before ' + $b.Trees[$tree].Count + '   after ' + $a.Trees[$tree].Count)
    Write-Host ('    DISAPPEARED ' + $kept.Count + '   added ' + $added.Count)

    if ($kept.Count -gt 0) {
        Write-Host '    --- these existed before and do NOT exist after ---' -ForegroundColor Red
        $kept | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor Red }
    }
    if ($added.Count -gt 0) {
        Write-Host '    --- new since the before-capture (allowed by the invariant) ---'
        $added | Select-Object -First 40 | ForEach-Object { Write-Host ('      ' + $_) }
        if ($added.Count -gt 40) { Write-Host ('      ... and ' + ($added.Count - 40) + ' more') }
    }

    $totalGone  += $kept.Count
    $totalAdded += $added.Count
}

Write-Host ''
Write-Host '================ VERDICT ================'
Write-Host ('  entries compared : ' + $bCount + ' before, ' + $aCount + ' after')
Write-Host ('  disappeared      : ' + $totalGone)
Write-Host ('  added            : ' + $totalAdded)
Write-Host ('  expected-gone    : ' + $suppressed)

if ($totalGone -gt 0) {
    Write-Host '  134 VIOLATED - something that existed before does not exist after.' -ForegroundColor Red
    exit 1
}
Write-Host '  134 HOLDS on this pair - nothing that existed before is missing after.' -ForegroundColor Green
exit 0
