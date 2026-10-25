; SDClient.pb
; SDClient PureBasic interface
; Copyright (c) 2005 Ladybridge Systems, All Rights Reserved

; Change History:
; 22 Mar 07  2.5-1 Changed UseFile() to FileID() to correspond to change in
;                  PureBasic version 4.
;                  Changed interface to ReadString(). Corrected definitions
;                  for SDError() and SDExecute().
; Usage notes:
;
; All arguments to SDCall() must be strings. Where a called subroutine returns
; a modified argument, the input string must be large enough to receive the
; result.
;
; Error code arguments, declared as *Err.l must be passed as pointers, for
; example:
;    s = SDRead(fno, id, @errno)


; Procedure declarations for use where needed

Declare SDCall0(Subrname.s)
Declare SDCall1(Subrname.s, *Arg1)
Declare SDCall2(Subrname.s, *Arg1, *Arg2)
Declare SDCall3(Subrname.s, *Arg1, *Arg2, *Arg3)
Declare SDCall4(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4)
Declare SDCall5(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5)
Declare SDCall6(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6)
Declare SDCall7(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7)
Declare SDCall8(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8)
Declare SDCall9(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9)
Declare SDCall10(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10)
Declare SDCall11(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11)
Declare SDCall12(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12)
Declare SDCall13(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13)
Declare SDCall14(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14)
Declare SDCall15(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15)
Declare SDCall16(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16)
Declare SDCall17(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17)
Declare SDCall18(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18)
Declare SDCall19(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19)
Declare SDCall20(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19, *Arg20)
Declare SDCallx0(Subrname.s)
Declare SDCallx1(Subrname.s, *Arg1)
Declare SDCallx2(Subrname.s, *Arg1, *Arg2)
Declare SDCallx3(Subrname.s, *Arg1, *Arg2, *Arg3)
Declare SDCallx4(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4)
Declare SDCallx5(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5)
Declare SDCallx6(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6)
Declare SDCallx7(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7)
Declare SDCallx8(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8)
Declare SDCallx9(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9)
Declare SDCallx10(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10)
Declare SDCallx11(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11)
Declare SDCallx12(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12)
Declare SDCallx13(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13)
Declare SDCallx14(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14)
Declare SDCallx15(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15)
Declare SDCallx16(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16)
Declare SDCallx17(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17)
Declare SDCallx18(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18)
Declare SDCallx19(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19)
Declare SDCallx20(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19, *Arg20)
Declare.s SDChange(Src.s, Old.s, New.s, Occ.l, Start.l)
Declare.l SDChecksum(Data.s)
Declare SDClearSelect(ListNo.l)
Declare SDClose(Fileno.l)
Declare SDClose(Fileno.l)
Declare.l SDConnect(Host.s, Port.l, User.s, Password.s, Account.s)
Declare.l SDConnectLocal(Account.s)
Declare.l SDConnected()
Declare.l SDDcount(String.s, Delim.s)
Declare.s SDDel(Src.s, Fno.l, Vno.l, SvNo.l)
Declare SDDelete(Fileno.l, Id.s)
Declare SDDeleteu(Fileno.l, Id.s)
Declare SDDisconnect()
Declare SDDisconnectAll()
Declare SDEndCommand()
Declare.s SDError()
Declare.s SDExecute(Cmd.s, *Err.l)
Declare.s SDExtract(Src.s, Fno.l, Vno.l, SvNo.l)
Declare.s SDField(Src.s, Delim.s, Start.l, Occ.l)
Declare.s SDGetArg(ArgNo.l)
Declare.l SDLogto(Account.s)
Declare SDDebug(Mode.l)
Declare.l SDGetSession()
Declare.s SDIns(Src.s, Fno.l, Vno.l, SvNo.l, New.s)
Declare.l SDLocate(Item.s, Dyn.s, Fno.l, Vno.l, SvNo.l, *Pos.l, Order.s)
Declare SDMarkMapping(Fileno.l, State.l)
Declare.l SDMatch(String.s, Template.s)
Declare.s SDMatchfield(String.s, Template.s, Component.l)
Declare.l SDOpen(Filename.s)
Declare.s SDRead(Fileno.l, Id.s, *Err.l)
Declare.s SDReadl(Fileno.l, Id.s, Wait.l, *Err.l)
Declare.s SDReadList(Listno.l)
Declare.s SDReadNext(Listno.l)
Declare.s SDReadu(Fileno.l, Id.s, Wait.l, *Err.l)
Declare SDRecordlock(Fileno.l, Id.s, Update.l, Wait.l)
Declare.l SDRecordlocked(Fileno.l, Id.s)
Declare SDRelease(Fileno.l, Id.s)
Declare.s SDReplace(Src.s, Fno.l, Vno.l, SvNo.l, New.s)
Declare.s SDRespond(Response.s, *Err.l)
Declare SDSelect(Fileno.l, Listno.l)
Declare SDSelectIndex(Fileno.l, IndexName.s, IndexValue.s, Listno.l)
Declare.s SDSelectLeft(Fileno.l, IndexName.s, Listno.l)
Declare.s SDSelectRight(Fileno.l, IndexName.s, Listno.l)
Declare.s SDGetVar(Name.s)
Declare.s SDIndices(Fileno.l, IndexName.s)
Declare.s SDRevision()
Declare.s SDRTrans(FileName.s, Id.s, FieldName.s, Action.s)
Declare.s SDSystem(Key.l)
Declare.s SDTrans(FileName.s, Id.s, FieldName.s, Action.s)
Declare SDTxn(Mode.l)
Declare.s SDEvaluate(Fileno.l, Name.s, Data.s, Id.s)
Declare.s SDEvalConv(Fileno.l, Name.s, Data.s, Id.s)
Declare.s SDIConv(Data.s, Code.s)
Declare.s SDOConv(Data.s, Code.s)
Declare.s SDIConvs(Data.s, Code.s)
Declare.s SDOConvs(Data.s, Code.s)
Declare SDSetLeft(Fileno.l, IndexName.s)
Declare SDSetRight(Fileno.l, IndexName.s)
Declare.l SDSetSession(Idx.l)
Declare.l SDStatus()
Declare SDWrite(Fileno.l, Id.s, Rec.s)
Declare SDWriteu(Fileno.l, Id.s, Rec.s)
Declare.l SDOpenSeq(Filename.s, Id.s, Modes.l)
Declare.s SDReadSeq(Fileno.l, *Err.l)
Declare.s SDReadBlk(Fileno.l, Bytes.l, *Actual.l)
Declare SDWriteSeq(Fileno.l, Rec.s)
Declare SDWriteBlk(Fileno.l, Rec.s, Bytes.l)
Declare SDSeek(Fileno.l, Offset.l, RelTo.l)
Declare SDWeofSeq(Fileno.l)
Declare.s SDWriteSeqKey(Fileno.l, Rec.s)
Declare.s SDWriteuSeqKey(Fileno.l, Rec.s)


; ======================================================================
; The actual interface routines

Global SDLib
Global Connected


;===== OpenSDClientLibrary  (Called internally - Do not use in user programs)
Procedure OpenSDClientLibrary()
   If SDLib = 0
      ConfigPath$ = "/etc/sdconfig"
      fno = ReadFile(#PB_Any, ConfigPath$)
      If fno = 0
         printn("Cannot open " + ConfigPath$)
         End
      EndIf

; PureBasic version 4 replacement code
      FileID(fno)
      Repeat
         String$ = ReadString(fno, #PB_Ascii)
      Until Eof(fno) Or Left(String$,6) = "SDSYS="

;     FileID(fno)
;     Repeat
;        String$ = ReadString()
;     Until Eof(fno) Or Left(String$,6) = "SDSYS="
; End of replacement code

      If Eof(fno)
         Printn("Cannot find SDSYS pointer in configuration file")
         CloseFile(fno)
         End
      EndIf

      CloseFile(fno)
      LibPath$ = Mid(String$, 7, 999) + "/bin/sdclilib.so"
      SDLib = OpenLibrary(#PB_Any, LibPath$)
      If SDLib = 0
         Printn("Cannot open " + LibPath$)
         End
      EndIf
   EndIf
EndProcedure


;===== CheckConnected  (Called internally - Do not use in user programs)
Procedure CheckConnected()
   If Connected = 0
      printn("SDClient server function attempted when not connected")
      End
   EndIf
EndProcedure


;===== SDCall
Procedure SDCall0(Subrname.s)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 0)
EndProcedure

Procedure SDCall1(Subrname.s, *Arg1)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 1, *Arg1)
EndProcedure

Procedure SDCall2(Subrname.s, *Arg1, *Arg2)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 2, *Arg1, *Arg2)
EndProcedure

Procedure SDCall3(Subrname.s, *Arg1, *Arg2, *Arg3)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 3, *Arg1, *Arg2, *Arg3)
EndProcedure

Procedure SDCall4(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 4, *Arg1, *Arg2, *Arg3, *Arg4)
EndProcedure

Procedure SDCall5(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 5, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5)
EndProcedure

Procedure SDCall6(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 6, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6)
EndProcedure

Procedure SDCall7(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 7, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7)
EndProcedure

Procedure SDCall8(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 8, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8)
EndProcedure

Procedure SDCall9(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 9, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9)
EndProcedure

Procedure SDCall10(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 10, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10)
EndProcedure

Procedure SDCall11(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 11, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11)
EndProcedure

Procedure SDCall12(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 12, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12)
EndProcedure

Procedure SDCall13(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 13, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13)
EndProcedure

Procedure SDCall14(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 14, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14)
EndProcedure

Procedure SDCall15(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 15, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15)
EndProcedure

Procedure SDCall16(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 16, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16)
EndProcedure

Procedure SDCall17(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 17, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17)
EndProcedure

Procedure SDCall18(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 18, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18)
EndProcedure

Procedure SDCall19(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 19, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19)
EndProcedure

Procedure SDCall20(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19, *Arg20)
   CheckConnected()
   CallCFunction(SDLib, "SDCall", Subrname, 20, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19, *Arg20)
EndProcedure


;===== SDCallx (15 Oct 26): SDCall's twin.  It does NOT put the called subroutine's changed arguments back into your
;      variables; read each one with SDGetArg(n) afterwards, 1 to the number of arguments
Procedure SDCallx0(Subrname.s)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 0)
EndProcedure

Procedure SDCallx1(Subrname.s, *Arg1)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 1, *Arg1)
EndProcedure

Procedure SDCallx2(Subrname.s, *Arg1, *Arg2)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 2, *Arg1, *Arg2)
EndProcedure

Procedure SDCallx3(Subrname.s, *Arg1, *Arg2, *Arg3)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 3, *Arg1, *Arg2, *Arg3)
EndProcedure

Procedure SDCallx4(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 4, *Arg1, *Arg2, *Arg3, *Arg4)
EndProcedure

Procedure SDCallx5(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 5, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5)
EndProcedure

Procedure SDCallx6(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 6, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6)
EndProcedure

Procedure SDCallx7(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 7, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7)
EndProcedure

Procedure SDCallx8(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 8, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8)
EndProcedure

Procedure SDCallx9(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 9, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9)
EndProcedure

Procedure SDCallx10(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 10, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10)
EndProcedure

Procedure SDCallx11(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 11, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11)
EndProcedure

Procedure SDCallx12(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 12, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12)
EndProcedure

Procedure SDCallx13(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 13, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13)
EndProcedure

Procedure SDCallx14(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 14, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14)
EndProcedure

Procedure SDCallx15(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 15, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15)
EndProcedure

Procedure SDCallx16(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 16, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16)
EndProcedure

Procedure SDCallx17(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 17, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17)
EndProcedure

Procedure SDCallx18(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 18, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18)
EndProcedure

Procedure SDCallx19(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 19, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19)
EndProcedure

Procedure SDCallx20(Subrname.s, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19, *Arg20)
   CheckConnected()
   CallCFunction(SDLib, "SDCallx", Subrname, 20, *Arg1, *Arg2, *Arg3, *Arg4, *Arg5, *Arg6, *Arg7, *Arg8, *Arg9, *Arg10, *Arg11, *Arg12, *Arg13, *Arg14, *Arg15, *Arg16, *Arg17, *Arg18, *Arg19, *Arg20)
EndProcedure

;===== SDChange
Procedure.s SDChange(Src.s, Old.s, New.s, Occ.l, Start.l)
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDChange", Src, Old, New, Occ, Start)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDChecksum
Procedure.l SDChecksum(Data.s)
   OpenSDClientLibrary()
   ProcedureReturn CallCFunction(SDLib, "SDChecksum", Data)
EndProcedure


;===== SDClearSelect
Procedure SDClearSelect(ListNo.l)
   CheckConnected()
   CallCFunction(SDLib, "SDClearSelect", ListNo)
EndProcedure


;===== SDClose
Procedure SDClose(Fileno.l)
   CheckConnected()
   CallCFunction(SDLib, "SDClose", Fileno)
EndProcedure


;===== SDConnect
Procedure.l SDConnect(Host.s, Port.l, User.s, Password.s, Account.s)
   OpenSDClientLibrary()
   If Connected
      SDDisconnect()
   EndIf
   Connected = CallCFunction(SDLib, "SDConnect", Host, Port, User, Password, Account)
   ProcedureReturn Connected
EndProcedure


;===== SDConnectLocal
Procedure.l SDConnectLocal(Account.s)
   OpenSDClientLibrary()
   If Connected
      SDDisconnect()
   EndIf
   Connected = CallCFunction(SDLib, "SDConnectLocal", Account)
   ProcedureReturn Connected
EndProcedure


;===== SDConnected
Procedure.l SDConnected()
   OpenSDClientLibrary()
   ProcedureReturn CallCFunction(SDLib, "SDConnected")
EndProcedure


;===== SDDcount
Procedure.l SDDcount(String.s, Delim.s)
   OpenSDClientLibrary()
   ProcedureReturn CallCFunction(SDLib, "SDDcount", String, Delim)
EndProcedure


;===== SDDel
Procedure.s SDDel(Src.s, Fno.l, Vno.l, SvNo.l)
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDDel", Src, OFno, Vno, SvNo)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDDelete
Procedure SDDelete(Fileno.l, Id.s)
   CheckConnected()
   CallCFunction(SDLib, "SDDelete", Fileno, Id)
EndProcedure


;===== SDDeleteu
Procedure SDDeleteu(Fileno.l, Id.s)
   CheckConnected()
   CallCFunction(SDLib, "SDDeleteu", Fileno, Id)
EndProcedure


;===== SDDisconnect
Procedure SDDisconnect()
   if Connected
      CallCFunction(SDLib, "SDDisconnect")
      Connected = 0
   EndIf
EndProcedure


;===== SDDisconnectAll
Procedure SDDisconnectAll()
   if Connected
      CallCFunction(SDLib, "SDDisconnectAll")
      Connected = 0
   EndIf
EndProcedure


;===== SDEndCommand
Procedure SDEndCommand()
   CheckConnected()
   CallCFunction(SDLib, "SDEndCommand")
EndProcedure


;===== SDError
Procedure.s SDError()
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDError")
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDExecute
Procedure.s SDExecute(Cmd.s, *Err.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDExecute", Cmd, *Err)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDExtract
Procedure.s SDExtract(Src.s, Fno.l, Vno.l, SvNo.l)
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDExtract", Src, OFno, Vno, SvNo)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDField
Procedure.s SDField(Src.s, Delim.s, Start.l, Occ.l)
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDField", Src, Delim, Start, Occ)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDGetArg (15 Oct 26): argument n of the last SDCallx
Procedure.s SDGetArg(ArgNo.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDGetArg", ArgNo)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDLogto (15 Oct 26)
Procedure.l SDLogto(Account.s)
   CheckConnected()
   ProcedureReturn CallCFunction(SDLib, "SDLogto", Account)
EndProcedure


;===== SDDebug (15 Oct 26): 1 writes the packets to the file clidbg in the current directory, 0 stops
Procedure SDDebug(Mode.l)
   OpenSDClientLibrary()
   CallCFunction(SDLib, "SDDebug", Mode)
EndProcedure


;===== SDGetSession
Procedure.l SDGetSession()
   OpenSDClientLibrary()
   ProcedureReturn CallCFunction(SDLib, "SDGetSession")
EndProcedure


;===== SDIns
Procedure.s SDIns(Src.s, Fno.l, Vno.l, SvNo.l, New.s)
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDIns", Src, OFno, Vno, SvNo, New)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDLocate
; 15 Oct 26: returns the library's int (1 found, 0 not), as the C header and the owner's PureBasic definitions have it.  It was
; declared and written as a String function, which would read the number 1 as the address of a string.
Procedure.l SDLocate(Item.s, Dyn.s, Fno.l, Vno.l, SvNo.l, *Pos.l, Order.s)
   OpenSDClientLibrary()
   ProcedureReturn CallCFunction(SDLib, "SDLocate", Item, Dyn, Fno, Vno, SvNo, *Pos, Order)
EndProcedure


;===== SDMarkMapping
; 15 Oct 26: declared since the first version of this file and never written.
Procedure SDMarkMapping(Fileno.l, State.l)
   CheckConnected()
   CallCFunction(SDLib, "SDMarkMapping", Fileno, State)
EndProcedure


;===== SDMatch
Procedure.l SDMatch(String.s, Template.s)
   OpenSDClientLibrary()
   ProcedureReturn CallCFunction(SDLib, "SDMatch", String, Template)
EndProcedure


;===== SDMatchfield
Procedure.s SDMatchfield(String.s, Template.s, Component.l)
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDMatchfield", String, Template, Component)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDOpen
Procedure.l SDOpen(Filename.s)
   CheckConnected()
   ProcedureReturn CallCFunction(SDLib, "SDOpen", Filename)
EndProcedure


;===== SDRead
Procedure.s SDRead(Fileno.l, Id.s, *Err.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDRead", Fileno, Id, *Err)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDReadl
Procedure.s SDReadl(Fileno.l, Id.s, Wait.l, *Err.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDReadl", Fileno, Id, Wait, *Err)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDReadList
Procedure.s SDReadList(Listno.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDReadList", Listno)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDReadNext
Procedure.s SDReadNext(Listno.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDReadNext", Listno)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDReadu
Procedure.s SDReadu(Fileno.l, Id.s, Wait.l, *Err.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDReadu", Fileno, Id, Wait, *Err)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDRecordlock
Procedure SDRecordlock(Fileno.l, Id.s, Update.l, Wait.l)
   CheckConnected()
   CallCFunction(SDLib, "SDRecordlock", Fileno, Id, Update, Wait)
EndProcedure


;===== SDRecordlocked (15 Oct 26): -3 -2 -1 another user holds a file, update or read lock; 0 none; 1 2 3 this session holds a read, update or file lock
Procedure.l SDRecordlocked(Fileno.l, Id.s)
   CheckConnected()
   ProcedureReturn CallCFunction(SDLib, "SDRecordlocked", Fileno, Id)
EndProcedure


;===== SDRelease
Procedure SDRelease(Fileno.l, Id.s)
   CheckConnected()
   CallCFunction(SDLib, "SDRelease", Fileno, Id)
EndProcedure


;===== SDReplace
Procedure.s SDReplace(Src.s, Fno.l, Vno.l, SvNo.l, New.s)
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDReplace", Src, OFno, Vno, SvNo, New)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDRespond
Procedure.s SDRespond(Response.s, *Err.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDRespond", Response, *Err)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDSelect
Procedure SDSelect(Fileno.l, Listno.l)
   CheckConnected()
   CallCFunction(SDLib, "SDSelect", Fileno, Listno)
EndProcedure


;===== SDSelectIndex
Procedure SDSelectIndex(Fileno.l, IndexName.s, IndexValue.s, Listno.l)
   CheckConnected()
   CallCFunction(SDLib, "SDSelectIndex", Fileno, IndexName, IndexValue, Listno)
EndProcedure


;===== SDSelectLeft
Procedure.s SDSelectLeft(Fileno.l, IndexName.s, Listno.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDSelectLeft", Fileno, IndexName, Listno)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDSelectRight
Procedure.s SDSelectRight(Fileno.l, IndexName.s, Listno.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDSelectRight", Fileno, IndexName, Listno)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDGetVar, SDIndices, SDRevision, SDRTrans, SDSystem, SDTrans (15 Oct 26): each returns one string from the library
Procedure.s SDGetVar(Name.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDGetVar", Name)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDIndices(Fileno.l, IndexName.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDIndices", Fileno, IndexName)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDRevision()
   OpenSDClientLibrary()                  ; works before a connection: the client's revision alone
   *String = CallCFunction(SDLib, "SDRevision")
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDRTrans(FileName.s, Id.s, FieldName.s, Action.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDRTrans", FileName, Id, FieldName, Action)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDSystem(Key.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDSystem", Key)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDTrans(FileName.s, Id.s, FieldName.s, Action.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDTrans", FileName, Id, FieldName, Action)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDTxn: 1 start, 2 commit, 3 abort, 4 commit non-durable
Procedure SDTxn(Mode.l)
   CheckConnected()
   CallCFunction(SDLib, "SDTxn", Mode)
EndProcedure


;===== SDEvaluate, SDEvalConv, SDIConv, SDOConv, SDIConvs, SDOConvs (15 Oct 26): each returns one string from the library
Procedure.s SDEvaluate(Fileno.l, Name.s, Data.s, Id.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDEvaluate", Fileno, Name, Data, Id)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDEvalConv(Fileno.l, Name.s, Data.s, Id.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDEvalConv", Fileno, Name, Data, Id)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDIConv(Data.s, Code.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDIConv", Data, Code)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDOConv(Data.s, Code.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDOConv", Data, Code)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDIConvs(Data.s, Code.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDIConvs", Data, Code)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDOConvs(Data.s, Code.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDOConvs", Data, Code)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


;===== SDSetLeft
Procedure SDSetLeft(Fileno.l, IndexName.s)
   CheckConnected()
   CallCFunction(SDLib, "SDSetLeft", Fileno, IndexName)
EndProcedure


;===== SDSetRight
Procedure SDSetRight(Fileno.l, IndexName.s)
   CheckConnected()
   CallCFunction(SDLib, "SDSetRight", Fileno, IndexName)
EndProcedure


;===== SDSetSession
Procedure.l SDSetSession(Idx.l)
   OpenSDClientLibrary()
   ProcedureReturn CallCFunction(SDLib, "SDSetSession", Idx)
EndProcedure


;===== SDStatus
Procedure.l SDStatus()
   OpenSDClientLibrary()
   ProcedureReturn CallCFunction(SDLib, "SDStatus")
EndProcedure


;===== SDWrite
Procedure SDWrite(Fileno.l, Id.s, Rec.s)
   CheckConnected()
   CallCFunction(SDLib, "SDWrite", Fileno, Id, Rec)
EndProcedure


;===== SDWriteu
Procedure SDWriteu(Fileno.l, Id.s, Rec.s)
   CheckConnected()
   CallCFunction(SDLib, "SDWriteu", Fileno, Id, Rec)
EndProcedure


;===== Sequential files (15 Oct 26): SDOpenSeq, SDReadSeq, SDReadBlk, SDWriteSeq, SDWriteBlk, SDSeek, SDWeofSeq; close with SDClose.
; SDOpenSeq(File, Id, Modes): File is a VOC name and Id the item in it, or with a null Id File is the pathname.  Modes adds 2 give
; up if another process has it, 16 read only, 256 append, 512 overwrite, 1024 flush every write, 4096 shared.  Returns the file
; number, or 0 (SDStatus() says why).  *Err gets the server's answer (2 at the end of the file).
Procedure.l SDOpenSeq(Filename.s, Id.s, Modes.l)
   CheckConnected()
   ProcedureReturn CallCFunction(SDLib, "SDOpenSeq", Filename, Id, Modes)
EndProcedure


Procedure.s SDReadSeq(Fileno.l, *Err.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDReadSeq", Fileno, *Err)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


; *Actual receives the number of bytes that came back; the data may hold any byte, so it is read by that count
Procedure.s SDReadBlk(Fileno.l, Bytes.l, *Actual.l)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDReadBlk", Fileno, Bytes, *Actual)
   If *string
      String$ = PeekS(*String, PeekL(*Actual), #PB_Ascii)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure SDWriteSeq(Fileno.l, Rec.s)
   CheckConnected()
   CallCFunction(SDLib, "SDWriteSeq", Fileno, Rec)
EndProcedure


Procedure SDWriteBlk(Fileno.l, Rec.s, Bytes.l)
   CheckConnected()
   CallCFunction(SDLib, "SDWriteBlk", Fileno, Rec, Bytes)
EndProcedure


; RelTo 0 from the start, 1 from here, 2 from the end
Procedure SDSeek(Fileno.l, Offset.l, RelTo.l)
   CheckConnected()
   CallCFunction(SDLib, "SDSeek", Fileno, Offset, RelTo)
EndProcedure


Procedure SDWeofSeq(Fileno.l)
   CheckConnected()
   CallCFunction(SDLib, "SDWeofSeq", Fileno)
EndProcedure


;===== SDWriteSeqKey, SDWriteuSeqKey (15 Oct 26): write a record of a HASHED file (the number SDOpen gave) under the id the file's
; own counter gives it, and return that id.  The second keeps the update lock the first releases.  CONFIGURE.FILE NEXT sets the counter.
Procedure.s SDWriteSeqKey(Fileno.l, Rec.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDWriteSeqKey", Fileno, Rec)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure


Procedure.s SDWriteuSeqKey(Fileno.l, Rec.s)
   CheckConnected()
   *String = CallCFunction(SDLib, "SDWriteuSeqKey", Fileno, Rec)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
EndProcedure
