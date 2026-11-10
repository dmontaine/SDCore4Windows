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

/* ======================================================================
   console_window_cells()  -  the console WINDOW's size, as Windows has it now.

   10 Nov 26 Windows port - RELEASE_1.1 212.  The owner, 10 Nov: after Windows
   Terminal's F11 (full screen) the page did not grow to the new size, while
   the maximize button made it grow.  The tty's TIOCGWINSZ answer, which
   linuxio.c asks, is the MSYS2 runtime's, and it is brought up to date only
   when the runtime handles console input; F11 is the terminal's own key and
   sends SD no input, while a click on the maximize button does.  This asks
   the console itself: the visible window (srWindow), not the buffer, which
   can be taller.  Returns 1 and the size, or 0 when there is no console (an
   ssh session, a pipe, a file) - the caller then keeps the tty's answer.   */

int console_window_cells(int* cols, int* rows) {
  HANDLE h;
  CONSOLE_SCREEN_BUFFER_INFO info;
  int c;
  int r;

  h = GetStdHandle(STD_OUTPUT_HANDLE);
  if ((h == NULL) || (h == INVALID_HANDLE_VALUE))
    return 0;
  if (!GetConsoleScreenBufferInfo(h, &info))
    return 0;
  c = info.srWindow.Right - info.srWindow.Left + 1;
  r = info.srWindow.Bottom - info.srWindow.Top + 1;
  if ((c <= 0) || (r <= 0))
    return 0;
  *cols = c;
  *rows = r;
  return 1;
}

/* ======================================================================
   grow_console_window()  -  make a small classic console window big enough
   for SD's full-screen pages.

   10 Nov 26 Windows port - RELEASE_1.1 215.  A console window opens at 120
   by 30, from the Start menu shortcut or a typed sd, and HOME, the IDE, CED
   and the toolkit take 140 by 43 at least, so an account that starts in HOME
   was refused, and on Core signed out (S.164).  The owner, 10 Nov, chose
   "SD grows its window": at start-up a CLASSIC console window smaller than
   want_cols by want_rows is made that size, or as big as the screen allows
   with the current font (GetLargestConsoleWindowSize).

   IT NEVER SHRINKS A WINDOW, and it acts only when all of these hold:
   - input and output are both a console: a script feeding SD, or reading
     its output, keeps the window it has;
   - the window is conhost's own (class ConsoleWindowClass).  Windows
     Terminal's sessions run on a pseudo console whose window is a hidden
     stand-in: the size there belongs to the terminal, and a program that
     resizes the buffer under it leaves the terminal and the buffer out of
     step.  So Windows Terminal is left alone, and its window is the person's
     to size.
   user32.dll is loaded here, for GetClassNameA only, rather than linked, so
   sd.exe's list of the DLLs it imports does not change.

   The buffer grows first (a window cannot be wider or taller than its
   buffer), then the window; the buffer's scrollback is kept.  Returns 1 if
   the window was made bigger, 0 if nothing was done.                      */

typedef int(WINAPI* class_name_fn)(HWND, LPSTR, int);

int grow_console_window(int want_cols, int want_rows) {
  HANDLE out;
  HANDLE in;
  DWORD mode;
  HWND w;
  HMODULE user32;
  class_name_fn class_name;
  char cls[64];
  int n;
  CONSOLE_SCREEN_BUFFER_INFO info;
  COORD largest;
  COORD buf;
  SMALL_RECT r;
  int cols;
  int rows;
  int c;

  out = GetStdHandle(STD_OUTPUT_HANDLE);
  in = GetStdHandle(STD_INPUT_HANDLE);
  if ((out == NULL) || (out == INVALID_HANDLE_VALUE) || (in == NULL) || (in == INVALID_HANDLE_VALUE))
    return 0;
  if (!GetConsoleMode(in, &mode)) /* input is not a console: a script */
    return 0;
  if (!GetConsoleScreenBufferInfo(out, &info)) /* nor is output */
    return 0;

  w = GetConsoleWindow();
  if (w == NULL)
    return 0;
  user32 = LoadLibraryA("user32.dll");
  if (user32 == NULL)
    return 0;
  class_name = (class_name_fn)(void (*)(void))GetProcAddress(user32, "GetClassNameA");
  n = (class_name == NULL) ? 0 : class_name(w, cls, (int)sizeof(cls));
  FreeLibrary(user32);
  if ((n <= 0) || (lstrcmpA(cls, "ConsoleWindowClass") != 0))
    return 0; /* not conhost's window: Windows Terminal, or something else */

  cols = info.srWindow.Right - info.srWindow.Left + 1;
  rows = info.srWindow.Bottom - info.srWindow.Top + 1;
  if ((cols >= want_cols) && (rows >= want_rows))
    return 0;

  largest = GetLargestConsoleWindowSize(out);
  c = want_cols;
  if (c > largest.X)
    c = largest.X;
  if (c < cols)
    c = cols;
  n = want_rows;
  if (n > largest.Y)
    n = largest.Y;
  if (n < rows)
    n = rows;
  if ((c == cols) && (n == rows))
    return 0; /* the screen takes no more */

  buf = info.dwSize;
  if (buf.X < c)
    buf.X = (SHORT)c;
  if (buf.Y < n)
    buf.Y = (SHORT)n;
  if ((buf.X != info.dwSize.X) || (buf.Y != info.dwSize.Y)) {
    if (!SetConsoleScreenBufferSize(out, buf))
      return 0;
  }

  r.Left = 0;
  r.Right = (SHORT)(c - 1);
  r.Top = info.srWindow.Top;
  if (r.Top + n > buf.Y)
    r.Top = (SHORT)(buf.Y - n);
  r.Bottom = (SHORT)(r.Top + n - 1);
  if (!SetConsoleWindowInfo(out, TRUE, &r))
    return 0;
  return 1;
}
