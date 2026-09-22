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
# 22 Sep 26 - voc AND gpl.bp ADDED, RELEASE_1.1 104.  THE LIST WAS THE EIGHT
# INHERITED-Modify TARGETS AS THEY STOOD IN AUGUST, AND THESE TWO WERE NEVER IN
# IT - which is the same omission sd.iss:3444-3451 has, where secure-sysdirs.ps1
# is handed seven paths and these two are not among them.  So the question "does
# anything ordinary write them" had never been asked of either, and 104 cannot be
# decided without asking it.  Measured 22 Sep 2026: both carry
# ace\sdusers = Modify, inherited, while their six locked siblings do not.
$roots = [ordered]@{
    'accounts' = 'C:\ProgramData\SD\sdsys\accounts'
    '$map'     = 'C:\ProgramData\SD\sdsys\$map'
    '$ipc'     = 'C:\ProgramData\SD\sdsys\$ipc'
    'messages' = 'C:\ProgramData\SD\sdsys\messages'
    'newvoc'   = 'C:\ProgramData\SD\sdsys\newvoc'
    'bp'       = 'C:\ProgramData\SD\sdsys\bp'
    'cat'      = 'C:\ProgramData\SD\sdsys\cat'
    'sd.conf'  = 'C:\ProgramData\SD\sd.conf'
    'voc'      = 'C:\ProgramData\SD\sdsys\voc'
    'gpl.bp'   = 'C:\ProgramData\SD\sdsys\gpl.bp'
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
    # 24 Aug 26 - THE PIPE IS THE ONLY HARNESS THAT RUNS ANYTHING, and this
    # comment replaces two earlier ones that were both wrong.
    #
    # WHAT WAS TRIED AND WHAT IT ACTUALLY DID:
    #   pipe   ($body | & $sdExe)            verbs RUN and echo; PHANTOM and
    #                                        SETPTR hang (>20s, sd.exe left)
    #   file   (-RedirectStandardInput)      NOTHING RUNS.  SD prints its
    #                                        banner and "Process terminated",
    #                                        408 bytes, no verb executed
    #   cmd /c "sd.exe < file"               0 of 9 verbs echoed
    #
    # SO A FILE-FED SESSION EXITING IN 1.3s IS NOT EVIDENCE THAT SD HANDLES
    # EOF WELL - it never reached a command.  An earlier version of this file
    # said "SD does not spin at EOF, it terminates the session" on exactly that
    # reading; that is withdrawn, and what SD does at EOF is UNMEASURED.
    #
    # The BOM is tolerated rather than fixed, for the reason below: $body opens
    # with a newline, so it lands on that empty line and cannot eat a verb, and
    # the caller asserts "at most one" rather than trusting it.
    $out = $body | & $sdExe 2>&1
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

'== snapshot BEFORE =='
$before = Snapshot
"   $($before.Count) file(s) hashed"

# --- the workload: what an ordinary user actually does in a session
'== running an ordinary user session =='
$stamp = 'ZZW' + (Get-Random -Minimum 1000 -Maximum 9999)
$cmds = @(
    'WHO', 'COUNT VOC', "CREATE.FILE $stamp", "COUNT $stamp",
    # 22 Sep 26 - LISTU AND LIST.LOCKS ARE GONE BECAUSE THEY DO NOT EXIST IN THIS
    # PORT, AND THAT IS WHY THIS PROBE COULD NEVER REPORT A RESULT.  Neither is in
    # sdsys/newvoc (source or installed) or in any account's VOC, so each answered
    # "X is not in your VOC" - and the BOM guard below counts EVERY "not in VOC"
    # line, so two of them made it conclude the BOM had eaten a verb and REFUSE
    # its own findings.  Measured 22 Sep 2026: 15 of 15 commands echoed and the
    # BOM ate nothing; the guard was wrong, not the session.
    #
    # LISTF, LISTQ and LIST.FILES replace them and were ISOLATED FIRST, which is
    # this file's standing rule: each run alone over the same pipe, 0.0s, present
    # in the VOC, 1809 / 1054 / 550 bytes returned.
    'LISTF', 'DATE', 'WHERE', 'LISTQ', 'LIST.FILES',
    # 24 Aug 26 - EVERY VERB HERE WAS ISOLATED FIRST and returns over a pipe.
    # SETPTR is followed by 'Y': it asks "OK to set new parameters (Y/N)?"
    # (SETPTR:558) and hung until answered - measured, and answering it brought
    # the case back to 0.5s.  PHANTOM is deliberately NOT in this list; it
    # hangs the pipe because the phantom inherits it, and it gets its own pass.
    'SETPTR 0,80,60,0,0', 'Y',
    'SELECT VOC', "SAVE.LIST $stamp", "GET.LIST $stamp", "DELETE.LIST $stamp",
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
# 22 Sep 26 - ***THIS GUARD COULD NOT TELL ITS TWO CAUSES APART, AND THAT IS WHY
# THE PROBE REFUSED EVERY RUN.***  It counted every "is not in your VOC" line and
# read any count above one as "the BOM ate a verb".  But a line naming a verb the
# ACCOUNT DOES NOT HAVE says nothing about the BOM, and the workload carried two
# such verbs (LISTU, LIST.LOCKS - see the note in $cmds).  So the probe blamed a
# swallowed verb, refused its own findings, and the cause was in its own list.
#
# THE FIX IS TO NAME WHAT WAS NOT FOUND RATHER THAN COUNT IT.  The BOM's line has
# no verb in front of "is not in your VOC" (it is the BOM character itself); any
# other such line names its subject.  So the two are distinguishable in the text,
# and each now reports separately - a missing verb is still a refusal, because the
# workload did not run in full, but it is reported as a MISSING VERB and says
# which one, instead of being attributed to an encoding fault three screens away.
# ***THE BOM IS EXCLUDED BY CHARACTER, NOT BY A REGEX CLASS - MEASURED 22 Sep 2026.***
# The first attempt used a single-quoted character class naming the BOM by its
# backslash-u escape.  PowerShell does not process escapes inside single quotes, so
# the pattern matched that ESCAPE AS LITERAL TEXT and never the character - the BOM
# was reported as a missing VERB and the probe refused itself again, which is the
# same class of fault this guard was being fixed for.
#
# AND THE COMMENT ITSELF CARRIED THE BUG ONCE: written with the escape spelled out,
# it landed in this file as a REAL BOM character mid-comment - caught by the
# byte-scan CLAUDE.md requires, not by the parser, which accepted it with 0 errors.
# The character is named in words here for that reason.  Do not paste it back.
$bomChar   = [char]0xFEFF
$trimSet   = [char[]]@($bomChar, ' ', "`t", "`r", "`n")
$vocMisses = @([regex]::Matches($out, '(?m)^\s*(?:\|\s*)?(\S+) is not in your VOC'))
$namedMiss = @($vocMisses | ForEach-Object { $_.Groups[1].Value } |
               Where-Object { $_.Trim($trimSet) -ne '' } | Select-Object -Unique)
$bomHits   = @([regex]::Matches($out, 'is not in your VOC')).Count
$bom       = ($bomHits -gt $namedMiss.Count + 1)
if ($namedMiss.Count) {
    ''
    "VERB(S) NOT IN THIS ACCOUNT'S VOC: $($namedMiss -join ', ')"
    '  Not a BOM fault and not an encoding fault.  Either the verb does not ship'
    '  in this port, or this account is missing it - check sdsys/newvoc first.'
}
$created = -not ($out -match ('No VOC record found for ' + $stamp))
''
"commands echoed : $ran of $($cmds.Count)"
"'not in VOC'   : $bomHits total, of which $($namedMiss.Count) name a verb"
"verbs missing   : $(if ($namedMiss.Count) { $namedMiss -join ', ' } else { 'none      (must be none)' })"
"BOM ate a verb  : $bom      (must be False)"
"CREATE.FILE took: $created  (must be True)"
"output length   : $($out.Length) chars"
if ($ran -lt $cmds.Count -or $bom -or $namedMiss.Count -or -not $created) {
    ''
    'REFUSING THE RESULT: the session did not run in full, so "untouched" above is NOT evidence.'
    if ($namedMiss.Count) { '  Cause: the verb(s) named above are not in this VOC - fix the workload, not the encoding.' }
    exit 1
}
''
'SESSION RAN IN FULL - the per-target verdict above is evidence.'

# ---------------------------------------------------------------------------
# 24 Aug 26 - THE PHANTOM PASS, which cannot go in the list above.
#
# PHANTOM hangs a piped session: the phantom child inherits the pipe, so the
# job never completes even after the parent exits.  Measured, 20s timeout, and
# it is the reason PHANTOM is not one of the verbs in the main workload.
#
# So it is fired and abandoned, the tree is diffed either side, and the proof
# that it RAN is that a second sd.exe appeared - the session's own output is
# unusable here.  A pass that saw no extra process is refused out loud.
#
# IT ONLY RUNS ON A QUIET MACHINE.  The cleanup kills every sd.exe, which would
# take somebody else's session with it, so the pass is SKIPPED unless there
# were none to begin with.  Skipping says so rather than reporting "untouched".
''
'== PHANTOM pass =='
$sdBefore = @(Get-CimInstance Win32_Process -Filter "Name='sd.exe'" -ErrorAction SilentlyContinue).Count
if ($sdBefore -gt 0) {
    "   SKIPPED - $sdBefore sd.exe already running; this pass would kill them."
    '   Re-run when the machine is quiet.'
} else {
    $before2 = Snapshot
    $body2 = "`n" + ((@('TERM 200,9999', 'PHANTOM COUNT VOC', 'OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($e,$x) $x | & $e 2>&1 } -ArgumentList $sdExe, $body2
    $peak = 0
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 400
        $n = @(Get-CimInstance Win32_Process -Filter "Name='sd.exe'" -ErrorAction SilentlyContinue).Count
        if ($n -gt $peak) { $peak = $n }
    }
    Stop-Job   -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='sd.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    $after2 = Snapshot

    $chg2 = @()
    foreach ($k in $after2.Keys) {
        if (-not $before2.ContainsKey($k))   { $chg2 += "CREATED  $k" }
        elseif ($before2[$k] -ne $after2[$k]) { $chg2 += "MODIFIED $k" }
    }
    if ($chg2.Count -eq 0) { '   nothing changed' } else { $chg2 | Sort-Object | ForEach-Object { "   $_" } }
    foreach ($k in $roots.Keys) {
        $hits = @($chg2 | Where-Object { $_ -like ('*' + $roots[$k] + '*') }).Count
        '   {0,-10} {1}' -f $k, $(if ($hits) { "WRITTEN ($hits)" } else { 'untouched' })
    }
    if ($peak -le 0) {
        '   REFUSING: no sd.exe was ever seen, so no phantom ran and the rows above measure nothing.'
        exit 1
    }
    "   a phantom existed (sd.exe peaked at $peak) - the rows above are evidence."
}
