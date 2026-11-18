# test-sysdirlock-units.ps1 - is every entry of sdsys, and the sdsys folder
# itself, either locked by the installer or left open on purpose?
#
#   powershell -ExecutionPolicy Bypass -File test-sysdirlock-units.ps1
#
# Exit 0 pass, 1 a check failed, 2 the check measured nothing.
# NO INSTALL, NO ELEVATION, NO RUN TOKEN.  Free tier.
#
# RELEASE_1.1 293 (14 Nov 2026, Linux parity: there sdsys is 755 and only errlog,
# prt, dumps and $ipc are group writable).  On the VM an ordinary account could
# create files in C:\ProgramData\SD\sdsys and 20 entries in it inherited sdusers
# Modify.  sd.iss SecureSysdirs now locks the fifteen that nothing ordinary writes
# (LockSysdirNames), creates errlog, then locks the folder with -KeepChildren.
#
# WHAT IT CHECKS, statically, against sd.iss and secure-sysdirs.ps1:
#   L1  every name in $Locked is in SecureSysdirs' LockSysdirNames list
#   L2  no name in $Open is in that list (locking $ipc breaks every session)
#   L3  SecureSysdirs locks {#DataDir}\sdsys with LockKeepChildrenPath
#   L4  LockKeepChildrenPath passes -KeepChildren
#   L5  errlog is created (SaveStringToFile) BEFORE the folder is locked
#   L6  secure-sysdirs.ps1's -KeepChildren grants sdusers (RX) and
#       (OI)(CI)(IO)(RX) and no other sdusers ACE on the folder, and gives
#       $ipc, prt, errlog, dumps and $hold their own Modify first (18 Nov 26,
#       Linux S.268: a new child of sdsys is read-only to sdusers)
#   L7  if an installed tree exists, every entry in it is in one class below;
#       a name in none of them is a new entry nobody decided about
#   L9  stacks (SDSYS's command history, made at runtime by CPROC) is created
#       BEFORE LockSysdirNames, which refuses a missing path (RELEASE_1.1 301)
#   L10 (17 Nov 26, P-2914) docs\admin, the administrator's documentation for the
#       AI line, is locked AFTER LockSysdirNames (which locks docs) with
#       LockAdminOnlyPath, which passes -AdminOnly, and secure-sysdirs.ps1's
#       -AdminOnly grants SYSTEM and Administrators and no sdusers ACE
#   L11 (17 Nov 26, found on the fresh install with icacls) SDSYS's own
#       examples.bp and examples.bp.out, which LOAD.EXAMPLES makes AFTER
#       SecureSysdirs, are locked by LockSdsysExamples, each only when it exists,
#       called after LoadExamples - start.default's pattern (L8)
# Then MUTANTS: each is a changed copy of the text IN MEMORY (the live files
# are never written), and the matching check must go red on it.

$ErrorActionPreference = 'Stop'

# The classes.  Fixed: SecureSysdirs' own variables.  Elsewhere: their own
# secure-*.ps1 or [Code] step.  Open: written by ordinary sessions.
$Locked = @('syscom','terminfo','terminfo.src','helptext','dir_dict','licence','contrib',
            'agent-pack','bp.out','pcode.out','stacks','examples','docs',
            'dict.dic','voc.dic','$map.dic','accounts.dic','$hold','$hold.dic')
# 14 Nov 26 - start.default is NOT in the staged tree (SET.START.DEFAULT writes it after SecureSysdirs); it is locked by
# LockStartDefault once it exists.  In the early list it made secure-sysdirs.ps1 exit 2 and LockSysdirNames stop (check L8).
# 17 Nov 26 - examples.bp and examples.bp.out the same way: LOAD.EXAMPLES makes them after SecureSysdirs (check L11).
$LockedLate = @('start.default','examples.bp','examples.bp.out')
$Fixed  = @('accounts','$map','messages','newvoc','bp','cat','voc',
            'voc_removed','voc_removed.saved','config.table','voc_template')
$Elsewhere = @('audit','dumps','pstmp','batch.jobs','batch.jobs.dic','gcat','gpl.bp.out','bin','$cred')
$Open   = @('$ipc','errlog','prt')   # 14 Nov 26: $hold and $hold.dic locked too (Linux 755, mail 17:35)

$iss    = Join-Path $PSScriptRoot 'sd.iss'
$script = Join-Path $PSScriptRoot 'secure-sysdirs.ps1'
Write-Output "sd.iss            : $iss"
Write-Output "secure-sysdirs.ps1: $script"
foreach ($f in @($iss, $script)) {
    if (-not (Test-Path -LiteralPath $f)) { Write-Output "NO TREE: $f is missing"; exit 2 }
}
$issText    = [IO.File]::ReadAllText($iss)
$scriptText = [IO.File]::ReadAllText($script)

function Get-Body([string]$text, [string]$head) {
    $i = $text.IndexOf($head)
    if ($i -lt 0) { return '' }
    $rest = $text.Substring($i + $head.Length)
    $m = [regex]::Match($rest, '(?m)^(function|procedure) ')
    if ($m.Success) { return $rest.Substring(0, $m.Index) }
    return $rest
}

function Get-LockList([string]$body) {
    $m = [regex]::Match($body, '(?s)LockSysdirNames\(Ps, Script,(.*?), Code\);')
    if (-not $m.Success) { return @() }
    $joined = (([regex]::Matches($m.Groups[1].Value, "'([^']*)'")) | ForEach-Object { $_.Groups[1].Value }) -join ''
    return @($joined -split '/' | Where-Object { $_ -ne '' })
}

# Each check returns '' for a pass or the reason it failed.
function Test-All([string]$issT, [string]$scrT) {
    $r = [ordered]@{}
    $body = Get-Body $issT 'function SecureSysdirs: String;'
    $list = Get-LockList $body
    $miss = @($Locked | Where-Object { $list -notcontains $_ })
    $r['L1'] = $(if ($list.Count -eq 0) { 'no LockSysdirNames list found in SecureSysdirs' }
                 elseif ($miss.Count) { 'not locked: ' + ($miss -join ' ') } else { '' })
    $bad = @($Open | Where-Object { $list -contains $_ })
    $r['L2'] = $(if ($list.Count -eq 0) { 'no list to check' }
                 elseif ($bad.Count) { 'an open entry is locked: ' + ($bad -join ' ') } else { '' })
    $rootSet  = $body.IndexOf("Root := ExpandConstant('{#DataDir}\sdsys');")
    $rootLock = $body.IndexOf('LockKeepChildrenPath(Ps, Script, Root, Code)')
    $r['L3'] = $(if ($rootSet -ge 0 -and $rootLock -gt $rootSet) { '' } else { 'the sdsys folder is not locked with LockKeepChildrenPath' })
    $kc = Get-Body $issT 'function LockKeepChildrenPath('
    $r['L4'] = $(if ($kc -match '-KeepChildren''') { '' } else { 'LockKeepChildrenPath does not pass -KeepChildren' })
    $mk = $body.IndexOf('SaveStringToFile(ErrLog')
    $el = $body.IndexOf("ErrLog := ExpandConstant('{#DataDir}\sdsys\errlog');")
    $r['L5'] = $(if ($el -ge 0 -and $mk -gt $el -and $rootLock -gt $mk) { '' } else { 'errlog is not created before the folder is locked' })
    $kb = [regex]::Match($scrT, "(?s)if \(\`$KeepChildren\) \{.*?\`$grants = @\((.*?')\)")
    if (-not $kb.Success) { $r['L6'] = 'no -KeepChildren grant list in secure-sysdirs.ps1' }
    else {
        $g = @([regex]::Matches($kb.Groups[1].Value, "'(sdusers:[^']*)'") | ForEach-Object { $_.Groups[1].Value })
        # 18 Nov 26 (Linux S.268): the folder hands down READ only; the places sessions write keep their own Modify.
        $want = @('sdusers:(RX)', 'sdusers:(OI)(CI)(IO)(RX)')
        $wl = [regex]::Match($scrT, "foreach \(\`$w in @\('\`$ipc', 'prt', 'errlog', 'dumps', '\`$hold'\)\)")
        $r['L6'] = $(if (($g.Count -eq 2) -and ($g -contains $want[0]) -and ($g -contains $want[1]) -and $wl.Success -and
                         ($scrT.IndexOf("'sdusers:(OI)(CI)(M)'") -ge 0)) { '' }
                     else { 'sdusers grants are: ' + ($g -join ' ') + $(if (-not $wl.Success) { '; the writable places are not granted their own Modify' } else { '' }) }) }
    # L8: a name the installer writes AFTER SecureSysdirs is not in the early list (the lock script refuses a missing path and the
    # loop stops at the first failure), and is locked after the step that writes it.
    $early = @($LockedLate | Where-Object { $list -contains $_ })
    $fn = Get-Body $issT 'function LockStartDefault: String;'
    $iSet = $issT.IndexOf('StartMsg := SetStartDefault;')
    $iLock = $issT.IndexOf('StartMsg := StartMsg + LockStartDefault;')
    $r['L8'] = $(if ($early.Count) { 'a late-written name is in the early list: ' + ($early -join ' ') }
                 elseif (($fn -notmatch "sdsys\\start\.default") -or ($fn -notmatch 'if not FileExists\(Target\) then')) { 'LockStartDefault does not lock start.default only when it exists' }
                 elseif (($iSet -lt 0) -or ($iLock -le $iSet)) { 'LockStartDefault is not called after SetStartDefault' } else { '' })
    $sk = $body.IndexOf('ForceDirectories(Stacks)')
    $sv = $body.IndexOf("Stacks := ExpandConstant('{#DataDir}\sdsys\stacks');")
    $sl = $body.IndexOf('LockSysdirNames(Ps, Script,')
    $r['L9'] = $(if ($sv -ge 0 -and $sk -gt $sv -and $sl -gt $sk) { '' } else { 'stacks is not created before LockSysdirNames' })
    # L10: docs\admin, administrators only, after docs itself is locked.
    $dv = $body.IndexOf("DocsAdmin := ExpandConstant('{#DataDir}\sdsys\docs\admin');")
    $dl = $body.IndexOf('LockAdminOnlyPath(Ps, Script, DocsAdmin, Code)')
    $ao = Get-Body $issT 'function LockAdminOnlyPath('
    $ab = [regex]::Match($scrT, "(?s)\} elseif \(\`$AdminOnly\) \{.*?\`$grants = @\((.*?')\)")
    $r['L10'] = $(if (-not ($list -contains 'docs')) { 'docs is not in the LockSysdirNames list' }
                  elseif (-not ($sl -ge 0 -and $dv -gt $sl -and $dl -gt $dv)) { 'docs\admin is not locked with LockAdminOnlyPath after LockSysdirNames' }
                  elseif ($ao -notmatch '-AdminOnly''') { 'LockAdminOnlyPath does not pass -AdminOnly' }
                  elseif (-not $ab.Success) { 'no -AdminOnly grant list in secure-sysdirs.ps1' }
                  elseif ($ab.Groups[1].Value -match 'sdusers') { 'the -AdminOnly grants name sdusers: ' + $ab.Groups[1].Value }
                  elseif (($ab.Groups[1].Value -notmatch [regex]::Escape("'*S-1-5-18:(OI)(CI)(F)'")) -or ($ab.Groups[1].Value -notmatch [regex]::Escape("'*S-1-5-32-544:(OI)(CI)(F)'"))) { 'the -AdminOnly grants lack SYSTEM or Administrators' }
                  else { '' })
    # L11: SDSYS's examples.bp and examples.bp.out, locked after LoadExamples, each only when it exists.
    $ex = Get-Body $issT 'function LockSdsysExamples: String;'
    $iLe = $issT.IndexOf('ExamplesMsg := LoadExamples;')
    $iLx = $issT.IndexOf('ExamplesMsg := ExamplesMsg + LockSdsysExamples;')
    $r['L11'] = $(if ($ex -eq '') { 'there is no LockSdsysExamples' }
                  elseif (($ex -notmatch "'examples\.bp/examples\.bp\.out'") -or ($ex -notmatch 'if DirExists\(Target\) then') -or ($ex -notmatch 'LockOsUsersPath\(Ps, Script, Target, Code\)')) { 'LockSdsysExamples does not lock examples.bp and examples.bp.out only when each exists' }
                  elseif (($iLe -lt 0) -or ($iLx -le $iLe)) { 'LockSdsysExamples is not called after LoadExamples' } else { '' })
    return $r
}

$fail = 0
$live = Test-All $issText $scriptText
$body = Get-Body $issText 'function SecureSysdirs: String;'
Write-Output ("LockSysdirNames list read from sd.iss: " + ((Get-LockList $body) -join ' '))
foreach ($k in $live.Keys) {
    if ($live[$k] -eq '') { Write-Output "  [PASS] $k" } else { Write-Output "  [FAIL] $k : $($live[$k])"; $fail++ }
}

# L7: the installed tree, when there is one.
$tree = 'C:/ProgramData/SD/sdsys'
if (Test-Path -LiteralPath $tree) {
    $names = @(Get-ChildItem -LiteralPath $tree -Force | ForEach-Object { $_.Name })
    $all = $Locked + $LockedLate + $Fixed + $Elsewhere + $Open
    $new = @($names | Where-Object { $all -notcontains $_ })
    Write-Output "  installed tree $tree : $($names.Count) entries"
    if ($names.Count -eq 0) { Write-Output '  [FAIL] L7 : the installed tree listed nothing'; $fail++ }
    elseif ($new.Count) { Write-Output ('  [FAIL] L7 : in no class (decide and add): ' + ($new -join ' ')); $fail++ }
    else { Write-Output '  [PASS] L7 every installed entry is in a class' }
} else {
    Write-Output "  [SKIP] L7 : no installed tree at $tree"
}

# Mutants: each must turn its check red.
$mutants = @(
    @{ n='drop agent-pack from the list';      k='L1'; t='iss'; a="'agent-pack/bp.out/pcode.out/stacks/' +"; b="'bp.out/pcode.out/stacks/' +" }
    @{ n='drop stacks from the list';          k='L1'; t='iss'; a="'agent-pack/bp.out/pcode.out/stacks/' +"; b="'agent-pack/bp.out/pcode.out/' +" }
    @{ n='drop examples from the list';        k='L1'; t='iss'; a="'examples/' +"; b="'' +" }     # 16 Nov 26, S.261
    @{ n='stacks not created';                 k='L9'; t='iss'; a='ForceDirectories(Stacks)'; b='{ForceDirectories}(Stacks)' }
    @{ n='start.default back in the early list'; k='L8'; t='iss'; a="'agent-pack/bp.out/pcode.out/stacks/' +"; b="'start.default/agent-pack/bp.out/pcode.out/stacks/' +" }
    @{ n='start.default never locked after its step'; k='L8'; t='iss'; a='StartMsg := StartMsg + LockStartDefault;'; b='StartMsg := StartMsg + LockStartDefaultX;' }
    @{ n='start.default locked even when absent'; k='L8'; t='iss'; a='if not FileExists(Target) then'; b='if FileExists(Target + ''x'') then' }
    # 17 Nov 26 - P-2914 and the examples found on the fresh install
    @{ n='drop docs from the list';           k='L10'; t='iss'; a="'docs/' +"; b="'' +" }
    @{ n='docs\admin never locked';           k='L10'; t='iss'; a='LockAdminOnlyPath(Ps, Script, DocsAdmin, Code)'; b='LockOsUsersPath(Ps, Script, DocsAdmin, Code)' }
    @{ n='admin-only lock without the switch'; k='L10'; t='iss'; a="'"" -AdminOnly'"; b="'""'" }
    @{ n='admin-only grants sdusers read';    k='L10'; t='scr'; a="'*S-1-5-32-544:(OI)(CI)(F)')"; b="'*S-1-5-32-544:(OI)(CI)(F)', 'sdusers:(OI)(CI)(RX)')" }
    @{ n='examples.bp in the early list';     k='L8'; t='iss'; a="'examples/' +"; b="'examples/examples.bp/' +" }
    @{ n='examples never locked after LoadExamples'; k='L11'; t='iss'; a='ExamplesMsg := ExamplesMsg + LockSdsysExamples;'; b='ExamplesMsg := ExamplesMsg + LockSdsysExamplesX;' }
    @{ n='examples locked even when absent';  k='L11'; t='iss'; a='    if DirExists(Target) then'; b='    if True then' }
    @{ n='examples.bp.out left out';          k='L11'; t='iss'; a="'examples.bp/examples.bp.out'"; b="'examples.bp'" }
    @{ n='drop the whole list call';          k='L1'; t='iss'; a='LockSysdirNames(Ps, Script,'; b='LockSysdirNamesX(Ps, Script,' }
    @{ n='lock $ipc too';                     k='L2'; t='iss'; a="'dict.dic/voc.dic"; b="'`$ipc/dict.dic/voc.dic" }
    @{ n='no folder lock';                    k='L3'; t='iss'; a='LockKeepChildrenPath(Ps, Script, Root, Code)'; b='LockOsUsersPath(Ps, Script, Root, Code)' }
    @{ n='folder lock without the switch';    k='L4'; t='iss'; a="'"" -KeepChildren'"; b="'""'" }
    @{ n='errlog not created';                k='L5'; t='iss'; a='SaveStringToFile(ErrLog'; b='{SaveStringToFile}(ErrLog' }
    @{ n='children lose inherit-only';        k='L6'; t='scr'; a="'sdusers:(OI)(CI)(IO)(RX)'"; b="'sdusers:(OI)(CI)(RX)'" }
    @{ n='new children inherit Modify again'; k='L6'; t='scr'; a="'sdusers:(OI)(CI)(IO)(RX)'"; b="'sdusers:(OI)(CI)(IO)(M)'" }
    @{ n='the writable places lose Modify';   k='L6'; t='scr'; a="foreach (`$w in @('`$ipc', 'prt', 'errlog', 'dumps', '`$hold'))"; b="foreach (`$w in @())" }
    @{ n='folder keeps Modify';               k='L6'; t='scr'; a="'sdusers:(RX)',"; b="'sdusers:(M)'," }
)
$mfail = 0
foreach ($m in $mutants) {
    $i = $issText; $s = $scriptText
    if ($m.t -eq 'iss') { $src = $i } else { $src = $s }
    if ($src.IndexOf($m.a) -lt 0) { Write-Output "  [FAIL] mutant '$($m.n)': its anchor is not in the live text, so it changed nothing"; $mfail++; continue }
    $mut = $src.Replace($m.a, $m.b)
    if ($mut -eq $src) { Write-Output "  [FAIL] mutant '$($m.n)': the replacement changed nothing"; $mfail++; continue }
    if ($m.t -eq 'iss') { $res = Test-All $mut $s } else { $res = Test-All $i $mut }
    if ($res[$m.k] -ne '') { Write-Output "  [PASS] mutant '$($m.n)' -> $($m.k) red: $($res[$m.k])" }
    else { Write-Output "  [FAIL] mutant '$($m.n)' left $($m.k) green"; $mfail++ }
}

$total = $fail + $mfail
Write-Output ''
Write-Output ("checks failed: {0}   mutants not caught: {1}   mutants run: {2}" -f $fail, $mfail, $mutants.Count)
if ($total -gt 0) { exit 1 }
exit 0
