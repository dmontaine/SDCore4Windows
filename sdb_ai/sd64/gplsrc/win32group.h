/* WIN32GROUP.H
 * Is a NAMED user a member of a NAMED local group?
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
 * A LIVE SAM QUERY WITH NO CHILD PROCESS, because a pre-authenticated API
 * session cannot start one (win32group.c says what was measured).  It replaces
 * the PowerShell that gpl.bp/is_grp_member used to run, and answers the SAME
 * question rather than a cheaper one - see that file's description.
 *
 * ***THREE ANSWERS, NOT TWO, AND THAT IS THE POINT.***  The return value says
 * whether the question could be answered at all; *member says what the answer
 * was.  A caller that collapses the two - reading "could not tell" as "not a
 * member" - is the defect this interface is shaped to prevent, and it is what
 * made a DLL-initialisation failure read as "not granted" for seven runs.
 *
 * END-DESCRIPTION
 */

#ifndef WIN32GROUP_H
#define WIN32GROUP_H

#include <stddef.h>

/* Returns TRUE when the question was answered, with *member set to 1 or 0.
   Returns FALSE when it could not be answered - a lookup failure OR a group
   that does not exist - with the reason in why.  The caller must NOT read
   FALSE as "not a member". */
int win32_group_has_member(const char* user, const char* group, int* member,
                           char* why, size_t whylen);

#endif

/* END-CODE */
