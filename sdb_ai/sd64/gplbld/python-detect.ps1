<#
.SYNOPSIS
    Is there a Python on this machine that SD could actually use?  Reads the
    registry; changes nothing; needs no elevation.

.DESCRIPTION
    ***WHY THIS IS NOT "where python".***  PROJECT_STATUS.md section 8,
    constraint 1.  SD's accounts cannot log in to Windows and API sessions run
    as LocalSystem, so NEITHER CAN REACH A PER-USER INSTALL under
    %LOCALAPPDATA%.  Only an all-users install is usable, and PEP 514 puts that
    under HKLM\SOFTWARE\Python\PythonCore.

    ***AND THE DEV BOX IS THE WRONG-ANSWER CASE, WHICH IS WHY IT IS THE
    FIXTURE.***  Measured 12 Sep 2026 on ACE: no HKLM key at all, a per-user
    3.13 under HKCU, and "python" on PATH resolving to
    C:\Users\Don\AppData\Local\Microsoft\WindowsApps\python.exe.  Anything that
    asked PATH would answer "yes, Python 3.13" and be wrong twice over - wrong
    scope, and possibly the Microsoft Store alias rather than Python at all.
    The same trap cost the editors a round; see HISTORY.md, 26 Aug 2026.

    ***IT REPORTS WHAT IT READ, NOT ONLY WHAT IT CONCLUDED.***  Every hive it
    looked in is named in the output with what was there, including the ones
    whose answer is "reject this".  A verdict with no evidence under it is the
    thing this project keeps paying for.

    ***AND IT DISTINGUISHES "ABSENT" FROM "COULD NOT READ".***  A registry read
    that throws is not an answer, and reporting it as "no Python" would be a
    false negative that reads exactly like a true one.  That case exits 2.

.PARAMETER Quiet
    Verdict line only.  The exit code is unchanged.

.OUTPUTS
    Exit 0  an all-users Python is present and its InstallPath exists
    Exit 1  none is - which is a fact, not an error
    Exit 2  the question could not be answered

.EXAMPLE
    C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\python-detect.ps1
#>

[CmdletBinding()]
param([switch] $Quiet)

$ErrorActionPreference = 'Stop'

function Say([string]$s) { if (-not $Quiet) { Write-Output $s } }

# Returns @{ Ok = bool; Present = bool; Entries = @(...) ; Error = string }
# Ok false means the hive could not be READ, which is not the same as empty.
function Read-PythonHive([string]$root, [string]$label) {
    $res = @{ Ok = $true; Present = $false; Entries = @(); Error = '' }
    try {
        if (-not (Test-Path -LiteralPath $root)) { return $res }
        $res.Present = $true
        foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
            $ver  = $k.PSChildName
            $ip   = ''
            $ipK  = Join-Path $k.PSPath 'InstallPath'
            try {
                if (Test-Path -LiteralPath $ipK) {
                    $ip = (Get-ItemProperty -LiteralPath $ipK -ErrorAction Stop).'(default)'
                    if ($null -eq $ip) { $ip = '' }
                }
            } catch { $ip = '' }
            $res.Entries += [pscustomobject]@{
                Hive    = $label
                Version = $ver
                Path    = $ip
                Exists  = ($ip -ne '' -and (Test-Path -LiteralPath $ip))
            }
        }
    } catch {
        $res.Ok    = $false
        $res.Error = $_.Exception.Message
    }
    return $res
}

$hklm = Read-PythonHive 'HKLM:\SOFTWARE\Python\PythonCore' 'HKLM'
$hkcu = Read-PythonHive 'HKCU:\SOFTWARE\Python\PythonCore' 'HKCU'

Say 'python-detect: PEP 514 registry, read-only'
Say ''
Say '  HKLM\SOFTWARE\Python\PythonCore   <- the ONLY one SD can use'
if (-not $hklm.Ok) {
    Say ("    COULD NOT READ: " + $hklm.Error)
} elseif (-not $hklm.Present) {
    Say '    (key absent - no all-users Python is installed)'
} elseif ($hklm.Entries.Count -eq 0) {
    Say '    (key present but empty)'
} else {
    foreach ($e in $hklm.Entries) {
        Say ("    {0,-6} {1}{2}" -f $e.Version, $(if ($e.Path -eq '') { '(no InstallPath)' } else { $e.Path }),
             $(if ($e.Path -ne '' -and -not $e.Exists) { '   <- RECORDED BUT NOT ON DISK' } else { '' }))
    }
}

Say ''
Say '  HKCU\SOFTWARE\Python\PythonCore   <- REJECTED: per-user, unreachable by SD'
if (-not $hkcu.Ok) {
    Say ("    could not read: " + $hkcu.Error)
} elseif (-not $hkcu.Present -or $hkcu.Entries.Count -eq 0) {
    Say '    (none)'
} else {
    foreach ($e in $hkcu.Entries) { Say ("    {0,-6} {1}" -f $e.Version, $e.Path) }
}

# SHOWN AND EXPLICITLY NOT USED.  It is here so a reader can see WHY the verdict
# disagrees with what they get by typing "python", which on this machine is the
# WindowsApps shim.
Say ''
Say '  PATH lookup                       <- NOT detection, shown for contrast'
$onPath = $null
try { $onPath = (Get-Command python -ErrorAction SilentlyContinue) } catch { }
if ($null -eq $onPath) {
    Say '    python: not on PATH'
} else {
    $src = $onPath.Source
    $note = ''
    if ($src -like '*\WindowsApps\*') { $note = '   <- WindowsApps shim: Store alias or a per-user install' }
    Say ("    python -> " + $src + $note)
}

# ---- verdict ---------------------------------------------------------------
#
# USABLE means: an HKLM entry whose InstallPath is recorded AND exists.  A key
# naming a directory that is gone is an uninstall that did not finish, and
# treating it as present would send the installer down a path with no python.exe
# at the end of it.

$usable = @($hklm.Entries | Where-Object { $_.Exists })

Say ''
if (-not $hklm.Ok) {
    Write-Output 'python-detect: COULD NOT ANSWER - the HKLM hive did not read.'
    Write-Output '  This is not "no Python".  Nothing should act on it.'
    exit 2
}
if ($usable.Count -gt 0) {
    $v = ($usable | ForEach-Object { $_.Version }) -join ', '
    Write-Output ("python-detect: USABLE - all-users Python present: " + $v)
    exit 0
}

Write-Output 'python-detect: NONE USABLE - no all-users Python on this machine.'
if ($hkcu.Ok -and $hkcu.Entries.Count -gt 0) {
    Write-Output ('  A per-user Python IS installed (' + (($hkcu.Entries | ForEach-Object { $_.Version }) -join ', ') +
                  ') and SD cannot use it: its accounts cannot sign in to Windows,')
    Write-Output '  and API sessions run as LocalSystem.  Neither reaches %LOCALAPPDATA%.'
}
if ($hklm.Entries.Count -gt 0) {
    Write-Output '  An HKLM entry exists but its InstallPath is missing or gone - an unfinished uninstall.'
}
exit 1
