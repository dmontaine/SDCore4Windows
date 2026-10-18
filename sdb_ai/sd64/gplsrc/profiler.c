/* PROFILER.C
 * Application event profiler (openQM 4 PROFILER, QM4 gap 66 / 203)
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
 * 18 Oct 26 Windows port - from Linux b51c637 (16 Oct 26): New.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * While the profiler is on in a process (kernel(K$PROFILER, mask)) the places in the kernel that carry out a program's CALL,
 * OPEN, READ, WRITE, DELETE, OPENSEQ, READSEQ, WRITESEQ, EXECUTE and a call of a class module's object (OBJECT) tell prof_event()
 * which they are, with a qualifier (the subroutine, the file, the pathname, the command, the class).  prof_event() counts them in a
 * table keyed by event, qualifier, program and line number.  The table is read with kernel(K$PROFILER, -2) as field-mark
 * delimited entries of value-mark delimited event, qualifier, program, line, count.  It is the process's own memory: nothing is
 * written to disk here.
 *
 * Only what a program's own object code does is counted.  The language runtime's recursive code (a READV is a recursive that reads
 * the record, for one) runs with the HDR_RECURSIVE flag and is left out, so one statement is one event.
 *
 * Functions:
 *   prof_event()      Count an event
 *   prof_set()        Start (mask > 0) or stop (0) logging; starting clears the table
 *   prof_dump()       Return the table in a string descriptor
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"

#define PROF_MAX 4000     /* Entries in the table; a profile that has more than this loses the rest and says so */
#define PROF_QUAL_LEN 64  /* Characters of a qualifier kept */

typedef struct PROF_ENTRY PROF_ENTRY;
struct PROF_ENTRY {
  int16_t bit;                           /* PROF_x of the event */
  int32_t line;                          /* Line number in the program, 0 if the program has no line table */
  int32_t count;
  char prog[MAX_PROGRAM_NAME_LEN + 1];
  char qual[PROF_QUAL_LEN + 1];
};

Private PROF_ENTRY* prof_tab = NULL;
Private int32_t prof_n = 0;
Private int32_t prof_lost = 0; /* Events that did not fit */

Private const char* const prof_names[PROF_TYPES] = {"CALL", "OPEN", "READ", "WRITE", "DELETE", "OPENSEQ", "READSEQ", "WRITESEQ", "EXECUTE", "OBJECT"};

/* ======================================================================
   prof_set()  -  Start or stop logging.  A mask starts it with an empty table, 0 stops it and leaves what was found.      */

void prof_set(int16_t mask) {
  if (mask != 0) {
    if (prof_tab == NULL) {
      prof_tab = (PROF_ENTRY*)k_alloc(125, sizeof(PROF_ENTRY) * PROF_MAX);
      if (prof_tab == NULL) {
        prof_mask = 0;
        return;
      }
    }
    prof_n = 0;
    prof_lost = 0;
  }
  prof_mask = mask & PROF_ALL;
}

/* ======================================================================
   prof_event()  -  Count one event of the program that is running                                                         */

void prof_event(int16_t bit, const char* qual, int qlen) {
  PROF_ENTRY* e;
  const char* prog;
  int32_t line;
  int32_t i;
  char q[PROF_QUAL_LEN + 1];

  if (!(prof_mask & bit) || (prof_tab == NULL) || (c_base == NULL))
    return;
  if (process.program.flags & HDR_RECURSIVE)
    return;

  if (qlen < 0)
    qlen = 0;
  if (qlen > PROF_QUAL_LEN)
    qlen = PROF_QUAL_LEN;
  for (i = 0; i < qlen; i++) { /* Nothing that delimits the report goes into it */
    unsigned char c = (unsigned char)qual[i];
    q[i] = ((c < 32) || (c >= 248)) ? '?' : (char)c;
  }
  q[qlen] = '\0';

  prog = ProgramName(c_base);
  line = k_line_no((int32_t)(pc - c_base) - 1, c_base); /* the last byte the instruction used: pc is already on the next one */
  if (line < 0)
    line = 0;

  for (i = 0, e = prof_tab; i < prof_n; i++, e++) {
    if ((e->bit == bit) && (e->line == line) && !strcmp(e->qual, q) && !strcmp(e->prog, prog)) {
      e->count++;
      return;
    }
  }
  if (prof_n >= PROF_MAX) {
    prof_lost++;
    return;
  }
  e = prof_tab + prof_n++;
  e->bit = bit;
  e->line = line;
  e->count = 1;
  strncpy(e->prog, prog, MAX_PROGRAM_NAME_LEN);
  e->prog[MAX_PROGRAM_NAME_LEN] = '\0';
  strcpy(e->qual, q);
}

/* ======================================================================
   prof_file_event()  -  An event on a file: the qualifier is the name the program opened it under (a VOC name, or the
   pathname of a file opened with OPENPATH).                                                                               */

void prof_file_event(int16_t bit, FILE_VAR* fvar) {
  const char* name = (fvar != NULL) ? fvar->voc_name : NULL;

  if (name == NULL)
    name = "";
  prof_event(bit, name, (int)strlen(name));
}

/* ======================================================================
   prof_dump()  -  The table as a string: field 1 is PROFILE, the events being logged, the entries and the events lost; then one
   field for each entry, event, qualifier, program, line, count delimited by value marks.                                      */

void prof_dump(DESCRIPTOR* result) {
  int32_t i;
  int t;
  PROF_ENTRY* e;

  InitDescr(result, STRING);
  result->data.str.saddr = NULL;
  ts_init(&(result->data.str.saddr), 256);
  /* Field 1 is always there: the events being logged, how many entries there are and how many events did not fit */
  ts_printf("PROFILE%c%d%c%d%c%d", VALUE_MARK, (int)prof_mask, VALUE_MARK, (int)prof_n, VALUE_MARK, (int)prof_lost);
  for (i = 0, e = prof_tab; i < prof_n; i++, e++) {
    for (t = 0; t < PROF_TYPES; t++) {
      if (e->bit == (1 << t))
        break;
    }
    if (t == PROF_TYPES)
      continue;
    ts_copy_byte(FIELD_MARK);
    ts_printf("%s%c%s%c%s%c%d%c%d", prof_names[t], VALUE_MARK, e->qual, VALUE_MARK, e->prog, VALUE_MARK, (int)e->line, VALUE_MARK,
              (int)e->count);
  }
  ts_terminate();
}

/* END-CODE */
