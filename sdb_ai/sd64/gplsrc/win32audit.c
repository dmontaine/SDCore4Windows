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
 * 13 Nov 26 Windows port - RELEASE_1.1 247: win32_audit_rotate() is called by the service as it writes (sdsvc/sdaudit.c,
 *           which builds this file natively too) as well as at "sd -start".  It refuses a rotation whose DACL it cannot
 *           read, recreates with OPEN_ALWAYS so a racing append is kept, and undoes the rename when the new trail
 *           cannot be made or given the old DACL (Linux S.159).
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
     file produces, which is the elevated caller and is correct.

     13 Nov 26 - RELEASE_1.1 247: A DESCRIPTOR THAT CANNOT BE READ REFUSES THE
     ROTATION.  It used to rotate anyway and leave the new trail with the data
     tree's inherited rights - editable by the users it records.  The trail
     stays whole and keeps growing instead, as Linux's audit_rot.c does when it
     cannot lift the append attribute.                                       */

  if (GetNamedSecurityInfoA((LPSTR)path, SE_FILE_OBJECT,
                            DACL_SECURITY_INFORMATION, NULL, NULL, &dacl, NULL,
                            &sd) != ERROR_SUCCESS) {
    return -1;
  }
  if (dacl == NULL) {
    LocalFree(sd);
    return -1;
  }

  /* MoveFile does not replace an existing name, so a rotated file of the same
     second is never overwritten (Linux refuses that case by hand); and it
     fails while a session holds the trail open, which is the moment not to
     rename it.                                                              */
  if (!MoveFileA(path, rotated)) {
    LocalFree(sd);
    return -1;
  }

  /* Recreate immediately.  13 Nov 26 - OPEN_ALWAYS, NOT CREATE_ALWAYS: a
     session appending for itself in the moment between the rename and this
     makes the file first, and CREATE_ALWAYS truncated its record away.  Kept
     now; the ACL is set below either way.                                  */

  h = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                  NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);

  if (h != INVALID_HANDLE_VALUE) {
    CloseHandle(h);
    status = 0;
  }

  /* PROTECTED_DACL_SECURITY_INFORMATION is what stops the directory's rights
     being inherited back on top of the ones just copied.

     13 Nov 26 - Linux S.159 (audit_rot.c): A NEW TRAIL THAT CANNOT BE MADE, OR
     CANNOT BE GIVEN THE OLD ONE'S DACL, UNDOES THE ROTATION.  This used to
     return -1 and leave either no trail or one with the directory's rights.
     The old trail goes back under its name - over the new file when one was
     made - and the caller tries again later.                               */

  if (status == 0) {
    if (SetNamedSecurityInfoA((LPSTR)path, SE_FILE_OBJECT,
                              DACL_SECURITY_INFORMATION |
                                  PROTECTED_DACL_SECURITY_INFORMATION,
                              NULL, NULL, dacl, NULL) != ERROR_SUCCESS) {
      status = -1;
      (void)MoveFileExA(rotated, path, MOVEFILE_REPLACE_EXISTING);
    }
  } else {
    (void)MoveFileA(rotated, path);
  }

  if (sd != NULL)
    LocalFree(sd);

  return status;
}

/* END-CODE */
