/* OP_DIO2.C
 * Disk i/o opcodes part 2 (Information opcodes)
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
 * START-HISTORY:
 * 31 Dec 23 SD launch - prior history suppressed
 * 21 Aug 26 Windows port - net_path_permitted(), the containment root for a
 *           network session, and the read/write axis on the shared entries
 *  1 Sep 26 Windows port - make_path() keeps a drive letter as the root
 *           instead of mkdir'ing it as a component (PRE_RELEASE 6)
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *  op_fileinfo        FILEINFO
 *  op_sysdir          SYSDIR
 *  op_ospath          OSPATH
 *  net_path_permitted May this session touch this path?
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "keys.h"
#include "dh_int.h"
#include "header.h"
#include "syscom.h"

#include <time.h>
#include <stdint.h>
#include <pwd.h>
#include <grp.h>
/* 21 Aug 26 Windows port - cygwin_conv_path(), for net_path_permitted().
   op_kernel.c includes this too, for K_WINPATH.                           */
#include <sys/cygwin.h>

Private bool valid_name(char* p);
Private bool attach(char* path);
Private STRING_CHUNK* get_file_status(FILE_VAR* fvar);
Private bool net_normalise(char* path, char* out);
Private bool path_within(char* cand, char* root);
Private bool has_parent_ref(char* path);
Private bool net_raw_permitted(char* path, bool for_write);

bool make_path(char* tgt);
bool FDS_open(DH_FILE* dh_file, int16_t subfile);

/* ======================================================================
   op_fileinfo()  -  Return information about an open file                */

void op_fileinfo() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Key                           | Information                 |
     |--------------------------------|-----------------------------| 
     |  ADDR to file variable         |                             |
     |================================|=============================|

 Key values:           Action                         Returns
     0 FL_OPEN         Test if is open file variable  True/False
     1 FL_VOCNAME      Get VOC name of file           VOC name
     2 FL_PATH         Get file pathname              Pathname
     3 FL_TYPE         Check file type                DH:         FL_TYPE_DH  (3)
                                                      Directory:  FL_TYPE_DIR (4)
                                                      Sequential: FL_TYPE_SEQ (5)
     5 FL_MODULUS      File modulus                   Modulus value
     6 FL_MINMOD       Minimum modulus                Minimum modulus value
     7 FL_GRPSIZE      Group size                     Group size
     8 FL_LARGEREC     Large record size              Large record size
     9 FL_MERGE        Merge load percentage          Merge load
    10 FL_SPLIT        Split load percentage          Split load
    11 FL_LOAD         Current load percentage        Current load
    13 FL_AK           File has AK indices?           Boolean
    14 FL_LINE         Number of next line            Line number
  1000 FL_LOADBYTES    Current load in bytes          Current load bytes
  1001 FL_READONLY     Read only file?                Boolean
  1002 FL_TRIGGER      Get trigger function name      Call name
  1003 FL_PHYSBYTES    Physical file size             Size in bytes, excl indices
  1004 FL_VERSION      File version
  1005 FL_STATS_QUERY  Query file stats status        Boolean
  1006 FL_SEQPOS       File position                  File offset
  1007 FL_TRG_MODES    Get trigger modes              Mode mask
  1008 FL_NOCASE       File uses case insensitive ids?  Boolean
  1009 FL_FILENO       Return internal file number    File number
  1010 FL_JNL_FNO      Return journalling file no     File no, zero if not journalling
  1011 FL_AKPATH       Returns AK subfile location    Pathname of directory
  1012 FL_ID           Id of last record read         Id
  1013 FL_STATUS       As STATUS statement            Dynamic array
  1014 FL_MARK_MAPPING Is mark mapping enabled?       Boolean
  1015 FL_RECORD_COUNT Approximate record count
  1016 FL_PRI_BYTES    Primary subfile size in bytes
  1017 FL_OVF_BYTES    Overflow subfile size in bytes
  1018 FL_NO_RESIZE    Resizing inhibited?
  1019 FL_UPDATE       Update counter
  1020 FL_ENCRYPTED    File uses encryption?          Boolean
 10000 FL_EXCLUSIVE    Set exclusive access           Successful?
 10001 FL_FLAGS        Fetch file flags               File flags
 10002 FL_STATS_ON     Turn on file statistics
 10003 FL_STATS_OFF    Turn off file statistics
 10004 FL_STATS        Return file statistics
 10005 FL_SETRDONLY    Set file as read only
 */

  int16_t key;
  DESCRIPTOR* descr;
  FILE_VAR* fvar;
  /* Modified by Composer AI - 2026/06/10.
     dh_file and floatnum are only assigned on some switch paths; initialize
     them so no path can ever read indeterminate values. */
  /* DH_FILE* dh_file; */
  DH_FILE* dh_file = NULL;
  /* -------------------- */
  char* p = NULL;
  int32_t n = 0;
  FILE_ENTRY* fptr;
  OSFILE fu;
  bool dynamic;
  bool internal;
  int32_t* q;
  STRING_CHUNK* str;
  int16_t i;
  /* Modified by Composer AI - 2026/06/10. See dh_file above. */
  /* double floatnum; */
  double floatnum = 0.0;
  /* -------------------- */
  u_char ftype;
  int64 n64;

  /* Get action key */

  descr = e_stack - 1;
  GetInt(descr);
  key = (int16_t)(descr->data.value);
  k_pop(1);

  /* Get file variable */

  descr = e_stack - 1;
  while (descr->type == ADDR) {
    descr = descr->data.d_addr;
  }

  if (key == FL_OPEN) /* Test if file is open */
  {
    n = (descr->type == FILE_REF);
  } else {
    if (descr->type != FILE_REF)
      k_error(sysmsg(1200));

    fvar = descr->data.fvar;
    ftype = fvar->type;

    fptr = FPtr(fvar->file_id);

    dynamic = (ftype == DYNAMIC_FILE);
    if (dynamic)
      dh_file = fvar->access.dh.dh_file;

    internal = ((process.program.flags & HDR_INTERNAL) != 0);
    switch (key) {
      case FL_VOCNAME: /* 1  VOC name of file */
        if (fvar->voc_name != NULL)
          p = fvar->voc_name;
        else
          p = "";
        goto set_string;

      case FL_PATH: /* 2  File pathname */
        p = (char*)(fptr->pathname);
        goto set_string;

      case FL_TYPE: /* 3  File type */
        /* !!FVAR_TYPES!! */
        switch (ftype) {
          case DYNAMIC_FILE:
            n = FL_TYPE_DH;
            break;
          case DIRECTORY_FILE:
            n = FL_TYPE_DIR;
            break;
          case SEQ_FILE:
            n = FL_TYPE_SEQ;
            break;
        }
        break;

      case FL_MODULUS: /* 5  Modulus of file */
        if (dynamic)
          n = fptr->params.modulus;
        break;

      case FL_MINMOD: /* 6  Minimum modulus of file */
        if (dynamic)
          n = fptr->params.min_modulus;
        break;

      case FL_GRPSIZE: /* 7  Group size of file */
        if (dynamic)
          n = dh_file->group_size / DH_GROUP_MULTIPLIER;
        break;

      case FL_LARGEREC: /* 8  Large record size */
        if (dynamic)
          n = fptr->params.big_rec_size;
        break;

      case FL_MERGE: /* 9  Merge load percentage */
        if (dynamic)
          n = fptr->params.merge_load;
        break;

      case FL_SPLIT: /* 10  Split load percentage */
        if (dynamic)
          n = fptr->params.split_load;
        break;

      case FL_LOAD: /* 11  Load percentage */
        if (dynamic) {
          n = DHLoad(fptr->params.load_bytes, dh_file->group_size,
                     fptr->params.modulus);
        }
        break;

      case FL_AK: /* 13  File has AKs? */
        if (dynamic)
          n = (dh_file->ak_map != 0);
        break;

      case FL_LINE: /* 14  Sequential file line position */
        if (ftype == SEQ_FILE) {
          n64 = fvar->access.seq.sq_file->line;
          if (n64 > INT32_MAX) {
            floatnum = (double)n64;
            goto set_float;
          }
          n = (int32_t)n64;
        }
        break;

      case FL_LOADBYTES: /* 1000  Load bytes */
        if (dynamic) {
          floatnum = (double)(fptr->params.load_bytes);
          goto set_float;
        }
        break;

      case FL_READONLY: /* 1001  Read-only? */
        n = ((fvar->flags & FV_RDONLY) != 0);
        break;

      case FL_TRIGGER: /* 1002  Trigger function name */
        if (dynamic) {
          p = dh_file->trigger_name;
          goto set_string;
        }
        break;

      case FL_PHYSBYTES: /* 1003  Physical file size */
        switch (ftype) {
          case DIRECTORY_FILE:
            floatnum = (double)dir_filesize(fvar);
            break;
          case DYNAMIC_FILE:
            floatnum = (double)dh_filesize(dh_file, PRIMARY_SUBFILE) +
                       dh_filesize(dh_file, OVERFLOW_SUBFILE);
            break;
          case SEQ_FILE:
            fu = fvar->access.seq.sq_file->fu;
            floatnum = (double)(ValidFileHandle(fu) ? filelength64(fu) : -1);
            break;
        }
        goto set_float;

      case FL_VERSION: /* 1004  File version */
        if (dynamic)
          n = dh_file->file_version;
        break;

      case FL_STATS_QUERY: /* 1005  File statistics enabled? */
        if (dynamic)
          n = (fptr->stats.reset != 0);
        break;

      case FL_SEQPOS: /* 1006  Sequential file offset */
        if (ftype == SEQ_FILE) {
          n64 = fvar->access.seq.sq_file->posn;
          if (n64 > INT32_MAX) {
            floatnum = (double)n64;
            goto set_float;
          }
          n = (int32_t)n64;
        }
        break;

      case FL_TRG_MODES: /* 1007  Trigger modes */
        if (dynamic)
          n = dh_file->trigger_modes;
        break;

      case FL_NOCASE: /* 1008  Case insensitive ids? */
        switch (ftype) {
          case DIRECTORY_FILE:
          case DYNAMIC_FILE:
            n = (fptr->flags & DHF_NOCASE) != 0;
            break;
        }
        break;

      case FL_FILENO: /* 1009  Internal file number */
        n = fvar->file_id;
        break;

      case FL_JNL_FNO: /* 1010  Journalling file number */
        break;

      case FL_AKPATH: /* 1011  AK subfile pathname */
        if (dynamic) {
          p = dh_file->akpath;
          goto set_string;
        }
        break;

      case FL_ID: /* 1012  Id of last record read */
        k_dismiss();
        k_put_string(fvar->id, fvar->id_len, e_stack);
        e_stack++;
        return;

      case FL_STATUS: /* 1013  STATUS array */
        str = get_file_status(fvar);
        k_dismiss();
        InitDescr(e_stack, STRING);
        (e_stack++)->data.str.saddr = str;
        return;

      case FL_MARK_MAPPING: /* 1014  Mark mapping enabled? */
        if (ftype == DIRECTORY_FILE)
          n = fvar->access.dir.mark_mapping;
        break;

      case FL_RECORD_COUNT: /* 1015  Approximate record count */
        if (dynamic) {
          floatnum = (double)(fptr->record_count);
          goto set_float;
        } else
          n = -1;
        /* Modified by Composer AI - 2026/06/10.
           This case fell through into FL_PRI_BYTES. That was harmless
           (FL_PRI_BYTES does nothing when not dynamic, and this point is
           only reached when not dynamic) but unintended; add the missing
           break, which provably preserves behaviour. */
        break;
        /* -------------------- */

      case FL_PRI_BYTES: /* 1016  Physical size of primary subfile */
        if (dynamic) {
          floatnum = (double)dh_filesize(dh_file, PRIMARY_SUBFILE);
          goto set_float;
        }
        break;

      case FL_OVF_BYTES: /* 1017  Physical size of overflow subfile */
        if (dynamic) {
          floatnum = (double)dh_filesize(dh_file, OVERFLOW_SUBFILE);
          goto set_float;
        }
        break;

      case FL_NO_RESIZE: /* 1018  Resizing inhibited? */
        if (dynamic)
          n = ((fptr->flags & DHF_NO_RESIZE) != 0);
        break;

      case FL_UPDATE: /* 1019  File update counter */
        n = (int32_t)(fptr->upd_ct);
        break;

      case FL_ENCRYPTED: /* 1020  File uses encryption? */
        /* Recognised but returns default zero */
        break;

      case FL_HOLDERS: /* 1021  Which sessions hold this file open? */
        /* 04 Sep 26 Windows port - PRE_RELEASE_FIXES.md 16.

           ***WHY THIS EXISTS.***  "Cannot gain exclusive access to file"
           (message 2602) named neither the file nor whoever was holding it,
           so a user whose BUILD.INDEX was refused had nothing to act on - and
           the commonest cause is a session that DIED, whose slot still holds
           the file open.  LISTU would show it and LISTU is administrator-only.
           The owner's ruling, 4 Sep 2026: display both session and file.

           ***IT NEEDS NO NEW BOOKKEEPING***, which is why it is cheap: the
           per-user file map is already maintained on every open and close -
           dh_open.c:501 and :519 increment it, dh_close.c:54 decrements it -
           and remove_user() already walks it to give a dead session's files
           back.  This asks the same table the same question.

           ***THE CALLER IS EXCLUDED.***  Reporting "you" as a holder would be
           true and useless: every caller of this has the file open, that being
           how they hold an fvar at all.  What the user needs is who ELSE.

           EMPTY IS A REAL ANSWER, not a failure.  It means nothing else holds
           the file, so the obstacle is this session's own cached reference -
           a different problem with a different remedy, and the message the
           BASIC prints says so rather than naming nobody.

           static, BECAUSE set_string IS REACHED AFTER THIS BLOCK ENDS.  p has
           to point at storage that outlives the scope, and SD runs one of
           these per process, so there is nothing to race with.              */
        {
          static char holders[256];
          USER_ENTRY* huptr;
          int16_t hu;
          int16_t hcount = 0;
          char one[64];

          holders[0] = '\0';

          StartExclusive(SHORT_CODE, 37);
          for (hu = 1; hu <= sysseg->max_users; hu++) {
            huptr = UPtr(hu);
            if ((huptr->uid == 0) || (huptr->uid == process.user_no))
              continue; /* free slot, or ourselves - see above */
            if (*UFMPtr(huptr, fvar->file_id) == 0)
              continue; /* does not hold this file open */

            snprintf(one, sizeof(one), "%s%d (%s)", (hcount ? ", " : ""),
                     (int)(huptr->uid), (char*)(huptr->username));
            /* Truncate rather than overflow: a machine with more holders than
               fit in one line still gets a usable answer, and the count of
               them is not what the user is being asked to act on. */
            if (strlen(holders) + strlen(one) >= sizeof(holders) - 4) {
              strcat(holders, ", ...");
              break;
            }
            strcat(holders, one);
            hcount++;
          }
          EndExclusive(SHORT_CODE);

          p = holders;
        }
        goto set_string;

      case FL_EXCLUSIVE: /* 10000  Set exclusive access mode */
        if (internal) {
          /* To gain exclusive access to a file it must be open only to this
             process (fptr->ref_ct = 1) and must not be open more than once
             in this process.  The latter condition only affects dynamic files
             as other types produce multiply referenced file table entries.
             We need to ensure a dynamic file is only open once so that when
             we close the file we really are going to kill off the DH_FILE
             structure. This is essential, for example, in AK creation where
             the DH_FILE structure has to change its size.                   */

          flush_dh_cache(); /* Ensure we are not stopped by a cached
                                  reference from our own process.       */
          n = FALSE;
          for (i = 0; i < 6; i++) {
            StartExclusive(FILE_TABLE_LOCK, 37);
            if ((fptr->ref_ct == 1) &&
                ((ftype != DYNAMIC_FILE) || (dh_file->open_count == 1))) {
              fptr->ref_ct = -1;
              fptr->fvar_index = fvar->index;
              n = TRUE;
            }
            EndExclusive(FILE_TABLE_LOCK);

            if (n)
              break;

            if (i == 0) /* First attempt */
            {
              /* Cannot gain exclusive access. Maybe some other process has
                 the file in its DH cache. Fire an EVT_FLUSH_CACHE event to
                 all processes to see if this clears the problem. We then
                 continue trying for a short time until either we get the
                 required access or we reach our retry count.              */
              raise_event(EVT_FLUSH_CACHE, -1);
            }

            Sleep(500); /* Pause for something to happen */
          }
        }
        break;

      case FL_FLAGS: /* 10001  File flags */
        if (dynamic && internal)
          n = (int32_t)(dh_file->flags);
        break;

      case FL_STATS_ON: /* 10002  Enable file statistics */
        if (dynamic && internal) {
          memset((char*)&(fptr->stats), 0, sizeof(struct FILESTATS));
          fptr->stats.reset = sdtime();
        }
        break;

      case FL_STATS_OFF: /* 10003  Disable file statistics */
        if (dynamic && internal)
          fptr->stats.reset = 0;
        break;

      case FL_STATS: /* 10004  Return file statistics data */
        if (dynamic && internal) {
          str = NULL;
          ts_init(&str, 5 * FILESTATS_COUNTERS);
          for (i = 0, q = (int32_t*)&(fptr->stats.reset);
               i < FILESTATS_COUNTERS; i++, q++) {
            ts_printf("%d\xfe", *q);
          }
          (void)ts_terminate();
          k_dismiss(); /* 0363 */
          InitDescr(e_stack, STRING);
          (e_stack++)->data.str.saddr = str;
          return;
        }
        break;

      case FL_SETRDONLY: /* 10005  Set read-only */
        if (internal) {
          fvar->flags |= FV_RDONLY;
          if (dynamic)
            dh_file->flags |= DHF_RDONLY;
        }
        break;

      default:
        k_error(sysmsg(1010));
    }
  }

  /* Set integer return value on stack */

set_integer:
  k_dismiss();
  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = n;
  return;

  /* Set string return value on stack */

set_string:
  k_dismiss();
  k_put_c_string(p, e_stack);
  e_stack++;
  return;

set_float:
  if (floatnum <= (double)INT32_MAX) {
    n = (int32_t)floatnum;
    goto set_integer;
  }

  k_dismiss();
  InitDescr(e_stack, FLOATNUM);
  (e_stack++)->data.float_value = floatnum;
  return;
}

/* ======================================================================
   op_sysdir()  -  Returns system directory name                          */

void op_sysdir() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |                                | System directory name       |
     |================================|=============================|
*/

  k_put_c_string((char*)(sysseg->sysdir), e_stack);
  e_stack++;
}

/* ======================================================================
   op_ospath()  -  OS file system actions                                 */

void op_ospath() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Key                           | Information                 |
     |--------------------------------|-----------------------------| 
     |  Pathname string               |                             |
     |================================|=============================|

 Key values:           Action                             Returns
     0  OS_PATHNAME    Test if valid pathname             True/False
     1  OS_FILENAME    Test if valid filename             True/False
                       or directory file record name
     2  OS_EXISTS      Test if file exists                True/False
     3  OS_UNIQUE      Make a unique file name            Name
     4  OS_FULLPATH    Return full pathname               Name
     5  OS_DELETE      Delete file                        Success/Failure
     6  OS_CWD         Get current working directory      Pathname
     7  OS_DTM         Return date/time modified          DTM value
     8  OS_FLUSH_CACHE Flush DH file cache                -
     9  OS_CD          Change working directory           Success/Failure
    10  OS_MAPPED_NAME Map a directory file name          Mapped name
    11  OS_OPEN        Check if path is an open file      True/False
    12  OS_DIR         Return content of directory        Filenames
    13  OS_MKDIR       Make a directory                   True/False
    14  OS_MKPATH      Make a directory path              True/False
* 20240225 mab add OS_CHOWN                                          *
   ospath(mvarray,os_chown)
   where mvarray = path vm user vm group. Note this requires some funny business
                   to pull off the info
    100 OS_CHOWN       Change file / dir ownership        True/False (success)

 Pathnames with lengths outside the range 1 to MAX_PATHNAME_LEN return
 0 regardless of the action key.

 */

  int32_t status = 0;
  int16_t key;
  DESCRIPTOR* descr;
  char path[MAX_PATHNAME_LEN + 1];
   int16_t path_len;
  char name[MAX_PATHNAME_LEN + 1];
  char* p;
  char* q;
  STRING_CHUNK* head;
  int file_id;
  FILE_ENTRY* fptr;
  struct stat stat_buff;
  DIR* dfu;
  struct dirent* dp;
  int32_t n;
  /* 20240225 mab OS_CHOWN */
  /* sizing for the parameter string passed is as follows:
     owner name 32 char
     group name 32 char
     path       255 char
     plus (2) vm separators = 321
  */   
  #define MAX_CHOWN_STR 321
  char chown_parm[MAX_CHOWN_STR+1];
  char * owner_name;
  char * group_name;
  char * chown_path;
  uid_t uid;
  gid_t gid;
  struct passwd *pwd;
  struct group  *grp;
  char* myVM = "\xFD";

  /* Get action key */

  descr = e_stack - 1;
  GetInt(descr);
  key = (int16_t)(descr->data.value);
  k_pop(1);

/* special code for OS_CHOWN  */
/* larger char buffer */
  if (key==OS_CHOWN){ 
    descr = e_stack - 1;
    path_len = k_get_c_string(descr, chown_parm, MAX_CHOWN_STR);
    k_dismiss();
    /* if return len < 0, we had characters remaining, error out*/
    if (path_len < 0){
      process.status = ER_LENGTH; /* Invalid length */
      goto set_status;
    }  

  }else{

  /* Get pathname */

    descr = e_stack - 1;
    path_len = k_get_c_string(descr, path, MAX_PATHNAME_LEN);
    k_dismiss();
    if (path_len < 0)
      goto set_status;
  }  

#ifdef CASE_INSENSITIVE_FILE_SYSTEM
  UpperCaseString(path);
#endif

  /* 21 Aug 26 Windows port - THE CONTAINMENT GATE FOR OSPATH.  Fifteen keys
     share one opcode and they do not all touch the filesystem, so the gate is
     applied to the ones that do and the rest are left alone:

       GATED    EXISTS UNIQUE DELETE DTM CD OPEN DIR MKDIR MKPATH, and CHOWN
                in its own case below because its path arrives inside a
                three-part parameter rather than in "path".
       NOT      PATHNAME and FILENAME validate a STRING and never look at the
                disk; CWD reports the session's own directory; FLUSH.CACHE
                takes no path; MAPPED.NAME maps a record id to a filename.
       NOT      FULLPATH, deliberately.  It resolves a name and returns it -
                the OPEN that follows is gated at open_file(), and refusing
                the arithmetic as well would break code that builds a path
                inside its own account before opening it.

     CD IS IN THE LIST BUT IS NOT WHAT HOLDS THE LINE.  A session that got its
     working directory outside the account would still be refused every open
     there, because fullpath() resolves a relative name against the working
     directory and the result is what net_path_permitted() sees.  @PATH does
     not move with OS$CD, so the root does not follow it either.

     THE REFUSAL HAS TO MATCH THE KEY'S RETURN TYPE.  Most answer with an
     integer through set_status, but UNIQUE and DIR push a STRING and jump
     straight to the exit, so refusing those with an integer would leave the
     caller reading a number as a string.                                  */

  switch (key) {
    /* Reads: they look at the disk and change nothing. */
    case OS_EXISTS:
    case OS_DTM:
    case OS_CD:
    case OS_OPEN:
      if (!net_raw_permitted(path, FALSE)) {
        process.status = ER_PERM;
        status = 0;
        goto set_status;
      }
      break;

    /* Writes.  MKDIR and MKPATH create; DELETE removes.  CHOWN is a write too
      and is handled in its own case below, because its path arrives inside a
      three-part parameter rather than in "path". */
    case OS_DELETE:
    case OS_MKDIR:
    case OS_MKPATH:
      if (!net_raw_permitted(path, TRUE)) {
        process.status = ER_PERM;
        status = 0;
        goto set_status;
      }
      break;

    /* A read that answers with a STRING, so a refusal has to answer with one
      too - see the note above. */
    case OS_DIR:
      if (!net_raw_permitted(path, FALSE)) {
        process.status = ER_PERM;
        k_put_c_string("", e_stack);
        e_stack++;
        goto exit_op_pathinfo;
      }
      break;

    /* OS_UNIQUE COUNTS AS A WRITE although it creates nothing: the only
      reason to ask for an unused name in a directory is to put something
      there, and answering would say what the directory does not contain. */
    case OS_UNIQUE:
      if (!net_raw_permitted(path, TRUE)) {
        process.status = ER_PERM;
        k_put_c_string("", e_stack);
        e_stack++;
        goto exit_op_pathinfo;
      }
      break;

    default:
      break;
  }

  switch (key) {
    case OS_PATHNAME: /* Test if valid pathname */
    {
      char* bs;

      /* 14 Aug 26 Windows port - ACCEPT NATIVE WINDOWS PATHNAMES.  This split
         on '/' alone and ran valid_name() over each component, and
         valid_name() rejects everything in df_restricted_chars - which
         contains both ':' and '\'.  So "C:\ProgramData\SD\user_accounts" was
         a single component holding two forbidden characters, and every native
         Windows path was refused.

         What that looked like: CREATE.ACCOUNT stopped with "Invalid account
         pathname" AFTER it had already created the Windows user and set its
         password, leaving the account half made and nothing saying why.
         Found 14 Aug 2026 on the first run of that verb.  It is the C twin of
         the VALID_OS_PATH trap in PROJECT_STATUS.md 6, which was fixed in the
         BASIC layer while this was missed.

         df_restricted_chars is DELIBERATELY NOT WIDENED.  op_dio3.c and
         op_dio4.c use it to map record ids onto filenames and back, which is
         a different job; changing it there would change how records are named
         on disk and would not be reversible for existing files.             */

      p = path;

      /* A drive letter is the only legitimate ':' in a pathname. */
      if (IsAlpha(p[0]) && (p[1] == ':'))
        p += 2;

      if ((*p == '/') || (*p == '\\'))
        p++;

      do {
        /* Either separator, whichever comes first. */
        q = strchr(p, '/');
        bs = strchr(p, '\\');
        if ((q == NULL) || ((bs != NULL) && (bs < q)))
          q = bs;

        if (q != NULL)
          *q = '\0';
        if (!valid_name(p))
          goto set_status;
        p = q + 1;
      } while (q != NULL);
      status = 1;
    }

      break;

    case OS_FILENAME: /* Test if valid pathname */
      status = (int32_t)valid_name(path);
      break;

    case OS_EXISTS: /* Test if file exists */
      status = !access(path, 0);
      break;

    case OS_UNIQUE: /* Make unique file name. Path variable holds directory name */
      n = (time(NULL) * 10) & 0xFFFFFFFL;
      do {
         /* converted to snprintf() -gwb 22Feb20 */
        if (snprintf(name, MAX_PATHNAME_LEN + 1,"%s\\D%07d", path, n) >= (MAX_PATHNAME_LEN +1 )) {
            /* TODO: this should be logged to a file with more details */
            k_error("Overflowed path/filename length in delete_path()!");
            goto exit_op_pathinfo;
        }
        n--;
      } while (!access(name, 0));
      sprintf(name, "D%07d", n);
      k_put_c_string(name, e_stack);
      e_stack++;
      goto exit_op_pathinfo;

    case OS_FULLPATH: /* Expand path to full OS pathname */
      fullpath(name, path);
      k_put_c_string(name, e_stack);
      e_stack++;
      goto exit_op_pathinfo;

    case OS_DELETE:
      flush_dh_cache();
      status = (int32_t)delete_path(path);
      break;

    case OS_CWD:
      (void)getcwd(name, MAX_PATHNAME_LEN);
#ifdef CASE_INSENSITIVE_FILE_SYSTEM
      UpperCaseString(name);
#endif
      k_put_c_string(name, e_stack);
      e_stack++;
      goto exit_op_pathinfo;

    case OS_DTM:
      if (stat(path, &stat_buff) == 0)
        status = stat_buff.st_mtime;
      break;

    case OS_FLUSH_CACHE:
      flush_dh_cache();
      break;

    case OS_CD:
      status = attach(path);
      break;

    case OS_MAPPED_NAME: /* Map a directory file record name */
      (void)map_t1_id(path, strlen(path), name);
      k_put_c_string(name, e_stack);
      e_stack++;
      goto exit_op_pathinfo;

    case OS_OPEN:
      fullpath(name, path);
      for (file_id = 1; file_id <= sysseg->used_files; file_id++) {
        fptr = FPtr(file_id);
        if ((fptr->ref_ct != 0) &&
            (strcmp((char*)(fptr->pathname), name) == 0)) {
          status = TRUE;
          break;
        }
      }
      break;

    case OS_DIR:
      head = NULL;
      ts_init(&head, 1024);
      if ((dfu = opendir(path)) != NULL) {
        if (path[path_len - 1] == DS)
          path[path_len - 1] = '\0';

        while ((dp = readdir(dfu)) != NULL) {
          if (strcmp(dp->d_name, ".") == 0)
            continue;
          if (strcmp(dp->d_name, "..") == 0)
            continue;
          /* converted to snprintf() -gwb 22Feb20 */
          if (snprintf(name, MAX_PATHNAME_LEN + 1,"%s%c%s", path, DS, 
                  dp->d_name) >= (MAX_PATHNAME_LEN + 1)) {
            /* TODO: this should be logged to a file with more details */
            k_error("Overflowed path/filename length in delete_path()!");
            goto exit_op_pathinfo;

          }
          if (stat(name, &stat_buff))
            continue;

          strcpy(name + 1, dp->d_name);
#ifdef CASE_INSENSITIVE_FILE_SYSTEM
          UpperCaseString(name + 1);
#endif
          if (stat_buff.st_mode & S_IFDIR) {
            name[0] = 'D';
            if (head != NULL)
              ts_copy_byte(FIELD_MARK);
            ts_copy_c_string(name);
          } else if (stat_buff.st_mode & S_IFREG) {
            name[0] = 'F';
            if (head != NULL)
              ts_copy_byte(FIELD_MARK);
            ts_copy_c_string(name);
          }
        }

        closedir(dfu);
      }
      ts_terminate();
      InitDescr(e_stack, STRING);
      (e_stack++)->data.str.saddr = head;
      goto exit_op_pathinfo;

    case OS_MKDIR:
      status = !MakeDirectory(path);
      break;

    case OS_MKPATH:
      status = make_path(path);
      break;

    case OS_CHOWN:
    /* 20240225 mab OS_CHOWN      */
    /* rem mv string in chown_parm*/
    /* OSPATH(<owener_name><vm><group_name><vm><path>,OS$CHOWN)*/
      if (Dcount(chown_parm,myVM)==3){
        owner_name = Extract(chown_parm, 0, 1, 0);
        group_name = Extract(chown_parm, 0, 2, 0);
        chown_path = Extract(chown_parm, 0, 3, 0);
        /* Modified by Composer AI - 2026/06/10.
           Extract() can return NULL on allocation failure and owner_name
           was passed to getpwnam() before any NULL test. Treat a NULL
           result as invalid parameters (handled by the pwd == NULL branch
           below). */
        /* pwd = getpwnam(owner_name); */
        if ((owner_name == NULL) || (group_name == NULL) || (chown_path == NULL)) {
          pwd = NULL; /* Handled as invalid parameters below */
        /* 21 Aug 26 Windows port - containment gate, CHOWN leg.  Its path is
           the third field of the parameter rather than "path", so the guard
           before the switch could not see it and it is tested here instead -
           after Extract() and before the path reaches chown().  Giving away
           ownership of a file is a write in the only sense that matters. */
        } else if (!net_raw_permitted(chown_path, TRUE)) {
          pwd = NULL; /* Refused - reported as invalid parameters below */
        } else {
          pwd = getpwnam(owner_name);
        }
        /* -------------------- */
        if (pwd != NULL) {
          uid = pwd->pw_uid;
          grp = getgrnam(group_name);
          if (grp != NULL) {
            gid = grp->gr_gid; 
            status = chown(chown_path, uid, gid);
            /* if we make it to the chown call and it fails, return its err number */
            if (status < 0){
               process.status = errno;
            }else{
               status = TRUE;  
            }
          }else{
            status = 0;
            process.status = ER_PARAMS;  /* Invalid parameters */
          }
        }else{
          status = 0;
          process.status = ER_PARAMS;  /* Invalid parameters */
        }
  
        if (owner_name!= NULL) free(owner_name);
        if (group_name!= NULL) free(group_name);
        if (chown_path!= NULL) free(chown_path);
      }else{
        status = 0;
        process.status = ER_PARAMS;  /* Invalid parameters */
      } 
      break;

    default:
      k_error(sysmsg(1010));
  }

set_status:

  /* Set status value on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;

exit_op_pathinfo:
  return;
}

/* ======================================================================
   op_osrename()  -  Rename a file                                        */

void op_osrename() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  New pathname                  | 1 = ok, 0 = error           |
     |--------------------------------|-----------------------------| 
     |  Old pathname                  |                             |
     |================================|=============================|

 */

  DESCRIPTOR* descr;
  char old_path[MAX_PATHNAME_LEN + 1];
  char new_path[MAX_PATHNAME_LEN + 1];
  int16_t path_len;

  process.status = 0;
  process.os_error = 0;

  /* Get new pathname */

  descr = e_stack - 1;
  path_len = k_get_c_string(descr, new_path, MAX_PATHNAME_LEN);
  if (path_len < 0) {
    process.status = ER_INVAPATH;
    goto exit_osrename;
  }
#ifdef CASE_INSENSITIVE_FILE_SYSTEM
  UpperCaseString(new_path);
#endif

  /* Get old pathname */

  descr = e_stack - 2;
  path_len = k_get_c_string(descr, old_path, MAX_PATHNAME_LEN);
  if (path_len < 0) {
    process.status = ER_INVAPATH;
    goto exit_osrename;
  }
#ifdef CASE_INSENSITIVE_FILE_SYSTEM
  UpperCaseString(old_path);
#endif

  /* 21 Aug 26 Windows port - containment gate, and OSRENAME IS A SIXTH ENTRY
     POINT THAT THE WRITTEN SPEC DID NOT LIST.  It named open_file(), ospath(),
     openseq() twice, os_permitted() and config.c; this opcode hands BOTH
     pathnames straight to rename() with no fullpath() anywhere in between, so
     without a gate here a network session could simply MOVE SDSYS/$cred
     somewhere it was allowed to read - a rename being the one filesystem
     operation that needs no access to the CONTENTS of what it moves.

     BOTH ENDS ARE TESTED.  The source, because moving a file out of a
     protected directory is a write to that directory; the target, because a
     rename INTO the account would otherwise import anything the session could
     name.  Refusing either is enough, so the cheaper source test comes first.

     ER_PERM RATHER THAN ER_FNF, so a refusal cannot be mistaken for a missing
     file - and it is set before the access() below, or a probe could still
     learn whether a file exists outside the account from which error came
     back.                                                                 */

  if (!net_raw_permitted(old_path, TRUE) || !net_raw_permitted(new_path, TRUE)) {
    process.status = ER_PERM;
    goto exit_osrename;
  }

  /* Check old path exists */

  if (access(old_path, 0)) {
    process.os_error = OSError;
    process.status = ER_FNF;
    goto exit_osrename;
  }

  if (rename(old_path, new_path)) {
    process.os_error = OSError;
    process.status = ER_FAILED;
    goto exit_osrename;
  }

exit_osrename:
  k_dismiss();
  k_dismiss();

  /* Set status value on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = (process.status == 0);

  return;
}

/* ======================================================================
   valid_name()  -  Test for valid OS file name                           */

Private bool valid_name(char* p) {
  bool status = FALSE;

  if ((strcmp(p, ".") == 0) || (strcmp(p, "..") == 0))
    return TRUE;

  if (strlen(p) > 0) {
    while (((*p == ' ') || IsGraph(*p)) &&
           (strchr(df_restricted_chars, *p) == NULL)) {
      p++;
    }
    status = (*p == '\0');
  }

  return status;
}

/* ======================================================================
   delete_path()  -  Delete DOS file/directory path                       */

bool delete_path(char* path) {
  bool status = FALSE;
  DIR* dfu;
  struct dirent* dp;
  struct stat stat_buf;
  char parent_path[MAX_PATHNAME_LEN + 1];
  int parent_len;
  char sub_path[MAX_PATHNAME_LEN + 1];

  /* Check path exists and get type information */

  if (stat(path, &stat_buf) != 0)
    goto exit_delete_path;

  if (stat_buf.st_mode & S_IFDIR) /* It's a directory */
  {
    dfu = opendir(path);
    if (dfu == NULL)
      goto exit_delete_path;

    strcpy(parent_path, path);
    parent_len = strlen(parent_path);
    if (parent_path[parent_len - 1] == DS)
      parent_path[parent_len - 1] = '\0';

    while ((dp = readdir(dfu)) != NULL) {
      if (strcmp(dp->d_name, ".") == 0)
        continue;
      if (strcmp(dp->d_name, "..") == 0)
        continue;
      /* converted to snprintf() -gwb 22Feb20 */
      if (snprintf(sub_path, MAX_PATHNAME_LEN + 1,"%s%c%s", parent_path, DS, 
            dp->d_name) >= (MAX_PATHNAME_LEN + 1)) {
            /* TODO: this should be logged to a file with more details */
            k_error("Overflowed path/filename length in delete_path()!");
            goto exit_delete_path;
      }
      if (!delete_path(sub_path))
        goto exit_delete_path;
      ;
    }
    closedir(dfu);

    if (rmdir(path) != 0)
      goto exit_delete_path;             /* Delete the directory */
  } else if (stat_buf.st_mode & S_IFREG) /* It's a file */
  {
    if (remove(path) != 0)
      goto exit_delete_path;
  }

  status = TRUE;

exit_delete_path:
  return status;
}

/* ======================================================================
   attach()  -  Change working directory and, perhaps, drive.             */

Private bool attach(char* path) {
  char cwd[MAX_PATHNAME_LEN + 1];

  (void)getcwd(cwd, MAX_PATHNAME_LEN); /* Hang on to current dir */

  if (!chdir(path))
    return TRUE; /* Success */

  (void)chdir(cwd);

  return FALSE;
}

/* ======================================================================
   fullpath()  -  Map a pathname to its absolute form                     */

bool fullpath(char* path, /* Out (can be same as input path buffer) */
              char* name) /* In */
{
  bool ok;

  char buff[PATH_MAX + 1];

  /* realpath() requires that the buffer is PATH_MAX bytes even for short
    pathnames. Use a temporary buffer and then copy the data back to the
    caller's buffer.                                                      */

  ok = (sdrealpath(name, buff) != NULL);

  strcpy(path, buff);

  return ok;
}

/* ======================================================================
   net_normalise()  -  Fold a pathname into the POSIX namespace            */

/* 21 Aug 26 Windows port - THE TWO NAMESPACES, AND WHY THIS EXISTS.
 *
 * fullpath() output lands in ONE OF TWO NAMESPACES depending on its INPUT,
 * and net_path_permitted() has to compare across them.  MEASURED 21 Aug 26
 * with a standalone probe built by MSYS2 gcc outside the repository:
 *
 *     getcwd()                        -> /c/ProgramData/SD/sdsys
 *     sdrealpath("C:\\ProgramData\\SD\\sdsys") -> C:/ProgramData/SD/sdsys
 *
 * sdrealpath() treats a leading drive letter as the root and emits "C:/...",
 * but falls back to getcwd() for a relative path and emits "/c/...".  So the
 * SAME directory has two spellings, and @PATH - which the BASIC layer sets
 * from ospath("", OS$CWD), i.e. getcwd() (LOGIN:384, CPROC:2709) - is always
 * the POSIX one.  op_kernel.c:563 already records the same fact from the
 * other side: "OS$FULLPATH returns a POSIX path whatever its comment claims".
 *
 * A PREFIX TEST ACROSS THE TWO WOULD MATCH NOTHING, so the gate would refuse
 * a session's own account directory and every network session would break on
 * its first OPEN.  Folding both sides through here is what makes the
 * comparison mean anything.
 *
 * CCP_WIN_A_TO_POSIX IS IDEMPOTENT ON POSIX INPUT - measured, same probe - so
 * this is safe to apply to a path already in the right namespace.  It folds
 * backslashes and the drive letter; IT DOES NOT FOLD CASE, which is why
 * path_within() below compares case-insensitively.
 *
 * Answers FALSE rather than a guess if the runtime cannot convert.  A wrong
 * pathname here would compare against the wrong root, and the caller treats
 * FALSE as "refuse" - exepath.c and K_WINPATH make the same choice.        */

Private bool net_normalise(char* path, /* In  */
                           char* out)  /* Out, MAX_PATHNAME_LEN + 1 bytes */
{
  if (path == NULL || *path == '\0')
    return FALSE;

  if (cygwin_conv_path(CCP_WIN_A_TO_POSIX, path, out, MAX_PATHNAME_LEN + 1) != 0)
    return FALSE;

  return (*out != '\0');
}

/* ======================================================================
   has_parent_ref()  -  Does this path still contain a ".." component?     */

/* 21 Aug 26 Windows port - THIS IS THE ESCAPE THAT WOULD HAVE MADE THE GATE
 * DECORATION, and it was found by measuring sdrealpath() rather than by
 * reading it.  Both halves below were run 21 Aug 26 against standalone probes
 * built with MSYS2 gcc - the real sdrealpath() lifted out of linuxlb.c, and
 * cygwin_conv_path() called directly.
 *
 * sdrealpath() COLLAPSES ".." ONLY WHILE EVERY COMPONENT EXISTS.  The moment
 * lstat() answers ENOENT it glues the REST OF THE INPUT ON VERBATIM
 * (linuxlb.c, "simply glue unrecognised component(s) on the end") and
 * returns.  So:
 *
 *   .../user_accounts/don/../../sdsys              -> /c/ProgramData/SD/sdsys
 *   .../don/nonexistent/../../../sdsys/$cred       -> UNCHANGED
 *
 * The second still BEGINS WITH THE ACCOUNT ROOT, so path_within() would admit
 * it - and the operating system would then resolve the ".." and open $cred.
 * One non-existent component is all it costs, and the attacker chooses it.
 *
 * AND net_normalise() DOES NOT SAVE US, which is the part that would have
 * been assumed.  cygwin_conv_path() collapses ".." when it converts FROM the
 * Windows namespace, and is a passthrough when the input is already POSIX:
 *
 *   C:/...(/don/../../sdsys/$cred)   -> /c/ProgramData/SD/sdsys/$cred
 *   /c/...(/don/nonexistent/../...)  -> UNCHANGED
 *
 * So a path can arrive here uncollapsed by either layer, and refusing it
 * outright is the only test that does not depend on which layer ran.  A
 * legitimate path never needs one: if every component existed, sdrealpath()
 * would already have removed it.                                          */

Private bool has_parent_ref(char* path) {
  char* p;

  for (p = path; *p != '\0'; p++) {
    if ((p != path) && (*(p - 1) != '/'))
      continue; /* Not at a component boundary */

    if ((p[0] == '.') && (p[1] == '.') && ((p[2] == '\0') || (p[2] == '/')))
      return TRUE;
  }

  return FALSE;
}

/* ======================================================================
   path_within()  -  Is cand at or below root?                             */

/* 21 Aug 26 Windows port - both arguments must already have been through
 * net_normalise().  The component test is the whole of the care here: a plain
 * strncasecmp() would put .../DONKEY/secret inside a root of .../DON, so the
 * byte after the prefix has to be the end of the string or a separator.
 *
 * CASE-INSENSITIVE ON PURPOSE.  Windows opens C:/PROGRAMDATA/... and
 * C:/ProgramData/... as the same file, cygwin_conv_path() preserves whichever
 * was typed, and a case-sensitive test would therefore refuse a session's own
 * files whenever the caller spelled the path differently from getcwd().  It
 * cannot be used to widen the root: a case difference can only fail to match,
 * and a failure to match is a refusal.
 *
 * ".." IS NOT HANDLED HERE.  It cannot be: see has_parent_ref() above, which
 * is why net_path_permitted() refuses an uncollapsed path before it ever
 * reaches this comparison.  A prefix test on a path still holding ".." would
 * admit exactly the escape this gate exists to stop.                       */

Private bool path_within(char* cand, char* root) {
  int root_len;

  if ((cand == NULL) || (root == NULL) || (*cand == '\0') || (*root == '\0'))
    return FALSE;

  root_len = strlen(root);

  /* Ignore a trailing separator on the root so that a root of "X/" and one
    of "X" behave the same.  "/" itself is left alone: trimming it would make
    root_len zero and match everything.                                     */

  while ((root_len > 1) && (root[root_len - 1] == '/'))
    root_len--;

  if (strncasecmp(cand, root, root_len) != 0)
    return FALSE;

  return ((cand[root_len] == '\0') || (cand[root_len] == '/'));
}

/* ======================================================================
   net_path_permitted()  -  May this session touch this pathname?          */

/* 21 Aug 26 Windows port - THE CONTAINMENT GATE.  PROJECT_STATUS.md item 4.
 *
 * WHAT IT CLOSES, measured 20 Aug 26 over a real remote API connection: a
 * PROGRAMMER-tier account opened SDSYS/$cred, wrote a record to it and read
 * the record back - so a client holding nothing but an ordinary account's
 * credential could reset any account's password.  It needed no administration
 * verb and no privilege flag; the probe wrote the file directly from BASIC,
 * which is what a PROGRAMMER account can do.  $cred was only the file that
 * was TESTED - the same reach covers everything the data tree holds, and
 * gcat is the sharp one, because it holds $LOGIN and $CPROC as object code
 * and CPROC:315 calls $LOGIN for every session.
 *
 * THE ROOT IS THE ACCOUNT THE SESSION IS STANDING IN - owner's decision,
 * 21 Aug 26, over a strict account-plus-NETDIRS root and a loose deny-SDSYS
 * one.  It needs no list and no enumeration because the account grant is
 * already checked where the session moves: LOGIN:344 admits nobody but their
 * own account and logto.authorised tests the grant at the move (CPROC:3783),
 * so the file gate inherits both by following @PATH.
 *
 * @PATH CANNOT BE FORGED FROM BASIC, checked 21 Aug 26 rather than assumed,
 * and the gate would be decoration if it could:
 *   - "@PATH = ..." does not compile.  BCOMP keeps the assignable @-variables
 *     in at.syscom.lvars (BCOMP:304-307) and PATH is not among them.
 *   - "common /$syscom/ ..." does not compile either.  A common block name
 *     may begin with "$" only if internal (get.name, BCOMP:3113), which needs
 *     $INTERNAL, which needs kernel(K$INTERNAL,-1) - and an API session is
 *     started "sd -n -q", not -internal, so internal_mode is FALSE for it.
 *
 * AND IT DEPENDS ON THE USR_ADMIN FIX IN kernel.c, which is why the two were
 * built together: an API session used to pass logto.authorised on
 * K$ADMINISTRATOR, so a root that follows the account would have followed it
 * into SDSYS and the gate would have opened the very tree it protects.
 *
 * SDSYS IS NOT SELF-CONTAINED OUT OF THE ACCOUNT, AND THAT IS WHY THE LIST
 * BELOW EXISTS.  Found 21 Aug 26 by reading sdsys/voc_template: a STOCK
 * account VOC carries EIGHT F-records pointing into SDSYS, and one of them is
 * "voc" itself, whose dictionary part is @SDSYS/voc.dic.  An account-root
 * gate with nothing else would refuse an account its own VOC dictionary.  The
 * design as written down on 21 Aug assumed the account was self-contained; it
 * is not, and this list is the correction.
 *
 * IT IS AN ALLOW-LIST, NOT A DENY-LIST, and that is the whole of its value.
 * Naming what a stock VOC needs leaves $cred, gcat, os.users, accounts and
 * cat outside by construction - the sharp ones are excluded by not being
 * mentioned, so a new sharp file in SDSYS is refused the day it appears.
 * Denying a list of known-sharp names instead would fail open on the next one
 * added.  Same direction as os_permitted()'s "missing record means no".
 *
 * THE SHARED ENTRIES ARE READ-ONLY TO A NETWORK SESSION (21 Aug 26).  Until
 * this, the gate admitted a PATH and not a MODE, so a session could WRITE
 * sd.voclib and newvoc - which shape what FUTURE accounts get - even though it
 * could not reach $cred, gcat or os.users at all.  for_write below is that
 * axis.  THE ACCOUNT AND NETDIRS STAY READ-WRITE: an account's own files are
 * its own, and a NETDIRS entry is a data directory the administrator named on
 * purpose.
 *
 * MOST OF THE ENFORCEMENT IS NOT HERE, AND THAT IS THE POINT.  An SD OPEN does
 * not declare intent - a file opened plainly can be written later - so there
 * is no mode to test at open time.  What open_file() does instead is set
 * FV_RDONLY on the file variable, which every write path in the engine already
 * honours: op_dio3.c at 133, 310 and 753, op_seqio.c at 112, 1456, 1530 and
 * 1652.  Borrowing the flag READONLY already sets means the refusals are the
 * ones users and programs already know, and it leaves no write site for this
 * change to have missed.
 *
 * PROGRAM LOADING DOES NOT COME THROUGH HERE, checked: load_object() calls
 * dio_open() on the catalogue directly (object.c:197), never open_file(), so
 * refusing gcat does not stop a network session RUNNING catalogued code.  It
 * stops it REWRITING it, which is the exposure.
 *
 * THE INTERNAL EXEMPTION IS REQUIRED, NOT A CONVENIENCE.  CRED_VERIFY:68
 * opens $cred during SCRAM, inside the session being authenticated, so
 * without it no API login could complete at all.  It cannot be forged:
 * BCOMP:2864 honours $INTERNAL only for a session that is itself internal AND
 * elevated.  All four programs on the login path - APISRVR, CRED_VERIFY,
 * LOGIN, CPROC - carry it, checked 21 Aug 26.                              */

/* The SDSYS entries a stock account VOC names.  From sdsys/voc_template:
   $MAP, dict.dict, messages, newvoc, qfile, SD.VOCLIB, syscom and voc.
   Keep this in step with that directory - if a template VOC gains an
   @SDSYS/ reference and this does not, a network session is refused it. */

Private char* net_sysdir_shared[] = {"$ipc",     "$map",    "$map.dic",
                                     "dict.dic", "messages", "newvoc",
                                     "sd.voclib", "syscom",  "voc.dic",
                                     NULL};

/* ======================================================================
   net_raw_permitted()  -  As net_path_permitted(), for an unresolved path   */

/* 21 Aug 26 Windows port - OSPATH and OSRENAME take the caller's pathname
 * and hand it to the operating system WITHOUT calling fullpath() first, so
 * there is no resolved form to gate.  This resolves one into a scratch buffer
 * for the check alone and leaves the caller's string untouched: the point is
 * to change what is REFUSED, not what a permitted call then opens, and
 * rewriting the path in place would alter behaviour for local sessions that
 * are not being gated at all.
 *
 * The connection and internal tests are repeated here so that no session
 * except a gated one pays for the fullpath() call.                        */

Private bool net_raw_permitted(char* path, bool for_write) {
  char resolved[MAX_PATHNAME_LEN + 1];

  if (connection_type != CN_SOCKET)
    return TRUE;

  if (process.program.flags & HDR_INTERNAL)
    return TRUE;

  if (path == NULL || *path == '\0')
    return FALSE;

  /* fullpath() answers FALSE only when it could not resolve at all; a
    component that does not exist yet is fine and comes back glued on, which
    net_path_permitted() then refuses if it still holds "..".             */

  if (!fullpath(resolved, path))
    return FALSE;

  return net_path_permitted(resolved, for_write);
}

bool net_path_permitted(char* path,     /* Absolute, as left by fullpath() */
                        bool for_write) /* Asking to modify, not just read? */
{
  char cand[MAX_PATHNAME_LEN + 1];
  char root[MAX_PATHNAME_LEN + 1];
  char item[MAX_PATHNAME_LEN + 1];
  DESCRIPTOR* descr;
  int i;

  /* Not a network session - nothing to contain.  This is the ONLY test that
    should ever be widened; everything below assumes it has passed.        */

  if (connection_type != CN_SOCKET)
    return TRUE;

  if (process.program.flags & HDR_INTERNAL)
    return TRUE;

  if (!net_normalise(path, cand))
    return FALSE;

  /* Before any comparison: a surviving ".." makes every prefix test below
    meaningless.  See has_parent_ref().                                    */

  if (has_parent_ref(cand))
    return FALSE;

  /* The account the session is standing in.  process.syscom is NULL before
    login has built it, and @PATH is empty until CPROC sets it, so a network
    session that reaches here that early is refused - which is the safe
    direction and is unreachable in practice, the whole login path being
    $internal and exempt above.                                            */

  if (process.syscom != NULL) {
    descr = Element(process.syscom, SYSCOM_ACCOUNT_PATH);
    if (k_get_c_string(descr, item, MAX_PATHNAME_LEN) > 0) {
      if (net_normalise(item, root) && path_within(cand, root))
        return TRUE;
    }
  }

  /* The shipped SDSYS entries a stock VOC points at.  READ ONLY - see the
    header note.  A write is not refused here as a special case; the loop is
    simply skipped, so a write falls through to NETDIRS and then to FALSE. */

  if (!for_write) {
    for (i = 0; net_sysdir_shared[i] != NULL; i++) {
      if (snprintf(item, MAX_PATHNAME_LEN + 1, "%s%c%s", sysseg->sysdir, DS,
                   net_sysdir_shared[i]) >= (MAX_PATHNAME_LEN + 1))
        continue;

      if (net_normalise(item, root) && path_within(cand, root))
        return TRUE;
    }
  }

  /* NETDIRS: site data directories outside any account.  Semicolon
    separated, because a Windows pathname contains a colon.               */

  if (sysseg->netdirs[0] != '\0') {
    char* p;
    char* q;

    p = (char*)(sysseg->netdirs);
    while (*p != '\0') {
      q = item;
      while ((*p != '\0') && (*p != ';') &&
             ((q - item) < MAX_PATHNAME_LEN))
        *(q++) = *(p++);
      *q = '\0';

      while ((*p != '\0') && (*p != ';'))
        p++; /* Discard an over-long element rather than truncating into a
                shorter directory that would then match more than it should */
      if (*p == ';')
        p++;

      if ((item[0] != '\0') && net_normalise(item, root) &&
          path_within(cand, root))
        return TRUE;
    }
  }

  return FALSE;
}

/* ======================================================================
   make_path()  -  Recursive mkdir to make directory path                 */

bool make_path(char* tgt) {
  char path[MAX_PATHNAME_LEN + 1];
  char new_path[MAX_PATHNAME_LEN + 1];
  char* p;
  char* q;
  struct stat statbuf;
  /* Modified by Composer AI - 2026/06/10.
     Use re-entrant strtok_r() instead of strtok(), which keeps hidden
     static state that breaks any caller that is itself tokenizing. */
  char* savep = NULL;
  /* -------------------- */

  strcpy(path, tgt); /* Make local copy as we will use strtok() */

  p = path;

  q = new_path;

  /* 1 Sep 26 Windows port - A DRIVE LETTER IS PART OF THE ROOT, NOT A PATH
   * COMPONENT.  This is where sdsys/"C:" came from (PRE_RELEASE 6), and it
   * needs both halves to see it:
   *
   * fullpath() emits "C:/ProgramData/SD/..." for anything drive-lettered -
   * sdrealpath() treats the drive as the root, measured 21 Aug 26 and recorded
   * at net_normalise() below - so CREATEA hands us a path whose FIRST token
   * under strtok_r(DSS) is the bare two characters "C:".
   *
   * The MSYS2 runtime does not read a bare "C:" as a drive.  It reads it as a
   * RELATIVE FILENAME, so stat() answers ENOENT and MakeDirectory() then
   * creates a directory of that name IN THE PROCESS'S CURRENT DIRECTORY,
   * written to NTFS as U+0043 U+F03A - 'C' plus the Cygwin private-use
   * mapping of a colon, which is how the runtime spells a character NTFS
   * forbids.  CREATE.ACCOUNT runs with SDSYS as its cwd, so the litter landed
   * in the data tree, once, on the first account creation after an install.
   * Measured end to end with a standalone probe built by the MSYS2 gcc: the
   * name it produces is byte-identical to the one found in sdsys.
   *
   * Carrying the drive into new_path as the root makes the first stat() ask
   * about "C:/ProgramData", which exists.  Same shape as the leading-DS case.
   *
   * A path of exactly "C:" leaves nothing for strtok_r() and returns TRUE
   * without creating anything, which is right - a drive root always exists. */

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

  /* Modified by Composer AI - 2026/06/10. See savep declaration above. */
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

/* ====================================================================== */

Private STRING_CHUNK* get_file_status(FILE_VAR* fvar) {
  STRING_CHUNK* str = NULL;
  u_char ftype;
  DH_FILE* dh_file;
  SQ_FILE* sq_file;
  int64 file_size = 0;
  int file_type_num = 0;
  bool is_seq = FALSE;
  char* path;
  int64 n64;
  struct stat statbuf;

  memset(&statbuf, 0, sizeof(statbuf));

  ftype = fvar->type;
  path = (char*)(FPtr(fvar->file_id)->pathname);

  /* !!FVAR_TYPES!! */
  switch (ftype) {
    case DYNAMIC_FILE:
      file_type_num = FL_TYPE_DH;
      dh_file = fvar->access.dh.dh_file;
      FDS_open(dh_file, PRIMARY_SUBFILE);
      fstat(dh_file->sf[PRIMARY_SUBFILE].fu, &statbuf);
      file_size = dh_filesize(dh_file, PRIMARY_SUBFILE) +
                  dh_filesize(dh_file, OVERFLOW_SUBFILE);
      break;

    case DIRECTORY_FILE:
      file_type_num = FL_TYPE_DIR;
      stat((char*)(FPtr(fvar->file_id)->pathname), &statbuf);
      file_size = dir_filesize(fvar);
      break;

    case SEQ_FILE:
      file_type_num = FL_TYPE_SEQ;
      is_seq = TRUE;
      sq_file = fvar->access.seq.sq_file;
      if (!(sq_file->flags & SQ_NOTFL))
        fstat(sq_file->fu, &statbuf);
      file_size = statbuf.st_size;
      path = sq_file->pathname;
      break;
  }

  ts_init(&str, 128);

  /* 1  File position */
  n64 = (is_seq) ? sq_file->posn : 0;
  ts_printf("%lld\xfe", n64);

  /* 2  At EOF? */
  ts_printf("%d\xfe", (is_seq) ? sq_file->posn == file_size : 0);

  /* 3  Not used */
  ts_printf("\xfe");

  /* 4  Bytes available to read */
  n64 = (is_seq) ? (file_size - sq_file->posn) : 0;
  ts_printf("%lld\xfe", n64);

  /* 5  File mode */
  ts_printf("%u\xfe", statbuf.st_mode & 0777);

  /* 6  File size */
  ts_printf("%lld\xfe", file_size);

  /*  7  Hard links */
  ts_printf("%u\xfe", statbuf.st_nlink);

  /*  8  UID of owner */
  ts_printf("%d\xfe", statbuf.st_uid);

  /*  9  GID of owner */
  ts_printf("%d\xfe", statbuf.st_gid);

  /* 10  Inode number */
  ts_printf("%u\xfe", statbuf.st_ino);

  /* 11  Device number */
  ts_printf("%u\xfe", statbuf.st_dev);

  /* 12  Not used */
  ts_printf("\xfe");

  /* 13  Time of last access */
  ts_printf("%d\xfe", statbuf.st_atime % 86400);

  /* 14  Date of last access */
  ts_printf("%d\xfe", (statbuf.st_atime / 86400) + 732);

  /* 15  Time of last modification */
  ts_printf("%d\xfe", statbuf.st_mtime % 86400);

  /* 16  Date of last modification */
  ts_printf("%d\xfe", (statbuf.st_mtime / 86400) + 732);

  /* 17 - 19 unused */
  ts_printf("\xfe\xfe\xfe");

  /* 20  Operating system file name */
  ts_printf("%s\xfe", path);

  /* 21  File type */
  ts_printf("%d", file_type_num);

  (void)ts_terminate();

  return str;
}

/* END-CODE */
