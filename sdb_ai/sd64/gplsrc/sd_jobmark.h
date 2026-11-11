/* sd_jobmark.h
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
 * 10 Nov 26 Windows port - from Linux 5162a5d1 (S.102 stage 3), carry area 14.  Linux reads the name from the process's systemd cgroup, which
 *               only root can enter; Windows has no cgroup, so the name is the claim the task's own command line makes ("sd -job <name> ..."),
 *               and what makes it a job is the PROCESS TOKEN (win32jobmark.c): the Windows account SDSYS, a batch logon, elevated, not a network
 *               logon.  The definition test is Linux's, with the owner and mode test made a DACL test.  Checked by gplbld/test-jobmark-units.py
 *               through gplbld/verify-jobmark.c.
 * 02 Nov 26 dm  S.102 stage 3 - written (Linux).
 * END-HISTORY
 */

#ifndef SD_JOBMARK_H
#define SD_JOBMARK_H

#include <stddef.h>

#define SD_JOB_DIR_REL      "SD/sd-jobs"   /* under the machine's ProgramData folder, from the registry (never SD_CONFIG or %ProgramData%) */
#define SD_JOB_NAME_MAX     32

/* Answers 1 when PATH (a directory when WANT_DIR, else a regular file) may be trusted as an administrator's record, 0 otherwise.  The kernel passes
 * win32_job_admin_path(); the test driver passes its own. */
typedef int (*sd_job_safe_fn)(const char *path, int want_dir);

/* 0, with the job's name in NAME, when ALL of these hold; -1 otherwise (and NAME is empty):
 *   - CLAIM is a job name (1 to 32 characters: a lower case letter, then lower case letters, digits and dashes, not ending in a dash);
 *   - SAFE(JOBS_DIR, 1) and SAFE(JOBS_DIR/<claim>, 0) both answer 1;
 *   - JOBS_DIR/<claim> is under 4096 bytes, holds no NUL, and its "name=" line is the claim and its "command=" line is exactly COMMAND (the
 *     session's own command line - the kernel passes single_command).
 * THE CLAIM IS ONLY A KEY.  It makes nothing a job by itself: the caller asks this only of a process whose token already passed
 * win32_job_token_ok(). */
int sd_job_name(const char *jobs_dir, const char *claim, const char *command, sd_job_safe_fn safe, char *name, size_t namesz);

/* The job this process was admitted as, for the audit trail (every line of the run ends " job=<name>"); empty when none. */
extern char sd_job_active[SD_JOB_NAME_MAX + 1];

/* win32jobmark.c - the Windows half; that file includes no SD header. */
int win32_job_token_ok(char *why, size_t whylen);
int win32_job_admin_path(const char *path, int want_dir);
int win32_job_dir(char *out, size_t outlen);   /* <ProgramData>/SD/sd-jobs with forward slashes; 0 when it cannot be named */

#endif
