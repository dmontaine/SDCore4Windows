<#
.SYNOPSIS
    Free guard over install-service.ps1's relay-account step.  No install, no
    elevation, no token.  RELEASE_1.1 43.

.DESCRIPTION
    install-service.ps1 runs HIDDEN inside the installer, and its relay-account
    step failed silently on the first cycle that carried it (16 Sep 2026): the
    New-LocalUser -Description literal was 88 characters against a cap of 48,
    the refusal was caught and swallowed, and the function's "return $false"
    travelled in an array with its own Say lines, which "-not" reads as $false.
    The install completed with no sdrelay and every API connection refused.
    verify-relayidentity found it an hour later, at the cost of a cycle.

    Every row here is a fact about the SCRIPT'S TEXT that the shell cannot
    check without running it elevated:
      1. the description literal is at most 48 characters (New-LocalUser's
         cap, measured at parameter binding - so it fails before any right
         is needed, which is how this test measures the cap itself);
      2. Install-RelayAccount returns NO value - the verdict is a script
         variable - so a Say line cannot make the caller's test truthy;
      3. the gate after it asks Windows for the account (Get-LocalUser), not
         only the variable;
      4. the -Remove path removes the account on BOTH exits (service present
         and absent).
    Mutant control on a COPY: the description lengthened by one character
    turns row 1 red; the live file is asserted unchanged.

.OUTPUTS
    Exit 0 all rows passed, 1 a row failed, 2 could not run.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here 'install-service.ps1'
if (-not (Test-Path -LiteralPath $script)) { Write-Host "COULD NOT RUN: no $script"; exit 2 }

$passed = 0; $failed = 0
function Row($name, $ok, $detail) {
    if ($ok) { $script:passed++; Write-Host "  PASS  $name  $detail" }
    else     { $script:failed++; Write-Host "  FAIL  $name  $detail" -ForegroundColor Red }
}

function Parse($path) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
    if ($e.Count) { throw "parse errors in $path" }
    return $ast
}

# The description literal: the string assigned to $RelayDescription.
function Get-Description($ast) {
    $a = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                        $args[0].Left.Extent.Text -eq '$RelayDescription' }, $true) | Select-Object -First 1
    if (-not $a) { return $null }
    return $a.Right.Extent.Text.Trim("'", '"')
}

# The cap, measured rather than remembered: New-LocalUser refuses a 49-character
# description at parameter binding, elevated or not, and accepts 48.
function Measure-Cap {
    $long = 'x' * 49
    $short = 'x' * 48
    $refused49 = $false; $accepted48 = $true
    try { New-LocalUser -Name zzcapprobe -NoPassword -WhatIf -Description $long | Out-Null } catch { $refused49 = $_.Exception.Message -match '48' }
    try { New-LocalUser -Name zzcapprobe -NoPassword -WhatIf -Description $short | Out-Null } catch {
        # Unelevated, -WhatIf may still reach an access check; only a LENGTH
        # complaint counts as a refusal of the 48-character string.
        if ($_.Exception.Message -match 'character length') { $accepted48 = $false }
    }
    return ($refused49 -and $accepted48)
}

Write-Host "test-installservice-units: $script"
$ast = Parse $script

Row 'New-LocalUser caps -Description at 48 (measured, 49 refused, 48 not)' (Measure-Cap) ''

$desc = Get-Description $ast
Row 'the description literal exists' ($null -ne $desc) "[$desc]"
Row 'the description is at most 48 characters' ($null -ne $desc -and $desc.Length -le 48) ("length " + $(if ($desc) { $desc.Length } else { 'n/a' }))

$fn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                     $args[0].Name -eq 'Install-RelayAccount' }, $true) | Select-Object -First 1
Row 'Install-RelayAccount is defined' ($null -ne $fn) ''
if ($fn) {
    $returnsValue = $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.ReturnStatementAst] -and
                                       $null -ne $args[0].Pipeline }, $true)
    Row 'Install-RelayAccount returns no VALUE (verdict is $script:RelayAccountOk)' ($returnsValue.Count -eq 0) ("$($returnsValue.Count) valued return(s)")
    $setsOk = $fn.Body.Extent.Text -match '\$script:RelayAccountOk\s*=\s*\$true'
    Row 'and it sets $script:RelayAccountOk = $true on the success path' $setsOk ''
}

$text = Get-Content -LiteralPath $script -Raw
$gate = $text -match 'Install-RelayAccount\s*\r?\n\s*\$relayMissing\s*=\s*\(-not \$script:RelayAccountOk\)\s*-or\s*\r?\n?\s*\(-not \(Get-LocalUser -Name \$RelayAccount'
Row 'the gate asks Windows for the account, not only the verdict' $gate ''

$removeCalls = ([regex]::Matches($text, 'Remove-RelayAccount(?!\s*\{)')).Count
Row '-Remove removes the account on both exits (2 call sites)' ($removeCalls -ge 2) "$removeCalls call(s)"

# Mutant control, on a copy: one character too many must turn row 3 red.
$copy = Join-Path $env:TEMP ('install-service-mutant-' + [guid]::NewGuid() + '.ps1')
try {
    $mut = $text -replace "(\`$RelayDescription = ')([^']*)(')", ('$1$2' + 'x' + '$3')
    Set-Content -LiteralPath $copy -Value $mut -Encoding UTF8 -NoNewline
    $mdesc = Get-Description (Parse $copy)
    Row 'mutant control: a 49-character description would fail row 3' ($null -ne $mdesc -and $mdesc.Length -eq 49 -and $mdesc.Length -gt 48) ("mutant length " + $(if ($mdesc) { $mdesc.Length } else { 'n/a' }))
} finally { Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue }
$liveDesc = Get-Description (Parse $script)
Row 'the live file is unchanged after the control' ($liveDesc -eq $desc) ''

Write-Host ''
Write-Host "test-installservice-units: $passed passed, $failed failed"
if ($passed -eq 0) { Write-Host 'COULD NOT RUN: no row ran'; exit 2 }
if ($failed) { exit 1 }
exit 0
