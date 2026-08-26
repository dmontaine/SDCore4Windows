/* WIN32VT.C
 * Turn on the Windows console's ANSI/VT processing, so the escape sequences SD
 * already emits actually do something.
 *
 * 26 Aug 26 Windows port - written after the owner found that clear-screen and
 * cursor positioning worked when SD was started from cmd.exe and did nothing
 * when it was started from PowerShell.
 *
 * WHY THAT HAPPENS, AND IT IS NOTHING TO DO WITH POWERSHELL BEING DIFFERENT AT
 * SD.  The default terminal type is "windows", a clone of xterm, so everything
 * SD draws with goes out as ANSI - terminfo.src:318 gives clear=\E[H\E[J and
 * cup=\E[%i%p1%d;%p2%dH.  Whether the console ACTS on those is one flag on the
 * screen buffer, ENABLE_VIRTUAL_TERMINAL_PROCESSING, and it is off unless some
 * program turns it on.  cmd.exe turns it on.  WINDOWS POWERSHELL 5.1 DOES NOT
 * - PowerShell 7 does, which is why this can look intermittent across machines.
 * The flag lives on the buffer, not the process, so SD inherited whatever its
 * launcher happened to leave there and had no opinion of its own.
 *
 * ***SD NEVER CALLED SetConsoleMode ANYWHERE.***  It relied entirely on being
 * started by something that had.
 *
 * WHY THIS IS NOT THE CHANGE THAT WAS REVERTED ON 23 Aug 2026, which matters
 * because that revert is in HISTORY.md and reads like a rule against touching
 * the Console API at all.  That leg replaced linuxio.c's SIX termios calls -
 * INPUT: canonical mode and echo - with the Console API, and failed because
 * Cygwin's tty layer implements termios in USERSPACE and sits in front of the
 * console, so the password prompt echoed in clear.  This touches none of that.
 * It sets ONE OUTPUT flag, adds nothing and removes nothing, and leaves every
 * termios call exactly where it is.  Different handle, different direction,
 * different layer.
 *
 * IT IS ITS OWN FILE BECAUSE windows.h DOES NOT BELONG IN linuxio.c.  That
 * file includes netdb.h, sys/socket.h and sys/un.h; windows.h redefines enough
 * of the socket world to make a mess of them.  win32sem.c, win32peer.c and the
 * rest exist for exactly this reason and this follows them.
 *
 * ***IT FAILS QUIETLY AND THAT IS DELIBERATE.***  A session with no console at
 * all - a phantom, an API server, output redirected to a file - has nothing to
 * set, and an older Windows will refuse the flag.  None of those is a reason
 * to stop SD starting, and none of them wants an error on the screen either.
 * The caller is told whether it worked and does not currently care.
 */

#include <windows.h>

#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
/* Present since Windows 10 1511.  Defined here so an older SDK still builds;
   the runtime call is what decides, not the header. */
#define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#endif

static HANDLE vt_handle = INVALID_HANDLE_VALUE;
static DWORD vt_saved_mode = 0;
static int vt_changed = 0;

/* ======================================================================
   enable_console_vt()  -  ask the console to interpret ANSI escapes.

   Returns 1 if VT processing is on when this returns - whether or not this
   call is what turned it on - and 0 if there is no console to ask.         */

int enable_console_vt(void) {
  HANDLE h;
  DWORD mode;

  h = GetStdHandle(STD_OUTPUT_HANDLE);
  if ((h == NULL) || (h == INVALID_HANDLE_VALUE))
    return 0;

  /* Not a console - a pipe, a file, a Cygwin pty.  GetConsoleMode is how you
     find that out, and there is nothing to set in any of those cases.  A
     Cygwin pty needs nothing anyway: mintty interprets the escapes itself. */
  if (!GetConsoleMode(h, &mode))
    return 0;

  if (mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING)
    return 1; /* Somebody already did - cmd.exe, or a previous SD. */

  if (!SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING))
    return 0; /* Refused.  Older Windows, or a redirected handle. */

  /* Remembered so shut_console() can put the console back as it was found.
     LEAVING IT ON WOULD BE HARMLESS AND STILL WRONG: the flag belongs to the
     window, which outlives this process, and a program that changes something
     it did not own should hand it back. */
  vt_handle = h;
  vt_saved_mode = mode;
  vt_changed = 1;
  return 1;
}

/* ======================================================================
   restore_console_vt()  -  put the mode back, if this process changed it.  */

void restore_console_vt(void) {
  if (vt_changed) {
    SetConsoleMode(vt_handle, vt_saved_mode);
    vt_changed = 0;
  }
}
