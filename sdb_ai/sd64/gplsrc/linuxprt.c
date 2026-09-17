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
 * 17 Sep 26 Windows port - RELEASE_1.1 54: spool_print_job() hands the job
 *           to WINDOWS PRINTING through PowerShell's Out-Printer - the
 *           session user's default printer, or the one SETPTR named with AT
 *           - started with fork/execl and waited for, no shell.  Until now
 *           it built an "lp" line and ran it through system(), and the
 *           install has no shell and no lp: every mode-1 job was written,
 *           then vanished with no message (gplbld/probe-system.c measured
 *           system() answering 127 under the installed runtime).  Owner's
 *           ruling, 17 Sep 2026: the default Windows printer, as upstream
 *           OpenQM does.  The Linux command build and its shell quoting are
 *           gone with it; git has them.
 * 17 Sep 26 Same day: the -Command text catches its own error and writes
 *           only the message, so a wrong AT name shows the user one sentence
 *           from Windows and one from SD, not PowerShell's six-line dump
 *           (seen on verify-print b177/b178).  Owner: "fix powershell dump".
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Printers work by diverting the output to the prt subdirectory of the
 * SDSYS account and then feeding this file to the spooler.  On Linux the
 * spooler is lp; here it is Windows printing, reached through PowerShell:
 *
 *   powershell.exe -NoProfile -NonInteractive -Command
 *       "Get-Content -LiteralPath '<job file>' | Out-Printer"
 *   ... | Out-Printer -Name '<printer>'          when SETPTR ... AT <printer>
 *
 * Out-Printer with no -Name IS the Windows default printer.  THAT IS PER
 * USER: a console session prints to the signed-in user's default; an API or
 * ssh session runs as the SD user through S4U or sshd with no profile loaded
 * and may have no default printer at all, so such a session should name the
 * printer in SETPTR.  That is how Windows printers work, not a defect here.
 *
 * WHAT CARRIES OVER AND WHAT DOES NOT.  COPIES n becomes n passes over the
 * job.  AT names the printer.  BANNER, the -o options string and LANDSCAPE
 * had lp meanings and have no Out-Printer equivalent; they are accepted by
 * SETPTR as before and ignored here, and the description of SETPTR in the
 * documentation is where that is said to the user.  Out-Printer sends the
 * text as the printer's default form.
 *
 * WHY fork/execl AND NOT system().  system() is "/bin/sh -c" and the install
 * ships no shell (RELEASE_1.1 37 found the same thing in sdwind).  PowerShell
 * is found the way op_sh.c finds it, sd_powershell_path(), and started
 * directly; the arguments go to execl() as separate strings, so the only
 * quoting is PowerShell's own inside the -Command text, where a single quote
 * in a name is doubled.  The child is waited for, because end_file() removes
 * the job file the moment this returns - a job handed to a child that has not
 * yet read it would print nothing.
 *
 * FAILURES ARE SAID, ON THE TERMINAL.  The old code's only message was for an
 * over-long command line; a spooler that failed said nothing.  Now a launch
 * that cannot happen, or a PowerShell that exits non-zero (no such printer,
 * no default printer), is reported with tio_printf() so the user who typed
 * the PRINT sees why nothing came out.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "tio.h"
#include "config.h"

#include <sys/wait.h>

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

/* ======================================================================
   ps_quote()  -  src inside PowerShell single quotes, ' doubled

   Returns the length written, or -1 if it does not fit.  Single quotes are
   the only character PowerShell interprets inside a single-quoted string, so
   doubling them is the whole of the escaping.                             */

static int ps_quote(char* dst, int dst_size, const char* src) {
  int n = 0;

  if (dst_size < 3)
    return -1;
  dst[n++] = '\'';
  for (; *src != '\0'; src++) {
    if (*src == '\'') {
      if (n + 3 >= dst_size)
        return -1;
      dst[n++] = '\'';
      dst[n++] = '\'';
    } else {
      if (n + 2 >= dst_size)
        return -1;
      dst[n++] = *src;
    }
  }
  dst[n++] = '\'';
  dst[n] = '\0';
  return n;
}

/* ======================================================================
   spool_print_job()  -  Hand the finished job file to Windows printing   */

void spool_print_job(PRINT_UNIT* pu) {
  char psh[MAX_PATHNAME_LEN + 1];
  char qfile[MAX_PATHNAME_LEN + 8];
  char qprinter[MAX_PATHNAME_LEN + 8];
  char script[2 * MAX_PATHNAME_LEN + 256];
  int copies = (pu->copies > 1) ? pu->copies : 1;
  pid_t cpid;
  int status = 0;

  if (ps_quote(qfile, sizeof(qfile), pu->file.pathname) < 0) {
    tio_printf("Print job not sent: the job file's name is too long\n");
    return;
  }
  qprinter[0] = '\0';
  if (pu->printer_name != NULL && pu->printer_name[0] != '\0') {
    if (ps_quote(qprinter, sizeof(qprinter), pu->printer_name) < 0) {
      tio_printf("Print job not sent: the printer name is too long\n");
      return;
    }
  }

  /* The job text is read once; each copy is one Out-Printer.  With no -Name
     Out-Printer uses the session user's default printer.  The try/catch is
     for the user's screen: PowerShell's child shares this session's stderr,
     and an uncaught error there is six lines of CategoryInfo and carets
     before the one line below that says what happened.  The catch leaves
     Windows' own sentence ("Settings to access printer 'x' are not valid.")
     and exit 1. */
  if (snprintf(script, sizeof(script),
               "$ErrorActionPreference = 'Stop'; "
               "try { $t = Get-Content -LiteralPath %s; "
               "1..%d | ForEach-Object { $t | Out-Printer%s%s } } "
               "catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }",
               qfile, copies,
               qprinter[0] ? " -Name " : "", qprinter) >= (int)sizeof(script)) {
    tio_printf("Print job not sent: the print command is too long\n");
    return;
  }

  sd_powershell_path(psh, sizeof(psh));

  cpid = fork();
  if (cpid < 0) {
    tio_printf("Print job not sent: cannot start PowerShell (errno %d)\n", errno);
    return;
  }
  if (cpid == 0) {
    execl(psh, "powershell.exe", "-NoProfile", "-NonInteractive",
          "-ExecutionPolicy", "Bypass", "-Command", script, (char*)NULL);
    _exit(127);                       /* only reached if exec failed */
  }
  if (waitpid(cpid, &status, 0) < 0) {
    tio_printf("Print job sent, but its outcome could not be read (errno %d)\n", errno);
    return;
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    if (WIFEXITED(status) && WEXITSTATUS(status) == 127)
      tio_printf("Print job not sent: PowerShell did not start (%s)\n", psh);
    else if (qprinter[0])
      tio_printf("Print job not sent: Windows refused it for printer %s (exit %d) - is the name right?\n",
                 pu->printer_name, WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    else
      tio_printf("Print job not sent: Windows refused it for the default printer (exit %d) - is one set for this user?\n",
                 WIFEXITED(status) ? WEXITSTATUS(status) : -1);
  }
}

/* END-CODE */
