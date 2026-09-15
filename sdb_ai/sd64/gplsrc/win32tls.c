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

/* END-CODE */
