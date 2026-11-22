/* sdcredown.h - cred-own in the SD service: a person changes their own SD password (RELEASE_1.1 379)
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
 * START-CODE
 */

#ifndef SDCREDOWN_H
#define SDCREDOWN_H

#include <stddef.h>

typedef void (*sdcredown_log_fn)(const char* fmt, ...);
/* Write one audit line for user (DOMAIN\name) and pid; the service passes sdaudit_write. */
typedef int (*sdcredown_audit_fn)(const char* user, unsigned long pid, const char* msg);

/* Serve pipe_name over SD's system directory sysdir.  grant: the accounts besides Administrators that may open the pipe (the service
   passes sdusers; the test its own user), NULL-terminated.  audit may be NULL (nothing is audited).  0 serving, -1 not (logged). */
int sdcredown_start(const char* pipe_name, const char* sysdir, const char* const* grant, sdcredown_audit_fn audit,
                    sdcredown_log_fn log);

/* Stop serving. */
void sdcredown_stop(void);

/* ---------------------------------------------------------------- the part the test drives on its own */

/* One request (the wire of win32credown.h, through "END") for ACCOUNT, the lower-case name the server took from the caller's
   token.  Fills answer ("OK ..." or "ER ...", no line end) and, when the request is to be audited, audit_msg (else "").  Returns
   0 answered OK, -1 refused. */
int sdcredown_handle(const char* sysdir, const char* account, const char* request, char* answer, size_t alen, char* audit_msg,
                     size_t amlen);

/* The account a Windows user name gives: lower case, and only letters, digits, '.', '_' and '-' (1 to 64, not starting with '.').
   0 and out filled, or -1. */
int sdcredown_account(const char* user_name, char* out, size_t outlen);

#endif

/* END-CODE */
