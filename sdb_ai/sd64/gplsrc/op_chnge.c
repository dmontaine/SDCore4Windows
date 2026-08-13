/* OP_CHNGE.C
 * CHANGE opcode
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
 * 14 Jul 24 mab max string size test in op_change  
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"

/* ======================================================================
   op_change()  -  Change substrings                                      */

void op_change() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  First occurrence to change |  New string                 |
     |-----------------------------|-----------------------------|
     |  Occurences to change       |                             |
     |-----------------------------|-----------------------------|
     |  New substring              |                             |
     |-----------------------------|-----------------------------|
     |  Old substring              |                             |
     |-----------------------------|-----------------------------|
     |  Source string              |                             |
     |=============================|=============================|
 */

  int32_t skip_count;   /* Occurrences to skip before change */
  int32_t change_count; /* Number of occurrences to change */

  STRING_CHUNK* new_str; /* New substring */
  STRING_CHUNK* str;

  char* old_str;     /* old substring */
  int16_t old_len; /* Length of old substring */

  STRING_CHUNK* src_hdr; /* Source string chunk pointer */

  DESCRIPTOR result_descr; /* Modified string */

  STRING_CHUNK* str_hdr;
  DESCRIPTOR* descr;
  int16_t n;
  char* p;

  /* Outer loop control */
  int16_t src_bytes_remaining;
  char* src;

  /* Inner loop control */
  STRING_CHUNK* isrc_hdr;
  int16_t isrc_bytes_remaining;
  char* isrc;
  char* substr;
  int16_t i_len;

  bool nocase;

  /* 020240714 mab Max String Size test */
  int32_t delta_len32;  /* net lenght change for each replacement              */
  int64_t chgd_len64;   /* what resulting string  length will be after change  */

  nocase = (process.program.flags & HDR_NOCASE) != 0;

  /* Fetch start occurrence number */

  descr = e_stack - 1;
  GetInt(descr);
  skip_count = descr->data.value;
  if (skip_count < 1)
    skip_count = 1;
  skip_count--;

  /* Fetch count of occurrences to change */

  descr = e_stack - 2;
  GetInt(descr);
  change_count = descr->data.value;

  /* Make new substring contiguous and find details */

  descr = e_stack - 3;
  k_get_string(descr);
  new_str = descr->data.str.saddr;
  if (new_str == NULL){
    delta_len32 = 0;   /* replacement string null ('') */
  }else{
    delta_len32 = new_str->string_len;  /* lenght of replacement string */
  }

  /* Make old substring contiguous and find details */
  /* 020240714 mab Max String Size test */
  /* Note something odd here,  lenght of string to search for and replace, "old" string */
  /* seems to be limited to a lenght of 32767 characters? see s_make_contiguous         */
  /* and int16_t casting of lenght */
  descr = e_stack - 4;
  k_get_string(descr);
  descr->data.str.saddr = s_make_contiguous(descr->data.str.saddr, NULL);
  str_hdr = descr->data.str.saddr;
  if (str_hdr == NULL) /* Null old string - return source unchanged */
  {
    k_pop(1);
    k_pop(1);
    k_dismiss();         /* New substring */
    k_dismiss();         /* Old substring */
    goto exit_op_change; /* Leave source as result */
  }

  old_str = str_hdr->data;
  old_len = (int16_t)(str_hdr->string_len);
  /* 020240714 mab Max String Size test */
  /* calc length change each replacement */
  delta_len32 -= old_len;

  /* Find source string */

  descr = e_stack - 5;
  k_get_string(descr);
  src_hdr = descr->data.str.saddr;
  if (src_hdr == NULL) {
    k_pop(1);
    k_pop(1);
    k_dismiss();         /* New substring */
    k_dismiss();         /* Old substring */
    goto exit_op_change; /* Leave null source as result */
  }
  chgd_len64 = src_hdr->string_len;   /* length of source string (and starting len of changed string)*/

  InitDescr(&result_descr, STRING);
  result_descr.data.str.saddr = NULL;
  ts_init(&result_descr.data.str.saddr, src_hdr->string_len);

  /* Outer loop - Scan source string for initial character of substring */

  while (src_hdr != NULL) {
    src = src_hdr->data;
    src_bytes_remaining = src_hdr->bytes;

    while (src_bytes_remaining > 0) {
      if (nocase)
        p = (char*)memichr(src, *old_str, src_bytes_remaining);
      else
        p = (char*)memchr(src, *old_str, src_bytes_remaining);

      if (p == NULL) {
        /* First character not present. Copy all of chunk and move on */
        ts_copy(src, src_bytes_remaining);
        break;
      }

      /* First character is present. Copy up to this character before
        looking any further.                                          */

      n = p - src;
      if (n)
        ts_copy(src, n);
      src_bytes_remaining -= n;
      src = p; /* Leave pointing at first character */

      if (old_len > 1) /* Multi-byte search item */
      {
        /* Inner loop - match remaining characters of the old substring */

        isrc_hdr = src_hdr;
        isrc = src + 1; /* Point to second character of source... */
        isrc_bytes_remaining = src_bytes_remaining - 1;
        substr = old_str + 1; /* ...and of old string */
        i_len = old_len - 1;
        do {
          if (isrc_bytes_remaining-- == 0) {
            isrc_hdr = isrc_hdr->next;
            if (isrc_hdr == NULL)
              goto no_match;

            isrc = isrc_hdr->data;
            isrc_bytes_remaining = isrc_hdr->bytes - 1;
            /* -1 allows for decrement for this cycle */
          }

          if (nocase) {
            if (UpperCase(*(isrc++)) != UpperCase(*(substr++)))
              goto no_match;
          } else {
            if (*(isrc++) != *(substr++))
              goto no_match;
          }
        } while (--i_len);

        /* Match found  -  do we want this one? */

        if (skip_count-- > 0)
          goto no_match;

        /* Insert replacement substring */
        /* 020240714 mab Max String Size test */
        chgd_len64 += delta_len32;
        if (chgd_len64 > MAX_STRING_SIZE){
          k_error(sysmsg(10004));   /* Operation exceeds MAX_STRING_SIZE */
        }

        for (str = new_str; str != NULL; str = str->next) {
          ts_copy(str->data, str->bytes);
        }

        /* Leave outer loop variables pointing after the substring */

        src_bytes_remaining = isrc_bytes_remaining;
        src = isrc;
        src_hdr = isrc_hdr;
        if (--change_count == 0)
          goto copy_remainder;
        continue;
      } else /* Matching single character substring */
      {
        if (skip_count-- > 0)
          goto no_match;

        /* 020240714 mab Max String Size test */
        chgd_len64 += delta_len32;
        if (chgd_len64 > MAX_STRING_SIZE){
          k_error(sysmsg(10004));   /* Operation exceeds MAX_STRING_SIZE */
        }  

        for (str = new_str; str != NULL; str = str->next) {
          ts_copy(str->data, str->bytes);
        }

        src++; /* Skip old substring */
        src_bytes_remaining--;
        if (--change_count == 0)
          goto copy_remainder;
        continue;
      }

    no_match:
      /* Move on one byte, copying to new string */
      ts_copy_byte(*(src++));
      src_bytes_remaining--;
    } /* while src_bytes_remaining */

    /* Advance to next chunk */

    src_hdr = src_hdr->next;
  }

copy_remainder:
  if (src_hdr != NULL) {
    if (src_bytes_remaining)
      ts_copy(src, src_bytes_remaining);

    while ((src_hdr = src_hdr->next) != NULL) {
      ts_copy(src_hdr->data, src_hdr->bytes);
    }
  }

  k_pop(1);
  k_pop(1);
  k_dismiss(); /* New substring */
  k_dismiss(); /* Old substring */
  k_dismiss(); /* Source string */

  ts_terminate();
  *(e_stack++) = result_descr;

exit_op_change:
  return;
}

/* END-CODE */
