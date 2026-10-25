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

# 25 Oct 26 - from Linux 6815cdc (S.65 slice 2a).  The SHA-256 of the certificate's SubjectPublicKeyInfo as 64 lower case hex digits: the figure
# another SD server pins (set.server ... connect shows it), and unlike the certificate thumbprint it survives a renewal over the same key.
# Windows PowerShell 5.1 has no ExportSubjectPublicKeyInfo, so the DER is walked: Certificate = SEQUENCE { tbsCertificate = SEQUENCE {
# [0] version (optional), serial, signature, issuer, validity, subject, subjectPublicKeyInfo ... } ... }.  Returns '' for anything it cannot read.
function Get-SpkiSha256([byte[]]$der) {
    function Read-Tlv([byte[]]$b, [int]$pos) {
        if ($pos + 2 -gt $b.Length) { return $null }
        $tag = $b[$pos]; $n = [int]$b[$pos + 1]; $hdr = 2
        if ($n -ge 128) {
            $k = $n - 128
            if ($k -lt 1 -or $k -gt 3 -or $pos + 2 + $k -gt $b.Length) { return $null }
            $n = 0
            for ($i = 0; $i -lt $k; $i++) { $n = ($n * 256) + [int]$b[$pos + 2 + $i] }
            $hdr = 2 + $k
        }
        if ($pos + $hdr + $n -gt $b.Length) { return $null }
        return @{ Tag = $tag; Start = $pos; Val = $pos + $hdr; End = $pos + $hdr + $n }
    }
    $cert = Read-Tlv $der 0
    if ($null -eq $cert -or $cert.Tag -ne 0x30) { return '' }
    $tbs = Read-Tlv $der $cert.Val
    if ($null -eq $tbs -or $tbs.Tag -ne 0x30) { return '' }
    $pos = $tbs.Val
    $first = Read-Tlv $der $pos
    if ($null -ne $first -and $first.Tag -eq 0xA0) { $pos = $first.End }
    for ($i = 0; $i -lt 5; $i++) {          # serial, signature, issuer, validity, subject
        $t = Read-Tlv $der $pos
        if ($null -eq $t) { return '' }
        $pos = $t.End
    }
    $spki = Read-Tlv $der $pos
    if ($null -eq $spki -or $spki.Tag -ne 0x30) { return '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $h = $sha.ComputeHash($der, $spki.Start, $spki.End - $spki.Start)
    return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
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
                    $spkiHash = Get-SpkiSha256 $c.RawData
                    if ($spkiHash -ne '') { Line "public key sha256: $spkiHash" }
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
