# dism-capability.ps1 - read, add and remove a Windows capability through
# dism.exe.  Dot-sourced by install-ssh.ps1 and remove-ssh.ps1; defines
# functions only, prints nothing, runs nothing on load.  RELEASE_1.1 109.
#
# WHY dism.exe AND NOT Get-/Add-/Remove-WindowsCapability.  Measured 24 Sep 2026
# on the owner's test machine, elevated: Get-WindowsCapability sat for minutes
# and then threw "Class not registered", while "dism /online /get-capabilities"
# in the same kind of prompt listed every capability.  The cmdlets are a front
# end to the same servicing API, so the break was in PowerShell's DISM module on
# that machine, not in Windows servicing - and the installer's OpenSSH step,
# which used the cmdlet, failed there before any download, taking the ssh-limit
# and firewall steps down with it.
#
# dism.exe OUTRIGHT, NOT AS A FALLBACK.  A second path that only runs on a broken
# machine is a path nobody tests.
#
# /English because dism translates its output and State is parsed below.
# /NoRestart because these run hidden and non-interactive, and without it dism
# can offer to restart Windows at the end of an add or remove.
#
# ONE COPY FOR BOTH CALLERS, on purpose: the State parse is the fragile part, and
# two copies of it are how one of them ends up reading a different spelling.

$DismRestartNeeded = 3010

function Get-DismExe {
    # A 32-bit PowerShell on 64-bit Windows is redirected from System32 to
    # SysWOW64, and a 32-bit dism cannot service the running 64-bit system.
    # Sysnative is the way back.  The installer runs in 64-bit mode (sd.iss
    # ArchitecturesInstallIn64BitMode), so this is for the unexpected caller.
    $dir = 'System32'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $dir = 'Sysnative'
    }
    return (Join-Path $env:SystemRoot ($dir + '\dism.exe'))
}

# Returns @{ Command; Code; Lines }.  Command is the exact line run, so a caller
# can log what was really passed; Lines is dism's output with the progress bars
# dropped.  PRINTS NOTHING: a function that prints and returns hands its caller
# the printed lines as part of the value (test-outputtrap-units.ps1).
#
# NOT $args - that is a PowerShell automatic variable, and a parameter of that
# name is silently replaced (CLAUDE.md, the instrument rules).
function Invoke-Dism([string[]]$DismArgs) {
    $exe = Get-DismExe
    # Continue, locally: under Stop, PowerShell 5.1 turns a native program's
    # redirected stderr into a terminating error.
    $ErrorActionPreference = 'Continue'
    $raw  = & $exe /Online /English @DismArgs 2>&1
    $code = $LASTEXITCODE
    $lines = New-Object System.Collections.ArrayList
    foreach ($r in @($raw)) {
        # A progress bar redraws itself with carriage returns; keep what is
        # left after the last one.
        $t = (("" + $r) -split "`r")[-1].TrimEnd()
        if ($t -eq '') { continue }
        if ($t -match '^\s*\[' -and $t -match '%') { continue }
        $null = $lines.Add($t)
    }
    return @{
        Command = ($exe + ' /Online /English ' + ($DismArgs -join ' '))
        Code    = $code
        Lines   = $lines.ToArray()
    }
}

# The State line of a /Get-CapabilityInfo result with its spaces removed, so it
# reads like the old cmdlet's values - Installed, NotPresent, UninstallPending -
# or '' when dism printed no State line at all.  Removing the spaces makes the
# comparison indifferent to whether dism writes "Uninstall Pending" or
# "UninstallPending".  Seen on a real run (the test machine, 24 Sep 2026, the
# /Get-Capabilities listing): "State : Installed" and "State : Not Present".
# That /Get-CapabilityInfo prints the same label is expected, not yet seen.
function Get-CapabilityState($Result) {
    foreach ($l in $Result.Lines) {
        if ($l -match '^\s*State\s*:\s*(.+?)\s*$') {
            return ($Matches[1] -replace '\s', '')
        }
    }
    return ''
}
