# test-sshpreflight-units.ps1 - ssh-preflight.ps1 reads SD's own sshd_config blocks as SD's (RELEASE_1.1 316).
#
#   powershell -ExecutionPolicy Bypass -File test-sshpreflight-units.ps1
#
# Free tier: no install, no elevation, nothing outside a scratch folder it makes and removes.  It takes Get-Directives and the
# four marker assignments OUT OF ssh-preflight.ps1 by its syntax tree (the script itself reads the machine at top level, so it
# is not dot-sourced) and drives the function on fixture files:
#   P1 a stock file gives the stock directives
#   P2 stock + SD's ssh-only block gives the same list (the block is SD's)
#   P3 stock + remote administration's OPEN fence gives the same list (sit3 step 9 refused on exactly this fence)
#   P4 stock + the SHUT fence ("DenyUsers *") gives the same list (remote.sdsys off leaves it; only the uninstall removes it)
#   P5 CONTROL: a directive somebody else added outside both blocks is still seen
#   P6 CONTROL: a directive after the fence's END is still seen (the fence closes)
# Exit 0 all pass, 1 a row failed, 2 could not run.
#
# START-HISTORY:
# 15 Nov 26  New (RELEASE_1.1 316): VM sit3 step 9, a reinstall over an install with remote administration opened, was refused
#            "configured by somebody" on remote administration's own fence.
# END-HISTORY

$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot 'ssh-preflight.ps1'
[Console]::Out.WriteLine("test-sshpreflight-units: reading $target")
if (-not (Test-Path -LiteralPath $target)) { [Console]::Out.WriteLine('CANNOT RUN: ssh-preflight.ps1 not found'); exit 2 }

$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tok, [ref]$err)
if ($err.Count -ne 0) { [Console]::Out.WriteLine("CANNOT RUN: ssh-preflight.ps1 has $($err.Count) parse errors"); exit 2 }

$fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-Directives' }, $true))
$want = @('SdBegin', 'SdEnd', 'RadminBeginPrefix', 'RadminEnd')
$assigns = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $want -contains $n.Left.VariablePath.UserPath }, $false))
[Console]::Out.WriteLine("  found: Get-Directives x$($fn.Count); markers $(@($assigns | ForEach-Object { $_.Left.VariablePath.UserPath }) -join ',')")
if ($fn.Count -ne 1 -or $assigns.Count -ne $want.Count) { [Console]::Out.WriteLine('CANNOT RUN: Get-Directives or a marker assignment is missing'); exit 2 }

foreach ($a in $assigns) { Invoke-Expression $a.Extent.Text }
Invoke-Expression $fn[0].Extent.Text

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sshpreflight-units-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
$stock = @('# comment', 'AuthorizedKeysFile	.ssh/authorized_keys', 'Subsystem	sftp	sftp-server.exe',
           'Match Group administrators', '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys')
$sdBlock = @($SdBegin, 'AllowGroups sdssh', 'Match Group sdsshonly', '    ForceCommand "C:\Program Files\SD\usr\bin\sd.exe"', $SdEnd)
$open = @(($RadminBeginPrefix + ' - remote-admin.ps1 writes this; do not edit within this fence ---'),
          'Match User sdradmin,acevm\sdradmin', '    AuthenticationMethods password', '    PasswordAuthentication yes',
          '    ForceCommand "C:\Program Files\SD\usr\bin\sd.exe"', $RadminEnd)
$shut = @(($RadminBeginPrefix + ' - remote-admin.ps1 writes this; do not edit within this fence ---'),
          'Match User sdradmin,acevm\sdradmin', '    DenyUsers *', $RadminEnd)

function Get-For([string]$name, [string[]]$lines) {
    $p = Join-Path $scratch $name
    [IO.File]::WriteAllLines($p, $lines)
    return ((Get-Directives $p) -join ' | ')
}
$rows = @()
try {
    $base = Get-For 'stock' $stock
    [Console]::Out.WriteLine("  stock directives: $base")
    $rows += , @('P1 a stock file gives its 4 directives', ((@(Get-Directives (Join-Path $scratch 'stock')).Count -eq 4)), $base)
    $r = Get-For 'sd' ($sdBlock + $stock);              $rows += , @('P2 SD''s ssh-only block is not counted', ($r -ceq $base), $r)
    $r = Get-For 'open' ($sdBlock + $open + $stock);    $rows += , @('P3 the OPEN remote administration fence is not counted', ($r -ceq $base), $r)
    $r = Get-For 'shut' ($sdBlock + $shut + $stock);    $rows += , @('P4 the SHUT remote administration fence is not counted', ($r -ceq $base), $r)
    $r = Get-For 'other' ($sdBlock + $shut + @('PermitRootLogin yes') + $stock)
    $rows += , @('P5 CONTROL a directive somebody else added outside both blocks is seen', ($r -match 'PermitRootLogin yes'), $r)
    $r = Get-For 'after' ($stock + $open + @('Match Group developers', '    ForceCommand none'))
    $rows += , @('P6 CONTROL a directive after the fence''s END is seen', (($r -match 'Match Group developers') -and ($r -match 'ForceCommand none')), $r)
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

$bad = 0
foreach ($row in $rows) {
    $ok = [bool]$row[1]
    if (-not $ok) { $bad++ }
    [Console]::Out.WriteLine(('  [{0}] {1}{2}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $row[0], $(if ($ok) { '' } else { '   <- ' + $row[2] })))
}
if ($rows.Count -ne 6) { [Console]::Out.WriteLine("CANNOT RUN: expected 6 rows, made $($rows.Count)"); exit 2 }
[Console]::Out.WriteLine("test-sshpreflight-units: $($rows.Count - $bad) of $($rows.Count) passed")
if ($bad) { exit 1 } else { exit 0 }
