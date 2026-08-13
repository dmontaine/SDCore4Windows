/* CTYPE.C
 * Character type handling and associated functions.
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
 * START-HISTORY 
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * This module replaces all the standard casing and character type functions
 * to enable support of user defined collation sequences and upper/lower case
 * pairing rules. By encapsulating all these functions here, future changes
 * should be relatively easy to implement.
 *
 * Although the C library provides locale support functions, these are not
 // * immediately applicable here because Q_M requires binary transparency and
 * the ability to sort right justified strings (amongst other problems).
 *
 * It is likely that Q_M will be adapted to support Unicode and all the
 * associated locale related operations in the long term future.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"

Private char* CNullString(void);

/* ======================================================================
   Set default_character maps                                             */

void set_default_character_maps() {
  int i;
  int j;
  for (i = 0; i < 256; i++) {
    uc_chars[i] = (char)i;
    lc_chars[i] = (char)i;
    char_types[i] = 0;
  }

  for (i = 'a', j = 'A'; i <= 'z'; i++, j++) {
    uc_chars[i] = j;
    lc_chars[j] = i;
    char_types[i] |= CT_ALPHA;
    char_types[j] |= CT_ALPHA;
  }

  for (i = '0'; i <= '9'; i++) {
    char_types[i] |= CT_DIGIT;
  }

  for (i = 33; i <= 126; i++) {
    char_types[i] |= CT_GRAPH;
  }

  char_types[U_TEXT_MARK] |= CT_MARK;
  char_types[U_SUBVALUE_MARK] |= CT_MARK | CT_DELIM;
  char_types[U_VALUE_MARK] |= CT_MARK | CT_DELIM;
  char_types[U_FIELD_MARK] |= CT_MARK | CT_DELIM;
  char_types[U_ITEM_MARK] |= CT_MARK;
}

/* ======================================================================
   LowerCaseString()  -  Convert string to lower case                     */

char* LowerCaseString(char* s) {
  char* p;

  p = s;
  while ((*(p++) = LowerCase(*p)) != '\0') {
  }
  return s;
}

/* ======================================================================
   MemCompareNoCase()  -  Case insensitive variant of memcmp              */

int MemCompareNoCase(char* p, char* q, int16_t len) {
  signed char c;

  while (len--) {
    if ((c = UpperCase(*p) - UpperCase(*q)) != 0)
      return c;
    p++;
    q++;
  }

  return 0;
}

/* ======================================================================
   memichr()  -  Case insensitive variant of memchr()                     */

char* memichr(char* s, char c, int n) {
  c = UpperCase(c);

  while (n--) {
    if (UpperCase(*s) == c)
      return s;
    s++;
  }

  return NULL;
}

/* ======================================================================
   memucpy()  -  Copy a specified number of bytes, converting to uppercase */

void memucpy(char* tgt, char* src, int16_t len) {
  while (len--)
    *(tgt++) = UpperCase(*(src++));
}

/* ======================================================================
   StringCompLenNoCase()  -  Case insensitive variant of strncmp          */

int StringCompLenNoCase(char* p, char* q, int16_t len) {
  register char c;

  while (len--) {
    if (((c = UpperCase(*p) - UpperCase(*q)) != 0) || (*p == '\0') ||
        (*q == '\0'))
      return c;
    p++;
    q++;
  }

  return 0;
}

/* ======================================================================
   UpperCaseMem()  -  Uppercase specified number of bytes                 */

void UpperCaseMem(char* str, int16_t len) {
  register char c;

  while (len--) {
    c = UpperCase(*str);
    *(str++) = c;
  }
}

/* ======================================================================
   UpperCaseString()  -  Convert string to upper case                     */

char* UpperCaseString(char* s) {
  char* p;

  p = s;
  while ((*p = UpperCase(*p)) != '\0') {
    p++;
  }

  return s;
}

/* ======================================================================
   Dcount()  -  Count fields, values or subvalues                       
   copied from qmclilib.c                                              */

int Dcount(char* src, char* delim_str) {
  int32_t src_len;
  char* p;
  int32_t ct = 0;
  char delim;

  if (strlen(delim_str) != 0) {
    delim = *delim_str;

    src_len = strlen(src);
    if (src_len != 0) {
      ct = 1;
      while ((p = memchr(src, delim, src_len)) != NULL) {
        src_len -= (1 + p - src);
        src = p + 1;
        ct++;
      }
    }
  }

  return ct;
}

/* ======================================================================
   Extract()  -  Extract field, value or subvalue                      
   copied from qmclilib.c                                              */

char* Extract(char* src, int fno, int vno, int svno) {
  int32_t src_len;
  char* p;
  char* result;

  src_len = strlen(src);
  if (src_len == 0)
    goto null_result; /* Extracting from null string */

  /* Setp 1  -  Initialise variables */

  if (fno < 1)
    fno = 1;

  /* Step 2  -  Position to start of item */

  /* Skip to start field */

  while (--fno) {
    p = memchr(src, FIELD_MARK, src_len);
    if (p == NULL)
      goto null_result; /* No such field */
    src_len -= (1 + p - src);
    src = p + 1;
  }
  p = memchr(src, FIELD_MARK, src_len);
  if (p != NULL)
    src_len = p - src; /* Adjust to ignore later fields */

  if (vno < 1)
    goto done; /* Extracting whole field */

  /* Skip to start value */

  while (--vno) {
    p = memchr(src, VALUE_MARK, src_len);
    if (p == NULL)
      goto null_result; /* No such value */
    src_len -= (1 + p - src);
    src = p + 1;
  }

  p = memchr(src, VALUE_MARK, src_len);
  if (p != NULL)
    src_len = p - src; /* Adjust to ignore later values */

  if (svno < 1)
    goto done; /* Extracting whole value */

  /* Skip to start subvalue */

  while (--svno) {
    p = memchr(src, SUBVALUE_MARK, src_len);
    if (p == NULL)
      goto null_result; /* No such subvalue */
    src_len -= (1 + p - src);
    src = p + 1;
  }
  p = memchr(src, SUBVALUE_MARK, src_len);
  if (p != NULL)
    src_len = p - src; /* Adjust to ignore later fields */

done:
  result = malloc(src_len + 1);
  /* Modified by Composer AI - 2026/06/10.
     malloc() can fail; return the empty-string helper instead of
     passing NULL to memcpy(). */
  if (result == NULL)
    return CNullString();
  /* -------------------- */
  memcpy(result, src, src_len);
  result[src_len] = '\0';
  return result;

null_result:
  return CNullString();
}


Private char* CNullString() {
  char* p;
  static char empty[1] = {'\0'};

  /* Modified by Composer AI - 2026/06/10.
     malloc(1) can fail; return a static empty string instead. */
  /* p = malloc(1);
  *p = '\0';
  return p; */
  p = malloc(1);
  if (p == NULL)
    return empty;
  *p = '\0';
  return p;
  /* -------------------- */
}

/* END-CODE */
