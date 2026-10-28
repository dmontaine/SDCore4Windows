* CREATEACC.H
* Settings positions for !create_account (S.50).
*
* START-HISTORY:
* 01 Oct 26 dm Written for S.50, BACKUP.ACCOUNT / RESTORE.ACCOUNT.  SHARED WITH
*              SD CORE FOR WINDOWS BYTE FOR BYTE (agreed by mail, 2026-10-01T0025):
*              Linux writes this file and the Windows port copies it.  Change it
*              here first, and mail the change.
* 02 Oct 26 dm CA$REUSE.SD.USER is read by both ports (Windows reuses with a
*              new password - owner's ruling that day); comment only.
* 25 Oct 26 Windows port - from Linux fc4030a (S.66): CA$SHARED.READ.OFF (37) and CA$SHARED.WRITE (38), the shared-account gates.
* 17 Oct 26 Windows port - from Linux 9d6f407 - S.65 slice 1: CA$NET (35), Linux only, the NET gate (as CA$VOC.EDIT etc. of S.64).
* 17 Oct 26 Windows port - from Linux 96d8be8 - S.65 slice 2c: CA$FILES (36), Linux only, membership of the group sdfiles.
* 18 Oct 26 Windows port - from Linux 3fbfc0d - S.66: CA$SHARED.READ.OFF (37) and CA$SHARED.WRITE (38), Linux only, the shared-account gates.  Windows ignores
*              the Linux block (31-40) and defines neither; the mail to the Windows agent is deferred (sequential order of 11 Oct).
* 18 Oct 26 Windows port - from Linux 3fbfc0d - S.65 write group: CA$FILESWRITE (39), Linux only, membership of the group sdfileswrite (needs CA$FILES).  Same block, same deferral.
* 28 Oct 26 Windows port - from Linux ec8459b - S.75, home: CA$START (42) and CA$PINS (43), where the new account starts and whether it may add programs of its own to its home screen.
*              Both ports read them (the Linux block ran past 40 on 23 Oct and is 31-50 there).
* END-HISTORY
*
* START-DESCRIPTION:
*
*    call !create_account(acc.type, acc.name, settings, err)
*
*    settings is a dynamic array with one setting per FIXED field position, so
*    either port can add a setting of its own without changing the signature.
*    A blank field takes the default.  A port ignores the other port's block.
*
*       1-8    shared
*       9-20   reserved for future shared settings
*       21-30  SD Core for Windows only
*       31-50  SD Core for Linux only (42 and 43 are read by this port too)
*
* END-DESCRIPTION
*
* START-CODE

$define CA$PATH            1     ;* OTHER: the account's pathname; blank = default parent
$define CA$DESC            2     ;* Description, written to ACCOUNTS field 2
$define CA$ROUTE.SSH       3     ;* 1 / 0; blank = on (the default for a USER account)
$define CA$ROUTE.API       4     ;* 1 / 0; blank = on
$define CA$MEMBERS         5     ;* GROUP: member user names, value-mark separated
$define CA$ATTACH          6     ;* 1 = attach an existing OS user (install only)
$define CA$NO.QUERY        7     ;* 1 = ask nothing (refused for a new USER: password)
$define CA$SUSPENDED       8     ;* 1 = create the account suspended

$define CA$OS.SH          21     ;* ACC$SH 'yes' (was os.users field 1 until 23 Oct 26)
$define CA$OS.EXECUTE     22     ;* ACC$OS.EXEC 'yes' (was os.users field 2 until 23 Oct 26)

* READ BY BOTH PORTS (it sits in the Linux block because Linux added it first):
* 1 = an OS user that SD itself created may be taken over instead of refused.
* RESTORE.ACCOUNT sets it.  Linux: the user keeps its Linux password ($cred is
* separate and is not written).  Windows (owner's ruling, 2 Oct 2026): the
* user is reused WITH A NEW PASSWORD, which sets the Windows password and
* $cred together.
$define CA$REUSE.SD.USER  31

* Linux only (17 Oct 26, S.64, the edit gates): 1 = the new account starts with the gate on.  A blank or a 0 is off.
$define CA$VOC.EDIT       32     ;* ACC$VOC.EDIT  'yes'
$define CA$BP.EDIT        33     ;* ACC$BP.EDIT   'yes'
$define CA$DICT.EDIT      34     ;* ACC$DICT.EDIT 'yes'

* Linux only (18 Oct 26, S.66, the shared account).  Both are requests only when exactly 1; anything else leaves the default.
* CA$SHARED.READ.OFF is INVERTED because the delivered default of shared.read is ON (a blank register field means yes).
$define CA$SHARED.READ.OFF 37    ;* 1 = the new account starts with ACC$SHARED.READ 'no' (withdrawn)
$define CA$SHARED.WRITE    38    ;* 1 = the new account starts with ACC$SHARED.WRITE 'yes'
* Linux only (17 Oct 26, S.65 slice 1, the NET gate for SDNet): 1 = the new account starts with the gate on.  A blank or a 0 is off.
* The gate takes effect for the remote-file slices that follow and does nothing yet.
$define CA$NET            35     ;* ACC$NET 'yes'
$define CA$FILES          36     ;* 1 = start in the group sdfiles, the SDNet files-only API route (Linux only; S.65 slice 2c)

* Linux only (18 Oct 26, S.65 write group): 1 = also join the Linux group sdfileswrite, so a files-only login can change files on this server.  Needs CA$FILES.
$define CA$FILESWRITE      39    ;* 1 = start in the group sdfileswrite (with CA$FILES; S.65 write group)

* Linux only (21 Oct 26, S.73 item 3): 1 = also join the Linux group sdfilesadmin, so a files-only login may administer files on this server.  Needs CA$FILES and CA$FILESWRITE.
$define CA$FILESADMIN      40    ;* 1 = start in the group sdfilesadmin (with CA$FILES and CA$FILESWRITE; S.73 item 3)

* READ BY BOTH PORTS (26 Oct 26, S.75, the home screen).  CA$START is a request only when it is exactly menu or terminal (lower case): the new account's ACC$START is that word; anything else
* is refused before anything is made.  Blank leaves the account following the system default (SET.START.DEFAULT).  CA$PINS is a request only when exactly 1 (off unless named): the
* new account's ACC$PINS is 'yes', the person may add programs of their own to their home screen (MY.MENU); blank or 0 leaves it off.
$define CA$START           42    ;* menu / terminal; blank = follow the system default
$define CA$PINS            43    ;* 1 = the new account starts with ACC$PINS 'yes'

* END-CODE
