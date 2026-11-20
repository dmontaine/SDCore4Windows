/* WIN32LOCALSDSYS.H
 * SDSYS reached from this computer by the Windows users the administrator lists (RELEASE_1.1 339, Linux S.267).
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
 * 18 Nov 26 Windows port - written for RELEASE_1.1 339, the Windows reading of Linux's sd_localsdsys.h (38cfb301), with the answers
 *           Linux gave in mail 2026-11-18T0745.  The design and its falsifiers: .claude/localsdsys/DESIGN.md.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * NOTHING IN THIS INTERFACE IS A WINDOWS TYPE (win32peer.h has why: windows.h and the POSIX socket headers cannot share a
 * translation unit), so sd.exe (the MSYS2 build) and the SD service (sdsvc.exe, native) both include it.  win32localsdsys.c is
 * compiled into both: the service asks the questions before it starts anything, and the SDSYS process it starts asks them again
 * in its own kernel (K$SDSYS.LOCAL), so neither trusts the other (Linux T0745, Q10).
 *
 * THE LISTS.  <ProgramData>\SD\sd-tls\sdsys-local-ssh and ...\sdsys-local-api, written only by gplbld/sd-sdsyslocal.ps1: one
 * "<name> <SID>" a line, ASCII, LF, at most 32.  Absent is empty.  A list is read only when the folder and the file are each not a
 * link and grant access to nobody but SYSTEM and Administrators, the file has one link, is owned by SYSTEM or Administrators and
 * is under 8 KB, and every line is well formed; otherwise it is an empty list with the reason list-unsafe.  The list is read FIRST,
 * so an empty list always answers list-empty (LOGIN then writes the audit line it always wrote).
 *
 * A LISTED SID MAY BE ANSWERED (sdl_account_ok) when it is now a local user account of this computer, enabled, RID 1000 or more,
 * a member of sdusers, and none of SDSYS, SDRADMIN, sdrunin, sdrelay: no-user, not-sd-user otherwise.
 *
 * THE REASON WORDS are Linux's: list-empty list-unsafe not-listed not-sd-user no-user no-login other-user other-session
 * no-session session-unsafe not-ssh not-local no-terminal, and peer-unknown for an API peer this file could not name.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef WIN32LOCALSDSYS_H
#define WIN32LOCALSDSYS_H

#include <stddef.h>

#define SDL_MAX_NAMES   32
#define SDL_NAME_MAX    20
#define SDL_SID_MAX     96
#define SDL_FILE_MAX    8192
#define SDL_COMMAND     "sd-sdsys"
#define SDL_PIPE        "\\\\.\\pipe\\sd-sdsys-local"
#define SDL_SVC_NAME    "SD"
#define SDL_SSHD_SVC    "sshd"

typedef struct {
  int n;
  char name[SDL_MAX_NAMES][SDL_NAME_MAX + 1];
  char sid[SDL_MAX_NAMES][SDL_SID_MAX];
} sdl_list;

/* ---------------------------------------------------------------- pure (the free check drives these on fixtures) */

/* 1 when NAME may be a name in a list: 1 to 20 characters, no control character, no space, none of " / \ [ ] : ; | = , + * ? < > @,
   not only dots.  The same rule as sd-sdsyslocal.ps1's Test-SdLocalName and LOCALSDSYS. */
int sdl_name_ok(const char* name);

/* A list file's bytes as entries: the count (0 to 32), or -1 when any rule of the text is broken (a byte that is not printable
   ASCII, LF or CR; a line that is not "<name> <SID>" with a local account's SID form S-1-5-21-a-b-c-rid; a SID twice; 33 lines). */
int sdl_parse(const char* text, size_t len, sdl_list* out);

/* ---------------------------------------------------------------- the operating system's answers */

/* The production path of a list, kind "ssh" or "api": <ProgramData>\SD\sd-tls\sdsys-local-<kind>, ProgramData named from the profile
   list in the registry (GetAllUsersProfileDirectory), never from the environment.  1, or 0 when it cannot be named. */
int sdl_list_path(const char* kind, char* out, size_t outlen);

/* The list at PATH, held to every file rule (CHECK_ACL 0 skips the owner and the grants, for the free check on scratch files).
   The count (0 = empty or absent, *why "list-empty"), or -1 (*why "list-unsafe"). */
int sdl_read(const char* path, int check_acl, sdl_list* out, const char** why);

/* 1 when the account whose SID is SID may be answered (see the description), its name now in NAME_NOW; 0 and *why otherwise. */
int sdl_account_ok(const char* sid, char* name_now, size_t nlen, const char** why);

/* The API: 1 when SID is on the API list and sdl_account_ok; 0 and *why (list-empty, list-unsafe, not-listed, no-user, not-sd-user). */
int sdl_api_listed(const char* sid, char* name_now, size_t nlen, const char** why);

/* The API front, at accept and before anything else (sd.c's PF_INET case, as LocalSystem): name the program at the other end of a
   loopback connection.  The TCP table's owner-module row gives the pid and the connection's creation time; the process is OPENED
   FIRST and everything else is read through that handle, so the pid cannot be recycled under it; a process created AFTER the
   connection is not its owner (a pid reused once the creator exited while a child kept the socket: other-session, Linux T0745 Q8);
   the logon session's own SID must be the token's user (other-user).  The answer is kept for sdl_peer_sid().  Anything that cannot
   be read leaves the peer unknown (peer-unknown).  OUR_PORT and PEER_PORT in host byte order; PEER_V4 the peer's IPv4 address in
   network byte order. */
void sdl_peer_record(unsigned long peer_v4, unsigned short our_port, unsigned short peer_port);
const char* sdl_peer_sid(void);       /* the recorded peer's SID, or "" */
const char* sdl_peer_why(void);       /* the reason word when it is "" */

/* The name a SID has now (the account name, no domain), for the audit line.  1, or 0 and NAME empty. */
int sdl_sid_name(const char* sid, char* name, size_t nlen);

/* The ssh door's evidence about process PID, which claims to be a listed user's sd.exe in an ssh login from this computer.  Read in
   this order, each failure its reason word: the ssh list (list-empty, list-unsafe); the process opened and its token read (no-login);
   its user on the list (not-listed) and an account that may be answered (no-user, not-sd-user); its logon session's SID that user
   (other-user) and its type network or network-cleartext, sshd's two (not-ssh); its ancestry, each parent created before its child
   and still running, through only cmd.exe and the user's sshd.exe in that logon up to the first SYSTEM process (session-unsafe for
   another image, no-session for a gap); that process sshd's own image, SYSTEM, a child of the sshd service, created after it (not-ssh);
   sshd's own record in OpenSSH/Operational, an Accepted event written BY that process (its ProcessID), after it was made, for that
   user (no-session); its address a literal loopback (not-local), and that connection still established at the sshd service
   (no-session).  sshd's record is waited for, up to SDL_EVENT_WAIT_MS: an event is not queryable the moment sshd writes it.
   0 with the user's name now and SID; -1 with *why, and *step (when STEP is not NULL) a fixed text naming the step that refused,
   for the service's log only: four steps share no-session. */
int sdl_ssh_evidence(unsigned long pid, char* name, size_t nlen, char* sid, size_t slen, const char** why, const char** step);

/* The SDSYS process the service started for an ssh login (sd -SDSYSLOCAL <pid>): 0 when THIS process is the local account SDSYS
   from the SD service's S4U logon (token source SDsessn), elevated, a child of the SD service, and PID passes sdl_ssh_evidence; the
   user's name then in NAME.  -1 and *why otherwise. */
int sdl_ssh_self(unsigned long pid, char* name, size_t nlen, const char** why);

#endif

/* END-CODE */
