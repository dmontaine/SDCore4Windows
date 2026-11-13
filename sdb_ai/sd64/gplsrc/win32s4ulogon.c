/* win32s4ulogon.c - the S4U logon: a local account's token, minted on the caller's SeTcb, no password.
 *
 * START-HISTORY:
 * 13 Nov 26 Windows port - lifted out of win32s4u.c unchanged, so that the SD service (native, UCRT64) can build it too:
 *           win32s4u.c takes the MSYS2 runtime's headers for adopt_in_runtime() and cannot.  And win32_s4u_logon_groups()
 *           added: the same logon with local groups put in the token (LsaLogonUser's LocalGroups), for RELEASE_1.1 253(b),
 *           run.in WITH debug - the debugged child runs as the bare account sdrunin plus sdusers and the account's own
 *           sdu_<account>.  win32_s4u_logon() is that call with no groups, which is what it always did.
 * 16 Sep 26 Windows port - (in win32s4u.c) the LSA logon lifted out of AssumeUserIdentity() as win32_s4u_logon(), so that
 *           win32relay.c could mint the TLS relay's bare account with the same code (RELEASE_1.1 43).
 * 23 Aug 26 Windows port - (in win32s4u.c) written.
 * END-HISTORY
 *
 * WHAT MAKES IT WORK, AND IT IS ONE PRIVILEGE.  LsaRegisterLogonProcess needs SeTcbPrivilege and returns a TRUSTED
 * connection; only a trusted connection yields an IMPERSONATION-level token, and only a caller with SeTcb may pass
 * LocalGroups.  LocalSystem has it; no interactive account does, elevated or not (gplbld/probe-s4u.c).
 *
 * THE GROUPS ARE ADDED, NOT MEMBERSHIPS.  LocalGroups puts the SIDs in this one token; the account is not made a member
 * of anything, so the SAM still says it is in no group and no other logon of it carries them.  Each is ENABLED and
 * MANDATORY, so the holder cannot disable one to slip past a deny entry.  A name that does not resolve to a group of this
 * machine is a failure, not a smaller token: a child that runs without the group it was meant to have would fail later
 * and less legibly, and one with a different group than asked would be wrong.  OWED IN A VM (falsifier F2 of the
 * design): that the MSV1_0 S4U logon honours LocalGroups; until measured, nothing has shown the groups arrive.
 *
 * NO sd.h HERE, the rule every win32*.c file follows (sd.h's Private, STRING and Sleep collide with windows.h).
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ntsecapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "win32s4u.h"

/* Origin and source names are cosmetic - they appear in the logon session's audit record.  TOKEN_SOURCE.SourceName is a
   fixed 8 bytes and is NOT NUL-terminated, so it is memcpy'd rather than strcpy'd. */
#define S4U_ORIGIN "SD"
#define S4U_SOURCE "SDsessn"

#define S4U_GROUPS_MAX 4

/* The SID of a group of THIS machine, or 0.  A domain group, a user, a well-known group or a built-in alias is refused:
   only a local group SD made may be put in a token here. */
static int local_group_sid(const char* name, BYTE* sid, DWORD sidlen) {
  char dom[MAX_COMPUTERNAME_LENGTH + 64];
  char host[MAX_COMPUTERNAME_LENGTH + 1];
  DWORD n = sidlen;
  DWORD dl = sizeof(dom);
  DWORD hl = sizeof(host);
  SID_NAME_USE use;

  if ((name == NULL) || (*name == '\0'))
    return 0;
  if (!LookupAccountNameA(NULL, name, (PSID)sid, &n, dom, &dl, &use))
    return 0;
  if ((use != SidTypeAlias) && (use != SidTypeGroup))
    return 0;
  if (!GetComputerNameA(host, &hl) || (lstrcmpiA(dom, host) != 0)) /* lstrcmpiA: _stricmp is not in the MSYS2 runtime */
    return 0; /* BUILTIN, NT AUTHORITY or a domain: not one of SD's local groups */
  return 1;
}

void* win32_s4u_logon_groups(const char* username, const char* const* groups) {
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
  int ng = 0;
  BYTE gsid[S4U_GROUPS_MAX][SECURITY_MAX_SID_SIZE];
  TOKEN_GROUPS* tg = NULL;
  int i;

  if ((username == NULL) || (*username == '\0'))
    return NULL;

  /* The groups first: a name that does not resolve fails the call before LSA is asked anything. */
  for (ng = 0; (groups != NULL) && (groups[ng] != NULL); ng++) {
    if ((ng >= S4U_GROUPS_MAX) || !local_group_sid(groups[ng], gsid[ng], SECURITY_MAX_SID_SIZE))
      return NULL;
  }
  if (ng > 0) {
    tg = (TOKEN_GROUPS*)malloc(sizeof(TOKEN_GROUPS) + (ng * sizeof(SID_AND_ATTRIBUTES)));
    if (tg == NULL)
      return NULL;
    tg->GroupCount = (DWORD)ng;
    for (i = 0; i < ng; i++) {
      tg->Groups[i].Sid = (PSID)gsid[i];
      tg->Groups[i].Attributes = SE_GROUP_MANDATORY | SE_GROUP_ENABLED_BY_DEFAULT | SE_GROUP_ENABLED;
    }
  }

  /* A local account's domain is this machine.  LEAVING DomainName EMPTY GIVES STATUS_NOT_SUPPORTED from a call that
     otherwise looks right - paid for while writing probe-impersonate.c. */
  if (!GetComputerNameA(domain, &domainlen))
    goto exit_logon;

  lsaname.Buffer = (PCHAR)S4U_ORIGIN;
  lsaname.Length = (USHORT)strlen(S4U_ORIGIN);
  lsaname.MaximumLength = (USHORT)(lsaname.Length + 1);

  /* TRUSTED or nothing.  LsaConnectUntrusted would succeed here and produce an Identification-level token, which
     impersonates nothing - a failure that looks like a success until the first file open. */
  st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (st != 0) {
    hlsa = NULL;
    goto exit_logon;
  }

  pkgname.Buffer = (PCHAR)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(MSV1_0_PACKAGE_NAME);
  pkgname.MaximumLength = (USHORT)(pkgname.Length + 1);
  st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (st != 0)
    goto exit_logon;

  /* ONE CONTIGUOUS BLOCK.  LSA copies the whole buffer into its own process, so both UNICODE_STRING.Buffer pointers must
     point inside it. */
  wuserlen = MultiByteToWideChar(CP_ACP, 0, username, -1, NULL, 0);
  wdomlen = MultiByteToWideChar(CP_ACP, 0, domain, -1, NULL, 0);
  if ((wuserlen <= 0) || (wdomlen <= 0))
    goto exit_logon;

  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) + (wuserlen * sizeof(WCHAR)) + (wdomlen * sizeof(WCHAR)));
  s4u = (MSV1_0_S4U_LOGON*)malloc(s4ulen);
  if (s4u == NULL)
    goto exit_logon;
  memset(s4u, 0, s4ulen);

  tail = (BYTE*)s4u + sizeof(MSV1_0_S4U_LOGON);
  wuser = (WCHAR*)tail;
  wdom = (WCHAR*)(tail + (wuserlen * sizeof(WCHAR)));
  MultiByteToWideChar(CP_ACP, 0, username, -1, wuser, wuserlen);
  MultiByteToWideChar(CP_ACP, 0, domain, -1, wdom, wdomlen);

  s4u->MessageType = MsV1_0S4ULogon;
  s4u->Flags = 0;

  /* Length is in BYTES and EXCLUDES the terminator; MaximumLength INCLUDES it.  Setting them equal gives
     STATUS_INVALID_PARAMETER from a call that reads correctly - the other mistake probe-impersonate.c paid for. */
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
    goto exit_logon;

  /* Network, not Interactive: an S4U logon carries no credentials and the user has no right to a desktop here. */
  st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen, tg, &source, &profile, &profilelen, &logonid, &token,
                    &quotas, &sub);
  if ((st != 0) || (token == NULL))
    goto exit_logon;

  /* Refuse an Identification-level token rather than hand it back: ImpersonateLoggedOnUser would SUCCEED with it and
     change nothing, and DuplicateTokenEx to a primary token would fail less legibly. */
  if (!GetTokenInformation(token, TokenImpersonationLevel, &level, sizeof(level), &got) ||
      (level != SecurityImpersonation))
    goto exit_logon;
  ok = 1;

exit_logon:
  if (profile != NULL)
    LsaFreeReturnBuffer(profile);
  if (s4u != NULL)
    free(s4u);
  if (tg != NULL)
    free(tg);
  if (hlsa != NULL)
    LsaDeregisterLogonProcess(hlsa);
  if (!ok && token != NULL) {
    CloseHandle(token);
    token = NULL;
  }
  return (void*)token;
}

void* win32_s4u_logon(const char* username) {
  return win32_s4u_logon_groups(username, NULL);
}

/* END-CODE */
