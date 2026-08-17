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
 * WHAT IS MEASURED AND WHAT IS NOT.  The two questions this file raised have
 * both been answered against a real named pipe with real data in it, using a
 * standalone probe rather than a whole install cycle:
 *
 *   * cygwin_attach_handle_to_fd() DOES honour a requested descriptor number.
 *     It returns the number asked for.  No dup2() is needed.
 *   * The access argument must MATCH THE HANDLE, which is the trap - see the
 *     comment on the calls below.  This is what made the first version fail.
 *
 * NOT verified: this code inside sd.exe, driven by the real client.  The probe
 * proves the mechanism, not the integration.
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
     translation anywhere in it would corrupt the packet length fields.

     THE ACCESS MUST MATCH HOW THE HANDLE WAS OPENED, NOT WHAT THE DESCRIPTOR
     IS FOR.  Both calls pass GENERIC_READ | GENERIC_WRITE because that is how
     CreateFile opened the handle above - NOT GENERIC_READ for descriptor 0 and
     GENERIC_WRITE for descriptor 1, which is the obvious thing to write and is
     wrong.

     MEASURED, 17 Aug 2026, because the failure is silent and misleading.  With
     GENERIC_READ alone on descriptor 0, the attach SUCCEEDS and returns 0,
     poll() then reports the descriptor READABLE with POLLIN set - and read()
     fails with EBADF.  So SD reached linuxio.c:535, passed the sdpoll() test,
     failed the read, took the "connection lost" branch and exited 0 with
     nothing on either stream; the client saw only "Connection closed by
     server".  Nothing in that chain names the access flags.  Four other
     combinations were tried against a real pipe with real data waiting - the
     pipe name, NULL, "/dev/null", O_RDONLY, O_RDWR - and all failed the same
     way; only matching the CreateFile access reads the bytes.              */

  if (cygwin_attach_handle_to_fd(pipe_name, 0, hread, 1,
                                 GENERIC_READ | GENERIC_WRITE) < 0) {
    CloseHandle(hread);
    CloseHandle(hwrite);
    return FALSE;
  }

  if (cygwin_attach_handle_to_fd(pipe_name, 1, hwrite, 1,
                                 GENERIC_READ | GENERIC_WRITE) < 0) {
    /* hread now belongs to descriptor 0 and must not be closed here. */
    CloseHandle(hwrite);
    return FALSE;
  }

  return TRUE;
}

/* END-CODE */
