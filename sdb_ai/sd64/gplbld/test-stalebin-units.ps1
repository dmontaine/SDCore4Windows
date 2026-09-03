# test-stalebin-units.ps1 - unit test for stale-binaries.ps1, the rule that
# decides whether the C needs rebuilding.  Needs NO install, NO elevation and
# NO run token, so it costs nothing and can run before the rule is handed to
# either of its two callers.
#
#   powershell -File test-stalebin-units.ps1
#
# Exit 0 every row passed, 1 a row failed, 2 the subject could not be read.
#
# START-HISTORY:
# 03 Sep 26 Windows port - written with stale-binaries.ps1, when assert-current
#           check A2 gained a second consumer in cycle.ps1's step 0.
# END-HISTORY
#
# ***WHY THIS RULE IS WORTH A TEST OF ITS OWN.***  It now decides two different
# things: whether assert-current REFUSES to let anything be measured, and
# whether cycle.ps1 DELETES the binaries and relinks.  Both directions are
# expensive to get wrong, and in opposite ways:
#
#   too EAGER  - a false "stale" makes every verify script refuse on a tree
#                that is fine.  That has happened three times, each time from a
#                build product or a document being counted as source, and each
#                time it cost a session: "make check-local" builds an .exe
#                under localtest\, "make check" builds two INTO sdclilib\, and
#                editing VENDORING.md answered "run make sd, then run a cycle"
#                when the rebuild had nothing to read.
#   too BLIND  - a false "current" is worse: it is how a C edit reached a
#                commit having never been compiled (to_file.c, 18 Aug 2026),
#                and the test for the change PASSED on the stale binary.
#
# THE EXCLUSIONS CANNOT BE EXERCISED BY RUNNING THE THING, which is the usual
# reason a rule ends up here: on a healthy tree the answer is "nothing is
# stale", and a rule that had silently stopped looking would give exactly that
# answer too.
#
# The functions are lifted out of the shipped file BY THE PowerShell PARSER,
# not copied - the technique test-reclaim-units.ps1 and test-reconcile-units.ps1
# both use, for the reason they both give.

param(
    [string] $Subject = ''
)

$ErrorActionPreference = 'Stop'

$pass = 0
$fail = 0

function Note([bool]$ok, [string]$what, [string]$detail = '') {
    if ($ok) {
        $script:pass++
        Write-Host ("  PASS  " + $what)
    } else {
        $script:fail++
        Write-Host ("  FAIL  " + $what + $(if ($detail -ne '') { "  <- " + $detail } else { '' }))
    }
}

if ($Subject -eq '') { $Subject = Join-Path $PSScriptRoot 'stale-binaries.ps1' }
$Subject = [System.IO.Path]::GetFullPath($Subject)

Write-Host ''
Write-Host ('test-stalebin-units: subject ' + $Subject)

if (-not (Test-Path -LiteralPath $Subject)) {
    Write-Host ('  FAIL  no such file: ' + $Subject)
    Write-Host 'test-stalebin-units: 0 passed, 1 failed'
    exit 2
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Subject, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host ('  FAIL  ' + $Subject + ' does not parse: ' + $errors.Count + ' error(s)')
    $errors | ForEach-Object { Write-Host ('        line ' + $_.Extent.StartLineNumber + ': ' + $_.Message) }
    Write-Host 'test-stalebin-units: 0 passed, 1 failed'
    exit 2
}

$funcs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
Write-Host ('test-stalebin-units: parsed, ' + $tokens.Count + ' tokens, ' +
            $funcs.Count + ' function(s): ' + (($funcs | ForEach-Object { $_.Name }) -join ', '))

# REFUSE THE NULL CASE OUT LOUD.  A file whose functions the parser cannot find
# parses with zero errors - that is how an embedded BOM scored a false green as
# step 17 of b18 - so the names are asserted, not assumed.
$wanted = @('Get-BinBinaries', 'Test-IsSdSource', 'Get-BinaryStaleness')
foreach ($w in $wanted) {
    $d = @($funcs | Where-Object { $_.Name -eq $w })
    if ($d.Count -ne 1) {
        Write-Host ('  FAIL  ' + $Subject + ' defines ' + $d.Count + ' function(s) called ' + $w + ', expected 1')
        Write-Host 'test-stalebin-units: 0 passed, 1 failed'
        exit 2
    }
    . ([scriptblock]::Create($d[0].Extent.Text))
}

# --- a synthetic tree ------------------------------------------------------
#
# Real files, because the subject reads mtimes off the filesystem and the whole
# question is "is this one newer than that one".

$tmp    = Join-Path ([System.IO.Path]::GetTempPath()) ('stalebin-units-' + [System.Guid]::NewGuid().ToString('N'))
$bin    = Join-Path $tmp 'bin'
$gplsrc = Join-Path $tmp 'gplsrc'
New-Item -ItemType Directory -Path $bin    -Force | Out-Null
New-Item -ItemType Directory -Path $gplsrc -Force | Out-Null

function Touch($path, [datetime]$when) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $path -Value 'x' -Encoding ASCII
    (Get-Item -LiteralPath $path).LastWriteTime = $when
}

$old   = [datetime]'2026-09-01 10:00:00'   # the binaries
$older = [datetime]'2026-08-01 10:00:00'   # a kept backup, deliberately ancient
$new   = [datetime]'2026-09-02 10:00:00'   # an edit after the build

Touch (Join-Path $bin 'sd.exe')       $old
Touch (Join-Path $bin 'sdwind.exe')   $old
Touch (Join-Path $bin 'sdclilib.dll') $old
Touch (Join-Path $bin 'README')       $new
# THE TWO THAT MUST NOT COUNT AS BINARIES.  Both are real files in the real
# bin\ today, and either one counting would make the oldest binary far older
# than it is - which turns every source file permanently stale.
Touch (Join-Path $bin 'sd.exe.installed-backup-20260819') $older
Touch (Join-Path $bin 'libsdclilib.dll.a')                $older

Write-Host ''
Write-Host '--- Get-BinBinaries: what counts as a binary'

$b = @(Get-BinBinaries $tmp)
$names = @($b | ForEach-Object { $_.Name } | Sort-Object)
Note ($b.Count -eq 3) 'three binaries found' ($names -join ', ')
Note ($names -contains 'sd.exe' -and $names -contains 'sdwind.exe' -and $names -contains 'sdclilib.dll') `
     'the .exe and .dll files are counted' ($names -join ', ')
Note (-not ($names -contains 'sd.exe.installed-backup-20260819')) `
     'a kept sd.exe backup is NOT a binary - its extension is not .exe'
Note (-not ($names -contains 'libsdclilib.dll.a')) `
     'libsdclilib.dll.a is NOT a binary - it is an import library rebuilt with the DLL'
Note (-not ($names -contains 'README')) 'README is not a binary'

# AND THE BACKUP MUST NOT DRAG THE OLDEST DOWN.  This is the row that matters:
# if it counted, "oldest" would be 01 Aug and every source file would be newer.
$s = Get-BinaryStaleness $tmp
Note ($s.oldest.LastWriteTime -eq $old) 'the oldest binary is the build, not the kept backup' `
     ($s.oldest.Name + ' ' + $s.oldest.LastWriteTime)

Write-Host ''
Write-Host '--- Test-IsSdSource: what counts as source'

Note (Test-IsSdSource 'C:\r\gplsrc\to_file.c' 'to_file.c')     'a .c file is source'
Note (Test-IsSdSource 'C:\r\gplsrc\keys.h' 'keys.h')           'a .h file is source'
Note (Test-IsSdSource 'C:\r\gplsrc\sdsvc\sdsvc.c' 'sdsvc.c')   'a .c under a subdirectory is source'

# EACH OF THESE COST A SESSION.  See the header.
Note (-not (Test-IsSdSource 'C:\r\gplsrc\sdclilib\localtest\local-connect-test.exe' 'local-connect-test.exe')) `
     'localtest\ is excluded - "make check-local" rebuilds it every run'
Note (-not (Test-IsSdSource 'C:\r\gplsrc\__pycache__\x.pyc' 'x.pyc')) `
     '__pycache__ is excluded'
Note (-not (Test-IsSdSource 'C:\r\gplsrc\sdclilib\tests\t.c' 't.c')) `
     'sdclilib\tests\ is excluded - those link AGAINST the DLL, they are not in it'
Note (-not (Test-IsSdSource 'C:\r\gplsrc\sdclilib\smoke-test.exe' 'smoke-test.exe')) `
     'a build product is excluded even outside localtest - "make check" builds INTO sdclilib\'
Note (-not (Test-IsSdSource 'C:\r\gplsrc\x.o' 'x.o'))     'an object file is excluded'
Note (-not (Test-IsSdSource 'C:\r\gplsrc\x.a' 'x.a'))     'a static library is excluded'
Note (-not (Test-IsSdSource 'C:\r\gplsrc\sdclilib\VENDORING.md' 'VENDORING.md')) `
     'documentation is excluded - a rebuild has nothing to read and the install nothing to receive'
Note (-not (Test-IsSdSource 'C:\r\gplsrc\notes.txt' 'notes.txt')) 'a .txt is excluded'

# THE EXCLUSIONS MUST NOT BE SO BROAD THEY SWALLOW REAL SOURCE.  "too blind" is
# the worse of the two failures - see the header.
Note (Test-IsSdSource 'C:\r\gplsrc\localtester.c' 'localtester.c') `
     'localtest is matched as a DIRECTORY, so localtester.c is still source'
Note (Test-IsSdSource 'C:\r\gplsrc\sdclilib\testsuite.c' 'testsuite.c') `
     'sdclilib\tests\ is matched as a directory, so testsuite.c is still source'

Write-Host ''
Write-Host '--- Get-BinaryStaleness: the verdict'

Touch (Join-Path $gplsrc 'quiet.c') ([datetime]'2026-08-15 10:00:00')
$s = Get-BinaryStaleness $tmp
Note ($s.ok -and -not $s.stale) 'source older than the binaries is NOT stale' `
     ('ok=' + $s.ok + ' stale=' + $s.stale)

Touch (Join-Path $gplsrc 'edited.c') $new
$s = Get-BinaryStaleness $tmp
Note ($s.ok -and $s.stale) 'a source file newer than the oldest binary IS stale'
Note ((@($s.uncompiled)).Count -eq 1) 'and exactly one file is named' ((@($s.uncompiled)).Count)
Note ($s.uncompiled[0].Name -eq 'edited.c') 'by name' ($s.uncompiled[0].Name)

# AN EXCLUDED FILE MUST NOT TRIP IT, end to end and not only through the
# predicate - this is the false STALE that no reinstall clears.
Remove-Item -LiteralPath (Join-Path $gplsrc 'edited.c') -Force
Touch (Join-Path $gplsrc 'sdclilib\localtest\local-connect-test.exe') $new
Touch (Join-Path $gplsrc 'sdclilib\VENDORING.md') $new
$s = Get-BinaryStaleness $tmp
Note ($s.ok -and -not $s.stale) 'a rebuilt localtest exe and an edited .md leave the tree CURRENT' `
     (($s.uncompiled | ForEach-Object { $_.Name }) -join ', ')

Write-Host ''
Write-Host '--- Get-BinaryStaleness: it answers rather than guessing'

$empty = Join-Path ([System.IO.Path]::GetTempPath()) ('stalebin-empty-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $empty 'bin')    -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $empty 'gplsrc') -Force | Out-Null
$s = Get-BinaryStaleness $empty
Note ($null -ne $s)     'an empty bin\ returns an answer, not $null'
Note (-not $s.ok)       'and says the question could not be answered'
Note ($s.reason -like '*no binaries*') 'naming the reason' $s.reason
Note ($s.stale)         'and errs towards stale, because a false current is the worse failure'

$noSrc = Join-Path ([System.IO.Path]::GetTempPath()) ('stalebin-nosrc-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $noSrc 'bin') -Force | Out-Null
Touch (Join-Path $noSrc 'bin\sd.exe') $old
$s = Get-BinaryStaleness $noSrc
Note (-not $s.ok) 'a missing gplsrc is refused rather than read as "no source newer"' `
     ('ok=' + $s.ok + ' stale=' + $s.stale)

# THE HASHTABLE ITSELF.  A function returning a collection hands the caller
# $null when it is empty and a bare scalar when it holds one - measured 3 Sep
# 2026 - so both callers would read "nothing to do" from a broken lookup.
$s = Get-BinaryStaleness $tmp
Note ($s -is [hashtable]) 'the result is a hashtable, which nothing unrolls' ($s.GetType().Name)
foreach ($k in 'ok', 'reason', 'binaries', 'oldest', 'uncompiled', 'stale') {
    Note ($s.ContainsKey($k)) ('it carries ' + $k)
}

Remove-Item -LiteralPath $tmp    -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $empty  -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $noSrc  -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ('test-stalebin-units: ' + $pass + ' passed, ' + $fail + ' failed')

if ($pass -eq 0) {
    Write-Host 'test-stalebin-units: NOTHING WAS ASSERTED - that is a failure, not a pass.'
    exit 1
}
if ($fail -gt 0) { exit 1 }
exit 0
