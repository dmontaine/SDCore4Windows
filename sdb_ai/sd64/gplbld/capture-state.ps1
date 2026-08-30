# capture-state.ps1 - record a machine's SD-relevant state as readable text.
#
#   powershell -ExecutionPolicy Bypass -File capture-state.ps1 -Label before
#   powershell -ExecutionPolicy Bypass -File capture-state.ps1 -Label after -OutDir D:\
#
# IT RUNS IN THE GUEST, NOT ON THE HOST.  Written 30 Aug 2026 for PRE_RELEASE 39,
# whose one requirement was a real interactive uninstall - which cycle.ps1 can
# never do, because unins000.exe is generated at INSTALL time and cycle.ps1
# uninstalls /VERYSILENT, short-circuiting before both of the uninstaller's
# prompts.  So the measurement has to happen on a VirtualBox guest, and the
# results have to come back to the host as TEXT rather than as screenshots.
#
# THE ROUTE IS A SHARED FOLDER AND guestcontrol IS FORBIDDEN (PROJECT_STATUS 7
# step 2 - it needs guest credentials).  The rig is two transient shares, and
# the writable one mounts as Y: by default:
#
#   VBoxManage sharedfolder add <vm> --name sdout --hostpath C:/Users/dmont/sdout --automount --readonly
#   VBoxManage sharedfolder add <vm> --name xfer  --hostpath C:/Users/dmont/sdxfer --automount
#
# Use --transient on a VM that is already RUNNING - a running VM is locked and a
# permanent add fails with "already locked for a session".  On a POWERED-OFF VM
# add them permanently instead, so they survive the power cycles an overnight
# install needs.
#
# RUN IT ELEVATED.  Get-LocalGroupMember and the data-tree paths need it, and an
# unelevated run reports "could not read" for most of what matters - which the
# script says out loud rather than reporting as absence.
#
# IT REFUSES THE NULL CASE OUT LOUD, which is the whole reason it exists rather
# than a handful of ad-hoc commands.  Every section distinguishes THREE answers:
# present, genuinely absent, and "this process could not look".  A group that
# does not exist and a group this process may not read are different facts, and
# an empty list is NEVER reported as "nothing there".  PROJECT_STATUS's
# instrument section is what this implements.

param(
    # before / after, or any label; it names the output file.
    [Parameter(Mandatory = $true)] [string] $Label,

    # Where the file goes.  Y:\ is the xfer share in the standard rig; override
    # it when running somewhere that has no share mounted.
    [string] $OutDir = 'Y:\'
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path -LiteralPath $OutDir)) {
    Write-Host ("capture-state: " + $OutDir + " is not there.") -ForegroundColor Red
    Write-Host 'If this is the rig, the xfer share is not mounted - try \\vboxsvr\xfer,' -ForegroundColor Yellow
    Write-Host 'which needs no Guest Additions automount, or pass -OutDir.' -ForegroundColor Yellow
    exit 2
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out   = Join-Path $OutDir ("state-" + $Label + "-" + $stamp + ".txt")

function Section($t) {
    Write-Output ''
    Write-Output ('=== ' + $t + ' ' + ('=' * [Math]::Max(0, 60 - $t.Length)))
}

$body = & {
    Write-Output ('capture-state: label   ' + $Label)
    Write-Output ('capture-state: when    ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-Output ('capture-state: host    ' + $env:COMPUTERNAME)
    Write-Output ('capture-state: user    ' + $env:USERNAME)
    Write-Output ('capture-state: writing ' + $out)

    # RULE 1 OF THE INSTRUMENT SECTION: say what this run actually was.  Most of
    # what follows reads differently unelevated, and a reader of the file must be
    # able to tell which kind of run produced it.
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $elevated = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Output ('capture-state: elevated ' + $elevated)

    Section 'local users'
    try {
        $u = @(Get-LocalUser -ErrorAction Stop)
        Write-Output ('count: ' + $u.Count)
        $u | ForEach-Object { Write-Output ('  {0,-24} enabled={1}' -f $_.Name, $_.Enabled) }
    } catch {
        Write-Output ('COULD NOT READ: ' + $_.Exception.Message)
    }

    # THE FOUR SD GROUPS AND Administrators.  sdsshonly is the one whose NAME
    # misleads: it grants no ssh, it carries SeDenyInteractiveLogonRight and
    # SeDenyRemoteInteractiveLogonRight (deny-logon.ps1), so membership means
    # "cannot use the console or Remote Desktop" - PRE_RELEASE 69.
    foreach ($g in 'sdusers', 'sdssh', 'sdapi', 'sdsshonly', 'Administrators') {
        Section ("group " + $g)
        try {
            $m = @(Get-LocalGroupMember -Group $g -ErrorAction Stop)
            Write-Output ('exists, members: ' + $m.Count)
            if ($m.Count -eq 0) { Write-Output '  (group exists and is EMPTY)' }
            $m | ForEach-Object { Write-Output ('  ' + $_.Name) }
        } catch {
            Write-Output ('NOT READABLE OR NOT PRESENT: ' + $_.Exception.Message)
        }
    }

    Section 'sdu_ / sdg_ groups'
    try {
        $sd = @(Get-LocalGroup -ErrorAction Stop | Where-Object { $_.Name -match '^sd[ug]_' })
        Write-Output ('count: ' + $sd.Count)
        $sd | ForEach-Object { Write-Output ('  ' + $_.Name) }
        if ($sd.Count -eq 0) { Write-Output '  (none - this is a real answer, the enumeration succeeded)' }
    } catch {
        Write-Output ('COULD NOT ENUMERATE: ' + $_.Exception.Message)
    }

    # THE SD BLOCK IS THE POINT OF THIS SECTION, not the whole file.  Uninstall
    # removes AllowGroups and ForceCommand together (RemoveAllowGroups), and the
    # ForceCommand half is the sharp one: without it an ssh session lands at a
    # PowerShell prompt instead of in SD.
    Section 'sshd_config'
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (Test-Path -LiteralPath $cfg) {
        $lines = @(Get-Content -LiteralPath $cfg | Where-Object { $_ -match 'AllowGroups|ForceCommand|BEGIN SD|END SD' })
        Write-Output ('present: ' + $cfg)
        if ($lines.Count -eq 0) {
            Write-Output '  NO AllowGroups / ForceCommand / SD block lines - the SD block is GONE'
        } else {
            $lines | ForEach-Object { Write-Output ('  ' + $_) }
        }
    } else {
        Write-Output ('NOT PRESENT: ' + $cfg)
    }

    Section 'SD trees'
    foreach ($p in 'C:\Program Files\SD', 'C:\ProgramData\SD', 'C:\ProgramData\SD\sdsys', 'C:\ProgramData\SD\user_accounts') {
        if (Test-Path -LiteralPath $p) {
            $n = @(Get-ChildItem -LiteralPath $p -ErrorAction SilentlyContinue).Count
            Write-Output ('  PRESENT  {0}  ({1} entries)' -f $p, $n)
        } else {
            Write-Output ('  absent   ' + $p)
        }
    }

    Section 'installed SD product'
    $found = $false
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        try {
            Get-ItemProperty $k -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'SD' } |
                ForEach-Object {
                    $found = $true
                    Write-Output ('  {0}  ver={1}' -f $_.DisplayName, $_.DisplayVersion)
                    Write-Output ('    uninstaller: ' + $_.UninstallString)
                }
        } catch { }
    }
    if (-not $found) { Write-Output '  no SD product registered (the registry was readable)' }

    # THE UNINSTALLER NAMES THIS PATH BACK TO THE USER, so the after-capture
    # carries the sweep's own report rather than a summary of it.  %TEMP% is the
    # elevated user's, which is where sd.iss:3589 puts it.
    Section 'sweep log, if the uninstaller has run'
    foreach ($lp in (Join-Path $env:TEMP 'sd-remove-accounts.log'), 'C:\Windows\Temp\sd-remove-accounts.log') {
        if (Test-Path -LiteralPath $lp) {
            Write-Output ('--- ' + $lp + ' ---')
            Get-Content -LiteralPath $lp | ForEach-Object { Write-Output ('  ' + $_) }
        } else {
            Write-Output ('  absent: ' + $lp)
        }
    }
}

# 30 Aug 26 - -Encoding utf8, AND THAT IS NOT A PREFERENCE.  The first run of
# this script used a bare Tee-Object, which in PowerShell 5.1 writes UTF-16LE:
# both captures came back to the host NUL-separated, and a plain grep matched
# NOTHING in either.  PROJECT_STATUS.md records the identical trap for the
# SD-verify transcripts - "a plain grep -a '[PASS]' matches nothing and reports
# PASS=0 FAIL=0, which reads as a green run and is a dead instrument" - and this
# script walked into it one day after that was read.  Out-File takes an encoding;
# Tee-Object in 5.1 does not, which is why this is two statements and not one.
$body | Out-File -FilePath $out -Encoding utf8
$body

Write-Host ''
Write-Host ("capture-state: written to " + $out) -ForegroundColor Green
