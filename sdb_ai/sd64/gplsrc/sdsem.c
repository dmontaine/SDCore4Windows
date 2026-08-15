/* SDSEM.C
 * Semaphore functions.
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
 * 31 Dec 23 SD launch - prior history suppressed
 * rev 0.9.0 Jan 25 d-chou add IPC_NOWAIT and RelinquishTimeslice (sched_yield) to LockSemaphore
 * 13 Aug 26 Windows port - System V semaphores replaced by POSIX named
 *           semaphores.  The MSYS2 runtime declares semget()/semop() but the
 *           implementations return ENOSYS, and native Windows has no System V
 *           IPC at all.  sem_open() works on both.
 * 14 Aug 26 Windows port - a leftover semaphore set no longer reports "SD is
 *           already started", which was true of the objects and not of the
 *           system.  See sd_state() in sysseg.c.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * The semaphore set is a group of NUM_SEMAPHORES binary semaphores, each
 * created with a value of one.  Under System V these lived in a single set
 * addressed by one id; as POSIX named semaphores each is a separate kernel
 * object, so the id is replaced by an array of handles held in this module.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include <semaphore.h>
#include <fcntl.h>
#include <errno.h>
#include <sched.h>

Private sem_t* sd_sem[NUM_SEMAPHORES];

Private void semaphore_name(char* buff, int semno) {
  sprintf(buff, SD_POSIX_SEM_FMT, semno);
}

/* ======================================================================
   close_semaphores()  -  Release our handles, leaving the objects intact   */

Private void close_semaphores() {
  int16_t i;

  for (i = 0; i < NUM_SEMAPHORES; i++) {
    if (sd_sem[i] != NULL) {
      sem_close(sd_sem[i]);
      sd_sem[i] = NULL;
    }
  }
}

/* ======================================================================
   get_semaphores()  -  Get inter-process semaphores                      */

bool get_semaphores(bool create, char* errmsg) {
  int16_t i;
  char name[MAX_PATHNAME_LEN + 1];
  sem_t* sem;

  /* Probe for an existing set.  Opening without O_CREAT fails with ENOENT if
     the semaphores have not been created, which is the test that semget()
     with a zero count used to perform.                                     */

  semaphore_name(name, 0);
  sem = sem_open(name, 0);
  if (sem != SEM_FAILED) {
    /* Semaphores already exist */

    sem_close(sem);

    if (create) {
      /* 14 Aug 26 Windows port - this is the message a stale system actually
         produced, because get_semaphores() runs before the segment is looked
         at: "SD is already started" off a semaphore set whose SD had been
         killed (PROJECT_STATUS.md section 6).  start_sd() now asks the sdwind
         process before it gets here, so reaching this point means the
         semaphores have outlived the segment - a half torn down system rather
         than a running one.  The advice is conditional because two starts
         racing can also land here, and sd -stop would kill the winner.      */

      strcpy(errmsg,
             "Semaphores are already present.  If SD is not running, "
             "sd -stop clears them.");
      return FALSE;
    }

    /* Attach to the existing set */

    for (i = 0; i < NUM_SEMAPHORES; i++) {
      semaphore_name(name, i);
      sd_sem[i] = sem_open(name, 0);
      if (sd_sem[i] == SEM_FAILED) {
        sd_sem[i] = NULL;
        sprintf(errmsg, "Error %d attaching to semaphores", errno);
        close_semaphores();
        return FALSE;
      }
    }

    return TRUE;
  }

  if (errno != ENOENT) {
    sprintf(errmsg, "Error %d getting semaphores", errno);
    return FALSE;
  }

  /* Semaphores do not already exist */

  if (!create) {
    strcpy(errmsg, "SD has not been started");
    return FALSE;
  }

  /* Create new semaphores, each initialised to one.  O_EXCL closes the race
     with another process starting SD at the same moment.                   */

  for (i = 0; i < NUM_SEMAPHORES; i++) {
    semaphore_name(name, i);
    sd_sem[i] = sem_open(name, O_CREAT | O_EXCL, 0666, 1);
    if (sd_sem[i] == SEM_FAILED) {
      sd_sem[i] = NULL;
      sprintf(errmsg, "Error %d allocating semaphores", errno);

      /* Unwind the ones we did create so a failed start leaves nothing
         behind to make the next attempt report "already started".         */

      while (--i >= 0) {
        semaphore_name(name, i);
        sem_close(sd_sem[i]);
        sd_sem[i] = NULL;
        sem_unlink(name);
      }

      return FALSE;
    }
  }

  return TRUE;
}

/* ====================================================================== */

void delete_semaphores() {
  int16_t i;
  char name[MAX_PATHNAME_LEN + 1];

  /* sem_unlink() removes the name whether or not this process holds a handle,
     matching the old semctl(IPC_RMID) behaviour.                            */

  for (i = 0; i < NUM_SEMAPHORES; i++) {
    if (sd_sem[i] != NULL) {
      sem_close(sd_sem[i]);
      sd_sem[i] = NULL;
    }

    semaphore_name(name, i);
    sem_unlink(name);
  }
}

/* ======================================================================
   Variants on StartExclusive and EndExclusive for use with no shared mem */

void LockSemaphore(int semno) {
// rev 0.9.0
  while (sem_trywait(sd_sem[semno]) != 0) {
// rev 0.9.0
  	RelinquishTimeslice;
  }
}

void UnlockSemaphore(int semno) {
  sem_post(sd_sem[semno]);
}

/* ====================================================================== */

void StartExclusive(int semno, int16_t where) {
  register SEMAPHORE_ENTRY* semptr;

  LockSemaphore(semno);
  semptr = (((SEMAPHORE_ENTRY*)(((char*)sysseg) + sysseg->semaphore_table)) +
            (semno));
  semptr->owner = process.user_no;
  semptr->where = where;
}

void EndExclusive(int semno) {
  register SEMAPHORE_ENTRY* semptr;

  semptr = (((SEMAPHORE_ENTRY*)(((char*)sysseg) + sysseg->semaphore_table)) +
            (semno));
  semptr->owner = 0;
  UnlockSemaphore(semno);
}

/* END-CODE */
