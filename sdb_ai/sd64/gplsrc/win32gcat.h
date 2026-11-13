/* WIN32GCAT.H
 * Is a global catalogue object writable by someone other than the administrators?  (RELEASE_1.1 249, Linux W.11 F2)
 * Copyright (c) String Database
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * START-HISTORY:
 * 13 Nov 26 Windows port - written, the Windows form of Linux 12615e80's gcat_object_writable() (object.c).
 * END-HISTORY
 */

#ifndef WIN32GCAT_H
#define WIN32GCAT_H

/* 1 when the file at winpath (a native Windows path) may be written by Everyone, Authenticated Users, Users, Interactive or
   the local group sdusers; 1 also when its security cannot be read or it has no DACL (fail closed); 0 otherwise. */
int win32_gcat_writable(const char* winpath);

#endif
