<#
.SYNOPSIS
    Is an SD administrator refused a REMOTE API session, and still admitted a
    LOCAL one?

.DESCRIPTION
    PRE_RELEASE_FIXES.md 170.  This is the API half of the 5 Sep 2026 ruling
    whose ssh half verify-sshadmin.ps1 witnessed on b122.  Owner: "remote admin
    through api or ssh is just a security nightmare waiting to happen",
    refined the same day to "if I am at the console, everything works, only
    remote access is denied".  REMOTE is what is denied, not the API.

    WHAT IT MEASURES.  APISRVR's vb.scram.final gate, added 5 Sep 2026 after
    the SCRAM proof and beside the sdapi test:

        call !peer_local(api.peer.local, api.peer.addr)
        if sd_admin_tier(scram.user) and not(api.peer.local) then ... refuse

    WHY IT COULD NOT BE FOLDED INTO verify-apiadmin.ps1.  That script connects
    over LOOPBACK with a PROGRAMMER account, so this gate never fires there -
    which is also why it must not regress.  This one needs an ADMINISTRATOR and
    two different routes to the same machine.

    THE THREE LEGS, AND THE CONTROL IS SCORED FIRST.

      CONTROL  a PROGRAMMER over the LAN address        MUST BE ADMITTED
      LEG A    the ADMINISTRATOR over 127.0.0.1         MUST BE ADMITTED
      LEG B    the SAME ADMINISTRATOR over the LAN IP   MUST BE REFUSED

    THE CONTROL GATES THE REST.  If a non-administrator cannot connect over the
    LAN address either, the listener or the firewall is shut and leg B's
    refusal says nothing about the gate.  Without it, a machine with no remote
    API at all would score a confident green.

    AND THE PAIR IS THE POINT.  Legs A and B are the same account, the same
    password and the same host; the ONLY variable is the address.  If both go
    the same way the gate is not reading the route - it is admitting or
    refusing everything - and either can look like a pass on a single leg.

    LEG A IS THE OWNER'S OWN CASE.  He runs a local application against the API
    on 127.0.0.1 as an administrator account, which is what made "is a LOCAL
    API session admitted" a ruling rather than a detail.  A green leg B with a
    red leg A is not a partial pass, it is a broken product.

    WHAT IT ANCHORS ON.  tests/api_admin_probe.c prints PROBE.CONNECT=YES only
    after SDConnect() returned a session, and PROBE.CONNECT=NO with SDError()
    otherwise.  The success wording therefore cannot appear on the refusal
    path, which is the rule CLAUDE.md states after ZZIDALLOW.  The refusal is
    scored twice over: message 10174's own words, and the audit line APISRVR
    writes at exit.vb.scram.fail - "API REFUSED user=... reason=administrator
    on a remote API session from ..." - which is written there and nowhere
    else, and which a session that never reached the gate cannot produce.

    WHAT IT DOES NOT COVER, AND IT IS WRITTEN DOWN RATHER THAN ASSUMED AWAY.
    An "ssh -L" tunnel terminates on this host, so a tunnelled API connection
    is accepted FROM 127.0.0.1 and this gate reads it as local.  No peer test
    can see through that; it is an sshd matter (AllowTcpForwarding, or a Match
    block).  PRE_RELEASE_FIXES 170 carries it.

    IT CHANGES THE INSTALLED SYSTEM AND PUTS IT BACK: two throwaway Windows and
    SD accounts, an sd.conf APIPORT line, and two SD restarts.  The accounts go
    in a finally block, and anything that could not be removed is NAMED - one
    of them is a real local administrator while it exists.

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

Write-Output 'verify-apiremote - PRE_RELEASE_FIXES.md 170 (the API half of 167)'
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
    Refuse 'run this ELEVATED - it creates accounts, edits the installed sd.conf and restarts SD.'
}

# ***CHECK THE SERVICE BEFORE MAKING ACCOUNTS, NOT AFTER.***  The name was wrong
# once (see Stop-SD), and because the check lived inside step 2 the run had
# already created two Windows accounts - one a real local ADMINISTRATOR - and
# edited sd.conf before it found out.  Cleanup handled it, but a guard that can
# fire early should.
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
# Piped stdin.  Start-Process -RedirectStandardInput hands sd.exe a FILE HANDLE
# and SD answers ":Process terminated" and runs nothing - written down 14 Aug
# 2026 and paid for again on 29 Aug.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    if ($null -eq $commands -or $commands.Count -eq 0) {
        throw 'Invoke-SD: no commands given; that would start a session, measure nothing and look like a pass.'
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

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
# once rather than at each of the three call sites.
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

$adminAcct = ($Prefix + 'a')
$progAcct  = ($Prefix + 'p')
$adminPw   = New-SdTestPassword
$progPw    = New-SdTestPassword
$restoreNeeded = $false

try {
    # -----------------------------------------------------------------------
    Step 1 'two accounts: one ADMINISTRATOR, one PROGRAMMER'

    # ADMINISTRATOR is matched on the token TEXT (CREATEA) and cannot be
    # abbreviated.
    #
    # ***THE ROUTE KEYWORD IS MANDATORY AND LEAVING IT OFF COST A RUN.***  The
    # first version of this line read "... ADMINISTRATOR" with no keyword, on
    # the reasoning that an administrator is granted both routes unconditionally
    # and cannot have either removed (PRE_RELEASE 169).  That is true of the
    # GRANT and says nothing about the SYNTAX: CREATEA's own header records
    # "SSH, API, BOTH or NONE, required for a USER account", so the parse fell
    # to its "invalid command arg" case, printed the syntax line and created
    # nothing.  The step then refused at the account check below - correctly,
    # and for a reason that looked like a product fault until the transcript
    # was read.  BOTH is what the ADMINISTRATOR tier forces anyway, so this
    # names what the account actually gets.
    $outA = Invoke-SD @(('CREATE.ACCOUNT USER ' + $adminAcct + ' ADMINISTRATOR BOTH'), $adminPw, $adminPw)
    Write-Output '  --- CREATE.ACCOUNT (administrator) said: ---'
    Write-Output $outA

    $outP = Invoke-SD (New-SdTestUserScript -Name $progAcct -Password $progPw)
    Write-Output '  --- CREATE.ACCOUNT (programmer) said: ---'
    Write-Output $outP

    # The control needs the API explicitly; CREATE.ACCOUNT no longer joins
    # sdapi for an ordinary tier (verify-apiadmin.ps1 step 7a is the witness).
    $outG = Invoke-SD @('MODIFY.ACCOUNT ' + $progAcct + ' API')
    Write-Output '  --- MODIFY.ACCOUNT ... API said: ---'
    Write-Output $outG

    # ***THE CONTROL IS WINDOWS, NOT SD's WORDING.***  A verb that refused still
    # echoes the account name it was given, so reading the transcript back for
    # it is the false-positive shape CLAUDE.md names after ZZIDALLOW.
    $madeAdmin = ($null -ne (Get-LocalUser -Name $adminAcct -ErrorAction SilentlyContinue))
    $madeProg  = ($null -ne (Get-LocalUser -Name $progAcct  -ErrorAction SilentlyContinue))
    Note 'the administrator account exists in Windows' $true $madeAdmin
    Note 'the programmer account exists in Windows'    $true $madeProg
    if (-not ($madeAdmin -and $madeProg)) {
        # ***NAME THE MALFORMED-COMMAND CASE SEPARATELY.***  "an account was not
        # created" is true of a refused CREATE.ACCOUNT and of a mistyped one
        # alike, and the second is a fault in THIS script rather than in the
        # product - which is exactly how the first run of it was read.  CREATEA
        # prints "Command Syntax:" only on its invalid-argument path, so it is
        # a safe anchor for that one cause.
        $syntax = (($outA + "`n" + $outP + "`n" + $outG) -match 'Command Syntax:')
        if ($syntax) {
            Write-Output ''
            Write-Output '  CREATE.ACCOUNT printed its SYNTAX message, so a command above is malformed'
            Write-Output '  and this is a fault in this script, not in SD.  The route keyword'
            Write-Output '  (SSH | API | BOTH | NONE) is REQUIRED for a USER account - CREATEA header.'
            Refuse 'a CREATE.ACCOUNT command was malformed - see the syntax message above.'
        }
        Refuse 'an account was not created - nothing below could measure anything.'
    }

    # AND THE ADMINISTRATOR ONE MUST REALLY BE ONE, or leg B proves nothing: a
    # refusal of a non-administrator is not the rule under test.
    $admins = @()
    try {
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
                    ForEach-Object { ($_.Name -split '\\')[-1].ToLower() })
    } catch {
        Refuse ('could not read the Administrators group - ' + $_.Exception.Message)
    }
    Note 'Administrators was readable'                  $true  ($admins.Count -gt 0)
    Note 'the admin account IS a Windows administrator' $true  ($admins -contains $adminAcct)
    Note 'the control account is NOT'                   $false ($admins -contains $progAcct)

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

    # REFUSE THE NULL CASE.  With no reachable routable address there is no
    # remote leg, and leg A alone would show an administrator ADMITTED with
    # nothing demonstrating that a remote one is refused - a green meaning
    # nothing.  This is also the honest answer on a machine whose firewall
    # keeps the API loopback-only, which is the shipped default.
    if (-not $lanIp) {
        Write-Output ''
        Write-Output '  No non-loopback IPv4 address on this machine accepts a connection on the'
        Write-Output '  API port.  That is the SHIPPED posture - remote.api is off by default - so'
        Write-Output '  it is not a fault; it does mean the gate cannot be exercised here.'
        Write-Output '  Run "remote.api on" in an SDSYS session first, and put it back afterwards.'
        Refuse 'there is no remote route to drive, so the gate cannot be measured at all.'
    }

    # -----------------------------------------------------------------------
    Step 4 'the audit trail, before'
    $before = [IO.File]::ReadAllText($audit)
    Write-Output ("  audit is {0} bytes before" -f $before.Length)

    # -----------------------------------------------------------------------
    Step 5 "CONTROL - a PROGRAMMER via $lanIp - MUST BE ADMITTED"
    $rc = Invoke-Api $lanIp $progAcct $progPw $progAcct.ToUpper() 'WHO'
    Write-Output ("  client exit {0}" -f $rc.Rc)
    Write-Output '  --- the client said: ---'
    Write-Output $rc.Text

    # -----------------------------------------------------------------------
    Step 6 'LEG A - the ADMINISTRATOR over 127.0.0.1 - MUST BE ADMITTED'
    Write-Output '  Owner, 5 Sep 2026: "local API and SSH should continue to work".'
    Write-Output '  This is his own case - a local application on 127.0.0.1 as an administrator.'
    $ra = Invoke-Api '127.0.0.1' $adminAcct $adminPw $adminAcct.ToUpper() 'WHO'
    Write-Output ("  client exit {0}" -f $ra.Rc)
    Write-Output '  --- the client said: ---'
    Write-Output $ra.Text

    # -----------------------------------------------------------------------
    Step 7 "LEG B - the SAME ADMINISTRATOR via $lanIp - MUST BE REFUSED"
    $rb = Invoke-Api $lanIp $adminAcct $adminPw $adminAcct.ToUpper() 'WHO'
    Write-Output ("  client exit {0}" -f $rb.Rc)
    Write-Output '  --- the client said: ---'
    Write-Output $rb.Text

    # -----------------------------------------------------------------------
    Step 8 'the verdict'

    # ***THE CONTROL IS SCORED FIRST AND IT GATES EVERYTHING.***  If a
    # non-administrator cannot connect over the LAN address either, the
    # listener or the firewall is shut and leg B's refusal says nothing.
    $controlIn = ($rc.Text -match 'PROBE\.CONNECT=YES')
    Note 'CONTROL: a non-administrator connects over the LAN address' $true $controlIn
    if (-not $controlIn) {
        Write-Output ''
        Write-Output '  The CONTROL did not get in, so the remote route itself is suspect.'
        Write-Output '  Leg B is NOT scored below - a refusal there would prove nothing about the gate.'
        Refuse 'the control leg failed, so the gate cannot be measured.'
    }

    # LEG A - LOCAL - MUST BE ADMITTED.  PROBE.CONNECT=YES is printed only
    # after SDConnect() returned a session, so the refusal path cannot say it.
    $localIn = ($ra.Text -match 'PROBE\.CONNECT=YES')
    Note 'LOCAL: an administrator over loopback IS admitted' $true $localIn

    # And the disqualifier for the same leg: the refusal wording must NOT appear.
    $localRefused = ($ra.Text -match '(?i)may not sign in')
    Note 'LOCAL: no refusal message was shown' $false $localRefused

    # LEG B - REMOTE - MUST BE REFUSED, scored on the success anchor's ABSENCE
    # and on 10174's own wording being PRESENT.  Both, because a connection can
    # fail for a dozen reasons that are not this gate.
    $remoteIn = ($rb.Text -match 'PROBE\.CONNECT=YES')
    Note 'REMOTE: the administrator did NOT get a session' $false $remoteIn

    $remoteMsg = ($rb.Text -match '(?i)may not sign in to this machine from another one')
    Note 'REMOTE: message 10174 was returned to the client' $true $remoteMsg

    # ***AND THE PAIR IS THE POINT.***  Same account, same password, same host,
    # two addresses.  If both legs went the same way the gate is not reading the
    # route at all - it is admitting everything or refusing everything - and
    # either of those can look like a pass on a single leg.
    Note 'the two routes were treated DIFFERENTLY' $true ($localIn -ne $remoteIn)

    # -----------------------------------------------------------------------
    Step 9 'the audit trail, after - THE DECISIVE READING'
    $after = [IO.File]::ReadAllText($audit)
    $tail  = $after.Substring([Math]::Min($before.Length, $after.Length))
    Write-Output ("  audit grew by {0} bytes" -f ($after.Length - $before.Length))
    Write-Output '  --- what APISRVR wrote ---'
    foreach ($l in ($tail -split "`r?`n")) {
        if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
    }

    # Written at exit.vb.scram.fail and nowhere else.  A session that never
    # reached the gate cannot produce this line.
    $auditRefused = ($tail -match '(?i)API REFUSED' -and
                     $tail -match '(?i)administrator on a remote API session')
    Note 'the audit records the REMOTE refusal, with the reason' $true $auditRefused

    # AND THE ADDRESS IS IN IT, which is what distinguishes "the gate fired"
    # from "the gate fired for some other reason".
    $auditAddr = ($tail -match ('(?i)remote API session from\s+' + [regex]::Escape($lanIp)))
    Note 'the refusal names the address it refused' $true $auditAddr

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

    foreach ($acct in @($adminAcct, $progAcct)) {
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
            # NAMED, LOUDLY.  One of these is a local ADMINISTRATOR with a
            # generated password; leaving it behind silently is the worst
            # outcome this script can have.
            Write-Output ''
            Write-Output ('  *** verify-apiremote: ACCOUNT STILL EXISTS: ' + $acct)
            Write-Output  '  *** Remove it by hand.  In an ELEVATED PowerShell:'
            Write-Output ('  ***   Remove-LocalUser -Name ' + $acct)
            Write-Output  '  *** If it was the administrator one, check it is out of Administrators too.'
        }
    }
}

Write-Output ''
Write-Output ("verify-apiremote: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
