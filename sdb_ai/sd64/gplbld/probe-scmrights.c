/* probe-scmrights.c - RELEASE_1.1 43, HANDOFF 76 next step 1, sub-question:
 * does THIS MSYS2 runtime pass a socket descriptor over AF_UNIX with
 * sendmsg/SCM_RIGHTS at all?  Same token, no privilege - if it fails here it
 * cannot cross a token boundary either.
 *
 * Parent: AF_UNIX listener at argv path, spawns itself as "child", accepts;
 * makes a connected TCP loopback pair (a,b); sends one data byte + fd a with
 * SCM_RIGHTS; closes a; writes PING on b; waits for PONG on b.
 * Child: connects, recvmsg with a cmsg buffer, prints everything it got, then
 * reads PING from the received fd and writes PONG.
 *
 * Exit 0 = descriptor passed AND worked as a socket; 1 = falsified; 2 = could
 * not run the measurement (channel itself broken).
 *
 * Build and run, unelevated, from gplbld through MSYS2's bash:
 *   gcc -O2 -Wall -o probe-scmrights.exe probe-scmrights.c && ./probe-scmrights.exe
 *
 * MEASURED 16 Sep 2026, msys-2.0 3.6.9: exit 1.  sendmsg returns 1 (success),
 * the data byte arrives, msg_controllen comes back 0 - the SCM_RIGHTS control
 * message is dropped SILENTLY while sendmsg reports success.  No
 * descriptor passing on this runtime, so it cannot cross a token either.
 */
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static void say(const char *who, const char *fmt, int a, int b)
{
    printf("[%s pid %d] ", who, (int)getpid());
    printf(fmt, a, b);
    printf("\n");
    fflush(stdout);
}

static int child(const char *path)
{
    alarm(15);
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un sa;
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    strncpy(sa.sun_path, path, sizeof sa.sun_path - 1);
    if (connect(s, (struct sockaddr *)&sa, sizeof sa) != 0) {
        say("child", "connect failed errno %d%.0d", errno, 0);
        return 2;
    }

    char data = 0;
    struct iovec iov = { &data, 1 };
    char cbuf[CMSG_SPACE(sizeof(int))];
    memset(cbuf, 0, sizeof cbuf);
    struct msghdr m;
    memset(&m, 0, sizeof m);
    m.msg_iov = &iov;
    m.msg_iovlen = 1;
    m.msg_control = cbuf;
    m.msg_controllen = sizeof cbuf;

    ssize_t r = recvmsg(s, &m, 0);
    int e = errno;
    say("child", "recvmsg returned %d errno %d", (int)r, r < 0 ? e : 0);
    if (r != 1 || data != 'X') {
        say("child", "CHANNEL BROKEN: data byte not received (got %d, want %d)", data, 'X');
        return 2;
    }
    say("child", "data byte OK; msg_controllen after = %d (sent space %d)",
        (int)m.msg_controllen, (int)sizeof cbuf);

    struct cmsghdr *c = m.msg_controllen ? CMSG_FIRSTHDR(&m) : NULL;
    if (c == NULL) {
        say("child", "NO CONTROL MESSAGE RECEIVED - descriptor not passed%.0d%.0d", 0, 0);
        return 1;
    }
    say("child", "cmsg level %d type %d", c->cmsg_level, c->cmsg_type);
    if (c->cmsg_level != SOL_SOCKET || c->cmsg_type != SCM_RIGHTS) {
        say("child", "control message is not SCM_RIGHTS%.0d%.0d", 0, 0);
        return 1;
    }
    int fd;
    memcpy(&fd, CMSG_DATA(c), sizeof fd);
    say("child", "received fd %d (unix socket was fd %d)", fd, s);

    char buf[8] = { 0 };
    ssize_t n = read(fd, buf, 4);
    e = errno;
    say("child", "read on received fd returned %d errno %d", (int)n, n < 0 ? e : 0);
    if (n != 4 || memcmp(buf, "PING", 4) != 0) {
        say("child", "received fd is NOT a working socket (no PING)%.0d%.0d", 0, 0);
        return 1;
    }
    say("child", "got PING through received fd%.0d%.0d", 0, 0);
    n = write(fd, "PONG", 4);
    say("child", "write PONG returned %d errno %d", (int)n, n < 0 ? errno : 0);
    return n == 4 ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc == 3 && strcmp(argv[1], "child") == 0)
        return child(argv[2]);

    alarm(20);
    char path[64];
    snprintf(path, sizeof path, "/tmp/scmprobe-%d.sock", (int)getpid());
    unlink(path);
    printf("[parent] argv0=%s socket path=%s\n", argv[0], path);

    int l = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un sa;
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    strncpy(sa.sun_path, path, sizeof sa.sun_path - 1);
    if (bind(l, (struct sockaddr *)&sa, sizeof sa) != 0 || listen(l, 1) != 0) {
        say("parent", "bind/listen failed errno %d%.0d", errno, 0);
        return 2;
    }

    pid_t pid;
    char *cargv[] = { argv[0], "child", path, NULL };
    int se = posix_spawn(&pid, argv[0], NULL, NULL, cargv, environ);
    if (se != 0) {
        say("parent", "posix_spawn failed %d%.0d", se, 0);
        return 2;
    }
    say("parent", "spawned child pid %d%.0d", (int)pid, 0);

    int u = accept(l, NULL, NULL);
    if (u < 0) { say("parent", "accept unix failed errno %d%.0d", errno, 0); return 2; }

    /* TCP loopback pair, created AFTER the spawn so the child cannot have
     * inherited it - anything the child reads, it got via SCM_RIGHTS. */
    int tl = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in si;
    memset(&si, 0, sizeof si);
    si.sin_family = AF_INET;
    si.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t sl = sizeof si;
    if (bind(tl, (struct sockaddr *)&si, sizeof si) != 0 || listen(tl, 1) != 0
        || getsockname(tl, (struct sockaddr *)&si, &sl) != 0) {
        say("parent", "tcp listener failed errno %d%.0d", errno, 0);
        return 2;
    }
    int b = socket(AF_INET, SOCK_STREAM, 0);
    if (connect(b, (struct sockaddr *)&si, sizeof si) != 0) {
        say("parent", "tcp connect failed errno %d%.0d", errno, 0);
        return 2;
    }
    int a = accept(tl, NULL, NULL);
    say("parent", "tcp pair: passed end a=%d, kept end b=%d", a, b);

    char data = 'X';
    struct iovec iov = { &data, 1 };
    char cbuf[CMSG_SPACE(sizeof(int))];
    memset(cbuf, 0, sizeof cbuf);
    struct msghdr m;
    memset(&m, 0, sizeof m);
    m.msg_iov = &iov;
    m.msg_iovlen = 1;
    m.msg_control = cbuf;
    m.msg_controllen = sizeof cbuf;
    struct cmsghdr *c = CMSG_FIRSTHDR(&m);
    c->cmsg_level = SOL_SOCKET;
    c->cmsg_type = SCM_RIGHTS;
    c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &a, sizeof a);

    ssize_t r = sendmsg(u, &m, 0);
    say("parent", "sendmsg(SCM_RIGHTS fd %d) returned %d", a, (int)r);
    if (r < 0) say("parent", "sendmsg errno %d (%d)", errno, 0);
    close(a);

    ssize_t n = write(b, "PING", 4);
    say("parent", "write PING on b returned %d errno %d", (int)n, n < 0 ? errno : 0);

    char buf[8] = { 0 };
    n = read(b, buf, 4);   /* child alarm/exit ends this if nothing comes */
    say("parent", "read on b returned %d errno %d", (int)n, n < 0 ? errno : 0);

    int st = 0;
    waitpid(pid, &st, 0);
    int cx = WIFEXITED(st) ? WEXITSTATUS(st) : 100 + (WIFSIGNALED(st) ? WTERMSIG(st) : 0);
    say("parent", "child exit %d; PONG seen %d", cx, n == 4 && memcmp(buf, "PONG", 4) == 0);
    unlink(path);

    if (cx == 0 && n == 4 && memcmp(buf, "PONG", 4) == 0) {
        printf("VERDICT: SCM_RIGHTS PASSED A WORKING SOCKET (same token)\n");
        return 0;
    }
    printf("VERDICT: %s\n", cx == 2 ? "COULD NOT RUN (channel)" : "SCM_RIGHTS DID NOT PASS A WORKING SOCKET");
    return cx == 2 ? 2 : 1;
}
