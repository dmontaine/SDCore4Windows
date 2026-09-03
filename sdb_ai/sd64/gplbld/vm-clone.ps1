# vm-clone.ps1 - clone a guest so its MAC and hardware UUID match the source,
# and PROVE it afterwards rather than assume it.
#
#   powershell -ExecutionPolicy Bypass -File vm-clone.ps1 `
#       -Source 'Windows 11 - Template with ssh' -Name 'Clone A' -Replace
#
# ===========================================================================
# WHY BOTH OPTIONS, AND WHAT THE SECOND ONE COSTS
# ===========================================================================
#
# ***keephwuuids IS REQUIRED OR THE CLONE IS UNLICENSED.***  Windows ties its
# digital licence to the hardware UUID, so a fresh one is new hardware and the
# guest deactivates.  Owner's correction, and not negotiable against tidiness.
#
# ***keepallmacs IS ALSO REQUIRED, AND FOR THE SAME REASON AS keephwuuids: THE
# LICENCE.***  Owner, 3 Sep 2026: "the problem is that ms licensing notices the
# macs are different and wants reauthorization."  The MAC is one of the
# components Windows hashes into its hardware id, so keeping the UUID and
# changing the MAC still reads as new hardware and still deactivates.  A clone
# demanding reactivation is what this option prevents.
#
# ***THAT REVERSES THE EARLIER DECISION, AND THE EARLIER REASONING WAS NOT
# WRONG - IT WAS WEIGHED AGAINST THE WRONG COST.***  The old rule let
# VirtualBox generate a MAC because §427 valued the Test guests running
# concurrently, and sdStandalone-C1 carried "never run both at once" for
# exactly this reason.  Concurrency was traded for tidiness then; it is being
# traded for ACTIVATION now, and activation wins because an unactivated guest
# is not a usable rig at all.
#
# ***SO THE CONCURRENCY COST IS NOT AN ARGUMENT AGAINST THIS, IT IS A THING TO
# MANAGE - AND IT IS REAL HERE RATHER THAN THEORETICAL.***  Measured 3 Sep
# 2026: every Windows guest has nic1=bridged on the Realtek adapter, so they
# sit on the real LAN and two powered-on guests with one MAC collide over ARP
# and DHCP.  This script reads the attachment and only says so when it applies.
#
#   ***RUN ONE OF THE SHARERS AT A TIME.***
#
# ***THE ESCAPE, IF RUNNING SEVERAL AT ONCE EVER MATTERS MORE:*** move the
# clones to nic1=nat.  A duplicate MAC is harmless under NAT because each VM
# gets its own stack, and activation is unaffected because it hashes the MAC
# whatever the adapter is attached to.  The price is that a NAT guest is not
# reachable from the LAN by address, so anything measuring "another computer on
# your network can connect to this one over ssh" changes meaning.  The three
# shared folders are unaffected - \\vboxsvr does not go over the NIC.
#
# ===========================================================================
# WHAT IT REFUSES
# ===========================================================================
#
# ***A CLONE THAT DID NOT COME OUT AS ASKED IS THE FAILURE THIS EXISTS TO
# CATCH.***  clonevm exits 0 having quietly given a new MAC if an option name is
# wrong or unsupported, and the guest then boots, works, and is wrong in the one
# way nobody looks at.  So every run re-reads BOTH values off the new VM and
# compares them to the source; a mismatch is a non-zero exit and a named
# difference, never a warning at the bottom of a wall of output.
#
#   - a source that does not exist, or is RUNNING (clonevm refuses a locked VM)
#   - a target name already registered, unless -Replace was given
#   - -Replace on a RUNNING target (it would have to be powered off first, and
#     that is the owner's call, not this script's)
#   - a clone whose MAC or hardware UUID does not match the source
#
# It never deletes anything without -Replace, and -Replace names what it is
# about to unregister before it does it.

#
# ===========================================================================
# -Audit: THE HALF THAT STILL MATTERS WHEN THE CLONE WAS MADE IN THE GUI
# ===========================================================================
#
# Owner, 3 Sep 2026, is making the clones in the GUI and keeping two templates,
# one raw and one with the ssh server installed.  The GUI can do both options -
# MAC Address Policy "Include all network adapter MAC addresses", and Additional
# Options "Keep Hardware UUIDs" - but they are two controls on one page and the
# defaults are wrong for this rig: the policy defaults to NAT-only, and Keep
# Hardware UUIDs defaults OFF.
#
# ***AND A CLONE MADE WITH EITHER ONE MISSED LOOKS COMPLETELY NORMAL UNTIL
# WINDOWS ASKS FOR REACTIVATION, WHICH MAY BE DAYS LATER.***  So the checking
# half is worth more than the cloning half here:
#
#   powershell -ExecutionPolicy Bypass -File vm-clone.ps1 -Audit
#
# lists every registered VM with its hardware UUID and MAC, groups them, and
# names which guests share an identity - so a clone that did not keep both is
# visible immediately rather than at the next activation check.

[CmdletBinding()]
param(
    # VM to clone from, exactly as VBoxManage list vms prints it.
    [string] $Source,

    # Name for the new VM.
    [string] $Name,

    # Report every registered VM's hardware UUID and MAC and stop.  Needs
    # neither -Source nor -Name.
    [switch] $Audit,

    # Delete an existing VM of that name first, with its disks.
    [switch] $Replace,

    # Report what would happen and change nothing.
    [switch] $WhatIfOnly,

    [string] $VBoxManage = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path -LiteralPath $VBoxManage)) {
    Write-Host ('vm-clone: VBoxManage not found at ' + $VBoxManage) -ForegroundColor Red
    exit 2
}

function Get-VmInfo {
    param([string] $Vm)
    $raw = & $VBoxManage showvminfo $Vm --machinereadable 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    $h = @{}
    foreach ($l in $raw) {
        if ($l -match '^([^=]+)="?(.*?)"?$') { $h[$Matches[1]] = $Matches[2] }
    }
    return [pscustomobject]@{
        Name   = $Vm
        State  = $h['VMState']
        HwUUID = $h['hardwareuuid']
        MAC    = $h['macaddress1']
        NIC1   = $h['nic1']
    }
}

function Get-AllVmNames {
    & $VBoxManage list vms | ForEach-Object { if ($_ -match '^"(.+)"\s') { $Matches[1] } }
}

# --- -Audit: READ EVERY GUEST'S IDENTITY AND GROUP IT -----------------------
if ($Audit) {
    Write-Host ('vm-clone: VBoxManage ' + $VBoxManage)
    Write-Host 'vm-clone: -Audit - reading every registered VM, changing nothing'
    Write-Host ''

    $all = @(Get-AllVmNames | ForEach-Object { Get-VmInfo -Vm $_ } | Where-Object { $_ })

    # REFUSE THE NULL CASE: an audit that found no VMs is not a clean rig.
    if ($all.Count -eq 0) {
        Write-Host 'vm-clone: REFUSED - no VMs could be read.  That is a broken query,' -ForegroundColor Red
        Write-Host 'not an empty rig, and reporting it as "nothing to check" would be wrong.' -ForegroundColor Yellow
        exit 2
    }

    $all | Sort-Object Name |
        Format-Table @{ n = 'VM'; e = { $_.Name } },
                     @{ n = 'state'; e = { $_.State } },
                     @{ n = 'hardware UUID'; e = { $_.HwUUID } },
                     @{ n = 'MAC'; e = { $_.MAC } },
                     @{ n = 'nic1'; e = { $_.NIC1 } } -AutoSize |
        Out-String -Width 200 | Write-Host

    Write-Host ('read ' + $all.Count + ' VM(s)')
    Write-Host ''
    Write-Host 'GUESTS GROUPED BY IDENTITY (same UUID and same MAC = one licence):'
    foreach ($g in ($all | Group-Object { $_.HwUUID + '  ' + $_.MAC } | Sort-Object Count -Descending)) {
        Write-Host ('  ' + $g.Name + '   x' + $g.Count)
        foreach ($m in ($g.Group | Sort-Object Name)) { Write-Host ('      ' + $m.Name) }
    }

    # A shared MAC only collides where the guests share a segment.
    $shared = @($all | Group-Object MAC | Where-Object { $_.Count -gt 1 })
    Write-Host ''
    foreach ($g in $shared) {
        $seg = @($g.Group | Where-Object { $_.NIC1 -in @('bridged', 'intnet', 'hostonly') })
        if ($seg.Count -gt 1) {
            Write-Host ('  MAC ' + $g.Name + ' is on ' + $seg.Count + ' guests sharing a segment - RUN ONE AT A TIME:') -ForegroundColor Yellow
            $seg | ForEach-Object { Write-Host ('      ' + $_.Name + '  [' + $_.State + '] ' + $_.NIC1) -ForegroundColor Yellow }
        }
    }
    $on = @($all | Where-Object { $_.State -ne 'poweroff' })
    Write-Host ''
    Write-Host ('  powered on right now: ' + $on.Count)
    $on | ForEach-Object { Write-Host ('      ' + $_.Name + '  mac=' + $_.MAC) }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Name)) {
    Write-Host 'vm-clone: REFUSED - -Source and -Name are both required unless -Audit is given.' -ForegroundColor Red
    exit 2
}

# --- RULE 1 OF THE INSTRUMENT SECTION: say what this run actually is --------
Write-Host ('vm-clone: VBoxManage ' + $VBoxManage)
Write-Host ('vm-clone: source     ' + $Source)
Write-Host ('vm-clone: new name   ' + $Name)
Write-Host ('vm-clone: options    keephwuuids,keepallmacs')
if ($WhatIfOnly) { Write-Host 'vm-clone: -WhatIfOnly - nothing will be created or deleted' -ForegroundColor Yellow }

$src = Get-VmInfo -Vm $Source
if ($null -eq $src) {
    Write-Host ('vm-clone: REFUSED - no such VM: ' + $Source) -ForegroundColor Red
    Write-Host 'Registered VMs:' -ForegroundColor Yellow
    Get-AllVmNames | ForEach-Object { Write-Host ('  ' + $_) }
    exit 2
}
Write-Host ''
Write-Host 'SOURCE, as read from VBoxManage:'
Write-Host ('  state       : ' + $src.State)
Write-Host ('  hardwareuuid: ' + $src.HwUUID)
Write-Host ('  macaddress1 : ' + $src.MAC)
Write-Host ('  nic1        : ' + $src.NIC1)

if ($src.State -ne 'poweroff') {
    Write-Host ('vm-clone: REFUSED - the source is ' + $src.State + '.') -ForegroundColor Red
    Write-Host 'clonevm cannot read a VM that is locked by a running session.' -ForegroundColor Yellow
    Write-Host 'Power it off (or save its state) and run this again.' -ForegroundColor Yellow
    exit 2
}

# --- THE CONCURRENCY COST, PRINTED WHERE IT APPLIES ------------------------
# Only bridged/internal/hostonly guests share a segment.  Under NAT a duplicate
# MAC is harmless, so saying so there would be noise that trains the reader to
# skip the warning when it IS real.
$existing = @(Get-AllVmNames | Where-Object { $_ -ne $Name } | ForEach-Object { Get-VmInfo -Vm $_ } |
              Where-Object { $_ -and $_.MAC -eq $src.MAC })
if ($src.NIC1 -in @('bridged', 'intnet', 'hostonly')) {
    Write-Host ''
    Write-Host ('*** keepallmacs GIVES THE CLONE MAC ' + $src.MAC + ', AND nic1 IS ' + $src.NIC1 + '.') -ForegroundColor Yellow
    Write-Host '*** GUESTS SHARING A MAC ON A SHARED SEGMENT MUST NOT RUN AT THE SAME TIME.' -ForegroundColor Yellow
    if ($existing.Count -gt 0) {
        Write-Host ('*** Already carrying that MAC (' + $existing.Count + '), and the clone joins them:') -ForegroundColor Yellow
        $existing | ForEach-Object { Write-Host ('      ' + $_.Name + '   [' + $_.State + ']') -ForegroundColor Yellow }
    }
}

# --- THE TARGET ------------------------------------------------------------
$dst = Get-VmInfo -Vm $Name
if ($null -ne $dst) {
    if (-not $Replace) {
        Write-Host ''
        Write-Host ('vm-clone: REFUSED - a VM named "' + $Name + '" is already registered.') -ForegroundColor Red
        Write-Host 'Pass -Replace to delete it (with its disks) first, or choose another name.' -ForegroundColor Yellow
        exit 2
    }
    if ($dst.State -ne 'poweroff') {
        Write-Host ''
        Write-Host ('vm-clone: REFUSED - the target "' + $Name + '" is ' + $dst.State + '.') -ForegroundColor Red
        Write-Host 'This script will not power off a running guest to replace it.' -ForegroundColor Yellow
        exit 2
    }
    Write-Host ''
    Write-Host ('vm-clone: -Replace, so this VM AND ITS DISKS will be deleted first:') -ForegroundColor Yellow
    Write-Host ('    ' + $dst.Name + '   mac=' + $dst.MAC + '   [' + $dst.State + ']') -ForegroundColor Yellow
    if (-not $WhatIfOnly) {
        & $VBoxManage unregistervm $Name --delete 2>&1 | ForEach-Object { Write-Host ('    ' + $_) }
        if ($LASTEXITCODE -ne 0) {
            Write-Host ('vm-clone: unregistervm exited ' + $LASTEXITCODE + ' - stopping.') -ForegroundColor Red
            exit 3
        }
    }
}

if ($WhatIfOnly) {
    Write-Host ''
    Write-Host 'vm-clone: -WhatIfOnly, so nothing was created.  The command would have been:'
    Write-Host ('  & "' + $VBoxManage + '" clonevm "' + $Source + '" --name "' + $Name + '" --options=keephwuuids,keepallmacs --register')
    exit 0
}

# --- THE CLONE -------------------------------------------------------------
Write-Host ''
Write-Host 'vm-clone: cloning...'
& $VBoxManage clonevm $Source --name $Name --options=keephwuuids,keepallmacs --register 2>&1 |
    ForEach-Object { Write-Host ('    ' + $_) }
if ($LASTEXITCODE -ne 0) {
    Write-Host ('vm-clone: clonevm exited ' + $LASTEXITCODE) -ForegroundColor Red
    exit 3
}

# --- THE PROOF, WHICH IS THE POINT -----------------------------------------
# clonevm can exit 0 and still have given a new MAC.  Read it back.
$new = Get-VmInfo -Vm $Name
if ($null -eq $new) {
    Write-Host ('vm-clone: FAILED - clonevm exited 0 but "' + $Name + '" is not registered.') -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'CLONE, as read back from VBoxManage:'
Write-Host ('  hardwareuuid: ' + $new.HwUUID)
Write-Host ('  macaddress1 : ' + $new.MAC)
Write-Host ('  nic1        : ' + $new.NIC1)

$bad = @()
if ($new.HwUUID -cne $src.HwUUID) { $bad += ('hardwareuuid: source ' + $src.HwUUID + ' vs clone ' + $new.HwUUID) }
if ($new.MAC    -cne $src.MAC)    { $bad += ('macaddress1 : source ' + $src.MAC    + ' vs clone ' + $new.MAC) }

Write-Host ''
Write-Host '================ VERDICT ================'
if ($bad.Count -gt 0) {
    Write-Host ('  MISMATCH on ' + $bad.Count + ' value(s) - the clone is NOT identical to the source:') -ForegroundColor Red
    $bad | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor Red }
    Write-Host '  The VM exists and is registered; delete it and investigate before using it.' -ForegroundColor Red
    exit 1
}
Write-Host ('  hardwareuuid and macaddress1 BOTH match ' + $Source) -ForegroundColor Green
Write-Host ('  ' + $Name + '  hwuuid=' + $new.HwUUID + '  mac=' + $new.MAC) -ForegroundColor Green
exit 0
