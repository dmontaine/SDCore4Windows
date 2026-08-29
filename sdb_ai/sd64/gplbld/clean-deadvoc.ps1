# clean-deadvoc.ps1 - remove dead <ACCT>BP.OUT records from SDSYS's VOC
#
#   Run from an ELEVATED PowerShell.  PRE_RELEASE_FIXES 60.
#
# WHAT IT IS FOR.  verify-catgate.ps1 compiled a control program into a scratch
# file <ACCT>BP, and "BASIC <ACCT>BP <name>" made <ACCT>BP.OUT and named it in
# SDSYS's VOC.  Its Remove-Fixtures deleted <ACCT>BP through SD and then removed
# <ACCT>BP.OUT with Remove-Item - which is what the comment on that function
# forbids, one line above it - so SDSYS's VOC was left naming a file that is not
# there.  One per suite run since b59:
#
#     SDCATGB59BP.OUT   Err 30   F   SDCATGB59BP.OUT
#     SDCATGB60BP.OUT   Err 30   F   SDCATGB60BP.OUT
#     SDCATGB61BP.OUT   Err 30   F   SDCATGB61BP.OUT
#     SDCATGB63BP.OUT   Err 30   F   SDCATGB63BP.OUT
#
# verify-catgate.ps1 is fixed, so no more accumulate.  This clears the ones
# already there.  Owner's ruling, 29 Aug 2026: "delete dead voc".
#
# ***IT DELETES ONLY WHAT IT CAN SEE IS DEAD, AND SAYS WHAT IT SKIPPED.***  Two
# conditions, both required:
#
#   1. the record name matches ^SD[A-Z0-9]+BP\.OUT$ - verify-catgate's own
#      naming, "<account upper>BP" plus the .OUT that BASIC appends;
#   2. LISTF reports it as an ERROR record, which is what "the file it names is
#      not there" looks like.  A record whose file EXISTS is not dead and is
#      not touched, however well the name matches.
#
# -WhatIf lists what it would do and deletes nothing.
#
# NOT SHIPPED - it is on assert-current.ps1's $neverShipped list, added in the
# same commit that creates this file (section 7 step 7's rule).

[CmdletBinding()]
param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

# ELEVATION IS REQUIRED AND IS CHECKED OUT LOUD.  Writing SDSYS's VOC is gated,
# and an unelevated run would fail per record with SD's refusal rather than with
# one line saying why.
$elevated = ([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Output 'clean-deadvoc: NOT ELEVATED - refusing.'
    Write-Output '  SDSYS is not writable from an ordinary token.  Open an elevated PowerShell:'
    Write-Output ''
    Write-Output '      C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\clean-deadvoc.ps1'
    exit 2
}
if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output ("clean-deadvoc: no sd.exe at " + $sdExe)
    exit 2
}

# PIPED, NOT -RedirectStandardInput.  A file handle makes SD print
# ":Process terminated" and run nothing - PROJECT_STATUS.md section 6, and it
# cost a run on 29 Aug 2026.  LOGTO SDSYS first and TERM to stop wrapping, the
# shape every elevated script here uses; the leading blank line is a BOM sink.
function Invoke-SdAdmin([string[]]$SdLines) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $SdLines + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($e, $t) $t | & $e } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout 120) { $raw = Receive-Job $job }
    else { Stop-Job $job; $raw = Receive-Job $job; $raw += '*** TIMED OUT - SD is at a prompt' }
    Remove-Job $job -Force
    return (($raw -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

Write-Output ('clean-deadvoc: sd.exe ' + $sdExe)
Write-Output ''

$before = Invoke-SdAdmin @('LISTF NO.PAGE')

# REFUSE THE NULL CASE.  A LISTF that did not run would list nothing, and
# "nothing to delete" would then read exactly like "already clean".
if ($before -notmatch 'Files referenced by the VOC') {
    Write-Output 'clean-deadvoc: LISTF did not run - refusing rather than reporting "nothing found".'
    Write-Output $before
    exit 2
}

# THE ERROR RECORDS, TAKEN FROM LISTF's OWN OUTPUT.  "Err" in the FType column
# is how LISTF says the file a record names is not there.
$dead = @()
foreach ($line in ($before -split "`n")) {
    if ($line -match '^\s*(SD[A-Z0-9]+BP\.OUT)\s+Err\s') { $dead += $Matches[1] }
}

Write-Output ('  dead <ACCT>BP.OUT records found: ' + $(if ($dead.Count) { $dead -join ', ' } else { '(none)' }))

# AND NAME WHAT MATCHED ONE CONDITION BUT NOT BOTH, so a record that looks like
# ours and is NOT dead is visibly left alone rather than silently missed.
foreach ($line in ($before -split "`n")) {
    if ($line -match '^\s*(SD[A-Z0-9]+BP\.OUT)\s+(\S+)' -and $Matches[2] -ne 'Err') {
        Write-Output ('  SKIPPED ' + $Matches[1] + ' - LISTF says "' + $Matches[2] +
                      '", so the file it names is there.  Not dead.')
    }
}

if ($dead.Count -eq 0) {
    Write-Output ''
    Write-Output 'clean-deadvoc: nothing to do.'
    exit 0
}

# ***THE COMMAND LIST IS BUILT ONCE, ABOVE THE -WhatIf BRANCH.***  It was built
# twice - once for -WhatIf to print and once to run - and the two then said
# different things the moment the verb changed on 29 Aug 2026: -WhatIf would
# have gone on promising DELETE.FILE while the run issued DELETE.  A preview
# that can disagree with the action is worse than no preview.

# ***"DELETE VOC <name>", NOT "DELETE.FILE". MEASURED, 29 Aug 2026.***  The
# first version of this script used DELETE.FILE and it changed nothing:
#
#     Error deleting DATA portion 'SDCATGB59BP.OUT'
#     DICT part of file does not exist
#
# on all four records.  DELETEF wants to remove a FILE, and the file these
# records name is already gone - which is the definition of the thing being
# cleaned up.  What has to go is the VOC RECORD itself.
#
# NO PROMPT ON THIS PATH, read from gpl.bp/DELETE rather than hoped for: with
# record names given explicitly it takes the "num.ids > 0" branch straight to
# delete.record, and both of DELETE's "input reply" prompts are in the other
# branches - an active select list (2050) and the ALL keyword (3220) - which
# naming ids makes unreachable.  NO.QUERY is therefore not needed, and DELETE
# does accept it; an unneeded token is what PRE_RELEASE 14 was.
#
# ***AND SD's SUCCESS WORDING IS NOT USABLE AS THE ANCHOR HERE.***  DELETE ends
# with sysmsg 3221, "%1 record(s) deleted", printed UNCONDITIONALLY - so
# "0 record(s) deleted" appears on the failure path too and a match on
# "record(s) deleted" would be a false positive with a check's name on it.
# The verdict below is the second LISTF, which is the artefact.
$cmds = @()
foreach ($d in $dead) { $cmds += ('DELETE VOC ' + $d) }

if ($WhatIf) {
    Write-Output ''
    Write-Output '  -WhatIf: would issue, in one SDSYS session:'
    foreach ($c in $cmds) { Write-Output ('      ' + $c) }
    Write-Output '  Nothing was changed.'
    exit 0
}

Write-Output ''
Write-Output '  --- SD session ---'
foreach ($c in $cmds) { Write-Output ('    > ' + $c) }
$out = Invoke-SdAdmin $cmds
foreach ($l in ($out -split "`n")) { $t = $l.TrimEnd(); if ($t -ne '') { Write-Output ('    | ' + $t) } }

# ***THE CHECK IS A SECOND LISTF, NOT SD's WORDING.***  The instrument rule:
# compare the state before and after, and do not anchor on a message that the
# failure path may also print.
$after = Invoke-SdAdmin @('LISTF NO.PAGE')
if ($after -notmatch 'Files referenced by the VOC') {
    Write-Output ''
    Write-Output 'clean-deadvoc: the verifying LISTF did not run - the result above is unconfirmed.'
    exit 1
}
$left = @()
foreach ($line in ($after -split "`n")) {
    if ($line -match '^\s*(SD[A-Z0-9]+BP\.OUT)\s') { $left += $Matches[1] }
}

Write-Output ''
Write-Output ('  before: ' + $dead.Count + ' dead record(s)')
Write-Output ('  after:  ' + $left.Count + ' <ACCT>BP.OUT record(s) of any kind remain' +
              $(if ($left.Count) { ' - ' + ($left -join ', ') } else { '' }))

if ($left.Count -eq 0) {
    Write-Output 'clean-deadvoc: PASSED - SDSYS s VOC no longer names a file that is not there.'
    exit 0
}
Write-Output 'clean-deadvoc: FAILED - read SD s lines above.'
exit 1
