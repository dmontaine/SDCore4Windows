<#
stage-clients.ps1 - put the clean-room client libraries beside an installer, in the release package's layout.

  powershell -ExecutionPolicy Bypass -File <sd64>\gplbld\stage-clients.ps1 -To <folder>\clients [-From <set>]

19 Nov 26 - RELEASE_1.1 351 (Linux S.262, c89f3864).  The owner, 17 and 19 Nov 2026: the GPL client library is no longer
built from this source; the clean-room library (written without it, so a commercial program may link to it) is what every
SD Core ships.  Its binaries live OUTSIDE every repository, in P:\git-private\sdclientlib-binaries\<commit>-<date>\, with a
COMMIT.txt naming each file's SHA-256.  This script is the one place that turns such a set into what sd.iss installs and
mkrelease.ps1 packages:

  <To>\Windows64\  sdclilib.dll  sdclient.dll  libsdclilib.dll.a  libsdclient.dll.a   (64-bit; sd.iss puts the DLLs in
                                                                                      usr\bin and all four in usr\clients\client64)
  <To>\Windows32\  qmclilib.dll  qmclient.dll  libqmclilib.dll.a  libqmclient.dll.a   (32-bit; usr\bin and usr\clients\client32)

each with its own COMMIT.txt (a line naming the set's SDClientLib commit, then "<sha256>  ./<name>" per file), which is the form mkrelease.ps1 -Clients
checks.  Every file is checked against the set's COMMIT.txt BEFORE it is copied and its copy AFTER; a file missing from the set,
missing from COMMIT.txt, or not matching it stops the run.  -From defaults to the newest set (by name) that has win64\ and win32\.

Exit 0: both folders written and every copy matches.  1: a check failed (nothing is claimed).  2: cannot run (no set, bad -To).
#>
param(
    [Parameter(Mandatory = $true)] [string] $To,
    [string] $From = ''
)
$ErrorActionPreference = 'Stop'

function Say([string] $t) { Write-Host $t }
function Fail([string] $t) { Say "stage-clients: FAILED - $t"; exit 1 }
function Cannot([string] $t) { Say "stage-clients: CANNOT RUN - $t"; exit 2 }

$Sets = 'P:\git-private\sdclientlib-binaries'
$Layout = [ordered]@{
    'Windows64' = @{ Src = 'win64'; Files = @('sdclilib.dll', 'sdclient.dll', 'libsdclilib.dll.a', 'libsdclient.dll.a') }
    'Windows32' = @{ Src = 'win32'; Files = @('qmclilib.dll', 'qmclient.dll', 'libqmclilib.dll.a', 'libqmclient.dll.a') }
}

if (-not $From) {
    if (-not (Test-Path -LiteralPath $Sets -PathType Container)) { Cannot "no -From and no $Sets" }
    $cand = @(Get-ChildItem -LiteralPath $Sets -Directory | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'win64')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'win32')) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'COMMIT.txt'))
    } | Sort-Object Name)
    if ($cand.Count -eq 0) { Cannot "no set under $Sets has win64\, win32\ and COMMIT.txt" }
    $From = $cand[-1].FullName
}
$manifest = Join-Path $From 'COMMIT.txt'
Say 'stage-clients'
Say "  from : $From"
Say "  to   : $To"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Cannot "no COMMIT.txt in $From" }

# The set's own record: "<64 hex>  ./<relative path>" lines, and its first line says what the set is.
$lines = @(Get-Content -LiteralPath $manifest)
$first = $lines[0]
$want = @{}
foreach ($l in $lines) {
    $m = [regex]::Match($l, '^([0-9a-f]{64})\s+\./(\S+)$')
    if ($m.Success) { $want[$m.Groups[2].Value] = $m.Groups[1].Value }
}
Say ("  set  : {0}" -f $first)
# The set's first line names the build machine's folders; the copies ship, so they carry only the commit (no owner names in
# anything that ships).
$cm = [regex]::Match($first, '\bcommit ([0-9a-f]{7,40})\b')
if (-not $cm.Success) { Fail "the first line of COMMIT.txt names no commit: $first" }
$first = "SD Core clean-room client library (not GPL), built from SDClientLib commit $($cm.Groups[1].Value)"
Say ("  COMMIT.txt names {0} file(s)" -f $want.Count)
if ($want.Count -eq 0) { Fail "COMMIT.txt in $From names no file" }

$null = New-Item -ItemType Directory -Path $To -Force
$total = 0
foreach ($dst in $Layout.Keys) {
    $src = $Layout[$dst].Src
    $dir = Join-Path $To $dst
    $null = New-Item -ItemType Directory -Path $dir -Force
    # A folder holding anything we did not put there would ship it: refuse rather than guess.
    $known = @($Layout[$dst].Files) + 'COMMIT.txt'
    $extra = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $known -notcontains $_.Name })
    if ($extra.Count) { Fail ("$dir holds files this script does not write: " + (($extra | ForEach-Object Name) -join ', ')) }
    $out = @($first, '')
    foreach ($f in $Layout[$dst].Files) {
        $rel = "$src/$f"
        $p = Join-Path (Join-Path $From $src) $f
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Fail "the set has no $rel" }
        if (-not $want.ContainsKey($rel)) { Fail "COMMIT.txt does not name ./$rel" }
        $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $want[$rel]) { Fail "$rel is $h, COMMIT.txt says $($want[$rel])" }
        $q = Join-Path $dir $f
        Copy-Item -LiteralPath $p -Destination $q -Force
        $h2 = (Get-FileHash -LiteralPath $q -Algorithm SHA256).Hash.ToLower()
        if ($h2 -ne $h) { Fail "the copy $q is $h2, the set's file $h" }
        Say ("  {0,-10} {1,-18} {2}  {3:N0} bytes" -f $dst, $f, $h, (Get-Item -LiteralPath $q).Length)
        $out += "$h  ./$f"
        $total++
    }
    Set-Content -LiteralPath (Join-Path $dir 'COMMIT.txt') -Value $out -Encoding ascii
}
if ($total -ne 8) { Fail "copied $total file(s), expected 8" }
Say "stage-clients: STAGED 8 files, each matching $manifest"
exit 0
