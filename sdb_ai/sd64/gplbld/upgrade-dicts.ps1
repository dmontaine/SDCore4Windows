#
# upgrade-dicts.ps1 - bring an upgraded install's dictionaries up to the release
#
# Run by the installer at ssPostInstall, on an UPGRADE only.
#
# WHY THE DICTIONARIES ARE BUILT AT INSTALL RATHER THAN SHIPPED.  Owner,
# 25 Aug 2026: there are no binary bits in this repository, and a dictionary is
# more efficient as a DYNAMIC file - so the dictionaries are created and loaded
# during the install instead of being tracked as built files.  That is why
# gplbld\FILES_DICTS is the tracked source (76 records, keyed
# "<file>^<record>") and gpl.bp\WRITE_INSTALL_DICTS is what turns it into
# dictionaries.  It is the same reasoning that makes the pcode build Python
# rather than a shipped binary.
#
# WHY AN UPGRADE NEEDS THIS AND A FIRST INSTALL DOES NOT.  A first install
# copies the whole staged tree, and the BUILD's own bootstrap already ran
# WRITE_INSTALL_DICTS against it.  An upgrade deliberately preserves the user's
# data tree, and the dictionaries live inside it - so a release that edits
# FILES_DICTS would never reach an upgraded machine.  The field would resolve
# on a fresh install and not on an upgraded one, which is the "works on my
# machine" shape.
#
# ***IT MERGES, IT DOES NOT REPLACE, AND THAT IS WHY IT IS THIS PROGRAM AND NOT
# A FILE COPY.*** WRITE_INSTALL_DICTS:107 is "WRITE DICT.REC ON DICT.FILE.VAR,
# FILE_REC_NAME" - one record at a time, no CLEARFILE and no delete - so a
# dictionary item an administrator added survives.  Copying the shipped
# dictionary over theirs would destroy it silently, which is the same argument
# that keeps cat and accounts on stage.py's SDSYS_PRESERVE.  It is
# UPDATE.ACCOUNT's shape, which the owner already ruled correct for VOC.
#
# THE INPUT HAS TO BE INSIDE THE DATA TREE WHILE IT RUNS.  WRITE_INSTALL_DICTS
# reads @sdsys:"/gplbld/FILES_DICTS", a hard-coded path, so this places the file
# there, runs, and removes it in a finally.  bootstrap.py does exactly the same
# at build time and its BOOTSTRAP_ONLY comment says why: it is a build input,
# not data, and the data tree must not keep one.
#
# AND THIRD.COMPILE AFTER IT, WHICH IS NOT OPTIONAL.  Dictionary I-types are
# compiled, and the bootstrap runs THIRD.COMPILE immediately after
# WRITE_INSTALL_DICTS for that reason.  Leaving it out writes dictionary
# records whose I-types have no object.
#
# THE THREE THINGS THAT KILLED EARLIER STEPS OF THIS SHAPE are all handled the
# way adopt-account.ps1's header records them, and its measurements are not
# repeated here: "sd -internal" NEEDS A RUNNING SERVER and the installer starts
# none; it NEEDS AN ELEVATED TOKEN, which is why sd.iss calls this from [Code]
# and not from a postinstall checkbox; and ITS OUTPUT HAS TO SURVIVE, so
# everything is captured and logged.
#
# EXIT CODES, and sd.iss reports each one differently:
#   0  the dictionaries were written and compiled
#   3  SD would not start, so nothing was run
#   4  no FILES_DICTS was shipped - a build fault, not a machine fault
#   1  it ran and did not finish the job
#

[CmdletBinding()]
param(
    # Where SD's program files are.  The installer passes {app}.  NOT
    # "= $PSScriptRoot" in the default: in a script with [CmdletBinding()] that
    # evaluates to the empty string, which cost a whole install once -
    # adopt-account.ps1's -AppDir comment has the measurement.  Assigned in the
    # body instead.
    [string] $AppDir = '',

    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Stop'

$LogFile = Join-Path $DataDir 'upgrade-dicts.log'

function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }

Say ("=== upgrade-dicts {0}  AppDir={1}  DataDir={2}" -f
     (Get-Date -Format 's'), $AppDir, $DataDir)

if (-not $AppDir) {
    Say 'upgrade-dicts: no -AppDir given and PSScriptRoot is empty; cannot find sd.exe'
    exit 1
}

$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) { Say "upgrade-dicts: no sd.exe at $sd"; exit 1 }

$sysdir  = Join-Path $DataDir 'sdsys'
$srcDict = Join-Path $AppDir  'gplbld\FILES_DICTS'
$dstDir  = Join-Path $sysdir  'gplbld'
$dstDict = Join-Path $dstDir  'FILES_DICTS'

# THE NULL CASE, REFUSED BEFORE ANYTHING STARTS.  WRITE_INSTALL_DICTS against
# an absent or empty FILES_DICTS transfers nothing and there is no wording in
# its output that distinguishes that from success - so the count is taken here,
# from the source, and every later check is measured against it.
if (-not (Test-Path $srcDict)) {
    Say "upgrade-dicts: no FILES_DICTS at $srcDict - nothing to write."
    Say '  stage.py ships it to {app}\gplbld; if it is missing the build is wrong.'
    exit 4
}
$wanted = @(Get-ChildItem -LiteralPath $srcDict -File -ErrorAction SilentlyContinue)
Say ("upgrade-dicts: {0} holds {1} dictionary record(s)" -f $srcDict, $wanted.Count)
if ($wanted.Count -eq 0) {
    Say 'upgrade-dicts: FILES_DICTS is EMPTY, so a run would transfer nothing and still say COMPLETE.'
    exit 4
}

function Invoke-Sd {
    # NEVER "Start-Process -Wait": sdwind inherits sd's handles and outlives it,
    # so waiting on the STREAMS waits for the daemon.  Wait on the PROCESS.
    # Measured twice on 15 Aug 2026 - adopt-account.ps1's Invoke-Sd has it.
    param([string[]] $SdArgs, [int] $TimeoutMs = 300000)

    $out = Join-Path $env:TEMP ("sd-updict-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-updict-err-$PID.txt")
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru `
                       -RedirectStandardOutput $out -RedirectStandardError $err
    $exited = $p.WaitForExit($TimeoutMs)
    $text = ''
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) {
            $text += (Get-Content $f -Raw)
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $exited) {
        return [pscustomobject]@{ Code = 1; Text = "sd $SdArgs did not finish in $($TimeoutMs / 1000)s" }
    }
    return [pscustomobject]@{ Code = $p.ExitCode; Text = "$text".Trim() }
}

function Test-SdRunning { return $null -ne (Get-Process sdwind -ErrorAction SilentlyContinue) }

function Wait-SdRunning {
    # "sd -start" forks and returns before sdwind appears, so looking once wins
    # the race on an idle machine and loses it on a busy one.  Measured
    # 15 Aug 2026; adopt-account.ps1's Wait-SdRunning has the whole story.
    param([int] $TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-SdRunning) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (Test-SdRunning)
}

# --- place the build input ---------------------------------------------------

$placed = $false
try {
    if (Test-Path -LiteralPath $dstDict) {
        Say "upgrade-dicts: $dstDict was already there - a previous run left it; replacing"
        Remove-Item -LiteralPath $dstDict -Recurse -Force
    }
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $srcDict -Destination $dstDict -Recurse -Force
    $placed = $true
    $n = @(Get-ChildItem -LiteralPath $dstDict -File).Count
    Say ("upgrade-dicts: placed {0} ({1} record(s))" -f $dstDict, $n)
    if ($n -ne $wanted.Count) {
        Say ("upgrade-dicts: the copy has {0} record(s), the source has {1} - refusing" -f
             $n, $wanted.Count)
        throw 'incomplete copy of FILES_DICTS'
    }
}
catch {
    Say "upgrade-dicts: could not place FILES_DICTS - $($_.Exception.Message)"
    if ($placed) { Remove-Item -LiteralPath $dstDir -Recurse -Force -ErrorAction SilentlyContinue }
    exit 1
}

# --- make sure there is a server ---------------------------------------------

$weStartedIt = $false
$result = 1
try {
    if (-not (Test-SdRunning)) {
        $r = Invoke-Sd @('-start')
        if (-not (Wait-SdRunning)) {
            Say 'upgrade-dicts: SD would not start, so the dictionaries were not written'
            Say ("  sd -start exited {0}: {1}" -f $r.Code, $r.Text)
            $result = 3
            throw 'no server'
        }
        $weStartedIt = $true
    }

    # --- WRITE_INSTALL_DICTS -------------------------------------------------
    #
    # Separate arguments and -internal, exactly as bootstrap.py runs it.
    # NO.PAGE matters: without it the program pages and waits for a keypress
    # that no installer will ever send.
    Say 'upgrade-dicts: sd -internal RUN gpl.bp WRITE_INSTALL_DICTS NO.PAGE'
    $w = Invoke-Sd @('-internal', 'RUN', 'gpl.bp', 'WRITE_INSTALL_DICTS', 'NO.PAGE')
    Say ("  exit {0}" -f $w.Code)
    Say '  --- output ---'
    foreach ($l in ("$($w.Text)" -split "`r?`n")) { if ($l.Trim()) { Say ("  | " + $l) } }
    Say '  --- end ---'

    # ANCHORED ON THE WORDING THE PROGRAM PRINTS ON THE POSITIVE PATH, and on a
    # COUNT rather than only on a word.  "COMPLETE" is its last line and
    # "DICTIONARY: <file> <record>" is printed once per record transferred, so
    # the number of those lines is the number of records that actually moved.
    # A run that opened nothing and stopped early prints neither.
    $moved = @(("$($w.Text)" -split "`r?`n") | Where-Object { $_ -match '^\s*DICTIONARY:\s' }).Count
    $complete = "$($w.Text)" -match '(?m)^\s*COMPLETE\s*$'

    # AND THE CONTROL: the wording it prints when it refuses.  A step where the
    # positive pattern matches AND one of these appears is not a pass either.
    $bad = @()
    foreach ($pat in @('ERROR OPENING FILE', 'PROCESS ABORTED', 'READLIST EMPTY',
                       'NO DIRECTORY RECORDS FOUND', 'ERROR CANNOT OPEN',
                       'CANNOT READ TRANSFER_FILE',
                       'Command requires administrator privileges')) {
        if ("$($w.Text)" -match [regex]::Escape($pat)) { $bad += $pat }
    }

    Say ("upgrade-dicts: {0} of {1} record(s) transferred; COMPLETE={2}" -f
         $moved, $wanted.Count, $complete)

    if ($bad.Count -gt 0) {
        Say ("upgrade-dicts: the program reported: {0}" -f ($bad -join '; '))
        throw 'WRITE_INSTALL_DICTS refused'
    }
    if (-not $complete) {
        Say 'upgrade-dicts: WRITE_INSTALL_DICTS did not reach COMPLETE'
        throw 'incomplete'
    }
    if ($moved -ne $wanted.Count) {
        Say 'upgrade-dicts: it finished, but not every record moved - treating as a failure'
        throw 'short transfer'
    }

    # --- THIRD.COMPILE -------------------------------------------------------
    #
    # Dictionary I-types are compiled.  bootstrap.py runs this immediately
    # after WRITE_INSTALL_DICTS and checks it the same way: THIRD.COMPILE
    # prints no "n error(s)" summary, so only the warning check applies.
    Say 'upgrade-dicts: sd -internal THIRD.COMPILE'
    $c = Invoke-Sd @('-internal', 'THIRD.COMPILE')
    Say ("  exit {0}" -f $c.Code)
    foreach ($l in ("$($c.Text)" -split "`r?`n")) { if ($l.Trim()) { Say ("  | " + $l) } }

    # "is not assigned a value" is a WARNING at compile time and an abort at
    # run time, in a program that may not run until much later - the ERRGEN
    # trap.  bootstrap.py's check_compile() refuses a build for it.
    $warn = @(("$($c.Text)" -split "`r?`n") | Where-Object { $_ -match 'is not assigned a value' })
    $errs = @(("$($c.Text)" -split "`r?`n") |
              Where-Object { $_.Trim() -match 'error\(s\)$' -and $_.Trim() -notmatch '^0 ' })
    if ($warn.Count -gt 0) {
        Say ("upgrade-dicts: THIRD.COMPILE produced {0} 'not assigned a value' warning(s)" -f $warn.Count)
        throw 'compile warnings'
    }
    if ($errs.Count -gt 0) {
        Say ("upgrade-dicts: THIRD.COMPILE reported: {0}" -f ($errs -join '; '))
        throw 'compile errors'
    }

    Say ("upgrade-dicts: DONE - {0} dictionary record(s) written and compiled" -f $moved)
    $result = 0
}
catch {
    # 3 is set BEFORE the throw in the no-server case and has to survive; every
    # other path is a plain failure.  Written as one test rather than two so
    # there is no order in which they can disagree.
    if ($result -ne 3) { $result = 1 }
    Say "upgrade-dicts: FAILED - $($_.Exception.Message)"
}
finally {
    # THE DATA TREE MUST NOT KEEP A BUILD INPUT, whatever happened above -
    # bootstrap.py removes it in a finally for the same reason.  A gplbld
    # directory left inside sdsys is exactly the thing the data-tree-holds-data
    # decision forbids, and nothing later would notice it.
    if ($placed) {
        try {
            Remove-Item -LiteralPath $dstDir -Recurse -Force -ErrorAction Stop
            Say "upgrade-dicts: removed $dstDir"
        }
        catch {
            Say "upgrade-dicts: COULD NOT REMOVE $dstDir - delete it by hand"
        }
    }

    # Leave the machine as it was found.
    if ($weStartedIt) { $null = Invoke-Sd @('-stop') }
}

exit $result
