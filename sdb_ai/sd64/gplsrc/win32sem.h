/* WIN32SEM.H
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
 * NOTHING IN THIS INTERFACE IS A WINDOWS TYPE, AND THAT IS THE POINT.
 *
 * windows.h and sd.h CANNOT SHARE A TRANSLATION UNIT.  Measured 16 Aug 2026
 * when this was first tried inside sdsem.c: linuxlb.h defines
 * GetCurrentProcessId() as a nought-argument macro and w32api declares it
 * taking VOID, so the header fails to parse; SD declares its own Sleep with a
 * different prototype from the Win32 one; and SD's "Private" macro expands
 * inside the w32api headers.  None of that is fixable from the SD side
 * without editing headers the whole tree depends on.
 *
 * So the Win32 half lives here, alone, including windows.h and NO SD header at
 * all - not even sddefs.h.  Callers pass ordinary C strings and get back void*
 * handles.  This is also what keeps the owner's 16 Aug 2026 sanction narrow:
 * one file to audit for where Win32 enters the server (PROJECT_STATUS.md 5.4).
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32SEM_H
#define WIN32SEM_H

/* Create a binary semaphore, value 1, named "name".  "group" is a Windows
   group given access alongside SYSTEM and Administrators, or NULL for none;
   a group that does not exist is not an error and is simply left out.
   *already_exists is set non-zero if the object was already there, in which
   case the returned handle is still valid and refers to it.
   Returns NULL on failure.                                                  */
void* w32sem_create(const char* name, const char* group, int* already_exists);

/* Open an existing one.  NULL if it is not there - use w32sem_absent() on
   w32sem_last_error() to tell "not started" from a real failure.            */
void* w32sem_open(const char* name);

void w32sem_close(void* handle);

/* Non-blocking acquire.  Non-zero if it was taken.                          */
int w32sem_trywait(void* handle);

void w32sem_post(void* handle);

unsigned long w32sem_last_error(void);

/* Is this the error that means "no such object"?  Kept here so no caller has
   to name ERROR_FILE_NOT_FOUND and therefore include windows.h.             */
int w32sem_absent(unsigned long err);

#endif

/* END-CODE */
