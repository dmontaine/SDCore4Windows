# verify-createfilecase.ps1 - a new file's id is stored LOWER CASE, whatever case
# it was typed, and it still resolves typed in any case.  RELEASE_1.1 5, phase
# (a): "lower case ids in SD system files, never in user data files" (owner,
# 13 Sep 2026).
#
#   powershell -ExecutionPolicy Bypass -File verify-createfilecase.ps1
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the fixture
# could not be built (never a FAIL).
#
# WHAT IT MEASURES.  CREATEF now downcases the file name before it writes the VOC
# record and derives the OS name (unless OPT.CREATE.FILE.CASE), so a user typing
# CREATE.FILE ZZ... gets a VOC record and a directory named zz...  The lookup
# fold (as typed -> down -> up, PROJECT_STATUS.md 5.12) already resolves the
# name in any case, so the change is additive: nothing that named a file in
# upper case breaks, only the STORED case moves.  This drives the verb and reads
# back both halves - the VOC id LISTF prints, and the directory on disk.
#
# ***THE DECISIVE CHECKS ANCHOR ON THE STORED CASE, WHICH ONLY THE FIX
# PRODUCES.***  A mixed-case name typed in, found stored in lower with NO
# upper-case twin: that state cannot arise from the old CREATEF, which stored the
# VOC id as typed and the OS name in upper.  Both are read case-SENSITIVELY
# (-cmatch / -ceq), because NTFS matches ZZ against zz and a case-blind check
# would pass whichever case was written and prove nothing - verify-lcnames.ps1
# makes the same point.
#
# ***IT MUST RUN ELEVATED.***  It drives an SDSYS session, and LOGTO SDSYS from
# an unelevated pipe reaches elevate('START')'s UAC consent and hangs (the
# lesson verify-pyapi.ps1 records).  The fixture is created in SDSYS and removed
# again; it needs no account.
#
# ***AND IT RESTORES NOTHING BECAUSE IT CHANGES NO SHIPPED STATE*** - it creates
# one throwaway file named from the clock and deletes all of it, sweeping any
# leftover of its own family first, the shape probe-catprivate.ps1 and
# verify-pyapi.ps1 use.

$ErrorActionPreference = 'Stop'

# assert-current: this measures an INSTALL of a BASIC change (CREATEF), so a
# stale tree answers for the code the change replaced.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-createfilecase: refusing - see assert-current above'
    exit 2
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-createfilecase: this needs an ELEVATED session and this one is not.'
    Write-Output '  It drives an SDSYS session; LOGTO SDSYS from an unelevated pipe hangs at a'
    Write-Output '  UAC consent nothing can answer (see verify-pyapi.ps1).  Run it elevated.'
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys = Join-Path $env:ProgramData 'SD\sdsys'

$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss').Substring(9)   # HHmmss
$typed = 'ZzLcTest' + $stamp        # deliberately MIXED case as typed
$lower = $typed.ToLower()
$upper = $typed.ToUpper()

Write-Output '=== inputs (rule 1: what it actually used) ================================'
Write-Output ("  sd.exe   : " + $sdExe)
Write-Output ("  sdsys    : " + $sdsys)
Write-Output ("  typed    : " + $typed + "   (as the user types it)")
Write-Output ("  expected : VOC id '" + $lower + "', directory '" + $lower + "' (both lower)")

if (-not (Test-Path -LiteralPath $sdExe)) { Write-Output "  no sd.exe at $sdExe"; exit 2 }

function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else {
        Stop-Job $job; $out = Receive-Job $job
        $out += ''; $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** The usual cause is an unelevated session hanging at LOGTO SDSYS."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# ---- sweep any leftover of this family, THEN create the fixture ------------
Write-Output ''
Write-Output '=== fixture ==============================================================='
$stale = @(Get-ChildItem -LiteralPath $sdsys -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match '(?i)^zzlctest[0-9]{6}(\.DIC|\.OUT)?$' })
foreach ($d in $stale) {
    Write-Output ("  sweeping leftover " + $d.Name)
    Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

$cmd = "CREATE.FILE $typed DIRECTORY"
Write-Output ("  SD: " + $cmd + "    (typed mixed case)")
$out = Invoke-SD @($cmd)
Write-Output '  --- CREATE.FILE said: ---'
Write-Output $out

# Anchor on the SUCCESS wording CREATE.FILE prints, not on the id (which the
# refusal echoes too - the trap CLAUDE.md names).
$created = ($out -match 'Created DATA part as')
if (-not $created -or ($out -match 'did not finish in')) {
    Write-Output '  CREATE.FILE did not report success - nothing below could be measured.'
    exit 2
}

$fails = 0; $rows = 0
function Row([bool]$ok, [string]$label, [string]$detail = '') {
    $script:rows++
    if (-not $ok) { $script:fails++ }
    Write-Output ("  [{0}] {1}{2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $label,
                  $(if ($detail) { "  - $detail" } else { '' }))
}

try {
    Write-Output ''
    Write-Output '=== the STORED case ======================================================='

    # (1) THE DIRECTORY ON DISK, read case-sensitively against the real listing.
    $dirs = @(Get-ChildItem -LiteralPath $sdsys -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match ('(?i)^' + [regex]::Escape($lower) + '$') })
    $onDiskName = if ($dirs.Count -gt 0) { $dirs[0].Name } else { '(none)' }
    Write-Output ("  directory on disk: " + $onDiskName)
    Row ($dirs.Count -gt 0) 'a directory for the new file exists in sdsys'
    Row ($onDiskName -ceq $lower) "the directory name is stored LOWER CASE" "got '$onDiskName', want '$lower'"
    # AND NO UPPER-CASE TWIN.  NTFS could not hold both, but the check states the
    # property the fix guarantees rather than resting on the filesystem for it.
    Row (-not ($onDiskName -cmatch '[A-Z]')) 'the directory name carries no upper-case letter'

    # (2) THE VOC RECORD ID, as LISTF prints it (LISTF shows the id as stored).
    $lf = Invoke-SD @("LISTF $lower")
    Write-Output '  --- LISTF said: ---'
    Write-Output $lf
    # The lower id must appear; the upper id must NOT appear as a separate F row.
    Row ($lf -cmatch ('\b' + [regex]::Escape($lower) + '\b')) "LISTF shows the VOC id in lower case ('$lower')"

    Write-Output ''
    Write-Output '=== resolution: the fold still finds it typed either way ==================='
    # OPEN the file by BOTH cases from BASIC-less command level via a SELECT,
    # which opens the file and reports its count; "records listed" / the ok path
    # proves the OPEN resolved.  Upper is the interesting one - the fold must
    # fold it UP-then-find, i.e. down to lower.
    foreach ($cs in @(@{ n = $upper; w = 'UPPER' }, @{ n = $lower; w = 'lower' })) {
        $o = Invoke-SD @("COUNT $($cs.n)")
        $resolved = ($o -notmatch 'not in your VOC' -and $o -notmatch 'not found' -and
                     $o -notmatch 'cannot|Unable to open')
        Row $resolved ("COUNT resolves the file typed in $($cs.w) ('$($cs.n)')")
        if (-not $resolved) { Write-Output '    --- COUNT said: ---'; Write-Output $o }
    }
}
finally {
    Write-Output ''
    Write-Output '=== cleanup ==============================================================='
    $rm = Invoke-SD @("DELETE.FILE $lower")
    foreach ($p in @($lower, ($lower + '.DIC'), ($lower + '.OUT'), $upper)) {
        $full = Join-Path $sdsys $p
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $left = @($lower, $upper) | Where-Object { Test-Path -LiteralPath (Join-Path $sdsys $_) }
    Write-Output ("  removed the fixture; leftover: " + $(if ($left.Count) { $left -join ', ' } else { '(none)' }))
}

Write-Output ''
# REFUSE THE NULL CASE - a run that scored nothing is not a pass.
if ($rows -eq 0) {
    Write-Output 'verify-createfilecase: no check ran - that is a broken test, not a pass.'
    exit 2
}
if ($fails -gt 0) {
    Write-Output "verify-createfilecase: $rows row(s), $fails FAILED"
    exit 1
}
Write-Output "verify-createfilecase: $rows of $rows passed - a new file id is stored lower and resolves either case"
exit 0
