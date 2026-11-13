/* sdrunin.h - run.in's debugged child, started by the SD service
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
 * 13 Nov 26 Windows port - written.  RELEASE_1.1 253(b); sdrunin.c has the description, ../win32runin.h the wire.
 * END-HISTORY
 *
 * START-CODE
 */

#ifndef SDRUNIN_H
#define SDRUNIN_H

#include <stddef.h>

typedef void (*sdrunin_log_fn)(const char* fmt, ...);

/* A request as the service reads it, every word already checked (sdrunin_parse). */
typedef struct {
  char account[65];
  char file[65];
  char program[65];
  char term[33];
  int cols;
  int rows;
} SDRUNIN_REQ;

/* Serve pipe_name: start a run for each elevated administrator who asks.  sysdir is SD's system directory (from sd.conf,
   as the audit writer reads it), store_base the directory the runs' stores are made in (<ProgramData>\SD\runin in the
   service), sd_exe the sd.exe the child is.  0 serving, -1 not (logged).  The test passes a pipe and directories of its
   own and never has SeTcb, so it sees every refusal before the logon and the logon's own. */
int sdrunin_start(const char* pipe_name, const char* sysdir, const char* store_base, const char* sd_exe,
                  sdrunin_log_fn log);

/* Stop serving: every run still going has its job terminated and its store removed. */
void sdrunin_stop(void);

/* ---------------------------------------------------------------- the parts the test drives on their own */

/* The request line without its newline: "SDRUNIN1 <account>\t<file>\t<program>\t<term>\t<cols>\t<rows>".  0 and rq
   filled, or -1 and why. */
int sdrunin_parse(const char* line, SDRUNIN_REQ* rq, char* why, size_t whylen);

/* The account's register record, <sysdir>\accounts\<account>: it must be there, a plain file, not SUSPENDED, and name
   sdu_<account> as its group (case aside).  0 and the group's name, or -1 and why. */
int sdrunin_register(const char* sysdir, const char* account, char* group, size_t grouplen, char* why, size_t whylen);

/* A new environment block (UTF-16, malloc'd; free() it): the variables of src (a block from CreateEnvironmentBlock, or
   NULL) less any TERM, LINES, COLUMNS, SD_RUNIN_STORE, SD_SESSION and SD_PHANTOM_NONCE it had, then those four set
   from the run.  NULL if it cannot be made. */
void* sdrunin_env(const void* src, const char* store, const char* term, int cols, int rows);

/* Make store_base (protected: SYSTEM and Administrators only; one found that is not SD's own is moved aside), then a new
   run directory inside it that SYSTEM and Administrators may use and the logon SID logon_sid may add, read, write and
   delete FILES in - not directories, so no link can be made in it.  0 and the path, or -1 and why. */
int sdrunin_store_make(const char* store_base, void* logon_sid, char* path, size_t pathlen, char* why, size_t whylen);

/* Remove a run directory: its files, then itself.  A link in it is removed as a link and never followed. */
void sdrunin_store_remove(const char* path);

/* Remove EVERY privilege from a token (SE_PRIVILEGE_REMOVED, then read back).  1 done, 0 not (why). */
int sdrunin_strip_privileges(void* token, char* why, size_t whylen);

#endif

/* END-CODE */
