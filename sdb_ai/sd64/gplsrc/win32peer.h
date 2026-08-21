/* WIN32PEER.H
 * Native Windows peer identification, for sdwind.c.
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
 * 20 Aug 26 Windows port - written.  The API listener binds to loopback, and
 *           binding to loopback is not the same as authenticating the peer.
 *           PROJECT_STATUS.md 8, posture B.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * NOTHING IN THIS INTERFACE IS A WINDOWS TYPE, for the reasons win32sem.h
 * gives at length.  This is the FOURTH such file and the constraint is
 * sharper here than in the other three: <windows.h> and <netinet/in.h>
 * CANNOT SHARE A TRANSLATION UNIT AT ALL - measured 20 Aug 2026, and the
 * error is "redefinition of struct in6_addr", w32api's in6addr.h against
 * cygwin's in6.h.  So a socket type crossing this interface would not merely
 * be untidy; the caller would not compile.  Ports are therefore passed as
 * plain integers in HOST byte order, and the socket half never sees a
 * Windows header.
 *
 * WHY NOT A NAMED PIPE, which is the usual Windows answer and which section 8
 * recommended until 20 Aug 2026.  GetNamedPipeClientProcessId needs a pipe,
 * and this server cannot use one: section 7 step 11 measured on 17 Aug 2026
 * that a pipe pushed into the Cygwin descriptor table with
 * cygwin_attach_handle_to_fd() is reported PERMANENTLY READY by select(), so
 * sdpoll() answers "input waiting" for ever and sd.exe spins - alive, silent,
 * never replying.  sd.c refuses the "-C <pipename>" form rather than hang.
 * CN_PIPE in connection_type is not spare either: it is SDLocal's transport.
 *
 * GetExtendedTcpTable asks the same question of the socket sdwind ALREADY
 * has, so no transport changes.
 *
 * TWO LIMITS, BOTH REAL, AND ANY POLICY BUILT ON THIS MUST ALLOW FOR THEM:
 *
 *   AN ssh-FORWARDED CONNECTION IDENTIFIES sshd, not the person at the far
 *   end - the tunnel terminates locally, so the peer process genuinely is
 *   sshd.  Given posture B pipes the API through ssh, that is the ORDINARY
 *   case rather than an edge one.  What this can distinguish is a genuinely
 *   local client from a tunnelled one; it cannot identify a remote person.
 *
 *   TOCTOU.  The peer can exit between accept() and the lookup and its port
 *   be reused by another process, which would then be named instead.  The
 *   window is narrow and closable by comparing process start times, and it
 *   is not zero.  Caller should look the peer up as early as it can.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32PEER_H
#define WIN32PEER_H

/* Which process owns the other end of a loopback TCP connection?  Both ports
   are in HOST byte order and are the two ends as this process sees them:
   our_port is the local port of the accepted socket, peer_port the remote.

   Returns 0 if the connection is not in the table, which includes the case
   where the peer has already gone.                                         */

unsigned long win32_peer_pid(unsigned short our_port, unsigned short peer_port);

/* The Windows account owning a process, as DOMAIN\name, into out.  This is
   the half that makes the pid worth having - a pid alone says nothing about
   trust.  Returns non-zero on success; out is set to the empty string first,
   so a caller that ignores the return value gets "" rather than rubbish.   */

int win32_pid_user(unsigned long pid, char* out, int outlen);

#endif

/* END-CODE */
