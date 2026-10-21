      * KEYS.H
      * Keys for BASIC functions
      * Copyright (c) 2004, Ladybridge Systems, All Rights Reserved
      
      $list off
      * 27 Aug 26 Windows port - corrected the ACC$PRIOR.TIER note: the equality
      *                      guard, not an inner test, is what keeps field 6
      *                      write-once (PRE_RELEASE 21)
      * 27 Aug 26 Windows port - ACC$PRIOR.TIER, field 6, and SUSPENDED as a
      *                      fourth value of ACC$TIER.  See the ACCOUNTS block
      * 25 Aug 26 Windows port - removed FL$TYPE.VFS; FILEINFO never
      *                      returned it and VFS is gone from the C
      * rev 0.9-2 Mar 25 mab add sdpyobj
      * rev 0.9.0 Jan 25 mab with the change in ownership of group ACCOUNTS
      *                      add SYSTEM() keys
      *                      add SD_EUID_SET SD_EUID_RESTORE 
      * 09 Aug 24 mab add SDEXT embedded python key codes
      * 13 Aug 26 Windows port - and removed again with the interpreter
      * 12 Sep 26 Windows port - and restored at the same numbers for the
      *                      sdpy.exe helper, plus SD_PyListCrte 2220
      * 06 Aug 24 mab add SDEXT key codes
      * 30 Jul 24 mab define SD_ENCRYPT_SODIUM encode types 
      * 13 Aug 26 Windows port - define ACC$USERS, the LOGTO grant list
      * 20240330 mab add ACC$USERS
      * 30Mar09 gwb Added missing defines, SKT$STREAM, SKT$DGRAM, SKT$TCP,
      *             SKT$UDP, SKT$ICMP
      *
      * System limits
      $define MAX.ID.LEN            63
      
      * FILEINFO() function keys
      $define FL$OPEN           0  ;* Check if variable is an open file
      $define FL$VOCNAME        1  ;* Get VOC name by which file was opened
      $define FL$PATH           2  ;* Get pathname of file
      $define FL$TYPE           3  ;* Return file type
      $define FL$TYPE.SH        1  ;* SH file
      $define FL$TYPE.DH        3  ;* DH file
      $define FL$TYPE.DIR       4  ;* Directory file
      $define FL$TYPE.SEQ       5  ;* Sequential file
      $define FL$MODULUS        5  ;* Get file modulus
      $define FL$MINMOD         6  ;* Get mimimum modulus value for file
      $define FL$GRPSIZE        7  ;* Get group size
      $define FL$LARGEREC       8  ;* Get large record size
      $define FL$MERGE          9  ;* Get merge load percentage
      $define FL$SPLIT         10  ;* Get split load percentage
      $define FL$LOAD          11  ;* Get current load percentage
      $define FL$AK            13  ;* File has AK indices?
      $define FL$LINE          14  ;* Get number of next line to read or write
      $define FL$LOADBYTES   1000  ;* Get current load bytes
      $define FL$READONLY    1001  ;* Read only file?
      $define FL$TRIGGER     1002  ;* Get trigger function name
      $define FL$PHYSBYTES   1003  ;* File size, excluding indices
      $define FL$VERSION     1004  ;* File version
      $define FL$STATS.QUERY 1005  ;* File statistics enabled?
      $define FL$SEQPOS      1006  ;* File position for sequential file
      $define FL$TRG.MODES   1007  ;* Trigger modes
      $define FL$TRG.PRE.WRITE    1
      $define FL$TRG.PRE.DELETE   2
      $define FL$TRG.POST.WRITE   4
      $define FL$TRG.POST.DELETE  8
      $define FL$TRG.READ        16
      $define FL$TRG.PRE.CLEAR   32
      $define FL$TRG.POST.CLEAR  64
      $define FL$NOCASE      1008  ;* File uses case insensitive ids?
      $define FL$FILENO      1009  ;* Get internal file number
      $define FL$JNL.FNO     1010  ;* Get journalling file no, zero if none
      $define FL$AKPATH      1011  ;* Get AK subfile relocation pathname
      $define FL$ID          1012  ;* Id of last record read */
      $define FL$STATUS      1013  ;* STATUS dynamic array
      $define FL$MARK.MAPPING 1014 ;* Mark mapping enabled?
      $define FL$RECORD.COUNT 1015 ;* Record count (approximate)
      $define FL$PRI.BYTES   1016  ;* Physical size of primary subfile
      $define FL$OVF.BYTES   1017  ;* Physical size of overflow subfile
      $define FL$NO.RESIZE   1018  ;* Resizing inhibited?
      $define FL$UPDATE      1019  ;* File update counter
      $define FL$ENCRYPTED   1020  ;* File uses encryption
*     17 Oct 26 - 1021 is the openQM FL$WHO: the user numbers of the other sessions
*     that hold this file open, a field mark between them, null for none (the caller
*     is left out unless it has the file open through more than one file variable).
*     Until then 1021 was FL$HOLDERS, the Windows port's text form ("12 (don)", or
*     several separated by commas), which SD's own programs print in "cannot gain
*     exclusive access" messages; it is at 1100 now.  Empty when nothing else has the
*     file, which is a real answer and not a failure: the obstacle is this session's
*     own cached reference.
      $define FL$WHO         1021  ;* User numbers of the sessions holding this file open
      $define FL$HOLDERS     1100  ;* The same as text, "12 (don), 14 (ann)", for messages
*     12 Oct 26 - the openQM FILEINFO() keys above 1021, numbered as the openQM 4
*     manual numbers them; mirrored from gplsrc/keys.h, which says what each does
*     in SD.  FL$COLLECTION was 1022 until then (an unreleased guess).
      $define FL$NETFILE     1022  ;* QMNet file?
      $define FL$SEQTYPE     1023  ;* Sequential file sub-type
      $define FL$SEQTYPE.PORT  1
      $define FL$SEQTYPE.CHDEV 2
      $define FL$SEQTYPE.FIFO  3
      $define FL$SEQTYPE.DRIVE 4
      $define FL$REPLICATED  1024  ;* Replication targets
      $define FL$NOMAP       1025  ;* Directory file, id translation off?
      $define FL$ECS         1026  ;* Created in ECS mode?
      $define FL$ECS.MAP.NAME 1027 ;* ECS map name
      $define FL$ENCODING    1028  ;* Data encoding of a directory file
      $define FL$LAST.PART   1029  ;* Last part of a distributed file
      $define FL$INDEX.SCAN  1030  ;* Index scanning operations supported?
      $define FL$SEQ.KEY     1031  ;* Sequential record id
      $define FL$NON.TXN     1032  ;* Opened NON.TRANSACTIONAL?
      $define FL$SYNC        1033  ;* Opened with SYNC?
      $define FL$ID.CASING   1034  ;* "L" or "U" for forced id casing
      $define FL$COLLECTION  1035  ;* Data collection file?
      $define FL$OWNER       1036  ;* Owner of the file (Windows only)
      $define FL$TEMP        1037  ;* Temporary file?
      $define FL$TXN.UPDATE  1038  ;* Updated in the current transaction?
      $define FL$LOCKS       1039  ;* Locks the caller holds in this file
      $define FL$CONSTRAINTS 1040  ;* Data integrity constraints?
      
      * PRINTER.SETTING() function keys
      * This function is obsolete - Use GETPU() and SETPU()
      $define LPTR$WIDTH               1
      $define LPTR$LINES               2
      $define LPTR$TOP.MARGIN          3
      $define LPTR$BOTTOM.MARGIN       4
      $define LPTR$LEFT.MARGIN         5
      $define LPTR$DATA.LINES          6
      $define LPTR$HEADING.LINES       7
      $define LPTR$FOOTING.LINES       8
      $define LPTR$MODE                9
      $define LPTR$NAME               10
      $define LPTR$FLAGS              11
      * Also defined below as PU$...
      $define LPTR$FLG.PS         0x0002   ;* Emulated PostScript printer
      $define LPTR$FLG.NFMT       0x0004   ;* Suppress all formatting
      $define LPTR$FLG.NEXT       0x0008   ;* SETPTR NEXT options
      $define LPTR$FLG.RAW        0x0010   ;* Use raw mode APIs (Windows)
      $define LPTR$FLG.KEEP.OPEN  0x0020   ;* Do not close on PRINTER CLOSE
      $define LPTR$FLG.LAND       0x0040   ;* Landscape mode
      $define LPTR$LINE.NO            12
      $define LPTR$PAGE.NO            13
      $define LPTR$LINES.LEFT         14
      $define LPTR$COPIES             15
      $define LPTR$BANNER             16
      $define LPTR$HIGH.PRINT.UNIT   255     ;* Highest available print unit number
      
      * RECORDLOCKED() function return values
      $define LOCK$OTHER.FILELOCK  -3
      $define LOCK$OTHER.READU     -2
      $define LOCK$OTHER.READL     -1
      $define LOCK$NO.LOCK          0
      $define LOCK$MY.READL         1
      $define LOCK$MY.READU         2
      $define LOCK$MY.FILELOCK      3
      
      * SELECTINFO() function keys
      $define SL$ACTIVE       1  ;* Check if select list is active
      $define IK$SLACTIVE     1  ;* Check if select list is active
      $define SL$COUNT        3  ;* Fetch number of entries in select list
      $define IK$SLCOUNT      3  ;* Fetch number of entries in select list
      
      * @functions
      $define IT$CS          -1  ;* Clear screen
      $define IT$CAH         -2  ;* Cursor home
      $define IT$CLEOS       -3  ;* Clear to end of screen
      $define IT$CLEOL       -4  ;* Clear to end of line
      $define IT$SBLINK      -5  ;* Start flashing text
      $define IT$EBLINK      -6  ;* End flashing text
      $define IT$CUB         -9  ;* Backspace one char (or count given in arg 2)
      $define IT$CUU        -10  ;* Cursor up one line (or count given in arg 2)
      $define IT$SHALF      -11  ;* Start half brightness
      $define IT$EHALF      -12  ;* End half brightness
      $define IT$SREV       -13  ;* Start reverse video
      $define IT$EREV       -14  ;* End reverse video
      $define IT$SUL        -15  ;* Start underline
      $define IT$EUL        -16  ;* End underline
      $define IT$IL         -17  ;* Insert line (or as count in arg 2)
      $define IT$DL         -18  ;* Delete line (or as count in arg 2)
      $define IT$ICH        -19  ;* Insert character (or as count in arg 2)
      $define IT$DCH        -22  ;* Delete character (or as count in arg 2)
      $define IT$AUXON      -23  ;* Auxillary print mode on
      $define IT$AUXOFF     -24  ;* Auxillary print mode off
      $define IT$E80        -29  ;* Set 80 column mode
      $define IT$E132       -30  ;* Set 132 column mode
      $define IT$RIC        -31  ;* Reset inhibit cursor
      $define IT$SIC        -32  ;* Set inhibit cursor
      $define IT$CUD        -33  ;* Cursor down one line (or as count in arg 2)
      $define IT$CUF        -34  ;* Cursor right one column (or as count in arg 2)
      $define IT$FGC        -37  ;* Set foreground colour
      $define IT$FCOLOR     -37  ;* Set foreground colour
      $define IT$BGC        -38  ;* Set background colour
      $define IT$BCOLOR     -38  ;* Set background colour
      $define IT$SLT        -54  ;* Set line truncate
      $define IT$RLT        -55  ;* Reset line truncate
      $define IT$SBOLD      -58  ;* Start bold
      $define IT$EBOLD      -59  ;* End bold
      $define IT$ACMD       -108 ;* Asynchronous command prefix
      $define IT$SCMD       -109 ;* Synchronous command prefix
      $define IT$STYLUS     -250 ;* Enable/disable PDA stylus
      $define IT$KEYS       -251 ;* Enable/disable PDA keyboard display
      
      * Colours for IT$FGC and IT$BGC
      $define IT$BLACK                 0
      $define IT$BLUE                  1
      $define IT$GREEN                 2
      $define IT$CYAN                  3
      $define IT$RED                   4
      $define IT$MAGENTA               5
      $define IT$BROWN                 6
      $define IT$WHITE                 7
      $define IT$GREY                  8
      $define IT$BRIGHT.BLUE           9
      $define IT$BRIGHT.GREEN         10
      $define IT$BRIGHT.CYAN          11
      $define IT$BRIGHT.RED           12
      $define IT$BRIGHT.MAGENTA       13
      $define IT$YELLOW               14
      $define IT$BRIGHT.WHITE         15
      
      * GETPU(), SETPU, !GETPU() and !SETPU() mode keys
      $define PU$DEFINED               0
      $define PU$MODE                  1
      $define PU$WIDTH                 2
      $define PU$LENGTH                3
      $define PU$TOPMARGIN             4
      $define PU$BOTMARGIN             5
      $define PU$LEFTMARGIN            6
      $define PU$SPOOLFLAGS            7
      * Older flags are also defined above as LPTR$...
      $define PU$FLG.PS             0x00000002   ;* Emulated PostScript printer
      $define PU$FLG.NFMT           0x00000004   ;* Suppress all formatting
      $define PU$FLG.NEXT           0x00000008   ;* SETPTR NEXT options
      $define PU$FLG.RAW            0x00000010   ;* Use raw mode APIs (Windows)
      $define PU$FLG.KEEP.OPEN      0x00000020   ;* Do not close on PRINTER CLOSE
      $define PU$FLG.LAND           0x00000040   ;* Landscape mode
      $define PU$FLG.PCL            0x00002000   ;* PCL printer
      $define PU$FLG.DUPLEX.LONG    0x00004000   ;* Duplex, long edge binding
      $define PU$FLG.DUPLEX.SHORT   0x00008000   ;* Duplex, short edge binding
      $define PU$FLG.INFORM         0x00020000   ;* Say the output file's name at the start of a job (modes 3, 6)
      $define PU$FLG.EJECT          0x00040000   ;* End the job with a form feed
      $define PU$FLG.FF.ONLY        0x00080000   ;* FORM.FEED FF: a bare form feed between pages, not CR FF
      $define PU$FORM                  9
      $define PU$BANNER               10
      $define PU$LOCATION             11
      $define PU$COPIES               12
      $define PU$PAGENUMBER           15
      $define PU$LINESLEFT          1002
      $define PU$HEADERLINES        1003
      $define PU$FOOTERLINES        1004
      $define PU$DATALINES          1005
      $define PU$OPTIONS            1006
      $define PU$PREFIX             1007
      $define PU$SPOOLER            1008
      $define PU$OVERLAY            1009
      $define PU$CPI                1010
      $define PU$PAPER.SIZE         1011
      $define PU$LPI                1012
      $define PU$WEIGHT             1013
      $define PU$SYMBOL.SET         1014
      $define PU$STYLE              1015
      $define PU$NEWLINE            1016
      $define PU$PRINTER.NAME       1017
      $define PU$FILE.NAME          1018
      $define PU$SEQNO              1019
      $define PU$FORM.QUEUE         1020
      $define PU$FORM.FEED          1021
      $define PU$ENCODING           1022
      $define PU$FONT               1023
      $define PU$PATHNAME           1024
      $define PU$FONT.SIZE          1025
      $define PU$LINENO             2000
      
      * SETNLS key values
      
      $define NLS$CURRENCY             1
      $define NLS$THOUSANDS            2
      $define NLS$DECIMAL              3
      
      * GET.PORT.PARAMS(), SET.PORT.PARAMS() dynamic array fields
      $define PP$PORT                  1    ;* Port number
      $define PP$BAUD.RATE             2    ;* Baud rate
      $define PP$CHECK.PARITY          3    ;* 1 = enable, 0 = disable
      $define PP$PARITY.MODE           4    ;* 0=None, 1=Odd, 2=Even, 3=Mark, 4=Space */
      $define PP$BYTE.SIZE             5    :* Bits per byte
      $define PP$STOP.BITS             6    ;* 0=One, 1= One and a half, 2 = Two
      
      * Socket interface tokens
      $define SKT$BLOCKING             1    ;* Blocking mode
      $define SKT$NON.BLOCKING         2    ;* Non-blocking mode
      * Socket Types
      $define SKT$STREAM               0x00000000  
      $define SKT$DGRM                 0x00000100
      * Protocols
      $define SKT$TCP                  0x00000000
      $define SKT$UDP                  0x00010000
      $define SKT$ICMP                 0x00020000
      * 15 Sep 26 Windows port - S.19/RELEASE_1.1 41, mirrored from gplsrc/keys.h:
      *   OPEN.SOCKET as a TLS 1.3 client with no certificate check - for
      *   !sdclient, whose login binds to it.
      $define SKT$TLS                  0x01000000

      * SOCKET.INFO() and SET.SOCKET.MODE() keys
      $define SKT$INFO.OPEN            0    ;* Is this a socket variable?
      $define SKT$INFO.TYPE            1    ;* What sort of socket is this?
      $define SKT$INFO.TYPE.SERVER     1    ;* From CREATE.SERVER.SOCKET()
      $define SKT$INFO.TYPE.INCOMING   2    ;* From ACCEPT.SOCKET.CONNECTION()
      $define SKT$INFO.TYPE.OUTGOING   3    ;* From OPEN.SOCKET()
      $define SKT$INFO.PORT            2    ;* Port number
      $define SKT$INFO.IP.ADDR         3    ;* IP address
      $define SKT$INFO.BLOCKING        4    ;* Blocking mode?
      $define SKT$INFO.NO.DELAY        5    ;* Nagle algorithm disabled?
      $define SKT$INFO.KEEP.ALIVE      6    ;* Keep alive enabled?
      $define SKT$INFO.FAMILY          7    ;* Socket address family
      * 15 Sep 26 Windows port - S.19/RELEASE_1.1 41: SOCKET.INFO only.  The SCRAM
      *   c= value for a socket opened with SKT$TLS: base64("p=tls-exporter,," +
      *   binding); "" otherwise.
      $define SKT$INFO.TLS.CBIND       8    ;* SCRAM c= for this TLS session
      $define SKT$INFO.FAMILY.IPV4     1    ;* Socket address family IPV4
      $define SKT$INFO.FAMILY.IPV6     2    ;* Socket address family IPV6
      * 18 Oct 26 Windows port - from Linux cc03bed (15 Oct 26): - QM4 gaps Q-5, SELECT.SOCKET().  SKT$INFO.EVENTS is SD's own number; the events are openQM's.
      $define SKT$INFO.EVENTS          9    ;* SET.SOCKET.MODE: events to watch.  SOCKET.INFO: the letters last found
      $define SKT$READ.EVENT           1    ;* Data to read, a connection waiting on a server socket, or the peer closed
      $define SKT$WRITE.EVENT          2    ;* Data can be sent
      $define SKT$EXCEPTION.EVENT      4    ;* An exception condition
      
      * JPARSE() and JBUILD() modes (13 Oct 26, data collections), mirrored from gplsrc/keys.h
      $define JP$NULL                  1    ;* A JSON null is read as a null string
      $define JP$UNQUOTED.NAME         2    ;* Element names may be unquoted
      $define JB$INVALID               1    ;* A value JSON cannot hold is saved as null
      $define JB$NULL                  2    ;* A null string is saved as null
      $define JB$NUM                   4    ;* A string that is a number is saved as one
      $define JB$SQUOTE.NAME           8    ;* Names in single quotes
      $define JB$NOQUOTE.NAME          16   ;* Names with no quotes
      $define JB$SQUOTE.VALUE          32   ;* String values in single quotes
      $define JB$NOQUOTE.VALUE         64   ;* String values with no quotes
      $define JB$PRETTY                128  ;* SD's own: one element to a line, indented (used by CT)

      * OBJINFO() keys
      $define OI$ISOBJ                 0    ;* Is descriptor an object
      $define OI$CLASS                 1    ;* Class name
      
      * ACCOUNTS file
      * Id = account name (forced to uppercase)
      $define ACC$PATH         1     ;* Account pathname
      $define ACC$DESCR        2     ;* Account description
      * REV 0.9.0
      $define ACC$GROUP        3     ;* Windows group for this Account
      * 14 Aug 26 Windows port - ACC$GROUP IS LIVE AGAIN AND IS THE GRANT.
      *   The comment that stood here called it dead, which was true for one
      *   day.  LOGIN and CPROC both test it now: CREATE.ACCOUNT writes
      *   sdu_<name>, puts the account's own user in that Windows group, and
      *   membership of it is what permits entry.  Granting somebody a second
      *   account means adding them to its group - the operating system holds
      *   the grant, not this record.  See PROJECT_STATUS.md sections 5.6, 7
      *   step 5.
      *
      * 15 Aug 26 Windows port - ACC$USERS IS GONE, field 4 with it.  It was
      *   the 13 Aug grant list, dead from 14 Aug when the grant became group
      *   membership.  Removed in the order 7 step 5d gives: the USERS entry in
      *   ACCOUNTS.DIC^@'s default listing first, then the dictionary item,
      *   then this define - the other way round breaks LIST ACCOUNTS on the
      *   way past.  FIELD 4 IS NOT REUSED: records written between 13 and
      *   14 Aug still carry a grant list there, and an installed tree is never
      *   upgraded (section 6), so a new meaning for field 4 would read those
      *   as data of the new kind.  Start at field 5.
      $define ACC$SUSPENDED    5     ;* 'SUSPENDED' or '' - whether the
      *                              ;*   account is temporarily denied entry
      * 18 Sep 26 Windows port - RELEASE_1.1 64.  THE TIERS ARE GONE, AND FIELD 5
      *   IS THE SUSPENSION STATE RATHER THAN A FOURTH TIER.  It holds the word
      *   SUSPENDED while the account is denied entry and '' otherwise.
      *   MODIFY.ACCOUNT SUSPENDED / UNSUSPENDED are its only writers; LOGIN,
      *   CPROC and APISRVR are its readers.  Every account's VOC is the whole
      *   of NEWVOC whatever this field says, so a suspension changes nothing
      *   about the VOC.
      *
      *   FIELD 6 (ACC$PRIOR.TIER) IS DELETED WITH THE TIERS.  It existed only
      *   to remember the tier a suspension displaced so the VOC delta on the
      *   way back could be computed; there is no tier to displace and no VOC
      *   delta any more, so nothing writes or reads it.  FIELD 4 REMAINS
      *   POISONED, per the note above: records written between 13 and 14 Aug
      *   2026 still carry a grant list there.
      deffun parse.pathname.tokens(path) calling "!PATHTKN"
      
      * encrytption decryption  *

      $define SD_ENCODEHX     201  ;* encode passed string as Hex String 
      $define SD_ENCODE64     202  ;* encode as Base64 
      
      * Key Codes for op_sdext     *
      $define SDEXT_TestIt      1  ;* Function Test 
      $define SD_SALT         100  ; sd_encrypt_sodium sd_salt function 
      $define SD_KEYFROMPW    101  ;* sd_encrypt_sodium sd_KeyFromPW function  
      * 5 Sep 26 Windows port - SD_EUID_SET (102) and SD_EUID_RESTORE (103)
      *   were defined here.  Removed with sdext_eguid.c and the two GPL.BP
      *   wrappers: PRE_RELEASE_FIXES 168.  The numbers are left unreused so an
      *   old catalogued object calling one gets the unknown-key response.
      *   SYS$UNX_EUID (system(28)) below is a DIFFERENT thing and stays.

      * 19 Aug 26 Windows port - SCRAM-SHA-256 primitives for the API login
      *   exchange.  All of them take and return BASE64, because SDEXT carries
      *   NUL-terminated C strings and a raw 32-byte digest would contain a
      *   mark character about one time in nine.  docs/SCRAM_AUTH.md
      $define SD_SHA256       104  ;* sd_scram sha256, 1 arg
      $define SD_HMACSHA256   105  ;* sd_scram hmac-sha256: base64 key, TEXT msg
      $define SD_PBKDF2       106  ;* sd_scram pbkdf2, 4 args: pw, salt, iter, len
      $define SD_RANDBYTES    107  ;* sd_scram random bytes, 1 arg: count
      $define SD_XORBYTES     108  ;* sd_scram xor, 2 args, equal lengths
      $define SD_CTEQUAL      109  ;* sd_scram constant-time compare, 2 args
      * 15 Sep 26 Windows port - S.19/RELEASE_1.1 41, mirrored from gplsrc/keys.h:
      *   this API session's SCRAM c= value, base64("p=tls-exporter,," +
      *   binding), or "" with no TLS.  Same number as Linux (S.19).
      $define SD_TLS_CBIND    110  ;* sd_tlssrv channel binding, 0 args
      * 20 Oct 26 Windows port - from Linux 00a5888, mirrored from gplsrc/keys.h: encryption layer 3, the key ring of the XE conversion.
      *   Args: 'set', name, base64 key (answers the key id, 8 hex digits) / 'clear', name or * (answers how many) / 'list'.
      $define SD_KEYRING      120  ;* sd_keyring key ring: set, clear, list

      * 13 Aug 26 Windows port - embedded python keys removed with the
      *   interpreter.  See PROJECT_STATUS.md 5.15.
      * 12 Sep 26 Windows port - RESTORED, with the SAME NUMBERS, for the
      *   helper process of PROJECT_STATUS.md 5.27.  Python is no longer
      *   inside sd.exe: these keys now name a verb that sdpy.exe performs
      *   at the other end of a pipe.  The numbers are the contract every
      *   PY_* documents, so they are kept rather than reassigned.
      *   The comments are gplsrc/keys.h's current ones, which differ from
      *   the 13 Aug text in one place: 2205 separates with a field mark,
      *   not a tab.
      * embedded python
      * py  object types
      $define  SD_Obj_Unkn         0  ;* Unknown python object type
      $define  SD_Obj_Str          1  ;* String (Unicode) python object type
      $define  SD_Obj_List         2  ;* List python object type
      $define  SD_Obj_Dict         3  ;* Dictionary  python object type
      $define  SD_Obj_Long         4  ;* Long (int)  python object type
      $define  SD_Obj_Float        5  ;* Float (floating point)  python object type

      $define SD_PyInit        2000  ;* initialize the python interpreter
      $define SD_PyFinal       2001  ;* Finalize the python interpreter
      $define SD_IsPyInit      2002  ;* Is python interpreter initialized
      $define SD_PyRunStr      2010  ;* Take the string in VAL and run in python interpreter
      $define SD_PyRunFile     2011  ;* Take the file and path defined in VAL and run in python interpreter
      $define SD_PyGetAtt      2100  ;* Return the (string) value of python attribute defined in VAL

      $define SD_PyDictCrte    2200  ;* Creaete new dictionary for sd
      $define SD_PyDictClr     2201  ;* Clear  dictionary Keys and Values, (Name remains in global dictionary) for sd
      $define SD_PyDictVset    2202  ;* set dictionary key : value
      $define SD_PyDictVget    2203  ;* get value of dictionary item key
      $define SD_PyDictIDel    2204  ;* delete item (key / value) from dictionary
      $define SD_PyDictKeys    2205  ;* get dictionay keys as fld mrk  separated string
      $define SD_PyDictValues  2206  ;* get dictionay values as fld mrk separated string

      $define SD_PYStrSet      2210  ;* create and or set string
      $define SD_PYStrGet      2211  ;* Get string

      $define SD_PYDelObj      2215  ;* Delete Python Object
      $define SD_PyObjLen      2216  ;* get object length (return SD$INT.OVERFLW err overflow > 32bits)
      $define SD_PyObjType     2217  ;* get object type

      * 12 Sep 26 Windows port - 2220 IS NEW TO THIS FILE.  It was reserved
      *   and commented out in gplsrc/keys.h, which is why the removed API
      *   could append to a list, clear one and read one but could only
      *   CREATE one by running a script that said "x = []".  No PY_* uses
      *   it yet - the verb exists in sdpy.exe and nothing is obliged to
      *   call it.
      $define SD_PyListCrte    2220  ;* create list object
      $define SD_PyListGet     2221  ;* get list items as fld mrk separated string
      $define SD_PyListAppd    2222  ;* append object to list
      $define SD_PyListClr     2223  ;* clear list object

      * SYSTEM() keys for BASIC Function SYSTEM() as defined in gplsrc/op_sys.c
      $define SYS$PTR_ON        1  ;*   Printer on?
      $define SYS$PTR_WIDTH     2  ;*   Default print unit page width
      $define SYS$PTR_DEPTH     3  ;*   Default print unit page depth
      $define SYS$PTR_LNS_REM   4  ;*   Default print unit lines remaining on page
      $define SYS$PTR_PAGE_NBR  5  ;*   Default print unit page number
      $define SYS$PTR_LINE_NBR  6  ;*   Default print unit line number
      $define SYS$TERM_TYPE     7  ;*   @TERM.TYPE
      $define SYS$CPU_TIME      9  ;*   CPU time (mS)
      $define SYS$DAT_Q_ACTIVE 10  ;*   DATA queue active?
      $define SYS$SEl_0_ACTIVE 11  ;*   Select list 0 active?
      $define SYS$TIME         12  ;*   Time (same as TIME())
      $define SYS$USER_NBR     18  ;*   User number
      $define SYS$BREAK_ENABLE 23  ;*   Break key enabled?
      $define SYS$ECHO_ENABLE  24  ;*   Echo enabled?
      $define SYS$IS_PHANTOM   25  ;*   Phantom process?
      $define SYS$PROMPT_CHAR  26  ;*   Prompt character
      $define SYS$UNX_UID      27  ;*   UID   
      $define SYS$UNX_EUID     28  ;*   EUID  
      $define SYS$UNX_GID      29  ;*   GID   
      $define SYS$UNX_EGID     30  ;*   EGID  
      $define SYS$LIC_NBR      31  ;*   Licence number
      $define SYS$SDSYS_PATH   32  ;*   System directory pathname
      $define SYS$TEMP_PATH    38  ;*   Temporary directory pathname
      $define SYS$CLIENT_IP    42  ;*   Client IP address
      $define SYS$WIN_OS       91  ;*   Windows? (see also 1006)
      $define SYS$IS_CAPTURE  1000  ;*   CAPTURING in effect?
      $define SYS$IS_INV_CASE 1001  ;*   Case inversion on?
      $define SYS$CALL_STACK  1002  ;*   Call stack
      $define SYS$OPEN_FILES  1003  ;*   Return list of open files
      $define SYS$PEAK_FILES  1004  ;*   Peak number of open files
      $define SYS$INT_TIME    1005  ;*   Internal time equivalent to DATE()      $define SYS$ 86400 + TIME()
      $define SYS$WIN_NT_OS   1006  ;*   Windows NT style (NT, 2000, XP)?
      $define SYS$TRANS_NBR   1007  ;*   Transaction number, zero if none
      $define SYS$TRANS_LEVEL 1008  ;*   Transaction level, zero if none
      $define SYS$IS_BIG_END  1009  ;*   Returns 1 on big endian system, 0 on little endian system
      $define SYS$PLAT_NAME   1010  ;*   Platform name
      $define SYS$CONFIG_PATH 1011  ;*   sd.ini or sdconfig file pathname
      $define SYS$SD_VERSION  1012  ;*   SD version number
      $define SYS$USER_LIMIT  1013  ;*   User limit (excluding phantom pool)
      $define SYS$USER_LMT_PH 1014  ;*   User limit (including phantom pool)
      $define SYS$HOST_NAME   1015  ;*   Computer name
      $define SYS$USRS_AVAIL  1016  ;*   Number of available users
      $define SYS$IP_PORT     1017  ;*   Port number for tcp/ip connection
      $define SYS$DEV_LIC_LMT 1018  ;*   Device licensing ip address limit
      $define SYS$DEV_LIC_CNT 1019  ;*   Device licensing current ip address count
      $define SYS$TIME_MS     1020  ;*   Time of day in milliseconds
      $define SYS$CLLCT_MAP   1021  ;*   Get collation map name
      $define SYS$CLL_MAP_USR 1022  ;*   Get collation map (user format)
      $define SYS$CLL_MAP_SYS 1023  ;*   Get collation map (internal format)
      $define SYS$CUR_DIR     1024  ;*   Current directory on entry to SD
      $define SYS$ENVIR_VARS  1025  ;*   Environment variables
      $define SYS$CMD_LINE    1026  ;*   Command text from "sd xxx"
      $define SYS$TTY_NAME    1027  ;*   Port name for serial connection
      $define SYS$SYS_ID      1028  ;*   System id code for system specific licences
      $define SYS$SUB_DEPTH   1029  ;*   Internal subroutine depth
      $define SYS$LOGIN_TIME  1030  ;*   Login time as date      $define SYS$ 86400 + time
      $define SYS$OS_PID      1031  ;*   Operating system process id
      $define SYS$BRK_PT_FLG  1032  ;*   Test and clear break pending flag
      $define SYS$USERS         35  ;*   Current number of users
      $define SYS$CSV.MODE    1043  ;*   CSV.MODE setting, 1 - 3 (14 Oct 26)
      $define SYS$CSV.DELIM   1046  ;*   CSV delimiter (14 Oct 26)
      $define SYS$START_TIME  1045  ;*   Time SD was started, Unix epoch
      $define SYS$GUID        1047  ;*   Globally unique identifier
      $define SYS$SYS_TYPE    9010  ;*   Return "SD"
      $define SYS$MAX_STR     9011  ;*   Return MAX_STRING_SIZE - max string / record length
      $define SYS$EXCEPTION   9012  ;*   @EXCEPTION: name of the exception last thrown
      $define SYS$EXC_DATA    9013  ;*   @EXCEPTION.DATA
      $define SYS$EXC_ORIGIN  9014  ;*   @EXCEPTION.ORIGIN: program name, field mark, line
      $define SYS$EXC_STACK   9015  ;*   @EXCEPTION.STACK: call stack when SAVING.STACK
      $define SYS$SEQNO       9016  ;*   @SEQNO: number of the last SETPTR AS NEXT hold file
*     12 Oct 26 - the openQM 4 SYSTEM() keys added with FILEINFO keys 1022-1040 (the manual lists numbers and
*     meanings, not token names; these names follow the ones above).  Those that name a feature SD does not
*     have answer as openQM does without it.
      $define SYS$TIMESLICE   13    ;*   Relinquish timeslice: always 1
      $define SYS$CPROC_LEVEL 16    ;*   Command processor level (@LEVEL)
      $define SYS$USER_NO     22    ;*   User number (@USERNO), the same as 18
      $define SYS$CALLER      33    ;*   Name of the program that called this subroutine
      $define SYS$TZ_OFFSET   1019  ;*   Offset of the local time zone from UTC, in seconds
      $define SYS$COMO_ON     1033  ;*   COMO file active?
      $define SYS$COMO_SUSP   1034  ;*   COMO output suspended? (never in SD)
      $define SYS$EPOCH       1035  ;*   Seconds since 1 Jan 1970 UTC
      $define SYS$FILE_USERS  1037  ;*   Open files and the users that have them open
      $define SYS$LOGIN_EPOCH 1038  ;*   Login time as an epoch value
      $define SYS$NOCASE_OS   1040  ;*   OS file names case insensitive? (never on Linux)
      $define SYS$ECS         1044  ;*   ECS mode? (never in SD)
      $define SYS$USB         1051  ;*   USB installation? (never in SD)
      $define SYS$CHILD_COUNT 1052  ;*   Number of direct child phantoms
      $define SYS$MAX_USERNO  1053  ;*   Highest user number
      $define SYS$PACKAGES    1054  ;*   Active packages (none in SD)
      $define SYS$USER_COUNTS 1056  ;*   Users now: interactive, API, iPhantom, other phantom, and the peak (14 Oct 26)
      $define SYS$PARENT      1057  ;*   Parent process user number
      $define SYS$CHILDREN    1058  ;*   Direct child phantoms' user numbers
      $define SYS$GROUPED.CHILDREN 1073 ;* Those grouped with this process (PHANTOM GROUP): logged out when it ends
      $define SYS$TXN_CACHE   1065  ;*   The transaction cache
      $define SYS$FORM.QUEUE  1066  ;*   The last form queue SP.ASSIGN gave to a print unit, -1 if none (15 Oct 26)
      $define SYS$PRECISION   1070  ;*   The PRECISION setting
      $define SYS$OSREAD.INFO 1071  ;*   STATUS array of the file the last OSREAD read (15 Oct 26, _system)
      $define SYS$CALL_DEPTH  1076  ;*   Current CALL depth
      $define SYS$GROUP_NAMES 1077  ;*   Names of the user's groups
      $define SYS$GROUP_NBRS  1078  ;*   Numbers of the user's groups
      $define SYS$FROM_PROC   1080  ;*   Started from a Proc? (never in SD)
      $define SYS$EPOCH_MS    1081  ;*   Epoch time in milliseconds
      $define SYS$TIME_MS_LCL 1082  ;*   Time of day in milliseconds, local time
      $define SYS$DEADLOCK    1083  ;*   The last deadlock this process was in: a field for each process, user number, file, record id

*     12 Oct 26 - OSPATH() keys from the openQM 4 manual that do not clash with SD's own numbers (the rest of
*     SD's OS$ names are in the internal program header int$keys.h and keep the older numbering).
      $define OS$FULLPATHX    4     ;*   Full path name keeping the case: the same as OS$FULLPATH, which keeps it on Linux
      $define OS$INFO         20    ;*   Information in the form of the STATUS statement's array
*     (Linux 7aba47d also names OS$PARENT, OS$UID, OS$GID, OS$MODES, OS$IS.FILE and OS$IS.DIR here for OSPATH() in a program that is
*     not internal; that function is behind the S.63 gate, which is held, so those names are not carried.)

*     15 Oct 26 - SYSTEM() keys of the openQM 4 manual (QM4 gaps bundle Q-18), named here by what they return.
      $define SYS$TYPEAHEAD   14    ;*   Characters waiting to be read (a snapshot for piped input)
      $define SYS$UNIQUE.TIME 19    ;*   A unique value from the date and time: two five digit numbers, a letter on a repeat
      $define SYS$UNIQUE.DATE 21    ;*   A unique value from the date and a sequence number that starts again each day
      $define SYS$PROGRAM     45    ;*   The name of the running program: its pathname if it was run from a source file
      $define SYS$SEQUENCE    1048  ;*   A sequence number unique across all sessions until SD restarts
      $define SYS$HUSH        1049  ;*   Is HUSH in effect?
      $define SYS$SIGNAMMED   1062  ;*   Has SIGNAL() been raised for this process?  Reading it clears it
      $define SYS$MAXMINPOS   1088  ;*   Position (field, value, subvalue, value mark delimited) of the element MAXIMUM() or MINIMUM() returned
      $define SYS$GROUP.SIZE  1067  ;*   The default group size of a dynamic file, in bytes
      $define SYS$CASING      1086  ;*   Is case sensitivity of string comparisons on in this program?

*     15 Oct 26 - the sort rules of SORT.COMPARE(), MERGELIST() and SORT() (QM4 gaps bundles Q-1, Q-2 and Fixes item 371).
*     The SRT$ values are the openQM 4 manual's.  The ML$ values are SD's own: the manual names the tokens and says they are added to the SRT$ ones.
      $define SRT$LEFT        0     ;*   Left justified: character by character from the start
      $define SRT$RIGHT       1     ;*   Right justified: integers as numbers
      $define SRT$COMPOUND    2     ;*   Alternating numeric and text elements
      $define SRT$RIGHT.FLOAT 3     ;*   As SRT$RIGHT, any number as a number
      $define SRT$STRICT      4     ;*   As SRT$COMPOUND, but 28 and 028 differ
      $define SRT$DESCENDING  16    ;*   The result of a comparison is reversed
      $define SRT$UNIQUE      32    ;*   SORT(): duplicate key values are ignored
      $define SRT$NOCASE      64    ;*   Case is ignored
      $define SRT$DATA        128   ;*   SORT(): sort has an associated data element
      $define ML$INTER        8     ;*   MERGELIST: the items in both lists
      $define ML$UNION        16    ;*   MERGELIST: the items in either list, once each
      $define ML$DIFF         24    ;*   MERGELIST: the items in the first list and not the second
      $define ML$UNSORTED     32    ;*   MERGELIST: the lists are not in order, so put them in order first
* The FC$ tokens of the public FCONTROL() (Linux 400500c, held with the QMClient chain) and the OS$ tokens of OSPATH() for any
* program (behind the S.63 gate) are NOT here.

* 16 Oct 26 - VARTYPE() values
      $define VT$UNASSIGNED   0
      $define VT$INTEGER      2
      $define VT$FLOATNUM     3
      $define VT$SUBR         4
      $define VT$STRING       5
      $define VT$FILE.REF     6
      $define VT$ARRAY        7
      $define VT$COMMON       8
      $define VT$IMAGE        9
      $define VT$BTREE        10
      $define VT$SELLIST      11
      $define VT$PMATRIX      12
      $define VT$SOCK         13
      $define VT$LOCALVARS    14
      $define VT$OBJ          15
      $define VT$OBJCD        16
      $define VT$OBJCDX       17
      $define VT$PERSISTENT   18
      $define VT$COLLECTION   19
      $define VT$SORT         20

