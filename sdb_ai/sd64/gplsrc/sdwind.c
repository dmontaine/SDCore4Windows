/* SDWIND.C
 * SD Windows daemon.
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
 * 16 Aug 26 Windows port - report why startup failed instead of exiting
 *                      silently; the errmsg from get_semaphores() was being
 *                      filled in and then discarded
 * 14 Aug 26 Windows port - renamed from sdlnxd, and the cleanup session is
 *                      launched from beside the running executable rather
 *                      than from <sysdir>/bin, which holds no binaries
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * The background daemon.  It was sdlnxd, "SD Linux daemon", which is the
 * wrong name in a Windows-only repository; the name now lives in one place,
 * SDWIND_NAME in sddefs.h, which start_sd() also uses to launch it.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#define Public
#define init(a) = a
#include "sd.h"

#include <time.h>
#include <ctype.h>
/* 13 Aug 26 Windows port - POSIX shared memory in place of System V */
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sched.h>

bool terminate = FALSE;

void check_lost_users(void);

void signal_handler(int signum);

/* ====================================================================== */

int main() {
  char errmsg[80];
  int timer = 0;
  int fd;
  struct stat statbuf;

  process.user_no = -2; /* Mark as sdwind for semaphore table */

  signal(SIGTERM, signal_handler);

  /* Attach the shared memory segment */

  /* 16 Aug 26 Windows port - SAY WHY, RATHER THAN JUST DYING.  Every failure
     below used to be a bare exit(1) or exit(2), and the exit(2) threw away the
     errmsg get_semaphores() had just filled in.  On 16 Aug 2026 the service
     started nothing and there was NOTHING to read anywhere - the fault had to
     be narrowed by running this program by hand and looking at its exit code.

     log_message() is not available here and cannot be: it takes ERRLOG_SEM,
     and the whole point of these branches is that the segment or the
     semaphores are not attached yet.  So stderr is all there is - which is
     enough when the daemon is run by hand, and is the first thing to try when
     it will not start.  The exit codes are unchanged and still discriminate:
     1 the shared memory segment, 2 the semaphores.                          */

  if ((fd = shm_open(SD_POSIX_SHM_NAME, O_RDWR, 0666)) == -1) {
    fprintf(stderr, "%s: cannot open shared memory %s - %s\n", SDWIND_NAME,
            SD_POSIX_SHM_NAME, strerror(errno));
    exit(1);
  }

  if (fstat(fd, &statbuf) || (statbuf.st_size == 0)) {
    fprintf(stderr, "%s: shared memory %s is unreadable or empty - %s\n",
            SDWIND_NAME, SD_POSIX_SHM_NAME, strerror(errno));
    close(fd);
    exit(1);
  }

  sysseg = (SYSSEG*)mmap(NULL, (size_t)statbuf.st_size, PROT_READ | PROT_WRITE,
                         MAP_SHARED, fd, 0);
  close(fd);

  if (sysseg == MAP_FAILED) {
    fprintf(stderr, "%s: cannot map shared memory - %s\n", SDWIND_NAME,
            strerror(errno));
    sysseg = NULL;
    exit(1);
  }

  /* Get access to semaphores */

  if (!get_semaphores(FALSE, errmsg)) {
    fprintf(stderr, "%s: %s\n", SDWIND_NAME, errmsg);
    exit(2);
  }

  /* Set process id into shared memory */

  sysseg->sdwind_pid = getpid();

  /* ========================= Main loop ========================= */

  while (!terminate) {
    timer++;

    /* One minute actions */

    if ((timer % 5) == 0) {
      /* Five minute actions */

      check_lost_users();
    }

    sleep(60);
  }

  /* Tidy up on our way out */

  munmap((void*)sysseg, (size_t)statbuf.st_size); /* Dettach shared memory */

  return 0;
}

/* ======================================================================
   check_lost_users()  -  Clear down "lost" processes                     */

void check_lost_users() {
  USER_ENTRY* uptr;
  int32_t pid;
  int16_t u;
  int16_t num_checked = 0;
  bool lost_user_detected = FALSE;
  char bindir[MAX_PATHNAME_LEN + 1];
  /* Room for the directory plus "'/sd' -cleanup" and its terminator. */
  char cmd[MAX_PATHNAME_LEN + 20];

  StartExclusive(SHORT_CODE, 69);

  for (u = 1; u <= sysseg->max_users; u++) {
    uptr = UPtr(u);
    pid = uptr->pid;
    if (uptr->uid) {
      if ((++num_checked % 5) == 0) {
        /* Be nice - don't hold sempahore for entire table scan */

        EndExclusive(SHORT_CODE);
        RelinquishTimeslice;
        StartExclusive(SHORT_CODE, 69);
        if (uptr->uid == 0)
          continue; /* User logged out */
      }

      if (kill(pid, 0) && (errno != EPERM)) {
        lost_user_detected = TRUE;
        break;
      }
    }
  }

  EndExclusive(SHORT_CODE);

  if (lost_user_detected) {
    /* Fire off a SD session to clear down the users. Although it would be
      nice to do the whole job here, there are so many dependencies that
      sdwind ends up carrying around most of SD.                          */
    // converted to snprintf() -gwb 25Feb20
    /* Modified by Composer AI - 2026/06/10.
       Single-quote the executable path so spaces or shell metacharacters
       in the (administrator controlled) system directory cannot break or
       inject into the command. Also do not execute the command at all if
       it would have been truncated, instead of running a mangled path. */
    /* if (snprintf(cmd, MAX_PATHNAME_LEN + 10, "%s/bin/sd -cleanup", sysseg->sysdir) >= (MAX_PATHNAME_LEN + 10)) {
        printf(
            "Overflowed path/filename buffer. Truncated to:\n%s/bin/sd "
            "-cleanup",
            sysseg->sysdir);
      }
    system(cmd); */
    /* 14 Aug 26 Windows port - this named "<sysdir>/bin/sd", the same wrong
       location start_sd() used for the daemon: <sysdir>/bin holds pcode and
       pcode.old, not executables (PROJECT_STATUS.md 5.8).  sd lives beside
       this daemon, so ask where that is.  A daemon has no useful stdout, so
       failures go to the error log rather than to printf.                 */
    if (!exe_directory(bindir, sizeof(bindir))) {
        log_message("Cleanup not run: cannot locate the SD program directory");
      } else if (snprintf(cmd, sizeof(cmd), "'%s/sd' -cleanup", bindir) >= (int)sizeof(cmd)) {
        log_message("Cleanup not run: overflowed path/filename buffer");
      } else {
        system(cmd);
      }
    /* -------------------- */
  }
}

/* ======================================================================
   Signal handler                                                         */

void signal_handler(signum) int signum;
{
  switch (signum) {
    case SIGTERM:
      signal(SIGTERM, SIG_IGN);
      terminate = TRUE;
      break;
  }
}

/* ======================================================================
   log_message()  -  Add message to error log                             */

void log_message(char* msg) {
  int errlog;
  time_t timenow;
  struct tm* ltime;
  int bytes;
#define BUFF_SIZE 4096
  char buff[BUFF_SIZE];
  static char* month_names[12] = {
      "January", "February", "March",     "April",   "May",      "June",
      "July",    "August",   "September", "October", "November", "December"};

  if (sysseg->errlog) {
    StartExclusive(ERRLOG_SEM, 71);

    sprintf(buff, "%s%cerrlog", sysseg->sysdir, DS);
    errlog = open(buff, O_RDWR | O_CREAT | O_BINARY, 0777);

    /* Modified by Composer AI - 2026/06/10.
       If the open() failed, "bytes" was used uninitialized and write()/
       close() were called with a negative file descriptor. Move the
       write and close inside the successful-open branch. */
    /* if (errlog >= 0) {
      lseek(errlog, 0, SEEK_END);

      timenow = time(NULL);
      ltime = localtime(&timenow);

      bytes = sprintf(buff, "%02d %.3s %02d %02d:%02d:%02d [sdlnxd]:%s   %s%s",
                      ltime->tm_mday, month_names[ltime->tm_mon],
                      ltime->tm_year % 100, ltime->tm_hour, ltime->tm_min,
                      ltime->tm_sec, Newline, msg, Newline);
    }

    write(errlog, buff, bytes);

    close(errlog); */
    if (errlog >= 0) {
      lseek(errlog, 0, SEEK_END);

      timenow = time(NULL);
      ltime = localtime(&timenow);

      bytes = sprintf(buff,
                      "%02d %.3s %02d %02d:%02d:%02d [" SDWIND_NAME "]:%s   %s%s",
                      ltime->tm_mday, month_names[ltime->tm_mon],
                      ltime->tm_year % 100, ltime->tm_hour, ltime->tm_min,
                      ltime->tm_sec, Newline, msg, Newline);

      write(errlog, buff, bytes);

      close(errlog);
    }
    /* -------------------- */

    EndExclusive(ERRLOG_SEM);
  }
}

/* END-CODE */
