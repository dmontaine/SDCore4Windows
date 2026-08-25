# ssh-preflight.ps1 - may SD install on this machine at all?
# PROJECT_STATUS.md 5.9 and 7 step 3.  Owner's ruling, 25 Aug 2026.
#
#   powershell -File ssh-preflight.ps1 -ReasonFile C:\path\reason.txt
#   powershell -File ssh-preflight.ps1            report to stdout, change nothing
#
# Exit 0  clear to install
#      1  REFUSE - this machine has an ssh server SD does not own, or one it
#         owns whose configuration somebody else has written
#      2  COULD NOT DETERMINE - also a refusal, see the null-case note below
#
# NOTHING HERE CHANGES ANYTHING.  It reads the service registry, one TCP table
# and two files.  It runs from InitializeSetup, before the wizard is drawn and
# before a single file is written, which is the only place a refusal costs the
# user nothing.
#
# ---------------------------------------------------------------------------
# WHY SD REFUSES RATHER THAN COPING.  Owner, 25 Aug 2026: "I would actually
# prefer that SD refused to install if another ssh server is installed.  It
# adds a layer of unpredictability.  If we support only the windows ssh server,
# then we know what it is that is being used and we have control over how it is
# configured."  And on a Microsoft server somebody has already configured: "I
# lean toward refusing in both cases because the pre-existing configuration
# could defeat our security.  If the user wants to change our security policy
# after the fact, that is not on us."
#
# IT CLOSES A HOLE THAT WAS LIVE, NOT ONLY A TIDINESS PROBLEM.  sd.iss asked
# "is Microsoft's OpenSSH present" and called the answer "is there an ssh
# server".  On a machine running Bitvise or freeSSHd those are different
# questions: SD concluded there was no server, installed Windows OpenSSH, and
# it could not bind port 22 because the other server already held it.  SD's
# whole access path was then broken and nothing in the install said so.
#
# AND THE EXISTING GUARD WAS NARROWER THAN THE THREAT.  allow-ssh-groups.ps1's
# second refusal tests only AllowGroups / AllowUsers / DenyGroups / DenyUsers.
# It does NOT look for Match or ForceCommand - and SD inserts its own block
# BEFORE the first Match, so a pre-existing
#
#     Match Group developers
#         ForceCommand none
#
# sits after SD's block and overrides SD's ForceCommand for those users.  An
# account confined to sdsshonly then lands at a PowerShell prompt, which is the
# 21 Aug 2026 failure arriving through somebody else's configuration.
#
# ---------------------------------------------------------------------------
# A FALSE REFUSAL IS THE WORSE FAILURE, AND THE FIRST DRAFT COMMITTED ONE.
# Run on the repository owner's own machine - Microsoft's server, SD installed,
# nothing wrong with it - the first version exited 2 and would have refused the
# install.  Get-Process().Path cannot read a SYSTEM-owned process without
# elevation, so port 22's owner came back "(path unavailable)" and the script
# called that "cannot determine".
#
# TWO THINGS CAME OUT OF THAT AND BOTH ARE STRUCTURAL:
#
#   1. THE SERVICE SCAN RUNS FIRST and the port check uses what it learned.  If
#      the process holding port 22 is called sshd and the registered sshd
#      service is Microsoft's, that is Microsoft's server - no path lookup, no
#      elevation, no guess.
#   2. ELEVATION IS REPORTED rather than assumed.  InitializeSetup is elevated,
#      so the installer never meets the unelevated case; a person running this
#      by hand does, and should be told why a path is missing rather than shown
#      a refusal they cannot act on.
#
# THE NULL CASE IS STILL A REFUSAL, DELIBERATELY.  If sshd_config_default is
# missing, or the service registry cannot be read, this exits 2 rather than 0.
# A check that measured nothing must not read as a pass - PROJECT_STATUS.md's
# instrument rule - and the whole point of this script is that the machine is
# knowable.  What changed is that "cannot determine" now means the instrument
# genuinely failed, not that it was pointed at something it had no right to
# read.
#
# EVERY REFUSAL NAMES WHAT IT FOUND - service name, image path, the offending
# directive.  A refusal a user cannot act on is a bug report waiting to happen.

param(
    [string]$ReasonFile = ''
)

$ErrorActionPreference = 'Continue'

$MsSshDir  = Join-Path $env:SystemRoot 'System32\OpenSSH'
$MsSshd    = Join-Path $MsSshDir 'sshd.exe'
$LiveCfg   = Join-Path $env:ProgramData 'ssh\sshd_config'
$StockCfg  = Join-Path $MsSshDir 'sshd_config_default'

$SdBegin   = '# --- BEGIN SD ssh-only model - PROJECT_STATUS.md 5.6.2 ---'
$SdEnd     = '# --- END SD ssh-only model ---'

$reasons = New-Object System.Collections.ArrayList
$verdict = 0

function Refuse([string]$text) {
    if (-not $script:reasons.Contains($text)) { $null = $script:reasons.Add($text) }
    if ($script:verdict -lt 1) { $script:verdict = 1 }
}
function Blocked([string]$text) {
    if (-not $script:reasons.Contains($text)) { $null = $script:reasons.Add($text) }
    $script:verdict = 2
}
function Say([string]$text) { Write-Output $text }

function IsMicrosoftPath([string]$p) {
    if (-not $p) { return $false }
    return ($p -ilike ($MsSshDir + '\*')) -or ($p -ieq $MsSshDir)
}

$elevated = ([Security.Principal.WindowsPrincipal] `
             [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Say 'ssh-preflight: checking whether this machine has an ssh server SD does not own.'
Say ('  Windows'' own ssh server would be at : ' + $MsSshd)
Say ('  present                            : ' + (Test-Path -LiteralPath $MsSshd))
Say ('  running elevated                   : ' + $elevated)
if (-not $elevated) {
    Say '  NOTE: without elevation the full path of a system process cannot be read.'
    Say '        The service scan below is used instead, which needs no elevation.'
}

# ---------------------------------------------------------------------------
# 1.  WHAT ssh SERVICES ARE INSTALLED, running or not.  This runs FIRST because
#     the port check below depends on it - see the note in the header.
#
#     Port 22 free today and taken tomorrow is still a machine SD cannot
#     predict, so a stopped server counts.
#
#     Matched on the IMAGE PATH, not on a list of product names: a name list is
#     out of date the moment somebody ships a new server.  Microsoft's own
#     ssh-agent lives in the same directory as sshd.exe, so excluding that whole
#     directory keeps it out of this without naming it.
# ---------------------------------------------------------------------------
Say ''
Say '== ssh services installed on this computer =============================='
$sshdServiceIsMicrosoft = $false
$foundAny = 0
try {
    foreach ($k in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop)) {
        $img = (Get-ItemProperty -LiteralPath $k.PSPath -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
        if (-not $img) { continue }
        if ($img -notmatch '(?i)ssh') { continue }

        # Strip quotes and arguments so what is compared is a path.
        $bin = $img.Trim()
        if ($bin.StartsWith('"')) { $bin = ($bin -split '"')[1] }
        else                      { $bin = ($bin -split ' ')[0] }
        $bin = [Environment]::ExpandEnvironmentVariables($bin) -replace '^\\\?\?\\', ''

        $foundAny++
        $mine = IsMicrosoftPath $bin
        Say ('  ' + $k.PSChildName + '  ->  ' + $bin + '   ' +
             $(if ($mine) { '(ships with Windows)' } else { '(NOT part of Windows)' }))

        if ($k.PSChildName -ieq 'sshd' -and $mine) { $sshdServiceIsMicrosoft = $true }

        if (-not $mine) {
            Refuse ('An ssh service that is not part of Windows is installed on this ' +
                    'computer: "' + $k.PSChildName + '" at ' + $bin + '. SD supports only ' +
                    'the OpenSSH server that ships with Windows, so that it knows how the ' +
                    'server is configured.')
        }
    }
    if ($foundAny -eq 0) { Say '  none' }
} catch {
    Blocked ('The list of installed Windows services could not be read, so SD cannot tell ' +
             'whether another ssh server is installed. Windows said: ' + $_.Exception.Message)
}

# ---------------------------------------------------------------------------
# 2.  WHO HOLDS PORT 22.  Port 22 is exclusive: whoever has it, SD's server
#     cannot also have it.  This is also the only check that sees a server
#     which is not installed as a Windows service at all.
# ---------------------------------------------------------------------------
Say ''
Say '== port 22 =============================================================='
$listeners = @()
try {
    $listeners = @(Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction Stop)
} catch {
    # An EMPTY table is a legitimate answer.  A failure to read it is not.
    if ($_.Exception.Message -notmatch 'No matching') {
        Blocked ('The list of listening ports could not be read, so SD cannot tell whether ' +
                 'another ssh server is already using port 22. Windows said: ' +
                 $_.Exception.Message)
    }
}

if ($listeners.Count -eq 0) {
    Say '  nothing is listening on port 22'
} else {
    foreach ($l in $listeners) {
        $proc = $null
        $path = ''
        try {
            $proc = Get-Process -Id $l.OwningProcess -ErrorAction Stop
            if ($proc.Path) { $path = $proc.Path }
        } catch { }
        $pname = if ($proc) { $proc.ProcessName } else { '' }

        if ($path) {
            Say ('  ' + $l.LocalAddress + ':22 held by ' + $pname + '  ' + $path)
            if (-not (IsMicrosoftPath $path)) {
                Refuse ('Another ssh server is already using port 22 on this computer: ' +
                        $pname + ' (' + $path + '). Windows'' own OpenSSH server, which SD ' +
                        'requires, cannot use port 22 at the same time.')
            }
        }
        elseif ($pname -ieq 'sshd' -and $sshdServiceIsMicrosoft) {
            # THE FALLBACK THAT STOPS THE FALSE REFUSAL.  No path, but the
            # process is sshd and the only registered sshd service is the one
            # that ships with Windows.  That is Microsoft's server.
            Say ('  ' + $l.LocalAddress + ':22 held by sshd  (path needs elevation; matched to ' +
                 'the Windows sshd service instead)')
        }
        elseif ($pname) {
            Say ('  ' + $l.LocalAddress + ':22 held by ' + $pname + '  (path unavailable)')
            Refuse ('Something other than Windows'' own ssh server is using port 22 on this ' +
                    'computer: ' + $pname + '. Windows'' OpenSSH server, which SD requires, ' +
                    'cannot use port 22 at the same time.')
        }
        else {
            Say ('  ' + $l.LocalAddress + ':22 held by an unknown process')
            Blocked ('Something is using port 22 but SD could not find out what it is, so it ' +
                     'cannot tell whether that is Windows'' own ssh server or another one.')
        }
    }
}

# ---------------------------------------------------------------------------
# 3.  HAS ANYBODY ALREADY CONFIGURED THE WINDOWS SERVER.  Compared against
#     sshd_config_default, on EFFECTIVE DIRECTIVES ONLY - the stock file is 88
#     lines and only FOUR of them do anything (measured 25 Aug 2026):
#
#         AuthorizedKeysFile      .ssh/authorized_keys
#         Subsystem       sftp    sftp-server.exe
#         Match Group administrators
#                 AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
#
#     Comparing whole files would refuse on nothing more than a Windows update
#     rewording a comment.  Comparing directives is stable.
#
#     DO NOT REPLACE THIS WITH "does the file contain a Match block".  THE
#     STOCK FILE SHIPS ONE, so that test refuses every machine on earth.
#
#     SD'S OWN BLOCK IS EXCLUDED, or every upgrade would refuse to install over
#     the last one.  Verified 25 Aug 2026 on a machine with SD installed: with
#     the block removed, the live file's directives matched stock exactly.
# ---------------------------------------------------------------------------
Say ''
Say '== has anyone configured the Windows ssh server ========================='

function Get-Directives([string]$path) {
    $out = New-Object System.Collections.ArrayList
    $inOurs = $false
    foreach ($line in (Get-Content -LiteralPath $path -ErrorAction Stop)) {
        $t = $line.Trim()
        if ($t -eq $SdBegin) { $inOurs = $true;  continue }
        if ($t -eq $SdEnd)   { $inOurs = $false; continue }
        if ($inOurs) { continue }
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $null = $out.Add(($t -replace '\s+', ' '))   # tabs and spaces compare equal
    }
    return $out
}

if (-not (Test-Path -LiteralPath $LiveCfg)) {
    Say ('  no sshd_config at ' + $LiveCfg + ' yet - nothing has configured a server here')
} elseif (-not (Test-Path -LiteralPath $StockCfg)) {
    Blocked ('SD compares this computer''s ssh configuration against the copy Windows ships, ' +
             'and that copy is missing from ' + $StockCfg + '. Without it SD cannot tell ' +
             'whether the configuration has been changed.')
} else {
    try {
        $live  = Get-Directives $LiveCfg
        $stock = Get-Directives $StockCfg
        Say ('  effective directives - stock: ' + $stock.Count + ', this machine: ' +
             $live.Count + '   (SD''s own block excluded)')
        $extra   = @($live  | Where-Object { $stock -notcontains $_ })
        $missing = @($stock | Where-Object { $live  -notcontains $_ })
        foreach ($e in $extra)   { Say ('    added:   ' + $e) }
        foreach ($m in $missing) { Say ('    removed: ' + $m) }
        if ($extra.Count -gt 0 -or $missing.Count -gt 0) {
            $detail = ''
            if ($extra.Count -gt 0)   { $detail += ' Added: ' + ($extra -join '; ') + '.' }
            if ($missing.Count -gt 0) { $detail += ' Removed: ' + ($missing -join '; ') + '.' }
            Refuse ('The Windows ssh server on this computer has already been configured by ' +
                    'somebody, and SD will not install over settings it did not write, because ' +
                    'they can change who may connect and what happens when they do.' + $detail)
        } else {
            Say '  unchanged from the copy Windows ships'
        }
    } catch {
        Blocked ('This computer''s ssh configuration could not be read, so SD cannot tell ' +
                 'whether it has been changed. Windows said: ' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
Say ''
Say '== verdict ============================================================='
if ($verdict -eq 0) {
    Say '  ssh-preflight: CLEAR - no other ssh server, and nothing has configured this one.'
} elseif ($verdict -eq 1) {
    Say '  ssh-preflight: REFUSE'
} else {
    Say '  ssh-preflight: CANNOT DETERMINE - treated as a refusal, see the note in this file.'
}
foreach ($r in $reasons) { Say ('   - ' + $r) }

if ($ReasonFile) {
    # UTF-8 WITHOUT A BOM, WRITTEN DELIBERATELY THIS WAY.  sd.iss reads this
    # with LoadStringFromFile, which hands back an AnsiString: PowerShell's
    # "-Encoding UTF8" prepends a byte-order mark in 5.1, and those three bytes
    # would arrive as visible rubbish at the front of the refusal the user is
    # shown.  Set-Content has no no-BOM option in 5.1, so write it directly.
    try {
        [System.IO.File]::WriteAllText(
            $ReasonFile,
            (($reasons -join [Environment]::NewLine) + [Environment]::NewLine),
            (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        Say ('  (could not write the reason file: ' + $_.Exception.Message + ')')
    }
}

exit $verdict
