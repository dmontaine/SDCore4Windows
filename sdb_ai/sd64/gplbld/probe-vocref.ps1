# probe-vocref.ps1 - does a file made with CREATE.FILE ... PATHNAME open? (RELEASE_1.1 189, _voc_ref's test for an absolute path)
#
#   powershell -ExecutionPolicy Bypass -File C:\...\gplbld\probe-vocref.ps1        an ordinary UNELEVATED PowerShell, SD running
#
# THE PROBLEM IT MEASURES.  CREATE.FILE ... PATHNAME <dir> writes the pointer with forward slashes (C:/Users/...).  _voc_ref's "is this absolute" test wanted C:\ or
# a leading separator, so it put the account directory in front of the pointer's path and the file "was not found": COUNT said "File not found" and CREATE.FILE itself
# said "Unable to open newly created dictionary" (measured on the Core host, 26 Oct 2026).  Fixed in _voc_ref (Core and Solo).
#
# WHAT IT DOES.  As the signed-in user, in that user's own SD account: makes a throwaway folder, CREATE.FILE zzvoc189 DYNAMIC PATHNAME <folder> NO.QUERY,
# CT VOC zzvoc189 (to print the pointer), COUNT zzvoc189, DELETE.FILE zzvoc189 (answering Y to both questions).  It anchors on the SUCCESS wording
# ("N record(s) counted") and treats "File not found" and "Unable to open newly created dictionary" as disqualifiers, and prints sd's raw answer every time.
# The account needs no gate for CREATE.FILE or COUNT; DELETE.FILE of the pointer needs none either when the file is deleted with it.  Exit 0 it opens, 1 it does not, 2 it could not run.

param(
    # Which product's sd to drive.  Core is the default; "-Product Solo" uses the signed-in user's SDCoreSolo (the install the Solo cycle makes under the user profile).
    [ValidateSet('Core', 'Solo')][string]$Product = 'Core',
    [string]$AppDir = (Join-Path $env:ProgramFiles 'SD')
)
$ErrorActionPreference = 'Continue'
if ($Product -eq 'Solo') { $sd = Join-Path $env:USERPROFILE 'SDCoreSolo\usr\bin\sd-solo.exe' }
else { $sd = Join-Path $AppDir 'usr\bin\sd.exe' }
Write-Output ("  product: $Product")
Write-Output ("probe-vocref: " + (Get-Date -Format 's'))
Write-Output ("  user : " + $env:USERNAME)
Write-Output ("  sd   : $sd  exists=" + (Test-Path $sd))
if (-not (Test-Path $sd)) { Write-Output 'REFUSED: no sd.exe or sd-solo.exe found'; exit 2 }
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($elev) { Write-Output 'REFUSED: run this UNELEVATED (an elevated session is the administrator, not the ordinary account this measures)'; exit 2 }

$dir = Join-Path $env:TEMP ('zzvoc189dir-' + $PID)
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Write-Output "  dir  : $dir"
$lines = @('TERM 200,9999', "CREATE.FILE zzvoc189 DYNAMIC PATHNAME $dir NO.QUERY", 'CT VOC zzvoc189', 'COUNT zzvoc189', 'DELETE.FILE zzvoc189', 'Y', 'Y', 'OFF')
$body = "`n" + ($lines -join "`n") + "`n"
# SOLO CANNOT BE MEASURED HERE, AND THE OBVIOUS SUBSTITUTE WOULD PASS FOR THE WRONG REASON.  Solo asks for the user's password at sign-on, which a piped session cannot
# give ("Wrong password / Connection terminated"); and an -internal session (the installer's door) opens a PATHNAME file correctly on the OLD build too, because the bug
# is in _voc_ref, which only an ordinary user's session goes through (the kernel opens for an administrator or internal session directly).  Measured 28 Oct 2026:
# the -internal run printed "0 record(s) counted" on a Solo install built before the fix.  So Solo has to be done by hand, signed on as the user.
if ($Product -eq 'Solo') {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "`nprobe-vocref: COULD NOT RUN for Solo - it asks for a password at sign-on and an internal session would pass on the unfixed build too."
    Write-Output '  By hand: start Solo, run sd-solo.exe in a console and sign on as yourself, then type, one line each:'
    Write-Output '      CREATE.FILE zzvoc189 DYNAMIC PATHNAME C:\Users\<you>\AppData\Local\Temp NO.QUERY'
    Write-Output '      COUNT zzvoc189'
    Write-Output '      DELETE.FILE zzvoc189       (answer Y twice)'
    Write-Output '  It passes when COUNT says "0 record(s) counted" and neither "File not found" nor "Unable to open newly created dictionary" appears.'
    exit 2
}
$out = $body | & $sd 2>&1
$text = (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
Write-Output "`n--- what sd said (raw) ---"
($text -split "`n") | Where-Object { $_.Trim() -ne '' } | ForEach-Object { Write-Output ("  | " + $_.TrimEnd()) }
Write-Output '--- end ---'

if ($text -match 'SD has not been started') {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "`nprobe-vocref: COULD NOT RUN - SD is not started, so nothing was measured (Start-Service SD, or the Solo task, from an elevated shell)."
    exit 2
}
if ($text -match 'Wrong password|Connection terminated') {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "`nprobe-vocref: COULD NOT RUN - the session asked for a password, so nothing was measured."
    exit 2
}
$counted = ($text -match '\d+ record\(s\) counted')
$notFound = ($text -match 'File not found')
$cantOpen = ($text -match 'Unable to open newly created dictionary')
Write-Output ("  COUNT said '<n> record(s) counted'   : $counted    (must be True)")
Write-Output ("  'File not found' appeared            : $notFound    (must be False)")
Write-Output ("  'Unable to open newly created ...'   : $cantOpen    (must be False)")
Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
if ($counted -and -not $notFound -and -not $cantOpen) { Write-Output "`nprobe-vocref: the file made with PATHNAME opens."; exit 0 }
Write-Output "`nprobe-vocref: FAILED - read the raw lines above."
exit 1
