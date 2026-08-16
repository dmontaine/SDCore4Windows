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
 * 16 Aug 26 Windows port - POSIX named semaphores replaced by native Win32
 *           ones in the Global namespace.  sem_open() cannot be used in
 *           session 0 and SD has to run as a service.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * The semaphore set is a group of NUM_SEMAPHORES binary semaphores, each
 * created with a value of one.  Under System V these lived in a single set
 * addressed by one id; as named objects each is a separate kernel object, so
 * the id is replaced by an array of handles held in this module.
 *
 * THE SEMAPHORES ARE NATIVE Win32 OBJECTS, through win32sem.c.
 *
 * PROJECT_STATUS.md 5.4 keeps two toolchains apart on purpose - the server on
 * the MSYS2 POSIX runtime, the client DLL and the service wrapper native - and
 * linuxlb.c records the decision NOT to drag windows.h across that line for
 * IsElevated(), which asks getgrouplist() instead.  That reasoning still holds
 * everywhere else.  It does not hold here, because there is no POSIX answer:
 *
 *   sem_open() IN SESSION 0 BLOCKS FOR TEN SECONDS AND FAILS WITH ETIMEDOUT.
 *
 * Measured 16 Aug 2026, with the process that created the semaphores and the
 * process that failed to open them BOTH running as LocalSystem in session 0 -
 * so it is not about crossing sessions, it is that the runtime's POSIX
 * semaphores do not work there at all.  The consequence was that SD could not
 * be started by a Windows service, and the owner's requirement is a production
 * system with nobody logged in, available to every user from system startup.
 * The owner sanctioned the exception on 16 Aug 2026.
 *
 * THIS FILE STILL DOES NOT INCLUDE windows.h, AND CANNOT.  Tried first, and it
 * does not compile: linuxlb.h defines GetCurrentProcessId() as a
 * nought-argument macro while w32api declares it taking VOID, SD declares its
 * own Sleep with a different prototype, and SD's "Private" macro expands inside
 * the w32api headers.  So the Win32 half is in win32sem.c, which includes
 * windows.h and no SD header at all, and this file talks to it through void*
 * handles and ordinary C strings.
 *
 * WHAT CHANGES IN BEHAVIOUR, AND IT IS AN IMPROVEMENT.  A POSIX named
 * semaphore is a file in /dev/shm and outlives every process that used it,
 * which is how this port kept producing sets with no SD behind them - the
 * "Error 116 getting semaphores" wreckage that broke installs all morning on
 * 16 Aug 2026.  A Win32 semaphore is reference counted: when the last handle
 * closes, the object is gone.  So a set that EXISTS now means a process is
 * holding it, and orphaned sets cannot happen.
 *
 * THE PRICE OF THAT, AND WHERE IT IS PAID.  Because the objects die with the
 * last handle, "sd -start" may not create them and exit before sdwind has
 * attached, or the set would evaporate in between.  start_sd() in sysseg.c
 * waits for the daemon to attach before it returns - see the comment there.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include <errno.h>
#include <sched.h>

#include "win32sem.h"

/* void*, not HANDLE: see the header comment - windows.h cannot be included
   here, so the handles stay opaque on this side of the line.                */

Private void* sd_sem[NUM_SEMAPHORES];

Private void semaphore_name(char* buff, int semno) {
  sprintf(buff, SD_WIN32_SEM_FMT, semno);
}

/* ======================================================================
   close_semaphores()  -  Release our handles.

   With Win32 objects this is also what destroys them, once no process is left
   holding one.  There is no unlink and none is wanted.                      */

Private void close_semaphores() {
  int16_t i;

  for (i = 0; i < NUM_SEMAPHORES; i++) {
    if (sd_sem[i] != NULL) {
      w32sem_close(sd_sem[i]);
      sd_sem[i] = NULL;
    }
  }
}

/* ======================================================================
   get_semaphores()  -  Get inter-process semaphores                      */

bool get_semaphores(bool create, char* errmsg) {
  int16_t i;
  char name[MAX_PATHNAME_LEN + 1];
  void* h;
  int already;
  unsigned long err;

  /* Probe for an existing set, exactly as the POSIX version did: opening
     without creating tells us whether SD is up.                             */

  semaphore_name(name, 0);
  h = w32sem_open(name);
  if (h != NULL) {
    w32sem_close(h);

    if (create) {
      /* Unchanged from the POSIX version, and still conditional for the same
         reason: two starts racing land here too, and sd -stop would kill the
         winner.  What HAS changed is that this can no longer be a set left by
         a dead SD - a Win32 semaphore does not outlive its last handle - so
         reaching this really does mean something is holding it.             */

      strcpy(errmsg,
             "Semaphores are already present.  If SD is not running, "
             "sd -stop clears them.");
      return FALSE;
    }

    /* Attach to the existing set */

    for (i = 0; i < NUM_SEMAPHORES; i++) {
      semaphore_name(name, i);
      sd_sem[i] = w32sem_open(name);
      if (sd_sem[i] == NULL) {
        sprintf(errmsg, "Error %lu attaching to semaphores",
                w32sem_last_error());
        close_semaphores();
        return FALSE;
      }
    }

    return TRUE;
  }

  err = w32sem_last_error();
  if (!w32sem_absent(err)) {
    sprintf(errmsg, "Error %lu getting semaphores", err);
    return FALSE;
  }

  /* Semaphores do not already exist */

  if (!create) {
    strcpy(errmsg, "SD has not been started");
    return FALSE;
  }

  /* Create new semaphores, each initialised to one.  ERROR_ALREADY_EXISTS
     closes the race with another process starting SD at the same moment,
     which is what O_EXCL did before.                                        */

  for (i = 0; i < NUM_SEMAPHORES; i++) {
    semaphore_name(name, i);
    sd_sem[i] = w32sem_create(name, SD_USERS_GROUP, &already);

    if (sd_sem[i] != NULL && already) {
      strcpy(errmsg, "Another process started SD while this one was starting");
      close_semaphores(); /* includes the one just opened */
      return FALSE;
    }

    if (sd_sem[i] == NULL) {
      sprintf(errmsg, "Error %lu allocating semaphores", w32sem_last_error());

      /* Unwind the ones we did create.  Closing them is enough - the objects
         go with the last handle, so nothing is left for the next start to
         trip over.  That is the whole difference from the POSIX set this
         replaced, which needed sem_unlink() and left wreckage when it did not
         get it.                                                             */

      close_semaphores();
      return FALSE;
    }
  }

  return TRUE;
}

/* ======================================================================
   delete_semaphores()  -  Give up our handles, destroying the set if we hold
   the last ones.  There is nothing else to remove: unlike a POSIX named
   semaphore there is no name left in a filesystem afterwards.              */

void delete_semaphores() {
  close_semaphores();
}

/* ======================================================================
   Variants on StartExclusive and EndExclusive for use with no shared mem */

void LockSemaphore(int semno) {
// rev 0.9.0
  while (!w32sem_trywait(sd_sem[semno])) {
// rev 0.9.0
  	RelinquishTimeslice;
  }
}

void UnlockSemaphore(int semno) {
  w32sem_post(sd_sem[semno]);
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
