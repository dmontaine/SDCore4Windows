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
 * 31 Dec 23 SD launch - prior history suppressed
 * rev 0.9.0 Jan 25 mab add CREATUSR - allow create.account to create os user
 * START-DESCRIPTION:
 *
 * Handles parsing of the configuration file.
 * 
 *  DEADLOCK=n    Trap deadlocks?
 *  DEBUG=n       Debug features enabled? (bit flags)
 *  FDS=n         Set FDS limit (default is no limit)
 *  FLTDIFF=f     Wide zero value
 *  GDI=n         Select default API calls for printing
 *  GRPSIZE=n     Default group size when creating a dynamic file
 *  MAXIDLEN=63   Maximum record id len
 *  MUSTLOCK=1    Must hold update or file lock to write or delete record
 *  NETFILES=0    Allow remote files?
 *                  0x0001   Allow outgoing NFS
 *                  0x0002   Allow incoming Q_M_Net
 *  NUMFILES=n    Maximum number of files open (all users)
 *  NUMLOCKS=n    Maximum number of record locks
 *  OBJECTS=n     Limit on loaded object code count (0 = no limit)
 *  OBJMEM=n      Limit on locade object size (kb, 0 = no limit)
 *  SDCLIENT=n    SDClient rules (0=all, 1=no call/exec, 2=restricted call)
 *  SDSYS=path    SDSYS directory path
 *  SAFEDIR=1     Use careful update to directory files
 *  SORTMEM=n     Threshold for disk based sort (units of 1kb)
 *  SORTWORK=path Pathname of sort workfile directory
 *  STARTUP=cmd   Run command on starting Q_M
 *  TEMPDIR=path  Pathname of temporary directory
 *  TERMINFO=path Pathname of terminfo directory
 *  TXCHAR=1      Enable ansi/oem character translation (default = 1)
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
  bool status = FALSE;
  int n2;
  int n3;
  struct stat statbuf;

  cfg = (struct CONFIG*)k_alloc(1, sizeof(struct CONFIG));
  if (cfg == NULL) {
    sprintf(errmsg, "Unable to allocate CONFIG memory.");
    return NULL;
  }

  memset((char*)cfg, 0, sizeof(struct CONFIG));

  /* Set defaults for private configuration parameters */
  /* !!CONFIG!! */

  pcfg.codepage = 0;      /* CODEPAGE: Console code page */
  pcfg.create_user = 1;   /* allow create.account to create os user */
  pcfg.dumpdir[0] = '\0'; /* DUMPDIR:  Directory for process dump files */
  pcfg.exclrem = 0;       /* EXCLREM:  Exclude remote files in ACCOUNT.SAVE? */
  pcfg.filerule = 0;      /* FILERULE: File name rules (special forms) */
  pcfg.fltdiff = 0.0000000000291; /* FLTDIFF: Wide zero for float eq test */
  pcfg.fsync = 0;                 /* FSYNC:    Controls when to do fsync() */
  pcfg.gdi = 0;                   /* GDI:      Default GDI spool API? */
 /* 20240219 mab create-account based on type (user / group / other) */   
  strncpy(pcfg.grpdir,"/home/sd/group_accounts",MAX_PATHNAME_LEN+1);  /* GRPDIR: group accounts parent dir */
  pcfg.grpsize = 1;               /* GRPSIZE:  Default group size */
  pcfg.intprec = 13;              /* INTPREC:  Precision for INT() etc */
  pcfg.lptrhigh = 66;             /* LPTRHIGH: Default printer lines */
  pcfg.lptrwide = 80;             /* LPTRWIDE: Default printer width */
  pcfg.maxcall = 10000;           /* MAXCALL:  Maximum call depth */
  pcfg.must_lock = FALSE;         /* MUSTLOCK: Enforce locking rules */
  pcfg.objects = 0;               /* OBJECTS:  Max loaded objects */
  pcfg.objmem = 0;                /* OBJMEM:   Max loaded object size */
  pcfg.sdclient_mode = 0;         /* SDCLIENT: Client capabilities */
  /* 20240219 mab mods to handle AF_UNIX sockets, security mode */
  pcfg.api_login = 1;             /* API (sdclient) login type     */
  pcfg.reccache = 0;              /* RECCACHE: Record cache size */
  pcfg.ringwait = TRUE;           /* RINGWAIT: Wait if ring buffer full */
  pcfg.safedir = FALSE;       /* SAFE_DIR: User careful update to dir files */
  pcfg.sh[0] = '\0';          /* SH:       Command to run interactive shell */
  pcfg.sh1[0] = '\0';         /* SH1:      Command to run single shell */
  pcfg.sortmem = 1048576;     /* SORTMEM:  1Mb default switch to disk sort */
  pcfg.sortmrg = 4;           /* SORTMRG:  Files merged in one pass */
  pcfg.sortworkdir[0] = '\0'; /* SORTWORK: Use Q_MSYS directory */
  pcfg.tempdir[0] = '\0';     /* TEMPDIR:  Temporary directory */
  pcfg.spooler[0] = '\0';     /* SPOOLER:  Default spooler name */
  pcfg.terminfodir[0] = '\0'; /* TERMINFO: Use default location */
  pcfg.txchar = TRUE;         /* TXCHAR:   Enable ansi/oem translation */
/* 20240219 mab create-account based on type (user / group / other) */   
  strncpy(pcfg.usrdir,"/home/sd/user_accounts",MAX_PATHNAME_LEN+1);  /* USRDIR: user accounts parent dir */
  pcfg.yearbase = 1930;       /* YEARBASE: Two digit year base */

  /* Set any non-zero defaults for shared configuration parameters */

  cfg->cmdstack = 99; /* CMDSTACK: Command stack depth */
  cfg->numfiles = 80;
  cfg->numlocks = 100;
  cfg->maxidlen = 63;
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
      else if (sscanf(rec, "CODEPAGE=%d", &n) == 1)
        pcfg.codepage = n;
      else if (sscanf(rec, "CREATUSR=%d", &n) == 1)
        pcfg.create_user = (n != 0);
      else if (sscanf(rec, "DEADLOCK=%d", &n) == 1)
        cfg->deadlock = (n != 0);
      else if (sscanf(rec, "DEBUG=%d", &n) == 1)
        cfg->debug |= n;
      else if (strncmp(rec, "DUMPDIR=", 8) == 0)
        strcpy(pcfg.dumpdir, rec + 8);
      else if (sscanf(rec, "ERRLOG=%d", &n) == 1)
        cfg->errlog = n * 1024;
      else if (sscanf(rec, "EXCLREM=%d", &n) == 1)
        pcfg.exclrem = (n != 0);
      else if (sscanf(rec, "FDS=%d", &n) == 1)
        cfg->fds_limit = n;
      else if (sscanf(rec, "FILERULE=%d", &n) == 1)
        pcfg.filerule |= n;
      else if (sscanf(rec, "FIXUSERS=%d,%d", &n, &n2) == 2) {
        cfg->fixusers_base = n;
        cfg->fixusers_range = n2;
      } else if (sscanf(rec, "FLTDIFF=%lf", &flt) == 1)
        pcfg.fltdiff = flt;
      else if (sscanf(rec, "FSYNC=%d", &n) == 1)
        pcfg.fsync |= n;
      else if (sscanf(rec, "GDI=%d", &n) == 1)
        pcfg.gdi = (n != 0);
      else if (sscanf(rec, "GRPSIZE=%d", &n) == 1)
        pcfg.grpsize = n;
/* 20240219 mab create-account based on type (user / group / other) */          
      else if (strncmp(rec, "GRPDIR=", 7) == 0)
        strncpy(pcfg.grpdir, rec + 7,MAX_PATHNAME_LEN+1); 
      else if (sscanf(rec, "INTPREC=%d", &n) == 1)
        pcfg.intprec = n;
      else if (strncmp(rec, "JNLDIR=", 7) == 0)
        strcpy(cfg->jnldir, rec + 7);
      else if (sscanf(rec, "JNLMODE=%d", &n) == 1)
        cfg->jnlmode = n;
      else if (sscanf(rec, "LPTRHIGH=%d", &n) == 1)
        pcfg.lptrhigh = n;
      else if (sscanf(rec, "LPTRWIDE=%d", &n) == 1)
        pcfg.lptrwide = n;
      else if (sscanf(rec, "MAXCALL=%d", &n) == 1)
        pcfg.maxcall = n;
      else if (sscanf(rec, "MAXIDLEN=%d", &n) == 1)
        cfg->maxidlen = n;
      else if (sscanf(rec, "MUSTLOCK=%d", &n) == 1)
        pcfg.must_lock = n != 0;
      else if (sscanf(rec, "NETFILES=%d", &n) == 1)
        cfg->netfiles |= n;
      else if (sscanf(rec, "NUMFILES=%d", &n) == 1)
        cfg->numfiles = n;
      else if (sscanf(rec, "NUMLOCKS=%d", &n) == 1)
        cfg->numlocks = n;
      else if (sscanf(rec, "OBJECTS=%d", &n) == 1)
        pcfg.objects = n;
      else if (sscanf(rec, "OBJMEM=%d", &n) == 1)
        pcfg.objmem = n * 1024L;
      else if (sscanf(rec, "PDUMP=%d", &n) == 1)
        cfg->pdump |= n;
      else if (sscanf(rec, "PORTMAP=%d,%d,%d", &n, &n2, &n3) == 3) {
        cfg->portmap_base_port = n;
        cfg->portmap_base_user = n2;
        cfg->portmap_range = n3;
      } 
      else if (sscanf(rec, "SDCLIENT=%d", &n) == 1)
        pcfg.sdclient_mode |= n;
/* 20240219 mab mods to handle AF_UNIX sockets, security mode */        
      else if (sscanf(rec, "APILOGIN=%d", &n) == 1)
        pcfg.api_login = n; 
      else if (strncmp(rec, "SDSYS=", 6) == 0) {
        if (!(command_options & CMD_FLASH))
          strcpy(cfg->sysdir, rec + 6);
      }
       else if (sscanf(rec, "RECCACHE=%d", &n) == 1)
        pcfg.reccache = n;
      else if (sscanf(rec, "RINGWAIT=%d", &n) == 1)
        pcfg.ringwait = (n != 0);
      else if (sscanf(rec, "SAFEDIR=%d", &n) == 1)
        pcfg.safedir = (n != 0);
      else if (strncmp(rec, "SH=", 3) == 0)
        strcpy(pcfg.sh, rec + 3);
      else if (strncmp(rec, "SH1=", 4) == 0)
        strcpy(pcfg.sh1, rec + 4);
      else if (sscanf(rec, "SORTMEM=%d", &n) == 1)
        pcfg.sortmem = n * 1024L;
      else if (sscanf(rec, "SORTMRG=%d", &n) == 1)
        pcfg.sortmrg = n;
      else if (strncmp(rec, "SORTWORK=", 9) == 0)
        strcpy(pcfg.sortworkdir, rec + 9);
      else if (strncmp(rec, "SPOOLER=", 8) == 0)
        strcpy(pcfg.spooler, rec + 8);
      else if (strncmp(rec, "STARTUP=", 8) == 0)
        strcpy(cfg->startup, rec + 8);
      else if (strncmp(rec, "TEMPDIR=", 8) == 0)
        strcpy(pcfg.tempdir, rec + 8);
      else if (strncmp(rec, "TERMINFO=", 9) == 0)
        strcpy(pcfg.terminfodir, rec + 9);
      else if (sscanf(rec, "TXCHAR=%d", &n) == 1)
        pcfg.txchar = (n != 0);
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

  if ((cfg->portmap_range) &&
      (cfg->portmap_base_user + cfg->portmap_range - 1 > MIN_HI_USER_NO)) {
    sprintf(errmsg, "PORTMAP user numbers extend beyond %d.", MIN_HI_USER_NO);
    goto exit_read_config;
  }

  if (cfg->fixusers_base) {
    if (cfg->fixusers_base + cfg->fixusers_range - 1 > MIN_HI_USER_NO) {
      sprintf(errmsg, "FIXUSERS user numbers extend beyond %d.", MIN_HI_USER_NO);
      goto exit_read_config;
    }

    if (cfg->portmap_range) /* Both PORTMAP and FIXUSERS - Check overlap */
    {
      if (((cfg->portmap_base_user >= cfg->fixusers_base) &&
           (cfg->portmap_base_user <
            cfg->fixusers_base + cfg->fixusers_range)) ||
          ((cfg->fixusers_base >= cfg->portmap_base_user) &&
           (cfg->fixusers_base <
            cfg->portmap_base_user + cfg->portmap_range))) {
        sprintf(errmsg, "PORTMAP and FIXUSERS user numbers overlap.");
        goto exit_read_config;
      }
    }
  }

  /* ERRLOG must be at least 10kb for file trim to work in log_message() */

  if ((cfg->errlog != 0) && (cfg->errlog < 10240))
    cfg->errlog = 10240;

  if (!rangecheck("GRPSIZE", pcfg.grpsize, 1, MAX_GROUP_SIZE, errmsg) ||
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
  if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s%cgcat%c$CPROC", cfg->sysdir, 
         DS, DS) >= (MAX_PATHNAME_LEN + 1)) {
      sprintf(errmsg, "Overflowed path/filename length with: '%s%cgcat%c$CPROC'.",
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

/* END-CODE */
