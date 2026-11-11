/* sd_jobmark.c
 * Is THIS process a scheduled administrator job of SD's, started by Windows Task Scheduler from an administrator-only definition (S.102 stage 3)?
 * Copyright (c) 2026 The SD Developers, All Rights Reserved
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
 * 10 Nov 26 Windows port - from Linux 5162a5d1 (S.102 stage 3), carry area 14.  name_ok(), line_value(), the size and NUL refusals and the
 *               name= and command= tests are Linux's; the cgroup read is replaced by the caller's claim (see sd_jobmark.h), and fstat()'s owner and
 *               mode test by the SAFE callback, because on the MSYS2 noacl mount st_uid and st_mode mean nothing (win32jobmark.c reads the DACL).
 * 02 Nov 26 dm  S.102 stage 3 - written (Linux).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * A scheduled job of the administrator runs as the Windows account SDSYS from a task that Task Scheduler starts, with nobody at a desktop, so LOGIN's
 * usual question - is this SDSYS, elevated, at a desktop where UAC can render - has no yes for it.  What answers on Windows is the process token
 * (win32jobmark.c), and this file the second half: the job's definition is a file only an administrator can write (sd-jobs.ps1 set), and the
 * command it names must be the very command this session was started with, so a process that inherited the token (a child the job started) cannot
 * use it to run anything else.  NOTHING HERE TRUSTS AN ENVIRONMENT VARIABLE OR AN ARGUMENT A BASIC PROGRAM CHOSE.
 *
 * END-DESCRIPTION
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "sd_jobmark.h"

#define DEF_MAX    4096

char sd_job_active[SD_JOB_NAME_MAX + 1];

static int name_ok(const char *n)
{
    size_t len = strlen(n), i;

    if (len < 1 || len > SD_JOB_NAME_MAX) return 0;
    if (!(n[0] >= 'a' && n[0] <= 'z')) return 0;
    if (n[len - 1] == '-') return 0;
    for (i = 1; i < len; i++) {
        char c = n[i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')) return 0;
    }
    return 1;
}

/* The value of the line "KEY=..." of TEXT, copied to OUT; 0 when there is none, it is too long, or the key appears twice.  A CR before the
   line's LF is not part of the value (a definition written by PowerShell on Windows may end its lines CRLF). */
static int line_value(const char *text, const char *key, char *out, size_t outsz)
{
    size_t klen = strlen(key);
    const char *p = text, *e, *found = NULL;
    size_t vlen = 0;

    while (*p) {
        e = strchr(p, '\n');
        if (e == NULL) e = p + strlen(p);
        if ((size_t)(e - p) > klen && strncmp(p, key, klen) == 0 && p[klen] == '=') {
            if (found != NULL) return 0;
            found = p + klen + 1;
            vlen = (size_t)(e - found);
            if (vlen > 0 && found[vlen - 1] == '\r') vlen--;
        }
        p = (*e == '\n') ? e + 1 : e;
    }
    if (found == NULL || vlen >= outsz) return 0;
    memcpy(out, found, vlen);
    out[vlen] = '\0';
    return 1;
}

int sd_job_name(const char *jobs_dir, const char *claim, const char *command, sd_job_safe_fn safe, char *name, size_t namesz)
{
    char path[1024], def[DEF_MAX], val[DEF_MAX];
    ssize_t n;
    int fd, k;

    if (name == NULL || namesz < SD_JOB_NAME_MAX + 1) return -1;
    name[0] = '\0';
    if (jobs_dir == NULL || claim == NULL || safe == NULL) return -1;
    if (command == NULL || command[0] == '\0') return -1;
    if (!name_ok(claim)) return -1;

    /* the directory of definitions is the administrators' and closed to others */
    if (!safe(jobs_dir, 1)) return -1;

    /* the definition: an administrators' plain file, named as the claim, naming this very command */
    k = snprintf(path, sizeof path, "%s/%s", jobs_dir, claim);
    if (k <= 0 || (size_t)k >= sizeof path) return -1;
    if (!safe(path, 0)) return -1;
    fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    n = read(fd, def, sizeof def);
    close(fd);
    if (n <= 0 || (size_t)n >= sizeof def) return -1;
    def[n] = '\0';
    if (memchr(def, '\0', (size_t)n) != NULL) return -1;
    if (!line_value(def, "name", val, sizeof val) || strcmp(val, claim) != 0) return -1;
    if (!line_value(def, "command", val, sizeof val) || strcmp(val, command) != 0) return -1;
    strcpy(name, claim);
    return 0;
}
