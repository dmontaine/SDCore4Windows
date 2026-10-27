# open-test-gates.ps1 - open the access gates the VERIFY SUITE'S unelevated half needs, for one account, on a TEST machine (RELEASE_1.1 192).
#
#   powershell -ExecutionPolicy Bypass -File C:\...\gplbld\open-test-gates.ps1 [-User <windows user>]       ELEVATED PowerShell
#
# WHY IT EXISTS.  Since 26 Oct 2026 (owner, via Linux 945e766) the installer opens NO gate: the installing user's account starts with every gate
# closed, like every account SD makes.  Most of the suite's unelevated steps compile BASIC, write a VOC or run a shell as that account, and refuse
# to run without bp-on, voc-on, sh-on and the rest ("can only be compiled or catalogued by an account that has bp.edit"; 18 of 26 steps could not run
# on the first install without the old box).  The suite is a developer's tool for a machine that is thrown away, so the gates are opened here, by name,
# and not by the installer.  DO NOT RUN THIS ON A REAL INSTALLATION.
#
# WHAT IT DOES.  MODIFY.ACCOUNT <user> sh-on os-on sd-on voc-on bp-on dict-on net-on shared-write-on, as sd -internal behind the one-shot marker (the way
# attach-account.ps1 ran MODIFY.ACCOUNT), then reads the register record back: fields 7 to 12, 14 and 15 must each be "yes".  Not opened here: ssh and the API
# (both), the files words and files-admin-on - the suite makes its own accounts for those.  The verdict is the register's, never sd's exit status.
# Exit 0 every gate reads yes, 1 one does not, 2 it could not run.

[CmdletBinding()]
param(
    [string] $User = $env:USERNAME,
    [string] $AppDir = 'C:\Program Files\SD',
    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Continue'
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Output ("open-test-gates: " + (Get-Date -Format 's'))
Write-Output ("  user    : $User")
Write-Output ("  sd.exe  : " + (Join-Path $AppDir 'usr\bin\sd.exe'))
Write-Output ("  register: " + (Join-Path $DataDir ('sdsys\accounts\' + $User.ToUpper())))
Write-Output ("  elevated: $elev")
if (-not $elev) { Write-Output 'REFUSED: run this in an ELEVATED PowerShell (the internal session of this product is elevated only).'; exit 2 }

$sd = Join-Path $AppDir 'usr\bin\sd.exe'
$record = Join-Path $DataDir ('sdsys\accounts\' + $User.ToUpper())
if (-not (Test-Path -LiteralPath $sd)) { Write-Output "REFUSED: no sd.exe at $sd"; exit 2 }
if (-not (Test-Path -LiteralPath $record)) { Write-Output "REFUSED: $User has no SD account (no register record at $record)"; exit 2 }
$svc = Get-Service -Name SD -ErrorAction SilentlyContinue
Write-Output ("  service : " + $(if ($svc) { $svc.Status } else { 'not found' }))
if (-not $svc -or $svc.Status -ne 'Running') { Write-Output 'REFUSED: the SD service is not running (Start-Service SD)'; exit 2 }

. (Join-Path $PSScriptRoot 'internal-marker.ps1')

$words = @('sh-on', 'os-on', 'sd-on', 'voc-on', 'bp-on', 'dict-on', 'net-on', 'shared-write-on')
$fields = @(@(7, 'sh-on'), @(8, 'os-on'), @(9, 'sd-on'), @(10, 'voc-on'), @(11, 'bp-on'), @(12, 'dict-on'), @(14, 'shared-write-on'), @(15, 'net-on'))

function Read-Gates {
    $lines = @()
    try { $lines = @([IO.File]::ReadAllText($record) -split "`r?`n") } catch { }
    $out = @()
    foreach ($p in $fields) {
        $n = [int] $p[0]
        $v = ''
        if ($lines.Count -ge $n) { $v = $lines[$n - 1].Trim().ToLower() }
        $out += ('{0,-16} field {1,2} = {2}' -f $p[1], $n, $(if ($v -eq '') { '(blank)' } else { $v }))
    }
    return $out
}

Write-Output "`n--- BEFORE"
Read-Gates | ForEach-Object { Write-Output ("  " + $_) }

$cmd = 'MODIFY.ACCOUNT ' + $User + ' ' + ($words -join ' ')
Write-Output "`n--- running: sd -internal $cmd   (stdin closed, 60 s limit)"
$null = Set-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') -Writer 'open-test-gates'
$tmp = Join-Path $env:TEMP 'open-test-gates.out'
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $env:ComSpec
$psi.Arguments = '/d /s /c ""' + $sd + '" -internal ' + $cmd + ' >"' + $tmp + '" 2>&1 <NUL"'
$psi.UseShellExecute = $false
$p = [Diagnostics.Process]::Start($psi)
if (-not $p.WaitForExit(60000)) { Write-Output 'TIMED OUT after 60 s' } else { Write-Output ("  exit " + $p.ExitCode + "   (says nothing about a refusal)") }
$null = Remove-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys')
if (Test-Path $tmp) { Get-Content $tmp | Select-Object -Skip 7 | ForEach-Object { Write-Output ("  | " + $_) } }

Write-Output "`n--- AFTER"
$after = Read-Gates
$after | ForEach-Object { Write-Output ("  " + $_) }
$closed = @($after | Where-Object { $_ -notmatch '= yes$' })
if ($closed.Count -gt 0) {
    Write-Output ("`nopen-test-gates: FAILED - " + $closed.Count + " gate(s) still not 'yes' for $User. Read the lines above.")
    exit 1
}
Write-Output "`nopen-test-gates: every gate reads yes for $User. Run the suite from an UNELEVATED PowerShell now."
exit 0
