/* sdaudit.h - the audit trail's writer, in the SD service
 *
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
 * 13 Nov 26 Windows port - written.  RELEASE_1.1 247 and 182; sdaudit.c has the description.
 * END-HISTORY
 *
 * START-CODE
 */

#ifndef SDAUDIT_H
#define SDAUDIT_H

typedef void (*sdaudit_log_fn)(const char* fmt, ...);

/* The system directory of the machine's SD, from SDSYS= in the [sd] section of <ProgramData>\SD\sd.conf, the file
   a session reads when SD_CONFIG is not set.  The directory is named from the profile list, never from the
   environment.  0 found, -1 not (then there is no writer, and sessions write the trail themselves).            */
int sdaudit_sysdir(char* out, int outsz);

/* Serve pipe_name, writing <sysdir>\audit and <sysdir>\locktrace.  grant: the accounts besides Administrators that
   may send (the service passes sdusers; the test passes its own user), NULL-terminated.  The pipe is owned by this
   process's own user - LocalSystem in the service, which is what a session checks.  0 serving, -1 not (logged). */
int sdaudit_start(const char* pipe_name, const char* sysdir, const char* const* grant, sdaudit_log_fn log);

/* Stop serving, write the rate notes still owed, and log what was done. */
void sdaudit_stop(void);

#endif

/* END-CODE */
