/* WIN32SDSYSASK.H
 * "ssh -t <user>@localhost sd-sdsys": the asker in sd.exe and the SD service's door, and the wire between them (RELEASE_1.1 339).
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
 * 18 Nov 26 Windows port - written for RELEASE_1.1 339 (Linux S.267, 38cfb301; no-terminal 044271af).  .claude/localsdsys/DESIGN.md
 *           section 4 is the design.  NOT RUN: compiled and linked only; the VM witness (W0 first) is what measures it.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * NO WINDOWS TYPE IN THIS INTERFACE (win32peer.h has why): sd.c and sd_sdsysask.c (the MSYS2 build, POSIX headers) include it, and so
 * does the SD service (sdsvc/sdsyslocal.c, native).  The pipe calls are in win32sdsysask.c; the terminal is in sd_sdsysask.c.
 *
 * WHO DOES WHAT.  Every Windows ssh login is sd.exe as the user (SD's ForceCommand).  sdsys_local_detect(), first in main() after
 * xfer_detect(), acts only when there is no argument, SSH_CONNECTION is set and SSH_ORIGINAL_COMMAND is exactly SDL_COMMAND
 * ("sd-sdsys").  The variables are NOT evidence - anybody may set them - they only choose this path; the SD service (LocalSystem)
 * decides from the operating system (win32localsdsys.c sdl_ssh_evidence) and starts nothing unless every question passes.  Without
 * a terminal the asker prints one line and exits 1 (Linux 044271af, reason word no-terminal).  The asker never binds SD's shared
 * memory and never runs LOGIN as the user.
 *
 * THE WIRE (SDL_PIPE, byte mode; the pipe's owner must be LocalSystem, checked by the asker before it sends anything):
 *
 *   asker -> service   one line:  "SDSYSLOCAL1 <cols> <rows> <term>\n"
 *                        cols SDASK_MIN_COLS..SDASK_MAX_SIZE, rows SDASK_MIN_ROWS..SDASK_MAX_SIZE, decimal digits only, no sign,
 *                        no leading space; term 1 to SDASK_TERM_MAX of a-z 0-9 . _ - +.  Single spaces.  Nothing else on the line
 *                        and nothing sent after it before the answer.
 *   service -> asker   one line:  "STARTED <pid>\n"   (the SDSYS sd.exe's pid), then the pseudo console's output, raw
 *                        or         "REFUSED <word>\n"  (the reason word; the pipe is then closed)
 *   asker -> service   after STARTED, frames only:
 *                        'K' <len high> <len low> <len bytes>      keys, len 1..SDASK_KEYS_MAX
 *                        'R' <cols high> <cols low> <rows high> <rows low>   a new window size, in the same bounds as the line
 *                      any other byte where a frame starts, or a size out of bounds, ends the session.
 *
 * The session ends when the SDSYS process exits (the service closes the pseudo console and then the pipe) or when the asker closes
 * the pipe (the service terminates the job).
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32SDSYSASK_H
#define WIN32SDSYSASK_H

#define SDASK_MAGIC "SDSYSLOCAL1 "
#define SDASK_LINE_MAX 128
#define SDASK_ANSWER_MAX 128
#define SDASK_TERM_MAX 32
#define SDASK_MIN_COLS 20  /* LOGIN's MIN.WIDTH and MIN.DEPTH */
#define SDASK_MIN_ROWS 10
#define SDASK_MAX_SIZE 999
#define SDASK_KEYS_MAX 4096
#define SDASK_FRAME_KEYS 'K'
#define SDASK_FRAME_SIZE 'R'
#define SDASK_STARTED "STARTED "
#define SDASK_REFUSED "REFUSED "
#define SDASK_DEFAULT_TERM "xterm" /* sent when TERM is absent or not a plain name */

/* A terminal type as the wire takes it: 1 to SDASK_TERM_MAX of a-z 0-9 . _ - +. */
static inline int sdask_term_ok(const char* w) {
  int n;
  char c;

  if ((w == 0) || (*w == '\0'))
    return 0;
  for (n = 0; w[n] != '\0'; n++) {
    if (n >= SDASK_TERM_MAX)
      return 0;
    c = w[n];
    if (!(((c >= 'a') && (c <= 'z')) || ((c >= '0') && (c <= '9')) || (c == '.') || (c == '_') || (c == '-') || (c == '+')))
      return 0;
  }
  return 1;
}

/* A size clamped into the wire's bounds (the asker's side: LOGIN would take the least anyway). */
static inline int sdask_clamp(int v, int lo) {
  if (v < lo)
    return lo;
  if (v > SDASK_MAX_SIZE)
    return SDASK_MAX_SIZE;
  return v;
}

/* ---------------------------------------------------------------------- sd.exe: the asker */

/* sd_sdsysask.c.  Returns at once, changing nothing, unless argc is 1, SSH_CONNECTION is set and SSH_ORIGINAL_COMMAND is exactly
   "sd-sdsys"; then it never returns: it relays the SDSYS session (exit 0), or prints why not (exit 1). */
void sdsys_local_detect(int argc);

/* win32sdsysask.c, the pipe.  One session per process.
   sdask_open: connect to SDL_PIPE (identification level only), refuse a pipe whose owner is not LocalSystem, send REQUEST (one line
   ending "\n"), read the answer line.  0 on STARTED (answer holds the pid), 1 on REFUSED (answer holds the word), -1 otherwise
   (answer holds what went wrong).
   sdask_read: what the session wrote, without waiting: n > 0 bytes, 0 nothing yet, -1 the session is over.
   sdask_keys / sdask_resize: send a frame; 0 sent, -1 the session is over.
   sdask_close: end the session (the service terminates the SDSYS process's job when the pipe closes). */
int sdask_open(const char* request, char* answer, int alen);
int sdask_read(char* buf, int len);
int sdask_keys(const char* buf, int len);
int sdask_resize(int cols, int rows);
void sdask_close(void);

#endif

/* END-CODE */
