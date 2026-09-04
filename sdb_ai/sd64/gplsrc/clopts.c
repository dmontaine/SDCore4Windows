/* CLOPTS.C
 * Special command line option processing
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
 * 04 Sep 26 Windows port - reap_lost_user(), so LOGOUT n can reclaim a slot
 *                      whose process is gone instead of marking it
 *                      "(logout pending)" for ever.  PRE_RELEASE_FIXES.md 16
 * 31 Aug 26 Windows port - remove_user() gave away the dead session's file,
 *                      record and group locks but never its TASK locks: the
 *                      loop tested process.user_no where the three loops
 *                      below it test user_no.  PRE_RELEASE_FIXES.md 24,
 *                      UPSTREAM_FIXES.md 25
 * 31 Dec 23 SD Launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 * Processes these command line options:
 * -K         Kill user(s)
 * -RECOVER   Recover users
 * -U         Show users
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <signal.h>
#include "sd.h"
#include "locks.h"


Private void kill_process(USER_ENTRY* uptr);
Private bool process_exists(int pid);
Private void remove_user(USER_ENTRY* uptr);

/* ======================================================================
   recover_users()  -  Recover licence space for vanished users           */

bool recover_users() {
  bool status = FALSE;
  USER_ENTRY* uptr;
  int32_t pid;
  int16_t u;
  int16_t user_no;

  /* Be brutal - Lock everything in sight */

  StartExclusive(FILE_TABLE_LOCK,
                 45); /* TODO: Magic numbers are bad, mmmkay? */
  StartExclusive(REC_LOCK_SEM, 45);
  StartExclusive(GROUP_LOCK_SEM, 45);
  StartExclusive(SHORT_CODE, 45);

  for (u = 1; u <= sysseg->max_users; u++) {
    uptr = UPtr(u);
    user_no = uptr->uid;
    pid = uptr->pid;
    if (uptr->uid) {
      if (!process_exists(pid)) {
        remove_user(uptr);
        tio_printf("Removed user %d (pid %d)\n", (int)user_no, pid);
        status = TRUE;
      }
    }
  }

  EndExclusive(SHORT_CODE);
  EndExclusive(GROUP_LOCK_SEM);
  EndExclusive(REC_LOCK_SEM);
  EndExclusive(FILE_TABLE_LOCK);

  return status;
}

/* ======================================================================
 * show_users()  -  Display user information (SD -U)
 * TODO: this may not show IPv6 addresses properly -gwb 22Feb20
 */

void show_users() {
  int i;
  USER_ENTRY* uptr;
  char origin[50];

  if (!attach_shared_memory()) {
    fprintf(stderr, "SD is not active.\n");
    return;
  }

  /* Users
     0         1         2         3         4         5         6         7
     01234567890123456789012345678901234567890123456789012345678901234567890123456789
      Uid Pid........ Puid Origin.................
     Username........................ 1234 12345678901 1234 telnet
     123.123.123.123  xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
 */

  printf(" Uid Pid........ Puid Origin................. Username\n");
  for (i = 1; i <= sysseg->max_users; i++) {
    uptr = UPtr(i);
    if (uptr->uid != 0) {
      strcpy(origin, (char*)(uptr->ttyname));
      if (origin[0] != '\0')
        strcat(origin, " ");
      strcat(origin, (char*)(uptr->ip_addr));
      printf("%4hd %11d %4d %-23s %-32s\n", uptr->uid, uptr->pid,
             (int)(uptr->puid), origin, uptr->username);
    }
  }

  unbind_sysseg();
}

/* ======================================================================
   kill_user()  -  Kill user process command line option                  */

void kill_user(char* user) {
  USER_ENTRY* uptr;
  int16_t u;
  char errmsg[80 + 1];
  int16_t uid;
  char* p;

  if (!attach_shared_memory()) {
    fprintf(stderr, "SD is not active.\n");
    return;
  }

  if (!get_semaphores(FALSE, errmsg)) {
    fprintf(stderr, "Cannot access semaphores.\n");
    return;
  }

  StartExclusive(FILE_TABLE_LOCK,
                 68); /* TODO: Magic numbers are bad, mmmkay? */
  StartExclusive(REC_LOCK_SEM, 68);
  StartExclusive(GROUP_LOCK_SEM, 68);
  StartExclusive(SHORT_CODE, 68);

  if (user == NULL) { /* Kill all users */
    log_printf("External request to terminate all SD users.\n");
    for (u = 1; u <= sysseg->max_users; u++) {
      uptr = UPtr(u);
      if (uptr->uid != 0) {
        uptr->events |= (uptr->flags & USR_LOGOUT) ? EVT_LOGOUT : EVT_TERMINATE;
        uptr->flags |= USR_LOGOUT;
      }
    }
  } else {              /* Kill specific user */
    if (IsDigit(*user)) { /* Kill user by user number */
      for (p = user, uid = 0; IsDigit(*p); p++)
        uid = (uid * 10) + (*p - '0');
      if ((*p != '\0') || (uid < 1) || (uid > sysseg->hi_user_no)) {
        fprintf(stderr, "Invalid user number.\n");
      } else {
        log_printf("External request to terminate SD user %d.\n", uid);
        uptr = UserPtr(uid);
        if (uptr != NULL)
          kill_process(uptr);
        else
          fprintf(stderr, "User %d is not active.\n", uid);
      }
    } else { /* Kill user by login name */
      log_printf(
          "External request to terminate SD sessions for user %2.\n",
          user);
      for (u = 1; u <= sysseg->max_users; u++) {
        uptr = UPtr(u);
        if ((uptr->uid != 0) && !stricmp((char*)(uptr->username), user)) {
          kill_process(uptr);
        }
      }
    }
  }

  EndExclusive(SHORT_CODE);
  EndExclusive(GROUP_LOCK_SEM);
  EndExclusive(REC_LOCK_SEM);
  EndExclusive(FILE_TABLE_LOCK);

  unbind_sysseg();
}

/* ======================================================================
   kill_process()  -  Kill a SD process */

Private void kill_process(USER_ENTRY* uptr) {
  int16_t user_no;
  int pid;

  user_no = uptr->uid;
  pid = uptr->pid;

  /* Check that the process actually exists */

  if (process_exists(pid)) {
    uptr->events |= (uptr->flags & USR_LOGOUT) ? EVT_LOGOUT : EVT_TERMINATE;
    uptr->flags |= USR_LOGOUT;
  } else {
    remove_user(uptr);
    printf("Removed user %d (pid %d).\n", (int)user_no, pid);
  }
}

/* ======================================================================
   reap_lost_user()  -  Reclaim ONE user table slot whose process is gone

   04 Sep 26 Windows port - PRE_RELEASE_FIXES.md 16.

   ***WHY THIS EXISTS.***  A session that dies without logging out leaves its
   user table slot behind, still holding the file it had open.  LOGOUT n then
   raise_event()s EVT_TERMINATE at a process that is not there to receive it,
   so USR_LOGOUT is set and nothing ever clears it: LISTU shows
   "(logout pending)" for ever and the file stays locked.  Measured 26 Aug
   2026 - user 58, pid 363, still listed ten minutes later.

   ***IT IS cleanup()'s PER-USER HALF AND DELIBERATELY SHARES ITS CODE.***
   process_exists() is the same liveness test and remove_user() the same
   release, so a slot reaped here and a slot reaped by "sd -cleanup" are
   reclaimed identically.  Writing a second release path was the alternative
   and it is exactly how PRE_RELEASE 24 happened - one of two copies fixed.

   ***IT DOES NOT ATTACH OR UNBIND SHARED MEMORY, WHICH IS THE ONE REAL
   DIFFERENCE FROM cleanup().***  cleanup() runs as a standalone process that
   has to attach first and let go afterwards; this runs inside a live session
   which already holds the segment, and unbinding it here would pull the floor
   out from under the caller.

   ***THE LOCK ORDER IS cleanup()'s, AND THAT IS NOT COSMETIC.***  Four
   semaphores are taken, and taking them in a different order from the other
   routine that takes all four is how two live sessions deadlock.  Same order,
   released in reverse.

   ***IT REFUSES TO REAP THE CALLER.***  A session removing its own slot while
   running would release its own locks underneath itself.  process_exists()
   would answer TRUE for a live caller and stop it anyway, so this is the
   belt to that braces - and it costs one comparison.                       */

bool reap_lost_user(int16_t user) {
  USER_ENTRY* uptr;
  int16_t u;
  int pid;
  char username[MAX_USERNAME_LEN + 1];
  bool reaped = FALSE;

  if (user == process.user_no)
    return FALSE; /* Never ourselves - see above */

  StartExclusive(FILE_TABLE_LOCK, 59);
  StartExclusive(REC_LOCK_SEM, 59);
  StartExclusive(GROUP_LOCK_SEM, 59);
  StartExclusive(SHORT_CODE, 59);

  for (u = 1; u <= sysseg->max_users; u++) {
    uptr = UPtr(u);
    if ((uptr->uid != 0) && (uptr->uid == user)) {
      pid = uptr->pid;
      if (!process_exists(pid)) {
        strcpy(username, (char*)(uptr->username));
        remove_user(uptr);
        log_printf("LOGOUT reaped user %d (pid %d, %s) - process was gone.\n",
                   (int)user, pid, username);
        reaped = TRUE;
      }
      break; /* uid is unique; alive or dead, this was the entry */
    }
  }

  EndExclusive(SHORT_CODE);
  EndExclusive(GROUP_LOCK_SEM);
  EndExclusive(REC_LOCK_SEM);
  EndExclusive(FILE_TABLE_LOCK);

  return reaped;
}

/* ======================================================================
   cleanup()  -  Clean up user tables from lost processes                 */

void cleanup() {
  USER_ENTRY* uptr;
  int16_t u;
  int16_t user_no;
  int pid;
  char username[MAX_USERNAME_LEN + 1]; /* Login user name */
  char errmsg[80 + 1];

  if (!attach_shared_memory()) {
    fprintf(stderr, "SD is not active.\n");
    return;
  }

  if (!get_semaphores(FALSE, errmsg)) {
    fprintf(stderr, "Cannot access semaphores.\n");
    return;
  }

  StartExclusive(FILE_TABLE_LOCK, 59); /* TODO: Magic numbers are bad, mmkay? */
  StartExclusive(REC_LOCK_SEM, 59);
  StartExclusive(GROUP_LOCK_SEM, 59);
  StartExclusive(SHORT_CODE, 59);

  for (u = 1; u <= sysseg->max_users; u++) {
    uptr = UPtr(u);
    if (uptr->uid != 0) {
      pid = uptr->pid;
      if (!process_exists(pid)) {
        user_no = uptr->uid;
        strcpy(username, (char*)(uptr->username));
        remove_user(uptr);
        log_printf("Cleanup removed user %d (pid %d, %s).\n", (int)user_no, pid,
                   username);
      }
    }
  }

  EndExclusive(SHORT_CODE);
  EndExclusive(GROUP_LOCK_SEM);
  EndExclusive(REC_LOCK_SEM);
  EndExclusive(FILE_TABLE_LOCK);

  unbind_sysseg();
}

/* ======================================================================
   suspend_resume()                                                       */

void suspend_resume(bool suspend) {
  if (!attach_shared_memory()) {
    fprintf(stderr, "SD is not active.\n");
    return;
  }

  if (suspend)
    sysseg->flags |= SSF_SUSPEND;
  else
    sysseg->flags &= ~SSF_SUSPEND;

  unbind_sysseg();
}

/* ====================================================================== */

Private bool process_exists(int pid) {
  return (!kill(pid, 0) || (errno == EPERM));
}

/* ====================================================================== */

Private void remove_user(USER_ENTRY* uptr) {
  int16_t i;
  int16_t user_no;
  /* int32_t pid; value set but never used. */
  FILE_ENTRY* fptr;
  RLOCK_ENTRY* lptr;
  GLOCK_ENTRY* gptr;
  u_int16_t* ufm;

  user_no = uptr->uid;
  /* pid = uptr->pid; value set but never used. */

  /* Give away process locks */

/* 31 Aug 26 Windows port - user_no, NOT process.user_no.  PRE_RELEASE_FIXES.md
   24 / UPSTREAM_FIXES.md 25.  This is the only loop in remove_user() that did
   not test the uid it was handed: the file, record and group loops below all
   use user_no, taken from uptr->uid above.

   WHY IT RELEASED NOTHING RATHER THAN THE WRONG THING.  remove_user() is
   reached from cleanup(), which tidies up on behalf of OTHER sessions and
   never becomes a user itself, so process.user_no is 0.  A FREE task lock
   slot is also 0.  So the test matched exactly the slots that were already
   empty, cleared them again, and left every held lock held - which is why
   this never presented as corruption, only as a lock nothing could shift.

   THE CONSEQUENCE IS THE RECOVERY THIS PORT DOCUMENTS EVERYWHERE.  "run an
   elevated sd -cleanup" is the answer PROJECT_STATUS gives for a dead
   session, and for task locks it was not one.  See PRE_RELEASE_FIXES.md 16,
   which is about the same dead session from the user's side.             */
  for (i = 0; i < 64; i++) {
    if (sysseg->task_locks[i] == user_no)
      sysseg->task_locks[i] = 0;
  }

  /* Give away file locks */

  for (i = 1; i <= sysseg->used_files; i++) {
    fptr = FPtr(i);
    if (fptr->ref_ct != 0) /* File entry is in use */
    {
      if (abs(fptr->file_lock) == user_no) {
        fptr->file_lock = 0;
        clear_waiters(-i);
        // 0538       (fptr->ref_ct)--;   /* Must have been open to us */
      }
    }
  }

  /* Give away record locks */

  for (i = 1; i <= sysseg->numlocks; i++) {
    lptr = RLPtr(i);

    if ((lptr->hash != 0) && (lptr->owner == user_no)) {
      /* We have found a lock to release */
      (RLPtr(lptr->hash)->count)--;
      (sysseg->rl_count)--;
      (FPtr(lptr->file_id)->lock_count)--;
      lptr->hash = 0; /* Free this cell */
      if (lptr->waiters)
        clear_waiters(i);
    }
  }

  /* Give away group locks */

  for (i = 1; i <= sysseg->num_glocks; i++) {
    gptr = GLPtr(i);

    if ((gptr->hash != 0) && (gptr->owner == user_no)) {
      /* We have found a lock to release */
      (GLPtr(gptr->hash)->count)--;
      gptr->hash = 0; /* Free this cell */
    }
  }

  /* Give away file table entries */

  if (!(sysseg->flags & SSF_NO_FILE_CLEANUP)) {
    for (i = 1; i <= sysseg->numfiles; i++) {
      ufm = UFMPtr(uptr, i);
      if (*ufm) {
        /* The following must allow for a reference count of -1 which
           indicates exclusive access to the file.                    */

        fptr = FPtr(i);
        fptr->ref_ct = abs(fptr->ref_ct) - *ufm;
      }
    }
  }

  /* Release user table entry */

  ReleaseLicence(uptr);
}

/* END-CODE */
