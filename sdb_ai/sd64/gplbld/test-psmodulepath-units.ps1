# test-psmodulepath-units.ps1 - every shipped script that calls a Microsoft.PowerShell.Security cmdlet resets
# $env:PSModulePath BEFORE its first such call.  RELEASE_1.1 111, the wider exposure (9 Oct 2026).
#
#   powershell -ExecutionPolicy Bypass -File test-psmodulepath-units.ps1
#
# WHY: a person who types "powershell -ExecutionPolicy Bypass -File <script>" into a PowerShell 7 window starts a 5.1
# that inherits PowerShell 7's module folders, where the first Security cmdlet (ConvertTo-SecureString, Get-Acl ...)
# fails to load (110).  gpl.bp/ps_scripto resets the path for SD's own scripts; a script a person starts by hand has to
# do it itself.  Measured 9 Oct: install-sdsys.ps1 died at ConvertTo-SecureString with a stand-in Security module first.
# Read from the sources in this folder (every .ps1 here ships or is a harness; a harness that calls a Security cmdlet is
# held to the same rule, which is harmless).  AST for the calls, text for the reset.
# THE NULL CASE IS REFUSED: fewer than 3 scripts with a Security call found means the scan measured nothing (exit 2),
# and a MUTANT (the reset line removed from a copy of install-sdsys.ps1) must be flagged.
# Exit 0 pass, 1 a script lacks the reset, 2 the scan measured nothing.
$ErrorActionPreference = 'Stop'
$sec = @('Get-Acl','Set-Acl','Get-Credential','Get-ExecutionPolicy','Set-ExecutionPolicy','Get-PfxCertificate',
         'Get-AuthenticodeSignature','Set-AuthenticodeSignature','ConvertFrom-SecureString','ConvertTo-SecureString',
         'New-FileCatalog','Test-FileCatalog','Get-CmsMessage','Protect-CmsMessage','Unprotect-CmsMessage','New-CmsMessage')
$rows = New-Object System.Collections.ArrayList
function Row([string]$what, [bool]$ok, [string]$detail = '') {
    $null = $rows.Add($ok)
    Write-Output ('  [{0}] {1}{2}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $what, $(if ($detail) { '   ' + $detail } else { '' }))
}
# Returns, for one file's text: the offset of the first Security-cmdlet call (or -1) and of the reset (or -1).
function Measure-File([string]$path) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
    $first = -1
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $nm = $c.GetCommandName()
        if ($nm -and ($sec -contains $nm)) { if ($first -lt 0 -or $c.Extent.StartOffset -lt $first) { $first = $c.Extent.StartOffset } }
    }
    $text = [IO.File]::ReadAllText($path)
    $m = [regex]::Match($text, '(?m)^\s*\$env:PSModulePath\s*=')
    return [pscustomobject]@{ First = $first; Reset = $(if ($m.Success) { $m.Index } else { -1 }); ParseErrors = $e.Count }
}
Write-Output ('test-psmodulepath-units: scanning ' + $PSScriptRoot)
# SHIPPED = staged by stage.py (see below).  A verify-/probe-/sdtestuser script is developer tooling, started by the
# developer, and is not held to this.
# "Named" means a QUOTED string in stage.py's staging lists: sd.iss and stage.py also mention harness scripts in comments
# (sdtestuser.ps1, verify-sshonly.ps1), and a script sd.iss runs from {app} has to be staged by stage.py anyway.
$shipText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'stage.py'))
$withSec = @()
foreach ($f in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1 -File | Sort-Object Name)) {
    if ($f.Name -like 'test-*') { continue }
    if (-not ($shipText.Contains("'" + $f.Name + "'") -or $shipText.Contains('"' + $f.Name + '"'))) { continue }
    $r = Measure-File $f.FullName
    if ($r.First -ge 0) { $withSec += [pscustomobject]@{ Name = $f.Name; R = $r } }
}
Write-Output ('  scripts with a Security-module call: ' + $withSec.Count + '   (' + (($withSec | ForEach-Object { $_.Name }) -join ', ') + ')')
if ($withSec.Count -lt 3) { Write-Output 'VOID: fewer than 3 shipped scripts with a Security call found - the scan measured nothing'; exit 2 }
foreach ($w in $withSec) {
    Row ($w.Name + ' resets PSModulePath before its first Security call') (($w.R.Reset -ge 0) -and ($w.R.Reset -lt $w.R.First)) ('reset at ' + $w.R.Reset + ', first call at ' + $w.R.First)
}
# the mutant: the shipped reset removed from a scratch copy must be flagged
$src = Join-Path $PSScriptRoot 'install-sdsys.ps1'
$text = [IO.File]::ReadAllText($src)
$mut = [regex]::Replace($text, '(?m)^\$env:PSModulePath\s*=.*$', '# removed by the mutant')
Row 'CONTROL: the mutant text differs from the live file' ($mut -ne $text)
$tmp = Join-Path $env:TEMP ('psmp-mutant-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
try {
    [IO.File]::WriteAllText($tmp, $mut)
    $r = Measure-File $tmp
    Row 'MUTANT (reset removed from install-sdsys.ps1) is flagged' (-not (($r.Reset -ge 0) -and ($r.Reset -lt $r.First)))
} finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
$bad = @($rows | Where-Object { -not $_ }).Count
Write-Output ('test-psmodulepath-units: {0} rows, {1} failed' -f $rows.Count, $bad)
if ($bad -gt 0) { exit 1 } else { Write-Output 'PASSED'; exit 0 }
