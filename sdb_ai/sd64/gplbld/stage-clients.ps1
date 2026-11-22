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

with its own COMMIT.txt (a line naming the set's SDClientLib commit, then "<sha256>  ./<name>" per file), which is the form mkrelease.ps1 -Clients
checks.  Every file is checked against the set's COMMIT.txt BEFORE it is copied and its copy AFTER; a file missing from the set,
missing from COMMIT.txt, or not matching it stops the run.  -From defaults to the newest set (by its COMMIT.txt's time) that has
win64\.

21 Nov 26 - RELEASE_1.1 383 (owner: "pull the 32 bit dlls from the release.  We will keep them in case someone wants them, but
the old programs written for qm will not work out of the box with sd because of the changes we have made").  The set's win32\
stays in the private store and is NOT staged.  A <To>\Windows32 an earlier run left is removed when it holds only the files
that run wrote (anything else stops the run), so it cannot reach a package.

22 Nov 26 - RELEASE_1.1 362 (the development bundles): a machine set up from a bundle has no P:.  The bundle carries the newest
set's Windows half (COMMIT.txt and win64\) in <Projects>\Project_Other\sdclientlib-binaries, which is used when P:'s store is not there.

Exit 0: the folder written and every copy matches.  1: a check failed (nothing is claimed).  2: cannot run (no set, bad -To).
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
$BundleSets = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))) 'Project_Other\sdclientlib-binaries'
if (-not (Test-Path -LiteralPath $Sets -PathType Container) -and (Test-Path -LiteralPath $BundleSets -PathType Container)) { $Sets = $BundleSets }
$Layout = [ordered]@{
    'Windows64' = @{ Src = 'win64'; Files = @('sdclilib.dll', 'sdclient.dll', 'libsdclilib.dll.a', 'libsdclient.dll.a') }
}
# RELEASE_1.1 383: what an earlier run staged as Windows32, so its leftover folder can be told from anything else.
$Retired32 = @('qmclilib.dll', 'qmclient.dll', 'libqmclilib.dll.a', 'libqmclient.dll.a', 'COMMIT.txt')

if (-not $From) {
    if (-not (Test-Path -LiteralPath $Sets -PathType Container)) { Cannot "no -From and no $Sets" }
    $cand = @(Get-ChildItem -LiteralPath $Sets -Directory | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'win64')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'COMMIT.txt'))
    } | Sort-Object { (Get-Item -LiteralPath (Join-Path $_.FullName 'COMMIT.txt')).LastWriteTimeUtc })
    # 19 Nov 26 - newest by its COMMIT.txt, not by name: a set's name starts with its commit hash, which does not sort by date.
    if ($cand.Count -eq 0) { Cannot "no set under $Sets has win64\ and COMMIT.txt" }
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
$old32 = Join-Path $To 'Windows32'
if (Test-Path -LiteralPath $old32) {
    $other = @(Get-ChildItem -LiteralPath $old32 -Force | Where-Object { $_.PSIsContainer -or ($Retired32 -notcontains $_.Name) })
    if ($other.Count) { Fail ("$old32 holds what no earlier run wrote: " + (($other | ForEach-Object Name) -join ', ')) }
    $gone = @(Get-ChildItem -LiteralPath $old32 -File -Force | ForEach-Object Name)
    Remove-Item -LiteralPath $old32 -Recurse -Force
    if (Test-Path -LiteralPath $old32) { Fail "could not remove $old32" }
    Say ("  removed {0} (32-bit set not shipped, RELEASE_1.1 383): {1}" -f $old32, ($gone -join ', '))
}
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
if ($total -ne 4) { Fail "copied $total file(s), expected 4" }
Say "stage-clients: STAGED 4 files (64-bit), each matching $manifest"
exit 0
