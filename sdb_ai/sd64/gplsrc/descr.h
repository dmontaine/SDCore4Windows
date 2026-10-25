/* DESCR.H
 * Descriptor definitions
 * Copyright (c) 2007 Ladybridge Systems, All Rights Reserved
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
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
 * START-HISTORY:
 * 18 Oct 26 dm S.65 slice 3e: the NET member of the FILE_VAR union gains write (the handle was opened in write mode) and edit_kind (the S.64
 *           kind of the remote file's name), after server; 16 + 2 + 2 + 17 + 2 = 39 bytes, within the union's 40.
 * 17 Oct 26 dm S.65 slice 3c: NET_FILE (4) is back, for a file on another SD server (SDNet, stage 1); its member of the FILE_VAR union holds the
 *           handle of the $netfile handler and the server name.  The file table entry of such a file variable is NOT a real one (file_id is -1).
 * 31 Dec 23 SD launch - prior history suppressed
 * 25 Aug 26 Windows port - VFS stripped: the C never implemented it
 * 25 Aug 26 Windows port - NET_FILE removed.  Its last reader went with
 *           netfiles.c on 18 Aug 26 (sd.h) and it had no other.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Every variable is represented by a DESCRIPTOR structure.  In some cases
 * this holds all the data associated with the variable.  In other cases it
 * contains pointers to other structures.
 *
 * UNASSIGNED   All local variable start out in this state.
 *
 * ADDR         A pointer to another descriptor.
 *
 * INTEGER      A 32 bit integer value.
 *
 * FLOATNUM     A floating point number.
 *
 * SUBR         A pointer to a memory resident Q_MBasic program.
 *              Created by CALL transforming a character string holding the
 *              name of the subroutine.  This string is still available via
 *              a pointer in the descriptor.
 *
 * STRING       A character string.
 *              Strings are stored as a series of STRING_CHUNK structures. By
 *              holding strings in this way, some operations such as
 *              concatenation are much faster than using contiguous strings.
 *              Conversely, some operations are slower.
 *              The actual string represented by the string chunks may be
 *              referenced by more than one descriptor. This is controlled
 *              using a reference count in the first chunk.
 *              The rmv_saddr and n1 elements of the descriptor are only
 *              significant if the DF_REMOVE flag is set in which case they
 *              point to the string chunk and offset within that chunk of the
 *              current remove pointer position.
 *
 * FILE_REF     A file variable.
 *              Points to a FILE_VAR structure.  This includes a reference
 *              count to allow multiple descriptors to share a FILE_VAR.
 *
 * ARRAY        An array.
 *              Points to an ARRAY_HEADER structure.  Again, this has a
 *              reference count.  The array header contains information about
 *              the array dimensions and points to a list of ARRAY_CHUNK
 *              structures.  This two level approach significantly improves
 *              performance of redimensioning arrays.
 *
 * COMMON       A common block.
 *              Common blocks are actually held as arrays, each element of
 *              which is an entry from the common declaration, perhaps also an
 *              array.  The common blocks are chained together through the
 *              next_common item in the array header. Element 0 of the common
 *              "array" is the name of the block, the remaining elements are
 *              the common itself. The chain has its head in named_common. The
 *              blank common is addressed by blank_common.
 *
 * IMAGE        A screen image.
 *              Points to a SCREEN_IMAGE structure: a reference id and the
 *              size and place of the region.  The terminal does not keep
 *              the picture (AccuTerm and SDTerm did; neither is supported).
 *             
 * BTREE        A binary tree data item.
 *              Not accessible to user mode programs (because it's a bit
 *              awkward to use), these are used internally by the SDBasic
 *              compiler and the query processor for fast access tables.
 *
 * SELLIST      A select list variable.
 *              Used by SDBasic operations that work with select list
 *              variables as distinct from numbered select lists.  Because this
 *              variable type was introduced late in the life of SD, the
 *              numbered lists are handled differently.
 *
 * PMATRIX      Pick style systems use a different form of matrix than 
 *              Information style systems. Firstly, Pick matrices have no zero
 *              element. Secondly, a Pick matrix in a common block is just a
 *              list of simple data items. Both styles have their advantages
 *              and disadvantages. SD supports both, though the Information
 *              style is the default. The PMATRIX descriptor defines a Pick
 *              style matrix in a common block.
 *
 * SOCK         Socket.
 *
 * LOCALVARS    A local variable pool.
 *              Local variables are held as arrays in exactly the same way as
 *              common. As far as the program using them is concerned, they
 *              are common variables.
 *              To allow for recursion, entry to an internal subroutine that
 *              declares local variables will stack any previous incarnation
 *              of the local variable pool by chaining it on to the next_common
 *              item in the array header.
 *
 * OBJ          Object.
 *
 * OBJCD        Object code pointer for property access.
 *
 * OBJCDX       Undefined object routine reference (variant on OBJCD)
 *
 * PERSISTENT   Persistent public and private variables of a CLASS module.
 *              For most purposes, this is the same as a COMMON block. The
 *              most significant difference is that element 0 is not
 *              reserved for the block name but is available for normal use.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* ====================================================================== */

/* Data descriptor */

struct DESCRIPTOR {
  u_char type; /* Item type */
  u_char flags;
#ifdef BIG_ENDIAN_SYSTEM
#define InitDescr(d, t) *((int16_t*)(d)) = ((t) << 8)
#else
#define InitDescr(d, t) *((int16_t*)(d)) = t
#endif
  int16_t n1;
  /* OBJCDX:
         Key value for OBJCODE reference.
     STRING:
         Remove pointer offset into chunk pointed to by
         rmv_saddr element of the descriptor. Using Q_MBasic
         character position numbers, this points to the
         character before the next one to be extracted.
         When the end of the string is reached, it points
         one character off the end of the string.
   */
  union {
    /* ADDR */
    DESCRIPTOR* d_addr; /* Ptr to descriptor (ADDR) */

    /* INTEGER */
    int32_t value; /* Value */

    /* FLOATNUM */
    double float_value; /* Value */

    /* SUBR */
    struct {
      void* object;
      STRING_CHUNK* saddr;
    } subr;

    /* STRING, SELLIST */
    struct {
      STRING_CHUNK* saddr;
      STRING_CHUNK* rmv_saddr; /* Ptr to current chunk */
    } str;

    /* FILE_REF */
    FILE_VAR* fvar; /* File var */

    /* ARRAY */
    ARRAY_HEADER* ahdr_addr;

    /* COMMON and PERSISTENT */
    ARRAY_HEADER* c_addr;

    /* IMAGE */
    SCREEN_IMAGE* i_addr;

    /* BTREE */
    BTREE_HEADER* btree;

    /* PMATRIX */
    PMATRIX_HEADER* pmatrix;

    /* SOCK */
    SOCKVAR* sock;

    /* LOCALVARS */
    ARRAY_HEADER* lv_addr;

    /* OBJ */
    OBJDATA* objdata;

    /* COLL */
    COLL_HEADER* coll;

    /* OBJCD */
    struct {
      OBJDATA* objdata; /* Object associated with this data */
      u_int16_t key;    /* Key value */
      u_char arg_ct;    /* Arg count + var args flag */
    } objcode;

    /* OBJCDX */
    struct {
      OBJDATA* objdata; /* Object associated with this data */
      char* undefined_name;
    } objundef;

    /* Debugging */
    struct {
      int32_t w1;
      int32_t w2;
    } dbg;
  } data;
};

/* Descriptor types (Also in BP INT$KEYS.H) */
#define UNASSIGNED 0
#define ADDR 1
#define INTEGER 2
#define FLOATNUM 3
#define COMPLEX_DESCR 4 /* Descriptors with types greater than or equal
                         * to this value have subordinate data which
                         * must be handled by k_release().              
                         */
#define SUBR 4
#define STRING 5
#define FILE_REF 6
#define ARRAY 7
#define COMMON 8
#define IMAGE 9
#define BTREE 10
#define SELLIST 11
#define PMATRIX 12
#define SOCK 13
#define LOCALVARS 14
#define OBJ 15
#define OBJCD 16
#define OBJCDX 17
#define PERSISTENT 18
#define COLL 19 /* Data collection or array in a collection (13 Oct 26) */

/* When adding new entry, all places that include a comment containing
   ++ALLTYPES++ must be amended.                                       */
/* This list is also in BP DEBUG.H */

/* Flags */
#define DF_REUSE 0x01  /* Set by reuse function */
#define DF_REMOVE 0x02 /* Remove pointer active */
#define DF_ARG 0x04    /* Argument pointer */
#define DF_WATCH 0x08  /* Set by debug watch, cleared by data change */
#define DF_ARGSET 0x10 /* Set on callv arg vars, cleared by data change */
#define DF_SYSTEM 0x20 /* Set on system variables (STORSYS opcode) */
#define DF_MOVE 0x40   /* Move descr in object function/subr call */
#define DF_CHANGE (DF_WATCH | DF_ARGSET) /* Flags to clear on change */
#define DF_JSON 0x80 /* INTEGER 0 or 1: a JSON boolean; null STRING: a JSON null.
                        Made by JBOOLEAN() and JNULL() and by reading such an element
                        of a data collection; any new result is a plain value. */

/* ====================================================================== */

/* --------------- String descriptor STRING --------------- */

struct STRING_CHUNK {
  STRING_CHUNK* next; /* Ptr to next chunk */
  int16_t alloc_size; /* Allocated space excluding header */
  int16_t bytes;      /* Actual used bytes */
  /* The following are only valid in the first chunk */
  int32_t string_len; /* Total length of all chunks */
  int32_t field;      /* Hint field number and... */
  int32_t offset;     /* ...offset. In SELLIST this is item count */
  int16_t ref_ct;     /* Reference count */
  char data[1];
} ALIGN2; /* Making this struct align on a 2 byte boundary cleared up a warning when 
           * a struct of DH_RECORD was being cast to STRING_CHUNK in dh_ak.c, around
           * line #3414. 09Jan22 gwb
           */

#define STRING_CHUNK_HEADER_SIZE (offsetof(STRING_CHUNK, data))
#define MAX_STRING_CHUNK_SIZE ((signed int)(16384 - STRING_CHUNK_HEADER_SIZE))

/* ------------------ File descriptor FILE_REF ------------------ */

typedef struct SQ_FILE SQ_FILE;
struct SQ_FILE {
  OSFILE fu;         /* -ve if open to create */
  char* buff;        /* Buffer */
  int64 posn;        /* File: File position
                        Port: Offset into buffer */
  int64 line;        /* Current line no */
  int64 base;        /* Base address of block */
  char* record_name; /* Record id */
  int16_t record_name_len;
  int16_t bytes;   /* Bytes in buffer */
  char* pathname;  /* File pathname */
  int32_t timeout; /* Timeout, -ve if none */
  u_int16_t flags;
#define SQ_NOBUF 0x0001 /* Unbuffered */
#define SQ_DIRTY 0x0002 /* Buffer needs writing */
#define SQ_PORT 0x0004  /* Is a port */
#define SQ_CHDEV 0x0008 /* Character mode device */
#define SQ_FIFO 0x0010  /* FIFO */
#define SQ_NOTFL 0x001C /* Mask for "files" that aren't files */
  u_char crlf;           /* Line terminator mode: CRLF_UNSET or CRLF_x (below) */
};

/* Line terminator modes of a directory file or a sequential file (openQM FC$CRLF, 16 Oct 26, QM4 Fixes item 452).  The value
   kept in the file is 0 (CRLF_UNSET) until a mode is chosen, by FCONTROL(fvar, FC$CRLF, mode) or by a letter in field 6 of the
   F-type VOC entry (L C B X), and the mode + 1 after.  UNSET is the behaviour SD always had: a directory file READ ends a line
   at LF and keeps every CR, WRITE ends it with LF; READSEQ ends a line at LF and drops a CR in front of it, WRITESEQ writes LF. */
#define CRLF_UNSET 0
#define CRLF_LF 1   /* mode 0: LF ends a line, CR is data;                              VOC letter L */
#define CRLF_CRLF 2 /* mode 1: CR LF ends a line, a lone CR or LF is data;               VOC letter C */
#define CRLF_BOTH 3 /* mode 2: CR LF or LF ends a line, a lone CR is data;               VOC letter B */
#define CRLF_NOCR 4 /* mode 3: CR LF or LF ends a line, a lone CR is thrown away;        VOC letter X */

/* The trigger function of a directory file (16 Oct 26, QM4 Fixes item 177).  A hashed file keeps its trigger in its header (DH_FILE);
   a directory file has no header, so its trigger is named in a file called %header% in the directory, read when the file is opened
   and kept here for the life of the file variable.  A change to the trigger is seen by the next OPEN of the file, not this one. */
typedef struct DIR_TRIGGER DIR_TRIGGER;
struct DIR_TRIGGER {
  char* name;      /* The function, in lower case */
  u_char* trigger; /* Its object code, or NULL if it is not catalogued (the first call that needs it says so) */
  u_char modes;    /* TRG_x: the operations that call it */
};

/* NET_FILE: the longest server name (the shape set.server and $netfile hold: a lower case letter, then letters and digits) and the most
   remote files one process may have open (NF$MAX.HANDLES in sdsys/gpl.bp/netfile.h - keep the two in step) */
#define NET_SERVER_LEN 16
#define NET_MAX_HANDLES 100

/* File variable structure
   See !!FVAR_CREATE!! and !!FVAR_DESTROY!! */
struct FILE_VAR {
  int16_t ref_ct;  /* Reference count */
  int16_t file_id; /* File table index */
  int32_t index;   /* Sequential reference counter */
  u_char type;
/* !!FVAR_TYPES!! */
#define INITIAL_FVAR 0
#define DIRECTORY_FILE 1
#define DYNAMIC_FILE 2
#define SEQ_FILE 3
/* 4 is NET_FILE again (17 Oct 26, S.65 slice 3c): a file on another SD server, reached through the $netfile handler (netfiles.c).
   It has NO file table entry (file_id is -1), so nothing may reach FPtr(fvar->file_id) or fvar->access.dh / .dir for it:
   every opcode that takes a file variable either supports it (OPEN, CLOSE, READ, READV, FILEINFO) or refuses it with net_refuse().
   5 was VFS_FILE - the virtual file system scaffolding removed (plan G2); the slot is left unused rather than renumbering.
   Neither value is persisted: fvar->type lives only in the runtime FILE_VAR. */
#define NET_FILE 4
  /* Tokens also in BP DEBUG.H */
  u_char flags;
#define FV_RDONLY 0x01  /* Read only file */
#define FV_NON_TXN 0x02 /* Updates are non-transactional */
  int16_t id_len;       /* Length of id and... */
  char* id;             /* ...actual id of last record read */
  char* voc_name;

  union {
    struct {
      DH_FILE* dh_file; /* DH_FILE structure */
      AK_CTRL* ak_ctrl; /* AK control data */
    } dh;
    struct {
      SQ_FILE* sq_file; /* SQ_FILE structure */
    } seq;
    struct {
      u_int16_t mark_mapping : 1;
      u_int16_t crlf : 3; /* CRLF_UNSET or CRLF_x */
      DIR_TRIGGER* trg;   /* The file's trigger function, or NULL */
    } dir;
    /* NET_FILE (S.65 slice 3c).  The two pointer-sized words in front are zeroed by net_open() so that they read as a NULL
       access.dir.trg, should any code that only expects a directory file look at one.  handle is the one $netfile gave (1 to
       NET_MAX_HANDLES, 0 once closed); epoch is net_epoch when it was opened, and a handle from an earlier epoch (net_close_all(),
       i.e. a LOGTO) is stale and is never sent; server is the server's name in lower case. */
    struct {
      void* zero[2];
      int16_t handle;
      u_int16_t epoch;
      char server[NET_SERVER_LEN + 1];
      u_char write;     /* 18 Oct 26 S.65 slice 3e: 1 when the handle was opened in write mode (rc<7> of NF$OPEN), 0 for a read mode handle */
      u_char edit_kind; /* 18 Oct 26 S.65 slice 3e: EDIT_NONE/EDIT_VOC/EDIT_DICT/EDIT_PROG of the REMOTE file's name (edit_kind_of_net_name) */
    } net;
  } access;
};

/* ------------------ Array descriptor ARRAY ------------------ */

#define MAX_ARRAY_CHUNK_SIZE 200 /* Max elements in a single chunk */

struct ARRAY_CHUNK {
  int16_t num_descr;
  int16_t pad;
  DESCRIPTOR descr[1];
};

struct ARRAY_HEADER {
  int16_t ref_ct;
  u_int16_t flags;
/* These tokens are also in BP INT$KEYS.H */
#define AH_PICK_STYLE 0x0001  /* Pick style matrix */
#define AH_AUTO_DELETE 0x0002 /* Self-deleting common block */
  int32_t rows;
  int32_t cols;              /* Zero if one dimension */
  int32_t alloc_elements;    /* Allocated descriptors and... */
  int32_t used_elements;     /* ...number actually used (could have
                                       redimensioned to smaller size) */
  ARRAY_HEADER* next_common; /* Chain linking named common */
  int16_t num_chunks;        /* Entries in chunk array below. There may
                                       be unused entries at the end of the
                                       array which will be set to NULL.      */
  int16_t pad;
  ARRAY_CHUNK* chunk[1];
};

/* Macro to find an array element given its header and element offset */
#define Element(hdr, n) \
  (&(hdr->chunk[(n) / MAX_ARRAY_CHUNK_SIZE]->descr[(n) % MAX_ARRAY_CHUNK_SIZE]))

/* ------------------ Screen image IMAGE ------------------ */

struct SCREEN_IMAGE {
  int16_t ref_ct;
  int16_t pad;
  void* buffer; /* Screen image data */
  int16_t x;    /* Left edge of block */
  int16_t y;    /* Top edge of block */
  int16_t w;    /* Width of block */
  int16_t h;    /* Height of block */
  int16_t line; /* Cursor line position */
  int16_t col;  /* Cursor column position */
  int16_t pagination;
  int16_t attr; /* ms8 = Inverse, ls8 = attr */
  int32_t id;
};

/* ------------------ Binary Tree BTREE ------------------ */

typedef struct BTREE_ELEMENT BTREE_ELEMENT;
struct BTREE_ELEMENT {
  BTREE_ELEMENT* parent;
  BTREE_ELEMENT* left;
  BTREE_ELEMENT* right;
  char* data;
  char* key[1];
};

struct BTREE_HEADER {
  int16_t ref_ct;
  int16_t pad;
  BTREE_ELEMENT* head;
  BTREE_ELEMENT* current;
  u_char keys;
  u_char flags[1];
/* Additive flags values: */
#define BT_RIGHT_ALIGNED 0x01
#define BT_DESCENDING 0x02
#define BT_UNIQUE 0x04
#define BT_DATA 0x08 /* Has data element */
};

/* ---------------------- PMATRIX ------------------------ */

struct PMATRIX_HEADER {
  DESCRIPTOR* com_descr; /* Associated COMMON */
  u_int16_t base_offset; /* Where is element 1 */
  u_int16_t rows;
  u_int16_t cols; /* Zero if one dimension */
};

/* ------------------------ SOCK ------------------------- */

struct SOCKVAR {
  int ref_ct;
  int socket_handle;
  int port;     /* Port number */
  int protocol; /* protocol to use... */
  int family;   /* PF_INET or PF_INET6 */

#define SKT_STREAM 0x00000000
#define SKT_DGRM 0x00000100
#define SKT_RAW 0x00000200

#define SKT_TCP 0x00000000
#define SKT_UDP 0x00010000
#define SKT_ICMP 0x00020000
  u_int16_t flags;
#define SKT_BLOCKING 0x0001     /* Blocking mode */
#define SKT_NON_BLOCKING 0x0002 /* Non-blocking (Irrelevant here) */
#define SKT_SERVER 0x0004       /* Opened with CREATE.SERVER.SOCKET */
#define SKT_INCOMING 0x0008     /* Opened with ACCEPT.SOCKET.CONNECTION */
#define SKT_USER_MASK 0x0001    /* Flags settable by user */
  /* 20240219 mab mods to handle AF_UNIX sockets */
  char ip_addr[MAX_SOCKET_ADDR_STR_LEN];             /* IP address,IPv4 or IPv6 or AF_UNIX sockets */
  /* 15 Sep 26 Windows port - S.19/RELEASE_1.1 41: an SD_TLS_CLIENT* when
     OPEN.SOCKET was given SKT$TLS, else NULL.  Every k_alloc of a SOCKVAR
     must set it - k_alloc does not zero. */
  void* tls;
  /* 15 Oct 26 dm - QM4 gaps Q-5, SELECT.SOCKET().  The events to watch (SKT_READ_EVENT 1, SKT_WRITE_EVENT 2,
     SKT_EXCEPTION_EVENT 4) and those the last SELECT.SOCKET() found.  Every k_alloc of a SOCKVAR must set both. */
  int16_t events;
  int16_t found;
};

/* --------------------- COLL (data collection) --------------------- */

/* A data collection is either an object (name / value pairs, held sorted by
   name) or an array (values only, position 1 upward).  It is reference
   counted: a copy of the descriptor is another reference to the same
   collection.  A collection that contains itself is never freed.         */

struct COLL_ENTRY {
  char* name;       /* NULL in an array */
  int32_t name_len;
  DESCRIPTOR d;     /* INTEGER, FLOATNUM, STRING or COLL */
  u_char tag;       /* How d is to be read and written out */
#define CT_PLAIN 0
#define CT_BOOL 1   /* d is INTEGER 0 or 1, JSON true / false */
#define CT_NULL 2   /* d is a null string, JSON null */
};

struct COLL_HEADER {
  int32_t ref_ct;
  u_char is_array;
  int32_t count;
  int32_t alloc;
  COLL_ENTRY* e;
};

/* -------------------- OBJECT NAME MAP ------------------ */

typedef struct OBJECT_NAME_MAP OBJECT_NAME_MAP;
struct OBJECT_NAME_MAP /* This is embedded in the object code */
{
  /* Multi-byte items are always low byte first because the object stream
    is machine architecture independent                                  */
  u_char next;       /* Offset of next entry, zero in last entry */
  u_char lo_var;     /* Public var no, ls 8 bits */
  u_char hi_var;     /* Public var no, ms 8 bits */
  u_char lo_set;     /* SET routine / method subroutine key, ls 8 bits */
  u_char hi_set;     /* SET routine / method subroutine key, ms 8 bits */
  u_char lo_get;     /* GET routine / method subroutine key, ls 8 bits */
  u_char hi_get;     /* GET routine / method function key, ms 8 bits */
  u_char set_arg_ct; /* SET routine / method subroutine arg count */
  u_char get_arg_ct; /* GET routine / method function arg count */
  char name[1];      /* Item name, upper case, null terminated */
};
/* Notes:
   The public variable number is negative if it is read-only.
   The two arg count items use the top bit to indicate that the
   routine is declared as VAR.ARGS.                                   */

/* 16 Oct 26 dm - RESTRICTED: the top bit of hi_set marks a name declared RESTRICTED (visible only to an object in the inheritance
   tree of the class that declares it).  A set key never needs 15 bits, so the key is the other seven.  Objects compiled before
   the statement existed have the bit clear. */
#define SetKey(p) ((p)->lo_set + ((int16_t)((p)->hi_set & 0x7F) << 8))
#define IsRestricted(p) (((p)->hi_set & 0x80) != 0)
#define GetKey(p) ((p)->lo_get + ((int16_t)((p)->hi_get) << 8))
#define PublicVar(p) ((p)->lo_var + ((int16_t)((p)->hi_var) << 8))
#define NextNameMapEntry(p) \
  (((p)->next == 0) ? NULL : ((OBJECT_NAME_MAP*)(((char*)(p)) + ((p)->next))))

/* ----------------------- OBJUNDEF ---------------------- */

struct OBJUNDEF /* An undefined object handler reference */
{
  int ref_ct;
  OBJDATA* objdata;     /* Object associated with this data */
  char* undefined_name; /* The handler name we could not find */
  u_int16_t key;        /* Key value */
};

/* ------------------------- OBJ -------------------------

   Object A inherits B and C
   B inherits D
   C inherits E

   -----   -----   -----        In this diagram, the link to the right
   | A |---| B |---| D |        is the "inherits" pointer and the link
   -----   -----   -----        below is the "next_inherited" pointer.
             |
           -----   -----
           | C |---| E |
           -----   -----
*/

/* 16 Oct 26 dm - QM4 Fixes item 13: a name map of NAME_INDEX_MIN entries or more is looked up through a hash index built the
   first time a name is sought in it, instead of by scanning the map for every reference.  The index holds the entries in map
   order (a name can appear more than once: a RESTRICTED entry the caller cannot see is skipped for the next of its name) and
   chains the entries of one hash value in that order.  Every k_alloc of an OBJDATA must set name_count to -1 and name_index to
   NULL (k_alloc does not zero): create_objdata() does. */
#define NAME_INDEX_MIN 32
typedef struct NAME_INDEX NAME_INDEX;
struct NAME_INDEX {
  int32_t nbuckets;
  int32_t* bucket;            /* First entry (a position in entry[]) of each hash value, or -1 */
  int32_t* next;              /* The next entry of the same hash value, or -1 */
  OBJECT_NAME_MAP** entry;    /* The name map entries, in map order */
};

struct OBJDATA /* The object itself */
{
  int ref_ct;                /* Reference count */
  void* objprog;             /* Object program pointer */
  OBJECT_NAME_MAP* name_map; /* Start of name map */
  int32_t name_count;        /* Entries in the name map, or -1 until the first lookup counts them */
  NAME_INDEX* name_index;    /* The hash index, or NULL (map too small to need one, or not yet built) */
  ARRAY_HEADER* obj_vars;    /* PUBLIC and GLOBAL data array */
  OBJDATA* inherits;         /* Head of inherited objects list */
  OBJDATA* next_inherited;   /* Links further items in inheritance chain */
  bool destructor_run;       /* Set on calling destructor to avoid loops */
};

/* ====================================================================== */

#define Release(d)                \
  if ((d)->type >= COMPLEX_DESCR) \
  k_release(d)
#define IncrRefCt(d)              \
  if ((d)->type >= COMPLEX_DESCR) \
  k_incr_refct(d)

#define GetBool(d)          \
  if ((d)->type != INTEGER) \
  k_get_bool(d)
#define GetInt(d)           \
  if ((d)->type != INTEGER) \
  k_get_int(d)
#define GetInt32(d)         \
  if ((d)->type != INTEGER) \
  k_get_int32(d)
#define GetNum(d)                                        \
  if (((d)->type != INTEGER) && ((d)->type != FLOATNUM)) \
  k_get_num(d)
#define GetString(d)       \
  if ((d)->type != STRING) \
  k_get_string(d)

/* END-CODE */
