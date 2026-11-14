# witness-vm-reinstall.ps1 - an install over an existing SD Core, and the uninstall after it (Core VM witness sitting,
# 13 Nov 2026).  Rows (RELEASE_1.1): 277 (an install over an existing sdssh must not put back a member an administrator took
# out), 202 F11 (the reinstall keeps remote administration's state; the uninstall removes its task, its sshd block and
# SDRADMIN from sdssh), 246 F11 (the reinstall keeps C:\ProgramData\SD\ai; the uninstall removes the service, the group and
# the program).
#
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-reinstall.ps1 -Phase Before
#   ... the owner runs the SAME installer again over the install (sheet step) ...
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-reinstall.ps1 -Phase AfterReinstall
#   ... the owner uninstalls SD (sheet step: remove the data and the accounts SD made) ...
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-reinstall.ps1 -Phase AfterUninstall
#
# ELEVATED PowerShell, in the VM.  Before needs SDSYS signed in (the seat) and the fixture zzwitoff (an SD account in sdssh).
# Before TAKES zzwitoff OUT OF sdssh by hand (the administrator's act the row is about) and opens remote administration if it
# is shut (the account exists from witness-vm-radmin.ps1, so no password is asked); its state goes to
# C:\SD-witness\reinstall-before.json for the later phases.  Every phase prints the state it read and its verdicts.
# Exit 0 passed, 1 FAIL, 2 could not run.
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting.  Parse-checked; not run (it needs the VM).
# END-HISTORY

param([Parameter(Mandatory = $true)][ValidateSet('Before', 'AfterReinstall', 'AfterUninstall')][string]$Phase)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')

Start-Wit ('witness-vm-reinstall-' + $Phase.ToLower()) @($Phase)
if (-not (Test-WitElevated)) { Write-Wit 'CANNOT RUN: not elevated.'; exit 2 }
$statePath = Join-Path $script:WitRoot 'reinstall-before.json'
$ra = Join-Path $env:ProgramFiles 'SD\remote-admin.ps1'
$cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
$aiDir = Join-Path $script:WitDataDir 'ai'

function Get-RaStatusText {
    if (-not (Test-Path -LiteralPath $ra)) { return '' }
    return ((& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ra -Status 2>&1 | ForEach-Object { [string]$_ }) -join "`n")
}
function Get-Facts {
    $f = [ordered]@{}
    $f.Sdssh = @(Get-WitGroupMembers 'sdssh' | Sort-Object)
    $f.RaStatus = Get-RaStatusText
    $f.RadminTask = @(Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction SilentlyContinue).Count
    $c = ''
    try { $c = [IO.File]::ReadAllText($cfg) } catch { }
    $f.SshdBlock = $c.Contains('# --- BEGIN SD remote administration')
    $f.SdBlock = ($c -match '(?m)^\s*AllowGroups\s+sdssh')
    $f.AiService = [string](Get-Service -Name sd-ai -ErrorAction SilentlyContinue).Status
    $f.AiGroup = $null -ne (Get-LocalGroup -Name sdaiusers -ErrorAction SilentlyContinue)
    $f.AiProgram = Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'SD\lib\sd-ai\sd-ai.exe')
    $f.AiState = Test-Path -LiteralPath $aiDir
    $f.AiStateCreated = ''
    if ($f.AiState) { $f.AiStateCreated = (Get-Item -LiteralPath $aiDir).CreationTimeUtc.ToString('o') }
    $f.SdradminUser = $null -ne (Get-LocalUser -Name SDRADMIN -ErrorAction SilentlyContinue)
    $f.SdExe = ''
    if (Test-Path -LiteralPath $script:WitSdExe) { $f.SdExe = (Get-FileHash -LiteralPath $script:WitSdExe -Algorithm SHA256).Hash }
    return $f
}
function Write-Facts($f) {
    foreach ($k in $f.Keys) {
        $v = $f[$k]
        if ($v -is [array]) { $v = '(' + ($v -join ',') + ')' }
        Write-Wit ('  ' + $k + ' = ' + ([string]$v -replace "`n", ' | '))
    }
}

if ($Phase -eq 'Before') {
    $w = Invoke-WitSd -Commands @('WHO') -Label 'the seat' -TimeoutSec 90
    if (-not $w.Ok) { Write-Wit 'CANNOT RUN: the SDSYS seat did not answer.'; exit 2 }
    $s = Get-RaStatusText
    if ($s -notmatch '(?m)^remote-admin=open') {
        $null = Invoke-WitSd -Commands @('remote.sdsys on', 'N', 'N') -Label 'open remote administration for the reinstall (SDRADMIN exists: nothing is asked)' -TimeoutSec 300
    }
    $sdssh = @(Get-WitGroupMembers 'sdssh')
    Write-Wit ('  sdssh before the hand edit: ' + ($sdssh -join ','))
    $removed = ''
    if ($sdssh -contains 'zzwitoff') {
        Remove-LocalGroupMember -Group sdssh -Member 'zzwitoff' -ErrorAction SilentlyContinue
        $removed = 'zzwitoff'
    }
    $f = Get-Facts
    Write-Facts $f
    if ($removed -eq '' -or @($f.Sdssh) -contains 'zzwitoff') { Add-WitResult '277' 'an administrator takes a member out of sdssh before the reinstall' 'NOT-MEASURED' 'zzwitoff was not in sdssh, or could not be taken out (run witness-vm-admin.ps1 -Only fixtures)' }
    else { Add-WitResult '277' 'zzwitoff taken out of sdssh by hand (the state the reinstall must keep)' 'INFO' ('sdssh now: ' + (@($f.Sdssh) -join ',')) }
    Set-WitVerdict '202' 'remote administration is open before the reinstall' $f.RaStatus '(?m)^remote-admin=open\s*$' @()
    $f.Removed = $removed
    ($f | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $statePath -Encoding ASCII
    Copy-Item -LiteralPath $cfg -Destination (Join-Path $script:WitRoot 'sshd_config.before-reinstall') -Force -ErrorAction SilentlyContinue
    Write-Wit ('  kept: ' + $statePath + ' and sshd_config.before-reinstall.  Now run the SAME installer over this install (sheet).')
}
else {
    if (-not (Test-Path -LiteralPath $statePath)) { Write-Wit ('CANNOT RUN: no ' + $statePath + ' (run -Phase Before first).'); exit 2 }
    $b = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $f = Get-Facts
    Write-Wit '  before:'
    foreach ($p in $b.PSObject.Properties) { Write-Wit ('    ' + $p.Name + ' = ' + (([string]($p.Value -join ',')) -replace "`n", ' | ')) }
    Write-Wit '  now:'
    Write-Facts $f
}

if ($Phase -eq 'AfterReinstall') {
    Add-WitResult 'context' ('sd.exe hash before ' + $b.SdExe + ', after ' + $f.SdExe) 'INFO' 'the same installer: equal is expected; the reinstall is proved by the log of the installer the owner ran'
    $added = @(@($f.Sdssh) | Where-Object { @($b.Sdssh) -notcontains $_ })
    if ([string]$b.Removed -eq '') { Add-WitResult '277' 'the reinstall did not re-seed sdssh' 'NOT-MEASURED' 'Before removed no member' }
    elseif (@($f.Sdssh) -contains [string]$b.Removed) { Add-WitResult '277' 'the reinstall did not put back the member an administrator took out of sdssh' 'FAIL' ('zzwitoff is in sdssh again; added: ' + ($added -join ',')) }
    else { Add-WitResult '277' 'the reinstall did not put back the member an administrator took out of sdssh' 'PASS' ('sdssh before ' + (@($b.Sdssh) -join ',') + '; after ' + (@($f.Sdssh) -join ',') + '; added: ' + $(if ($added.Count) { $added -join ',' } else { 'none' })) }
    Set-WitVerdict '202' 'F11: the reinstall keeps remote administration open (Linux keeps whichever form is there)' $f.RaStatus '(?m)^remote-admin=open\s*$' @('remote-admin=(inconsistent|absent)')
    Set-WitCompare '246' 'F11: the reinstall keeps C:\ProgramData\SD\ai (not recreated)' ([string]$b.AiStateCreated) ([string]$f.AiStateCreated)
    Set-WitCompare '246' 'the AI service runs after the reinstall' 'Running' $f.AiService
}

if ($Phase -eq 'AfterUninstall') {
    Set-WitCompare '202' 'F11: the uninstall removes the broker task' '0' ([string]$f.RadminTask)
    Set-WitCompare '202' 'F11: the uninstall removes the remote administration block from sshd_config' 'False' ([string]$f.SshdBlock)
    $inSsh = @($f.Sdssh) -contains 'sdradmin'
    Set-WitCompare '202' 'F11: SDRADMIN is not in sdssh after the uninstall' 'False' ([string]$inSsh) -Evidence ('sdssh: ' + (@($f.Sdssh) -join ','))
    Add-WitResult '202' ('the Windows account SDRADMIN after the uninstall: ' + $f.SdradminUser) 'INFO' 'it goes with the uninstaller''s "remove the Windows accounts SD Core created" answer'
    $bef = Join-Path $script:WitRoot 'sshd_config.before-radmin'
    if (Test-Path -LiteralPath $bef) {
        $d = @(Compare-Object (Get-Content -LiteralPath $bef) (Get-Content -LiteralPath $cfg -ErrorAction SilentlyContinue) | ForEach-Object { $_.SideIndicator + ' ' + $_.InputObject })
        Write-WitRaw 'sshd_config: before remote administration (<=) against after the uninstall (=>)' ($d -join "`n")
        Add-WitResult '202' ('F11: sshd_config differs from its copy before ON in ' + $d.Count + ' line(s) (SD''s own global block goes with the uninstall too; the lines are above)') 'INFO' 'no remote administration line may be among them'
        Set-WitCompare '202' 'F11: no remote administration line is left' '0' ([string]@($d | Where-Object { $_ -match 'sdradmin|SD remote administration' -and $_ -like '=>*' }).Count)
    }
    Set-WitCompare '246' 'F11: the uninstall removes the sd-ai service' '' $f.AiService
    Set-WitCompare '246' 'F11: the uninstall removes sdaiusers' 'False' ([string]$f.AiGroup)
    Set-WitCompare '246' 'F11: the uninstall removes the program lib\sd-ai\sd-ai.exe' 'False' ([string]$f.AiProgram)
    Add-WitResult '246' ('C:\ProgramData\SD\ai after the uninstall: ' + $f.AiState) 'INFO' 'it goes when the accounts and data go (Linux''s rule): read with the uninstaller''s answers'
}

$code = Complete-Wit
exit $code
