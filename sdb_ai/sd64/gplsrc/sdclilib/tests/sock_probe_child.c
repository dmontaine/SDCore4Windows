/* sockprobe_child.c - MSYS2/CYGWIN.  Stands in for "sd -n -q".
 *
 * fd 0 = whatever the parent handed over as standard input: either an accepted
 *        native Winsock SOCKET (the question) or an anonymous PIPE (the
 *        control, which step 11 proved honest).
 * fd 1 = report channel back to the parent.
 *
 * One shot, no phases, no sleeps: the parent decides before spawning this
 * whether fd 0 is empty or already carries data, so nothing here can race.
 * It reports what start_connection() (gplsrc/linuxio.c) actually does to
 * descriptor 0:
 *
 *   getsockname(0, ...)   - does Cygwin think fd 0 is a socket at all?
 *                           EXPECTED TO FAIL on the pipe row; that failure is
 *                           what makes the socket row's success mean something.
 *   send(0, "\x06", 1, 0) - the Ack that starts the API conversation
 *   select()              - where step 11 died: a descriptor made from a raw
 *                           HANDLE is reported PERMANENTLY READY, so sdpoll()
 *                           spins for ever.  On the "empty" column 0 is honest
 *                           and 1 is that same stopper.
 *   read() and recv()     - different paths through Cygwin.  read() goes via
 *                           the fhandler installed for whatever GetFileType()
 *                           said fd 0 was; recv() is the socket call.  If they
 *                           disagree, the disagreement IS the finding.
 *
 * Build and run:  make check-sock-probe
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

static int ready(int fd) {
    fd_set r;
    struct timeval tv;
    int n;
    FD_ZERO(&r);
    FD_SET(fd, &r);
    tv.tv_sec = 0;
    tv.tv_usec = 500000;
    n = select(fd + 1, &r, NULL, NULL, &tv);
    return (n > 0 && FD_ISSET(fd, &r)) ? 1 : 0;
}

static void trim(char *s) {
    char *nl = strpbrk(s, "\r\n");
    if (nl) *nl = '\0';
}

int main(void) {
    FILE *rep = fdopen(1, "w");
    struct sockaddr_storage sa;
    socklen_t slen = sizeof sa;
    char line[256];
    int rdy;
    ssize_t got;

    if (!rep) return 9;

    memset(&sa, 0, sizeof sa);
    if (getsockname(0, (struct sockaddr *)&sa, &slen) == 0) {
        const char *fam = (sa.ss_family == AF_INET) ? "AF_INET"
                        : (sa.ss_family == AF_UNIX) ? "AF_UNIX" : "other";
        int port = (sa.ss_family == AF_INET)
                     ? ntohs(((struct sockaddr_in *)&sa)->sin_port) : 0;
        fprintf(rep, "   getsockname  OK  family=%s port=%d\n", fam, port);
    } else {
        fprintf(rep, "   getsockname  FAIL errno=%d (%s)\n", errno, strerror(errno));
    }

    fprintf(rep, "   send(ACK)    %s\n",
            (send(0, "\x06", 1, 0) == 1) ? "OK" : "FAIL");

    rdy = ready(0);
    fprintf(rep, "   select       %d\n", rdy);

    if (rdy) {
        memset(line, 0, sizeof line);
        got = read(0, line, sizeof line - 1);
        if (got > 0) { trim(line); fprintf(rep, "   read         OK  [%s]\n", line); }
        else fprintf(rep, "   read         FAIL ret=%zd errno=%d (%s)\n",
                     got, errno, strerror(errno));

        if (ready(0)) {
            memset(line, 0, sizeof line);
            got = recv(0, line, sizeof line - 1, 0);
            if (got > 0) { trim(line); fprintf(rep, "   recv         OK  [%s]\n", line); }
            else fprintf(rep, "   recv         FAIL ret=%zd errno=%d (%s)\n",
                         got, errno, strerror(errno));
        } else {
            fprintf(rep, "   recv         nothing left - read() drained it\n");
        }
    } else {
        /* THE DISCRIMINATOR.  select() said nothing is waiting.  If a
           non-blocking recv() hands back the payload anyway, then the bytes
           were there all along and select() is simply blind to this kind of
           descriptor - which is fatal for SD, because sdpoll() is how it
           decides whether input has arrived.  If recv() also says "would
           block", the data genuinely had not arrived and the harness is at
           fault, not the descriptor. */
        memset(line, 0, sizeof line);
        got = recv(0, line, sizeof line - 1, MSG_DONTWAIT);
        if (got > 0) {
            trim(line);
            fprintf(rep, "   recv NONBLOCK OK [%s]  <- THE DATA WAS THERE; select() is blind\n",
                    line);
        } else {
            fprintf(rep, "   recv NONBLOCK ret=%zd errno=%d (%s)%s\n",
                    got, errno, strerror(errno),
                    (errno == EAGAIN || errno == EWOULDBLOCK)
                        ? "  <- genuinely empty, so select() was right" : "");
        }
    }
    fflush(rep);
    return 0;
}
