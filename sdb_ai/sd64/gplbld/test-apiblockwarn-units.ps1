# test-apiblockwarn-units.ps1 - RELEASE_1.1 317: api-firewall.ps1 names an inbound Block rule that stops the API, and never removes
# one (owner, 19 Nov 2026: "warn only").  Free tier: no elevation, no firewall change - the script's own Get-ApiBlockRules and
# Write-BlockWarning are taken out of its AST and run against STAND-IN firewall cmdlets defined here.
#
# Rows:
#   B1  a Block rule for SD's sdwind.exe (the path written in another case and with %ProgramFiles%) is named
#   B2  a Block rule for TCP port 4247 (any program) is named
#   B3  a Block rule for another program on port 22 is NOT named
#   B4  no Block rule at all (Windows THROWS "No matching MSFT_NetFirewallRule objects found ...") prints nothing
#   B5  any other read failure says "could not read the other firewall rules"
#   T1  -Show's ON branch and -Open both call Write-BlockWarning
#   T2  warn only: Remove-/Set-/Disable-NetFirewallRule appear only for SD's own rule ($ruleName)
#   M1-M3 mutants (in memory; the live file is hashed before and after): the program test, the port test, the Block filter
#         broken in turn - each must turn a row red
#
# Exit 0 all pass, 1 any fail, 2 nothing measured.  Prints every input and result.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $here 'api-firewall.ps1'
Write-Output "test-apiblockwarn-units: target $target"
if (-not (Test-Path -LiteralPath $target)) { Write-Output 'NO TREE: api-firewall.ps1 is not beside this script'; exit 2 }
$hashBefore = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
$text = [IO.File]::ReadAllText($target)

$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tok, [ref]$err)
if ($err.Count) { Write-Output ('FAIL parse: ' + $err.Count + ' errors'); exit 1 }
$fns = @{}
foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $fns[$f.Name] = $f.Extent.Text }
foreach ($n in 'Get-ApiBlockRules', 'Write-BlockWarning') {
    if (-not $fns.ContainsKey($n)) { Write-Output "FAIL: function $n not found in api-firewall.ps1"; exit 1 }
}
Write-Output ('functions found: ' + (($fns.Keys | Sort-Object) -join ', '))
# The port is the script's own ($Port = 4247 in SD Core's, 4249 in Solo's): this same file guards both products.
$pm = [regex]::Match($text, '(?m)^\$Port = (\d+)')
if (-not $pm.Success) { Write-Output 'FAIL: no "$Port = <n>" line in api-firewall.ps1'; exit 1 }
$apiPort = $pm.Groups[1].Value
Write-Output "the script's API port: $apiPort"

$fakeRoot = 'C:\Program Files\SD'
$script:pass = 0; $script:fail = 0

# ---- stand-ins for the firewall cmdlets ----
$script:MockRules = @()
$script:MockThrow = ''
function Get-NetFirewallRule {
    [CmdletBinding()] param($Direction, $Action, $Enabled, $Name)
    if ($script:MockThrow) { throw $script:MockThrow }
    return @($script:MockRules | Where-Object { $_.Direction -eq $Direction -and $_.Action -eq $Action -and $_.Enabled -eq $Enabled })
}
function Get-NetFirewallApplicationFilter {
    [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)] $InputObject)
    process { foreach ($a in @($InputObject.App)) { [pscustomobject]@{ Program = $a } } }
}
function Get-NetFirewallPortFilter {
    [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)] $InputObject)
    process { foreach ($p in @($InputObject.Ports)) { $p } }
}
function New-Rule($name, $app, $proto, $ports, $action = 'Block', $enabled = 'True') {
    [pscustomobject]@{ Name = $name; DisplayName = "display $name"; Direction = 'Inbound'; Action = $action; Enabled = $enabled
                       App = @($app); Ports = @([pscustomobject]@{ Protocol = $proto; LocalPort = @($ports) }) }
}

function Load([string]$getText, [string]$writeText) {
    $body = ($getText -replace '\$PSScriptRoot', ("'" + $fakeRoot + "'")) + "`n" + $writeText
    . ([scriptblock]::Create($body))
    Set-Item -Path function:global:Get-ApiBlockRules -Value (Get-Item function:Get-ApiBlockRules).ScriptBlock
    Set-Item -Path function:global:Write-BlockWarning -Value (Get-Item function:Write-BlockWarning).ScriptBlock
}

# Each case PRINTS with Write-Host (a function's Write-Output would fold into whatever captures it - the trap this file first fell
# into: the live rows vanished into "$live = Run-All") and records its verdict in $script:last for the mutant checks.
$script:last = @{}
function Run-Case([string]$id, [string]$what, $rules, [string]$throw, [scriptblock]$judge) {
    $script:MockRules = @($rules); $script:MockThrow = $throw
    $global:Port = [int]$apiPort
    $out = @(Write-BlockWarning 2>&1 | ForEach-Object { "$_" })
    $ok = [bool](& $judge $out)
    $shown = if ($out.Count) { $out -join ' | ' } else { '<nothing>' }
    $script:last[$id] = $ok
    if ($ok) { $script:pass++; Write-Host "  [PASS] $id $what`n         printed: $shown" }
    else { $script:fail++; Write-Host "  [FAIL] $id $what`n         printed: $shown" }
}

function Run-All {
    Run-Case 'B1' 'a Block rule for sdwind.exe (case and %ProgramFiles% differ) is named' `
        @((New-Rule 'ProgPrompt' '%ProgramFiles%\sd\USR\bin\SDWIND.exe' 'TCP' 'Any')) '' {
            param($o) ($o.Count -eq 1) -and ($o[0] -match 'WARNING') -and ($o[0] -match '"display ProgPrompt" \(ProgPrompt\) BLOCKS the API') }
    Run-Case 'B2' "a Block rule for TCP port $apiPort (any program) is named" `
        @((New-Rule 'PortApi' 'Any' 'TCP' @($apiPort))) '' {
            param($o) ($o.Count -eq 1) -and ($o[0] -match '\(PortApi\) BLOCKS the API') }
    Run-Case 'B3' 'a Block rule for another program on port 22 is not named (and an Allow rule for sdwind is not either)' `
        @((New-Rule 'Other' 'C:\Windows\notepad.exe' 'TCP' @('22')), (New-Rule 'AllowSd' 'C:\Program Files\SD\usr\bin\sdwind.exe' 'TCP' 'Any' 'Allow')) '' {
            param($o) $o.Count -eq 0 }
    Run-Case 'B4' 'no Block rule at all (Windows throws "No matching ...") prints nothing' `
        @() 'No matching MSFT_NetFirewallRule objects found by CIM query for instances of the root/standardcimv2/MSFT_NetFirewallRule class' {
            param($o) $o.Count -eq 0 }
    Run-Case 'B5' 'another read failure is said, not hidden' `
        @() 'Access is denied.' {
            param($o) ($o.Count -eq 1) -and ($o[0] -match 'could not read the other firewall rules \(Access is denied') }
}

Write-Host "`n=== the live functions"
Load $fns['Get-ApiBlockRules'] $fns['Write-BlockWarning']
Run-All
if ($script:last.Count -ne 5) { Write-Output ('FAIL: ' + $script:last.Count + ' live cases recorded, 5 expected'); exit 1 }

Write-Output "`n=== the script's text"
$showOn = [regex]::Match($text, "(?s)state is ON at the firewall - other computers on your network may reach the API'\s*\r?\n\s*Write-BlockWarning")
if ($showOn.Success) { $script:pass++; Write-Output '  [PASS] T1 -Show ON calls Write-BlockWarning' } else { $script:fail++; Write-Output '  [FAIL] T1 -Show ON does not call Write-BlockWarning' }
$openOn = [regex]::Match($text, '(?s)other computers MAY reach the SD API on port \$Port"\s*\r?\n\s*Write-BlockWarning')
if ($openOn.Success) { $script:pass++; Write-Output '  [PASS] T1 -Open calls Write-BlockWarning' } else { $script:fail++; Write-Output '  [FAIL] T1 -Open does not call Write-BlockWarning' }
# Only lines that CALL the cmdlet (a message that names it is not a call), and SD's own rule under its name now ($ruleName) or,
# in Solo's script, the name an older Solo used ($legacyRuleName, which Solo adopts or retires) - never anybody else's.
$changers = @([regex]::Matches($text, '(?m)^\s*(Remove|Set|Disable)-NetFirewallRule\b[^\r\n]*') | ForEach-Object { $_.Value.Trim() })
$bad = @($changers | Where-Object { $_ -notmatch '-Name \$(ruleName|legacyRuleName)\b' })
Write-Output ('  calls that change a rule: ' + $changers.Count)
foreach ($c in $changers) { Write-Output "     $c" }
if ($changers.Count -gt 0 -and $bad.Count -eq 0) { $script:pass++; Write-Output '  [PASS] T2 warn only: every rule change names SD''s own rule ($ruleName)' }
else { $script:fail++; Write-Output ('  [FAIL] T2 a rule change that is not SD''s own: ' + ($bad -join ' ; ')) }

Write-Output "`n=== mutants (in memory)"
$mutants = @(
    @{ id = 'M1'; what = 'the program test never matches'; from = '-ieq $sdwind) { $hit = $true }'; to = '-ieq $sdwind) { $hit = $false }'; must = 'B1' },
    @{ id = 'M2'; what = 'the port test never matches'; from = '-contains [string]$Port)) { $hit = $true }'; to = '-contains [string]$Port)) { $hit = $false }'; must = 'B2' },
    @{ id = 'M3'; what = 'the "none" answer is reported as a failure'; from = "-match 'No (matching )?MSFT_NetFirewallRule objects found'"; to = "-match 'NEVER-MATCHES'"; must = 'B4' }
)
$mutPass = 0
foreach ($m in $mutants) {
    $g = $fns['Get-ApiBlockRules']
    if (-not $g.Contains($m.from)) { $script:fail++; Write-Output ("  [FAIL] " + $m.id + ': the text to break is not in the function: ' + $m.from); continue }
    Load ($g.Replace($m.from, $m.to)) $fns['Write-BlockWarning']
    $savePass = $script:pass; $saveFail = $script:fail
    $script:last = @{}
    Write-Host ("  --- " + $m.id + ' (mutant: ' + $m.what + ')')
    Run-All
    $redNow = $script:fail - $saveFail
    $script:pass = $savePass; $script:fail = $saveFail
    $mustRed = ($script:last.ContainsKey($m.must) -and -not $script:last[$m.must])
    if ($mustRed) { $mutPass++; $script:pass++; Write-Output ("  [PASS] " + $m.id + ' ' + $m.what + ': ' + $m.must + ' went red (' + $redNow + ' red)') }
    else { $script:fail++; Write-Output ("  [FAIL] " + $m.id + ' ' + $m.what + ': ' + $m.must + ' stayed green') }
}

# ---- Solo only: solo-doors.ps1 -Show reads the firewall through COM (no CIM in an ssh logon), so its Get-ApiBlocks is run
# against a stand-in HNetCfg.FwPolicy2.  SD Core has no solo-doors.ps1 and says so.
$doors = Join-Path $here 'solo-doors.ps1'
if (-not (Test-Path -LiteralPath $doors)) { Write-Output "`n=== solo-doors.ps1: not in this tree (SD Core), COM rows not applicable" }
else {
    Write-Host "`n=== solo-doors.ps1 Get-ApiBlocks (COM)"
    $dHashBefore = (Get-FileHash -LiteralPath $doors -Algorithm SHA256).Hash
    $dtext = [IO.File]::ReadAllText($doors)
    $dast = [System.Management.Automation.Language.Parser]::ParseInput($dtext, [ref]$tok, [ref]$err)
    $gab = @($dast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-ApiBlocks' }, $true))
    if ($gab.Count -ne 1) { $script:fail++; Write-Output '  [FAIL] C0 Get-ApiBlocks not found in solo-doors.ps1' }
    else {
        $script:ComRules = @()
        function global:New-Object { param([string]$ComObject) if ($ComObject -ne 'HNetCfg.FwPolicy2') { throw "unexpected New-Object $ComObject" }; [pscustomobject]@{ Rules = $script:ComRules } }
        function ComRule($name, $app, $proto, $ports, $action = 0, $enabled = $true) {
            [pscustomobject]@{ Name = $name; Direction = 1; Action = $action; Enabled = $enabled; ApplicationName = $app; Protocol = $proto; LocalPorts = $ports } }
        $AppDir = $fakeRoot
        . ([scriptblock]::Create($gab[0].Extent.Text))
        $cases = @(
            @{ id = 'C1'; what = 'a Block rule for sdwind.exe is named'; rules = @((ComRule 'Prompt sdwind' '%ProgramFiles%\SD\usr\bin\sdwind.exe' 256 '*')); want = 1; match = '"Prompt sdwind" blocks the API' },
            @{ id = 'C2'; what = "a Block rule for TCP $apiPort is named"; rules = @((ComRule 'Port rule' '' 6 ('80,' + $apiPort))); want = 1; match = '"Port rule" blocks the API' },
            @{ id = 'C3'; what = 'an Allow rule for sdwind, a disabled Block rule and another port are not named';
               rules = @((ComRule 'Allow' 'C:\Program Files\SD\usr\bin\sdwind.exe' 6 '*' 1), (ComRule 'Off' 'C:\Program Files\SD\usr\bin\sdwind.exe' 6 '*' 0 $false), (ComRule 'Other' '' 6 '22')); want = 0; match = '' }
        )
        foreach ($c in $cases) {
            $script:ComRules = $c.rules
            $o = @(Get-ApiBlocks ([int]$apiPort) | ForEach-Object { "$_" })
            $ok = ($o.Count -eq $c.want) -and ($c.want -eq 0 -or ($o[0] -match '^api blocked: ' -and $o[0] -match [regex]::Escape($c.match)))
            $shown = if ($o.Count) { $o -join ' | ' } else { '<nothing>' }
            if ($ok) { $script:pass++; Write-Host ("  [PASS] " + $c.id + ' ' + $c.what + "`n         printed: $shown") }
            else { $script:fail++; Write-Host ("  [FAIL] " + $c.id + ' ' + $c.what + "`n         printed: $shown") }
        }
        Remove-Item function:global:New-Object
        $showCall = [regex]::Match($dtext, "(?s)Write-Output \('api mode: ' \+ \`$mode\)\s*\r?\n\s*if \(\`$mode -eq 'open'\) \{ Get-ApiBlocks \`$ApiPort \}")
        if ($showCall.Success) { $script:pass++; Write-Output '  [PASS] C4 -Show calls Get-ApiBlocks after "api mode: open"' } else { $script:fail++; Write-Output '  [FAIL] C4 -Show does not call Get-ApiBlocks after the api mode line' }
    }
    if ((Get-FileHash -LiteralPath $doors -Algorithm SHA256).Hash -ne $dHashBefore) { Write-Output 'FAIL: solo-doors.ps1 changed'; exit 1 }
}

$hashAfter = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
Write-Output ("`nlive file sha256 before " + $hashBefore.Substring(0, 16) + ' after ' + $hashAfter.Substring(0, 16))
if ($hashBefore -ne $hashAfter) { Write-Output 'FAIL: the live file changed'; exit 1 }
Write-Output ("test-apiblockwarn-units: " + $script:pass + ' passed, ' + $script:fail + ' failed')
if ($script:pass -eq 0) { Write-Output 'NOTHING MEASURED'; exit 2 }
if ($script:fail) { exit 1 }
exit 0
