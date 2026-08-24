/* win32s4u.c - take on an SD user's Windows identity without their password.
 *
 * START-HISTORY:
 * 23 Aug 26 Windows port - written.  PROJECT_STATUS.md section 7 step 14,
 *           shape (b): the API session authenticates with SCRAM in APISRVR and
 *           THEN becomes the user, rather than being spawned as them.
 * 24 Aug 26 Windows port - the identity did not survive the session's first
 *           fork().  ImpersonateLoggedOnUser alone is per-THREAD and Cygwin's
 *           fork() silently reverts the thread, so the LOGTO group check
 *           (APISRVR:566 -> op_sh.c:379) dropped it back to LocalSystem and
 *           every later write was SYSTEM's.  The runtime is now told to carry
 *           the token itself.  See "ADOPTING IT INTO THE RUNTIME" below.
 * END-HISTORY
 *
 * WHY THIS EXISTS.  sdwind.c:491 fork()s the session, so it inherits the
 * service's LocalSystem token and every file it opens is opened by LocalSystem.
 * It cannot be fixed at the fork: SCRAM runs in the child, after the execl, so
 * at spawn time sdwind does not yet know who the caller is.
 *
 * WHY S4U AND NOT LogonUser.  SCRAM means the server NEVER HOLDS THE PASSWORD -
 * it holds StoredKey and ServerKey, from which the password cannot be
 * recovered.  LogonUser needs a password.  S4U ("service for user") issues a
 * logon token on the strength of the caller's own privilege instead.
 *
 * WHAT MAKES IT WORK, AND IT IS ONE PRIVILEGE.  LsaRegisterLogonProcess needs
 * SeTcbPrivilege and returns a TRUSTED connection; only a trusted connection
 * yields an IMPERSONATION-level token.  An untrusted one yields Identification,
 * which impersonates nothing.  LocalSystem has SeTcbPrivilege; no interactive
 * account does, elevated or not.  Measured three ways by gplbld/probe-s4u.c.
 *
 * AND IMPERSONATION REALLY DOES GOVERN THE FILE LAYER, which was the open
 * question and is not obvious: SD opens data files with POSIX open()
 * (dh_file.c:815), through msys-2.0.dll, which does its own path translation.
 * gplbld/probe-impersonate.c measured it - open() of a file the impersonated
 * user may not read fails with EACCES, and succeeds again after RevertToSelf.
 *
 * ADOPTING IT INTO THE RUNTIME, AND WHY IMPERSONATING IS NOT ENOUGH ON ITS OWN.
 * ImpersonateLoggedOnUser sets a token on the CALLING THREAD.  Cygwin's fork()
 * deimpersonates and reimpersonates around the clone, and it restores only what
 * the RUNTIME knows about - so a token set behind its back is silently dropped
 * and the thread comes back as the process's own identity.  Nothing reports it:
 * no error, no signal, and win32s4u.c cannot see it happen.
 *
 * That is not a corner case here.  The account switch at LOGTO runs
 * is_grp_member (APISRVR:566), which is BASIC calling !ps_script, which reaches
 * op_sh.c:379 and forks there.  So the identity was gone before the session
 * opened a single account file, and every record it wrote came out owned by
 * NT AUTHORITY\SYSTEM.
 *
 * THE FIX IS A PAIR OF CALLS AND IT HAS TO BE BOTH.  cygwin_internal(
 * CW_SET_EXTERNAL_TOKEN) only REGISTERS a token for the runtime to adopt at its
 * next user-context change; seteuid() is what performs that change.  Measured
 * by gplbld/probe-impfork.c's Q4 leg, in the API session's own shape (a fork()ed
 * and exec()d Cygwin child) and in a direct control, both instruments agreeing:
 *
 *   plain fork()                     thread token NONE,   file owned by SYSTEM
 *   CW_SET_EXTERNAL_TOKEN, fork()    thread token NONE,   file owned by SYSTEM
 *   CW_SET_EXTERNAL_TOKEN + seteuid  thread token TARGET, file owned by TARGET
 *
 * The bare call is the form this project wrote down for a day and it does not
 * work.  An implementation of it would have compiled, returned 0 from every
 * call, and silently not worked.
 *
 * WHAT ELSE MOVES WHEN seteuid() DOES, surveyed over the 13 POSIX uid sites in
 * gplsrc: seteuid changes the EFFECTIVE uid only, so the REAL uid stays the
 * service's and getpwuid(getuid()) at linuxlb.c:95 and :213, and sdfix.c:1548,
 * are untouched.  The one visible change is op_sys.c:228, SYSTEM(28), which
 * reports geteuid() to BASIC - and it has no caller anywhere in gpl.bp.
 * setegid() is deliberately NOT called: ingroup.c:76 reads getegid() and does
 * have callers, and the measurement did not need it.
 *
 * ONE LIMIT REMAINS, DELIBERATE AND NOT FIXABLE HERE:
 *
 *   IT DOES NOT REACH BACKWARDS.  Handles already open keep the access they
 *   were opened with.  The shared segment and $cred are opened before this runs
 *   and stay LocalSystem's.  That is acceptable because the ACCOUNT's files are
 *   opened at LOGTO, which is after; it is not acceptable to assume, so
 *   anything opened earlier should be treated as privileged.
 *
 *   THERE IS A WINDOW.  Between execl and the call to this, the session is
 *   LocalSystem.  APISRVR's dispatcher admits only requests 24, 25, 47 and 48
 *   before logged.in, so that window holds the SCRAM exchange and nothing an
 *   unauthenticated caller can steer.
 *
 * FAIL CLOSED.  Every failure returns FALSE and leaves the thread as it was.
 * The caller must refuse the login rather than continue as LocalSystem - a
 * session that believes it is the user while holding the service's token is
 * worse than one that never started.
 */

/* NO sd.h HERE, AND THAT IS THE RULE EVERY win32*.c FILE FOLLOWS.  sd.h
   defines Private, STRING, Sleep and GetCurrentProcessId as macros, and every
   one of them collides with windows.h - the build fails with "expected
   identifier or ( before static" pointing at a line of the project's own
   header.  So these files take windows.h and their own header and nothing
   else, and they use malloc rather than k_alloc for the same reason. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ntsecapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* THE MSYS2 RUNTIME'S OWN HEADERS, and they go AFTER windows.h because
   sys/cygwin.h needs the Win32 HANDLE type.  This is not the sd.h collision
   the note above is about - these are system headers, and gplbld/probe-impfork.c
   mixes exactly this set with windows.h and builds clean under -Wall. */
#include <unistd.h>
#include <pwd.h>
#include <sys/cygwin.h>

#include "win32s4u.h"

/* Origin and source names are cosmetic - they appear in the logon session's
   audit record.  TOKEN_SOURCE.SourceName is a fixed 8 bytes and is NOT
   NUL-terminated, so it is memcpy'd rather than strcpy'd. */
#define S4U_ORIGIN "SD"
#define S4U_SOURCE "SDsessn"

/* The token we are impersonating with, kept so it can be closed on revert.
   One session is one process here, so a single static is the right scope. */
static HANDLE s4u_token = NULL;

/* The effective uid before the runtime adopted the token, so a revert can put
   it back.  (uid_t)-1 means "nothing to restore" and is NOT a valid uid.   */
static uid_t s4u_saved_euid = (uid_t)-1;

/* ======================================================================
   adopt_in_runtime()  -  make the MSYS2 runtime carry the token across fork()

   Returns TRUE only when the runtime has actually taken the identity on.  The
   caller FAILS CLOSED on FALSE: an identity that survives to the LOGTO group
   check and no further is the defect this file exists to remove, not a partial
   success.                                                                  */

static int adopt_in_runtime(HANDLE token, const char* username) {
  struct passwd* pw;
  uid_t before;

  /* getpwnam resolves the Windows account through the runtime's own NSS, which
     is the same view seteuid() will use.  Looking it up any other way would be
     asking a different question from the one that has to agree. */
  pw = getpwnam(username);
  if (pw == NULL)
    return 0;

  /* REGISTER.  This only records the token; on its own it changes nothing and
     the identity still dies at the first fork().  Measured, not assumed. */
  if (cygwin_internal(CW_SET_EXTERNAL_TOKEN, token, CW_TOKEN_IMPERSONATION) != 0)
    return 0;

  before = geteuid();

  /* REFUSE THE NULL CASE.  seteuid() to the uid already held returns 0 from a
     fast path WITHOUT touching the user context, so the runtime would never
     adopt what was just registered - and this function would report success
     for a session whose identity drops at the first fork.  Unreachable in
     practice (the session is the service's uid and the target is a real user),
     which is exactly why it must not be left to chance. */
  if (before == pw->pw_uid)
    return 0;

  if (seteuid(pw->pw_uid) != 0)
    return 0;

  /* READBACK, NOT A RETURN CODE.  seteuid reporting success and the euid not
     having moved is the shape of failure that matters here. */
  if (geteuid() != pw->pw_uid) {
    seteuid(before);
    return 0;
  }

  s4u_saved_euid = before;
  return 1;
}

/* ======================================================================
   AssumeUserIdentity()  -  impersonate a local user, no password needed

   Returns TRUE only when the calling thread is, on return, running as the
   named user.  Anything else returns FALSE with the thread untouched.       */

int AssumeUserIdentity(const char* username) {
  LSA_HANDLE hlsa = NULL;
  LSA_OPERATIONAL_MODE mode = 0;
  LSA_STRING lsaname;
  LSA_STRING pkgname;
  LSA_STRING origin;
  ULONG pkg = 0;
  MSV1_0_S4U_LOGON* s4u = NULL;
  ULONG s4ulen;
  BYTE* tail;
  WCHAR* wuser;
  WCHAR* wdom;
  int wuserlen;
  int wdomlen;
  char domain[MAX_COMPUTERNAME_LENGTH + 1];
  DWORD domainlen = sizeof(domain);
  TOKEN_SOURCE source;
  NTSTATUS st;
  NTSTATUS sub = 0;
  void* profile = NULL;
  ULONG profilelen = 0;
  LUID logonid;
  QUOTA_LIMITS quotas;
  HANDLE token = NULL;
  SECURITY_IMPERSONATION_LEVEL level;
  DWORD got = 0;
  int ok = 0;

  if ((username == NULL) || (*username == '\0'))
    return 0;

  /* A local account's domain is this machine.  LEAVING DomainName EMPTY GIVES
     STATUS_NOT_SUPPORTED from a call that otherwise looks right - paid for
     while writing probe-impersonate.c. */
  if (!GetComputerNameA(domain, &domainlen))
    return 0;

  lsaname.Buffer = (PCHAR)S4U_ORIGIN;
  lsaname.Length = (USHORT)strlen(S4U_ORIGIN);
  lsaname.MaximumLength = (USHORT)(lsaname.Length + 1);

  /* TRUSTED or nothing.  LsaConnectUntrusted would succeed here and produce an
     Identification-level token, which impersonates nothing - a failure that
     looks like a success until the first file open. */
  st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (st != 0)
    return 0;

  pkgname.Buffer = (PCHAR)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(MSV1_0_PACKAGE_NAME);
  pkgname.MaximumLength = (USHORT)(pkgname.Length + 1);
  st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (st != 0)
    goto exit_assume;

  /* ONE CONTIGUOUS BLOCK.  LSA copies the whole buffer into its own process,
     so both UNICODE_STRING.Buffer pointers must point inside it. */
  wuserlen = MultiByteToWideChar(CP_ACP, 0, username, -1, NULL, 0);
  wdomlen = MultiByteToWideChar(CP_ACP, 0, domain, -1, NULL, 0);
  if ((wuserlen <= 0) || (wdomlen <= 0))
    goto exit_assume;

  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) + (wuserlen * sizeof(WCHAR)) +
                   (wdomlen * sizeof(WCHAR)));
  s4u = (MSV1_0_S4U_LOGON*)malloc(s4ulen);
  if (s4u == NULL)
    goto exit_assume;
  memset(s4u, 0, s4ulen);

  tail = (BYTE*)s4u + sizeof(MSV1_0_S4U_LOGON);
  wuser = (WCHAR*)tail;
  wdom = (WCHAR*)(tail + (wuserlen * sizeof(WCHAR)));
  MultiByteToWideChar(CP_ACP, 0, username, -1, wuser, wuserlen);
  MultiByteToWideChar(CP_ACP, 0, domain, -1, wdom, wdomlen);

  s4u->MessageType = MsV1_0S4ULogon;
  s4u->Flags = 0;

  /* Length is in BYTES and EXCLUDES the terminator; MaximumLength INCLUDES it.
     Setting them equal gives STATUS_INVALID_PARAMETER from a call that reads
     correctly - the other mistake probe-impersonate.c paid for. */
  s4u->UserPrincipalName.Length = (USHORT)((wuserlen - 1) * sizeof(WCHAR));
  s4u->UserPrincipalName.MaximumLength = (USHORT)(wuserlen * sizeof(WCHAR));
  s4u->UserPrincipalName.Buffer = wuser;
  s4u->DomainName.Length = (USHORT)((wdomlen - 1) * sizeof(WCHAR));
  s4u->DomainName.MaximumLength = (USHORT)(wdomlen * sizeof(WCHAR));
  s4u->DomainName.Buffer = wdom;

  origin.Buffer = (PCHAR)S4U_ORIGIN;
  origin.Length = (USHORT)strlen(S4U_ORIGIN);
  origin.MaximumLength = (USHORT)(origin.Length + 1);

  memcpy(source.SourceName, S4U_SOURCE, sizeof(source.SourceName));
  if (!AllocateLocallyUniqueId(&source.SourceIdentifier))
    goto exit_assume;

  /* Network, not Interactive: an S4U logon carries no credentials and the user
     has no right to a desktop here. */
  st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen, NULL, &source,
                    &profile, &profilelen, &logonid, &token, &quotas, &sub);
  if ((st != 0) || (token == NULL))
    goto exit_assume;

  /* Refuse an Identification-level token rather than impersonate with it:
     ImpersonateLoggedOnUser would SUCCEED and change nothing. */
  if (!GetTokenInformation(token, TokenImpersonationLevel, &level, sizeof(level),
                           &got) ||
      (level != SecurityImpersonation))
    goto exit_assume;

  if (!ImpersonateLoggedOnUser(token))
    goto exit_assume;

  /* THE THREAD IS THE USER NOW, AND THAT IS NOT YET ENOUGH.  Cygwin's fork()
     restores only the identity the RUNTIME knows about, so without this the
     token is dropped silently at the LOGTO group check.  Fail closed: revert
     the thread rather than hand back a session that is the user only until it
     forks. */
  if (!adopt_in_runtime(token, username)) {
    RevertToSelf();
    goto exit_assume;
  }

  /* Hold the token for RevertUserIdentity(). */
  if (s4u_token != NULL)
    CloseHandle(s4u_token);
  s4u_token = token;
  token = NULL; /* Not ours to close below any more */
  ok = 1;

exit_assume:
  if (profile != NULL)
    LsaFreeReturnBuffer(profile);
  if (s4u != NULL)
    free(s4u);
  if (token != NULL)
    CloseHandle(token);
  if (hlsa != NULL)
    LsaDeregisterLogonProcess(hlsa);
  return ok;
}

/* ======================================================================
   RevertUserIdentity()  -  go back to the process's own token               */

void RevertUserIdentity(void) {
  /* RevertToSelf FIRST, so the seteuid below is attempted from the process's
     own privileged token rather than from the user's.  The runtime half has to
     be undone too: reverting only the thread would leave the euid moved, and
     the next fork() would carry the user back in. */
  RevertToSelf();
  if (s4u_saved_euid != (uid_t)-1) {
    seteuid(s4u_saved_euid);
    s4u_saved_euid = (uid_t)-1;
  }
  if (s4u_token != NULL) {
    CloseHandle(s4u_token);
    s4u_token = NULL;
  }
}

/* ======================================================================
   ImpersonatingUser()  -  is this thread running as somebody else, and WHO?

   Reported rather than assumed: a caller that believes it impersonated and did
   not is the failure this whole file is written to avoid.

   24 Aug 26 Windows port - IT DID THE THING ITS OWN COMMENT WARNS AGAINST, and
   it had no callers, so nothing had ever caught it.  It was:

       return (s4u_token != NULL) ? 1 : 0;

   which reports whether THIS FILE STILL HOLDS A HANDLE, not whether the thread
   is impersonating.  Those are different facts, and PROJECT_STATUS.md 7 step
   14 is the case where they disagree: a fork() silently reverts the calling
   thread to the process token, and nothing clears s4u_token when it happens -
   RevertUserIdentity() is the only thing that would, and it has no caller
   either.  So at the moment the identity is GONE this returned 1.

   Step 14 (b) was written as "call this at write time and the answer is
   direct".  It would have answered "still impersonating" and looked like it
   contradicted b28's SYSTEM-owned record.  A confident wrong answer from the
   instrument sent to confirm the finding.

   It now ASKS WINDOWS.  OpenThreadToken fails with ERROR_NO_TOKEN when the
   thread holds no impersonation token, which is the answer "not impersonating"
   rather than an error, and the caller gets the NAME because "whose identity"
   is the question and a boolean cannot carry it.                            */

int ImpersonatingUser(char* name, int namelen) {
  HANDLE tok = NULL;
  unsigned char buf[512];
  char user[256];
  char dom[256];
  DWORD ulen;
  DWORD dlen;
  DWORD got = 0;
  SID_NAME_USE use;

  if ((name != NULL) && (namelen > 0))
    name[0] = '\0';

  /* OpenAsSelf TRUE so the access check uses the PROCESS token.  With FALSE,
     a thread impersonating a token that cannot open itself would report "not
     impersonating" - the wrong answer, arrived at from the right call.      */

  if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok))
    return 0; /* ERROR_NO_TOKEN here IS the answer, not a failure */

  if (GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &got)) {
    TOKEN_USER* tu = (TOKEN_USER*)buf;

    ulen = sizeof(user);
    dlen = sizeof(dom);
    if (LookupAccountSidA(NULL, tu->User.Sid, user, &ulen, dom, &dlen, &use)) {
      if ((name != NULL) && (namelen > 0))
        snprintf(name, namelen, "%s\\%s", dom, user);
    }
  }

  CloseHandle(tok);
  return 1;
}

/* ======================================================================
   HoldingUserToken()  -  does this file still hold an S4U token?

   The other half of the pair above, and it exists so the two can be COMPARED.
   ImpersonatingUser() says what Windows does; this says what SD believes.
   Equal is healthy.  Believing while not impersonating is step 14's defect,
   and no single value can express that.                                    */

int HoldingUserToken(void) {
  return (s4u_token != NULL) ? 1 : 0;
}

/* END-CODE */
