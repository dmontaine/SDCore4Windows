# measure-f3-f5.ps1 - READ-ONLY measurement for RELEASE_1.1 176 (Linux security evaluation F3 and F5).
#
# Run in an ELEVATED PowerShell (it reads ACLs that an ordinary user is refused):
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\measure-f3-f5.ps1
#
# It changes nothing: no ACL, firewall rule, setting or file is written, except its own log under
# %LOCALAPPDATA%\SD-verify. It does not start or stop SD.
#
# F3 (Linux ca70d23): can a member of sdusers make, rename or delete an entry in the account roots,
#     and so replace another account's directory? Measured here from the ACL: for each directory, the
#     ACEs that name sdusers (and the broad groups Everyone, Users, Authenticated Users), with the
#     rights that matter spelled out: CREATE (WriteData/AppendData on a directory), DELETE-CHILD
#     (DeleteSubdirectoriesAndFiles) and DELETE (Delete on the directory itself).
#     NOT measured: an actual create/rename as an ordinary SD user. That needs a second account and
#     is stated in the verdict, never implied.
# F5 (Linux f3bace1): who can reach the API's first stage? Measured: sd.conf APIPORT, what is
#     listening on 4247 (the SD API) and 4243 (the TLS relay) and ON WHICH ADDRESS, the SD firewall
#     rules (port, profile, remote address, program) and the state of the SD service.

param([string]$Root = 'C:\ProgramData\SD')

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("f3f5-" + $stamp + ".log")
Start-Transcript -Path $log | Out-Null

$fail = 0
function Say([string]$t) { Write-Host $t }

Say '== INPUTS (what this run actually used)'
Say ('  script        : ' + $PSCommandPath)
Say ('  data root     : ' + $Root)
Say ('  log           : ' + $log)
Say ('  user          : ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say ('  elevated      : ' + $isAdmin)
if (-not $isAdmin) { Say 'REFUSED: not elevated. The ACLs of user_accounts and group_accounts cannot be read from an ordinary prompt, so a run here would measure nothing.'; Stop-Transcript | Out-Null; exit 2 }
if (-not (Test-Path -LiteralPath $Root)) { Say ('REFUSED: ' + $Root + ' does not exist; nothing to measure.'); Stop-Transcript | Out-Null; exit 2 }

# ---------------------------------------------------------------- F3
Say ''
Say '== F3  ACLs on the account roots (read-only)'

$watch = @('sdusers', 'Everyone', 'Users', 'Authenticated Users')
function Show-Dir([string]$path, [string]$why) {
  Say ''
  Say ('-- ' + $path + '   (' + $why + ')')
  if (-not (Test-Path -LiteralPath $path)) { Say '   ABSENT'; return $null }
  $acl = Get-Acl -LiteralPath $path
  Say ('   owner: ' + $acl.Owner + '   inheritance blocked: ' + $acl.AreAccessRulesProtected)
  $hits = 0
  $res = @{ create = $false; delchild = $false; del = $false; denyseen = $false; named = 0 }
  foreach ($r in $acl.Access) {
    $who = [string]$r.IdentityReference
    $short = ($who -split '\\')[-1]
    $isWatched = $false
    foreach ($w in $watch) { if ($short -ieq $w) { $isWatched = $true } }
    if (-not $isWatched) { continue }
    $hits++
    $res.named++
    $rights = [int]$r.FileSystemRights
    $c = (($rights -band 2) -ne 0) -or (($rights -band 4) -ne 0)
    $dc = ($rights -band 64) -ne 0
    $d = ($rights -band 65536) -ne 0
    Say ('   ' + $r.AccessControlType + '  ' + $who + '  ' + $r.FileSystemRights + '  inherited=' + $r.IsInherited + '  flags=' + $r.InheritanceFlags + '/' + $r.PropagationFlags)
    Say ('      CREATE=' + $c + '  DELETE-CHILD=' + $dc + '  DELETE-SELF=' + $d)
    if ($r.AccessControlType -eq 'Allow') {
      if ($c) { $res.create = $true }
      if ($dc) { $res.delchild = $true }
      if ($d) { $res.del = $true }
    } else { $res.denyseen = $true }
  }
  if ($hits -eq 0) { Say '   (no ACE names sdusers, Everyone, Users or Authenticated Users)' }
  return $res
}

# the principal must exist, or "no ACE names sdusers" would be a pass that measured nothing
$sdu = $null
try { $sdu = (New-Object Security.Principal.NTAccount('sdusers')).Translate([Security.Principal.SecurityIdentifier]) } catch {}
if ($sdu -eq $null) { Say 'REFUSED: the group sdusers does not resolve on this machine; the ACEs cannot be read as SD users.'; Stop-Transcript | Out-Null; exit 2 }
Say ('  sdusers SID   : ' + $sdu.Value)

$ua = Join-Path $Root 'user_accounts'
$ga = Join-Path $Root 'group_accounts'
$sys = Join-Path $Root 'sdsys'
$sample = $null
if (Test-Path -LiteralPath $ua) { $sample = Get-ChildItem -LiteralPath $ua -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 1 }

$rRoot = Show-Dir $Root 'parent of everything'
$rUa   = Show-Dir $ua 'F3: the user account roots'
$rGa   = Show-Dir $ga 'F3: the group account roots'
$rSys  = Show-Dir $sys 'F1/F3(c): the system account'
if ($sample -ne $null) { $rSmp = Show-Dir $sample.FullName 'F3: one account directory, to see what it inherits' } else { Say ''; Say '-- no account directory under user_accounts to sample' }

Say ''
Say '== F3 VERDICT (from the ACL only)'
function Verdict([string]$name, $r) {
  if ($r -eq $null) { Say ('  ' + $name + ': NOT MEASURED (absent)'); return }
  if ($r.create -or $r.delchild -or $r.del) {
    Say ('  ' + $name + ': OPEN to the watched groups  create=' + $r.create + ' delete-child=' + $r.delchild + ' delete-self=' + $r.del + '  (deny ACE seen: ' + $r.denyseen + ')')
    $script:fail++
  } elseif ($r.named -eq 0) {
    Say ('  ' + $name + ': no ACE for the watched groups; closed to them unless another group they belong to is granted (not resolved here)')
  } else {
    Say ('  ' + $name + ': the watched groups have read-type rights only')
  }
}
Verdict 'user_accounts ' $rUa
Verdict 'group_accounts' $rGa
Say '  (sdsys and the data root are context: they are expected to be OPEN to sdusers, row 176 (c))'
Verdict 'sdsys         ' $rSys
Verdict 'data root     ' $rRoot
Say '  NOT DONE: an actual create / rename / delete as an ordinary SD user. A second account is needed for that.'

# ---------------------------------------------------------------- F5
Say ''
Say '== F5  who can reach the API (read-only)'
$conf = Join-Path $Root 'sdsys\sd.conf'
if (-not (Test-Path -LiteralPath $conf)) { $conf = Join-Path $Root 'sd.conf' }
Say ('  sd.conf       : ' + $conf + '  exists=' + (Test-Path -LiteralPath $conf))
if (Test-Path -LiteralPath $conf) {
  $lines = Get-Content -LiteralPath $conf | Where-Object { $_ -match '^\s*#?\s*(APIPORT|NETDIRS|NETFILES)\b' }
  foreach ($l in $lines) { Say ('    ' + $l) }
  if (-not ($lines | Where-Object { $_ -match '^\s*APIPORT\s*=' })) { Say '    APIPORT is not set (commented out): the SD API listener should be OFF' }
}

Say ''
Say '  services:'
$svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(sd|SD)' -or $_.DisplayName -match '^SD' }
if ($svc) { foreach ($s in $svc) { Say ('    ' + $s.Name + '  ' + $s.Status + '  (' + $s.DisplayName + ')') } } else { Say '    none named SD*' }

Say ''
Say '  listeners on 4247 (SD API) and 4243 (TLS relay):'
$listen = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 4247 -or $_.LocalPort -eq 4243 })
if ($listen.Count -eq 0) { Say '    NOTHING is listening on either port (so the address question cannot be answered from this run)' }
foreach ($l in $listen) {
  $pn = ''
  try { $pn = (Get-Process -Id $l.OwningProcess -ErrorAction Stop).ProcessName } catch {}
  $scope = 'ALL INTERFACES'
  if ($l.LocalAddress -eq '127.0.0.1' -or $l.LocalAddress -eq '::1') { $scope = 'loopback only' }
  Say ('    ' + $l.LocalAddress + ':' + $l.LocalPort + '  pid ' + $l.OwningProcess + ' ' + $pn + '  -> ' + $scope)
}

Say ''
Say '  firewall rules named SD*, sdwind* or sd-solo*:'
$rules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^(SD|sdwind|sd-solo)' })
if ($rules.Count -eq 0) { Say '    none' }
foreach ($ru in $rules) {
  $pf = $ru | Get-NetFirewallPortFilter
  $af = $ru | Get-NetFirewallAddressFilter
  $ap = $ru | Get-NetFirewallApplicationFilter
  Say ('    ' + $ru.DisplayName + '  enabled=' + $ru.Enabled + '  ' + $ru.Direction + '  ' + $ru.Action + '  profile=' + $ru.Profile + '  proto=' + $pf.Protocol + '  local=' + $pf.LocalPort + '  remote=' + $af.RemoteAddress + '  program=' + $ap.Program)
}

Say ''
Say '== F5 READING (for the owner, not a pass/fail)'
Say '  An enabled inbound Allow rule on 4243 / 4247 with remote=Any and profile=Any means a remote machine can try the API IF something listens there.'
Say '  A listener on loopback only is reachable from this machine alone whatever the firewall says.'

Say ''
Say ('== DONE  F3 open-to-watched-groups count: ' + $fail + '   log: ' + $log)
Stop-Transcript | Out-Null
exit 0
