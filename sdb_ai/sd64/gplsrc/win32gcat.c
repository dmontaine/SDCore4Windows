/* WIN32GCAT.C
 * Is a global catalogue object writable by someone other than the administrators?  (RELEASE_1.1 249, Linux W.11 F2)
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
 * 13 Nov 26 Windows port - written.  Linux 12615e80 (W.11 F2, security evaluation of 24 Oct 26) refuses to load a global
 *           catalogue object that others or the group sdusers can write (object.c gcat_object_writable(), message 11930),
 *           so that a mistake in the files' modes fails closed: the kernel trusts the global catalogue by where a file
 *           lives.  On Linux the test is the file's mode bits.  On Windows the rights are the file's DACL, and the POSIX
 *           mode the runtime reports maps only Everyone to "others" and one group to "group"; the users the installer's
 *           access list keeps out (Users, Authenticated Users, sdusers) would not show.  So this reads the DACL itself.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * This file includes windows.h and NO SD header, as win32audit.c does and for the same reason.
 *
 * win32_gcat_writable(winpath) reads the file's DACL and answers 1 when an ACCESS_ALLOWED entry gives any right that could
 * change the object - write or append data, write its extended attributes, delete it, change its permissions or its owner,
 * generic write or generic all - to one of the principals that stand for "other users" on Windows: Everyone (S-1-1-0),
 * Authenticated Users (S-1-5-11), Interactive (S-1-5-4), Users (S-1-5-32-545), or the local group sdusers that every SD user
 * is in (Linux's "others or sdusers").  SYSTEM, Administrators, TrustedInstaller and any one account are not judged: SDSYS is
 * an Administrator.  A file whose security cannot be read, or that has no DACL at all (which grants everyone everything),
 * answers 1: fail closed, as Linux's fstat() failure does.  Deny entries are not credited: a deny that cancels an allow
 * is a configuration this test does not try to evaluate, and it errs towards refusing.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>

#include "win32gcat.h"

#define GCAT_WRITE_RIGHTS (FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_EA | DELETE | WRITE_DAC | WRITE_OWNER | \
                           GENERIC_WRITE | GENERIC_ALL)

/* The SIDs that are "other users" here.  sdusers is looked up by name once per process. */

static int sid_is_other(PSID sid) {
  static PSID sdusers = NULL;
  static int looked_up = 0;
  static BYTE sdusers_buf[SECURITY_MAX_SID_SIZE];
  static const char* const well_known[] = {"S-1-1-0", "S-1-5-11", "S-1-5-4", "S-1-5-32-545"};
  PSID w;
  int i;

  for (i = 0; i < (int)(sizeof(well_known) / sizeof(well_known[0])); i++) {
    w = NULL;
    if (ConvertStringSidToSidA(well_known[i], &w)) {
      int same = EqualSid(sid, w);
      LocalFree(w);
      if (same)
        return 1;
    }
  }

  if (!looked_up) {
    DWORD sid_len = sizeof(sdusers_buf);
    char domain[256];
    DWORD domain_len = sizeof(domain);
    SID_NAME_USE use;

    looked_up = 1;
    if (LookupAccountNameA(NULL, "sdusers", (PSID)sdusers_buf, &sid_len, domain, &domain_len, &use))
      sdusers = (PSID)sdusers_buf;
  }
  return (sdusers != NULL) && EqualSid(sid, sdusers);
}

/* ====================================================================== */

int win32_gcat_writable(const char* winpath) {
  PACL dacl = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  ACL_SIZE_INFORMATION info;
  DWORD i;
  int writable = 0;

  if ((winpath == NULL) || (*winpath == '\0'))
    return 1;

  if (GetNamedSecurityInfoA((LPSTR)winpath, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, &dacl, NULL, &sd) !=
      ERROR_SUCCESS)
    return 1; /* cannot tell: fail closed */

  if (dacl == NULL) { /* no DACL: everyone may do anything */
    LocalFree(sd);
    return 1;
  }

  if (!GetAclInformation(dacl, &info, sizeof(info), AclSizeInformation)) {
    LocalFree(sd);
    return 1;
  }

  for (i = 0; (i < info.AceCount) && !writable; i++) {
    LPVOID ace;
    ACE_HEADER* hdr;

    if (!GetAce(dacl, i, &ace))
      continue;
    hdr = (ACE_HEADER*)ace;
    if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE)
      continue;
    if (hdr->AceFlags & INHERIT_ONLY_ACE) /* applies to children only, not to this file */
      continue;
    {
      ACCESS_ALLOWED_ACE* a = (ACCESS_ALLOWED_ACE*)ace;
      if ((a->Mask & GCAT_WRITE_RIGHTS) && sid_is_other((PSID)&a->SidStart))
        writable = 1;
    }
  }

  LocalFree(sd);
  return writable;
}

/* END-CODE */
