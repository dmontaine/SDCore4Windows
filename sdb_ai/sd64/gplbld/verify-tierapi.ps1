<#
.SYNOPSIS
    Can a client reach all three account tiers over the API, and is it stopped
    from reaching one it should not?

.DESCRIPTION
    THE POINT IS THE CLIENT IT USES.  This drives sd-connect.exe, which links
    against the 32-bit qmclilib.dll in ..\sdclilib32 - the same file
    mvDeveloper loads.  So "mvDeveloper can connect as a standard user" stops
    being an inference about the protocol and becomes a reading of the actual
    library, without needing anyone at a GUI.

    WHAT IT ESTABLISHES, and the last two are the ones that matter:

      - a STANDARD, a PROGRAMMER and an ADMINISTRATOR account can each log in
        over SCRAM and attach to their own account
      - what each tier can DO once in, as a VOC count: 355 / 397 / 420.  A
        standard account connects perfectly well and then has no BASIC, ED or
        RUN, which is the answer to "can a standard user use mvDeveloper"
      - a wrong password is refused, so the successes mean something
      - ONE TIER CANNOT ENTER ANOTHER'S ACCOUNT.  vb.account applies the
        ACC$GROUP check; without this the three successes above would only
        show that three accounts exist

    THE TIER DOES NOT GATE THE LOGIN AND IS NOT MEANT TO.  Nothing in the
    SCRAM exchange or in vb.account consults the VOC, so a standard account is
    expected to connect.  If that ever changes, this test is what notices.

    IT CHANGES THE INSTALLED SYSTEM AND PUTS IT BACK, as verify-apiport.ps1
    does: three throwaway accounts, APIPORT in sd.conf if it was not already
    on, and SD restarted.  The restore runs in a finally block.

    THE PASSWORDS GO ON sd-connect's COMMAND LINE, which puts them in the
    process list.  That is sd-connect's interface, not a choice made here, and
    it is why these are generated single-use passwords on accounts this script
    deletes.  Never point it at a real one.  (MODIFY.PASSWORD itself refuses a
    password on its command line - see verify-setpw.ps1.)

.PARAMETER Prefix
    Base name for three throwaway accounts, <Prefix>1..3.  Use one nobody has
    used - CREATE.ACCOUNT refuses a name it has seen.

.EXAMPLE
    gplbld\verify-tierapi.ps1 -Prefix sdtapi1
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# 03 Sep 26 - THAT SENTENCE IS NEW HERE, AND THE THIRD CODE HAD NEVER BEEN
# USED.  PRE_RELEASE_FIXES.md 151.  Twelve other verifiers state this
# convention in their own headers; the six API ones stated nothing and left
# every precondition refusal through Fail() at exit 1 - which in a suite
# summary is indistinguishable from a check that ran and failed.  See Refuse().

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [int]    $Port = 4243,
    [string] $SdConnect = 'C:\Users\dmont\Projects\sdclilib32\sd-connect.exe',
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$conf    = Join-Path $env:ProgramData 'SD\sd.conf'
$backup  = $conf + '.before-tierapi'
$SvcName = 'SD'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-tierapi-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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
    Write-Host ''; Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
# 03 Sep 26 - PRE_RELEASE_FIXES.md 151.  A PRECONDITION REFUSAL IS NOT A FAILED
# CHECK, and until now both left through Fail() at exit 1.  Run b106 showed six
# API verifiers "exit 1" in a block, which reads as "the API is broken" - and
# NOT ONE OF THEM HAD MEASURED ANYTHING.  All six had refused on
# assert-current because a source file was written while the run was in flight.
#
# IT DOWNGRADES TO 1 IF A DECISIVE CHECK HAS ALREADY FAILED, and that is the
# half that is easy to get wrong.  Several stop-sites below sit immediately
# after a Note() that has already recorded a [FAIL] - there the fixture step IS
# a decisive check - and exiting 2 there would file a real failure under "could
# not run", which is the more dangerous direction of the two.  So the helper
# asks the run's own state rather than trusting the call site to be a
# precondition.
function Refuse($msg) {
    if ($script:failed) {
        Fail ($msg + '  (a decisive check had already FAILED, so this is exit 1, not 2)')
    }
    Write-Host ''; Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

function Invoke-SD([string[]]$commands) {
    # LOGIN re-inits terminal geometry on every account switch (LOGIN:201-209),
    # so the initial TERM below is wiped by any LOGTO in $commands and long
    # LIST/COUNT output paginates on a stdin the pipe can no longer answer.
    # Full write-up in verify-tiers.ps1's Invoke-SD.
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}
function Get-VocCount($text) {
    if ($text -match '(\d+)\s+record\(s\) counted') { return [int]$Matches[1] }
    return -1
}
function Stop-SD { if ((Get-Service $SvcName).Status -eq 'Running') { & sc.exe stop $SvcName | Out-Null; Start-Sleep -Seconds 3; return $true }; return $false }
function Start-SD { & sc.exe start $SvcName | Out-Null; Start-Sleep -Seconds 4 }

# Runs sd-connect and answers only "did the login succeed".  Its exit code is
# 0 for a connect, 1 for a refusal, 2 for bad usage - so 2 is a broken call
# here and must never be read as a refusal.
function Test-Connect([string]$user, [string]$pw, [string]$account) {
    $o = & $SdConnect '127.0.0.1' "$Port" $user $pw $account 2>&1
    $rc = $LASTEXITCODE
    if ($rc -eq 2) { Write-Host ($o -join "`n"); Refuse 'sd-connect rejected its arguments - this is a bug in this script, not a refusal.' }
    Write-Host ('     sd-connect: ' + (($o | Select-String -Pattern '  ok |  FAILED') -join '; '))
    return ($rc -eq 0)
}

# ---------------------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Refuse 'Run this from an ELEVATED PowerShell - CREATE.ACCOUNT and MODIFY.PASSWORD for another account are both gated on administrator.'
}

Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current refuses - run gplbld/cycle.ps1 first.' }

if (-not (Test-Path -LiteralPath $SdConnect)) {
    Refuse ("sd-connect.exe not found at $SdConnect.  Build it: make sd-connect.exe in the sdclilib32 project. " +
          "It is the 32-bit client, which is the whole reason this test uses it.")
}

$Tiers = @(
    # 30 Aug 26 - STANDARD 354 -> 355, PRE_RELEASE_FIXES.md 7.  sort.item left
    #   TIER.OMIT.STANDARD; it and list.item are $QPROC verbs 11 and 10, one
    #   program, and the 24 Aug ruling named only list.item.
    #   ***THIS FILE IS THE ONE THAT GETS LEFT BEHIND*** - twice now, 28 and 30
    #   Aug - so test-tiercounts-units.ps1 was run before the suite this time
    #   and is step 1 of VerifyInstall1 precisely to catch it in a second.
    [pscustomobject]@{ Name = ($Prefix + '1'); Keyword = '';              Tier = 'STANDARD';      Voc = 355 }
    # 04 Sep 26 - 396 -> 397, PRE_RELEASE 16, AND THIS FILE WAS LEFT BEHIND FOR
    #   THE THIRD TIME - caught by test-tiercounts-units in 0.4 s, exactly as
    #   the comment above predicted it would be.  "logout" moved out of
    #   TIER.ADD.ADMINISTRATOR into newvoc plus TIER.OMIT.STANDARD, the shape
    #   "micro" already has, so a PROGRAMMER may clear their own dead session.
    #   RE-DERIVED FROM THE DIRECTORY RATHER THAN COPIED FROM verify-tiers.ps1:
    #   newvoc now holds 396 names, less "%t" and the two list records = 393;
    #   TIER.OMIT.STANDARD is 43 lines, 1 + 42.  So PROGRAMMER 393 + 4 = 397,
    #   while ADMINISTRATOR 393 + 23 + 4 = 420 and STANDARD 393 - 42 + 4 = 355
    #   do NOT move - the verb left one side of ADMINISTRATOR's sum and joined
    #   the other, and joined both sides of STANDARD's at once.
    [pscustomobject]@{ Name = ($Prefix + '2'); Keyword = 'PROGRAMMER';    Tier = 'PROGRAMMER';    Voc = 397 }
    # 28 Aug 26 - 417 -> 416, AND THIS FILE WAS THE ONE LEFT BEHIND.
    #   PRE_RELEASE 25 deleted encrypt.field from voc_template and from
    #   TIER.ADD.ADMINISTRATOR - a V record pointing at $CRYPTO, which is
    #   nowhere in the tree - so ADMINISTRATOR lost a verb and the other two
    #   tiers did not.  verify-tiers.ps1 was re-derived from the directory the
    #   same day and this constant was not, so THE TWO VERIFIERS DISAGREED
    #   ABOUT THE SAME FACT for a day.  It surfaced on -Run b52, the first
    #   suite run to reach step 19 against an install carrying 25's change.
    #
    #   RE-DERIVED FROM THE DIRECTORY RATHER THAN COPIED FROM THE OTHER FILE:
    #   newvoc holds 395 names, less "%t" and the two list records = 392;
    #   TIER.ADD.ADMINISTRATOR is 24 lines, 1 description + 23 verbs.  So
    #   392 + 23 + 4 = 419, while PROGRAMMER 392 + 4 = 396 and STANDARD
    #   392 - 42 + 4 = 354 do not move - which is the check on the arithmetic,
    #   since the verbs were only ever ADMINISTRATOR's.
    #
    #   test-tiercounts-units.ps1 now asserts the two files agree WITH EACH
    #   OTHER and with the directory, so this cannot drift again unnoticed.
    #
    # 30 Aug 26 - 416 -> 419, AND THIS FILE WAS THE ONE LEFT BEHIND. AGAIN.
    #   PRE_RELEASE 78 added remote.api, remote.ssh and ssh.server to
    #   TIER.ADD.ADMINISTRATOR; verify-tiers.ps1 was re-derived and this
    #   constant was not - the SAME file, the SAME way, second time in three
    #   days.  It surfaced on -Run b70 step 21, a whole suite run.
    #
    #   ***AND THE LINE ABOVE IS WRONG ABOUT WHY.***  "this cannot drift again
    #   unnoticed" was never true: test-tiercounts-units.ps1 catches it in
    #   under a second with no install, no elevation and no run token, and it
    #   caught THIS the moment it was finally run - "verify-tierapi.ps1:
    #   ADMINISTRATOR -- claims 416, tree says 419".  What it cannot do is run
    #   itself.  NOTHING INVOKES IT: it is in neither VerifyInstall1 nor
    #   VerifyInstall2, so the guard written for exactly this failure sat
    #   unrun while exactly this failure happened again.  Filed as
    #   PRE_RELEASE 82.
    #
    #   ***SO RUN test-tiercounts-units.ps1 BEFORE ANY SUITE RUN THAT FOLLOWS
    #   A CHANGE TO EITHER TIER LIST.***  It is free; a suite step is not.
    # 31 Aug 26 - 419 -> 420.  PRE_RELEASE 89 adds append.sd.path to
    #   TIER.ADD.ADMINISTRATOR, the fourth administrator verb.
    #
    #   ***AND THIS TIME THE FILE WAS NOT LEFT BEHIND, BECAUSE THE GUARD WAS
    #   RUN.***  test-tiercounts-units.ps1 was run immediately after
    #   verify-tiers.ps1 was updated and said, in under a second:
    #   "verify-tierapi.ps1: ADMINISTRATOR -- claims 419, tree says 420".
    #   Third time for this constant, first time it cost nothing - no suite
    #   run, no install, no run token.  The entry above is right that what the
    #   guard cannot do is invoke itself; running it is the habit.
    #
    #   RE-DERIVED FROM THE DIRECTORY, NOT COPIED FROM THE OTHER FILE:
    #   newvoc still holds 395 names, less "%t" and the two list records = 392,
    #   and that it did NOT move is the proof the verb went to voc_template;
    #   TIER.ADD.ADMINISTRATOR is 25 lines, 1 description + 24 verbs.  So
    #   392 + 24 + 4 = 420, while PROGRAMMER 392 + 4 = 396 and STANDARD
    #   392 - 41 + 4 = 355 do not move.
    #
    #   ***THE 25 Aug ARITHMETIC ABOVE HAS TIER.OMIT.STANDARD WRONG.***  It
    #   says "392 - 42 + 4 = 354"; the file is 42 lines, 1 + 41 verbs, and the
    #   STANDARD constant in this file and in verify-tiers.ps1 has always been
    #   355.  Stale comment, not a stale constant - nothing was failing - but a
    #   re-derivation that trusted it would come out one short and read as a
    #   regression.  Corrected in verify-tiers.ps1's block too.
    [pscustomobject]@{ Name = ($Prefix + '3'); Keyword = 'ADMINISTRATOR'; Tier = 'ADMINISTRATOR'; Voc = 420 }
)
foreach ($t in $Tiers) {
    if (Get-LocalUser -Name $t.Name -ErrorAction SilentlyContinue) { Refuse ($t.Name + ' already exists as a Windows account.  Use a fresh -Prefix.') }
    if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $t.Name.ToUpper()))) {
        Refuse ($t.Name.ToUpper() + ' is still in the ACCOUNTS register.  Use a fresh -Prefix, or DELETE.ACCOUNT it.')
    }
}

Add-Type -AssemblyName System.Web
$restoreNeeded = $false
$portAdded     = $false

try {
    # -----------------------------------------------------------------------
    Step 1 'Creating one account per tier'
    foreach ($t in $Tiers) {
        # TWO PASSWORDS, AND THEY ARE NOT THE SAME THING.  winPw is the
        # WINDOWS account's, which is what an ssh login would use; sdPw is the
        # SD credential in $cred, which is the only one the API ever sees.
        $winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6)
        $bytes = New-Object byte[] 18
        ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
        $t | Add-Member -NotePropertyName SdPw -NotePropertyValue (
            ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + 'aA1')

        $cmd = ('CREATE.ACCOUNT USER ' + $t.Name + ' ' + $t.Keyword + ' BOTH').Trim()
        Write-Host ("  " + $cmd)
        $null = Invoke-SD @($cmd, $winPw, $winPw)
        # THE REGISTER RECORD, NOT THE OUTPUT TEXT - SD echoes the command it
        # was given, so the name is in the output whether it worked or refused.
        $made = Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $t.Name.ToUpper()))
        Note ($t.Tier + ' account created') $true $made
        if (-not $made) { Refuse ('CREATE.ACCOUNT did not register ' + $t.Name) }
        $restoreNeeded = $true
    }

    # -----------------------------------------------------------------------
    Step 2 'Giving each an API credential'
    foreach ($t in $Tiers) {
        $out = Invoke-SD @(('MODIFY.PASSWORD ' + $t.Name.ToUpper()), $t.SdPw, $t.SdPw)
        Note ($t.Tier + ' password set') $true ($out -match 'Password set for account')
    }

    # -----------------------------------------------------------------------
    Step 3 'What each tier can DO once in, as a VOC count'
    # Not a login test at all - it is the answer to "a standard user connects,
    # but can they use a developer tool".  354 has no BASIC, ED or RUN.
    # 23 Aug 26 - 393/411/421 until PROC, SED and UPDATE.RECORD went; the
    # arithmetic behind all three is in verify-tiers.ps1's header.
    #
    # 24 Aug 26 - 391/408/418 UNTIL THE OWNER'S TIER SPLIT LANDED, and
    # THIS FILE WAS MISSED WHEN IT DID.  Session 50 re-derived the three
    # counts in verify-tiers.ps1 and did not touch the copy here, so the
    # b33 suite failed exactly these three checks against a CORRECT
    # install: expected 391/408/418, got 354/396/417 - and step 5 of the
    # same run, verify-tiers, PASSED on 354/396/417.
    #
    # THE NUMBERS LIVE IN TWO FILES AND MUST MOVE TOGETHER.  The line
    # above already pointed at verify-tiers.ps1's header as the
    # arithmetic, and that was not enough to stop the drift, because
    # nothing here fails when the two disagree - only when the INSTALL
    # disagrees with this copy.  Changing the split means changing both,
    # in the same commit, and verify-tiers.ps1's header is the source.
    foreach ($t in $Tiers) {
        $out = Invoke-SD @(('LOGTO ' + $t.Name.ToUpper()), 'COUNT VOC')
        Note ($t.Tier + ' VOC count') $t.Voc (Get-VocCount $out)
    }

    # -----------------------------------------------------------------------
    Step 4 'Making sure the API is listening'
    $listen = @(netstat -an | Select-String 'LISTENING' | Where-Object { $_ -match (':' + $Port + '\s') })
    if ($listen.Count -eq 0) {
        Write-Host '  no listener - adding APIPORT and restarting SD'
        Copy-Item -LiteralPath $conf -Destination $backup -Force
        Add-Content -LiteralPath $conf -Value ("APIPORT=" + $Port)
        $portAdded = $true
        if (Stop-SD) { Start-SD } else { Start-SD }
        $listen = @(netstat -an | Select-String 'LISTENING' | Where-Object { $_ -match (':' + $Port + '\s') })
    }
    Note 'a listener on the port' $true ($listen.Count -gt 0)
    if ($listen.Count -eq 0) { Refuse 'Nothing is listening - the rest of this script has nothing to talk to.' }
    # 22 Aug 26 - THIS CHECK WAS INVERTED AGAINST ITS OWN NAME, and it is
    # POSTURE B LEFT BEHIND.  It read:
    #
    #   Note 'bound to 127.0.0.1 only' $false (... -match '0.0.0.0:' + $Port)
    #
    # The EXPRESSION asks "is it bound to 0.0.0.0", which is TRUE on a correct
    # install; the EXPECTATION was $false.  So it failed BECAUSE the server was
    # right.  Under posture B - loopback TCP with ssh carrying it - the port was
    # meant to be loopback-only and this passed; Phase 1 reversed that on
    # 21 Aug 2026 (INADDR_ANY, APIPORT ships active, the installer opens a
    # firewall rule), and this line was not moved with it.
    #
    # verify-apiport.ps1 asks the same question the right way round, two steps
    # earlier in the runner, and reported "bound to 0.0.0.0 (every interface):
    # expected True, got True" on the same install minutes before this said the
    # opposite.  THAT DISAGREEMENT IS WHAT MAKES IT A TEST BUG rather than a
    # finding: two verifiers, one server, one run, contradictory answers.
    Note 'bound to every interface, not loopback only' $true ([bool](@($listen) -match '0\.0\.0\.0:' + $Port))

    # -----------------------------------------------------------------------
    Step 5 'Each tier logs in through the 32-bit client mvDeveloper uses'
    foreach ($t in $Tiers) {
        Write-Host ('  ' + $t.Tier + ' as ' + $t.Name)
        Note ($t.Tier + ' connects') $true (Test-Connect $t.Name $t.SdPw $t.Name)
    }

    # -----------------------------------------------------------------------
    Step 6 'The controls'

    # A wrong password.  Without this, "three tiers connected" would pass just
    # as well against a server that admitted anybody.
    Write-Host '  wrong password for the STANDARD account'
    Note 'wrong password refused' $false (Test-Connect $Tiers[0].Name ($Tiers[0].SdPw + 'x') $Tiers[0].Name)

    # ONE TIER MAY NOT ENTER ANOTHER'S ACCOUNT.  The login is fine - it is the
    # same correct credential - and vb.account refuses the attach on ACC$GROUP.
    # This is what makes the three successes above mean "reached its OWN
    # account" rather than "reached an account".
    Write-Host ('  ' + $Tiers[0].Tier + ' credentials, attaching to the ' + $Tiers[2].Tier + ' account')
    Note 'one account cannot enter another' $false (Test-Connect $Tiers[0].Name $Tiers[0].SdPw $Tiers[2].Name)
}
finally {
    if (-not $Keep) {
        Step 7 'Putting the system back'
        if ($portAdded -and (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $backup -Destination $conf -Force
            Remove-Item -LiteralPath $backup -Force
            if (Stop-SD) { Start-SD }
            Write-Host '   sd.conf restored and SD restarted'
        }
        if ($restoreNeeded) {
            foreach ($t in $Tiers) {
                if (Get-LocalUser -Name $t.Name -ErrorAction SilentlyContinue) {
                    Remove-LocalUser -Name $t.Name; Write-Host ("   removed Windows account " + $t.Name)
                }
                $d = Join-Path $env:ProgramData ('SD\user_accounts\' + $t.Name)
                if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
                $g = 'sdu_' + $t.Name
                if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $g }
            }
            # The SD half is left deliberately, as the other verifiers leave
            # theirs: removing the register records here would hide a
            # CREATE.ACCOUNT that had half failed.  $CRED keeps its records too.
            #
            # 30 Aug 26 - AND SO DOES os.users, WHICH THIS LINE DID NOT NAME.
            # PRE_RELEASE_FIXES.md 65.  The ADMINISTRATOR subject above is given
            # an os.users record at create time and this block removes the
            # Windows LOGIN without it, so the residue includes a yes|yes keyed
            # on a name that no longer resolves - the one leftover that is a
            # PERMISSION rather than a register entry.  Left for the same reason
            # as the others, but not left unsaid.  DELETE.ACCOUNT takes it as of
            # the same entry's fix to DELACC; before that fix it did not.
            Write-Host '   ACCOUNTS and $CRED records left in place - remove with DELETE.ACCOUNT'
            Write-Host ('   sdsys\os.users record for ' + $Tiers[2].Name +
                        ' left in place too - the same DELETE.ACCOUNT takes it')
        }
    } else {
        Write-Host ''
        Write-Host "-Keep: the three accounts and their credentials are STILL THERE." -ForegroundColor Yellow
        foreach ($t in $Tiers) { Write-Host ("  {0,-14} {1}  password: {2}" -f $t.Tier, $t.Name, $t.SdPw) }
    }
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
