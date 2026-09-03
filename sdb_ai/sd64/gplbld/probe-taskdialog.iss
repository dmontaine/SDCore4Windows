; probe-taskdialog.iss - how TaskDialogMsgBox actually behaves, measured.
;
; NOT PART OF THE PRODUCT AND NOT ON ANY SHIP LIST.  It is on assert-current's
; $neverShipped.  Build it with an OUTPUT DIRECTORY OUTSIDE THE REPOSITORY -
; nothing binary is tracked here, and there is no OutputDir in [Setup] below so
; that forgetting /O is a visible choice rather than a silent commit:
;
;     "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /OC:\Users\dmont\sdout ^
;         gplbld\probe-taskdialog.iss
;
; then run the resulting sigprobe.exe (installs one file under the user's own
; profile, no elevation), and uninstall it.  The dialog appears during the
; UNINSTALL, which is the context sd.iss uses it in.
;
; ===========================================================================
; WHY IT IS KEPT
; ===========================================================================
;
; PRE_RELEASE_FIXES 139.  sd.iss's KeepOrDelete decides whether the uninstaller
; destroys every SD account and password, and it rests on six properties of
; TaskDialogMsgBox that Inno's help does not make readable from here - the help
; is a compressed .chm that cannot be searched from the build tree.
;
; ***THREE OF THE SIX ARE INVISIBLE TO A COMPILER.***  Two calls compiled clean
; and failed at run time on 2 Sep 2026, and one measurement could only come from
; a person looking at the screen.  So this file is the record of how the API
; behaves, and it is re-runnable when Inno changes.
;
; ===========================================================================
; WHAT WAS MEASURED, 2 Sep 2026
; ===========================================================================
;
;   MB_YESNO or MB_DEFBUTTON2  COMPILES, then fails at RUN time: "Internal
;                              error: TaskDialogMsgBox: Invalid Buttons".  The
;                              MB_DEFBUTTON flags are not accepted, so the
;                              default button cannot be chosen through them.
;   bare MB_YESNO              accepted.  Renders as stacked COMMAND LINKS
;                              carrying the labels, not as push buttons.
;   Labels[0] / Labels[1]      IDYES / IDNO.
;   focus                      follows Labels[0].  Owner, at the dialog with
;                              Keep first: "keep was the default".
;   Escape, and the X          THERE IS NO X AND ESCAPE DOES NOTHING.  The
;                              dialog cannot be dismissed without choosing,
;                              so no third outcome has to be handled.
;   in an UNINSTALLER          WORKS, and the mapping is the same as in Setup.
;                              Measured here: clicked Delete, KeepOrDelete
;                              returned True.  Inno's uninstaller is a separate
;                              executable, so this did not follow from the
;                              Setup measurement and was not assumed.
;
; ***THE CONSEQUENCE, WHICH IS THE POINT OF ALL OF IT:*** focus follows
; Labels[0], so the SAFE answer must be first - which makes Keep IDYES and
; Delete IDNO, the INVERSE of the Yes/No test sd.iss used before 139.
;
; NO LINE MAY BEGIN WITH '#' unless it is a real ISPP directive.  A Pascal
; character constant wrapped onto its own line is read as a directive; this file
; hit that twice while it was being written.  Constants go at the END of a line.

[Setup]
AppName=SD KeepOrDelete probe
AppVersion=1
DefaultDirName={localappdata}\sigprobe
OutputBaseFilename=sigprobe
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
Uninstallable=yes

[Files]
; Something has to be installed for there to be an uninstall.  This file will
; do, and it means the installed copy carries its own explanation.
Source: "probe-taskdialog.iss"; DestDir: "{app}"; Flags: ignoreversion

[Code]
{ COPIED FROM sd.iss VERBATIM, deliberately.  A probe that tests a paraphrase
  of the shipping code proves nothing about the shipping code.  If sd.iss's
  KeepOrDelete changes, change this with it or the measurement above stops
  being about anything. }
function KeepOrDelete(const Instruction, Text: String): Boolean;
var
  Labels: TArrayOfString;
begin
  SetArrayLength(Labels, 2);
  Labels[0] := 'Keep';
  Labels[1] := 'Delete';
  Result := TaskDialogMsgBox(Instruction, Text, mbConfirmation, MB_YESNO, Labels, 0) = IDNO;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Chose: Boolean;
begin
  if CurUninstallStep <> usUninstall then
    Exit;

  try
    Chose := KeepOrDelete(
               'PROBE - this is sd.iss''s dialog, running in an UNINSTALLER',
               'Nothing is deleted whatever you answer. Click either link.' + #13#10#13#10 +
               'Keep is Labels[0] and returns IDYES; Delete is Labels[1] and ' +
               'returns IDNO. KeepOrDelete returns True only for Delete.');
  except
    MsgBox('TaskDialogMsgBox FAILED in the uninstaller:' + #13#10#13#10 + GetExceptionMessage + #13#10#13#10 +
           'This is the answer that matters - sd.iss cannot use it at ' +
           'CurUninstallStepChanged and needs a different shape. Report this text.',
           mbCriticalError, MB_OK);
    Exit;
  end;

  { BOTH ARMS NAME THE WRONG ANSWER TOO.  A probe that only describes the
    expected outcome cannot tell a reader that the mapping inverted. }
  if Chose then
    MsgBox('KeepOrDelete returned TRUE.' + #13#10#13#10 +
           'You clicked Delete, and sd.iss would have deleted the database here.' + #13#10#13#10 +
           'If you clicked KEEP and see this, the mapping is INVERTED in the ' +
           'uninstaller and must not ship.',
           mbInformation, MB_OK)
  else
    MsgBox('KeepOrDelete returned FALSE.' + #13#10#13#10 +
           'You clicked Keep, and sd.iss would have kept the database here.' + #13#10#13#10 +
           'If you clicked DELETE and see this, the mapping is INVERTED in the ' +
           'uninstaller and must not ship.',
           mbInformation, MB_OK);
end;
