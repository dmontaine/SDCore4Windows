/* INIPATH.C
 * Get system paths
 * Copyright (c) 2004 Ladybridge Systems, All Rights Reserved
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
 * 14 Aug 26 Windows port - SD_CONFIG replaces SCARLET_CONFIG, and the
 *                      fallback is the Windows location rather than /etc
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * GetConfigPath() answers where sd.conf is.
 *
 * AN INSTALLED SYSTEM MUST FIND IT WITH NOTHING SET IN THE ENVIRONMENT.  It
 * did not: the fallback was "/etc/sd.conf", and once the binaries ship with
 * msys-2.0.dll beside them the POSIX root moves to C:\Program Files\SD\, so
 * /etc/sd.conf resolves INSIDE Program Files - read-only to ordinary users,
 * and separated from the data it describes.  Installing therefore required
 * setting an environment variable by hand, which is not an install.
 * See PROJECT_STATUS.md 5.8 and 5.16.
 *
 * The variable is SD_CONFIG.  It was SCARLET_CONFIG here while the client
 * library read SD_CONFIG, with a comment in the client wrongly claiming the
 * two matched - so setting the one you would expect fixed exactly one of
 * them.  SCARLET_CONFIG is not read any more; it named a project this is no
 * longer part of.
 *
 * The default is built from %ProgramData% rather than written as
 * C:\ProgramData, because that folder can be relocated and its real location
 * is what the variable holds.  The literal is only the last resort.
 *
 * END-CODE
 */

#include "sd.h"

/* ====================================================================== */

bool GetConfigPath(char *inipath) {

  char* p;

  /* Callers pass a buffer of MAX_PATHNAME_LEN + 1.  Nothing here may write
     more than that.                                                        */

  p = getenv(SD_CONFIG_ENV);
  if ((p != NULL) && (*p != '\0')) {
    snprintf(inipath, MAX_PATHNAME_LEN + 1, "%s", p);
    return TRUE;
  }

  p = getenv("ProgramData");
  if ((p != NULL) && (*p != '\0')) {
    snprintf(inipath, MAX_PATHNAME_LEN + 1, "%s\\SD\\sd.conf", p);
  } else {
    snprintf(inipath, MAX_PATHNAME_LEN + 1, "%s", SD_CONFIG_DEFAULT);
  }

  return TRUE;
}

/* END-CODE */
