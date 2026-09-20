# internal-marker.ps1 - the one-shot authorisation an "sd -internal" session needs.
# RELEASE_1.1 82 (D2').  DOT-SOURCED, never run: it defines two functions and does
# nothing else, and it ships beside the install scripts that use it.
#
# WHAT IT IS FOR.  LOGIN (sdsys/gpl.bp/login, the K$INTERNAL branch) admits an
# "sd -internal" session only while a marker file exists in the SDSYS directory,
# and DELETES it on admission.  So the developer door is closed on a delivered
# system - "sd -internal" from anyone, an elevated administrator included, gets no
# session - and whoever legitimately starts an internal session (the installer's own
# steps, the bootstrap, a development verifier) writes ONE marker immediately
# before it.  The consumer closes the window, not the writer: a marker that was
# written and never used authorises exactly one later session and expires.
#
# THE OWNER'S STANDARD, 20 Sep 2026: "the developer mode switch is not a published
# feature, it has to be discovered by looking at the source code, which is fine in
# an open source product."  This is a speed bump for an administrator, not a
# boundary - an administrator can write the file by hand, and the SDSYS directory
# is writable by sdusers as well - and the file says so rather than pretending.
#
# THE CONTRACT WITH LOGIN, and both sides are checked by test-internalgate-units.py:
#   path      <sdsys>\$internal            (LOGIN builds it as @sdsys:@ds:'$internal')
#   line 1    "<writer> pid=<pid> <ISO time>" - read by LOGIN for its audit line only
#   freshness LOGIN refuses a marker older than its own expiry (10 minutes)
#   encoding  UTF-8 WITHOUT a BOM: LOGIN reads line 1 with READSEQ, and a BOM would
#             land in the audit record as three stray characters
#
# BOTH FUNCTIONS RETURN A BOOLEAN AND PRINT NOTHING.  A function that writes with
# Write-Output AND returns a value folds its output into the return value (three
# occurrences in this tree); these do neither.
#
#   Set-SdInternalMarker    -SdsysDir <dir> -Writer <name>   $true when the marker is there afterwards
#   Remove-SdInternalMarker -SdsysDir <dir>                  $true when NO marker is there afterwards

function Set-SdInternalMarker {
    param(
        [Parameter(Mandatory = $true)] [string] $SdsysDir,
        [Parameter(Mandatory = $true)] [string] $Writer
    )
    $path = Join-Path $SdsysDir '$internal'
    try {
        if (-not (Test-Path -LiteralPath $SdsysDir)) { return $false }
        $line = ('{0} pid={1} {2}' -f ($Writer -replace '[^\x20-\x7E]', '?'), $PID, (Get-Date).ToString('o'))
        [IO.File]::WriteAllText($path, $line + "`n", (New-Object Text.UTF8Encoding($false)))
        return (Test-Path -LiteralPath $path)
    }
    catch { return $false }
}

function Remove-SdInternalMarker {
    param([Parameter(Mandatory = $true)] [string] $SdsysDir)
    $path = Join-Path $SdsysDir '$internal'
    try {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
        return (-not (Test-Path -LiteralPath $path))
    }
    catch { return (-not (Test-Path -LiteralPath $path)) }
}
