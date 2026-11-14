# test-pin-units.ps1 - free-tier guard for sd_pin.c, the client's first-use certificate
# pinning (RELEASE_1.1 297; Solo's SOLO 24, Linux S.236).  Compiles the store logic with MSYS2's UCRT64 gcc together with
# test-pin-driver.c (no OpenSSL, no network, no installed tree) and drives it against a
# SCRATCH store through SD_KNOWN_SERVERS.  Prints each driver line; every row anchors on
# the driver's own "PIN: OK" / "PIN: REFUSED" wording, never on an echoed argument.
#
# The rules are the Linux client's, so the words and the store format must match:
# see sd_pin.h.  Exit 0 = all rows pass, 1 = a row failed, 2 = no compiler (NO TREE).

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here '..\gplsrc\sdclilib\sd_pin.c'
$drv = Join-Path $here 'test-pin-driver.c'
$gcc = 'C:\msys64\ucrt64\bin\gcc.exe'
if (-not ((Test-Path $gcc) -and (Test-Path $src) -and (Test-Path $drv))) { Write-Host "NO TREE: need $gcc, $src and $drv"; exit 2 }

$root = Join-Path $env:TEMP ('sdpin-units-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root | Out-Null
$exe = Join-Path $root 'pin.exe'
$env:PATH = (Split-Path $gcc) + ';' + $env:PATH
Write-Host "scratch root: $root"
Write-Host "compiling: $gcc -std=c11 -Wall -Wextra -o $exe test-pin-driver.c sd_pin.c"
& $gcc -std=c11 -Wall -Wextra -Wno-unknown-pragmas -o $exe $drv $src 2>&1 | ForEach-Object { Write-Host "  cc: $_" }
if (-not (Test-Path $exe)) { Write-Host 'FAIL: the driver did not compile'; exit 1 }

$h1 = ('a1' * 32); $h2 = ('b2' * 32)
$store = Join-Path $root 'known_servers'
$env:SD_KNOWN_SERVERS = $store
$env:USERPROFILE = Join-Path $root 'profile'

function Drive([string]$what, [string]$h, [int]$p, [string]$hex) {
    $out = (& $exe $h $p $hex 2>&1 | Out-String).Trim()
    Write-Host ("--- $what : $h`:$p $hex"); Write-Host "    $out"
    return $out
}
$fail = 0
function Check([string]$label, [bool]$ok) { if ($ok) { Write-Host "PASS  $label" } else { Write-Host "FAIL  $label"; $script:fail++ } }
function StoreHash { if (Test-Path -LiteralPath $store -PathType Leaf) { (Get-FileHash $store -Algorithm SHA256).Hash } else { '(absent)' } }

$o = Drive 'first connection' 'Server.Example' 4249 $h1
Check 'first connection records and connects' ($o -eq 'PIN: OK' -and (Get-Content $store -Raw).Trim() -eq ('server.example:4249 ' + $h1))
$o = Drive 'same certificate' 'server.example' 4249 $h1
Check 'the same certificate connects, store unchanged' ($o -eq 'PIN: OK' -and @(Get-Content $store).Count -eq 1)
$before = StoreHash
$o = Drive 'different certificate' 'server.example' 4249 $h2
Check 'a different certificate is REFUSED with the shared wording' ($o -match "^PIN: REFUSED THE SERVER'S CERTIFICATE HAS CHANGED since this client first connected to server.example:4249 \(pinned $h1, now $h2\)\. The connection was refused before any password was sent\. If the server was reinstalled, remove the line for server.example:4249 from ")
Check 'and the store is left untouched (no auto-update)' ((StoreHash) -eq $before)
# 01 Oct 26 - THE REAL PAIR: a Solo (4249) and a full product (4247) on one
# computer.  The owner ruled the pin keyed by host AND port so that they keep two
# separate pins; the second connection is a different certificate on the same
# host and is accepted only because its port differs.
$o = Drive 'the full product on the same computer' 'server.example' 4247 $h2
Check 'a different port is a different server (full product 4247 beside Solo 4249)' ($o -eq 'PIN: OK' -and @(Get-Content $store).Count -eq 2 -and (Get-Content $store | Where-Object { $_ -eq ('server.example:4247 ' + $h2) }).Count -eq 1)
$o = Drive 'an IP address' '192.0.2.10' 4249 $h2
Check 'an IP is a host like any other' ($o -eq 'PIN: OK' -and (Get-Content $store | Where-Object { $_ -eq ('192.0.2.10:4249 ' + $h2) }).Count -eq 1)

# A store with a comment, a blank line and no final newline: the new record starts its own line.
[IO.File]::WriteAllText($store, "# my servers`r`n`r`nold.example:4249 $h1")
$o = Drive 'no final newline' 'new.example' 4249 $h2
$lines = @(Get-Content $store)
Check 'a store without a final newline gets the record on its own line' ($o -eq 'PIN: OK' -and $lines[-1] -eq ('new.example:4249 ' + $h2) -and $lines[-2] -eq ('old.example:4249 ' + $h1))
$o = Drive 'old record still honoured' 'old.example' 4249 $h1
Check 'a record in a hand-made store is honoured (CRLF tolerated)' ($o -eq 'PIN: OK')

# Unusable stores REFUSE rather than connect unpinned.
$dirStore = Join-Path $root 'adir'
New-Item -ItemType Directory -Path $dirStore | Out-Null
$env:SD_KNOWN_SERVERS = $dirStore
$o = Drive 'store is a directory' 'x.example' 4249 $h1
Check 'a store that cannot be opened refuses, never an unpinned connection' ($o -match '^PIN: REFUSED cannot pin the server: cannot open ')
$env:SD_KNOWN_SERVERS = Join-Path $root 'no-such-dir\known_servers'
$o = Drive 'store folder missing' 'x.example' 4249 $h1
Check 'a store whose folder does not exist (a path the caller named) refuses' ($o -match '^PIN: REFUSED cannot pin the server: cannot open ')

# The default store is created under the profile.
Remove-Item Env:\SD_KNOWN_SERVERS
New-Item -ItemType Directory -Path $env:USERPROFILE | Out-Null
$o = Drive 'default store' 'def.example' 4249 $h1
$def = Join-Path $env:USERPROFILE '.sdcore\known_servers'
Check 'with SD_KNOWN_SERVERS unset the store is %USERPROFILE%\.sdcore\known_servers, created' ($o -eq 'PIN: OK' -and (Test-Path $def) -and (Get-Content $def -Raw).Trim() -eq ('def.example:4249 ' + $h1))

$o = Drive 'bad digest' 'y.example' 4249 'XYZ'
Check 'a digest that is not 64 lower-case hex digits is refused' ($o -match '^PIN: REFUSED cannot pin the server: no usable host name or certificate')
$o = Drive 'upper-case digest' 'y.example' 4249 ($h1.ToUpper())
Check 'an upper-case digest is refused (the value is lower-case hex)' ($o -match '^PIN: REFUSED ')

Remove-Item $root -Recurse -Force
Write-Host ''
if ($fail -eq 0) { Write-Host 'pin units: ALL PASS'; exit 0 }
Write-Host "pin units: $fail FAILED"; exit 1
