/* probe-sessionpipe-child.c - the SESSION stand-in for probe-sessionpipe.c: a
 * CYGWIN process, raw-spawned as the user, OPENS a named pipe by name itself
 * and tries to use it as the pollable, bidirectional stream with clean EOF that
 * sd needs for its session I/O.
 *
 * 17 Sep 26 Windows port, RELEASE_1.1 55 direction (a), the RECONNECT handover.
 * probe-sessionsp measured that a user-spawned Cygwin session cannot INHERIT
 * the relay's socketpair (a raw Win32 spawn does not carry a Cygwin socket fd).
 * So under (a) the session must open its OWN channel to the front/relay.  A
 * named pipe is the channel with no local security hole: the server side
 * (native, the relay) can put a SID-scoped DACL on the pipe so no other user
 * can open it, and can call GetNamedPipeClientProcessId to bind the connection
 * to exactly the session process it spawned - both kernel-enforced, neither
 * resting on an app-level secret.  What is NOT guaranteed, and is the whole
 * point of this file, is the mechanics: sd's I/O is poll/select-based, so the
 * pipe is only usable if the Cygwin runtime wraps the handle into a fd that
 * POLLS and reports EOF, not merely one that reads once.
 *
 * The session opens the pipe with CreateFile (a native HANDLE) and adopts it
 * with cygwin_attach_handle_to_fd.  RELEASE_1.1 43 found an INHERITED pipe
 * handle adopted this way read EBADF; a pipe the session opens ITSELF is a
 * different handle in the process that will use it, which is why this is worth
 * measuring rather than assuming from 43.
 *
 * No <sys/socket.h> here (that is what cannot share a TU with <windows.h>); a
 * named pipe needs only CreateFile, so windows.h + sys/cygwin.h + the POSIX
 * poll/read/write headers coexist, the same set win32s4u.c and probe-impfork.c
 * use.
 *
 * Launched by probe-sessionpipe.exe:
 *   probe-sessionpipe-child.exe --hello                       exit 7
 *   probe-sessionpipe-child.exe --client <pipename> <report>
 * It writes every observation to <report> (a plain path), then, on the fd it
 * adopted for the pipe:
 *   1. a zero-timeout poll                                    - informational
 *   2. reads one greeting line the server (relay) sends       - leg READ
 *   3. writes one ack line back                               - leg WRITE
 *   4. echoes every byte until EOF                            - legs BULK, EOF
 * Exit 0 when read, write, bulk and EOF all held on a POLLABLE fd; 3 when the
 * adopted fd could not carry them (the falsified-if: the Cygwin session cannot
 * use a self-opened named pipe, so the reconnect must use a loopback socket);
 * 2 for a setup failure.
 *
 * Build CYGWIN (msys-2.0), from gplbld in MSYS2's MSYS bash, -lcygwin first:
 *   gcc -O2 -Wall -o probe-sessionpipe-child.exe probe-sessionpipe-child.c -lcygwin
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sys/cygwin.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BULK_BYTES (256L * 1024L)

static FILE* rep = NULL;
static void say(const char* fmt, ...) {
  va_list ap;
  if (!rep)
    return;
  va_start(ap, fmt);
  vfprintf(rep, fmt, ap);
  va_end(ap);
  fputc('\n', rep);
  fflush(rep);
}

/* read() with a deadline via poll - sd's binding-preamble loop shape, and the
   thing that fails if the adopted fd is not pollable. */
static long read_wait(int fd, char* buf, long n, int ms) {
  struct pollfd p;
  long r;
  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;
  r = poll(&p, 1, ms);
  if (r < 0)
    return -1000 - errno; /* poll itself refused the fd */
  if (r == 0)
    return -1;            /* timeout */
  errno = 0;
  r = (long)read(fd, buf, n);
  return r < 0 ? -2000 - errno : r;
}

/* Echo every byte until EOF - blocking read/write, the shape sd's session side
   actually uses on its channel (in the product the nonblocking poll loop is the
   RELAY's job, native and already proven; the session does ordinary read/write
   and selects only to WAIT for input, which the poll leg above already showed
   works).  Each read is preceded by a poll so a stuck fd is caught out loud
   rather than blocking for ever.  Returns bytes echoed, or -1 on a break before
   a clean EOF. */
static long echo_until_eof(int fd) {
  long echoed = 0;
  char buf[16384];
  for (;;) {
    struct pollfd p;
    long n, off;
    int r;
    p.fd = fd;
    p.events = POLLIN;
    p.revents = 0;
    r = poll(&p, 1, 15000);
    if (r < 0) {
      say("  echo: poll errno %d after %ld bytes - fd went bad", errno, echoed);
      return -1;
    }
    if (r == 0) {
      say("  echo: poll timed out after %ld bytes - STALLED", echoed);
      return -1;
    }
    n = (long)read(fd, buf, sizeof buf);
    if (n == 0)
      break; /* the clean EOF sd needs when the far end closes */
    if (n < 0) {
      say("  echo: read errno %d after %ld bytes", errno, echoed);
      return -1;
    }
    for (off = 0; off < n;) {
      long w = write(fd, buf + off, (size_t)(n - off));
      if (w <= 0) {
        say("  echo: write errno %d after %ld bytes", errno, echoed);
        return -1;
      }
      off += w;
    }
    echoed += n;
  }
  return echoed;
}

int main(int argc, char** argv) {
  HANDLE h;
  int fd;
  struct pollfd p;
  char line[256];
  long r, echoed;

  if (argc >= 2 && strcmp(argv[1], "--hello") == 0)
    return 7;

  if (argc < 4 || strcmp(argv[1], "--client") != 0) {
    fprintf(stderr, "usage: %s --client <pipename> <reportfile>\n", argv[0]);
    return 2;
  }
  rep = fopen(argv[3], "w");
  if (!rep) {
    fprintf(stderr, "cannot open report %s: %s\n", argv[3], strerror(errno));
    return 2;
  }
  say("probe-sessionpipe-child (Cygwin SESSION, spawned as the user)");
  say("  opening the pipe the front/relay named: %s", argv[2]);

  /* Open the pipe ourselves - a native handle, in the process that will use it
     (unlike 43's inherited-pipe EBADF). */
  h = CreateFileA(argv[2], GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING,
                  0, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    say("  OPEN  : FAILED, CreateFile error %lu (the DACL denied us, or the "
        "server was not listening)",
        (unsigned long)GetLastError());
    return 3;
  }
  say("  OPEN  : OK, got a native pipe handle");

  /* Adopt it into the Cygwin runtime as a binary, read/write fd. */
  errno = 0;
  fd = cygwin_attach_handle_to_fd("/dev/sd-relay-pipe", -1, h, 1,
                                  GENERIC_READ | GENERIC_WRITE);
  if (fd < 0) {
    say("  ATTACH: FAILED, cygwin_attach_handle_to_fd errno %d (%s)", errno,
        strerror(errno));
    return 3;
  }
  say("  ATTACH: OK, adopted as fd %d", fd);

  /* Is the adopted fd pollable at all?  A generic fhandler that reads but does
     not poll is exactly the failure that sends the reconnect to a socket. */
  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;
  r = poll(&p, 1, 0);
  say("  fd %d poll(0 ms) : %ld revents=0x%x%s", fd, r, p.revents,
      r < 0 ? " - POLL REFUSED THE FD (not usable for sd's I/O)" : "");

  /* Leg READ. */
  memset(line, 0, sizeof line);
  r = read_wait(fd, line, sizeof line - 1, 5000);
  if (r <= 0) {
    say("  READ  : FAILED r=%ld (%s) - the adopted fd carried no greeting", r,
        r == -1 ? "timeout" : r <= -1000 && r > -2000 ? "poll refused the fd"
                                                       : "read error");
    return 3;
  }
  line[strcspn(line, "\r\n")] = '\0';
  say("  READ  : OK, got \"%s\"", line);

  /* Leg WRITE. */
  r = (long)write(fd, "SESSION->RELAY ack\n", 19);
  if (r != 19) {
    say("  WRITE : FAILED r=%ld errno %d", r, errno);
    return 3;
  }
  say("  WRITE : OK, wrote 19 bytes");

  /* Legs BULK + EOF. */
  echoed = echo_until_eof(fd);
  if (echoed < 0) {
    say("  BULK  : FAILED - the echo loop broke before EOF");
    return 3;
  }
  say("  BULK  : OK, echoed %ld bytes", echoed);
  say("  EOF   : OK, read() returned 0 when the server closed its end");
  say("  VERDICT: the spawned Cygwin session used a SELF-OPENED named pipe as a "
      "pollable stream (read, write, %ld bytes echoed, clean EOF)", echoed);
  return 0;
}
/* END-CODE */
