# witness-vm-forge.ps1 - one forged audit record, sent straight to the audit writer's pipe (row 247, Core VM witness sitting).
#
# NOT RUN BY HAND.  witness-vm-user.ps1 runs it INSIDE an SD session of the fixture account zzwiton (OS and SH on, a member
# of sdusers), through SD's own SH, so the sender is a sdusers member who is not the writer's user and not an administrator:
#
#   SH powershell -NoProfile -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-forge.ps1 -Nonce <n>
#
# The record CLAIMS user number 0 (SDSYS's) and carries the nonce.  The writer must write it with this process's REAL
# Windows user and pid (sdaudit.c audit_format_line), which witness-vm-admin.ps1 -Only afterconsole reads back.  It prints
# one line, FORGE ..., that appears only when this script ran; the caller parses it.
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting.  Not run: it needs the VM.
# END-HISTORY

param([Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]{6,40}$')][string]$Nonce)

. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')
$sysd = Join-Path (Join-Path $env:ProgramData 'SD') 'sdsys'
$msg = 'SDAUDIT1 0' + "`t" + $sysd + "`t" + 'witness forged by a sdusers member ' + $Nonce
$r = [SdWit.Native]::PipeSend('\\.\pipe\sd-audit', [Text.Encoding]::ASCII.GetBytes($msg), 5000)
Write-Host ('FORGE identity=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name + ' pid=' + $PID + ' open=' + $r.OpenError +
            ' write=' + $r.WriteError + ' answer=' + $r.Answer + ' timeout=' + $r.TimedOut + ' nonce=' + $Nonce)
