# api-listener.ps1 - turn the SD API listener on or off in sd.conf.
# PRE_RELEASE_FIXES 78.
#
#   powershell -File api-listener.ps1 -Show     report, change nothing
#   powershell -File api-listener.ps1 -On       set APIPORT
#   powershell -File api-listener.ps1 -Off      comment APIPORT out
#
# Exit 0 the file now says what was asked, 1 it could not be written, 2 the
# question could not be answered - the file is missing, unreadable, or carries
# neither form of the line.
#
# WHY THIS EXISTS.  "remote.api on|local|off" (gpl.bp/REMOTEAPI) is the verb;
# this is the half of it that edits a file.  The verb is a thin wrapper on
# purpose: a script can be parse-checked, byte-checked and run on its own,
# which BASIC embedded in a verb cannot, and this file's neighbours all follow
# the same split - install-ssh.ps1, ssh-firewall.ps1, api-firewall.ps1.
#
# IT IS THE LISTENER, NOT THE FIREWALL, AND THOSE ARE THE TWO AXES.  APIPORT
# decides whether SD opens a socket at all; api-firewall.ps1 decides who may
# reach it.  Keeping them in separate scripts is what lets "remote.api local"
# exist - listener on, firewall shut - which is the state PRE_RELEASE 75
# removed from the installer and the owner ruled back in here on 30 Aug 2026.
#
# THE PORT ONLY OPENS AT START-UP.  gplbld/stage.py:499 records why this is a
# real edit and not a runtime switch: "open_api_listener() returns -1 for 'no
# listener' when the port is <= 0", read once as SD starts.  So every change
# here needs an SD restart, and the caller is responsible for saying so.
#
# ***CRLF AND ASCII, BOTH MEASURED RATHER THAN ASSUMED.***  The installed
# sd.conf is 4714 bytes with 85 CR and 85 LF, no BOM, no byte outside ASCII -
# checked on the live file 30 Aug 2026.  Set-Content would rewrite that in the
# system's ANSI codepage and Get-Content/Set-Content round trips have corrupted
# tracked files in this repository before, so this reads and writes bytes with
# [System.IO.File] and rejoins with an explicit CRLF.
#
# ***THE MATCH IS CASE-SENSITIVE ON PURPOSE, TO AGREE WITH stage.py.***
# stage.py:538 selects the active line with Python's `l.strip() == 'APIPORT=4243'`,
# which is case-sensitive; if this script accepted "apiport=4243" it would
# report a state stage.py's own assertion would not, and the two would disagree
# about the same file.  PowerShell's -eq is case-INSENSITIVE by default, so the
# -c forms are used throughout and that is not decoration.

param(
    [switch]$On,
    [switch]$Off,
    [switch]$Show,

    # Overridable for testing.  The default is where the installer puts it, and
    # is derived the same way every other shipped script locates the install.
    [string]$ConfPath = ''
)

$ErrorActionPreference = 'Stop'

$ACTIVE    = 'APIPORT=4243'
$COMMENTED = '# APIPORT=4243'

if ($ConfPath -eq '') {
    $ConfPath = Join-Path $env:ProgramData 'SD\sd.conf'
}

function Say([string]$t) { Write-Output ("api-listener: " + $t) }

# EVERY RUN ECHOES ITS REAL INPUTS.  CLAUDE.md's instrument rule: a verdict with
# no evidence of what was measured is not a result.
Say ("file   : " + $ConfPath)
Say ("action : " + $(if ($On) { 'On' } elseif ($Off) { 'Off' } elseif ($Show) { 'Show' } else { '(none given)' }))

if (-not $On -and -not $Off -and -not $Show) {
    Say 'one of -On, -Off or -Show is required'
    exit 2
}
if ($On -and $Off) {
    Say '-On and -Off are contradictory'
    exit 2
}

if (-not (Test-Path -LiteralPath $ConfPath)) {
    Say 'the file does not exist, so there is nothing to read or change'
    exit 2
}

try {
    $text = [System.IO.File]::ReadAllText($ConfPath, [System.Text.Encoding]::ASCII)
} catch {
    Say ('the file could not be read: ' + $_.Exception.Message)
    exit 2
}

# LINE-WISE, FOR stage.py's REASON.  Its own comment says the first version
# tested "APIPORT_LINE in out" and the commented-out replacement CONTAINS that
# string, so a substring test cannot tell the two states apart.
$nl    = [char]13 + [char]10
$lines = $text -split "`r`n", 0, 'SimpleMatch'

$activeIdx    = @()
$commentedIdx = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    $t = $lines[$i].Trim()
    if ($t -ceq $ACTIVE)    { $activeIdx    += $i }
    if ($t -ceq $COMMENTED) { $commentedIdx += $i }
}

Say ("before : active=" + $activeIdx.Count + " commented=" + $commentedIdx.Count)

# ***THE NULL CASE IS REFUSED OUT LOUD.***  A file carrying neither form is one
# this script does not understand, and editing it would be guesswork.  Reporting
# "done" after changing nothing is the exact failure CLAUDE.md's instrument rule
# is about.
if ($activeIdx.Count -eq 0 -and $commentedIdx.Count -eq 0) {
    Say ("neither '" + $ACTIVE + "' nor '" + $COMMENTED + "' appears as a whole line - refusing rather than guessing")
    exit 2
}

if ($Show) {
    if ($activeIdx.Count -gt 0) { Say 'state  : ON - SD opens the API listener when it next starts' }
    else                        { Say 'state  : OFF - SD opens no API socket at all' }
    exit 0
}

$wantOn = [bool]$On

if ($wantOn -and $activeIdx.Count -gt 0) {
    Say 'already ON - nothing to change'
    exit 0
}
if ((-not $wantOn) -and $activeIdx.Count -eq 0) {
    Say 'already OFF - nothing to change'
    exit 0
}

# ONE LINE MOVES, AND IT IS THE FIRST.  A file with several is already odd; the
# count is reported above so the caller can see it, and touching only one keeps
# the change reversible by eye.
if ($wantOn) {
    $i = $commentedIdx[0]
    $lines[$i] = $ACTIVE
} else {
    $i = $activeIdx[0]
    $lines[$i] = $COMMENTED
}
Say ("editing line " + ($i + 1))

try {
    [System.IO.File]::WriteAllText($ConfPath, ($lines -join $nl), [System.Text.Encoding]::ASCII)
} catch {
    Say ('the file could not be written: ' + $_.Exception.Message)
    exit 1
}

# ***READ BACK BEFORE REPORTING SUCCESS.***  The same rule CRED_SET learned the
# hard way on 30 Aug 2026 (PRE_RELEASE 68): a write that reported success can
# still leave a file the reader cannot use, and this one decides whether SD
# opens a socket.  Unlike CRED_SET's case this process can always read what it
# just wrote - sd.conf is not ACL'd away from it - so the check is done here.
try {
    $after = [System.IO.File]::ReadAllText($ConfPath, [System.Text.Encoding]::ASCII)
} catch {
    Say ('written, but it could not be read back: ' + $_.Exception.Message)
    exit 1
}

$afterActive = @($after -split "`r`n", 0, 'SimpleMatch' | Where-Object { $_.Trim() -ceq $ACTIVE })
Say ("after  : active=" + $afterActive.Count)

if ($wantOn -and $afterActive.Count -ne 1) {
    Say 'the file does not read back as ON'
    exit 1
}
if ((-not $wantOn) -and $afterActive.Count -ne 0) {
    Say 'the file does not read back as OFF'
    exit 1
}

if ($wantOn) { Say 'the API listener is ON when SD is next started' }
else         { Say 'the API listener is OFF when SD is next started' }
exit 0
