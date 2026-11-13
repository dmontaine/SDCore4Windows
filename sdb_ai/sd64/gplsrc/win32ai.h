/* WIN32AI.H
 * The named-pipe transport of the in-SD AI helper (op_ai.c), the Windows half.
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
 * 13 Nov 26 Windows port - written for RELEASE_1.1 246 (Linux's AI helper,
 *           S.69 step 2): Linux talks to its helper on a Unix socket; here the
 *           helper is the service sd-ai on the pipe \\.\pipe\sd-ai.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * NOTHING IN THIS INTERFACE IS A WINDOWS TYPE, the rule every win32*.h keeps
 * (win32peer.h says why): a connection is a small SLOT NUMBER, never a HANDLE.
 *
 * ***AND THE HANDLE NEVER ENTERS THE MSYS2 DESCRIPTOR TABLE.***  A pipe pushed
 * there with cygwin_attach_handle_to_fd() is reported permanently ready by
 * select() (measured 17 Aug 2026, win32peer.h), which would make a poll spin.
 * So readiness is asked of the pipe itself, with PeekNamedPipe.
 *
 * THE SERVER IS CHECKED BEFORE ANYTHING IS SENT (no Linux counterpart: the
 * directory of Linux's socket is root's).  The pipe namespace is global and any
 * user may create \\.\pipe\sd-ai while the service is stopped, then read every
 * prompt sent to it.  With check_owner set, the pipe object's owner must be the
 * service's own account, NT SERVICE\sd-ai; anything else is refused and the
 * handle closed before one byte is written.
 *
 * END-DESCRIPTION
 */

#ifndef WIN32AI_H
#define WIN32AI_H

#define WIN32_AI_NONE   (-1) /* no such pipe, or every instance busy past the wait */
#define WIN32_AI_NOTOURS (-2) /* a pipe is there and it is not the service's */

/* Open the pipe (a name beginning \\.\pipe\).  check_owner 1: refuse a pipe whose owner is not NT SERVICE\sd-ai.
   wait_ms: how long to wait for a free instance when all are busy.  Returns a slot (0 or more), WIN32_AI_NONE or WIN32_AI_NOTOURS. */
int win32_ai_open(const char* pipe, int check_owner, int wait_ms);

/* Write all len bytes.  1 when all were taken; 0 when the helper took none for wait_ms at a stretch, or the pipe broke. */
int win32_ai_write(int slot, const char* buf, int len, int wait_ms);

/* Bytes waiting to be read (0 or more), or -1 when the helper has closed its end and nothing is left, or -2 on another error.  Never blocks. */
int win32_ai_avail(int slot);

/* Read at most len bytes that win32_ai_avail() said were there.  Returns the count, 0 at the end, -1 on an error.  Never blocks. */
int win32_ai_read(int slot, char* buf, int len);

/* Close a slot (a slot already closed, or -1, is ignored). */
void win32_ai_close(int slot);

#endif

/* END-CODE */
