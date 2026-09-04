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
#
# VersionArg IS PER EDITOR AND IS EMPTY WHERE WE DO NOT KNOW THE FLAG.
# PRE_RELEASE_FIXES 153.  It is only ever used when the Win32 version resource
# is empty, and an editor with no entry here is simply not asked - guessing
# "--version" at a full-screen editor is how this step would hang an install.
$Editors = @(
    [pscustomobject]@{ Verb = 'edit';  Name = 'Microsoft Edit'; Exe = 'edit.exe';  Id = 'Microsoft.Edit';  VersionArg = '' },
    [pscustomobject]@{ Verb = 'micro'; Name = 'micro';          Exe = 'micro.exe'; Id = 'zyedidia.micro'; VersionArg = '-version' }
)

# --- what counts as present ------------------------------------------------
# The resolved path, not just a yes: gpl.bp/EDIT resolves the editor the same
# way at run time, so printing what THIS found is what makes a later "editor
# not found" from the verb diagnosable rather than mysterious.
function Find-Editor($exe) {
    # THE BUNDLED COPY FIRST.  PRE_RELEASE_FIXES 66: the installer ships the
    # editor at {app}\usr\bin, beside sd.exe, and this script runs from {app}
    # ({app}\install-editors.ps1), so $PSScriptRoot locates it without touching
    # PATH.  Preferring it makes the version SD shipped the one that runs, and
    # it matches gpl.bp/EDIT's find.editor, which resolves the same fixed path.
    if ($PSScriptRoot) {
        $bundled = Join-Path $PSScriptRoot ('usr\bin\' + $exe)
        if (Test-Path -LiteralPath $bundled) { return $bundled }
    }
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

# --- which version is this, and never a blank -----------------------------
# PRE_RELEASE_FIXES 153.  This line used to read
#     $v = (Get-Item -LiteralPath $found).VersionInfo.ProductVersion
# and micro is a GO BINARY WITH NO WIN32 VERSION RESOURCE, so the log recorded
#     micro: already present - ...\micro.exe  version
# and stopped.  The one place the machine records which micro is installed
# answered nothing - which is the whole of what entry 66 was for, the owner's
# "so that we knew which version was installed".  Microsoft Edit answers 1.2.1
# from the same call, which is why it was never noticed.
#
# A BLANK FIELD READS AS "no version" RATHER THAN "not asked", and that is the
# null case the instrument rules refuse.  So this returns SOMETHING for every
# file that exists: the resource, else the executable's own answer, else the
# size and SHA-256 - which is not a consolation prize, it is the exact value
# stage.py's BUNDLED_EDITORS pins, so a reader can match the log against the
# build.
#
# ***ASKING THE EXECUTABLE IS THE RISKY PART AND IT IS FENCED FOUR WAYS.***
# The installer runs this script HIDDEN, so a full-screen editor that opened
# here would hang the install with nothing on screen to say why:
#   1. only editors with a KNOWN flag are asked (VersionArg above);
#   2. it is only reached when the version resource is empty, so Edit never
#      gets here at all;
#   3. hidden window, stdout and stderr to files, stdin from an EMPTY file, so
#      a TUI cannot take the console and gets EOF at once if it tries to read;
#   4. a five-second timeout and a Kill, and the whole thing inside try/catch -
#      a version string is not worth failing an install over.
function Get-EditorVersion($path, $versionArg) {
    try {
        $v = (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
        if ($null -ne $v) { $v = $v.Trim() }
        if ($v) { return $v }
    } catch { }

    if ($versionArg) {
        $out = Join-Path $env:TEMP ('sd-editorver-' + [guid]::NewGuid().ToString('N') + '.txt')
        $err = $out + '.err'
        $nul = $out + '.in'
        try {
            Set-Content -LiteralPath $nul -Value '' -NoNewline -Encoding ascii
            $p = Start-Process -FilePath $path -ArgumentList $versionArg `
                               -WindowStyle Hidden -PassThru `
                               -RedirectStandardOutput $out `
                               -RedirectStandardError $err `
                               -RedirectStandardInput $nul
            if (-not $p.WaitForExit(5000)) {
                try { $p.Kill() } catch { }
                Say ('    version probe timed out after 5s: ' + $path + ' ' + $versionArg)
            } else {
                $text = ''
                if (Test-Path -LiteralPath $out) { $text = (Get-Content -LiteralPath $out -Raw) }
                if ($text) {
                    # micro prints "Version: 2.0.15" then a commit hash and a
                    # build date.  Take the labelled line where there is one,
                    # and the first non-empty line otherwise.
                    $m = [regex]::Match($text, '(?im)^\s*version\s*:\s*(.+?)\s*$')
                    if ($m.Success) { return $m.Groups[1].Value }
                    foreach ($line in ($text -split "`r?`n")) {
                        if ($line.Trim()) { return $line.Trim() }
                    }
                }
            }
        } catch {
            Say ('    version probe failed: ' + $_.Exception.Message)
        } finally {
            foreach ($f in @($out, $err, $nul)) {
                try { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } } catch { }
            }
        }
    }

    # LAST RESORT, AND STILL NOT A BLANK.  The SHA-256 is what the build pins.
    try {
        $it = Get-Item -LiteralPath $path
        $h  = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
        return ('unknown - {0:n0} bytes, sha256 {1}' -f $it.Length, $h)
    } catch {
        return 'unknown - and the file could not be read to identify it'
    }
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
            $v = Get-EditorVersion $found $ed.VersionArg
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
            # PRE_RELEASE_FIXES 153 - the same question, and the same reason to
            # answer it: "which version did winget just put here" is exactly
            # what a later support call needs, and it was not recorded at all.
            Say ($ed.Verb + ': installed - ' + $found +
                 '  version ' + (Get-EditorVersion $found $ed.VersionArg))
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
