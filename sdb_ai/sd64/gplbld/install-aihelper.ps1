# install-aihelper.ps1 - create, start and remove the AI helper service sd-ai
#
#   powershell -ExecutionPolicy Bypass -File "C:\Program Files\SD\install-aihelper.ps1" -Install [-AppDir <dir>] [-DataDir <dir>]
#   powershell -ExecutionPolicy Bypass -File "C:\Program Files\SD\install-aihelper.ps1" -Remove
#
# Elevated.  Exit 0 done, 1 failed, 2 could not be attempted (not elevated, no helper in the program folder).
#
# 13 Nov 26 Windows port - RELEASE_1.1 246, the owner's ruling the same day ("python not being an integral part of windows argues for the c
# helper"): the helper is the native program sd-ai.exe, so the service runs it directly and this no longer looks for Python.  Exit 3 (no
# all-users Python, no service) is gone with it.
#
# 13 Nov 26 Windows port - RELEASE_1.1 246, Linux's AI helper (S.69 step 2; design .claude/design-ai-helper-20261113.md 3.1, 3.4, 3.10; the owner's answers
# of 13 Nov 2026).  Linux's installer makes the OS user sdai, puts sd-ai, sd-ai-ctl, ai-providers and ai-context root-owned in /usr/local/lib/sd-ai, keeps
# /var/lib/sd-ai{,/keys,/state} sdai's own (kept by an upgrade) and enables sd-ai.socket.  Here:
#   - THE PROGRAM is <AppDir>\lib\sd-ai\sd-ai.exe, helper and administrator's client in one, beside ai-providers and ai-context (the installer's
#     [Files]; Program Files: only administrators may change it).
#   - THE ACCOUNT is the virtual account NT SERVICE\sd-ai (owner, Q3): no password to keep, no interactive sign-in, a SID of its own for the access lists
#     and a profile of its own for DPAPI (the keys are encrypted in ITS user scope, owner Q4).
#   - THE SERVICE sd-ai runs "<AppDir>\lib\sd-ai\sd-ai.exe --service", start auto (it holds the pipe's name from boot, so nobody else can make \\.\pipe\sd-ai first), restricted SID (Linux ProtectSystem=strict + ReadWritePaths: it may write only where its
#     own SID is granted), one privilege, SeChangeNotifyPrivilege (Linux CapabilityBoundingSet=), restarted twice on failure.
#   - THE STATE is <DataDir>\ai: SYSTEM full, the service modify, Administrators read (the log and the settings); keys\ is SYSTEM and the service only.  Kept
#     by an upgrade, as Linux keeps /var/lib/sd-ai; it goes when the database does.  ai.conf is NOT written: none means no provider, the AI off as delivered.
#   - The Application event log source sd-ai, which the service writes to when it cannot start (a pipe of its name already made by someone else).
# NOTHING ELSE IS TURNED ON: no provider, no key, nobody in sdaiusers (sync-route-groups.ps1 makes the group empty).  The administrator does that (set.ai,
# tool.ai, modify.account NAME ai-on).
# AN ADMINISTRATOR CAN OBTAIN THE KEY, AND ON WINDOWS SDSYS IS AN ELEVATED ADMINISTRATOR (owner, Q5): it can take the key files, run code as the service,
# replace the program or edit ai-providers.  Linux's sdsys can do none of that.  The installation documentation says so.

param(
    [switch] $Install,
    [switch] $Remove,
    [string] $AppDir = '',
    [string] $DataDir = ''
)

# RELEASE_1.1 111: a person may run this by hand from a PowerShell 7 window; Windows PowerShell's own module folders, SET, not removed.
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"

$ErrorActionPreference = 'Continue'

$SvcName    = 'sd-ai'
$SvcAccount = 'NT SERVICE\sd-ai'
$SvcDisplay = 'SD Core AI helper'
$SvcDesc    = 'Sends the AI requests SD accounts are allowed to make to the provider the SD administrator chose, and holds its key. Off until the administrator turns it on.'
$PipePath   = '\\.\pipe\sd-ai'
$sc         = Join-Path $env:SystemRoot 'System32\sc.exe'

# Is the pipe there?  From the pipe namespace's LISTING: Test-Path on the name would open it, which is a connection the helper serves.
function Test-AiPipe {
    try { return (@([System.IO.Directory]::GetFiles('\\.\pipe\')) -contains $PipePath) } catch { return $false }
}

# Not param defaults: $PSScriptRoot is empty in a param default (install-service.ps1 records the cost).
if ($AppDir -eq '') { $AppDir = $PSScriptRoot }
if ($DataDir -eq '') { $DataDir = Join-Path $env:ProgramData 'SD' }
$lib   = Join-Path $AppDir 'lib\sd-ai'
$state = Join-Path $DataDir 'ai'

$logPath = Join-Path $DataDir 'install-aihelper.log'
try { Start-Transcript -Path $logPath -Append -Force | Out-Null } catch { }

function Say($m) { Write-Output "install-aihelper: $m" }
Say ("{0}  {1}  AppDir={2}  DataDir={3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
     $(if ($Install) { '-Install' } elseif ($Remove) { '-Remove' } else { '(no switch)' }), $AppDir, $DataDir)

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Say 'not elevated - creating or removing a service needs an elevated token'
    exit 2
}
if (-not ($Install -or $Remove)) {
    Say 'pass -Install or -Remove'
    exit 2
}

function Get-Svc { return (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) }

# Prints, so it RETURNS NOTHING: the answer is $script:SvcRemoved (a function that prints and returns hands its caller an array of both).
$script:SvcRemoved = $false
function Remove-Svc {
    $script:SvcRemoved = $false
    $s = Get-Svc
    if ($null -eq $s) { $script:SvcRemoved = $true; return }
    if ($s.Status -ne 'Stopped') {
        Say "stopping $SvcName"
        Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            $s = Get-Svc
            if ($null -eq $s -or $s.Status -eq 'Stopped') { break }
            Start-Sleep -Milliseconds 500
        }
    }
    & $sc delete $SvcName | Out-Null
    if ($LASTEXITCODE -ne 0) { Say "sc delete failed, exit $LASTEXITCODE"; return }
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline -and $null -ne (Get-Svc)) { Start-Sleep -Milliseconds 300 }
    Say "$SvcName removed"
    $script:SvcRemoved = $true
}

if ($Remove) {
    Remove-Svc
    try { if ([System.Diagnostics.EventLog]::SourceExists($SvcName)) { [System.Diagnostics.EventLog]::DeleteEventSource($SvcName) } } catch { }
    if ($script:SvcRemoved) { exit 0 } else { exit 1 }
}

# --- install -------------------------------------------------------------------
$helper = Join-Path $lib 'sd-ai.exe'
foreach ($f in @('sd-ai.exe', 'ai-providers', 'ai-context')) {
    if (-not (Test-Path -LiteralPath (Join-Path $lib $f) -PathType Leaf)) { Say "no $(Join-Path $lib $f) - was the install complete?"; exit 2 }
}

# The service is made afresh (an earlier build ran the Python helper; an upgrade may have moved the program), with New-Service so that the command
# line's quotes reach the SCM as written (sc.exe binPath= through PowerShell 5.1 loses embedded quotes), then given its account and hardening with
# sc.exe, whose words have no quotes inside.
Remove-Svc
if (-not $script:SvcRemoved) { exit 1 }
$bin = '"' + $helper + '" --service'
try {
    New-Service -Name $SvcName -BinaryPathName $bin -DisplayName $SvcDisplay -Description $SvcDesc -StartupType Automatic -ErrorAction Stop | Out-Null
} catch {
    Say ("New-Service failed: " + $_.Exception.Message)
    exit 1
}
& $sc config $SvcName obj= $SvcAccount | Out-Null
if ($LASTEXITCODE -ne 0) { Say "sc config obj= $SvcAccount failed, exit $LASTEXITCODE"; exit 1 }
& $sc sidtype $SvcName restricted | Out-Null
if ($LASTEXITCODE -ne 0) { Say "sc sidtype restricted failed, exit $LASTEXITCODE"; exit 1 }
& $sc privs $SvcName SeChangeNotifyPrivilege | Out-Null
if ($LASTEXITCODE -ne 0) { Say "sc privs failed, exit $LASTEXITCODE"; exit 1 }
& $sc failure $SvcName reset= 86400 actions= restart/5000/restart/15000/none/0 | Out-Null

# The state directory, now that the account exists (icacls resolves NT SERVICE\sd-ai only for an installed service).
$keys = Join-Path $state 'keys'
$cnt  = Join-Path $state 'state'
foreach ($d in @($state, $keys, $cnt)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
& icacls $state /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' "${SvcAccount}:(OI)(CI)M" '*S-1-5-32-544:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { Say "icacls on $state failed, exit $LASTEXITCODE"; exit 1 }
& icacls $keys /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' "${SvcAccount}:(OI)(CI)M" | Out-Null
if ($LASTEXITCODE -ne 0) { Say "icacls on $keys failed, exit $LASTEXITCODE"; exit 1 }

try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($SvcName)) { New-EventLog -LogName Application -Source $SvcName }
} catch { Say ("the event log source could not be registered: " + $_.Exception.Message) }

Start-Service -Name $SvcName -ErrorAction SilentlyContinue
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    $s = Get-Svc
    if ($null -ne $s -and $s.Status -eq 'Running' -and (Test-AiPipe)) { break }
    Start-Sleep -Milliseconds 500
}

# WHAT WAS MADE, read back rather than assumed.
$w = Get-CimInstance -ClassName Win32_Service -Filter "Name='$SvcName'" -ErrorAction SilentlyContinue
$s = Get-Svc
$pipe = Test-AiPipe
Say ("service: state={0}  account={1}  start={2}" -f $(if ($s) { $s.Status } else { 'absent' }), $(if ($w) { $w.StartName } else { '?' }), $(if ($w) { $w.StartMode } else { '?' }))
Say ("command: {0}" -f $(if ($w) { $w.PathName } else { '?' }))
Say ("pipe {0}: {1}" -f $PipePath, $(if ($pipe) { 'present' } else { 'ABSENT' }))
Say ("state: {0}" -f (((& icacls $state) | Select-Object -First 4) -join ' | '))
Say ("keys:  {0}" -f (((& icacls $keys) | Select-Object -First 3) -join ' | '))
if ($null -ne $s -and $s.Status -eq 'Running' -and $pipe -and $w -and $w.StartName -eq $SvcAccount) {
    Say 'the AI helper is installed and running; the AI stays off until the administrator chooses a provider, sets its key and opens an account gate'
    exit 0
}
Say 'THE AI HELPER IS NOT RUNNING AS IT SHOULD (above); the Application event log, source sd-ai, may say why'
exit 1
