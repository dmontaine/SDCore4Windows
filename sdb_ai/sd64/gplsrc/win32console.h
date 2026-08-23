/* WIN32CONSOLE.H
 * Console input modes for the session terminal.
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
 * 23 Aug 26 Windows port - written.  PROJECT_STATUS.md section 7 step 13,
 *           leg 1: linuxio.c's termios calls become Console API calls.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Declared in its own header, as win32pipe.h and win32audit.h are, so that
 * linuxio.c does not have to include windows.h - which defines BOOL, BYTE and
 * a great deal else that collides with this codebase's own names.  Section 5.4
 * is the toolchain split this keeps clean.
 *
 * RETURNS int AND NOT bool, for the same reason win32_audit_append() does:
 * the two headers cannot meet, because sd.h reaches linuxlb.h which declares
 * its own bool.
 *
 * END-DESCRIPTION
 */

#ifndef WIN32CONSOLE_H
#define WIN32CONSOLE_H

/* Capture the console's entry mode and apply SD's.  Returns 1 if standard
   input is a console and the mode was applied, 0 otherwise - a piped session
   is the 0 case and is not an error, exactly as a failed tcgetattr() was. */
int win32_console_init(void);

/* Re-apply SD's mode.  No-op if win32_console_init() answered 0. */
void win32_console_set(void);

/* Put back the mode found at entry.  No-op if win32_console_init()
   answered 0. */
void win32_console_restore(void);

#endif
