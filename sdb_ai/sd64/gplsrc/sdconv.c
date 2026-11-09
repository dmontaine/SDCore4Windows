/* SDCONV.C
 * File convertor for high/low byte systems.
 * Copyright (c) 2006 Ladybridge Systems, All Rights Reserved
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
 * 
 * START-HISTORY:
 * 31 Dec 23 SD launch - prior history suppressed
 * rev 0.9.0 Jan 25 mab change dyn file prefix to %
 * 18 Oct 26 Windows port - from Linux c42aa13 (18 Oct 26): A hashed file is refused with a message and exit status 1 (owner's choice "A", 18 Oct): the call that converted it was
 *               commented out in a warning clean-up and the branch ran the compiled-program converter on a directory, so the command
 *               printed nothing, changed nothing and exited 0.  This SD cannot open a big-endian hashed file, and the owner works on
 *               Linux and Windows only (both little-endian).
 * 06 Nov 26 dm  S.152 (owner, 6 Nov: "All 20"): the hashed-file converter, unreachable since 18 Oct, is removed - process_file,
 *               open_subfile, read_block, write_block, write_header, swap8, convert_primary_header and the globals only they used
 *               (fu, oheader, header_bytes, ak_header_size, the block buffer).  process_file also read fu[34] past the end of fu
 *               after its index loop.  The compiled-program converter is unchanged.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * sdconv {options} pathname(s)
 *
 * Options:
 *   -B   Convert to big-endian format
 *   -L   Convert to little-endian format
 *        If neither option is given, converts to format of machine on
 *        which it is being run.
 *
 *   -D   Debug - Prints detailed progress information.
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
#include "header.h"
#include "revstamp.h"

static bool file_found = FALSE;
static bool file_refused = FALSE; /* A hashed file was named: sdconv does not convert those */
static DH_HEADER header;       /* Primary subfile header, read by is_dh_file() */

#define TO_CURRENT 0
#define TO_BIG 1
#define TO_LITTLE 2
static int16_t mode = TO_CURRENT;
static bool converting_to_inverse; /* Are we going away from this system? */

static bool debug = FALSE;

void convert_file(char* fn);
bool is_dh_file(char* fn);
bool is_object_file(char* fn);
int process_object_file(char* fn);
int16_t swap2(int16_t data);
int32_t swap4(int32_t data);
bool convert_object(OBJECT_HEADER* obj, int bytes, bool skip_fields);

#define Reverse2(a) a = swap2(a)
#define Reverse4(a) a = swap4(a)

#define Seek(fu, offset, whence) lseek(fu, offset, whence)

/* ====================================================================== */

int main(int argc, char* argv[]) {
  int status = 1;
  int arg;
  int argx;
  bool arg_end;

  printf(
      "[ SDCONV %s   Copyright, Ladybridge Systems, %s.  All rights reserved. "
      "]\n\n",
      SD_REV_STAMP, SD_COPYRIGHT_YEAR);

  /* Check command arguments */

  for (arg = 1; arg < argc; arg++) {
    if (argv[arg][0] != '-')
      break;

    argx = 1;
    arg_end = FALSE;
    do {
      switch (toupper(argv[arg][argx])) {
        case '\0':
          arg_end = TRUE;
          break;

        case 'B':
          mode = TO_BIG;
          break;

        case 'D':
          debug = TRUE;
          break;

        case 'L':
          mode = TO_LITTLE;
          break;

        default:
          goto usage;
      }

      argx++;
    } while (!arg_end);
  }

  if (arg == argc)
    goto usage; /* No filenames */

#ifdef BIG_ENDIAN_SYSTEM
  converting_to_inverse = (mode == TO_LITTLE);
#else
  converting_to_inverse = (mode == TO_BIG);
#endif

  while (arg < argc) {
    convert_file(argv[arg]);
    arg++;
  }

  status = (file_refused) ? 1 : 0;

exit_sdconv:
  return status;

usage:
  printf("Usage: SDCONV {options} pathname(s)\n\n");
  printf("Options:\n");
  printf("   -B      Force conversion to big-endian\n");
  printf("   -L      Force conversion to little-endian\n");
  printf("\nOnly compiled programs are converted; a hashed file is refused (exit status 1).\n");

  goto exit_sdconv;
}

/* ======================================================================
   convert_file()                                                         */

void convert_file(char* fn) {
  // int status; value set but never used.
  char filename[MAX_PATHNAME_LEN + 1];

  strcpy(filename, fn);

  if (is_dh_file(filename)) {
    /* 18 Oct 26: refused, not converted (see the history line).  The old code ran process_object_file() on the directory. */
    printf("%s is a hashed file: sdconv converts compiled programs only, nothing was changed\n", filename);
    file_refused = TRUE;
  } else if (is_object_file(filename)) {
    if (file_found)
      printf("\n\n");
    file_found = TRUE;
    // status = process_object_file(filename);
    // value is never used, so don't assign it.
    process_object_file(filename);
  }
}

/* ======================================================================
   is_dh_file()                                                           */

bool is_dh_file(char* filename) {
  bool status = FALSE;
  int dhfu = -1;
  char pathname[MAX_PATHNAME_LEN + 1];
  struct stat statbuf;
/* rev 0.9.0 */
  sprintf(pathname, "%s%c%%0", filename, DS);

  if (stat(pathname, &statbuf) != 0)
    goto exit_is_dh_file;

  if (!(statbuf.st_mode & S_IFREG))
    goto exit_is_dh_file;

  dhfu = open(pathname, (int)(O_RDWR | O_BINARY), default_access);
  if (dhfu < 0)
    goto exit_is_dh_file;

  if (read(dhfu, (u_char*)&header, DH_HEADER_SIZE) != DH_HEADER_SIZE) {
    goto exit_is_dh_file;
  }

  /* Check magic number in primary subfile */

  if ((header.magic != DH_PRIMARY) && (swap2(header.magic) != DH_PRIMARY)) {
    goto exit_is_dh_file;
  }

  status = TRUE;

exit_is_dh_file:
  if (dhfu >= 0)
    close(dhfu);
  return status;
}

/* ======================================================================
   is_object_file()                                                      */

bool is_object_file(char* filename) {
  bool status = FALSE;
  int objfu = -1;
  struct stat statbuf;
  OBJECT_HEADER obj_header;

  if (stat(filename, &statbuf) != 0)
    goto exit_is_object_file;

  if (!(statbuf.st_mode & S_IFREG))
    goto exit_is_object_file;

  objfu = open(filename, (int)(O_RDWR | O_BINARY), default_access);
  if (objfu < 0)
    goto exit_is_object_file;

  if (read(objfu, (u_char*)&obj_header, OBJECT_HEADER_SIZE) !=
      OBJECT_HEADER_SIZE) {
    goto exit_is_object_file;
  }

  /* Check magic number */

  if ((obj_header.magic != HDR_MAGIC) &&
      (obj_header.magic != HDR_MAGIC_INVERSE)) {
    goto exit_is_object_file;
  }

  status = TRUE;

exit_is_object_file:
  if (objfu >= 0)
    close(objfu);
  return status;
}

/* ======================================================================
   process_object_file()  -  Process an object file                       */

int process_object_file(char* filename) {
  int status = 1;
  int objfu = -1;
  int fsize;
  OBJECT_HEADER* obj = NULL;

  objfu = open(filename, (int)(O_RDWR | O_BINARY), default_access);
  if (objfu < 0)
    goto exit_process_object_file;

  fsize = filelength(objfu);
  obj = malloc(fsize);
  if (obj == NULL) {
    printf("Cannot allocate memory for %s\n", filename);
    goto exit_process_object_file;
  }

  if (read(objfu, (u_char*)obj, fsize) != fsize) {
    printf("Cannot read %s\n", filename);
    goto exit_process_object_file;
  }

  if (!convert_object(obj, fsize, FALSE)) {
    printf("Error converting %s\n", filename);
    goto exit_process_object_file;
  }

  if (Seek(objfu, 0, SEEK_SET) < 0) {
    printf("Seek error in %s\n", filename);
    goto exit_process_object_file;
  }

  if (write(objfu, (u_char*)obj, fsize) != fsize) {
    printf("Write error in %s\n", filename);
    goto exit_process_object_file;
  }

  status = 0;

exit_process_object_file:
  if (objfu >= 0)
    close(objfu);
  if (obj != NULL)
    free(obj);
  return status;
}

/* ======================================================================
   swap2()                                                                */

int16_t swap2(int16_t data) {
  union {
    int16_t val;
    unsigned char chr[2];
  } in, out;

  in.val = data;
  out.chr[0] = in.chr[1];
  out.chr[1] = in.chr[0];
  return out.val;
}

/* ======================================================================
   swap4()                                                                */

int32_t swap4(int32_t data) {
  union {
    int32_t val;
    unsigned char chr[4];
  } in, out;

  in.val = data;
  out.chr[0] = in.chr[3];
  out.chr[1] = in.chr[2];
  out.chr[2] = in.chr[1];
  out.chr[3] = in.chr[0];
  return out.val;
}

/* ======================================================================
   convert_object()                                                       */

bool convert_object(OBJECT_HEADER* obj, int bytes, bool skip_fields) {
  u_char tgt_magic;
  u_char expected_magic;
  int16_t i;
  u_char* p;

  if (skip_fields) /* AK has dictionary fields on front of object code */
  {
    p = (u_char*)obj;
    for (i = 15; i--;) /* Skip 15 field marks */
    {
      p = (u_char*)strchr((char*)p, (char)FIELD_MARK);
      if (p == NULL) {
        printf("Invalid AK object code\n");
        return FALSE;
      }
      p++;
    }
    obj = (OBJECT_HEADER*)p;
  }

  tgt_magic = (converting_to_inverse) ? HDR_MAGIC_INVERSE : HDR_MAGIC;
  if (obj->magic == tgt_magic)
    return TRUE;

  expected_magic = (converting_to_inverse) ? HDR_MAGIC : HDR_MAGIC_INVERSE;
  if (obj->magic != expected_magic) {
    printf("Invalid magic number (%d) in object code\n", obj->magic);
    return FALSE;
  }

  /* ========== Object header */

  Reverse4(obj->id);
  Reverse4(obj->start_offset);
  Reverse2(obj->args);
  Reverse2(obj->no_vars);
  Reverse2(obj->stack_depth);
  Reverse4(obj->sym_tab_offset);
  Reverse4(obj->line_tab_offset);
  Reverse4(obj->object_size);
  Reverse2(obj->flags);
  Reverse4(obj->compile_time);
  obj->magic = tgt_magic;

  return TRUE;
}

/* END-CODE */
