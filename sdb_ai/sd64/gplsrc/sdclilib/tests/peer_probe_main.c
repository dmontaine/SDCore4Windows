/* peer_probe_main.c - the Cygwin half.  Sockets and fork() only; no windows.h.
 *
 * 20 Aug 26 - the Windows half it links against is now gplsrc/win32peer.c,
 * the file sdwind.c calls, rather than a copy kept beside this one. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/wait.h>
#include <sys/cygwin.h>

#include "win32peer.h"

int main(void) {
  int lsn, conn;
  struct sockaddr_in sa, peer;
  socklen_t slen;
  unsigned short port;
  pid_t child;
  unsigned long pid_seen, winpid;
  char who[512];
  int failures = 0;

  lsn = socket(AF_INET, SOCK_STREAM, 0);
  if (lsn < 0) { perror("socket"); return 2; }
  memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET;
  sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  sa.sin_port = 0;
  if (bind(lsn, (struct sockaddr*)&sa, sizeof(sa)) < 0) { perror("bind"); return 2; }
  if (listen(lsn, 1) < 0) { perror("listen"); return 2; }
  slen = sizeof(sa);
  getsockname(lsn, (struct sockaddr*)&sa, &slen);
  port = ntohs(sa.sin_port);
  printf("listening on 127.0.0.1:%u\n", port);

  child = fork();
  if (child < 0) { perror("fork"); return 2; }
  if (child == 0) {
    int c = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in to;
    memset(&to, 0, sizeof(to));
    to.sin_family = AF_INET;
    to.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    to.sin_port = htons(port);
    if (connect(c, (struct sockaddr*)&to, sizeof(to)) < 0) { perror("child connect"); _exit(3); }
    sleep(3);
    close(c);
    _exit(0);
  }

  winpid = (unsigned long)cygwin_internal(CW_CYGWIN_PID_TO_WINPID, child);
  printf("forked client: cygwin pid %ld, windows pid %lu\n", (long)child, winpid);

  slen = sizeof(peer);
  conn = accept(lsn, (struct sockaddr*)&peer, &slen);
  if (conn < 0) { perror("accept"); return 2; }
  printf("accepted from %s:%u\n", inet_ntoa(peer.sin_addr), ntohs(peer.sin_port));

  pid_seen = win32_peer_pid(port, ntohs(peer.sin_port));
  printf("owning pid from GetExtendedTcpTable: %lu\n", pid_seen);

  if (pid_seen == 0) { printf("FAIL: connection not in the TCP table\n"); failures++; }
  else if (pid_seen == winpid) { printf("PASS: matches the client's WINDOWS pid\n"); }
  else if (pid_seen == (unsigned long)child) { printf("PASS: matches the client's cygwin pid\n"); }
  else { printf("FAIL: %lu is neither %lu nor %ld\n", pid_seen, winpid, (long)child); failures++; }

  if (pid_seen && win32_pid_user(pid_seen, who, sizeof(who)))
    printf("peer runs as: %s\n", who);
  else if (pid_seen)
    { printf("FAIL: could not resolve the owner of pid %lu\n", pid_seen); failures++; }

  { unsigned long bogus = win32_peer_pid(port, 1);
    printf("control: non-existent peer -> %lu %s\n", bogus, bogus == 0 ? "(PASS)" : "(FAIL)");
    if (bogus != 0) failures++; }

  close(conn); close(lsn); waitpid(child, NULL, 0);
  printf("\n%s\n", failures == 0 ? "peer_probe: PASS" : "peer_probe: FAIL");
  return failures ? 1 : 0;
}
