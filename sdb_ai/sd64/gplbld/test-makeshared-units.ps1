# test-makeshared-units.ps1 - drive gplbld/make-shared.ps1's decisions (RELEASE_1.1 170, S.66, the Windows installer half of the shared account)
# and the one rule secure-account-dirs.ps1 must keep, against scratch fixtures.  No SD, no install, no elevation.
#
#   powershell -ExecutionPolicy Bypass -File ...\test-makeshared-units.ps1
#
# WHAT IT PROTECTS.
#   1. The PREFLIGHT: an account named shared that is not SD's own stops the install (exit 4, with the register record named) and an
#      absent or SD-own one does not.  A refusal that never fires would let the installer adopt an account the administrator made.
#   2. The ACL VERDICT: the shared directory is SYSTEM and Administrators Full, the users group Modify, both (OI)(CI), inheritance broken,
#      nothing else.  Judged entry by entry from the live ACL of a scratch directory, with the users group stood in for by "Users" (the
#      group sdusers exists only on an installed machine), and MUTATED: each wrong ACL must be reported.
#   3. THE SECOND SCRIPT MUST NOT UNDO THE FIRST (Linux's check for the three differences, 24 Oct): secure-account-dirs.ps1, which runs at
#      every install over group_accounts, stamps the directory named shared for sdusers and NOT for sdg_shared.  Without that line the next
#      install locks every user out of the shared files.  Driven with -WhatIf over a scratch root, and mutated by removing the rule.
#
# The ACL and group parts need a Windows with icacls and net.exe; where a step cannot be run it says so and FAILS rather than passing.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkipRun = $true
. (Join-Path $here 'make-shared.ps1')
$SkipRun = $false

$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name$(if($detail){"  ->  $detail"})" }
}

foreach ($fn in 'Get-SharedRecordVerdict', 'Get-SharedAclProblems', 'Get-SharedGroupMembers', 'Get-SharedVerdict') {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { Write-Host "test-makeshared-units: could not load $fn"; exit 1 }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("makeshared-test-$PID")
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Write-Host "scratch: $scratch"

function New-Fixture([string]$name, [string[]]$lines) {
    $data = Join-Path $scratch $name
    $reg = Join-Path $data 'sdsys\accounts'
    New-Item -ItemType Directory -Path $reg -Force | Out-Null
    if ($null -ne $lines) { Set-Content -LiteralPath (Join-Path $reg 'shared') -Value $lines -Encoding ascii }
    return $data
}

try {
    # --- 1. the record verdict, on its own -------------------------------------------------------------------------------------
    $dir = 'C:\ProgramData\SD\group_accounts\shared'
    $f = New-Fixture 'absent' $null
    $v = Get-SharedRecordVerdict -Record (Join-Path $f 'sdsys\accounts\shared') -Dir $dir
    Check 'no record: absent' ($v.Verdict -eq 'absent')

    foreach ($spelling in @('C:\ProgramData\SD\group_accounts\shared', 'C:\ProgramData\SD\group_accounts/shared', 'c:\programdata\sd\group_accounts\SHARED\')) {
        $f = New-Fixture ('ours-' + [Math]::Abs($spelling.GetHashCode())) @($spelling, 'x', 'sdg_shared', 'y')
        $v = Get-SharedRecordVerdict -Record (Join-Path $f 'sdsys\accounts\shared') -Dir $dir
        Check "SD's own record, spelled '$spelling': ours" ($v.Verdict -eq 'ours') "got $($v.Verdict)"
    }

    $f = New-Fixture 'foreign-path' @('D:\data\shared', 'x', 'sdg_shared')
    $v = Get-SharedRecordVerdict -Record (Join-Path $f 'sdsys\accounts\shared') -Dir $dir
    Check 'a record with another path: foreign' ($v.Verdict -eq 'foreign')
    Check 'foreign: line 1 is reported as read' ($v.Line1 -eq 'D:\data\shared')

    $f = New-Fixture 'foreign-group' @($dir, 'x', 'sdusers')
    $v = Get-SharedRecordVerdict -Record (Join-Path $f 'sdsys\accounts\shared') -Dir $dir
    Check 'the right path but the group sdusers: foreign' ($v.Verdict -eq 'foreign')

    $f = New-Fixture 'short' @($dir)
    $v = Get-SharedRecordVerdict -Record (Join-Path $f 'sdsys\accounts\shared') -Dir $dir
    Check 'a record with no line 3: foreign (it is not what the installer writes)' ($v.Verdict -eq 'foreign')

    # --- 2. the preflight, through the script itself (the exit code the installer reads) ----------------------------------------
    $ps = (Get-Command powershell.exe).Source
    $script = Join-Path $here 'make-shared.ps1'
    function Run-Preflight([string]$data) {
        $rf = Join-Path $scratch ("reason-$([guid]::NewGuid().ToString('N')).txt")
        $a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script, '-Preflight', '-DataDir', $data, '-ReasonFile', $rf)
        Write-Host ("  run: powershell " + ($a -join ' '))
        $out = & $ps @a 2>&1
        $code = $LASTEXITCODE
        $reason = ''
        if (Test-Path $rf) { $reason = Get-Content -Raw $rf }
        return [pscustomobject]@{ Code = $code; Out = ($out -join "`n"); Reason = $reason }
    }

    $f = New-Fixture 'pf-absent' $null
    $r = Run-Preflight $f
    Check 'preflight, no shared account: exit 0' ($r.Code -eq 0) "exit $($r.Code): $($r.Out)"

    $oursData = Join-Path $scratch 'pf-ours'
    $f = New-Fixture 'pf-ours' @((Join-Path $oursData 'group_accounts\shared'), 'x', 'sdg_shared')
    $r = Run-Preflight $f
    Check 'preflight, SD''s own account (data dir of the fixture): exit 0' ($r.Code -eq 0) "exit $($r.Code): $($r.Out)"

    $f = New-Fixture 'pf-foreign' @('D:\somewhere\shared', 'x', 'sdusers')
    $r = Run-Preflight $f
    Check 'preflight, foreign account: exit 4' ($r.Code -eq 4) "exit $($r.Code): $($r.Out)"
    Check 'preflight, foreign: the reason names the register record' ($r.Reason -match [regex]::Escape('sdsys\accounts\shared'))
    Check 'preflight, foreign: the reason gives both lines it read' (($r.Reason -match 'D:\\somewhere\\shared') -and ($r.Reason -match "'sdusers'"))
    Check 'preflight, foreign: the success wording is NOT printed' ($r.Out -notmatch 'preflight ok')

    # --- 3. the ACL verdict, on a real directory --------------------------------------------------------------------------------
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    $users = 'Users'
    function New-Shared([string]$name, [string[]]$grants, [bool]$breakInheritance = $true) {
        $d = Join-Path $scratch $name
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $a = @($d)
        if ($breakInheritance) { $a += '/inheritance:r' }
        foreach ($g in $grants) { $a += '/grant'; $a += $g }
        $o = & $icacls @a 2>&1
        if ($LASTEXITCODE -ne 0) { throw "icacls failed on $d : $($o -join ' ')" }
        return $d
    }
    $good = @('*S-1-5-18:(OI)(CI)(F)', '*S-1-5-32-544:(OI)(CI)(F)', ($users + ':(OI)(CI)(M)'))

    $d = New-Shared 'acl-good' $good
    $p = @(Get-SharedAclProblems -Dir $d -UsersGroup $users)
    Check 'ACL as designed: no problems' ($p.Count -eq 0) ($p -join '; ')

    # mutants: each wrong ACL must be reported, and by the right words
    $d = New-Shared 'acl-nobreak' $good $false
    $p = @(Get-SharedAclProblems -Dir $d -UsersGroup $users)
    Check 'MUTANT inheritance not broken: reported' (($p -join ';') -match 'inheritance') ($p -join '; ')

    $d = New-Shared 'acl-full' @('*S-1-5-18:(OI)(CI)(F)', '*S-1-5-32-544:(OI)(CI)(F)', ($users + ':(OI)(CI)(F)'))
    $p = @(Get-SharedAclProblems -Dir $d -UsersGroup $users)
    Check 'MUTANT users group has Full control: reported' (($p -join ';') -match 'Full control') ($p -join '; ')

    $d = New-Shared 'acl-read' @('*S-1-5-18:(OI)(CI)(F)', '*S-1-5-32-544:(OI)(CI)(F)', ($users + ':(OI)(CI)(R)'))
    $p = @(Get-SharedAclProblems -Dir $d -UsersGroup $users)
    Check 'MUTANT users group only Read: reported' ($p.Count -gt 0) ($p -join '; ')

    $d = New-Shared 'acl-extra' ($good + @('*S-1-1-0:(OI)(CI)(R)'))
    $p = @(Get-SharedAclProblems -Dir $d -UsersGroup $users)
    Check 'MUTANT an extra entry for Everyone: reported' (($p -join ';') -match 'unexpected') ($p -join '; ')

    $d = New-Shared 'acl-noadmin' @('*S-1-5-18:(OI)(CI)(F)', ($users + ':(OI)(CI)(M)'))
    $p = @(Get-SharedAclProblems -Dir $d -UsersGroup $users)
    Check 'MUTANT no Administrators entry: reported' (($p -join ';') -match 'S-1-5-32-544') ($p -join '; ')

    $d = New-Shared 'acl-noinherit' @('*S-1-5-18:(OI)(CI)(F)', '*S-1-5-32-544:(OI)(CI)(F)', ($users + ':(M)'))
    $p = @(Get-SharedAclProblems -Dir $d -UsersGroup $users)
    Check 'MUTANT users entry not inherited by files and folders: reported' (($p -join ';') -match '\(OI\)\(CI\)') ($p -join '; ')

    $p = @(Get-SharedAclProblems -Dir (Join-Path $scratch 'no-such-dir') -UsersGroup $users)
    Check 'no directory at all: reported' ($p.Count -eq 1 -and $p[0] -match 'no directory')

    $p = @(Get-SharedAclProblems -Dir (Join-Path $scratch 'acl-good') -UsersGroup 'no-such-group-xyz')
    Check 'a users group that does not exist: reported' (($p -join ';') -match 'does not exist')

    # --- 4. the group's members -------------------------------------------------------------------------------------------------
    $m = Get-SharedGroupMembers 'Users'
    Check 'the members of an existing group are listed' ($null -ne $m -and @($m).Count -gt 0) 'Users had no members'
    $m = Get-SharedGroupMembers 'no-such-group-xyz'
    Check 'a group that does not exist answers null, not an empty list' ($null -eq $m)

    # --- 5. secure-account-dirs.ps1 must keep the rule for shared ---------------------------------------------------------------
    $sad = Join-Path $here 'secure-account-dirs.ps1'
    $root = Join-Path $scratch 'group_accounts'
    foreach ($n in 'shared', 'other') {
        New-Item -ItemType Directory -Path (Join-Path $root $n) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root "$n\voc") -Value 'x' -Encoding ascii
    }
    function Run-Sad([string]$scriptPath, [string]$prefix) {
        $a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-Root', $root, '-GroupPrefix', $prefix, '-WhatIf')
        Write-Host ("  run: powershell " + ($a -join ' '))
        $o = & $ps @a 2>&1
        return ($o -join "`n")
    }
    $o = Run-Sad $sad 'sdg_'
    Check 'sdg_ run: shared is judged against sdusers' ($o -match 'shared[^\n]*sdusers') $o
    Check 'sdg_ run: shared is NOT judged against sdg_shared' ($o -notmatch 'sdg_shared') $o
    Check 'sdg_ run: another account is still judged against its own sdg_ group' ($o -match 'sdg_other') $o
    $o2 = Run-Sad $sad 'sdu_'
    Check 'sdu_ run: the rule does not apply (a user account called shared cannot exist)' ($o2 -match 'sdu_shared') $o2

    # MUTANT: the same script without the rule must put the directory against sdg_shared, which is what the test above forbids
    $mut = Join-Path $scratch 'secure-account-dirs-mutant.ps1'
    $src = Get-Content -Raw -LiteralPath $sad
    $mutText = $src -replace "(?m)^\s*if \(\(\`$GroupPrefix -eq 'sdg_'\) -and \(\`$name -ieq 'shared'\)\) \{ \`$group = 'sdusers' \}\s*$", ''
    Check 'mutant built: the rule line was found and removed' ($mutText.Length -lt $src.Length) 'the rule line is not where the test expects it'
    Set-Content -LiteralPath $mut -Value $mutText -Encoding utf8
    $om = Run-Sad $mut 'sdg_'
    Check 'MUTANT without the rule: shared is judged against sdg_shared (so the check above has teeth)' ($om -match 'sdg_shared') $om
}
finally {
    # the scratch directories carry broken-inheritance ACLs; reset them so they can be removed
    try { & (Join-Path $env:SystemRoot 'System32\icacls.exe') $scratch /reset /T /C /Q 2>&1 | Out-Null } catch { }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "test-makeshared-units: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
if ($pass -eq 0) { Write-Host 'test-makeshared-units: nothing ran'; exit 1 }
exit 0
