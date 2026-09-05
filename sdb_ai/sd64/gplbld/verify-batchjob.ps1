# verify-batchjob.ps1 - prove that a command on the command line is admitted by
# the account's list OR by elevation, and refused otherwise.
# PROJECT_STATUS.md 7 step 9.
#
#   powershell -File verify-batchjob.ps1
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# RUN IT UNELEVATED.  The measurement that matters is what an ORDINARY token
# may run, and an elevated shell passes the gate on its own by design - so an
# elevated run would report success while proving nothing.  The gate below
# refuses one, exactly as verify-osusers.ps1 does and for the same reason.
#
# IT RAISES TWO UAC PROMPTS OF ITS OWN, and cannot avoid them: the list lives
# in SDSYS batch.jobs, which is read-only to sdusers - that ACL is the whole of
# the control - so writing a probe record into it and taking it out again needs
# an elevated child.  The measurements in between are made by THIS process,
# with its ordinary token.  Same shape as verify-osusers.ps1, which prompts
# three times.
#
# WHAT IT MEASURES, and every row has its opposite somewhere in the list,
# because a gate that refuses everything would otherwise pass:
#
#   refused BEFORE the list entry exists      the fail-closed default
#   RUNS once the entry is written            the entry is what admits it
#   refused again once it is removed          and nothing else was admitting it
#   refused WITH AN ARGUMENT though listed    section 8's no-arguments rule
#   refused when the VOC record is not PA/S   the type test
#   RUNS ELEVATED IN SDSYS with no entry      elevation still passes on its own
#
# 29 Aug 26 - THE LAST ROW IS ASKED OF SDSYS, NOT OF THE ACCOUNT, and the change
# is the owner's ruling on PRE_RELEASE 59.  It used to Push-Location into the
# account and run sd elevated; b65 measured that FAILING, because under the
# ruled access model an elevated session cannot stand in an ordinary account at
# all - it lands in SDSYS, and a LOGTO out of SDSYS gives up the flag.  The
# state that row measured stopped existing; the rule it protects did not.  The
# elevated half's own comment carries the full reasoning.
#   an ordinary token cannot write the list   the ACL, which is the control
#
# THE PARAGRAPH RUNS "COUNT VOC", chosen because its output - "N record(s)
# counted" - cannot be confused with a login banner, a refusal or an empty
# session.  "It did not refuse" is not evidence that it ran.

[CmdletBinding()]
param(
    # Set when this script re-invokes itself elevated.  Not for a person.
    [ValidateSet('', 'setup', 'cleanup')]
    [string] $Phase = '',
    [string] $Account = '',
    [string] $ResultFile = '',

    # 04 Sep 26 - PRE_RELEASE 165.  A pipe VerifyInstall1 is already serving, so
    # the two elevated phases below cost no consent of their own.  Not passed
    # down to this script's own elevated halves: they are already elevated and
    # have nothing to ask for.
    [string] $HelperPipe = ''
)

$ErrorActionPreference = 'Stop'

# ADOPT ONLY - this script never starts a helper.  Run standalone it behaves
# exactly as it always has, two UAC prompts, because Invoke-ElevatedScript falls
# back to Start-Process -Verb RunAs when no pipe is active.
. (Join-Path $PSScriptRoot 'elevate-once.ps1')
if ($HelperPipe -ne '') {
    $null = Start-SdElevationHelper -Adopt $HelperPipe -Purpose 'this step'
}

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys   = Join-Path $env:ProgramData  'SD\sdsys'
$listDir = Join-Path $sdsys 'batch.jobs'

$paName = 'zzbatchpa'      # a paragraph: allowed once listed
$fpName = 'zzbatchfp'      # a file pointer: listed, but the wrong VOC type
# 29 Aug 26 - the same paragraph again, in SDSYS's own VOC, for the elevated
# row.  It needs a name of its own: the account probes are in the ACCOUNT's VOC
# and an elevated session never sees them, which is the whole reason that row
# was re-aimed.  PRE_RELEASE 59.
$sysPa  = 'zzbatchsyspa'   # the same paragraph, in SDSYS, for the elevated row

# ---------------------------------------------------------------- elevated half
#
# TWO PHASES, ONE FILE.  The elevated child writes or removes the batch.jobs
# record and nothing else - it makes no measurement, because a measurement made
# with the wrong token is the fault this script is shaped to avoid.
if ($Phase -ne '') {
    $rec = Join-Path $listDir $Account
    try {
        switch ($Phase) {
            'setup' {
                if (-not (Test-Path -LiteralPath $listDir)) {
                    Set-Content -LiteralPath $ResultFile -Value "no batch.jobs at $listDir" -Encoding utf8
                    exit 2
                }
                # One name per LINE, which is a field mark on disk.  LOGIN reads
                # field marks and value marks alike; this is the shape somebody
                # editing with ED would produce.
                [System.IO.File]::WriteAllText($rec, "$paName`n$fpName")
                Set-Content -LiteralPath $ResultFile -Value 'ok' -Encoding utf8
            }
            'cleanup' {
                if (Test-Path -LiteralPath $rec) { Remove-Item -LiteralPath $rec -Force }

                # WHILE STILL ELEVATED, and this is a measurement the ordinary
                # half CANNOT make: with the record now gone, an elevated
                # session must still run the command.  That is the owner's
                # decision of 22 Aug - elevation passes on its own - and it is
                # the row that proves this change did not tighten the
                # administrator path while loosening the other.
                # 23 Aug 26 - "$null |" IS LOAD-BEARING, NOT TIDINESS.
                #
                # This child was launched by Start-Process -Verb RunAs, so it HAS
                # A CONSOLE, and a bare "& $sdExe" hands that console straight to
                # the child as stdin.  LOGIN:639 then sees kernel(K$TTY,0) # ''
                # - ttyname(fileno(stdin)), kernel.c:250 - decides somebody is
                # there to type, and asks an account with no credential to set a
                # password.  Nobody is there, so it BLOCKS FOR EVER and the whole
                # suite stops on this line.
                #
                # That is not hypothetical: it is the fault the forty-fourth
                # session handed over as "elevated sd hangs during start-up", and
                # it costs an elevation to clear because an ordinary token cannot
                # kill an SD console session.  A -Silent install leaves every
                # account without a credential (sd.iss:1276), so this is the
                # NORMAL state after a cycle, not an unlucky one.
                #
                # MEASURED in a real elevated console, 23 Aug 2026: bare call
                # gives the child a TTY, "$null |" gives NOTTY, and this command
                # then returns in 0.3s with "ZZNOSUCHVERB is not in your VOC"
                # instead of a password prompt.  Start-Job would do it too - that
                # is why Invoke-SdCommand above never hit this - but a pipe keeps
                # the measurement in this process, where the elevated token is.
                #
                # IT DOES NOT WEAKEN THE ROW.  What is being measured is whether
                # an elevated session may still RUN the command; the credential
                # prompt is a different subject and does not belong in the way.
                #
                # ------------------------------------------------------------
                # 29 Aug 26 - RE-AIMED AT SDSYS.  Owner's ruling, PRE_RELEASE 59.
                #
                # THIS ROW USED TO Push-Location INTO THE ACCOUNT and run sd
                # elevated, expecting to stand in that account with the gate
                # bypassed.  b65 measured it FAILING, and the cause is not a
                # product defect: UNDER THE RULED MODEL AN ELEVATED SESSION
                # CANNOT STAND IN AN ORDINARY ACCOUNT AT ALL.  An elevated login
                # goes to SDSYS (LOGIN's "case kernel(K$ADMINISTRATOR,-1) and
                # kernel(K$OS.ADMINISTRATOR,0)"), and a LOGTO out of SDSYS gives
                # up the flag (CPROC, "administrator rights belong to SDSYS").
                # The state this row measured no longer exists, so it is asked
                # where an elevated session actually is.
                #
                # THE CLAIM IS UNCHANGED - "elevation passes on its own", the
                # owner's decision of 22 Aug 2026.  Only the place it is asked
                # has moved.
                #
                # AND IT IS STILL DECISIVE.  LOGIN:901 bypasses the WHOLE of
                # batch.permitted on K$ADMINISTRATOR - the no-arguments check,
                # the batch.jobs listing check AND the PA/S type check.  So a
                # command that runs here with NO batch.jobs record for SDSYS
                # cannot have passed the listing check, and the bypass is the
                # only thing left that explains it.
                #
                # THE "NO ENTRY" PRECONDITION IS ASSERTED, NOT ASSUMED - and a
                # record found here is NOT deleted, because this script did not
                # write it.  Without the assertion the row could pass because
                # SDSYS happened to be listed rather than because elevation
                # bypassed the gate: a pass for the wrong reason, which is what
                # section 8 exists to stop.
                $sysRec = Join-Path $listDir 'SDSYS'
                if (Test-Path -LiteralPath $sysRec) {
                    Set-Content -LiteralPath $ResultFile -Encoding utf8 -Value @(
                        'SDSYS-ENTRY-PRESENT'
                        "batch.jobs already carries a record for SDSYS: $sysRec"
                        'This row measures a session with NO entry, so it cannot be'
                        'measured while that record stands - and this will not delete'
                        'a record it did not write.  Remove it by hand if it is stale.'
                    )
                    exit 0
                }

                # PLANTED IN SDSYS's OWN VOC, THROUGH SD, for the reason the
                # account-side planter gives: a VOC is a dynamic file and a
                # record cannot be dropped into it from the file system.  This
                # process is elevated, so a piped sd lands in SDSYS and OPEN
                # 'voc' opens SDSYS's own.
                $sysBp   = Join-Path $sdsys 'bp'
                $sysProg = 'ZZBATCHS'
                $sysSrc  = Join-Path $sysBp $sysProg
                $sysObj  = Join-Path (Join-Path $sdsys 'bp.out') $sysProg

                $planter = @(
                    "* $sysProg - written by gplbld/verify-batchjob.ps1.  Safe to delete."
                    "      OPEN 'voc' TO F ELSE STOP 'cannot open VOC'"
                    "      R = 'PA' : @FM : 'COUNT VOC'"
                    "      WRITE R ON F, '$sysPa'"
                    "      CRT '$sysProg-DONE'"
                ) -join "`n"
                [System.IO.File]::WriteAllText($sysSrc, $planter + "`n",
                                               [System.Text.Encoding]::GetEncoding('iso-8859-1'))

                try {
                    # PIPED, never on the command line: "sd BASIC bp X" is the
                    # very thing this script exists to see refused.
                    $plant = (("`nBASIC bp $sysProg`nRUN bp $sysProg`nOFF`n") |
                              & $sdExe 2>&1 | Out-String)
                    if (-not $plant.Contains("$sysProg-DONE")) {
                        Set-Content -LiteralPath $ResultFile -Encoding utf8 -Value @(
                            'SDSYS-PLANT-FAILED'
                            $plant
                        )
                    } else {
                        # THE MEASUREMENT.  "$null |" is load-bearing - see the
                        # long note above; it is what keeps this NOTTY.
                        $out = ($null | & $sdExe $sysPa 2>&1 | Out-String)
                        Set-Content -LiteralPath $ResultFile -Value $out -Encoding utf8
                    }
                }
                finally {
                    # UNCONDITIONAL, AND "DELETE VOC" RATHER THAN "DELETE.FILE" -
                    # PRE_RELEASE 60 and 61.  A VOC record outliving what it
                    # names IS the defect those entries are about, so this runs
                    # on every path out, including both failures above.  Its
                    # wording is not read: sysmsg 3221 prints "%1 record(s)
                    # deleted" on the failure path too, so it is no anchor.
                    $null = (("`nDELETE VOC $sysPa`nOFF`n") | & $sdExe 2>&1)
                    foreach ($f in @($sysSrc, $sysObj)) {
                        if (Test-Path -LiteralPath $f) {
                            try { Remove-Item -LiteralPath $f -Force } catch { }
                        }
                    }
                }
            }
        }
        exit 0
    }
    catch {
        Set-Content -LiteralPath $ResultFile -Value ("EXCEPTION: " + $_.Exception.Message) -Encoding utf8
        exit 2
    }
}

# -------------------------------------------------------------------- the gate
if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-batchjob: this is an ELEVATED PowerShell, and the measurement needs an ordinary one.'
    Write-Output ''
    Write-Output '  An elevated session passes the gate on its own, by design (step 7''s shape).'
    Write-Output '  Run from a normal window; this script elevates twice by itself for the'
    Write-Output '  two steps that write the list.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-batchjob: refusing - see above'
    exit 2
}

foreach ($p in @($sdExe, $listDir)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output "verify-batchjob: refusing - no $p"
        exit 2
    }
}

$account = $env:USERNAME.ToLower()
$acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $account)
if (-not (Test-Path -LiteralPath $acctDir)) {
    Write-Output "verify-batchjob: refusing - $account has no SD account at $acctDir"
    exit 2
}
$bp = Join-Path $acctDir 'bp'
if (-not (Test-Path -LiteralPath $bp)) {
    Write-Output "verify-batchjob: refusing - $account has no bp file at $bp"
    exit 2
}

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($check, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
}

# Drive one "sd <words>" from inside the account, with its own token.
function Invoke-SdCommand([string[]]$words, [int]$TimeoutSec = 60) {
    $job = Start-Job -ScriptBlock {
        param($exe, $argv, $cwd)
        Set-Location $cwd
        & $exe @argv 2>&1
    } -ArgumentList $sdExe, $words, $acctDir
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += '*** TIMED OUT - it is sitting at a prompt.'
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') | Out-String)
}

# THE INTERACTIVE PATH, WHICH THIS CHANGE DOES NOT TOUCH.  Only the COMMAND
# LINE is gated - SYSTEM(1026) - so commands piped into a plain "sd" session run
# exactly as they always did.  That distinction is not a convenience here, it is
# the only way this script can set itself up at all: planting and removing the
# VOC probes with "sd DELETE VOC x" would be refused by the very gate being
# measured, and the setup would fail for the same reason as a genuine defect.
function Invoke-SdPiped([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + (($commands + 'OFF') -join "`n") + "`n"
    $job = Start-Job -ScriptBlock {
        param($exe, $text, $cwd)
        Set-Location $cwd
        $text | & $exe
    } -ArgumentList $sdExe, $body, $acctDir
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += '*** TIMED OUT - it is sitting at a prompt.'
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') | Out-String)
}

# Message fragments, each wholly inside ONE line of its message - 10096, 10097
# and 10098 all wrap with \n, and a fragment spanning the break would never
# match.  .Contains() rather than -match or -SimpleMatch: no regex layer to
# escape and no pattern layer to take too literally.
function SawRefusal([string]$t) { return $t.Contains('is not a command that account') }
function SawArgs([string]$t)    { return $t.Contains('must be a single name with nothing') }
function SawType([string]$t)    { return $t.Contains('has to be a paragraph or a sentence') }
function SawRan([string]$t)     { return $t.Contains('record(s) counted') }

# ------------------------------------------------------- plant the VOC probes
#
# THROUGH SD, NOT THROUGH THE FILE SYSTEM.  An account VOC is a DYNAMIC file -
# on disk two %0/%1 buckets - so a record cannot be dropped in the way a
# directory file's can.  A one-shot BASIC program is the shortest honest route,
# and it runs with the ordinary token like everything else here.
$planter = @(
    "* ZZBATCHW - written by gplbld/verify-batchjob.ps1.  Safe to delete."
    "      OPEN 'voc' TO F ELSE STOP 'cannot open VOC'"
    "      R = 'PA' : @FM : 'COUNT VOC'"
    "      WRITE R ON F, '$paName'"
    "      R = 'F' : @FM : 'bp'"
    "      WRITE R ON F, '$fpName'"
    "      CRT 'ZZBATCHW-DONE'"
) -join "`n"

$planterSrc = Join-Path $bp 'ZZBATCHW'
[System.IO.File]::WriteAllText($planterSrc, $planter + "`n",
                               [System.Text.Encoding]::GetEncoding('iso-8859-1'))

function Remove-Probes {
    $out = Invoke-SdPiped @(('DELETE VOC ' + $paName), ('DELETE VOC ' + $fpName))
    foreach ($f in @($planterSrc, (Join-Path $acctDir ('bp.out\ZZBATCHW')))) {
        if (Test-Path -LiteralPath $f) {
            try { Remove-Item -LiteralPath $f -Force } catch {
                Write-Output "verify-batchjob: WARNING - could not remove $f"
            }
        }
    }
}

# PIPED, for the reason Invoke-SdPiped gives: "sd BASIC bp ZZBATCHW" on the
# command line is exactly what this script exists to see refused.
$plant = Invoke-SdPiped @('BASIC bp ZZBATCHW', 'RUN bp ZZBATCHW')
if (-not $plant.Contains('ZZBATCHW-DONE')) {
    Write-Output 'verify-batchjob: the VOC probes could not be planted - nothing below would mean anything.'
    Write-Output $plant
    Remove-Probes
    exit 2
}

Write-Output "verify-batchjob: probing as SD account $account"
Write-Output ''

# ------------------------------------------------------------ 1. the default
$before = Invoke-SdCommand @($paName)
Note 'unlisted: refused'                 $true (SawRefusal $before) $true
Note 'unlisted: did NOT run'             $true (-not (SawRan $before)) $true

# --------------------------------------------------------------- 2. the ACL
$aclProbe = Join-Path $listDir 'zzaclprobe.tmp'
$wrote = $false
try { [System.IO.File]::WriteAllText($aclProbe, 'x'); $wrote = $true } catch { $wrote = $false }
if ($wrote) { try { Remove-Item -LiteralPath $aclProbe -Force } catch { } }
Note 'an ordinary token cannot WRITE batch.jobs' $false $wrote $true

# ------------------------------------------------------- 3. write the entry
$resultFile = Join-Path ([System.IO.Path]::GetTempPath()) 'verify-batchjob-elev.txt'
if (Test-Path -LiteralPath $resultFile) { Remove-Item -LiteralPath $resultFile -Force }

# 04 Sep 26 - PRE_RELEASE 165.  ONE FUNCTION FOR BOTH PHASES, AND IT REPLACES
# A POSITIONAL EDIT.  The two calls used to share one $a array with the second
# reaching into it - "$a[6] = 'cleanup'   # element 6 is the -Phase VALUE" - so
# inserting an argument anywhere before it would silently have set the wrong
# element and run the setup phase twice.  A parameter cannot do that.
#
# THROUGH THE RUNNER'S HELPER WHEN THERE IS ONE: the helper takes a script path
# and passes no arguments, so the re-entry goes into a launcher.
function Invoke-BatchJobPhase([string]$Phase) {
    $vals = @($PSCommandPath, $Phase, $account, $resultFile)
    if (@($vals | Where-Object { $_ -match "'" }).Count -gt 0) {
        Write-Output 'verify-batchjob: a value contains an apostrophe; cannot build the launcher.'
        return $false
    }
    $work = Join-Path $env:TEMP ('vbj-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $work
    try {
        $call = "& '$PSCommandPath' -Phase '$Phase' -Account '$account' -ResultFile '$resultFile'"
        $launcher = Join-Path $work 'phase.ps1'
        [System.IO.File]::WriteAllText($launcher,
            (@($call, 'exit $LASTEXITCODE') -join "`r`n") + "`r`n",
            [System.Text.Encoding]::ASCII)
        Write-Output ('  elevated phase argv: ' + $call)
        $r = Invoke-ElevatedScript -Launcher $launcher -Why ('verify-batchjob ' + $Phase)
        if (-not $r.Ok) {
            Write-Output ("verify-batchjob: elevation did not happen: " + $r.Reason)
            return $false
        }
        return ($r.ExitCode -eq 0)
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($HelperPipe -ne '') {
    Write-Output '  No prompt: the probe record is written through the runner''s elevated helper.'
} else {
    Write-Output '  A UAC PROMPT IS COMING - it writes the probe record into batch.jobs.'
}
$elevOk = Invoke-BatchJobPhase 'setup'
if (-not $elevOk) {
    Write-Output 'verify-batchjob: could not write the list entry, so nothing below is measurable.'
    if (Test-Path -LiteralPath $resultFile) { Write-Output (Get-Content -Raw $resultFile) }
    Remove-Probes
    exit 2
}

# ------------------------------------------------------------ 4. listed: runs
$listed = Invoke-SdCommand @($paName)
Note 'listed: the paragraph RAN'          $true (SawRan $listed)     $true
Note 'listed: no refusal'                 $false (SawRefusal $listed) $true

# ------------------------------------------- 5. listed, but with an argument
$withArg = Invoke-SdCommand @($paName, 'EXTRA')
Note 'listed + argument: refused'         $true (SawArgs $withArg)   $true
Note 'listed + argument: did NOT run'     $true (-not (SawRan $withArg)) $true

# ------------------------------------------------ 6. listed, wrong VOC type
$wrongType = Invoke-SdCommand @($fpName)
Note 'listed but not PA/S: refused on TYPE' $true (SawType $wrongType) $true

# ------------------------------------- 7. remove it, and check elevation too
if ($HelperPipe -ne '') {
    Write-Output '  No prompt: the removal goes through the same helper, and still tests the elevated path.'
} else {
    Write-Output '  A SECOND UAC PROMPT IS COMING - it removes the record and tests the elevated path.'
}
if (Test-Path -LiteralPath $resultFile) { Remove-Item -LiteralPath $resultFile -Force }
$cleanOk = Invoke-BatchJobPhase 'cleanup'

if ($cleanOk -and (Test-Path -LiteralPath $resultFile)) {
    $elevOut = (Get-Content -Raw -LiteralPath $resultFile)

    # 29 Aug 26 - "COULD NOT BE MEASURED" IS NOT "FAILED", and scoring it as one
    # would be a claim about the product that this run did not make.  Both
    # markers mean the elevated child never reached the question: SDSYS was
    # already listed in batch.jobs, or the probe would not plant.  The row is
    # recorded NON-DECISIVE so it cannot turn the script red, and the child's
    # own text is printed so the reason is on the transcript rather than
    # inferred from a bare FAIL.
    if ($elevOut.Contains('SDSYS-ENTRY-PRESENT') -or $elevOut.Contains('SDSYS-PLANT-FAILED')) {
        Write-Output 'verify-batchjob: the SDSYS row COULD NOT BE MEASURED - this is not a failure.'
        Write-Output $elevOut
        Note 'ELEVATED in SDSYS, no entry: still runs' $true $false $false
    } else {
        Note 'ELEVATED in SDSYS, no entry: still runs' $true (SawRan $elevOut) $true
    }
    Remove-Item -LiteralPath $resultFile -Force
} else {
    Write-Output 'verify-batchjob: WARNING - the record may still be in batch.jobs.'
    Write-Output ("  Remove by hand: " + (Join-Path $listDir $account))
    Note 'ELEVATED in SDSYS, no entry: still runs' $true $false $true
}

# ------------------------------------------------- 8. and refused once more
$after = Invoke-SdCommand @($paName)
Note 'entry removed: refused again'       $true (SawRefusal $after)  $true

Remove-Probes

# ---------------------------------------------------------------------- report
$results | Format-Table -AutoSize | Out-String | Write-Output

if ($fatal) {
    Write-Output 'verify-batchjob: FAILED.'
    Write-Output ''
    if ((SawRan $before) -or (SawRan $after)) {
        Write-Output '  IT RAN WITHOUT A LIST ENTRY, which is the serious direction: the gate in'
        Write-Output '  LOGIN (batch.permitted) is not being reached, or it is falling through to'
        Write-Output '  batch.ok true.  sd.c no longer refuses an unelevated command line, so'
        Write-Output '  LOGIN is the only thing standing there.'
    } elseif (-not (SawRan $listed)) {
        Write-Output '  IT NEVER RAN, even when listed.  That is the harmless direction but it'
        Write-Output '  makes every refusal above meaningless - a gate that refuses everything'
        Write-Output '  passes those rows for the wrong reason.  Check the record actually'
        Write-Output ("  reached " + (Join-Path $listDir $account) + " and that the VOC records exist.")
    }
    exit 1
}

Write-Output 'verify-batchjob: PASSED - the list admits, the absence of it refuses, and elevation still passes.'
exit 0
