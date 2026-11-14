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
#       (OI)(CI)(IO)(M) and no other sdusers ACE
#   L7  if an installed tree exists, every entry in it is in one class below;
#       a name in none of them is a new entry nobody decided about
# Then MUTANTS: each is a changed copy of the text IN MEMORY (the live files
# are never written), and the matching check must go red on it.

$ErrorActionPreference = 'Stop'

# The classes.  Fixed: SecureSysdirs' own variables.  Elsewhere: their own
# secure-*.ps1 or [Code] step.  Open: written by ordinary sessions.
$Locked = @('syscom','terminfo','terminfo.src','helptext','dir_dict','licence','contrib',
            'start.default','agent-pack','bp.out','pcode.out',
            'dict.dic','voc.dic','$map.dic','accounts.dic','$hold','$hold.dic')
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
        $want = @('sdusers:(RX)', 'sdusers:(OI)(CI)(IO)(M)')
        $r['L6'] = $(if (($g.Count -eq 2) -and ($g -contains $want[0]) -and ($g -contains $want[1])) { '' }
                     else { 'sdusers grants are: ' + ($g -join ' ') }) }
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
    $all = $Locked + $Fixed + $Elsewhere + $Open
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
    @{ n='drop agent-pack from the list';      k='L1'; t='iss'; a="'start.default/agent-pack/bp.out/pcode.out/' +"; b="'start.default/bp.out/pcode.out/' +" }
    @{ n='drop the whole list call';          k='L1'; t='iss'; a='LockSysdirNames(Ps, Script,'; b='LockSysdirNamesX(Ps, Script,' }
    @{ n='lock $ipc too';                     k='L2'; t='iss'; a="'dict.dic/voc.dic"; b="'`$ipc/dict.dic/voc.dic" }
    @{ n='no folder lock';                    k='L3'; t='iss'; a='LockKeepChildrenPath(Ps, Script, Root, Code)'; b='LockOsUsersPath(Ps, Script, Root, Code)' }
    @{ n='folder lock without the switch';    k='L4'; t='iss'; a="'"" -KeepChildren'"; b="'""'" }
    @{ n='errlog not created';                k='L5'; t='iss'; a='SaveStringToFile(ErrLog'; b='{SaveStringToFile}(ErrLog' }
    @{ n='children lose inherit-only';        k='L6'; t='scr'; a="'sdusers:(OI)(CI)(IO)(M)'"; b="'sdusers:(OI)(CI)(M)'" }
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
