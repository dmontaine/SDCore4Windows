# probe-systemtask312.ps1 - RELEASE_1.1 312: run remote-admin.ps1's own Invoke-SystemTask (now through Task Scheduler's COM interface) with a
# trivial body, as SYSTEM, and show what came back, how long it took, and that no check task is left.  ELEVATED.  Changes nothing else:
# the task is made in \SD and removed again by the function itself.
$ErrorActionPreference = 'Stop'
$ra = Join-Path $PSScriptRoot 'remote-admin.ps1'
"probe-systemtask312 at $(Get-Date -Format s) as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
"source: $ra"
. (Join-Path $PSScriptRoot 'sd-taskfolder.ps1')
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ra, [ref]$t, [ref]$e)
foreach ($n in @('Out-Line', 'ConvertTo-PsQuoted', 'Invoke-SystemTask')) {
    $fd = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
    if ($null -eq $fd) { "REFUSED: no function $n in $ra"; exit 2 }
    . ([scriptblock]::Create($fd.Extent.Text))
}
$Prog = 'probe-systemtask312'
$body = @(
    '$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name',
    '[IO.File]::WriteAllText(@@OUT@@, ("ran as " + $me))',
    '[IO.File]::WriteAllText(@@ERR@@, "")',
    '[IO.File]::WriteAllText(@@CODE@@, "0")'
) -join "`n"
$t0 = Get-Date
$r = Invoke-SystemTask $body 'the probe body'
"elapsed: " + [int]((Get-Date) - $t0).TotalSeconds + " s"
"code: $($r.Code)"
"out: " + (($r.Out | Where-Object { $_ -ne '' }) -join ' | ')
"err: $($r.Err)"
$left = $null
try { $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $left = $svc.GetFolder('\SD').GetTask('sdcore-radmin-check') } catch { }
"check task left behind: " + ($null -ne $left)
if ($r.Code -eq 0 -and ($r.Out -join '') -match 'ran as NT AUTHORITY\\SYSTEM' -and $null -eq $left) { "PROBE PASS"; exit 0 } else { "PROBE FAIL"; exit 1 }
