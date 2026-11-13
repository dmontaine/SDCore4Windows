# test-psreturn-units.ps1 - no gplbld PowerShell function both RETURNS a value and lets a printed line into its output stream.
#
#   powershell -ExecutionPolicy Bypass -File <tree>\sdb_ai\sd64\gplbld\test-psreturn-units.ps1
#   powershell -ExecutionPolicy Bypass -File <tree>\sdb_ai\sd64\gplbld\test-psreturn-units.ps1 -SelfTest
#
# WHY.  A PowerShell function's output stream IS its return value.  A function that calls Write-Output (or a local function
# that does, such as every script's Say) and then returns $true, $false, a list or a password returns an ARRAY: the printed
# lines and the value.  13 Nov 2026 (RELEASE_1.1 277): sync-route-groups.ps1 Ensure-Group's "already there" made its $false
# truthy, so an existing sdssh was re-seeded on every run (members an administrator removed from ssh put back); the scan that
# found it found four more of the same shape (install-sdsys New-RandomPassword, install-editors Get-EditorVersion,
# restore-sshonly Get-GroupMembers, sync-route-groups Get-Members).  Memory ps-function-output-trap: the fourth time.
#
# THE RULE THIS HOLDS.  In a function that has a `return <value>`, a call of Write-Output or of a local printing function must
# not reach the output stream: pipe it to Out-Host or Out-Null, assign it, or cast it to [void].  It reads the scripts' syntax
# trees (System.Management.Automation.Language), so a call in a comment or a string does not count.
#
# Exit 0 none found, 1 one or more found (each named), 2 nothing to scan.  -SelfTest copies sync-route-groups.ps1 into a scratch
# folder with one `| Out-Host` taken off, and a synthetic function, and requires both to be found; the live files are not touched.
#
# START-HISTORY:
# 13 Nov 26  New, RELEASE_1.1 277.
# END-HISTORY

param([switch]$SelfTest)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Leaks([string]$path) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) { return ,@("PARSE ERROR in " + $path) }
    $fns = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $printers = @{ 'Write-Output' = $true; 'echo' = $true }
    foreach ($fn in $fns) {
        $wo = @($fn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Write-Output' }, $true)).Count
        if ($wo -gt 0) { $printers[$fn.Name] = $true }
    }
    $found = New-Object System.Collections.ArrayList
    foreach ($fn in $fns) {
        $rets = @($fn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ReturnStatementAst] -and $null -ne $n.Pipeline }, $true))
        if ($rets.Count -eq 0) { continue }
        $calls = @($fn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $printers.ContainsKey([string]$n.GetCommandName()) }, $true))
        foreach ($c in $calls) {
            if ($c.GetCommandName() -eq $fn.Name) { continue }
            $pipe = $c.Parent
            if ($pipe -is [System.Management.Automation.Language.PipelineAst]) {
                $last = $pipe.PipelineElements[$pipe.PipelineElements.Count - 1]
                if ($pipe.PipelineElements.Count -gt 1 -and $last -is [System.Management.Automation.Language.CommandAst] -and
                    @('Out-Host', 'Out-Null', 'Write-Host') -contains $last.GetCommandName()) { continue }
                $up = $pipe.Parent
                if ($up -is [System.Management.Automation.Language.AssignmentStatementAst]) { continue }
                if ($up -is [System.Management.Automation.Language.ConvertExpressionAst]) { continue }
                if ($up -is [System.Management.Automation.Language.SubExpressionAst] -or $up -is [System.Management.Automation.Language.ParenExpressionAst]) {
                    if ($up.Parent -is [System.Management.Automation.Language.ConvertExpressionAst]) { continue }
                }
            }
            [void]$found.Add(("{0}: {1} returns a value and line {2} lets '{3}' into its output" -f (Split-Path -Leaf $path), $fn.Name,
                              $c.Extent.StartLineNumber, $c.GetCommandName()))
        }
    }
    return ,$found.ToArray()
}

function Scan([string]$dir) {
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File)
    $all = New-Object System.Collections.ArrayList
    foreach ($f in $files) { foreach ($x in (Find-Leaks $f.FullName)) { [void]$all.Add($x) } }
    return ,@($files.Count, $all.ToArray())
}

Write-Output ("test-psreturn-units: scanning {0}\*.ps1" -f $here)
$r = Scan $here
$count = $r[0]; $leaks = @($r[1])
if ($count -lt 50) { Write-Output ("NO TREE: only {0} scripts found - expected the gplbld folder" -f $count); exit 2 }
Write-Output ("{0} scripts read" -f $count)
foreach ($l in $leaks) { Write-Output ("  [FAIL] " + $l) }
if ($leaks.Count -gt 0) { Write-Output ("{0} function(s) let printed lines into a returned value" -f $leaks.Count); exit 1 }
Write-Output "  [PASS] no function both returns a value and lets a printed line into its output"

if ($SelfTest) {
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("psreturn-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch | Out-Null
    try {
        $live = Join-Path $here 'sync-route-groups.ps1'
        $text = [System.IO.File]::ReadAllText($live)
        $old = '$($_.Exception.Message)" | Out-Host'
        $n = ([regex]::Matches($text, [regex]::Escape($old))).Count
        $m1 = $text.Replace($old, '$($_.Exception.Message)"')
        [System.IO.File]::WriteAllText((Join-Path $scratch 'm1.ps1'), $m1)
        $m2 = "function Say(`$m) { Write-Output `$m }`nfunction Get-Flag { Say 'checking'; return `$true }`n"
        [System.IO.File]::WriteAllText((Join-Path $scratch 'm2.ps1'), $m2)
        $c1 = @(Find-Leaks (Join-Path $scratch 'm1.ps1')).Count -gt 0
        $c2 = @(Find-Leaks (Join-Path $scratch 'm2.ps1')).Count -gt 0
        Write-Output ("  [{0}] mutant: sync-route-groups Get-Members without its Out-Host (the text matched {1} time(s))" -f ($(if ($c1 -and $n -eq 1) { 'pass' } else { 'FAIL' })), $n)
        Write-Output ("  [{0}] mutant: a synthetic Say-then-return function" -f ($(if ($c2) { 'pass' } else { 'FAIL' })))
        $after = [System.IO.File]::ReadAllText($live)
        Write-Output ("  live file unchanged: {0}" -f ($after -ceq $text))
        $holes = @(@(($c1 -and $n -eq 1), $c2) | Where-Object { -not $_ }).Count
        Write-Output ("self-test: 2 mutants, {0} not caught" -f $holes)
        if ($holes -gt 0 -or $after -cne $text) { exit 1 }
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $scratch -ErrorAction SilentlyContinue
    }
}
exit 0
