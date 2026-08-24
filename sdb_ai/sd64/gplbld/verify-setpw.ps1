# Does MODIFY.PASSWORD now refuse a trailing token, and ONLY a trailing token?
#
# THE CONTROL IS THE WHOLE POINT.  "It refused" proves nothing on its own - a
# verb that refused everything would pass just as well.  So the same command
# without the extra token has to get PAST the syntax check and reach the
# password prompt.
$ErrorActionPreference = 'Continue'
$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$msg   = (Get-Content -LiteralPath (Join-Path $env:ProgramData 'SD\sdsys\messages\5276') -Raw).Trim()

function Invoke-SD([string[]]$commands) {
    # Blank first line absorbs the BOM; TERM stops it paginating; OFF ends it.
    # LOGIN re-inits terminal geometry on every account switch (LOGIN:201-209),
    # so a LOGTO in $commands wipes the initial TERM - full write-up in
    # verify-tiers.ps1's Invoke-SD.
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

$results = @()
function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    $script:results += [pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got; Result = $(if($pass){'PASS'}else{'FAIL'}) }
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f $(if($pass){'PASS'}else{'FAIL'}), $check, $expected, $got)
}

Write-Host "message 5276 reads: $msg"
Write-Host ''

# --- TREATMENT: a trailing token.  Nothing sensible is fed after it, because
# --- the verb must refuse before it prompts for anything.
Write-Host '== treatment: MODIFY.PASSWORD DON somethingextra'
$t = Invoke-SD @('MODIFY.PASSWORD DON somethingextra')
Note 'refused with 5276'            $true ($t -match [regex]::Escape($msg))
Note 'and did NOT reach the prompt' $false ($t -match 'New password|Current password|has no password set')

# --- CONTROL: the same command without it must get past the syntax check.
# --- A deliberately wrong current password ends the attempt without changing
# --- anything; there is no lockout to trip (docs/SCRAM_AUTH.md, "Still open").
Write-Host ''
Write-Host '== control: MODIFY.PASSWORD DON  (reaches the prompt, then fails on a wrong current password)'
$c = Invoke-SD @('MODIFY.PASSWORD DON', 'definitely-not-the-password', '', '')
Note 'control reached the password prompt' $true ($c -match 'Current password|New password|has no password set')
Note 'control NOT refused with 5276'       $false ($c -match [regex]::Escape($msg))

Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$fail = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
if ($fail) {
    Write-Host "--- treatment output ---"; Write-Host $t
    Write-Host "--- control output ---";   Write-Host $c
    exit 1
}
Write-Host "verify-setpw: PASSED - the trailing token is refused, and only it."
exit 0
