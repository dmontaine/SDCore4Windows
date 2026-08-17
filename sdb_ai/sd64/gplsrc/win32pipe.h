/* WIN32PIPE.H
 * Attach an SDLocal client's named pipe to stdin and stdout.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 * START-HISTORY:
 * 17 Aug 26 Windows port - written.  PROJECT_STATUS.md section 7 step 11.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Declared in its own header, as win32audit.h is, so that sd.c does not have
 * to include windows.h - which defines BOOL, BYTE and a great deal else that
 * collides with this codebase's own names.
 *
 * IT RETURNS int AND NOT bool, for the same reason win32_audit_append() does.
 * The two headers cannot meet: sd.h reaches linuxlb.h, which declares
 * GetUserNameA() and Sleep() with types that conflict with the Windows ones,
 * so win32pipe.c cannot include sd.h and therefore has no bool to return.
 * Callers on the sd.h side treat non-zero as success, as they do there.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32PIPE_H
#define WIN32PIPE_H

/* Open the named pipe and make it descriptors 0 and 1.  Returns zero with
   nothing changed if the pipe cannot be opened.  See win32pipe.c for why the
   Cygwin runtime cannot do this through open().                            */

int win32_attach_client_pipe(char* pipe_name);

#endif

/* END-CODE */
