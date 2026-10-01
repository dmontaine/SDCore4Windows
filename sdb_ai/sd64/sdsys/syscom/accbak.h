* ACCBAK.H
* BACKUP.ACCOUNT / RESTORE.ACCOUNT / SETTINGS.REPORT shared definitions (S.50).
*
* START-HISTORY:
* 01 Oct 26 dm Written for S.50.  SHARED WITH SD CORE FOR WINDOWS BYTE FOR BYTE:
*              Linux writes this file and the Windows port copies it, as it
*              copies the verbs that include it.
* END-HISTORY
*
* START-DESCRIPTION:
*
*    THE ARCHIVE (agreed by mail, 2026-09-30T2359 to 2026-10-01T1210):
*       manifest.txt                 at the root
*       accounts/<name>/...          one tree per account, under its account name
*    A zip, deflate or stored, "/" separators, a "name/" entry for every
*    directory.  The manifest is plain ASCII with LF line endings: "key: value"
*    lines, then one "[account <name>]" section per account.  Unknown keys are
*    ignored by a reader, so a later version can add keys.
*
*    THE LOGIN HOLD: the record ACCBAK$HOLD in SDSYS's directory, read and
*    written as a directory-file record (so one field per line on disk):
*       <1> userno  <2> pid  <3> logname  <4> verb  <5> date  <6> time
*    !acc_hold writes it once every other session
*    has gone, LOGIN and the API server refuse a new session while its holder
*    is alive, and a holder that is gone (no user-table entry with that userno
*    AND pid) is ignored, so a session that died cannot lock everybody out.
*
* END-DESCRIPTION
*
* START-CODE

$define ACCBAK$FORMAT      1                ;* manifest "format:" value written
$define ACCBAK$MANIFEST    'manifest.txt'
$define ACCBAK$HOLD        'login.hold'     ;* in @sdsys
$define ACCBAK$STAGE       '.sdrestore.'    ;* <accounts.root>/.sdrestore.<@userno>

* !acc_hold modes
$define ACCBAK$CHECK       'CHECK'          ;* list every other session
$define ACCBAK$SET         'SET'            ;* CHECK, then write the hold
$define ACCBAK$CLEAR       'CLEAR'          ;* remove the hold if it is ours
$define ACCBAK$TEST        'TEST'           ;* LOGIN / API: is a live hold set?

* END-CODE
