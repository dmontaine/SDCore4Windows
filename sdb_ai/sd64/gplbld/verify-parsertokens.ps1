# verify-parsertokens.ps1 - prove a TCL token is NOT split at a backslash, and
# IS still split at the punctuation the parser is supposed to split at.
# PROJECT_STATUS.md 7 step 12.
#
#   powershell -File verify-parsertokens.ps1
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# RUN IT AS AN ORDINARY SD USER.  It needs no elevation and spends no prefix:
# it creates nothing, reads nothing it does not already own, and asks about
# record ids that do not exist.  Elevation is not refused either - nothing here
# depends on the token.
#
# WHAT IT GUARDS.  gpl.bp/PARSER splits a simple token at a comma, a right
# bracket or a string quote.  Upstream splits at a BACKSLASH too, guarded by
# "if not(is.windows)"; this port kept the body and dropped the guard, on a
# build where a backslash is a path separator.  Every native path typed at TCL
# was therefore truncated at the first backslash - CREATE.ACCOUNT OTHER takes
# its pathname through this parser at CREATEA:466, so an account went to the
# wrong place or the command failed for a reason that made no sense.
#
# THE READING BEFORE THE FIX, on the 22 Aug 21:34:25 install:
#
#   RUN BP C:\Temp\zznosuch  ->  Program BP.OUT C: not found
#   RUN BP C:/Temp/zznosuch  ->  Program BP.OUT C:/Temp/zznosuch not found
#
# CT AND NOT RUN, AND THAT IS NOT A PREFERENCE.  RUN echoes both names through
# message 5073 only once the account HAS AN OBJECT PART to look in; on a fresh
# account nothing has been compiled, bp.out does not exist, and RUN answers
# "Cannot find item to run" without echoing anything.  That is how the original
# instrument stopped working between two installs on the same day.  CT reads
# the VOC, which every account has from the moment it is made.
#
# THE COMMA ROW IS WHAT MAKES THE BACKSLASH ROW MEAN ANYTHING.  A whole path
# coming back could equally mean CT never reaches the parser at all - in which
# case this script would pass just as happily with the defect restored.  So it
# also asks for a token the parser MUST still split, and a pass requires both:
# the backslash kept, the comma split.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# A CURRENT INSTALL FIRST.  This measures shipped BASIC, which the installer
# never overwrites in an existing data tree - so on a stale install it reads
# the PARSER that was there before the fix and blames the fix for it.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-parsertokens: refusing - see above'
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output "verify-parsertokens: refusing - no $sdExe"
    exit 2
}

# LOWER CASE, because 22 Aug 2026 made account names lower (5.12) - and the
# lookup is case-insensitive on NTFS in any case, so this survived the rename
# either way.  The session must START in the account directory: LOGIN:430
# derives the account from the working directory.
$acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $env:USERNAME.ToLower())
if (-not (Test-Path -LiteralPath $acctDir)) {
    Write-Output "verify-parsertokens: refusing - $env:USERNAME has no SD account at $acctDir"
    exit 2
}

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($check, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
}

# ------------------------------------------------------------------- the probe

# Ids that cannot exist, so every answer is the "not found" message and nothing
# is created.  CT echoes the id it was refused, which is the whole instrument.
$bsPath = 'C:\Temp\zznosuch'
$fsPath = 'C:/Temp/zznosuch'

# THE LEADING BLANK LINE IS A BOM SINK, not a stray newline - the pipe prepends
# a BOM whatever $OutputEncoding says, and it lands on a line that was empty
# anyway instead of eating a real command.  PROJECT_STATUS.md 6.
$body = "`n" + (@(
    "CT VOC $bsPath"
    "CT VOC $fsPath"
    'CT VOC zznosuch'
    'CT VOC a,b'
    'OFF'
) -join "`n") + "`n"

Push-Location -LiteralPath $acctDir
try {
    $raw = $body | & $sdExe 2>&1
}
catch {
    Write-Output "verify-parsertokens: could not drive sd.exe: $($_.Exception.Message)"
    exit 2
}
finally {
    Pop-Location
}

$text = (($raw -replace "`e\[[0-9]*[A-Za-z]", '') | Out-String)

# A SESSION THAT NEVER STARTED MUST NOT READ AS A MEASUREMENT.  With no
# "not found" line at all there is nothing to score, and scoring absence would
# report the defect present whatever the parser did.
if ($text -notmatch "Record '") {
    Write-Output 'verify-parsertokens: the probe did not run - no "Record ..." line in the output.'
    Write-Output '  Raw output follows.'
    Write-Output $text
    exit 2
}

# -A LITERAL, NOT A REGEX, and not -SimpleMatch either.  The path holds a
# backslash; as a regex "C:\Temp" would mean an escape, and -SimpleMatch on
# Select-String has bitten this tree twice by taking the pattern TOO literally.
# .Contains() on one string has neither layer.
function Saw([string]$id) { return $text.Contains("Record '" + $id + "' not found") }

Note 'a backslash path comes back WHOLE'      $true (Saw $bsPath)  $true
Note 'control: a forward-slash path is whole' $true (Saw $fsPath)  $true
Note 'control: a bare name is whole'          $true (Saw 'zznosuch') $true

# The parser must STILL split at a comma.  Without this row the script cannot
# tell "the backslash split is gone" from "the parser was never consulted".
Note 'a comma still splits: first token'  $true (Saw 'a') $true
Note 'a comma still splits: the comma'    $true (Saw ',') $true
Note 'a comma still splits: last token'   $true (Saw 'b') $true

# The failure this exists to catch, stated as its own row so the report names
# it rather than leaving it to be inferred from the first row's absence.
Note 'the truncated form is NOT seen'     $true (-not (Saw 'C:')) $true

$results | Format-Table -AutoSize | Out-String | Write-Output

if ($fatal) {
    Write-Output 'verify-parsertokens: FAILED.'
    Write-Output ''
    if (Saw 'C:') {
        Write-Output "  It answered Record 'C:' - the token was cut at the first backslash."
        Write-Output '  gpl.bp/PARSER has the split back; PROJECT_STATUS.md 7 step 12 has why'
        Write-Output '  it must not, and sdb64 carries the same line correctly for Linux.'
    } elseif (-not (Saw 'a')) {
        Write-Output '  The COMMA rows failed, which is the opposite fault: the parser is not'
        Write-Output '  splitting where it should, or CT no longer reaches it. The backslash'
        Write-Output '  row cannot be trusted on its own in that state.'
    }
    exit 1
}

Write-Output 'verify-parsertokens: PASSED - backslash kept, comma still split.'
exit 0
