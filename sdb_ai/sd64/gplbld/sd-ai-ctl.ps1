# sd-ai-ctl.ps1 - run the AI helper's administrator client (sd-ai-ctl, Python) under the all-users Python.
#
#   & 'C:\Program Files\SD\lib\sd-ai\sd-ai-ctl.ps1' 'show'          (SET.AI runs it so; the words are sd-ai-ctl's own)
#
# 13 Nov 26 Windows port - RELEASE_1.1 246 (Linux's AI helper, S.69 step 2).  Linux's set.ai runs /usr/local/lib/sd-ai/sd-ai-ctl, a python3 script, directly.
# Windows has no Python of its own, so this finds the one the SD installer offers (Find-SdPython, sd-ai-python.ps1) and runs the client with it, isolated
# (-I: no PYTHON* variables, no user site, not the script's folder first) and writing no bytecode (-B: the program folder is not the caller's to write).
# With no usable Python it prints ONE line, "error: nopython: ...", which SET.AI turns into message 12934; it prints it on standard output like everything
# the client prints, because SET.AI reads standard output only (PowerShell 5.1 would wrap standard error in error records).
# Exit: the client's own (0 done, 1 the helper refused, 2 not reached), or 1 with no Python.

. (Join-Path $PSScriptRoot 'sd-ai-python.ps1')

$py = Find-SdPython
if (-not $py) {
    Write-Output 'error: nopython: no Python 3.13 or later is installed for all users'
    exit 1
}
& $py -I -B (Join-Path $PSScriptRoot 'sd-ai-ctl') @args
exit $LASTEXITCODE
