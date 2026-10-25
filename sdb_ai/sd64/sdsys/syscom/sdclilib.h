/* sdclilib.h
 * SD client C API library functions and tokens.
 * Copyright (c) 2004 Ladybridge Systems, All Rights Reserved
 */

/* Function definitions */

#ifdef __BORLANDC__
   /* Borland C compiler for Windows users */
   #define DLLEntry __declspec(dllimport)
#endif

#ifdef _MSC_VER
   /* Microsoft C compiler for Windows users */
   #define DLLEntry __declspec(dllimport)

   #define SDCall _SDCall
   #define SDCallx _SDCallx
   #define SDChange _SDChange
   #define SDChecksum _SDChecksum
   #define SDClearSelect _SDClearSelect
   #define SDClose _SDClose
   #define SDConnect _SDConnect
   #define SDConnected _SDConnected
   #define SDConnectLocal _SDConnectLocal
   #define SDDisconnect _SDDisconnect
   #define SDDisconnectAll _SDDisconnectAll
   #define SDDcount _SDDcount
   #define SDDebug _SDDebug
   #define SDDel _SDDel
   #define SDDelete _SDDelete
   #define SDDeleteu _SDDeleteu
   #define SDEndCommand _SDEndCommand
   #define SDError _SDError
   #define SDExecute _SDExecute
   #define SDExtract _SDExtract
   #define SDField _SDField
   #define SDFree _SDFree
   #define SDGetArg _SDGetArg
   #define SDGetSession _SDGetSession
   #define SDIns _SDIns
   #define SDLocate _SDLocate
   #define SDLogto _SDLogto
   #define SDMarkMapping _SDMarkMapping
   #define SDMatch _SDMatch
   #define SDMatchfield _SDMatchfield
   #define SDOpen _SDOpen
   #define SDRead _SDRead
   #define SDReadl _SDReadl
   #define SDReadList _SDReadList
   #define SDReadNext _SDReadNext
   #define SDReadu _SDReadu
   #define SDRecordlock _SDRecordlock
   #define SDRecordlocked _SDRecordlocked
   #define SDRelease _SDRelease
   #define SDReplace _SDReplace
   #define SDRespond _SDRespond
   #define SDSelect _SDSelect
   #define SDSelectIndex _SDSelectIndex
   #define SDSelectLeft _SDSelectLeft
   #define SDSelectRight _SDSelectRight
   #define SDGetVar _SDGetVar
   #define SDIndices _SDIndices
   #define SDRevision _SDRevision
   #define SDRTrans _SDRTrans
   #define SDSystem _SDSystem
   #define SDTrans _SDTrans
   #define SDTxn _SDTxn
   #define SDEvaluate _SDEvaluate
   #define SDEvalConv _SDEvalConv
   #define SDIConv _SDIConv
   #define SDOConv _SDOConv
   #define SDIConvs _SDIConvs
   #define SDOConvs _SDOConvs
   #define SDOpenSeq _SDOpenSeq
   #define SDReadSeq _SDReadSeq
   #define SDReadBlk _SDReadBlk
   #define SDWriteSeq _SDWriteSeq
   #define SDWriteBlk _SDWriteBlk
   #define SDSeek _SDSeek
   #define SDWeofSeq _SDWeofSeq
   #define SDWriteSeqKey _SDWriteSeqKey
   #define SDWriteuSeqKey _SDWriteuSeqKey
   #define SDSetLeft _SDSetLeft
   #define SDSetRight _SDSetRight
   #define SDSetSession _SDSetSession
   #define SDStatus _SDStatus
   #define SDWrite _SDWrite
   #define SDWriteu _SDWriteu
#endif

#ifndef DLLEntry
   /* Other platforms */
   #define DLLEntry
#endif

DLLEntry void SDCall(char * subrname, short int argc, ...);
DLLEntry void SDCallx(char * subrname, short int argc, ...);
DLLEntry char * SDGetArg(int arg_number);
DLLEntry char * SDChange(char * src, char * old_string, char * new_string, int occurrences, int start);
DLLEntry int SDChecksum(char * data);
DLLEntry void SDClearSelect(int listno);
DLLEntry void SDClose(int fno);
DLLEntry int SDConnect(char * host, int port, char * username, char * password, char * account);
DLLEntry int SDConnected(void);
DLLEntry int SDConnectLocal(char * account);
DLLEntry int SDDcount(char * src, char * delim_str);
DLLEntry void SDDebug(short int mode);
DLLEntry char * SDDel(char * src, int fno, int vno, int svno);
DLLEntry void SDDelete(int fno, char * id);
DLLEntry void SDDeleteu(int fno, char * id);
DLLEntry void SDDisconnect(void);
DLLEntry void SDDisconnectAll(void);
DLLEntry void SDEndCommand(void);
DLLEntry char * SDError(void);
DLLEntry char * SDExecute(char * cmnd, int * err);
DLLEntry char * SDExtract(char * src, int fno, int vno, int svno);
DLLEntry char * SDField(char * src, char * delim, int first, int occurrences);
DLLEntry void SDFree(void * p);
DLLEntry int SDGetSession(void);
DLLEntry char * SDIns(char * src, int fno, int vno, int svno, char * new_string);
DLLEntry int SDLocate(char * item, char * src, int fno, int vno, int svno, int * pos, char * order);
DLLEntry int SDLogto(char * account_name);
DLLEntry void SDMarkMapping(int fno, int state);
DLLEntry int SDMatch(char * str, char * pattern);
DLLEntry char * SDMatchfield(char * str, char * pattern, int component);
DLLEntry int SDOpen(char * filename);
DLLEntry char * SDRead(int fno, char * id, int * err);
DLLEntry char * SDReadl(int fno, char * id, int wait, int * err);
DLLEntry char * SDReadList(int listno);
DLLEntry char * SDReadNext(short int listno);
DLLEntry char * SDReadu(int fno, char * id, int wait, int * err);
DLLEntry void SDRecordlock(int fno, char * id, int update_lock, int wait);
DLLEntry int SDRecordlocked(int fno, char * id);
DLLEntry void SDRelease(int fno, char * id);
DLLEntry char * SDReplace(char * src, int fno, int vno, int svno, char * new_string);
DLLEntry char * SDRespond(char * response, int * err);
DLLEntry void SDSelect(int fno, int listno);
DLLEntry void SDSelectIndex(int fno, char * indexname, char * indexvalue, int listno);
DLLEntry char * SDSelectLeft(int fno, char * indexname, int listno);
DLLEntry char * SDSelectRight(int fno, char * indexname, int listno);
DLLEntry char * SDGetVar(char * name);
DLLEntry char * SDIndices(int fno, char * indexname);
DLLEntry char * SDRevision(void);
DLLEntry char * SDRTrans(char * filename, char * id, char * fieldname, char * action);
DLLEntry char * SDSystem(int key);
DLLEntry char * SDTrans(char * filename, char * id, char * fieldname, char * action);
DLLEntry void SDTxn(int mode);
DLLEntry char * SDEvaluate(int fno, char * name, char * data, char * id);
DLLEntry char * SDEvalConv(int fno, char * name, char * data, char * id);
DLLEntry char * SDIConv(char * data, char * code);
DLLEntry char * SDOConv(char * data, char * code);
DLLEntry char * SDIConvs(char * data, char * code);
DLLEntry char * SDOConvs(char * data, char * code);
DLLEntry int SDOpenSeq(char * filename, char * id, int modes);
DLLEntry char * SDReadSeq(int fno, int * err);
DLLEntry char * SDReadBlk(int fno, int bytes, int * actual);
DLLEntry void SDWriteSeq(int fno, char * rec);
DLLEntry void SDWriteBlk(int fno, char * rec, int bytes);
DLLEntry void SDSeek(int fno, int offset, int relto);
DLLEntry void SDWeofSeq(int fno);
DLLEntry char * SDWriteSeqKey(int fno, char * rec);
DLLEntry char * SDWriteuSeqKey(int fno, char * rec);
DLLEntry void SDSetLeft(int fno, char * indexname);
DLLEntry void SDSetRight(int fno, char * indexname);
DLLEntry int SDSetSession(int session);
DLLEntry int SDStatus(void);
DLLEntry void SDWrite(int fno, char * id, char * data);
DLLEntry void SDWriteu(int fno, char * id, char * data);


/* Server error status values */

#define SV_OK             0    /* Action successful                       */
#define SV_ON_ERROR       1    /* Action took ON ERROR clause             */
#define SV_ELSE           2    /* Action took ELSE clause                 */
#define SV_ERROR          3    /* Action failed. Error text available     */
#define SV_LOCKED         4    /* Action took LOCKED clause               */
#define SV_PROMPT         5    /* Server requesting input                 */
/* 15 Aug 26 Windows port - from sdb64 dev (1.0-3), numbering and all.  The C
   client already distinguished these two states and this header did not, so
   BASIC could not tell a transport failure from a context error.  sdb64's
   values are the shared ones; winsdclilib had them transposed and the vendored
   copy is corrected to match - PROJECT_STATUS.md 5.3.                       */
#define SV_EMSG_PAIR      6    /* Server message_pair error               */
#define SV_ECONTXT        7    /* Server context_error                    */

/* END-CODE */
