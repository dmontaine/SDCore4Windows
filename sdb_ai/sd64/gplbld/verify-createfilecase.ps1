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
    # THROUGH SD FIRST (13 Sep 26, RELEASE_1.1 32): a leftover directory from an
    # interrupted run has a VOC record too, and Remove-Item alone would strand it
    # - PRE_RELEASE 60's shape.  The .DIC and .OUT go with the DATA name.
    if ($d.Name -notmatch '\.(DIC|OUT)$') { $null = Invoke-SD @("DELETE.FILE $($d.Name.ToLower())") }
    if (Test-Path -LiteralPath $d.FullName) {
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
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

# 13 Sep 26 - RELEASE_1.1 32.  THE THREE MATCHERS, AS FUNCTIONS SO THEY CAN BE
# DRIVEN ON THEIR OWN.  Found while wiring this into VerifyInstall2: the first
# version's LISTF row matched the id ANYWHERE in the session text - and the
# session ECHOES ":LISTF <id>", and a miss prints "'<id>' not found" - so it
# passed whether LISTF found the file or not.  Its COUNT rows asserted only the
# ABSENCE of failure words, never the success line.  Both are the trap CLAUDE.md
# names ("anchor on the SUCCESS wording, not on any string the failure also
# carries").  The formats below were captured from a real session on the
# 18:41:41 install, success and miss both, before these were written.
#
#   LISTF hit :  "zzlcprobe210617      Dir      F   zzlcprobe210617  ..."
#                "1 record(s) listed"
#   LISTF miss:  "0 record(s) listed" / "'zznosuchfile999' not found"
#   COUNT hit :  "0 record(s) counted"   (an empty file is still found)
#   COUNT miss:  "File not found"
#   CT gone   :  "Record 'zzlcprobe210617' not found"

# A LISTF table ROW for the id, case-sensitive, at the start of a line - the
# echoed command starts with ":" and the miss wording starts with "'", so
# neither can match - AND exactly one record listed.
function Test-ListfRow([string]$text, [string]$id) {
    return (($text -cmatch ('(?m)^' + [regex]::Escape($id) + '\s+Dir\s')) -and
            ($text -match '(?m)^1 record\(s\) listed'))
}
# COUNT's own success line, and none of the ways it says it could not open.
function Test-CountResolved([string]$text) {
    return (($text -match '(?m)^\d+ record\(s\) counted') -and
            ($text -notmatch 'File not found|not in your VOC|did not finish in'))
}
# The VOC record is gone: CT's not-found wording naming the id, from a session
# that finished.
function Test-VocGone([string]$text, [string]$id) {
    return (($text -match ("Record '" + [regex]::Escape($id) + "' not found")) -and
            ($text -notmatch 'did not finish in'))
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
    # A table row for the lower id - not the echo, not the miss wording.
    Row (Test-ListfRow $lf $lower) "LISTF lists a row for the VOC id in lower case ('$lower')"

    Write-Output ''
    Write-Output '=== resolution: the fold still finds it typed either way ==================='
    # OPEN the file by BOTH cases from BASIC-less command level via a SELECT,
    # which opens the file and reports its count; "records listed" / the ok path
    # proves the OPEN resolved.  Upper is the interesting one - the fold must
    # fold it UP-then-find, i.e. down to lower.
    foreach ($cs in @(@{ n = $upper; w = 'UPPER' }, @{ n = $lower; w = 'lower' })) {
        $o = Invoke-SD @("COUNT $($cs.n)")
        $resolved = Test-CountResolved $o
        Row $resolved ("COUNT resolves the file typed in $($cs.w) ('$($cs.n)') - 'record(s) counted'")
        if (-not $resolved) { Write-Output '    --- COUNT said: ---'; Write-Output $o }
    }

    # 14 Sep 26 - RELEASE_1.1 5, STAGE 1: CASE INVERSION STARTS OFF.  LOGIN set
    # pterm(PT$INVERT, @true) at every login and linuxio.c set it at session
    # start; the owner ruled both off.  ***A PIPED SESSION CANNOT SEE THIS***:
    # measured on the pre-change install, a piped "PTERM DISPLAY" already read
    # "Case inversion: Off" - the pipe's first input clears it (_INPUT) - so
    # verify-lcnames' pipe rows are only a control.  "sd -internal PTERM
    # DISPLAY" reads no input at all, so it reports the state LOGIN left, and
    # -internal needs elevation, which is why this lives here.
    Write-Output ''
    Write-Output '=== case inversion as LOGIN leaves it (sd -internal, no input read) ======'
    $ptOut = Join-Path $env:TEMP ("sd-ptdisp-out-$PID.txt")
    $ptErr = Join-Path $env:TEMP ("sd-ptdisp-err-$PID.txt")
    Write-Output ("  command: `"$sdExe`" -internal PTERM DISPLAY")
    $pp = Start-Process -FilePath $sdExe -ArgumentList @('-internal', 'PTERM', 'DISPLAY') -NoNewWindow -PassThru `
                        -RedirectStandardOutput $ptOut -RedirectStandardError $ptErr
    $null = $pp.Handle                      # upgrade-voc.ps1: or ExitCode reads $null
    $ptDone = $pp.WaitForExit(60000)
    $ptText = ''
    foreach ($f in @($ptOut, $ptErr)) {
        if (Test-Path $f) { $ptText += (Get-Content $f -Raw); Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    if (-not $ptDone) { try { $pp.Kill() } catch { } }
    Write-Output '  --- sd -internal PTERM DISPLAY said: ---'
    Write-Output $ptText
    $ptRead = @([regex]::Matches("$ptText", 'Case inversion: (On|Off)') | ForEach-Object { $_.Groups[1].Value })
    Row $ptDone 'sd -internal PTERM DISPLAY finished within 60 s'
    Row ($ptRead.Count -eq 1) 'PTERM DISPLAY printed exactly one case inversion line' ("got " + $ptRead.Count)
    Row (($ptRead.Count -eq 1) -and ($ptRead[0] -eq 'Off')) 'a session LOGIN has set up reports case inversion Off' ($ptRead -join ',')
}
finally {
    Write-Output ''
    Write-Output '=== cleanup ==============================================================='
    $rm = Invoke-SD @("DELETE.FILE $lower")
    Write-Output '  --- DELETE.FILE said: ---'
    Write-Output $rm
    foreach ($p in @($lower, ($lower + '.DIC'), ($lower + '.OUT'), $upper)) {
        $full = Join-Path $sdsys $p
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $left = @($lower, $upper) | Where-Object { Test-Path -LiteralPath (Join-Path $sdsys $_) }
    Write-Output ("  removed the fixture; leftover: " + $(if ($left.Count) { $left -join ', ' } else { '(none)' }))

    # 13 Sep 26 - RELEASE_1.1 32.  THE VOC RECORD IS CHECKED, NOT ASSUMED.  This
    # fixture is a file in SDSYS, so a cleanup that took the directory and not
    # the record would leave a dead F-pointer - RELEASE_1.1 26 and 31, twice
    # today, both from green steps.  CT, not a file test: a VOC record is not a
    # file.  If DELETE.FILE left it, DELETE VOC takes it and the row still fails,
    # so the leak is reported rather than quietly repaired.
    $ct = Invoke-SD @("CT VOC $lower")
    $gone = Test-VocGone $ct $lower
    if (-not $gone) {
        Write-Output '  --- CT VOC said: ---'; Write-Output $ct
        $null = Invoke-SD @("DELETE VOC $lower")
    }
    Row $gone "the VOC record '$lower' is gone after cleanup"
    Row ($left.Count -eq 0) 'no fixture directory is left in sdsys' ($left -join ', ')
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
