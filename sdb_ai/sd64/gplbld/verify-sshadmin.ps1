# verify-sshadmin.ps1 - prove that an SD ADMINISTRATOR gets no ssh session at
# all, and that a non-administrator still does.
#
#   powershell -ExecutionPolicy Bypass -File verify-sshadmin.ps1 -Prefix sdsshadm<run>
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# RUN IT ELEVATED.  CREATE.ACCOUNT is gated on K$ADMINISTRATOR, and this makes
# two accounts.  VerifyInstall2 is already elevated, so it costs no extra UAC
# prompt; run by hand it needs an elevated PowerShell.
#
# WHAT IT MEASURES.  PRE_RELEASE_FIXES.md 167 and PROJECT_STATUS.md 5.25.
# Owner's ruling, 5 Sep 2026: remote ssh and API access is TOTALLY DENIED to
# administrators - administration happens at the console or through a remote
# desktop installed as a service.  LOGIN refuses the session outright when
# sd_admin_tier(@logname) is true and kernel(K$INTERACTIVE, 0) is false.
#
#   ADMINISTRATOR via localhost   ADMITTED, runs a command    <- local is allowed
#   ADMINISTRATOR via the LAN IP  REFUSED, message 10174      <- the gate
#
# ***18 Sep 26 - RELEASE_1.1 58 CHANGED BOTH LEGS AND THE LAYER THAT REFUSES.***
# An administrator now gets NO ssh session from any address, loopback included
# (the owner withdrew the local exception: "I don't have any problem with it not
# being available on the local computer"), and the refusal happens in SSHD
# rather than in SD, because the administrators group left AllowGroups.  So
# message 10174 and LOGIN's audit line are now ABSENCES to assert rather than
# evidence to find - LOGIN is never reached - and the discriminator is the TIER
# against the control, not the route against itself.  The leg table above is
# kept as the shape this file was built for; the rows below are what it does.
#   PROGRAMMER    via localhost   ADMITTED, runs a command    <- the CONTROL
#
# ***IT IS REMOTE THAT IS DENIED, NOT ssh.***  Owner's refinement, 5 Sep 2026:
# "my lockout from remote API and SSH is fine.  However, local API and SSH
# should continue to work - if I am at the console, everything works, only
# remote access is denied."  THE FIRST VERSION OF THIS SCRIPT MEASURED THE
# NARROWER RULE AND PASSED 10/0 ON IT: it ssh'd to localhost, was refused, and
# scored that as the gate working.  It was the gate working as specified, and
# the specification was narrower than the ruling.
#
# ***THE PAIR IS THE INSTRUMENT.***  Legs A and B are the SAME ACCOUNT, the same
# password and the same host, reached by two addresses - so the only variable
# between "admitted" and "refused" is the route.  A single leg cannot show that:
# a gate that admitted everything and a gate that refused everything would each
# pass one of them.  The last check scores the DIFFERENCE for exactly that
# reason.
#
# AND THE THIRD LEG IS STILL THE ORDINARY CONTROL - a non-administrator over the
# same loopback route - because a refusal has causes that are nothing to do with
# the gate: sshd stopped, ForceCommand not starting SD, a rejected password, a
# changed host key.
#
# WHY IT NEEDS NO SECOND MACHINE, WHICH IS WHAT PARKED q14 FOR WEEKS.  ssh to
# one of this machine's OWN LAN addresses leaves and returns over the interface,
# and sshd then reports SSH_CLIENT as that address rather than 127.0.0.1 - which
# is the only thing LOGIN's peer test reads.  A routable address is required and
# its absence is refused out loud: without one there is no remote leg, and leg A
# alone would show an administrator admitted with nothing showing a remote one
# refused.
#
# ***IT CREATES A REAL LOCAL ADMINISTRATOR, BRIEFLY, AND THAT IS DELIBERATE.***
# CREATE.ACCOUNT ... ADMINISTRATOR adds the Windows account to S-1-5-32-544
# (CREATEA:872), so leg A's account is a Windows administrator as well as an SD
# one - which is the state the defect was measured in.  verify-tiers.ps1 already
# makes one for the same reason.  Both accounts are removed in a finally block,
# and if removal fails the account is NAMED on the transcript rather than left
# silently behind.
#
# ANCHORED ON THE AUDIT TRAIL, NOT ON THE SCREEN.  The decisive reading is
# LOGIN's own record - "LOGIN REFUSED account=SDSYS reason=administrator on a
# session with no interactive desktop" - because it is written on the refusal
# path and nowhere else.  Message 10174's text is recorded too, and scored, but
# a screen can be empty for a dozen reasons; the audit line cannot be written by
# a session that never reached the gate.

[CmdletBinding()]
param(
    # Derived from -Run by the runner.  A FIXED prefix passes once and fails
    # every later run - PRE_RELEASE 54 - which is why this goes through
    # VerifyInstall2 rather than being called by hand with a constant.
    # Lower case only: it becomes a Windows account name.
    [string]$Prefix = ''

    # NO -HelperPipe, DELIBERATELY, and test-elevonce-units.ps1 is why this
    # sentence exists.  One was declared here in the first draft and never used:
    # this step launches no elevated child - the runner is already elevated and
    # Invoke-SD runs in-process - so there was nothing for a pipe to serve.
    # That guard's bidirectional check caught it in a second, which is exactly
    # the shape it was written for.  verify-sdsysgate.ps1 takes none either, for
    # the same reason.  If this ever DOES start an elevated child, add the
    # parameter AND the name to $helperAware in elevate-once.ps1, together.
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }

. (Join-Path $here 'sdtestuser.ps1')

$sd64  = Split-Path $here -Parent
$sdExe = Join-Path $sd64 'bin\sd.exe'

$pass = 0
$fail = 0

function Note([string]$name, $expected, $got, [bool]$decisive) {
    $ok = ($expected -eq $got)
    if ($decisive) {
        if ($ok) { $script:pass++ } else { $script:fail++ }
    }
    $tag = if ($ok) { 'PASS' } else { if ($decisive) { 'FAIL' } else { 'note' } }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $tag, $name, $expected, $got)
}

Write-Output 'verify-sshadmin - PRE_RELEASE_FIXES.md 167, PROJECT_STATUS.md 5.25'
Write-Output ("  prefix : {0}" -f $Prefix)
Write-Output ("  sd.exe : {0}" -f $sdExe)

# ---------------------------------------------------------------- refusals
# Every one of these is "the test could not be run", not "the product failed".

if ($Prefix -eq '') {
    Write-Output 'verify-sshadmin: no -Prefix. The runner derives it from -Run; a fixed one passes once (PRE_RELEASE 54).'
    exit 2
}
if ($Prefix -cne $Prefix.ToLower()) {
    Write-Output "verify-sshadmin: -Prefix must be lower case - it becomes a Windows account name."
    exit 2
}
if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output ("verify-sshadmin: no sd.exe at {0} - nothing could be measured." -f $sdExe)
    exit 2
}
if ($null -eq (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
    Write-Output 'verify-sshadmin: no ssh.exe on PATH - the whole measurement is over ssh.'
    exit 2
}
$elevated = ([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
Note 'this process is elevated' $true $elevated $false
if (-not $elevated) {
    Write-Output 'verify-sshadmin: this needs an ELEVATED PowerShell - CREATE.ACCOUNT is gated on K$ADMINISTRATOR.'
    exit 2
}

# Where LOGIN writes its refusals.
$dataDir = Join-Path $env:ProgramData 'SD'
$audit   = Join-Path $dataDir 'sdsys\audit'
if (-not (Test-Path -LiteralPath $audit)) {
    # Some installs name it differently; find it rather than guess, and refuse
    # rather than score a leg whose evidence cannot be read.
    $found = Get-ChildItem -Path (Join-Path $dataDir 'sdsys') -Filter 'audit*' -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($null -ne $found) { $audit = $found.FullName }
}
Write-Output ("  audit  : {0}" -f $audit)
if (-not (Test-Path -LiteralPath $audit)) {
    Write-Output 'verify-sshadmin: the audit trail does not exist - the decisive reading is unavailable.'
    exit 2
}
Write-Output ''

# ------------------------------------------------------------- local driver
# Piped stdin, in a job with a timeout.  Start-Process -RedirectStandardInput
# hands sd.exe a FILE HANDLE and SD answers ":Process terminated" and runs
# nothing - written down 14 Aug 2026 and paid for again on 29 Aug.
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

$adminAcct = ($Prefix + 'a')
$progAcct  = ($Prefix + 'p')
$adminPw   = New-SdTestPassword
$progPw    = New-SdTestPassword
$madeAdmin = $false
$madeProg  = $false

try {
    Write-Output '=== 1. two accounts: one ADMINISTRATOR, one PROGRAMMER ============'

    # ADMINISTRATOR is matched on the token TEXT (CREATEA:1524) and cannot be
    # abbreviated.  SSH so the account may be reached at all.
    # 18 Sep 26 - "SSH" REMOVED.  RELEASE_1.1 58: an administrator gets no
    # remote door, and CREATE.ACCOUNT now REFUSES the combination rather than
    # overriding it, so the old command created nothing and this script exited 2
    # on b196 with "an account was not created".  The keyword that matters here
    # is ADMINISTRATOR - the tier is the whole subject of the test.
    $outA = Invoke-SD @(('CREATE.ACCOUNT USER ' + $adminAcct + ' ADMINISTRATOR'), $adminPw, $adminPw)
    Write-Output '  --- CREATE.ACCOUNT (administrator) said: ---'
    Write-Output $outA

    $outP = Invoke-SD (New-SdTestUserScript -Name $progAcct -Password $progPw)
    Write-Output '  --- CREATE.ACCOUNT (programmer) said: ---'
    Write-Output $outP

    # ***THE CONTROL IS WINDOWS, NOT SD's WORDING.***  A verb that refused still
    # echoes the account name it was given, so reading the transcript back for
    # it is the false-positive shape CLAUDE.md names.
    $madeAdmin = ($null -ne (Get-LocalUser -Name $adminAcct -ErrorAction SilentlyContinue))
    $madeProg  = ($null -ne (Get-LocalUser -Name $progAcct  -ErrorAction SilentlyContinue))
    Note 'the administrator account exists in Windows' $true $madeAdmin $true
    Note 'the programmer account exists in Windows'    $true $madeProg  $true
    if (-not ($madeAdmin -and $madeProg)) {
        Write-Output 'verify-sshadmin: an account was not created - nothing below could measure anything.'
        exit 2
    }

    # AND THE ADMINISTRATOR ONE MUST REALLY BE ONE, or leg A proves nothing: a
    # refusal of a non-administrator is not the rule under test.
    $admins = @()
    try {
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
                    ForEach-Object { ($_.Name -split '\\')[-1].ToLower() })
    } catch {
        Write-Output ('verify-sshadmin: could not read the Administrators group - ' + $_.Exception.Message)
        exit 2
    }
    Note 'Administrators was readable'                  $true ($admins.Count -gt 0)        $true
    Note 'the admin account IS a Windows administrator' $true ($admins -contains $adminAcct) $true
    Note 'the control account is NOT'                   $false ($admins -contains $progAcct) $true
    Write-Output ''

    # --------------------------------------------------------- the measurement

    Write-Output '=== 2. the audit trail, before ===================================='
    $before = [IO.File]::ReadAllText($audit)
    Write-Output ("  audit is {0} bytes before" -f $before.Length)
    Write-Output ''

    # ***A NON-LOOPBACK ADDRESS FOR THIS SAME MACHINE.***  ssh to it and the
    # packet leaves and returns over the interface, so sshd reports SSH_CLIENT
    # as that address rather than 127.0.0.1 - which is the only thing LOGIN's
    # peer test reads.  Same host, same account, same password: the ONLY
    # variable between legs A and B is the route.
    # ***AN ADDRESS IS NOT A ROUTE, AND b121 PAID FOR THAT DISTINCTION.***  The
    # first version took the first non-loopback IPv4 it found.  That was
    # 10.0.0.13 on an Ethernet adapter whose status was Disconnected - the
    # address is still configured on a down interface - so ssh answered 255 and
    # the leg measured nothing.  Require the adapter to be Up AND port 22 to
    # actually accept a connection; an address that fails either is not a route
    # to this machine.
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
                $reach = (Test-NetConnection -ComputerName $c.IPAddress -Port 22 `
                              -WarningAction SilentlyContinue -ErrorAction Stop).TcpTestSucceeded
            } catch { }
        }
        Write-Output ("  candidate {0,-16} adapter={1,-14} port22={2}" -f
                      $c.IPAddress, $(if ($status) { $status } else { '?' }), $reach)
        if ($reach -and -not $lanIp) { $lanIp = $c.IPAddress }
    }
    Write-Output ("  non-loopback address for the REMOTE leg: {0}" -f
                  $(if ($lanIp) { $lanIp } else { '<none>' }))

    # REFUSE THE NULL CASE.  With no reachable routable address there is no
    # remote leg, and leg A alone would show an administrator being ADMITTED
    # with nothing demonstrating that a remote one is refused - a green that
    # means nothing.
    if (-not $lanIp) {
        Write-Output 'verify-sshadmin: no non-loopback IPv4 address on this machine accepts a connection on port 22.'
        Write-Output '  The REMOTE leg cannot be driven, so the gate cannot be measured at all.'
        Write-Output '  This is NOT a product failure - it is a network the test cannot use.'
        exit 2
    }
    Write-Output ''

    Write-Output '=== 3. LEG A - the ADMINISTRATOR over LOOPBACK - MUST BE ADMITTED =='
    Write-Output '  Owner, 5 Sep 2026: "local API and SSH should continue to work".'
    $ra = $null
    try {
        $ra = Invoke-SdAsTestUser -Name $adminAcct -Password $adminPw `
                  -Commands @('WHO') -SshHost 'localhost'
    } catch {
        Write-Output ("verify-sshadmin: could not drive ssh as {0} - {1}" -f $adminAcct, $_.Exception.Message)
        exit 2
    }
    $textA = ($ra.Out | Out-String)
    Write-Output ("  ssh exit {0}, {1} characters of output" -f $ra.ExitCode, $textA.Length)
    Write-Output '  --- the session said: ---'
    Write-Output $textA
    if ($ra.Err -ne '') {
        Write-Output '  --- ssh stderr ---'
        Write-Output $ra.Err
    }
    Write-Output ''

    Write-Output ('=== 3b. LEG B - the SAME ACCOUNT via ' + $lanIp + ' - MUST BE REFUSED ==')
    $rr = $null
    try {
        $rr = Invoke-SdAsTestUser -Name $adminAcct -Password $adminPw `
                  -Commands @('WHO') -SshHost $lanIp
    } catch {
        Write-Output ("verify-sshadmin: could not drive ssh to {0} - {1}" -f $lanIp, $_.Exception.Message)
        exit 2
    }
    $textR = ($rr.Out | Out-String)
    Write-Output ("  ssh exit {0}, {1} characters of output" -f $rr.ExitCode, $textR.Length)
    Write-Output '  --- the session said: ---'
    Write-Output $textR
    if ($rr.Err -ne '') {
        # PRINTED, BECAUSE b121 THREW IT AWAY.  The first version printed leg
        # A's stderr and not this one, so "ssh exit 255" arrived with no reason
        # attached and the cause had to be found afterwards by hand.
        Write-Output '  --- ssh stderr ---'
        Write-Output $rr.Err
    }
    Write-Output ''

    # ***A SESSION THAT NEVER STARTED MUST NOT SCORE, AND ON b121 THIS ONE DID.***
    # verify-sdsysgate.ps1's header says exactly this and it was read the same
    # day.  ssh answered 255 with two characters of output - it never connected
    # - and the two rows below PASSED on that: "the administrator did NOT reach
    # a session" is true of a connection that never happened, and "the two
    # routes were treated DIFFERENTLY" is true when one leg produced nothing.
    # Both were right for the wrong reason.  Only the two anchored on positive
    # evidence - the refusal message and the audit line - failed, which is the
    # whole argument for anchoring on the success wording.
    #
    # SD PRINTS ITS BANNER ON THE REFUSAL PATH TOO - measured on b120, where the
    # refused leg showed the full banner and then 10174 - so the banner is the
    # signal that SD ran at all, and its absence means the leg measured nothing.
    # ***18 Sep 26 - THIS GUARD IS INVERTED, AND THE REASON IS THE WHOLE OF
    # RELEASE_1.1 58.***  The paragraphs above are kept because their argument
    # is still the right one for a refusal that happens INSIDE SD: a connection
    # that never happened looks identical to a session SD turned away, so the
    # banner was the proof that SD had run at all.
    #
    # 58 MOVED THE REFUSAL OUT OF SD.  The administrators group left sshd's
    # AllowGroups, so an administrator is now refused BEFORE AUTHENTICATION -
    # sshd never starts a session, SD never runs, and there is no banner and can
    # never be one.  Requiring the banner here would exit 2 forever on the
    # correct product, which is the "guard nothing can reach" trap.
    #
    # WHAT REPLACES IT, and it is stronger than what it replaces: the CONTROL
    # leg below must show a banner over the SAME route, which is what proves ssh
    # works on this machine; and these legs must show sshd's own refusal.  So a
    # dead ssh server cannot pass - it would take the control down with it.
    $adminBanner = ($textR -match '(?i)SD Core for Windows')
    if ($adminBanner) {
        Write-Output 'verify-sshadmin: the administrator REACHED SD over ssh - the banner is in its output.'
        Write-Output ("  ssh exit {0}.  Under RELEASE_1.1 58 sshd should have refused this before" -f $rr.ExitCode)
        Write-Output '  authentication: the administrators group is not in AllowGroups.  Getting a'
        Write-Output '  session means that entry is back, or the block was never applied - check'
        Write-Output '  gplbld/allow-ssh-groups.ps1 and C:\ProgramData\ssh\sshd_config.'
        Write-Output '  Scored below rather than exited on, because it is a product failure.'
    }

    Write-Output '=== 4. LEG B - the CONTROL, a PROGRAMMER, over the same route ====='
    $rb = $null
    try {
        $rb = Invoke-SdAsTestUser -Name $progAcct -Password $progPw -Commands @('WHO')
    } catch {
        Write-Output ("verify-sshadmin: could not drive ssh as {0} - {1}" -f $progAcct, $_.Exception.Message)
        exit 2
    }
    $textB = ($rb.Out | Out-String)
    Write-Output ("  ssh exit {0}, {1} characters of output" -f $rb.ExitCode, $textB.Length)
    Write-Output '  --- the session said: ---'
    Write-Output $textB
    Write-Output ''

    # ***THE CONTROL IS SCORED FIRST, AND IT GATES EVERYTHING.***  If a
    # non-administrator cannot get in either, ssh is broken on this machine and
    # leg A's refusal says nothing about the gate.
    Write-Output '=== 5. the verdict ================================================'
    $controlRan = ($textB -match '(?i)\b' + [regex]::Escape($progAcct) + '\b')
    Note 'CONTROL: a non-administrator still gets a session' $true $controlRan $true
    if (-not $controlRan) {
        Write-Output 'verify-sshadmin: the CONTROL did not get in, so ssh itself is suspect.'
        Write-Output '  Leg A is NOT scored below - a refusal here would prove nothing about the gate.'
        exit 2
    }

    # ***18 Sep 26 - BOTH ADMINISTRATOR LEGS ARE REFUSALS NOW, AND THE REFUSAL
    # IS THE TRANSPORT'S RATHER THAN SD'S.***  RELEASE_1.1 58.  Leg A was "MUST
    # BE ADMITTED" under the owner's 5 Sep refinement; he withdrew that on
    # 18 Sep - "I don't have any problem with it not being available on the
    # local computer" - so the pair below no longer differs by route.
    #
    # ANCHORED ON POSITIVE EVIDENCE OF THE REFUSAL, not on the absence of a
    # session, which is the rule this file already argues for at length: an ssh
    # that never connected and a session turned away look identical unless
    # something positive distinguishes them.  What is positive now is sshd's own
    # wording on stderr plus a non-zero ssh exit, with the CONTROL's banner
    # standing as proof that the route works at all.
    $localRan  = ($textA -match '(?i)\b' + [regex]::Escape($adminAcct) + '\b')
    $remoteRan = ($textR -match '(?i)\b' + [regex]::Escape($adminAcct) + '\b')

    $localDenied  = (($ra.ExitCode -ne 0) -and ($ra.Err -match '(?i)permission denied|not allowed'))
    $remoteDenied = (($rr.ExitCode -ne 0) -and ($rr.Err -match '(?i)permission denied|not allowed'))

    Note 'LOCAL: sshd refused the administrator before authentication'  $true  $localDenied  $true
    Note 'LOCAL: it reached no session'                                 $false $localRan     $true
    Note 'REMOTE: sshd refused the administrator before authentication' $true  $remoteDenied $true
    Note 'REMOTE: it reached no session'                                $false $remoteRan    $true

    # ***AND SD MUST NOT HAVE BEEN CONSULTED.***  10174 is LOGIN's refusal, and
    # LOGIN runs only after authentication.  Its presence would mean sshd let
    # the account through and SD caught it - the product still refusing, but one
    # layer later than 58 intends, and exactly the regression to notice.
    $peerMsgSeen = (($textA -match '(?i)may not sign in') -or ($textR -match '(?i)may not sign in'))
    Note 'NEITHER leg reached LOGIN (10174 absent)' $false $peerMsgSeen $true
    Note 'NEITHER leg reached SD at all (no banner)' $false `
         (($textA -match '(?i)SD Core for Windows') -or $adminBanner) $true

    # ***THE DISCRIMINATOR IS THE TIER, NOT THE ROUTE.***  The old row here
    # required legs A and B to differ, which 58 makes false by design and which
    # would have failed a correct product.  One route, two tiers: the control got
    # a session over the same transport and the administrator did not.
    Note 'the TIER decided: control in, administrator out' $true ($controlRan -and -not $remoteRan) $true

    Write-Output ''
    Write-Output '=== 6. the audit trail, after - THE DECISIVE READING =============='
    $after = [IO.File]::ReadAllText($audit)
    $tail  = $after.Substring([Math]::Min($before.Length, $after.Length))
    Write-Output ("  audit grew by {0} bytes" -f ($after.Length - $before.Length))
    Write-Output '  --- what LOGIN wrote ---'
    foreach ($l in ($tail -split "`r?`n")) {
        if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
    }

    # Written on the refusal path and nowhere else.  LOGIN sets audit.reason =
    # 'administrator on a remote session with no interactive desktop' and
    # terminate.connection writes "LOGIN REFUSED account=... reason=...".
    #
    # ***18 Sep 26 - AND IT MUST NOT BE THERE ANY MORE.***  RELEASE_1.1 58.
    # LOGIN runs only after authentication, and sshd now refuses an
    # administrator before that - so neither the refusal line nor an admission
    # line can exist for this account.  Their PRESENCE is the regression: it
    # would mean sshd admitted the account and SD caught it one layer later.
    $auditSaysRefused = ($tail -match '(?i)LOGIN REFUSED' -and
                         $tail -match '(?i)remote session with no interactive desktop')
    Note 'the audit has NO LOGIN refusal for it (sshd refused first)' $false $auditSaysRefused $true

    $auditSaysAdmitted = ($tail -match ('(?i)LOGIN account=' + [regex]::Escape($adminAcct)))
    Note 'the audit has NO admission for the administrator'           $false $auditSaysAdmitted $true

    # ***THE CONTROL IS WHAT MUST BE IN THE TRAIL NOW, AND IT IS WHAT KEEPS THE
    # TWO ROWS ABOVE HONEST.***  They are absences, and an absence also holds
    # when the audit file is not being written at all - a broken path, a
    # permission change, LOGIN never running for anybody.  The control DID
    # authenticate, so its line must be present: that proves the trail is live
    # and the absences above mean what they say.
    $auditSaysControl = ($tail -match ('(?i)LOGIN account=' + [regex]::Escape($progAcct)))
    Note 'the audit records the CONTROL admission (so the trail is live)' $true $auditSaysControl $true

    # A trail that did not move at all means nothing reached LOGIN - which is
    # not the gate working, it is the measurement failing.
    Note 'the audit trail actually moved' $true (($after.Length - $before.Length) -gt 0) $true

} finally {
    Write-Output ''
    Write-Output '=== cleanup ======================================================='
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
            Write-Output ('  *** verify-sshadmin: ACCOUNT STILL EXISTS: ' + $acct)
            Write-Output  '  *** Remove it by hand.  In an ELEVATED PowerShell:'
            Write-Output ('  ***   Remove-LocalUser -Name ' + $acct)
            Write-Output  '  *** If it was the administrator one, check it is out of Administrators too.'
        }
    }
}

Write-Output ''
Write-Output ("verify-sshadmin: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
