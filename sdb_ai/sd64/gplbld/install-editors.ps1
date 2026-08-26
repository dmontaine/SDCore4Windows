# install-editors.ps1 - make sure the full-screen editors the EDIT and MICRO
# verbs run are on the machine.  Owner's rulings, 26 Aug 2026.
#
#   powershell -File install-editors.ps1 [-CheckOnly]
#
# Exit 0  every editor is present (already was, or this installed it)
#      2  at least one is missing and could not be installed
#      1  failed for a reason worth reading
#
# WAS install-edit.ps1, RENAMED THE SAME DAY when the second editor arrived.
# It never shipped in a release under the old name.
#
# IT IS NOT A FAILURE OF THE INSTALL.  Exit 2 is the OpenSSH shape and for the
# same reason: a machine can be offline, behind a proxy, on a policy that
# blocks winget, or a Server SKU with no App Installer.  SD is complete without
# either editor; only that verb is not, and ED - the line editor - needs
# nothing installed at all.  Report it and let the install finish.
#
# WHY IT LOOKS FOR THE EXECUTABLE FIRST.  Microsoft Edit ships IN Windows on
# current builds - C:\Windows\System32\edit.exe, measured on this machine
# 26 Aug 2026 at version 1.2.1 - so most machines need nothing done for that
# one.  Running winget on a machine that already has it would be a download for
# no reason and, on the per-user default, would put a SECOND copy somewhere
# only one profile can see.
#
# ***AND THAT IS THE TRAP THIS SCRIPT EXISTS TO AVOID.*** "winget install
# <id>" with no scope is a PER-USER install: it lands in
# %LOCALAPPDATA%\Microsoft\WinGet\Packages of whoever ran it.  The installer
# runs elevated, so that profile is the installing administrator's - or
# SYSTEM's - and NOT the profile of any account SD creates.  Those accounts
# cannot log in to Windows at all, so a per-user copy is one they can never
# reach.  --scope machine is what makes an editor everybody's.
#
# ***AND IF MACHINE SCOPE IS REFUSED, THIS DOES NOT FALL BACK TO PER-USER.***
# A fallback would report success and leave SD's own users with nothing, which
# is worse than the honest refusal: the whole point of the scope is who can
# reach the result.
#
# WHY NOT Add-WindowsCapability, like OpenSSH.  Neither editor is a Windows
# capability - they are winget packages, and there is no Features-on-Demand
# name for either.

[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'

# THE INSTALLER RUNS THIS HIDDEN, so anything it prints is lost unless it is
# also written down.  upgrade-dicts.log is the precedent: the step that can
# quietly not happen leaves a file saying what happened.  Without it, "no
# editor" reaches the user as EDIT refusing, weeks later, with nothing to read.
$LogPath = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD\install-editors.log'

function Say($m) {
    $line = "install-editors: " + $m
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

# THE TABLE IS THE WHOLE DIFFERENCE BETWEEN THE TWO.  gpl.bp/EDIT carries the
# same pair of names for the same two verbs; if one is changed the other has
# to be, and there is nothing else to keep in step.
$Editors = @(
    [pscustomobject]@{ Verb = 'edit';  Name = 'Microsoft Edit'; Exe = 'edit.exe';  Id = 'Microsoft.Edit' },
    [pscustomobject]@{ Verb = 'micro'; Name = 'micro';          Exe = 'micro.exe'; Id = 'zyedidia.micro' }
)

# --- what counts as present ------------------------------------------------
# The resolved path, not just a yes: gpl.bp/EDIT resolves the editor the same
# way at run time, so printing what THIS found is what makes a later "editor
# not found" from the verb diagnosable rather than mysterious.
function Find-Editor($exe) {
    $c = Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue
    if ($c) { return $c[0].Source }
    foreach ($p in @(
        (Join-Path $env:SystemRoot ('System32\' + $exe)),
        (Join-Path $env:ProgramFiles ('WinGet\Links\' + $exe))
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return ''
}

function Refresh-Path {
    # A fresh PATH: the machine PATH this process started with does not carry
    # a link directory winget has just created.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

try {
    Say ('editors wanted: ' + (($Editors | ForEach-Object { $_.Verb + ' -> ' + $_.Exe }) -join ', '))

    $missing = @()
    $winget = $null

    foreach ($ed in $Editors) {
        $found = Find-Editor $ed.Exe
        if ($found -ne '') {
            $v = (Get-Item -LiteralPath $found).VersionInfo.ProductVersion
            Say ($ed.Verb + ': already present - ' + $found + '  version ' + $v)
            continue
        }

        Say ($ed.Verb + ': no ' + $ed.Exe + ' on this machine')

        if ($CheckOnly) {
            Say ($ed.Verb + ': CheckOnly - nothing installed')
            $missing += $ed.Verb
            continue
        }

        if ($null -eq $winget) {
            $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Say 'not elevated - a machine-scope install needs an elevated session'
                exit 1
            }
            $w = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue
            if (-not $w) {
                Say 'winget is not on this machine, so there is nothing to install with'
                $missing += $ed.Verb
                continue
            }
            $winget = $w[0].Source
            Say ('winget: ' + $winget)
        }

        # An instrument prints the command line it really used (CLAUDE.md).
        $wargs = @('install', '--id', $ed.Id, '--exact',
                   '--scope', 'machine', '--silent',
                   '--accept-package-agreements', '--accept-source-agreements',
                   '--disable-interactivity')
        Say ($ed.Verb + ': running winget ' + ($wargs -join ' '))

        # A native command writing to stderr terminates the script under
        # ErrorActionPreference Stop, so the output is folded in and the exit
        # code read explicitly rather than trusted to $?.
        & $winget @wargs 2>&1 | ForEach-Object { Say ('    ' + $_) }
        Say ($ed.Verb + ': winget exited ' + $LASTEXITCODE)

        # THE VERDICT IS THE MACHINE STATE, NOT THE EXIT CODE.  winget reports
        # 0 for "no applicable installer" on some SKUs and non-zero for an
        # already-installed package; what matters is whether an executable is
        # reachable afterwards.
        Refresh-Path
        $found = Find-Editor $ed.Exe
        if ($found -ne '') {
            Say ($ed.Verb + ': installed - ' + $found)
        } else {
            Say ($ed.Verb + ': winget ran and no ' + $ed.Exe + ' is reachable afterwards')
            $missing += $ed.Verb
        }
    }

    if ($missing.Count -eq 0) {
        Say 'every editor is present'
        exit 0
    }

    Say ('NOT AVAILABLE: ' + ($missing -join ', ') +
         ' - that verb will refuse and name the command that installs it')
    Say 'ed, the line editor, is unaffected and needs nothing'
    exit 2
}
catch {
    Say ("FAILED - " + $_.Exception.Message)
    exit 1
}
