/* TXN.C
 * Transaction Management
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
 *  4 Sep 26 Windows port - a commit that fails half way now PUTS BACK the
 *           records it had already applied.  Owner's ruling, disambiguated
 *           3 Sep 26: restore each already-applied record to what it held
 *           before - NOT delete it, which taken literally would destroy the
 *           prior version of an UPDATED record and defeat all-or-nothing
 *           instead of delivering it.  The before image is taken at commit
 *           time, immediately before each action is applied, because only
 *           then is it certainly the one about to be overwritten; TXN_CACHE
 *           has never held one.  It is replayed in reverse from txn_abort(),
 *           the far side of the longjmp, before the locks are released.
 *           An entry is the prior record, or a marker that there was none (so
 *           the undo deletes), or a marker that the image could not be read -
 *           which is logged by file and id rather than passed over.  The undo
 *           never raises: the disk is already misbehaving by then.
 *           PRE_RELEASE_FIXES 102, UPSTREAM_FIXES 32.
 *  4 Sep 26 Windows port - the directory-file arms of op_txncmt() now map the
 *           record id before touching the disk.  dir_write() and the delete
 *           path both take a MAPPED id, op_dio3.c passes map_t1_id()'s output
 *           outside a transaction, and both were handed txn->id - which is the
 *           RAW id, because op_dio3.c caches the id the statement used.  A
 *           WRITE inside a transaction therefore created a file the matching
 *           READ could never find, and a DELETE removed a path that had never
 *           existed, tolerated the ENOENT and reported success.  Neither
 *           needed an induced fault: an ordinary successful commit was enough.
 *           PRE_RELEASE_FIXES 154, UPSTREAM_FIXES 36.
 *  1 Sep 26 Windows port - a commit that fails half way no longer holds its
 *           record locks for the life of the process.  k_error() longjmps to
 *           K_ABORT rather than returning, so the five "goto exit_op_txncmt"
 *           paths skipped unlock_txn() entirely and nothing else released
 *           them: txn_abort() gates on process.txn_id, which op_txncmt() sets
 *           to 0 before the loop.  txn_abort() now also releases
 *           commit_txn_id, which is the id the commit was running under, and
 *           op_txncmt() clears it on the success path so the two cannot
 *           overlap.  Fixed in txn_abort() and not at the five call sites
 *           BECAUSE THAT IS THE CLASS: a sixth error path added to the loop
 *           later is covered without anybody remembering to cover it.
 *           PRE_RELEASE_FIXES 102 (the lock half; the half-applied records
 *           still need a ruling), UPSTREAM_FIXES 32.
 *  1 Sep 26 Windows port - the directory-file delete at commit now tests
 *           remove() and the S_IFREG guard, copying the non-transactional
 *           twin (op_dio3.c).  It was a bare remove() with its return
 *           discarded - the only arm of the four that checked nothing - so a
 *           delete that failed inside a transaction was reported as done and
 *           the record stayed on disk.  PRE_RELEASE_FIXES 101, UPSTREAM_FIXES 31.
 * 29 Aug 26 Windows port - op_txncmt() now leaves the transaction level it
 *           commits.  PRE_RELEASE_FIXES 11, UPSTREAM_FIXES 17: it undid
 *           neither half of what op_txnbgn() did, so txn_depth only ever
 *           climbed and a NESTED commit orphaned the outer transaction's
 *           cache on txn_stack - the outer COMMIT then wrote an empty cache
 *           and its records were lost silently.  The reinstate-and-decrement
 *           block is lifted out of rollback() into end_txn_level() and called
 *           from both, because having it in one place with one caller is what
 *           the defect was.
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "dh_int.h"
#include "config.h"

typedef struct TXN_CACHE TXN_CACHE;
struct TXN_CACHE {
  TXN_CACHE* next;
  int16_t mode;
#define TXN_WRITE 1
#define TXN_DELETE 2
#define TXN_CLOSE 3
  FILE_VAR* fvar;    /* File */
  STRING_CHUNK* str; /* Data to write */
  int16_t id_len;
  char id[1];
};

Private TXN_CACHE* txn_head = NULL;
Private TXN_CACHE* txn_tail = NULL;
Private int16_t txn_cproc_level;
Private bool journalled_txn; /* Journalled update in this txn? */

int txn_depth = 0;           /* Also accessed by op_sys.c */

/* 1 Sep 26 Windows port - THE COMMENT HERE SAID "Also needed by dh_jnl.c" AND
   THAT FILE DOES NOT EXIST IN THIS TREE.  Checked before relying on it, because
   the whole of PRE_RELEASE 102's lock fix turns on whether this variable's
   lifetime is ours to manage: grep says txn.c is the only user.  It is now
   load-bearing - NON-ZERO MEANS "a commit is in flight under this id", which is
   what lets txn_abort() release the locks op_txncmt() could not.  Explicitly
   initialised for the same reason; the guard depends on it starting at 0.    */
u_int32_t commit_txn_id = 0;

typedef struct TXN_STACK TXN_STACK;
struct TXN_STACK {
  TXN_STACK* next;
  u_int32_t txn_id;  /* Previous transaction id */
  int16_t cproc_level; /* Command process level of previous transaction */
  bool journalled_txn;
  TXN_CACHE* txn_head;
  TXN_CACHE* txn_tail;
};

#define IdMatch(id1, id2, id_len)                 \
  (((nocase) ? MemCompareNoCase(id1, id2, id_len) \
             : memcmp(id1, id2, id_len)) == 0)

Private TXN_STACK* txn_stack = NULL;

/* ======================================================================
   4 Sep 26 Windows port - THE BEFORE IMAGES.  PRE_RELEASE_FIXES 102.

   Owner's ruling, as disambiguated 3 Sep 2026: a commit that fails part way
   must RESTORE EACH ALREADY-APPLIED RECORD TO WHAT IT HELD BEFORE.  ***THE
   LITERAL READING OF THE ORIGINAL WORDS - "they are deleted" - WAS PUT BACK TO
   HIM AND CLOSED, because deleting a record the transaction had UPDATED would
   destroy the version that survives today.  That defeats all-or-nothing
   instead of delivering it.  Do not re-open it.***

   WHY THE IMAGE IS TAKEN AT COMMIT TIME AND NOT AT WRITE-CACHE TIME.  TXN_CACHE
   holds only the NEW data (see its declaration above - mode, fvar, str, id).
   Between the WRITE statement and the COMMIT, any number of things can change
   the record; only immediately before the action is applied is the image
   certainly the one about to be overwritten.

   THE LIST IS A STACK, SO WALKING IT HEAD TO TAIL IS ALREADY REVERSE ORDER.
   That matters when one transaction touches the same record twice through
   different cache entries: the LAST image captured is the oldest state still
   reachable, and it must be the one written back last.

   THREE KINDS OF ENTRY, AND THE THIRD IS NOT A LUXURY.  A record that existed
   is restored; one that did not is deleted; and one whose image COULD NOT BE
   READ is neither - it is logged by file and id, because a commit that cannot
   promise all-or-nothing for a particular record must say which record, not
   fail silently or pretend it succeeded.                                    */

typedef struct TXN_UNDO TXN_UNDO;
struct TXN_UNDO {
  TXN_UNDO* next;
  int16_t mode;
#define UNDO_RESTORE 1    /* it existed - write these bytes back */
#define UNDO_DELETE 2     /* it did not exist - remove it again */
#define UNDO_UNREADABLE 3 /* the image could not be taken - say so, do nothing */
  FILE_VAR* fvar;
  STRING_CHUNK* str; /* the record as it was; NULL is a valid empty record */
  int16_t id_len;
  char id[1]; /* the RAW id, exactly as TXN_CACHE holds it */
};

Private TXN_UNDO* undo_head = NULL;

Private TXN_CACHE* alloc_txn(int16_t id_len);
Private void rollback(void);
Private void end_txn_level(void);
Private void clear_parent(int16_t fno, char* id, int16_t id_len);
Private void capture_undo(FILE_VAR* fvar, char* id, int16_t id_len);
Private void replay_undo(void);
Private void free_undo(void);

/* ======================================================================
   op_txnbgn()  -  Begin transaction                                      */

void op_txnbgn() {
  TXN_STACK* stk;

  if (process.txn_id != 0) /* Nested transaction */
  {
    stk = (TXN_STACK*)k_alloc(81, sizeof(TXN_STACK));
    stk->next = txn_stack;
    stk->txn_id = process.txn_id;
    stk->cproc_level = cproc_level;
    stk->journalled_txn = journalled_txn;
    stk->txn_head = txn_head;
    stk->txn_tail = txn_tail;
    txn_stack = stk;

    txn_head = NULL;
    txn_tail = NULL;
  }

  txn_depth++;
  txn_cproc_level = cproc_level;

  StartExclusive(SHORT_CODE, 58);
  if ((process.txn_id = (sysseg->next_txn_id)++) == 0) {
    /* Wrapped  -  Hopefully the oldest transactions are not stacked */
    process.txn_id = (sysseg->next_txn_id)++;
  }
  EndExclusive(SHORT_CODE);

  journalled_txn = FALSE;
}

/* ======================================================================
   op_txncmt()  -  Commit transaction                                     */

void op_txncmt() {
  TXN_CACHE* txn;
  TXN_CACHE* next_txn;
  FILE_VAR* fvar;
  FILE_ENTRY* fptr;
  DH_FILE* dh_file;
  char path[MAX_PATHNAME_LEN + 1];
  STRING_CHUNK* str;
  struct stat statbuf; /* 1 Sep 26 - the S_IFREG guard below, PRE_RELEASE 101 */
  /* 4 Sep 26 Windows port - THE CACHED ID IS THE RAW ONE AND THE DISK WANTS
     THE MAPPED ONE.  PRE_RELEASE_FIXES 154, UPSTREAM_FIXES 36.  Sized as
     op_dio3.c sizes it: every mapped character can become two.            */
  char mapped_id[2 * MAX_ID_LEN + 1];

  if (sysseg->flags & SSF_SUSPEND)
    suspend_updates();

  /* 0323 Clear process.txn_id so that close action doesn't loop */

  commit_txn_id = process.txn_id;
  process.txn_id = 0;

  /* Commit all actions */

  for (txn = txn_head; txn != NULL; txn = next_txn) {
    fvar = txn->fvar;

    /* 4 Sep 26 Windows port - TAKE THE BEFORE IMAGE, IMMEDIATELY BEFORE THE
       ACTION IS APPLIED.  PRE_RELEASE_FIXES 102.

       ONE CALL SITE FOR BOTH MODES, ON PURPOSE, AND IT IS THE SAME REASONING
       THAT PUT THE LOCK FIX IN txn_abort() RATHER THAN AT FIVE k_error()
       SITES: a capture per arm would be four places to add a fifth to, and
       this file has already been shown adding arms one day and forgetting the
       bookkeeping the next.  TXN_CLOSE changes no record and capture_undo()
       ignores it.

       IT IS INVISIBLE TO EVERYTHING BELOW IT - process.status, os_error and
       dh_err are all put back before it returns, because the arms under here
       report their failures through exactly those. */

    if ((txn->mode == TXN_WRITE) || (txn->mode == TXN_DELETE))
      capture_undo(fvar, txn->id, txn->id_len);

    switch (txn->mode) {
      case TXN_WRITE:
        switch (fvar->type) {
          case DYNAMIC_FILE:
            dh_file = fvar->access.dh.dh_file;

            if (!dh_write(dh_file, txn->id, txn->id_len, txn->str)) {
              k_error(sysmsg(1422));
              goto exit_op_txncmt;
            }
            dh_file->flags |= DHF_FSYNC;
            break;

          case DIRECTORY_FILE:
            /* 4 Sep 26 Windows port - MAP THE ID, WHICH THIS ARM NEVER DID.
               PRE_RELEASE_FIXES 154, UPSTREAM_FIXES 36.

               dir_write()'s second parameter is a MAPPED id - it is spelled
               mapped_id in the prototype and is used verbatim as the filename.
               op_dio3.c:832 passes map_t1_id()'s output; this arm passed
               txn->id, and txn->id is the RAW id: op_dio3.c:829 calls
               txn_write(fvar, id, id_len, str), not mapped_id, so nothing
               between the WRITE statement and here had ever mapped it.

               WHAT THAT COST, MEASURED 4 Sep 2026 ON A COMMIT THAT SUCCEEDED:
               WRITE ... ON F, ',' inside a transaction created the file ',',
               where the identical statement outside one creates '%C'.  A
               later READ of ',' maps as it always has, looks for '%C', and
               returns NOREC.  THE RECORD IS WRITTEN WHERE NOTHING CAN READ IT
               AGAIN, with no error on any path - map_dir_ids defaults TRUE and
               df_restricted_chars is *,=><%/+:;?\" , so ordinary ids reach it.

               THE CACHE IS RIGHT TO HOLD THE RAW ID AND IS NOT CHANGED.
               txn_read(), txn_write(), txn_delete() and clear_parent() all
               match the cache against the id the BASIC statement used, which
               is the raw one; mapping it at cache time would break all four.
               The mapping belongs here, at the point of contact with the disk,
               which is exactly where the non-transactional twin does it.

               THE FAILURE RETURN CANNOT FIRE FROM HERE and is handled anyway:
               both entry points (op_dio3.c:821 for WRITE, :374 for DELETE)
               call map_t1_id() and refuse ER_IID before they ever reach the
               cache, so an id that maps has already been proved to map.  A
               silent skip would be the null case the instrument rules refuse,
               so it raises 1422 like every other failure in this arm.      */
            if (!map_t1_id(txn->id, txn->id_len, mapped_id)) {
              process.status = -ER_IID;
              k_error(sysmsg(1422));
              goto exit_op_txncmt;
            }

            if (!dir_write(fvar, mapped_id, txn->str)) {
              k_error(sysmsg(1422));
              goto exit_op_txncmt;
            }
            break;
        }

        if (((str = txn->str) != NULL) && (--(str->ref_ct) == 0))
          s_free(str);

        clear_parent(fvar->file_id, txn->id, txn->id_len);
        break;

      case TXN_DELETE:
        switch (fvar->type) {
          case DYNAMIC_FILE:
            dh_file = fvar->access.dh.dh_file;
            if ((!dh_delete(dh_file, txn->id, txn->id_len)) &&
                (dh_err != DHE_RECORD_NOT_FOUND)) {
              k_error(sysmsg(1423));
              goto exit_op_txncmt;
            }
            dh_file->flags |= DHF_FSYNC;
            break;

          case DIRECTORY_FILE:
            /* 4 Sep 26 Windows port - MAP THE ID HERE TOO, AND BEFORE THE
               COUNTERS.  PRE_RELEASE_FIXES 154, UPSTREAM_FIXES 36.  Same
               defect as the TXN_WRITE arm above and the same one line of
               cause; see that comment for why the cache is right to hold the
               raw id.  THIS ARM IS THE WORSE OF THE TWO, because it is
               SILENT: the path built from the raw id names a file that never
               existed, remove() fails ENOENT, and ENOENT is deliberately
               tolerated twenty lines below (the record is gone, which is what
               was asked for) - so a transactional DELETE of a mapped id
               reported success, removed nothing, and left the record readable.
               Measured 4 Sep 2026: DELETE F, ';' inside a transaction left
               '%Y' on disk and a later READ still returned its contents.

               BEFORE THE COUNTERS ON PURPOSE.  They were incremented first,
               so an id that could not be mapped would have counted a delete
               that never happened.  It cannot happen today - op_dio3.c:374
               validates before caching - but a statistic raised by a path
               that then refuses is the null case in miniature.            */
            if (!map_t1_id(txn->id, txn->id_len, mapped_id)) {
              process.status = -ER_IID;
              k_error(sysmsg(1423));
              goto exit_op_txncmt;
            }

            /* Increment statistics and transaction counters */

            StartExclusive(FILE_TABLE_LOCK, 50);
            sysseg->global_stats.deletes++;
            fptr = FPtr(fvar->file_id);
            fptr->upd_ct++;
            EndExclusive(FILE_TABLE_LOCK);
            /* converted sprintf() -gwb 22Feb20 */
            if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s%c%s", fptr->pathname,
                         DS, mapped_id) >= (MAX_PATHNAME_LEN + 1)) {
               /* TODO should log more detail here */
               k_error("Overflowed path/filename length in op_txncmt()!");
            } else {
              /* 1 Sep 26 Windows port - THE DELETE IS TESTED.  PRE_RELEASE 101,
                 UPSTREAM_FIXES 31.  This was a bare remove(path) with its
                 return discarded, and it was the WHOLE of the directory-file
                 delete at commit.

                 IT WAS THE ONLY ARM OF THE FOUR THAT CHECKED NOTHING:
                 TXN_WRITE/DYNAMIC_FILE tests dh_write and raises 1422,
                 TXN_WRITE/DIRECTORY_FILE tests dir_write and raises 1422, and
                 TXN_DELETE/DYNAMIC_FILE - twenty lines above - tests dh_delete
                 and raises 1423.  So the shape below is this switch's own, not
                 something imported.

                 AND THE NON-TRANSACTIONAL TWIN IS THE SAME OPCODE.  op_delete()
                 branches at op_dio3.c:380: in a transaction it defers to here,
                 outside one it does the three things copied below.  The same
                 DELETE therefore reported ER_PERM and logged it outside a
                 transaction and could not fail inside one.

                 WHAT THE SILENCE COST: the delete did not happen, clear_parent()
                 ran anyway, the cache was freed, the locks released and the level
                 popped - so the next READ, SELECT or LIST returned a record the
                 administrator had been told was deleted, with nothing in the
                 trail.  It needs no induced fault on Windows: a read-only file,
                 an ACL denial, or a file held open by a scanner is enough.

                 ENOENT IS TOLERATED, exactly as DHE_RECORD_NOT_FOUND is in the
                 dh_delete arm: the record is gone, which is what was asked for. */

              /* 0408 Check that this really is a file, not CON, COMn, LPTn */
              if (!stat(path, &statbuf) && !(statbuf.st_mode & S_IFREG)) {
                process.status = -ER_IID;
                k_error(sysmsg(1423));
                goto exit_op_txncmt;
              }

              if (remove(path) < 0) {
                process.os_error = errno;
                if (process.os_error != ENOENT) {
                  process.status = -ER_PERM;
                  log_permissions_error(fvar);
                  k_error(sysmsg(1423));
                  goto exit_op_txncmt;
                }
              }
            }
            break;
        }

        clear_parent(fvar->file_id, txn->id, txn->id_len);
        break;

      case TXN_CLOSE:
        fvar = txn->fvar;
        if (--(fvar->ref_ct) == 0)
          dio_close(fvar);
        break;
    }

    next_txn = txn->next;
    k_free(txn);
  }

  txn_head = NULL;
  txn_tail = NULL;

  /* If we are synchronising at transaction commit, run down the DH file
    chain, doing an fsync() for each file marked as needing it.          */

  if (pcfg.fsync & 0x0002) {
    for (dh_file = dh_file_head; dh_file != NULL;
         dh_file = dh_file->next_file) {
      if (dh_file->flags & DHF_FSYNC) {
        dh_fsync(dh_file, PRIMARY_SUBFILE);
        dh_fsync(dh_file, OVERFLOW_SUBFILE);
      }
    }
  }

  /* Release all locks acquired during this transaction */

  unlock_txn(commit_txn_id);

  /* 1 Sep 26 Windows port - AND THE COMMIT IS NO LONGER IN FLIGHT.  This clear
     is what keeps txn_abort()'s new release honest: without it commit_txn_id
     would still name the transaction that has just committed successfully, and
     a LATER, UNRELATED abort - a K_TERMINATE or K_LOGOUT, which also reach
     txn_abort() - would call unlock_txn() on an id whose locks are already gone
     and which the allocator may since have handed out again.  PRE_RELEASE 102. */

  commit_txn_id = 0;

  /* 4 Sep 26 Windows port - AND THE BEFORE IMAGES GO WITH IT.
     PRE_RELEASE_FIXES 102.  The commit succeeded, so there is nothing to put
     back; this only releases the captured records.  It is deliberately beside
     the commit_txn_id clear so that the two halves of "no commit is in flight"
     are dropped together - leaving the list behind would arm a later,
     unrelated K_TERMINATE or K_LOGOUT to undo a transaction that committed,
     which is the same shape of bug the commit_txn_id clear exists to stop. */

  free_undo();

  /* 29 Aug 26 Windows port - AND NOW LEAVE THE TRANSACTION LEVEL, WHICH THIS
     FUNCTION NEVER DID.  PRE_RELEASE_FIXES 11, UPSTREAM_FIXES 17.  Without it
     txn_depth only ever climbed (so SYSTEM(1008) was useless) and, far worse, a
     NESTED commit left the outer transaction's cache orphaned on txn_stack -
     process.txn_id was zeroed above, so the outer COMMIT then committed an
     empty cache and its writes vanished with no message.  See end_txn_level().

     DELIBERATELY BEFORE THE LABEL, SO THE ERROR PATHS DO NOT REACH IT.  The
     five "goto exit_op_txncmt" above are write and delete failures that have
     already called k_error(); the transaction is broken at that point and the
     level must not be popped as though it had committed.  (Three until
     1 Sep 26; PRE_RELEASE 101 added the two in the directory-file delete, which
     until then could not fail at all.  Same shape, same reasoning.)

     THAT LEAVES A SEPARATE, PRE-EXISTING GAP AND THIS DOES NOT WIDEN IT: on
     those error paths process.txn_id has already been set to 0 at the top of
     this function, so txn_abort() and op_txnrbk() both test it, find nothing,
     and roll nothing back - the level stays counted and the stack stays
     orphaned.  That is a different defect from this one; it is filed rather
     than fixed here, because a commit that failed half way needs a decision
     about what to do with the records already written, not a decrement.
     PRE_RELEASE 102 tracks it.

     1 Sep 26 - HALF OF THAT GAP IS NOW CLOSED AND THIS PARAGRAPH WOULD
     OTHERWISE READ AS THOUGH NONE OF IT WERE.  txn_abort() releases
     commit_txn_id's record locks, so the failed commit no longer holds them
     for the life of the process; see the comment there for why the fix is on
     the far side of the longjmp rather than at the five call sites.  WHAT IS
     STILL OPEN is the part that needs the ruling: the level stays counted, the
     cache stays orphaned on txn_stack, and the records already written stay
     written.  unlock_txn(commit_txn_id) below still runs on the SUCCESS path
     only, and that is correct - it is the abort path that had nothing.

     1 Sep 26 - AND 101 GIVES THAT GAP TWO MORE WAYS IN, WHICH IS WORTH SAYING
     PLAINLY RATHER THAN LEAVING FOR SOMEBODY TO FIND.  A directory-file delete
     that fails now takes the error path instead of being silently skipped, so
     it lands in the same unrolled-back state the dh_delete arm already could.
     The gap is unchanged in kind and it is reached more often.  That trade was
     made deliberately: the alternative is the commit reporting a deletion that
     did not happen, which is the worse of the two and is why 101 is a B.     */

  end_txn_level();

exit_op_txncmt:
  return;
}

/* ======================================================================
   op_txnend()  -  End transaction                                        */

void op_txnend() {
  if (process.txn_id == 0)
    k_error(sysmsg(1424));

  rollback();
}

/* ======================================================================
   op_txnrbk()  -  Rollback transactions at this or higher command level  */

void op_txnrbk() {
  if ((process.txn_id != 0) && (txn_cproc_level >= cproc_level)) {
    tio_printf(sysmsg(1425));
  }

  while ((process.txn_id != 0) && (txn_cproc_level >= cproc_level)) {
    rollback();
  }
}

/* ======================================================================
   txn_abort()  -  Roll back at abort/logout/terminate/etc                */

void txn_abort() {
  /* 1 Sep 26 Windows port - RELEASE THE LOCKS A FAILED COMMIT LEFT HELD.
     PRE_RELEASE_FIXES 102, UPSTREAM_FIXES 32.

     op_txncmt() saves process.txn_id into commit_txn_id and sets
     process.txn_id to 0 before its loop, so that a close action taken during
     the commit does not recurse.  If a write or delete in that loop then
     fails it calls k_error(), and K_ERROR DOES NOT RETURN - k_error.c sets
     k_exit_cause = K_ABORT and longjmps to the setjmp in kernel.c, which is
     what calls this function.  Everything after the loop is therefore skipped,
     unlock_txn(commit_txn_id) included, and THE LOCKS WERE NEVER RELEASED BY
     ANYTHING: the test below finds process.txn_id == 0 and does nothing, and
     rollback() - the only other caller of unlock_txn() - is not reached
     either.  The records stayed locked for the life of the process, which on a
     server session means until somebody killed it.

     THE FIVE "goto exit_op_txncmt" IN THAT LOOP ARE DEAD CODE, which is why
     the fix cannot go there or at any label after them: k_error() has already
     jumped.  It has to be on the far side of the longjmp, and this is the far
     side.

     AND IT IS HERE RATHER THAN BEFORE EACH k_error() ON PURPOSE.  Guarding the
     five call sites would fix those five; a sixth error path added to the loop
     later would leak again and nothing would say so.  PRE_RELEASE 101 added two
     of the five this way in one day.  One release on the abort path covers the
     loop however it grows, and covers K_TERMINATE and K_LOGOUT too.

     WHAT THIS DELIBERATELY DOES NOT DO: it does not pop the transaction level,
     and it does not touch the records the failed commit already wrote.  A
     half-applied commit needs a ruling on those, which is the other half of
     PRE_RELEASE 102 and is not a decrement.  Releasing the locks does not
     depend on that ruling and should not have waited for it - the partial
     state is already on disk and visible; the locks only stopped anybody
     reaching it, including whoever came to repair it.                        */

  /* 4 Sep 26 Windows port - PUT BACK WHAT THE FAILED COMMIT ALREADY APPLIED,
     BEFORE THE LOCKS GO.  PRE_RELEASE_FIXES 102.

     BEFORE, NOT AFTER, AND THE ORDER IS THE POINT: the records this is about
     to rewrite are the ones the transaction still holds locks on, and they are
     ours to write only until unlock_txn() below gives them up.  Undoing after
     the release would be writing to records another session may already have
     taken.

     It does nothing when the list is empty, which is every abort that did not
     come from a half-applied commit - K_TERMINATE and K_LOGOUT included. */

  replay_undo();

  if (commit_txn_id != 0) {
    unlock_txn(commit_txn_id);
    commit_txn_id = 0;
  }

  if (process.txn_id) {
    tio_printf(sysmsg(1426));
    while (process.txn_id)
      rollback();
  }
}

/* ======================================================================
   txn_close()  -  Close file in transaction                              */

bool txn_close(FILE_VAR* fvar) {
  bool status = FALSE;
  TXN_CACHE* txn;

  fvar->ref_ct++; /* Ensure doesn't really get closed */

  /* Allocate memory for TXN_CACHE entry */

  txn = alloc_txn(0);
  if (txn == NULL)
    goto exit_txn_close;

  txn->mode = TXN_CLOSE;
  txn->fvar = fvar;

  status = TRUE;

exit_txn_close:
  return status;
}

/* ======================================================================
   txn_delete()  -  Delete record via transaction cache                   */

bool txn_delete(FILE_VAR* fvar, char* id, int16_t id_len) {
  bool status = FALSE;
  TXN_CACHE* txn;
  STRING_CHUNK* str;
  int16_t fno;
  FILE_ENTRY* fptr;
  bool nocase;

  /* Scan cache for an existing entry for this file */

  fno = fvar->file_id;
  fptr = FPtr(fno);
  nocase = (fptr->flags & DHF_NOCASE) != 0;

  for (txn = txn_head; txn != NULL; txn = txn->next) {
    if ((txn->fvar->file_id == fno)        /* Right file... */
        && (txn->id_len == id_len)         /* ...right id length... */
        && (IdMatch(txn->id, id, id_len))) /* ...right id */
    {
      switch (txn->mode) {
        case TXN_WRITE: /* Replace write with delete */
          txn->mode = TXN_DELETE;
          if ((str = txn->str) != NULL) {
            if (--(str->ref_ct) == 0)
              s_free(str);
            txn->str = NULL;
          }
          goto exit_txn_delete_ok;

        case TXN_DELETE: /* Deleted twice! */
          goto exit_txn_delete_ok;
      }
    }
  }

  /* Allocate memory for TXN_CACHE entry */

  txn = alloc_txn(id_len);
  if (txn == NULL)
    goto exit_txn_delete;

  txn->mode = TXN_DELETE;
  txn->fvar = fvar;
  txn->id_len = id_len;
  memcpy(txn->id, id, id_len);

exit_txn_delete_ok:
  status = TRUE;

exit_txn_delete:
  return status;
}

/* ======================================================================
   txn_open()  -  Try to reopen a file from the cache                     */

FILE_VAR* txn_open(char* pathname) {
  TXN_CACHE* txn;
  TXN_CACHE* prev_txn = NULL;
  FILE_VAR* fvar;
  FILE_ENTRY* fptr;

  /* Scan for a close for this file */

  for (txn = txn_head; txn != NULL; txn = txn->next) {
    if (txn->mode == TXN_CLOSE) {
      fvar = txn->fvar;
      fptr = FPtr(fvar->file_id);
      if (!strcmp((char*)(fptr->pathname), pathname)) /* Right file */
      {
        /* We have found the right file. The VOC name may be wrong but this
          will be fixed by the caller. All we are trying to do is avoid
          creating a new fvar from scratch as this could leave us with a
          cache chain packed full of close/open pairs (e.g. TRANS() loop)  */

        /* Remove the close entry for this file */

        if (prev_txn == NULL)
          txn_head = txn->next;
        else
          prev_txn->next = txn->next;
        if (txn == txn_tail)
          txn_tail = prev_txn;

        /* The fvar reference count still reflects the old open */

        return fvar;
      }
    }

    prev_txn = txn;
  }

  return NULL;
}

/* ======================================================================
   txn_read()  -  Attempt to read record from cache

   It is the caller's responsibility to increment the string reference
   count if the string is to be retained.                                  */

int16_t txn_read(FILE_VAR* fvar,
                   char* id,
                   int16_t id_len,
                   char* actual_id,
                   STRING_CHUNK** str) {
  int16_t status = 0;
  TXN_CACHE* head;
  TXN_STACK* stack;
  TXN_CACHE* txn;
  int16_t fno;
  FILE_ENTRY* fptr;
  bool nocase;

  fno = fvar->file_id;
  fptr = FPtr(fno);
  nocase = (fptr->flags & DHF_NOCASE) != 0;

  head = txn_head;
  stack = txn_stack;
  while (1) {
    for (txn = head; txn != NULL; txn = txn->next) {
      if ((txn->fvar->file_id == fno)        /* Right file... */
          && (txn->id_len == id_len)         /* ...right id length... */
          && (IdMatch(txn->id, id, id_len))) /* ...right id */
      {
        switch (txn->mode) {
          case TXN_WRITE:
            status = TXC_FOUND;
            memcpy(actual_id, txn->id, id_len);
            *str = txn->str;
            goto exit_txn_read;

          case TXN_DELETE:
            status = TXC_DELETED;
            memcpy(actual_id, txn->id, id_len);
            goto exit_txn_read;
        }
      }
    }

    if (status)
      break; /* Found in this transaction */

    if (stack == NULL)
      break;                /* Not nested */
    head = stack->txn_head; /* Drop down to parent transaction */
    stack = stack->next;
  }

exit_txn_read:
  return status;
}

/* ======================================================================
   txn_write()  -  Write record to transaction cache                      */

bool txn_write(FILE_VAR* fvar, char* id, int16_t id_len, STRING_CHUNK* str) {
  bool status = FALSE;
  TXN_CACHE* txn;
  STRING_CHUNK* old_str;
  int16_t fno;
  FILE_ENTRY* fptr;
  bool nocase;

  /* Scan cache for an existing entry for this file */

  fno = fvar->file_id;
  fptr = FPtr(fno);
  nocase = (fptr->flags & DHF_NOCASE) != 0;

  for (txn = txn_head; txn != NULL; txn = txn->next) {
    if ((txn->fvar->file_id == fno)        /* Right file... */
        && (txn->id_len == id_len)         /* ...right id length... */
        && (IdMatch(txn->id, id, id_len))) /* ...right id */
    {
      switch (txn->mode) {
        case TXN_WRITE: /* Replace write new write */
          if ((old_str = txn->str) != NULL) {
            if (--(old_str->ref_ct) == 0)
              s_free(old_str);
          }
          txn->str = str;
          goto exit_txn_write_ok;

        case TXN_DELETE: /* Replace delete with write */
          txn->mode = TXN_WRITE;
          txn->str = str;
          if (str != NULL)
            str->ref_ct++;
          goto exit_txn_write_ok;
      }
    }
  }

  /* Allocate memory for TXN_CACHE entry */

  txn = alloc_txn(id_len);
  if (txn == NULL)
    goto exit_txn_write;

  txn->mode = TXN_WRITE;
  txn->fvar = fvar;
  txn->str = str;
  if (str != NULL)
    str->ref_ct++;
  txn->id_len = id_len;
  memcpy(txn->id, id, id_len);

exit_txn_write_ok:
  status = TRUE;

exit_txn_write:
  return status;
}

/* ======================================================================
   alloc_txn()  -  Allocate transaction cache entry                       */

Private TXN_CACHE* alloc_txn(int16_t id_len) {
  TXN_CACHE* txn;
  int bytes;

  bytes = sizeof(TXN_CACHE) + id_len;
  txn = (TXN_CACHE*)k_alloc(21, bytes);
  if (txn == NULL)
    process.status = -ER_MEM;
  else {
    memset(txn, 0, bytes);

    /* Add to chain */

    if (txn_head == NULL)
      txn_head = txn;
    else
      txn_tail->next = txn;
    txn_tail = txn;
  }

  return txn;
}

/* ======================================================================
   rollback()  -  Roll back top level transaction                         */

Private void rollback() {
  TXN_CACHE* txn;
  TXN_CACHE* next_txn;
  FILE_VAR* fvar;
  STRING_CHUNK* str;
  u_int32_t saved_txn_id;

  /* Remove all uncommitted actions */

  for (txn = txn_head; txn != NULL; txn = next_txn) {
    switch (txn->mode) {
      case TXN_WRITE:
        if (((str = txn->str) != NULL) && (--(str->ref_ct) == 0))
          s_free(str);
        break;

      case TXN_DELETE:
        break;

      case TXN_CLOSE:
        fvar = txn->fvar;
        if (--(fvar->ref_ct) == 0) {
          saved_txn_id = process.txn_id; /* 0468 */
          process.txn_id = 0;
          dio_close(fvar);
          process.txn_id = saved_txn_id;
        }
        break;
    }

    next_txn = txn->next;
    k_free(txn);
  }

  txn_head = NULL;
  txn_tail = NULL;

  /* Release all locks acquired during this transaction */

  unlock_txn(process.txn_id);

  /* Exit from this transaction */

  end_txn_level();
}

/* ======================================================================
   end_txn_level()  -  Leave one transaction level, reinstating the parent

   29 Aug 26 Windows port - LIFTED OUT OF rollback() SO THAT COMMIT CAN DO IT
   TOO.  PRE_RELEASE_FIXES 11, UPSTREAM_FIXES 17.

   THE BUG THIS FIXES WAS THAT ONLY ONE PATH DID THIS.  op_txnbgn() does two
   things - it increments txn_depth, and if a transaction is already running it
   pushes that one onto txn_stack.  rollback() undid both; op_txncmt() undid
   NEITHER, and BCOMP's st.commit jumps past the OP.TXNEND that would have
   called rollback(), so on the committed path nothing ever reversed them.

   TWO SYMPTOMS, AND THE SECOND IS THE ONE THAT MATTERS.  SYSTEM(1008) climbed
   for ever, so a program could not ask "am I in a transaction"; and a NESTED
   commit set process.txn_id = 0 while leaving the outer transaction's cache
   orphaned on txn_stack, so the outer COMMIT then committed an EMPTY cache and
   its writes were lost with no message.  Part of a transaction landing and
   part not is the one outcome a transaction exists to prevent.

   IT IS ONE FUNCTION RATHER THAN TWO COPIES BECAUSE THE DEFECT WAS EXACTLY
   THAT THE BOOKKEEPING LIVED IN ONE PLACE AND ONE CALLER.  A second copy in
   op_txncmt() would be the same shape of thing waiting to drift again.

   THE unlock STAYS WITH THE CALLER and is not moved in here, because the two
   pass different ids: rollback() unlocks process.txn_id, which is still the
   running transaction at that point, while op_txncmt() has already zeroed
   process.txn_id (so the close action does not loop) and unlocks the saved
   commit_txn_id.  Folding that in would have to re-derive which id to use,
   which is how a shared helper becomes wrong for one of its callers.        */

Private void end_txn_level() {
  TXN_STACK* stk;

  if ((stk = txn_stack) != NULL) /* Reinstate nested transaction */
  {
    process.txn_id = stk->txn_id;
    txn_cproc_level = stk->cproc_level;
    journalled_txn = stk->journalled_txn;
    txn_head = stk->txn_head;
    txn_tail = stk->txn_tail;
    txn_stack = stk->next;
    k_free(stk);
  } else
    process.txn_id = 0;

  txn_depth--;
}

/* ======================================================================
   capture_undo()  -  Take the before image of one record, at commit time

   4 Sep 26 Windows port - PRE_RELEASE_FIXES 102.  Called from op_txncmt()'s
   loop IMMEDIATELY BEFORE each action is applied, which is the only moment the
   image is certainly the one about to be overwritten.

   ***IT MUST BE INVISIBLE TO THE CALLER, AND THAT IS NOT A DETAIL.***  It reads
   a record, so it sets process.status, process.os_error and dh_err on its way
   past - and the caller is about to apply an action whose failure is reported
   through exactly those.  A capture that succeeded would otherwise leave
   ER_RNF sitting in process.status and the commit's own error would be
   described by this function's last read.  All three are saved and restored.

   NOT FINDING THE RECORD IS THE NORMAL CASE FOR A NEW ONE and is not a
   failure: it becomes UNDO_DELETE, so the undo removes what the commit was
   about to create.  Only a read that failed for some OTHER reason is
   UNDO_UNREADABLE.  A caller that could not tell those apart would either
   resurrect a record that never existed or leave one it should have removed.

   AN ALLOCATION FAILURE IS LOGGED AND THE COMMIT CONTINUES.  Refusing the
   commit here would turn a memory shortage into a failed transaction on a path
   that works today; the record says which record cannot be undone instead.  */

Private void capture_undo(FILE_VAR* fvar, char* id, int16_t id_len) {
  TXN_UNDO* u;
  STRING_CHUNK* str = NULL;
  int16_t mode;
  int16_t status;
  char actual_id[MAX_ID_LEN + 1];
  char mapped_id[2 * MAX_ID_LEN + 1];
  char msg[MAX_PATHNAME_LEN + MAX_ID_LEN + 80];
  int bytes;

  int16_t saved_status = process.status;
  int32_t saved_os_error = process.os_error;
  int16_t saved_dh_err = dh_err;

  switch (fvar->type) {
    case DYNAMIC_FILE:
      /* An EMPTY record returns NULL with dh_err 0, which is a record that
         exists and holds nothing - not an absent one.  Test dh_err, never the
         pointer. */
      str = dh_read(fvar->access.dh.dh_file, id, id_len, actual_id);
      if (dh_err == 0)
        mode = UNDO_RESTORE;
      else if (dh_err == DHE_RECORD_NOT_FOUND)
        mode = UNDO_DELETE;
      else
        mode = UNDO_UNREADABLE;
      break;

    case DIRECTORY_FILE:
      /* The id is mapped here for the same reason PRE_RELEASE 154 maps it in
         the commit loop: the cache holds the raw id and the disk is called by
         the mapped one. */
      if (!map_t1_id(id, id_len, mapped_id))
        mode = UNDO_UNREADABLE;
      else if (dir_read(fvar, mapped_id, &str, &status))
        mode = UNDO_RESTORE;
      else if (process.status == ER_RNF)
        mode = UNDO_DELETE;
      else
        mode = UNDO_UNREADABLE;
      break;

    default:
      goto exit_capture_undo; /* nothing on disk to put back */
  }

  bytes = sizeof(TXN_UNDO) + id_len;
  u = (TXN_UNDO*)k_alloc(82, bytes);
  if (u == NULL) {
    snprintf(msg, sizeof(msg),
             "Transaction commit: no memory to record the prior content of "
             "record '%.*s' in %s - it cannot be undone if the commit fails",
             (int)id_len, id, (char*)(FPtr(fvar->file_id)->pathname));
    log_message(msg);
    if ((str != NULL) && (--(str->ref_ct) == 0))
      s_free(str);
    goto exit_capture_undo;
  }

  memset(u, 0, bytes);
  u->mode = mode;
  u->fvar = fvar;
  u->id_len = id_len;
  memcpy(u->id, id, id_len);

  if (mode == UNDO_RESTORE) {
    u->str = str; /* dh_read/dir_read hand it over at ref_ct 1 */
  } else if ((str != NULL) && (--(str->ref_ct) == 0)) {
    s_free(str);
  }

  /* PUSHED, NOT APPENDED.  Walking head to tail is then already reverse order,
     which is what an undo has to be. */
  u->next = undo_head;
  undo_head = u;

exit_capture_undo:
  process.status = saved_status;
  process.os_error = saved_os_error;
  dh_err = saved_dh_err;
}

/* ======================================================================
   replay_undo()  -  Put back what a failed commit had already applied

   4 Sep 26 Windows port - PRE_RELEASE_FIXES 102.  Called from txn_abort(),
   which is THE FAR SIDE OF THE LONGJMP - the same placement the lock half
   uses, and for the same reason: k_error() does not return, so the five
   "goto exit_op_txncmt" in the commit loop are dead code and nothing after
   them in that function can run.

   ***IT MUST NOT RAISE.***  The disk is already misbehaving - that is why the
   commit failed - and a k_error() here would longjmp out of the abort handler
   itself.  So every failure is logged and the walk continues: the entry's own
   rule is "log every failed restore by file and id, finish undoing the rest,
   and leave the transaction reported as failed".

   ONE ACKNOWLEDGED EDGE, WRITTEN DOWN RATHER THAN WISHED AWAY: dir_write(),
   dh_write() and t1_buffer_alloc() can themselves k_error() - on a path
   overflow, on an alternate-key update, or on memory exhaustion.  The overflow
   cannot fire here (the same path was built from the same pathname and id
   moments earlier, when the commit applied it) but the other two genuinely
   can.  Reimplementing either writer to avoid it would mean a second copy of a
   write path, which is the trade this file has already refused once for the
   mark mapping.

   ***THE RECORD THE COMMIT FAILED ON IS RESTORED TOO, AND THAT IS DELIBERATE
   RATHER THAN AN OVERSIGHT.***  capture_undo() runs before EVERY action,
   including the one that then fails, because a write that fails PART WAY has
   left the record in a state nobody can describe - and "the action failed" is
   not the same claim as "the record is untouched".  Restoring it is the only
   answer that is right in both cases.

   IT ALSO MEANS THE LOG CAN NAME THAT RECORD AS "COULD NOT BE UNDONE" WHEN IT
   WAS NEVER DAMAGED, and the witness of 4 Sep 2026 did exactly that: the
   delete failed because the file was held open, so the restore was refused for
   the same reason, and the summary read "2 restored, 2 removed, 1 could not be
   undone" over a record that was provably intact.  ***THAT IS THE SAFE
   DIRECTION AND IT IS NOT WORTH SUPPRESSING.***  Reporting a record whose
   state we could not guarantee costs a line in the errlog; staying quiet about
   one we could not put back costs the operator the only notice they get.

   IT ALSO RUNS FOR K_TERMINATE AND K_LOGOUT, which reach txn_abort() too, and
   does nothing at all when the list is empty - which is every abort that did
   not come from a half-applied commit.                                      */

Private void replay_undo(void) {
  TXN_UNDO* u;
  TXN_UNDO* next;
  FILE_VAR* fvar;
  FILE_ENTRY* fptr;
  char mapped_id[2 * MAX_ID_LEN + 1];
  char path[MAX_PATHNAME_LEN + 1];
  char msg[MAX_PATHNAME_LEN + MAX_ID_LEN + 120];
  int restored = 0;
  int removed = 0;
  int failed = 0;
  bool ok;

  if (undo_head == NULL)
    return;

  for (u = undo_head; u != NULL; u = next) {
    next = u->next;
    fvar = u->fvar;
    fptr = FPtr(fvar->file_id);
    ok = TRUE;

    switch (u->mode) {
      case UNDO_RESTORE:
        switch (fvar->type) {
          case DYNAMIC_FILE:
            ok = dh_write(fvar->access.dh.dh_file, u->id, u->id_len, u->str);
            break;

          case DIRECTORY_FILE:
            if (!map_t1_id(u->id, u->id_len, mapped_id))
              ok = FALSE;
            else
              ok = dir_write(fvar, mapped_id, u->str);
            break;

          default:
            ok = FALSE;
            break;
        }
        if (ok)
          restored++;
        break;

      case UNDO_DELETE:
        switch (fvar->type) {
          case DYNAMIC_FILE:
            /* Already absent is the outcome asked for, not a failure - the
               same tolerance the commit's own delete arm applies. */
            if (!dh_delete(fvar->access.dh.dh_file, u->id, u->id_len) &&
                (dh_err != DHE_RECORD_NOT_FOUND))
              ok = FALSE;
            break;

          case DIRECTORY_FILE:
            if (!map_t1_id(u->id, u->id_len, mapped_id)) {
              ok = FALSE;
            } else if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s%c%s",
                                fptr->pathname, DS,
                                mapped_id) >= (MAX_PATHNAME_LEN + 1)) {
              ok = FALSE;
            } else if ((remove(path) < 0) && (errno != ENOENT)) {
              ok = FALSE;
            }
            break;

          default:
            ok = FALSE;
            break;
        }
        if (ok)
          removed++;
        break;

      case UNDO_UNREADABLE:
        ok = FALSE;
        break;
    }

    if (!ok) {
      failed++;
      snprintf(msg, sizeof(msg),
               "Transaction commit failed and record '%.*s' in %s could not be "
               "put back as it was (%s)",
               (int)u->id_len, u->id, (char*)(fptr->pathname),
               (u->mode == UNDO_UNREADABLE) ? "its prior content could not be read"
                                            : "the undo itself failed");
      log_message(msg);
    }

    if ((u->str != NULL) && (--(u->str->ref_ct) == 0))
      s_free(u->str);
    k_free(u);
  }

  undo_head = NULL;

  /* ***SAY WHAT WAS DONE EVEN WHEN IT ALL WORKED.***  A transaction that
     failed and was fully undone is still a transaction that failed, and the
     operator has no other way to learn that the disk was touched and put back.
     A verdict with no record of what it did is the thing the house rules
     refuse.  (A user-visible message would need a sysmsg number and the
     owner's word; the errlog is what this entry's design asked for.) */

  snprintf(msg, sizeof(msg),
           "Transaction commit failed part way: %d record(s) restored, "
           "%d removed, %d could not be undone",
           restored, removed, failed);
  log_message(msg);
}

/* ======================================================================
   free_undo()  -  Discard the before images after a commit that succeeded

   4 Sep 26 Windows port - PRE_RELEASE_FIXES 102.  Nothing is undone here; the
   images are simply no longer needed.  Called where commit_txn_id is cleared,
   so that the two pieces of "this commit is no longer in flight" state are
   dropped together and neither can be left behind for a later, unrelated
   abort to act on.                                                          */

Private void free_undo(void) {
  TXN_UNDO* u;
  TXN_UNDO* next;

  for (u = undo_head; u != NULL; u = next) {
    next = u->next;
    if ((u->str != NULL) && (--(u->str->ref_ct) == 0))
      s_free(u->str);
    k_free(u);
  }

  undo_head = NULL;
}

/* ======================================================================
   clear_parent()  -  Clear references to record from parent txns         */

Private void clear_parent(int16_t fno,    /* File number */
                          char* id,         /* Record id and... */
                          int16_t id_len) /* ...id length */
{
  TXN_STACK* stack;
  TXN_CACHE* txn;
  TXN_CACHE* prev;
  TXN_CACHE* next;
  STRING_CHUNK* str;
  FILE_ENTRY* fptr;
  bool nocase;

  fptr = FPtr(fno);
  nocase = (fptr->flags & DHF_NOCASE) != 0;

  /* Modified by Composer AI - 2026/06/10.
     Use-after-free: when an entry was dechained and k_free'd, the for
     loop update clause still executed "prev = txn", leaving prev
     pointing at freed memory; a later removal in the same scan then
     wrote through it ("prev->next = ..."). Only advance prev when the
     current entry was NOT removed. */
  /* for (stack = txn_stack; stack != NULL; stack = stack->next) {
    prev = NULL;
    for (txn = stack->txn_head; txn != NULL; prev = txn, txn = next) {
      next = txn->next;
      switch (txn->mode) {
        case TXN_WRITE:
        case TXN_DELETE:
          if ((txn->fvar->file_id == fno) && (txn->id_len == id_len) &&
              (IdMatch(txn->id, id, id_len))) {
            if (txn->mode == TXN_WRITE) {
              if (((str = txn->str) != NULL) && (--(str->ref_ct) == 0))
                s_free(str);
            }

            / * Dechain this entry * /

            if (prev == NULL)
              stack->txn_head = txn->next;
            else
              prev->next = txn->next;
            if (txn->next == NULL)
              stack->txn_tail = prev;
            k_free(txn);
          }
          break;
      }
    }
  } */
  for (stack = txn_stack; stack != NULL; stack = stack->next) {
    prev = NULL;
    for (txn = stack->txn_head; txn != NULL; txn = next) {
      bool removed = FALSE;

      next = txn->next;
      switch (txn->mode) {
        case TXN_WRITE:
        case TXN_DELETE:
          if ((txn->fvar->file_id == fno) && (txn->id_len == id_len) &&
              (IdMatch(txn->id, id, id_len))) {
            if (txn->mode == TXN_WRITE) {
              if (((str = txn->str) != NULL) && (--(str->ref_ct) == 0))
                s_free(str);
            }

            /* Dechain this entry */

            if (prev == NULL)
              stack->txn_head = txn->next;
            else
              prev->next = txn->next;
            if (txn->next == NULL)
              stack->txn_tail = prev;
            k_free(txn);
            removed = TRUE;
          }
          break;
      }
      if (!removed)
        prev = txn;
    }
  }
  /* -------------------- */
}

/* END-CODE */
