<#
.SYNOPSIS
    Can LocalSystem actually reach and USE the all-users Python?  Runs the
    measurement as SYSTEM through a scheduled task and reports what it read.

.DESCRIPTION
    ***THE QUESTION, AND WHY IT IS THE LAST ONE BEFORE CODE.***
    PROJECT_STATUS.md section 8, constraint 1, and section 5.27's helper.  An
    API session runs as LocalSystem, so sd.exe starts sdpy.exe as LocalSystem,
    so sdpy.exe loads python3.dll as LocalSystem.  Every part of the helper's
    identity story rests on that last step working, and NOBODY HAS RUN ANYTHING
    AS SYSTEM AGAINST THIS INSTALL.  Handoff 47: "it almost certainly can - but
    'almost certainly' is what this project punishes".

    ***WHY IT CANNOT BE ANSWERED BY REASONING ABOUT ACLs.***  Program Files is
    readable by Everyone, so the ACL half is not in doubt.  The parts that are:

      - SYSTEM has a DIFFERENT ENVIRONMENT.  No per-user PATH, no WindowsApps
        aliases, a different %TEMP%, and no user profile - and python.exe
        initialises site-packages and sys.prefix from where it finds itself.
      - SYSTEM has a DIFFERENT REGISTRY VIEW for HKCU.  The detector rejects
        HKCU already, but a reader should see SYSTEM's own answer, not infer it.
      - A 32-bit host would see HKLM through WOW6432Node and find nothing.
        The bitness is therefore printed rather than assumed.

    ***HOW IT RUNS AS SYSTEM.***  A scheduled task with a ServiceAccount
    principal, created, run once, and deleted in a finally block.  The driver
    half must be ELEVATED to register that task; the payload half must be
    SYSTEM, and REFUSES OUT LOUD if it is anything else - a payload that ran as
    the interactive user would pass every row below and mean nothing.

    ***WHAT IT PRINTS.***  The payload writes one file; the driver prints that
    file VERBATIM before it parses anything, so a reader sees the measurement
    rather than this script's opinion of it.  Every leg is a ROW| line with its
    own evidence, including the legs whose answer is "I could not measure this".

    ***AND IT CHECKS THE FILE'S ENCODING BEFORE READING IT.***  Handoff 47:
    the suite's per-step logs came out UTF-16, where a plain grep reports
    0 PASS / 0 FAIL and reads exactly like a run that did nothing.  The payload
    writes UTF-8 with no BOM and the driver reports the first bytes it found.

    ***IT CHANGES NOTHING AND INSTALLS NOTHING.***  It reads the registry,
    reads files, and runs two programs that are already on the machine.  The
    scheduled task is the only thing it creates and it is removed on every
    path, including failure.

.PARAMETER Payload
    Internal.  Run the measurement as SYSTEM and write results to this path.
    Not for hand use: run without it and the driver arranges this half.

.PARAMETER TimeoutSeconds
    How long the driver waits for the SYSTEM task.  Default 120.  A timeout is
    reported as a timeout, never as a failed measurement.

.OUTPUTS
    Exit 0  every decisive leg was measured and passed
    Exit 1  a decisive leg FAILED - the helper's assumption is wrong
    Exit 2  the question could not be asked (not elevated, no Python, no task)
    Exit 3  nothing failed, but a decisive leg was NOT MEASURED

.EXAMPLE
    C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\probe-pysystem.ps1

    Run it in an ELEVATED PowerShell.  It needs no run token, no install, and
    no cycle.
#>

[CmdletBinding()]
param(
    [string] $Payload = '',
    [int]    $TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

$TaskName   = 'SDProbePySystem'
$ScriptPath = $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------

# A row is the unit of evidence.  Detail is not optional: a PASS with nothing
# under it is the thing section 0 keeps paying for.
function New-Row([string]$name, [string]$state, [string]$detail) {
    return ('ROW|' + $name + '|' + $state + '|' + $detail)
}

function Get-HklmPythonEntries {
    $out = @()
    $root = 'HKLM:\SOFTWARE\Python\PythonCore'
    if (-not (Test-Path -LiteralPath $root)) { return $out }
    foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
        $ip  = ''
        $ipK = Join-Path $k.PSPath 'InstallPath'
        try {
            if (Test-Path -LiteralPath $ipK) {
                $ip = (Get-ItemProperty -LiteralPath $ipK -ErrorAction Stop).'(default)'
                if ($null -eq $ip) { $ip = '' }
            }
        } catch { $ip = '' }
        $out += [pscustomobject]@{
            Version = $k.PSChildName
            Path    = $ip
            Exists  = ($ip -ne '' -and (Test-Path -LiteralPath $ip))
        }
    }
    return $out
}

# ===========================================================================
# PAYLOAD - this half runs as SYSTEM
# ===========================================================================

if ($Payload -ne '') {

    $lines = @()
    $lines += '=== probe-pysystem PAYLOAD ==============================='
    $lines += ('  started      : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    $lines += ('  script       : ' + $ScriptPath)
    $lines += ('  output       : ' + $Payload)

    # --- A. WHO AM I.  THE NULL-CASE REFUSAL, AND IT IS THE WHOLE PROBE. ---
    #
    # Everything below is a claim about LocalSystem.  If this half is running
    # as anyone else, every row is true of the wrong identity and reads exactly
    # like a pass.  So the identity is measured FIRST and from the token, not
    # from the fact that a task was configured to use it.
    $who = ''
    $sid = ''
    try {
        $id  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $who = $id.Name
        $sid = $id.User.Value
    } catch {
        $who = '(could not read token: ' + $_.Exception.Message + ')'
    }
    $lines += ('  identity     : ' + $who + '  SID ' + $sid)
    $lines += ('  64-bit proc  : ' + [Environment]::Is64BitProcess)
    $lines += ('  PSVersion    : ' + $PSVersionTable.PSVersion.ToString())
    $lines += ''

    # S-1-5-18 is LocalSystem.  The SID is the test; the display name is
    # localised and "NT AUTHORITY\SYSTEM" is not what every machine prints.
    if ($sid -ne 'S-1-5-18') {
        $lines += (New-Row 'running as LocalSystem' 'FAIL' ("token is " + $who + " (" + $sid + "), not S-1-5-18 - NOTHING BELOW WAS MEASURED"))
        $lines += '=== END (refused: wrong identity) ========================='
        [IO.File]::WriteAllLines($Payload, $lines, (New-Object System.Text.UTF8Encoding($false)))
        exit 2
    }
    $lines += (New-Row 'running as LocalSystem' 'PASS' ($who + ' ' + $sid))

    # --- C. THE PEP 514 HIVE, READ BY SYSTEM ITSELF ---
    $installPath = ''
    try {
        $entries = Get-HklmPythonEntries
        if ($entries.Count -eq 0) {
            $lines += (New-Row 'HKLM PythonCore readable as SYSTEM' 'FAIL' 'no entries under HKLM\SOFTWARE\Python\PythonCore')
        } else {
            foreach ($e in $entries) {
                $lines += ('    hive entry : ' + $e.Version + '  ' + $e.Path + '  exists=' + $e.Exists)
            }
            $usable = @($entries | Where-Object { $_.Exists })
            if ($usable.Count -eq 0) {
                $lines += (New-Row 'HKLM PythonCore readable as SYSTEM' 'FAIL' 'entries present but no InstallPath exists on disk')
            } else {
                $installPath = $usable[0].Path.TrimEnd('\')
                $lines += (New-Row 'HKLM PythonCore readable as SYSTEM' 'PASS' ($usable[0].Version + ' -> ' + $installPath))
            }
        }
    } catch {
        $lines += (New-Row 'HKLM PythonCore readable as SYSTEM' 'FAIL' ('read threw: ' + $_.Exception.Message))
    }

    # HKCU as SYSTEM.  NOT a decisive row - it is the contrast that shows why
    # the detector judges by hive.  SYSTEM's HKCU is the service profile's, so
    # the per-user 3.13 this box has is expected to be INVISIBLE here.
    try {
        $cu = 'HKCU:\SOFTWARE\Python\PythonCore'
        if (Test-Path -LiteralPath $cu) {
            $names = @(Get-ChildItem -LiteralPath $cu -ErrorAction Stop | ForEach-Object { $_.PSChildName })
            $lines += ('    HKCU (contrast, not detection): ' + ($names -join ', '))
        } else {
            $lines += '    HKCU (contrast, not detection): absent - SYSTEM does not see the interactive user''s 3.13'
        }
    } catch {
        $lines += ('    HKCU (contrast, not detection): could not read - ' + $_.Exception.Message)
    }

    if ($installPath -eq '') {
        $lines += ''
        $lines += 'NO INSTALL PATH: the legs below need one and were NOT MEASURED.'
        $lines += '=== END (refused: nothing to measure) ====================='
        [IO.File]::WriteAllLines($Payload, $lines, (New-Object System.Text.UTF8Encoding($false)))
        exit 2
    }

    # --- D. TRAVERSE AND PRESENCE ---
    $pyExe  = Join-Path $installPath 'python.exe'
    $dllStable = Join-Path $installPath 'python3.dll'
    $libOs  = Join-Path $installPath 'Lib\os.py'
    $missing = @()
    foreach ($p in @($pyExe, $dllStable, $libOs)) {
        if (-not (Test-Path -LiteralPath $p)) { $missing += $p }
    }
    $concrete = @()
    try {
        $concrete = @(Get-ChildItem -LiteralPath $installPath -Filter 'python3??.dll' -ErrorAction Stop |
                      ForEach-Object { $_.Name })
    } catch { }
    if ($missing.Count -eq 0) {
        $lines += (New-Row 'SYSTEM can traverse the install' 'PASS' ('python.exe, python3.dll, Lib\os.py all present; concrete DLL: ' + ($concrete -join ', ')))
    } else {
        $lines += (New-Row 'SYSTEM can traverse the install' 'FAIL' ('not reachable: ' + ($missing -join '; ')))
    }

    # --- E. READ, NOT MERELY SEE ---
    #
    # Test-Path needs traverse.  Opening the file needs READ, and those are
    # separate ACEs - a directory SYSTEM can list and a DLL it cannot open
    # would pass leg D and break the helper.
    try {
        $fs = [IO.File]::Open($dllStable, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $buf = New-Object byte[] 2
            $n = $fs.Read($buf, 0, 2)
            $mz = ($n -eq 2 -and $buf[0] -eq 0x4D -and $buf[1] -eq 0x5A)
            if ($mz) {
                $lines += (New-Row 'SYSTEM can READ python3.dll' 'PASS' ('opened ' + $dllStable + ', first 2 bytes MZ, length ' + $fs.Length))
            } else {
                $lines += (New-Row 'SYSTEM can READ python3.dll' 'FAIL' ('opened but read ' + $n + ' bytes and no MZ header'))
            }
        } finally { $fs.Close() }
    } catch {
        $lines += (New-Row 'SYSTEM can READ python3.dll' 'FAIL' ('open threw: ' + $_.Exception.Message))
    }

    # --- F. THE INTERPRETER RUNS AS SYSTEM, AND FINDS ITS STANDARD LIBRARY ---
    #
    # ANCHOR: PYOK is printed ONLY by the interpreter executing our argument.
    # It cannot appear in "is not recognized", in a Traceback, or in an echo of
    # the command - which is the trap section 0 names.  The disqualifiers are
    # checked as well, so a line carrying both is not a pass either.
    $pyOut = ''
    try {
        $code = 'import sys, os; print("PYOK " + sys.version.split()[0] + " prefix=" + sys.prefix + " os=" + os.__file__)'
        $tmpO = [IO.Path]::GetTempFileName()
        $tmpE = [IO.Path]::GetTempFileName()
        $p = Start-Process -FilePath $pyExe -ArgumentList @('-c', $code) -NoNewWindow -Wait -PassThru `
                           -RedirectStandardOutput $tmpO -RedirectStandardError $tmpE
        $so = ''
        $se = ''
        if (Test-Path -LiteralPath $tmpO) { $so = (Get-Content -LiteralPath $tmpO -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path -LiteralPath $tmpE) { $se = (Get-Content -LiteralPath $tmpE -Raw -ErrorAction SilentlyContinue) }
        if ($null -eq $so) { $so = '' }
        if ($null -eq $se) { $se = '' }
        Remove-Item -LiteralPath $tmpO, $tmpE -Force -ErrorAction SilentlyContinue
        $pyOut = ($so + $se).Trim()
        $lines += ('    python.exe -c  : exit ' + $p.ExitCode)
        foreach ($l in ($pyOut -split "`r?`n")) { if ($l -ne '') { $lines += ('      | ' + $l) } }

        $bad = ($pyOut -match 'Traceback' -or $pyOut -match 'ModuleNotFoundError' -or
                $pyOut -match 'is not recognized' -or $pyOut -match 'Fatal Python error')
        if ($pyOut -match 'PYOK ' -and -not $bad -and $p.ExitCode -eq 0) {
            $lines += (New-Row 'python.exe runs as SYSTEM' 'PASS' (($pyOut -split "`r?`n" | Where-Object { $_ -match 'PYOK ' } | Select-Object -First 1)))
        } elseif ($bad) {
            $lines += (New-Row 'python.exe runs as SYSTEM' 'FAIL' 'a disqualifier appeared in the output - see the transcript above')
        } else {
            $lines += (New-Row 'python.exe runs as SYSTEM' 'FAIL' ('no PYOK marker; exit ' + $p.ExitCode))
        }
    } catch {
        $lines += (New-Row 'python.exe runs as SYSTEM' 'FAIL' ('could not start python.exe: ' + $_.Exception.Message))
    }

    # --- G. THE ROUTE THE HELPER WILL ACTUALLY TAKE ---
    #
    # probe-pylimited-limited.exe is the constraint-5 binary: native UCRT64,
    # linked -lpython3 with Py_LIMITED_API, exactly what sdpy.exe would be.
    # Running THAT as SYSTEM is the decisive leg - leg F proves python.exe
    # works, which is not the same as our own binary binding python3.dll.
    #
    # It is build output and is not tracked, so "not built" is reported as NOT
    # MEASURED.  A leg that did not run must never count as a pass.
    $limited = Join-Path (Split-Path -Parent $ScriptPath) 'probe-pylimited-limited.exe'
    if (-not (Test-Path -LiteralPath $limited)) {
        $lines += (New-Row 'UCRT64 binary binds python3.dll as SYSTEM' 'SKIP' ('not built: ' + $limited))
    } else {
        try {
            $tmpO = [IO.Path]::GetTempFileName()
            $tmpE = [IO.Path]::GetTempFileName()
            $p2 = Start-Process -FilePath $limited -NoNewWindow -Wait -PassThru `
                                -RedirectStandardOutput $tmpO -RedirectStandardError $tmpE
            $so = ''
            $se = ''
            if (Test-Path -LiteralPath $tmpO) { $so = (Get-Content -LiteralPath $tmpO -Raw -ErrorAction SilentlyContinue) }
            if (Test-Path -LiteralPath $tmpE) { $se = (Get-Content -LiteralPath $tmpE -Raw -ErrorAction SilentlyContinue) }
            if ($null -eq $so) { $so = '' }
            if ($null -eq $se) { $se = '' }
            Remove-Item -LiteralPath $tmpO, $tmpE -Force -ErrorAction SilentlyContinue
            $lo = ($so + $se).Trim()
            $lines += ('    probe-pylimited-limited.exe : exit ' + $p2.ExitCode)
            foreach ($l in ($lo -split "`r?`n")) { if ($l -ne '') { $lines += ('      | ' + $l) } }

            # ANCHOR on the success sentence the probe prints on the positive
            # path only, and on a bound DLL having been READ BACK FROM THE
            # LOADER.  "NONE FOUND" is that probe's own null-case refusal.
            $okText  = ($lo -match 'interpreter started, answered, and finalised cleanly')
            $bound   = ($lo -match 'bound:\s+python')
            $noneFnd = ($lo -match 'NONE FOUND')
            if ($okText -and $bound -and -not $noneFnd -and $p2.ExitCode -eq 0) {
                $b = @($lo -split "`r?`n" | Where-Object { $_ -match 'bound:' })
                $lines += (New-Row 'UCRT64 binary binds python3.dll as SYSTEM' 'PASS' (($b -join ' ; ').Trim()))
            } else {
                $lines += (New-Row 'UCRT64 binary binds python3.dll as SYSTEM' 'FAIL' ('exit ' + $p2.ExitCode + '; success sentence=' + $okText + ' bound=' + $bound + ' noneFound=' + $noneFnd))
            }
        } catch {
            $lines += (New-Row 'UCRT64 binary binds python3.dll as SYSTEM' 'FAIL' ('could not start it: ' + $_.Exception.Message))
        }
    }

    # --- H. CONTRAST: what PATH says to SYSTEM ---
    #
    # Not a decisive row.  It is here because PATH got this question wrong in
    # BOTH directions for the interactive user (section 8), and a reader will
    # want to know what it says to SYSTEM before trusting anything that asks.
    try {
        $cmd = (Get-Command python.exe -ErrorAction SilentlyContinue)
        if ($null -eq $cmd) {
            $lines += '    PATH (contrast, not detection): python.exe not on SYSTEM''s PATH'
        } else {
            $lines += ('    PATH (contrast, not detection): python.exe -> ' + $cmd.Source)
        }
    } catch { }

    $lines += ''
    $lines += ('=== END ' + (Get-Date -Format 'HH:mm:ss') + ' ================================')
    [IO.File]::WriteAllLines($Payload, $lines, (New-Object System.Text.UTF8Encoding($false)))
    exit 0
}

# ===========================================================================
# DRIVER - this half must be elevated
# ===========================================================================

Write-Output 'probe-pysystem: can LocalSystem reach the all-users Python?'
Write-Output ''
Write-Output ('  script       : ' + $ScriptPath)
Write-Output ('  driver as    : ' + [System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-Output ('  64-bit proc  : ' + [Environment]::Is64BitProcess)
Write-Output ('  PSVersion    : ' + $PSVersionTable.PSVersion.ToString())

$elevated = (New-Object System.Security.Principal.WindowsPrincipal(
                [System.Security.Principal.WindowsIdentity]::GetCurrent())
            ).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Output ('  elevated     : ' + $elevated)

if (-not $elevated) {
    Write-Output ''
    Write-Output 'probe-pysystem: COULD NOT ASK - registering a SYSTEM task needs elevation.'
    Write-Output '  Run this in an ELEVATED PowerShell.  Nothing was measured.'
    exit 2
}

# Refuse before creating anything if there is no all-users Python: the probe
# would otherwise register a task, run it, and report a failure that is a fact
# about this machine's Python rather than about SYSTEM's reach.
$pre = @(Get-HklmPythonEntries | Where-Object { $_.Exists })
if ($pre.Count -eq 0) {
    Write-Output ''
    Write-Output 'probe-pysystem: COULD NOT ASK - no all-users Python under HKLM\SOFTWARE\Python\PythonCore.'
    Write-Output '  Install one at machine scope first; python-detect.ps1 is the detector.'
    exit 2
}
Write-Output ('  target       : ' + $pre[0].Version + ' at ' + $pre[0].Path)

$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $env:SystemRoot ('Temp\sd-probe-pysystem-' + $stamp + '.txt')
Write-Output ('  payload out  : ' + $outFile)

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $ScriptPath + '" -Payload "' + $outFile + '"'
Write-Output ('  task action  : ' + $psExe + ' ' + $argLine)
Write-Output ''

$created = $false
try {
    # Remove a leftover from an interrupted earlier run before registering.
    $old = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -ne $old) {
        Write-Output ('  note: a previous ' + $TaskName + ' existed and was removed')
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $argLine
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                                              -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal `
                           -Settings $settings -Description 'SD probe: can LocalSystem reach Python (temporary)' | Out-Null
    $created = $true
    Write-Output ('  registered   : ' + $TaskName + ' as SYSTEM')

    Start-ScheduledTask -TaskName $TaskName
    Write-Output '  started, waiting...'

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $state    = ''
    while ((Get-Date) -lt $deadline) {
        $state = (Get-ScheduledTask -TaskName $TaskName).State
        if ($state -eq 'Ready') { break }
        Start-Sleep -Milliseconds 500
    }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Output ('  final state  : ' + $state + ', LastTaskResult 0x' + ('{0:X}' -f $info.LastTaskResult))

    if ($state -ne 'Ready') {
        Write-Output ''
        Write-Output ('probe-pysystem: TIMED OUT after ' + $TimeoutSeconds + 's - the task did not finish.')
        Write-Output '  That is a timeout, not a failed measurement.  Nothing below was read.'
        exit 2
    }
}
catch {
    Write-Output ''
    Write-Output ('probe-pysystem: COULD NOT ASK - ' + $_.Exception.Message)
    exit 2
}
finally {
    if ($created) {
        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Output ('  cleaned up   : ' + $TaskName + ' removed')
        } catch {
            Write-Output ('  WARNING: could not remove the task ' + $TaskName + ' - ' + $_.Exception.Message)
        }
    }
}

# --- read the payload's file -----------------------------------------------
#
# ITS ENCODING IS REPORTED BEFORE ITS CONTENT.  Handoff 47: the suite's per-step
# logs came out UTF-16 and a plain grep read 0 PASS / 0 FAIL, which looks exactly
# like a run that did nothing.

if (-not (Test-Path -LiteralPath $outFile)) {
    Write-Output ''
    Write-Output 'probe-pysystem: THE TASK RAN AND WROTE NOTHING.'
    Write-Output ('  expected ' + $outFile)
    Write-Output '  An empty measurement is not a pass.  Nothing is known.'
    exit 2
}

$bytes = [IO.File]::ReadAllBytes($outFile)
if ($bytes.Length -eq 0) {
    Write-Output ''
    Write-Output ('probe-pysystem: THE OUTPUT FILE IS EMPTY - ' + $outFile)
    Write-Output '  An empty measurement is not a pass.  Nothing is known.'
    exit 2
}
$head = ''
$n = [Math]::Min(4, $bytes.Length)
for ($i = 0; $i -lt $n; $i++) { $head = $head + ('{0:X2} ' -f $bytes[$i]) }
$enc = 'UTF-8 / ASCII, no BOM'
if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $enc = 'UTF-16LE - A PLAIN GREP WILL READ NOTHING FROM THIS' }
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $enc = 'UTF-8 with BOM' }

Write-Output ''
Write-Output ('  payload file : ' + $bytes.Length + ' bytes, first bytes ' + $head + '=> ' + $enc)
Write-Output ''
Write-Output '----- what SYSTEM reported, verbatim --------------------------'

$content = Get-Content -LiteralPath $outFile
foreach ($l in $content) { Write-Output $l }

Write-Output '----- end of SYSTEM''s report ---------------------------------'
Write-Output ''

# --- verdict ---------------------------------------------------------------
#
# The decisive legs are the ones the helper rests on.  A SKIP is not a failure
# and is not a pass either: it exits 3, with the leg named.

$rows = @($content | Where-Object { $_ -like 'ROW|*' })
if ($rows.Count -eq 0) {
    Write-Output 'probe-pysystem: THE REPORT CARRIES NO ROWS - the payload did not reach its measurements.'
    Write-Output '  Read the verbatim block above.  Nothing is known.'
    exit 2
}

$pass = 0
$fail = 0
$skip = 0
foreach ($r in $rows) {
    $parts = $r.Split('|')
    $name  = $parts[1]
    $state = $parts[2]
    $detail = ''
    if ($parts.Length -gt 3) { $detail = $parts[3] }
    Write-Output ('  [' + $state + '] ' + $name)
    if ($detail -ne '') { Write-Output ('          ' + $detail) }
    if     ($state -eq 'PASS') { $pass++ }
    elseif ($state -eq 'SKIP') { $skip++ }
    else                       { $fail++ }
}

Write-Output ''
Write-Output ('probe-pysystem: ' + $pass + ' PASS, ' + $fail + ' FAIL, ' + $skip + ' NOT MEASURED')

if ($fail -gt 0) {
    Write-Output '  A DECISIVE LEG FAILED.  Section 5.27''s helper assumes the opposite; read the rows above'
    Write-Output '  before writing any of sdpy.exe.'
    exit 1
}
if ($skip -gt 0) {
    Write-Output '  Nothing failed, but a leg was NOT MEASURED and the question is not fully answered.'
    Write-Output '  Build probe-pylimited-limited.exe and run this again.'
    exit 3
}
Write-Output '  LocalSystem reaches the all-users Python, reads it, runs it, and binds python3.dll'
Write-Output '  through the stable ABI.  The helper''s identity assumption holds.'
exit 0
