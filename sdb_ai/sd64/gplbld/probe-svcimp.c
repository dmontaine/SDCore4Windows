/* probe-svcimp.c - can a VIRTUAL SERVICE ACCOUNT adopt a broker-minted token?
 *
 * 16 Sep 26 Windows port, RELEASE_1.1 43.  Built and driven by
 * probe-svcimp.ps1.  Owner's option 1, 16 Sep 2026: a throwaway "sdprobe"
 * service, so the real SD service is never touched.
 *
 * ===========================================================================
 * WHAT IS ALREADY MEASURED, SO THIS DOES NOT RE-ASK IT
 *
 * probe-impfork.c's Q4 ran 24 Aug 2026 (-Account test1, elevated) and settled
 * the MECHANISM - HISTORY.md:4523:
 *
 *   CW_SET_EXTERNAL_TOKEN, then fork              LOST (token NONE, file SYSTEM)
 *   register, then seteuid(target), then fork     CARRIED (file owned by the user)
 *
 * The bare call only REGISTERS a token; seteuid() is what makes the runtime
 * adopt it, which is why Cygwin's own sshd and su do the pair.  Row 1 is the
 * control and it reproduced the defect before the cure was tried.
 *
 * ***THAT RUN WAS LocalSystem.***  RELEASE_1.1 43's plan (owner's option 3c)
 * needs the same sequence to hold in a session running as the virtual service
 * account NT SERVICE\SD, which does NOT hold SeTcbPrivilege - which is the
 * whole reason the plan puts a LocalSystem broker in front to do the minting.
 * The entry records the remaining claim as conditional and unmeasured:
 *
 *   "a session running as NT SERVICE\SD WOULD be able to
 *    ImpersonateLoggedOnUser a broker-minted token and adopt it across fork()"
 *
 * So the only new variable here is THE CALLER'S ACCOUNT.  Everything else is
 * held identical to the run that already passed.
 *
 * ===========================================================================
 * THE TWO ROLES, AND WHY THEY CANNOT BE ONE PROCESS
 *
 * --broker   runs as LocalSystem (schtasks /RU SYSTEM, the shape the other
 *            probes already use).  Only a caller holding SeTcbPrivilege gets a
 *            usable impersonation-level S4U token back - measured by
 *            probe-s4u.c, 23 Aug 2026 - so the minting MUST happen here.
 *            LsaLogonUser returns a HANDLE valid only in this process, so the
 *            broker DuplicateHandle()s it into the worker and writes the
 *            duplicated VALUE where the worker can read it.
 *
 * --worker   runs as NT SERVICE\sdprobe, started by the SCM, because only the
 *            SCM can put a process under a virtual service account: runas and
 *            schtasks cannot.  It receives the handle, impersonates, and runs
 *            the proven sequence.
 *
 * ***THE NULL CASE THIS PROBE MUST REFUSE IS THE WHOLE POINT OF IT.***  If the
 * worker is not actually running as a virtual service account, every row below
 * would pass - and would be re-measuring what probe-impfork measured in
 * August.  So the worker asserts its own account before it does anything, and
 * REFUSES if it is SYSTEM, an administrator, or anything else.
 *
 * ===========================================================================
 * FALSIFIED-IF, from the entry, unchanged: the worker, holding the broker's
 * token, writes a file owned by NT SERVICE\sdprobe or by SYSTEM rather than by
 * the user.  Then option 3c does not close the gap and the choice reopens.
 *
 * Exit: 0 the question was answered (read the verdict), 2 it could not be.
 * Both roles write a log file, because a service has no console to print to.
 */

#include <windows.h>
#include <ntsecapi.h>
#include <sddl.h>
#include <aclapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <strings.h> /* strncasecmp - this is the MSYS runtime, not MSVC */
#include <wchar.h>
#include <fcntl.h>
#include <errno.h>
#include <pwd.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/stat.h>
/* The runtime's own header, AFTER windows.h: the external-token call is given
   the Win32 HANDLE type.  probe-impfork.c:140 records the same ordering. */
#include <sys/cygwin.h>

#define WAIT_SECONDS 25 /* Under the SCM's 30 s window - see the .ps1 */

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

/* DOMAIN\name for a token's user, or "" when it cannot be read. */
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

/* Does this process hold the named privilege at all (enabled or not)? */
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

/* 16 Sep 26 diagnostic (RELEASE_1.1 43).  EVERY privilege on the process token,
   name and whether enabled - the verdict on why seteuid refused has to be read
   against what this account ACTUALLY holds, not a hand-picked list that could
   omit the one that mattered.  LocalSystem (the proven Q4 run) holds
   SeAssignPrimaryToken and SeIncreaseQuota; a virtual service account may not,
   and Cygwin's user-context switch may need one of them - so it is enumerated,
   not assumed. */
static void dump_privileges(void) {
  HANDLE t;
  BYTE buf[8192];
  DWORD len = 0;
  TOKEN_PRIVILEGES* tp;
  DWORD i;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t)) {
    say("  privileges        : <OpenProcessToken failed: %s>",
        winerr(GetLastError()));
    return;
  }
  if (!GetTokenInformation(t, TokenPrivileges, buf, sizeof buf, &len)) {
    say("  privileges        : <GetTokenInformation failed: %s>",
        winerr(GetLastError()));
    CloseHandle(t);
    return;
  }
  tp = (TOKEN_PRIVILEGES*)buf;
  say("  privileges (%lu held):", (unsigned long)tp->PrivilegeCount);
  for (i = 0; i < tp->PrivilegeCount; i++) {
    char nm[64];
    DWORD nl = sizeof nm;
    int on = (tp->Privileges[i].Attributes &
              (SE_PRIVILEGE_ENABLED | SE_PRIVILEGE_ENABLED_BY_DEFAULT)) != 0;
    if (LookupPrivilegeNameA(NULL, &tp->Privileges[i].Luid, nm, &nl))
      say("    %-34s %s", nm, on ? "enabled" : "present (off)");
    else
      say("    <luid %lx:%lx> %s",
          (unsigned long)tp->Privileges[i].Luid.HighPart,
          (unsigned long)tp->Privileges[i].Luid.LowPart,
          on ? "enabled" : "present (off)");
  }
  CloseHandle(t);
}

/* 16 Sep 26 (RELEASE_1.1 43).  Enable a PRESENT privilege on the PROCESS token.
   The grant put SeAssignPrimaryToken/SeIncreaseQuota in the worker's token but
   OFF, and Win32 1314 is returned for present-but-disabled as well as for
   absent - so before reading the second 1314 as "the account cannot", we turn
   on what it holds.  LocalSystem (the proven Q4 run) carries these ENABLED by
   default; a granted service account does not.  Enabling a privilege the token
   already holds needs no right of its own.  Returns 1 only when it is on
   afterwards (AdjustTokenPrivileges returns TRUE with ERROR_NOT_ALL_ASSIGNED
   when the privilege is not held, which is NOT success). */
static int enable_privilege(const char* name) {
  HANDLE t;
  LUID luid;
  TOKEN_PRIVILEGES tp;
  int ok = 0;

  if (!LookupPrivilegeValueA(NULL, name, &luid))
    return 0;
  if (!OpenProcessToken(GetCurrentProcess(),
                        TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &t))
    return 0;
  tp.PrivilegeCount = 1;
  tp.Privileges[0].Luid = luid;
  tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
  if (AdjustTokenPrivileges(t, FALSE, &tp, sizeof tp, NULL, NULL) &&
      GetLastError() == ERROR_SUCCESS)
    ok = 1;
  CloseHandle(t);
  return ok;
}

/* The identity the RUNTIME believes in, which is not the thread token - the
   distinction probe-impfork had to make and this inherits. */
static const char* thread_account_as(BOOL openAsSelf) {
  HANDLE t;
  static char r[256];
  DWORD e;
  snprintf(r, sizeof r, "NONE");
  if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, openAsSelf, &t)) {
    snprintf(r, sizeof r, "%s", token_account(t));
    CloseHandle(t);
  } else {
    e = GetLastError();
    /* 16 Sep 26 - WHY IT FAILED, NOT JUST THAT IT DID.  The first run of this
       probe printed a bare "NONE" after an ImpersonateLoggedOnUser that had
       RETURNED SUCCESS, which cannot be read as "not impersonating": with
       OpenAsSelf TRUE the access check uses the PROCESS token, and as a
       virtual service account that may fail to open a token which is in fact
       attached.  A verdict drawn from that would not have known which. */
    snprintf(r, sizeof r, "NONE (OpenThreadToken err %lu)", (unsigned long)e);
  }
  return r;
}

/* Both ways round, because they answer different questions and the pair is
   what tells "not impersonating" from "cannot look". */
static const char* thread_account(void) { return thread_account_as(FALSE); }

/* Create a file and report who owns it - the measurement the verdict rests
   on.  GetNamedSecurityInfoA, as probe-impfork.c:233 does. */
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
   THE BROKER - LocalSystem.  Mints, duplicates, hands over.             */

static int broker(const char* dir, const char* account) {
  char pidpath[MAX_PATH], tokpath[MAX_PATH];
  FILE* f;
  /* 16 Sep 26 - unsigned long, NOT DWORD, AND IT COST A RUN TO SEE WHY.
     This was "DWORD workerpid" read with fscanf("%lu", (unsigned long*)&...).
     Under the MSYS2/Cygwin runtime unsigned long is EIGHT bytes and DWORD is
     four, so the scan wrote four bytes past it and into tokpath, which sits
     next to it on the stack.  The symptom was that the path printed correctly,
     a write test through it SUCCEEDED, and then the same variable came back
     EMPTY a few calls later - "cannot write [] - errno 2".  The identical code
     is correct under MSVC, where unsigned long is four bytes; it is this
     runtime that makes it wrong, which is the same LP64 difference the port
     has to keep in mind everywhere it touches Win32 types. */
  unsigned long workerpid = 0;
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
  HANDLE tok = NULL, hworker = NULL, dup = NULL;
  wchar_t wuser[256], wdom[256];
  int i, ok = 0;

  say("probe-svcimp BROKER");
  say("  running as        : %s", my_account());
  say("  SeTcbPrivilege    : %s", has_privilege("SeTcbPrivilege") ? "yes" : "NO");

  /* NULL CASE: without SeTcbPrivilege the S4U token comes back unusable
     (probe-s4u.c, 23 Aug 2026), so a failure here would be misread as "3c
     does not work" when it is "the broker was not LocalSystem". */
  if (!has_privilege("SeTcbPrivilege")) {
    say("REFUSED: the broker is not holding SeTcbPrivilege, so it cannot mint.");
    return 2;
  }

  snprintf(pidpath, sizeof pidpath, "%s\\worker.pid", dir);
  snprintf(tokpath, sizeof tokpath, "%s\\token.txt", dir);
  say("  handoff dir       : [%s]", dir);
  say("  will read         : [%s]", pidpath);
  say("  will write        : [%s]", tokpath);

  /* 16 Sep 26 - WRITABILITY IS PROVED BEFORE THE TOKEN IS MINTED, NOT AFTER.
     The first run got as far as minting and duplicating and THEN could not
     write the handoff file, reporting only "cannot write" with no path and no
     errno - which is this project's own instrument rule broken in the probe
     that exists to obey it.  Failing here instead costs nothing and says
     exactly what was tried. */
  {
    FILE* t = fopen(tokpath, "w");
    if (!t) {
      say("REFUSED: cannot create [%s] - errno %d (%s)", tokpath, errno,
          strerror(errno));
      say("  the broker runs as %s; check the ACL on the handoff directory.",
          my_account());
      return 2;
    }
    fclose(t);
    unlink(tokpath);
    say("  write test        : ok");
  }

  for (i = 0; i < WAIT_SECONDS; i++) {
    f = fopen(pidpath, "r");
    if (f) {
      if (fscanf(f, "%lu", &workerpid) != 1)
        workerpid = 0;
      fclose(f);
      if (workerpid)
        break;
    }
    Sleep(1000);
  }
  if (!workerpid) {
    say("REFUSED: no worker pid appeared at %s - the worker never started.",
        pidpath);
    return 2;
  }
  say("  worker pid        : %lu", (unsigned long)workerpid);

  /* --- mint, exactly as probe-s4u.c does ------------------------------- */
  lsaname.Buffer = (char*)"sdprobe";
  lsaname.Length = (USHORT)strlen(lsaname.Buffer);
  lsaname.MaximumLength = (USHORT)(lsaname.Length + 1);
  st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (st != 0) {
    say("REFUSED: LsaRegisterLogonProcess 0x%lx", (unsigned long)st);
    return 2;
  }
  pkgname.Buffer = (char*)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(pkgname.Buffer);
  pkgname.MaximumLength = (USHORT)(pkgname.Length + 1);
  st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (st != 0) {
    say("REFUSED: LsaLookupAuthenticationPackage 0x%lx", (unsigned long)st);
    return 2;
  }

  MultiByteToWideChar(CP_ACP, 0, account, -1, wuser, 256);
  MultiByteToWideChar(CP_ACP, 0, ".", -1, wdom, 256);

  /* ONE contiguous block: LSA copies the whole thing (probe-s4u.c:565). */
  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) +
                   (wcslen(wuser) + 1) * sizeof(wchar_t) +
                   (wcslen(wdom) + 1) * sizeof(wchar_t));
  s4u = (MSV1_0_S4U_LOGON*)calloc(1, s4ulen);
  if (!s4u) {
    say("REFUSED: out of memory");
    return 2;
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

  origin.Buffer = (char*)"sdprobe";
  origin.Length = (USHORT)strlen(origin.Buffer);
  origin.MaximumLength = (USHORT)(origin.Length + 1);
  memcpy(source.SourceName, "sdprobe\0", 8);
  AllocateLocallyUniqueId(&source.SourceIdentifier);

  st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen, NULL, &source,
                    &prof, &proflen, &luid, &tok, &quota, &sub);
  free(s4u);
  if (st != 0 || tok == NULL) {
    say("REFUSED: LsaLogonUser 0x%lx sub 0x%lx", (unsigned long)st,
        (unsigned long)sub);
    return 2;
  }
  say("  minted token for  : %s", token_account(tok));

  /* --- hand it over ----------------------------------------------------- */
  hworker = OpenProcess(PROCESS_DUP_HANDLE, FALSE, (DWORD)workerpid);
  if (!hworker) {
    say("REFUSED: OpenProcess(PROCESS_DUP_HANDLE, %lu) - %s",
        (unsigned long)workerpid, winerr(GetLastError()));
    return 2;
  }
  if (!DuplicateHandle(GetCurrentProcess(), tok, hworker, &dup, 0, FALSE,
                       DUPLICATE_SAME_ACCESS)) {
    say("REFUSED: DuplicateHandle - %s", winerr(GetLastError()));
    CloseHandle(hworker);
    return 2;
  }
  say("  duplicated handle : %p (valid in the worker)", (void*)dup);

  f = fopen(tokpath, "w");
  if (!f) {
    say("REFUSED: cannot write [%s] - errno %d (%s)", tokpath, errno,
        strerror(errno));
    CloseHandle(hworker);
    return 2;
  }
  fprintf(f, "%llu\n", (unsigned long long)(uintptr_t)dup);
  fclose(f);
  ok = 1;
  CloseHandle(hworker);
  say("  handed over       : %s", ok ? "yes" : "no");
  return 0;
}

/* ======================================================================
   THE WORKER - NT SERVICE\sdprobe.  Receives, impersonates, forks.      */

static int worker(const char* dir, const char* account) {
  char pidpath[MAX_PATH], tokpath[MAX_PATH], f1[MAX_PATH], f2[MAX_PATH];
  FILE* f;
  HANDLE tok = NULL;
  unsigned long long raw = 0;
  struct passwd* pw;
  const char* acct;
  int i, status, plain_lost = 0;
  pid_t child;

  say("probe-svcimp WORKER");
  acct = my_account();
  say("  running as        : %s", acct);
  say("  SeImpersonate     : %s",
      has_privilege("SeImpersonatePrivilege") ? "yes" : "NO");
  say("  SeTcbPrivilege    : %s  (expected NO - that is why a broker exists)",
      has_privilege("SeTcbPrivilege") ? "yes" : "NO");
  dump_privileges();

  /* ***THE NULL CASE, AND IT IS THE WHOLE POINT.***  If this is not really a
     virtual service account then the run re-measures probe-impfork's August
     result and would pass for the wrong reason. */
  if (strncasecmp(acct, "NT SERVICE\\", 11) != 0) {
    say("REFUSED: the worker is running as '%s', not a virtual service", acct);
    say("  account.  Every row below would pass without testing 43's claim.");
    return 2;
  }

  snprintf(pidpath, sizeof pidpath, "%s\\worker.pid", dir);
  snprintf(tokpath, sizeof tokpath, "%s\\token.txt", dir);
  snprintf(f1, sizeof f1, "%s\\made-plain.txt", dir);
  snprintf(f2, sizeof f2, "%s\\made-adopted.txt", dir);

  f = fopen(pidpath, "w");
  if (!f) {
    say("REFUSED: cannot write %s", pidpath);
    return 2;
  }
  fprintf(f, "%lu\n", (unsigned long)GetCurrentProcessId());
  fclose(f);

  for (i = 0; i < WAIT_SECONDS; i++) {
    f = fopen(tokpath, "r");
    if (f) {
      if (fscanf(f, "%llu", &raw) != 1)
        raw = 0;
      fclose(f);
      if (raw)
        break;
    }
    Sleep(1000);
  }
  if (!raw) {
    say("REFUSED: the broker never handed a token over.");
    return 2;
  }
  tok = (HANDLE)(uintptr_t)raw;
  say("  received handle   : %p", (void*)tok);
  say("  token belongs to  : %s", token_account(tok));

  say("  runtime identity  : uid %d euid %d  (BEFORE anything)", (int)getuid(),
      (int)geteuid());
  pw = getpwnam(account);
  say("  getpwnam(%s)      : %s", account,
      pw ? "found" : "NOT FOUND - the runtime cannot name the target user");
  if (pw)
    say("  target uid        : %d", (int)pw->pw_uid);

  /* 16 Sep 26 diagnostic (RELEASE_1.1 43).  The first run showed uid -1 here:
     the runtime maps this virtual service account to NO POSIX uid, while it
     maps the TARGET user fine (above).  seteuid runs FROM this identity, so
     whether the runtime knows the caller at all is measured, not assumed.  A
     fresh, stable copy of my own name because token_account()'s static buffer
     is about to be reused. */
  {
    char selfacct[256];
    struct passwd* self_pw;
    snprintf(selfacct, sizeof selfacct, "%s", my_account());
    self_pw = getpwnam(selfacct);
    say("  runtime gids      : gid %d egid %d", (int)getgid(), (int)getegid());
    say("  getpwnam(self)    : %s  [%s]", self_pw ? "found" : "NOT FOUND",
        selfacct);
    if (self_pw)
      say("  self uid (byname) : %d", (int)self_pw->pw_uid);
  }

  if (!ImpersonateLoggedOnUser(tok)) {
    say("REFUSED: ImpersonateLoggedOnUser - %s", winerr(GetLastError()));
    say("  (this is the row SeImpersonatePrivilege decides.)");
    return 2;
  }
  say("  after impersonate : thread token %s  [OpenAsSelf FALSE]",
      thread_account_as(FALSE));
  say("                      thread token %s  [OpenAsSelf TRUE]",
      thread_account_as(TRUE));

  /* ***THE GATE THAT WAS MISSING, AND ITS ABSENCE PRODUCED A FALSE VERDICT.***
     The first full run reported both children's files owned by the service
     account and the script called that 43's falsified-if.  But the thread
     token read NONE and getuid() read -1, so the run had never reached the
     impersonated state at all - the plain-fork CONTROL "reproduced the defect"
     trivially, for the same reason, which is what made the whole thing look
     consistent.  A measurement that could not have come out any other way is
     not a measurement, so this refuses instead of scoring it. */
  if (strstr(thread_account_as(FALSE), account) == NULL &&
      strstr(thread_account_as(TRUE), account) == NULL) {
    say("REFUSED: impersonation did not take effect - neither view of the");
    say("  thread token names %s.  Nothing below would be evidence about", account);
    say("  whether a service account can ADOPT a token, only that this probe");
    say("  never impersonated one.  43 is NOT falsified by this run.");
    RevertToSelf();
    return 2;
  }

  /* --- CONTROL: a plain fork MUST lose the identity --------------------- */
  child = fork();
  if (child == 0) {
    say("  [plain fork child] thread token %s", thread_account());
    say("  [plain fork child] created file owned by %s", create_and_owner(f1));
    _exit(0);
  }
  waitpid(child, &status, 0);

  /* --- THE CURE, exactly as probe-impfork Q4 form 2 ------------------- */
  pw = getpwnam(account);
  if (!pw) {
    say("REFUSED: getpwnam(%s) failed - no uid to seteuid to.", account);
    RevertToSelf();
    return 2;
  }
  errno = 0;
  {
    /* win32s4u.c:149 treats non-zero as failure; cygwin_internal returns an
       unsigned uintptr_t here, so the previous "< 0" check was DEAD and could
       never report a failed register - the absence of a note meant nothing.
       Report the actual value so the register step is measured, not assumed. */
    uintptr_t reg = cygwin_internal(CW_SET_EXTERNAL_TOKEN, tok,
                                    CW_TOKEN_IMPERSONATION);
    say("  CW_SET_EXTERNAL_TOKEN: returned %ld (0 = ok), errno %d (%s)",
        (long)reg, errno, strerror(errno));
  }

  /* ***seteuid IS THE STEP THAT MAKES THE RUNTIME ADOPT THE TOKEN***, and the
     first run let it FAIL and carried on to a verdict anyway.  probe-impfork's
     Q4 is explicit that the bare register changes nothing and the pair is the
     cure, so an "adopted child" measured after a failed seteuid is a child
     that adopted nothing - it cannot tell a service account's inability to
     adopt from this probe's failure to ask it to.  Refuse. */
  say("  adopt-relevant    : SeAssignPrimaryToken=%s SeIncreaseQuota=%s "
      "SeTcb=%s SeCreateToken=%s",
      has_privilege("SeAssignPrimaryTokenPrivilege") ? "yes" : "no",
      has_privilege("SeIncreaseQuotaPrivilege") ? "yes" : "no",
      has_privilege("SeTcbPrivilege") ? "yes" : "no",
      has_privilege("SeCreateTokenPrivilege") ? "yes" : "no");

  /* Turn the granted privileges ON before seteuid.  The pair, even ENABLED, was
     not enough (run 3, still 1314), so this run adds SeTcb - the CONFIRMATION
     experiment.  If seteuid now carries, the runtime needs SeTcb and 3c == 3a
     (dead as designed); if it still refuses, the privilege story is wrong and
     the blocker is structural (the uid -1 mapping is the next suspect). */
  {
    int a = enable_privilege("SeAssignPrimaryTokenPrivilege");
    int q = enable_privilege("SeIncreaseQuotaPrivilege");
    int c = enable_privilege("SeTcbPrivilege");
    say("  enabled           : SeAssignPrimaryToken=%s SeIncreaseQuota=%s "
        "SeTcb=%s",
        a ? "on" : "FAILED", q ? "on" : "FAILED", c ? "on" : "FAILED");
  }
  errno = 0;
  SetLastError(0);
  if (seteuid(pw->pw_uid) != 0) {
    DWORD gle = GetLastError();
    say("REFUSED: seteuid(%d) failed - errno %d (%s); Win32 last-error [%s]",
        (int)pw->pw_uid, errno, strerror(errno), winerr(gle));
    say("  uid %d euid %d.  The register-then-seteuid pair never completed, so", (int)getuid(), (int)geteuid());
    say("  no row below would be about ADOPTION.  ***43 IS NOT FALSIFIED BY");
    say("  THIS***; what is measured is that THIS runtime, in THIS account,");
    say("  would not perform the switch - which is a finding about the");
    say("  runtime's user mapping for a virtual service account, and is the");
    say("  next thing to chase rather than a verdict on option 3c.");
    RevertToSelf();
    return 2;
  }
  say("  after seteuid     : uid %d euid %d", (int)getuid(), (int)geteuid());

  child = fork();
  if (child == 0) {
    say("  [adopted child]    thread token %s", thread_account());
    say("  [adopted child]    created file owned by %s", create_and_owner(f2));
    _exit(0);
  }
  waitpid(child, &status, 0);

  RevertToSelf();
  (void)plain_lost;
  say("WORKER DONE - read made-plain.txt and made-adopted.txt owners above.");
  return 0;
}

int main(int argc, char* argv[]) {
  char logpath[MAX_PATH];
  const char* dir;
  const char* account;
  int rc;

  if (argc < 4) {
    printf("usage: probe-svcimp.exe --broker|--worker <handoff-dir> <account>\n");
    return 2;
  }
  dir = argv[2];
  account = argv[3];

  snprintf(logpath, sizeof logpath, "%s\\%s.log", dir,
           (strcmp(argv[1], "--broker") == 0) ? "broker" : "worker");
  lg = fopen(logpath, "w");

  if (strcmp(argv[1], "--broker") == 0)
    rc = broker(dir, account);
  else if (strcmp(argv[1], "--worker") == 0)
    rc = worker(dir, account);
  else {
    printf("unknown role '%s'\n", argv[1]);
    rc = 2;
  }

  if (lg)
    fclose(lg);
  return rc;
}
