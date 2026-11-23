/* WIN32TRACE.H
 * The socket trace log, made owner-only (SET.SOCKET.MODE SKT$INFO.TRACE).
 * Copyright (c) Donald Montaine
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
 * 17 Nov 26 Windows port - written, four-version audit round 1 (owner's answer 5a of 17 Nov): the socket trace of Linux 400500c
 *           is carried with the protection Linux gives its log (mode 0600, O_NOFOLLOW).  See win32trace.c.
 * END-HISTORY
 */

#ifndef WIN32TRACE_H
#define WIN32TRACE_H

/* Open the trace log at path (a POSIX path, as SD holds it) for writing, truncated, readable and writable only by this
   process's own Windows user, SYSTEM and the Administrators group.  Returns a file descriptor, or -1 with errno set. */
int win32_trace_open(const char* path);

#endif
