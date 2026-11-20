/* SD_SDSYSASK.C
 * "ssh -t <user>@localhost sd-sdsys", sd.exe's half: the asker's terminal (RELEASE_1.1 339).
 * Copyright (c) String Database
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
 * START-HISTORY:
 * 19 Nov 26 Windows port - RELEASE_1.1 358 (VM sit7: after an admitted session ended, ssh did not return in 5 of 6 until Ctrl+C): the
 *           key read is non-blocking (O_NONBLOCK on fd 0 for the relay, the old flags put back on every way out).  select() on the
 *           MSYS2 console may say "readable" for an input event that is no key (a key release, focus, a size change); a blocking read
 *           then waited for a real key, and the end of the SDSYS session, seen only at the top of the loop, waited with it.  EAGAIN is
 *           now "no key yet" and the loop goes back to the pipe.
 * 18 Nov 26 Windows port - written for RELEASE_1.1 339 (Linux S.267; no-terminal Linux 044271af).  win32sdsysask.h has the design and
 *           the wire.  NOT RUN: compiled and linked only.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * POSIX headers and NO windows.h (win32peer.h has why the two are kept apart); the pipe is win32sdsysask.c's, reached through the
 * plain interface in win32sdsysask.h.  No SD header either: this runs before SD is anything in this process - no shared memory is
 * bound, no configuration read, LOGIN never runs as the user.
 *
 * The terminal is put in raw mode, so every key (Ctrl-C included) goes to the SDSYS session as a byte, and taken back out of it on
 * every way out of the relay.  The window size is asked every SDASK_SIZE_MS as well as at SIGWINCH: under the MSYS2 console the
 * signal arrives only with the next input event (linuxio.c, RELEASE_1.1 212).
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "win32localsdsys.h"
#include "win32sdsysask.h"

#define SDASK_IO 4096
#define SDASK_POLL_MS 20    /* how long the relay waits for a key before it asks the pipe again */
#define SDASK_SIZE_MS 250   /* how often the window size is asked */

static volatile sig_atomic_t sdask_winch = 0;

static void sdask_winch_handler(int sig) {
  (void)sig;
  sdask_winch = 1;
}

static long long sdask_now_ms(void) {
  struct timespec ts;

  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ((long long)ts.tv_sec * 1000) + (ts.tv_nsec / 1000000);
}

static int sdask_window(int* cols, int* rows) {
  struct winsize ws;

  if ((ioctl(0, TIOCGWINSZ, &ws) != 0) || (ws.ws_col == 0) || (ws.ws_row == 0))
    return 0;
  *cols = sdask_clamp(ws.ws_col, SDASK_MIN_COLS);
  *rows = sdask_clamp(ws.ws_row, SDASK_MIN_ROWS);
  return 1;
}

static int sdask_out(const char* buf, int len) {
  ssize_t n;

  while (len > 0) {
    n = write(1, buf, (size_t)len);
    if (n < 0) {
      if (errno == EINTR)
        continue;
      if (errno == EAGAIN) { /* 19 Nov 26 (358): fd 1 may share fd 0's O_NONBLOCK; a full terminal waits, it does not end the relay */
        struct timespec ms = {0, 2000000};
        nanosleep(&ms, NULL);
        continue;
      }
      return -1;
    }
    buf += n;
    len -= (int)n;
  }
  return 0;
}

/* ======================================================================
   sdsys_local_detect()  -  Is this ssh login "ssh -t <user>@localhost sd-sdsys"?  Called in main() right after xfer_detect().

   Three things together and nothing else: no argument (the ForceCommand is sd alone), SSH_CONNECTION set, and SSH_ORIGINAL_COMMAND
   exactly "sd-sdsys" - not a prefix, no arguments.  Anything else returns and sd.exe goes on as the person's ordinary session.  These
   variables decide nothing: the SD service asks the operating system about this process before it starts anything.          */

void sdsys_local_detect(int argc) {
  const char* cmd = getenv("SSH_ORIGINAL_COMMAND");
  const char* conn = getenv("SSH_CONNECTION");
  const char* term = getenv("TERM");
  char request[SDASK_LINE_MAX];
  char answer[SDASK_ANSWER_MAX];
  char buf[SDASK_IO];
  struct termios old_tty;
  struct termios raw_tty;
  struct timeval tv;
  fd_set rd;
  long long next_size;
  int have_old;
  int cols = 80;
  int rows = 24;
  int ncols;
  int nrows;
  int rc;
  int n;
  int got;
  int old_fl;

  if ((argc != 1) || (cmd == NULL) || (conn == NULL) || (strcmp(cmd, SDL_COMMAND) != 0))
    return;

  /* No terminal (ssh without -t, input from a pipe): one line, and no session.  Linux 044271af refuses the same with no-terminal. */
  if (!isatty(0)) {
    fprintf(stderr, "sd-sdsys needs a terminal: ssh -t <user>@localhost sd-sdsys\n");
    exit(1);
  }

  (void)sdask_window(&cols, &rows);
  if (!sdask_term_ok(term))
    term = SDASK_DEFAULT_TERM;
  if (snprintf(request, sizeof(request), "%s%d %d %s\n", SDASK_MAGIC, cols, rows, term) >= (int)sizeof(request)) {
    fprintf(stderr, "sd-sdsys: the request could not be made\n");
    exit(1);
  }

  rc = sdask_open(request, answer, (int)sizeof(answer));
  if (rc == 1) {
    fprintf(stderr, "sd-sdsys refused: %s\n", answer);
    exit(1);
  }
  if (rc != 0) {
    fprintf(stderr, "sd-sdsys: %s\n", answer);
    exit(1);
  }

  have_old = (tcgetattr(0, &old_tty) == 0);
  if (have_old) {
    raw_tty = old_tty;
    cfmakeraw(&raw_tty);
    (void)tcsetattr(0, TCSANOW, &raw_tty);
  }
  /* 19 Nov 26 - RELEASE_1.1 358: a read that cannot wait (see the history). */
  old_fl = fcntl(0, F_GETFL);
  if (old_fl != -1)
    (void)fcntl(0, F_SETFL, old_fl | O_NONBLOCK);
  signal(SIGWINCH, sdask_winch_handler);
  signal(SIGPIPE, SIG_IGN);
  next_size = sdask_now_ms() + SDASK_SIZE_MS;

  for (;;) {
    /* The session's screen, all that is there. */
    got = 0;
    while ((n = sdask_read(buf, (int)sizeof(buf))) > 0) {
      got = 1;
      if (sdask_out(buf, n) != 0)
        goto done;
    }
    if (n < 0)
      goto done; /* the SDSYS session has ended */

    /* The keys. */
    FD_ZERO(&rd);
    FD_SET(0, &rd);
    tv.tv_sec = 0;
    tv.tv_usec = got ? 0 : (SDASK_POLL_MS * 1000);
    rc = select(1, &rd, NULL, NULL, &tv);
    if ((rc < 0) && (errno != EINTR))
      goto done;
    if ((rc > 0) && FD_ISSET(0, &rd)) {
      n = (int)read(0, buf, sizeof(buf));
      if ((n < 0) && ((errno == EINTR) || (errno == EAGAIN)))
        continue; /* EAGAIN: the console's event was no key (RELEASE_1.1 358) - back to the pipe */
      if (n <= 0)
        goto done; /* the ssh login's input has ended */
      if (sdask_keys(buf, n) != 0)
        goto done;
    }

    /* The window size, when it changed. */
    if (sdask_winch || (sdask_now_ms() >= next_size)) {
      sdask_winch = 0;
      next_size = sdask_now_ms() + SDASK_SIZE_MS;
      if (sdask_window(&ncols, &nrows) && ((ncols != cols) || (nrows != rows))) {
        cols = ncols;
        rows = nrows;
        if (sdask_resize(cols, rows) != 0)
          goto done;
      }
    }
  }

done:
  sdask_close();
  if (old_fl != -1)
    (void)fcntl(0, F_SETFL, old_fl);
  if (have_old)
    (void)tcsetattr(0, TCSANOW, &old_tty);
  exit(0);
}

/* END-CODE */
