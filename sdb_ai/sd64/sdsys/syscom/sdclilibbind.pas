{ SdCliLibBind.pas
  SD client API (sdclilib.so) bindings for Lazarus / Free Pascal.
  From the Lazarus definitions of the SD Core owner; 15 Oct 2026: SDGetVar, SDIndices, SDRecordlocked, SDOpenSeq, SDReadSeq, SDReadBlk, SDWriteSeq, SDWriteBlk, SDSeek, SDWeofSeq, SDRevision, SDSystem, SDTrans,
  SDRTrans, SDTxn, SDEvaluate, SDEvalConv, SDIConv, SDOConv, SDIConvs and SDOConvs added (the functions of the QMClient
  API that SD Core for Linux took on), and the load and unload routines written out.  The library's own signatures are in
  gplsrc/sdclilib/sdclilib.h and win over this file.

  Name this file sdclilibbind.pas.  LoadSdCliLib('') looks for sdclilib.so by the system's rules; give the directory
  (the installed one is /usr/local/sdsys/bin) to load that copy.  It returns False, and leaves every pointer nil,
  when the library or any one of its functions is missing.  Every function that returns a PAnsiChar returns memory the
  library allocated: pass it to SDFree when you have copied it.  SDCallx returns nothing; read the arguments back with
  SDGetArg.  SDReadList and SDReadNext take only the list number.  SDOpenSeq gives the file number for the sequential file
  functions and SDClose.  The data of SDReadBlk may hold any byte, including zero, where a PAnsiChar ends: use ActualBytes.
  NOT COMPILED by the project (no Free Pascal here). }

unit SdCliLibBind;

{$mode objfpc}{$H+}

interface

uses
  dynlibs;

const
  // Server status constants (sorted)
  SV_ELSE = 2;
  SV_ERROR = 3;
  SV_LOCKED = 4;
  SV_OK = 0;
  SV_ON_ERROR = 1;
  SV_PROMPT = 5;

// Free Pascal cdecl type definitions (sorted)
type
  TSDCallFn = procedure(SubrName: PAnsiChar; ArgCount: SmallInt); cdecl; varargs;

  TSDCallxFn = procedure(SubrName: PAnsiChar; ArgCount: SmallInt); cdecl; varargs;

  TSDChangeFn = function(Src, OldStr, NewStr: PAnsiChar;
    Occurrences, StartPos: LongInt): PAnsiChar; cdecl;

  TSDClearSelectFn = procedure(ListNo: LongInt); cdecl;

  TSDCloseFn = procedure(FileNo: LongInt); cdecl;

  TSDConnectFn = function(Host: PAnsiChar; Port: LongInt;
    User, Pass, Account: PAnsiChar): LongInt; cdecl;

  TSDConnectedFn = function: LongInt; cdecl;

  TSDConnectLocalFn = function(Account: PAnsiChar): LongInt; cdecl;

  TSDDcountFn = function(Src, Delim: PAnsiChar): LongInt; cdecl;

  TSDDebugFn = procedure(Mode: LongInt); cdecl;

  TSDDelFn = function(Src: PAnsiChar; Fno, Vno, Svno: LongInt): PAnsiChar; cdecl;

  TSDDeleteFn = procedure(FileNo: LongInt; Id: PAnsiChar); cdecl;

  TSDDeleteuFn = procedure(FileNo: LongInt; Id: PAnsiChar); cdecl;

  TSDDisconnectFn = procedure; cdecl;

  TSDDisconnectAllFn = procedure; cdecl;

  TSDEndCommandFn = procedure; cdecl;

  TSDErrorFn = function: PAnsiChar; cdecl;

  TSDEvalConvFn = function(FileNo: LongInt; Name: PAnsiChar; Data: PAnsiChar; Id: PAnsiChar): PAnsiChar; cdecl;

  TSDEvaluateFn = function(FileNo: LongInt; Name: PAnsiChar; Data: PAnsiChar; Id: PAnsiChar): PAnsiChar; cdecl;

  TSDExecuteFn = function(Cmnd: PAnsiChar; ErrNo: PLongInt): PAnsiChar; cdecl;

  TSDExtractFn = function(Src: PAnsiChar; Fno, Vno, Svno: LongInt): PAnsiChar; cdecl;

  TSDFieldFn = function(Src, Delim: PAnsiChar; First, Occurrences: LongInt): PAnsiChar; cdecl;

  TSDFreeFn = procedure(P: Pointer); cdecl;

  TSDGetArgFn = function(ArgNo: LongInt): PAnsiChar; cdecl;

  TSDGetSessionFn = function: LongInt; cdecl;

  TSDGetVarFn = function(Name: PAnsiChar): PAnsiChar; cdecl;

  TSDIConvFn = function(Data: PAnsiChar; Code: PAnsiChar): PAnsiChar; cdecl;

  TSDIConvsFn = function(Data: PAnsiChar; Code: PAnsiChar): PAnsiChar; cdecl;

  TSDIndicesFn = function(FileNo: LongInt; IndexName: PAnsiChar): PAnsiChar; cdecl;

  TSDInsFn = function(Src: PAnsiChar; Fno, Vno, Svno: LongInt;
    NewData: PAnsiChar): PAnsiChar; cdecl;

  TSDLocateFn = function(Item, Src: PAnsiChar; Fno, Vno, Svno: LongInt;
    Pos: PLongInt; Order: PAnsiChar): LongInt; cdecl;

  TSDLogtoFn = function(AccountName: PAnsiChar): LongInt; cdecl;

  TSDMarkMappingFn = procedure(FileNo, State: LongInt); cdecl;

  TSDMatchFn = function(Src, Template: PAnsiChar): LongInt; cdecl;

  TSDMatchfieldFn = function(Src, Template: PAnsiChar;
    Component: LongInt): PAnsiChar; cdecl;

  TSDOConvFn = function(Data: PAnsiChar; Code: PAnsiChar): PAnsiChar; cdecl;

  TSDOConvsFn = function(Data: PAnsiChar; Code: PAnsiChar): PAnsiChar; cdecl;

  TSDOpenFn = function(FileName: PAnsiChar): LongInt; cdecl;

  TSDOpenSeqFn = function(FileName: PAnsiChar; Id: PAnsiChar; Modes: LongInt): LongInt; cdecl;

  TSDReadFn = function(FileNo: LongInt; Id: PAnsiChar; Err: PLongInt): PAnsiChar; cdecl;

  TSDReadBlkFn = function(FileNo: LongInt; Bytes: LongInt; ActualBytes: PLongInt): PAnsiChar; cdecl;

  TSDReadlFn = function(FileNo: LongInt; Id: PAnsiChar; Wait: LongInt;
    Err: PLongInt): PAnsiChar; cdecl;

  TSDReadListFn = function(ListNo: LongInt): PAnsiChar; cdecl;

  TSDReadNextFn = function(ListNo: LongInt): PAnsiChar; cdecl;

  TSDReadSeqFn = function(FileNo: LongInt; ErrNo: PLongInt): PAnsiChar; cdecl;

  TSDReaduFn = function(FileNo: LongInt; Id: PAnsiChar; Wait: LongInt;
    Err: PLongInt): PAnsiChar; cdecl;

  TSDRecordlockFn = procedure(FileNo: LongInt; Id: PAnsiChar;
    UpdateLock, Wait: LongInt); cdecl;

  TSDRecordlockedFn = function(FileNo: LongInt; Id: PAnsiChar): LongInt; cdecl;

  TSDReleaseFn = procedure(FileNo: LongInt; Id: PAnsiChar); cdecl;

  TSDReplaceFn = function(Src: PAnsiChar; Fno, Vno, Svno: LongInt;
    NewData: PAnsiChar): PAnsiChar; cdecl;

  TSDRespondFn = function(Response: PAnsiChar; ErrNo: PLongInt): PAnsiChar; cdecl;

  TSDRevisionFn = function: PAnsiChar; cdecl;

  TSDRTransFn = function(FileName: PAnsiChar; Id: PAnsiChar; FieldName: PAnsiChar; Action: PAnsiChar): PAnsiChar; cdecl;

  TSDSeekFn = procedure(FileNo: LongInt; Offset: LongInt; RelTo: LongInt); cdecl;

  TSDSelectFn = procedure(FileNo, ListNo: LongInt); cdecl;

  TSDSelectIndexFn = procedure(FileNo: LongInt; IndexName, IndexValue: PAnsiChar;
    ListNo: LongInt); cdecl;

  TSDSelectLeftFn = function(FileNo: LongInt; IndexName: PAnsiChar;
    ListNo: LongInt): PAnsiChar; cdecl;

  TSDSelectRightFn = function(FileNo: LongInt; IndexName: PAnsiChar;
    ListNo: LongInt): PAnsiChar; cdecl;

  TSDSetLeftFn = procedure(FileNo: LongInt; IndexName: PAnsiChar); cdecl;

  TSDSetRightFn = procedure(FileNo: LongInt; IndexName: PAnsiChar); cdecl;

  TSDSetSessionFn = function(Session: LongInt): LongInt; cdecl;

  TSDStatusFn = function: LongInt; cdecl;

  TSDSystemFn = function(Key: LongInt): PAnsiChar; cdecl;

  TSDTransFn = function(FileName: PAnsiChar; Id: PAnsiChar; FieldName: PAnsiChar; Action: PAnsiChar): PAnsiChar; cdecl;

  TSDTxnFn = procedure(Mode: LongInt); cdecl;

  TSDWeofSeqFn = procedure(FileNo: LongInt); cdecl;

  TSDWriteFn = procedure(FileNo: LongInt; Id, RecData: PAnsiChar); cdecl;

  TSDWriteBlkFn = procedure(FileNo: LongInt; Rec: PAnsiChar; Bytes: LongInt); cdecl;

  TSDWriteSeqFn = procedure(FileNo: LongInt; Rec: PAnsiChar); cdecl;

  TSDWriteSeqKeyFn = function(FileNo: LongInt; Rec: PAnsiChar): PAnsiChar; cdecl;

  TSDWriteuFn = procedure(FileNo: LongInt; Id, RecData: PAnsiChar); cdecl;

  TSDWriteuSeqKeyFn = function(FileNo: LongInt; Rec: PAnsiChar): PAnsiChar; cdecl;

// Global function pointers (sorted)
var
  SDCall: TSDCallFn;
  SDCallx: TSDCallxFn;
  SDChange: TSDChangeFn;
  SDClearSelect: TSDClearSelectFn;
  SdCliLib: TLibHandle;
  SDClose: TSDCloseFn;
  SDConnect: TSDConnectFn;
  SDConnected: TSDConnectedFn;
  SDConnectLocal: TSDConnectLocalFn;
  SDDcount: TSDDcountFn;
  SDDebug: TSDDebugFn;
  SDDel: TSDDelFn;
  SDDelete: TSDDeleteFn;
  SDDeleteu: TSDDeleteuFn;
  SDDisconnect: TSDDisconnectFn;
  SDDisconnectAll: TSDDisconnectAllFn;
  SDEndCommand: TSDEndCommandFn;
  SDError: TSDErrorFn;
  SDEvalConv: TSDEvalConvFn;
  SDEvaluate: TSDEvaluateFn;
  SDExecute: TSDExecuteFn;
  SDExtract: TSDExtractFn;
  SDField: TSDFieldFn;
  SDFree: TSDFreeFn;
  SDGetArg: TSDGetArgFn;
  SDGetSession: TSDGetSessionFn;
  SDGetVar: TSDGetVarFn;
  SDIConv: TSDIConvFn;
  SDIConvs: TSDIConvsFn;
  SDIndices: TSDIndicesFn;
  SDIns: TSDInsFn;
  SDLocate: TSDLocateFn;
  SDLogto: TSDLogtoFn;
  SDMarkMapping: TSDMarkMappingFn;
  SDMatch: TSDMatchFn;
  SDMatchfield: TSDMatchfieldFn;
  SDOConv: TSDOConvFn;
  SDOConvs: TSDOConvsFn;
  SDOpen: TSDOpenFn;
  SDOpenSeq: TSDOpenSeqFn;
  SDRead: TSDReadFn;
  SDReadBlk: TSDReadBlkFn;
  SDReadl: TSDReadlFn;
  SDReadList: TSDReadListFn;
  SDReadNext: TSDReadNextFn;
  SDReadSeq: TSDReadSeqFn;
  SDReadu: TSDReaduFn;
  SDRecordlock: TSDRecordlockFn;
  SDRecordlocked: TSDRecordlockedFn;
  SDRelease: TSDReleaseFn;
  SDReplace: TSDReplaceFn;
  SDRespond: TSDRespondFn;
  SDRevision: TSDRevisionFn;
  SDRTrans: TSDRTransFn;
  SDSeek: TSDSeekFn;
  SDSelect: TSDSelectFn;
  SDSelectIndex: TSDSelectIndexFn;
  SDSelectLeft: TSDSelectLeftFn;
  SDSelectRight: TSDSelectRightFn;
  SDSetLeft: TSDSetLeftFn;
  SDSetRight: TSDSetRightFn;
  SDSetSession: TSDSetSessionFn;
  SDStatus: TSDStatusFn;
  SDSystem: TSDSystemFn;
  SDTrans: TSDTransFn;
  SDTxn: TSDTxnFn;
  SDWeofSeq: TSDWeofSeqFn;
  SDWrite: TSDWriteFn;
  SDWriteBlk: TSDWriteBlkFn;
  SDWriteSeq: TSDWriteSeqFn;
  SDWriteSeqKey: TSDWriteSeqKeyFn;
  SDWriteu: TSDWriteuFn;
  SDWriteuSeqKey: TSDWriteuSeqKeyFn;

function LoadSdCliLib(const BasePath: string = ''): Boolean;
procedure UnloadSdCliLib;

implementation

uses
  SysUtils;

var
  Missing: Boolean;

function Sym(const AName: string): Pointer;
begin
  Result := GetProcedureAddress(SdCliLib, AName);
  if Result = nil then Missing := True;
end;

function LoadSdCliLib(const BasePath: string): Boolean;
var
  Path: string;
begin
  Result := True;
  if SdCliLib <> NilHandle then Exit;
  if BasePath = '' then
    Path := 'sdclilib.so'
  else
    Path := IncludeTrailingPathDelimiter(BasePath) + 'sdclilib.so';
  SdCliLib := LoadLibrary(Path);
  if SdCliLib = NilHandle then
  begin
    Result := False;
    Exit;
  end;
  Missing := False;
  SDCall := TSDCallFn(Sym('SDCall'));
  SDCallx := TSDCallxFn(Sym('SDCallx'));
  SDChange := TSDChangeFn(Sym('SDChange'));
  SDClearSelect := TSDClearSelectFn(Sym('SDClearSelect'));
  SDClose := TSDCloseFn(Sym('SDClose'));
  SDConnect := TSDConnectFn(Sym('SDConnect'));
  SDConnected := TSDConnectedFn(Sym('SDConnected'));
  SDConnectLocal := TSDConnectLocalFn(Sym('SDConnectLocal'));
  SDDcount := TSDDcountFn(Sym('SDDcount'));
  SDDebug := TSDDebugFn(Sym('SDDebug'));
  SDDel := TSDDelFn(Sym('SDDel'));
  SDDelete := TSDDeleteFn(Sym('SDDelete'));
  SDDeleteu := TSDDeleteuFn(Sym('SDDeleteu'));
  SDDisconnect := TSDDisconnectFn(Sym('SDDisconnect'));
  SDDisconnectAll := TSDDisconnectAllFn(Sym('SDDisconnectAll'));
  SDEndCommand := TSDEndCommandFn(Sym('SDEndCommand'));
  SDError := TSDErrorFn(Sym('SDError'));
  SDEvalConv := TSDEvalConvFn(Sym('SDEvalConv'));
  SDEvaluate := TSDEvaluateFn(Sym('SDEvaluate'));
  SDExecute := TSDExecuteFn(Sym('SDExecute'));
  SDExtract := TSDExtractFn(Sym('SDExtract'));
  SDField := TSDFieldFn(Sym('SDField'));
  SDFree := TSDFreeFn(Sym('SDFree'));
  SDGetArg := TSDGetArgFn(Sym('SDGetArg'));
  SDGetSession := TSDGetSessionFn(Sym('SDGetSession'));
  SDGetVar := TSDGetVarFn(Sym('SDGetVar'));
  SDIConv := TSDIConvFn(Sym('SDIConv'));
  SDIConvs := TSDIConvsFn(Sym('SDIConvs'));
  SDIndices := TSDIndicesFn(Sym('SDIndices'));
  SDIns := TSDInsFn(Sym('SDIns'));
  SDLocate := TSDLocateFn(Sym('SDLocate'));
  SDLogto := TSDLogtoFn(Sym('SDLogto'));
  SDMarkMapping := TSDMarkMappingFn(Sym('SDMarkMapping'));
  SDMatch := TSDMatchFn(Sym('SDMatch'));
  SDMatchfield := TSDMatchfieldFn(Sym('SDMatchfield'));
  SDOConv := TSDOConvFn(Sym('SDOConv'));
  SDOConvs := TSDOConvsFn(Sym('SDOConvs'));
  SDOpen := TSDOpenFn(Sym('SDOpen'));
  SDOpenSeq := TSDOpenSeqFn(Sym('SDOpenSeq'));
  SDRead := TSDReadFn(Sym('SDRead'));
  SDReadBlk := TSDReadBlkFn(Sym('SDReadBlk'));
  SDReadl := TSDReadlFn(Sym('SDReadl'));
  SDReadList := TSDReadListFn(Sym('SDReadList'));
  SDReadNext := TSDReadNextFn(Sym('SDReadNext'));
  SDReadSeq := TSDReadSeqFn(Sym('SDReadSeq'));
  SDReadu := TSDReaduFn(Sym('SDReadu'));
  SDRecordlock := TSDRecordlockFn(Sym('SDRecordlock'));
  SDRecordlocked := TSDRecordlockedFn(Sym('SDRecordlocked'));
  SDRelease := TSDReleaseFn(Sym('SDRelease'));
  SDReplace := TSDReplaceFn(Sym('SDReplace'));
  SDRespond := TSDRespondFn(Sym('SDRespond'));
  SDRevision := TSDRevisionFn(Sym('SDRevision'));
  SDRTrans := TSDRTransFn(Sym('SDRTrans'));
  SDSeek := TSDSeekFn(Sym('SDSeek'));
  SDSelect := TSDSelectFn(Sym('SDSelect'));
  SDSelectIndex := TSDSelectIndexFn(Sym('SDSelectIndex'));
  SDSelectLeft := TSDSelectLeftFn(Sym('SDSelectLeft'));
  SDSelectRight := TSDSelectRightFn(Sym('SDSelectRight'));
  SDSetLeft := TSDSetLeftFn(Sym('SDSetLeft'));
  SDSetRight := TSDSetRightFn(Sym('SDSetRight'));
  SDSetSession := TSDSetSessionFn(Sym('SDSetSession'));
  SDStatus := TSDStatusFn(Sym('SDStatus'));
  SDSystem := TSDSystemFn(Sym('SDSystem'));
  SDTrans := TSDTransFn(Sym('SDTrans'));
  SDTxn := TSDTxnFn(Sym('SDTxn'));
  SDWeofSeq := TSDWeofSeqFn(Sym('SDWeofSeq'));
  SDWrite := TSDWriteFn(Sym('SDWrite'));
  SDWriteBlk := TSDWriteBlkFn(Sym('SDWriteBlk'));
  SDWriteSeq := TSDWriteSeqFn(Sym('SDWriteSeq'));
  SDWriteSeqKey := TSDWriteSeqKeyFn(Sym('SDWriteSeqKey'));
  SDWriteu := TSDWriteuFn(Sym('SDWriteu'));
  SDWriteuSeqKey := TSDWriteuSeqKeyFn(Sym('SDWriteuSeqKey'));
  if Missing then
  begin
    UnloadSdCliLib;
    Result := False;
  end;
end;

procedure UnloadSdCliLib;
begin
  SDCall := nil;
  SDCallx := nil;
  SDChange := nil;
  SDClearSelect := nil;
  SDClose := nil;
  SDConnect := nil;
  SDConnected := nil;
  SDConnectLocal := nil;
  SDDcount := nil;
  SDDebug := nil;
  SDDel := nil;
  SDDelete := nil;
  SDDeleteu := nil;
  SDDisconnect := nil;
  SDDisconnectAll := nil;
  SDEndCommand := nil;
  SDError := nil;
  SDEvalConv := nil;
  SDEvaluate := nil;
  SDExecute := nil;
  SDExtract := nil;
  SDField := nil;
  SDFree := nil;
  SDGetArg := nil;
  SDGetSession := nil;
  SDGetVar := nil;
  SDIConv := nil;
  SDIConvs := nil;
  SDIndices := nil;
  SDIns := nil;
  SDLocate := nil;
  SDLogto := nil;
  SDMarkMapping := nil;
  SDMatch := nil;
  SDMatchfield := nil;
  SDOConv := nil;
  SDOConvs := nil;
  SDOpen := nil;
  SDOpenSeq := nil;
  SDRead := nil;
  SDReadBlk := nil;
  SDReadl := nil;
  SDReadList := nil;
  SDReadNext := nil;
  SDReadSeq := nil;
  SDReadu := nil;
  SDRecordlock := nil;
  SDRecordlocked := nil;
  SDRelease := nil;
  SDReplace := nil;
  SDRespond := nil;
  SDRevision := nil;
  SDRTrans := nil;
  SDSeek := nil;
  SDSelect := nil;
  SDSelectIndex := nil;
  SDSelectLeft := nil;
  SDSelectRight := nil;
  SDSetLeft := nil;
  SDSetRight := nil;
  SDSetSession := nil;
  SDStatus := nil;
  SDSystem := nil;
  SDTrans := nil;
  SDTxn := nil;
  SDWeofSeq := nil;
  SDWrite := nil;
  SDWriteBlk := nil;
  SDWriteSeq := nil;
  SDWriteSeqKey := nil;
  SDWriteu := nil;
  SDWriteuSeqKey := nil;
  if SdCliLib <> NilHandle then FreeLibrary(SdCliLib);
  SdCliLib := NilHandle;
end;

end.
