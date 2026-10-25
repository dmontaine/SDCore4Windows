<?php
/* sdclient.php - SD client API (sdclilib) bindings for PHP 7.4 and later, with the FFI extension.
 *
 * 15 Oct 2026.  The library's own signatures are in gplsrc/sdclilib.h and win over this file; gplbld/test-clientheaders-units.py
 * holds the C declarations below against that header (and has a C compiler read the two together, so a type that differs is an
 * error), and checks the class constants.
 *
 * The extension must be on (extension=ffi in php.ini) and, for a web server's PHP, ffi.enable must be "true" in php.ini: the default
 * "preload" allows FFI only in command line scripts and preloaded code.  The library is sdclilib.so on Linux (the installed copy is
 * /usr/local/sdsys/bin/sdclilib.so) and sdclilib.dll, the C client library of the Windows kit, on Windows; a client of either kind
 * talks to a server of either kind.  A 64-bit PHP needs the 64-bit library.
 *
 * STRINGS ARE BYTES, and a PHP string is too, so there is no conversion to get wrong: SD's marks (0xFB to 0xFF) pass through
 * untouched.  A string result comes back from FFI as a char *, memory the library allocated: SDClient::str($p) copies it into a PHP
 * string and gives the memory back with SDFree; SDClient::strn($p, $n) does the same for $n bytes that may hold zeros (SDReadBlk,
 * with the Actual it returned).  Both return null for a null pointer.  The marks as constants: SDClient::FM, VM and SVM.
 *
 * An int * parameter is a pointer to an int you make with SDClient::intRef() and read with ->cdata:
 *     require 'sdclient.php';
 *     $sd = SDClient::load('/usr/local/sdsys/bin/sdclilib.so');
 *     if ($sd->SDConnect('server', 4247, 'user', 'password', 'account')) {
 *         $fno = $sd->SDOpen('CUSTOMERS');
 *         $err = SDClient::intRef();
 *         $rec = SDClient::str($sd->SDRead($fno, '1001', FFI::addr($err)));
 *         echo $rec, ' (status ', $err->cdata, ")\n";
 *         $sd->SDDisconnect();
 *     }
 * SDCall and SDCallx take their arguments after the argument count, as in C: $sd->SDCallx('MYSUB', 2, $a, $b).  Use SDCallx and
 * read the arguments back with SDGetArg.  SDCall writes the results back into the buffers you passed, with no check of their size,
 * and a PHP string is not a buffer to let it write into: if you must use SDCall, give it FFI::new('char[65536]') buffers.
 */

final class SDClient
{
    // Server status constants (sorted)
    const SV_ELSE = 2;
    const SV_ERROR = 3;
    const SV_LOCKED = 4;
    const SV_OK = 0;
    const SV_ON_ERROR = 1;
    const SV_PROMPT = 5;
    const SV_ECONTXT = 7;
    const SV_EMSG_PAIR = 6;

    // The marks, as one-byte strings
    const FM = "\xFE";
    const VM = "\xFD";
    const SVM = "\xFC";

    // The C declarations FFI reads: the library's header without SD_API and without the two package functions
    const CDEF = <<<'C'
void SDCall(char *subrname, int16_t argc, ...);
void SDCallx(char *subrname, int16_t argc, ...);
char *SDGetArg(int arg_number);
char *SDChange(char *src, char *old_string, char *new_string, int occurrences, int start);
int SDChecksum(char *data);
void SDClearSelect(int listno);
void SDClose(int fno);
int SDConnect(char *host, int port, char *username, char *password, char *account);
int SDConnectLocal(char *account);
int SDConnected(void);
int SDDcount(char *src, char *delim);
void SDDebug(int16_t mode);
char *SDDel(char *src, int fno, int vno, int svno);
void SDDelete(int fno, char *id);
void SDDeleteu(int fno, char *id);
void SDDisconnect(void);
void SDDisconnectAll(void);
void SDEndCommand(void);
char *SDError(void);
char *SDExecute(char *command, int *err);
char *SDExtract(char *src, int fno, int vno, int svno);
char *SDField(char *src, char *delim, int first, int occurrences);
void SDFree(void *p);
int SDGetSession(void);
char *SDIns(char *src, int fno, int vno, int svno, char *new_string);
int SDLocate(char *item, char *src, int fno, int vno, int svno, int *pos, char *order);
int SDLogto(char *account_name);
void SDMarkMapping(int16_t fno, int16_t state);
int SDMatch(char *str, char *pattern);
char *SDMatchfield(char *str, char *pattern, int component);
int SDOpen(char *filename);
char *SDRead(int fno, char *id, int *err);
char *SDReadl(int fno, char *id, int wait, int *err);
char *SDReadList(int listno);
char *SDReadNext(int16_t listno);
char *SDReadu(int fno, char *id, int wait, int *err);
void SDRecordlock(int fno, char *id, int update_lock, int wait);
int SDRecordlocked(int fno, char *id);
void SDRelease(int fno, char *id);
char *SDReplace(char *src, int fno, int vno, int svno, char *new_string);
char *SDRespond(char *response, int *err);
void SDSelect(int fno, int listno);
void SDSelectIndex(int16_t fno, char *index_name, char *index_value, int16_t listno);
char *SDSelectLeft(int16_t fno, char *index_name, int16_t listno);
char *SDSelectRight(int16_t fno, char *index_name, int16_t listno);
char *SDRevision(void);
char *SDGetVar(char *name);
char *SDSystem(int key);
char *SDIndices(int fno, char *index_name);
char *SDTrans(char *file_name, char *id, char *field_name, char *action);
void SDTxn(int mode);
char *SDEvaluate(int fno, char *name, char *data, char *id);
char *SDEvalConv(int fno, char *name, char *data, char *id);
char *SDIConv(char *data, char *code);
char *SDOConv(char *data, char *code);
char *SDIConvs(char *data, char *code);
char *SDOConvs(char *data, char *code);
int SDOpenSeq(char *filename, char *id, int modes);
char *SDReadSeq(int fno, int *err);
char *SDReadBlk(int fno, int bytes, int *actual);
void SDWriteSeq(int fno, char *rec);
void SDWriteBlk(int fno, char *rec, int bytes);
void SDSeek(int fno, int offset, int relto);
void SDWeofSeq(int fno);
char *SDWriteSeqKey(int fno, char *rec);
char *SDWriteuSeqKey(int fno, char *rec);
char *SDRTrans(char *file_name, char *id, char *field_name, char *action);
void SDSetLeft(int16_t fno, char *index_name);
void SDSetRight(int16_t fno, char *index_name);
int SDSetSession(int session);
int SDStatus(void);
void SDWrite(int fno, char *id, char *data);
void SDWriteu(int fno, char *id, char *data);
C;

    private static $ffi = null;

    /** Load the library (once) and return the FFI object whose methods are the library's functions. */
    public static function load($library = 'sdclilib.so')
    {
        if (self::$ffi === null) {
            self::$ffi = \FFI::cdef(self::CDEF, $library);
        }
        return self::$ffi;
    }

    /** A new int, for the functions that take an int * ( FFI::addr(...) of it ); read the value with ->cdata. */
    public static function intRef()
    {
        return \FFI::new('int');
    }

    /** A string result as a PHP string, and the library's memory given back with SDFree; null for a null pointer. */
    public static function str($p)
    {
        if ($p === null || \FFI::isNull($p)) {
            return null;
        }
        $s = \FFI::string($p);
        self::load()->SDFree($p);
        return $s;
    }

    /** The same for $n bytes that may hold zeros. */
    public static function strn($p, $n)
    {
        if ($p === null || \FFI::isNull($p)) {
            return null;
        }
        $s = \FFI::string($p, max(0, (int)$n));
        self::load()->SDFree($p);
        return $s;
    }
}
