# verify-registersweep.ps1 - the register goes dirty, the service start cleans
# it, and this watches the whole loop happen
#
#   powershell -File verify-registersweep.ps1     ELEVATED PowerShell
#
# Exit 0 the loop worked, 1 it did not, 2 the check could not be run.
#
# PRE_RELEASE_FIXES.md 93 and 65.  Owner's instruction, 3 Sep 2026, after the
# b107 witness: put verify-register at the end of VerifyInstall2 as well.
#
# ***WHY IT IS NOT verify-register RUN A SECOND TIME.***  It cannot be.
# verify-tierapi is the LAST step of VerifyInstall2 and it leaves its register
# records BEHIND ON PURPOSE - "removing the register records here would hide a
# CREATE.ACCOUNT that had half failed" - so a plain verify-register placed after
# it would find three dead records and go red ON EVERY RUN.  A guard that is
# always red is the one thing this repository's own record says teaches people
# to distrust guards, so the owner ruled sweep-then-verify.
#
# WHAT IT ACTUALLY PROVES, WHICH IS MORE THAN EITHER HALF ALONE:
#
#   1. the suite really does leave dead records          (measured, by name)
#   2. an SD service start runs reconcile-accounts.ps1   (sdsvc.log)
#   3. it removes exactly those records                  (by name, before/after)
#   4. and leaves the valid ones alone                   (by name)
#   5. and the register is consistent afterwards         (verify-register, 0)
#
# THE PLACEMENT IS THE POINT.  verify-register in VerifyInstall1 runs FIRST, so
# it can only ever see what a PREVIOUS run left uncleaned - which is real value
# (it would have caught the b100 state, 14 dead records in 15) but is not this.
# This one runs last, against residue that is seconds old.
#
# ***A RESTART, NOT A DIRECT CALL, AND THAT IS DELIBERATE.***  The sweep is
# written to run BEFORE "sd -start", because both registers are directory files
# and removing records under a running SD would pull them out from under an open
# cursor.  Calling reconcile-accounts.ps1 by hand here would test the script but
# not the thing that matters - that a service start runs it - and would do so in
# the one state its own header says to avoid.  VerifyInstall2 is elevated and
# this runner already restarts SD more than once, so this costs nothing new.
#
# NOT SHIPPED - must be on assert-current.ps1's $neverShipped list, added in the
# same commit that creates this file.
#
# START-HISTORY:
# 03 Sep 26 Windows port - written on the owner's instruction after b107.
# END-HISTORY

param(
    [string] $DataDir = '',

    # For a unit test only: skip the assert-current call.
    [switch] $NoCurrentCheck,

    # How long to wait for SD to come back after the restart.
    [int] $StartWaitSeconds = 60
)

$ErrorActionPreference = 'Continue'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path

$pass = 0
$fail = 0

function Note([bool]$ok, [string]$what, [string]$detail = '') {
    if ($ok) {
        $script:pass++
        Write-Host ("  [PASS] " + $what)
    } else {
        $script:fail++
        Write-Host ("  [FAIL] " + $what + $(if ($detail -ne '') { "  <- " + $detail } else { '' }))
    }
}

function Stop-Now([string]$why) {
    Write-Host ''
    Write-Host ('verify-registersweep: CANNOT RUN - ' + $why)
    Write-Host 'verify-registersweep: nothing was measured and nothing was changed.'
    exit 2
}

Write-Host ''
Write-Host '=== verify-registersweep: a service start clears the records the suite left ==='

# ELEVATION IS REQUIRED, and unlike most of this tree that is not about what is
# measured - restarting a service needs the token.  Said plainly rather than
# failing later with a confusing access error.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-Now 'this needs an ELEVATED PowerShell - it restarts the SD service.'
}

if (-not $NoCurrentCheck) {
    & (Join-Path $Gplbld 'assert-current.ps1') | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-Now 'assert-current refuses - the install does not match source.' }
}

$progData = $env:ProgramData
if ([string]::IsNullOrEmpty($progData)) { $progData = 'C:\ProgramData' }
if ($DataDir -eq '') { $DataDir = Join-Path $progData 'SD' }

$accountsDir = Join-Path $DataDir 'sdsys\accounts'
$osUsersDir  = Join-Path $DataDir 'sdsys\os.users'
$sweepLog    = Join-Path $DataDir 'reconcile-accounts.log'
$svcLog      = Join-Path $DataDir 'sdsvc.log'

Write-Host ('  data tree  : ' + $DataDir)
Write-Host ('  sweep log  : ' + $sweepLog)

# --- the rule, borrowed rather than reimplemented ---------------------------

$sweep = Join-Path $Gplbld 'reconcile-accounts.ps1'
if (-not (Test-Path -LiteralPath $sweep)) { Stop-Now ('no sweep at ' + $sweep) }

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sweep, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { Stop-Now ($sweep + ' does not parse') }
$funcs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
foreach ($w in @('Norm', 'Get-RecordLogin', 'Get-ReconcileRefusal', 'Get-Verdict', 'Resolve-WindowsAccount')) {
    $d = @($funcs | Where-Object { $_.Name -eq $w })
    # REFUSE THE NULL CASE: a file whose functions the parser cannot find parses
    # with zero errors.
    if ($d.Count -ne 1) { Stop-Now ($sweep + ' defines ' + $d.Count + ' function(s) called ' + $w) }
    . ([scriptblock]::Create($d[0].Extent.Text))
}

$localUsers = $null
try { $localUsers = @(Get-LocalUser -ErrorAction Stop) } catch { Stop-Now ('cannot enumerate local accounts - ' + $_.Exception.Message) }
if ($localUsers.Count -eq 0) { Stop-Now 'the local account enumeration returned ZERO accounts, which no Windows machine has.' }
$localNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($u in $localUsers) { [void]$localNames.Add($u.Name) }
Write-Host ('  control    : ' + $localNames.Count + ' local Windows account(s) enumerated')

# THE ACCOUNT ROOT, READ THE WAY THE SWEEP READS IT.  Passing '' here is not a
# harmless shortcut: the shared rule answers "the account root could not be
# resolved" for every accounts record, which is a refusal, so nothing is ever
# classified dead and the check goes quietly inert.  Measured 3 Sep 2026.
$AccountsRoot = Join-Path $DataDir 'user_accounts'
$conf = Join-Path $DataDir 'sd.conf'
if (Test-Path -LiteralPath $conf) {
    try {
        foreach ($l in @(Get-Content -LiteralPath $conf -ErrorAction Stop)) {
            $t = $l.Trim()
            if ($t.StartsWith('#')) { continue }
            if ($t -match '^(?i)USRDIR\s*=\s*(.+)$') {
                $v = $Matches[1].Trim()
                if ($v -ne '') { $AccountsRoot = [Environment]::ExpandEnvironmentVariables($v) }
            }
        }
    } catch { }
}
$script:rootNorm = Norm $AccountsRoot
Write-Host ('  root       : ' + $script:rootNorm)
if ($script:rootNorm -eq '') { Stop-Now 'the account root could not be resolved, so every record would score refused' }

# --- classify the register as it stands NOW --------------------------------

function Read-Dir([string]$d) {
    if (-not (Test-Path -LiteralPath $d)) { return @{ ok = $true; items = @() } }
    try { return @{ ok = $true; items = @(Get-ChildItem -LiteralPath $d -File -ErrorAction Stop) } }
    catch { return @{ ok = $false; items = @() } }
}

# ***THREE BUCKETS, NOT TWO, AND THE ACCOUNT ROOT IS RESOLVED RATHER THAN
# PASSED EMPTY.***  Both corrections were forced by the first real run, 3 Sep
# 2026, and the fixture found them rather than a suite:
#
#   * an empty $rootNorm makes the shared rule answer "the account root could
#     not be resolved" for EVERY accounts record, which is a refusal - so
#     nothing was ever classified dead and the whole check was inert.
#   * 'refused' was being lumped in with valid and exempt.  A refused record is
#     a DEAD record the sweep declined to act on; it is not alive.  Counting it
#     as alive made "every valid record survived" fail when the sweep correctly
#     removed the planted one.
#
# So: 'act' must go, 'valid'/'exempt' must stay, and 'refused' is reported and
# expected to remain - the sweep leaves those deliberately, and they still make
# the register inconsistent, which the final verify-register child scores.

function Classify() {
    $dead    = @()
    $refused = @()
    $ok      = @()

    $r = Read-Dir $accountsDir
    if (-not $r.ok) { return $null }
    foreach ($f in @($r.items)) {
        $rec = @()
        try { $rec = @(Get-Content -LiteralPath $f.FullName -ErrorAction Stop) } catch { continue }
        $path  = ''; $group = ''
        if ($rec.Count -ge 1) { $path  = ([string]$rec[0]).Trim() }
        if ($rec.Count -ge 3) { $group = ([string]$rec[2]).Trim() }
        $login = Get-RecordLogin $group
        $look  = Resolve-WindowsAccount $login $localNames
        $v = Get-Verdict (Get-ReconcileRefusal 'accounts' $f.Name $group $path $script:rootNorm $login $look.live $look.ok)
        if     ($v -eq 'act')     { $dead    += ('accounts/' + $f.Name) }
        elseif ($v -eq 'refused') { $refused += ('accounts/' + $f.Name) }
        else                      { $ok      += ('accounts/' + $f.Name) }
    }

    $r = Read-Dir $osUsersDir
    if (-not $r.ok) { return $null }
    foreach ($f in @($r.items)) {
        $look = Resolve-WindowsAccount $f.Name $localNames
        $v = Get-Verdict (Get-ReconcileRefusal 'os.users' $f.Name '' '' $script:rootNorm $f.Name $look.live $look.ok)
        if     ($v -eq 'act')     { $dead    += ('os.users/' + $f.Name) }
        elseif ($v -eq 'refused') { $refused += ('os.users/' + $f.Name) }
        else                      { $ok      += ('os.users/' + $f.Name) }
    }

    return @{ dead = $dead; refused = $refused; ok = $ok }
}

$before = Classify
if ($null -eq $before) { Stop-Now 'the register could not be read' }

Write-Host ''
Write-Host '--- before the restart'
Write-Host ('  ' + (@($before.dead)).Count + ' dead, the sweep should take these : ' + $(if ((@($before.dead)).Count -eq 0) { '(none)' } else { ($before.dead -join ', ') }))
Write-Host ('  ' + (@($before.refused)).Count + ' refused, the sweep will LEAVE these: ' + $(if ((@($before.refused)).Count -eq 0) { '(none)' } else { ($before.refused -join ', ') }))
Write-Host ('  ' + (@($before.ok)).Count + ' valid or exempt, must survive        : ' + (($before.ok) -join ', '))

# ***THE NULL CASE, SAID OUT LOUD RATHER THAN SCORED.***  If nothing is dirty
# there is nothing for the sweep to remove, and a PASS here would mean "the
# sweep works" on the strength of a run in which it did nothing.  That is not a
# failure either - a clean register is a legitimate state - so it is reported,
# the removal rows are skipped by name, and the consistency half still runs.
$provesRemoval = ((@($before.dead)).Count -gt 0)
if (-not $provesRemoval) {
    Write-Host ''
    Write-Host '  NOTE: the register is already clean, so THIS RUN CANNOT PROVE THE SWEEP REMOVES'
    Write-Host '  ANYTHING.  The removal rows below are skipped by name rather than passed.  In'
    Write-Host '  VerifyInstall2 this is unexpected: verify-tierapi runs immediately before and'
    Write-Host '  leaves its records deliberately.'
}

# --- restart, which is what runs the sweep ---------------------------------

$svcLogBefore = 0
if (Test-Path -LiteralPath $svcLog) { $svcLogBefore = (@(Get-Content -LiteralPath $svcLog)).Count }
$sweepLogBefore = 0
if (Test-Path -LiteralPath $sweepLog) { $sweepLogBefore = (@(Get-Content -LiteralPath $sweepLog)).Count }

Write-Host ''
Write-Host '--- restarting the SD service (this is what runs the sweep)'
try {
    Restart-Service -Name 'SD' -Force -ErrorAction Stop
} catch {
    Stop-Now ('the SD service would not restart - ' + $_.Exception.Message)
}

$up = $false
for ($i = 0; $i -lt $StartWaitSeconds; $i++) {
    Start-Sleep -Seconds 1
    $svc = Get-Service -Name 'SD' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running' -and
        @(Get-Process -Name 'sdwind' -ErrorAction SilentlyContinue).Count -gt 0) { $up = $true; break }
}
Note $up ('SD came back up within ' + $StartWaitSeconds + 's')
if (-not $up) { Stop-Now 'SD did not come back, so nothing below would mean anything.' }

# --- what the service and the sweep said about it --------------------------

$svcNew = @()
if (Test-Path -LiteralPath $svcLog) {
    $all = @(Get-Content -LiteralPath $svcLog)
    if ($all.Count -gt $svcLogBefore) { $svcNew = @($all[$svcLogBefore..($all.Count - 1)]) }
}
$ran = @($svcNew | Select-String -Pattern 'register reconcile: exited with' -SimpleMatch)
Note ($ran.Count -gt 0) 'sdsvc.log records that the service ran the register reconcile' `
     (($svcNew | Select-String -Pattern 'register reconcile').Line -join ' | ')
if ($ran.Count -gt 0) {
    Write-Host ('         ' + $ran[-1].Line.Trim())
}

$sweepNew = @()
if (Test-Path -LiteralPath $sweepLog) {
    $all = @(Get-Content -LiteralPath $sweepLog)
    if ($all.Count -gt $sweepLogBefore) { $sweepNew = @($all[$sweepLogBefore..($all.Count - 1)]) }
}
# Rule 1 of the instrument section: what it actually did, not the conclusion.
Note ($sweepNew.Count -gt 0) 'the sweep wrote a fresh record of what it did' ($sweepNew.Count.ToString() + ' new line(s)')
$summary = @($sweepNew | Select-String -Pattern 'considered,')
if ($summary.Count -gt 0) { Write-Host ('         ' + $summary[-1].Line.Trim()) }

# --- and the register afterwards -------------------------------------------

$after = Classify
if ($null -eq $after) { Stop-Now 'the register could not be read after the restart' }

Write-Host ''
Write-Host '--- after the restart'
Write-Host ('  ' + (@($after.dead)).Count + ' dead   : ' + $(if ((@($after.dead)).Count -eq 0) { '(none)' } else { ($after.dead -join ', ') }))
Write-Host ('  ' + (@($after.refused)).Count + ' refused: ' + $(if ((@($after.refused)).Count -eq 0) { '(none)' } else { ($after.refused -join ', ') }))
Write-Host ('  ' + (@($after.ok)).Count + ' valid or exempt: ' + (($after.ok) -join ', '))

if ($provesRemoval) {
    $stillThere = @($before.dead | Where-Object { $after.dead -contains $_ })
    Note ($stillThere.Count -eq 0) `
         ('every one of the ' + (@($before.dead)).Count + ' dead record(s) was removed') `
         ('still there: ' + ($stillThere -join ', '))
} else {
    Write-Host '  [SKIP] the removal rows - there was nothing dead to remove (see the NOTE above)'
}

# THE OTHER HALF OF "BOTH HALVES OR NEITHER": a sweep that removed the dead
# records AND something else would pass the row above.  Only valid and exempt
# records are asserted to survive - a REFUSED one is a dead record the sweep
# declined to act on, and whether it survives is not this row's question.
$lost = @($before.ok | Where-Object { $after.ok -notcontains $_ })
Note ($lost.Count -eq 0) 'and every valid or exempt record survived' ('lost: ' + ($lost -join ', '))

Note ((@($after.dead)).Count -eq 0) 'no record the sweep should have taken is still there' `
     (($after.dead) -join ', ')

# A REFUSED RECORD LEFT BEHIND IS NOT A FAILURE OF THE SWEEP - it is the sweep
# doing what it is told - but it IS an inconsistent register, so it is reported
# by name here and scored by the verify-register child below.
if ((@($after.refused)).Count -gt 0) {
    Write-Host ('  NOTE: ' + (@($after.refused)).Count + ' record(s) were REFUSED and remain. That is the sweep obeying its')
    Write-Host '  refusal table, not failing - but the register is still inconsistent, and'
    Write-Host '  verify-register below will say so.  Read reconcile-accounts.log for the reason.'
}

# --- the shipped consistency check, unchanged ------------------------------
#
# Run as a child rather than reimplemented, so "is the register clean" has one
# definition and this cannot drift from the step in VerifyInstall1.

Write-Host ''
Write-Host '--- verify-register.ps1 on the swept tree'
& (Join-Path $Gplbld 'verify-register.ps1') -DataDir $DataDir -NoCurrentCheck | Out-Null
$vr = $LASTEXITCODE
Note ($vr -eq 0) 'verify-register exits 0 on the swept register' ('got ' + $vr)

Write-Host ''
Write-Host ('verify-registersweep: ' + $pass + ' passed, ' + $fail + ' failed')
if ($pass -eq 0) {
    Write-Host 'verify-registersweep: NOTHING WAS ASSERTED - that is a failure, not a pass.'
    exit 1
}
if ($fail -gt 0) { exit 1 }
exit 0
