# upgrade-gates.ps1 - carry an upgraded machine's OS-access grants from the person's os.users record to the ACCOUNT's register
# fields.  RELEASE_1.1 170 (Linux S.63, 215ce2c; owner's answer of 23 Oct 2026: the grant is the account's and os.users is retired).
# Runs at UPGRADE only; the installer calls it from sd.iss beside upgrade-nocase.ps1.
#
# It drives  sd -internal RUN gpl.bp upgrade_gates , which walks the account register once and, for every USER account (an sdu_
# group), copies what sdsys\os.users says about that Windows user: field 1 'yes' to ACC$SH and field 2 'yes' to ACC$OS.EXEC, 'no'
# for anything else and for a user with no record.  Without it an upgrade would leave both fields blank, a blank reads as denied,
# and everybody who had a shell or OS.EXECUTE the day before would lose it.  ONCE MEANS ONCE: the walk leaves sdsys\$gates.done.
#
# ***THE FULL REPORT IS WRITTEN TO C:\ProgramData\SD\upgrade-gates.log*** so an administrator can read, after a hidden install,
# what was set for which account.
#
# Exit 0 complete, 1 a real failure (the program did not reach COMPLETE), 3 SD would not start.

[CmdletBinding()]
param(
    [string] $AppDir = '',
    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $DataDir 'upgrade-gates.log'

function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

# The verdict, read from the program's own output and nothing else.  Kept a pure function of the text so that
# test-upgradegates-units.ps1 can drive it with no SD.  UPGRADE_GATES prints "COMPLETE" on a line of its own when, and only
# when, the register holds what it should, and "OS-access gates: set for N existing account(s) from os.users; K already right;
# F failed" before it; "... nothing changed." on a repeat.  A failure line never carries COMPLETE.
function Get-GatesVerdict([string] $Text) {
    $complete = $Text -match '(?m)^\s*COMPLETE\s*$'
    $set = -1; $kept = -1; $failed = -1
    $m = [regex]::Match($Text, 'OS-access gates: set for (\d+) existing account\(s\) from os\.users; (\d+) already right; (\d+) failed')
    if ($m.Success) { $set = [int]$m.Groups[1].Value; $kept = [int]$m.Groups[2].Value; $failed = [int]$m.Groups[3].Value }
    $again = $Text -match 'were set for the existing accounts by an earlier install; nothing changed'
    $refused = ($Text -match 'Cannot open the account register') -or ($Text -match 'were NOT all set') -or ($Text -match 'Cannot write the register record')
    return [pscustomobject]@{
        Complete = $complete
        Set = $set
        Kept = $kept
        Failed = $failed
        Repeat = $again
        Refused = $refused
    }
}

# The same decision for the SECOND program this step runs, UPGRADE_EDITGATES (S.64, Linux d7cda81): it sets the three edit gates
# (voc.edit, bp.edit, dict.edit) to 'yes' once for every USER account whose field is blank, because the accounts that exist at an
# upgrade have always been able to change their VOC, programs and dictionaries.  It prints "Edit gates: switched on for N existing
# account(s); K already had all three set; F failed" and COMPLETE, or "... by an earlier install; nothing changed".
function Get-EditGatesVerdict([string] $Text) {
    $complete = $Text -match '(?m)^\s*COMPLETE\s*$'
    $set = -1; $kept = -1; $failed = -1
    $m = [regex]::Match($Text, 'Edit gates: switched on for (\d+) existing account\(s\); (\d+) already had all three set; (\d+) failed')
    if ($m.Success) { $set = [int]$m.Groups[1].Value; $kept = [int]$m.Groups[2].Value; $failed = [int]$m.Groups[3].Value }
    $again = $Text -match 'The edit gates were set for the existing accounts by an earlier install; nothing changed'
    $refused = ($Text -match 'Cannot open the account register') -or ($Text -match 'were NOT all set') -or ($Text -match 'Cannot write the register record')
    return [pscustomobject]@{
        Complete = $complete
        Set = $set
        Kept = $kept
        Failed = $failed
        Repeat = $again
        Refused = $refused
    }
}

# The units test dot-sources this file for Get-GatesVerdict with $SkipRun set, so nothing below - including the sd.exe check -
# runs under test.
if ($SkipRun) { return }

if (-not $AppDir) { $AppDir = $PSScriptRoot }
Say ("=== upgrade-gates {0}  AppDir={1}  DataDir={2}" -f (Get-Date -Format 's'), $AppDir, $DataDir)
if (-not $AppDir) { Say 'upgrade-gates: no -AppDir and PSScriptRoot empty; cannot find sd.exe'; exit 1 }
$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) { Say "upgrade-gates: no sd.exe at $sd"; exit 1 }

. (Join-Path $PSScriptRoot 'internal-marker.ps1')
function Invoke-Sd {
    param([string[]] $SdArgs, [int] $TimeoutMs = 300000)
    $out = Join-Path $env:TEMP ("sd-gates-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-gates-err-$PID.txt")
    # LOGIN admits an "sd -internal" session only against a one-shot marker, which it deletes on admission; this writes one
    # immediately before the session and removes it afterwards in case sd never consumed it (RELEASE_1.1 82).
    $marked = $false
    if (@($SdArgs).Count -gt 0 -and $SdArgs[0] -ieq '-internal') {
        $marked = Set-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') -Writer 'upgrade-gates'
    }
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru `
                       -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    $exited = $p.WaitForExit($TimeoutMs)
    if ($marked) { $null = Remove-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') }
    $text = ''
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) { $text += (Get-Content $f -Raw); Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    if (-not $exited) { return [pscustomobject]@{ Code = 1; Text = "sd $SdArgs did not finish in $($TimeoutMs/1000)s" } }
    return [pscustomobject]@{ Code = $p.ExitCode; Text = "$text".Trim() }
}
function Test-SdRunning { return $null -ne ((Get-Process sdwind -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'sdwind' -or -not ($_.Path -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $_.Path) 'sd-solo.exe'))) })) }
function Wait-SdRunning {
    param([int] $TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) { if (Test-SdRunning) { return $true }; Start-Sleep -Milliseconds 500 }
    return (Test-SdRunning)
}

# THE NULL CASE, REFUSED BEFORE ANYTHING STARTS: no register, nothing to carry over, and "complete" would be a claim about a
# question that was never asked.
$acctDir = Join-Path $DataDir 'sdsys\accounts'
if (-not (Test-Path -LiteralPath $acctDir)) {
    Say "upgrade-gates: no account register at $acctDir - nothing could be walked."
    exit 1
}

$weStartedIt = $false
$result = 1
try {
    if (-not (Test-SdRunning)) {
        $r = Invoke-Sd @('-start')
        if (-not (Wait-SdRunning)) {
            Say 'upgrade-gates: SD would not start, so no account was changed'
            Say ("  sd -start exited {0}: {1}" -f $r.Code, $r.Text)
            $result = 3
            throw 'no server'
        }
        $weStartedIt = $true
    }

    Say 'upgrade-gates: sd -internal RUN gpl.bp upgrade_gates NO.PAGE'
    $w = Invoke-Sd @('-internal', 'RUN', 'gpl.bp', 'UPGRADE_GATES', 'NO.PAGE')
    Say ("  exit {0}" -f $w.Code)
    Say '  --- report ---'
    foreach ($l in ("$($w.Text)" -split "`r?`n")) { if ($l.Trim()) { Say ("  | " + $l) } }
    Say '  --- end ---'

    $v = Get-GatesVerdict $w.Text
    Say ("upgrade-gates: complete={0} set={1} kept={2} failed={3} repeat={4} refused={5}" -f
         $v.Complete, $v.Set, $v.Kept, $v.Failed, $v.Repeat, $v.Refused)

    if (-not $v.Complete) {
        Say 'upgrade-gates: UPGRADE_GATES did not reach COMPLETE'
        throw 'incomplete'
    }
    if ($v.Refused -or ($v.Failed -gt 0)) {
        Say 'upgrade-gates: one or more accounts could not be written (see the report)'
        throw 'write trouble'
    }
    if ((-not $v.Repeat) -and ($v.Set -lt 0)) {
        Say 'upgrade-gates: COMPLETE with no count of accounts - the program printed neither of its two positive lines'
        throw 'no count'
    }
    # --- the edit gates, second program, same standard -------------------------------------------------------------------------
    Say 'upgrade-gates: sd -internal RUN gpl.bp upgrade_editgates NO.PAGE'
    $e = Invoke-Sd @('-internal', 'RUN', 'gpl.bp', 'UPGRADE_EDITGATES', 'NO.PAGE')
    Say ("  exit {0}" -f $e.Code)
    Say '  --- report ---'
    foreach ($l in ("$($e.Text)" -split "`r?`n")) { if ($l.Trim()) { Say ("  | " + $l) } }
    Say '  --- end ---'

    $ev = Get-EditGatesVerdict $e.Text
    Say ("upgrade-gates: edit gates complete={0} set={1} kept={2} failed={3} repeat={4} refused={5}" -f
         $ev.Complete, $ev.Set, $ev.Kept, $ev.Failed, $ev.Repeat, $ev.Refused)
    if (-not $ev.Complete) {
        Say 'upgrade-gates: UPGRADE_EDITGATES did not reach COMPLETE'
        throw 'incomplete (edit gates)'
    }
    if ($ev.Refused -or ($ev.Failed -gt 0)) {
        Say 'upgrade-gates: one or more accounts could not be written for the edit gates (see the report)'
        throw 'write trouble (edit gates)'
    }
    if ((-not $ev.Repeat) -and ($ev.Set -lt 0)) {
        Say 'upgrade-gates: the edit gates reached COMPLETE with no count of accounts'
        throw 'no count (edit gates)'
    }

    Say 'upgrade-gates: DONE'
    $result = 0
}
catch {
    if ($result -ne 3) { $result = 1 }
    Say "upgrade-gates: FAILED - $($_.Exception.Message)"
}
finally {
    if ($weStartedIt) { $null = Invoke-Sd @('-stop') }
}

exit $result
