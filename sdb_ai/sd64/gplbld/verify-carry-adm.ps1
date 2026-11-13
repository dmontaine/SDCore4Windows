<#
.SYNOPSIS
    The carried Linux sandbox suites that need an ADMINISTRATOR session, adm(), run against the INSTALLED SD with SDSYS
    as the administrator (RELEASE_1.1 254).  ***AN ELEVATED POWERSHELL, AND SDSYS SIGNED IN.***

.DESCRIPTION
    Linux's suites gates, sdaccts, shared, editgates, runin, ospath, prof, resetall, stmt-q3 (and classinit, nameindex,
    q4, q5, restricted, which load it) and net make administrator sessions with SDTEST_ADMIN=1 - adm() - and fixture
    accounts (a directory, a VOC from NEWVOC, a register record written by hand).  On Windows the only SD administrator is
    the OS account SDSYS (RELEASE_1.1 64), reached through the SDSYS seat (sdsys-seat.ps1).  verify-carry.ps1 cannot run
    them (an ordinary prompt; they are NOT RUN in verify-carry-known.psd1, and the launcher refuses them, exit 2).  This
    script is their entry:

      * the BOX is C:\ProgramData\SD-verify\carry-adm-<Run>, one per -Run token (a spent token is refused: PRE_RELEASE 54,
        a fixed name passes once and fails every later run), holding
          sys            a JUNCTION to the installed SDSYS, so the suites' register records and probes land where SD looks;
          user_accounts  where the suites build their fixture accounts (SDSYS is granted Modify on the box, because the
                         seat's internal session makes the account directories);
      * verify-carry-run.py runs each suite in ADM MODE (SD_CARRY_ADM=1): every administrator session goes to the seat
        through verify-carry-seat.ps1, the installed SDSYS is guarded (no file the install owns is written or deleted
        through Python) and what the suite made under it is removed and named at the end.  The ordinary sessions are the
        caller's own, elevated token (an elevated session of any account but SDSYS is not an SD administrator).

    THE FIXTURE ACCOUNT NAMES ARE THE SUITES' OWN (zzoff, zzon, zzaa ...), NOT DERIVED FROM -Run.  The rows and the BASIC
    probes name them, so renaming would edit the suites; they make no Windows user (only a register record and a directory
    in this run's box), which is what made a fixed name fail before; and a name left by an interrupted run is refused here
    before anything starts (-Sweep removes it).  -Run derives the box and is printed with every suite.

    The rows' verdicts are read as verify-carry.ps1 reads them: every [PASS]/[FAIL] line, the Rows table of
    verify-carry-known.psd1 for rows that are a Linux mechanism, and COULD NOT RUN for a suite that exited 2 or printed no
    row.  A suite not carried yet (no verify-carry-<name>.py) is NOT CARRIED, and a run with any is never the whole set.

.PARAMETER Run
    A token nobody has used, lower-case letters and digits.  Required.

.PARAMETER Suite
    Suite names (gates, stmt-q3 ...), comma separated or a list.  Default: every suite the launcher lists (--adm-suites).

.PARAMETER Sweep
    Remove zz-named entries left in the installed SDSYS (accounts, bp, bp.out, gcat) by an interrupted run, naming each,
    before the run starts.  Without it such a leftover refuses the run.

.PARAMETER Keep
    Leave the box (its junction is still removed first).

.OUTPUTS
    Exit 0 every suite run passed, 1 a row failed, 2 a suite could not run or the run could not start.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\verify-carry-adm.ps1 -Run a1 -Suite ospath,prof
#>

[CmdletBinding()]
param(
    [string]$Run = '',
    [string[]]$Suite = @(),
    [switch]$Sweep,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Launcher = Join-Path $Gplbld 'verify-carry-run.py'
$Bridge   = Join-Path $Gplbld 'verify-carry-seat.ps1'
$SdsysDir = Join-Path $env:ProgramData 'SD\sdsys'
$GplSrc   = Join-Path (Split-Path -Parent $Gplbld) 'sdsys\gpl.bp'
$Watched  = @('accounts', 'bp', 'bp.out', 'gcat')

$whole = [System.Diagnostics.Stopwatch]::StartNew()
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$carryLog = Join-Path $logDir ('verify-carry-adm-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { $null = Start-Transcript -Path $carryLog -Force } catch { $carryLog = '(no log: ' + $_.Exception.Message + ')' }

function Say([string]$m) { Write-Host $m }
function Bail([int]$code, [string]$why) {
    Say ''
    if ($code -eq 0) { Say "verify-carry-adm: PASSED - $why" }
    elseif ($code -eq 1) { Say "verify-carry-adm: FAILED - $why" }
    else { Say "verify-carry-adm: COULD NOT RUN - $why" }
    Say ("verify-carry-adm: took {0:N0} s; log {1}" -f $whole.Elapsed.TotalSeconds, $carryLog)
    try { $null = Stop-Transcript } catch { }
    exit $code
}

# zz-named entries in the watched SDSYS directories: what an interrupted run leaves behind.
function Get-ZzLeftovers {
    $found = @()
    foreach ($d in $Watched) {
        $p = Join-Path $SdsysDir $d
        if (Test-Path -LiteralPath $p) {
            $found += @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^\$?zz' } | ForEach-Object { $_.FullName })
        }
    }
    return ,$found
}

# --- preconditions --------------------------------------------------------------------------------
Say "verify-carry-adm: run       '$Run'"
Say "verify-carry-adm: suites    $(if ($Suite.Count) { $Suite -join ',' } else { '(all the launcher lists)' })"
Say "verify-carry-adm: launcher  $Launcher"
Say "verify-carry-adm: bridge    $Bridge"
Say "verify-carry-adm: sdsys     $SdsysDir"
Say ''

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Bail 2 'NOT ELEVATED - the SDSYS seat registers a task for another account, which needs an elevated PowerShell.  Nothing was run.'
}
if ($Run -notmatch '^[a-z0-9]+$') { Bail 2 "-Run is '$Run': give a token nobody has used, lower-case letters and digits." }
foreach ($f in @($Launcher, $Bridge, (Join-Path $Gplbld 'sdsys-seat.ps1'))) {
    if (-not (Test-Path -LiteralPath $f)) { Bail 2 "$f is missing." }
}
if (-not (Test-Path -LiteralPath (Join-Path $SdsysDir 'accounts'))) { Bail 2 "$SdsysDir has no accounts register - SD does not look installed." }
$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path -LiteralPath $sdExe)) { Bail 2 "no sd.exe at $sdExe - SD does not look installed." }
if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) { Bail 2 'python is not on PATH.' }

$admAll = @(& python -X utf8 $Launcher --adm-suites 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if ($admAll.Count -lt 5) { Bail 2 ("the launcher listed {0} adm suite(s): {1}" -f $admAll.Count, ($admAll -join ' ')) }
$names = @($Suite | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($names.Count -eq 0) { $names = $admAll }
foreach ($n in $names) {
    if ($admAll -notcontains $n) { Bail 2 "'$n' is not a suite the launcher runs in adm mode.  Known: $($admAll -join ', ')" }
}

# The register group of the fixture accounts: the caller's own account's (field 3), which LOGIN admits the caller to.
$me = $env:USERNAME
$recFile = Join-Path (Join-Path $SdsysDir 'accounts') $me
if (-not (Test-Path -LiteralPath $recFile)) { Bail 2 "no register record for $me at $recFile - the caller needs an SD account of its own." }
$rec = @(Get-Content -LiteralPath $recFile)
$group = $(if ($rec.Count -ge 3) { $rec[2].Trim() } else { '' })
if ($group -notmatch '^[A-Za-z0-9_.-]+$') { Bail 2 "the register group of $me is '$group' - not a group name." }
$members = @()
try { $members = @(Get-LocalGroupMember -Group $group -ErrorAction Stop | ForEach-Object { ($_.Name -split '\\')[-1] }) } catch { }
Say "verify-carry-adm: group     $group (members: $($members -join ', '))"
if ($members -notcontains $me) { Bail 2 "$me is not a member of $group, so the fixture accounts would not admit the ordinary sessions." }

# --- the install must match source ---------------------------------------------------------------
Say '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }

# --- the seat, through its internal door ---------------------------------------------------------
. (Join-Path $Gplbld 'sdsys-seat.ps1')
Assert-SdSeat -Label 'verify-carry-adm' -Internal

# --- what an interrupted run left ----------------------------------------------------------------
$left = Get-ZzLeftovers
Say ("verify-carry-adm: zz-named entries already in SDSYS: {0}" -f $left.Count)
foreach ($p in $left) { Say "    $p" }
if ($left.Count -gt 0) {
    if (-not $Sweep) { Bail 2 'zz-named entries are already in the installed SDSYS (an interrupted run?).  Read them above; -Sweep removes them.' }
    foreach ($p in $left) {
        try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop; Say "    swept $p" }
        catch { Say ("    COULD NOT SWEEP $p : " + $_.Exception.Message) }
    }
    $left = Get-ZzLeftovers
    if ($left.Count -gt 0) { Bail 2 "$($left.Count) zz-named entr(ies) survived the sweep." }
}

# --- the box ---------------------------------------------------------------------------------------
$box = Join-Path $env:ProgramData ('SD-verify\carry-adm-' + $Run)
if (Test-Path -LiteralPath $box) { Bail 2 "$box exists: the -Run token '$Run' is spent.  Use a new one." }
$null = New-Item -ItemType Directory -Path $box -Force
$null = New-Item -ItemType Directory -Path (Join-Path $box 'user_accounts') -Force
$acl = Get-Acl -LiteralPath $box
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('SDSYS', 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
Set-Acl -LiteralPath $box -AclObject $acl
Say "verify-carry-adm: box       $box"

$Known = @{}
$KnownFile = Join-Path $Gplbld 'verify-carry-known.psd1'
if (Test-Path -LiteralPath $KnownFile) {
    $kd = Import-PowerShellDataFile -LiteralPath $KnownFile
    if ($kd.ContainsKey('Rows')) { $Known = $kd['Rows'] }
}

$env:SD_CARRY_ADM    = '1'
$env:SD_CARRY_SDSYS  = $SdsysDir
$env:SD_CARRY_GROUP  = $group
$env:SD_CARRY_SEAT   = $Bridge
$env:SD_CARRY_GPLSRC = $GplSrc
$env:SD_CARRY_RUN    = $Run

$rows = @()
$worst = 0
$noJunction = $false
try {
    # The junction is made INSIDE the try, so the finally below removes it whatever happens next.
    $null = New-Item -ItemType Junction -Path (Join-Path $box 'sys') -Target $SdsysDir
    Say "verify-carry-adm: sys       -> $SdsysDir  (a junction)"
    Say ''
    if (-not (Test-Path -LiteralPath (Join-Path $box 'sys\accounts'))) { $noJunction = $true; $names = @() }
    foreach ($n in $names) {
        $file = Join-Path $Gplbld "verify-carry-$n.py"
        Say "=== $n (run $Run) ================================================="
        if (-not (Test-Path -LiteralPath $file)) {
            Say "  [N/A ] not carried yet: $file is absent"
            $rows += [pscustomobject]@{ Suite = $n; Rows = 0; Pass = 0; Fail = 0; NA = 0; Exit = '-'; Secs = 0; Verdict = 'NOT CARRIED' }
            Say ''
            continue
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $pass = 0; $fail = 0; $na = 0
        $ErrorActionPreference = 'Continue'
        $lines = @(& python -X utf8 $Launcher $file $box 2>&1 | ForEach-Object { "$_" })
        $rc = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        foreach ($l in $lines) {
            $mark = $false
            if ($l -match '^\s*\[FAIL\]\s*(.*)$') {
                $label = $Matches[1]
                $why = $null
                if ($Known.ContainsKey($n)) {
                    foreach ($k in $Known[$n].Keys) { if ($label.StartsWith($k)) { $why = $Known[$n][$k] } }
                }
                if ($why) { $na++; Say ("  [N/A ] " + $label + "   (" + $why + ")"); $mark = $true }
                else { $fail++ }
            } elseif ($l -match '^\s*\[PASS\]') { $pass++ }
            if (-not $mark) { Say $l }
        }
        $sw.Stop()
        if ($null -eq $rc -or $rc -lt 0 -or $rc -ge 2 -or ($pass + $fail + $na) -eq 0 -or ($rc -eq 0 -and $pass -eq 0)) { $verdict = 'COULD NOT RUN'; $worst = [Math]::Max($worst, 2) }
        elseif ($fail -gt 0 -or ($rc -eq 1 -and $na -eq 0)) { $verdict = 'FAIL'; $worst = [Math]::Max($worst, 1) }
        else { $verdict = 'PASS' }
        $rows += [pscustomobject]@{ Suite = $n; Rows = ($pass + $fail + $na); Pass = $pass; Fail = $fail; NA = $na; Exit = $rc; Secs = [int]$sw.Elapsed.TotalSeconds; Verdict = $verdict }
        Say ''
    }
} finally {
    foreach ($v in @('SD_CARRY_ADM', 'SD_CARRY_SDSYS', 'SD_CARRY_GROUP', 'SD_CARRY_SEAT', 'SD_CARRY_GPLSRC', 'SD_CARRY_RUN')) {
        Remove-Item -LiteralPath ("Env:" + $v) -ErrorAction SilentlyContinue
    }
    # Remove the junction ITSELF first, and the rest of the box only once it is gone: a recursive Remove-Item through a live
    # junction would delete the installed SDSYS it points at.
    $sysLink = Join-Path $box 'sys'
    if (Test-Path -LiteralPath $sysLink) { [System.IO.Directory]::Delete($sysLink, $false) }
    if (-not $Keep) {
        if (-not (Test-Path -LiteralPath $sysLink)) {
            Remove-Item -LiteralPath $box -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "WARNING: the junction $sysLink is still there; the box was left alone." -ForegroundColor Red
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $SdsysDir 'accounts'))) {
        Write-Host "WARNING: $SdsysDir\accounts is missing after cleanup" -ForegroundColor Red
    }
}

if ($noJunction) { Bail 2 'the junction did not show the SDSYS accounts register; nothing was run.' }
$left = Get-ZzLeftovers
if ($left.Count -gt 0) {
    Say ("WARNING: {0} zz-named entr(ies) are still in SDSYS after the run (the next run refuses until -Sweep):" -f $left.Count)
    foreach ($p in $left) { Say "    $p" }
}

Say '--- summary --------------------------------------------------------'
$rows | Format-Table Suite, Rows, Pass, Fail, NA, Exit, Secs, Verdict -AutoSize | Out-String -Width 200 | ForEach-Object { Say $_.TrimEnd() }
$totR = ($rows | Measure-Object Rows -Sum).Sum
$totF = ($rows | Measure-Object Fail -Sum).Sum
$totN = ($rows | Measure-Object NA -Sum).Sum
$nRun = @($rows | Where-Object { $_.Verdict -ne 'NOT CARRIED' }).Count
$nSkip = $rows.Count - $nRun
Say ("verify-carry-adm: run {0}: {1} suite(s) run, {2} NOT CARRIED, {3} row(s), {4} failed, {5} N/A on Windows" -f $Run, $nRun, $nSkip, $totR, $totF, $totN)
if ($nRun -eq 0) { Bail 2 'no suite ran: every suite named is not carried yet, so nothing was measured.' }
if ($worst -eq 2) { Bail 2 'at least one suite could not run (or printed no PASS row): nothing may be concluded from it.' }
if ($worst -eq 1) { Bail 1 "$totF row(s) failed." }
if ($nSkip -gt 0) { Bail 0 "$totR row(s) in $nRun suite(s); $nSkip suite(s) NOT CARRIED, so this is not the whole adm set." }
Bail 0 "$totR row(s) in $nRun suite(s)."
