/* LINUXLB.H
 * Windows library substitutes for Linux.
 * Copyright (c) 2002 Ladybridge Systems, All Rights Reserved
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
 * 05 Sep 26 Windows port - IsInteractive() added.  PRE_RELEASE_FIXES.md 167.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef __LINUXLB
#define __LINUXLB

/* Inline macros */

#define max(a, b) (((a) > (b)) ? (a) : (b))
#define min(a, b) (((a) < (b)) ? (a) : (b))

/* Simple substitutes */

#define chsize(fd, bytes) ftruncate(fd, bytes)
#define GetCurrentProcessId() getpid()
#define stricmp(a, b) strcasecmp(a, b)

#define chsize64 chsize

/* The privilege predicates, and why they answer in two parts.
 *
 * 03 Sep 26 Windows port - PRE_RELEASE_FIXES.md 96.  THEY ANSWERED "NO" AND
 * "I COULD NOT TELL" WITH THE SAME FALSE, AND EVERY CALLER READ IT AS "NO".
 * IsAdmin(), IsElevated() and os_permitted() (op_sh.c) each have several FALSE
 * exits of which only one is the answer to the question asked; the rest are
 * the check failing to complete.
 *
 * THE REFUSAL IS RIGHT EITHER WAY, AND THAT IS NOT WHAT WAS FILED.  Failing
 * closed is the correct direction, no false grant was possible, and none is
 * introduced here.  What was filed is that the refusal then STATED A REASON
 * NOBODY ESTABLISHED: sd.c told an already-elevated administrator to elevate,
 * and CPROC:2699 wrote "reason=not an administrator" into the trail an
 * investigation reads, when the tier register may say otherwise.
 *
 * THE RETURN STAYS bool ON PURPOSE.  An enum return with three values would
 * leave "if (IsElevated())" compiling and answering TRUE for the undetermined
 * case - a false GRANT, and the one direction this must never take.  The bool
 * is still fail-closed; the out-parameter carries what the bool cannot.  A
 * NULL why is allowed and means "not going to look".
 *
 * THE REACHABLE TRIGGER IS NOT malloc().  On Cygwin getpwuid() and
 * getgrouplist() resolve through Windows name lookup, so a domain account with
 * the controller unreachable reaches all three of IsAdmin()'s failure exits at
 * once - the administrator is locked out and told they are not one.
 */

typedef enum {
  PRIV_ANSWERED = 0,   /* the check completed - the returned bool IS the answer */
  PRIV_NO_PASSWD,      /* getpwuid() could not name the account */
  PRIV_NO_GROUP_COUNT, /* the group list would not size */
  PRIV_NO_MEMORY,      /* malloc() failed */
  PRIV_NO_GROUP_LIST,  /* it sized, and then would not fetch */
  PRIV_NO_USERNAME,    /* the session has no user name to look up */
  PRIV_PATH_TOO_LONG,  /* the os.users pathname did not fit */
  PRIV_OPEN_FAILED,    /* os.users record would not open, and NOT because absent */
  PRIV_READ_FAILED,    /* os.users record would not read */
  PRIV_MALFORMED       /* os.users record has no second field */
} PRIV_WHY;

/* Functions in linuxlb.c */

bool IsAdmin(PRIV_WHY* why);
bool IsElevated(PRIV_WHY* why);
bool IsInteractive(PRIV_WHY* why);
char* priv_why_text(PRIV_WHY why);
void priv_log_undetermined(char* what, PRIV_WHY why);
int64 filelength64(int fd);
#define filelength(f) (int)filelength64(f)
bool GetUserName(char* name, u_int32_t* bytes);
char* itoa(int value, char* string, int radix);
char* Ltoa(int32_t value, char* string, int radix);
char* sdrealpath(char* inpath, char* outpath);
void Sleep(int32_t n);
void strrep(char* s, char old, char new);

#endif

/* END-CODE */
