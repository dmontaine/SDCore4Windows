/* WIN32S4U.H
 * Take on an SD user's Windows identity without their password, for
 * op_kernel.c's K_ASSUME_USER.
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
 * 23 Aug 26 Windows port - written.  PROJECT_STATUS.md 7 step 14, shape (b):
 *           the API session authenticates with SCRAM and THEN becomes the
 *           user, because it cannot be spawned as them - sdwind does not know
 *           who the caller is at fork time.
 * END-HISTORY
 *
 * AssumeUserIdentity() returns TRUE only when the calling thread is, on
 * return, running as the named user.  It FAILS CLOSED: anything else returns
 * FALSE with the thread untouched, and the caller must refuse the login rather
 * than carry on holding the service's token.
 *
 * win32s4u.c's header carries why S4U rather than LogonUser, the one privilege
 * that makes it work, and the two limits - it is per-thread and does not reach
 * backwards, and there is a window before it runs.
 */

#ifndef WIN32S4U_H
#define WIN32S4U_H

/* int rather than bool: this header is included from op_kernel.c, which has
   sd.h's definitions, and from win32s4u.c, which deliberately has none. */
int AssumeUserIdentity(const char* username);
void RevertUserIdentity(void);
int ImpersonatingUser(void);

#endif

/* END-CODE */
