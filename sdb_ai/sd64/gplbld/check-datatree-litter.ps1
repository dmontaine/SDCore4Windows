# check-datatree-litter.ps1 - find names in the data tree that only the POSIX
# runtime could have written.
#
# 1 Sep 26 - PRE_RELEASE 6.  An empty directory called "C:" sat in
# C:\ProgramData\SD\sdsys for six days and three sessions, and the reason it
# survived that long is that THE TWO OBVIOUS INSTRUMENTS BOTH REPORT NOTHING:
#
#   find . -name 'C:'      - MSYS mangles the argument before find sees it
#   Test-Path '...\sdsys\C:' - a trailing colon names an alternate data stream,
#                              so this answers False about a directory that is
#                              plainly there
#
# A SEARCH FOR THIS BY NAME WILL KEEP COMING BACK CLEAN.  It has to be found by
# enumerating and reading the characters, which is what this does.
#
# WHAT IT LOOKS FOR, AND WHY IT IS NOT JUST "C:".  When the MSYS2/Cygwin runtime
# is asked to create a file whose name contains a character NTFS forbids, it
# does not fail - it writes the character into the U+F000-U+F0FF private use
# area, so ':' becomes U+F03A, '\' becomes U+F05C, and so on.  Any such name in
# the data tree is therefore something SD wrote that no Windows tool would have,
# which is the whole class rather than the one instance.  Entries 60 and 65 are
# litter of the same family.
#
# UNELEVATED AND READ-ONLY.  Get-ChildItem only; it creates and deletes nothing.
# Not wired into either runner - run it by hand after a cycle.
#
# Exit 0 = clean, 1 = litter found, 2 = it could not measure (which is NOT a pass).

[CmdletBinding()]
param(
    [string] $DataTree = 'C:\ProgramData\SD'
)

# No file-scope Set-StrictMode or $ErrorActionPreference here on purpose: both
# bind the CALLER if this file is ever dot-sourced, which is the trap
# test-suiteonly-units.ps1 section 0 exists to catch. Errors are handled where
# they can happen, with -ErrorAction on the call itself.

Write-Output 'check-datatree-litter: names the POSIX runtime wrote and Windows would not'
Write-Output ("  data tree : {0}" -f $DataTree)

if (-not (Test-Path -LiteralPath $DataTree)) {
    Write-Output "  the data tree is not present - NOTHING WAS MEASURED."
    Write-Output '  RESULT: CANNOT MEASURE (exit 2). This is not a clean report.'
    exit 2
}

$resolved = (Get-Item -LiteralPath $DataTree).FullName
Write-Output ("  resolved  : {0}" -f $resolved)

$all = @()
try {
    $all = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue)
} catch {
    Write-Output ("  enumeration failed: {0}" -f $_.Exception.Message)
    Write-Output '  RESULT: CANNOT MEASURE (exit 2).'
    exit 2
}

Write-Output ("  entries   : {0} scanned" -f $all.Count)

# THE NULL CASE.  An empty or near-empty scan is indistinguishable from a clean
# one, and a clean report from a scan that reached nothing is exactly the false
# green the instrument rules forbid.  A real SD data tree is thousands of files;
# sdsys alone was 39 entries at the top level on 1 Sep 26.
if ($all.Count -lt 100) {
    Write-Output '  FEWER THAN 100 ENTRIES REACHED. A real data tree is far larger, so this'
    Write-Output '  scan probably hit a permission wall rather than a clean tree.'
    Write-Output '  RESULT: CANNOT MEASURE (exit 2). This is not a clean report.'
    exit 2
}

# The private use block the runtime maps forbidden characters into.
$litter = @($all | Where-Object {
    $n = $_.Name
    $hit = $false
    foreach ($c in $n.ToCharArray()) {
        $cp = [int]$c
        if ($cp -ge 0xF000 -and $cp -le 0xF0FF) { $hit = $true; break }
    }
    $hit
})

if ($litter.Count -eq 0) {
    Write-Output ''
    Write-Output '  no name in the data tree carries a U+F000-U+F0FF character.'
    Write-Output '  RESULT: CLEAN (exit 0)'
    exit 0
}

Write-Output ''
Write-Output ("  FOUND {0} entr(y/ies) with a private-use character in the name:" -f $litter.Count)
foreach ($i in $litter) {
    $cps = (($i.Name.ToCharArray()) | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
    $kind = if ($i.PSIsContainer) { 'dir ' } else { 'file' }
    Write-Output ''
    Write-Output ("    {0} {1}" -f $kind, $i.FullName)
    Write-Output ("         name       {0}" -f $i.Name)
    Write-Output ("         codepoints {0}" -f $cps)
    Write-Output ("         created    {0}" -f $i.CreationTime.ToString('yyyy-MM-dd HH:mm:ss.fff'))
    Write-Output ("         written    {0}" -f $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff'))
    if ($i.PSIsContainer) {
        $kids = @(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue)
        Write-Output ("         contains   {0} entr(y/ies)" -f $kids.Count)
    }
}

Write-Output ''
Write-Output '  U+F03A is a colon, U+F05C a backslash - the runtime writes them this way'
Write-Output '  because NTFS forbids the real character. Compare the two timestamps above'
Write-Output '  BEFORE concluding anything from them: they are different fields, and'
Write-Output '  reading one against the other is what misdirected PRE_RELEASE 6 for a week.'
Write-Output ''
Write-Output '  RESULT: LITTER FOUND (exit 1)'
exit 1
