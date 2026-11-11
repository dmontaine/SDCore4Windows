# sd-confset.ps1 - the Windows half of SET.CONFIG: change ONE tuning parameter of sd.conf.
#
#   ... -Name CLEANUP -Value 600 [-ConfPath <file>]
#
# Run by SD through !ps_script_out, from gpl.bp SETCONFIG, as SDSYS's ELEVATED helper (the verb is
# SDSYS-only, and C:\ProgramData\SD\sd.conf is closed to anyone else by the installer's
# SecureSysdirs).  Carried 10 Nov 2026 from Linux's sd-elevate conf-set (S.75 A6, the owner's
# "do a6", 26 Oct 2026; Windows RELEASE_1.1 218).  The rules are Linux's, line for line:
#
#   THE NAME is one of the 14 parameters config.c range-checks that this script lists below, with
#   config.c's own range: CLEANUP DHCACHE GRPSIZE LGNWAIT LPTRHIGH LPTRWIDE MAXCALL MAXRLOCK
#   NETREPLY NETWAIT NUMLOCKS RECCACHE SORTMRG USPLIT.  Any other name is refused, with one sentence
#   for a name SD knows (a door, a path, a command, a log or a security setting...) and another for
#   a name it does not (such a line in sd.conf stops SD from starting).
#   THE VALUE is digits only, at most 7, no leading zero, inside the range.
#   THE FILE is read as config.c reads it: '#' and empty lines skipped, a '[' line names the section
#   (up to ']', 32 characters, capitals), a KEY= line counts only in an [sd] section, case
#   sensitive.  The first KEY= line there is replaced, later ones are dropped (config.c would have
#   used the LAST, so a file with two is mended rather than left disagreeing), and when there is none
#   the line is added after the last setting of the last [sd] section.  Comments and every other
#   line are kept byte for byte, with the file's own line end.
#   THE WRITE: nothing is written when the file already says it; otherwise a new file beside it
#   (a fresh random name, created new), then File.Replace, which keeps sd.conf's own ACL and leaves
#   the old file as sd.conf.bak (one generation).  It is read back: exactly one KEY=VALUE line in
#   [sd], every other line as written.
#
# Windows deviations from Linux, both forced: PowerShell rather than bash; and a file holding a
# byte outside printable ASCII is refused (English only, owner 29 Sep 2026: SD writes sd.conf as
# ASCII, and reading such a byte as ASCII would rewrite it as '?').
#
# Output: the first line echoes the inputs really given.  On success the LAST line is
#   SD-CONFSET OK <NAME> <value> <session|restart>[ unchanged]
# and that is the only text a caller may anchor on; a refusal is one "SD-CONFSET ERROR <reason>"
# line.  Exit 0 done, 1 refused or failed.

param(
    [string]$Name = '',
    [string]$Value = '',
    # Overridable for testing.  The default is where the installer puts it.
    [string]$ConfPath = ''
)

$ErrorActionPreference = 'Stop'

function Say([string]$t) { Write-Output ('SD-CONFSET ' + $t) }
function Refuse([string]$t) { Say ('ERROR ' + $t); exit 1 }

# config.c's rangecheck() for the 14, and when a change reaches anyone (tool.config's 'effect')
$Writable = @{
    'CLEANUP'  = @(30, 3600, 'restart')
    'DHCACHE'  = @(0, 1024, 'session')
    'GRPSIZE'  = @(1, 8, 'session')
    'LGNWAIT'  = @(0, 32767, 'restart')
    'LPTRHIGH' = @(10, 32767, 'session')
    'LPTRWIDE' = @(10, 1000, 'session')
    'MAXCALL'  = @(10, 1000000, 'session')
    'MAXRLOCK' = @(0, 100000, 'session')
    'NETREPLY' = @(1, 3600, 'session')
    'NETWAIT'  = @(1, 3600, 'session')
    'NUMLOCKS' = @(1, 32767, 'restart')
    'RECCACHE' = @(0, 32, 'session')
    'SORTMRG'  = @(2, 10, 'session')
    'USPLIT'   = @(0, 1, 'restart')
}

# The other names config.c accepts in [sd] (sdsys\config.table's write=no rows)
$Fixed = @('APIPORT', 'BACKUPDIR', 'CMDSTACK', 'DEADLOCK', 'DEBUG', 'DUMPDIR', 'ERRLOG', 'FDS',
           'FLTDIFF', 'FSYNC', 'GRPDIR', 'INTPREC', 'MAXIDLEN', 'MUSTLOCK', 'NETDIRS', 'NETFILES',
           'NUMFILES', 'NUMUSERS', 'OBJECTS', 'OBJMEM', 'PDUMP', 'PHANTOMS', 'PWDELAY', 'SAFEDIR',
           'SCREENTHEME', 'SDCLIENT', 'SDSYS', 'SH', 'SH1', 'SORTMEM', 'SORTWORK', 'SPOOLER',
           'TEMPDIR', 'TERMINFO', 'USERPOOL', 'USRDIR', 'YEARBASE')

# Why NAME=VALUE may not be written, or '' when it may.  Nothing here touches the disk.
function Test-Setting([string]$k, [string]$v) {
    if ($k -eq '') { return 'no parameter name was given' }
    if ($k -cnotmatch '^[A-Z][A-Z0-9]*$') { return 'the parameter name holds a character that is not a capital letter or a digit: sd.conf spells a parameter in capitals (CLEANUP, not cleanup) and SD does not start when it meets a name it does not know' }
    if ($k.Length -gt 12) { return 'the parameter name is longer than any parameter SD has' }
    if (-not $Writable.ContainsKey($k)) {
        if ($Fixed -ccontains $k) { return "$k is a parameter SD knows, and set.config does not change it (a door, a path or a command, a log or security setting, a size config.c does not check, or one nothing acts on): tool.config says why, and the line to add by hand" }
        return "$k is not a parameter SD knows, so nothing was written (a name SD does not know in sd.conf stops SD from starting)"
    }
    if ($v -eq '') { return "no value was given for $k" }
    if ($v -cnotmatch '^[0-9]+$') { return 'the value must be a whole number written with digits only: no sign, point, space, quote or line break' }
    if ($v.Length -gt 7) { return 'the value has more than 7 digits' }
    if ($v -ne '0' -and $v.StartsWith('0')) { return 'the value must not start with a zero' }
    $n = [int]$v
    $lim = $Writable[$k]
    if ($n -lt $lim[0] -or $n -gt $lim[1]) { return "$v is outside the range $($lim[0]) to $($lim[1]) that SD accepts for $k" }
    return ''
}

# The lines as config.c would see them.  Returns First (the index of the first KEY= line in an [sd]
# section, -1), Drops (the later ones), Count, and After (the index to add after: the last line
# that sets anything in the last [sd] section, or its header; -1 when there is no [sd] section).
function Get-Scan($lines, [string]$k) {
    $first = -1; $after = -1; $count = 0; $insd = $false
    $drops = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line.StartsWith('[')) {
            $nm = $line.Substring(1)
            $e = $nm.IndexOf(']')
            if ($e -ge 0) { $nm = $nm.Substring(0, $e) }
            if ($nm.Length -gt 32) { $nm = $nm.Substring(0, 32) }
            $insd = ($nm.ToUpperInvariant() -ceq 'SD')
            if ($insd) { $after = $i }
            continue
        }
        if (-not $insd) { continue }
        $after = $i
        if ($line.StartsWith($k + '=', [System.StringComparison]::Ordinal)) {
            $count++
            if ($first -lt 0) { $first = $i } else { $drops.Add($i) }
        }
    }
    return [pscustomobject]@{ First = $first; Drops = $drops; Count = $count; After = $after }
}

function Test-Reparse([string]$p) {
    $fi = New-Object System.IO.FileInfo($p)
    return (($fi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

# --- the run -----------------------------------------------------------------

if ($ConfPath -eq '') { $ConfPath = Join-Path $env:ProgramData 'SD\sd.conf' }
Say ("name=$Name value=$Value conf=$ConfPath")

$tmp = ''
try {
    $why = Test-Setting $Name $Value
    if ($why -ne '') { Refuse $why }
    $effect = $Writable[$Name][2]

    if (-not (Test-Path -LiteralPath $ConfPath -PathType Leaf)) { Refuse "$ConfPath is not a regular file" }
    if (Test-Reparse $ConfPath) { Refuse "$ConfPath is not a regular file" }
    $bak = $ConfPath + '.bak'
    if (Test-Path -LiteralPath $bak) {
        if (-not (Test-Path -LiteralPath $bak -PathType Leaf) -or (Test-Reparse $bak)) { Refuse "$bak is not a regular file" }
    }

    $bytes = [System.IO.File]::ReadAllBytes($ConfPath)
    foreach ($b in $bytes) {
        if ($b -eq 0) { Refuse "$ConfPath holds a NUL byte, so it is not rewritten" }
        if ($b -gt 126 -or ($b -lt 32 -and $b -ne 9 -and $b -ne 10 -and $b -ne 13)) { Refuse "$ConfPath holds a byte that is not plain ASCII, so it is not rewritten" }
    }
    $original = [System.Text.Encoding]::ASCII.GetString($bytes)
    $nl = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
    $endsNl = $original.EndsWith($nl)
    $body = if ($endsNl) { $original.Substring(0, $original.Length - $nl.Length) } else { $original }
    $lines = if ($original -eq '') { @() } else { @($body -split [regex]::Escape($nl)) }

    $scan = Get-Scan $lines $Name
    if ($scan.After -lt 0) { Refuse "$ConfPath has no [sd] section, so there is nowhere to put $Name" }

    $setting = $Name + '=' + $Value
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq $scan.First) { $out.Add($setting) }
        elseif ($scan.Drops.Contains($i)) { }
        else { $out.Add($lines[$i]) }
        if ($scan.First -lt 0 -and $i -eq $scan.After) { $out.Add($setting) }
    }
    $newText = ($out -join $nl) + $(if ($endsNl -or $out.Count -gt 0) { $nl } else { '' })

    if ($newText -ceq $original) {
        Say ("OK $Name $Value $effect unchanged")
        exit 0
    }

    $dir = Split-Path -Parent $ConfPath
    $tmp = Join-Path $dir ('sd.conf.' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '.new')
    $fs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $nb = [System.Text.Encoding]::ASCII.GetBytes($newText)
        $fs.Write($nb, 0, $nb.Length)
        $fs.Flush($true)
    } finally { $fs.Dispose() }

    # File.Replace keeps sd.conf's own DACL (the installer's lock) and leaves the old file as .bak
    [System.IO.File]::Replace($tmp, $ConfPath, $bak)
    $tmp = ''

    # READ BACK BEFORE REPORTING SUCCESS
    $after = [System.IO.File]::ReadAllText($ConfPath, [System.Text.Encoding]::ASCII)
    $abody = if ($after.EndsWith($nl)) { $after.Substring(0, $after.Length - $nl.Length) } else { $after }
    $alines = @($abody -split [regex]::Escape($nl))
    $ascan = Get-Scan $alines $Name
    if ($after -cne $newText -or $ascan.Count -ne 1 -or $alines[$ascan.First] -cne $setting) {
        Refuse "$ConfPath does not read back as written (the file as it was is $bak)"
    }
    Say ("OK $Name $Value $effect")
    exit 0
}
catch {
    if ($tmp -ne '' -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    Say ('ERROR ' + $_.Exception.Message)
    exit 1
}
