<#
.SYNOPSIS
    Drives VerifyInstall2's Close-LeakedTranscripts.  No install, no elevation,
    no run token - it starts and stops transcripts in this process.

.DESCRIPTION
    ***WHY THIS EXISTS.***  RELEASE_1.1_FIXES.md 14.  VerifyInstall2 gained a
    transcript of its own on 11 Sep 2026, because without -Quiet it kept no
    record of anything it ran: the b136 suite went 27 of 27 and wrote 0 step
    files, and RELEASE_1.1 1 was closed on an exit code because the two rows
    that decide it had gone to a console.

    ***THE FIX HAD A WAY OF DESTROYING ITSELF, SILENTLY, AND THAT IS WHAT THIS
    GUARDS.***  Close-LeakedTranscripts drains EVERY open transcript in a
    while(true) loop, and its comment used to say - correctly, at the time -
    "THIS RUNNER HAS NO TRANSCRIPT OF ITS OWN, so every one closed here is a
    leak and there is nothing to restore".  The moment the runner gained one,
    that loop would close it after step 1, and every step after would go
    unrecorded.  THE SUITE WOULD STILL GO GREEN.  The transcript would still
    exist.  It would simply stop a twenty-seventh of the way in, and nobody
    reads a log to check that it ends where the run did.

    So the function restores it with -Append, and this drives that:

      1  the runner's transcript holds output from BEFORE a leaking step
      2  and output from AFTER it            <- the decisive one
      3  the leaked transcript holds only the leak, not the whole run
      4  the reported leak count is 1, not 2 - the runner's own is always
         among those closed, so reporting the raw count would accuse every
         step of a leak it did not commit

    ***THE MUTANT CONTROL IS ROW 2.***  Delete the -Append restore from
    VerifyInstall2 and row 2 goes red while 1, 3 and 4 stay green - which is
    exactly what the silent failure looks like.

    THE FUNCTION IS LIFTED BY AST, not copied, so it cannot drift from the one
    the runner actually uses.

.EXAMPLE
    C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\test-suitetranscript-units.ps1
#>

[CmdletBinding()]
param([switch] $Detail)

$ErrorActionPreference = 'Stop'

$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $here 'VerifyInstall2.ps1'

Write-Host "test-suitetranscript-units: subject $runner"

if (-not (Test-Path -LiteralPath $runner)) {
    Write-Host "  FAIL  $runner is not there - nothing was measured" -ForegroundColor Red
    exit 2
}

$pass = 0; $fail = 0
function Note($ok, $label, $why) {
    if ($ok) { $script:pass++; if ($Detail) { Write-Host ("  PASS  " + $label) } }
    else     { $script:fail++; Write-Host ("  FAIL  " + $label + "  <- " + $why) -ForegroundColor Red }
}

# --- lift the function out of the runner -----------------------------------
#
# BY AST, so a rename or a rewrite in VerifyInstall2 is picked up here rather
# than silently diverging from a copy.

$tok = $null; $perr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tok, [ref]$perr)
Note ($perr.Count -eq 0) 'VerifyInstall2.ps1 parses' ("$($perr.Count) parse error(s)")
if ($perr.Count -ne 0) { Write-Host "test-suitetranscript-units: $pass passed, $fail failed"; exit 1 }

$fn = $ast.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $n.Name -eq 'Close-LeakedTranscripts' }, $true)

Note ($fn.Count -eq 1) 'Close-LeakedTranscripts is defined exactly once' "found $($fn.Count)"
if ($fn.Count -ne 1) { Write-Host "test-suitetranscript-units: $pass passed, $fail failed"; exit 1 }

# ***REFUSE THE NULL CASE.***  A lifted function that no longer restores would
# make every row below pass by never testing a restore at all - the body is
# checked for the call before it is trusted to exercise it.
$body = $fn[0].Extent.Text
Note ($body -match 'Start-Transcript') `
     'the lifted function actually restores a transcript' `
     'no Start-Transcript in its body - rows 1-2 below would measure nothing'

. ([scriptblock]::Create($body))

# --- drive it ---------------------------------------------------------------

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('sdtranscript-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$null = New-Item -ItemType Directory -Path $tmp -Force
$script:transcript = Join-Path $tmp 'runner.log'
$leakPath          = Join-Path $tmp 'leaked.log'

$before = 'ZZBEFORE-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$after  = 'ZZAFTER-'  + [Guid]::NewGuid().ToString('N').Substring(0,8)
$inLeak = 'ZZLEAK-'   + [Guid]::NewGuid().ToString('N').Substring(0,8)
$noted  = ''

try {
    # drain anything this window already had open, so the counts below are ours
    while ($true) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null } catch { break }
    }

    Start-Transcript -Path $script:transcript -Force | Out-Null
    Write-Host $before

    # A STEP THAT LEAKS: it starts a transcript and never stops it, which is
    # precisely PRE_RELEASE 40's shape.
    Start-Transcript -Path $leakPath -Force | Out-Null
    Write-Host $inLeak

    $noted = (Close-LeakedTranscripts 'fake-step.ps1' 6>&1 | Out-String)

    Write-Host $after
} finally {
    while ($true) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null } catch { break }
    }
}

$runnerText = if (Test-Path -LiteralPath $script:transcript) { Get-Content -LiteralPath $script:transcript -Raw } else { '' }
$leakText   = if (Test-Path -LiteralPath $leakPath)          { Get-Content -LiteralPath $leakPath -Raw }          else { '' }

Note ($runnerText -ne '') 'the runner transcript was written at all' 'the file is missing or empty'
Note ($runnerText -match [regex]::Escape($before)) `
     'it holds output from BEFORE the leaking step' 'the marker written before the leak is absent'

# ***THE DECISIVE ROW.***  Without the -Append restore this is the only one that
# fails, and the suite it guards would still go green.
Note ($runnerText -match [regex]::Escape($after)) `
     'it holds output from AFTER the leaking step' `
     'THE RESTORE IS MISSING - the runner stopped recording at the first step that leaked'

Note ($leakText -match [regex]::Escape($inLeak)) `
     'the leaked transcript holds what the step wrote' 'the leak file did not capture its own marker'
Note (-not ($leakText -match [regex]::Escape($after))) `
     'and does NOT go on recording after it was closed' 'the leaked transcript was still open afterwards'

Note ($noted -match 'left 1 transcript\(s\) open') `
     'the note reports ONE leak, not two' `
     ("the runner's own must not be counted - it said: " + (($noted -replace '\s+',' ').Trim()))

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "test-suitetranscript-units: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
