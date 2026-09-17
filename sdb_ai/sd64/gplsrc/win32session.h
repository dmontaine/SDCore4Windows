/* WIN32SESSION.H
 * Spawn an authenticated API session AS the user, over a named pipe, for
 * RELEASE_1.1 55 (direction (a), Linux parity).
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
 * 17 Sep 26 Windows port - written for RELEASE_1.1 55.  The API session used
 *           to become the user in place (win32s4u.c's AssumeUserIdentity,
 *           seteuid), which leaves the process's real token LocalSystem's
 *           underneath.  Parity with the Linux port (a full setuid session)
 *           means the session must be SPAWNED as the user instead, so nothing
 *           SYSTEM survives in it.  This is the spawn; the channel it is
 *           handed is the crux-(1) named pipe (probe-sessionpipe), and the
 *           relay cuts its app side over to that pipe (probe-relaycutover).
 * END-HISTORY
 *
 * win32_session_spawn() mints the user's token on the LocalSystem front's
 * SeTcbPrivilege (win32_s4u_logon, no password - SCRAM never gives the server
 * one), makes it primary, and CreateProcessAsUser's sd AS the user with
 * "-N -A <pipename>": -N is the API connection type, -A tells sd it is a
 * PRE-AUTHENTICATED session whose I/O is the named pipe rather than a socket on
 * 0/1, and that it must NOT run the SCRAM handshake (the front already did).
 * The user is not passed - the session IS the user and reads its own identity
 * from its token.
 *
 * Unlike win32_relay_spawn() it does NOT strip privileges or lower integrity:
 * this is the user's own session and must have the user's own rights, exactly
 * as a Linux setuid session has the user's uid and groups.  It inherits no
 * handles - the session opens the pipe itself by name (a raw-spawned Cygwin
 * process cannot adopt an inherited socket/pipe; measured, probe-sessionsp).
 *
 * Returns TRUE with *proc a Windows process HANDLE (as void*, so this header
 * stays free of windows.h) and *pid the new pid, or FALSE with a reason in
 * why.  The caller owns the handle and closes it with win32_session_close().
 */

#ifndef WIN32SESSION_H
#define WIN32SESSION_H

#include <stddef.h>

int win32_session_spawn(const char* username, const char* pipename,
                        void** proc, unsigned long* pid, char* why,
                        size_t whylen);

/* Close the process handle win32_session_spawn() returned. */
void win32_session_close(void* proc);

#endif

/* END-CODE */
