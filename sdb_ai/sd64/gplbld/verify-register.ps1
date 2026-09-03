# verify-register.ps1 - assert that @SDSYS/ACCOUNTS and @SDSYS/OS.USERS contain
# only valid records
#
#   powershell -File verify-register.ps1     ORDINARY UNELEVATED PROMPT
#
# Exit 0 the register is consistent, 1 it is not, 2 the check could not be run.
#
# PRE_RELEASE_FIXES.md 93 and 65.  The fix for those is a sweep at service
# start (reconcile-accounts.ps1); this is the check that says whether it
# worked, and it is worth having whichever way the fix had gone - entry 93 says
# so in those words, because "the register contains only valid records" was
# assertable on every run since the register existed and nothing asserted it.
#
# ***WHAT IT WOULD HAVE CAUGHT, AND WHEN.***  1 Sep 2026, immediately after the
# b100 full suite came back GREEN in both halves - 41 steps, 753 PASS, 0 FAIL -
# the ACCOUNTS register held 15 records for that run's accounts and ONE of
# their directories still existed.  A 41-step green suite noticed nothing,
# because no step asserted the register was internally consistent.  That is the
# gap this closes, and it is the same class as PRE_RELEASE 112.
#
# UNELEVATED, AND THAT IS NOT A CONVENIENCE.  Both register files grant sdusers
# ReadAndExecute (secure-accounts.ps1, secure-osusers.ps1), so an ordinary
# member can read them - which is the whole reason a stale record MATTERS: it
# is visible to every SD user through LIST ACCOUNTS.  Checking it from an
# elevated window would measure a file nobody reads that way.
#
# IT CHANGES NOTHING.  Every path here reads.
#
# ======================================================================
#   HOW IT DECIDES, AND WHY IT BORROWS RATHER THAN REIMPLEMENTS
# ======================================================================
#
# The rule for "is this record valid" lives in reconcile-accounts.ps1, and this
# LIFTS it out of that file with the PowerShell parser rather than carrying a
# copy - the technique verify-allowgroups.ps1, test-reclaim-units.ps1 and
# test-apiidentity-units.ps1 all use, for the reason they all give: two hand-
# maintained copies of one rule is the defect three of this tree's own guards
# exist to catch, and here it would produce a verifier that passes a register
# the sweep would act on, or the reverse.
#
# SO IT ALSO ASKS THE QUESTION A SECOND WAY, WITHOUT THE TABLE.  A borrowed
# rule inherits a borrowed mistake.  Check 2 below goes straight at the fact -
# every USER record must name a Windows account that resolves - with no
# reference to the sweep's classifier at all, and check 3 requires the two
# readings to agree.  Where they disagree it is the verifier that is wrong, and
# it says so rather than picking a winner.
#
# AND IT PROVES IT CAN FAIL.  Check 0 runs the classifier over a record that is
# invented on the spot and cannot exist, and requires it to be scored
# actionable.  A verifier that passes because it measured nothing is the thing
# CLAUDE.md's instrument section is about, and a register that is legitimately
# clean - which is the ordinary state, and is the state on a fresh install -
# produces exactly the same "0 bad records" as one that was never read.
#
# NOT SHIPPED - must be on assert-current.ps1's $neverShipped list, added in
# the same commit that creates this file.
#
# START-HISTORY:
# 03 Sep 26 Windows port - written with the fix for PRE_RELEASE_FIXES.md 93
#           and 65.
# END-HISTORY

param(
    # The data tree.  Overridable for the same reason the sweep's is.
    [string] $DataDir = '',

    # Skip the assert-current call.  For a unit test only: it lets the checks
    # below be driven against a synthetic tree on a machine whose install is
    # deliberately not current.
    [switch] $NoCurrentCheck
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
    Write-Host ('verify-register: CANNOT RUN - ' + $why)
    Write-Host 'verify-register: nothing was measured.'
    exit 2
}

Write-Host ''
Write-Host '=== verify-register: the account register contains only valid records ==='

if (-not $NoCurrentCheck) {
    & (Join-Path $Gplbld 'assert-current.ps1') | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Stop-Now 'assert-current refuses - the install does not match source.'
    }
}

$progData = $env:ProgramData
if ([string]::IsNullOrEmpty($progData)) { $progData = 'C:\ProgramData' }
if ($DataDir -eq '') { $DataDir = Join-Path $progData 'SD' }

$sysDir      = Join-Path $DataDir 'sdsys'
$accountsDir = Join-Path $sysDir 'accounts'
$osUsersDir  = Join-Path $sysDir 'os.users'

# Rule 1 of the instrument section: the resolved inputs.
Write-Host ('  data tree : ' + $DataDir)
Write-Host ('  accounts  : ' + $accountsDir)
Write-Host ('  os.users  : ' + $osUsersDir)

# --- lift the sweep's rule -------------------------------------------------

$Sweep = Join-Path $Gplbld 'reconcile-accounts.ps1'
if (-not (Test-Path -LiteralPath $Sweep)) { Stop-Now ('no sweep to borrow the rule from: ' + $Sweep) }

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Sweep, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { Stop-Now ($Sweep + ' does not parse: ' + $errors.Count + ' error(s)') }

$funcs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
$wanted = @('Norm', 'Get-RecordLogin', 'Get-ReconcileRefusal', 'Get-Verdict', 'Resolve-WindowsAccount')
foreach ($w in $wanted) {
    $d = @($funcs | Where-Object { $_.Name -eq $w })
    # REFUSE THE NULL CASE.  A file whose functions the parser cannot find
    # parses with ZERO errors - measured, on the embedded BOM that scored a
    # false green as step 17 of b18 - so the names are asserted, not assumed.
    if ($d.Count -ne 1) {
        Stop-Now ($Sweep + ' defines ' + $d.Count + ' function(s) called ' + $w + ', expected 1')
    }
    . ([scriptblock]::Create($d[0].Extent.Text))
}
Write-Host ('  rule      : lifted ' + $wanted.Count + ' function(s) from ' + $Sweep)

# --- the account root, read the way the sweep reads it ---------------------

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
$rootNorm = Norm $AccountsRoot
Write-Host ('  root      : ' + $rootNorm)

# --- the control on the lookup, before any verdict -------------------------

$localUsers = $null
try { $localUsers = @(Get-LocalUser -ErrorAction Stop) } catch {
    Stop-Now ('the local account enumeration failed - ' + $_.Exception.Message + '.  Every record would have looked stale.')
}
if ($localUsers.Count -eq 0) {
    Stop-Now 'the local account enumeration returned ZERO accounts, which no Windows machine has.  The lookup is broken, not the register.'
}
$localNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($u in $localUsers) { [void]$localNames.Add($u.Name) }
Write-Host ('  control   : ' + $localNames.Count + ' local Windows account(s) enumerated')

# ======================================================================
#   CHECK 0 - the instrument can say no
# ======================================================================

Write-Host ''
Write-Host '--- check 0: the instrument is shown failing before it is believed'

$ghost = 'zzregister-no-such-account-8b1d'
$look  = Resolve-WindowsAccount $ghost $localNames
Note ($look.ok -and $look.live -eq '') 'an invented account name is ABSENT, and the lookup completed' `
     ('ok=' + $look.ok + ' live=' + $look.live)

$verdict = Get-Verdict (Get-ReconcileRefusal 'accounts' $ghost ('sdu_' + $ghost) `
                        (Join-Path $rootNorm $ghost) $rootNorm $ghost $look.live $look.ok)
Note ($verdict -eq 'act') 'and a register record naming it would score INVALID' $verdict

$verdict = Get-Verdict (Get-ReconcileRefusal 'os.users' $ghost '' '' $rootNorm $ghost $look.live $look.ok)
Note ($verdict -eq 'act') 'so would an os.users record naming it' $verdict

# ======================================================================
#   CHECK 1 - every record, by the sweep's own rule
# ======================================================================

# A HASHTABLE, NOT AN ARRAY, and reconcile-accounts.ps1's Get-Records carries
# the measurement: a PowerShell function returning @() hands the caller $null,
# so an EMPTY register and an UNREADABLE one arrive as the same value.  Here
# that would have refused the whole check with "OS.USERS could not be read" on
# any install with no ADMINISTRATOR-tier account - which is a legitimate tree,
# and is exactly what a fresh install looks like before adopt runs.
function Read-Register([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return @{ ok = $true; absent = $true; items = @() } }
    try {
        return @{ ok = $true; absent = $false; items = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction Stop) }
    } catch {
        return @{ ok = $false; absent = $false; items = @() }
    }
}

Write-Host ''
Write-Host '--- check 1: every ACCOUNTS record scores valid or exempt'

$accRead = Read-Register $accountsDir
if (-not $accRead.ok)   { Stop-Now ('ACCOUNTS could not be read at ' + $accountsDir) }
if ($accRead.absent)    { Stop-Now ('there is no ACCOUNTS file at ' + $accountsDir) }
$accRecords = @($accRead.items)
# AN EMPTY REGISTER IS NOT A CLEAN ONE.  sdsys always has a record, so zero is
# a broken read or a broken install, and it must not score "0 bad records".
if ($accRecords.Count -eq 0) { Stop-Now 'ACCOUNTS holds ZERO records.  sdsys always has one, so this is not an empty register - it is an unreadable or broken one.' }

Write-Host ('  ' + $accRecords.Count + ' ACCOUNTS record(s)')

$badAcc      = @()
$loginOfRec  = @{}
foreach ($f in $accRecords) {
    $rec = @()
    try { $rec = @(Get-Content -LiteralPath $f.FullName -ErrorAction Stop) } catch {
        $badAcc += ('{0} could not be read - {1}' -f $f.Name, $_.Exception.Message)
        continue
    }
    $path  = ''
    $group = ''
    if ($rec.Count -ge 1) { $path  = ([string]$rec[0]).Trim() }
    if ($rec.Count -ge 3) { $group = ([string]$rec[2]).Trim() }

    $login = Get-RecordLogin $group
    $loginOfRec[$f.Name] = $login

    $look = Resolve-WindowsAccount $login $localNames
    $why  = Get-ReconcileRefusal 'accounts' $f.Name $group $path $rootNorm $login $look.live $look.ok
    $v    = Get-Verdict $why

    # AN ACTIONABLE RECORD HAS NO "reason", because '' IS the verdict - so it
    # is spelled out rather than printed as an empty column, which reads like a
    # row the check did not reach.
    Write-Host ('    {0,-20} login={1,-16} {2,-8} {3}' -f $f.Name,
                $(if ($login -eq '') { '(none)' } else { $login }), $v,
                $(if ($why -eq '') { 'DEAD - no Windows account of that name exists' } else { $why }))

    if ($v -ne 'valid' -and $v -ne 'exempt') { $badAcc += ('{0}: {1}' -f $f.Name, $(if ($why -eq '') { 'names a Windows account that no longer exists' } else { $why })) }
}
Note ($badAcc.Count -eq 0) ('all ' + $accRecords.Count + ' ACCOUNTS records are valid or exempt') `
     ($badAcc -join ' | ')

Write-Host ''
Write-Host '--- check 1b: every OS.USERS record scores valid'

$osRead = Read-Register $osUsersDir
if (-not $osRead.ok) { Stop-Now ('OS.USERS could not be read at ' + $osUsersDir) }
$osRecords = @($osRead.items)
if ($osRead.absent) {
    Write-Host ('  no OS.USERS file at ' + $osUsersDir + ' - ordinary before any ADMINISTRATOR-tier account exists')
}
Write-Host ('  ' + $osRecords.Count + ' OS.USERS record(s)')

$badOsu = @()
foreach ($f in $osRecords) {
    $look = Resolve-WindowsAccount $f.Name $localNames
    $why  = Get-ReconcileRefusal 'os.users' $f.Name '' '' $rootNorm $f.Name $look.live $look.ok
    $v    = Get-Verdict $why
    Write-Host ('    {0,-20} {1,-8} {2}' -f $f.Name, $v,
                $(if ($why -eq '') { 'DEAD - no Windows account of that name exists' } else { $why }))
    if ($v -ne 'valid' -and $v -ne 'exempt') { $badOsu += ('{0}: {1}' -f $f.Name, $(if ($why -eq '') { 'names a Windows account that no longer exists' } else { $why })) }
}
# ZERO IS LEGITIMATE HERE, unlike ACCOUNTS: only an ADMINISTRATOR-tier account
# ever gets an os.users record (CREATEA grant.os.access), so an install with
# none is an ordinary state and is reported as such rather than scored.
if ($osRecords.Count -eq 0) {
    Write-Host '    (none - ordinary: only ADMINISTRATOR-tier accounts get one)'
}
Note ($badOsu.Count -eq 0) ('all ' + $osRecords.Count + ' OS.USERS records are valid') ($badOsu -join ' | ')

# ======================================================================
#   CHECK 2 - the same question, asked WITHOUT the borrowed rule
# ======================================================================

Write-Host ''
Write-Host '--- check 2: the same fact, read a second way, with no reference to the sweep'

$badDirect = @()
$exemptDirect = 0
foreach ($f in $accRecords) {
    $rec = @()
    try { $rec = @(Get-Content -LiteralPath $f.FullName -ErrorAction Stop) } catch { continue }
    $path  = ''
    $group = ''
    if ($rec.Count -ge 1) { $path  = ([string]$rec[0]).Trim() }
    if ($rec.Count -ge 3) { $group = ([string]$rec[2]).Trim() }

    # A TRUNCATED RECORD IS BAD, NOT EXEMPT - the same row the table carries,
    # written independently here, because without it an empty file looks like
    # an OTHER account to both readings and check 3 would agree on a wrong
    # answer.
    if ($path -eq '') { $badDirect += ($f.Name + ': no ACC$PATH - the record is truncated'); continue }

    # Written out longhand on purpose - this must not call Get-RecordLogin.
    if (-not $group.ToLower().StartsWith('sdu_')) { $exemptDirect++; continue }
    $login = $group.Substring(4).Trim()
    if ($login -eq '') { $badDirect += ($f.Name + ': ACC$GROUP is a bare sdu_'); continue }

    $known = $false
    foreach ($u in $localUsers) { if ($u.Name -eq $login) { $known = $true } }
    if (-not $known) {
        try {
            [void]([System.Security.Principal.NTAccount]$login).Translate([System.Security.Principal.SecurityIdentifier])
            $known = $true
        } catch { }
    }
    if (-not $known) { $badDirect += ($f.Name + ': no Windows account called ' + $login) }
}
Write-Host ('  ' + $exemptDirect + ' record(s) have no sdu_ group and so no Windows login to check')
Note ($badDirect.Count -eq 0) 'the direct reading finds no dead USER record' ($badDirect -join ' | ')

Write-Host ''
Write-Host '--- check 3: the two readings agree'
Note ($badDirect.Count -eq $badAcc.Count) `
     ('both readings found the same number of bad records (' + $badAcc.Count + ')') `
     ('table=' + $badAcc.Count + ' direct=' + $badDirect.Count + ' - where these differ it is THIS VERIFIER that is wrong, not the register')

Write-Host ''
Write-Host ('verify-register: ' + $pass + ' passed, ' + $fail + ' failed')

if ($pass -eq 0) {
    Write-Host 'verify-register: NOTHING WAS ASSERTED - that is a failure, not a pass.'
    exit 1
}
if ($fail -gt 0) {
    Write-Host ''
    Write-Host '  A dead record is PRE_RELEASE 93 or 65.  reconcile-accounts.ps1 clears them'
    Write-Host '  at every SD service start; run it by hand with -List to see what is'
    Write-Host '  pending, and restart the SD service to have them cleared:'
    Write-Host ''
    Write-Host '      C:\Program Files\SD\reconcile-accounts.ps1 -List'
    Write-Host ''
    exit 1
}
exit 0
