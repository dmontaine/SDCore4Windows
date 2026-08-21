<#
.SYNOPSIS
    Does a REMOTE API session hold privileges an ordinary SD user does not?

.DESCRIPTION
    PROJECT_STATUS.md section 8.  APISRVR asserts in two places that an API
    session "cannot have" elevation - at its K$ADMINISTRATOR note (:459) and
    again where it refuses SDSYS (:489) - and the account gating there is
    reasoned on that basis.

    THE CLAIM LOOKS FALSE ON WINDOWS.  sdwind runs as a service
    (SERVICE_START_NAME LocalSystem) and accept_api_session() fork()s and
    exec()s "sd -n -q", so the session inherits LOCALSYSTEM'S TOKEN rather than
    the client's.  Measured from outside on 20 Aug 2026: the forked sd.exe's
    owner is unreadable to an unelevated query, exactly as sdwind's is, while
    an ordinary interactive sd.exe reads back as the user.

    WHAT THAT LEAVES OPEN, and what this measures: whether the SD session can
    USE it.  $cred is granted to SYSTEM and Administrators and nothing else
    (gplbld/secure-cred.ps1), so if a remote client can WRITE it, a remote
    client can reset anybody's password - and the port is reachable from
    another machine over "ssh -L", which is the route administrators are not
    supposed to have.

    THE ASSERTION IS THAT IT CANNOT.  A pass means the exposure is not there;
    a FAIL is the finding, not a broken test.  Read the summary accordingly.

    WHY A PROGRAMMER-TIER ACCOUNT.  It is the least privileged tier that still
    has RUN in its VOC - a STANDARD account has no "basic", "ed" or "run", so
    it cannot execute the probe at all.  PROGRAMMER holds none of the
    administration verbs, so anything it reaches, it reaches through the
    session's OS token rather than through SD granting it.

    THE CONTROL IS THE LOCAL RUN, and without it this proves nothing.  The
    SAME compiled program is run from a local elevated session, which MUST
    report the store open and writable.  A probe that answered "no" whatever
    happened would otherwise pass every assertion below while measuring
    nothing.

    IT CHANGES THE INSTALLED SYSTEM AND PUTS IT BACK: a throwaway Windows and
    SD account, an sd.conf APIPORT line, and two SD restarts.  The account is
    removed in a finally block, and what could not be removed is named.

    21 AUG 2026 - AND IT NOW MEASURES THE sdapi GATE ON THE WAY PAST.
    CREATE.ACCOUNT no longer joins sdapi, so step 7a connects with a valid
    credential and NO permission and must be REFUSED; 7b grants it with
    MODIFY.ACCOUNT ... API and 7c is the original measurement.  That was not
    an addition for its own sake - without the grant this script could no
    longer connect at all - but the refusal leg is what turns a necessary fix
    into evidence, and it is deliberately taken with NO SD restart between,
    because APISRVR asks the SAM per login rather than reading a cached list.

.PARAMETER Prefix
    Name for the throwaway Windows and SD account.  Lower case, and one that
    does not exist - CREATE.ACCOUNT refuses a name it has seen.

.PARAMETER Port
    Loopback port the API listener uses.  4243 is the shipped default.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-apiadmin.ps1 -Prefix sdapia1
#>

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
$backup  = $conf + '.before-apiadmin'
$cred    = Join-Path $env:ProgramData 'SD\sdsys\$cred'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-apiadmin-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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

# 21 Aug 26 - A THIRD OUTCOME, AND IT EXISTS TO STOP A VACUOUS PASS.
#
# Once OS.EXECUTE is gated for network sessions, the probe can no longer ASK
# what the session is running as - the os.execute that would have printed
# WHOAMI is refused, so the marker is absent.  Fed to Note() that reads as
# "not SYSTEM" and PASSES, on a session that is still running as LocalSystem
# and has merely lost the ability to say so.
#
# THAT IS THE SAME FAULT AS THE ONE FOUND ON 21 Aug IN THIS FILE - a check
# that cannot fail is not a check - so it gets a state of its own rather than
# a comment asking the reader to remember.  N/A does NOT set $failed and does
# NOT count as a pass; the summary counts it separately.
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

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# Drives a local SD session in a NAMED account.  Same shape as
# verify-apiport.ps1's helper, except that it does not go to SDSYS: the probe
# lives in the throwaway account's BP and has to be run from there.
function Invoke-SDIn([string]$account, [string[]]$commands) {
    $body = "`n" + ((@("LOGTO $account", 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

function Invoke-SDSys([string[]]$commands) {
    return (Invoke-SDIn 'SDSYS' $commands)
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

# SD RETURNS CAPTURED OUTPUT AS A DYNAMIC ARRAY, NOT AS TEXT WITH NEWLINES.
# "execute cmnd capturing response" joins the lines with FIELD MARKS (char
# 254), so everything the probe printed arrives as ONE physical line:
#
#   PROBE.ACCOUNT=SDAPIA1<fm>PROBE.CRED.OPEN=YES<fm>PROBE.CRED.WRITE=YES<fm>...
#
# 20 Aug 26 - THE FIRST VERSION OF THIS ANCHORED ON ^ AND CAPTURED \S*, AND
# BOTH HALVES WERE WRONG ON THAT INPUT.  A field mark is not whitespace, so
# the first marker swallowed the whole reply; and with no line starts after
# it, every later marker read as ABSENT - which the verdict then reported as a
# missing answer rather than the answer.  Three checks failed and the finding
# was sitting inside the text of the first one.  The local leg parsed cleanly
# because a local session's output really does have newlines, so the defect
# appeared only on the leg that mattered.
function Convert-ProbeText([string]$text) {
    # Marks are 252-255.  The probe prints ASCII only, so nothing legitimate
    # is in that range and turning them all into newlines is safe.  A run that
    # arrived already decoded to U+FFFD is handled too.
    # \u escapes rather than the literal characters: this file must not depend
    # on being read back in the same encoding it was written in.
    return ($text -replace '[\u00FC-\u00FF\uFFFD]', "`n")
}

# Pull one PROBE.<name>= marker out of a captured run.  Returns '' if absent,
# which is distinguishable from 'NO' and is meant to be - a missing marker
# means the probe did not get that far, not that the answer was no.
#
# DELIMITER-AGNOSTIC ON PURPOSE: no ^ anchor, and the value is bounded to the
# characters the probe actually emits rather than to "not whitespace".  That
# holds whatever SD puts between the lines.
function Get-Marker([string]$text, [string]$name) {
    $m = [regex]::Match($text, ('PROBE\.' + [regex]::Escape($name) + '=([A-Za-z0-9_.\\-]*)'))
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# ---------------------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'Run this from an ELEVATED PowerShell - it creates an account, edits the installed sd.conf and restarts SD.'
}

Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'assert-current refuses - run gplbld/cycle.ps1 first.' }

if ($Prefix -notmatch '^[a-z][a-z0-9_]*$') {
    Fail "-Prefix is '$Prefix'.  Lower case letters, digits and underscore only, starting with a letter."
}
if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
    Fail "$Prefix already exists as a Windows account.  Use a -Prefix that does not."
}
if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper()))) {
    Fail ($Prefix.ToUpper() + ' is still in the ACCOUNTS register from an earlier run.  Use a fresh -Prefix.')
}

$bash = 'C:\msys64\usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) { Fail "MSYS2 bash not found at $bash" }

$restoreNeeded = $false
$madeAccount   = $false
$pw            = ''

try {
    # -----------------------------------------------------------------------
    Step 1 "Creating the throwaway PROGRAMMER account $Prefix"

    # Two passwords, and they are not the same thing - verify-apiport.ps1 says
    # why at length.  $winPw is the WINDOWS account's and only travels down the
    # pipe into SD; $pw is the SD credential and is the only one the API sees.
    # The SD one is kept alphanumeric because it is passed through "bash -lc".
    Add-Type -AssemblyName System.Web
    $winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6)

    $out = Invoke-SDSys @("CREATE.ACCOUNT USER $Prefix PROGRAMMER", $winPw, $winPw)
    $accRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper())
    $made = Test-Path -LiteralPath $accRec
    Note 'accounts record created' $true $made
    if (-not $made) { Write-Host $out; Fail 'CREATE.ACCOUNT did not register the account.' }
    $madeAccount = $true

    # -----------------------------------------------------------------------
    Step 2 'Setting its SD credential'

    $bytes = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + 'aA1'

    $out = Invoke-SDSys @(("MODIFY.PASSWORD " + $Prefix.ToUpper()), $pw, $pw)
    $set = ($out -match 'Password set for account')
    Note 'credential set' $true $set
    if (-not $set) { Write-Host $out; Fail 'MODIFY.PASSWORD did not report success.' }

    # -----------------------------------------------------------------------
    Step 3 'The premise: what the ACL on $cred actually says'

    # ASSERTED RATHER THAN ASSUMED.  Everything below is about a file this
    # script believes is locked to SYSTEM and Administrators.  If the ACL has
    # drifted, the API result would be unremarkable and would still "fail".
    $acl = (& icacls.exe $cred) -join "`n"
    Write-Host $acl
    $grantsSystem = ($acl -match 'NT AUTHORITY\\SYSTEM')
    $grantsAdmins = ($acl -match 'BUILTIN\\Administrators')
    $grantsUsers  = ($acl -match 'sdusers')
    Note '$cred grants SYSTEM'          $true  $grantsSystem
    Note '$cred grants Administrators'  $true  $grantsAdmins
    Note '$cred grants sdusers NOTHING' $false $grantsUsers

    # -----------------------------------------------------------------------
    Step 4 'Compiling the probe into the account'

    $acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $Prefix)
    $bpDir   = Join-Path $acctDir 'bp'
    if (-not (Test-Path -LiteralPath $bpDir)) {
        Fail "No bp directory at $bpDir - CREATE.ACCOUNT's layout has changed."
    }
    # 21 Aug 26 - TWO PROBES NOW, AND THE SPLIT IS NOT COSMETIC.  The os.execute
    # leg ABORTS when it is refused, and an abort DISCARDS the output an API
    # session has captured - so while the two lived in one program, every run
    # where the gate worked came back holding the refusal message and NOT ONE
    # of the $cred markers the program had already printed.  That scored two
    # FAILs which were absence of data rather than measurement.  Measured
    # 21 Aug 2026; apiadminprobe.sb's tail comment has the detail.
    #
    # APIADMINPROBE IS ABORT-FREE BY CONSTRUCTION and carries the measurements
    # that must come back.  APIOSEXECPROBE is the one allowed to die.
    Copy-Item -LiteralPath (Join-Path $Gplbld 'apiadminprobe.sb') `
              -Destination (Join-Path $bpDir 'APIADMINPROBE') -Force
    Copy-Item -LiteralPath (Join-Path $Gplbld 'apiosexecprobe.sb') `
              -Destination (Join-Path $bpDir 'APIOSEXECPROBE') -Force

    $out = Invoke-SDIn $Prefix.ToUpper() @('BASIC BP APIADMINPROBE', 'BASIC BP APIOSEXECPROBE')
    Write-Host $out
    $compiled = ($out -match 'APIADMINPROBE') -and ($out -match 'APIOSEXECPROBE') `
                -and ($out -notmatch '[1-9][0-9]* error')
    Note 'probe compiled' $true $compiled
    if (-not $compiled) { Fail 'A probe did not compile - the output above says why.' }

    # -----------------------------------------------------------------------
    Step 5 'CONTROL: the same probe from a LOCAL ELEVATED session'

    # WITHOUT THIS THE TEST IS VACUOUS.  This session genuinely is elevated, so
    # it MUST reach the store.  A probe that answered "no" whatever happened
    # would pass every assertion in step 7 while measuring nothing at all.
    $localOut = Invoke-SDIn $Prefix.ToUpper() @('RUN BP APIADMINPROBE')
    Write-Host $localOut

    # Separate run, because this one may abort - see the note in step 4.
    $localOsOut = Invoke-SDIn $Prefix.ToUpper() @('RUN BP APIOSEXECPROBE')
    Write-Host $localOsOut

    $localAcct  = Get-Marker $localOut 'ACCOUNT'
    $localOpen  = Get-Marker $localOut 'CRED.OPEN'
    $localWrite = Get-Marker $localOut 'CRED.WRITE'
    Write-Host "   local: account=$localAcct open=$localOpen write=$localWrite"

    Note 'control: probe ran locally'            $true  ($localOut -match 'PROBE\.DONE')
    Note 'control: elevated session OPENS $cred' 'YES'  $localOpen
    Note 'control: elevated session WRITES $cred' 'YES' $localWrite

    # -----------------------------------------------------------------------
    Step 6 "Enabling APIPORT=$Port and restarting SD"

    Copy-Item -LiteralPath $conf -Destination $backup -Force
    $restoreNeeded = $true
    $lines = @(Get-Content -LiteralPath $conf) | Where-Object { $_ -notmatch '^\s*APIPORT\s*=' }
    $lines += ('APIPORT=' + $Port)
    Set-Content -LiteralPath $conf -Value $lines -Encoding Ascii

    # read_config() runs only when the shared segment is CREATED, so it has to
    # be a restart rather than a reload.
    if (-not (Stop-SD))  { Fail 'SD would not stop - close any open session and try again.' }
    if (-not (Start-SD)) { Fail 'SD would not start again.  Read the SD error log.' }
    Start-Sleep -Seconds 2

    $listen = @(netstat -an | Select-String 'LISTENING' |
                Where-Object { $_ -match ('127\.0\.0\.1:' + $Port + '\s') })
    Note 'listener on 127.0.0.1' $true ($listen.Count -gt 0)
    if ($listen.Count -eq 0) { Fail "Nothing is listening on 127.0.0.1:$Port." }

    # -----------------------------------------------------------------------
    # C:\a\b -> /c/a/b
    $msys = '/' + $Sd64.Substring(0, 1).ToLower() + ($Sd64.Substring(2) -replace '\\', '/')
    $cmdFor = {
        param([string]$apiCmd)
        "cd '$msys' && make check-api-admin APIHOST=127.0.0.1 APIPORT=$Port " +
        "APIUSER=$Prefix APIPASS='$pw' APIACCT=" + $Prefix.ToUpper() +
        " APICMD='$apiCmd'"
    }
    $cmd = & $cmdFor 'RUN BP APIADMINPROBE'

    # 21 Aug 26 - THE PROBE RUN IS A FUNCTION NOW because it is made TWICE:
    # once before this account is granted the API and once after.  Two copies
    # of the stderr handling below is two places to get it wrong.
    #
    # 2>&1 ON A NATIVE COMMAND UNDER $ErrorActionPreference='Stop' IS THE TRAP
    # THIS PROJECT HAS ALREADY BEEN BITTEN BY TWICE - secure-account-dirs.ps1:95
    # and verify-catgate.ps1:395.  PowerShell 5.1 wraps each stderr line in a
    # NativeCommandError and TERMINATES, and make writes to stderr routinely.
    # Without this the script would die at the one step it exists to perform,
    # and a run that never reached the verdict reads like a passing one.
    function Invoke-ApiProbe {
        # 21 Aug 26 - takes the command now, because the os.execute leg is a
        # SECOND run against the same session settings.  Defaulted, so the two
        # existing callers in step 7a and 7b are unchanged.
        param([string]$RunCmd = $cmd)
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $t = (& $bash -lc $RunCmd 2>&1 | Out-String)
            $rc = $LASTEXITCODE
        } finally { $ErrorActionPreference = $prevEap }
        # Field marks turned back into newlines BEFORE anything reads it, so
        # the transcript is legible and every marker sits on a line of its own.
        # The run that found this printed the probe's whole reply as one line
        # and the answer was easy to miss inside it.
        return @{ Text = (Convert-ProbeText $t); Rc = $rc }
    }

    # -----------------------------------------------------------------------
    Step '7a' 'THE NEW GATE: no sdapi membership, so the API must REFUSE this account'

    # 21 Aug 26 - CREATE.ACCOUNT no longer joins sdapi (owner's decision,
    # 21 Aug 2026), so the account made in step 1 has a valid credential and no
    # permission to use it.  APISRVR tests sdapi AFTER the SCRAM proof
    # succeeds, so this is an AUTHORISATION refusal on a correct password - not
    # a bad-password path, and not the same code.
    #
    # THIS LEG IS WHAT MAKES THE GRANT BELOW MEAN ANYTHING.  Without it, the
    # measurement in 7c would pass just as well if the gate did not exist, and
    # so would a run where MODIFY.PASSWORD had silently failed.
    $r = Invoke-ApiProbe
    Write-Host $r.Text
    $preConnect = Get-Marker $r.Text 'CONNECT'
    Note 'API REFUSES an account not in sdapi' $false ($preConnect -eq 'YES')

    # -----------------------------------------------------------------------
    Step '7b' "Granting it: MODIFY.ACCOUNT $($Prefix.ToUpper()) API"

    $out = Invoke-SDSys @(("MODIFY.ACCOUNT " + $Prefix.ToUpper() + " API"))
    $inApi = [bool](Get-LocalGroupMember -Group 'sdapi' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like ("*\" + $Prefix) })
    Note 'MODIFY.ACCOUNT ... API put it in sdapi' $true $inApi
    if (-not $inApi) { Write-Host $out; Fail 'the account was not granted the API - nothing below can be measured.' }

    # NO SD RESTART, AND THAT IS AN ASSERTION RATHER THAN A SAVING.  APISRVR
    # asks the SAM per login through is_grp_member, so a grant is live for the
    # next connection.  If this leg ever needs a restart to pass, the gate has
    # been moved to something cached and the "immediate withdrawal" claim in
    # MODIFYA is no longer true.

    # -----------------------------------------------------------------------
    Step '7c' 'THE MEASUREMENT: the same probe down a REMOTE API connection'

    $r = Invoke-ApiProbe
    $apiOut = $r.Text
    $apiRc  = $r.Rc
    Write-Host $apiOut

    # 21 Aug 26 - THE SECOND API RUN, and it is allowed to come back with
    # nothing but an abort.  Everything the verdict depends on has already been
    # collected by the run above, which cannot abort.
    $apiOsOut = (Invoke-ApiProbe (& $cmdFor 'RUN BP APIOSEXECPROBE')).Text
    Write-Host $apiOsOut

    $apiConnect = Get-Marker $apiOut 'CONNECT'
    $apiAcct    = Get-Marker $apiOut 'ACCOUNT'
    $apiOpen    = Get-Marker $apiOut 'CRED.OPEN'
    $apiWrite   = Get-Marker $apiOut 'CRED.WRITE'
    Write-Host "   api:   connect=$apiConnect account=$apiAcct open=$apiOpen write=$apiWrite (exit $apiRc)"

    Note 'API session connected' 'YES' $apiConnect
    if ($apiConnect -ne 'YES') { Fail 'The API session did not connect - nothing below was measured.' }

    # We are where we think we are.  Without this, a probe that ran in some
    # other account would be read as a result about this one.
    Note 'API session is in the test account' $Prefix.ToUpper() $apiAcct
    Note 'API session ran the probe' $true ($apiOut -match 'PROBE\.DONE')

    # -----------------------------------------------------------------------
    Step 8 'The verdict'

    # THESE TWO ARE THE POINT.  A FAIL HERE IS A FINDING, NOT A BROKEN TEST:
    # it means a remote API client, holding nothing but an ordinary account's
    # credential, can read and rewrite the credential store - and the port is
    # reachable from another machine with "ssh -L", which is the route
    # administrators are deliberately not given.
    Note 'API session CANNOT open $cred'  'NO' $apiOpen

    # 21 Aug 26 - THE WRITE IS ENTAILED BY THE OPEN, AND READING ITS ABSENCE AS
    # A FAILURE WAS WRONG.  apiadminprobe.sb only attempts the write inside
    # "if cred.open then" - there is no file variable to write through
    # otherwise - so a refused OPEN means PROBE.CRED.WRITE is never printed.
    # Measured on sdapia6: open came back "NO status 3035" and this line read a
    # blank and scored FAIL on the run where the gate had just worked.
    #
    # A REFUSED OPEN IS THE STRONGER RESULT, NOT A MISSING ONE.  You cannot
    # write a file you could not open, so the assertion is satisfied - but it
    # is satisfied for a DIFFERENT REASON than "the write was refused", and the
    # transcript says which, because collapsing the two would hide the day the
    # open starts succeeding again.
    if ($apiOpen -eq 'NO') {
        Write-Host '   (the write was never attempted: the open was refused, which subsumes it)'
        Note 'API session CANNOT write $cred' 'NO' 'NO'
    } else {
        Note 'API session CANNOT write $cred' 'NO' $apiWrite
    }

    # 20 Aug 26 - AND WHAT THE SESSION SAYS IT IS, FROM INSIDE.  Everything
    # above infers the identity from OUTSIDE the process, by reading the owner
    # of the forked sd.exe.  This is SD's own session answering.
    #
    # IT ALSO TESTS os_permitted() (op_sh.c), which returns TRUE on USR_ADMIN -
    # and kernel.c:195 seeds USR_ADMIN from IsElevated() with no test of
    # connection type.  If OS.EXECUTE runs here at all, that gate is open to
    # every API client.
    $apiWho    = Get-Marker $apiOsOut   'WHOAMI'
    $localWho  = Get-Marker $localOsOut 'WHOAMI'
    Write-Host "   whoami - local: '$localWho'   api: '$apiWho'"

    # 21 Aug 26 - THIS PATTERN WAS ^nt_authority_+system$ AND IT DID NOT MATCH
    # WHAT THE PROBE PRINTS.  The probe flattened space but not BACKSLASH, so
    # the marker arrived as "nt_authority\system" - and this check reported
    # "API session is NOT running as SYSTEM" as a PASS on the very run where
    # the session had just said it was.  A FALSE PASS on the most important
    # check in this file.  The probe now flattens the backslash too
    # (apiadminprobe.sb), and this pattern no longer depends on which
    # separators it happened to catch: anything non-alphanumeric between the
    # three words counts.  Two independent changes for one fault, deliberately
    # - the check must not be able to go blind again if the probe is reworded.
    $apiIsSystem = ($apiWho -match '(?i)^nt[^a-z0-9]*authority[^a-z0-9]*system$')

    # 21 Aug 26 - AND IT IS ONLY A CHECK WHILE THE PROBE CAN STILL ASK.
    #
    # This question is answered by running "whoami" INSIDE the session.  Once
    # the containment gate refuses OS.EXECUTE to a network session - which is
    # the very thing the next check asserts - no marker comes back, $apiWho is
    # empty, and this would report "NOT running as SYSTEM ... PASS" on a
    # session that is still LocalSystem and has only lost the ability to say
    # so.  A false pass on the most important line in the file, for the second
    # time and by a different route.
    #
    # WHAT IS ACTUALLY TRUE AFTER THE GATE: the session STILL RUNS AS
    # LocalSystem.  sdwind fork()s it and it inherits the service token; that
    # is unchanged and needs the CreateProcessAsUser work to fix.  What changed
    # is that it can no longer reach the operating system with it.  Recording
    # N/A here keeps those two facts apart.
    if ($apiWho -eq '') {
        Skip 'API session is NOT running as SYSTEM' `
             'OS.EXECUTE was refused, so the probe could not ask - the session may still BE SYSTEM'
    } else {
        Note 'API session is NOT running as SYSTEM' $false $apiIsSystem
    }

    # 21 Aug 26 - AND WHETHER OS.EXECUTE RAN AT ALL, which is section 8 item 5
    # measured rather than read.  WHOAMI is printed only if os.execute
    # RETURNED; a refusal aborts the program at that line, so the marker is
    # absent.  PROBE.DONE is printed BEFORE the attempt, so its presence
    # separates "refused" from "never got there".
    $apiRanOsExec   = ($apiWho   -ne '')
    $localRanOsExec = ($localWho -ne '')

    # 21 Aug 26 - AND WHETHER THE ATTEMPT WAS MADE AT ALL, WHICH IS WHAT MAKES
    # THE NEXT CHECK A CHECK.  "CANNOT run OS.EXECUTE" is read off the ABSENCE
    # of WHOAMI, and an absent marker is equally consistent with the probe
    # never having started - a compile that failed, a connection that dropped,
    # a name that no longer resolves.  That is the same vacuous-pass shape as
    # the SYSTEM line below, so it gets the same treatment rather than a
    # comment: PROBE.OSEXEC.TRIED is printed BEFORE the attempt, so its
    # presence is the difference between "refused" and "never got there".
    # 21 Aug 26 - AND THE REFUSAL MESSAGE IS THE EVIDENCE, NOT THE MARKER.
    #
    # PROBE.OSEXEC.TRIED is printed BEFORE the attempt, which was supposed to
    # separate "refused" from "never got there".  It does on the local leg and
    # it CANNOT on the API leg: the refusal aborts the program, an abort
    # discards the captured buffer, and the marker goes with it.  So the check
    # that asked for it could never pass over the API while the gate worked -
    # a check that cannot pass is as useless as one that cannot fail, and it
    # scored FAIL on sdapia6 for that reason.
    #
    # WHAT DOES COME BACK IS SD'S OWN REFUSAL, and it is better evidence than
    # the marker ever was, because it NAMES THE ACCOUNT AND THE PROGRAM:
    #
    #   000000D3: sdapia6 is not permitted to use OS.EXECUTE at line 26 of
    #   /cygdrive/c/.../sdapia6/BP.OUT/APIOSEXECPROBE
    #
    # ASSERT ON SOMETHING THAT MUST BE PRESENT.  That is the lesson from all
    # four instrument faults in this file: an absent marker is not an answer.
    $refusedRx = [regex]::Escape($Prefix) + ' is not permitted to use OS\.EXECUTE'
    $apiRefusedOsExec   = ($apiOsOut   -match $refusedRx) -and ($apiOsOut   -match 'APIOSEXECPROBE')
    # The local leg is refused under whatever Windows account is running this,
    # so it is matched on the message rather than on a name.
    $localRefusedOsExec = ($localOsOut -match 'not permitted to use OS\.EXECUTE')

    # Reached the attempt: either it said so, or it was refused AT it.
    $apiTriedOsExec   = ($apiOsOut   -match 'PROBE\.OSEXEC\.TRIED') -or $apiRefusedOsExec
    $localTriedOsExec = ($localOsOut -match 'PROBE\.OSEXEC\.TRIED') -or $localRefusedOsExec

    Note 'the OS.EXECUTE probe reached the attempt, API'   $true $apiTriedOsExec
    Note 'the OS.EXECUTE probe reached the attempt, local' $true $localTriedOsExec

    # THE POSITIVE FORM OF THE HEADLINE, and the one to read: SD refused THIS
    # account BY NAME, in THIS program.  Nothing about it is inferred from an
    # absence.
    Note 'API session was refused OS.EXECUTE by name' $true $apiRefusedOsExec

    # A FAIL HERE IS THE FINDING, like the two $cred lines above: os_permitted()
    # returns TRUE on USR_ADMIN and kernel.c:195 seeds USR_ADMIN from
    # IsElevated() with no test of connection type.
    #
    # ONLY MEANINGFUL IF THE ATTEMPT WAS MADE - see the two lines above.
    if ($apiTriedOsExec) {
        Note 'API session CANNOT run OS.EXECUTE' $false $apiRanOsExec
    } else {
        Skip 'API session CANNOT run OS.EXECUTE' `
             'the probe never reached the attempt, so a refusal cannot be distinguished from a no-show'
    }

    # AND THE CONTROL THAT MAKES THAT MEAN SOMETHING, which is the inversion
    # worth naming: a LOCAL ELEVATED session standing in the SAME account is
    # REFUSED.  It starts in SDSYS with USR_ADMIN set and gives the flag up on
    # the way out (CPROC, "administrator rights belong to SDSYS"), so by the
    # time it reaches the probe os_permitted() says no.  The API session never
    # leaves anywhere, so it keeps the flag.  Same account, same program, and
    # the remote client is the one that gets the operating system.
    if ($localTriedOsExec) {
        Note 'control: local elevated session refused OS.EXECUTE' $false $localRanOsExec
    } else {
        Skip 'control: local elevated session refused OS.EXECUTE' `
             'the probe never reached the attempt'
    }

    # 21 Aug 26 - GATED ON "IT RAN" RATHER THAN ON "IT SAID SYSTEM".  The two
    # are different failures and the first is the one that matters: OS.EXECUTE
    # reaching the operating system at all from a network session is the hole,
    # whatever identity it reports.  Gating on $apiIsSystem meant that when the
    # pattern above went blind, this block stayed silent on the run that
    # measured the thing it exists to announce.
    if ($apiRanOsExec) {
        Write-Host ''
        Write-Host 'FINDING: OS.EXECUTE RAN in a remote API session.' -ForegroundColor Red
        Write-Host ("It reported its identity as: " + $apiWho) -ForegroundColor Red
        Write-Host 'op_sh.c os_permitted() returns TRUE on USR_ADMIN, and kernel.c:195' -ForegroundColor Red
        Write-Host 'seeds USR_ADMIN from IsElevated() with no test of connection type.' -ForegroundColor Red
        if (-not $localRanOsExec) {
            Write-Host '' -ForegroundColor Red
            Write-Host 'AND THE INVERSION IS THE SHARP PART: the LOCAL ELEVATED control,' -ForegroundColor Red
            Write-Host 'running the SAME program in the SAME account, was REFUSED.  It gives' -ForegroundColor Red
            Write-Host 'up USR_ADMIN on the way out of SDSYS (CPROC); the API session never' -ForegroundColor Red
            Write-Host 'leaves, so it keeps it.  The remote client gets the operating system' -ForegroundColor Red
            Write-Host 'and the administrator at the keyboard does not.' -ForegroundColor Red
        }
    }

    if ($apiOpen -eq 'YES' -or $apiWrite -eq 'YES') {
        Write-Host ''
        Write-Host 'FINDING: the API session reached a file locked to SYSTEM and Administrators.' -ForegroundColor Red
        Write-Host 'The local control shows the probe reports YES only when it genuinely can,' -ForegroundColor Red
        Write-Host 'so this is the session token, not the probe.  APISRVR:459 and :489 assume' -ForegroundColor Red
        Write-Host 'the opposite and the account gating there is reasoned on that assumption.' -ForegroundColor Red
    }
}
finally {
    Write-Host ''
    Write-Host '== [restore] Undoing everything this run created' -ForegroundColor Cyan

    if ($restoreNeeded -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $conf -Force
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        Write-Host '   sd.conf restored'
        if (Stop-SD) { $null = Start-SD }
    }

    # The probe writes a namespaced record and deletes it again, but a run that
    # died between the two would leave it.  Named rather than silently left.
    if (Test-Path -LiteralPath (Join-Path $cred '$$apiadminprobe')) {
        Remove-Item -LiteralPath (Join-Path $cred '$$apiadminprobe') -Force -ErrorAction SilentlyContinue
        Write-Host '   removed a leftover $$apiadminprobe record from $cred'
    }

    if ($madeAccount) {
        # 21 Aug 26 - OUT OF sdapi FIRST, AND BEFORE DELETE.ACCOUNT RATHER THAN
        # RELYING ON IT.  Removing the Windows user takes its group memberships
        # with it, so this is redundant on the happy path - but DELETE.ACCOUNT
        # is exactly the step that sometimes does not finish (the block below
        # exists for that), and an account left behind holding an API grant is
        # the one piece of litter from this script that would be a permission
        # rather than a name in a register.
        foreach ($g in @('sdapi', 'sdssh')) {
            try {
                if (Get-LocalGroupMember -Group $g -Member $Prefix -ErrorAction SilentlyContinue) {
                    Remove-LocalGroupMember -Group $g -Member $Prefix -ErrorAction Stop
                    Write-Host "   took $Prefix out of $g"
                }
            } catch { }
        }

        try {
            $out = Invoke-SDSys @("DELETE.ACCOUNT $Prefix", 'Y', 'Y')
            Write-Host $out
        } catch { Write-Host "   DELETE.ACCOUNT threw: $_" }

        $stillReg = Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper()))
        $stillWin = [bool](Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue)
        if ($stillReg -or $stillWin) {
            Write-Host "   NOT fully removed - register:$stillReg windows:$stillWin" -ForegroundColor Yellow
            Write-Host "   Remove by hand before reusing -Prefix $Prefix." -ForegroundColor Yellow
        } else {
            Write-Host '   throwaway account removed'
        }
    }
}

Write-Host ''
$results | Format-Table -AutoSize
$pass  = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
$total = $results.Count
Write-Host ("verify-apiadmin: {0}/{1}" -f $pass, $total) -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
try { Stop-Transcript | Out-Null } catch { }
exit $(if ($failed) { 1 } else { 0 })
