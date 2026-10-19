/* SDIDX.C
 * Index relocation tool
 * Copyright (c) 2005 Ladybridge Systems, All Rights Reserved
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
 * rev 0.9.0 Jan 25 mab change dyn file prefix to %
 * 18 Oct 26 Windows port - from Linux 04a6baf (18 Oct 26): - The old local index files are deleted through a PATH_LEN buffer (-m and -d used a 33 byte one, so a data
 *           path over 32 characters left the old %n behind and reported success).  -m and -d remove only the index
 *           subfiles the header lists, never the rest of a relocated directory, and remove that directory only if it
 *           is then empty (-m used to delete all of it, including a new target inside it).  -d answered n or met the
 *           end of input and still cleared the header: now it stops.  -p says what -q would say, and checks the
 *           header write.  A path argument over the header's limit is refused (strcpy overran the buffer).
 * 18 Oct 26 Windows port - from Linux 73aee7a (18 Oct 26): - A RELATIVE index path given to -m or -p is made absolute (from the current directory) before it is
 *           used and stored.  The header held the text as typed, so the indices were found only by a process whose
 *           current directory was the one the command was run from; SD never is.
 * 19 Oct 26 Windows port - index_path_arg(): a DRIVE-LETTER path is absolute.  Linux's test was a leading '/', so
 *           C:\data\idx was taken for a relative path and became <cwd>/C:\data\idx, which -m could not create and -p
 *           could not find: both ended status 1 with no message (verify-carry-tools, I1).  A relative path is completed
 *           from the current directory in WINDOWS form (getcwd() gives /cygdrive/c/...), as an absolute one is stored
 *           as typed (V12, V13).
 * END-HISTORY
 *  1 Sep 26 Windows port - make_path() keeps a drive letter as the root
 *           instead of mkdir'ing it as a component (PRE_RELEASE 6)
 * END-HISTORY      
 *
 * START-DESCRIPTION:
 *
 * sdidx -d datapath           Delete indices
 * sdidx -m datapath {akpath}  Move indices to new location
 * sdidx -p datapath {akpath}  Set index path
 * sdidx -q datapath           Report path   [ Default action if no option ]
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <ctype.h>

#define Public
#define init(a) = a

#include "sd.h"
#include "dh_int.h"
#include "revstamp.h"

#include <unistd.h>
/* 13 Aug 26 Windows port - POSIX shared memory in place of System V */
#include <sys/mman.h>
#include <sys/cygwin.h> /* 19 Oct 26 Windows port - cygwin_conv_path(), for index_path_arg() */
#include <sys/stat.h>
#include <fcntl.h>

#define Seek(fu, offset, whence) lseek(fu, offset, whence)

#define SF(ak) (ak + AK_BASE_SUBFILE)

char data_path[MAX_PATHNAME_LEN + 1] = "";
char ak_path[MAX_PATHNAME_LEN + 1] = "";

int pfu;          /* Primary subfile file handle */
DH_HEADER header; /* Primary subfile header */

#define BUFFER_SIZE 32768
char buffer[BUFFER_SIZE];

bool open_primary(void);
bool write_primary_header(void);
bool cross_check(char *path);
bool copy_indices(void);
bool yesno(void);
bool ak_file_path(char *path, char *dir, int16_t ak);
bool delete_index_files(char *dir, bool remove_dir);
void report_location(void);
bool bounded_copy(char *dst, char *src);
bool index_path_arg(char *dst, char *src);
bool make_path(char *tgt);
bool attach_shared_memory(void);
void unbind_sysseg(void);
bool fullpath(char *path, char *name);

/* ====================================================================== */

int main(int argc, char *argv[]) {
  int status = 1;
  int arg;
  char mode;
  bool ak_deleted = TRUE; /* Old index files all removed? */
  char old_akpath[MAX_PATHNAME_LEN + 1];
  struct stat stat_buf;

  printf(
      "[ SDIDX %s   Copyright, Ladybridge Systems, %s.  All rights reserved. "
      "]\n\n",
      SD_REV_STAMP, SD_COPYRIGHT_YEAR);

  /* Check command arguments */

  mode = 0;
  for (arg = 1; arg < argc; arg++) {
    if (argv[arg][0] != '-')
      break;

    /* Although there are currently no options other than the mode, the
      code below allows for future introduction of non-mode options.   */

    switch (toupper(argv[arg][1])) {
      case 'D': /* Delete indices */
        if (mode)
          goto usage;
        mode = 'D';
        break;

      case 'M': /* Move indices */
        if (mode)
          goto usage;
        mode = 'M';
        break;

      case 'P': /* Set index path */
        if (mode)
          goto usage;
        mode = 'P';
        break;

      case 'Q': /* Query path settings */
        if (mode)
          goto usage;
        mode = 'Q';
        break;

      default:
        goto usage;
    }
  }

  /* Select path by mode */

  switch (mode) {
    case 'D': /* Delete indices */
      if (arg >= argc)
        goto usage; /* Data pathname missing */
      if (!fullpath(data_path, argv[arg++]))
        goto exit_sdidx;
      if (arg != argc)
        goto usage; /* Unexpected argument */

      if (!open_primary())
        goto exit_sdidx;

      /* 18 Oct 26 dm - Only the index subfiles the header lists are removed, wherever they are.  A relocated
         directory is asked about first, and a "no" (or input that ends) leaves the header and the files alone: it
         used to clear the header and orphan the directory.  The directory itself goes only if it is then empty. */

      if (header.akpath[0] != '\0') /* Has relocated indices */
      {
        if ((stat(header.akpath, &stat_buf) == 0) /* Path exists */
            && (stat_buf.st_mode & S_IFDIR))      /* It's a directory */
        {
          printf("Delete the index files in %s (Y/N)", header.akpath);
          if (!yesno()) {
            printf("Indices not deleted\n");
            goto exit_sdidx;
          }
          ak_deleted = delete_index_files(header.akpath, TRUE);
        }
        header.akpath[0] = '\0'; /* Wipe out reference to indices */
      } else                     /* Delete all "local" index subfiles */
      {
        ak_deleted = delete_index_files(data_path, FALSE);
      }

      header.ak_map = 0; /* Clear AK map */
      if (!write_primary_header())
        goto exit_sdidx;
      if (!ak_deleted) {
        printf("The indices are removed from the file, but some index files could not be deleted\n");
        goto exit_sdidx;
      }
      printf("All indices deleted\n");
      break;

    case 'M': /* Move indices */
      if (arg >= argc)
        goto usage; /* Data pathname missing */
      if (!fullpath(data_path, argv[arg++]))
        goto exit_sdidx;
      if (arg < argc) {
        if (!index_path_arg(ak_path, argv[arg++]))
          goto exit_sdidx;
      }
      if (arg != argc)
        goto usage; /* Unexpected argument */

      if (!open_primary())
        goto exit_sdidx;

      /* Check we are not moving to the current index location */

      if (strcmp(ak_path, header.akpath) == 0) {
        printf("Indices are already at this location\n");
        goto exit_sdidx;
      }

      /* Cross-check that these indices really belong to this file */

      if (!cross_check(header.akpath))
        goto exit_sdidx;

      /* Confirm target directory does not exist */

      if (ak_path[0] != '\0') {
        /* Check target location does not already exist */

        if (stat(ak_path, &stat_buf) == 0) {
          printf("%s already exists\n", ak_path);
          goto exit_sdidx;
        }

        /* Create the directory */

        if (!make_path(ak_path))
          goto exit_sdidx;
      }

      /* Copy indices */

      if (!copy_indices())
        goto exit_sdidx;

      /* Update primary header */

      strcpy(old_akpath, header.akpath);
      strcpy(header.akpath, ak_path);
      if (!write_primary_header())
        goto exit_sdidx;

      /* Remove old indices - the index subfiles only, see -d above */

      if (old_akpath[0] != '\0') /* Had relocated indices */
      {
        ak_deleted = delete_index_files(old_akpath, TRUE);
      } else /* Delete all "local" index subfiles */
      {
        ak_deleted = delete_index_files(data_path, FALSE);
      }

      if (!ak_deleted) {
        printf("Indices have been moved, but the old index files could not all be deleted\n");
        goto exit_sdidx;
      }
      printf("Indices have been moved\n");
      break;

    case 'P': /* Set index path */
      if (arg >= argc)
        goto usage; /* Data pathname missing */
      if (!fullpath(data_path, argv[arg++]))
        goto exit_sdidx;
      if (arg < argc) {
        if (!index_path_arg(ak_path, argv[arg++]))
          goto exit_sdidx;
      }
      if (arg != argc)
        goto usage; /* Unexpected argument */

      if (!open_primary())
        goto exit_sdidx;

      if (strcmp(ak_path, header.akpath) == 0) {
        printf("Indices are already at this location\n");
        goto exit_sdidx;
      }

      if (ak_path[0] != '\0') {
        /* Check target location exists */

        if (stat(ak_path, &stat_buf) != 0) {
          printf("%s does not exist\n", ak_path);
          goto exit_sdidx;
        }

        if (!(stat_buf.st_mode & S_IFDIR)) {
          printf("%s is not a directory\n", ak_path);
          goto exit_sdidx;
        }
      }

      /* Cross-check that indices are for this file */

      if (!cross_check(ak_path))
        goto exit_sdidx;

      /* Update primary header */

      strcpy(header.akpath, ak_path);
      if (!write_primary_header())
        goto exit_sdidx;

      /* 18 Oct 26 dm - Say what was done, in the words -q uses.  Every other mode prints its result; this one
         printed nothing, so a success looked like nothing having happened.  sd-elevate's akpath-set still checks
         with -q itself. */

      report_location();
      break;

    case 'Q': /* Query path settings */
    case '\0':
      if (arg >= argc)
        goto usage; /* Data pathname missing */
      if (!fullpath(data_path, argv[arg++]))
        goto exit_sdidx;
      if (arg != argc)
        goto usage; /* Unexpected argument */

      if (!open_primary())
        goto exit_sdidx;

      report_location();
      break;

    default:
      goto usage;
  }

  status = 0;

exit_sdidx:
  return status;

usage:
  printf("sdidx -d datapath           Delete indices\n");
  printf("sdidx -m datapath {akpath}  Move indices to new location\n");
  printf("sdidx -p datapath {akpath}  Set index path\n");
  printf("sdidx -q datapath           Report path\n");
  printf("sdidx datapath              Report path\n");

  return 1;
}

/* ======================================================================
   open_primary()  -  Open primary subfile                                */

bool open_primary() {
  bool status = FALSE;
  char pathname[MAX_PATHNAME_LEN + 1];
  int fno;
  FILE_ENTRY *fptr;
  // converted to snprintf() -gwb 25Feb20
/* rev 0.9.0 */  
  if (snprintf(pathname, MAX_PATHNAME_LEN + 1, "%s%c%%0", data_path, DS) >= (MAX_PATHNAME_LEN + 1)) {
    printf("Overflowed path/filename buffer.  Truncated to:\n%s%c%%0\n", data_path, DS);
  }

  /* Check that this file is not currently in use within SD */

  if (attach_shared_memory()) {
    for (fno = 1; fno <= sysseg->used_files; fno++) {
      fptr = FPtr(fno);
      if (fptr->ref_ct != 0) {
        if (strcmp((char *)(fptr->pathname), data_path) == 0) {
          printf("File is currently open within SD\n");
          goto exit_open_primary;
        }
      }
    }
    unbind_sysseg();
  }

  pfu = open(pathname, (int)(O_RDWR | O_BINARY), default_access);
  if (pfu < 0) {
    printf("Cannot open data file [%d]\n", errno);
    goto exit_open_primary;
  }

  if (read(pfu, (u_char *)&header, DH_HEADER_SIZE) != DH_HEADER_SIZE) {
    printf("Read error in primary subfile [%d]\n", errno);
    goto exit_open_primary;
  }

  /* Check magic number in primary subfile */

  if (header.magic != DH_PRIMARY) {
    printf("Incorrect magic number in primary subfile\n");
    goto exit_open_primary;
  }

  status = TRUE;

exit_open_primary:
  return status;
}

/* ======================================================================
   write_primary_header()  -  Write primary subfile header                */

bool write_primary_header() {
  if (Seek(pfu, 0, SEEK_SET) < 0) {
    printf("Seek error positioning to write primary subfile header [%d]\n", errno);
    return FALSE;
  }

  if (write(pfu, (char *)&header, DH_HEADER_SIZE) != DH_HEADER_SIZE) {
    printf("Error writing primary subfile header [%d]\n", errno);
    return FALSE;
  }

  return TRUE;
}

/* ======================================================================
   cross_check()  -  Cross-check index subfile                            */

bool cross_check(char *path) {
  bool status = FALSE;
  char pathname[MAX_PATHNAME_LEN + 1];
  int16_t ak;
  DH_AK_HEADER ak_header;
  int akfu = -1;

  for (ak = 0; ak < MAX_INDICES; ak++) {
    if (header.ak_map & (1 << ak)) {
 /*  20240122  mab change sprintf to snprintf and test for buffer overflow */ 
/* rev 0.9.0 */     
      if (snprintf(pathname, MAX_PATHNAME_LEN + 1, "%s%c%%%d", (path[0] != '\0') ? path : data_path, DS, SF(ak)) >= (MAX_PATHNAME_LEN + 1)){
        printf("Overflowed directory/filename path length in sdidx.c cross_check()");
        goto exit_cross_check;
      }
      akfu = open(pathname, (int)(O_RDONLY | O_BINARY), default_access);
      if (akfu < 0) {
        printf("Cannot open index subfile %d [%d]\n", SF(ak), errno);
        goto exit_cross_check;
      }

      if (read(akfu, (u_char *)&ak_header, DH_AK_HEADER_SIZE) != DH_AK_HEADER_SIZE) {
        printf("Read error in index subfile %d [%d]\n", SF(ak), errno);
        goto exit_cross_check;
      }

      /* Check magic number in primary subfile */

      if (ak_header.magic != DH_INDEX) {
        printf("Incorrect magic number in index subfile %d\n", SF(ak));
        goto exit_cross_check;
      }

      /* Cross-check with primary subfile */

      if (ak_header.data_creation_timestamp != header.creation_timestamp) {
        printf("Index subfile %d does not appear to belong to the data file\n", SF(ak));
        goto exit_cross_check;
      }

      close(akfu);
      akfu = -1;
    }
  }

  status = TRUE;

exit_cross_check:
  if (akfu >= 0)
    close(akfu);

  return status;
}

/* ======================================================================
   copy_indices()  -  Copy indices to new location                        */

bool copy_indices() {
  bool status = FALSE;
  char src[MAX_PATHNAME_LEN + 1];
  char tgt[MAX_PATHNAME_LEN + 1];
  int16_t ak;
  int src_fu = -1;
  int tgt_fu = -1;
  int bytes;

  for (ak = 0; ak < MAX_INDICES; ak++) {
    if (header.ak_map & (1 << ak)) {
      printf("Moving index subfile %d\n", SF(ak));

      /* Form source path and open subfile */
/*  20240122  mab change sprintf to snprintf and test for buffer overflow */
/* rev 0.9.0 */
      if (snprintf(src,MAX_PATHNAME_LEN + 1,"%s%c%%%d", (header.akpath[0] != '\0') ? header.akpath : data_path, DS, SF(ak)) >= (MAX_PATHNAME_LEN + 1)){
        printf("Overflowed directory/filename path length in sdidx.c copy_indices()");
        goto exit_copy_indices;
      }

      src_fu = open(src, (int)(O_RDONLY | O_BINARY), default_access);
      if (src_fu < 0) {
        printf("Cannot open old index subfile %d [%d]\n", SF(ak), errno);
        goto exit_copy_indices;
      }

      /* Form target path and open subfile */
/*  20240122  mab change sprintf to snprintf and test for buffer overflow */
/* rev 0.9.0 */
      if (snprintf(tgt, MAX_PATHNAME_LEN + 1, "%s%c%%%d", (ak_path[0] != '\0') ? ak_path : data_path, DS, SF(ak)) >= (MAX_PATHNAME_LEN + 1)){
        printf("Overflowed directory/filename path length in sdidx.c copy_indices()");
        goto exit_copy_indices;
      }

      tgt_fu = open(tgt, (int)(O_RDWR | O_CREAT | O_EXCL | O_BINARY), default_access);
      if (tgt_fu < 0) {
        printf("Cannot create new index subfile %d [%d]\n", SF(ak), errno);
        goto exit_copy_indices;
      }

      while ((bytes = read(src_fu, buffer, BUFFER_SIZE)) > 0) {
        if (write(tgt_fu, buffer, bytes) != bytes) {
          printf("Write error in new index subfile %d [%d]\n", SF(ak), errno);
          goto exit_copy_indices;
        }
      }

      close(src_fu);
      src_fu = -1;
      close(tgt_fu);
      tgt_fu = -1;
    }
  }

  status = TRUE;

exit_copy_indices:
  if (src_fu >= 0)
    close(src_fu);
  if (tgt_fu >= 0)
    close(tgt_fu);

  return status;
}

/* ====================================================================== */

/* 18 Oct 26 dm - A "no" is the only way to get FALSE out of this except the end of input, which used to leave the
   buffer as it was and so answered whatever the stack held (or looped for ever).  The end of input is "no". */

bool yesno() {
  char c;
  char s[10 + 1];

  do {
    printf("? ");
    fflush(stdout);
    if (fgets(s, sizeof(s), stdin) == NULL) {
      printf("\nEnd of input\n");
      return FALSE;
    }
    c = toupper(s[0]);
  } while ((c != 'Y') && (c != 'N'));
  return (c == 'Y');
}

/* ======================================================================
   ak_file_path()  -  Form the path of index subfile AK in directory DIR  */

bool ak_file_path(char *path, char *dir, int16_t ak) {
  if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s%c%%%d", dir, DS, SF(ak)) >= (MAX_PATHNAME_LEN + 1)) {
    printf("Overflowed directory/filename path length in sdidx.c, index subfile %d\n", SF(ak));
    return FALSE;
  }
  return TRUE;
}

/* ======================================================================
   delete_index_files()  -  Delete the index subfiles the header lists
   from directory DIR, and nothing else.  With REMOVE_DIR (a relocated
   directory) the directory is removed too, but only if that leaves it
   empty; one that holds anything else is left and said so.  A file that
   is not there is not a failure.  Returns FALSE if a delete failed.      */

bool delete_index_files(char *dir, bool remove_dir) {
  bool status = TRUE;
  char path[MAX_PATHNAME_LEN + 1];
  int16_t ak;

  for (ak = 0; ak < MAX_INDICES; ak++) {
    if (header.ak_map & (1 << ak)) {
      if (!ak_file_path(path, dir, ak)) {
        status = FALSE;
        continue;
      }
      if ((remove(path) != 0) && (errno != ENOENT)) {
        printf("Cannot delete %s [%d]\n", path, errno);
        status = FALSE;
      }
    }
  }

  if (remove_dir && status && (rmdir(dir) != 0)) {
    if ((errno == ENOTEMPTY) || (errno == EEXIST))
      printf("%s holds other files and has been left\n", dir);
    else if (errno != ENOENT) {
      printf("Cannot remove directory %s [%d]\n", dir, errno);
      status = FALSE;
    }
  }

  return status;
}

/* ======================================================================
   report_location()  -  Say where the indices are (-q, and -p after it)  */

void report_location() {
  if (header.ak_map == 0) {
    printf("File has no indices\n");
  } else if (header.akpath[0] == '\0') {
    printf("Indices are not relocated\n");
  } else {
    printf("Index directory is %s\n", header.akpath);
  }
}

/* ======================================================================
   bounded_copy()  -  Copy a path argument into one of the path buffers,
   refusing one the file header could not hold                            */

bool bounded_copy(char *dst, char *src) {
  if (strlen(src) > MAX_PATHNAME_LEN) {
    printf("Path is too long (the limit is %d characters)\n", MAX_PATHNAME_LEN);
    return FALSE;
  }
  strcpy(dst, src);
  return TRUE;
}

/* ======================================================================
   index_path_arg()  -  The index path argument of -m and -p, as it is
   stored in the header: a relative one is taken from the current
   directory and so made absolute.  An empty one (the indices go back
   into the file's own directory) stays empty.                            */

bool index_path_arg(char *dst, char *src) {
  char cwd[PATH_MAX + 1];
  char full[MAX_PATHNAME_LEN + 1];
  char win[MAX_PATHNAME_LEN + 1];

  if (!bounded_copy(dst, src))
    return FALSE;
  if ((dst[0] == '\0') || (dst[0] == DS))
    return TRUE;

  /* 19 Oct 26 Windows port - the drive letter is the root (same test as make_path() below). */

  if (isalpha((unsigned char)dst[0]) && (dst[1] == ':'))
    return TRUE;

  if (getcwd(cwd, sizeof(cwd)) == NULL) {
    printf("Cannot find the current directory to complete %s [%d]\n", src, errno);
    return FALSE;
  }
  if (snprintf(full, sizeof(full), "%s%c%s", cwd, DS, src) >= (int)sizeof(full)) {
    printf("Path is too long (the limit is %d characters)\n", MAX_PATHNAME_LEN);
    return FALSE;
  }

  /* 19 Oct 26 Windows port - getcwd() answers in POSIX form (/cygdrive/c/...); what is stored is the form a user types
     here, C:\...  An absolute path typed by the user is stored as typed, so a relative one is completed the same way. */

  if (cygwin_conv_path(CCP_POSIX_TO_WIN_A, full, win, sizeof(win)) == 0)
    strcpy(dst, win);
  else
    strcpy(dst, full);
  return TRUE;
}

/* ======================================================================
   make_path()  -  Recursive mkdir to make directory path                 */

bool make_path(char *tgt) {
  char path[MAX_PATHNAME_LEN + 1];
  char new_path[MAX_PATHNAME_LEN + 3]; /* 18 Oct 26 dm - room for the separator added after the last component */
  struct stat statbuf;
  char *p;
  char *q;
  /* Modified by Composer AI - 2026/06/10.
     Use re-entrant strtok_r() instead of strtok(). */
  char* savep = NULL;
  /* -------------------- */

  strcpy(path, tgt);

  p = path;
  q = new_path;

  /* 1 Sep 26 Windows port - A DRIVE LETTER IS PART OF THE ROOT, NOT A PATH
   * COMPONENT.  Second copy of the same fault; the reasoning and the
   * measurement are written up once, at make_path() in op_dio2.c.  Without
   * this, a drive-lettered ak_path (sdidx.c:215) makes a directory called
   * "C:" - on NTFS U+0043 U+F03A - in whatever the current directory is. */

  if (((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')) && (p[1] == ':')) {
    *(q++) = *p;
    *(q++) = ':';
    *(q++) = DS;
    p += 2;
  } else if (*p == DS) /* 0355 */
  {
    *(q++) = DS;
    p++;
  }
  *q = '\0';

  /* Modified by Composer AI - 2026/06/10. See savep above. */
  /* while ((q = strtok(p, DSS)) != NULL) { */
  while ((q = strtok_r(p, DSS, &savep)) != NULL) {
  /* -------------------- */
    strcat(new_path, q);

    if (stat(new_path, &statbuf)) /* Directory does not exist */
    {
      if (MakeDirectory(new_path) != 0)
        return FALSE;
    } else if (!(statbuf.st_mode & S_IFDIR)) /* Exists but not as a directory */
    {
      return FALSE;
    }

    strcat(new_path, DSS);
    p = NULL;
  }

  return TRUE;
}

/* ======================================================================
   Attach to shared memory segment                                        */

static size_t sysseg_bytes = 0; /* Mapped size, needed by munmap() */

bool attach_shared_memory() {
  int fd;
  struct stat statbuf;

  if ((fd = shm_open(SD_POSIX_SHM_NAME, O_RDWR, 0666)) == -1)
    return FALSE; /* Not started */

  if (fstat(fd, &statbuf) || statbuf.st_size == 0) {
    close(fd);
    return FALSE;
  }

  sysseg = (SYSSEG *)mmap(NULL, (size_t)statbuf.st_size,
                          PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);

  if (sysseg == MAP_FAILED) {
    sysseg = NULL;
    printf("Error %d attaching to shared segment\n", errno);
    return FALSE;
  }

  sysseg_bytes = (size_t)statbuf.st_size;

  return TRUE;
}

/* ====================================================================== */

void unbind_sysseg() {
  if (sysseg != NULL) {
    munmap((void *)sysseg, sysseg_bytes);
    sysseg = NULL;
    sysseg_bytes = 0;
  }
}

/* ======================================================================
   fullpath()  -  Map a pathname to its absolute form                     */

bool fullpath(char *path, char *name) {
  //char* path; /* Out */
  // char* name; /* In */

  bool ok;

  /* realpath() requires that the buffer is PATH_MAX bytes even for short
    pathnames. Use a temporary buffer and then copy the data back to the
    caller's buffer.                                                      */

  /* 18 Oct 26 dm - When realpath() fails (no such path) buff was copied unset, and a path longer than the caller's
     buffer overran it.  A path that cannot be resolved is kept as given, so the open reports why; one the buffer
     (and the file header) cannot hold is refused.  The result is FALSE only for the second.                    */

  char buff[PATH_MAX + 1];
  ok = (realpath(name, buff) != NULL);

  return bounded_copy(path, ok ? buff : name);
}

/* END-CODE */
