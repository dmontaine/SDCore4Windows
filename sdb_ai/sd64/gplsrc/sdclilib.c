/* SDCLILIB.C
 * SD Client C library
 * Copyright (c) 2007 Ladybridge Systems, All Rights Reserved
 *
 * Licensed under the terms of any of the following licenses at your
 * choice:
 *
 *  - GNU General Public License Version 3 or later (the "GPL")
 *    http://www.gnu.org/licenses/gpl.html
 *
 *  - GNU Lesser General Public License Version 3 or later (the "LGPL")
 *    http://www.gnu.org/licenses/lgpl.html
 *
 * START-HISTORY
 * 31 Dec 23 SD launch - prior history suppressed
 * 20240219  mab Major update to use AF_UNIX socket to talk to sd
 * 20240702  mab add MAX_STING_SIZE test to write
 * rev 0.9.0 mab add Callx GetArg 
 *               log local connections
 *               on local connection, set user / group id to user who forked process
 *               on connectlocal if account fails, disconnect!
 *  Warning: sdclilib does not maintian a storage area for Getarg parameters for each session.
 *  Using Callx will "overwrite" the previous Callx parameters regardless of session number.
 *  A solution would be to add the return call buffers to the session structure....
 *    Or size the pointer array CallArgArray to have a slot for the max number of call args * the max number of sessions
 *    char *    CallArgArray[MAX_ARGS*MAX_SESSIONS]
 *    Then use session_idx*MAX_ARGS as the offset into CallArgArray for the sessions SDCall arguments
 *  I cannot find where the transfer buffer "buff" is freed, need to test for memory leak to see if this is really the case.
 *     For now I have added code to disconnect() to free buff if there are no more remainging active connections.
 *
 * 
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
 * SDConnectLocal()
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
 * SDCallx()
 * SDGetArg()
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

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
/* rev 0.9.0 */
#include <syslog.h>
#include <pwd.h>

#define Public
#include "sddefs.h"
#include "sdnet.h"

void set_default_character_maps(void);

#include <sys/wait.h>
#include "linuxlb.h"
#define NetErr(msg, winerr, lnxerr) net_error(msg, lnxerr)

#define DLLEntry

#define FOPEN_READ_MODE "r"

#define SERVER_PATH     "/tmp/sdsys/sdclient.socket"   /* define our all important UNIX DOMAIN SOCKET */

#include "err.h"
#include "revstamp.h"
#include "sdclient.h"

/* Network data */
Private bool OpenSocket(char* host, int16_t port);
Private bool OpenUDSocket(void);
Private bool CloseSocket(void);
Private bool read_packet(void);
Private bool write_packet(int type, char* data, int32_t bytes);
Private void net_error(char* prefix, int err);
Private void debug(unsigned char* p, int n);
Private void initialise_client(void);
Private bool FindFreeSession(void);
Private void disconnect(void);

typedef struct ARGDATA ARGDATA;
struct ARGDATA {
  int16_t argno;
  int32_t arglen ALIGN2;
  char text[1];
};

/* Packet buffer */
#define BUFF_INCR 4096
typedef struct INBUFF INBUFF;
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
} ALIGN2;

Private INBUFF* buff = NULL;
Private int32_t buff_size;  /* Allocated size of buffer */
Private int32_t buff_bytes; /* Size of received packet */
Private FILE* srvr_debug = NULL;

/* rev 0.9.0 */
/* buffers for Callx return arguments  */
#define MAX_ARGS 20
Private char *    CallArgArray[MAX_ARGS];          /* create an array of pointers, for string arguments (returned by Callx) not sure if this is correct */
Private int       CallArgArraySz[MAX_ARGS];        /* and size of memory allocated for each  string length + terminator */


#define MAX_SESSIONS 4
Private struct {
  bool is_local;
  int16_t context;
#define CX_DISCONNECTED 0 /* No session active */
#define CX_CONNECTED 1    /* Session active but not... */
#define CX_EXECUTING 2    /* ...executing command (implies connected) */
  char sderror[512 + 1];
  int16_t server_error;
  int32_t sd_status;
  SOCKET sock;
  int RxPipe[2];
  int TxPipe[2];
  int pid; /* 0421 Pid of child process */
} session[MAX_SESSIONS];
Private int16_t session_idx = 0;

/* Matching data */
Private char* component_start;
Private char* component_end;

/* Internally used routines */
void DLLEntry SDDisconnect(void);
void DLLEntry SDEndCommand(void);

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
Private char* sysdir(void);

#define ClearError session[session_idx].sderror[0] = '\0'

/* rev 0.9.0 */
/* ======================================================================
   SDCall()  - Callx catalogued subroutine
   Note, this version does NOT repopulate the returned values of the QMCallx calling arguments, you must use QMGetArg to retrive them */
void DLLEntry SDCallx(char* subrname, int16_t argc, ...) {
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
  struct ARGDATA* argptr;
  int offset;

  if (context_error(CX_CONNECTED))
    return;
  subrname_len = strlen(subrname);
  if ((subrname_len < 1) || (subrname_len > MAX_CALL_NAME_LEN)) {
    Abort("Illegal subroutine name in call", FALSE);
  }
  if ((argc < 0) || (argc > MAX_ARGS)) {
    Abort("Illegal argument count in call", FALSE);
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
    n = (bytes + BUFF_INCR - 1) & ~BUFF_INCR;
    q = (INBUFF*)malloc(n);
    if (q == NULL) {
      Abort("Unable to allocate network buffer", FALSE);
    }
    free(buff);
    buff = q;
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
		strcpy(arg_p,arg);
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
      argptr = (ARGDATA*)(((char*)buff) + offset);
      arg = va_arg(ap, char*);
	  if (i == argptr->argno) {
		arg_len = LongInt(argptr->arglen);
	   /*  memcpy(arg, argptr->text, arg_len);  */
	   /*  arg[arg_len] = '\0';                 */
	   /* check CallArgArray buffer is large enough for returned value */
		if ((CallArgArraySz[i-1]) < (arg_len+1)) {
	   /* not large enough, free and re allocate  */
		  if (CallArgArray[i-1] != NULL)
			 free(CallArgArray[i-1]);
		  CallArgArray[i-1] = malloc((arg_len+1) * sizeof(char));
		  if (CallArgArray[i-1] != NULL){
			CallArgArraySz[i-1] = (arg_len+1) * sizeof(char);
			memcpy(CallArgArray[i-1], argptr->text, arg_len);
			CallArgArray[i-1][arg_len] = '\0';
		  }else{
			Abort("Unable to allocate Callx buffer on return", FALSE);
		  }
		}else{
	  /* existing buffer large enough  */
		  memcpy(CallArgArray[i-1], argptr->text, arg_len);
		  CallArgArray[i-1][arg_len] = '\0';
		}

		offset +=
            offsetof(ARGDATA, text) + ((LongInt(argptr->arglen) + 1) & ~1);
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
char* DLLEntry SDGetArg(int ArgNbr) {
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
  strcpy(arg,CallArgArray[arg_idx]);
  return arg;
}


/* ======================================================================
   SDCall()  - Call catalogued subroutine                                 */

void DLLEntry SDCall(char* subrname, int16_t argc, ...) {
  va_list ap;
  int16_t i;
  char* arg;
  int subrname_len;
  int32_t arg_len;
  int32_t bytes; /* Total length of outgoing packet */
  int32_t n;
  char* p;
  INBUFF* q;
  struct ARGDATA* argptr;
  int offset;

#define MAX_ARGS 20

  if (context_error(CX_CONNECTED))
    return;

  subrname_len = strlen(subrname);
  if ((subrname_len < 1) || (subrname_len > MAX_CALL_NAME_LEN)) {
    Abort("Illegal subroutine name in call", FALSE);
  }

  if ((argc < 0) || (argc > MAX_ARGS)) {
    Abort("Illegal argument count in call", FALSE);
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
    n = (bytes + BUFF_INCR - 1) & ~BUFF_INCR;
    q = (INBUFF*)malloc(n);
    if (q == NULL) {
      Abort("Unable to allocate network buffer", FALSE);
    }
    free(buff);
    buff = q;
  }

  /* Set up outgoing packet */

  p = (char*)buff;

  *((int16_t*)p) = ShortInt(subrname_len); /* Subrname length */
  p += 2;

  memcpy(p, subrname, subrname_len); /* Subrname */
  p += (subrname_len + 1) & ~1;

  *((int16_t*)p) = ShortInt(argc); /* Arg count */
  p += 2;

  va_start(ap, argc);
  for (i = 1; i <= argc; i++) {
    arg = va_arg(ap, char*);
    arg_len = (arg == NULL) ? 0 : strlen(arg);
    *((int32_t*)p) = LongInt(arg_len); /* Arg length */
    p += 4;
    if (arg_len)
      memcpy(p, arg, arg_len); /* Arg text */
    p += (arg_len + 1) & ~1;
  }
  va_end(ap);

  if (!message_pair(SrvrCall, (char*)buff, bytes)) {
    goto err;
  }

  /* Now update any returned arguments */

  offset = offsetof(INBUFF, data.call.argdata);
  if (offset < buff_bytes) {
    va_start(ap, argc);
    for (i = 1; i <= argc; i++) {
      argptr = (ARGDATA*)(((char*)buff) + offset);

      arg = va_arg(ap, char*);
      if (i == argptr->argno) {
        arg_len = LongInt(argptr->arglen);
        memcpy(arg, argptr->text, arg_len);
        arg[arg_len] = '\0';

        offset +=
            offsetof(ARGDATA, text) + ((LongInt(argptr->arglen) + 1) & ~1);
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
   SDChange()  -  Change substrings                                       */

char* DLLEntry
SDChange(char* src, char* old, char* new, int occurrences, int start) {
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
  strcpy(new_str, src);
  return new_str;
}

/* ======================================================================
   SDClearSelect()  - Clear select list                                   */

void DLLEntry SDClearSelect(int listno) {
  struct {
    int16_t listno;
  } ALIGN2 packet;

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

void DLLEntry SDClose(int fno) {
  struct {
    int16_t fno;
  } ALIGN2 packet;

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

int DLLEntry
SDConnect(char* host, int port, char* username, char* password, char* account) {
  int status = FALSE;
  char login_data[2 + MAX_USERNAME_LEN + 2 + MAX_USERNAME_LEN];
  int n;
  char* p;

  initialise_client();

  if (!FindFreeSession())
    goto exit_sdconnect;
  ClearError;
  session[session_idx].is_local = FALSE;

  n = strlen(host);
  if (n == 0) {
    strcpy(session[session_idx].sderror, "Invalid host name");
    goto exit_sdconnect;
  }

  /* Set up login data */

  p = login_data;

  n = strlen(username);
  if (n > MAX_USERNAME_LEN) {
    strcpy(session[session_idx].sderror, "Invalid user name");
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
    strcpy(session[session_idx].sderror, "Invalid password");
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
        memcpy(session[session_idx].sderror, buff->data.abort.message, n);
        buff->data.abort.message[n] = '\0';
      }
    }
    goto exit_sdconnect;
  }

  /* Now attempt to attach to required account */

  if (!message_pair(SrvrAccount, account, strlen(account))) {
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
   SDConnectUDS()  -  Open connection to server via unix domain socket   */

int DLLEntry
SDConnectUDS(char* account) {
  int status = FALSE;
  char login_data[2 + MAX_USERNAME_LEN + 2 + MAX_USERNAME_LEN];
  char username[MAX_USERNAME_LEN + 1]; 
  char password[MAX_USERNAME_LEN + 1] = "dummy";
  u_int32_t m;
  int n;
  char* p;
  
  initialise_client();

  if (!FindFreeSession())
    goto exit_sdconnectUDS;
  ClearError;
  session[session_idx].is_local = FALSE;

  /* setup login data */
  /* get username of process */
  m = MAX_USERNAME_LEN + 1;
  p = username;
  if (!GetUserName(p,&m)){
    goto exit_sdconnectUDS; 
  }
  
  p = login_data;
  n = strlen(username);
  *((int16_t*)p) = ShortInt(n); /* User name len */
  p += 2;
  
  memcpy(p, username, n); /* User name */
  p += n;
  if (n & 1)
    *(p++) = '\0';

  n = strlen(password);
  *((int16_t*)p) = ShortInt(n); /* Password len */
  p += 2;

  memcpy(p, password, n); /* Password */
  p += n;
  if (n & 1)
    *(p++) = '\0'; 

  /* Note systemd starts the  sd process as root, linuxio.c function start_connection will set process to user */
  /* Open connection to server */

  if (!OpenUDSocket())
    goto exit_sdconnectUDS;

  /* Check username and password */

  n = p - login_data;
  if (!message_pair(SrvrLogin, login_data, n)) {
    goto exit_sdconnectUDS;
  }

  if (session[session_idx].server_error != SV_OK) {
    if (session[session_idx].server_error == SV_ON_ERROR) {
      n = buff_bytes - offsetof(INBUFF, data.abort.message);
      if (n > 0) {
        memcpy(session[session_idx].sderror, buff->data.abort.message, n);
        buff->data.abort.message[n] = '\0';
      }
    }
    goto exit_sdconnectUDS;
  }

  /* Now attempt to attach to required account */

  if (!message_pair(SrvrAccount, account, strlen(account))) {
    goto exit_sdconnectUDS;
  }

  session[session_idx].context = CX_CONNECTED;
  status = TRUE;

exit_sdconnectUDS:
  if (!status)
    CloseSocket();
  return status;
}


/* ======================================================================
   SDConnected()  -  Are we connected?                                    */

int DLLEntry SDConnected() {
  ClearError;

  return (session[session_idx].context == CX_DISCONNECTED) ? FALSE : TRUE;
}

/* ======================================================================
   SDConnectLocal()  -  Open connection to local system as current user   */

int DLLEntry SDConnectLocal(char* account) {
  int status = FALSE;
  struct passwd *pwd;
  int cpid;
  char option[20];
  char path[MAX_PATHNAME_LEN + 1];
/* rev 0.9.0 log local login */
  char username[MAX_USERNAME_LEN + 1];
  u_int32_t m;
  char* p;
  
  initialise_client();

  if (!FindFreeSession())
    goto exit_sdconnect_local;
  ClearError;
  session[session_idx].is_local = TRUE;

  /* Create pipes */

  if (pipe(session[session_idx].RxPipe) || pipe(session[session_idx].TxPipe)) {
    sprintf(session[session_idx].sderror, "Error %d creating pipe", errno);
    goto exit_sdconnect_local;
  }

  /* Launch SD process */

  cpid = fork();
  if (cpid == 0) /* Child process */
  {
    sprintf(path, "%s/bin/sd", sysdir());
    sprintf(option, "-C%d!%d", session[session_idx].RxPipe[1],
            session[session_idx].TxPipe[0]);
    execl(path, path, "-Q", option, NULL);
  } else if (cpid == -1) /* Error */
  {
    sprintf(session[session_idx].sderror, "Error %d forking process", errno);
    goto exit_sdconnect_local;
  } else /* Parent process */
  {
    session[session_idx].pid = cpid; /* 0421 */
  }
  
  /* rev 0.9.0 log username of process, set forked process to uid gid of user forking process */
 
  m = MAX_USERNAME_LEN + 1;
  p = username;
  if (!GetUserName(p,&m)){
    sprintf(session[session_idx].sderror, "Error Could Not Establish Username");
    goto exit_sdconnect_local; 
  }

  openlog ("sd_Log", LOG_CONS | LOG_PID | LOG_NDELAY, LOG_LOCAL1);
  syslog (LOG_INFO, "APISrvr Local Connection, user:");
  syslog (LOG_INFO, "%s", username);

  if (((pwd = getpwnam(username)) != NULL) && (setgid(pwd->pw_gid) == 0) && (setuid(pwd->pw_uid) == 0)) {
            //         set_groups();
    syslog (LOG_INFO, "sdApiSrvr login via Username: %s (%d) Group: %d",username,pwd->pw_uid, pwd->pw_gid);
  } else {
    syslog (LOG_INFO, "sdApiSrvr unable to set user and group for Username: %s",username);
    closelog();
    sprintf(session[session_idx].sderror, "Error Could Set User Group");
    goto exit_sdconnect_local; 
  }
 
  closelog();

  /* Send local login packet */

  if (!message_pair(SrvrLocalLogin, NULL, 0)) {
    goto exit_sdconnect_local;
  }

  /* Now attempt to attach to required account */

  if (!message_pair(SrvrAccount, account, strlen(account))) {
// rev 0.9.0
    disconnect();
    goto exit_sdconnect_local;
  }

  session[session_idx].context = CX_CONNECTED;
  status = TRUE;

exit_sdconnect_local:
  if (!status) {
    if (session[session_idx].RxPipe[0] >= 0) {
      close(session[session_idx].RxPipe[0]);
      session[session_idx].RxPipe[0] = -1;
    }
    if (session[session_idx].RxPipe[1] >= 0) {
      close(session[session_idx].RxPipe[1]);
      session[session_idx].RxPipe[1] = -1;
    }
    if (session[session_idx].TxPipe[0] >= 0) {
      close(session[session_idx].TxPipe[0]);
      session[session_idx].TxPipe[0] = -1;
    }
    if (session[session_idx].TxPipe[1] >= 0) {
      close(session[session_idx].TxPipe[1]);
      session[session_idx].TxPipe[1] = -1;
    }
  }

  return status;
}

/* ======================================================================
   SDDcount()  -  Count fields, values or subvalues                       */

int DLLEntry SDDcount(char* src, char* delim_str) {
  int32_t src_len;
  char* p;
  int32_t ct = 0;
  char delim;

  initialise_client();

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

void DLLEntry SDDebug(bool mode) {
  if (mode && (srvr_debug == NULL)) /* Turn on */
  {
    srvr_debug = fopen("clidbg", "w");
  }

  if (!mode && (srvr_debug != NULL)) /* Turn off */
  {
    fclose(srvr_debug);
    srvr_debug = NULL;
  }
}

/* ======================================================================
   SDDel()  -  Delete field, value or subvalue                            */

char* DLLEntry SDDel(char* src, int fno, int vno, int svno) {
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
    p = memchr(pos, FIELD_MARK, bytes);
    if (p == NULL)
      goto unchanged_result; /* No such field */
    bytes -= (1 + p - pos);
    pos = p + 1;
  }

  p = memchr(pos, FIELD_MARK, bytes);
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
    } else /* Not last field */
    {
      bytes++; /* Include trailing mark in deleted region */
    }
    goto done;
  }

  /* Skip to start value */

  i = vno;
  while (--i) {
    p = memchr(pos, VALUE_MARK, bytes);
    if (p == NULL)
      goto unchanged_result; /* No such value */
    bytes -= (1 + p - pos);
    pos = p + 1;
  }

  p = memchr(pos, VALUE_MARK, bytes);
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
    } else /* Not last value */
    {
      bytes++; /* Include trailing mark in deleted region */
    }
    goto done;
  }

  /* Skip to start subvalue */

  i = svno;
  while (--i) {
    p = memchr(pos, SUBVALUE_MARK, bytes);
    if (p == NULL)
      goto unchanged_result; /* No such subvalue */
    bytes -= (1 + p - pos);
    pos = p + 1;
  }
  p = memchr(pos, SUBVALUE_MARK, bytes);
  if (p != NULL)
    bytes = p - pos; /* Length of subvalue, excluding end mark */

  if (p == NULL) /* Last subvalue */
  {
    if (svno > 1) /* Not only subvalue. Back up to include leading mark */
    {
      pos--;
      bytes++;
    }
  } else /* Not last subvalue */
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
  strcpy(new_str, src);
  return new_str;
}

/* ======================================================================
   SDDelete()  -  Delete record                                           */

void DLLEntry SDDelete(int fno, char* id) {
  delete_record(SrvrDelete, fno, id);
}

/* ======================================================================
   SDDeleteu()  -  Delete record, retaining lock                          */

void DLLEntry SDDeleteu(int fno, char* id) {
  delete_record(SrvrDeleteu, fno, id);
}

/* ======================================================================
   SDDisconnect()  -  Close connection to server.                         */

void DLLEntry SDDisconnect() {
  if (session[session_idx].context != CX_DISCONNECTED) {
    disconnect();
  }
}

/* ======================================================================
   SDDisconnectAll()  -  Close connection to all servers.                 */

void DLLEntry SDDisconnectAll() {
  int16_t i;

  for (i = 0; i < MAX_SESSIONS; i++) {
    if (session[session_idx].context != CX_DISCONNECTED) {
      session_idx = i;
      disconnect();
    }
  }
}

/* ======================================================================
   SDEndCommand()  -  End a command that is requesting input              */

void DLLEntry SDEndCommand() {
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
   SDEnterPackage()  -  Enter a licensed package                          */

bool DLLEntry SDEnterPackage(char* name) {
  bool status = FALSE;
  int name_len;

  if (context_error(CX_CONNECTED))
    goto exit_EnterPackage;

  name_len = strlen(name);
  if ((name_len < 1) || (name_len > MAX_PACKAGE_NAME_LEN)) {
    session[session_idx].server_error = SV_ELSE;
    session[session_idx].sd_status = ER_BAD_NAME;
  } else {
    if (!message_pair(SrvrEnterPackage, name, name_len)) {
      goto exit_EnterPackage;
    }
  }

  switch (session[session_idx].server_error) {
    case SV_OK:
      status = TRUE;
      break;

    case SV_ON_ERROR:
      Abort("EnterPackage generated an abort event", TRUE);
      break;

    case SV_LOCKED:
    case SV_ELSE:
    case SV_ERROR:
      break;
  }

exit_EnterPackage:
  return status;
}

/* ======================================================================
   SDExitPackage()  -  Exit from a licensed package                       */

bool DLLEntry SDExitPackage(char* name) {
  bool status = FALSE;
  int name_len;

  if (context_error(CX_CONNECTED))
    goto exit_ExitPackage;

  name_len = strlen(name);
  if ((name_len < 1) || (name_len > MAX_PACKAGE_NAME_LEN)) {
    session[session_idx].server_error = SV_ELSE;
    session[session_idx].sd_status = ER_BAD_NAME;
  } else {
    if (!message_pair(SrvrExitPackage, name, name_len)) {
      goto exit_ExitPackage;
    }
  }

  switch (session[session_idx].server_error) {
    case SV_OK:
      status = TRUE;
      break;

    case SV_ON_ERROR:
      Abort("ExitPackage generated an abort event", TRUE);
      break;

    case SV_LOCKED:
    case SV_ELSE:
    case SV_ERROR:
      break;
  }

exit_ExitPackage:
  return status;
}

/* ======================================================================
   SDError()  -  Return extended error string                             */

char* DLLEntry SDError() {
  return session[session_idx].sderror;
}

/* ======================================================================
   SDExecute()  -  Execute a command                                      */

char* DLLEntry SDExecute(char* cmnd, int* err) {
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
      /* Modified by Composer AI - 2026/06/10.
         Intentional fall-through: SV_PROMPT shares reply extraction. */
      /* **** FALL THROUGH **** */
      __attribute__((fallthrough));
      /* -------------------- */

    case SV_OK:
      reply_len = buff_bytes - offsetof(INBUFF, data.execute.reply);
      break;

    case SV_ON_ERROR:
      Abort("EXECUTE generated an abort event", TRUE);
      break;
  }

exit_sdexecute:
  reply = malloc(reply_len + 1);
  /* Modified by Composer AI - 2026/06/10.
     malloc() can fail; return empty string instead of strcpy through NULL. */
  if (reply == NULL) {
    *err = session[session_idx].server_error;
    return NullString();
  }
  /* -------------------- */
  strcpy(reply, buff->data.execute.reply);
  *err = session[session_idx].server_error;

  return reply;
}

/* ======================================================================
   SDExtract()  -  Extract field, value or subvalue                       */

char* DLLEntry SDExtract(char* src, int fno, int vno, int svno) {
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
    p = memchr(src, FIELD_MARK, src_len);
    if (p == NULL)
      goto null_result; /* No such field */
    src_len -= (1 + p - src);
    src = p + 1;
  }
  p = memchr(src, FIELD_MARK, src_len);
  if (p != NULL)
    src_len = p - src; /* Adjust to ignore later fields */

  if (vno < 1)
    goto done; /* Extracting whole field */

  /* Skip to start value */

  while (--vno) {
    p = memchr(src, VALUE_MARK, src_len);
    if (p == NULL)
      goto null_result; /* No such value */
    src_len -= (1 + p - src);
    src = p + 1;
  }

  p = memchr(src, VALUE_MARK, src_len);
  if (p != NULL)
    src_len = p - src; /* Adjust to ignore later values */

  if (svno < 1)
    goto done; /* Extracting whole value */

  /* Skip to start subvalue */

  while (--svno) {
    p = memchr(src, SUBVALUE_MARK, src_len);
    if (p == NULL)
      goto null_result; /* No such subvalue */
    src_len -= (1 + p - src);
    src = p + 1;
  }
  p = memchr(src, SUBVALUE_MARK, src_len);
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

char* DLLEntry SDField(char* src, char* delim, int first, int occurrences) {
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

void DLLEntry SDFree(void* p) {
  free(p);
}

/* ======================================================================
   SDGetSession()  -  Return session index                                */

int DLLEntry SDGetSession() {
  return session_idx;
}

/* ======================================================================
   SDIns()  -  Insert field, value or subvalue                            */

char* DLLEntry SDIns(char* src, int fno, int vno, int svno, char* new) {
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
  char postmark = '\0';

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
    p = memchr(pos, FIELD_MARK, bytes);
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

  p = memchr(pos, FIELD_MARK, bytes);
  if (p != NULL)
    bytes = p - pos; /* Length of field */

  if (vno == 0) { /* Inserting field */
    postmark = FIELD_MARK;
    goto done;
  }

  /* Skip to start value */

  for (i = 1; i < vno; i++) {
    p = memchr(pos, VALUE_MARK, bytes);
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

  p = memchr(pos, VALUE_MARK, bytes);
  if (p != NULL)
    bytes = p - pos; /* Length of value, excluding end mark */

  if (svno == 0) { /* Inserting value */
    postmark = VALUE_MARK;
    goto done;
  }

  /* Skip to start subvalue */

  for (i = 1; i < svno; i++) {
    p = memchr(pos, SUBVALUE_MARK, bytes);
    if (p == NULL) { /* No such subvalue */
      sm = svno - i;
      pos += bytes;
      goto done;
    }
    bytes -= (1 + p - pos);
    pos = p + 1;
  }

  postmark = SUBVALUE_MARK;

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
    *(p++) = FIELD_MARK;
  while (vm--)
    *(p++) = VALUE_MARK;
  while (sm--)
    *(p++) = SUBVALUE_MARK;

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

int DLLEntry SDLocate(char* item,
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

  mark = FIELD_MARK;
  idx = fno;
  for (i = 1; i < fno; i++) {
    if (bytes == 0)
      goto done;
    q = memchr(p, FIELD_MARK, bytes);
    if (q == NULL)
      goto done; /* No such field */
    bytes -= (1 + q - p);
    p = q + 1;
  }

  if (vno > 0) /* Searching for value or subvalue */
  {
    q = memchr(p, FIELD_MARK, bytes);
    if (q != NULL)
      bytes = q - p; /* Limit view to length of field */

    mark = VALUE_MARK;
    idx = vno;
    for (i = 1; i < vno; i++) {
      if (bytes == 0)
        goto done;
      q = memchr(p, VALUE_MARK, bytes);
      if (q == NULL)
        goto done; /* No such value */
      bytes -= (1 + q - p);
      p = q + 1;
    }

    if (svno > 0) /* Searching for subvalue */
    {
      q = memchr(p, VALUE_MARK, bytes);
      if (q != NULL)
        bytes = q - p; /* Limit view to length of value */

      mark = SUBVALUE_MARK;
      idx = svno;
      for (i = 1; i < svno; i++) /* 0512 */
      {
        if (bytes == 0)
          goto done;
        q = memchr(p, SUBVALUE_MARK, bytes);
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

int DLLEntry SDLogto(char* account_name) {
  bool status = FALSE;
  int name_len;

  if (context_error(CX_CONNECTED))
    goto exit_logto;

  name_len = strlen(account_name);
  if ((name_len < 1) || (name_len > MAX_ACCOUNT_NAME_LEN)) {
    session[session_idx].server_error = SV_ELSE;
    session[session_idx].sd_status = ER_BAD_NAME;
  } else {
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

void DLLEntry SDMarkMapping(int16_t fno, int16_t state) {
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

int DLLEntry SDMatch(char* str, char* pattern) {
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
    q = strchr(p, (char)VALUE_MARK);
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

char* DLLEntry SDMatchfield(char* str, char* pattern, int component) {
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
    q = strchr(p, (char)VALUE_MARK);
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

int DLLEntry SDOpen(char* filename) {
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

char* DLLEntry SDRead(int fno, char* id, int* err) {
  return read_record(fno, id, err, SrvrRead);
}

/* ======================================================================
   SDReadl()  -  Read record with shared lock                             */

char* DLLEntry SDReadl(int fno, char* id, int wait, int* err) {
  return read_record(fno, id, err, (wait) ? SrvrReadlw : SrvrReadl);
}

/* ======================================================================
   SDReadList()  - Read select list                                       */

char* DLLEntry SDReadList(int listno) {
  char* list;
  /* int16_t status = 0; variable set but never used */
  int32_t data_len = 0;
  struct {
    int16_t listno;
  } ALIGN2 packet;

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
      return NULL;
  }

  /* status = session[session_idx].server_error;
   * variable set but never used. */

exit_sdreadlist:

  list = malloc(data_len + 1);
  memcpy(list, buff->data.readlist.list, data_len);
  list[data_len] = '\0';
  return list;
}

/* ======================================================================
   SDReadNext()  - Read select list entry                                 */

char* DLLEntry SDReadNext(int16_t listno) {
  char* id;
  int32_t id_len = 0;
  struct {
    int16_t listno;
  } ALIGN2 packet;

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
      return NULL;
  }

exit_sdreadnext:
  id = malloc(id_len + 1);
  memcpy(id, buff->data.readnext.id, id_len);
  id[id_len] = '\0';
  return id;
}

/* ======================================================================
   SDReadu()  -  Read record with exclusive lock                          */

char* DLLEntry SDReadu(int fno, char* id, int wait, int* err) {
  return read_record(fno, id, err, (wait) ? SrvrReaduw : SrvrReadu);
}

/* ======================================================================
   SDRecordlock()  -  Get lock on a record                                */

void DLLEntry SDRecordlock(int fno, char* id, int update_lock, int wait) {
  int id_len;
  int16_t flags;
  struct {
    int16_t fno;
    int16_t flags; /* 0x0001 : Update lock */
                     /* 0x0002 : No wait */
    char id[MAX_ID_LEN];
  } ALIGN2 packet;

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

void DLLEntry SDRelease(int fno, char* id) {
  int id_len;
  struct {
    int16_t fno;
    char id[MAX_ID_LEN];
  } ALIGN2 packet;

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

char* DLLEntry SDReplace(char* src, int fno, int vno, int svno, char* new) {
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
    p = memchr(pos, FIELD_MARK, bytes);
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

  p = memchr(pos, FIELD_MARK, bytes);
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
    p = memchr(pos, VALUE_MARK, bytes);
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

  p = memchr(pos, VALUE_MARK, bytes);
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
    p = memchr(pos, SUBVALUE_MARK, bytes);
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

  p = memchr(pos, SUBVALUE_MARK, bytes);
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
    *(p++) = FIELD_MARK;
  while (vm--)
    *(p++) = VALUE_MARK;
  while (sm--)
    *(p++) = SUBVALUE_MARK;

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

char* DLLEntry SDRespond(char* response, int* err) {
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
      /* Modified by Composer AI - 2026/06/10.
         Intentional fall-through: SV_OK shares reply extraction. */
      /* **** FALL THROUGH **** */
      __attribute__((fallthrough));
      /* -------------------- */

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
  /* Modified by Composer AI - 2026/06/10.
     malloc() can fail; return empty string instead of memcpy through NULL. */
  if (reply == NULL) {
    *err = session[session_idx].server_error;
    return NullString();
  }
  /* -------------------- */
  memcpy(reply, buff->data.execute.reply, reply_len);
  reply[reply_len] = '\0';
  *err = session[session_idx].server_error;
  return reply;
}

/* ======================================================================
   SDSelect()  - Generate select list                                     */

void DLLEntry SDSelect(int fno, int listno) {
  struct {
    int16_t fno;
    int16_t listno;
  } ALIGN2 packet;

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

char* DLLEntry SDSelectLeft(int16_t fno, char* index_name, int16_t listno) {
  return SelectLeftRight(fno, index_name, listno, SrvrSelectLeft);
}

char* DLLEntry SDSelectRight(int16_t fno,
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

  key = malloc(key_len + 1);
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

/* ======================================================================
   SDSetSession()  -  Set session index                                   */

int DLLEntry SDSetSession(int idx) {
  if ((idx < 0) || (idx >= MAX_SESSIONS) ||
      (session[idx].context == CX_DISCONNECTED)) {
    return FALSE;
  }

  session_idx = idx;
  return TRUE;
}

/* ======================================================================
   SDStatus()  -  Return STATUS() value                                   */

int DLLEntry SDStatus() {
  return session[session_idx].sd_status;
}

/* ======================================================================
   SDWrite()  -  Write record                                             */

void DLLEntry SDWrite(int fno, char* id, char* data) {
  write_record(SrvrWrite, fno, id, data);
}

/* ======================================================================
   SDWriteu()  -  Write record, retaining lock                            */

void DLLEntry SDWriteu(int fno, char* id, char* data) {
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
  struct {
    int16_t fno;
    char id[MAX_ID_LEN];
  } ALIGN2 packet;

  if (context_error(CX_CONNECTED))
    goto exit_delete;

  packet.fno = ShortInt(fno);

  id_len = strlen(id);
  if ((id_len < 1) || (id_len > MAX_ID_LEN)) {
    session[session_idx].server_error = SV_ON_ERROR;
    session[session_idx].sd_status = ER_IID;
  } else {
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
  /* Modified by Composer AI - 2026/06/10.
     Default status for early exit paths that skip the server switch. */
  /* int32_t status; */
  int32_t status = SV_ERROR;
  /* -------------------- */
  int32_t rec_len = 0;
  int id_len;
  char* rec;
  struct {
    int16_t fno;
    char id[MAX_ID_LEN];
  } ALIGN2 packet;

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

  status = session[session_idx].server_error;

exit_read:
  rec = malloc(rec_len + 1);
  /* Modified by Composer AI - 2026/06/10.
     malloc() can fail; return empty string instead of memcpy through NULL. */
  if (rec == NULL) {
    *err = status;
    return NullString();
  }
  /* -------------------- */
  memcpy(rec, buff->data.read.rec, rec_len);
  rec[rec_len] = '\0';
  *err = status;
  return rec;
}

/* ====================================================================== */

Private void write_record(int16_t mode, int16_t fno, char* id, char* data) {
  int id_len;
/* 020240701 mab Max String Size, use could pass > 2GB */ 
  size_t data_len;
  int bytes;
  INBUFF* q;
  struct PACKET {
    int16_t fno;
    int16_t id_len;
    char id[1];
  } ALIGN2;

  if (context_error(CX_CONNECTED))
    goto exit_write;

  id_len = strlen(id);
  if ((id_len < 1) || (id_len > MAX_ID_LEN)) {
    Abort("Illegal record id", FALSE);
    session[session_idx].sd_status = ER_IID;
    goto exit_write;
  }

  data_len = strlen(data);

  /* 20240702 mab do not allow write > MAX_STRING_SIZE */
  if (data_len > MAX_STRING_SIZE) {
    Abort("Illegal record size", FALSE);
    session[session_idx].sd_status = ER_MAX_STRING;
    goto exit_write;
  }

  /* Ensure buffer is big enough for this record */

  bytes = sizeof(struct PACKET) + id_len + data_len;
  if (bytes >= buff_size) /* Must reallocate larger buffer */
  {
    bytes = (bytes + BUFF_INCR - 1) & ~BUFF_INCR;
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
    strcpy(session[session_idx].sderror, "Unable to retrieve error text");
    write_packet(SrvrGetError, NULL, 0);
    if (read_packet())
      strcpy(session[session_idx].sderror, buff->data.error.text);
    return FALSE;
  }

  return TRUE;
}

/* ====================================================================== */

Private void Abort(char* msg, bool use_response) {
  char abort_msg[1024 + 1];
  int n;
  char* p;

  strcpy(abort_msg, msg);

  if (use_response) {
    n = buff_bytes - offsetof(INBUFF, data.abort.message);
    if (n > 0) {
      p = abort_msg + strlen(msg);
      *(p++) = '\r';
      memcpy(p, buff->data.abort.message, n);
      *(p + n) = '\0';
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
      template ++;
    } else
      not = FALSE;

    if (IsDigit(*template)) {
      n = 0;
      do {
        n = (n * 10) + (*(template ++) - '0');
      } while (IsDigit(*template));

      switch (UpperCase(*(template ++))) {
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
          } else /* 0A */
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
            } else {
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
          } else /* 0N */
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
            } else {
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
          } else /* 0X */
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
            m = (m * 10) + (*(template ++) - '0');
          } while (IsDigit(*template));
          m -= n;
          if (m < 0)
            return FALSE;

          switch (UpperCase(*(template ++))) {
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
              } else
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
              } else
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
              } else {
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
    } else if (memcmp(template, "...", 3) == 0) /* ... same as 0X */
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
    } else /* Must be literal text item */
    {
      delimiter = *template;
      if ((delimiter == '\'') || (delimiter == '"')) /* Quoted literal */
      {
        template ++;
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
      } else /* Unquoted literal. Treat as single character */
      {
        if ((*(template ++) == *(string++)) == not)
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
  if (write_packet(type, data, bytes)) {
    return GetResponse();
  }

  return FALSE;
}

/* ====================================================================== */

Private char* NullString() {
  char* p;
  static char empty[1] = {'\0'};

  /* Modified by Composer AI - 2026/06/10.
     malloc(1) can fail; return a static empty string instead. */
  /* p = malloc(1);
  *p = '\0';
  return p; */
  p = malloc(1);
  if (p == NULL)
    return empty;
  *p = '\0';
  return p;
  /* -------------------- */
}

/* ======================================================================
   OpenUDSocket()  -  Open connection to Unix Domain Socket - server                            */

Private bool OpenUDSocket() {
  bool status = FALSE;
  char ack_buff;
 
  struct sockaddr_un serveraddr;

/* note see
  https://www.ibm.com/docs/en/i/7.5?topic=uauaf-example-client-application-that-uses-af-unix-address-family
  For af_unix client sample
*/

  session[session_idx].sock = socket(AF_UNIX, SOCK_STREAM, 0);
  if (session[session_idx].sock == INVALID_SOCKET) {
    NetErr("socket()", WSAGetLastError(), errno);
    goto exit_openUDsocket;
  }

  memset(&serveraddr, 0, sizeof(serveraddr));
  serveraddr.sun_family = AF_UNIX;
  strncpy(serveraddr.sun_path, SERVER_PATH,sizeof(serveraddr.sun_path)-1);

  if (connect(session[session_idx].sock, (struct sockaddr *)&serveraddr,sizeof(struct sockaddr_un))) {
    NetErr("connect()", WSAGetLastError(), errno);
    goto exit_openUDsocket;
  }


  /* Wait for an Ack character to arrive before we assume the connection
    to be open and working. This is necessary because Linux loses anything
    we send before the SD process is up and running.                       */

  do {
    if (recv(session[session_idx].sock, &ack_buff, 1, 0) < 1)
      goto exit_openUDsocket;
  } while (ack_buff != '\x06');

  status = 1;

exit_openUDsocket:
  return status;
}

/* ======================================================================
   OpenSocket()  -  Open connection to server                            */

Private bool OpenSocket(char* host, int16_t port) {
  bool status = FALSE;
  u_int32_t nInterfaceAddr;
  struct hostent* hostdata;
  int nPort;
  struct sockaddr_in sock_addr;
  char ack_buff;
  int n;
  unsigned int n1, n2, n3, n4;

  if (port < 0)
    port = 4245;

  if ((sscanf(host, "%u.%u.%u.%u", &n1, &n2, &n3, &n4) == 4) && (n1 <= 255) &&
      (n2 <= 255) && (n3 <= 255) && (n4 <= 255)) {
    /* Looks like an IP address */
    nInterfaceAddr = inet_addr(host);
  } else {
    hostdata = gethostbyname(host);
    if (hostdata == NULL) {
      NetErr("gethostbyname()", WSAGetLastError(), h_errno);
      goto exit_opensocket;
    }

    nInterfaceAddr = *((int32_t*)(hostdata->h_addr));
  }

  nPort = htons(port);

  session[session_idx].sock = socket(AF_INET, SOCK_STREAM, 0);
  if (session[session_idx].sock == INVALID_SOCKET) {
    NetErr("socket()", WSAGetLastError(), errno);
    goto exit_opensocket;
  }

  sock_addr.sin_family = AF_INET;
  sock_addr.sin_addr.s_addr = nInterfaceAddr;
  sock_addr.sin_port = nPort;

  if (connect(session[session_idx].sock, (struct sockaddr*)&sock_addr,
              sizeof(sock_addr))) {
    NetErr("connect()", WSAGetLastError(), errno);
    goto exit_opensocket;
  }

  n = TRUE;
  if (setsockopt(session[session_idx].sock, IPPROTO_TCP, TCP_NODELAY, (char*)&n,
                 sizeof(int))) {
    NetErr("setsockopt()", WSAGetLastError(), errno);
    goto exit_opensocket;
  }

  /* Wait for an Ack character to arrive before we assume the connection
    to be open and working. This is necessary because Linux loses anything
    we send before the SD process is up and running.                       */

  do {
    if (recv(session[session_idx].sock, &ack_buff, 1, 0) < 1)
      goto exit_opensocket;
  } while (ack_buff != '\x06');

  status = 1;

exit_opensocket:
  return status;
}


/* ======================================================================
   CloseSocket()  -  Close connection to server                          */

Private bool CloseSocket() {
  bool status = FALSE;

  if (session[session_idx].sock == INVALID_SOCKET)
    goto exit_closesocket;

  closesocket(session[session_idx].sock);
  session[session_idx].sock = INVALID_SOCKET;

  status = TRUE;

exit_closesocket:
  return status;
}

/* ======================================================================
   NetErr                                                               */

static void net_error(char* prefix, int err) {
  fprintf(stderr, "Error %d from %s\n", err, prefix);
}

/* ======================================================================
   read_packet()  -  Read a SD data packet                                */

Private bool read_packet() {
  int rcvd_bytes;        /* Length of received packet fragment */
  int32_t packet_bytes; /* Total length of incoming packet */
  int rcv_len;
  int32_t n;
  unsigned char* p;

  /* 0272 restructured */
  struct {
    int32_t packet_length;
    int16_t server_error ALIGN2;
    int32_t status ALIGN2;
  } in_packet_header;
#define IN_PKT_HDR_BYTES 10

  if ((!session[session_idx].is_local) &&
      (session[session_idx].sock == INVALID_SOCKET))
    return FALSE;

  /* Read packet header */

  p = (unsigned char*)&in_packet_header;
  buff_bytes = 0;
  do {
    rcv_len = IN_PKT_HDR_BYTES - buff_bytes;

    if (session[session_idx].is_local) {
      if ((rcvd_bytes = read(session[session_idx].RxPipe[0], p, rcv_len)) < 0)
        return FALSE;
    } else {
      if ((rcvd_bytes = recv(session[session_idx].sock, p, rcv_len, 0)) <= 0)
        return FALSE;
    }
    if (rcvd_bytes <= 0)
      return FALSE;

    buff_bytes += rcvd_bytes;
    p += rcvd_bytes;
  } while (buff_bytes < IN_PKT_HDR_BYTES);

  /* Calculate remaining bytes to read */

  packet_bytes = LongInt(in_packet_header.packet_length) - IN_PKT_HDR_BYTES;

  if (srvr_debug != NULL) {
    fprintf(srvr_debug, "IN (%d bytes)\n", packet_bytes);
  }

  if (packet_bytes >= buff_size) /* Must reallocate larger buffer */
  {
    free(buff);
    n = (packet_bytes + BUFF_INCR) & ~(BUFF_INCR - 1);
    buff = (INBUFF*)malloc(n);
    if (buff == NULL)
      return FALSE;
    buff_size = n;

    if (srvr_debug != NULL) {
      fprintf(srvr_debug, "Resized buffer to %d bytes\n", n);
    }
  }

  /* Read data part of packet */

  p = (unsigned char*)buff;
  buff_bytes = 0;
  while (buff_bytes < packet_bytes) {
    rcv_len = min(buff_size - buff_bytes, 16384);
    if (session[session_idx].is_local) {
      if ((rcvd_bytes = read(session[session_idx].RxPipe[0], p, rcv_len)) < 0)
        return FALSE;
    } else {
      if ((rcvd_bytes = recv(session[session_idx].sock, p, rcv_len, 0)) <= 0)
        return FALSE;
    }

    if (rcvd_bytes <= 0)
      return FALSE;

    buff_bytes += rcvd_bytes;
    p += rcvd_bytes;
  }

  ((char*)buff)[buff_bytes] = '\0';

  if (srvr_debug != NULL)
    debug((unsigned char*)buff, buff_bytes);

  session[session_idx].server_error = ShortInt(in_packet_header.server_error);
  session[session_idx].sd_status = LongInt(in_packet_header.status);

  return TRUE;
}

/* ======================================================================
   write_packet()  -  Send SD data packet                                 */

Private bool write_packet(int type, char* data, int32_t bytes) {
  struct {
    int32_t length;
    int16_t type;
  } ALIGN2 packet_header;
#define PKT_HDR_BYTES 6

  if ((!session[session_idx].is_local) &&
      (session[session_idx].sock == INVALID_SOCKET))
    return FALSE;

  packet_header.length = LongInt(bytes + PKT_HDR_BYTES); /* 0272 */
  packet_header.type = ShortInt(type);

  if (session[session_idx].is_local) {
    if (write(session[session_idx].TxPipe[1], (char*)&packet_header,
              PKT_HDR_BYTES) != PKT_HDR_BYTES)
      return FALSE;
  } else {
    if (send(session[session_idx].sock, (unsigned char*)&packet_header,
             PKT_HDR_BYTES, 0) != PKT_HDR_BYTES)
      return FALSE;
  }

  if (srvr_debug != NULL) {
    fprintf(srvr_debug, "OUT (%d bytes). Type %d\n", packet_header.length,
            (int)packet_header.type);
  }

  if ((data != NULL) && (bytes > 0)) {
    if (session[session_idx].is_local) {
      if (write(session[session_idx].TxPipe[1], data, bytes) != bytes)
        return FALSE;
    } else {
      if (send(session[session_idx].sock, data, bytes, 0) != bytes)
        return FALSE;
    }

    if (srvr_debug != NULL)
      debug((unsigned char*)data, bytes);
  }

  return TRUE;
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

/* ======================================================================
   sysdir()  -  Return static SDSYS directory pointer                     */

Private char* sysdir() {
  static char sysdirpath[MAX_PATHNAME_LEN + 1] = "";
  char inipath[MAX_PATHNAME_LEN + 1];
  char section[50];
  char rec[200 + 1];
  FILE* fu;
  char* p;
 /* 20240219 mab correct env name */
  p = getenv("SD_CONFIG");  /* was QMCONFIG */ /* Issue #29 */
  if (p != NULL)
    strcpy(inipath, p);
  else
    strcpy(inipath, "/etc/sd.conf"); // was sdconfig

  fu = fopen(inipath, FOPEN_READ_MODE);
  if (fu == NULL) {
    sprintf(session[session_idx].sderror, "%s not found", inipath);
    return NULL;
  }

  section[0] = '\0';
  while (fgets(rec, 200, fu) != NULL) {
    if ((p = strchr(rec, '\n')) != NULL)
      *p = '\0';

    if ((rec[0] == '#') || (rec[0] == '\0'))
      continue;

    if (rec[0] == '[') {
      if ((p = strchr(rec, ']')) != NULL)
        *p = '\0';
      strcpy(section, rec + 1);

      for (p = section; *p != '\0'; p++)
        *p = UpperCase(*p);
      continue;
    }

    if (strcmp(section, "SD") == 0) /* [sd] items */
    {
      if (strncmp(rec, "SDSYS=", 6) == 0) {
        strcpy(sysdirpath, rec + 6);
        break;
      }
    }
  }

  fclose(fu);

  if (sysdirpath[0] == '\0') {
    sprintf(session[session_idx].sderror,
            "No SDSYS parameter in configuration file");
    return NULL;
  }

  return sysdirpath;
}

/* ====================================================================== */

Private void initialise_client() {
  int16_t i;

  if (buff == NULL) {
    set_default_character_maps();

    buff_size = 2048;
    buff = (INBUFF*)malloc(buff_size);

    for (i = 0; i < MAX_SESSIONS; i++) {
      session[i].context = CX_DISCONNECTED;
      session[i].is_local = FALSE;
      session[i].sderror[0] = '\0';
      session[i].sock = INVALID_SOCKET;
      session[i].RxPipe[0] = -1;
      session[i].RxPipe[1] = -1;
      session[i].TxPipe[0] = -1;
      session[i].TxPipe[1] = -1;
    }
    /* rev 0.9.0  initialize the arg pointer array for Callx */
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
    strcpy(session[session_idx].sderror, "Too many sessions");
    return FALSE;
  }

  session_idx = i;
  return TRUE;
}

/* ====================================================================== */

Private void  disconnect() {
  /* rev 0.9.0 */
   int16_t i;

  (void)write_packet(SrvrQuit, NULL, 0);
  if (session[session_idx].is_local) {
    if (session[session_idx].RxPipe[0] >= 0) {
      close(session[session_idx].RxPipe[0]);
      session[session_idx].RxPipe[0] = -1;
    }
    if (session[session_idx].RxPipe[1] >= 0) {
      close(session[session_idx].RxPipe[1]);
      session[session_idx].RxPipe[1] = -1;
    }
    if (session[session_idx].TxPipe[0] >= 0) {
      close(session[session_idx].TxPipe[0]);
      session[session_idx].TxPipe[0] = -1;
    }
    if (session[session_idx].TxPipe[1] >= 0) {
      close(session[session_idx].TxPipe[1]);
      session[session_idx].TxPipe[1] = -1;
    }
    waitpid(session[session_idx].pid, NULL, 0); /* 0421 */
  } else {
    (void)CloseSocket();
  }

  session[session_idx].context = CX_DISCONNECTED;

 /* rev 0.9.0 
  I cannot find where the original transfer buffer "buff" is freed on exit
	So look for connected session, if none, release buffer                */

  for (i = 0; i < MAX_SESSIONS; i++) {
	  if (session[i].context == CX_CONNECTED)
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

#ifdef BIG_ENDIAN_SYSTEM
/* ======================================================================
   swap2()                                                                */

int16_t swap2(int16_t data) {
  union {
    int16_t val;
    unsigned char chr[2];
  } in, out;

  in.val = data;
  out.chr[0] = in.chr[1];
  out.chr[1] = in.chr[0];
  return out.val;
}

/* ======================================================================
   swap4()                                                                */

int32_t swap4(int32_t data) {
  union {
    int32_t val;
    unsigned char chr[4];
  } in, out;

  in.val = data;
  out.chr[0] = in.chr[3];
  out.chr[1] = in.chr[2];
  out.chr[2] = in.chr[1];
  out.chr[3] = in.chr[0];
  return out.val;
}

#endif

/* When building a simply .o file instead of a DLL, we need to import
      the routines from ctype.c into this module.                        */

#include "ctype.c"

/* END-CODE */
