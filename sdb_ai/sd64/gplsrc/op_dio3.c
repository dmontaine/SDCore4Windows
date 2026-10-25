/* OP_DIO3.C
 * Disk i/o opcodes (Read, write and delete actions for DH and type1 files)
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
 * 25 Oct 26 Windows port - from Linux 5315c65 (18 Oct 26), S.65 slice 3e: WRITE, WRITEU, MATWRITE, WRITEV, DELETE and CLEARFILE of a NET_FILE of a write-mode
 *               server go to netfiles.c (net_write, net_delete, net_clear), and READU, READL, MATREADU, MATREADL, READVU and READVL take the record lock
 *               there first (net_lock_step), once refuse_net_file() has asked net_gate(); a read-mode file variable is refused as in slice 3c.  MUSTLOCK
 *               and $MODE AUTOLOCK are honoured for a remote WRITE and DELETE (net_pre_change_lock).  Refactored: refuse_net_file() takes the
 *               kind of statement; net_reload_read_operands() is the operand lookup that read_record() needed twice.
 * 25 Oct 26 Windows port - from Linux e7ea5f8 (17 Oct 26), S.65 slice 3c: a NET_FILE (a file on another SD server) is read by READ, MATREAD and READV through
 *               net_read() and net_readv(); every other statement that can be given a file variable in this file (the locking forms of the reads,
 *               WRITE, WRITEV, DELETE, CLEARFILE) refuses it with net_refuse() before it touches anything.
 * 25 Oct 26 Windows port - from Linux fc4030a (S.66): edit_refusal() asks edit_refusal_for_canon() (op_sh.c: the administrator, then shared.write for a
 *               file inside the shared account, then the S.64 kind) after its own HDR_INTERNAL and administrator returns; EDIT_REFUSED_MSG() is
 *               edit_refused_message() (12518 and 12519 as well as 12410-12412); shared_structure_refusal() (no HDR_INTERNAL exemption) is asked by
 *               CLEARFILE before the read-only and S.64 tests, and by the structure ops of other files.
 * 23 Oct 26 Windows port - from Linux d7cda81 (17 Oct 26), S.64, the edit gates: edit_refusal() before a WRITE, WRITEV, DELETE or CLEARFILE of a
 *               VOC, a dictionary or a program file by a program that is not $internal and a session that has not the gate (voc.edit,
 *               dict.edit, bp.edit).  RELEASE_1.1 170.
 * 18 Oct 26 Windows port - from Linux 9f067b8 (11 Oct 26): Data collection files: text written to one is made into its collection before
 * 15 Oct 26 Windows port - from Linux 400500c - WRITE ... CREATING.SEQKEY skips an id that already names a record (owner's choice, a difference from openQM).
 * 15 Oct 26 Windows port - from Linux 400500c - WRITE ... CREATING.SEQKEY: a read-only file variable is refused, and a suspended system waited for, BEFORE an id is
 *               taken from the file's counter (the audit of the counter: a refused write had moved it on).
 * 11 Oct 26 Windows port - from Linux 400500c - Data collection files: text written to one is made into its collection before
 *               the pre-write trigger, so a trigger is always given a collection, and the
 *               post-write trigger is given the collection (call_trigger passed it as a string
 *               and the trigger stopped the process: Fault type 11).
 * 18 Oct 26 Windows port - from Linux 5572c08 (12 Oct 26): map_t1_id(): bytes 128 to 255 are allowed in a directory file record id (openQM item 34).
 *  4 Sep 26 Windows port - dir_read() added, the read half the directory code
 *           never had: dir_write() has always been callable but the only
 *           reader was read_record(), which takes its arguments off the VM's
 *           e-stack, so nothing outside an executing READ opcode could ask
 *           what a directory record held.  PRE_RELEASE_FIXES 102's undo needs
 *           exactly that.  The CRLF/LF to field-mark conversion is lifted into
 *           t1_unmap_chunk() and SHARED by both readers rather than copied,
 *           because a capture that reverses the mapping differently from an
 *           ordinary READ would restore the wrong bytes silently.
 * 31 Aug 26 Windows port - a WRITE refused for want of a lock reported
 *           "Error 3023 (o/s 0) writing record (Possible full disk?)".  The
 *           disk is not involved and nothing was written; message 10151 says
 *           what happened and how to fix it.  PRE_RELEASE_FIXES.md 12,
 *           UPSTREAM_FIXES.md 20.
 * 24 Aug 26 Windows port - a directory-file record written by an external
 *           editor with CRLF read back with a trailing CR on EVERY field: the
 *           mapping loop turned the LF into a field mark and left the CR.
 *           CRLF now folds to ONE field mark; a LONE CR is left alone because
 *           it is data.  Image mode is untouched, so binary reads cannot be
 *           affected.  The CR is held across the chunk boundary rather than
 *           assumed to be in one chunk: MAX_T1_BUFFER_SIZE is 31744.
 *           PROJECT_STATUS.md 7 step 16 (a).
 * rev 0.9-3 mab map_t1_id - map ~ to %T and . to %D (consistent with what dir_select in op_dio4.c)
 * rev 0.9.0 Jan 25 mab change dyn file prefix to %
 * 01 Jul 24 mab define max string size.
 * 31 Dec 23 SD launch - prior history suppressed
 * 25 Aug 26 Windows port - VFS stripped: the C never implemented it
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *  op_clrfile         CLRFILE
 *  op_delete          DELETE
 *  op_mapmarks        MAPMARKS
 *  op_matread         MATREAD
 *  op_read            READ
 *  op_readv           READV
 *  op_write           WRITE
 *  op_writev          WRITEV
 *
 *  dir_read           Read record from directory file
 *  dir_write          Write record to directory file
 *
 * Private functions
 *  t1_buffer_alloc    Allocate working buffer for directory file handling
 *  t1_write           Write data to directory file
 *  t1_flush           Flush directory file working buffer
 *  t1_buffer_free     Free working buffer for directory file handling
 *  t1_unmap_chunk     CRLF/LF to field marks, shared by both readers
 *  read_record        Read/Matread common path
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "dh_int.h"
#include "syscom.h"
#include "header.h"
#include "config.h"
#include "locks.h"
#include "sdclient.h"
#include "options.h"

#include <time.h>
#include <fcntl.h>
#include <sys/stat.h>

/* Modified by Composer AI - 2026/06/10.
   k_error() longjmps back to the kernel command loop and never returns,
   but the analyzer cannot see this across translation units. Redeclare
   it with the noreturn attribute so that paths following a k_error()
   call (e.g. the NULL check in t1_buffer_alloc) are not reported as
   NULL dereferences. */
void k_error(char msg[], ...) __attribute__((noreturn));
/* -------------------- */

#define MAX_T1_BUFFER_SIZE 31744

/* 17 Oct 26 dm S.65 slice 3c: the NET_FILE entry points, as slice 3c declares them in sd.h (a second declaration is harmless).
   net_read() and net_readv() return 0 with the record (or the field) in *rec / *out, a positive local status (ER_RNF) for the ELSE
   branch, or a negative status for an error, and leave *rec / *out alone unless they return 0.  net_refuse() reports the refusal
   of an operation (message 12506) and returns the negative status for ON ERROR.  All three raise the error themselves, with the
   handler's message, unless process.op_flags holds P_ON_ERROR; the callers below set it for the call and clear it after.      */
int net_read(FILE_VAR *fvar, char *id, int16_t id_len, STRING_CHUNK **rec);
int net_readv(FILE_VAR *fvar, char *id, int16_t id_len, int32_t field, STRING_CHUNK **out);
int net_refuse(FILE_VAR *fvar, const char *what);

/* The modes of a directory file's trigger function (QM4 Fixes item 177): 0 if it has none */
#define DirTrgModes(fvar) ((fvar)->access.dir.trg != NULL ? (fvar)->access.dir.trg->modes : 0)

Private char *t1_buffer = NULL;
Private int t1_buffer_size;
Private int16_t t1_space;
Private char *t1_ptr;
Private OSFILE t1_fu;

void t1in(char *src, char *dst, int16_t inct, int16_t *outct);

/* ======================================================================
   edit_write_refused()  -  Is this a change to a VOC, a dictionary or a program file that the session may not make?

   17 Oct 26 dm, S.64 (owner, 17 Oct: the gates voc.edit, bp.edit and dict.edit).  Linux Solo's voc_write_refused() (LSOLO 6, the
   owner's ruling 14 for Solo) is the model, widened to the other two kinds and asking a per-account gate instead of ADMIN.  The
   kind comes from the pathname of the OPEN file (op_sh.c edit_kind_of_path), so a Q-pointer to a VOC is caught.  DIRECT edits
   only: the records SD writes itself as a side effect of ordinary commands - CREATE.FILE's F-record, a saved sentence, the
   command stack, a compiled I-type - come from $internal programs, so HDR_INTERNAL lets them through.  ED, SED, COPY, DELETE and
   the rest are $internal too, and so ask K_EDIT_OK for themselves in BASIC (gpl.bp/edit_guard).  The caller's program flags
   are read BEFORE any k_recurse(), since the recursive pcode is itself $internal (see op_writev()).  The administrator is never
   refused.  The cost for a file that is none of the three is one scan of the last path component.                           */

Private int edit_refusal(FILE_VAR *fvar) {
  const char *path;
  int kind;

  /* Only a hashed or a directory file has a pathname in the file table.  A NET_FILE (S.65) has no file table entry (file_id is -1),
     so it is answered here and never reaches FPtr(): the NET refusals in the opcodes come before this call anyway. */
  if ((fvar == NULL) || ((fvar->type != DYNAMIC_FILE) && (fvar->type != DIRECTORY_FILE)))
    return EDIT_NONE;
  if (process.program.flags & HDR_INTERNAL)
    return EDIT_NONE;
  if (my_uptr->flags & USR_ADMIN)
    return EDIT_NONE;

  /* The file table is shared memory; the name cannot change while this session holds the file open.  18 Oct 26 S.66: the order of
     the tests (the shared account's shared.write, then the S.64 kind) is edit_refusal_for_canon()'s, op_sh.c. */
  path = (const char *)FPtr(fvar->file_id)->pathname;
  kind = edit_refusal_for_canon(path);
  return kind;
}

/* 18 Oct 26 S.66: the message for a refusing kind: 12410 the VOC, 12411 a dictionary, 12412 a program file, 12518 a shared file without
   shared.write, 12519 a structure change to a shared file (op_sh.c edit_refused_message) */
#define EDIT_REFUSED_MSG(kind) edit_refused_message(kind)

/* ======================================================================
   refuse_net_file()  -  Is this a NET_FILE?  If so, refuse the operation.

   17 Oct 26 dm, S.65 slice 3c.  A file on another SD server is read only in stage 1, and it has no file table entry, no lock, no
   transaction cache and no trigger: file_id is -1, so any code that goes on to FPtr(fvar->file_id), lock_record() or
   log_permissions_error() would read or WRITE memory in front of the file table.  Every statement of this file that is given a
   file variable and is not a plain READ or READV of a NET_FILE calls this FIRST, before it takes a lock, a transaction cache entry
   or an edit-gate decision.

   Returns FALSE (and does nothing) for any other kind of file.

   18 Oct 26 dm, slice 3e: for a NET_FILE it now asks net_gate() (netfiles.c) whether this KIND of statement (NETG_WRITE, NETG_DELETE,
   NETG_CLEAR, NETG_LOCK) may go on.  A file variable of a read-mode server is refused exactly as before (message 12506, status -7000);
   a write-mode one is refused for a transaction (12515, -1010), CREATING.SEQKEY (12516) or the S.64 edit gate of the remote file's name
   (12410 to 12412, -3035).  A refusal is raised by net_gate() itself unless the statement has ON ERROR, and then TRUE is returned with
   process.status the negative status for the caller to put on the stack.  FALSE for a NET_FILE means the gate passed: the caller then
   takes its NET arm (it must test fvar->type == NET_FILE itself).  The test below the call is only the safety net for a net_gate() that
   came back with no ON ERROR: the statement still fails.  The gate runs no BASIC, so the caller's program flags are the ones it tests. */

Private bool refuse_net_file(FILE_VAR *fvar, u_int16_t op_flags, const char *what, int kind) {
  int st;

  if ((fvar == NULL) || (fvar->type != NET_FILE))
    return FALSE;

  process.op_flags = op_flags & P_ON_ERROR; /* net_gate() raises the error unless this holds ON ERROR */
  st = net_gate(fvar, kind, op_flags, what);
  process.op_flags = 0;
  if (st == 0)
    return FALSE;

  process.status = (st < 0) ? st : -ER_PERM;

  if (!(op_flags & P_ON_ERROR))
    k_error("%s", net_message());

  return TRUE;
}

/* ======================================================================
   net_pre_change_lock()  -  The lock rules of a WRITE or DELETE of a NET_FILE (slice 3e), which the local code applies with check_lock() and
   lock_record() and a remote file has neither of.  $MODE AUTOLOCK: take the update lock now (waiting, by running the opcode again).  MUSTLOCK:
   the session must hold it already, as for a local file; without this a program under MUSTLOCK would write a record it had not locked,
   which the same program cannot do locally.  A plain WRITE or DELETE lets the server release the lock when it is done.
   NETL_GO: carry on.  NETL_WAIT: the opcode is set up to run again; the caller RETURNS AT ONCE.  NETL_FAIL: process.status is the
   negative status (already raised unless ON ERROR); the caller goes to its exit.                                                     */

#define NETL_GO 0
#define NETL_WAIT 1
#define NETL_FAIL 2

Private int net_pre_change_lock(FILE_VAR *fvar, char *id, int16_t id_len, u_int16_t op_flags, u_char *retry_pc) {
  int st;

  if (op_flags & P_AUTOLOCK) {
    st = net_lock_step(fvar, id, id_len, TRUE, op_flags & ~P_LOCKED, retry_pc);
    switch (st) {
      case NET_LOCK_HELD:
        return NETL_GO;
      case NET_LOCK_WAIT:
        return NETL_WAIT;
      case NET_LOCK_LOCKED: /* (not reached: P_LOCKED is taken off) */
        process.status = -ER_NOLOCK;
        return NETL_FAIL;
      default:
        return NETL_FAIL; /* an error: process.status is set */
    }
  }

  if (pcfg.must_lock) {
    process.op_flags = op_flags & P_ON_ERROR;
    st = net_check_lock(fvar, id, id_len);
    process.op_flags = 0;
    if (st == 0) {
      process.status = -ER_NOLOCK;
      return NETL_FAIL;
    }
    if (st < 0) {
      process.status = st;
      return NETL_FAIL;
    }
  }
  return NETL_GO;
}

/* ======================================================================
   net_reload_read_operands()  -  The operands of READ, MATREAD, READU... found again on the e-stack (record id, file variable, and the
   target through its ADDRs).  After a call into netfiles.c the e-stack may have been moved by the handler.                            */

Private void net_reload_read_operands(DESCRIPTOR **rid_descr, DESCRIPTOR **fvar_descr, DESCRIPTOR **tgt_descr) {
  *rid_descr = e_stack - 1;
  *fvar_descr = e_stack - 2;
  *tgt_descr = e_stack - 3;
  do {
    *tgt_descr = (*tgt_descr)->data.d_addr;
  } while ((*tgt_descr)->type == ADDR);
}

/* ======================================================================
   shared_structure_refusal()  -  18 Oct 26 dm, S.66.  A STRUCTURE change (CLEARFILE, CONFIGURE.FILE, an index made or deleted, a
   trigger set, a header setting) to a file inside the shared account's directory is SDSYS's alone, signed on at a terminal
   (USR_ADMIN).  HDR_INTERNAL is NOT an exemption: no sanctioned internal path changes the structure of a shared file for anyone else.
   EDIT_SHARED_STRUCT or EDIT_NONE.  A file that is not a hashed or a directory file has no pathname here and is none of them.      */

int shared_structure_refusal(FILE_VAR *fvar) {
  if ((fvar == NULL) || ((fvar->type != DYNAMIC_FILE) && (fvar->type != DIRECTORY_FILE)))
    return EDIT_NONE;
  if (my_uptr->flags & USR_ADMIN)
    return EDIT_NONE;
  if (path_in_shared((const char *)FPtr(fvar->file_id)->pathname))
    return EDIT_SHARED_STRUCT;
  return EDIT_NONE;
}

void op_write(void); /* Necessary for internal call */
void op_dspnl(void);
void op_matparse(void);

Private void t1_buffer_alloc(int32_t size);
Private bool t1_write(char *p, int16_t bytes);
Private bool t1_flush(void);
Private void t1_buffer_free(void);
/* 4 Sep 26 Windows port - PRE_RELEASE_FIXES 102; shared by read_record() and
   dir_read() so the two cannot reverse the mark mapping differently. */
Private int32_t t1_unmap_chunk(char *buff,
                               int32_t bytes,
                               bool last_chunk,
                               bool *cr_pending);
Private void read_record(bool matread);
Private bool valid_id(char *id, int16_t id_len);

/* 16 Oct 26 (QM4 Fixes item 452): the line terminator modes of a directory file.  A record is read in chunks of up to
   MAX_T1_BUFFER_SIZE bytes, and a CR LF pair, or the terminator at the very end, can fall across two chunks, so the modes
   that look at CR keep what they have not decided yet in one of these between chunks. */
typedef struct T1_UNMAP {
  u_char mode;     /* CRLF_x of the file */
  bool pending_cr; /* a CR ended the last chunk: data, or the first half of CR LF, as the next byte decides */
  bool hold_fm;    /* the last chunk ended in the field mark of a terminator, kept back: it is dropped if it is the last one */
} T1_UNMAP;
Private int32_t t1_unmap_crlf(T1_UNMAP *st, char *buff, int32_t bytes, bool last_chunk, char *prefix, int *prefix_len);
Private int32_t t1_unmap_lf(char *buff, int32_t bytes, bool last_chunk);
Private void t1_unmap_and_copy(FILE_VAR *fvar, T1_UNMAP *st, char *buff, int32_t bytes, bool last_chunk);

/* ======================================================================
   op_clrfile()  -  Clear File                                            */

void op_clrfile() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  File variable              | Status 0=ok, <0 = ON ERROR  |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to CLRFILE.
 */

  DESCRIPTOR *fvar_descr;
  FILE_VAR *fvar;
  char pathname[MAX_PATHNAME_LEN + 1];
  int path_len;
  char subfilename[MAX_PATHNAME_LEN + 1];
  DIR *dfu;
  struct dirent *dp;
  u_int16_t op_flags;
  FILE_ENTRY *fptr;
  DH_FILE *dh_file;
  bool took_lock = FALSE; /* Did we aquire lock here? */

  op_flags = process.op_flags;
  process.op_flags = 0;

  process.status = 0;

  if (sysseg->flags & SSF_SUSPEND)
    suspend_updates();

  /* Find the file variable descriptor */

  fvar_descr = e_stack - 1;
  k_get_file(fvar_descr);
  fvar = fvar_descr->data.fvar;

  /* 17 Oct 26 S.65 slice 3c: a file on another server is not cleared by a read-mode file variable.  Before the file lock below, which
     writes the file table at FPtr(file_id) and a NET_FILE has none.
     18 Oct 26 slice 3e: a write-mode one is cleared by the server (net_clear()).  No local transaction, read-only, edit-gate or file lock
     test follows for it: net_gate() made them, and a remote file has no file lock here. */
  if (refuse_net_file(fvar, op_flags, "CLEARFILE", NETG_CLEAR)) {
    k_dismiss();
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = process.status;
    return;
  }
  if (fvar->type == NET_FILE) {
    int net_st;

    process.op_flags = op_flags & P_ON_ERROR;
    net_st = net_clear(fvar); /* the handler runs BASIC: the stack is found by e_stack from here on */
    process.op_flags = 0;
    process.status = net_st;
    k_dismiss(); /* the file variable */
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = process.status;
    return;
  }

  /* 18 Oct 26 S.66: CLEARFILE changes the STRUCTURE of a file in the shared account (it empties it): SDSYS's alone, and a $internal program is
     not exempt.  Before anything is taken or touched; shaped as the S.64 block below. */
  if (shared_structure_refusal(fvar) != EDIT_NONE) {
    if (!(op_flags & P_ON_ERROR))
      k_error(sysmsg(EDIT_REFUSED_MSG(EDIT_SHARED_STRUCT)));
    process.status = -ER_PERM;
    k_dismiss();
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = process.status;
    return;
  }

  if ((process.txn_id != 0) && !(fvar->flags & FV_NON_TXN))
    k_txn_error();

  if (fvar->flags & FV_RDONLY)
    k_error(sysmsg(1403));

  {
    int edit_kind = edit_refusal(fvar); /* 17 Oct 26 S.64: the edit gates */

    if (edit_kind != EDIT_NONE) {
      if (!(op_flags & P_ON_ERROR))
        k_error(sysmsg(EDIT_REFUSED_MSG(edit_kind)));
      /* ON ERROR: nothing has been taken or touched yet, so drop the file variable and report the refusal as the tail does */
      process.status = -ER_PERM;
      k_dismiss();
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = process.status;
      return;
    }
  }

  {
    /* Get exclusive access to the file_lock entry in the file table. Because
      acquisition of a file lock may require scanning the record lock table,
      the file_lock entry is protected by the REC_LOCK_SEM. The file table
      entry cannot go away while we are looking at it because we have the
      file open.                                                              */

    StartExclusive(REC_LOCK_SEM, 3);

    /* Wait if file lock held elsewhere. */

    fptr = FPtr(fvar->file_id);
    if (fptr->file_lock != process.user_no) {
      if (fptr->file_lock != 0) {
        EndExclusive(REC_LOCK_SEM);
        pc--; /* Back up to repeat opcode */
        if (my_uptr->events)
          process_events();
        Sleep(500);
        return;
      }
      took_lock = TRUE;
    }

    fptr->file_lock = -process.user_no; /* Mark clearfile in progress */
    if (took_lock)
      fptr->file_lock_time = (int32_t)time(NULL); /* item 487 */
    if (fptr->ref_ct > 1)
      Sleep(1000); /* Ensure all activity finished */
    EndExclusive(REC_LOCK_SEM);

    /* Clear the file */

    (fptr->upd_ct)++;
    switch (fvar->type) /* !!FVAR_TYPES!! */
    {
      case DYNAMIC_FILE:
        dh_file = fvar->access.dh.dh_file;

        /* Call pre-clearfile trigger function if required */

        if (dh_file->trigger_modes & TRG_PRE_CLEAR) {
          if (!call_trigger(fvar_descr, TRG_PRE_CLEAR, NULL, NULL, op_flags & P_ON_ERROR, FALSE)) {
            process.status = -ER_TRIGGER;
            goto exit_op_clrfile;
          }
        }

        if (!dh_clear(dh_file)) {
          process.status = -dh_err;
          goto exit_op_clrfile;
        }

        /* Call post-clearfile trigger function if required */

        if (dh_file->trigger_modes & TRG_POST_CLEAR) {
          if (!call_trigger(fvar_descr, TRG_POST_CLEAR, NULL, NULL, op_flags & P_ON_ERROR, FALSE)) {
            process.status = -ER_TRIGGER;
            goto exit_op_clrfile;
          }
        }
        break;

      case DIRECTORY_FILE:
        /* Call pre-clearfile trigger function if required (QM4 Fixes item 177) */

        if (DirTrgModes(fvar) & TRG_PRE_CLEAR) {
          if (!call_trigger(fvar_descr, TRG_PRE_CLEAR, NULL, NULL, op_flags & P_ON_ERROR, FALSE)) {
            process.status = -ER_TRIGGER;
            goto exit_op_clrfile;
          }
        }

        strcpy(pathname, (char *)(fptr->pathname));
        if ((dfu = opendir(pathname)) == NULL) {
          process.status = -ER_RNF;
          goto exit_op_clrfile;
        }

        path_len = strlen(pathname);
        if (pathname[path_len - 1] == DS)
          pathname[path_len - 1] = '\0';

        while ((dp = readdir(dfu)) != NULL) {
          if (strcmp(dp->d_name, ".") == 0)
            continue;
          if (strcmp(dp->d_name, "..") == 0)
            continue;
          if (is_dir_header(dp->d_name)) /* the trigger's file is not a record: CLEAR.FILE leaves it */
            continue;
          /* converted to snprintf() -gwb 22Feb20 */
          if (snprintf(subfilename, MAX_PATHNAME_LEN + 1, "%s%c%s", pathname, DS, dp->d_name) >= (MAX_PATHNAME_LEN + 1)) {
            /* TODO: this should also be logged with more detail */
            closedir(dfu);
            k_error("Overflowed path/filename length in op_clrfile()!");
            goto exit_op_clrfile;
          }
          remove(subfilename);
        }
        closedir(dfu); /* (16 Oct 26: the directory was never closed, one descriptor lost per CLEAR.FILE of a directory file) */

        /* Call post-clearfile trigger function if required */

        if (DirTrgModes(fvar) & TRG_POST_CLEAR) {
          if (!call_trigger(fvar_descr, TRG_POST_CLEAR, NULL, NULL, op_flags & P_ON_ERROR, FALSE)) {
            process.status = -ER_TRIGGER;
            goto exit_op_clrfile;
          }
        }
        break;
    }

  exit_op_clrfile:

    if (took_lock) {
      StartExclusive(REC_LOCK_SEM, 55);
      fptr->file_lock = 0; /* Release special lock */
      clear_waiters(-(fvar->file_id));
      EndExclusive(REC_LOCK_SEM);
    } else {
      fptr->file_lock = process.user_no; /* Revert to normal lock */
    }
  }

  k_dismiss();

  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = process.status;

  if (process.status && !(op_flags & P_ON_ERROR)) {
    k_error(sysmsg(1404), -process.status);
  }
}

/* ======================================================================
   op_delete()  -  Delete record                                          */

void op_delete() {
  hsm_io(HSM_DELETE);
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Record id                  | Status 0=ok, <0 = ON ERROR  |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to DELETE.
 */

  DESCRIPTOR *fvar_descr;
  DESCRIPTOR *rid_descr;
  char id[MAX_ID_LEN + 1];
  char mapped_id[2 * MAX_ID_LEN + 1];
  int16_t id_len;
  FILE_VAR *fvar;
  DH_FILE *dh_file;
  u_int16_t op_flags;
  char subfilename[MAX_PATHNAME_LEN + 1];
  char pathname[MAX_PATHNAME_LEN + 1];
  int16_t path_len;
  FILE_ENTRY *fptr;
  bool keep_lock;
  u_int32_t txn_id;
  struct stat statbuf;
  u_char *retry_pc = op_pc; /* 18 Oct 26 slice 3e: where a remote lock that is busy runs this opcode again from, taken before any handler call */

  op_flags = process.op_flags;
  process.op_flags = 0;
  keep_lock = (op_flags & P_ULOCK) != 0;

  process.status = 0;

  /* Get record id */

  rid_descr = e_stack - 1;
  id_len = k_get_c_string(rid_descr, id, sysseg->maxidlen);
  if (id_len <= 0) {
    process.status = -ER_IID;
    goto exit_op_delete; /* We failed to extract the record id */
  }

  /* Find the file variable descriptor */

  fvar_descr = e_stack - 2;
  k_get_file(fvar_descr);
  fvar = fvar_descr->data.fvar;
  ProfFile(PROF_DELETE, fvar); /* the application event profiler (16 Oct 26) */

  /* 17 Oct 26 S.65 slice 3c: a record of a file on another server is not deleted.  Before suspend_updates(), the RDONLY test (it
     logs through FPtr(file_id)), the lock checks and the type switch, which has no arm for it and would report success. */
  if (refuse_net_file(fvar, op_flags, "DELETE", NETG_DELETE))
    goto exit_op_delete;

  txn_id = (fvar->flags & FV_NON_TXN) ? 0 : process.txn_id;

  /* 18 Oct 26 S.65 slice 3e: a write-mode remote file (net_gate() passed it: not read only, not in a transaction, edit gate asked).  Goes
     to the server; no local lock, suspend, read-only or edit test follows.  The empty id was refused above.  The server's plain DELETE
     releases the session's lock on the record, so the tail's unlock_record() has nothing to do for a NET_FILE; DELETE of a record that is
     not there is not an error. */
  if (fvar->type == NET_FILE) {
    int net_st;

    if (id_len > NET_ID_MAX) {
      process.status = -ER_IID;
      goto exit_op_delete;
    }
    switch (net_pre_change_lock(fvar, id, id_len, op_flags, retry_pc)) {
      case NETL_WAIT:
        return;
      case NETL_FAIL:
        goto exit_op_delete;
    }
    process.op_flags = op_flags & P_ON_ERROR;
    net_st = net_delete(fvar, id, id_len, keep_lock); /* the handler runs BASIC: the stack is found by e_stack from here on */
    process.op_flags = 0;
    process.status = net_st;
    goto exit_op_delete;
  }

  if ((sysseg->flags & SSF_SUSPEND) && (txn_id == 0))
    suspend_updates();

  /* Check for read only file */

  if (fvar->flags & FV_RDONLY) {
    process.status = -ER_RDONLY;
    log_permissions_error(fvar);
    goto exit_op_delete;
  }

  {
    int edit_kind = edit_refusal(fvar); /* 17 Oct 26 S.64: the edit gates */

    if (edit_kind != EDIT_NONE) {
      if (!(op_flags & P_ON_ERROR))
        k_error(sysmsg(EDIT_REFUSED_MSG(edit_kind)));
      process.status = -ER_PERM;
      goto exit_op_delete;
    }
  }

  if (pcfg.must_lock || txn_id || (op_flags & P_AUTOLOCK)) {
    if (!check_lock(fvar, id, id_len)) {
      /* $MODE AUTOLOCK: take the lock, waiting for it; it is let go below as a plain DELETE lets go of its own */
      if (!(op_flags & P_AUTOLOCK) || (lock_record(fvar, id, id_len, TRUE, txn_id, FALSE) != 0)) {
        process.status = -ER_NOLOCK;
        goto exit_op_delete;
      }
    }
  }

  /* Delete the record */

  switch (fvar->type) /* !!FVAR_TYPES!! */
  {
    case DYNAMIC_FILE:
      dh_file = fvar->access.dh.dh_file;

      /* Call pre-delete trigger function if required */

      if (dh_file->trigger_modes & TRG_PRE_DELETE) {
        if (!call_trigger(fvar_descr, TRG_PRE_DELETE, rid_descr, NULL, (op_flags & (P_ON_ERROR | P_THEN_ELSE)) != 0, FALSE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_delete;
        }
      }

      if (txn_id != 0) {
        txn_delete(fvar, id, id_len);
      } else {
        if ((!dh_delete(dh_file, id, id_len)) && (dh_err != DHE_RECORD_NOT_FOUND)) {
          process.status = -dh_err;
        }
      }

      /* Call post-delete trigger function if required */

      if (dh_file->trigger_modes & TRG_POST_DELETE) {
        if (!call_trigger(fvar_descr, TRG_POST_DELETE, rid_descr, NULL, (op_flags & (P_ON_ERROR | P_THEN_ELSE)) != 0, FALSE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_delete;
        }
      }

      break;

    case DIRECTORY_FILE:
      fptr = FPtr(fvar->file_id);
      if (!map_t1_id(id, id_len, mapped_id)) {
        process.status = -ER_IID;
        goto exit_op_delete; /* Illegal record id */
      }

      /* Call pre-delete trigger function if required (QM4 Fixes item 177) */

      if (DirTrgModes(fvar) & TRG_PRE_DELETE) {
        if (!call_trigger(fvar_descr, TRG_PRE_DELETE, rid_descr, NULL, (op_flags & (P_ON_ERROR | P_THEN_ELSE)) != 0, FALSE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_delete;
        }
      }

      if (txn_id != 0) {
        txn_delete(fvar, id, id_len);
      } else {
        /* Increment statistics and transaction counters */

        StartExclusive(FILE_TABLE_LOCK, 50);
        NoteStat(deletes);
        fptr->upd_ct++;
        EndExclusive(FILE_TABLE_LOCK);

        strcpy(pathname, (char *)(fptr->pathname));
        path_len = strlen(pathname);
        if (pathname[path_len - 1] == DS)
          pathname[path_len - 1] = '\0'; /* 0214 */
        /* converted to snprintf() -gwb 22Feb20 */
        if (snprintf(subfilename, MAX_PATHNAME_LEN + 1, "%s%c%s", pathname, DS, mapped_id) >= (MAX_PATHNAME_LEN + 1)) {
          /* TODO: this should also be logged with more detail */
          k_error("Overflowed path/filename length in op_delete()!");
          goto exit_op_delete;
        }

        /* 0408 Check that this really is a file, not CON, COMn, LPTn */

        if (!stat(subfilename, &statbuf) && !(statbuf.st_mode & S_IFREG)) {
          process.status = -ER_IID;
          goto exit_op_delete;
        }

        if (remove(subfilename) < 0) /* 0427 */
        {
          process.os_error = errno;
          if (process.os_error != ENOENT) {
            process.status = -ER_PERM;
            log_permissions_error(fvar);
            goto exit_op_delete;
          }
        }
      }

      /* Call post-delete trigger function if required */

      if (DirTrgModes(fvar) & TRG_POST_DELETE) {
        if (!call_trigger(fvar_descr, TRG_POST_DELETE, rid_descr, NULL, (op_flags & (P_ON_ERROR | P_THEN_ELSE)) != 0, FALSE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_delete;
        }
      }
      break;

  }

exit_op_delete:
  k_dismiss();
  k_dismiss();

  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  /* $MODE WRITE.DELETE.THEN.ELSE: a trigger failure under a THEN / ELSE
     clause goes to ELSE, so it is returned as a positive status, which the
     ON ERROR test passes by.  Anything else follows the old rules. */
  if ((process.status == -ER_TRIGGER) && (op_flags & P_THEN_ELSE))
    (e_stack++)->data.value = ER_TRIGGER;
  else
    (e_stack++)->data.value = process.status;

  if (process.status >= 0) {
    /* Release record lock if non-transactional DELETE */
    if (!keep_lock && (txn_id == 0) && (id_len != 0)) {
      unlock_record(fvar, id, id_len);
    }
  } else if (!(op_flags & P_ON_ERROR) && !((process.status == -ER_TRIGGER) && (op_flags & P_THEN_ELSE)))
    k_error(sysmsg(1405), process.status);
}

/* ======================================================================
   op_matread()  -  Read record to matrix                                 */

void op_matread() {
  read_record(TRUE);
}

/* ======================================================================
   op_read()  -  Read record                                              */

void op_read() {
  read_record(FALSE);
}

/* ======================================================================
   op_readv()  -  Read specific field from a record                       */

void op_readv() {
  hsm_io(HSM_READ); /* 14 Oct 26: Hot Spot Monitor counts, sheet 491 */
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Field number               | Status 0=ok, >0 = ELSE      |
     |                             |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  Record id                  |                             |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |-----------------------------|-----------------------------| 
     |  ADDR to target             |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to READV.
 */

  DESCRIPTOR *descr;
  DESCRIPTOR *rid_descr;
  char id[MAX_ID_LEN + 1];
  char mapped_id[2 * MAX_ID_LEN + 1];
  char actual_id[MAX_ID_LEN + 1];
  int32_t field_no;
  char subfilename[MAX_PATHNAME_LEN + 1];
  char pathname[MAX_PATHNAME_LEN + 1];
  int16_t path_len;
  int16_t id_len;
  FILE_VAR *fvar;
  DH_FILE *dh_file;
  u_int16_t op_flags;
  STRING_CHUNK *str;
  int32_t status = 0;
  u_int32_t txn_id;
  u_char *retry_pc = op_pc; /* 18 Oct 26 slice 3e: where a remote lock that is busy runs this opcode again from, taken before any handler call */

  process.status = 0;

  op_flags = process.op_flags;
  process.op_flags = 0;

  /* Get field number */

  descr = e_stack - 1;
  GetInt(descr);
  field_no = descr->data.value;

  /* Find the file variable descriptor */

  descr = e_stack - 3;
  k_get_file(descr);
  fvar = descr->data.fvar;
  ProfFile(PROF_READ, fvar); /* READV: the application event profiler (16 Oct 26) */
  txn_id = (fvar->flags & FV_NON_TXN) ? 0 : process.txn_id;

  if (fvar->type == NET_FILE) {
    /* 17 Oct 26 S.65 slice 3c: a file on another SD server.  Not the recursive _readv, which would READ (and so call the handler)
       and then cut the field in BASIC: net_readv() asks for the field, and for field 0 only whether the record exists.  READVU and
       READVL are refused, nothing is locked on another server in stage 1.  The target is left alone by a refusal and cleared by a
       read that fails, as a local READV does. */
    DESCRIPTOR *net_tgt;
    STRING_CHUNK *net_str = NULL;
    int net_st;

    rid_descr = e_stack - 2;
    id_len = k_get_c_string(rid_descr, id, sysseg->maxidlen);

    /* 18 Oct 26 slice 3e: READVU and READVL are refused here only by net_gate(): a read-mode file variable (as in slice 3c) and a
       transaction.  A plain READV is allowed in every mode, in a transaction too. */
    if ((op_flags & P_REC_LOCKS) && refuse_net_file(fvar, op_flags, (op_flags & P_ULOCK) ? "READVU" : "READVL", NETG_LOCK)) {
      status = process.status;
    } else {
      net_tgt = e_stack - 4;
      do {
        net_tgt = net_tgt->data.d_addr;
      } while (net_tgt->type == ADDR);

      if (!(op_flags & P_PICKREAD)) {
        k_release(net_tgt);
        InitDescr(net_tgt, STRING);
        net_tgt->data.str.saddr = NULL;
      }

      if (id_len <= 0) {
        status = process.status = ER_IID;
      } else {
        /* READVU and READVL of a write-mode file: the lock first, as READU does.  Busy with a LOCKED clause: status ER_LCK, STATUS() the
           holder; busy without: the opcode is set up to run again in 250 ms and we leave before anything is popped. */
        net_st = 0;
        if (op_flags & P_REC_LOCKS) {
          net_st = net_lock_step(fvar, id, id_len, (op_flags & P_ULOCK) != 0, op_flags, retry_pc);
          switch (net_st) {
            case NET_LOCK_HELD:
              net_st = 0;
              break;
            case NET_LOCK_WAIT:
              return;
            case NET_LOCK_LOCKED:
              net_st = ER_LCK;
              break;
            default:
              net_st = (int)process.status; /* an error, already raised unless ON ERROR */
              break;
          }
        }

        if (net_st == 0) {
          process.op_flags = op_flags & P_ON_ERROR;
          net_st = net_readv(fvar, id, id_len, field_no, &net_str);
          process.op_flags = 0;
        }

        /* The handler ran BASIC: take the operands from the stack again, it may have moved */
        net_tgt = e_stack - 4;
        do {
          net_tgt = net_tgt->data.d_addr;
        } while (net_tgt->type == ADDR);

        status = net_st;
        if (net_st != 0) {
          if (net_st != ER_LCK)
            process.status = net_st; /* (for a lock that is busy, STATUS() is the holder net_lock_step() left) */
        } else if (field_no == 0) {
          k_release(net_tgt);
          k_put_string(id, id_len, net_tgt);
        } else {
          k_release(net_tgt);
          InitDescr(net_tgt, STRING);
          net_tgt->data.str.saddr = net_str;
        }
      }
    }

    k_pop(1);    /* Dismiss field number */
    k_dismiss(); /* Record id */
    k_dismiss(); /* File var */
    k_dismiss(); /* Target */
  } else if (field_no != 0) {
    /* Reading a field of a local file */

    /* Push lock flag onto e-stack. This corresponds to the lock bits of
      the op_flags opcode prefix value.                                 */

    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = op_flags;

    k_recurse(pcode_readv, 5);        /* Execute recursive code */
    status = (--e_stack)->data.value; /* 0439 */
  } else {
    /* Get record id */

    rid_descr = e_stack - 2;
    id_len = k_get_c_string(rid_descr, id, sysseg->maxidlen);

    /* Get target descr */

    descr = e_stack - 4;
    do {
      descr = descr->data.d_addr;
    } while (descr->type == ADDR);

    if (!(op_flags & P_PICKREAD)) {
      k_release(descr);
      InitDescr(descr, STRING);
      descr->data.str.saddr = NULL;
    }

    if (id_len <= 0) {
      status = process.status = ER_IID;
    } else {
      {
        if (fvar->type == DIRECTORY_FILE) {
          if (!map_t1_id(id, id_len, mapped_id)) {
            status = process.status = ER_IID;
            goto exit_op_readv; /* Illegal record id */
          }
        }

        /* Aquire lock if necessary */

        if (op_flags & P_REC_LOCKS) /* READL or READU */
        {
          process.status = lock_record(fvar, id, id_len, (op_flags & P_ULOCK) != 0, txn_id, (op_flags & P_LOCKED) != 0);
          switch (process.status) {
            case 0: /* Got the lock */
              break;

            case -3: /* This process is at its MAXRLOCK limit: an error to take or abort on, not a lock to wait for */
              status = process.status = -ER_MAXRLOCK;
              goto exit_op_readv;

            case -2: /* Deadlock detected */
              if (sysseg->deadlock)
                k_deadlock();
              /* **** FALL THROUGH **** */
              /* Modified by Composer AI - 2026/06/10.
                 Fall-through is intentional (see comment above); make
                 it explicit for the compiler. */
              __attribute__((fallthrough));
              /* -------------------- */

            case -1:                   /* Lock table is full */
            default:                   /* Conflicting lock is held by another user */
              if (op_flags & P_LOCKED) /* LOCKED clause present */
              {
                status = ER_LCK;
                goto exit_op_readv;
              }
              if (my_uptr->events)
                process_events();
              process.op_flags = op_flags;
              pc = op_pc;
              lock_beep();
              Sleep(250);
              return;
          }
        }

        /* Read the record */

        if (txn_id) {
          switch (txn_read(fvar, id, id_len, actual_id, &str)) {
            case TXC_FOUND: /* Found the record */
              goto exit_op_readv;

            case TXC_DELETED: /* Reference found as deleted record */
              status = process.status = ER_RNF;
              goto exit_op_readv;
          }
        }

        switch (fvar->type) /* !!FVAR_TYPES!! */
        {
          case DYNAMIC_FILE:
            dh_file = fvar->access.dh.dh_file;
            if (!dh_exists(dh_file, id, id_len)) {
              if (dh_err == DHE_RECORD_NOT_FOUND)
                process.status = ER_RNF;
              else
                process.status = -dh_err;
              status = process.status;
            }
            break;

          case DIRECTORY_FILE:
            strcpy(pathname, (char *)(FPtr(fvar->file_id)->pathname));
            path_len = strlen(pathname);
            if (pathname[path_len - 1] == DS)
              pathname[path_len - 1] = '\0'; /* 0214 */
            /* converted to snprintf() -gwb 22Feb20 */
            if (snprintf(subfilename, MAX_PATHNAME_LEN + 1, "%s%c%s", pathname, DS, mapped_id) >= (MAX_PATHNAME_LEN + 1)) {
              /* TODO: this should also be logged with more detail */
              k_error("Overflowed path/filename length in op_readv()!");
              goto exit_op_readv;
            }
            if ((mapped_id[0] == '\0') || access(subfilename, 0)) {
              status = process.status = ER_RNF;
            }
            break;
        }
      }
    }

    if ((status == 0) && (field_no == 0)) {
      k_release(descr);
      k_put_string(id, id_len, descr);
    }

  exit_op_readv:
    k_pop(1);    /* Dismiss field number */
    k_dismiss(); /* Record id */
    k_dismiss(); /* File var */
    k_dismiss(); /* Target */
  }

  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;

  if ((status < 0) && !(op_flags & P_ON_ERROR)) {
    if (process.status == -ER_MAXRLOCK)
      k_error(sysmsg(12167));
    k_error(sysmsg(1406), -process.status, process.os_error);
  }
}

/* ======================================================================
   op_mapmarks()  -  Perform mark mapping in directory files?             */

void op_mapmarks() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  New status                 |                             |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |=============================|=============================|

     This operation is ignored if not a directory file.                    
 */

  DESCRIPTOR *descr;
  FILE_VAR *fvar;
  bool state;

  /* Get file variable */

  descr = e_stack - 2;
  k_get_file(descr);
  fvar = descr->data.fvar;

  /* Get new setting */

  descr = e_stack - 1;
  GetInt(descr);
  state = (descr->data.value != 0);

  switch (fvar->type) {
    case DIRECTORY_FILE:
      fvar->access.dir.mark_mapping = state;
      break;

  }

  k_pop(1);
  k_dismiss();
}

/* ======================================================================
   op_write()  -  Write record                                            */

void op_write() {
  hsm_io(HSM_WRITE);
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Record id                  | Status 0=ok, <0 = ON ERROR  |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |-----------------------------|-----------------------------| 
     |  Record data to write       |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to WRITE.
 */

  DESCRIPTOR *fvar_descr;
  DESCRIPTOR *rid_descr;
  DESCRIPTOR *src_descr;
  char id[MAX_ID_LEN + 1];
  char lock_id[MAX_ID_LEN + 1];
  char mapped_id[2 * MAX_ID_LEN + 1];
  int16_t id_len;
  FILE_VAR *fvar;
  DH_FILE *dh_file;
  STRING_CHUNK *str;
  u_int16_t op_flags;
  bool keep_lock;
  u_int32_t txn_id;
  bool coll_file;                 /* A data collection file */
  COLL_HEADER *coll_keep = NULL;  /* The collection being written, while src_descr holds its text */
  u_char *retry_pc = op_pc;       /* 18 Oct 26 slice 3e: where a remote lock that is busy runs this opcode again from, taken before any handler call */

  op_flags = process.op_flags;
  process.op_flags = 0;
  keep_lock = (op_flags & P_ULOCK) != 0;

  process.status = 0;

  rid_descr = e_stack - 1;

  /* Find the file variable descriptor */

  fvar_descr = e_stack - 2;
  k_get_file(fvar_descr);
  fvar = fvar_descr->data.fvar;
  ProfFile(PROF_WRITE, fvar); /* the application event profiler (16 Oct 26) */

  txn_id = (fvar->flags & FV_NON_TXN) ? 0 : process.txn_id;

  /* 17 Oct 26 S.65 slice 3c: a record is not written to a file on another server.  First, before the edit gates, a CREATING.SEQKEY
     id, the lock and transaction code, the read-only branches (they log through FPtr(file_id)) and the type switch, which has no
     arm for it and would report success. */
  if (refuse_net_file(fvar, op_flags, keep_lock ? "WRITEU" : "WRITE", NETG_WRITE))
    goto exit_op_write;

  /* 18 Oct 26 S.65 slice 3e: a record is written to a write-mode remote file (net_gate() passed it: not read only, not in a transaction,
     not CREATING.SEQKEY, edit gate asked).  The record goes down as the chain it is.  No local suspend, read-only, trigger or lock test
     follows for it.  The server's plain WRITE lets go of the session's lock on the record, WRITEU keeps it, so the tail's unlock_record()
     (which does nothing for a NET_FILE) is not needed.  A COLL value is made a string by k_get_string() as for any file that is not a
     data collection file. */
  if (fvar->type == NET_FILE) {
    int net_st;

    id_len = k_get_c_string(rid_descr, id, sysseg->maxidlen);
    src_descr = e_stack - 3;
    if (src_descr->type == ADDR)
      k_get_value(src_descr);
    k_get_string(src_descr);

    if (!valid_id(id, id_len) || (id_len > NET_ID_MAX)) {
      process.status = -ER_IID;
      goto exit_op_write;
    }
    memcpy(lock_id, id, id_len);

    switch (net_pre_change_lock(fvar, id, id_len, op_flags, retry_pc)) {
      case NETL_WAIT:
        return;
      case NETL_FAIL:
        goto exit_op_write;
    }

    process.op_flags = op_flags & P_ON_ERROR;
    net_st = net_write(fvar, id, id_len, src_descr->data.str.saddr, keep_lock); /* the handler runs BASIC: the stack is found by e_stack from here on */
    process.op_flags = 0;
    process.status = net_st;
    goto exit_op_write;
  }

  {
    /* 17 Oct 26 S.64: the edit gates.  Before anything is taken from the file. */
    int edit_kind = edit_refusal(fvar);

    if (edit_kind != EDIT_NONE) {
      if (!(op_flags & P_ON_ERROR))
        k_error(sysmsg(EDIT_REFUSED_MSG(edit_kind)));
      process.status = -ER_PERM;
      goto exit_op_write;
    }
  }

  if (op_flags & P_SEQKEY) {
    /* 15 Oct 26 dm - WRITE ... CREATING.SEQKEY id.var.  The operand where the record id would be is the ADDRESS of the program's
       id variable.  The id is the file's next sequential number, taken from the counter in the file header; it is put in the
       variable, an update lock is taken on it (nobody can hold it, it is new, but a transaction and MUSTLOCK demand the lock and
       a WRITEU keeps it), and the write goes on as any other.  In a transaction the id is taken now, not at the commit.  Only a
       hashed file has the counter.                                                                                       */
    DESCRIPTOR* id_target;
    STRING_CHUNK* id_str = NULL;
    int32_t seq_id;

    if (fvar->type != DYNAMIC_FILE) {
      process.status = -ER_NDYN;
      goto exit_op_write;
    }

    /* 15 Oct 26 dm - audit.  Taking an id writes the file's header, so the two refusals that cost nothing are made BEFORE it:
       a read-only file variable is refused with its counter as it was (it was moved on, and the write then refused), and a
       SUSPEND (sd -suspend) holds the write until sd -resume without the header having changed on disk meanwhile. */
    if ((sysseg->flags & SSF_SUSPEND) && (txn_id == 0))
      suspend_updates();

    if (fvar->flags & FV_RDONLY) {
      process.status = -ER_RDONLY;
      log_permissions_error(fvar);
      goto exit_op_write;
    }

    /* 15 Oct 26 dm - an id that already names a record is skipped, so that records written some other way (a copy, a load, a
       program that picked its own number) are not overwritten.  openQM does not look; the owner chose to (15 Oct 2026).  Only
       the committed file is looked at: in a transaction an id taken earlier by this process is never given out twice anyway. */
    for (;;) {
      seq_id = dh_seq_key(fvar->access.dh.dh_file, 0, 0);
      if (seq_id < 0) {
        process.status = -ER_IOE;
        goto exit_op_write;
      }
      id_len = (int16_t)snprintf(id, sizeof(id), "%d", (int)seq_id);
      if (!dh_exists(fvar->access.dh.dh_file, id, id_len)) {
        if (dh_err == DHE_RECORD_NOT_FOUND)
          break;
        process.status = -dh_err;
        goto exit_op_write;
      }
    }

    id_target = rid_descr;
    while (id_target->type == ADDR)
      id_target = id_target->data.d_addr;
    k_release(id_target);
    ts_init(&id_str, 16);
    ts_printf("%d", (int)seq_id);
    ts_terminate();
    InitDescr(id_target, STRING);
    id_target->data.str.saddr = id_str;
    rid_descr = id_target; /* what the trigger and the id checks below are given: the id as a string */

    memcpy(lock_id, id, id_len);
    if (lock_record(fvar, lock_id, id_len, TRUE, txn_id, FALSE) != 0) {
      process.status = -ER_NOLOCK;
      goto exit_op_write;
    }
  } else {
    /* Get record id */

    id_len = k_get_c_string(rid_descr, id, sysseg->maxidlen);
  }

  if ((sysseg->flags & SSF_SUSPEND) && (txn_id == 0))
    suspend_updates();

  /* Get string descr.  A data collection file takes a collection as it is and
     turns it to JSON text just before the write (13 Oct 26). */

  src_descr = e_stack - 3;
  coll_file = (fvar->type == DYNAMIC_FILE) && (fvar->access.dh.dh_file->flags & DHF_COLLECTION);
  if (src_descr->type == ADDR)
    k_get_value(src_descr);
  if (!(coll_file && src_descr->type == COLL))
    k_get_string(src_descr);

  if (!valid_id(id, id_len)) {
    process.status = -ER_IID;
    goto exit_op_write; /* We failed to extract the record id */
  }

  /* Check for read only file */

  if (fvar->flags & FV_RDONLY) {
    process.status = -ER_RDONLY;
    log_permissions_error(fvar);
    goto exit_op_write;
  }

  memcpy(lock_id, id, id_len);

  if (pcfg.must_lock || (txn_id != 0) || (op_flags & P_AUTOLOCK)) {
    if (!check_lock(fvar, lock_id, id_len)) {
      /* $MODE AUTOLOCK: take the lock, waiting for it; it is let go below as a plain WRITE lets go of its own */
      if (!(op_flags & P_AUTOLOCK) || (lock_record(fvar, lock_id, id_len, TRUE, txn_id, FALSE) != 0)) {
        process.status = -ER_NOLOCK;
        goto exit_op_write;
      }
    }
  }

  /* Write the record */

  switch (fvar->type) /* !!FVAR_TYPES!! */
  {
    case DYNAMIC_FILE:
      dh_file = fvar->access.dh.dh_file;

      /* 11 Oct 26 dm - A data collection file: text is made into its collection BEFORE any trigger
         sees it, so a trigger is always given a collection whatever the program wrote (it was given
         the text when the program wrote text).  Text that is not a JSON object or array is refused
         here, with the same status as before, but ahead of the trigger.  The file then holds the
         compact JSON of the collection. */

      if (coll_file && (src_descr->type != COLL)) {
        if (!coll_record_in(src_descr)) {
          process.status = -ER_PARSE_ERROR;
          goto exit_op_write;
        }
      }

      /* Call pre-write trigger function if required */

      if (dh_file->trigger_modes & TRG_PRE_WRITE) {
        if (!call_trigger(fvar_descr, TRG_PRE_WRITE, rid_descr, src_descr, (op_flags & (P_ON_ERROR | P_THEN_ELSE)) != 0, TRUE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_write;
        }
      }

      if (coll_file) {
        if (src_descr->type == COLL) {
          /* Hold the collection for the post-write trigger while the descriptor
             carries its JSON text for the write */
          coll_keep = src_descr->data.coll;
          coll_keep->ref_ct++;
          if (!coll_record_text(src_descr)) {
            process.status = -ER_BUILD_ERROR;
            goto exit_op_write;
          }
        } else if (!coll_record_text(src_descr)) {
          process.status = -ER_PARSE_ERROR; /* Text that is not a JSON object or array */
          goto exit_op_write;
        }
      }

      str = src_descr->data.str.saddr;
      if (txn_id != 0) {
        if (!txn_write(fvar, id, id_len, str))
          goto exit_op_write;
      } else {
        if (!dh_write(dh_file, id, id_len, str)) {
          process.status = -dh_err;
          goto exit_op_write;
        }
      }

      if (coll_keep != NULL) {
        k_release(src_descr);
        InitDescr(src_descr, COLL);
        src_descr->data.coll = coll_keep;
        coll_keep = NULL;
      } else if (coll_file && (dh_file->trigger_modes & TRG_POST_WRITE)) {
        /* A pre-write trigger put text in the place of the collection: the post-write trigger is given
           the collection made from it (the text was accepted above, so this succeeds) */
        (void)coll_record_in(src_descr);
      }

      /* Call post-write trigger function if required */

      if (dh_file->trigger_modes & TRG_POST_WRITE) {
        if (!call_trigger(fvar_descr, TRG_POST_WRITE, rid_descr, src_descr, (op_flags & (P_ON_ERROR | P_THEN_ELSE)) != 0, FALSE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_write;
        }
      }
      break;

    case DIRECTORY_FILE:
      if (!map_t1_id(id, id_len, mapped_id)) {
        process.status = -ER_IID;
        if (!(op_flags & P_ON_ERROR))
          k_illegal_id(rid_descr);
        goto exit_op_write; /* Illegal record id */
      }

      /* Call pre-write trigger function if required (QM4 Fixes item 177).  The data is taken AFTER it: the trigger may change it. */

      if (DirTrgModes(fvar) & TRG_PRE_WRITE) {
        if (!call_trigger(fvar_descr, TRG_PRE_WRITE, rid_descr, src_descr, (op_flags & (P_ON_ERROR | P_THEN_ELSE)) != 0, TRUE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_write;
        }
      }

      str = src_descr->data.str.saddr;

      if (txn_id != 0) {
        if (!txn_write(fvar, id, id_len, str))
          goto exit_op_write;
      } else {
        if (!dir_write(fvar, mapped_id, str))
          goto exit_op_write;
      }

      /* Call post-write trigger function if required */

      if (DirTrgModes(fvar) & TRG_POST_WRITE) {
        if (!call_trigger(fvar_descr, TRG_POST_WRITE, rid_descr, src_descr, (op_flags & (P_ON_ERROR | P_THEN_ELSE)) != 0, FALSE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_write;
        }
      }

      break;

  }

exit_op_write:

  if (coll_keep != NULL)
    coll_deref(coll_keep);

  k_dismiss();
  k_dismiss();
  k_dismiss();

  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  /* $MODE WRITE.DELETE.THEN.ELSE: as for DELETE, a trigger failure under a
     THEN / ELSE clause is a positive status and takes ELSE. */
  if ((process.status == -ER_TRIGGER) && (op_flags & P_THEN_ELSE))
    (e_stack++)->data.value = ER_TRIGGER;
  else
    (e_stack++)->data.value = process.status;

  if (process.status >= 0) {
    /* Release record lock if non-transactional WRITE */

    if (!keep_lock && (txn_id == 0)) {
      unlock_record(fvar, lock_id, id_len);
    }
  } else if (!(op_flags & P_ON_ERROR) && !((process.status == -ER_TRIGGER) && (op_flags & P_THEN_ELSE))) {
/* 31 Aug 26 Windows port - ER_NOLOCK GETS ITS OWN MESSAGE.  PRE_RELEASE_FIXES
   12 / UPSTREAM_FIXES 20.  1407 ends "(Possible full disk?)", and every failure
   arriving here rendered through it - so a WRITE refused at :776 because the
   caller held no lock told the user to go and look at the disk.  The disk was
   never touched: :776 is reached BEFORE the switch that writes anything, so
   nothing was written and the stored record is unchanged.

   IT IS THE COMMONEST OF THEM, WHICH IS WHY IT IS THE ONE SPLIT OUT.  The test
   at :775 fires whenever MUSTLOCK=1 or the write is inside a transaction, and
   a transaction is the ordinary case in application code.

   THE OTHER STATUSES ARRIVING HERE STILL USE 1407 AND ARE STILL WRONG ABOUT
   THE DISK - ER_RDONLY, ER_IID and ER_TRIGGER among them - but each wants its
   own text rather than a shared one, and ER_RDONLY already logs separately via
   log_permissions_error().  Left deliberately, and said out loud here so the
   next reader knows it was seen rather than missed.                        */
    if (process.status == -ER_NOLOCK)
      k_error(sysmsg(10151), -process.status);
    else if ((process.status == -ER_NDYN) && (op_flags & P_SEQKEY))
      k_error(sysmsg(12353)); /* CREATING.SEQKEY needs a hashed file */
    else
      k_error(sysmsg(1407), -process.status, process.os_error);
  }
}

/* ======================================================================
   op_writev()  -  Write specific field to a record                       */

void op_writev() {
  hsm_io(HSM_WRITE);
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Field number               | Status 0=ok, >0 = ELSE      |
     |                             |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  Record id                  |                             |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |-----------------------------|-----------------------------| 
     |  Field value                |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to WRITEV.
 */

  u_int16_t op_flags;

  op_flags = process.op_flags;
  process.op_flags = 0;

  process.status = 0;

  if (prof_mask & PROF_WRITE) /* WRITEV: the application event profiler (16 Oct 26); the file variable is third from the top */
  {
    DESCRIPTOR* prof_d = e_stack - 3;

    while (prof_d->type == ADDR)
      prof_d = prof_d->data.d_addr;
    if (prof_d->type == FILE_REF)
      ProfFile(PROF_WRITE, prof_d->data.fvar);
  }

  /* 17 Oct 26 S.64: the edit gates.  Tested HERE, not left to op_write(): the recursive pcode below is $internal, so by the time it
     writes, the caller's program flags are gone (Linux Solo's voc_write_refused() does the same, LSOLO 6).  A refusal without
     ON ERROR is an error with the reason; with it, the four operands are dropped and the status is -ER_PERM.                */
  {
    DESCRIPTOR *wv_fvar = e_stack - 3;
    int edit_kind;

    k_get_file(wv_fvar);

    /* 17 Oct 26 S.65 slice 3c: a field is not written to a record of a file on another server.  Here, before the recursive _writev,
       which would READ the record from the server and then WRITE.
       18 Oct 26 slice 3e: a write-mode remote file passes net_gate() here (the caller's program flags are tested, not the $internal
       pcode's) and the recursive _writev goes on: its READ and its WRITE or WRITEU are ordinary statements of a NET_FILE. */
    if (refuse_net_file(wv_fvar->data.fvar, op_flags, (op_flags & P_ULOCK) ? "WRITEVU" : "WRITEV", NETG_WRITE)) {
      k_dismiss();
      k_dismiss();
      k_dismiss();
      k_dismiss();
      goto exit_op_writev;
    }

    edit_kind = edit_refusal(wv_fvar->data.fvar);
    if (edit_kind != EDIT_NONE) {
      if (!(op_flags & P_ON_ERROR))
        k_error(sysmsg(EDIT_REFUSED_MSG(edit_kind)));
      process.status = -ER_PERM;
      k_dismiss();
      k_dismiss();
      k_dismiss();
      k_dismiss();
      goto exit_op_writev;
    }
  }

  /* Push lock flag onto e-stack; zero for WRITEV, non-zero for WRITEVU */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = op_flags & P_ULOCK;

  k_recurse(pcode_writev, 5); /* Execute recursive code */

exit_op_writev:

  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = process.status;

  if ((process.status < 0) && !(op_flags & P_ON_ERROR)) {
    k_error(sysmsg(1408), -process.status);
  }
}

/* ======================================================================
   read_record()  -  Read a record                                        */

Private void read_record(bool matread) {
  hsm_io(HSM_READ);
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Record id                  | Status 0=ok, >0 = ELSE      |
     |                             |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |-----------------------------|-----------------------------| 
     |  ADDR to target             |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to READ.
 */

  DESCRIPTOR *fvar_descr;
  DESCRIPTOR *rid_descr;
  DESCRIPTOR *tgt_descr;
  char id[MAX_ID_LEN + 1];
  char mapped_id[2 * MAX_ID_LEN + 1];
  /* initializing actual_id to clear a valgrind warning. 06feb22 -gwb */
  char actual_id[MAX_ID_LEN + 1] = {0}; /* Returned as recorded in file */
  int16_t id_len;
  char pathname[MAX_PATHNAME_LEN + 1];
  int16_t path_len;
  char record_path[MAX_PATHNAME_LEN + 1];
  FILE_VAR *fvar;
  DH_FILE *dh_file;
  int32_t bytes;
  u_int16_t op_flags;
  OSFILE t1_fu;
  int32_t remaining_bytes;
  int64_t remaining_bytes64;
  int16_t n;
  /* 24 Aug 26 Windows port - a CR seen as the last byte of a chunk, whose LF
     (if any) will be the first byte of the next one.  PROJECT_STATUS 7 step
     16 (a).  18 Oct 26: it is t1u.pending_cr now (Linux f0af637 item 452). */
  int16_t status;
  DESCRIPTOR temp_descr; /* Temporary string used by MATREAD */
  DESCRIPTOR *str_descr; /* Descriptor into which to perform string read */
  STRING_CHUNK *str;
  u_int32_t txn_id;
  /* 24 Aug 26 Windows port - p and q went with the memchr mapping loop the
     CRLF change replaced; the compactor declares its own src/dst. */
  struct stat statbuf;
  T1_UNMAP t1u; /* line terminator mode of a directory file, and what is carried from chunk to chunk */
  u_char *retry_pc = op_pc; /* 18 Oct 26 slice 3e: where a remote lock that is busy runs this opcode again from, taken before any handler call */

  op_flags = process.op_flags;
  process.op_flags = 0;

  status = 0;

  t1_fu = INVALID_FILE_HANDLE;

  /* Get record id */

  rid_descr = e_stack - 1;
  id_len = k_get_c_string(rid_descr, id, sysseg->maxidlen);

  /* Find the file variable descriptor */

  fvar_descr = e_stack - 2;
  k_get_file(fvar_descr);
  fvar = fvar_descr->data.fvar;
  ProfFile(PROF_READ, fvar); /* READ, READU, READL and MATREAD: the application event profiler (16 Oct 26) */
  /* A NET_FILE (S.65 slice 3c) has no transaction cache and no file table entry: txn_read() would read FPtr(-1) */
  txn_id = ((fvar->flags & FV_NON_TXN) || (fvar->type == NET_FILE)) ? 0 : process.txn_id;

  /* Get target descr */

  tgt_descr = e_stack - 3;
  do {
    tgt_descr = tgt_descr->data.d_addr;
  } while (tgt_descr->type == ADDR);

  if (matread) {
    InitDescr(&temp_descr, UNASSIGNED);
    str_descr = &temp_descr;

    /* Check target is a matrix */
    if ((tgt_descr->type != ARRAY) && (tgt_descr->type != PMATRIX)) /* 0369 */
    {
      k_error(sysmsg(1232));
    }
  } else {
    str_descr = tgt_descr;
  }

  /* 17 Oct 26 S.65 slice 3c: READU, READL, MATREADU and MATREADL of a file on another server are refused, before the lock code
     below, which writes the lock table with file_id -1.  The target is left as it was.  A plain READ and MATREAD are served by
     the NET_FILE case of the switch further down.
     18 Oct 26 slice 3e: refused here still for a read-mode file variable and in a transaction (net_gate()); for a write-mode one the
     flow goes on, and the lock block below asks the server for the lock (net_lock_step()) in place of lock_record(). */
  if ((fvar->type == NET_FILE) && (op_flags & P_REC_LOCKS)) {
    if (refuse_net_file(fvar, op_flags, matread ? ((op_flags & P_ULOCK) ? "MATREADU" : "MATREADL") : ((op_flags & P_ULOCK) ? "READU" : "READL"), NETG_LOCK)) {
      status = (int16_t)process.status;
      goto exit_op_read;
    }
  }

  /* 1.4-3  Moved to before all possible exit paths */

  if (!(op_flags & P_PICKREAD)) {
    k_release(str_descr);
    InitDescr(str_descr, STRING);
    str_descr->data.str.saddr = NULL;
  }

  if (id_len <= 0) {
    process.status = ER_IID;
    status = (int16_t)process.status;
    goto exit_op_read; /* We failed to extract the record id */
  }

  {
    /* Aquire lock if necessary */

    if ((op_flags & P_REC_LOCKS) && (fvar->type == NET_FILE)) {
      /* 18 Oct 26 slice 3e: the lock of a write-mode remote file is the server's.  Busy with a LOCKED clause: that branch, STATUS() the
         holder.  Busy without one: net_lock_step() has set this opcode up to run again in 250 ms and we leave at once, the operands
         still on the stack.  The handler ran BASIC, so the operands are found again before anything below uses them. */
      int net_lock_st = net_lock_step(fvar, id, id_len, (op_flags & P_ULOCK) != 0, op_flags, retry_pc);

      net_reload_read_operands(&rid_descr, &fvar_descr, &tgt_descr);
      if (!matread)
        str_descr = tgt_descr;
      switch (net_lock_st) {
        case NET_LOCK_HELD:
          break;
        case NET_LOCK_WAIT:
          return;
        case NET_LOCK_LOCKED:
          status = ER_LCK;
          goto exit_op_read;
        default:
          status = (int16_t)process.status;
          goto exit_op_read;
      }
    } else if (op_flags & P_REC_LOCKS) /* READL or READU */
    {
      process.status = lock_record(fvar, id, id_len, (op_flags & P_ULOCK) != 0, txn_id, (op_flags & P_LOCKED) != 0);
      switch (process.status) {
        case 0: /* Got the lock */
          break;

        case -3: /* This process is at its MAXRLOCK limit: an error to take or abort on, not a lock to wait for */
          status = process.status = -ER_MAXRLOCK;
          goto exit_op_read;

        case -2: /* Deadlock detected */
          if (sysseg->deadlock)
            k_deadlock();
          /* **** FALL THROUGH **** */
          /* Modified by Composer AI - 2026/06/10.
             Fall-through is intentional (see comment above); make it
             explicit for the compiler. */
          __attribute__((fallthrough));
          /* -------------------- */

        case -1:                   /* Lock table is full */
        default:                   /* Conflicting lock is held by another user */
          if (op_flags & P_LOCKED) /* LOCKED clause present */
          {
            status = ER_LCK;
            goto exit_op_read;
          }
          pc = op_pc;
          process.op_flags = op_flags;
          if (my_uptr->events)
            process_events();
          lock_beep();
          Sleep(250);
          return;
      }
    }

    memcpy(actual_id, id, id_len); /* For all paths that don't update it */

    /* If we're in a transaction, we must scan the transaction cache for a
      possible reference to this record.                                   */

    if (txn_id) {
      switch (txn_read(fvar, id, id_len, actual_id, &str)) {
        case TXC_FOUND: /* Found the record */
          /* For a directory file, the cached record is in internal format 
             so we do not need to apply mark mapping.                      */

          if ((op_flags & P_PICKREAD)) {
            k_release(str_descr);
            InitDescr(str_descr, STRING);
          }

          str_descr->data.str.saddr = str;
          if (str != NULL)
            str->ref_ct++;

          /* A data collection file gives the record as a collection (13 Oct 26) */
          if (fvar->type == DYNAMIC_FILE && (fvar->access.dh.dh_file->flags & DHF_COLLECTION)) {
            if (matread)
              k_error(sysmsg(12132));
            if (!coll_record_in(str_descr))
              status = (int16_t)(-(process.status = ER_PARSE_ERROR));
          }
          goto exit_op_read;

        case TXC_DELETED: /* Reference found as deleted record */
          status = (int16_t)(process.status = ER_RNF);
          goto exit_op_read;
      }
    }
  }

  switch (fvar->type) /* !!FVAR_TYPES!! */
  {
    case DYNAMIC_FILE:
      dh_file = fvar->access.dh.dh_file;
      if (matread && (dh_file->flags & DHF_COLLECTION))
        k_error(sysmsg(12132)); /* MATREAD makes no sense for a data collection */
      str = dh_read(dh_file, id, id_len, actual_id);
      switch (dh_err) {
        case 0:
          if ((op_flags & P_PICKREAD)) {
            k_release(str_descr);
            InitDescr(str_descr, STRING);
          }
          str_descr->data.str.saddr = str;

          /* A data collection file gives the record as a collection (13 Oct 26),
             and so does its read trigger. */
          if ((dh_file->flags & DHF_COLLECTION) && !coll_record_in(str_descr)) {
            status = (int16_t)(-(process.status = ER_PARSE_ERROR));
            goto exit_op_read;
          }

          /* Call read trigger function if required */

          if (dh_file->trigger_modes & TRG_READ) {
            if (!call_trigger(fvar_descr, TRG_READ, rid_descr, str_descr, (op_flags & P_ON_ERROR), TRUE)) {
              process.status = -ER_TRIGGER;
              goto exit_op_read;
            }
          }
          break;

        case DHE_RECORD_NOT_FOUND:
          status = (int16_t)(process.status = ER_RNF);
          break;

        default:
          status = (int16_t)(-(process.status = dh_err));
          goto exit_op_read;
      }
      break;

    case DIRECTORY_FILE:
      if (!map_t1_id(id, id_len, mapped_id)) {
        process.status = ER_IID;
        goto exit_op_read; /* Illegal record id */
      }

      /* Increment statistics counter */

      StartExclusive(FILE_TABLE_LOCK, 49);
      NoteStat(reads);
      EndExclusive(FILE_TABLE_LOCK);

      strcpy(pathname, (char *)(FPtr(fvar->file_id)->pathname));
      path_len = strlen(pathname);
      if (pathname[path_len - 1] == DS)
        pathname[path_len - 1] = '\0'; /* 0214 */
      /* converted to snprintf() -gwb 22Feb20 */
      if (snprintf(record_path, MAX_PATHNAME_LEN + 1, "%s%c%s", pathname, DS, mapped_id) >= (MAX_PATHNAME_LEN + 1)) {
        /* TODO: this should also be logged with more detail */
        k_error("Overflowed path/filename length in read_record()!");
        goto exit_op_read;
      }

      t1_fu = dio_open(record_path, DIO_READ);

      if (!ValidFileHandle(t1_fu)) {
        status = (int16_t)(process.status = ER_RNF);
        goto exit_op_read;
      }

      /* 0408 Check that this really is a file, not CON, COMn, LPTn */

      if (fstat(t1_fu, &statbuf) || !(statbuf.st_mode & S_IFREG)) {
        status = process.status = ER_IID;
        goto exit_op_read;
      }

      /* Find file size and initialise target string */
/* 020240701 mab Max String Size test */
      remaining_bytes64 = filelength64(t1_fu);

      if (remaining_bytes64 > MAX_STRING_SIZE) {
        status = process.status = ER_MAX_STRING;      
        goto exit_op_read;
      }
/* now safe to cast to 32 bits */      
      remaining_bytes = (int32_t)remaining_bytes64;

      if ((op_flags & P_PICKREAD)) {
        k_release(str_descr);
        InitDescr(str_descr, STRING);
      }
      str_descr->data.str.saddr = NULL;
      ts_init(&(str_descr->data.str.saddr), remaining_bytes);

      /* Create a buffer in the virtual memory area */

      t1_buffer_alloc(remaining_bytes);

      t1u.mode = fvar->access.dir.crlf;
      t1u.pending_cr = FALSE;
      t1u.hold_fm = FALSE;

      while (remaining_bytes > 0) {
        bytes = min(remaining_bytes, t1_buffer_size);

        if (Read(t1_fu, t1_buffer, bytes) < 0) {
          status = (int16_t)(-(process.status = ER_IOE));
          process.os_error = OSError;
          goto exit_op_read;
        }

        remaining_bytes -= bytes;

        /* 4 Sep 26 Windows port - THE CONVERSION MOVED TO t1_unmap_chunk() SO
           THAT dir_read() USES THE SAME COPY.  PRE_RELEASE_FIXES 102.
           18 Oct 26 - from Linux f0af637 (16 Oct 26, item 452): it is t1_unmap_and_copy() now, which knows the line
           terminator mode of the file; image mode (no mark mapping) is in there too. */
        t1_unmap_and_copy(fvar, &t1u, t1_buffer, bytes, (remaining_bytes == 0));
      }

      /* A CR that ended the record with no LF after it is DATA, and would
         otherwise be swallowed by having been deferred. */
      if (t1u.pending_cr) {
        char cr = '\r';
        ts_copy(&cr, 1);
        t1u.pending_cr = FALSE;
      }

      (void)ts_terminate();

      /* Call read trigger function if required (QM4 Fixes item 177) */

      if (DirTrgModes(fvar) & TRG_READ) {
        if (!call_trigger(fvar_descr, TRG_READ, rid_descr, str_descr, (op_flags & P_ON_ERROR), TRUE)) {
          process.status = -ER_TRIGGER;
          goto exit_op_read;
        }
      }
      break;

    case NET_FILE: {
      /* 17 Oct 26 S.65 slice 3c: a file on another SD server (the locking forms were refused above).  net_read() runs the handler:
         0 is the record in net_rec, a positive status takes the ELSE branch, a negative one is an error, which net_read() has
         raised itself unless the statement has ON ERROR.  Like a local failure, a failed read leaves the target a null string.
         The handler ran BASIC, so the descriptors on the e-stack are found again. */
      STRING_CHUNK *net_rec = NULL;
      int net_st;

      process.op_flags = op_flags & P_ON_ERROR;
      net_st = net_read(fvar, id, id_len, &net_rec);
      process.op_flags = 0;

      net_reload_read_operands(&rid_descr, &fvar_descr, &tgt_descr);
      if (!matread)
        str_descr = tgt_descr;

      if (net_st == 0) {
        if ((op_flags & P_PICKREAD)) {
          k_release(str_descr);
          InitDescr(str_descr, STRING);
        }
        str_descr->data.str.saddr = net_rec;
      } else {
        status = (int16_t)(process.status = net_st);
      }
      break;
    }
  }

exit_op_read:

  if (ValidFileHandle(t1_fu))
    CloseFile(t1_fu);
  if (t1_buffer != NULL)
    t1_buffer_free();

  k_dismiss(); /* Record id */
  k_dismiss(); /* File var */

  if (matread) {
    if (status) {
      k_release(str_descr); /* Cast off string */
      k_dismiss();          /* ADDR to target */
    } else {
      *(e_stack++) = temp_descr; /* Move temporary string to e-stack */
      InitDescr(e_stack, STRING);
      str = e_stack->data.str.saddr = s_alloc(1L, &n);
      str->ref_ct = 1;
      str->string_len = 1;
      str->bytes = 1;
      str->data[0] = FIELD_MARK;
      (e_stack++)->data.str.saddr = str;
      op_matparse();
    }
  } else {
    k_dismiss(); /* Dismiss ADDR */
  }

  process.op_flags = 0; /* For error paths */

  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;

  if (status == 0) /* No errors */
  {
    /* Save the record id as the "last record read" using the actual_id
      so that files with case insensitive ids record the "real" id.    */

    fvar->id_len = id_len;
    setstring(&(fvar->id), actual_id);
  }

  if ((status < 0) && !(op_flags & P_ON_ERROR)) {
    if (process.status == -ER_MAXRLOCK)
      k_error(sysmsg(12167));
    k_error(sysmsg(1406), process.status, process.os_error);
  }
}

/* ======================================================================
   map_t1_id()  -  Perform name mapping for directory files              
   see ref manual - Directory Files Record IDs */

bool map_t1_id(char *id, int16_t id_len, char *mapped_id) {
  char *p;
  char *q;
  char *r;
  char c;

  p = id;
  q = mapped_id;

  /* 15 Oct 26 (openQM GIT): with the option on, the two names git keeps in a working directory are not mapped, so that a directory file
     can hold a project's source with its own .gitignore and .gitattributes */
  if (map_dir_ids && Option(OptGit) && (id_len > 0) && (*id == '.') &&
      (((id_len == 14) && !memcmp(id, ".gitattributes", 14)) || ((id_len == 10) && !memcmp(id, ".gitignore", 10)))) {
    memcpy(mapped_id, id, id_len);
    mapped_id[id_len] = '\0';
    return TRUE;
  }

// rev 0.9-3  map ~ to %T and . to %D (consistent with what dir_select in op_dio4.c)
//            but only when mapping to on
  if (map_dir_ids){
    if (*p == '.') {
      *(q++) = '%';
      *(q++) = 'D';
      p++;
      id_len--;
    } else if (*p == '~') {
      *(q++) = '%';
      *(q++) = 'T';
      p++;
      id_len--;
    }
  }

  while (id_len--) {
    c = *(p++);
    /* 12 Oct 26 dm  openQM item 34, on the owner's yes in chat the same day: bytes 128 to 255 are
       allowed in a record id (they were refused, c being a signed char, with everything over 126).
       Control characters and DEL are still refused.  This is the one place SD's English-only rule
       is lifted, by the owner, for the characters a directory file's record id may hold.        */
    if (((unsigned char)c < 32) || (c == 127)) {
      mapped_id = '\0';
      return FALSE;
    } else if (map_dir_ids && ((r = strchr(df_restricted_chars, c)) != NULL)) {
      *(q++) = '%';
      *(q++) = df_substitute_chars[r - df_restricted_chars];
    } else {
      *(q++) = c;
    }
  }

  *q = '\0';
  return TRUE;
}

/* ======================================================================
   t1_unmap_chunk()  -  Convert one chunk of a directory file's bytes into
                        SD's internal format: CRLF and LF become field marks

   4 Sep 26 Windows port - LIFTED OUT OF read_record() UNCHANGED SO THAT
   dir_read() USES THE SAME COPY.  PRE_RELEASE_FIXES 102.

   ***SHARING IT IS THE WHOLE POINT, NOT A TIDY-UP.***  102's undo captures a
   record before a commit overwrites it and writes it back if the commit fails.
   A capture that reverses the mark mapping even slightly differently from the
   way an ordinary READ does it would restore a record that is NOT the one it
   captured, and would do it silently, on the failure path, where nobody is
   looking.  One copy cannot drift from itself; two copies of this loop would
   be exactly the kind of thing that agrees for a year and then does not.

   THE CALLER OWNS *cr_pending AND MUST DO TWO THINGS WITH IT.  Initialise it
   FALSE before the first chunk, and after the LAST chunk, if it is still set,
   emit a '\r' of its own - a CR that ended the record with no LF after it is
   DATA, and deferring it is the only way to tell that from a CRLF split across
   a chunk boundary.  MAX_T1_BUFFER_SIZE is 31744, so a record larger than that
   really does arrive in pieces and this really does happen.

   Returns the new byte count.  Compacts in place, which is safe because CRLF
   is two bytes in and one out, so dst never overtakes src.                  */

Private int32_t t1_unmap_chunk(char *buff,
                               int32_t bytes,
                               bool last_chunk,
                               bool *cr_pending) {
  if (last_chunk) {
    /* This chunk contains the final byte of the file. This is
       probably a newline which we do not want to convert into
       a field mark. If so, decrement the byte count.

       24 Aug 26 Windows port - and if that newline was a CRLF, drop
       BOTH bytes, or the last field keeps a trailing CR.  If the pair
       straddled the chunk boundary the CR is in *cr_pending instead,
       and clearing it is how the same case is handled there.      */

    if ((bytes > 0) && (buff[bytes - 1] == '\n')) {
      bytes--;
      if ((bytes > 0) && (buff[bytes - 1] == '\r'))
        bytes--;
      else if (bytes == 0)
        *cr_pending = FALSE;
    }
  }

  /* 24 Aug 26 Windows port - CRLF folds to ONE field mark; a LONE CR
     is left alone because it is data.  PROJECT_STATUS 7 step 16 (a). */
  if (bytes || *cr_pending) {
    char *src = buff;
    char *dst = buff;
    int32_t left = bytes;

    if (*cr_pending) {
      /* A CR ended the PREVIOUS chunk.  Only now can we see whether
         an LF followed it. */
      *cr_pending = FALSE;
      if (left && (*src == '\n')) {
        *dst++ = FIELD_MARK;
        src++;
        left--;
      } else {
        *dst++ = '\r'; /* lone CR - data */
      }
    }

    while (left) {
      char c = *src++;
      left--;

      if (c == '\r') {
        if (left) {
          if (*src == '\n') {
            src++;
            left--;
            *dst++ = FIELD_MARK;
          } else {
            *dst++ = '\r'; /* lone CR - data */
          }
        } else {
          /* Last byte of the chunk: defer the decision. */
          *cr_pending = TRUE;
        }
      } else if (c == '\n') {
        *dst++ = FIELD_MARK;
      } else {
        *dst++ = c;
      }
    }

    bytes = (int32_t)(dst - buff);
  }

  return bytes;
}

/* ======================================================================
   crlf_from_vflags()  -  The line terminator mode named by field 6 of an F-type VOC entry

   L LF only, C CR LF only, B CR LF or LF (a lone CR is data), X CR LF or LF (a lone CR is thrown away): the letters of the
   openQM manual.  The letters come in capitals (get_voc_file_reference()).  None of them: CRLF_UNSET, the way SD has always
   done it.  Used by OPEN of a directory file and by OPENSEQ.                                                       */

u_char crlf_from_vflags(const char *vflags) {
  if (vflags == NULL)
    return CRLF_UNSET;
  if (strchr(vflags, 'L') != NULL)
    return CRLF_LF;
  if (strchr(vflags, 'C') != NULL)
    return CRLF_CRLF;
  if (strchr(vflags, 'B') != NULL)
    return CRLF_BOTH;
  if (strchr(vflags, 'X') != NULL)
    return CRLF_NOCR;
  return CRLF_UNSET;
}

/* ======================================================================
   t1_unmap_crlf()  -  One chunk of a directory file record, for the modes that look at CR (CRLF_CRLF, CRLF_BOTH, CRLF_NOCR)

   The converted bytes are left at the start of buff and their count returned; they never come to more bytes than went in,
   so the conversion is done in place.  What cannot be put there is the two things carried over from the chunk before - a
   field mark that was kept back, and a CR that turned out to be data - and those are handed back in prefix[] (at most 2
   bytes), to be copied BEFORE the returned bytes.

   Whichever way the record is cut into chunks, the answer is the same as for the whole record at once:
     CRLF_CRLF   CR LF is a line end; a lone CR or LF is data.
     CRLF_BOTH   CR LF or LF is a line end; a lone CR is data.
     CRLF_NOCR   LF is a line end; every CR is dropped.
   and the last line end of the record is not turned into a field mark (the record "a" + terminator is "a", as it always was
   for LF).  A CR that ends the record is data, in the two modes that have lone CRs.                                  */

Private int32_t t1_unmap_crlf(T1_UNMAP *st, char *buff, int32_t bytes, bool last_chunk, char *prefix, int *prefix_len) {
  u_char mode = st->mode;
  char *q = buff;       /* the bytes put out, in place */
  int32_t i = 0;
  bool produced = FALSE;  /* something came out of this chunk, a line end that will be dropped included */
  bool term_last = FALSE; /* the last byte put out is the field mark of a line end */
  bool cr_data = FALSE;   /* the CR carried over from the chunk before is data */
  bool held = st->hold_fm;
  int32_t n;

  *prefix_len = 0;
  st->hold_fm = FALSE;

  if (st->pending_cr) { /* only the modes that keep a lone CR ever have one */
    st->pending_cr = FALSE;
    produced = TRUE;
    if ((bytes > 0) && (buff[0] == '\n')) { /* it was CR LF */
      *q++ = FIELD_MARK;
      term_last = TRUE;
      i = 1;
    } else {
      cr_data = TRUE;
    }
  }

  for (; i < bytes; i++) {
    char c = buff[i]; /* q <= i, so this is never a byte already written */

    if (c == '\r') {
      if (mode == CRLF_NOCR)
        continue; /* thrown away */
      if (i + 1 < bytes) {
        if (buff[i + 1] == '\n') { /* CR LF */
          *q++ = FIELD_MARK;
          term_last = TRUE;
          i++;
        } else { /* a lone CR */
          *q++ = '\r';
          term_last = FALSE;
        }
        produced = TRUE;
      } else if (last_chunk) { /* a lone CR at the very end */
        *q++ = '\r';
        term_last = FALSE;
        produced = TRUE;
      } else { /* the next chunk says */
        st->pending_cr = TRUE;
      }
    } else if (c == '\n') {
      if (mode == CRLF_CRLF) { /* a lone LF */
        *q++ = '\n';
        term_last = FALSE;
      } else {
        *q++ = FIELD_MARK;
        term_last = TRUE;
      }
      produced = TRUE;
    } else {
      *q++ = c;
      term_last = FALSE;
      produced = TRUE;
    }
  }

  n = (int32_t)(q - buff);

  /* The field mark kept back from the chunk before goes out if anything follows it: the last line end is not a field mark */

  if (held) {
    if (produced)
      prefix[(*prefix_len)++] = FIELD_MARK;
    else if (!last_chunk)
      st->hold_fm = TRUE; /* nothing came out of this chunk (a CR still undecided, or CRs thrown away) */
  }
  if (cr_data)
    prefix[(*prefix_len)++] = '\r';

  if (term_last && (n > 0)) {
    if (last_chunk)
      n--; /* the last line end of the record */
    else if (!st->pending_cr) {
      n--; /* it may be the last: keep it back until something follows */
      st->hold_fm = TRUE;
    }
  }

  return n;
}

/* ======================================================================
   t1_unmap_lf()  -  One chunk, mode L: LF ends a line, a CR is data  (Linux's original t1_unmap_chunk(), 18 Oct 26)

   The last byte of the record, if it is a LF, is not turned into a field mark.                                      */

Private int32_t t1_unmap_lf(char *buff, int32_t bytes, bool last_chunk) {
  char *p;
  char *q;
  int32_t n;

  if (last_chunk && (bytes > 0) && (buff[bytes - 1] == '\n'))
    bytes--;

  if (bytes) {
    p = buff;
    n = bytes;
    do {
      q = memchr(p, '\n', n);
      if (q == NULL)
        break;
      *q = FIELD_MARK;
      n -= (q + 1 - p);
      p = q + 1;
    } while (n);
  }

  return bytes;
}

/* ======================================================================
   t1_unmap_and_copy()  -  The text of one chunk of a directory file record, into the string being built

   The one place both readers (read_record(), dir_read()) turn a chunk into SD's internal form: nothing at all in image mode
   (MARK.MAPPING off), the old LF conversion for CRLF_UNSET and CRLF_LF, t1_unmap_crlf() for the rest.             */

Private void t1_unmap_and_copy(FILE_VAR *fvar, T1_UNMAP *st, char *buff, int32_t bytes, bool last_chunk) {
  char prefix[2];
  int prefix_len = 0;

  if (fvar->access.dir.mark_mapping) {
    /* 18 Oct 26 Windows port - Linux's "no mode set" is LF only; this port's has always folded CR LF as well as LF (a lone CR is
       data), which is t1_unmap_chunk() below, left exactly as it was for a file with no letter and no FCONTROL.  Mode L (LF only,
       a CR is data) is Linux's old conversion, here t1_unmap_lf().  The CR it defers at the end of a chunk is st->pending_cr, and
       the caller emits it as data if the last chunk leaves it set. */
    if (st->mode == CRLF_UNSET)
      bytes = t1_unmap_chunk(buff, bytes, last_chunk, &st->pending_cr);
    else if (st->mode == CRLF_LF)
      bytes = t1_unmap_lf(buff, bytes, last_chunk);
    else
      bytes = t1_unmap_crlf(st, buff, bytes, last_chunk, prefix, &prefix_len);
  }
  if (prefix_len)
    ts_copy(prefix, prefix_len);
  if (bytes)
    ts_copy(buff, bytes);
}

/* ======================================================================
   The trigger function of a directory file (16 Oct 26, QM4 Fixes item 177)

   A hashed file keeps its trigger in its header.  A directory file has none, so SET.TRIGGER writes it into a file called
   %header% in the directory (openQM's name for the file that "controls replication and triggers"; SD's holds only the
   trigger).  A user's record id can never name it: % is one of the characters map_t1_id() rewrites, so the id %header% reaches
   the disk as something else.  SELECT does not list it and CLEAR.FILE does not delete it.  The file is text:

       trigger=name
       modes=n          (the TRG_ bits; 0 or none means pre-write and pre-delete, as for a hashed file)

   It is read when the file is opened and the trigger kept in the file variable (DIR_TRIGGER), loaded the way a hashed file's
   is.  Setting or removing a trigger therefore takes effect for the NEXT OPEN of the file, as the manual says of a directory
   file.  Only the operations that go through READ, WRITE, DELETE and CLEARFILE call it: WRITESEQ, WRITEBLK, OSWRITE and
   OSDELETE do not (the manual's limit).                                                                              */

#define DIR_HEADER_NAME "%header%"

Private bool dir_header_path(const char *dirpath, char *path) {
  char dir[MAX_PATHNAME_LEN + 1];
  int n;

  strncpy(dir, dirpath, MAX_PATHNAME_LEN);
  dir[MAX_PATHNAME_LEN] = '\0';
  n = strlen(dir);
  if ((n > 0) && (dir[n - 1] == DS))
    dir[n - 1] = '\0';
  return snprintf(path, MAX_PATHNAME_LEN + 1, "%s%c%s", dir, DS, DIR_HEADER_NAME) < (MAX_PATHNAME_LEN + 1);
}

/* The trigger named in the header, if there is one and it is a name a trigger can have */

Private bool dir_header_read(const char *dirpath, char *name, int *modes) {
  char path[MAX_PATHNAME_LEN + 1];
  char buff[256];
  OSFILE fu;
  int n;
  char *p;
  char *q;

  name[0] = '\0';
  *modes = 0;
  if (!dir_header_path(dirpath, path))
    return FALSE;
  fu = dio_open(path, DIO_READ);
  if (!ValidFileHandle(fu))
    return FALSE;
  n = (int)Read(fu, buff, sizeof(buff) - 1);
  CloseFile(fu);
  if (n <= 0)
    return FALSE;
  buff[n] = '\0';

  for (p = buff; *p != '\0'; p = q) {
    q = strchr(p, '\n');
    if (q != NULL)
      *(q++) = '\0';
    else
      q = p + strlen(p);
    if (strncmp(p, "trigger=", 8) == 0) {
      if (strlen(p + 8) <= MAX_TRIGGER_NAME_LEN)
        strcpy(name, p + 8);
    } else if (strncmp(p, "modes=", 6) == 0) {
      *modes = atoi(p + 6) & 0x7F;
    }
  }

  LowerCaseString(name);
  if ((name[0] == '\0') || !valid_call_name(name)) {
    name[0] = '\0';
    return FALSE;
  }
  return TRUE;
}

/* Called by OPEN of a directory file: find the trigger and load it. */

void dir_trigger_open(FILE_VAR *fvar, const char *dirpath) {
  char name[MAX_TRIGGER_NAME_LEN + 1];
  int modes;
  DIR_TRIGGER *trg;
  OBJECT_HEADER *obj;

  fvar->access.dir.trg = NULL;
  if (!dir_header_read(dirpath, name, &modes))
    return;

  trg = (DIR_TRIGGER *)k_alloc(108, sizeof(DIR_TRIGGER));
  if (trg == NULL)
    return;
  trg->name = (char *)k_alloc(109, strlen(name) + 1);
  if (trg->name == NULL) {
    k_free(trg);
    return;
  }
  strcpy(trg->name, name);

  obj = (OBJECT_HEADER *)load_object(trg->name, FALSE); /* NULL if it is not catalogued: the first call says so */
  if (obj != NULL)
    obj->ext_hdr.prog.refs += 1;
  trg->trigger = (u_char *)obj;
  trg->modes = (u_char)((modes != 0) ? modes : (TRG_PRE_WRITE | TRG_PRE_DELETE));
  fvar->access.dir.trg = trg;
}

/* Called when the file variable is closed. */

void dir_trigger_close(FILE_VAR *fvar) {
  DIR_TRIGGER *trg = fvar->access.dir.trg;

  if (trg == NULL)
    return;
  if (trg->trigger != NULL)
    --(((OBJECT_HEADER *)(trg->trigger))->ext_hdr.prog.refs);
  k_free(trg->name);
  k_free(trg);
  fvar->access.dir.trg = NULL;
}

/* SET.TRIGGER of a directory file: write the header, or take it away when the name is null.  Returns the STATUS() value. */

int dir_set_trigger(FILE_VAR *fvar, const char *name, int modes) {
  char path[MAX_PATHNAME_LEN + 1];
  char text[MAX_TRIGGER_NAME_LEN + 40];
  OSFILE fu;
  int n;

  if (fvar->flags & FV_RDONLY)
    return ER_RDONLY;
  if (!dir_header_path((char *)(FPtr(fvar->file_id)->pathname), path))
    return ER_IID;

  if (name[0] == '\0') {
    if ((remove(path) < 0) && (errno != ENOENT)) {
      process.os_error = errno;
      return ER_IOE;
    }
    return 0;
  }

  n = snprintf(text, sizeof(text), "trigger=%s\nmodes=%d\n", name, modes);
  fu = dio_open(path, DIO_REPLACE);
  if (!ValidFileHandle(fu)) {
    process.os_error = errno;
    return ER_IOE;
  }
  if (Write(fu, text, n) != n) {
    process.os_error = OSError;
    CloseFile(fu);
    return ER_IOE;
  }
  CloseFile(fu);
  return 0;
}

/* Is this the name of the header file, which is not a record?  (SELECT, CLEAR.FILE and ANALYSE.FILE ask.) */

bool is_dir_header(const char *name) {
  return strcmp(name, DIR_HEADER_NAME) == 0;
}

/* ======================================================================
   dir_read()  -  Read a record from a directory file, as a callable

   4 Sep 26 Windows port - NEW.  PRE_RELEASE_FIXES 102.

   ***THE DIRECTORY HALF OF SD HAD A WRITE API AND NO READ API***, which is why
   102 is not a short job.  dir_write() has been callable from op_txncmt() since
   the beginning; the only reader was read_record(), a Private function that
   takes its file variable, its id and its target off the VM's e-stack and can
   only be reached by executing a READ opcode.  A commit cannot execute an
   opcode, so 102's undo could not ask what a directory record held before it
   overwrote it.  This is that missing half, and it is deliberately shaped like
   dir_write(): a FILE_VAR, a MAPPED id, and the record as a STRING_CHUNK.

   THE ID MUST ALREADY BE MAPPED, exactly as dir_write() requires, and for the
   same reason PRE_RELEASE 154 exists: the raw id is what the BASIC statement
   used and the mapped id is what the disk is called.

   *str IS SET TO THE RECORD ON SUCCESS and is NULL for an empty one, which is
   a real state and not a failure - an empty directory record is a zero-length
   file.  The chunk is returned with ref_ct 1 and belongs to the caller.

   ON FAILURE *str IS NULL AND *status SAYS WHY, using the same values and the
   same SIGNS read_record() uses, because that is where they came from:
   ER_RNF for no such record, ER_IID for an illegal name or a device name,
   ER_MAX_STRING for one too large to hold, and NEGATIVE -ER_IOE for a read
   error, whose sign is what tells a caller to take the ON ERROR path.

   ***ER_RNF IS NOT AN ERROR TO 102 AND THAT IS THE POINT OF SEPARATING IT.***
   A commit that is about to create a record needs to know the record was not
   there, so that the undo DELETES rather than restoring something.  A caller
   that cannot tell "absent" from "unreadable" would either resurrect a record
   that never existed or leave one it should have removed.

   IT IS NOT RE-ENTRANT, and neither is read_record(): ts_init() parks the
   target-string chain in file-scope state, and t1_buffer is a single shared
   buffer.  Both callers are places where no other string is being built.   */

bool dir_read(FILE_VAR *fvar,
              char *mapped_id,
              STRING_CHUNK **str,
              int16_t *status) {
  char pathname[MAX_PATHNAME_LEN + 1];
  int16_t path_len;
  char record_path[MAX_PATHNAME_LEN + 1];
  OSFILE fu = INVALID_FILE_HANDLE;
  struct stat statbuf;
  int64_t remaining_bytes64;
  int32_t remaining_bytes;
  int32_t bytes;
  bool ts_started = FALSE;
  bool ok = FALSE;
  T1_UNMAP t1u; /* line terminator mode of the file, and what is carried from chunk to chunk */

  t1u.mode = fvar->access.dir.crlf;
  t1u.pending_cr = FALSE;
  t1u.hold_fm = FALSE;

  *str = NULL;
  *status = 0;

  /* Increment statistics counter */

  StartExclusive(FILE_TABLE_LOCK, 49);
  NoteStat(reads);
  EndExclusive(FILE_TABLE_LOCK);

  strcpy(pathname, (char *)(FPtr(fvar->file_id)->pathname));
  path_len = strlen(pathname);
  if (pathname[path_len - 1] == DS)
    pathname[path_len - 1] = '\0'; /* 0214 */

  if (snprintf(record_path, MAX_PATHNAME_LEN + 1, "%s%c%s", pathname, DS,
               mapped_id) >= (MAX_PATHNAME_LEN + 1)) {
    *status = (int16_t)(process.status = ER_IID);
    goto exit_dir_read;
  }

  fu = dio_open(record_path, DIO_READ);
  if (!ValidFileHandle(fu)) {
    *status = (int16_t)(process.status = ER_RNF);
    goto exit_dir_read;
  }

  /* 0408 Check that this really is a file, not CON, COMn, LPTn */

  if (fstat(fu, &statbuf) || !(statbuf.st_mode & S_IFREG)) {
    *status = (int16_t)(process.status = ER_IID);
    goto exit_dir_read;
  }

  remaining_bytes64 = filelength64(fu);
  if (remaining_bytes64 > MAX_STRING_SIZE) {
    *status = (int16_t)(process.status = ER_MAX_STRING);
    goto exit_dir_read;
  }
  remaining_bytes = (int32_t)remaining_bytes64;

  ts_init(str, remaining_bytes);
  ts_started = TRUE;
  t1_buffer_alloc(remaining_bytes);

  while (remaining_bytes > 0) {
    bytes = min(remaining_bytes, t1_buffer_size);

    if (Read(fu, t1_buffer, bytes) < 0) {
      *status = (int16_t)(-(process.status = ER_IOE));
      process.os_error = OSError;
      goto exit_dir_read;
    }

    remaining_bytes -= bytes;

    t1_unmap_and_copy(fvar, &t1u, t1_buffer, bytes, (remaining_bytes == 0));
  }

  /* A CR that ended the record with no LF after it is DATA, and would
     otherwise be swallowed by having been deferred. */

  if (t1u.pending_cr) {
    char cr = '\r';
    ts_copy(&cr, 1);
    t1u.pending_cr = FALSE;
  }

  (void)ts_terminate();
  ts_started = FALSE;
  ok = TRUE;

exit_dir_read:
  if (ValidFileHandle(fu))
    CloseFile(fu);
  if (t1_buffer != NULL)
    t1_buffer_free();

  /* ***TERMINATE BEFORE FREEING, OR THE FREE WALKS AN UNFINISHED CHAIN.***
     ts_terminate() is what fills in ref_ct and string_len on the first chunk;
     bail out of the read loop before it and the chunks exist but say nothing
     about themselves.  read_record() never had to care because it leaves its
     partial string on a descriptor for k_release() to deal with. */

  if (!ok) {
    if (ts_started)
      (void)ts_terminate();
    if (*str != NULL) {
      s_free(*str);
      *str = NULL;
    }
  }

  return ok;
}

/* ======================================================================
   dir_write()  -  Write record to directory file                         */

bool dir_write(FILE_VAR *fvar, char *mapped_id, STRING_CHUNK *str) {
  char pathname[MAX_PATHNAME_LEN + 1];
  int16_t path_len;
  char record_path[MAX_PATHNAME_LEN + 1];
  char temp_path[MAX_PATHNAME_LEN + 1];
  int16_t bytes_remaining;
  char *p;
  char *q;
  int16_t n;
  struct stat statbuf;
  /* What ends a line of the record: LF, except in the mode that wants CR LF (16 Oct 26, QM4 Fixes item 452).  The other
     modes write the operating system's line end, which on Linux is the LF. */
  char *newline = (fvar->access.dir.crlf == CRLF_CRLF) ? "\r\n" : Newline;
  int16_t newline_bytes = (fvar->access.dir.crlf == CRLF_CRLF) ? 2 : NewlineBytes;

  t1_fu = INVALID_FILE_HANDLE;
  process.status = 0;

  /* Increment statistics and transactions counters */

  StartExclusive(FILE_TABLE_LOCK, 51);
  NoteStat(writes);
  FPtr(fvar->file_id)->upd_ct++;
  EndExclusive(FILE_TABLE_LOCK);

  /* Open and truncate the file */

  strcpy(pathname, (char *)(FPtr(fvar->file_id)->pathname));
  path_len = strlen(pathname);
  if (pathname[path_len - 1] == DS)
    pathname[path_len - 1] = '\0'; /* 0214 */
  /* converted to snprintf() -gwb 22Feb20 */
  if (snprintf(record_path, MAX_PATHNAME_LEN + 1, "%s%c%s", pathname, DS, mapped_id) >= (MAX_PATHNAME_LEN + 1)) {
    /* TODO: this should also be logged with more detail */
    k_error("Overflowed path/filename length in dir_write()!");
    goto exit_dir_write;
  }

  if (pcfg.safedir) {
    /* converted to snprintf() -gwb 22Feb20 */
/* rev 0.9.0 */
    if (snprintf(temp_path, MAX_PATHNAME_LEN + 1, "%s%c%%%%%d", pathname, DS, my_uptr->uid) >= (MAX_PATHNAME_LEN + 1)) {
      /* TODO: this should also be logged with more detail */
      k_error("Overflowed path/filename length in dir_write()!");
      goto exit_dir_write;
    }
    t1_fu = dio_open(temp_path, DIO_REPLACE);
  } else {
    t1_fu = dio_open(record_path, DIO_REPLACE);
  }

  if (!ValidFileHandle(t1_fu)) {
    if (errno == ENOENT) {
      process.status = -ER_RNF;
    } else {
      process.status = -ER_PERM;
      log_permissions_error(fvar);
    }
    goto exit_dir_write;
  }

  /* 0408 Check that this really is a file, not CON, COMn, LPTn, AUX */

  if (fstat(t1_fu, &statbuf) || !(statbuf.st_mode & S_IFREG)) {
    process.status = -ER_IID;
    goto exit_dir_write;
  }

  /* Create a buffer in the virtual memory area */

  if (str != NULL) {
    t1_buffer_alloc(str->string_len);

    do {
      if (!fvar->access.dir.mark_mapping) {
        if (!t1_write(str->data, str->bytes))
          goto exit_dir_write;
      } else /* Convert field marks to newlines */
      {
        p = str->data;
        bytes_remaining = str->bytes;
        while (bytes_remaining) {
          q = (char *)memchr(p, FIELD_MARK, bytes_remaining);
          if (q == NULL) {
            if (!t1_write(p, bytes_remaining))
              goto exit_dir_write;
            break;
          } else {
            n = q - p;
            if ((n > 0) && (!t1_write(p, n)))
              goto exit_dir_write;
            if (!t1_write(newline, newline_bytes))
              goto exit_dir_write;
            p = q + 1;
            bytes_remaining -= n + 1;
          }
        }
      }
      str = str->next;
    } while (str != NULL);

    /* If we are not writing in image mode add a newline to the end
      of the file.                                                   */

    if (fvar->access.dir.mark_mapping) {
      if (!t1_write(newline, newline_bytes))
        goto exit_dir_write;
    }

    if (!t1_flush())
      goto exit_dir_write;
  }

  if (pcfg.safedir) {
    CloseFile(t1_fu);
    t1_fu = INVALID_FILE_HANDLE;
    remove(record_path);
    if (rename(temp_path, record_path)) {
      goto exit_dir_write;
    }
  }

exit_dir_write:
  if (ValidFileHandle(t1_fu))
    CloseFile(t1_fu);
  if (t1_buffer != NULL)
    t1_buffer_free();

  /* 15 Oct 26 (openQM DIR.DTM): the option makes a write to a directory file count as a change of the directory, whose date and time
     modified the operating system moves only when a name is added or removed, not when a record is replaced */
  if ((process.status == 0) && Option(OptDirDtm))
    (void)utimensat(AT_FDCWD, pathname, NULL, 0);

  return process.status == 0;
}

/* ======================================================================
   Directory file buffering functions                                     */

Private void t1_buffer_alloc(int32_t size) {
  if (size > MAX_T1_BUFFER_SIZE)
    size = MAX_T1_BUFFER_SIZE;
  t1_buffer = (char *)k_alloc(8, size);
  /* Modified by Composer AI - 2026/06/10.
     k_alloc() can return NULL on memory exhaustion; t1_buffer was used
     without a check by the callers of t1_buffer_alloc(). */
  if (t1_buffer == NULL)
    k_error("Insufficient memory for directory file buffer");
  /* -------------------- */
  t1_ptr = t1_buffer;
  t1_buffer_size = size;
  t1_space = (int16_t)size;
}

Private bool t1_write(char *p, int16_t bytes) {
  while (bytes) {
    if (bytes < t1_space) /* Fits with at least one byte to spare */
    {
      memcpy(t1_ptr, p, bytes);
      t1_ptr += bytes;
      t1_space -= bytes;
      break;
    } else /* Fills buffer */
    {
      memcpy(t1_ptr, p, t1_space);
      p += t1_space;
      bytes -= t1_space;
      t1_space = 0;

      if (!t1_flush())
        return FALSE;

      t1_ptr = t1_buffer;
      t1_space = t1_buffer_size;
    }
  }

  return TRUE;
}

Private bool t1_flush() {
  int16_t len;
  len = t1_buffer_size - t1_space;
  if (len == 0)
    return TRUE;
  if (Write(t1_fu, t1_buffer, len) < 0) {
    process.status = -ER_IOE;
    process.os_error = OSError;
    return FALSE;
  }

  return TRUE;
}

Private void t1_buffer_free() {
  k_free(t1_buffer);
  t1_buffer = NULL;
}

/* ======================================================================
   call_trigger()  -  Call trigger function                               */

bool call_trigger(DESCRIPTOR *fvar_descr, int16_t mode, DESCRIPTOR *id_descr, DESCRIPTOR *data_descr, bool on_error, bool updatable) /* Allow data to be modified? */
{
  FILE_VAR *fvar;
  DESCRIPTOR *trg_descr; /* @TRIGGER.RETURN.CODE */
  STRING_CHUNK *str;
  DH_FILE *dh_file;
  bool error;
  int16_t args;
  char *trigger_name;
  u_char *trigger_obj;

  fvar = fvar_descr->data.fvar;

  /* The trigger of a hashed file is in its DH_FILE, that of a directory file in the file variable (item 177) */

  if (fvar->type == DIRECTORY_FILE) {
    trigger_name = fvar->access.dir.trg->name;
    trigger_obj = fvar->access.dir.trg->trigger;
  } else {
    dh_file = fvar->access.dh.dh_file;
    trigger_name = dh_file->trigger_name;
    trigger_obj = dh_file->trigger;
  }

  /* Check trigger function was loaded on open */

  if (trigger_obj == NULL) {
    k_error(sysmsg(1409), trigger_name, FPtr(fvar->file_id)->pathname);
  }

  /* Check argument count */

  args = ((OBJECT_HEADER *)trigger_obj)->args;
  if ((args < 4) || (args > 5))
    k_error(sysmsg(1410));

  /* Set @TRIGGER.RETURN.CODE to 0 */

  trg_descr = Element(process.syscom, SYSCOM_TRIGGER_RETURN_CODE);
  k_release(trg_descr);
  InitDescr(trg_descr, INTEGER);
  trg_descr->data.value = 0;

  /* Push action onto stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = mode;

  /* Push record id onto stack */

  InitDescr(e_stack, STRING);
  str = (id_descr == NULL) ? NULL : (id_descr->data.str.saddr);
  (e_stack++)->data.str.saddr = str;
  if (str != NULL)
    (str->ref_ct)++;

  /* Push record data onto stack */

  if (updatable) {
    InitDescr(e_stack, ADDR);
    (e_stack++)->data.d_addr = data_descr;
  } else if ((data_descr != NULL) && (data_descr->type == COLL)) {
    /* 11 Oct 26 dm - The post-write trigger of a data collection file is given the collection.  It was
       given the descriptor read as a string, a pointer that was not a string, and stopped the process. */
    InitDescr(e_stack, COLL);
    e_stack->data.coll = data_descr->data.coll;
    (data_descr->data.coll->ref_ct)++;
    e_stack++;
  } else {
    InitDescr(e_stack, STRING);
    str = (data_descr == NULL) ? NULL : (data_descr->data.str.saddr);
    (e_stack++)->data.str.saddr = str;
    if (str != NULL)
      (str->ref_ct)++;
  }

  /* Push ON_ERROR flag onto stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = on_error;

  /* Push trigger file variable if five args */

  if (args == 5) {
    InitDescr(e_stack, ADDR);
    (e_stack++)->data.d_addr = fvar_descr;
  }

  /* Call trigger function using an adaptation of k_recurse() */

  k_call("", args, trigger_obj, 0);
  process.program.flags |= PF_IS_TRIGGER | PF_IN_TRIGGER;
  k_run_program();
  k_exit_cause = 0;

  error = ((trg_descr->type != INTEGER) || (trg_descr->data.value != 0));
  if (error && !on_error) {
    tio_printf("\n");
    tio_printf(sysmsg(1411)); /* Data validation error: */

    /* Push ADDR to @TRIGGER.RETURN.CODE onto stack */

    InitDescr(e_stack, ADDR);
    (e_stack++)->data.d_addr = trg_descr;
    op_dspnl();
  }

  return !error;
}

/* ======================================================================
   op_pickread()  -  PICKREAD  Set Pick style read behaviour              */

void op_pickread() {
  process.op_flags |= P_PICKREAD;
}

/* ======================================================================
   valid_id()  -  Validate record id                                      */

Private bool valid_id(char *id, int16_t id_len) {
  register char c;

  if ((id_len <= 0) /* Handle k_get_c_string() failure here */
      || (id_len > sysseg->maxidlen)) {
    return FALSE;
  }

  while (id_len--) {
    c = *(id++);
    if (c == 0)
      return FALSE;
    if (IsMark(c))
      return FALSE;
  }

  return TRUE;
}

/* END-CODE */
