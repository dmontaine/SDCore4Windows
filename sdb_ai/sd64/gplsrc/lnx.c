/* LNX.C
 * Linux specific functions
 * Copyright (c) 2003 Ladybridge Systems, All Rights Reserved
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
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"

/* Modified by Composer AI - 2026/06/10.
   Helper for sdsendmail(): copies src into dst wrapped in single quotes
   with any embedded single quote rewritten as '\'' so the value cannot
   inject shell commands when passed to system(). Returns the number of
   characters written, or -1 if it does not fit. */
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

/* Modified by Composer AI - 2026/06/10.
   Helper for sdsendmail(): quotes a whitespace separated address list,
   quoting each token individually so the resulting argument structure of
   the mail command is unchanged but shell metacharacters in the
   addresses cannot inject commands. Returns length or -1 if too long. */
static int shell_quote_list(char* dst, int dst_size, const char* src) {
  int n = 0;
  int q;
  char token[256];
  int t;

  dst[0] = '\0';
  while (*src != '\0') {
    while ((*src == ' ') || (*src == '\t'))
      src++;
    if (*src == '\0')
      break;

    t = 0;
    while ((*src != '\0') && (*src != ' ') && (*src != '\t')) {
      if (t >= (int)sizeof(token) - 1)
        return -1;
      token[t++] = *(src++);
    }
    token[t] = '\0';

    if (n > 0) {
      if (n + 1 >= dst_size)
        return -1;
      dst[n++] = ' ';
      dst[n] = '\0';
    }
    q = shell_quote_arg(dst + n, dst_size - n, token);
    if (q < 0)
      return -1;
    n += q;
  }
  return n;
}
/* -------------------- */

/* ======================================================================
   sdsendmail()  -  Send email                                            */

bool sdsendmail(
    sender,
    recipients,
    cc_recipients,
    bcc_recipients,
    subject,
    text,
    attachments) char* sender; /* Sender's address:  fred@acme.com */
char* recipients;              /* Comma separated list of recipient addresses */
char* cc_recipients;           /* Comma separated list of recipient addresses */
char* bcc_recipients;          /* Comma separated list of recipient addresses */
char* subject;                 /* Subject line */
char* text;                    /* Text of email */
char* attachments;             /* Comma separated list of attachment files */
{
  bool status = FALSE;
  /*  20240122  mab change sprintf to snprintf and test for buffer overflow */

  #define tempnamesz 13      /* 12 char + \0 */
  char tempname[tempnamesz]; /* .sd__mailnnnn */
  char command[1024 + 1];
  int tfu;
  int n;

  /* Write mail text to a temporary file */

/*  20240122  mab change sprintf to snprintf and test for buffer overflow */
  if (snprintf(tempname, tempnamesz, ".sd_mail%d", my_uptr->uid) >= tempnamesz) {
    process.status = ER_NO_TEMP;
    process.os_error = errno;
    goto exit_sendmail;
  };
  
  tfu = open(tempname, O_RDWR | O_CREAT | O_TRUNC, default_access);
  if (tfu < 0) {
    process.status = ER_NO_TEMP;
    process.os_error = errno;
    goto exit_sendmail;
  }

  n = strlen(text);
  if (write(tfu, text, n) != n) {
    process.status = ER_NO_TEMP;
    goto exit_sendmail;
  }

  close(tfu);

  /* Construct mail command */

  /* Modified by Composer AI - 2026/06/10.
     The mail command was assembled with unbounded sprintf() calls into a
     fixed buffer; long subject or recipient lists overflowed it. Use
     bounded snprintf() calls and fail the send (ER_LENGTH) instead of
     executing a truncated command.
     Additionally, the subject is now shell-quoted as a single argument
     and each recipient address is individually shell-quoted, so shell
     metacharacters in them cannot inject commands into the system()
     call. The argument structure of the generated command is otherwise
     unchanged. */
  /* n = sprintf(command, "mail -s \"%s\"", subject);

  if (cc_recipients != NULL)
    n += sprintf(command + n, " -c %s", cc_recipients);
  if (bcc_recipients != NULL)
    n += sprintf(command + n, " -b %s", bcc_recipients);
  if (recipients != NULL)
    n += sprintf(command + n, " %s", recipients);

  sprintf(command + n, " <%s", tempname);

  system(command); */
  {
    char qbuf[1024 + 1];

    if (shell_quote_arg(qbuf, sizeof(qbuf), subject) < 0)
      goto cmd_too_long;
    n = snprintf(command, sizeof(command), "mail -s %s", qbuf);

    if ((cc_recipients != NULL) && (n < (int)sizeof(command))) {
      if (shell_quote_list(qbuf, sizeof(qbuf), cc_recipients) < 0)
        goto cmd_too_long;
      n += snprintf(command + n, sizeof(command) - n, " -c %s", qbuf);
    }
    if ((bcc_recipients != NULL) && (n < (int)sizeof(command))) {
      if (shell_quote_list(qbuf, sizeof(qbuf), bcc_recipients) < 0)
        goto cmd_too_long;
      n += snprintf(command + n, sizeof(command) - n, " -b %s", qbuf);
    }
    if ((recipients != NULL) && (n < (int)sizeof(command))) {
      if (shell_quote_list(qbuf, sizeof(qbuf), recipients) < 0)
        goto cmd_too_long;
      n += snprintf(command + n, sizeof(command) - n, " %s", qbuf);
    }

    if (n < (int)sizeof(command))
      n += snprintf(command + n, sizeof(command) - n, " <%s", tempname);

    if (n >= (int)sizeof(command)) {
cmd_too_long:
      process.status = ER_LENGTH;
      remove(tempname);
      goto exit_sendmail;
    }
  }

  system(command);
  /* -------------------- */

  /* Delete temporary file */

  remove(tempname);

  status = TRUE;

exit_sendmail:
  return status;
}

/* END-CODE */
