# test-settingsos-units.ps1 - drive sd-settings-os.ps1's pure functions.
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-settingsos-units.ps1
#
# ORDINARY UNELEVATED PROMPT.  No install, no SD, no elevation, no certificate
# store.  Exit 0 all passed, 1 something failed, 2 could not set up.
#
# WHY IT EXISTS.  RELEASE_1.1 116: SETTINGS.REPORT reads api.pem, which holds
# the API's PRIVATE KEY beside its certificate.  The one thing this must prove
# is that the key's text never reaches the report - so it feeds a PEM whose key
# block carries a marker and checks the marker comes out nowhere.  The
# functions are lifted from the file by AST (test-sdpath-units.ps1's
# technique), so it tests the shipped text.
#
# NOT SHIPPED - assert-current exempts test-* scripts by name.

$ErrorActionPreference = 'Stop'

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $here 'sd-settings-os.ps1'

Write-Host "test-settingsos-units: subject $subject"
if (-not (Test-Path -LiteralPath $subject)) { Write-Host 'test-settingsos-units: subject not found.'; exit 2 }

$tok = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($subject, [ref]$tok, [ref]$errs)
if ($errs.Count -gt 0) { Write-Host "test-settingsos-units: subject has $($errs.Count) parse error(s)."; exit 2 }

$wanted = @('Get-PemCertificates', 'Select-SshdLines', 'Select-ConfLines')
$lifted = 0
foreach ($name in $wanted) {
    $fn = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true))
    if ($fn.Count -ne 1) { Write-Host "test-settingsos-units: expected exactly one $name, found $($fn.Count)."; exit 2 }
    . ([scriptblock]::Create($fn[0].Extent.Text))
    $lifted++
}
if ($lifted -ne $wanted.Count) { Write-Host 'test-settingsos-units: VOID - not every function was lifted.'; exit 2 }
Write-Host "  lifted $lifted functions"

$script:pass = 0
$script:fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $what" }
    else     { $script:fail++; Write-Host "  [FAIL] $what $detail" }
}

try {
    # A real certificate, made in memory: RSA, self-signed, no store.
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $req = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest('CN=sd-test', $rsa,
             [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $cert = $req.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddDays(30))
    $b64 = [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
    $marker = 'KEYMARKERxyzzy'
    $pem = "-----BEGIN PRIVATE KEY-----`n$marker" + "AAAA`n-----END PRIVATE KEY-----`n" +
           "-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----`n"

    Write-Host ''
    Write-Host '1. certificate blocks'
    $got = Get-PemCertificates $pem
    Check 'exactly one certificate block found' ($got.Count -eq 1)
    Check 'the key block is not among them' (-not (($got -join '') -like "*$marker*"))
    $thumb = ''
    try { $thumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,[Convert]::FromBase64String($got[0]))).Thumbprint }
    catch { $thumb = "undecodable: $($_.Exception.Message)" }
    Check 'it decodes to the same certificate' ($thumb -eq $cert.Thumbprint) $thumb
    Check 'a key-only PEM yields nothing' ((Get-PemCertificates "-----BEGIN PRIVATE KEY-----`n$marker`n-----END PRIVATE KEY-----`n").Count -eq 0)
    Check 'empty text yields nothing' ((Get-PemCertificates '').Count -eq 0)

    Write-Host ''
    Write-Host '2. sshd_config lines'
    $cfg = @('# Port 22', 'Port 2222', '#AllowGroups x', 'AllowGroups sdssh HOST\sdssh', 'PasswordAuthentication no',
             'Match Group sdsshonly', '    ForceCommand "C:\Program Files\SD\usr\bin\sd.exe"', 'Subsystem sftp sftp-server.exe')
    $sel = Select-SshdLines $cfg
    Check "kept Port, AllowGroups, Match, ForceCommand ($($sel.Count))" ($sel.Count -eq 4)
    Check 'commented lines dropped' (-not ($sel | Where-Object { $_.StartsWith('#') }))
    Check 'unrelated settings dropped' (-not ($sel -match 'Password|Subsystem'))

    Write-Host ''
    Write-Host '3. sd.conf lines'
    $conf = Select-ConfLines @('# comment', '', '  ', 'APIPORT=4247', '# APIPORT=4247', 'USRDIR=C:\ProgramData\SD\user_accounts')
    Check "kept the two settings ($($conf.Count))" ($conf.Count -eq 2 -and $conf[0] -eq 'APIPORT=4247')
}
catch {
    # A crash after a check has failed is a FAILURE, not "could not set up":
    # check-free-tier reports exit 2 as NO TREE, which would hide it.
    Write-Host "test-settingsos-units: STOPPED - $($_.Exception.Message)"
    if ($script:fail -gt 0) { Write-Host "test-settingsos-units: FAILED - $($script:fail) failed before it stopped."; exit 1 }
    exit 2
}

Write-Host ''
if ($script:pass -eq 0) { Write-Host 'test-settingsos-units: VOID - no check ran.'; exit 2 }
if ($script:fail -gt 0) { Write-Host "test-settingsos-units: FAILED - $($script:pass) passed, $($script:fail) failed."; exit 1 }
Write-Host "test-settingsos-units: PASSED - $($script:pass) of $($script:pass) checks passed."
exit 0
