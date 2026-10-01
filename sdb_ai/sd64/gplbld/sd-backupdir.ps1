# sd-backupdir.ps1 - the Windows half of SET.BACKUP.DIRECTORY: the directory BACKUP.ACCOUNT and
# RESTORE.ACCOUNT use when they are not given one.
#
#   ... -Mode Get                  print the saved directory, if there is one
#   ... -Mode Set -Path <dir>      create it if necessary, prove it can be written to, save it
#
# Run by SD through !ps_script_out, from gpl.bp ACC_OS_BAKDIR, as SDSYS's ELEVATED helper (the verbs
# are SDSYS-only here, and C:\ProgramData\SD\sd.conf is closed to anyone else).  RELEASE_1.1 116;
# owner's ruling, 1 Oct 2026:
# "a new command set.backup.directory that creates (if necessary) and makes persistent the backup
# path through the config file, so it need not be typed in every backup and restore command").
# Exit 0 done, 1 refused or failed.
#
# THE SAVED VALUE IS ONE LINE OF sd.conf:  BACKUPDIR=<full Windows path>.  It is read from the file
# at every use rather than from SD's memory, so SET.BACKUP.DIRECTORY takes effect without a
# restart.  gplsrc/config.c ACCEPTS the key and stores nothing: its parser ends in "Unrecognised
# configuration parameter", which stops SD starting, so a build without that branch would not start
# on a file carrying this line.
#
# On success the LAST line is "SD-BACKUPDIR <GET|SET> OK <path>" (or "SD-BACKUPDIR GET NONE"), and
# that is the only text a caller may anchor on; a refusal is one "SD-BACKUPDIR ERROR <reason>"
# line.  Every run first echoes the inputs it was really given (the mode, the path, the file).
#
# ***sd.conf IS READ AND WRITTEN AS BYTES, CRLF AND ASCII PRESERVED.***  Same reasoning as
# api-listener.ps1: Set-Content would rewrite it in the ANSI code page and round trips have
# corrupted tracked files here before.  Only the BACKUPDIR line changes; everything else is
# compared before and after, and the original is put back if it does not read back.
#
# ENGLISH ONLY (owner, 29 Sep 2026): a path with anything outside printable ASCII is refused by
# name rather than half-supported, so a file this script writes is always plain ASCII.

param(
    [Parameter(Mandatory = $true)] [ValidateSet('Get', 'Set')] [string]$Mode,
    [string]$Path = '',
    # Overridable for testing.  The default is where the installer puts it: this script is in the
    # program directory and sd.conf is in the data tree, which is not beside it.
    [string]$ConfPath = ''
)

$ErrorActionPreference = 'Stop'

function Say([string]$t) { Write-Output ('SD-BACKUPDIR ' + $t) }

# Why a path cannot be saved, or '' when it can.  Nothing here touches the disk.
function Test-BackupPath([string]$p) {
    if ($p -eq '') { return 'no directory was given' }
    if ($p -notmatch '^[\x20-\x7E]+$') { return 'the path must be plain ASCII' }
    if ($p -ne $p.Trim()) { return 'the path starts or ends with a space' }
    if ($p -match '[*?"<>|]') { return 'the path holds a character Windows does not allow in a name' }
    if ($p -notmatch '^([A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+)') { return 'the path must be a full path, such as C:\Backups' }
    if ($p.Length -gt 240) { return 'the path is longer than 240 characters' }
    return ''
}

# The file's text as lines, and which line end it uses, so the same one is written back.
function Split-ConfText([string]$text) {
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    return [pscustomobject]@{ Nl = $nl; Lines = @($text -split [regex]::Escape($nl)) }
}

# CASE-SENSITIVE and at the start of the line, as gplsrc/config.c reads it.  The first one wins.
function Get-BackupDirLine($lines) {
    foreach ($l in $lines) {
        if ($l -clike 'BACKUPDIR=*') { return $l.Substring(10) }
    }
    return ''
}

# The same lines with the first BACKUPDIR= line replaced, or one added at the end - before the
# final empty element when the file ended with a newline, so it still does.
function Set-BackupDirLine($lines, [string]$value) {
    $out  = New-Object System.Collections.Generic.List[string]
    $done = $false
    foreach ($l in $lines) {
        if ((-not $done) -and ($l -clike 'BACKUPDIR=*')) { $out.Add('BACKUPDIR=' + $value); $done = $true }
        else { $out.Add($l) }
    }
    if (-not $done) {
        if ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.Insert($out.Count - 1, 'BACKUPDIR=' + $value) }
        else { $out.Add('BACKUPDIR=' + $value) }
    }
    return ,@($out)
}

# Every line that is not a BACKUPDIR line, in order: what must not change.
function Get-OtherLines($lines) {
    return ,@($lines | Where-Object { -not ($_ -clike 'BACKUPDIR=*') })
}

# --- the run -----------------------------------------------------------------

if ($ConfPath -eq '') { $ConfPath = Join-Path $env:ProgramData 'SD\sd.conf' }
Say ("mode=$Mode path=$Path conf=$ConfPath")

try {
    if (-not (Test-Path -LiteralPath $ConfPath -PathType Leaf)) {
        Say ('ERROR ' + $ConfPath + ' does not exist')
        exit 1
    }
    $original = [System.IO.File]::ReadAllText($ConfPath, [System.Text.Encoding]::ASCII)
    $conf     = Split-ConfText $original

    if ($Mode -eq 'Get') {
        $dir = Get-BackupDirLine $conf.Lines
        if ($dir -eq '') { Say 'GET NONE' }
        else             { Say ('GET OK ' + $dir) }
        exit 0
    }

    # --- Set -----------------------------------------------------------------
    $why = Test-BackupPath $Path
    if ($why -ne '') { Say ('ERROR ' + $why); exit 1 }

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3 -and $full.EndsWith('\')) { $full = $full.TrimEnd('\') }
    $why = Test-BackupPath $full
    if ($why -ne '') { Say ('ERROR ' + $why); exit 1 }

    if (Test-Path -LiteralPath $full -PathType Leaf) { Say ('ERROR ' + $full + ' is a file, not a directory'); exit 1 }
    [void][System.IO.Directory]::CreateDirectory($full)
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { Say ('ERROR ' + $full + ' could not be created'); exit 1 }

    # PROVE IT CAN BE WRITTEN TO.  A saved directory that cannot take a file would make every
    # later backup fail far from here; a read-only share or a missing right is found now.
    $probe = Join-Path $full ('.sdbackup-probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        [System.IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force
    } catch {
        Say ('ERROR cannot write a file in ' + $full + ': ' + $_.Exception.Message)
        exit 1
    }

    $newLines = Set-BackupDirLine $conf.Lines $full
    $newText  = $newLines -join $conf.Nl
    [System.IO.File]::WriteAllText($ConfPath, $newText, [System.Text.Encoding]::ASCII)

    # READ BACK BEFORE REPORTING SUCCESS: the saved value is the one asked for, and every other
    # line is as it was.  A file that does not read back is put back as it was.
    $after = Split-ConfText ([System.IO.File]::ReadAllText($ConfPath, [System.Text.Encoding]::ASCII))
    $ok = ((Get-BackupDirLine $after.Lines) -ceq $full) -and
          (((Get-OtherLines $after.Lines) -join '|') -ceq ((Get-OtherLines $conf.Lines) -join '|'))
    if (-not $ok) {
        [System.IO.File]::WriteAllText($ConfPath, $original, [System.Text.Encoding]::ASCII)
        Say ('ERROR ' + $ConfPath + ' did not read back as written; it was put back as it was')
        exit 1
    }
    Say ('SET OK ' + $full)
    exit 0
}
catch {
    Say ('ERROR ' + $_.Exception.Message)
    exit 1
}
