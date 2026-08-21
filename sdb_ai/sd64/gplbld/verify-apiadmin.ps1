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

    $out = Invoke-SDSys @(("SET.PASSWORD " + $Prefix.ToUpper()), $pw, $pw)
    $set = ($out -match 'Password set for account')
    Note 'credential set' $true $set
    if (-not $set) { Write-Host $out; Fail 'SET.PASSWORD did not report success.' }

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
    Copy-Item -LiteralPath (Join-Path $Gplbld 'apiadminprobe.sb') `
              -Destination (Join-Path $bpDir 'APIADMINPROBE') -Force

    $out = Invoke-SDIn $Prefix.ToUpper() @('BASIC BP APIADMINPROBE')
    Write-Host $out
    $compiled = ($out -match 'APIADMINPROBE') -and ($out -notmatch '[1-9][0-9]* error')
    Note 'probe compiled' $true $compiled
    if (-not $compiled) { Fail 'The probe did not compile - the output above says why.' }

    # -----------------------------------------------------------------------
    Step 5 'CONTROL: the same probe from a LOCAL ELEVATED session'

    # WITHOUT THIS THE TEST IS VACUOUS.  This session genuinely is elevated, so
    # it MUST reach the store.  A probe that answered "no" whatever happened
    # would pass every assertion in step 7 while measuring nothing at all.
    $localOut = Invoke-SDIn $Prefix.ToUpper() @('RUN BP APIADMINPROBE')
    Write-Host $localOut

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
    Step 7 'THE MEASUREMENT: the same probe down a REMOTE API connection'

    # C:\a\b -> /c/a/b
    $msys = '/' + $Sd64.Substring(0, 1).ToLower() + ($Sd64.Substring(2) -replace '\\', '/')
    $cmd = "cd '$msys' && make check-api-admin APIHOST=127.0.0.1 APIPORT=$Port " +
           "APIUSER=$Prefix APIPASS='$pw' APIACCT=" + $Prefix.ToUpper() +
           " APICMD='RUN BP APIADMINPROBE'"
    # 2>&1 ON A NATIVE COMMAND UNDER $ErrorActionPreference='Stop' IS THE TRAP
    # THIS PROJECT HAS ALREADY BEEN BITTEN BY TWICE - secure-account-dirs.ps1:95
    # and verify-catgate.ps1:395.  PowerShell 5.1 wraps each stderr line in a
    # NativeCommandError and TERMINATES, and make writes to stderr routinely.
    # Without this the script would die at the one step it exists to perform,
    # and a run that never reached the verdict reads like a passing one.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $apiOut = (& $bash -lc $cmd 2>&1 | Out-String)
        $apiRc  = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEap }

    # Field marks turned back into newlines BEFORE anything reads it, so the
    # transcript is legible and every marker sits on a line of its own.  The
    # run that found this printed the probe's whole reply as one line and the
    # answer was easy to miss inside it.
    $apiOut = Convert-ProbeText $apiOut
    Write-Host $apiOut

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
    Note 'API session CANNOT write $cred' 'NO' $apiWrite

    # 20 Aug 26 - AND WHAT THE SESSION SAYS IT IS, FROM INSIDE.  Everything
    # above infers the identity from OUTSIDE the process, by reading the owner
    # of the forked sd.exe.  This is SD's own session answering.
    #
    # IT ALSO TESTS os_permitted() (op_sh.c), which returns TRUE on USR_ADMIN -
    # and kernel.c:195 seeds USR_ADMIN from IsElevated() with no test of
    # connection type.  If OS.EXECUTE runs here at all, that gate is open to
    # every API client.
    $apiWho    = Get-Marker $apiOut 'WHOAMI'
    $localWho  = Get-Marker $localOut 'WHOAMI'
    Write-Host "   whoami - local: '$localWho'   api: '$apiWho'"

    # Underscores because the probe flattens "nt authority\system" to one token.
    $apiIsSystem = ($apiWho -match '(?i)^nt_authority_+system$')
    Note 'API session is NOT running as SYSTEM' $false $apiIsSystem

    if ($apiIsSystem) {
        Write-Host ''
        Write-Host 'FINDING: OS.EXECUTE ran, and the session is LocalSystem.' -ForegroundColor Red
        Write-Host 'That is arbitrary command execution as SYSTEM from a remote API' -ForegroundColor Red
        Write-Host 'client holding an ordinary account credential.  op_sh.c os_permitted()' -ForegroundColor Red
        Write-Host 'returns TRUE on USR_ADMIN, which kernel.c:195 sets from IsElevated().' -ForegroundColor Red
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
