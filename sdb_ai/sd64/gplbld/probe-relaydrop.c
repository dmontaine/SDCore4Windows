/* probe-relaydrop.c - can a LocalSystem daemon run a CYGWIN child as a
 * dedicated BARE account, the way the Linux relay runs as "nobody"?
 *
 * 16 Sep 26 Windows port, RELEASE_1.1 43's successor work.  Built and driven
 * by probe-relaydrop.ps1.  This is the FOUNDATIONAL step of the relay/session
 * split (option 3c is dead; the split replaces it): the TLS relay must stop
 * parsing unauthenticated bytes as LocalSystem and run as a bare, unprivileged
 * identity - Tier 2, the Linux setuid("nobody") shape.
 *
 * ===========================================================================
 * WHY THIS IS A SPAWN, NOT A fork()+setuid - AND IT FALLS OUT OF 43.
 *
 * probe-svcimp measured that Cygwin's seteuid to a DIFFERENT account needs
 * SeTcb.  So the relay cannot fork() from the LocalSystem session and
 * setuid("nobody") without SeTcb (which is 3a, "SYSTEM by another name").
 * The route that does NOT need SeTcb is to SPAWN the relay as a separate
 * process already under a bare token, via CreateProcessAsUser - which needs
 * only SeAssignPrimaryToken (LocalSystem holds it).  So the relay becomes a
 * spawned process, not a fork child.  This probe measures the first unknown on
 * that route.
 *
 * ===========================================================================
 * THE ONE QUESTION THIS STEP ANSWERS.  Not the socket handover yet - that is
 * the next probe.  Here: does a Cygwin/MSYS2 program even RUN under a foreign,
 * privilege-stripped, Low-integrity PRIMARY token created by CreateProcessAsUser
 * from a LocalSystem parent?  The runtime keeps shared state (its process
 * table, /tmp) that a stripped token may be unable to touch; if it cannot
 * initialise, Tier 2 needs rethinking before any product code.
 *
 * --parent   runs as LocalSystem (schtasks /RU SYSTEM).  S4U-mints a token for
 *            the dedicated account (the daemon will do the same: it holds SeTcb),
 *            duplicates it to a PRIMARY token, STRIPS it (every privilege
 *            removed, integrity lowered to Low), and CreateProcessAsUser()s the
 *            worker under it.  The mint is probe-svcimp's, proven.
 *
 * --child    the spawned relay stand-in.  Reports who it is, that it holds no
 *            privileges, its integrity level, and whether basic Cygwin I/O
 *            works (writes a file, reports the owner).  It does NOT need to be
 *            the bare account for the mint to have worked - it needs to be the
 *            bare account AND functional, which is the whole measurement.
 *
 * FALSIFIED-IF: the child does not start, or starts as SYSTEM rather than the
 * bare account, or cannot perform ordinary file I/O.  Then a spawned Cygwin
 * relay under a bare token is not viable as-is and the split's mechanism reopens.
 *
 * Exit: 0 the question was answered (read the verdict), 2 it could not be.
 */

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <ntsecapi.h>
#include <sddl.h>
#include <aclapi.h>
#include <userenv.h>
/* AFTER windows.h, so the runtime call is given the Win32 HANDLE type -
   probe-svcimp.c records the same ordering.  cygwin_attach_handle_to_fd is how
   a spawned (not fork()ed) Cygwin child adopts an inherited socket handle. */
#include <sys/cygwin.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <strings.h>
#include <wchar.h>
#include <fcntl.h>
#include <errno.h>
#include <pwd.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

static FILE* lg = NULL;

static void say(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  if (lg) {
    vfprintf(lg, fmt, ap);
    fputc('\n', lg);
    fflush(lg);
  }
  va_end(ap);
  va_start(ap, fmt);
  vprintf(fmt, ap);
  putchar('\n');
  fflush(stdout);
  va_end(ap);
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

static const char* token_account(HANDLE tok) {
  static char out[256];
  BYTE buf[512];
  DWORD len = 0;
  char name[128], dom[128];
  DWORD nl = sizeof name, dl = sizeof dom;
  SID_NAME_USE use;

  out[0] = '\0';
  if (!GetTokenInformation(tok, TokenUser, buf, sizeof buf, &len))
    return out;
  if (!LookupAccountSidA(NULL, ((TOKEN_USER*)buf)->User.Sid, name, &nl, dom,
                         &dl, &use))
    return out;
  snprintf(out, sizeof out, "%s\\%s", dom, name);
  return out;
}

static const char* my_account(void) {
  HANDLE t;
  const char* r = "";
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t)) {
    r = token_account(t);
    CloseHandle(t);
  }
  return r;
}

static int has_privilege(const char* priv) {
  HANDLE t;
  LUID want;
  BYTE buf[2048];
  DWORD len = 0;
  TOKEN_PRIVILEGES* tp;
  DWORD i;
  int found = 0;

  if (!LookupPrivilegeValueA(NULL, priv, &want))
    return 0;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t))
    return 0;
  if (GetTokenInformation(t, TokenPrivileges, buf, sizeof buf, &len)) {
    tp = (TOKEN_PRIVILEGES*)buf;
    for (i = 0; i < tp->PrivilegeCount; i++)
      if (tp->Privileges[i].Luid.LowPart == want.LowPart &&
          tp->Privileges[i].Luid.HighPart == want.HighPart)
        found = 1;
  }
  CloseHandle(t);
  return found;
}

/* Every privilege on the process token - so "no privileges" is measured, not
   assumed.  0 held is the point for the child. */
static int dump_privileges(void) {
  HANDLE t;
  BYTE buf[8192];
  DWORD len = 0;
  TOKEN_PRIVILEGES* tp;
  DWORD i;
  int count = -1;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t)) {
    say("  privileges        : <OpenProcessToken failed: %s>",
        winerr(GetLastError()));
    return -1;
  }
  if (GetTokenInformation(t, TokenPrivileges, buf, sizeof buf, &len)) {
    tp = (TOKEN_PRIVILEGES*)buf;
    count = (int)tp->PrivilegeCount;
    say("  privileges (%d held):", count);
    for (i = 0; i < tp->PrivilegeCount; i++) {
      char nm[64];
      DWORD nl = sizeof nm;
      if (LookupPrivilegeNameA(NULL, &tp->Privileges[i].Luid, nm, &nl))
        say("    %s", nm);
    }
  } else {
    say("  privileges        : <GetTokenInformation failed: %s>",
        winerr(GetLastError()));
  }
  CloseHandle(t);
  return count;
}

/* The token's integrity level as a printable string. */
static const char* integrity_level(void) {
  static char out[64];
  HANDLE t;
  BYTE buf[256];
  DWORD len = 0;
  DWORD rid = 0;

  snprintf(out, sizeof out, "unknown");
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t))
    return out;
  if (GetTokenInformation(t, TokenIntegrityLevel, buf, sizeof buf, &len)) {
    TOKEN_MANDATORY_LABEL* ml = (TOKEN_MANDATORY_LABEL*)buf;
    UCHAR cnt = *GetSidSubAuthorityCount(ml->Label.Sid);
    rid = *GetSidSubAuthority(ml->Label.Sid, cnt - 1);
    if (rid < SECURITY_MANDATORY_LOW_RID)
      snprintf(out, sizeof out, "Untrusted (0x%lx)", (unsigned long)rid);
    else if (rid < SECURITY_MANDATORY_MEDIUM_RID)
      snprintf(out, sizeof out, "Low (0x%lx)", (unsigned long)rid);
    else if (rid < SECURITY_MANDATORY_HIGH_RID)
      snprintf(out, sizeof out, "Medium (0x%lx)", (unsigned long)rid);
    else if (rid < SECURITY_MANDATORY_SYSTEM_RID)
      snprintf(out, sizeof out, "High (0x%lx)", (unsigned long)rid);
    else
      snprintf(out, sizeof out, "System (0x%lx)", (unsigned long)rid);
  }
  CloseHandle(t);
  return out;
}

static const char* create_and_owner(const char* path) {
  static char out[256];
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  char name[128], dom[128];
  DWORD nl = sizeof name, dl = sizeof dom;
  SID_NAME_USE use;
  int fd;

  out[0] = '\0';
  unlink(path);
  fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0600);
  if (fd < 0) {
    snprintf(out, sizeof out, "<could not create: %s>", strerror(errno));
    return out;
  }
  write(fd, "x", 1);
  close(fd);
  if (GetNamedSecurityInfoA(path, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
                            &owner, NULL, NULL, NULL, &sd) != ERROR_SUCCESS) {
    snprintf(out, sizeof out, "<owner unreadable>");
    return out;
  }
  if (LookupAccountSidA(NULL, owner, name, &nl, dom, &dl, &use))
    snprintf(out, sizeof out, "%s\\%s", dom, name);
  else
    snprintf(out, sizeof out, "<sid unresolved>");
  if (sd)
    LocalFree(sd);
  return out;
}

/* ======================================================================
   S4U mint - probe-svcimp's broker, unchanged in substance.  Returns an
   impersonation-level token for `account` on the local machine, or NULL.   */
static HANDLE s4u_mint(const char* account) {
  LSA_HANDLE hlsa = NULL;
  LSA_OPERATIONAL_MODE mode;
  LSA_STRING lsaname, origin, pkgname;
  NTSTATUS st, sub = 0;
  ULONG pkg = 0, s4ulen;
  MSV1_0_S4U_LOGON* s4u;
  BYTE* tail;
  TOKEN_SOURCE source;
  void* prof = NULL;
  ULONG proflen = 0;
  LUID luid;
  QUOTA_LIMITS quota;
  HANDLE tok = NULL;
  wchar_t wuser[256], wdom[256];

  lsaname.Buffer = (char*)"relaydrop";
  lsaname.Length = (USHORT)strlen(lsaname.Buffer);
  lsaname.MaximumLength = (USHORT)(lsaname.Length + 1);
  st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (st != 0) {
    say("REFUSED: LsaRegisterLogonProcess 0x%lx", (unsigned long)st);
    return NULL;
  }
  pkgname.Buffer = (char*)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(pkgname.Buffer);
  pkgname.MaximumLength = (USHORT)(pkgname.Length + 1);
  st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (st != 0) {
    say("REFUSED: LsaLookupAuthenticationPackage 0x%lx", (unsigned long)st);
    LsaDeregisterLogonProcess(hlsa);
    return NULL;
  }
  MultiByteToWideChar(CP_ACP, 0, account, -1, wuser, 256);
  MultiByteToWideChar(CP_ACP, 0, ".", -1, wdom, 256);
  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) +
                   (wcslen(wuser) + 1) * sizeof(wchar_t) +
                   (wcslen(wdom) + 1) * sizeof(wchar_t));
  s4u = (MSV1_0_S4U_LOGON*)calloc(1, s4ulen);
  if (!s4u) {
    say("REFUSED: out of memory");
    LsaDeregisterLogonProcess(hlsa);
    return NULL;
  }
  s4u->MessageType = MsV1_0S4ULogon;
  tail = (BYTE*)s4u + sizeof(MSV1_0_S4U_LOGON);
  wcscpy((wchar_t*)tail, wuser);
  s4u->UserPrincipalName.Buffer = (wchar_t*)tail;
  s4u->UserPrincipalName.Length = (USHORT)(wcslen(wuser) * sizeof(wchar_t));
  s4u->UserPrincipalName.MaximumLength =
      (USHORT)(s4u->UserPrincipalName.Length + sizeof(wchar_t));
  tail += s4u->UserPrincipalName.MaximumLength;
  wcscpy((wchar_t*)tail, wdom);
  s4u->DomainName.Buffer = (wchar_t*)tail;
  s4u->DomainName.Length = (USHORT)(wcslen(wdom) * sizeof(wchar_t));
  s4u->DomainName.MaximumLength =
      (USHORT)(s4u->DomainName.Length + sizeof(wchar_t));
  origin.Buffer = (char*)"relaydrop";
  origin.Length = (USHORT)strlen(origin.Buffer);
  origin.MaximumLength = (USHORT)(origin.Length + 1);
  memcpy(source.SourceName, "reldrop\0", 8);
  AllocateLocallyUniqueId(&source.SourceIdentifier);
  st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen, NULL, &source,
                    &prof, &proflen, &luid, &tok, &quota, &sub);
  free(s4u);
  if (prof)
    LsaFreeReturnBuffer(prof);
  LsaDeregisterLogonProcess(hlsa);
  if (st != 0 || tok == NULL) {
    say("REFUSED: LsaLogonUser 0x%lx sub 0x%lx", (unsigned long)st,
        (unsigned long)sub);
    return NULL;
  }
  return tok;
}

/* Remove EVERY privilege from a token, permanently (SE_PRIVILEGE_REMOVED, not
   disable - removal is what makes the drop a boundary rather than a
   suggestion).  THE LOW-INTEGRITY DROP IS DEFERRED to the next iteration: a
   Low-integrity child must also write into a Low-labelled directory, a second
   variable, and this first probe isolates the one foundational question -
   whether a Cygwin child runs as the bare ACCOUNT at all.  The child reports
   its integrity either way, so we see it is Medium now and Low later. */
static int strip_privileges(HANDLE tok) {
  BYTE buf[8192];
  DWORD len = 0;
  TOKEN_PRIVILEGES* tp;
  DWORD i;

  if (GetTokenInformation(tok, TokenPrivileges, buf, sizeof buf, &len)) {
    tp = (TOKEN_PRIVILEGES*)buf;
    for (i = 0; i < tp->PrivilegeCount; i++)
      tp->Privileges[i].Attributes = SE_PRIVILEGE_REMOVED;
    if (tp->PrivilegeCount > 0 &&
        !AdjustTokenPrivileges(tok, FALSE, tp, 0, NULL, NULL)) {
      say("REFUSED: AdjustTokenPrivileges(remove all) - %s",
          winerr(GetLastError()));
      return 0;
    }
  }
  return 1;
}

/* A connected TCP pair on loopback: the ACCEPTED end stands in for the API
   connection the daemon would hand the relay; the CLIENT end is what the parent
   uses to prove the child can read and write it.  Winsock, so the handle is a
   native SOCKET the child can inherit and adopt. */
static int make_loopback_pair(SOCKET* accepted, SOCKET* client) {
  SOCKET lis = INVALID_SOCKET, cli = INVALID_SOCKET, acc = INVALID_SOCKET;
  struct sockaddr_in addr;
  int addrlen = sizeof addr;

  lis = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (lis == INVALID_SOCKET) {
    say("REFUSED: socket(listener) %d", WSAGetLastError());
    return 0;
  }
  memset(&addr, 0, sizeof addr);
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  addr.sin_port = 0;
  if (bind(lis, (struct sockaddr*)&addr, sizeof addr) != 0 ||
      listen(lis, 1) != 0 ||
      getsockname(lis, (struct sockaddr*)&addr, &addrlen) != 0) {
    say("REFUSED: bind/listen/getsockname %d", WSAGetLastError());
    closesocket(lis);
    return 0;
  }
  cli = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (cli == INVALID_SOCKET) {
    say("REFUSED: socket(client) %d", WSAGetLastError());
    closesocket(lis);
    return 0;
  }
  if (connect(cli, (struct sockaddr*)&addr, sizeof addr) != 0) {
    say("REFUSED: connect %d", WSAGetLastError());
    closesocket(lis);
    closesocket(cli);
    return 0;
  }
  acc = accept(lis, NULL, NULL);
  closesocket(lis);
  if (acc == INVALID_SOCKET) {
    say("REFUSED: accept %d", WSAGetLastError());
    closesocket(cli);
    return 0;
  }
  *accepted = acc;
  *client = cli;
  return 1;
}

/* ======================================================================
   THE PARENT - LocalSystem.  Mints, strips, spawns, hands over a socket.  */
static int parent(const char* dir, const char* account) {
  char childexe[MAX_PATH], cmd[MAX_PATH * 2], childlog[MAX_PATH];
  HANDLE imp = NULL, prim = NULL;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  void* env = NULL;
  SOCKET acc = INVALID_SOCKET, cli = INVALID_SOCKET;
  WSADATA wsa;
  int ok = 0;

  say("probe-relaydrop PARENT");
  say("  running as        : %s", my_account());
  say("  SeTcbPrivilege    : %s", has_privilege("SeTcbPrivilege") ? "yes" : "NO");
  say("  SeAssignPrimary   : %s",
      has_privilege("SeAssignPrimaryTokenPrivilege") ? "yes" : "NO");
  say("  target account    : %s", account);

  if (!has_privilege("SeTcbPrivilege")) {
    say("REFUSED: the parent is not LocalSystem (no SeTcb), so S4U cannot mint.");
    return 2;
  }

  imp = s4u_mint(account);
  if (!imp)
    return 2;
  say("  minted (imp) for  : %s", token_account(imp));

  if (!DuplicateTokenEx(imp, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation,
                        TokenPrimary, &prim)) {
    say("REFUSED: DuplicateTokenEx to primary - %s", winerr(GetLastError()));
    CloseHandle(imp);
    return 2;
  }
  CloseHandle(imp);
  say("  primary token     : %s", token_account(prim));

  if (!strip_privileges(prim)) {
    CloseHandle(prim);
    return 2;
  }
  say("  stripped          : all privileges removed (Low integrity deferred)");

  /* --- the socket handover: the crux -----------------------------------
     Make a connected pair; hand the ACCEPTED end to the child (an inheritable
     handle across CreateProcessAsUser), keep the CLIENT end to prove the child
     can read and write it.  sdwind.c:400 measured naive socket-passing to a
     Cygwin child failing, so this is the make-or-break. */
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    say("REFUSED: WSAStartup %d", WSAGetLastError());
    CloseHandle(prim);
    return 2;
  }
  if (!make_loopback_pair(&acc, &cli)) {
    CloseHandle(prim);
    return 2;
  }
  if (!SetHandleInformation((HANDLE)acc, HANDLE_FLAG_INHERIT,
                            HANDLE_FLAG_INHERIT)) {
    say("REFUSED: SetHandleInformation(inherit) - %s", winerr(GetLastError()));
    closesocket(acc);
    closesocket(cli);
    CloseHandle(prim);
    return 2;
  }
  say("  socket handed     : accepted-end handle %llu (marked inheritable)",
      (unsigned long long)acc);

  snprintf(childexe, sizeof childexe, "%s\\probe-relaydrop.exe", dir);
  snprintf(childlog, sizeof childlog, "%s\\child.log", dir);
  snprintf(cmd, sizeof cmd, "\"%s\" --child \"%s\" %llu", childexe, dir,
           (unsigned long long)acc);
  say("  spawning          : %s", cmd);

  /* An explicit environment for the target account; without it Cygwin has no
     PATH to find its own DLL.  CreateEnvironmentBlock with the bare token. */
  if (!CreateEnvironmentBlock(&env, prim, FALSE)) {
    say("  note: CreateEnvironmentBlock failed (%s); passing NULL env",
        winerr(GetLastError()));
    env = NULL;
  }

  ZeroMemory(&si, sizeof si);
  si.cb = sizeof si;
  si.lpDesktop = (char*)"winsta0\\default";
  ZeroMemory(&pi, sizeof pi);

  /* bInheritHandles TRUE so the accepted socket reaches the child; only that
     handle was marked inheritable. */
  if (!CreateProcessAsUserA(prim, childexe, cmd, NULL, NULL, TRUE,
                            CREATE_NO_WINDOW |
                                (env ? CREATE_UNICODE_ENVIRONMENT : 0),
                            env, dir, &si, &pi)) {
    say("REFUSED: CreateProcessAsUser - %s", winerr(GetLastError()));
    if (env)
      DestroyEnvironmentBlock(env);
    closesocket(acc);
    closesocket(cli);
    CloseHandle(prim);
    return 2;
  }
  say("  CreateProcessAsUser: launched pid %lu", (unsigned long)pi.dwProcessId);

  /* Close the parent's copy of the accepted end so only the child holds it,
     then PING down the client end and wait for the child's PONG. */
  closesocket(acc);
  acc = INVALID_SOCKET;
  {
    const char* ping = "PING-from-parent";
    int sent = send(cli, ping, (int)strlen(ping), 0);
    say("  parent sent       : %d bytes on the client end", sent);
  }
  WaitForSingleObject(pi.hProcess, 30000);
  {
    DWORD code = 0;
    DWORD tmo = 3000;
    char rb[128];
    int rn;
    GetExitCodeProcess(pi.hProcess, &code);
    say("  child exit code   : %lu", (unsigned long)code);
    setsockopt(cli, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tmo, sizeof tmo);
    rn = recv(cli, rb, sizeof rb - 1, 0);
    if (rn > 0) {
      rb[rn] = '\0';
      say("  parent received   : [%s] (%d bytes) - the ROUND TRIP WORKED", rb,
          rn);
      ok = 1;
    } else {
      say("  parent received   : nothing (recv=%d, err %d) - the child could",
          rn, WSAGetLastError());
      say("                      not use the handed-over socket; see child.log.");
      ok = 0;
    }
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  if (env)
    DestroyEnvironmentBlock(env);
  closesocket(cli);
  CloseHandle(prim);
  (void)childlog;
  say("PARENT DONE - read child.log for what the bare child could do.");
  return ok ? 0 : 2;
}

/* ======================================================================
   THE CHILD - the bare relay stand-in.                                    */
static int child(const char* dir, const char* sockarg) {
  char made[MAX_PATH];
  int nprivs;

  say("probe-relaydrop CHILD");
  say("  running as        : %s", my_account());
  say("  runtime uid/euid  : %d / %d", (int)getuid(), (int)geteuid());
  say("  integrity level   : %s", integrity_level());
  say("  SeImpersonate     : %s",
      has_privilege("SeImpersonatePrivilege") ? "yes" : "no");
  say("  SeTcbPrivilege    : %s",
      has_privilege("SeTcbPrivilege") ? "yes" : "no");
  nprivs = dump_privileges();
  snprintf(made, sizeof made, "%s\\child-made.txt", dir);
  say("  file I/O owner    : %s", create_and_owner(made));
  say("  privilege count   : %d (0 is the goal)", nprivs);

  /* The crux: adopt the inherited socket handle as a Cygwin fd and prove it
     reads and writes.  This is what a spawned (not fork()ed) relay must do with
     the accepted connection - fork() sets the fd up for the child, a spawn does
     not. */
  if (sockarg) {
    SOCKET s = (SOCKET)(uintptr_t)strtoull(sockarg, NULL, 10);
    int fd;
    say("  socket handle     : %llu (inherited)", (unsigned long long)s);
    errno = 0;
    fd = cygwin_attach_handle_to_fd((char*)"relaysock", -1, (HANDLE)s, 1,
                                    GENERIC_READ | GENERIC_WRITE);
    if (fd < 0) {
      say("  socket adopt      : FAILED (cygwin_attach_handle_to_fd errno %d %s)",
          errno, strerror(errno));
    } else {
      char rb[128];
      ssize_t rn;
      say("  socket adopt      : ok, fd %d", fd);
      rn = read(fd, rb, sizeof rb - 1);
      if (rn > 0) {
        rb[(size_t)rn] = '\0';
        say("  socket read       : [%s] (%zd bytes)", rb, rn);
        {
          const char* pong = "PONG-from-child";
          ssize_t wn = write(fd, pong, strlen(pong));
          say("  socket write      : %zd bytes back", wn);
        }
      } else {
        say("  socket read       : nothing (read=%zd errno %d %s)", rn, errno,
            strerror(errno));
      }
      close(fd);
    }
  }

  say("CHILD DONE");
  return 0;
}

int main(int argc, char* argv[]) {
  char logpath[MAX_PATH];
  const char* role;
  const char* dir;
  int rc;

  if (argc < 3) {
    printf("usage: probe-relaydrop.exe --parent|--child <dir> [account]\n");
    return 2;
  }
  role = argv[1];
  dir = argv[2];

  snprintf(logpath, sizeof logpath, "%s\\%s.log", dir,
           (strcmp(role, "--parent") == 0) ? "parent" : "child");
  lg = fopen(logpath, "w");

  if (strcmp(role, "--parent") == 0) {
    if (argc < 4) {
      say("usage: --parent <dir> <account>");
      rc = 2;
    } else {
      rc = parent(dir, argv[3]);
    }
  } else if (strcmp(role, "--child") == 0) {
    rc = child(dir, (argc >= 4) ? argv[3] : NULL);
  } else {
    printf("unknown role '%s'\n", role);
    rc = 2;
  }

  if (lg)
    fclose(lg);
  return rc;
}
