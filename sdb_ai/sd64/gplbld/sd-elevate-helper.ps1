# sd-elevate-helper.ps1 - the elevated half of an SD administrator session
#
# Launched by sd-elevate.ps1 through Start-Process -Verb RunAs, which is where
# the UAC prompt appears.  Serves one SD session until told to stop or until
# that session's process disappears, running the PowerShell scripts SD hands
# it and returning their exit codes.
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
# IT DIES WITH ITS SESSION.  A privileged process outliving the session that
# asked for it is the thing to avoid above all, so the owning pid is checked
# both while idle and between requests.

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

function Test-OwnerAlive {
    return [bool](Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue)
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
                Say "session $OwnerPid has gone - exiting"
                $server.Dispose()
                exit 0
            }
        }
        $server.EndWaitForConnection($iar)

        $reader = New-Object IO.StreamReader($server)
        $writer = New-Object IO.StreamWriter($server)
        $writer.AutoFlush = $true

        $req = $reader.ReadLine()

        if ($req -eq 'PING') {
            # Answers what the caller actually needs to know: that something
            # ELEVATED is on the other end.  sd-elevate.ps1 refuses to trust an
            # exit code from a helper that is not.
            $writer.WriteLine('ELEVATED')
            $server.Dispose()
            continue
        }

        if ($req -eq 'STOP') {
            $writer.WriteLine('0')
            Say "stop requested"
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

        $code = 1
        try {
            $p = Start-Process powershell -Wait -PassThru -WindowStyle Hidden `
                -ArgumentList @('-NoProfile', '-NonInteractive',
                                '-ExecutionPolicy', 'Bypass',
                                '-File', "`"$req`"")
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
