/* LINUXLB.C
 * Windows library substitutes for Linux
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
 * 14 Aug 26 Windows port - IsElevated() added beside IsAdmin()
 * 05 Sep 26 Windows port - IsInteractive() added beside both.  How the session
 *           arrived, where the other two ask who and what.  PRE_RELEASE 167.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"

#include <pwd.h>
#include <grp.h>
#include <stdlib.h>
#include <time.h>

#ifndef __APPLE__
#include <crypt.h>
#endif

/* ======================================================================
   filelength64()  -  Return file size in bytes                           */

int64 filelength64(fd) int fd;
{
  struct stat statbuf;

  fstat(fd, &statbuf);
  return statbuf.st_size;
}

/* ======================================================================
   IsAdmin()  -  Is this user an administrator at the o/s level?

   13 Aug 26 Windows port - this used to be getuid() == 0.  Windows has no uid
   zero; the account database is derived from security identifiers and even an
   elevated process keeps its own uid, so that test could never be true and
   every privilege check in the BASIC layer answered "no" permanently.

   14 Aug 26 Windows port - A WINDOWS ADMINISTRATOR IS AN SD ADMINISTRATOR.
   Decision from the repository owner; see PROJECT_STATUS.md 5.6.1.  This used
   to test membership of a private "sdadmins" group, which separated SD
   administration from Windows administration.  That group is gone: the
   installer never created it, so a machine that had never had SD development
   on it got an install where nobody was an administrator and sd -start
   refused - and meanwhile the BASIC layer was already treating an OS
   administrator as an SD one, so the written decision and the behaviour had
   drifted apart.

   TWO THINGS HERE ARE DELIBERATE AND NEITHER IS OBVIOUS.

   getgrouplist(), not getgroups().  getgroups() reports the PROCESS TOKEN, and
   a UAC-filtered token carries Administrators as "deny only", which Cygwin
   omits - so an administrator who had not elevated would not have counted, and
   the test would really have meant "is elevated".  getgrouplist() asks what
   groups the ACCOUNT is in, which is the question being asked.  Measured
   14 Aug 2026 from an unelevated administrator session: getgroups() no,
   getgrouplist() yes.

   The gid 544, not the name.  Cygwin maps built-in SIDs to their RID, so
   BUILTIN\Administrators (S-1-5-32-544) is always gid 544, exactly as Users is
   545.  THE NAME IS RENAMED ON A LOCALISED WINDOWS and the number is not, so
   looking it up by name would fail on a German or French machine.  sd.iss had
   to learn the same thing for icacls, where it writes *S-1-5-32-544.        */

bool IsAdmin(PRIV_WHY* why) {
  struct passwd* pw;
  gid_t* list;
  int count;
  int i;
  bool status = FALSE;

  /* 03 Sep 26 Windows port - PRE_RELEASE_FIXES.md 96.  Set once here and
     overwritten by whichever exit could not finish, so the DEFAULT is "this
     answer was established" and a new failure path added below without a line
     here is the only way to get it wrong.  sd.h has the reasoning.         */

  if (why != NULL)
    *why = PRIV_ANSWERED;

  pw = getpwuid(getuid());
  if (pw == NULL) {
    if (why != NULL)
      *why = PRIV_NO_PASSWD;
    return FALSE; /* No account to ask about - fail closed */
  }

  /* getgrouplist() wants the size in/out.  Ask twice: once to be told how many
     there are, once to fetch them.  It returns -1 on the sizing call, which is
     expected and is not an error.                                           */

  count = 0;
  getgrouplist(pw->pw_name, pw->pw_gid, NULL, &count);
  if (count <= 0) {
    if (why != NULL)
      *why = PRIV_NO_GROUP_COUNT;
    return FALSE;
  }

  list = (gid_t*)malloc(count * sizeof(gid_t));
  if (list == NULL) {
    if (why != NULL)
      *why = PRIV_NO_MEMORY;
    return FALSE;
  }

  if (getgrouplist(pw->pw_name, pw->pw_gid, list, &count) >= 0) {
    for (i = 0; i < count; i++) {
      if (list[i] == SD_ADMIN_GID) {
        status = TRUE;
        break;
      }
    }
  } else {
    /* 03 Sep 26 Windows port - THE SIZING CALL SUCCEEDED AND THE FETCH DID
       NOT, so the loop never ran and the initialised FALSE below would have
       left as an answer.  PRE_RELEASE 96 named this as one of the two paths
       its own list was short by; it is unreachable only if getgrouplist()
       cannot fail twice differently, which is not promised.                */
    if (why != NULL)
      *why = PRIV_NO_GROUP_LIST;
  }

  free(list);

  return status;
}

/* ======================================================================
   IsElevated()  -  May this process act as an administrator right now?

   14 Aug 26 Windows port - the companion to IsAdmin() above, and the distance
   between the two of them is the whole of the access model in
   PROJECT_STATUS.md section 5.6.  IsAdmin() asks whether the ACCOUNT is an
   administrator; this asks whether THIS PROCESS may act as one.  Linux draws
   the same line between being named in the sudoers file and having actually
   run sudo, and SD needs both halves for the same reasons Linux does.

   THE TEST IS getgroups() AGAINST THE SAME GID, AND IT IS THE DELIBERATE
   OPPOSITE OF IsAdmin()'s getgrouplist().  getgroups() reports the process
   token.  UAC hands an unelevated administrator a filtered token that carries
   BUILTIN\Administrators marked "Group used for deny only" - it is there so it
   can be denied against, never granted - and Cygwin omits a deny-only group
   from getgroups().  So its absence is precisely the elevation question, and
   the two calls were measured against each other in one unelevated
   administrator session on 14 Aug 2026: getgroups() no, getgrouplist() yes.

   That measurement is why no Win32 call appears here.
   GetTokenInformation(TokenElevation) answers the same question and would drag
   windows.h into a file built against the MSYS2 POSIX runtime, which is the
   toolchain split PROJECT_STATUS.md section 5.4 exists to keep clean.        */

bool IsElevated(PRIV_WHY* why) {
  gid_t* list;
  int count;
  int i;
  bool status = FALSE;

  if (why != NULL)
    *why = PRIV_ANSWERED;

  /* getgroups() sizes the same way getgrouplist() does, but by returning the
     count rather than writing it back through the argument.                 */

  count = getgroups(0, NULL);
  if (count <= 0) {
    if (why != NULL)
      *why = PRIV_NO_GROUP_COUNT;
    return FALSE; /* No groups in the token - fail closed */
  }

  list = (gid_t*)malloc(count * sizeof(gid_t));
  if (list == NULL) {
    if (why != NULL)
      *why = PRIV_NO_MEMORY;
    return FALSE;
  }

  if (getgroups(count, list) >= 0) {
    for (i = 0; i < count; i++) {
      if (list[i] == SD_ADMIN_GID) {
        status = TRUE;
        break;
      }
    }
  } else {
    /* 03 Sep 26 Windows port - the second of the two paths PRE_RELEASE 96's
       list was short by.  Same shape as IsAdmin() above: sized, then would
       not fetch, so the loop never ran.                                    */
    if (why != NULL)
      *why = PRIV_NO_GROUP_LIST;
  }

  free(list);

  return status;
}

/* ======================================================================
   IsInteractive()  -  Does this session have a desktop UAC could render on?

   05 Sep 26 Windows port - PRE_RELEASE_FIXES.md 167, the owner's ruling of
   5 Sep 2026: administration requires a session where UAC can RENDER, because
   that is what makes an elevation consented to by a person rather than merely
   granted.  PROJECT_STATUS.md 5.25.

   THE THIRD OF THE THREE, AND IT ASKS A DIFFERENT KIND OF QUESTION.  IsAdmin()
   asks WHO the account is, IsElevated() asks WHAT this process may do, and
   this asks HOW the session arrived.  All three are answered from the token;
   only this one is about the route.

   S-1-5-4 IS THE SIGNAL AND IT IS ALREADY IN THE LIST getgroups() RETURNS.
   Windows puts a logon SID in every token saying how the session was
   established, Cygwin maps a well-known SID to its RID, so INTERACTIVE arrives
   as gid 4 beside the 544 IsElevated() is already looking for.  Measured
   5 Sep 2026 from an MSYS2 shell: "id -Gn" printed INTERACTIVE CONSOLE LOGON
   and "id -G" carried 4.  NO Win32 CALL AND NO NEW DEPENDENCY - which is what
   keeps this out of the toolchain split PROJECT_STATUS.md 5.4 exists to
   protect, exactly as the note on IsElevated() above explains.

   WHAT IT ADMITS AND WHAT IT SHUTS.  A console logon carries 4; RDP and a
   remote-control product INSTALLED AS A SERVICE carry 4 plus 14 REMOTE
   INTERACTIVE, so both are admitted by testing 4 alone.  ssh carries 2 NETWORK
   and no 4.  An unattended scheduled task carries 3 BATCH and no 4.  The API
   is a socket session and was already excluded by CN_SOCKET.

   ***ELEVATION KEEPS IT, AND HAD IT NOT, THIS WOULD LOCK OUT THE CONSOLE
   ADMINISTRATOR*** - the one case that must keep working.  UAC hands back the
   LINKED token from the same logon session, so the logon SIDs are the filtered
   token's.  Measured rather than reasoned, from one ordinary session via
   TokenLinkedToken: INTERACTIVE true in BOTH legs, with
   BUILTIN\Administrators moving FALSE -> TRUE between them - the control that
   stops the two legs being one token read twice.

   A SIBLING OF IsElevated() RATHER THAN A SHARED WALK, DELIBERATELY, AND THE
   NEXT READER WILL WANT TO MERGE THEM.  The two bodies differ only in the gid,
   and folding them into one helper would move every "return FALSE" out of the
   functions test-privwhy-units.ps1 guards - whose per-predicate check would
   then pass on nothing, which is the null case PRE_RELEASE 96's whole guard
   exists to refuse.  Merge them only by strengthening that guard first.

   A PHANTOM INHERITS THIS AND THAT IS THE OWNER'S RULING, 5 Sep 2026.
   op_phantom() forks and execs (op_kernel.c), so a phantom carries the token
   of the session that started it, INTERACTIVE included - it has no desktop of
   its own and still tests TRUE.  Deliberate: the consent happened once, at a
   real desktop, and the phantom is that session's own work continued.  Do not
   "correct" it to a per-process desktop test; an administrator would then be
   unable to background anything at all.                                     */

bool IsInteractive(PRIV_WHY* why) {
  gid_t* list;
  int count;
  int i;
  bool status = FALSE;

  if (why != NULL)
    *why = PRIV_ANSWERED;

  count = getgroups(0, NULL);
  if (count <= 0) {
    if (why != NULL)
      *why = PRIV_NO_GROUP_COUNT;
    return FALSE; /* No groups in the token - fail closed */
  }

  list = (gid_t*)malloc(count * sizeof(gid_t));
  if (list == NULL) {
    if (why != NULL)
      *why = PRIV_NO_MEMORY;
    return FALSE;
  }

  if (getgroups(count, list) >= 0) {
    for (i = 0; i < count; i++) {
      if (list[i] == SD_INTERACTIVE_GID) {
        status = TRUE;
        break;
      }
    }
  } else {
    /* Sized, then would not fetch - the loop never ran, so the initialised
       FALSE below is not an answer.  IsElevated()'s note has the reasoning. */
    if (why != NULL)
      *why = PRIV_NO_GROUP_LIST;
  }

  free(list);

  return status;
}

/* ======================================================================
   priv_why_text()  -  Why could a privilege predicate not answer?

   03 Sep 26 Windows port - PRE_RELEASE_FIXES.md 96.  One mapping, so the four
   callers cannot describe the same failure two different ways.             */

char* priv_why_text(PRIV_WHY why) {
  switch (why) {
    case PRIV_ANSWERED:
      return "the check completed";
    case PRIV_NO_PASSWD:
      return "the account could not be looked up (getpwuid failed)";
    case PRIV_NO_GROUP_COUNT:
      return "the group list could not be sized";
    case PRIV_NO_MEMORY:
      return "out of memory";
    case PRIV_NO_GROUP_LIST:
      return "the group list sized and then could not be fetched";
    case PRIV_NO_USERNAME:
      return "the session has no user name";
    case PRIV_PATH_TOO_LONG:
      return "the os.users pathname did not fit";
    case PRIV_OPEN_FAILED:
      return "the os.users record could not be opened";
    case PRIV_READ_FAILED:
      return "the os.users record could not be read";
    case PRIV_MALFORMED:
      return "the os.users record has no second field";
  }

  return "unrecorded";
}

/* priv_log_undetermined() IS NOT HERE, AND THE LINKER IS THE REASON.
   03 Sep 26 - it lives in k_error.c beside log_message().  This file is linked
   into sdfix, sdtic, sdconv and sdidx, none of which carry the kernel's error
   log, so a log call here fails to LINK those four:
     "linuxlb.o: undefined reference to `log_message'"
   Measured, not guessed - it is what the first build of PRE_RELEASE 96 did.
   priv_why_text() above stays because it calls nothing.                    */

/* ======================================================================
   itoa()  -  Convert integer to string                                   */

char* itoa(value, string, radix) int value;
char* string;
int radix; /* Ignored */
{
  sprintf(string, "%d", value);
  return string;
}

/* ======================================================================
   Ltoa()  -  Convert long integer to string                              */

char* Ltoa(value, string, radix) int32_t value;
char* string;
int radix; /* Ignored */
{
  sprintf(string, "%d", value);
  return string;
}

/* ======================================================================
   GetUserName()  -  Return user name for logged in user.                 */

bool GetUserName(name, bytes) char* name;
u_int32_t* bytes; /* Buffer size - updated to actual size on exit */
{
  char* p;
  int n = 0;
  struct passwd* pw;

  pw = getpwuid(getuid());
  p = (pw == NULL) ? NULL : (pw->pw_name);

  if (p != NULL) {
    n = strlen(p);
    /* Modified by Composer AI - 2026/06/10.
       The truncation test was inverted: a name shorter than the buffer
       was padded by copying bytes from beyond the end of the password
       entry (returning a wrong length), and a name longer than the
       buffer was copied in full, overflowing it. Truncate only when the
       name does not fit. */
    /* if (*bytes >= n)
      n = *bytes - 1; */
    if (n >= (int)*bytes)
      n = *bytes - 1;
    /* -------------------- */
    memcpy(name, p, n);
  }
  *(name + n) = '\0';
  *bytes = n;

  return TRUE;
}

/* ======================================================================
   sdrealpath()  -  Emulation of realpath() with extension to handle
                    pathnames that do not exist.                          */

char* sdrealpath(char* inpath,  /* Supplied path */
                 char* outpath) /* Full path */
{
  char* tgt;
  char* p;
  char* q;
  struct stat st;
  int n;
  int link_depth = 0;
  char link_buf[PATH_MAX + 1];
/* 13 Aug 26 Windows port - see the note below */
  char path[PATH_MAX + 1];
  int root_len;

  /* 13 Aug 26 Windows port - accept the Windows spellings of a path.

     This function was the only reason a drive letter did not work anywhere
     in SD.  Nothing else objects to one: the MSYS2 runtime stats both
     C:\ProgramData\... and C:/ProgramData/... quite happily.  But here,
     anything not beginning with '/' was taken for a relative path and had
     the working directory glued in front of it, and a backslash was never
     a separator - so C:\ProgramData\SD resolved to
     /usr/local/sdsys/C:\ProgramData\SD and every open of it failed with
     ER_FNF, "file not found", pointing nowhere near the cause.

     Backslashes are now folded to '/' and a leading drive letter is treated
     as the root, so C:\ProgramData\SD resolves to C:/ProgramData/SD.  DS is
     still '/' and this does not change what SD produces (see
     PROJECT_STATUS.md section 6) - only what it will accept.              */

  n = 0;
  for (p = inpath, q = path; *p != '\0'; p++) {
    if (++n > PATH_MAX)
      return NULL;
    *(q++) = (*p == '\\') ? '/' : *p;
  }
  *q = '\0';
  inpath = path;

  if (((((inpath[0] >= 'A') && (inpath[0] <= 'Z')) ||
        ((inpath[0] >= 'a') && (inpath[0] <= 'z')))) &&
      (inpath[1] == ':')) /* Drive letter - absolute, the drive is the root */
  {
    outpath[0] = inpath[0];
    outpath[1] = ':';
    outpath[2] = '/';
    outpath[3] = '\0';
    tgt = outpath + 3;
    root_len = 3;
    p = inpath + 2;
  } else {
    root_len = 1;

    switch (inpath[0]) {
      case '/': /* Absolute pathname */
        outpath[0] = '/';
        tgt = outpath + 1;
        break;

      case '\0': /* Null pathname - error */
        return NULL;

      default: /* Relative pathname - get current directory */
        getcwd(outpath, PATH_MAX);
        tgt = strchr(outpath, '\0');
        break;
    }

    p = inpath; /* Source pointer */
  }

  while (*p != '\0') {
    /* Skip over multiple delimiters */
    while (*p == '/')
      p++;

    /* Find next delimiter or end of inpath */
    q = p;
    while (*q != '\0' && *q != '/')
      q++;
    n = q - p;

    if ((*p == '.') && (n == 1)) /* . reference */
    {
      /* Nothing to do */
    } else if ((*p == '.') && (*(p + 1) == '.') && (n == 2)) /* .. reference */
    {
      /* Revert one level unless already at root */
      if (tgt > outpath + root_len) {
        while (*((--tgt) - 1) != '/') {
        }
      }
    } else /* Name reference */
    {
      if (*(tgt - 1) != '/')
        *(tgt++) = '/';

      /* Append this name unless it would overrun the buffer */

      if (tgt + n - outpath >= PATH_MAX)
        return NULL;

      memcpy(tgt, p, n);
      p = q + 1;
      tgt += n;
      *tgt = '\0';

      /* Check the path exists and whether it is a symlink */

      if (lstat(outpath, &st) < 0) {
        if (errno != ENOENT)
          return NULL;

        /* Simply glue unrecognised component(s) on the end so that we
          return a fully resolved path of what we might be trying to
          create.                                                      */

        /* Modified by Composer AI - 2026/06/10.
           Cast the (always non-negative) pointer difference so the
           comparison is not done between signed and unsigned types. */
        /* if ((p - inpath) <= strlen(inpath)) { */
        if ((size_t)(p - inpath) <= strlen(inpath)) {
        /* -------------------- */
          if (tgt + strlen(p) + 1 >= outpath + PATH_MAX)
            return NULL; /* Too long */

          *(tgt++) = '/';
          strcpy(tgt, p);
        }
        return outpath;
      }

      if (S_ISLNK(st.st_mode)) {
        if (++link_depth > 20)
          return NULL; /* Symlinks too deep */

        n = readlink(outpath, link_buf, PATH_MAX);
        if (n < 0)
          return NULL;

        link_buf[n] = '\0';

        if (link_buf[0] == '/') /* It's an absolute symlink */
        {
          strcpy(outpath, link_buf);
          tgt = outpath + n;
          root_len = 1; /* 13 Aug 26 - back to a POSIX root */
        } else {
          /* Back up one level unless already at root directory */
          if (tgt > outpath + root_len)
            while (*((--tgt) - 1) != '/') {
            }

          if (tgt + n - outpath >= PATH_MAX)
            return NULL;

          strcpy(tgt, link_buf);
          tgt += n;
        }
      }
    }

    p = q;
  }

  /* Remove trailing / if present unless root directory reference */

  if (tgt > outpath + root_len && *(tgt - 1) == '/')
    tgt--;
  *tgt = '\0';

  return outpath;
}

/* ======================================================================
   Sleep()  -  Sleep for period in milliseconds                           */

void Sleep(n) int32_t n;
{
  struct timespec period;
  struct timespec remaining;

  period.tv_sec = n / 1000;
  period.tv_nsec = (n % 1000) * 1000000;
  nanosleep(&period, &remaining);
}

/* END-CODE */
