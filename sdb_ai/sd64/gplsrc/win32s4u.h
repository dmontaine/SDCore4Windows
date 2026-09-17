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
 * 24 Aug 26 Windows port - AssumeUserIdentity() now also makes the MSYS2
 *           runtime adopt the token, so it survives fork().  No signature
 *           change and no new entry point: the session still becomes the user
 *           at one place, and callers need not know it takes two calls.
 * END-HISTORY
 *
 * AssumeUserIdentity() returns TRUE only when the calling thread is, on
 * return, running as the named user AND THE RUNTIME WILL CARRY THAT IDENTITY
 * ACROSS fork().  The second half is not a bonus: without it the token is
 * dropped silently at the session's first fork, which is the LOGTO group
 * check.  It FAILS CLOSED: anything else returns FALSE with the thread
 * reverted, and the caller must refuse the login rather than carry on holding
 * the service's token.
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

/* 24 Aug 26 - ImpersonatingUser() TOOK NO ARGUMENTS AND ASKED THE WRONG
   QUESTION.  It returned whether s4u_token was non-NULL - what this file
   believes - rather than whether the thread is impersonating, which is what
   Windows knows.  A fork() reverts the thread and clears nothing, so the two
   part company exactly when it matters.  It now asks Windows and reports the
   NAME; HoldingUserToken() is the belief, kept separately so the two can be
   compared rather than confused.  win32s4u.c carries the full reasoning.
   Changing the signature was safe: it had no callers anywhere.            */
int ImpersonatingUser(char* name, int namelen);
int HoldingUserToken(void);

/* 16 Sep 26 - the S4U logon on its own: an IMPERSONATION-level token (a
   Windows HANDLE, passed as void* so this header stays free of windows.h)
   for a local account, or NULL.  Needs SeTcbPrivilege - LocalSystem only.
   win32relay.c mints the TLS relay's bare account with it; the caller owns
   the handle.  Nothing is impersonated or adopted here.                    */
void* win32_s4u_logon(const char* username);

/* 17 Sep 26 - RELEASE_1.1 55.  THE PROCESS TOKEN'S USER NAME, BARE.
   ImpersonatingUser() above cannot answer this and it is worth saying why,
   because the two look interchangeable: it calls OpenThreadToken, so it
   reports an IMPERSONATION, and a session spawned AS the user is not
   impersonating anybody - it IS the user, by its process token, and that call
   returns 0 with an empty name for it.  It also answers "DOMAIN\user", where
   an SD account name is bare.

   So a pre-authenticated session asks this instead, to learn who it is
   without being told over a wire it does not trust.  Non-zero with the bare
   name in name, zero if it cannot be read.                                 */
int ProcessUserName(char* name, int namelen);

#endif

/* END-CODE */
