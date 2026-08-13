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
   #define SDChange _SDChange
   #define SDClearSelect _SDClearSelect
   #define SDClose _SDClose
   #define SDConnect _SDConnect
   #define SDConnected _SDConnected
   #define SDConnectLocal _SDConnectLocal
   #define SDDisconnect _SDDisconnect
   #define SDDisconnectAll _SDDisconnectAll
   #define SDDcount _SDDcount
   #define SDDel _SDDel
   #define SDDelete _SDDelete
   #define SDDeleteu _SDDeleteu
   #define SDEndCommand _SDEndCommand
   #define SDError _SDError
   #define SDExecute _SDExecute
   #define SDExtract _SDExtract
   #define SDField _SDField
   #define SDFree _SDFree
   #define SDGetSession _SDGetSession
   #define SDIns _SDIns
   #define SDLocate _SDLocate
   #define SDMarkMapping _SDMarkMapping
   #define SDMatch _SDMatch
   #define SDMatchfield _SDMatchfield
   #define SDOpen _SDOpen
   #define SDRead _SDRead
   #define SDReadl _SDReadl
   #define SDReadList _SDReadList
   #define SDReadNext _SDReadNext
   #define SDReadu _SDReadu
   #define SDRelease _SDRelease
   #define SDReplace _SDReplace
   #define SDRespond _SDRespond
   #define SDSelect _SDSelect
   #define SDSelectIndex _SDSelectIndex
   #define SDSelectLeft _SDSelectLeft
   #define SDSelectRight _SDSelectRight
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
DLLEntry char * SDChange(char * src, char * old_string, char * new_string, int occurrences, int start);
DLLEntry void SDClearSelect(int listno);
DLLEntry void SDClose(int fno);
DLLEntry int SDConnect(char * host, int port, char * username, char * password, char * account);
DLLEntry int SDConnected(void);
DLLEntry int SDConnectLocal(char * account);
DLLEntry int SDDcount(char * src, char * delim_str);
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
DLLEntry void SDMarkMapping(int fno, int state);
DLLEntry int SDMatch(char * str, char * pattern);
DLLEntry char * SDMatchfield(char * str, char * pattern, int component);
DLLEntry int SDOpen(char * filename);
DLLEntry char * SDRead(int fno, char * id, int * err);
DLLEntry char * SDReadl(int fno, char * id, int wait, int * err);
DLLEntry char * SDReadList(int listno);
DLLEntry char * SDReadNext(short int listno);
DLLEntry char * SDReadu(int fno, char * id, int wait, int * err);
DLLEntry void SDRelease(int fno, char * id);
DLLEntry char * SDReplace(char * src, int fno, int vno, int svno, char * new_string);
DLLEntry char * SDRespond(char * response, int * err);
DLLEntry void SDSelect(int fno, int listno);
DLLEntry void SDSelectIndex(int fno, char * indexname, char * indexvalue, int listno);
DLLEntry char * SDSelectLeft(int fno, char * indexname, int listno);
DLLEntry char * SDSelectRight(int fno, char * indexname, int listno);
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

/* END-CODE */
