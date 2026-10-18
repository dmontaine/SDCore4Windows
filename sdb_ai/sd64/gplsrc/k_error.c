/* K_ERROR.C
 * Kernel error handling
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
 * 18 Oct 26 Windows port - from Linux bafe928 (17 Oct 26): k_error(): an error with a row in sys_exc_table is thrown as a SYS.* exception when a TRY handler can
 *               catch it (QM4 Fixes 354); with none it aborts as before.
 * 29 Sep 26 RELEASE_1.1 114 - the "at line N of <program>" suffix is
 *           snprintf-bounded; it could write past s[] (from Solo's SOLO 12)
 * 31 Aug 26 Windows port - k_error() truncated every message at about 84
 *                      characters: the vsnprintf bound read MAX_ERROR_LINES +
 *                      MAX_EMSG_LEN where the buffer is sized on the PRODUCT.
 *                      Now sizeof(s) - n, which also accounts for the offset
 *                      prefix already written.  PRE_RELEASE_FIXES.md 87
 * 16 Aug 26 Windows port - audit_message() writes the audit trail.  Separate
 *                      from log_message() because errlog DISCARDS its oldest
 *                      half and an audit trail may not lose records
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * If the message text starts with ! the call is not fatal and returns.
 *
 * op_illegal()            Report "Illegal opcode"
 * k_dh_error()            Report "Needs dynamic file"
 * k_index_error()         Report "Array subscript out of range"
 * k_not_array_error()     Report "Expected array variable"
 * k_value_error()         Report "Value not found where expected"
 * k_non_numeric_error()   Report "Non-numeric where numeric required"
 * k_select_range_error()  Report "Select list number out of range"
 * k_unassigned()          Report "Unassigned variable"
 * k_err_pu()              Report "Invalid print unit"
 * k_data_type()           Report "Incorrect data type"
 * k_deadlock()            Report "Deadlock detected"
 * k_txn_error()           Report "File operation not allowed in transaction"
 * k_illegal_call_name()   Report "Illegal call name"
 * k_error()               Report error using supplied text and abort
 * log_message()           Add a message to the error log
 * audit_message()         Add a record to the audit trail
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "syscom.h"
#include "options.h"
#include "tio.h"
#include "sdtermlb.h"
/* 16 Aug 26 Windows port - the audit trail's append.  Declares no Windows
   type, so it is safe to include here; win32audit.h says why it has to be a
   separate translation unit.                                              */
#include "win32audit.h"

#include <setjmp.h>
#include <stdarg.h>
#include <time.h>

extern jmp_buf k_exit;
extern char* month_names[];

extern bool in_sh; /* 0562 Doing SH command? */

Private int32_t line_table_offset;
Private int32_t line_table_bytes;
void null_function(void);

Private void k_descr_error(int16_t err, DESCRIPTOR* descr);

/* ======================================================================
   SYS.* EXCEPTIONS  (17 Oct 26, QM4 Fixes 354)

   A fatal error whose message is in this table is thrown as the named
   exception when a TRY handler for it (or for SYS$ANY or SYS$UNHANDLED) can
   be reached; with none the error aborts as it always did, and the message
   is the same either way. The names are those of the openQM manual's list of
   system generated exceptions ("SYS." and the hierarchy); a message with no
   row here is still a plain abort.

   ONLY WHERE THE OPCODE HOLDS NOTHING THAT AN ABANDONED OPCODE WOULD LEAVE
   BEHIND.  The thrown exception gives up the opcode where the error was
   raised, without the abort's clearing of locks, select lists and the
   transaction. These rows are all errors found at the head of an opcode
   (operand type, range, argument count) or on its return from the file
   system, none of them while a file lock, a DH group lock or the transaction
   commit is held. The two commit failures (1422, 1423) and the S.63 gate
   refusals (10054, 12185) have no row, on purpose.

   The row is found by message number, which k_error() learns from
   sysmsg_number_of() (the text it was given is the message buffer's) or, for
   the descriptor errors, from k_descr_error(). A new row is one line here and
   a message that exists; test-sysexc-units.py checks both.                 */

typedef struct {
  int16_t msg;
  const char* name;
} SYS_EXC;

#define SE_KERNEL "SYS.KERNEL."
#define SE_LOCKS "SYS.LOCKS."
#define SE_PRINTER "SYS.PRINTER."
#define SE_SELECT "SYS.SELECT."
#define SE_SORT "SYS.SORT."
#define SE_FILESYS "SYS.FILESYS."
#define SE_PROGRAM "SYS.PROGRAM."
#define SE_DATATYPE "SYS.PROGRAM.DATATYPE."

Private const SYS_EXC sys_exc_table[] = {
    {1002, SE_PROGRAM "NOT_FOUND"},
    {1003, SE_KERNEL "NO_MEMORY"},
    {1004, SE_KERNEL "NO_MEMORY"},
    {1005, SE_PROGRAM "INVALID_ARGCT"},
    {1006, SE_KERNEL "NO_MEMORY"},
    {1008, SE_KERNEL "NO_MEMORY"},
    {1009, SE_KERNEL "NO_MEMORY"},
    {1026, SE_PROGRAM "INVALID_ARGCT"},
    {1100, SE_PROGRAM "INVALID_MATRIX_INDEX"},
    {1101, SE_FILESYS "INVALID_FILE_TYPE"},
    {1102, SE_DATATYPE "NOT_MATRIX"},
    {1104, SE_DATATYPE "NOT_NUMERIC"},
    {1105, SE_DATATYPE "UNASSIGNED"},
    {1106, SE_FILESYS "INVALID_RECORD_ID"},
    {1107, SE_FILESYS "INVALID_RECORD_ID"},
    {1108, SE_PROGRAM "DIV_ZERO"},
    {1113, SE_DATATYPE "INVALID"},
    {1114, SE_LOCKS "DEADLOCK"},
    {1115, SE_PRINTER "INVALID_UNIT"},
    {1116, SE_LOCKS "TASK_LOCK.INVALID"},
    {1117, SE_PROGRAM "INVALID_DATA_SIZE"},
    {1118, SE_SELECT "INVALID_LIST_NO"},
    {1119, SE_PROGRAM "INVALID_IN_TXN"},
    {1123, SE_PROGRAM "NOT_FOUND"},
    {1124, SE_PROGRAM "NOT_FOUND"},
    {1125, SE_PROGRAM "NOT_FOUND"},
    {1126, SE_PROGRAM "LOAD_ERROR.READ_ERROR"},
    {1127, SE_PROGRAM "LOAD_ERROR"},
    {1128, SE_PROGRAM "LOAD_ERROR.READ_ERROR"},
    {1129, SE_PROGRAM "INVALID_CALL_NAME"},
    {1130, SE_PROGRAM "INVALID_CALL_NAME"},
    {1131, SE_PROGRAM "INVALID_ARGCT"},
    {1132, SE_PROGRAM "INVALID_MATRIX_SIZE"},
    {1133, SE_PROGRAM "LIMIT.GOSUB_DEPTH"},
    {1134, SE_PROGRAM "NOT_FOUND"},
    {1136, SE_PROGRAM "INVALID_MATRIX_SIZE"},
    {1137, SE_PROGRAM "INVALID_DATA_SIZE"},
    {1138, SE_DATATYPE "NOT_SOCKET"},
    {1139, SE_PROGRAM "INVALID_MATRIX_SIZE"},
    {1140, SE_PROGRAM "LIMIT.CALL_DEPTH"},
    {1200, SE_DATATYPE "NOT_FILE"},
    {1202, SE_DATATYPE "INVALID"},
    {1203, SE_DATATYPE "INVALID"},
    {1220, SE_PROGRAM "RANGE"},
    {1221, SE_DATATYPE "INVALID"},
    {1222, SE_PROGRAM "RANGE"},
    {1223, SE_PROGRAM "RANGE"},
    {1224, SE_PROGRAM "INVALID_DATA_SIZE"},
    {1231, SE_PROGRAM "RESIZE_ERROR"},
    {1232, SE_DATATYPE "NOT_MATRIX"},
    {1234, SE_PROGRAM "RESIZE_ERROR"},
    {1236, SE_DATATYPE "NOT_MATRIX"},
    {1300, SE_PROGRAM "LIMIT.MAX_BREAKPOINTS"},
    {1302, SE_PROGRAM "INVALID_MATRIX_INDEX"},
    {1400, SE_FILESYS "PERMISSIONS.READ_ONLY"},
    {1401, SE_FILESYS "CREATION_ERROR"},
    {1402, SE_FILESYS "OPEN_ERROR"},
    {1403, SE_FILESYS "PERMISSIONS.READ_ONLY"},
    {1404, SE_FILESYS "IO_ERROR"},
    {1405, SE_FILESYS "IO_ERROR"},
    {1406, SE_FILESYS "IO_ERROR"},
    {1407, SE_FILESYS "IO_ERROR"},
    {1408, SE_FILESYS "IO_ERROR"},
    {1409, SE_FILESYS "TRIGGER"},
    {1410, SE_FILESYS "TRIGGER.INVALID_ARGCT"},
    {1412, SE_FILESYS "IO_ERROR"},
    {1413, SE_FILESYS "INVALID_FILE_TYPE"},
    {1414, SE_FILESYS "IO_ERROR"},
    {1415, SE_FILESYS "INVALID_FILE_TYPE"},
    {1416, SE_FILESYS "IO_ERROR"},
    {1417, SE_FILESYS "IO_ERROR"},
    {1418, SE_FILESYS "INVALID_FILE_TYPE"},
    {1419, SE_FILESYS "PERMISSIONS.READ_ONLY"},
    {1420, SE_FILESYS "IO_ERROR"},
    {1421, SE_FILESYS "IO_ERROR"},
    {1424, SE_PROGRAM "NOT_TXN"},
    {1470, SE_PROGRAM "INVALID_ITYPE"},
    {1471, SE_PROGRAM "INVALID_ITYPE"},
    {1480, SE_SORT "IO_ERROR"},
    {1481, SE_SORT "INVALID_KEY_COUNT"},
    {1482, SE_KERNEL "NO_MEMORY"},
    {1485, SE_SORT "IO_ERROR"},
    {1486, SE_SORT "INVALID_KEY_COUNT"},
    {1487, SE_SORT "INVALID_OPERATION"},
    {1488, SE_SORT "INVALID_KEY_COUNT"},
    {1489, SE_SORT "IO_ERROR"},
    {1490, SE_SORT "IO_ERROR"},
    {1491, SE_SORT "IO_ERROR"},
    {1600, SE_PROGRAM "RANGE"},
    {1601, SE_DATATYPE "NULL_STRING"},
    {1602, SE_PROGRAM "INVALID_DATA_SIZE"},
    {1603, SE_PROGRAM "INVALID_DATA_SIZE"},
    {1604, SE_PROGRAM "INVALID_DATA_SIZE"},
    {1605, SE_DATATYPE "NULL_STRING"},
    {1703, SE_PRINTER "INVALID_KEY"},
    {1704, SE_PRINTER "INVALID_OPERATION"},
    {1705, SE_PRINTER "IO_ERROR"},
    {1706, SE_PRINTER "IO_ERROR"},
    {1707, SE_PRINTER "INVALID_KEY"},
    {1708, SE_DATATYPE "NOT_IMAGE"},
    {1709, SE_PRINTER "INVALID_REGION"},
    {1710, SE_KERNEL "NO_MEMORY"},
    {1711, SE_PRINTER "INVALID_OPERATION"},
    {1712, SE_KERNEL "NO_MEMORY"},
    {1716, SE_PRINTER "IO_ERROR"},
    {1717, SE_PRINTER "IO_ERROR"},
    {3450, SE_PROGRAM "IS_CLASS"},
    {3460, SE_DATATYPE "NOT_OBJECT"},
    {10004, SE_PROGRAM "INVALID_DATA_SIZE"},
    {10005, SE_KERNEL "NO_MEMORY"},
    {10151, SE_FILESYS "LOCK_REQUIRED"},
    {12126, SE_DATATYPE "NOT_COLLECTION"},
    {12127, SE_PROGRAM "INVALID_NAME"},
    {12130, SE_DATATYPE "INVALID"},
    {12132, SE_FILESYS "INVALID_FILE_TYPE"},
    {12167, SE_LOCKS "LIMIT"},
    /* 18 Oct 26 Windows port: Linux's 11348 (CREATING.SEQKEY needs a hashed file; the QMClient sitting) and 11355 (the public
       FCONTROL's unknown action) are not carried, so neither has a row here: 12353 and 12360 are left unused. */
    {12403, SE_DATATYPE "NOT_SORT"},
    {12404, SE_SORT "INVALID_OPERATION"},
};

Private int descr_msg_no = 0; /* k_descr_error() tells k_error() which message it is passing on (its text is a copy) */

/* ======================================================================
   sys_exc_name()  -  The SYS.* exception a message stands for, or NULL   */

Private const char* sys_exc_name(int msg_no) {
  int i;

  if (msg_no <= 0)
    return NULL;
  for (i = 0; i < (int)(sizeof(sys_exc_table) / sizeof(sys_exc_table[0])); i++) {
    if (sys_exc_table[i].msg == msg_no)
      return sys_exc_table[i].name;
  }
  return NULL;
}

/* ====================================================================== */

void op_illegal() {
  k_error("Illegal opcode x%02X", (unsigned int)(*(pc - 1)));
}

void op_illegal2() {
  k_error("Illegal opcode x%02X%02X", (unsigned int)(*(pc - 2)),
          (unsigned int)(*(pc - 1)));
}

/* ======================================================================
   General descriptor based message handler                               */

#define DescrError(msg_no, name) \
  void name(DESCRIPTOR* descr) { k_descr_error(msg_no, descr); }

DescrError(1100, k_index_error) DescrError(1101, k_dh_error)
    DescrError(1102, k_not_array_error) DescrError(1103, k_value_error)
        DescrError(1104, k_non_numeric_error) DescrError(1105, k_unassigned)
            DescrError(1106, k_null_id) DescrError(1107, k_illegal_id)
                DescrError(1108, k_div_zero_error)
                    DescrError(1109, k_unassigned_zero)
                        DescrError(1110, k_unassigned_null)
                            DescrError(1111, k_div_zero_warning)
                                DescrError(1112, k_non_numeric_warning)
                                    DescrError(1113, k_data_type)
                                        DescrError(1137, k_strnum_len)
                                            DescrError(1138, k_not_socket)

                                                Private
    void k_descr_error(int16_t msg_no, DESCRIPTOR* descr) {
  char* var;
  char message[80 + 1];
  char* p;

  strcpy(message, sysmsg(msg_no));
  p = strchr(message, '|');
  descr_msg_no = msg_no; /* message is a copy, so k_error() cannot tell which it is */
  if ((var = k_var_name(descr)) != NULL) {
    *p = ' ';
    k_error(message, var);
  } else {
    *p = '\0';
    k_error(message);
  }
}

/* ======================================================================
   Simple messages                                                        */

void k_deadlock() {
  k_error(sysmsg(1114));
}

void k_err_pu() {
  k_error(sysmsg(1115));
}

void k_inva_task_lock_error() {
  k_error(sysmsg(1116));
}

void k_nary_length_error() {
  k_error(sysmsg(1117));
}

void k_select_range_error() {
  k_error(sysmsg(1118));
}

void k_txn_error() {
  k_error(sysmsg(1119));
}

void k_illegal_call_name() {
  k_error(sysmsg(1130));
}

/* ====================================================================== */

void k_error(char* message, ...) {
  /* Modified by Composer AI - 2026/06/10.
     failing_offset and xcbase are only assigned when c_base != NULL. The
     paths that use them cannot be reached otherwise, but initialize them
     anyway so no path can ever read indeterminate values. */
  /* int32_t failing_offset; */
  int32_t failing_offset = 0;
  /* -------------------- */
  char s[(MAX_ERROR_LINES * MAX_EMSG_LEN) + 1]; /* Max 3 lines */
  va_list arg_ptr;
  int16_t n;
  int line;
  struct PROGRAM* pgm;
  int32_t xpc_offset;
  /* Modified by Composer AI - 2026/06/10. See failing_offset above. */
  /* u_char* xcbase; */
  u_char* xcbase = NULL;
  /* -------------------- */
  DESCRIPTOR* msg_descr;
  bool fatal;
  const char* sys_exc = NULL; /* The SYS.* exception to throw instead of aborting, if it will be caught */

  fatal = (*message != '!');

  /* 17 Oct 26: an error with a name in the SYS group goes to a handler, if
     one can be reached, in place of the message and the abort (QM4 Fixes
     354). This is decided first, before the terminal is touched, so that an
     error that is caught leaves the screen as it was. */

  if (fatal && (c_base != NULL)) {
    sys_exc = sys_exc_name((descr_msg_no != 0) ? descr_msg_no : sysmsg_number_of(message));
    if ((sys_exc != NULL) && !exc_sys_can_catch(sys_exc))
      sys_exc = NULL;
  }
  descr_msg_no = 0;

  /* Ensure terminal is in an appropriate mode to receive the error message */

  if (sys_exc == NULL) {
    tio.hush = FALSE;
    tio.suppress_como = TRUE;
    tio_write(sdtgetstr("rlt"));
    tio.suppress_como = FALSE;
  }

  in_sh = FALSE; /* 0562 */

  if (!fatal)
    message++;

  process.numeric_array_allowed = FALSE;

  /* PC may now point anywhere from one byte after the start of the failing
    opcode to the first byte of the next opcode. Back up by one byte to
    place us within the current opcode.                                    */

  if (c_base != NULL) {
    /* Track back through any recursives to report error as belonging to
      parent program.                                                    */

    xpc_offset = pc - c_base;
    xcbase = c_base;

    pgm = &process.program;
    while (pgm->flags & HDR_RECURSIVE) {
      if (internal_mode) {
        tio_printf("%08X in %s \n", xpc_offset - 1,
                   ((OBJECT_HEADER*)xcbase)->ext_hdr.prog.program_name);
      }

      pgm = pgm->prev;
      xpc_offset = pgm->saved_pc_offset;
      xcbase = pgm->saved_c_base;
    }

    failing_offset = xpc_offset - 1;
    n = sprintf(s, "%08X: ", failing_offset);
  } else {
    n = 0;
  }

  va_start(arg_ptr, message);
  /* Fix for Issue #13.  Converted a vsprintf() to vsnprintf(). -gwb */
/* 31 Aug 26 Windows port - THE LIMIT WAS "LINES + LEN" WHERE THE BUFFER IS
   "LINES * LEN".  PRE_RELEASE_FIXES.md 87 / UPSTREAM_FIXES.md 28.  s is
   (MAX_ERROR_LINES * MAX_EMSG_LEN) + 1 = 241 bytes; the bound below said
   (MAX_ERROR_LINES + MAX_EMSG_LEN) + 1 = 84, so every k_error() message was
   truncated at about 84 characters instead of the three 80-column lines the
   buffer was sized for.  Found by measuring PRE_RELEASE 12: message 10151
   rendered as "...A WRITE must already hold an u", cut mid-word, so the half
   that tells the reader what to DO never reached them.

   sizeof(s) - n, NOT the corrected product.  n is already 10 bytes of
   "%08X: " offset prefix written above, so passing the full 241 here would
   let vsnprintf write up to n + 241 into a 241-byte buffer.  The obvious
   repair of the typo - turning the + into a * - introduces a buffer overflow
   where there was only a truncation.                                      */
  vsnprintf(&(s[n]), sizeof(s) - n,  message, arg_ptr);
  va_end(arg_ptr);

  if (c_base == NULL) /* No object currently loaded */
  {
    tio_write(s);
    tio_write("\n");
    k_exit_cause = K_LOGOUT;
    longjmp(k_exit, k_exit_cause);
  }

  /* 29 Sep 26 - RELEASE_1.1 114 (SD Core Solo's SOLO 12).  THESE THREE WERE
     sprintf ONTO THE END OF A BUFFER vsnprintf MAY ALREADY HAVE FILLED.  The
     message above can use all 240 bytes, and " at line N of <program name>"
     (up to 128 more for the name) was then written past s[] - reachable with a
     long %s argument, and easier once op_run() passes runfile paths up to
     MAX_PATHNAME_LEN.  Bounded now; an over-long line is truncated, never
     overrun.                                                              */
  n = strlen(s);
  if (process.program.flags & HDR_ITYPE) {
    // sprintf(s + n, sysmsg(1120)); /* in dictionary expression */
    snprintf(s + n, sizeof(s) - n, "%s", sysmsg(1120)); /* 20Jun12 gwb #1 */

  } else {
    line = k_line_no(failing_offset, xcbase);
    if (line >= 0) {
      snprintf(s + n, sizeof(s) - n, sysmsg(1121), (int)line,
               ((OBJECT_HEADER*)xcbase)->ext_hdr.prog.program_name);
    } else {
      snprintf(s + n, sizeof(s) - n, sysmsg(1122),
               ((OBJECT_HEADER*)xcbase)->ext_hdr.prog.program_name);
    }
  }

  if (sys_exc != NULL) {
    /* Caught: the message is kept for @ABORT.MESSAGE and is the exception's
       data, but is not displayed, logged or dumped (openQM: "System
       Generated Exceptions"). exc_sys_throw() does not return. */

    msg_descr = Element(process.syscom, SYSCOM_ABORT_MESSAGE);
    k_release(msg_descr);
    k_put_c_string(s, msg_descr);
    exc_sys_throw(sys_exc, s);
  }

  tio_write(s);
  tio_write("\n");

  log_message(s);

  if (fatal) {
    /* Save abort message in SYSCOM */

    msg_descr = Element(process.syscom, SYSCOM_ABORT_MESSAGE);
    k_release(msg_descr);
    k_put_c_string(s, msg_descr);

    if (Option(OptShowStackOnError))
      show_stack();

    if (Option(OptDumpOnError))
      pdump();

    k_exit_cause = K_ABORT;
    longjmp(k_exit, k_exit_cause);
  }
}

/* ======================================================================
   k_quit  -  raise quit event. (Also used as opcode)

   BEWARE: This function can be called in mid-opcode (eg during a long
   terminal display).                                                     */

void k_quit() {
  k_exit_cause = K_QUIT;
  longjmp(k_exit, k_exit_cause);
}

/* ======================================================================
   k_line_no()
   Return line number for given PC into program, -1 if cannot locate      */

int k_line_no(int32_t offset, u_char* xcbase) {
  OBJECT_HEADER* obj_header;
  int32_t line_table_end;
  int line;
  int32_t line_pc;
  int16_t bytes;
  u_char* p;

  obj_header = (OBJECT_HEADER*)xcbase;

  /* Modified by Composer AI - 2026/06/10.
     Defensive check: return the documented "cannot locate" value instead
     of dereferencing NULL if no object pointer was supplied. */
  if (obj_header == NULL)
    return -1;
  /* -------------------- */

  line_table_offset = obj_header->line_tab_offset;
  if (line_table_offset) {
    /* The first entry in the line table is for line 0, the fixed stuff on
      the front of the program.                                           */

    line_table_end = obj_header->sym_tab_offset;
    if (line_table_end == 0)
      line_table_end = obj_header->object_size;
    line_table_bytes = line_table_end - line_table_offset;

    p = xcbase + line_table_offset;
    line = 0;
    line_pc = 0;
    while (line_table_bytes-- > 0) {
      bytes = (int16_t)(*(p++));
      if (bytes == 255) {
        bytes = (int16_t)(*(p++));
        bytes |= ((int16_t)(*(p++))) << 8;
        line_table_bytes -= 2;
      }
      line_pc += bytes;

      if (offset < line_pc)
        return line;

      line += 1;
    }
  }

  return -1;
}

/* ======================================================================
   k_var_name()  - Identify variable by name                              */

char* k_var_name(DESCRIPTOR* descr) {
  struct PROGRAM* pgm;
  OBJECT_HEADER* obj_header;
  int32_t sym_tab_offset;
  int16_t d_no; /* Descriptor number within program */
  DESCRIPTOR* d;
  DESCRIPTOR* cd;
  int16_t cd_no;
  ARRAY_HEADER* ahdr;
  ARRAY_CHUNK* achnk;
  int16_t c_no = -1; /* Common block variable index */
  ARRAY_HEADER* chdr;  /* Common block header... */
  ARRAY_CHUNK* cchnk;  /* ...and chunk */
  int32_t cols;
  int32_t element = -1;
  static char name[80 + 1]; /* Extracted variable name */
  u_char* p;
  u_char* q;
  int16_t i;
  int16_t j;
  int16_t n;
  u_char c;
  u_char* xcbase;

  if (descr == NULL)
    return NULL;

  /* Track back through any recursives to report variable error as
    belonging to parent program.                                   */

  xcbase = c_base;
  pgm = &process.program;
  while (pgm->flags & HDR_RECURSIVE) {
    pgm = pgm->prev;
    xcbase = pgm->saved_c_base;
  }

  obj_header = (OBJECT_HEADER*)xcbase;
  if ((sym_tab_offset = obj_header->sym_tab_offset) == 0)
    return NULL;

  /* Follow ADDR chain to base descriptor, stopping if we find an ADDR
    that represents a subroutine argument.                                */

  while (descr->type == ADDR) {
    if (descr->flags & DF_ARG)
      break;
    descr = descr->data.d_addr;
  }

  /* Check decriptor is in variable area */

  d_no = descr - pgm->vars;
  if ((d_no >= 0) && (d_no < pgm->no_vars))
    goto found;

  null_function(); /* Just to stop the compiler optimiser */

  /* No, is it a common variable or an array element? */

  for (d_no = 0, d = pgm->vars; d_no < pgm->no_vars; d_no++, d++) {
    switch (d->type) {
      case ARRAY:
        element = 0;
        ahdr = d->data.ahdr_addr;
        cols = ahdr->cols;
        for (i = 0; i < ahdr->num_chunks; i++) {
          achnk = ahdr->chunk[i];
          if ((descr >= achnk->descr) &&
              (descr < (achnk->descr + achnk->num_descr))) {
            element += descr - achnk->descr;
            goto found;
          }

          element += achnk->num_descr;
        }
        break;

      case COMMON:
        c_no = 0;
        chdr = d->data.ahdr_addr;
        for (j = 0; j < chdr->num_chunks; j++) {
          cchnk = chdr->chunk[j];
          if ((descr >= cchnk->descr) &&
              (descr < (cchnk->descr + cchnk->num_descr))) {
            /* Variable is a simple common block entry */
            c_no += descr - cchnk->descr - 1; /* -1 to skip block name */
            goto found;
          }

          /* Check for arrays in this common chunk */

          for (cd_no = 0, cd = cchnk->descr; cd_no < cchnk->num_descr;
               cd_no++, cd++) {
            if (cd->type == ARRAY) {
              element = 0;
              ahdr = cd->data.ahdr_addr;
              cols = ahdr->cols;
              for (i = 0; i < ahdr->num_chunks; i++) {
                achnk = ahdr->chunk[i];
                if ((descr >= achnk->descr) &&
                    (descr < (achnk->descr + achnk->num_descr))) {
                  c_no += cd - cchnk->descr - 1; /* -1 to skip block name */
                  element += descr - achnk->descr;
                  goto found;
                }

                element += achnk->num_descr;
              }
            }
          }

          c_no += cchnk->num_descr; /* 0450 */
        }
        c_no = -1; /* Didn' find it - make sure we don't treat as common */
        break;
    }
  }

  return NULL;

found:
  /* Identify the variable at offset d_no */

  p = xcbase + sym_tab_offset;

  for (i = 0;
       (i < d_no) && ((q = (u_char*)strchr((char*)p, VALUE_MARK)) != NULL);
       i++) {
    p = q + 1;
  }

  if (i == d_no) /* Found start of symbol */
  {
    q = (u_char*)name;
    if (c_no >= 0) /* Common block reference */
    {
      *(q++) = '/';
    }

    for (i = 0; i < 80; i++) {
      if ((p == NULL) || IsMark(*p) || (*p == '\0'))
        break;
      *(q++) = *(p++);
    }

    if (c_no >= 0) /* Add common block variable name */
    {
      *(q++) = '/';

      p = xcbase + sym_tab_offset;
      while ((p = (u_char*)strchr((char*)p, (char)FIELD_MARK)) != NULL) {
        p++; /* Skip field mark */

        /* Extract common block number */

        n = 0;
        while (IsDigit(*p))
          n = (n * 10) + (*(p++) - '0');

        if (n == d_no) /* Found this common */
        {
          p++; /* Skip VM before first name */

          /* Step through to required variable name */

          for (j = 0; (j < c_no) && (p != NULL); j++) {
            while ((((char)(c = *(p++))) != SUBVALUE_MARK) && (c != '\0')) {
            }
            if (c == '\0')
              p = NULL;
          }

          /* Copy variable name */

          if (p != NULL) {
            while ((!IsMark(*p)) && (*p != '\0'))
              *(q++) = *(p++);
            break;
          }
        }
      }
    }

    switch (element) {
      case -1: /* Not an array */
        *q = '\0';
        break;

      case 0: /* Zero element */
        sprintf((char*)q, (cols == 0) ? "(0)" : "(0,0)");
        break;

      default: /* Some other element */
        if (cols == 0)
          sprintf((char*)q, "(%d)", element);
        else
          sprintf((char*)q, "(%d,%d)", ((element - 1) / cols) + 1,
                  ((element - 1) % cols) + 1);
        break;
    }
  }

  return name;
}

void null_function() {}

/* ======================================================================
   log_message()  -  Add message to error log                             */

void log_message(char* msg) {
  OSFILE errlog;
  time_t timenow;
  struct tm* ltime;
  int bytes;
  int src;
  int dst;
#define BUFF_SIZE 4096
  char buff[BUFF_SIZE];
  char* p;

  if (sysseg->errlog) {
    StartExclusive(ERRLOG_SEM, 66);

    sprintf(buff, "%s%cerrlog", sysseg->sysdir, DS);
    errlog = dio_open(buff, DIO_OVERWRITE);

    if (ValidFileHandle(errlog)) {
      if (filelength64(errlog) >= sysseg->errlog) {
        /* Must trim front from log file */

        src = sysseg->errlog / 2; /* Move from here... */
        dst = 0;                  /* ...to here */

        Seek(errlog, src, SEEK_SET);
        bytes = Read(errlog, buff, BUFF_SIZE);
        src += bytes;

        /* Find the first newline (there must be one) */

        p = ((char*)memchr(buff, '\n', bytes)) + 1;
        bytes -= (p - buff); /* Bytes to copy */

        do {
          Seek(errlog, dst, SEEK_SET);
          dst += Write(errlog, p, bytes);

          Seek(errlog, src, SEEK_SET);
          bytes = Read(errlog, buff, BUFF_SIZE);

          src += bytes;
          p = buff;
        } while (bytes > 0);

        /* Truncate the file */

        chsize64(errlog, dst);
      }

      Seek(errlog, 0, SEEK_END);

      timenow = time(NULL);
      ltime = localtime(&timenow);

      /* The buffer trimming mechanism above requires that the file is
        opened in binary mode on Windows systems otherwise the destination
        pointer loses track because Windows is busy modifying the data
        written to the file. Therefore, we must do our own handling of
        the CRLF newline pair on Windows. To do this in a platform
        independent way, we use the Newline macro in the sprintf() below
        instead of the more obvious use of \n.                            */

      if (my_uptr != NULL) {
        bytes = sprintf(
            buff,
            "%02d %.3s %02d %02d:%02d:%02d User %d (pid %d, %s):%s   %s%s",
            ltime->tm_mday, month_names[ltime->tm_mon], ltime->tm_year % 100,
            ltime->tm_hour, ltime->tm_min, ltime->tm_sec, my_uptr->uid,
            my_uptr->pid, my_uptr->username, Newline, msg, Newline);
      } else {
        bytes = sprintf(buff, "%02d %.3s %02d %02d:%02d:%02d:%s   %s%s",
                        ltime->tm_mday, month_names[ltime->tm_mon],
                        ltime->tm_year % 100, ltime->tm_hour, ltime->tm_min,
                        ltime->tm_sec, Newline, msg, Newline);
      }

      Write(errlog, buff, bytes);

      CloseFile(errlog); /* 0423 */
    }

    EndExclusive(ERRLOG_SEM);
  }
}

/* ======================================================================
   audit_message()  -  Append a record to the audit trail

   16 Aug 26 Windows port.  PROJECT_STATUS.md 7 step 4, and the missing half
   of the identity model in 5.6: access is controlled, and until this existed
   nothing recorded who used it.

   WHY NOT log_message().  errlog TRIMS ITS OLDEST HALF when it reaches the
   configured ERRLOG size (above, and config.c requires 10kb for that to work).
   That is right for diagnostics and disqualifying for an audit trail, where
   the record an investigator wants is exactly the old one somebody would like
   discarded.  This file therefore ROTATES: at AUDIT_ROTATE_BYTES the current
   file is renamed with a timestamp and a new one started, so nothing is ever
   deleted by SD.  Pruning the old ones is a site decision, deliberately not
   ours to make.

   THE CALLER DOES NOT SUPPLY THE IDENTITY, and that is the point rather than
   an economy.  The timestamp, user number, pid and username are stamped here
   from my_uptr; the caller passes only what happened.  5.6 warns that CPROC
   reassigns logname when it drops to sdsys, so a trail that believed a BASIC
   caller's idea of who it was would attribute a step-up to the account being
   stepped into.  my_uptr->username is the OS identity that authenticated and
   no BASIC program can change it.

   ERRLOG_SEM rather than a seventh semaphore.  Both are log writes held for
   the length of one append, contention between them is not a real scenario,
   and NUM_SEMAPHORES is part of the shared segment layout - see sysseg.h.

   APPEND ONLY, AND THROUGH win32audit.c RATHER THAN dio_open().  The
   installer grants sdusers AppendData on this file and withholds WriteData,
   so that the people it records can add to it and cannot rewrite it.  The
   POSIX runtime cannot open a file that way: O_WRONLY becomes GENERIC_WRITE,
   which contains FILE_WRITE_DATA, and the open fails with errno 13.  Measured
   16 Aug 2026, along with what granting WriteData to make it work costs -
   with it an ordinary user CAN truncate the trail to nothing and CAN
   overwrite earlier records in place.  win32audit.h has both measurements.

   So the write goes through one CreateFile asking for FILE_APPEND_DATA alone.
   The kernel then puts every record at the end, and the ACL can withhold
   everything else.  Owner's decision, 16 Aug 2026: administrators are trusted,
   so this raises the floor rather than trying to be proof against the people
   holding the keys - Administrators and SYSTEM keep full control.

   The semaphore is kept even though appends are atomic: it stops a record
   interleaving with a log_message(), and it is what audit_rotate() locks
   against.

   Silent on failure, like log_message().  This is called from the login path
   and an audit file that cannot be written must not be what stops somebody
   logging in; the missing records are themselves the evidence.               */

#define AUDIT_ROTATE_BYTES 1048576L /* 1MB, then rename and start a new one */
#define AUDIT_BUFF_SIZE    2048     /* One record.  op_kernel caps msg well
                                       below this; the stamp adds ~70.      */

Private void audit_pathname(char* path, int len) {
  if (snprintf(path, len, "%s%caudit", sysseg->sysdir, DS) >= len)
    *path = '\0';
}

void audit_message(char* msg) {
  time_t timenow;
  struct tm* ltime;
  int bytes;
  char path[MAX_PATHNAME_LEN + 1];
  char buff[AUDIT_BUFF_SIZE];

  if (sysseg == NULL)
    return;

  timenow = time(NULL);
  ltime = localtime(&timenow);

  StartExclusive(ERRLOG_SEM, 67);

  audit_pathname(path, sizeof(path));

  if (*path != '\0') {
    /* Newline rather than \n for the reason log_message() gives above - this
       is a byte count handed to WriteFile, not a text-mode stream.        */

    if (my_uptr != NULL) {
      bytes = snprintf(buff, sizeof(buff),
                       "%04d-%02d-%02d %02d:%02d:%02d user=%s uid=%d "
                       "pid=%d %s%s",
                       ltime->tm_year + 1900, ltime->tm_mon + 1, ltime->tm_mday,
                       ltime->tm_hour, ltime->tm_min, ltime->tm_sec,
                       my_uptr->username, my_uptr->uid, my_uptr->pid, msg,
                       Newline);
    } else {
      bytes = snprintf(buff, sizeof(buff),
                       "%04d-%02d-%02d %02d:%02d:%02d user=? uid=? pid=? "
                       "%s%s",
                       ltime->tm_year + 1900, ltime->tm_mon + 1, ltime->tm_mday,
                       ltime->tm_hour, ltime->tm_min, ltime->tm_sec, msg,
                       Newline);
    }

    /* snprintf reports the length it WANTED, not what it wrote, so a long
       record would otherwise send WriteFile past the end of the buffer.   */

    if (bytes > (int)sizeof(buff) - 1)
      bytes = (int)sizeof(buff) - 1;

    if (bytes > 0)
      (void)win32_audit_append(path, buff, bytes);
  }

  EndExclusive(ERRLOG_SEM);
}

/* ======================================================================
   audit_rotate()  -  Start a new audit file if the current one is large

   16 Aug 26 Windows port.  PROJECT_STATUS.md 7 step 4.  SEPARATE FROM
   audit_message() BECAUSE ORDINARY USERS CANNOT DO IT: renaming needs Delete
   on the file and write on the directory, and the whole point of the ACL the
   installer sets is that sdusers has neither.  A rotation attempted on every
   record would therefore fail on every record written by the people this
   trail exists to record.

   So it is called from start_sd(), which is elevated and runs before any
   session exists - which also means nothing can be mid-append while the
   rename happens.  It takes ERRLOG_SEM anyway, because "nothing else is
   running" is an assumption about the caller and not a property of this
   function.

   THE CONSEQUENCE, AND IT IS ACCEPTED: a machine that never restarts never
   rotates, and the file grows without limit.  SD is a service that starts at
   boot, so in practice it rotates whenever the machine does.  If that stops
   being good enough, sdwind's five-minute slot (sdwind.c) is the right home -
   it is privileged and long-lived - but sdwind links four objects and not the
   kernel, so this would have to move to its own file first.

   Renaming rather than deleting: nothing here discards a record.  Pruning the
   old files is left to the site, deliberately.                              */

void audit_rotate(void) {
  time_t timenow;
  struct tm* ltime;
  char path[MAX_PATHNAME_LEN + 1];
  char rotated[MAX_PATHNAME_LEN + 1];
  struct stat statbuf;

  if (sysseg == NULL)
    return;

  StartExclusive(ERRLOG_SEM, 68);

  audit_pathname(path, sizeof(path));

  /* stat() rather than opening it - this needs the size and no more, and
     asking for a handle it does not need is how the append path went wrong. */

  if ((*path != '\0') && !stat(path, &statbuf) &&
      (statbuf.st_size >= AUDIT_ROTATE_BYTES)) {
    timenow = time(NULL);
    ltime = localtime(&timenow);

    if (snprintf(rotated, sizeof(rotated), "%s.%04d%02d%02d-%02d%02d%02d", path,
                 ltime->tm_year + 1900, ltime->tm_mon + 1, ltime->tm_mday,
                 ltime->tm_hour, ltime->tm_min, ltime->tm_sec) <
        (int)sizeof(rotated)) {
      /* NOT rename() - the new file has to carry the old one's ACL, or the
         trail silently becomes editable by the users it records from the
         first rotation onwards.  win32audit.h explains.                   */

      (void)win32_audit_rotate(path, rotated);
    }
  }

  EndExclusive(ERRLOG_SEM);
}

/* ======================================================================
   op_logmsg()  -  Log a message in the errlog file                       */

void op_logmsg() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Message to log             |                             |
     |=============================|=============================|
 */

#define MAX_LOG_MSG_LEN 500

  DESCRIPTOR* descr;
  char msg[MAX_LOG_MSG_LEN + 1];

  descr = e_stack - 1;
  k_get_c_string(descr, msg, MAX_LOG_MSG_LEN);

  log_message(msg);

  k_dismiss();
}

/* ======================================================================
   log_printf()  -  tio version of printf() with logging to errlog        */

int log_printf(char* template_string, ...) {
  char s[MAX_LOG_MSG_LEN];
  va_list arg_ptr;
  int16_t n;
  int bytes;

  va_start(arg_ptr, template_string);

  n = vsprintf(s, template_string, arg_ptr);

  bytes = strlen(s);

  /* If this is a logged in user, display the message too */

  if (my_uptr != NULL)
    tio_display_string(s, bytes, TRUE, FALSE);

  /* Log message, removing possible trailing newline */

  if (s[bytes - 1] == '\n')
    s[bytes - 1] = '\0';
  log_message(s);

  va_end(arg_ptr);

  return n;
}

/* ======================================================================
   log_permissions_error()                                                */

void log_permissions_error(FILE_VAR* fvar) {
  char msg[MAX_PATHNAME_LEN + 50];

  if (abs(process.status) == ER_PERM) {
    sprintf(msg, "Permissions error on %s",
            (char*)(FPtr(fvar->file_id)->pathname));
  } else {
    sprintf(msg, "Update to read-only file %s",
            (char*)(FPtr(fvar->file_id)->pathname));
  }
  log_message(msg);
}

/* ======================================================================
   priv_log_undetermined()  -  Record a privilege check that could not answer

   03 Sep 26 Windows port - PRE_RELEASE_FIXES.md 96.  A lockout has to be
   distinguishable from a denial in the record, and until now neither left a
   trace: kernel.c simply did not set USR_ADMIN, with no message and no log.

   IT IS HERE RATHER THAN IN linuxlb.c BESIDE THE PREDICATES, AND THE LINKER
   DECIDED THAT.  linuxlb.o is linked into sdfix, sdtic, sdconv and sdidx, none
   of which carry this file, so a log call from there fails to link all four -
   "linuxlb.o: undefined reference to `log_message'", which is what the first
   build of this entry did.

   IT IS log_message() AND NOT log_printf(), WHICH IS NOT A STYLE CHOICE.
   log_printf() calls tio_display_string() whenever my_uptr != NULL (below), so
   every line here would ALSO print on the user's terminal mid-session - new
   console output on a privilege path, which is the thing PRE_RELEASE 84 caught
   verifiers matching against.

   AND sysseg IS TESTED BECAUSE log_message() DEREFERENCES IT UNGUARDED
   ("if (sysseg->errlog)" above).  sysseg is init(NULL) until bind_sysseg().
   Every caller reaches this with the segment bound; sd.c's check_admin() does
   NOT, which is exactly why that one site prints to stderr itself rather than
   calling this - a guard that silently did nothing there would have omitted
   the case the entry was filed for.                                        */

void priv_log_undetermined(char* what, PRIV_WHY why) {
  char msg[MAX_LOG_MSG_LEN];

  if (sysseg == NULL)
    return;

  snprintf(msg, sizeof(msg),
           "PRIVILEGE CHECK UNDETERMINED %s: %s - refused, but this is not a "
           "denial", what, priv_why_text(why));
  log_message(msg);
}

/* END-CODE */
