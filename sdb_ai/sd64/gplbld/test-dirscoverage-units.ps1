# test-dirscoverage-units.ps1 - does sd.iss protect every sdsys directory that
# ships empty and is preserved?
#
#   powershell -ExecutionPolicy Bypass -File test-dirscoverage-units.ps1
#
# Exit 0 covered, 1 a directory is not covered, 2 the check measured nothing.
# NO INSTALL, NO ELEVATION, NO RUN TOKEN.  One of the free tests CLAUDE.md says
# to run on every change.
#
# ===========================================================================
# WHY THIS EXISTS
# ===========================================================================
#
# PRE_RELEASE_FIXES 132, and it is the guard 120 needed and did not get.
#
# TWO LISTS DESCRIBE ONE FACT AND THEY DRIFTED.  stage.py says which sdsys
# directories ship EMPTY (SDSYS_EMPTY) and which an upgrade PRESERVES rather
# than replaces (SDSYS_PRESERVE).  A directory in BOTH is at risk: the
# uninstaller takes an empty directory it created, and because the directory is
# preserved, no later install puts it back.  sd.iss protects them one at a time,
# by hand, in [Dirs].
#
# THE HAND-KEPT HALF HAS NOW BEEN WRONG TWICE, AND THE SECOND TIME WAS FOUND BY
# ACCIDENT:
#
#   PRE_RELEASE 120   bp, bp.out and batch.jobs - a site that ever reinstalled
#                     was unhardened for ever and told so on every install,
#                     while the remedy it printed named paths that did not
#                     exist and exited 2 as well.
#   PRE_RELEASE 132   cat, prt and $hold - the SAME defect, still open after
#                     120 shipped, found only because the witness run for 120
#                     swept every preserved directory instead of the three it
#                     had just fixed.
#
# AND ONLY ONE OF THE SIX EVER ANNOUNCED ITSELF.  secure-sysdirs.ps1 hardens bp
# and cat, so their absence reaches the closing box as "NOT locked (code 2)".
# NOTHING hardens bp.out, prt or $hold: those vanish in silence, and on the
# 2 Sep 2026 witness run prt and $hold had been gone for an entire uninstall
# and two reinstalls with nothing anywhere saying so.
#
# ***AND THE INSTALLER PROMISES THESE DIRECTORIES BY NAME.***  sd.iss's upgrade
# notice says "YOUR DATA IS UNTOUCHED: your accounts and their passwords, the
# account register, anything you catalogued, the print queue, held output, and
# any programs you wrote in SDSYS's own BP" - and its own comment says that
# sentence is generated from SDSYS_PRESERVE.  So the PROMISE tracked the
# ten-entry list while the PROTECTION tracked a three-entry one, and three of
# its six named items - cat, prt, $hold - were the ones being destroyed.
#
# SO THE FIX IS A COMPARISON, NOT A LONGER COMMENT.  stage.py is the authority
# on which directories ship empty and which are preserved; sd.iss is the
# authority on which are protected.  Read both and subtract.
#
# ===========================================================================
# WHAT COUNTS AS PROTECTED, AND WHY A [Dirs] LINE ALONE IS NOT ENOUGH
# ===========================================================================
#
# A [Dirs] entry must carry uninsneveruninstall.  Without it the entry creates
# the directory and the uninstaller still takes it, which is the defect wearing
# the fix's clothes - and it would score green against a check that only looked
# for the name.  The flag is tested, not assumed.
$ErrorActionPreference = 'Stop'

$root  = $PSScriptRoot
$stage = Join-Path $root 'stage.py'
$iss   = Join-Path $root 'sd.iss'

# ---------------------------------------------------------------------------
# THE EXEMPTIONS.  Declared here, in the guard, and NOT beside the [Dirs] block
# in sd.iss - PRE_RELEASE 112's reasoning.  The discipline that has failed twice
# is "open sd.iss when you add to SDSYS_EMPTY"; an exemption declared in sd.iss
# would let the next author skip this file and still go green.
#
# THERE IS EXACTLY ONE KIND OF EXEMPTION, AND IT IS THE ONE THAT HEALS.
#
#   recreated  - something else creates the directory when it is absent, so it
#                is repaired on every install exactly as a [Dirs] entry would
#                repair it.  THE REASON IS MACHINE-CHECKED below: if the named
#                script stops creating it, this test fails.
#
# ***A SECOND KIND WAS WRITTEN AND THEN DELETED THE SAME DAY, AND THE REASON IS
# WORTH KEEPING BECAUSE IT IS THE WHOLE DISTINCTION.***  $cred, os.users,
# os.users.dic and batch.jobs.dic were briefly exempted as "content": the
# install writes records into each, so none is empty at uninstall time and the
# uninstaller leaves it.  Owner's ruling, 2 Sep 2026 - "as long as the
# directories are not needed and reinstalled when the install after removal
# happens" - and having content does not meet it.  HAVING CONTENT MEANS THE
# UNINSTALLER DOES NOT TAKE THE DIRECTORY.  IT DOES NOT MEAN ANYTHING PUTS IT
# BACK.  A site whose $cred happened to be empty would lose it exactly as cat,
# prt and $hold were lost, and no later install would restore it - which is the
# whole shape of 120.  All four now hold [Dirs] entries instead, so the
# distinction survives here as a comment rather than as a category that would
# quietly accept the weaker guarantee again.
$exempt = @(
    @{ name = 'dumps'
       kind = 'recreated'
       by   = 'secure-dumps.ps1'
       why  = 'creates it when absent; its [Run] entry carries no Check:' }
)

# ---------------------------------------------------------------------------
function Get-PyList {
    param([string] $Text, [string] $Name)

    # From "NAME = [" to the first line that is a bare "]" at column 0.  The
    # entries are ('name', 'why') tuples; comment lines start with # and cannot
    # match, which is what keeps the prose out.
    $out = New-Object System.Collections.ArrayList
    $in  = $false
    foreach ($line in ($Text -split "`r?`n")) {
        if (-not $in) {
            if ($line -match ('^' + [regex]::Escape($Name) + '\s*=\s*\[')) { $in = $true }
            continue
        }
        if ($line -match '^\]') { break }
        if ($line -match "^\s*\(\s*'([^']+)'") { $null = $out.Add($Matches[1]) }
    }
    return $out
}

function Get-IssDirs {
    param([string] $Text)

    # Only the [Dirs] section, and only entries under {#DataDir}\sdsys\.  The
    # uninsneveruninstall flag is captured rather than assumed - see the header.
    $out = New-Object System.Collections.ArrayList
    $in  = $false
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\[Dirs\]')  { $in = $true;  continue }
        if ($line -match '^\[' -and $in) { break }
        if (-not $in) { continue }
        if ($line -match '^\s*;') { continue }
        if ($line -match '^\s*Name:\s*"\{#DataDir\}\\sdsys\\([^"]+)"') {
            $null = $out.Add([pscustomobject]@{
                name    = $Matches[1]
                neveruninst = ($line -match 'uninsneveruninstall')
            })
        }
    }
    return $out
}

# ---------------------------------------------------------------------------
Write-Output ('test-dirscoverage-units: stage.py ' + $stage)
Write-Output ('test-dirscoverage-units: sd.iss   ' + $iss)

foreach ($f in @($stage, $iss)) {
    if (-not (Test-Path -LiteralPath $f)) {
        Write-Output ('REFUSED: ' + $f + ' is not there.  Nothing was compared.')
        exit 2
    }
}

$stageText = Get-Content -LiteralPath $stage -Raw
$issText   = Get-Content -LiteralPath $iss   -Raw

$empty    = Get-PyList -Text $stageText -Name 'SDSYS_EMPTY'
$preserve = Get-PyList -Text $stageText -Name 'SDSYS_PRESERVE'
$dirs     = Get-IssDirs -Text $issText

Write-Output ('test-dirscoverage-units: SDSYS_EMPTY ' + $empty.Count +
              ', SDSYS_PRESERVE ' + $preserve.Count +
              ', [Dirs] under sdsys ' + $dirs.Count)

# --- THE NULL CASES, REFUSED OUT LOUD --------------------------------------
# A parse that silently found nothing looks exactly like a tree with no
# problems.  Each of these three is fatal on its own.
if ($empty.Count -eq 0) {
    Write-Output 'REFUSED: parsed 0 entries from SDSYS_EMPTY.  The parse is broken, not the tree.'
    exit 2
}
if ($preserve.Count -eq 0) {
    Write-Output 'REFUSED: parsed 0 entries from SDSYS_PRESERVE.  The parse is broken, not the tree.'
    exit 2
}
if ($dirs.Count -eq 0) {
    Write-Output 'REFUSED: parsed 0 [Dirs] entries under sdsys.  The parse is broken, not the tree.'
    exit 2
}

# --- THE CANARY -------------------------------------------------------------
# bp is in both python lists AND in [Dirs].  If the parse cannot find it, the
# parse is wrong and every verdict below is worthless.
if ($empty -notcontains 'bp' -or $preserve -notcontains 'bp' -or
    ($dirs | Where-Object { $_.name -eq 'bp' }).Count -eq 0) {
    Write-Output 'REFUSED: the canary "bp" was not found in all three lists.  The parse is wrong.'
    exit 2
}
Write-Output 'test-dirscoverage-units: canary ok - "bp" found in SDSYS_EMPTY, SDSYS_PRESERVE and [Dirs]'

# --- THE AT-RISK SET --------------------------------------------------------
$atRisk = @($empty | Where-Object { $preserve -contains $_ } | Sort-Object -Unique)
Write-Output ('test-dirscoverage-units: at risk (ships empty AND preserved): ' +
              ($atRisk -join ', '))
if ($atRisk.Count -eq 0) {
    Write-Output 'REFUSED: the two lists intersect in nothing.  That has never been true; the parse is wrong.'
    exit 2
}

# --- A NAME MAY NOT BE BOTH PROTECTED AND EXEMPT ---------------------------
$exemptNames = @($exempt | ForEach-Object { $_.name })
$both = @($exemptNames | Where-Object { $n = $_; ($dirs | Where-Object { $_.name -eq $n }).Count -gt 0 })
if ($both.Count -gt 0) {
    Write-Output ''
    Write-Output ('FAILED: named in BOTH [Dirs] and $exempt: ' + ($both -join ', '))
    Write-Output 'One or the other.  An exemption for something already protected is a false'
    Write-Output 'claim about why it is safe, and it will outlive the reason it names.'
    exit 1
}

# --- EVERY EXEMPTION IS PRINTED, AND "recreated" IS CHECKED ----------------
Write-Output ''
Write-Output 'Declared exemptions:'
$badReason = New-Object System.Collections.ArrayList
foreach ($e in $exempt) {
    $mark = ''
    if ($e.kind -eq 'recreated') {
        $script = Join-Path $root $e.by
        $ok = $false
        if (Test-Path -LiteralPath $script) {
            $t = Get-Content -LiteralPath $script -Raw
            $ok = ($t -match 'New-Item\s+-ItemType\s+Directory')
        }
        if (-not $ok) { $mark = '   <-- REASON NO LONGER TRUE'; $null = $badReason.Add($e.name) }
    }
    Write-Output ('  ' + $e.name.PadRight(16) + $e.kind.PadRight(11) +
                  $(if ($e.by) { $e.by + ' - ' } else { '' }) + $e.why + $mark)
}

if ($badReason.Count -gt 0) {
    Write-Output ''
    Write-Output ('FAILED: exemption reason no longer holds for: ' + ($badReason -join ', '))
    Write-Output 'The script named above no longer creates the directory when it is absent, so'
    Write-Output 'the exemption is now a hole.  Give it a [Dirs] entry or fix the script.'
    exit 1
}

# A KIND THIS FILE DOES NOT DEFINE IS A HOLE, NOT A TYPO.  "recreated" is the
# only kind whose reason is checked above; anything else would be waved through
# unverified, which is how the weaker guarantee got in once already.
$badKind = @($exempt | Where-Object { $_.kind -ne 'recreated' } | ForEach-Object { $_.name })
if ($badKind.Count -gt 0) {
    Write-Output ''
    Write-Output ('FAILED: exemption with an unknown kind: ' + ($badKind -join ', '))
    Write-Output 'The only exemption this guard can verify is kind = recreated, naming the'
    Write-Output 'script that creates the directory when it is absent.  Anything else is an'
    Write-Output 'unchecked claim - see the deleted "content" kind in the header for why.'
    exit 1
}

# --- A STALE EXEMPTION IS REPORTED, NOT FAILED -----------------------------
# stemcoverage's precedent: a name that is no longer at risk is a tidying job,
# not a hole.
$stale = @($exemptNames | Where-Object { $atRisk -notcontains $_ })
if ($stale.Count -gt 0) {
    Write-Output ''
    Write-Output ('$exempt names no longer at risk (stale, NOT a failure): ' + ($stale -join ', '))
}

# --- THE VERDICT ------------------------------------------------------------
$protected = @($dirs | Where-Object { $_.neveruninst } | ForEach-Object { $_.name })
$unflagged = @($dirs | Where-Object { -not $_.neveruninst } | ForEach-Object { $_.name })

$bad = New-Object System.Collections.ArrayList
foreach ($d in $atRisk) {
    if ($protected -contains $d)   { continue }
    if ($exemptNames -contains $d) { continue }
    $null = $bad.Add($d)
}

if ($unflagged.Count -gt 0) {
    Write-Output ''
    Write-Output ('FAILED: [Dirs] entries WITHOUT uninsneveruninstall: ' + ($unflagged -join ', '))
    Write-Output 'Such an entry creates the directory and lets the uninstaller take it again,'
    Write-Output 'which looks like the fix and is not one.'
    exit 1
}

if ($bad.Count -gt 0) {
    Write-Output ''
    Write-Output ('FAILED: ships empty, is preserved, and nothing protects it: ' + ($bad -join ', '))
    Write-Output ''
    Write-Output 'Add to [Dirs] in sd.iss, WITH uninsneveruninstall:'
    foreach ($d in $bad) { Write-Output ('    Name: "{#DataDir}\sdsys\' + $d + '"; Flags: uninsneveruninstall') }
    Write-Output ''
    Write-Output 'A [Dirs] entry carries no Check:, so it runs on every install and HEALS a tree'
    Write-Output 'that has already lost the directory - which is the half that made 120 a'
    Write-Output 'blocker, because no reinstall could put it back.'
    Write-Output ''
    Write-Output 'If something else already creates it when absent, declare it in $exempt in'
    Write-Output 'this file with kind = recreated and the script that does it, so the reason is'
    Write-Output 'checked rather than remembered.'
    exit 1
}

Write-Output ''
Write-Output ('test-dirscoverage-units: ' + ($atRisk.Count - $exemptNames.Count) + ' of ' +
              $atRisk.Count + ' at-risk director(y/ies) hold a [Dirs] entry, ' +
              $exemptNames.Count + ' declared exempt, 0 unprotected.')
Write-Output 'test-dirscoverage-units: PASSED - every sdsys directory that ships empty and is preserved is protected or declared.'
exit 0
