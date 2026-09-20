# sdsys-seat.ps1 - run sd.exe AS THE OS SDSYS ACCOUNT, inside its own live console
# session, and hand the output back.  Dot-sourced; it defines functions and runs
# nothing.  RELEASE_1.1 76.
#
# WHY THIS EXISTS.  RELEASE_1.1 64 made the Windows SDSYS account the only SD
# administrator, and SD reaches SDSYS only from a process that IS that OS account
# with a token that is BOTH elevated AND interactive (kernel.c:299).  "LOGTO SDSYS"
# and "sd -ASDSYS" from any other account are refused (10002).  So a verifier that
# needs SDSYS cannot send a prefix - it has to run sd.exe as SDSYS.
#
# THE SEAT, MEASURED (probe-sdsysseat.ps1, owner's run 19 Sep 2026 23:33): a
# scheduled task registered for the account with LogonType Interactive and
# RunLevel Highest runs INSIDE that account's already-signed-in session - even a
# DISCONNECTED one - with a High-integrity token, Administrators enabled and
# S-1-5-4 present.  SD then answers WHO with "<n> SDSYS".  Routes that mint a
# session instead (Start-Process -Credential: filtered; a plain scheduled task:
# batch, no S-1-5-4; the linked token: refused 1346) are not seats.  No password
# is involved at all, which is why nothing here can leak one.
#
# WHAT IT NEEDS.  (1) The CALLER elevated - registering a task for another
# account needs it, so this belongs to the elevated tier only.  (2) SDSYS SIGNED
# IN and left signed in (the owner's ruling, 19 Sep 2026): sign in once per boot
# using the login name SDSYS, then switch back.  ***A task registered for an
# account with no session does not fail - it never runs***, so both are checked
# before anything is registered and refused out loud.
#
# ***IT REFUSES A SEAT THAT IS NOT ONE.***  The task script reports the identity
# and the two token facts it actually ran with, in a header, and this validates
# them: the identity must be the account asked for, the token must be elevated,
# and it must be interactive.  A run that produced output as the WRONG account,
# or as SDSYS without the seat, would otherwise look like SD refusing the
# command - which is the failure the instrument rules exist to stop.  The end
# marker is required for the same reason: a report cut off mid-write is not a
# report.
#
# A FUNCTION THAT RETURNS A VALUE PRINTS NOTHING (probe-sdsysseat.ps1's rule,
# paid for on 19 Sep 2026): every function here returns its value and the CALLER
# prints.  Write-Output inside one would fold its lines into the return value.
#
# NO Set-StrictMode AT FILE SCOPE.  A dot-sourced file's strict mode binds the
# CALLER (the suite-only.ps1 trap).
#
# TEST SEAM.  $script:SeatTestHooks, when a caller sets it, replaces the four
# things that need a real machine: Elevated, Qwinsta, SdExe and Runner.
# test-sdsysseat-units.ps1 drives every decision through it.  Production callers
# never set it.  The lines tagged "MUT-" are the checks the unit test mutates to
# prove its own fixtures can tell a broken helper from a good one.

function Get-SeatHook([string]$Name) {
    $h = Get-Variable -Name SeatTestHooks -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $h -and $null -ne $h.Value -and $h.Value.ContainsKey($Name)) {
        return @{ Has = $true; Value = $h.Value[$Name] }
    }
    return @{ Has = $false; Value = $null }
}

function New-SeatResult([bool]$Ok, [string]$Text, [string]$Why, [string]$Detail, $Session) {
    return [pscustomobject]@{ Ok = $Ok; Text = $Text; Why = $Why; Detail = $Detail; Session = $Session }
}

function Test-SeatCallerElevated {
    $hk = Get-SeatHook 'Elevated'
    if ($hk.Has) { return [bool]$hk.Value }
    $pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Finds the account's session in qwinsta's table.  Active and Disc both count: a
# disconnected session is a seat (measured).  The name must stand alone - SDSYS2
# and xSDSYS are other accounts.  Lines can be injected for the unit test.
function Get-SeatSession {
    param([string]$Account = 'SDSYS', [string[]]$Lines = $null)
    if ($null -eq $Lines) {
        $hk = Get-SeatHook 'Qwinsta'
        if ($hk.Has) {
            $Lines = @($hk.Value)
        } else {
            $Lines = @(& (Join-Path $env:SystemRoot 'System32\qwinsta.exe') 2>&1 | ForEach-Object { [string]$_ })
        }
    }
    $clean = @($Lines | Where-Object { $_ -match '\S' })
    if ($clean.Count -eq 0) {
        return @{ Ok = $false; Id = -1; State = ''; Line = ''
                  Why = 'qwinsta produced nothing - the session list could not be read' }
    }
    $rx = '(?i)(^|\s)' + [regex]::Escape($Account) + '\s+(\d+)\s+(Active|Disc)\b'
    foreach ($l in $clean) {
        if ($l -match $rx) {
            return @{ Ok = $true; Id = [int]$Matches[2]; State = $Matches[3]; Line = $l.Trim(); Why = '' }
        }
    }
    return @{ Ok = $false; Id = -1; State = ''; Line = ''
              Why = ("no live session for {0} in qwinsta.  Sign in as {0} once - at the switch-user screen pick " +
                     "the login name {0}, NOT your own account's tile - then switch back; the session stays alive " +
                     "behind yours.  A task registered without one does not fail, it never runs.") -f $Account }
}

# The whole check on what the seat wrote.  Value in, value out.
function ConvertFrom-SeatReport {
    param([string]$Raw, [string]$Account = 'SDSYS', [int]$MaxBytes = 4194304)
    $bad = { param($why) return @{ Ok = $false; Text = ''; Why = $why; Identity = ''; Admin = $false; Interactive = $false } }

    if ([string]::IsNullOrEmpty($Raw)) { return (& $bad 'the seat wrote an empty report') }
    if ([Text.Encoding]::UTF8.GetByteCount($Raw) -gt $MaxBytes) {
        return (& $bad ("the seat's report is larger than {0} bytes - a runaway loop, not an answer" -f $MaxBytes))
    }
    $lines = @($Raw -split "`r?`n")
    if (-not ($lines[0] -match '^SEAT identity=(\S+) admin=(True|False) interactive=(True|False)\s*$')) {
        return (& $bad 'the seat report has no SEAT header - it did not come from the task script')
    }
    $id    = $Matches[1]
    $admin = ($Matches[2] -eq 'True')
    $inter = ($Matches[3] -eq 'True')

    $idRx = '(?i)\\' + [regex]::Escape($Account) + '$'
    if (-not ($id -match $idRx)) { return (& $bad ("the seat ran as '{0}', not {1}: the output is not {1}'s, and LOGTO cannot reach it from another account" -f $id, $Account)) } #MUT-ID
    if (-not $admin) { return (& $bad ("the seat's token is not elevated (Administrators is not enabled) - SD will refuse it with 10002")) } #MUT-ADMIN
    if (-not $inter) { return (& $bad ("the seat's token is not interactive (no S-1-5-4) - a batch logon is elevated and still refused with 10002")) } #MUT-INTERACTIVE
    if ($Raw -notmatch 'ENDOFSEAT\s*$') { return (& $bad 'the seat report has no end marker - it was cut off or is still being written') } #MUT-MARKER

    $body = @()
    if ($lines.Count -gt 1) { $body = @($lines[1..($lines.Count - 1)] | Where-Object { $_ -ne 'ENDOFSEAT' }) }
    $text = ($body -join "`n") -replace ([string][char]27 + '\[[0-9;?]*[A-Za-z]'), ''
    return @{ Ok = $true; Text = $text; Why = ''; Identity = $id; Admin = $admin; Interactive = $inter }
}

# Builds the script the task runs.  .Replace() rather than -replace: the
# replacements are PATHS and a regex replacement string is not a literal one
# (CLAUDE.md's backslash rule, met by building the text rather than escaping).
#
# ORDER MATTERS AND THE UNIT TEST PINS IT: the input file - which can hold a
# test account's password - is read and DELETED before sd.exe starts, so it
# does not sit on disk for the length of the run.  The report is written to a
# .tmp and RENAMED, so the caller can never see half of it.
function New-SeatScript {
    # -Internal runs "sd.exe -internal" instead of "sd.exe".  ONLY THAT ONE FLAG IS
    # OFFERED, AS A SWITCH AND NOT A FREE-TEXT ARGUMENT LIST: the script text is
    # built by string replacement, and an arbitrary argument string would be an
    # injection point into a script that runs elevated as SDSYS.  See
    # Invoke-SdViaSeat for why a verifier needs it.
    param([string]$SdExe, [string]$InFile, [string]$OutFile, [bool]$Internal = $false)
    $t = @'
$sd   = '@@SD@@'
$inF  = '@@IN@@'
$outF = '@@OUT@@'
$id   = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr   = New-Object Security.Principal.WindowsPrincipal($id)
$hdr  = 'SEAT identity=' + $id.Name +
        ' admin=' + $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) +
        ' interactive=' + $pr.IsInRole((New-Object Security.Principal.SecurityIdentifier('S-1-5-4')))
$in   = [IO.File]::ReadAllText($inF)
Remove-Item -LiteralPath $inF -Force
$u8   = New-Object Text.UTF8Encoding($false)
$part = $outF + '.part'
[IO.File]::WriteAllText($part, ($hdr + "`n"), $u8)
$all  = New-Object System.Collections.ArrayList
$in | & $sd @@ARGS@@2>&1 | ForEach-Object { $l = [string]$_; $null = $all.Add($l); [IO.File]::AppendAllText($part, ($l + "`n"), $u8) }
$body = $hdr + "`n" + ($all -join "`n") + "`nENDOFSEAT"
[IO.File]::WriteAllText($outF + '.tmp', $body, $u8)
Move-Item -LiteralPath ($outF + '.tmp') -Destination $outF -Force
Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
'@
    $sdArgs = $(if ($Internal) { "'-internal' " } else { '' })
    return $t.Replace('@@SD@@', $SdExe).Replace('@@IN@@', $InFile).Replace('@@OUT@@', $OutFile).Replace('@@ARGS@@', $sdArgs)
}

# The real runner: a task in the account's own live session.  Never called by
# the unit test (it needs elevation and a session); test-sdsysseat-units.ps1
# checks its shape from the AST instead.
#
# AllowStartIfOnBatteries / DontStopIfGoingOnBatteries: a task's default is to
# NOT start on battery, and it fails as a silent "never ran".  This tree is
# moving to a laptop (owner, 28 Aug 2026), so that default would surface as a
# verifier that hangs until its timeout for no visible reason.
function Invoke-SeatTask {
    param([string]$Ps1, [string]$OutFile, [int]$Seconds, [string]$Account)
    $name = 'SDVerifySdsysSeatRun_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $made = $false
    try {
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
                         -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $Ps1)
        $principal = New-ScheduledTaskPrincipal -UserId ($env:COMPUTERNAME + '\' + $Account) `
                         -LogonType Interactive -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                         -ExecutionTimeLimit (New-TimeSpan -Seconds ($Seconds + 30))
        Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        $made = $true
        Start-ScheduledTask -TaskName $name
        $deadline = (Get-Date).AddSeconds($Seconds)
        while (-not (Test-Path -LiteralPath $OutFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
        $got  = Test-Path -LiteralPath $OutFile
        $last = '<not read>'
        try { $last = (Get-ScheduledTaskInfo -TaskName $name).LastTaskResult } catch { }
        if (-not $got) { try { Stop-ScheduledTask -TaskName $name -ErrorAction Stop } catch { } }
        return @{ Ok = $got; Detail = ('task {0}, LastTaskResult {1}' -f $name, $last)
                  Why = $(if ($got) { '' } else {
                      ('the task wrote no report within {0}s (LastTaskResult {1}; 267011 means it never ran, 267009 that it was still running)' -f $Seconds, $last) }) }
    } catch {
        return @{ Ok = $false; Detail = $name; Why = ('the scheduled task could not be run: ' + $_.Exception.Message) }
    } finally {
        if ($made) { try { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop } catch { } }
    }
}

# Creates the work directory if needed and lets the account write into it - the
# task, running as SDSYS, has to be able to write its report there.
function Initialize-SeatWorkDir {
    param([string]$Dir, [string]$Account)
    if (-not (Test-Path -LiteralPath $Dir)) { $null = New-Item -ItemType Directory -Path $Dir -Force }
    $acl  = Get-Acl -LiteralPath $Dir
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $Account, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Dir -AclObject $acl
}

# THE ENTRY POINT.  Runs the commands in sd.exe as the account and returns
# @{ Ok; Text; Why; Detail; Session }.  Ok is false - with Why saying which
# precondition or which validation failed - and Text empty in every refusal, so
# a caller cannot mistake "the seat did not run" for "SD printed nothing".
# "OFF" is appended, and a leading newline is the BOM sink Invoke-SD always had.
function Invoke-SdViaSeat {
    param(
        # AllowEmptyCollection / AllowNull: without them PowerShell's own binder
        # answers an empty list with a TERMINATING error before the refusal below
        # can run, and the helper's promise - a result object with a Why on EVERY
        # refusal - would not hold for the caller most likely to hit it, one that
        # builds its command list conditionally.  Found by the unit test.
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [AllowNull()] [AllowEmptyString()] [string[]] $Commands,
        [string] $Account    = 'SDSYS',
        [int]    $TimeoutSec = 90,
        [string] $WorkDir    = '',
        [int]    $MaxBytes   = 4194304,
        # ***WHY A VERIFIER WOULD ASK FOR THIS: LOGTO TO A PERSONAL ACCOUNT.***  Found
        # 20 Sep 2026 by the owner's run of verify-apiwire, and the comment that stood in
        # apiwire and vocwrite ("SDSYS -> a personal account is allowed") was WRONG.
        # cproc's logto.authorised admits a LOGTO in exactly two cases: the session is
        # K$INTERNAL and K$ADMINISTRATOR, or the account is not suspended and the OS
        # user (@logname) is a member of the target account's group.  The seat's
        # @logname is SDSYS, which is in NO personal account's group, so "LOGTO
        # SDWIRE199" is REFUSED (10003) and the commands after it run in SDSYS's OWN
        # account - CREATE.FILE printed its success line there and left zzwire in
        # C:\ProgramData\SD\sdsys.  The pre-64 flow got through on elev.obtained, which
        # 64 made dead code.  -Internal runs "sd.exe -internal": forced to SDSYS, and it
        # is K$INTERNAL, which is the first admission case.  ***THIS IS THE DEVELOPMENT
        # DOOR - RELEASE_1.1 82 RULES IT DEVELOPMENT-ONLY - AND ONLY A DEVELOPMENT TOOL
        # SHOULD ASK FOR IT.***  Off by default: nothing that ran without it changes.
        [switch] $Internal
    )
    $cmds = @($Commands | Where-Object { $_ -ne $null })
    if ($cmds.Count -eq 0 -or -not (@($cmds | Where-Object { $_ -match '\S' }).Count)) {
        return (New-SeatResult $false '' 'no commands were given - there is nothing to run' '' $null)
    }
    if (-not (Test-SeatCallerElevated)) {
        return (New-SeatResult $false '' 'the caller is not elevated - registering a task for another account needs an elevated PowerShell' '' $null)
    }
    $sess = Get-SeatSession -Account $Account
    if (-not $sess.Ok) { return (New-SeatResult $false '' $sess.Why '' $sess) }

    $hkSd = Get-SeatHook 'SdExe'
    $sdExe = if ($hkSd.Has) { [string]$hkSd.Value } else { Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe' }
    if (-not $hkSd.Has -and -not (Test-Path -LiteralPath $sdExe)) {
        return (New-SeatResult $false '' ("there is no {0} - SD is not installed" -f $sdExe) '' $sess)
    }

    $hkRun = Get-SeatHook 'Runner'
    if ($WorkDir -eq '') { $WorkDir = Join-Path $env:ProgramData 'SD-verify\sdsysseat' }
    try {
        if (-not $hkRun.Has) { Initialize-SeatWorkDir -Dir $WorkDir -Account $Account }
        elseif (-not (Test-Path -LiteralPath $WorkDir)) { $null = New-Item -ItemType Directory -Path $WorkDir -Force }
    } catch {
        return (New-SeatResult $false '' ('the work directory {0} could not be prepared: {1}' -f $WorkDir, $_.Exception.Message) '' $sess)
    }

    $tag  = [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $inF  = Join-Path $WorkDir ('seat-' + $tag + '.in')
    $ps1  = Join-Path $WorkDir ('seat-' + $tag + '.ps1')
    $outF = Join-Path $WorkDir ('seat-' + $tag + '.out')
    try {
        $body = "`n" + ((@($cmds) + @('OFF')) -join "`n") + "`n"
        [IO.File]::WriteAllText($inF, $body, (New-Object Text.UTF8Encoding($false)))
        Set-Content -LiteralPath $ps1 -Value (New-SeatScript -SdExe $sdExe -InFile $inF -OutFile $outF -Internal ([bool]$Internal)) -Encoding UTF8

        $run = if ($hkRun.Has) { & $hkRun.Value $ps1 $outF $TimeoutSec $Account }
               else { Invoke-SeatTask -Ps1 $ps1 -OutFile $outF -Seconds $TimeoutSec -Account $Account }
        if (-not $run.Ok) {
            # ***WHAT SD HAD PRINTED WHEN IT WAS STOPPED.***  The task appends every line to
            # <report>.part as sd.exe prints it, so a call that hit its timeout still says
            # where it stopped.  Before this, a hang returned no text at all and the prompt
            # that caused it had to be found by reading the product's source - which is
            # exactly what verify-accountrules cost on 20 Sep 2026 (CREATE.ACCOUNT with no
            # keyword had stopped being refused, and sat at "Password:" for 180 s).
            $why = $run.Why
            $partF = $outF + '.part'
            try {
                if (Test-Path -LiteralPath $partF) {
                    $tail = @(Get-Content -LiteralPath $partF -Tail 25 -Encoding UTF8 | Where-Object { $_ -match '\S' })
                    if ($tail.Count) { $why += '  WHAT SD HAD PRINTED WHEN IT WAS STOPPED (last lines): ' + (($tail | ForEach-Object { $_.Trim() }) -join ' | ') }
                }
            } catch { }
            return (New-SeatResult $false '' $why $run.Detail $sess)
        }

        $raw = ''
        if (Test-Path -LiteralPath $outF) {
            if ((Get-Item -LiteralPath $outF).Length -gt ($MaxBytes * 3)) { $raw = 'x' * ($MaxBytes + 1) }
            else { $raw = [IO.File]::ReadAllText($outF, [Text.Encoding]::UTF8) }
        }
        $rep = ConvertFrom-SeatReport -Raw $raw -Account $Account -MaxBytes $MaxBytes
        if (-not $rep.Ok) { return (New-SeatResult $false '' $rep.Why $run.Detail $sess) }
        return (New-SeatResult $true $rep.Text '' $run.Detail $sess)
    } finally {
        foreach ($f in @($inF, $ps1, $outF, ($outF + '.tmp'), ($outF + '.part'))) {
            try { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction Stop } } catch { }
        }
    }
}

# ---------------------------------------------------------------------------
# THE SHARED "TERM" HANDLING, ONCE.  RELEASE_1.1 76, the mechanical group.
#
# Eight verifiers each carried their own copy of this.  A pipe cannot answer
# "Press RETURN to continue", so a long LIST or CT paginates and blocks for ever;
# TERM 200,9999 stops it.  And LOGIN re-initialises the terminal geometry on
# EVERY account switch (LOGIN:201-209), so a TERM sent before a LOGTO is wiped
# by it and has to be sent again after each one.  The pilot needs none of this -
# it uses NO.PAGE and sends no LOGTO - so it does not call these.
#
# The result is an array: CALLERS WRAP IT IN @() because PowerShell unrolls a
# one-element array on return, and Invoke-SdViaSeat's -Commands is a string[].
function Expand-SeatCommands([string[]]$Commands) {
    $out = New-Object System.Collections.ArrayList
    $null = $out.Add('TERM 200,9999')
    foreach ($c in @($Commands)) {
        $null = $out.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $out.Add('TERM 200,9999') } #MUT-TERMAFTER
    }
    return $out.ToArray()
}

# THE PRECHECK, ONCE.  verify-createaccount.ps1 (the pilot) carried this inline; a
# verifier calls it BEFORE it creates anything.  CREATE.ACCOUNT makes a real
# Windows account, so a run that only finds out at its first SD call that SDSYS has
# no live session would fail with a thrown error - exit 1, a stack trace, and every
# appearance of a product defect - when it is the precondition, which is exit 2
# ("could not be run").  WHO is the cheapest command that says who SD thinks it is.
# ANCHORED ON THE SUCCESS WORDING ("<n> SDSYS") with the refusal wording as a
# disqualifier, because SDSYS appears in the refusal too; and SD's raw answer is
# printed either way.
#
# THIS ONE PRINTS AND EXITS, AND SAYS SO IN ITS NAME: it is an Assert, it returns
# nothing, and a caller must not capture it.  It ends the calling SCRIPT with exit 2.
function Assert-SdSeat {
    param([Parameter(Mandatory = $true)] [string] $Label, [int] $TimeoutSec = 90, [string] $WorkDir = '', [switch] $Internal)
    # -Internal proves the seat can reach "sd.exe -internal", the door a verifier that
    # LOGTOs into a personal account depends on - so a run that cannot use it stops
    # HERE, exit 2, and not at the first LOGTO with the commands silently landing in
    # SDSYS's own account.
    Write-Output ("  proving the SDSYS seat (a task inside SDSYS's own live session)" + $(if ($Internal) { ', through sd -internal' } else { '' }) + ' ...')
    $seat = Invoke-SdViaSeat -Commands @('WHO') -TimeoutSec $TimeoutSec -WorkDir $WorkDir -Internal:$Internal
    Write-Output ("  seat: Ok={0}  {1}" -f $seat.Ok, $seat.Detail)
    # Stop-Transcript BEFORE exit 2, as the verifiers' own Refuse() does: a
    # transcript left running can swallow the NEXT verifier's output into this
    # one's file when they share a process.  Harmless when none is running.
    if (-not $seat.Ok) {
        Write-Output ($Label + ': the SDSYS seat did not run - ' + $seat.Why)
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }
    Write-Output '  --- what SD said to WHO ---'
    foreach ($l in @($seat.Text -split "`n")) { if ($l -match '\S') { Write-Output ('    ' + $l.Trim()) } }
    if ($seat.Text -match 'restricted to privileged users' -or $seat.Text -notmatch '(?m)^\s*\d+\s+SDSYS\b') {
        Write-Output ($Label + ': SD did not answer WHO as SDSYS, so nothing below would measure what it claims to.')
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }
}

# What each converted verifier's Invoke-SD calls: the commands (with the TERM
# handling) go to the seat and the output TEXT comes back.
#
# ***IT THROWS WHEN THE SEAT DID NOT RUN, RATHER THAN RETURNING ''.***  An empty
# string would read as "SD printed nothing" and every check below the call would
# then fail for a reason invisible in its own output - the null case the
# instrument rules exist to stop.  The message carries the seat's Why and its
# Detail (task id, LastTaskResult).
function Invoke-SdSeatText {
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [AllowNull()] [AllowEmptyString()] [string[]] $Commands,
        [int]    $TimeoutSec = 90,
        [string] $WorkDir    = '',
        [switch] $Internal
    )
    if (@($Commands | Where-Object { $_ -match '\S' }).Count -eq 0) {
        throw 'the SDSYS seat was given no commands - there is nothing to run'
    }
    $r = Invoke-SdViaSeat -Commands @(Expand-SeatCommands $Commands) -TimeoutSec $TimeoutSec -WorkDir $WorkDir -Internal:$Internal
    if (-not $r.Ok) { throw ('the SDSYS seat did not run: ' + $r.Why + '  [' + $r.Detail + ']') }
    return $r.Text
}
