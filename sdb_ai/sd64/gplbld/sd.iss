; sd.iss - Inno Setup script for SD on Windows
;
; Build:
;   cd sdb_ai/sd64
;   make sd
;   python3 gplbld/stage.py --stage ../../stage --force --bootstrap
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DStage=..\..\stage gplbld\sd.iss
;
; This packages the tree gplbld/stage.py produces.  It does not build anything
; and it must not: the staged tree is already compiled AND already bootstrapped,
; which is what lets an install be a file copy needing neither Python nor a
; compiler on the target.  See PROJECT_STATUS.md 5.16.
;
; THE LAYOUT IS LOAD-BEARING, NOT TIDINESS.  Binaries go in
; C:\Program Files\SD\usr\bin, two components down, because shipping
; msys-2.0.dll beside sd.exe relocates the entire POSIX namespace: the runtime
; derives its root by stripping TWO components from the directory holding the
; DLL.  usr\bin puts the root on C:\Program Files\SD\.  One level up and the
; root becomes C:\Program Files\, which would mean creating C:\Program Files\dev.
; etc\fstab then maps /dev/shm back out to C:\ProgramData\SD\shm, because
; shm_open() creates files there and Program Files is read-only to ordinary
; users.  Both are measured, not guessed - the trap is in PROJECT_STATUS.md 6.
;
; Do not "simplify" this by putting the executables directly in the app folder.

#ifndef Stage
  #define Stage "..\..\stage"
#endif
#ifndef AppVer
  #define AppVer "W1.0-0"
#endif

#define AppName    "SD"
#define AppPublisher "String Database"
#define DataDir    "{commonappdata}\SD"

[Setup]
AppId={{9F2B7C41-3D6A-4E58-9B0F-5C7A1E2D8B34}
AppName={#AppName}
AppVersion={#AppVer}
AppVerName={#AppName} {#AppVer}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\SD
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputBaseFilename=sd-setup-{#AppVer}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

; Creating C:\Program Files\SD and writing the ACLs on C:\ProgramData\SD both
; need an elevated token, and so does installing OpenSSH Server.  Inno asks for
; it through UAC, which is why the installer can do things a normal SD session
; cannot - creating Windows accounts among them.
PrivilegesRequired=admin

; Inno warns that {username} is a per-user value being used in an
; administrative install, and it is right to.  We mean it, and the limit is
; understood: {username} is whoever authenticated the UAC prompt.  When an
; administrator installs SD for themselves - the common case, and the one the
; opt-in ssh checkbox is aimed at - that is the right person.  When a STANDARD
; user runs setup and an administrator types credentials, it is the
; administrator who joins sdusers and the standard user who does not, and they
; will find SD cannot open its files.  There is no reliable way to ask Inno who
; is at the keyboard, so the final message tells the user how to add anyone
; else - with CREATE.ACCOUNT, which is the only answer it gives.  It used to
; offer "net localgroup sdusers <name> /add" as a fallback for somebody who
; already has a Windows account; that was dropped on 15 Aug 2026 because it does
; not work.  See the comment on the MsgBox itself.
UsedUserAreasWarning=no

; The server is PE32+ and the MSYS2 runtime is 64 bit.  There is no 32 bit build.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; The PATH entry below is a machine environment change; without this the
; setting does not reach already-running processes.
ChangesEnvironment=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "addtopath"; Description: "Add SD to the system PATH so ""sd"" runs from any directory"; \
    GroupDescription: "System integration:"

; THE ssh SERVER IS NO LONGER A TASK.  Owner's decision, 16 Aug 2026, reversing
; the opt-in of 14 Aug 2026.
;
; WHY IT REVERSED.  SD accounts sign in over ssh and nothing else (5.6.2) and
; the API is carried over ssh as well (8, posture B, which already said in as
; many words that this makes the ssh install path load-bearing).  So an install
; without an ssh server is one that nobody but the installing user can use: every
; account CREATE.ACCOUNT makes is denied the console and Remote Desktop, and
; without ssh it has no way in at all.  That is true even with no network -
; a local user reaches SD by ssh'ing to localhost, which is the case that
; decided it.
;
; It is installed whenever this machine does not already have one.  If it does,
; SD leaves it completely alone: "we never reconfigure or restart an ssh server
; we did not install" (5.9) is a SEPARATE rule from whether ours is optional,
; and it survives this change untouched.  SshServerAbsent is what enforces it.
;
; WHAT IS OPTIONAL NOW IS THE EXPOSURE, WHICH IS WHERE THE RISK ACTUALLY WAS.
; Installing the capability creates OpenSSH-Server-In-TCP and enables it for any
; remote address - measured on this machine, 16 Aug 2026 - so an unconditional
; install would open port 22 to the whole local network EVERY time, including
; for the local-only user whose case made ssh mandatory in the first place.
; ssh-firewall.ps1 scopes the rule to loopback unless this is ticked, which
; leaves the risk attached to the decision that carries it.
Name: "sshremote"; Description: "Let other computers on your network connect to this one over ssh (port 22)"; \
    GroupDescription: "Remote access:"; Flags: unchecked; Check: SshServerAbsent

; THE SECOND LAYER OF 5.6.2.  PROMOTED FROM A SUBTASK on 16 Aug 2026, because
; the parent it hung off no longer exists.
;
; ITS OWN Check IS NOW DOING ALL THE WORK.  As a child it was unreachable unless
; SD was installing the ssh server itself, and that was described as structural
; rather than remembered; with the parent gone, the Check on this line is the
; only thing left standing between it and a machine whose ssh server belongs to
; somebody else.  Do not remove it.  allow-ssh-groups.ps1 refuses without
; -Installed as a second, independent backstop.
;
; The deny rights say where an account may NOT log in.  This says who may ssh at
; all: two independent controls rather than one.  Still off by default, because
; it writes to a file outside SD's own tree.
;
; THE LIST INCLUDES ADMINISTRATORS.  Without that the machine's own
; administrator loses ssh the moment this is applied - the caution in 5.6.2, and
; the reason this is offered rather than done silently.  allow-ssh-groups.ps1
; resolves the name from S-1-5-32-544 rather than writing "Administrators",
; which would be wrong on a localised Windows.
;
; THE DESCRIPTION NAMES scp AND sftp because the ForceCommand half of that
; script stops them working for everyone, which follows from the decision and is
; not a side effect that was missed - but it is not something to discover after
; ticking a box that only mentioned AllowGroups, which is what it used to say.
Name: "limitssh"; Description: "Limit ssh to SD users and administrators, and put every ssh session straight into SD (disables scp and sftp)"; \
    GroupDescription: "Remote access:"; Flags: unchecked; Check: SshServerAbsent

[Files]
; --- C:\Program Files\SD\ --------------------------------------------------
; Everything here is program.  It is replaced on upgrade and removed on
; uninstall, which is what should happen to program files.
Source: "{#Stage}\ProgramFiles\*"; DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

; --- C:\ProgramData\SD\ ----------------------------------------------------
; THE DATA TREE IS INSTALLED ONCE AND NEVER TOUCHED AGAIN.
;
; uninsneveruninstall, because this is the user's database.  Uninstalling SD
; must not remove accounts, passwords or data - the repository owner's
; instruction, 14 Aug 2026 - and the boundary between "shipped" and "the
; user's" runs through the middle of this tree: accounts ships with the SDSYS
; record in it and then accumulates every account the user creates.  There is
; no way to remove the shipped half without risking the other, so none of it
; is removed.  The opt-in path in [Code] deletes the whole tree instead, which
; is honest about what it is doing.
;
; The Check stops an upgrade overwriting a live database.  On a machine that
; already has C:\ProgramData\SD\sdsys, this whole section is skipped and the
; existing data is kept untouched.  UPGRADING AN EXISTING DATABASE IS NOT
; SOLVED - a new release's gpl.bp.out will not reach an existing install, and
; that needs a migration story before there is ever a second release.  Said
; plainly here rather than discovered later.
Source: "{#Stage}\ProgramData\sdsys\*"; DestDir: "{#DataDir}\sdsys"; \
    Flags: recursesubdirs createallsubdirs uninsneveruninstall; Check: DataTreeAbsent

; sd.conf is separate from the tree above because it needs BOTH flags:
; onlyifdoesntexist so a reinstall does not discard settings the user edited,
; and uninsneveruninstall so uninstalling does not delete their configuration.
; Without the second one Inno removes it like any other installed file, because
; unlike the database it genuinely is one.
Source: "{#Stage}\ProgramData\sd.conf"; DestDir: "{#DataDir}"; \
    Flags: onlyifdoesntexist uninsneveruninstall

[Dirs]
; Created empty and left alone.  shm is where etc\fstab maps /dev/shm, so every
; SD user needs to be able to write in it; the ACLs below grant that.
Name: "{#DataDir}\user_accounts"; Flags: uninsneveruninstall
Name: "{#DataDir}\group_accounts"; Flags: uninsneveruninstall
Name: "{#DataDir}\shm"; Flags: uninsneveruninstall

[Icons]
Name: "{group}\SD"; Filename: "{app}\usr\bin\sd.exe"; WorkingDir: "{#DataDir}"

[Run]
; ORDER MATTERS.  The group has to exist before icacls can grant to it, and the
; ACLs have to be right before anyone is invited in.

; sdusers is the group SD's own account provisioning uses - CREATE.ACCOUNT adds
; each new Windows user to it (PROJECT_STATUS.md 5.6).  Creating it here means
; a fresh machine can create accounts without a manual step.  Failure is not
; fatal: it already existing is the common case on a reinstall.
;
; NOTE IT IS NOT THE ADMINISTRATOR GROUP, and never was.  This grants access to
; the FILES; who administers SD is Windows Administrators (5.6.1).  The two are
; separate questions and it is worth not confusing them: an administrator who
; has not elevated does not carry Administrators in their token either, so they
; need sdusers to reach the data tree just as an ordinary user does.
Filename: "{sys}\net.exe"; Parameters: "localgroup sdusers /add /comment:""SD users"""; \
    Flags: runhidden skipifdoesntexist; StatusMsg: "Creating the sdusers group..."

; AND PUT THE INSTALLING USER IN IT.  Without this, the icacls below locks the
; person who just installed SD out of their own database: the ACL grants
; SYSTEM, Administrators and sdusers, and an ordinary session carries a
; UAC-filtered token whose Administrators membership is "deny only" - so it
; matches none of the three.  SD would install perfectly and then fail to open
; anything, which is about the worst first impression available.
;
; This does NOT take effect in the session that runs the installer.  Windows
; fixes group membership in the access token at logon, so it stays invisible
; until the user signs out and back in.  That is the trap in
; PROJECT_STATUS.md 6, and it is why the wizard says so at the end.
Filename: "{sys}\net.exe"; Parameters: "localgroup sdusers ""{username}"" /add"; \
    Flags: runhidden skipifdoesntexist; StatusMsg: "Adding {username} to sdusers..."

; sdsshonly is the group that confines an account to ssh (PROJECT_STATUS.md
; 5.6.2).  CREATE.ACCOUNT puts every NON-administrator account it creates into
; it; the deny rights below are what the membership actually means.
;
; IT IS DELIBERATELY NOT sdusers.  That grants access to the data files and
; administrators are in it too, so denying console logon there would lock the
; machine's administrators out of their own console.
Filename: "{sys}\net.exe"; Parameters: "localgroup sdsshonly /add /comment:""SD accounts restricted to ssh"""; \
    Flags: runhidden skipifdoesntexist; StatusMsg: "Creating the sdsshonly group..."

; AND THIS IS WHAT MAKES THAT GROUP MEAN ANYTHING.  Applied ONCE, here, rather
; than per account: Windows has no cmdlet for user rights assignment, so doing
; it per account would need an LsaAddAccountRights P/Invoke or a secedit
; rewrite on every account creation.
;
; TWO RIGHTS, AND DELIBERATELY NOT A THIRD.  SeDenyInteractiveLogonRight blocks
; the console and SeDenyRemoteInteractiveLogonRight blocks Remote Desktop.
; SeDenyNetworkLogonRight IS NOT SET AND MUST NOT BE: Win32-OpenSSH
; authenticates with a network logon - cleartext network for passwords, S4U for
; keys - so denying it would remove the one route this is meant to preserve.
;
; LsaAddAccountRights rather than secedit, because secedit is a read-modify-
; write of the ENTIRE USER_RIGHTS area: it would rewrite unrelated machine
; policy and race anything else editing it.  This adds one right to one SID.
; Both calls are idempotent - adding a right an account already holds succeeds.
;
; Failure is not fatal, on the same reasoning as the ssh install: a machine
; where this cannot be applied should still get a working SD, with the
; restriction absent rather than the install broken.
;
; CORRECTED 16 Aug 2026, AND IT IS STILL A LOOSE END.  This comment used to
; claim the step "is checked at the end by CurStepChanged so it cannot fail
; silently, which is the mistake the OpenSSH step made".  IT IS NOT CHECKED -
; CurStepChanged never read it, and the mistake it names as somebody else's was
; being made here too.  Corrected in place rather than deleted, per the standing
; rule about wrong comments.
;
; NOT FIXED IN THE SAME PASS, deliberately, because it is not the ssh work and
; the fix is not a comment: unlike the OpenSSH step there is no machine state
; Inno can read to tell whether the rights were applied - user rights
; assignment needs LsaEnumerateAccountRights, so judging it means shelling out
; to a script the way ApplyAllowGroups does.  Recorded in PROJECT_STATUS.md 7
; step 3 rather than left here.
;
; What it costs while it stays unchecked: an account confined to sdsshonly on a
; machine where the deny rights never landed is NOT confined at all, and the
; install says nothing.  That is a quiet weakening, not a broken install, which
; is why it can wait - but it is exactly the shape of the six defects of
; 16 Aug 2026, each of which sat at a seam between two halves that were correct
; alone.
; CLOSED 17 Aug 2026: THE STEP MOVED TO THE CODE SECTION, as ApplyDenyLogon,
; called at ssPostInstall.  The loose end the comment above records was that a
; Run entry discards the exit code, so the one thing this step could not do was
; report having failed - and a group that is not actually denied the console is
; a quiet weakening nobody would notice.  The reasoning is on that function.

; THIS IS THE STEP THAT MAKES THE DATA PRIVATE.  Nothing SD does at runtime
; substitutes for it.  C:\ProgramData grants BUILTIN\Users:(I)(OI)(CI)(RX) by
; inheritance, so without this the whole database is world readable and
; snooping needs no privilege at all.
;
; /inheritance:r FIRST and in the same command - /grant alone leaves the
; inherited Users:(RX) in place and the tree stays readable.
;
; SIDs, not names: *S-1-5-18 is SYSTEM and *S-1-5-32-544 is
; BUILTIN\Administrators, and both are renamed on a localised Windows.
; sdusers is our own name, so it is safe to write out.
;
; Everything created underneath inherits this afterwards, including files SD
; writes through the MSYS2 runtime - NTFS applies inheritance in the kernel, so
; it works even though the mount is noacl and chmod is a no-op.  That is what
; makes one icacls enough.  See PROJECT_STATUS.md 5.7.
Filename: "{sys}\icacls.exe"; \
    Parameters: """{#DataDir}"" /inheritance:r /grant ""*S-1-5-18:(OI)(CI)F"" /grant ""*S-1-5-32-544:(OI)(CI)F"" /grant ""sdusers:(OI)(CI)M"""; \
    Flags: runhidden; StatusMsg: "Securing the data directory..."

; AND THEN TAKE MOST OF THAT BACK ON ONE FILE.  The grant above is what every
; SD user needs to use the database; inherited onto the audit trail it would
; also let them read, rewrite and delete the record of what they did.  This
; step breaks inheritance on that one file and leaves sdusers with AppendData
; and nothing else - measured 16 Aug 2026: appending works, reading,
; truncating, overwriting, renaming and deleting are all refused.
;
; IT MUST COME AFTER THE icacls ABOVE.  Run it before and inheritance puts the
; directory's Modify straight back on the file.
;
; A SHIPPED SCRIPT RATHER THAN AN INLINE COMMAND, for the reason the OpenSSH
; entry below gives at length: an inline parameter is where a brace bug hid for
; its whole life, and a file can be parse-checked on its own.
;
; No exit code check here, deliberately.  secure-audit.ps1 never truncates an
; existing trail and SD falls back to creating the file itself if this step did
; not run - the trail is then inherited-Modify rather than append-only, which
; is the pre-16-Aug behaviour and not a broken install.  PROJECT_STATUS.md 7
; step 4 names this as the thing to check if a trail turns out to be editable.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\secure-audit.ps1"" -Path ""{#DataDir}\sdsys\audit"""; \
    Flags: runhidden; StatusMsg: "Making the audit trail append-only..."

; THE CREDENTIAL STORE IS NOT LOCKED HERE.  It is locked from the Code section,
; by SecureCredStore, called at ssPostInstall.  MOVED OUT OF THIS SECTION
; 17 Aug 2026 because a Run entry discards the exit code, and this is the one
; step whose silent failure is a privilege escalation rather than a degraded
; install.  The reasoning, and what the entry here got wrong for its whole
; life, are on that function.

; THE ELEVATION HELPER'S LOG, and it must exist before the helper ever runs.
; sd-elevate.ps1 logs only if this file is already there, precisely so that a
; missing one means "no logging" rather than "a log created with the data
; tree's Modify for every SD user" - see the note at the top of that script.
;
; SAME ORDERING RULE AS THE AUDIT TRAIL ABOVE: after the icacls, never before.
;
; NOT IN sdsys, and not in the user's AppData either.  sdsys is the database;
; the operational logs an administrator goes looking for - sdsvc.log,
; adopt-account.log - live here.  AppData was considered and rejected on
; 16 Aug 2026: the user owns their own profile, so the person the log is about
; could reset its ACL and rewrite it.  secure-log.ps1's header has the full
; reasoning.
;
; No exit code check, as above.  If this step does not run, sd-elevate.ps1
; finds no file and logs nothing, which is exactly the pre-16-Aug behaviour.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\secure-log.ps1"" -Path ""{#DataDir}\sd-elevate.log"""; \
    Flags: runhidden; StatusMsg: "Securing the elevation log..."

; WHERE !ps_script PUTS A SCRIPT THAT MAY CARRY A PASSWORD.  It used to write
; them into the account directory, which the grant above leaves writable by
; every SD user - so one user could read another's new Windows password, and,
; worse, rewrite a pending script before the elevated helper ran it.  This
; creates SDSYS\pstmp with a per-creator ACL; secure-psdir.ps1 has the detail.
;
; ORDER: after the icacls, as above, AND BEFORE adopt-account.ps1, which runs
; at ssPostInstall and is the install's own first caller of !ps_script.  [Run]
; finishes before ssPostInstall, so being in this section is enough.
;
; NOT A [Dirs] ENTRY, deliberately.  Creating anything under {#DataDir}\sdsys
; before [Files] runs risks the installer's own "a database is already here"
; test seeing a directory it did not put there - PROJECT_STATUS.md section 6.
; The script creates it, which keeps that test looking at an untouched tree.
;
; !ps_script FAILS CLOSED if this directory is absent, so a failure here stops
; account creation rather than quietly writing privileged scripts somewhere
; every SD user can edit them.  That is the intended trade.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\secure-psdir.ps1"" -Path ""{#DataDir}\sdsys\pstmp"""; \
    Flags: runhidden; StatusMsg: "Securing the script directory..."

; NOT OPTIONAL SINCE 16 Aug 2026 - see the note in [Tasks].  The Check is the
; whole of the condition now: install one if this machine has none, and never
; touch one it already has.
;
; A FAILURE HERE STILL MUST NOT FAIL THE SD INSTALL.  This is a Features on
; Demand download, and policy, a WSUS with no FoD source, a metered connection
; or an offline machine can each block it.  That rule (5.9) has survived the
; change - but its CONSEQUENCE has not, and this is the important part: the
; machine can now land in the state the user used to choose, an SD with no ssh
; server, in which NO ACCOUNT BUT THE INSTALLING USER'S CAN SIGN IN ANYWHERE.
; It is not fatal and it is not silent either; SshReport says so at the end.
;
; MOVED OUT OF THIS FILE ON PURPOSE - see install-ssh.ps1.  It used to be an
; inline -Command, and it carried a brace bug for its entire life: Inno escapes
; a literal "{" as "{{" but needs no escape for "}", so "}}" reached PowerShell
; as two closing braces and the whole script was a syntax error before it ran.
; Ticking the box installed nothing and, because this entry deliberately checks
; no exit code, said nothing either.  A shipped file can be read and
; parse-checked on its own; an inline parameter cannot.
;
; IT STAYS A [Run] ENTRY RATHER THAN MOVING TO [Code] WITH THE OTHERS, and the
; reason is the StatusMsg.  This step hands off to TiWorker and can work for
; minutes with nothing on screen; it was reported as a hang during testing on
; 14 Aug 2026, when it was optional and rare.  It is now on every install of a
; machine without ssh, so the one line saying what it is doing matters more than
; the exit code does - and the exit code is not what is judged anyway.
;
; CORRECTED 16 Aug 2026.  This comment used to end "Exit 2 means installed,
; restart required, which CurStepChanged reports."  IT DID NOT.  Nothing read
; this entry's exit code at all - a [Run] entry discards it - and CurStepChanged
; handled only ApplyAllowGroups and AdoptAccount.  The claim is left visible
; rather than deleted because it is the second comment in this file found
; asserting a check that was never written.  What replaces it is better than the
; exit code would have been: SshReport reads the MACHINE STATE afterwards, which
; also answers correctly when the capability was already installed.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\install-ssh.ps1"""; \
    Flags: runhidden skipifdoesntexist; Check: SshServerAbsent; \
    StatusMsg: "Installing OpenSSH Server (this can take several minutes)..."

; THE SERVICE, AND IT IS NOT A TASK - owner's decision, 15 Aug 2026.  SD must
; be running when the installer finishes and after every Windows startup, so
; this is not offered, it is done.  Until now there was no service at all and
; "sd -start" had to be typed after every restart.
;
; BEFORE the account step in [Code], which is why it is here rather than at
; ssPostInstall: adopt-account.ps1 starts SD itself if it has to, and having
; the service already running means it does not have to - one less thing to
; race, and that race cost an install earlier the same day.
;
; No Tasks: condition and no Check:.  A shipped .ps1 rather than inline sc.exe
; for the reason above the ssh entry - sc.exe binPath quoting inside an Inno
; parameter is exactly the sort of thing that silently produces a broken
; service, and a shipped file can be read and parse-checked on its own.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\install-service.ps1"" -Install -AppDir ""{app}"""; \
    Flags: runhidden skipifdoesntexist; \
    StatusMsg: "Creating and starting the SD service..."

; THERE IS DELIBERATELY NO "SET THE SDSYS PASSWORD" STEP.
;
; Removed 14 Aug 2026 with the decision that a Windows administrator IS an SD
; administrator (PROJECT_STATUS.md 5.6.1).  Whoever runs this installer is an
; administrator - Inno requires it - so they already administer SD when it
; finishes, and there is nothing they must set to get in.  Accounts still carry
; passwords; what changed is that the SDSYS password is no longer what confers
; administration, so demanding one at install time asks for a credential that
; secures nothing the installer has not already granted.
;
; It was also broken two ways over, which is how the decision came up.  Measured
; on a real interactive install, 14 Aug 2026:
;
;   1. sd -internal needs a running server and the installer never runs
;      sd -start, so it failed with "SD has not been started".
;   2. Inno logs the entry as "Run as: Original user", so it ran with the
;      UNELEVATED token - which does not carry sdusers until the user signs out
;      and back in, so it could not have opened the database either.
;
; And "nowait" meant the console vanished before either message could be read,
; so it looked to the user as though nothing had happened at all.  If a password
; step is ever wanted back, all three have to be fixed together.

[UninstallRun]
; THE SERVICE GOES FIRST, and the order is load-bearing.  Removing it stops it,
; which stops SD; doing it the other way round lets the service notice the
; daemon has gone and, with the restart action configured, start it again from
; files that are being deleted underneath it.
;
; It is also why this is not left to "sd -stop" alone below - that would end
; the daemon while leaving a service pointing at an executable about to vanish,
; which is how a machine ends up with a permanently failing service after an
; uninstall.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\install-service.ps1"" -Remove"; \
    Flags: runhidden skipifdoesntexist; RunOnceId: "RemoveSDService"

; Stop the server before removing the files it is running from.  Ignore any
; failure: not running is the normal case, and after the service has gone it
; is the usual one.
Filename: "{app}\usr\bin\sd.exe"; Parameters: "-stop"; Flags: runhidden; \
    RunOnceId: "StopSD"

[Code]

{ ---------------------------------------------------------------------------
  Detection helpers
  --------------------------------------------------------------------------- }

var
  DataTreeWasAbsent: Boolean;
  SshWasAbsent: Boolean;

function InitializeSetup: Boolean;
begin
  (* ASKED ONCE, BEFORE ANY FILE IS COPIED, AND THE ANSWER CACHED.

     A Check function is evaluated PER FILE.  When this tested DirExists
     directly, the first file of the sdsys set created the directory, every
     later evaluation therefore answered False, and the remaining ~3,260 files
     were silently skipped - producing an install whose database contained 16
     files and no catalogue at all.  Setup still exited 0.

     It survived the first round of testing because the upgrade case skips the
     whole set consistently and so looks identical either way.  Only a genuine
     first install exposes it.  Measured 14 Aug 2026. *)
  DataTreeWasAbsent := not DirExists(ExpandConstant('{#DataDir}\sdsys'));

  (* AND THE SAME TREATMENT FOR ssh AS OF 16 Aug 2026, FOR A REASON THAT ONLY
     ARRIVED WITH THE MANDATORY INSTALL.

     Tested by looking for the file rather than by asking Windows.
     Get-WindowsCapability -Online REQUIRES ELEVATION - measured 14 Aug 2026 -
     and while Inno happens to be elevated, a file test costs nothing, cannot
     fail for a reason unrelated to the question, and is instant.

     WHY IT IS NOW CACHED.  While ssh was a task, the live test was safe: it
     was read before anything was installed, and the only consumer downstream
     asked WizardIsTaskSelected, which cannot be true on a machine that already
     had a server.  Now the installer installs one itself, so from ssPostInstall
     onwards the live answer is False on EVERY machine and "did we put this
     here?" becomes unanswerable - taking the firewall step and the whole ssh
     report with it, since both must do nothing to a server SD did not install.
     The question is about the machine as we found it, so it is asked once,
     here, exactly as the data tree above is. *)
  SshWasAbsent := not FileExists(ExpandConstant('{sys}\OpenSSH\sshd.exe'));
  Result := True;
end;

function DataTreeAbsent: Boolean;
begin
  Result := DataTreeWasAbsent;
end;

function SshServerAbsent: Boolean;
begin
  Result := SshWasAbsent;
end;

{ Registered by the OpenSSH capability, not by us.  Its absence just after an
  install is what "a restart is outstanding" looks like from here - measured
  14 Aug 2026, when Add-WindowsCapability completed and the service did not
  exist until after a reboot.  Read from the registry rather than by shelling
  out to sc.exe: it is the same fact, and it costs nothing. }
function SshServiceRegistered: Boolean;
begin
  Result := RegKeyExists(HKEY_LOCAL_MACHINE, 'SYSTEM\CurrentControlSet\Services\sshd');
end;

{ ---------------------------------------------------------------------------
  The page that says what this will do, before anything has been chosen
  --------------------------------------------------------------------------- }

var
  SummaryPage: TOutputMsgMemoWizardPage;

(* AFTER wpWelcome AND BEFORE THE TASKS PAGE, AND THAT ORDER IS THE POINT.

   Inno already provides the last-chance page: Ready to Install lists the
   destination and the ticked tasks with Cancel beside them.  What it cannot
   show is everything this installer does that is NOT a task - two local groups,
   a group membership, two user-rights denials, an ACL rewrite that strips
   inherited access from the data tree, a Windows service, and the OpenSSH
   install.  A summary at the end would come after the reader had already
   decided; the ssh exposure checkbox in particular is a decision they were
   being asked to take with no context at all.

   IT ALSO CARRIES THE THINGS THAT USED TO BE SAID ONLY AT THE END, where they
   were too late to act on: that Windows will not apply the sdusers membership
   until the user signs out, and that the OpenSSH install can take minutes and
   usually wants a restart before any account can sign in.  The closing dialog
   still says both - somebody who has just clicked through six pages should not
   have to remember - but saying it first is the difference between a stated
   cost and a surprise.

   A MEMO PAGE RATHER THAN InfoBeforeFile, which would mean shipping an .rtf and
   teaching stage.py to stage it.  This needs no new file and cannot get out of
   step with the script that does the work.

   Do not start a line here with a "#" - ISPP reads it as a preprocessor
   directive and a wrapped string constant becomes "Unknown preprocessor
   directive".  The trap is recorded at the closing MsgBox; every #13#10 below
   is mid-line for that reason. *)
procedure InitializeWizard;
var
  M: String;
begin
  (* NOT WRAPPED BY HAND, AND THAT IS THE POINT.  CORRECTED 16 Aug 2026 on the
     owner seeing it: the first version broke every line at about 50 characters
     because the memo width was a guess the compiler cannot check, and the guess
     was far too narrow - a thin column of text in a wide control, with most of
     the page unused.

     The control word-wraps.  So each paragraph below is ONE line and the memo
     fills whatever width it actually has, at any DPI and any wizard style -
     which is a property rather than another guess.  The source lines are broken
     with "+" for readability; those breaks put nothing in the string.

     THE INDENTS WENT WITH IT, and had to.  A two-space indent only survives on
     the first line of a wrapped paragraph, so indented text under a heading
     comes out with one line in and the rest flush left, which looks worse than
     no indent at all.  Structure is carried by blank lines and capitalised
     headings instead.

     So: do not reintroduce a line break inside a paragraph here, and do not
     indent one.  Both look fine in the source and wrong on screen. *)
  M := 'WHERE THINGS GO' + #13#10#13#10 +
       'Program files:  C:\Program Files\SD  - you can change this.' + #13#10 +
       'Database:  C:\ProgramData\SD  - fixed, it cannot be moved.' + #13#10#13#10 +

       'WINDOWS GROUPS, AND ONE THING YOU MUST DO AFTERWARDS' + #13#10#13#10 +
       'Creates the group "sdusers" and adds you to it. That membership is what ' +
       'grants access to the database. Windows only applies a new group when you ' +
       'sign in, so YOU MUST SIGN OUT AND BACK IN, or restart, before SD will ' +
       'run. Until then it reports that it cannot open its files.' + #13#10#13#10 +
       'Creates the group "sdsshonly" and denies its members the right to sign in ' +
       'at the console or over Remote Desktop. Accounts SD creates go in it. Your ' +
       'own account does not.' + #13#10#13#10 +

       'PERMISSIONS ON THE DATABASE' + #13#10#13#10 +
       'Removes inherited permissions from C:\ProgramData\SD and grants access to ' +
       'SYSTEM, administrators and sdusers only. Without this the database would ' +
       'be readable by anyone with an account on this machine.' + #13#10#13#10 +

       'SERVICE AND PATH' + #13#10#13#10 +
       'Installs a Windows service that runs SD and starts it again after every ' +
       'restart. There is nothing to start by hand.' + #13#10#13#10 +
       'Adds SD to the system PATH, unless you clear that option.' + #13#10#13#10 +

       'OPENSSH SERVER - INSTALLED, NOT OPTIONAL' + #13#10#13#10 +
       'Accounts SD creates sign in over ssh and nothing else. That is true even ' +
       'with no network: on a machine used by one person, you reach SD by ' +
       'connecting with ssh to "localhost". So SD installs an OpenSSH server if ' +
       'this machine has none.' + #13#10#13#10 +
       'It is downloaded from Windows Update and CAN TAKE SEVERAL MINUTES with ' +
       'nothing on screen. Do not stop it part way.' + #13#10#13#10 +
       'IT USUALLY NEEDS A RESTART. Until you restart, no SD account except your ' +
       'own can sign in at all.' + #13#10#13#10 +
       'By default it can be reached only from this machine. The options page can ' +
       'open it to other computers on your network.' + #13#10#13#10 +
       'IF THIS MACHINE ALREADY HAS AN SSH SERVER, SD LEAVES IT ALONE. It ' +
       'installs nothing, restarts nothing, and changes neither its configuration ' +
       'nor its firewall rule.' + #13#10#13#10 +

       'WHAT UNINSTALLING DOES NOT REMOVE' + #13#10#13#10 +
       'Your database, the ssh server, and the sdusers group. Removing the ' +
       'database is offered separately and defaults to keeping it.' + #13#10#13#10 +

       'ONE LIMIT WORTH KNOWING BEFORE YOU RELY ON IT' + #13#10#13#10 +
       'SD users are not isolated from each other. Every SD process opens the ' +
       'database as the person running it, so anyone who can use SD on this ' +
       'machine can read another account''s files outside SD. Do not use SD ' +
       'accounts as a privacy boundary between people who should not see each ' +
       'other''s data.';

  SummaryPage := CreateOutputMsgMemoPage(wpWelcome,
      'Before you install',
      'What SD changes on this computer',
      'Setup changes Windows itself, not only its own folders. All of it is listed below. ' +
      'Nothing has happened yet - Cancel stops without changing anything.',
      M);
end;

{ ---------------------------------------------------------------------------
  Install
  --------------------------------------------------------------------------- }

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Exe: String;
  Code: Integer;
begin
  Result := '';
  NeedsRestart := False;

  { An upgrade replaces sd.exe and the MSYS2 DLLs.  A running server holds them
    open, and a half-replaced runtime is a worse outcome than a failed install. }
  Exe := ExpandConstant('{app}\usr\bin\sd.exe');
  if FileExists(Exe) then
    Exec(Exe, '-stop', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

{ Deny the sdsshonly group the console and Remote Desktop, and return what to
  tell the user if it did not happen.  PROJECT_STATUS.md 5.6.2, 7 step 3.

  MOVED OUT OF [Run] 17 Aug 2026, WHICH IS THE WHOLE OF THIS CHANGE.  The
  script was always correct - it checks every NTSTATUS and throws, so its exit
  code means something - but a [Run] entry discards the exit code, so the one
  thing this step could not do was report having failed.  sd.iss carried a
  comment claiming CurStepChanged checked it; that claim was corrected in place
  on 16 Aug 2026 and the check itself is what this supplies.

  WHAT IT COSTS WHEN IT FAILS, and why it is worth a paragraph in the closing
  box: an account in sdsshonly on a machine where the deny rights never landed
  is NOT confined to ssh at all.  It can sign in at the console like anyone
  else.  That is a quiet weakening rather than a broken install - which is
  precisely why nobody would notice it, and why it must say so out loud.

  NOT FATAL, on the same reasoning as the OpenSSH step: a machine where user
  rights cannot be set should still get a working SD with the restriction
  absent, rather than a failed install.

  THE READ-BACK LIVES IN verify-sshonly.ps1, NOT HERE.  Confirming the rights
  are present afterwards needs LsaEnumerateAccountRights, and that script
  already dumps and checks them - so repeating it here would be a second
  implementation of the same assertion, to be kept in step with the first. }
function ApplyDenyLogon: String;
var
  Code: Integer;
  Ps, Script: String;
begin
  Result := '';
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\deny-logon.ps1');

  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  Script + '" sdsshonly',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;

  if Code = 0 then
    Exit;

  Result := 'SD accounts were NOT confined to ssh (code ' + IntToStr(Code) + '). ' +
            'They can sign in at the console and over Remote Desktop like any other ' +
            'Windows account. SD itself is installed and working. To apply it, from an ' +
            'ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" sdsshonly' + #13#10#13#10;
end;

{ Applies the AllowGroups block and returns what to tell the user, or '' if the
  task was not selected.  PROJECT_STATUS.md 5.6.2.

  RUN FROM [Code] AND NOT AS A [Run] ENTRY, because the exit code is the whole
  point.  allow-ssh-groups.ps1 has THREE outcomes, not two, and the middle one
  is the likely one on a fresh machine: 2 means "refused, and here is why" -
  usually that OpenSSH needs a restart before sshd has ever run, so there is no
  sshd_config to edit yet.  A [Run] entry would discard that and the user would
  tick a box and silently get nothing, which is exactly the failure the OpenSSH
  step made for its whole life.

  It runs even in a silent install; only the reporting is skipped. }
function ApplyAllowGroups: String;
var
  Code: Integer;
  Ps: String;
begin
  Result := '';
  { RENAMED 16 Aug 2026 with the task itself.  It was 'installssh\allowgroups'
    while it was a subtask; the parent is gone and a stale name here would read
    as "the user did not tick it" for ever, silently. }
  if not WizardIsTaskSelected('limitssh') then
    Exit;

  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  ExpandConstant('{app}\allow-ssh-groups.ps1') + '" -Installed' +
                  ' -SdExe "' + ExpandConstant('{app}\usr\bin\sd.exe') + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Result := 'ssh could NOT be limited to SD users and administrators: the script did not run.';
    Exit;
  end;

  if Code = 0 then
    Result := 'ssh is now limited to members of "sdusers" and the administrators group. ' +
              'The original sshd_config was kept as sshd_config.before-sd.'
  else if Code = 2 then
    { The common case on a machine that has just been told to restart: sshd
      writes its config on first start, so there is nothing to edit yet. }
    Result := 'ssh was NOT limited, and nothing was changed. The most likely reason is ' +
              'that OpenSSH has not started yet and has no configuration file - restart, ' +
              'then run this from an elevated prompt:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}\allow-ssh-groups.ps1') + '" -Installed' + #13#10#13#10 +
              'It also refuses if sshd_config already says who may connect, in which case ' +
              'that setting is somebody else''s and has been left alone.'
  else
    Result := 'Limiting ssh FAILED and sshd_config was left as it was. Run this from an ' +
              'elevated prompt to see why:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}\allow-ssh-groups.ps1') + '" -Installed';
end;

{ Scope the OpenSSH firewall rule to match the checkbox, and return what to tell
  the user.  PROJECT_STATUS.md 5.9.

  ONLY IF SD INSTALLED THE SERVER.  The rule belongs to the ssh server, and "we
  do not touch an ssh server we did not install" covers its firewall rule as
  squarely as it covers sshd_config - restricting the rule of a server that
  predates SD would break somebody's remote access just as thoroughly as
  editing their config would.  SshWasAbsent, not SshServerAbsent evaluated now,
  which by this point answers False on every machine.

  RUN FROM [Code] LIKE ApplyAllowGroups AND FOR THE SAME REASON: the exit code
  distinguishes three outcomes and the middle one is likely on a fresh machine.
  It is also fast, so it needs no StatusMsg - which is what kept the OpenSSH
  install itself in [Run]. }
function ApplySshFirewall: String;
var
  Code: Integer;
  Ps, Args: String;
  Wanted: Boolean;
begin
  Result := '';
  if not SshWasAbsent then
    Exit;

  Wanted := WizardIsTaskSelected('sshremote');
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Args := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
          ExpandConstant('{app}\ssh-firewall.ps1') + '" -Installed';
  if Wanted then
    Args := Args + ' -Open'
  else
    Args := Args + ' -Restrict';

  if not Exec(Ps, Args, '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Result := 'Who may reach ssh could NOT be set: the script did not run. ' +
              'Windows left port 22 open to your local network, which is its own default.' + #13#10#13#10;
    Exit;
  end;

  if Code = 0 then
  begin
    if Wanted then
      Result := 'Other computers on your network CAN now connect to this one over ssh, ' +
                'because you asked for that.' + #13#10#13#10
    else
      Result := 'ssh can be reached FROM THIS COMPUTER ONLY. Nothing on your network can ' +
                'connect to it. To change that later, run this from an elevated prompt:' + #13#10#13#10 +
                '    powershell -File "' + ExpandConstant('{app}') + '\ssh-firewall.ps1" -Installed -Open' + #13#10#13#10;
  end
  else if Code = 2 then
    { The likely case when a restart is outstanding: the capability has not
      finished registering its firewall rule, so there is nothing to scope. }
    Result := 'Who may reach ssh has NOT been set yet, because Windows has not finished ' +
              'registering the ssh firewall rule. Restart, then run this from an elevated prompt:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}') + '\ssh-firewall.ps1" -Installed -Restrict' + #13#10#13#10
  else
    Result := 'Setting who may reach ssh FAILED, and Windows'' own default is in force - ' +
              'port 22 open to your local network. Run this from an elevated prompt to see why:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}') + '\ssh-firewall.ps1" -Installed -Restrict' + #13#10#13#10;
end;

{ What happened to the ssh server, judged from the state of the machine rather
  than from an exit code.

  FROM STATE, DELIBERATELY.  install-ssh.ps1 is a [Run] entry and a [Run] entry
  discards its exit code - a comment in this file claimed otherwise for months.
  Reading the machine is better than fixing that would have been: it answers the
  same way whether the capability was installed just now, was already there, or
  failed, and it cannot drift from what the user will actually experience.

  THE FAILURE BRANCH IS THE ONE THAT MATTERS.  While ssh was optional, no ssh
  meant the user had declined it.  It is now the state a blocked Features on
  Demand download leaves behind, and in it every account CREATE.ACCOUNT makes is
  denied the console and Remote Desktop with no ssh to fall back on - so it must
  be said in as many words rather than left to be discovered one account later. }
function SshReport: String;
begin
  if not SshWasAbsent then
  begin
    Result := 'This machine already had an OpenSSH server. SD did not install, restart or ' +
              'reconfigure one, and left both its configuration and its firewall rule exactly ' +
              'as they were. SD accounts sign in over ssh, so check that yours will accept ' +
              'them.' + #13#10#13#10;
    Exit;
  end;

  if not FileExists(ExpandConstant('{sys}\OpenSSH\sshd.exe')) then
  begin
    Result := 'OPENSSH SERVER COULD NOT BE INSTALLED, and SD needs it. Windows downloads it ' +
              'on demand, so this is usually a policy that blocks optional features, a metered ' +
              'connection, or no connection at all.' + #13#10#13#10 +
              'SD itself is installed and works for you. But accounts created with ' +
              'CREATE.ACCOUNT sign in over ssh and nothing else, so until there is an ssh ' +
              'server NOBODY BUT YOU CAN USE THIS SD. Put it right from an elevated ' +
              'PowerShell prompt:' + #13#10#13#10 +
              '    powershell -File "' + ExpandConstant('{app}') + '\install-ssh.ps1"' + #13#10#13#10;
    Exit;
  end;

  if not SshServiceRegistered then
  begin
    Result := 'OpenSSH Server was installed and NEEDS A RESTART before it will run. This is ' +
              'normal and is Windows'' doing, not SD''s - SD itself needs no restart.' + #13#10#13#10 +
              'Until you restart, the ssh service does not exist, so no SD account except ' +
              'your own can sign in.' + #13#10#13#10;
    Exit;
  end;

  Result := 'OpenSSH Server was installed and is running.' + #13#10#13#10;
end;

{ GIVE THE INSTALLING USER AN SD ACCOUNT.  Without this SD installs perfectly
  and then refuses the person who installed it: every SD account brings its own
  Windows account and theirs existed first, so "sd" answers "Account DON not in
  register" (PROJECT_STATUS.md 7 step 1f).

  FROM [Code] AT ssPostInstall, NOT FROM [Run], AND THAT IS THE WHOLE TRICK.
  The step needs an elevated token - it reaches SDSYS through sd -internal -
  and this runs with Setup's own.  The SDSYS password step that used to live at
  the bottom of this file was a "postinstall" checkbox, which Inno runs as the
  ORIGINAL user, and that is one of the three reasons it never worked.  The
  script handles the other two, starting a server and keeping its output.

  Returns the script's exit code, or -1 if it could not be run at all. }
function AdoptAccount: Integer;
var
  Code: Integer;
  Ps: String;
begin
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  { -AppDir IS PASSED, NOT LEFT TO THE SCRIPT.  Its default used to be
    $PSScriptRoot, which comes out EMPTY in a param default when the script is
    an advanced one with a mandatory parameter - so the step failed on a real
    install with nothing readable.  Setup knows where it put the files; say so.
    Do not start a line in this file with a square bracket, even in a comment:
    ISCC scans for section tags first and answers "Invalid section tag". }
  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  ExpandConstant('{app}\adopt-account.ps1') + '" -User "' +
                  ExpandConstant('{username}') + '" -AppDir "' +
                  ExpandConstant('{app}') + '" -DataDir "' +
                  ExpandConstant('{#DataDir}') + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
  begin
    Result := -1;
    Exit;
  end;
  Result := Code;
end;

{ LOCK THE SHELL PERMISSION LIST, and return what to tell the user if it did
  not happen.  PROJECT_STATUS.md 7 step 7.

  WHAT IT PROTECTS.  SDSYS os.users names the accounts allowed SH, one record
  per account.  CPROC reads it from the USER'S OWN process when they type SH,
  so ordinary users must be able to READ it - which is the difference from the
  credential store, where they get nothing at all.  What they must never have
  is WRITE: a user who can add their own name grants themselves a shell.

  SO THE ACL IS THE ENTIRE CONTROL, exactly as it is for $CRED, and it fails
  the same way if this step does not run - silently, with the list writable by
  the people it exists to restrain.  That is why this is here and not in [Run]:
  the exit code is checked.

  TWO OBJECTS, TWO CALLS.  The dictionary is locked as well.  It enforces
  nothing - CPROC reads the flags positionally, rec<1> and rec<2> - but an
  administrator reads the list THROUGH that dictionary, and a user able to
  redefine SH to point at another field could make LIST OS.USERS show
  something other than the truth.  Called once per path rather than passing
  both, because -File binds a comma-joined argument in ways that are worth not
  depending on.

  IT MUST RUN AFTER THE DATA-TREE icacls, like the credential store, and
  ssPostInstall is after the whole [Run] section. }
{ Locking one object, so SecureOsUsers can call it twice.  A separate function
  because Inno's Pascal Script has NO NESTED FUNCTIONS - declaring one inside
  another is "'BEGIN' expected" at the inner declaration, which does not name
  the cause. }
function LockOsUsersPath(Ps, Script, Target: String; var Code: Integer): Boolean;
begin
  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  Script + '" -Path "' + Target + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;
  Result := (Code = 0);
end;

function SecureOsUsers: String;
var
  Code: Integer;
  Ps, Script, Store, Dict, Failed: String;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-osusers.ps1');
  Store := ExpandConstant('{#DataDir}\sdsys\os.users');
  Dict := ExpandConstant('{#DataDir}\sdsys\os.users.dic');

  Failed := '';
  if not LockOsUsersPath(Ps, Script, Store, Code) then
    Failed := Store
  else if not LockOsUsersPath(Ps, Script, Dict, Code) then
    Failed := Dict;

  if Failed = '' then
    Exit;

  { NAMED, NOT BURIED, for the same reason the credential store is: a list that
    anyone can edit is not a permission list, and nothing else in the install
    would reveal it. }
  Result := 'The shell permission list was NOT locked (code ' + IntToStr(Code) + '). ' +
            'Until it is, any SD user can add themselves to it and obtain a command shell. ' +
            'Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Store + '"' + #13#10 +
            '    powershell -File "' + Script + '" -Path "' + Dict + '"' + #13#10#13#10;
end;

{ LOCK THE ACCOUNT DIRECTORIES.  PROJECT_STATUS.md section 8, "the B work".

  THE HOLE: the data tree grants sdusers Modify with (OI)(CI), so every account
  directory inherits it and any SD user can read and rewrite any other
  account's files outside SD.  Measured on the 16:54:55 install: from an
  ordinary session, listing another account's directory returned 6 entries and
  writing into it was allowed.

  SD ALREADY REFUSES THAT SESSION, so this aligns the file layer with the rule
  CPROC has enforced since 14 Aug 2026 rather than inventing a new one - LOGTO
  into that account answered "User not allowed in requested account" in the
  same measurement.

  TWO SCRIPTS, AND THE ORDER MATTERS.  secure-accounts.ps1 does the CONTAINER:
  it takes sdusers' inheritable Modify off user_accounts and leaves CREATOR
  OWNER inheritable, which is what lets CREATE.ACCOUNT populate a directory it
  has just made.  secure-account-dirs.ps1 then stamps each EXISTING account
  with its own sdu_<name>.  Container first: the second is pointless while the
  first is still handing out Modify to everybody.

  AFTER AdoptAccount, deliberately.  Adopt is what creates the installing
  user's own account, and running after it means that account is stamped by
  this step on the very install that creates it, rather than waiting for the
  next one.

  NEW accounts are stamped by CREATE.ACCOUNT itself (CREATEA's
  secure.account.dir), so this step is for the ones already on disk - which is
  why it runs unconditionally on every install rather than only on a fresh
  one. }
function SecureAccountDirs: String;
var
  Code: Integer;
  Ps, Container, PerAccount, Root: String;
  ContainerOk, PerAccountOk: Boolean;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Container := ExpandConstant('{app}\secure-accounts.ps1');
  PerAccount := ExpandConstant('{app}\secure-account-dirs.ps1');
  Root := ExpandConstant('{#DataDir}\user_accounts');

  ContainerOk := Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                      Container + '" -Path "' + Root + '"',
                      '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);

  PerAccountOk := False;
  if ContainerOk then
    PerAccountOk := Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                         PerAccount + '" -Root "' + Root + '"',
                         '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);

  if ContainerOk and PerAccountOk then
    Exit;

  { NAMED, NOT BURIED, like the credential store and the shell list: an ACL
    that is the whole of a control fails silently, and nothing else in the
    install would reveal it. }
  Result := 'The account directories were NOT locked (code ' + IntToStr(Code) + '). ' +
            'Until they are, any SD user can read and rewrite any other account''s ' +
            'files outside SD. Put it right from an ELEVATED PowerShell prompt:' +
            #13#10#13#10 +
            '    powershell -File "' + Container + '" -Path "' + Root + '"' + #13#10 +
            '    powershell -File "' + PerAccount + '" -Root "' + Root + '"' + #13#10#13#10;
end;

{ LOCK THE GLOBAL CATALOGUE.  PROJECT_STATUS.md 8, UPSTREAM_FIXES.md 7.

  gcat holds the object code every session executes - $LOGIN among it, which
  CPROC calls for EVERY session - and the data tree grants sdusers Modify, so
  without this any SD user can replace a program that runs in everybody's
  session or delete one and stop the machine signing in.

  IT REUSES LockOsUsersPath, which is generic despite the name: one path, one
  script, one exit code.  A second copy of four lines would only be a second
  place to fix.

  THE BASIC HALF IS NOT ENOUGH ON ITS OWN, which is why this exists as well.
  CATALOG and DELCAT now test K$ADMINISTRATOR, but a gate in a program protects
  that program; the ACL protects the directory from everything, including code
  not yet written.  secure-gcat.ps1's header carries the consequence: global
  cataloguing now needs a genuinely ELEVATED session. }
function SecureGcat: String;
var
  Code: Integer;
  Ps, Script, Target, Objects, Failed: String;
begin
  Result := '';
  Code := 0;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-gcat.ps1');
  Target := ExpandConstant('{#DataDir}\sdsys\gcat');
  Objects := ExpandConstant('{#DataDir}\sdsys\gpl.bp.out');

  { gpl.bp.out BESIDE gcat - owner's instruction, 18 Aug 2026.  It holds the
    compiled objects the global catalogue is loaded FROM, and it measured
    sdusers:(I)(OI)(CI)(M) on the 11:27:32 install after gcat was already
    locked.  On its own it is the weaker path - planting an object there does
    nothing until an administrator re-catalogues it - but that is a delay, not
    a barrier, and nothing writes it after an install except a gpl.bp
    recompile, which is elevated anyway.

    Called once per path, like SecureOsUsers: -File binds a comma-joined
    argument in ways that are worth not depending on. }
  Failed := '';
  if not LockOsUsersPath(Ps, Script, Target, Code) then
    Failed := Target
  else if not LockOsUsersPath(Ps, Script, Objects, Code) then
    Failed := Objects;

  if Failed = '' then
    Exit;

  { NAMED, NOT BURIED, like the credential store and the shell list: this ACL
    is the whole of a control and it fails silently if the step does not run. }
  Result := 'The global catalogue was NOT locked (code ' + IntToStr(Code) + '). ' +
            'Until it is, any SD user can replace the programs SD runs for every session. ' +
            'Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Failed + '"' + #13#10#13#10;
end;

{ LOCK THE CREDENTIAL STORE, and return what to tell the user if it did not
  happen.  PROJECT_STATUS.md 7 step 6.

  WHAT IT PREVENTS IS WRITING, NOT READING.  $CRED holds a per-account salt
  and an Argon2 verifier, never a password.  The data tree grants sdusers
  Modify, and inherited onto the credential store that lets any SD user
  OVERWRITE another account's verifier with one derived from a password they
  chose, then authenticate through the API as that account - a straight
  privilege escalation, where reading an Argon2 verifier is worth little.
  It stays reachable by everything that needs it: API sessions are forked by
  sdwind, which runs as LocalSystem, and SET.PASSWORD is an administration
  verb run from an elevated session.

  IT MUST RUN AFTER THE DATA-TREE icacls, or inheritance puts that Modify
  straight back.  ssPostInstall is after the whole Run section, so that
  ordering is structural here rather than a rule about where to put a line.

  THE PATH IS DOUBLE QUOTED, LIKE EVERY OTHER SCRIPT ARGUMENT IN THIS FILE.
  CORRECTED 17 Aug 2026, and the comment it replaces had been wrong since the
  step was written.  That comment said the path had to be SINGLE quoted
  because "PowerShell EXPANDS $CRED inside a double-quoted string", leaving
  -Path as ...\sdsys\ with the step reporting success.

  THAT IS TRUE OF -Command AND FALSE OF -File, AND THIS IS -File.  Measured
  17 Aug 2026, driving powershell.exe from a batch file so the command line
  reaches it as raw as Inno's does, with a probe script that printed its own
  argument:

    -File    -Path '...\sdsys\$CRED'   ->  ['...\sdsys\$CRED']  151 chars
    -File    -Path "...\sdsys\$CRED"   ->  [...\sdsys\$CRED]    149 chars
    -Command -Path "...\sdsys\$CRED"   ->  [...\sdsys\]         144 chars

  So -File never runs the argument through the expression parser: it neither
  expands $CRED nor strips single quotes, and the shipped single quotes
  arrived as part of the value.  Test-Path then failed and secure-cred.ps1
  exited 2 saying "does not exist - nothing secured" - correctly, on a path
  that really did not exist.  The escape the status file proposed instead,
  a backtick before the $, is wrong for the same reason: -File delivers the
  backtick literally too.

  AND THE EXIT CODE IS CHECKED, which is why this is here and not in Run.
  The step was copied from secure-audit.ps1, including its deliberate absence
  of a check - but that rationale does not carry across.  A missed audit ACL
  leaves an editable trail, which is the pre-16-Aug behaviour; a missed
  credential ACL leaves an escalation open, and it did, silently, for a whole
  session.  A Run entry discards the exit code (this file records the same
  mistake being made about the OpenSSH entry), so checking it means Exec. }
function SecureCredStore: String;
var
  Code: Integer;
  Ps, Script, Store: String;
begin
  Result := '';
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Script := ExpandConstant('{app}\secure-cred.ps1');
  Store := ExpandConstant('{#DataDir}\sdsys\$cred');

  if not Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                  Script + '" -Path "' + Store + '"',
              '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;

  if Code = 0 then
    Exit;

  { NAMED, NOT BURIED.  Anything other than 0 means other SD users can still
    overwrite each other's stored credentials, so the one thing this must not
    do is finish quietly.  The recovery is the same script the installer
    itself ran, so the user gets the same code path rather than a hand-built
    icacls line that could grant something subtly different. }
  Result := 'The credential store was NOT locked (code ' + IntToStr(Code) + ').  Until it is, any SD ' +
            'user can overwrite another account''s stored password and then sign in as them. ' +
            'Put it right from an ELEVATED PowerShell prompt:' + #13#10#13#10 +
            '    powershell -File "' + Script + '" -Path "' + Store + '"' + #13#10#13#10;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  SshLimit: String;
  SshFw: String;
  SshMsg: String;
  AdoptCode: Integer;
  AccountMsg: String;
  CredMsg: String;
  DenyMsg: String;
  OsuMsg: String;
  GcatMsg: String;
  AcctAclMsg: String;
begin
  if CurStep = ssPostInstall then
  begin
    { THE CREDENTIAL STORE GOES FIRST, ahead of even the firewall.  It is the
      only step here that closes a hole rather than configuring something, and
      AdoptAccount below is the install's own first writer into the data tree
      as an elevated process - so locking before it runs means the store is
      never open while an account is being made.  It needs no ordering against
      the Run section beyond being after it, which ssPostInstall guarantees. }
    CredMsg := SecureCredStore;

    { Beside the credential store and for the same reason: both are ACLs that
      are the whole of a control, and both fail silently if the step does not
      run.  Order between them does not matter - different files, no shared
      state - so it goes second simply because the escalation is the graver. }
    OsuMsg := SecureOsUsers;

    { Third of the three ACL steps, and the same reasoning: it closes a hole
      rather than configuring something, and it is silent if it does not run.
      Order between the three does not matter - different paths, no shared
      state. }
    GcatMsg := SecureGcat;

    { AHEAD OF THE ssh STEPS BELOW because it is the one that confines the
      accounts rather than configuring the server, and it needs nothing from
      them - only that the sdsshonly group exists, which [Run] created.  It ran
      from [Run] until 17 Aug 2026, earlier than this, and the move is safe for
      the same reason: the rights are held by the GROUP, so nothing that has
      already happened depends on when they land. }
    DenyMsg := ApplyDenyLogon;

    { Before the silent-install exit below: the work happens either way, and it
      is only the message about it that a silent install skips.  The firewall
      goes first - it decides who can reach the server at all, and the two
      steps are independent, so the more fundamental one is done first. }
    SshFw := ApplySshFirewall;
    SshMsg := SshReport;
    SshLimit := ApplyAllowGroups;

    { Same rule - an unattended install must still end with a usable account. }
    AdoptCode := AdoptAccount;

    { AFTER Adopt, so the account it has just made is stamped on this very
      install rather than on the next one.  See SecureAccountDirs. }
    AcctAclMsg := SecureAccountDirs;
    case AdoptCode of
      0: AccountMsg := 'You also have an SD account of your own, named ' +
                       Uppercase(ExpandConstant('{username}')) + '. Type "sd" to use it; ' +
                       'there is no password to set, because Windows has already ' +
                       'authenticated you.' + #13#10#13#10;
      2: AccountMsg := 'Your SD account, ' + Uppercase(ExpandConstant('{username}')) +
                       ', was already there and has been left alone.' + #13#10#13#10;
    else
      { Named rather than buried: without an account the person who just
        installed SD cannot use it at all, and the recovery is one command.

        THE RECOVERY IS THE SCRIPT, NOT THE VERB.  Owner's instruction,
        15 Aug 2026: ADOPT is not public.  This branch used to print
        "sd -internal CREATE.ACCOUNT USER <name> ADOPT", which is the one
        place in the product that documented it - contradicting the decision
        recorded in PROJECT_STATUS.md 7 step 1f, that K$INTERNAL is not a wall
        but stays undocumented, not in the changelog and not in this dialog.

        adopt-account.ps1 ships beside sd.exe and is what the installer itself
        ran, so naming it gives the user the SAME code path rather than a
        second, hand-driven one - and it keeps the verb out of sight. }
      AccountMsg := 'SD could NOT give you an account automatically (code ' +
                    IntToStr(AdoptCode) + '). Until one exists, "sd" will answer that your ' +
                    'account is not in the register. Put it right from an ELEVATED ' +
                    'PowerShell prompt:' + #13#10#13#10 +
                    '    powershell -File "' + ExpandConstant('{app}') + '\adopt-account.ps1" -User ' +
                    ExpandConstant('{username}') + #13#10#13#10 +
                    'What went wrong is recorded in ' + ExpandConstant('{#DataDir}') +
                    '\adopt-account.log' + #13#10#13#10;
    end;

    { /SUPPRESSMSGBOXES DOES NOT SUPPRESS THESE.  Measured 14 Aug 2026: a
      /VERYSILENT /SUPPRESSMSGBOXES install still stopped and waited for OK on
      both boxes below, so an unattended deployment would hang until somebody
      walked past.  WizardSilent is the test that actually works.  The
      uninstaller's confirmation is guarded separately by UninstallSilent,
      which is a different flag for the same reason. }
    if WizardSilent then
      Exit;

    { Group membership is fixed in the access token at logon, so the sdusers
      membership just granted is not in this user's token yet and the data
      tree will refuse them until they sign out and back in.  Saying so here
      is the difference between "SD is broken" and "sign out and back in".
      PROJECT_STATUS.md 6. }
    { THE VERB IS THE ONLY ANSWER THIS BOX GIVES.  It used to end by offering
      "net localgroup sdusers <name> /add" for somebody who already has a
      Windows account.  REMOVED 15 Aug 2026 (owner's decision) BECAUSE IT DOES
      NOT WORK: sdusers grants access to the data tree, but login needs a
      linked SD account, so a user added that way and nothing else is refused
      with "Account X not in register" - which is the exact symptom don himself
      had before step 1f (PROJECT_STATUS.md 7).  The door for an existing
      Windows account is ADOPT, and that stays undocumented deliberately.
      SD has accounts rather than accounts and users (docs/TCL_VERBS.md), so
      CREATE.ACCOUNT IS the account-creation interface. }
    MsgBox('SD is installed.' + #13#10#13#10 +
           { EMPTY ON EVERY HEALTHY INSTALL, and first when it is not.  This is
             the one line in the box that reports a hole rather than a setting,
             so it is read before the sign-out instruction rather than after
             three paragraphs the reader already skimmed on the first page. }
           CredMsg +
           OsuMsg +
           GcatMsg +
           AcctAclMsg +
           { Beside CredMsg and for the same reason: both are empty on a healthy
             install, and both report a protection that is absent rather than a
             setting that is present. }
           DenyMsg +
           'You have been added to the "sdusers" group, which is what grants ' +
           'access to the SD database.' + #13#10#13#10 +
           'Windows only applies group membership when you sign in, so you must ' +
           'SIGN OUT AND BACK IN (or restart) before SD will run. Until then it ' +
           'will report that it cannot open its files.' + #13#10#13#10 +
           { TRIMMED 16 Aug 2026, owner: "it is even longer".  Fair - the first
             page was added to move things EARLIER and then three paragraphs were
             added here as well, so the box grew rather than shrank.

             THE RULE FOR WHAT STAYS: this box says what the first page could not
             know in advance - what actually happened to ssh, to the firewall and
             to your account - plus the one instruction that is actionable right
             now, which is signing out.  Everything else the first page already
             said, and repeating it here is what made this unreadable.

             Removed: the "SD runs as a service and restarts itself" paragraph;
             the explanation of what LOGTO SDSYS does and why Windows asks for
             consent; the remote-control-tool passage; and the ADMINISTRATOR
             keyword.  The first page carries the service and the ssh-only model;
             the rest is reference material that belongs with the verb, not in a
             box somebody reads once.  The bare COMMANDS stayed, because they are
             the thing a reader comes back for.

             NEVER START A LINE WITH #13#10.  ISPP reads any line whose first
             non-blank character is "#" as a preprocessor directive, so a
             wrapped Pascal string constant becomes "Unknown preprocessor
             directive" and the compile aborts - line number and all, with
             nothing to say it is about string continuation.  Mid-line is fine,
             which is why every #13#10 in this box works.  Cost the eleventh
             session an ISCC run, 16 Aug 2026. }
           { The ssh pair goes here, above the account paragraph, because on a
             machine where the install failed or wants a restart it changes what
             the account advice MEANS - an account nobody can sign in to yet. }
           SshMsg +
           SshFw +
           AccountMsg +
           { CORRECTED 15 Aug 2026, owner, on two counts.

             "with SD started: sd -start" was wrong twice over - SD is started
             by the installer and again at every Windows startup, so there is
             nothing for the user to start, and telling them to do it invites
             them to start a second one.

             "sd -ASDSYS" was wrong because NOBODY LOGS IN TO AN ACCOUNT BUT
             THEIR OWN.  You arrive in your own account and move with LOGTO,
             which is where the grant is checked.  The installer's own account
             step does the same thing. }
           { CORRECTED 16 Aug 2026, owner.  This used to say "From an ELEVATED
             command prompt", which was never the intent and was not what the
             underlying gate required either - that one is rev 0.9.0 and
             predates the port.  Windows does need an elevated token to create
             a user, so SD now obtains one for the session when you enter
             SDSYS, and asks Windows for your consent at that moment.  An
             ordinary command prompt is all that is needed.
             PROJECT_STATUS.md 7 step 4. }
           { THE COMMANDS STAY AND THE PROSE ROUND THEM GOES.  What used to
             follow was four paragraphs explaining LOGTO SDSYS, UAC, remote
             control tools, ssh-only accounts and the ADMINISTRATOR keyword.
             The first page carries the model; a reader who comes back to this
             box comes back for the three lines, not the essay.  The one
             sentence kept is the UAC-over-ssh trap, because its failure mode is
             a frozen screen with no explanation and nothing else warns of it. }
           'TO GIVE SOMEBODY ELSE ACCESS, at the machine itself:' + #13#10#13#10 +
           '    sd' + #13#10 +
           '    LOGTO SDSYS' + #13#10 +
           '    CREATE.ACCOUNT USER <name>' + #13#10#13#10 +
           'Windows asks you to confirm at the LOGTO. Do it AT THE MACHINE - ' +
           'over ssh, and under a remote-control tool not installed as a ' +
           'service, Windows cannot show you that prompt and you get a frozen ' +
           'screen instead.' + #13#10#13#10 +
           'The new account signs in over ssh, on this machine as well:' + #13#10#13#10 +
           '    ssh <name>@localhost',
           mbInformation, MB_OK);

    { Its own box rather than a paragraph in the one above: this one reports
      what happened to a file outside SD's tree, and it can say "nothing was
      changed", which must not be buried under six paragraphs about accounts. }
    if SshLimit <> '' then
      MsgBox(SshLimit, mbInformation, MB_OK);

    if not DataTreeAbsent then
      { Said out loud, because silently keeping the old data would look like
        the upgrade had worked. }
      MsgBox('An existing SD database was found at ' + ExpandConstant('{#DataDir}\sdsys') + '.' + #13#10#13#10 +
             'It has been left exactly as it was, and the newly built system files were NOT installed over it. ' +
             'Your accounts and data are untouched.' + #13#10#13#10 +
             'Upgrading an existing database in place is not yet supported.',
             mbInformation, MB_OK);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  { CurPageChanged STILL FIRES IN SILENT MODE, and this box is the only thing
    in the script that could block one.  MEASURED 18 Aug 2026: a cycle run with
    -Silent stopped here with a modal box on screen and copied not one file
    until somebody clicked OK.  The wizard form is created in silent mode and
    simply not shown, so "the page was never displayed" is not the same as
    "the page never changed".

    THE GUARD IS THE ONE ALREADY USED at CurStepChanged rather than a second
    idiom.  SuppressibleMsgBox was the obvious alternative and is the wrong
    one here: it needs /SUPPRESSMSGBOXES, which the comment there records as
    measured NOT to reach these boxes, and it would leave two ways of saying
    the same thing in one file.

    AND IT FIXES THE TEXT AS WELL AS THE HANG.  The box explains why two
    options are "absent from this page" - which is incoherent read in a mode
    that shows no pages, so there was nothing worth showing here anyway. }
  if WizardSilent then
    Exit;

  if (CurPageID = wpSelectTasks) and (not SshServerAbsent) then
    { Notify rather than offer, which is what the repository owner asked for:
      the option is not available and the reason is stated.

      REWORDED 16 Aug 2026.  It used to say "the option to install it is
      therefore not offered", which stops making sense once installing is not
      an option anybody is offered.  What the reader needs now is the opposite
      reassurance: SD requires an ssh server, this machine has one, and SD is
      going to keep its hands off it - which is also why BOTH ssh options have
      vanished from the page they are looking at. }
    MsgBox('OpenSSH Server is already installed on this machine.' + #13#10#13#10 +
           'SD needs an ssh server and would install one, but it will not touch ' +
           'the one you already have: nothing is installed, nothing is restarted, ' +
           'and neither its configuration nor its firewall rule is changed.' + #13#10#13#10 +
           'That is why the two ssh options are absent from this page. Accounts SD ' +
           'creates sign in over ssh, so make sure your server accepts them.',
           mbInformation, MB_OK);
end;

{ ---------------------------------------------------------------------------
  Uninstall
  --------------------------------------------------------------------------- }

procedure RemoveFromPath;
var
  Path, Dir, Lower, LowerDir, Rebuilt: String;
  P: Integer;
begin
  (* INNO DOES NOT UNDO AN APPENDED PATH.  The [Registry] entry appends to the
     existing value with the olddata constant, and the uninstaller has no way
     to know which part it contributed - so by default it leaves a dead
     directory on the system PATH for ever.  Measured 14 Aug 2026: after a
     clean uninstall the SD directory was still on PATH.  Strip it by name.

     This comment is not brace-delimited on purpose: a brace comment cannot
     mention a brace-delimited Inno constant, because the first closing brace
     ends the comment and everything after it is parsed as code. *)
  if not RegQueryStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'Path', Path) then
    Exit;

  Dir := ExpandConstant('{app}\usr\bin');
  Lower := ';' + Lowercase(Path) + ';';
  LowerDir := ';' + Lowercase(Dir) + ';';
  P := Pos(LowerDir, Lower);
  if P = 0 then
    Exit;

  { Rebuilt from the original text, so surviving entries keep their case. }
  Rebuilt := Copy(Path, 1, P - 1) + Copy(Path, P + Length(Dir) + 1, MaxInt);
  if (Length(Rebuilt) > 0) and (Rebuilt[1] = ';') then
    Delete(Rebuilt, 1, 1);

  (* AND THE SAME AT THE OTHER END, WHICH WAS MISSING AND LEFT AN EMPTY PATH
     ENTRY BEHIND ON EVERY UNINSTALL.  Reported by the owner on 16 Aug 2026,
     who read the system PATH and found 23 empty entries in 30 - the visible
     symptom being a long run of semicolons that makes it look as though SD
     was never added at all.

     The cause is an asymmetry two lines up: the head copy KEEPS the separator
     that preceded our directory, while the tail copy starts AFTER the one that
     followed it.  With an entry in the middle that is exactly right - "a;" and
     "b" rejoin as "a;b".  With our entry LAST, and Inno always appends so it
     always is, the tail is empty and the kept separator dangles.  The next
     install then appends after it, so the run grows by one every cycle.

     A LOOP, NOT A SINGLE STRIP, AND THAT IS THE USEFUL PART: after our entry
     is removed, every empty slot this bug ever left is trailing, so this
     clears the whole accumulated run on the next uninstall rather than only
     the one just created.  It can only ever delete separators, never a real
     entry, which is what makes it safe to apply to a PATH we do not own. *)
  while (Length(Rebuilt) > 0) and (Rebuilt[Length(Rebuilt)] = ';') do
    Delete(Rebuilt, Length(Rebuilt), 1);

  RegWriteExpandStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'Path', Rebuilt);
end;

(* Take SD's AllowGroups block back out of sshd_config.

   BECAUSE IT IS THE ONE THING SD WROTE OUTSIDE ITS OWN TREE.  Everything else
   the uninstaller leaves behind is either the user's data or a group their data
   is ACL'd to; this is a line in somebody else's configuration file, and
   leaving it would keep restricting who may ssh into a machine that no longer
   has SD on it.  The script removes only what is between its own markers and
   is a no-op if the block is not there, so this is safe on a machine where the
   task was never ticked.

   AT usUninstall, NOT usPostUninstall: by the latter the script it runs has
   already been deleted along with the rest of {app}.

   Not brace-delimited, for the reason RemoveFromPath gives above - and this
   comment is how that trap was hit a second time. *)
procedure RemoveAllowGroups;
var
  Ps, Script: String;
  Code: Integer;
begin
  Script := ExpandConstant('{app}\allow-ssh-groups.ps1');
  if not FileExists(Script) then
    Exit;
  Ps := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Exec(Ps, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + Script + '" -Remove',
       '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataPath: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    RemoveAllowGroups;
    RemoveFromPath;
    Exit;
  end;

  if CurUninstallStep <> usPostUninstall then
    Exit;

  { The sdusers group is deliberately NOT removed.  CREATE.ACCOUNT adds every
    SD user to it, and a data tree the user chose to keep is ACL'd to it, so
    deleting the group would orphan the permissions on their own database. }

  { AND THE ssh FIREWALL RULE IS DELIBERATELY NOT PUT BACK, which is worth
    stating because RemoveAllowGroups two procedures up sets the opposite
    precedent - SD reverses what it wrote outside its own tree.

    The asymmetry is deliberate.  Restoring that rule means WIDENING it, and an
    uninstaller must not open a network port on a machine on its way out; a
    server left reachable from itself is the harmless direction to fail in.  SD
    did not create the rule either - the OpenSSH capability did, and the
    capability stays, for the same "it may be in use by something else" reason
    that keeps the server itself installed.

    ssh-firewall.ps1 -Installed -Open is there for somebody who wants it back. }

  DataPath := ExpandConstant('{#DataDir}');
  if not DirExists(DataPath) then
    Exit;

  { A SILENT UNINSTALL MUST NEVER DELETE THE DATABASE.  An unattended removal
    that takes the user's accounts with it is the worst possible default, and
    there is nobody there to answer the question. }
  if UninstallSilent then
    Exit;

  { Defaults to No - MB_DEFBUTTON2 - and names exactly what it destroys and
    where.  "Do you want to remove your settings?" is how people lose data. }
  if MsgBox('Remove the SD database as well?' + #13#10#13#10 +
            DataPath + #13#10#13#10 +
            'This permanently deletes EVERY SD account, every password and all ' +
            'data stored in them, including the SDSYS account and your ' +
            'configuration file.' + #13#10#13#10 +
            'Choose No to keep them, which is the normal choice - reinstalling ' +
            'SD later will find them again.',
            mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
  begin
    if not DelTree(DataPath, True, True, True) then
      MsgBox('Some files under ' + DataPath + ' could not be removed. ' +
             'They may be in use by a running SD process.', mbError, MB_OK);
  end;
end;

function NotOnPath(Dir: String): Boolean;
var
  Path: String;
begin
  Dir := ExpandConstant(Dir);
  if not RegQueryStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'Path', Path) then
  begin
    Result := True;
    Exit;
  end;
  { Semicolons either side so that a directory whose name is a prefix of
    another entry is not mistaken for it. }
  Result := Pos(';' + Lowercase(Dir) + ';', ';' + Lowercase(Path) + ';') = 0;
end;

[Registry]
; The system PATH, so "sd" works from any directory - one of the three things
; the install layout has to deliver (PROJECT_STATUS.md 5.8).  It also means the
; MSYS2 DLLs beside sd.exe are the ones found, which is the answer to Git for
; Windows shipping a rival msys-2.0.dll: Windows searches the executable's own
; directory first, and nothing on PATH can displace it.
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\usr\bin"; \
    Tasks: addtopath; Check: NotOnPath('{app}\usr\bin')
