/* probe-relaysp-cyg.c - the Cygwin half of probe-relaysp.c (see its header).
 * Everything here uses msys-2.0's own socket layer, the way sd does; its own
 * translation unit because <sys/socket.h> and <windows.h> cannot share one.
 * probe-cygsock-cyg.c supplies the loopback TCP pair; this adds the
 * socketpair and the poll-driven bulk exchange. */
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/* sd's own channel today: sd_tlssrv.c's socketpair(AF_UNIX, SOCK_STREAM). */
int cyg_socketpair(int* sd_end, int* relay_end) {
  int sp[2];
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0)
    return -errno;
  *sd_end = sp[0];
  *relay_end = sp[1];
  return 0;
}

long cyg_write(int fd, const char* s) { return (long)write(fd, s, strlen(s)); }

/* read() with a deadline, via poll - what sd's binding-preamble loop does. */
long cyg_read_wait(int fd, char* buf, long n, int ms) {
  struct pollfd p;
  long r;
  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;
  r = poll(&p, 1, ms);
  if (r <= 0)
    return r < 0 ? -errno : -ETIMEDOUT;
  errno = 0;
  r = (long)read(fd, buf, n);
  return r < 0 ? -errno : r;
}

/* Push `total` patterned bytes into wr_fd while draining rd_fd, single-
   threaded and poll-driven, so the relay in between must handle a full
   send buffer (its WSAEWOULDBLOCK path).  Returns the bytes received back;
   *pattern_ok says whether every byte came back in order.  Refuses out loud
   when nothing moved for 10 s. */
long cyg_bulk(int wr_fd, int rd_fd, long total, int* pattern_ok) {
  long sent = 0, got = 0;
  char out[8192], in[8192];
  int i;
  *pattern_ok = 1;
  for (i = 0; i < (int)sizeof out; i++)
    out[i] = (char)('A' + (i % 26));
  fcntl(wr_fd, F_SETFL, fcntl(wr_fd, F_GETFL) | O_NONBLOCK);
  while (got < total) {
    struct pollfd p[2];
    int r;
    p[0].fd = rd_fd;
    p[0].events = POLLIN;
    p[0].revents = 0;
    p[1].fd = wr_fd;
    p[1].events = sent < total ? POLLOUT : 0;
    p[1].revents = 0;
    r = poll(p, 2, 10000);
    if (r <= 0) {
      printf("  bulk: poll %d errno %d after sent %ld got %ld - STALLED\n", r,
             errno, sent, got);
      break;
    }
    if (p[1].revents & POLLOUT) {
      long want = total - sent, off = sent % (long)sizeof out;
      long chunk = (long)sizeof out - off;
      long w;
      if (chunk > want)
        chunk = want;
      w = write(wr_fd, out + off, (size_t)chunk);
      if (w < 0 && errno != EAGAIN) {
        printf("  bulk: write errno %d\n", errno);
        break;
      }
      if (w > 0)
        sent += w;
    }
    if (p[0].revents & (POLLIN | POLLHUP | POLLERR)) {
      long n = read(rd_fd, in, sizeof in);
      long k;
      if (n <= 0) {
        printf("  bulk: read %ld errno %d before %ld bytes arrived\n", n, errno,
               total);
        break;
      }
      for (k = 0; k < n; k++)
        if (in[k] != (char)('A' + ((got + k) % 8192 % 26))) {
          *pattern_ok = 0;
          break;
        }
      got += n;
    }
  }
  fcntl(wr_fd, F_SETFL, fcntl(wr_fd, F_GETFL) & ~O_NONBLOCK);
  return got;
}
