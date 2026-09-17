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
 * RUN 1 (owner-elevated, 16 Sep 2026): the child died before its first line,
 * exit 0xC0000142 (DLL init failed).  Iteration 3 - identical at Medium - ran,
 * so Low broke initialisation in THIS launch context (session 0, fresh account,
 * winsta0\default, CREATE_NO_WINDOW); unelevated, the same user at Low in its own
 * session ran fine.  So the parent now runs TRIALS first - a native exe at Low,
 * the MSYS2 exe at Low three ways (desktop, inherited desktop, console), and a
 * Medium control - and does the handover with the first Low launch that ran.
 * RUN 2: native at Low RAN; MSYS2 at Low died 0xC0000142 all three ways; MSYS2
 * at Medium RAN.  Cause, reproduced unelevated (probe-lowmsys.c): a Low MSYS2
 * process cannot open the runtime's object directory that a Medium-or-higher
 * process of the same runtime - here this parent, in the product sd - created.
 *
 * ===========================================================================
 * ITERATION 5 - THE RELAY CHILD IS NATIVE (probe-relaychild.c, UCRT64).
 * This file is now the PARENT only: an MSYS2 process standing in for sd, with
 * everything from iteration 4 unchanged (Low token, Cygwin-accepted socket,
 * PING 1500 ms late, two Cygwin pipes, the child's report over the pipe).  The
 * trials are replaced by one PREFLIGHT: probe-relaychild.exe --hello at Low must
 * exit 7 before the handover is attempted.  The file-I/O lines above now come
 * from the native child, native CreateFile only.
 *
 * FALSIFIED-IF: the child is not the bare account at Low with 0 privileges, or
 * its WSAPoll/WSARecv does not return PING, or the parent's Cygwin read of the
 * pipe lacks RELAYED:PING-from-parent or GOT:PLAINTEXT-to-relay, or the parent
 * does not get PONG.
 *
 * Build, from gplbld in MSYS2's MSYS bash.  -lcygwin FIRST: recv/send/socket/
 * accept exist in both msys-2.0 and ws2_32, and probe-cygsock-cyg.c must get
 * Cygwin's (check with objdump -p).
 *   gcc -O2 -Wall -o probe-relaydrop.exe probe-relaydrop.c probe-cygsock-cyg.c -lcygwin -lsecur32 -ladvapi32 -lws2_32 -luserenv
 * and the child, NATIVE, in an MSYS2 UCRT64 bash (see probe-relaychild.c):
 *   gcc -O2 -Wall -o probe-relaychild.exe probe-relaychild.c -lws2_32 -ladvapi32
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

/* One trial launch: start exe under tok with the given desktop and creation
   flags, inherit nothing, wait up to 15 s, return the exit code (or a marker
   for "could not create" / "still running").  0xC0000142 is DLL init failed. */
#define TRIAL_NOCREATE 0xFFFFFFF0UL
#define TRIAL_TIMEOUT  0xFFFFFFF1UL
static DWORD trial(const char* label, HANDLE tok, const char* exe,
                   const char* args, const char* desktop, DWORD flags,
                   const char* cwd) {
  char cmd[MAX_PATH * 2];
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  void* env = NULL;
  DWORD code = TRIAL_NOCREATE;

  snprintf(cmd, sizeof cmd, "\"%s\"%s%s", exe, args ? " " : "", args ? args : "");
  CreateEnvironmentBlock(&env, tok, FALSE);
  ZeroMemory(&si, sizeof si);
  si.cb = sizeof si;
  si.lpDesktop = (char*)desktop;
  ZeroMemory(&pi, sizeof pi);
  if (!CreateProcessAsUserA(tok, exe, cmd, NULL, NULL, FALSE,
                            flags | (env ? CREATE_UNICODE_ENVIRONMENT : 0), env,
                            cwd, &si, &pi)) {
    say("  trial %s: CreateProcessAsUser FAILED - %s", label,
        winerr(GetLastError()));
  } else {
    if (WaitForSingleObject(pi.hProcess, 15000) == WAIT_TIMEOUT) {
      TerminateProcess(pi.hProcess, 99);
      code = TRIAL_TIMEOUT;
    } else {
      GetExitCodeProcess(pi.hProcess, &code);
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    say("  trial %s: exit %lu (0x%08lx)%s", label, (unsigned long)code,
        (unsigned long)code,
        code == 0xC0000142UL ? " = DLL INIT FAILED"
        : code == TRIAL_TIMEOUT ? " = still running at 15 s, terminated" : "");
  }
  if (env)
    DestroyEnvironmentBlock(env);
  return code;
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
  const char* desk = "winsta0\\default";
  DWORD cflags = CREATE_NO_WINDOW;
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

  /* ---- PREFLIGHT: the NATIVE relay child must initialise at Low before the
     handover is attempted.  Iteration 4's trials: native at Low ran, MSYS2 at
     Low died 0xC0000142 because this parent - an MSYS2 process of the same
     runtime - already holds the runtime's object directory. */
  snprintf(childexe, sizeof childexe, "%s\\probe-relaychild.exe", dir);
  snprintf(lowdir, sizeof lowdir, "%s\\low", dir);
  {
    DWORD pf = trial("preflight: native relay child --hello at Low", prim,
                     childexe, "--hello", desk, cflags, lowdir);
    if (pf != 7) {
      say("REFUSED: the native relay child did not initialise at Low (exit 0x%08lx) - the handover is not attempted.",
          (unsigned long)pf);
      CloseHandle(prim);
      return 2;
    }
    say("  preflight         : native relay child initialised at Low (exit 7)");
  }

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
  si.lpDesktop = (char*)desk; /* the configuration the trials chose */
  ZeroMemory(&pi, sizeof pi);

  if (!CreateProcessAsUserA(prim, childexe, cmd, NULL, NULL, TRUE,
                            cflags | (env ? CREATE_UNICODE_ENVIRONMENT : 0),
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

/* The relay child is probe-relaychild.c, a native program (iteration 5). */

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
  printf("usage: probe-relaydrop.exe --parent <dir> <account>\n"
         "       (the child is probe-relaychild.exe, staged beside it)\n");
  return 2;
}
