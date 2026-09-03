# vm-type.ps1 - type into a VirtualBox guest from the host, with no guest
# credentials.
#
#   powershell -ExecutionPolicy Bypass -File vm-type.ps1 -Vm '<name>' -Text 'dir'
#   powershell -ExecutionPolicy Bypass -File vm-type.ps1 -Vm '<name>' -Keys ENTER
#   powershell -ExecutionPolicy Bypass -File vm-type.ps1 -Vm '<name>' -Keys 'WIN+r'
#
# ===========================================================================
# WHY THIS EXISTS AT ALL
# ===========================================================================
#
# The witness runs this project cannot do any other way - an INTERACTIVE
# uninstall, an installer wizard, a closing box read as the user sees it - all
# happen on a VirtualBox guest, and the record allows exactly one route into
# one:
#
#   guestcontrol         FORBIDDEN.  It needs guest credentials.
#   keyboardputstring    DROPS CHARACTERS (HISTORY 1931).  Not usable for a
#                        command whose failure mode is a silently different
#                        command.
#   keyboardputscancode  what is left, and what the record recommends beside
#                        screenshotpng.
#
# Every guest session so far has hand-assembled its own scancodes.  That is
# slow, it is where a mistyped path comes from, and it is the same table
# rewritten each time - so it is a script now.
#
# ===========================================================================
# THE TWO THINGS THAT MAKE TYPED INPUT GO WRONG, BOTH HANDLED HERE
# ===========================================================================
#
# 1. ***A KEY LEFT DOWN.***  Every make code must get its break code.  If a run
#    is interrupted between the two, the guest keeps the key held and every
#    later keystroke arrives shifted or ctrl-ed - which looks like a broken
#    guest rather than a broken send.  Each character here is sent as a
#    COMPLETE make/break group, so a chunk boundary can never fall inside one,
#    and -Release sends the break codes for the modifiers on their own if a
#    previous run did strand one.
#
# 2. ***A CHUNK TOO LONG FOR THE COMMAND LINE.***  keyboardputscancode takes
#    the bytes as arguments, so a long line becomes a long argv.  Sent in
#    groups of $ChunkBytes, split only ON a group boundary.
#
# THE BACKSLASH RULE THE RECORD ASKS FOR IS SATISFIED STRUCTURALLY.
# PROJECT_STATUS says to send every backslash on its own; that advice is about
# hand-built chunks, and here no chunk can ever split a character's own codes,
# backslash included.
#
# ===========================================================================
# WHAT IT WILL NOT DO
# ===========================================================================
#
# ***IT REFUSES A CHARACTER IT HAS NO CODE FOR, LOUDLY, AND TYPES NOTHING.***
# It does not skip it and it does not send a near miss.  A path silently
# missing one character is a wrong command that looks like the right one, and
# the whole reason the record rejects keyboardputstring is that it does that.
# Refusing before sending anything means a bad -Text costs a message, never a
# half-typed line in a live installer.
#
# The map is the US layout the guests use.  A guest on another layout would
# need its own table, and this script would type the wrong punctuation rather
# than notice - so if a guest is ever built with a different layout, that fact
# belongs beside this comment.

[CmdletBinding()]
param(
    # The VM name exactly as VBoxManage list vms prints it.
    [Parameter(Mandatory = $true)] [string] $Vm,

    # Literal text to type.  No trailing Enter is added - ask for it with
    # -Keys ENTER, or -Enter.
    [string] $Text,

    # Named keys and chords, e.g. ENTER, TAB, ESC, F4, UP, 'WIN+r',
    # 'CTRL+SHIFT+ENTER', 'ALT+y'.  Several may be given.
    [string[]] $Keys,

    # Convenience: send ENTER after -Text.
    [switch] $Enter,

    # Send only the modifier break codes, to clear a key stranded by an
    # interrupted run.
    [switch] $Release,

    # Bytes per keyboardputscancode call.  Split only on a group boundary.
    [int] $ChunkBytes = 60,

    [string] $VBoxManage = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $VBoxManage)) {
    Write-Host ("vm-type: VBoxManage not found at " + $VBoxManage) -ForegroundColor Red
    exit 2
}

# --- SCANCODE SET 1, US LAYOUT ---------------------------------------------
# Make code only; the break code is make + 0x80 and is computed, never listed,
# so the two cannot drift apart.
$unshifted = @{
    'a' = 0x1E; 'b' = 0x30; 'c' = 0x2E; 'd' = 0x20; 'e' = 0x12; 'f' = 0x21
    'g' = 0x22; 'h' = 0x23; 'i' = 0x17; 'j' = 0x24; 'k' = 0x25; 'l' = 0x26
    'm' = 0x32; 'n' = 0x31; 'o' = 0x18; 'p' = 0x19; 'q' = 0x10; 'r' = 0x13
    's' = 0x1F; 't' = 0x14; 'u' = 0x16; 'v' = 0x2F; 'w' = 0x11; 'x' = 0x2D
    'y' = 0x15; 'z' = 0x2C
    '1' = 0x02; '2' = 0x03; '3' = 0x04; '4' = 0x05; '5' = 0x06; '6' = 0x07
    '7' = 0x08; '8' = 0x09; '9' = 0x0A; '0' = 0x0B
    '-' = 0x0C; '=' = 0x0D; '[' = 0x1A; ']' = 0x1B; ';' = 0x27; "'" = 0x28
    '`' = 0x29; '\' = 0x2B; ',' = 0x33; '.' = 0x34; '/' = 0x35; ' ' = 0x39
}

# The shifted face of the same physical key.  Upper-case letters are handled
# by rule below rather than listed twice.
$shifted = @{
    '!' = 0x02; '@' = 0x03; '#' = 0x04; '$' = 0x05; '%' = 0x06; '^' = 0x07
    '&' = 0x08; '*' = 0x09; '(' = 0x0A; ')' = 0x0B
    '_' = 0x0C; '+' = 0x0D; '{' = 0x1A; '}' = 0x1B; ':' = 0x27; '"' = 0x28
    '~' = 0x29; '|' = 0x2B; '<' = 0x33; '>' = 0x34; '?' = 0x35
}

# Named keys.  A value of the form 'E0,xx' is an extended key and carries the
# E0 prefix on both the make and the break.
$named = @{
    'ENTER' = '1C'; 'RETURN' = '1C'; 'TAB' = '0F'; 'ESC' = '01'
    'BACKSPACE' = '0E'; 'BKSP' = '0E'; 'SPACE' = '39'; 'DELETE' = 'E0,53'
    'UP' = 'E0,48'; 'DOWN' = 'E0,50'; 'LEFT' = 'E0,4B'; 'RIGHT' = 'E0,4D'
    'HOME' = 'E0,47'; 'END' = 'E0,4F'; 'PGUP' = 'E0,49'; 'PGDN' = 'E0,51'
    'F1' = '3B'; 'F2' = '3C'; 'F3' = '3D'; 'F4' = '3E'; 'F5' = '3F'
    'F6' = '40'; 'F7' = '41'; 'F8' = '42'; 'F9' = '43'; 'F10' = '44'
    'F11' = '57'; 'F12' = '58'
}

$modifiers = @{ 'SHIFT' = 0x2A; 'CTRL' = 0x1D; 'ALT' = 0x38; 'WIN' = 'E0,5B' }

function Add-Code {
    param([System.Collections.ArrayList] $List, $Code, [switch] $Break)
    # $Code is either an int make code or an 'E0,xx' extended string.
    if ($Code -is [string] -and $Code -like 'E0,*') {
        $b = [Convert]::ToInt32($Code.Substring(3), 16)
        if ($Break) { $b = $b -bor 0x80 }
        [void]$List.Add('e0')
        [void]$List.Add('{0:x2}' -f $b)
    } else {
        $b = [int] $Code
        if ($Break) { $b = $b -bor 0x80 }
        [void]$List.Add('{0:x2}' -f $b)
    }
}

function Get-TextCodes {
    param([string] $s)
    $codes = New-Object System.Collections.ArrayList
    $bad   = New-Object System.Collections.ArrayList
    foreach ($ch in $s.ToCharArray()) {
        $c = [string] $ch
        $needShift = $false
        $make = $null

        if ($c -cmatch '^[A-Z]$') {
            $make = $unshifted[$c.ToLower()]
            $needShift = $true
        } elseif ($unshifted.ContainsKey($c)) {
            $make = $unshifted[$c]
        } elseif ($shifted.ContainsKey($c)) {
            $make = $shifted[$c]
            $needShift = $true
        } else {
            [void]$bad.Add($c)
            continue
        }

        # ONE COMPLETE GROUP PER CHARACTER, shift included, so a chunk boundary
        # can never leave a key down.
        if ($needShift) { Add-Code -List $codes -Code $modifiers['SHIFT'] }
        Add-Code -List $codes -Code $make
        Add-Code -List $codes -Code $make -Break
        if ($needShift) { Add-Code -List $codes -Code $modifiers['SHIFT'] -Break }
    }
    return @{ Codes = $codes; Bad = $bad }
}

function Get-ChordCodes {
    param([string] $chord)
    # 'CTRL+SHIFT+ENTER' / 'WIN+r' / 'ENTER'.  The last part is the key; every
    # earlier part is a modifier held around it.
    #
    # ***THE @() IS LOAD-BEARING AND ITS ABSENCE BROKE EVERY SINGLE-TOKEN KEY.***
    # A pipeline that yields ONE item unrolls to a scalar, so 'ESC'.Split('+')
    # came back as the STRING 'ESC' rather than a one-element array - and then
    # $parts[-1] indexed the string and returned the CHARACTER 'C', which has no
    # .ToUpper().  -Keys ESC died while -Keys 'WIN+r' worked, because two parts
    # stay an array.  The count guard below is the same bug's other half:
    # $parts[0..($parts.Count - 2)] on one element is $parts[0..-1], which is
    # the whole thing rather than nothing.
    $parts = @($chord.Split('+') | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return $null }

    $keyPart = [string] $parts[$parts.Count - 1]
    $mods    = if ($parts.Count -gt 1) { @($parts[0..($parts.Count - 2)]) } else { @() }
    $codes   = New-Object System.Collections.ArrayList

    $held = @()
    foreach ($m in $mods) {
        $mu = $m.ToUpper()
        if (-not $modifiers.ContainsKey($mu)) { return @{ Error = ("unknown modifier '" + $m + "'") } }
        $held += ,$modifiers[$mu]
    }

    $ku   = $keyPart.ToUpper()
    $make = $null
    if ($named.ContainsKey($ku)) {
        $v = $named[$ku]
        if ($v -like 'E0,*') { $make = $v } else { $make = [Convert]::ToInt32($v, 16) }
    } elseif ($keyPart.Length -eq 1 -and $unshifted.ContainsKey($keyPart.ToLower())) {
        $make = $unshifted[$keyPart.ToLower()]
    } elseif ($modifiers.ContainsKey($ku)) {
        # A chord that is only modifiers, e.g. 'WIN'.
        $make = $modifiers[$ku]
    } else {
        return @{ Error = ("unknown key '" + $keyPart + "'") }
    }

    foreach ($h in $held) { Add-Code -List $codes -Code $h }
    Add-Code -List $codes -Code $make
    Add-Code -List $codes -Code $make -Break
    for ($i = $held.Count - 1; $i -ge 0; $i--) { Add-Code -List $codes -Code $held[$i] -Break }
    return @{ Codes = $codes }
}

function Send-Codes {
    param([System.Collections.ArrayList] $codes, [string] $what)
    if ($codes.Count -eq 0) { return }
    $sent = 0
    for ($i = 0; $i -lt $codes.Count; $i += $ChunkBytes) {
        $end   = [Math]::Min($i + $ChunkBytes, $codes.Count) - 1
        $chunk = $codes[$i..$end]
        & $VBoxManage controlvm $Vm keyboardputscancode @chunk | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("vm-type: keyboardputscancode exited " + $LASTEXITCODE) -ForegroundColor Red
            exit 3
        }
        $sent += $chunk.Count
        Start-Sleep -Milliseconds 40
    }
    # RULE 1 OF THE INSTRUMENT SECTION: say what was actually sent, not what
    # was asked for.
    Write-Host ("vm-type: {0}  {1} byte(s) sent to {2}" -f $what, $sent, $Vm)
}

# --- WHAT THIS RUN IS, PRINTED BEFORE IT ACTS ------------------------------
Write-Host ("vm-type: vm    " + $Vm)

if ($Release) {
    $codes = New-Object System.Collections.ArrayList
    foreach ($m in 'SHIFT', 'CTRL', 'ALT', 'WIN') {
        Add-Code -List $codes -Code $modifiers[$m] -Break
    }
    Send-Codes -codes $codes -what 'modifier release'
    exit 0
}

if (-not $PSBoundParameters.ContainsKey('Text') -and -not $Keys -and -not $Enter) {
    Write-Host 'vm-type: nothing to send.  Pass -Text, -Keys or -Enter.' -ForegroundColor Red
    Write-Host 'REFUSED rather than exiting 0 on a run that would have typed nothing.' -ForegroundColor Yellow
    exit 2
}

if ($PSBoundParameters.ContainsKey('Text')) {
    Write-Host ("vm-type: text  [" + $Text + "]")
    Write-Host ("vm-type: chars " + $Text.Length)
    $r = Get-TextCodes -s $Text
    if ($r.Bad.Count -gt 0) {
        # NOTHING HAS BEEN SENT YET, and that is the point of checking first.
        $shown = ($r.Bad | ForEach-Object { "'" + $_ + "'" }) -join ' '
        Write-Host ("vm-type: REFUSED - no scancode for " + $r.Bad.Count + " character(s): " + $shown) -ForegroundColor Red
        Write-Host 'Nothing was typed.  A half-typed line in a live installer is worse than none.' -ForegroundColor Yellow
        exit 2
    }
    Send-Codes -codes $r.Codes -what 'text'
}

foreach ($k in @($Keys)) {
    if ([string]::IsNullOrWhiteSpace($k)) { continue }
    $c = Get-ChordCodes -chord $k
    if ($null -eq $c) { continue }
    if ($c.ContainsKey('Error')) {
        Write-Host ("vm-type: REFUSED - " + $c.Error) -ForegroundColor Red
        exit 2
    }
    Send-Codes -codes $c.Codes -what ("key " + $k)
}

if ($Enter) {
    $c = Get-ChordCodes -chord 'ENTER'
    Send-Codes -codes $c.Codes -what 'key ENTER'
}

exit 0
