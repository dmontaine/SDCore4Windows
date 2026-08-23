/* probe-console.c - can SD drive the Windows Console API from an MSYS2 build?
 *
 * 23 Aug 26 Windows port.  Built and run by probe-console.ps1, IN A REAL
 * CONSOLE.  It is an instrument, not a verifier: there is nothing here to pass
 * or fail, and a person reads what it prints.  probe-keys.ps1 is the same
 * shape and says why that distinction matters.
 *
 * WHAT IT DECIDES.  Section 7 step 13's first leg is linuxio.c's six termios
 * calls -> Console API.  The leg is only doable BEFORE the toolchain flip if
 * SetConsoleMode() called from an MSYS2 process actually sticks, because under
 * MSYS2 fd 0 is a CYGWIN descriptor and Cygwin's own tty layer is what
 * implements termios.  Two layers would then both own the console.
 *
 * Reasoning cannot settle it, and the cost of guessing is the console: this is
 * the code path every interactive session uses.  So the probe does what SD
 * does, then does what SD WOULD do natively, and looks at what survives.
 *
 *   1. is fd 0 a tty, and is its handle a real console?
 *   2. the console mode as we found it
 *   3. the console mode after Cygwin's own termios raw-mode setup
 *      - this is the interesting one: it shows Cygwin's raw mode
 *        expressed in Console API terms, which is the target to match
 *   4. the console mode after we set SD's intended native mode directly
 *   5. THE DECIDING STEP - read keystrokes, then read the mode back.
 *      If Cygwin has stomped it, the leg must wait for the flip.
 *
 * Restores both the termios settings and the console modes on the way out,
 * including on Ctrl-C, because leaving a console in raw mode with no echo is
 * a thing the operator would have to close the window to escape.
 */

#include <windows.h>
#include <io.h>
#include <stdio.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <signal.h>

static HANDLE hIn = INVALID_HANDLE_VALUE;
static HANDLE hOut = INVALID_HANDLE_VALUE;
static DWORD in_mode_entry = 0, out_mode_entry = 0;
static struct termios tty_entry;
static int tty_saved = 0, modes_saved = 0;

static void restore(void) {
  if (modes_saved) {
    SetConsoleMode(hIn, in_mode_entry);
    SetConsoleMode(hOut, out_mode_entry);
  }
  if (tty_saved)
    tcsetattr(0, TCSANOW, &tty_entry);
}

static void on_signal(int sig) {
  (void)sig;
  restore();
  printf("\n(interrupted - console restored)\n");
  _exit(2);
}

/* The input-mode bits by name, so the reader does not decode hex by hand. */
static void show_in(const char *tag) {
  DWORD m = 0;
  if (!GetConsoleMode(hIn, &m)) {
    printf("  %-34s GetConsoleMode FAILED, error %lu\n", tag, (unsigned long)GetLastError());
    return;
  }
  printf("  %-34s 0x%08lx  %s%s%s%s\n", tag, (unsigned long)m,
         (m & ENABLE_LINE_INPUT) ? "LINE " : "-line ",
         (m & ENABLE_ECHO_INPUT) ? "ECHO " : "-echo ",
         (m & ENABLE_PROCESSED_INPUT) ? "PROCESSED " : "-processed ",
         (m & ENABLE_VIRTUAL_TERMINAL_INPUT) ? "VT" : "-vt");
}

int main(void) {
  DWORD m = 0, after = 0, want = 0;
  struct termios raw;
  unsigned char buf[64];
  int n, i;

  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);

  printf("probe-console - section 7 step 13, leg 1\n");
  printf("=========================================\n\n");

  /* --- 1. Is this a console at all? ------------------------------------ */

  printf("1. What fd 0 and fd 1 are\n");
  printf("  isatty(0) = %d, isatty(1) = %d\n", isatty(0), isatty(1));

  hIn = (HANDLE)get_osfhandle(0);
  hOut = (HANDLE)get_osfhandle(1);
  printf("  get_osfhandle(0) = %p, get_osfhandle(1) = %p\n",
         (void *)hIn, (void *)hOut);

  if (hIn == INVALID_HANDLE_VALUE || !GetConsoleMode(hIn, &in_mode_entry)) {
    printf("\n  fd 0 IS NOT A CONSOLE HANDLE (error %lu).\n", (unsigned long)GetLastError());
    printf("  Run this in a real console window, not through a pipe.\n");
    printf("  ANSWER: undetermined - the probe did not get to the question.\n");
    return 2;
  }
  if (!GetConsoleMode(hOut, &out_mode_entry)) {
    printf("\n  fd 1 is not a console handle (error %lu).\n", (unsigned long)GetLastError());
    return 2;
  }
  modes_saved = 1;
  printf("  Both are real console handles, so the question is live.\n\n");

  /* --- 2 and 3. What Cygwin's own raw mode looks like ------------------ */

  printf("2. Console input mode as found\n");
  show_in("on entry");
  printf("\n");

  printf("3. After Cygwin's termios raw mode - what linuxio.c does today\n");
  if (tcgetattr(0, &tty_entry) != 0) {
    printf("  tcgetattr failed - not a tty after all\n");
    restore();
    return 2;
  }
  tty_saved = 1;
  raw = tty_entry;
  raw.c_iflag &= ~(ISTRIP | ICRNL | IGNCR | INLCR | IXON | IXOFF);
  raw.c_iflag |= IGNPAR;
  raw.c_oflag &= ~OPOST;
  raw.c_cflag &= ~CSIZE;
  raw.c_cflag |= CS8;
  raw.c_lflag &= ~(ICANON | ECHO | ECHONL);
  raw.c_lflag |= ISIG;
  raw.c_cc[VMIN] = 1;
  tcsetattr(0, TCSANOW, &raw);
  show_in("after tcsetattr(raw)");
  printf("  ^ this is the mode the native code has to reproduce\n\n");

  /* --- 4. Set SD's intended native mode directly ------------------------ */

  printf("4. Setting SD's intended NATIVE mode with SetConsoleMode\n");
  GetConsoleMode(hIn, &m);
  want = m;
  want &= ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
  want |= ENABLE_PROCESSED_INPUT; /* ISIG on - set_term(TRUE) */
  if (!SetConsoleMode(hIn, want)) {
    printf("  SetConsoleMode FAILED, error %lu\n", (unsigned long)GetLastError());
    printf("  ANSWER: NO - the leg must wait for the toolchain flip.\n");
    restore();
    return 0;
  }
  show_in("requested");
  printf("\n");

  /* --- 5. Does it survive a Cygwin read? ------------------------------- */

  printf("5. THE DECIDING STEP\n");
  printf("  Press the LEFT ARROW key, then press Enter.\n");
  printf("  (an arrow reads 27 91 68 when it arrives the way SD expects)\n");
  printf("  bytes: ");
  fflush(stdout);

  n = read(0, buf, sizeof(buf));
  if (n <= 0)
    printf("(read returned %d)", n);
  for (i = 0; i < n; i++)
    printf("%d ", buf[i]);
  printf("\n\n");

  if (!GetConsoleMode(hIn, &after)) {
    printf("  GetConsoleMode after the read FAILED, error %lu\n", (unsigned long)GetLastError());
    restore();
    return 0;
  }
  show_in("after a Cygwin read()");

  printf("\n=========================================\n");
  if (after == want) {
    printf("ANSWER: YES.  The mode we set survived a Cygwin read unchanged,\n");
    printf("so linuxio.c can move to the Console API BEFORE the flip.\n");
  } else {
    printf("ANSWER: NO.  Cygwin changed the mode under us:\n");
    printf("  we set   0x%08lx\n", (unsigned long)want);
    printf("  read got 0x%08lx\n", (unsigned long)after);
    printf("Two layers own the console, so linuxio.c must move WITH the\n");
    printf("toolchain flip, like the sys/cygwin.h calls.  Section 7 step 13.\n");
  }

  restore();
  printf("(console restored)\n");
  return 0;
}
