# sd-restore-kept.ps1 - put back, AS SDSYS, what an uninstall that kept the data took away
#
# 21 Nov 26 Windows port - RELEASE_1.1 370 (owner, 21 Nov 2026: a Keep must put the system back exactly as it was; "Yes, build it" to an installer
# helper that does it as SDSYS).  Run ONLY by "sdsvc.exe -restore-kept" (gplsrc/sdsvc/sdrestore.c), which the installer's run-restore-kept.ps1
# starts as a one-time SYSTEM task: sdsvc mints SDSYS's S4U token, checks it is elevated, and starts this script under it, with its output in
# <ProgramData>\SDrestore\result.txt.  It refuses to do anything unless it IS the local account SDSYS with an elevated token (-DryRun excepted).
#
# WHY IT MUST BE SDSYS.  The jobs' tasks and remote administration's broker task run as SDSYS (S4U, highest run level), and Windows registers
# such a task only for SDSYS itself (row 280).  MEASURED on a VM, 21 Nov 2026 (probe-sdsys-taskreg.ps1): an administrator and SYSTEM are refused;
# SDSYS's own S4U token, minted by SYSTEM, registers it and runs sd-jobs.ps1 job-set.
#
# WHAT IT RESTORES, under Linux's trust rules (mails T0510, T0610: installsdcore.sh restore_saved_jobs, the sdsys-ssh.saved note):
#   JOBS  the kept definitions in <ProgramData>\SD\sd-jobs.  Each is read by sd-jobs.ps1 job-list (which refuses a link, a foreign owner, a
#         damaged or an edited file) and given to the SAME validating verb as an administrator's own set.job: sd-jobs.ps1 job-set NAME JOB
#         SCHEDULE.  A kept file is never trusted as written.  A definition the verb refuses is said with its reason and counted.  A job already
#         scheduled under that name is replaced, not doubled (job-set replaces by name).  One summary line: "RESTORE jobs: N scheduled again, M NOT."
#   REMOTE ADMINISTRATION  only when the uninstall noted it was on (HKLM64 SOFTWARE\SD\SetupNotes, value RemoteAdmin = on: sd.iss SaveRadminNote),
#         and only if no principal but SYSTEM, Administrators and TrustedInstaller can write that key.  The note is deleted whatever it said (used,
#         untrusted, or not "on"), so nothing planted can wait for a later run.  The arm is reopened by remote-admin.ps1 -On, which refuses anyone
#         but SDSYS - and this is SDSYS.  A failure says so and leaves it off.  "RESTORE remote-admin: open" or "NOT opened - <why>".
#
# THE LINES THE INSTALLER ANCHORS ON (sd.iss RunRestoreKept), all "RESTORE ...": "RESTORE jobs: N scheduled again, M NOT.", "RESTORE job NAME:
# scheduled again|NOT scheduled again - <why>", "RESTORE remote-admin: open|NOT opened - <why>|none to restore."  Success is judged on the
# helpers' own success wording ("sd-jobs: job NAME is scheduled", "remote-admin: open"), never on an exit code or on the name being in the output.
#
# -DryRun (with -ListFile, the text of job-list, and -NoteState on|off|untrusted|none) is for gplbld/test-restorekept-units.ps1: it skips the
# identity test, never runs a helper and never touches the registry; it prints what it WOULD run.

param(
    [switch]$DryRun,
    [string]$ListFile = '',
    [string]$NoteState = ''
)

$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
$ErrorActionPreference = 'Continue'
$Account = 'SDSYS'
$here = $PSScriptRoot
$Ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# BEGIN restore_functions
function Out-Line([string]$t) { [Console]::Out.WriteLine($t) }

function Clip([string]$s) {
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt 200) { return $s.Substring(0, 200) }
    return $s
}

# One line of job-list: "job NAME: SCHEDULE: COMMAND (JOB)" -> @{ Name; Sched; Job }, or "damaged NAME: WHY" -> @{ Name; Why }, else $null (the
# helper's own header lines).  A schedule can hold a colon but never ": ", so the line splits on ": " into three.
function ConvertFrom-JobListLine([string]$line) {
    $d = [regex]::Match($line, '^damaged ([a-z0-9.-]{1,64}): (.{1,200})$')
    if ($d.Success) { return @{ Name = $d.Groups[1].Value; Why = $d.Groups[2].Value } }
    $m = [regex]::Match($line, '^job ([a-z](?:[a-z0-9-]{0,30}[a-z0-9])?): (.+)$')
    if (-not $m.Success) { return $null }
    $parts = $m.Groups[2].Value -split ': ', 2
    if ($parts.Count -ne 2) { return $null }
    $c = [regex]::Match($parts[1], ' \((backup-all|update-accounts)\)$')
    if (-not $c.Success) { return $null }
    if (-not [regex]::IsMatch($parts[0], '^[a-z0-9: ]{1,40}$')) { return $null }
    return @{ Name = $m.Groups[1].Value; Sched = $parts[0]; Job = $c.Groups[1].Value }
}

# Rights that let a principal change a registry key; only these principals may hold one for the note to be trusted.
function Test-NoteWriters($rules) {
    $ok = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464', 'S-1-3-0')
    # The single write bits, NOT the composite WriteKey: that one contains ReadControl, which a read-only grant also carries.
    $writeBits = [Security.AccessControl.RegistryRights]'SetValue, CreateSubKey, CreateLink, Delete, ChangePermissions, TakeOwnership'
    foreach ($r in @($rules)) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        if (-not (($r.RegistryRights -band $writeBits) -ne 0)) { continue }
        $sid = try { $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $r.IdentityReference.Value }
        if ($ok -notcontains $sid) { return @{ Trusted = $false; Who = [string]$r.IdentityReference } }
    }
    return @{ Trusted = $true; Who = '' }
}
# END restore_functions

Out-Line ('RESTORE start: ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name + ' ' + (Get-Date -Format s) + $(if ($DryRun) { ' (dry run)' } else { '' }))

# ---------------------------------------------------------------- who is running this
if (-not $DryRun) {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sdsysSid = ''
    try { $sdsysSid = (New-Object Security.Principal.NTAccount("$([Environment]::MachineName)\$Account")).Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
    $elevated = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.SecurityIdentifier]'S-1-5-32-544')
    if ($sdsysSid -eq '' -or $me.User.Value -ne $sdsysSid) { Out-Line 'RESTORE refused: this is not the local account SDSYS; nothing was changed.'; exit 3 }
    if (-not $elevated) { Out-Line 'RESTORE refused: this session is not elevated; nothing was changed.'; exit 3 }
}

# ---------------------------------------------------------------- the jobs
$jobsPs1 = Join-Path $here 'sd-jobs.ps1'
$listText = @()
if ($DryRun) {
    if ($ListFile -ne '' -and (Test-Path -LiteralPath $ListFile)) { $listText = @(Get-Content -LiteralPath $ListFile) }
} elseif (-not (Test-Path -LiteralPath $jobsPs1)) {
    Out-Line ('RESTORE jobs: NOT RUN, ' + $jobsPs1 + ' is not there.')
} else {
    $listText = @(& $Ps -NoProfile -ExecutionPolicy Bypass -File $jobsPs1 job-list 2>&1 | ForEach-Object { "$_" })
}
$done = 0; $failed = 0; $seen = 0
foreach ($line in $listText) {
    $j = ConvertFrom-JobListLine $line
    if ($null -eq $j) { continue }
    $seen++
    if ($j.ContainsKey('Why')) {
        $failed++
        Out-Line ('RESTORE job ' + $j.Name + ': NOT scheduled again - its definition is damaged (' + (Clip $j.Why) + ')')
        continue
    }
    $words = @('job-set', $j.Name, $j.Job) + @($j.Sched -split ' ')
    if ($DryRun) { Out-Line ('RESTORE would run: sd-jobs.ps1 ' + ($words -join ' ')); $done++; continue }
    $o = @(& $Ps -NoProfile -ExecutionPolicy Bypass -File $jobsPs1 @words 2>&1 | ForEach-Object { "$_" })
    $okLine = @($o | Where-Object { $_ -cmatch ('^sd-jobs: job ' + [regex]::Escape($j.Name) + ' is scheduled: ') }).Count -gt 0
    $bad = @($o | Where-Object { $_ -match 'could not be registered|nothing will run until job-set succeeds' }).Count -gt 0
    if ($okLine -and -not $bad) {
        $done++
        Out-Line ('RESTORE job ' + $j.Name + ': scheduled again (' + $j.Sched + ')')
    } else {
        $failed++
        $why = if ($o.Count) { Clip ($o[$o.Count - 1]) } else { 'the helper printed nothing' }
        Out-Line ('RESTORE job ' + $j.Name + ': NOT scheduled again - ' + $why)
    }
}
if ($seen -eq 0) { Out-Line 'RESTORE jobs: none to restore.' }
else { Out-Line ('RESTORE jobs: ' + $done + ' scheduled again, ' + $failed + ' NOT.') }

# ---------------------------------------------------------------- remote administration
$noteKey = 'SOFTWARE\SD\SetupNotes'
$state = 'none'
if ($DryRun) {
    $state = $(if ($NoteState -ne '') { $NoteState } else { 'none' })
} else {
    try {
        $hk = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
        $k = $hk.OpenSubKey($noteKey)
        if ($null -ne $k) {
            $v = $k.GetValue('RemoteAdmin', $null)
            if ($null -ne $v) {
                $trust = Test-NoteWriters ($k.GetAccessControl().GetAccessRules($true, $true, [Security.Principal.NTAccount]))
                if (-not $trust.Trusted) { $state = 'untrusted:' + $trust.Who }
                elseif ([string]$v -ceq 'on') { $state = 'on' }
                else { $state = 'off' }
            }
            $k.Close()
        }
        $hk.Close()
    } catch { $state = 'untrusted:unreadable (' + (Clip $_.Exception.Message) + ')' }
}
switch -Regex ($state) {
    '^none$' { Out-Line 'RESTORE remote-admin: none to restore.' }
    '^off$' { Out-Line 'RESTORE remote-admin: none to restore (the note did not say on).' }
    '^untrusted' { Out-Line ('RESTORE remote-admin: NOT opened - the note is not trusted (' + ($state -replace '^untrusted:?', '') + '); it was not used.') }
    '^on$' {
        if ($DryRun) { Out-Line 'RESTORE would run: remote-admin.ps1 -On'; Out-Line 'RESTORE remote-admin: open' }
        else {
            $ra = Join-Path $here 'remote-admin.ps1'
            if (-not (Test-Path -LiteralPath $ra)) { Out-Line ('RESTORE remote-admin: NOT opened - ' + $ra + ' is not there.') }
            else {
                $o = @(& $Ps -NoProfile -ExecutionPolicy Bypass -File $ra -On 2>&1 | ForEach-Object { "$_" })
                $code = $LASTEXITCODE
                if (@($o | Where-Object { $_ -cmatch '^remote-admin: open' }).Count -gt 0 -and $code -eq 0) { Out-Line 'RESTORE remote-admin: open' }
                else {
                    $why = if ($o.Count) { Clip ($o[$o.Count - 1]) } else { 'the helper printed nothing' }
                    Out-Line ('RESTORE remote-admin: NOT opened - exit ' + $code + ', ' + $why)
                }
            }
        }
    }
}
# The note is spent whatever it said, so nothing planted can wait for a later run.
if (-not $DryRun) {
    try {
        $hk = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
        $k = $hk.OpenSubKey($noteKey, $true)
        if ($null -ne $k) { $k.DeleteValue('RemoteAdmin', $false); $k.Close() }
        $hk.Close()
    } catch { }
}
Out-Line 'RESTORE done'
exit 0
