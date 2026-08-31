; ---------------------------------------------------------------------------
; probe-taskflags.iss - THE WIZARD'S TASKS PAGE, MEASURED WITHOUT A PERSON.
;
; Driven by probe-taskflags.ps1.  Do not compile this by hand - the driver
; passes the leg and cleans up after leg 2.
;
; NOT INSTALLED AND NOT SHIPPED.  It must be on assert-current.ps1's
; $neverShipped list or the tree reports STALE merely because this exists.
;
; ***WHY IT EXISTS: "ONLY A PERSON CAN JUDGE THIS" WAS TRUE AND IS NOT ANY
; MORE.***  PRE_RELEASE 67 and 85 were both written round that sentence - ISCC
; checks that tasks COMPILE, not that they BEHAVE, and no cycle or suite run
; ever renders the tasks page - so each cost a build, a hand-off, and the
; owner's eyes, and 85 cost two of them to reach a WRONG conclusion.  This
; drives the checkboxes through Inno's OWN click path,
; TNewCheckListBox.CheckItem, which is the method a mouse click calls,
; inheritance rules and all.  It is not a simulation of the wizard; it is the
; wizard, with the clicking done in Pascal.
;
; WHAT IT CANNOT DO.  It does not judge LAYOUT - wording, order, indentation,
; or whether a caption is truthful.  Those still want eyes.  It judges STATE.
;
; THE TWO LEGS, AND WHY BOTH ARE NEEDED.
;   LEG 1  UsePreviousTasks=no.  The flags alone, on a machine with no history.
;          This is the question 85 THOUGHT it was asking.
;   LEG 2  UsePreviousTasks=yes - which is what sd.iss gets BY DEFAULT, having
;          never set it - with a previous selection pre-written.  This is the
;          question that actually mattered, and it is the one that reproduced
;          the owner's report on 31 Aug 2026.
;
; INSTRUMENT RULES (CLAUDE.md).  It prints the resolved captions and indices it
; actually used, the BEFORE and AFTER state of every transition, and it REFUSES
; THE NULL CASE OUT LOUD: a caption it cannot find, or an empty tasks list,
; marks the run VOID rather than scoring a pass on a list it never touched.
; ---------------------------------------------------------------------------

; LEG 2 IS SELECTED BY THE PRESENCE OF THE SYMBOL, NOT BY ITS VALUE - the
; driver passes /DLEG2 for leg 2 and nothing for leg 1.  `#if LEG == 2` was
; tried first and ISCC refused it: a /D value arrives as a STRING, so comparing
; it to an integer is a type error rather than a false.  Presence has no type.

[Setup]
AppId=SDProbeTaskFlags
; ***THE NAME IS SHOUTING ON PURPOSE.***  It lands in the title bar, and on
; 31 Aug 2026 the owner saw this window, read "SD task-flag probe" as the SD
; installer, and reported the forced ssh box as a defect - twice.  The window
; has to appear for the tasks page to exist at all, so the title is the only
; place that can say what it is.
AppName=ZZ PROBE - NOT the SD installer
AppVersion=0
DefaultDirName={localappdata}\SDProbeTaskFlags
; It cannot install anything: no [Files], no [Run], no app dir, no uninstaller,
; and it aborts at the tasks page before Inno writes a single thing.
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
; So the wizard opens DIRECTLY on the tasks page and needs no click to reach it.
DisableWelcomePage=yes
WizardStyle=modern
OutputBaseFilename=probe-taskflags

#ifdef LEG2
UsePreviousTasks=yes
#else
UsePreviousTasks=no
#endif

[Tasks]
; ***COPIES OF sd.iss's ENTRIES.  THEY ARE A COPY AND THAT IS A REAL COST.***
; If sd.iss's flags change and these do not, this probe measures a pair that no
; longer ships and says PASS.  probe-taskflags.ps1 guards exactly that: it reads
; the four Name:/Flags: lines out of sd.iss and refuses to run if they have
; drifted from these.  Change one, change the other, or the driver stops you.

; --- the ssh pair, sd.iss:187-193 - THE CONTROL -----------------------------
Name: "sshserver"; Description: "Install the OpenSSH server (SD accounts sign in over ssh and nothing else)"; \
    GroupDescription: "ssh:"; Flags: checkablealone; \
    Check: SshServerAbsent

Name: "sshserver\sshremote"; Description: "Let other computers on your network connect to this one over ssh (port 22)"; \
    Flags: unchecked dontinheritcheck; \
    Check: SshServerAbsent

; --- the API pair, sd.iss:425-428 - THE SUBJECT -----------------------------
Name: "apiremote"; Description: "Provide the SD API (port 4243)"; \
    GroupDescription: "SD API:"; Flags: unchecked checkablealone
Name: "apiremote\apinetwork"; Description: "Let other computers on your network reach it"; \
    Flags: unchecked dontinheritcheck

[Code]
var
  Buf: TArrayOfString;
  N: Integer;
  Void: Boolean;

function SshServerAbsent: Boolean;
begin
  { Forced TRUE so the DEPENDENT ssh pair renders rather than the flat
    server-present entries.  Stated in the log - it is an input, not a
    measurement, and sd.iss derives it from the real machine. }
  Result := True;
end;

procedure L(S: String);
begin
  if N >= GetArrayLength(Buf) then
    SetArrayLength(Buf, N + 128);
  Buf[N] := S;
  N := N + 1;
end;

function YN(B: Boolean): String;
begin
  if B then Result := 'CHECKED  ' else Result := 'unchecked';
end;

{ Booleans that are NOT checkbox states get their own spelling, so a return
  code can never be misread as a tick. }
function TF(B: Boolean): String;
begin
  if B then Result := 'True' else Result := 'False';
end;

{ Index of a task by the leading text of its caption.  -1 when absent. }
function Find(Caption: String): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to WizardForm.TasksList.Items.Count - 1 do
    if Pos(Caption, WizardForm.TasksList.ItemCaption[I]) = 1 then
    begin
      Result := I;
      Exit;
    end;
end;

{ One transition: act on Actor, then report BOTH boxes. }
procedure Step(Caption: String; Actor, Parent, Child: Integer; DoCheck: Boolean);
var
  Op: TCheckItemOperation;
  Ok: Boolean;
  Before: String;
begin
  Before := 'before: parent=' + YN(WizardForm.TasksList.Checked[Parent]) +
            ' child=' + YN(WizardForm.TasksList.Checked[Child]);
  if DoCheck then Op := coCheck else Op := coUncheck;
  Ok := WizardForm.TasksList.CheckItem(Actor, Op);
  L('  ' + Caption);
  L('    ' + Before);
  if DoCheck then
    L('    CheckItem(index ' + IntToStr(Actor) + ', coCheck) returned ' + TF(Ok))
  else
    L('    CheckItem(index ' + IntToStr(Actor) + ', coUncheck) returned ' + TF(Ok));
  L('    after : parent=' + YN(WizardForm.TasksList.Checked[Parent]) +
    ' child=' + YN(WizardForm.TasksList.Checked[Child]));
end;

procedure RunPair(Title, ParentCap, ChildCap: String);
var
  P, C: Integer;
begin
  L('');
  L('=== ' + Title + ' ===');
  P := Find(ParentCap);
  C := Find(ChildCap);
  L('  parent caption : "' + ParentCap + '" -> index ' + IntToStr(P));
  L('  child  caption : "' + ChildCap + '" -> index ' + IntToStr(C));
  if (P < 0) or (C < 0) then
  begin
    L('  *** NOT FOUND.  THIS PAIR WAS NEVER MEASURED.  RUN IS VOID. ***');
    Void := True;
    Exit;
  end;
  L('  AS RENDERED    : parent=' + YN(WizardForm.TasksList.Checked[P]) +
    ' child=' + YN(WizardForm.TasksList.Checked[C]) +
    '  (child enabled=' + TF(WizardForm.TasksList.ItemEnabled[C]) + ')');
  L('');
  Step('1. tick PARENT      (child MUST stay unchecked - dontinheritcheck)', P, P, C, True);
  Step('2. tick CHILD       (parent becoming ticked is CORRECT Inno)',       C, P, C, True);
  Step('3. untick CHILD     (parent MUST stay ticked - checkablealone)',     C, P, C, False);
  Step('4. untick PARENT    (child unticking is CORRECT and undisableable)', P, P, C, False);
  Step('5. re-tick PARENT   (child MUST stay unchecked - dontinheritcheck)', P, P, C, True);
end;

procedure CurPageChanged(CurPageID: Integer);
var
  I: Integer;
  LogPath: String;
begin
  if CurPageID <> wpSelectTasks then Exit;

  { Say so ON THE PAGE too.  The title bar was not enough on 31 Aug 2026: the
    window is only up for a moment, and a moment is long enough to be read as
    the SD installer and reported as a defect. }
  WizardForm.PageNameLabel.Caption := 'PROBE - THIS IS NOT THE SD INSTALLER';
  WizardForm.PageDescriptionLabel.Caption :=
    'It installs nothing, and closes itself in a moment.';
  WizardForm.SelectTasksLabel.Caption :=
    'gplbld\probe-taskflags - PRE_RELEASE 85 / 67.  The ssh box below is ' +
    'FORCED to appear so it can be tested; the real installer hides it when ' +
    'the machine already has a server.  Nothing here is installed or removed.';

  { The driver always passes /TASKLOG=.  The fallback exists so a hand-run
    still lands somewhere findable rather than silently nowhere. }
  LogPath := ExpandConstant('{param:TASKLOG|' +
                            ExpandConstant('{localappdata}') +
                            '\probe-taskflags.log}');

  N := 0;
  Void := False;
  L('probe-taskflags - the tasks page, driven through Inno''s own click path');
#ifdef LEG2
  L('LEG             : 2 - a previous selection restored');
  L('UsePreviousTasks: YES - which is what sd.iss gets BY DEFAULT');
#else
  L('LEG             : 1 - the flags alone');
  L('UsePreviousTasks: no  - the flags measured on their own');
#endif
  L('Windows version : ' + GetWindowsVersionString);
  L('Setup filename  : ' + ExpandConstant('{srcexe}'));
  L('Log path        : ' + LogPath);
  L('');
  L('*** THIS IS NOT THE BOX SET THE INSTALLER SHOWS. ***');
  L('    SshServerAbsent is FORCED True here so the DEPENDENT ssh pair renders');
  L('    and can be tested.  sd.iss derives it from the real machine');
  L('    (sd.iss:1105, FileExists({sys}\OpenSSH\sshd.exe)), so on a machine that');
  L('    ALREADY HAS a server the real wizard HIDES "Install the OpenSSH server"');
  L('    and shows the flat sshremoteshut/sshremoteopen entry instead.');
  L('    FOUR boxes below = this probe.  THREE = the real installer, server present.');
  L('    Asked 31 Aug 2026 by the owner, who read the four here as a defect.');
  L('');
  L('THE TASKS LIST AS INNO BUILT IT:');
  for I := 0 to WizardForm.TasksList.Items.Count - 1 do
    L('  [' + IntToStr(I) + '] level=' +
      IntToStr(WizardForm.TasksList.ItemLevel[I]) + ' ' +
      YN(WizardForm.TasksList.Checked[I]) + ' ' +
      WizardForm.TasksList.ItemCaption[I]);

  if WizardForm.TasksList.Items.Count = 0 then
  begin
    L('*** THE TASKS LIST IS EMPTY.  NOTHING WAS MEASURED.  RUN IS VOID. ***');
    Void := True;
  end;

  RunPair('ssh pair - THE CONTROL (sd.iss:187-193)',
          'Install the OpenSSH server',
          'Let other computers on your network connect');

  RunPair('API pair - THE SUBJECT (sd.iss:425-428)',
          'Provide the SD API',
          'Let other computers on your network reach it');

  L('');
  if Void then
    L('VERDICT: VOID - see the NOT FOUND / EMPTY line above.')
  else
    L('VERDICT: both pairs were driven.  Read AS RENDERED, then steps 1 and 5.');

  SetArrayLength(Buf, N);
  SaveStringsToFile(LogPath, Buf, False);

  WizardForm.Close;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  { No "are you sure" - this thing is closing itself. }
  Confirm := False;
end;
