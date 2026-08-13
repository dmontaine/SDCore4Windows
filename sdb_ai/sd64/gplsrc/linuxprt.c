/* LINUXPRT.C
 * Printer i/o (Linux)
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
 * Linux printers work by diverting the output to the prt subdirectory of
 * the Q_M_SYS account and then feeding this file to the Linux spooler.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "tio.h"
#include "config.h"

#define FILE_BUFF_SIZE 1024

void to_file(PRINT_UNIT* pu, char* str, int16_t bytes);

/* ======================================================================
   to_printer  -  Send text to printer                                    */

void to_printer(pu, str, bytes) PRINT_UNIT* pu;
char* str;
int16_t bytes;
{ to_file(pu, str, bytes); }

/* ======================================================================
   validate_printer()  -  Check printer name is valid                     */

bool validate_printer(printer_name) char* printer_name;
{ return TRUE; }

/* ======================================================================
   end_printer()  -  End access to printer                                */

void end_printer(pu) PRINT_UNIT* pu;
{
  if (!(pu->flags & PU_KEEP_OPEN)) {
    end_file(pu);
  }
}

/* Modified by Composer AI - 2026/06/10.
   Helper for spool_print_job(): copies src into dst wrapped in single
   quotes with any embedded single quote rewritten as '\'' so the value
   cannot inject shell commands when passed to system(). Returns the
   number of characters written, or -1 if it does not fit. */
static int shell_quote_arg(char* dst, int dst_size, const char* src) {
  int n = 0;

  if (n >= dst_size - 1)
    return -1;
  dst[n++] = '\'';
  for (; *src != '\0'; src++) {
    if (*src == '\'') {
      if (n + 4 >= dst_size)
        return -1;
      dst[n++] = '\'';
      dst[n++] = '\\';
      dst[n++] = '\'';
      dst[n++] = '\'';
    } else {
      if (n + 1 >= dst_size)
        return -1;
      dst[n++] = *src;
    }
  }
  if (n + 2 > dst_size)
    return -1;
  dst[n++] = '\'';
  dst[n] = '\0';
  return n;
}
/* -------------------- */

/* ======================================================================
   spool_print_job()                                                      */

void spool_print_job(PRINT_UNIT* pu) {
  char cmd[300];
  /* Modified by Composer AI - 2026/06/10.
     The command was assembled with unbounded sprintf() calls into a fixed
     300 byte buffer. Long printer names, banners, options or pathnames
     overflowed the stack buffer. Build the command with bounded snprintf()
     calls instead and refuse to run a truncated command.
     Additionally, the printer name, banner, options and pathname are now
     passed through shell_quote_arg() so shell metacharacters in them
     cannot inject commands into the system() call. */
  /* char* p;

  if (pu->spooler != NULL) {
    p = cmd + sprintf(cmd, "%s ", pu->spooler);
  } else if (pcfg.spooler[0] != '\0') {
    p = cmd + sprintf(cmd, "%s ", pcfg.spooler);
  } else {
    p = cmd + sprintf(cmd, "lp ");
  }

  if (pu->copies > 1)
    p += sprintf(p, " -n %d", pu->copies); / * Copies * /
  if (pu->printer_name != NULL)
    p += sprintf(p, " -d %s", pu->printer_name); / * Printer * /
  if (pu->banner != NULL)
    p += sprintf(p, " -t \"%s\"", pu->banner); / * Banner * /
  if (pu->options != NULL)
    p += sprintf(p, " -o \"%s\"", pu->options); / * Options * /
  if (pu->flags & PU_LAND)
    p += sprintf(p, " -o \"landscape\"");

  p += sprintf(p, " '%s' > /dev/null", pu->file.pathname); / * File to print * /

  system(cmd); */
  int n;
  char qbuf[300];

  if (pu->spooler != NULL) {
    n = snprintf(cmd, sizeof(cmd), "%s ", pu->spooler);
  } else if (pcfg.spooler[0] != '\0') {
    n = snprintf(cmd, sizeof(cmd), "%s ", pcfg.spooler);
  } else {
    n = snprintf(cmd, sizeof(cmd), "lp ");
  }

  if ((pu->copies > 1) && (n < (int)sizeof(cmd)))
    n += snprintf(cmd + n, sizeof(cmd) - n, " -n %d", pu->copies); /* Copies */
  if ((pu->printer_name != NULL) && (n < (int)sizeof(cmd))) { /* Printer */
    if (shell_quote_arg(qbuf, sizeof(qbuf), pu->printer_name) < 0)
      goto cmd_too_long;
    n += snprintf(cmd + n, sizeof(cmd) - n, " -d %s", qbuf);
  }
  if ((pu->banner != NULL) && (n < (int)sizeof(cmd))) { /* Banner */
    if (shell_quote_arg(qbuf, sizeof(qbuf), pu->banner) < 0)
      goto cmd_too_long;
    n += snprintf(cmd + n, sizeof(cmd) - n, " -t %s", qbuf);
  }
  if ((pu->options != NULL) && (n < (int)sizeof(cmd))) { /* Options */
    if (shell_quote_arg(qbuf, sizeof(qbuf), pu->options) < 0)
      goto cmd_too_long;
    n += snprintf(cmd + n, sizeof(cmd) - n, " -o %s", qbuf);
  }
  if ((pu->flags & PU_LAND) && (n < (int)sizeof(cmd)))
    n += snprintf(cmd + n, sizeof(cmd) - n, " -o \"landscape\"");

  if (n < (int)sizeof(cmd)) { /* File to print */
    if (shell_quote_arg(qbuf, sizeof(qbuf), pu->file.pathname) < 0)
      goto cmd_too_long;
    n += snprintf(cmd + n, sizeof(cmd) - n, " %s > /dev/null", qbuf);
  }

  if (n >= (int)sizeof(cmd)) {
cmd_too_long:
    fprintf(stderr, "spool_print_job: print command too long - job not spooled\n");
    return;
  }

  system(cmd);
  /* -------------------- */
}

/* END-CODE */
