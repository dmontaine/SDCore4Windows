# witness-vm-system.ps1 - the LocalSystem half of the Core VM witness sitting (13 Nov 2026).
#
# NOT RUN BY HAND.  witness-vm-admin.ps1 runs it as NT AUTHORITY\SYSTEM through a one-shot scheduled task
# (Invoke-WitAsSystem in witness-vm-lib.ps1), because two things the sitting reads are closed to an elevated administrator:
#   -Mode Token     the token of a process another account's service started (row 253(b): the run.in debug child runs as
#                   sdrunin, and its process and token DACLs name that account and SYSTEM, not Administrators).
#   -Mode KeyProbe  the AI helper's key directory (row 246 F1: SYSTEM and the service SID only) - the DPAPI blob's header
#                   says whether it was sealed in machine scope (flag 0x4 at offset 40) and which master key sealed it,
#                   and an unprotect attempt as SYSTEM must fail if the blob is in the service account's user scope.
# It writes one text report to -Out (key=value lines and an ENDOFREPORT line) and prints nothing else; the caller prints it.
# A report without ENDOFREPORT is not a report.
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting.  Not run: it needs the VM.
# END-HISTORY

param(
    [Parameter(Mandatory = $true)][ValidateSet('Token', 'KeyProbe')][string]$Mode,
    [int[]]$ProcessId = @(),
    [string]$UserName = '',
    [string]$KeyDir = 'C:\ProgramData\SD\ai\keys',
    [string]$CopyTo = '',
    [Parameter(Mandatory = $true)][string]$Out
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')

$lines = New-Object System.Collections.ArrayList
$null = $lines.Add('identity=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
$null = $lines.Add('mode=' + $Mode)

if ($Mode -eq 'Token') {
    $pids = @($ProcessId)
    if ($UserName -ne '') {
        foreach ($p in @(Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -like ('*\' + $UserName) })) { $pids += $p.Id }
    }
    $null = $lines.Add('pids=' + (($pids | Sort-Object -Unique) -join ','))
    foreach ($id in ($pids | Sort-Object -Unique)) {
        $f = [SdWit.Native]::ReadToken([uint32]$id)
        $img = ''
        try { $img = (Get-Process -Id $id -ErrorAction Stop).Path } catch { $img = '?' }
        $par = ''
        try { $par = [string](Get-CimInstance Win32_Process -Filter ('ProcessId=' + $id)).ParentProcessId } catch { }
        $null = $lines.Add(('pid={0} image={1} parent={2} error={3} stage={4} user={5} elevated={6} injob={7} integrity={8} privcount={9}' -f
                            $id, $img, $par, $f.Error, $f.Stage, $f.User, $f.Elevated, $f.InJob, $f.Integrity, $f.PrivilegeCount))
        $null = $lines.Add(('pid={0} groups={1}' -f $id, $f.Groups))
        $null = $lines.Add(('pid={0} privileges={1}' -f $id, $f.Privileges))
    }
}

if ($Mode -eq 'KeyProbe') {
    $null = $lines.Add('keydir=' + $KeyDir)
    $files = @()
    try { $files = @(Get-ChildItem -LiteralPath $KeyDir -File -Force -ErrorAction Stop) } catch { $null = $lines.Add('keydir-error=' + $_.Exception.Message) }
    $null = $lines.Add('keyfiles=' + $files.Count)
    try { $null = $lines.Add('keydir-sddl=' + (Get-Acl -LiteralPath $KeyDir).Sddl) } catch { }
    Add-Type -AssemblyName System.Security
    foreach ($k in $files) {
        $b = [IO.File]::ReadAllBytes($k.FullName)
        $null = $lines.Add(('key={0} bytes={1} sddl={2}' -f $k.Name, $b.Length, (Get-Acl -LiteralPath $k.FullName).Sddl))
        if ($b.Length -ge 44) {
            $ver = [BitConverter]::ToUInt32($b, 0)
            $prov = New-Object -TypeName Guid -ArgumentList (, [byte[]]($b[4..19]))
            $mkg = New-Object -TypeName Guid -ArgumentList (, [byte[]]($b[24..39]))
            $flags = [BitConverter]::ToUInt32($b, 40)
            $null = $lines.Add(('key={0} dpapi-version={1} provider={2} masterkey={3} flags=0x{4:X} machine-scope={5}' -f $k.Name, $ver, $prov, $mkg, $flags, (($flags -band 4) -ne 0)))
            $where = @()
            foreach ($root in @('C:\Windows\ServiceProfiles', 'C:\Windows\System32\config\systemprofile', 'C:\Windows\System32\Microsoft\Protect')) {
                try { $where += @(Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $mkg.ToString() } | ForEach-Object { $_.FullName }) } catch { }
            }
            $null = $lines.Add(('key={0} masterkey-file={1}' -f $k.Name, ($where -join ';')))
        }
        foreach ($ent in @($null, ('sd-ai key ' + $k.Name))) {
            $e = $null
            if ($null -ne $ent) { $e = [Text.Encoding]::ASCII.GetBytes($ent) }
            $label = 'none'
            if ($null -ne $ent) { $label = $ent }
            try {
                $null = [Security.Cryptography.ProtectedData]::Unprotect($b, $e, [Security.Cryptography.DataProtectionScope]::CurrentUser)
                $null = $lines.Add(('key={0} unprotect-as-system entropy="{1}" result=DECRYPTED' -f $k.Name, $label))
            } catch {
                $null = $lines.Add(('key={0} unprotect-as-system entropy="{1}" result=refused ({2})' -f $k.Name, $label, $_.Exception.Message.Trim()))
            }
        }
        if ($CopyTo -ne '') {
            try {
                Copy-Item -LiteralPath $k.FullName -Destination (Join-Path $CopyTo ('copy-' + $k.Name)) -Force
                $null = $lines.Add(('key={0} copied-to={1}' -f $k.Name, (Join-Path $CopyTo ('copy-' + $k.Name))))
            } catch { $null = $lines.Add(('key={0} copy-error={1}' -f $k.Name, $_.Exception.Message)) }
        }
    }
}

$null = $lines.Add('ENDOFREPORT')
[IO.File]::WriteAllText(($Out + '.tmp'), (($lines.ToArray()) -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath ($Out + '.tmp') -Destination $Out -Force
