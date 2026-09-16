/* probe-cygsock-cyg.c - the Cygwin half of probe-cygsock.c (see its header for
 * the question, build line and results).  Everything here uses Cygwin's own
 * socket layer, the way sd does.  Kept in its own translation unit because
 * <sys/socket.h> and <winsock2.h> cannot share one. */
#include <errno.h>
#include <io.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/* Cygwin loopback pair: *accepted is what sd's accept() would return. */
int cyg_pair(int *accepted, int *client)
{
    struct sockaddr_in a;
    socklen_t al = sizeof a;
    int l = socket(AF_INET, SOCK_STREAM, 0);
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(l, (struct sockaddr *)&a, sizeof a) || listen(l, 1) ||
        getsockname(l, (struct sockaddr *)&a, &al))
        return -1;
    *client = socket(AF_INET, SOCK_STREAM, 0);
    if (connect(*client, (struct sockaddr *)&a, sizeof a))
        return -1;
    *accepted = accept(l, NULL, NULL);
    close(l);
    return *accepted < 0 ? -1 : 0;
}

long cyg_osfhandle(int fd) { return _get_osfhandle(fd); }
int cyg_close(int fd) { return close(fd); }
long cyg_send(int fd, const char *s) { return (long)send(fd, s, strlen(s), 0); }

/* Blocking read with a deadline, via Cygwin. */
long cyg_recv(int fd, char *buf, long n, int secs)
{
    struct timeval tv = { secs, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    errno = 0;
    long r = (long)recv(fd, buf, n, 0);
    if (r < 0) return -(long)errno;
    return r;
}
