<#
.SYNOPSIS
    RELEASE_1.1 44's witness: DELETE.ACCOUNT skips an account whose `voc` cannot
    be opened during the cross-reference scan, prints 10188 naming it, and
    FINISHES the deletion instead of aborting (ER_SFNF).

.DESCRIPTION
    THE ELSE MUST BE INDUCED OR IT SHIPS UNEXECUTED.  Linux nearly shipped the
    same fix with its new ELSE never once fired - every account's `voc` was
    present in the witness run, so 10188 never printed and the branch the commit
    was about left no trace (mailbox 15 Sep 2026, their K8/K9).  A plain
    DELETE.ACCOUNT in a cycle does NOT reach the ELSE.  So this MAKES the
    condition rather than waiting for it.

    HOW.  Two throwaway accounts.  A is the one deleted; B is the one whose `voc`
    is crippled so the scan cannot open it.  DELETE.ACCOUNT's cross-reference
    scan (delacc:199) walks EVERY OTHER account's `voc` looking for references to
    A - so deleting A makes it try to open B's `voc`, which is the ELSE.

    THE INDUCER IS B's `voc` DIRECTORY MOVED ASIDE, the shape Linux used: a
    missing `voc` fails `openpath` exactly as an unreadable one does, and it is
    simpler and surer than an ACL.  ***THE WINDOWS-ONLY CASE, an ACL-restricted
    `voc` the elevated deleter cannot open (the ZZINTEROPW case, 15 Sep), reaches
    the SAME ELSE*** and could be a second row; this file takes the simpler
    inducer because either proves the branch.  The `voc` goes back before the
    checks and in the finally if the run dies holding it.

    TWO DECISIVE CHECKS, Linux's K8 and K9:
      - 10188 is printed WITH B's NAME IN IT, so the match cannot be a refusal,
        a "not found", or an echo of the command - the name is the anchor.
      - A's deletion COMPLETED (its ACCOUNTS record is gone).  The abort the fix
        removed happened BEFORE the confirmation, so a completed deletion is the
        proof the scan did not kill the verb.

    ELEVATED, and it refuses otherwise: CREATE.ACCOUNT / DELETE.ACCOUNT are gated
    on an elevated session.  NOT SHIPPED - on assert-current's $neverShipped.

.PARAMETER Prefix
    Base for the two throwaway account names.  Use one nobody has used;
    CREATE.ACCOUNT refuses a name it has seen.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File verify-delacc-xref.ps1 -Prefix sddx1
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.

[CmdletBinding()]
param([Parameter(Mandatory = $false)] [string] $Prefix)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$accts   = Join-Path $env:ProgramData 'SD\sdsys\accounts'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-delacc-xref-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}
function Fail($msg)   { Write-Host ''; Write-Host "STOPPED: $msg" -ForegroundColor Red; try { Stop-Transcript | Out-Null } catch { }; exit 1 }
function Refuse($msg) { Write-Host ''; Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch { }; exit 2 }
function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

function Get-SysMsg([int]$n) {
    $f = Join-Path $env:ProgramData ('SD\sdsys\messages\' + $n)
    if (-not (Test-Path -LiteralPath $f)) { return "<message $n is not installed>" }
    return ((Get-Content -LiteralPath $f -Raw)).Trim()
}

# Drives an SD session from SDSYS, as verify-scramlogin does.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# The account directory (field 1 of the ACCOUNTS record), read from the
# register with forward slashes normalised - the same read verify-apiidentity
# uses.  Empty if the record is absent.
function Get-AccountDir([string]$upperName) {
    $rec = Join-Path $accts $upperName
    if (-not (Test-Path -LiteralPath $rec)) { return '' }
    return ((Get-Content -LiteralPath $rec -TotalCount 1) -replace '/', '\').Trim()
}

# ---------------------------------------------------------------------------
if (-not $Prefix) { Refuse 'pass -Prefix, e.g. -Prefix sddx1.  It names the two throwaway accounts.' }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Refuse 'Run this from an ELEVATED PowerShell - it creates and deletes accounts.'
}

Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current refuses - run gplbld/cycle.ps1 first.' }

$accA = ($Prefix + 'a')            # deleted
$accB = ($Prefix + 'b')            # its voc is crippled
$upA  = $accA.ToUpper()
$upB  = $accB.ToUpper()

foreach ($n in @($accA, $accB)) {
    if (Get-LocalUser -Name $n -ErrorAction SilentlyContinue) { Refuse "$n already exists as a Windows account.  Use a fresh -Prefix." }
    if (Test-Path -LiteralPath (Join-Path $accts $n.ToUpper()))  { Refuse "$($n.ToUpper()) is still in the ACCOUNTS register.  Use a fresh -Prefix." }
}

$vocB      = ''
$vocBAside = ''
$movedVoc  = $false
$madeA     = $false
$madeB     = $false

try {
    Add-Type -AssemblyName System.Web

    # -----------------------------------------------------------------------
    Step 1 "Creating the two throwaway accounts $accA (to delete) and $accB (voc crippled)"

    # NONE: CREATE.ACCOUNT refuses (10082) unless told how the account is
    # reached, and the first run of this file, 15 Sep 20:42, omitted it - SD
    # asked "Say who may reach this account" and was fed the password.  Neither
    # account needs a route; the scan opens their voc from disk.  Password shape
    # copied from verify-delaccount (GeneratePassword + 'aA1!' meets complexity).
    # 19 Sep 26 - RELEASE_1.1 64: PROGRAMMER is REFUSED at create time now
    # (createa's keyword case, sysmsg 2018 - the whole command stops and no
    # account is made), so the access keyword is the whole of the line.
    $winPwA = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $accA NONE", $winPwA, $winPwA)
    if (-not (Test-Path -LiteralPath (Join-Path $accts $upA))) { Write-Host $out; Refuse "CREATE.ACCOUNT did not register $accA." }
    $madeA = $true
    Write-Host "   $accA created"

    $winPwB = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $accB NONE", $winPwB, $winPwB)
    if (-not (Test-Path -LiteralPath (Join-Path $accts $upB))) { Write-Host $out; Refuse "CREATE.ACCOUNT did not register $accB." }
    $madeB = $true
    Write-Host "   $accB created"

    # -----------------------------------------------------------------------
    Step 2 "Crippling $accB's voc so the cross-reference scan cannot open it"
    $dirB = Get-AccountDir $upB
    if (-not $dirB -or -not (Test-Path -LiteralPath $dirB -PathType Container)) {
        Refuse "$accB's account directory (from the register) is '$dirB', which is not on disk."
    }
    $vocB = Join-Path $dirB 'voc'
    if (-not (Test-Path -LiteralPath $vocB -PathType Container)) {
        Refuse "$accB has no voc directory at '$vocB' - nothing to cripple, so the ELSE could not be reached."
    }
    # CONTROL: the voc IS a real hashed file before we move it (has %0), so the
    # scan WOULD have opened it - which is what makes the ELSE the only reason it
    # cannot afterwards.
    if (-not (Test-Path -LiteralPath (Join-Path $vocB '%0'))) {
        Refuse "$accB's voc has no %0 bucket - it was already broken, so a later ELSE would prove nothing."
    }
    $vocBAside = $vocB + '.aside-for-44'
    Rename-Item -LiteralPath $vocB -NewName (Split-Path -Leaf $vocBAside) -ErrorAction Stop
    $movedVoc = $true
    Write-Host "   moved $vocB aside; the scan will now fail to open it"

    # -----------------------------------------------------------------------
    Step 3 "Deleting $accA - its cross-reference scan must hit $accB's missing voc"
    # DELETE.ACCOUNT asks one Y/N confirmation (delacc:271-286); the 'Y' is piped
    # after it.  The cross-ref scan runs BEFORE the confirmation, so if the ELSE
    # were absent the verb would abort here with ER_SFNF and never reach it.
    $out = Invoke-SD @("DELETE.ACCOUNT $upA", 'Y')
    Write-Host '   --- raw DELETE.ACCOUNT output ---'
    ($out -split "`r?`n") | ForEach-Object { Write-Host ('   | ' + $_) }
    Write-Host '   --- end raw output ---'

    # THE 10188 CHECK (K8).  The installed message with %1 replaced by B's name -
    # so the needle carries the crippled account's name and cannot be a refusal,
    # a "not found", or an echo of "DELETE.ACCOUNT ...".
    $msg10188 = Get-SysMsg 10188
    $needle   = $msg10188 -replace '%1', $upB
    Note "10188 printed, naming $upB (the un-scannable account)" $true (
        $out -match [regex]::Escape($needle))
    if ($out -notmatch [regex]::Escape($needle)) {
        Write-Host ("   looked for: " + $needle)
    }

    # DISQUALIFIER: the verb must NOT have aborted with the pre-fix error.  3001
    # / ER_SFNF / "opening file at line" would mean the ELSE did not take.
    Note 'no ER_SFNF / "opening file" abort' $false (
        ($out -match '3001') -or ($out -match 'opening file') -or ($out -match 'ER_SFNF'))

    # THE COMPLETION CHECK (K9).  A's ACCOUNTS record is gone - the deletion
    # finished despite the un-scannable voc, which is the whole point of the fix.
    Note "$upA was deleted (its ACCOUNTS record is gone)" $false (
        Test-Path -LiteralPath (Join-Path $accts $upA))
    if (-not (Test-Path -LiteralPath (Join-Path $accts $upA))) { $madeA = $false }
}
finally {
    # RESTORE B's voc FIRST, so B is a whole account again before it is deleted -
    # and even if a check above failed.
    if ($movedVoc -and (Test-Path -LiteralPath $vocBAside) -and -not (Test-Path -LiteralPath $vocB)) {
        try {
            Rename-Item -LiteralPath $vocBAside -NewName (Split-Path -Leaf $vocB) -ErrorAction Stop
            Write-Host "   $accB's voc restored"
        } catch {
            Write-Host ("   COULD NOT RESTORE $accB's voc - put it back by hand: " +
                        $vocBAside + ' -> ' + $vocB) -ForegroundColor Red
        }
    }

    Step 9 'Cleaning up the throwaway accounts'
    # Says what it removed rather than "removed both": the 20:42 run created
    # nothing and still printed that it had removed two accounts.
    $removed = @()
    if ($madeA -and (Test-Path -LiteralPath (Join-Path $accts $upA))) {
        $null = Invoke-SD @("DELETE.ACCOUNT $upA", 'Y'); $removed += "SD:$upA"
    }
    if ($madeB) { $null = Invoke-SD @("DELETE.ACCOUNT $upB", 'Y'); $removed += "SD:$upB" }
    foreach ($n in @($accA, $accB)) {
        if (Get-LocalUser -Name $n -ErrorAction SilentlyContinue) { Remove-LocalUser -Name $n -ErrorAction SilentlyContinue; $removed += "user:$n" }
        $prof = Join-Path $env:ProgramData ('SD\user_accounts\' + $n)
        if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force -ErrorAction SilentlyContinue; $removed += "dir:$n" }
        $grp = 'sdu_' + $n
        if (Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $grp -ErrorAction SilentlyContinue; $removed += "group:$grp" }
    }
    if ($removed.Count) { Write-Host ('   removed: ' + ($removed -join ', ')) }
    else                { Write-Host '   nothing to remove - no account had been created' }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host
$passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("{0} / {1} checks passed" -f $passed, $results.Count)
try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 }
exit 0
