/* probe-pipestd-child.c - the corrected SESSION stand-in for RELEASE_1.1 55
 * direction (a): a CYGWIN process, raw-spawned as the user, is handed a NATIVE
 * named-pipe end on its STANDARD HANDLES (not by cygwin_attach_handle_to_fd),
 * and the one thing that must hold is that select()/poll reports the fd NOT
 * ready when it is empty.
 *
 * 17 Sep 26 Windows port.  probe-sessionpipe used cygwin_attach_handle_to_fd to
 * adopt the pipe, and it appeared to work - but sd.c:460 / PROJECT_STATUS §7
 * step 11 record, MEASURED, that a descriptor built that way from a raw HANDLE
 * is reported PERMANENTLY READY by select() ("sel.always_ready 1"), which makes
 * sd's poll-driven input layer spin - alive, silent, never replying.
 * probe-sessionpipe never tested the EMPTY-poll case (it always had data or
 * EOF), so it validated a mechanism sd cannot use.  The shipping SDLocal client
 * path avoids the trap by handing the pipe over as STANDARD HANDLES (sd.c's
 * -C1!0), which Cygwin wraps as a real fhandler_pipe with working select, not
 * as a generic always-ready fhandler.  This measures that path for a
 * raw-spawned session: does an inherited native-pipe std handle SELECT
 * CORRECTLY WHEN EMPTY?
 *
 * fds 0 and 1 are the pipe (duplex).  Sequence, made deterministic so the
 * empty-poll really is empty:
 *   1. EMPTY-POLL: poll(0, POLLIN, 0) BEFORE anything is sent - must be revents
 *      0.  A POLLIN here with no data is the always-ready trap = FAIL.
 *   2. write "READY\n" so the parent knows the empty-poll is done and may send.
 *   3. read the greeting (poll then read - proves poll reports READY on data).
 *   4. write the ack; echo until EOF.
 * Exit 0 when the empty-poll was correctly not-ready AND read/write/echo/EOF
 * held; 3 when empty-poll was ALWAYS-READY (the trap) or a leg failed; 2 setup.
 *
 * Build CYGWIN, from gplbld in MSYS2's MSYS bash, -lcygwin first:
 *   gcc -O2 -Wall -o probe-pipestd-child.exe probe-pipestd-child.c -lcygwin
 * No windows.h and no cygwin_attach_handle_to_fd - the whole point is to use
 * the std handles as the runtime wrapped them.
 */
#include <errno.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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

static long read_wait(int fd, char* buf, long n, int ms) {
  struct pollfd p;
  long r;
  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;
  r = poll(&p, 1, ms);
  if (r < 0)
    return -1000;
  if (r == 0)
    return -1;
  r = (long)read(fd, buf, n);
  return r;
}

static long echo_until_eof(int fd_r, int fd_w) {
  long echoed = 0;
  char buf[16384];
  for (;;) {
    struct pollfd p;
    long n, off;
    int r;
    p.fd = fd_r;
    p.events = POLLIN;
    p.revents = 0;
    r = poll(&p, 1, 15000);
    if (r <= 0) {
      say("  echo: poll %d after %ld bytes - STALLED", r, echoed);
      return -1;
    }
    n = (long)read(fd_r, buf, sizeof buf);
    if (n == 0)
      break;
    if (n < 0) {
      say("  echo: read errno %d", errno);
      return -1;
    }
    for (off = 0; off < n;) {
      long w = write(fd_w, buf + off, (size_t)(n - off));
      if (w <= 0) {
        say("  echo: write errno %d", errno);
        return -1;
      }
      off += w;
    }
    echoed += n;
  }
  return echoed;
}

int main(int argc, char** argv) {
  struct pollfd p;
  char line[256];
  long r, echoed;
  int empty_ok;

  if (argc >= 2 && strcmp(argv[1], "--hello") == 0)
    return 7;
  if (argc < 3 || strcmp(argv[1], "--stdio") != 0) {
    fprintf(stderr, "usage: %s --stdio <reportfile>\n", argv[0]);
    return 2;
  }
  rep = fopen(argv[2], "w");
  if (!rep) {
    fprintf(stderr, "cannot open report %s\n", argv[2]);
    return 2;
  }
  say("probe-pipestd-child (Cygwin SESSION, native pipe on std handles)");

  /* 1. THE TEST THAT MATTERS: poll an EMPTY pipe.  Nothing has been sent yet -
     the parent waits for our READY line before sending - so a correct
     fhandler_pipe answers 0 (not ready), and the always-ready trap answers
     POLLIN. */
  p.fd = 0;
  p.events = POLLIN;
  p.revents = 0;
  r = poll(&p, 1, 0);
  empty_ok = (r == 0 && p.revents == 0);
  say("  EMPTY-POLL: poll(0,0ms)=%ld revents=0x%x -> %s", r, p.revents,
      empty_ok ? "OK, not ready when empty (real select)"
               : "FAIL, ALWAYS-READY TRAP (sel.always_ready) - sd would spin");

  /* 2. tell the parent the empty-poll is done. */
  if (write(1, "READY\n", 6) != 6) {
    say("  READY : write failed errno %d", errno);
    return 3;
  }

  /* 3. greeting (poll must now report ready). */
  memset(line, 0, sizeof line);
  r = read_wait(0, line, sizeof line - 1, 5000);
  if (r <= 0) {
    say("  READ  : FAILED r=%ld", r);
    return 3;
  }
  line[strcspn(line, "\r\n")] = '\0';
  say("  READ  : OK, got \"%s\"", line);

  /* 4. ack + echo + EOF. */
  if (write(1, "SESSION->RELAY ack\n", 19) != 19) {
    say("  WRITE : FAILED errno %d", errno);
    return 3;
  }
  say("  WRITE : OK");
  echoed = echo_until_eof(0, 1);
  if (echoed < 0) {
    say("  BULK  : FAILED");
    return 3;
  }
  say("  BULK  : OK, echoed %ld bytes", echoed);
  say("  EOF   : OK, read()==0 on the parent's close");

  if (!empty_ok) {
    say("  VERDICT: read/write/echo worked but the EMPTY-POLL trap makes this "
        "fd unusable for sd's select-driven input layer");
    return 3;
  }
  say("  VERDICT: native pipe on std handles selects correctly when empty AND "
      "carries the traffic - usable for sd's session I/O");
  return 0;
}
/* END-CODE */
