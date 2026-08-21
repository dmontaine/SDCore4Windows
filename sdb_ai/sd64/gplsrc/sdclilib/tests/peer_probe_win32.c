/* win32peer.c - which process owns the other end of a loopback TCP connection?
 *
 * THE FOURTH windows.h FILE, and it is separate for the same reason the other
 * three are: this one cannot share a translation unit with Cygwin's socket
 * headers at all.  Measured - <windows.h> and <netinet/in.h> together give
 * "redefinition of struct in6_addr", w32api's in6addr.h against cygwin's
 * in6.h.  So the interface below is deliberately plain integers: no socket
 * types cross it, and the caller never sees a Windows header.
 */

/* winsock2.h BEFORE windows.h: iphlpapi needs AF_INET, and under this
   toolchain windows.h alone does not define it. */
#include <winsock2.h>
#include <windows.h>
#include <iphlpapi.h>

#include "peer_probe_win32.h"

/* The peer's socket is the mirror of ours: its local port is our remote port
   and vice versa.  Returns 0 if no such connection is in the table. */
unsigned long win32_peer_pid(unsigned short our_port, unsigned short peer_port) {
  PMIB_TCPTABLE_OWNER_PID tbl;
  DWORD size = 0;
  DWORD rc;
  DWORD found = 0;
  DWORD i;

  rc = GetExtendedTcpTable(NULL, &size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0);
  if (rc != ERROR_INSUFFICIENT_BUFFER && rc != NO_ERROR)
    return 0;

  tbl = (PMIB_TCPTABLE_OWNER_PID)HeapAlloc(GetProcessHeap(), 0, size);
  if (tbl == NULL)
    return 0;

  rc = GetExtendedTcpTable(tbl, &size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0);
  if (rc != NO_ERROR) {
    HeapFree(GetProcessHeap(), 0, tbl);
    return 0;
  }

  for (i = 0; i < tbl->dwNumEntries; i++) {
    MIB_TCPROW_OWNER_PID* r = &tbl->table[i];
    unsigned short lp = (unsigned short)(((r->dwLocalPort & 0xFF) << 8) |
                                         ((r->dwLocalPort >> 8) & 0xFF));
    unsigned short rp = (unsigned short)(((r->dwRemotePort & 0xFF) << 8) |
                                         ((r->dwRemotePort >> 8) & 0xFF));
    if (lp == peer_port && rp == our_port) {
      found = r->dwOwningPid;
      break;
    }
  }

  HeapFree(GetProcessHeap(), 0, tbl);
  return (unsigned long)found;
}

/* The Windows account that owns a process, as DOMAIN\name.  This is the half
   that makes the pid worth having: a pid alone says nothing about trust. */
int win32_pid_user(unsigned long pid, char* out, int outlen) {
  HANDLE hp;
  HANDLE tok = NULL;
  char buf[4096];
  DWORD need = 0;
  TOKEN_USER* tu;
  char name[256], dom[256];
  DWORD nlen = sizeof(name), dlen = sizeof(dom);
  SID_NAME_USE use;
  int ok = 0;

  if (outlen > 0) out[0] = '\0';

  hp = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (hp == NULL)
    return 0;

  if (OpenProcessToken(hp, TOKEN_QUERY, &tok)) {
    tu = (TOKEN_USER*)buf;
    if (GetTokenInformation(tok, TokenUser, tu, sizeof(buf), &need)) {
      if (LookupAccountSidA(NULL, tu->User.Sid, name, &nlen, dom, &dlen, &use)) {
        if ((int)(strlen(name) + strlen(dom) + 2) <= outlen) {
          lstrcpyA(out, dom);
          lstrcatA(out, "\\");
          lstrcatA(out, name);
          ok = 1;
        }
      }
    }
    CloseHandle(tok);
  }

  CloseHandle(hp);
  return ok;
}
