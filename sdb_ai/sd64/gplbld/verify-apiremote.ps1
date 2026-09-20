<#
.SYNOPSIS
    The API door over the network: does an account's route keyword decide whether
    the API admits it, and does the ADDRESS it connects from make no difference?

.DESCRIPTION
    ***THE NAME IS HISTORICAL AND KEPT ON PURPOSE.***  This file was written for
    PRE_RELEASE_FIXES.md 170 to prove that an SD ADMINISTRATOR is refused an API
    session from any non-local address while a non-administrator is admitted over
    the same route (the 5 Sep 2026 ruling, refined by RELEASE_1.1 58 and 62).
    RELEASE_1.1 64 abolished the administrator account type and deleted the peer
    test that read the address, so that subject no longer exists and the script
    died at its first step (the verb refuses the administrator tier word, 2018).
    ***REWRITTEN 20 Sep 2026 ON THE OWNER'S RULING ("rewrite")*** to the subject
    that is left and that only a real client over a real network address can
    measure.  The name stays because the runner's table, the scope guards and the
    record all name it.

    THE MODEL (RELEASE_1.1 64, 68): one administrator, SDSYS; every other account
    is ordinary, with its routes said at create time - SSH, API, BOTH or NONE, and
    silence means BOTH.  APISRVR's ONLY gate on the route is the sdapi group
    (sdsys/gpl.bp/apisrvr, "not in sdapi", message 10073).  The address is not
    read.  This rig proves both halves of that sentence:

      CONTROL  the API account over the LAN address       MUST BE ADMITTED
      LEG A    the SAME account over 127.0.0.1            MUST BE ADMITTED
      LEG B    an SSH-ONLY account over the LAN address   MUST BE REFUSED (10073)
      LEG C    the same SSH-only account over 127.0.0.1   MUST BE REFUSED (10073)

    THE CONTROL GATES THE REST.  If an account with the API route cannot connect
    over the LAN address, the listener or the firewall is shut and legs B and C's
    refusals say nothing about the keyword.  Without it, a machine with no remote
    API at all would score a confident green.

    AND THE PAIRS ARE THE POINT.  Control and leg A are the same account, the same
    password and the same host, reached by two addresses: if the API read the
    address they would differ.  Control and leg B differ ONLY in the route keyword:
    if the API ignored the keyword they would not.  Either alone can look like a
    pass on a single leg.

    WHAT IT ANCHORS ON.  tests/api_admin_probe.c prints PROBE.CONNECT=YES only
    after SDConnect() returned a session, and PROBE.CONNECT=NO with SDError()
    otherwise.  The success wording therefore cannot appear on the refusal path,
    which is the rule CLAUDE.md states after ZZIDALLOW.  The refusal is scored
    twice over: message 10073's own words ("is not permitted to use the API"), and
    the audit line APISRVR writes at exit.vb.scram.fail - "API REFUSED user=...
    reason=not in sdapi" - which is written there and nowhere else, and which a
    session that never reached the gate cannot produce.

    WHAT IT DOES NOT COVER, SAID PLAINLY.  Whether the LISTENER is reachable from
    another machine (as opposed to this machine's own LAN address) is the
    firewall's question and needs a second machine; the interop run with the Linux
    port is that witness.  What a connection to this machine's own LAN address
    proves is that the API does not read the peer address and that the route
    keyword is the only thing deciding.

    IT CHANGES THE INSTALLED SYSTEM AND PUTS IT BACK: two throwaway Windows and SD
    accounts, an sd.conf APIPORT line, and two SD restarts.  The accounts go in a
    finally block, and anything that could not be removed is NAMED.

    RUN IT ELEVATED, AND SDSYS MUST BE SIGNED IN.  The accounts are made through
    the SDSYS seat (sdsys-seat.ps1, RELEASE_1.1 76), which registers a task for the
    OS SDSYS account and so needs an elevated caller.

.PARAMETER Prefix
    Derived from -Run by the runner.  A FIXED prefix passes once and fails
    every later run (PRE_RELEASE 54), which is why this goes through
    VerifyInstall2 rather than being called by hand with a constant.
    Lower case only: it becomes a Windows account name.

.PARAMETER Port
    Loopback port the API listener uses.  4243 is the shipped default.

.EXAMPLE
    VerifyInstall2.ps1 -Run b124 -Only verify-apiremote
#>
[CmdletBinding()]
param(
    [string]$Prefix = '',
    [int]$Port = 4243
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }

. (Join-Path $here 'sdtestuser.ps1')

$sd64    = Split-Path $here -Parent
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$dataDir = Join-Path $env:ProgramData 'SD'
$conf    = Join-Path $dataDir 'sd.conf'
$backup  = $conf + '.before-apiremote'
$bash    = 'C:\msys64\usr\bin\bash.exe'
# THE SERVICE IS NAMED "SD", NOT AFTER ITS BINARY.  install-service.ps1 sets it,
# and cycle.ps1, restart-sd.ps1 and six verifiers all carry the same constant.
# The first version of this file said 'sdsvc' - the PROCESS name, which is what
# Get-Process shows - and the cost is in the note on Stop-SD below.
$SvcName = 'SD'

$pass = 0
$fail = 0

function Note([string]$name, $expected, $got, [bool]$decisive = $true) {
    $ok = ($expected -eq $got)
    if ($decisive) {
        if ($ok) { $script:pass++ } else { $script:fail++ }
    }
    $tag = if ($ok) { 'PASS' } else { if ($decisive) { 'FAIL' } else { 'note' } }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $tag, $name, $expected, $got)
}

function Refuse([string]$why) {
    Write-Output ''
    Write-Output ("verify-apiremote: CANNOT MEASURE - " + $why)
    Write-Output '  This is the test refusing, not the product failing.'
    exit 2
}

function Step($n, $msg) { Write-Output ''; Write-Output "== [$n] $msg" }

Write-Output 'verify-apiremote - the API door over the network (rewritten 20 Sep 2026; the name is historical)'
Write-Output ("  prefix : {0}" -f $Prefix)
Write-Output ("  sd.exe : {0}" -f $sdExe)
Write-Output ("  port   : {0}" -f $Port)

# ---------------------------------------------------------------- refusals
# Every one of these is "the test could not be run", not "the product failed".

if ($Prefix -eq '') {
    Refuse 'no -Prefix.  The runner derives it from -Run; a fixed one passes once (PRE_RELEASE 54).'
}
if ($Prefix -cne $Prefix.ToLower()) {
    Refuse "the prefix '$Prefix' is not lower case, and it becomes a Windows account name."
}
if (-not (Test-Path -LiteralPath $sdExe)) {
    Refuse "no installed sd.exe at $sdExe.  Run the cycle first."
}
if (-not (Test-Path -LiteralPath $conf)) {
    Refuse "no sd.conf at $conf."
}
if (-not (Test-Path -LiteralPath $bash)) {
    Refuse "no MSYS2 bash at $bash - the API client is built and run through it."
}
if (-not ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Refuse 'run this ELEVATED - it creates accounts through the SDSYS seat, edits the installed sd.conf and restarts SD.'
}

# ***CHECK THE SERVICE BEFORE MAKING ACCOUNTS, NOT AFTER.***  The name was wrong
# once (see Stop-SD), and because the check lived inside step 2 the run had
# already created two Windows accounts and edited sd.conf before it found out.
# Cleanup handled it, but a guard that can fire early should.
if (-not (Get-Service -Name $SvcName -ErrorAction SilentlyContinue)) {
    Write-Output ("  looked for service : {0}" -f $SvcName)
    Write-Output ('  services matching "String Database": ' +
                  ((Get-Service | Where-Object { $_.DisplayName -like '*String Database*' } |
                    ForEach-Object { $_.Name }) -join ', '))
    Refuse ("no service named '$SvcName' - this script has the name wrong, or SD is not installed.")
}

$audit = Join-Path $dataDir 'sdsys\audit'
if (-not (Test-Path -LiteralPath $audit)) {
    $found = Get-ChildItem -Path (Join-Path $dataDir 'sdsys') -Filter 'audit*' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -ne $found) { $audit = $found.FullName }
}
Write-Output ("  audit  : {0}" -f $audit)
if (-not (Test-Path -LiteralPath $audit)) {
    Refuse 'the audit trail does not exist - the decisive reading is unavailable.'
}

# ------------------------------------------------------------- local driver
# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT (sdsys-seat.ps1; verify-createaccount was the
# pilot).  THE "LOGTO SDSYS" PREFIX THIS USED TO SEND IS REFUSED (10002) FROM ANY SESSION THAT
# DID NOT START AS THE OS SDSYS ACCOUNT with an elevated, interactive token.  So the commands
# go to a task inside SDSYS's own live session and the text comes back through a file.  A seat
# that did not run THROWS rather than returning ''.  SDSYS must be signed in.
. (Join-Path $here 'sdsys-seat.ps1')
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 180) {
    if ($null -eq $commands -or $commands.Count -eq 0) {
        throw 'Invoke-SD: no commands given; that would start a session, measure nothing and look like a pass.'
    }
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec)
}

# PROVE THE SEAT BEFORE MAKING ANYTHING, so a missing SDSYS session is exit 2 and leaves no
# account and no edited sd.conf behind.
Assert-SdSeat -Label 'verify-apiremote'

# ***A SERVICE NAME THAT MATCHES NOTHING MUST BE LOUD, NOT SILENT.***  This read
# "if (Get-Service ... -ErrorAction SilentlyContinue) { sc stop }", so a wrong
# name simply did not enter the branch: sc.exe was never called, sdwind kept
# running, and the function returned $false.  The step then refused with "SD
# would not stop - close any open session and try again", which names a cause
# that was not true and reads as a product or environment fault.  One run of the
# suite went that way.  CLAUDE.md's rule is that a test which did nothing must
# say so rather than blame something else.
function Stop-SD {
    $svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Output ("  Stop-SD: no service named '{0}' on this machine." -f $SvcName)
        Write-Output  '  That is this script being wrong about the name, not SD failing to stop.'
        # Get-Service returns ServiceController, which has Name/DisplayName and
        # NO PathName - reaching for one throws under Set-StrictMode.
        Write-Output ('  Services that look like it: ' +
                      ((Get-Service | Where-Object { $_.DisplayName -like '*String Database*' } |
                        ForEach-Object { $_.Name }) -join ', '))
        return $false
    }
    & "$env:SystemRoot\System32\sc.exe" stop $SvcName | Out-Null
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

# Field marks (252-255) turned into newlines BEFORE anything reads the text, so
# the transcript is legible and every marker sits on a line of its own.
# verify-apiadmin.ps1's own note records what anchoring on ^ cost without this.
function Convert-ProbeText([string]$text) {
    if ($null -eq $text) { return '' }
    return ($text -replace '[\xFC-\xFF]', "`n")
}

# C:\a\b -> /c/a/b
$msys = '/' + $sd64.Substring(0, 1).ToLower() + ($sd64.Substring(2) -replace '\\', '/')

# One API connection.  Returns the text and the exit code.
# 2>&1 ON A NATIVE COMMAND UNDER ErrorActionPreference='Stop' TERMINATES the
# script - PowerShell 5.1 wraps each stderr line in a NativeCommandError and
# make writes to stderr routinely.  Two sites in this project have paid for it
# (secure-account-dirs.ps1:95, verify-catgate.ps1:395), so it is handled here
# once rather than at each of the call sites.
function Invoke-Api([string]$ApiHost, [string]$User, [string]$Pw, [string]$Acct, [string]$ApiCmd) {
    $cmd = "cd '$msys' && make check-api-admin APIHOST=$ApiHost APIPORT=$Port " +
           "APIUSER=$User APIPASS='$Pw' APIACCT=$Acct APICMD='$ApiCmd'"
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $t = (& $bash -lc $cmd 2>&1 | Out-String)
        $rc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEap }
    return @{ Text = (Convert-ProbeText $t); Rc = $rc }
}

function InGroup($group, $user) {
    $m = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like ('*\' + $user) }
    return [bool]$m
}

# The API account (route API) and the SSH-only account (route SSH): they differ in NOTHING but
# the keyword, which is what makes leg B a measurement of the keyword.
$apiAcct   = ($Prefix + 'a')
$sshAcct   = ($Prefix + 'p')
$apiPw     = New-SdTestPassword
$sshPw     = New-SdTestPassword
$restoreNeeded = $false

try {
    # -----------------------------------------------------------------------
    Step 1 'two accounts: one with the API route, one with SSH only'

    # ***REWRITTEN 20 Sep 2026.***  This step made a real local ADMINISTRATOR and a
    # PROGRAMMER; 64 abolished the first and refuses both keywords (2018).  The route
    # keyword is what decides the API door now, so the pair is made by keyword alone.
    $outA = Invoke-SD @(('CREATE.ACCOUNT USER ' + $apiAcct + ' API'), $apiPw, $apiPw)
    Write-Output '  --- CREATE.ACCOUNT (API) said: ---'
    Write-Output $outA

    $outP = Invoke-SD (New-SdTestUserScript -Name $sshAcct -Password $sshPw)
    Write-Output '  --- CREATE.ACCOUNT (SSH only) said: ---'
    Write-Output $outP

    # ***THE CONTROL IS WINDOWS, NOT SD's WORDING.***  A verb that refused still
    # echoes the account name it was given, so reading the transcript back for
    # it is the false-positive shape CLAUDE.md names after ZZIDALLOW.
    $madeApi = ($null -ne (Get-LocalUser -Name $apiAcct -ErrorAction SilentlyContinue))
    $madeSsh = ($null -ne (Get-LocalUser -Name $sshAcct -ErrorAction SilentlyContinue))
    Note 'the API account exists in Windows'      $true $madeApi
    Note 'the SSH-only account exists in Windows' $true $madeSsh
    if (-not ($madeApi -and $madeSsh)) {
        # ***NAME THE MALFORMED-COMMAND CASE SEPARATELY.***  "an account was not
        # created" is true of a refused CREATE.ACCOUNT and of a mistyped one
        # alike, and the second is a fault in THIS script rather than in the
        # product.  CREATEA prints "Command Syntax:" only on its invalid-argument
        # path, so it is a safe anchor for that one cause.
        $syntax = (($outA + "`n" + $outP) -match 'Command Syntax:')
        if ($syntax) {
            Write-Output ''
            Write-Output '  CREATE.ACCOUNT printed its SYNTAX message, so a command above is malformed'
            Write-Output '  and this is a fault in this script, not in SD.'
            Refuse 'a CREATE.ACCOUNT command was malformed - see the syntax message above.'
        }
        Refuse 'an account was not created - nothing below could measure anything.'
    }

    # THE FIXTURE MUST BE WHAT IT CLAIMS, or leg B measures a mislabelled account: the API
    # account holds sdapi, the SSH-only account does not.  (verify-routes.ps1 owns group
    # membership as a subject; here it is a precondition, so it is scored as one.)
    Note 'fixture: the API account is in sdapi'          $true  (InGroup 'sdapi' $apiAcct)
    Note 'fixture: the SSH-only account is NOT in sdapi' $false (InGroup 'sdapi' $sshAcct)
    Note 'fixture: the SSH-only account is in sdssh'     $true  (InGroup 'sdssh' $sshAcct)

    # -----------------------------------------------------------------------
    Step 2 "enabling APIPORT=$Port and restarting SD"

    Copy-Item -LiteralPath $conf -Destination $backup -Force
    $restoreNeeded = $true
    $lines = @(Get-Content -LiteralPath $conf) | Where-Object { $_ -notmatch '^\s*APIPORT\s*=' }
    $lines += ('APIPORT=' + $Port)
    Set-Content -LiteralPath $conf -Value $lines -Encoding Ascii

    # read_config() runs only when the shared segment is CREATED, so this has
    # to be a restart rather than a reload.
    if (-not (Stop-SD))  { Refuse 'SD would not stop - close any open session and try again.' }
    if (-not (Start-SD)) { Refuse 'SD would not start again.  Read the SD error log.' }
    Start-Sleep -Seconds 2

    $listen = @(& "$env:SystemRoot\System32\netstat.exe" -an |
                Where-Object { $_ -match (':' + $Port + '\s') })
    Note 'a listener on the port' $true ($listen.Count -gt 0)
    foreach ($l in $listen) { Write-Output ('   ' + $l.ToString().Trim()) }
    if ($listen.Count -eq 0) { Refuse "nothing is listening on port $Port." }

    # -----------------------------------------------------------------------
    Step 3 'a non-loopback address for THIS machine, that actually answers'

    # ***AN ADDRESS IS NOT A ROUTE, AND b121 PAID FOR THAT DISTINCTION*** in
    # verify-sshadmin.ps1: the first version took the first non-loopback IPv4 it
    # found, which sat on a DISCONNECTED adapter, so the remote leg measured
    # nothing.  Require the adapter Up AND the API port to actually accept.
    $lanIp = ''
    $candidates = @()
    try {
        $candidates = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                        Where-Object { $_.IPAddress -notlike '127.*' -and
                                       $_.IPAddress -notlike '169.254.*' })
    } catch { }
    foreach ($c in $candidates) {
        $status = ''
        try { $status = (Get-NetAdapter -InterfaceIndex $c.InterfaceIndex -ErrorAction Stop).Status } catch { }
        $reach = $false
        if ($status -eq 'Up') {
            try {
                $reach = (Test-NetConnection -ComputerName $c.IPAddress -Port $Port `
                              -WarningAction SilentlyContinue -ErrorAction Stop).TcpTestSucceeded
            } catch { }
        }
        Write-Output ("  candidate {0,-16} adapter={1,-14} port{2}={3}" -f
                      $c.IPAddress, $(if ($status) { $status } else { '?' }), $Port, $reach)
        if ($reach -and -not $lanIp) { $lanIp = $c.IPAddress }
    }
    Write-Output ("  address for the REMOTE legs: {0}" -f
                  $(if ($lanIp) { $lanIp } else { '<none>' }))

    # REFUSE THE NULL CASE.  With no reachable routable address there is no remote leg and no
    # CONTROL: every remaining row would pass on a machine with no remote API at all, a green
    # meaning nothing.  This is also the honest answer on a machine whose firewall keeps the
    # API loopback-only, which is the shipped default.
    if (-not $lanIp) {
        Write-Output ''
        Write-Output '  No non-loopback IPv4 address on this machine accepts a connection on the'
        Write-Output '  API port.  That is the SHIPPED posture - remote.api is off by default - so'
        Write-Output '  it is not a fault; it does mean the address pair cannot be exercised here.'
        Write-Output '  Run "remote.api on" in an SDSYS session first, and put it back afterwards.'
        Refuse 'there is no remote route to drive, so the door cannot be measured over the network.'
    }

    # -----------------------------------------------------------------------
    Step 4 'the audit trail, before'
    $before = [IO.File]::ReadAllText($audit)
    Write-Output ("  audit is {0} bytes before" -f $before.Length)

    # -----------------------------------------------------------------------
    Step 5 "CONTROL - the API account via $lanIp - MUST BE ADMITTED"
    $rc = Invoke-Api $lanIp $apiAcct $apiPw $apiAcct.ToUpper() 'WHO'
    Write-Output ("  client exit {0}" -f $rc.Rc)
    Write-Output '  --- the client said: ---'
    Write-Output $rc.Text

    # -----------------------------------------------------------------------
    Step 6 'LEG A - the SAME API account over 127.0.0.1 - MUST BE ADMITTED'
    $ra = Invoke-Api '127.0.0.1' $apiAcct $apiPw $apiAcct.ToUpper() 'WHO'
    Write-Output ("  client exit {0}" -f $ra.Rc)
    Write-Output '  --- the client said: ---'
    Write-Output $ra.Text

    # -----------------------------------------------------------------------
    Step 7 "LEG B - the SSH-ONLY account via $lanIp - MUST BE REFUSED"
    $rb = Invoke-Api $lanIp $sshAcct $sshPw $sshAcct.ToUpper() 'WHO'
    Write-Output ("  client exit {0}" -f $rb.Rc)
    Write-Output '  --- the client said: ---'
    Write-Output $rb.Text

    # -----------------------------------------------------------------------
    Step 8 'LEG C - the SSH-ONLY account over 127.0.0.1 - MUST BE REFUSED'
    $rcx = Invoke-Api '127.0.0.1' $sshAcct $sshPw $sshAcct.ToUpper() 'WHO'
    Write-Output ("  client exit {0}" -f $rcx.Rc)
    Write-Output '  --- the client said: ---'
    Write-Output $rcx.Text

    # -----------------------------------------------------------------------
    Step 9 'the verdict'

    # ***THE CONTROL IS SCORED FIRST AND IT GATES EVERYTHING.***  If an account with the API
    # route cannot connect over the LAN address, the listener or the firewall is shut and the
    # refusals below say nothing about the keyword.
    $controlIn = ($rc.Text -match 'PROBE\.CONNECT=YES')
    Note 'CONTROL: the API account connects over the LAN address' $true $controlIn
    if (-not $controlIn) {
        Write-Output ''
        Write-Output '  The CONTROL did not get in, so the network route itself is suspect.'
        Write-Output '  Legs B and C are NOT scored below - a refusal there would prove nothing about the keyword.'
        Refuse 'the control leg failed, so the door cannot be measured.'
    }

    # LEG A - the ADDRESS makes no difference.  PROBE.CONNECT=YES is printed only after
    # SDConnect() returned a session, so the refusal path cannot say it.
    $localIn = ($ra.Text -match 'PROBE\.CONNECT=YES')
    Note 'LEG A: the same account over loopback IS admitted too' $true $localIn
    Note 'LEG A: not refused by the sdapi gate (10073 absent)' $false `
         ($ra.Text -match '(?i)is not permitted to use the API')

    # LEGS B AND C - the KEYWORD decides.  Scored on the success anchor's ABSENCE and on 10073's
    # own wording being PRESENT, both, because a connection can fail for a dozen reasons that are
    # not the gate.
    foreach ($x in @(@{ N = 'LEG B (LAN address)'; T = $rb.Text }, @{ N = 'LEG C (loopback)'; T = $rcx.Text })) {
        Note ($x.N + ': the SSH-only account did NOT get a session') $false ($x.T -match 'PROBE\.CONNECT=YES')
        Note ($x.N + ': message 10073 was returned to the client') $true ($x.T -match '(?i)is not permitted to use the API')
    }

    # ***THE PAIRS ARE THE POINT.***  Same account over two addresses went the SAME way (the
    # address is not read), and two accounts differing only in keyword went DIFFERENT ways (the
    # keyword is).  If both were true of a broken door - one that admitted everything or refused
    # everything - a single leg would look like a pass.
    Note 'the ADDRESS made no difference (control and leg A agree)' $true ($controlIn -eq $localIn)
    Note 'the KEYWORD decided (API account in, SSH-only account out, on the SAME address)' $true `
         ($controlIn -and -not ($rb.Text -match 'PROBE\.CONNECT=YES'))

    # -----------------------------------------------------------------------
    Step 10 'the audit trail, after - THE DECISIVE READING'
    $after = [IO.File]::ReadAllText($audit)
    $tail  = $after.Substring([Math]::Min($before.Length, $after.Length))
    Write-Output ("  audit grew by {0} bytes" -f ($after.Length - $before.Length))
    Write-Output '  --- what APISRVR wrote ---'
    foreach ($l in ($tail -split "`r?`n")) {
        if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
    }

    # Written at exit.vb.scram.fail and nowhere else.  A session that never reached the gate
    # cannot produce this line, and it NAMES THE USER, which is what ties it to leg B and not to
    # some other refusal on the machine.
    $auditRefused = ($tail -match ('(?i)API REFUSED user=' + [regex]::Escape($sshAcct) + '\b.*reason=not in sdapi'))
    Note 'the audit records the SSH-only account''s refusal, with the reason (not in sdapi)' $true $auditRefused
    Note 'the audit has NO refusal for the API account' $false `
         ($tail -match ('(?i)API REFUSED user=' + [regex]::Escape($apiAcct) + '\b'))

    # A trail that did not move at all means the session never reached APISRVR -
    # which is not the gate working, it is the measurement failing.
    Note 'the audit trail actually moved' $true (($after.Length - $before.Length) -gt 0)

} finally {
    Write-Output ''
    Write-Output '== cleanup'

    if ($restoreNeeded -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $conf -Force
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        Write-Output '  sd.conf restored'
        $null = Stop-SD
        $null = Start-SD
        Write-Output '  SD restarted on the restored configuration'
    }

    foreach ($acct in @($apiAcct, $sshAcct)) {
        $exists = ($null -ne (Get-LocalUser -Name $acct -ErrorAction SilentlyContinue))
        if (-not $exists) { continue }
        try {
            $rm = Invoke-SD (Remove-SdTestUserScript -Name $acct)
            Write-Output ("  DELETE.ACCOUNT {0}:" -f $acct)
            Write-Output $rm
        } catch {
            Write-Output ("  DELETE.ACCOUNT {0} threw: {1}" -f $acct, $_.Exception.Message)
        }
        $still = ($null -ne (Get-LocalUser -Name $acct -ErrorAction SilentlyContinue))
        if ($still) {
            # NAMED, LOUDLY: an account with a generated password left behind silently is the
            # worst outcome this script can have.
            Write-Output ''
            Write-Output ('  *** verify-apiremote: ACCOUNT STILL EXISTS: ' + $acct)
            Write-Output  '  *** Remove it by hand.  In an ELEVATED PowerShell:'
            Write-Output ('  ***   Remove-LocalUser -Name ' + $acct)
        }
    }
}

Write-Output ''
Write-Output ("verify-apiremote: {0} passed, {1} failed" -f $pass, $fail)
if (($pass + $fail) -eq 0) { Write-Output 'verify-apiremote: COULD NOT RUN - no decisive check ran'; exit 2 }
if ($fail -gt 0) { exit 1 }
exit 0
