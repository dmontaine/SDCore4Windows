/* SD.C
 * Main module of SD
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
 * 15 Jun 24 add bootstrap build option install option -I
 * 02 Jul 24 -i  typeo will hit bootstrap option
 * 08 Aug 24 mab add code to embedded python if EMBED_PYTHON defined 
 * rev 0.9.1 Mar 25 return to single rev track 
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Available single letter options: EFGHJORVWY
 *
 * SD      -A            Query account name
 *         -Aname        Force entry to named account unless set in $LOGINS
 *         -Bn           Telnet binary mode? Additive: 1=input, 2=output,
 *                                                     4 = suppress telnet
 *         -D            Diagnostic dump
 *         -I            Bootstrap Install
 *         -K n          Kill user n
 *         -K ALL        Kill all users
 *         -L            Apply new licence
 *         -M            Dump shared memory
 *         -N            Network connection (SDClient or direct telnet)
 *         -Pn           Execute phantom command (command in $IPC)
 *         -Q            SDClient
 *         -U            List current users
 *
 * "Word" options
 *    -CLEANUP      Clean up lost processes
 *    -INTERNAL     Run in internal mode
 *    -QUIET        Suppress copyright/licence display on entry
 *    -RESUME       Resume updates
 *    -SUSPEND      Suspend updates
 *    -TERM xx      Set default terminal type
 *
 * Doubly prefixed word options
 *    --HELP        Display usage help
 *    --VERSION     Display revision stamp
 *
 *
 * Options applicable to Linux only:
 *    -Cs.r         Local client connection (s = send pipe, r = receive pipe)
 *    -N            Network connection
 *    -RESTART      Restart system
 *    -START        Start system
 *    -STOP         Stop system
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <setjmp.h>
#include <time.h>
#include <stdarg.h>
/* 20240126 mab add syslog */
#include <syslog.h>

// #define DEBUG /* enables harcoded diagnostic output */

#define Public
#define init(a) = a

#include "sd.h"
#include "revstamp.h"
#include "header.h"
#include "debug.h"
#include "dh_int.h"
#include "tio.h"
#include "config.h"
#include "options.h"
#include "locks.h"
#include "keys.h"

#define BUILD_TARGET "64 Bit"

extern char *x_option; /* -x option */

/* 20240808 mab embedding python? */
#ifdef EMBED_PYTHON
extern void sdext_py(int key, char* Arg);
#endif

bool bind_sysseg(bool create, char *errmsg);
void unbind_sysseg(void);
void dump_sysseg(bool dump_config);
void show_users(void);
void kill_user(char *user);

Private jmp_buf sd_exit;

Private void sd_init(int argc, char *argv[]);
Private void check_admin(void);
Private bool comlin(int argc, char *argv[]);
Private bool load_pcode(char *pname, u_char **ptr);

void suspend_resume(bool suspend);
void cleanup(void);
void clean_stop(void);
void dump_pcode_file(void);

/* ====================================================================== */

int main(int argc, char *argv[]) {
  /* 13Jan22 gwb Refactored to remove "goto" calls. */

  int status = 1;
  char errmsg[80 + 1];

  tio.term_type[0] = '\0';

 /* 20240126 mab add syslog */
 /* log startup and command line args */
  int arg;
  #define msgsz 256
  char msg[msgsz];
  openlog ("sd_Log", LOG_CONS | LOG_PID | LOG_NDELAY, LOG_LOCAL1);
  syslog (LOG_INFO, "String Database (sd) command line:");
  strcpy(msg,"sd ");
  for (arg = 1; (arg < argc); arg++) {
    if ((strlen(msg)+ strlen(argv[arg]) + 2) < msgsz){
      strcat(msg," "); 
      strcat(msg,argv[arg]); 
    } else {
      break;
    }
  }
  syslog (LOG_INFO, "%s",msg); 

  set_default_character_maps();
  sd_init(argc, argv);

  if (!(command_options & CMD_FLASH)) {
    /* Get config file path */
    if (!GetConfigPath(config_path)) {
      clean_stop();
      return status; /* TODO: add a custom return value for this failure. */
    }

    fullpath(config_path, config_path);
  }

  /* Process the command line */
  if (!comlin(argc, argv)) {
    clean_stop();
    return status; /* TODO: add a custom return value for this failure. */
  }

  if (!bind_sysseg(FALSE, errmsg)) {
    fprintf(stderr, "%s\n", errmsg);
    clean_stop();
    return status; /* TODO: add a custom return value for this failure. */
  }

  if (sysseg->flags & SSF_SUSPEND) {
    fprintf(stderr, "SD is suspended\n");
    clean_stop();
    return status; /* TODO: add a custom return value for this failure. */
  }

  /* Disaster exit */
  if (setjmp(sd_exit)) {
    clean_stop();
    return status; /* TODO: add a custom return value for this failure. */
  }

  /* Set pcode pointers */

#undef Pcode
/* 
 * The block below is kind of interesting.  The #define functions as a function call that works like
 * this:
 * Given a call like Pcode(chain), the preprocessor is going to emit this:
 * if (!load_pcode("chain", &pcode_chain)) {
 *   clean_stop();
 *   return status;
 * }
  * 
 * Now the line below where pcode.h is included is going to trigger a call to load_pcode() for each
 * line in the pcode.h file that references the Pcode() macro.  It's clever in that you don't need to 
 * somehow specify a static list of pcode value names, you just add them to the include file and they'll
 * get pulled in automatically since the compiler preprocessor will have "unrolled" all of the entries
 * in the pcode.h include file, resulting in them being loaded at run time.
 * 
 * A similar method is used in kernel.h to declare all of the pcode variables via this define:
 * #define Pcode(a) Public u_char* pcode_##a;
 * Public has been defined in sddefs.h as "extern".  Given a call of Pcode(chain), the pre-processor
 * is going to expand that as:
 * extern u_char* pcode_chain;
 * 
 * -gwb
 * 
 */
 
#define Pcode(a)                       \
     if (!load_pcode(#a, &pcode_##a)) { \
      clean_stop();                    \
      return status;                   \
    }                                  \
 

#include "pcode.h" /* this loads up all the pcode object code from the "pcode" file. */

  /* Go run the system */
  if (!init_kernel()) {
    clean_stop();
    return status; /* TODO: add a custom return value for this failure. */
  }

  /* Initialize English messages */
  if (!load_language("")) {
    clean_stop();
    return status; /* TODO: add a custom return value for this failure. */
  }

#ifdef DEBUG
  dump_pcode_file();
#endif

  kernel(); /* Run the command processor */

  s_free_all(); /* Only really needed for MEMTRACE */

  status = exit_status;

  // abort:
  //   dh_shutdown();
  //   unbind_sysseg();
  //   shut_console();

  /* 20240808 mab embedding python? */
  #ifdef EMBED_PYTHON
  char py_shutdown[] = "shutdown";
  sdext_py(SD_PyFinal, py_shutdown);   /* if python was used, shut it down */
  #endif

  clean_stop();
  return status;
}

void clean_stop(void) {
  /* these functions were originally called at the end of main().
   * I've moved them to their own function in order to remove all of the
   * instances of "goto abort" that were in main().
   * 13Jan22 gwb */

  dh_shutdown();
  unbind_sysseg();
  shut_console();
}

/* ======================================================================
   Initialialisation tasks that need to be done very early                */

Private void sd_init(int argc, char *argv[]) {
  char cwd[MAX_PATHNAME_LEN + 1];

  /* Save the current working directory for use by SYSTEM(1024) */

  (void)getcwd(cwd, MAX_PATHNAME_LEN);
  entry_dir = k_alloc(MAX_PATHNAME_LEN, strlen(cwd) + 1); /* was hard coded at 110 -gwb */
  /* Modified by Composer AI - 2026/06/10.
     k_alloc() can return NULL; abort startup rather than strcpy to NULL. */
  if (entry_dir == NULL) {
    fprintf(stderr, "sd: insufficient memory for entry directory\n");
    exit(1);
  }
  /* -------------------- */
  strcpy(entry_dir, cwd);
}

/* ====================================================================== */

Private bool comlin(int argc, char *argv[]) {
  int arg;
  int socket_handle = 0;
  char c;
  int16_t bytes;
  int n; /* Fix for Issue #15 - 11Jan22 gwb */
  int RxPipe;
  int TxPipe;

  for (arg = 1; (arg < argc) && (argv[arg][0] == '-'); arg++) {
    if (IsDigit(*(argv[arg] + 1))) {
      /* Modified by Composer AI - 2026/06/10. atoi -> strtol (no overflow UB). */
      /* forced_user_no = atoi(argv[arg] + 1); */
      forced_user_no = (int)strtol(argv[arg] + 1, NULL, 10);
      /* -------------------- */
    } else if (!stricmp(argv[arg], "-CLEANUP")) {
      cleanup();
      exit(0);
    } else if (!stricmp(argv[arg], "-INTERNAL")) {
      internal_mode = TRUE;
    } else if (!stricmp(argv[arg], "-QUIET")) {
      command_options |= CMD_QUIET;
    } else if (!stricmp(argv[arg], "-TERM")) {
      if (++arg < argc)
        strcpy(tio.term_type, argv[arg]);
    } else if (!stricmp(argv[arg], "-I")) {    
/* 20240702 mab Bootstrap build arg must be exactly "-I" */		  
        /* Bootstrap Install*/
        check_admin();
        is_bootstrap = TRUE;
        internal_mode = TRUE;
        strcpy(command_processor, "$BBPROC");

    } else {
      switch (UpperCase(argv[arg][1])) {
        
        case 'A': /* Query account */
          if (argv[arg][2] == '\0') {
            command_options |= CMD_QUERY_ACCOUNT;
          } else {
            forced_account = argv[arg] + 2;
          }
          break;
        
        case 'B': /* Enable telnet binary mode */
          c = argv[arg][2];
          telnet_binary_mode_in = c & 1;
          telnet_binary_mode_out = c & 2;
          if (c & 4)
            telnet_negotiation = FALSE;
          break;

        case 'D': /* Diagnostic report */
          dump_sysseg(TRUE);
          exit(0);

        case 'K': /* Kill user */
          check_admin();
          if (++arg < argc) {
            if (!stricmp(argv[arg], "ALL"))
              kill_user(NULL);
            else
              kill_user(argv[arg]);
            exit(0);
          }
          fprintf(stderr, "User number, login name or ALL required\n");
          exit(1);

        case 'L': /* Apply new licence */
          command_options |= CMD_APPLY_LICENCE;
          break;

        case 'M': /* Dump memory */
          dump_sysseg(FALSE);
          exit(0);

        case 'P': /* Execute phantom command */
          /* Modified by Composer AI - 2026/06/10. atoi -> strtol (no overflow UB). */
          /* phantom_user_index = atoi(argv[arg] + 2); */
          phantom_user_index = (int)strtol(argv[arg] + 2, NULL, 10);
          /* -------------------- */
          is_phantom = TRUE;
          connection_type = CN_NONE;
          break;

        case 'Q': /* Start SDClient session (NT style login) */
/* 20240219 mab rebrand VBSRVR to APISRVR */     
          is_sdApiSrvr = TRUE;
          telnet_binary_mode_in = TRUE;
          telnet_binary_mode_out = TRUE;
          break;

        case 'U': /* Show users */
          show_users();
          exit(0);

        case 'C': /* SDLocal client connection */
          connection_type = CN_PIPE;
          if (sscanf(argv[arg], "-C%d!%d", &TxPipe, &RxPipe) != 2) {
            exit(1);
          }
          dup2(RxPipe, 0);
          dup2(TxPipe, 1);
          break;

        case 'N': /* Network server */
          connection_type = CN_SOCKET;
          break;

        case 'R':
          if (!stricmp(argv[arg], "-RESUME")) {
            suspend_resume(FALSE);
            exit(0);
          }

          if (stricmp(argv[arg], "-RESTART") == 0) {
            check_admin();
            if (stop_sd() && start_sd()) {
              printf("SD has been restarted\n");
              exit(0);
            }
            exit(1);
          }

          goto unrecognised;

        case 'S':
          if (!stricmp(argv[arg], "-SUSPEND")) {
            suspend_resume(TRUE);
            exit(0);
          }

          if (stricmp(argv[arg], "-START") == 0) {
            check_admin();
            if (start_sd()) {
              printf("SD (%s) has been started\n", BUILD_TARGET);
              exit(0);
            }
            exit(1);
          }

          if (stricmp(argv[arg], "-STOP") == 0) {
            check_admin();
            if (stop_sd()) {
              printf("SD (%s) has been shut down\n", BUILD_TARGET);
              exit(0);
            }
            exit(1);
          }
          /* Modified by Composer AI - 2026/06/10.
             Intentional fall-through: unrecognized -S... options are
             handled as long options in case '-'. */
          __attribute__((fallthrough));
          /* -------------------- */

        case '-':
          if (!stricmp(argv[arg], "--HELP")) {
            goto help;
          } else if (!stricmp(argv[arg], "--VERSION")) {
/* rev 0.9.1 Mar 25 return to single rev track */            
            printf("String Database (sd) Version %s %s\n", SD_REV_STAMP, BUILD_TARGET);
            exit(0);
          } else
            goto unrecognised;
          break;

        default:
          goto unrecognised;
      }
    }
  }

  /* Anything else on the command line is considered to be a command
    to be executed.                                                  */

  if (arg < argc) {
    bytes = 0;
    for (n = arg; n < argc; n++) {
      bytes += strlen(argv[n]) + 1;
    }

    single_command = k_alloc(109, bytes);
    /* Modified by Composer AI - 2026/06/10.
       k_alloc() can return NULL; skip single-command mode on failure. */
    if (single_command == NULL) {
      fprintf(stderr, "sd: insufficient memory for command line\n");
      exit(1);
    }
    /* -------------------- */
    n = 0;
    while (1) {
      strcpy(single_command + n, argv[arg]);
      n += strlen(argv[arg]);
      if (++arg == argc)
        break;
      single_command[n++] = ' ';
    }
  }

  /* Start connection */

  switch (connection_type) {
    case CN_SOCKET:
      if (!start_connection(socket_handle))
        exit(1);
      break;
    case CN_PIPE:
    case CN_PORT:
      if (!start_connection(0))
        exit(1);
      break;
    case CN_WINSTDOUT:
      break;
  }

  if (connection_type != CN_SOCKET)
    telnet_negotiation = FALSE;

  return TRUE;

unrecognised:
  fprintf(stderr, "Unrecognised argument '%s'\n", argv[arg]);
help:
  fprintf(stderr, "\nUsage:\n");
  fprintf(stderr, "   sd xxx\n");
  fprintf(stderr, "      Execute SD command xxx\n\n");
  fprintf(stderr, "   sd {options}\n");
  fprintf(stderr, "      -a          Prompt for account unless forced elsewhere\n");
  fprintf(stderr,
          "      -axxx       Enter SD in account xxx unless forced "
          "elsewhere\n");
  fprintf(stderr, "      -k n        Kill (logout) user n\n");
  fprintf(stderr, "      -k all      Kill (logout) all users n\n");
  fprintf(stderr, "      -l          Apply new licence\n");
  fprintf(stderr, "      -u          List current users\n");
  fprintf(stderr, "      -quiet      Suppress all displays on entry\n");
  fprintf(stderr, "      --help      Show this summary\n");
  fprintf(stderr, "      --version   Report version number\n");

  fprintf(stderr, "      -start      Start system\n");
  fprintf(stderr, "      -stop       Stop system\n");
  return FALSE;
}

/* ======================================================================
   Fatal error handler                                                    */

void fatal() {
  longjmp(sd_exit, 1);
}

/* ======================================================================
   dump()  -  General purpose memory dump function                        */

void dump(u_char *addr, int32_t bytes) {
  int32_t i;
  int16_t j;
  u_char c;

  for (i = 0; i < bytes; i += 16) {
    /* Offset */

    printf("%08X: ", i);  // was lX -Wformat=2 issue

    /* Hex */

    for (j = 0; j < 16; j++) {
      if (i + j < bytes)
        printf("%02X", addr[i + j]);
      else
        printf("  ");
      if ((j % 4) == 3)
        printf(" ");
    }

    printf(" | ");

    /* Character */

    for (j = 0; (j < 16) && (i + j < bytes); j++) {
      c = *(addr + i + j);
      printf("%c", (c < 32) ? '.' : c);
    }

    printf("\n");
  }

  if (bytes % 16 != 0)
    printf("\n");
}

/* ======================================================================
   check_admin()  -  Check user has admin rights                          */

void check_admin() {
  bool IsAdmin(void);

  /* 13 Aug 26 Windows port - was (geteuid() != 0) && !in_group("admin").
     Neither half means anything here: there is no uid zero on Windows, and
     "admin" is a Linux group name.  Deferring to IsAdmin() keeps one
     definition of what an SD administrator is, which is membership of
     SD_ADMIN_GROUP.  See linuxlb.c.                                        */

  if (!IsAdmin()) {
    fprintf(stderr, "Command requires administrator privileges\n");
    exit(1);
  }
}

/* ====================================================================== */

Private bool load_pcode(char *pname, u_char **ptr) {
  char u_pname[MAX_PROGRAM_NAME_LEN + 1];
  OBJECT_HEADER *obj;
  int i;
  u_char *pcode;

  pcode = ((u_char *)sysseg) + sysseg->pcode_offset;

  /* Take a local copy of the pcode name and force it to uppercase */

  strcpy(u_pname, pname);
  UpperCaseString(u_pname);

  /* Search for this item in the pcode library */
  for (i = 0; i < sysseg->pcode_len; i += (obj->object_size + 3) & ~3) {
    obj = (OBJECT_HEADER *)(pcode + i);
    if (obj->magic == HDR_MAGIC_INVERSE) {
      convert_object_header(obj);
    } else if (obj->magic != HDR_MAGIC) {
      fprintf(stderr, "Pcode is corrupt (%s)\n", u_pname);
      return FALSE;
    }

    if (!strcmp(obj->ext_hdr.prog.program_name, u_pname)) { /* Found it */
      *ptr = pcode + i;
      return TRUE;
    }
  }

  fprintf(stderr, "Pcode item %s not found\n", u_pname);
  return FALSE;
}

/* END-CODE */
