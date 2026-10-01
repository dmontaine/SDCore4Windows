# sd-account-archive.ps1 - the Windows half of BACKUP.ACCOUNT's and RESTORE.ACCOUNT's file work
#
#   ... -Mode Create  -Zip <file> -ListFile <file>
#   ... -Mode Extract -Zip <file> -Dest <dir>
#   ... -Mode Count   -Path <dir>
#   ... -Mode Place   -Staged <dir> -Target <dir> [-Previous <dir>]
#   ... -Mode AkPath  -Path <hashed file> -AkPath <dir>
#
# Run by SD through !ps_script_out, from gpl.bp ACC_ARCHIVE, which ACC_TREE_COUNT,
# ACC_OS_PLACE and ACC_OS_AKPATH call (RELEASE_1.1 116).  Exit 0 done, 1 refused or failed, 2 could not
# run.  On success the LAST line is "ACC-ARCHIVE <MODE> OK ..." and that is the
# only text a caller may anchor on; a refusal is one "ACC-ARCHIVE ERROR <reason>"
# line.  Counts are printed as "... FILES <n> BYTES <n> DIRS <n>".
#
# THE ZIP FORMAT IS SHARED WITH SD CORE FOR LINUX (agreed by mail 30 Sep - 1 Oct
# 2026): manifest.txt at the root, each account under accounts/<name>/, "/" as
# the separator, deflate or stored, no zip64 below 4 GB, and EVERY directory
# stored as its own "name/" entry with no data - an empty directory is a valid,
# empty SD file, and a zip of files alone loses it.  DIRS counts directories
# under an account directory, not the account directory itself.
#
# WHY .NET AND NOT tar.exe.  Measured 1 Oct 2026: the inbox bsdtar 3.8.8 refuses
# -s ("not supported by this version"), so it cannot store a tree under any name
# but its own, and an account directory can be named differently from its
# account (user_accounts\Ann for account ann, RELEASE_1.1 67).
# System.IO.Compression names every entry explicitly; zips it wrote were read by
# Python's zipfile and by tar.exe, and it extracted Python's, empty directory
# included.  Compress-Archive is NOT used: on 5.1 it writes "\" separators.
#
# COUNTS ARE OF WHAT WAS DONE, NOT A PRIOR SCAN.  Create counts entries as it
# writes them; Extract and Place count the tree on disk afterwards.  The verb
# compares them with the manifest and refuses on a mismatch.
#
# A REPARSE POINT IS REFUSED, never followed.  A junction inside an account would
# put another directory's contents - or a loop - into the backup.

param(
    [Parameter(Mandatory = $true)] [ValidateSet('Create', 'Extract', 'Count', 'Place', 'AkPath')] [string]$Mode,
    [string]$Zip = '',
    [string]$ListFile = '',
    [string]$Dest = '',
    [string]$Path = '',
    [string]$Staged = '',
    [string]$Target = '',
    [string]$AkPath = '',
    [string]$Previous = ''
)

$ErrorActionPreference = 'Stop'

# --- pure rules --------------------------------------------------------------

# '' when an archive entry name may be extracted, otherwise why not.  Printable
# ASCII only (SD maps a record id outside 32-126 to nothing, op_dio3.c
# map_t1_id); "/" only; no absolute name, no empty, "." or ".." segment; and
# nothing outside manifest.txt and accounts/<name>/.
function Test-EntryName([string]$name) {
    if ($name -eq '') { return 'empty name' }
    if ($name -notmatch '^[\x20-\x7E]+$') { return 'non-printable or non-ASCII character' }
    if ($name.Contains('\')) { return 'backslash' }
    if ($name.Contains(':')) { return 'colon' }
    if ($name.StartsWith('/')) { return 'absolute name' }
    if ($name -eq 'manifest.txt' -or $name -eq 'accounts/') { return '' }
    if (-not $name.StartsWith('accounts/')) { return 'outside accounts/' }
    $body = $name.TrimEnd('/')
    $segs = $body.Split('/')
    if ($segs.Count -lt 2) { return 'no account name' }
    foreach ($s in $segs) {
        if ($s -eq '' -or $s -eq '.' -or $s -eq '..') { return "bad segment '$s'" }
    }
    return ''
}

# Every directory and file under $root, depth first, as objects with Rel ("/"
# separated, relative to $root), IsDir, Full and Length.  Refuses a reparse point.
function Get-TreeItems([string]$root) {
    $root  = (New-Object System.IO.DirectoryInfo($root)).FullName.TrimEnd('\')
    $items = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $di  = New-Object System.IO.DirectoryInfo($dir)
        foreach ($e in $di.GetFileSystemInfos()) {
            if ($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "reparse point $($e.FullName)"
            }
            $rel = $e.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
            if ($e -is [System.IO.DirectoryInfo]) {
                $items.Add([pscustomobject]@{ Rel = $rel; IsDir = $true; Full = $e.FullName; Length = 0 })
                $stack.Push($e.FullName)
            } else {
                $items.Add([pscustomobject]@{ Rel = $rel; IsDir = $false; Full = $e.FullName; Length = $e.Length })
            }
        }
    }
    return ,$items
}

function Get-TreeCounts([string]$root) {
    $c = [pscustomobject]@{ Files = 0; Bytes = [int64]0; Dirs = 0 }
    foreach ($i in (Get-TreeItems $root)) {
        if ($i.IsDir) { $c.Dirs++ } else { $c.Files++; $c.Bytes += $i.Length }
    }
    return $c
}

function Format-Counts($c) { return "FILES $($c.Files) BYTES $($c.Bytes) DIRS $($c.Dirs)" }

# --- the four operations -----------------------------------------------------

# $entries: objects with Name and Source.  A FILE source is stored under exactly
# Name; a DIRECTORY is stored as Name/ and everything beneath it.  Returns one
# counts object per entry, in order.  The zip must not exist; a failure removes
# the partial zip.
function New-AccountZip([string]$zipPath, $entries) {
    if (Test-Path -LiteralPath $zipPath) { throw "zip already exists: $zipPath" }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $result = @()
    $z = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    $ok = $false
    try {
        foreach ($en in $entries) {
            $c = [pscustomobject]@{ Files = 0; Bytes = [int64]0; Dirs = 0 }
            if (Test-Path -LiteralPath $en.Source -PathType Leaf) {
                Add-ZipFile $z $en.Source $en.Name
                $c.Files = 1; $c.Bytes = (New-Object System.IO.FileInfo($en.Source)).Length
            } elseif (Test-Path -LiteralPath $en.Source -PathType Container) {
                $root = (New-Object System.IO.DirectoryInfo($en.Source)).FullName.TrimEnd('\')
                [void]$z.CreateEntry($en.Name + '/')
                foreach ($i in (Get-TreeItems $root)) {
                    if ($i.IsDir) {
                        [void]$z.CreateEntry($en.Name + '/' + $i.Rel + '/')
                        $c.Dirs++
                    } else {
                        Add-ZipFile $z $i.Full ($en.Name + '/' + $i.Rel)
                        $c.Files++; $c.Bytes += $i.Length
                    }
                }
            } else {
                throw "no such source: $($en.Source)"
            }
            $result += $c
        }
        $ok = $true
    } finally {
        $z.Dispose()
        if (-not $ok) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
    }
    return $result
}

# Read with FileShare.ReadWrite so a handle someone else holds cannot fail the
# backup; nothing else may be using the account by the time this runs (the verb
# has refused while anyone is logged in).
function Add-ZipFile($z, [string]$src, [string]$name) {
    $e  = $z.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
    $e.LastWriteTime = [System.IO.File]::GetLastWriteTime($src)    # not Get-Item: it cannot see a hidden file
    $fs = [System.IO.File]::Open($src, 'Open', 'Read', 'ReadWrite')
    try {
        $es = $e.Open()
        try { $fs.CopyTo($es) } finally { $es.Dispose() }
    } finally { $fs.Dispose() }
}

# Every name is checked BEFORE anything is written, including the Windows-only
# refusal of two names differing only in case (agreed with Linux 1 Oct 2026:
# NTFS cannot hold both).  $dest must not exist; a failure removes it.  With
# $protect the directory is closed (Protect-Dir) before any data goes in; the
# unit test passes $false because it runs unelevated.  Returns one counts object
# per account, measured on disk after extraction, with Name.
#
# .NET calls rather than New-Item and Move-Item: a record id may hold "[", which
# the cmdlets' -Path and -Destination can read as a wildcard.
function Expand-AccountZip([string]$zipPath, [string]$dest, [bool]$protect) {
    if (Test-Path -LiteralPath $dest) { throw "extract target already exists: $dest" }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    $made = $false
    $ok = $false
    try {
        $seen = @{}    # case-blind already; the ToLowerInvariant below says so out loud
        $haveManifest = $false
        foreach ($e in $z.Entries) {
            $why = Test-EntryName $e.FullName
            if ($why -ne '') { throw "bad entry name '$($e.FullName)': $why" }
            $key = $e.FullName.TrimEnd('/').ToLowerInvariant()
            if ($seen.ContainsKey($key)) {
                if ($seen[$key] -cne $e.FullName.TrimEnd('/')) {
                    throw "names differ only in case: '$($seen[$key])' and '$($e.FullName)'"
                }
                throw "duplicate entry '$($e.FullName)'"
            }
            $seen[$key] = $e.FullName.TrimEnd('/')
            if ($e.FullName -eq 'manifest.txt') { $haveManifest = $true }
        }
        if (-not $haveManifest) { throw 'no manifest.txt in the archive' }

        [void][System.IO.Directory]::CreateDirectory($dest)
        $made = $true
        if ($protect) { Protect-Dir $dest }
        $accounts = @{}
        foreach ($e in $z.Entries) {
            $out = [System.IO.Path]::Combine($dest, $e.FullName.TrimEnd('/').Replace('/', '\'))
            $segs = $e.FullName.Split('/')
            if ($segs[0] -eq 'accounts' -and $segs.Count -gt 1 -and $segs[1] -ne '') { $accounts[$segs[1]] = $true }
            if ($e.FullName.EndsWith('/')) {
                [void][System.IO.Directory]::CreateDirectory($out)
                continue
            }
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($out))
            $es = $e.Open()
            try {
                $fs = [System.IO.File]::Open($out, 'CreateNew', 'Write', 'None')
                try { $es.CopyTo($fs) } finally { $fs.Dispose() }
            } finally { $es.Dispose() }
            [System.IO.File]::SetLastWriteTime($out, $e.LastWriteTime.DateTime)
        }
        $result = @()
        foreach ($name in ($accounts.Keys | Sort-Object)) {
            $c = Get-TreeCounts ([System.IO.Path]::Combine($dest, 'accounts', $name))
            $c | Add-Member -NotePropertyName Name -NotePropertyValue $name
            $result += $c
        }
        $ok = $true
        return $result
    } finally {
        $z.Dispose()
        if ($made -and -not $ok) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Replace the CONTENTS of $target with the contents of $staged.  The target
# directory itself stays: its explicit ACL is the account's grant (CREATE.ACCOUNT
# secure.account.dir, secure-account-dirs.ps1), and a directory moved into its
# place would carry the staging ACL instead.  The old contents go to $old (a
# directory that must not exist yet, on the same volume) before any new one
# comes in; the CALLER decides whether $old is removed afterwards or kept (Solo
# keeps it as .sdrestore.previous).  Any failure puts everything back.  Returns
# the counts of $target after.
#
# BOTH MUST HOLD A voc - secure-account-dirs.ps1's test for "this is an account
# directory".  A wrong path must not be able to empty some other directory.
function Move-AccountTree([string]$staged, [string]$target, [string]$old) {
    if (-not (Test-Path -LiteralPath $staged -PathType Container)) { throw "no staged tree: $staged" }
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "no target directory: $target" }
    foreach ($d in @($staged, $target)) {
        if (-not (Test-Path -LiteralPath ([System.IO.Path]::Combine($d, 'voc')))) { throw "not an account directory (no voc): $d" }
    }
    if ($old -eq '') { throw 'no directory given for the old contents' }
    if (Test-Path -LiteralPath $old) { throw "already exists: $old" }
    [void][System.IO.Directory]::CreateDirectory($old)

    $movedOut = @(); $movedIn = @()
    try {
        foreach ($c in @(Get-ChildItem -LiteralPath $target -Force)) {
            $to = [System.IO.Path]::Combine($old, $c.Name)
            Move-FsItem $c.FullName $to
            $movedOut += [pscustomobject]@{ From = $c.FullName; To = $to }
        }
        foreach ($c in @(Get-ChildItem -LiteralPath $staged -Force)) {
            $to = [System.IO.Path]::Combine($target, $c.Name)
            Move-FsItem $c.FullName $to
            $movedIn += [pscustomobject]@{ From = $c.FullName; To = $to }
        }
    } catch {
        $first = $_.Exception.Message
        foreach ($m in $movedIn)  { try { Move-FsItem $m.To $m.From } catch { } }
        foreach ($m in $movedOut) { try { Move-FsItem $m.To $m.From } catch { } }
        Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
        throw "move failed, old contents put back: $first"
    }
    return (Get-TreeCounts $target)
}

# A same-volume rename of a file or a directory.
function Move-FsItem([string]$from, [string]$to) {
    if ([System.IO.Directory]::Exists($from)) { [System.IO.Directory]::Move($from, $to) }
    else { [System.IO.File]::Move($from, $to) }
}

# Everything under $target inherits $target's ACL again (a moved file keeps the
# ACL it had).  "$target\*" with /T resets the children and their trees but NOT
# $target, whose explicit grant must stay.
function Reset-ChildAcl([string]$target) {
    if (@(Get-ChildItem -LiteralPath $target -Force).Count -eq 0) { return }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & icacls.exe (Join-Path $target '*') /reset /T /C /Q 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($rc -ne 0) { throw "icacls /reset exit $rc on $target\*: $($out -join ' ')" }
}

# True when "sdidx -q" output names $want as the index directory.  sdidx -p
# prints nothing on success and does not check its own header write
# (gplsrc/sdidx.c, case 'P'), so its exit status proves nothing; the query is
# the instrument.
function Test-AkQuery([string[]]$lines, [string]$want) {
    foreach ($l in $lines) {
        if ($l.TrimEnd() -ceq "Index directory is $want") { return $true }
    }
    return $false
}

# The staging directory holds account data between unpacking and placing, so it
# is closed to everyone but SYSTEM and Administrators - the data tree it sits in
# grants sdusers Modify by inheritance.  One icacls, so it is never open between
# removing inheritance and granting.
function Protect-Dir([string]$dir) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & icacls.exe $dir /inheritance:r /grant '*S-1-5-18:(OI)(CI)(F)' /grant '*S-1-5-32-544:(OI)(CI)(F)' 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($rc -ne 0) { throw "icacls exit $rc securing ${dir}: $($out -join ' ')" }
}

# --- dispatch ----------------------------------------------------------------

Write-Output "ACC-ARCHIVE mode=$Mode zip=$Zip list=$ListFile dest=$Dest path=$Path staged=$Staged target=$Target akpath=$AkPath previous=$Previous"
try {
    switch ($Mode) {
        'Create' {
            if ($Zip -eq '' -or $ListFile -eq '') { Write-Output 'ACC-ARCHIVE ERROR Create needs -Zip and -ListFile'; exit 2 }
            $entries = @()
            foreach ($line in [System.IO.File]::ReadAllLines($ListFile)) {
                if ($line -eq '') { continue }
                $p = $line.Split("`t")
                if ($p.Count -ne 2) { Write-Output "ACC-ARCHIVE ERROR bad list line: $line"; exit 2 }
                $why = Test-EntryName ($p[0] + $(if (Test-Path -LiteralPath $p[1] -PathType Container) { '/' } else { '' }))
                if ($why -ne '') { Write-Output "ACC-ARCHIVE ERROR bad entry name '$($p[0])': $why"; exit 1 }
                $entries += [pscustomobject]@{ Name = $p[0]; Source = $p[1] }
            }
            if ($entries.Count -eq 0) { Write-Output 'ACC-ARCHIVE ERROR the list is empty'; exit 1 }
            $counts = @(New-AccountZip $Zip $entries)
            for ($i = 0; $i -lt $entries.Count; $i++) {
                Write-Output ("ACC-ARCHIVE ENTRY {0} {1} {2}" -f ($i + 1), $entries[$i].Name, (Format-Counts $counts[$i]))
            }
            Write-Output ("ACC-ARCHIVE CREATE OK ENTRIES {0} ZIPBYTES {1}" -f $entries.Count, (Get-Item -LiteralPath $Zip).Length)
        }
        'Extract' {
            if ($Zip -eq '' -or $Dest -eq '') { Write-Output 'ACC-ARCHIVE ERROR Extract needs -Zip and -Dest'; exit 2 }
            $counts = @(Expand-AccountZip $Zip $Dest $true)
            foreach ($c in $counts) { Write-Output ("ACC-ARCHIVE ACCOUNT {0} {1}" -f $c.Name, (Format-Counts $c)) }
            Write-Output ("ACC-ARCHIVE EXTRACT OK ACCOUNTS {0}" -f $counts.Count)
        }
        'Count' {
            if ($Path -eq '') { Write-Output 'ACC-ARCHIVE ERROR Count needs -Path'; exit 2 }
            if (-not (Test-Path -LiteralPath $Path -PathType Container)) { Write-Output "ACC-ARCHIVE ERROR no such directory: $Path"; exit 1 }
            Write-Output ("ACC-ARCHIVE COUNT OK " + (Format-Counts (Get-TreeCounts $Path)))
        }
        'Place' {
            if ($Staged -eq '' -or $Target -eq '') { Write-Output 'ACC-ARCHIVE ERROR Place needs -Staged and -Target'; exit 2 }
            # -Previous KEEPS the old contents there, replacing an older copy
            # (SD Core Solo's .sdrestore.previous, agreed with Linux 2 Oct
            # 2026; the same text in both products); without it they go to
            # "<staged>.old" and are removed.
            $keep = ($Previous -ne '')
            if ($keep) {
                $old = $Previous
                if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
            } else {
                $old = $Staged.TrimEnd('\') + '.old'
            }
            $c = Move-AccountTree $Staged $Target $old
            try { Reset-ChildAcl $Target }
            catch { throw "the new contents ARE in place, but their permissions were not reset: $($_.Exception.Message)" }
            if (-not $keep) {
                Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $old) { Write-Output "ACC-ARCHIVE WARNING the old contents could not be removed: $old" }
            }
            Write-Output ("ACC-ARCHIVE PLACE OK " + (Format-Counts $c))
        }
        'AkPath' {
            if ($Path -eq '' -or $AkPath -eq '') { Write-Output 'ACC-ARCHIVE ERROR AkPath needs -Path and -AkPath'; exit 2 }
            # The installer puts sdidx.exe in usr\bin under the program directory
            # this script ships to (stage.py PF_BIN_SUBDIR).
            $sdidx = [System.IO.Path]::Combine($PSScriptRoot, 'usr', 'bin', 'sdidx.exe')
            if (-not (Test-Path -LiteralPath $sdidx)) { Write-Output "ACC-ARCHIVE ERROR no $sdidx"; exit 2 }
            if (-not (Test-Path -LiteralPath $AkPath -PathType Container)) { Write-Output "ACC-ARCHIVE ERROR no index directory $AkPath"; exit 1 }
            $prev = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $set = @(& $sdidx -p $Path $AkPath 2>&1 | ForEach-Object { "$_" })
            $qry = @(& $sdidx -q $Path 2>&1 | ForEach-Object { "$_" })
            $ErrorActionPreference = $prev
            foreach ($l in ($set + $qry)) { if ($l.Trim() -ne '') { Write-Output "ACC-ARCHIVE SDIDX $l" } }
            if (-not (Test-AkQuery $qry $AkPath)) { Write-Output "ACC-ARCHIVE ERROR sdidx -q does not report $AkPath for $Path"; exit 1 }
            Write-Output 'ACC-ARCHIVE AKPATH OK'
        }
    }
    exit 0
} catch {
    Write-Output "ACC-ARCHIVE ERROR $($_.Exception.Message)"
    exit 1
}
