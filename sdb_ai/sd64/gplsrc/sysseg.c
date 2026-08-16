/* SYSSEG.C
 * System shared segment management
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
 * 16 Aug 26 Windows port - start_sd() checks whether fork() actually worked.
 *                      A -1 return was falling into the parent branch, so a
 *                      failed start reported success and left a segment behind
 * 14 Aug 26 Windows port - start_sd() and stop_sd() ask the sdwind process
 *                      whether SD is running instead of trusting the shared
 *                      segment, which outlives it
 * 14 Aug 26 Windows port - the daemon is sdwind, not sdlnxd, and start_sd()
 *                      finds it beside the running executable rather than
 *                      under <sysdir>/bin, which no longer holds binaries
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <signal.h>
#include <time.h>
/* 20240126 mab add syslog */
#include <syslog.h>

#include "sd.h"
#include "locks.h"
#include "config.h"
#include "revstamp.h"

/* Special interfaces in sdsem.c for use before shared memory created */

void LockSemaphore(int semno);
void UnlockSemaphore(int semno);

#define SYSSEG_REVSTAMP \
  (((u_int32_t)MAJOR_REV << 16) | ((u_int32_t)MINOR_REV << 8) | BUILD)

/* 13 Aug 26 Windows port - POSIX shared memory (shm_open/mmap) replaces the
   System V segment.  The MSYS2 runtime stubs shmget()/shmat() out with ENOSYS
   and native Windows has no System V IPC.                                  */

#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

/* For CW_CYGWIN_PID_TO_WINPID - see win_pid() */

#include <sys/cygwin.h>

void dump_config(void);

Private bool create_shared_segment(int32_t bytes,
                                   struct CONFIG* cfg,
                                   char* errmsg);

/* Size of the current mapping.  shmdt() could find this from the address
   alone; munmap() must be told, so it is recorded at attach time.          */

Private size_t sysseg_bytes = 0;

/* ====================================================================== */

bool bind_sysseg(bool create, char* errmsg) {
  /* 13Jan22 gwb A bit of refactoring.
   *         renamed "pcode_fu" to "pcode_fd"  It holds a file descriptor, 
   *         not whatever the hell "fu" is. :)
   */

  /* Linux only - Create rather than attach to existing? */

  bool status = FALSE;
  int32_t sharedMemSize;
  int32_t offset;
  int16_t num_glocks;
  struct CONFIG* cfg = NULL;
  int16_t max_users;
  int16_t rlock_entry_size;
  int16_t hi_user_no;
  int user_map_size;
  char path[MAX_PATHNAME_LEN + 1];
  int pcode_fd;
  struct stat statBuf;
  int pcode_len;
  int16_t user_entry_size;

  /* Get the semaphores. If this fails, return directly rather than jumping
    to the normal error exit as we do not need to release the semaphores.   */

  if (!get_semaphores(create, errmsg))
    return FALSE;

  /* 
   * Try to open existing shared segment.
   * Use SHORT_CODE semaphore to prevent two users trying to create the
   * shared segment at once.  We cannot use StartExclusive as this uses
   * the shared segment.                      
   */

  LockSemaphore(SHORT_CODE);

  if (attach_shared_memory()) {
    /* The shared memory is already initialised */

    UnlockSemaphore(SHORT_CODE);

    if (sysseg->revstamp != SYSSEG_REVSTAMP) {
      sprintf(errmsg, "Shared memory revstamp mismatch (%08X %08X)",
              sysseg->revstamp, SYSSEG_REVSTAMP);
      unbind_sysseg();
      goto exit_bind_sysseg;
    }

    if (create) {
      strcpy(errmsg, "SD is already started.");
      goto exit_bind_sysseg;
    }

    /* Copy the template pcfg structure to our private version */

    memcpy(&pcfg, ((char*)sysseg) + sysseg->pcfg_offset, sizeof(struct PCFG));
    status = TRUE;
    goto exit_bind_sysseg;
  }

  /* If we arrive here, the shared segment does not already exist.
    Create a new shared segment and populate it.                   */

  if (!create) {
    strcpy(errmsg, "SD has not been started.");
    goto exit_bind_sysseg;
  }

  /* Read the config file */

  if ((cfg = read_config(errmsg)) == NULL)
    goto exit_bind_sysseg;

  max_users = cfg->max_users;

  num_glocks = max_users * 3; /* Worst case in split, src, tgt, grp 0 */

  sharedMemSize = sizeof(SYSSEG);
  sharedMemSize += cfg->numfiles * sizeof(struct FILE_ENTRY);

  rlock_entry_size = (offsetof(RLOCK_ENTRY, id) + MAX_ID_LEN + 3) & ~3;
  sharedMemSize += cfg->numlocks * rlock_entry_size;

  sharedMemSize += num_glocks * sizeof(struct GLOCK_ENTRY);

  sharedMemSize += NUM_SEMAPHORES * sizeof(SEMAPHORE_ENTRY);

  user_entry_size =
      sizeof(struct USER_ENTRY) + (cfg->numfiles * sizeof(int16_t));
  sharedMemSize += max_users * user_entry_size;

  /* Work out size of user map based on highest user number. Users are
    allocated user numbers in a cycle from 1 to hi_user_no. This upper
    limit has a minimum value of MIN_HI_USER_NO but must be expanded if
    the licence results in more than this number of simultaneous processes. */

  hi_user_no = max(max_users, MIN_HI_USER_NO);
  user_map_size = (hi_user_no + 1) * sizeof(int16_t);
  sharedMemSize += user_map_size;

  /* Find size of pcode */
  /* converted to snprintf() -gwb 22Feb20 */
  if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s%cbin%cpcode", cfg->sysdir, DS, DS) >= (MAX_PATHNAME_LEN + 1)) {
    fprintf(stderr, "Overflowed file/pathname length in bind_sysseg())!\n");
    goto exit_bind_sysseg;
  }
  if (((pcode_fd = open(path, O_RDONLY | O_BINARY)) < 0) || fstat(pcode_fd, &statBuf)) {
    /* return an error message, not a number that has to be looked up! */
    sprintf(errmsg, "Cannot read pcode file - %s.", strerror(errno)); 
    goto exit_bind_sysseg;
  }

  pcode_len = statBuf.st_size;
  sharedMemSize += pcode_len;

  /* Make space for template pcfg structure */

  sharedMemSize += sizeof(struct PCFG);

  /* Create the shared segment */

  if (!create_shared_segment(sharedMemSize, cfg, errmsg)) {
    goto exit_bind_sysseg;
  }

  memset((char*)sysseg, '\0', sharedMemSize);

  sysseg->revstamp = SYSSEG_REVSTAMP;
  sysseg->shmem_size = sharedMemSize;

  sysseg->flags |= SSF_SECURE; /* Secure until we know otherwise */
  sysseg->prtjob = 1;
  sysseg->next_txn_id = 1;

  /* Licence data */

  sysseg->max_users = max_users; /* Total, all process types */

  /* Copy global configuration parameters to sysseg */

  /* !!CONFIG!! */
  sysseg->cmdstack = cfg->cmdstack;                   /* CMDSTACK */
  sysseg->deadlock = cfg->deadlock;                   /* DEADLOCK */
  sysseg->errlog = cfg->errlog;                       /* ERRLOG */
  sysseg->fds_limit = cfg->fds_limit;                 /* FDS */
  sysseg->fixusers_base = cfg->fixusers_base;         /* FIXUSERS */
  sysseg->fixusers_range = cfg->fixusers_range;       /* FIXUSERS */
  sysseg->jnlmode = cfg->jnlmode;                     /* JNLMODE */
  strcpy((char*)(sysseg->jnldir), cfg->jnldir);       /* JNLDIR */
  sysseg->maxidlen = cfg->maxidlen;                   /* MAXIDLEN */
  sysseg->netfiles = cfg->netfiles;                   /* NETFILES */
  sysseg->pdump = cfg->pdump;                         /* PDUMP */
  sysseg->portmap_base_port = cfg->portmap_base_port; /* PORTMAP */
  sysseg->portmap_base_user = cfg->portmap_base_user; /* PORTMAP */
  sysseg->portmap_range = cfg->portmap_range;         /* PORTMAP */
  strcpy((char*)(sysseg->sysdir), cfg->sysdir);       /* SDSYS */
  strcpy((char*)(sysseg->startup), cfg->startup);     /* STARTUP */

  /* Create dynamically sized parts of segment */

  offset = sizeof(SYSSEG);
  sysseg->numfiles = cfg->numfiles;
  sysseg->file_table = offset;
  offset += (cfg->numfiles * sizeof(struct FILE_ENTRY));

  sysseg->numlocks = cfg->numlocks;
  sysseg->rlock_table = offset;
  sysseg->rlock_entry_size = rlock_entry_size;
  offset += (cfg->numlocks * rlock_entry_size);

  sysseg->num_glocks = num_glocks;
  sysseg->glock_table = offset;
  offset += (num_glocks * sizeof(struct GLOCK_ENTRY));

  sysseg->semaphore_table = offset;
  offset += NUM_SEMAPHORES * sizeof(SEMAPHORE_ENTRY);

  sysseg->user_table = offset;
  sysseg->user_entry_size = user_entry_size;
  offset += max_users * user_entry_size;

  sysseg->hi_user_no = hi_user_no;
  sysseg->user_map = offset;
  offset += user_map_size;

  /* Load pcode */

  sysseg->pcode_offset = offset;
  sysseg->pcode_len = pcode_len;

  if (read(pcode_fd, ((char*)sysseg) + offset, pcode_len) != pcode_len) {
    sprintf(errmsg, "Unable to load pcode [%d].\n", errno);
    goto exit_bind_sysseg;
  }

  close(pcode_fd);
  offset += pcode_len;

  /* Copy our pcfg to become the template for new processes */

  sysseg->pcfg_offset = offset;
  memcpy(((char*)sysseg) + offset, &pcfg, sizeof(struct PCFG));
  offset += sizeof(struct PCFG);

  UnlockSemaphore(SHORT_CODE);

  /* Reset file stats timer. This must be done after creating the dynamic
    tables as sdtime() may reference user table. Furthermore, because
    sdtime() may end up calling raise_event(), which requires the short
    code semaphore, we need to be very sinful and do this operation after
    releasing the semaphore that we already hold. Given that we are
    creating the shared memory, the risk of collision is extremely low
    and the effect would be unimportant anyway.                          */

  sysseg->global_stats.reset = sdtime();

  status = TRUE;

  if (cfg != NULL)
    k_free(cfg);

exit_bind_sysseg:

  if (!status)
    stop_sd();

  return status;
}

/* ======================================================================
   create_shared_segment()                                                */

Private bool create_shared_segment(int32_t bytes,
                                   struct CONFIG* cfg,
                                   char* errmsg) {
  int fd;

  if ((fd = shm_open(SD_POSIX_SHM_NAME, O_CREAT | O_RDWR, 0666)) == -1) {
    sprintf(errmsg, "Error %d creating shared segment.", errno);
    return FALSE;
  }

  /* Unlike shmget(), shm_open() always creates a zero length object, so the
     size has to be set explicitly before it can be mapped.                 */

  if (ftruncate(fd, (off_t)bytes)) {
    sprintf(errmsg, "Error %d sizing shared segment.", errno);
    close(fd);
    shm_unlink(SD_POSIX_SHM_NAME);
    return FALSE;
  }

  sysseg = (SYSSEG*)mmap(NULL, (size_t)bytes, PROT_READ | PROT_WRITE,
                         MAP_SHARED, fd, 0);
  close(fd); /* The mapping outlives the descriptor */

  if (sysseg == MAP_FAILED) {
    sysseg = NULL;
    sprintf(errmsg, "Error %d attaching to new shared segment.", errno);
    shm_unlink(SD_POSIX_SHM_NAME);
    return FALSE;
  }

  sysseg_bytes = (size_t)bytes;

  return TRUE;
}

/* ======================================================================
   Attach to shared memory segment                                        */

bool attach_shared_memory() {
  int fd;
  struct stat statbuf;

  if ((fd = shm_open(SD_POSIX_SHM_NAME, O_RDWR, 0666)) == -1)
    return FALSE; /* Not started */

  /* The creator sizes the object in a separate step from creating it.  A zero
     length here means we looked in that window and it is not usable yet.    */

  if (fstat(fd, &statbuf) || statbuf.st_size == 0) {
    close(fd);
    return FALSE;
  }

  sysseg = (SYSSEG*)mmap(NULL, (size_t)statbuf.st_size, PROT_READ | PROT_WRITE,
                         MAP_SHARED, fd, 0);
  close(fd);

  if (sysseg == MAP_FAILED) {
    sysseg = NULL;
    fprintf(stderr, "Error %d attaching to shared segment.\n", errno);
    return FALSE;
  }

  sysseg_bytes = (size_t)statbuf.st_size;

  return TRUE;
}

/* ====================================================================== */

void unbind_sysseg() {
  if (sysseg != NULL) {
    munmap((void*)sysseg, sysseg_bytes);
    sysseg = NULL;
    sysseg_bytes = 0;
  }
}

/* ======================================================================
   win_pid()  -  The Windows process id behind an MSYS2 one

   14 Aug 26 Windows port.  getpid() under the MSYS2 runtime answers with the
   runtime's own process id, which is not the number Task Manager, Get-Process
   or Stop-Process use: the daemon that reported itself here as pid 87 was pid
   14712 to Windows.  Printing the runtime's number in a "stop it" instruction
   is worse than printing none, because Stop-Process -Id would then act on
   whatever unrelated process happens to hold it.  Answers 0 if the runtime
   cannot translate, and the caller then says nothing about a pid at all.   */

Private int win_pid(int pid) {
  return (int)cygwin_internal(CW_CYGWIN_PID_TO_WINPID, pid);
}

/* ======================================================================
   process_exists()  -  Is this pid still a process?

   kill() with signal zero performs the existence and permission checks
   without delivering anything, so it answers for a process this session
   could not signal.  EPERM is a yes: the process is there and belongs to a
   more privileged session.  Same idiom as clopts.c.                       */

Private bool process_exists(int pid) {
  return (!kill(pid, 0) || (errno == EPERM));
}

/* ======================================================================
   sd_state()  -  What is actually running behind the shared segment?

   14 Aug 26 Windows port.  "SD is already started" was answered by objects
   rather than by processes: the semaphore set in get_semaphores() and the
   segment in bind_sysseg() both outlive the processes that made them.  So a
   session killed while SD was up left sd -start reporting success and doing
   nothing, with the system unusable until somebody worked out that sd -stop
   was the way back (PROJECT_STATUS.md section 6, section 7 step 1d).  Ask
   the daemon instead - it is the process whose life SD's really is.        */

#define SD_STOPPED 0  /* No shared segment, or not one this build can read */
#define SD_RUNNING 1  /* Segment and daemon both present */
#define SD_WRECKAGE 2 /* Segment left behind by a daemon that has gone */

Private int sd_state(int* daemon_pid, int* sessions) {
  int state = SD_STOPPED;
  int16_t i;
  USER_ENTRY* uptr;

  *daemon_pid = 0;
  *sessions = 0;

  if (!attach_shared_memory())
    return SD_STOPPED;

  /* Every offset past the revstamp belongs to the build that created the
     segment.  If it is not this one, read no further and leave the report to
     bind_sysseg(), which says so properly.                                 */

  if (sysseg->revstamp == SYSSEG_REVSTAMP) {
    state = SD_WRECKAGE;

    if ((sysseg->sdwind_pid > 0) && process_exists(sysseg->sdwind_pid)) {
      *daemon_pid = sysseg->sdwind_pid;
      state = SD_RUNNING;
    }

    /* What an sd -stop would take with it.  The advice that follows from
       SD_WRECKAGE is only safe when the answer is none.                    */

    for (i = 1; i <= sysseg->max_users; i++) {
      uptr = UPtr(i);
      if (uptr->uid && (uptr->pid > 0) && process_exists(uptr->pid))
        (*sessions)++;
    }
  }

  unbind_sysseg();

  return state;
}

/* ======================================================================
   start_sd()                                                             */

bool start_sd() {
  char errmsg[80 + 1];
  int cpid;
  int i;
  char path[MAX_PATHNAME_LEN + 1];
  char bindir[MAX_PATHNAME_LEN + 1];
  int daemon_pid;
  int sessions;

  /* 14 Aug 26 Windows port - decide what is running before touching anything.
     Both "already started" answers below the fold are about objects and not
     processes; see sd_state().  Neither clears the wreckage here: sd -start
     silently discarding somebody else's shared segment is a destructive
     default, and the session that sees this message is the one that knows
     whether the sessions counted are worth keeping.                        */

  switch (sd_state(&daemon_pid, &sessions)) {
    case SD_RUNNING:
      daemon_pid = win_pid(daemon_pid);
      if (daemon_pid > 0) {
        fprintf(stderr, "SD is already started - %s is running as pid %d.\n",
                SDWIND_NAME, daemon_pid);
      } else {
        fprintf(stderr, "SD is already started - %s is running.\n",
                SDWIND_NAME);
      }
      return FALSE;

    case SD_WRECKAGE:
      fprintf(stderr,
              "SD did not shut down cleanly: the shared segment is still "
              "here but %s is not running.\n",
              SDWIND_NAME);
      if (sessions) {
        fprintf(stderr,
                "%d SD session(s) are still attached to it, and sd -stop "
                "will end them.\n",
                sessions);
      }
      fprintf(stderr, "Run sd -stop to clear it, then sd -start again.\n");
      return FALSE;

    default: /* SD_STOPPED - nothing there, carry on and create it */
      break;
  }

  if (!bind_sysseg(TRUE, errmsg)) {
    fprintf(stderr, "%s\n", errmsg);
    return FALSE;
  }

  /* Start sdwind daemon */

  sysseg->sdwind_pid = -1; /* Stays -ve if fails to start */
  cpid = fork();

  /* 16 Aug 26 Windows port - A FAILED fork() USED TO LOOK LIKE SUCCESS.
     fork() returns -1 on failure, and -1 is not 0, so it fell into the "Parent
     process" branch below: the daemon was never started, nothing said so, and
     start_sd() went on to report "SD has been started".  That is exactly what
     the service produced on 16 Aug 2026 - Running, no sdwind, and a segment
     plus six semaphores left behind that broke every later session with
     "Error 116 getting semaphores" (PROJECT_STATUS.md header item 1).

     The segment is deliberately NOT torn down here.  Removing it is sd -stop's
     job and the SD_WRECKAGE path above already says so in those words; undoing
     bind_sysseg() from this point would duplicate that badly.  What matters is
     that the caller now hears about it instead of being told it worked.      */

  if (cpid < 0) {
    fprintf(stderr, "Cannot start %s - fork() failed: %s\n", SDWIND_NAME,
            strerror(errno));
    fprintf(stderr, "Run sd -stop to clear what this left behind.\n");
    return FALSE;
  }

  if (cpid == 0) { /* Child process */
    for (i = 3; i < 1024; i++)
      close(i);
    daemon(1, 1);

    /* 14 Aug 26 Windows port - this built "<sysdir>/bin/sdlnxd", which was
       right while the Linux install kept the executables and the pcode
       composite library in the same directory.  The Windows layout splits
       them (PROJECT_STATUS.md 5.8), so <sysdir>/bin holds only pcode and
       pcode.old and the daemon was never found - silently, because this is a
       forked child that has already daemon()ed.  See exepath.c.            */

    if (!exe_directory(bindir, sizeof(bindir))) {
      fprintf(stderr, "Cannot locate the SD program directory - %s not started\n",
              SDWIND_NAME);
      _exit(1);
    }

    /* converted to snprintf() -gwb 22Feb20 */
    if (snprintf(path, sizeof(path), "%s/%s", bindir, SDWIND_NAME) >=
        (int)sizeof(path)) {
      fprintf(stderr, "Overflowed file/pathname length in start_sd()!\n");
      _exit(1);
    }

    execl(path, path, NULL);

    /* execl() returns only on failure.  This child has already detached, so
       it must not fall back into the caller's code - which is what used to
       happen, and is why a missing daemon produced no symptom at all.      */

    fprintf(stderr, "Cannot start %s from %s - %s\n", SDWIND_NAME, path,
            strerror(errno));
    _exit(1);
  } else /* Parent process */
      // {
      // Moved to sdwind:   sysseg->sdwind_pid = cpid;   /* -ve if failed to start */
      // }

      /* 16 Aug 26 Windows port - WAIT FOR THE DAEMON BEFORE LETTING GO.
         Two things depend on this and the first one is new:

         THE SEMAPHORES DIE WITH THE LAST HANDLE.  They are Win32 objects now
         (sdsem.c) rather than files in /dev/shm, so if this process created
         them and exited before sdwind had opened them, the set would simply
         evaporate and the daemon would find nothing.  Holding on until sdwind
         has attached closes that window.

         AND "sd -start" STOPS LYING.  It used to fork and return TRUE without
         ever looking, so it reported success when the daemon had failed to
         start at all - which is how a Windows service came to report RUNNING
         over a machine with no SD on 16 Aug 2026, twice.  sdwind publishes its
         pid into the segment once it is up (sdwind.c), so that is what to
         wait for.

         Ten seconds is generous: sdwind attaches immediately or not at all.
         Failing here does NOT tear the segment down - sd -stop is what clears
         a half-started system, and it says so.                              */

      {
        int waited;

        for (waited = 0; waited < 100; waited++) {
          if (sysseg->sdwind_pid > 0)
            break;
          usleep(100000); /* 100ms */
        }

        if (sysseg->sdwind_pid <= 0) {
          fprintf(stderr,
                  "%s did not start within 10 seconds, so SD is not running.\n",
                  SDWIND_NAME);
          fprintf(stderr, "Run sd -stop to clear what this left behind.\n");
          return FALSE;
        }
      }

      /* Run startup command, if defined */

      if (sysseg->startup[0] != '\0') {
    cpid = fork();
    if (cpid == 0) { /* Child process */
      for (i = 3; i < 1024; i++)
        close(i);
      daemon(1, 1);
      /* converted to snprintf() -gwb 22Feb20 */
      if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s/bin/sd", sysseg->sysdir) >=
          (MAX_PATHNAME_LEN + 1)) {
        fprintf(stderr, "Overflowed file/pathname length in start_sd()!\n");
        return FALSE;
      } else
        execl(path, path, "-aSDSYS", sysseg->startup, NULL);
    }
  }

  return TRUE;
}

/* ======================================================================
   stop_sd()                                                              */

bool stop_sd() {
  int16_t i;
  USER_ENTRY* uptr;
  int16_t retry;
  int active;
  int daemon_pid = 0;            /* Daemon named in the segment, 0 if none */
  bool daemon_signalled = FALSE; /* SIGTERM was accepted, so wait for it */
  bool daemon_refused = FALSE;   /* Alive, and not this session's to signal */
  bool daemon_stuck = FALSE;     /* Signalled, still there when we gave up */

  /* We may already hold a mapping if we were called from the bind_sysseg
     error path.  Re-attaching would leak a second one.                     */

  if (sysseg != NULL || attach_shared_memory()) {
    /* Send all SD processes the SIGTERM signal */

    for (i = 1; i <= sysseg->max_users; i++) {
      uptr = UPtr(i);

      /* 14 Aug 26 Windows port - pid MUST be tested, not just uid.
         kill(0, SIGTERM) does not mean "no process", it means EVERY PROCESS
         IN THE CALLER'S PROCESS GROUP - so a user table entry that has been
         claimed but not yet filled in, or left behind by a process that died
         between the two, made "sd -stop" terminate whatever launched it.
         Observed while building the installer: sd -stop run from a script
         killed the Python process driving it and the shell above that, with
         no error anywhere, so the whole build simply stopped.  A negative pid
         is just as bad - kill(-n) signals a process group too.
         The liveness poll below always had this test; this loop did not.   */

      if (uptr->uid && uptr->pid > 0) {
        kill(uptr->pid, SIGTERM);
      }
    }

    /* Shutdown the sdwind daemon if it is running */

    /* > 0 rather than merely non-zero, for the reason above: a negative pid
       signals a process group.  Zero was already excluded here. */

    /* 14 Aug 26 Windows port - kill()'s return value was discarded here, so a
       session less elevated than the one that started the daemon got EPERM,
       left sdwind running, and printed "has been shut down" anyway
       (PROJECT_STATUS.md section 6).  The teardown below is still right and
       still wanted - the segment and the semaphores are this command's to
       remove - but a daemon that outlives it has to be reported: it holds a
       mapping of a segment nothing else can see, and the next sd -start
       creates a second daemon beside it.                                    */

    if (sysseg->sdwind_pid > 0) {
      daemon_pid = sysseg->sdwind_pid;
      if (!kill(daemon_pid, SIGTERM))
        daemon_signalled = TRUE;
      else if (errno != ESRCH) /* ESRCH: already gone, which is the aim */
        daemon_refused = TRUE;
    }

    /* Wait for everyone to go.  System V exposed an attach count that fell to
       zero as processes detached; POSIX shared memory has no equivalent, so
       poll the user table for processes that still exist instead.  kill()
       with signal zero performs the permission and existence checks without
       delivering anything, and so reports whether a pid is still live even if
       the process died without clearing its own table entry.               */

    for (retry = 10; retry; retry--) {
      active = 0;

      for (i = 1; i <= sysseg->max_users; i++) {
        uptr = UPtr(i);
        if (uptr->uid && uptr->pid > 0 && kill(uptr->pid, 0) == 0)
          active++;
      }

      /* The daemon was never counted here, which is the other half of why
         nothing noticed it surviving: this poll walks the user table only,
         and sdwind is not in it.                                           */

      if (daemon_signalled && !kill(daemon_pid, 0))
        active++;

      if (active == 0)
        break; /* Everyone has gone */

      sleep(1);
    }

    if (daemon_signalled && !kill(daemon_pid, 0))
      daemon_stuck = TRUE; /* Took the signal and has not acted on it */

    /* Dettach the shared memory */

    unbind_sysseg();
  }

  /* Say so before the caller announces a shutdown.  The segment and the
     semaphores really are going, so this is a warning and not a failure -
     but an orphaned daemon is the one thing sd -stop cannot clear up, and
     the next sd -start will build a second system around it.               */

  if (daemon_refused || daemon_stuck) {
    daemon_pid = win_pid(daemon_pid);

    if (daemon_pid > 0) {
      fprintf(stderr, "Warning: %s (pid %d) is still running.\n", SDWIND_NAME,
              daemon_pid);
    } else {
      fprintf(stderr, "Warning: %s is still running.\n", SDWIND_NAME);
    }

    if (daemon_refused) {
      fprintf(stderr, "It belongs to a session with more privilege than this "
                      "one, so it could not be\nsignalled.\n");
    } else {
      fprintf(stderr, "It did not stop when it was asked to.\n");
    }

    if (daemon_pid > 0) {
      fprintf(stderr, "Stop it from an elevated session with \"Stop-Process "
                      "-Id %d -Force\" before\nstarting SD again, or the "
                      "machine will run two daemons.\n",
              daemon_pid);
    } else {
      fprintf(stderr, "Stop it from an elevated session before starting SD "
                      "again, or the machine\nwill run two daemons.\n");
    }
  }

  /* Remove the name.  As with IPC_RMID, any mapping a straggler still holds
     stays valid until that process exits.                                  */

  if (shm_unlink(SD_POSIX_SHM_NAME) && (errno != ENOENT)) {
/* 20240126 mab add syslog */
    syslog (LOG_INFO, "Error %d deleting shared memory", errno);
    fprintf(stderr, "Error %d deleting shared memory\n", errno);
    return FALSE;
  }

  delete_semaphores();

  return TRUE;
}

/* END-CODE */
