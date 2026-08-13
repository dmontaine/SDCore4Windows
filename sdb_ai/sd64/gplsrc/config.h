/* CONFIG.H
 * Configuration data
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
 * START-HISTORY
 * 31 Dec 23 SD launch - prior history suppressed
 * rev 0.9.0 Jan 25 mab add create_user
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* !!CONFIG!! All places requiring changes for config parameters are marked */

struct CONFIG {
 
  int16_t max_users;               /* User limit */
  char sysdir[MAX_PATHNAME_LEN+1];
  int16_t cmdstack;                /* CMDSTACK: Command stack depth */
  bool deadlock;                   /* DEADLOCK: Trap deadlocks */
  u_int16_t debug;                 /* DEBUG:    Controls debug features */
  int errlog;                      /* ERRLOG:   Max errlog size in bytes, 0 if disabled */
  int16_t fds_limit;               /* FDS */
  int16_t fixusers_base;           /* FIXUSERS: First user number and... */
  int16_t fixusers_range;          /*          ...Number of users */
  int16_t jnlmode;                 /* JNLMODE:  Journalling mode */
  char jnldir[MAX_PATHNAME_LEN+1]; /* JNLDIR:   Journal file directory */
  int16_t maxidlen;                /* MAXIDLEN: Maximum record id length */
  int16_t netfiles;                /* NETFILES:
                                      0x0001    Allow outgoing NFS
                                      0x0002    Allow incoming SDNet   */
  int16_t numfiles;                /* NUMFILES: Maximum number of files open */
  int16_t numlocks;                /* NUMLOCKS: Maximum number of record locks */
  int16_t pdump;                   /* PDUMP:    PDUMP mode flags */
  int16_t portmap_base_port;       /* PORTMAP: First port number ... */
  int16_t portmap_base_user;       /*          ...First user number... */
  int16_t portmap_range;           /*          ...Number of ports/users */
  char startup[80+1];              /* STARTUP: Startup command */
 };


/* Config parameters loaded per process to allow local changes */

#define MAX_SH_CMD_LEN 80
struct PCFG  {
/* 20240219 mab mods to handle AF_UNIX sockets, security mode */ 
  int16_t api_login;                    /* REQUIRE API LOGIN  APILOGIN 0 = UserName and Password are NOT validated, run as peer user. 1 = UserName and Password validated */
  unsigned int codepage;                /* CODEPAGE: Set console codepage */
  bool create_user;                     /* allow create account to create os user */
  char dumpdir[MAX_PATHNAME_LEN+1];     /* DUMPDIR:  Directory for process dump files */
  bool exclrem;                         /* EXCLREM:  Exclude remote files from ACCOUNT.SAVE? */
  int16_t filerule;                     /* FILERULE: Rules for special filename formats */
  double fltdiff;                       /* FLTDIFF : Wide zero for float comparisons */
  int16_t fsync;                        /* FSYNC:    Controls when to do fsync() */
  bool gdi;                             /* GDI:      Default to GDI print API? */
 /* 20240219 mab create-account based on type (user / group / other) */  
  char grpdir[MAX_PATHNAME_LEN+1];      /* GRPDIR:   Parent Directory for group accounts */
  int16_t grpsize;                      /* GRPSIZE:  Default group size (1-8) */
  int16_t intprec;                      /* INTPREC:  Precision for INT() etc */
  int16_t lptrhigh;                     /* LPTRHIGH: Default printer lines */
  int16_t lptrwide;                     /* LPTRWIDE: Default printer width */
  int maxcall;                          /* MAXCALL:  Maximum call depth */
  bool must_lock;                       /* MUSTLOCK: Enforce locking rules */
  int16_t objects;                      /* OBJECTS:  Max loaded objects */
  int32_t objmem;                       /* OBJMEM:   Object size limit, zero = none */
  int16_t sdclient_mode;                /* SDCLIENT: 0 = any, 1 = no open/exec, 2 = restricted call */
  int16_t reccache;                     /* RECCACHE: Record cache size */
  bool ringwait;                        /* RINGWAIT: Wait if ring buffer full */
  bool safedir;                         /* SAFEDIR:  Use careful update on dir file write */
  char sh[MAX_SH_CMD_LEN+1];            /* SH:       Command to run interactive shell */
  char sh1[MAX_SH_CMD_LEN+1];           /* SH1:      Command to run single shell */
  int32_t sortmem;                      /* SORTMEM: Limit on in-memory sort size */
  int16_t sortmrg;                      /* SORTMRG: Number of files in merge */
  char sortworkdir[MAX_PATHNAME_LEN+1]; /* SORTWORK */
  char spooler[MAX_PATHNAME_LEN+1];     /* SPOOLER: Non-default spooler */
  char tempdir[MAX_PATHNAME_LEN+1];     /* TEMPDIR */
  char terminfodir[MAX_PATHNAME_LEN+1]; /* TERMINFO */
  bool txchar;                          /* TXCHAR */
/* 20240219 mab create-account based on type (user / group / other) */  
  char usrdir[MAX_PATHNAME_LEN+1];      /* USRDIR:   Parent Directory for user accounts */
  int16_t yearbase;                     /* YEARBASE: Two digit year start */
 };

Public struct PCFG pcfg;

/* END-CODE */
