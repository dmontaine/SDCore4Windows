/* probe-sessionsp-cyg.c - the Cygwin half of probe-sessionsp.c (see its
 * header).  The parent stands in for sd's LocalSystem front and its TLS relay:
 * it makes the Cygwin socketpair, hands one end to the spawned session, and
 * drives the OTHER end as the relay would.  These calls use msys-2.0's own
 * socket layer, the way sd does, and live in their own translation unit
 * because <sys/socket.h> and <windows.h> cannot share one. */
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#define BULK_BYTES (256L * 1024L)

/* sd's own channel today: sd_tlssrv.c's socketpair(AF_UNIX, SOCK_STREAM).
   sd keeps sd_end (on 0/1); the relay - here, the parent - keeps relay_end. */
int cyg_socketpair(int* session_end, int* relay_end) {
  int sp[2];
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0)
    return -errno;
  *session_end = sp[0];
  *relay_end = sp[1];
  return 0;
}

/* The Win32 HANDLE behind a Cygwin fd - what the parent puts on the child's
   standard handles.  Returned as long so the windows.h side needs no POSIX
   header to receive it. */
long cyg_osfhandle(int fd) { return (long)_get_osfhandle(fd); }

int cyg_close(int fd) { return close(fd); }

/* THE POSITIVE CONTROL.  sd's real handover today: fork(), the child dup2s the
   session end onto 0 and 1 and execl()s the session program.  Cygwin's fork
   carries the socketpair's fhandler across the clone and exec preserves the fd
   table, so this is the path that is KNOWN to work - if the same child passes
   here and fails under CreateProcess, the difference is spawn-vs-fork and not
   the child's code.  Returns the child pid to the parent, or -errno. */
int cyg_fork_exec(int session_end, int relay_end, const char* exe,
                  const char* report) {
  pid_t pid = fork();
  if (pid < 0)
    return -errno;
  if (pid == 0) {
    close(relay_end);
    if (dup2(session_end, 0) < 0 || dup2(session_end, 1) < 0)
      _exit(126);
    if (session_end > 1)
      close(session_end);
    execl(exe, exe, "--stdio", report, (char*)NULL);
    _exit(127);
  }
  return (int)pid;
}

/* waitpid the control child; returns its exit code, or -1 if it did not exit
   normally. */
int cyg_waitpid(int pid) {
  int status = 0;
  if (waitpid((pid_t)pid, &status, 0) != (pid_t)pid)
    return -1;
  return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

long cyg_write_line(int fd, const char* s) {
  return (long)write(fd, s, strlen(s));
}

/* read() with a deadline via poll. Returns bytes, 0 EOF, -errno, -ETIMEDOUT. */
long cyg_read_wait(int fd, char* buf, long n, int ms) {
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

/* Push BULK_BYTES patterned bytes into fd while draining the echo the session
   sends back on the SAME socketpair end - single-threaded, poll-driven, so the
   session's full-buffer path is exercised.  *pattern_ok says every byte came
   back in order.  Returns the byte count echoed back, or refuses out loud
   after 10 s of no progress. */
long cyg_bulk_echo(int fd, int* pattern_ok) {
  long sent = 0, got = 0;
  char out[8192], in[8192];
  int i;
  *pattern_ok = 1;
  for (i = 0; i < (int)sizeof out; i++)
    out[i] = (char)('A' + (i % 26));
  fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
  while (got < BULK_BYTES) {
    struct pollfd p;
    int r;
    p.fd = fd;
    p.events = POLLIN | (sent < BULK_BYTES ? POLLOUT : 0);
    p.revents = 0;
    r = poll(&p, 1, 10000);
    if (r <= 0) {
      printf("  bulk: poll %d errno %d after sent %ld got %ld - STALLED\n", r,
             errno, sent, got);
      break;
    }
    if ((p.revents & POLLOUT) && sent < BULK_BYTES) {
      long want = BULK_BYTES - sent, off = sent % (long)sizeof out;
      long chunk = (long)sizeof out - off, w;
      if (chunk > want)
        chunk = want;
      w = write(fd, out + off, (size_t)chunk);
      if (w < 0 && errno != EAGAIN) {
        printf("  bulk: write errno %d\n", errno);
        break;
      }
      if (w > 0)
        sent += w;
    }
    if (p.revents & (POLLIN | POLLHUP | POLLERR)) {
      long n = read(fd, in, sizeof in), k;
      if (n < 0) {
        if (errno == EAGAIN)
          continue;
        printf("  bulk: read errno %d after %ld bytes\n", errno, got);
        break;
      }
      if (n == 0) {
        printf("  bulk: EOF from the session after %ld bytes (it closed "
               "early)\n", got);
        break;
      }
      for (k = 0; k < n; k++)
        if (in[k] != (char)('A' + ((got + k) % (long)sizeof out % 26))) {
          *pattern_ok = 0;
          break;
        }
      got += n;
    }
  }
  fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
  return got;
}
