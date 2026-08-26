# install-edit.ps1 - make sure a terminal full-screen editor exists for the
# EDIT verb.  Owner's ruling, 26 Aug 2026.
#
#   powershell -File install-edit.ps1 [-CheckOnly]
#
# Exit 0  an editor is present (already was, or this installed it)
#      2  none, and it could not be installed - SD still works, EDIT does not
#      1  failed for a reason worth reading
#
# IT IS NOT A FAILURE OF THE INSTALL.  Exit 2 is the OpenSSH shape and for the
# same reason: a machine can be offline, behind a proxy, on a policy that
# blocks winget, or a Server SKU with no App Installer.  SD is complete without
# the editor; only the EDIT verb is not, and ED - the line editor - needs
# nothing installed at all.  Report it and let the install finish.
#
# WHY IT LOOKS FOR THE EXECUTABLE FIRST.  Microsoft Edit ships IN Windows on
# current builds - C:\Windows\System32\edit.exe, measured on this machine
# 26 Aug 2026 at version 1.2.1 - so most machines need nothing done.  Running
# winget on one that already has it would be a download for no reason and, on
# the per-user default, would put a SECOND copy somewhere only one profile can
# see.
#
# ***AND THAT IS THE TRAP THIS SCRIPT EXISTS TO AVOID.*** "winget install
# Microsoft.Edit" with no scope is a PER-USER install: it lands in
# %LOCALAPPDATA%\Microsoft\WinGet\Packages of whoever ran it.  The installer
# runs elevated, so that profile is the installing administrator's - or
# SYSTEM's - and NOT the profile of any account SD creates.  Those accounts
# cannot log in to Windows at all, so a per-user copy is one they can never
# reach.  --scope machine is what makes the editor everybody's.
#
# WHY NOT Add-WindowsCapability, like OpenSSH.  Edit is not a Windows
# capability - it is a winget package on machines that do not already carry the
# executable, and there is no Features-on-Demand name for it.

[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'

# THE INSTALLER RUNS THIS HIDDEN, so anything it prints is lost unless it is
# also written down.  upgrade-dicts.log is the precedent: the step that can
# quietly not happen leaves a file saying what happened.  Without it, "no
# editor" reaches the user as EDIT refusing, weeks later, with nothing to read.
$LogPath = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD\install-edit.log'

function Say($m) {
    $line = "install-edit: " + $m
    Write-Output $line
    try {
        $dir = Split-Path -Parent $LogPath
        if (Test-Path -LiteralPath $dir) {
            Add-Content -LiteralPath $LogPath -Value ((Get-Date -Format 's') + '  ' + $line) -Encoding utf8
        }
    } catch {
        # A log that cannot be written must not fail the install.
    }
}

# --- what counts as present ------------------------------------------------
# The resolved path, not just a yes: gpl.bp/EDIT resolves the editor the same
# way at run time, so printing what THIS found is what makes a later "editor
# not found" from the verb diagnosable rather than mysterious.
function Find-Editor {
    $c = Get-Command -Name 'edit.exe' -CommandType Application -ErrorAction SilentlyContinue
    if ($c) { return $c[0].Source }
    foreach ($p in @(
        (Join-Path $env:SystemRoot 'System32\edit.exe'),
        (Join-Path $env:ProgramFiles 'WinGet\Links\edit.exe')
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return ''
}

try {
    $found = Find-Editor
    if ($found -ne '') {
        $v = (Get-Item -LiteralPath $found).VersionInfo.ProductVersion
        Say ("already present: " + $found + "  version " + $v)
        exit 0
    }

    Say 'no edit.exe on this machine'

    if ($CheckOnly) {
        Say 'CheckOnly - nothing installed'
        exit 2
    }

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Say 'not elevated - a machine-scope install needs an elevated session'
        exit 1
    }

    $winget = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue
    if (-not $winget) {
        Say 'winget is not on this machine, so there is nothing to install with'
        Say 'EDIT will refuse and say so; ed, the line editor, is unaffected'
        exit 2
    }
    Say ("winget: " + $winget[0].Source)

    # An instrument prints the command line it really used (CLAUDE.md).
    $wargs = @('install', '--id', 'Microsoft.Edit', '--exact',
               '--scope', 'machine', '--silent',
               '--accept-package-agreements', '--accept-source-agreements',
               '--disable-interactivity')
    Say ('running: winget ' + ($wargs -join ' '))

    # A native command writing to stderr terminates the script under
    # ErrorActionPreference Stop, so the output is folded in and the exit code
    # read explicitly rather than trusted to $?.
    & $winget[0].Source @wargs 2>&1 | ForEach-Object { Say ('  ' + $_) }
    $code = $LASTEXITCODE
    Say ("winget exited " + $code)

    # THE VERDICT IS THE MACHINE STATE, NOT THE EXIT CODE.  winget reports 0
    # for "no applicable installer" on some SKUs, and a non-zero for an
    # already-installed package; what matters is whether an executable is
    # reachable afterwards.  A fresh PATH is needed for that - the machine PATH
    # this process started with does not carry the link directory winget just
    # created.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')

    $found = Find-Editor
    if ($found -ne '') {
        Say ("installed: " + $found)
        exit 0
    }

    Say 'winget ran and no edit.exe is reachable afterwards'
    Say 'EDIT will refuse and say so; ed, the line editor, is unaffected'
    exit 2
}
catch {
    Say ("FAILED - " + $_.Exception.Message)
    exit 1
}
