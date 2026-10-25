"""sdclient.py - SD client API (sdclilib.so) bindings for Python 3, with ctypes.

From the Python definitions of the SD Core owner; 15 Oct 2026: SDGetVar, SDIndices, SDRecordlocked, SDOpenSeq, SDReadSeq, SDReadBlk, SDWriteSeq, SDWriteBlk, SDSeek, SDWeofSeq, SDRevision, SDSystem, SDTrans,
SDRTrans, SDTxn, SDEvaluate, SDEvalConv, SDIConv, SDOConv, SDIConvs and SDOConvs added (the functions of the QMClient
API that SD Core for Linux took on).  The library's own signatures are in gplsrc/sdclilib/sdclilib.h and win over this file.

Every function with a c_char_p result returns text the library allocated: ctypes copies it and the original is not
freed, so a long-running program that calls these many times leaks.  Declare the result type c_void_p instead, read
it with ctypes.string_at() and pass it to SDFree - sandbox-qmclient.py does exactly that.  SDCallx returns nothing;
read the arguments back with SDGetArg.  SDReadList and SDReadNext take only the list number.  SDOpenSeq gives the file number
for the sequential file functions and SDClose.  The data of SDReadBlk may hold any byte, including zero, where c_char_p ends:
give SDReadBlk a restype of c_void_p and read it with ctypes.string_at(ptr, ActualBytes).

The library is loaded from the current directory; change the path below (the installed one is
/usr/local/sdsys/bin/sdclilib.so).
"""

import ctypes

# Server status constants (sorted)
SV_ELSE = 2
SV_ERROR = 3
SV_LOCKED = 4
SV_OK = 0
SV_ON_ERROR = 1
SV_PROMPT = 5

# Library loading
_lib = ctypes.CDLL('./sdclilib.so')

# ctypes function bindings (sorted; argtypes / restype)
SDCall = _lib.SDCall
SDCall.argtypes = [ctypes.c_char_p, ctypes.c_short]
SDCall.restype = None

SDCallx = _lib.SDCallx
SDCallx.argtypes = [ctypes.c_char_p, ctypes.c_short]
SDCallx.restype = None

SDChange = _lib.SDChange
SDChange.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
SDChange.restype = ctypes.c_char_p

SDClearSelect = _lib.SDClearSelect
SDClearSelect.argtypes = [ctypes.c_int]
SDClearSelect.restype = None

SDClose = _lib.SDClose
SDClose.argtypes = [ctypes.c_int]
SDClose.restype = None

SDConnect = _lib.SDConnect
SDConnect.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
SDConnect.restype = ctypes.c_int

SDConnected = _lib.SDConnected
SDConnected.argtypes = []
SDConnected.restype = ctypes.c_int

SDConnectLocal = _lib.SDConnectLocal
SDConnectLocal.argtypes = [ctypes.c_char_p]
SDConnectLocal.restype = ctypes.c_int

SDDcount = _lib.SDDcount
SDDcount.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
SDDcount.restype = ctypes.c_int

SDDebug = _lib.SDDebug
SDDebug.argtypes = [ctypes.c_int]
SDDebug.restype = None

SDDel = _lib.SDDel
SDDel.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
SDDel.restype = ctypes.c_char_p

SDDelete = _lib.SDDelete
SDDelete.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDDelete.restype = None

SDDeleteu = _lib.SDDeleteu
SDDeleteu.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDDeleteu.restype = None

SDDisconnect = _lib.SDDisconnect
SDDisconnect.argtypes = []
SDDisconnect.restype = None

SDDisconnectAll = _lib.SDDisconnectAll
SDDisconnectAll.argtypes = []
SDDisconnectAll.restype = None

SDEndCommand = _lib.SDEndCommand
SDEndCommand.argtypes = []
SDEndCommand.restype = None

SDError = _lib.SDError
SDError.argtypes = []
SDError.restype = ctypes.c_char_p

SDEvalConv = _lib.SDEvalConv
SDEvalConv.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
SDEvalConv.restype = ctypes.c_char_p

SDEvaluate = _lib.SDEvaluate
SDEvaluate.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
SDEvaluate.restype = ctypes.c_char_p

SDExecute = _lib.SDExecute
SDExecute.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
SDExecute.restype = ctypes.c_char_p

SDExtract = _lib.SDExtract
SDExtract.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
SDExtract.restype = ctypes.c_char_p

SDField = _lib.SDField
SDField.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
SDField.restype = ctypes.c_char_p

SDFree = _lib.SDFree
SDFree.argtypes = [ctypes.c_void_p]
SDFree.restype = None

SDGetArg = _lib.SDGetArg
SDGetArg.argtypes = [ctypes.c_int]
SDGetArg.restype = ctypes.c_char_p

SDGetSession = _lib.SDGetSession
SDGetSession.argtypes = []
SDGetSession.restype = ctypes.c_int

SDGetVar = _lib.SDGetVar
SDGetVar.argtypes = [ctypes.c_char_p]
SDGetVar.restype = ctypes.c_char_p

SDIConv = _lib.SDIConv
SDIConv.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
SDIConv.restype = ctypes.c_char_p

SDIConvs = _lib.SDIConvs
SDIConvs.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
SDIConvs.restype = ctypes.c_char_p

SDIndices = _lib.SDIndices
SDIndices.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDIndices.restype = ctypes.c_char_p

SDIns = _lib.SDIns
SDIns.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_char_p]
SDIns.restype = ctypes.c_char_p

SDLocate = _lib.SDLocate
SDLocate.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_int), ctypes.c_char_p]
SDLocate.restype = ctypes.c_int

SDLogto = _lib.SDLogto
SDLogto.argtypes = [ctypes.c_char_p]
SDLogto.restype = ctypes.c_int

SDMarkMapping = _lib.SDMarkMapping
SDMarkMapping.argtypes = [ctypes.c_int, ctypes.c_int]
SDMarkMapping.restype = None

SDMatch = _lib.SDMatch
SDMatch.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
SDMatch.restype = ctypes.c_int

SDMatchfield = _lib.SDMatchfield
SDMatchfield.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
SDMatchfield.restype = ctypes.c_char_p

SDOConv = _lib.SDOConv
SDOConv.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
SDOConv.restype = ctypes.c_char_p

SDOConvs = _lib.SDOConvs
SDOConvs.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
SDOConvs.restype = ctypes.c_char_p

SDOpen = _lib.SDOpen
SDOpen.argtypes = [ctypes.c_char_p]
SDOpen.restype = ctypes.c_int

SDOpenSeq = _lib.SDOpenSeq
SDOpenSeq.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
SDOpenSeq.restype = ctypes.c_int

SDRead = _lib.SDRead
SDRead.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
SDRead.restype = ctypes.c_char_p

SDReadBlk = _lib.SDReadBlk
SDReadBlk.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
SDReadBlk.restype = ctypes.c_char_p

SDReadl = _lib.SDReadl
SDReadl.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
SDReadl.restype = ctypes.c_char_p

SDReadList = _lib.SDReadList
SDReadList.argtypes = [ctypes.c_int]
SDReadList.restype = ctypes.c_char_p

SDReadNext = _lib.SDReadNext
SDReadNext.argtypes = [ctypes.c_short]
SDReadNext.restype = ctypes.c_char_p

SDReadSeq = _lib.SDReadSeq
SDReadSeq.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
SDReadSeq.restype = ctypes.c_char_p

SDReadu = _lib.SDReadu
SDReadu.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
SDReadu.restype = ctypes.c_char_p

SDRecordlock = _lib.SDRecordlock
SDRecordlock.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
SDRecordlock.restype = None

SDRecordlocked = _lib.SDRecordlocked
SDRecordlocked.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDRecordlocked.restype = ctypes.c_int

SDRelease = _lib.SDRelease
SDRelease.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDRelease.restype = None

SDReplace = _lib.SDReplace
SDReplace.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_char_p]
SDReplace.restype = ctypes.c_char_p

SDRespond = _lib.SDRespond
SDRespond.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
SDRespond.restype = ctypes.c_char_p

SDRevision = _lib.SDRevision
SDRevision.argtypes = []
SDRevision.restype = ctypes.c_char_p

SDRTrans = _lib.SDRTrans
SDRTrans.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
SDRTrans.restype = ctypes.c_char_p

SDSeek = _lib.SDSeek
SDSeek.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
SDSeek.restype = None

SDSelect = _lib.SDSelect
SDSelect.argtypes = [ctypes.c_int, ctypes.c_int]
SDSelect.restype = None

SDSelectIndex = _lib.SDSelectIndex
SDSelectIndex.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
SDSelectIndex.restype = None

SDSelectLeft = _lib.SDSelectLeft
SDSelectLeft.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
SDSelectLeft.restype = ctypes.c_char_p

SDSelectRight = _lib.SDSelectRight
SDSelectRight.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
SDSelectRight.restype = ctypes.c_char_p

SDSetLeft = _lib.SDSetLeft
SDSetLeft.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDSetLeft.restype = None

SDSetRight = _lib.SDSetRight
SDSetRight.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDSetRight.restype = None

SDSetSession = _lib.SDSetSession
SDSetSession.argtypes = [ctypes.c_int]
SDSetSession.restype = ctypes.c_int

SDStatus = _lib.SDStatus
SDStatus.argtypes = []
SDStatus.restype = ctypes.c_int

SDSystem = _lib.SDSystem
SDSystem.argtypes = [ctypes.c_int]
SDSystem.restype = ctypes.c_char_p

SDTrans = _lib.SDTrans
SDTrans.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
SDTrans.restype = ctypes.c_char_p

SDTxn = _lib.SDTxn
SDTxn.argtypes = [ctypes.c_int]
SDTxn.restype = None

SDWeofSeq = _lib.SDWeofSeq
SDWeofSeq.argtypes = [ctypes.c_int]
SDWeofSeq.restype = None

SDWrite = _lib.SDWrite
SDWrite.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p]
SDWrite.restype = None

SDWriteBlk = _lib.SDWriteBlk
SDWriteBlk.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
SDWriteBlk.restype = None

SDWriteSeq = _lib.SDWriteSeq
SDWriteSeq.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDWriteSeq.restype = None

SDWriteSeqKey = _lib.SDWriteSeqKey
SDWriteSeqKey.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDWriteSeqKey.restype = ctypes.c_char_p

SDWriteu = _lib.SDWriteu
SDWriteu.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p]
SDWriteu.restype = None

SDWriteuSeqKey = _lib.SDWriteuSeqKey
SDWriteuSeqKey.argtypes = [ctypes.c_int, ctypes.c_char_p]
SDWriteuSeqKey.restype = ctypes.c_char_p

# CFUNCTYPE definitions for per-arity SDCall / SDCallx wrappers (sorted)
SDCall0_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short)
SDCall10_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall11_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall12_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall13_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall14_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall15_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall16_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall17_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall18_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall19_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall1_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p)
SDCall20_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall2_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p)
SDCall3_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall4_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall5_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall6_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall7_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall8_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCall9_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx0_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short)
SDCallx10_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx11_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx12_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx13_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx14_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx15_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx16_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx17_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx18_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx19_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx1_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p)
SDCallx20_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx2_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p)
SDCallx3_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx4_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx5_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx6_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx7_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx8_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
SDCallx9_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_short, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)
