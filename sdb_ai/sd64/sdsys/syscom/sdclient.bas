Attribute VB_Name = "SDClient"
' SDClient.bas
' SDClient API function and constant definitions.
' Copyright (c) 2002, Ladybridge Systems, All Rights Reserved


Declare Sub SDCall Lib "SDClient.dll" (ByVal name As String, ByVal ArgCount As Integer, Optional ByRef a1 As String, Optional ByRef a2 As String, Optional ByRef a3 As String, Optional ByRef a4 As String, Optional ByRef a5 As String, Optional ByRef a6 As String, Optional ByRef a7 As String, Optional ByRef a8 As String, Optional ByRef a9 As String, Optional ByRef a10 As String, Optional ByRef a11 As String, Optional ByRef a12 As String, Optional ByRef a13 As String, Optional ByRef a14 As String, Optional ByRef a15 As String, Optional ByRef a16 As String, Optional ByRef a17 As String, Optional ByRef a18 As String, Optional ByRef a19 As String, Optional ByRef a20 As String)
Declare Function SDChange Lib "SDClient.dll" (ByVal Str As String, ByVal OldStr As String, ByVal NewStr As String, Optional ByRef Occurrences As Long, Optional ByRef Start As Long) As String
Declare Function SDConnect Lib "SDClient.dll" (ByVal Host As String, ByVal Port As Integer, ByVal UserName As String, ByVal Password As String, ByVal Account As String) As Boolean
Declare Function SDConnectLocal Lib "SDClient.dll" (ByVal Account As String) As Boolean
Declare Function SDConnected Lib "SDClient.dll" () As Boolean
Declare Sub SDClearSelect Lib "SDClient.dll" (ByVal ListNo As Integer)
Declare Sub SDClose Lib "SDClient.dll" (ByVal FileNo As Integer)
Declare Function SDDcount Lib "SDClient.dll" (ByVal Src As String, ByVal Delim As String) As Long
Declare Function SDDel Lib "SDClient.dll" (ByVal Src As String, ByVal Fno As Integer, ByVal Vno As Integer, ByVal Svno As Integer) As String
Declare Sub SDDelete Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String)
Declare Sub SDDeleteu Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String)
Declare Sub SDDisconnect Lib "SDClient.dll" ()
Declare Sub SDDisconnectAll Lib "SDClient.dll" ()
Declare Sub SDEndCommand Lib "SDClient.dll" ()
Declare Function SDError Lib "SDClient.dll" () As String
Declare Function SDExecute Lib "SDClient.dll" (ByVal Cmnd As String, ByRef ErrNo As Integer) As String
Declare Function SDExtract Lib "SDClient.dll" (ByVal Src As String, ByVal Fno As Integer, ByVal Vno As Integer, ByVal Svno As Integer) As String
Declare Function SDField Lib "SDClient.dll" (ByVal Str As String, ByVal Delimited As String, ByVal Start As Long, Optional ByRef Occurrences As Long) As String
Declare Function SDGetSession Lib "SDClient.dll" () As Integer
Declare Function SDIns Lib "SDClient.dll" (ByVal Src As String, ByVal Fno As Integer, ByVal Vno As Integer, ByVal Svno As Integer, ByVal NewData As String) As String
Declare Function SDLocate Lib "SDClient.dll" (ByVal Item As String, ByVal Src As String, ByVal Fno As Integer, ByVal Vno As Integer, ByVal Svno As Integer, ByRef Pos As Integer, ByVal Order As String) As Boolean
Declare Function SDLogto Lib "SDClient.dll" (ByVal Cmnd As String) As Boolean
Declare Function SDMarkMapping Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal State As Integer)
Declare Function SDMatch Lib "SDClient.dll" (ByVal Src As String, ByVal Template As String) As Boolean
Declare Function SDMatchfield Lib "SDClient.dll" (ByVal Src As String, ByVal Template As String, ByVal Component As Integer) As String
Declare Function SDOpen Lib "SDClient.dll" (ByVal Filename As String) As Integer
Declare Function SDRead Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String, ByRef ErrNo As Integer) As String
Declare Function SDReadl Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String, ByVal Wait As Boolean, ByRef ErrNo As Integer) As String
Declare Function SDReadList Lib "SDClient.dll" (ByVal ListNo As Integer, ByRef ErrNo As Integer) As String
Declare Function SDReadNext Lib "SDClient.dll" (ByVal ListNo As Integer, ByRef ErrNo As Integer) As String
Declare Function SDReadu Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String, ByVal Wait As Boolean, ByRef ErrNo As Integer) As String
Declare Sub SDRecordlock Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String, ByVal UpdateLock as Integer, ByVal Wait as Integer)
Declare Sub SDRelease Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String)
Declare Function SDReplace Lib "SDClient.dll" (ByVal Src As String, ByVal Fno As Integer, ByVal Vno As Integer, ByVal Svno As Integer, ByVal NewData As String) As String
Declare Function SDRespond Lib "SDClient.dll" (ByVal Response As String, ByRef ErrNo As Integer) As String
Declare Sub SDSelect Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal ListNo As Integer)
Declare Sub SDSelectIndex Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal IndexName as String, ByVal IndexValue as String, ByVal ListNo As Integer)
Declare Function SDSelectLeft Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal IndexName as String, ByVal ListNo As Integer) as String
Declare Function SDSelectRight Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal IndexName as String, ByVal ListNo As Integer) as String
Declare Sub SDSetLeft Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal IndexName as String)
Declare Sub SDSetRight Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal IndexName as String)
Declare Function SDSetSession Lib "SDClient.dll" (ByVal Session as Integer) As Boolean
Declare Function SDStatus Lib "SDClient.dll" () As Long
Declare Sub SDWrite Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String, ByVal Data As String)
Declare Sub SDWriteu Lib "SDClient.dll" (ByVal FileNo As Integer, ByVal Id As String, ByVal Data As String)


Global Const SV_OK = 0        ' Action successul
Global Const SV_ON_ERROR = 1  ' Trapped abort
Global Const SV_ELSE = 2      ' Action took the ELSE clause
Global Const SV_ERROR = 3     ' Error for which SDError() can be used to retrieve error text
Global Const SV_LOCKED = 4    ' Action blocked by a lock held by another user
Global Const SV_PROMPT = 5    ' Server requesting input

Global Const SDDateOffset = 24837
