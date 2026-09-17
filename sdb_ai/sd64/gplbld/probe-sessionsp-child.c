/* probe-sessionsp-child.c - the SESSION stand-in for probe-sessionsp.c: a
 * CYGWIN process, SPAWNED (not fork()ed) with one end of a Cygwin socketpair
 * placed on its standard handles, tries to use fds 0 and 1 as sd would - a
 * pollable, bidirectional stream that reports EOF when the far end closes.
 *
 * 17 Sep 26 Windows port, RELEASE_1.1 55 direction (a), crux (1).  Direction
 * (a) - chosen by the owner - spawns the authenticated API session AS THE USER
 * with CreateProcessAsUser, instead of fork()ing it from the LocalSystem
 * daemon.  sd's only channel to its TLS relay is one end of a Cygwin
 * socketpair(), which sd keeps on descriptors 0 and 1 (sd_tlssrv.c; the shape
 * Linux's relay() and sd's own SIGIO code already run on).  Today that fd
 * reaches the session because Cygwin's fork() carries the socketpair's
 * fhandler across the clone.  A SPAWN carries nothing: CreateProcessAsUser is
 * a raw Win32 spawn, so the runtime cannot hand the fd over the way fork does,
 * and the only thing that crosses is whatever is on the inherited STANDARD
 * HANDLES.  So the question this file answers is precisely: when the parent
 * puts the socketpair end on hStdInput/hStdOutput and raw-spawns this Cygwin
 * program, does the Cygwin runtime wrap fds 0 and 1 into a working stream -
 * bytes both ways AND a clean EOF - or only into something that reads once and
 * cannot poll or cannot see the close?
 *
 * WHY ONLY THIS MECHANISM, AND NOT cygwin_attach_handle_to_fd.  The attach
 * route was already MEASURED DEAD for a spawned Cygwin child: RELEASE_1.1 43
 * (HISTORY.md 16 Sep, probe-relaydrop iteration) found an inherited raw SOCKET
 * handle adopted with cygwin_attach_handle_to_fd reads EINVAL, because Cygwin
 * wraps it as a generic fhandler, not an fhandler_socket.  The standard-handle
 * path is the one nobody has measured and the one that matches what sd already
 * does (dup2 the connection to 0 and 1), so it is the only leg here.
 *
 * The pass criterion is FUNCTIONAL, not "it is a socket": sd needs a working
 * bidirectional stream with EOF on 0/1, and does not care whether Cygwin's
 * fhandler underneath is a socket or a pipe.  So SO_TYPE is printed for the
 * record but does not decide the verdict; bytes-both-ways-and-EOF does.
 *
 * Launched by probe-sessionsp.exe:
 *   probe-sessionsp-child.exe --hello                 exit 7: it initialised
 *   probe-sessionsp-child.exe --stdio <reportfile>
 * with fds 0 and 1 both bound to the session's socketpair end.  It writes
 * every observation to <reportfile> (a plain path, so the report channel does
 * not itself depend on the handle mechanism under test), then:
 *   1. describes fd 0 (SO_TYPE, a zero-timeout poll)          - informational
 *   2. reads one greeting line the parent (as relay) sends    - leg READ
 *   3. writes one ack line back                               - leg WRITE
 *   4. echoes every byte until EOF (the parent pushes 256 KiB
 *      and drains its echo, then closes its end)              - legs BULK, EOF
 * Exit 0 when read, write, bulk and EOF all held; 3 when the stream could not
 * carry them (the falsified-if); 2 for a setup failure.
 *
 * Build CYGWIN (msys-2.0), from gplbld in MSYS2's MSYS bash, -lcygwin first:
 *   gcc -O2 -Wall -o probe-sessionsp-child.exe probe-sessionsp-child.c -lcygwin
 * No windows.h here: <sys/socket.h> and <windows.h> cannot share a translation
 * unit, and the whole point is to be the Cygwin session, so it takes the POSIX
 * headers and nothing Win32.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
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

/* Print what fd 0 turned into, for the record.  A Cygwin socketpair end wrapped
   as fhandler_socket answers SO_TYPE SOCK_STREAM; wrapped as a pipe it fails
   getsockopt with ENOTSOCK - either way the functional legs below are what
   decide the verdict. */
static void describe(int fd) {
  int type = -1;
  socklen_t tl = sizeof type;
  struct pollfd p;
  int r;
  if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &tl) == 0)
    say("  fd %d SO_TYPE      : %d (%s)", fd, type,
        type == SOCK_STREAM ? "SOCK_STREAM" : "not a stream");
  else
    say("  fd %d SO_TYPE      : errno %d (%s) - wrapped as a non-socket fhandler",
        fd, errno, strerror(errno));
  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;
  r = poll(&p, 1, 0);
  say("  fd %d poll(0 ms)   : %d revents=0x%x%s", fd, r, p.revents,
      r < 0 ? " - POLL REFUSED THE FD" : "");
}

/* read() with a deadline via poll - exactly sd's binding-preamble loop shape.
   Returns bytes, 0 on EOF, negative errno on error, -ETIMEDOUT on timeout. */
static long read_wait(int fd, char* buf, long n, int ms) {
  struct pollfd p;
  long r;
  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;
  r = poll(&p, 1, ms);
  if (r < 0)
    return -errno;
  if (r == 0)
    return -ETIMEDOUT;
  errno = 0;
  r = (long)read(fd, buf, n);
  return r < 0 ? -errno : r;
}

/* Echo every byte from fd until EOF, non-blocking and poll-driven so a full
   send buffer is handled the way the relay's would be.  Returns the byte count
   echoed, or -1 if the loop broke before a clean EOF. */
static long echo_until_eof(int fd) {
  long echoed = 0;
  char pend[16384];
  long plen = 0, poff = 0;
  int saw_eof = 0;
  fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
  for (;;) {
    struct pollfd p;
    int r;
    p.fd = fd;
    p.events = (plen > poff) ? (POLLIN | POLLOUT) : POLLIN;
    if (saw_eof && plen == poff)
      break;
    p.revents = 0;
    r = poll(&p, 1, 10000);
    if (r <= 0) {
      say("  echo: poll %d errno %d after %ld bytes - STALLED", r, errno,
          echoed);
      return -1;
    }
    if ((p.revents & POLLOUT) && plen > poff) {
      long w = write(fd, pend + poff, (size_t)(plen - poff));
      if (w < 0 && errno != EAGAIN) {
        say("  echo: write errno %d", errno);
        return -1;
      }
      if (w > 0) {
        poff += w;
        echoed += w;
        if (poff == plen)
          plen = poff = 0;
      }
    }
    if ((p.revents & (POLLIN | POLLHUP)) && plen == poff) {
      long n = read(fd, pend, sizeof pend);
      if (n == 0) {
        saw_eof = 1; /* the clean EOF sd needs to see when the client closes */
      } else if (n < 0) {
        if (errno != EAGAIN) {
          say("  echo: read errno %d", errno);
          return -1;
        }
      } else {
        plen = n;
        poff = 0;
      }
    }
  }
  return echoed;
}

int main(int argc, char** argv) {
  char line[256];
  long r, echoed;

  if (argc >= 2 && strcmp(argv[1], "--hello") == 0)
    return 7; /* proves the Cygwin runtime initialised under whatever token */

  if (argc < 3 || strcmp(argv[1], "--stdio") != 0) {
    fprintf(stderr, "usage: %s --stdio <reportfile>\n", argv[0]);
    return 2;
  }
  rep = fopen(argv[2], "w");
  if (!rep) {
    fprintf(stderr, "cannot open report %s: %s\n", argv[2], strerror(errno));
    return 2;
  }
  say("probe-sessionsp-child (Cygwin SESSION, spawned as the user)");
  say("  fds 0 and 1 are the socketpair end the parent placed on std handles");

  describe(0);

  /* Leg READ: the parent, standing in for the relay, sends one greeting. */
  memset(line, 0, sizeof line);
  r = read_wait(0, line, sizeof line - 1, 5000);
  if (r <= 0) {
    say("  READ  : FAILED r=%ld (%s) - the stream carried no greeting", r,
        r == -ETIMEDOUT ? "timeout" : r == 0 ? "EOF too early" : strerror((int)-r));
    return 3;
  }
  line[strcspn(line, "\r\n")] = '\0';
  say("  READ  : OK, got \"%s\"", line);

  /* Leg WRITE: ack back on fd 1 (the same socketpair end). */
  r = (long)write(1, "SESSION->RELAY ack\n", 19);
  if (r != 19) {
    say("  WRITE : FAILED r=%ld errno %d - could not write the ack", r, errno);
    return 3;
  }
  say("  WRITE : OK, wrote 19 bytes");

  /* Legs BULK + EOF: echo the parent's 256 KiB and then see its close. */
  echoed = echo_until_eof(0);
  if (echoed < 0) {
    say("  BULK  : FAILED - the echo loop broke before EOF");
    return 3;
  }
  say("  BULK  : OK, echoed %ld bytes", echoed);
  say("  EOF   : OK, read() returned 0 when the parent closed its end");
  say("  VERDICT: the spawned Cygwin session used its socketpair end as a "
      "working stream (read, write, %ld bytes echoed, clean EOF)", echoed);
  return 0;
}
/* END-CODE */
