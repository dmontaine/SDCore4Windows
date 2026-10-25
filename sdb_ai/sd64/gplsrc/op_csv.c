/* OP_CSV.C
 * CSV text: FORMCSV(), the dequoting of a CSV line, CSV.MODE's quote and escape characters, CSVPARSE() and CSVBUILD()
 * Copyright (c) 2026 SD Core for Linux
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
 * 20 Oct 26 dm  New.  The owner's CSV / JSON / XML task.  FORMCSV() moves here from the BASIC program _formcsv (so that a statement can
 *               name its own delimiter, quote and escape characters, and so that a field holding a line break is enclosed);
 *               CSVDQ() takes a quote and an escape character; CSV.MODE keeps a quote and an escape character; CSVPARSE() reads a
 *               whole CSV text, quoted line breaks included, into a data collection or a dynamic array and CSVBUILD() writes
 *               one back, with a header row.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *    A CSV dialect is three characters: the delimiter (a comma), the quote (a double quote) and an escape character (none).
 *    The program's own setting is process.program.csv_delim / csv_quote / csv_esc, which CSV.MODE sets and a called program
 *    inherits.  A field is enclosed in quotes when it must be (mode 1: it holds a quote, the delimiter, a carriage return or
 *    a line feed, or the escape character; mode 2: it is not empty and not a number; mode 3: always).  Inside an enclosed
 *    field the quote is written twice, or, when an escape character is set, once with the escape character before it (and
 *    the escape character itself is doubled that way).  A reader takes either form.
 *
 *    XF_FORMCSVX  FORMCSV(item, delim, quote, esc)   one item, or the items of a field mark delimited array, as a CSV line
 *    XF_CSVDQX    CSVDQ(line, delim, quote, esc)     a CSV line as the items of a field mark delimited array
 *    XF_CSVQESC   CSV.MODE's third and fourth operands
 *    XF_CSVPARSE  CSVPARSE(text, mode, dialect)      text -> collection (or dynamic array)
 *    XF_CSVBUILD  CSVBUILD(c, mode, dialect)         collection (or dynamic array) -> text
 *
 *    "dialect" is a string of up to three characters: the delimiter, the quote and the escape character.  A character left
 *    out is the default (the quote) or none (the escape character).
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <ctype.h>
#include <errno.h>
#include <string.h>
#include "sd.h"
#include "header.h"
#include "err.h"
#include "keys.h"
#include "options.h"

#define CSV_TAG 161

/* The CSVPARSE() and CSVBUILD() mode bits, as keys.h names them */
#define CSV_HEADER 1    /* first row names the columns; CSVBUILD writes a header row */
#define CSV_NUMBER 2    /* CSVPARSE: a field that is a number becomes one */
#define CSV_DYNAMIC 4   /* a dynamic array (rows by field mark, fields by value mark) instead of a collection */
#define CSV_KEEPBLANK 8 /* CSVPARSE: a blank line is a row of one empty field instead of being skipped */
#define CSV_NOHEADER 16 /* CSVBUILD: no header row even for rows that are named */
#define CSV_CRLF 32     /* CSVBUILD: lines end with carriage return and line feed (the default is a line feed) */
#define CSV_QUOTE2 64   /* CSVBUILD: enclose every field that is not a number */
#define CSV_QUOTE3 128  /* CSVBUILD: enclose every field */

typedef struct {
  char delim;
  char quote;
  char esc; /* 0 for none */
} CSVD;

typedef struct {
  char* b;
  int32_t len;
  int32_t cap;
} FB;

DESCRIPTOR coll_str_descr(char* s, int32_t len);
char* coll_chunks_to_buffer(STRING_CHUNK* s, int32_t* len);
int32_t coll_number_len(unsigned char* s, int32_t len, bool* is_int);

/* ----------------------------------------------------------------------
   A growing buffer                                                       */

Private void fb_init(FB* f) {
  f->cap = 256;
  f->len = 0;
  f->b = (char*)k_alloc(CSV_TAG, f->cap);
}

Private void fb_add(FB* f, const char* s, int32_t n) {
  if (f->len + n + 1 > f->cap) {
    int32_t nc = f->cap * 2;
    char* nb;

    while (nc < f->len + n + 1)
      nc *= 2;
    nb = (char*)k_alloc(CSV_TAG, nc);
    memcpy(nb, f->b, f->len);
    k_free(f->b);
    f->b = nb;
    f->cap = nc;
  }
  memcpy(f->b + f->len, s, n);
  f->len += n;
}

Private void fb_addc(FB* f, char c) {
  fb_add(f, &c, 1);
}

Private void fb_free(FB* f) {
  if (f->b != NULL)
    k_free(f->b);
  f->b = NULL;
}

/* ----------------------------------------------------------------------
   The dialect                                                            */

Private void csvd_state(CSVD* d) {
  d->delim = process.program.csv_delim;
  d->quote = process.program.csv_quote;
  d->esc = process.program.csv_esc;
}

Private void csvd_default(CSVD* d) {
  d->delim = ',';
  d->quote = '"';
  d->esc = 0;
}

/* Take the characters of a dialect string.  False if the dialect cannot work: the same character in two places, or a line
   break or a mark in any. */

Private bool csvd_from_string(CSVD* d, char* s, int32_t len) {
  if (len > 0 && s[0] != '\0')
    d->delim = s[0];
  if (len > 1 && s[1] != '\0')
    d->quote = s[1];
  if (len > 2)
    d->esc = s[2];
  if (d->delim == d->quote || d->delim == '\n' || d->delim == '\r' || d->quote == '\n' || d->quote == '\r')
    return FALSE;
  if (d->esc != 0 && (d->esc == d->delim || d->esc == d->quote || d->esc == '\n' || d->esc == '\r'))
    return FALSE;
  return TRUE;
}

/* A number, as NUM() sees one */

Private bool csv_is_num(const char* s, int32_t len) {
  bool sign = FALSE, dp = FALSE, digit_seen = FALSE;
  int digits = 0;
  int exp_state = 0;
  bool exp_sign = FALSE;
  int exp_val = 0;
  int32_t i;
  char c;

  for (i = 0; i < len; i++) {
    c = s[i];
    if (exp_state) {
      if (c >= '0' && c <= '9') {
        exp_val = exp_val * 10 + (c - '0');
        if (exp_val > 308)
          return FALSE;
        exp_state = 2;
      } else if (exp_state == 1 && !exp_sign && (c == '+' || c == '-')) {
        exp_sign = TRUE;
      } else {
        return FALSE;
      }
      continue;
    }
    if (c >= '0' && c <= '9') {
      digit_seen = TRUE;
      if (!dp && ++digits > 15)
        return FALSE;
    } else {
      switch (c) {
        case '+':
        case '-':
          if (digits || sign)
            return FALSE;
          sign = TRUE;
          break;
        case '.':
          if (dp)
            return FALSE;
          dp = TRUE;
          digits++;
          break;
        case 'E':
        case 'e':
          if (!Option(OptNumericExponent) || !digit_seen)
            return FALSE;
          exp_state = 1;
          break;
        default:
          return FALSE;
      }
    }
  }
  return digit_seen && exp_state != 1;
}

/* ----------------------------------------------------------------------
   One field, enclosed when it must be                                    */

Private void csv_put_field(FB* out, const char* s, int32_t len, int mode, CSVD* d) {
  bool enclose;
  int32_t i;

  switch (mode) {
    case 3:
      enclose = TRUE;
      break;
    case 2:
      enclose = (len > 0 && (!csv_is_num(s, len) || memchr(s, d->delim, len) != NULL || memchr(s, d->quote, len) != NULL));
      break;
    default:
      enclose = (memchr(s, d->quote, len) != NULL || memchr(s, d->delim, len) != NULL || memchr(s, '\n', len) != NULL ||
                 memchr(s, '\r', len) != NULL || (d->esc != 0 && memchr(s, d->esc, len) != NULL));
      break;
  }
  if (!enclose) {
    fb_add(out, s, len);
    return;
  }
  fb_addc(out, d->quote);
  for (i = 0; i < len; i++) {
    if (s[i] == d->quote) {
      if (d->esc != 0)
        fb_addc(out, d->esc);
      else
        fb_addc(out, d->quote);
    } else if (d->esc != 0 && s[i] == d->esc) {
      fb_addc(out, d->esc);
    }
    fb_addc(out, s[i]);
  }
  fb_addc(out, d->quote);
}

/* The items of a field mark delimited string as one CSV line: the descriptor is replaced by the line.  A null string is one
   empty item: nothing, or an enclosed empty item in mode 3 (the BASIC program this replaced said a null string was no items
   and gave a null line even in mode 3, which the documentation of mode 3 - "always, an empty one too" - did not promise). */

Private void csv_format_descr(DESCRIPTOR* d, int mode, CSVD* cd) {
  char* s;
  int32_t len;
  int32_t start = 0;
  int32_t i;
  FB out;

  k_get_string(d);
  s = coll_chunks_to_buffer(d->data.str.saddr, &len);
  fb_init(&out);
  for (i = 0; i <= len; i++) {
    if (i == len || s[i] == FIELD_MARK) {
      csv_put_field(&out, s + start, i - start, mode, cd);
      if (i < len)
        fb_addc(&out, cd->delim);
      start = i + 1;
    }
  }
  k_release(d);
  *d = coll_str_descr(out.b, out.len);
  fb_free(&out);
  k_free(s);
}

/* ======================================================================
   op_formcsv()  -  FORMCSV()  -  The item(s) as a CSV line, as CSV.MODE has set the rules        */

void op_formcsv() {
  CSVD cd;

  csvd_state(&cd);
  csv_format_descr(e_stack - 1, process.program.csv_mode, &cd);
}

/* The one character of a descriptor, a default when it is null */

Private char one_char(DESCRIPTOR* d, char dflt) {
  char t[4];

  t[0] = '\0';
  k_get_c_string(d, t, 1);
  return (t[0] != '\0') ? t[0] : dflt;
}

/* XF_FORMCSVX: [item, delim, quote, esc] -> the line.  The delimiter, quote and escape character are the statement's own. */

void x_formcsvx() {
  CSVD cd;

  csvd_state(&cd);
  cd.delim = one_char(e_stack - 3, cd.delim);
  cd.quote = one_char(e_stack - 2, cd.quote);
  cd.esc = one_char(e_stack - 1, cd.esc);
  if (cd.esc == cd.quote || cd.esc == cd.delim || cd.quote == cd.delim)
    cd.esc = 0;
  k_dismiss();
  k_dismiss();
  k_dismiss();
  csv_format_descr(e_stack - 1, process.program.csv_mode, &cd);
}

/* XF_CSVQESC: [quote, esc] (CSV.MODE's third and fourth operands).  A null quote is the double quote and a null escape
   character is none; a quote that is the delimiter, or an escape character that is the quote or the delimiter, is ignored. */

void x_csvqesc() {
  char q = one_char(e_stack - 2, '"');
  char e = one_char(e_stack - 1, 0);

  k_dismiss();
  k_dismiss();
  if (q == process.program.csv_delim || q == '\n' || q == '\r')
    q = '"';
  if (e == q || e == process.program.csv_delim || e == '\n' || e == '\r')
    e = 0;
  process.program.csv_quote = q;
  process.program.csv_esc = e;
}

/* ======================================================================
   csvdq_core()  -  A CSV line as the items of a field mark delimited array

   The descriptor on top of the stack is the line, and is replaced by the items.  The rules are the ones CSVDQ() has always had
   (a quote at the start of an item opens it, two together inside it are one, one that is not followed by another ends it), with
   the quote the dialect names and, when it names an escape character, that character before any character inside an enclosed
   item meaning that character as it stands.                                                                               */

Private void csvdq_core(DESCRIPTOR* src_descr, CSVD* cd) {
  STRING_CHUNK* src;
  STRING_CHUNK* result = NULL;
  int16_t bytes;
  char* p;
  char c;
  bool first = TRUE;
  bool quoted = FALSE;
  bool last_char_was_quote = FALSE;
  bool skip_escaped = FALSE;

  GetString(src_descr);
  if ((src = src_descr->data.str.saddr) == NULL)
    return;
  ts_init(&result, src->string_len);
  do {
    bytes = src->bytes;
    p = src->data;
    while (bytes--) {
      c = *(p++);
      if (skip_escaped) {
        ts_copy_byte(c);
        skip_escaped = FALSE;
        continue;
      }
      if (quoted && !last_char_was_quote && cd->esc != 0 && c == cd->esc) {
        skip_escaped = TRUE;
        continue;
      }
      if (c == cd->quote) {
        if (first) {
          quoted = TRUE;
        } else if (last_char_was_quote) {
          ts_copy_byte(c); /* a doubled quote is one */
          last_char_was_quote = FALSE;
        } else {
          last_char_was_quote = TRUE; /* remember it, copy nothing */
        }
        first = FALSE;
      } else if (c == cd->delim) {
        if (quoted && !last_char_was_quote) {
          ts_copy_byte(c);
        } else {
          ts_copy_byte(FIELD_MARK);
          first = TRUE;
          last_char_was_quote = FALSE;
          quoted = FALSE;
        }
      } else {
        last_char_was_quote = FALSE; /* a format error such as "ab"cd" */
        ts_copy_byte(c);
        first = FALSE;
      }
    }
  } while ((src = src->next) != NULL);
  ts_terminate();
  k_release(src_descr);
  InitDescr(src_descr, STRING);
  src_descr->data.str.saddr = result;
}

/* The OP.CSVDQ opcode is in op_str5.c and takes [line, delimiter]; it calls this with the quote and escape character of a
   comma separated file. */

void csv_dequote(DESCRIPTOR* src_descr, char delim) {
  CSVD cd;

  cd.delim = delim;
  cd.quote = '"';
  cd.esc = 0;
  csvdq_core(src_descr, &cd);
}

/* XF_CSVDQX: [line, delim, quote, esc] */

void x_csvdqx() {
  CSVD cd;

  csvd_default(&cd);
  cd.delim = one_char(e_stack - 3, ',');
  cd.quote = one_char(e_stack - 2, '"');
  cd.esc = one_char(e_stack - 1, 0);
  if (cd.quote == cd.delim)
    cd.quote = '"';
  if (cd.esc == cd.quote || cd.esc == cd.delim)
    cd.esc = 0;
  k_dismiss();
  k_dismiss();
  k_dismiss();
  csvdq_core(e_stack - 1, &cd);
}

/* ======================================================================
   CSVPARSE()

   The text is read by the rules of RFC 4180 with the dialect's characters: a field that starts with the quote runs to the
   quote that closes it (two together inside it are one quote; with an escape character, that character and the one after it
   are the one after it), whatever it holds, a line break too; a quote inside a field that did not start with one is data.
   A line ends at a line feed, a carriage return or both.  A line with nothing on it is skipped unless CSV_KEEPBLANK.  A quote that
   is never closed is an error (ER_PARSE_ERROR, INMAT() the position of the quote that opened it).                            */

typedef struct {
  char* s;
  int32_t n;
  int32_t pos;
} CSVSRC;

/* Read the next field into cell.  Returns 1 when a field was read and a delimiter follows it, 2 when a field was read and a line
   ended or the text did (the row is complete; the text ending straight after a delimiter is an empty last field).  -1 for an
   unclosed quote (err_pos set). */

Private int csv_next_field(CSVSRC* sp, CSVD* d, FB* cell, int32_t* err_pos, bool* was_quoted) {
  int32_t i = sp->pos;
  char c;

  cell->len = 0;
  *was_quoted = FALSE;
  if (i >= sp->n)
    return 2;
  if (sp->s[i] == d->quote) {
    int32_t open_at = i;

    *was_quoted = TRUE;
    i++;
    for (;;) {
      if (i >= sp->n) {
        *err_pos = open_at + 1;
        return -1;
      }
      c = sp->s[i];
      if (d->esc != 0 && c == d->esc && i + 1 < sp->n) {
        fb_addc(cell, sp->s[i + 1]);
        i += 2;
      } else if (c == d->quote) {
        if (i + 1 < sp->n && sp->s[i + 1] == d->quote) {
          fb_addc(cell, d->quote);
          i += 2;
        } else {
          i++;
          break;
        }
      } else {
        fb_addc(cell, c);
        i++;
      }
    }
    /* Anything between the closing quote and the delimiter is kept as it stands */
    while (i < sp->n && sp->s[i] != d->delim && sp->s[i] != '\n' && sp->s[i] != '\r') {
      fb_addc(cell, sp->s[i]);
      i++;
    }
  } else {
    while (i < sp->n && sp->s[i] != d->delim && sp->s[i] != '\n' && sp->s[i] != '\r') {
      fb_addc(cell, sp->s[i]);
      i++;
    }
  }
  if (i < sp->n && sp->s[i] == d->delim) {
    sp->pos = i + 1;
    return 1;
  }
  if (i < sp->n) { /* a line break: take CR LF as one */
    if (sp->s[i] == '\r' && i + 1 < sp->n && sp->s[i + 1] == '\n')
      i++;
    i++;
  }
  sp->pos = i;
  return 2;
}

/* XF_CSVOPEN: [line, delim, quote, esc] -> 1 when the line ends inside an enclosed field, so that the row goes on on the next line,
   else 0.  READCSV reads its logical row with it (!readcsvrow).  A quote is only an opening quote at the start of a field. */

void x_csvopen() {
  CSVD cd;
  CSVSRC src;
  FB cell;
  char* text;
  int32_t tlen;
  int32_t err_pos = 0;
  bool was_quoted;
  int r;
  int32_t open = 0;
  DESCRIPTOR* line_d;

  csvd_default(&cd);
  cd.delim = one_char(e_stack - 3, ',');
  cd.quote = one_char(e_stack - 2, '"');
  cd.esc = one_char(e_stack - 1, 0);
  if (cd.quote == cd.delim)
    cd.quote = '"';
  if (cd.esc == cd.quote || cd.esc == cd.delim)
    cd.esc = 0;
  k_dismiss();
  k_dismiss();
  k_dismiss();
  line_d = e_stack - 1;
  k_get_string(line_d);
  text = coll_chunks_to_buffer(line_d->data.str.saddr, &tlen);
  src.s = text;
  src.n = tlen;
  src.pos = 0;
  fb_init(&cell);
  if (tlen > 0) {
    do {
      r = csv_next_field(&src, &cd, &cell, &err_pos, &was_quoted);
    } while (r == 1);
    if (r < 0)
      open = 1;
  }
  fb_free(&cell);
  k_free(text);
  k_release(line_d);
  InitDescr(line_d, INTEGER);
  line_d->data.value = open;
}

/* A field as a descriptor: a string, or a number when CSV_NUMBER is set and it is one in the JSON sense */

Private DESCRIPTOR csv_cell(FB* cell, int mode) {
  DESCRIPTOR r;
  bool is_int;
  int32_t n;

  if ((mode & CSV_NUMBER) && cell->len > 0 && cell->len < 60) {
    n = coll_number_len((unsigned char*)cell->b, cell->len, &is_int);
    if (n == cell->len) {
      char tmp[64];

      memcpy(tmp, cell->b, n);
      tmp[n] = '\0';
      if (is_int) {
        errno = 0;
        long v = strtol(tmp, NULL, 10);
        if (errno == 0 && v >= -2147483647L && v <= 2147483647L) {
          InitDescr(&r, INTEGER);
          r.data.value = (int32_t)v;
          return r;
        }
      }
      InitDescr(&r, FLOATNUM);
      r.data.float_value = strtod(tmp, NULL);
      return r;
    }
  }
  return coll_str_descr(cell->b, cell->len);
}

/* Name an object's element.  The name is the caller's text and is copied. */

Private COLL_ENTRY* obj_slot(COLL_HEADER* h, const char* name, int32_t len) {
  int32_t pos;
  COLL_ENTRY* e;

  if (coll_find(h, (char*)name, len, &pos)) {
    e = &h->e[pos];
    k_release(&e->d);
    InitDescr(&e->d, STRING);
    e->d.data.str.saddr = NULL;
    e->tag = CT_PLAIN;
    return e;
  }
  coll_insert(h, pos);
  e = &h->e[pos];
  e->name = (char*)k_alloc(CSV_TAG, len + 1);
  memcpy(e->name, name, len);
  e->name[len] = '\0';
  e->name_len = len;
  return e;
}

Private COLL_ENTRY* arr_slot(COLL_HEADER* h) {
  coll_insert(h, h->count);
  return &h->e[h->count - 1];
}

Private DESCRIPTOR coll_descr(COLL_HEADER* h) {
  DESCRIPTOR d;

  InitDescr(&d, COLL);
  d.data.coll = h;
  return d;
}

Private DESCRIPTOR null_descr(void) {
  DESCRIPTOR d;

  InitDescr(&d, STRING);
  d.data.str.saddr = NULL;
  return d;
}

/* The text as a dynamic array: rows by field mark, fields by value mark (a mark in the data is left as it is) */

Private bool csv_parse_dynamic(CSVSRC* sp, CSVD* d, int mode, FB* outb, int32_t* err_pos) {
  FB cell;
  int r;
  int fields = 0;
  bool was_quoted;
  bool first_row = TRUE;

  fb_init(&cell);
  while (sp->pos < sp->n) {
    if (!(mode & CSV_KEEPBLANK) && (sp->s[sp->pos] == '\n' || sp->s[sp->pos] == '\r')) {
      if (sp->s[sp->pos] == '\r' && sp->pos + 1 < sp->n && sp->s[sp->pos + 1] == '\n')
        sp->pos++;
      sp->pos++;
      continue;
    }
    if (!first_row)
      fb_addc(outb, FIELD_MARK);
    first_row = FALSE;
    fields = 0;
    for (;;) {
      r = csv_next_field(sp, d, &cell, err_pos, &was_quoted);
      if (r < 0) {
        fb_free(&cell);
        return FALSE;
      }
      if (fields++ > 0)
        fb_addc(outb, VALUE_MARK);
      fb_add(outb, cell.b, cell.len);
      if (r != 1)
        break;
    }
  }
  fb_free(&cell);
  return TRUE;
}

/* The text as a collection.  Without CSV_HEADER an array of arrays; with it an object { "columns": [names], "rows": [objects] }
   so that the order of the columns, which an object does not keep, is kept. */

Private bool csv_parse_coll(CSVSRC* sp, CSVD* d, int mode, DESCRIPTOR* result, int32_t* err_pos) {
  COLL_HEADER* top;
  COLL_HEADER* rows;
  COLL_HEADER* cols = NULL;
  COLL_HEADER* row;
  COLL_ENTRY* slot;
  FB cell;
  int r;
  int ncols = 0;
  int field;
  bool was_quoted;
  bool header = (mode & CSV_HEADER) != 0;
  bool first = TRUE;
  char nm[32];

  fb_init(&cell);
  rows = coll_new(TRUE);
  if (header) {
    top = coll_new(FALSE);
    cols = coll_new(TRUE);
  } else {
    top = rows;
  }

  while (sp->pos < sp->n) {
    if (!(mode & CSV_KEEPBLANK) && (sp->s[sp->pos] == '\n' || sp->s[sp->pos] == '\r')) {
      if (sp->s[sp->pos] == '\r' && sp->pos + 1 < sp->n && sp->s[sp->pos + 1] == '\n')
        sp->pos++;
      sp->pos++;
      continue;
    }
    if (header && first) {
      /* the header row: the names, kept in order */
      field = 0;
      for (;;) {
        r = csv_next_field(sp, d, &cell, err_pos, &was_quoted);
        if (r < 0)
          goto fail;
        field++;
        if (cell.len == 0) { /* a column with no name is called _n for its place */
          int nl = snprintf(nm, sizeof nm, "_%d", field);

          fb_add(&cell, nm, nl);
        }
        slot = arr_slot(cols);
        slot->d = coll_str_descr(cell.b, cell.len);
        if (r != 1)
          break;
      }
      ncols = field;
      first = FALSE;
      continue;
    }
    first = FALSE;
    if (header) {
      row = coll_new(FALSE);
      slot = arr_slot(rows);
      slot->d = coll_descr(row);
    } else {
      row = coll_new(TRUE);
      slot = arr_slot(rows);
      slot->d = coll_descr(row);
    }
    field = 0;
    for (;;) {
      r = csv_next_field(sp, d, &cell, err_pos, &was_quoted);
      if (r < 0)
        goto fail;
      field++;
      if (header) {
        int32_t nlen;

        if (field <= ncols) {
          COLL_ENTRY* ce = &cols->e[field - 1];
          char* cb = coll_chunks_to_buffer(ce->d.data.str.saddr, &nlen);
          slot = obj_slot(row, cb, nlen);
          k_free(cb);
        } else {
          nlen = snprintf(nm, sizeof nm, "_%d", field);
          slot = obj_slot(row, nm, nlen);
        }
        slot->d = csv_cell(&cell, mode);
      } else {
        slot = arr_slot(row);
        slot->d = csv_cell(&cell, mode);
      }
      if (r != 1)
        break;
    }
    if (header) {
      /* a short row has the missing columns as empty strings */
      int k;

      for (k = field + 1; k <= ncols; k++) {
        int32_t nlen, pos;
        COLL_ENTRY* ce = &cols->e[k - 1];
        char* cb = coll_chunks_to_buffer(ce->d.data.str.saddr, &nlen);

        if (!coll_find(row, cb, nlen, &pos)) { /* a name used twice keeps the value it was given */
          slot = obj_slot(row, cb, nlen);
          slot->d = null_descr();
        }
        k_free(cb);
      }
    }
  }
  fb_free(&cell);
  if (header) {
    slot = obj_slot(top, "columns", 7);
    slot->d = coll_descr(cols);
    slot = obj_slot(top, "rows", 4);
    slot->d = coll_descr(rows);
  }
  *result = coll_descr(top);
  return TRUE;

fail:
  fb_free(&cell);
  {
    DESCRIPTOR t = coll_descr(top);

    k_release(&t);
    if (header) {
      /* rows and cols are not yet in top when it was just made */
      t = coll_descr(rows);
      k_release(&t);
      t = coll_descr(cols);
      k_release(&t);
    }
  }
  return FALSE;
}

/* XF_CSVPARSE: [text, mode, dialect] -> a collection, or a dynamic array under CSV_DYNAMIC, or a null string with STATUS() set */

void x_csvparse() {
  DESCRIPTOR* dial_d = e_stack - 1;
  DESCRIPTOR* mode_d = e_stack - 2;
  DESCRIPTOR* text_d = e_stack - 3;
  CSVD cd;
  CSVSRC src;
  int mode;
  char* dial;
  int32_t dlen;
  char* text;
  int32_t tlen;
  int32_t err_pos = 0;
  DESCRIPTOR result;
  bool ok;

  GetInt(mode_d);
  mode = mode_d->data.value;
  k_get_string(dial_d);
  k_get_string(text_d);
  dial = coll_chunks_to_buffer(dial_d->data.str.saddr, &dlen);
  text = coll_chunks_to_buffer(text_d->data.str.saddr, &tlen);
  csvd_default(&cd);
  process.status = 0;
  result = null_descr();
  if (!csvd_from_string(&cd, dial, dlen)) {
    process.status = ER_PARAMS;
    goto done;
  }
  src.s = text;
  src.n = tlen;
  src.pos = 0;
  if (mode & CSV_DYNAMIC) {
    FB out;

    fb_init(&out);
    ok = csv_parse_dynamic(&src, &cd, mode, &out, &err_pos);
    if (ok)
      result = coll_str_descr(out.b, out.len);
    fb_free(&out);
  } else {
    ok = csv_parse_coll(&src, &cd, mode, &result, &err_pos);
  }
  if (!ok) {
    process.status = ER_PARSE_ERROR;
    process.inmat = err_pos;
    result = null_descr();
  }
done:
  k_free(dial);
  k_free(text);
  k_dismiss(); /* dialect */
  k_pop(1);    /* mode */
  k_dismiss(); /* text */
  *(e_stack++) = result;
}

/* ======================================================================
   CSVBUILD()                                                             */

/* The text of a value as a CSV field.  False for a value a CSV field cannot hold (a collection). */

Private bool csv_value_text(COLL_ENTRY* e, FB* tmp) {
  DESCRIPTOR t;
  char* s;
  int32_t len;

  tmp->len = 0;
  if (e->tag == CT_NULL)
    return TRUE;
  if (e->d.type == COLL)
    return FALSE;
  if (e->tag == CT_BOOL) {
    fb_add(tmp, e->d.data.value ? "true" : "false", e->d.data.value ? 4 : 5);
    return TRUE;
  }
  if (e->d.type == UNASSIGNED)
    return TRUE;
  t = e->d;
  t.flags = 0;
  IncrRefCt(&t);
  GetString(&t);
  if (t.data.str.saddr != NULL) {
    s = coll_chunks_to_buffer(t.data.str.saddr, &len);
    fb_add(tmp, s, len);
    k_free(s);
  }
  k_release(&t);
  return TRUE;
}

Private void csv_put_eol(FB* out, int mode) {
  if (mode & CSV_CRLF)
    fb_addc(out, '\r');
  fb_addc(out, '\n');
}

/* Collect the names an array of objects uses, in order of name: the union over all its rows */

Private void csv_union_names(COLL_HEADER* rows, COLL_HEADER* names) {
  int32_t i, j, pos;
  COLL_HEADER* r;
  COLL_ENTRY* slot;

  for (i = 0; i < rows->count; i++) {
    if (rows->e[i].d.type != COLL)
      continue;
    r = rows->e[i].d.data.coll;
    if (r->is_array)
      continue;
    for (j = 0; j < r->count; j++) {
      if (!coll_find(names, r->e[j].name, r->e[j].name_len, &pos)) {
        coll_insert(names, pos);
        slot = &names->e[pos];
        slot->name = (char*)k_alloc(CSV_TAG, r->e[j].name_len + 1);
        memcpy(slot->name, r->e[j].name, r->e[j].name_len);
        slot->name[r->e[j].name_len] = '\0';
        slot->name_len = r->e[j].name_len;
      }
    }
  }
}

/* x_csvbuild: [c, mode, dialect] -> text.  c is an array of rows (arrays of values or objects), the object CSVPARSE() makes
   for CSV_HEADER ({columns, rows}), or, under CSV_DYNAMIC, a dynamic array. */

void x_csvbuild() {
  DESCRIPTOR* dial_d = e_stack - 1;
  DESCRIPTOR* mode_d = e_stack - 2;
  DESCRIPTOR* src_d = e_stack - 3;
  CSVD cd;
  int mode;
  int fmode;
  char* dial;
  int32_t dlen;
  FB out, tmp;
  DESCRIPTOR result;
  int32_t i, j;
  bool ok = TRUE;

  GetInt(mode_d);
  mode = mode_d->data.value;
  k_get_string(dial_d);
  dial = coll_chunks_to_buffer(dial_d->data.str.saddr, &dlen);
  csvd_state(&cd);
  process.status = 0;
  fmode = process.program.csv_mode;
  if (mode & CSV_QUOTE3)
    fmode = 3;
  else if (mode & CSV_QUOTE2)
    fmode = 2;
  result = null_descr();
  fb_init(&out);
  fb_init(&tmp);
  if (!csvd_from_string(&cd, dial, dlen)) {
    process.status = ER_PARAMS;
    ok = FALSE;
    goto done;
  }

  if (mode & CSV_DYNAMIC) {
    /* a dynamic array: rows by field mark, fields by value mark */
    char* s;
    int32_t len, rs = 0;

    k_get_string(src_d);
    s = coll_chunks_to_buffer(src_d->data.str.saddr, &len);
    for (i = 0; i <= len; i++) {
      if (i == len || s[i] == FIELD_MARK) {
        int32_t fs = rs;

        if (i == len && i == rs)
          break; /* nothing after the last row mark */
        for (j = rs; j <= i; j++) {
          if (j == i || s[j] == VALUE_MARK) {
            csv_put_field(&out, s + fs, j - fs, fmode, &cd);
            if (j < i)
              fb_addc(&out, cd.delim);
            fs = j + 1;
          }
        }
        csv_put_eol(&out, mode);
        rs = i + 1;
      }
    }
    k_free(s);
  } else {
    DESCRIPTOR* root = src_d;
    COLL_HEADER* top;
    COLL_HEADER* rows = NULL;
    COLL_HEADER* names = NULL;
    bool own_names = FALSE;
    bool objects = FALSE;

    while (root->type == ADDR)
      root = root->data.d_addr;
    if (root->type != COLL) {
      process.status = ER_BUILD_ERROR;
      ok = FALSE;
      goto done;
    }
    top = root->data.coll;
    if (!top->is_array) {
      /* { columns, rows } */
      int32_t pos;

      if (!coll_find(top, "rows", 4, &pos) || top->e[pos].d.type != COLL || !top->e[pos].d.data.coll->is_array) {
        process.status = ER_BUILD_ERROR;
        ok = FALSE;
        goto done;
      }
      rows = top->e[pos].d.data.coll;
      if (coll_find(top, "columns", 7, &pos) && top->e[pos].d.type == COLL && top->e[pos].d.data.coll->is_array)
        names = top->e[pos].d.data.coll;
      objects = TRUE;
    } else {
      rows = top;
      for (i = 0; i < rows->count; i++) {
        if (rows->e[i].d.type == COLL && !rows->e[i].d.data.coll->is_array) {
          objects = TRUE;
          break;
        }
      }
    }
    if (objects && names == NULL) {
      names = coll_new(FALSE);
      own_names = TRUE;
      csv_union_names(rows, names);
    }
    /* the header row: from "columns" (an array of names) or from the names of the rows (an object, in order of name) */
    if (names != NULL && !(mode & CSV_NOHEADER) && (objects || (mode & CSV_HEADER))) {
      bool by_name = names->is_array ? FALSE : TRUE;

      for (i = 0; i < names->count; i++) {
        if (by_name) {
          csv_put_field(&out, names->e[i].name, names->e[i].name_len, fmode, &cd);
        } else {
          if (!csv_value_text(&names->e[i], &tmp)) {
            process.status = ER_BUILD_ERROR;
            ok = FALSE;
            goto cleanup_names;
          }
          csv_put_field(&out, tmp.b, tmp.len, fmode, &cd);
        }
        if (i < names->count - 1)
          fb_addc(&out, cd.delim);
      }
      csv_put_eol(&out, mode);
    }
    for (i = 0; i < rows->count && ok; i++) {
      COLL_ENTRY* re = &rows->e[i];
      COLL_HEADER* r;

      if (re->d.type != COLL) {
        /* a bare value is a row of one field */
        if (!csv_value_text(re, &tmp)) {
          process.status = ER_BUILD_ERROR;
          ok = FALSE;
          break;
        }
        csv_put_field(&out, tmp.b, tmp.len, fmode, &cd);
        csv_put_eol(&out, mode);
        continue;
      }
      r = re->d.data.coll;
      if (r->is_array) {
        for (j = 0; j < r->count; j++) {
          if (!csv_value_text(&r->e[j], &tmp)) {
            process.status = ER_BUILD_ERROR;
            ok = FALSE;
            break;
          }
          csv_put_field(&out, tmp.b, tmp.len, fmode, &cd);
          if (j < r->count - 1)
            fb_addc(&out, cd.delim);
        }
      } else if (names != NULL) {
        for (j = 0; j < names->count; j++) {
          int32_t pos;
          char* nb = NULL;
          int32_t nlen;
          bool found;

          if (names->is_array) {
            nb = coll_chunks_to_buffer(names->e[j].d.data.str.saddr, &nlen);
            found = coll_find(r, nb, nlen, &pos);
            k_free(nb);
          } else {
            found = coll_find(r, names->e[j].name, names->e[j].name_len, &pos);
          }
          tmp.len = 0;
          if (found && !csv_value_text(&r->e[pos], &tmp)) {
            process.status = ER_BUILD_ERROR;
            ok = FALSE;
            break;
          }
          csv_put_field(&out, tmp.b, tmp.len, fmode, &cd);
          if (j < names->count - 1)
            fb_addc(&out, cd.delim);
        }
      }
      if (!ok)
        break;
      csv_put_eol(&out, mode);
    }
  cleanup_names:
    if (own_names) {
      DESCRIPTOR t = coll_descr(names);

      k_release(&t);
    }
  }

done:
  if (ok)
    result = coll_str_descr(out.b, out.len);
  fb_free(&out);
  fb_free(&tmp);
  k_free(dial);
  k_dismiss(); /* dialect */
  k_pop(1);    /* mode */
  k_dismiss(); /* the collection or text */
  *(e_stack++) = result;
}

/* END-CODE */
