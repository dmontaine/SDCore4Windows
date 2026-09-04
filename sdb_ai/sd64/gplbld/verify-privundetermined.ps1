<#
.SYNOPSIS
    Does a privilege check that COULD NOT ANSWER say so - and does one that
    DID answer stay silent?

.DESCRIPTION
    PRE_RELEASE_FIXES.md 96.  The three privilege predicates used to answer
    "no" and "I could not tell" with the same FALSE, and every caller read it
    as "no".  Entry 96 built the tri-state - a PRIV_WHY out-parameter, four
    callers, and priv_log_undetermined() writing one line into sdsys\errlog -
    and then it was PARKED, with the whole of the undetermined half unexecuted.

    THE ROW SAID WHAT WOULD BE NEEDED AND THIS IS THAT DESIGN, BUILT.  Its
    words: "a new elevated verifier modelled on verify-apiadmin.ps1 - a
    throwaway PROGRAMMER account, the apiosexecprobe.sb probe, and four legs
    varying the record (valid yes / absent / malformed / empty) reading errlog
    deltas, with the valid-yes leg as the null-case control."  There are five
    legs here, not four: PRIV_OPEN_FAILED is reachable with an ACL denial and
    the row already said so.

    WHY IT HAS TO GO OVER THE API, WHICH IS THE PART THAT LOOKS LIKE OVERKILL.
    os_permitted() (op_sh.c:167) returns TRUE on USR_ADMIN before the os.users
    record is ever opened, so NOTHING below the flag can be reached from an
    ordinary elevated session - and kernel.c:253 sets that flag for every
    elevated NON-SOCKET session.  A socket session never gets it:

        if (IsElevated(&why) && (connection_type != CN_SOCKET))
          my_uptr->flags |= USR_ADMIN;

    So an API session is the one route on this machine that falls through into
    the file lookup.  The other route the row traced - piping into sd as the
    signed-in user - was rejected there and stays rejected: PROJECT_STATUS.md
    section 6 records it hanging on an unanswerable prompt and leaving a stray
    sd.exe that cost an elevation to clear, and it would rewrite the owner's own
    live os.users record.

    AND THE FILE LOOKUP IS REACHABLE, WHICH IS MEASURED RATHER THAN HOPED FOR.
    b108 ran with the tri-state in and left ZERO "PRIVILEGE CHECK UNDETERMINED"
    lines in errlog, while verify-apiadmin's API session was refused OS.EXECUTE
    BY NAME on that same run.  A refusal with no log line means open() returned
    ENOENT - the record was absent - and not EACCES, which would have been
    logged.  So the API session can traverse os.users and read a record in it.
    secure-osusers.ps1 says the same thing from the other side: that list is
    deliberately READ-ONLY to sdusers rather than closed to them.

    THE FIVE LEGS, AND WHAT EACH ONE IS FOR.

      absent     no record            REFUSED, and NO log line.  ENOENT is the
                                      DESIGNED no - op_sh.c's banner says
                                      "MISSING FILE OR MISSING RECORD MEANS
                                      NO... the safe direction" - so this leg
                                      asserts the discrimination entry 96 made
                                      on purpose.  A log line here would mean
                                      every ordinary refusal writes one.
      granted    "no" LF "yes"        OS.EXECUTE RUNS, and NO log line.
                                      ***THIS IS THE NULL-CASE CONTROL AND IT
                                      CARRIES THE WHOLE FILE.***  Without it
                                      every other leg is a refusal, and a probe
                                      that could never succeed would score them
                                      all.  It is also the only leg that proves
                                      the new logging is not NOISY: a check
                                      that completed must write nothing.
      malformed  "yes", no newline    REFUSED + PRIV_MALFORMED
      empty      zero bytes           REFUSED + PRIV_READ_FAILED
      denied     valid, deny ACE      REFUSED + PRIV_OPEN_FAILED

    THE GRANTED LEG IS A FIXTURE, NOT AN INVENTION.  "no" LF "yes" is byte for
    byte what CREATEA's grant.os.access writes for an ADMINISTRATOR-tier USER
    account (SH no, OS.EXECUTE yes), so this leg puts the account into a state
    the shipped product produces.  It is removed in the finally block, and the
    account is deleted with it.

    WHAT IT CANNOT REACH, SAID OUT LOUD RATHER THAN LEFT AS A GAP.  Six of the
    nine undetermined paths are not inducible here and the summary prints them
    by name every run: PRIV_NO_PASSWD, PRIV_NO_GROUP_COUNT, PRIV_NO_MEMORY and
    PRIV_NO_GROUP_LIST need getpwuid()/getgrouplist()/getgroups() to FAIL, which
    on Cygwin means a real name-service or domain-controller outage;
    PRIV_NO_USERNAME needs a session with no user name, which no login produces;
    PRIV_PATH_TOO_LONG cannot happen while sysdir is fixed and the record name
    is bounded by MAX_USERNAME_LEN.  A green run here is a claim about three
    paths and about the silence of the other side, not about all nine.

    THE LEG TABLE IS DATA AND IS GUARDED FROM OUTSIDE.
    gplbld/test-privundetermined-units.ps1 lifts Get-PrivLegs and
    Get-PrivUnreachable out of this file by AST and asserts that every reason
    string here appears VERBATIM in priv_why_text() (gplsrc/linuxlb.c), that the
    marker matches priv_log_undetermined()'s format (gplsrc/k_error.c), and that
    covered + unreachable + PRIV_ANSWERED is exactly the PRIV_WHY enum.  Adding
    an enum member turns that guard red until somebody classifies it.  It is a
    free check - no install, no elevation, no run token.

    IT CHANGES THE INSTALLED SYSTEM AND PUTS IT BACK: a throwaway Windows and SD
    account, one record in sdsys\os.users, an sd.conf APIPORT line, and two SD
    restarts.  Everything is undone in a finally block and what could not be
    undone is named.

    NOT SHIPPED - it is on assert-current.ps1's $neverShipped list.

.PARAMETER Prefix
    Name for the throwaway Windows and SD account.  Lower case, and one that
    does not exist - CREATE.ACCOUNT refuses a name it has seen.

.PARAMETER Port
    Loopback port the API listener uses.  4243 is the shipped default.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-privundetermined.ps1 -Prefix sdpwb113

    Elevated PowerShell.  Through the runner is better, because -Run derives a
    fresh prefix and a spent one fails (PRE_RELEASE 54):

    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\VerifyInstall2.ps1 -Run b113 -Only verify-privundetermined
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.  PRE_RELEASE_FIXES.md 151: a precondition refusal is not a
# failed check, and the two must not arrive at a suite summary wearing the same
# exit code.  See Refuse().

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [int] $Port = 4243
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sd64    = Split-Path -Parent $Gplbld
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$SvcName = 'SD'
$conf    = Join-Path $env:ProgramData 'SD\sd.conf'
$backup  = $conf + '.before-privundetermined'
$sysdir  = Join-Path $env:ProgramData 'SD\sdsys'
$osUsers = Join-Path $sysdir 'os.users'
$errlog  = Join-Path $sysdir 'errlog'

# ===========================================================================
# THE LEG TABLE AND THE PATHS NOBODY CAN REACH.  Two functions rather than two
# variables, so test-privundetermined-units.ps1 can lift them by AST and drive
# them without running any of this file - the same shape test-wraptext-units
# uses on finish-install.ps1's Write-Wrapped.
#
# THEY RETURN A HASHTABLE AND NOT AN ARRAY, and that is not style.  A
# PowerShell function returning @() hands the caller $null and one returning a
# single element hands back a scalar, so "empty" and "one leg" and "unreadable"
# collapse into shapes the caller cannot tell apart.  The wrapper makes .Legs
# an array whatever is in it.
# ===========================================================================

function Get-PrivLegs {
    # Fixture:  none    - no record at all
    #           bytes   - write Content exactly, as ASCII, no BOM, LF only
    #           denied  - write Content, then deny READ to the account
    # Grants:   must OS.EXECUTE actually RUN on this leg?
    # Why:      priv_why_text() for the line expected in errlog; '' means NO
    #           line is expected, which is an assertion and not an absence of
    #           one.
    return @{ Legs = @(
        @{
            Name    = 'absent'
            Title   = 'no os.users record - ENOENT, the DESIGNED no'
            Fixture = 'none'
            Content = ''
            Grants  = $false
            WhyId   = ''
            Why     = ''
            Note    = 'a log line here would mean every ordinary refusal writes one'
        },
        @{
            Name    = 'granted'
            Title   = 'a valid record granting OS.EXECUTE - THE NULL-CASE CONTROL'
            Fixture = 'bytes'
            Content = "no`nyes`n"
            Grants  = $true
            WhyId   = ''
            Why     = ''
            Note    = 'byte for byte what CREATEA grant.os.access writes for an ADMINISTRATOR'
        },
        @{
            Name    = 'malformed'
            Title   = 'a record with no second field'
            Fixture = 'bytes'
            Content = 'yes'
            Grants  = $false
            WhyId   = 'PRIV_MALFORMED'
            Why     = 'the os.users record has no second field'
            Note    = 'op_sh.c:207 - strchr found no newline'
        },
        @{
            Name    = 'empty'
            Title   = 'a record of zero bytes'
            Fixture = 'bytes'
            Content = ''
            Grants  = $false
            WhyId   = 'PRIV_READ_FAILED'
            Why     = 'the os.users record could not be read'
            Note    = 'op_sh.c:197 - read() returned 0, which is n <= 0'
        },
        @{
            Name    = 'denied'
            Title   = 'a valid record the session may not open'
            Fixture = 'denied'
            Content = "no`nyes`n"
            Grants  = $false
            WhyId   = 'PRIV_OPEN_FAILED'
            Why     = 'the os.users record could not be opened'
            Note    = 'op_sh.c:191 - open() failed with an errno that is NOT ENOENT'
        }
    ) }
}

function Get-PrivUnreachable {
    # NOT A LIST OF EXCUSES.  It is printed every run, and the units test
    # asserts that these plus the WhyIds above plus PRIV_ANSWERED are EXACTLY
    # the PRIV_WHY enum - so a tenth member cannot appear without somebody
    # deciding which side of this line it is on.
    return @{ Unreachable = @(
        @{ WhyId = 'PRIV_NO_PASSWD'
           Because = 'getpwuid() must fail - on Cygwin that is a real name-service or domain-controller outage' },
        @{ WhyId = 'PRIV_NO_GROUP_COUNT'
           Because = 'getgrouplist() must fail to SIZE the list - same outage' },
        @{ WhyId = 'PRIV_NO_MEMORY'
           Because = 'malloc() must fail' },
        @{ WhyId = 'PRIV_NO_GROUP_LIST'
           Because = 'the list must size and then fail to FETCH - same outage' },
        @{ WhyId = 'PRIV_NO_USERNAME'
           Because = 'the session must have no user name, and no login route produces one' },
        @{ WhyId = 'PRIV_PATH_TOO_LONG'
           Because = 'sysdir is fixed and the record name is bounded by MAX_USERNAME_LEN, so it cannot overflow' }
    ) }
}

# ***COUNTS THE RESULT ROWS, AND IT IS A FUNCTION BECAUSE THE ONE-LINE VERSION
# OF IT REPORTED A FALSITY ON THIS SCRIPT'S FIRST REAL RUN.***  PRE_RELEASE 156.
# The closing line said "12 check(s) reported N/A - they were not measured" on
# a run where NOTHING was skipped and all 25 rows were measured.
#
# THE CAUSE IS THE ONE THIS TREE HAS ALREADY WRITTEN DOWN TWICE.  PowerShell's
# -eq coerces the RIGHT operand to the LEFT's type, so with Expected holding a
# BOOLEAN, "$true -eq 'n/a'" is $true -eq $true - TRUE.  Every check expecting
# $true counted as N/A; there were exactly twelve of them.  verify-delaccount.ps1
# caught it before its first run and verify-profiledir.ps1 carries the note
# forward; the fix is [string] on the left, and this file is the third copy of
# it because it is the third file to need it.
#
# IT IS LIFTED AND DRIVEN BY test-privundetermined-units.ps1, which is why this
# is a function rather than three lines at the foot of the file: the fix is
# proved for free, with a row that fails against the original form, instead of
# costing a second elevated run to look at a summary line.
function Get-ResultTally($rows) {
    $all   = @($rows)
    $asked = @($all | Where-Object { [string]$_.Expected -ne 'n/a' })
    $na    = @($all | Where-Object { [string]$_.Expected -eq 'n/a' })
    $pass  = @($asked | Where-Object { $_.Expected -eq $_.Observed })
    return @{
        Total = $all.Count
        Asked = $asked.Count
        Na    = $na.Count
        Pass  = $pass.Count
        Fail  = ($asked.Count - $pass.Count)
    }
}

# The one string priv_log_undetermined() writes.  Kept here so the units test
# can compare it against k_error.c's snprintf rather than against a copy of
# itself.
function Get-PrivMarker {
    return @{
        Prefix = 'PRIVILEGE CHECK UNDETERMINED'
        What   = 'OS.EXECUTE'
        Tail   = 'refused, but this is not a denial'
    }
}

# ---------------------------------------------------------------------------
# Everything below RUNS.  Nothing above it does.
# ---------------------------------------------------------------------------

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-privundetermined-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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

# N/A does NOT set $failed and does NOT count as a pass.  Same three-state
# treatment as verify-apiadmin.ps1, and for the same reason: a leg whose
# measurement could not be taken must not be reported as one that was.
function Skip($check, $why) {
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = 'n/a'; Observed = $why })
    Write-Host ("  [N/A ] {0}: {1}" -f $check, $why) -ForegroundColor Yellow
}

function Fail($msg) {
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

function Refuse($msg) {
    if ($script:failed) {
        Fail ($msg + '  (a decisive check had already FAILED, so this is exit 1, not 2)')
    }
    Write-Host ''
    Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# ICACLS THROUGH A WRAPPER, AND IT IS NOT TIDINESS.  Under
# $ErrorActionPreference='Stop' a native command writing ANYTHING to stderr is
# wrapped in a NativeCommandError that TERMINATES the script - the trap
# secure-account-dirs.ps1:95, verify-catgate.ps1:395 and secure-osusers.ps1 all
# carry a note about.  icacls says "Successfully processed N files" on stdout
# and goes to stderr the moment it is unhappy, so an unguarded call would kill
# the run at the leg it exists to measure, in a finally block, with no message.
function Invoke-Icacls([string[]]$icArgs) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = (& icacls.exe @icArgs 2>&1 | Out-String)
        $rc  = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEap }
    return @{ Rc = $rc; Text = $out }
}

# Drives a local SD session in a NAMED account.  Copied from verify-apiadmin.ps1,
# which carries the write-up: LOGIN re-inits terminal geometry on every account
# switch, so a TERM follows every LOGTO.
function Invoke-SDIn([string]$account, [string[]]$commands) {
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@("LOGTO $account", 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

function Invoke-SDSys([string[]]$commands) {
    return (Invoke-SDIn 'SDSYS' $commands)
}

# ONE REMOVAL FOR BOTH THROWAWAY ACCOUNTS, because there are two now and the
# second is a member of BUILTIN\Administrators.  Two copies of this would be
# two places for the administrator one to be removed less thoroughly.
#
# OUT OF THE GROUPS FIRST, BEFORE DELETE.ACCOUNT rather than relying on it.
# Removing the Windows user takes its memberships with it, so this is redundant
# on the happy path - but DELETE.ACCOUNT is exactly the step that sometimes does
# not finish, and an account left behind holding an API grant is the one piece
# of litter here that is a permission rather than a name.
function Remove-ThrowawayAccount([string]$name) {
    foreach ($g in @('sdapi', 'sdssh')) {
        try {
            if (Get-LocalGroupMember -Group $g -Member $name -ErrorAction SilentlyContinue) {
                Remove-LocalGroupMember -Group $g -Member $name -ErrorAction Stop
                Write-Host "   took $name out of $g"
            }
        } catch { }
    }

    # ***THE SECOND 'Y' IS DELIBERATE AND THE "Y is not in your VOC" IT PRODUCES
    # IS EVIDENCE, NOT NOISE.  DO NOT "FIX" IT.***  DELETE.ACCOUNT asks one
    # confirmation on the path taken here, so the first Y answers it and the
    # second arrives at the ":" prompt and is refused as a verb - which is
    # exactly what b114's transcript shows, twice.
    #
    # IT IS INSURANCE AGAINST THE ONE FAILURE THIS SCRIPT MUST NOT HAVE.  An
    # unanswered SD prompt HANGS the piped session, and PROJECT_STATUS section 6
    # records what that costs: a stray sd.exe that took an elevation to clear.
    # Trading a cosmetic refusal line for that risk is the wrong way round, and
    # the refusal line is also the POSITIVE EVIDENCE that only one prompt
    # appeared - if DELETE.ACCOUNT ever grows a second question, this line stops
    # appearing and the second Y is silently doing real work.
    # verify-apiadmin.ps1 passes the same pair for the same reason.
    try {
        $out = Invoke-SDSys @("DELETE.ACCOUNT $name", 'Y', 'Y')
        Write-Host $out
    } catch { Write-Host "   DELETE.ACCOUNT $name threw: $_" }

    $stillReg = Test-Path -LiteralPath (Join-Path $sysdir ('accounts\' + $name.ToUpper()))
    $stillWin = [bool](Get-LocalUser -Name $name -ErrorAction SilentlyContinue)
    # NAMED LOUDLY IF IT IS AN ADMINISTRATOR THAT SURVIVED.  A leftover
    # PROGRAMMER account is litter; a leftover member of BUILTIN\Administrators
    # with a generated password is not, and must not scroll past in the same
    # colour as the rest of the restore.
    if ($stillReg -or $stillWin) {
        $admin = $false
        try {
            $admin = [bool](Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -like ("*\" + $name) })
        } catch { }
        $colour = $(if ($admin) { 'Red' } else { 'Yellow' })
        Write-Host "   $name NOT fully removed - register:$stillReg windows:$stillWin" -ForegroundColor $colour
        if ($admin) {
            Write-Host "   *** $name IS STILL IN BUILTIN\Administrators.  Remove it by hand NOW. ***" -ForegroundColor Red
        }
        Write-Host "   Remove by hand before reusing this prefix." -ForegroundColor $colour
        return $false
    }
    Write-Host "   $name removed"
    return $true
}

function Stop-SD {
    if (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) {
        & "$env:SystemRoot\System32\sc.exe" stop $SvcName | Out-Null
    }
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    return -not [bool](Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue)
}

function Start-SD {
    & "$env:SystemRoot\System32\sc.exe" start $SvcName | Out-Null
    $deadline = (Get-Date).AddSeconds(45)
    while (-not (Get-Process -Name sdwind -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    return [bool](Get-Process -Name sdwind -ErrorAction SilentlyContinue)
}

# SD returns captured output as a dynamic array, so the probe's lines arrive
# separated by FIELD MARKS rather than newlines.  verify-apiadmin.ps1 carries
# the full write-up of what anchoring on ^ cost.
function Convert-ProbeText([string]$text) {
    return ($text -replace '[\u00FC-\u00FF\uFFFD]', "`n")
}

function Get-Marker([string]$text, [string]$name) {
    $m = [regex]::Match($text, ('PROBE\.' + [regex]::Escape($name) + '=([A-Za-z0-9_.\\-]*)'))
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# Read it with FileShare::ReadWrite - the daemon holds it open across its own
# write, and a plain Get-Content intermittently answers "in use by another
# process" rather than the contents.  Lifted from verify-peerlog.ps1.
function Get-ErrlogText {
    if (-not (Test-Path -LiteralPath $errlog)) { return '' }
    $fs = [System.IO.File]::Open($errlog, [System.IO.FileMode]::Open,
                                 [System.IO.FileAccess]::Read,
                                 [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}

# THE DELTA, AND IT REFUSES TO GUESS.  log_message() TRIMS THE FRONT OFF errlog
# when it reaches sysseg->errlog bytes (k_error.c:588) - it copies the back half
# over the front and truncates - so a plain "count after minus count before"
# can go NEGATIVE, or worse, can come out right by cancellation.  The only safe
# delta is one where the old text is still a PREFIX of the new; if it is not,
# the log rotated under the measurement and this returns Ok=$false so the caller
# reports N/A rather than a number nobody can stand behind.
function Get-ErrlogDelta([string]$before) {
    $after = Get-ErrlogText
    if ($after.Length -ge $before.Length -and $after.StartsWith($before, [System.StringComparison]::Ordinal)) {
        return @{ Ok = $true; Text = $after.Substring($before.Length) }
    }
    return @{ Ok = $false; Text = '' }
}

# ---------------------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Refuse 'Run this from an ELEVATED PowerShell - it creates an account, writes a record into sdsys\os.users, edits the installed sd.conf and restarts SD.'
}

Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current refuses - run gplbld/cycle.ps1 first.' }

if ($Prefix -notmatch '^[a-z][a-z0-9_]*$') {
    Refuse "-Prefix is '$Prefix'.  Lower case letters, digits and underscore only, starting with a letter."
}
if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
    Refuse "$Prefix already exists as a Windows account.  Use a -Prefix that does not."
}
if (Test-Path -LiteralPath (Join-Path $sysdir ('accounts\' + $Prefix.ToUpper()))) {
    Refuse ($Prefix.ToUpper() + ' is still in the ACCOUNTS register from an earlier run.  Use a fresh -Prefix.')
}
if (-not (Test-Path -LiteralPath $osUsers)) {
    Refuse "$osUsers does not exist - there is no permission list to vary, so nothing here could be measured."
}

# THE RECORD THIS RUN WILL WRITE, AND IT MUST NOT ALREADY BE THERE.  os.users
# is keyed on the WINDOWS LOGIN NAME (op_sh.c builds the path from
# process.username), and the account does not exist yet, so a file of that name
# is litter from an interrupted earlier run.  Overwriting it silently would be
# fine here and would teach the wrong habit on a list where a stray "yes" is a
# shell nobody granted.
$fixture = Join-Path $osUsers $Prefix
if (Test-Path -LiteralPath $fixture) {
    Refuse "$fixture already exists.  It is litter from an interrupted run - remove it, or use a fresh -Prefix."
}

# AND THE COMPOSITION STEP'S RECORD, WHICH WOULD POISON A PREMISE RATHER THAN
# A MEASUREMENT.  Step 8 asserts that CREATE.ACCOUNT WROTE that record; if a
# stale one is already there, grant.os.access leaves it exactly as it is and
# says so (10103), and the assertion would pass on somebody else's file.
# DELACC:394 removes it with the Windows user, so its presence means an earlier
# run died between the two.
$adminFixture = Join-Path $osUsers ($Prefix + 'a')
if (Test-Path -LiteralPath $adminFixture) {
    Refuse "$adminFixture already exists.  Step 8 would read it as CREATE.ACCOUNT's own work - remove it, or use a fresh -Prefix."
}

$bash = 'C:\msys64\usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) { Refuse "MSYS2 bash not found at $bash" }

$legs        = (Get-PrivLegs).Legs
$unreachable = (Get-PrivUnreachable).Unreachable
$marker      = Get-PrivMarker

# THE NULL CASE FOR THIS FILE'S OWN TABLE.  A Get-PrivLegs that came back empty
# would run no legs, fail nothing, and print a green summary of nothing at all.
if ($legs.Count -lt 2) {
    Refuse "the leg table holds $($legs.Count) leg(s) - there is nothing to measure."
}
if (@($legs | Where-Object { $_.Grants }).Count -ne 1) {
    Refuse 'the leg table has no single granting leg - without the null-case control every other leg is vacuous.'
}

Write-Host ''
Write-Host ("verify-privundetermined - PRE_RELEASE_FIXES.md 96, the privilege tri-state") -ForegroundColor Cyan
Write-Host ("  account : {0}  (SD: {1})" -f $Prefix, $Prefix.ToUpper())
Write-Host ("  record  : {0}" -f $fixture)
Write-Host ("  errlog  : {0}" -f $errlog)
Write-Host ("  port    : {0}" -f $Port)
Write-Host ("  legs    : {0} - {1}" -f $legs.Count, (($legs | ForEach-Object { $_.Name }) -join ', '))

$restoreNeeded = $false
$madeAccount   = $false
$madeAdmin     = $false
$madeFixture   = $false
$deniedAce     = $false
$pw            = ''

# DECLARED OUT HERE BECAUSE THE finally BLOCK READS IT.  Filled in at step 6,
# once the account exists and has a SID; a run that dies before then leaves it
# empty and the restore skips the ACL removal, which is correct - there is no
# ACE to remove.  Declaring it inside the try would leave finally reading $null
# and, under a strict mode inherited from a caller, throwing on the way out.
$sids = @{ account = ''; system = 'S-1-5-18' }

try {
    # -----------------------------------------------------------------------
    Step 1 "Creating the throwaway PROGRAMMER account $Prefix"

    # PROGRAMMER because it is the least privileged tier that still has RUN in
    # its VOC - a STANDARD account has no "basic", "ed" or "run" and could not
    # execute the probe at all.  It holds none of the administration verbs, so
    # anything it reaches, it reaches through os.users rather than through SD.
    #
    # NONE rather than API: the grant comes later, on its own, so that a failure
    # to reach the port cannot be confused with a failure to be admitted.
    Add-Type -AssemblyName System.Web
    $winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6)

    $out = Invoke-SDSys @("CREATE.ACCOUNT USER $Prefix PROGRAMMER NONE", $winPw, $winPw)
    $accRec = Join-Path $sysdir ('accounts\' + $Prefix.ToUpper())
    $made = Test-Path -LiteralPath $accRec
    Note 'accounts record created' $true $made
    if (-not $made) { Write-Host $out; Refuse 'CREATE.ACCOUNT did not register the account.' }
    $madeAccount = $true

    # AND IT MUST HAVE NO os.users RECORD OF ITS OWN.  grant.os.access returns
    # early unless os.sh or os.exec is set, and neither is on the PROGRAMMER
    # arm - so the "absent" leg below is the state CREATE.ACCOUNT actually
    # leaves, not one this script had to manufacture.  Asserted, because if
    # CREATEA ever starts writing one the absent leg silently becomes a
    # different test.
    Note 'CREATE.ACCOUNT left no os.users record' $false (Test-Path -LiteralPath $fixture)

    # -----------------------------------------------------------------------
    Step 2 'Setting its SD credential'

    $bytes = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + 'aA1'

    $out = Invoke-SDSys @(("MODIFY.PASSWORD " + $Prefix.ToUpper()), $pw, $pw)
    $set = ($out -match 'Password set for account')
    Note 'credential set' $true $set
    if (-not $set) { Write-Host $out; Refuse 'MODIFY.PASSWORD did not report success.' }

    # -----------------------------------------------------------------------
    Step 3 'Compiling apiosexecprobe into the account'

    $acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $Prefix)
    $bpDir   = Join-Path $acctDir 'bp'
    if (-not (Test-Path -LiteralPath $bpDir)) {
        Refuse "No bp directory at $bpDir - CREATE.ACCOUNT's layout has changed."
    }

    # THE SAME PROBE verify-apiadmin USES, unmodified.  It prints
    # PROBE.OSEXEC.TRIED before the attempt and PROBE.WHOAMI only if os.execute
    # RETURNED, and it is the one allowed to abort - which is what a refusal
    # does to it.
    Copy-Item -LiteralPath (Join-Path $Gplbld 'apiosexecprobe.sb') `
              -Destination (Join-Path $bpDir 'APIOSEXECPROBE') -Force

    # ANCHOR ON THE SUCCESS WORDING (PRE_RELEASE 105).  The probe NAME is
    # printed on the failure path too - sysmsg 2812 "Compiling %1 %2" before
    # bcomp runs and 2612 "Compilation error in %1" when it fails - so the name
    # proves the compile was attempted and never that it worked.  BCOMP:1540
    # prints "%1 error(s)" on both paths, so requiring "0 error(s)" fails a run
    # that printed no count at all.
    $out = Invoke-SDIn $Prefix.ToUpper() @('BASIC BP APIOSEXECPROBE')
    Write-Host $out
    $okCount = ([regex]::Matches($out, '\b0 error\(s\)')).Count
    $errSeen = ($out -match '[1-9][0-9]* error')
    Write-Host ("    compile: {0} '0 error(s)'; an error count was {1}" -f
                $okCount, $(if ($errSeen) { 'SEEN' } else { 'absent' }))
    $compiled = ($okCount -eq 1) -and (-not $errSeen)
    Note 'probe compiled' $true $compiled
    if (-not $compiled) { Refuse 'The probe did not compile - the output above says why.' }

    # -----------------------------------------------------------------------
    Step 4 'CONTROL: the probe can see OS.EXECUTE RUN (local, listed administrator)'

    # WITHOUT THIS THE API LEGS PROVE LESS THAN THEY LOOK.  Every refusal below
    # is read off SD's refusal message, and a refusal is only evidence if this
    # probe could have seen a success.  The local elevated session reaches
    # os_permitted through os.users keyed on THE PERSON running this - the
    # installing administrator, whose record CREATEA wrote (PRE_RELEASE 2) and
    # which a LOGTO does not change (op_sh.c:167) - so it runs.
    #
    # IT ALSO ESTABLISHES THAT THIS SCRIPT'S FIXTURES CANNOT DISTURB IT: the
    # local leg reads os.users\<the person>, the API legs read os.users\<the
    # throwaway account>.  Two different records, and this script only ever
    # writes the second.
    $localOut = Invoke-SDIn $Prefix.ToUpper() @('RUN BP APIOSEXECPROBE')
    Write-Host $localOut
    $localWho = Get-Marker $localOut 'WHOAMI'
    Write-Host ("    local whoami marker: '{0}'" -f $localWho)
    $localRefused = ($localOut -match 'not permitted to use OS\.EXECUTE')
    $localTried   = ($localOut -match 'PROBE\.OSEXEC\.TRIED') -or $localRefused
    Note 'control: the local probe reached the attempt' $true $localTried
    Note 'control: the probe CAN see OS.EXECUTE run'    $true ($localWho -ne '')
    if ($localWho -eq '') {
        Write-Host '   The local control did not run OS.EXECUTE.  Every refusal below is now' -ForegroundColor Yellow
        Write-Host '   consistent with a blind probe, so read the API legs with that in mind.' -ForegroundColor Yellow
    }

    # -----------------------------------------------------------------------
    Step 5 "Enabling APIPORT=$Port and restarting SD"

    Copy-Item -LiteralPath $conf -Destination $backup -Force
    $restoreNeeded = $true
    $lines = @(Get-Content -LiteralPath $conf) | Where-Object { $_ -notmatch '^\s*APIPORT\s*=' }
    $lines += ('APIPORT=' + $Port)
    Set-Content -LiteralPath $conf -Value $lines -Encoding Ascii

    # read_config() runs only when the shared segment is CREATED, so it has to
    # be a restart rather than a reload.
    if (-not (Stop-SD))  { Refuse 'SD would not stop - close any open session and try again.' }
    if (-not (Start-SD)) { Refuse 'SD would not start again.  Read the SD error log.' }
    Start-Sleep -Seconds 2

    $listen = @(netstat -an | Select-String 'LISTENING' |
                Where-Object { $_ -match (':' + $Port + '\s') })
    Note 'a listener on the port' $true ($listen.Count -gt 0)
    foreach ($l in $listen) { Write-Host ('   ' + $l.ToString().Trim()) }
    if ($listen.Count -eq 0) { Refuse "Nothing is listening on port $Port." }

    # -----------------------------------------------------------------------
    Step 6 "Granting the API: MODIFY.ACCOUNT $($Prefix.ToUpper()) API"

    $out = Invoke-SDSys @(("MODIFY.ACCOUNT " + $Prefix.ToUpper() + " API"))
    $inApi = [bool](Get-LocalGroupMember -Group 'sdapi' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like ("*\" + $Prefix) })
    Note 'MODIFY.ACCOUNT ... API put it in sdapi' $true $inApi
    if (-not $inApi) { Write-Host $out; Refuse 'the account was not granted the API - nothing below can be measured.' }

    # -----------------------------------------------------------------------
    # C:\a\b -> /c/a/b
    $msys = '/' + $Sd64.Substring(0, 1).ToLower() + ($Sd64.Substring(2) -replace '\\', '/')
    $apiCmd = "cd '$msys' && make check-api-admin APIHOST=127.0.0.1 APIPORT=$Port " +
              "APIUSER=$Prefix APIPASS='$pw' APIACCT=" + $Prefix.ToUpper() +
              " APICMD='RUN BP APIOSEXECPROBE'"
    Write-Host ''
    Write-Host 'The command each leg runs, once, verbatim:' -ForegroundColor DarkGray
    Write-Host ("   $bash -lc " + $apiCmd) -ForegroundColor DarkGray

    # 2>&1 ON A NATIVE COMMAND UNDER $ErrorActionPreference='Stop' is the trap
    # this project has been bitten by three times - secure-account-dirs.ps1:95,
    # verify-catgate.ps1:395 and verify-apiadmin.ps1.  PowerShell 5.1 wraps each
    # stderr line in a NativeCommandError and TERMINATES, and make writes to
    # stderr routinely, so without this the script dies at the step it exists to
    # perform and a run that never reached the verdict reads like a passing one.
    function Invoke-ApiProbe {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $t = (& $bash -lc $apiCmd 2>&1 | Out-String)
        } finally { $ErrorActionPreference = $prevEap }
        return (Convert-ProbeText $t)
    }

    # Writes the leg's record.  ASCII BYTES, NOT Set-Content: a BOM would put
    # three bytes in front of field 1 and, on the malformed leg, would be the
    # difference between "no newline" and "no newline plus rubbish".  LF only,
    # which is what SD's own write to a DIRECTORY file produces.
    function Set-Fixture($leg) {
        if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Force }
        if ($leg.Fixture -eq 'none') { return $false }
        [System.IO.File]::WriteAllBytes($fixture,
            [System.Text.Encoding]::ASCII.GetBytes($leg.Content))
        return $true
    }

    # S-1-5-18 IS LocalSystem AND BOTH ARE SPELT AS SIDs ON PURPOSE.  "NT
    # AUTHORITY\SYSTEM" is localised, and icacls on a non-English Windows would
    # refuse a name this file had hard-coded in English.
    $sids['account'] = (Get-LocalUser -Name $Prefix).SID.Value

    Write-Host ''
    Write-Host ("   account SID: {0}" -f $sids['account']) -ForegroundColor DarkGray

    # -----------------------------------------------------------------------
    foreach ($leg in $legs) {

        Step ('7.' + $leg.Name) ("LEG " + $leg.Name + ' - ' + $leg.Title)
        Write-Host ("   ({0})" -f $leg.Note) -ForegroundColor DarkGray

        # --- the fixture, and what it actually is on disk afterwards.
        $madeFixture = Set-Fixture $leg
        if ($leg.Fixture -eq 'denied') {
            # BOTH IDENTITIES, AND THE REASON IS THAT THEY ARE BOTH REAL.  The
            # API session's file access runs IMPERSONATED as the user - that is
            # what verify-apiidentity.ps1 measures - while the process token is
            # still LocalSystem, which is what verify-apiadmin.ps1 measures.
            # Denying both means this leg does not depend on which of the two
            # os_permitted()'s open() happens to be under, and a change to that
            # answer cannot silently turn the leg into a no-op.
            foreach ($k in @('account', 'system')) {
                $r = Invoke-Icacls @($fixture, '/deny', ('*' + $sids[$k] + ':(R)'))
                if ($r.Rc -ne 0) { Write-Host ('   icacls /deny ' + $sids[$k] + ' exit ' + $r.Rc + ': ' + $r.Text) -ForegroundColor Yellow }
            }
            $deniedAce = $true
            # THE ACL AS IT ACTUALLY IS, printed rather than assumed.  If the
            # deny did not land, this leg's record is a VALID grant and
            # OS.EXECUTE will RUN - which fails the leg loudly instead of
            # coinciding with some other refusal and reading as a pass.
            Write-Host ('   ' + ((Invoke-Icacls @($fixture)).Text.TrimEnd() -replace "`r?`n", "`n   "))
        }

        if ($madeFixture) {
            $onDisk = [System.IO.File]::ReadAllBytes($fixture)
            Write-Host ("   record: {0} byte(s) - {1}" -f $onDisk.Length,
                        $(if ($onDisk.Length -eq 0) { '(empty)' }
                          else { (($onDisk | ForEach-Object { $_.ToString('x2') }) -join ' ') }))
        } else {
            Write-Host '   record: not present'
        }

        # --- the measurement.
        $before = Get-ErrlogText
        $out    = Invoke-ApiProbe
        Write-Host $out
        # The refusal is written by sh() BEFORE k_error() reports to the client,
        # so by the time the client has its answer the line is already in the
        # log.  The settle is for the filesystem, not for the ordering.
        Start-Sleep -Milliseconds 750
        $delta = Get-ErrlogDelta $before

        $who     = Get-Marker $out 'WHOAMI'
        $ran     = ($who -ne '')
        $refused = ($out -match ([regex]::Escape($Prefix) + ' is not permitted to use OS\.EXECUTE'))

        Write-Host ("   whoami marker: '{0}'   refused-by-name: {1}" -f $who, $refused)

        # DID THE SESSION HAPPEN AT ALL?  Everything below reads an outcome off
        # this one run, and "ran" and "refused" being BOTH false is a session
        # that never started - a dropped connection, a login refusal, a probe
        # that is no longer there.  That is the null case, and it is refused by
        # name rather than reported as a quiet pass on the "did not run" row.
        if (-not ($ran -or $refused)) {
            Write-Host '   Neither outcome marker came back - the session did not reach the probe.' -ForegroundColor Yellow
            Skip ("leg " + $leg.Name + ': OS.EXECUTE outcome') 'the API session never reached the attempt'
            Skip ("leg " + $leg.Name + ': errlog') 'no attempt was made, so there is nothing to have logged'
            continue
        }

        # --- (1) the grant.
        Note ("leg " + $leg.Name + ': OS.EXECUTE runs') $leg.Grants $ran
        # A leg that neither ran nor was refused is already gone; a leg that did
        # not run must have been refused BY NAME, which is SD saying so rather
        # than this script inferring it from an absence.
        if (-not $leg.Grants) {
            Note ("leg " + $leg.Name + ': refused BY NAME') $true $refused
        }

        # --- (2) the log line.
        if (-not $delta.Ok) {
            # k_error.c:588 trims the front off errlog when it fills.  A delta
            # taken across a trim is not a delta.
            Skip ("leg " + $leg.Name + ': errlog') 'the error log TRIMMED during this leg - the delta is not readable'
            continue
        }

        $newLines = @($delta.Text -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($marker.Prefix) })
        Write-Host ("   errlog grew by {0} byte(s); {1} UNDETERMINED line(s) in the new text" -f
                    $delta.Text.Length, $newLines.Count)
        foreach ($l in $newLines) { Write-Host ('     ' + $l.Trim()) -ForegroundColor DarkGray }

        # THE LOG HAS TO BE LIVE FOR AN ABSENCE TO MEAN ANYTHING.  Every leg
        # opens an API connection and sdwind records it, so a delta of nothing
        # at all is a log that is not being written - under which "0 lines" is
        # not a measurement of silence, it is a measurement of nothing.
        if ($delta.Text.Length -eq 0) {
            Skip ("leg " + $leg.Name + ': errlog') 'the error log did not grow AT ALL this leg, so its silence proves nothing'
            continue
        }

        if ($leg.Why -eq '') {
            Note ("leg " + $leg.Name + ': writes NO undetermined line') 0 $newLines.Count
        } else {
            Note ("leg " + $leg.Name + ': writes ONE undetermined line') 1 $newLines.Count

            # ANCHOR ON THE WORDING THE POSITIVE PATH PRINTS, and on all three
            # parts of it.  The reason string alone appears nowhere else, but
            # requiring the "what" and the tail too means a line written by some
            # other predicate - USR_ADMIN at session start, K$OS.ADMINISTRATOR -
            # cannot be counted as this one.
            $hit = @($newLines | Where-Object {
                        $_.Contains($marker.Prefix) -and
                        $_.Contains($marker.What)   -and
                        $_.Contains($leg.Why)       -and
                        $_.Contains($marker.Tail) })
            Note ("leg " + $leg.Name + ': the line names ' + $leg.WhyId) 1 $hit.Count
        }
    }

    # -----------------------------------------------------------------------
    Step 8 'THE COMPOSITION: an ADMINISTRATOR-tier account, no fixture at all'

    # ***THIS IS NOT A LEG AND IT IS DELIBERATELY NOT IN THE LEG TABLE.***  Every
    # leg above varies the RECORD for one account.  This varies the ACCOUNT and
    # writes no record at all - the whole point is that this script touches
    # nothing and the product supplies the state by itself.
    #
    # WHAT IT COMPOSES, AND EVERY LINK IS SEPARATELY GREEN ALREADY:
    #
    #   CREATEA:1731-1732  an ADMINISTRATOR-tier account gets os.sh=yes AND
    #                      os.exec=yes in os.users, unconditionally.  Owner,
    #                      27 Aug 2026: "administrators have full access, there
    #                      should be no way to turn it off."
    #   CREATEA:1718-1721  the same account joins sdapi and sdssh with NO
    #                      keyword, and MODIFY.ACCOUNT refuses to remove either
    #                      (10083).  Owner, 21 Aug 2026: "all administrators
    #                      have access to both ssh and api".
    #   verify-tierapi     an ADMINISTRATOR-tier account logs in over SCRAM and
    #                      attaches to its own account.  Green suite step.
    #   kernel.c:253       a CN_SOCKET session never gets USR_ADMIN, so
    #                      os_permitted() falls through to that record.
    #   the 'granted' leg  an API session whose record says yes RUNS os.execute.
    #   verify-apiadmin    when it runs over the API it reports itself SYSTEM.
    #
    # ***SO THE COMPOSITION HAS NEVER BEEN RUN END TO END, WHILE EVERY ONE OF ITS
    # LINKS HAS.***  That is the gap this step closes, and it is the reason it
    # writes no fixture: a finding here is the product's own configuration, not
    # one this script arranged.
    #
    # ***THE OUTCOME IS SCORED, AND IT BECAME SCORABLE ON 4 Sep 2026 WHEN THE
    # OWNER RULED ON IT.***  Shown the b113 measurement, he said "157 Accept it",
    # so a remote administrator reaching the operating system is now STATED
    # POLICY rather than an open question - and a policy is something a verifier
    # may assert.
    #
    # WHILE IT WAS UNSCORED THIS STEP ONLY REPORTED.  It now guards, and the
    # direction it guards is the one nobody would think to watch: the obvious
    # "fix" here is to withhold os.execute from a CN_SOCKET session the way
    # kernel.c:253 withholds USR_ADMIN, and that fix would make the SHIPPED
    # DOCUMENTATION FALSE.  80 has to say this happens; this row is what notices
    # if it stops.
    #
    # ENTRY 64 IS SATISFIED RATHER THAN SIDESTEPPED: it forbids flipping an
    # Expected to match what was OBSERVED, and the row below is a differently
    # named claim about what was RULED - the same treatment verify-apiadmin.ps1
    # gave its own OS.EXECUTE row on 29 Aug, for the same reason.

    $adminAcct = $Prefix + 'a'
    if (Get-LocalUser -Name $adminAcct -ErrorAction SilentlyContinue) {
        Skip 'composition: an ADMINISTRATOR-tier account' "$adminAcct already exists as a Windows account"
    } else {

        # NO ACCESS KEYWORD, AND ITS ABSENCE IS HALF THE MEASUREMENT.  CREATEA
        # sets access.given for this tier so no keyword is needed, and 10083
        # refuses one that tries to take ssh or the API away.  If this script
        # passed API here it would be arranging the very thing it claims the
        # product arranges by itself.
        $winPw2 = [System.Web.Security.Membership]::GeneratePassword(24, 6)
        $out = Invoke-SDSys @("CREATE.ACCOUNT USER $adminAcct ADMINISTRATOR", $winPw2, $winPw2)
        Write-Host $out
        $madeAdmin = Test-Path -LiteralPath (Join-Path $sysdir ('accounts\' + $adminAcct.ToUpper()))
        Note 'composition: the ADMINISTRATOR account was created' $true $madeAdmin

        if ($madeAdmin) {
            # --- the premise, READ OFF DISK rather than taken from the source.
            $adminRec  = Join-Path $osUsers $adminAcct
            $recExists = Test-Path -LiteralPath $adminRec
            Note 'composition: CREATE.ACCOUNT wrote it an os.users record' $true $recExists
            $field2 = ''
            if ($recExists) {
                $txt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($adminRec))
                Write-Host ("   os.users\{0}: {1}" -f $adminAcct, ($txt -replace "`r?`n", ' | '))
                $nl = $txt.IndexOf("`n")
                if ($nl -ge 0) {
                    $field2 = ($txt.Substring($nl + 1) -split "[`r`n]")[0].Trim()
                }
            }
            Note 'composition: its OS.EXECUTE field says yes' 'yes' $field2.ToLower()

            # --- and sdapi membership NOBODY GRANTED.  Step 6 had to ask for the
            # PROGRAMMER account; this one is expected to be in it already.
            $adminInApi = [bool](Get-LocalGroupMember -Group 'sdapi' -ErrorAction SilentlyContinue |
                                 Where-Object { $_.Name -like ("*\" + $adminAcct) })
            Note 'composition: it is in sdapi with NO keyword given' $true $adminInApi

            $bytes2 = New-Object byte[] 18
            ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes2)
            $pw2 = ([Convert]::ToBase64String($bytes2) -replace '[^A-Za-z0-9]', '') + 'aA1'
            $out = Invoke-SDSys @(("MODIFY.PASSWORD " + $adminAcct.ToUpper()), $pw2, $pw2)
            Note 'composition: credential set' $true ($out -match 'Password set for account')

            $bpDir2 = Join-Path $env:ProgramData ('SD\user_accounts\' + $adminAcct + '\bp')
            if (Test-Path -LiteralPath $bpDir2) {
                Copy-Item -LiteralPath (Join-Path $Gplbld 'apiosexecprobe.sb') `
                          -Destination (Join-Path $bpDir2 'APIOSEXECPROBE') -Force
                $out = Invoke-SDIn $adminAcct.ToUpper() @('BASIC BP APIOSEXECPROBE')
                $ok2 = (([regex]::Matches($out, '\b0 error\(s\)')).Count -eq 1) -and
                       (-not ($out -match '[1-9][0-9]* error'))
                Note 'composition: probe compiled in the administrator account' $true $ok2

                if ($ok2) {
                    $adminCmd = "cd '$msys' && make check-api-admin APIHOST=127.0.0.1 APIPORT=$Port " +
                                "APIUSER=$adminAcct APIPASS='$pw2' APIACCT=" + $adminAcct.ToUpper() +
                                " APICMD='RUN BP APIOSEXECPROBE'"
                    Write-Host ("   $bash -lc " + $adminCmd) -ForegroundColor DarkGray
                    $prevEap = $ErrorActionPreference
                    $ErrorActionPreference = 'Continue'
                    try { $aOut = (& $bash -lc $adminCmd 2>&1 | Out-String) }
                    finally { $ErrorActionPreference = $prevEap }
                    $aOut = Convert-ProbeText $aOut
                    Write-Host $aOut

                    # PROBE.CONNECT COMES FROM THE C CLIENT (api_admin_probe.c:64),
                    # not from the BASIC, so it is available whatever APICMD ran.
                    $aConnect = Get-Marker $aOut 'CONNECT'
                    $aWho     = Get-Marker $aOut 'WHOAMI'
                    $aRefused = ($aOut -match ([regex]::Escape($adminAcct) + ' is not permitted to use OS\.EXECUTE'))
                    $aTried   = ($aOut -match 'PROBE\.OSEXEC\.TRIED') -or $aRefused -or ($aWho -ne '')

                    # SCORED, because verify-tierapi already says this is true and
                    # a False here would contradict a green suite step rather than
                    # settle a policy question.
                    Note 'composition: the API ADMITTED an ADMINISTRATOR-tier account' 'YES' $aConnect
                    Note 'composition: the probe reached the attempt' $true $aTried

                    # ***A ROW WAS DELETED HERE AND THE REASON IS WORTH KEEPING.***
                    # PRE_RELEASE 158.  It read
                    #
                    #   Note 'composition: it landed in its OWN account, not SDSYS' `
                    #        $adminAcct.ToUpper() (Get-Marker $aOut 'ACCOUNT')
                    #
                    # and it SCORED FAIL on b113 against an account that had landed
                    # exactly where it should.  PROBE.ACCOUNT is printed by
                    # apiadminprobe.sb:31 (crt 'PROBE.ACCOUNT=' : @who) and this step
                    # runs APIOSEXECPROBE, which never emits it - so the marker was
                    # always empty and the row COULD NEVER PASS.  Same class as the
                    # rows verify-apiadmin.ps1 and test-wraptext-units.ps1 each had to
                    # delete: a check that cannot pass is as useless as one that
                    # cannot fail, and this one manufactured a red on a green run.
                    #
                    # NOT REPLACED BY ADDING THE MARKER TO THE PROBE.  apiosexecprobe
                    # is shared with verify-apiadmin, a green step, and the marker
                    # would be discarded by the abort on the refusal path anyway - so
                    # it would still be absent in the case where it mattered.  THE
                    # CLAIM IS ALSO ALREADY SOMEBODY ELSE'S: verify-tierapi asserts
                    # that one tier cannot enter another's account, and attaching to
                    # APIACCT is entailed by PROBE.CONNECT=YES above.

                    # ***NOW SCORED, AND THE OWNER'S RULING OF 4 Sep 2026 IS WHAT
                    # MADE IT SCORABLE.  HE WAS SHOWN THE b113 MEASUREMENT AND SAID
                    # "157 Accept it".***
                    #
                    # IT IS NOT A FLIPPED EXPECTED VALUE, WHICH ENTRY 64 FORBIDS BY
                    # NAME.  64 forbids changing an Expected to match what was
                    # OBSERVED; this is a claim about what was RULED, and it is a
                    # differently-named row rather than the old one turned round -
                    # the same treatment, for the same reason, that
                    # verify-apiadmin.ps1's OS.EXECUTE row was given on 29 Aug when
                    # the owner ruled on os.users.  While it was unscored this step
                    # only reported; now it GUARDS.
                    #
                    # ***WHAT A FAILURE HERE MEANS IS THE WHOLE VALUE OF THE CHANGE:
                    # SOMEBODY CLOSED THIS WITHOUT A RULING.***  An administrator
                    # reaching the operating system over the API is accepted
                    # behaviour and 80 documents it, so a future change that
                    # withholds os.execute from a CN_SOCKET session - the obvious
                    # fix, and the one deliberately NOT taken - would silently make
                    # the shipped documentation false.  This row is what notices.
                    Note 'composition: the RULED behaviour - a remote administrator reaches the OS' `
                         $true ($aWho -ne '')

                    Write-Host ''
                    if ($aWho -ne '') {
                        Write-Host 'COMPOSITION RESULT: OS.EXECUTE ran in a remote API session - AS RULED.' -ForegroundColor Cyan
                        Write-Host ('  on an ADMINISTRATOR-tier account this script gave NO keyword and NO record.') -ForegroundColor Cyan
                        Write-Host ('  It reported its identity as: ' + $aWho) -ForegroundColor Cyan
                        Write-Host '  Three rulings compose to produce this: an administrator always has the API' -ForegroundColor Cyan
                        Write-Host '  (21 Aug), always has os.execute (27 Aug), and os.users is the authority' -ForegroundColor Cyan
                        Write-Host '  below USR_ADMIN (op_sh.c).  The port is reachable off-machine over ssh -L.' -ForegroundColor Cyan
                        Write-Host '  ACCEPTED BY THE OWNER, 4 Sep 2026.  PRE_RELEASE_FIXES 157; the API page' -ForegroundColor Cyan
                        Write-Host '  must say so in plain words, which is 80.' -ForegroundColor Cyan
                    } elseif ($aRefused) {
                        Write-Host 'COMPOSITION RESULT: OS.EXECUTE was REFUSED by name - THE RULED BEHAVIOUR HAS CHANGED.' -ForegroundColor Red
                        Write-Host '  This was ACCEPTED on 4 Sep 2026 and the shipped documentation says it happens.' -ForegroundColor Red
                        Write-Host '  Read the refusal above, then correct PRE_RELEASE_FIXES 157 AND the API page' -ForegroundColor Red
                        Write-Host '  under 80 - a silent close leaves the documentation false.' -ForegroundColor Red
                    } else {
                        Write-Host 'COMPOSITION RESULT: undetermined - the probe never reached the attempt.' -ForegroundColor Yellow
                    }
                }
            } else {
                Skip 'composition: probe compiled in the administrator account' "no bp directory at $bpDir2"
            }
        }

        # ***REMOVED HERE AND NOT ONLY IN THE finally.***  This account is in
        # BUILTIN\Administrators (CREATEA:858) - a real local administrator with
        # a password - so the window it exists for is kept to this step rather
        # than to the rest of the run.  The finally is the backstop, not the plan.
        # ***THIS BLOCK SCORED FAIL ON b113 ON A RUN WHERE THE ACCOUNT WAS
        # CORRECTLY REMOVED, AND IT REUSED $madeAdmin FOR TWO OPPOSITE MEANINGS.***
        # PRE_RELEASE 158.  It read
        #
        #   $madeAdmin = -not [bool](Get-LocalUser ...)
        #   Note '...removed again' $false $madeAdmin
        #
        # so $madeAdmin - which every other site reads as "there is an account to
        # clean up" - was assigned a value meaning "it is GONE", and then compared
        # against $false.  Removal therefore scored FAIL, and the finally block
        # would have re-run the removal on an account that no longer existed.
        # A separate, positively-named variable, and the expectation the right way
        # round.
        if ($madeAdmin) {
            # $null = BECAUSE THE RETURN VALUE LEAKED INTO THE TRANSCRIPT.
            # Measured on b114: a bare "True" printed on its own line after
            # "sdpwb114a removed", with nothing to say what it was a claim about.
            # An unlabelled boolean in a transcript is the opposite of what
            # CLAUDE.md's instrument section asks for, and it is this project's
            # own "a function's return value joins its output" trap - the
            # function reports through Write-Host and its bool is for callers
            # that ask, which none of the three do.
            $null = Remove-ThrowawayAccount $adminAcct
            $adminGone = -not [bool](Get-LocalUser -Name $adminAcct -ErrorAction SilentlyContinue)
            Note 'composition: the ADMINISTRATOR account was removed again' $true $adminGone
            $madeAdmin = -not $adminGone
        }
    }

    # -----------------------------------------------------------------------
    Step 9 'What this run did NOT reach'

    # PRINTED EVERY RUN, PASS OR FAIL.  A green summary above is a claim about
    # three of the nine undetermined paths and about the silence of the answered
    # ones.  Leaving the other six to be remembered is how "96 is covered" would
    # become true-sounding and false.
    Write-Host ''
    Write-Host ("   {0} of the 9 undetermined paths were EXERCISED here:" -f
                @($legs | Where-Object { $_.WhyId -ne '' }).Count) -ForegroundColor Cyan
    foreach ($l in @($legs | Where-Object { $_.WhyId -ne '' })) {
        Write-Host ("     {0,-20} leg '{1}'" -f $l.WhyId, $l.Name)
    }
    Write-Host ''
    Write-Host ("   {0} were NOT, and cannot be from here:" -f $unreachable.Count) -ForegroundColor Yellow
    foreach ($u in $unreachable) {
        Write-Host ("     {0,-20} {1}" -f $u.WhyId, $u.Because) -ForegroundColor Yellow
    }
}
finally {
    Write-Host ''
    Write-Host '== [restore] Undoing everything this run created' -ForegroundColor Cyan

    # THE RECORD FIRST, AND THE DENY ACE BEFORE THE RECORD.  os.users is the
    # list that decides who gets a shell; a "yes" left in it under a name that
    # is about to be deleted, or a deny ACE left on a path a later run reuses,
    # are both worse litter than an account name in a register.
    if (Test-Path -LiteralPath $fixture) {
        if ($deniedAce) {
            foreach ($s in @($sids['account'], $sids['system'])) {
                if ($s) { $null = Invoke-Icacls @($fixture, '/remove:d', ('*' + $s)) }
            }
        }
        Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $fixture) {
        Write-Host ("   COULD NOT REMOVE $fixture - delete it by hand before the next run.") -ForegroundColor Red
    } else {
        Write-Host '   os.users record removed'
    }

    if ($restoreNeeded -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $conf -Force
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        Write-Host '   sd.conf restored'
        if (Stop-SD) { $null = Start-SD }
    }

    # ***THE ADMINISTRATOR ONE FIRST, AND THAT ORDERING IS THE WHOLE POINT OF
    # DOING IT HERE AT ALL.***  Step 8 already removed it on the happy path;
    # this is the backstop for a run that died inside that step, and it goes
    # first because it is the only account here that is a member of
    # BUILTIN\Administrators (CREATEA:858).
    if ($madeAdmin) { $null = Remove-ThrowawayAccount ($Prefix + 'a') }
    if ($madeAccount) { $null = Remove-ThrowawayAccount $Prefix }
}

Write-Host ''
$results | Format-Table -AutoSize

$tally = Get-ResultTally $results
if ($tally.Asked -eq 0) {
    Write-Host 'verify-privundetermined: NOTHING WAS ASKED - a run that measured nothing is not a green run.' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
if ($tally.Na -gt 0) {
    Write-Host ("{0} check(s) reported N/A - they were not measured, and are neither passes nor failures." -f $tally.Na) -ForegroundColor Yellow
}
Write-Host ("verify-privundetermined: {0} PASS + {1} N/A of {2}" -f $tally.Pass, $tally.Na, $tally.Total) `
    -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
try { Stop-Transcript | Out-Null } catch { }
exit $(if ($failed) { 1 } else { 0 })
