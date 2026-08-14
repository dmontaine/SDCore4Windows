# verify-allowgroups.ps1 - exercise allow-ssh-groups.ps1's file editing against
# the sshd_config Windows actually ships.  PROJECT_STATUS.md 5.6.2.
#
#   powershell -File verify-allowgroups.ps1
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# NEEDS NO ELEVATION, NO sshd AND NO NETWORK, which is the point of it.  The
# input is C:\Windows\System32\OpenSSH\sshd_config_default - the template sshd
# copies to C:\ProgramData\ssh\sshd_config on its first start - and that file is
# readable by anybody.  So the risky half of AllowGroups can be tested on any
# machine, in any session, before it is ever pointed at a live config.
#
# WHAT IT CANNOT TELL YOU.  Whether the patterns MATCH the right people. That
# is a property of Win32-OpenSSH's group lookup, not of the text, and it needs
# a real ssh connection from a real account - see PROJECT_STATUS.md 4
# Unverified.  Everything here is about not corrupting the file: the block
# lands before the first Match block rather than inside it, re-running replaces
# rather than stacks, removal is an exact inverse, and somebody else's
# AllowUsers is recognised and left alone.
#
# IT TESTS THE SHIPPED FILE, NOT A COPY OF IT.  The functions are lifted out of
# allow-ssh-groups.ps1 by parsing it, so this cannot drift away from the code it
# is checking - which a transcribed copy of the logic certainly would.

$ErrorActionPreference = 'Stop'

$src      = Join-Path $PSScriptRoot 'allow-ssh-groups.ps1'
$template = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd_config_default'

$failed = 0

function Show($name, $expected, $got) {
    $ok = ($expected -eq $got)
    if (-not $ok) { $script:failed++ }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $expected, $got)
}

if (-not (Test-Path $src))      { Write-Output "verify-allowgroups: no $src"; exit 2 }
if (-not (Test-Path $template)) { Write-Output "verify-allowgroups: no $template - OpenSSH is not present on this machine"; exit 2 }

# Pull the markers and the functions out of the shipped script itself.
foreach ($l in (Get-Content $src)) {
    if ($l -match '^\$(begin|end)\s*=') { Invoke-Expression $l }
}
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    Invoke-Expression $f.Extent.Text
}

$default  = @(Get-Content $template)
# Not this machine's real names: the editing is what is under test, and a
# fixed alphabet keeps the result the same everywhere.  Get-Patterns is what
# resolves the real ones, and "allow-ssh-groups.ps1 -Check" prints them.
$patterns = @('sdusers', 'BOX\sdusers', 'Administrators', 'BOX\Administrators')

Write-Output "=== the file Windows ships ============================================="
$matchAt = ($default | Select-String -Pattern '^\s*Match\b' | Select-Object -First 1).LineNumber
Show 'it has a Match block'      'yes' $(if ($matchAt) { 'yes' } else { 'no' })
Show 'and restricts nobody yet'  0     (Get-ExistingRestrictions $default).Count
Write-Output ("  first Match is line " + $matchAt + " of " + $default.Count)

Write-Output ""
Write-Output "=== insert ============================================================="
$new = Add-OurBlock $default $patterns
$ai = ($new | Select-String -Pattern '^AllowGroups ' | Select-Object -First 1).LineNumber
$mi = ($new | Select-String -Pattern '^\s*Match\b'   | Select-Object -First 1).LineNumber
Show 'AllowGroups present'                1     ($new | Select-String -Pattern '^AllowGroups ').Count
# THE ONE THAT MATTERS.  Inside a Match block it would apply to that block's
# users only, which reads as working and is the opposite of what it says.
Show 'it is BEFORE the first Match'       'yes' $(if ($ai -and $mi -and $ai -lt $mi) { 'yes' } else { 'no' })
Show 'three lines added and nothing lost' ($default.Count + 3) $new.Count
Write-Output ("  wrote: " + ($new | Where-Object { $_ -like 'AllowGroups*' }))

Write-Output ""
Write-Output "=== re-running replaces, it does not stack ============================="
$cycle = $default
for ($i = 0; $i -lt 3; $i++) { $cycle = Add-OurBlock (Remove-OurBlock $cycle) $patterns }
Show 'one AllowGroups after three applies' 1     ($cycle | Select-String -Pattern '^AllowGroups ').Count
Show 'identical to a single apply'         'yes' $(if (($cycle -join "`n") -eq ($new -join "`n")) { 'yes' } else { 'no' })

Write-Output ""
Write-Output "=== removal is an exact inverse ========================================"
# Not cosmetic.  A block that leaves one line behind grows the file on every
# apply/remove cycle, and that is what a trailing blank line did on 14 Aug 2026.
Show 'one apply then remove is the original'   'yes' $(if (((Remove-OurBlock $new) -join "`n") -eq ($default -join "`n")) { 'yes' } else { 'no' })
Show 'three applies then remove, likewise'     'yes' $(if (((Remove-OurBlock $cycle) -join "`n") -eq ($default -join "`n")) { 'yes' } else { 'no' })
Show 'no marker survives'                      0     ((Remove-OurBlock $cycle) | Select-String -Pattern 'SD ssh-only model').Count

Write-Output ""
Write-Output "=== somebody else's policy is recognised and left alone ================"
Show 'our own block does not read as theirs' 0 (Get-ExistingRestrictions $new).Count
foreach ($d in @('AllowUsers alice', '  DenyGroups contractors', 'AllowGroups sshusers', 'DenyUsers bob')) {
    Show ("refuses on: " + $d.Trim()) 1 (Get-ExistingRestrictions (@($d) + $default)).Count
}
Show 'AllowAgentForwarding is not a restriction' 0 (Get-ExistingRestrictions (@('AllowAgentForwarding yes') + $default)).Count
Show 'nor is a commented-out AllowGroups'        0 (Get-ExistingRestrictions (@('#AllowGroups sshusers') + $default)).Count

Write-Output ""
Write-Output "=== a config with no Match block at all ================================"
$noMatch = @('Port 22', 'PasswordAuthentication yes')
$nm = Add-OurBlock $noMatch $patterns
Show 'AllowGroups still written' 1     ($nm | Select-String -Pattern '^AllowGroups ').Count
Show 'the original lines are kept' 'yes' $(if ($nm[0] -eq 'Port 22' -and $nm[1] -eq 'PasswordAuthentication yes') { 'yes' } else { 'no' })

Write-Output ""
if ($failed -gt 0) { Write-Output ("verify-allowgroups: " + $failed + " FAILED"); exit 1 }
Write-Output "verify-allowgroups: all checks passed"
exit 0
