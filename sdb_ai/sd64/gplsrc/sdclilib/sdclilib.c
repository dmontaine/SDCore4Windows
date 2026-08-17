/* winSDclilib.c
 * based on: QMCLILIB.C
 * QM Client C library
 * Copyright (c) 2007 Ladybridge Systems, All Rights Reserved
 *
 * Licensed under the terms of any of the following licenses at your
 * choice:
 *
 *  - GNU General Public License Version 2 or later (the "GPL")
 *    http://www.gnu.org/licenses/gpl.html
 *
 *  - GNU Lesser General Public License Version 2.1 or later (the "LGPL")
 *    http://www.gnu.org/licenses/lgpl.html
 *
 * Ladybridge Systems can be contacted via the www.openqm.com web site.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 * Linking exception:
 *
 * As a special exception, the copyright holders of this library give you
 * permission to link this library with independent modules to produce an
 * executable, regardless of the license terms of these independent modules,
 * and to copy and distribute the resulting executable under terms of your
 * choice, provided that you also meet, for each linked independent module,
 * the terms and conditions of the license of that module. An independent
 * module is a module which is not derived from or based on this library. If
 * you modify this library, you may extend this exception to your version of
 * the library, but you are not obligated to do so. If you do not wish to do
 * so, delete this exception statement from your version.
 *
 * START-HISTORY:
 * 31 Dec 23 SD launch - prior history suppressed 
 * START-HISTORY (winSDclilib):
 * xxDec23 mab add more functions, at this build we now include:
 * SDCallx
 * SDClose
 * SDConnect
 * SDConnected
 * SDDcount
 * SDDebug
 * SDDisconnect
 * SDDisconnectAll
 * SDError
 * SDExecute
 * SDExtract
 * SDFree
 * SDGetArg
 * SDGetSession
 * SDIns
 * SDLocate
 * SDOpen
 * SDRead
 * SDReadl
 * SDReadu
 * SDRecordlock
 * SDRelease
 * SDReplace
 * SDSetSession
 * SDStatus
 * SDWrite
 * SDWriteu
 * 20240301 mab attempt windows port, using Visual Studio 2022
 * This port is not intended to be a complete port of sdclilib.c, at this time only porting functions that I currently need.
 * Also will probably not include the call function, but instead the Callx / Getarg functions of newer client versions.
 * Warning: winSDclilib does not maintian a storage area for Getarg parameters for each session.
 *  Using Callx will "overwrite" the previous Callx parameters regardless of session number.
 *  A solution would be to add the return call buffers to the session structure....
 *    Or size the pointer array CallArgArray to have a slot for the max number of call args * the max number of sessions
 *    char *    CallArgArray[MAX_ARGS*MAX_SESSIONS]
 *    Then use session_idx*MAX_ARGS as the offset into CallArgArray for the sessions SDCall arguments
 * Notes: There seems to be an issue with char vs unsigned char when using the memchr c function (void *memchr(const void *str, int c, size_t n).
 *   If passing the int c parameter as a char, characters > 127 cannot be found (interpreted as a neg integer?).
 *   The gcc compiler & linux runtime seems to be fine with it
 *     not so with C++ BUilder / Windows. Need to use unsigned Char.
 *   I cannot find where the transfer buffer "buff" is freed, need to test for memory leak to see if this is really the case.
 *     For now I have added code to disconnect() to free buff if there are no more remaining active connections.
 *   Note use of:
 *  #define _CRT_SECURE_NO_WARNINGS
 *  #define _WINSOCK_DEPRECATED_NO_WARNINGS
 *   Need to revisit and update code to remove the need for these compilier switches
 *
 *   Rem "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.38.33130\bin\Hostx64\x86\dumpbin.exe" /exports winSDclilib.dll
 *   To get listing of functions
 *
 * 20240305 mab add balance of functions to msvc port
 * 20260805 align write-size validation and error-response semantics with the
 * Linux client; remove unreachable Windows named-pipe transport code; add
 * client context and message-pair status values.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *
 *
 * Session Management
 * ==================
 * SDConnect()
 * SDConnected()
 * SDDisconnect()
 * SDDisconnectAll()
 * SDGetSession()
 * SDSetSession()
 * SDLogto()
 * 
 * 
 * File Handling
 * =============
 * SDOpen()
 * SDClose()
 * SDRead()
 * SDReadl()
 * SDReadu()
 * SDWrite()
 * SDWriteu()
 * SDDelete()
 * SDDeleteu()
 * SDRelease()
 * SDSelect()
 * SDSelectIndex()
 * SDSelectLeft()
 * SDSelectRight()
 * SDSetLeft()
 * SDSetRight()
 * SDReadNext()
 * SDClearSelect()
 * SDRecordlock()
 * SDMarkMapping()
 *
 *
 * Dynamic Array Handling
 * ======================
 * SDExtract()
 * SDReplace()
 * SDIns()
 * SDDel()
 * SDLocate()
 *
 *
 * String Handling
 * ===============
 * SDChange()
 * SDDcount()
 * SDField()
 * SDMatch()
 * SDMatchfield()
 * SDFree()
 *
 * Command Execution
 * =================
 * SDExecute()
 * SDRespond()
 * SDEndCommand()
 *
 * Subroutine Execution
 * ====================
 * SDCall()
 *
 *
 * Error Handling
 * ==============
 * SDError()
 * SDStatus()
 *
 *
 * Internal
 * ========
 * SDDebug()
 * SDEnterPackage()
 * SDExitPackage()
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#define _WINSOCK_DEPRECATED_NO_WARNINGS
#endif



#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h> /* toupper() in sysdir() */
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
/* next 3 for windows? */
#include <io.h>
#include <winsock2.h>
/* Must follow winsock2.h, which would otherwise be pre-empted by the winsock
   1.1 declarations that windows.h pulls in.  Needed for the named pipe and
   process creation calls used by SDConnectLocal().                          */
#include <windows.h>
#include <stdint.h>
#include <stdalign.h>
/* need this lib for linking socket library */
#pragma comment(lib, "Ws2_32.lib")

/* define the @#!$ BSD style int types */
typedef uint32_t u_int32_t;

#define Public
/* #include "sddefs.h" */
/* following pulled from sddefs.h at least for now
	there is a bunch of stuff in sddefs.h that will not resolve with c++ builder
	some of the int defines, bigended stuff
*/
#define Private static

#define MAX_PATHNAME_LEN 255    /* Changes affect file headers */
#define MAX_ID_LEN 255          /* Increasing requires major file changes */
#define MAX_CALL_NAME_LEN 63    /* Cannot exceed MAX_ID_LEN */
#define MAX_TRIGGER_NAME_LEN 32 /* Increasing would alter file header */
#define MAX_PROGRAM_NAME_LEN 128
#define MAX_USERNAME_LEN 32
#define MAX_MATCH_TEMPLATE_LEN 256
#define MAX_MATCHED_STRING_LEN 8192
#define MAX_STRING_SIZE 1073741822
#define MAX_PACKAGES 32
#define MAX_PACKAGE_NAME_LEN 15
#define MAX_ACCOUNT_NAME_LEN 32
#define MAX_SORTMRG 10
#define MAX_SORT_KEYS 32
#define MAX_SORT_KEY_LEN 1024


 typedef int16_t bool;
#define FALSE 0
#define TRUE 1

#define ShortInt(n) (n)
#define LongInt(n) (n)


/* ======================================================================
   Case conversion macros and data                                        */
typedef unsigned char u_char;    /* u_char is a  BSD type ?? */
Public char uc_chars[256];
Public char lc_chars[256];
#define UpperCase(c) (uc_chars[((u_char)(c))])
#define LowerCase(c) (lc_chars[((u_char)(c))])
Public u_char char_types[256];
#define CT_ALPHA 0x01
#define CT_DIGIT 0x02
#define CT_GRAPH 0x04
#define CT_MARK 0x08
#define CT_DELIM 0x10
#define IsAlnum(c) (char_types[((u_char)(c))] & (CT_ALPHA | CT_DIGIT))
#define IsAlpha(c) (char_types[((u_char)(c))] & CT_ALPHA)
#define IsDigit(c) (char_types[((u_char)(c))] & CT_DIGIT)
#define IsGraph(c) (char_types[((u_char)(c))] & CT_GRAPH)
#define IsDelim(c) (char_types[((u_char)(c))] & CT_DELIM)
#define IsMark(c) (char_types[((u_char)(c))] & CT_MARK)

/*
  these do not work the same as gcc,
  you end up with the interger value of the neg number, ie
  #define TEXT_MARK ((char)-5)
  resolves as -5

  #define SUBVALUE_MARK ((char)-4)
  #define VALUE_MARK ((char)-3)
  #define FIELD_MARK ((char)-2)
  #define ITEM_MARK ((char)-1)

  */
#define U_TEXT_MARK ((u_char)'\xFB')
#define U_SUBVALUE_MARK ((u_char)'\xFC')
#define U_VALUE_MARK ((u_char)'\xFD')
#define U_FIELD_MARK ((u_char)'\xFE')
#define U_ITEM_MARK ((u_char)'\xFF')

/* end of sddefs.h lazyness  */

/* #include "sdnet.h"   do not include until i know why */

void set_default_character_maps(void);

/* include <sys/wait.h> not on windows*/
/* #include "linuxlb.h" not on windows*/
/* removed, call net_error directly #define NetErr(msg, winerr, lnxerr) net_error(msg, lnxerr) */

#define DLLEntry  __declspec(dllexport)

#define FOPEN_READ_MODE "r"

#include "err.h"
#include "revstamp.h"
#include "sdclient.h"
/* Include the public header so the compiler verifies every exported
   definition below matches its declared prototype (SV_* macros here are
   identical to those in sdclient.h, so the redefinition is benign). */
#include "sdclilib.h"

DLLEntry char* SDError(void);

/* Network data */
Private bool OpenSocket(char* host, int16_t port);
Private bool CloseSocket(void);
Private bool read_packet(void);
Private bool write_packet(int type, char* data, int32_t bytes);
Private bool send_all(SOCKET sock, const char* data, int32_t bytes);
Private void abandon_connection(void);
Private void net_error(char* prefix);
Private void debug(unsigned char* p, int n);
Private void initialise_client(void);
Private bool FindFreeSession(void);
Private void disconnect(void);
Private int32_t grow_buffer_size(int32_t needed);
Private bool valid_packet_length(int32_t packet_length);
Private bool read_arg_record(const char* buf, int32_t buf_bytes, int offset,
                             int16_t* argno, const char** arg_text,
                             int32_t* arg_len, int* next_offset);
Private bool valid_record_size(size_t bytes);
/* Local (named pipe) transport - see SDConnectLocal() */
Private char* sysdir(void);
Private int transport_recv(char* p, int len);
Private bool transport_send(const char* data, int32_t bytes);
Private bool transport_live(void);
Private void transport_error(char* prefix);

typedef struct ARGDATA ARGDATA;

#pragma pack(2)
struct ARGDATA {
  int16_t argno;
  int32_t arglen;
  char text[1];
};
#pragma pack()

/* Packet buffer */
#define BUFF_INCR 4096
/* Upper bound on a single response packet. Guards against a rogue or
   version-mismatched server, protocol desync, and signed overflow in the
   buffer-size rounding. Generous for record data, well under INT32_MAX. */
#define SD_MAX_PACKET_BYTES (256 * 1024 * 1024)
/* Size of the fixed response-packet header: length(4) + error(2) + status(4). */
#define IN_PKT_HDR_BYTES 10
typedef struct INBUFF INBUFF;

#pragma pack(2)
struct INBUFF {
    union {
        struct {
            char message[1];
        } abort;
        struct { /* SDCall returned arguments */
            struct ARGDATA argdata;
        } call;
        struct { /* Error text retrieval */
            char text[1];
        } error;
        struct { /* SDExecute */
            char reply[1];
        } execute;
        struct { /* SDOpen */
            int16_t fno;
        } open;
        struct { /* SDRead, SDReadl, SDReadu */
            char rec[1];
        } read;
        struct { /* SDReadList */
            char list[1];
        } readlist;
        struct { /* SDReadNext */
            char id[1];
        } readnext;
        struct { /* SDSelectLeft, SDSelectRight */
            char key[1];
        } selectleft;
    } data;
};
#pragma pack()

Private INBUFF* buff = NULL;
Private int32_t buff_size;  /* Allocated size of buffer */
Private int32_t buff_bytes; /* Size of received packet */
Private FILE* srvr_debug = NULL;

/* buffers for Callx return arguments  */
#define MAX_ARGS 20
Private char *    CallArgArray[MAX_ARGS];          /* create an array of pointers, for string arguments (returned by Callx) not sure if this is correct */
Private int       CallArgArraySz[MAX_ARGS];        /* and size of memory allocated for each  string length + terminator */

#define MAX_SESSIONS 4
Private struct {
  bool winsock_started;
  int16_t context;
#define CX_DISCONNECTED 0 /* No session active */
#define CX_CONNECTED 1    /* Session active but not... */
#define CX_EXECUTING 2    /* ...executing command (implies connected) */
  char sderror[512 + 1];
  int16_t server_error;
  int32_t sd_status;
  SOCKET sock;
  /* A local session talks to an SD process on this machine over a named pipe
     instead of a socket.  Exactly one of sock / hPipe is live at a time. */
  HANDLE hPipe;
  bool is_local;
} session[MAX_SESSIONS];

Private int16_t session_idx = 0;

/* Matching data */
Private char* component_start;
Private char* component_end;

/* Internally used routines */
/*
DLLEntry  void  SDDisconnect(void);
DLLEntry  void  SDEndCommand(void);
*/

/* Internal functions */

Private char* SelectLeftRight(int16_t fno,
                              char* index_name,
                              int16_t listno,
                              int16_t mode);
Private void SetLeftRight(int16_t fno, char* index_name, int16_t mode);
Private bool context_error(int16_t expected);
Private void delete_record(int16_t mode, int fno, char* id); 

Private char* read_record(int fno, char* id, int* err, int mode);
Private void write_record(int16_t mode, int16_t fno, char* id, char* data);
Private bool GetResponse(void);
Private void Abort(char* msg, bool use_response);
Private char* memstr(char* str, char* substr, int str_len, int substr_len);  
Private bool match_template(char* string,
							char* template,
							int16_t component,
							int16_t return_component);  

Private bool message_pair(int type, char* data, int32_t bytes);
Private char* NullString(void);

#define ClearError session[session_idx].sderror[0] = '\0'

/* ======================================================================
   grow_buffer_size()  -  Round a required byte count up to the next BUFF_INCR
   multiple strictly greater than it. Used for every network-buffer
   (re)allocation so the historical rounding-mask bug cannot recur and so
   there is always room for read_packet()'s trailing NUL.                    */
Private int32_t grow_buffer_size(int32_t needed) {
    return (needed + BUFF_INCR) & ~(BUFF_INCR - 1);
}

/* ======================================================================
   valid_packet_length()  -  Accept only a server-declared packet length that
   covers the fixed header and stays within SD_MAX_PACKET_BYTES.            */
Private bool valid_packet_length(int32_t packet_length) {
    return (packet_length >= IN_PKT_HDR_BYTES) &&
           (packet_length <= SD_MAX_PACKET_BYTES);
}

/* ======================================================================
   read_arg_record()  -  Bounds-checked read of one ARGDATA record from a
   received CALL response. On success fills the out-params and advances
   *next_offset past the padded record; returns FALSE if the fixed header
   would read past the packet, the length is negative, or the argument text
   would run past the packet.                                                */
Private bool read_arg_record(const char* buf, int32_t buf_bytes, int offset,
                             int16_t* argno, const char** arg_text,
                             int32_t* arg_len, int* next_offset) {
    const struct ARGDATA* rec;
    int32_t len;
    int hdr = (int)offsetof(ARGDATA, text);
    if ((offset < 0) || (offset > buf_bytes - hdr))
        return FALSE;
    rec = (const struct ARGDATA*)(buf + offset);
    len = LongInt(rec->arglen);
    if ((len < 0) || (len > buf_bytes - offset - hdr))
        return FALSE;
    *argno = ShortInt(rec->argno);
    *arg_text = rec->text;
    *arg_len = len;
    /* Advance past the padded record. A well-formed server pads every argument
       to an even length; tolerate a missing final pad byte by clamping so
       *next_offset can never point past the packet. */
    *next_offset = offset + hdr + ((len + 1) & ~1);
    if (*next_offset > buf_bytes)
        *next_offset = buf_bytes;
    return TRUE;
}

/* ======================================================================
   SDCall()  - Callx catalogued subroutine
   Note, this version does NOT repopulate the returned values of the SDCallx calling arguments, you must use SDGetArg to retrive them */
DLLEntry void SDCallx(char* subrname, int16_t argc, ...) {
  va_list ap;    /* variable arg list, see man va_list */
  int16_t i;
  char* arg;
  char* arg_p;   /* pointer to memory for coping arg string*/
  int subrname_len;
  int32_t arg_len;
  int32_t bytes; /* Total length of outgoing packet */
  int32_t n;
  char* p;
  INBUFF* q;
  int offset;

  if (context_error(CX_CONNECTED))
    return;
  subrname_len = strlen(subrname);
  if ((subrname_len < 1) || (subrname_len > MAX_CALL_NAME_LEN)) {
    Abort("Illegal subroutine name in call", FALSE);
    return;
  }
  if ((argc < 0) || (argc > MAX_ARGS)) {
    Abort("Illegal argument count in call", FALSE);
    return;
  }
 /* free up any memory allocated for prev callx arg strorage */
  for (i = 0; i < MAX_ARGS; i++) {
	if (CallArgArray[i] != NULL ){
	 free(CallArgArray[i]);
	 CallArgArray[i] = NULL;
	 CallArgArraySz[i] = 0;
	}
  }
  /* Accumulate outgoing packet size */
  bytes = 2;                        /* Subrname length */
  bytes += (subrname_len + 1) & ~1; /* Subrname string (padded) */
  bytes += 2;                       /* Arg count */
  va_start(ap, argc);
  for (i = 0; i < argc; i++) {
    arg = va_arg(ap, char*);
    arg_len = (arg == NULL) ? 0 : strlen(arg);
    bytes +=
        4 + ((arg_len + 1) & ~1); /* Four byte length + arg text (padded) */
  }
  va_end(ap);
  /* Ensure buffer is big enough */
  if (bytes >= buff_size) /* Must reallocate larger buffer */
  {
    n = grow_buffer_size(bytes);
    q = (INBUFF*)malloc(n);
    if (q == NULL) {
      Abort("Unable to allocate network buffer", FALSE);
      return;
    }
    free(buff);
    buff = q;
    buff_size = n;
  }
  /* Set up outgoing packet */
  p = (char*)buff;
  *((int16_t*)p) = ShortInt(subrname_len); /* Subrname length */
  p += 2;
  memcpy(p, subrname, subrname_len); /* Subrname */
  p += (subrname_len + 1) & ~1;
  *((int16_t*)p) = ShortInt(argc); /* Arg count */
  p += 2;
 /* we do 2 things in this block, move callx args to the send buffer    */
 /* and save a copy pointed to by  CallArgArray[i]   for use by GetArg  */
  va_start(ap, argc);
  for (i = 1; i <= argc; i++) {
  /* first move arg to io buffer  */
    arg = va_arg(ap, char*);
    arg_len = (arg == NULL) ? 0 : strlen(arg);
    *((int32_t*)p) = LongInt(arg_len); /* Arg length */
    p += 4;
    if (arg_len)
      memcpy(p, arg, arg_len); /* Arg text */
	p += (arg_len + 1) & ~1;
  /* now save a copy                    */
	arg_p = (char *)malloc((arg_len+1) * sizeof(char));   /* reserver mem for string and terminator */
	/* if we fail to allocate memory, bomb out */
	if (arg_p == NULL) {
	   Abort("Unable to allocate Callx buffer", FALSE);
	} else {
   /* save ponter to allocated memory */
	  CallArgArray[i-1] = arg_p;
	  CallArgArraySz[i-1] = arg_len + 1;  /* along with the buffer size (string sz + terminator)    */
	  if (arg_len == 0) {
		*arg_p = '\0';
	  } else {
   /* copy arg to allocated memory, we are assuming arg is '\0' terminated, probably should check on this */
		strcpy_s(arg_p, arg_len + 1,arg);
	  }
	}
  }
  va_end(ap);
  if (!message_pair(SrvrCall, (char*)buff, bytes)) {
    goto err;
  }
  /* Now update CallArgArray with any returned arguments */
  offset = offsetof(INBUFF, data.call.argdata);
  if (offset < buff_bytes) {
    va_start(ap, argc);
    for (i = 1; i <= argc; i++) {
      int16_t rec_argno;
      const char* rec_text;
      int next;
      if (!read_arg_record((char*)buff, buff_bytes, offset,
                           &rec_argno, &rec_text, &arg_len, &next))
        break;
      arg = va_arg(ap, char*);
      if (i == rec_argno) {
        /* check CallArgArray buffer is large enough for returned value */
        if (CallArgArraySz[i-1] < arg_len + 1) {
          if (CallArgArray[i-1] != NULL)
            free(CallArgArray[i-1]);
          CallArgArray[i-1] = malloc((arg_len + 1) * sizeof(char));
          if (CallArgArray[i-1] != NULL) {
            CallArgArraySz[i-1] = (arg_len + 1) * sizeof(char);
            memcpy(CallArgArray[i-1], rec_text, arg_len);
            CallArgArray[i-1][arg_len] = '\0';
          } else {
            Abort("Unable to allocate Callx buffer on return", FALSE);
          }
        } else {
          memcpy(CallArgArray[i-1], rec_text, arg_len);
          CallArgArray[i-1][arg_len] = '\0';
        }
        offset = next;
        if (offset >= buff_bytes)
          break;
      }
    }
    va_end(ap);
  }
err:
  switch (session[session_idx].server_error) {
    case SV_OK:
      break;
    case SV_ON_ERROR:
      Abort("CALL generated an abort event", TRUE);
      break;
    case SV_LOCKED:
    case SV_ELSE:
    case SV_ERROR:
      break;
  }
}
/* ======================================================================
   SDGetArg() Get called subroutine return argument
*/
DLLEntry char* SDGetArg(int ArgNbr) {
  int arg_idx;
  int arg_len;
  char* arg;
  if ((ArgNbr < 1) || (ArgNbr > MAX_ARGS)) {
	Abort("Illegal argument index in call", TRUE);
    return NULL;
  }
  arg_idx = ArgNbr - 1;
  if ((CallArgArray[arg_idx] == NULL)) {
	Abort("Argument value NULL", TRUE);
    return NULL;
  }
  arg_len = strlen(CallArgArray[arg_idx]);
  arg = (char *)malloc((arg_len+1) * sizeof(char));   /* reserver mem for string and terminator */
  /* if we fail to allocate memory, bomb out */
  if (arg == NULL) {
	Abort("GetgArg Memory Allocation Failed", TRUE);
    return NULL;
  }
  memcpy(arg, CallArgArray[arg_idx], arg_len + 1);
  return arg;
}

/* ======================================================================
   SDCall() - Call a catalogued subroutine and update returned arguments. */
DLLEntry void SDCall(char* subrname, int16_t argc, ...) {
  va_list ap;
  int16_t i;
  char* arg;
  int subrname_len;
  int32_t arg_len;
  int32_t bytes;
  int32_t n;
  char* p;
  INBUFF* q;
  int offset;

  if (context_error(CX_CONNECTED))
    return;
  subrname_len = (int)strlen(subrname);
  if ((subrname_len < 1) || (subrname_len > MAX_CALL_NAME_LEN)) {
    Abort("Illegal subroutine name in call", FALSE);
    return;
  }
  if ((argc < 0) || (argc > MAX_ARGS)) {
    Abort("Illegal argument count in call", FALSE);
    return;
  }

  bytes = 2 + ((subrname_len + 1) & ~1) + 2;
  va_start(ap, argc);
  for (i = 0; i < argc; i++) {
    arg = va_arg(ap, char*);
    arg_len = (arg == NULL) ? 0 : (int32_t)strlen(arg);
    bytes += 4 + ((arg_len + 1) & ~1);
  }
  va_end(ap);

  if (bytes >= buff_size) {
    n = grow_buffer_size(bytes);
    q = (INBUFF*)malloc(n);
    if (q == NULL) {
      Abort("Unable to allocate network buffer", FALSE);
      return;
    }
    free(buff);
    buff = q;
    buff_size = n;
  }

  p = (char*)buff;
  *((int16_t*)p) = ShortInt(subrname_len);
  p += 2;
  memcpy(p, subrname, subrname_len);
  p += (subrname_len + 1) & ~1;
  *((int16_t*)p) = ShortInt(argc);
  p += 2;
  va_start(ap, argc);
  for (i = 0; i < argc; i++) {
    arg = va_arg(ap, char*);
    arg_len = (arg == NULL) ? 0 : (int32_t)strlen(arg);
    *((int32_t*)p) = LongInt(arg_len);
    p += 4;
    if (arg_len)
      memcpy(p, arg, arg_len);
    p += (arg_len + 1) & ~1;
  }
  va_end(ap);

  if (!message_pair(SrvrCall, (char*)buff, bytes))
    goto call_done;

  offset = (int)offsetof(INBUFF, data.call.argdata);
  if (offset < buff_bytes) {
    va_start(ap, argc);
    for (i = 1; i <= argc; i++) {
      int16_t rec_argno;
      const char* rec_text;
      int32_t rec_len;
      int next;
      if (!read_arg_record((char*)buff, buff_bytes, offset,
                           &rec_argno, &rec_text, &rec_len, &next))
        break;
      arg = va_arg(ap, char*);
      if (i == rec_argno) {
        if (arg != NULL) {
          memcpy(arg, rec_text, rec_len);
          arg[rec_len] = '\0';
        }
        offset = next;
        if (offset >= buff_bytes)
          break;
      }
    }
    va_end(ap);
  }

call_done:
  if (session[session_idx].server_error == SV_ON_ERROR)
    Abort("CALL generated an abort event", TRUE);
}

/* ======================================================================
   SDChange()  -  Change substrings                                       */

DLLEntry char* SDChange(char* src, char* old, char* new, int occurrences, int start) {
    int src_len;
    int old_len;
    int new_len;
    int32_t bytes; /* Remaining bytes counter */
    char* start_pos;
    char* new_str;
    int32_t changes;
    char* pos;
    char* p;
    char* q;
    int32_t n;

    initialise_client();

    src_len = strlen(src);
    old_len = strlen(old);
    new_len = strlen(new);

    if (src_len == 0) {
        new_str = NullString();
        return new_str;
    }

    if (old_len == 0)
        goto return_unchanged;

    if (occurrences < 1)
        occurrences = -1;
    if (start < 1)
        start = 1;

    /* Count occurences of old string in source string, remembering start of
      region to change.                                                     */

    changes = 0;
    bytes = src_len;
    pos = src;
    start_pos = pos;   /* get rid of potentially uninitialized compile error */
    while (bytes > 0) {
        p = memstr(pos, old, bytes, old_len);
        if (p == NULL)
            break;

        if (--start <= 0) {
            if (start == 0)
                start_pos = p; /* This is the first one to replace */

            changes++;

            if (--occurrences == 0)
                break; /* This was the last one to replace */
        }

        bytes -= (p - pos) + old_len;
        pos = p + old_len;
    }

    if (changes == 0)
        goto return_unchanged;

    /* Now make the changes */

    new_str = (char*)malloc(src_len + changes * (new_len - old_len) + 1);

    q = new_str;
    pos = src;
    bytes = src_len;
    p = start_pos;
    do {
        /* Copy intermediate text */

        n = p - pos;
        if (n) {
            memcpy(q, pos, n);
            q += n;
            pos += n;
            bytes -= n;
        }

        /* Insert replacement */

        if (new_len) {
            memcpy(q, new, new_len);
            q += new_len;
        }

        /* Skip old substring */

        pos += old_len;
        bytes -= old_len;

        /* Find next replacement */

        p = memstr(pos, old, bytes, old_len);

    } while (--changes);

    /* Copy trailing substring */

    if (bytes)
        memcpy(q, pos, bytes);
    q[bytes] = '\0';
    return new_str;

return_unchanged:
    new_str = (char*)malloc(src_len + 1);
    memcpy(new_str, src, src_len + 1);
    return new_str;
}

/* ======================================================================
   SDClearSelect()  - Clear select list                                   */

DLLEntry void  SDClearSelect(int listno) {
    
    #pragma pack(2)
    struct {
        int16_t listno;
    } packet;
    #pragma pack()

    if (context_error(CX_CONNECTED))
        goto exit_sdclearselect;

    packet.listno = ShortInt(listno);

    if (!message_pair(SrvrClearSelect, (char*)&packet, sizeof(packet))) {
        goto exit_sdclearselect;
    }

    switch (session[session_idx].server_error) {
    case SV_ON_ERROR:
        Abort("CLEARSELECT generated an abort event", TRUE);
        break;
    }

exit_sdclearselect:
    return;
}


/* ======================================================================
   SDClose()  -  Close a file                                             */
DLLEntry void SDClose(int fno) {
  #pragma pack(2)
  struct {
     int16_t fno;
  }  packet;
  #pragma pack()

  if (context_error(CX_CONNECTED))
    goto exit_sdclose;
  packet.fno = ShortInt(fno);
  if (!message_pair(SrvrClose, (char*)&packet, sizeof(packet))) {
    goto exit_sdclose;
  }
  switch (session[session_idx].server_error) {
    case SV_ON_ERROR:
	  Abort("CLOSE generated an abort event", TRUE);
      break;
  }
exit_sdclose:
  return;
}


/* ======================================================================
   SDConnect()  -  Open connection to server.                             */
DLLEntry  int
SDConnect(char* host, int port, char* username, char* password, char* account) {
  int status = FALSE;
  char login_data[2 + MAX_USERNAME_LEN + 2 + MAX_USERNAME_LEN];
  int n;
  char* p;
  initialise_client();
  if (!FindFreeSession())
    goto exit_sdconnect;
  ClearError;
  n = strlen(host);
  if (n == 0) {
    strcpy_s(session[session_idx].sderror, sizeof(session[0].sderror), "Invalid host name");
    goto exit_sdconnect;
  }
  /* Set up login data */
  p = login_data;
  n = strlen(username);
  if (n > MAX_USERNAME_LEN) {
    strcpy_s(session[session_idx].sderror, sizeof(session[0].sderror), "Invalid user name");
    goto exit_sdconnect;
  }
  *((int16_t*)p) = ShortInt(n); /* User name len */
  p += 2;
  memcpy(p, (char*)username, n); /* User name */
  p += n;
  if (n & 1)
    *(p++) = '\0';
  n = strlen(password);
  if (n > MAX_USERNAME_LEN) {
    strcpy_s(session[session_idx].sderror, sizeof(session[0].sderror), "Invalid password");
    goto exit_sdconnect;
  }
  *((int16_t*)p) = ShortInt(n); /* Password len */
  p += 2;
  memcpy(p, (char*)password, n); /* Password */
  p += n;
  if (n & 1)
    *(p++) = '\0';
  /* Open connection to server */
  if (!OpenSocket((char*)host, port))
    goto exit_sdconnect;
  /* Check username and password */
  n = p - login_data;
  if (!message_pair(SrvrLogin, login_data, n)) {
    goto exit_sdconnect;
  }
  if (session[session_idx].server_error != SV_OK) {
    if (session[session_idx].server_error == SV_ON_ERROR) {
      n = buff_bytes - offsetof(INBUFF, data.abort.message);
      if (n > 0) {
        if (n > (int)sizeof(session[session_idx].sderror) - 1)
          n = (int)sizeof(session[session_idx].sderror) - 1;
        memcpy(session[session_idx].sderror, buff->data.abort.message, n);
        session[session_idx].sderror[n] = '\0';
      }
    }
    goto exit_sdconnect;
  }
  /* Now attempt to attach to required account */
  if (!message_pair(SrvrAccount, account, strlen(account))) {
    goto exit_sdconnect;
  }
  if (session[session_idx].server_error != SV_OK) {
    /* Account attach failed. On SV_ERROR the text is already in sderror
       (fetched by GetResponse); capture the abort text otherwise so the
       caller is not told the connection succeeded. */
    if (session[session_idx].server_error == SV_ON_ERROR) {
      n = buff_bytes - offsetof(INBUFF, data.abort.message);
      if (n > 0) {
        if (n > (int)sizeof(session[session_idx].sderror) - 1)
          n = (int)sizeof(session[session_idx].sderror) - 1;
        memcpy(session[session_idx].sderror, buff->data.abort.message, n);
        session[session_idx].sderror[n] = '\0';
      }
    }
    goto exit_sdconnect;
  }
  session[session_idx].context = CX_CONNECTED;
  status = TRUE;
exit_sdconnect:
  if (!status)
    CloseSocket();
  return status;
}

/* ======================================================================
   sysdir()  -  Return the SDSYS directory named by the configuration file

   SD_CONFIG names the file if it is set, and this now genuinely does match
   the server - it did not before, whatever the comment here used to say.  The
   server read SCARLET_CONFIG and fell back to /etc/sd.conf, so setting the
   variable you would expect configured exactly one of the two.

   The sd.ini-in-the-Windows-directory fallback is gone (14 Aug 2026).  Writing
   to C:\Windows has needed administrator rights since Vista and it is
   16-bit-era practice; the file now lives beside the data it describes, at
   %ProgramData%\SD\sd.conf.  These two values are duplicated from
   gplsrc/sddefs.h, which this toolchain deliberately does not include
   (PROJECT_STATUS.md 5.2) - change them in both places.

   The answer is cached after the first successful read. */

#define SD_CONFIG_ENV     "SD_CONFIG"
#define SD_CONFIG_DEFAULT "C:\\ProgramData\\SD\\sd.conf"

Private char* sysdir(void) {
  static char sysdirpath[MAX_PATHNAME_LEN + 1] = "";
  char inipath[MAX_PATHNAME_LEN + 1];
  char section[50];
  char rec[200 + 1];
  FILE* fu;
  char* p;

  if (sysdirpath[0] != '\0')
    return sysdirpath;

  p = getenv(SD_CONFIG_ENV);
  if ((p != NULL) && (*p != '\0')) {
    snprintf(inipath, sizeof(inipath), "%s", p);
  } else {
    /* Built from %ProgramData% rather than written as C:\ProgramData,
       because that folder can be relocated and the variable holds where it
       actually is.  The literal is only the last resort. */
    p = getenv("ProgramData");
    if ((p != NULL) && (*p != '\0')) {
      snprintf(inipath, sizeof(inipath), "%s\\SD\\sd.conf", p);
    } else {
      snprintf(inipath, sizeof(inipath), "%s", SD_CONFIG_DEFAULT);
    }
  }

  fu = fopen(inipath, "rt");
  if (fu == NULL) {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror), "%s not found", inipath);
    return NULL;
  }

  section[0] = '\0';
  while (fgets(rec, 200, fu) != NULL) {
    if ((p = strchr(rec, '\n')) != NULL)
      *p = '\0';

    if ((rec[0] == '#') || (rec[0] == '\0'))
      continue;

    if (rec[0] == '[') {
      size_t seclen;

      if ((p = strchr(rec, ']')) != NULL)
        *p = '\0';

      /* A section name longer than the buffer cannot match anything we look
         for, so truncating it is harmless.                                  */

      seclen = strlen(rec + 1);
      if (seclen >= sizeof(section))
        seclen = sizeof(section) - 1;
      memcpy(section, rec + 1, seclen);
      section[seclen] = '\0';

      for (p = section; *p != '\0'; p++)
        *p = (char)toupper((unsigned char)*p);
      continue;
    }

    if (strcmp(section, "SD") == 0) /* [sd] items */
    {
      if (strncmp(rec, "SDSYS=", 6) == 0) {
        snprintf(sysdirpath, sizeof(sysdirpath), "%s", rec + 6);
        break;
      }
    }
  }

  fclose(fu);

  if (sysdirpath[0] == '\0') {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror),
             "No SDSYS parameter in %s", inipath);
    return NULL;
  }

  return sysdirpath;
}

/* ======================================================================
   sd_exe_path()  -  Where is sd.exe?

   BESIDE THIS DLL, AND NOT UNDER SDSYS.  17 Aug 2026, PROJECT_STATUS.md
   section 7 step 11.  SDConnectLocal() built "<sysdir>\bin\sd.exe", which is
   inside the DATA tree - C:\ProgramData\SD\sdsys\bin - and that directory
   exists but holds the pcode file, not an executable.  sd.exe is installed to
   C:\Program Files\SD\usr\bin, beside this library, because gplbld/stage.py
   ships both in PROGRAM_FILES_BIN.  The layout is load-bearing for another
   reason too (the two-component POSIX root rule, PROJECT_STATUS.md 6), so it
   is not going to drift.

   Asking Windows where this module was loaded from is therefore both correct
   and self-maintaining: no configuration to set, and it survives an install
   into a different directory, which "{app}" is free to be.

   GetModuleHandleEx with FROM_ADDRESS takes the address of a function in THIS
   DLL, so it answers for the library and not for whichever executable loaded
   it - a client .exe would otherwise get its own directory.  UNCHANGED_REFCOUNT
   because we are not holding a reference, only asking a question.          */

Private int sd_exe_path(char* buff, size_t buffsize) {
  /* The address handed to FROM_ADDRESS only has to lie inside this module, so
     it is a static DATUM rather than this function.  Taking a function's
     address would mean casting a function pointer to an object pointer, which
     ISO C forbids and -Wpedantic reports - and this tree builds without
     warnings. */

  static const char anchor = 0;

  HMODULE hmod;
  DWORD n;
  char* p;

  if (!GetModuleHandleExA(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          (LPCSTR)&anchor, &hmod))
    return FALSE;

  n = GetModuleFileNameA(hmod, buff, (DWORD)buffsize);

  /* GetModuleFileNameA truncates and reports success on a short buffer in
     some Windows versions, so the length is checked rather than trusted. */

  if ((n == 0) || (n >= buffsize))
    return FALSE;

  p = strrchr(buff, '\\');
  if (p == NULL)
    return FALSE;

  if ((size_t)(p - buff) + sizeof("\\sd.exe") > buffsize)
    return FALSE;

  strcpy(p, "\\sd.exe");
  return TRUE;
}

/* ======================================================================
   SDConnectLocal()  -  Open connection to local system as current user

   There is no network involved: we create a named pipe, start an SD process
   attached to it, and speak the same packet protocol over that pipe.  The
   server authenticates us from the process owner, so no credentials are sent
   and SrvrLocalLogin replaces the SrvrLogin exchange used by SDConnect().   */

DLLEntry int SDConnectLocal(char* account) {
  int status = FALSE;
  char command[MAX_PATHNAME_LEN + 128];
  char pipe_name[64];
  int cmdlen;
  char exepath[MAX_PATHNAME_LEN + 1];
  int32_t n;
  STARTUPINFOA startupinfo;
  PROCESS_INFORMATION process_information;

  initialise_client();

  if (!FindFreeSession())
    return FALSE;

  ClearError;
  session[session_idx].server_error = 0;
  session[session_idx].sd_status = 0;
  session[session_idx].is_local = TRUE;

  /* SD must be configured for a local session to be possible at all, and
     sysdir() writes the session error text when it is not.  The executable is
     no longer found through it - see sd_exe_path() - but the check is worth
     keeping ahead of spawning anything. */

  if (sysdir() == NULL)
    goto exit_sdconnect_local;

  if (!sd_exe_path(exepath, sizeof(exepath))) {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror),
             "Cannot determine where sd.exe is installed");
    goto exit_sdconnect_local;
  }

  /* The name only has to be unique among the pipes this process owns */

  snprintf(pipe_name, sizeof(pipe_name), "\\\\.\\pipe\\~SDPipe%lu-%d",
           (unsigned long)GetCurrentProcessId(), (int)session_idx);

  session[session_idx].hPipe =
      CreateNamedPipeA(pipe_name, PIPE_ACCESS_DUPLEX,
                       PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                       1,     /* Max instances */
                       1024,  /* Output buffer size */
                       1024,  /* Input buffer size */
                       0,     /* Default timeout */
                       NULL); /* Security attributes */

  if (session[session_idx].hPipe == INVALID_HANDLE_VALUE) {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror), "Error %d creating pipe",
             (int)GetLastError());
    goto exit_sdconnect_local;
  }

  /* Launch the SD process that will serve this session */

  /* THE PATH IS QUOTED, and it has to be: sd.exe lives under C:\Program
     Files, CreateProcessA is called with lpApplicationName NULL, and an
     unquoted path with a space in it makes Windows try each prefix in turn -
     C:\Program.exe first.  That is a hijack, not only a bug. */

  cmdlen = snprintf(command, sizeof(command), "\"%s\" -Q -C %s", exepath,
                    pipe_name);

  /* Truncation would launch something other than what we intended, so refuse
     rather than run a mangled command line.                                 */

  if ((cmdlen < 0) || ((size_t)cmdlen >= sizeof(command))) {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror),
             "SDSYS path too long to build a command line");
    goto exit_sdconnect_local;
  }

  memset(&startupinfo, 0, sizeof(startupinfo));
  startupinfo.cb = sizeof(startupinfo);

  if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, DETACHED_PROCESS, NULL,
                      NULL, &startupinfo, &process_information)) {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror),
             "Failed to create child process. Error %d", (int)GetLastError());
    goto exit_sdconnect_local;
  }

  /* We never wait on the child, so neither handle is of any further use */

  CloseHandle(process_information.hThread);
  CloseHandle(process_information.hProcess);

  /* Wait for the child to connect.  If it got there first the call fails with
     ERROR_PIPE_CONNECTED, which means the pipe is connected, not broken.    */

  if (!ConnectNamedPipe(session[session_idx].hPipe, NULL) &&
      (GetLastError() != ERROR_PIPE_CONNECTED)) {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror), "Error %d connecting pipe",
             (int)GetLastError());
    goto exit_sdconnect_local;
  }

  /* Send local login packet */

  if (!message_pair(SrvrLocalLogin, NULL, 0))
    goto exit_sdconnect_local;

  if (session[session_idx].server_error != SV_OK) {
    if (session[session_idx].server_error == SV_ON_ERROR) {
      n = buff_bytes - offsetof(INBUFF, data.abort.message);
      if (n > 0) {
        if (n > (int)sizeof(session[session_idx].sderror) - 1)
          n = (int)sizeof(session[session_idx].sderror) - 1;
        memcpy(session[session_idx].sderror, buff->data.abort.message, n);
        session[session_idx].sderror[n] = '\0';
      }
    }
    goto exit_sdconnect_local;
  }

  /* Now attempt to attach to required account */

  if (!message_pair(SrvrAccount, account, strlen(account)))
    goto exit_sdconnect_local;

  if (session[session_idx].server_error != SV_OK) {
    if (session[session_idx].server_error == SV_ON_ERROR) {
      n = buff_bytes - offsetof(INBUFF, data.abort.message);
      if (n > 0) {
        if (n > (int)sizeof(session[session_idx].sderror) - 1)
          n = (int)sizeof(session[session_idx].sderror) - 1;
        memcpy(session[session_idx].sderror, buff->data.abort.message, n);
        session[session_idx].sderror[n] = '\0';
      }
    }
    goto exit_sdconnect_local;
  }

  session[session_idx].context = CX_CONNECTED;
  status = TRUE;

exit_sdconnect_local:
  if (!status)
    CloseSocket(); /* Closes the pipe and clears is_local */

  return status;
}

/* ======================================================================
   SDConnected()  -  Are we connected?                                    */
DLLEntry  int SDConnected() {
  ClearError;
  return (session[session_idx].context == CX_DISCONNECTED) ? FALSE : TRUE;
}

/* ======================================================================
   SDDcount()  -  Count fields, values or subvalues                       */
DLLEntry  int SDDcount(char* src, char* delim_str) {
  int32_t src_len;
  char* p;
  int32_t ct = 0;
  unsigned char delim;  /* note need unsigned char for memchr to work > 127 character, is this a c++ builder thing? */

  /* initialise_client();  */
  if (strlen(delim_str) != 0) {
	delim = *delim_str;
	src_len = strlen(src);
	if (src_len != 0) {
	  ct = 1;
	  while ((p = memchr(src, delim, src_len)) != NULL) {
        src_len -= (1 + p - src);
        src = p + 1;
		ct++;
      }
	}
  }
  return ct;
}

/* ======================================================================
   SDDebug()  -  Turn on/off packet debugging                             */
DLLEntry void SDDebug(int16_t mode)
{
  if (mode && (srvr_debug == NULL)) /* Turn on */
  {
    char debug_path[MAX_PATH];
    const char* configured_path = getenv("SD_CLIENT_DEBUG");
    if ((configured_path != NULL) && (configured_path[0] != '\0')) {
      srvr_debug = fopen(configured_path, "wt");
    } else {
      DWORD path_len = GetTempPathA((DWORD)sizeof(debug_path), debug_path);
      if ((path_len > 0) && (path_len < sizeof(debug_path)) &&
          (path_len + strlen("sdclilib.log") < sizeof(debug_path))) {
        memcpy(debug_path + path_len, "sdclilib.log",
               strlen("sdclilib.log") + 1);
        srvr_debug = fopen(debug_path, "wt");
      }
    }
    if (srvr_debug == NULL) {
      snprintf(session[session_idx].sderror,
               sizeof(session[session_idx].sderror),
               "Unable to open SD client debug log");
    }
  }
  if (!mode && (srvr_debug != NULL)) /* Turn off */
  {
    fclose(srvr_debug);
    srvr_debug = NULL;
  }
}
/* ======================================================================
   SDDel()  -  Delete field, value or subvalue                            */

DLLEntry char*  SDDel(char* src, int fno, int vno, int svno) {
    int32_t src_len;
    char* pos;      /* Rolling source pointer */
    int32_t bytes; /* Remaining bytes counter */
    int32_t new_len;
    char* new_str;
    char* p;
    int16_t i;
    int32_t n;

    initialise_client();

    src_len = strlen(src);
    if (src_len == 0)
        goto null_result; /* Deleting from null string */

    /* Setp 1  -  Initialise varaibles */

    if (fno < 1)
        fno = 1;

    /* Step 2  -  Position to start of item */

    pos = src;
    bytes = src_len;

    /* Skip to start field */

    i = fno;
    while (--i) {
        p = memchr(pos, U_FIELD_MARK, bytes);
        if (p == NULL)
            goto unchanged_result; /* No such field */
        bytes -= (1 + p - pos);
        pos = p + 1;
    }

    p = memchr(pos, U_FIELD_MARK, bytes);
    if (p != NULL)
        bytes = p - pos; /* Length of field, excluding end mark */

    if (vno < 1) /* Deleting whole field */
    {
        if (p == NULL) /* Last field */
        {
            if (fno > 1) /* Not only field. Back up to include leading mark */
            {
                pos--;
                bytes++;
            }
        }
        else /* Not last field */
        {
            bytes++; /* Include trailing mark in deleted region */
        }
        goto done;
    }

    /* Skip to start value */

    i = vno;
    while (--i) {
        p = memchr(pos, U_VALUE_MARK, bytes);
        if (p == NULL)
            goto unchanged_result; /* No such value */
        bytes -= (1 + p - pos);
        pos = p + 1;
    }

    p = memchr(pos, U_VALUE_MARK, bytes);
    if (p != NULL)
        bytes = p - pos; /* Length of value, excluding end mark */

    if (svno < 1) /* Deleting whole value */
    {
        if (p == NULL) /* Last value */
        {
            if (vno > 1) /* Not only value. Back up to include leading mark */
            {
                pos--;
                bytes++;
            }
        }
        else /* Not last value */
        {
            bytes++; /* Include trailing mark in deleted region */
        }
        goto done;
    }

    /* Skip to start subvalue */

    i = svno;
    while (--i) {
        p = memchr(pos, U_SUBVALUE_MARK, bytes);
        if (p == NULL)
            goto unchanged_result; /* No such subvalue */
        bytes -= (1 + p - pos);
        pos = p + 1;
    }
    p = memchr(pos, U_SUBVALUE_MARK, bytes);
    if (p != NULL)
        bytes = p - pos; /* Length of subvalue, excluding end mark */

    if (p == NULL) /* Last subvalue */
    {
        if (svno > 1) /* Not only subvalue. Back up to include leading mark */
        {
            pos--;
            bytes++;
        }
    }
    else /* Not last subvalue */
    {
        bytes++; /* Include trailing mark in deleted region */
    }

done:
    /* Now construct new string with 'bytes' bytes omitted starting at 'pos' */

    new_len = src_len - bytes;
    new_str = malloc(new_len + 1);
    p = new_str;

    n = pos - src; /* Length of leading substring */
    if (n) {
        memcpy(p, src, n);
        p += n;
    }

    n = src_len - (bytes + n); /* Length of trailing substring */
    if (n) {
        memcpy(p, pos + bytes, n);
        p += n;
    }

    *p = '\0';
    return new_str;

null_result:
    return NullString();

unchanged_result:
    new_str = malloc(src_len + 1);
    memcpy(new_str, src, src_len + 1);
    return new_str;
}

/* ======================================================================
   SDDelete()  -  Delete record                                           */

DLLEntry void SDDelete(int fno, char* id) {
    delete_record(SrvrDelete, fno, id);
}

/* ======================================================================
   SDDeleteu()  -  Delete record, retaining lock                          */

DLLEntry void SDDeleteu(int fno, char* id) {
    delete_record(SrvrDeleteu, fno, id);
}

/* ======================================================================
   SDDisconnect()  -  Close connection to server.                         */
DLLEntry void SDDisconnect() {
  if (session[session_idx].context != CX_DISCONNECTED) {
    disconnect();
  }
}

/* ======================================================================
   SDDisconnectAll()  -  Close connection to all servers.                 */
DLLEntry void SDDisconnectAll() {
  int16_t i;
  for (i = 0; i < MAX_SESSIONS; i++) {
    if (session[i].context != CX_DISCONNECTED) {
      session_idx = i;
      disconnect();
    }
  }
}

/* ======================================================================
   SDEndCommand()  -  End a command that is requesting input              */

DLLEntry void SDEndCommand() {
    if (context_error(CX_EXECUTING))
        goto exit_sdendcommand;

    if (!message_pair(SrvrEndCommand, NULL, 0)) {
        goto exit_sdendcommand;
    }

    session[session_idx].context = CX_CONNECTED;

exit_sdendcommand:
    return;
}

/* ======================================================================
   Licensed package management. */
DLLEntry int16_t SDEnterPackage(char* name) {
  int name_len;
  if (context_error(CX_CONNECTED))
    return FALSE;
  name_len = (int)strlen(name);
  if ((name_len < 1) || (name_len > MAX_PACKAGE_NAME_LEN)) {
    session[session_idx].server_error = SV_ELSE;
    session[session_idx].sd_status = ER_BAD_NAME;
    return FALSE;
  }
  if (!message_pair(SrvrEnterPackage, name, name_len))
    return FALSE;
  if (session[session_idx].server_error == SV_ON_ERROR)
    Abort("EnterPackage generated an abort event", TRUE);
  return session[session_idx].server_error == SV_OK;
}

DLLEntry int16_t SDExitPackage(char* name) {
  int name_len;
  if (context_error(CX_CONNECTED))
    return FALSE;
  name_len = (int)strlen(name);
  if ((name_len < 1) || (name_len > MAX_PACKAGE_NAME_LEN)) {
    session[session_idx].server_error = SV_ELSE;
    session[session_idx].sd_status = ER_BAD_NAME;
    return FALSE;
  }
  if (!message_pair(SrvrExitPackage, name, name_len))
    return FALSE;
  if (session[session_idx].server_error == SV_ON_ERROR)
    Abort("ExitPackage generated an abort event", TRUE);
  return session[session_idx].server_error == SV_OK;
}

/* ======================================================================
   SDError()  -  Return extended error string                             */
DLLEntry char*  SDError() {
  return session[session_idx].sderror;
}

/* ======================================================================
   SDExecute()  -  Execute a command                                      */
DLLEntry char*  SDExecute(char* cmnd, int* err) {
  int32_t reply_len = 0;
  char* reply;
  if (context_error(CX_CONNECTED))
    goto exit_sdexecute;
  if (!message_pair(SrvrExecute, cmnd, strlen(cmnd))) {
    goto exit_sdexecute;
  }
  switch (session[session_idx].server_error) {
    case SV_PROMPT:
      session[session_idx].context = CX_EXECUTING;
      /* fall through */
    case SV_OK:
      reply_len = buff_bytes - offsetof(INBUFF, data.execute.reply);
      break;
    case SV_ON_ERROR:
      Abort("EXECUTE generated an abort event", TRUE);
      break;
  }
exit_sdexecute:
  reply = malloc(reply_len + 1);
  if (reply == NULL) {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror),
             "Unable to allocate command reply");
    *err = SV_ERROR;
    return NULL;
  }
  if (reply_len > 0)
    memcpy(reply, buff->data.execute.reply, reply_len);
  reply[reply_len] = '\0';
  *err = session[session_idx].server_error;
  return reply;
}
/* ======================================================================
   SDExtract()  -  Extract field, value or subvalue                       */
DLLEntry char*  SDExtract(char* src, int fno, int vno, int svno) {
  int32_t src_len;
  char* p;
  char* result;
  initialise_client();
  src_len = strlen(src);
  if (src_len == 0)
    goto null_result; /* Extracting from null string */
  /* Setp 1  -  Initialise variables */
  if (fno < 1)
    fno = 1;
  /* Step 2  -  Position to start of item */
  /* Skip to start field */
  while (--fno) {
	p = memchr(src, U_FIELD_MARK, src_len);
	if (p == NULL)
      goto null_result; /* No such field */
    src_len -= (1 + p - src);
    src = p + 1;
  }
  p = memchr(src, U_FIELD_MARK, src_len);
  if (p != NULL)
    src_len = p - src; /* Adjust to ignore later fields */
  if (vno < 1)
    goto done; /* Extracting whole field */
  /* Skip to start value */
  while (--vno) {
	p = memchr(src, U_VALUE_MARK, src_len);
    if (p == NULL)
      goto null_result; /* No such value */
    src_len -= (1 + p - src);
    src = p + 1;
  }
  p = memchr(src, U_VALUE_MARK, src_len);
  if (p != NULL)
    src_len = p - src; /* Adjust to ignore later values */
  if (svno < 1)
    goto done; /* Extracting whole value */
  /* Skip to start subvalue */
  while (--svno) {
	p = memchr(src, U_SUBVALUE_MARK, src_len);
    if (p == NULL)
      goto null_result; /* No such subvalue */
    src_len -= (1 + p - src);
    src = p + 1;
  }
  p = memchr(src, U_SUBVALUE_MARK, src_len);
  if (p != NULL)
    src_len = p - src; /* Adjust to ignore later fields */
done:
  result = malloc(src_len + 1);
  memcpy(result, src, src_len);
  result[src_len] = '\0';
  return result;
null_result:
  return NullString();
}

/* ======================================================================
   SDField()  -  Extract delimited substring                              */

DLLEntry char*  SDField(char* src, char* delim, int first, int occurrences) {
    int src_len;
    int delim_len;
    char delimiter;
    int32_t bytes; /* Remaining bytes counter */
    char* pos;
    char* p;
    char* q;
    char* result;
    int result_len;

    initialise_client();

    src_len = strlen(src);

    delim_len = strlen(delim);
    if ((delim_len == 0) || (src_len == 0))
        goto return_null;

    if (first < 1)
        first = 1;

    if (occurrences < 1)
        occurrences = 1;

    delimiter = *delim;

    /* Find start of data to return */

    pos = src;
    bytes = src_len;
    while (--first) {
        p = memchr(pos, delimiter, bytes);
        if (p == NULL)
            goto return_null;
        bytes -= (p - pos + 1);
        pos = p + 1;
    }

    /* Find end of data to return */

    q = pos;
    do {
        p = memchr(q, delimiter, bytes);
        if (p == NULL) {
            p = q + bytes;
            break;
        }
        bytes -= (p - q + 1);
        q = p + 1;
    } while (--occurrences);

    result_len = p - pos;
    result = malloc(result_len + 1);
    memcpy(result, pos, result_len);
    result[result_len] = '\0';
    return result;

return_null:
    return NullString();
}

/* ======================================================================
   SDFree()  -  Free memory returned by other functions                   */
DLLEntry void SDFree(void* p) {
  free(p);
}

/* ======================================================================
   SDGetSession()  -  Return session index                                */
DLLEntry  int SDGetSession() {
  return session_idx;
}

/* ======================================================================
   SDIns()  -  Insert field, value or subvalue                            */
DLLEntry char*  SDIns(char* src, int fno, int vno, int svno, char* new) {
  int32_t src_len;
  char* pos;        /* Rolling source pointer */
  int32_t bytes;   /* Remaining bytes counter */
  int32_t ins_len; /* Length of inserted data */
  int32_t new_len;
  char* new_str;
  char* p;
  int i;   /* resolves CWE-197 check, "Comparison of narrow type with wide type in loop condition." */
  int32_t n;
  int16_t fm = 0;
  int16_t vm = 0;
  int16_t sm = 0;
  unsigned char postmark = '\0';
  initialise_client();
  src_len = strlen(src);
  ins_len = strlen(new);
  pos = src;
  bytes = src_len;
  if (fno < 1)
    fno = 1;
  if (vno < 0)
    vno = 0;
  if (svno < 0)
    svno = 0;
  if (src_len == 0) { /* Inserting in null string */
    if (fno > 1)
      fm = fno - 1;
    if (vno > 1)
      vm = vno - 1;
    if (svno > 1)
      sm = svno - 1;
    goto done;
  }
  /* Skip to start field */
  for (i = 1; i < fno; i++) {
	p = memchr(pos, U_FIELD_MARK, bytes);
    if (p == NULL) { /* No such field */
      fm = fno - i;
      if (vno > 1)
        vm = vno - 1;
      if (svno > 1)
        sm = svno - 1;
      pos = src + src_len;
      goto done;
    }
    bytes -= (1 + p - pos);
    pos = p + 1;
  }
  p = memchr(pos, U_FIELD_MARK, bytes);
  if (p != NULL)
    bytes = p - pos; /* Length of field */
  if (vno == 0) { /* Inserting field */
	postmark = U_FIELD_MARK;
    goto done;
  }
  /* Skip to start value */
  for (i = 1; i < vno; i++) {
	p = memchr(pos, U_VALUE_MARK, bytes);
    if (p == NULL) { /* No such value */
      vm = vno - i;
      if (svno > 1)
        sm = svno - 1;
      pos += bytes;
      goto done;
    }
    bytes -= (1 + p - pos);
    pos = p + 1;
  }
  p = memchr(pos, U_VALUE_MARK, bytes);
  if (p != NULL)
    bytes = p - pos; /* Length of value, excluding end mark */
  if (svno == 0) { /* Inserting value */
	postmark = U_VALUE_MARK;
    goto done;
  }
  /* Skip to start subvalue */
  for (i = 1; i < svno; i++) {
	p = memchr(pos, U_SUBVALUE_MARK, bytes);
    if (p == NULL) { /* No such subvalue */
      sm = svno - i;
      pos += bytes;
      goto done;
    }
    bytes -= (1 + p - pos);
    pos = p + 1;
  }
  postmark = U_SUBVALUE_MARK;
done:
  /* Now construct new string inserting fm, vm and sm marks and new data
    at 'pos'.                                                           */
  n = pos - src; /* Length of leading substring */
  if ((n == src_len) || (IsDelim(src[n]) && src[n] > postmark)) { /* 0380 */
    postmark = '\0';
  }
  new_len = src_len + fm + vm + sm + ins_len + (postmark != '\0');
  new_str = malloc(new_len + 1);
  p = new_str;
  if (n) {
    memcpy(p, src, n);
    p += n;
  }
  while (fm--)
	*(p++) = U_FIELD_MARK;
  while (vm--)
	*(p++) = U_VALUE_MARK;
  while (sm--)
    *(p++) = U_SUBVALUE_MARK;
  if (ins_len) {
    memcpy(p, new, ins_len);
    p += ins_len;
  }
  if (postmark != '\0')
    *(p++) = postmark;
  n = src_len - n; /* Length of trailing substring */
  if (n) {
    memcpy(p, pos, n);
    p += n;
  }
  *p = '\0';
  return new_str;
}

/* ======================================================================
   SDLocate()  -  Search dynamic array                                    */

DLLEntry  int SDLocate(char* item,
                      char* src,
                      int fno,
                      int vno,
                      int svno,
                      int* pos,
                      char* order) {
  int item_len;
  int src_len;
  char* p;
  char* q;
  bool ascending = TRUE;
  bool left = TRUE;
  bool sorted = FALSE;
  int16_t idx = 1;
  int d;
  bool found = FALSE;
  int i;
  int bytes;
  char mark;
  int n;
  int x;
  char* s1;
  char* s2;

  initialise_client();

  /* Establish sort mode */

  i = strlen(order);
  if (i >= 1) {
    sorted = TRUE;
    ascending = (order[0] != 'D');
  }

  if (i >= 2)
    left = (order[1] != 'R');

  item_len = strlen(item); /* Length of item to find */

  src_len = strlen(src);

  p = src;
  bytes = src_len;

  if (fno < 1)
    fno = 1;

  /* Scan to start field */

  mark = U_FIELD_MARK;
  idx = fno;
  for (i = 1; i < fno; i++) {
    if (bytes == 0)
      goto done;
	q = memchr(p, U_FIELD_MARK, bytes);
    if (q == NULL)
      goto done; /* No such field */
    bytes -= (1 + q - p);
    p = q + 1;
  }

  if (vno > 0) /* Searching for value or subvalue */
  {
	q = memchr(p, U_FIELD_MARK, bytes);
    if (q != NULL)
      bytes = q - p; /* Limit view to length of field */

	mark = U_VALUE_MARK;
    idx = vno;
    for (i = 1; i < vno; i++) {
      if (bytes == 0)
        goto done;
	  q = memchr(p, U_VALUE_MARK, bytes);
      if (q == NULL)
        goto done; /* No such value */
      bytes -= (1 + q - p);
      p = q + 1;
    }

    if (svno > 0) /* Searching for subvalue */
    {
	  q = memchr(p, U_VALUE_MARK, bytes);
      if (q != NULL)
        bytes = q - p; /* Limit view to length of value */

	  mark = U_SUBVALUE_MARK;
      idx = svno;
      for (i = 1; i < svno; i++) /* 0512 */
      {
        if (bytes == 0)
          goto done;
        q = memchr(p, U_SUBVALUE_MARK, bytes);
        if (q == NULL)
          goto done; /* No such subvalue */
        bytes -= (1 + q - p);
        p = q + 1;
      }
    }
  }

  /* We are now at the start position for the search and 'mark' contains the
    delimiting mark character.  Because we have adjusted 'bytes' to limit
    our view to the end of the item, we do not need to worry about higher
    level marks.  Examine successive items from this point.                 */

  if (bytes == 0) {
    if (item_len == 0)
      found = TRUE;
    goto done;
  }

  do {
    q = memchr(p, mark, bytes);
    n = (q == NULL) ? bytes : (q - p); /* Length of entry */
    if ((n == item_len) && (memcmp(p, item, n) == 0)) {
      found = TRUE;
      goto done;
    }

    if (sorted) /* Check if we have gone past correct position */
    {
      if (left || (n == item_len)) {
        d = memcmp(p, item, min(n, item_len));
        if (d == 0) {
          if ((n > item_len) == ascending)
            goto done;
        } else if ((d > 0) == ascending)
          goto done;
      } else /* Right sorted and lengths differ */
      {
        x = n - item_len;
        s1 = p;
        s2 = item;
        if (x > 0) /* Array entry longer than item to find */
        {
          do {
            d = *(s1++) - ' ';
          } while ((d == 0) && --x);
        } else /* Array entry shorter than item to find */
        {
          do {
            d = ' ' - *(s2++);
          } while ((d == 0) && ++x);
        }
        if (d == 0)
          d = memcmp(s1, s2, min(n, item_len));
        if ((d > 0) == ascending)
          goto done;
      }
    }

    bytes -= (1 + q - p);
    p = q + 1;
    idx++;
  } while (q);

done:
  *pos = idx;
  return found;
}

/* ======================================================================
   SDLogto()  -  LOGTO                                                    */

DLLEntry  int SDLogto(char* account_name) {
    bool status = FALSE;
    int name_len;

    if (context_error(CX_CONNECTED))
        goto exit_logto;

    name_len = strlen(account_name);
    if ((name_len < 1) || (name_len > MAX_ACCOUNT_NAME_LEN)) {
        session[session_idx].server_error = SV_ELSE;
        session[session_idx].sd_status = ER_BAD_NAME;
    }
    else {
        if (!message_pair(SrvrAccount, account_name, name_len)) {
            goto exit_logto;
        }
    }

    switch (session[session_idx].server_error) {
    case SV_OK:
        status = TRUE;
        break;

    case SV_ON_ERROR:
        Abort("LOGTO generated an abort event", TRUE);
        break;

    case SV_LOCKED:
    case SV_ELSE:
    case SV_ERROR:
        break;
    }

exit_logto:
    return status;
}

/* ======================================================================
   SDMarkMapping()  -  Enable/disable mark mapping on a directory file    */

DLLEntry  void  SDMarkMapping(int16_t fno, int16_t state) {
    struct {
        int16_t fno;
        int16_t state;
    } packet;

    if (!context_error(CX_CONNECTED)) {
        packet.fno = ShortInt(fno);
        packet.state = ShortInt(state);

        message_pair(SrvrMarkMapping, (char*)&packet, sizeof(packet));
    }
}

/* ======================================================================
   SDMatch()  -  String matching                                          */

DLLEntry int SDMatch(char* str, char* pattern) {
    char template[MAX_MATCH_TEMPLATE_LEN + 1];
    char src_string[MAX_MATCHED_STRING_LEN + 1];
    int n;
    char* p;
    char* q;

    initialise_client();

    component_start = NULL;
    component_end = NULL;

    /* Copy template and string to our own buffers so we can alter them */

    n = strlen(pattern);
    if ((n == 0) || (n > MAX_MATCH_TEMPLATE_LEN))
        goto no_match;
    memcpy(template, pattern, n);
    template[n] = '\0';

    n = strlen(str);
    if (n > MAX_MATCHED_STRING_LEN)
        goto no_match;
    if (n)
        memcpy(src_string, str, n);
    src_string[n] = '\0';

    /* Try matching against each value mark delimited template */

    p = template;
    do { /* Outer loop - extract templates */
        q = strchr(p, (char)U_VALUE_MARK);
        if (q != NULL)
            *q = '\0';

        if (match_template(src_string, p, 0, 0))
            return TRUE;

        p = q + 1;
    } while (q != NULL);

no_match:
    return FALSE;
}

/* ======================================================================
   SDMatchfield()  -  String matching                                     */

DLLEntry char*  SDMatchfield(char* str, char* pattern, int component) {
    char template[MAX_MATCH_TEMPLATE_LEN + 1];
    char src_string[MAX_MATCHED_STRING_LEN + 1];
    int n;
    char* p;
    char* q;
    char* result;

    initialise_client();

    if (component < 1)
        component = 1;

    component_start = NULL;
    component_end = NULL;

    /* Copy template and string to our own buffers so we can alter them */

    n = strlen(pattern);
    if ((n == 0) || (n > MAX_MATCH_TEMPLATE_LEN))
        goto no_match;
    memcpy(template, pattern, n);
    template[n] = '\0';

    n = strlen(str);
    if (n > MAX_MATCHED_STRING_LEN)
        goto no_match;
    if (n)
        memcpy(src_string, str, n);
    src_string[n] = '\0';

    /* Try matching against each value mark delimited template */

    p = template;
    do { /* Outer loop - extract templates */
        q = strchr(p, (char)U_VALUE_MARK);
        if (q != NULL)
            *q = '\0';

        if (match_template(src_string, p, 0, component)) {
            if (component_end != NULL)
                *(component_end) = '\0';
            n = strlen(component_start);
            result = malloc(n + 1);
            memcpy(result, component_start, n);
            result[n] = '\0';
            return result;
        }

        p = q + 1;
    } while (q != NULL);

no_match:
    return NullString();
}

/* ======================================================================
   SDOpen()  -  Open file                                                 */
DLLEntry  int SDOpen(char* filename) {
  int fno = 0;
  if (context_error(CX_CONNECTED))
    goto exit_sdopen;
  if (!message_pair(SrvrOpen, filename, strlen(filename))) {
    goto exit_sdopen;
  }
  switch (session[session_idx].server_error) {
    case SV_OK:
      fno = ShortInt(buff->data.open.fno);
      break;
    case SV_ON_ERROR:
    case SV_ELSE:
    case SV_ERROR:
      break;
  }
exit_sdopen:
  return fno;
}

/* ======================================================================
   SDRead()  -  Read record                                               */
DLLEntry char* SDRead(int fno, char* id, int* err) {
  return read_record(fno, id, err, SrvrRead);
}

/* ======================================================================
   SDReadl()  -  Read record with shared lock                             */
DLLEntry char*  SDReadl(int fno, char* id, int wait, int* err) {
  return read_record(fno, id, err, (wait) ? SrvrReadlw : SrvrReadl);
}

/* ======================================================================
   SDReadList()  - Read select list                                       */

 DLLEntry char* SDReadList(int listno) {
    char* list;
    /* int16_t status = 0; variable set but never used */
    int32_t data_len = 0;
    #pragma pack(2)
    struct {
        int16_t listno;
    } packet;
    #pragma pack()

    if (context_error(CX_CONNECTED))
        goto exit_sdreadlist;

    packet.listno = ShortInt(listno);

    if (!message_pair(SrvrReadList, (char*)&packet, sizeof(packet))) {
        goto exit_sdreadlist;
    }

    switch (session[session_idx].server_error) {
    case SV_OK:
        data_len = buff_bytes - offsetof(INBUFF, data.readlist.list);
        break;

    case SV_ON_ERROR:
        Abort("READLIST generated an abort event", TRUE);
        break;

    default:
        /* SV_ELSE / SV_LOCKED / SV_ERROR: fall through to return an empty
           string so callers never receive NULL. The error is available via
           SDError() / SDStatus(). */
        break;
    }

    /* status = session[session_idx].server_error;
     * variable set but never used. */

exit_sdreadlist:

    list = malloc(data_len + 1);
    if (data_len > 0) /* buff may be NULL on a pre-network failure */
        memcpy(list, buff->data.readlist.list, data_len);
    list[data_len] = '\0';
    return list;
}

/* ======================================================================
   SDReadNext()  - Read select list entry                                 */

 DLLEntry char* SDReadNext(int16_t listno) {
    char* id;
    int32_t id_len = 0;
    
    #pragma pack(2)
    struct {
        int16_t listno;
    } packet;
    #pragma pack()
    if (context_error(CX_CONNECTED))
        goto exit_sdreadnext;

    packet.listno = ShortInt(listno);

    if (!message_pair(SrvrReadNext, (char*)&packet, sizeof(packet))) {
        goto exit_sdreadnext;
    }

    switch (session[session_idx].server_error) {
    case SV_OK:
        id_len = buff_bytes - offsetof(INBUFF, data.readnext.id);
        break;

    case SV_ON_ERROR:
        Abort("READNEXT generated an abort event", TRUE);
        break;

    default:
        /* SV_ELSE / SV_LOCKED / SV_ERROR: fall through to return an empty
           string so callers never receive NULL. The error is available via
           SDError() / SDStatus(). */
        break;
    }

exit_sdreadnext:
    id = malloc(id_len + 1);
    if (id_len > 0) /* buff may be NULL on a pre-network failure */
        memcpy(id, buff->data.readnext.id, id_len);
    id[id_len] = '\0';
    return id;
}


/* ======================================================================
   SDReadu()  -  Read record with exclusive lock                          */
DLLEntry char* SDReadu(int fno, char* id, int wait, int* err) {
  return read_record(fno, id, err, (wait) ? SrvrReaduw : SrvrReadu);
}

/* ======================================================================
   SDRecordlock()  -  Get lock on a record                                */
DLLEntry void SDRecordlock(int fno, char* id, int update_lock, int wait) {
  int id_len;
  int16_t flags;

  #pragma pack(2)
  struct {
    int16_t fno;
    int16_t flags; /* 0x0001 : Update lock */
                     /* 0x0002 : No wait */
    char id[MAX_ID_LEN];
  } packet;
  #pragma pack()

  if (!context_error(CX_CONNECTED)) {
    packet.fno = ShortInt(fno);
    id_len = strlen(id);
    if (id_len > MAX_ID_LEN) {
      session[session_idx].server_error = SV_ON_ERROR;
      session[session_idx].sd_status = ER_IID;
    } else {
      memcpy(packet.id, id, id_len);
      flags = (update_lock) ? 1 : 0;
      if (!wait)
        flags |= 2;
      packet.flags = ShortInt(flags);
      if (!message_pair(SrvrLockRecord, (char*)&packet, id_len + 4)) {
        session[session_idx].server_error = SV_ON_ERROR;
      }
    }
    switch (session[session_idx].server_error) {
      case SV_OK:
        break;
      case SV_ON_ERROR:
        Abort("RECORDLOCK generated an abort event", TRUE);
        break;
      case SV_LOCKED:
      case SV_ELSE:
      case SV_ERROR:
        break;
    }
  }
}
/* ======================================================================
   SDRelease()  -  Release lock                                           */
DLLEntry void SDRelease(int fno, char* id) {
  int id_len;

  #pragma pack(2)
  struct {
    int16_t fno;
    char id[MAX_ID_LEN];
  } packet;
  #pragma pack()

  if (context_error(CX_CONNECTED))
    goto exit_release;
  packet.fno = ShortInt(fno);
  if (fno == 0) /* Release all locks */
  {
    id_len = 0;
  } else {
    id_len = strlen(id);
    if (id_len > MAX_ID_LEN) {
      session[session_idx].server_error = SV_ON_ERROR;
      session[session_idx].sd_status = ER_IID;
      goto release_error;
    }
    memcpy(packet.id, id, id_len);
  }
  if (!message_pair(SrvrRelease, (char*)&packet, id_len + 2)) {
    goto exit_release;
  }
release_error:
  switch (session[session_idx].server_error) {
    case SV_OK:
      break;
    case SV_ON_ERROR:
      Abort("RELEASE generated an abort event", TRUE);
      break;
    case SV_LOCKED:
    case SV_ELSE:
    case SV_ERROR:
      break;
  }
exit_release:
  return;
}

/* ======================================================================
   SDReplace()  -  Replace field, value or subvalue                       */

DLLEntry  char* SDReplace(char* src, int fno, int vno, int svno, char* new) {
    int32_t src_len;
    char* pos;        /* Rolling source pointer */
    int32_t bytes;   /* Remaining bytes counter */
    int32_t ins_len; /* Length of inserted data */
    int32_t new_len;
    char* new_str;
    char* p;
    int i;
    int32_t n;
    int16_t fm = 0;
    int16_t vm = 0;
    int16_t sm = 0;

    initialise_client();

    src_len = strlen(src);
    ins_len = strlen(new);

    pos = src;
    bytes = src_len;

    if (src_len == 0) /* Replacing in null string */
    {
        if (fno > 1)
            fm = fno - 1;
        if (vno > 1)
            vm = vno - 1;
        if (svno > 1)
            sm = svno - 1;
        bytes = 0;
        goto done;
    }

    if (fno < 1) /* Appending a new field */
    {
        pos = src + src_len;
        fm = 1;
        if (vno > 1)
            vm = vno - 1;
        if (svno > 1)
            sm = svno - 1;
        bytes = 0;
        goto done;
    }

    /* Skip to start field */

    for (i = 1; i < fno; i++) {
        p = memchr(pos,U_FIELD_MARK, bytes);
        if (p == NULL) /* No such field */
        {
            fm = fno - i;
            if (vno > 1)
                vm = vno - 1;
            if (svno > 1)
                sm = svno - 1;
            pos = src + src_len;
            bytes = 0;
            goto done;
        }
        bytes -= (1 + p - pos);
        pos = p + 1;
    }

    p = memchr(pos,U_FIELD_MARK, bytes);
    if (p != NULL)
        bytes = p - pos; /* Length of field */

    if (vno == 0)
        goto done; /* Replacing whole field */

    if (vno < 0) /* Appending new value */
    {
        if (p != NULL)
            pos = p; /* 0553 */
        else
            pos += bytes; /* 0553 */
        if (bytes)
            vm = 1; /* 0553 */
        if (svno > 1)
            sm = svno - 1;
        bytes = 0;
        goto done;
    }

    /* Skip to start value */

    for (i = 1; i < vno; i++) {
        p = memchr(pos,U_VALUE_MARK, bytes);
        if (p == NULL) /* No such value */
        {
            vm = vno - i;
            if (svno > 1)
                sm = svno - 1;
            pos += bytes;
            bytes = 0;
            goto done;
        }
        bytes -= (1 + p - pos);
        pos = p + 1;
    }

    p = memchr(pos,U_VALUE_MARK, bytes);
    if (p != NULL)
        bytes = p - pos; /* Length of value, including end mark */

    if (svno == 0)
        goto done; /* Replacing whole value */

    if (svno < 1) /* Appending new subvalue */
    {
        if (p != NULL)
            pos = p; /* 0553 */
        else
            pos += bytes; /* 0553 */
        if (bytes)
            sm = 1; /* 0553 */
        bytes = 0;
        goto done;
    }

    /* Skip to start subvalue */

    for (i = 1; i < svno; i++) {
        p = memchr(pos, U_SUBVALUE_MARK, bytes);
        if (p == NULL) /* No such subvalue */
        {
            sm = svno - i;
            pos += bytes;
            bytes = 0;
            goto done;
        }
        bytes -= (1 + p - pos);
        pos = p + 1;
    }

    p = memchr(pos, U_SUBVALUE_MARK, bytes);
    if (p != NULL)
        bytes = p - pos; /* Length of subvalue, including end mark */

done:
    /* Now construct new string with 'bytes' bytes omitted starting at 'pos',
      inserting fm, vm and sm marks and new data                             */

    new_len = src_len - bytes + fm + vm + sm + ins_len;
    new_str = malloc(new_len + 1);
    p = new_str;

    n = pos - src; /* Length of leading substring */
    if (n) {
        memcpy(p, src, n);
        p += n;
    }

    while (fm--)
        *(p++) =U_FIELD_MARK;
    while (vm--)
        *(p++) =U_VALUE_MARK;
    while (sm--)
        *(p++) = U_SUBVALUE_MARK;

    if (ins_len) {
        memcpy(p, new, ins_len);
        p += ins_len;
    }

    n = src_len - (bytes + n); /* Length of trailing substring */
    if (n) {
        memcpy(p, pos + bytes, n);
        p += n;
    }

    *p = '\0';
    return new_str;
}

/* ======================================================================
   SDRespond()  -  Respond to request for input                           */

DLLEntry  char* SDRespond(char* response, int* err) {
    int32_t reply_len = 0;
    char* reply;

    if (context_error(CX_EXECUTING))
        goto exit_sdrespond;

    if (!message_pair(SrvrRespond, response, strlen(response))) {
        goto exit_sdrespond;
    }

    switch (session[session_idx].server_error) {
    case SV_OK:
        session[session_idx].context = CX_CONNECTED;
        /* fall through */

    case SV_PROMPT:
        reply_len = buff_bytes - offsetof(INBUFF, data.execute.reply);
        break;

    case SV_ERROR: /* Probably SDRespond() used when not expected */
        break;

    case SV_ON_ERROR:
        session[session_idx].context = CX_CONNECTED;
        Abort("EXECUTE generated an abort event", TRUE);
        break;
    }

exit_sdrespond:
    reply = malloc(reply_len + 1);
    if (reply_len > 0) /* buff may be NULL on a pre-network failure */
        memcpy(reply, buff->data.execute.reply, reply_len);
    reply[reply_len] = '\0';
    *err = session[session_idx].server_error;
    return reply;
}

/* ======================================================================
   SDSelect()  - Generate select list                                     */

void DLLEntry SDSelect(int fno, int listno) {

    #pragma pack(2)
    struct {
        int16_t fno;
        int16_t listno;
    } packet;
    #pragma pack()

    if (context_error(CX_CONNECTED))
        goto exit_sdselect;

    packet.fno = ShortInt(fno);
    packet.listno = ShortInt(listno);

    if (!message_pair(SrvrSelect, (char*)&packet, sizeof(packet))) {
        goto exit_sdselect;
    }

    switch (session[session_idx].server_error) {
    case SV_OK:
        break;

    case SV_ON_ERROR:
        Abort("Select generated an abort event", TRUE);
        break;
    }

exit_sdselect:
    return;
}

/* ======================================================================
   SDSelectIndex()  - Generate select list from index entry               */

void DLLEntry SDSelectIndex(int16_t fno,
    char* index_name,
    char* index_value,
    int16_t listno) {
    struct {
        int16_t fno;
        int16_t listno;
        int16_t name_len;
        char index_name[255 + 1];
        int16_t data_len_place_holder;       /* Index name is actually... */
        char index_data_place_holder[255 + 1]; /* ...var length */
    } packet;
    int16_t n;
    char* p;

    if (context_error(CX_CONNECTED))
        goto exit_sdselectindex;

    /* Bound the caller-supplied strings to the fixed packet buffers before
       any memcpy, otherwise a long name or value overflows the stack. */
    if ((strlen(index_name) > sizeof(packet.index_name) - 1) ||
        (strlen(index_value) > sizeof(packet.index_data_place_holder) - 1)) {
        session[session_idx].server_error = SV_ELSE;
        session[session_idx].sd_status = ER_BAD_NAME;
        goto exit_sdselectindex;
    }

    packet.fno = ShortInt(fno);
    packet.listno = ShortInt(listno);

    /* Insert index name */

    n = strlen(index_name);
    packet.name_len = ShortInt(n);
    p = packet.index_name;
    memcpy(p, index_name, n);
    p += n;
    if (n & 1)
        *(p++) = '\0';

    /* Insert index value */

    n = strlen(index_value); /* 0267 */
    *((int16_t*)p) = ShortInt(n);
    p += sizeof(int16_t);
    memcpy(p, index_value, n);
    p += n;
    if (n & 1)
        *(p++) = '\0';

    if (!message_pair(SrvrSelectIndex, (char*)&packet, p - (char*)&packet)) {
        goto exit_sdselectindex;
    }

    switch (session[session_idx].server_error) {
    case SV_OK:
        break;

    case SV_ON_ERROR:
        Abort("SelectIndex generated an abort event", TRUE);
        break;
    }

exit_sdselectindex:
    return;
}

/* ======================================================================
   SDSelectLeft()  - Scan index position to left
   SDSelectRight()  - Scan index position to right                        */

DLLEntry  char* SDSelectLeft(int16_t fno, char* index_name, int16_t listno) {
    return SelectLeftRight(fno, index_name, listno, SrvrSelectLeft);
}

DLLEntry  char* SDSelectRight(int16_t fno,
    char* index_name,
    int16_t listno) {
    return SelectLeftRight(fno, index_name, listno, SrvrSelectRight);
}

Private char* SelectLeftRight(int16_t fno,
    char* index_name,
    int16_t listno,
    int16_t mode) {
    int32_t key_len = 0;
    char* key;
    struct {
        int16_t fno;
        int16_t listno;
        char index_name[255 + 1];
    } packet;
    int16_t n;
    char* p;

    if (!context_error(CX_CONNECTED)) {
        if (strlen(index_name) > sizeof(packet.index_name) - 1) {
            /* Too long for the fixed packet buffer; fail rather than overflow. */
            session[session_idx].server_error = SV_ELSE;
            session[session_idx].sd_status = ER_BAD_NAME;
        } else {
            packet.fno = ShortInt(fno);
            packet.listno = ShortInt(listno);

            /* Insert index name */

            n = strlen(index_name);
            p = packet.index_name;
            memcpy(p, index_name, n);
            p += n;

            if (message_pair(mode, (char*)&packet, p - (char*)&packet)) {
                switch (session[session_idx].server_error) {
                case SV_OK:
                    key_len = buff_bytes - offsetof(INBUFF, data.selectleft.key);
                    break;

                case SV_ON_ERROR:
                    Abort("SelectLeft / SelectRight generated an abort event", TRUE);
                    break;
                }
            }
        }
    }

    key = malloc(key_len + 1);
    if (key_len > 0) /* buff may be NULL on a pre-network failure */
        memcpy(key, buff->data.selectleft.key, key_len);
    key[key_len] = '\0';
    return key;
}

/* ======================================================================
   SDSetLeft()  - Set index position at extreme left
   SDSetRight()  - Set index position at extreme right                    */

void DLLEntry SDSetLeft(int16_t fno, char* index_name) {
    SetLeftRight(fno, index_name, SrvrSetLeft);
}

void DLLEntry SDSetRight(int16_t fno, char* index_name) {
    SetLeftRight(fno, index_name, SrvrSetRight);
}

Private void SetLeftRight(int16_t fno, char* index_name, int16_t mode) {
    struct {
        int16_t fno;
        char index_name[255 + 1];
    } packet;
    int16_t n;
    char* p;

    if (!context_error(CX_CONNECTED)) {
        if (strlen(index_name) > sizeof(packet.index_name) - 1) {
            /* Too long for the fixed packet buffer; fail rather than overflow. */
            session[session_idx].server_error = SV_ELSE;
            session[session_idx].sd_status = ER_BAD_NAME;
        } else {
            packet.fno = ShortInt(fno);

            /* Insert index name */

            n = strlen(index_name);
            p = packet.index_name;
            memcpy(p, index_name, n);
            p += n;

            if (message_pair(mode, (char*)&packet, p - (char*)&packet)) {
                switch (session[session_idx].server_error) {
                case SV_OK:
                    break;

                case SV_ON_ERROR:
                    Abort("SetLeft / SetRight generated an abort event", TRUE);
                    break;
                }
            }
        }
    }
}


/* ======================================================================
   SDSetSession()  -  Set session index                                   */
DLLEntry int SDSetSession(int idx) {
  if ((idx < 0) || (idx >= MAX_SESSIONS) ||
      (session[idx].context == CX_DISCONNECTED)) {
    return FALSE;
  }
  session_idx = idx;
  return TRUE;
}

/* ======================================================================
   SDStatus()  -  Return STATUS() value                                   */
DLLEntry  int SDStatus() {
  return session[session_idx].sd_status;
}

/* ======================================================================
   SDWrite()  -  Write record                                             */
DLLEntry void SDWrite(int fno, char* id, char* data) {
  write_record(SrvrWrite, fno, id, data);
}

/* ======================================================================
   SDWriteu()  -  Write record, retaining lock                            */
DLLEntry void SDWriteu(int fno, char* id, char* data) {
  write_record(SrvrWriteu, fno, id, data);
}

/* ======================================================================
   context_error()  - Check for appropriate context                       */

Private bool context_error(int16_t expected) {
    /* the char* p throws a warning about the variable being set, but never used.
   * The annoying thing about this is that p is being set to useful values,
   * but that detailed information is never making it out of the routine.
   * It appears that many of these extended descriptions are also living
   * in sdclient.c where they're used as part of a Windows message box
   * output.  I'm going to comment out the use here in order to clean up the
   * error, but some method of leveraging this extended information should be
   * developed. -gwb 23Feb20
   */
   // char* p; triggers a variable set but never used warning.

    if (session[session_idx].context != expected) {
        session[session_idx].server_error = SV_ECONTXT;
        switch (session[session_idx].context) {
        case CX_DISCONNECTED:
            //   p = "A server function has been attempted when no connection has been "
            //       "established";
            break;

        case CX_CONNECTED:
            switch (expected) {
            case CX_DISCONNECTED:
                // p = "A function has been attempted which is not allowed when a "
                //     "connection has been established";
                break;

            case CX_EXECUTING:
                // p = "Cannot send a response or end a command when not executing a "
                //     "server command";
                break;
            }
            break;

        case CX_EXECUTING:
            //   p = "A new server function has been attempted while executing a server "
            //       "command";
            break;

        default:
            // p = "A function has been attempted in the wrong context";
            break;
        }

        return TRUE;
    }

    return FALSE;
}

/* ====================================================================== */

Private void delete_record(int16_t mode, int fno, char* id) {
    int id_len;

    #pragma pack(2)
    struct {
        int16_t fno;
        char id[MAX_ID_LEN];
    } packet;
    #pragma pack()

    if (context_error(CX_CONNECTED))
        goto exit_delete;

    packet.fno = ShortInt(fno);

    id_len = strlen(id);
    if ((id_len < 1) || (id_len > MAX_ID_LEN)) {
        session[session_idx].server_error = SV_ON_ERROR;
        session[session_idx].sd_status = ER_IID;
    }
    else {
        memcpy(packet.id, id, id_len);

        if (!message_pair(mode, (char*)&packet, id_len + 2)) {
            goto exit_delete;
        }
    }

    switch (session[session_idx].server_error) {
    case SV_OK:
        break;

    case SV_ON_ERROR:
        Abort("DELETE generated an abort event", TRUE);
        break;

    case SV_LOCKED:
    case SV_ELSE:
    case SV_ERROR:
        break;
    }

exit_delete:
    return;
}

/* ======================================================================
   read_record()  -  Common path for READ, READL and READU                */
Private char* read_record(int fno, char* id, int* err, int mode) {
    /* 20240301 mab status must be initialized */
    int32_t status = 0;
    int32_t rec_len = 0;
    int id_len;
    char* rec;

#pragma pack(2)
    struct {
        int16_t fno;
        char id[MAX_ID_LEN];
    } packet;
#pragma pack() 

    if (context_error(CX_CONNECTED))
        goto exit_read;
    id_len = strlen(id);
    if ((id_len < 1) || (id_len > MAX_ID_LEN)) {
        session[session_idx].sd_status = ER_IID;
        status = SV_ON_ERROR;
        goto exit_read;
    }
    packet.fno = ShortInt(fno);
    memcpy(packet.id, id, id_len);
    if (!message_pair(mode, (char*)&packet, id_len + 2)) {
        goto exit_read;
    }
    switch (session[session_idx].server_error) {
    case SV_OK:
        rec_len = buff_bytes - offsetof(INBUFF, data.read.rec);
        break;
    case SV_ON_ERROR:
        Abort("Read generated an abort event", TRUE);
        break;
    case SV_LOCKED:
    case SV_ELSE:
    case SV_ERROR:
        break;
    }
exit_read:
    status = session[session_idx].server_error;

    rec = malloc(rec_len + 1);
    if (rec_len > 0) /* buff may be NULL on a pre-network failure */
        memcpy(rec, buff->data.read.rec, rec_len);
    rec[rec_len] = '\0';
    *err = status;
    return rec;
}

/* ====================================================================== */

Private void write_record(int16_t mode, int16_t fno, char* id, char* data) {
    int id_len;
    size_t data_len;
    int bytes;
    INBUFF* q;
#pragma pack(2)
    struct PACKET {
        int16_t fno;
        int16_t id_len;
        char id[1];
    };
#pragma pack()
    if (context_error(CX_CONNECTED))
        goto exit_write;
    id_len = strlen(id);
    if ((id_len < 1) || (id_len > MAX_ID_LEN)) {
        Abort("Illegal record id", FALSE);
        session[session_idx].sd_status = ER_IID;
        goto exit_write;
    }
    data_len = strlen(data);
    if (!valid_record_size(data_len)) {
        Abort("Illegal record size", FALSE);
        session[session_idx].sd_status = ER_MAX_STRING;
        goto exit_write;
    }
    /* Ensure buffer is big enough for this record */
    bytes = sizeof(struct PACKET) + id_len + data_len;
    if (bytes >= buff_size) /* Must reallocate larger buffer */
    {
        bytes = grow_buffer_size(bytes);
        q = (INBUFF*)malloc(bytes);
        if (q == NULL) {
            Abort("Insufficient memory", FALSE);
            session[session_idx].sd_status = ER_SRVRMEM;
            goto exit_write;
        }
        free(buff);
        buff = q;
        buff_size = bytes;
    }
    /* Set up outgoing packet */
    ((struct PACKET*)buff)->fno = ShortInt(fno);
    ((struct PACKET*)buff)->id_len = ShortInt(id_len);
    memcpy(((struct PACKET*)buff)->id, id, id_len);
    memcpy(((struct PACKET*)buff)->id + id_len, data, data_len);
    if (!message_pair(mode, (char*)buff,
        offsetof(struct PACKET, id) + id_len + data_len)) {
        goto exit_write;
    }
    switch (session[session_idx].server_error) {
    case SV_OK:
        break;
    case SV_ON_ERROR:
        Abort("Write generated an abort event", TRUE);
        break;
    case SV_LOCKED:
    case SV_ELSE:
    case SV_ERROR:
        break;
    }
exit_write:
    return;
}

/* ====================================================================== */
Private bool GetResponse() {
    if (!read_packet())
        return FALSE;
    if (session[session_idx].server_error == SV_ERROR) {
        /* The error packet itself carries no text; request it from the server.
           read_packet() below overwrites server_error with the GetError reply's
           own (successful) status, so on success we restore SV_ERROR for the
           caller. If the fetch fails, keep a usable fallback message rather than
           copying stale buffer contents (the previous code did the copy
           unconditionally, discarding the fallback). */
        strcpy_s(session[session_idx].sderror, sizeof(session[0].sderror),
                 "Unable to retrieve error text");
        if (!write_packet(SrvrGetError, NULL, 0) || !read_packet())
            return FALSE;
        session[session_idx].server_error = SV_ERROR;
        strcpy_s(session[session_idx].sderror, sizeof(session[0].sderror),
                 buff->data.error.text);
        return TRUE;
    }
    return TRUE;
}

/* ====================================================================== */
Private bool valid_record_size(size_t bytes) {
    return bytes <= MAX_STRING_SIZE;
}


/* ====================================================================== */

/* NOTE: Abort() only reports the error (to stderr and, for the callers that
   read it, via the network buffer). Unlike the original QM client it does NOT
   longjmp/terminate the operation, so callers that must stop have to return
   themselves after calling it. */
Private void Abort(char* msg, bool use_response) {
    char abort_msg[1024 + 1];
    int n;
    int avail;
    char* p;
    strcpy_s(abort_msg, 1024 + 1, msg);
    if (use_response) {
        n = buff_bytes - offsetof(INBUFF, data.abort.message);
        if (n > 0) {
            p = abort_msg + strlen(abort_msg);
            /* Clamp the server-supplied text to the space left in abort_msg,
               reserving room for the '\r' separator and the NUL terminator. */
            avail = (int)sizeof(abort_msg) - (int)(p - abort_msg) - 2;
            if (n > avail)
                n = avail;
            if (n > 0) {
                *(p++) = '\r';
                memcpy(p, buff->data.abort.message, n);
                *(p + n) = '\0';
            }
        }
    }
    fprintf(stderr, "%s\n", abort_msg);
}

/* ====================================================================== */

Private char* memstr(char* str, char* substr, int str_len, int substr_len) {
    char* p;

    while (str_len != 0) {
        p = memchr(str, *substr, str_len);
        if (p == NULL)
            break;

        str_len -= p - str;
        if (str_len < substr_len)
            break;

        if (memcmp(p, substr, substr_len) == 0)
            return p;

        str = p + 1;
        str_len--;
    }

    return NULL;
}

/* ======================================================================
   match_template()  -  Match string against template                     */

Private bool match_template(
    char* string,
    char* template,
    int16_t component, /* Current component number - 1 (incremented) */
    int16_t return_component /* Required component number */) {


    bool not;
    int16_t n;
    int16_t m;
    int16_t z;
    char* p;
    char delimiter;
    char* start;

    while (*template != '\0') {
        component++;
        if (component == return_component)
            component_start = string;
        else if (component == return_component + 1)
            component_end = string;

        start = template;

        if (*template == '~') {
            not = TRUE;
            template++;
        }
        else
            not = FALSE;

        if (IsDigit(*template)) {
            n = 0;
            do {
                n = (n * 10) + (*(template++) - '0');
            } while (IsDigit(*template));

            switch (UpperCase(*(template++))) {
            case '\0': /* String longer than template */
                /* 0115 rewritten */
                n = --template - start;
                if (n == 0)
                    return FALSE;
                /* encapsulating the !memcmp() in parens removes a compiler
                 * warning about ambiguity.
                 */
                if ((!memcmp(start, string, n)) == not)
                    return FALSE;
                string += n;
                break;

            case 'A': /* nA  Alphabetic match */
                if (n) {
                    while (n--) {
                        if (*string == '\0')
                            return FALSE;
                        if ((IsAlpha(*string) != 0) == not)
                            return FALSE;
                        string++;
                    }
                }
                else /* 0A */
                {
                    if (*template != '\0') /* Further template items exist */
                    {
                        /* Match as many as possible further chaarcters */

                        for (z = 0, p = string;; z++, p++) {
                            if ((*p == '\0') || ((IsAlpha(*p) != 0) == not))
                                break;
                        }

                        /* z now holds number of contiguous alphabetic characters ahead
                           of current position. Starting one byte after the final
                           alphabetic character, backtrack until the remainder of the
                           string matches the remainder of the template.               */

                        for (p = string + z; z-- >= 0; p--) {
                            if (match_template(p, template, component, return_component)) {
                                goto match_found;
                            }
                        }
                        return FALSE;
                    }
                    else {
                        while ((*string != '\0') && ((IsAlpha(*string) != 0) != not)) {
                            string++;
                        }
                    }
                }
                break;

            case 'N': /* nN  Numeric match */
                if (n) {
                    while (n--) {
                        if (*string == '\0')
                            return FALSE;
                        if ((IsDigit(*string) != 0) == not)
                            return FALSE;
                        string++;
                    }
                }
                else /* 0N */
                {
                    if (*template != '\0') /* Further template items exist */
                    {
                        /* Match as many as possible further chaarcters */

                        for (z = 0, p = string;; z++, p++) {
                            if ((*p == '\0') || ((IsDigit(*p) != 0) == not))
                                break;
                        }

                        /* z now holds number of contiguous numeric characters ahead
                           of current position. Starting one byte after the final
                           numeric character, backtrack until the remainder of the
                           string matches the remainder of the template.               */

                        for (p = string + z; z-- >= 0; p--) {
                            if (match_template(p, template, component, return_component)) {
                                goto match_found;
                            }
                        }
                        return FALSE;
                    }
                    else {
                        while ((*string != '\0') && ((IsDigit(*string) != 0) != not)) {
                            string++;
                        }
                    }
                }
                break;

            case 'X': /* nX  Unrestricted match */
                if (n) {
                    while (n--) {
                        if (*(string++) == '\0')
                            return FALSE;
                    }
                }
                else /* 0X */
                {
                    if (*template != '\0') /* Further template items exist */
                    {
                        /* Match as few as possible further characters */

                        do {
                            if (match_template(string, template, component,
                                return_component)) {
                                goto match_found;
                            }
                        } while (*(string++) != '\0');
                        return FALSE;
                    }
                    goto match_found;
                }
                break;

            case '-': /* Count range */
                if (!IsDigit(*template))
                    return FALSE;
                m = 0;
                do {
                    m = (m * 10) + (*(template++) - '0');
                } while (IsDigit(*template));
                m -= n;
                if (m < 0)
                    return FALSE;

                switch (UpperCase(*(template++))) {
                case '\0': /* String longer than template */
                    n = --template - start;
                    if (n) /* We have found a trailing unquoted literal */
                    {
                        if ((memcmp(start, string, n) == 0) != not)
                            return TRUE;
                    }
                    return FALSE;

                case 'A': /* n-mA  Alphabetic match */
                    /* Match n alphabetic items */

                    while (n--) {
                        if (*string == '\0')
                            return FALSE;
                        if ((IsAlpha(*string) != 0) == not)
                            return FALSE;
                        string++;
                    }

                    /* We may match up to m further alphabetic characters but must
                        also match as many as possible.  Check how many alphabetic
                        characters there are (up to m) and then backtrack trying
                        matches against the remaining template (if any).           */

                    for (z = 0, p = string; z < m; z++, p++) {
                        if ((*p == '\0') || ((IsAlpha(*p) != 0) == not))
                            break;
                    }

                    /* z now holds max number of matchable characters.
                        Try match at each of these positions and also at the next
                        position (Even if it is the end of the string)            */

                    if (*template != '\0') /* Further template items exist */
                    {
                        for (p = string + z; z-- >= 0; p--) {
                            if (match_template(p, template, component,
                                return_component)) {
                                goto match_found;
                            }
                        }
                        return FALSE;
                    }
                    else
                        string += z;
                    break;

                case 'N': /* n-mN  Numeric match */
                    /* Match n numeric items */

                    while (n--) {
                        if (*string == '\0')
                            return FALSE;
                        if ((IsDigit(*string) != 0) == not)
                            return FALSE;
                        string++;
                    }

                    /* We may match up to m further numeric characters but must
                        also match as many as possible.  Check how many numeric
                        characters there are (up to m) and then backtrack trying
                        matches against the remaining template (if any).           */

                    for (z = 0, p = string; z < m; z++, p++) {
                        if ((*p == '\0') || ((IsDigit(*p) != 0) == not))
                            break;
                    }

                    /* z now holds max number of matchable characters.
                        Try match at each of these positions and also at the next
                        position (Even if it is the end of the string)            */

                    if (*template != '\0') /* Further template items exist */
                    {
                        for (p = string + z; z-- >= 0; p--) {
                            if (match_template(p, template, component,
                                return_component)) {
                                goto match_found;
                            }
                        }
                        return FALSE;
                    }
                    else
                        string += z;
                    break;

                case 'X': /* n-mX  Unrestricted match */
                    /* Match n items of any type */

                    while (n--) {
                        if (*(string++) == '\0')
                            return FALSE;
                    }

                    /* Match as few as possible up to m further characters */

                    if (*template != '\0') {
                        while (m--) {
                            if (match_template(string, template, component,
                                return_component)) {
                                goto match_found;
                            }
                            string++;
                        }
                        return FALSE;
                    }
                    else {
                        if ((signed int)strlen(string) > m)
                            return FALSE;
                        goto match_found;
                    }

                default:
                    /* We have found an unquoted literal */
                    n = --template - start;
                    if ((memcmp(start, string, n) == 0) == not)
                        return FALSE;
                    string += n;
                    break;
                }
                break;

            default:
                /* We have found an unquoted literal */
                n = --template - start;
                if ((memcmp(start, string, n) == 0) == not)
                    return FALSE;
                string += n;
                break;
            }
        }
        else if (memcmp(template, "...", 3) == 0) /* ... same as 0X */
        {
            template += 3;
            if (not)
                return FALSE;
            if (*template != '\0') /* Further template items exist */
            {
                /* Match as few as possible further characters */

                while (*string != '\0') {
                    if (match_template(string, template, component, return_component)) {
                        goto match_found;
                    }
                    string++;
                }
                return FALSE;
            }
            goto match_found;
        }
        else /* Must be literal text item */
        {
            delimiter = *template;
            if ((delimiter == '\'') || (delimiter == '"')) /* Quoted literal */
            {
                template++;
                p = strchr(template, (char)delimiter);
                if (p == NULL)
                    return FALSE;
                n = p - template;
                if (n) {
                    if ((memcmp(template, string, n) == 0) == not)
                        return FALSE;
                    string += n;
                }
                template += n + 1;
            }
            else /* Unquoted literal. Treat as single character */
            {
                if ((*(template++) == *(string++)) == not)
                    return FALSE;
            }
        }
    }

    if (*string != '\0')
        return FALSE; /* String longer than template */

match_found:
    return TRUE;
}


/* ======================================================================
   message_pair()  -  Send packet and receive response                    */
Private bool message_pair(int type, char* data, int32_t bytes) {
    if (write_packet(type, data, bytes) && GetResponse())
        return TRUE;
    session[session_idx].server_error = SV_EMSG_PAIR;
    return FALSE;
}
/* ====================================================================== */

Private char* NullString() {
    char* p;
    p = malloc(1);
    *p = '\0';
    return p;
}

/* ======================================================================
   OpenSocket()  -  Open connection to server                            */
Private bool OpenSocket(char* host, int16_t port) {
    bool status = FALSE;
    WSADATA wsadata;
    u_int32_t nInterfaceAddr;
    struct sockaddr_in sock_addr;
    int nPort;
    struct hostent* hostdata;
    char ack_buff;
    int n;
    unsigned int n1, n2, n3, n4;
    if (port < 0)
        port = 4243;
    /* Start Winsock up */
    if (WSAStartup(MAKEWORD(2, 2), &wsadata) != 0) {
        sprintf_s(session[session_idx].sderror, sizeof(session[0].sderror),
                  "WSAStartup error");
        goto exit_opensocket;
    }
    session[session_idx].winsock_started = TRUE;
    if ((sscanf(host, "%u.%u.%u.%u", &n1, &n2, &n3, &n4) == 4) && (n1 <= 255) &&
        (n2 <= 255) && (n3 <= 255) && (n4 <= 255)) {
        /* Looks like an IP address */
        nInterfaceAddr = inet_addr(host);
    }
    else {
        hostdata = gethostbyname(host);
        if (hostdata == NULL) {
            net_error("gethostbyname()");
            goto exit_opensocket;
        }
        nInterfaceAddr = *((int32_t*)(hostdata->h_addr));
    }
    nPort = htons(port);
    session[session_idx].sock = socket(AF_INET, SOCK_STREAM, 0);
    if (session[session_idx].sock == INVALID_SOCKET) {
        net_error("socket()");
        goto exit_opensocket;
    }
    sock_addr.sin_family = AF_INET;
    sock_addr.sin_addr.s_addr = nInterfaceAddr;
    sock_addr.sin_port = nPort;
    if (connect(session[session_idx].sock, (struct sockaddr*)&sock_addr, sizeof(sock_addr))) {
        net_error("connect()");
        goto exit_opensocket;
    }
    n = TRUE;
    if (setsockopt(session[session_idx].sock, IPPROTO_TCP, TCP_NODELAY,
                   (char*)&n, sizeof(int)) == SOCKET_ERROR) {
        net_error("setsockopt(TCP_NODELAY)");
        goto exit_opensocket;
    }
    /* Wait for an Ack character to arrive before we assume the connection
      to be open and working. This is necessary because Linux loses anything
      we send before the SD process is up and running.                       */
    do {
        n = recv(session[session_idx].sock, &ack_buff, 1, 0);
        if (n == 0) { /* orderly close during handshake: WSAGetLastError stale */
            snprintf(session[session_idx].sderror,
                     sizeof(session[session_idx].sderror),
                     "Connection closed by server");
            goto exit_opensocket;
        }
        if (n == SOCKET_ERROR) {
            net_error("recv()"); /* Socket only path */
            goto exit_opensocket;
        }
    } while (ack_buff != '\x06');
    status = 1;
exit_opensocket:
    return status;
}

/* ======================================================================
   CloseSocket()  -  Close connection to server                          */
Private bool CloseSocket() {
    bool status = TRUE;

    /* A local session holds a pipe rather than a socket.  Winsock was never
       started for it, so there is nothing else here to unwind.              */

    if (session[session_idx].hPipe != INVALID_HANDLE_VALUE) {
        DisconnectNamedPipe(session[session_idx].hPipe);
        CloseHandle(session[session_idx].hPipe);
        session[session_idx].hPipe = INVALID_HANDLE_VALUE;
        session[session_idx].is_local = FALSE;
    }

    if (session[session_idx].sock != INVALID_SOCKET) {
        if (closesocket(session[session_idx].sock) == SOCKET_ERROR) {
            net_error("closesocket()");
            status = FALSE;
        }
        session[session_idx].sock = INVALID_SOCKET;
    }
    if (session[session_idx].winsock_started) {
        if (WSACleanup() == SOCKET_ERROR) {
            net_error("WSACleanup()");
            status = FALSE;
        }
        session[session_idx].winsock_started = FALSE;
    }
    return status;
}
/* ======================================================================
   abandon_connection()  -  A response that cannot be consumed (bad length, or
   no buffer for the declared body) leaves the unread body in the stream. Drop
   the connection so a later call does not read residual bytes as a new packet
   header. Any diagnostic already in sderror is preserved.                    */
Private void abandon_connection(void) {
    (void)CloseSocket();
    session[session_idx].context = CX_DISCONNECTED;
}
/* ======================================================================
   NetErr                                                               */
static void net_error(char* prefix) {
    snprintf(session[session_idx].sderror,
             sizeof(session[session_idx].sderror),
             "Winsock error %d from %s", WSAGetLastError(), prefix);
}
/* ======================================================================
   transport_recv()  -  Read from whichever transport this session uses.

   Returns the byte count, 0 for an orderly close by the peer, or SOCKET_ERROR
   for a failure, so callers keep the recv() conventions they already handle.
   A named pipe reports the far end closing as ERROR_BROKEN_PIPE, which is the
   same condition as a zero length recv() on a socket.                        */

Private int transport_recv(char* p, int len) {
    DWORD n;

    if (!session[session_idx].is_local)
        return recv(session[session_idx].sock, p, len, 0);

    if (!ReadFile(session[session_idx].hPipe, p, (DWORD)len, &n, NULL)) {
        DWORD err = GetLastError();

        if (err == ERROR_BROKEN_PIPE)
            return 0; /* Orderly close, same meaning as a zero length recv() */

        /* Record it here while the code is still current; the caller reports
           socket failures through WSAGetLastError(), which says nothing about
           a pipe.                                                            */
        snprintf(session[session_idx].sderror,
                 sizeof(session[session_idx].sderror),
                 "Error %d reading from pipe", (int)err);
        return SOCKET_ERROR;
    }

    return (int)n;
}

/* ======================================================================
   transport_error()  -  Report a read failure for the active transport.
   The local path has already filled in sderror inside transport_recv().    */

Private void transport_error(char* prefix) {
    if (!session[session_idx].is_local)
        net_error(prefix);
}

/* ======================================================================
   transport_send()  -  Write to whichever transport this session uses.

   Loops until everything is written.  WriteFile() on a byte mode pipe can
   report a short write for the same reason send() can, and a partial packet
   would desynchronise the protocol.                                          */

Private bool transport_send(const char* data, int32_t bytes) {
    int32_t sent = 0;
    DWORD n;

    if (!session[session_idx].is_local)
        return send_all(session[session_idx].sock, data, bytes);

    while (sent < bytes) {
        if (!WriteFile(session[session_idx].hPipe, data + sent,
                       (DWORD)(bytes - sent), &n, NULL)) {
            snprintf(session[session_idx].sderror,
                     sizeof(session[session_idx].sderror),
                     "Error %d writing to pipe", (int)GetLastError());
            return FALSE;
        }

        if (n == 0) { /* No progress; treat as a dead pipe */
            snprintf(session[session_idx].sderror,
                     sizeof(session[session_idx].sderror),
                     "Send made no progress");
            return FALSE;
        }

        sent += (int32_t)n;
    }

    return TRUE;
}

/* ======================================================================
   transport_live()  -  Is there a usable connection to abandon or use?     */

Private bool transport_live(void) {
    if (session[session_idx].is_local)
        return session[session_idx].hPipe != INVALID_HANDLE_VALUE;

    return session[session_idx].sock != INVALID_SOCKET;
}

/* ======================================================================
   read_packet()  -  Read a SD data packet                                */
Private bool read_packet() {
    int rcvd_bytes;       /* Length of received packet fragment */
    int32_t packet_bytes; /* Total length of incoming packet */
    int rcv_len;
    int32_t n;
    char* p;
    /* 0272 restructured */
    struct {
        int32_t packet_length;
#pragma pack(2)
        int16_t server_error;
        int32_t status;
#pragma pack()
    } in_packet_header;


    if (!transport_live())
        return FALSE; /* no live connection to abandon */
    /* Read packet header */
    p = (char*)&in_packet_header;
    buff_bytes = 0;
    do {
        rcv_len = IN_PKT_HDR_BYTES - buff_bytes;
        rcvd_bytes = transport_recv(p, rcv_len);
        if (rcvd_bytes == 0) { /* orderly close: WSAGetLastError is stale */
            snprintf(session[session_idx].sderror,
                     sizeof(session[session_idx].sderror),
                     "Connection closed by server");
            goto fail;
        }
        if (rcvd_bytes == SOCKET_ERROR) {
            transport_error("recv()");
            goto fail;
        }
        buff_bytes += rcvd_bytes;
        p += rcvd_bytes;
    } while (buff_bytes < IN_PKT_HDR_BYTES);
    if (srvr_debug != NULL)
        debug((unsigned char*)&in_packet_header, IN_PKT_HDR_BYTES);
    /* Validate the server-supplied length before trusting it for allocation
       or reading: it must at least cover the header and stay within a sane
       maximum. */
    if (!valid_packet_length(in_packet_header.packet_length)) {
        snprintf(session[session_idx].sderror,
                 sizeof(session[session_idx].sderror),
                 "Invalid response packet length (%ld)",
                 (long)in_packet_header.packet_length);
        goto fail;
    }
    /* Calculate remaining bytes to read */
    packet_bytes = in_packet_header.packet_length - IN_PKT_HDR_BYTES;
    if (srvr_debug != NULL) {
        fprintf(srvr_debug, "IN (%d bytes)\n", packet_bytes);
        fflush(srvr_debug);
    }
    if (packet_bytes >= buff_size) /* Must reallocate larger buffer */
    {
        /* Allocate the replacement before freeing the old buffer, so a failed
           allocation does not leave buff dangling with a stale buff_size. */
        INBUFF* newbuff;
        n = grow_buffer_size(packet_bytes);
        newbuff = (INBUFF*)malloc(n);
        if (newbuff == NULL) {
            snprintf(session[session_idx].sderror,
                     sizeof(session[session_idx].sderror),
                     "Insufficient memory for response buffer");
            goto fail;
        }
        free(buff);
        buff = newbuff;
        buff_size = n;
        if (srvr_debug != NULL) {
            fprintf(srvr_debug, "Resized buffer to %d bytes\n", buff_size);
            fflush(srvr_debug);
        }
    }
    /* Read data part of packet */
    p = (char*)(buff);
    buff_bytes = 0;
    while (buff_bytes < packet_bytes) {
        rcv_len = min(buff_size - buff_bytes, 16384);
        rcvd_bytes = transport_recv(p, rcv_len);
        if (rcvd_bytes == 0) { /* orderly close: WSAGetLastError is stale */
            snprintf(session[session_idx].sderror,
                     sizeof(session[session_idx].sderror),
                     "Connection closed by server");
            goto fail;
        }
        if (rcvd_bytes == SOCKET_ERROR) {
            transport_error("recv()");
            goto fail;
        }
        buff_bytes += rcvd_bytes;
        p += rcvd_bytes;
    }
    ((char*)(buff))[buff_bytes] = '\0';
    if (srvr_debug != NULL)
        debug((unsigned char*)buff, buff_bytes);
    session[session_idx].server_error = in_packet_header.server_error;
    session[session_idx].sd_status = in_packet_header.status;
    return TRUE;
fail:
    /* Any failure here means the response could not be fully/validly consumed,
       so the stream is desynchronized and the socket may be dead. Abandon the
       connection so SDConnected() reports the truth and no later call reuses
       a dead or desynced session. */
    abandon_connection();
    return FALSE;
}

/* ======================================================================
   send_all()  -  send() may transmit fewer bytes than requested on a blocking
   socket for large payloads. Loop until everything is sent so a short send
   does not leave a partial packet on the wire and desync the protocol.      */

Private bool send_all(SOCKET sock, const char* data, int32_t bytes) {
    int32_t sent = 0;
    int n;
    while (sent < bytes) {
        n = send(sock, data + sent, bytes - sent, 0);
        if (n == SOCKET_ERROR) {
            net_error("send()");
            return FALSE;
        }
        if (n <= 0) { /* no progress; WSAGetLastError would be stale */
            snprintf(session[session_idx].sderror,
                     sizeof(session[session_idx].sderror),
                     "Send made no progress");
            return FALSE;
        }
        sent += n;
    }
    return TRUE;
}

/* ======================================================================
   write_packet()  -  Send SD data packet  from  sdclient                 */

Private bool write_packet(int type,
    char* data,
    int32_t bytes) {
#pragma pack(2)
    struct {
        int32_t length;
        int16_t type;
    } packet_header;
#pragma pack()

#define PKT_HDR_BYTES 6

    if (!transport_live())
        return FALSE; /* no live connection to abandon */

    packet_header.length = bytes + PKT_HDR_BYTES; /* 0272 */
    packet_header.type = type;
    if (!transport_send((char*)&packet_header, PKT_HDR_BYTES))
        goto fail; /* transport_send() has set sderror */

    if (srvr_debug != NULL) {
        fprintf(srvr_debug, "OUT (%d bytes). Type %d\n", packet_header.length,
            (int)packet_header.type);
        fflush(srvr_debug);
    }

    if ((data != NULL) && (bytes > 0)) {
        if (!transport_send(data, bytes))
            goto fail; /* transport_send() has set sderror */

        if (srvr_debug != NULL)
            debug((unsigned char*)data, bytes);
    }

    return TRUE;
fail:
    /* A partial or failed send leaves a truncated request on the wire (or a
       dead socket); abandon the connection so the protocol cannot desync and
       SDConnected() reports the truth. */
    abandon_connection();
    return FALSE;
}

/* ======================================================================
   debug()  -  Debug function                                             */

Private void debug(unsigned char* p, int n) {
    int i;
    int j;
    unsigned char c;
    char s[72 + 1];
    static char hex[] = "0123456789ABCDEF";

    for (i = 0; i < n; i += 16) {
        memset(s, ' ', 72);
        s[72] = '\0';

        s[0] = hex[i >> 12];
        s[1] = hex[(i >> 8) & 0x0F];
        s[2] = hex[(i >> 4) & 0x0F];
        s[3] = hex[i & 0x0F];
        s[4] = ':';
        s[54] = '|';

        for (j = 0; (j < 16) && ((j + i) < n); j++) {
            c = *(p++);
            s[6 + 3 * j] = hex[c >> 4];
            s[7 + 3 * j] = hex[c & 0x0F];
            s[56 + j] = ((c >= 32) && (c < 128)) ? c : '.';
        }

        fprintf(srvr_debug, "%s\n", s);
    }
    fprintf(srvr_debug, "\n");
}

Private void initialise_client() {
  int16_t i;
  /* if buff has been allocated, we have been here once before, skip */
  if (buff == NULL) {
	set_default_character_maps();
	buff_size = 2048;
    buff = (INBUFF*)malloc(buff_size);
	for (i = 0; i < MAX_SESSIONS; i++) {
	  session[i].context = CX_DISCONNECTED;
	  session[i].winsock_started = FALSE;
	  session[i].sderror[0] = '\0';
	  session[i].sock = INVALID_SOCKET;
	  session[i].hPipe = INVALID_HANDLE_VALUE;
	  session[i].is_local = FALSE;
	}
	  /* initialize the arg pointer array for EngCall */
	for (i = 0; i < MAX_ARGS; i++) {
	  CallArgArray[i] = NULL;
	  CallArgArraySz[i] = 0;
	}
  }
}

/* ====================================================================== */
Private bool FindFreeSession() {
  int16_t i;
  /* Find a free session table entry */
  for (i = 0; i < MAX_SESSIONS; i++) {
	if (session[i].context == CX_DISCONNECTED)
	  break;
  }
  if (i == MAX_SESSIONS) {
	/* Must return error via a currently connected session */
	strcpy_s(session[session_idx].sderror, sizeof(session[0].sderror), "Too many sessions");
	return FALSE;
  }
  session_idx = i;
  return TRUE;
}

/* ====================================================================== */

Private void disconnect() {
  int16_t i;
  if (srvr_debug != NULL) {
	fprintf(srvr_debug, "Disconnect session %d \n", session_idx);
    fflush(srvr_debug);
  }
  (void)write_packet(SrvrQuit, NULL, 0);
  (void)CloseSocket();
  session[session_idx].context = CX_DISCONNECTED;
 /* I cannot find where the original transfer buffer "buff" is freed on exit
	So look for connected session, if none, release buffer                */
  for (i = 0; i < MAX_SESSIONS; i++) {
	if (session[i].context != CX_DISCONNECTED)
	  break;
  }

  if (i == MAX_SESSIONS) {
	/* looked at all the sessions and none connected free buff */
	if (buff != NULL) {
	  free(buff);
	  buff = NULL;
	}
   /* free the callx arg buffers if they are still around */
   /* this needs modifing if we go with more than 1 session, see comments at top */
	for (i = 0; i < MAX_ARGS; i++) {
	  if (CallArgArray[i] != NULL ){
		free(CallArgArray[i]);
		CallArgArray[i] = NULL;
		CallArgArraySz[i] = 0;
	}
  }

  }
}

/* #include "ctype.c" */
/* ======================================================================
   Set default_character maps                                             */
void set_default_character_maps() {
    int i;
    int j;
    for (i = 0; i < 256; i++) {
        uc_chars[i] = (char)i;
        lc_chars[i] = (char)i;
        char_types[i] = 0;
    }
    for (i = 'a', j = 'A'; i <= 'z'; i++, j++) {
        uc_chars[i] = j;
        lc_chars[j] = i;
        char_types[i] |= CT_ALPHA;
        char_types[j] |= CT_ALPHA;
    }
    for (i = '0'; i <= '9'; i++) {
        char_types[i] |= CT_DIGIT;
    }
    for (i = 33; i <= 126; i++) {
        char_types[i] |= CT_GRAPH;
    }
    char_types[U_TEXT_MARK] |= CT_MARK;
    char_types[U_SUBVALUE_MARK] |= CT_MARK | CT_DELIM;
    char_types[U_VALUE_MARK] |= CT_MARK | CT_DELIM;
    char_types[U_FIELD_MARK] |= CT_MARK | CT_DELIM;
    char_types[U_ITEM_MARK] |= CT_MARK;
}



/* END-CODE */
