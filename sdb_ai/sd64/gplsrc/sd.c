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
 * 20 Aug 26 Windows port - two comments corrected, no code changed: the
 *           -INTERNAL note claimed entering SDSYS needs the SDSYS password,
 *           which LOGIN stopped being true on 14 Aug; and check_admin()
 *           claimed the spawned children inherit an ordinary user's token,
 *           which the API's do not - sdwind is a service
 * 15 Aug 26 Windows port - the administrative switches need an ELEVATED
 *           session, not merely an administrator's account: check_admin()
 *           asks IsElevated(), and -CLEANUP, -D, -L, -M, -U, -SUSPEND and
 *           -RESUME now call it as -START, -STOP, -RESTART, -K and -I did
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
/* 17 Aug 26 Windows port - its own header rather than a prototype here, so
   that sd.c never sees windows.h.  See win32pipe.h.                        */
#include "win32pipe.h"
#include "locks.h"
#include "keys.h"

#define BUILD_TARGET "64 Bit"

extern char *x_option; /* -x option */

/* 13 Aug 26 Windows port - embedded Python removed, see PROJECT_STATUS.md 5.15 */

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

  /* 13 Aug 26 Windows port - the embedded Python interpreter was shut down
     here.  Removed with the rest of it (PROJECT_STATUS.md 5.15). */

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
/* 15 Aug 26 Windows port - ONE SD PER SESSION.  Owner's rule, 15 Aug 2026:
   somebody who shells out of SD with SH must not be able to start a second
   one.  op_sh.c marks the shell it launches with SD_SESSION, and that is what
   this reads; the comment there explains why it is a guard rather than a
   boundary, and what the real boundary is.

   Before everything, so it applies to every form of the command, and worded
   for a user rather than an administrator: the way back is the shell they are
   standing in.                                                             */
  if (getenv("SD_SESSION") != NULL) {
    fprintf(stderr,
            "SD is already running in this session - type EXIT to return to "
            "it.\n");
    exit(1);
  }

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
/* 15 Aug 26 Windows port - the administrative switches all take the elevation
   gate now, not just the three that had it.  Each of them either changes the
   state of the server or reports on everybody's sessions; see check_admin(). */
      check_admin();
      cleanup();
      exit(0);
    } else if (!stricmp(argv[arg], "-INTERNAL")) {
/* 15 Aug 26 Windows port - -INTERNAL TAKES THE GATE TOO.  It names SDSYS for
   itself below, and LOGIN refuses SDSYS to an unelevated session anyway
   (sysmsg 10002), so this was always going to fail - but only after starting
   up, connecting and reaching the BASIC layer, and it failed with a message
   about accounts rather than about elevation.  Refusing here says the true
   reason at the door and leaves the BASIC gate as the second of two.
   Nothing spawns sd -internal: the bootstrap, the installer's adopt step and
   an administrator at the keyboard are all elevated already.               */
      check_admin();
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
          check_admin();
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
          check_admin();
          command_options |= CMD_APPLY_LICENCE;
          break;

        case 'M': /* Dump memory */
          check_admin();
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
          check_admin();
          show_users();
          exit(0);

        case 'C': /* SDLocal client connection */
          connection_type = CN_PIPE;
/* 17 Aug 26 Windows port - A PIPE NAME IS ACCEPTED HERE, WHICH IS WHAT THE
   CLIENT HAS ALWAYS SENT.  section 7 step 11.  This parsed only
   "-C<txfd>!<rxfd>" and exit(1)'d on anything else, while SDConnectLocal()
   builds "sd.exe -Q -C \\.\pipe\~SDPipe<pid>-<n>" - a pipe NAME, in the NEXT
   argument.  The two halves have never agreed, so SDConnectLocal() could not
   have worked on any platform, and it is the same in sdb64: see
   UPSTREAM_FIXES.md.

   The descriptor form is kept rather than replaced.  It costs one sscanf, it
   is what a Unix parent doing fork-then-exec with inherited descriptors would
   still send, and removing a calling convention nothing here can survey is
   not worth the risk.

   THE NAME IS A SEPARATE ARGUMENT AND MUST BE CONSUMED HERE.  The loop above
   stops at the first argument not beginning with "-", and a pipe name does
   not, so leaving it would end option parsing and then be taken for a command
   to execute.  -TERM consumes its argument the same way.                   */
/* 17 Aug 26 Windows port - THE DESCRIPTOR FORM IS NOW THE ONE THE CLIENT SENDS,
   and it sends "-C1!0", which is two no-op dup2 calls: SDConnectLocal() hands
   the pipes over as this process's STANDARD HANDLES, so they already are 0
   and 1 before main() runs.  Note the order - tx first, rx second.

   THE NAME FORM IS REFUSED RATHER THAN LEFT TO HANG.  It is kept as a branch
   because the code behind it is correct and measured, and the flaw is not in
   it: a descriptor built by cygwin_attach_handle_to_fd() from a raw HANDLE is
   reported PERMANENTLY READY by select(), so sdpoll() answers "input waiting"
   for ever and this process spins reading one byte at a time - alive, silent,
   and never replying.  That is indistinguishable from a hung server, and a
   caller who reaches this branch deserves to be told rather than left to
   diagnose it again.  PROJECT_STATUS.md section 7 step 11 has the measurement
   and gplsrc/win32pipe.c has the mechanism.                                 */
          if (sscanf(argv[arg], "-C%d!%d", &TxPipe, &RxPipe) == 2) {
            dup2(RxPipe, 0);
            dup2(TxPipe, 1);
          } else {
            if (++arg >= argc)
              exit(1);
            fprintf(stderr,
                    "-C with a pipe name is not supported: a descriptor made "
                    "from a raw HANDLE is always ready to select(), so this "
                    "process would never answer.  Pass the pipes as standard "
                    "handles and use -C1!0.  See PROJECT_STATUS.md 7 step 11.\n");
            exit(1);
          }
          break;

        case 'N': /* Network server */
          connection_type = CN_SOCKET;
          break;

        case 'R':
          if (!stricmp(argv[arg], "-RESUME")) {
            check_admin();
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
            check_admin();
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

  /* 13 Aug 26 Windows port - internal mode is for SDSYS and nothing else.

     Internal programs are the only ones allowed to set the administrator
     flag, and BCOMP will only compile one for SDSYS, so an internal session
     in an ordinary account has no business it could legitimately conduct.
     Allowing one was how an account could build itself a program that
     granted it administrator rights - demonstrated, and now closed at both
     ends.  Naming any other account with -INTERNAL is refused rather than
     quietly redirected, so nobody is left wondering where they ended up.

     20 Aug 26 - THE JUSTIFICATION THAT STOOD HERE IS FALSE, AND THE GATE IS
     NOT.  It read: "There is no bypass here: entering SDSYS needs the SDSYS
     password like any other entry", plus a note about LOGIN admitting an
     administrator to a credential-less account with a warning.  Both describe
     the password login DELETED THE NEXT DAY - LOGIN's 14 Aug reversal, its
     history block and the comment at its end: "Login takes no password: the
     operating system authenticated this user before SD started, and the two
     gates above are group membership and elevation."  Written 13 Aug, stale
     on 14 Aug, never updated.  The changelog got this right and this comment
     did not, because a dated entry is superseded by the next one while a
     comment in the present tense just goes on being read.

     WHAT THE GATE ACTUALLY RESTS ON, which never depended on a password:
     ELEVATION, TWICE.  check_admin() above refuses an unelevated session at
     the door, and LOGIN refuses SDSYS to a session without K$ADMINISTRATOR
     (sysmsg 10002), which kernel.c seeds from IsElevated().  So reaching
     SDSYS this way takes a Windows administrator who has actually elevated -
     somebody who can already do anything on the machine, which is why this
     buys an attacker nothing.

     THE FLAG IS UNPUBLISHED, NOT SECRET, and nothing here rests on it being
     unknown.  The source is GPL, so anyone may read this file and find it;
     what "unpublished" means is that --HELP does not list it and no
     user-facing document explains it, because it is for developing SD.  Do
     not add an obscurity argument to the reasoning above - the two elevation
     checks are the protection and they hold against a reader who knows
     everything in this comment.  LOGIN says the same at its K$INTERNAL test.

     The install is not affected - "sd -i" runs $BBPROC, which never goes
     through LOGIN.  See PROJECT_STATUS.md section 5.6.                     */

  if (internal_mode) {
    if ((forced_account != NULL) && stricmp(forced_account, "SDSYS")) {
      fprintf(stderr, "sd: -INTERNAL may only be used with the SDSYS account\n");
      exit(1);
    }
    forced_account = "SDSYS";
  }

  /* Anything else on the command line is considered to be a command
    to be executed.                                                  */

  if (arg < argc) {
/* 15 Aug 26 Windows port - A COMMAND IS A PARAMETER TOO.  Owner's rule,
   15 Aug 2026: "sd LISTF" runs LISTF just as "sd -start" started the server,
   and an unelevated session has no business doing either from the command
   line.

   20 Aug 26 Windows port - THE JUSTIFICATION THAT STOOD HERE WAS FALSE FOR ONE
   DAY, and the gate never rested on it.  It read: "whoever is at the console or
   on Remote Desktop is an administrator, because SD's own accounts are confined
   to ssh".  That was true by construction while every SD account went into
   sdsshonly, which carries SeDenyInteractiveLogonRight and
   SeDenyRemoteInteractiveLogonRight; CREATE.ACCOUNT's RDPACCOUNT keyword skipped
   that group, so for a day a NON-administrator could be at a console.

   21 Aug 26 Windows port - AND IT IS TRUE BY CONSTRUCTION AGAIN.  RDPACCOUNT is
   gone (owner's decision, 21 Aug 2026 - see CREATEA), so every account SD
   creates is in sdsshonly unless Windows already calls it an administrator.
   The old sentence could be restored; it is not, because the gate should not
   depend on it a second time.

   WHAT THE GATE ACTUALLY RESTS ON, which never depended on that claim: it asks
   whether the SESSION IS ELEVATED, not how the person arrived.  A user who
   reaches a console some other way gets an ordinary unelevated token like
   anyone else, so "sd LISTF" is refused for them exactly as it is for an
   unelevated administrator - which is the behaviour wanted.  The old sentence
   explained why the refusal was near-unreachable, not why it was right.

   AN ssh SESSION STILL ARRIVES AT SD ITSELF through ForceCommand rather than
   at a prompt, and that is unchanged.

   THE INCONSISTENCY THIS EXPOSES IS REAL AND IS LEFT ALONE (section 8,
   difficulty 3): from a desktop, "sd LISTF" is refused while "sd" then LISTF
   at the prompt works.  Defensible - the gate is on the command line form, and
   an interactive session is what an account is for - but it only becomes
   visible with this class of user, and it is a decision rather than an
   oversight.

   NOT "with no shell", which this comment claimed until 15 Aug 2026: SH hands
   one back.  It changes nothing about this gate - that shell is still
   unelevated, so "sd LISTF" typed in it is refused like any other - but it is
   why the SD_SESSION guard in comlin() exists at all, and the owner's answer
   to the rest is a menu system inside SD, where SH is never reachable.

   Plain "sd" with nothing after it is untouched: that is how a user reaches
   their own account, and it is the whole of what an ordinary session may do.
   Nothing SD spawns passes a command this way - a phantom carries its command
   in the user table and gets only "-p<n>".                                 */
    check_admin();

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
  bool IsElevated(void);

  /* 13 Aug 26 Windows port - was (geteuid() != 0) && !in_group("admin").
     Neither half means anything here: there is no uid zero on Windows, and
     "admin" is a Linux group name.

     15 Aug 26 Windows port - AND IT NOW ASKS IsElevated(), NOT IsAdmin().
     Owner's rule, 15 Aug 2026: an unelevated session must not be able to
     drive sd from the command line.  It could: "sd -start" and "sd -stop"
     both worked for any administrator who had not elevated, because
     IsAdmin() answers "is this ACCOUNT an administrator" while IsElevated()
     answers "may this PROCESS act as one right now".  That is the same
     distinction PROJECT_STATUS.md 5.6 draws for entry to SDSYS, applied to
     the switches - and an ordinary user was never meant to have it either
     way, since IsAdmin() would have refused them.

     THE COST, STATED: there is no service (PROJECT_STATUS.md 5.7), so SD is
     started by hand, and now only from an elevated window.  After a restart
     nobody but an administrator can bring SD up.

     WHAT IS DELIBERATELY NOT GATED, BECAUSE SD SPAWNS ITSELF.  op_kernel.c
     builds "-p<n>" and forks sd for every PHANTOM, and the client, network
     and API paths use -C, -N and -Q.  Gating them would break phantoms, the
     client library, network logins and the API - the last of which is what
     this port is for (PROJECT_STATUS.md 1).

     20 Aug 26 Windows port - AND THE REASON THAT USED TO BE GIVEN FOR IT IS
     FALSE FOR ONE OF THOSE FOUR.  It read "Those children inherit an ORDINARY
     user's token".  True for PHANTOM and for -C, whose parent is a user's own
     sd.exe.  NOT TRUE FOR THE API: its parent is sdwind, which is a Windows
     service running as LocalSystem, so an API session inherits SYSTEM'S
     token.  Measured 20 Aug 2026 with gplbld/verify-apiadmin.ps1 - a
     PROGRAMMER-tier account over a remote API connection opened and wrote
     $cred, which is granted to SYSTEM and Administrators alone.

     THE DECISION NOT TO GATE IS UNCHANGED AND IS STILL RIGHT - check_admin()
     is about the COMMAND LINE, and these children are spawned by SD rather
     than typed by anybody.  What is wrong is only the sentence that said the
     children are harmless because they are unprivileged.  This is the third
     place in the tree to rest on that assumption; APISRVR carried the other
     two.  PROJECT_STATUS.md's opening section has the finding and the fix
     options, and nothing is fixed yet.                                     */

  if (!IsElevated()) {
    fprintf(stderr, "This command needs an elevated session - "
                    "start the shell with \"Run as administrator\"\n");
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
