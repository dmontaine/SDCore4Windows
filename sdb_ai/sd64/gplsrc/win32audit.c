/* WIN32AUDIT.C
 * Native Windows append-only file writing, for k_error.c.
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
 * 16 Aug 26 Windows port - written.  The POSIX runtime cannot open a file for
 *           appending without also asking for FILE_WRITE_DATA, which defeats
 *           an append-only ACL.  PROJECT_STATUS.md 7 step 4.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * win32audit.h has the reasoning and the measurements.  This file includes
 * windows.h and NO SD header, exactly as win32sem.c does and for the same
 * reason - the two cannot share a translation unit.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <aclapi.h>

#include "win32audit.h"

/* ====================================================================== */

int win32_audit_append(const char* path, const char* data, int len) {
  HANDLE h;
  DWORD written;
  int status = -1;

  if ((path == NULL) || (data == NULL) || (len <= 0))
    return -1;

  /* FILE_APPEND_DATA WITHOUT FILE_WRITE_DATA IS THE WHOLE POINT.  Asking for
     the two together is what GENERIC_WRITE does, and it is what the POSIX
     open() cannot avoid.  With this alone the kernel puts every write at the
     end of the file, and a caller holding only AppendData - which is what
     sdusers is granted - can add records and cannot touch the ones already
     there.

     FILE_SHARE_READ | FILE_SHARE_WRITE so that concurrent sessions do not
     lock each other out.  Writes are serialised by ERRLOG_SEM on the SD side
     and, independently, by the append semantics here.

     OPEN_ALWAYS creates the file when it is missing.  A file SD creates this
     way inherits the directory's ACL rather than the append-only one the
     installer sets, so this is a fallback that keeps the trail being written
     rather than the normal path - see PROJECT_STATUS.md 7 step 4.         */

  h = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                  NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);

  if (h == INVALID_HANDLE_VALUE)
    return -1;

  if (WriteFile(h, data, (DWORD)len, &written, NULL) && (written == (DWORD)len))
    status = 0;

  CloseHandle(h);

  return status;
}

/* ======================================================================
   win32_audit_rotate()  -  Rename the trail and start a new one like it   */

int win32_audit_rotate(const char* path, const char* rotated) {
  HANDLE h;
  PACL dacl = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  int status = -1;

  if ((path == NULL) || (rotated == NULL))
    return -1;

  /* Read the descriptor BEFORE the rename, while the name still resolves.
     Only the DACL is wanted: the owner is left to whatever creating the new
     file produces, which is the elevated caller and is correct.           */

  if (GetNamedSecurityInfoA((LPSTR)path, SE_FILE_OBJECT,
                            DACL_SECURITY_INFORMATION, NULL, NULL, &dacl, NULL,
                            &sd) != ERROR_SUCCESS) {
    dacl = NULL;
    sd = NULL;
  }

  if (!MoveFileA(path, rotated)) {
    if (sd != NULL)
      LocalFree(sd);
    return -1;
  }

  /* Recreate immediately.  CREATE_ALWAYS rather than CREATE_NEW because a
     racing append could have made it already; either way it is empty and the
     ACL is set below.                                                     */

  h = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                  NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);

  if (h != INVALID_HANDLE_VALUE) {
    CloseHandle(h);
    status = 0;
  }

  /* PROTECTED_DACL_SECURITY_INFORMATION is what stops the directory's rights
     being inherited back on top of the ones just copied.  A failure here
     leaves a working trail with weaker rights than intended, which is why it
     is reported: the caller cannot fix it, but PROJECT_STATUS.md 7 step 4
     names the symptom so it is recognisable.                              */

  if ((status == 0) && (dacl != NULL)) {
    if (SetNamedSecurityInfoA((LPSTR)path, SE_FILE_OBJECT,
                              DACL_SECURITY_INFORMATION |
                                  PROTECTED_DACL_SECURITY_INFORMATION,
                              NULL, NULL, dacl, NULL) != ERROR_SUCCESS) {
      status = -1;
    }
  }

  if (sd != NULL)
    LocalFree(sd);

  return status;
}

/* END-CODE */
