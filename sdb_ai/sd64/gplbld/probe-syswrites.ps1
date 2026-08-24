# write_probe.ps1 - §7 step 15: WHICH of the eight sdusers:(M) targets does an
# ORDINARY user's SD session actually write?
#
# The ACL question cannot be answered from the ACL.  gcat and pcode were made
# read-only because nothing a user does writes them; the remaining eight are
# open because nobody has checked.  This checks, by hashing every file before
# and after a normal session and diffing.
#
# IT RUNS UNELEVATED, AS GITORLI\don, WHICH IS THE WHOLE POINT.  An elevated
# session would write as Administrator and say nothing about what sdusers needs.
#
# It does not LOGTO SDSYS - that requires elevation by design (section 5.6) and
# is not what an ordinary user does.

$ErrorActionPreference = 'Continue'

$sdExe = 'C:\Program Files\SD\usr\bin\sd.exe'
$roots = [ordered]@{
    'accounts' = 'C:\ProgramData\SD\sdsys\accounts'
    '$map'     = 'C:\ProgramData\SD\sdsys\$map'
    '$ipc'     = 'C:\ProgramData\SD\sdsys\$ipc'
    'messages' = 'C:\ProgramData\SD\sdsys\messages'
    'newvoc'   = 'C:\ProgramData\SD\sdsys\newvoc'
    'bp'       = 'C:\ProgramData\SD\sdsys\bp'
    'cat'      = 'C:\ProgramData\SD\sdsys\cat'
    'sd.conf'  = 'C:\ProgramData\SD\sd.conf'
}

"who am i : $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
"elevated : $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
"sd.exe   : $sdExe"
if (-not (Test-Path $sdExe)) { 'REFUSING: no sd.exe'; exit 2 }
''

function Snapshot {
    $h = @{}
    foreach ($k in $roots.Keys) {
        $p = $roots[$k]
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $files = if ((Get-Item -LiteralPath $p).PSIsContainer) {
            Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
        } else { Get-Item -LiteralPath $p }
        foreach ($f in $files) {
            try {
                $h[$f.FullName] = ('{0}:{1}' -f $f.Length,
                                   (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash)
            } catch {
                $h[$f.FullName] = 'UNREADABLE'
            }
        }
    }
    return $h
}

function Invoke-SD([string[]]$commands) {
    # the canonical shape from the verifiers: leading newline, TERM re-applied
    # after every LOGTO (LOGIN:201-209 resets it), OFF last.
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    # 24 Aug 26 - NO BOM DOWN THE PIPE.  PowerShell 5.1's default $OutputEncoding
    # put a UTF-8 BOM in front of the first command, SD read it as a verb and
    # answered "<BOM> is not in your VOC", so command 1 was eaten every run.
    # 24 Aug 26 - THE LEADING BOM IS HARMLESS BY CONSTRUCTION, and fighting it
    # cost more than it was worth.  PowerShell 5.1 puts a UTF-8 BOM in front of
    # the first byte it pipes to a native exe; $OutputEncoding does not remove
    # it, local or $global:, and routing through cmd.exe's "<" broke the feed
    # entirely (0 of 9 verbs echoed).
    #
    # $body BEGINS WITH A NEWLINE, so the BOM lands on that empty first line and
    # SD answers "<BOM> is not in your VOC" ONCE, before any real command. It
    # cannot eat a verb. The caller asserts that below rather than trusting it:
    # every command must echo, and the BOM message must appear at most once.
    $out = $body | & $sdExe 2>&1
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

'== snapshot BEFORE =='
$before = Snapshot
"   $($before.Count) file(s) hashed"

# --- the workload: what an ordinary user actually does in a session
'== running an ordinary user session =='
$stamp = 'ZZW' + (Get-Random -Minimum 1000 -Maximum 9999)
$cmds = @(
    'WHO', 'COUNT VOC', "CREATE.FILE $stamp", "COUNT $stamp",
    'LISTU', 'DATE', 'WHERE', 'LIST.LOCKS',
    # 24 Aug 26 - A WIDENED PASS WAS TRIED AND HUNG, AND IS NOT IN THIS LIST.
    # It added PHANTOM, SETPTR, SELECT/SAVE.LIST/GET.LIST to cover the write
    # paths these nine verbs do not reach.  It never returned: two sd.exe
    # processes were left behind (the session and its phantom, both owned by
    # the invoking user, cleared with Stop-Process and no elevation) and no
    # output was flushed.  Same family as the LOGIN/TERM pagination hang - a
    # prompt reading a stdin that has already been closed.
    #
    # SO PHANTOM AND THE SPOOLER ARE NOT MEASURED HERE, and the table this
    # feeds says so rather than implying nine verbs covered everything.  It
    # changes no recommendation: PHANTOM writes its command into $ipc
    # (sd.c:55) and $ipc is the one directory already staying writable.
    "DELETE.FILE $stamp"
)
$out = Invoke-SD $cmds
$out -split "`n" | ForEach-Object { "   | $_" }

'== snapshot AFTER =='
$after = Snapshot
"   $($after.Count) file(s) hashed"

''
'== WHAT CHANGED =='
$changed = @()
foreach ($k in $after.Keys) {
    if (-not $before.ContainsKey($k))      { $changed += "CREATED  $k" }
    elseif ($before[$k] -ne $after[$k])    { $changed += "MODIFIED $k" }
}
foreach ($k in $before.Keys) {
    if (-not $after.ContainsKey($k))       { $changed += "DELETED  $k" }
}

if ($changed.Count -eq 0) {
    'nothing under the eight targets changed'
} else {
    $changed | Sort-Object | ForEach-Object { "  $_" }
}

''
'== per-target verdict =='
foreach ($k in $roots.Keys) {
    $p = $roots[$k]
    $hits = @($changed | Where-Object { $_ -like "*$p*" }).Count
    '{0,-10} {1}' -f $k, $(if ($hits) { "WRITTEN ($hits file(s))" } else { 'untouched' })
}

''
# THE NULL CASE, TESTED RATHER THAN ASSERTED.  CLAUDE.md: a measurement that
# could have run against nothing must test for that and say so.  "untouched"
# from a session whose verbs never executed is not evidence of anything.
'== did each command actually run? =='
$ran = 0
foreach ($c in $cmds) {
    $seen = [bool]($out -match [regex]::Escape($c))
    if ($seen) { $ran++ }
    '{0,-22} {1}' -f $c, $(if ($seen) { 'echoed' } else { 'NOT SEEN' })
}
# at most ONE "not in your VOC" - the BOM's own line.  Two would mean a verb
# was eaten, which is the thing that actually matters.
$bomHits = @([regex]::Matches($out, 'is not in your VOC')).Count
$bom     = ($bomHits -gt 1)
$created = -not ($out -match ('No VOC record found for ' + $stamp))
''
"commands echoed : $ran of $($cmds.Count)"
"'not in VOC'   : $bomHits  (1 = the BOM's own line; >1 means a verb was eaten)"
"BOM ate a verb  : $bom      (must be False)"
"CREATE.FILE took: $created  (must be True)"
"output length   : $($out.Length) chars"
if ($ran -lt $cmds.Count -or $bom -or -not $created) {
    ''
    'REFUSING THE RESULT: the session did not run in full, so "untouched" above is NOT evidence.'
    exit 1
}
''
'SESSION RAN IN FULL - the per-target verdict above is evidence.'
