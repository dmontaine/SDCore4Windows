# sd-settings-os.ps1 - the Windows sections of SETTINGS.REPORT
#
#   powershell -ExecutionPolicy Bypass -File "C:\Program Files\SD\sd-settings-os.ps1"
#
# Run by SD through !ps_script_out, from gpl.bp SETTINGS_OS (RELEASE_1.1 116),
# in an SDSYS session's elevated helper.  Every report line is printed as
# "REPORT <text>", section headers as "REPORT [name]", and the LAST line on
# success is "SETTINGS-OS OK SECTIONS <n>" - the only text a caller may anchor
# on.  Exit 0 done, 1 failed.
#
# THE REPORT IS REFERENCE TEXT THAT NOTHING READS BACK (owner, 1 Oct 2026), so a
# section that cannot be read says so in its own lines and the rest still go
# out: a report missing one part is more use than none.  A section with no data
# on this machine is left out, not printed empty (agreed with Linux).
#
# NEVER IN IT: a private key, $cred, a password.  api.pem holds the API's
# private key AND its certificate in one file (secure-tls.ps1), so only the
# CERTIFICATE block is ever decoded - Get-PemCertificates below - and the key
# block's text is never put in a variable that is printed.

param()

$ErrorActionPreference = 'Stop'

# --- pure helpers ------------------------------------------------------------

# The base64 bodies of every CERTIFICATE block in PEM text, and nothing else.
function Get-PemCertificates([string]$pem) {
    $out = @()
    $rx = [regex]'(?s)-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----'
    foreach ($m in $rx.Matches($pem)) { $out += ($m.Groups[1].Value -replace '\s', '') }
    return ,$out
}

# The sshd_config lines a reader of the report needs: active (uncommented)
# Port, ListenAddress, AllowGroups/AllowUsers/DenyGroups/DenyUsers, Match and
# ForceCommand lines.
function Select-SshdLines([string[]]$lines) {
    $keep = @()
    foreach ($l in $lines) {
        $t = $l.Trim()
        if ($t -match '^(?i)(Port|ListenAddress|AllowGroups|AllowUsers|DenyGroups|DenyUsers|Match|ForceCommand)\b') { $keep += $t }
    }
    return ,$keep
}

# sd.conf lines worth reporting: everything but blanks and comments.
function Select-ConfLines([string[]]$lines) {
    $keep = @()
    foreach ($l in $lines) {
        $t = $l.Trim()
        if ($t -ne '' -and -not $t.StartsWith('#')) { $keep += $t }
    }
    return ,$keep
}

# --- sections ----------------------------------------------------------------

$script:sections = 0
function Section([string]$name) { Write-Output "REPORT [$name]"; $script:sections++ }
function Line([string]$text) { Write-Output "REPORT $text" }
function Failed([string]$what) { Line "(could not be read: $what)" }

$dataDir = Join-Path $env:ProgramData 'SD'

try {
    # sd.conf
    $conf = Join-Path $dataDir 'sd.conf'
    if (Test-Path -LiteralPath $conf) {
        Section 'sd.conf'
        Line "file: $conf"
        try { foreach ($l in (Select-ConfLines ([System.IO.File]::ReadAllLines($conf)))) { Line $l } }
        catch { Failed $_.Exception.Message }
    }

    # ssh
    $sshd = Join-Path $env:ProgramData 'ssh\sshd_config'
    $sshSvc = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
    if ($sshSvc -or (Test-Path -LiteralPath $sshd)) {
        Section 'ssh'
        if ($sshSvc) { Line "sshd service: $($sshSvc.Status), start $($sshSvc.StartType)" } else { Line 'sshd service: not installed' }
        if (Test-Path -LiteralPath $sshd) {
            Line "file: $sshd"
            try { foreach ($l in (Select-SshdLines ([System.IO.File]::ReadAllLines($sshd)))) { Line $l } }
            catch { Failed $_.Exception.Message }
        }
    }

    # api
    $pem = Join-Path $dataDir 'sd-tls\api.pem'
    $apiRule = Get-NetFirewallRule -Name 'SD-API-In-TCP' -ErrorAction SilentlyContinue
    if ((Test-Path -LiteralPath $pem) -or $apiRule) {
        Section 'api'
        if (Test-Path -LiteralPath $pem) {
            try {
                $certs = Get-PemCertificates ([System.IO.File]::ReadAllText($pem))
                if ($certs.Count -eq 0) { Line "certificate: none in $pem" }
                foreach ($b in $certs) {
                    $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,[Convert]::FromBase64String($b))
                    Line "certificate subject: $($c.Subject)"
                    Line ("certificate expires: {0:yyyy-MM-dd HH:mm}" -f $c.NotAfter)
                    Line "certificate thumbprint: $($c.Thumbprint)"
                }
            } catch { Failed "certificate in $pem - $($_.Exception.Message)" }
        } else {
            Line 'certificate: not yet generated'
        }
    }

    # firewall
    $rules = @()
    if ($apiRule) { $rules += $apiRule }
    $rules += @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like 'OpenSSH SSH Server*' -and $_.Direction -eq 'Inbound' })
    if ($rules.Count -gt 0) {
        Section 'firewall'
        foreach ($r in $rules) {
            try {
                $port = ($r | Get-NetFirewallPortFilter).LocalPort -join ','
                $addr = ($r | Get-NetFirewallAddressFilter).RemoteAddress -join ','
                Line "$($r.DisplayName): enabled $($r.Enabled), $($r.Action), port $port, from $addr"
            } catch { Failed "$($r.DisplayName) - $($_.Exception.Message)" }
        }
    }

    # service
    $svc = Get-Service -Name 'SD' -ErrorAction SilentlyContinue
    if ($svc) {
        Section 'service'
        Line "SD service: $($svc.Status), start $($svc.StartType)"
    }

    # groups
    $groups = @('sdusers', 'sdssh', 'sdapi', 'sdsshonly')
    $present = @($groups | Where-Object { Get-LocalGroup -Name $_ -ErrorAction SilentlyContinue })
    if ($present.Count -gt 0) {
        Section 'groups'
        foreach ($g in $present) {
            try {
                $ms = @(Get-LocalGroupMember -Group $g -ErrorAction Stop | ForEach-Object { ($_.Name -split '\\')[-1] })
                Line ("{0}: {1}" -f $g, ($ms -join ','))
            } catch { Failed "$g - $($_.Exception.Message)" }
        }
    }

    Write-Output "SETTINGS-OS OK SECTIONS $($script:sections)"
    exit 0
} catch {
    Write-Output "SETTINGS-OS ERROR $($_.Exception.Message)"
    exit 1
}
