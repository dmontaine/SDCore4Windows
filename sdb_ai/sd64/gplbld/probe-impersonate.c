/* probe-impersonate.c - does thread impersonation govern the MSYS2 runtime's
 * open(), which is how SD opens every data file?
 *
 * 23 Aug 26 Windows port.  Built and run by probe-impersonate.ps1.
 * PROJECT_STATUS.md section 7 step 14, shape (b).
 *
 * THE QUESTION, AND WHY IT DECIDES THE SHAPE.  Step 14 has two shapes.  (a)
 * authenticates in sdwind and spawns the session as the user; (b) lets the
 * session take the user's identity AFTER it authenticates, at APISRVR:1442,
 * the single point where SCRAM sets logged.in.  Shape (b) is much the smaller
 * change and leaves SCRAM readable as BASIC - but it rests entirely on one
 * assumption nobody has tested:
 *
 *     that ImpersonateLoggedOnUser changes what open() can open.
 *
 * probe-s4u.c already proved the token half from LocalSystem: an S4U logon
 * returns an IMPERSONATION-level token and CreateProcessAsUser works with it.
 * It did NOT prove this.  SD does not open files with CreateFile; dh_file.c:815
 * OpenFile() calls POSIX open(), and that goes through msys-2.0.dll, which does
 * its own path translation and its own permission logic.  A runtime that
 * decided access from the PROCESS token, or from cached POSIX ownership, would
 * ignore the thread token completely and shape (b) would buy nothing.
 *
 * SO THIS IS BUILT WITH THE SAME COMPILER AS THE SERVER - the MSYS2 gcc, not
 * UCRT64 - because the runtime is the subject, not the language.
 *
 * WHAT IT MEASURES, and the controls are most of it.  Two directories are
 * prepared by the .ps1: one the target user may read, one ACL'd like
 * sdsys\$cred - SYSTEM and Administrators only.  Then, running as LocalSystem:
 *
 *   control A, before impersonating   both opens must SUCCEED
 *                                     (if the forbidden one fails here the
 *                                      probe is VOID: it would prove only that
 *                                      LocalSystem cannot read it either)
 *   measurement, while impersonating  allowed SUCCEEDS, forbidden must FAIL
 *   control B, after RevertToSelf     forbidden SUCCEEDS again
 *                                     (without this, a denial could be a lock,
 *                                      a bad path or an exhausted handle table)
 *
 * A run where control A or control B does not hold is reported as VOID rather
 * than as a result.  CLAUDE.md: a test that passes because it did nothing must
 * fail, not pass.
 *
 * IDENTITY BY READBACK.  After impersonating, the thread token's user is
 * printed.  probe-s4u established that convention and it is the reason its
 * result could be trusted: a return code says a call succeeded, not who you
 * became.
 *
 * IF THE ANSWER IS NO, the next thing to try before abandoning shape (b) is
 * Cygwin's own hook - cygwin_internal(CW_SET_EXTERNAL_TOKEN, tok,
 * CW_TOKEN_IMPERSONATION) - which tells the runtime about a token it did not
 * create.  That is a second probe, not a fix, and it is out of scope here.
 */

#include <windows.h>
#include <ntsecapi.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>    /* wcslen - implicit here is an error, not a warning */
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>

#ifndef O_BINARY
#define O_BINARY 0
#endif

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
  if (n == 0) { snprintf(buf, sizeof(buf), "error %lu", (unsigned long)e); return buf; }
  while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r')) buf[--n] = '\0';
  return buf;
}

/* Who does a token say we are?  Used for the readback after impersonating. */
static const char *token_user(HANDLE tok) {
  static char out[256];
  BYTE buf[512];
  DWORD len = 0;
  char name[128], dom[128];
  DWORD nlen = sizeof(name), dlen = sizeof(dom);
  SID_NAME_USE use;

  out[0] = '\0';
  if (!GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &len)) {
    snprintf(out, sizeof(out), "(GetTokenInformation failed: %s)",
             winerr(GetLastError()));
    return out;
  }
  if (!LookupAccountSidA(NULL, ((TOKEN_USER *)buf)->User.Sid,
                         name, &nlen, dom, &dlen, &use)) {
    snprintf(out, sizeof(out), "(LookupAccountSid failed: %s)",
             winerr(GetLastError()));
    return out;
  }
  snprintf(out, sizeof(out), "%s\\%s", dom, name);
  return out;
}

/* The whole measurement, in one place: try to open a path and say plainly what
 * happened.  Returns 1 for opened, 0 for refused. */
static int try_open(const char *what, const char *path) {
  int fd = open(path, O_RDONLY | O_BINARY);
  if (fd >= 0) {
    close(fd);
    say("    %-34s OPENED", what);
    return 1;
  }
  say("    %-34s refused - errno %d (%s)", what, errno, strerror(errno));
  return 0;
}

int main(int argc, char *argv[]) {
  const char *user, *allowed, *forbidden;
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

  if (argc < 4) {
    say("usage: probe-impersonate <user> <allowed-file> <forbidden-file>");
    return 2;
  }
  user = argv[1]; allowed = argv[2]; forbidden = argv[3];

  say("probe-impersonate - does impersonation govern MSYS2 open()?");
  say("PROJECT_STATUS.md section 7 step 14, shape (b)");
  say("");
  /* CLAUDE.md: an instrument shows what it DID.  These are the real inputs. */
  say("INPUTS AS RECEIVED");
  say("  running as      : %s", "(process token below)");
  say("  target user     : %s", user);
  say("  allowed file    : %s", allowed);
  say("  forbidden file  : %s", forbidden);
  {
    HANDLE me;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &me)) {
      say("  process token   : %s", token_user(me));
      CloseHandle(me);
    }
  }
  say("");

  /* ---- control A: as LocalSystem, both must open ---------------------- */
  say("CONTROL A - before impersonating, as this process's own identity");
  a_allowed   = try_open("allowed file", allowed);
  a_forbidden = try_open("forbidden file", forbidden);
  if (!a_allowed || !a_forbidden) {
    say("");
    say("*** VOID: control A did not hold. ***");
    say("    Both files must be openable BEFORE impersonating, or a refusal");
    say("    later says nothing about the thread token.  Fix the paths or the");
    say("    ACLs and run again.  Nothing below is a result.");
    return 3;
  }
  say("  control A holds: this process can open both.");
  say("");

  /* ---- the S4U logon, exactly as probe-s4u.c does it ------------------ */
  say("S4U LOGON for %s", user);
  lsaname.Buffer = (PCHAR)"probe-imp";
  lsaname.Length = (USHORT)strlen(lsaname.Buffer);
  lsaname.MaximumLength = lsaname.Length + 1;

  /* SeTcbPrivilege is the discriminator - probe-s4u.c's finding.  Without a
     TRUSTED LSA connection the token comes back at Identification level and
     cannot be used for anything. */
  st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (st != 0) {
    say("  LsaRegisterLogonProcess refused: NTSTATUS 0x%08lx", (unsigned long)st);
    say("  This must run as LocalSystem.  probe-impersonate.ps1 does that with");
    say("  schtasks /RU SYSTEM; running it by hand as yourself lands here.");
    return 4;
  }
  say("  LsaRegisterLogonProcess: TRUSTED connection");

  pkgname.Buffer = (PCHAR)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(pkgname.Buffer);
  pkgname.MaximumLength = pkgname.Length + 1;
  st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (st != 0) {
    say("  LsaLookupAuthenticationPackage failed: 0x%08lx", (unsigned long)st);
    return 4;
  }

  /* ONE CONTIGUOUS BLOCK, and BOTH strings live in its tail: LSA copies the
     whole buffer into its own process, so a Buffer pointing outside it would
     be a pointer into an address space LSA is not in.  probe-s4u.c:565.

     TWO MISTAKES MADE HERE ON THE FIRST RUN, 23 Aug 2026, both giving a call
     that looks correct:
       - DomainName left empty.  A LOCAL account needs the machine name, and
         without it LsaLogonUser answers STATUS_NOT_SUPPORTED (0xC00000BB).
       - MaximumLength set equal to Length.  Length is in BYTES and EXCLUDES
         the terminator; MaximumLength INCLUDES it.  probe-s4u.c:591 carries
         that warning and this ignored it. */
  if (GetComputerNameA(dom, &domlen) == 0) {
    say("  GetComputerNameA failed: %s", winerr(GetLastError()));
    return 4;
  }
  say("  domain (this machine): %s", dom);

  wuserlen = MultiByteToWideChar(CP_ACP, 0, user, -1, NULL, 0);
  wdomlen  = MultiByteToWideChar(CP_ACP, 0, dom, -1, NULL, 0);
  if (wuserlen <= 0 || wdomlen <= 0) {
    say("  cannot widen the account name: %s", winerr(GetLastError()));
    return 4;
  }

  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) +
                   (size_t)wuserlen * sizeof(WCHAR) +
                   (size_t)wdomlen  * sizeof(WCHAR));
  s4u = (MSV1_0_S4U_LOGON *)calloc(1, s4ulen);
  if (s4u == NULL) { say("  out of memory"); return 4; }

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

  origin.Buffer        = (PCHAR)"probe-imp";
  origin.Length        = (USHORT)strlen(origin.Buffer);
  origin.MaximumLength = (USHORT)(origin.Length + 1);

  memcpy(src.SourceName, "probeimp", 8);
  if (!AllocateLocallyUniqueId(&src.SourceIdentifier)) {
    say("  AllocateLocallyUniqueId failed: %s", winerr(GetLastError()));
    return 4;
  }

  st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen,
                    NULL, &src, &profile, &proflen, &logonid,
                    &tok, &quota, &sub);
  if (st != 0 || tok == NULL) {
    say("  LsaLogonUser failed: 0x%08lx (sub 0x%08lx)",
        (unsigned long)st, (unsigned long)sub);
    return 4;
  }
  say("  token for       : %s", token_user(tok));

  if (GetTokenInformation(tok, TokenImpersonationLevel, &lvl, sizeof(lvl), &got)) {
    say("  impersonation   : %s",
        lvl == SecurityImpersonation ? "Impersonation" :
        lvl == SecurityIdentification ? "Identification" : "other");
    if (lvl != SecurityImpersonation) {
      say("");
      say("*** VOID: the token is not at Impersonation level. ***");
      say("    ImpersonateLoggedOnUser would succeed and change nothing.");
      return 3;
    }
  }
  say("");

  /* ---- the measurement ------------------------------------------------ */
  say("MEASUREMENT - while impersonating %s", user);
  if (!ImpersonateLoggedOnUser(tok)) {
    say("  ImpersonateLoggedOnUser failed: %s", winerr(GetLastError()));
    return 4;
  }

  /* Readback, not a return code.  probe-s4u.c's convention. */
  if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &thread_tok)) {
    say("  thread token now: %s   <- readback, not a return code", token_user(thread_tok));
    CloseHandle(thread_tok);
  } else {
    say("  OpenThreadToken failed: %s", winerr(GetLastError()));
  }

  m_allowed   = try_open("allowed file", allowed);
  m_forbidden = try_open("forbidden file", forbidden);

  RevertToSelf();
  say("");

  /* ---- control B: the denial must be undoable -------------------------- */
  say("CONTROL B - after RevertToSelf");
  b_forbidden = try_open("forbidden file", forbidden);
  if (!b_forbidden) {
    say("");
    say("*** VOID: control B did not hold. ***");
    say("    The forbidden file did not open again after reverting, so the");
    say("    refusal above may have been a lock or a bad path rather than the");
    say("    thread token.  Nothing here is a result.");
    return 3;
  }
  say("  control B holds: reverting restored access.");
  say("");

  /* ---- verdict --------------------------------------------------------- */
  say("VERDICT");
  say("  allowed file while impersonating   : %s", m_allowed ? "opened" : "REFUSED");
  say("  forbidden file while impersonating : %s", m_forbidden ? "OPENED" : "refused");
  say("");
  if (!m_forbidden && m_allowed) {
    say("  IMPERSONATION GOVERNS open().  Shape (b) is viable: the runtime");
    say("  honours the thread token, so a session that impersonates after SCRAM");
    say("  opens account files as the user.");
    return 0;
  }
  if (m_forbidden) {
    say("  IMPERSONATION DOES NOT GOVERN open().  The MSYS2 runtime opened a");
    say("  file the impersonated user may not read, so it is deciding access");
    say("  from something other than the thread token.  Shape (b) as written");
    say("  buys nothing.  Try cygwin_internal(CW_SET_EXTERNAL_TOKEN) next, and");
    say("  if that fails too, shape (a) is the only one left.");
    return 1;
  }
  say("  INCONCLUSIVE: the allowed file was refused too, so the target user may");
  say("  simply have no access to either path.  Check the ACLs.");
  return 3;
}

/* END-CODE */
