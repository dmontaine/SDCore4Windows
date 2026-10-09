# test-verifyauditwords-units.ps1 - drives the pure functions of verify-auditwords.ps1 with synthetic
# audit text.  No install, no elevation, no SD.
#
#   powershell -ExecutionPolicy Bypass -File test-verifyauditwords-units.ps1
#
# Exit 0 every case behaved, 1 one did not, 2 the file under test could not be loaded.
#
# THE POINT IS THAT THE CHECK CAN FAIL.  A reader that said "no upper-case word" about anything it
# was handed would be believed, so the cases include the capital it must find, a MUTANT copy whose
# case-sensitive test has been made insensitive (it must MISS the same capital, proving the fixture
# can tell a broken reader from a good one), and the null case (no text, nothing since -Since).
# It loads the verifier with SD_VERIFYAUDITWORDS_LOAD_ONLY=1, which makes the script return after its
# function definitions and before anything that needs an install.

$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot 'verify-auditwords.ps1'
if (-not (Test-Path -LiteralPath $target)) { Write-Output ('COULD NOT RUN: ' + $target + ' is not there'); exit 2 }

$rows = New-Object System.Collections.ArrayList
function Row([string] $Case, $Got, $Want) {
    $ok = ($Got -eq $Want)
    $null = $rows.Add([pscustomobject]@{ Case = $Case; Got = $Got; Want = $Want; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }) })
    Write-Output ('  [{0}] {1}: got {2}, want {3}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $Case, $Got, $Want)
}

# The verifier is dot-sourced AT SCRIPT SCOPE below (three times: live, mutant, live again).  A
# helper function would dot-source into its own scope and the definitions would vanish on return.
Write-Output ('target: ' + $target)
$env:SD_VERIFYAUDITWORDS_LOAD_ONLY = '1'
. $target
Remove-Item Env:\SD_VERIFYAUDITWORDS_LOAD_ONLY -ErrorAction SilentlyContinue
Row 'Get-AuditEvents is defined after loading' ([bool](Get-Command Get-AuditEvents -ErrorAction SilentlyContinue)) $true
Row 'Get-UpperHeadLines is defined after loading' ([bool](Get-Command Get-UpperHeadLines -ErrorAction SilentlyContinue)) $true
Row 'Measure-EventWord is defined after loading' ([bool](Get-Command Measure-EventWord -ErrorAction SilentlyContinue)) $true
if (-not (Get-Command Get-AuditEvents -ErrorAction SilentlyContinue)) { Write-Output 'COULD NOT RUN: the functions did not load'; exit 2 }

$good = @(
    '2026-10-08 18:46:50 user=SYSTEM uid=0 pid=11 internal session admitted account=SDSYS writer=attach-account',
    '2026-10-08 18:46:51 user=DON uid=1 pid=12 login account=SDSYS',
    '2026-10-08 18:46:52 user=DON uid=1 pid=13 login account=DON command=COUNT VOC',
    '2026-10-08 18:46:53 user=DON uid=1 pid=14 create.account account=ZZAUDG type=group',
    '2026-10-08 18:46:54 user=DON uid=1 pid=15 modify.account route none account=ZZAUDU',
    '2026-10-08 18:46:55 user=DON uid=1 pid=16 restore.account account=zzaudg archive=SD-ace-zzaudg-20261008-184655.zip',
    '2026-10-08 18:46:56 user=DON uid=1 pid=17 api refused request=25 account=SDSYS',
    '2026-10-08 18:46:57 user=DON uid=1 pid=18 account refused branch=4 account=SDSYS reason=x'
) -join "`n"
$since0 = [datetime]::MinValue

$ev = @(Get-AuditEvents $good $since0)
Row 'a lower-case file parses every line' (@($ev | Where-Object { $_.Parsed }).Count) 8
Row 'a lower-case file: no upper-case head (typed names after "=" do not count)' (@(Get-UpperHeadLines $ev)).Count 0
Row 'word of "login account=SDSYS" is login' ($ev[1].Word) 'login'
Row 'word of "login account=DON command=COUNT VOC" is login' ($ev[2].Word) 'login'
Row 'word of "create.account account=..." is create.account' ($ev[3].Word) 'create.account'
Row 'word of "modify.account route none account=.." keeps the route word' ($ev[4].Word) 'modify.account route none'
Row 'word of "account refused branch=4 ..." is account refused' ($ev[7].Word) 'account refused'
Row 'Measure-EventWord counts the login events' (Measure-EventWord $ev '^login') 2
Row 'Measure-EventWord on an event that is not there is 0' (Measure-EventWord $ev '^remote\.api') 0

# The capitals it must find.
$bad = $good + "`n" + '2026-10-08 18:47:00 user=DON uid=1 pid=19 LOGIN account=DON' +
       "`n" + '2026-10-08 18:47:01 user=DON uid=1 pid=20 MODIFY.ACCOUNT ADD account=ZZ to=zz' +
       "`n" + '2026-10-08 18:47:02 user=DON uid=1 pid=21 deny.verbs add WHO - now who'
$evBad = @(Get-AuditEvents $bad $since0)
$up = @(Get-UpperHeadLines $evBad)
Row 'an upper-case event name is found (LOGIN, MODIFY.ACCOUNT ADD)' $up.Count 3
Row 'the first offender carries its line number' ($up[0].Line) 9
Row 'a Capital typed AFTER the first "=" is not an offender' (@(Get-UpperHeadLines (Get-AuditEvents '2026-10-08 18:47:03 user=D uid=1 pid=22 login account=SDSYS' $since0))).Count 0

# -Since filter
$sinceT = [datetime]::ParseExact('2026-10-08 18:46:55', 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
$evSince = @(Get-AuditEvents $good $sinceT)
Row '-Since keeps only lines at or after it (3 of 8)' $evSince.Count 3
Row '-Since drops an old upper-case line' (@(Get-UpperHeadLines (Get-AuditEvents ('2026-10-01 09:00:00 user=D uid=1 pid=1 LOGIN account=OLD' + "`n" + $good) $sinceT))).Count 0

# Unparsed and null cases
$evOdd = @(Get-AuditEvents ($good + "`n" + 'this line has no audit prefix') $since0)
Row 'a line with no audit prefix is returned unparsed, not dropped' (@($evOdd | Where-Object { -not $_.Parsed }).Count) 1
Row 'empty text yields nothing' (@(Get-AuditEvents '' $since0)).Count 0
Row 'null text yields nothing' (@(Get-AuditEvents $null $since0)).Count 0
Row 'Get-UpperHeadLines of nothing is nothing' (@(Get-UpperHeadLines @())).Count 0

# MUTANT: make the capital test insensitive; the same fixture must now be MISSED.  A scratch copy under
# $env:TEMP, removed afterwards; the live file is hashed before and after and must not change.
$hashBefore = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
$src = [IO.File]::ReadAllText($target)
$needle = '$_.Head -cmatch ''[A-Z]'''
Row 'the mutant needle is present in the live file' ($src.Contains($needle)) $true
$mutDir = Join-Path $env:TEMP ('vaw-mutant-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $mutDir
$mutFile = Join-Path $mutDir 'verify-auditwords.ps1'
try {
    [IO.File]::WriteAllText($mutFile, $src.Replace($needle, '$_.Head -cmatch ''[a-z]{99}'''))
    $env:SD_VERIFYAUDITWORDS_LOAD_ONLY = '1'
    . $mutFile
    Remove-Item Env:\SD_VERIFYAUDITWORDS_LOAD_ONLY -ErrorAction SilentlyContinue
    $upM = @(Get-UpperHeadLines (Get-AuditEvents $bad $since0))
    Row 'MUTANT (capital test broken): the same capitals are MISSED' $upM.Count 0
} finally {
    Remove-Item -LiteralPath $mutDir -Recurse -Force -ErrorAction SilentlyContinue
}
$hashAfter = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
Row 'the live verifier is byte-identical after the mutant run' ($hashBefore -eq $hashAfter) $true

# the real one again, after the mutant, to prove the control is not the mutant's leftovers
$env:SD_VERIFYAUDITWORDS_LOAD_ONLY = '1'
. $target
Remove-Item Env:\SD_VERIFYAUDITWORDS_LOAD_ONLY -ErrorAction SilentlyContinue
Row 'live copy reloaded: the capitals are found again' (@(Get-UpperHeadLines (Get-AuditEvents $bad $since0))).Count 3

$failed = @($rows | Where-Object { $_.Result -eq 'FAIL' }).Count
Write-Output ''
Write-Output ('test-verifyauditwords-units: {0} rows, {1} failed' -f $rows.Count, $failed)
if ($failed -gt 0) { exit 1 } else { Write-Output 'PASSED'; exit 0 }
