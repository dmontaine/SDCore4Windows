/* probe-s4u.c - can a passwordless S4U logon produce a token that
 *               CreateProcessAsUser will actually accept?
 *
 * 23 Aug 26 Windows port.  Built and run by probe-s4u.ps1.  It is an
 * INSTRUMENT, not a verifier: there is nothing here to pass or fail, and a
 * person reads what it prints.  probe-keys.ps1 and probe-console.c are the
 * same shape and say why that distinction matters.
 *
 * ---------------------------------------------------------------------------
 * WHAT IT DECIDES.  PROJECT_STATUS.md section 7 step 14, shape (b) - "let the
 * session take the token after it authenticates".  That step says:
 *
 *     SCRAM means the server never holds the password, so LogonUser is not
 *     available; only S4U, which yields an *identification*-level token
 *     unless the service holds TCB or the account is trusted for delegation -
 *     and an identification token cannot be passed to CreateProcessAsUser.
 *     Check that before choosing it; a probe would answer it in one run.
 *
 * This is that probe.  The whole of shape (b) rests on a token this process
 * can obtain WITHOUT a password, and everything downstream - step 14, and
 * step 15's private data tree, which needs CreateProcessAsUser at the session
 * sites - is a different design depending on the answer.
 *
 * Reasoning cannot settle it.  The documentation says "identification level"
 * for an untrusted LSA caller and "impersonation level" for a caller holding
 * SeTcbPrivilege, and sdwind runs as LocalSystem, which HAS SeTcbPrivilege -
 * so the paper answer is that it works.  Paper answers about tokens are how
 * step 13 leg 1 shipped a cleartext password prompt.
 *
 * ---------------------------------------------------------------------------
 * IT MUST BE RUN TWICE, AND THE SECOND RUN IS THE ONE THAT COUNTS.
 *
 * The question is what the SERVICE can do, and the service is LocalSystem.
 * A run from an ordinary elevated administrator is NOT the same measurement:
 * an elevated admin does not hold SeTcbPrivilege, so it gets the untrusted
 * LSA connection and the identification-level token - the failing half.
 *
 * probe-s4u.ps1 runs both and prints them side by side, because a success
 * with no failing control beside it proves nothing about the mechanism: it
 * would look identical if S4U were irrelevant and every token worked.  The
 * pair is what shows WHY it works, which is the part a design decision needs.
 *
 * ---------------------------------------------------------------------------
 * THE INTERNAL CONTROL, AND IT IS HERE FOR probe-console.c's REASON.
 *
 * That probe's first version answered YES on a run where the deciding read
 * had failed, because all it compared was state a failed read cannot disturb.
 * So nothing here is believed on a return code alone:
 *
 *   - the S4U token's user is read back and NAMED, so "we got a token" cannot
 *     pass for "we got the target's token" - a caller's own token would
 *     satisfy every check below and answer the wrong question;
 *   - CreateProcessAsUser is not believed when it returns TRUE.  The child is
 *     whoami.exe and its OUTPUT is read back, so the reading is who the child
 *     actually was, not who we asked for; and
 *   - step 7 is a NEGATIVE control: the same token deliberately duplicated
 *     DOWN to identification level, put through the same call.  If that
 *     succeeds too, then step 6 proved nothing about impersonation level and
 *     this probe says so instead of claiming the win.
 *
 * ---------------------------------------------------------------------------
 * BUILT WITH THE MSYS2 COMPILER ON PURPOSE, like probe-console.c.  sd.exe and
 * sdwind are built against the MSYS2 POSIX runtime (5.3, 5.4), and a token is
 * a property of the process that holds it, so measuring this from a native
 * UCRT64 binary would measure a process SD is not.  Under Cygwin a process
 * still holds an ordinary Windows token and these are ordinary Win32 calls;
 * that is the assumption, and building it this way is what tests it.
 *
 * NOT INSTALLED AND NOT SHIPPED - it is on assert-current.ps1's $neverShipped
 * list, with its runner and its build product, or it reports the tree stale
 * because it exists.
 */

#define _WIN32_WINNT 0x0A00
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <ntsecapi.h>
#include <sddl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* LsaLogonUser's origin string and our token source name.  TOKEN_SOURCE_LENGTH
   is 8 and SourceName is not NUL-terminated by contract, so "SDPROBE" plus its
   terminator is exactly the field width - memcpy of 8, not strncpy, because
   -Wstringop-truncation is right to complain about the latter. */
#define PROBE_ORIGIN "SDProbe"
#define PROBE_SOURCE "SDPROBE"

static int failures = 0;   /* steps that did not do what was asked of them */

/* ------------------------------------------------------------------ */
/* Reporting                                                          */
/* ------------------------------------------------------------------ */

static void step(const char *fmt, ...) {
  va_list ap;
  printf("\n");
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
  printf("\n");
}

/* FormatMessage for a Win32 error, trimmed.  Static buffer: this is a
   single-threaded instrument that prints one message at a time. */
static const char *winerr(DWORD e) {
  static char buf[512];
  char *p;
  DWORD n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
                               FORMAT_MESSAGE_IGNORE_INSERTS,
                           NULL, e, 0, buf, sizeof(buf) - 1, NULL);
  if (n == 0) {
    snprintf(buf, sizeof(buf), "(no text for error %lu)", (unsigned long)e);
    return buf;
  }
  buf[n] = '\0';
  for (p = buf + strlen(buf); p > buf && (p[-1] == '\r' || p[-1] == '\n' ||
                                          p[-1] == '.' || p[-1] == ' '); p--)
    p[-1] = '\0';
  return buf;
}

/* An NTSTATUS from LSA is not a Win32 error; LsaNtStatusToWinError converts
   it.  Printing the raw NTSTATUS as well because the converted form loses
   detail - STATUS_NO_SUCH_USER and STATUS_ACCOUNT_DISABLED both become
   ERROR_NO_SUCH_USER-ish text and the distinction matters when this fails. */
static void report_nt(const char *what, NTSTATUS st, NTSTATUS sub) {
  DWORD e = LsaNtStatusToWinError((ULONG)st);
  printf("  %s: NTSTATUS 0x%08lx -> %s\n", what, (unsigned long)st, winerr(e));
  if (sub != 0)
    printf("    substatus 0x%08lx -> %s\n", (unsigned long)sub,
           winerr(LsaNtStatusToWinError((ULONG)sub)));
}

/* ------------------------------------------------------------------ */
/* Token reading                                                      */
/* ------------------------------------------------------------------ */

/* Name a SID as DOMAIN\user.  Returns a static buffer; on failure it prints
   the SID in string form instead, because an unnameable SID is still evidence
   (a deleted account, or a logon SID) and "unknown" is not. */
static const char *sid_name(PSID sid) {
  static char out[512];
  char name[256], dom[256];
  DWORD nlen = sizeof(name), dlen = sizeof(dom);
  SID_NAME_USE use;

  if (LookupAccountSidA(NULL, sid, name, &nlen, dom, &dlen, &use)) {
    snprintf(out, sizeof(out), "%s\\%s", dom, name);
  } else {
    LPSTR s = NULL;
    if (ConvertSidToStringSidA(sid, &s) && s != NULL) {
      snprintf(out, sizeof(out), "%s (unnameable)", s);
      LocalFree(s);
    } else {
      snprintf(out, sizeof(out), "(a SID that could not be read)");
    }
  }
  return out;
}

/* The token's user, named.  This is the check that stops "we got a token"
   passing for "we got the TARGET's token". */
static const char *token_user(HANDLE tok) {
  static char out[512];
  DWORD len = 0;
  TOKEN_USER *tu;

  GetTokenInformation(tok, TokenUser, NULL, 0, &len);
  if (len == 0) {
    snprintf(out, sizeof(out), "(TokenUser unreadable: %s)",
             winerr(GetLastError()));
    return out;
  }
  tu = (TOKEN_USER *)malloc(len);
  if (tu == NULL) return "(out of memory)";
  if (!GetTokenInformation(tok, TokenUser, tu, len, &len)) {
    snprintf(out, sizeof(out), "(TokenUser unreadable: %s)",
             winerr(GetLastError()));
    free(tu);
    return out;
  }
  snprintf(out, sizeof(out), "%s", sid_name(tu->User.Sid));
  free(tu);
  return out;
}

static const char *level_name(SECURITY_IMPERSONATION_LEVEL l) {
  switch (l) {
    case SecurityAnonymous:      return "Anonymous";
    case SecurityIdentification: return "Identification";
    case SecurityImpersonation:  return "Impersonation";
    case SecurityDelegation:     return "Delegation";
    default:                     return "(unrecognised)";
  }
}

/* Type and, for an impersonation token, level.  TokenImpersonationLevel is
   only meaningful when TokenType is TokenImpersonation - asking a primary
   token gives a value that means nothing, which is worth not printing. */
static void describe_token(HANDLE tok, const char *what) {
  TOKEN_TYPE tt = 0;
  SECURITY_IMPERSONATION_LEVEL sil = 0;
  DWORD len = 0;

  if (!GetTokenInformation(tok, TokenType, &tt, sizeof(tt), &len)) {
    printf("  %s: TokenType unreadable: %s\n", what, winerr(GetLastError()));
    return;
  }
  if (tt == TokenPrimary) {
    printf("  %s: PRIMARY token, user %s\n", what, token_user(tok));
    return;
  }
  if (!GetTokenInformation(tok, TokenImpersonationLevel, &sil, sizeof(sil),
                           &len)) {
    printf("  %s: impersonation token, level unreadable: %s\n", what,
           winerr(GetLastError()));
    return;
  }
  printf("  %s: IMPERSONATION token at %s level, user %s\n", what,
         level_name(sil), token_user(tok));
}

/* Is a named privilege in this process's token, and is it enabled?  The
   answer is the mechanism behind everything below: SeTcbPrivilege decides
   whether LSA will take us as a trusted logon process, and without that the
   S4U token comes back at identification level. */
static void report_privilege(const char *priv) {
  HANDLE tok = NULL;
  LUID luid;
  PRIVILEGE_SET set;
  BOOL held = FALSE;
  DWORD len = 0;
  TOKEN_PRIVILEGES *tp;
  DWORD i;
  const char *state = "absent";

  if (!LookupPrivilegeValueA(NULL, priv, &luid)) {
    printf("  %-28s (name not recognised here)\n", priv);
    return;
  }
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
    printf("  %-28s (process token unreadable)\n", priv);
    return;
  }

  set.PrivilegeCount = 1;
  set.Control = PRIVILEGE_SET_ALL_NECESSARY;
  set.Privilege[0].Luid = luid;
  set.Privilege[0].Attributes = 0;
  if (PrivilegeCheck(tok, &set, &held) && held) {
    state = "held and ENABLED";
  } else {
    /* PrivilegeCheck answers "enabled", not "present".  A privilege that is
       present but disabled can still be enabled by its holder, so the two
       are different answers and the distinction decides whether a failure
       here is fatal or merely needs AdjustTokenPrivileges. */
    GetTokenInformation(tok, TokenPrivileges, NULL, 0, &len);
    if (len > 0 && (tp = (TOKEN_PRIVILEGES *)malloc(len)) != NULL) {
      if (GetTokenInformation(tok, TokenPrivileges, tp, len, &len)) {
        for (i = 0; i < tp->PrivilegeCount; i++) {
          if (tp->Privileges[i].Luid.LowPart == luid.LowPart &&
              tp->Privileges[i].Luid.HighPart == luid.HighPart) {
            state = "held but DISABLED";
            break;
          }
        }
      }
      free(tp);
    }
  }
  printf("  %-28s %s\n", priv, state);
  CloseHandle(tok);
}

/* ------------------------------------------------------------------ */
/* Step 6 and 7: does CreateProcessAsUser take this token?            */
/* ------------------------------------------------------------------ */

/* Run whoami.exe under `tok` and return what it printed, or NULL.
 *
 * THE CHILD'S OUTPUT IS THE READING, not CreateProcessAsUser's return value.
 * A TRUE from that call says a process started; it does not say whose token
 * it started with, and the difference is the entire question.  whoami is the
 * shortest program that answers it and it is in System32 on every install.
 *
 * The output file is opened HERE and INHERITED, deliberately: access to a
 * file is checked when it is opened, so the child writes through a handle it
 * could not have opened itself.  Otherwise this would also be measuring
 * whether an S4U-logged-on user can write to the temp directory, which is a
 * different question that would fail for its own reasons.
 */
static char *run_whoami_as(HANDLE tok, const char *desktop, DWORD *lasterr) {
  char sysdir[MAX_PATH], cmd[MAX_PATH + 32], tmpdir[MAX_PATH], tmpfile[MAX_PATH];
  SECURITY_ATTRIBUTES sa;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  HANDLE hout = INVALID_HANDLE_VALUE, hin = INVALID_HANDLE_VALUE;
  char *text = NULL;
  DWORD got = 0, size;
  BOOL ok;

  *lasterr = 0;

  if (GetSystemDirectoryA(sysdir, sizeof(sysdir)) == 0) return NULL;
  snprintf(cmd, sizeof(cmd), "%s\\whoami.exe", sysdir);

  if (GetTempPathA(sizeof(tmpdir), tmpdir) == 0) return NULL;
  if (GetTempFileNameA(tmpdir, "s4u", 0, tmpfile) == 0) return NULL;

  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = NULL;
  sa.bInheritHandle = TRUE;

  hout = CreateFileA(tmpfile, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                     &sa, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
  if (hout == INVALID_HANDLE_VALUE) {
    *lasterr = GetLastError();
    DeleteFileA(tmpfile);
    return NULL;
  }
  /* A NULL stdin is not the same as no stdin; give the child NUL so that a
     failure here can never be blamed on a handle it was not given. */
  hin = CreateFileA("NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    &sa, OPEN_EXISTING, 0, NULL);

  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = hin;
  si.hStdOutput = hout;
  si.hStdError = hout;
  si.lpDesktop = (LPSTR)desktop;   /* NULL, or "winsta0\\default" */
  ZeroMemory(&pi, sizeof(pi));

  ok = CreateProcessAsUserA(tok, cmd, NULL, NULL, NULL, TRUE,
                            CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
  if (!ok) {
    *lasterr = GetLastError();
    CloseHandle(hout);
    if (hin != INVALID_HANDLE_VALUE) CloseHandle(hin);
    DeleteFileA(tmpfile);
    return NULL;
  }

  WaitForSingleObject(pi.hProcess, 15000);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  CloseHandle(hout);
  if (hin != INVALID_HANDLE_VALUE) CloseHandle(hin);

  hout = CreateFileA(tmpfile, GENERIC_READ, FILE_SHARE_READ, NULL,
                     OPEN_EXISTING, 0, NULL);
  if (hout != INVALID_HANDLE_VALUE) {
    size = GetFileSize(hout, NULL);
    if (size != INVALID_FILE_SIZE && size < 4096) {
      text = (char *)malloc(size + 1);
      if (text != NULL) {
        if (ReadFile(hout, text, size, &got, NULL)) {
          text[got] = '\0';
          while (got > 0 && (text[got - 1] == '\r' || text[got - 1] == '\n'))
            text[--got] = '\0';
        } else {
          free(text);
          text = NULL;
        }
      }
    }
    CloseHandle(hout);
  }
  DeleteFileA(tmpfile);

  /* A child that ran and printed nothing is not a success.  Say so by
     returning NULL with no error, which the caller distinguishes. */
  if (text != NULL && text[0] == '\0') {
    free(text);
    text = NULL;
  }
  return text;
}

/* Try the spawn twice: with a desktop and without.
 *
 * WHY BOTH.  An S4U logon is a NETWORK logon; the resulting user has no
 * interactive rights, so naming winsta0\default can be refused for a reason
 * that has nothing to do with impersonation level - which is the failure this
 * probe would otherwise misread as its answer.  Passing NULL inherits this
 * process's desktop instead.  Trying both and printing which one carried
 * keeps that confusion out of the verdict.
 */
static int spawn_and_report(HANDLE tok, const char *what) {
  DWORD err = 0;
  char *who;

  who = run_whoami_as(tok, "winsta0\\default", &err);
  if (who != NULL) {
    printf("  %s: CreateProcessAsUser SUCCEEDED (lpDesktop winsta0\\default)\n",
           what);
    printf("    the child reported itself as: %s\n", who);
    free(who);
    return 1;
  }
  if (err != 0)
    printf("  %s: refused with winsta0\\default - %s (%lu)\n", what,
           winerr(err), (unsigned long)err);
  else
    printf("  %s: ran with winsta0\\default but printed nothing\n", what);

  who = run_whoami_as(tok, NULL, &err);
  if (who != NULL) {
    printf("  %s: CreateProcessAsUser SUCCEEDED (lpDesktop NULL - inherited)\n",
           what);
    printf("    the child reported itself as: %s\n", who);
    free(who);
    return 1;
  }
  if (err != 0)
    printf("  %s: refused with lpDesktop NULL - %s (%lu)\n", what,
           winerr(err), (unsigned long)err);
  else
    printf("  %s: ran with lpDesktop NULL but printed nothing\n", what);

  return 0;
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

int main(int argc, char *argv[]) {
  char account[256], domain[256];
  char me[256];
  DWORD melen = sizeof(me);
  const char *sep;

  LSA_STRING lsaname, origin, pkgname;
  LSA_OPERATIONAL_MODE mode = 0;
  HANDLE hlsa = NULL;
  int trusted = 0;
  ULONG pkg = 0;
  NTSTATUS st, sub = 0;

  MSV1_0_S4U_LOGON *s4u = NULL;
  ULONG s4ulen;
  WCHAR *wuser, *wdom;
  int wuserlen, wdomlen;
  BYTE *tail;

  TOKEN_SOURCE source;
  void *profile = NULL;
  ULONG profilelen = 0;
  LUID logonid;
  QUOTA_LIMITS quotas;
  HANDLE s4utoken = NULL, primary = NULL, ident = NULL, identprim = NULL;

  int attached = 0, acted = 0, spawned = 0, control_spawned = 0;
  TOKEN_TYPE tt = 0;
  SECURITY_IMPERSONATION_LEVEL sil = 0;
  DWORD len = 0;

  setvbuf(stdout, NULL, _IONBF, 0);   /* the runner reads this through a file */

  printf("probe-s4u - PROJECT_STATUS.md section 7 step 14, shape (b)\n");
  printf("Can a passwordless S4U logon give a token CreateProcessAsUser takes?\n");

  /* ---------------------------------------------------------------- */
  /* The target account.  Default to whoever is running this, which is */
  /* the only account we can be sure exists and is not disabled.       */
  /* ---------------------------------------------------------------- */
  if (argc > 1 && argv[1][0] != '\0') {
    snprintf(account, sizeof(account), "%s", argv[1]);
  } else {
    if (!GetUserNameA(me, &melen)) {
      printf("\nCannot read the current user name: %s\n",
             winerr(GetLastError()));
      return 2;
    }
    snprintf(account, sizeof(account), "%s", me);
  }

  /* DOMAIN\user splits; a bare name is a local account, whose "domain" is
     this computer's own name.  "." does not work here - MSV1_0 wants the
     name, not the shorthand a connection string would take. */
  sep = strchr(account, '\\');
  if (sep != NULL) {
    size_t dlen = (size_t)(sep - account);
    if (dlen >= sizeof(domain)) dlen = sizeof(domain) - 1;
    memcpy(domain, account, dlen);
    domain[dlen] = '\0';
    memmove(account, sep + 1, strlen(sep + 1) + 1);
  } else {
    DWORD dl = sizeof(domain);
    if (!GetComputerNameA(domain, &dl)) {
      printf("\nCannot read this computer's name: %s\n",
             winerr(GetLastError()));
      return 2;
    }
  }
  printf("Target account: %s\\%s\n", domain, account);

  /* ---------------------------------------------------------------- */
  step("STEP 1 - who is asking, and with what privileges");
  {
    HANDLE self = NULL;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &self)) {
      printf("  running as: %s\n", token_user(self));
      CloseHandle(self);
    } else {
      printf("  running as: (own token unreadable: %s)\n",
             winerr(GetLastError()));
    }
  }
  /* SeTcbPrivilege is the one that decides this whole probe; the other two
     are what CreateProcessAsUser itself requires, and reporting them here
     means a later refusal can be attributed rather than guessed at. */
  report_privilege(SE_TCB_NAME);
  report_privilege(SE_ASSIGNPRIMARYTOKEN_NAME);
  report_privilege(SE_INCREASE_QUOTA_NAME);
  report_privilege(SE_IMPERSONATE_NAME);

  /* ---------------------------------------------------------------- */
  step("STEP 2 - connect to LSA, trusted if we are allowed to be");
  /*
   * LsaRegisterLogonProcess needs SeTcbPrivilege and gives a TRUSTED
   * connection; LsaConnectUntrusted needs nothing and gives an untrusted one.
   * WHICH ONE CARRIES IS THE MECHANISM: an untrusted caller's S4U token comes
   * back at identification level, and that is the case step 14 warns about.
   * So this deliberately tries the trusted route first and REPORTS the fall
   * back rather than quietly taking it.
   */
  lsaname.Buffer = (PCHAR)PROBE_ORIGIN;
  lsaname.Length = (USHORT)strlen(PROBE_ORIGIN);
  lsaname.MaximumLength = (USHORT)(strlen(PROBE_ORIGIN) + 1);

  st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (st == 0) {
    trusted = 1;
    printf("  LsaRegisterLogonProcess succeeded - TRUSTED connection\n");
  } else {
    report_nt("LsaRegisterLogonProcess refused", st, 0);
    st = LsaConnectUntrusted(&hlsa);
    if (st != 0) {
      report_nt("LsaConnectUntrusted also failed", st, 0);
      printf("\nCannot reach LSA at all; nothing below can be measured.\n");
      return 2;
    }
    printf("  fell back to LsaConnectUntrusted - UNTRUSTED connection\n");
  }

  /* ---------------------------------------------------------------- */
  step("STEP 3 - S4U logon for %s\\%s, with no password", domain, account);

  pkgname.Buffer = (PCHAR)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(MSV1_0_PACKAGE_NAME);
  pkgname.MaximumLength = (USHORT)(strlen(MSV1_0_PACKAGE_NAME) + 1);
  st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (st != 0) {
    report_nt("LsaLookupAuthenticationPackage failed", st, 0);
    return 2;
  }

  /* MSV1_0_S4U_LOGON must be ONE contiguous block: LSA copies the whole
     buffer across into its own process, and UNICODE_STRING.Buffer pointers
     that point outside it would be pointers into an address space LSA is not
     in.  So the two strings live in the tail of the same allocation. */
  wuserlen = MultiByteToWideChar(CP_ACP, 0, account, -1, NULL, 0);
  wdomlen  = MultiByteToWideChar(CP_ACP, 0, domain, -1, NULL, 0);
  if (wuserlen <= 0 || wdomlen <= 0) {
    printf("  cannot widen the account name: %s\n", winerr(GetLastError()));
    return 2;
  }
  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) +
                   (size_t)wuserlen * sizeof(WCHAR) +
                   (size_t)wdomlen * sizeof(WCHAR));
  s4u = (MSV1_0_S4U_LOGON *)calloc(1, s4ulen);
  if (s4u == NULL) {
    printf("  out of memory\n");
    return 2;
  }
  tail = (BYTE *)s4u + sizeof(MSV1_0_S4U_LOGON);
  wuser = (WCHAR *)tail;
  wdom  = (WCHAR *)(tail + (size_t)wuserlen * sizeof(WCHAR));
  MultiByteToWideChar(CP_ACP, 0, account, -1, wuser, wuserlen);
  MultiByteToWideChar(CP_ACP, 0, domain, -1, wdom, wdomlen);

  s4u->MessageType = MsV1_0S4ULogon;
  s4u->Flags = 0;
  /* Length is in BYTES and excludes the terminator; MaximumLength includes
     it.  Getting this wrong gives STATUS_INVALID_PARAMETER from a call that
     looks correct. */
  s4u->UserPrincipalName.Length        = (USHORT)((wuserlen - 1) * sizeof(WCHAR));
  s4u->UserPrincipalName.MaximumLength = (USHORT)(wuserlen * sizeof(WCHAR));
  s4u->UserPrincipalName.Buffer        = wuser;
  s4u->DomainName.Length               = (USHORT)((wdomlen - 1) * sizeof(WCHAR));
  s4u->DomainName.MaximumLength        = (USHORT)(wdomlen * sizeof(WCHAR));
  s4u->DomainName.Buffer               = wdom;

  origin.Buffer = (PCHAR)PROBE_ORIGIN;
  origin.Length = (USHORT)strlen(PROBE_ORIGIN);
  origin.MaximumLength = (USHORT)(strlen(PROBE_ORIGIN) + 1);

  memcpy(source.SourceName, PROBE_SOURCE, sizeof(source.SourceName));
  if (!AllocateLocallyUniqueId(&source.SourceIdentifier)) {
    printf("  AllocateLocallyUniqueId failed: %s\n", winerr(GetLastError()));
    return 2;
  }

  st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen, NULL, &source,
                    &profile, &profilelen, &logonid, &s4utoken, &quotas, &sub);
  if (st != 0 || s4utoken == NULL) {
    report_nt("LsaLogonUser failed", st, sub);
    printf("\n  Nothing below can be measured without a token.  If this is\n");
    printf("  STATUS_NO_SUCH_USER the target name is wrong; if it is\n");
    printf("  STATUS_ACCOUNT_RESTRICTION the account exists but is refused.\n");
    if (hlsa != NULL) { if (trusted) LsaDeregisterLogonProcess(hlsa); else LsaClose(hlsa); }
    return 2;
  }
  printf("  LsaLogonUser SUCCEEDED - no password was supplied or held\n");
  printf("  logon session LUID: 0x%08lx%08lx\n",
         (unsigned long)logonid.HighPart, (unsigned long)logonid.LowPart);
  if (profile != NULL) LsaFreeReturnBuffer(profile);

  /* ---------------------------------------------------------------- */
  step("STEP 4 - what came back, and whose it is");
  describe_token(s4utoken, "S4U token");
  GetTokenInformation(s4utoken, TokenType, &tt, sizeof(tt), &len);
  if (tt == TokenImpersonation)
    GetTokenInformation(s4utoken, TokenImpersonationLevel, &sil, sizeof(sil),
                        &len);
  printf("\n  THIS IS THE READING step 14 ASKED FOR.  Identification level\n");
  printf("  means the token can be interrogated but not acted with; anything\n");
  printf("  above it can be acted with.\n");

  /* ---------------------------------------------------------------- */
  step("STEP 5 - shape (b) in its cheapest form: impersonate in-process");
  /*
   * Step 14 shape (b) is "let the session take the token after it
   * authenticates".  If ImpersonateLoggedOnUser works then the session does
   * not need to be re-spawned at all - it changes its own thread token after
   * SCRAM, which is a much smaller change than either shape as written.  So
   * this is measured even though the step does not name it.
   */
  if (ImpersonateLoggedOnUser(s4utoken)) {
    char who[256], witness[MAX_PATH];
    DWORD wl = sizeof(who);
    HANDLE thr = NULL, f;
    SECURITY_IMPERSONATION_LEVEL tl = 0;
    DWORD tlen = 0;
    const char *root = getenv("SystemRoot");

    attached = 1;
    if (GetUserNameA(who, &wl))
      printf("  attached; GetUserName now reads: %s\n", who);
    else
      printf("  attached, but GetUserName failed: %s\n",
             winerr(GetLastError()));

    /* What level actually landed on the THREAD, which is not necessarily the
       level of the token handed in.  bOpenAsSelf is TRUE so that reading it
       is not itself done under the token being read. */
    if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &thr)) {
      if (GetTokenInformation(thr, TokenImpersonationLevel, &tl, sizeof(tl),
                              &tlen))
        printf("  the thread token is at %s level\n", level_name(tl));
      CloseHandle(thr);
    }

    /* THE DECIDING READ, and step 5 is worthless without it.
     *
     * GetUserName above is NOT evidence that this impersonation can do
     * anything: it reads identity, and reading identity is the one thing an
     * identification-level token IS for.  Worse, when the target account is
     * also the caller it returns the same name either way - which is exactly
     * the mistake this file's header describes, made again one step down.
     *
     * So: open a securable object.  An identification-level thread token
     * cannot, and is refused with ERROR_BAD_IMPERSONATION_LEVEL (1346),
     * which is distinctive enough to name the cause rather than guess it.
     * hosts is chosen because it is on every Windows install and readable by
     * Users, so a refusal cannot be the file's own ACL.
     *
     * WHAT THIS DOES NOT SHOW: that the open happened as the TARGET rather
     * than as us.  A world-readable file cannot distinguish those.  Identity
     * is established by step 4's token user and step 6's child; this step
     * answers only "can it act at all" - deliberately, because a per-account
     * path would make the probe depend on an install existing.
     */
    snprintf(witness, sizeof(witness), "%s\\System32\\drivers\\etc\\hosts",
             root != NULL ? root : "C:\\Windows");
    f = CreateFileA(witness, GENERIC_READ,
                    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                    NULL, OPEN_EXISTING, 0, NULL);
    if (f != INVALID_HANDLE_VALUE) {
      printf("  and it can ACT: opened %s while impersonating\n", witness);
      CloseHandle(f);
      acted = 1;
    } else {
      DWORD e = GetLastError();
      printf("  but it CANNOT ACT: opening %s gave %s (%lu)\n", witness,
             winerr(e), (unsigned long)e);
      if (e == ERROR_BAD_IMPERSONATION_LEVEL)
        printf("    which is the identification-level refusal, by name.\n");
    }
    RevertToSelf();
  } else {
    printf("  ImpersonateLoggedOnUser refused: %s\n", winerr(GetLastError()));
  }

  /* ---------------------------------------------------------------- */
  step("STEP 6 - the deciding call: CreateProcessAsUser with this token");
  /*
   * CreateProcessAsUser needs a PRIMARY token and LsaLogonUser returns an
   * impersonation one, so the duplicate is required and is not a workaround.
   * If the source token is identification level the duplicate still succeeds
   * - that is why the failure lands on CreateProcessAsUser and not here.
   */
  if (!DuplicateTokenEx(s4utoken, MAXIMUM_ALLOWED, NULL, SecurityImpersonation,
                        TokenPrimary, &primary)) {
    printf("  DuplicateTokenEx to a primary token failed: %s\n",
           winerr(GetLastError()));
    failures++;
  } else {
    describe_token(primary, "duplicated");
    spawned = spawn_and_report(primary, "primary");
    if (!spawned) failures++;
  }

  /* ---------------------------------------------------------------- */
  step("STEP 7 - THE NEGATIVE CONTROL: the same token at identification level");
  /*
   * Without this, a success in step 6 says only "this token worked".  It does
   * not say that impersonation level is what made the difference, and if it
   * is not, then everything step 14 concluded about identification tokens is
   * still unmeasured.  So: duplicate DOWN to identification level, make the
   * same call, and expect a refusal.  A success here is the interesting
   * result, and it would mean step 6 proved nothing.
   */
  if (!DuplicateTokenEx(s4utoken, MAXIMUM_ALLOWED, NULL, SecurityIdentification,
                        TokenImpersonation, &ident)) {
    printf("  could not make an identification-level token: %s\n",
           winerr(GetLastError()));
    printf("  the control could not be run; step 6 stands alone.\n");
  } else if (!DuplicateTokenEx(ident, MAXIMUM_ALLOWED, NULL,
                               SecurityIdentification, TokenPrimary,
                               &identprim)) {
    printf("  could not make it primary: %s\n", winerr(GetLastError()));
    printf("  the control could not be run; step 6 stands alone.\n");
  } else {
    describe_token(ident, "control source");
    control_spawned = spawn_and_report(identprim, "identification");
    if (control_spawned)
      printf("  ^ THIS IS THE UNEXPECTED RESULT.  See the verdict.\n");
  }

  /* ---------------------------------------------------------------- */
  step("VERDICT");
  printf("  LSA connection ....... %s\n", trusted ? "TRUSTED (SeTcbPrivilege)"
                                                  : "UNTRUSTED");
  printf("  S4U token level ...... %s\n",
         tt == TokenPrimary ? "primary" : level_name(sil));
  /* Two lines, not one: a token that ATTACHES but cannot open anything is
     the identification-level case, and collapsing the two would report it as
     a working impersonation - which is the claim step 14 is trying to
     settle. */
  printf("  impersonation attach . %s\n", attached ? "works" : "refused");
  printf("  and it could ACT ..... %s\n", acted ? "YES" : "NO");
  printf("  CreateProcessAsUser .. %s\n", spawned ? "WORKS" : "REFUSED");
  printf("  identification ctrl .. %s\n",
         control_spawned ? "ALSO WORKED - see below" : "refused, as expected");

  printf("\n");
  if (spawned && !control_spawned) {
    printf("  SHAPE (b) IS AVAILABLE FROM THIS IDENTITY, and the control\n");
    printf("  shows why: the same token at identification level is refused,\n");
    printf("  so it is the level that carried it and not something else.\n");
  } else if (spawned && control_spawned) {
    printf("  BOTH WORKED, WHICH MAKES STEP 6 UNDECISIVE.  If an\n");
    printf("  identification token is accepted here then the refusal step 14\n");
    printf("  expects is not happening on this system, and the reason needs\n");
    printf("  finding before either shape is chosen.\n");
  } else if (!spawned && acted) {
    printf("  CreateProcessAsUser IS REFUSED, BUT IMPERSONATION CAN ACT.\n");
    printf("  That is shape (b) without a re-spawn - the session changes its\n");
    printf("  own thread token after SCRAM.  Note what it does NOT cover:\n");
    printf("  files already open, and any thread that did not impersonate.\n");
  } else if (!spawned && attached) {
    printf("  NOTHING IS AVAILABLE FROM THIS IDENTITY.  The token attached to\n");
    printf("  the thread but could not open a world-readable file, which is\n");
    printf("  identification level doing exactly what it is for: it answers\n");
    printf("  WHO, and refuses to act.  If this run was not LocalSystem it is\n");
    printf("  the expected half of the pair; read the LocalSystem run.\n");
  } else {
    printf("  NEITHER WORKED FROM THIS IDENTITY.  If this run was not\n");
    printf("  LocalSystem it is the expected half of the pair and says\n");
    printf("  nothing about the service; read the LocalSystem run.\n");
  }

  if (identprim != NULL) CloseHandle(identprim);
  if (ident != NULL) CloseHandle(ident);
  if (primary != NULL) CloseHandle(primary);
  CloseHandle(s4utoken);
  free(s4u);
  if (trusted) LsaDeregisterLogonProcess(hlsa); else LsaClose(hlsa);

  /* Exit 0 means THE PROBE RAN, not that the answer was yes.  It is an
     instrument; a person reads the verdict.  2 is reserved for "could not be
     set up", which is the only outcome that makes the printout worthless. */
  (void)failures;
  return 0;
}
