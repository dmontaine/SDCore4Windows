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
 *           SYSTEM survives in it.  This is the spawn; the channel it is handed
 *           is the crux-(1) named pipe (probe-relaycutover for the relay side).
 * 17 Sep 26 Windows port - REVISED to hand the pipe over on the session's STD
 *           HANDLES, not for the session to open by name.  probe-pipestd and
 *           sd.c:460 / PROJECT_STATUS §7 step 11: a descriptor made by
 *           cygwin_attach_handle_to_fd() from a raw HANDLE is permanently ready
 *           to select() and sd's input layer spins on it, while a native pipe
 *           handed over as a std handle wraps as a real fhandler_pipe with
 *           working select (the shipping -C1!0 shape).
 * 17 Sep 26 Windows port - the spawned command line is "-N -H", not "-N -A".
 *           Slice 2 moved the pre-authenticated flag to -H because sd.c's
 *           option switch folds the letter with UpperCase() and -A is already
 *           "query account"; this file was not changed with it, so the session
 *           would have been spawned asking for an account name with
 *           api_preauth still FALSE.
 * END-HISTORY
 *
 * win32_session_spawn() mints the user's token on the LocalSystem front's
 * SeTcbPrivilege (win32_s4u_logon, no password - SCRAM never gives the server
 * one), makes it primary, and CreateProcessAsUser's sd AS the user with
 * "-N -H": -N is the API connection type, -H tells sd it is a PRE-AUTHENTICATED
 * session whose I/O is already on descriptors 0 and 1 (this pipe) and that it
 * must NOT spawn a relay or run the SCRAM handshake (the front already did).
 * The user is not passed - the session IS the user and reads its own identity
 * from its token.
 *
 * pipe_client is the pipe's CLIENT end, opened by the FRONT (LocalSystem opens
 * the sole client end, so no other process is on the pipe; that plus the pipe's
 * single instance and its SID-DACL is the bind).  It is duplicated into TWO
 * inheritable handles - one per descriptor, as win32pipe.c requires for a
 * duplex pipe - and handed over as the session's std handles.  Nothing else is
 * inherited.
 *
 * Unlike win32_relay_spawn() it does NOT strip privileges or lower integrity:
 * this is the user's own session and must have the user's own rights, exactly
 * as a Linux setuid session has the user's uid and groups.
 *
 * Returns TRUE with *proc a Windows process HANDLE (as void*, so this header
 * stays free of windows.h) and *pid the new pid, or FALSE with a reason in
 * why.  The caller owns the handle and closes it with win32_session_close().
 */

#ifndef WIN32SESSION_H
#define WIN32SESSION_H

#include <stddef.h>

int win32_session_spawn(const char* username, void* pipe_client, void** proc,
                        unsigned long* pid, char* why, size_t whylen);

/* Close the process handle win32_session_spawn() returned. */
void win32_session_close(void* proc);

#endif

/* END-CODE */
