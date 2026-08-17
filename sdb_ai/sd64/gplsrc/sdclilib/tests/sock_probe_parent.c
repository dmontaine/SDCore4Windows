/* sockprobe_parent.c - NATIVE (UCRT64).  Stands in for a native listener.
 *
 * QUESTION: if a native parent accepts a Winsock connection and hands the
 * accepted SOCKET to an MSYS2/Cygwin child as its STANDARD INPUT, does the
 * child get a working socket descriptor 0?
 *
 * That is what PROJECT_STATUS 7 step 6a/6b option B needs, and it is exactly
 * what start_connection() (gplsrc/linuxio.c) assumes: it calls getsockname(0),
 * send(0,...) and getpeereid(0,...) on descriptor 0.
 *
 * A 2x2, AND BOTH AXES ARE THERE FOR A REASON:
 *
 *              empty            data
 *   pipe    expect select=0   expect select=1     <- CONTROL: step 11 proved
 *                                                    an inherited pipe honest,
 *                                                    so this row validates the
 *                                                    harness itself
 *   sock    expect select=0   expect select=1     <- THE QUESTION
 *
 * The control is the SAME DESCRIPTOR (fd 0) in a separate run, so the only
 * difference between the rows is what kind of object it is.
 *
 * TWO EARLIER HARNESSES WERE WRONG AND THE CONTROL CAUGHT BOTH:
 *   1. Sending only after spawning the child - it measured channels nobody had
 *      written to yet.  Fixed by pre-loading in "data" mode, before the child
 *      exists, so nothing depends on scheduling.
 *   2. Using hStdError as the control channel.  hStdError is an OUTPUT handle,
 *      so Cygwin builds fd 2 write-only and a read-select on it can never
 *      fire - the control reported 0 with data sitting in the pipe.
 *
 * WHAT IT SETTLED, 17 Aug 2026: option B is dead.  The socket row reads
 * getsockname OK / send OK / select 0 / recv EAGAIN with THIRTEEN BYTES
 * PROVED PENDING before the child was spawned.  A Windows socket's receive
 * path stays bound to the process that created it; handle inheritance is not
 * how sockets are passed between processes, and the documented alternative -
 * WSADuplicateSocket - needs the result injected into Cygwin's descriptor
 * table by cygwin_attach_handle_to_fd(), which is the always-ready path
 * section 7 step 11 already measured and rejected.
 *
 * So the listener lives in sdwind, on the Cygwin side, where fork() hands the
 * socket over and none of this applies.
 *
 * Build and run:  make check-sock-probe
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void die(const char *what) {
    fprintf(stderr, "parent: %s failed, err=%lu\n", what, (unsigned long)GetLastError());
    exit(2);
}

int main(int argc, char **argv) {
    WSADATA wsa;
    SOCKET lsn = INVALID_SOCKET, cli = INVALID_SOCKET, srv = INVALID_SOCKET;
    struct sockaddr_in addr;
    int alen, want_data, use_sock;
    HANDLE inRd = NULL, inWr = NULL, repRd, repWr, childIn;
    SECURITY_ATTRIBUTES sa;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    char cmd[1024], buf[512];
    DWORD n;

    if (argc < 4) {
        fprintf(stderr, "usage: %s <cygwin-child.exe> sock|pipe empty|data\n", argv[0]);
        return 2;
    }
    use_sock  = (strcmp(argv[2], "sock") == 0);
    want_data = (strcmp(argv[3], "data") == 0);

    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) die("WSAStartup");

    sa.nLength = sizeof sa;
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle = TRUE;

    if (use_sock) {
        /* A real connected TCP pair on loopback - what an ssh -L forward
           delivers to a listener. */
        lsn = socket(AF_INET, SOCK_STREAM, 0);
        if (lsn == INVALID_SOCKET) die("socket(listen)");
        memset(&addr, 0, sizeof addr);
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = 0;
        if (bind(lsn, (struct sockaddr *)&addr, sizeof addr) != 0) die("bind");
        if (listen(lsn, 1) != 0) die("listen");
        alen = sizeof addr;
        if (getsockname(lsn, (struct sockaddr *)&addr, &alen) != 0) die("getsockname");

        cli = socket(AF_INET, SOCK_STREAM, 0);
        if (cli == INVALID_SOCKET) die("socket(client)");
        if (connect(cli, (struct sockaddr *)&addr, sizeof addr) != 0) die("connect");
        srv = accept(lsn, NULL, NULL);
        if (srv == INVALID_SOCKET) die("accept");
        closesocket(lsn);
        if (!SetHandleInformation((HANDLE)srv, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT))
            die("SetHandleInformation(srv)");
        childIn = (HANDLE)srv;
    } else {
        if (!CreatePipe(&inRd, &inWr, &sa, 0)) die("CreatePipe(in)");
        SetHandleInformation(inWr, HANDLE_FLAG_INHERIT, 0);
        childIn = inRd;
    }

    if (!CreatePipe(&repRd, &repWr, &sa, 0)) die("CreatePipe(rep)");
    SetHandleInformation(repRd, HANDLE_FLAG_INHERIT, 0);

    /* THE WHOLE POINT: the bytes are in the buffer BEFORE the child exists. */
    if (want_data) {
        if (use_sock) {
            if (send(cli, "PAYLOAD-DATA\n", 13, 0) != 13) die("send");
        } else {
            if (!WriteFile(inWr, "PAYLOAD-DATA\n", 13, &n, NULL)) die("WriteFile(in)");
        }
        Sleep(250);                       /* let loopback deliver */
    }
    printf("== stdin=%s  %s ==\n", use_sock ? "SOCKET" : "pipe  ",
           want_data ? "data " : "empty");
    /* PROOF THE BYTES ARRIVED BEFORE THE CHILD EXISTED.  Without this, "the
       child saw nothing" is equally consistent with "nothing was ever sent",
       and the whole measurement would be worthless. */
    if (use_sock) {
        u_long avail = 0;
        if (ioctlsocket(srv, FIONREAD, &avail) == 0)
            printf("   parent: %lu bytes pending on the server socket pre-spawn\n",
                   (unsigned long)avail);
    }
    fflush(stdout);

    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput  = childIn;                    /* UNDER TEST -> child fd 0 */
    si.hStdOutput = repWr;                      /* report     -> child fd 1 */
    si.hStdError  = GetStdHandle(STD_ERROR_HANDLE);

    snprintf(cmd, sizeof cmd, "\"%s\"", argv[1]);
    if (!CreateProcessA(NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi))
        die("CreateProcess");
    CloseHandle(childIn);
    CloseHandle(repWr);

    for (;;) {
        memset(buf, 0, sizeof buf);
        if (!ReadFile(repRd, buf, sizeof buf - 1, &n, NULL) || n == 0) break;
        fputs(buf, stdout);
        fflush(stdout);
    }

    WaitForSingleObject(pi.hProcess, 15000);
    return 0;
}
