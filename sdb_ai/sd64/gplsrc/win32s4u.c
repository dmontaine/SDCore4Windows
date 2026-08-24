/* win32s4u.c - take on an SD user's Windows identity without their password.
 *
 * START-HISTORY:
 * 23 Aug 26 Windows port - written.  PROJECT_STATUS.md section 7 step 14,
 *           shape (b): the API session authenticates with SCRAM in APISRVR and
 *           THEN becomes the user, rather than being spawned as them.
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
 * TWO LIMITS, BOTH DELIBERATE AND NEITHER FIXABLE HERE:
 *
 *   IT IS PER-THREAD AND DOES NOT REACH BACKWARDS.  Handles already open keep
 *   the access they were opened with.  The shared segment and $cred are opened
 *   before this runs and stay LocalSystem's.  That is acceptable because the
 *   ACCOUNT's files are opened at LOGTO, which is after; it is not acceptable
 *   to assume, so anything opened earlier should be treated as privileged.
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

#include "win32s4u.h"

/* Origin and source names are cosmetic - they appear in the logon session's
   audit record.  TOKEN_SOURCE.SourceName is a fixed 8 bytes and is NOT
   NUL-terminated, so it is memcpy'd rather than strcpy'd. */
#define S4U_ORIGIN "SD"
#define S4U_SOURCE "SDsessn"

/* The token we are impersonating with, kept so it can be closed on revert.
   One session is one process here, so a single static is the right scope. */
static HANDLE s4u_token = NULL;

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
  RevertToSelf();
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
