# test-accarchive-units.ps1 - drive sd-account-archive.ps1's functions on scratch trees.
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-accarchive-units.ps1
#
# ORDINARY UNELEVATED PROMPT.  No install, no SD, no elevation.  Exit 0 all
# passed, 1 something failed, 2 could not set up.  Everything it makes is under
# %TEMP%\test-accarchive-<pid> and is removed at the end.
#
# WHY IT EXISTS.  RELEASE_1.1 116: the script is what BACKUP.ACCOUNT and
# RESTORE.ACCOUNT trust with the account data, and the restore half replaces an
# account's files.  Every rule is in a function, and this lifts them out of the
# file by AST (test-sdpath-units.ps1's technique) rather than copying them, so
# it tests the shipped text.  Protect-Dir is not driven: closing a directory to
# SYSTEM and Administrators locks an unelevated test out of its own fixture.
#
# NOT SHIPPED - assert-current exempts test-* scripts by name.

$ErrorActionPreference = 'Stop'

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $here 'sd-account-archive.ps1'

Write-Host "test-accarchive-units: subject $subject"
if (-not (Test-Path -LiteralPath $subject)) { Write-Host 'test-accarchive-units: subject not found.'; exit 2 }

# --- lift the functions ------------------------------------------------------
$tok = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($subject, [ref]$tok, [ref]$errs)
if ($errs.Count -gt 0) { Write-Host "test-accarchive-units: subject has $($errs.Count) parse error(s)."; exit 2 }

$wanted = @('Test-EntryName', 'Get-TreeItems', 'Get-TreeCounts', 'Format-Counts', 'New-AccountZip',
            'Add-ZipFile', 'Expand-AccountZip', 'Move-AccountTree', 'Move-FsItem', 'Reset-ChildAcl', 'Protect-Dir',
            'Test-AkQuery')
$lifted = 0
foreach ($name in $wanted) {
    $fn = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true))
    if ($fn.Count -ne 1) { Write-Host "test-accarchive-units: expected exactly one $name, found $($fn.Count)."; exit 2 }
    . ([scriptblock]::Create($fn[0].Extent.Text))
    $lifted++
}
if ($lifted -ne $wanted.Count) { Write-Host 'test-accarchive-units: VOID - not every function was lifted.'; exit 2 }
Write-Host "  lifted $lifted functions"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:pass = 0
$script:fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $what" }
    else     { $script:fail++; Write-Host "  [FAIL] $what $detail" }
}
function Throws([scriptblock]$sb, [string]$like) {
    try { & $sb; return "no exception" } catch {
        if ($_.Exception.Message -like $like) { return '' }
        return "wrong exception: $($_.Exception.Message)"
    }
}
function Get-Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

# A zip with exactly these entry names; a name ending "/" is a directory.
function New-RawZip([string]$zip, [string[]]$names) {
    $z = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
    try {
        foreach ($n in $names) {
            $e = $z.CreateEntry($n)
            if (-not $n.EndsWith('/')) {
                $w = New-Object System.IO.StreamWriter($e.Open())
                try { $w.Write("x") } finally { $w.Dispose() }
            }
        }
    } finally { $z.Dispose() }
}

$work = Join-Path $env:TEMP ("test-accarchive-" + $PID)
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
[void][System.IO.Directory]::CreateDirectory($work)
Write-Host "  scratch $work"

try {
    # --- 1. entry-name rules -------------------------------------------------
    Write-Host ''
    Write-Host '1. entry names'
    foreach ($ok in @('manifest.txt', 'accounts/', 'accounts/sales/', 'accounts/sales/bp/MyProg',
                      'accounts/sales/data/%0', 'accounts/sales/x[1]')) {
        $r = Test-EntryName $ok
        Check "accepted '$ok'" ($r -eq '') $r
    }
    foreach ($bad in @('', '/accounts/sales/x', 'accounts/../x', 'accounts/sales/../../x', 'accounts\sales',
                       'C:/x', 'other/x', 'accounts//x', 'accounts/./x', 'accounts',
                       ('accounts/s/' + [char]0xE9), ('accounts/s/a' + [char]9 + 'b'))) {
        $r = Test-EntryName $bad
        Check "refused '$bad' ($r)" ($r -ne '')
    }

    # --- 2. a source account tree --------------------------------------------
    Write-Host ''
    Write-Host '2. create'
    $src = Join-Path $work 'src\Sales'
    foreach ($d in @('bp', 'data', 'emptyfile', 'deep\a\b', 'voc')) { [void][System.IO.Directory]::CreateDirectory((Join-Path $src $d)) }
    [System.IO.File]::WriteAllText((Join-Path $src 'bp\MyProg'), "PROGRAM MyProg`nEND`n")
    [System.IO.File]::WriteAllText((Join-Path $src 'bp\x[1]'), "bracket`n")
    $rnd = New-Object byte[] 150000
    (New-Object System.Random 42).NextBytes($rnd)
    [System.IO.File]::WriteAllBytes((Join-Path $src 'data\%0'), $rnd)
    [System.IO.File]::WriteAllText((Join-Path $src 'deep\a\b\leaf'), "leaf`n")
    $hidden = Join-Path $src 'bp\hidden'
    [System.IO.File]::WriteAllText($hidden, "h`n")
    (Get-Item -LiteralPath $hidden -Force).Attributes = 'Hidden'
    $man = Join-Path $work 'manifest.txt'
    [System.IO.File]::WriteAllText($man, "format: 1`n")

    $srcCounts = Get-TreeCounts $src
    Check "source counted: $(Format-Counts $srcCounts)" ($srcCounts.Files -eq 5 -and $srcCounts.Dirs -eq 7 -and $srcCounts.Bytes -gt 150000)

    $zip = Join-Path $work 'b.zip'
    $entries = @([pscustomobject]@{ Name = 'manifest.txt'; Source = $man },
                 [pscustomobject]@{ Name = 'accounts/sales'; Source = $src })
    $counts = @(New-AccountZip $zip $entries)
    Check 'one counts object per entry' ($counts.Count -eq 2)
    Check "manifest entry counted as one file: $(Format-Counts $counts[0])" ($counts[0].Files -eq 1 -and $counts[0].Dirs -eq 0)
    Check "account counts written = source counts ($(Format-Counts $counts[1]))" ((Format-Counts $counts[1]) -eq (Format-Counts $srcCounts))

    $z = [System.IO.Compression.ZipFile]::OpenRead($zip)
    $names = @($z.Entries | ForEach-Object { $_.FullName })
    $z.Dispose()
    Check 'empty directory stored as its own entry' ($names -contains 'accounts/sales/emptyfile/')
    Check 'account root stored as a directory entry' ($names -contains 'accounts/sales/')
    Check 'stored under the ACCOUNT name, not the directory name' (-not ($names | Where-Object { $_ -clike '*Sales*' }))
    Check 'record case kept (MyProg)' ($names -ccontains 'accounts/sales/bp/MyProg')
    Check 'hidden file included' ($names -contains 'accounts/sales/bp/hidden')
    Check 'no backslash in any name' (-not ($names | Where-Object { $_.Contains('\') }))
    Check 'refuses an existing zip' ((Throws { New-AccountZip $zip $entries } '*already exists*') -eq '')
    Check 'refuses a missing source, leaves no zip' (((Throws { New-AccountZip (Join-Path $work 'n.zip') @([pscustomobject]@{ Name = 'accounts/x'; Source = (Join-Path $work 'nope') }) } '*no such source*') -eq '') -and -not (Test-Path (Join-Path $work 'n.zip')))

    # --- 3. extract ----------------------------------------------------------
    Write-Host ''
    Write-Host '3. extract'
    $dest = Join-Path $work 'stage'
    $got = @(Expand-AccountZip $zip $dest $false)
    Check 'one account extracted' ($got.Count -eq 1 -and $got[0].Name -eq 'sales')
    Check "extracted counts = source counts ($(Format-Counts $got[0]))" ((Format-Counts $got[0]) -eq (Format-Counts $srcCounts))
    Check 'binary file identical' ((Get-Sha (Join-Path $dest 'accounts\sales\data\%0')) -eq (Get-Sha (Join-Path $src 'data\%0')))
    Check 'empty directory restored' (Test-Path -LiteralPath (Join-Path $dest 'accounts\sales\emptyfile') -PathType Container)
    Check 'bracketed name restored' (Test-Path -LiteralPath (Join-Path $dest 'accounts\sales\bp\x[1]') -PathType Leaf)
    Check 'manifest at the root' (Test-Path -LiteralPath (Join-Path $dest 'manifest.txt') -PathType Leaf)
    Check 'refuses an existing target' ((Throws { Expand-AccountZip $zip $dest $false } '*already exists*') -eq '')

    $cases = @(
        @{ Name = 'path escape';      Names = @('manifest.txt', 'accounts/s/', 'accounts/s/../../evil');  Like = '*bad entry name*' },
        @{ Name = 'outside accounts'; Names = @('manifest.txt', 'evil.txt');                               Like = '*bad entry name*' },
        @{ Name = 'case-only clash';  Names = @('manifest.txt', 'accounts/s/', 'accounts/s/A', 'accounts/s/a'); Like = '*differ only in case*' },
        @{ Name = 'no manifest';      Names = @('accounts/s/', 'accounts/s/x');                            Like = '*no manifest*' }
    )
    $k = 0
    foreach ($c in $cases) {
        $k++
        $bz = Join-Path $work "bad$k.zip"
        New-RawZip $bz $c.Names
        $bd = Join-Path $work "badout$k"
        $r = Throws { Expand-AccountZip $bz $bd $false } $c.Like
        Check "refuses $($c.Name), writes nothing" (($r -eq '') -and -not (Test-Path -LiteralPath $bd)) $r
    }
    Check 'nothing escaped the scratch tree' (-not (Test-Path -LiteralPath (Join-Path (Split-Path $work -Parent) 'evil')))

    # --- 4. reparse points ---------------------------------------------------
    Write-Host ''
    Write-Host '4. reparse point'
    $jt = Join-Path $work 'jsrc'
    [void][System.IO.Directory]::CreateDirectory($jt)
    $null = & cmd.exe /c mklink /J (Join-Path $jt 'link') (Join-Path $work 'src') 2>&1
    if (Test-Path -LiteralPath (Join-Path $jt 'link')) {
        Check 'a junction is refused, not followed' ((Throws { Get-TreeCounts $jt } '*reparse point*') -eq '')
        [System.IO.Directory]::Delete((Join-Path $jt 'link'))
    } else {
        Check 'could make a junction to test with' $false 'mklink /J failed'
    }

    # --- 5. place ------------------------------------------------------------
    Write-Host ''
    Write-Host '5. place'
    $target = Join-Path $work 'target'
    [void][System.IO.Directory]::CreateDirectory((Join-Path $target 'olddir'))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $target 'voc'))
    [System.IO.File]::WriteAllText((Join-Path $target 'old.txt'), "old`n")
    $staged = Join-Path $dest 'accounts\sales'

    $novoc = Join-Path $work 'novoc'
    [void][System.IO.Directory]::CreateDirectory($novoc)
    [System.IO.File]::WriteAllText((Join-Path $novoc 'precious.txt'), "p`n")
    Check 'refuses a target that is not an account directory' (((Throws { Move-AccountTree $staged $novoc } '*no voc*') -eq '') -and (Test-Path -LiteralPath (Join-Path $novoc 'precious.txt')))
    $placed = Move-AccountTree $staged $target
    Check "target holds the new tree ($(Format-Counts $placed))" ((Format-Counts $placed) -eq (Format-Counts $srcCounts))
    Check 'old contents gone from the target' (-not (Test-Path -LiteralPath (Join-Path $target 'old.txt')))
    Check 'old contents kept aside until removed' (Test-Path -LiteralPath ($staged + '.old\old.txt'))
    Check 'staged directory emptied' (@(Get-ChildItem -LiteralPath $staged -Force).Count -eq 0)

    # Give one child an explicit ACE, as a file moved in from elsewhere would have.
    $probe = Join-Path $target 'bp\MyProg'
    $null = & icacls.exe $probe /grant '*S-1-1-0:(R)' 2>&1
    $before = @((Get-Acl -LiteralPath $probe).Access | Where-Object { -not $_.IsInherited }).Count
    Reset-ChildAcl $target
    $after = @((Get-Acl -LiteralPath $probe).Access | Where-Object { -not $_.IsInherited }).Count
    Check "ACL reset makes children inherit (explicit ACEs $before -> $after)" ($before -gt 0 -and $after -eq 0)

    # Rollback: a locked file in the staged tree cannot be moved.
    $t2 = Join-Path $work 'target2'; $s2 = Join-Path $work 'staged2'
    [void][System.IO.Directory]::CreateDirectory((Join-Path $t2 'voc')); [void][System.IO.Directory]::CreateDirectory((Join-Path $s2 'voc'))
    [System.IO.File]::WriteAllText((Join-Path $t2 'keep.txt'), "keep`n")
    [System.IO.File]::WriteAllText((Join-Path $s2 'a.txt'), "a`n")
    $lockPath = Join-Path $s2 'z-locked.txt'
    [System.IO.File]::WriteAllText($lockPath, "z`n")
    $lock = [System.IO.File]::Open($lockPath, 'Open', 'Read', 'None')
    try {
        $r = Throws { Move-AccountTree $s2 $t2 } '*old contents put back*'
    } finally { $lock.Dispose() }
    Check 'a failed move is refused' ($r -eq '') $r
    Check 'old contents back in the target' (Test-Path -LiteralPath (Join-Path $t2 'keep.txt'))
    Check 'new contents back in the staged tree' ((Test-Path -LiteralPath (Join-Path $s2 'a.txt')) -and -not (Test-Path -LiteralPath (Join-Path $t2 'a.txt')))
    Check 'no .old left behind' (-not (Test-Path -LiteralPath ($s2 + '.old')))

    # --- 6. reading sdidx -q -------------------------------------------------
    Write-Host ''
    Write-Host '6. sdidx query'
    $banner = '[ SDIDX W1.1-1   Copyright, Ladybridge Systems, 2007.  All rights reserved. ]'
    Check 'the wanted path is recognised' (Test-AkQuery @($banner, '', 'Index directory is C:\d\ak') 'C:\d\ak')
    Check 'a different path is not' (-not (Test-AkQuery @($banner, 'Index directory is C:\d\old') 'C:\d\ak'))
    Check 'not relocated is not' (-not (Test-AkQuery @($banner, 'Indices are not relocated') 'C:\d\ak'))
    Check 'no output is not' (-not (Test-AkQuery @() 'C:\d\ak'))
    Check 'a prefix of the path is not' (-not (Test-AkQuery @('Index directory is C:\d\ak2') 'C:\d\ak'))
}
catch {
    # A crash after a check has failed is a FAILURE, not "could not set up":
    # check-free-tier reports exit 2 as NO TREE, which would hide it.
    Write-Host "test-accarchive-units: STOPPED - $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($script:fail -gt 0) { Write-Host "test-accarchive-units: FAILED - $($script:fail) failed before it stopped."; exit 1 }
    exit 2
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:pass -eq 0) { Write-Host 'test-accarchive-units: VOID - no check ran.'; exit 2 }
if ($script:fail -gt 0) {
    Write-Host "test-accarchive-units: FAILED - $($script:pass) passed, $($script:fail) failed."
    exit 1
}
Write-Host "test-accarchive-units: PASSED - $($script:pass) of $($script:pass) checks passed."
exit 0
