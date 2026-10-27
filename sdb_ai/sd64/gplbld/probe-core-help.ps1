# probe-core-help.ps1 - READ-ONLY look at why LOAD.HELP says "Could not enter the shared account" on the installed Core (RELEASE_1.1 187).
# Run in an ELEVATED PowerShell (the internal session of this product is elevated only).  It shows the shared account's register record,
# LIST.SHARED, and runs LOAD.HELP once, each with stdin closed so no prompt can hang it.  It changes nothing but what LOAD.HELP itself does.
$ErrorActionPreference = 'Continue'
$data = 'C:\ProgramData\SD'
$sd = 'C:\Program Files\SD\usr\bin\sd.exe'
. (Join-Path $PSScriptRoot 'internal-marker.ps1')
"time    : " + (Get-Date).ToString('s')
"sd.exe  : $sd  exists=" + (Test-Path $sd)
"elevated: " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not (Test-Path $sd)) { "REFUSED: no sd.exe"; exit 2 }
$svc = Get-Service -Name SD -ErrorAction SilentlyContinue
"service SD: " + $(if ($svc) { $svc.Status } else { 'not found' })
if (-not $svc -or $svc.Status -ne 'Running') { "REFUSED: the SD service is not running; start it first (Start-Service SD)"; exit 2 }
foreach ($cmd in 'CT ACCOUNTS shared', 'LIST.SHARED', 'LOAD.HELP') {
  "=== $cmd"
  $null = Set-SdInternalMarker -SdsysDir (Join-Path $data 'sdsys') -Writer 'probe-core-help'
  $out = Join-Path $env:TEMP 'probe-core-help.out'
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $env:ComSpec
  $psi.Arguments = '/d /s /c ""' + $sd + '" -internal ' + $cmd + ' >"' + $out + '" 2>&1 <NUL"'
  $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(60000)) { "TIMED OUT after 60 s" } else { "exit " + $p.ExitCode }
  Get-Content $out -ErrorAction SilentlyContinue | Select-Object -Skip 7 | Select-Object -First 25
}
"=== context.help in the shared account"
Get-ChildItem (Join-Path $data 'group_accounts\shared') -Force | Select-Object Name | Format-Table | Out-String
