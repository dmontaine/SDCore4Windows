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
Declare.s SDChange(Src.s, Old.s, New.s, Occ.l, Start.l)
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
Declare.l SDGetSession()
Declare.s SDIns(Src.s, Fno.l, Vno.l, SvNo.l, New.s)
Declare.s SDLocate(Item.s, Dyn.s, Fno.l, Vno.l, SvNo.l, *Pos.l, Order.s)
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
Declare SDRelease(Fileno.l, Id.s)
Declare.s SDReplace(Src.s, Fno.l, Vno.l, SvNo.l, New.s)
Declare.s SDRespond(Response.s, *Err.l)
Declare SDSelect(Fileno.l, Listno.l)
Declare SDSelectIndex(Fileno.l, IndexName.s, IndexValue.s, Listno.l)
Declare.s SDSelectLeft(Fileno.l, IndexName.s, Listno.l)
Declare.s SDSelectRight(Fileno.l, IndexName.s, Listno.l)
Declare SDSetLeft(Fileno.l, IndexName.s)
Declare SDSetRight(Fileno.l, IndexName.s)
Declare.l SDSetSession(Idx.l)
Declare.l SDStatus()
Declare SDWrite(Fileno.l, Id.s, Rec.s)
Declare SDWriteu(Fileno.l, Id.s, Rec.s)


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
Procedure.s SDLocate(Item.s, Dyn.s, Fno.l, Vno.l, SvNo.l, *Pos.l, Order.s)
   OpenSDClientLibrary()
   *String = CallCFunction(SDLib, "SDLocate", Item, Dyn, Fno, Vno, SvNo, *Pos, Order)
   If *string
      String$ = PeekS(*String)
      CallCFunction(SDLib, "SDFree", *String)
   EndIf
   ProcedureReturn String$
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
