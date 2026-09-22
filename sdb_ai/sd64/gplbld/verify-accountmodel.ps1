<#
.SYNOPSIS
    RELEASE_1.1 64's owed whole-of-NEWVOC coverage: does a freshly created ordinary
    account's VOC hold EVERY record NEWVOC holds, and what else does it hold?

.DESCRIPTION
    RELEASE_1.1 64 (PROJECT_STATUS.md) named four things owed when it deleted
    verify-tiers.ps1 and the tier machinery it measured.  Two are covered elsewhere
    (the SUSPENDED/UNSUSPENDED round trip: verify-doors-admin.ps1 and verify-doors*.ps1;
    the tier keywords refused at create time: verify-routes.ps1 Step 2 and
    test-acctkeywords-units.py).  This file is the whole-of-NEWVOC count.

    ***REWRITTEN 21 SEP 2026 AFTER ITS FIRST RUN (b209) COULD NOT RUN.***  Three defects,
    all in this file and none in the product:
      1. The count reader disqualified on "not in your VOC" anywhere in the output, and
         that phrase came from the UPDATE.ACCOUNTS line, not from COUNT VOC, which had
         answered "398 record(s) counted".  It now anchors ONLY on the success wording.
      2. UPDATE.ACCOUNTS is in voc_template and NOT in newvoc, so an ordinary account
         cannot run it; the two "refresh" steps and this header's old premise were wrong.
         A freshly created account's VOC is NOT empty - CREATEA fills it (createa:1620+)
         - so nothing needs refreshing before it can be measured.
      3. The account's VOC held 398 records against NEWVOC's 395 with no refresh run, so
         "the account's count equals NEWVOC's" was the wrong assertion.  The right one is
         "no NEWVOC id is MISSING", and the extras are named and pinned.

    WHAT IT DOES.  As SDSYS (the seat, sdsys-seat.ps1): CREATE.ACCOUNT a throwaway account,
    then LIST NEWVOC's ids.  Then, through the seat's -Internal door, LOGTO the account and
    LIST its own VOC's ids.  Then it compares the two sets.  A LIST is used rather than one
    COUNT per id, so the EXTRAS are seen and named, not only counted.

    THE SDSYS SEAT, AND WHY -Internal IS NEEDED HERE SPECIFICALLY.  cproc (logto.authorised)
    admits a LOGTO only to a session that is BOTH K$INTERNAL and K$ADMINISTRATOR, or to an OS
    user standing in the target account's own group.  The seat's ordinary session is SDSYS
    but not K$INTERNAL, so a LOGTO into a throwaway personal account needs the seat's
    -Internal door.  RELEASE_1.1 82 rules that door development-only; this is a gplbld
    verifier, which is what it is for.

    WHAT THIS DOES NOT COVER, SAID PLAINLY.  The "update.voc @ID case machinery" (the
    upper-case-fallback half of login:1734-1747) and a SECOND refresh are not exercised:
    UPDATE.ACCOUNTS is not reachable from an ordinary account, and "UPDATE.ACCOUNTS ALL" from
    SDSYS would refresh every registered account, the owner's included, for the sake of one
    throwaway.  Cover that on an upgrade run (verify-upgrade / upgrade-voc.ps1) instead.

.PARAMETER Prefix
    Stem for one throwaway account, <prefix>a.  Use a stem nobody has used - CREATE.ACCOUNT
    refuses a name it has seen.

.PARAMETER Keep
    Leave the account behind for poking at.  It still needs DELETE.ACCOUNT.

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

# 22 Sep 26 - RELEASE_1.1 100 IS FIXED AND THIS IS NOW 0, WHICH IS WHAT THIS CONSTANT WAS
# BUILT TO ANNOUNCE.  It read 1, and its note said "when 100 is fixed this becomes 0 and the
# two count rows below go red until this is changed - which is the point".  That is what
# happened: newvoc/%t was renamed to newvoc/%T (a case-only rename, so through a temporary
# name on NTFS), and COUNT NEWVOC and LIST NEWVOC should now agree exactly.
#
# WHY %T AND NOT %t, MEASURED RATHER THAN INFERRED - which was the recorded objection to the
# fix.  op_dio4.c:1135 decodes the "~" escape by testing *(p+1) == 'T', UPPER CASE and first
# character only; a lower-case %t falls through to the generic loop, where PRE_RELEASE 128
# keeps an unknown escape LITERAL.  So "%t" read back as the id "%t" and never as "~".  The
# UpperCaseString() above it at :1119 does not save it: that sits under
# CASE_INSENSITIVE_FILE_SYSTEM, which dh_open.c:581 records as "a macro this tree never
# defines".  The 19 Aug 2026 "every file name is lower case" rename is what broke it, and an
# escape letter is not a name - which is why this one file is exempt from that rule.
$KnownUnlisted = 0

# THE EXTRAS: what a created account's VOC holds that NEWVOC does not - the four
# per-account file pointers CREATEA makes - pinned from the first measured run (b213,
# 21 Sep 2026: 394 listed NEWVOC ids + these 4 = the account's 398).  $null would mean
# "not measured yet": the run prints them and the row reads SKIP rather than passing on a guess.
$ExpectedExtras = @('$command.stack', '$hold', '$savedlists', 'bp')

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

function Skip($check, $why) {
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = '(skipped)'; Observed = '(skipped)' })
    Write-Host ("  [SKIP] {0}: {1}" -f $check, $why)
}

function Fail($msg) {
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# "N record(s) counted" is the ONLY thing this reads, and the FIRST such line.  It is not
# disqualified by any other wording in the output: the b209 run died because a refusal on
# a DIFFERENT command ("UPDATE.ACCOUNTS is not in your VOC") sat beside a good count.  No
# match at all returns -1, which the caller turns into a refusal.
function Get-CountLine([string]$out) {
    if ($out -match '(?m)^(\d+) record\(s\) counted') { return [int]$Matches[1] }
    return -1
}

# "LIST <file> @ID NO.PAGE" prints an @ID column twice, one record per line, under a
# header line of dots, and ends with "N record(s) listed".  Returns the ids AND that N, so
# the caller can reconcile them: a listing that lost lines must not score as a smaller set.
function Get-ListedIds([string]$out) {
    $ids = New-Object System.Collections.ArrayList
    foreach ($l in ($out -split "`r?`n")) {
        if ($l -match '^(\S+)\s+\1\s*$' -and $Matches[1] -notmatch '^@ID\.') { $null = $ids.Add($Matches[1]) }
    }
    $said = -1
    if ($out -match '(?m)^(\d+) record\(s\) listed') { $said = [int]$Matches[1] }
    return [pscustomobject]@{ Ids = [string[]]$ids.ToArray(); Said = $said }
}

# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT.  See the header for why -Internal is needed.
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

# Prove the seat BEFORE anything is made, INCLUDING the -Internal door: this run needs both,
# and a failure discovered only at the LOGTO step would look like a product defect rather
# than the precondition it is.
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
    Step 1 "CREATE.ACCOUNT USER $acct SSH, then list NEWVOC's ids"

    # No -Internal: SDSYS makes its own account here, nothing LOGTOs anywhere.
    $out = Invoke-SD @("CREATE.ACCOUNT USER $acct SSH", $pw, $pw, 'COUNT NEWVOC', 'LIST NEWVOC @ID NO.PAGE')
    if (-not (Test-Path -LiteralPath $accRec)) { Write-Host $out; Fail "CREATE.ACCOUNT did not register $acct" }
    $made = $true
    Note 'CREATE.ACCOUNT registered the account' $true (Test-Path -LiteralPath $accRec)

    $newvocCount = Get-CountLine $out
    $nv = Get-ListedIds $out
    Write-Host ("   COUNT NEWVOC said $newvocCount; LIST NEWVOC printed $($nv.Ids.Count) id line(s) and said $($nv.Said)")
    Note 'COUNT NEWVOC answered with a real number' $true ($newvocCount -ge 300)
    if ($newvocCount -lt 300) { Write-Host $out; Fail 'COUNT NEWVOC did not answer - nothing below can be judged.  Raw output above.' }
    $wantListed = $newvocCount - $KnownUnlisted
    Note "LIST NEWVOC printed COUNT minus the $KnownUnlisted known unlisted entry (RELEASE_1.1 100)" $wantListed $nv.Ids.Count
    Note 'and its own "N record(s) listed" line agrees' $wantListed $nv.Said
    if ($nv.Ids.Count -ne $wantListed) { Write-Host $out; Fail 'the NEWVOC id listing lost lines (or the known unlisted entry changed) - refusing to compare a partial set.  Raw output above.' }

    # -----------------------------------------------------------------------
    Step 2 "LOGTO $acct and list its own VOC's ids"

    $out = Invoke-SD @("LOGTO $acct", 'COUNT VOC', 'LIST VOC @ID NO.PAGE', 'COUNT VOC WITH @ID = "create.account"') -Internal
    $vocCount = Get-CountLine $out
    $av = Get-ListedIds $out
    Write-Host ("   COUNT VOC said $vocCount; LIST VOC printed $($av.Ids.Count) id line(s) and said $($av.Said)")
    if ($vocCount -lt 300) { Write-Host $out; Fail "the LOGTO did not reach a VOC with a readable count.  A refused LOGTO reads 'Connection terminated'.  Raw output above." }
    Note 'LIST VOC printed exactly as many ids as COUNT VOC said' $vocCount $av.Ids.Count
    Note 'and its own "N record(s) listed" line agrees' $vocCount $av.Said
    if ($av.Ids.Count -ne $vocCount) { Write-Host $out; Fail 'the account VOC id listing lost lines - refusing to compare a partial set.  Raw output above.' }

    # THE PROOF THAT THE LOGTO SWITCHED ACCOUNT.  CREATE.ACCOUNT is an administration verb
    # that lives in voc_template, SDSYS's own VOC, and in no ordinary account's.  Had the
    # LOGTO been silently refused the session would still be SDSYS and this would count 1.
    $counts = @([regex]::Matches($out, '(?m)^(\d+) record\(s\) counted') | ForEach-Object { [int]$_.Groups[1].Value })
    $adminVerbs = $(if ($counts.Count -ge 2) { $counts[$counts.Count - 1] } else { -1 })
    Note 'the account VOC does NOT hold CREATE.ACCOUNT (so the LOGTO really switched)' 0 $adminVerbs

    # -----------------------------------------------------------------------
    Step 3 'Compare the two sets'

    $have = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in $av.Ids) { $null = $have.Add($i) }
    $want = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in $nv.Ids) { $null = $want.Add($i) }

    $missing = @($nv.Ids | Where-Object { -not $have.Contains($_) } | Sort-Object)
    $extras  = @($av.Ids | Where-Object { -not $want.Contains($_) } | Sort-Object)
    Write-Host ("   NEWVOC $($want.Count) distinct id(s); account VOC $($have.Count) distinct id(s)")
    Write-Host ("   MISSING from the account (in NEWVOC, not in its VOC): " + $(if ($missing.Count) { $missing -join ', ' } else { '(none)' }))
    Write-Host ("   EXTRAS in the account (in its VOC, not in NEWVOC)   : " + $(if ($extras.Count) { $extras -join ', ' } else { '(none)' }))

    # THE ASSERTION THE OWED ITEM IS ABOUT: a fresh account receives the WHOLE of NEWVOC.
    Note 'no NEWVOC id is missing from the account VOC' 0 $missing.Count

    if ($null -eq $ExpectedExtras) {
        Skip 'the account VOC holds exactly the pinned extras' ('$ExpectedExtras is not pinned yet - pin these: ' + ($extras -join ' '))
    } else {
        Note 'the account VOC holds exactly the pinned extras' (($ExpectedExtras | Sort-Object) -join ' ') ($extras -join ' ')
    }

    # -----------------------------------------------------------------------
    Step 4 'A spot check: a name every NEWVOC has carried is actually there'

    # WHO is chosen because it is unconditionally in NEWVOC (every session needs it) and is
    # not one of the administration verbs 64's entry says NEWVOC has never carried.
    $out = Invoke-SD @("LOGTO $acct", 'COUNT VOC WITH @ID = "who"') -Internal
    Note 'WHO is present in the account VOC' 1 (Get-CountLine $out)
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
Write-Host ('verify-accountmodel: a fresh account receives the whole of NEWVOC.  The extras are ' +
            'listed above.  The case machinery and a second refresh are NOT covered - see the header.') -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
