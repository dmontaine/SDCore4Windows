/* WIN32AUDITPIPE.H
 * The audit trail's writer: what a session and the service agree on.
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
 * 13 Nov 26 Windows port - written.  RELEASE_1.1 247 (Linux W.11 F4, options C1 and C2): the service is the audit
 *           trail's one writer, so a session can no longer append a line that names somebody else; and LOCK.TRACER
 *           (RELEASE_1.1 182, Linux 7f7a4fd4), whose file only the service writes.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * NO WINDOWS TYPE IN THIS INTERFACE, for the reason win32audit.h gives: k_error.c, op_lock.c and op_kernel.c include
 * it beside sd.h.  The service (gplsrc/sdsvc/sdaudit.c, native) includes it too, so the constants below are the one
 * copy both sides read.
 *
 * THE WIRE.  One message on the named pipe SD_AUDIT_PIPE, which the service (LocalSystem) makes and serves:
 *
 *   SDAUDIT1 <who>\t<sysdir>\t<text>        an audit record
 *   SDLOCKT1 <sysdir>\t<line>               a LOCK.TRACER line, ending in a newline
 *
 * <who> is the SD user number the session claims (digits, or ?).  The service does NOT believe it about anything
 * else: the line it writes says user=<DOMAIN\name> pid=<pid> from the KERNEL - the token of the thread that opened
 * the pipe (ImpersonateNamedPipeClient) and GetNamedPipeClientProcessId() - the Windows form of Linux's
 * SCM_CREDENTIALS.  <sysdir> is not trusted either: the service writes only under its own system directory (read
 * from the machine's sd.conf) and answers N to a record from a session of another tree, which then writes its own
 * trail as before.  A tab cannot be in either field: SD makes every control byte of the text '?', and Windows
 * allows none in a path.
 *
 * THE ANSWER is one byte: Y taken (written, or dropped by the rate bound and counted), N not this service's tree,
 * E not written.  Anything but Y, or no answer, and audit_message() appends the record itself (Linux's option C1).
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32AUDITPIPE_H
#define WIN32AUDITPIPE_H

/* Fixed at compile time and NOT an environment variable, for the reason Linux gives for SD_AUDIT_SOCK: a name the
   user can set would let a user send their own session's records somewhere they are not kept.                    */
#define SD_AUDIT_PIPE "\\\\.\\pipe\\sd-audit"

#define AUDIT_MAGIC "SDAUDIT1 "
#define LOCKTRACE_MAGIC "SDLOCKT1 "
#define AUDIT_PIPE_MAX 4096 /* one message: the magic, the claim, a system directory and up to 2048 bytes of text */

#define AUDIT_ANSWER_TAKEN 'Y'
#define AUDIT_ANSWER_NOT_MINE 'N'
#define AUDIT_ANSWER_FAILED 'E'

/* Linux's numbers (sddefs.h, W.11 F4 option C2): one user may add AUDIT_RATE_MAX records in AUDIT_RATE_WINDOW
   seconds; the rest are dropped and the end of the window writes one line saying how many.  The trail is rotated
   by size as the service writes, and at "sd -start" as before.                                                  */
#define AUDIT_RATE_MAX 600
#define AUDIT_RATE_WINDOW 60
#define AUDIT_ROTATE_BYTES 1048576L /* 1MB, then rename and start a new one */

/* Send one message to the pipe called name.  need_system_owner: refuse a pipe whose owner is not LocalSystem - the
   name can be made by anybody while the service is down, and a squatter would otherwise take every record and
   write none (returns -2).  want_answer: wait for the one-byte answer, put in *answer.  0 sent (and answered),
   -1 not.  The shipped callers below always pass need_system_owner 1; the test passes 0 to talk to a pipe of its
   own.                                                                                                          */
int audit_pipe_send(const char* name, int need_system_owner, const char* msg, int len, int want_answer,
                    char* answer);

/* An audit record to the service.  0 when the service took it (answer Y); -1 for anything else, and the caller
   appends the record itself.  win32_audit_pipe() is win32_audit_pipe_to(SD_AUDIT_PIPE, 1, ...).               */
int win32_audit_pipe(const char* sysdir, const char* who, const char* text);
int win32_audit_pipe_to(const char* name, int need_system_owner, const char* sysdir, const char* who,
                        const char* text);

/* A LOCK.TRACER line (len bytes, ending in a newline) to the service, which appends it to <sysdir>\locktrace if
   that file is there.  Does not wait for an answer and has no fallback: no session may write that file.
   win32_locktrace_pipe() is win32_locktrace_pipe_to(SD_AUDIT_PIPE, 1, ...); 0 sent, -1 not.                     */
void win32_locktrace_pipe(const char* sysdir, const char* line, int len);
int win32_locktrace_pipe_to(const char* name, int need_system_owner, const char* sysdir, const char* line, int len);

/* LOCK.TRACER ON: make path an EMPTY file that SYSTEM and Administrators may use and nobody else - the service
   appends to it, the administrator reads it.  Refuses a link or a directory in its place.  0 made, -1 not.     */
int win32_locktrace_create(const char* path);

#endif

/* END-CODE */
