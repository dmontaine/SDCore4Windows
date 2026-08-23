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
 * the code path every interactive session uses.
 *
 * ---------------------------------------------------------------------------
 * THE FIRST VERSION OF THIS PROBE ANSWERED "YES" ON A RUN WHERE read() HAD
 * FAILED, and that is why the verdict logic below is as fussy as it is.
 * 23 Aug 2026, first real-console run: step 5 printed "(read returned -1)" and
 * the probe still concluded "the mode we set survived a Cygwin read
 * unchanged" - because all it compared was the mode bits, and a read that
 * never happened cannot disturb them.  A check that passes without meaning it
 * is worse than no check.  So now:
 *
 *   - a verdict of YES requires a read that SUCCEEDED,
 *   - a failed read prints errno rather than just "-1",
 *   - there is a CONTROL READ FIRST, in Cygwin's raw mode and nothing of
 *     ours, so that a later failure can be attributed at all, and
 *   - if the deciding read fails, the entry mode is put back and the read is
 *     tried AGAIN.  Success then pins the failure on our SetConsoleMode,
 *     which is a decisive NO; failure both ways is INCONCLUSIVE and says so.
 *
 * Without those two controls a failed read is ambiguous, and the ambiguity
 * gets resolved by whoever wants an answer.
 * ---------------------------------------------------------------------------
 *
 * ALREADY MEASURED ON THAT FIRST RUN, and it holds whatever the verdict turns
 * out to be: on entry this console reads 0x2e8 - line input off, echo off,
 * processed input off, virtual-terminal input ON - and Cygwin's own
 * tcsetattr(raw) leaves it at 0x2e8, unchanged.  So CYGWIN IS ALREADY DRIVING
 * SetConsoleMode and translating termios into console modes, and 0x2e8 is the
 * mode the native code has to reproduce.
 *
 * Restores the termios settings and both console modes on the way out,
 * including on Ctrl-C, because leaving a console raw with no echo is a thing
 * the operator would have to close the window to escape.
 */

#include <windows.h>
#include <io.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <termios.h>
#include <unistd.h>
#include <signal.h>

/* Step 3 clears OPOST, so from there a bare \n does not return the carriage
   and every later line staircases across the screen - the first run printed
   its entire verdict that way.  CRLF costs nothing before raw mode and is
   correct after it. */
#define NL "\r\n"

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
  printf(NL "(interrupted - console restored)" NL);
  _exit(2);
}

/* The input-mode bits by name, so the reader does not decode hex by hand. */
static void show_in(const char *tag) {
  DWORD m = 0;
  if (!GetConsoleMode(hIn, &m)) {
    printf("  %-34s GetConsoleMode FAILED, error %lu" NL, tag,
           (unsigned long)GetLastError());
    return;
  }
  printf("  %-34s 0x%08lx  %s%s%s%s" NL, tag, (unsigned long)m,
         (m & ENABLE_LINE_INPUT) ? "LINE " : "-line ",
         (m & ENABLE_ECHO_INPUT) ? "ECHO " : "-echo ",
         (m & ENABLE_PROCESSED_INPUT) ? "PROCESSED " : "-processed ",
         (m & ENABLE_VIRTUAL_TERMINAL_INPUT) ? "VT" : "-vt");
}

/* Retries EINTR, which a stray signal would otherwise present as a broken
   read and this probe would then blame on SetConsoleMode. */
static int read_keys(unsigned char *buf, size_t len, int *err) {
  int n;
  do {
    errno = 0;
    n = (int)read(0, buf, len);
  } while (n < 0 && errno == EINTR);
  *err = errno;
  return n;
}

static void show_bytes(int n, int err, unsigned char *buf) {
  int i;
  printf("  bytes: ");
  if (n < 0) {
    printf("read FAILED, errno %d (%s)" NL, err, strerror(err));
    return;
  }
  if (n == 0) {
    printf("end of file" NL);
    return;
  }
  for (i = 0; i < n; i++)
    printf("%d ", buf[i]);
  printf(NL);
}

int main(void) {
  DWORD m = 0, after = 0, want = 0;
  struct termios raw;
  unsigned char buf[64];
  int n, err, n2 = 0, err2 = 0, retried = 0;

  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);

  printf("probe-console - section 7 step 13, leg 1" NL);
  printf("=========================================" NL NL);

  /* --- 1. Is this a console at all? ------------------------------------ */

  printf("1. What fd 0 and fd 1 are" NL);
  printf("  isatty(0) = %d, isatty(1) = %d" NL, isatty(0), isatty(1));

  hIn = (HANDLE)get_osfhandle(0);
  hOut = (HANDLE)get_osfhandle(1);

  if (hIn == INVALID_HANDLE_VALUE || !GetConsoleMode(hIn, &in_mode_entry)) {
    printf(NL "  fd 0 IS NOT A CONSOLE HANDLE (error %lu)." NL,
           (unsigned long)GetLastError());
    printf("  Run this in a real console window, not through a pipe." NL);
    printf("  ANSWER: undetermined - the probe did not reach the question." NL);
    return 2;
  }
  if (!GetConsoleMode(hOut, &out_mode_entry)) {
    printf(NL "  fd 1 is not a console handle (error %lu)." NL,
           (unsigned long)GetLastError());
    return 2;
  }
  modes_saved = 1;
  printf("  Both are real console handles, so the question is live." NL NL);

  /* --- 2 and 3. What Cygwin's own raw mode looks like ------------------ */

  printf("2. Console input mode as found" NL);
  show_in("on entry");
  printf(NL);

  printf("3. After Cygwin's termios raw mode - what linuxio.c does today" NL);
  if (tcgetattr(0, &tty_entry) != 0) {
    printf("  tcgetattr failed - not a tty after all" NL);
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
  printf("  ^ the mode the native code has to reproduce" NL NL);

  /* --- 4. A CONTROL READ, BEFORE WE TOUCH ANYTHING --------------------- */

  printf("4. CONTROL read - Cygwin raw mode only, nothing of ours yet" NL);
  printf("   Press the LEFT ARROW key, then Enter." NL);
  printf("   (an arrow reads 27 91 68 when it arrives the way SD expects)" NL);
  n = read_keys(buf, sizeof(buf), &err);
  show_bytes(n, err, buf);
  if (n < 0) {
    printf(NL "  The control read ALREADY fails, before we set anything." NL);
    printf("  ANSWER: INCONCLUSIVE - the fault is not SetConsoleMode's, and" NL);
    printf("  nothing later in this probe could be attributed to it." NL);
    restore();
    return 0;
  }
  printf(NL);

  /* --- 5. Set SD's intended native mode directly ------------------------ */

  printf("5. Setting SD's intended NATIVE mode with SetConsoleMode" NL);
  GetConsoleMode(hIn, &m);
  want = m;
  want &= ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
  want |= ENABLE_PROCESSED_INPUT; /* ISIG on - set_term(TRUE) */
  if (!SetConsoleMode(hIn, want)) {
    printf("  SetConsoleMode FAILED, error %lu" NL,
           (unsigned long)GetLastError());
    printf("  ANSWER: NO - the leg must wait for the toolchain flip." NL);
    restore();
    return 0;
  }
  show_in("requested");
  printf(NL);

  /* --- 6. THE DECIDING STEP -------------------------------------------- */

  printf("6. THE DECIDING STEP - the same key, with our mode set" NL);
  printf("   Press the LEFT ARROW key, then Enter." NL);
  n = read_keys(buf, sizeof(buf), &err);
  show_bytes(n, err, buf);

  if (!GetConsoleMode(hIn, &after))
    after = 0;
  show_in("after a Cygwin read()");

  if (n < 0) {
    printf(NL "  Read failed.  Restoring the entry mode and retrying, to find"
           NL "  out whether OUR change is what broke it." NL);
    SetConsoleMode(hIn, in_mode_entry);
    printf("   Press the LEFT ARROW key once more, then Enter." NL);
    n2 = read_keys(buf, sizeof(buf), &err2);
    show_bytes(n2, err2, buf);
    retried = 1;
  }

  printf(NL "=========================================" NL);

  if (n >= 0 && after == want) {
    printf("ANSWER: YES.  A Cygwin read SUCCEEDED with our mode set, and the" NL);
    printf("mode was unchanged afterwards.  linuxio.c can move to the Console" NL);
    printf("API BEFORE the toolchain flip." NL);
  } else if (n >= 0) {
    printf("ANSWER: NO.  The read worked, but Cygwin changed the mode under us:" NL);
    printf("  we set   0x%08lx" NL, (unsigned long)want);
    printf("  read got 0x%08lx" NL, (unsigned long)after);
    printf("Two layers own the console, so linuxio.c moves WITH the flip." NL);
  } else if (retried && n2 >= 0) {
    printf("ANSWER: NO, and decisively.  The read failed with our mode set and" NL);
    printf("SUCCEEDED as soon as the entry mode was restored, so calling" NL);
    printf("SetConsoleMode underneath Cygwin's tty layer is what broke it." NL);
    printf("linuxio.c must move WITH the toolchain flip, like sys/cygwin.h." NL);
  } else {
    printf("ANSWER: INCONCLUSIVE.  The read failed both with our mode set and" NL);
    printf("with the entry mode restored, so the fault is not SetConsoleMode's" NL);
    printf("and this probe has not answered the question.  Do NOT read the" NL);
    printf("first failure as a NO." NL);
  }

  restore();
  printf("(console restored)" NL);
  return 0;
}
