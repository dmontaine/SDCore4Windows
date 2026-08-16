/* WIN32SEM.C
 * Native Windows named semaphores, for sdsem.c.
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
 * 16 Aug 26 Windows port - written.  POSIX sem_open() cannot be used in
 *           session 0, so SD could not run as a service.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY THIS FILE EXISTS AT ALL.  POSIX sem_open() on the MSYS2 runtime does not
 * work in session 0: as LocalSystem it BLOCKS FOR TEN SECONDS AND FAILS WITH
 * ETIMEDOUT.  Measured 16 Aug 2026 with the creating process and the opening
 * process BOTH LocalSystem in session 0, so it is not about crossing sessions -
 * the runtime's POSIX semaphores simply do not work there.  SD could therefore
 * never be started by a Windows service, and the requirement is a production
 * system with nobody logged in, serving every user from system startup.
 *
 * The repository owner sanctioned the windows.h exception on 16 Aug 2026.
 * win32sem.h explains why the exception has to live in a file of its own
 * rather than inside sdsem.c.
 *
 * TWO THINGS ARE LOAD-BEARING HERE AND NEITHER IS OBVIOUS:
 *
 * THE "Global\" PREFIX.  A service runs in session 0 and its users in sessions
 * 1 and up.  An unqualified name is session-local, so the service and the users
 * would each get their own private semaphore of the same name and neither would
 * ever see the other - the same failure as before, wearing a different hat.
 * Creating in Global needs SeCreateGlobalPrivilege, which LocalSystem and an
 * elevated administrator both hold; OPENING one does not, which is what lets an
 * ordinary user's session attach.
 *
 * THE SECURITY DESCRIPTOR.  A default one grants the creator's token and
 * nothing else, so SD would start as a service and then refuse every user on
 * the machine - and it would look healthy while doing it.  The objects are
 * therefore created granting SYSTEM, Administrators and the caller's nominated
 * group, which is sdusers: the same three the data tree's ACL grants.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "win32sem.h"

/* ======================================================================
   The security descriptor.

   Built in SDDL rather than with InitializeAcl/AddAccessAllowedAce because the
   call form is forty lines with three failure paths and this can be read at a
   glance.  GA is GENERIC_ALL, SY is SYSTEM, BA is the Administrators alias -
   the last of these by SID rather than by name, so it is right on a localised
   Windows, which is the same reason sd.iss passes *S-1-5-32-544 to icacls.

   A MISSING GROUP IS NOT AN ERROR.  The bootstrap (gplbld/bootstrap.py) starts
   SD on a build machine that has never had the installer near it, so sdusers
   does not exist there.  Falling back to SYSTEM and Administrators is exactly
   right for that case: the bootstrap is elevated and nobody else is involved. */

static PSECURITY_DESCRIPTOR build_descriptor(const char* group) {
  char sddl[256];
  char* group_sid = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  SID* sid = NULL;
  char* domain = NULL;
  DWORD sid_len = 0;
  DWORD dom_len = 0;
  SID_NAME_USE use;

  if (group != NULL && *group != '\0') {
    /* Documented two-call form: ask for the sizes, then the values. */
    LookupAccountNameA(NULL, group, NULL, &sid_len, NULL, &dom_len, &use);

    if (sid_len != 0) {
      sid = (SID*)malloc(sid_len);
      domain = (char*)malloc(dom_len + 1);

      if (sid != NULL && domain != NULL &&
          LookupAccountNameA(NULL, group, sid, &sid_len, domain, &dom_len,
                             &use)) {
        ConvertSidToStringSidA(sid, &group_sid);
      }
    }

    if (sid != NULL)
      free(sid);
    if (domain != NULL)
      free(domain);
  }

  if (group_sid != NULL &&
      strlen(group_sid) + strlen("D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;)") <
          sizeof(sddl)) {
    sprintf(sddl, "D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;%s)", group_sid);
  } else {
    strcpy(sddl, "D:(A;;GA;;;SY)(A;;GA;;;BA)");
  }

  if (group_sid != NULL)
    LocalFree(group_sid);

  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(
          sddl, SDDL_REVISION_1, &sd, NULL))
    return NULL;

  return sd;
}

/* ====================================================================== */

void* w32sem_create(const char* name, const char* group, int* already_exists) {
  SECURITY_ATTRIBUTES sa;
  PSECURITY_DESCRIPTOR sd;
  HANDLE h;

  if (already_exists != NULL)
    *already_exists = 0;

  sd = build_descriptor(group);
  if (sd == NULL)
    return NULL;

  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;
  sa.bInheritHandle = FALSE;

  /* Binary: initial one, maximum one, matching the POSIX set this replaced. */
  h = CreateSemaphoreA(&sa, 1, 1, name);

  /* GetLastError() is meaningful even when the call succeeded, and reading it
     has to happen before anything else can overwrite it - LocalFree included. */
  if (h != NULL && already_exists != NULL &&
      GetLastError() == ERROR_ALREADY_EXISTS)
    *already_exists = 1;

  {
    DWORD saved = GetLastError();
    LocalFree(sd);
    SetLastError(saved);
  }

  return (void*)h;
}

void* w32sem_open(const char* name) {
  return (void*)OpenSemaphoreA(SEMAPHORE_ALL_ACCESS, FALSE, name);
}

void w32sem_close(void* handle) {
  if (handle != NULL)
    CloseHandle((HANDLE)handle);
}

int w32sem_trywait(void* handle) {
  return (WaitForSingleObject((HANDLE)handle, 0) == WAIT_OBJECT_0);
}

void w32sem_post(void* handle) {
  ReleaseSemaphore((HANDLE)handle, 1, NULL);
}

unsigned long w32sem_last_error(void) {
  return (unsigned long)GetLastError();
}

int w32sem_absent(unsigned long err) {
  return (err == (unsigned long)ERROR_FILE_NOT_FOUND);
}

/* END-CODE */
