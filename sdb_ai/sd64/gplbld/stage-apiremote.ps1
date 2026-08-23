# stage-apiremote.ps1 - put the API client kit in front of a VM, so the API can
# be reached ACROSS A REAL NETWORK.  PROJECT_STATUS.md section 7 step 2, item 4.
#
#   powershell -File stage-apiremote.ps1                      stage, print the command
#   powershell -File stage-apiremote.ps1 -Prefix sdapib8      also find the password
#   powershell -File stage-apiremote.ps1 -Remove              undo
#
# Exit 0 staged, 1 something is wrong, 2 it could not be staged.
#
# WHY THIS EXISTS.  Until 22 Aug 2026 every API measurement went to
# 127.0.0.1:4243, and loopback cannot answer the question - connecting to this
# host's OWN LAN address from this host is short-circuited by the local stack
# and never reaches the wire either.  The client has to run on another machine.
#
# IT DOES THE HOST HALF ONLY, AND THAT IS NOT LAZINESS.  section 7 step 2: do NOT drive
# the guest with VBoxManage guestcontrol, which needs guest credentials.  The
# guest command is printed instead and somebody types it.  Everything that CAN
# be checked from here is checked here, so that a failure on the guest has
# already had the host ruled out.
#
# WHAT THE GUEST NEEDS: TWO FILES AND NO TOOLCHAIN.  remote-connect-test.exe and
# sdclilib.dll are native UCRT64 and import only KERNEL32, WS2_32, bcrypt and
# the UCRT api-ms-win-crt-* set, all of which ship with Windows.  That is
# checked below rather than assumed - a kit that pulled in msys-2.0.dll would
# fail on a clean guest as a silent "unable to start correctly", which reads
# like anything except a missing runtime.
#
# THE HOST ADDRESS IS DERIVED FROM THE VM'S OWN BRIDGE ADAPTER, not guessed.
# This machine has an address on more than one 10.x adapter and only the one the
# guest is bridged to is reachable from it.  Getting that wrong looks exactly
# like a firewall problem.
#
# THE FIXTURE IS NOT MADE HERE.  Run, ELEVATED, first:
#     gplbld\verify-apiport.ps1 -Prefix sdapib8 -Keep
# which creates the account, sets a password, joins it to sdapi, runs the
# loopback test as a CONTROL, and leaves it all up.  That control is what makes
# a guest result attributable to the address and nothing else.

[CmdletBinding()]
param(
    [string] $Vm     = 'Windows 11 Clone',
    [string] $Kit    = (Join-Path $env:USERPROFILE 'sd-apikit'),
    [string] $Share  = 'apikit',
    # The prefix given to verify-apiport.ps1 -Keep.  Only used to find the
    # generated password in its transcript, which is the one thing that cannot
    # be worked out from anywhere else.
    [string] $Prefix = '',
    [int]    $Port   = 4243,
    [switch] $Remove
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sd64   = Split-Path -Parent $Gplbld
$cliDir = Join-Path $Sd64 'gplsrc\sdclilib'
$vbox   = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'

function Say($m)  { Write-Host $m }
function Bad($m)  { Write-Host ('  [PROBLEM] ' + $m) -ForegroundColor Red }
function Good($m) { Write-Host ('  [ok]      ' + $m) -ForegroundColor Green }

if (-not (Test-Path -LiteralPath $vbox)) {
    Say "stage-apiremote: VBoxManage not found at $vbox"
    exit 2
}

# --------------------------------------------------------------- -Remove -----
if ($Remove) {
    & $vbox sharedfolder remove $Vm --name $Share 2>&1 | Out-Null
    & $vbox sharedfolder remove $Vm --name $Share --transient 2>&1 | Out-Null
    Say "removed shared folder '$Share' from '$Vm' (if it was there)"
    if (Test-Path -LiteralPath $Kit) {
        Remove-Item -Recurse -Force -LiteralPath $Kit
        Say "removed $Kit"
    }
    Say ''
    Say 'The API fixture is NOT removed by this - it is not made by this either.'
    Say '  DELETE.ACCOUNT in SD, and restore sd.conf as verify-apiport printed.'
    exit 0
}

# ------------------------------------------------------- the kit is current --
Say ''
Say '== the client kit'

$exe = Join-Path $cliDir 'localtest\remote-connect-test.exe'
$dll = Join-Path $cliDir 'sdclilib.dll'
$srcExe = Join-Path $cliDir 'tests\remote_connect_test.c'
$srcDll = Join-Path $cliDir 'sdclilib.c'

foreach ($f in @($exe, $dll)) {
    if (-not (Test-Path -LiteralPath $f)) {
        Bad ((Split-Path -Leaf $f) + ' has not been built')
        Say '  Build it from an MSYS2 UCRT64 shell:'
        Say '    cd gplsrc/sdclilib && make'
        Say '  or run gplbld\verify-apiport.ps1, whose check-remote target builds the exe.'
        exit 2
    }
}

# A STALE KIT WOULD TEST OLD CODE AND SAY NOTHING.  These are build products in
# a tree assert-current does not compare, so nothing else would catch it.
$stale = @()
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $srcExe).LastWriteTime) { $stale += 'remote-connect-test.exe is older than remote_connect_test.c' }
if ((Get-Item $dll).LastWriteTime -lt (Get-Item $srcDll).LastWriteTime) { $stale += 'sdclilib.dll is older than sdclilib.c' }
if ($stale.Count) {
    foreach ($m in $stale) { Bad $m }
    Say '  Rebuild before staging - a stale kit measures code nobody is shipping.'
    exit 2
}
Good 'both build products are newer than their sources'

# NO MSYS2 RUNTIME.  The guest has no toolchain; an import of msys-2.0.dll or of
# the libgcc/libwinpthread pair turns into "unable to start correctly (0xc...)"
# over there, which names nothing.
$objdump = 'C:\msys64\usr\bin\objdump.exe'
if (Test-Path -LiteralPath $objdump) {
    $bad = @()
    foreach ($f in @($exe, $dll)) {
        $imports = & $objdump -p $f 2>$null | Select-String 'DLL Name:' |
                   ForEach-Object { ($_.ToString() -replace '.*DLL Name:\s*','').Trim() }
        foreach ($i in $imports) {
            if ($i -match '^(msys-|libgcc|libwinpthread|libstdc)') { $bad += ((Split-Path -Leaf $f) + ' imports ' + $i) }
        }
    }
    if ($bad.Count) {
        foreach ($m in $bad) { Bad $m }
        Say '  That kit cannot run on a clean guest.  Build it with the UCRT64 toolchain.'
        exit 2
    }
    Good 'no MSYS2 or libgcc imports - it will run on a clean Windows guest'
} else {
    Say '  [skip]    objdump not present, import check not made'
}

if (-not (Test-Path -LiteralPath $Kit)) { $null = New-Item -ItemType Directory -Path $Kit }
Copy-Item -LiteralPath $exe -Destination $Kit -Force
Copy-Item -LiteralPath $dll -Destination $Kit -Force
Good ("staged into $Kit")

# --------------------------------------------------------------- the VM ------
Say ''
Say '== the VM'

$info = & $vbox showvminfo $Vm --machinereadable 2>$null
if (-not $info) { Bad "no VM called '$Vm'"; exit 2 }

$nic = ($info | Select-String '^nic1=') -replace '.*=','' -replace '"',''
if ($nic -ne 'bridged') {
    Bad "'$Vm' has nic1=$nic, not bridged"
    Say '  NAT cannot answer this question: the guest would be behind this host'
    Say '  rather than beside it on the network.  section 7 step 2.'
    exit 2
}
$adapter = ($info | Select-String '^bridgeadapter1=') -replace '.*=','' -replace '"',''
Good ("bridged over: " + $adapter)

# THE HOST ADDRESS ON THAT ADAPTER, not any other.  See the header.
$hostIp = $null
$na = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -eq $adapter }
if ($na) {
    $hostIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $na.ifIndex -ErrorAction SilentlyContinue |
               Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
               Select-Object -First 1).IPAddress
}
if (-not $hostIp) {
    Bad 'could not find this host''s address on that adapter'
    Say '  Is the adapter up and on a network?  Without it the guest has nothing to reach.'
    exit 2
}
Good ("this host on that segment: " + $hostIp)

# A RUNNING VM IS LOCKED, AND A PERMANENT sharedfolder add ON ONE FAILS with
# "already locked for a session (or being unlocked)".  section 7 step 2 says to use
# --transient and that is why; the cost is that a transient share is gone when
# the guest powers off.  So: match what is already there first, add transient to
# a running VM, permanent to a stopped one.  Measured 22 Aug 2026 - the first
# version of this script read VMState AFTER using it and failed here.
$state = ($info | Select-String '^VMState=') -replace '.*=','' -replace '"',''

$already = $false
$names = $info | Select-String '^SharedFolderName(MachineMapping|TransientMapping)\d+='
foreach ($n in $names) {
    $idx = ($n.ToString() -replace '^SharedFolderName(MachineMapping|TransientMapping)(\d+)=.*','$1$2')
    $nm  = ($n.ToString() -replace '.*=','' -replace '"','')
    if ($nm -ne $Share) { continue }
    $pathLine = $info | Select-String ('^SharedFolderPath' + [regex]::Escape($idx) + '=')
    if ($pathLine) {
        # .Replace(), NOT -replace.  showvminfo doubles the backslashes, and
        # undoing that with a regex needs four of them in the pattern - which is
        # exactly the count that gets halved by whatever writes the file.  It
        # was written with two here, so the regex replaced each backslash with
        # itself, the path stayed doubled, and this comparison never matched:
        # the script then tried to add a share that was already there and
        # VBoxManage refused.  .Replace is a literal string method with no
        # escaping layer to lose.
        $hp = ($pathLine.ToString() -replace '.*?=','').Trim('"').Replace('\\','\')
        if ($hp.TrimEnd('\') -ieq $Kit.TrimEnd('\')) { $already = $true }
    }
}

if ($already) {
    Good ("shared folder '$Share' is already attached and points at the kit")
} elseif ($state -eq 'running') {
    & $vbox sharedfolder add $Vm --name $Share --hostpath $Kit --transient --automount --auto-mount-point 'E:' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Bad "could not add a transient shared folder (exit $LASTEXITCODE)"; exit 2 }
    Good ("shared folder '$Share' -> E: (TRANSIENT - it goes when the guest powers off)")
} else {
    & $vbox sharedfolder remove $Vm --name $Share 2>&1 | Out-Null
    & $vbox sharedfolder add $Vm --name $Share --hostpath $Kit --automount --auto-mount-point 'E:' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Bad "could not add the shared folder (exit $LASTEXITCODE)"; exit 2 }
    Good ("shared folder '$Share' -> E: on the guest")
}

if ($state -ne 'running') {
    Say ("  [note]    '$Vm' is $state - start it, or: VBoxManage startvm `"$Vm`" --type gui")
}

# ------------------------------------------------ the port, and the password --
Say ''
Say '== the API'

$listening = @(& "$env:SystemRoot\System32\netstat.exe" -an |
               Select-String (':' + $Port + '\s') | Select-String 'LISTENING')
if ($listening | Where-Object { $_ -match '0\.0\.0\.0:' + $Port }) {
    Good "SD is listening on 0.0.0.0:$Port - every interface"
} elseif ($listening.Count) {
    Bad "something is on port $Port but NOT on 0.0.0.0 - a remote client cannot reach it"
} else {
    Bad "nothing is listening on port $Port - run verify-apiport.ps1 -Prefix <p> -Keep first"
}

$fw = Get-NetFirewallRule -ErrorAction SilentlyContinue |
      Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' } |
      Where-Object { ($_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue).LocalPort -contains "$Port" }
if ($fw) { Good ("firewall admits it: " + (($fw | Select-Object -First 1).DisplayName)) }
else     { Bad  "no enabled inbound allow rule for port $Port - the guest will time out" }

$pw = '<password verify-apiport printed>'
if ($Prefix) {
    $log = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'SD-verify') -Filter 'verify-apiport-*.log' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) {
        $hit = Get-Content $log.FullName | Select-String '^\s*password:\s*(\S+)' | Select-Object -Last 1
        if ($hit) { $pw = $hit.Matches[0].Groups[1].Value; Good ("password read from " + $log.Name) }
    }
    if ($pw -like '<*') { Bad 'no password found - has verify-apiport run with -Keep?' }
}

# ------------------------------------------------------------- the command ---
$acct = if ($Prefix) { $Prefix.ToUpper() } else { '<ACCOUNT>' }
$user = if ($Prefix) { $Prefix } else { '<user>' }

Say ''
Say '== RUN THIS ON THE GUEST, not here'
Say ''
Say ("    E:\remote-connect-test.exe $hostIp $Port $user $pw $acct")
Say ''
Say '  Expect: admitted with a WHO line, then a wrong password refused, then'
Say '  SDSYS refused - the ACC$GROUP gate holding over the network.'
Say ''
Say '  If it cannot connect at all, the path is the suspect and not SD:'
Say ("    Test-NetConnection $hostIp -Port $Port      (on the guest)")
Say '  and on THIS host, arp -a should carry the guest''s own MAC once it has'
Say '  sent anything - that is how bridging is confirmed (section 7 step 2).'
Say ''
Say '  Undo with: stage-apiremote.ps1 -Remove'

exit 0
