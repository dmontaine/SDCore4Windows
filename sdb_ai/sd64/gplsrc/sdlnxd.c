/* SDLNXD.C
 * SD Linux daemon.
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
 * END-HISTORY
 *
 * START-DESCRIPTION:
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
#include <sys/ipc.h>
#include <sys/shm.h>
#include <signal.h>
#include <sched.h>

int shmid; /* Shared memory id */

bool terminate = FALSE;

void check_lost_users(void);

void signal_handler(int signum);

/* ====================================================================== */

int main() {
  char errmsg[80];
  int timer = 0;

  process.user_no = -2; /* Mark as sdlnxd for semaphore table */

  signal(SIGTERM, signal_handler);

  /* Attach the shared memory segment */

  if (((shmid = shmget(SD_SHM_KEY, 0, 0666)) == -1) ||
      (((sysseg = (SYSSEG*)shmat(shmid, NULL, 0))) == (void*)(-1))) {
    exit(1);
  }

  /* Get access to semaphores */

  if (!get_semaphores(FALSE, errmsg))
    exit(2);

  /* Set process id into shared memory */

  sysseg->sdlnxd_pid = getpid();

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

  shmdt((void*)sysseg); /* Dettach shared memory */

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
  char cmd[MAX_PATHNAME_LEN + 10];

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
      sdlnxd ends up carrying around most of SD.                          */
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
    if (snprintf(cmd, sizeof(cmd), "'%s/bin/sd' -cleanup", sysseg->sysdir) >= (int)sizeof(cmd)) {
        printf(
            "Overflowed path/filename buffer. Cleanup not run for:\n%s/bin/sd "
            "-cleanup",
            sysseg->sysdir);
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

      bytes = sprintf(buff, "%02d %.3s %02d %02d:%02d:%02d [sdlnxd]:%s   %s%s",
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
