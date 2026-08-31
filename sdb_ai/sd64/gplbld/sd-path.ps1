# sd-path.ps1 - put SD's program directory on the system PATH, or take it off.
#
#   powershell -File sd-path.ps1 -Show      report, change nothing
#   powershell -File sd-path.ps1 -Add       add it if it is not there
#   powershell -File sd-path.ps1 -Remove    take it off
#
# Exit 0 applied (or -Show succeeded), 1 failed, 2 refused.  ELEVATED for -Add
# and -Remove: the system PATH is a machine-wide setting under HKLM.  -Show
# needs no elevation and changes nothing.
#
# ***WHY IT EXISTS.  OWNER'S RULING, 31 Aug 2026.***  An upgrade is to skip the
# tasks page entirely and fire none of its actions, because a control the reader
# cannot act on is a control that should not be offered (PROJECT_STATUS 5.21).
# That left `addtopath` with no way to be changed after the first install, and
# he named the gap himself: *"we do not have a user command to change the path.
# If we skip page, fire nothing on upgrade we need to have that option available
# as a command."*  This is that command.  It also closes PRE_RELEASE 89's
# defect B, where unticking the box did nothing because the only code that ever
# removed the entry ran at uninstall.
#
# ***IT IS DELIBERATELY THE SAME LOGIC AS sd.iss's RemoveFromPath, NOT A SECOND
# OPINION.***  That procedure has already paid for two bugs and this must not
# re-learn either:
#
#   1. MATCH WITH A SEPARATOR EITHER SIDE, so a directory whose name is a prefix
#      of another entry is not mistaken for it.  That is `NotOnPath`'s rule
#      (sd.iss:3927) and it is why the comparison pads both strings with ';'.
#
#   2. CLEAR THE TRAILING RUN OF EMPTIES, not just the slot we made.  Inno
#      always APPENDS, so SD's entry is always last; the head copy keeps the
#      separator before it and the tail copy starts after the one following it,
#      so removing the last entry leaves a dangling separator.  The owner read
#      his own PATH on 16 Aug 2026 and found *23 empty entries in 30*.  A while
#      loop rather than one strip, because it can only ever delete separators
#      and never an entry - which is what makes it safe on a PATH we do not own.
#      sd.iss:3697 carries the full reasoning.
#
# ***AND ONE TRAP THAT IS THIS SCRIPT'S ALONE, BECAUSE Inno NEVER HAD IT.***
# `[Environment]::SetEnvironmentVariable('Path', ..., 'Machine')` is the obvious
# way to write this and IT CORRUPTS THE PATH: it writes REG_SZ and EXPANDS the
# value on the way through, so an entry written as `%SystemRoot%\system32`
# comes back as a literal `C:\WINDOWS\system32` and stops tracking the variable.
# This reads the RAW value with DoNotExpandEnvironmentNames and writes it back
# as ExpandString, which is what `ValueType: expandsz` does in sd.iss:3948.

[CmdletBinding()]
param(
    [switch]$Show,
    [switch]$Add,
    [switch]$Remove,
    # Defaults to the usr\bin beside this script, which is where it ships:
    # sd.iss installs it into {app} and the directory on PATH is {app}\usr\bin.
    [string]$Dir
)

$ErrorActionPreference = 'Stop'

$PathKey  = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$ValName  = 'Path'

# ---------------------------------------------------------------------------
# THE THREE PURE FUNCTIONS.  They take a PATH string and give one back, touch
# no registry and no machine state, and every rule this script has to get right
# lives in them - which is what lets test-sdpath-units.ps1 lift them out by AST
# and drive them against synthetic values, including the historical 23-empties
# case, without an elevated prompt or a machine to break.
# ---------------------------------------------------------------------------

# Padded with ';' either side so a directory whose name is a PREFIX of another
# entry is not mistaken for it.  NotOnPath's rule, sd.iss:3937.
function Test-DirOnPath {
    param([string]$Current, [string]$Dir)
    return (";$($Current.ToLowerInvariant());").Contains(";$($Dir.ToLowerInvariant());")
}

# Append, matching sd.iss:3948's "{olddata};{app}\usr\bin".  Dangling
# separators are trimmed first so an add never extends a run of empties.
function Get-PathAfterAdd {
    param([string]$Current, [string]$Dir)
    return ($Current.TrimEnd(';') + ';' + $Dir)
}

# Remove by name, then clear the TRAILING RUN of empties - not just the slot we
# made.  See header note 2 and sd.iss:3697: this is the bug that put 23 empty
# entries in 30 on the owner's own PATH.
function Get-PathAfterRemove {
    param([string]$Current, [string]$Dir)
    $padded = ";$($Current.ToLowerInvariant());"
    $at     = $padded.IndexOf(";$($Dir.ToLowerInvariant());")
    if ($at -lt 0) { return $Current }
    # Rebuilt from the ORIGINAL text so surviving entries keep their case -
    # sd.iss:3693 makes the same point.
    $head = $Current.Substring(0, $at)
    # ***CLAMP, AND THIS IS WHERE THE PASCAL ORIGINAL DOES NOT TRANSLATE.***
    # sd.iss:3693 ends with Copy(Path, P + Length(Dir) + 1, MaxInt), and Pascal's
    # Copy returns '' when the start is past the end.  .NET's Substring THROWS.
    # Our entry is LAST on every machine Inno installed - it always appends - so
    # that is the common case, not the edge one, and it took an exception on the
    # third unit test rather than on somebody's PATH.
    $tailStart = $at + $Dir.Length + 1
    if ($tailStart -ge $Current.Length) { $tail = '' }
    else                                { $tail = $Current.Substring($tailStart) }
    $out  = $head + $tail
    if ($out.StartsWith(';')) { $out = $out.Substring(1) }
    return $out.TrimEnd(';')
}

# --- one mode, stated explicitly ------------------------------------------
# No default action.  A script that changes the system PATH when run with no
# arguments is the wrong shape, and the owner's standing preference is the
# explicit keyword over the convenient default.
$modes = @($Show, $Add, $Remove) | Where-Object { $_ }
if ($modes.Count -ne 1) {
    Write-Host 'sd-path: give exactly one of -Show, -Add or -Remove.'
    Write-Host ''
    Write-Host '  powershell -File sd-path.ps1 -Show      report, change nothing'
    Write-Host '  powershell -File sd-path.ps1 -Add       add it if it is not there'
    Write-Host '  powershell -File sd-path.ps1 -Remove    take it off'
    exit 2
}

if ([string]::IsNullOrWhiteSpace($Dir)) {
    $Dir = Join-Path $PSScriptRoot 'usr\bin'
}
# Trailing separators would break the ';'-padded match below.
$Dir = $Dir.TrimEnd('\', '/', ' ')

Write-Host 'sd-path - inputs actually used'
Write-Host "  mode      : $(if ($Show) {'-Show'} elseif ($Add) {'-Add'} else {'-Remove'})"
Write-Host "  directory : $Dir"
Write-Host "  registry  : HKLM\$PathKey [$ValName]"
Write-Host "  this dir exists on disk: $(Test-Path -LiteralPath $Dir)"
Write-Host ''

# --- elevation ------------------------------------------------------------
$elevated = ([Security.Principal.WindowsPrincipal] `
             [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "  elevated  : $elevated"
if ((-not $Show) -and (-not $elevated)) {
    Write-Host ''
    Write-Host 'sd-path: REFUSED - changing the system PATH needs an elevated prompt.'
    Write-Host '         Re-run this from an elevated PowerShell.  -Show works unelevated.'
    exit 2
}

# --- read the RAW value ---------------------------------------------------
# DoNotExpandEnvironmentNames, so %SystemRoot% and friends survive the
# round-trip.  See the header.
try {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($PathKey, -not $Show)
} catch {
    Write-Host "sd-path: could not open the registry key: $($_.Exception.Message)"
    exit 1
}
if ($null -eq $key) {
    Write-Host "sd-path: the registry key does not exist: HKLM\$PathKey"
    exit 1
}

try {
    $raw  = $key.GetValue($ValName, $null,
             [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $kind = $key.GetValueKind($ValName)
} catch {
    Write-Host "sd-path: could not read [$ValName]: $($_.Exception.Message)"
    if ($null -ne $key) { $key.Close() }
    exit 1
}

# REFUSE THE NULL CASE OUT LOUD.  An absent or empty PATH is not "SD is not on
# it" - it is an instrument that has measured nothing, and writing our entry as
# the ONLY entry would be a machine-wrecking repair of a problem we did not
# diagnose.
if ($null -eq $raw -or [string]::IsNullOrWhiteSpace([string]$raw)) {
    Write-Host ''
    Write-Host 'sd-path: REFUSED - the system PATH is missing or empty.'
    Write-Host '         That is not a machine this script should write to.  Nothing done.'
    $key.Close()
    exit 2
}

$raw = [string]$raw
$entriesBefore = @($raw -split ';')
$realBefore    = @($entriesBefore | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$present = Test-DirOnPath -Current $raw -Dir $Dir

Write-Host ''
Write-Host 'BEFORE'
Write-Host "  value kind        : $kind"
Write-Host "  entries           : $($entriesBefore.Count) ($($realBefore.Count) non-empty)"
Write-Host "  SD dir on PATH    : $present"
Write-Host ''

if ($Show) {
    Write-Host 'Entries, in order:'
    for ($i = 0; $i -lt $entriesBefore.Count; $i++) {
        $e = $entriesBefore[$i]
        if ([string]::IsNullOrWhiteSpace($e)) {
            Write-Host ("  [{0}] <EMPTY>" -f $i)
        } else {
            Write-Host ("  [{0}] {1}" -f $i, $e)
        }
    }
    $key.Close()
    Write-Host ''
    Write-Host 'sd-path: -Show changed nothing.'
    exit 0
}

# --- work out the new value ------------------------------------------------
if ($Add) {
    if ($present) {
        Write-Host 'sd-path: already on the system PATH.  Nothing to do.'
        $key.Close()
        exit 0
    }
    # ***REFUSE TO ADD A DIRECTORY THAT IS NOT THERE.***  Run from the source
    # tree the default -Dir resolves to gplbld\usr\bin, which does not exist,
    # and adding it would put a dead entry on the machine PATH while reporting
    # success.  The codebase's own idiom: refuse rather than act on something
    # it could not check.
    if (-not (Test-Path -LiteralPath $Dir)) {
        Write-Host ''
        Write-Host "sd-path: REFUSED - that directory does not exist: $Dir"
        Write-Host '         Pass -Dir with the real one, or run the copy that ships in'
        Write-Host '         C:\Program Files\SD, where the default is correct.'
        $key.Close()
        exit 2
    }
    $rebuilt      = Get-PathAfterAdd -Current $raw -Dir $Dir
    $expectedReal = $realBefore.Count + 1
} else {
    if (-not $present) {
        Write-Host 'sd-path: not on the system PATH.  Nothing to do.'
        $key.Close()
        exit 0
    }
    $rebuilt      = Get-PathAfterRemove -Current $raw -Dir $Dir
    $expectedReal = $realBefore.Count - 1
}

$entriesAfter = @($rebuilt -split ';')
$realAfter    = @($entriesAfter | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

# ***THE GUARD THAT MAKES THIS SAFE ON A PATH WE DO NOT OWN.***  Exactly one
# real entry may appear or disappear, and every OTHER entry must survive
# unchanged and in order.  A string edit that got its arithmetic wrong fails
# here rather than on the machine.
$survivors = @($realAfter | Where-Object { $_.ToLowerInvariant() -ne $Dir.ToLowerInvariant() })
$expectedSurvivors = @($realBefore | Where-Object { $_.ToLowerInvariant() -ne $Dir.ToLowerInvariant() })
$intact = ($survivors.Count -eq $expectedSurvivors.Count)
if ($intact) {
    for ($i = 0; $i -lt $survivors.Count; $i++) {
        # -cne: PowerShell compares case-insensitively by default, and a case
        # change to somebody else's PATH entry is still a change.
        if ($survivors[$i] -cne $expectedSurvivors[$i]) { $intact = $false; break }
    }
}

Write-Host 'AFTER (proposed)'
Write-Host "  entries           : $($entriesAfter.Count) ($($realAfter.Count) non-empty)"
Write-Host "  expected non-empty: $expectedReal"
Write-Host "  other entries intact and in order: $intact"

if (($realAfter.Count -ne $expectedReal) -or (-not $intact)) {
    Write-Host ''
    Write-Host 'sd-path: REFUSED - the rebuilt PATH is not what was intended.'
    Write-Host '         Nothing was written.  The BEFORE value is untouched.'
    $key.Close()
    exit 2
}

# --- write it back ---------------------------------------------------------
try {
    $key.SetValue($ValName, $rebuilt, [Microsoft.Win32.RegistryValueKind]::ExpandString)
} catch {
    Write-Host "sd-path: the write FAILED: $($_.Exception.Message)"
    $key.Close()
    exit 1
}
$key.Close()

# Read it back rather than trusting the write.
$verify = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($PathKey, $false)
$back = $verify.GetValue($ValName, $null,
         [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$backKind = $verify.GetValueKind($ValName)
$verify.Close()

Write-Host ''
Write-Host 'VERIFIED BY READ-BACK'
Write-Host "  value kind        : $backKind  (must stay ExpandString)"
$nowPresent = (";$(([string]$back).ToLowerInvariant());").Contains(";$($Dir.ToLowerInvariant());")
Write-Host "  SD dir on PATH    : $nowPresent"

if ([string]$back -cne $rebuilt) {
    Write-Host 'sd-path: the value read back does not match what was written.'
    exit 1
}
if ($backKind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) {
    Write-Host 'sd-path: the value kind is no longer ExpandString - %VARS% would stop expanding.'
    exit 1
}
if ($Add -and (-not $nowPresent)) { Write-Host 'sd-path: -Add did not take.'; exit 1 }
if ($Remove -and $nowPresent)     { Write-Host 'sd-path: -Remove did not take.'; exit 1 }

# --- tell the rest of Windows ----------------------------------------------
# Without this the change reaches new processes only after a sign-out or
# reboot.  Inno broadcasts it for its own [Registry] Environment writes; a
# script has to do it itself.  SendMessageTimeout, not SendMessage: a hung
# top-level window would otherwise hang this script indefinitely.
try {
    if (-not ('SdPathNative' -as [type])) {
        Add-Type -Namespace '' -Name 'SdPathNative' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(
    System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
    }
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1A
    $SMTO_ABORTIFHUNG = 0x0002
    $res = [UIntPtr]::Zero
    [void][SdPathNative]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE,
            [IntPtr]::Zero, 'Environment', $SMTO_ABORTIFHUNG, 5000, [ref]$res)
    Write-Host '  broadcast         : WM_SETTINGCHANGE sent'
} catch {
    # Not fatal: the registry is already correct, and a sign-out picks it up.
    Write-Host "  broadcast         : could not send WM_SETTINGCHANGE ($($_.Exception.Message))"
    Write-Host '                      The PATH IS set; new shells see it after a sign-out.'
}

Write-Host ''
if ($Add) {
    Write-Host 'sd-path: added.  Open a NEW terminal - an existing one keeps the PATH it started with.'
} else {
    Write-Host 'sd-path: removed.  Open a NEW terminal - an existing one keeps the PATH it started with.'
}
exit 0
