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
*       31-40  SD Core for Linux only
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

$define CA$OS.SH          21     ;* Windows only: os.users field 1
$define CA$OS.EXECUTE     22     ;* Windows only: os.users field 2

* READ BY BOTH PORTS (it sits in the Linux block because Linux added it first):
* 1 = an OS user that SD itself created may be taken over instead of refused.
* RESTORE.ACCOUNT sets it.  Linux: the user keeps its Linux password ($cred is
* separate and is not written).  Windows (owner's ruling, 2 Oct 2026): the
* user is reused WITH A NEW PASSWORD, which sets the Windows password and
* $cred together.
$define CA$REUSE.SD.USER  31

* END-CODE
