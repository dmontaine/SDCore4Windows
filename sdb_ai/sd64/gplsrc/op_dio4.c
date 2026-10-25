/* OP_DIO4.C
 * Disk i/o opcodes (Select actions for DH and directory files)
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
 * 18 Oct 26 Windows port - from Linux fa146d9 (16 Oct 26): dir_select() closes the oldest cached file and tries again when opendir() fails at the open-file limit (QM4 Fixes 279).
 * 18 Oct 26 Windows port - from Linux ff49d57 (15 Oct 26): $MODE SELECTV default select list variable (openQM item 85): readnext() takes P_DEF_SELLIST, an unassigned
 * 17 Oct 26 Windows port - from Linux e7ea5f8 - S.65 slice 3c: op_select() and op_selectv() refuse a NET_FILE (net_refuse) before the target list is touched
 * 16 Oct 26 Windows port - from Linux e7ea5f8 - dir_select() closes the oldest cached file and tries again when opendir() fails at the open-file limit (QM4 Fixes 279).
 * 15 Oct 26 Windows port - from Linux e7ea5f8 - $MODE SELECTV default select list variable (openQM item 85): readnext() takes P_DEF_SELLIST, an unassigned
 *               default variable being an empty list
 * 18 Oct 26 Windows port - from Linux c608b9f (15 Oct 26): $MODE PICK.SELECT (QM4 gaps Q-16): op_selectv() moves an active list 0 to its target;
 *               transfer_list0() is the body of op_selecte(), which both now call
 * 02 Sep 26 Windows port - dir_select tests the escape character before
 *                      consuming it (PRE_RELEASE_FIXES.md 128, UPSTREAM 35)
 * rev 0.9-3 mab in dir_select if we end up with an empty name, don't add to list
 * rev 0.9.0 Jan 25 mab fix period or tilde character mapping (%t / %d) 
 *                      to match either case
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 *  START-DESCRIPTION:
 *
 *  op_clearall        CLEARALL
 *  op_clrselect       CLEARSEL
 *  op_dellist         DELLIST
 *  op_formlist        FORMLIST
 *  op_getlist         GETLIST
 *  op_readlist        READLIST
 *  op_readnext        READNEXT
 *  op_savelist        SAVELIST
 *  op_select          SELECT
 *  op_selecte         SELECTE
 *  op_selectv         SELECTV
 *  op_sselect         SSELECT
 *  op_slctinfo        SLCTINFO
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "keys.h"
#include "syscom.h"
#include "dh_int.h"
#include "options.h"

void init_record_cache(void);

void op_formlist(void);
void op_rmvf(void);
void op_stor(void);
void op_dcount(void);

Private void readnext(int16_t mode);
Private bool dir_select(FILE_VAR* fvar, int16_t list_no);
Private void transfer_list0(DESCRIPTOR* tgt_descr);
Private void store_select_list(int16_t list_no, STRING_CHUNK* head, int32_t record_count);
Private int net_select_with_flags(FILE_VAR* fvar, u_int16_t op_flags, STRING_CHUNK** ids, int32_t* count);

/* ====================================================================== */

bool dio_init() {
  int16_t i;

  for (i = 0; i <= HIGH_SELECT; i++) {
    select_ftype[i] = SEL_NONE;
    select_file[i] = NULL;
    select_group[i] = 0;
  }

  init_record_cache();

  if (!dh_init())
    return FALSE;

  return TRUE;
}

/* ======================================================================
   op_clearall()  -  Clear all user select lists                          */

void op_clearall() {
  int16_t i;

  for (i = 0; i <= HIGH_USER_SELECT; i++) {
    clear_select(i);
  }
}

/* ======================================================================
   op_clrselect()  -  Clear select list                                   */

void op_clrselect() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         |                             |
     |=============================|=============================|
 */

  DESCRIPTOR* list_descr;
  int16_t list_no; /* Select list number */

  /* Get the select list number */

  list_descr = e_stack - 1;
  GetInt(list_descr);
  list_no = (int16_t)(list_descr->data.value);
  k_pop(1);

  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  clear_select(list_no);
}

/* ======================================================================
   op_dellist()  -  DELETELIST statement                                  */

void op_dellist() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  List name                  |                             |
     |=============================|=============================|

 */

  k_recurse(pcode_dellist, 1); /* Execute recursive code */
}

/* ======================================================================
   op_getlist()  -  GETLIST statement                                     */

void op_getlist() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         | Status 0=ok, >0 = ELSE      |
     |-----------------------------|-----------------------------| 
     |  List name                  |                             |
     |=============================|=============================|

 */

  DESCRIPTOR* descr;
  int16_t list_no;

  /* Validate select list number, leaving on e-stack */

  descr = e_stack - 1;
  GetInt(descr);
  list_no = (int16_t)(descr->data.value);

  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  k_recurse(pcode_getlist, 2); /* Execute recursive code */
}

/* ======================================================================
   op_formlst()  -  Form select list from dynamic array                   */

void op_formlist() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         |                             |
     |-----------------------------|-----------------------------| 
     |  Source list                |                             |
     |=============================|=============================|

 */

  DESCRIPTOR* descr;
  int16_t list_no;

  /* Validate select list number, leaving on e-stack */

  descr = e_stack - 1;
  GetInt(descr);
  list_no = (int16_t)(descr->data.value);
  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  end_select(list_no); /* Terminate any partial select */

  k_recurse(pcode_formlst, 2);
}

/* ======================================================================
   op_readlist()  -  Read select list to dynamic array                    */

void op_readlist() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         | Status 0=ok, >0 = ELSE      |
     |-----------------------------|-----------------------------| 
     |  ADDR to target             |                             |
     |=============================|=============================|

 */

  DESCRIPTOR* descr;
  int16_t list_no;
  DESCRIPTOR status_descr;

  /* Validate select list number, leaving on e-stack */

  descr = e_stack - 1;
  GetInt(descr);
  list_no = (int16_t)(descr->data.value);

  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  complete_select(list_no); /* Complete any partial select */

  /* Push ADDR to status-descr onto e-stack */

  InitDescr(&status_descr, UNASSIGNED);
  InitDescr(e_stack, ADDR);
  (e_stack++)->data.d_addr = &status_descr;

  k_recurse(pcode_readlst, 3); /* Execute recursive code */

  /* Set status code on stack */

  *(e_stack++) = status_descr;
}

/* ======================================================================
   op_rdnxpos()   Standard READNEXT, returning composite exploded list
   op_readnext()  Standard READNEXT, returning id only in exploded list
   op_rdnxexp()   Extended READNEXT, returning positional data            */

void op_rdnxpos() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         | Status 0=ok, >0 = ELSE      |
     |                             |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  ADDR to id target          |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to READNEXT.
 */

  readnext(0);
}

void op_readnext() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         | Status 0=ok, >0 = ELSE      |
     |                             |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  ADDR to id target          |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to READNEXT.
 */

  readnext(1);
}

void op_rdnxexp() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number or      | Status 0=ok, >0 = ELSE      |
     |  Pick style list variable   |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  ADDR to subvalue target    |                             |
     |-----------------------------|-----------------------------| 
     |  ADDR to value target       |                             |
     |-----------------------------|-----------------------------| 
     |  ADDR to id target          |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to READNEXT.
 */

  readnext(2);
}

void op_rdnxint() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number or      | Status 0=ok, >0 = ELSE      |
     |  Pick style list variable   |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  ADDR to additional target  |                             |
     |-----------------------------|-----------------------------| 
     |  ADDR to subvalue target    |                             |
     |-----------------------------|-----------------------------| 
     |  ADDR to value target       |                             |
     |-----------------------------|-----------------------------| 
     |  ADDR to id target          |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to READNEXT.
 */

  readnext(3);
}

Private void readnext(int16_t mode)
/* 0 = Standard READNEXT, returns composite exploded data */
/* 1 = Standard READNEXT, returns id only */
/* 2 = Extended READNEXT, returns id and  positional data */
/* 3 = Extended READNEXT, Mode 2 + internal data */
{
  DESCRIPTOR* descr;
  DESCRIPTOR* d;
  DESCRIPTOR* select_list_descr;
  DESCRIPTOR* select_count_descr;
  DESCRIPTOR value_descr;
  DESCRIPTOR subvalue_descr;
  DESCRIPTOR int_descr;
  int16_t list_no;
  int16_t status;
  u_int16_t op_flags;
  int32_t count;
  char* vpos;
  int16_t id_bytes;
  int16_t bytes_remaining;
  int value = 0;
  int subvalue = 0;
  STRING_CHUNK* str;
  int saved_status;
  int16_t errnum;

  op_flags = process.op_flags;
  process.op_flags = 0;

  /* Save copies of positional descriptors for exploded list format. We
    need to do this so that these descriptors are not in the way when
    we store the id string by calling op_stor().
    The code below removes the two positional descriptors, leaving us with

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number or      | Status 0=ok, >0 = ELSE      |
     |  Pick style list variable   |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  ADDR to id target          |                             |
     |=============================|=============================|
 */

  switch (mode) {
    case 2:
      subvalue_descr = *(e_stack - 2);
      value_descr = *(e_stack - 3);
      *(e_stack - 3) = *(e_stack - 1);
      k_pop(2);
      break;

    case 3:
      int_descr = *(e_stack - 2);
      subvalue_descr = *(e_stack - 3);
      value_descr = *(e_stack - 4);
      *(e_stack - 4) = *(e_stack - 1);
      k_pop(3);
      break;
  }

  /* Get list number or Pick style list variable */

  descr = e_stack - 1;
  for (d = descr; d->type == ADDR; d = d->data.d_addr) {
  }

  /* 15 Oct 26 dm - $MODE SELECTV (openQM item 85): the list is the program's default select list variable. Until a
     SELECT has given it a list there is no list, which is a list that is not active: take the ELSE clause. */
  if ((op_flags & P_DEF_SELLIST) && d->type == UNASSIGNED) {
    k_pop(1); /* The unassigned variable */
    status = 1;
    goto exit_readnext_null;
  }

  if (d->type == SELLIST) {
    saved_status = process.status;

    /* Remove next field from the string */
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = 1;
    op_rmvf();
    status = (process.status != 0);
    process.status = saved_status;
  } else {
    GetInt(descr);
    list_no = (int16_t)(descr->data.value);
    k_pop(1);
    if (InvalidSelectListNo(list_no))
      k_select_range_error();

    /* Find SELECT.COUNT(LIST.NO) in SYSCOM */

    select_count_descr = SelectCount(list_no);
    GetInt(select_count_descr);

    /* Find SELECT.LIST(LIST.NO) in SYSCOM */

    select_list_descr = SelectList(list_no);
    if (select_list_descr->type != STRING)
      k_get_string(select_list_descr);

    count = select_count_descr->data.value;

    if (count < 0) /* List is not active */
    {
      status = 1; /* Take ELSE clause */
      goto exit_readnext_null;
    }

    if (count == 0) /* List is empty */
    {
      switch (select_ftype[list_no]) {
        case SEL_DH:
          if (dh_select_group(((DH_FILE*)select_file[list_no]), list_no))
            goto list_extended;
          break;
      }

      /* Nothing added to list. Release memory from previous list */

      k_release(select_list_descr);
      InitDescr(select_list_descr, STRING);
      select_list_descr->data.str.saddr = NULL;
      select_count_descr->data.value = -1;
      status = 1; /* Take ELSE clause */
      goto exit_readnext_null;
    }

  list_extended:

    /* List is active */

    (select_count_descr->data.value)--;

    InitDescr(e_stack, ADDR);
    (e_stack++)->data.d_addr = select_list_descr;

    /* Extract item from list */

    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = 1;
    op_rmvf();
    status = 0; /* Take THEN clause */
  }

  if (mode) {
    descr = e_stack - 1;
    str = descr->data.str.saddr;

    if (str != NULL) /* 0162 */
    {
      /* The top item on the stack is a string. If we are going to do
        anything clever with it, we need it to be contiguous.         */

      if (str->next != NULL) {
        errnum = 0;
        str = s_make_contiguous(str, &errnum);
        descr->data.str.saddr = str;

        if (errnum) {
          process.status = errnum;
          status = -errnum;
          goto exit_readnext;
        }
      }

      vpos = (char*)memchr(str->data, VALUE_MARK, str->bytes);
      if (vpos) /* Looks like an exploded list */
      {
        /* We need to chop off positional data. Rather than copying the
          id string in a truncated form, we simply adjust the byte count
          so that the positional stuff is never seen.                   */

        id_bytes = vpos - str->data;
        bytes_remaining = str->bytes - (id_bytes + 1);
        str->bytes = id_bytes;
        str->string_len = id_bytes;
      } else
        id_bytes = (int16_t)(str->string_len); /* 0239 */

      if (mode >= 2) /* Return positional data */
      {
        if (vpos++) {
          /* Extract value position */

          while (bytes_remaining && IsDigit(*vpos)) {
            value = value * 10 + (*(vpos++) - '0');
            bytes_remaining--;
          }

          /* Extract subvalue position */

          if (*(vpos++) == VALUE_MARK) {
            bytes_remaining--;
            while (bytes_remaining && IsDigit(*vpos)) {
              subvalue = subvalue * 10 + (*(vpos++) - '0');
              bytes_remaining--;
            }
          }

          /* Extract internal data */

          if (mode == 3) {
            if (*(vpos++) == VALUE_MARK) {
              bytes_remaining--;
              descr = &int_descr;
              while (descr->type == ADDR)
                descr = descr->data.d_addr;
              Release(descr);
              k_put_string(vpos, bytes_remaining, descr);
            }
          }
        }
      }

      if (id_bytes == 0) /* 0239 */
      {
        /* This is clearly a duff select list item as SD doesn't support
          null record ids.  It can happen if a user writes a record with
          an id that starts with a value mark (naughty!). We need to
          dispose of the STRING_CHUNK and write a null string.          */

        s_free(descr->data.str.saddr);
        descr->data.str.saddr = NULL;
      }
    }
  }

  /* 14 Oct 26 dm - $MODE PICK.READNEXT (openQM item 418): a list variable that has no more items takes the ELSE
     clause and the id variable is left as it was */
  if ((op_flags & P_PICK_RDNX) && status) {
    k_pop(2); /* The (empty) string and the address of the target */
    goto exit_readnext;
  }

  op_stor(); /* Store the id string */

  goto exit_readnext;

exit_readnext_null:

  /* 14 Oct 26 dm - $MODE PICK.READNEXT (openQM item 418): the id variable is left as it was */
  if (op_flags & P_PICK_RDNX) {
    k_pop(1);
    goto exit_readnext;
  }

  /* Set target as null string */

  descr = e_stack - 1;
  do {
    descr = descr->data.d_addr;
  } while (descr->type == ADDR);
  k_release(descr);
  InitDescr(descr, STRING);
  descr->data.str.saddr = NULL;
  k_pop(1);

exit_readnext:
  if (mode >= 2) {
    /* Set value and subvalue positions to zero */

    descr = &subvalue_descr; /* Subvalue position (optional) */
    if (descr->type != UNASSIGNED) {
      while (descr->type == ADDR)
        descr = descr->data.d_addr;
      Release(descr);
      InitDescr(descr, INTEGER);
      descr->data.value = subvalue;
    }

    descr = &value_descr; /* Value position (mandatory) */
    while (descr->type == ADDR)
      descr = descr->data.d_addr;
    Release(descr);
    InitDescr(descr, INTEGER);
    descr->data.value = value;
  }

  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;

  if ((status < 0) && !(op_flags & P_ON_ERROR)) {
    k_error(sysmsg(1412), -status);
  }
}

/* ======================================================================
   op_savelist()  -  SAVELIST statement                                   */

void op_savelist() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         |  Status 0=ok, >0 = ELSE     |
     |-----------------------------|-----------------------------| 
     |  List name                  |                             |
     |=============================|=============================|

 */

  DESCRIPTOR* descr;
  int16_t list_no;

  /* Validate select list number, leaving on e-stack */

  descr = e_stack - 1;
  GetInt(descr);
  list_no = (int16_t)(descr->data.value);
  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  k_recurse(pcode_savelst, 2); /* Execute recursive code */
}

/* ======================================================================
   op_select()  -  Select records from file                               */

void op_select() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         | Status 0=ok, >0 = ELSE      |
     |                             |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to SELECT.
 */

  u_int16_t op_flags;
  DESCRIPTOR* descr;
  int16_t list_no;
  FILE_VAR* fvar;
  int32_t record_count;
  STRING_CHUNK* net_ids = NULL; /* S.65 slice 3d: the ids of a remote file, and how many, and how asking went */
  int32_t net_count = 0;
  int net_st;

  op_flags = process.op_flags;
  process.op_flags = 0;

  process.status = 0;

  /* Validate select list number */

  descr = e_stack - 1;
  GetInt(descr);
  list_no = (int16_t)(descr->data.value);

  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  descr = e_stack - 2;
  k_get_value(descr);

  if (descr->type != FILE_REF) /* 0208 */
  {
    op_formlist();
  } else {
    fvar = descr->data.fvar;

    if (fvar->type == NET_FILE) /* 17 Oct 26 S.65 slice 3d: the ids come from the server first; the target list is touched only if they do */
    {
      net_ids = NULL;
      net_count = 0;
      net_st = net_select_with_flags(fvar, op_flags, &net_ids, &net_count);
      if (net_st != 0) { /* the ELSE branch, or an error that net_select() raised unless the statement has ON ERROR */
        process.status = net_st;
        k_pop(1);
        k_dismiss();
        goto select_status;
      }
    }

    end_select(list_no);
    clear_select(list_no); /* 0441 */

    /* Do the select */

    switch (fvar->type) {
      case NET_FILE:
        store_select_list(list_no, net_ids, net_count);
        break;

      case DYNAMIC_FILE:
        if (!dh_select(fvar->access.dh.dh_file, list_no)) {
          process.status = ER_RNF;
        }
        break;

      case DIRECTORY_FILE:
        if (!dir_select(fvar, list_no))
          process.status = ER_RNF;
        break;

      default:
        k_error(sysmsg(1413));
    }

    k_pop(1);
    k_dismiss();

    /* Copy selected record count to @SELECTED */

    /* Find SELECT.COUNT(LIST.NO) in SYSCOM */

    record_count = SelectCount(list_no)->data.value;

    /* Find @SELECTED in SYSCOM */

    descr = Element(process.syscom, SYSCOM_SELECTED);
    k_release(descr); /* 0487 */
    InitDescr(descr, INTEGER);
    descr->data.value = record_count;
  }

select_status:
  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = process.status;

  if ((process.status < 0) && !(op_flags & P_ON_ERROR)) {
    k_error(sysmsg(1414), -process.status);
  }
}

/* ======================================================================
   op_selecte()  -  Transfer list 0 to a select list variable             */

void op_selecte() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list variable       |                             |
     |=============================|=============================|

 */

  DESCRIPTOR* tgt_descr;

  /* Get target address */

  tgt_descr = e_stack - 1;
  while (tgt_descr->type == ADDR)
    tgt_descr = tgt_descr->data.d_addr;
  k_release(tgt_descr);
  k_pop(1);

  transfer_list0(tgt_descr);
}

/* ======================================================================
   transfer_list0()  -  Move the unprocessed items of list 0 to a select list variable

   The target has been released.  Used by SELECTE and, under $MODE PICK.SELECT, by SELECTV when list 0 is active
   (15 Oct 26, QM4 gaps Q-16, which also moved this out of op_selecte()).  */

Private void transfer_list0(DESCRIPTOR* tgt_descr) {
  DESCRIPTOR* src_descr;
  STRING_CHUNK* src_hdr;
  STRING_CHUNK* src_str;
  STRING_CHUNK* tgt_str;
  int16_t offset; /* Offset into current source chunk */
  int16_t bytes_remaining;

  /* Transfer unprocessed items in select list 0 to the target variable */

  src_descr = SelectList(0);

  src_hdr = src_descr->data.str.saddr;
  if (src_hdr != NULL) {
    if (src_descr->flags & DF_REMOVE) /* Remove pointer is active */
    {
      offset = src_descr->n1;
      src_str = src_descr->data.str.rmv_saddr;

      ts_init(&tgt_str, 128);
      do {
        bytes_remaining = src_str->bytes - offset;
        if (bytes_remaining > 0)
          ts_copy(src_str->data + offset, bytes_remaining);
        src_str = src_str->next;
        offset = 0;
      } while (src_str != NULL);

      (void)ts_terminate();

      if (--(src_hdr->ref_ct) == 0)
        s_free(src_hdr);
    } else /* No remove pointer - Simply reference whole string */
    {
      tgt_str = src_hdr;
    }
  } else /* Null source list */
  {
    tgt_str = NULL;
  }

  InitDescr(tgt_descr, SELLIST);
  tgt_descr->data.str.saddr = tgt_str;

  /* Wipe out the original list 0 */

  src_descr->data.str.saddr = NULL;

  /* Copy remaining item count to offset field of SELLIST header and
    clear on list 0.                                                */

  src_descr = SelectCount(0);
  if (tgt_str != NULL)
    tgt_str->offset = src_descr->data.value;
  src_descr->data.value = 0;
}

/* ======================================================================
   op_selectv()  -  Select records from file to a SELLIST variable        */

void op_selectv() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list variable       | Status 0=ok, >0 = ELSE      |
     |                             |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to SELECTV.

    NOTE: This opcode uses list 11 internally.
 */

  u_int16_t op_flags;
  DESCRIPTOR* descr;
  DESCRIPTOR* tgt_descr;
  FILE_VAR* fvar;
  STRING_CHUNK* tgt_str;
  STRING_CHUNK* str;
  int32_t record_count;
  char* p;
  int16_t bytes;
  STRING_CHUNK* net_ids = NULL; /* S.65 slice 3d: the ids of a remote file, and how many, and how asking went */
  int32_t net_count = 0;
  int net_st;

  op_flags = process.op_flags;
  process.op_flags = 0;

  process.status = 0;

  /* Get target address */

  tgt_descr = e_stack - 1;
  while (tgt_descr->type == ADDR)
    tgt_descr = tgt_descr->data.d_addr;
  k_release(tgt_descr);

  /* $MODE PICK.SELECT: with the default list active, SELECTV moves it to the target and looks at nothing else, the file
     variable included (15 Oct 26, QM4 gaps Q-16) */

  if ((op_flags & P_PICK_SEL) && SelectList(0)->data.str.saddr != NULL) {
    transfer_list0(tgt_descr);
    goto selectv_status;
  }

  /* Get file variable / dynamic array */

  descr = e_stack - 2;
  k_get_value(descr);
  if (descr->type != FILE_REF) /* 0208 */
  {
    k_get_string(descr);
    InitDescr(tgt_descr, SELLIST);

    /* Must copy the string rather than just incrementing the reference
      count as we are going to the use offset field of the header for
      the item count.                                                  */

    tgt_descr->data.str.saddr = k_copy_string(descr->data.str.saddr);
    tgt_str = tgt_descr->data.str.saddr;
    if ((str = tgt_str) != NULL) {
      record_count = 1;
      do {
        for (p = str->data, bytes = str->bytes; bytes--; p++) {
          if (*p == FIELD_MARK)
            record_count++;
        }
      } while ((str = str->next) != NULL);
      tgt_str->offset = record_count;
    }
  } else {
    fvar = descr->data.fvar;

    if (fvar->type == NET_FILE) /* 17 Oct 26 S.65 slice 3d: the ids of a remote file are the target list; list 11 is not used */
    {
      net_ids = NULL;
      net_count = 0;
      net_st = net_select_with_flags(fvar, op_flags, &net_ids, &net_count);

      /* The handler ran BASIC: the target is found again from the stack, as op_read does */
      tgt_descr = e_stack - 1;
      while (tgt_descr->type == ADDR)
        tgt_descr = tgt_descr->data.d_addr;

      InitDescr(tgt_descr, SELLIST);
      tgt_descr->data.str.saddr = NULL; /* an empty list unless the ids came */
      if (net_st != 0) {
        process.status = net_st;
      } else {
        if (net_ids != NULL) {
          tgt_descr->data.str.saddr = net_ids;
          net_ids->offset = net_count;
        }
        descr = Element(process.syscom, SYSCOM_SELECTED);
        descr->data.value = net_count;
      }
      goto selectv_status;
    }

    /* Do the select */

    switch (fvar->type) {
      case DYNAMIC_FILE:
        if (!dh_select(fvar->access.dh.dh_file, 11)) {
          process.status = ER_RNF;
        }
        complete_select(11); /* Complete select */
        break;

      case DIRECTORY_FILE:
        if (!dir_select(fvar, 11))
          process.status = ER_RNF;
        break;

      default:
        k_error(sysmsg(1415));
    }

    /* Transfer the select list to the target variable */

    descr = SelectList(11);
    *tgt_descr = *descr;
    tgt_descr->type = SELLIST;
    tgt_str = tgt_descr->data.str.saddr;
    InitDescr(descr, STRING);
    descr->data.str.saddr = NULL;

    /* Copy selected record count to @SELECTED and SELLIST, then clear it */

    descr = SelectCount(11);
    record_count = descr->data.value;
    descr->data.value = 0;

    if (tgt_str != NULL)
      tgt_str->offset = record_count;

    descr = Element(process.syscom, SYSCOM_SELECTED);
    descr->data.value = record_count;
  }

selectv_status:
  k_pop(1); /* 0293 Moved to be in both processing paths */
  k_dismiss();

  /* Set status code on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = process.status;

  if ((process.status < 0) && !(op_flags & P_ON_ERROR)) {
    k_error(sysmsg(1414), -process.status);
  }
}

/* ======================================================================
   op_sselect()  -  Select records from file, sorted by record id         */

void op_sselect() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Select list number         | Status 0=ok, >0 = ELSE      |
     |                             |        <0 = ON ERROR        |
     |-----------------------------|-----------------------------| 
     |  File variable              |                             |
     |=============================|=============================|
                    
    ON ERROR codes are only returned if ONERROR opcode executed prior to
    call to SELECT.
 */

  DESCRIPTOR* descr;
  int16_t list_no;

  process.op_flags = 0; /* ON ERROR not used */

  process.status = 0;

  /* Validate select list number */

  descr = e_stack - 1;
  GetInt(descr);
  list_no = (int16_t)(descr->data.value);

  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  descr = e_stack - 2;
  k_get_value(descr); /* 0208 */

  /* 11 Oct 26 - SSELECT now takes the sort mode as a third argument; none here */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = 0;

  k_recurse(pcode_sselct, 3);
}

/* ======================================================================
   op_sselectm()  -  SSELECT with RIGHT.ALIGNED and/or DESCENDING

   11 Oct 26  openQM refs 243 and 367.  Mode: 1 right aligned, 2 descending
   (the BT_ flags of SORTINIT).                                           */

void op_sselectm() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Sort mode                  | Status 0=ok                 |
     |-----------------------------|-----------------------------|
     |  Select list number         |                             |
     |-----------------------------|-----------------------------|
     |  File variable              |                             |
     |=============================|=============================|
 */

  DESCRIPTOR* descr;
  int16_t list_no;

  process.op_flags = 0;
  process.status = 0;

  descr = e_stack - 1;
  GetInt(descr);

  descr = e_stack - 2;
  GetInt(descr);
  list_no = (int16_t)(descr->data.value);

  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  descr = e_stack - 3;
  k_get_value(descr);

  k_recurse(pcode_sselct, 3);
}

/* ======================================================================
   op_sselectv()  -  Select records from a file, sorted by id, into a SELLIST variable   (14 Oct 26, openQM 209) */

void op_sselectv() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Sort mode                  | Status 0=ok                 |
     |-----------------------------|-----------------------------|
     |  ADDR of select list var    |                             |
     |-----------------------------|-----------------------------|
     |  File variable / dyn array  |                             |
     |=============================|=============================|
 */

  DESCRIPTOR* descr;

  process.op_flags = 0;
  process.status = 0;

  descr = e_stack - 1;
  GetInt(descr);

  descr = e_stack - 3;
  k_get_value(descr);

  k_recurse(pcode_sselctv, 3);
}

/* ======================================================================
   op_slctinfo()  -  SELECTINFO() function                                */

void op_slctinfo() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Key value                  | Result                      |
     |-----------------------------|-----------------------------| 
     |  Select list number         |                             |
     |=============================|=============================|

     Key values:       Function                      Returns       
     1    SL_ACTIVE    Test if list is active        True/False 
     3    SL_COUNT     Find size of list             No of items
 */

  DESCRIPTOR* descr;
  DESCRIPTOR* select_count_descr;
  int16_t list_no; /* Select list number */
  int32_t key;

  /* Fetch key value */

  descr = e_stack - 1;
  GetInt(descr);
  key = descr->data.value;
  k_pop(1);

  /* Validate select list number, leaving on e-stack */

  descr = e_stack - 1;
  GetInt(descr);
  list_no = (int16_t)(descr->data.value);

  if (InvalidSelectListNo(list_no))
    k_select_range_error();

  /* Find SELECT.COUNT(LIST.NO) in SYSCOM */

  select_count_descr = SelectCount(list_no);
  GetInt(select_count_descr);

  /* Process according to key value */

  descr = e_stack - 1;
  switch (key) {
    case 1:
      descr->data.value = (select_count_descr->data.value > 0);
      break;

    case 3:
      complete_select(list_no); /* Complete any partial select */
      descr->data.value = max(0, select_count_descr->data.value);
      break;

    default:
      descr->data.value = 0;
      break;
  }
}

/* ======================================================================
   clear_select()  -  Clear a select list                                 */

void clear_select(int16_t list_no) {
  DESCRIPTOR* tgt_descr; /* Target select list descriptor */

  /* Find SELECT.LIST array in SYSCOM */

  tgt_descr = SelectList(list_no);

  /* Release current content and replace by null string */

  k_release(tgt_descr);
  InitDescr(tgt_descr, STRING);
  tgt_descr->data.str.saddr = NULL;

  /* Find SELECT.COUNT array in SYSCOM */

  tgt_descr = SelectCount(list_no);

  /* Check if this is an active partial select */

  end_select(list_no);

  /* Release current content and replace by -1 */

  k_release(tgt_descr);
  InitDescr(tgt_descr, INTEGER);
  tgt_descr->data.value = -1;
}

/* ======================================================================
   Perform select on directory file                                       */

Private bool dir_select(FILE_VAR* fvar, int16_t list_no) {
  bool status = FALSE;
  FILE_ENTRY* fptr;
  char pathname[MAX_PATHNAME_LEN + 1];
  int path_len;
  char name[MAX_PATHNAME_LEN + 1];
  STRING_CHUNK* head = NULL;
  int record_count = 0; /* 0481 */
  char* p;
  char* q;
  char* r;
  char c;
  DIR* dfu;
  struct dirent* dp;
  struct stat statbuf;
  int retries;

  fptr = FPtr(fvar->file_id);
  strcpy(pathname, (char*)(fptr->pathname));
  path_len = strlen(pathname);

  /* 16 Oct 26 (openQM 279): at the operating system's limit of open files opendir() fails and the list was left empty
     with nothing said.  dio_open() closes the oldest file the FDS system holds and tries again; so does this. */
  dfu = opendir(pathname);
  for (retries = 0; (dfu == NULL) && ((errno == EMFILE) || (errno == ENFILE)) && (retries < 8); retries++) {
    FDS_close();
    dfu = opendir(pathname);
  }
  if ((dfu == NULL) && ((errno == EMFILE) || (errno == ENFILE)))
    k_error("Cannot read the directory %s: too many files are open", pathname);

  if (dfu != NULL) {
    if (pathname[path_len - 1] == DS)
      pathname[path_len - 1] = '\0';

    while ((dp = readdir(dfu)) != NULL) {
      /* converted to snprintf() -gwb 22Feb20 */
      if (snprintf(name, MAX_PATHNAME_LEN + 1, "%s%c%s", pathname, DS,
                   dp->d_name) >= (MAX_PATHNAME_LEN + 1)) {
        /* TODO: this should also be logged with more detail */
        k_error("Overflowed path/filename length in dir_select()!");
        /* as in op_dir(), I'm not sure how to safely exit this routine,
         * so I'm gonna...
         */
        break; /* TODO: Work out the correct way of exiting this function with an error */
      }
      /* 12 Oct 26 (openQM item 445): OPTION DIR.SEL.OMIT.HIDDEN leaves out the names that begin with a dot */
      if (Option(OptDirSelOmitHidden) && dp->d_name[0] == '.')
        continue;

      /* 16 Oct 26 (QM4 Fixes item 177): %header% holds the directory file's trigger, and is not a record */
      if (is_dir_header(dp->d_name))
        continue;

      if (stat(name, &statbuf))
        continue; /* 1.3-8  Carry on rather than end */

      if (statbuf.st_mode & S_IFREG) {
        strcpy(name, dp->d_name);
#ifdef CASE_INSENSITIVE_FILE_SYSTEM
        if (!Option(OptSelectKeepCase))
          UpperCaseString(name);
#endif

        if (map_dir_ids && (strchr(name, '%') != NULL)) /* Mapped name */
        {
          p = name;
          q = name;
/* rev 0.9.0 */
/* rev 0.9-3 roll back test for both cases of t and d */
          if ((*p == '%') &&
             (*(p + 1) == 'D'))    /* Special case - first char only */
          {
            *(q++) = '.';
            p += 2;
/* rev 0.9.0 */            
          } else if ((*p == '%') &&
                     (*(p + 1) == 'T'))/* Special case - first char only */
          {
            *(q++) = '~';
            p += 2;
          }

          while ((c = *(p++)) != '\0') {
            if (c == '%') {
              /* 02 Sep 26 Windows port - PRE_RELEASE_FIXES.md 128, UPSTREAM 35.
                 TEST THE CHARACTER BEFORE CONSUMING IT.  This read
                 strchr(df_substitute_chars, *(p++)) and then tested the
                 result, which had two faults.

                 An unknown escape wrote nothing but had ALREADY stepped over
                 the letter, so "draft%1" decoded to "draft" - two different
                 files collapsing onto one id, and an id readnext hands back
                 that will not open.

                 Worse, a TRAILING '%' consumed the string's own terminator,
                 and strchr(s, '\0') returns a pointer to that table's NUL
                 rather than NULL - so the "r != NULL" guard PASSED, p was
                 left pointing past the end of name, and this loop went on
                 consuming adjacent stack memory while q wrote it back into
                 name.  name is char[MAX_PATHNAME_LEN + 1] on the stack, so
                 that overflows it rather than merely over-reading.

                 An unknown escape is now kept LITERAL, which makes the decode
                 total: every input maps to some output and none runs off the
                 end.  q never overtakes p (each turn consumes at least as
                 much as it writes), so the in-place decode is still safe.

                 KNOWN AND DELIBERATE: a literal '%' does not round-trip
                 through map_t1_id(), which encodes '%' as "%P" - so the id
                 reported for a file named "draft%1" will not re-open it.  SD
                 never creates such a name; only a file dropped into the
                 directory from outside can carry one.  Reporting it visibly
                 beats both the old silent collision and dropping the entry,
                 which would hide the file from SELECT entirely. */
              if ((*p != '\0') &&
                  ((r = strchr(df_substitute_chars, *p)) != NULL)) {
                *(q++) = df_restricted_chars[r - df_substitute_chars];
                p++;
              } else {
                *(q++) = c;
              }
            } else {
              *(q++) = c;
            }
          }
          *q = '\0';
        }
// rev 0.9-3  mab if we end up here with an empty name, don't add to list
        if (strlen(name) > 0) {        
          if (head == NULL)
            ts_init(&head, 256);
          else
            ts_copy_byte(FIELD_MARK);

          ts_copy_c_string(name);
          record_count++;
		}
	  }
    }

    closedir(dfu);
  }

  /* Copy the record list (if any) to the select list */

  if (head != NULL) {
    ts_terminate();
    store_select_list(list_no, head, record_count);
  }

  status = TRUE;

  return status;
}

/* ======================================================================
   store_select_list()  -  Make a string of ids (field marks between) select list LIST_NO, with RECORD_COUNT in SELECT.COUNT.  Taken out of
   dir_select() when a remote file's SELECT (S.65 slice 3d) needed the same two steps; the list is the string and keeps it.               */

Private void store_select_list(int16_t list_no, STRING_CHUNK* head, int32_t record_count) {
  DESCRIPTOR* descr;

  /* Find SELECT.COUNT(LIST.NO) in SYSCOM */

  descr = Element(process.syscom, SYSCOM_SELECT_COUNT);
  descr = Element(descr->data.ahdr_addr, list_no);
  k_release(descr);
  InitDescr(descr, INTEGER);
  descr->data.value = record_count;

  /* Find SELECT.LIST(LIST.NO) in SYSCOM.  No ids (a remote file with no records) leaves the list as clear_select() made it, with the count 0. */

  if (head == NULL)
    return;

  descr = Element(process.syscom, SYSCOM_SELECT_LIST);
  descr = Element(descr->data.ahdr_addr, list_no);
  k_release(descr);
  InitDescr(descr, STRING);
  descr->data.str.saddr = head;
}

/* ======================================================================
   net_select_with_flags()  -  net_select() with only the statement's ON ERROR given to it (the caller cleared process.op_flags), and
   cleared again afterwards.  The handler runs BASIC: the caller finds its operands again by e_stack.                                    */

Private int net_select_with_flags(FILE_VAR* fvar, u_int16_t op_flags, STRING_CHUNK** ids, int32_t* count) {
  int st;

  process.op_flags = op_flags & P_ON_ERROR;
  st = net_select(fvar, ids, count);
  process.op_flags = 0;
  return st;
}

/* ======================================================================
   op_dir()  -  Return directory data                                     */

void op_dir() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Directory pathname         | Returned data               |
     |=============================|=============================|
                    
 */

  DESCRIPTOR* descr;
  char pathname[MAX_PATHNAME_LEN + 1];
  int16_t path_len;
  char name[MAX_PATHNAME_LEN + 1];
  STRING_CHUNK* result = NULL;
  char mode;
  DIR* dfu;
  struct dirent* dp;
  struct stat statbuf;

  ts_init(&result, 1024);

  /* 13 Oct 26: STATUS() is 0 unless this call says otherwise.  It was never set here, so an empty directory read
     as "cannot read directory" in a session whose last operation had left a status behind (SELECT.DIR's test
     is "no entries and STATUS() not 0"); found by the S.63 suite's SELECT.DIR sub row.                         */
  process.status = 0;

  descr = e_stack - 1;
  path_len = k_get_c_string(descr, pathname, MAX_PATHNAME_LEN);
  if (path_len > 0) {
    /* 13 Oct 26 S.63 (the second sitting): DIR() lists an OS directory by pathname, which is "a file external to
       SD" exactly as OPENSEQ and OPENPATH name one.  An account without OS.EXECUTE lists only a directory inside
       its own; the answer is a null string and STATUS() 3035, as OPEN ... ELSE gets.  A $internal program is
       trusted and asks the account itself (SELECT.DIR asks K$PATH.OK).  The first gates suite did not cover this:
       a measured DIR('/etc') gave 257 entries to an account with both gates off.                              */
    if (!os_path_open_ok(pathname)) {
      process.status = ER_PERM;
    } else if ((dfu = opendir(pathname)) != NULL) {
      if (pathname[path_len - 1] == DS)
        pathname[path_len - 1] = '\0';

      while ((dp = readdir(dfu)) != NULL) {
        if (!strcmp(dp->d_name, ".") || !strcmp(dp->d_name, ".."))
          continue;
        /* converted to snprintf() -gwb 22Feb20 */
        if (snprintf(name, MAX_PATHNAME_LEN + 1, "%s%c%s", pathname, DS,
                     dp->d_name) >= (MAX_PATHNAME_LEN + 1)) {
          /* TODO: this should also be logged with more detail */
          k_error("Overflowed path/filename length in op_dir()!");
          /* since I really don't want to add a goto here, and I'm not
           * exactly sure what the correct error behavior should be, 
           * I'm going to add a...
           */
          break; /* TODO: work out the correct way to exit this function with an error. */
        }

        if (stat(name, &statbuf))
          continue;

        strcpy(name, dp->d_name);
#ifdef CASE_INSENSITIVE_FILE_SYSTEM
        UpperCaseString(name);
#endif
        if (statbuf.st_mode & S_IFREG)
          mode = 'F';
        else if (statbuf.st_mode & S_IFDIR)
          mode = 'D';
        else
          continue;

        if (result != NULL)
          ts_copy_byte(FIELD_MARK);

        ts_copy_c_string(name);
        ts_copy_byte(VALUE_MARK);
        ts_copy_byte(mode);
        /* 12 Oct 26 (openQM item 366): a third value, the size in bytes */
        {
          char size_text[32];
          snprintf(size_text, sizeof(size_text), "%lld", (long long)statbuf.st_size);
          ts_copy_byte(VALUE_MARK);
          ts_copy_c_string(size_text);
        }
      }
      closedir(dfu);
    } else {
      /* a directory that cannot be opened says so in STATUS(), which is what tells it from an empty one */
      process.os_error = OSError;
      process.status = (process.os_error == ENOENT) ? ER_FNF : ER_PERM;
    }
  }

  ts_terminate();

  k_release(descr);
  InitDescr(descr, STRING);
  descr->data.str.saddr = result;
}

/* ======================================================================
   complete_select()  -  Complete a partial select                        */

void complete_select(int16_t list_no) {
  switch (select_ftype[list_no]) {
    case SEL_DH:
      dh_complete_select(list_no);
      break;
  }
}

/* ======================================================================
   end_select()  -  Terminate a partial select                           */

void end_select(int16_t list_no) {
  switch (select_ftype[list_no]) {
    case SEL_DH:
      dh_end_select(list_no);
      break;
  }
}

/* END-CODE */
