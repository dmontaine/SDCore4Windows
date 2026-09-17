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
 * 17 Sep 26 Windows port - RELEASE_1.1 54: sdsendmail() REFUSES with
 *           ER_UNSUPPORTED instead of running "sendmail" through system().
 *           The install has no shell (system() answers 127) and no sendmail
 *           behind it, so the old body wrote the message to a temp file,
 *           ran nothing, deleted the file and returned TRUE - SENDMAIL
 *           reported success and nothing was sent, since the port began.
 *           Owner's ruling, 17 Sep 2026: mail not being available is fine.
 *           The Linux body (shell_quote_arg, shell_quote_list, the sendmail
 *           command line) is gone with it; git has it.
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * sdsendmail() - the platform half of BASIC's SENDMAIL.  On Linux it hands
 * the message to the local sendmail.  This port has none, and says so:
 * STATUS() after SENDMAIL is ER_UNSUPPORTED (12, "This operation is not
 * supported on this platform") and nothing is written anywhere.  A program
 * that tests STATUS() sees the refusal; one that does not is no worse off
 * than before, when the same call quietly did nothing and answered 0.
 *
 * WHY A REFUSAL AND NOT AN IMPLEMENTATION.  Sending mail from Windows needs
 * an SMTP host, credentials and a place in sd.conf for both - a design, not a
 * fix - and nothing in the record says anyone has asked for it.  Printing,
 * the other system() caller 54 found, WAS implemented (linuxprt.c), because
 * Windows has a default printer to hand the job to and needs no configuration.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"

/* ======================================================================
   sdsendmail()  -  Send email: not on this platform                      */

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
  (void)sender;
  (void)recipients;
  (void)cc_recipients;
  (void)bcc_recipients;
  (void)subject;
  (void)text;
  (void)attachments;

  process.status = ER_UNSUPPORTED;
  return FALSE;
}

/* END-CODE */
