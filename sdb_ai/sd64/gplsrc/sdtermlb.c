/* SDTERMLB.C
 * Terminfo routines
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
 *   sdtgetstr(id)  -  Returns terminal control sequence pointer.
 *
 *   tparm(str, ...)  -  Terminal control sequence parameter substitution.
 *
 * All of this module, except for op_terminfo(), is based on code fragments
 * from terminfo specifications and related web sites. The following notice
 * relates to these routines:
 *
 * Copyright (c) 1997-2003,2004 Free Software Foundation, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, distribute with
 * modifications, sublicense, and/or sell copies of the Software, and to permit
 * persons to whom the Software is furnished to do so, subject to the following
 * conditions: 
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software. 
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * ABOVE COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
 * IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 *
 * The op_terminfo() routine is copyright Ladybridge Systems and is released
 * in source form under the General Public Licence.
 * 
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "tio.h"
#include "config.h"
#include "sdtermlb.h"
#include "ti_names.h"

#include <stdarg.h>

#define read_shorts(fu, buff, count) (read(fu, buff, (count)*2) == (count)*2)
#define even_boundary(fu, value) \
  if ((value)&1)                 \
  Seek(fu, 1, SEEK_CUR)

#undef BYTE
#define BYTE(p, n) (unsigned char)((p)[n])

#define IS_NEG1(p) ((BYTE(p, 0) == 0377) && (BYTE(p, 1) == 0377))
#define IS_NEG2(p) ((BYTE(p, 0) == 0376) && (BYTE(p, 1) == 0377))
#define LOW_MSB(p) (BYTE(p, 0) + 256 * BYTE(p, 1))
#define isUPPER(c) ((c) >= 'A' && (c) <= 'Z')
#define isLOWER(c) ((c) >= 'a' && (c) <= 'z')

/* Terminfo file constants */

#define TERMINFO_MAGIC 0x011A /* Magic number for terminfo file */
#define MAX_NAME_SIZE 512     /* Maximum name length (XSI:127) */
#define MAX_ENTRY_SIZE 4096   /* Maximum entry length */

/* TERMTYPE structure */

/* Special values for representing absent / unknown capabilities
   These are standard terminfo definitions. SD does not use the concept
   of cancelled strings but must support them for imported compiled files. */

#define ABSENT_NUMERIC -1
#define UNKNOWN_NUMERIC -2
#define ABSENT_BOOLEAN ((char)-1)
#define UNKNOWN_BOOLEAN ((char)-2)
#define ABSENT_STRING (char*)0
#define UNKNOWN_STRING ((char*)0)
#define CANCELLED_STRING ((char*)-1)

#define VALID_STRING(s) ((s) != CANCELLED_STRING && (s) != ABSENT_STRING)

typedef struct termtype {
  char* term_names;      /* str_table offset of term names */
  char* str_table;       /* pointer to string table */
  signed char* Booleans; /* array of boolean values */
  int16_t* Numbers;        /* array of integer values */
  char** Strings;        /* array of string offsets */
} TERMTYPE;

TERMTYPE tinfo = {NULL, NULL, NULL, NULL, NULL};

Private void get_space(size_t need);
Private void save_text(const char* fmt, const char* s, int len);
Private void save_number(const char* fmt, int number, int len);
Private void save_char(int c);
Private void npush(int x);
Private int npop(void);
Private void spush(char* x);
Private char* spop(void);
Private char* parse_format(char* s, char* format, int* len);
Private void convert_shorts(char* buf, int16_t* Numbers, int count);
Private void convert_strings(char* buf,
                             char** Strings,
                             int count,
                             int size,
                             char* table);

/* ======================================================================
   tsettermtype()  -  Set terminal type                                   */

bool tsettermtype(termname) char* termname;
{
  bool status = FALSE;
  char tname[32 + 1];
  char filename[MAX_PATHNAME_LEN + 1];
  int fu = -1;
  char buff[MAX_ENTRY_SIZE];
  int name_size;
  int bool_count;
  int num_count;
  int str_count;
  int str_size;
  int i;
  int bytes;

  /* Form lowercase version of terminal name */

  strcpy(tname, termname);
  LowerCaseString(tname);

  /* Construct name of terminfo file and try to open it */

  if (pcfg.terminfodir[0] == '\0') {
    /* converted to snprintf() -gwb 22Feb20 */
    if (snprintf(filename, MAX_PATHNAME_LEN + 1, "%s%cterminfo", sysseg->sysdir,
                 DS) >= (MAX_PATHNAME_LEN + 1)) {
       /* TODO should log a detailed error here */
       k_error("Overflowed path/filename in tsettermtype()!");
    }
  } else
    strcpy(filename, pcfg.terminfodir);
  sprintf(filename + strlen(filename), "%c%c%c%s", DS, tname[0], DS, tname);

  if ((fu = open(filename, O_RDONLY | O_BINARY)) < 0) {
    process.status = ER_TI_NOENT; /* No terminfo entry for given name */
    goto exit_settermtype;
  }

  /* Read header */

/* 26 Aug 26 Windows port - THE HEADER IS VALIDATED BEFORE THE OLD DEFINITION
   IS THROWN AWAY.  free_terminfo() used to sit above this, immediately after
   the open, and the two checks below could then each fail with the previous
   terminal's capabilities ALREADY GONE - leaving the session with none at all
   rather than with the type it had a moment earlier.

   A MISSING FILE WAS NEVER THE PROBLEM and this does not change it: the open
   above returns first, so "TERM vt320" on a machine with no vt320 entry has
   always kept the current type, and TERM:246 compares what came back with what
   was asked and says "Unrecognised terminal name".  What could strip a session
   was a file that EXISTED and was corrupt or truncated - a half-copied
   terminfo, a bad sdtic run - which is exactly the case where somebody is
   least able to guess what happened.

   IT IS A MOVE, NOT A REWRITE, AND THE WINDOW IS NARROWED RATHER THAN CLOSED.
   Everything below writes into the global tinfo as it goes, so a k_alloc
   failure after this point still leaves it half built; closing that properly
   means loading into a temporary and swapping, which is a bigger change than
   an out-of-memory path justifies.  These two checks cost nothing to move
   because they read into a local buffer and touch tinfo not at all. */

  if (!read_shorts(fu, buff, 6) || (LOW_MSB(buff) != TERMINFO_MAGIC)) {
    process.status = ER_TI_MAGIC; /* Magic number check failed */
    goto exit_settermtype;
  }

  name_size = LOW_MSB(buff + 2);
  bool_count = LOW_MSB(buff + 4);
  num_count = LOW_MSB(buff + 6);
  str_count = LOW_MSB(buff + 8);
  str_size = LOW_MSB(buff + 10);

  if (name_size < 0 || bool_count < 0 || num_count < 0 || str_count < 0 ||
      str_size < 0) {
    process.status = ER_TI_INVHDR; /* Invalid header data */
    goto exit_settermtype;
  }

  free_terminfo(); /* Free any old dynamic structures */

  /* ---------- Allocate memory for the string table */

  if (str_size) {
    if (str_count * 2 >= (int)sizeof(buff)) {
      process.status = ER_TI_STRSZ; /* String data exceeds MAX_ENTRY_SIZE */
      goto exit_settermtype;
    }

    if ((tinfo.str_table = (char*)k_alloc(92, (unsigned)str_size)) == NULL) {
      process.status = ER_TI_STRMEM; /* Error allocating string data */
      goto exit_settermtype;
    }
  } else {
    str_count = 0;
  }

  /* ---------- Read the name (a null-terminated string) */

  read(fu, buff, min(MAX_NAME_SIZE, (unsigned)name_size));
  buff[MAX_NAME_SIZE] = '\0';
  bytes = strlen(buff) + 1;
  if ((tinfo.term_names = (char*)k_alloc(93, bytes)) == NULL) {
    process.status = ER_TI_NAMEMEM; /* Error allocating name space */
    goto exit_settermtype;
  }

  memset(tinfo.term_names, 0, bytes);
  (void)strcpy(tinfo.term_names, buff);
  if (name_size > MAX_NAME_SIZE) {
    Seek(fu, name_size - MAX_NAME_SIZE, SEEK_CUR);
  }

  /* ---------- Read the booleans */

  /* Modified by Composer AI - 2026/06/10.
     NumBoolNames is size_t; cast for max() with int bool_count. */
  /* i = max(NumBoolNames, bool_count); */
  i = max((int)NumBoolNames, bool_count);
  /* -------------------- */
  if ((tinfo.Booleans = (signed char*)k_alloc(94, i)) == NULL) {
    process.status = ER_TI_BOOLMEM; /* Error allocating space for booleans */
    goto exit_settermtype;
  }
  memset(tinfo.Booleans, 0, i);

  if (read(fu, tinfo.Booleans, (unsigned)bool_count) < bool_count) {
    process.status = ER_TI_BOOLRD; /* Error reading booleans */
    goto exit_settermtype;
  }

  /* If booleans end on an odd byte, skip it.  The machine they were
    originally written on must have been a 16-bit word-oriented machine
    that would trap out if you tried a word access off a 2-byte boundary. */

  even_boundary(fu, name_size + bool_count);

  /* ---------- Read the numbers */

  /* Modified by Composer AI - 2026/06/10.
     NumNumNames is size_t; cast for max() with int num_count. */
  /* bytes = max(NumNumNames, num_count) * sizeof(int16_t); */
  bytes = max((int)NumNumNames, num_count) * sizeof(int16_t);
  /* -------------------- */
  if ((tinfo.Numbers = (int16_t*)k_alloc(95, bytes)) == NULL) {
    process.status = ER_TI_NUMMEM; /* Error allocating space for numbers */
    goto exit_settermtype;
  }
  memset(tinfo.Numbers, 0, bytes);

  if (!read_shorts(fu, buff, num_count)) {
    process.status = ER_TI_NUMRD; /* Error reading numbers */
    goto exit_settermtype;
  }

  convert_shorts(buff, tinfo.Numbers, num_count);

  /* ---------- Read string offsets */

  /* Modified by Composer AI - 2026/06/10.
     NumStrNames is size_t; cast for max() with int str_count. */
  /* bytes = max(NumStrNames, str_count) * sizeof(char*); */
  bytes = max((int)NumStrNames, str_count) * sizeof(char*);
  /* -------------------- */
  if ((tinfo.Strings = (char**)k_alloc(96, bytes)) == NULL) {
    process.status =
        ER_TI_STROMEM; /* Error allocating space for string offsets */
    goto exit_settermtype;
  }
  memset(tinfo.Strings, 0, bytes);

  if (str_count) {
    if (!read_shorts(fu, buff, str_count)) {
      process.status = ER_TI_STRORD; /* Error reading string offsets */
      goto exit_settermtype;
    }

    /* Read the string table itself */

    if (read(fu, tinfo.str_table, (unsigned)str_size) != str_size) {
      process.status = ER_TI_STRTBL; /* Error reading string table */
      goto exit_settermtype;
    }

    convert_strings(buff, tinfo.Strings, str_count, str_size, tinfo.str_table);
  }

  /* Clear undefined entries */

  /* Modified by Composer AI - 2026/06/10.
     Num*Names macros are size_t; cast for comparison with int loop index. */
  /* for (i = bool_count; i < NumBoolNames; i++) */
  for (i = bool_count; i < (int)NumBoolNames; i++)
    tinfo.Booleans[i] = ABSENT_BOOLEAN;
  /* for (i = num_count; i < NumNumNames; i++) */
  for (i = num_count; i < (int)NumNumNames; i++)
    tinfo.Numbers[i] = ABSENT_NUMERIC;
  /* for (i = str_count; i < NumStrNames; i++) */
  for (i = str_count; i < (int)NumStrNames; i++)
    tinfo.Strings[i] = ABSENT_STRING;
  /* -------------------- */

  /* Force all of the cancelled strings to null pointers so we don't have
    to test them in the rest of the library.                             */

  /* Modified by Composer AI - 2026/06/10. See NumStrNames cast above. */
  /* for (i = 0; i < NumStrNames; i++) { */
  for (i = 0; i < (int)NumStrNames; i++) {
  /* -------------------- */
    if (tinfo.Strings[i] == CANCELLED_STRING)
      tinfo.Strings[i] = ABSENT_STRING;
  }

  is_SDTerm = !stricmp(tname, "sdterm");

  process.status = 0;
  strcpy(tio.term_type, tname);
  status = TRUE;

exit_settermtype:

  /* Reset optimisation flags */

  tio.terminfo_hpa = 0;
  tio.terminfo_colour_map = NULL;

  if (fu >= 0)
    close(fu);

  return status;
}

/* ======================================================================
   tgetbool()  -  Get boolean parameter                                   */

int tgetbool(char* str) {
  int i;

  if (tinfo.Booleans != NULL) {
    /* Modified by Composer AI - 2026/06/10. See NumBoolNames cast above. */
    for (i = 0; i < (int)NumBoolNames; i++) {
      if (!strcmp(str, boolnames[i]))
        return tinfo.Booleans[i];
    }
  }

  return UNKNOWN_BOOLEAN;
}

/* ======================================================================
   tgetnum()  -  Get numeric parameter                                    */

int tgetnum(char* str) {
  int i;

  if (tinfo.Numbers != NULL) {
    /* Modified by Composer AI - 2026/06/10. See NumNumNames cast above. */
    for (i = 0; i < (int)NumNumNames; i++) {
      if (!strcmp(str, numnames[i])) {
        if (tinfo.Numbers[i] >= 0)
          return tinfo.Numbers[i];
        return ABSENT_NUMERIC;
      }
    }
  }

  return UNKNOWN_NUMERIC;
}

/* ======================================================================
   sdtgetstr()  -  Get pointer to string parameter                        */

char* sdtgetstr(id) char* id;
{
  int i;
  char* result = NULL;
  static char buff[100];
  char* p;
  char* q;
  char* r;
  int n;

  if (tinfo.Strings == NULL)
    return null_string;

  /* Modified by Composer AI - 2026/06/10. See NumStrNames cast above. */
  for (i = 0; i < (int)NumStrNames; i++) {
    if (!strcmp(id, strnames[i])) {
      result = tinfo.Strings[i];
      if ((result != NULL) && ((p = strstr(result, "$<")) != NULL)) {
        /* Post-process to remove delay constructs */
        q = result;
        r = buff;
        do {
          n = p - q;
          if (n) {
            memcpy(r, q, n);
            r += n;
          }
          q = strchr(p, '>');
          if (q == NULL) /* Faulty string? Copy it across */
          {
            *(r++) = '$';
            q = p + 1;
          } else {
            q++;
          }
        } while ((p = strstr(q, "$<")) != NULL);
        strcpy(r, q);
        result = buff;
      }

      return (result == NULL) ? null_string : result;
    }
  }

  return UNKNOWN_STRING;
}

/* ======================================================================
   tparm()  -  Substitute parameters in string                            */

#define STACKSIZE 20
#define NUM_VARS 26

typedef struct {
  union {
    unsigned int num;
    char* str;
  } data;
  bool num_type;
} STACK_FRAME;

static STACK_FRAME stack[STACKSIZE];
static int stack_ptr;
static const char* tparam_base = "";
static int tparm_err = 0;

static char* out_buff = NULL;
static size_t out_size;
static size_t out_used;

char* tparm(int* bytes, char* str, ...) {
  va_list ap;
  char* p_is_s[9];
  int param[9];
  int lastpop;
  int popcount;
  int number;
  int len;
  int level;
  int x, y;
  int i;
  size_t len2;
  register char* cp;
  static size_t len_fmt = 0;
  static char dummy[] = "";
  static char* format = NULL;
  static int dynamic_var[NUM_VARS];
  static int static_vars[NUM_VARS];

  *bytes = 0;
  tparm_err = 0;
  va_start(ap, str);

  out_used = 0;
  if (str == NULL)
    return NULL;

  if ((len2 = strlen(str)) > len_fmt) {
    len_fmt = len2 + len_fmt + 2;
    if ((format = realloc(format, len_fmt)) == NULL)
      return NULL;
  }

  /* Find the highest parameter-number referred to in the format string.
    Use this value to limit the number of arguments copied from the
    variable-length argument list.                                      */

  number = 0;
  lastpop = -1;
  popcount = 0;
  memset(p_is_s, 0, sizeof(p_is_s));

  /* Analyze the string to see how many parameters we need from the varargs
    list, and what their types are.  We will only accept string parameters
    if they appear as a %l or %s format following an explicit parameter
    reference (e.g., %p2%s).  All other parameters are numbers.
    
    'number' counts coarsely the number of pop's we see in the string, and
    'popcount' shows the highest parameter number in the string.  We would
    like to simply use the latter count, but if we are reading termcap
    strings, there may be cases that we cannot see the explicit parameter
    numbers.                                                                */

  for (cp = str; (cp - str) < (int)len2;) {
    if (*cp == '%') {
      cp++;
      cp = parse_format(cp, format, &len);
      switch (*cp) {
        default:
          break;

        case 'd':
        case 'o':
        case 'x':
        case 'X':
        case 'c':
          number++;
          lastpop = -1;
          break;

        case 'l':
        case 's':
          if (lastpop > 0)
            p_is_s[lastpop - 1] = dummy;
          ++number;
          break;

        case 'p':
          cp++;
          i = (*cp - '0');
          if (i >= 0 && i <= 9) {
            lastpop = i;
            if (lastpop > popcount)
              popcount = lastpop;
          }
          break;

        case 'P':
        case 'g':
          cp++;
          break;

        case '\'':
          cp += 2;
          lastpop = -1;
          break;

        case '{':
          cp++;
          while (*cp >= '0' && *cp <= '9') {
            cp++;
          }
          break;

        case '+':
        case '-':
        case '*':
        case '/':
        case 'm':
        case 'A':
        case 'O':
        case '&':
        case '|':
        case '^':
        case '=':
        case '<':
        case '>':
        case '!':
        case '~':
          lastpop = -1;
          number += 2;
          break;

        case 'i':
          lastpop = -1;
          if (popcount < 2)
            popcount = 2;
          break;
      }
    }
    if (*cp != '\0')
      cp++;
  }

  if (number > 9)
    number = 9;
  for (i = 0; i < max(popcount, number); i++) {
    if (p_is_s[i] != 0)
      p_is_s[i] = va_arg(ap, char*);
    else
      param[i] = va_arg(ap, int);
  }

  stack_ptr = 0;
  if (popcount == 0) {
    popcount = number;
    for (i = number - 1; i >= 0; i--)
      npush(param[i]);
  }

  while (*str) {
    if (*str != '%') {
      save_char(*str);
    } else {
      tparam_base = str++;
      str = parse_format(str, format, &len);
      switch (*str) {
        default:
          break;

        case '%':
          save_char('%');
          break;

        case 'd':
        case 'o':
        case 'x':
        case 'X':
        case 'c':
          save_number(format, npop(), len);
          break;

        case 'l':
          save_number("%d", strlen(spop()), 0);
          break;

        case 's':
          save_text(format, spop(), len);
          break;

        case 'p':
          str++;
          i = (*str - '1');
          if (i >= 0 && i < 9) {
            if (p_is_s[i])
              spush(p_is_s[i]);
            else
              npush(param[i]);
          }
          break;

        case 'P':
          str++;
          if (isUPPER(*str)) {
            i = (*str - 'A');
            static_vars[i] = npop();
          } else if (isLOWER(*str)) {
            i = (*str - 'a');
            dynamic_var[i] = npop();
          }
          break;

        case 'g':
          str++;
          if (isUPPER(*str)) {
            i = (*str - 'A');
            npush(static_vars[i]);
          } else if (isLOWER(*str)) {
            i = (*str - 'a');
            npush(dynamic_var[i]);
          }
          break;

        case '\'':
          str++;
          npush(*str);
          str++;
          break;

        case '{':
          number = 0;
          str++;
          while (*str >= '0' && *str <= '9') {
            number = number * 10 + *str - '0';
            str++;
          }
          npush(number);
          break;

        case '+':
          npush(npop() + npop());
          break;

        case '-':
          y = npop();
          x = npop();
          npush(x - y);
          break;

        case '*':
          npush(npop() * npop());
          break;

        case '/':
          y = npop();
          x = npop();
          npush(y ? (x / y) : 0);
          break;

        case 'm':
          y = npop();
          x = npop();
          npush(y ? (x % y) : 0);
          break;

        case 'A':
          npush(npop() && npop());
          break;

        case 'O':
          npush(npop() || npop());
          break;

        case '&':
          npush(npop() & npop());
          break;

        case '|':
          npush(npop() | npop());
          break;

        case '^':
          npush(npop() ^ npop());
          break;

        case '=':
          y = npop();
          x = npop();
          npush(x == y);
          break;

        case '<':
          y = npop();
          x = npop();
          npush(x < y);
          break;

        case '>':
          y = npop();
          x = npop();
          npush(x > y);
          break;

        case '!':
          npush(!npop());
          break;

        case '~':
          npush(~npop());
          break;

        case 'i':
          if (p_is_s[0] == 0)
            param[0]++;
          if (p_is_s[1] == 0)
            param[1]++;
          break;

        case '?':
          break;

        case 't':
          x = npop();
          if (!x) {
            str++;
            level = 0;
            while (*str) {
              if (*str == '%') {
                str++;
                if (*str == '?')
                  level++;
                else if (*str == ';') {
                  if (level > 0)
                    level--;
                  else
                    break;
                } else if (*str == 'e' && level == 0)
                  break;
              }

              if (*str)
                str++;
            }
          }
          break;

        case 'e':
          /* scan forward for a %; at level zero */
          str++;
          level = 0;
          while (*str) {
            if (*str == '%') {
              str++;
              if (*str == '?')
                level++;
              else if (*str == ';') {
                if (level > 0)
                  level--;
                else
                  break;
              }
            }

            if (*str)
              str++;
          }
          break;

        case ';':
          break;
      }
    }

    if (*str == '\0')
      break;

    str++;
  }

  get_space(1);
  out_buff[out_used] = '\0'; /* Pointless as must allow embedded nulls */

  va_end(ap);
  *bytes = out_used;
  return out_buff;
}

/* ======================================================================
   op_terminfo()  -  Return terminfo data in dynamic array                */

void op_terminfo() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top | Capability name or null string |  Result                     |
     |================================|=============================|
 */

  DESCRIPTOR* descr;
  DESCRIPTOR result;
  char cap_name[32 + 1];
  int len;
  char* p;
  int n;
  char s[12] = "";

  descr = e_stack - 1;
  if ((len = k_get_c_string(descr, cap_name, 32)) < 0) {
    k_error(sysmsg(1780));
  }
  k_dismiss();

  if (len != 0) /* Get specific capability */
  {
    p = s;
    n = tgetnum(cap_name); /* Try as number... */
    if (n >= 0)
      p = itoa(n, s, 10);
    else if (n == UNKNOWN_NUMERIC) {
      n = tgetbool(cap_name); /* Try as boolean */
      if (n >= 0)
        p = itoa(n, s, 10);
      else if (n == UNKNOWN_BOOLEAN) {
        p = sdtgetstr(cap_name); /* Try as string - returns "" if not found */
      }
    }

    k_put_c_string(p, &result);
  } else /* Get standard list of capabilities */
  {
    InitDescr(&result, STRING);
    ts_init(&(result.data.str.saddr), 256);
    ts_copy_c_string(tio.term_type); /* TERM.TYPE */
    ts_copy_byte(FIELD_MARK);
    ts_printf("%d", tgetnum("cols")); /* COLUMNS */
    ts_copy_byte(FIELD_MARK);
    ts_printf("%d", tgetnum("lines")); /* LINES */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cr")); /* CARRIAGE.RETURN */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ff")); /* FORM.FEED */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("nel")); /* NEWLINE CR followed by LF */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("bel")); /* BELL */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ht")); /* TAB */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cbt")); /* BACK.TAB */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("clear")); /* CLEAR.SCREEN */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("el")); /* CLR_EOL */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ed")); /* CLR_EOS */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("hpa")); /* COLUMN.ADDRESS */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cup")); /* CURSOR.ADDRESS */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cub1")); /* CURSOR.LEFT */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cub")); /* CURSOR.LEFT.N */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cuf1")); /* CURSOR.RIGHT */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cuf")); /* CURSOR.RIGHT.N */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cuu1")); /* CURSOR.UP */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cuu")); /* CURSOR.UP.N */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cud1")); /* CURSOR.DOWN */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cud")); /* CURSOR.DOWN.N */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("home")); /* CURSOR.HOME */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("dch1")); /* DELETE.CHARACTER */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("dl1")); /* DELETE.LINE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("dl")); /* DELETE.LINES */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ich1")); /* INSERT.CHARACTER */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("il1")); /* INSERT.LINE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("il")); /* INSERT.LINES */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("blink")); /* ENTER.BLINK.MODE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("bold")); /* ENTER.BOLD.MODE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("dim")); /* ENTER.DIM.MODE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("rev")); /* ENTER.REVERSE.MODE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("smul")); /* ENTER.UNDERLINE.MODE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("sgr0")); /* EXIT.ATTRIBUTE.MODE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("rmul")); /* EXIT.UNDERLINE.MODE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("mc4")); /* PRTR.OFF Printer off */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("mc5")); /* PRTR.ON Printer on */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ind")); /* SCROLL.FORWARD */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ri")); /* SCROLL.BACK */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(
        sdtgetstr("setf")); /* SET.FOREGROUND Set foreground colour attribute */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(
        sdtgetstr("setb")); /* SET.BACKGROUND Set background colour attribute */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u0")); /* USER0 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u1")); /* USER1 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u2")); /* USER2 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u3")); /* USER3 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u4")); /* USER4 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u5")); /* USER5 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u6")); /* USER6 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u7")); /* USER7 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u8")); /* USER8 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("u9")); /* USER9 */
    /* Keys */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kbs")); /* KEY.BACKSPACE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kcbt")); /* KEY.BTAB Back tab key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kcub1")); /* KEY.LEFT */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kcuf1")); /* KEY.RIGHT */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kcuu1")); /* KEY.UP */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kcud1")); /* KEY.DOWN */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("knp")); /* KEY.NPAGE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kpp")); /* KEY.PPAGE */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kind")); /* KEY.SF Scroll forward key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kri")); /* KEY.SR Scroll back key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("khome")); /* KEY.HOME */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kend")); /* KEY.END */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kent")); /* KEY.ENTER */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("khlp")); /* KEY.HELP Help key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kprt")); /* KEY.PRINT Print key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kclr")); /* KEY.CLEAR */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kich1")); /* KEY.IC */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kil1")); /* KEY.IL */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kdch1")); /* KEY.DC */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kdl1")); /* KEY.DL */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kel")); /* KEY.EOL */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ked")); /* KEY.EOS */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf0")); /* KEY.F0 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf1")); /* KEY.F1 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf2")); /* KEY.F2 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf3")); /* KEY.F3 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf4")); /* KEY.F4 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf5")); /* KEY.F5 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf6")); /* KEY.F6 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf7")); /* KEY.F7 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf8")); /* KEY.F8 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf9")); /* KEY.F9 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf10")); /* KEY.F10 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf11")); /* KEY.F11 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kf12")); /* KEY.F12 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kLFT")); /* KEY.SLEFT Shifted left arrow key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(
        sdtgetstr("kRIT")); /* KEY.SRIGHT Shifted right arrow key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(
        sdtgetstr("kIC")); /* KEY.SIC Shifted insert character key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(
        sdtgetstr("kDC")); /* KEY.SDC Shifted delete character key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kDL")); /* KEY.SDL Shifted delete line key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kEND")); /* KEY.SEND Shifted end key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(
        sdtgetstr("kEOL")); /* KEY.SEOL Shifted clear to end of line key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kHOM")); /* KEY.SHOME Shifted home key */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("kmous")); /* KEY.MOUSE Mouse input */
    /* SD extensions */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("slt")); /* Set line truncate mode */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("rlt")); /* Reset line truncate mode */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku0")); /* User key 0 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku1")); /* User key 1 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku2")); /* User key 2 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku3")); /* User key 3 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku4")); /* User key 4 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku5")); /* User key 5 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku6")); /* User key 6 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku7")); /* User key 7 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku8")); /* User key 8 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("ku9")); /* User key 9 */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("sreg")); /* Save screen region */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("rreg")); /* Restore screen region */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("dreg")); /* Delete saved screen region */
    /* Other standard terminfo items */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("cvvis")); /* Set cursor visible */
    ts_copy_byte(FIELD_MARK);
    ts_copy_c_string(sdtgetstr("civis")); /* Set cursor invisible */
    ts_copy_byte(FIELD_MARK);
    ts_printf("%d", tgetnum("xmc")); /* Space occupied by attribute */

    ts_terminate();
  }

  *(e_stack++) = result;
}

/* ====================================================================== */

Private void get_space(size_t need) {
  need += out_used;
  if (need > out_size) {
    out_size = need * 2;
    out_buff = realloc(out_buff, out_size);
  }
}

Private void save_text(const char* fmt, const char* s, int len) {
  size_t s_len = strlen(s);

  if (len > (int)s_len)
    s_len = len;

  get_space(s_len + 1);

  out_used += sprintf(out_buff + out_used, fmt, s);
  // out_used += strlen(out_buff + out_used);
}

Private void save_number(const char* fmt, int number, int len) {
  if (len < 30)
    len = 30; /* actually log10(MAX_INT)+1 */

  get_space(len + 1);

  out_used += sprintf(out_buff + out_used, fmt, number);
  // out_used += strlen(out_buff + out_used);
}

Private void save_char(int c) {
  if (c == 0)
    c = 0200;
  get_space(1);
  out_buff[out_used++] = c;
}

Private void npush(int x) {
  if (stack_ptr < STACKSIZE) {
    stack[stack_ptr].num_type = TRUE;
    stack[stack_ptr].data.num = x;
    stack_ptr++;
  } else {
    tio_printf("npush: stack overflow\n");
    tparm_err++;
  }
}

Private int npop(void) {
  int result = 0;

  if (stack_ptr > 0) {
    stack_ptr--;
    if (stack[stack_ptr].num_type)
      result = stack[stack_ptr].data.num;
    else {
      tio_printf("npop: stack underflow\n");
      tparm_err++;
    }
  }
  return result;
}

Private void spush(char* x) {
  if (stack_ptr < STACKSIZE) {
    stack[stack_ptr].num_type = FALSE;
    stack[stack_ptr].data.str = x;
    stack_ptr++;
  } else {
    tio_printf("spush: stack overflow\n");
    tparm_err++;
  }
}

Private char* spop(void) {
  static char dummy[] = ""; /* avoid const-cast */
  char* result = dummy;

  if (stack_ptr > 0) {
    stack_ptr--;
    if (!stack[stack_ptr].num_type && stack[stack_ptr].data.str != 0) {
      result = stack[stack_ptr].data.str;
    }
  } else {
    tio_printf("spop: stack underflow\n");
    tparm_err++;
  }
  return result;
}

/* ====================================================================== */

Private char* parse_format(s, format, len) char* s;
char* format;
int* len;
{
  bool done = FALSE;
  bool allowminus = FALSE;
  bool dot = FALSE;
  bool err = FALSE;
  char* fmt = format;
  int prec = 0;
  int width = 0;
  int value = 0;

  *len = 0;
  *format++ = '%';
  while (*s != '\0' && !done) {
    switch (*s) {
      case 'c':
      case 'd':
      case 'o':
      case 'x':
      case 'X':
      case 's':
        *format++ = *s;
        done = TRUE;
        break;

      case '.':
        *format++ = *s++;
        if (dot)
          err = TRUE;
        else {
          dot = TRUE;
          prec = value;
        }
        value = 0;
        break;

      case '#':
        *format++ = *s++;
        break;

      case ' ':
        *format++ = *s++;
        break;

      case ':':
        s++;
        allowminus = TRUE;
        break;

      case '-':
        if (allowminus)
          *format++ = *s++;
        else
          done = TRUE;
        break;

      default:
        if (IsDigit(*s)) {
          value = (value * 10) + (*s - '0');
          if (value > 10000)
            err = TRUE;
          *format++ = *s++;
        } else {
          done = TRUE;
        }
    }
  }

  /* If we found an error, ignore (and remove) the flags. */

  if (err) {
    prec = width = value = 0;
    format = fmt;
    *format++ = '%';
    *format++ = *s;
  }

  if (dot)
    width = value;
  else
    prec = value;

  *format = '\0';
  /* return maximum string length in print */
  *len = (prec > width) ? prec : width;
  return s;
}

/* ======================================================================
   convert_shorts()  -  Convert short integer format                      */

Private void convert_shorts(buf, numbers, count) char* buf;
int16_t* numbers;
int count;
{
  int i;

  for (i = 0; i < count; i++) {
    numbers[i] = LOW_MSB(buf + 2 * i);
  }
}

/* ======================================================================
   convert_strings()  -  Convert string data                              */

Private void convert_strings(buf, Strings, count, size, table) char* buf;
char** Strings;
int count;
int size;
char* table;
{
  int i;
  char* p;

  for (i = 0; i < count; i++) {
    if (IS_NEG1(buf + 2 * i))
      Strings[i] = ABSENT_STRING;
    else if (IS_NEG2(buf + 2 * i))
      Strings[i] = CANCELLED_STRING;
    else if (LOW_MSB(buf + 2 * i) > size)
      Strings[i] = ABSENT_STRING;
    else
      Strings[i] = (LOW_MSB(buf + 2 * i) + table);

    /* Make sure all strings are null terminated */

    if (VALID_STRING(Strings[i])) {
      for (p = Strings[i]; p <= table + size; p++)
        if (*p == '\0')
          break;
      /* If there is no NULL, ignore the string */
      if (p > table + size)
        Strings[i] = ABSENT_STRING;
    }
  }
}

void free_terminfo() {
  if (tinfo.term_names != NULL)
    k_free(tinfo.term_names);
  if (tinfo.str_table != NULL)
    k_free(tinfo.str_table);
  if (tinfo.Booleans != NULL)
    k_free(tinfo.Booleans);
  if (tinfo.Numbers != NULL)
    k_free(tinfo.Numbers);
  if (tinfo.Strings != NULL)
    k_free(tinfo.Strings);
  memset(&tinfo, 0, sizeof(TERMTYPE));
}

/* END-CODE */
