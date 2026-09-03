# capture-state.ps1 - record a machine's SD-relevant state as readable text.
#
#   powershell -ExecutionPolicy Bypass -File capture-state.ps1 -Label before
#   powershell -ExecutionPolicy Bypass -File capture-state.ps1 -Label after -OutDir D:\
#
# IT RUNS IN THE GUEST, NOT ON THE HOST.  Written 30 Aug 2026 for PRE_RELEASE 39,
# whose one requirement was a real interactive uninstall - which cycle.ps1 can
# never do, because unins000.exe is generated at INSTALL time and cycle.ps1
# uninstalls /VERYSILENT, short-circuiting before both of the uninstaller's
# prompts.  So the measurement has to happen on a VirtualBox guest, and the
# results have to come back to the host as TEXT rather than as screenshots.
#
# THE ROUTE IS A SHARED FOLDER AND guestcontrol IS FORBIDDEN (PROJECT_STATUS 7
# step 2 - it needs guest credentials).  The rig is two transient shares, and
# the writable one mounts as Y: by default:
#
#   VBoxManage sharedfolder add <vm> --name sdout --hostpath C:/Users/dmont/sdout --automount --readonly
#   VBoxManage sharedfolder add <vm> --name xfer  --hostpath C:/Users/dmont/sdxfer --automount
#
# Use --transient on a VM that is already RUNNING - a running VM is locked and a
# permanent add fails with "already locked for a session".  On a POWERED-OFF VM
# add them permanently instead, so they survive the power cycles an overnight
# install needs.
#
# RUN IT ELEVATED.  Get-LocalGroupMember and the data-tree paths need it, and an
# unelevated run reports "could not read" for most of what matters - which the
# script says out loud rather than reporting as absence.
#
# IT REFUSES THE NULL CASE OUT LOUD, which is the whole reason it exists rather
# than a handful of ad-hoc commands.  Every section distinguishes THREE answers:
# present, genuinely absent, and "this process could not look".  A group that
# does not exist and a group this process may not read are different facts, and
# an empty list is NEVER reported as "nothing there".  PROJECT_STATUS's
# instrument section is what this implements.

param(
    # before / after, or any label; it names the output file.
    [Parameter(Mandatory = $true)] [string] $Label,

    # Where the file goes.  Y:\ is the xfer share in the standard rig; override
    # it when running somewhere that has no share mounted.
    [string] $OutDir = 'Y:\',

    # 02 Sep 26 - PRE_RELEASE_FIXES 134.  Walk both SD trees and list every
    # directory and file, so a before-capture and an after-capture can be
    # DIFFED rather than compared by eye.
    #
    # OFF BY DEFAULT, DELIBERATELY.  It adds thousands of lines - the mirrored
    # directories alone are 3028 files - and every existing use of this script
    # wants the summary, not the inventory.  Pass it for an uninstall-then-
    # reinstall comparison and leave it off otherwise.
    [switch] $Manifest
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path -LiteralPath $OutDir)) {
    Write-Host ("capture-state: " + $OutDir + " is not there.") -ForegroundColor Red
    Write-Host 'If this is the rig, the xfer share is not mounted - try \\vboxsvr\xfer,' -ForegroundColor Yellow
    Write-Host 'which needs no Guest Additions automount, or pass -OutDir.' -ForegroundColor Yellow
    exit 2
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out   = Join-Path $OutDir ("state-" + $Label + "-" + $stamp + ".txt")

function Section($t) {
    Write-Output ''
    Write-Output ('=== ' + $t + ' ' + ('=' * [Math]::Max(0, 60 - $t.Length)))
}

$body = & {
    Write-Output ('capture-state: label   ' + $Label)
    Write-Output ('capture-state: when    ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-Output ('capture-state: host    ' + $env:COMPUTERNAME)
    Write-Output ('capture-state: user    ' + $env:USERNAME)
    Write-Output ('capture-state: writing ' + $out)

    # RULE 1 OF THE INSTRUMENT SECTION: say what this run actually was.  Most of
    # what follows reads differently unelevated, and a reader of the file must be
    # able to tell which kind of run produced it.
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $elevated = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Output ('capture-state: elevated ' + $elevated)

    Section 'local users'
    try {
        $u = @(Get-LocalUser -ErrorAction Stop)
        Write-Output ('count: ' + $u.Count)
        $u | ForEach-Object { Write-Output ('  {0,-24} enabled={1}' -f $_.Name, $_.Enabled) }
    } catch {
        Write-Output ('COULD NOT READ: ' + $_.Exception.Message)
    }

    # THE FOUR SD GROUPS AND Administrators.  sdsshonly is the one whose NAME
    # misleads: it grants no ssh, it carries SeDenyInteractiveLogonRight and
    # SeDenyRemoteInteractiveLogonRight (deny-logon.ps1), so membership means
    # "cannot use the console or Remote Desktop" - PRE_RELEASE 69.
    foreach ($g in 'sdusers', 'sdssh', 'sdapi', 'sdsshonly', 'Administrators') {
        Section ("group " + $g)
        try {
            $m = @(Get-LocalGroupMember -Group $g -ErrorAction Stop)
            Write-Output ('exists, members: ' + $m.Count)
            if ($m.Count -eq 0) { Write-Output '  (group exists and is EMPTY)' }
            $m | ForEach-Object { Write-Output ('  ' + $_.Name) }
        } catch {
            Write-Output ('NOT READABLE OR NOT PRESENT: ' + $_.Exception.Message)
        }
    }

    Section 'sdu_ / sdg_ groups'
    try {
        $sd = @(Get-LocalGroup -ErrorAction Stop | Where-Object { $_.Name -match '^sd[ug]_' })
        Write-Output ('count: ' + $sd.Count)
        $sd | ForEach-Object { Write-Output ('  ' + $_.Name) }
        if ($sd.Count -eq 0) { Write-Output '  (none - this is a real answer, the enumeration succeeded)' }
    } catch {
        Write-Output ('COULD NOT ENUMERATE: ' + $_.Exception.Message)
    }

    # THE SD BLOCK IS THE POINT OF THIS SECTION, not the whole file.  Uninstall
    # removes AllowGroups and ForceCommand together (RemoveAllowGroups), and the
    # ForceCommand half is the sharp one: without it an ssh session lands at a
    # PowerShell prompt instead of in SD.
    Section 'sshd_config'
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (Test-Path -LiteralPath $cfg) {
        $lines = @(Get-Content -LiteralPath $cfg | Where-Object { $_ -match 'AllowGroups|ForceCommand|BEGIN SD|END SD' })
        Write-Output ('present: ' + $cfg)

        # 02 Sep 26 - PRE_RELEASE 133 AND 118 ARE BOTH DECIDED BY THE mtime, AND
        # NEITHER COULD BE READ OUT OF THE LINES ABOVE.  118 says an over-the-top
        # install must NOT touch this file; 133 says the closing box claimed ssh
        # was left alone on a path where the installer had just rewritten it and
        # bounced sshd.  Both entries were measured by hand - "mtime 15:30:04 ->
        # 15:44:32, sshd process created 15:44:34" - and the hand measurement is
        # what this line replaces.  The SIZE goes with it because a rewrite that
        # lands in the same second still changes the length of an AllowGroups
        # line, and the two together are harder to coincide than either alone.
        $ci = Get-Item -LiteralPath $cfg
        Write-Output ('  mtime: ' + $ci.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + '   size: ' + $ci.Length)

        if ($lines.Count -eq 0) {
            Write-Output '  NO AllowGroups / ForceCommand / SD block lines - the SD block is GONE'
        } else {
            $lines | ForEach-Object { Write-Output ('  ' + $_) }
        }
    } else {
        Write-Output ('NOT PRESENT: ' + $cfg)
    }

    # THE OTHER HALF OF 133's SIGNATURE: sshd RESTARTED.  A rewritten config
    # alone does not prove ApplyAllowGroups ran to completion - it restarts the
    # service, and a process created seconds after the mtime is what says so.
    # An ABSENT process is a third answer and is printed as one, because "no
    # sshd" and "sshd that did not restart" are different facts and the closing
    # box's wording is wrong in different ways against each.
    # ***StartTime IS NULL UNELEVATED, IT DOES NOT THROW, AND THE FIRST VERSION
    # OF THIS SECTION DIED ON IT.*** sshd runs as SYSTEM; an unelevated
    # Get-Process still returns the object and still fills in Id, but StartTime
    # comes back $null, so .ToString() threw "you cannot call a method on a
    # null-valued expression" - and because the try wrapped the whole loop, the
    # section printed one generic line and NO process at all.  Two rules broken
    # at once: a reading that was merely unavailable was reported as a failure
    # to enumerate, and one bad process would have hidden every good one.  The
    # try is per-process now and the missing time says which of the two it is.
    Section 'sshd process (PRE_RELEASE 133)'
    $sshd = @(Get-Process -Name sshd -ErrorAction SilentlyContinue)
    Write-Output ('  processes named sshd: ' + $sshd.Count)
    if ($sshd.Count -eq 0) {
        Write-Output '  none running (the enumeration itself succeeded)'
    }
    foreach ($p in $sshd) {
        $started = '(START TIME NOT READABLE - this process is not elevated)'
        try {
            if ($null -ne $p.StartTime) { $started = $p.StartTime.ToString('yyyy-MM-dd HH:mm:ss') }
        } catch {
            $started = '(START TIME REFUSED: ' + $_.Exception.Message + ')'
        }
        Write-Output ('  pid {0}  started {1}' -f $p.Id, $started)
    }

    # 30 Aug 26 - PRE_RELEASE 67 AND 75 ARE MEASURED HERE RATHER THAN READ OUT OF
    # sd.iss.  67 says a full install puts the OpenSSH server on even when the ssh
    # box is left unchecked, because sd.iss:719 gates on SshServerAbsent and never
    # tests the task; 75 says the api box only shuts the firewall and leaves SD
    # listening, because APIPORT stays active in the full sd.conf.  Both were
    # reasoned from the installer source and neither had been observed on a
    # machine.  These three readings are what turn them into observations - so
    # take this capture on an install where BOTH boxes were left unchecked.
    Section 'OpenSSH server (PRE_RELEASE 67)'
    $sshd = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
    if (Test-Path -LiteralPath $sshd) {
        Write-Output ('  PRESENT  ' + $sshd)
        try {
            $svc = Get-Service -Name sshd -ErrorAction Stop
            Write-Output ('  service sshd: status=' + $svc.Status + ' startup=' + $svc.StartType)
        } catch {
            Write-Output ('  service sshd: NOT REGISTERED or not readable: ' + $_.Exception.Message)
        }
    } else {
        Write-Output ('  absent   ' + $sshd)
        Write-Output '  (no OpenSSH server on this machine)'
    }

    # THE ACTIVE-LINE COUNT IS THE READING, not the presence of the word.  The
    # stand-alone conf carries APIPORT commented out, and sdwind.c's
    # open_api_listener() returns -1 for "no listener" when the port is <= 0, so
    # a commented line and a missing line mean the same thing and an ACTIVE one
    # means SD is listening.
    Section 'sd.conf APIPORT (PRE_RELEASE 75)'
    $sdconf = Join-Path $env:ProgramData 'SD\sd.conf'
    if (Test-Path -LiteralPath $sdconf) {
        Write-Output ('present: ' + $sdconf)
        $api = @(Get-Content -LiteralPath $sdconf | Where-Object { $_ -match 'APIPORT' })
        if ($api.Count -eq 0) { Write-Output '  NO APIPORT line at all' }
        $api | ForEach-Object { Write-Output ('  ' + $_) }
        $active = @($api | Where-Object { $_ -match '^\s*APIPORT\s*=' })
        Write-Output ('  ACTIVE APIPORT lines: ' + $active.Count + '   (0 = no listener)')
    } else {
        Write-Output ('NOT PRESENT: ' + $sdconf)
    }

    # 30 Aug 26 - RemoteAddress IS THE READING, AND THE FIRST VERSION OF THIS
    # SECTION DID NOT TAKE IT.  It printed DisplayName, Enabled and Direction,
    # and on the 11:00 capture that showed "OpenSSH SSH Server (sshd)
    # enabled=True dir=Inbound" - which I read as "port 22 is open" and used to
    # claim PRE_RELEASE 67 was worse than filed.  IT PROVES NOTHING OF THE KIND.
    # ssh-firewall.ps1:150 restricts the rule with
    # "Set-NetFirewallRule -RemoteAddress '127.0.0.1' -Enabled True", so a
    # correctly RESTRICTED install looks EXACTLY like an open one on those three
    # fields.  The scope is the whole question and it was the one thing not read.
    #
    # Noise is dropped too: matching on 'SSH' pulled in twelve Network Discovery
    # rules that have nothing to do with either route.
    Section 'firewall rules for the two remote routes'
    try {
        $r = @(Get-NetFirewallRule -ErrorAction Stop |
               Where-Object { $_.Name -match 'OpenSSH|sshd' -or $_.DisplayName -match 'OpenSSH|SD API|4243' })
        Write-Output ('matching rules: ' + $r.Count)
        foreach ($x in $r) {
            $addr = '<unreadable>'
            try { $addr = (($x | Get-NetFirewallAddressFilter -ErrorAction Stop).RemoteAddress -join ',') } catch { }
            Write-Output ('  {0}' -f $x.DisplayName)
            Write-Output ('      name={0} enabled={1} dir={2} profile={3}' -f
                          $x.Name, $x.Enabled, $x.Direction, $x.Profile)
            Write-Output ('      RemoteAddress={0}   <- 127.0.0.1 = restricted, Any = open to the network' -f $addr)
        }
        if ($r.Count -eq 0) { Write-Output '  (none matched - the enumeration succeeded)' }
    } catch {
        Write-Output ('COULD NOT ENUMERATE: ' + $_.Exception.Message)
    }

    Section 'SD trees'
    foreach ($p in 'C:\Program Files\SD', 'C:\ProgramData\SD', 'C:\ProgramData\SD\sdsys', 'C:\ProgramData\SD\user_accounts') {
        if (Test-Path -LiteralPath $p) {
            $n = @(Get-ChildItem -LiteralPath $p -ErrorAction SilentlyContinue).Count
            Write-Output ('  PRESENT  {0}  ({1} entries)' -f $p, $n)
        } else {
            Write-Output ('  absent   ' + $p)
        }
    }

    # 02 Sep 26 - PRE_RELEASE 120 AND 132, WHICH ARE BOTH "A PRESERVED DIRECTORY
    # WENT MISSING ACROSS AN UNINSTALL-THEN-REINSTALL".  The four counted paths
    # above cannot say it: sdsys is PRESENT either way and its entry count moves
    # for a dozen innocent reasons.  The entries name their directories one at a
    # time, so this reports them one at a time.
    #
    # ***THE LIST IS READ FROM stage.py, NOT RETYPED HERE.*** 132's whole finding
    # was a hand-kept list drifting from stage.py's - the PROMISE tracked ten
    # entries while the PROTECTION tracked three - and a third hand-kept copy in
    # the INSTRUMENT would be the same defect in the place it is least visible.
    # There is a built-in fallback for a run that cannot reach stage.py, and it
    # SAYS WHICH ONE IT USED; a fallback that is silently taken is a fourth copy.
    #
    # ***AND "0 entries" IS NOT "empty".*** The 2 Sep witness read entries=0 for
    # $cred and dumps and recorded them as "empty and survived"; both are simply
    # read-denied to a process without the rights, and that reading was withdrawn.
    # So each line distinguishes absent, present-and-counted, and present-but-
    # unreadable, and never collapses the last two.
    Section 'SDSYS_PRESERVE directories (PRE_RELEASE 120, 132)'
    $fallback = @('$cred', 'accounts', 'cat', 'os.users', 'os.users.dic',
                  'batch.jobs', 'batch.jobs.dic', 'prt', '$hold', 'dumps',
                  'bp', 'bp.out')
    $names   = $null
    $source  = ''
    $fromPy  = $false
    $stage   = Join-Path $PSScriptRoot 'stage.py'
    if (Test-Path -LiteralPath $stage) {
        $txt = Get-Content -LiteralPath $stage -Raw
        if ($txt -match '(?s)SDSYS_PRESERVE\s*=\s*\[(.*?)\n\]') {
            $parsed = @([regex]::Matches($Matches[1], "\(\s*'([^']+)'") |
                        ForEach-Object { $_.Groups[1].Value })
            if ($parsed.Count -gt 0) {
                $names  = $parsed
                $source = $stage
                $fromPy = $true
            }
        }
    }
    if ($null -eq $names) {
        $names  = $fallback
        $source = 'BUILT-IN FALLBACK - stage.py was not readable beside this script'
    }
    Write-Output ('  list source: ' + $source)
    Write-Output ('  names      : ' + $names.Count)
    if ($fromPy) {
        # The fallback is allowed to be shorter than stage.py; it is NOT allowed
        # to be shorter silently, because a stale fallback is what gets used on
        # the one run that could not reach the share.
        $only = @($names | Where-Object { $fallback -notcontains $_ })
        if ($only.Count -gt 0) {
            Write-Output ('  NOTE: the built-in fallback is STALE - stage.py also has: ' + ($only -join ', '))
        }
    }
    if ($names.Count -eq 0) {
        Write-Output '  REFUSED: no directory names to check.  This section measured NOTHING.'
    }
    foreach ($d in $names) {
        $p = Join-Path 'C:\ProgramData\SD\sdsys' $d
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Output ('  ABSENT      ' + $p)
            continue
        }
        $err = $null
        $n = @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue -ErrorVariable err).Count
        if ($err) {
            Write-Output ('  UNREADABLE  {0}  ({1})' -f $p, $err[0].Exception.GetType().Name)
        } else {
            Write-Output ('  present     {0}  ({1} entries, read OK)' -f $p, $n)
        }
    }

    # 02 Sep 26 - PRE_RELEASE_FIXES 134.  Owner's invariant: "all the system
    # files and directories that existed when sd was first installed need to
    # exist after it is reinstalled."  Nothing tested it - the section above
    # counts entries in four trees and never walks them, so it can say a tree
    # shrank but never WHICH thing left.
    #
    # ***THE WHOLE VALUE IS IN THE DIFF, SO THE OUTPUT IS SORTED AND RELATIVE.***
    # Absolute paths and directory order would make two captures differ for
    # reasons nobody cares about.
    #
    # ***AND A DIRECTORY THIS PROCESS MAY NOT READ IS NAMED, NEVER OMITTED.***
    # That is the difference between this and the three ad-hoc probes that were
    # written and corrected on 2 Sep 2026, each of which reported a permission
    # denial as an absence.  Here the cost would be worse than a wrong line: a
    # subtree that was readable BEFORE and denied AFTER would appear in the diff
    # as hundreds of deleted files and read as catastrophic data loss.  So the
    # walk's errors are collected and printed, and any capture carrying them is
    # marked NOT COMPARABLE at the top of the section.
    if ($Manifest) {
        Section 'SD tree manifest (PRE_RELEASE 134)'
        Write-Output '  Diff a before-capture against an after-capture.  Every line that'
        Write-Output '  disappears is a file or directory the reinstall did not put back.'

        foreach ($treeRoot in 'C:\Program Files\SD', 'C:\ProgramData\SD') {
            Write-Output ''
            Write-Output ('  --- ' + $treeRoot)
            if (-not (Test-Path -LiteralPath $treeRoot)) {
                Write-Output '      absent (the path is not there at all)'
                continue
            }

            $walkErrs = $null
            $items = @(Get-ChildItem -LiteralPath $treeRoot -Recurse -Force `
                                     -ErrorAction SilentlyContinue -ErrorVariable walkErrs)

            if ($walkErrs -and $walkErrs.Count -gt 0) {
                Write-Output ('      NOT COMPARABLE: ' + $walkErrs.Count +
                              ' path(s) could not be read by this process.')
                Write-Output '      A denial is not an absence.  Re-run ELEVATED before diffing:'
                foreach ($er in ($walkErrs | Select-Object -First 20)) {
                    Write-Output ('        unreadable: ' + $er.TargetObject)
                }
                if ($walkErrs.Count -gt 20) {
                    Write-Output ('        ... and ' + ($walkErrs.Count - 20) + ' more')
                }
            }

            if ($items.Count -eq 0) {
                Write-Output '      REFUSED: the path exists and the walk returned NOTHING.'
                Write-Output '      That is a broken measurement, not an empty tree.'
                continue
            }

            $dirs  = @($items | Where-Object { $_.PSIsContainer }).Count
            Write-Output ('      ' + $items.Count + ' entries (' + $dirs + ' directories, ' +
                          ($items.Count - $dirs) + ' files)')

            $items |
                ForEach-Object {
                    $rel = $_.FullName.Substring($treeRoot.Length)
                    if ($_.PSIsContainer) { 'D ' + $rel } else { 'F ' + $rel }
                } |
                Sort-Object |
                ForEach-Object { Write-Output ('      ' + $_) }
        }
    }

    Section 'installed SD product'
    $found = $false
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        try {
            Get-ItemProperty $k -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'SD' } |
                ForEach-Object {
                    $found = $true
                    Write-Output ('  {0}  ver={1}' -f $_.DisplayName, $_.DisplayVersion)
                    Write-Output ('    uninstaller: ' + $_.UninstallString)
                }
        } catch { }
    }
    if (-not $found) { Write-Output '  no SD product registered (the registry was readable)' }

    # THE UNINSTALLER NAMES THIS PATH BACK TO THE USER, so the after-capture
    # carries the sweep's own report rather than a summary of it.  %TEMP% is the
    # elevated user's, which is where sd.iss:3589 puts it.
    # 02 Sep 26 - sd-remove-database.log JOINS IT, PRE_RELEASE 139.  That entry
    # exists because the database question confirmed nothing and wrote nothing,
    # so after a run in which both questions were answered the machine could not
    # say which button had been pressed - and the session that ran it could not
    # tell whether the click was wrong or the code was.  This is the file that
    # closes that gap, so it is read back the same way as the accounts sweep.
    Section 'sweep log, if the uninstaller has run'
    foreach ($lp in (Join-Path $env:TEMP 'sd-remove-accounts.log'), 'C:\Windows\Temp\sd-remove-accounts.log',
                    (Join-Path $env:TEMP 'sd-remove-database.log'), 'C:\Windows\Temp\sd-remove-database.log') {
        if (Test-Path -LiteralPath $lp) {
            Write-Output ('--- ' + $lp + ' ---')
            Get-Content -LiteralPath $lp | ForEach-Object { Write-Output ('  ' + $_) }
        } else {
            Write-Output ('  absent: ' + $lp)
        }
    }
}

# 30 Aug 26 - -Encoding utf8, AND THAT IS NOT A PREFERENCE.  The first run of
# this script used a bare Tee-Object, which in PowerShell 5.1 writes UTF-16LE:
# both captures came back to the host NUL-separated, and a plain grep matched
# NOTHING in either.  PROJECT_STATUS.md records the identical trap for the
# SD-verify transcripts - "a plain grep -a '[PASS]' matches nothing and reports
# PASS=0 FAIL=0, which reads as a green run and is a dead instrument" - and this
# script walked into it one day after that was read.  Out-File takes an encoding;
# Tee-Object in 5.1 does not, which is why this is two statements and not one.
$body | Out-File -FilePath $out -Encoding utf8
$body

Write-Host ''
Write-Host ("capture-state: written to " + $out) -ForegroundColor Green
