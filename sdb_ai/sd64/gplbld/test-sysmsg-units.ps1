<#
.SYNOPSIS
    Drives every verifier's Get-SysMsgPattern against a reconstruction of what
    SD prints for every message that verifier names.  No elevation, no run
    number, no accounts - it reads the installed messages and nothing else.

.DESCRIPTION
    ***THIS FUNCTION HAS GONE BLIND THREE TIMES, IN THREE DIFFERENT WAYS, AND
    EACH TIME IT WAS FOUND BY A RUN RATHER THAN BY A TEST.***

      20 Aug 2026  It took the text before the first "%".  Every message
                   verify-rdpaccount.ps1 named STARTS with %1, so the pattern
                   was the empty string and six checks reported FAIL on a run
                   where the feature worked perfectly.
      28 Aug 2026  PRE_RELEASE_FIXES.md 45.  The message FILES hold literal
                   backslash-n rather than newlines - sixteen in 10124 - and SD
                   renders each as a line break, so escaping the text as it
                   stands produced a pattern hunting a literal backslash the
                   output never contains.  A multi-line message could not be
                   matched at all.  It cost verify-profiledir.ps1 a FAIL on a
                   correct product, left verify-delaccount.ps1:553 incapable of
                   failing, and left :568 certain to fail on the first machine
                   whose profile hive is still mounted.

    So the third time it is a test, and the test is the cheap kind: it needs an
    install to read the messages from, and nothing else.

    ***IT LIFTS THE SHIPPED FUNCTIONS, IT DOES NOT COPY THEM.***  Same technique
    as test-reclaim-units.ps1: parse each verifier, pull Esc-Loose and
    Get-SysMsgPattern out of the AST, and call those.  A copy in here would be a
    copy that can go stale, and staleness is the whole subject.

    ***AND IT REFUSES THE NULL CASES OUT LOUD.***  A verifier whose functions
    cannot be lifted, or that names no messages at all, is a FAIL rather than a
    silent skip - the first version of this harness reported "0 messages" for
    verify-accountacl.ps1 and that refusal is what revealed the second call
    shape: that script has no Shown() wrapper and calls Get-SysMsgPattern
    directly.  A harness that had shrugged would have proved nothing about it
    while appearing to.

    ***WHAT IT CANNOT SEE.***  It proves a pattern matches the message as
    rendered.  It does not prove the verifier asked the right question with it -
    verify-delaccount.ps1:553 expects the message NOT to be shown, and that
    check would pass on a broken matcher and a working one alike.  Direction is
    the reader's job; this only rules out the matcher.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\test-sysmsg-units.ps1
#>

[CmdletBinding()]
param(
    # Point it at a directory of copies with a check removed and the matching
    # rows must go RED.  Default is the verifiers beside this script.
    [string] $Gplbld = ''
)

$ErrorActionPreference = 'Stop'

if ($Gplbld -eq '') { $Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path }
$msgDir = Join-Path $env:ProgramData 'SD\sdsys\messages'

Write-Host "test-sysmsg-units: verifiers in $Gplbld"
Write-Host "test-sysmsg-units: messages from $msgDir"

if (-not (Test-Path -LiteralPath $msgDir)) {
    Write-Host "  FAIL  $msgDir is not there - nothing could be measured" -ForegroundColor Red
    exit 2
}

$pass = 0; $fail = 0
function Note($ok, $label, $detail) {
    if ($ok) { $script:pass++; Write-Host ("  PASS  " + $label) }
    else     { $script:fail++; Write-Host ("  FAIL  " + $label + "  <- " + $detail) -ForegroundColor Red }
}

# SD's rendering: literal backslash-n becomes a line break, and the transcripts
# of 28 Aug show it DOUBLED - a blank line between every line of the message.
# The placeholders take a value the pattern will accept either way.
function Render([string]$raw) {
    $r = $raw.Replace('\n', "`r`n`r`n")
    for ($i = 1; $i -le 9; $i++) { $r = $r.Replace('%' + $i, 'SDXVALUE') }
    return "preamble`r`n" + $r + "`r`ntrailer"
}

$files = @(Get-ChildItem -LiteralPath $Gplbld -Filter 'verify-*.ps1' |
           Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'function Get-SysMsgPattern' })

# REFUSE THE NULL CASE.  Nought verifiers is a green run that measured nothing.
if ($files.Count -eq 0) {
    Write-Host '  FAIL  no verifier in that directory carries Get-SysMsgPattern - nothing was measured' -ForegroundColor Red
    exit 2
}
Write-Host ("test-sysmsg-units: " + $files.Count + " verifier(s) carry the helper")

foreach ($vf in $files) {
    Write-Host ''
    Write-Host ("=== " + $vf.Name)

    $src = Get-Content -LiteralPath $vf.FullName -Raw
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($vf.FullName, [ref]$t, [ref]$e)
    Note ($e.Count -eq 0) '  parses, 0 errors' ($e.Count.ToString() + ' parse error(s)')
    if ($e.Count -gt 0) { continue }

    # GET-SYSMSGPATTERN IS REQUIRED; Esc-Loose IS NOT, AND THAT IS WHAT MAKES
    # -Gplbld A REAL CONTROL.  Insisting on both meant a pre-45 copy failed at
    # the lift and the matcher was never run - "the fix is missing" rather than
    # "here is what it does without the fix".  Lifting whichever are there lets
    # the old matcher run and MISS 10075 and 10123 by itself, which is the
    # failure this test exists to catch.
    $has = @{}
    foreach ($w in @('Esc-Loose', 'Get-SysMsgPattern')) {
        $d = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $w }, $true))
        if ($d.Count -eq 1) { . ([scriptblock]::Create($d[0].Extent.Text)); $has[$w] = $true }
    }
    Note ($has.ContainsKey('Get-SysMsgPattern')) '  Get-SysMsgPattern lifted from the shipped file' 'not found, or defined more than once'
    if (-not $has.ContainsKey('Get-SysMsgPattern')) { continue }
    if (-not $has.ContainsKey('Esc-Loose')) {
        Write-Host '  note: no Esc-Loose in this copy - pre-45 matcher, multi-line messages are expected to MISS'
    }

    # verify-accountrules.ps1 builds its path from $Data, not $env:ProgramData.
    $Data = Join-Path $env:ProgramData 'SD'

    # Two call shapes: the verify-accountacl/verify-routes variant takes only
    # the number, the rest take a value list as well.
    $takesVals = (Get-Command Get-SysMsgPattern).Parameters.ContainsKey('vals')

    # BOTH SHAPES ARE SEARCHED FOR - see the header on why.
    $msgs = @($src | Select-String -Pattern '(?:Shown \$[a-zA-Z]+|Get-SysMsgPattern) (\d+)' -AllMatches |
              ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Note ($msgs.Count -gt 0) ("  names " + $msgs.Count + " message(s)") 'none found - this verifier would be proved nothing about'

    foreach ($m in $msgs) {
        $mf = Join-Path $msgDir $m
        if (-not (Test-Path -LiteralPath $mf)) {
            Note $false ("  msg " + $m) 'message file missing from the install'
            continue
        }
        $raw = (Get-Content -LiteralPath $mf -Raw).Trim()
        if ($takesVals) { $pat = Get-SysMsgPattern ([int]$m) @() } else { $pat = Get-SysMsgPattern ([int]$m) }
        $escapes = ([regex]::Matches($raw, [regex]::Escape('\n'))).Count
        $tag = $(if ($escapes -gt 0) { "multi-line, $escapes escapes" } else { 'single-line' })
        Note ($pat -ne '' -and (Render $raw) -match $pat) ("  msg " + $m + " matches as rendered (" + $tag + ")") 'no match'
    }
}

Write-Host ''
Write-Host ("test-sysmsg-units: " + $pass + " passed, " + $fail + " failed")
if ($fail -gt 0) { exit 1 }
exit 0
