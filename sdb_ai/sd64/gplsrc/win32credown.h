/* WIN32CREDOWN.H
 * A person's own SD password, changed through the SD service (cred-own).
 * Copyright (c) String Database
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
 * START-HISTORY:
 * 21 Nov 26 Windows port - written.  RELEASE_1.1 379, the Windows form of Linux's "sudo sd-elevate cred-own" (d147a5c), agreed
 *           with the Linux audit session (mail 2026-11-22T1900).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY.  $cred is SYSTEM and Administrators only (gplbld/secure-cred.ps1), so a session whose token is not elevated can neither
 * read nor write its own record, and a standard Windows user could never change its own SD password (RELEASE_1.1 378).  Linux
 * reaches the template's RESULT through a root helper sudoers lets every SD user run on ONE record, the caller's; this is the
 * same door with the operating system's own parts: the SD service (LocalSystem, gplsrc/sdsvc/sdcredown.c) serves a pipe that
 * every SD user may open, and acts on the record of the account whose TOKEN opened it.
 *
 * WHO.  The account is the Windows user of the token the client opened the pipe with (identification level only), lower case,
 * as LOGIN names a session's account.  Nothing in the request names an account.
 *
 * THE WIRE (SD_CREDOWN_PIPE, byte mode).  The client writes lines, each ending in LF, then "END":
 *
 *   SDCREDOWN1 query                          answer: OK salt <salt> iter <iterations>   or   OK none
 *   SDCREDOWN1 verify / <stored key> / END    answer: OK the current password is correct
 *   SDCREDOWN1 set / <current stored key, empty when there is no credential yet> / 2 / SCRAM-SHA-256 / <salt> /
 *              <iterations> / <stored key> / <server key> / END
 *                                             answer: OK SD password set for <account>
 *
 * and every refusal is "ER <reason>".  The answer is one line; then the service closes.  The keys are derived in the session from
 * the password (!CRED_SET's arithmetic) and never leave it as a command line or a file; the service needs no cryptography: the
 * caller cannot read $cred, so arriving with the record's exact stored key proves it knew the password.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32CREDOWN_H
#define WIN32CREDOWN_H

/* Fixed at compile time and not an environment variable, for the reason win32auditpipe.h gives for SD_AUDIT_PIPE. */
#define SD_CREDOWN_PIPE "\\\\.\\pipe\\sd-cred-own"
#define CREDOWN_MAGIC "SDCREDOWN1 "
#define CREDOWN_REQUEST_MAX 2048 /* a set is eight lines of at most 256 */
#define CREDOWN_LINE_MAX 256
#define CREDOWN_ANSWER_MAX 512

/* The session's end.  request: the lines above, through "END\n".  0 and the service's answer line (without its LF) in answer, or
   -1 and why the service could not be asked.  The pipe must be owned by LocalSystem (anybody may make the name while the service
   is down, and this request carries the person's keys); win32_credown_ask_to is the same with the pipe's name and that test as
   arguments, for gplbld/test-credown-units.py. */
int win32_credown_ask(const char* request, char* answer, int alen);
int win32_credown_ask_to(const char* pipe_name, int need_system_owner, const char* request, char* answer, int alen);

#endif

/* END-CODE */
