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

   SD administrator rights now come from membership of the SD_ADMIN_GROUP local
   group.  That deliberately separates SD administration from Windows
   administration: granting it does not require handing out machine admin, it
   needs no elevation prompt, and it works for a service or other
   non-interactive process.  If the group does not exist, nobody is an
   administrator, which fails closed.                                       */

bool IsAdmin(void) {
  struct group* grp;
  gid_t* list;
  int count;
  int i;
  bool status = FALSE;

  grp = getgrnam(SD_ADMIN_GROUP);
  if (grp == NULL)
    return FALSE; /* Group not defined - nobody qualifies */

  /* The group may be our primary one, in which case it need not appear in the
     supplementary list.                                                     */

  if ((getgid() == grp->gr_gid) || (getegid() == grp->gr_gid))
    return TRUE;

  count = getgroups(0, NULL);
  if (count <= 0)
    return FALSE;

  list = (gid_t*)malloc(count * sizeof(gid_t));
  if (list == NULL)
    return FALSE;

  if (getgroups(count, list) == count) {
    for (i = 0; i < count; i++) {
      if (list[i] == grp->gr_gid) {
        status = TRUE;
        break;
      }
    }
  }

  free(list);

  return status;
}

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
