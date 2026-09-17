/* probe-relaydrop.c - can a LocalSystem daemon run a CYGWIN child as a
 * dedicated BARE account, the way the Linux relay runs as "nobody"?
 *
 * 16 Sep 26 Windows port, RELEASE_1.1 43's successor work.  Built and driven
 * by probe-relaydrop.ps1.  The TLS relay must stop parsing unauthenticated
 * bytes as LocalSystem and run as a bare, unprivileged identity - the Linux
 * setuid("nobody") shape.
 *
 * WHY A SPAWN, NOT fork()+setuid: probe-svcimp measured that Cygwin's seteuid
 * to a different account needs SeTcb (option 3a).  CreateProcessAsUser needs
 * only SeAssignPrimaryToken, which LocalSystem holds.
 *
 * ===========================================================================
 * WHAT THE EARLIER ITERATIONS MEASURED (details in HISTORY.md, 16 Sep 2026)
 *   1. A Cygwin child runs as the bare account under an S4U-minted, privilege-
 *      stripped primary token.                                        WORKS
 *   2. Inherited SOCKET adopted with cygwin_attach_handle_to_fd: read EINVAL.
 *   -  SCM_RIGHTS (probe-scmrights.c): not implemented by msys-2.0.
 *   3. Owner: "whichever is closest to the Linux model" - one relay per
 *      connection, private channel to sd.  The child used the inherited SOCKET
 *      through NATIVE Winsock and exchanged bytes both ways with the Cygwin
 *      parent over two Cygwin pipe()s handed over as inheritable
 *      DuplicateHandle()s.  Owner-elevated run 2: ANSWERED (FULL).
 *   -  probe-cygsock.c: a CYGWIN-accepted socket hands over too, but it is
 *      NON-BLOCKING at the Winsock level and cannot be made blocking; WSAPoll
 *      then WSARecv works.
 *   -  probe-cygshared.c / probe-lowmsys.c: what the relay can write is set by
 *      its token - at Low integrity no MSYS2 shared section opens for write -
 *      and an MSYS2 program runs at Low.  Owner delegated the runtime choice;
 *      the relay stays MSYS2 with the Low drop MANDATORY.
 *
 * ===========================================================================
 * ITERATION 4 - EVERYTHING AT ONCE, THE WAY THE PRODUCT WOULD DO IT.
 *   token   bare account, every privilege removed, integrity LOW.
 *   socket  accepted by CYGWIN in the parent (probe-cygsock-cyg.c), SOCKET
 *           recovered with _get_osfhandle, inherited as a DuplicateHandle; the
 *           parent closes its Cygwin fd right after the spawn.
 *   wait    the parent sends PING 1500 ms AFTER the spawn, so the child's
 *           first wait is on an EMPTY non-blocking socket - WSAPoll, WSARecv.
 *   channel two Cygwin pipe()s as in iteration 3.
 *   report  the child reports through the relay->sd pipe, not a file: at Low
 *           an MSYS2 fopen into LocalLow failed EACCES, so a file log could
 *           leave a working relay with nothing to say.  The parent writes what
 *           it received to child.log.  The child's file I/O is still TRIED, in
 *           a Low-labelled subdirectory, Cygwin open() and native CreateFile
 *           both, and reported - informational, the relay writes no files.
 *
 * FALSIFIED-IF: the child is not the bare account at Low with 0 privileges, or
 * its WSAPoll/WSARecv does not return PING, or the parent's Cygwin read of the
 * pipe lacks RELAYED:PING-from-parent or GOT:PLAINTEXT-to-relay, or the parent
 * does not get PONG.
 *
 * Build, from gplbld in MSYS2's MSYS bash.  -lcygwin FIRST: recv/send/socket/
 * accept exist in both msys-2.0 and ws2_32, and probe-cygsock-cyg.c must get
 * Cygwin's (check with objdump -p).  So THIS file calls only names Winsock
 * alone has (WSAStartup, WSAPoll, WSARecv, WSASend, closesocket).
 *   gcc -O2 -Wall -o probe-relaydrop.exe probe-relaydrop.c probe-cygsock-cyg.c -lcygwin -lsecur32 -ladvapi32 -lws2_32 -luserenv
 *
 * Exit: 0 answered (read the verdict), 2 it could not be.
 */

#include <winsock2.h>
#include <windows.h>
#include <ntsecapi.h>
#include <sddl.h>
#include <aclapi.h>
#include <userenv.h>
/* AFTER windows.h, so the runtime calls are given the Win32 HANDLE type. */
#include <sys/cygwin.h>
#include <io.h> /* _get_osfhandle: a Cygwin pipe end's Windows handle */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

/* probe-cygsock-cyg.c - Cygwin's own socket layer, the way sd holds a socket */
int cyg_pair(int* accepted, int* client);
long cyg_osfhandle(int fd);
int cyg_close(int fd);
long cyg_send(int fd, const char* s);
long cyg_recv(int fd, char* buf, long n, int secs);

static FILE* lg = NULL;         /* parent: parent.log */
static HANDLE report = NULL;    /* child: the relay->sd pipe */

static void say(const char* fmt, ...) {
  va_list ap;
  char line[1024];
  int n;
  va_start(ap, fmt);
  n = vsnprintf(line, sizeof line - 1, fmt, ap);
  va_end(ap);
  if (n < 0)
    return;
  if (n > (int)sizeof line - 2)
    n = (int)sizeof line - 2;
  line[n++] = '\n';
  line[n] = '\0';
  if (report) {
    DWORD w;
    WriteFile(report, line, (DWORD)n, &w, NULL);
    return;
  }
  if (lg) {
    fputs(line, lg);
    fflush(lg);
  }
  fputs(line, stdout);
  fflush(stdout);
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

static const char* owner_of(const char* path) {
  static char out[256];
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  char name[128], dom[128];
  DWORD nl = sizeof name, dl = sizeof dom;
  SID_NAME_USE use;

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

/* File I/O through the Cygwin runtime. */
static const char* cygwin_create(const char* path) {
  static char out[300];
  int fd;
  unlink(path);
  fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0600);
  if (fd < 0) {
    snprintf(out, sizeof out, "<could not create: errno %d %s>", errno,
             strerror(errno));
    return out;
  }
  write(fd, "x", 1);
  close(fd);
  snprintf(out, sizeof out, "created, owner %s", owner_of(path));
  return out;
}

/* The same through Win32, to tell a runtime refusal from a token refusal. */
static const char* native_create(const char* path) {
  static char out[300];
  DWORD w;
  HANDLE h = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    snprintf(out, sizeof out, "<could not create: %s>", winerr(GetLastError()));
    return out;
  }
  WriteFile(h, "x", 1, &w, NULL);
  CloseHandle(h);
  snprintf(out, sizeof out, "created, owner %s", owner_of(path));
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
   suggestion). */
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

/* Lower the token to Low integrity (S-1-16-4096).  RELEASE_1.1 53 measured
   why this is mandatory: at Medium an ordinary account can open the LocalSystem
   runtime's shared.5 for write; at Low it cannot. */
static int set_low_integrity(HANDLE tok) {
  PSID low = NULL;
  TOKEN_MANDATORY_LABEL tml;
  int ok;

  if (!ConvertStringSidToSidA("S-1-16-4096", &low)) {
    say("REFUSED: ConvertStringSidToSid(Low) - %s", winerr(GetLastError()));
    return 0;
  }
  tml.Label.Attributes = SE_GROUP_INTEGRITY;
  tml.Label.Sid = low;
  ok = SetTokenInformation(tok, TokenIntegrityLevel, &tml,
                           sizeof tml + GetLengthSid(low));
  if (!ok)
    say("REFUSED: SetTokenInformation(Low) - %s", winerr(GetLastError()));
  LocalFree(low);
  return ok;
}

static int dup_inheritable(HANDLE h, HANDLE* out) {
  return DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), out, 0,
                         TRUE, DUPLICATE_SAME_ACCESS);
}

/* ======================================================================
   THE PARENT - LocalSystem, standing in for sd.                           */
static int parent(const char* dir, const char* account) {
  char childexe[MAX_PATH], cmd[MAX_PATH * 3], lowdir[MAX_PATH],
       childlog[MAX_PATH];
  HANDLE imp = NULL, prim = NULL;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  void* env = NULL;
  int acc = -1, cli = -1;
  HANDLE sockInh = NULL;
  int up[2] = {-1, -1}, down[2] = {-1, -1};
  HANDLE upW = NULL, downR = NULL;
  int pong = 0, piped = 0;

  say("probe-relaydrop PARENT (iteration 4)");
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

  if (!strip_privileges(prim) || !set_low_integrity(prim)) {
    CloseHandle(prim);
    return 2;
  }
  say("  stripped          : all privileges removed, integrity set to Low");

  /* The connection, held the way sd holds it: a CYGWIN-accepted fd. */
  if (cyg_pair(&acc, &cli) != 0) {
    say("REFUSED: Cygwin loopback pair (socket/bind/listen/connect/accept)");
    CloseHandle(prim);
    return 2;
  }
  if ((HANDLE)cyg_osfhandle(acc) == INVALID_HANDLE_VALUE ||
      !dup_inheritable((HANDLE)cyg_osfhandle(acc), &sockInh)) {
    say("REFUSED: _get_osfhandle/DuplicateHandle(socket) - %s",
        winerr(GetLastError()));
    CloseHandle(prim);
    return 2;
  }
  say("  socket            : Cygwin accepted fd %d -> SOCKET %ld -> inheritable %llu",
      acc, cyg_osfhandle(acc), (unsigned long long)(uintptr_t)sockInh);

  /* The private relay<->sd channel, one Cygwin pipe() each way. */
  if (pipe(up) != 0 || pipe(down) != 0 ||
      !dup_inheritable((HANDLE)_get_osfhandle(up[1]), &upW) ||
      !dup_inheritable((HANDLE)_get_osfhandle(down[0]), &downR)) {
    say("REFUSED: pipe()/DuplicateHandle - errno %d, %s", errno,
        winerr(GetLastError()));
    CloseHandle(prim);
    return 2;
  }
  say("  pipes handed      : relay->sd write %llu, sd->relay read %llu",
      (unsigned long long)(uintptr_t)upW, (unsigned long long)(uintptr_t)downR);

  snprintf(childexe, sizeof childexe, "%s\\probe-relaydrop.exe", dir);
  snprintf(lowdir, sizeof lowdir, "%s\\low", dir);
  snprintf(childlog, sizeof childlog, "%s\\child.log", dir);
  snprintf(cmd, sizeof cmd, "\"%s\" --child \"%s\" %llu %llu %llu", childexe,
           lowdir, (unsigned long long)(uintptr_t)sockInh,
           (unsigned long long)(uintptr_t)upW,
           (unsigned long long)(uintptr_t)downR);
  say("  spawning          : %s", cmd);

  /* An explicit environment for the target account; without it Cygwin has no
     PATH to find its own DLL. */
  if (!CreateEnvironmentBlock(&env, prim, FALSE)) {
    say("  note: CreateEnvironmentBlock failed (%s); passing NULL env",
        winerr(GetLastError()));
    env = NULL;
  }

  ZeroMemory(&si, sizeof si);
  si.cb = sizeof si;
  si.lpDesktop = (char*)"winsta0\\default";
  ZeroMemory(&pi, sizeof pi);

  if (!CreateProcessAsUserA(prim, childexe, cmd, NULL, NULL, TRUE,
                            CREATE_NO_WINDOW |
                                (env ? CREATE_UNICODE_ENVIRONMENT : 0),
                            env, lowdir, &si, &pi)) {
    say("REFUSED: CreateProcessAsUser - %s", winerr(GetLastError()));
    if (env)
      DestroyEnvironmentBlock(env);
    CloseHandle(prim);
    return 2;
  }
  say("  CreateProcessAsUser: launched pid %lu", (unsigned long)pi.dwProcessId);

  /* Everything the child now holds is closed here, including sd's own Cygwin
     fd of the connection - the child is its only holder from this point. */
  CloseHandle(sockInh);
  CloseHandle(upW);
  CloseHandle(downR);
  close(up[1]);
  close(down[0]);
  say("  parent closed     : its Cygwin fd of the connection (close=%d)",
      cyg_close(acc));
  {
    const char* plain = "PLAINTEXT-to-relay";
    ssize_t wn = write(down[1], plain, strlen(plain));
    say("  parent pipe write : %zd bytes sd->relay (errno %d)", wn,
        wn < 0 ? errno : 0);
    close(down[1]);
  }

  /* The child must be WAITING on an empty socket when this arrives. */
  Sleep(1500);
  say("  parent sent       : %ld bytes PING on the client end (after 1500 ms)",
      cyg_send(cli, "PING-from-parent"));
  {
    char rb[64] = {0};
    long rn = cyg_recv(cli, rb, sizeof rb - 1, 10);
    if (rn > 0 && strcmp(rb, "PONG-from-child") == 0) {
      say("  parent received   : [%s] (%ld bytes) - the ROUND TRIP WORKED", rb,
          rn);
      pong = 1;
    } else {
      say("  parent received   : nothing usable (recv=%ld [%s])", rn,
          rn > 0 ? rb : "");
    }
  }

  WaitForSingleObject(pi.hProcess, 30000);
  {
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    say("  child exit code   : %lu", (unsigned long)code);
  }

  /* The child's report and its RELAYED line, read as sd would: a Cygwin fd.
     Saved verbatim as child.log for the driver. */
  {
    static char pb[16384];
    ssize_t pn, tot = 0;
    FILE* cl;
    while (tot < (ssize_t)sizeof pb - 1 &&
           (pn = read(up[0], pb + tot, sizeof pb - 1 - (size_t)tot)) > 0)
      tot += pn;
    pb[tot > 0 ? tot : 0] = '\0';
    close(up[0]);
    say("  pipe read (cygwin): %zd bytes from the child", tot);
    cl = fopen(childlog, "w");
    if (cl) {
      fputs(pb, cl);
      fclose(cl);
    } else {
      say("  note: could not write %s (errno %d)", childlog, errno);
    }
    if (strstr(pb, "RELAYED:PING-from-parent") &&
        strstr(pb, "GOT:PLAINTEXT-to-relay")) {
      say("  THE PIPE CARRIED both directions between a Cygwin sd and the child");
      piped = 1;
    }
  }
  say("  socket leg        : %s", pong ? "WORKED" : "did NOT");
  say("  pipe leg          : %s", piped ? "WORKED" : "did NOT");
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  if (env)
    DestroyEnvironmentBlock(env);
  CloseHandle(prim);
  say("PARENT DONE - child.log holds what the child reported over the pipe.");
  return (pong && piped) ? 0 : 2;
}

/* ======================================================================
   THE CHILD - the bare, Low, 0-privilege relay stand-in.                  */
static int child(const char* dir, const char* sockarg, const char* uparg,
                 const char* downarg) {
  SOCKET s = (SOCKET)(uintptr_t)strtoull(sockarg, NULL, 10);
  HANDLE pw = (HANDLE)(uintptr_t)strtoull(uparg, NULL, 10);
  HANDLE pr = (HANDLE)(uintptr_t)strtoull(downarg, NULL, 10);
  char path[MAX_PATH], rb[128] = {0}, got[64] = {0};
  WSADATA wsa;
  int nprivs, rn = -1, e;
  DWORD gn = 0, t0;

  report = pw; /* every say() from here goes to the parent */

  say("probe-relaydrop CHILD (iteration 4)");
  say("  running as        : %s", my_account());
  say("  runtime uid/euid  : %d / %d", (int)getuid(), (int)geteuid());
  say("  integrity level   : %s", integrity_level());
  say("  SeImpersonate     : %s",
      has_privilege("SeImpersonatePrivilege") ? "yes" : "no");
  say("  SeTcbPrivilege    : %s",
      has_privilege("SeTcbPrivilege") ? "yes" : "no");
  nprivs = dump_privileges();
  say("  privilege count   : %d (0 is the goal)", nprivs);
  snprintf(path, sizeof path, "%s\\child-cygwin.txt", dir);
  say("  file I/O cygwin   : %s", cygwin_create(path));
  snprintf(path, sizeof path, "%s\\child-native.txt", dir);
  say("  file I/O native   : %s", native_create(path));
  say("  handles           : socket %llu, relay->sd %llu, sd->relay %llu",
      (unsigned long long)s, (unsigned long long)(uintptr_t)pw,
      (unsigned long long)(uintptr_t)pr);

  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    say("  socket read       : WSAStartup failed %d", WSAGetLastError());
  } else {
    WSAPOLLFD p;
    int pollr;
    p.fd = s;
    p.events = POLLRDNORM;
    p.revents = 0;
    t0 = GetTickCount();
    pollr = WSAPoll(&p, 1, 10000);
    e = pollr < 0 ? WSAGetLastError() : 0;
    say("  socket wait       : WSAPoll=%d revents=0x%x err=%d after %lu ms", pollr,
        p.revents, e, (unsigned long)(GetTickCount() - t0));
    if (pollr == 1) {
      WSABUF wb;
      DWORD got_n = 0, fl = 0;
      wb.len = sizeof rb - 1;
      wb.buf = rb;
      if (WSARecv(s, &wb, 1, &got_n, &fl, NULL, NULL) == 0) {
        rn = (int)got_n;
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
    say("RELAYED:%s|GOT:%s", rb, got);
    {
      WSABUF wb;
      DWORD sent = 0;
      const char* pong = "PONG-from-child";
      wb.len = (ULONG)strlen(pong);
      wb.buf = (char*)pong;
      if (WSASend(s, &wb, 1, &sent, 0, NULL, NULL) == 0)
        say("  socket write      : %lu bytes back (WSASend)", (unsigned long)sent);
      else
        say("  socket write      : FAILED (WSASend err %d)", WSAGetLastError());
    }
  }
  closesocket(s);
  CloseHandle(pr);
  say("CHILD DONE");
  CloseHandle(pw);
  return 0;
}

int main(int argc, char* argv[]) {
  char logpath[MAX_PATH];
  int rc;

  /* Occupy descriptors 0-2 if the launcher left them closed, so no pipe or
     socket fd lands on stdout (iteration 2's artifact). */
  {
    int i;
    for (i = 0; i <= 2; i++)
      if (fcntl(i, F_GETFD) == -1)
        open("/dev/null", O_RDWR);
  }

  if (argc == 4 && strcmp(argv[1], "--parent") == 0) {
    snprintf(logpath, sizeof logpath, "%s\\parent.log", argv[2]);
    lg = fopen(logpath, "w");
    rc = parent(argv[2], argv[3]);
    if (lg)
      fclose(lg);
    return rc;
  }
  if (argc == 6 && strcmp(argv[1], "--child") == 0)
    return child(argv[2], argv[3], argv[4], argv[5]);

  printf("usage: probe-relaydrop.exe --parent <dir> <account>\n"
         "       probe-relaydrop.exe --child <lowdir> <socket> <up> <down>\n");
  return 2;
}
