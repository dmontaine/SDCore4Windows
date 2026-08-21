/* WIN32PEER.C
 * Native Windows peer identification, for sdwind.c.
 * Copyright (c) String Database
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * START-HISTORY:
 * 20 Aug 26 Windows port - written.  Proved first as a standalone probe under
 *           gplsrc/sdclilib/tests, then moved here when sdwind gained the
 *           call; "make check-peer-probe" now compiles THIS file rather than
 *           a copy of it, so the test and the shipped code cannot drift.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * win32peer.h has why this is a file of its own, why it is not a named pipe,
 * and the two limits any policy built on it has to allow for.  Read it first.
 *
 * ONE THING HERE IS EASY TO GET WRONG: the peer's row in the TCP table is the
 * MIRROR of ours.  Its local port is our remote port and its remote port is
 * our local one, so the test below is deliberately crossed over.  Matching
 * either port alone would find the listener's own row, or every connection to
 * the same server, and would then report the wrong owner with no symptom.
 *
 * MIB_TCPROW_OWNER_PID PORTS ARE NETWORK BYTE ORDER IN A DWORD - the low two
 * bytes hold the port, big-endian - so they are swapped here rather than
 * passed to ntohs(), which would need winsock's declaration and drag the
 * socket headers back in.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* winsock2.h BEFORE windows.h, and this is not stylistic: iphlpapi.h needs
   AF_INET, and under this toolchain windows.h alone does not define it.    */
#include <winsock2.h>
#include <windows.h>
#include <iphlpapi.h>
#include <string.h>

#include "win32peer.h"

/* ======================================================================
   win32_peer_pid()  -  Owning process of the far end of a connection     */

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

/* ======================================================================
   win32_pid_user()  -  The Windows account a process runs as             */

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

  if (outlen > 0)
    out[0] = '\0';

  /* PROCESS_QUERY_LIMITED_INFORMATION, not PROCESS_QUERY_INFORMATION: the
     limited right is enough for the token and is grantable across accounts,
     which matters because the daemon runs as LocalSystem and every peer it
     looks at belongs to somebody else.                                    */
  hp = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (hp == NULL)
    return 0;

  if (OpenProcessToken(hp, TOKEN_QUERY, &tok)) {
    tu = (TOKEN_USER*)buf;
    if (GetTokenInformation(tok, TokenUser, tu, sizeof(buf), &need)) {
      if (LookupAccountSidA(NULL, tu->User.Sid, name, &nlen, dom, &dlen, &use)) {
        /* +2 is the separator and the terminator. */
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

/* END-CODE */
