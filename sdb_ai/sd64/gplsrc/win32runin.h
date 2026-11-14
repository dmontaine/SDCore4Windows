/* WIN32RUNIN.H
 * RUN.IN ... DEBUG on Windows: what the SDSYS session, the debugged child and the SD service agree on.
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
 * 13 Nov 26 Windows port - written.  RELEASE_1.1 253(b): run.in WITH debug, the Windows form of Linux's sixth run.in
 *           command (Linux cproc int.runin, case ri.cmd = 'debug').  .claude/design-runin-debug-20261113.md.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY THERE IS A SECOND PROCESS.  On Linux, "run.in account debug file program" runs the program inside the administrator's
 * session with SD's administrator flag off, as the operating-system user sdsys, which is not root.  An SDSYS session here is
 * a process started ELEVATED, and its token stays elevated for the life of the process (op_kernel.c K_OS_ELEVATED): Windows
 * cannot drop that token and give it back, so the account's code would run with a Windows administrator's reach.  So the
 * program runs in ANOTHER sd.exe, which never held elevation:
 *
 *   the SDSYS session          asks the SD service (pipe SD_RUNIN_PIPE) for a run, then shows the debugger (gpl.bp/debug, in
 *                              its cross-process form, the one PDEBUG uses for a phantom) and relays the program's screen
 *                              and keyboard to and from its own terminal (K$RUNIN.DEBUG, win32runin.c)
 *   the SD service (LocalSystem, gplsrc/sdsvc/sdrunin.c)
 *                              checks that the asker is an ELEVATED administrator, logs the bare account SD_RUNIN_ACCOUNT on
 *                              by S4U with two groups added - sdusers (SD's shared segment and data tree) and the account's own
 *                              sdu_<account> - removes every privilege, keeps Medium integrity, makes a store only that logon
 *                              and administrators can open, and starts the child in a job of one process
 *   the child (sd.exe -RUNIN)  checks its own token before anything else (win32_runin_child_verify), enters the account with
 *                              no administrator flag, no shell, no OS.EXECUTE and no edit gate, and runs DEBUG file program;
 *                              each stop is a message in the store ($pdbg), its screen and keyboard are its standard handles
 *
 * NO WINDOWS TYPE IN THIS INTERFACE: op_kernel.c and sd.c include it beside sd.h, and the service includes it natively.  The
 * word check below is the one copy both sides (and gplbld/test-runindebug-units.py) use.
 *
 * THE WIRE (SD_RUNIN_PIPE, byte mode).  The SDSYS session writes one line:
 *
 *   SDRUNIN1 <account>\t<file>\t<program>\t<term>\t<cols>\t<rows>\n
 *
 * and the service answers one line, "OK <pid>\t<store>\n" or "ER <reason>\n".  After OK the pipe carries the child's screen
 * (service to session) and the keyboard (session to service) as raw bytes until either side ends: the child's end closes the
 * pipe; the session's close ends the run (the job is terminated).  Nothing on the wire is a path the service believes: the
 * account is looked up in the register by the service, the store is the service's, and the words are checked on both sides.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32RUNIN_H
#define WIN32RUNIN_H

/* Fixed at compile time and not an environment variable, for the reason win32auditpipe.h gives for SD_AUDIT_PIPE. */
#define SD_RUNIN_PIPE "\\\\.\\pipe\\sd-runin"

/* The bare local account the child runs as.  install-service.ps1 makes it (no group, no password anyone knows, every
   interactive kind of logon denied) and removes it with the service. */
#define SD_RUNIN_ACCOUNT "sdrunin"

#define RUNIN_MAGIC "SDRUNIN1 "
#define RUNIN_LINE_MAX 512     /* the request, and the answer */
#define RUNIN_WORD_MAX 64      /* cproc ri.plain.word's limit */
#define RUNIN_TERM_MAX 32
#define RUNIN_MIN_COLS 20      /* LOGIN's MIN.WIDTH and MIN.DEPTH */
#define RUNIN_MIN_ROWS 10
#define RUNIN_MAX_SIZE 999
#define RUNIN_USERS_GROUP "sdusers"
#define RUNIN_GROUP_PREFIX "sdu_"  /* create_account: ACC$GROUP is "sdu_" : the account name for a USER account */
#define RUNIN_GROUP_PREFIX_GROUP "sdg_"  /* ... and "sdg_" : the account name for a GROUP account (RELEASE_1.1 287) */

/* The child's store, given to it in its environment (taken out at start-up, as SD_PHANTOM_NONCE is). */
#define RUNIN_STORE_ENV "SD_RUNIN_STORE"

/* ri.plain.word (cproc), in C: 1 to max characters of a-z 0-9 . _ -, the first a letter or a digit.  Lower case only: the
   SDSYS session lower-cases the sentence before it checks it, so an upper-case letter here is a word that did not come
   from there. */
static inline int runin_plain_word(const char* w, int max) {
  int n;
  char c;

  if ((w == 0) || (*w == '\0'))
    return 0;
  if (!(((*w >= 'a') && (*w <= 'z')) || ((*w >= '0') && (*w <= '9'))))
    return 0;
  for (n = 0; w[n] != '\0'; n++) {
    if (n >= max)
      return 0;
    c = w[n];
    if (!(((c >= 'a') && (c <= 'z')) || ((c >= '0') && (c <= '9')) || (c == '.') || (c == '_') || (c == '-')))
      return 0;
  }
  return 1;
}

/* A terminal type name: as a plain word, and '+' allowed (xterm+256color style names). */
static inline int runin_term_word(const char* w) {
  int n;
  char c;

  if ((w == 0) || (*w == '\0'))
    return 0;
  for (n = 0; w[n] != '\0'; n++) {
    if (n >= RUNIN_TERM_MAX)
      return 0;
    c = w[n];
    if (!(((c >= 'a') && (c <= 'z')) || ((c >= '0') && (c <= '9')) || (c == '.') || (c == '_') || (c == '-') ||
          (c == '+')))
      return 0;
  }
  return 1;
}

/* A screen size: digits only, from lo to RUNIN_MAX_SIZE.  0 when it is not one. */
static inline int runin_size(const char* w, int lo) {
  int v = 0;
  int n;

  if ((w == 0) || (*w == '\0'))
    return 0;
  for (n = 0; w[n] != '\0'; n++) {
    if ((n >= 3) || (w[n] < '0') || (w[n] > '9'))
      return 0;
    v = (v * 10) + (w[n] - '0');
  }
  return ((v >= lo) && (v <= RUNIN_MAX_SIZE)) ? v : 0;
}

/* ---------------------------------------------------------------------- sd.exe's half (win32runin.c) */

/* THE CHILD'S DOOR.  1 only when this process's token is the one the service makes: its user is the local account
   SD_RUNIN_ACCOUNT, it is not elevated, it holds no privilege at all, its integrity is Medium or lower, and no
   Administrators group in it is enabled.  groups gets the names of the token's enabled LOCAL groups, comma separated
   (a comma cannot be in a Windows group name), for LOGIN to find the account's own group in.  0 with why set
   otherwise.  An ordinary user typing "sd -RUNIN account" is refused here: nobody but the SD service (SeTcb) can make a
   process with that account's token. */
int win32_runin_child_verify(char* groups, int glen, char* why, int whylen);

/* THE SDSYS SESSION'S END OF A RUN.  One run per process.
   win32_runin_open: connect to SD_RUNIN_PIPE, refuse a pipe whose owner is not LocalSystem (anybody may make the name
   while the service is down), send the request line, read the answer line.  0 when the answer is OK (answer holds what
   follows "OK "), -1 otherwise (answer holds the reason).
   win32_runin_read: what the child has written, without waiting: n > 0 bytes, 0 nothing yet, -1 the run is over.
   win32_runin_write: the keyboard to the child; 0 written, -1 the run is over.
   win32_runin_close: end the run (the service terminates the child's job when the pipe closes). */
int win32_runin_open(const char* request, char* answer, int alen);
/* win32_runin_open() is this with SD_RUNIN_PIPE and the owner required to be LocalSystem; gplbld/test-runindebug-units.py
   passes a pipe of its own and 0. */
int win32_runin_open_to(const char* pipe_name, int need_system_owner, const char* request, char* answer, int alen);
int win32_runin_read(char* buf, int len);
int win32_runin_write(const char* buf, int len);
void win32_runin_close(void);
int win32_runin_is_open(void);

#endif

/* END-CODE */
