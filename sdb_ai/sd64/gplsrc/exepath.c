/* EXEPATH.C
 * Locate the directory holding the running executable.
 * Copyright (c) 2026 Ladybridge Systems, All Rights Reserved
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
 * 14 Aug 26 Windows port - new file
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * exe_directory() answers the directory holding the running executable, with
 * no trailing separator.
 *
 * IT EXISTS BECAUSE ONE SD PROCESS HAS TO LAUNCH ANOTHER, and until now both
 * places that do so built the path from sysseg->sysdir as "<sysdir>/bin/...".
 * That was correct while the Linux install put the executables and the pcode
 * composite library in the same /usr/local/sdsys/bin.  The Windows layout
 * (PROJECT_STATUS.md 5.8) splits them - binaries to
 * C:\Program Files\SD\usr\bin, pcode and pcode.old staying with SDSYS because
 * BCOMP addresses them relative to @sdsys - so <sysdir>/bin no longer holds
 * any executable at all, and BOTH call sites were pointing at a directory
 * containing two data files.
 *
 * The failure was silent in both.  start_sd() execs the daemon from a forked
 * child that has already called daemon(), so a failed exec printed nothing and
 * sd -start still reported success; the daemon simply never ran.  And it
 * worked perfectly in development, where <sysdir>/bin does hold the binaries,
 * which is why it survived until there was an install to test.
 *
 * Deriving the location from the running executable rather than naming it
 * keeps the two together by construction, so the next layout change does not
 * reintroduce this.  It is also the same rule the MSYS2 runtime itself uses to
 * find its POSIX root, which is why sd.exe and its DLLs must share a directory
 * (the trap in PROJECT_STATUS.md 6).
 *
 * /proc/self/exe is a Linux interface that the MSYS2 runtime implements.
 * Measured 14 Aug 2026: it resolves correctly from a path containing spaces,
 * and it reports the name WITHOUT the .exe extension - which is what is
 * wanted, since execl() and system() both append it, and the code this
 * replaced named "sdlnxd" and "sd" the same way.  It becomes a stage 2
 * question along with the rest of the POSIX layer, where the native answer is
 * GetModuleFileName().
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"

#include <unistd.h>

/* ======================================================================
   exe_directory()  -  Directory holding the running executable

   Returns FALSE and leaves buff undefined if the location cannot be
   determined, or will not fit.  Callers must fail rather than fall back on a
   guess: launching the wrong executable is worse than launching none.      */

bool exe_directory(char* buff, int buff_len) {
  ssize_t n;
  char* p;

  if ((buff == NULL) || (buff_len < 2))
    return FALSE;

  n = readlink("/proc/self/exe", buff, (size_t)(buff_len - 1));

  /* readlink() neither terminates the string nor reports truncation, so a
     result that exactly fills the buffer has to be treated as too long.    */

  if ((n <= 0) || (n >= buff_len - 1))
    return FALSE;

  buff[n] = '\0';

  p = strrchr(buff, '/');
  if (p == NULL)
    return FALSE;

  /* Truncating at the final separator leaves an empty string for an
     executable in the root directory, which is right: callers append
     "/name", giving "/name".                                              */

  *p = '\0';

  return TRUE;
}

/* END-CODE */
