/* probe-relaychild.c - the relay stand-in for probe-relaydrop iteration 5, as a
 * NATIVE (UCRT64) program with no MSYS2 runtime in it.
 *
 * 16 Sep 26 Windows port, RELEASE_1.1 43.  WHY NATIVE, MEASURED: an MSYS2
 * process at Low integrity dies at startup (exit 0xC0000142, "fatal error -
 * NtCreateDirectoryObject(\BaseNamedObjects\msys-2.0S5-<key>): 0xC0000022")
 * whenever a Medium-or-higher process of the same runtime is alive, and sd is
 * always one (probe-lowmsys.c; owner-elevated trials in probe-relaydrop
 * iteration 4, where a native exe at Low ran).  Low is mandatory
 * (RELEASE_1.1 53), so the relay is native.
 *
 * Launched by probe-relaydrop.exe --parent (LocalSystem) under a bare account's
 * S4U token with every privilege removed and integrity Low:
 *   probe-relaychild.exe --hello                     exit 7: it initialised
 *   probe-relaychild.exe --child <lowdir> <socket> <up> <down>
 * <socket> is an inherited duplicate of a CYGWIN-accepted SOCKET, which is
 * non-blocking and cannot be made blocking (probe-cygsock.c), so the child
 * waits with WSAPoll before WSARecv.  <up>/<down> are inherited duplicates of
 * the parent's Cygwin pipe() ends.  Every report line goes to <up>, which the
 * parent saves as child.log; the child writes no log file of its own.
 *
 * Build NATIVE, from gplbld in an MSYS2 UCRT64 bash:
 *   gcc -O2 -Wall -o probe-relaychild.exe probe-relaychild.c -lws2_32 -ladvapi32
 * then check objdump -p shows no msys-2.0.dll and no non-system DLL.
 */
#include <winsock2.h>
#include <windows.h>
#include <sddl.h>
#include <aclapi.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static HANDLE report = NULL;

static void say(const char* fmt, ...) {
  va_list ap;
  char line[1024];
  int n;
  DWORD w;
  va_start(ap, fmt);
  n = vsnprintf(line, sizeof line - 1, fmt, ap);
  va_end(ap);
  if (n < 0 || !report)
    return;
  if (n > (int)sizeof line - 2)
    n = (int)sizeof line - 2;
  line[n++] = '\n';
  WriteFile(report, line, (DWORD)n, &w, NULL);
}

static const char* winerr(DWORD e) {
  static char b[256];
  char* m = NULL;
  FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                     FORMAT_MESSAGE_IGNORE_INSERTS,
                 NULL, e, 0, (LPSTR)&m, 0, NULL);
  snprintf(b, sizeof b, "%lu %s", (unsigned long)e, m ? m : "(no text)");
  if (m)
    LocalFree(m);
  for (char* p = b; *p; p++)
    if (*p == '\r' || *p == '\n')
      *p = ' ';
  return b;
}

static const char* my_account(void) {
  static char out[256];
  HANDLE t;
  BYTE buf[512];
  DWORD len = 0;
  char name[128], dom[128];
  DWORD nl = sizeof name, dl = sizeof dom;
  SID_NAME_USE use;

  out[0] = '\0';
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t))
    return out;
  if (GetTokenInformation(t, TokenUser, buf, sizeof buf, &len) &&
      LookupAccountSidA(NULL, ((TOKEN_USER*)buf)->User.Sid, name, &nl, dom, &dl,
                        &use))
    snprintf(out, sizeof out, "%s\\%s", dom, name);
  CloseHandle(t);
  return out;
}

static int privilege_count(void) {
  HANDLE t;
  BYTE buf[8192];
  DWORD len = 0, i;
  int count = -1;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t))
    return -1;
  if (GetTokenInformation(t, TokenPrivileges, buf, sizeof buf, &len)) {
    TOKEN_PRIVILEGES* tp = (TOKEN_PRIVILEGES*)buf;
    count = (int)tp->PrivilegeCount;
    say("  privileges (%d held):", count);
    for (i = 0; i < tp->PrivilegeCount; i++) {
      char nm[64];
      DWORD nl = sizeof nm;
      if (LookupPrivilegeNameA(NULL, &tp->Privileges[i].Luid, nm, &nl))
        say("    %s", nm);
    }
  }
  CloseHandle(t);
  return count;
}

static const char* integrity_level(void) {
  static char out[64];
  HANDLE t;
  BYTE buf[256];
  DWORD len = 0, rid;
  snprintf(out, sizeof out, "unknown");
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t))
    return out;
  if (GetTokenInformation(t, TokenIntegrityLevel, buf, sizeof buf, &len)) {
    PSID s = ((TOKEN_MANDATORY_LABEL*)buf)->Label.Sid;
    rid = *GetSidSubAuthority(s, *GetSidSubAuthorityCount(s) - 1);
    snprintf(out, sizeof out, "%s (0x%lx)",
             rid < SECURITY_MANDATORY_LOW_RID      ? "Untrusted"
             : rid < SECURITY_MANDATORY_MEDIUM_RID ? "Low"
             : rid < SECURITY_MANDATORY_HIGH_RID   ? "Medium"
             : rid < SECURITY_MANDATORY_SYSTEM_RID ? "High"
                                                   : "System",
             (unsigned long)rid);
  }
  CloseHandle(t);
  return out;
}

/* Informational: the relay writes no files, but the answer is worth having. */
static const char* native_create(const char* path) {
  static char out[300];
  DWORD w;
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  char name[128], dom[128];
  DWORD nl = sizeof name, dl = sizeof dom;
  SID_NAME_USE use;
  HANDLE h = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    snprintf(out, sizeof out, "<could not create: %s>", winerr(GetLastError()));
    return out;
  }
  WriteFile(h, "x", 1, &w, NULL);
  CloseHandle(h);
  if (GetNamedSecurityInfoA(path, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
                            &owner, NULL, NULL, NULL, &sd) == ERROR_SUCCESS &&
      LookupAccountSidA(NULL, owner, name, &nl, dom, &dl, &use))
    snprintf(out, sizeof out, "created, owner %s\\%s", dom, name);
  else
    snprintf(out, sizeof out, "created, owner unreadable");
  if (sd)
    LocalFree(sd);
  return out;
}

static int relay(const char* dir, const char* sockarg, const char* uparg,
                 const char* downarg) {
  SOCKET s = (SOCKET)(uintptr_t)strtoull(sockarg, NULL, 10);
  HANDLE pw = (HANDLE)(uintptr_t)strtoull(uparg, NULL, 10);
  HANDLE pr = (HANDLE)(uintptr_t)strtoull(downarg, NULL, 10);
  char path[MAX_PATH], rb[128] = {0}, got[64] = {0};
  WSADATA wsa;
  int rn = -1;
  DWORD gn = 0;

  report = pw;
  say("probe-relaychild CHILD (iteration 5, native)");
  say("  running as        : %s", my_account());
  say("  integrity level   : %s", integrity_level());
  say("  privilege count   : %d (0 is the goal)", privilege_count());
  snprintf(path, sizeof path, "%s\\child-native.txt", dir);
  say("  file I/O native   : %s", native_create(path));
  say("  handles           : socket %llu, relay->sd %llu, sd->relay %llu",
      (unsigned long long)s, (unsigned long long)(uintptr_t)pw,
      (unsigned long long)(uintptr_t)pr);

  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    say("  socket read       : WSAStartup failed %d", WSAGetLastError());
  } else {
    WSAPOLLFD p;
    int pollr, e;
    DWORD t0 = GetTickCount();
    p.fd = s;
    p.events = POLLRDNORM;
    p.revents = 0;
    pollr = WSAPoll(&p, 1, 10000);
    e = pollr < 0 ? WSAGetLastError() : 0;
    say("  socket wait       : WSAPoll=%d revents=0x%x err=%d after %lu ms", pollr,
        p.revents, e, (unsigned long)(GetTickCount() - t0));
    if (pollr == 1) {
      WSABUF wb;
      DWORD n = 0, fl = 0;
      wb.len = sizeof rb - 1;
      wb.buf = rb;
      if (WSARecv(s, &wb, 1, &n, &fl, NULL, NULL) == 0) {
        rn = (int)n;
        rb[rn] = '\0';
        say("  socket read       : [%s] (%d bytes, WSARecv)", rb, rn);
      } else {
        say("  socket read       : nothing (WSARecv err %d)", WSAGetLastError());
      }
    } else {
      say("  socket read       : nothing (the wait did not report data)");
    }
  }

  if (ReadFile(pr, got, sizeof got - 1, &gn, NULL))
    say("  pipe read         : [%s] (%lu bytes, native ReadFile)", got,
        (unsigned long)gn);
  else
    say("  pipe read         : FAILED - %s", winerr(GetLastError()));

  if (rn > 0) {
    WSABUF wb;
    DWORD sent = 0;
    const char* pong = "PONG-from-child";
    say("RELAYED:%s|GOT:%s", rb, got);
    wb.len = (ULONG)strlen(pong);
    wb.buf = (char*)pong;
    if (WSASend(s, &wb, 1, &sent, 0, NULL, NULL) == 0)
      say("  socket write      : %lu bytes back (WSASend)", (unsigned long)sent);
    else
      say("  socket write      : FAILED (WSASend err %d)", WSAGetLastError());
  }
  closesocket(s);
  CloseHandle(pr);
  say("CHILD DONE");
  CloseHandle(pw);
  return 0;
}

int main(int argc, char* argv[]) {
  if (argc == 2 && strcmp(argv[1], "--hello") == 0)
    return 7;
  if (argc == 6 && strcmp(argv[1], "--child") == 0)
    return relay(argv[2], argv[3], argv[4], argv[5]);
  printf("usage: probe-relaychild.exe --hello | --child <lowdir> <socket> <up> <down>\n");
  return 2;
}
