# Set up the three shared folders on a guest, the way the record documents.
#
#   sdout   read-only   the installer goes in
#   xfer    read-write  results come back to the host AS TEXT - a probe doing
#                       Start-Transcript -Path \\vboxsvr\xfer\out.txt beats
#                       screenshots and beats keyboardputstring, which drops
#                       characters (HISTORY 1931)
#   gplbld  read-only   the tracked capture-state.ps1, the state instrument
#
# PERMANENT, not --transient: the record's --transient form is for a VM that is
# already running and locked, and these must survive the reboots leg 2 needs
# (PROJECT_STATUS 2654).  A RUNNING VM IS LOCKED and a permanent add fails, so
# this refuses unless the guest is powered off.
#
# guestcontrol is deliberately NOT used anywhere: it needs guest credentials and
# is forbidden by the record (HISTORY 5407).

[CmdletBinding()]
param([string]$Vm = 'Windows 11 - Test 1')

$ErrorActionPreference = 'Stop'
$vb = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'

if (-not (Test-Path -LiteralPath $vb)) { Write-Output "ABORT: no VBoxManage at $vb"; exit 2 }
Write-Output ("VBoxManage : " + $vb)
Write-Output ("guest      : " + $Vm)

$info  = & $vb showvminfo $Vm --machinereadable 2>&1
$state = ($info | Where-Object { $_ -match '^VMState=' }) -replace 'VMState=|"',''
Write-Output ("state      : " + $state)
if ($state -ne 'poweroff') {
    Write-Output "ABORT: the guest is not powered off.  A running VM is locked and a"
    Write-Output "       PERMANENT sharedfolder add fails on it.  Shut it down first."
    exit 2
}

# host side
$sdout  = 'C:/Users/dmont/sdout'
$xfer   = 'C:/Users/dmont/sdxfer'
$gplbld = 'C:/Users/dmont/Projects/sd4windows/sdb_ai/sd64/gplbld'

if (-not (Test-Path -LiteralPath $xfer)) {
    $null = New-Item -ItemType Directory -Path $xfer -Force
    Write-Output ("created    : " + $xfer)
}
foreach ($p in @($sdout, $xfer, $gplbld)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Output ("ABORT: host path missing: " + $p); exit 2 }
}

# what it already has, so re-running this is safe
$have = @($info | Where-Object { $_ -match '^SharedFolderNameMachineMapping' } |
          ForEach-Object { ($_ -split '=')[1].Trim('"') })
Write-Output ("existing   : " + $(if ($have.Count) { $have -join ', ' } else { '(none)' }))

$want = @(
    @{ Name = 'sdout';  Path = $sdout;  ReadOnly = $true  },
    @{ Name = 'xfer';   Path = $xfer;   ReadOnly = $false },
    @{ Name = 'gplbld'; Path = $gplbld; ReadOnly = $true  }
)

$added = 0
foreach ($w in $want) {
    if ($have -contains $w.Name) { Write-Output ("skip       : " + $w.Name + " already present"); continue }
    # NOT $args - that is a PowerShell AUTOMATIC variable, and the record has a
    # false verdict from exactly this: a probe named its parameter $args, it was
    # clobbered, Start-Process received no switches, and the gate passed
    # trivially (CLAUDE.md, 23 Aug 2026).
    $vbArgs = @('sharedfolder','add',$Vm,'--name',$w.Name,'--hostpath',$w.Path,'--automount')
    if ($w.ReadOnly) { $vbArgs += '--readonly' }
    Write-Output ("adding     : " + $w.Name + " -> " + $w.Path + $(if ($w.ReadOnly) { '  (read-only)' } else { '  (read-write)' }))
    Write-Output ("  cmdline  : VBoxManage " + ($vbArgs -join ' '))
    & $vb @vbArgs
    if ($LASTEXITCODE -ne 0) { Write-Output ("ABORT: sharedfolder add failed for " + $w.Name); exit 1 }
    $added++
}

# READ IT BACK rather than trusting the exit codes
Write-Output ''
Write-Output '=== read back from the VM config ==='
$after = & $vb showvminfo $Vm --machinereadable 2>&1
$rows  = @($after | Where-Object { $_ -match '^SharedFolder' })
if ($rows.Count -eq 0) { Write-Output 'FAIL: the VM reports no shared folders at all.'; exit 1 }
$rows | ForEach-Object { '  ' + $_ }

$names = @($after | Where-Object { $_ -match '^SharedFolderNameMachineMapping' } |
           ForEach-Object { ($_ -split '=')[1].Trim('"') })
Write-Output ''
Write-Output ("mapped     : " + ($names -join ', '))
$missing = @($want | Where-Object { $names -notcontains $_.Name } | ForEach-Object { $_.Name })
if ($missing.Count) { Write-Output ("FAIL: still missing " + ($missing -join ', ')); exit 1 }

Write-Output ("added this run: " + $added)
Write-Output ''
Write-Output '=== the installer the guest will see ==='
Get-ChildItem 'C:\Users\dmont\sdout' -Filter '*.exe' |
    ForEach-Object { "  {0}  {1:n0} bytes  {2}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString('dd MMM HH:mm:ss') }
Write-Output ''
Write-Output 'REACH THEM BY NAME IN THE GUEST, NOT BY DRIVE LETTER:'
Write-Output '    \\vboxsvr\sdout     \\vboxsvr\xfer     \\vboxsvr\gplbld'
Write-Output 'Adding a third share MOVED the letters last time (PROJECT_STATUS 2562);'
Write-Output 'two shares came up Y: and Z:, one share came up Z: alone.'
exit 0
