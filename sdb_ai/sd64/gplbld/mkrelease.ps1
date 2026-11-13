<#
    mkrelease.ps1 - stage the Windows release package and zip it (RELEASE_1.1 268; owner, 13 Nov 2026: the release package and zip
    are made here for every version, he only uploads them).  The template is SD Core for Linux's gplbld/mkrelease.sh (S.144).

    ONE FILE FOR BOTH WINDOWS PRODUCTS.  The same bytes are in SDCore4Windows and SDCore4WindowsSolo; the script knows which
    product it is from the installer script beside it (sd.iss: SD Core for Windows; sd-solo.iss: SD Core Solo for Windows).

        powershell -ExecutionPolicy Bypass -File <repo>\sdb_ai\sd64\gplbld\mkrelease.ps1 -Version W2.0-0
                   [-Installer FILE] [-SourceZip FILE] [-DocsRepo DIR] [-Readme FILE] [-Books DIR] [-Clients DIR]
                   [-SshServer DIR] [-Python DIR] [-ConfSample FILE] [-Label rc1] [-AllowDev] [-Force]
                   [-StagingDir DIR] [-ZipDir DIR]

    -Version     W2.0-0 (Core) or WS2.0-0 (Solo): the installer's AppVer
    -Installer   default <Projects>\Project_Installers\sdout\sd-setup-<ver>.exe (Solo: sd-solo-setup-<ver>.exe), as cycle.ps1 writes it
    -SourceZip   default sdout\<repo>-source-<ver>.zip; its .txt beside it names the commit and branch the installer was built from
    -DocsRepo    default <Projects>\SDCore4WindowsDocs (Solo: SDCore4WindowsSoloDocs)
    -Readme      README.txt of the package (the owner reads it before anything is distributed; this script does not write one)
    -Books       a folder holding the whole-book PDFs <Product>-<ver>-*.pdf, copied to documentation\
    -Clients     a folder of client folders (Linux64, Linux64-openssl4, Windows32, Windows64, bindings), copied to clients\.  Each must
                 hold a COMMIT.txt whose sha256 lines name every other file in it, and match them.  P:\sdcore-mail\transfer\clients is
                 where both agents keep the current sets.
    -SshServer   a folder with OpenSSH-Win64-*.msi, copied to ssh-server\ (the installer installs from it when the box is ticked)
    -Python      a folder with python-*-amd64.exe, copied to python\ (the installer offers to run it)
    -ConfSample  Solo only: sd-solo-setup.conf.sample, beside the installer
    -Label       names a release candidate: SDCore-W2.0-0-rc1 (lower case letters and digits, up to 12)
    -AllowDev    the source .txt names a branch other than main: a TEST package, named -test, never to be distributed
    -Force       replace an existing staging folder and zip of this name
    -StagingDir, -ZipDir   default <Projects>\Project_Staging and Project_Zips (test seam)

    MAKES  <StagingDir>\<pkg>\  and  <ZipDir>\<pkg>.zip, where <pkg> is SDCore-<ver> (Solo: SDCoreSolo-<ver>):
      the installer, the source zip and its .txt          as cycle.ps1 built them (row 208: the source ships beside the installer)
      sd-core[-solo]-for-windows-<ver>-changes.{pdf,html,md}   the Changes document, lower case: the installer's shared-docs.ps1
                                                          (Solo: solo-setup.ps1) copies exactly that pattern into the pdf directory
      pdf\                                                one PDF per chapter of each book, named <book>-<chapter>.pdf with the book
                                                          in lower case (user, administrator, gettingstarted): Linux mail
                                                          2026-11-13T0930, choice (a), so 00a-copyright-and-licence.pdf, which is in
                                                          every book, cannot collide; DOCS.INSTALL takes ^[a-z0-9][a-z0-9._-]{0,79}$
      SHA256SUMS.txt                                      one line for every other file in the package
      README.txt, documentation\, clients\, ssh-server\, python\, the Solo conf sample   only when given

    THEN IT UNPACKS THE ZIP INTO A SCRATCH FOLDER AND CHECKS IT: every file of the staging folder is in the zip with the same SHA-256
    and nothing else is; SHA256SUMS.txt holds for the unpacked tree; the installer's and the source zip's hashes are the ones staged.
    Exit 0 made and checked, 1 a check failed (the zip is removed), 2 it could not start.

    REFUSES RATHER THAN SHIPPING A DOUBT (release.ps1's rule): a per-chapter PDF older than its markdown page, a Changes file missing,
    a source .txt whose commit is not in this repository or whose branch is not main (without -AllowDev), a client file whose hash is
    not its COMMIT.txt's.

    NOT DONE HERE, and said so at the end: rendering the PDFs and the Changes document (the docs repository's tools: release.ps1,
    mkdoc.py, mkfooterpdf.py, mkbookpdf.ps1), writing the README, an install from the zip, the merge to main, the tag, the push.

    13 Nov 26 - written for RELEASE_1.1 268 (and 234: the clients folder with the other platform's libraries and the bindings).
#>

[CmdletBinding()]
param(
    [string] $Version = '',
    [string] $Installer = '',
    [string] $SourceZip = '',
    [string] $DocsRepo = '',
    [string] $Readme = '',
    [string] $Books = '',
    [string] $Clients = '',
    [string] $SshServer = '',
    [string] $Python = '',
    [string] $ConfSample = '',
    [string] $Label = '',
    [switch] $AllowDev,
    [switch] $Force,
    [string] $StagingDir = '',
    [string] $ZipDir = ''
)

$ErrorActionPreference = 'Stop'
function Say([string] $m) { Write-Host "mkrelease: $m" }
function Die([string] $m) { Write-Host "mkrelease: $m" -ForegroundColor Red; exit 2 }
$script:zipMade = ''
function Fail([string] $m) {
    Write-Host "mkrelease: CHECK FAILED: $m" -ForegroundColor Red
    if ($script:zipMade -and (Test-Path -LiteralPath $script:zipMade)) { Remove-Item -LiteralPath $script:zipMade -Force; Write-Host "mkrelease: removed $script:zipMade" }
    exit 1
}
function Hash([string] $p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
function Test-PdfMagic([string] $p) {
    $fs = [System.IO.File]::OpenRead($p)
    try { $b = New-Object byte[] 5; $n = $fs.Read($b, 0, 5) } finally { $fs.Close() }
    return ($n -eq 5 -and [System.Text.Encoding]::ASCII.GetString($b) -eq '%PDF-')
}

# --- which product, and where everything is ------------------------------------------------------------------------------
$gplbld = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $gplbld '..\..\..')).Path
$projects = Split-Path -Parent $repo
if (Test-Path -LiteralPath (Join-Path $gplbld 'sd-solo.iss')) {
    $product = 'Solo'; $iss = 'sd-solo.iss'; $verRx = '^WS[0-9]+\.[0-9]+-[0-9]+$'; $setupPre = 'sd-solo-setup-'
    $pkgPre = 'SDCoreSolo-'; $changesPre = 'sd-core-solo-for-windows-'; $docsName = 'SDCore4WindowsSoloDocs'; $repoName = 'SDCore4WindowsSolo'
    $bookPre = 'SD-Core-Solo-for-Windows-'
} elseif (Test-Path -LiteralPath (Join-Path $gplbld 'sd.iss')) {
    $product = 'Core'; $iss = 'sd.iss'; $verRx = '^W[0-9]+\.[0-9]+-[0-9]+$'; $setupPre = 'sd-setup-'
    $pkgPre = 'SDCore-'; $changesPre = 'sd-core-for-windows-'; $docsName = 'SDCore4WindowsDocs'; $repoName = 'SDCore4Windows'
    $bookPre = 'SD-Core-for-Windows-'
} else { Die "neither sd.iss nor sd-solo.iss is beside this script ($gplbld)" }

if ($Version -notmatch $verRx) { Die "-Version looks like $(if ($product -eq 'Solo') {'WS2.0-0'} else {'W2.0-0'}) for $product (given: '$Version')" }
$issVer = (Select-String -LiteralPath (Join-Path $gplbld $iss) -Pattern '#define AppVer "([^"]+)"' | Select-Object -First 1)
if (-not $issVer) { Die "no '#define AppVer' in $iss" }
$issVer = $issVer.Matches[0].Groups[1].Value
if ($issVer -ne $Version) { Die "$iss says AppVer $issVer, not ${Version}: the installer of this tree is not that version" }
if ($Label -and $Label -cnotmatch '^[a-z0-9]{1,12}$') { Die '-Label is lower case letters and digits, up to 12 (rc1)' }
$lcver = $Version.ToLower()

$sdout = Join-Path $projects 'Project_Installers\sdout'
if (-not $Installer) { $Installer = Join-Path $sdout ($setupPre + $Version + '.exe') }
if (-not $SourceZip) { $SourceZip = Join-Path $sdout ($repoName + '-source-' + $Version + '.zip') }
$sourceTxt = [System.IO.Path]::ChangeExtension($SourceZip, '.txt')
if (-not $DocsRepo) { $DocsRepo = Join-Path $projects $docsName }
if (-not $StagingDir) { $StagingDir = Join-Path $projects 'Project_Staging' }
if (-not $ZipDir) { $ZipDir = Join-Path $projects 'Project_Zips' }

Say "product     $product ($iss, AppVer $issVer)"
Say "repository  $repo"
Say "installer   $Installer"
Say "source zip  $SourceZip"
Say "docs        $DocsRepo"
Say "staging     $StagingDir"
Say "zips        $ZipDir"
foreach ($p in @($Installer, $SourceZip, $sourceTxt)) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Die "no file $p" } }
foreach ($p in @($DocsRepo, $StagingDir, $ZipDir)) { if (-not (Test-Path -LiteralPath $p -PathType Container)) { Die "no folder $p" } }
# one spelling of each folder (backslashes, no trailing one), so that a file's path relative to the stage is a plain Substring
$StagingDir = (Resolve-Path -LiteralPath $StagingDir).ProviderPath.TrimEnd('\'); $ZipDir = (Resolve-Path -LiteralPath $ZipDir).ProviderPath.TrimEnd('\')
if ($Readme -and -not (Test-Path -LiteralPath $Readme -PathType Leaf)) { Die "no README file $Readme" }
if ($ConfSample -and $product -ne 'Solo') { Die '-ConfSample is for Solo only' }
if ($ConfSample -and -not (Test-Path -LiteralPath $ConfSample -PathType Leaf)) { Die "no file $ConfSample" }

# --- the source .txt: which commit the installer was built from ------------------------------------------------------------
$txt = Get-Content -LiteralPath $sourceTxt
$commit = ($txt | Where-Object { $_ -match '^commit:\s+([0-9a-f]{40})\s*$' } | Select-Object -First 1)
$branch = ($txt | Where-Object { $_ -match '^branch:\s+(\S+)\s*$' } | Select-Object -First 1)
if (-not $commit -or -not $branch) { Die "$sourceTxt has no 'commit:' and 'branch:' line" }
$commit = ($commit -replace '^commit:\s+', '').Trim(); $branch = ($branch -replace '^branch:\s+', '').Trim()
# Windows PowerShell 5.1 turns a native command's stderr into an error record, which 'Stop' would throw: git runs under 'Continue'.
$ErrorActionPreference = 'Continue'
$null = & git -C $repo cat-file -e "$commit^{commit}" 2>$null
$gitRc = $LASTEXITCODE
$tags = @(& git -C $repo tag --points-at $commit 2>$null)
$ErrorActionPreference = 'Stop'
if ($gitRc -ne 0) { Die "the source .txt names commit $commit, which is not in $repo" }
Say "built from  $commit ($branch)"
if ($branch -ne 'main' -and $tags.Count -eq 0) {
    if (-not $AllowDev) { Die "the installer was built from $branch, not main or a tagged commit (merge Dev into main on the owner's word and cycle; -AllowDev makes a TEST package that must not be distributed)" }
    if (-not $Label) { $Label = 'test' }
    Say "TEST PACKAGE: built from $branch; it must not be distributed"
}
if ((Get-Item -LiteralPath $Installer).LastWriteTime -lt (Get-Item -LiteralPath $SourceZip).LastWriteTime.AddMinutes(-30)) {
    Die "the installer is more than 30 minutes older than the source zip: they were not made by the same cycle"
}

$pkg = $pkgPre + $Version + $(if ($Label) { '-' + $Label } else { '' })
$stage = Join-Path $StagingDir $pkg
$zipf = Join-Path $ZipDir ($pkg + '.zip')

# --- everything checked before anything is written ---------------------------------------------------------------------------
# The Changes document
$changes = @()
foreach ($e in @(@('pdf', 'pdf'), @('html', 'html'), @('markdown', 'md'))) {
    $d = Join-Path $DocsRepo ('Changes\' + $e[0])
    $f = @(Get-ChildItem -LiteralPath $d -Filter ('*-changes-' + $Version + '.' + $e[1]) -File -ErrorAction SilentlyContinue)
    if ($f.Count -ne 1) {
        Die ("Changes\{0}\*-changes-{1}.{2}: {3} found, one wanted. In {4}:  python tools\mkdoc.py --in Changes\markdown --out Changes\html --version {1}{5}   then   python tools\mkfooterpdf.py Changes\html\<page>.html Changes\pdf\<page>.pdf" -f $e[0], $Version, $e[1], $f.Count, $DocsRepo, $(if ($product -eq 'Solo') { ' --product "SD Core Solo for Windows"' } else { '' }))
    }
    $changes += , @($f[0].FullName, ($changesPre + $lcver + '-changes.' + $e[1]))
}
$md = $changes[2][0]
foreach ($c in $changes[0..1]) {
    if ((Get-Item -LiteralPath $c[0]).LastWriteTime -lt (Get-Item -LiteralPath $md).LastWriteTime) { Die "$($c[0]) is older than ${md}: render it again" }
}
if (-not (Test-PdfMagic $changes[0][0])) { Die "$($changes[0][0]) is not a PDF" }

# The per-chapter PDFs
$pdfs = @(); $stale = @(); $notes = @()
foreach ($book in @('User', 'Administrator', 'GettingStarted')) {
    $mdDir = Join-Path $DocsRepo ($book + '\markdown'); $pdfDir = Join-Path $DocsRepo ($book + '\pdf')
    if (-not (Test-Path -LiteralPath $mdDir)) { Say "no $book book in $docsName; none packaged"; continue }
    $pages = @(Get-ChildItem -LiteralPath $mdDir -Filter '*.md' -File | Where-Object { $_.BaseName -ne 'index' })
    $have = 0
    foreach ($pg in $pages) {
        $p = Join-Path $pdfDir ($pg.BaseName + '.pdf')
        if (-not (Test-Path -LiteralPath $p)) { $stale += "$book\pdf\$($pg.BaseName).pdf is missing"; continue }
        if ((Get-Item -LiteralPath $p).LastWriteTime -lt $pg.LastWriteTime) { $stale += "$book\pdf\$($pg.BaseName).pdf is older than its markdown"; continue }
        if (-not (Test-PdfMagic $p)) { $stale += "$book\pdf\$($pg.BaseName).pdf is not a PDF"; continue }
        $name = $book.ToLower() + '-' + $pg.BaseName + '.pdf'
        if ($name -cnotmatch '^[a-z0-9][a-z0-9._-]{0,79}$') { $stale += "$name is not a name DOCS.INSTALL takes (lower case, digits . _ -, up to 80)"; continue }
        if ($pdfs | Where-Object { $_[1] -eq $name }) { $stale += "two PDFs are named $name"; continue }
        $pdfs += , @($p, $name); $have++
    }
    foreach ($p in @(Get-ChildItem -LiteralPath $pdfDir -Filter '*.pdf' -File -ErrorAction SilentlyContinue)) {
        if ($p.BaseName -ne 'index' -and -not (Test-Path -LiteralPath (Join-Path $mdDir ($p.BaseName + '.md')))) { $notes += "$book\pdf\$($p.Name) has no markdown page (left from an earlier build); not packaged" }
    }
    Say ("{0}: {1} markdown pages, {2} PDFs to package" -f $book, $pages.Count, $have)
}
foreach ($n in $notes) { Say "NOTE: $n" }
if ($stale.Count) {
    foreach ($s in $stale) { Write-Host "mkrelease:   $s" -ForegroundColor Red }
    Die ("{0} chapter PDF(s) cannot be packaged. In {1}:  powershell -ExecutionPolicy Bypass -File tools\release.ps1 -Set <book> -Version {2} -NoZip" -f $stale.Count, $DocsRepo, $Version)
}
if ($pdfs.Count -eq 0) { Die "no chapter PDFs at all in $DocsRepo" }

# Clients: each folder's COMMIT.txt names and hashes every other file in it
$clientDirs = @()
if ($Clients) {
    if (-not (Test-Path -LiteralPath $Clients -PathType Container)) { Die "no clients folder $Clients" }
    $subs = @(Get-ChildItem -LiteralPath $Clients -Directory)
    if ($subs.Count -eq 0) { Die "the clients folder $Clients holds no client folder" }
    foreach ($s in $subs) {
        $ct = Join-Path $s.FullName 'COMMIT.txt'
        if (-not (Test-Path -LiteralPath $ct)) { Die "$($s.FullName) has no COMMIT.txt" }
        if (@(Get-ChildItem -LiteralPath $s.FullName -Directory).Count) { Die "$($s.FullName) holds a folder; a client folder holds files only" }
        $listed = @{}
        foreach ($l in (Get-Content -LiteralPath $ct)) { if ($l -match '^([0-9a-f]{64})\s+(\S+)\s*$') { $listed[$Matches[2]] = $Matches[1] } }
        $files = @(Get-ChildItem -LiteralPath $s.FullName -File | Where-Object { $_.Name -ne 'COMMIT.txt' })
        if ($files.Count -eq 0) { Die "$($s.FullName) holds no client file" }
        foreach ($f in $files) {
            if (-not $listed.ContainsKey($f.Name)) { Die "$($s.Name)\$($f.Name) is not in its COMMIT.txt" }
            if ((Hash $f.FullName) -ne $listed[$f.Name]) { Die "$($s.Name)\$($f.Name) does not match the sha256 in its COMMIT.txt" }
        }
        foreach ($k in $listed.Keys) { if (-not (Test-Path -LiteralPath (Join-Path $s.FullName $k))) { Die "$($s.Name)\COMMIT.txt names $k, which is not there" } }
        Say ("clients\{0}: {1} file(s) match COMMIT.txt" -f $s.Name, $files.Count)
        $clientDirs += $s
    }
}
if ($Books) {
    $bookFiles = @(Get-ChildItem -LiteralPath $Books -Filter ($bookPre + $Version + '-*.pdf') -File -ErrorAction SilentlyContinue)
    if ($bookFiles.Count -eq 0) { Die "no $bookPre$Version-*.pdf in $Books" }
    foreach ($b in $bookFiles) { if (-not (Test-PdfMagic $b.FullName)) { Die "$($b.FullName) is not a PDF" } }
}
if ($SshServer -and @(Get-ChildItem -LiteralPath $SshServer -Filter 'OpenSSH-Win64-*.msi' -File -ErrorAction SilentlyContinue).Count -ne 1) { Die "-SshServer: one OpenSSH-Win64-*.msi wanted in $SshServer" }
if ($Python -and @(Get-ChildItem -LiteralPath $Python -Filter 'python-*-amd64.exe' -File -ErrorAction SilentlyContinue).Count -ne 1) { Die "-Python: one python-*-amd64.exe wanted in $Python" }

# --- stage ----------------------------------------------------------------------------------------------------------------
if ((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $zipf)) {
    if (-not $Force) { Die "$stage or $zipf exists (-Force replaces both)" }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    if (Test-Path -LiteralPath $zipf) { Remove-Item -LiteralPath $zipf -Force }
}
Say "staging $pkg"
$null = New-Item -ItemType Directory -Path $stage
$null = New-Item -ItemType Directory -Path (Join-Path $stage 'pdf')
Copy-Item -LiteralPath $Installer -Destination $stage
Copy-Item -LiteralPath $SourceZip -Destination $stage
Copy-Item -LiteralPath $sourceTxt -Destination $stage
foreach ($c in $changes) { Copy-Item -LiteralPath $c[0] -Destination (Join-Path $stage $c[1]) }
foreach ($p in $pdfs) { Copy-Item -LiteralPath $p[0] -Destination (Join-Path $stage ('pdf\' + $p[1])) }
if ($Readme) { Copy-Item -LiteralPath $Readme -Destination (Join-Path $stage 'README.txt') }
if ($ConfSample) { Copy-Item -LiteralPath $ConfSample -Destination $stage }
foreach ($s in $clientDirs) {
    $to = Join-Path $stage ('clients\' + $s.Name); $null = New-Item -ItemType Directory -Path $to -Force
    Get-ChildItem -LiteralPath $s.FullName -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $to }
}
if ($Books) { $to = Join-Path $stage 'documentation'; $null = New-Item -ItemType Directory -Path $to; foreach ($b in $bookFiles) { Copy-Item -LiteralPath $b.FullName -Destination $to } }
if ($SshServer) { $to = Join-Path $stage 'ssh-server'; $null = New-Item -ItemType Directory -Path $to; Get-ChildItem -LiteralPath $SshServer -Filter 'OpenSSH-Win64-*.msi' -File | Copy-Item -Destination $to }
if ($Python) { $to = Join-Path $stage 'python'; $null = New-Item -ItemType Directory -Path $to; Get-ChildItem -LiteralPath $Python -Filter 'python-*-amd64.exe' -File | Copy-Item -Destination $to }

# SHA256SUMS.txt: every other file, forward slashes, sorted ordinally (sha256sum -c reads it on Linux as well)
$all = @(Get-ChildItem -LiteralPath $stage -Recurse -File)
$lines = foreach ($f in $all) { '{0}  {1}' -f (Hash $f.FullName), ($f.FullName.Substring($stage.Length + 1) -replace '\\', '/') }
$lines = [string[]]$lines; [Array]::Sort($lines, [StringComparer]::Ordinal)
[System.IO.File]::WriteAllText((Join-Path $stage 'SHA256SUMS.txt'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))

# --- zip ------------------------------------------------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Say ("zipping {0} files (about 30 seconds) ..." -f ($all.Count + 1))
# Entry by entry, named with forward slashes: .NET Framework's CreateFromDirectory (Windows PowerShell 5.1) names every entry with
# backslashes, which unzip on Linux reads as part of the file name (measured 13 Nov 2026: 154 of 154 entries, caught by the check below).
$script:zipMade = $zipf
$zs = [System.IO.File]::Open($zipf, [System.IO.FileMode]::CreateNew)
try {
    $za = New-Object System.IO.Compression.ZipArchive($zs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in @(Get-ChildItem -LiteralPath $stage -Recurse -File)) {
            $entry = $pkg + '/' + ($f.FullName.Substring($stage.Length + 1) -replace '\\', '/')
            $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $za.Dispose() }
} finally { $zs.Dispose() }

# --- check the zip as a person unpacking it will find it -------------------------------------------------------------------
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('mkrelease-' + [guid]::NewGuid().ToString('N'))
try {
    Say "unpacking into $scratch to check it ..."
    $za = [System.IO.Compression.ZipFile]::OpenRead($zipf)
    try { $bad = @($za.Entries | Where-Object { $_.FullName -match '\\' }) } finally { $za.Dispose() }
    if ($bad.Count) { Fail "$($bad.Count) zip entries carry a backslash (first: $($bad[0].FullName))" }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipf, $scratch)
    $u = Join-Path $scratch $pkg
    if (-not (Test-Path -LiteralPath $u)) { Fail "the zip does not unpack to one folder $pkg" }
    $want = @{}; foreach ($f in @(Get-ChildItem -LiteralPath $stage -Recurse -File)) { $want[$f.FullName.Substring($stage.Length + 1)] = Hash $f.FullName }
    $got = @{}; foreach ($f in @(Get-ChildItem -LiteralPath $u -Recurse -File)) { $got[$f.FullName.Substring($u.Length + 1)] = Hash $f.FullName }
    foreach ($k in $want.Keys) { if (-not $got.ContainsKey($k)) { Fail "$k is staged but not in the zip" } elseif ($got[$k] -ne $want[$k]) { Fail "$k differs between staging and the zip" } }
    foreach ($k in $got.Keys) { if (-not $want.ContainsKey($k)) { Fail "$k is in the zip but was not staged" } }
    $n = 0
    foreach ($l in (Get-Content -LiteralPath (Join-Path $u 'SHA256SUMS.txt'))) {
        if ($l -notmatch '^([0-9a-f]{64})  (.+)$') { Fail "SHA256SUMS.txt line not understood: $l" }
        $p = Join-Path $u ($Matches[2] -replace '/', '\')
        if (-not (Test-Path -LiteralPath $p)) { Fail "SHA256SUMS.txt names $($Matches[2]), which is not in the zip" }
        if ((Hash $p) -ne $Matches[1]) { Fail "SHA256SUMS.txt does not match $($Matches[2])" }
        $n++
    }
    if ($n -ne $got.Count - 1) { Fail "SHA256SUMS.txt lists $n files; the zip holds $($got.Count - 1) besides it" }
    if ((Hash (Join-Path $u (Split-Path -Leaf $Installer))) -ne (Hash $Installer)) { Fail 'the installer in the zip is not the one given' }
    $nPdf = @(Get-ChildItem -LiteralPath (Join-Path $u 'pdf') -Filter '*.pdf' -File).Count
    if ($nPdf -ne $pdfs.Count) { Fail "pdf\ holds $nPdf PDFs in the zip, $($pdfs.Count) were staged" }
    foreach ($c in $changes) { if (-not (Test-Path -LiteralPath (Join-Path $u $c[1]))) { Fail "$($c[1]) is not in the zip" } }
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

Write-Host ''
Say "Made $zipf"
Say ("  {0} files ({1} chapter PDFs), built from {2} ({3}){4}" -f $got.Count, $nPdf, $commit, $branch, $(if ($Label -eq 'test') { ' - TEST PACKAGE, NOT FOR DISTRIBUTION' } else { '' }))
if (-not $Readme) { Say '  NOT INCLUDED: README.txt (-Readme FILE; the owner reads it before anything is distributed)' }
if (-not $Books) { Say '  NOT INCLUDED: documentation\ (-Books DIR; the whole-book PDFs, mkbook.py and mkbookpdf.ps1 in the docs repository)' }
if (-not $Clients) { Say '  NOT INCLUDED: clients\ (-Clients DIR; P:\sdcore-mail\transfer\clients holds the current sets)' }
if (-not $SshServer) { Say '  NOT INCLUDED: ssh-server\ (-SshServer DIR)' }
if (-not $Python) { Say '  NOT INCLUDED: python\ (-Python DIR)' }
if ($product -eq 'Solo' -and -not $ConfSample) { Say '  NOT INCLUDED: sd-solo-setup.conf.sample (-ConfSample FILE)' }
Say '  sha256 for the README:'
Say ('    {0}  {1}' -f (Split-Path -Leaf $Installer), (Hash $Installer))
Say ('    SHA256SUMS.txt  {0}' -f (Hash (Join-Path $stage 'SHA256SUMS.txt')))
Say ('    {0}  {1}' -f (Split-Path -Leaf $zipf), (Hash $zipf))
Say 'NOT DONE HERE: rendering the documents, the README, an install from the zip, the merge to main, the tag, the push.'
exit 0
