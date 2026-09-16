/* probe-cygsock: can sd hand a CYGWIN-accepted socket to a spawned relay that
 * uses it through native Winsock?  Same token, unelevated - the token boundary
 * is already measured (probe-relaydrop run 2); this isolates what differs in
 * the product: the socket was made by Cygwin, not by native Winsock.
 *
 * Parent: Cygwin loopback pair (cygside.c); _get_osfhandle(accepted) ->
 * DuplicateHandle inheritable -> CreateProcess child; closes ITS Cygwin fd of
 * the accepted end BEFORE sending PING (does Cygwin's close() end the
 * connection?); then waits for PONG on the Cygwin client fd.
 * Mode A: the parent clears Cygwin's event association and sets the socket
 * blocking BEFORE the handover; the child reads directly.
 * Mode B: the socket is left as Cygwin made it; the child waits in WSAPoll.
 * The parent sends 1500 ms after the spawn so the first wait is on an EMPTY
 * socket - with data already queued (the first version slept in the child) a
 * non-blocking socket passes and hides the fault.
 *
 * Build and run, unelevated, from gplbld through MSYS2's bash.  -lcygwin FIRST:
 * recv/send/socket/accept exist in both msys-2.0 and ws2_32, and with ws2_32
 * first the "Cygwin" half silently binds to Winsock (it refused itself as
 * COULD NOT RUN that way).  Check with objdump -p.
 *   gcc -O2 -Wall -o probe-cygsock.exe probe-cygsock.c probe-cygsock-cyg.c -lcygwin -lws2_32
 *   ./probe-cygsock.exe A ; ./probe-cygsock.exe B
 *
 * MEASURED 16 Sep 2026, msys-2.0 3.6.9, twice each:
 *   A - FAILS.  A Cygwin socket is non-blocking at the Winsock level (the
 *       child's WSARecv on an empty socket: 10035 WSAEWOULDBLOCK at 0 ms), and
 *       it cannot be made blocking: after WSAEventSelect(NULL) returns 0,
 *       ioctlsocket(FIONBIO 0) is 10045 WSAEOPNOTSUPP - in the parent and in
 *       the child alike.
 *   B - WORKS.  WSAPoll waited 1500 ms and returned POLLRDNORM, WSARecv got
 *       PING, WSASend PONG reached the Cygwin client.  The parent's Cygwin
 *       close() of its copy before PING did not end the connection.
 * So a relay handed sd's accepted socket must be written for a NON-BLOCKING
 * socket (poll, then read/write; OpenSSL sees WANT_READ/WANT_WRITE).
 */
#include <winsock2.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/cygwin.h>

int cyg_pair(int *accepted, int *client);
long cyg_osfhandle(int fd);
int cyg_close(int fd);
long cyg_send(int fd, const char *s);
long cyg_recv(int fd, char *buf, long n, int secs);

/* recv/send/setsockopt exist in BOTH msys-2.0 and ws2_32, and the link is
   ordered -lcygwin first so cygside.c gets Cygwin's.  The child therefore uses
   the names only Winsock has. */
static int wrecv(SOCKET s, char *b, int n)
{
    WSABUF wb = { (__LONG32)n, b };
    DWORD got = 0, fl = 0;
    if (WSARecv(s, &wb, 1, &got, &fl, NULL, NULL) != 0) return -1;
    return (int)got;
}
static int wsend(SOCKET s, const char *b, int n)
{
    WSABUF wb = { (__LONG32)n, (char *)b };
    DWORD sent = 0;
    if (WSASend(s, &wb, 1, &sent, 0, NULL, NULL) != 0) return -1;
    return (int)sent;
}

/* mode A: the parent made the socket blocking before handover; child just reads.
   mode B: the socket stays as Cygwin left it; child waits with WSAPoll first.
   Either way the parent sends 1500 ms after the spawn, so the first wait starts
   on an EMPTY socket - the only way a non-blocking socket shows itself. */
static int child(const char *mode, const char *harg)
{
    SOCKET s = (SOCKET)(uintptr_t)strtoull(harg, NULL, 10);
    WSADATA w;
    char b[64] = { 0 };
    int n, e;
    WSAStartup(MAKEWORD(2, 2), &w);
    DWORD t0 = GetTickCount();
    if (strcmp(mode, "B") == 0) {
        WSAPOLLFD p = { s, POLLRDNORM, 0 };
        int pr = WSAPoll(&p, 1, 8000);
        e = pr < 0 ? WSAGetLastError() : 0;
        printf("  child[B]: WSAPoll=%d revents=0x%x err=%d after %lu ms\n", pr,
               p.revents, e, (unsigned long)(GetTickCount() - t0));
        t0 = GetTickCount();
    }
    n = wrecv(s, b, sizeof b - 1);
    e = n < 0 ? WSAGetLastError() : 0; /* before any printf clobbers it */
    printf("  child[%s]: WSARecv=%d err=%d [%s] after %lu ms\n", mode, n, e,
           n > 0 ? b : "", (unsigned long)(GetTickCount() - t0));
    if (n <= 0 || strcmp(b, "PING") != 0) return 1;
    n = wsend(s, "PONG", 4);
    printf("  child[%s]: WSASend=%d err=%d\n", mode, n, n < 0 ? WSAGetLastError() : 0);
    closesocket(s);
    return n == 4 ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc == 4 && strcmp(argv[1], "child") == 0)
        return child(argv[2], argv[3]);
    if (argc != 2 || (strcmp(argv[1], "A") && strcmp(argv[1], "B"))) {
        printf("usage: A | B\n");
        return 2;
    }
    const char *mode = argv[1];
    printf("MODE %s\n", mode);

    int acc, cli;
    if (cyg_pair(&acc, &cli)) { printf("COULD NOT RUN: cygwin pair\n"); return 2; }
    HANDLE h = (HANDLE)cyg_osfhandle(acc), inh;
    printf("  parent: cygwin accepted fd %d -> handle %llu, client fd %d\n", acc,
           (unsigned long long)(uintptr_t)h, cli);
    if (strcmp(mode, "A") == 0) {
        WSADATA w;
        __ms_u_long zero = 0; /* LP64 Cygwin: winsock's u_long is 32-bit */
        WSAStartup(MAKEWORD(2, 2), &w);
        int es = WSAEventSelect((SOCKET)h, NULL, 0);
        int ese = es ? WSAGetLastError() : 0;
        int io = ioctlsocket((SOCKET)h, FIONBIO, &zero);
        int ioe = io ? WSAGetLastError() : 0;
        printf("  parent[A]: WSAEventSelect(clear)=%d err=%d; ioctlsocket(FIONBIO 0)=%d err=%d\n",
               es, ese, io, ioe);
    }
    if (h == INVALID_HANDLE_VALUE ||
        !DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), &inh, 0, TRUE,
                         DUPLICATE_SAME_ACCESS)) {
        printf("COULD NOT RUN: DuplicateHandle %lu\n", (unsigned long)GetLastError());
        return 2;
    }
    char self[MAX_PATH], cmd[1024];
    cygwin_conv_path(CCP_POSIX_TO_WIN_A, argv[0], self, sizeof self);
    snprintf(cmd, sizeof cmd, "\"%s\" child %s %llu", self, mode,
             (unsigned long long)(uintptr_t)inh);
    STARTUPINFOA si = { sizeof si };
    PROCESS_INFORMATION pi;
    if (!CreateProcessA(self, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
        printf("COULD NOT RUN: CreateProcess %lu\n", (unsigned long)GetLastError());
        return 2;
    }
    CloseHandle(inh);
    printf("  parent: cygwin close(accepted fd) = %d  (before PING)\n", cyg_close(acc));
    Sleep(1500);
    printf("  parent: cygwin send PING = %ld\n", cyg_send(cli, "PING"));
    char b[16] = { 0 };
    long r = cyg_recv(cli, b, 15, 8);
    printf("  parent: cygwin recv = %ld [%s]\n", r, r > 0 ? b : "");
    WaitForSingleObject(pi.hProcess, 15000);
    DWORD code = 99;
    GetExitCodeProcess(pi.hProcess, &code);
    printf("  parent: child exit %lu\n", (unsigned long)code);
    int ok = code == 0 && r == 4 && strcmp(b, "PONG") == 0;
    printf("VERDICT: %s\n", ok ? "CYGWIN-ACCEPTED SOCKET HANDED OVER AND WORKED" : "DID NOT WORK");
    return ok ? 0 : 1;
}
