/* WIN32GROUP.C
 * Is a NAMED user a member of a NAMED local group?  A live SAM query, with no
 * child process.
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
 * 17 Sep 26 Windows port - written for RELEASE_1.1 55.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY THIS EXISTS, AND IT IS A MEASUREMENT RATHER THAN A PREFERENCE.
 * gpl.bp/is_grp_member answered this question by running PowerShell's
 * Get-LocalGroupMember through os.execute.  RELEASE_1.1 55 spawns an
 * authenticated API session AS the user, and such a session CANNOT START
 * POWERSHELL AT ALL: measured on b190, CreateProcess succeeds and the child
 * dies in DLL initialisation with 0xC0000142, because the session is on a
 * non-interactive S4U token pointed at winsta0\default and user32 cannot
 * attach.  sd.exe itself survives only because a POSIX console program never
 * loads user32.  So every helper that shells out is unavailable to exactly the
 * sessions 55 created, and the group check is the first one they reach.
 *
 * ***IT ANSWERS THE SAME QUESTION THE POWERSHELL DID, NOT A CHEAPER ONE.***
 * The alternative was K$IN.GROUP, whose in_group() (ingroup.c) reads the
 * CALLING PROCESS's own groups with getgrnam/getgroups - it cannot be asked
 * about another user at all, and a token answer is a snapshot from logon.  A
 * live NetLocalGroupGetMembers keeps today's semantics: a grant removed in
 * Windows takes effect on the next connection, with no sign-out, which is what
 * apisrvr's own comment on the sdapi test relies on.
 *
 * NO PRIVILEGE IS NEEDED.  Enumerating a local group's members is readable by
 * an ordinary authenticated user, which is the whole point - the session that
 * needs the answer is now an ordinary user.
 *
 * windows.h and NO SD header, the rule every win32*.c file follows.
 *
 * END-DESCRIPTION
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <lm.h>
#include <sddl.h>   /* ConvertStringSidToSidA, for a group named as a SID */
#include <stdio.h>
#include <string.h>
#include <strings.h>

#include "win32group.h"

/* The bare name: everything after the last backslash, so DOMAIN\user and user
   compare the same.  Windows account names are case-insensitive. */
static const char* bare(const char* name) {
  const char* slash = strrchr(name, '\\');
  return (slash != NULL) ? (slash + 1) : name;
}

static int to_wide(const char* in, WCHAR* out, int outlen) {
  return MultiByteToWideChar(CP_ACP, 0, in, -1, out, outlen) > 0;
}

/* A group may be named as a SID string, which is what gpl.bp/is_grp_member's
   "S-" branch has always accepted.  NetLocalGroupGetMembers wants a name, so
   resolve it first rather than refusing the form. */
static int group_name_from_sid(const char* sidtext, char* out, int outlen,
                               char* why, size_t whylen) {
  PSID sid = NULL;
  char dom[256];
  DWORD nlen = (DWORD)outlen;
  DWORD dlen = sizeof dom;
  SID_NAME_USE use;
  int ok = 0;

  if (!ConvertStringSidToSidA(sidtext, &sid)) {
    snprintf(why, whylen, "%.80s is not a usable SID (error %lu)", sidtext,
             (unsigned long)GetLastError());
    return 0;
  }
  if (LookupAccountSidA(NULL, sid, out, &nlen, dom, &dlen, &use)) {
    ok = 1;
  } else {
    snprintf(why, whylen, "no account for SID %.80s (error %lu)", sidtext,
             (unsigned long)GetLastError());
  }
  LocalFree(sid);
  return ok;
}

int win32_group_has_member(const char* user, const char* group, int* member,
                           char* why, size_t whylen) {
  WCHAR wgroup[256];
  char gname[256];
  LOCALGROUP_MEMBERS_INFO_3* info = NULL;
  DWORD read = 0;
  DWORD total = 0;
  DWORD_PTR resume = 0;
  NET_API_STATUS st;
  DWORD i;
  int found = 0;

  /* Set before the guards, not after: a caller that ignored the return value
     and read *member anyway would otherwise get whatever was on its stack -
     the same class of mistake as reading FALSE as "not a member". */
  if (member != NULL)
    *member = 0;

  if ((member == NULL) || (user == NULL) || (group == NULL) ||
      (*user == '\0') || (*group == '\0')) {
    snprintf(why, whylen, "win32_group_has_member: empty user or group");
    return 0;
  }

  if (((group[0] == 'S') || (group[0] == 's')) && (group[1] == '-')) {
    if (!group_name_from_sid(group, gname, sizeof gname, why, whylen))
      return 0;
  } else {
    snprintf(gname, sizeof gname, "%s", group);
  }

  if (!to_wide(gname, wgroup, (int)(sizeof wgroup / sizeof wgroup[0]))) {
    snprintf(why, whylen, "cannot convert the group name %.80s", gname);
    return 0;
  }

  /* LEVEL 3 gives "DOMAIN\name" strings directly, so no second lookup per
     member and no SID handling in the loop.  The resume handle is honoured:
     a group with more members than one call returns would otherwise answer
     "not a member" for everybody past the first page - a false refusal that
     would look exactly like a real one. */
  do {
    info = NULL;
    st = NetLocalGroupGetMembers(NULL, wgroup, 3, (LPBYTE*)&info, MAX_PREFERRED_LENGTH,
                                 &read, &total, &resume);
    if ((st != NERR_Success) && (st != ERROR_MORE_DATA)) {
      /* NERR_GroupNotFound is not "no" - nobody can be a member of a group
         that does not exist, but the CALLER must be able to tell that from a
         lookup that failed, so both are reported as "could not tell" and the
         reason names which.  gpl.bp's old code could not make this
         distinction either; it is the conflation this whole change exists to
         stop. */
      snprintf(why, whylen, "NetLocalGroupGetMembers(%.80s) failed, status %lu",
               gname, (unsigned long)st);
      if (info != NULL)
        NetApiBufferFree(info);
      return 0;
    }

    for (i = 0; (i < read) && !found; i++) {
      char mname[512];

      if (info[i].lgrmi3_domainandname == NULL)
        continue;
      if (WideCharToMultiByte(CP_ACP, 0, info[i].lgrmi3_domainandname, -1,
                              mname, (int)sizeof mname, NULL, NULL) <= 0)
        continue;
      if (strcasecmp(bare(mname), bare(user)) == 0)
        found = 1;
    }

    if (info != NULL)
      NetApiBufferFree(info);
  } while ((st == ERROR_MORE_DATA) && !found);

  *member = found;
  return 1;
}

/* END-CODE */
