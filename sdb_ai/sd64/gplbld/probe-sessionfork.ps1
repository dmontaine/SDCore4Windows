<#
.SYNOPSIS
    Step 14 (a2) - does the API SESSION process fork between login and the write?

.DESCRIPTION
    PROJECT_STATUS.md section 7 step 14 is stuck on one tension.  probe-impfork
    measured that fork() is the ONLY thing that drops a thread's impersonation
    - thirteen other operations a session performs do not, including chdir, the
    socket request loop, select, signal delivery and LsaDeregisterLogonProcess.
    But nothing on the API login-to-write path appears to fork: the server's
    only fork() sites are op_kernel.c:735 (PHANTOM), op_sh.c:379 (SH),
    sdwind.c:491 (the spawn itself, which is BEFORE the hook) and
    sysseg.c:643/:745 (SD start-up), and b28's flow takes none of them.

    So either the session forks somewhere not yet found, or something outside
    those fourteen steps drops it.  THIS SCRIPT ANSWERS WHICH, by watching for
    real process creations while a live API session logs in and writes.

    A Cygwin fork() is a real Win32 process creation, so it is visible to
    Win32_ProcessStartTrace.

    WHY AN EVENT TRACE AND NOT POLLING.  A forked child that exits quickly can
    live for a few milliseconds.  Polling Win32_Process would miss it and the
    miss would look exactly like "the session did not fork" - a false negative
    reported as a finding.  Win32_ProcessStartTrace fires on every creation.

    WHY IT FILTERS ON ParentProcessID AND NEVER ON CommandLine.  HISTORY.md
    records a trap: a "Get-CimInstance Win32_Process | Where CommandLine -like"
    search matches the searching shell, because the search text is in that
    shell's own command line.  It produced a false failure and a Stop-Process
    aimed at the measuring shell.  Filtering on pid parentage cannot do that.

    WHAT IT REFUSES.  Per CLAUDE.md's instrument rule, a run that measured
    nothing must FAIL rather than report "no forks":
      * it self-tests the trace by deliberately starting a process and
        requiring the trace to catch it, before any measurement;
      * it requires that the API session process was actually identified;
      * "no forks by the session" is only reported when both of those held.

    THERE IS DELIBERATELY NO SWITCH TO SKIP assert-current.  A result taken
    from a tree that does not match source describes a system that no longer
    exists, and a flag to bypass that is the kind of shortcut CLAUDE.md's
    "standing procedures" rule exists to stop.

.PARAMETER Prefix
    Account/user prefix handed to verify-apiidentity.ps1.  Prefixes sdapiidb18
    to sdapiidb28 are spent - use b29 or later.

.PARAMETER SelfTestOnly
    Run the elevation check and the trace self-test, then stop WITHOUT touching
    SD or the install.  This exists so the instrument can be proven to fire on
    a stale tree, before a cycle is spent.  It measures nothing about SD and
    says so.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\probe-sessionfork.ps1 -SelfTestOnly

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\probe-sessionfork.ps1 -Prefix sdapiidb29

.NOTES
    NOT SHIPPED - it must be on assert-current.ps1's $neverShipped list.
    Needs elevation: Win32_ProcessStartTrace is admin-only.
#>

[CmdletBinding()]
param(
    [string] $Prefix,
    [switch] $SelfTestOnly
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say([string]$m) { Write-Host $m }
function Fail([string]$m) {
    Write-Host ''
    Write-Host "REFUSING: $m"
    exit 1
}

Say '============================================================'
Say ' step 14 (a2) - does the API session process fork?'
Say '============================================================'

# ---------------------------------------------------------------------------
# Rule 1 of the instrument section: print the REAL inputs, not the intended
# ones.  Everything below is echoed as resolved, not as written.
# ---------------------------------------------------------------------------
$mypid = $PID
Say ''
Say 'INPUTS AS RESOLVED'
Say "  this script          : $($MyInvocation.MyCommand.Path)"
Say "  gplbld               : $Gplbld"
Say "  measuring shell pid  : $mypid   <- excluded from every parentage test"
Say "  prefix               : $(if ($Prefix) { $Prefix } else { '(none - self-test only)' })"
Say "  mode                 : $(if ($SelfTestOnly) { 'SELF-TEST ONLY, nothing about SD is measured' } else { 'full measurement' })"

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say "  running as           : $($id.Name)"
Say "  elevated             : $elevated"
if (-not $elevated) {
    Fail 'Win32_ProcessStartTrace is admin-only. Run this from an elevated PowerShell.'
}

if (-not $SelfTestOnly -and [string]::IsNullOrWhiteSpace($Prefix)) {
    Fail 'a full measurement needs -Prefix (b29 or later; b18-b28 are spent).'
}

# ---------------------------------------------------------------------------
# The trace.  Registered before anything else happens so nothing is missed.
# ---------------------------------------------------------------------------
$srcId = "sessionfork_$mypid"
Say ''
Say 'STARTING THE TRACE'
Say "  query      : SELECT * FROM Win32_ProcessStartTrace"
Say "  source id  : $srcId"

try {
    Register-CimIndicationEvent -Query 'SELECT * FROM Win32_ProcessStartTrace' `
                                -SourceIdentifier $srcId | Out-Null
} catch {
    Fail "could not register the process-start trace: $($_.Exception.Message)"
}

function Get-Starts {
    # Returns every process-start seen so far as plain objects.  Get-Event does
    # not remove them, so this can be called repeatedly.
    Get-Event -SourceIdentifier $srcId -ErrorAction SilentlyContinue | ForEach-Object {
        $e = $_.SourceEventArgs.NewEvent
        [pscustomobject]@{
            Time     = $_.TimeGenerated
            Name     = [string]$e.ProcessName
            Pid      = [int]$e.ProcessID
            ParentPid= [int]$e.ParentProcessID
        }
    }
}

try {
    # -----------------------------------------------------------------------
    # SELF-TEST.  CLAUDE.md: a test that passes because it did nothing must
    # FAIL, not pass.  So before measuring anything, cause a process start on
    # purpose and require the trace to see it.  If this does not fire, every
    # "no fork" that followed would be meaningless.
    # -----------------------------------------------------------------------
    Say ''
    Say 'SELF-TEST OF THE TRACE - a known process start must be caught'
    $canary = Start-Process -FilePath $env:ComSpec -ArgumentList '/c','exit','0' `
                            -PassThru -WindowStyle Hidden
    $canaryPid = $canary.Id
    Say "  started $env:ComSpec (pid $canaryPid), parent is this shell ($mypid)"
    $canary.WaitForExit()

    $deadline = (Get-Date).AddSeconds(15)
    $seen = $null
    while ((Get-Date) -lt $deadline) {
        $seen = Get-Starts | Where-Object { $_.Pid -eq $canaryPid }
        if ($seen) { break }
        Start-Sleep -Milliseconds 200
    }

    if (-not $seen) {
        Fail @'
the trace did not catch a process start that definitely happened.
Nothing measured after this could be trusted, so the run stops here rather
than reporting "no forks". Check that the WMI service is running.
'@
    }
    Say "  CAUGHT: $($seen.Name) pid $($seen.Pid), parent $($seen.ParentPid) at $($seen.Time)"
    Say '  the trace fires. Measurements below are meaningful.'

    if ($SelfTestOnly) {
        Say ''
        Say '============================================================'
        Say ' SELF-TEST ONLY - NOTHING ABOUT SD WAS MEASURED'
        Say '============================================================'
        Say ' The instrument works. It has NOT been pointed at SD, and this'
        Say ' run says nothing whatever about whether the session forks.'
        Say ' Run a cycle, then re-run with -Prefix sdapiidb29.'
        exit 0
    }

    # -----------------------------------------------------------------------
    # The gate.  A measurement from a tree that does not match source is void.
    # -----------------------------------------------------------------------
    Say ''
    Say 'ASSERT-CURRENT'
    & (Join-Path $Gplbld 'assert-current.ps1')
    if ($LASTEXITCODE -ne 0) {
        Fail 'assert-current refuses - the install does not match source. Run cycle.ps1 first.'
    }

    # -----------------------------------------------------------------------
    # BEFORE state.
    # -----------------------------------------------------------------------
    Say ''
    Say 'BEFORE - the process picture the measurement starts from'
    $sdwind = @(Get-CimInstance Win32_Process -Filter "Name='sdwind.exe'" -ErrorAction SilentlyContinue)
    if ($sdwind.Count -eq 0) {
        Fail 'no sdwind.exe is running, so there is no daemon to fork a session. Is the SD service started?'
    }
    $sdwindPids = @($sdwind | ForEach-Object { [int]$_.ProcessId })
    foreach ($p in $sdwind) { Say "  sdwind.exe pid $($p.ProcessId), started $($p.CreationDate)" }
    $sdBefore = @(Get-CimInstance Win32_Process -Filter "Name='sd.exe'" -ErrorAction SilentlyContinue)
    Say "  sd.exe processes before: $($sdBefore.Count)"
    foreach ($p in $sdBefore) { Say "     pid $($p.ProcessId), parent $($p.ParentProcessId)" }

    # -----------------------------------------------------------------------
    # The live run.  verify-apiidentity does the SCRAM login, the account
    # switch, the open and the write - the exact flow b28 measured.  Reusing it
    # rather than re-implementing SCRAM keeps this measuring the same thing.
    # -----------------------------------------------------------------------
    $verifier = Join-Path $Gplbld 'verify-apiidentity.ps1'
    if (-not (Test-Path $verifier)) { Fail "verify-apiidentity.ps1 not found at $verifier" }

    Say ''
    Say 'RUNNING THE LIVE API SESSION'
    Say "  $verifier -Prefix $Prefix"
    Say '  ---------------- verifier output begins ----------------'
    $tStart = Get-Date
    & $verifier -Prefix $Prefix
    $verifierExit = $LASTEXITCODE
    $tEnd = Get-Date
    Say '  ---------------- verifier output ends ------------------'
    Say "  verifier exit code: $verifierExit"
    Say "  window: $($tStart.ToString('HH:mm:ss.fff')) to $($tEnd.ToString('HH:mm:ss.fff'))"

    # Let any trailing indications arrive before reading.
    Start-Sleep -Milliseconds 750

    # -----------------------------------------------------------------------
    # AFTER - and the analysis.
    # -----------------------------------------------------------------------
    $all = @(Get-Starts | Where-Object { $_.Time -ge $tStart -and $_.Pid -ne $canaryPid })
    Say ''
    Say "ALL PROCESS STARTS DURING THE RUN: $($all.Count)"
    foreach ($e in ($all | Sort-Object Time)) {
        Say ("  {0}  {1,-22} pid {2,-7} parent {3}" -f $e.Time.ToString('HH:mm:ss.fff'), $e.Name, $e.Pid, $e.ParentPid)
    }

    if ($all.Count -eq 0) {
        Fail @'
not one process start was recorded during the whole run, yet the verifier ran.
That contradicts the self-test and means the trace stopped listening. This is
an instrument failure, NOT a finding of "no forks".
'@
    }

    # -----------------------------------------------------------------------
    # A CYGWIN fork()+exec() IS **TWO** WINDOWS PROCESS CREATIONS, AND READING
    # IT AS ONE IS HOW THE FIRST VERSION OF THIS SCRIPT GOT THE RIGHT ANSWER
    # FOR THE WRONG REASON ON b29.  fork() clones the image, so the child is
    # briefly named after the PARENT's exe; exec() then starts a NEW Windows
    # process for the target and the clone exits.  So sdwind spawning a session
    # appears as:
    #
    #     sdwind.exe pid A   parent <daemon>     <- the fork clone
    #     sd.exe     pid B   parent A            <- the exec target = THE SESSION
    #
    # The first version called A the session and B "a fork by the session",
    # and reported that the session forks - which is true, but NOT because of
    # those two rows: they are the spawn at sdwind.c:491, which happens BEFORE
    # the hook and was never in question.  The real forks are children of B.
    #
    # Naming the exec target matters as well as counting it: the image the
    # clone turns into is what identifies the call site.  A powershell.exe
    # means !ps_script (op_sh.c:308 builds the path, :379 is the fork), which
    # is how is_grp_member reaches Windows.
    # -----------------------------------------------------------------------
    $clones = @($all | Where-Object { $sdwindPids -contains $_.ParentPid })
    Say ''
    Say "FORK CLONES MADE BY sdwind (sdwind.c:491, before the hook): $($clones.Count)"
    foreach ($c in $clones) { Say "  pid $($c.Pid)  $($c.Name)  at $($c.Time.ToString('HH:mm:ss.fff'))" }

    $clonePids = @($clones | ForEach-Object { $_.Pid })
    $sessions  = @($all | Where-Object { $clonePids -contains $_.ParentPid })

    Say ''
    Say "API SESSIONS (the exec targets of those clones): $($sessions.Count)"
    foreach ($s in $sessions) { Say "  pid $($s.Pid)  $($s.Name)  at $($s.Time.ToString('HH:mm:ss.fff'))" }

    if ($sessions.Count -eq 0) {
        Fail @'
sdwind made no fork clone that went on to exec, so the API session process was
never identified. Without knowing which process WAS the session, "the session
did not fork" is not a claim this run is entitled to make.
'@
    }

    $sessionPids = @($sessions | ForEach-Object { $_.Pid })
    $forks = @($all | Where-Object { $sessionPids -contains $_.ParentPid })

    Say ''
    Say '============================================================'
    Say ' VERDICT'
    Say '============================================================'
    Say "  session pids watched : $($sessionPids -join ', ')"
    Say "  fork clones made BY a session : $($forks.Count)"

    if ($forks.Count -gt 0) {
        foreach ($f in $forks) {
            # What did the clone turn into?  That names the call site.
            $target = @($all | Where-Object { $_.ParentPid -eq $f.Pid })
            $what = if ($target.Count -gt 0) {
                        ($target | ForEach-Object { "$($_.Name) pid $($_.Pid)" }) -join ', '
                    } else { '(no exec seen - a plain fork, or the child died first)' }
            Say ("     {0}  clone {1} pid {2} -> {3}" -f $f.Time.ToString('HH:mm:ss.fff'), $f.Name, $f.Pid, $what)
        }
        Say ''
        Say '  *** THE SESSION DOES FORK, AFTER sdwind SPAWNED IT. ***'
        Say '  probe-impfork measured that fork() silently drops a thread'
        Say '  impersonation, so this is the mechanism behind b28.'
        Say ''
        Say '  If the exec target above is powershell.exe, the call site is'
        Say '  !ps_script (op_sh.c:379 forks, :308 builds the path). The only'
        Say '  thing reaching it after login is is_grp_member - APISRVR:566,'
        Say '  inside vb.account (:439), the account switch that runs AFTER'
        Say '  the hook at :1472 and BEFORE any file is opened for the caller.'
        exit 20
    }

    Say ''
    Say '  THE SESSION DOES NOT FORK between login and the write.'
    Say '  The trace fired (self-test), the session was identified (above), and'
    Say '  no child of it was ever created. So the thing that drops the'
    Say '  impersonation is NOT a fork by the session, and the remaining'
    Say '  candidates are all inside sd.exe.'
    Say ''
    Say '  NEXT IS (b), AND IT COSTS A CYCLE: ImpersonatingUser()'
    Say '  (win32s4u.c:230) exists and has no caller anywhere. Report it at'
    Say '  write time and the answer is direct.'
    exit 21
}
finally {
    Unregister-Event -SourceIdentifier $srcId -ErrorAction SilentlyContinue
    Remove-Event   -SourceIdentifier $srcId -ErrorAction SilentlyContinue
}
