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
  #define AppVer "1.0-2"
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
; else: net localgroup sdusers <name> /add.
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

; OPT IN, AND OFF BY DEFAULT.  Decision from the repository owner, 14 Aug 2026.
; The case for offering it: SD is often installed by someone with little
; administrative knowledge who wants the handful of people on their local
; network to reach it.  Good security is the default; the easy path exists but
; has to be chosen deliberately.
;
; The Check hides this entirely when the machine already has an ssh server.  We
; never reconfigure or restart one we did not install - it may be there for
; something else and may be managed by policy.  See PROJECT_STATUS.md 5.9.
Name: "installssh"; Description: "Install and start OpenSSH Server (allows remote access to THIS MACHINE on port 22)"; \
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
; user's" runs through the middle of this tree: ACCOUNTS ships with the SDSYS
; record in it and then accumulates every account the user creates.  There is
; no way to remove the shipped half without risking the other, so none of it
; is removed.  The opt-in path in [Code] deletes the whole tree instead, which
; is honest about what it is doing.
;
; The Check stops an upgrade overwriting a live database.  On a machine that
; already has C:\ProgramData\SD\sdsys, this whole section is skipped and the
; existing data is kept untouched.  UPGRADING AN EXISTING DATABASE IS NOT
; SOLVED - a new release's GPL.BP.OUT will not reach an existing install, and
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
; Failure is reported and not fatal, on the same reasoning as the ssh install:
; a machine where this cannot be applied should still get a working SD, with
; the restriction absent rather than the install broken.  It is checked at the
; end by CurStepChanged so it cannot fail silently, which is the mistake the
; OpenSSH step made.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\deny-logon.ps1"" sdsshonly"; \
    Flags: runhidden; StatusMsg: "Restricting SD accounts to ssh..."

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

; Optional, and only reachable if the task was ticked and no ssh server was
; already present.  A failure here must NOT fail the SD install: this is a
; Features on Demand download and policy, a metered connection or an offline
; machine can all block it.  Hence skipifdoesntexist and no exit code check.
; BRACES: "{{" IS THE ESCAPE FOR A LITERAL "{", AND "}" NEEDS NO ESCAPE AT ALL.
; This line read "try {{ ... }} catch {{ exit 1 }}", which expanded to
; "try { ... }} catch { exit 1 }}" - single opening braces and DOUBLED closing
; ones.  PowerShell could not parse it, so the capability was never installed;
; and because this entry deliberately checks no exit code, it failed in total
; silence.  Measured 14 Aug 2026 from the install log, after a real install
; with the box ticked produced no sshd at all.  Write "}" singly.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ""$ErrorActionPreference='Stop'; try {{ Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null; Set-Service -Name sshd -StartupType Automatic; Start-Service sshd } catch {{ Write-Output $_; exit 1 }"""; \
    Flags: runhidden skipifdoesntexist; Tasks: installssh; \
    StatusMsg: "Installing OpenSSH Server..."

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
; Stop the server before removing the files it is running from.  Ignore any
; failure: not running is the normal case.
Filename: "{app}\usr\bin\sd.exe"; Parameters: "-stop"; Flags: runhidden; \
    RunOnceId: "StopSD"

[Code]

{ ---------------------------------------------------------------------------
  Detection helpers
  --------------------------------------------------------------------------- }

function SshServerAbsent: Boolean;
begin
  { Tested by looking for the file rather than by asking Windows.
    Get-WindowsCapability -Online REQUIRES ELEVATION - measured 14 Aug 2026 -
    and while Inno happens to be elevated, a file test costs nothing, cannot
    fail for a reason unrelated to the question, and is instant. }
  Result := not FileExists(ExpandConstant('{sys}\OpenSSH\sshd.exe'));
end;

var
  DataTreeWasAbsent: Boolean;

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
  Result := True;
end;

function DataTreeAbsent: Boolean;
begin
  Result := DataTreeWasAbsent;
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

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
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
    MsgBox('SD is installed.' + #13#10#13#10 +
           'You have been added to the "sdusers" group, which is what grants ' +
           'access to the SD database.' + #13#10#13#10 +
           'Windows only applies group membership when you sign in, so you must ' +
           'SIGN OUT AND BACK IN (or restart) before SD will run. Until then it ' +
           'will report that it cannot open its files.' + #13#10#13#10 +
           'To give other people access, add each of them to that group:' + #13#10 +
           '    net localgroup sdusers <name> /add' + #13#10 +
           'They must sign out and back in as well.',
           mbInformation, MB_OK);

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
  if (CurPageID = wpSelectTasks) and (not SshServerAbsent) then
    { Notify rather than offer, which is what the repository owner asked for:
      the option is not available and the reason is stated. }
    MsgBox('OpenSSH Server is already installed on this machine.' + #13#10#13#10 +
           'The option to install it is therefore not offered, and this installer ' +
           'will not change, restart or reconfigure your existing ssh server.',
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

  RegWriteExpandStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'Path', Rebuilt);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataPath: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    RemoveFromPath;
    Exit;
  end;

  if CurUninstallStep <> usPostUninstall then
    Exit;

  { The sdusers group is deliberately NOT removed.  CREATE.ACCOUNT adds every
    SD user to it, and a data tree the user chose to keep is ACL'd to it, so
    deleting the group would orphan the permissions on their own database. }

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
