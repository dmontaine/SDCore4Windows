# micro-home.ps1 - give the CALLING USER a micro configuration home they can
# write to, and print where it is.  Run by gpl.bp/EDIT before it launches micro.
#
#   powershell -File micro-home.ps1
#
# Prints exactly one machine-readable line on success:
#
#     MICROHOME=C:\Users\<someone>\.micro
#
# Exit 0 with that line, 1 without it.  Every other line is diagnostics and
# begins "micro-home:", so the caller can anchor on MICROHOME= and nothing else.
#
# WHY THIS EXISTS.  PRE_RELEASE_FIXES #29.  micro writes to its configuration
# home when it saves, and EDIT used to point MICRO_CONFIG_HOME at
# C:\Program Files\SD\micro, which is BUILTIN\Users:(RX).  Every save from an
# unelevated account then printed
#
#     Permission denied. Save with sudo not supported on Windows
#
# in red - and wrote the file anyway.  A false alarm rather than data loss, but
# the wording says "refused" and a user has no reason to doubt it.
#
# MEASURED, NOT REASONED - four runs, one variable, 27 Aug 2026.  Same file in a
# writable directory, unelevated, micro launched straight from PowerShell, only
# MICRO_CONFIG_HOME differing: read-only home errors with no flags, with
# "-backup off", and with "-backup false -savehistory false"; a writable home is
# clean.  NO OPTION SUPPRESSES IT, so the home has to be writable.  An earlier
# fix passed "-backup off" on the strength of reasoning alone and fixed nothing.
#
# ***AND IT MUST BE PER-USER, NOT ONE SHARED WRITABLE DIRECTORY.***  micro loads
# and executes Lua plugins from its configuration home.  A single directory every
# SD user can write is one where any user can drop code that runs inside every
# other user's editor session, with that user's rights - a privilege escalation
# traded for a cosmetic message.  A directory only its owner can write is one
# where the only code they can run is their own.
#
# WHY THE HOME DIRECTORY.  Owner's ruling, 27 Aug 2026, and it is where micro
# itself looks: $MICRO_CONFIG_HOME, then $XDG_CONFIG_HOME/micro, then
# ~/.config/micro.  A home-directory configuration is micro's own arrangement
# rather than something SD invents.
#
# ".micro" AND NOT micro's OWN "~/.config/micro", also his: this host already
# carries C:\Users\dmont\.config\micro with a personal bindings.json in it, made
# outside SD.  Writing SD's syntax file into a user's own configuration - and
# inheriting their settings into SD's editor - is a collision in both
# directions.  ".micro" belongs to SD and meets neither.
#
# ***%USERPROFILE%, NEVER C:\Users\<login>.***  Measured on this host: the login
# name is "don" and the profile is "C:\Users\dmont".  Building the path from the
# account name would be wrong SILENTLY - it would make a second directory nobody
# reads and leave micro with nowhere writable, which is the bug this fixes.
#
# THE FALLBACK IS NOT DECORATION.  An SD account that only ever arrives over ssh
# may have no populated profile: the C:\Users\sd* directories left behind on the
# build host are empty stubs with no NTUSER.DAT, so "an ssh account has a
# profile" is UNMEASURED.  Rather than block the fix on it, TEMP is tried when
# the profile cannot be written.  Both candidates are per-user and private, so
# the plugin question above is answered whichever one wins.
#
# WRITABILITY IS TESTED BY WRITING.  Test-Path answers whether a directory
# exists, which is not the question; a profile directory can exist and refuse a
# file.  Each candidate gets a real probe file, created and deleted.

[CmdletBinding()]
param(
    # The read-only master copy of the syntax directory.  Defaults to the one
    # beside this script in Program Files; a parameter so the build can test
    # against a staged tree without an install.
    [string] $Master = ''
)

$ErrorActionPreference = 'Stop'

function Say($m) { Write-Output ("micro-home: " + $m) }

# --- where the shipped syntax file lives -----------------------------------
# $PSScriptRoot is C:\Program Files\SD; the master is its micro\syntax.  Derived
# rather than hard-coded so a staged tree and an install both work.
if ($Master -eq '') { $Master = Join-Path $PSScriptRoot 'micro' }
$masterSyntax = Join-Path $Master 'syntax'

# --- the candidates, in order ----------------------------------------------
$candidates = @()
if ($env:USERPROFILE) { $candidates += (Join-Path $env:USERPROFILE '.micro') }
if ($env:TEMP)        { $candidates += (Join-Path $env:TEMP 'sd-micro') }

if ($candidates.Count -eq 0) {
    Say 'neither USERPROFILE nor TEMP is set - there is nowhere to put a writable configuration home'
    exit 1
}

function Test-Writable([string]$dir) {
    # Create it if it is not there, then prove a file can be made in it.  A
    # directory that exists is not a directory that accepts a write.
    try {
        if (Test-Path -LiteralPath $dir -PathType Leaf) { return $false }
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }
        $probe = Join-Path $dir ('.write-probe-' + [Guid]::NewGuid().ToString('N'))
        $fs = [System.IO.File]::Open($probe, [System.IO.FileMode]::CreateNew,
                                     [System.IO.FileAccess]::Write)
        $fs.Close()
        Remove-Item -LiteralPath $probe -Force
        return $true
    }
    catch { return $false }
}

$home1 = ''
foreach ($c in $candidates) {
    if (Test-Writable $c) { $home1 = $c; break }
    Say ("not writable, trying the next: " + $c)
}

if ($home1 -eq '') {
    Say ('no candidate could be written: ' + ($candidates -join ', '))
    Say 'micro would report "Permission denied" on every save, so EDIT should refuse instead'
    exit 1
}

Say ("configuration home: " + $home1)

# --- the syntax file, copied from the read-only master ----------------------
# THIS IS WHAT DISPOSES OF THE OLD OBJECTION.  gpl.bp/EDIT and stage.py both
# used to say a per-profile configuration was useless because accounts SD
# creates cannot log in to Windows, "so a syntax file in a profile is one they
# could never be given".  That is only true of a file nobody puts there.
#
# REFRESHED WHEN THE MASTER IS NEWER, so a release that regenerates
# sdbasic.yaml reaches a user who already has one.  mkbasicsyntax.py builds it
# from BCOMP's own tables, so it does change between releases.
#
# A MISSING MASTER IS NOT FATAL.  Without the syntax file micro still edits and
# still saves; it just does not colour SD BASIC.  Refusing here would trade the
# defect this script fixes for a worse one.
$destSyntax = Join-Path $home1 'syntax'
$srcYaml    = Join-Path $masterSyntax 'sdbasic.yaml'
$dstYaml    = Join-Path $destSyntax 'sdbasic.yaml'

if (-not (Test-Path -LiteralPath $srcYaml)) {
    Say ("WARNING: no syntax master at " + $srcYaml + " - micro will run without SD BASIC highlighting")
}
else {
    try {
        if (-not (Test-Path -LiteralPath $destSyntax)) {
            $null = New-Item -ItemType Directory -Path $destSyntax -Force
        }
        $copy = $true
        if (Test-Path -LiteralPath $dstYaml) {
            $s = (Get-Item -LiteralPath $srcYaml).LastWriteTimeUtc
            $d = (Get-Item -LiteralPath $dstYaml).LastWriteTimeUtc
            if ($d -ge $s) { $copy = $false }
        }
        if ($copy) {
            Copy-Item -LiteralPath $srcYaml -Destination $dstYaml -Force
            Say ("syntax file copied from the master (" + (Get-Item -LiteralPath $dstYaml).Length + " bytes)")
        } else {
            Say 'syntax file already current'
        }
    }
    catch {
        # Same reasoning as a missing master: highlighting is not worth refusing
        # the editor over.
        Say ("WARNING: could not place the syntax file: " + $_.Exception.Message)
    }
}

# THE ONE LINE THE CALLER READS.  It appears here and nowhere else, and only on
# the path where a writable home was proved by writing to it - so a caller that
# matches on it cannot be reading back its own input or an error message.
Write-Output ("MICROHOME=" + $home1)
exit 0
