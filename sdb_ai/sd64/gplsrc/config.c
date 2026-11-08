/* CONFIG.C
 * Configuration file processing
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
 * 8 Nov 26 Windows port - from Linux 2930d92f (S.87): FILERULE is gone, with the Account:File and PATH:pathname forms of file name; the installer
 *           strips the line from a kept sd.conf (sd.iss RemoveRetiredConf).
 * 06 Oct 26 Windows port - APILOGIN is retired: accepted and ignored, not
 *           stored (parity audit PAW-5; Linux's S.18)
 * 01 Oct 26 Windows port - BACKUPDIR is accepted (and not stored), so the line
 *           SET.BACKUP.DIRECTORY writes does not stop SD starting
 * 01 Oct 26 Windows port - APIPORT is an ON/OFF switch: any value above zero
 *           means the fixed port SD_API_PORT (owner's port ruling)
 * 19 Oct 26 Windows port - from Linux 0bdc4bd - NETWAIT (5) and NETREPLY (30): the two SDNet timeouts, seconds, 1 to 3600, per process (K8d, S.65).  Zero is refused (openQM's NETWAIT 0 means no limit).
 * 19 Oct 26 Windows port - from Linux d93ea0d - NETWAIT and NETREPLY are held in 32 bit fields (config.h): 65541 in sd.conf wrapped to 5 in the 16 bit field BEFORE rangecheck, so SD started with a 5 second wait instead of
 * 24 Oct 26 Windows port - from Linux 2a68b2f - W.11 F9: sd_sysdir() and sd_sysdir_trust(), the system directory a process trusts, from this file and not from the shared segment.
 *               refusing the value.  (PWDELAY and DHCACHE are 16 bit fields read the same way and wrap the same way; they are not changed here.)
 * 14 Sep 26 Windows port - the global catalogue check names gcat/$cproc
 *           (RELEASE_1.1 5 stage 3a)
 * 31 Dec 23 SD launch - prior history suppressed
 * 8 Nov 26 Windows port - from Linux 843344ba (S.87 batch 15): the parameters CODEPAGE, CREATUSR, EXCLREM, GDI, RINGWAIT, TXCHAR, APILOGIN,
 *           FIXUSERS, JNLDIR, JNLMODE, PORTMAP (and INVCASE, batch 14) are no longer read; a line naming one stops SD, so the installer
 *           removes them from a kept sd.conf.  APILOGIN and CREATUSR were accepted and ignored here; now they are unknown like the rest.
 * rev 0.9.0 Jan 25 mab add CREATUSR - allow create.account to create os user (removed 8 Nov 26)
 * 18 Oct 26 Windows port - from Linux fa146d9 (16 Oct 26): NUMLOCKS is range checked, 1 to 32767 (QM4 Fixes 532): the lock table's cells and counts are int16, so a bigger value wrapped.
 * 18 Oct 26 Windows port - from Linux 7f7a4fd (16 Oct 26): CLEANUP (seconds between scans for lost processes) and PHANTOMS (user numbers reserved for PHANTOM USER n), QM4 gaps.
 * 18 Oct 26 Windows port - from Linux 3b43525 (15 Oct 26): USPLIT (QM4 gaps Q-19): interactive users take the lowest user number, other processes the highest.
 * 16 Aug 26 Windows port - CREATUSR is gone.  The line was accepted and
 *           discarded until 8 Nov 26 (see the top line).
 * START-DESCRIPTION:
 *
 * Handles parsing of the configuration file.
 * 
 *  CLEANUP=n     Seconds between scans for processes that ended abnormally, 30 to 3600 (default 300)
 *  PHANTOMS=u,n  n user numbers from u are kept for phantoms started with PHANTOM USER
 *  DEADLOCK=n    Trap deadlocks?
 *  DEBUG=n       Debug features enabled? (bit flags)
 *  FDS=n         Set FDS limit (default is no limit)
 *  FLTDIFF=f     Wide zero value
 *  GRPSIZE=n     Default group size when creating a dynamic file
 *  MAXIDLEN=63   Maximum record id len
 *  MUSTLOCK=1    Must hold update or file lock to write or delete record
 *  NETDIRS=p;p   Directories a network session may reach outside its account
 *  NETFILES=0    Allow remote files?
 *                  0x0001   Allow outgoing NFS
 *                  0x0002   Allow incoming Q_M_Net
 *  NETWAIT=5     Seconds to wait for a connection to a remote SDNet server (1 to 3600)
 *  NETREPLY=30   Seconds to wait for each reply of a remote SDNet server (1 to 3600)
 *  NUMFILES=n    Maximum number of files open (all users)
 *  NUMLOCKS=n    Maximum number of record locks
 *  OBJECTS=n     Limit on loaded object code count (0 = no limit)
 *  OBJMEM=n      Limit on locade object size (kb, 0 = no limit)
 *  SDCLIENT=n    SDClient rules (0=all, 1=no call/exec, 2=restricted call)
 *  SCREENTHEME=name  The screen library's default theme: mono, classic or blue (default none = mono)
 *  SDSYS=path    SDSYS directory path
 *  SAFEDIR=1     Use careful update to directory files
 *  SORTMEM=n     Threshold for disk based sort (units of 1kb)
 *  SORTWORK=path Pathname of sort workfile directory
 *  STARTUP=cmd   (REMOVED 6 Oct 2026 - refused by name if present)
 *  TEMPDIR=path  Pathname of temporary directory
 *  TERMINFO=path Pathname of terminfo directory
 *  YEARBASE=n    Two digit year base (default = 1930)
 *
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "config.h"
#include "revstamp.h"
#include <time.h>
#include <sys/utsname.h>

Private bool rangecheck(char* param,
                        int value,
                        int min_val,
                        int max_val,
                        char* errmsg);

/* ====================================================================== */

struct CONFIG* read_config(char* errmsg) {
  FILE* fu;
  char path[MAX_PATHNAME_LEN + 1];
  char rec[200 + 1];
  char section[32 + 1] = "";
  char* p;
  struct CONFIG* cfg;
  double flt;
  int n;
  int numlocks_asked = 100; /* NUMLOCKS as written: cfg->numlocks is int16 and would wrap before it was checked */
  bool status = FALSE;
  int n2;
  int hi_user;
  struct stat statbuf;

  cfg = (struct CONFIG*)k_alloc(1, sizeof(struct CONFIG));
  if (cfg == NULL) {
    sprintf(errmsg, "Unable to allocate CONFIG memory.");
    return NULL;
  }

  memset((char*)cfg, 0, sizeof(struct CONFIG));

  /* Set defaults for private configuration parameters */
  /* !!CONFIG!! */

  pcfg.dhcache = 10;      /* DHCACHE:  Closed dynamic files kept open: the fixed 10 until 1.2-0 (openQM item 90) */
  pcfg.dumpdir[0] = '\0'; /* DUMPDIR:  Directory for process dump files */
  pcfg.fltdiff = 0.0000000000291; /* FLTDIFF: Wide zero for float eq test */
  pcfg.fsync = 0;                 /* FSYNC:    Controls when to do fsync() */
 /* 20240219 mab create-account based on type (user / group / other) */
 /* 13 Aug 26 Windows port - accounts live beside the rest of SD's data under
    C:\ProgramData\SD.  /home/sd was the right place while an SD account was
    an operating system user; under the credential model it is not one, so
    the Linux location decides nothing.  See PROJECT_STATUS.md section 5.8.
    Drive letters and backslashes only became usable when sdrealpath() was
    taught to accept them - see the note there.                            */
  strncpy(pcfg.grpdir,"C:\\ProgramData\\SD\\group_accounts",MAX_PATHNAME_LEN+1);  /* GRPDIR: group accounts parent dir */
  pcfg.grpsize = 1;               /* GRPSIZE:  Default group size */
  pcfg.intprec = 11;              /* INTPREC:  Precision for INT() etc. 13 until 1.2-0 (openQM 2.6-9, item 6) */
  pcfg.lptrhigh = 66;             /* LPTRHIGH: Default printer lines */
  pcfg.lptrwide = 80;             /* LPTRWIDE: Default printer width */
  pcfg.maxcall = 10000;           /* MAXCALL:  Maximum call depth */
  pcfg.maxrlock = 0;              /* MAXRLOCK: Record locks per process, 0 = no limit (openQM item 313) */
  pcfg.must_lock = FALSE;         /* MUSTLOCK: Enforce locking rules */
  pcfg.objects = 0;               /* OBJECTS:  Max loaded objects */
  pcfg.objmem = 0;                /* OBJMEM:   Max loaded object size */
  pcfg.netwait = 5;               /* NETWAIT:  Seconds to wait for a connection to a remote SDNet server (19 Oct 26, K8d; the plan's 5) */
  pcfg.netreply = 30;             /* NETREPLY: Seconds to wait for each reply of a remote SDNet server (the plan's 30) */
  pcfg.pwdelay = 3;               /* PWDELAY:  Seconds after a failed network login.  SD's own 3 (openQM's is 5) */
  pcfg.sdclient_mode = 0;         /* SDCLIENT: Client capabilities */
  pcfg.reccache = 0;              /* RECCACHE: Record cache size */
  pcfg.safedir = FALSE;       /* SAFE_DIR: User careful update to dir files */
  pcfg.sh[0] = '\0';          /* SH:       Command to run interactive shell */
  pcfg.sh1[0] = '\0';         /* SH1:      Command to run single shell */
  pcfg.sortmem = 4194304;     /* SORTMEM:  4Mb default switch to disk sort (1Mb until 1.2-0; openQM item 535) */
  pcfg.sortmrg = 4;           /* SORTMRG:  Files merged in one pass */
  pcfg.screentheme[0] = '\0'; /* SCREENTHEME: the screen library's own default (mono) */
  pcfg.sortworkdir[0] = '\0'; /* SORTWORK: Use Q_MSYS directory */
  pcfg.tempdir[0] = '\0';     /* TEMPDIR:  Temporary directory */
  pcfg.spooler[0] = '\0';     /* SPOOLER:  Default spooler name */
  pcfg.terminfodir[0] = '\0'; /* TERMINFO: Use default location */
  pcfg.timezone[0] = '\0';    /* TIMEZONE: the epoch functions use the process's own TZ (15 Oct 26, QM4 gaps Q-3) */
/* 20240219 mab create-account based on type (user / group / other) */
/* 13 Aug 26 Windows port - see the note on grpdir above.                   */
  strncpy(pcfg.usrdir,"C:\\ProgramData\\SD\\user_accounts",MAX_PATHNAME_LEN+1);  /* USRDIR: user accounts parent dir */
  pcfg.yearbase = 1930;       /* YEARBASE: Two digit year base */

  /* Set any non-zero defaults for shared configuration parameters */

  cfg->cmdstack = 99; /* CMDSTACK: Command stack depth */
  cfg->numfiles = 80;
  cfg->numlocks = 100;
  cfg->maxidlen = 63;
  cfg->lgnwait = 0;                /* LGNWAIT:  No wait when the user limit is reached (openQM item 46) */
  cfg->userpool = MIN_HI_USER_NO;  /* USERPOOL: Highest user number to allocate (openQM item 551) */
  cfg->usplit = 0;                 /* USPLIT:   Plain allocation (QM4 gaps Q-19, 15 Oct 26) */
  cfg->cleanup = 300;              /* CLEANUP:  A scan for lost processes every five minutes, as before the parameter (16 Oct 26) */
  cfg->phantoms_base = 0;          /* PHANTOMS: No user numbers reserved for PHANTOM USER n */
  cfg->phantoms_range = 0;
  cfg->fds_limit = SHRT_MAX;
  cfg->max_users = 1;

  fu = fopen(config_path, "r");
  if (fu == NULL) {
    sprintf(errmsg, "%s not found.", config_path);
    goto exit_read_config;
  }

  while (fgets(rec, 200, fu) != NULL) {
    if ((p = strchr(rec, '\n')) != NULL)
      *p = '\0';

    /* 14 Aug 26 Windows port - strip the carriage return too.  Only '\n' was
       removed, which is correct for a Unix file and wrong for every
       configuration file written on Windows: gplbld/stage.py writes CRLF, as
       Notepad and most Windows editors do.  The '\r' was left on the end of
       every STRING parameter, so SDSYS became "C:\ProgramData\SD\sdsys\r" and
       every path built from it was wrong, while the numeric parameters were
       unaffected because sscanf stops at the '\r'.  A fault that appears only
       in the shipped configuration and not in the developer's own. */

    p = rec + strlen(rec);
    while ((p > rec) && ((p[-1] == '\r') || (p[-1] == '\n')))
      *(--p) = '\0';

    if ((rec[0] == '#') || (rec[0] == '\0'))
      continue;

    if (rec[0] == '[') {
      p = strchr(rec, ']');
      if (p != NULL)
        *p = '\0';
      strncpy(section, rec + 1, 32);
      UpperCaseString(section);
      continue;
    }

    if (!strcmp(section, "SD")) {
      if (sscanf(rec, "NUMUSERS=%d", &n) == 1)
        cfg->max_users = n;
      /* !!CONFIG!! */
      else if (sscanf(rec, "CMDSTACK=%d", &n) == 1)
        cfg->cmdstack = n;
      /* 8 Nov 26 Windows port - from Linux 843344ba (S.87 batch 15): CODEPAGE and
         CREATUSR are gone.  CREATUSR was accepted and discarded here so that a
         file carrying it still loaded; now, as on Linux, the installer removes a
         retired parameter's line from a kept sd.conf (sd.iss, RetiredConf). */
      /* 01 Oct 26 Windows port - BACKUPDIR, THE DIRECTORY BACKUP.ACCOUNT AND
         RESTORE.ACCOUNT USE WHEN THEY ARE NOT GIVEN ONE.  SET.BACKUP.DIRECTORY
         writes this line; the CHAIN BELOW ENDS IN "Unrecognised configuration
         parameter", which aborts read_config() and stops SD starting, so a
         file carrying the line would not start without this branch.  It is
         accepted and NOT stored: SD BASIC reads the file itself, through
         !acc_os_bakdir, each time it needs the value, so a change takes
         effect without restarting SD.  Bounded like SH= above, so an overlong
         value is refused by name rather than silently kept.                  */
      else if (strncmp(rec, "BACKUPDIR=", 10) == 0) {
        if (strlen(rec + 10) > MAX_PATHNAME_LEN) {
          sprintf(errmsg, "BACKUPDIR value is longer than %d characters.",
                  MAX_PATHNAME_LEN);
          goto exit_read_config;
        }
      }
      else if (sscanf(rec, "DEADLOCK=%d", &n) == 1)
        cfg->deadlock = n; /* 0, 1 or 2: rangecheck below (openQM item 500) */
      else if (sscanf(rec, "DEBUG=%d", &n) == 1)
        cfg->debug |= n;
      else if (sscanf(rec, "DHCACHE=%d", &n) == 1)
        pcfg.dhcache = n;
      else if (strncmp(rec, "DUMPDIR=", 8) == 0)
        strcpy(pcfg.dumpdir, rec + 8);
      else if (sscanf(rec, "ERRLOG=%d", &n) == 1)
        cfg->errlog = n * 1024;
      else if (sscanf(rec, "FDS=%d", &n) == 1)
        cfg->fds_limit = n;
      else if (sscanf(rec, "FLTDIFF=%lf", &flt) == 1)
        pcfg.fltdiff = flt;
      else if (sscanf(rec, "FSYNC=%d", &n) == 1)
        pcfg.fsync |= n;
      else if (sscanf(rec, "GRPSIZE=%d", &n) == 1)
        pcfg.grpsize = n;
/* 20240219 mab create-account based on type (user / group / other) */          
      else if (strncmp(rec, "GRPDIR=", 7) == 0)
        strncpy(pcfg.grpdir, rec + 7,MAX_PATHNAME_LEN+1); 
      else if (sscanf(rec, "INTPREC=%d", &n) == 1)
        pcfg.intprec = n;
      else if (sscanf(rec, "LGNWAIT=%d", &n) == 1)
        cfg->lgnwait = n;
      else if (sscanf(rec, "LPTRHIGH=%d", &n) == 1)
        pcfg.lptrhigh = n;
      else if (sscanf(rec, "LPTRWIDE=%d", &n) == 1)
        pcfg.lptrwide = n;
      else if (sscanf(rec, "MAXCALL=%d", &n) == 1)
        pcfg.maxcall = n;
      else if (sscanf(rec, "MAXIDLEN=%d", &n) == 1)
        cfg->maxidlen = n;
      else if (sscanf(rec, "MAXRLOCK=%d", &n) == 1)
        pcfg.maxrlock = n;
      else if (sscanf(rec, "MUSTLOCK=%d", &n) == 1)
        pcfg.must_lock = n != 0;
/* 21 Aug 26 Windows port - NETDIRS, the escape hatch for the containment gate
   in op_dio2.c.  A network session is confined to the account it is standing
   in plus the SDSYS entries a stock VOC names; a site with a data directory
   outside any account names it here or its network sessions cannot reach it.

   SEMICOLON SEPARATED, NOT COLON.  A Windows pathname contains a colon, so
   the Unix PATH convention cannot be borrowed.

   NO DEFAULT, AND THE EMPTY VALUE IS THE STRICT ONE.  struct config is
   memset to zero above, so an sd.conf that does not mention NETDIRS confines
   every network session to its account.  That is the safe direction and it is
   the same convention as os.users: what is not named is refused.

   BOUNDS CHECKED, and the refusal is deliberate rather than a truncation - a
   truncated pathname is a SHORTER one, which as a containment root would
   match MORE than the administrator asked for, not less.                   */
      else if (strncmp(rec, "NETDIRS=", 8) == 0) {
        if (strlen(rec + 8) > MAX_NETDIRS_LEN) {
          sprintf(errmsg, "NETDIRS value is longer than %d characters.",
                  MAX_NETDIRS_LEN);
          goto exit_read_config;
        }
        strcpy(cfg->netdirs, rec + 8);
      }
      else if (sscanf(rec, "NETFILES=%d", &n) == 1)
        cfg->netfiles |= n;
      else if (sscanf(rec, "NETWAIT=%d", &n) == 1)
        pcfg.netwait = n;
      else if (sscanf(rec, "NETREPLY=%d", &n) == 1)
        pcfg.netreply = n;
      else if (sscanf(rec, "NUMFILES=%d", &n) == 1)
        cfg->numfiles = n;
      else if (sscanf(rec, "NUMLOCKS=%d", &n) == 1) {
        numlocks_asked = n;
        cfg->numlocks = n;
      }
      else if (sscanf(rec, "OBJECTS=%d", &n) == 1)
        pcfg.objects = n;
      else if (sscanf(rec, "OBJMEM=%d", &n) == 1)
        pcfg.objmem = n * 1024L;
      else if (sscanf(rec, "PDUMP=%d", &n) == 1)
        cfg->pdump |= n;
      else if (sscanf(rec, "PWDELAY=%d", &n) == 1)
        pcfg.pwdelay = n;
      else if (sscanf(rec, "SDCLIENT=%d", &n) == 1)
        pcfg.sdclient_mode |= n;
/* 8 Nov 26 Windows port - APILOGIN (accepted and ignored since 6 Oct 26) is gone with
   S.87 batch 15 (Linux 843344ba); the installer removes its line from a kept sd.conf. */
/* 17 Aug 26 Windows port - APIPORT, whether sdwind listens for API
   connections.  There is no default: the struct is memset to zero above, zero
   means no listener, and the listener has to be asked for.  Opening one is a
   decision - it is reachable by every local process on the machine, which is
   what $CRED and the ACC$GROUP check in APISRVR are there to answer
   (PROJECT_STATUS.md section 7 step 6).

   01 Oct 26 - THE NUMBER IS NO LONGER THE PORT.  Owner's ruling: the port is
   fixed (SD_API_PORT, sddefs.h) and not adjustable, so any value above zero
   means ON and the listener binds SD_API_PORT whatever was written.  A file
   from W1.1-1 or earlier that says APIPORT=4243 therefore still means ON, and
   the port it listens on moves by itself.  A value of zero or less is OFF.  */
      else if (sscanf(rec, "APIPORT=%d", &n) == 1)
        cfg->api_port = (n > 0) ? SD_API_PORT : 0;
      else if (strncmp(rec, "SDSYS=", 6) == 0) {
        if (!(command_options & CMD_FLASH))
          strcpy(cfg->sysdir, rec + 6);
      }
       else if (sscanf(rec, "RECCACHE=%d", &n) == 1)
        pcfg.reccache = n;
      else if (sscanf(rec, "SAFEDIR=%d", &n) == 1)
        pcfg.safedir = (n != 0);
      /* 14 Aug 26 Windows port - bounds checked.  These were plain strcpy
         into fixed buffers, so a long value in the configuration file
         overran into the fields declared after them in struct config and
         the error named an unrelated parameter.  Refuse the value instead. */
      else if (strncmp(rec, "SH=", 3) == 0) {
        if (strlen(rec + 3) > MAX_SH_CMD_LEN) {
          sprintf(errmsg, "SH value is longer than %d characters.",
                  MAX_SH_CMD_LEN);
          goto exit_read_config;
        }
        strcpy(pcfg.sh, rec + 3);
      } else if (strncmp(rec, "SH1=", 4) == 0) {
        if (strlen(rec + 4) > MAX_SH_CMD_LEN) {
          sprintf(errmsg, "SH1 value is longer than %d characters.",
                  MAX_SH_CMD_LEN);
          goto exit_read_config;
        }
        strcpy(pcfg.sh1, rec + 4);
      }
      else if (sscanf(rec, "SORTMEM=%d", &n) == 1)
        pcfg.sortmem = n * 1024L;
      else if (sscanf(rec, "SORTMRG=%d", &n) == 1)
        pcfg.sortmrg = n;
      else if (strncmp(rec, "SORTWORK=", 9) == 0)
        strcpy(pcfg.sortworkdir, rec + 9);
      else if (strncmp(rec, "SPOOLER=", 8) == 0)
        strcpy(pcfg.spooler, rec + 8);
      else if (strncmp(rec, "SCREENTHEME=", 12) == 0) {
        strncpy(pcfg.screentheme, rec + 12, sizeof(pcfg.screentheme) - 1);
        pcfg.screentheme[sizeof(pcfg.screentheme) - 1] = '\0';
      }
      /* 06 Oct 26 Windows port - STARTUP was removed (RELEASE_1.1 119): it never ran
         here and what it asked for is reserved to an elevated Windows sign-in.  A line
         still carrying it is refused BY NAME, not as an unknown word, so whoever wrote
         it is told what to do rather than left to guess. */
      else if (strncmp(rec, "STARTUP=", 8) == 0) {
        sprintf(errmsg, "STARTUP is no longer supported (it never ran on Windows). "
                        "Remove the STARTUP line from sd.conf.");
        goto exit_read_config;
      }
      else if (strncmp(rec, "TEMPDIR=", 8) == 0)
        strcpy(pcfg.tempdir, rec + 8);
      else if (strncmp(rec, "TERMINFO=", 9) == 0)
        strcpy(pcfg.terminfodir, rec + 9);
      else if (sscanf(rec, "USERPOOL=%d", &n) == 1)
        cfg->userpool = n;
      else if (sscanf(rec, "USPLIT=%d", &n) == 1)
        cfg->usplit = n;
      else if (sscanf(rec, "CLEANUP=%d", &n) == 1)
        cfg->cleanup = n;               /* 30 to 3600: rangecheck below (16 Oct 26) */
      else if (sscanf(rec, "PHANTOMS=%d,%d", &n, &n2) == 2) {
        cfg->phantoms_base = n;         /* checked against the highest user number below */
        cfg->phantoms_range = n2;
      }
 /* 20240219 mab create-account based on type (user / group / other) */
      else if (strncmp(rec, "USRDIR=", 7) == 0)
        strncpy(pcfg.usrdir, rec + 7,MAX_PATHNAME_LEN+1);        
      else if (sscanf(rec, "YEARBASE=%d", &n) == 1)
        pcfg.yearbase = n;
      else {
        sprintf(errmsg, "Unrecognised configuration parameter '%s'", rec);
        goto exit_read_config;
      }
    }
  }

  /* If the TEMPDIR parameter has not been set, insert the default value
     so that we do not have to repeat this operation everywhere else.    */

  if (pcfg.tempdir[0] != '\0') {
    if ((stat(pcfg.tempdir, &statbuf) != 0) /* No such directory */
        || (!(statbuf.st_mode & S_IFDIR))) {
      pcfg.tempdir[0] = '\0';
    }
  }

  if (pcfg.tempdir[0] == '\0') {
    p = getenv("TMP");
    strcpy(pcfg.tempdir, (p == NULL) ? "/tmp" : p);
  }

  /* If the SORTWORK parameter has not been set, use TEMPDIR */

  if (pcfg.sortworkdir[0] != '\0') {
    if ((stat(pcfg.sortworkdir, &statbuf) != 0) /* No such directory */
        || (!(statbuf.st_mode & S_IFDIR))) {
      pcfg.sortworkdir[0] = '\0';
    }
  }

  if (pcfg.sortworkdir[0] == '\0') {
    strcpy(pcfg.sortworkdir, pcfg.tempdir);
  }

  /* Validate critical parameters */

  if (cfg->sysdir[0] == '\0') {
    sprintf(errmsg, "No SDSYS parameter in configuration file.");
    goto exit_read_config;
  }

  /* The highest user number is the greater of USERPOOL and the licence's user count
    (sysseg.c), 1023 unless USERPOOL says otherwise. */

  hi_user = max(cfg->max_users, cfg->userpool);

  /* PHANTOMS (16 Oct 26): the user numbers PHANTOM ... USER n may take must exist */

  if (cfg->phantoms_base || cfg->phantoms_range) {
    if ((cfg->phantoms_base < 1) || (cfg->phantoms_range < 1) ||
        (cfg->phantoms_base + cfg->phantoms_range - 1 > hi_user)) {
      sprintf(errmsg, "PHANTOMS user numbers must lie between 1 and %d.", hi_user);
      goto exit_read_config;
    }
  }

  /* ERRLOG must be at least 10kb for file trim to work in log_message() */

  if ((cfg->errlog != 0) && (cfg->errlog < 10240))
    cfg->errlog = 10240;

  if (!rangecheck("DEADLOCK", cfg->deadlock, 0, 2, errmsg) ||
      !rangecheck("DHCACHE", pcfg.dhcache, 0, MAX_DH_CACHE_SIZE, errmsg) ||
      !rangecheck("LGNWAIT", cfg->lgnwait, 0, 32767, errmsg) ||
      !rangecheck("MAXRLOCK", pcfg.maxrlock, 0, 100000, errmsg) ||
      !rangecheck("NETWAIT", pcfg.netwait, 1, 3600, errmsg) ||           /* 19 Oct 26, K8d: 0 (wait for ever) is refused, which is tighter than openQM's */
      !rangecheck("NETREPLY", pcfg.netreply, 1, 3600, errmsg) ||
      !rangecheck("NUMLOCKS", numlocks_asked, 1, 32767, errmsg) ||        /* 16 Oct 26 (openQM 532): the table's cells are int16 */
      !rangecheck("PWDELAY", pcfg.pwdelay, 0, 3600, errmsg) ||
      !rangecheck("USERPOOL", cfg->userpool, 0, 16383, errmsg) ||
      !rangecheck("USPLIT", cfg->usplit, 0, 1, errmsg) ||
      !rangecheck("CLEANUP", cfg->cleanup, 30, 3600, errmsg) ||
      !rangecheck("GRPSIZE", pcfg.grpsize, 1, MAX_GROUP_SIZE, errmsg) ||
      !rangecheck("INTPREC", pcfg.intprec, 0, 14, errmsg) ||
      !rangecheck("LPTRHIGH", pcfg.lptrhigh, 10, 32767, errmsg) ||
      !rangecheck("LPTRWIDE", pcfg.lptrwide, 10, 1000, errmsg) ||
      !rangecheck("MAXCALL", pcfg.maxcall, 10, 1000000, errmsg) ||
      !rangecheck("RECCACHE", pcfg.reccache, 0, 32, errmsg) ||
      !rangecheck("SORTMRG", pcfg.sortmrg, 2, 10, errmsg) ||
      !rangecheck("MAXIDLEN", cfg->maxidlen, 63, MAX_ID_LEN, errmsg)) {
    goto exit_read_config;
  }
  /* changed to snprintf() from sprintf() 22Feb20 -gwb */
  /* 14 Sep 26 - $cproc, lower case (RELEASE_1.1 5 stage 3a). bootstrap.py's
     placeholder carries the same name: on NTFS a file written over an
     existing one keeps the OLD name's case, so the two must agree.       */
  if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s%cgcat%c$cproc", cfg->sysdir,
         DS, DS) >= (MAX_PATHNAME_LEN + 1)) {
      sprintf(errmsg, "Overflowed path/filename length with: '%s%cgcat%c$cproc'.",
            cfg->sysdir, DS, DS);
      goto exit_read_config;
  }
  if (access(path, 0)) {
    sprintf(errmsg, "Global catalogue missing or corrupt.");
    goto exit_read_config;
  }

  status = TRUE;

exit_read_config:
  if (fu != NULL)
    fclose(fu);

  if (status)
    return cfg;

  k_free(cfg);
  return NULL;
}

/* ======================================================================
   rangecheck()  -  Validate a critical configuration parameter           */

Private bool rangecheck(char* param,
                        int value,
                        int min_val,
                        int max_val,
                        char* errmsg) {
  if ((value < min_val) || (value > max_val)) {
    sprintf(errmsg, "Invalid value for %s configuration parameter", param);
    return FALSE;
  }

  return TRUE;
}

/* ======================================================================
   W.11 F9: the system directory this process TRUSTS

   sysseg->sysdir is a copy of SDSYS= that the starter made, in a segment every member of sdusers can write, so no decision may rest on it.  The
   trusted copy comes from the configuration file this process was told to use (SD_CONFIG, else /etc/sd.conf, which is root's on an install).
   A session takes it when bind_sysseg() reads the whole file (sd_sysdir_trust()); a command that only attaches (sd -stop, -cleanup ...) asks
   sd_sysdir() and gets a scan of that one line, so that a bad line elsewhere does not stop those commands.  It is "" when the file cannot be
   read, and a path built from "" fails: an unreadable configuration ends badly, never in a directory the segment names.                    */

Private char trusted_sysdir[MAX_PATHNAME_LEN + 1] = "";

/* SDSYS= of the [sd] section: the last one, as read_config() takes it.  Writes nothing to out unless it finds one.  No other line is judged. */

Private bool config_sysdir_scan(char *out) {
  FILE* fu;
  char rec[200 + 1];
  char section[32 + 1] = "";
  char* p;
  bool found = FALSE;

  if ((config_path[0] == '\0') || ((fu = fopen(config_path, "r")) == NULL))
    return FALSE;

  while (fgets(rec, sizeof(rec), fu) != NULL) {
    if ((p = strchr(rec, '\n')) != NULL)
      *p = '\0';
    if ((rec[0] == '#') || (rec[0] == '\0'))
      continue;
    if (rec[0] == '[') {
      p = strchr(rec, ']');
      if (p != NULL)
        *p = '\0';
      strncpy(section, rec + 1, 32);
      UpperCaseString(section);
      continue;
    }
    if (!strcmp(section, "SD") && (strncmp(rec, "SDSYS=", 6) == 0)) {
      snprintf(out, MAX_PATHNAME_LEN + 1, "%s", rec + 6);
      found = TRUE;
    }
  }
  fclose(fu);
  return found;
}

const char* sd_sysdir(void) {
  if (trusted_sysdir[0] == '\0')
    (void)config_sysdir_scan(trusted_sysdir);
  return trusted_sysdir;
}

void sd_sysdir_trust(const char* dir) {
  snprintf(trusted_sysdir, sizeof(trusted_sysdir), "%s", dir);
}

/* END-CODE */
