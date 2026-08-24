/* probe-impfork.c - the two things step 14 cannot decide without them.
 *
 * 24 Aug 26 Windows port.  Built and run by probe-impfork.ps1.
 * PROJECT_STATUS.md section 7 step 14, after run b28.
 *
 * WHY THIS EXISTS AND WHY IT IS NOT AN EDIT TO probe-impersonate.c.  That
 * probe's result is cited in PROJECT_STATUS as the evidence shape (b) rests
 * on, so it stays exactly as it was and stays re-runnable.  This one asks two
 * further questions, and carries probe-impersonate's whole measurement as its
 * own control so the comparison is inside a single run.
 *
 * ---------------------------------------------------------------------------
 * QUESTION 1 - THE ONE PROJECT_STATUS ASKS FOR.  Does impersonation still
 * govern open() IN A fork()ed AND exec()d CYGWIN CHILD?
 *
 * probe-impersonate measured a STANDALONE program started by schtasks, i.e.
 * with cmd.exe - not a Cygwin process - as its parent, so the MSYS2 runtime
 * initialised itself from its own process token.  An API session is neither:
 * sdwind.c:491 fork()s and execl()s it, so the runtime's idea of the user is
 * inherited through Cygwin's own child startup rather than derived afresh.
 * That difference is untested, and step 14 names re-testing it as the cheapest
 * thing that could overturn shape (b).
 *
 * ---------------------------------------------------------------------------
 * QUESTION 2 - AND IT IS ABOUT b28's INSTRUMENT, NOT ABOUT SD.  When a file is
 * CREATED while impersonating, whose name goes on it?
 *
 * verify-apiidentity's ownership probe read Get-Acl.Owner on a record written
 * by the API session, found NT AUTHORITY\SYSTEM, and concluded that the
 * K$ASSUME.USER switch has no effect.  Its control was that a record written
 * by a LOCAL elevated session read GITORLI\don instead.
 *
 * ***THAT CONTROL DOES NOT SEPARATE THE TWO EXPLANATIONS.*** In both readings
 * the owner equals the identity of the PROCESS that wrote it - the local
 * session's process is don's, the API session's process is the service's.  So
 * it is equally consistent with:
 *
 *   (i)  the impersonation is not in effect at all, or
 *   (ii) the impersonation IS in effect - open() is governed, access is the
 *        user's - but the runtime stamps a NEW file's owner from its own
 *        cached idea of the user, which fork() carried in from the service
 *        and which ImpersonateLoggedOnUser does not touch.
 *
 * If (ii) holds, b28 measured the runtime's owner-stamping and not the
 * session's effective token, and step 14's conclusion has to be rewritten.
 * ONE RUN SEPARATES THEM: impersonate, then in the SAME breath try to open a
 * file the user may not read AND create a file, and report both.
 *
 *   forbidden refused + created file owned by SYSTEM -> (ii).  Access is
 *       governed; ownership is not the instrument it was taken for.
 *   forbidden OPENED  + created file owned by SYSTEM -> (i).  b28 stands and
 *       shape (b) buys nothing in a forked child.
 *
 * THE RUNTIME'S OWN UID IS PRINTED THROUGHOUT, before, during and after the
 * switch.  getuid()/geteuid() answer from the cached user that mechanism (ii)
 * is about, so if they do not move while the THREAD TOKEN does, that is the
 * mechanism visible directly rather than inferred.
 *
 * ---------------------------------------------------------------------------
 * CONTROLS, and they are most of the file.  Per leg:
 *
 *   control A, before impersonating   both opens must SUCCEED, or a refusal
 *                                     later says nothing about the token
 *   control B, after RevertToSelf     the forbidden open must SUCCEED again,
 *                                     or the refusal may have been a lock or
 *                                     a bad path
 *   ownership control                 a file is created BEFORE impersonating
 *                                     too.  Without it, "owned by SYSTEM"
 *                                     could mean the fixture forces it.
 *   configuration control             the parent runs the identical
 *                                     measurement DIRECTLY after the child
 *                                     has finished, reproducing
 *                                     probe-impersonate's configuration with
 *                                     this binary and these fixtures.  A
 *                                     difference between the two rows is then
 *                                     the fork, and nothing else.
 *
 * A leg whose controls do not hold is reported VOID and does not reach a
 * verdict.  CLAUDE.md: a test that passes because it did nothing must fail.
 *
 * ORDERING IS DELIBERATE: the CHILD runs FIRST, while this process has never
 * impersonated, so nothing the parent did can be carried into it.
 *
 * BUILT WITH THE MSYS2 gcc, not UCRT64 - the runtime is the subject.
 *
 * EXIT CODES.  2 usage, 3 VOID, 4 a required call failed, and on a completed
 * measurement 8 + 1 if access was governed + 2 if ownership tracked the
 * impersonated user.  So 8..11, decoded in words by the parent.
 */

#include <windows.h>
#include <ntsecapi.h>
#include <aclapi.h>
#include <sddl.h>    /* ConvertSidToStringSidA - implicit here is an error */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>

#ifndef O_BINARY
#define O_BINARY 0
#endif

#define R_USAGE 2
#define R_VOID  3
#define R_CALL  4
#define R_BASE  8
#define R_ACCESS 1
#define R_OWNER  2

static void say(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
  printf("\n");
  fflush(stdout);
}

static const char *winerr(DWORD e) {
  static char buf[256];
  DWORD n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
                           FORMAT_MESSAGE_IGNORE_INSERTS,
                           NULL, e, 0, buf, sizeof(buf) - 1, NULL);
  if (n == 0) {
    snprintf(buf, sizeof(buf), "error %lu", (unsigned long)e);
    return buf;
  }
  while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = '\0';
  return buf;
}

/* DOMAIN\name for a SID, or a printable reason it could not be resolved.
   Callers must not put two of these in one printf - one static buffer. */
static const char *sid_name(PSID sid) {
  static char out[256];
  char name[128], dom[128];
  DWORD nlen = sizeof(name), dlen = sizeof(dom);
  SID_NAME_USE use;

  out[0] = '\0';
  if (sid == NULL) {
    snprintf(out, sizeof(out), "(no SID)");
    return out;
  }
  if (!LookupAccountSidA(NULL, sid, name, &nlen, dom, &dlen, &use)) {
    LPSTR s = NULL;
    if (ConvertSidToStringSidA(sid, &s)) {
      snprintf(out, sizeof(out), "(unresolved SID %s)", s);
      LocalFree(s);
    } else {
      snprintf(out, sizeof(out), "(LookupAccountSid failed: %s)",
               winerr(GetLastError()));
    }
    return out;
  }
  snprintf(out, sizeof(out), "%s\\%s", dom, name);
  return out;
}

static const char *token_user(HANDLE tok) {
  static char out[256];
  BYTE buf[512];
  DWORD len = 0;

  if (!GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &len)) {
    snprintf(out, sizeof(out), "(GetTokenInformation failed: %s)",
             winerr(GetLastError()));
    return out;
  }
  snprintf(out, sizeof(out), "%s", sid_name(((TOKEN_USER *)buf)->User.Sid));
  return out;
}

/* The owner recorded on an object, read with the Windows API rather than
   inferred.  Returns a printable name; sets *ok to 0 if it could not be read,
   so an unreadable owner is never silently treated as a mismatch. */
static const char *file_owner(const char *path, int *ok) {
  static char out[256];
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  DWORD rc;

  *ok = 0;
  rc = GetNamedSecurityInfoA(path, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
                             &owner, NULL, NULL, NULL, &sd);
  if (rc != ERROR_SUCCESS) {
    snprintf(out, sizeof(out), "(cannot read owner of %s: %s)", path,
             winerr(rc));
    return out;
  }
  snprintf(out, sizeof(out), "%s", sid_name(owner));
  *ok = 1;
  if (sd != NULL) LocalFree(sd);
  return out;
}

/* Try to open a path and say plainly what happened.  1 opened, 0 refused. */
static int try_open(const char *what, const char *path) {
  int fd = open(path, O_RDONLY | O_BINARY);
  if (fd >= 0) {
    close(fd);
    say("    %-36s OPENED", what);
    return 1;
  }
  say("    %-36s refused - errno %d (%s)", what, errno, strerror(errno));
  return 0;
}

/* Create a file with the SAME call SD uses - POSIX open(), through the MSYS2
   runtime - not CreateFile.  The runtime is the subject.  1 created. */
static int try_create(const char *what, const char *path) {
  int fd;
  unlink(path); /* a leftover would be owned by whoever made it last */
  fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_BINARY, 0600);
  if (fd >= 0) {
    if (write(fd, "x\n", 2) != 2)
      say("    %-36s created but the write was short", what);
    close(fd);
    say("    %-36s CREATED", what);
    return 1;
  }
  say("    %-36s not created - errno %d (%s)", what, errno, strerror(errno));
  return 0;
}

static void show_uids(const char *when) {
  say("    runtime uid %-24s uid=%ld euid=%ld", when, (long)getuid(),
      (long)geteuid());
}

/* ==========================================================================
   The measurement.  One function, run twice in different configurations, so
   the two rows cannot drift apart.

   tag         how this run was started, printed so the row names itself
   Returns R_VOID / R_CALL, or R_BASE|flags on a completed measurement.
   ========================================================================== */
static int measure(const char *tag, const char *user, const char *allowed,
                   const char *forbidden, const char *writedir) {
  LSA_STRING lsaname, pkgname;
  LSA_HANDLE hlsa = NULL;
  LSA_OPERATIONAL_MODE mode = 0;
  ULONG pkg = 0;
  MSV1_0_S4U_LOGON *s4u = NULL;
  ULONG s4ulen;
  BYTE *tail;
  WCHAR *wuser, *wdom;
  int wuserlen, wdomlen;
  char dom[MAX_COMPUTERNAME_LENGTH + 1];
  DWORD domlen = sizeof(dom);
  LSA_STRING origin;
  TOKEN_SOURCE src;
  NTSTATUS st, sub = 0;
  void *profile = NULL;
  ULONG proflen = 0;
  LUID logonid;
  HANDLE tok = NULL, thread_tok = NULL;
  QUOTA_LIMITS quota;
  SECURITY_IMPERSONATION_LEVEL lvl;
  DWORD got = 0;
  int a_allowed, a_forbidden, m_allowed, m_forbidden, b_forbidden;
  int made_before, made_during;
  int own_ok_before = 0, own_ok_during = 0;
  char before_path[MAX_PATH], during_path[MAX_PATH];
  char owner_before[256], owner_during[256], thread_who[256];
  int access_governed, owner_tracked;
  int result;

  say("===========================================================");
  say(" MEASUREMENT - %s", tag);
  say("===========================================================");
  say("  pid %ld, parent pid %ld", (long)getpid(), (long)getppid());
  {
    HANDLE me;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &me)) {
      say("  process token   : %s", token_user(me));
      CloseHandle(me);
    } else {
      say("  process token   : (OpenProcessToken failed: %s)",
          winerr(GetLastError()));
    }
  }
  show_uids("at entry");
  say("");

  if (snprintf(before_path, sizeof(before_path), "%s\\made-before", writedir) >=
      (int)sizeof(before_path)) {
    say("  the writable fixture path is too long"); return R_CALL;
  }
  if (snprintf(during_path, sizeof(during_path), "%s\\made-during", writedir) >=
      (int)sizeof(during_path)) {
    say("  the writable fixture path is too long"); return R_CALL;
  }

  /* ---- control A ------------------------------------------------------ */
  say("CONTROL A - before impersonating, as this process's own identity");
  a_allowed   = try_open("allowed file", allowed);
  a_forbidden = try_open("forbidden file", forbidden);
  made_before = try_create("file created BEFORE impersonating", before_path);
  if (!a_allowed || !a_forbidden) {
    say("");
    say("*** VOID: control A did not hold. ***");
    say("    Both files must open BEFORE impersonating, or a refusal later");
    say("    says nothing about the thread token.  Nothing here is a result.");
    return R_VOID;
  }
  if (!made_before) {
    say("");
    say("*** VOID: the writable fixture is not writable by this process. ***");
    say("    The ownership leg has no control without it.  Nothing here is a");
    say("    result.");
    return R_VOID;
  }
  say("  control A holds: both open, and the writable fixture accepts a file.");
  say("");

  /* ---- S4U logon, as probe-s4u.c and probe-impersonate.c do it --------- */
  say("S4U LOGON for %s", user);
  lsaname.Buffer = (PCHAR)"probe-impf";
  lsaname.Length = (USHORT)strlen(lsaname.Buffer);
  lsaname.MaximumLength = lsaname.Length + 1;

  st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (st != 0) {
    say("  LsaRegisterLogonProcess refused: NTSTATUS 0x%08lx",
        (unsigned long)st);
    say("  This must run as LocalSystem - SeTcbPrivilege is the discriminator.");
    say("  probe-impfork.ps1 does that with schtasks /RU SYSTEM.");
    return R_CALL;
  }
  say("  LsaRegisterLogonProcess: TRUSTED connection");

  pkgname.Buffer = (PCHAR)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(pkgname.Buffer);
  pkgname.MaximumLength = pkgname.Length + 1;
  st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (st != 0) {
    say("  LsaLookupAuthenticationPackage failed: 0x%08lx", (unsigned long)st);
    return R_CALL;
  }

  /* ONE CONTIGUOUS BLOCK, both strings in its tail - LSA copies the whole
     buffer into its own process.  Length EXCLUDES the terminator and
     MaximumLength INCLUDES it; setting them equal gives a call that reads
     correctly and fails.  Both traps are recorded in probe-impersonate.c. */
  if (GetComputerNameA(dom, &domlen) == 0) {
    say("  GetComputerNameA failed: %s", winerr(GetLastError()));
    return R_CALL;
  }
  say("  domain (this machine): %s", dom);

  wuserlen = MultiByteToWideChar(CP_ACP, 0, user, -1, NULL, 0);
  wdomlen  = MultiByteToWideChar(CP_ACP, 0, dom, -1, NULL, 0);
  if (wuserlen <= 0 || wdomlen <= 0) {
    say("  cannot widen the account name: %s", winerr(GetLastError()));
    return R_CALL;
  }

  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) +
                   (size_t)wuserlen * sizeof(WCHAR) +
                   (size_t)wdomlen * sizeof(WCHAR));
  s4u = (MSV1_0_S4U_LOGON *)calloc(1, s4ulen);
  if (s4u == NULL) { say("  out of memory"); return R_CALL; }

  tail  = (BYTE *)s4u + sizeof(MSV1_0_S4U_LOGON);
  wuser = (WCHAR *)tail;
  wdom  = (WCHAR *)(tail + (size_t)wuserlen * sizeof(WCHAR));
  MultiByteToWideChar(CP_ACP, 0, user, -1, wuser, wuserlen);
  MultiByteToWideChar(CP_ACP, 0, dom,  -1, wdom,  wdomlen);

  s4u->MessageType = MsV1_0S4ULogon;
  s4u->Flags       = 0;
  s4u->UserPrincipalName.Length        = (USHORT)((wuserlen - 1) * sizeof(WCHAR));
  s4u->UserPrincipalName.MaximumLength = (USHORT)(wuserlen * sizeof(WCHAR));
  s4u->UserPrincipalName.Buffer        = wuser;
  s4u->DomainName.Length               = (USHORT)((wdomlen - 1) * sizeof(WCHAR));
  s4u->DomainName.MaximumLength        = (USHORT)(wdomlen * sizeof(WCHAR));
  s4u->DomainName.Buffer               = wdom;

  origin.Buffer        = (PCHAR)"probe-impf";
  origin.Length        = (USHORT)strlen(origin.Buffer);
  origin.MaximumLength = (USHORT)(origin.Length + 1);

  memcpy(src.SourceName, "probeimf", 8);
  if (!AllocateLocallyUniqueId(&src.SourceIdentifier)) {
    say("  AllocateLocallyUniqueId failed: %s", winerr(GetLastError()));
    return R_CALL;
  }

  st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen, NULL, &src,
                    &profile, &proflen, &logonid, &tok, &quota, &sub);
  if (st != 0 || tok == NULL) {
    say("  LsaLogonUser failed: 0x%08lx (sub 0x%08lx)", (unsigned long)st,
        (unsigned long)sub);
    return R_CALL;
  }
  say("  token for       : %s", token_user(tok));

  if (GetTokenInformation(tok, TokenImpersonationLevel, &lvl, sizeof(lvl),
                          &got)) {
    say("  impersonation   : %s",
        lvl == SecurityImpersonation  ? "Impersonation" :
        lvl == SecurityIdentification ? "Identification" : "other");
    if (lvl != SecurityImpersonation) {
      say("");
      say("*** VOID: the token is not at Impersonation level. ***");
      say("    ImpersonateLoggedOnUser would succeed and change nothing.");
      return R_VOID;
    }
  }
  say("");

  /* ---- the measurement ------------------------------------------------ */
  say("MEASUREMENT - while impersonating %s", user);
  if (!ImpersonateLoggedOnUser(tok)) {
    say("  ImpersonateLoggedOnUser failed: %s", winerr(GetLastError()));
    return R_CALL;
  }

  /* Readback, not a return code - probe-s4u.c's convention, and the reason
     its result could be trusted. */
  thread_who[0] = '\0';
  if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &thread_tok)) {
    snprintf(thread_who, sizeof(thread_who), "%s", token_user(thread_tok));
    say("  thread token now: %s   <- readback, not a return code", thread_who);
    CloseHandle(thread_tok);
  } else {
    say("  OpenThreadToken failed: %s", winerr(GetLastError()));
    say("");
    say("*** VOID: the thread token could not be read back. ***");
    say("    Without it there is no evidence the switch happened at all.");
    RevertToSelf();
    return R_VOID;
  }

  /* THE RUNTIME'S OWN IDEA OF THE USER, asked while the thread token says
     somebody else.  If this does not move, mechanism (ii) in the header is
     visible directly rather than inferred. */
  show_uids("while impersonating");

  m_allowed   = try_open("allowed file", allowed);
  m_forbidden = try_open("forbidden file", forbidden);
  made_during = try_create("file created WHILE impersonating", during_path);

  RevertToSelf();
  say("");

  /* ---- control B ------------------------------------------------------ */
  say("CONTROL B - after RevertToSelf");
  show_uids("after reverting");
  b_forbidden = try_open("forbidden file", forbidden);
  if (!b_forbidden) {
    say("");
    say("*** VOID: control B did not hold. ***");
    say("    The forbidden file did not open again after reverting, so the");
    say("    refusal above may have been a lock or a bad path.");
    return R_VOID;
  }
  say("  control B holds: reverting restored access.");
  say("");

  /* ---- owners, read AFTER reverting so the read itself cannot be the
     thing that was refused --------------------------------------------- */
  say("OWNERSHIP - read after reverting, so no read is refused by the switch");
  snprintf(owner_before, sizeof(owner_before), "%s",
           made_before ? file_owner(before_path, &own_ok_before)
                       : "(not created)");
  snprintf(owner_during, sizeof(owner_during), "%s",
           made_during ? file_owner(during_path, &own_ok_during)
                       : "(not created)");
  say("  created BEFORE impersonating : %s", owner_before);
  say("  created WHILE impersonating  : %s", owner_during);
  say("  thread token at that moment  : %s", thread_who);
  say("");

  /* ---- verdict -------------------------------------------------------- */
  access_governed = (!m_forbidden && m_allowed);
  owner_tracked   = 0;

  say("VERDICT - %s", tag);
  say("  Q1 ACCESS");
  say("    allowed file while impersonating   : %s",
      m_allowed ? "opened" : "REFUSED");
  say("    forbidden file while impersonating : %s",
      m_forbidden ? "OPENED" : "refused");
  if (access_governed) {
    say("    -> IMPERSONATION GOVERNS open() here.");
  } else if (m_forbidden) {
    say("    -> IMPERSONATION DOES NOT GOVERN open() here.  The runtime opened");
    say("       a file the impersonated user may not read.");
  } else {
    say("    -> INCONCLUSIVE: the allowed file was refused too, so the target");
    say("       may have no access to either path.  Check the fixtures.");
  }
  say("");

  say("  Q2 OWNERSHIP OF A FILE CREATED THROUGH THE RUNTIME");
  if (!made_during) {
    say("    NOT MEASURED: the file could not be created while impersonating.");
    say("    That is itself a reading - the user may not write the fixture -");
    say("    but it is not an answer about ownership.");
  } else if (!own_ok_during || !own_ok_before) {
    say("    NOT MEASURED: an owner could not be read.  See the lines above;");
    say("    a name that could not be resolved is not a mismatch.");
  } else if (strcmp(owner_before, owner_during) != 0) {
    owner_tracked = 1;
    say("    The two owners DIFFER, so ownership tracks the writing identity.");
    say("    b28's instrument means what it was taken to mean.");
  } else {
    say("    The two owners are THE SAME (%s) although the thread token was", owner_before);
    say("    %s at the moment of creation.", thread_who);
    say("    -> OWNERSHIP DOES NOT TRACK THE THREAD TOKEN.  The runtime stamps");
    say("       a new file from its own cached user, which fork() carried in.");
  }
  say("");

  /* THE COMBINATION IS THE POINT, so it is stated rather than left to be
     assembled by a reader of two separate verdicts. */
  say("  WHAT THE COMBINATION MEANS FOR b28");
  if (access_governed && !owner_tracked && made_during) {
    say("    ACCESS GOVERNED and OWNERSHIP BLIND.  This is mechanism (ii):");
    say("    verify-apiidentity read the runtime's owner-stamping, not the");
    say("    session's effective token, and its control could not have");
    say("    separated the two.  Step 14's conclusion needs rewriting and the");
    say("    ownership probe needs replacing with an ACCESS one.");
  } else if (!access_governed && !owner_tracked) {
    say("    ACCESS NOT GOVERNED and OWNERSHIP BLIND.  b28's reading stands:");
    say("    the switch does not reach the file layer in this configuration.");
    say("    cygwin_internal(CW_SET_EXTERNAL_TOKEN) is the next thing to try");
    say("    before shape (b) is abandoned for shape (a).");
  } else if (access_governed && owner_tracked) {
    say("    ACCESS GOVERNED and OWNERSHIP TRACKING.  Both instruments agree");
    say("    here, so the difference from b28 is the API session itself and");
    say("    not the runtime - look at APISRVR and the hook, not at Cygwin.");
  } else {
    say("    Mixed or unmeasured - read the two blocks above rather than");
    say("    taking a one-line answer from here.");
  }
  say("");

  result = R_BASE;
  if (access_governed) result |= R_ACCESS;
  if (owner_tracked)   result |= R_OWNER;
  say("  exit code %d = 8 base + %d access + %d ownership", result,
      access_governed ? R_ACCESS : 0, owner_tracked ? R_OWNER : 0);
  say("");
  return result;
}

/* Decode an exit code into words, so no reader has to do the arithmetic. */
static void explain(const char *tag, int code) {
  if (code == R_USAGE)      { say("  %-28s : usage error", tag); return; }
  if (code == R_VOID)       { say("  %-28s : VOID - controls did not hold", tag); return; }
  if (code == R_CALL)       { say("  %-28s : a required call failed", tag); return; }
  if (code < R_BASE || code > (R_BASE | R_ACCESS | R_OWNER)) {
    say("  %-28s : did not complete (exit %d)", tag, code);
    return;
  }
  say("  %-28s : access %s, ownership %s", tag,
      (code & R_ACCESS) ? "GOVERNED" : "not governed",
      (code & R_OWNER)  ? "tracks the token" : "blind to the token");
}

int main(int argc, char *argv[]) {
  const char *user, *allowed, *forbidden, *writedir;
  char self[MAX_PATH];
  ssize_t n;
  pid_t pid;
  int child_status = 0, child_code = -1, direct_code;

  /* --- SELF-TEST for the owner reader, so its first exercise is not the
     elevated run.  The ownership leg only executes after a successful S4U
     logon, which needs SeTcbPrivilege, so without this mode a broken
     GetNamedSecurityInfoA would be discovered by spending the measurement.
     CLAUDE.md: use the check that CATCHES THE BREAK. ------------------- */
  if (argc == 3 && strcmp(argv[1], "--ownercheck") == 0) {
    int ok = 0;
    const char *who = file_owner(argv[2], &ok);
    say("owner of %s", argv[2]);
    say("  -> %s", who);
    say("  readable: %s", ok ? "yes" : "NO");
    return ok ? 0 : 1;
  }

  /* --- the forked child does one measurement and says nothing else ----- */
  if (argc == 6 && strcmp(argv[1], "--child") == 0) {
    return measure("FORKED AND EXEC'D CYGWIN CHILD - the API session's shape",
                   argv[2], argv[3], argv[4], argv[5]);
  }

  if (argc < 5) {
    say("usage: probe-impfork <user> <allowed-file> <forbidden-file> <writable-dir>");
    return R_USAGE;
  }
  user = argv[1]; allowed = argv[2]; forbidden = argv[3]; writedir = argv[4];

  say("probe-impfork - PROJECT_STATUS.md section 7 step 14, after b28");
  say("  Q1  does impersonation govern open() in a fork()ed, exec()d child?");
  say("  Q2  when a file is CREATED while impersonating, whose name is on it?");
  say("");
  say("INPUTS AS RECEIVED");
  say("  target user     : %s", user);
  say("  allowed file    : %s", allowed);
  say("  forbidden file  : %s", forbidden);
  say("  writable dir    : %s", writedir);

  /* REFUSE THE NULL CASE OUT LOUD.  Two identical fixture paths would make
     every comparison below trivially true. */
  if (strcmp(allowed, forbidden) == 0) {
    say("");
    say("*** VOID: the allowed and forbidden paths are the same file. ***");
    return R_VOID;
  }

  n = readlink("/proc/self/exe", self, sizeof(self) - 1);
  if (n > 0) {
    self[n] = '\0';
    say("  this program    : %s   (from /proc/self/exe)", self);
  } else {
    snprintf(self, sizeof(self), "%s", argv[0]);
    say("  this program    : %s   (from argv[0] - /proc/self/exe failed)", self);
  }
  say("");

  /* --- the child FIRST, before this process has ever impersonated ------ */
  say("Forking.  The child runs first, so nothing this process does can");
  say("reach it.  It re-execs this same binary, which is what makes it a");
  say("fork()ed AND exec()d Cygwin child rather than merely a fork.");
  say("");
  fflush(stdout); /* or fork duplicates whatever is still buffered */

  pid = fork();
  if (pid < 0) {
    say("*** fork() failed: %s ***", strerror(errno));
    return R_CALL;
  }
  if (pid == 0) {
    execl(self, "probe-impfork", "--child", user, allowed, forbidden, writedir,
          (char *)NULL);
    /* Only reached if exec failed - and it must not be mistaken for a result. */
    fprintf(stdout, "*** execl failed: %s ***\n", strerror(errno));
    fflush(stdout);
    _exit(R_CALL);
  }

  if (waitpid(pid, &child_status, 0) < 0) {
    say("*** waitpid failed: %s ***", strerror(errno));
    return R_CALL;
  }
  if (WIFEXITED(child_status)) {
    child_code = WEXITSTATUS(child_status);
  } else if (WIFSIGNALED(child_status)) {
    say("*** the child died on signal %d - nothing it printed is a result ***",
        WTERMSIG(child_status));
    child_code = -1;
  }
  say("child pid %ld exited %d", (long)pid, child_code);
  say("");

  /* --- then the same measurement HERE: the configuration control ------- */
  say("Now the identical measurement in THIS process, which cmd.exe started -");
  say("probe-impersonate's configuration, same binary, same fixtures.  A");
  say("difference between the two rows is the fork and nothing else.");
  say("");
  direct_code = measure("DIRECT - started by cmd.exe, as probe-impersonate was",
                        user, allowed, forbidden, writedir);

  say("===========================================================");
  say(" SUMMARY");
  say("===========================================================");
  explain("forked and exec'd child", child_code);
  explain("direct (control)", direct_code);
  say("");

  if (child_code < R_BASE || direct_code < R_BASE) {
    say("  ONE OR BOTH LEGS DID NOT COMPLETE.  Read them above; the comparison");
    say("  below is not made from an incomplete leg.");
    return R_VOID;
  }

  if (child_code == direct_code) {
    say("  THE FORK MAKES NO DIFFERENCE.  Both configurations behave the same,");
    say("  so step 14's suspicion of the fork()ed child is answered NO and the");
    say("  explanation for b28 is whatever the shared row above says it is.");
  } else {
    say("  THE FORK CHANGES THE ANSWER.  The two rows differ, and the only");
    say("  difference between them is how the process was started.  That is");
    say("  the finding step 14 asked for.");
  }
  say("");
  return child_code;
}

/* END-CODE */
