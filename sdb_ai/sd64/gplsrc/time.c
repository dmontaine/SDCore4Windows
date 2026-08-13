/* TIME.C
 * Time related functions
 * Copyright (c) 2005 Ladybridge Systems, All Rights Reserved
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
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <sys/types.h>
#include "sd.h"
#include <time.h>

#define _timezone timezone

time_t clock_time;

/* ====================================================================== */

int32_t local_time(void) {
  static int32_t hour = -1;
  struct tm* ltm;
  static int dst;
  int32_t h;

  clock_time = time(NULL);

  /* Because daylight saving time does not take effect at midnight (though
    the Windows/Linux implementation might), we must reassess whether we
    are in a daylight saving time period if this call to local_time() is
    not in the same hour as the previous call.                            */

  h = clock_time / 3600;
  if (h != hour) /* Must reassess whether we're in daylight saving time */
  {
    hour = h;
    ltm = localtime(&clock_time);
    dst = (ltm->tm_isdst) ? 3600 : 0;
  }

  return clock_time - _timezone + dst;
}

/* ====================================================================== */

int32_t sdtime() {
  return local_time() + (732 * 86400L);
}

/* END-CODE */
