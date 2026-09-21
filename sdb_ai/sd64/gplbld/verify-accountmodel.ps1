<#
.SYNOPSIS
    Two of RELEASE_1.1 64's four owed items for this file: does a fresh ordinary
    account really receive the whole of NEWVOC, and does refreshing it a second
    time leave no duplicate or missing record behind?

.DESCRIPTION
    RELEASE_1.1 64 (PROJECT_STATUS.md "START HERE", 20 Sep 2026 teardown review)
    named four things this file was owed, when it deleted verify-tiers.ps1 and
    the tier machinery it measured: "the whole-of-NEWVOC count for an ordinary
    account, the SUSPENDED/UNSUSPENDED register round trip, the tier keywords
    refused, and the update.voc @ID case machinery."

    TWO OF THE FOUR ARE ALREADY COVERED, MEASURED THIS SESSION RATHER THAN
    ASSUMED, AND ARE NOT REPEATED HERE:
      - the SUSPENDED/UNSUSPENDED register round trip, and its enforcement
        across all three doors (ssh, logto, the API) - verify-doors-admin.ps1
        (the elevated half) and verify-doors.ps1 / verify-doors-suite.ps1.
      - the tier keywords refused at create time (message 2018, nothing left
        behind) - verify-routes.ps1 Step 2, live; test-acctkeywords-units.py,
        statically, deriving the refused set from createa itself.
    So this file is deliberately narrower than its name might suggest: it is
    the other two, and nothing here duplicates what those already measure.

    "UPDATE.ACCOUNTS" DOES NOT TAKE AN ACCOUNT NAME - read from cproc:3374-3406
    and login:324-426, not assumed. With no keyword it refreshes the CALLER'S
    OWN current VOC (login mode 2); "UPDATE.ACCOUNTS ALL" (mode 4, SDSYS and
    administrator only) walks the whole ACCOUNTS register and refreshes every
    entry BY PATH, with no session switch. A plain LOGTO does NOT refresh a
    VOC - login only reaches update.voc on modes 2, 3 or 4 - so a freshly
    created account's VOC is empty (CREATEA creates the dynamic file and
    nothing else, createa:1497-1499) until something runs one or the other.
    This file uses the first form, from inside the subject account, because
    that is what an ordinary person's first login exercises.

    THE SDSYS SEAT, AND WHY -Internal IS NEEDED HERE SPECIFICALLY.
    cproc:4000 (logto.authorised) admits a LOGTO only to a session that is
    BOTH K$INTERNAL and K$ADMINISTRATOR, or to an OS user standing in the
    target account's own group - the bare K$ADMINISTRATOR bypass was deleted
    31 Aug 2026 (PRE_RELEASE_FIXES 91). The seat's ordinary session is SDSYS
    but not K$INTERNAL, so a LOGTO into a throwaway personal account needs the
    seat's -Internal door (sdsys-seat.ps1's own comment names this exact case:
    "LOGTO to a personal account"). RELEASE_1.1 82 rules that door
    development-only; this is a gplbld verifier, which is what it is for.

    WHAT THIS DOES NOT COVER, SAID PLAINLY - THE UPPERCASE-FALLBACK HALF OF
    THE CASE MACHINERY IS NOT EXERCISED. login:1734-1747 is the mechanism the
    "update.voc @ID case machinery" phrase actually names: on a rename
    ($RELEASE -> $release, 14 Sep 2026), an account holding the OLD upper-case
    record takes it over on an exact-id miss rather than growing a lower-case
    twin beside it. Exercising that branch needs a fresh account's EMPTY VOC to
    already hold an upper-case legacy record before its first refresh - and
    every route found to plant one this session was judged too uncertain to
    ship unverified: COPY's src/tgt file arguments resolve through the CALLING
    session's own VOC (copy:28, "COPY FROM [DICT] src.file"), which is exactly
    what a fresh account does not have before its first refresh, so
    "COPY FROM NEWVOC ..." from inside it would need NEWVOC to already
    resolve - and this agent has no elevation in this session, so a
    path-based alternative from the SDSYS side could not be tried against a
    live install before being written down here as fact. Shipping a leg this
    session could not watch pass is exactly what "verify a script loads before
    you submit it" exists to stop, extended to a mechanism rather than a
    parse. What IS exercised instead - a second refresh creating no duplicate
    - is the exact-match branch immediately above the fallback (the
    "old.found" it reaches by readu on the unchanged id), which is real
    coverage of the same subroutine's ordinary path, not a substitute for the
    rename path. A future session with either elevation or a verified COPY
    incantation should extend Step 3 rather than write a second file.

.PARAMETER Prefix
    Stem for one throwaway account, <prefix>a. Use a stem nobody has used -
    CREATE.ACCOUNT refuses a name it has seen.

.PARAMETER Keep
    Leave the account behind for poking at. It still needs DELETE.ACCOUNT.

.EXAMPLE
    From an elevated PowerShell:
    C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-accountmodel.ps1 -Prefix sdam1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-accountmodel-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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

function Fail($msg) {
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# "N record(s) counted", anchored the way verify-createfilecase.ps1's
# Test-CountResolved already proved live: disqualified by the wording SD uses
# when the file named does not resolve at all, which "0 record(s) counted"
# must not be confused with (an empty or missing-record COUNT is not the same
# as a file COUNT could not open).
function Get-VocCount([string]$out) {
    if ($out -match 'File not found|not in your VOC|did not finish in') { return -1 }
    if ($out -match '(?m)^(\d+) record\(s\) counted') { return [int]$Matches[1] }
    return -1
}

# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT.  See the header for why -Internal
# is needed for the LOGTO leg and not for the others.
. (Join-Path $Gplbld 'sdsys-seat.ps1')
function Invoke-SD([string[]]$commands, [switch]$Internal) {
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec 120 -Internal:$Internal)
}

# ---------------------------------------------------------------------------
if (-not $Prefix) {
    Write-Host 'verify-accountmodel: -Prefix is required, and must be a stem nobody has used.'
    Write-Host '  Example: -Prefix sdam1'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
if ($Prefix -notmatch '^[a-z][a-z0-9_]*$') {
    Fail ("-Prefix is '$Prefix'.  Lower case letters, digits and underscore only, " +
          'starting with a letter - CREATEA downcases the name and the Windows ' +
          'account takes it verbatim.')
}

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'this needs an ELEVATED PowerShell - registering a task in the SDSYS seat needs an elevated caller.'
}

& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'the installed tree does not match source - see above' }

if (-not (Test-Path -LiteralPath $sdExe)) { Fail "no $sdExe" }

# Prove the seat BEFORE anything is made, INCLUDING the -Internal door: this run needs
# both, and a failure discovered only at the LOGTO step would look like a product defect
# rather than the precondition it is.
Assert-SdSeat -Label 'verify-accountmodel' -Internal

$acct = $Prefix + 'a'
$accRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $acct.ToUpper())
if (Get-LocalUser -Name $acct -ErrorAction SilentlyContinue) {
    Fail "$acct already exists as a Windows account - use a fresh -Prefix."
}
if (Test-Path -LiteralPath $accRec) {
    Fail ($acct.ToUpper() + ' is still in the ACCOUNTS register - use a fresh -Prefix.')
}

Add-Type -AssemblyName System.Web
$pw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
$made = $false

try {
    # -----------------------------------------------------------------------
    Step 1 "CREATE.ACCOUNT USER $acct SSH, and COUNT NEWVOC as the expected total"

    # No -Internal: SDSYS makes its own account here, nothing LOGTOs anywhere.
    $out = Invoke-SD @("CREATE.ACCOUNT USER $acct SSH", $pw, $pw, 'COUNT NEWVOC')
    if (-not (Test-Path -LiteralPath $accRec)) { Write-Host $out; Fail "CREATE.ACCOUNT did not register $acct" }
    $made = $true

    $newvocCount = Get-VocCount $out
    Note 'CREATE.ACCOUNT registered the account' $true (Test-Path -LiteralPath $accRec)
    Note 'COUNT NEWVOC resolved to a real number' $true ($newvocCount -ge 0)
    if ($newvocCount -lt 0) {
        Fail ("COUNT NEWVOC did not answer with a parseable count - nothing below this " +
              'point can be judged against an expected total.  Raw output above.')
    }
    Write-Host "   NEWVOC holds $newvocCount record(s) - this is the target for the account's own VOC"

    # -----------------------------------------------------------------------
    Step 2 "LOGTO $acct and refresh its VOC for the first time"

    # UPDATE.ACCOUNTS with no keyword is mode 2: it refreshes the CALLER's own
    # current VOC (login:324-340), which after the LOGTO above is this account's.
    # This is the SAME call an ordinary first login's UPDATE.ACCOUNTS would make -
    # nothing here is a shortcut CREATEA itself does not take.
    $out = Invoke-SD @("LOGTO $acct", 'UPDATE.ACCOUNTS', 'COUNT VOC') -Internal
    $firstCount = Get-VocCount $out

    Note 'the LOGTO reached the account (COUNT VOC resolved)' $true ($firstCount -ge 0)
    if ($firstCount -lt 0) {
        Write-Host $out
        Fail ('COUNT VOC did not answer with a parseable count after the LOGTO - see the ' +
              'raw output above for what actually happened (a refused LOGTO reads as ' +
              '"Connection terminated" and COUNT would then run in SDSYS''s own account, ' +
              'which the count comparison below would catch as a mismatch, not this refusal).')
    }

    # THE ASSERTION THE FIRST OF THE FOUR OWED ITEMS IS ACTUALLY ABOUT.  Equal,
    # not "at least" - an ordinary account is PROGRAMMER-level now and nothing
    # else adds to or omits from NEWVOC's own copy (createa:1649-1663, the omit
    # list is dead code kept at zero).  A count that is LOWER means the walk
    # skipped something; HIGHER means something is in this account's VOC that
    # NEWVOC does not ship, which COUNT VOC would not itself explain but the
    # transcript above has the raw listing to chase.
    Note 'the account''s VOC equals NEWVOC''s count (whole-of-NEWVOC coverage)' $newvocCount $firstCount

    # -----------------------------------------------------------------------
    Step 3 "Refresh a second time: the exact-match branch must create nothing new"

    # login:1736-1737 - the FIRST thing update.voc tries for every id is an exact
    # readu against what this account already holds.  On this second call every
    # id it walked a moment ago is found that way, so this leg proves the
    # exact-match path is a true no-op, not that a NEW record cannot appear
    # twice - see the header for the fallback branch this does not reach.
    $out = Invoke-SD @("LOGTO $acct", 'UPDATE.ACCOUNTS', 'COUNT VOC') -Internal
    $secondCount = Get-VocCount $out
    Note 'second refresh: COUNT VOC still resolved' $true ($secondCount -ge 0)
    Note 'second refresh created no duplicate or missing record' $firstCount $secondCount

    # -----------------------------------------------------------------------
    Step 4 "A spot check: a name every NEWVOC has carried is actually there"

    # COUNT alone cannot tell "the right 400 records" from "some other 400" -
    # this is the one row that ties the number to an id a reader can check by
    # eye.  WHO is chosen because it is unconditionally in NEWVOC (every
    # session needs it) and is not one of the nine administration verbs 64's
    # entry says NEWVOC has never carried, so its presence says nothing about
    # whether this account was accidentally given more than PROGRAMMER level.
    $out = Invoke-SD @("LOGTO $acct", 'COUNT VOC WITH @ID = "WHO"') -Internal
    Note 'WHO is present in the refreshed VOC' 1 (Get-VocCount $out)
}
catch {
    $script:failed = $true
    Write-Host ''
    Write-Host ('verify-accountmodel: THREW - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $null = $results.Add([pscustomobject]@{
        Check = 'the run completed without throwing'; Expected = $true; Observed = $false })
}
finally {
    if ($made -and -not $Keep) {
        Step 5 'Putting the system back'
        $out = Invoke-SD @("DELETE.ACCOUNT $acct", 'Y')
        Write-Host $out
        if (Test-Path -LiteralPath $accRec) {
            Write-Host "   ACCOUNTS record for $acct is still there - remove it by hand" -ForegroundColor Yellow
        } else {
            Write-Host "   $acct removed"
        }
    } elseif ($made) {
        Write-Host ''
        Write-Host "-Keep: $acct is still there." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host

$passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("$passed/" + @($results).Count + ' checks passed')

if ($failed) {
    Write-Host ''
    Write-Host 'verify-accountmodel: FAILED' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

Write-Host ''
Write-Host ('verify-accountmodel: a fresh account receives the whole of NEWVOC, and a second ' +
            'refresh leaves the exact-match branch idempotent.  The rename/uppercase-fallback ' +
            'branch is NOT covered - see the header.') -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
