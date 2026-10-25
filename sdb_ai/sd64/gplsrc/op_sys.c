/* OP_SYS.C
 * op_system()  -  SYSTEM() function.
 * Copyright (c) 2007 Ladybridge Systems, All Rights Reserved
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
 * 25 Oct 26 Windows port - from Linux 2287a0a (18 Oct 26): SYSTEM(1057) tested the parent's user NUMBER against max_users, the count of user table
 *           cells; user numbers run to hi_user_no (USERPOOL), so a phantom whose parent had number 694 on 20 cells was told "no parent".
 * 17 Aug 26  SYSTEM(91) "Windows?" answers 1, not 0
 * rev 0.9.1 Mar 25 mab return to single rev track
 * 02 Jul 24 mab add 9010 and 9011 
 * 31 Dec 23 SD launch - prior history suppressed
   
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *     1   Printer on?
 *     2   Default print unit page width
 *     3   Default print unit page depth
 *     4   Default print unit lines remaining on page
 *     5   Default print unit page number
 *     6   Default print unit line number
 *     7   @TERM.TYPE
 *     9   CPU time (mS)
 *    10   DATA queue active?
 *    11   Select list 0 active?
 *    12   Time (same as TIME())
 *    18   User number
 *    23   Break key enabled?
 *    24   Echo enabled?
 *    25   Phantom process?
 *    26   Prompt character
 *    27   UID   (not Windows)
 *    28   EUID  (not Windows)
 *    29   GID   (not Windows)
 *    30   EGID  (not Windows)
 *    31   Licence number
 *    32   System directory pathname
 *    38   Temporary directory pathname
 *    42   Client IP address
 *    91   Windows? (see also 1006)
 *  1000   CAPTURING in effect?
 *  1001   Case inversion on?
 *  1002   Call stack
 *  1003   Return list of open files
 *  1004   Peak number of open files
 *  1005   Internal time equivalent to DATE() * 86400 + TIME()
 *  1006   Windows NT style (NT, 2000, XP)?
 *  1007   Transaction number, zero if none
 *  1008   Transaction level, zero if none
 *  1009   Returns 1 on big endian system, 0 on little endian system
 *  1010   Platform name
 *  1011   sd.ini or sdconfig file pathname
 *  1012   SD version number
 *  1013   User limit (excluding phantom pool)
 *  1014   User limit (including phantom pool)
 *  1015   Computer name
 *  1016   Number of available users
 *  1017   Port number for tcp/ip connection
 *  1018   Device licensing ip address limit
 *  1019   Device licensing current ip address count
 *  1020   Time of day in milliseconds
 *  1021   Get collation map name
 *  1022   Get collation map (user format)
 *  1023   Get collation map (internal format)
 *  1024   Current directory on entry to SD
 *  1025   Environment variables
 *  1026   Command text from "sd xxx"
 *  1027   Port name for serial connection
 *  1028   System id code for system specific licences
 *  1029   Internal subroutine depth
 *  1030   Login time as date * 86400 + time
 *  1031   Operating system process id
 *  1032   Test and clear break pending flag
 *    35   Current number of users
 *  1043   CSV.MODE (1, 2 or 3)
 *  1045   Time SD was started, Unix epoch
 *  1046   CSV delimiter
 *  1047  Globally unique identifier
 *  9010   Return "SD"
 *  9011   Return MAX_STRING_SIZE - max string / record lenght
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "tio.h"
#include "syscom.h"
#include "dh_int.h"
#include "revstamp.h"
#include "config.h"

#include <time.h>
#include <sys/time.h>
#include <grp.h>

extern int txn_depth;
extern time_t clock_time; /* time.c: set by every call of local_time() */

void op_getprompt(void);
void op_sysdir(void);

/* ======================================================================
   op_system()  -  SYSTEM() function                                      */

void op_system() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Key                        |  SYSTEM() value             |
     |=============================|=============================|
 */

  DESCRIPTOR* descr;
  DESCRIPTOR* syscom_descr;
  int16_t key;
  PRINT_UNIT* pu;
  STRING_CHUNK* str;
  struct PROGRAM* prg;
  int32_t offset;
  FILE_ENTRY* fptr;
  int16_t i;
  char s[256 + 1] = "";
  char* p;
  char* q;

  struct timeval tv;

  descr = e_stack - 1;
  GetInt(descr);
  key = (int16_t)(descr->data.value);

  switch (key) {
    case 1: /* Printer on? */
      descr->data.value = (process.program.flags & PF_PRINTER_ON) != 0;
      break;

    case 2: /* Default print unit page width */
      pu = (process.program.flags & PF_PRINTER_ON) ? (&tio.lptr_0) : (&tio.dsp);
      descr->data.value = pu->width;
      break;

    case 3: /* Default print unit page depth */
      pu = (process.program.flags & PF_PRINTER_ON) ? (&tio.lptr_0) : (&tio.dsp);
      descr->data.value = pu->lines_per_page;
      break;

    case 4: /* Default print unit lines remaining on page */
      if (process.program.flags & PF_PRINTER_ON) {
        descr->data.value = tio.lptr_0.data_lines_per_page - tio.lptr_0.line;
      } else {
        descr->data.value = tio.dsp.data_lines_per_page - tio.dsp.line - 1;
        /* Allow one line for pagination prompt */
      }
      break;

    case 5: /* Default print unit page number */
      pu = (process.program.flags & PF_PRINTER_ON) ? (&tio.lptr_0) : (&tio.dsp);
      descr->data.value = pu->page_no;
      break;

    case 6: /* Default print unit line number */
      pu = (process.program.flags & PF_PRINTER_ON) ? (&tio.lptr_0) : (&tio.dsp);
      descr->data.value =
          (pu->line >= pu->data_lines_per_page) ? 1 : (pu->line + 1);
      break;

    case 7: /* Terminal type - Same as @TERM.TYPE */
      k_put_c_string(tio.term_type, descr);
      break;

    case 9: /* Process CPU time (mS) */

      descr->data.value = (clock() * 1000) / CLOCKS_PER_SEC;
      break;

    case 10: /* DATA queue active? */
      syscom_descr = Element(process.syscom, SYSCOM_DATA_QUEUE);
      descr->data.value = (syscom_descr->data.str.saddr != NULL);
      break;

    case 11: /* Select list 0 active? */
      syscom_descr = SelectList(0);
      descr->data.value = (syscom_descr->data.str.saddr != NULL);
      break;

    case 12: /* Time - Same as TIME() */
      descr->data.value = local_time() % 86400L;
      break;

    case 13: /* Relinquish timeslice: nothing to give up, always 1 (openQM manual) */
      descr->data.value = 1;
      break;

    case 16: /* Command processor level, same as @LEVEL (openQM manual) */
      descr->data.value = cproc_level;
      break;

    case 18: /* User number */
    case 22: /* User number, same as @USERNO (openQM manual; 18 is the older Ladybridge key) */
      descr->data.value = my_uptr->uid;
      break;

    case 23: /* Break key enabled? */
      descr->data.value = (process.break_inhibits == 0);
      break;

    case 24: /* Echo enabled? */
      syscom_descr = Element(process.syscom, SYSCOM_ECHO_INPUT);
      descr->data.value = syscom_descr->data.value;
      break;

    case 25: /* Phantom process? */
      descr->data.value = is_phantom;
      break;

    case 26: /* Prompt character */
      k_dismiss();
      op_getprompt();
      break;

    case 27: /* UID */
      descr->data.value = getuid();
      break;

    case 28: /* Effective UID */
      descr->data.value = geteuid();
      break;

    case 29: /* GID */
      descr->data.value = getgid();
      break;

    case 30: /* Effective GID */
      descr->data.value = getegid();
      break;

    case 31: /* Licence number */
      descr->data.value = 0;
      /* If there is ever a need, programs can use this to determine whether
         they are running on the GPL version of the product.
         DO NOT ALTER THE RETURNED VALUE                                     */
      break;

    case 32: /* System directory pathname */
      k_dismiss();
      op_sysdir();
      break;

    case 38: /* Temporary directory pathname */
      k_put_c_string(pcfg.tempdir, descr);
      break;

    case 42: /* IP address */
      k_put_c_string(ip_addr, descr);
      break;

    case 91: /* Windows? */
      /* 17 Aug 26  ANSWERS 1 ON THIS PORT.  It answered 0, which was inherited
         from sdb64 where it is correct, and left every BASIC program that asks
         "am I on Windows" being told no - on Windows.

         WHAT THAT ACTUALLY BROKE, and it is not cosmetic.  QPROC:82 reads this
         into is.windows and QPROC:499 is

             if is.windows and is.dir then is.case.insensitive = @true

         which is the ONLY route by which the query processor treats a
         directory file's ids as case insensitive - FL$FLAGS cannot supply it,
         because op_dio2.c:439 answers FL_FLAGS only when (dynamic && internal)
         and a directory file is neither.  So SELECT ... WITH @ID = "sue" never
         matched record SUE, and the code to make it match has been sitting
         there unreachable.  Same shape as CASE_INSENSITIVE_FILE_SYSTEM at
         dh_open.c:529: correct code, already written, never switched on.

         is.case.insensitive upper-cases BOTH SIDES OF A COMPARISON only
         (QPROC 4034, 4447, 7059, 7198) and stores nothing, so this is the same
         strategy taken there and not the upper-casing 5.12 rejected.

         The only other reader is APISRVR:954, which is commented out. */
      descr->data.value = 1;
      break;

    case 1000: /* CAPTURING in effect? */
      descr->data.value = capturing;
      break;

    case 1001: /* Case inversion on? */
      descr->data.value = case_inversion;
      break;

    case 1002: /* Call stack */
      str = NULL;
      ts_init(&str, 1024);
      if (c_base != NULL) {
        prg = &(process.program);
        offset = pc - c_base;
        do {
          ts_printf("%s%c%d%c%d", ProgramName(prg->saved_c_base), VALUE_MARK,
                    offset, SUBVALUE_MARK,
                    k_line_no(offset, prg->saved_c_base));

          /* Local gosub return pointers
               Back up to point to GOSUB rather than to return address */

          for (i = prg->gosub_depth - 1; i >= 0; i--) {
            offset = prg->gosub_stack[i] - 1; /* Back up to GOSUB (etc) */
            ts_printf("%c%d%c%d", VALUE_MARK, offset, SUBVALUE_MARK,
                      k_line_no(offset, prg->saved_c_base));
          }

          if ((prg = prg->prev) == NULL)
            break;

          offset = prg->saved_pc_offset - 1; /* Back up into CALL */
          ts_printf("%c", FIELD_MARK);
        } while (1);
      }
      ts_terminate();
      InitDescr(descr, STRING);
      descr->data.str.saddr = str;
      break;

    case 1003: /* Return list of open files */
      str = NULL;
      ts_init(&str, 1024);

      for (i = 1, fptr = FPtr(1); i <= sysseg->used_files; i++, fptr++) {
        if (fptr->ref_ct) {
          if (str != NULL)
            ts_copy_byte(FIELD_MARK);
          ts_printf("%d\xfd%s", (int)i, fptr->pathname);
        }
      }

      ts_terminate();
      InitDescr(descr, STRING);
      descr->data.str.saddr = str;
      break;

    case 1004: /* Return peak number of open files */
      descr->data.value = sysseg->used_files;
      break;

    case 1005: /* Internal time - Equivalent to DATE() * 86400 + TIME() */
      descr->data.value = sdtime();
      break;

    case 1006: /* Windows NT style? */
      descr->data.value = is_nt;
      break;

    case 1007: /* Transaction number */
      descr->data.value = process.txn_id;
      break;

    case 1008: /* Transaction level */
      descr->data.value = txn_depth;
      break;

    case 1009: /* Endian */
#ifdef BIG_ENDIAN_SYSTEM
      descr->data.value = 1;
#else
      descr->data.value = 0;
#endif
      break;

    case 1010: /* Platform name */
      k_put_c_string(PLATFORM_NAME, descr);
      break;

    case 1011: /* Full path of sd.ini or sdconfig file */
      k_put_c_string(config_path, descr);
      break;

    case 1012: /* SD version number */
//      k_put_c_string(Q_M_REV_STAMP, descr);
/* rev 0.9.1 */  
		  k_put_c_string(SD_REV_STAMP, descr);
      break;

    case 1013: /* User limit, excluding phantom pool */
    case 1014: /* User limit, including phantom pool */
      descr->data.value = sysseg->max_users;
      break;

    case 1015: /* Computer name */
      gethostname(s, 100);
      k_put_c_string(s, descr);
      break;

    case 1017: /* Port number for tcp/ip connection */
      descr->data.value = port_no;
      break;

    case 1020: /* Time of day in milliseconds */
      gettimeofday(&tv, NULL);
      descr->data.value = (tv.tv_sec % 86400) * 1000 + (tv.tv_usec / 1000);
      break;

    case 1021: /* Get collation map name */
      k_put_c_string(collation_map_name, descr);
      break;

    case 1022: /* Get collation map (user format) */
      if (collation != NULL) {
        /* Transform map back to "source" form */
        for (i = 0; i < 256; i++)
          s[(u_char)collation[i]] = i;
        k_put_string(s, 256, descr);
      } else
        k_put_string("", 0, descr);
      break;

    case 1023: /* Get collation map (internal format) */
      k_put_string(collation, 256, descr);
      break;

    case 1024: /* Current directory on entry to SD */
      k_put_c_string(entry_dir, descr);
      break;

    case 1025: /* Environment variables */
      str = NULL;
      ts_init(&str, 1024);
      for (i = 0; (p = environ[i]) != NULL; i++) {
        if (i)
          ts_copy_byte(VALUE_MARK);
        q = strchr(p, '=');
        if (q != NULL)
          ts_copy(p, q - p);
      }

      ts_copy_byte(FIELD_MARK);

      for (i = 0; (p = environ[i]) != NULL; i++) {
        if (i)
          ts_copy_byte(VALUE_MARK);
        q = strchr(p, '=');
        if (q != NULL)
          ts_copy_c_string(q + 1);
      }
      ts_terminate();
      InitDescr(descr, STRING);
      descr->data.str.saddr = str;
      break;

    case 1026:
      k_put_c_string(single_command, descr);
      break;

    case 1027: /* Serial port name */
      k_put_c_string(port_name, descr);
      break;

    case 1028: /* System id */
      /* Recognised but returns zero on GPL source */
      break;

    case 1029: /* Internal subroutine depth */
      descr->data.value = process.program.gosub_depth;
      break;

    case 1030: /* Login time */
      descr->data.value = my_uptr->login_time;
      break;

    case 1031: /* Operating system process id */
      descr->data.value = my_uptr->pid;
      break;

    case 35:   /* Current number of users (openQM 3.4-17, item 586) */
    case 1016: /* Number of available users */
      i = 0;
      {
        int16_t u;
        for (u = 1; u <= sysseg->max_users; u++) {
          if (UPtr(u)->uid > 0)
            i++;
        }
      }
      descr->data.value = (key == 35) ? i : ((sysseg->max_users > i) ? (sysseg->max_users - i) : 0);
      break;

    case 1043: /* CSV.MODE: 1, 2 or 3 (openQM item 173) */
      descr->data.value = process.program.csv_mode;
      break;

    case 1046: /* The CSV delimiter set by CSV.MODE, a comma by default (openQM item 200) */
      s[0] = process.program.csv_delim;
      s[1] = '\0';
      k_put_c_string(s, descr);
      break;

    case 1045: /* Time at which SD was started, as a Unix epoch value (openQM item 192) */
      descr->data.value = (int32_t)sysseg->start_time;
      break;

    case 1047: /* Globally unique identifier (openQM item 244): a random (version 4) uuid, lower case.
                  Linux reads the kernel's /proc/sys/kernel/random/uuid; the MSYS2 runtime has no such
                  file, so the 16 bytes come from /dev/urandom (18 Oct 26, Windows port). */
      {
        unsigned char ub[16];
        FILE* fu = fopen("/dev/urandom", "rb");
        s[0] = '\0';
        if (fu != NULL) {
          if (fread(ub, 1, 16, fu) == 16) {
            ub[6] = (unsigned char)((ub[6] & 0x0f) | 0x40); /* version 4 */
            ub[8] = (unsigned char)((ub[8] & 0x3f) | 0x80); /* variant 1 */
            snprintf(s, 40, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", ub[0], ub[1],
                     ub[2], ub[3], ub[4], ub[5], ub[6], ub[7], ub[8], ub[9], ub[10], ub[11], ub[12], ub[13], ub[14],
                     ub[15]);
          }
          fclose(fu);
        }
        k_put_c_string(s, descr);
      }
      break;

    /* ---- 12 Oct 26 dm: more of the openQM 4 SYSTEM() keys (sheet B-2 part 2).  Numbers and meanings are the
       manual's.  Those that name a feature SD does not have answer as openQM does without it. ---- */

    case 33: /* Name of the program that called this subroutine (openQM item 308) */
      k_put_c_string((process.program.prev != NULL) ? (char*)ProgramName(process.program.prev->saved_c_base) : "",
                     descr);
      break;

    case 1019: /* Offset in seconds of the local time zone from UTC, negative west of Greenwich */
      {
        int32_t lt = local_time(); /* which sets clock_time, so it must be called first */

        descr->data.value = lt - (int32_t)clock_time;
      }
      break;

    case 1033: /* COMO file active? */
      descr->data.value = ValidFileHandle(tio.como_file) ? 1 : 0;
      break;

    case 1034: /* COMO output suspended?  SD's COMO cannot be suspended */
    case 1044: /* ECS mode?  SD is English only */
    case 1051: /* USB installation? */
    case 1080: /* Started from a Proc?  SD has no Procs */
      descr->data.value = 0;
      break;

    case 1040: /* Operating system file names case insensitive?  18 Oct 26 Windows port: YES -
                  NTFS, which Linux's answer (0) does not describe */
      descr->data.value = 1;
      break;

    case 1035: /* Seconds since 1 Jan 1970 UTC, independent of the time zone (EPOCH()) */
      descr->data.value = (int32_t)time(NULL);
      break;

    case 1038: /* Login time as an epoch value.  The login time is held in the local clock, so it is moved back by
                  the zone's offset now (a login either side of a change to or from summer time is an hour out) */
      {
        int32_t lt = local_time(); /* which sets clock_time, so it must be called first */

        descr->data.value = my_uptr->login_time - (732 * 86400L) - (lt - (int32_t)clock_time);
      }
      break;

    case 1037: /* Every open file and the users that have it open: file number VM pathname VM user numbers (SM) */
      str = NULL;
      ts_init(&str, 1024);
      StartExclusive(FILE_TABLE_LOCK, 78);
      for (i = 1, fptr = FPtr(1); i <= sysseg->used_files; i++, fptr++) {
        if (fptr->ref_ct) {
          int16_t hu;
          bool first = TRUE;
          USER_ENTRY* huptr;

          if (str != NULL)
            ts_copy_byte(FIELD_MARK);
          ts_printf("%d%c%s%c", (int)i, VALUE_MARK, fptr->pathname, VALUE_MARK);
          for (hu = 1; hu <= sysseg->max_users; hu++) {
            huptr = UPtr(hu);
            if ((huptr->uid <= 0) || (*UFMPtr(huptr, i) == 0))
              continue;
            if (!first)
              ts_copy_byte(SUBVALUE_MARK);
            ts_printf("%d", (int)(huptr->uid));
            first = FALSE;
          }
        }
      }
      EndExclusive(FILE_TABLE_LOCK);
      ts_terminate();
      InitDescr(descr, STRING);
      descr->data.str.saddr = str;
      break;

    case 1052: /* Number of direct child phantom processes */
    case 1058: /* Their user numbers, field mark delimited */
    case 1073: /* The user numbers of those grouped with this process (PHANTOM GROUP), field mark delimited */
      str = NULL;
      if (key != 1052)
        ts_init(&str, 64);
      i = 0;
      {
        int16_t hu;
        USER_ENTRY* huptr;

        for (hu = 1; hu <= sysseg->max_users; hu++) {
          huptr = UPtr(hu);
          if ((huptr->uid > 0) && (huptr->puid == process.user_no) && (huptr->flags & USR_PHANTOM) &&
              ((key != 1073) || huptr->grouped)) {
            if (key != 1052) {
              if (i > 0)
                ts_copy_byte(FIELD_MARK);
              ts_printf("%d", (int)(huptr->uid));
            }
            i++;
          }
        }
      }
      if (key != 1052) {
        ts_terminate();
        InitDescr(descr, STRING);
        descr->data.str.saddr = str;
      } else {
        descr->data.value = i;
      }
      break;

    case 1066: /* The last form queue number SP.ASSIGN assigned to any print unit; -1 if it has not been used */
      descr->data.value = last_form_queue;
      break;

    case 1053: /* Highest user number that can be assigned: the greater of USERPOOL and the licence's users */
      descr->data.value = sysseg->hi_user_no;
      break;

    case 1036: /* How long this login waited for a spare user entry, in tenths of a second (LGNWAIT) */
      descr->data.value = login_delay;
      break;

    case 1055: /* LGNWAIT statistics: logins delayed, delayed ones that got in, waiting now, peak waiting, given up */
      {
        unsigned lg[5];

        StartExclusive(SHORT_CODE, 80);
        lg[0] = sysseg->lgn_delayed;
        lg[1] = sysseg->lgn_success;
        lg[2] = sysseg->lgn_waiting;
        lg[3] = sysseg->lgn_peak;
        lg[4] = sysseg->lgn_failed;
        EndExclusive(SHORT_CODE);

        str = NULL;
        ts_init(&str, 64);
        ts_printf("%u%c%u%c%u%c%u%c%u", lg[0], FIELD_MARK, lg[1], FIELD_MARK, lg[2], FIELD_MARK, lg[3], FIELD_MARK, lg[4]);
        ts_terminate();
      }
      InitDescr(descr, STRING);
      descr->data.str.saddr = str;
      break;

    case 1056: /* 14 Oct 26 - sheet item 38 (LISTU DETAIL), openQM SYS$USER.COUNTS: the user counts as a field mark delimited
                  array: interactive users, API (the QMClient count) sessions, interactive phantoms that count as
                  licensed (USR_CHGPHANT: SD has no licence, so the flag is only ever set by what sets it), other
                  phantoms, and the peak number of users at once since SD started.  Counted from the user table.   */
      {
        unsigned cnt[5] = {0, 0, 0, 0, 0};
        int16_t ui;
        USER_ENTRY *up;

        StartExclusive(SHORT_CODE, 81);
        for (ui = 1; ui <= sysseg->max_users; ui++) {
          up = UPtr(ui);
          if (up->uid <= 0)
            continue;
          /* A phantom's cell is reserved by its parent (puid set) a moment before the phantom itself starts and sets
             USR_PHANTOM, so a cell with a parent is a phantom too.                                              */
          if ((up->flags & USR_PHANTOM) || (up->puid != 0))
            cnt[(up->flags & USR_CHGPHANT) ? 2 : 3]++;
          else if (up->flags & (USR_SDAPISRVR | USR_SDNET))
            cnt[1]++;
          else
            cnt[0]++;
        }
        cnt[4] = sysseg->users_peak;
        EndExclusive(SHORT_CODE);

        str = NULL;
        ts_init(&str, 64);
        ts_printf("%u%c%u%c%u%c%u%c%u", cnt[0], FIELD_MARK, cnt[1], FIELD_MARK, cnt[2], FIELD_MARK, cnt[3], FIELD_MARK, cnt[4]);
        ts_terminate();
      }
      InitDescr(descr, STRING);
      descr->data.str.saddr = str;
      break;

    case 1072: /* The IP address SD listens on: sdwind.c's API listener binds INADDR_ANY, so null (all addresses) */
      k_put_c_string("", descr);
      break;

    case 1054: /* Active packages: SD has none */
      k_put_c_string("", descr);
      break;

    case 1057: /* Parent process user number, zero if this is not a phantom or the parent has gone */
      {
        int16_t pu = my_uptr->puid;
        USER_ENTRY* puptr;

        descr->data.value = 0;
        /* 18 Oct 26 Windows port - the bound is the highest user NUMBER (hi_user_no), as for key 1053, not the number of cells
           (max_users): a user number is up to USERPOOL, 1023 by default, and the first run found a phantom answering 0 for its
           parent 694 on a system of 20 cells.  Told to Linux, whose suite never sees a number above NUMUSERS. */
        if ((pu > 0) && (pu <= sysseg->hi_user_no) && ((puptr = UserPtr(pu)) != NULL) && (puptr->uid == pu))
          descr->data.value = pu;
      }
      break;

    case 1065: /* The transaction cache, one cached write or delete to a field */
      {
        STRING_CHUNK* rep = txn_cache_report();

        InitDescr(descr, STRING);
        descr->data.str.saddr = rep;
      }
      break;

    case 1070: /* The current PRECISION setting */
      descr->data.value = process.program.precision;
      break;

    case 1076: /* Current CALL depth */
      {
        struct PROGRAM* cp;

        i = 0;
        for (cp = process.program.prev; cp != NULL; cp = cp->prev)
          i++;
        descr->data.value = i;
      }
      break;

    case 1077: /* Names of the groups the user belongs to, field mark delimited */
    case 1078: /* And their numbers */
      {
        gid_t groups[256];
        int ng = getgroups(256, groups);
        int gi;
        bool have_egid = FALSE;
        struct group* gr;

        str = NULL;
        ts_init(&str, 128);
        for (gi = 0; gi < ng; gi++) {
          if (groups[gi] == getegid())
            have_egid = TRUE;
        }
        if (ng < 0)
          ng = 0;
        for (gi = 0; gi < ng + (have_egid ? 0 : 1); gi++) {
          gid_t g = (gi < ng) ? groups[gi] : getegid();

          if (gi > 0)
            ts_copy_byte(FIELD_MARK);
          if (key == 1078) {
            ts_printf("%d", (int)g);
          } else if ((gr = getgrgid(g)) != NULL) {
            ts_printf("%s", gr->gr_name);
          } else {
            ts_printf("%d", (int)g);
          }
        }
        ts_terminate();
        InitDescr(descr, STRING);
        descr->data.str.saddr = str;
      }
      break;

    case 1081: /* Epoch time in milliseconds */
      gettimeofday(&tv, NULL);
      InitDescr(descr, FLOATNUM);
      descr->data.float_value = ((double)tv.tv_sec * 1000.0) + (double)(tv.tv_usec / 1000);
      break;

    case 1082: /* Time of day in milliseconds since midnight, local time */
      gettimeofday(&tv, NULL);
      descr->data.value = ((local_time() % 86400L) * 1000) + (tv.tv_usec / 1000);
      break;

    case 1083: /* The last deadlock this process was in (openQM item 587): a field
                  for each process, user number VM file pathname VM record id,
                  the id left out for a file lock.  Null if there has been none. */
      {
        int dl_len;
        char* dl = deadlock_info_string(&dl_len);

        if (dl_len == 0) {
          k_put_c_string("", descr);
        } else {
          k_put_c_string(dl, descr);
        }
      }
      break;

    case 1032: /* Test and clear break pending flag */
      descr->data.value = break_pending;
      break_pending = FALSE;
      break;
    /* njs 13Feb23 */  
    case 1050: /* admin flag user */
      descr->data.value = (my_uptr->flags & USR_ADMIN) != 0;
      break;  

    case 9010: /* SD */
      k_put_c_string("SD", descr);
      break;

    case 9011: /*MAX_STRING_SIZE */
      descr->data.value = MAX_STRING_SIZE;
      break;

    case 9016: /* @SEQNO: number of the last NEXT hold file this process made, null if none */
      k_put_c_string(last_seqno, descr);
      break;

    case 9012: /* @EXCEPTION */
    case 9013: /* @EXCEPTION.DATA */
    case 9014: /* @EXCEPTION.ORIGIN */
    case 9015: /* @EXCEPTION.STACK */
      exc_value(key - 9012, descr);
      break;

    /* ---- 15 Oct 26 dm: QM4 gaps bundle Q-18, more of the openQM 4 SYSTEM() keys, by the manual's numbers ---- */

    case 14: /* Characters waiting to be read from the terminal; a snapshot for piped input, as the manual says */
      descr->data.value = type_ahead_count();
      break;

    case 19: /* A value from the internal date and time as two five digit numbers.  A second one in the same second, from any
                process, gets a letter on the end (a, b ... z, aa ...).  The time is the process's local time, so the value
                can repeat between users in different time zones, which the manual warns of as well. */
      {
        int32_t it = (int32_t)sdtime();
        u_int32_t dup;
        char rev[8];
        int k = 0;
        int j;

        StartExclusive(SHORT_CODE, 211);
        if (it == sysseg->uniq19_secs) {
          dup = ++(sysseg->uniq19_n);
        } else {
          sysseg->uniq19_secs = it;
          sysseg->uniq19_n = 0;
          dup = 0;
        }
        EndExclusive(SHORT_CODE);

        snprintf(s, sizeof(s), "%05d%05d", (int)(it / 86400), (int)(it % 86400));
        while (dup > 0 && k < (int)sizeof(rev)) { /* bijective base 26: 1 is a, 26 is z, 27 is aa */
          rev[k++] = (char)('a' + ((dup - 1) % 26));
          dup = (dup - 1) / 26;
        }
        p = s + strlen(s);
        for (j = k - 1; j >= 0; j--)
          *(p++) = rev[j];
        *p = '\0';
        k_put_c_string(s, descr);
      }
      break;

    case 20: /* The number of print jobs passed to the operating system spooler since SD started, all sessions: the last job's
                reference as a count.  (The spooler's own job id is not read back: a site's spooler is whatever it names.) */
      descr->data.value = (int32_t)__atomic_load_n(&sysseg->print_jobs, __ATOMIC_SEQ_CST);
      break;

    case 21: /* A value from the internal date and a sequence number that starts again at 1 each day, as two five digit numbers */
      {
        int32_t today = (int32_t)(sdtime() / 86400);
        u_int32_t seq;

        StartExclusive(SHORT_CODE, 212);
        if (today != sysseg->uniq_date) {
          sysseg->uniq_date = today;
          sysseg->uniq_seq = 0;
        }
        seq = ++(sysseg->uniq_seq);
        EndExclusive(SHORT_CODE);
        snprintf(s, sizeof(s), "%05d%05u", (int)today, (unsigned)seq);
        k_put_c_string(s, descr);
      }
      break;

    case 45: /* The name of the running program, from its object code: its catalogue name when it was catalogued under the
                name it was compiled with, which is how SD names them */
      k_put_c_string((char*)ProgramName(c_base), descr);
      break;

    case 1048: /* A sequence number that is unique across all sessions until SD is restarted, then 1 again */
      StartExclusive(SHORT_CODE, 213);
      descr->data.value = (int32_t)(++(sysseg->rolling_seq));
      EndExclusive(SHORT_CODE);
      break;

    case 1049: /* Is HUSH in effect? */
      descr->data.value = (tio.hush != 0);
      break;

    case 1062: /* SYS$SIGNAMMED: has SIGNAL() been raised for this process?  Reading it clears it */
      /* One atomic step, as another process may be setting this or another bit of flags at the moment */
      descr->data.value = ((__atomic_fetch_and(&my_uptr->flags, (int16_t)~USR_SIGNAL, __ATOMIC_SEQ_CST) & USR_SIGNAL) != 0);
      break;

    case 1067: /* The default group size of a dynamic file, in bytes */
      descr->data.value = DEFAULT_GROUP_SIZE * DH_GROUP_MULTIPLIER;
      break;

    case 1088: /* SYS$MAXMINPOS: the position of the element MAXIMUM() or MINIMUM() last returned, as field, value and subvalue numbers
                  joined by value marks; a null string when it had no element */
      k_put_c_string(maxmin_pos, descr);
      break;

    case 1086: /* Is case sensitivity of string comparisons on in this program?  Off is $NOCASE.STRINGS or CASING OFF */
      descr->data.value = ((process.program.flags & HDR_NOCASE) == 0);
      break;

    default:
      k_recurse(pcode_system, 1); /* Execute recursive code */
      break;
  }
}

/* END-CODE */
