# run-restore-kept.ps1 - the installer's side of "put back, as SDSYS, what a Keep uninstall took away"
#
# 21 Nov 26 Windows port - RELEASE_1.1 370.  Run by sd.iss (RunRestoreKept), ELEVATED, after a Keep reinstall, with its output captured to a
# file the installer reads.  It makes <ProgramData>\SDrestore (administrators only), registers ONE task that runs
# "<program folder>\sdsvc.exe -restore-kept" as SYSTEM, starts it, waits for it, prints the result file, and removes the task and the folder.
# sdsvc.exe -restore-kept (gplsrc/sdsvc/sdrestore.c) mints SDSYS's S4U token and starts sd-restore-kept.ps1 under it; Windows lets only SDSYS
# register the tasks that script registers (row 280), and this is how the install becomes SDSYS (measured 21 Nov 2026, probe-sdsys-taskreg.ps1).
#
# WHAT THE INSTALLER READS, all of it printed here: "RESTORE-RUN: ..." lines about this script's own steps, then the result file verbatim - the
# "RESTORE ..." lines of sd-restore-kept.ps1 and the last line "sdrestore: child exit N".  A run that printed no "sdrestore: child exit 0" did
# not finish, and the installer then falls back to its red warning with the exact steps.  Exit 0 whatever happened: the installer judges the text.

param([string]$AppDir = '')

# Windows PowerShell's own module folders (RELEASE_1.1 111): the ScheduledTasks cmdlets below must be the 5.1 ones whatever started this.
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
$ErrorActionPreference = 'Continue'
if ($AppDir -eq '') { $AppDir = $PSScriptRoot }
function Out-Line([string]$t) { [Console]::Out.WriteLine($t) }

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Out-Line ('RESTORE-RUN: ' + $me.Name + ' elevated=' + $elevated + ' app=' + $AppDir)
if (-not $elevated) { Out-Line 'RESTORE-RUN: NOT RUN, not elevated.'; exit 0 }
# The service binary is installed in <program folder>\usr\bin, the scripts in <program folder> (sdrestore.c finds the script from there).
$svc = Join-Path $AppDir 'usr\bin\sdsvc.exe'
if (-not (Test-Path -LiteralPath $svc)) { Out-Line ('RESTORE-RUN: NOT RUN, ' + $svc + ' is not there.'); exit 0 }
$script = Join-Path $AppDir 'sd-restore-kept.ps1'
if (-not (Test-Path -LiteralPath $script)) { Out-Line ('RESTORE-RUN: NOT RUN, ' + $script + ' is not there.'); exit 0 }

$work = Join-Path $env:ProgramData 'SDrestore'
$result = Join-Path $work 'result.txt'
$task = 'SDRestoreKept'

# The folder: made here, with its ACL, in one call - SYSTEM and Administrators only, owned by Administrators.  A leftover (or a link, or a folder
# somebody else made) is removed first; sdrestore.c refuses a folder that is not a real one owned by Administrators or SYSTEM.
if (Test-Path -LiteralPath $work) {
    $it = Get-Item -LiteralPath $work -Force
    if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($work, $false) }
    else { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
if (Test-Path -LiteralPath $work) { Out-Line ('RESTORE-RUN: NOT RUN, ' + $work + ' could not be cleared.'); exit 0 }
$ds = New-Object Security.AccessControl.DirectorySecurity
$ds.SetAccessRuleProtection($true, $false)
$inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
    $ds.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
}
$ds.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
try { [IO.Directory]::CreateDirectory($work, $ds) | Out-Null } catch { Out-Line ('RESTORE-RUN: NOT RUN, ' + $work + ' could not be made: ' + $_.Exception.Message); exit 0 }

try {
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute $svc -Argument '-restore-kept'
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $task -ErrorAction Stop
    Out-Line ('RESTORE-RUN: the SYSTEM task ' + $task + ' was started: ' + $svc + ' -restore-kept')
    $deadline = (Get-Date).AddSeconds(240)
    $seenRunning = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        if ($null -eq $t) { break }
        if ([string]$t.State -eq 'Running') { $seenRunning = $true; continue }
        if ($seenRunning -or (Test-Path -LiteralPath $result)) { if ((Test-Path -LiteralPath $result) -and ((Get-Content -LiteralPath $result -Raw) -match 'sdrestore: ')) { break } }
    }
} catch {
    Out-Line ('RESTORE-RUN: NOT RUN, the task could not be run: ' + ($_.Exception.Message -replace '\s+', ' '))
}
Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $result) { Get-Content -LiteralPath $result | ForEach-Object { Out-Line $_ } }
else { Out-Line 'RESTORE-RUN: no result file: the restore did not run.' }
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Out-Line ('RESTORE-RUN: the task is gone: ' + ($null -eq (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)) + '; the folder is gone: ' + (-not (Test-Path -LiteralPath $work)))
exit 0
