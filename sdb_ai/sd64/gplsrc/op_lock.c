/* OP_LOCK.C
 * Lock management opcodes
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
 * 25 Oct 26 Windows port - from Linux eb9ef4a (20 Oct 26) S.72b: op_reclckd() of a NET_FILE is refused for a read mode one (message 12506, nothing sent) inside net_recordlocked; the server
 *               refuses request 34 to a login without sdfileswrite.
 * 25 Oct 26 Windows port - from Linux fc8e304 (20 Oct 26) S.72 (QMNet parity, tiers A and B): op_filelock() and op_flunlock() act on a write mode NET_FILE (net_filelock_step,
 *               net_fileunlock; a read mode one is still refused with 12506), op_reclckd() asks the server for any NET_FILE (net_recordlocked) and op_getlocks() gives a NET_FILE
 *               the local view - the counters and no lock line (NO_LOCAL_FILE).  LOCK.TRACER is not carried here.
 * 25 Oct 26 Windows port - from Linux 5315c65 (18 Oct 26) S.65 slice 3e: op_lockrec(), op_release(), op_rlsfile() and op_rlsall() act on a write mode NET_FILE (net_gate, net_lock_step,
 *               net_release, net_release_all); a read mode one is refused as in slice 3c.
 * 18 Oct 26 Windows port - from Linux b51c637 (16 Oct 26): OPTION COMMAND.LEVEL.LOCKS (QM4 gap 231): park_fvar(), release_parked_fvars()
 * 11 Sep 26 Windows port - RELEASE_1.1_FIXES.md 7.  op_getlocks() passed the
 *           result of UserPtr() straight into ts_printf() without testing it
 *           for NULL, so GETLOCKS and LIST.READU faulted on a lock whose
 *           owner's session had gone.  Found by SD Core for Linux, which
 *           measured the fault there; the two deadlock loops in this same
 *           file were already guarded in June 2026 and these two sites were
 *           missed.  Now goes through lock_owner_name().
 * 17 Oct 26 Windows port - from Linux e7ea5f8 - S.65 slice 3c: FILELOCK, FILEUNLOCK, GETLOCKS, RECORDLOCKU/L, RECORDLOCKED, RELEASE of a NET_FILE are refused (net_refuse); lock_record, check_lock, unlock_record guard NET_FILE
 * 16 Oct 26 Windows port - from Linux e7ea5f8 - OPTION COMMAND.LEVEL.LOCKS (QM4 gap 231): park_fvar(), release_parked_fvars()
 * 18 Oct 26 Windows port - from Linux 5315c65 - S.65 slice 3e: op_lockrec(), op_release(), op_rlsfile() and op_rlsall() act on a write mode NET_FILE (net_gate, net_lock_step, net_release, net_release_all); a read mode one is refused as before
 * 17 Oct 26 Windows port - from Linux 5315c65 - S.65 slice 3c: FILELOCK, FILEUNLOCK, GETLOCKS, RECORDLOCKU/L, RECORDLOCKED, RELEASE of a NET_FILE are refused (net_refuse); lock_record, check_lock, unlock_record guard NET_FILE
 * 16 Oct 26 Windows port - from Linux 5315c65 - OPTION COMMAND.LEVEL.LOCKS (QM4 gap 231): park_fvar(), release_parked_fvars()
 * 20 Oct 26 Windows port - from Linux fc8e304 - S.72 (QMNet parity, tiers A and B): op_filelock() and op_flunlock() act on a write mode NET_FILE (net_filelock_step, net_fileunlock; a read mode one is still refused with
 *               12506), op_reclckd() asks the server for any NET_FILE (net_recordlocked) and op_getlocks() gives a NET_FILE the local view - the counters and no lock line (NO_LOCAL_FILE)
 * 31 Dec 23 SD launch - prior history suppressed
 * 18 Oct 26 Windows port - from Linux 916c2cd (12 Oct 26): openQM items 487, 500 and 587: the time each record lock, file
 *               lock and lock wait began is kept and GETLOCKS() returns it as
 *               a seventh value; DEADLOCK=2 saves the state of the locks as
 *               deadlock.n; SYSTEM(1083) returns the processes of the last
 *               deadlock.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Opcodes:
 *    op_filelock       FILELOCK
 *    op_flunlock       FLUNLOCK
 *    op_getlocks       GETLOCKS()
 *    op_llock          LLOCK
 *    op_lock           LOCK
 *    op_lockrec        RECORDLOCKL/U
 *    op_nowait         NOWAIT
 *    op_reclckd        RECORDLOCKED()
 *    op_release        RELEASE
 *    op_rlsall         RLSALL
 *    op_rlsfile        RLSFILE
 *    op_testlock       TESTLOCK()
 *    op_ulock          ULOCK
 *    op_unlock         UNLOCK
 *
 *    lock_record
 *    unlock_record
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "locks.h"
#include "keys.h"
#include "header.h"
#include "config.h" /* pcfg.maxrlock */
#include "tio.h"
#include "options.h" /* OPTION COMMAND.LEVEL.LOCKS */

#include <time.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>

Private bool unlock_id(int16_t file_id, char* raw_id, int16_t id_len);
Private char* lock_owner_name(int16_t user_no);

/* 20 Oct 26 S.72 (Linux fc8e304): the file id GETLOCKS() is given for a file on another server.  File ids start at 1 (FPtr(1)), so no lock, file lock or waiter in this machine's tables carries it,
   and -1 stays "every file". */
#define NO_LOCAL_FILE 0

/* ======================================================================
   op_filelock()  -  Set file lock                                        */

void op_filelock() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  File variable              |  0 = success, <0 = error    |
     |                             |  ER$LCK = Already locked    |
     |=============================|=============================|

  The ON ERROR clause is currently never taken.

  ER$LCK is only returned if LOCKED clause is present. Otherwise the opcode
  waits for the lock to become available.
 */

  DESCRIPTOR* descr;
  u_int16_t op_flags;
  int16_t status = 0;
  int16_t lock_owner;
  FILE_ENTRY* fptr;
  RLOCK_ENTRY* lptr;
  int16_t idx;
  int16_t file_id;
  FILE_VAR* fvar;
  u_char* retry_pc = op_pc; /* 20 Oct 26 S.72: taken before any net_ call; the handler's own opcodes overwrite op_pc */

  op_flags = process.op_flags;

  descr = e_stack - 1;
  k_get_file(descr);
  fvar = descr->data.fvar;

  if (fvar->type == NET_FILE) /* 20 Oct 26 S.72: a remote file has no entry in the file table; the lock is asked of the server (write-mode handle only) */
  {
    /* net_filelock_step() asks net_gate() first (a read-mode handle is refused with 12506, a transaction with 12515), then sends the no-wait request.  A busy file without a LOCKED
       clause is asked for again in 250 ms: the step has set this opcode up to run again (pc = retry_pc) and we return at once, leaving the operand on the stack.  The handler runs
       BASIC, so nothing may be found by a pointer taken before the call: k_dismiss() works from e_stack. */

    switch (status = (int16_t)net_filelock_step(fvar, op_flags, retry_pc)) {
      case NET_LOCK_HELD:
        status = 0;
        break;

      case NET_LOCK_WAIT: /* the opcode will be run again; process.op_flags was left as it was found */
        return;

      case NET_LOCK_LOCKED: /* process.status is the holder's user number on the server */
        status = ER_LCK;
        break;

      default: /* an error; process.status is set and the error was raised unless ON ERROR */
        status = (int16_t)process.status;
        break;
    }

    process.op_flags = 0;
    k_dismiss();
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = status;
    return;
  }

  {
    file_id = fvar->file_id;
    fptr = FPtr(file_id);

    StartExclusive(REC_LOCK_SEM, 36);

    if ((lock_owner = fptr->file_lock) != 0) {
      if (lock_owner == process.user_no) /* File lock is held by us */
      {
        fptr->txn_id = process.txn_id;
        goto locked_it; /* Already hold the lock */
      } else {
        goto wait_lock;
      }
    }

    if (fptr->lock_count == 0) /* No locks in this file */
    {
      fptr->file_lock = process.user_no;
      fptr->file_lock_time = (int32_t)time(NULL);
      fptr->fvar_index = fvar->index;
      fptr->txn_id = process.txn_id;
      goto locked_it;
    }

    /* Check that all record locks are held by us */

    for (idx = 1; idx <= sysseg->numlocks; idx++) {
      lptr = RLPtr(idx);
      if ((lptr->hash != 0)                    /* Cell used... */
          && (lptr->file_id == file_id)        /* ...for this file... */
          && (lptr->owner != process.user_no)) /* ...by another user */
      {
        lock_owner = lptr->owner;
        goto wait_lock;
      }
    }

    fptr->file_lock = process.user_no;
    fptr->file_lock_time = (int32_t)time(NULL);
    fptr->fvar_index = fvar->index;
    fptr->txn_id = process.txn_id;
    goto locked_it;

    /* The lock is in use. Wait for the lock? */

  wait_lock:
    if (!(op_flags & P_LOCKED)) {
      /* Set up lock wait information.  The time is when the wait began, so it
        is set only on the first of the retries. */

      if (my_uptr->lockwait_index == 0)
        my_uptr->lockwait_time = (int32_t)time(NULL);
      my_uptr->lockwait_index = -(fvar->file_id);
      EndExclusive(REC_LOCK_SEM);
      if (my_uptr->events)
        process_events();
      pc--; /* Back up to repeat opcode */
      lock_beep();
      Sleep(250);
      return;
    }

    status = ER_LCK; /* Take the LOCKED clause */
    process.status = lock_owner;

  locked_it:
    my_uptr->lockwait_index = 0;
    EndExclusive(REC_LOCK_SEM);
  }

  process.op_flags = 0;
  k_dismiss();

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;
}

/* ======================================================================
   op_flunlock()  -  Release file lock                                    */

void op_flunlock() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  File variable              |  0 = success, <0 = error    |
     |=============================|=============================|

  The ON ERROR clause is currently never taken.
 */

  DESCRIPTOR* descr;
  FILE_VAR* fvar;
  FILE_ENTRY* fptr;
  int16_t lock_owner;
  int16_t file_id;
  u_int16_t op_flags = process.op_flags; /* 20 Oct 26 S.72: P_ON_ERROR, for a remote file; a local FILEUNLOCK never took it */

  descr = e_stack - 1;
  k_get_file(descr);
  fvar = descr->data.fvar;

  if (fvar->type == NET_FILE) /* 20 Oct 26 S.72: net_fileunlock() asks the gate (12506, 12515) and then the server; it answers 0, ER_LCK or ER_NLK as a local FILEUNLOCK leaves them */
  {
    int net_status = net_fileunlock(fvar, op_flags); /* the handler runs BASIC: the stack is found by e_stack from here on */

    process.op_flags = 0;
    k_dismiss();
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = (int16_t)net_status;
    return;
  }

  {
    file_id = fvar->file_id;
    fptr = FPtr(file_id);
    if ((lock_owner = fptr->file_lock) == process.user_no) {
      StartExclusive(REC_LOCK_SEM, 56);
      fptr->file_lock = 0;
      clear_waiters(-file_id);
      EndExclusive(REC_LOCK_SEM);
      process.status = 0;
    } else if (lock_owner != 0) {
      process.status = ER_LCK;
    } else {
      process.status = ER_NLK;
    }
  }

  k_dismiss();
  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = process.status;
}

/* ======================================================================
   lock_owner_name()  -  Login name of a lock's owner, for the reports

   11 Sep 26 Windows port - RELEASE_1.1_FIXES.md 7.

   UserPtr() yields NULL for a user number that is no longer mapped
   (sysseg.h), and a lock can outlive its owner's session: the user table
   slot is released while the lock entry still names that number.  The two
   report loops below then formatted a NULL as %s.

   A lock with no live owner is a normal state to REPORT, not an error, so
   this answers with a placeholder rather than refusing.  "(gone)" is the
   wording SD Core for Linux chose for the same fix; the two ports print the
   same thing on purpose.

   The callers hold FILE_TABLE_LOCK and REC_LOCK_SEM, which is why this
   matters more than the missing line suggests - a fault here left both held
   on Linux and stopped every session.                                     */

Private char* lock_owner_name(int16_t user_no) {
  USER_ENTRY* uptr;

  /* The cast drops the volatile qualifier the shared user table carries.
     It is what clopts.c:183 already does with the same field, and the two
     call sites below did it implicitly by passing username to ts_printf. */
  uptr = UserPtr(user_no);
  return (uptr != NULL) ? (char*)(uptr->username) : "(gone)";
}

/* ======================================================================
   op_getlocks()  -  GETLOCKS() function                                  */

void op_getlocks() {
  /* Stack:

     |===============================|===============================|
     |            BEFORE             |             AFTER             |
     |===============================|===============================|
 top |  User no, zero if all         |  Result list                  |
     |-------------------------------|-------------------------------|
     |  File var. All if not a file  |                               |
     |===============================|===============================|

 The first field of the result contains record lock statistics:
     numlocks VM current count VM peak locks
 The remainder of the result list is a string formatted as:
     file_id VM file path VM userno VM type VM id VM username VM time FM file path....
     Time is time() (seconds since 1 Jan 1970 UTC) when the lock was acquired,
     or, for type WAIT, when the wait began (openQM item 487).
     Type = RU, RL, FX or SX
     Id is absent for file lock
     Multiple locks for a single file are not merged
     Locks are only reported for the specified user / file
 */

  DESCRIPTOR* descr;
  int16_t file_id; /* File to report, -ve if all */
  int16_t user;    /* User to report, zero if all */
  STRING_CHUNK* str_head = NULL;
  FILE_ENTRY* fptr;
  RLOCK_ENTRY* rlptr;
  int16_t lock_owner;
  int16_t i;
  USER_ENTRY* uptr;
  int16_t j;
  int16_t lo;
  int16_t hi;

  /* Get user number, zero if to report all users */

  descr = e_stack - 1;
  GetInt(descr);
  user = (int16_t)(descr->data.value);

  /* Get file variable. Report all files if it is not a file var */

  descr = e_stack - 2;
  k_get_value(descr);
  if (descr->type == FILE_REF) {
    /* 17 Oct 26 S.65: file_id -1 means "all files" here, so a remote file would list every lock of every user.
       20 Oct 26 S.72 (QMNet parity): GETLOCKS() of a remote file is the LOCAL view, as openQM documents - the locks of a remote file are held on the server and never appear in this
       machine's lock table - so it reports the counters of field 1 and no lock line, and asks the server nothing.  NO_LOCAL_FILE names no file, so the three loops below find nothing. */
    if (descr->data.fvar->type == NET_FILE)
      file_id = NO_LOCAL_FILE;
    else
      file_id = descr->data.fvar->file_id;
  } else {
    file_id = -1;
  }

  /* Generate result string */

  ts_init(&str_head, 64);

  /* We hold the file table lock throughout so that file ids are guaranteed
    not to change during the report. The file_lock entry in the file table
    is actually protected by the REC_LOCK_SEM so we get this up front too. */

  StartExclusive(FILE_TABLE_LOCK, 27);
  StartExclusive(REC_LOCK_SEM, 28);

  /* Counters */

  ts_printf("%d\xfd%d\xfd%d", sysseg->numlocks, sysseg->rl_count,
            sysseg->rl_peak);

  /* File locks */

  for (i = 1, fptr = FPtr(1); i <= sysseg->used_files; i++, fptr++) {
    if (fptr->file_lock != 0) {
      lock_owner = abs(fptr->file_lock);
      if (((file_id < 0) || (i == file_id)) &&
          ((user == 0) || (user == abs(lock_owner)))) {
        ts_copy_byte(FIELD_MARK);
        ts_printf("%d\xfd%s\xfd%d\xfd%s\xfd\xfd%s\xfd%d", (int)i, fptr->pathname,
                  (int)abs(lock_owner), (lock_owner < 0) ? "SX" : "FX",
                  lock_owner_name(abs(lock_owner)), (int)(fptr->file_lock_time));
      }
    }
  }

  /* Record locks */

  for (i = 1; i <= sysseg->numlocks; i++) {
    rlptr = RLPtr(i);
    if (rlptr->hash != 0) {
      lock_owner = rlptr->owner;
      if (((file_id < 0) || (rlptr->file_id == file_id)) &&
          ((user == 0) || (user == lock_owner))) {
        fptr = FPtr(rlptr->file_id);
        if (str_head != NULL)
          ts_copy_byte(FIELD_MARK);

        ts_printf("%d\xfd%s\xfd%d\xfd%s\xfd%.*s\xfd%s\xfd%d", (int)(rlptr->file_id),
                  fptr->pathname, (int)lock_owner,
                  (rlptr->lock_type == L_UPDATE) ? "RU" : "RL", rlptr->id_len,
                  rlptr->id, lock_owner_name(abs(lock_owner)),
                  (int)(rlptr->lock_time));
      }
    }
  }

  /* Lock waiters */

  if (file_id == NO_LOCAL_FILE) { /* 20 Oct 26 S.72: a file on another server: no session of this machine waits for it, and the user number asked for is nobody's business here -
                                     it indexed UMap() unchecked, and an absurd number faulted the process (measured: getlocks(f, 12345) of a remote file, Fault type 11) */
    lo = 1;
    hi = 0;
  } else if (user == 0) {
    lo = 1;
    hi = sysseg->max_users;
  } else {
    lo = hi = *(UMap(user));
  }

  for (i = lo; i <= hi; i++) {
    uptr = UPtr(i);

    if ((uptr->uid != 0)                      /* User table entry is in use */
        && ((j = uptr->lockwait_index) != 0)) /* User is waiting for a lock */
    {
      if (j > 0) /* Waiting for record lock */
      {
        rlptr = RLPtr(j);
        if ((file_id < 0) || (rlptr->file_id == file_id)) {
          fptr = FPtr(rlptr->file_id);
          if (str_head != NULL)
            ts_copy_byte(FIELD_MARK);

          ts_printf("%d\xfd%s\xfd%d\xfdWAIT\xfd%.*s\xfd\xfd%d", (int)(rlptr->file_id),
                    fptr->pathname, (int)(uptr->uid), rlptr->id_len, rlptr->id,
                    (int)(uptr->lockwait_time));
        }
      } else /* Waiting for file lock */
      {
        if ((file_id < 0) || (-j == file_id)) {
          fptr = FPtr(-j);
          if (str_head != NULL)
            ts_copy_byte(FIELD_MARK);

          ts_printf("%d\xfd%s\xfd%d\xfdWAIT\xfd\xfd\xfd%d", (int)(-j), fptr->pathname,
                    (int)(uptr->uid), (int)(uptr->lockwait_time));
        }
      }
    }
  }

  EndExclusive(REC_LOCK_SEM);
  EndExclusive(FILE_TABLE_LOCK);

  (void)ts_terminate();

  k_pop(1);
  k_dismiss();

  InitDescr(e_stack, STRING);
  (e_stack++)->data.str.saddr = str_head;
}

/* ======================================================================
   op_llock()  -  Read lock prefix opcode                                 */

void op_llock() {
  process.op_flags |= P_LLOCK;

  /* Set the lock_beep_timer back to zero so that we always wait one
    second before the first beep. This ensures that "normal" short
    waits do not beep.                                              */

  lock_beep_timer = 0;
}

/* ======================================================================
   op_lock()  -  Acquire task lock                                        */

void op_lock() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Lock number                |  0 = success, >0 = failed   |
     |=============================|=============================|
 */

  DESCRIPTOR* descr;
  int16_t lock_no;
  int16_t lock_owner;

  descr = e_stack - 1;
  GetInt(descr);
  lock_no = (int16_t)(descr->data.value);

  if ((lock_no < 0) || (lock_no > 63))
    k_inva_task_lock_error();

  StartExclusive(SHORT_CODE, 41);

  lock_owner = sysseg->task_locks[lock_no];
  process.status = lock_owner;
  if ((lock_owner == 0) || (lock_owner == process.user_no)) {
    descr->data.value = 0;
    sysseg->task_locks[lock_no] = process.user_no;
  } else {
    descr->data.value = lock_owner;
  }

  EndExclusive(SHORT_CODE);
}

/* ======================================================================
   op_testlock  -  Test a task lock                                       */

void op_testlock() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Lock number                |  Owner                      |
     |=============================|=============================|
 */

  DESCRIPTOR* descr;
  int16_t lock_no;

  descr = e_stack - 1;
  GetInt(descr);
  lock_no = (int16_t)(descr->data.value);

  if ((lock_no < 0) || (lock_no > 63))
    k_inva_task_lock_error();

  descr->data.value = sysseg->task_locks[lock_no];
}

/* ======================================================================
   op_lockrec()  -  Set read or update lock on record                     */

void op_lockrec() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Record id                  | Status 0=ok, <0 = ON ERROR  |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to LOCKREC.
 */

  DESCRIPTOR* descr;
  DESCRIPTOR* id_descr;
  int16_t id_len;
  char id[MAX_ID_LEN + 1];
  FILE_VAR* fvar;
  u_int16_t op_flags;
  int16_t status;
  bool update;
  bool no_wait;
  u_int32_t txn_id;
  u_char* retry_pc = op_pc; /* 18 Oct 26 S.65 slice 3e: taken before any net_ call; the handler's own opcodes overwrite op_pc */

  op_flags = process.op_flags;
  update = (op_flags & P_ULOCK) != 0;
  no_wait = (op_flags & P_LOCKED) != 0;

  /* Get record id */

  id_descr = e_stack - 1;
  if ((id_len = k_get_c_string(id_descr, id, sysseg->maxidlen)) <= 0) {
    k_illegal_id(id_descr);
  }

  /* Find the file variable descriptor */

  descr = e_stack - 2;
  k_get_file(descr);
  fvar = descr->data.fvar;

  if (fvar->type == NET_FILE) /* 17 Oct 26 S.65: a remote file takes no local lock; nothing has been touched yet */
  {
    if (!fvar->access.net.write || (fvar->flags & FV_RDONLY)) /* 18 Oct 26 S.65 slice 3e: a read mode handle is refused exactly as in slice 3c */
    {
      if (!(op_flags & P_ON_ERROR))
        net_refuse(fvar, update ? "RECORDLOCKU" : "RECORDLOCKL");
      process.op_flags = 0;
      process.status = -ER_PERM;
      k_dismiss();
      k_dismiss();
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = process.status;
      return;
    }

    /* A write mode handle.  net_gate() makes the mode, transaction and S.64 tests and raises the refusal unless the caller said ON ERROR;
       net_lock_step() sends the no-wait lock request, and on a busy record without a LOCKED clause arranges the 250 ms re-execution of this
       opcode (pc = retry_pc, operands left on the stack) and we return at once.  The handler runs BASIC, so find nothing by pointer after
       either call: k_dismiss() works from e_stack.  The local pc-- is right only for a one byte opcode and is not used here. */

    process.op_flags = op_flags & P_ON_ERROR;
    status = net_gate(fvar, NETG_LOCK, op_flags, update ? "RECORDLOCKU" : "RECORDLOCKL");
    process.op_flags = 0;
    if (status != 0) {
      process.status = status;
    } else {
      switch (status = net_lock_step(fvar, id, id_len, update, op_flags, retry_pc)) {
        case NET_LOCK_HELD:
          status = 0;
          break;

        case NET_LOCK_WAIT: /* the opcode will be run again; process.op_flags was left as it was found */
          return;

        case NET_LOCK_LOCKED: /* process.status is the holder's user number */
          status = ER_LCK;
          break;

        default: /* an error; process.status is set and the error was raised unless ON ERROR */
          status = (int16_t)process.status;
          break;
      }
      process.op_flags = 0;
    }

    k_dismiss();
    k_dismiss();
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = status;
    return;
  }

  txn_id = (fvar->flags & FV_NON_TXN) ? 0 : process.txn_id;

  switch (status = lock_record(fvar, id, id_len, update, txn_id, no_wait)) {
    case 0: /* Got the lock */
      break;

    case -3: /* This process is at its MAXRLOCK limit: the ON ERROR clause, or an abort */
      process.status = -ER_MAXRLOCK;
      status = -ER_MAXRLOCK;
      if (!(op_flags & P_ON_ERROR))
        k_error(sysmsg(12167));
      break;

    case -2: /* Deadlock detected */
      if (sysseg->deadlock)
        k_deadlock();
      /* **** FALL THROUGH **** */
      /* Modified by Composer AI - 2026/06/10.
         Fall-through is intentional (see comment above); make it
         explicit for the compiler. */
      __attribute__((fallthrough));
      /* -------------------- */

    case -1:        /* Lock table is full */
    default:        /* Conflicting lock is already held by another user */
      if (!no_wait) /* Wait for the lock */
      {
        if (my_uptr->events)
          process_events();
        pc--;
        lock_beep();
        Sleep(250);
        return;
      }
      process.status = status;
      status = ER_LCK; /* Take the LOCKED clause */
      break;
  }

  process.op_flags = 0;

  k_dismiss();
  k_dismiss();

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;
}

/* ======================================================================
   op_nowait()  -  Activate LOCKED clause for various opcodes             */

void op_nowait() {
  process.op_flags |= P_LOCKED;
}

/* ======================================================================
   op_reclckd()  -  RECORDLOCKED function                                 */

void op_reclckd() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Record id                  |  Lock state code            |
     |-----------------------------|-----------------------------|
     |  File variable              |                             |
     |=============================|=============================|
 */

  DESCRIPTOR* descr;
  char id[MAX_ID_LEN + 1];
  int16_t id_len;
  int16_t status = 0;
  FILE_VAR* fvar;
  FILE_ENTRY* fptr;
  int16_t idx;
  int32_t hash_value;
  int16_t scan_idx; /* Scanning index */
  RLOCK_ENTRY* lptr;
  int16_t active_locks;
  int16_t file_id;

  /* Get record id */

  descr = e_stack - 1;
  if ((id_len = k_get_c_string(descr, id, sysseg->maxidlen)) <= 0) {
    k_illegal_id(descr);
  }

  /* Find the file variable descriptor */

  descr = e_stack - 2;
  k_get_file(descr);
  fvar = descr->data.fvar;

  if (fvar->type == NET_FILE) /* 20 Oct 26 S.72: the server says; STATUS() is the owner's user number on the server.  S.72b: a read-mode handle is refused inside, nothing is sent */
  {
    status = (int16_t)net_recordlocked(fvar, id, id_len); /* an error is raised, always; the handler runs BASIC: the stack is found by e_stack from here on */

    k_dismiss();
    k_dismiss();

    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = status;
    return;
  }

  {
    file_id = fvar->file_id;
    fptr = FPtr(file_id);

    if ((process.status = fptr->file_lock) != 0) /* File is locked */
    {
      if (process.status == process.user_no)
        status = LOCK_MY_FILELOCK;
      else
        status = LOCK_OTHER_FILELOCK;
    } else if (fptr->lock_count != 0) {
      StartExclusive(REC_LOCK_SEM, 29);

      if (fptr->flags & DHF_NOCASE)
        UpperCaseMem(id, id_len);

      hash_value = hash(id, id_len);
      idx = (int16_t)RLockHash(file_id, hash_value);
      scan_idx = idx;
      lptr = RLPtr(scan_idx);

      active_locks = lptr->count; /* There are this many locks somewhere */
      while (active_locks) {
        if (lptr->hash == idx) {
          if ((lptr->file_id == file_id)          /* Right file... */
              && (lptr->id_hash == hash_value)    /* ...right hash... */
              && (lptr->id_len == id_len)         /* ...right id_len... */
              && (!memcmp(lptr->id, id, id_len))) /* ...right id */
          {
            /* We have found the lock */

            if ((process.status = lptr->owner) == process.user_no) {
              status =
                  (lptr->lock_type == L_UPDATE) ? LOCK_MY_READU : LOCK_MY_READL;
              break;
            } else {
              status = (lptr->lock_type == L_UPDATE) ? LOCK_OTHER_READU
                                                     : LOCK_OTHER_READL;
            }
          }

          active_locks--;
        }

        if (++scan_idx > sysseg->numlocks)
          scan_idx = 1;
        lptr = RLPtr(scan_idx);
      }

      EndExclusive(REC_LOCK_SEM);
    }
  }

  k_dismiss();
  k_dismiss();

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;
}

/* ======================================================================
   op_release()  -  Release locks                                         */

void op_release() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Record id                  |  0 = ok; <0 = ON ERROR      |
     |-----------------------------|-----------------------------|
     |  File variable              |                             |
     |=============================|=============================|

    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to RELEASE.
 */

  DESCRIPTOR* id_descr;
  DESCRIPTOR* descr;
  FILE_VAR* fvar;
  char id[MAX_ID_LEN + 1];
  int16_t id_len;
  u_int32_t txn_id;

  process.op_flags = 0;

  /* Get record id */

  id_descr = e_stack - 1;
  if ((id_len = k_get_c_string(id_descr, id, sysseg->maxidlen)) < 0) {
    k_illegal_id(id_descr);
  }

  /* Find the file variable descriptor */

  descr = e_stack - 2;
  k_get_file(descr);
  fvar = descr->data.fvar;

  if (fvar->type == NET_FILE) {
    if (!fvar->access.net.write)
      net_refuse(fvar, "RELEASE"); /* 17 Oct 26 S.65: a read mode handle can hold no lock; refused as in slice 3c */

    /* 18 Oct 26 S.65 slice 3e: a write mode handle.  Inside a transaction, as locally, nothing is released (and nothing is sent); an empty
       id releases nothing.  An id over the server's limit cannot be locked, so there is nothing to ask for.  net_release() never raises and
       ignores every answer.  The handler runs BASIC: the operands are dismissed by e_stack below. */

    if (process.txn_id == 0 && id_len > 0 && id_len <= NET_ID_MAX)
      net_release(fvar, id, id_len);

    k_dismiss();
    k_dismiss();

    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = 0;
    return;
  }

  txn_id = (fvar->flags & FV_NON_TXN) ? 0 : process.txn_id;

  if (txn_id == 0) {
    if (id_len)
      (void)unlock_record(fvar, id, id_len);
  }

  k_dismiss();
  k_dismiss();

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = 0;
}

/* ======================================================================
   op_rlsfile()  -  Release all locks for given file                      */

void op_rlsfile() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  File variable              |  0 = ok; <0 = ON ERROR      |
     |=============================|=============================|

    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to RELEASE.
 */

  DESCRIPTOR* descr;
  FILE_VAR* fvar;
  u_int32_t txn_id;

  process.op_flags = 0;

  /* Find the file variable descriptor */

  descr = e_stack - 1;
  k_get_file(descr);
  fvar = descr->data.fvar;

  if (fvar->type == NET_FILE) {
    if (!fvar->access.net.write)
      net_refuse(fvar, "RELEASE"); /* 17 Oct 26 S.65, as op_release() */

    /* 18 Oct 26 S.65 slice 3e: a write mode handle; every lock this session holds through the file, nothing inside a transaction */

    if (process.txn_id == 0)
      net_release(fvar, NULL, 0);

    k_dismiss();

    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = 0;
    return;
  }

  txn_id = (fvar->flags & FV_NON_TXN) ? 0 : process.txn_id;

  if (txn_id == 0) {
    unlock_record(fvar, NULL, 0);
  }

  k_dismiss();

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = 0;
}

/* ======================================================================
   op_rlsall()  -  Release all record locks                               */

void op_rlsall() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |                             |  0 = ok; <0 = ON ERROR      |
     |=============================|=============================|

    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to RLSALL.
 */

  process.op_flags = 0;

  if (process.txn_id == 0) {
    net_release_all(); /* 18 Oct 26 S.65 slice 3e: returns at once unless this process opened a write mode remote file; never raises */
    (void)unlock_record(NULL, "", 0);
  }

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = 0;
}

/* ======================================================================
   op_ulock()  -  Update lock prefix opcode                               */

void op_ulock() {
  process.op_flags |= P_ULOCK;

  /* Set the lock_beep_timer back to zero so that we always wait one
    second before the first beep. This ensures that "normal" short
    waits do not beep.                                              */

  lock_beep_timer = 0;
}

/* ======================================================================
 op_unlk()  -  Release a specific record lock, possibly not ours          */

void op_unlk() {
  /* Stack:

     |===============================|===============================|
     |            BEFORE             |             AFTER             |
     |===============================|===============================|
 top |  Record id, null if all       |                               |
     |-------------------------------|-------------------------------|
     |  User no, -ve if all          |                               |
     |-------------------------------|-------------------------------|
     |  File id, -ve if all          |                               |
     |===============================|===============================|

*/

  DESCRIPTOR* descr;
  int16_t id_len;
  char id[MAX_ID_LEN + 1];
  int16_t file_id;
  int16_t user_no;
  RLOCK_ENTRY* lptr;
  int16_t lno;

  /* Get record id */

  descr = e_stack - 1;
  if ((id_len = k_get_c_string(descr, id, sysseg->maxidlen)) < 0) {
    k_illegal_id(descr);
  }
  k_dismiss();

  /* Get user number */

  descr = e_stack - 1;
  GetInt(descr);
  user_no = (int16_t)(descr->data.value);
  k_pop(1);

  /* Get file id */

  descr = e_stack - 1;
  GetInt(descr);
  file_id = (int16_t)(descr->data.value);
  k_pop(1);

  if (file_id >= 0) {
    if (FPtr(file_id)->flags & DHF_NOCASE)
      UpperCaseMem(id, id_len);
  }

  StartExclusive(REC_LOCK_SEM, 30);

  for (lno = 1; lno <= sysseg->numlocks; lno++) {
    lptr = RLPtr(lno);

    if ((lptr->hash != 0)                                /* Cell in use */
        && ((file_id < 0) || (lptr->file_id == file_id)) /* Right file... */
        && ((user_no < 0) || (lptr->owner == user_no))   /* ...right user... */
        && ((id_len == 0) ||
            ((lptr->id_len == id_len)              /* ...id_len... */
             && (!memcmp(lptr->id, id, id_len))))) /* ...right id */
    {
      /* We have found a lock to release */
      (RLPtr(lptr->hash)->count)--;
      (sysseg->rl_count)--;
      (FPtr(lptr->file_id)->lock_count)--;
      if (lptr->waiters)
        clear_waiters(lno);
      lptr->hash = 0; /* Free this cell */

      /* Raise an EVT_REBUILD_LLT event in the target user. We do this,
        even if it is ourself, as the code above will not have released
        the local lock table entry.                                     */

      raise_event(EVT_REBUILD_LLT, lptr->owner);
    }
  }

  EndExclusive(REC_LOCK_SEM);
}

/* ======================================================================
 op_unlkfl()  -  Release a specific file lock, possibly not ours          */

void op_unlkfl() {
  /* Stack:

     |===============================|===============================|
     |            BEFORE             |             AFTER             |
     |===============================|===============================|
 top |  User no, -ve if all          |                               |
     |-------------------------------|-------------------------------|
     |  File id, -ve if all          |                               |
     |===============================|===============================|

*/

  DESCRIPTOR* descr;
  int16_t user_no;
  FILE_ENTRY* fptr;
  int16_t fno;

  /* Get user number */

  descr = e_stack - 1;
  GetInt(descr);
  user_no = (int16_t)(descr->data.value);
  k_pop(1);

  /* Get file id */

  descr = e_stack - 1;
  GetInt(descr);
  fno = (int16_t)(descr->data.value);
  k_pop(1);

  StartExclusive(REC_LOCK_SEM, 31);
  if (fno >= 0) /* Specific file */
  {
    fptr = FPtr(fno);
    if (fptr->ref_ct != 0) {
      if ((user_no < 0) || (abs(fptr->file_lock) == user_no)) {
        clear_waiters(-fno);
        fptr->file_lock = 0;
      }
    }
  } else /* All files */
  {
    for (fno = 1; fno <= sysseg->used_files; fno++) {
      fptr = FPtr(fno);
      if (fptr->ref_ct != 0) {
        if ((user_no < 0) || (abs(fptr->file_lock) == user_no)) {
          clear_waiters(-fno);
          fptr->file_lock = 0;
        }
      }
    }
  }

  EndExclusive(REC_LOCK_SEM);
}

/* ======================================================================
   op_unlock()  -  Release task lock                                      */

void op_unlock() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Lock number                |  0 = ok; >0 = error         |
     |=============================|=============================|

     Lock number may have 1024 additive to release locks owned by
     other users (only valid from internal mode programs).

     Errors are:
        ER$LCK    Lock is held by another process
        ER$NLK    Lock is not held by any process
 */

  DESCRIPTOR* descr;
  int16_t lock_no;
  bool allow_other_users = FALSE;

  descr = e_stack - 1;
  GetInt(descr);
  lock_no = (int16_t)(descr->data.value);

  if (process.program.flags & HDR_INTERNAL) {
    allow_other_users = (lock_no & 1024) != 0;
    lock_no &= ~1024;
  }

  if ((lock_no < 0) || (lock_no > 63))
    k_inva_task_lock_error();

  if ((sysseg->task_locks[lock_no] == process.user_no) /* Own this lock */
      || allow_other_users) {
    process.status = 0;
    sysseg->task_locks[lock_no] = 0;
  } else if (sysseg->task_locks[lock_no]) /* Lock owned elsewhere */
  {
    process.status = ER_LCK;
  } else {
    process.status = ER_NLK;
  }

  descr->data.value = process.status;
}

/* ======================================================================
   check_lock()  -  Check if record is covered by update or file lock     */

bool check_lock(FILE_VAR* fvar,
                char* raw_id, /* Record id */
                int16_t id_len) {
  bool status = FALSE;
  FILE_ENTRY* fptr;
  int16_t idx;
  int32_t hash_value;
  int16_t scan_idx; /* Scanning index */
  RLOCK_ENTRY* lptr;
  int16_t active_locks;
  int16_t file_id;
  char u_id[MAX_ID_LEN];
  char* id;

  if (fvar->type == NET_FILE)
    net_refuse(fvar, "LOCK"); /* 17 Oct 26 S.65: backstop, file_id is -1 and there is no entry to read */

  file_id = fvar->file_id;
  fptr = FPtr(file_id);

  if (fptr->flags & DHF_NOCASE) /* 0313 */
  {
    memucpy(u_id, raw_id, id_len);
    id = u_id;
  } else {
    id = raw_id;
  }

  if (fptr->file_lock != 0) /* File is locked */
  {
    if (fptr->file_lock == process.user_no)
      status = TRUE;                /* It's us */
  } else if (fptr->lock_count != 0) /* File not locked but records are locked */
  {
    StartExclusive(REC_LOCK_SEM, 47);

    hash_value = hash(id, id_len);
    idx = (int16_t)RLockHash(file_id, hash_value);
    scan_idx = idx;
    lptr = RLPtr(scan_idx);

    active_locks = lptr->count; /* There are this many locks somewhere */
    while (active_locks) {
      if (lptr->hash == idx) {
        if ((lptr->file_id == file_id)           /* Right file... */
            && (lptr->id_hash == hash_value)     /* ...right hash... */
            && (lptr->id_len == id_len)          /* ...right id_len... */
            && (!memcmp(lptr->id, id, id_len))   /* ...right id... */
            && (lptr->owner == process.user_no)) /* ...right user */
        {
          /* We have found the lock */

          status = (lptr->lock_type == L_UPDATE);
          break;
        }

        active_locks--;
      }

      if (++scan_idx > sysseg->numlocks)
        scan_idx = 1;
      lptr = RLPtr(scan_idx);
    }

    EndExclusive(REC_LOCK_SEM);
  }

  return status;
}

/* ======================================================================
   Deadlock diagnostics  (12 Oct 26 dm, openQM items 587 and 500)

   deadlock_info_add() is called by lock_record() as it walks the chain of
   waiting processes that makes a deadlock.  It builds what SYSTEM(1083)
   returns: a field for each process in the deadlock, of three values - its
   user number, the pathname of the file and the record id of the lock it is
   waiting for, the id left out for a file lock.  The list belongs to this
   process and lasts until its next deadlock, so a program that follows the
   abort can still ask for it.  A deadlock of so many processes that the
   buffer fills is reported without the later ones.  Record ids are as the
   lock table holds them (upper case in a file that folds case).             */

#define DEADLOCK_INFO_SIZE 8192
Private char deadlock_info[DEADLOCK_INFO_SIZE];
Private int deadlock_info_len = 0;

Private void deadlock_info_add(bool first, int16_t user, char* path, char* id,
                               int16_t id_len) {
  int n;

  if (first)
    deadlock_info_len = 0;

  n = (int)strlen(path) + ((id != NULL && id_len > 0) ? id_len : 0) + 16;
  if (deadlock_info_len + n >= DEADLOCK_INFO_SIZE)
    return;

  if (deadlock_info_len > 0)
    deadlock_info[deadlock_info_len++] = FIELD_MARK;
  deadlock_info_len += sprintf(deadlock_info + deadlock_info_len, "%d%c%s",
                               (int)user, VALUE_MARK, path);
  if (id != NULL && id_len > 0) {
    deadlock_info[deadlock_info_len++] = VALUE_MARK;
    memcpy(deadlock_info + deadlock_info_len, id, id_len);
    deadlock_info_len += id_len;
    deadlock_info[deadlock_info_len] = '\0';
  }
}

/* deadlock_info_string()  -  The list above, for SYSTEM(1083) */

char* deadlock_info_string(int* len) {
  *len = deadlock_info_len;
  return deadlock_info;
}

/* ----------------------------------------------------------------------
   deadlock_save()  -  DEADLOCK=2: write every lock to deadlock.n

   n is this user number and the file goes where a process dump does,
   DUMPDIR or else the SDSYS directory.  Four lines for each lock and a
   blank line between locks: the user number and name, the file number and
   pathname, the lock type and, for a record lock, the record id, and the
   date and time the lock was acquired in the server's time zone.  The text
   is built under the lock semaphores and written after they are released.
   It is created 0600 and not through a link, for the reasons given in
   pdump.c: the directory is writable by every SD user.                    */

Private void deadlock_save() {
  char path[MAX_PATHNAME_LEN + 1];
  char* buf = NULL;
  size_t size = 0;
  FILE* ms;
  int fd;
  int16_t i;
  int16_t lock_owner;
  FILE_ENTRY* fptr;
  RLOCK_ENTRY* rlptr;
  time_t t;
  struct tm tmv;
  char stamp[32];
  char* p;
  ssize_t w;

  if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s%cdeadlock.%d",
               (pcfg.dumpdir[0] != '\0') ? pcfg.dumpdir : (sysseg->sysdir), DS,
               process.user_no) >= (MAX_PATHNAME_LEN + 1))
    return;

  if ((ms = open_memstream(&buf, &size)) == NULL)
    return;

  StartExclusive(FILE_TABLE_LOCK, 81);
  StartExclusive(REC_LOCK_SEM, 82);

  for (i = 1, fptr = FPtr(1); i <= sysseg->used_files; i++, fptr++) {
    if (fptr->file_lock != 0) {
      lock_owner = abs(fptr->file_lock);
      t = (time_t)(fptr->file_lock_time);
      localtime_r(&t, &tmv);
      strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tmv);
      fprintf(ms, "%d %s\n%d %s\n%s\n%s\n\n", (int)lock_owner,
              lock_owner_name(lock_owner), (int)i, fptr->pathname,
              (fptr->file_lock < 0) ? "SX" : "FX", stamp);
    }
  }

  for (i = 1; i <= sysseg->numlocks; i++) {
    rlptr = RLPtr(i);
    if (rlptr->hash != 0) {
      t = (time_t)(rlptr->lock_time);
      localtime_r(&t, &tmv);
      strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tmv);
      fprintf(ms, "%d %s\n%d %s\n%s %.*s\n%s\n\n", (int)(rlptr->owner),
              lock_owner_name(rlptr->owner), (int)(rlptr->file_id),
              FPtr(rlptr->file_id)->pathname,
              (rlptr->lock_type == L_UPDATE) ? "RU" : "RL", rlptr->id_len,
              rlptr->id, stamp);
    }
  }

  EndExclusive(REC_LOCK_SEM);
  EndExclusive(FILE_TABLE_LOCK);
  fclose(ms);

  fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
  if (fd < 0) {
    tio_printf(sysmsg(12169), path, strerror(errno));
    tio_printf("\n");
  } else {
    (void)fchmod(fd, 0600);
    for (p = buf; size > 0 && (w = write(fd, p, size)) > 0; p += w, size -= w) {
    }
    close(fd);
    tio_printf(sysmsg(12168), path);
    tio_printf("\n");
  }
  free(buf);
}

/* ======================================================================
   lock_record()  -  Set a read or update lock on a record.
   Note that a record can be locked if the file lock is held by the user
   locking the record.                                                    */

int16_t lock_record(
    /* Returns 0 if ok else user no of process preventing lock,
                  -1 = lock table full
                  -2 = deadlock detected */
    FILE_VAR* fvar,
    char* raw_id,             /* Record id... */
    int16_t id_len,         /* ...and length */
    bool update,              /* Update lock? */
    u_int32_t txn_id, /* Locked as part of this transaction */
    bool no_wait)             /* Caller is not going to wait for lock */
{
  int16_t status = 0;
  int16_t file_id;
  FILE_ENTRY* fptr;
  char u_id[MAX_ID_LEN];
  char* id;
  int16_t idx;
  int32_t hash_value;
  int16_t scan_idx; /* Scanning index */
  int16_t upgrade_idx = 0;
  /* Modified by Composer AI - 2026/06/10.
     lptr was used uninitialized on the path where the file lock check
     jumps to exit_lock_record before lptr is first assigned (the
     blocking_idx >= 0 guard prevents this in practice, but the
     analyzer cannot prove it). Initialize to NULL at declaration. */
  /* RLOCK_ENTRY* lptr; */
  RLOCK_ENTRY* lptr = NULL;
  /* -------------------- */
  int16_t active_locks;
  int16_t free_cell = 0;
  int16_t lock_owner;
  int16_t blocking_idx;
  bool table_full = FALSE;
  int16_t u;
  int16_t lwi;
  /* Modified by Composer AI - 2026/06/10.
     New local used to test the result of UserPtr() for NULL before
     dereferencing it in the deadlock detection loops below. */
  USER_ENTRY* wait_uptr;
  /* -------------------- */
  FILE_ENTRY* d_fptr;
  RLOCK_ENTRY* d_lptr;
  LLT_ENTRY* llt;

  if (fvar->type == NET_FILE)
    net_refuse(fvar, "LOCK"); /* 17 Oct 26 S.65: backstop, as check_lock() */

  file_id = fvar->file_id;
  fptr = FPtr(file_id);

  if (fptr->flags & DHF_NOCASE) {
    memucpy(u_id, raw_id, id_len);
    id = u_id;
  } else {
    id = raw_id;
  }

  StartExclusive(REC_LOCK_SEM, 32);

  /* Check file lock */

  lock_owner = abs(fptr->file_lock); /* 0194 */
  if (lock_owner && (lock_owner != process.user_no)) {
    status = lock_owner; /* File is locked elsewhere */
    blocking_idx = -file_id;
    goto exit_lock_record;
  }

  /* Check record lock */

  hash_value = hash(id, id_len);
  idx = (int16_t)RLockHash(file_id, hash_value);

  scan_idx = idx;
  lptr = RLPtr(scan_idx);

  /* Scan to see if this lock is already owned, remembering any blank cell */

  active_locks = lptr->count; /* There are this many locks somewhere */
  while (active_locks) {
    if (lptr->hash == idx) {
      if ((lptr->file_id == file_id)          /* Right file... */
          && (lptr->id_hash == hash_value)    /* ...right hash... */
          && (lptr->id_len == id_len)         /* ...right length... */
          && (!memcmp(lptr->id, id, id_len))) /* ...right id */
      {
        /* We have found this lock already in use. Is it ours? */

        if (lptr->owner == process.user_no) /* Already own this lock */
        {
          if (lptr->lock_type == L_UPDATE) {
            if (!update)
              lptr->lock_type = L_SHARED;
            lptr->fvar_index = fvar->index; /* Now for this fvar */
            lptr->txn_id = txn_id;
            goto exit_lock_record;
          }

          /* Existing lock is a shared lock. Are we upgrading? */

          if (!update) /* No - just exit */
          {
            lptr->fvar_index = fvar->index; /* Now for this fvar */
            lptr->txn_id = txn_id;
            goto exit_lock_record;
          }
          upgrade_idx = scan_idx; /* Remember this cell */
        } else                    /* Lock is owned by another user */
        {
          if (update || (lptr->lock_type == L_UPDATE)) {
            status = lptr->owner;
            blocking_idx = scan_idx;

            if (sysseg->deadlock) {
              /* Check for a deadlock */

              u = lptr->owner;
              /* Modified by Composer AI - 2026/06/10.
                 UserPtr() returns NULL if the user is no longer
                 logged in; check before dereferencing. A NULL entry
                 is treated as "not waiting", ending the scan. */
              /* while ((lwi = UserPtr(u)->lockwait_index) != 0) { */
              while (((wait_uptr = UserPtr(u)) != NULL) &&
                     ((lwi = wait_uptr->lockwait_index) != 0)) {
              /* -------------------- */
                if (lwi > 0) /* Waiting for record lock */
                {
                  u = RLPtr(lwi)->owner;
                } else /* Waiting for file lock */
                {
                  u = abs(FPtr(-lwi)->file_lock);
                }

                if (u == process.user_no) /* Found ourself - It's a deadlock */
                {
                  u = lptr->owner;
                  tio_printf("\n");
                  tio_printf(sysmsg(1450), u, file_id, id_len, id);
                  deadlock_info_add(TRUE, process.user_no, (char*)(fptr->pathname), id, id_len);
                  /* Modified by Composer AI - 2026/06/10.
                     UserPtr() returns NULL if the user is no longer
                     logged in; check before dereferencing. A NULL
                     entry is treated as "not waiting", ending the
                     scan. */
                  /* while ((lwi = UserPtr(u)->lockwait_index) != 0) { */
                  while (((wait_uptr = UserPtr(u)) != NULL) &&
                         ((lwi = wait_uptr->lockwait_index) != 0)) {
                  /* -------------------- */
                    if (lwi > 0) /* Waiting for record lock */
                    {
                      d_lptr = RLPtr(lwi);
                      tio_printf(sysmsg(1451), d_lptr->file_id, d_lptr->id_len,
                                 d_lptr->id, d_lptr->owner);
                      deadlock_info_add(FALSE, u, (char*)(FPtr(d_lptr->file_id)->pathname),
                                        d_lptr->id, d_lptr->id_len);
                      u = RLPtr(lwi)->owner;
                    } else /* Waiting for file lock */
                    {
                      d_fptr = FPtr(-lwi);
                      tio_printf(sysmsg(1452), -lwi, abs(d_fptr->file_lock));
                      deadlock_info_add(FALSE, u, (char*)(d_fptr->pathname), NULL, 0);
                      u = abs(FPtr(-lwi)->file_lock);
                    }

                    if (u == process.user_no)
                      break;
                  }

                  status = -2; /* Deadlock */
                  break;
                }
              }
            }

            goto exit_lock_record;
          }
        }
      } else /* Not the right lock */
      {
      }
      active_locks--;
    } else if (lptr->hash == 0) /* Unused cell */
    {
      if (free_cell == 0)
        free_cell = scan_idx;
    }

    if (++scan_idx > sysseg->numlocks)
      scan_idx = 1;
    lptr = RLPtr(scan_idx);
  }

  /* We have now scanned all locks for this hash position.  If we are upgrading
    an existing shared lock, we did not find a conflict so do the upgrade. */

  if (upgrade_idx > 0) {
    lptr = RLPtr(upgrade_idx);
    lptr->lock_type = L_UPDATE;
    goto exit_lock_record;
  }

  /* Continue looking if we have yet to find a spare cell */

  if (free_cell == 0) {
    do {
      if (lptr->hash == 0) {
        free_cell = scan_idx;
        break;
      }

      if (++scan_idx > sysseg->numlocks)
        scan_idx = 1;
      lptr = RLPtr(scan_idx);

      if (scan_idx == idx) /* Table full */
      {
        table_full = TRUE;
        status = -1;
        goto exit_lock_record;
      }
    } while (1);
  }

  /* MAXRLOCK (openQM item 313): one process may hold only so many record locks.
    Locking again a record we hold, and upgrading a shared lock, left above, so
    this is a new lock.  -3 is the caller's cue to take the statement's ON ERROR
    clause or abort, not to wait: waiting would never end.                       */

  if ((pcfg.maxrlock > 0) && (llt_count >= pcfg.maxrlock)) {
    status = -3;
    goto exit_lock_record;
  }

  /* Set up a new lock in the free cell */

  lptr = RLPtr(free_cell);
  lptr->hash = idx;
  lptr->owner = process.user_no;
  lptr->waiters = 0;
  lptr->lock_type = (update) ? L_UPDATE : L_SHARED;
  lptr->file_id = file_id;
  lptr->id_hash = hash_value;
  lptr->fvar_index = fvar->index;
  lptr->txn_id = txn_id;
  lptr->lock_time = (int32_t)time(NULL);
  lptr->id_len = id_len;
  memcpy(lptr->id, id, id_len);
  RLPtr(idx)->count += 1;
  if (++(sysseg->rl_count) > sysseg->rl_peak)
    sysseg->rl_peak = sysseg->rl_count;
  (fptr->lock_count)++;

  /* Create local lock table entry */

  llt = (LLT_ENTRY*)k_alloc(122, sizeof(LLT_ENTRY) + id_len - 1);
  if (llt != NULL) {
    llt->fno = file_id;
    llt->fvar_index = fvar->index;
    llt->id_len = id_len;
    memcpy(llt->id, id, id_len);
    llt->next = llt_head;
    llt_head = llt;
    llt_count++;
  }

exit_lock_record:
  switch (status) {
    case 0: /* Got the lock */
      my_uptr->lockwait_index = 0;
      break;

    case -1: /* Lock table full */
    case -3: /* This process is at its MAXRLOCK limit */
      my_uptr->lockwait_index = 0;
      break;

    case -2: /* Deadlock detected */
      if (sysseg->deadlock && !no_wait)
        break; /* Let deadlock system handle */
               /* *** FALL THROUGH *** */
      /* Modified by Composer AI - 2026/06/10.
         Fall-through is intentional (see comment above); make it
         explicit for the compiler. */
      __attribute__((fallthrough));
      /* -------------------- */

    default: /* Blocked by another user */
      if (!no_wait) {
        /* Note that we are waiting for this lock.  If lockwait_index is
           already non-zero, it must be for a subsequent attempt to get
           this lock so we must not increment the waiters counter.      */
        if (my_uptr->lockwait_index == 0) {
          /* Modified by Composer AI - 2026/06/10.
             Also check lptr against NULL: it is NULL on the early
             file-lock conflict path, which always produces a negative
             blocking_idx, but the analyzer cannot prove that. */
          /* if (blocking_idx >= 0) */
          if ((blocking_idx >= 0) && (lptr != NULL))
            lptr->waiters++; /* 0193 */
          /* -------------------- */
          my_uptr->lockwait_time = (int32_t)time(NULL); /* item 487 */
          my_uptr->lockwait_index = blocking_idx;
        }
      }
      break;
  }

  EndExclusive(REC_LOCK_SEM);

  /* Now that we have released the semaphore, log a message if the lock
    action failed because the lock table is full.                      */

  if (table_full)
    log_message("Lock table full");

  /* DEADLOCK=2: keep the state of every lock for whoever analyses this */

  if ((status == -2) && (sysseg->deadlock >= 2))
    deadlock_save();

  return status;
}

/* ======================================================================
   unlock_record()  -  Release a read or update lock on a record          */

bool unlock_record(FILE_VAR* fvar, /* NULL if for all files */
                   char* raw_id,   /* Record id. Null to release all on file */
                   int16_t id_len) {
  FILE_ENTRY* fptr;
  bool status = 0;
  /* Modified by Composer AI - 2026/06/10.
     file_id was used uninitialized if this function was called with
     fvar == NULL and a non-zero id_len (callers never do this, but
     the analyzer cannot prove it). Initialize to zero. */
  /* int16_t file_id; */
  int16_t file_id = 0;
  /* -------------------- */
  int16_t i;
  LLT_ENTRY* llt;
  LLT_ENTRY* next_llt;

  if (fvar != NULL) {
    if (fvar->type == NET_FILE)
      return FALSE; /* 17 Oct 26 S.65: no lock can exist on a remote file; FPtr(-1) must not be read */
    file_id = fvar->file_id;
  }

  StartExclusive(REC_LOCK_SEM, 33);

  if (id_len == 0) /* Unlock all records */
  {
    for (llt = llt_head; llt != NULL; llt = next_llt) {
      next_llt = llt->next;
      if ((fvar == NULL)            /* All files or... */
          || ((llt->fno == file_id) /* ...correct file */
              && (llt->fvar_index == fvar->index))) {
        unlock_id(llt->fno, llt->id, llt->id_len);
        /* Note: on return, the original LLT entry will have been removed */
      }
    }

    /* Also unlock file lock(s) */

    if (fvar == NULL) /* Unlock all file locks for this user */
    {
      for (i = 1, fptr = FPtr(1); i <= sysseg->used_files; i++, fptr++) {
        if (fptr->file_lock == process.user_no) {
          clear_waiters(-i);
          fptr->file_lock = 0;
        }
      }
    } else /* Release specific file lock */
    {
      fptr = FPtr(file_id);
      if ((fptr->file_lock == process.user_no) &&
          (fptr->fvar_index == fvar->index)) {
        clear_waiters(-file_id);
        fptr->file_lock = 0;
      }
    }
    goto exit_unlock_record;
  }

  /* Unlock specific record */

  status = unlock_id(file_id, raw_id, id_len);

exit_unlock_record:
  EndExclusive(REC_LOCK_SEM);

  return status;
}

/* ======================================================================
   Unlock specific file number / id pair                                  */

Private bool unlock_id(int16_t file_id, char* raw_id, int16_t id_len) {
  bool status = FALSE;
  FILE_ENTRY* fptr;
  char u_id[MAX_ID_LEN];
  char* id;
  int32_t hash_value;
  int16_t scan_idx; /* Scanning index */
  int16_t idx;
  RLOCK_ENTRY* lptr;
  int16_t active_locks;
  LLT_ENTRY* llt;
  LLT_ENTRY* prev_llt;

  fptr = FPtr(file_id);
  if (fptr->lock_count != 0) {
    if (fptr->flags & DHF_NOCASE) {
      memucpy(u_id, raw_id, id_len);
      id = u_id; /* 0261 */
    } else {
      id = raw_id;
    }

    hash_value = hash(id, id_len);
    idx = (int16_t)RLockHash(file_id, hash_value);

    scan_idx = idx;
    lptr = RLPtr(scan_idx);

    active_locks = lptr->count; /* There are this many locks somewhere */
    while (active_locks) {
      if (lptr->hash == idx) {
        if ((lptr->file_id == file_id)          /* Right file... */
            && (lptr->owner == process.user_no) /* ...right user... */
            && (lptr->id_hash == hash_value)    /* ...right hash... */
            && (lptr->id_len == id_len)         /* ...right id_len */
            && (!memcmp(lptr->id, id, id_len))) /* ...right id */
        {
          /* We have found the lock */

          if (lptr->waiters)
            clear_waiters(scan_idx);
          lptr->hash = 0; /* Free this cell */
          (RLPtr(idx)->count)--;
          (sysseg->rl_count)--;
          (fptr->lock_count)--;

          /* Remove from the local lock table too */

          for (llt = llt_head, prev_llt = NULL; llt != NULL; llt = llt->next) {
            if ((llt->fno == file_id) && (llt->id_len == id_len) &&
                (!memcmp(llt->id, id, id_len))) {
              if (prev_llt == NULL)
                llt_head = llt->next;
              else
                prev_llt->next = llt->next;
              k_free(llt);
              llt_count--;
              break;
            }
            prev_llt = llt;
          }

          status = TRUE;
          goto exit_unlock_id;
        } else /* Not the right lock */
        {
        }
        active_locks--;
      }

      if (++scan_idx > sysseg->numlocks)
        scan_idx = 1;
      lptr = RLPtr(scan_idx);
    }
  }

exit_unlock_id:
  return status;
}

/* ======================================================================
   unlock_txn()  -  Release all locks for a given transaction             */

void unlock_txn(u_int32_t txn) {
  FILE_ENTRY* fptr;
  int16_t idx;
  RLOCK_ENTRY* lptr;
  int16_t i;

  StartExclusive(REC_LOCK_SEM, 33);

  for (idx = 1; idx <= sysseg->numlocks; idx++) {
    lptr = RLPtr(idx);
    if ((lptr->hash != 0)                   /* Cell used... */
        && (lptr->owner == process.user_no) /* ...by this user... */
        && (lptr->txn_id == txn))           /* ...for this transaction */
    {
      (RLPtr(lptr->hash)->count)--;
      (sysseg->rl_count)--;
      (FPtr(lptr->file_id)->lock_count)--;
      if (lptr->waiters)
        clear_waiters(idx);
      lptr->hash = 0; /* Free this cell */
    }
  }

  /* Also unlock file lock(s) */

  for (i = 1, fptr = FPtr(1); i <= sysseg->used_files; i++, fptr++) {
    if ((fptr->file_lock == process.user_no) && (fptr->txn_id == txn)) {
      clear_waiters(-i);
      fptr->file_lock = 0;
      fptr->txn_id = 0;
    }
  }

  EndExclusive(REC_LOCK_SEM);
}

/* ======================================================================
   clear_waiters()  -  Clear lock wait entries                            */

void clear_waiters(int16_t idx) /* Lock cell index */
{
  int16_t i;
  USER_ENTRY* uptr;
  /* Modified by Composer AI - 2026/06/10.
     lptr is only assigned when idx > 0; although the dereference below
     is guarded by the same condition, the analyzer cannot prove the
     correlation. Initialize to NULL at declaration. */
  /* RLOCK_ENTRY* lptr; */
  RLOCK_ENTRY* lptr = NULL;
  /* -------------------- */

  /* We must clear the user table lock wait entry for any users that are
    waiting for this lock.  If we do not do so, the deadlock detection
    system can see what looks like a deadlock where a process was waiting
    for a lock that has just been released but has not yet managed to wake
    up and claim it.  If more than one user is waiting for the same lock,
    the unlucky ones will reinstate themselves when they next try to get
    the lock.  The only downside to this is that the deadlock system won't
    always abort the last process to wait.

    If the lock we are releasing is a shared read lock and there are other
    users also holding this lock, a number of situations may exist if a
    further user is waiting for an update lock:

    1. All the waiters are recorded against this lock cell.
       We will clear down the wait information and each user will
       re-establish it against the another entry for the same shared lock.

    2. All the waiters are recorded against another lock cell.
       We will not arrive in this routine.  This doesn't matter as the
       users for which we would otherwise clear the wait information are
       still waiting.

    3. Some of the waiters are recorded against this lock cell.
       We will clear some of the waiters.  All of them will subsequently
       retry the lock.  Those that we clear will move their waiter count
       to another lock entry.                                            */

  if (idx > 0)
    lptr = RLPtr(idx);

  for (i = 1; i <= sysseg->max_users; i++) {
    uptr = UPtr(i);
    if ((uptr->uid != 0)                  /* Live user */
        && (uptr->lockwait_index == idx)) /* This lock */
    {
      uptr->lockwait_index = 0;
      /* Modified by Composer AI - 2026/06/10.
         Also check lptr against NULL: lptr is non-NULL whenever
         idx > 0 (see assignment above), but the analyzer cannot
         prove the correlation. */
      /* if (idx > 0) / * Clearing wait on record lock * / */
      if ((idx > 0) && (lptr != NULL)) /* Clearing wait on record lock */
      {
        if (--(lptr->waiters) == 0)
          break;
      }
      /* -------------------- */
    }
  }
}

/* ======================================================================
   clear_lockwait()  -  Clear lock wait for user                          */

void clear_lockwait() {
  int16_t i;

  StartExclusive(REC_LOCK_SEM, 53);

  if ((i = my_uptr->lockwait_index) > 0) /* Waiting for record lock */
  {
    (RLPtr(i)->waiters)--;
  }

  my_uptr->lockwait_index = 0;

  EndExclusive(REC_LOCK_SEM);
}

/* ======================================================================
   rebuild_llt()  -  Rebuild local lock table after UNLOCK                */

void rebuild_llt() {
  /* The UNLOCK command allows a system administrator to release locks in
    another process. Because the local lock table is in our private
    memory, use of UNLOCK raises an event in the process that owns the
    lock being released. This event then calls this routine to rebuild
    the local lock table completely.                                    */

  LLT_ENTRY* llt;
  LLT_ENTRY* next_llt;
  int16_t idx;
  RLOCK_ENTRY* lptr;

  /* Give away all existing LLT entries */

  for (llt = llt_head; llt != NULL; llt = next_llt) {
    next_llt = llt->next;
    k_free(llt);
  }
  llt_head = NULL;
  llt_count = 0;

  /* Create new LLT chain */

  for (idx = 1; idx <= sysseg->numlocks; idx++) {
    lptr = RLPtr(idx);
    if ((lptr->hash != 0)                    /* Cell used... */
        && (lptr->owner == process.user_no)) /* ...by this user */
    {
      /* Create new local lock table entry */

      llt = (LLT_ENTRY*)k_alloc(123, sizeof(LLT_ENTRY) + lptr->id_len - 1);
      if (llt != NULL) {
        llt->fno = lptr->file_id;
        llt->fvar_index = lptr->fvar_index;
        llt->id_len = lptr->id_len;
        memcpy(llt->id, lptr->id, lptr->id_len);
        llt->next = llt_head;
        llt_head = llt;
        llt_count++;
      }
    }
  }
}

/* ======================================================================
   OPTION COMMAND.LEVEL.LOCKS  (16 Oct 26, QM4 gap 231 / 428)

   Without the option, a file variable that goes (a subroutine returns, or the variable is given another file) closes
   its file and with it the locks taken through it.  With the option the locks belong to the command processor level
   instead: park_fvar() keeps the file open, and the file is closed, with its locks, when the program that was running
   at that level returns to the command processor (release_parked_fvars(), called by k_return()).  An explicit CLOSE is
   still a close.                                                                                                      */

typedef struct PARKED_FVAR PARKED_FVAR;
struct PARKED_FVAR {
  PARKED_FVAR* next;
  FILE_VAR* fvar;
  int16_t level; /* cproc_level when it was parked */
};
Private PARKED_FVAR* parked_fvars = NULL;

/* fvar_holds_locks()  -  Does this process hold the file lock, or a record lock, taken through this file variable?  */

Private bool fvar_holds_locks(FILE_VAR* fvar) {
  FILE_ENTRY* fptr;
  LLT_ENTRY* llt;

  if (fvar->file_id <= 0)
    return FALSE;
  fptr = FPtr(fvar->file_id);
  if ((abs(fptr->file_lock) == process.user_no) && (fptr->fvar_index == fvar->index))
    return TRUE;
  for (llt = llt_head; llt != NULL; llt = llt->next) {
    if ((llt->fno == fvar->file_id) && (llt->fvar_index == fvar->index))
      return TRUE;
  }
  return FALSE;
}

/* park_fvar()  -  k_release() found the last reference to a file variable gone.  True if the file was kept open for its
   locks, in which case the caller must not close it.  */

bool park_fvar(FILE_VAR* fvar) {
  PARKED_FVAR* p;

  if (!Option(OptCommandLevelLocks) || explicit_close || !fvar_holds_locks(fvar))
    return FALSE;
  p = (PARKED_FVAR*)k_alloc(124, sizeof(PARKED_FVAR));
  if (p == NULL)
    return FALSE;
  p->fvar = fvar;
  p->level = cproc_level;
  p->next = parked_fvars;
  parked_fvars = p;
  return TRUE;
}

/* release_parked_fvars()  -  Close the files parked at this command processor level or above, which releases their locks.  */

void release_parked_fvars(int16_t level) {
  PARKED_FVAR** pp = &parked_fvars;
  PARKED_FVAR* p;

  while ((p = *pp) != NULL) {
    if (p->level >= level) {
      *pp = p->next;
      dio_close(p->fvar);
      k_free(p);
    } else {
      pp = &p->next;
    }
  }
}

/* END-CODE */
