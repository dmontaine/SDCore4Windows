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
 * 17 Aug 26 Windows port - the API listener.  Windows has neither xinetd nor
 *                      systemd socket activation, so the listener and the
 *                      per-connection spawn that the Linux build gets from
 *                      the operating system have to live somewhere; this is
 *                      the only process SD already keeps running.
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
/* 17 Aug 26 Windows port - for the API listener */
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>

bool terminate = FALSE;

/* 17 Aug 26 Windows port - the API listener, -1 when APIPORT is not set,
   which is the default and the shipped state. */
static int api_listener = -1;

void check_lost_users(void);
static int open_api_listener(int port);
static void accept_api_session(void);

void signal_handler(int signum);

/* ====================================================================== */

int main() {
  char errmsg[80];
  int timer = 0;
  int fd;
  struct stat statbuf;
  time_t next_tick;

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

  /* 17 Aug 26 Windows port - THE LOOP NOW WAITS ON A SOCKET RATHER THAN
     SLEEPING, and the minute timer is driven by the CLOCK instead of by the
     iteration count.  It has to be: select() returns as soon as a connection
     arrives, so counting iterations would run check_lost_users() once per
     API connection rather than once every five minutes.  With APIPORT unset
     there is no descriptor to watch and select() is just the old sleep.    */
  api_listener = open_api_listener((int)sysseg->api_port);

  next_tick = time(NULL) + 60;

  while (!terminate) {
    fd_set rd;
    struct timeval tv;
    long wait_secs;
    int nfds;

    wait_secs = (long)(next_tick - time(NULL));
    if (wait_secs < 0)
      wait_secs = 0;
    tv.tv_sec = wait_secs;
    tv.tv_usec = 0;

    FD_ZERO(&rd);
    nfds = 0;
    if (api_listener >= 0) {
      FD_SET(api_listener, &rd);
      nfds = api_listener + 1;
    }

    /* EINTR is expected here - SIGTERM arrives this way - and is handled by
       falling through to the while test rather than by retrying. */
    if (select(nfds, (nfds > 0) ? &rd : NULL, NULL, NULL, &tv) > 0) {
      if ((api_listener >= 0) && FD_ISSET(api_listener, &rd))
        accept_api_session();
    }

    /* REAPED HERE RATHER THAN IN A SIGCHLD HANDLER, deliberately.  SIG_IGN
       would auto-reap but then make system() in check_lost_users() fail with
       ECHILD, and a handler would have to be reasoned about against the
       SIGCHLD system() blocks around itself.  A zombie living until the next
       loop pass costs nothing.                                             */
    while (waitpid(-1, NULL, WNOHANG) > 0)
      ;

    if (time(NULL) >= next_tick) {
      next_tick += 60;
      timer++;

      /* One minute actions */

      if ((timer % 5) == 0) {
        /* Five minute actions */

        check_lost_users();
      }
    }
  }

  if (api_listener >= 0)
    close(api_listener);

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
   open_api_listener()  -  Bind the API port, if there is one

   17 Aug 26 Windows port.  Returns -1 for "no listener", which is not an
   error: APIPORT defaults to zero and a shipped system opens no port at all.
   Enabling it is an act by an administrator, because the port is reachable by
   every local process on the machine - what answers that is $CRED and the
   ACC$GROUP check inside APISRVR, not the transport.  section 7 step 6.      */

static int open_api_listener(int port) {
  int fd;
  int on = 1;
  struct sockaddr_in addr;
  char msg[128];

  if (port <= 0)
    return -1; /* APIPORT not set - the default, and not a failure */

  if ((fd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
    log_message("API listener not started: cannot create socket");
    return -1;
  }

  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (char*)&on, sizeof(on));

  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  /* LOOPBACK ONLY, AND NOT CONFIGURABLE.  Posture B (section 8): nothing of
     SD's own faces the network, ssh carries the traffic.  A bind address in
     the configuration file would be a way to get that wrong by accident.   */
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  addr.sin_port = htons((u_int16_t)port);

  if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
    snprintf(msg, sizeof(msg),
             "API listener not started: cannot bind 127.0.0.1 port %d", port);
    log_message(msg);
    close(fd);
    return -1;
  }

  if (listen(fd, 5) < 0) {
    snprintf(msg, sizeof(msg),
             "API listener not started: cannot listen on port %d", port);
    log_message(msg);
    close(fd);
    return -1;
  }

  snprintf(msg, sizeof(msg), "API listener on 127.0.0.1 port %d", port);
  log_message(msg);
  return fd;
}

/* ======================================================================
   accept_api_session()  -  One connection, one sd process

   17 Aug 26 Windows port.  This is the half of xinetd that Windows does not
   provide: accept, then fork and exec "sd -n -q" with the socket as
   descriptors 0 and 1, which is exactly the contract etc/xinetd.d/qmclient
   describes and what start_connection() reads.

   The socket is handed over by INHERITING IT ACROSS fork(), which is why this
   lives in an MSYS2 program rather than in the native service.  A native
   listener passing the accepted socket to a Cygwin child was measured on
   17 Aug 2026 and does not work: the descriptor arrives valid enough for
   getsockname() and send() and cannot be read at all, because a Windows
   socket's receive path stays bound to the process that created it.  Both
   halves of this fork are Cygwin, so none of that applies.                  */

static void accept_api_session(void) {
  int conn;
  pid_t pid;
  char bindir[MAX_PATHNAME_LEN + 1];
  char sdpath[MAX_PATHNAME_LEN + 20];

  if ((conn = accept(api_listener, NULL, NULL)) < 0)
    return; /* EINTR, or a client that gave up between select and accept */

  /* sd lives beside this daemon, not under <sysdir>/bin, which holds pcode -
     the same correction check_lost_users() carries. */
  if (!exe_directory(bindir, sizeof(bindir))) {
    log_message("API connection refused: cannot locate the SD program directory");
    close(conn);
    return;
  }

  if (snprintf(sdpath, sizeof(sdpath), "%s/sd", bindir) >= (int)sizeof(sdpath)) {
    log_message("API connection refused: overflowed path/filename buffer");
    close(conn);
    return;
  }

  if ((pid = fork()) < 0) {
    log_message("API connection refused: fork failed");
    close(conn);
    return;
  }

  if (pid == 0) {
    /* Child.  The listening socket must not survive into the session, or a
       dead sdwind would leave the port held open by whatever is still
       running. */
    close(api_listener);
    if ((dup2(conn, 0) < 0) || (dup2(conn, 1) < 0))
      _exit(126);
    if (conn > 1)
      close(conn);
    execl(sdpath, "sd", "-n", "-q", (char*)NULL);
    _exit(127); /* Only reached if exec failed */
  }

  /* Parent.  Close our copy, or the client never sees the session end. */
  close(conn);
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
