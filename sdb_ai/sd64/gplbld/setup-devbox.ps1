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
#   * IT CANNOT CREATE SSH KEYS.  Two remotes are git@github.com, and
#     credentials are the operator's to set up.  It detects and reports.
#   * IT CANNOT FETCH Projects\GPL.BP.  That tree has NO REMOTE - it is 212
#     files of original ScarletDME BASIC, PROJECT_STATUS.md section 2 calls it
#     "genuinely valuable", and section 7 step 12 worked from it.  A machine
#     built by this script can build and test SD; it cannot do the attribution
#     work section 2 is written around until that tree is copied over by hand.
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

# Set by Step-Ssh, read by Step-Clone.  Initialised TRUE so that if the ssh
# step is ever skipped or moved, the clones are ATTEMPTED rather than silently
# passed over - a failed clone says so, a skipped one is easy to miss.
$script:HaveSshKey = $true

# The four, and what each is for.  linuxsdclilib is deliberately absent -
# removed from the project 23 Aug 2026, section 2.
$Repos = @(
    [pscustomobject]@{
        Name = 'sd4windows'
        Url  = 'git@github.com:dmontaine/sd4windows.git'
        Why  = 'the port, and the client library''s home'
        Ssh  = $true
    }
    [pscustomobject]@{
        Name = 'sdb64'
        Url  = 'https://codeberg.org/stringdatabase/sdb64'
        Why  = 'upstream Linux, read-only - the attribution tool'
        Ssh  = $false
    }
    [pscustomobject]@{
        Name = 'winsdclilib'
        Url  = 'https://github.com/dmontaine/winsdclilib'
        Why  = 'mirror of gplsrc/sdclilib - push to it when the client changes'
        Ssh  = $false
    }
    [pscustomobject]@{
        Name = 'sdclilib32'
        Url  = 'git@github.com:dmontaine/sdclilib32.git'
        Why  = '32-bit qmclilib.dll; holds no source, SRCDIR points into sd4windows'
        Ssh  = $true
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

function Step-Git {
    Head 'Git'
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $g) {
        Ok ('git present - ' + (& git --version))
        return
    }
    $null = Install-Winget 'Git.Git' 'Git for Windows'
    # PATH in THIS process does not pick up a just-installed program, so the
    # clone step below would still fail.  Say so rather than let it look like
    # a clone problem.
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $g) {
        Hand 'git was installed but is not on PATH in this session - re-run this script in a NEW elevated window to finish'
    }
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

    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1'
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
    Did ('Inno Setup 6 installed - ISCC at ' + $found)
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
    Head 'SSH keys for the git@ remotes'
    $needSsh = @($Repos | Where-Object { $_.Ssh })
    $keyDir = Join-Path $env:USERPROFILE '.ssh'
    $haveKey = $false
    if (Test-Path -LiteralPath $keyDir) {
        $keys = @(Get-ChildItem -LiteralPath $keyDir -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '^id_(rsa|ecdsa|ed25519)$' })
        if ($keys.Count -gt 0) { $haveKey = $true }
    }

    # Step-Clone reads this.  23 Aug 2026, from the first real run: without it
    # the ssh clones are ATTEMPTED anyway and each one fails on its own,
    # turning one cause into three lines in the summary - "no SSH key" under
    # LEFT FOR A PERSON and two separate PROBLEMS underneath it.  Three
    # entries for one missing key reads like three things to fix, and it
    # buries the one problem on that run that was real.
    #
    # IT ALSO STOPS AN INTERACTIVE HANG.  The first ssh clone asks
    # "Are you sure you want to continue connecting (yes/no/[fingerprint])?"
    # for github.com's host key and WAITS.  That prompt is legitimate when a
    # clone can succeed; asking it before a clone that is already doomed means
    # the script sits there for a while and then fails anyway.
    $script:HaveSshKey = $haveKey

    if ($haveKey) {
        Ok 'a private key is present in ~\.ssh'
        # Presence is not authorisation, and saying so matters: the clone is
        # what proves it, and it fails much later.
        Say '  (that it is the RIGHT key is not something this can check - the clone below is the test)'
        Say '  (the first ssh clone asks you to accept github.com''s host key - that is expected)'
        return
    }

    Hand ('no SSH key in ~\.ssh - these will not clone: ' + (($needSsh | ForEach-Object { $_.Name }) -join ', '))
    Say '  Create one and add the public half to GitHub, then re-run:'
    Say '      ssh-keygen -t ed25519 -C "you@example.com"'
    Say '      gh ssh-key add ~\.ssh\id_ed25519.pub      (or paste it in the web UI)'
    Say '  The ssh clones below are SKIPPED rather than attempted - re-running'
    Say '  after the key is in place picks them up.'
}

function Step-Clone {
    Head 'Repositories'
    Say ('  they must be SIBLINGS - sdclilib32\Makefile reads')
    Say ('  SRCDIR ?= ../sd4windows/sdb_ai/sd64/gplsrc/sdclilib')
    Say ''

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

        # No key, no point - Step-Ssh has already said so once, and saying it
        # again per repository is what made one cause look like three.
        if ($r.Ssh -and -not $script:HaveSshKey) {
            Say ('  ' + $r.Name.PadRight(14) + '- skipped, no SSH key (see above)')
            continue
        }

        Say ('  cloning ' + $r.Name + ' ...')
        & git clone $r.Url $dest
        if ($LASTEXITCODE -ne 0) {
            if ($r.Ssh) {
                Bad ($r.Name + ' did not clone. It is an ssh remote - check the key step above')
            } else {
                Bad ($r.Name + ' did not clone (git exit ' + $LASTEXITCODE + ')')
            }
            continue
        }
        Did ($r.Name + ' cloned - ' + $r.Why)
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

Step-Preflight
Step-Git
Step-Msys
Step-Packages
Step-Sodium
Step-Inno
Step-Ssh
Step-Clone
Step-Build
Step-Report

Write-Host ''
if ($script:Problems.Count -gt 0) {
    Write-Host ('setup-devbox: finished with ' + $script:Problems.Count + ' problem(s).')
    exit 1
}
Write-Host 'setup-devbox: finished, no problems.'
exit 0
