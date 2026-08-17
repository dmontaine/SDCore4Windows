/* WIN32PIPE.C
 * Attach an SDLocal client's named pipe to this process's stdin and stdout.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 * START-HISTORY:
 * 17 Aug 26 Windows port - written.  PROJECT_STATUS.md section 7 step 11.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * THE THIRD windows.h FILE, after win32sem.c and win32audit.c, and it exists
 * for the same class of reason as both: the POSIX runtime cannot express what
 * Windows needs here.
 *
 * WHY IT IS NEEDED.  SDConnectLocal() in the client library creates a Windows
 * named pipe, launches "sd.exe -Q -C <pipe name>", and speaks the packet
 * protocol over it.  The client is a NATIVE UCRT64 build and sd.exe is an
 * MSYS2 one (PROJECT_STATUS.md 5.3), so the pipe is a native Windows object
 * and sd.exe cannot reach it through open(): the Cygwin runtime does not map
 * \\.\pipe\ names into its filesystem namespace at all.
 *
 * So the pipe is opened with CreateFile and injected into the Cygwin file
 * descriptor table with cygwin_attach_handle_to_fd(), which is exported by
 * msys-2.0.dll for exactly this purpose.  Everything above this - the whole
 * of op_tio.c and the packet layer - then reads and writes descriptors 0 and
 * 1 without knowing anything has happened, which is the point: the alternative
 * was a second I/O path through the entire terminal layer.
 *
 * TWO HANDLES, NOT ONE, for a duplex pipe.  Descriptors 0 and 1 are closed
 * independently by the runtime, and two descriptors sharing one handle means
 * the first close destroys the second descriptor's handle underneath it.
 * DuplicateHandle gives each its own.
 *
 * THE PIPE IS OPENED WITHOUT FILE_FLAG_OVERLAPPED deliberately.  The client
 * creates it without PIPE_ACCESS_OVERLAPPED, the protocol is strictly
 * request/response, and the descriptors are handed to code that does blocking
 * read()/write().  Overlapped handles behave differently under those calls.
 *
 * NOT VERIFIED.  Nothing has called this: SDConnectLocal() could never reach
 * it before, because sd.exe's -C parsed only "-C<txfd>!<rxfd>" and rejected a
 * pipe name (sd.c, and the same defect is in sdb64 - see UPSTREAM_FIXES.md).
 * The first thing to test is whether cygwin_attach_handle_to_fd() honours a
 * REQUESTED descriptor number rather than allocating the lowest free one; if
 * it allocates instead, the returned descriptors need dup2() onto 0 and 1 and
 * this file is where that goes.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* NO sd.h HERE, and it is not an oversight - win32sem.c and win32audit.c both
   do the same.  sd.h reaches linuxlb.h, which declares GetUserNameA() and
   Sleep() with types that CONFLICT with the real Windows ones, so a file that
   includes both fails to compile.  Measured, 17 Aug 2026: two "conflicting
   types" errors, which is why this returns int rather than sd.h's bool, as
   win32audit.h also does.  TRUE and FALSE come from windows.h.            */

#include <windows.h>

#include <sys/cygwin.h>
#include <unistd.h>

#include "win32pipe.h"

/* ====================================================================== */

int win32_attach_client_pipe(char* pipe_name) {
  HANDLE hread;
  HANDLE hwrite;

  /* Not FILE_SHARE_*: this pipe has one client and one server, and the
     client created it with nMaxInstances 1.                              */

  hread = CreateFileA(pipe_name, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                      OPEN_EXISTING, 0, NULL);
  if (hread == INVALID_HANDLE_VALUE)
    return FALSE;

  if (!DuplicateHandle(GetCurrentProcess(), hread, GetCurrentProcess(),
                       &hwrite, 0, FALSE, DUPLICATE_SAME_ACCESS)) {
    CloseHandle(hread);
    return FALSE;
  }

  /* The descriptors this process was started with are of no use to it - the
     client launches us DETACHED_PROCESS with no handles inherited - and they
     have to be out of the way before the pipe can take their numbers.      */

  close(0);
  close(1);

  /* The name argument is what the descriptor reports as its path; it is
     passed rather than left NULL so that anything printing it says where the
     descriptor came from.  bin = 1: this is a byte protocol and a newline
     translation anywhere in it would corrupt the packet length fields.     */

  if (cygwin_attach_handle_to_fd(pipe_name, 0, hread, 1, GENERIC_READ) < 0) {
    CloseHandle(hread);
    CloseHandle(hwrite);
    return FALSE;
  }

  if (cygwin_attach_handle_to_fd(pipe_name, 1, hwrite, 1, GENERIC_WRITE) < 0) {
    /* hread now belongs to descriptor 0 and must not be closed here. */
    CloseHandle(hwrite);
    return FALSE;
  }

  return TRUE;
}

/* END-CODE */
