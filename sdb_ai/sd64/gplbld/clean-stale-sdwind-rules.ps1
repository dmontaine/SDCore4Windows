# clean-stale-sdwind-rules.ps1 - remove the Windows "allow this program" firewall rules named sdwind.exe whose program no longer exists.
#
# Run in an ELEVATED PowerShell:
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\clean-stale-sdwind-rules.ps1
# Default is a DRY RUN that only lists. To delete:
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\clean-stale-sdwind-rules.ps1 -Delete
#
# RELEASE_1.1 176 / 183.  Windows makes one TCP and one UDP Public-profile Allow rule for each copy of sdwind.exe that listens.
# A rule whose program file is gone allows nothing useful and can match a different file later placed at that path.
# Only a rule that is named exactly sdwind.exe, is an inbound Allow, and whose program path does NOT exist is touched.
# A rule whose program exists is never touched, and the "SD API", "SD Core Solo API" and ssh rules are not named sdwind.exe.

param([switch]$Delete)

$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ('script   : ' + $PSCommandPath)
Write-Host ('mode     : ' + $(if ($Delete) { 'DELETE' } else { 'dry run (lists only)' }))
Write-Host ('elevated : ' + $isAdmin)
if (-not $isAdmin) { Write-Host 'REFUSED: not elevated; rules cannot be removed from an ordinary prompt.'; exit 2 }

$all = @(Get-NetFirewallRule -DisplayName 'sdwind.exe' -ErrorAction SilentlyContinue)
Write-Host ('rules named sdwind.exe: ' + $all.Count)
if ($all.Count -eq 0) { Write-Host 'REFUSED: no rule of that name; nothing was measured.'; exit 2 }

$stale = @()
foreach ($r in $all) {
  $prog = ($r | Get-NetFirewallApplicationFilter).Program
  $proto = ($r | Get-NetFirewallPortFilter).Protocol
  $exists = $false
  if ($prog -and $prog -ne 'Any') { $exists = Test-Path -LiteralPath $prog }
  $isStale = ($r.Direction -eq 'Inbound') -and ($r.Action -eq 'Allow') -and $prog -and ($prog -ne 'Any') -and (-not $exists)
  Write-Host ('  ' + $(if ($isStale) { 'STALE ' } else { 'keep  ' }) + $proto + '  program exists=' + $exists + '  ' + $prog)
  if ($isStale) { $stale += $r }
}
Write-Host ('stale: ' + $stale.Count + ' of ' + $all.Count)

if ($Delete -and $stale.Count -gt 0) {
  foreach ($r in $stale) { Remove-NetFirewallRule -Name $r.Name }
  $after = @(Get-NetFirewallRule -DisplayName 'sdwind.exe' -ErrorAction SilentlyContinue)
  Write-Host ('removed ' + $stale.Count + '; rules named sdwind.exe now: ' + $after.Count + ' (was ' + $all.Count + ')')
} elseif ($Delete) {
  Write-Host 'nothing stale; nothing removed.'
} else {
  Write-Host 'dry run: nothing changed. Add -Delete to remove the STALE ones.'
}
exit 0
