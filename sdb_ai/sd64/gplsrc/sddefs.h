/* SDDEFS.H
 * SD definitions common to all components.
 * Copyright (c) 2006 Ladybridge Systems, All Rights Reserved
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
 * 24 Aug 26 Windows port - Newline is CRLF and NewlineBytes is 2.  A directory
 *           file's records are read and written by external programs, so they
 *           get the platform's line ending; DH files cannot be read from
 *           outside and this macro never reaches them.  See the comment at the
 *           definition.  PROJECT_STATUS.md 7 step 16 (b).
 * 31 Dec 23 SD launch - prior history suppressed
 * 02 Jul 24 mab define max string size.
 * 06 Aug 24 mab define sdext max arg
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef __SDDEFS
#define __SDDEFS

/* Platforms and derivations */

#define PRODUCT_KEY 2
#define PLATFORM_NAME "Linux"
#define NIX
#define BSD
#define FALLBACK
#define HOT_SPOT_MONITOR

#define _XOPEN_SOURCE 700
#define _XOPEN_CRYPT
#include <unistd.h>

#include <endian.h>

#if __BYTE_ORDER__ == __BIG_ENDIAN__
#define BIG_ENDIAN_SYSTEM
#endif

/* 13 Aug 26 Windows port - __environ is a glibc internal alias.  <unistd.h>
 * declares environ directly here, so the remapping is dropped.
 */


#define Seek(fu, offset, whence) lseek(fu, offset, whence)

/* Derived items */

#define DS '/'
#define DSS "/"

/* 24 Aug 26 Windows port - CRLF.  PROJECT_STATUS.md 7 step 16 (b).
   Owner's rule, 24 Aug 26: a DIRECTORY file's records are real OS files that
   external programs read and write, so they get the platform's line ending;
   DYNAMIC (DH) files are in SD's own hashed format, cannot be read from
   outside, and therefore do not matter.  EVERY site this macro reaches is on
   the first side of that line - directory-file record writes, WRITESEQ /
   WRITECSV, COMO, hold files and the error log - and NO DH path uses it at
   all, so the rule resolves to the constant.

   IT IS NOT A NEW IDEA, IT IS A RESTORATION.  k_error.c:605-611 says in its
   own words that it uses this macro "instead of the more obvious use of \n"
   precisely so it can "do our own handling of the CRLF newline pair on
   Windows" - code written when this was "\r\n".  tio.h:111's per-print-unit
   newline is char[2+1] for the same reason.

   THE READERS WERE MADE TOLERANT FIRST, AND THAT ORDER IS NOT OPTIONAL.
   Step 16 (a) - verified 24 Aug, install 12:15:51 - folds CRLF on the way in
   at op_dio3.c and op_seqio.c.  Without it, changing this line would write
   two bytes and read back a stray CR on every field.  DS stays '/' for the
   reason 7 step 12 records: @ds is load-bearing for compilation.  These two
   "derived items" are NOT one decision. */
#define Newline "\r\n"
#define NewlineBytes 2

#define default_access 0666

/* 13 Aug 26 Windows port - these were unconditionally zero because Linux draws
 * no distinction between text and binary streams.  Windows does, and <fcntl.h>
 * defines both with real values, so define them only as a fallback for a
 * platform that supplies neither.
 *
 * This is protective rather than a fix for observed damage: the MSYS2 runtime
 * opens files in binary mode by default, so discarding the flag changes
 * nothing today.  A native Windows CRT defaults to text mode, where losing it
 * would open every DH data file in text mode and translate line endings in
 * binary records.
 */

#ifndef O_BINARY
#define O_BINARY 0
#endif
#ifndef O_TEXT
#define O_TEXT 0
#endif

/* 13 Aug 26 Windows port - O_ASYNC requests SIGIO on input arrival and has no
 * equivalent here.  linuxio.c uses it only to let io_handler() fill the type
 * ahead ring buffer early; keyin() and keyboard_pending() independently test
 * stdin with sdpoll() before reading, so input still works without it.  Defined
 * as zero so the fcntl() call still applies O_NONBLOCK.
 */

#ifndef O_ASYNC
#define O_ASYNC 0
#endif
#define FOPEN_READ_MODE "r"
#define FOPEN_WRITE_MODE "w"
#define NULL_DEVICE "/dev/null"

#define ALIGN2 __attribute__((aligned(2), packed))

#define MakeDirectory(path) mkdir(path, 0777)

#define SD_SHM_KEY 0x716d0301
#define SD_SEM_KEY 0x716d0302
/* To allow the SD  and other versions based on the same code
 * base tocoexist, SD has changed the third byte from 01 to 03
 */

/* System V IPC (shmget/semget) is not implemented by the MSYS2 runtime and
 * does not exist on native Windows, so this Windows port uses POSIX named
 * shared memory and named semaphores throughout.  The keys above are retained
 * only to derive the object names below and to keep on-disk formats identical
 * to the Linux build.
 */

#define SD_POSIX_SHM_NAME "/sd_shm_716d0301"
#define SD_POSIX_SEM_FMT  "/sd_sem_716d0302_%d"

/* 16 Aug 26 Windows port - THE SEMAPHORES ARE NATIVE Win32 OBJECTS NOW, and
 * the POSIX name above is kept only for removing sets left by older builds.
 *
 * WHY.  POSIX sem_open() on the MSYS2 runtime does not work in session 0: as
 * LocalSystem it BLOCKS FOR TEN SECONDS AND FAILS WITH ETIMEDOUT, measured
 * 16 Aug 2026 with the creator and the opener both SYSTEM in session 0, so it
 * is not a cross-session problem.  SD could therefore never run as a Windows
 * service, which the owner requires: a production system with nobody logged
 * in, available to every user from startup.  PROJECT_STATUS.md header item 1.
 *
 * "Global\" is the point of the exercise.  A service lives in session 0 and
 * its users in sessions 1 and up, and the Global namespace is what Windows
 * provides for exactly that.  A bare name would be session-local and would
 * reproduce the problem in a different form.
 *
 * The shared SEGMENT is deliberately left on POSIX shm_open(), which works
 * here: sdwind reached get_semaphores() in session 0, so it had already
 * mapped the segment.  Replacing what is not broken would widen the change
 * for nothing.
 */

#define SD_WIN32_SEM_FMT  "Global\\sd_sem_716d0302_%d"

/* 14 Aug 26 Windows port - the background daemon was sdlnxd, "SD Linux
 * daemon", which is the wrong name in a Windows-only repository.  Named once
 * here so that start_sd() and the daemon's own errlog prefix cannot drift
 * apart, and so a further rename is a single line.  No extension: execl() and
 * system() both append .exe on this runtime.
 */

#define SDWIND_NAME "sdwind"

/* 14 Aug 26 Windows port - A WINDOWS ADMINISTRATOR IS AN SD ADMINISTRATOR.
 * Decision from the repository owner; see PROJECT_STATUS.md 5.6.1.  This was a
 * private "sdadmins" group, on the reasoning that SD administration should be
 * grantable without handing out machine admin.  The installer never created
 * that group, so a clean machine got an install nobody could start.
 *
 * BUILTIN\Administrators is S-1-5-32-544, and Cygwin maps built-in SIDs to
 * their RID - so the gid is always 544, exactly as Users is 545.  IT IS
 * DELIBERATELY THE NUMBER AND NOT THE NAME: "Administrators" is renamed on a
 * localised Windows, so a lookup by name fails on a German or French machine.
 * sd.iss writes *S-1-5-32-544 to icacls for the same reason.
 *
 * Overridable so that the trick in PROJECT_STATUS.md 6 still works - build a
 * probe with a gid nobody holds to see the system as an ordinary user.
 *
 * 14 Aug 26 - TWO functions in linuxlb.c now test against this one gid, and
 * the difference between them is the access model: IsAdmin() asks the SAM
 * (getgrouplist) whether the account is an administrator, IsElevated() asks
 * the process token (getgroups) whether this session may act as one.
 */

/* 16 Aug 26 Windows port - the group that may USE SD, as opposed to the one
 * that administers it.  sd.iss creates it, CREATE.ACCOUNT adds every account
 * to it, and the ACL on C:\ProgramData\SD grants it (PROJECT_STATUS.md 5.6).
 * sdsem.c needs the name in C for the first time, to put the same group in the
 * security descriptor on the semaphores - otherwise SD starts as a service and
 * then refuses every user on the machine.
 *
 * BY NAME, WHERE SD_ADMIN_GID BELOW IS BY NUMBER, and the difference is not an
 * inconsistency: 544 is a well-known SID whose NAME is localised, whereas
 * sdusers is a name this port creates itself and is therefore the same on
 * every machine.
 */

#define SD_USERS_GROUP "sdusers"

#ifndef SD_ADMIN_GID
#define SD_ADMIN_GID 544
#endif

#define RelinquishTimeslice sched_yield()

/* WINFS denotes use of the Windows file system interface (PDA only so far) */

#define OSError errno
#define OSFILE int
#define INVALID_FILE_HANDLE -1
#define ValidFileHandle(fu) (fu >= 0)
#define CloseFile(fu) close(fu)
#define Read(fu, buff, bytes) (read(fu, buff, bytes))
#define Write(fu, buff, bytes) (write(fu, buff, bytes))

#ifndef DS
#error No environment set
#endif

/* 020240702 mab Max String Size */
/* Max String (record) size is capped at A little under 2Gb or available memory space     */
/* Remember SD is a 32 bit VM, so this limit is a product of the data structres           */
/* created and used by SD.                                                                */
/* The limit introduced here is an arbitrary size less than the  2Gb limit imposed by the */
/* by the VM, modify as you see fit                                                       */
#define MAX_STRING_SIZE   1073741822   /* 1/ GB, 1FFF FFFF */ 

#define MAX_PATHNAME_LEN 255    /* Changes affect file headers */

/* 14 Aug 26 Windows port - where the configuration file lives.
 *
 * ONE VARIABLE AND ONE FILE, for the server and the client alike.  The server
 * used to read SCARLET_CONFIG and fall back to /etc/sd.conf; the client read
 * SD_CONFIG and fell back to sd.ini in the Windows directory, with a comment
 * claiming the two matched.  They did not, so setting the variable you would
 * expect fixed one and not the other.
 *
 * The client library is a separate toolchain and does not include this header
 * (PROJECT_STATUS.md 5.2 - do not let the client's headers displace the
 * server's), so it carries its own copy of these two values.  If you change
 * them here, change gplsrc/sdclilib/sdclilib.c to match.
 */
#define SD_CONFIG_ENV     "SD_CONFIG"
#define SD_CONFIG_DEFAULT "C:\\ProgramData\\SD\\sd.conf"
#define MAX_ID_LEN 255          /* Increasing requires major file changes */
#define MAX_CALL_NAME_LEN 63    /* Cannot exceed MAX_ID_LEN */
#define MAX_TRIGGER_NAME_LEN 32 /* Increasing would alter file header */
#define MAX_PROGRAM_NAME_LEN 128
#define MAX_USERNAME_LEN 32
#define MAX_MATCH_TEMPLATE_LEN 256
#define MAX_MATCHED_STRING_LEN 8192
#define MAX_PACKAGES 32
#define MAX_PACKAGE_NAME_LEN 15
#define MAX_ACCOUNT_NAME_LEN 32
#define MAX_SORTMRG 10
#define MAX_SORT_KEYS 32
#define MAX_SORT_KEY_LEN 1024
/* 20240127 mab mods to handle AF_UNIX path length, defined in un.h as 108 characters  (108 + term char)*/
#define MAX_SOCKET_ADDR_STR_LEN 109

#define MAX_ERROR_LINES 3        /* because I HATE magic numbers! */
#define MAX_EMSG_LEN 80          /* These are used in k_error() in k_error.c */
/* 20240806 mab define sdext max arg */
#define SD_MAX_ARGS 10           /* max number of args passed by SDEXT function */ 
#define SD_ERR_MSG_LEN 512       /* max characters for error message */

#define Private static

#ifndef Public
#define Public extern
#endif

#ifndef init
#define init(a)
#endif

/* ======================================================================
   Type definitions                                                       */

typedef int16_t bool;
#define FALSE 0
#define TRUE 1

typedef int64_t int64;
typedef u_int64_t u_int64;

/* ======================================================================
   Byte ordering macros                                                   */

#ifdef BIG_ENDIAN_SYSTEM
short int swap2(int16_t n);
long int swap4(int32_t n);
#define ShortInt(n) swap2(n)
#define LongInt(n) swap4(n)
#else
#define ShortInt(n) (n)
#define LongInt(n) (n)
#endif

/* ======================================================================
   Case conversion macros and data                                        */

Public char uc_chars[256];
Public char lc_chars[256];
#define UpperCase(c) (uc_chars[((u_char)(c))])
#define LowerCase(c) (lc_chars[((u_char)(c))])

Public u_char char_types[256];
#define CT_ALPHA 0x01
#define CT_DIGIT 0x02
#define CT_GRAPH 0x04
#define CT_MARK 0x08
#define CT_DELIM 0x10

#define IsAlnum(c) (char_types[((u_char)(c))] & (CT_ALPHA | CT_DIGIT))
#define IsAlpha(c) (char_types[((u_char)(c))] & CT_ALPHA)
#define IsDigit(c) (char_types[((u_char)(c))] & CT_DIGIT)
#define IsGraph(c) (char_types[((u_char)(c))] & CT_GRAPH)
#define IsDelim(c) (char_types[((u_char)(c))] & CT_DELIM)
#define IsMark(c) (char_types[((u_char)(c))] & CT_MARK)

/* Collation map */

Public char* collation_map_name init(NULL);
Public char* collation init(NULL);

#define SortCompare(s1, s2, n, nocase) \
  ((nocase) ? MemCompareNoCase(s1, s2, n) : memcmp(s1, s2, n))

#define TEXT_MARK ((char)-5)
#define SUBVALUE_MARK ((char)-4)
#define VALUE_MARK ((char)-3)
#define FIELD_MARK ((char)-2)
#define ITEM_MARK ((char)-1)

#define U_TEXT_MARK ((u_char)'\xFB')
#define U_SUBVALUE_MARK ((u_char)'\xFC')
#define U_VALUE_MARK ((u_char)'\xFD')
#define U_FIELD_MARK ((u_char)'\xFE')
#define U_ITEM_MARK ((u_char)'\xFF')

#define TEXT_MARK_STRING "\xFB"
#define SUBVALUE_MARK_STRING "\xFC"
#define VALUE_MARK_STRING "\xFD"
#define FIELD_MARK_STRING "\xFE"
#define ITEM_MARK_STRING "\xFF"

#endif

/* END-CODE */
