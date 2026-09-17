/* probe-relaycutover-drive.c - the driver for probe-relaycutover.c (see its
 * header).  Plays all three of the other parties - the network client, the
 * LocalSystem front, and the authenticated session - so the relay is the only
 * process under test.  RELEASE_1.1 55 parity build, the cutover's byte
 * integrity.
 *
 * It makes two native loopback socket pairs (NET: client<->relay, APPA:
 * front<->relay), spawns the relay with the relay ends and a pipe name, then:
 *   PHASE A : client->front and front->client one line each (SCRAM window)
 *   CUTOVER : the front CLOSES its end (the auth-done signal), THEN the client
 *             sends a post-auth byte while the relay is standing the pipe up -
 *             the byte that must not be lost across the switch
 *   PHASE B : connect to the pipe as the session; the first thing read must be
 *             that post-auth byte; then session<->client both ways and a 32 KiB
 *             burst; then close
 * Exit 0 when phase A, the un-lost post-auth byte, phase B both ways and the
 * burst all held and the relay exited 0; 1 on a failed leg; 2 on setup.
 *
 * Build NATIVE, from gplbld in an MSYS2 UCRT64 bash:
 *   gcc -O2 -Wall -o probe-relaycutover-drive.exe probe-relaycutover-drive.c -lws2_32
 *   ./probe-relaycutover-drive.exe   (probe-relaycutover.exe must be beside it)
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define BURST 32768

/* A connected loopback TCP pair.  parent_end is not inheritable; child_end is,
   for the relay. */
static int make_pair(SOCKET* parent_end, SOCKET* child_end) {
  SOCKET lis, c, a;
  struct sockaddr_in addr;
  int len = sizeof addr;
  lis = socket(AF_INET, SOCK_STREAM, 0);
  if (lis == INVALID_SOCKET)
    return 0;
  memset(&addr, 0, sizeof addr);
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  addr.sin_port = 0;
  if (bind(lis, (struct sockaddr*)&addr, sizeof addr) != 0 ||
      listen(lis, 1) != 0 ||
      getsockname(lis, (struct sockaddr*)&addr, &len) != 0)
    return 0;
  c = socket(AF_INET, SOCK_STREAM, 0);
  if (c == INVALID_SOCKET || connect(c, (struct sockaddr*)&addr, sizeof addr) != 0)
    return 0;
  a = accept(lis, NULL, NULL);
  closesocket(lis);
  if (a == INVALID_SOCKET)
    return 0;
  SetHandleInformation((HANDLE)c, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation((HANDLE)a, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  *parent_end = c;
  *child_end = a;
  return 1;
}

/* recv exactly n bytes (SO_RCVTIMEO guards against a hang). */
static int recv_all(SOCKET s, char* buf, int n) {
  int got = 0, r;
  while (got < n) {
    r = recv(s, buf + got, n - got, 0);
    if (r <= 0)
      return got;
    got += r;
  }
  return got;
}
static int pipe_read_all(HANDLE h, char* buf, int n) {
  int got = 0;
  DWORD r;
  while (got < n) {
    if (!ReadFile(h, buf + got, n - got, &r, NULL) || r == 0)
      return got;
    got += (int)r;
  }
  return got;
}

int main(void) {
  WSADATA wsa;
  char dir[MAX_PATH], relayexe[MAX_PATH + 32], cmd[MAX_PATH * 3], pipename[128];
  SOCKET client, relay_net, front, relay_appA;
  HANDLE session;
  HANDLE list[2];
  STARTUPINFOEXA six;
  PROCESS_INFORMATION pi;
  SIZE_T alen = 0;
  DWORD code = 1, tick, to = 5000;
  char buf[BURST];
  char* slash;
  int i, ok_a = 0, ok_afterauth = 0, ok_s2c = 0, ok_c2s = 0, ok_burst = 0,
         relay_ok = 0;

  if (GetModuleFileNameA(NULL, dir, sizeof dir) == 0)
    return 2;
  slash = strrchr(dir, '\\');
  if (slash)
    *slash = '\0';
  snprintf(relayexe, sizeof relayexe, "%s\\probe-relaycutover.exe", dir);
  printf("probe-relaycutover DRIVER (plays client + front + session)\n");
  printf("relay exe : %s\n", relayexe);
  if (GetFileAttributesA(relayexe) == INVALID_FILE_ATTRIBUTES) {
    printf("COULD NOT RUN: build probe-relaycutover.exe first\n");
    return 2;
  }
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
    return 2;

  if (!make_pair(&client, &relay_net) || !make_pair(&front, &relay_appA)) {
    printf("COULD NOT RUN: loopback pair setup %d\n", WSAGetLastError());
    return 2;
  }
  setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, (char*)&to, sizeof to);
  setsockopt(front, SOL_SOCKET, SO_RCVTIMEO, (char*)&to, sizeof to);

  tick = GetTickCount();
  snprintf(pipename, sizeof pipename, "\\\\.\\pipe\\sd-cutover-%lu-%lu",
           (unsigned long)GetCurrentProcessId(), (unsigned long)tick);

  ZeroMemory(&six, sizeof six);
  ZeroMemory(&pi, sizeof pi);
  six.StartupInfo.cb = sizeof six;
  list[0] = (HANDLE)relay_net;
  list[1] = (HANDLE)relay_appA;
  InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
  six.lpAttributeList =
      (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, alen);
  if (!six.lpAttributeList ||
      !InitializeProcThreadAttributeList(six.lpAttributeList, 1, 0, &alen) ||
      !UpdateProcThreadAttribute(six.lpAttributeList, 0,
                                 PROC_THREAD_ATTRIBUTE_HANDLE_LIST, list,
                                 sizeof list, NULL, NULL)) {
    printf("COULD NOT RUN: handle list %lu\n", (unsigned long)GetLastError());
    return 2;
  }
  snprintf(cmd, sizeof cmd, "\"%s\" --relay %llu %llu %s", relayexe,
           (unsigned long long)(uintptr_t)relay_net,
           (unsigned long long)(uintptr_t)relay_appA, pipename);
  if (!CreateProcessA(relayexe, cmd, NULL, NULL, TRUE,
                      CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT, NULL, dir,
                      &six.StartupInfo, &pi)) {
    printf("COULD NOT RUN: CreateProcess %lu\n", (unsigned long)GetLastError());
    return 2;
  }
  CloseHandle(pi.hThread);
  /* The relay owns the relay ends now. */
  closesocket(relay_net);
  closesocket(relay_appA);

  /* PHASE A: client -> front, then front -> client, through the relay. */
  send(client, "SCRAM-client\n", 13, 0);
  memset(buf, 0, sizeof buf);
  if (recv_all(front, buf, 13) == 13 && memcmp(buf, "SCRAM-client\n", 13) == 0) {
    send(front, "SCRAM-front\n", 12, 0);
    memset(buf, 0, sizeof buf);
    ok_a = (recv_all(client, buf, 12) == 12 &&
            memcmp(buf, "SCRAM-front\n", 12) == 0);
  }
  printf("phase A (SCRAM window, net<->appA) : %s\n", ok_a ? "OK" : "FAILED");

  /* CUTOVER: the front closes (auth done), THEN the client sends a post-auth
     byte while the relay is standing the pipe up - the loss test. */
  closesocket(front);
  send(client, "AFTERAUTH\n", 10, 0);

  /* PHASE B: connect to the pipe as the session.  Retry briefly - the relay
     creates the pipe only after it sees the front close. */
  session = INVALID_HANDLE_VALUE;
  for (i = 0; i < 100 && session == INVALID_HANDLE_VALUE; i++) {
    session = CreateFileA(pipename, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                          OPEN_EXISTING, 0, NULL);
    if (session == INVALID_HANDLE_VALUE)
      Sleep(50);
  }
  if (session == INVALID_HANDLE_VALUE) {
    printf("phase B connect : FAILED (relay never served the pipe)\n");
    goto finish;
  }

  /* The FIRST bytes the session reads must be the post-auth byte the client
     sent during the switch - proof nothing was lost across the cutover. */
  memset(buf, 0, sizeof buf);
  ok_afterauth = (pipe_read_all(session, buf, 10) == 10 &&
                  memcmp(buf, "AFTERAUTH\n", 10) == 0);
  printf("cutover no-loss (post-auth byte reached the session) : %s\n",
         ok_afterauth ? "OK" : "FAILED");

  /* session -> client. */
  {
    DWORD w = 0;
    WriteFile(session, "SESSION-out\n", 12, &w, NULL);
    memset(buf, 0, sizeof buf);
    ok_s2c = (recv_all(client, buf, 12) == 12 &&
              memcmp(buf, "SESSION-out\n", 12) == 0);
    printf("phase B session->client : %s\n", ok_s2c ? "OK" : "FAILED");
  }
  /* client -> session. */
  {
    send(client, "CLIENT-in\n", 10, 0);
    memset(buf, 0, sizeof buf);
    ok_c2s = (pipe_read_all(session, buf, 10) == 10 &&
              memcmp(buf, "CLIENT-in\n", 10) == 0);
    printf("phase B client->session : %s\n", ok_c2s ? "OK" : "FAILED");
  }
  /* A 32 KiB burst client->session, fits under the pipe buffer so a single
     writer/reader cannot deadlock. */
  {
    char* big = (char*)malloc(BURST);
    int got, k;
    for (k = 0; k < BURST; k++)
      big[k] = (char)('A' + (k % 26));
    send(client, big, BURST, 0);
    got = pipe_read_all(session, buf, BURST);
    ok_burst = (got == BURST);
    for (k = 0; ok_burst && k < BURST; k++)
      if (buf[k] != (char)('A' + (k % 26)))
        ok_burst = 0;
    printf("phase B burst 32 KiB client->session : %d of %d %s\n", got, BURST,
           ok_burst ? "OK" : "FAILED");
    free(big);
  }

  CloseHandle(session);

finish:
  closesocket(client);
  if (WaitForSingleObject(pi.hProcess, 8000) == WAIT_OBJECT_0 &&
      GetExitCodeProcess(pi.hProcess, &code)) {
    relay_ok = (code == 0);
    printf("relay exit : %lu %s\n", (unsigned long)code,
           relay_ok ? "OK" : "- did not end cleanly");
  } else {
    printf("relay exit : did NOT end within 8 s\n");
    TerminateProcess(pi.hProcess, 99);
  }
  CloseHandle(pi.hProcess);
  if (six.lpAttributeList) {
    DeleteProcThreadAttributeList(six.lpAttributeList);
    HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
  }
  WSACleanup();

  if (ok_a && ok_afterauth && ok_s2c && ok_c2s && ok_burst && relay_ok) {
    printf("\nVERDICT: PASS - the relay cut its app side over from the front's "
           "socketpair to the session's pipe at the post-SCRAM boundary with no "
           "byte lost (the post-auth byte sent during the switch arrived), and "
           "pumped both ways after.  The parity build's data-path handover "
           "holds; the front can leave the path, so only relay(Low) and "
           "session(user) remain - Linux parity.\n");
    return 0;
  }
  printf("\nVERDICT: FAIL (A=%d afterauth=%d s2c=%d c2s=%d burst=%d relay=%d)\n",
         ok_a, ok_afterauth, ok_s2c, ok_c2s, ok_burst, relay_ok);
  return 1;
}
/* END-CODE */
