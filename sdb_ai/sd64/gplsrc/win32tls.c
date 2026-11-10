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
 * 9 Nov 26 Windows port - from Linux debd0698 / S.88: win32_user_home(), SD_USER_HOME (the user's AppData\Local and a private store below it).
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
#include <userenv.h>
#include <stdio.h>
#include <string.h>

/* Declared in sd_tls.h; repeated here so this file includes no SD header. */
int win32_admin_only(const char* path, char* why, size_t whylen);
int win32_private_to_user(const char* path, int want_dir, char* why, size_t whylen);   /* 25 Oct 26: used by op_sdext.c (SD_FILE_PRIVATE) */
int win32_user_home(const char* rel, char* out, size_t out_sz, char* why, size_t whylen);   /* 9 Nov 26: used by op_sdext.c (SD_USER_HOME) */

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

/* ======================================================================
   win32_user_home()  -  9 Nov 26, from Linux debd0698 / S.88 (SD_USER_HOME, SDEXT 112)

   Linux's user_home_dir() answers the home of the process's effective user from the password database (never $HOME), followed by REL, when
   nobody but that user (and root) can rename, replace or add an entry anywhere on the way.  The Windows reading:

   - THE HOME is <profile>\AppData\Local of the user this process's token names.  The profile comes from GetUserProfileDirectory() on the
     token (the profile list in the registry), never from %LOCALAPPDATA% or %USERPROFILE%, which the person's environment sets.  A service
     account (LocalSystem, LocalService, NetworkService) has no home: it answers 0, as Linux does for root.
   - EVERY DIRECTORY on the way, the drive root included, must be a directory and not a reparse point (no junction or link anywhere), and be
     owned by the running user, SYSTEM, Administrators or TrustedInstaller.  From the profile directory down to the home, nobody else may be
     allowed to add, delete, rename or re-own anything (TRUSTED below); above the profile (C:\Users, C:\) nobody else may delete, rename,
     re-own or change the ACL (C:\ lets every user ADD a folder, which cannot move C:\Users aside, so adding is allowed there only).
     App-container SIDs (S-1-15-...) are not counted: Windows grants them access only together with a user who already has it, so they
     never give another person anything.  Measured 9 Nov 26: AppData grants an app-container capability full control and Local inherits it.
   - REL ('' for the home) is relative words separated by \ or /, with no empty word, ".", "..", or any of :*?"<>| (no stream names).  Each
     directory below the home must pass win32_private_to_user() (owned by the user, nobody but the user, SYSTEM and Administrators in its
     ACL).  ONE DEVIATION FROM LINUX, FOR AN OS REASON: Linux's check makes nothing and the caller makes a missing directory under umask 077.
     On Windows a new directory inherits its parent's entries, so one made by OS$MKDIR below the home carries the app-container entry and
     could never pass; BASIC cannot set an ACL.  So a MISSING word is made here, one level at a time and only below a directory that has
     just passed, with a protected ACL (no inheritance) that holds only the user, SYSTEM and Administrators, and the user as owner (so an
     elevated session's directory is still the person's when they are not elevated).  A word that is there and does not pass is refused,
     never repaired.
   Answers 1 and the path (with \) in OUT, or 0 with OUT empty and WHY saying what failed.                                                */

#define HOME_TRUSTED_TI "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464"   /* NT SERVICE\TrustedInstaller */
#define HOME_BAD_BELOW  (FILE_ADD_FILE | FILE_ADD_SUBDIRECTORY | FILE_DELETE_CHILD | DELETE | WRITE_DAC | WRITE_OWNER | GENERIC_ALL | GENERIC_WRITE)
#define HOME_BAD_ABOVE  (FILE_DELETE_CHILD | DELETE | WRITE_DAC | WRITE_OWNER | GENERIC_ALL)

static int sid_is_system_kind(PSID sid) {
  LPSTR text = NULL;
  int ti = 0;

  if (IsWellKnownSid(sid, WinLocalSystemSid) || IsWellKnownSid(sid, WinBuiltinAdministratorsSid))
    return 1;
  if (ConvertSidToStringSidA(sid, &text)) {
    ti = (strcmp(text, HOME_TRUSTED_TI) == 0);
    LocalFree(text);
  }
  return ti;
}

static int sid_is_app_container(PSID sid) {
  PSID_IDENTIFIER_AUTHORITY ia = GetSidIdentifierAuthority(sid);
  return ia != NULL && ia->Value[0] == 0 && ia->Value[1] == 0 && ia->Value[2] == 0 && ia->Value[3] == 0 && ia->Value[4] == 0 &&
         ia->Value[5] == 15;   /* SECURITY_APP_PACKAGE_AUTHORITY */
}

/* One directory on the way to the home: not a link, owned by us or the system kind, and no ACE outside those (and app containers) that
   allows any right in BAD.  BAD is HOME_BAD_BELOW from the profile down, HOME_BAD_ABOVE above it. */
static int home_dir_ok(const char* dir, DWORD bad, PSID user, PSID towner, char* why, size_t whylen) {
  DWORD attr;
  PSID owner = NULL;
  PACL dacl = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  DWORD rc;
  WORD a;
  int ok = 1;

  attr = GetFileAttributesA(dir);
  if (attr == INVALID_FILE_ATTRIBUTES) {
    snprintf(why, whylen, "cannot examine %s (error %lu)", dir, (unsigned long)GetLastError());
    return 0;
  }
  if (!(attr & FILE_ATTRIBUTE_DIRECTORY)) {
    snprintf(why, whylen, "%s is not a directory", dir);
    return 0;
  }
  if (attr & FILE_ATTRIBUTE_REPARSE_POINT) {
    snprintf(why, whylen, "%s is a link", dir);
    return 0;
  }
  rc = GetNamedSecurityInfoA((LPSTR)dir, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, NULL, &dacl, NULL, &sd);
  if (rc != ERROR_SUCCESS) {
    snprintf(why, whylen, "cannot read the security of %s (error %lu)", dir, (unsigned long)rc);
    return 0;
  }
  if (owner == NULL || !(sid_is_ours(owner, user, towner) || sid_is_system_kind(owner))) {
    snprintf(why, whylen, "%s is owned by somebody else", dir);
    LocalFree(sd);
    return 0;
  }
  if (dacl == NULL) {
    snprintf(why, whylen, "%s has no DACL: everyone has full control", dir);
    LocalFree(sd);
    return 0;
  }
  for (a = 0; a < dacl->AceCount; a++) {
    ACE_HEADER* hdr;
    PSID sid;
    ACCESS_MASK mask;

    if (!GetAce(dacl, a, (LPVOID*)&hdr))
      continue;
    if (hdr->AceType == ACCESS_DENIED_ACE_TYPE)
      continue;   /* a deny only narrows access */
    if (hdr->AceFlags & INHERIT_ONLY_ACE)
      continue;   /* applies to what is made below, not to this directory */
    if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE) {
      snprintf(why, whylen, "%s has an access entry of a kind this check does not read (type %u)", dir, (unsigned)hdr->AceType);
      ok = 0;
      break;
    }
    sid = (PSID)&((ACCESS_ALLOWED_ACE*)hdr)->SidStart;
    mask = ((ACCESS_ALLOWED_ACE*)hdr)->Mask;
    if (sid_is_ours(sid, user, towner) || sid_is_system_kind(sid) || sid_is_app_container(sid))
      continue;
    if ((mask & bad) == 0)
      continue;
    {
      char who[512];
      name_sid(sid, who, sizeof(who));
      snprintf(why, whylen, "%s lets %s change what it holds", dir, who);
    }
    ok = 0;
    break;
  }
  LocalFree(sd);
  return ok;
}

/* A directory only the user, SYSTEM and Administrators can reach, owned by the user, inheriting nothing from its parent. */
static int make_private_dir(const char* dir, PSID user, char* why, size_t whylen) {
  LPSTR us = NULL;
  char sddl[512];
  PSECURITY_DESCRIPTOR sd = NULL;
  SECURITY_ATTRIBUTES sa;
  int ok;

  if (!ConvertSidToStringSidA(user, &us)) {
    snprintf(why, whylen, "cannot name the running user");
    return 0;
  }
  snprintf(sddl, sizeof(sddl), "O:%sD:P(A;OICI;FA;;;%s)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)", us, us);
  LocalFree(us);
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(sddl, SDDL_REVISION_1, &sd, NULL)) {
    snprintf(why, whylen, "cannot build the ACL for %s (error %lu)", dir, (unsigned long)GetLastError());
    return 0;
  }
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;
  sa.bInheritHandle = FALSE;
  ok = CreateDirectoryA(dir, &sa);
  if (!ok)
    snprintf(why, whylen, "cannot make %s (error %lu)", dir, (unsigned long)GetLastError());
  LocalFree(sd);
  return ok;
}

int win32_user_home(const char* rel, char* out, size_t out_sz, char* why, size_t whylen) {
  HANDLE tok = NULL;
  BYTE ubuf[256];
  BYTE obuf[256];
  DWORD got = 0;
  PSID user = NULL;
  PSID towner = NULL;
  char profile[MAX_PATH + 1];
  DWORD plen = sizeof(profile);
  char work[1024];
  size_t len;
  size_t plen_chars;
  size_t i;
  const char* p;
  const char* e;

  out[0] = '\0';
  why[0] = '\0';
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
    snprintf(why, whylen, "cannot read the process token (error %lu)", (unsigned long)GetLastError());
    return 0;
  }
  if (GetTokenInformation(tok, TokenUser, ubuf, sizeof(ubuf), &got))
    user = ((TOKEN_USER*)ubuf)->User.Sid;
  if (GetTokenInformation(tok, TokenOwner, obuf, sizeof(obuf), &got))
    towner = ((TOKEN_OWNER*)obuf)->Owner;
  if (user == NULL) {
    CloseHandle(tok);
    snprintf(why, whylen, "cannot read the process user");
    return 0;
  }
  if (IsWellKnownSid(user, WinLocalSystemSid) || IsWellKnownSid(user, WinLocalServiceSid) || IsWellKnownSid(user, WinNetworkServiceSid)) {
    CloseHandle(tok);
    snprintf(why, whylen, "a service account has no home");
    return 0;
  }
  if (!GetUserProfileDirectoryA(tok, profile, &plen)) {
    CloseHandle(tok);
    snprintf(why, whylen, "no profile directory for the running user (error %lu)", (unsigned long)GetLastError());
    return 0;
  }
  CloseHandle(tok);

  plen_chars = strlen(profile);
  while (plen_chars > 3 && (profile[plen_chars - 1] == '\\' || profile[plen_chars - 1] == '/'))
    profile[--plen_chars] = '\0';
  if (plen_chars < 3 || profile[1] != ':' || profile[2] != '\\') {
    snprintf(why, whylen, "the profile directory %s is not a local path", profile);
    return 0;
  }
  for (i = 0; i < plen_chars; i++)
    if (profile[i] == '/')
      profile[i] = '\\';

  /* Above the profile: the drive root and each directory down to the profile's parent */
  memcpy(work, profile, 3);
  work[3] = '\0';
  if (!home_dir_ok(work, HOME_BAD_ABOVE, user, towner, why, whylen))
    return 0;
  for (i = 3; i < plen_chars; i++) {
    if (profile[i] != '\\')
      continue;
    memcpy(work, profile, i);
    work[i] = '\0';
    if (!home_dir_ok(work, HOME_BAD_ABOVE, user, towner, why, whylen))
      return 0;
  }

  /* The profile, AppData and Local */
  if (plen_chars + sizeof("\\AppData\\Local") >= sizeof(work)) {
    snprintf(why, whylen, "path too long");
    return 0;
  }
  memcpy(work, profile, plen_chars + 1);
  if (!home_dir_ok(work, HOME_BAD_BELOW, user, towner, why, whylen))
    return 0;
  strcat(work, "\\AppData");
  if (!home_dir_ok(work, HOME_BAD_BELOW, user, towner, why, whylen))
    return 0;
  strcat(work, "\\Local");
  if (!home_dir_ok(work, HOME_BAD_BELOW, user, towner, why, whylen))
    return 0;
  len = strlen(work);

  /* REL, one word at a time */
  if (rel == NULL)
    rel = "";
  for (p = rel; *p != '\0'; p = (*e != '\0') ? e + 1 : e) {
    size_t wl;
    DWORD attr;

    for (e = p; *e != '\0' && *e != '\\' && *e != '/'; e++)
      if (strchr(":*?\"<>|", *e) != NULL) {
        snprintf(why, whylen, "a name below the home may not hold %c", *e);
        return 0;
      }
    wl = (size_t)(e - p);
    if (wl == 0 || (wl == 1 && p[0] == '.') || (wl == 2 && p[0] == '.' && p[1] == '.')) {
      snprintf(why, whylen, "an empty name, . or .. below the home");
      return 0;
    }
    if (*e != '\0' && e[1] == '\0') {
      snprintf(why, whylen, "a trailing separator");
      return 0;
    }
    if (len + 1 + wl + 1 > sizeof(work)) {
      snprintf(why, whylen, "path too long");
      return 0;
    }
    work[len++] = '\\';
    memcpy(work + len, p, wl);
    len += wl;
    work[len] = '\0';
    attr = GetFileAttributesA(work);
    if (attr == INVALID_FILE_ATTRIBUTES) {
      if (GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) {
        snprintf(why, whylen, "cannot examine %s (error %lu)", work, (unsigned long)GetLastError());
        return 0;
      }
      if (!make_private_dir(work, user, why, whylen))
        return 0;
    }
    if (!win32_private_to_user(work, 1, why, whylen))
      return 0;
  }

  if (len + 1 > out_sz) {
    snprintf(why, whylen, "path too long");
    return 0;
  }
  memcpy(out, work, len + 1);
  return 1;
}

/* END-CODE */
