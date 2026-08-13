/* KEYS.H
 * Keys for C implementation of BASIC functions
 * Copyright (c) 2006 Ladybridge Systems, All Rights Reserved
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
 * 31 Dec 23 SD launch - prior history suppressed 
 * 28 Jul 24 mab SD_ENCRYPT_SODIUM encode types
 * 08 Aug 24 mab SDEXT keys for salt and key from password
 * 09 Aug 24 mab embedded python SDEXT keys
 * rev 0.9.0 Jan 25 mab SD_EUID_SET SD_EUID_RESTORE
 * rev 0.9-2 Mar 25 mab add sdext_pyobj direct control of python dictionary object
 * 
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* FLAGS argument to $INPUT */
#define IN_FIELD_MODE     0x0001
#define IN_UPCASE         0x0002
#define IN_DISPLAY        0x0010
#define IN_NOCRLF         0x0020
#define IN_NOLF           0x0040
#define IN_NOT_DATA       0x0080
#define IN_MASK           0x0100
#define IN_ERR_DISPLAYED  0x0200
#define IN_PASSWORD       0x0400
#define IN_TIMEOUT        0x0800
#define IN_THENELSE       0x1000

/* FILEINFO() function keys */
#define FL_OPEN            0
#define FL_VOCNAME         1
#define FL_PATH            2
#define FL_TYPE            3
   #define FL_TYPE_DH      3  /* DH file */
   #define FL_TYPE_DIR     4  /* Directory file */
   #define FL_TYPE_SEQ     5  /* Sequential file */
   #define FL_TYPE_VFS     6  /* VFS */
#define FL_MODULUS         5
#define FL_MINMOD          6
#define FL_GRPSIZE         7
#define FL_LARGEREC        8
#define FL_MERGE           9
#define FL_SPLIT          10
#define FL_LOAD           11
#define FL_AK             13
#define FL_LINE           14
/* Values over 1000 are specific to Q_M */
#define FL_LOADBYTES    1000
#define FL_READONLY     1001
#define FL_TRIGGER      1002
#define FL_PHYSBYTES    1003
#define FL_VERSION      1004
#define FL_STATS_QUERY  1005
#define FL_SEQPOS       1006
#define FL_TRG_MODES    1007
#define FL_NOCASE       1008
#define FL_FILENO       1009
#define FL_JNL_FNO      1010
#define FL_AKPATH       1011
#define FL_ID           1012
#define FL_STATUS       1013
#define FL_MARK_MAPPING 1014
#define FL_RECORD_COUNT 1015
#define FL_PRI_BYTES    1016
#define FL_OVF_BYTES    1017
#define FL_NO_RESIZE    1018
#define FL_UPDATE       1019
#define FL_ENCRYPTED    1020

/* Values over 10000 are restricted */
#define FL_EXCLUSIVE   10000
#define FL_FLAGS       10001
#define FL_STATS_ON    10002
#define FL_STATS_OFF   10003
#define FL_STATS       10004
#define FL_SETRDONLY   10005


/* RECORDLOCKED() function return values */
#define LOCK_OTHER_FILELOCK  -3
#define LOCK_OTHER_READU     -2
#define LOCK_OTHER_READL     -1
#define LOCK_NO_LOCK          0
#define LOCK_MY_READL         1
#define LOCK_MY_READU         2
#define LOCK_MY_FILELOCK      3

/* KERNEL() function action keys.
   Not all apply to GPL version. GPL developers should use values over
   1000 to avoid clashes with change in the non-GPL source.           */
#define K_INTERNAL            0
#define K_SECURE              1
#define K_LPTRHIGH            2
#define K_LPTRWIDE            3
#define K_PAGINATE            4
#define K_FLAGS               5
#define K_DATE_FORMAT         6
#define K_CRTHIGH             7
#define K_CRTWIDE             8
#define K_SET_DATE            9
#define K_IS_PHANTOM         10
#define K_TERM_TYPE          11
#define K_USERNAME           12
#define K_DATE_CONV          13
#define K_PPID               14
#define K_USERS              15
#define K_CONFIG_DATA        16
#define K_LICENCE            17
#define K_INIPATH            18
#define K_MONITOR            19
#define K_FORCED_ACCOUNT     20
#define K_SDNET              21
#define K_CPROC_LEVEL        22
#define K_HELP               23
#define K_SUPPRESS_COMO      24
#define K_IS_SDAPISRVR       25
#define K_ADMINISTRATOR      26
#define K_FILESTATS          27
#define K_TTY                28
#define K_GET_OPTIONS        29
#define K_SET_OPTIONS        30
#define K_PRIVATE_CATALOGUE  31
#define K_SYS_ID             32
#define K_CLEANUP            33
#define K_OBJKEY             34
#define K_COMMAND_OPTIONS    35
#define K_CASE_SENSITIVE     36
#define K_PACKAGE_DATA       37
#define K_SET_LANGUAGE       38
#define K_HSM                39
#define K_COLLATION          40
#define K_GET_SDNET_CONNECTIONS  41
#define K_JNL                42
#define K_INVALIDATE_OBJECT  43
#define K_MESSAGE            44
#define K_SET_EXIT_CAUSE     45
#define K_COLLATION_NAME     46
#define K_AK_COLLATION       47
#define K_EXIT_STATUS        48
#define K_CASE_MAP           49
#define K_AUTOLOGOUT         50
#define K_MAP_DIR_IDS        51
#define K_IN_GROUP           52
#define K_BREAK_HANDLER      53
#define K_SETUID             54
#define K_SETGID             55
#define K_RUNEXE             56

/* PTERM() function action keys */
#define PT_BREAK              1
#define PT_INVERT             2
#define PT_BRKCH              3
#define PT_ONEWLINE           4
#define PT_INEWLINE           5
#define PT_BINARY_IN          6
#define PT_BINARY_OUT         7
#define PT_TELNET             8

/* SELECTINFO() function keys */
#define SL_ACTIVE       1
#define SL_COUNT        3

/* OSPATH() */
#define OS_PATHNAME     0  /* Test if valid filename */
#define OS_FILENAME     1  /* Test if valid pathname */
#define OS_EXISTS       2  /* Test if file exists */
#define OS_UNIQUE       3  /* Make a unique file name */
#define OS_FULLPATH     4  /* Return full DOS file name */
#define OS_DELETE       5  /* Delete file */
#define OS_CWD          6  /* Get current working directory */
#define OS_DTM          7  /* Get date/time modified */
#define OS_FLUSH_CACHE  8  /* Flush DH file cache */
#define OS_CD           9  /* Change working directory */
#define OS_MAPPED_NAME 10  /* Map a directory file name */
#define OS_OPEN        11  /* Check if file is open by pathanme */
#define OS_DIR         12  /* Return content of directory */
#define OS_MKDIR       13  /* Create a directory */
#define OS_MKPATH      14  /* Create a directory path */
/* 20240225 mab add CHOWN to OSPATH                       */
#define OS_CHOWN      100  /* change file / dir ownership */

/* @functions */
#define IT_CS          -1  /* Clear screen */
#define IT_CAH         -2  /* Cursor home */
#define IT_CLEOS       -3  /* Clear to end of screen */
#define IT_CLEOL       -4  /* Clear to end of line */
#define IT_SBLINK      -5  /* Start flashing text */
#define IT_EBLINK      -6  /* End flashing text */
#define IT_CUB         -9  /* Backspace one char (or count in arg 2) */
#define IT_CUU        -10  /* Cursor up one line (or count in arg 2) */
#define IT_SHALF      -11  /* Start half brightness */
#define IT_EHALF      -12  /* End half brightness */
#define IT_SREV       -13  /* Start reverse video */
#define IT_EREV       -14  /* End reverse video */
#define IT_SUL        -15  /* Start underline */
#define IT_EUL        -16  /* End underline */
#define IT_IL         -17  /* Insert line (or as count in arg 2) */
#define IT_DL         -18  /* Delete line (or as count in arg 2) */
#define IT_ICH        -19  /* Insert character (or as count in arg 2) */
#define IT_DCH        -22  /* Delete character (or as count in arg 2) */
#define IT_AUXON      -23  /* Auxillary print mode on */
#define IT_AUXOFF     -24  /* Auxillary print mode off */
#define IT_E80        -29  /* Set 80 character wide mode */
#define IT_E132       -30  /* Set 132 character wide mode */
#define IT_RIC        -31  /* Reset inhibit cursor */
#define IT_SIC        -32  /* Set inhibit cursor */
#define IT_CUD        -33  /* Cursor down one line (or as count in arg 2) */
#define IT_CUF        -34  /* Cursor right one column (or as count in arg 2) */
#define IT_FGC        -37  /* Set foreground colour */
#define IT_BGC        -38  /* Set background colour */
#define IT_SLT        -54  /* Set line truncate */
#define IT_RLT        -55  /* Reset line truncate */
#define IT_SBOLD      -58  /* Start bold */
#define IT_EBOLD      -59  /* End bold */
#define IT_PAGINATE   -79  /* Turn on screen pagination */
#define IT_NCOMO      -80  /* Suppress como output */
#define IT_COMO       -81  /* Enable como output */
#define IT_ACMD       -108 /* Asynchronous command prefix */
#define IT_SCMD       -109 /* Synchronous command prefix */
#define IT_SCREEN     -256 /* Set screen shape (Q_M_Console/Q_M_Term)*/

/* Colours for AT_FGC and AT_BGC */
#define AT_BLACK                 0
#define AT_BLUE                  1
#define AT_GREEN                 2
#define AT_CYAN                  3
#define AT_RED                   4
#define AT_MAGENTA               5
#define AT_BROWN                 6
#define AT_WHITE                 7
#define AT_GREY                  8
#define AT_BRIGHT_BLUE           9
#define AT_BRIGHT_GREEN         10
#define AT_BRIGHT_CYAN          11
#define AT_BRIGHT_RED           12
#define AT_BRIGHT_MAGENTA       13
#define AT_YELLOW               14
#define AT_BRIGHT_WHITE         15

/* PRINTER.SETTING() function action keys [THIS FUNCITON IS OBSOLETE] */
#define LPTR_WIDTH               1
#define LPTR_LINES               2
#define LPTR_TOP_MARGIN          3
#define LPTR_BOTTOM_MARGIN       4
#define LPTR_LEFT_MARGIN         5
#define LPTR_DATA_LINES          6
#define LPTR_HEADING_LINES       7
#define LPTR_FOOTING_LINES       8
#define LPTR_MODE                9
#define LPTR_NAME               10
#define LPTR_FLAGS              11
#define LPTR_LINE_NO            12
#define LPTR_PAGE_NO            13
#define LPTR_LINES_LEFT         14
#define LPTR_COPIES             15
#define LPTR_BANNER             16

/* GETPU() and SETPU mode keys */
#define PU_DEFINED               0
#define PU_MODE                  1
#define PU_WIDTH                 2
#define PU_LENGTH                3
#define PU_TOPMARGIN             4
#define PU_BOTMARGIN             5
#define PU_LEFTMARGIN            6
#define PU_SPOOLFLAGS            7
#define PU_FORM                  9
#define PU_BANNER               10
#define PU_LOCATION             11
#define PU_COPIES               12
#define PU_PAGENUMBER           15
#define PU_LINESLEFT          1002
#define PU_HEADERLINES        1003
#define PU_FOOTERLINES        1004
#define PU_DATALINES          1005
#define PU_OPTIONS            1006
#define PU_PREFIX             1007
#define PU_SPOOLER            1008
#define PU_OVERLAY            1009
#define PU_CPI                1010
#define PU_PAPER_SIZE         1011
#define PU_LPI                1012
#define PU_WEIGHT             1013
#define PU_SYMBOL_SET         1014
#define PU_STYLE              1015
#define PU_NEWLINE            1016
#define PU_PRINTER_NAME       1017
#define PU_FILE_NAME          1018
#define PU_LINENO             2000

/* SETNLS key values */

#define NLS_CURRENCY             1
#define NLS_THOUSANDS            2
#define NLS_DECIMAL              3

/* SOCKET.INFO() and SET.SOCKET.MODE() keys */
#define SKT_INFO_OPEN            0    /* Is this a socket variable? */
#define SKT_INFO_TYPE            1    /* What sort of socket is this? */
#define SKT_INFO_TYPE_SERVER    1    /* From CREATE.SERVER.SOCKET() */
#define SKT_INFO_TYPE_INCOMING  2    /* From ACCEPT.SOCKET.CONNECTION() */
#define SKT_INFO_TYPE_OUTGOING  3    /* From OPEN.SOCKET() */
#define SKT_INFO_PORT            2    /* Port number */
#define SKT_INFO_IP_ADDR         3    /* IP address */
#define SKT_INFO_BLOCKING        4    /* Blocking mode? */
#define SKT_INFO_NO_DELAY        5    /* Nagle algorithm disabled? */
#define SKT_INFO_KEEP_ALIVE      6    /* Keep alive enabled? */
#define SKT_INFO_FAMILY		 7    /* Socket address family */
#define SKT_INFO_FAMILY_IPV4     1    /* Socket address family IPV4 */
#define SKT_INFO_FAMILY_IPV6     2    /* Socket address family IPV6 */

/* OBJINFO() keys */
#define OI_ISOBJ      0  /* Is descriptor an object */
#define OI_CLASS      1  /* Class name */

/* FCONTROL() keys */
#define FC_SET_JNL_FNO           1    /* Set jnl_fno in file header */
#define FC_KILL_JNL              2    /* Disable journalling on open file */
#define FC_SET_AKPATH            3    /* Set akpath eleent of file header */
#define FC_NON_TXN               4    /* Set open file as non-transactional */
#define FC_SPLIT_MERGE           5    /* Force split/merge */
#define FC_NO_RESIZE             6    /* Set DHF_NO_RESIZE flag */

/* SD_ENCRYPT_SODIUM encryption decryption  */
#define SD_EncodeHX     201  /* encode passed string as Hex String */
#define SD_Encode64     202  /* encode as Base64 */

/* Key Codes for op_sdext     */
#define SDEXT_TestIt   1  /* Function Test */
#define SD_SALT      100  /* sd_encrypt_sodium sd_salt function */
#define SD_KEYFROMPW 101  /* sd_encrypt_sodium sd_KeyFromPW function */
#define SD_EUID_SET     102  /* set current process's euid egid to that of user */
#define SD_EUID_RESTORE 103  /* set current process's euid egid to what it was on entry to sd */

/* embedded python  */
/* py  object types */
#define  SD_Obj_Unkn         0  /* Unknown python object type */
#define  SD_Obj_Str          1  /* String (Unicode) python object type */
#define  SD_Obj_List         2  /* List python object type */
#define  SD_Obj_Dict         3  /* Dictionary  python object type */
#define  SD_Obj_Long         4  /* Long (int)  python object type */
#define  SD_Obj_Float        5  /* Float (floating point)  python object type */


#define  SD_PyInit        2000  /* initialize the python interpreter   */
#define  SD_PyFinal       2001  /* Finalize the python interpreter   */
#define  SD_IsPyInit      2002  /* Is python interpreter initialized   */
#define  SD_PyRunStr      2010  /* Take the string in qmBasic variable VAL and run in python interpreter   */
#define  SD_PyRunFile     2011  /* Take the file and path defined in qmBasic variable VAL and run in python interpreter   */
#define  SD_PyGetAtt      2100  /* Return the (string) value of python attribute defined in qmBasic variable VAL   */

#define  SD_PyDictCrte    2200  /* Creaete new dictionary for sd */
#define  SD_PyDictClr     2201  /* Clear  dictionary Keys and Values, (Name remains in global dictionary) for sd */
#define  SD_PyDictVset    2202  /* set dictionary key : value    */
#define  SD_PyDictVget    2203  /* get value of dictionary item key   */
#define  SD_PyDictIDel    2204  /* delete item (key / value) from dictionary */
#define  SD_PyDictKeys    2205  /* get dictionay keys as fld mrk  separated string */
#define  SD_PyDictValues  2206  /* get dictionay values as fld mrk separated string */

#define SD_PYStrSet       2210  /* create and or set string */
#define SD_PYStrGet       2211  /* Get string */

#define SD_PYDelObj       2215  /* Delete Python Object */
#define SD_PyObjLen       2216  /* get object length (return SD_INT_OVERFLW  err overflow > 32bits)*/
#define SD_PyObjType      2217  /* get object type*/

//#define SD_PyListCrte     2220  /* create list object */
#define SD_PyListGet      2221  /* get list items as fld mrk separated string */
#define SD_PyListAppd     2222  /* append object to list     */
#define SD_PyListClr      2223  /* clear list object   */
/* END-CODE */
