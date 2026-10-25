/* WIN32TLS.C
 * Native Windows half of the API's TLS relay: is the identity directory
 * closed to everyone but SYSTEM and Administrators?
 * Copyright (c) String Database
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * START-HISTORY:
 * 15 Sep 26 Windows port - written for RELEASE_1.1 41 (Linux S.19).
 * 25 Oct 26 Windows port - from Linux 71eb0aa (S.65 slice 2b): win32_private_to_user(), the SD_FILE_PRIVATE test for a stored SDNet credential.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * This file includes windows.h and NO SD header, exactly as win32audit.c and
 * win32sem.c do and for the same reason: windows.h and sd.h cannot share a
 * translation unit.  Its one interface is declared in sd_tls.h with no
 * Windows type in it.
 *
 * WHY THE CHECK IS NATIVE AND NOT stat().  Linux's relay refuses the identity
 * unless the file and its directory are owned by the process's user and
 * closed to others, read from st_uid and st_mode.  Neither means anything
 * here: the MSYS2 mount is noacl (PROJECT_STATUS.md 5.7), so st_mode is
 * invented from the read-only attribute and chmod() is a no-op.  What
 * protects the key on Windows is the DACL the installer sets with icacls
 * (gplbld/secure-tls.ps1: /inheritance:r, SYSTEM and Administrators only),
 * and a DACL is what this reads.  The relay runs as LocalSystem, so "owned by
 * me" would be satisfied by anything SYSTEM created - including a directory
 * an ordinary SD user created FIRST under the sdusers-writable data directory
 * and handed over.  The ACE walk catches that too: their grant is on it.
 *
 * END-DESCRIPTION
 */

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <string.h>

/* Declared in sd_tls.h; repeated here so this file includes no SD header. */
int win32_admin_only(const char* path, char* why, size_t whylen);
int win32_private_to_user(const char* path, int want_dir, char* why, size_t whylen);   /* 25 Oct 26: used by op_sdext.c (SD_FILE_PRIVATE) */

/* ====================================================================== */

static void name_sid(PSID sid, char* out, size_t outlen) {
  char account[256];
  char domain[256];
  DWORD alen = sizeof(account);
  DWORD dlen = sizeof(domain);
  SID_NAME_USE use;
  LPSTR text = NULL;

  if (LookupAccountSidA(NULL, sid, account, &alen, domain, &dlen, &use)) {
    snprintf(out, outlen, "%s\\%s", domain, account);
  } else if (ConvertSidToStringSidA(sid, &text)) {
    snprintf(out, outlen, "%s", text);
    LocalFree(text);
  } else {
    snprintf(out, outlen, "<unknown SID>");
  }
}

int win32_admin_only(const char* path, char* why, size_t whylen) {
  PACL dacl = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  DWORD rc;
  WORD i;
  int ok = 0;

  if (path == NULL) {
    snprintf(why, whylen, "no path");
    return 0;
  }

  rc = GetNamedSecurityInfoA((LPSTR)path, SE_FILE_OBJECT,
                             DACL_SECURITY_INFORMATION, NULL, NULL, &dacl,
                             NULL, &sd);
  if (rc != ERROR_SUCCESS) {
    snprintf(why, whylen, "cannot read the ACL of %s (error %lu)", path,
             (unsigned long)rc);
    return 0;
  }

  /* A NULL DACL is "everyone, full control" - the opposite of what is being
     asked, and it must not read as "no grants found, so nobody else". */
  if (dacl == NULL) {
    snprintf(why, whylen, "%s has no DACL: everyone has full control", path);
    LocalFree(sd);
    return 0;
  }

  ok = 1;
  for (i = 0; i < dacl->AceCount; i++) {
    ACE_HEADER* hdr;
    PSID sid;
    char who[512];

    if (!GetAce(dacl, i, (LPVOID*)&hdr))
      continue;

    /* Deny entries only narrow access; the question is who is ALLOWED. */
    if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE)
      continue;

    sid = (PSID)&((ACCESS_ALLOWED_ACE*)hdr)->SidStart;
    if (IsWellKnownSid(sid, WinLocalSystemSid) ||
        IsWellKnownSid(sid, WinBuiltinAdministratorsSid))
      continue;

    name_sid(sid, who, sizeof(who));
    snprintf(why, whylen,
             "%s grants access to %s, and only SYSTEM and Administrators may "
             "have any%s", path, who,
             (hdr->AceFlags & INHERITED_ACE) ? " (inherited from the parent)"
                                             : "");
    ok = 0;
    break;
  }

  LocalFree(sd);
  return ok;
}

/* ======================================================================
   win32_private_to_user()  -  25 Oct 26, from Linux 71eb0aa (S.65 slice 2b)

   Linux's file_private_check() (SD_FILE_PRIVATE, SDEXT 111) trusts a stored SDNet credential only if it is a regular file by lstat, owned by
   the effective uid, with no group or world bits, in a directory that passes the same test.  The Windows reading, from the DACL as
   win32_admin_only() reads it: the path is not a link (no reparse point), is a file (or, for want_dir, a directory), is OWNED by the user this
   process runs as, and its DACL allows nobody but that user, SYSTEM and Administrators.  A NULL DACL is everyone, so it fails.  A file's parent
   directory must pass as a directory.  Every failure answers 0 and says why.  The process's own SID is taken from its token (TokenUser), and
   the token's default owner (TokenOwner) is also accepted as the owner, because an elevated administrator's new files are owned by the
   Administrators group, not by the user.                                                                                                   */

static int sid_is_ours(PSID sid, PSID user, PSID towner) {
  return EqualSid(sid, user) || (towner != NULL && EqualSid(sid, towner));
}

int win32_private_to_user(const char* path, int want_dir, char* why, size_t whylen) {
  char native[1024];
  char parent[1024];
  size_t n, i;
  DWORD attr;
  PSID owner = NULL;
  PACL dacl = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  HANDLE tok = NULL;
  BYTE ubuf[256];
  BYTE obuf[256];
  DWORD got = 0;
  PSID user = NULL;
  PSID towner = NULL;
  DWORD rc;
  WORD a;
  int ok = 0;

  if (path == NULL || path[0] == '\0') {
    snprintf(why, whylen, "no path");
    return 0;
  }
  n = strlen(path);
  if (n >= sizeof(native)) {
    snprintf(why, whylen, "path too long");
    return 0;
  }
  for (i = 0; i <= n; i++)
    native[i] = (path[i] == '/') ? '\\' : path[i];

  attr = GetFileAttributesA(native);
  if (attr == INVALID_FILE_ATTRIBUTES) {
    snprintf(why, whylen, "cannot examine %s (error %lu)", native, (unsigned long)GetLastError());
    return 0;
  }
  if (attr & FILE_ATTRIBUTE_REPARSE_POINT) {
    snprintf(why, whylen, "%s is a link", native);
    return 0;
  }
  if (want_dir && !(attr & FILE_ATTRIBUTE_DIRECTORY)) {
    snprintf(why, whylen, "%s is not a directory", native);
    return 0;
  }
  if (!want_dir && (attr & FILE_ATTRIBUTE_DIRECTORY)) {
    snprintf(why, whylen, "%s is not a regular file", native);
    return 0;
  }

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
    snprintf(why, whylen, "cannot read the process token (error %lu)", (unsigned long)GetLastError());
    return 0;
  }
  if (GetTokenInformation(tok, TokenUser, ubuf, sizeof(ubuf), &got))
    user = ((TOKEN_USER*)ubuf)->User.Sid;
  if (GetTokenInformation(tok, TokenOwner, obuf, sizeof(obuf), &got))
    towner = ((TOKEN_OWNER*)obuf)->Owner;
  CloseHandle(tok);
  if (user == NULL) {
    snprintf(why, whylen, "cannot read the process user");
    return 0;
  }

  rc = GetNamedSecurityInfoA(native, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, NULL, &dacl, NULL, &sd);
  if (rc != ERROR_SUCCESS) {
    snprintf(why, whylen, "cannot read the security of %s (error %lu)", native, (unsigned long)rc);
    return 0;
  }
  if (owner == NULL || !sid_is_ours(owner, user, towner)) {
    snprintf(why, whylen, "%s is not owned by the running user", native);
    LocalFree(sd);
    return 0;
  }
  if (dacl == NULL) {
    snprintf(why, whylen, "%s has no DACL: everyone has full control", native);
    LocalFree(sd);
    return 0;
  }

  ok = 1;
  for (a = 0; a < dacl->AceCount; a++) {
    ACE_HEADER* hdr;
    PSID sid;

    if (!GetAce(dacl, a, (LPVOID*)&hdr))
      continue;
    if (hdr->AceType == ACCESS_DENIED_ACE_TYPE)
      continue;   /* a deny only narrows access */
    if (hdr->AceFlags & INHERIT_ONLY_ACE)
      continue;   /* applies to what is made below, not to this object (the CREATOR OWNER entry a directory inherits is one) */
    if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE) {
      snprintf(why, whylen, "%s has an access entry of a kind this check does not read (type %u)", native, (unsigned)hdr->AceType);
      ok = 0;
      break;
    }
    sid = (PSID)&((ACCESS_ALLOWED_ACE*)hdr)->SidStart;
    if (sid_is_ours(sid, user, towner) || IsWellKnownSid(sid, WinLocalSystemSid) || IsWellKnownSid(sid, WinBuiltinAdministratorsSid))
      continue;
    {
      char who[512];
      name_sid(sid, who, sizeof(who));
      snprintf(why, whylen, "%s grants access to %s, and only the running user, SYSTEM and Administrators may have any", native, who);
    }
    ok = 0;
    break;
  }
  LocalFree(sd);
  if (!ok)
    return 0;

  if (!want_dir) {
    /* the directory it sits in must be as closed */
    size_t k = strlen(native);
    strcpy(parent, native);
    while (k > 0 && parent[k - 1] != '\\')
      k--;
    if (k <= 1) {
      snprintf(why, whylen, "%s has no parent directory", native);
      return 0;
    }
    parent[k - 1] = '\0';
    if (k >= 3 && parent[k - 2] == ':')
      return 0;   /* a drive root is not a private directory */
    return win32_private_to_user(parent, 1, why, whylen);
  }
  return 1;
}

/* END-CODE */
