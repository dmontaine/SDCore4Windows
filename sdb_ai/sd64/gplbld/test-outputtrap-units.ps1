<#
.SYNOPSIS
    The free guard over PowerShell's print-and-return trap: a function that prints with
    Write-Output AND returns a value hands its caller both.

.DESCRIPTION
    ***THE TRAP.***  In PowerShell everything a function writes to the output stream IS its
    return value.  So a function that says "Write-Output 'sdwind is up'" and then "return $true"
    returns the ARRAY @('sdwind is up', $true) - and

        if (-not (Start-SD)) { fail }

    tests an array, which is true whether or not the server started.  The failure branch can never
    be reached, the screen shows nothing (the text went into the caller's variable), and the check
    that was meant to guard the step is a check with a check's name on it.

    ***IT HAS COST THIS PROJECT FOUR TIMES BEFORE THIS FILE EXISTED*** (the memory note
    ps-function-output-trap records three; RELEASE_1.1 76's verify-sshadmin rewrite was the
    fourth, on the owner's b202 run: "The property 'Ran' cannot be found").  Each time the local
    fix was to change one function.  ***THE FIX IS NEVER THE ONE-LINE CAUSE*** (CLAUDE.md): what
    would have caught it is a scan of every function in the harness, and the first scan found SIX
    live instances in files nobody was looking at, two of them REAL:

      verify-batchjob.ps1  Invoke-BatchJobPhase   $elevOk was ALWAYS true, so "elevation did not
                                                  happen" could never be detected
      allow-ssh-groups.ps1 Get-Patterns           the refusal text was folded into $patterns
                                                  next to a $null, and the caller carried on to
                                                  write an AllowGroups line containing it
                                                  (this file SHIPS)

    plus verify-createaccount's Start-SD, verify-apiremote's Stop-SD, verify-dictrename's
    Invoke-Upgrade (which worked only by member enumeration) and probe-nolockmsg's Invoke-SD
    (whose refusal text was swallowed before exit).

    WHAT IT ASSERTS.  No function in any non-test gplbld script contains a Write-Output CALL and a
    "return <expression>" of its own.  Use Write-Host (which reaches the transcript and the
    runner's step log, both of which capture every stream) or return a structured object and let
    the CALLER print it.  A function nested inside another is judged on its own body.

    WHAT IT DOES NOT ASSERT, SAID PLAINLY.  It sees an explicit Write-Output CALL and an explicit
    return.  It does not see a bare expression statement or a native command whose output is not
    captured (both also become return values), and it does not judge a function that prints with
    Write-Output and never returns a value (its callers must capture or discard the text, which is
    a different question).  Those are the same trap by other doors; this is the one that has cost.

    Exit 0 all checks passed, 1 a check failed, 2 it could not measure.
#>

$ErrorActionPreference = 'Stop'
$gplbld = Split-Path -Parent $PSCommandPath

$script:pass = 0
$script:fail = 0
function Check([string]$label, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ('  [PASS] ' + $label) }
    else     { $script:fail++; Write-Output ('  [FAIL] ' + $label + $(if ($detail) { '   <- ' + $detail } else { '' })) }
}

# Returns @{ Parsed = bool; Functions = <count>; Hits = @('name  writeOutput=n returns=m', ...) } for one file.
function Get-OutputTrapHits([string]$Path) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) { return @{ Parsed = $false; Functions = 0; Hits = @() } }
    $fns = @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $hits = @()
    foreach ($fn in $fns) {
        $body = $fn.Body
        # Nodes that belong to THIS function and not to one nested inside it.
        $own = { param($node)
            $p = $node.Parent
            while ($null -ne $p -and $p -ne $body) {
                if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
                $p = $p.Parent
            }
            return $true }
        $wo = @($body.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] -and $x.GetCommandName() -eq 'Write-Output' }, $true) |
                Where-Object { & $own $_ })
        $rt = @($body.FindAll({ param($x) $x -is [System.Management.Automation.Language.ReturnStatementAst] -and $null -ne $x.Pipeline }, $true) |
                Where-Object { & $own $_ })
        if ($wo.Count -gt 0 -and $rt.Count -gt 0) {
            $hits += ('{0}  writeOutput={1} returns={2}' -f $fn.Name, $wo.Count, $rt.Count)
        }
    }
    return @{ Parsed = $true; Functions = $fns.Count; Hits = $hits }
}

Write-Output 'test-outputtrap-units: the print-and-return trap'
Write-Output ('  gplbld : ' + $gplbld)
Write-Output ''

# --- fixtures: the live scan is only trusted once the scanner can tell these apart --------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('outtrap-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmp -Force
try {
    $fxTrap = Join-Path $tmp 'trap.ps1'
    $fxHost = Join-Path $tmp 'host.ps1'
    $fxOnly = Join-Path $tmp 'returnonly.ps1'
    $fxNest = Join-Path $tmp 'nested.ps1'
    $fxBare = Join-Path $tmp 'barereturn.ps1'
    Set-Content -LiteralPath $fxTrap -Encoding UTF8 -Value @('function Start-Thing {', '  Write-Output ''up''', '  return $true', '}')
    Set-Content -LiteralPath $fxHost -Encoding UTF8 -Value @('function Start-Thing {', '  Write-Host ''up''', '  return $true', '}')
    Set-Content -LiteralPath $fxOnly -Encoding UTF8 -Value @('function Get-Thing {', '  return 42', '}')
    # A print in the OUTER function and a return in a NESTED one are different functions.
    Set-Content -LiteralPath $fxNest -Encoding UTF8 -Value @('function Outer {', '  Write-Output ''hello''', '  function Inner { return 1 }', '  Inner | Out-Null', '}')
    # "return" with no value returns nothing, so printing and then a bare return is not the trap.
    Set-Content -LiteralPath $fxBare -Encoding UTF8 -Value @('function Say {', '  Write-Output ''hi''', '  return', '}')
    $rTrap = Get-OutputTrapHits $fxTrap; $rHost = Get-OutputTrapHits $fxHost; $rOnly = Get-OutputTrapHits $fxOnly
    $rNest = Get-OutputTrapHits $fxNest; $rBare = Get-OutputTrapHits $fxBare
    Check 'CONTROL: a function that Write-Outputs and returns a value is FLAGGED, by name' (($rTrap.Hits.Count -eq 1) -and ($rTrap.Hits[0] -match '^Start-Thing ')) ($rTrap.Hits -join ';')
    Check 'the same function with Write-Host is NOT flagged' ($rHost.Hits.Count -eq 0) ($rHost.Hits -join ';')
    Check 'a function that only returns is NOT flagged' ($rOnly.Hits.Count -eq 0) ($rOnly.Hits -join ';')
    Check 'a print in an outer function and a return in a NESTED one are not one function' ($rNest.Hits.Count -eq 0) ($rNest.Hits -join ';')
    Check 'a bare "return" (no value) after a print is NOT the trap' ($rBare.Hits.Count -eq 0) ($rBare.Hits -join ';')
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# --- the live scan --------------------------------------------------------------------------------
$files = @(Get-ChildItem -LiteralPath $gplbld -Filter '*.ps1' | Where-Object { $_.Name -notmatch '^test-' })
$scanned = 0; $fnCount = 0; $unparsed = @(); $bad = @()
foreach ($f in $files) {
    $r = Get-OutputTrapHits $f.FullName
    if (-not $r.Parsed) { $unparsed += $f.Name; continue }
    $scanned++
    $fnCount += $r.Functions
    foreach ($h in $r.Hits) { $bad += ($f.Name + ':' + $h) }
}
# THE NULL CASE, refused out loud: a scan that looked at nothing must not read as "no hits".
Check ("CONTROL: the scan really read the harness ({0} scripts, {1} functions)" -f $scanned, $fnCount) (($scanned -gt 100) -and ($fnCount -gt 200)) "scanned=$scanned functions=$fnCount"
Check 'every script parsed (a file the parser could not read was not scanned)' ($unparsed.Count -eq 0) ($unparsed -join ', ')
Check 'NO function in the harness prints with Write-Output AND returns a value' ($bad.Count -eq 0) ($bad -join ' | ')

Write-Output ''
if (($script:pass + $script:fail) -eq 0) { Write-Output 'REFUSED: no check ran'; exit 2 }
Write-Output ('test-outputtrap-units: {0} passed, {1} failed.' -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
