<#
.SYNOPSIS
    Free guard over verify-lcnames.ps1's elevated re-entry: the request/result
    round trip between the unelevated parent and the -Phase RunLegs child.
    No SD, no install, no elevation, no token.  RELEASE_1.1 45's fallout.

.DESCRIPTION
    Since RELEASE_1.1 45 an unelevated session cannot LOGTO SDSYS, so
    verify-lcnames runs its five SDSYS legs in an elevated re-entry of itself:
    the parent writes the command lists to a request file, the child runs each
    through the SDSYS seat (Invoke-SdSeatText, since 21 Sep 2026 - RELEASE_1.1
    76; it was Invoke-SD with a LOGTO SDSYS, which 64 refuses) and writes the
    raw outputs to a result file in sections, the parent reads them back.  Every row of that protocol is reached only
    inside a suite run that costs a token and an elevation, and a leg that
    silently came back EMPTY would read as "nothing matched" - ten red rows
    blamed on the product.  So both halves are lifted out of the live script
    by AST (they cannot drift), Invoke-SdSeatText and Invoke-ElevatedScript are
    replaced by stubs, and the round trip is driven here:

      1. four legs in, four answers out, each answer the stub's output for
         exactly that leg's commands (order and content);
      2. a leg the child did not answer comes back '' - not the previous leg's
         text, not $null;
      3. the child refuses the null case: no request file -> legs=0, exit 2;
      4. a multi-line SD output survives the section framing intact;
      5. control: a request whose section marker is broken yields 0 legs;
      6. a seat that did not run (the stub throws) leaves every answer '' and
         the parent prints why - added 21 Sep 2026 with the seat itself.

.OUTPUTS
    Exit 0 all rows passed, 1 a row failed, 2 could not run.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here 'verify-lcnames.ps1'
if (-not (Test-Path -LiteralPath $script)) { Write-Host "COULD NOT RUN: no $script"; exit 2 }

$passed = 0; $failed = 0
function Row($name, $ok, $detail) {
    if ($ok) { $script:passed++; Write-Host "  PASS  $name  $detail" }
    else     { $script:failed++; Write-Host "  FAIL  $name  $detail" -ForegroundColor Red }
}

$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$t, [ref]$e)
if ($e.Count) { Write-Host "COULD NOT RUN: $script has parse errors"; exit 2 }

# The parent half: the function, verbatim.
$fn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                     $args[0].Name -eq 'Invoke-SDElevatedLegs' }, $true) | Select-Object -First 1
if (-not $fn) { Write-Host 'COULD NOT RUN: Invoke-SDElevatedLegs is not in the script'; exit 2 }

# The child half: the top-level "if ($Phase -eq 'RunLegs') { ... }" block.  Its
# body is wrapped into a function here so "exit" becomes a return code we can
# read, and Invoke-SdSeatText is a stub that echoes its commands.
$ifAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and
                        $args[0].Clauses[0].Item1.Extent.Text -match "\`$Phase -eq 'RunLegs'" }, $true) | Select-Object -First 1
if (-not $ifAst) { Write-Host 'COULD NOT RUN: the RunLegs block is not in the script'; exit 2 }
$childBody = $ifAst.Clauses[0].Item2.Extent.Text        # the { ... } block
$childBody = $childBody -replace '\bexit (\d)\b', 'return $1'
# This test runs unelevated, so the child's administrator check is replaced by
# "is elevated" - and the replacement is asserted to have happened, so a
# reworded check cannot leave the test silently measuring the refusal path.
$adminCheck = '(?s)-not \(\[Security\.Principal\.WindowsPrincipal\] \[Security\.Principal\.WindowsIdentity\]::GetCurrent\(\)\s*\)\.IsInRole\(\[Security\.Principal\.WindowsBuiltInRole\]::Administrator\)'
if ($childBody -notmatch $adminCheck) { Write-Host 'COULD NOT RUN: the child''s administrator check is not where this test expects it'; exit 2 }
$childBody = $childBody -replace $adminCheck, '$false'

$sandbox = Join-Path $env:TEMP ('lcl-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $sandbox
try {
    # Child runner: a script file taking -RequestFile/-ResultFile, with the
    # lifted block and a stub Invoke-SdSeatText that answers "SD<n>: <command>"
    # per line - or THROWS, as the real one does when the seat did not run, when
    # the parent has set LCL_SEATFAIL (mode 'seatfail', section 6).
    $childPs1 = Join-Path $sandbox 'child.ps1'
    $childText = @(
        'param([string]$RequestFile, [string]$ResultFile)',
        '$Phase = ''RunLegs''',
        'function Stop-Transcript { }',
        'function Invoke-SdSeatText { param([string[]]$Commands, [int]$TimeoutSec = 90, [switch]$Internal)',
        '    if ($env:LCL_SEATFAIL -eq ''1'') { throw ''stub: the SDSYS seat did not run'' }',
        '    $i = 0; return (($Commands | ForEach-Object { $i++; "SD$i" + ": " + $_ }) -join "`n")',
        '}',
        # PARENTHESISED: inside an array literal the comma binds tighter than +,
        # so an unbracketed 'a' + $b + 'c', 'd' splits into stray elements and
        # the join puts newlines through the middle of a path (measured here).
        ('function Run-Child ' + $childBody),
        '$code = Run-Child',
        'if ($null -eq $code) { $code = 0 }',
        'exit $code'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($childPs1, $childText, (New-Object System.Text.UTF8Encoding($false)))

    # Parent runner: the lifted function, with Invoke-ElevatedScript replaced by
    # a stub that runs the launcher UNELEVATED - the launcher re-enters the real
    # script, so its path is rewritten to the child runner above.
    $parentPs1 = Join-Path $sandbox 'parent.ps1'
    $parentText = @(
        'param([string]$Mode)',
        ('$PSCommandPath = ''' + $childPs1 + ''''),
        '$script:childExit = -1',
        'function Invoke-ElevatedScript { param([string]$Launcher, [string]$Why)',
        '    $txt = [System.IO.File]::ReadAllText($Launcher)',
        '    if ($Mode -eq ''norun'') { return @{ Ok = $false; ExitCode = 2; Reason = ''stub: declined'' } }',
        '    # the launcher line is "& ''<child>'' -Phase ''RunLegs'' -RequestFile ''..'' -ResultFile ''..''"',
        '    if ($txt -notmatch "-RequestFile ''([^'']+)'' -ResultFile ''([^'']+)''") { return @{ Ok = $false; ExitCode = 2; Reason = ''stub: launcher unparsed'' } }',
        '    $req = $Matches[1]; $res = $Matches[2]',
        '    if ($Mode -eq ''noreq'') { Remove-Item -LiteralPath $req -Force }',
        '    if ($Mode -eq ''badmarker'') { $c = Get-Content -LiteralPath $req; $c = $c -replace ''^### '', ''## ''; [System.IO.File]::WriteAllLines($req, [string[]]$c) }',
        '    if ($Mode -eq ''seatfail'') { $env:LCL_SEATFAIL = ''1'' }',
        ('    & powershell -NoProfile -ExecutionPolicy Bypass -File ''' + $childPs1 + ''' -RequestFile $req -ResultFile $res | Out-Null'),
        '    $script:childExit = $LASTEXITCODE',
        '    return @{ Ok = $true; ExitCode = $LASTEXITCODE; Reason = '''' }',
        '}',
        $fn.Extent.Text,
        # 21 Sep 26 - no LOGTO SDSYS in the legs, matching verify-lcnames: the
        # seat's session already is SDSYS (RELEASE_1.1 76).
        '$legs = [ordered]@{',
        '    sysct   = @(''CT VOC ACCOUNTS'', ''LIST VOC WITH @ID LIKE "accounts"'')',
        '    copypct = @(''CT VOC COPYP'')',
        '    unknown = @(''ZZNOSUCHVERB'')',
        '    copyp   = @(''COPYP'')',
        '}',
        'Invoke-SDElevatedLegs $legs',
        '$a = $script:sdsysOut',
        'Write-Output (''CHILDEXIT='' + $script:childExit)',
        'Write-Output (''ANSWERTYPE='' + $a.GetType().Name)',
        'foreach ($k in $legs.Keys) { Write-Output (''ANSWER '' + $k + ''='' + ($a[$k] -replace "`n", ''|'')) }'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($parentPs1, $parentText, (New-Object System.Text.UTF8Encoding($false)))

    function Run-Parent([string]$mode) {
        # Start-Process with files, not "2>&1" - RELEASE_1.1 16: under
        # $ErrorActionPreference = 'Stop' a native exe's stderr line becomes a
        # terminating ErrorRecord in PowerShell 5.1.
        $so = Join-Path $sandbox ("out-$mode.txt"); $se = Join-Path $sandbox ("err-$mode.txt")
        $p = Start-Process -FilePath 'powershell.exe' -Wait -PassThru -NoNewWindow `
             -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $parentPs1 + '"'), '-Mode', $mode) `
             -RedirectStandardOutput $so -RedirectStandardError $se
        $out = @()
        if (Test-Path -LiteralPath $so) { $out += @(Get-Content -LiteralPath $so) }
        if (Test-Path -LiteralPath $se) { $out += @(Get-Content -LiteralPath $se) }
        $h = @{}
        foreach ($l in $out) {
            if ($l -match '^ANSWER (\w+)=(.*)$') { $h[$Matches[1]] = $Matches[2] }
            if ($l -match '^CHILDEXIT=(-?\d+)$') { $h['_exit'] = [int]$Matches[1] }
        }
        $h['_raw'] = ($out -join "`n")
        return $h
    }

    Write-Host "test-lcnameslegs-units: $script"
    Write-Host '--- 1. four legs round-trip, each answer its own leg''s commands ---'
    $r = Run-Parent 'ok'
    if ($r['_exit'] -ne 0) { Write-Host '--- raw parent output ---'; Write-Host $r['_raw']; Write-Host '---' }
    Row 'the child exited 0' ($r['_exit'] -eq 0) ("exit " + $r['_exit'])
    Row 'the parent echoed the real call (rule 1)' ($r['_raw'] -match "elevated legs argv: & '") ''
    # The first draft RETURNED the table, and its own Write-Output lines rode
    # along in the pipeline - the caller got an array and indexed strings.
    Row '$script:sdsysOut is a Hashtable, not a pipeline array' ($r['_raw'] -match '(?m)^ANSWERTYPE=Hashtable\s*$') ''
    Row 'sysct answer is the 2-line output of ITS commands' ($r['sysct'] -eq 'SD1: CT VOC ACCOUNTS|SD2: LIST VOC WITH @ID LIKE "accounts"') ("[" + $r['sysct'] + "]")
    Row 'copypct answer names CT VOC COPYP' ($r['copypct'] -eq 'SD1: CT VOC COPYP') ("[" + $r['copypct'] + "]")
    Row 'unknown answer names ZZNOSUCHVERB' ($r['unknown'] -eq 'SD1: ZZNOSUCHVERB') ''
    Row 'copyp answer names COPYP and NOT the unknown verb' ($r['copyp'] -eq 'SD1: COPYP') ''
    Row 'the four answers are all different (no leg leaked into another)' (@($r['sysct'], $r['copypct'], $r['unknown'], $r['copyp'] | Sort-Object -Unique).Count -eq 4) ''
    Row 'the parent reported 4 of 4 answered' ($r['_raw'] -match 'elevated legs answered: 4 of 4') ''

    Write-Host '--- 2. the elevation did not happen: every answer is '''' ---'
    $r = Run-Parent 'norun'
    # Fully parenthesised: in argument mode "(pipeline).Count -eq 0" hands Row
    # the array and then ".Count", "-eq", "0" as further arguments.
    $notEmpty = @(@('sysct','copypct','unknown','copyp') | Where-Object { $r[$_] -ne '' })
    Row 'every leg comes back empty, not null and not stale' ($notEmpty.Count -eq 0 -and $r.ContainsKey('sysct')) ("non-empty: " + ($notEmpty -join ','))
    Row 'and the parent says why' ($r['_raw'] -match 'did not run: stub: declined') ''

    Write-Host '--- 3. the child refuses the null case: no request file ---'
    $r = Run-Parent 'noreq'
    Row 'child exit 2 with no request file' ($r['_exit'] -eq 2) ("exit " + $r['_exit'])
    Row 'the parent saw legs=0 / no request file' ($r['_raw'] -match 'legs=0' -and $r['_raw'] -match 'no request file') ''
    $notEmpty = @(@('sysct','copypct','unknown','copyp') | Where-Object { $r[$_] -ne '' })
    Row 'and every answer is empty' ($notEmpty.Count -eq 0 -and $r.ContainsKey('sysct')) ("non-empty: " + ($notEmpty -join ','))

    Write-Host '--- 4. control: a broken section marker yields 0 legs, exit 2 ---'
    $r = Run-Parent 'badmarker'
    Row 'child exit 2 on a request with no ### sections' ($r['_exit'] -eq 2) ("exit " + $r['_exit'])
    Row 'the parent reported 0 of 4 answered' ($r['_raw'] -match 'answered: 0 of 4') ''

    # 21 Sep 26 - RELEASE_1.1 76.  The seat THROWS when it did not run (SDSYS not
    # signed in is the usual cause).  The child must turn that into an EMPTY
    # answer - the failing direction for every row that reads it - and say why
    # on a RESULT line the parent prints, never into a stale or partial answer.
    Write-Host '--- 6. the seat did not run: every answer is '''' and the parent says why ---'
    $r = Run-Parent 'seatfail'
    Row 'child still exits 0 (it answered every leg, with nothing)' ($r['_exit'] -eq 0) ("exit " + $r['_exit'])
    $notEmpty = @(@('sysct','copypct','unknown','copyp') | Where-Object { $r[$_] -ne '' })
    Row 'every leg comes back empty, not an error text' ($notEmpty.Count -eq 0 -and $r.ContainsKey('sysct')) ("non-empty: " + ($notEmpty -join ','))
    Row 'the parent printed the seat''s reason for a leg' ($r['_raw'] -match 'elevated half: seat did not run for leg sysct - stub: the SDSYS seat did not run') ''
    Row 'the parent reported 0 of 4 answered' ($r['_raw'] -match 'answered: 0 of 4') ''
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "test-lcnameslegs-units: $passed passed, $failed failed"
if ($passed -eq 0) { Write-Host 'COULD NOT RUN: no row ran'; exit 2 }
if ($failed) { exit 1 }
exit 0
