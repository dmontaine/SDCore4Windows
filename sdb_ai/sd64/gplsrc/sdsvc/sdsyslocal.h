/* sdsyslocal.h - "ssh -t <user>@localhost sd-sdsys": the SD service's door to an SDSYS session
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
 * 18 Nov 26 Windows port - written.  RELEASE_1.1 339; sdsyslocal.c has the description, ../win32sdsysask.h the wire.
 * END-HISTORY
 *
 * START-CODE
 */

#ifndef SDSYSLOCAL_H
#define SDSYSLOCAL_H

#include <stddef.h>

typedef void (*sdsyslocal_log_fn)(const char* fmt, ...);

/* Serve pipe_name (SDL_PIPE in the service): start an SDSYS session for each listed user's ssh login from this computer that
   passes every question.  sd_exe is the sd.exe the SDSYS process is.  0 serving, -1 not (logged). */
int sdsyslocal_start(const char* pipe_name, const char* sd_exe, sdsyslocal_log_fn log);

/* Stop serving: every session still going has its job terminated and its pseudo console closed. */
void sdsyslocal_stop(void);

/* ---------------------------------------------------------------- the part a test can drive on its own */

/* The request line without its newline: "SDSYSLOCAL1 <cols> <rows> <term>" (win32sdsysask.h).  0 and the three filled, or -1. */
int sdsyslocal_parse(const char* line, int* cols, int* rows, char* term, size_t tlen);

#endif

/* END-CODE */
