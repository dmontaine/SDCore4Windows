# probe-compilelisting.ps1 - the compile listing User 16a quotes, taken from a real compile in an ordinary account.
#
#   powershell -ExecutionPolicy Bypass -File <sd64>\gplbld\probe-compilelisting.ps1 [-Account don]
#
# AN ORDINARY UNELEVATED PROMPT.  19 Nov 26 - RELEASE_1.1 336 (four-version audit, OUTSTANDING item 2; findings P-2772, P-2778,
# P-2779): User 16a shows what BASIC says for kernel(), option() and pterm() in an ordinary account, and the Windows page's
# listing was never taken from a compile.  The model is verify-basicfuncs.ps1: a throwaway record in the caller's own bp,
# compiled there, and removed again with its object - nothing else is written, no account is made.
#
# It prints the program, the exact commands, the whole compile output, and what it removed.  Its anchor is BCOMP's own count line
# ("<n> error(s)"): a run that printed no count compiled nothing and is exit 2, never a listing.
# Exit 0 the listing was taken, 2 it could not be.
[CmdletBinding()]
param([string]$Account = $env:USERNAME)
$ErrorActionPreference = 'Stop'
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$acct   = Join-Path (Join-Path $env:ProgramData 'SD\user_accounts') $Account
$bpDir  = Join-Path $acct 'bp'
$Probe  = 'ZZCOMPLIST'
function Say([string]$m) { Write-Host $m }
function Bail([string]$m) { Say ('probe-compilelisting: COULD NOT RUN - ' + $m); exit 2 }

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($elevated) { Bail 'this must run UNELEVATED - the listing is the one an ordinary account sees' }
if (-not (Test-Path -LiteralPath $sdExe)) { Bail "no sd.exe at $sdExe" }
if (-not (Test-Path -LiteralPath $bpDir)) { Bail "no bp at $bpDir - pass -Account with your SD account name" }
$dest = Join-Path $bpDir $Probe
if (Test-Path -LiteralPath $dest) { Bail "$dest already exists - not overwriting a record this probe did not make" }

# The page's program, as the page prints it, ending in END: "line 4 of this four-line file, counting its end" is Linux's wording.
$src = @('      v1 = kernel(28, 0)', '      v5 = option(''X'')', '      v6 = pterm(1, '''')', '      end')
Say "account : $Account"
Say "bp      : $bpDir"
Say "sd.exe  : $sdExe"
Say "record  : $dest"
Say '--- the program -----------------------------------------------'
$i = 0; foreach ($l in $src) { $i++; Say ('{0,3}: {1}' -f $i, $l) }

function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    Say ('--- sd input: ' + (($commands) -join ' | '))
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

$made = @()
try {
    [IO.File]::WriteAllText($dest, (($src -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    $made += $dest
    Say '--- compile output (whole) -------------------------------------'
    $out = Invoke-SD @("BASIC BP $Probe")
    Write-Host $out
    Say '----------------------------------------------------------------'
    $m = [regex]::Match($out, '(\d+) error\(s\)')
    if (-not $m.Success) { Bail 'no "<n> error(s)" line in the output - nothing was compiled, so there is no listing' }
    Say ('probe-compilelisting: LISTING TAKEN - the compiler counted ' + $m.Groups[1].Value + ' error(s)')
} finally {
    foreach ($p in @($dest, (Join-Path $acct ('bp.out\' + $Probe)), (Join-Path $acct ('BP.OUT\' + $Probe)))) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Say ('removed : ' + $p) }
    }
}
exit 0
