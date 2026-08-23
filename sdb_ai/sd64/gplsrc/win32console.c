/* WIN32CONSOLE.C
 * Console input modes for the session terminal.
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
 * 23 Aug 26 Windows port - written.  PROJECT_STATUS.md section 7 step 13,
 *           leg 1: linuxio.c's six termios calls become Console API calls.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * THE MODE IS MEASURED, NOT CHOSEN.  gplbld/probe-console.ps1, run in a real
 * console on 23 Aug 2026, read the console as 0x2e8 on entry and found
 * Cygwin's own tcsetattr(raw) left it at 0x2e8 unchanged - so Cygwin is
 * already driving SetConsoleMode and translating termios into console modes,
 * and 0x2e8 is what linuxio.c has been asking for all along without knowing
 * it.  This file asks for the same thing directly.
 *
 *   -ENABLE_LINE_INPUT          no line discipline, a key at a time
 *   -ENABLE_ECHO_INPUT          SD echoes, the console must not
 *   -ENABLE_PROCESSED_INPUT     see below - this one is not obvious
 *   +ENABLE_VIRTUAL_TERMINAL_INPUT   arrows arrive as ESC [ A .. D
 *
 * ENABLE_PROCESSED_INPUT IS OFF ON PURPOSE, AND IT IS THE ONE TO UNDERSTAND.
 * linuxio.c sets ISIG in its termios flags, so the obvious reading is that the
 * console should process control keys.  It must not: SD HANDLES THE BREAK KEY
 * ITSELF, IN SOFTWARE, at linuxio.c's input loop - it compares the incoming
 * byte against tio.break_char and calls break_key() when trap_break_char is
 * set.  For that to work the byte has to REACH SD, and processed input is
 * exactly what would intercept it first.  The measurement agrees: Cygwin's
 * raw mode leaves processed input OFF despite ISIG being on, because Cygwin
 * handles signals in its own tty layer rather than the console's.
 *
 * So set_term()'s trap_break toggle changes no console bit at all.  It is a
 * software flag and always was; only the termios call made it look otherwise.
 *
 * VIRTUAL TERMINAL INPUT IS WHAT KEEPS THE ARROW KEYS ALIVE - section 5.18,
 * and verify-keys section 3 is the standing guard.  It was already on in the
 * measured entry mode; setting it explicitly means a console that arrives
 * without it still gets it.
 *
 * A PIPED SESSION IS NOT AN ERROR.  Every verifier drives SD down a pipe, so
 * GetConsoleMode() failing is the normal case there and answers 0, which is
 * what a failed tcgetattr() did before.  It follows that THE SUITE CANNOT TEST
 * THIS FILE: use gplbld/probe-keys.ps1, in a real console, which is why that
 * script exists.
 *
 * END-DESCRIPTION
 */

#include <windows.h>
#include <io.h>

#include "win32console.h"

static HANDLE console_in = INVALID_HANDLE_VALUE;
static DWORD entry_mode = 0;
static DWORD sd_mode = 0;
static int have_console = 0;

int win32_console_init(void) {
  HANDLE h;

  have_console = 0;
  console_in = INVALID_HANDLE_VALUE;

  /* Standard input, through the descriptor rather than CONIN$, so that this
     follows whatever the session was actually given. */
  h = (HANDLE)get_osfhandle(0);
  if (h == INVALID_HANDLE_VALUE || h == NULL)
    return 0;

  if (!GetConsoleMode(h, &entry_mode))
    return 0; /* Not a console - a pipe, and that is normal */

  sd_mode = entry_mode;
  sd_mode &= ~(DWORD)(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT |
                      ENABLE_PROCESSED_INPUT);
  sd_mode |= (DWORD)ENABLE_VIRTUAL_TERMINAL_INPUT;

  if (!SetConsoleMode(h, sd_mode))
    return 0; /* Leave the console as we found it */

  console_in = h;
  have_console = 1;
  return 1;
}

void win32_console_set(void) {
  if (have_console)
    SetConsoleMode(console_in, sd_mode);
}

void win32_console_restore(void) {
  if (have_console)
    SetConsoleMode(console_in, entry_mode);
}
