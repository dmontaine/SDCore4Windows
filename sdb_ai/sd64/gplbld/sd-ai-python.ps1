# sd-ai-python.ps1 - DOT-SOURCED by sd-ai-ctl.ps1 and install-aihelper.ps1: which Python runs the AI helper.
#
# 13 Nov 26 Windows port - RELEASE_1.1 246 (Linux's AI helper, S.69 step 2).  Linux's helper runs under the system's python3; Windows has no Python of its own,
# so the AI needs the all-users 64-bit Python 3.13 or later that the SD installer offers (its Python box).  ONE COPY of the rule for both callers, and it is
# python-detect.ps1's rule: HKLM PythonCore only (PEP 514) - a per-user install is not reachable by the service account or by SD's accounts - an InstallPath
# that exists, and the highest such version.  Reads the registry; changes nothing.
#
# Find-SdPython returns the full path of python.exe, or '' when there is none.  It prints nothing (a function that prints AND returns hands its caller an array).

function Find-SdPython {
    $best = ''
    $bestVer = [version]'0.0'
    try {
        $root = 'HKLM:\SOFTWARE\Python\PythonCore'
        if (-not (Test-Path -LiteralPath $root)) { return '' }
        foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
            if ($k.PSChildName -notmatch '^(\d+)\.(\d+)$') { continue }
            $v = [version]('{0}.{1}' -f $Matches[1], $Matches[2])
            if ($v -lt [version]'3.13') { continue }
            $ipK = Join-Path $k.PSPath 'InstallPath'
            if (-not (Test-Path -LiteralPath $ipK)) { continue }
            $ip = (Get-ItemProperty -LiteralPath $ipK -ErrorAction Stop).'(default)'
            if (-not $ip) { continue }
            $exe = Join-Path $ip 'python.exe'
            if ((Test-Path -LiteralPath $exe -PathType Leaf) -and $v -gt $bestVer) {
                $best = $exe
                $bestVer = $v
            }
        }
    } catch {
        return ''
    }
    return $best
}
