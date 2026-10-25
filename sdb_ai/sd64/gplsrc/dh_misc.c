/* DH_MISC.C
 * Miscellaneous DH file opcodes.
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
 * 25 Oct 26 Windows port - from Linux fc4030a (S.66): op_settrig() and the actions of op_fcontrol() that change a setting of the file refuse a
 *           file in the shared account with message 12519 (Linux 11514) for anyone but the administrator, a $internal program included
 *           (shared_structure_refusal).  Windows has no pub_fcontrol or FC$SYNC / FC$CRLF / FC$MINMOD, so Linux's hunk for those is not carried.
 * 17 Oct 26 Windows port - from Linux e7ea5f8 - S.65 slice 3c: op_fcontrol() and pub_fcontrol() refuse a NET_FILE (net_refuse)
 * 15 Oct 26 Windows port - from Linux e7ea5f8 - pub_fcontrol(): the public FCONTROL() with openQM's action numbers (op_fcontrol is FCONTROL.INT).
 * 15 Oct 26 Windows port - from Linux e7ea5f8 - Audit of the sequential id counter (CREATING.SEQKEY): dh_seq_key() writes only the counter's four bytes and
 *               every other writer of the primary header (FCONTROL, SETTRIG) stops short of them - DH_HEADER_SHARED_SIZE; the
 *               header lock FC_NO_RESIZE took is freed on its failure paths.
 * 14 Sep 26 Windows port - op_settrig stores the trigger name lower case
 *           (RELEASE_1.1 5 stage 3a)
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *  op_fcontrol     FCONTROL.INT  Miscellaneous file control functions (internal)
 *  pub_fcontrol    FCONTROL    The public one, with openQM's numbers (called from op_xfun)
 *  op_grpstat      GRPSTAT     Return information about file group
 *  op_settrig      SETTRIG     Set trigger function
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "dh_int.h"
#include "keys.h"

/* ======================================================================
   dh_seq_key()  -  The sequential record id counter of a hashed file     (15 Oct 26 dm, WRITE ... CREATING.SEQKEY)

   The counter is the NEXT id to give out and lives in the header of the primary subfile, so it is read and written under the
   header's group write lock and what every process sees is what is on the disk; a file with none yet, or made before there was
   one, gives 1.
     action 0  take the next id: it is returned and the counter moves on
     action 1  set the next id to n (0 puts it back to 1)
     action 2  look at the next id without taking it
   Returns the id (the one the counter held, before it moved on), or -1 when the header cannot be read or written, -2 when the
   counter has no further id to give.

   15 Oct 26 dm - audit: ONLY THE FOUR BYTES OF THE COUNTER ARE WRITTEN, at their own offset, and no other writer of the header
   writes them (DH_HEADER_SHARED_SIZE).  The header lock above serialises the processes that take ids; it is NOT taken by
   dh_flush_header(), SETTRIG, the AK subfile code or FCONTROL, which all rewrite the header from a copy they read a moment
   before.  The whole header written from here put whatever those had just changed back to its old value, and a whole header
   written by them put the counter back to its old value - the next WRITE was then given an id that had been used.        */

int32_t dh_seq_key(DH_FILE* dh_file, int action, int32_t n) {
  DH_HEADER header;
  int16_t header_lock;
  int32_t next;
  int32_t new_value;

  header_lock = GetGroupWriteLock(dh_file, 0);
  if (!dh_read_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header, DH_HEADER_SIZE)) {
    FreeGroupWriteLock(header_lock);
    return -1;
  }

  next = (header.seq_key > 0) ? header.seq_key : 1;
  if ((action == 0) && (next == 0x7FFFFFFF)) {
    FreeGroupWriteLock(header_lock);
    return -2;
  }

  if (action != 2) {
    new_value = (action == 0) ? next + 1 : ((n > 0) ? n : 0);

    /* dh_read_group() has opened the subfile if it was not open */
    if (!write_at(dh_file->sf[PRIMARY_SUBFILE].fu, (int64)offsetof(DH_HEADER, seq_key), (char*)&new_value, (int)sizeof(new_value)))
      next = -1;
  }
  FreeGroupWriteLock(header_lock);
  return next;
}

/* ======================================================================
   op_fcontrol()  -  Miscellaneous file control functions                 */

void op_fcontrol() {
  /* Stack:

      |================================|=============================|
      |            BEFORE              |           AFTER             |
      |================================|=============================|
  top |  Qualifier                     | Returned data               |
      |--------------------------------|-----------------------------|
      |  Action key                    |                             |
      |--------------------------------|-----------------------------|
      |  File variable                 |                             |
      |================================|=============================|

  This function is restricted for internal use only and therefore assumes
  that the caller knows what they are doing. There is minimal validation.

  Key   Action                                      Qualifier
    1   Set journalling file no in file header      File number
    2   Disable journalling for an open file
    3   Set akpath element of file header           Path name
    4   Set file as non-transactional
    5   Force resize
    6   Set/clear DHF_NO_RESIZE flag                New setting
 */

  DESCRIPTOR* descr;
  int action;
  FILE_VAR* fvar;
  DESCRIPTOR result;
  DH_FILE* dh_file;
  DH_HEADER header;
  int32_t modulus;
  int32_t load;
  FILE_ENTRY* fptr;
  int16_t header_lock;
  /* u_char ftype; variable assigned but not used */
  /* bool dynamic; variable assigned but not used */

  process.status = 0;

  InitDescr(&result, INTEGER); /* Assume integer return value by default */
  result.data.value = 0;

  /* Get action key */

  descr = e_stack - 2;
  GetInt(descr);
  action = descr->data.value;

  /* Get file variable */

  descr = e_stack - 3;
  k_get_file(descr);
  fvar = descr->data.fvar;
  if (fvar->type == NET_FILE) /* 17 Oct 26 S.65: a remote file has no entry in the file table and no access.dh */
    net_refuse(fvar, "FCONTROL");
  fptr = FPtr(fvar->file_id);
  /* ftype = fvar->type; variable assigned but not used */
  /* dynamic = (ftype == DYNAMIC_FILE); variable assigned but never used */
  dh_file = fvar->access.dh.dh_file; /* May be irrelevant */

  /* Resolve value of qualifier */

  descr = e_stack - 1;
  k_get_value(descr);

  /* 18 Oct 26 S.66: every action that CHANGES a setting of the file is a structure change, and for a file in the shared account it is
     SDSYS's alone ($internal is not exempt).  Refused before anything is changed.  FC_SET_SEQ_KEY and FC_GET_SEQ_KEY are record level. */
  switch (action) {
    case FC_SET_JNL_FNO:
    case FC_KILL_JNL:
    case FC_SET_AKPATH:
    case FC_NON_TXN:
    case FC_SPLIT_MERGE:
    case FC_NO_RESIZE:
      if (shared_structure_refusal(fvar) != EDIT_NONE)
        k_error(sysmsg(edit_refused_message(EDIT_SHARED_STRUCT)));
      break;
  }

  switch (action) {
    case FC_SET_JNL_FNO: /* Set jnl_fno field of file header */
      GetInt(descr);

      /* Read file header - We have exclusive access so needn't lock */

      if (!dh_read_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header,
                         DH_HEADER_SIZE)) {
        process.status = ER_IOE;
        goto exit_op_fcontrol;
      }

      header.jnl_fno = descr->data.value;
      dh_file->jnl_fno = descr->data.value;

      if (!dh_write_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header,
                          DH_HEADER_SHARED_SIZE)) {
        process.status = ER_IOE;
        goto exit_op_fcontrol;
      }

      result.data.value = 1;
      break;

    case FC_KILL_JNL:
      dh_file->jnl_fno = 0; /* Kill journalling */
      break;

    case FC_SET_AKPATH:
      /* Read file header - We have exclusive access so needn't lock */

      if (!dh_read_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header,
                         DH_HEADER_SIZE)) {
        process.status = ER_IOE;
        goto exit_op_fcontrol;
      }

      k_get_c_string(descr, header.akpath, MAX_PATHNAME_LEN);
#ifdef CASE_INSENSITIVE_FILE_SYSTEM
      UpperCaseString(header.akpath);
#endif

      if (header.akpath[0] == '\0')
        dh_file->akpath = NULL;
      else {
        dh_file->akpath = (char*)k_alloc(107, strlen(header.akpath) + 1);
        strcpy(dh_file->akpath, header.akpath);
      }

      if (!dh_write_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header,
                          DH_HEADER_SHARED_SIZE)) {
        process.status = ER_IOE;
        goto exit_op_fcontrol;
      }
      break;

    case FC_SET_SEQ_KEY: /* Set the next id WRITE ... CREATING.SEQKEY gives out (a hashed file only; 1 if it was set) */
      if (fvar->type == DYNAMIC_FILE) {
        GetInt(descr);
        if (dh_seq_key(dh_file, 1, descr->data.value) >= 0)
          result.data.value = 1;
        else
          process.status = ER_IOE;
      }
      break;

    case FC_GET_SEQ_KEY: /* Take the next id, as CREATING.SEQKEY does; a null string for a file that is not a hashed file */
      if (fvar->type == DYNAMIC_FILE) {
        result.data.value = dh_seq_key(dh_file, 0, 0);
        if (result.data.value < 0) {
          process.status = ER_IOE;
          result.data.value = 0;
        }
      } else {
        InitDescr(&result, STRING);
        result.data.str.saddr = NULL;
      }
      break;

    case FC_NON_TXN: /* Set file as non-transactional */
      fvar->flags |= FV_NON_TXN;
      break;

    case FC_SPLIT_MERGE: /* Force split/merge */
      if (fvar->type == DYNAMIC_FILE) {
        modulus = fptr->params.modulus;
        load = DHLoad(fptr->params.load_bytes, dh_file->group_size, modulus);

        if ((load > fptr->params.split_load) ||
            (modulus < fptr->params.min_modulus)) {
          dh_split(dh_file);
          result.data.value = TRUE;
        } else if ((load < fptr->params.merge_load) &&
                   (modulus > fptr->params.min_modulus)) {
          /* Looks like we need to merge but check won't immediately split */
          load =
              DHLoad(fptr->params.load_bytes, dh_file->group_size, modulus - 1);
          if (load < fptr->params.split_load) /* Would not immediately split */
          {
            dh_merge(dh_file);
            result.data.value = TRUE;
          }
        }
      }
      break;

    case FC_NO_RESIZE: /* Set/clear DHF_NO_RESIZE flag */
      if (fvar->type == DYNAMIC_FILE) {
        GetInt(descr);
        header_lock = GetGroupWriteLock(dh_file, 0);

        /* 15 Oct 26 dm - the header lock is given back on the failure paths too: it is the lock dh_seq_key() takes, and
           a leaked one made every WRITE ... CREATING.SEQKEY to the file wait for as long as this process lived. */
        if (!dh_read_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header,
                           DH_HEADER_SIZE)) {
          FreeGroupWriteLock(header_lock);
          process.status = ER_IOE;
          goto exit_op_fcontrol;
        }

        if (descr->data.value) {
          fptr->flags |= DHF_NO_RESIZE;
          header.flags |= DHF_NO_RESIZE;
        } else {
          fptr->flags &= ~DHF_NO_RESIZE;
          header.flags &= ~DHF_NO_RESIZE;
        }

        if (!dh_write_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header,
                            DH_HEADER_SHARED_SIZE)) {
          FreeGroupWriteLock(header_lock);
          process.status = ER_IOE;
          goto exit_op_fcontrol;
        }

        FreeGroupWriteLock(header_lock);
      }
      break;
  }

exit_op_fcontrol:
  k_dismiss();
  k_dismiss();
  k_dismiss();

  *(e_stack++) = result; /* Move result descriptor to stack */
}

/* ======================================================================
   pub_fcontrol()  -  The public FCONTROL(fvar, action {, qualifier})     (15 Oct 26 dm)

   The openQM 4 function, with its numbers (FC$ in syscom/keys.h); the internal function of the same job is FCONTROL.INT
   (op_fcontrol above) and has other numbers.  Called from op_xfun() with the function number already taken off; the
   compiler loads 0 for a qualifier left out.

      Stack:   top  qualifier
                    action
                    file variable                                   -> the result

      1 FC$SYNC     forced writes     \  SD has neither: the program is stopped with a message, never answered as if it
      4 FC$CRLF     line terminators  /  had worked
      2 FC$SET.SEQ.KEY  qualifier n   sets the next id of WRITE ... CREATING.SEQKEY (a hashed file); 1 if done
      3 FC$GET.SEQ.KEY                takes that id and moves the counter on; a null string if the file is not hashed
      5 field access                  always 1 (SD has no field level encryption)
      6 FC$VALID.ID     qualifier id  1 if the id could be written to this file, else 0
      7 FC$MINMOD       qualifier n   sets the minimum modulus of a hashed file; 1 if done

   The three that change the file (2, 3, 7) are refused on a file opened read only, with STATUS() ER_RDONLY and the
   result 0 (null for 3).  STATUS() is ER_NDYN for a file that is not hashed, ER_ARGS for a number below 1, ER_IOE if the
   header could not be written.                                                                                     */

void pub_fcontrol() {
  DESCRIPTOR* descr;
  int action;
  FILE_VAR* fvar;
  DESCRIPTOR result;
  DH_FILE* dh_file;
  int32_t n;
  char id[MAX_ID_LEN + 1];
  char mapped[(3 * MAX_ID_LEN) + 1];
  int id_len;
  char* p;

  process.status = 0;

  InitDescr(&result, INTEGER);
  result.data.value = 0;

  descr = e_stack - 2;
  GetInt(descr);
  action = descr->data.value;

  descr = e_stack - 3;
  k_get_file(descr);
  fvar = descr->data.fvar;
  dh_file = fvar->access.dh.dh_file; /* only used for a hashed file */

  descr = e_stack - 1;
  k_get_value(descr);

  switch (action) {
    case 1: /* FC$SYNC */
    case 4: /* FC$CRLF */
      k_error(sysmsg(12359)); /* does not return */
      break;

    case 2: /* FC$SET.SEQ.KEY */
    case 7: /* FC$MINMOD */
      if (fvar->type != DYNAMIC_FILE) {
        process.status = ER_NDYN;
        break;
      }
      if (fvar->flags & FV_RDONLY) {
        process.status = ER_RDONLY;
        log_permissions_error(fvar);
        break;
      }
      GetInt(descr);
      n = descr->data.value;
      if (n < 1) {
        process.status = ER_ARGS;
        break;
      }
      if (action == 2) {
        if (dh_seq_key(dh_file, 1, n) >= 0)
          result.data.value = 1;
        else
          process.status = ER_IOE;
      } else {
        dh_configure(dh_file, n, -1, -1, -1);
        result.data.value = 1;
      }
      break;

    case 3: /* FC$GET.SEQ.KEY */
      InitDescr(&result, STRING);
      result.data.str.saddr = NULL;
      if (fvar->type != DYNAMIC_FILE)
        break; /* a null string, as the manual says */
      if (fvar->flags & FV_RDONLY) {
        process.status = ER_RDONLY;
        log_permissions_error(fvar);
        break;
      }
      n = dh_seq_key(dh_file, 0, 0);
      if (n < 0) {
        process.status = ER_IOE;
        break;
      }
      InitDescr(&result, INTEGER);
      result.data.value = n;
      break;

    case 5: /* the field access test: there is no field level encryption, so always true */
      result.data.value = 1;
      break;

    case 6: /* FC$VALID.ID */
      id_len = k_get_c_string(descr, id, MAX_ID_LEN);
      if ((id_len > 0) && (id_len <= sysseg->maxidlen)) {
        result.data.value = 1;
        for (p = id; p < id + id_len; p++) {
          if ((*p == '\0') || IsMark(*p)) {
            result.data.value = 0;
            break;
          }
        }
        if (result.data.value && (fvar->type == DIRECTORY_FILE) && !map_t1_id(id, (int16_t)id_len, mapped))
          result.data.value = 0;
      }
      break;

    default:
      k_error(sysmsg(12360));
  }

  k_dismiss();
  k_dismiss();
  k_dismiss();

  *(e_stack++) = result;
}

/* ======================================================================
   op_grpstat()  -  Return information about a file group                 */

void op_grpstat() {
  /* Stack:

      |================================|=============================|
      |            BEFORE              |           AFTER             |
      |================================|=============================|
  top |  Group number                  | Information                 |
      |--------------------------------|-----------------------------|
      |  ADDR to file variable         |                             |
      |================================|=============================|

  Returns:
     F1    Bytes used (excluding large records but including group headers)
     F2    Group buffer chain length
     F3    Record count (including large records)
     F4    Large record count
  */

  DESCRIPTOR* descr;
  FILE_VAR* fvar;
  DH_FILE* dh_file;
  FILE_ENTRY* fptr;
  int32_t group;
  int16_t group_bytes;
  int16_t used_bytes;
  char result[50] = "";
  int16_t lock_slot = 0;
  int16_t subfile;
  int32_t grp;
  int16_t rec_offset;
  DH_RECORD* rec_ptr;
  int32_t byte_count = 0;
  int16_t buffer_count = 0;
  int16_t record_count = 0;
  int32_t large_record_count = 0;

  /* Get group number */

  descr = e_stack - 1;
  GetInt(descr);
  group = descr->data.value;

  /* Get file variable */

  descr = e_stack - 2;
  k_get_file(descr);
  fvar = descr->data.fvar;
  if (fvar->type != DYNAMIC_FILE)
    goto exit_op_grpstat;

  dh_file = fvar->access.dh.dh_file;

  fptr = FPtr(dh_file->file_id);
  while (fptr->file_lock < 0)
    Sleep(1000); /* Clearfile in progress */

  /* Lock group */

  StartExclusive(FILE_TABLE_LOCK, 39);
  lock_slot = GetGroupReadLock(dh_file, group);
  EndExclusive(FILE_TABLE_LOCK);

  group_bytes = (int16_t)(dh_file->group_size);

  subfile = PRIMARY_SUBFILE;
  grp = group;
  do {
    /* Read group */

    if (!dh_read_group(dh_file, subfile, grp, dh_buffer, group_bytes)) {
      goto exit_op_grpstat;
    }

    /* Scan group buffer for records */

    used_bytes = ((DH_BLOCK*)dh_buffer)->used_bytes;
    if ((used_bytes == 0) || (used_bytes > group_bytes)) {
      goto exit_op_grpstat;
    }

    buffer_count++;
    byte_count += used_bytes;

    rec_offset = offsetof(DH_BLOCK, record);
    while (rec_offset < used_bytes) {
      rec_ptr = (DH_RECORD*)(dh_buffer + rec_offset);
      record_count++;
      if (rec_ptr->flags & DH_BIG_REC)
        large_record_count++;

      rec_offset += rec_ptr->next;
    }

    /* Move to next group buffer */

    subfile = OVERFLOW_SUBFILE;
    grp = GetFwdLink(dh_file, ((DH_BLOCK*)dh_buffer)->next);
  } while (grp != 0);

  /* Construct return data */

  sprintf(result, "%d%c%d%c%d%c%d", byte_count, FIELD_MARK, (int)buffer_count,
          FIELD_MARK, (int)record_count, FIELD_MARK, large_record_count);

exit_op_grpstat:
  if (lock_slot != 0)
    FreeGroupReadLock(lock_slot);

  k_pop(1);
  k_dismiss();

  /* Set string return value on stack */

  k_put_c_string(result, e_stack++);
}

/* ======================================================================
   op_settrig()  - Set trigger name                                       */

void op_settrig() {
  /* Stack:

      |================================|=============================|
      |            BEFORE              |           AFTER             |
      |================================|=============================|
  top |  Mode flags                    |                             |
      |--------------------------------|-----------------------------|
      |  Function name                 |                             |
      |--------------------------------|-----------------------------|
      |  File variable                 |                             |
      |================================|=============================|
 */

  DESCRIPTOR* descr;
  char call_name[MAX_TRIGGER_NAME_LEN + 1];
  int16_t name_len;
  FILE_VAR* fvar;
  DH_FILE* dh_file;
  DH_HEADER header;
  int modes;

  process.status = 0;

  /* Get mode flags */

  descr = e_stack - 1;
  GetNum(descr);
  modes = descr->data.value;

  /* Get function name */

  descr = e_stack - 2;
  name_len = k_get_c_string(descr, call_name, MAX_TRIGGER_NAME_LEN);
  /* 14 Sep 26 - stored lower case, the canonical case of program names
     (RELEASE_1.1 5 stage 3a); valid_call_name() now refuses upper case.   */
  if (name_len > 0)
    LowerCaseString(call_name);
  if ((name_len < 0) || (name_len && !valid_call_name(call_name))) {
    process.status = ER_IID;
    goto exit_op_settrig;
  }

  /* Get file variable */

  descr = e_stack - 3;
  k_get_file(descr);
  fvar = descr->data.fvar;

  /* 18 Oct 26 S.66: a trigger is part of the STRUCTURE of a file; in the shared account it is SDSYS's alone ($internal is not exempt).
     Before anything is read or written. */
  if (shared_structure_refusal(fvar) != EDIT_NONE)
    k_error(sysmsg(edit_refused_message(EDIT_SHARED_STRUCT)));

  /* 18 Oct 26 Windows port - from Linux f0af637 (16 Oct 26, QM4 Fixes item 177), the hunk the first carry lost: a directory file has
     no header to put the trigger in, so it goes into its %header% file.  Without it SET.TRIGGER on a directory file said ER_NDYN. */

  if (fvar->type == DIRECTORY_FILE) {
    process.status = dir_set_trigger(fvar, call_name, modes);
    goto exit_op_settrig;
  }

  if (fvar->type != DYNAMIC_FILE) {
    process.status = ER_NDYN;
    goto exit_op_settrig;
  }

  dh_file = fvar->access.dh.dh_file;

  /* Read file header - We have exclusive access so needn't lock */

  if (!dh_read_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header,
                     DH_HEADER_SIZE)) {
    process.status = ER_IOE;
    goto exit_op_settrig;
  }

  memset(header.trigger_name, 0,
         MAX_TRIGGER_NAME_LEN); /* Wipe out completely */
  strcpy(header.trigger_name, call_name);
  header.trigger_modes = modes;

  if (!dh_write_group(dh_file, PRIMARY_SUBFILE, 0, (char*)&header,
                      DH_HEADER_SHARED_SIZE)) {
    process.status = ER_IOE;
    goto exit_op_settrig;
  }

exit_op_settrig:
  k_dismiss();
  k_dismiss();
  k_dismiss();
}

/* END-CODE */
