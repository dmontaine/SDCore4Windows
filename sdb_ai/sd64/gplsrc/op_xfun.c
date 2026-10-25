/* OP_XFUN.C
 * XFUN opcode: a family of small BASIC functions behind one opcode
 * Copyright (c) 2026 SD Core for Linux
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
 * 20 Oct 26 Windows port - from Linux 845d3b1 (18 Oct 26): XF_SDSALT, XF_SDKEY, XF_SDRANDKEY: encryption layer 2, for any program
 *               (sd_encrypt_sodium.c).  The first XFUN functions that take no arguments (bcomp's in.xfun skips get.args for a row that
 *               writes none).
 * 18 Oct 26 Windows port - from Linux 7aba47d (16 Oct 26): XF_GET, the GET statement (QM4 Fixes item 583); XF_OSPATH 31 (OSPATH for
 *               any program, behind the S.63 gate) and XF_FCONTROL 29 (400500c) are NOT carried.
 * 18 Oct 26 Windows port - from Linux 3b43525 (15 Oct 26): XF_DIGEST for QM4 gaps bundle Q-13 (DIGEST()).
 * 18 Oct 26 Windows port - from Linux c608b9f (15 Oct 26): Written for QM4 gaps bundle Q-1: CEIL FLOOR ROUNDUP ROUNDDOWN IS.* LEFT RIGHT LAST NV NS TRIMWS MATCHESS
 * 15 Oct 26 Windows port - from Linux 400500c - XF_FCONTROL: the public FCONTROL() (pub_fcontrol(), dh_misc.c).
 * 15 Oct 26 Windows port - from Linux 400500c - XF_DIGEST for QM4 gaps bundle Q-13 (DIGEST()).
 * 15 Oct 26 Windows port - from Linux 400500c - Written for QM4 gaps bundle Q-1: CEIL FLOOR ROUNDUP ROUNDDOWN IS.* LEFT RIGHT LAST NV NS TRIMWS MATCHESS
 *               MATCHFIELDS.  One opcode (0xBB, a single byte, so that the multivalue wrappers MVDS, MVDSS and MVDSSS can
 *               take it as their base) with the function number pushed last, as OP_EPOCHCV does.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Stack on entry:  argument(s) ... , function number (top).  The compiler (bcomp, in.xfun) pushes the number as a
 * constant after the arguments, so the function's own arguments are in the order the program wrote them.  The numbers are
 * the XF_ constants below and the table xfun.info in bcomp; test-xfun-units.py keeps the two in step.
 *
 *    XF_CEIL        CEIL(value)               array aware, through k_num_array1()
 *    XF_FLOOR       FLOOR(value)              array aware
 *    XF_ROUNDUP     ROUNDUP(value, step)      away from zero in steps of step; a step under one gives zero
 *    XF_ROUNDDOWN   ROUNDDOWN(value, step)    towards zero in steps of step
 *    XF_IS_ALNUM .. XF_IS_SPACE               first character of the argument; a null string is false
 *    XF_LEFT        LEFT(string, n)           same as string[1, n], n under 1 taken as 1
 *    XF_RIGHT       RIGHT(string, n)          same as string[n], n under 0 taken as 0
 *    XF_LAST        LAST(string, delim)       final delimited element; LASTS is this under the MVDSS wrapper
 *    XF_NV          NV(string, repeat)        value position numbers in place of the values
 *    XF_NS          NS(string)                subvalue position numbers in place of the subvalues
 *    XF_TRIMW       TRIMWS(array)             TRIMW under the MVDS wrapper
 *    XF_MATCHES     MATCHESS(array, template) MATCHES under the MVDSS wrapper
 *    XF_MATCHFIELD  MATCHFIELDS(array, template, component)   MATCHFIELD under the MVDSSS wrapper
 *    XF_CASING      CASING ON / OFF / expr    the CASING statement (SYSTEM(1086) reads the state back)
 *    XF_SIGNAL      SIGNAL(user.no)           raise the application signal in a process; SYSTEM(1062) reads and clears it
 *    XF_DIGEST      DIGEST(string, is.file, mode)   MD5 SHA1 SHA256 SHA384 SHA512 of a string or of an OS file, as hex
 *    XF_SELSOCKET   SELECT.SOCKET(skt.array, timeout)  wait for events on the sockets of a matrix; R, W and E letters per element
 *    XF_SDSALT      SDSALT()                  a fresh random salt: base64 for 16 bytes (24 characters)
 *    XF_SDKEY       SDKEY(passphrase, salt)   a 44 character base64 key by argon2id (2 passes, 64 MiB; fixed, they are part of the
 *                   key's format).  A null string with STATUS() 10206 for a bad salt, 10207 for an empty or over-long passphrase
 *    XF_SDRANDKEY   SDRANDKEY()               a random 256 bit key, 44 base64 characters
 *    XF_FCONTROL    FCONTROL(fvar, action {, qualifier})  the openQM function: 2 and 3 the CREATING.SEQKEY counter, 5 field access
 *                   (always true), 6 a valid record id, 7 the minimum modulus; 1 and 4 (forced writes, line terminators) abort
 *                   with a message, SD having neither
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <math.h>
#include <poll.h>
#include <time.h>
#include <unistd.h>
#include <openssl/evp.h>   /* before sd.h: descr.h defines OBJ, which turns OpenSSL's OBJ_dup into 15_dup */
#include "sd.h"
#include "header.h"
#include "keys.h"

/* The function numbers.  Keep in step with xfun.info in sdsys/gpl.bp/bcomp (test-xfun-units.py checks it). */
#define XF_CEIL 1
#define XF_FLOOR 2
#define XF_ROUNDUP 3
#define XF_ROUNDDOWN 4
#define XF_IS_ALNUM 5
#define XF_IS_ALPHA 6
#define XF_IS_DIGIT 7
#define XF_IS_GRAPH 8
#define XF_IS_MARK 9
#define XF_IS_SPACE 10
#define XF_LEFT 11
#define XF_RIGHT 12
#define XF_LAST 13
#define XF_NV 14
#define XF_NS 15
#define XF_TRIMW 16
#define XF_MATCHES 17
#define XF_MATCHFIELD 18
#define XF_CASING 19 /* the CASING statement, not a function: it takes a Boolean and leaves nothing (bcomp st.casing) */
#define XF_ARGPRESENT 20 /* ARG.PRESENT(name): the compiler loads the argument's variable number, which has its own handler (in.arg.present) */
#define XF_BOOL 21
#define XF_ISNULL 22
#define XF_NUMERIC 23
#define XF_REUSING 24 /* REUSING(name): the compiler loads the variable itself, which has its own handler (in.reusing) */
#define XF_SIGNAL 25  /* SIGNAL(user.no), QM4 gaps Q-5 */
#define XF_DIGEST 26  /* DIGEST(string, is.file, mode), QM4 gaps Q-13 */
#define XF_SELSOCKET 27 /* SELECT.SOCKET(socket matrix, timeout): the compiler loads the matrix itself (in.select.socket), QM4 gaps Q-5 */
#define XF_SWAPMARKS 28 /* SWAPMARKS(string): the string as it is - SD has no ECS mode, where the marks would be exchanged; sheet 238 */
#define XF_FCONTROL 29  /* FCONTROL(fvar, action, qualifier): the public one, openQM's numbers; pub_fcontrol() in dh_misc.c */
/* 31 is Linux's XF_OSPATH (OSPATH for any program, behind the S.63 OS-access gate): not carried, and the number stays free. */
#define XF_GET 30      /* GET var {, length} {SETTING count} FROM dev {UNTIL term} {RETURNING last} {WAITING timeout}: op_get_device() in op_seqio.c (QM4 Fixes item 583) */
#define XF_SORT 32      /* SORT(key.count, {MAT} flags) (QM4 Fixes item 371) */
#define XF_SORTADD 33   /* SORTADD sortvar, {MAT} keys {, data} (QM4 Fixes item 371) */
#define XF_SORTCLEAR 34 /* SORTCLEAR sortvar (QM4 Fixes item 371) */
#define XF_SORTDATA 35  /* SORTDATA(sortvar {, max.items}) (QM4 Fixes item 371) */
#define XF_SORTNEXT 36  /* SORTNEXT(sortvar {, {MAT} keys}) (QM4 Fixes item 371) */
#define XF_SDSALT 37    /* SDSALT(): a fresh random salt (sd_xf_salt in sd_encrypt_sodium.c; encryption layer 2) */
#define XF_SDKEY 38     /* SDKEY(passphrase, salt): a key by argon2id (sd_xf_key) */
#define XF_SDRANDKEY 39 /* SDRANDKEY(): a random 256 bit key (sd_xf_randkey) */
#define XF_FORMCSVX 40  /* FORMCSV(item, delim, quote, esc): the statement's own CSV characters (x_formcsvx, op_csv.c); the compiler loads the four */
#define XF_CSVDQX 41    /* CSVDQ(line, delim, quote, esc) (x_csvdqx) */
#define XF_CSVQESC 42   /* CSV.MODE's third and fourth operands (x_csvqesc): leaves nothing */
#define XF_CSVPARSE 43  /* CSVPARSE(text {, mode {, dialect}}): CSV text as a data collection or a dynamic array (x_csvparse) */
#define XF_CSVBUILD 44  /* CSVBUILD(c {, mode {, dialect}}): a data collection or dynamic array as CSV text (x_csvbuild) */
#define XF_CSVOPEN 45   /* CSVOPEN(line {, delim {, quote {, esc}}}): does the line end inside a quoted field (x_csvopen) */
#define XF_JMERGE 46    /* JMERGE(target, patch): RFC 7396 (x_jmerge, op_json.c) */
#define XF_JPATCH 47    /* JPATCH(c, ops): RFC 6902 (x_jpatch) */
#define XF_JPATH 48     /* JPATH(c, query): JSONPath (x_jpath) */
#define XF_JVALIDATE 49 /* JVALIDATE(c, schema): JSON Schema (x_jvalidate) */
#define XF_XPARSE 50    /* XPARSE(text {, mode}): XML text as a data collection (x_xparse, op_xml.c) */
#define XF_XBUILD 51    /* XBUILD(element {, mode {, indent}}): an XML element as text (x_xbuild) */
#define XF_XPATH 52     /* XPATH(x, query): XPath 1.0 over an element (x_xpath) */

void x_xparse(void);
void x_xbuild(void);
void x_xpath(void);

void x_jmerge(void);
void x_jpatch(void);
void x_jpath(void);
void x_jvalidate(void);
void x_csvopen(void);
void x_formcsvx(void);
void x_csvdqx(void);
void x_csvqesc(void);
void x_csvparse(void);
void x_csvbuild(void);
void sd_xf_salt(void);
void sd_xf_key(void);
void sd_xf_randkey(void);
void op_get_device(void);
void x_sort(void);
void x_sortadd(void);
void x_sortclear(void);
void x_sortdata(void);
void x_sortnext(void);
void pub_fcontrol(void);

void op_dcount(void);
void op_field(void);
void op_matches(void);
void op_matchfld(void);
void op_substr(void);
void op_substre(void);
void op_trimw(void);

Private void x_ceil(void);
Private void x_floor(void);
Private void x_round(bool up);
Private void x_is(int fn);
Private void x_bool(void);
Private void x_isnull(void);
Private void x_left(void);
Private void x_right(void);
Private void x_last(void);
Private void x_nv(bool ns);
Private int32_t x_signal(int32_t uid);
Private void x_digest(void);
Private void x_select_socket(void);
Private void push_int(int32_t n);

/* ======================================================================
   op_xfun()  -  XFUN opcode                                              */

void op_xfun() {
  DESCRIPTOR* descr;
  int32_t fn;
  int32_t n;

  descr = e_stack - 1;
  GetInt(descr);
  fn = descr->data.value;
  k_pop(1);

  switch (fn) {
    case XF_CEIL:
      x_ceil();
      break;
    case XF_FLOOR:
      x_floor();
      break;
    case XF_ROUNDUP:
      x_round(TRUE);
      break;
    case XF_ROUNDDOWN:
      x_round(FALSE);
      break;
    case XF_IS_ALNUM:
    case XF_IS_ALPHA:
    case XF_IS_DIGIT:
    case XF_IS_GRAPH:
    case XF_IS_MARK:
    case XF_IS_SPACE:
      x_is(fn);
      break;
    case XF_LEFT:
      x_left();
      break;
    case XF_RIGHT:
      x_right();
      break;
    case XF_LAST:
      x_last();
      break;
    case XF_NV:
      x_nv(FALSE);
      break;
    case XF_NS:
      x_nv(TRUE);
      break;
    case XF_TRIMW:
      op_trimw();
      break;
    case XF_MATCHES:
      op_matches();
      break;
    case XF_MATCHFIELD:
      op_matchfld();
      break;
    case XF_CASING:
      /* CASING ON / OFF / expr: string comparisons and searches of this program are case sensitive when true.  The flag is
         the program's own NOCASE bit, the same one $NOCASE.STRINGS sets for the whole program, so a program called from
         here keeps its own (SYSTEM(1086) reads it back) */
      descr = e_stack - 1;
      GetBool(descr);
      if (descr->data.value)
        process.program.flags &= ~HDR_NOCASE;
      else
        process.program.flags |= HDR_NOCASE;
      k_pop(1);
      break;
    case XF_ARGPRESENT:
      /* The argument's variable number is below the number of arguments the caller passed (ARG.COUNT() counts it without
         the hidden return value of a function, but the variable numbers of a function's arguments start above it, so the
         hidden one is counted on both sides). */
      descr = e_stack - 1;
      GetInt(descr);
      descr->data.value = (descr->data.value < (int32_t)process.program.arg_ct) ? 1 : 0;
      break;
    case XF_BOOL:
      x_bool();
      break;
    case XF_ISNULL:
      x_isnull();
      break;
    case XF_NUMERIC:
      /* The value in numeric form, as value + 0 gives it: an integer where it is one, otherwise a floating point number */
      descr = e_stack - 1;
      GetNum(descr);
      break;
    case XF_REUSING:
      /* The state of the REUSE flag on a variable, which this does not clear */
      descr = e_stack - 1;
      {
        DESCRIPTOR* v = descr;

        while (v->type == ADDR)
          v = v->data.d_addr;
        n = ((v->flags & DF_REUSE) != 0) ? 1 : 0;
      }
      InitDescr(descr, INTEGER);
      descr->data.value = n;
      break;
    case XF_SIGNAL:
      descr = e_stack - 1;
      GetInt(descr);
      n = x_signal(descr->data.value);
      InitDescr(descr, INTEGER);
      descr->data.value = n;
      break;
    case XF_DIGEST:
      x_digest();
      break;
    case XF_SELSOCKET:
      x_select_socket();
      break;
    case XF_SWAPMARKS:
      /* openQM's SWAPMARKS exchanges the mark characters with accented letters on an ECS system and, since release 3.0-2,
         returns the data unchanged on any other.  SD has no ECS mode, so the argument is the result */
      break;
    case XF_FCONTROL:
      pub_fcontrol();
      break;
    case XF_GET:
      op_get_device();
      break;
    case XF_SORT:
      x_sort();
      break;
    case XF_SORTADD:
      x_sortadd();
      break;
    case XF_SORTCLEAR:
      x_sortclear();
      break;
    case XF_SORTDATA:
      x_sortdata();
      break;
    case XF_SORTNEXT:
      x_sortnext();
      break;
    case XF_SDSALT:
      sd_xf_salt();
      break;
    case XF_SDKEY:
      sd_xf_key();
      break;
    case XF_SDRANDKEY:
      sd_xf_randkey();
      break;
    case XF_FORMCSVX:
      x_formcsvx();
      break;
    case XF_CSVDQX:
      x_csvdqx();
      break;
    case XF_CSVQESC:
      x_csvqesc();
      break;
    case XF_CSVPARSE:
      x_csvparse();
      break;
    case XF_CSVBUILD:
      x_csvbuild();
      break;
    case XF_CSVOPEN:
      x_csvopen();
      break;
    case XF_JMERGE:
      x_jmerge();
      break;
    case XF_JPATCH:
      x_jpatch();
      break;
    case XF_JPATH:
      x_jpath();
      break;
    case XF_JVALIDATE:
      x_jvalidate();
      break;
    case XF_XPARSE:
      x_xparse();
      break;
    case XF_XBUILD:
      x_xbuild();
      break;
    case XF_XPATH:
      x_xpath();
      break;
    default:
      k_error("Illegal XFUN function number %d", (int)fn); /* the compiler cannot have made this */
      break;
  }
}

/* ======================================================================
   x_signal()  -  SIGNAL(user.no)

   Raises the application signal in the process with that user number, which reads it with SYSTEM(1062).  Returns 1 if
   that process is logged in and was signalled, otherwise 0.  A process of another login user is not signalled, and
   the answer is 0, unless the caller is an administrator: any process may SIGNAL its own phantoms, but not interfere with
   somebody else's work (the same rule in effect as for the processes a user can see; WAKE has none, which is older).      */

Private int32_t x_signal(int32_t uid) {
  USER_ENTRY* uptr;

  if ((uid <= 0) || (uid > sysseg->hi_user_no))
    return 0;
  uptr = UserPtr(uid);
  if ((uptr == NULL) || (uptr->uid != uid))
    return 0;
  if (!(my_uptr->flags & USR_ADMIN) && (strcmp((char*)(uptr->username), (char*)(my_uptr->username)) != 0))
    return 0;
  __atomic_fetch_or(&uptr->flags, (int16_t)USR_SIGNAL, __ATOMIC_SEQ_CST);
  return 1;
}

/* ======================================================================
   x_digest()  -  DIGEST(string, is.file, mode)

   The message digest of a string, or of the file whose pathname the string is, as lower case hexadecimal characters
   (the same form as MD5()).  mode is MD5, SHA1, SHA256, SHA384 or SHA512, in either case.  STATUS() is 0 on success and
   the result is a null string, with STATUS() saying why, when:
     ER_ARGS     the mode is not one of those (MD4 is the openQM mode that is not here: broken, and not in OpenSSL 3's
                 default provider either)
     ER_PERM     the file is outside what the session may reach (the OPENSEQ rule: a network session is held to its
                 containment, a local one is limited by Windows; an $internal program is exempt, as it is for OPENSEQ)
     ER_FNF      there is no such file
     ER_FAILED   it is not a regular file, or could not be read                                                     */

/* 18 Oct 26 Windows port - Linux asks os_path_open_ok() here, the S.63 OS-access gate, which is held and not carried.  OPENSEQ
   on this port is contained only for a network session (net_path_permitted() in op_dio2.c; a local session is limited by
   Windows itself), so DIGEST of a file asks the same and nothing more.  An $internal program is exempt, as for OPENSEQ.  */

Private bool digest_path_ok(char* name) {
  char resolved[MAX_PATHNAME_LEN + 1];

  if (process.program.flags & HDR_INTERNAL)
    return TRUE;
  if (connection_type != CN_SOCKET)
    return TRUE;
  if (!fullpath(resolved, name))
    return FALSE;
  return net_path_permitted(resolved, FALSE);
}

Private void x_digest() {
  DESCRIPTOR* mode_d = e_stack - 1;
  DESCRIPTOR* file_d = e_stack - 2;
  DESCRIPTOR* str_d = e_stack - 3;
  char mode[24];
  char path[MAX_PATHNAME_LEN + 1];
  char hex[2 * EVP_MAX_MD_SIZE + 1];
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned char buff[65536];
  unsigned int digest_len = 0;
  unsigned int i;
  const EVP_MD* md = NULL;
  EVP_MD_CTX* ctx = NULL;
  STRING_CHUNK* chunk;
  bool is_file;
  bool ok = FALSE;
  int fd;
  ssize_t got;
  struct stat st;

  hex[0] = '\0';
  process.status = 0;

  if (k_get_c_string(mode_d, mode, (int)sizeof(mode) - 1) < 0)
    mode[0] = '\0';
  for (i = 0; mode[i] != '\0'; i++) {
    if ((mode[i] >= 'a') && (mode[i] <= 'z'))
      mode[i] = (char)(mode[i] - 'a' + 'A');
  }

  if (strcmp(mode, "MD5") == 0)
    md = EVP_md5();
  else if (strcmp(mode, "SHA1") == 0)
    md = EVP_sha1();
  else if (strcmp(mode, "SHA256") == 0)
    md = EVP_sha256();
  else if (strcmp(mode, "SHA384") == 0)
    md = EVP_sha384();
  else if (strcmp(mode, "SHA512") == 0)
    md = EVP_sha512();

  GetBool(file_d);
  is_file = (file_d->data.value != 0);

  if (md == NULL) {
    process.status = ER_ARGS;
  } else if ((ctx = EVP_MD_CTX_new()) == NULL || EVP_DigestInit_ex(ctx, md, NULL) != 1) {
    process.status = ER_FAILED;
  } else if (is_file) {
    if (k_get_c_string(str_d, path, MAX_PATHNAME_LEN) < 1) {
      process.status = ER_FNF;
    } else if (!digest_path_ok(path)) {
      process.status = ER_PERM;
    } else if ((fd = open(path, O_RDONLY | O_CLOEXEC)) < 0) {
      process.status = (errno == EACCES) ? ER_PERM : ((errno == ENOENT || errno == ENOTDIR) ? ER_FNF : ER_FAILED);
    } else {
      if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
        process.status = ER_FAILED;
      } else {
        ok = TRUE;
        while ((got = read(fd, buff, sizeof(buff))) != 0) {
          if (got < 0) {
            if (errno == EINTR)
              continue;
            ok = FALSE;
            process.status = ER_FAILED;
            break;
          }
          EVP_DigestUpdate(ctx, buff, (size_t)got);
        }
      }
      close(fd);
    }
  } else {
    k_get_string(str_d);
    for (chunk = str_d->data.str.saddr; chunk != NULL; chunk = chunk->next) {
      if (chunk->bytes > 0)
        EVP_DigestUpdate(ctx, chunk->data, (size_t)chunk->bytes);
    }
    ok = TRUE;
  }

  if (ok) {
    EVP_DigestFinal_ex(ctx, digest, &digest_len);
    for (i = 0; i < digest_len; i++)
      sprintf(hex + 2 * i, "%02x", digest[i]);
    hex[2 * digest_len] = '\0';
  }
  if (ctx != NULL)
    EVP_MD_CTX_free(ctx);

  k_pop(2);                         /* the mode and the Boolean */
  k_dismiss();                      /* the string */
  k_put_c_string(hex, e_stack);
  e_stack++;
}

/* ======================================================================
   x_select_socket()  -  SELECT.SOCKET(skt.array, timeout)

   poll()s the sockets in the elements of a dimensioned matrix for the events each was given with SET.SOCKET.MODE(skt,
   SKT$INFO.EVENTS, ...): SKT$READ.EVENT (data, or a connection waiting on a server socket, or the peer closing),
   SKT$WRITE.EVENT, SKT$EXCEPTION.EVENT.  An element that is not an open socket, or has no events set, is not watched.
   timeout is in milliseconds: 0 asks and returns, negative waits until something happens.

   The result is a field mark delimited array with a field for each element of the matrix: the letters R, W and E of the
   events found (only those asked for), null where there were none.  When nothing happens in the time the result is the
   null string and STATUS() is ER_TIMEOUT; any other failure is a null string with ER_FAILED.  What each socket found is
   also what SOCKET.INFO(skt, SKT$INFO.EVENTS) says until the next call.

   Only the TCP connection is watched: bytes a TLS session has already taken off it are not seen as "readable".      */

Private void x_select_socket() {
  DESCRIPTOR* mat_descr;
  DESCRIPTOR* to_descr;
  DESCRIPTOR* com_descr;
  DESCRIPTOR* d;
  ARRAY_HEADER* a_hdr = NULL;
  PMATRIX_HEADER* pm_hdr;
  int32_t num_elements;
  int32_t first;
  int32_t i;
  int32_t timeout;
  SOCKVAR* sv;
  struct pollfd* pfd = NULL;
  SOCKVAR** svs = NULL;
  int32_t npoll = 0;
  char* result = NULL;
  int32_t res_len = 0;
  int rc = 0;
  int ms;
  time_t deadline = 0;

  process.status = 0;

  to_descr = e_stack - 1;
  GetInt(to_descr);
  timeout = to_descr->data.value;

  mat_descr = e_stack - 2;
  while (mat_descr->type == ADDR)
    mat_descr = mat_descr->data.d_addr;

  switch (mat_descr->type) {
    case ARRAY:
      a_hdr = mat_descr->data.ahdr_addr;
      num_elements = ((a_hdr->cols == 0) ? 1 : a_hdr->cols) * a_hdr->rows;
      first = 1;
      break;
    case PMATRIX:
      pm_hdr = mat_descr->data.pmatrix;
      com_descr = pm_hdr->com_descr;
      num_elements = (pm_hdr->cols == 0) ? pm_hdr->rows : pm_hdr->cols * pm_hdr->rows;
      a_hdr = com_descr->data.ahdr_addr;
      first = pm_hdr->base_offset;
      break;
    default:
      k_error(sysmsg(1236)); /* Matrix required */
      return;
  }

  pfd = (struct pollfd*)malloc(sizeof(struct pollfd) * (size_t)(num_elements + 1));
  svs = (SOCKVAR**)malloc(sizeof(SOCKVAR*) * (size_t)(num_elements + 1));
  result = (char*)malloc((size_t)num_elements * 4 + 2);
  if ((pfd == NULL) || (svs == NULL) || (result == NULL)) {
    process.status = ER_FAILED;
    goto done;
  }

  for (i = 0; i < num_elements; i++) {
    d = Element(a_hdr, first + i);
    while (d->type == ADDR)
      d = d->data.d_addr;
    if ((d->type != SOCK) || (d->data.sock == NULL))
      continue;
    sv = d->data.sock;
    sv->found = 0;
    if (sv->events == 0)
      continue;
    pfd[npoll].fd = sv->socket_handle;
    pfd[npoll].events = 0;
    if (sv->events & SKT_READ_EVENT)
      pfd[npoll].events |= POLLIN;
    if (sv->events & SKT_WRITE_EVENT)
      pfd[npoll].events |= POLLOUT;
    if (sv->events & SKT_EXCEPTION_EVENT)
      pfd[npoll].events |= POLLPRI;
    pfd[npoll].revents = 0;
    svs[npoll] = sv;
    npoll++;
  }

  if (timeout > 0)
    deadline = time(NULL) + (time_t)((timeout + 999) / 1000) + 1;

  for (;;) {
    ms = timeout;
    if (timeout > 0) {
      time_t left = deadline - time(NULL);

      ms = (left > 0) ? (int)(left * 1000) : 0;
      if (ms > timeout)
        ms = timeout;
    }
    rc = poll(pfd, (nfds_t)npoll, ms);
    if ((rc < 0) && (errno == EINTR) && ((timeout < 0) || (time(NULL) < deadline)))
      continue;
    break;
  }

  if (rc < 0) {
    process.status = ER_FAILED;
  } else if (rc == 0) {
    process.status = ER_TIMEOUT;
  } else {
    for (i = 0; i < npoll; i++) {
      short r = pfd[i].revents;

      if ((svs[i]->events & SKT_READ_EVENT) && (r & (POLLIN | POLLHUP)))
        svs[i]->found |= SKT_READ_EVENT;
      if ((svs[i]->events & SKT_WRITE_EVENT) && (r & POLLOUT))
        svs[i]->found |= SKT_WRITE_EVENT;
      if ((svs[i]->events & SKT_EXCEPTION_EVENT) && (r & (POLLPRI | POLLERR | POLLNVAL)))
        svs[i]->found |= SKT_EXCEPTION_EVENT;
    }

    /* One field for each element of the matrix, in its order */
    for (i = 0; i < num_elements; i++) {
      d = Element(a_hdr, first + i);
      while (d->type == ADDR)
        d = d->data.d_addr;
      if (i > 0)
        result[res_len++] = FIELD_MARK;
      if ((d->type == SOCK) && (d->data.sock != NULL)) {
        sv = d->data.sock;
        if (sv->found & SKT_READ_EVENT)
          result[res_len++] = 'R';
        if (sv->found & SKT_WRITE_EVENT)
          result[res_len++] = 'W';
        if (sv->found & SKT_EXCEPTION_EVENT)
          result[res_len++] = 'E';
      }
    }
  }

done:
  if (result != NULL)
    result[res_len] = '\0';
  k_pop(1);    /* the timeout */
  k_dismiss(); /* the matrix reference */
  k_put_c_string((process.status == 0 && result != NULL) ? result : "", e_stack);
  e_stack++;
  free(pfd);
  free(svs);
  free(result);
}

/* ======================================================================
   push_int()  -  Push an integer result                                  */

Private void push_int(int32_t n) {
  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = n;
}

/* ======================================================================
   number_result()  -  Replace the top of the stack by a whole number held as an integer where it fits */

Private void number_result(DESCRIPTOR* descr, double r) {
  if (r > -2147483647.0 && r < 2147483647.0) {
    InitDescr(descr, INTEGER);
    descr->data.value = (int32_t)r;
  } else {
    InitDescr(descr, FLOATNUM);
    descr->data.float_value = r;
  }
}

/* ======================================================================
   x_ceil()  -  CEIL(): smallest integer not less than the value; an array gives an array */

Private void x_ceil() {
  DESCRIPTOR* descr;

  process.numeric_array_allowed = TRUE;
  descr = e_stack - 1;
  GetNum(descr);
  process.numeric_array_allowed = FALSE;

  switch (descr->type) {
    case INTEGER:
      break;
    case FLOATNUM:
      number_result(descr, ceil(descr->data.float_value));
      break;
    default:
      k_num_array1(x_ceil);
      break;
  }
}

/* ======================================================================
   x_floor()  -  FLOOR(): largest integer not greater than the value; an array gives an array */

Private void x_floor() {
  DESCRIPTOR* descr;

  process.numeric_array_allowed = TRUE;
  descr = e_stack - 1;
  GetNum(descr);
  process.numeric_array_allowed = FALSE;

  switch (descr->type) {
    case INTEGER:
      break;
    case FLOATNUM:
      number_result(descr, floor(descr->data.float_value));
      break;
    default:
      k_num_array1(x_floor);
      break;
  }
}

/* ======================================================================
   x_round()  -  ROUNDUP() and ROUNDDOWN(): the value in steps of an integer increment, away from zero or towards it.
   The manual's own forms are IDIV(value, step) * step and IDIV(value + step - 1, step) * step (minus for a negative
   value), IDIV truncating towards zero; a step under one gives zero.                                            */

Private void x_round(bool up) {
  DESCRIPTOR* v_descr;
  DESCRIPTOR* s_descr;
  double v;
  double step;
  double q;

  s_descr = e_stack - 1;
  GetNum(s_descr);
  step = (s_descr->type == INTEGER) ? (double)s_descr->data.value : s_descr->data.float_value;
  step = trunc(step);

  v_descr = e_stack - 2;
  GetNum(v_descr);
  v = (v_descr->type == INTEGER) ? (double)v_descr->data.value : v_descr->data.float_value;

  if (step < 1) {
    q = 0;
    step = 1;
  } else if (!up) {
    q = trunc(v / step);
  } else if (v >= 0) {
    q = trunc((v + step - 1) / step);
  } else {
    q = trunc((v - step + 1) / step);
  }

  k_pop(1);
  number_result(e_stack - 1, q * step);
}

/* ======================================================================
   x_is()  -  IS.ALNUM(), IS.ALPHA(), IS.DIGIT(), IS.GRAPH(), IS.MARK(), IS.SPACE(): the first character is tested, a
   null string is false.  The classes are the kernel's own character types, and the space is only the space character. */

Private void x_is(int fn) {
  DESCRIPTOR* descr;
  STRING_CHUNK* str;
  bool r = FALSE;
  char c;

  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  if (str != NULL && str->bytes > 0) {
    c = str->data[0];
    switch (fn) {
      case XF_IS_ALNUM:
        r = IsAlnum(c) != 0;
        break;
      case XF_IS_ALPHA:
        r = IsAlpha(c) != 0;
        break;
      case XF_IS_DIGIT:
        r = IsDigit(c) != 0;
        break;
      case XF_IS_GRAPH:
        r = IsGraph(c) != 0;
        break;
      case XF_IS_MARK:
        r = IsMark(c) != 0;
        break;
      case XF_IS_SPACE:
        r = (c == ' ');
        break;
    }
  }
  k_dismiss();
  push_int(r ? 1 : 0);
}

/* ======================================================================
   x_bool()  -  BOOL(value): false for a zero or a null string, true for everything else, as a Boolean (the same kind of
   value JBOOLEAN makes, so JBUILD() writes true or false and JTYPE() says boolean).  "0.0" and "-0" are zero.  Unlike
   JBOOLEAN() the text false is not false: it is a string that is not null.                                         */

Private void x_bool() {
  DESCRIPTOR* descr;
  DESCRIPTOR result;
  int n;

  descr = e_stack - 1;
  if (descr->type == ADDR)
    k_get_value(descr);
  switch (descr->type) {
    case INTEGER:
      n = (descr->data.value != 0);
      break;
    case FLOATNUM:
      n = (descr->data.float_value != 0.0);
      break;
    case STRING:
      if (descr->data.str.saddr == NULL) {
        n = 0;
      } else if (k_is_num(descr)) {
        k_get_num(descr);
        n = (descr->type == INTEGER) ? (descr->data.value != 0) : (descr->data.float_value != 0.0);
      } else {
        n = 1;
      }
      break;
    default:
      n = 1;
  }
  k_dismiss();
  InitDescr(&result, INTEGER);
  result.data.value = n;
  result.flags = DF_JSON;
  *(e_stack++) = result;
}

/* ======================================================================
   x_isnull()  -  IS.NULL(var): is it the SQL style null that JNULL() makes (the null string with the JSON flag)?  The
   ordinary null string, the empty string a program assigns, is not it.                                             */

Private void x_isnull() {
  DESCRIPTOR* descr;
  bool is_null;

  descr = e_stack - 1;
  if (descr->type == ADDR) {
    DESCRIPTOR* v = descr;

    while (v->type == ADDR)
      v = v->data.d_addr;
    is_null = (v->type == STRING) && (v->flags & DF_JSON) && (v->data.str.saddr == NULL);
  } else {
    is_null = (descr->type == STRING) && (descr->flags & DF_JSON) && (descr->data.str.saddr == NULL);
  }
  k_dismiss();
  push_int(is_null ? 1 : 0);
}

/* ======================================================================
   x_left()  -  LEFT(string, n): the same as string[1, n], with n under 1 taken as 1   */

Private void x_left() {
  DESCRIPTOR* n_descr;
  int32_t n;

  n_descr = e_stack - 1;
  GetInt(n_descr);
  n = n_descr->data.value;
  if (n < 1)
    n = 1;
  InitDescr(n_descr, INTEGER);
  n_descr->data.value = 1; /* the start */
  push_int(n);             /* the length: SUBSTR takes string, start, length */
  op_substr();
}

/* ======================================================================
   x_right()  -  RIGHT(string, n): the same as string[n], with n under 0 taken as 0   */

Private void x_right() {
  DESCRIPTOR* n_descr;

  n_descr = e_stack - 1;
  GetInt(n_descr);
  if (n_descr->data.value < 0)
    n_descr->data.value = 0;
  op_substre();
}

/* ======================================================================
   x_last()  -  LAST(string, delimiter): the final delimited element, as FIELD(string, delimiter, DCOUNT(string,
   delimiter)).  FIELD also sets COL1() and COL2() to the element's place in the string, as the manual says LAST does. */

Private void x_last() {
  DESCRIPTOR* src;
  DESCRIPTOR* delim;

  src = e_stack - 2;
  delim = e_stack - 1;

  /* stack: s d  ->  s d s d  (the copies share the strings) */
  *e_stack = *src;
  k_incr_refct(e_stack);
  e_stack++;
  *e_stack = *delim;
  k_incr_refct(e_stack);
  e_stack++;
  op_dcount(); /* s d count */

  push_int(1); /* s d count 1: FIELD(string, delimiter, occurrence, number of fields) */
  op_field();
}

/* ======================================================================
   x_nv()  -  NV(string, repeat) and NS(string)

   A dynamic array with the field, value and subvalue marks.  NV puts each value's position number in place of the
   value; with repeat true each subvalue is replaced by the position of the value it is in, with it false the
   subvalues are dropped and the value gives one number.  NS puts each subvalue's own position number in place of it.
   The marks stay where they were, so the result has the structure of the argument.
   Example from the manual:  111 VM 121 SM 122 SM 123 VM 131 SM 132 FM 211 SM 212 VM 221
      NV(s, 0) = 1 VM 2 VM 3 FM 1 VM 2           NV(s, 1) = 1 VM 2 SM 2 SM 2 VM 3 SM 3 FM 1 SM 1 VM 2
      NS(s)    = 1 VM 1 SM 2 SM 3 VM 1 SM 2 FM 1 SM 2 VM 1                                               */

Private void x_nv(bool ns) {
  DESCRIPTOR* descr;
  DESCRIPTOR result;
  STRING_CHUNK* str;
  char* p;
  int16_t left;
  bool repeat = FALSE;
  int32_t valno = 1;
  int32_t svno = 1;
  char c; /* plain char, as the marks are: FIELD_MARK and the others are defined as signed characters */
  char numbuf[16];

  if (!ns) {
    descr = e_stack - 1;
    GetInt(descr);
    repeat = (descr->data.value != 0);
    k_pop(1);
  }

  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;

  InitDescr(&result, STRING);
  result.data.str.saddr = NULL;
  if (str == NULL) { /* a null string stays null */
    *(e_stack - 1) = result;
    return;
  }

  ts_init(&result.data.str.saddr, str->string_len + 16);

  /* The number for the first item, then one more after every mark: the data between the marks is dropped.  The numbers
     are the value position, or (NS) the subvalue position, which both start again at 1 after the mark above them. */

  ts_copy_byte('1');
  for (; str != NULL; str = str->next) {
    p = str->data;
    for (left = str->bytes; left > 0; left--, p++) {
      c = *p;
      if (c == FIELD_MARK) {
        ts_copy_byte(c);
        valno = 1;
        svno = 1;
        ts_copy_byte('1');
      } else if (c == VALUE_MARK) {
        ts_copy_byte(c);
        valno++;
        svno = 1;
        snprintf(numbuf, sizeof(numbuf), "%d", (int)(ns ? 1 : valno));
        ts_copy(numbuf, (int)strlen(numbuf));
      } else if (c == SUBVALUE_MARK && (ns || repeat)) {
        ts_copy_byte(c);
        svno++;
        snprintf(numbuf, sizeof(numbuf), "%d", (int)(ns ? svno : valno));
        ts_copy(numbuf, (int)strlen(numbuf));
      }
    }
  }

  ts_terminate();
  k_dismiss();
  *(e_stack++) = result;
}

/* END-CODE */
