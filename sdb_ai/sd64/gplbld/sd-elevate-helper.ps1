# sd-elevate-helper.ps1 - the elevated half of an SD administrator session
#
# Launched by sd-elevate.ps1 through Start-Process -Verb RunAs, which is where
# the UAC prompt appears.  Serves every SD session belonging to one user until
# the last of them stops or disappears, running the PowerShell scripts SD
# hands it and returning their exit codes.
#
# PROJECT_STATUS.md 7 step 4 and 5.6.  Owner's decisions, 16 Aug 2026:
# elevation comes from entering SDSYS and from nowhere else, and there is no
# ELEVATE verb - a normal session must never be able to elevate itself.
#
# WHY A HELPER AND NOT AN ELEVATED sd.exe.  A Windows process's token is fixed
# when it is created; nothing can elevate a running process.  So SD stays
# unelevated for its whole life and this process holds the privilege instead,
# which is the smaller blast radius of the two: with an elevated terminal
# everything typed runs privileged, whereas here only what SD sends does.
#
# THE EXPLICIT PIPE DACL IS LOAD-BEARING, MEASURED 16 Aug 2026.  Without it
# the pipe takes this elevated process's default DACL and the unelevated SD
# session is refused with "Access to the path is denied" - the whole design
# failing, at the one moment nobody is watching.  Granting the owning user's
# SID is also the security boundary: no other user can reach this pipe, which
# matters because the data tree is writable by every member of sdusers.
#
# IT DIES WITH ITS SESSIONS - PLURAL SINCE 29 Aug 26, AND THAT IS THE ONLY
# PART OF THIS RULE THAT MOVED.  A privileged process outliving the sessions
# that asked for it is still the thing to avoid above all, and the owning pids
# are still checked both while idle and between requests.  What changed is how
# many there are: PRE_RELEASE_FIXES 56 elevates an administrator AT LOGIN, so
# a helper scoped to one sd.exe meant a UAC prompt per COMMAND.  One helper
# now serves every session of one user and exits when the last of them goes.
#
# THE NAME WIDENED AND THE ACL DID NOT, which is what makes that safe.  The
# pipe is "sd-elev-<logname>" rather than "...-<userno>", and the DACL below
# still grants exactly one SID - this user's.  No other account can reach the
# pipe, so no other account can register a pid with it or send it a script.

param(
    [Parameter(Mandatory = $true)][string]$PipeName,
    [Parameter(Mandatory = $true)][int]$OwnerPid,
    [string]$LogFile = ''
)

function Say($m) {
    if ($LogFile -ne '') {
        try {
            Add-Content -LiteralPath $LogFile -Value (
                "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
        } catch { }
    }
}

$elevated = ([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# Refuse to serve unelevated.  Without this the helper would answer requests
# it cannot carry out and SD would report failures that look like Windows
# refusing the operation rather than the helper never having been elevated.
if (-not $elevated) {
    Say "not elevated - refusing to serve"
    exit 2
}

Say "helper up, pid $PID, serving session $OwnerPid"

$me = [Security.Principal.WindowsIdentity]::GetCurrent().User

# 29 Aug 26 - ONE HELPER PER USER, SO THERE IS A SET OF OWNERS AND NOT ONE.
# PRE_RELEASE_FIXES 56.  The rule in the header is UNCHANGED IN SUBSTANCE -
# this still dies with its sessions - but it now has more than one, so "the
# owner is gone" becomes "every owner is gone".  Each -Start and -Run
# registers a pid through PING and -Stop deregisters one; the last one out
# turns the light off.
#
# A HASHTABLE AND NOT AN ARRAY, DELIBERATELY.  PowerShell's "+" on an array is
# the trap that splits one element into two or folds two into one depending on
# which side the literal is; keying by pid cannot do either, and Remove() on a
# pid that was never registered is silently fine, which is what a duplicate
# STOP needs.
#
# ONLY THIS USER CAN REGISTER, and that is the pipe DACL rather than anything
# here: it grants this user's SID and nobody else's, so no other account can
# reach the pipe to add a pid to this set.
$owners = @{}
if ($OwnerPid -gt 0) { $owners[$OwnerPid] = $true }

function Test-OwnerAlive {
    # Prune first, then answer.  A snapshot of the keys, because removing from
    # a hashtable while enumerating it throws.
    foreach ($p in @($owners.Keys)) {
        if (-not (Get-Process -Id $p -ErrorAction SilentlyContinue)) {
            $owners.Remove($p)
            Say "session $p has gone; $($owners.Count) left"
        }
    }
    return ($owners.Count -gt 0)
}

try {
    while (Test-OwnerAlive) {
        $psec = New-Object System.IO.Pipes.PipeSecurity
        $psec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule(
            $me, 'FullControl', 'Allow')))

        $server = New-Object System.IO.Pipes.NamedPipeServerStream(
            $PipeName, 'InOut', 1, 'Byte', 'Asynchronous', 4096, 4096, $psec)

        # Wake periodically while idle so a session that ended without saying
        # so - killed, crashed, window closed - still releases this process.
        $iar = $server.BeginWaitForConnection($null, $null)
        $connected = $false
        while (-not $connected) {
            if ($iar.AsyncWaitHandle.WaitOne(2000)) { $connected = $true; break }
            if (-not (Test-OwnerAlive)) {
                Say "every session has gone - exiting"
                $server.Dispose()
                exit 0
            }
        }
        $server.EndWaitForConnection($iar)

        $reader = New-Object IO.StreamReader($server)
        $writer = New-Object IO.StreamWriter($server)
        $writer.AutoFlush = $true

        $req = $reader.ReadLine()

        # 29 Aug 26 - PING AND STOP NOW CARRY A PID.  PRE_RELEASE_FIXES 56.
        # Split once here rather than in two places; anything else is a script
        # path and must not be touched, because a path can contain a space and
        # SD's are "$PS.TMP.<userno>" under a data tree the user can name.
        $verb = $req
        $argPid = 0
        if ($req -match '^(PING|STOP) +([0-9]+)$') {
            $verb = $Matches[1]
            $argPid = [int]$Matches[2]
        }

        if ($verb -eq 'PING') {
            # Answers what the caller actually needs to know: that something
            # ELEVATED is on the other end.  sd-elevate.ps1 refuses to trust an
            # exit code from a helper that is not.
            #
            # AND REGISTERS THE ASKER, which is what makes one helper per user
            # safe: a session that found this helper instead of starting one
            # has no other moment to say it is here.  Re-registering an
            # already-known pid is a no-op.
            if ($argPid -gt 0 -and -not $owners.ContainsKey($argPid)) {
                $owners[$argPid] = $true
                Say "session $argPid registered; $($owners.Count) now"
            }
            $writer.WriteLine('ELEVATED')
            $server.Dispose()
            continue
        }

        if ($verb -eq 'STOP') {
            # ONE SESSION LEAVING IS NOT THE HELPER STOPPING.  CPROC calls
            # elevate('STOP') every time a session leaves SDSYS, and with one
            # helper serving every session of a user that must not take the
            # privilege away from the others.  Exit only when the last owner
            # has gone.
            #
            # A BARE STOP - no pid - still stops it outright.  That is what a
            # diagnostic or a cleanup means by STOP, and it is what this
            # message meant before there was anything to deregister.
            if ($argPid -gt 0) {
                $owners.Remove($argPid)
                Say "session $argPid deregistered; $($owners.Count) left"
                $writer.WriteLine('0')
                $server.Dispose()
                if ($owners.Count -gt 0) { continue }
                Say "last session left - exiting"
                break
            }

            $writer.WriteLine('0')
            Say "stop requested outright"
            $server.Dispose()
            break
        }

        # Anything else is a script path.  SD writes these into the data tree,
        # which the installer has already restricted, and they are deleted by
        # the caller afterwards - see !ps_script, which is the only thing that
        # sends them.
        if (-not (Test-Path -LiteralPath $req)) {
            Say "no such script: $req"
            $writer.WriteLine('9')
            $server.Dispose()
            continue
        }

        # RUN IT THE WAY !ps_script RUNS IT LOCALLY, WHICH IS NOT -File.
        # Measured 16 Aug 2026: -File REFUSES a file that is not named *.ps1 -
        # "Processing -File '...' failed because the file does not have a
        # '.ps1' extension" - and exits -196608 without running a line of it.
        # SD names these files "$PS.TMP.<userno>", so -File could never have
        # run a single one; CREATE.ACCOUNT reported "Create User Failed, OS
        # Error: 127" from the far end of that.
        #
        # !ps_script uses "Get-Content | Invoke-Expression" for exactly this
        # reason, and the two paths must not differ in how they execute - only
        # in what privilege they execute with.  Single quotes round the path
        # keep the leading $ of the name literal to the child, as they do
        # there.
        #
        # STILL A CHILD PROCESS, NOT Invoke-Expression IN HERE.  The scripts
        # end in "exit 0" / "exit 1" / "exit 5", and run in-process that would
        # terminate the helper itself and take the session's privilege with it.
        # The child's exit code is the script's own answer.
        $code = 1
        try {
            $p = Start-Process powershell -Wait -PassThru -WindowStyle Hidden `
                -ArgumentList @('-NoProfile', '-NonInteractive',
                                '-ExecutionPolicy', 'Bypass',
                                '-Command',
                                "Get-Content -LiteralPath '$req' -Raw | Invoke-Expression")
            $code = $p.ExitCode
        } catch {
            Say "run failed: $($_.Exception.Message)"
            $code = 1
        }

        Say "ran $req -> $code"
        $writer.WriteLine([string]$code)
        $server.Dispose()
    }
}
catch {
    Say "helper error: $($_.Exception.Message)"
}

Say "helper exiting"
exit 0
