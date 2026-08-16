/* WIN32AUDIT.H
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
 * NOTHING IN THIS INTERFACE IS A WINDOWS TYPE, for the reasons win32sem.h
 * gives at length: windows.h and sd.h cannot share a translation unit, so the
 * Win32 half lives alone in a file that includes NO SD header.  This is the
 * second such file, and it is deliberately the same shape as the first.
 *
 * WHY IT EXISTS, MEASURED 16 AUG 2026.  The audit trail is written by every
 * SD user and must not be rewritable by them, so the installer grants sdusers
 * AppendData and withholds WriteData.  Against that ACL:
 *
 *   open(O_WRONLY|O_APPEND|O_CREAT)   FAILS, errno 13
 *
 * because the MSYS2 runtime maps O_WRONLY to GENERIC_WRITE, which contains
 * FILE_WRITE_DATA.  Granting WriteData to make the open work hands back
 * exactly what the ACL was for: with it, an ordinary user CAN truncate the
 * file to nothing and CAN overwrite earlier records in place - both measured,
 * not assumed.  CreateFile asking for FILE_APPEND_DATA alone succeeds, and
 * truncation, overwriting and reading are then all refused with error 5.
 *
 * So the whole of the Win32 exception here is one CreateFile flag that the
 * POSIX layer will not let us ask for on its own.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32AUDIT_H
#define WIN32AUDIT_H

/* Append len bytes to path, creating it if it does not exist.  Opens with
   FILE_APPEND_DATA ONLY, so the write always lands at the end and the caller
   needs no right that would let it alter what is already there.

   Returns 0 on success and -1 on any failure.  The caller cannot act on the
   reason - audit_message() is deliberately silent - so none is returned.  */

int win32_audit_append(const char* path, const char* data, int len);

/* Rename path to rotated, then recreate path empty CARRYING THE SAME ACL.

   The recreation is not tidiness.  A file created by CreateFile inherits the
   directory's rights, and the data tree grants sdusers Modify - so a rotation
   that only renamed would leave the next trail readable, rewritable and
   deletable by the very users it records, silently and from then on.  That is
   the kind of quiet downgrade this port has been bitten by before, so the
   descriptor is copied from the file being rotated away rather than rebuilt
   from anything that could drift out of step with the installer.

   Caller must be elevated: renaming needs Delete, which sdusers is not given.
   Returns 0 on success and -1 on any failure.                             */

int win32_audit_rotate(const char* path, const char* rotated);

#endif

/* END-CODE */
