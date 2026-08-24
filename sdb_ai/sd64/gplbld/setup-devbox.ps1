# setup-devbox.ps1 - build a SD for Windows development machine from nothing.
#
#   powershell -ExecutionPolicy Bypass -File setup-devbox.ps1
#   powershell -ExecutionPolicy Bypass -File setup-devbox.ps1 -CheckOnly
#   powershell -ExecutionPolicy Bypass -File setup-devbox.ps1 -Root D:\Projects
#
# ELEVATED.  Installing MSYS2 and Inno Setup needs it, and the script refuses
# without it rather than failing halfway through.
#
# Exit 0 everything needed is present, 1 something could not be done, 2 it
# could not start (not elevated, no winget).
#
# IT IS SAFE TO RE-RUN.  Every step checks before it acts and says "already
# present" rather than reinstalling, so this doubles as a way to find out what
# a machine is missing - which is what -CheckOnly does without changing
# anything.
#
# ---------------------------------------------------------------------------
# IT MUST BE ABLE TO RUN BEFORE THIS REPOSITORY IS CLONED, which is why it does
# not read anything from the tree it lives in.  Fetch it on its own:
#
#   curl.exe -fLo setup-devbox.ps1 https://raw.githubusercontent.com/dmontaine/sd4windows/main/sdb_ai/sd64/gplbld/setup-devbox.ps1
#
# and it will clone sd4windows itself.  Run from inside an existing clone it
# notices and leaves it alone.
# ---------------------------------------------------------------------------
#
# WHAT IT CANNOT DO, said here rather than discovered at the end:
#
#   * IT CANNOT CREATE SSH KEYS - and since 23 Aug 2026 that no longer stops
#     it.  Every repository is PUBLIC and is CLONED OVER https, so a machine
#     with no credentials at all sets itself up completely and builds.  The
#     ssh push URL is set afterwards for the two that are pushed to, and a key
#     is wanted only the first time somebody pushes.
#   * IT CANNOT FETCH Projects\GPL.BP.  That tree has NO REMOTE - it is 212
#     files of original ScarletDME BASIC, PROJECT_STATUS.md section 2 calls it
#     "genuinely valuable", and section 7 step 12 worked from it.  A machine
#     built by this script can build and test SD; it cannot do the attribution
#     work section 2 is written around until that tree is copied over by hand.
#   * IT CANNOT CLONE Projects\sdhelp EITHER, and 24 Aug 2026 the owner asked
#     for it anyway: "the documentation process may happen on another computer
#     and I want those resources handy".  It is 30 MB and ~1300 files of
#     OpenQM 2.6.6 and SD help - PDF and HTML, third-party, no remote - so it
#     can be neither cloned nor vendored here (no binaries in this
#     repository).  -SdHelpSource copies it from a path you supply; without
#     one it is REPORTED as a hand-carry item rather than passed over in
#     silence, which is the GPL.BP treatment above and for the same reason.
#
# THE LAYOUT IS LOAD-BEARING, NOT TIDINESS.  sdclilib32\Makefile carries
# "SRCDIR ?= ../sd4windows/sdb_ai/sd64/gplsrc/sdclilib", so the four clones
# MUST be siblings in one directory.  That is why -Root names a parent and the
# repository names are not configurable.
#
# A NOTE ON POWERSHELL, because this project has paid for it twice:
# A FUNCTION RETURNS EVERYTHING IT WRITES TO THE OUTPUT STREAM.  Write-Output
# beside a return yields an ARRAY, and a caller testing the result then gets
# nonsense - it cost two bugs elsewhere in gplbld, one of which made a refusal
# exit 0.  So every function whose value is read below writes with Write-Host.

[CmdletBinding()]
param(
    # The PARENT directory the four repositories become siblings in.
    [string]$Root = (Join-Path $env:USERPROFILE 'Projects'),

    # Where to copy Projects\sdhelp FROM - a USB drive, a share, a pCloud
    # sync folder, or another dev box's Projects\sdhelp.  Omitted, the tree
    # is reported as owed rather than fetched; it has no remote to clone.
    # The archive it unpacks from is "sdhelp_2-6-6 20260221 AM" on pCloud.
    [string]$SdHelpSource = '',

    # Report what is missing and change nothing.
    [switch]$CheckOnly,

    # Skip the closing "make sd", which is the slow part.
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# What a development machine needs.  Every constant here is a fact measured
# from the build rather than a preference - see the comment on each.
# ---------------------------------------------------------------------------

$MsysRoot = 'C:\msys64'
$MsysBash = Join-Path $MsysRoot 'usr\bin\bash.exe'

# PROJECT_STATUS.md section 2.  python-devel and gettext-devel are NOT here -
# both were dropped on 13 Aug 2026 with embedded Python (section 5.15).
# libxcrypt-devel is -lcrypt and libbsd is -lbsd, both in the Makefile's
# L_FLAGS; mingw-w64-ucrt-x86_64-gcc is the NATIVE compiler the client DLL and
# the service wrapper are built with (section 5.3, the two toolchains).
# 23 Aug 26 - MSYS2's OWN git IS NOT IN THIS LIST, and a first draft had it.
# Running -CheckOnly against the reference machine reported it missing - on a
# machine that builds SD, ships installers and passes all 26 verifiers.  So it
# was never a requirement: cloning is done by WINDOWS git from PowerShell, and
# nothing in the Makefile or gplbld/*.py shells out to git at all (checked).  A
# setup script that reports a working machine as incomplete teaches the
# operator to ignore it, which is worse than not checking.
#
# curl and tar STAY: the libsodium step below uses both, and both ship with
# base MSYS2, so they cost nothing to assert and would be a confusing failure
# if a stripped install ever lacked them.
$PacmanPackages = @(
    'gcc', 'make', 'pkgconf', 'libxcrypt-devel', 'libbsd', 'python',
    'mingw-w64-ucrt-x86_64-gcc', 'curl', 'tar',
    # 23 Aug 26 - diffutils, ADDED FROM THE FIRST REAL RUN.  libsodium's
    # configure printed "cmp: command not found" three times and "diff:
    # command not found" once on the owner's laptop, where every other package
    # was already present.  It is not fatal - configure treats a missing cmp as
    # "the files differ" and carries on, and the build finished - but it is a
    # real missing dependency that only shows up as noise, so it was never
    # going to be noticed any other way than by watching a build.
    'diffutils'
)

# NOT PACKAGED FOR THE MSYS2 RUNTIME - only for mingw64/ucrt64/clang64, which
# are ABI incompatible with it.  So it is built from source into /usr/local,
# and the Makefile looks for it there: SODIUM := /usr/local/include,
# LIBSODIUM := /usr/local/lib.  Skipping this step does not fail the configure;
# it fails the LINK, much later, which is why it is checked for explicitly.
$SodiumVersion = '1.0.20'
$SodiumUrl     = "https://download.libsodium.org/libsodium/releases/libsodium-$SodiumVersion-stable.tar.gz"

# The path Inno Setup 6 uses by default, and the one cycle.ps1 tries first.
# It is a STARTING POINT, not the answer - Resolve-Iscc is the answer.
$IsccPath = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'

# The four, and what each is for.  linuxsdclilib is deliberately absent -
# removed from the project 23 Aug 2026, section 2.
# Set by Step-Git, read by Step-Clone and Step-Build.  Initialised FALSE: on a
# machine with no git the clone step must SKIP, not call a command that is not
# there.  That call threw CommandNotFoundException on the first clean-VM run
# and, under $ErrorActionPreference = 'Stop', took the summary down with it.
$script:HaveGit = $false

# CLONE OVER https, PUSH OVER ssh.  Changed 23 Aug 2026, owner's decision,
# before the first clean-VM run so that the run tests the final script.
#
# ALL THREE GitHub REPOSITORIES ARE PUBLIC, so a key was never needed to READ
# them - only to push.  Cloning over git@ meant a machine with no credentials
# skipped sd4windows and sdclilib32, and skipped `make sd` with them, which is
# the one step this script calls the only real test of the environment.  So a
# bare machine could be set up right up to the point that would have proved it.
#
# `Push` is applied with `git remote set-url --push` after the clone, so the
# owner's push path is unchanged and nothing has to be edited by hand
# afterwards.  A machine with no key clones, builds and tests; the key is only
# wanted the first time somebody pushes, and git says so plainly then.
$Repos = @(
    [pscustomobject]@{
        Name = 'sd4windows'
        Url  = 'https://github.com/dmontaine/sd4windows'
        Push = 'git@github.com:dmontaine/sd4windows.git'
        Why  = 'the port, and the client library''s home'
    }
    [pscustomobject]@{
        Name = 'sdb64'
        Url  = 'https://codeberg.org/stringdatabase/sdb64'
        Push = ''      # read-only upstream - nothing here ever pushes to it
        Why  = 'upstream Linux, read-only - the attribution tool'
    }
    [pscustomobject]@{
        Name = 'winsdclilib'
        Url  = 'https://github.com/dmontaine/winsdclilib'
        Push = ''      # already https both ways on the reference machine
        Why  = 'mirror of gplsrc/sdclilib - push to it when the client changes'
    }
    [pscustomobject]@{
        Name = 'sdclilib32'
        Url  = 'https://github.com/dmontaine/sdclilib32'
        Push = 'git@github.com:dmontaine/sdclilib32.git'
        Why  = '32-bit qmclilib.dll; holds no source, SRCDIR points into sd4windows'
    }
)

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

$script:Problems = New-Object System.Collections.ArrayList
$script:Manual   = New-Object System.Collections.ArrayList

function Say([string]$text)  { Write-Host $text }
function Head([string]$text) {
    Write-Host ''
    Write-Host ('== ' + $text + ' ' + ('=' * [Math]::Max(0, 68 - $text.Length)))
}
function Ok([string]$text)   { Write-Host ('  [ok]      ' + $text) }
function Did([string]$text)  { Write-Host ('  [done]    ' + $text) }
function Skip([string]$text) { Write-Host ('  [skipped] ' + $text) }
function Bad([string]$text)  {
    Write-Host ('  [PROBLEM] ' + $text)
    $null = $script:Problems.Add($text)
}
function Hand([string]$text) {
    Write-Host ('  [BY HAND] ' + $text)
    $null = $script:Manual.Add($text)
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# THE COMPILER'S OWN DIRECTORY MUST BE ON PATH INSIDE THE SHELL.  gcc resolves
# by full path, but the subprograms it spawns - cc1.exe - find their DLLs
# through PATH, and without it the build dies with
#   "cc1.exe: error while loading shared libraries: ?: cannot open shared
#    object file"
# which names no file and reads like a broken toolchain.  Cost two builds on
# 23 Aug 2026.  -l gives a login shell, which sets MSYS2's own PATH.
function Invoke-Msys([string]$Command, [int]$TimeoutMinutes = 30) {
    if (-not (Test-Path -LiteralPath $MsysBash)) {
        Bad 'MSYS2 bash is not present, so this step cannot run'
        return $false
    }
    $full = 'export PATH=/usr/bin:/ucrt64/bin:$PATH; ' + $Command
    & $MsysBash -lc $full
    if ($LASTEXITCODE -ne 0) {
        Bad ("MSYS2 command failed (exit $LASTEXITCODE): " + $Command)
        return $false
    }
    return $true
}

function Get-WingetPath {
    $c = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $c) { return '' }
    return $c.Source
}

# RE-READ PATH THE WAY A NEW WINDOW WOULD.  Added 23 Aug 2026 after the first
# clean-VM run died on it.
#
# A process gets its PATH when it starts.  winget installs write the new
# directory into the MACHINE or USER environment in the registry, and every
# window opened afterwards picks it up - but THIS process keeps the copy it
# started with, so a program installed a moment ago is still "not recognized".
#
# THAT IS EXACTLY WHAT KILLED THE FIRST FRESH-MACHINE RUN.  git installed
# fine, the script said so, and then Step-Clone called `git clone` and threw
# CommandNotFoundException - which under $ErrorActionPreference = 'Stop' took
# the whole script down, so the build, the summary and every remaining check
# were lost.  Telling somebody to "re-run in a new window" is not a fix when
# rebuilding the variable is three lines.
function Update-SessionPath {
    $parts = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) | Where-Object { $_ }
    if ($parts.Count -gt 0) { $env:PATH = ($parts -join ';') }
}

function Install-Winget([string]$Id, [string]$Label) {
    if ($CheckOnly) { Hand ("$Label is missing - winget install $Id"); return $false }
    Say ("  installing $Label ...")
    # --silent so it does not open a UI and wait; --accept-* because an
    # unattended install must not stop on a licence prompt.
    winget install --id $Id --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Bad "$Label did not install (winget exit $LASTEXITCODE)"
        return $false
    }
    # BEFORE the caller looks for the program it just installed - see above.
    Update-SessionPath
    Did "$Label installed"
    return $true
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

function Step-Preflight {
    Head 'Preflight'
    Say ("  PowerShell " + $PSVersionTable.PSVersion)
    Say ("  root for the repositories: " + $Root)
    if ($CheckOnly) { Say '  -CheckOnly: nothing will be changed' }

    # ELEVATION IS REQUIRED TO INSTALL AND NOT TO LOOK.  -CheckOnly changes
    # nothing, so demanding admin for it would put the survey - the cheapest
    # thing here, and the one somebody runs first on a strange machine -
    # behind a UAC prompt for no reason.  Found by running it, 23 Aug 2026.
    if (Test-Elevated) {
        Ok 'elevated'
    } elseif ($CheckOnly) {
        Ok 'not elevated - fine, -CheckOnly changes nothing'
    } else {
        Say ''
        Say 'setup-devbox: this needs an ELEVATED PowerShell.'
        Say 'Installing MSYS2 and Inno Setup cannot be done without it, and'
        Say 'stopping now is better than stopping halfway through.'
        Say ''
        Say 'To survey this machine without changing it, add -CheckOnly.'
        exit 2
    }

    $wg = Get-WingetPath
    if ($wg -eq '') {
        Say ''
        Say 'setup-devbox: winget was not found.'
        Say 'It ships with App Installer from the Microsoft Store on Windows 10'
        Say '1809 and later. Install that first, or install MSYS2, Git and Inno'
        Say 'Setup by hand and re-run with everything already present.'
        exit 2
    }
    Ok ('winget at ' + $wg)
}

# FIND A PROGRAM winget HAS JUST INSTALLED, and make plain `git`/`gh` work for
# the rest of this run.  Update-SessionPath covers the normal case; these are
# the fallbacks for an installer that did not write PATH at all, or wrote it
# somewhere this process cannot see.  Returns the full path, or $null.
function Resolve-Tool([string]$Exe, [string[]]$Candidates) {
    $c = Get-Command $Exe -ErrorAction SilentlyContinue
    if ($null -ne $c) { return $c.Source }
    foreach ($p in $Candidates) {
        if (Test-Path -LiteralPath $p) {
            # Callers invoke by NAME, so put the directory on PATH rather than
            # threading a full path through every call site.
            $env:PATH = (Split-Path -Parent $p) + ';' + $env:PATH
            return $p
        }
    }
    return $null
}

$GitCandidates = @(
    'C:\Program Files\Git\cmd\git.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
)
$GhCandidates = @(
    'C:\Program Files\GitHub CLI\gh.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
)

function Step-Git {
    Head 'Git'
    if (Resolve-Tool 'git' $GitCandidates) {
        Ok ('git present - ' + (& git --version))
        $script:HaveGit = $true
        return
    }
    # Return on the install's own verdict rather than falling through.  Under
    # -CheckOnly Install-Winget has already said "git is missing", and the
    # check below would then say "installed but not usable" about an install
    # that never happened - one cause, two lines, which is the defect the ssh
    # clones had (HISTORY, 23 Aug).
    if (-not (Install-Winget 'Git.Git' 'Git for Windows')) { return }

    # Install-Winget has already re-read PATH from the registry, which is what
    # opening a new window does.  This is the second look.
    if (Resolve-Tool 'git' $GitCandidates) {
        Ok ('git is usable in THIS session - ' + (& git --version))
        $script:HaveGit = $true
        return
    }
    Hand 'git installed but cannot be found even after re-reading PATH - re-run this script in a NEW elevated window'
}

# GitHub CLI.  ADDED 23 Aug 2026 ON THE OWNER'S INSTRUCTION.
#
# Recorded because this file's own section 2 argues the other way, and the next
# person reading it should not think the argument was missed.  MSYS2's own git
# was deliberately kept OUT of the pacman list on the grounds that nothing in
# the project uses it, and by that reasoning gh does not belong here either:
# no Makefile, script or build step calls it, and the key can be pasted into
# the GitHub web UI with no tooling at all.
#
# THE OWNER'S CALL OVERRIDES THAT, and it is a reasonable one: the ONE step
# this script cannot do for you is the SSH key, it is the step that stopped the
# first real run dead, and `gh ssh-key add` is the shortest way through it.  A
# setup script that names a tool it does not install - which is exactly what
# this one did until today - is worse than one that installs it.
function Step-Gh {
    Head 'GitHub CLI'
    if (Resolve-Tool 'gh' $GhCandidates) {
        Ok ('gh present - ' + (@(& gh --version)[0]))
        return
    }
    if (-not (Install-Winget 'GitHub.cli' 'GitHub CLI')) { return }
    if (Resolve-Tool 'gh' $GhCandidates) {
        Ok ('gh is usable in THIS session - ' + (@(& gh --version)[0]))
        return
    }
    # Not a problem - nothing in this script needs gh, and the next window will
    # have it.  It matters only for the ssh-key step below.
    Hand 'gh installed but not usable in this session - open a NEW window before using it for the key step'
}

function Step-Msys {
    Head 'MSYS2'
    if (Test-Path -LiteralPath $MsysBash) {
        Ok ('present at ' + $MsysRoot)
        return
    }
    if ($CheckOnly) { Hand 'MSYS2 is missing - winget install MSYS2.MSYS2'; return }

    $null = Install-Winget 'MSYS2.MSYS2' 'MSYS2'
    if (-not (Test-Path -LiteralPath $MsysBash)) {
        # THE PATH IS NOT NEGOTIABLE and this is why it is checked rather than
        # searched for: the MSYS2 runtime derives its root by stripping TWO
        # components from the directory holding msys-2.0.dll, and everything in
        # this project - the Makefile, cycle.ps1, the install layout in section
        # 5.8 - is written around C:\msys64.
        Bad "MSYS2 is not at $MsysRoot after installing. This project requires that exact location"
    }
}

function Step-Packages {
    Head 'MSYS2 packages'
    if (-not (Test-Path -LiteralPath $MsysBash)) { Skip 'no MSYS2 yet'; return }

    $missing = @()
    foreach ($p in $PacmanPackages) {
        & $MsysBash -lc ("pacman -Qi " + $p + " > /dev/null 2>&1")
        if ($LASTEXITCODE -ne 0) { $missing += $p }
    }

    if ($missing.Count -eq 0) {
        Ok ('all ' + $PacmanPackages.Count + ' packages present')
        return
    }
    Say ('  missing: ' + ($missing -join ' '))
    if ($CheckOnly) { Hand ('pacman -S --needed ' + ($missing -join ' ')); return }

    # -Syu, NOT -Sy.  Corrected 23 Aug 2026; the comment here already said
    # -Syu and the code did -Sy, which is not a typo with no consequences.
    #
    # `pacman -Sy` followed by `pacman -S <pkg>` is a PARTIAL UPGRADE: it
    # refreshes the package database without upgrading anything already
    # installed, and then installs new packages built against library versions
    # that are newer than the ones on disk.  On MSYS2, as on any Arch-derived
    # system, that is a documented way to break a working toolchain.
    #
    # AND IT IS MOST DANGEROUS ON EXACTLY THE MACHINES THIS GETS RE-RUN ON.
    # On a fresh machine nothing is installed yet, so there is nothing to be
    # out of step with and -Sy would have been harmless.  The damage case is
    # an EXISTING MSYS2 that is missing one package - which is this repository
    # owner's own build machine, where `diffutils` turned out to be missing.
    Say '  pacman -Syu: this upgrades ALL MSYS2 packages, not just the missing ones.'
    Say '  That is deliberate - installing into a stale tree is what breaks toolchains -'
    Say '  but on a machine that already builds SD it is a real change.'
    $null = Invoke-Msys 'pacman -Syu --noconfirm'
    if (Invoke-Msys ('pacman -S --needed --noconfirm ' + ($missing -join ' '))) {
        Did ('installed ' + ($missing -join ' '))
    }
}

function Step-Sodium {
    Head 'libsodium'
    if (-not (Test-Path -LiteralPath $MsysBash)) { Skip 'no MSYS2 yet'; return }

    & $MsysBash -lc 'test -f /usr/local/lib/libsodium.a -o -f /usr/local/lib/libsodium.dll.a'
    if ($LASTEXITCODE -eq 0) {
        Ok 'built and installed in /usr/local'
        return
    }
    if ($CheckOnly) { Hand 'libsodium is not in /usr/local - it must be built from source'; return }

    Say '  not present - building from source, this takes a few minutes'
    # One shell so the cd survives between commands.  Built in /tmp because
    # nothing afterwards needs the source tree.
    $build = @(
        'set -e',
        'cd /tmp',
        'rm -rf libsodium-stable',
        "curl -fLO $SodiumUrl",
        "tar xzf libsodium-$SodiumVersion-stable.tar.gz",
        'cd libsodium-stable',
        './configure --prefix=/usr/local --disable-dependency-tracking',
        'make -j4',
        'make install'
    ) -join '; '

    if (Invoke-Msys $build) {
        & $MsysBash -lc 'test -f /usr/local/lib/libsodium.a -o -f /usr/local/lib/libsodium.dll.a'
        if ($LASTEXITCODE -eq 0) { Did 'libsodium built into /usr/local' }
        else { Bad 'libsodium build reported success but the library is not in /usr/local/lib' }
    }
}

# WHERE IS ISCC.exe REALLY?  Rewritten 23 Aug 2026 after the first real run.
#
# The old version tested ONE hardcoded path immediately after winget returned,
# and on the owner's laptop it reported "[done] Inno Setup 6 installed" and
# "[PROBLEM] Inno Setup is not at ..." on consecutive lines.  Both of the
# things that can cause that are handled here, because the printout cannot
# tell them apart afterwards:
#
#   - THE INSTALL HAD NOT SETTLED.  winget returns when the installer process
#     exits, which is not always when the files are all in place.  Step-Inno
#     retries for a few seconds rather than deciding on the first look.
#   - IT WENT SOMEWHERE ELSE.  winget falls back to a per-user install when a
#     machine-scope one is refused, and Inno's own path can be changed at
#     install time.  So the REGISTRY is consulted - it is what the installer
#     itself writes, and it is authoritative in a way a guessed path is not.
#
# Inno Setup 6 is a 32-bit application even on x64, so its uninstall key
# normally lives under WOW6432Node; the native view is read too, against a
# future 64-bit build.
function Resolve-Iscc {
    # The canonical path first, so a machine that has it where cycle.ps1 looks
    # resolves to exactly that and nothing below can change the answer.
    if (Test-Path -LiteralPath $IsccPath) { return $IsccPath }

    # HKCU as well as HKLM, confirmed necessary by the first clean-VM run:
    # winget gave that machine a PER-USER Inno install, and a per-user install
    # writes its uninstall key under HKCU.  The LOCALAPPDATA fallback below is
    # what actually caught it there, but the key is the tidier answer and
    # cycle.ps1 now reads the same four.
    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1'
    )
    foreach ($k in $keys) {
        try {
            $loc = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).InstallLocation
        } catch { continue }
        if ([string]::IsNullOrWhiteSpace($loc)) { continue }
        $cand = Join-Path $loc 'ISCC.exe'
        if (Test-Path -LiteralPath $cand) { return $cand }
    }

    # A per-user winget install, which lands here and is invisible to both of
    # the above.
    $userCand = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
    if (Test-Path -LiteralPath $userCand) { return $userCand }

    return $null
}

function Step-Inno {
    Head 'Inno Setup'
    $found = Resolve-Iscc
    if ($found) {
        Ok ('ISCC present at ' + $found)
        if ($found -ne $IsccPath) { Warn-IsccElsewhere $found }
        return
    }
    if ($CheckOnly) { Hand 'Inno Setup 6 is missing - winget install JRSoftware.InnoSetup'; return }

    $null = Install-Winget 'JRSoftware.InnoSetup' 'Inno Setup 6'

    # Not one look - see the header above.  Ten seconds is far longer than the
    # race needs and costs nothing on a machine where it is already there,
    # because that machine never reaches this line.
    for ($i = 0; $i -lt 10; $i++) {
        $found = Resolve-Iscc
        if ($found) { break }
        Start-Sleep -Seconds 1
    }

    if (-not $found) {
        # Not fatal to the BUILD - only to building an installer - so this is a
        # problem rather than a stop.
        Bad ("Inno Setup installed but no ISCC.exe was found, at $IsccPath, " +
             'in the Inno Setup 6 uninstall key, or in a per-user install. ' +
             'cycle.ps1 needs it to build the installer')
        return
    }
    # Install-Winget has already said "Inno Setup 6 installed"; this adds only
    # the part it could not know, which is where ISCC actually landed.
    Say ('  ISCC at ' + $found)
    if ($found -ne $IsccPath) { Warn-IsccElsewhere $found }
}

# ISCC IS SOMEWHERE cycle.ps1 WILL NOT LOOK BY ITSELF.  Not a problem here -
# nothing this script does needs ISCC - but it is a problem the first time
# anybody runs a cycle, and that is a long way from this message, so it is
# stated with the actual path rather than left to be discovered.
function Warn-IsccElsewhere($path) {
    Hand ("ISCC is at $path, not $IsccPath. cycle.ps1 tries the default " +
          'first and then the registry, so it will find this one - but if a ' +
          'cycle ever reports ISCC missing, that is the path it needs')
}

function Step-Ssh {
    Head 'SSH keys - for PUSHING, not for the setup'
    $needSsh = @($Repos | Where-Object { $_.Push -ne '' })
    $keyDir = Join-Path $env:USERPROFILE '.ssh'
    $haveKey = $false
    if (Test-Path -LiteralPath $keyDir) {
        $keys = @(Get-ChildItem -LiteralPath $keyDir -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '^id_(rsa|ecdsa|ed25519)$' })
        if ($keys.Count -gt 0) { $haveKey = $true }
    }

    # THIS STEP NO LONGER BLOCKS ANYTHING, and that is the point of the change
    # on 23 Aug 2026.  The clones are https now, so a machine with no key sets
    # itself up completely - every repository, and `make sd` at the end.  A
    # missing key costs nothing until the first push, which is a thing the
    # operator does deliberately and which git explains clearly by itself.
    #
    # It was a blocker until today: with git@ clone URLs, no key meant no
    # sd4windows, which meant no build, which meant the one step that proves
    # the environment never ran on the machine that most needed proving.

    if ($haveKey) {
        Ok 'a private key is present in ~\.ssh - pushes should work'
        # Presence is not authorisation, and saying so matters: only a real
        # push proves it, and that is a long way from here.
        Say '  (that it is the RIGHT key is not something this can check)'
        return
    }

    Ok 'no SSH key - that does NOT affect this setup'
    Say ('  Everything clones over https and builds without one. A key is wanted')
    Say ('  only to PUSH to: ' + (($needSsh | ForEach-Object { $_.Name }) -join ', '))
    Say '  When you want that:'
    Say '      ssh-keygen -t ed25519 -C "you@example.com"'

    # THIS USED TO NAME `gh` UNCONDITIONALLY WHEN NOTHING INSTALLED IT.  On the
    # reference machine gh happened to be present, so the advice read perfectly
    # well from the one box that would never follow it; on the fresh machine
    # this script exists for it was "gh: command not found" at the exact moment
    # somebody is stuck.  Step-Gh installs it now (owner, 23 Aug 2026), so the
    # gh line is the normal path again - but it is still CHECKED rather than
    # assumed, because a just-installed gh is not on this session's PATH and
    # the install can fail.
    if ($null -ne (Get-Command gh -ErrorAction SilentlyContinue)) {
        Say '      gh ssh-key add ~\.ssh\id_ed25519.pub'
    } else {
        Say '  gh is installed but not on THIS session''s PATH - either open a new'
        Say '  window and use:   gh ssh-key add %USERPROFILE%\.ssh\id_ed25519.pub'
        Say '  or paste the PUBLIC half into https://github.com/settings/keys'
        Say '      type %USERPROFILE%\.ssh\id_ed25519.pub'
    }

    Say '  The clones below go ahead either way.'
}

function Step-Clone {
    Head 'Repositories'
    Say ('  they must be SIBLINGS - sdclilib32\Makefile reads')
    Say ('  SRCDIR ?= ../sd4windows/sdb_ai/sd64/gplsrc/sdclilib')
    Say ''

    # NO git, NO CLONES - and say so rather than calling it.  This is the guard
    # the first clean-VM run needed: without it `git clone` raises
    # CommandNotFoundException, which terminates the whole script under Stop
    # and loses the build, the summary and every remaining check.  A step that
    # cannot run should report and step aside.
    if (-not $script:HaveGit -and -not $CheckOnly) {
        Bad 'git is not usable in this session, so nothing was cloned - see the Git step above'
        return
    }

    if (-not (Test-Path -LiteralPath $Root)) {
        if ($CheckOnly) { Hand ("root does not exist: " + $Root); return }
        $null = New-Item -ItemType Directory -Path $Root -Force
        Did ('created ' + $Root)
    }

    foreach ($r in $Repos) {
        $dest = Join-Path $Root $r.Name
        if (Test-Path -LiteralPath (Join-Path $dest '.git')) {
            Ok ($r.Name.PadRight(14) + '- already cloned')
            continue
        }
        if (Test-Path -LiteralPath $dest) {
            Bad ($dest + ' exists and is not a git repository - left alone')
            continue
        }
        if ($CheckOnly) { Hand ('would clone ' + $r.Name + ' - ' + $r.Why); continue }

        Say ('  cloning ' + $r.Name + ' ...')
        & git clone $r.Url $dest
        if ($LASTEXITCODE -ne 0) {
            # No ssh special case any more - every clone is https, so a failure
            # here is the network or the URL and never a missing credential.
            Bad ($r.Name + ' did not clone (git exit ' + $LASTEXITCODE + ')')
            continue
        }
        Did ($r.Name + ' cloned - ' + $r.Why)

        # PUSH GOES BACK OVER ssh where there is one.  Set here rather than
        # left to the operator: the fetch URL is what makes a bare machine
        # work, and the push URL is what stops that convenience quietly
        # becoming "this clone can no longer push where it used to".
        if ($r.Push -ne '') {
            & git -C $dest remote set-url --push origin $r.Push
            if ($LASTEXITCODE -eq 0) {
                Say ('  ' + ''.PadRight(14) + '  push URL set to ' + $r.Push)
            } else {
                Bad ($r.Name + ': clone succeeded but the ssh push URL could not be set - pushes will go to ' + $r.Url)
            }
        }
    }

    # SECTION 2 RELIES ON origin/dev BEING READABLE WITHOUT THE NETWORK:
    #   git -C ../sdb64 show origin/dev:sd64/<path>
    # A plain clone fetches main only, so this is not optional decoration.
    $sdb64 = Join-Path $Root 'sdb64'
    if (Test-Path -LiteralPath (Join-Path $sdb64 '.git')) {
        & git -C $sdb64 rev-parse --verify --quiet origin/dev > $null
        if ($LASTEXITCODE -eq 0) {
            Ok 'sdb64 origin/dev is fetched'
        } elseif ($CheckOnly) {
            Hand 'sdb64 origin/dev is not fetched - git -C sdb64 fetch origin dev:refs/remotes/origin/dev'
        } else {
            & git -C $sdb64 fetch origin 'dev:refs/remotes/origin/dev'
            if ($LASTEXITCODE -eq 0) { Did 'fetched sdb64 origin/dev' }
            else { Bad 'could not fetch sdb64 origin/dev - section 2 reads it offline' }
        }
    }
}

function Step-Build {
    Head 'Proving it - make sd'
    $sd64 = Join-Path $Root 'sd4windows\sdb_ai\sd64'
    if (-not (Test-Path -LiteralPath (Join-Path $sd64 'Makefile'))) {
        Skip 'sd4windows is not cloned, so there is nothing to build'
        return
    }
    if ($CheckOnly -or $SkipBuild) { Skip 'not building (-CheckOnly or -SkipBuild)'; return }

    # THE BUILD IS THE TEST OF THE ENVIRONMENT.  Nothing else here proves the
    # compiler, libsodium and the two toolchains actually work together, and a
    # machine that cannot build is not set up whatever the checks above said.
    #
    # make -C rather than cd: the Makefile does MAIN := $(shell pwd)/, and -C
    # chdirs before reading it, so pwd is right.
    $posix = (& $MsysBash -lc ("cygpath -u '" + $sd64 + "'")).Trim()
    Say '  building, this takes a few minutes ...'
    if (Invoke-Msys ("make -C '" + $posix + "' sd")) {
        $exe = Join-Path $sd64 'bin\sd.exe'
        if (Test-Path -LiteralPath $exe) {
            Did ('built ' + $exe)
            Ok  'the toolchain works end to end'
        } else {
            Bad 'make reported success but bin\sd.exe is not there'
        }
    }
}

# 24 Aug 26 - owner's instruction: the sdhelp tree must reach a new machine,
# because the documentation work may be done there.  It is not a repository
# and never will be - 30 MB of third-party PDF and HTML with no remote - so
# this copies rather than clones, and says so plainly when it cannot.
#
# THE COUNT IS REPORTED, NOT JUST THE EXISTENCE OF THE DIRECTORY.  An empty
# or half-copied sdhelp\ is the failure this would otherwise call [ok]:
# a bare Test-Path passes on a directory somebody created and never filled.
function Step-SdHelp {
    Head 'sdhelp (documentation resources)'

    $dest = Join-Path $Root 'sdhelp'
    $have = 0
    if (Test-Path -LiteralPath $dest) {
        $have = @(Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue).Count
    }

    if ($have -gt 0) {
        Ok ('sdhelp   - already present, ' + $have + ' file(s) in ' + $dest)
        return
    }

    if ($CheckOnly) {
        Hand ('Projects\sdhelp is missing or empty at ' + $dest +
              ' - re-run with -SdHelpSource <path> to copy it')
        return
    }

    if ($SdHelpSource) {
        if (-not (Test-Path -LiteralPath $SdHelpSource)) {
            Bad ('-SdHelpSource ' + $SdHelpSource + ' does not exist, so nothing was copied')
            return
        }
        $src = @(Get-ChildItem -LiteralPath $SdHelpSource -Recurse -File -ErrorAction SilentlyContinue).Count
        if ($src -eq 0) {
            Bad ('-SdHelpSource ' + $SdHelpSource + ' holds no files - refusing to report an empty copy as done')
            return
        }
        Say ('  copying ' + $src + ' file(s) from ' + $SdHelpSource)
        # robocopy exit codes below 8 are success; it returns 1 for "files copied".
        $null = robocopy $SdHelpSource $dest /E /NFL /NDL /NJH /NJS /R:1 /W:1
        if ($LASTEXITCODE -ge 8) {
            Bad ('robocopy failed with exit ' + $LASTEXITCODE)
            return
        }
        $now = @(Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue).Count
        if ($now -lt $src) {
            Bad ('copied ' + $now + ' of ' + $src + ' file(s) - sdhelp is incomplete')
        } else {
            Ok ('sdhelp   - copied, ' + $now + ' file(s) in ' + $dest)
        }
        return
    }

    Hand ('Projects\sdhelp is NOT obtainable by this script - it has no remote and is 30 MB of third-party PDF/HTML. It is the OpenQM 2.6.6 and SD help set, wanted whenever documentation is written. Copy it from a machine that has it, or re-run this script with -SdHelpSource <path>. The archive is "sdhelp_2-6-6 20260221 AM" on pCloud')
}

function Step-Report {
    Head 'Summary'

    # NAMED, NOT BURIED.  A machine set up by this script can build and test SD
    # and cannot do the attribution work section 2 is written around, and the
    # difference is invisible until somebody needs it.
    Hand 'Projects\GPL.BP is NOT obtainable by this script - it has no remote. 212 files of original ScarletDME BASIC, referenced 9 times in PROJECT_STATUS.md, and section 7 step 12 worked from it. Copy it from a machine that has it'

    Write-Host ''
    if ($script:Problems.Count -eq 0) {
        Say 'No problems.'
    } else {
        Say ('PROBLEMS (' + $script:Problems.Count + '):')
        foreach ($p in $script:Problems) { Say ('  - ' + $p) }
    }

    Write-Host ''
    if ($script:Manual.Count -gt 0) {
        Say ('LEFT FOR A PERSON (' + $script:Manual.Count + '):')
        foreach ($m in $script:Manual) { Say ('  - ' + $m) }
    }

    Write-Host ''
    Say 'Next, on a machine that is fully set up:'
    Say ('  ' + (Join-Path $Root 'sd4windows\sdb_ai\sd64\gplbld\cycle.ps1') + '     (ELEVATED)')
    Say ('  ' + (Join-Path $Root 'sd4windows\sdb_ai\sd64\gplbld\VerifyInstall1.ps1') + ' -ThenElevated -Run <fresh>   (ORDINARY window)')
    Say ''
    Say 'Read PROJECT_STATUS.md before doing anything else in the repository.'
}

# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'setup-devbox - SD for Windows development environment'
Write-Host '====================================================='

# THE SUMMARY IS THE DELIVERABLE, so no step is allowed to take it down with
# it.  23 Aug 2026: on the first clean-VM run an unexpected exception in
# Step-Clone ended the script where it stood - no build, no summary, no list of
# what had been done or was still owed - and the machine WAS most of the way
# set up.  Losing the report is worse than the failure it was reporting.
#
# Preflight is deliberately OUTSIDE this: it decides whether the run may happen
# at all (elevation, winget), and if it exits there is nothing to summarise.
Step-Preflight

foreach ($step in @('Step-Git', 'Step-Gh', 'Step-Msys', 'Step-Packages',
                    'Step-Sodium', 'Step-Inno', 'Step-Ssh', 'Step-Clone',
                    'Step-SdHelp', 'Step-Build')) {
    try {
        & $step
    } catch {
        # Named, not swallowed: the step is identified and the message kept, so
        # this reads as a reported failure rather than a step that did nothing.
        Bad ("$step stopped unexpectedly - " + $_.Exception.Message)
    }
}

Step-Report

Write-Host ''
if ($script:Problems.Count -gt 0) {
    Write-Host ('setup-devbox: finished with ' + $script:Problems.Count + ' problem(s).')
    exit 1
}
Write-Host 'setup-devbox: finished, no problems.'
exit 0
