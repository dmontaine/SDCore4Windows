/* OP_STR4.C
 * String handling opcodes (4)
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
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *    op_alpha       ALPHA
 *    op_count       COUNT
 *    op_dcount      DCOUNT
 *    op_index       INDEX
 *    op_matbuild    MATBUILD
 *    op_matches     MATCHES
 *    op_matchfld    MATCHFLD
 *    op_matparse    MATPARSE
 *    op_num         NUM
 *    op_soundex     SOUNDEX
 *    op_trim        TRIM
 *    op_trimb       TRIMB
 *    op_trimf       TRIMF
 *    op_trimx       TRIMX   Full format of TRIM() function
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <openssl/evp.h>   /* before sd.h: descr.h defines OBJ, which turns OpenSSL's OBJ_dup into 15_dup */
#include "sd.h"
#include "header.h"

Private void count(bool dcount);
Private void matches(bool matchfield);

/* ======================================================================
   op_alpha()  -  Test alphabetic                                         */

void op_alpha() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Source string              |  True/False result          |
     |=============================|=============================|
 */

  DESCRIPTOR *descr;
  bool is_alpha = FALSE;
  STRING_CHUNK *src_str;
  int16_t src_bytes;
  char *src;

  descr = e_stack - 1;
  k_get_string(descr);

  src_str = descr->data.str.saddr;

  if (src_str != NULL) {
    do {
      src = src_str->data;
      for (src_bytes = src_str->bytes; src_bytes > 0; src_bytes--) {
        if (!IsAlpha(*src))
          goto exit_op_alpha;
        src++;
      }

      src_str = src_str->next;
    } while (src_str != NULL);

    is_alpha = TRUE;
  }

exit_op_alpha:

  k_dismiss();

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = is_alpha;
}

/* ======================================================================
   op_count()  -  Count occurrences of substring in string                */

void op_count() {
  count(FALSE);
}

/* ======================================================================
   op_dcount()  -  Count delimited string fields                          */

void op_dcount() {
  count(TRUE);
}

/* ======================================================================
   op_index()  -  Find n'th occurrence of substring in string             */

void op_index() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Occurrence                 |  Substring position         |
     |-----------------------------|-----------------------------|
     |  Substring                  |                             |
     |-----------------------------|-----------------------------|
     |  Source string              |                             |
     |=============================|=============================|
 */

  DESCRIPTOR *descr;

  int32_t occurrence;

#define MAX_SUBSTRING_LEN 256
  char substring[MAX_SUBSTRING_LEN + 1];
  int16_t substring_len;
  char *substr;

  /* Outer loop control */
  STRING_CHUNK *src_str;
  int16_t src_bytes_remaining;
  char *src;
  int32_t offset = 0;

  /* Inner loop control */
  STRING_CHUNK *isrc_str;
  int16_t isrc_bytes_remaining;
  char *isrc;
  int32_t ioffset;
  bool nocase;
  int16_t i_len;
  char *p;

  nocase = (process.program.flags & HDR_NOCASE) != 0;

  /* Fetch occurrence number */

  descr = e_stack - 1;
  GetInt(descr);
  occurrence = descr->data.value;
  k_pop(1);

  /* Fetch substring */

  descr = e_stack - 1;
  substring_len = k_get_c_string(descr, substring, MAX_SUBSTRING_LEN);
  k_dismiss();

  if (substring_len < 0) {
    substring_len = MAX_SUBSTRING_LEN; /* Truncate at max */
    process.status = 1;
  } else
    process.status = 0;

  if (occurrence < 1)
    goto exit_op_index;

  if (substring_len == 0) {
    offset = occurrence;
    goto exit_op_index;
  }

  substring_len--; /* Set as one fewer than actual length */

  /* Fetch source string to be searched */

  descr = e_stack - 1;
  k_get_string(descr);
  src_str = descr->data.str.saddr;

  /* Outer loop - Scan source string for initial character of substring */

  while (src_str != NULL) {
    src = src_str->data;
    src_bytes_remaining = src_str->bytes;
    offset += src_bytes_remaining;

    while (src_bytes_remaining > 0) {
      if (nocase) {
        p = (char *)memichr(src, substring[0], src_bytes_remaining);
      } else {
        p = (char *)memchr(src, substring[0], src_bytes_remaining);
      }
      if (p == NULL)
        break;

      src_bytes_remaining -= (p - src) + 1;
      src = p + 1;

      if (substring_len) /* Multi-byte search item */
      {
        /* Inner loop - match each character of the substring. */

        isrc_str = src_str;
        isrc = src;
        isrc_bytes_remaining = src_bytes_remaining;
        ioffset = 0;
        i_len = substring_len;
        substr = &(substring[1]);

        do {
          /* ++++ Could use memcmp in this loop */
          if (isrc_bytes_remaining-- == 0) {
            isrc_str = isrc_str->next;
            if (isrc_str == NULL)
              goto no_match;

            isrc = isrc_str->data;
            isrc_bytes_remaining = isrc_str->bytes;
            ioffset += isrc_bytes_remaining--;
          }

          if (nocase) {
            if (UpperCase(*(isrc++)) != UpperCase(*(substr++)))
              goto no_match;
          } else {
            if (*(isrc++) != *(substr++))
              goto no_match;
          }
        } while (--i_len);

        /* Match found - leave outer loop variables pointing after the
          substring.                                                   */

        if (--occurrence == 0) /* Found desired occurrence */
        {
          offset -= src_bytes_remaining;
          goto exit_op_index;
        }

        src_bytes_remaining = isrc_bytes_remaining;
        offset += ioffset;
        src = isrc;
        src_str = isrc_str;
      no_match:;
      } else /* Matching single character substring */
      {
        if (--occurrence == 0) /* Found desired occurrence */
        {
          offset -= src_bytes_remaining;
          goto exit_op_index;
        }
      }
    }

    /* Advance to next chunk */

    src_str = src_str->next;
  }

  /* Desired occurrence not found - return zero */

  offset = 0;

exit_op_index:

  k_dismiss();

  /* Set result on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = offset;
}

/* ======================================================================
   op_matbuild()  -  MATBUILD  -  Build string from matrix                */

void op_matbuild() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Delimiter                  |  Result                     |
     |-----------------------------|-----------------------------| 
     |  End index                  |                             |
     |-----------------------------|-----------------------------| 
     |  Start index                |                             |
     |-----------------------------|-----------------------------| 
     |  Source matrix              |                             |
     |=============================|=============================|
 */

  DESCRIPTOR *mat_descr;
  DESCRIPTOR *com_descr;
  DESCRIPTOR *descr; /* Various descriptors */

  STRING_CHUNK *delim_str;
  PMATRIX_HEADER *pm_hdr;

  ARRAY_HEADER *a_hdr;
  int32_t num_elements;
  int32_t indx;
  ARRAY_CHUNK *a_chunk;

  DESCRIPTOR src_descr;
  STRING_CHUNK *src_str;

  int32_t start_index;
  int32_t end_index;

  DESCRIPTOR tgt_descr;

  /* Get delimiter string */

  descr = e_stack - 1;
  k_get_string(descr);
  delim_str = descr->data.str.saddr;

  /* Get ending index */

  descr = e_stack - 2;
  GetInt(descr);
  end_index = descr->data.value;

  /* Get starting index */

  descr = e_stack - 3;
  GetInt(descr);
  start_index = descr->data.value;
  if (start_index < 1)
    start_index = 1;

  /* Get source matrix */

  mat_descr = e_stack - 4;
  while (mat_descr->type == ADDR)
    mat_descr = mat_descr->data.d_addr;

  switch (mat_descr->type) {
    case ARRAY:
      a_hdr = mat_descr->data.ahdr_addr;
      num_elements = ((a_hdr->cols == 0) ? 1 : a_hdr->cols) * a_hdr->rows;
      /* Excludes zero element */
      if ((end_index < 1) || (end_index > num_elements))
        end_index = num_elements;
      break;

    case PMATRIX:
      pm_hdr = mat_descr->data.pmatrix;
      com_descr = pm_hdr->com_descr;
      if (pm_hdr->cols == 0)
        num_elements = pm_hdr->rows;
      else
        num_elements = pm_hdr->cols * pm_hdr->rows;
      if ((end_index < 1) || (end_index > num_elements))
        end_index = num_elements;
      start_index += pm_hdr->base_offset - 1;
      end_index += pm_hdr->base_offset - 1;
      a_hdr = com_descr->data.ahdr_addr;
      break;

    default:
      k_error(sysmsg(1236));
  }

  /* Initialise target variable in our C stack */

  InitDescr(&tgt_descr, STRING);
  tgt_descr.data.str.saddr = NULL;
  ts_init(&tgt_descr.data.str.saddr, 64);

  /* Find last non-null element in range being processed */

  for (indx = end_index; indx >= start_index; indx--) {
    a_chunk = a_hdr->chunk[indx / MAX_ARRAY_CHUNK_SIZE];
    descr = &(a_chunk->descr[indx % MAX_ARRAY_CHUNK_SIZE]);
    if ((descr->type != STRING) || (descr->data.str.saddr != NULL)) {
      break;
    }
    end_index--;
  }

  /* Build target string */

  for (indx = start_index; indx <= end_index; indx++) {
    /* 0122  if (tgt_descr.data.str.saddr != NULL) */
    if (indx != start_index) /* 0122 */
    {
      /* Copy delimiter to target string */

      for (src_str = delim_str; src_str != NULL; src_str = src_str->next) {
        ts_copy(src_str->data, src_str->bytes);
      }
    }

    /* Copy source array element to target string */

    a_chunk = a_hdr->chunk[indx / MAX_ARRAY_CHUNK_SIZE];

    /* We need a string format version of the source array element but we
      must not convert the actual element itself if it is not already a
      string.  Make a local copy of the descriptor as a string.           */

    InitDescr(&src_descr, ADDR);
    src_descr.data.d_addr = &(a_chunk->descr[indx % MAX_ARRAY_CHUNK_SIZE]);
    (void)k_dereference(&src_descr);
    if (src_descr.type != UNASSIGNED) {
      k_get_string(&src_descr);

      for (src_str = src_descr.data.str.saddr; src_str != NULL; src_str = src_str->next) {
        ts_copy(src_str->data, src_str->bytes);
      }
      k_release(&src_descr); /* Release local copy */
    }
  }

  if ((mat_descr->type == ARRAY) && !(a_hdr->flags & AH_PICK_STYLE)) {
    /* Now add the zero element, if it is not null */

    a_chunk = a_hdr->chunk[0];
    InitDescr(&src_descr, ADDR);
    src_descr.data.d_addr = &(a_chunk->descr[0]);
    (void)k_dereference(&src_descr);
    if (src_descr.type != UNASSIGNED) {
      k_get_string(&src_descr);

      if (src_descr.data.str.saddr != NULL) {
        if (tgt_descr.data.str.saddr != NULL) {
          /* Copy delimiter to target string */

          for (src_str = delim_str; src_str != NULL; src_str = src_str->next) {
            ts_copy(src_str->data, src_str->bytes);
          }
        }
      }

      /* Copy zero element to target string */

      for (src_str = src_descr.data.str.saddr; src_str != NULL; src_str = src_str->next) {
        ts_copy(src_str->data, src_str->bytes);
      }

      k_release(&src_descr); /* Release local copy */
    }
  }

  ts_terminate();

  k_dismiss(); /* Delimiter string */
  k_pop(2);    /* Ending and starting index */
  k_dismiss(); /* Array */

  /* Move result string to top of stack */

  *(e_stack++) = tgt_descr;
}

/* ======================================================================
   op_matstr()  -  MATSTR() function   (12 Oct 26, openQM item 509, the description the owner supplied)

   A dynamic array from a whole matrix.  A two dimensional matrix gives a
   field for each row and a value for each column.  A one dimensional one
   gives a field for each element, as MATBUILD does (trailing null elements
   left off).  The zero element is not used.  Marks already in the data are
   not escaped.

     Stack:   top  matrix (an ADDR)                       -> the string     */

Private void matstr_element(ARRAY_HEADER* a_hdr, int32_t indx) {
  ARRAY_CHUNK* a_chunk;
  DESCRIPTOR src_descr;
  STRING_CHUNK* src_str;

  a_chunk = a_hdr->chunk[indx / MAX_ARRAY_CHUNK_SIZE];
  InitDescr(&src_descr, ADDR);
  src_descr.data.d_addr = &(a_chunk->descr[indx % MAX_ARRAY_CHUNK_SIZE]);
  (void)k_dereference(&src_descr);
  if (src_descr.type != UNASSIGNED) {
    k_get_string(&src_descr);
    for (src_str = src_descr.data.str.saddr; src_str != NULL; src_str = src_str->next)
      ts_copy(src_str->data, src_str->bytes);
    k_release(&src_descr);
  }
}

void op_matstr() {
  DESCRIPTOR* mat_descr;
  DESCRIPTOR* descr;
  PMATRIX_HEADER* pm_hdr;
  ARRAY_HEADER* a_hdr;
  ARRAY_CHUNK* a_chunk;
  DESCRIPTOR tgt_descr;
  int32_t rows;
  int32_t cols;
  int32_t base = 0;
  int32_t r;
  int32_t c;
  int32_t last;

  mat_descr = e_stack - 1;
  while (mat_descr->type == ADDR)
    mat_descr = mat_descr->data.d_addr;

  switch (mat_descr->type) {
    case ARRAY:
      a_hdr = mat_descr->data.ahdr_addr;
      rows = a_hdr->rows;
      cols = a_hdr->cols;
      break;

    case PMATRIX:
      pm_hdr = mat_descr->data.pmatrix;
      a_hdr = pm_hdr->com_descr->data.ahdr_addr;
      rows = pm_hdr->rows;
      cols = pm_hdr->cols;
      base = pm_hdr->base_offset - 1;
      break;

    default:
      k_error(sysmsg(1236));
      return;
  }

  InitDescr(&tgt_descr, STRING);
  tgt_descr.data.str.saddr = NULL;
  ts_init(&tgt_descr.data.str.saddr, 64);

  if (cols == 0) { /* One dimensional: as MATBUILD with an FM */
    last = rows;
    while (last >= 1) {
      a_chunk = a_hdr->chunk[(last + base) / MAX_ARRAY_CHUNK_SIZE];
      descr = &(a_chunk->descr[(last + base) % MAX_ARRAY_CHUNK_SIZE]);
      if ((descr->type != STRING) || (descr->data.str.saddr != NULL))
        break;
      last--;
    }
    for (r = 1; r <= last; r++) {
      if (r > 1)
        ts_copy_byte(FIELD_MARK);
      matstr_element(a_hdr, r + base);
    }
  } else { /* Two dimensional: a field for each row, a value for each column */
    for (r = 1; r <= rows; r++) {
      if (r > 1)
        ts_copy_byte(FIELD_MARK);
      for (c = 1; c <= cols; c++) {
        if (c > 1)
          ts_copy_byte(VALUE_MARK);
        matstr_element(a_hdr, (r - 1) * cols + c + base);
      }
    }
  }

  ts_terminate();
  k_dismiss(); /* The matrix address */
  *(e_stack++) = tgt_descr;
}

/* ======================================================================
   op_matches()  -  Match string against template                         */

void op_matches() {
  matches(FALSE);
}

/* ======================================================================
   op_matchfld()  -  MATCHFIELD() function                                */

void op_matchfld() {
  matches(TRUE);
}

/* ======================================================================
   op_matparse()  -  Parse string into array                              */

void op_matparse() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Delimiter                  |                             |
     |-----------------------------|-----------------------------| 
     |  Source string              |                             |
     |-----------------------------|-----------------------------| 
     |  ADDR to target array       |                             |
     |=============================|=============================|
 */

  DESCRIPTOR *descr; /* Various descriptors */

  char s[256 + 1];       /* Delimiter string from program */
  char delimiters[256];  /* Boolean map of delimiter characters */
  int16_t no_delimiters; /* No of delimiters */

  DESCRIPTOR *array_descr; /* Target array */
  ARRAY_HEADER *a_hdr;
  PMATRIX_HEADER *pm_hdr;
  int lo_index;
  int32_t hi_index; /* Index of last element */
  int32_t indx;     /* Current target element number */

  STRING_CHUNK *src_str;
  int16_t src_bytes_remaining;
  char *src;

  DESCRIPTOR *tgt_descr; /* Target array element descriptor */
  STRING_CHUNK *tgt_str;
  u_int16_t last_char = 256;

  DESCRIPTOR *com_descr;
  int rows;
  int cols;
  bool pick_style;
  int offset;

  register char c;
  int16_t i;

  /* Get delimiter character(s) */

  descr = e_stack - 1;
  k_get_string(descr);
  if (descr->data.str.saddr == NULL) {
    memset(delimiters, 1, 256);
    no_delimiters = 0;
  } else {
    no_delimiters = k_get_c_string(descr, s, 256);

    /* Build a map of characters which are delimiters */

    memset(delimiters, 0, 256);
    for (i = 0; i < no_delimiters; i++) {
      delimiters[(u_char)s[i]] = 1;
    }
  }
  k_dismiss();

  /* Get source string */

  descr = e_stack - 1;
  k_get_string(descr);
  src_str = descr->data.str.saddr;

  /* Get target array */

  array_descr = e_stack - 2;
  while (array_descr->type == ADDR)
    array_descr = array_descr->data.d_addr;
  switch (array_descr->type) {
    case ARRAY:
      a_hdr = array_descr->data.ahdr_addr;
      pick_style = a_hdr->flags & AH_PICK_STYLE;
      rows = a_hdr->rows;
      cols = a_hdr->cols;
      offset = 0;
      break;

    case PMATRIX:
      pick_style = TRUE;
      pm_hdr = array_descr->data.pmatrix;
      com_descr = pm_hdr->com_descr;
      rows = pm_hdr->rows;
      cols = pm_hdr->cols;
      offset = pm_hdr->base_offset - 1; /* Allow pseudo zero element */
      a_hdr = com_descr->data.ahdr_addr;
      break;

    default:
      k_not_array_error(array_descr);
  }

  lo_index = (pick_style) ? 1 : 0;
  if (cols == 0)
    cols = 1;
  hi_index = cols * rows;

  /* Set all elements as null strings */

  for (indx = lo_index; indx <= hi_index; indx++) {
    tgt_descr = Element(a_hdr, indx + offset);
    Release(tgt_descr);
    InitDescr(tgt_descr, STRING);
    tgt_descr->data.str.saddr = NULL;
  }

  /* Walk the string parsing it into the array */

  if (src_str == NULL) {
    process.inmat = 0;
    goto exit_op_matparse;
  }

  indx = 1;
  if (hi_index == 0) /* 0389 */
  {
    src = src_str->data;
    src_bytes_remaining = src_str->bytes;
    goto no_elements;
  }

  ts_init(&tgt_str, 32);
  tgt_str = NULL;

  while (src_str != NULL) {
    src = src_str->data;
    src_bytes_remaining = src_str->bytes;

    while (src_bytes_remaining-- > 0) {
      c = *(src++);
      if (delimiters[(u_char)c]) /* Character is a delimiter */
      {
        /* If we have more than one delimiter character and this delimiter
          was also the immediately preceding character, discard it.       */

        if ((no_delimiters > 1) && (c == last_char))
          continue;

        if (indx == hi_index) {
          if (pick_style)
            ts_copy_byte(c);
          goto assign_excess_data;
        }

        /* Terminate current element */

        ts_terminate();
        Element(a_hdr, indx + offset)->data.str.saddr = tgt_str;
        indx++;

        /* Start new element */

        ts_init(&tgt_str, 32);
        tgt_str = NULL;

        if (no_delimiters) {
          if (no_delimiters > 1) /* Multiple delimiters */
          {
            /* The delimiter must be placed in an element of its own */

            ts_init(&tgt_str, 1);
            tgt_str = NULL;
            ts_copy_byte(c);

            if (indx == hi_index)
              goto assign_excess_data;

            ts_terminate();
            Element(a_hdr, indx + offset)->data.str.saddr = tgt_str;
            indx++;
          }

          ts_init(&tgt_str, 32);
          tgt_str = NULL;
          goto next_char;
        }
      }

      ts_copy_byte(c);

    next_char:
      last_char = c;
    }

    src_str = src_str->next;
  }

assign_excess_data:

  if ((!pick_style) || (src_str == NULL)) /* Nothing to append to final element */
  {
    ts_terminate(); /* Terminate final element */
    Element(a_hdr, indx + offset)->data.str.saddr = tgt_str;
  }

no_elements:
  if (src_str == NULL) /* No text remains to be assigned */
  {
    process.inmat = indx;
  } else /* Text remains to be assigned */
  {
    process.inmat = 0;

    if (!pick_style) {
      indx = 0;
      ts_init(&tgt_str, 32);
      tgt_str = NULL;
    }

    do {
      if (src_bytes_remaining)
        ts_copy(src, src_bytes_remaining);
      if ((src_str = src_str->next) != NULL) {
        src = src_str->data;
        src_bytes_remaining = src_str->bytes;
      }
    } while (src_str != NULL);

    ts_terminate();
    Element(a_hdr, indx + offset)->data.str.saddr = tgt_str;
  }

exit_op_matparse:

  k_dismiss(); /* Dismiss source string */
  k_dismiss(); /* Dismiss target array ADDR */

  return;
}

/* ======================================================================
   op_num()  -  Test numeric                                              */

void op_num() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Source string              |  True/False result          |
     |=============================|=============================|
 */

  DESCRIPTOR *descr;
  bool is_num = FALSE;

  descr = e_stack - 1;
  k_get_value(descr);
  if ((descr->type == INTEGER) || (descr->type == FLOATNUM)) {
    is_num = TRUE;
    k_pop(1);
  } else {
    k_get_string(descr);
    is_num = k_is_num(descr);
    k_dismiss();
  }

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = is_num;
}

/* ======================================================================
   op_soundex()  -  Return SOUNDEX value of string                        */

void op_soundex() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Source string              |  Soundex value              |
     |=============================|=============================|
 */

  DESCRIPTOR *descr;
  STRING_CHUNK *src_str;
  int16_t src_bytes;
  char *src;
  register u_char c;
  char last = '\0';
  char code;
  char soundex[4 + 1];
  int16_t i;
  static char soundex_value[] = "01230120022455012623010202";
  /* ABCDEFGHIJKLMNOPQRSTUVWXYZ */
  descr = e_stack - 1;
  k_get_string(descr);

  i = 0;
  for (src_str = descr->data.str.saddr; src_str != NULL; src_str = src_str->next) {
    src = src_str->data;
    for (src_bytes = src_str->bytes; src_bytes > 0; src_bytes--) {
      c = *(src++);

      if (IsAlpha(c)) {
        c = UpperCase(c);
        code = soundex_value[c - 'A'];

        if (i == 0) /* First character */
        {
          soundex[i++] = c;
          last = c;
        } else {
          if ((code != '0') && (c != last)) /* Later characters */
          {
            soundex[i++] = code;
            if (i == 4)
              break;
            last = c;
          }
        }
      }
    }
  }

  while (i < 4)
    soundex[i++] = '0';
  soundex[4] = '\0';

  k_dismiss();

  k_put_c_string(soundex, e_stack++);
}

/* ======================================================================
   op_trim()  -  Trim leading, embedded and trailing spaces from string   */

void op_trim() {
  DESCRIPTOR *src_descr;       /* Source string descriptor */
  DESCRIPTOR result;           /* Result string descriptor */
  STRING_CHUNK *src_str;       /* Current source chunk */
  char *src;                   /* Ptr to current byte */
  int16_t src_bytes_remaining; /* Remaining bytes in this chunk */

  bool front_of_string;
  bool space_skipped;

  char c;

  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Source string              |  Result string              |
     |=============================|=============================|
 */

  /* Get source string */

  src_descr = e_stack - 1;
  k_get_string(src_descr);
  src_str = src_descr->data.str.saddr;
  if (src_str == NULL)
    goto exit_trim; /* Null source */

  /* Create a result string descriptor in our C stack space */

  result.type = STRING;
  result.flags = 0;
  result.data.str.saddr = NULL;

  ts_init(&result.data.str.saddr, min(64, src_str->string_len));

  /* Copy string, removing leading and trailing spaces from each field, 
    value, etc, compressing multiple spaces to a single space.         */

  front_of_string = TRUE;
  space_skipped = FALSE;

  while (src_str != NULL) {
    src_bytes_remaining = src_str->bytes;
    src = src_str->data;

    /* Process all data in this chunk */

    while (src_bytes_remaining-- > 0) {
      c = *(src++);
      if (c == ' ') {
        space_skipped = !front_of_string;
      } else {
        front_of_string = FALSE;
        if (space_skipped && !front_of_string) { /* Insert a single space */
          ts_copy_byte(' ');
          space_skipped = FALSE;
        }

        ts_copy_byte(c);
      }
    }

    /* Advance to next source chunk */

    src_str = src_str->next;
  }

  ts_terminate();

  k_dismiss(); /* Dismiss source string */

  /* Copy result to e-stack */

  *(e_stack++) = result;

exit_trim:
  return;
}

/* ======================================================================
   op_trimb()  -  Trim trailing spaces from string                        */

void op_trimb() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Source string              |  Result string              |
     |=============================|=============================|
 */

  DESCRIPTOR *src_descr;       /* Source string descriptor */
  DESCRIPTOR result;           /* Result string descriptor */
  STRING_CHUNK *src_str;       /* Current source chunk */
  char *src;                   /* Ptr to current byte */
  int16_t src_bytes_remaining; /* Remaining bytes in this chunk */

  int32_t space_count;

  char c;

  /* Get source string */

  src_descr = e_stack - 1;
  k_get_string(src_descr);
  src_str = src_descr->data.str.saddr;
  if (src_str == NULL)
    goto exit_trimb; /* Null source */

  /* Create a result string descriptor in our C stack space */

  InitDescr(&result, STRING);
  result.data.str.saddr = NULL;

  ts_init(&result.data.str.saddr, min(64, src_str->string_len));

  /* Copy string, removing trailing spaces */

  space_count = 0;

  while (src_str != NULL) {
    src_bytes_remaining = src_str->bytes;
    src = src_str->data;

    /* Process all data in this chunk */

    while (src_bytes_remaining-- > 0) {
      c = *(src++);
      if (c == ' ') {
        space_count++;
      } else {
        if (space_count) {
          ts_fill(' ', space_count);
          space_count = 0;
        }
        ts_copy_byte(c);
      }
    }

    /* Advance to next source chunk */

    src_str = src_str->next;
  }

  ts_terminate();

  k_dismiss(); /* Dismiss source string */

  /* Copy result to e-stack */

  *(e_stack++) = result;

exit_trimb:
  return;
}

/* ======================================================================
   op_trimw()  -  Trim whitespace from string

   11 Oct 26  openQM ref 302.  Like TRIM() but for every white space
   character (space, tab, line feed, carriage return, form feed, vertical
   tab): leading and trailing white space is removed and each run inside
   the string becomes one space.                                          */

void op_trimw() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Source string              |  Result string              |
     |=============================|=============================|
 */

  DESCRIPTOR *src_descr;       /* Source string descriptor */
  DESCRIPTOR result;           /* Result string descriptor */
  STRING_CHUNK *src_str;       /* Current source chunk */
  char *src;                   /* Ptr to current byte */
  int16_t src_bytes_remaining; /* Remaining bytes in this chunk */

  bool front_of_string = TRUE;
  bool white_pending = FALSE;
  char c;

  src_descr = e_stack - 1;
  k_get_string(src_descr);
  src_str = src_descr->data.str.saddr;
  if (src_str == NULL)
    goto exit_trimw; /* Null source */

  InitDescr(&result, STRING);
  result.data.str.saddr = NULL;

  ts_init(&result.data.str.saddr, min(64, src_str->string_len));

  while (src_str != NULL) {
    src_bytes_remaining = src_str->bytes;
    src = src_str->data;

    while (src_bytes_remaining-- > 0) {
      c = *(src++);
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v') {
        white_pending = !front_of_string;
      } else {
        if (white_pending) {
          ts_copy_byte(' ');
          white_pending = FALSE;
        }
        front_of_string = FALSE;
        ts_copy_byte(c);
      }
    }

    src_str = src_str->next;
  }

  ts_terminate();

  k_dismiss(); /* Dismiss source string */

  *(e_stack++) = result;

exit_trimw:
  return;
}

/* ======================================================================
   op_md5()  -  MD5() function

   12 Oct 26  openQM ref 63.  The MD5 message digest of the string, as 32
   lower case hexadecimal characters (the owner supplied the openQM
   description).  Uses OpenSSL's EVP interface.                           */

void op_md5() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Source string              |  Digest, 32 hex characters  |
     |=============================|=============================|
 */

  DESCRIPTOR *src_descr;
  STRING_CHUNK *src_str;
  EVP_MD_CTX *ctx;
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int digest_len = 0;
  char hex[2 * EVP_MAX_MD_SIZE + 1];
  unsigned int i;

  src_descr = e_stack - 1;
  k_get_string(src_descr);
  src_str = src_descr->data.str.saddr;

  ctx = EVP_MD_CTX_new();
  if (ctx == NULL || EVP_DigestInit_ex(ctx, EVP_md5(), NULL) != 1) {
    if (ctx != NULL)
      EVP_MD_CTX_free(ctx);
    k_error("MD5() is not available");
    return;
  }

  while (src_str != NULL) {
    if (src_str->bytes > 0)
      EVP_DigestUpdate(ctx, src_str->data, (size_t)src_str->bytes);
    src_str = src_str->next;
  }

  EVP_DigestFinal_ex(ctx, digest, &digest_len);
  EVP_MD_CTX_free(ctx);

  for (i = 0; i < digest_len; i++)
    sprintf(hex + 2 * i, "%02x", digest[i]);
  hex[2 * digest_len] = '\0';

  k_dismiss();                      /* Dismiss the source string */
  k_put_c_string(hex, e_stack);
  e_stack++;
}

/* ======================================================================
   op_trimf()  -  Trim leading spaces from string                         */

void op_trimf() {
  DESCRIPTOR *src_descr;       /* Source string descriptor */
  DESCRIPTOR result;           /* Result string descriptor */
  STRING_CHUNK *src_str;       /* Current source chunk */
  char *src;                   /* Ptr to current byte */
  int16_t src_bytes_remaining; /* Remaining bytes in this chunk */

  bool front_of_string;

  char c;

  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Source string              |  Result string              |
     |=============================|=============================|
 */

  /* Get source string */

  src_descr = e_stack - 1;
  k_get_string(src_descr);
  src_str = src_descr->data.str.saddr;
  if (src_str == NULL)
    goto exit_trimf; /* Null source */

  /* Create a result string descriptor in our C stack space */

  result.type = STRING;
  result.flags = 0;
  result.data.str.saddr = NULL;

  ts_init(&result.data.str.saddr, min(64, src_str->string_len));

  /* Copy string, removing leading spaces from each field, value, etc */

  front_of_string = TRUE;

  while (src_str != NULL) {
    src_bytes_remaining = src_str->bytes;
    src = src_str->data;

    /* Process all data in this chunk */

    while (src_bytes_remaining-- > 0) {
      c = *(src++);
      if ((!front_of_string) || (c != ' ')) {
        ts_copy_byte(c);
        front_of_string = FALSE;
      }
    }

    /* Advance to next source chunk */

    src_str = src_str->next;
  }

  ts_terminate();

  k_dismiss(); /* Dismiss source string */

  /* Copy result to e-stack */

  *(e_stack++) = result;

exit_trimf:
  return;
}

/* ======================================================================
   op_trimx()  -  Variable mode trim function                            */

void op_trimx() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Mode                       |  Result string              |
     |-----------------------------|-----------------------------|
     |  Character                  |                             |
     |-----------------------------|-----------------------------|
     |  Source string              |                             |
     |=============================|=============================|

     Modes:
       A   Remove all occurrences of character
       B   Remove leading and trailing occurrences of character
       C   Compact multiple occurrences of character
       D   As TRIM()  Remove leading and trailing spaces, compressing
           repeated embedded spaces
       E   As TRIMB() Remove trailing spaces
       F   As TRIMF() Remove leading spaces
       R   Remove leading and trailing occurences of character, compressing
           repeated embedded characters
       T   Remove trailing occurences of character
       L   Remove leading occurences of character
 */

  DESCRIPTOR *descr;
  char mode;
  char ch;
  STRING_CHUNK *str;

  DESCRIPTOR *src_descr;       /* Source string descriptor */
  DESCRIPTOR result;           /* Result string descriptor */
  STRING_CHUNK *src_str;       /* Current source chunk */
  char *src;                   /* Ptr to current byte */
  int16_t src_bytes_remaining; /* Remaining bytes in this chunk */

  bool front_of_string;
  bool skip_count;

  bool skip_leading;
  bool skip_trailing;
  bool skip_all;
  bool compress;

  char c;

  /* Fetch mode */

  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  if (str == NULL)
    mode = 'R';
  else
    mode = str->data[0];
  k_dismiss();

  switch (mode) {
    case 'A':
      skip_leading = TRUE;
      skip_trailing = TRUE;
      skip_all = TRUE;
      compress = TRUE;
      break;

    case 'B':
      skip_leading = TRUE;
      skip_trailing = TRUE;
      skip_all = FALSE;
      compress = FALSE;
      break;

    case 'C':
      skip_leading = FALSE;
      skip_trailing = FALSE;
      skip_all = FALSE;
      compress = TRUE;
      break;

    case 'D':
    case 'R':
      skip_leading = TRUE;
      skip_trailing = TRUE;
      skip_all = FALSE;
      compress = TRUE;
      break;

    case 'E':
    case 'T':
      skip_leading = FALSE;
      skip_trailing = TRUE;
      skip_all = FALSE;
      compress = FALSE;
      break;

    case 'F':
    case 'L':
      skip_leading = TRUE;
      skip_trailing = FALSE;
      skip_all = FALSE;
      compress = FALSE;
      break;

    default:
      k_error(sysmsg(1600));
  }

  /* Fetch character */

  descr = e_stack - 1;
  k_get_string(descr);
  if (strchr("DEF", mode) != NULL) {
    ch = ' ';
  } else {
    str = descr->data.str.saddr;
    if (str == NULL)
      k_error(sysmsg(1601));
    ch = str->data[0];
  }
  k_dismiss();

  /* Get source string */

  src_descr = e_stack - 1;
  k_get_string(src_descr);
  src_str = src_descr->data.str.saddr;
  if (src_str == NULL)
    goto exit_trim; /* Null source */

  /* Create a result string descriptor in our C stack space */

  result.type = STRING;
  result.flags = 0;
  result.data.str.saddr = NULL;

  ts_init(&result.data.str.saddr, min(64, src_str->string_len));

  /* Copy string, removing characters as appropriate */

  front_of_string = TRUE;
  skip_count = 0;

  while (src_str != NULL) {
    src_bytes_remaining = src_str->bytes;
    src = src_str->data;

    /* Process all data in this chunk */

    while (src_bytes_remaining-- > 0) {
      c = *(src++);

      if (c == ch) {
        if ((skip_count == 0) || !compress)
          skip_count++;
      } else {
        if (skip_count) /* We have skipped some embedded characters.
                                Do we need to put them back?              */
        {
          if (!skip_all) {
            if (!front_of_string || !skip_leading) {
              ts_fill(ch, skip_count);
            }
          }
          skip_count = 0;
        }
        ts_copy_byte(c);
        front_of_string = FALSE;
      }
    }

    /* Advance to next source chunk */

    src_str = src_str->next;
  }

  if (skip_count) /* We have skipped some trailing characters.  Do we need
                     to put them back?                                     */
  {
    if (!skip_trailing && !(skip_leading && front_of_string)) {
      ts_fill(ch, skip_count);
    }
  }

  ts_terminate();

  k_dismiss(); /* Dismiss source string */

  /* Copy result to e-stack */

  *(e_stack++) = result;

exit_trim:
  return;
}

/* ======================================================================
   count()  -  Common path for COUNT and DCOUNT                           */

Private void count(bool dcount) /* Doing DCOUNT? */
{
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Substring                  |  Count                      |
     |-----------------------------|-----------------------------|
     |  Source string              |                             |
     |=============================|=============================|
 */

  DESCRIPTOR *src_descr;       /* Source string to search */
  DESCRIPTOR *substring_descr; /* Substring / Delimiter */
#define MAX_SUBSTRING_LEN 256
  char substring[MAX_SUBSTRING_LEN + 1];
  int16_t substring_len;
  char *substr;

  /* Outer loop control */
  STRING_CHUNK *src_str;
  int16_t src_bytes_remaining;
  char *src;

  /* Inner loop control */
  STRING_CHUNK *isrc_str;
  int16_t isrc_bytes_remaining;
  int16_t ilen;
  char *isrc;

  bool nocase;
  int32_t ct = 0;
  char *p;

  nocase = (process.program.flags & HDR_NOCASE) != 0;

  /* Fetch substring */

  substring_descr = e_stack - 1;
  substring_len = k_get_c_string(substring_descr, substring, MAX_SUBSTRING_LEN);
  if (substring_len < 0)
    k_error(sysmsg(1602));
  k_dismiss();

  /* Fetch source string to be searched */

  src_descr = e_stack - 1;
  k_get_string(src_descr);
  src_str = src_descr->data.str.saddr;
  if (src_str == NULL)
    goto exit_count;

  if (substring_len == 0) {
    ct = src_str->string_len;
    goto exit_count;
  }

  substring_len--; /* Actually one fewer than substring length */

  /* Count occurrences of substring in source */

  /* Outer loop - Scan source string for initial character of substring */

  while (src_str != NULL) {
    src = src_str->data;
    src_bytes_remaining = src_str->bytes;

    while (src_bytes_remaining) {
      if (nocase) {
        p = (char *)memichr(src, substring[0], src_bytes_remaining);
      } else {
        p = (char *)memchr(src, substring[0], src_bytes_remaining);
      }
      if (p == NULL)
        break;

      p++;
      src_bytes_remaining -= p - src;
      src = p;

      if (substring_len) /* Matching string of more than one byte */
      {
        /* Inner loop - match each character of the substring. */

        isrc_str = src_str;
        isrc = src;
        isrc_bytes_remaining = src_bytes_remaining;
        ilen = substring_len;

        substr = substring + 1;
        do {
          /* ++++ Could use memcmp */
          if (isrc_bytes_remaining-- == 0) {
            isrc_str = isrc_str->next;
            if (isrc_str == NULL)
              goto no_match;

            isrc = isrc_str->data;
            isrc_bytes_remaining = isrc_str->bytes - 1;
          }

          if (nocase) {
            if (UpperCase(*(isrc++)) != UpperCase(*(substr++)))
              goto no_match;
          } else {
            if (*(isrc++) != *(substr++))
              goto no_match;
          }
        } while (--ilen);

        /* Match found - leave outer loop variables pointing after the
          substring.                                                   */

        ct++;

        src_bytes_remaining = isrc_bytes_remaining;
        src = isrc;
        src_str = isrc_str;

      no_match:;
      } else /* Matching single character substring */
      {
        ct++;
      }
    }

    /* Advance to next chunk */

    src_str = src_str->next;
  }

  if (dcount)
    ct++;

exit_count:

  k_dismiss();

  /* Set result count on stack */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = ct;
}

/* ======================================================================
   matches()  -  Common path for MATCHES and MATCHFLD opcodes             */

Private char *component_start;
Private char *component_end;

Private void matches(bool matchfield) {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Component (Matchfield only)| Result                      |
     |-----------------------------|-----------------------------| 
     |  Template                   |                             |
     |-----------------------------|-----------------------------| 
     |  Source string              |                             |
     |=============================|=============================|
 */

#define MAX_TEMPLATE_LEN 256

  DESCRIPTOR *descr;
  char template_string[MAX_TEMPLATE_LEN + 1];
  char *src_string;
  char *p;
  char *q;
  int16_t return_component; /* Component number for MATCHFIELD */
  bool match = FALSE;

  if (matchfield) {
    descr = e_stack - 1;
    GetInt(descr);
    return_component = (int16_t)(descr->data.value);  // value is int32_t (descr.h) -gwb
    if (return_component < 1)
      return_component = 1;
    k_pop(1);
  } else
    return_component = -1; /* initializing this to satisfy valgrind 06feb22 -gwb */

  descr = e_stack - 1;
  if (k_get_c_string(descr, template_string, MAX_TEMPLATE_LEN) < 0) {
    k_error(sysmsg(1603));
  }
  k_dismiss();

  descr = e_stack - 1;
  GetString(descr);
  src_string = alloc_c_string(descr);
  k_dismiss();

  component_start = NULL;
  component_end = NULL;

  /* Try matching against each value mark delimited template */

  p = template_string;
  do { /* Outer loop - extract templates */
    q = strchr(p, VALUE_MARK);
    if (q != NULL)
      *q = '\0';

    match = match_template(src_string, p, 0, return_component);
    if (match)
      break;

    p = q + 1;
  } while (q != NULL);

  if (matchfield) {
    if (match && (component_start != NULL)) /* Item found */
    {
      if (component_end != NULL)
        *(component_end) = '\0';
      k_put_c_string(component_start, e_stack++);
    } else {
      InitDescr(e_stack, STRING);
      (e_stack++)->data.str.saddr = NULL;
    }
  } else {
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = match;
  }

  k_free(src_string);
}

/* ======================================================================
   match_template()  -  Match string against template                     */

bool match_template(char *string,
                    char *template_string,
                    int16_t component,        /* Current component number - 1 (incremented) */
                    int16_t return_component) /* Required component number */
{
  bool not ;
  int16_t n;
  int16_t m;
  int16_t z;
  char *p;
  char delimiter;
  char *start;

  while (*template_string != '\0') {
    component++;
    if (component == return_component)
      component_start = string;
    else if (component == return_component + 1)
      component_end = string;

    start = template_string;

    if (*template_string == '~') {
      not = TRUE;
      template_string++;
    } else
      not = FALSE;

    if (IsDigit(*template_string)) {
      n = 0;
      do {
        n = (n * 10) + (*(template_string++) - '0');
      } while (IsDigit(*template_string));

      switch (UpperCase(*(template_string++))) {
        case '\0': /* Trailing unquoted numeric literal */
          /* 0115 rewritten */
          n = --template_string - start;
          if (n == 0)
            return FALSE;
          /* without enclosing the !memcmp() in parens, the 
           * compiler complains about potential ambiguity.
           * -gwb 22Feb20
           */
          if ((!memcmp(start, string, n)) == not )
            return FALSE;
          string += n;
          break;

        case 'A': /* nA  Alphabetic match */
          if (n) {
            while (n--) {
              if (*string == '\0')
                return FALSE;
              if ((IsAlpha(*string) != 0) == not )
                return FALSE;
              string++;
            }
          } else {                          /* 0A */
            if (*template_string != '\0') { /* Further template items exist */
              /* Match as many as possible further characters */

              for (z = 0, p = string;; z++, p++) {
                if ((*p == '\0') || ((IsAlpha(*p) != 0) == not ))
                  break;
              }

              /* z now holds number of contiguous alphabetic characters ahead
                 of current position. Starting one byte after the final
                 alphabetic character, backtrack until the remainder of the
                 string matches the remainder of the template.               */

              for (p = string + z; z-- >= 0; p--) {
                if (match_template(p, template_string, component, return_component)) {
                  goto match_found;
                }
              }
              return FALSE;
            } else {
              while ((*string != '\0') && ((IsAlpha(*string) != 0) != not )) {
                string++;
              }
            }
          }
          break;

        case 'N': /* nN  Numeric match */
          if (n) {
            while (n--) {
              if (*string == '\0')
                return FALSE;
              if ((IsDigit(*string) != 0) == not )
                return FALSE;
              string++;
            }
          } else {                          /* 0N */
            if (*template_string != '\0') { /* Further template items exist */
              /* Match as many as possible further chaarcters */

              for (z = 0, p = string;; z++, p++) {
                if ((*p == '\0') || ((IsDigit(*p) != 0) == not ))
                  break;
              }

              /* z now holds number of contiguous numeric characters ahead
                 of current position. Starting one byte after the final
                 numeric character, backtrack until the remainder of the
                 string matches the remainder of the template.               */

              for (p = string + z; z-- >= 0; p--) {
                if (match_template(p, template_string, component, return_component)) {
                  goto match_found;
                }
              }
              return FALSE;
            } else {
              while ((*string != '\0') && ((IsDigit(*string) != 0) != not )) {
                string++;
              }
            }
          }
          break;

        case 'X': /* nX  Unrestricted match */
          if (n) {
            while (n--) {
              if (*(string++) == '\0')
                return FALSE;
            }
          } else {                          /* 0X */
            if (*template_string != '\0') { /* Further template items exist */
              /* Match as few as possible further characters */

              do {
                if (match_template(string, template_string, component, return_component)) {
                  goto match_found;
                }
              } while (*(string++) != '\0');
              return FALSE;
            }
            goto match_found;
          }
          break;

        case '-': /* Count range */
          if (!IsDigit(*template_string))
            return FALSE;
          m = 0;
          do {
            m = (m * 10) + (*(template_string++) - '0');
          } while (IsDigit(*template_string));
          m -= n;
          if (m < 0)
            return FALSE;

          switch (UpperCase(*(template_string++))) {
            case '\0': /* String longer than template */
              n = --template_string - start;
              if (n) { /* We have found a trailing unquoted literal */
                if ((memcmp(start, string, n) == 0) != not )
                  return TRUE;
              }
              return FALSE;

            case 'A': /* n-mA  Alphabetic match */
                      /* Match n alphabetic items */

              while (n--) {
                if (*string == '\0')
                  return FALSE;
                if ((IsAlpha(*string) != 0) == not )
                  return FALSE;
                string++;
              }

              /* We may match up to m further alphabetic characters but must
                  also match as many as possible.  Check how many alphabetic
                  characters there are (up to m) and then backtrack trying
                  matches against the remaining template (if any).           */

              for (z = 0, p = string; z < m; z++, p++) {
                if ((*p == '\0') || ((IsAlpha(*p) != 0) == not ))
                  break;
              }

              /* z now holds max number of matchable characters.
                  Try match at each of these positions and also at the next
                  position (Even if it is the end of the string)            */

              if (*template_string != '\0') { /* Further template items exist */
                for (p = string + z; z-- >= 0; p--) {
                  if (match_template(p, template_string, component, return_component)) {
                    goto match_found;
                  }
                }
                return FALSE;
              } else
                string += z;
              break;

            case 'N': /* n-mN  Numeric match */
                      /* Match n numeric items */

              while (n--) {
                if (*string == '\0')
                  return FALSE;
                if ((IsDigit(*string) != 0) == not )
                  return FALSE;
                string++;
              }

              /* We may match up to m further numeric characters but must
                  also match as many as possible.  Check how many numeric
                  characters there are (up to m) and then backtrack trying
                  matches against the remaining template (if any).           */

              for (z = 0, p = string; z < m; z++, p++) {
                if ((*p == '\0') || ((IsDigit(*p) != 0) == not ))
                  break;
              }

              /* z now holds max number of matchable characters.
                  Try match at each of these positions and also at the next
                  position (Even if it is the end of the string)            */

              if (*template_string != '\0') { /* Further template items exist */
                for (p = string + z; z-- >= 0; p--) {
                  if (match_template(p, template_string, component, return_component)) {
                    goto match_found;
                  }
                }
                return FALSE;
              } else
                string += z;
              break;

            case 'X': /* n-mX  Unrestricted match */
              /* Match n items of any type */

              while (n--) {
                if (*(string++) == '\0')
                  return FALSE;
              }

              /* Match as few as possible up to m further characters */

              if (*template_string != '\0') {
                while (m--) {
                  if (match_template(string, template_string, component, return_component)) {
                    goto match_found;
                  }
                  string++;
                }
                return FALSE;
              } else {
                if ((signed int)strlen(string) > m)
                  return FALSE;
                goto match_found;
              }

            default:
              /* We have found an unquoted literal */
              n = --template_string - start;
              if ((memcmp(start, string, n) == 0) == not )
                return FALSE;
              string += n;
              break;
          }
          break;

        default:
          /* We have found an unquoted literal */
          n = --template_string - start;
          if ((memcmp(start, string, n) == 0) == not )
            return FALSE;
          string += n;
          break;
      }
    } else if (memcmp(template_string, "...", 3) == 0) { /* ... same as 0X */
      template_string += 3;
      if (not )
        return FALSE;
      if (*template_string != '\0') { /* Further template items exist */
        /* Match as few as possible further characters */

        while (*string != '\0') {
          if (match_template(string, template_string, component, return_component)) {
            goto match_found;
          }
          string++;
        }
        return FALSE;
      }
      goto match_found;
    } else { /* Must be literal text item */
      delimiter = *template_string;
      if ((delimiter == '\'') || (delimiter == '"')) { /* Quoted literal */
        template_string++;
        p = strchr(template_string, delimiter);
        if (p == NULL)
          return FALSE;
        n = p - template_string;
        if (n) {
          if ((memcmp(template_string, string, n) == 0) == not )
            return FALSE;
          string += n;
        }
        template_string += n + 1;
      } else { /* Unquoted literal. Treat as single character */
        if ((*(template_string++) == *(string++)) == not )
          return FALSE;
      }
    }
  }

  if (*string != '\0')
    return FALSE; /* String longer than template */

match_found:
  return TRUE;
}

/* ======================================================================
   String arithmetic and REGEX()   (12 Oct 26, openQM items 391, 468, 510)

   SADD SSUB SMUL SDIV SCMP work on numbers held as strings of any length,
   with an optional sign and decimal point: no rounding, no floating point.
   SDIV gives 15 decimal places, truncated, trailing zeros dropped.  SCMP
   answers -1, 0 or 1.  A string that is not a number counts as zero.

   REGEX(string, pattern) is 1 if the POSIX extended regular expression
   matches anywhere in the string, else 0.  A pattern that begins (?i)
   ignores case.  A pattern that does not compile is a run-time error.     */

#include <regex.h>

typedef struct SNUM {
  int neg;
  int scale;   /* digits after the decimal point */
  int n;       /* digits held */
  char* d;     /* the digits, most significant first, value = d / 10^scale */
} SNUM;

/* The bytes of the string at the top of the stack, as a NUL terminated copy (malloc) */
Private char* top_string_copy(DESCRIPTOR* descr, int* lenp) {
  STRING_CHUNK* str;
  char* buf;
  int len = 0;
  int pos = 0;

  k_get_string(descr);
  for (str = descr->data.str.saddr; str != NULL; str = str->next)
    len += str->bytes;
  buf = (char*)malloc((size_t)len + 1);
  if (buf == NULL)
    return NULL;
  for (str = descr->data.str.saddr; str != NULL; str = str->next) {
    memcpy(buf + pos, str->data, (size_t)str->bytes);
    pos += str->bytes;
  }
  buf[len] = '\0';
  if (lenp != NULL)
    *lenp = len;
  return buf;
}

Private void snum_parse(const char* s, SNUM* v) {
  const char* p = s;
  int i;
  int seen_dot = 0;
  int bad = 0;

  v->neg = 0;
  v->scale = 0;
  v->n = 0;
  v->d = (char*)malloc(strlen(s) + 2);
  while (*p == ' ')
    p++;
  if (*p == '-') {
    v->neg = 1;
    p++;
  } else if (*p == '+') {
    p++;
  }
  for (; *p != '\0'; p++) {
    if (*p >= '0' && *p <= '9') {
      v->d[v->n++] = *p;
      if (seen_dot)
        v->scale++;
    } else if (*p == '.' && !seen_dot) {
      seen_dot = 1;
    } else if (*p == ' ') {
      continue;
    } else {
      bad = 1;
      break;
    }
  }
  if (bad || v->n == 0) {
    v->n = 1;
    v->d[0] = '0';
    v->scale = 0;
    v->neg = 0;
  }
  /* drop leading zeros, keeping at least scale+1 digits */
  i = 0;
  while (i < v->n - 1 && v->d[i] == '0' && v->n - i > v->scale + 1)
    i++;
  if (i) {
    memmove(v->d, v->d + i, (size_t)(v->n - i));
    v->n -= i;
  }
}

Private void snum_pad(SNUM* v, int scale) { /* raise the scale by appending zeros */
  int add = scale - v->scale;
  if (add > 0) {
    v->d = (char*)realloc(v->d, (size_t)(v->n + add + 1));
    memset(v->d + v->n, '0', (size_t)add);
    v->n += add;
    v->scale = scale;
  }
}

/* compare magnitudes of two digit strings of the same scale */
Private int mag_cmp(const char* a, int an, const char* b, int bn) {
  int i = 0;
  int j = 0;
  while (i < an - 1 && a[i] == '0')
    i++;
  while (j < bn - 1 && b[j] == '0')
    j++;
  if ((an - i) != (bn - j))
    return ((an - i) > (bn - j)) ? 1 : -1;
  return memcmp(a + i, b + j, (size_t)(an - i)) < 0 ? -1 : (memcmp(a + i, b + j, (size_t)(an - i)) > 0 ? 1 : 0);
}

/* result = a + b (digit strings of equal scale, no sign); returns malloc'd, length in *rn */
Private char* mag_add(const char* a, int an, const char* b, int bn, int* rn) {
  int n = ((an > bn) ? an : bn) + 1;
  char* r = (char*)malloc((size_t)n + 1);
  int carry = 0;
  int i = an - 1;
  int j = bn - 1;
  int k = n - 1;
  while (k >= 0) {
    int s = carry + ((i >= 0) ? a[i--] - '0' : 0) + ((j >= 0) ? b[j--] - '0' : 0);
    r[k--] = (char)('0' + s % 10);
    carry = s / 10;
  }
  *rn = n;
  return r;
}

/* result = a - b where |a| >= |b| */
Private char* mag_sub(const char* a, int an, const char* b, int bn, int* rn) {
  char* r = (char*)malloc((size_t)an + 1);
  int borrow = 0;
  int i = an - 1;
  int j = bn - 1;
  int k = an - 1;
  while (k >= 0) {
    int s = (a[i--] - '0') - borrow - ((j >= 0) ? b[j--] - '0' : 0);
    if (s < 0) {
      s += 10;
      borrow = 1;
    } else {
      borrow = 0;
    }
    r[k--] = (char)('0' + s);
  }
  *rn = an;
  return r;
}

/* Build the result string: sign, integer part, point, fraction, trailing zeros of the fraction dropped */
Private void snum_format(int neg, const char* d, int n, int scale, char* out) {
  int i = 0;
  int ip;
  int fp;
  char* o = out;

  while (i < n - 1 && d[i] == '0' && n - i > scale + 1)
    i++;
  ip = n - i - scale; /* integer digits */
  fp = scale;
  /* trim trailing zeros of the fraction */
  while (fp > 0 && d[n - 1 - (scale - fp)] == '0')
    fp--;
  {
    int nonzero = 0;
    int k;
    for (k = i; k < n; k++)
      if (d[k] != '0')
        nonzero = 1;
    if (neg && nonzero)
      *o++ = '-';
  }
  if (ip <= 0)
    *o++ = '0';
  else {
    memcpy(o, d + i, (size_t)ip);
    o += ip;
  }
  if (fp > 0) {
    int k;
    *o++ = '.';
    for (k = 0; k < fp; k++)
      *o++ = d[i + (ip > 0 ? ip : 0) + k];
  }
  *o = '\0';
}

Private void sarith(int which) { /* 0 add, 1 sub, 2 mul, 3 div, 4 cmp */
  DESCRIPTOR* a_descr = e_stack - 2;
  DESCRIPTOR* b_descr = e_stack - 1;
  char* as;
  char* bs;
  SNUM x;
  SNUM y;
  char* res = NULL;
  int rn = 0;
  int rneg = 0;
  int rscale = 0;
  char* out;
  int cmp;

  bs = top_string_copy(b_descr, NULL);
  as = top_string_copy(a_descr, NULL);
  if (as == NULL || bs == NULL) {
    free(as);
    free(bs);
    k_error("Insufficient memory for string arithmetic");
    return;
  }
  snum_parse(as, &x);
  snum_parse(bs, &y);
  free(as);
  free(bs);

  if (which == 4) { /* compare */
    int sc = (x.scale > y.scale) ? x.scale : y.scale;
    snum_pad(&x, sc);
    snum_pad(&y, sc);
    {
      int xz = (mag_cmp(x.d, x.n, "0", 1) == 0);
      int yz = (mag_cmp(y.d, y.n, "0", 1) == 0);
      if (xz) x.neg = 0;
      if (yz) y.neg = 0;
    }
    if (x.neg != y.neg)
      cmp = x.neg ? -1 : 1;
    else {
      cmp = mag_cmp(x.d, x.n, y.d, y.n);
      if (x.neg)
        cmp = -cmp;
    }
    free(x.d);
    free(y.d);
    k_dismiss();
    k_dismiss();
    InitDescr(e_stack, INTEGER);
    (e_stack++)->data.value = cmp;
    return;
  }

  if (which == 0 || which == 1) {
    int sc = (x.scale > y.scale) ? x.scale : y.scale;
    int yneg = (which == 1) ? !y.neg : y.neg;
    snum_pad(&x, sc);
    snum_pad(&y, sc);
    rscale = sc;
    if (x.neg == yneg) {
      res = mag_add(x.d, x.n, y.d, y.n, &rn);
      rneg = x.neg;
    } else if (mag_cmp(x.d, x.n, y.d, y.n) >= 0) {
      res = mag_sub(x.d, x.n, y.d, y.n, &rn);
      rneg = x.neg;
    } else {
      res = mag_sub(y.d, y.n, x.d, x.n, &rn);
      rneg = yneg;
    }
  } else if (which == 2) {
    int i;
    int j;
    int* t = (int*)calloc((size_t)(x.n + y.n + 1), sizeof(int));
    res = (char*)malloc((size_t)(x.n + y.n + 1));
    for (i = x.n - 1; i >= 0; i--)
      for (j = y.n - 1; j >= 0; j--)
        t[i + j + 1] += (x.d[i] - '0') * (y.d[j] - '0');
    for (i = x.n + y.n - 1; i > 0; i--) {
      t[i - 1] += t[i] / 10;
      t[i] %= 10;
    }
    rn = x.n + y.n;
    for (i = 0; i < rn; i++)
      res[i] = (char)('0' + t[i]);
    free(t);
    rneg = x.neg != y.neg;
    rscale = x.scale + y.scale;
  } else { /* divide: 15 decimal places */
    int sc = (x.scale > y.scale) ? x.scale : y.scale;
    int places = 15;
    char* num;
    int nn;
    char* rem;
    int remn = 0;
    int i;

    snum_pad(&x, sc);
    snum_pad(&y, sc);
    if (mag_cmp(y.d, y.n, "0", 1) == 0) {
      free(x.d);
      free(y.d);
      k_error("Division by zero in SDIV()");
      return;
    }
    nn = x.n + places;
    num = (char*)malloc((size_t)nn + 1);
    memcpy(num, x.d, (size_t)x.n);
    memset(num + x.n, '0', (size_t)places);
    res = (char*)malloc((size_t)nn + 1);
    rem = (char*)calloc((size_t)(y.n + 3), 1);
    rem[0] = '0';
    remn = 1;
    for (i = 0; i < nn; i++) {
      int q = 0;
      char* r2;
      int r2n;
      /* rem = rem * 10 + digit */
      rem = (char*)realloc(rem, (size_t)remn + 2);
      rem[remn++] = num[i];
      while (mag_cmp(rem, remn, y.d, y.n) >= 0) {
        r2 = mag_sub(rem, remn, y.d, y.n, &r2n);
        free(rem);
        rem = r2;
        remn = r2n;
        q++;
      }
      res[i] = (char)('0' + q);
    }
    rn = nn;
    free(num);
    free(rem);
    rneg = x.neg != y.neg;
    rscale = places;
  }

  out = (char*)malloc((size_t)rn + 8);
  snum_format(rneg, res, rn, rscale, out);
  free(res);
  free(x.d);
  free(y.d);
  k_dismiss();
  k_dismiss();
  k_put_c_string(out, e_stack);
  e_stack++;
  free(out);
}

/* EREPLACE(string, old, new {, occurrence {, start}})  (12 Oct 26, openQM item 472, the description the owner supplied).
   With a non-null OLD it is CHANGE() exactly, except that an occurrence count below 1 means all; with a null OLD the
   result is NEW put in front of STRING.  Stack as for op_change(), whose body does the work.                       */
void op_change(void);

void op_ereplace() {
  DESCRIPTOR* d;
  int old_len;
  char* src;
  char* nw;
  char* buf;
  int sl = 0;
  int nl = 0;

  d = e_stack - 4;
  k_get_string(d);
  old_len = (d->data.str.saddr == NULL) ? 0 : (int)d->data.str.saddr->string_len;

  if (old_len > 0) {
    d = e_stack - 2;
    GetInt(d);
    if (d->data.value < 1)
      d->data.value = -1;
    op_change();
    return;
  }

  src = top_string_copy(e_stack - 5, &sl);
  nw = top_string_copy(e_stack - 3, &nl);
  if (src == NULL || nw == NULL) {
    free(src);
    free(nw);
    k_error("Insufficient memory for EREPLACE()");
    return;
  }
  buf = (char*)malloc((size_t)(sl + nl) + 1);
  memcpy(buf, nw, (size_t)nl);
  memcpy(buf + nl, src, (size_t)sl);
  free(src);
  free(nw);
  k_dismiss();
  k_dismiss();
  k_dismiss();
  k_dismiss();
  k_dismiss();
  k_put_string(buf, sl + nl, e_stack);
  e_stack++;
  free(buf);
}

/* FIX(number {, precision {, mode}})  (12 Oct 26, openQM item 472, the description the owner supplied)
   The number as a string with PRECISION decimal places (default: the program's PRECISION), rounded to the nearest
   when MODE is 0 or left out, cut off when MODE is not 0.  Stack: top mode, then precision (-1 = default), number. */
void op_fix() {
  DESCRIPTOR* d;
  int mode;
  int prec;
  double x;
  long double scaled;
  long double p10 = 1.0L;
  int i;
  int neg;
  char buf[96];
  unsigned long long whole;
  unsigned long long ip;
  unsigned long long fp;

  d = e_stack - 1;
  GetInt(d);
  mode = (int)d->data.value;
  d = e_stack - 2;
  GetInt(d);
  prec = (int)d->data.value;
  if (prec < 0)
    prec = process.program.precision;
  if (prec > 14)
    prec = 14;
  d = e_stack - 3;
  GetNum(d);
  x = (d->type == INTEGER) ? (double)d->data.value : d->data.float_value;

  neg = (x < 0);
  if (neg)
    x = -x;
  for (i = 0; i < prec; i++)
    p10 *= 10.0L;
  scaled = (long double)x * p10;
  if (scaled > 1.8e18L) { /* beyond what 64 bits can hold: leave it to the default format */
    snprintf(buf, sizeof(buf), "%.*f", prec, neg ? -x : x);
  } else {
    /* the small epsilon stops 2.675 (really 2.67499999...) rounding the wrong way */
    whole = (unsigned long long)(mode == 0 ? (scaled + 0.5L + 1e-9L * (scaled > 1 ? scaled : 1)) : (scaled + 1e-9L * (scaled > 1 ? scaled : 1)));
    ip = whole;
    fp = 0;
    if (prec > 0) {
      unsigned long long div = 1;
      for (i = 0; i < prec; i++)
        div *= 10ULL;
      ip = whole / div;
      fp = whole % div;
      if (neg && whole != 0)
        snprintf(buf, sizeof(buf), "-%llu.%0*llu", ip, prec, fp);
      else
        snprintf(buf, sizeof(buf), "%llu.%0*llu", ip, prec, fp);
    } else {
      if (neg && whole != 0)
        snprintf(buf, sizeof(buf), "-%llu", ip);
      else
        snprintf(buf, sizeof(buf), "%llu", ip);
    }
  }

  k_dismiss();
  k_dismiss();
  k_dismiss();
  k_put_c_string(buf, e_stack);
  e_stack++;
}

void op_sadd() { sarith(0); }
void op_ssub() { sarith(1); }
void op_smul() { sarith(2); }
void op_sdiv() { sarith(3); }
void op_scmp() { sarith(4); }

void op_regex() {
  /* Stack:   top  pattern        below  string */
  char* pat;
  char* str;
  regex_t re;
  int flags = REG_EXTENDED | REG_NOSUB;
  int rc;
  int result = 0;
  char* p;

  pat = top_string_copy(e_stack - 1, NULL);
  str = top_string_copy(e_stack - 2, NULL);
  if (pat == NULL || str == NULL) {
    free(pat);
    free(str);
    k_error("Insufficient memory for REGEX()");
    return;
  }
  p = pat;
  if (strncmp(p, "(?i)", 4) == 0) {
    flags |= REG_ICASE;
    p += 4;
  }
  rc = regcomp(&re, p, flags);
  if (rc != 0) {
    char msg[200];
    char text[300];
    regerror(rc, &re, msg, sizeof(msg));
    snprintf(text, sizeof(text), "REGEX(): %s", msg);
    free(pat);
    free(str);
    k_error(text);
    return;
  }
  result = (regexec(&re, str, 0, NULL, 0) == 0) ? 1 : 0;
  regfree(&re);
  free(pat);
  free(str);
  k_dismiss();
  k_dismiss();
  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = result;
}

/* END-CODE */
