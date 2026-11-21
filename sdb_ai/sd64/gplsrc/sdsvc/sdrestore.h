/* SDRESTORE.H
 * "sdsvc.exe -restore-kept": put back, AS SDSYS, what an uninstall that kept the data took away.
 * Copyright (c) String Database
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * START-HISTORY:
 * 21 Nov 26 Windows port - RELEASE_1.1 370 (owner, 21 Nov 2026: a Keep must put the system back exactly as it was).
 * END-HISTORY
 */

#ifndef SDRESTORE_H
#define SDRESTORE_H

/* The whole of the mode: returns the process exit code (0 the child ran and exited 0; 1 it ran and did not, or could not be started; 2 refused). */
int sdrestore_main(void);

#endif

/* END-CODE */
