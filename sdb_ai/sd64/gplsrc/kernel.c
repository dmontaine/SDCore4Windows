/* KERNEL.C
 * Run Machine Kernel
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
 * 11 Jun 24 mab overwrite op_errmsg (pick error message) and op_pabort (pick abort) as illegal op code
 * 15 Jun 24 mab overwrite op_ttyset op_ttyget as illegal op code
 * 28 Jul 24 mab remove op code overwrites (removed from opcodes.h)
 * 13 Aug 26 Windows port - seed USR_ADMIN from IsAdmin() at process start
 * 14 Aug 26 Windows port - seed it from IsElevated() instead
 * 21 Aug 26 Windows port - and never for a network session, whatever the
 *           token says
 * 25 Aug 26 Windows port - VFS stripped: the C never implemented it
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "revstamp.h"
#include "header.h"
#include "tio.h"
#include "debug.h"
#include "keys.h"
#include "syscom.h"
#include "config.h"
#include "options.h"
#include "dh_int.h"
#include "locks.h"

#include <setjmp.h>
#include <time.h>
#include <stdarg.h>
#include <signal.h>

#include <sys/wait.h>

Private void init_program(void);

/* 13 Aug 26 Windows port - declared here as op_kernel.c does, rather than in a
   header, because linuxlb.c has none of its own.                            */
/* 03 Sep 26 Windows port - THAT REASON WAS NOT TRUE: linuxlb.h has existed all
   along, and sd.h includes it.  The declaration moved there with the signature
   change for PRE_RELEASE_FIXES.md 96.                                       */

jmp_buf k_exit;

/* Declare opcode functions */

#define _opc_(code, key, name, func, format, stack_use) void func(void);
#include "opcodes.h"
#undef _opc_

/* Build dispatch table */

#define _opc_(code, key, name, func, format, stack_use) func,
void (*dispatch[])(void) = {
#include "opcodes.h"
};
#undef _opc_

Private void kill_process(void);
Private void unwind_stack(void);
Private void k_release_vars(void);
Private void dump_status(void);

typedef void (*signal_handler)();
void fatal_signal_handler(int signum);
void sigusr1_handler(int signum);
void set_old_tty_modes(void);

/* ======================================================================
   init_kernel()  -  Kernel initialisation                                */

bool init_kernel() {
  bool status = FALSE;
  int16_t i;
  USER_ENTRY* uptr;
  u_int32_t m;
  int16_t msg_no = 1000; /* User limit reached */
  char* p;
  PRIV_WHY why; /* 03 Sep 26 - PRE_RELEASE_FIXES.md 96 */
  PRIV_WHY why_desktop = PRIV_ANSWERED; /* 05 Sep 26 - PRE_RELEASE_FIXES.md 167.
      Its own out-parameter, because && short-circuits and one variable would
      name the wrong predicate in the log.  Initialised because the same
      short-circuit means IsInteractive() may never run to set it. */

  memset(option_flags, '\0', NumOptions);

  strcpy(national.currency, "$");
  national.thousands = ',';
  national.decimal = '.';

  /* Initialise subsystems. The order is important */

  tzset();

  if (!dio_init())
    goto exit_init_kernel;

  memset((void*)&process, 0, sizeof(struct PROCESS)); /* Set all zero */

  c_base = NULL;

  /* Program control */

  init_program();
  process.program.prev = NULL;
  process.debugging = FALSE;

  /* Common areas */

  process.named_common = NULL;
  process.syscom = NULL;

  /* Opcode actions */

  process.break_inhibits = 1; /* Off until end of LOGIN paragraph */

  if (!tio_init())
    goto exit_init_kernel;

  /* Perform licensing checks.
    For a terminal user, we are looking for a user table entry with a zero
    uid field.  For a phantom user, the user table index is in
    phantom_user_index.                                                    */

  StartExclusive(SHORT_CODE, 23);

  if (is_phantom) {
    my_uptr = UPtr(phantom_user_index);
  } else {
    for (i = 1; i <= sysseg->max_users; i++) {
      uptr = UPtr(i);
      if (uptr->uid == 0) {
        uptr->uid = assign_user_no(i);
        if (uptr->uid == 0) {
          msg_no = 1023; /* Port is already in use */
          goto abort_login;
        }
        my_uptr = uptr;
        break;
      }
    }
  }

  if (my_uptr != NULL) {
    my_uptr->pid = GetCurrentProcessId();
    strcpy((char*)(my_uptr->ip_addr), ip_addr);
    my_uptr->events = 0;
    my_uptr->flags = 0;
    my_uptr->lockwait_index = 0;
    my_uptr->ttyname[0] = '\0';

    /* Ensure file map table is all zero */

    memset((char*)(my_uptr->file_map), 0, sysseg->numfiles * sizeof(u_int16_t));

    if (is_phantom)
      my_uptr->flags |= USR_PHANTOM;
/* 20240219 mab rebrand VBSRVR to APISRVR */
    if (is_sdApiSrvr)
      my_uptr->flags |= USR_SDAPISRVR;

    /* 13 Aug 26 Windows port - seed the administrator flag from the operating
       system.  On Linux the BASIC layer set this itself: CPROC tested
       SYSTEM(27) for uid zero and called KERNEL(K$ADMINISTRATOR, 1) after
       dropping to sdsys.  Neither half of that works here - there is no uid
       zero on Windows - so nothing set the flag and K$ADMINISTRATOR answered
       "no" for everybody, permanently.  Seeding it here gives the BASIC layer
       a truthful answer to ask for.

       14 Aug 26 - and that answer is now "is this session ELEVATED", which is
       narrower than "is this account an administrator" and is the reversal in
       PROJECT_STATUS.md section 5.6.  K$ADMINISTRATOR is what puts a session
       into SDSYS with nothing typed, so it has to mean the deliberate act -
       sudo, not the sudoers file.  An administrator who has not elevated is an
       ordinary SD user, exactly as on Linux.

       IsAdmin() is untouched and still answers the other question, because
       check_admin() in sd.c gates sd -start with it: starting the server
       should not demand elevation of somebody who is already an
       administrator.  See linuxlb.c, where the two sit side by side.        */

    /* 21 Aug 26 Windows port - AND NEVER FOR A NETWORK SESSION.  IsElevated()
       reads the PROCESS token, and an API session's process is forked by
       sdwind and inherits the SERVICE's token: sdwind runs as LocalSystem,
       whose token carries BUILTIN\Administrators, so IsElevated() answered
       TRUE for every remote client and USR_ADMIN was set for all of them.

       MEASURED, 21 Aug 26, from inside the session rather than inferred from
       outside: a PROGRAMMER-tier account over a real remote API connection
       ran "os.execute 'cmd /c whoami'" and SD's own session printed back
       PROBE.WHOAMI=nt_authority_system.  os_permitted() returns TRUE on
       USR_ADMIN, so that was arbitrary command execution as SYSTEM for
       anyone holding an ordinary account's credential.

       AND THE CONTROL INVERTS IT, which is what makes it a measurement: the
       SAME program in the SAME account from a LOCAL ELEVATED session was
       REFUSED.  A local session starts in SDSYS with the flag set and gives
       it up on the way out (CPROC, "administrator rights belong to SDSYS"),
       so os_permitted() says no by the time it reaches the probe.  The API
       session never leaves anywhere, so it kept the flag.  The remote client
       got the operating system and the administrator at the keyboard did not.

       CN_SOCKET IS THE DISCRIMINATOR AND NOT is_sdApiSrvr.  sd.c sets
       CN_SOCKET from -N, which is what sdwind's execl passes; -Q sets
       is_sdApiSrvr and is about the login protocol, not about where the
       session came from.  Gating on the connection is the narrower claim and
       is the same discriminator net_path_permitted() uses, so the two halves
       of the containment cannot drift apart.

       THIS ONLY MAKES THE CODE AGREE WITH WHAT IT ALREADY CLAIMED.
       APISRVR:459 and :489 say outright "an API session cannot have
       K$ADMINISTRATOR" and reason the account gating on it; nothing enforced
       it until now.

       IT IS NOT THE WHOLE FIX, AND MUST NOT BE READ AS ONE.  The $cred write
       measured on 20 Aug went through no privilege flag at all - the probe
       wrote the file from ordinary BASIC - so this closes OS.EXECUTE and
       leaves the file reach open.  net_path_permitted() in op_dio2.c is that
       half, and it depends on this one: without it an API session passes
       logto.authorised on K$ADMINISTRATOR (CPROC:3753), reaches SDSYS, and a
       root that follows the account would follow it there.
       PROJECT_STATUS.md items 4 and 5.                                     */

    /* 03 Sep 26 Windows port - PRE_RELEASE_FIXES.md 96.  THIS WAS THE QUIET
       ONE: USR_ADMIN was simply not set, with no message and no log, and
       os_permitted() (op_sh.c) reads USR_ADMIN, so the loss propagated to
       OS.EXECUTE as a refusal nobody could account for.  The grant is
       unchanged - an undetermined answer still does not set the flag - but it
       is no longer silent.  sysseg is bound well before here (it is
       dereferenced at :170), so the log call is safe.                      */

    /* 05 Sep 26 Windows port - PRE_RELEASE_FIXES.md 167.  AND A DESKTOP, WHICH
       IS THE TERM ssh WAS GETTING PAST.  Owner's ruling, 5 Sep 2026:
       administration requires a session where UAC can RENDER, because that is
       what makes an elevation consented to by a person rather than merely
       granted.  PROJECT_STATUS.md 5.25.

       WHAT WAS MEASURED, AND IT IS THE OPPOSITE OF WHAT THIS FILE BELIEVED.
       q14 held that an administrator over ssh gets a FILTERED token and so
       gets LESS, not more.  On 5 Sep 2026 an administrator ssh'd in and got
       WHO = 3 SDSYS, LIST ACCOUNTS, and an elevated PowerShell from "sh":
       S-1-16-12288 High, BUILTIN\Administrators ENABLED rather than deny-only,
       NT AUTHORITY\NETWORK in the same token.  THE CAUSE IS OpenSSH, NOT SD -
       sshd runs as LocalSystem and builds the logon token itself, so the
       filtering LocalAccountTokenFilterPolicy governs never applies to it.
       IsElevated() therefore answered TRUE, and the line below was the whole
       of the gate.

       CN_SOCKET WAS REACHING FOR THIS AND CAUGHT HALF OF IT.  The 21 Aug term
       excludes a socket-connected session, which is the API; it cannot see
       ssh, because sshd starts sd.exe as an ordinary process on a pty rather
       than connecting to it.  So this is the same intent completed, not a
       second discriminator that could drift away from it.

       ***THE TEST GOES HERE AND NOT INSIDE IsElevated().***  sdwind.c shells
       out to "sd -cleanup" from the daemon as LocalSystem - non-interactive -
       and sd.c gates that verb on IsElevated().  Gating the predicate itself
       would break check_lost_users()'s recovery, which is the exact path whose
       failure once answered every new session "Forced logout" for twenty
       minutes.  IsElevated() keeps its present meaning for sd.c and sdsem.c.

       A PHANTOM INHERITS THE SEED AND THAT IS RULED, NOT OVERLOOKED.  Owner,
       5 Sep 2026.  op_phantom() forks and execs, so a phantom carries its
       parent's token and tests interactive when the parent did; the consent
       happened once, at a real desktop, and the phantom is that session's own
       work continued.  linuxlb.c's IsInteractive() carries the reasoning.

       IT IS NOT THE WHOLE FIX EITHER.  This closes LOGIN's landing case, which
       is the door the measurement came through.  LOGTO SDSYS is a SECOND door
       and does not read this flag at all - it asks K$OS.ADMINISTRATOR, so the
       same term is in op_kernel.c beside the same CN_SOCKET guard.  Without
       both, an administrator lands in their own account over ssh and types
       "logto sdsys" to get everything back, because CPROC re-grants this very
       flag on entering SDSYS.                                              */

    if (IsElevated(&why) && (connection_type != CN_SOCKET) &&
        IsInteractive(&why_desktop)) {
      my_uptr->flags |= USR_ADMIN;
    } else {
      /* WHICHEVER OF THE TWO COULD NOT ANSWER, and not just the first.  Two
         out-parameters rather than one, because && short-circuits: reusing a
         single "why" would leave IsElevated()'s PRIV_ANSWERED standing when it
         was IsInteractive() that failed to complete, and the log would then
         name the wrong predicate - the exact class of wrong-reason defect
         PRE_RELEASE 96 was filed for.                                      */
      if (why != PRIV_ANSWERED)
        priv_log_undetermined("USR_ADMIN at session start", why);
      else if (why_desktop != PRIV_ANSWERED)
        priv_log_undetermined("USR_ADMIN at session start (desktop test)",
                              why_desktop);
    }

    /* Phantom processes have the user name entered by the parent when the
      user table entry is reserved.  For other users, initialise this now. */

    if (!is_phantom) {
      m = MAX_USERNAME_LEN + 1;
      if (!GetUserName((char*)(my_uptr->username), &m)) {
        my_uptr->username[0] = '\0';
      }
      p = ttyname(fileno(stdin));
      if (p != NULL) {
        strncpy((char*)(my_uptr->ttyname), p, MAX_TTYNAME_LEN);
        my_uptr->ttyname[MAX_TTYNAME_LEN] = '\0';
      }
    }
  }

abort_login:
  EndExclusive(SHORT_CODE);

  if (my_uptr == NULL) /* Failed to login - Message key is in msg_no */
  {
    tio_printf("%s\n", sysmsg(msg_no));
    sleep(2);
    goto exit_init_kernel;
  }

  my_uptr->login_time = sdtime();

  process.user_no = my_uptr->uid;
  strcpy(process.username, (char*)(my_uptr->username));

  status = TRUE;

exit_init_kernel:

  return status;
}

/* ======================================================================
   Initialise PROGRAM structure on first entry or CALL                    */

Private void init_program() {
  process.program.vars = NULL;
  process.program.col1 = 0;
  process.program.col2 = 0;
  process.program.saved_capture_head = NULL;
  process.program.precision = 4;
  process.program.gosub_depth = 0;
  process.program.break_handler = NULL;
}

/* ======================================================================
   assign_user_no()
   NOTE: The caller must own the SHORT_CODE semaphore.
   Returns the user number, or zero if clash of fixed port/user           */

int16_t assign_user_no(int16_t user_table_index) {
  int16_t i;
  int16_t hi;
  int16_t portmap_lo_user = 9999;
  int16_t portmap_hi_user;
  int16_t portmap_lo_port;
  int16_t portmap_range;
  int16_t fixusers_lo_user = 9999;
  int16_t fixusers_hi_user;

  /* Copy FIXUSERS and PORTMAP related parameters from shared memory
    for best performance                                             */

  if (sysseg->fixusers_range != 0) {
    fixusers_lo_user = sysseg->fixusers_base;
    fixusers_hi_user = fixusers_lo_user + sysseg->fixusers_range - 1;

    if ((forced_user_no >= fixusers_lo_user) &&
        (forced_user_no < fixusers_hi_user)) {
      /* This user is trying to logon as a specific user number */

      if (*(UMap(forced_user_no)))
        return 0;
      *(UMap(forced_user_no)) = user_table_index;
      return forced_user_no;
    }
  }

  if ((portmap_range = sysseg->portmap_range) != 0) {
    portmap_lo_user = sysseg->portmap_base_user;
    portmap_hi_user = portmap_lo_user + portmap_range - 1;
    portmap_lo_port = sysseg->portmap_base_port;

    if ((port_no >= portmap_lo_port) &&
        (port_no < portmap_lo_port + portmap_range)) {
      /* This user has arrived from a port with a fixed user mapping */

      i = portmap_lo_user + port_no - portmap_lo_port;

      if (*(UMap(i)))
        return 0;

      *(UMap(i)) = user_table_index;
      return i;
    }
  }

  /* Starting at the next user number in cyclic order, find the first
    available user number (there must be one).                        */

  i = sysseg->last_user;
  hi = sysseg->hi_user_no;
  do {
    i = (i % hi) + 1;
    if ((i >= portmap_lo_user) && (i <= portmap_hi_user)) {
      /* Skip reserved ports */
      i = (portmap_hi_user % hi) + 1;
    } else if ((i >= fixusers_lo_user) && (i <= fixusers_hi_user)) {
      /* Skip reserved ports */
      i = (fixusers_hi_user % hi) + 1;
    }
  } while (*(UMap(i)));

  sysseg->last_user = i;
  *(UMap(i)) = user_table_index;

  return i;
}

/* ======================================================================
   Kernel                                                                 */

void kernel() {
  int32_t retained_flags;
  char processor[MAX_PROGRAM_NAME_LEN + 1];
  bool aborting = FALSE;

  signal(SIGSEGV, fatal_signal_handler);
  signal(SIGILL, fatal_signal_handler);

  signal(SIGBUS, fatal_signal_handler);
  signal(SIGCHLD, sigchld_handler);
  signal(SIGUSR1, sigusr1_handler);

  /* Call the command processor in the new process */

  k_call(command_processor, 0, NULL, 0);

  if (setjmp(k_exit)) /* Abort, Quit, Logout */
  {
    unwind_stack();           /* Tidy up e-stack */
    process.for_init = FALSE; /* Not initialising FOR loop */
    process.op_flags = 0;     /* Clear opcode prefix flags */
    retained_flags = 0;

    switch (k_exit_cause) {
      case K_ABORT:
        if (my_uptr->lockwait_index)
          clear_lockwait();
        collation = primary_collation; /* Clear down use of AK collation map */
        txn_abort();
        clear_select(0);
        aborting = TRUE;
        process.k_abort_code = 1; /* Set @ABORT.CODE */
        break;

      case K_QUIT:
        process.k_abort_code = 2; /* Set @ABORT.CODE */
        break;

      case K_TERMINATE: /* Forced logout of process */
        txn_abort();
        /* Cast off all but bottom level process (which must be a command
           processor), decrementing command level for each stacked processor */

        while (process.call_depth > 1) {
          if (process.program.flags & HDR_IS_CPROC)
            cproc_level--;
          k_return();
        }
        process.k_abort_code = 3; /* Set @ABORT.CODE */
        break;

      case K_LOGOUT: /* Immediate termination of process */
        txn_abort();
        kill_process();
        goto exit_kernel;
    }

    k_exit_cause = 0;

    /* Cast off all programs down to and including one with the HDR_IS_CPROC
      flag set. Then re-call the same processor, retaining the IS_EXECUTE
      and IGNORE_ABORTS flags from the aborted command processor.           */

    while (!(process.program.flags & HDR_IS_CPROC)) {
      k_return();
    }

    if (aborting) {
      aborting = FALSE;
      if (capturing) {
        if (capture_head != NULL) {
          s_free(capture_head);
          capture_head = NULL;
        }
        capturing = FALSE; /* 0117 Target variable has gone... */
        unstack_display_pu();
      }
      rtnlist = FALSE; /* ...so has RTNLIST variable */
    }

    retained_flags = process.program.flags & (IS_EXECUTE | IGNORE_ABORTS);
    strcpy(processor, ((OBJECT_HEADER*)c_base)->ext_hdr.prog.program_name);

    k_return();

    k_call(processor, 0, NULL, 0);

    process.program.flags |= retained_flags;
  }

  recursion_depth = -1;
  k_run_program();

exit_kernel:
  como_close();

  return;
}

/* ======================================================================
   kill_process()  -  Remove process                                      */

Private void kill_process() {
  int16_t i;

  /* Release task locks owned by this process */

  for (i = 0; i < 64; i++) {
    if (sysseg->task_locks[i] == process.user_no)
      sysseg->task_locks[i] = 0;
  }

  /* Give away process resources */

  unwind_stack(); /* Release all e-stack variables */

  k_free(e_stack_base); /* Free e-stack memory */

  while (process.call_depth) /* Unwind program levels */
  {
    k_return();
  }

  free_common(process.named_common);

  free_print_units();

  como_close(); /* Close any como file and free buffer */

  StartExclusive(SHORT_CODE, 22);

  /* Release licence */

  ReleaseLicence(my_uptr);

  EndExclusive(SHORT_CODE);
}

/* ======================================================================
   k_run_program()  -  Dispatch loop                                      */

void k_run_program() /* Returns FALSE if aborts */
{
  u_int32_t flags;
  DESCRIPTOR* restored_e_stack;

  k_exit_cause = 0;
  recursion_depth++;

  do {
    while (!k_exit_cause) {
      dispatch[*(op_pc = pc++)]();
    }

    switch (k_exit_cause) {
      case K_CHAIN_PROC:
        if (my_uptr->lockwait_index)
          clear_lockwait();

        if (recursion_depth) {
          if (!(process.program.flags & (HDR_ITYPE | HDR_IS_CLASS))) {
            k_error("Termination in recursive code");
          }
        }

        /* Cast off all programs down to but not including one with
             the HDR_IS_CPROC flag set.                               */

        while (!(process.program.flags & HDR_IS_CPROC)) {
          k_return();
        }

        k_exit_cause = 0;
        break;

      case K_STOP:
        if (my_uptr->lockwait_index)
          clear_lockwait();

        /* Cast off all programs down to but not including one with
             the HDR_IS_CPROC or IS_CLEXEC flag set.                    */

        while (
            !((flags = process.program.flags) & (HDR_IS_CPROC | IS_CLEXEC))) {
          /* Cast of any e_stack items that are from partially
               evaluated expressions in the terminated program.  */

          restored_e_stack = e_stack_base + process.program.e_stack_depth;
          while (e_stack != restored_e_stack)
            k_dismiss();

          k_return();

          /* If this was a recursive, return to caller, leaving
               k_exit_cause set.                                  */

          if (flags & HDR_RECURSIVE) {
            k_exit_cause = K_STOP;
            return;
          }
        }

        if (process.program.flags & IS_CLEXEC)
          k_return(); /* 0510 */

        k_exit_cause = 0;
        break;

      case K_CHAIN:
        if (my_uptr->lockwait_index)
          clear_lockwait();

        if (recursion_depth) {
          if (!(process.program.flags & (HDR_ITYPE | HDR_IS_CLASS))) {
            k_error("Termination in recursive code");
          }
        }

        /* Cast off all programs down to but not including one with
             the HDR_IS_CPROC flag set.                               */

        while (!(process.program.flags & HDR_IS_CPROC)) {
          k_return();
        }

        k_exit_cause = 0;
        break;

      case K_ABORT:
      case K_LOGOUT:
      case K_TERMINATE:
        if (my_uptr->lockwait_index)
          clear_lockwait();
        Element(process.syscom, SYSCOM_ITYPE_MODE)->data.value = 0;
        longjmp(k_exit, k_exit_cause);
        break;

      case K_RETURN:
        if (process.program.prev == NULL) /* Final return */
        {
          goto exit_run_program; /* The end */
        } else {
          k_exit_cause = 0;
          k_return();
        }
        break;

      case K_QUIT: /* Quit handler activated */
        break_pending = FALSE;
        if (!tio_handle_break()) {
          longjmp(k_exit, k_exit_cause);
        }
        break;

      case K_EXIT_RECURSIVE:
        goto exit_run_program;

      case K_TOGGLE_TRACER: /* Change in trace or monitor mode setting */
        k_exit_cause = 0;
        break;
    }
  } while ((k_exit_cause == 0) || (k_exit_cause == K_QUIT) ||
           (k_exit_cause == K_STOP)); /* 0531 */

exit_run_program:
  if (--recursion_depth == 0) /* Returning from outermost recursive code */
  {
    if (break_pending && !process.break_inhibits) {
      k_exit_cause = K_QUIT;
    }
  }

  return;
}

/* ======================================================================
   op_prefix()  -  Secondary dispatch                                     */

void op_prefix() {
  dispatch[256 + *(pc++)]();
}

/* ======================================================================
   k_return()  -  Return to previous call level                           */

void k_return() {
  struct PROGRAM* prg;
  u_int32_t old_flags;
  OBJECT_HEADER* obj_hdr;

  k_release_vars(); /* 0495 Release local variables */

  obj_hdr = (OBJECT_HEADER*)c_base;
  /* Modified by Composer AI - 2026/06/10.
     Defensive check: k_return() must only run with a loaded object. If
     c_base is NULL, report a fatal error (k_error() aborts to the kernel
     loop when no object is loaded) instead of dereferencing NULL. */
  if (obj_hdr == NULL) {
    k_error("k_return() called with no object loaded");
    return; /* Not reached - k_error() aborts */
  }
  /* -------------------- */
  if ((obj_hdr->id == 0) /* Return from recursive program */
      || (process.program.flags & (PF_IS_TRIGGER | HDR_IS_CLASS))) {
    k_exit_cause = K_EXIT_RECURSIVE;
  } else {
    if ((--(obj_hdr->ext_hdr.prog.refs) == 0) &&
        (obj_hdr->id < 0)) /* Expired runfile */
    {
      unload_object((void*)obj_hdr);
    }
  }

  old_flags = process.program.flags;

  /* Free break handler name, if defined */

  if (process.program.break_handler != NULL) {
    k_free(process.program.break_handler);
  }

  if ((prg = process.program.prev) != NULL) {
    /* Look for a stacked EXECUTE...CAPTURING construct.
      This has to be because the executed program stopped or aborted
      and hence we did not execute the CAPTURE opcode in the parent program.
      Discard any data collected at the current level and reinstate the
      previous capture string.                                              */

    if (process.program.flags & PF_CAPTURING) {
      if (capturing) /* Probably must be true */
      {
        s_free(capture_head);
      }

      capture_head = process.program.saved_capture_head;
      capture_tail = process.program.saved_capture_tail;
      capturing = TRUE;
    }

    process.program = *prg;
    k_free((void*)prg);
    c_base = process.program.saved_c_base;
    pc = c_base + process.program.saved_pc_offset;
  } else {
    init_program();
    process.program.flags = 0;
    c_base = NULL;
  }

  if (hsm)
    hsm_enter();

  if (--process.call_depth == 0) /* Exit from bottom level */
  {
    k_exit_cause = K_LOGOUT;
  }

  if (old_flags & SORT_ACTIVE) {
    op_sortclr();
  }

  if (old_flags & IS_EXECUTE) {
    tio.prompt_char = process.program.saved_prompt_char;
  }

  if (old_flags & HDR_IS_DEBUGGER) {
    /* Returning from debugger to program being debugged.
      Restore saved items from process structure.        */

    process.status = debug_status;
    process.inmat = debug_inmat;
    tio.suppress_como = debug_suppress_como;
    tio.hush = debug_hush;
    capturing = debug_capturing;
    tio.prompt_char = debug_prompt_char;
    tio.dsp.line = debug_dsp_line;
    if (debug_dsp_paginate)
      tio.dsp.flags |= PU_PAGINATE;
    else
      tio.dsp.flags &= ~PU_PAGINATE;
    in_debugger = FALSE;
  } else { /* Not returning from debugger to program being debugged */
  
  }
}

/* ======================================================================
   k_call()  -  Call program

   If the code_ptr argument is null, we perform a search for this object
   name.  Otherwise we simply call the object at that address.             */

void k_call(char* name, int num_args, u_char* code_ptr, int16_t stack_adj) {
  /* code_ptr - For in-line code items */
  /* stack_adj - No of stack items to be removed before running */

  struct OBJECT_HEADER* hdr;
  unsigned int mem_reqd;
  int i;
  DESCRIPTOR* p;
  DESCRIPTOR* q;
  DESCRIPTOR* new_stack;
  struct PROGRAM* prg;
  int new_stack_depth;

  if (process.call_depth == pcfg.maxcall)
    k_error(sysmsg(1140)); /* CALLs nested too deeply */

  /* Find the program. We omit this step for recursive calls as the program
    pointers will already be set.                                          */

  if (code_ptr == NULL) { /* Dynamically loaded object */
    hdr = (OBJECT_HEADER*)load_object(name, FALSE);
    if (hdr == NULL)
      k_error(sysmsg(1002), name);

    hdr->ext_hdr.prog.refs++;

    if (hdr->flags & HDR_IS_CLASS) {
      k_error(sysmsg(3450)); /* A CLASS routine may not be used in this way */
    }
  } else { /* In-line object, recursive or call via SUBR */
    hdr = (struct OBJECT_HEADER*)code_ptr;
  }

  if (c_base != NULL) {
    /* Save previous PROGRAM state */

    prg = (struct PROGRAM*)k_alloc(18, sizeof(struct PROGRAM));
    /* Modified by Composer AI - 2026/06/10.
       k_error() aborts via longjmp for fatal messages but the compiler
       cannot know that; add an explicit return so no path can continue
       into the dereference of prg below. */
    /* if (prg == NULL)
      k_error(sysmsg(1003)); */
    if (prg == NULL) {
      k_error(sysmsg(1003));
      return; /* Not reached - k_error() aborts */
    }
    /* -------------------- */

    process.program.saved_pc_offset = pc - c_base;
    process.program.saved_prompt_char = tio.prompt_char;
    *prg = process.program;
    process.program.prev = prg;

    process.program.flags &= FLAG_COPY_MASK;
  } else {
    process.program.flags = 0;
  }

  process.call_depth++;
  init_program();

  c_base = (u_char*)hdr;
  process.program.saved_c_base = c_base;

  if (hsm)
    hsm_enter();

  /* Find start of program execution */

  pc = c_base + hdr->start_offset;

  /* Allocate descriptor area */

  process.program.no_vars = hdr->no_vars;
  if (process.program.no_vars == 0) {
    process.program.vars = NULL;
  } else {
    mem_reqd = process.program.no_vars * sizeof(DESCRIPTOR);

    process.program.vars = (DESCRIPTOR*)k_alloc(19, mem_reqd);
    if (process.program.vars == NULL) {
      /* Insufficient memory for program variables */
      k_error(sysmsg(1004));
    }

    for (i = 0, p = process.program.vars; i < process.program.no_vars;
         i++, p++) {
      InitDescr(p, UNASSIGNED);
    }
  }

  if ((hdr->flags & HDR_VAR_ARGS) ? (num_args > hdr->args)
                                  : (num_args != hdr->args)) {
    /* Argument count mismatch */
    k_return(); /* Return to caller so that message relates to CALL */
    k_error(sysmsg(1005),
            ((name == NULL) || (*name == '\0')) ? ProgramName(hdr) : name,
            num_args, hdr->args);
  }

  process.program.arg_ct = num_args;
  if (num_args) {
    /* Copy arguments currently on e-stack into new vars */

    for (i = num_args, p = e_stack - num_args, q = process.program.vars; i > 0;
         i--) {
      *q = *(p++);
      q->flags |= DF_ARG;
      q++;
    }
    e_stack -= num_args; /* Remove from e-stack. Do not release as copied */
  }

  /* Save e_stack depth */

  process.program.e_stack_depth = e_stack - e_stack_base - stack_adj;

  /* Ensure evaluation stack is big enough (0280)
    The program header includes an estimate of the depth needed to run this
    program. This should never be too low though the compiler doesn't do
    full stack tracking yet. Add a little extra to allow for pushing
    arguments to recursives.                                                */

  if (e_stack_depth < hdr->stack_depth + (e_stack - e_stack_base) + 10) {
    new_stack_depth = e_stack_depth + hdr->stack_depth + 10;

    /* Allocate new stack */

    mem_reqd = new_stack_depth * sizeof(DESCRIPTOR);
    new_stack = (DESCRIPTOR*)k_alloc(20, mem_reqd);
    /* Modified by Composer AI - 2026/06/10.
       k_error() aborts via longjmp for fatal messages but the compiler
       cannot know that; add an explicit return so no path can continue
       into the initialization loop with new_stack == NULL. */
    /* if (new_stack == NULL) / * Insufficient memory for stack * /
    {
      k_error(sysmsg(1006));
    } */
    if (new_stack == NULL) /* Insufficient memory for stack */
    {
      k_error(sysmsg(1006));
      return; /* Not reached - k_error() aborts */
    }
    /* -------------------- */

    e_stack_depth = new_stack_depth;

    for (i = e_stack_depth, p = new_stack; i--; p++) {
      InitDescr(p, UNASSIGNED);
    }

    /* Copy any existing e-stack items and free old stack */

    p = e_stack; /* Old stack */
    e_stack = new_stack;
    if (p != NULL) {
      i = p - e_stack_base;
      q = e_stack_base;
      while (i--)
        *(e_stack++) = *(q++);

      k_free((void*)e_stack_base);
    }

    e_stack_base = new_stack;
  }

  /* Set flags */

  process.program.flags |= hdr->flags;
}

/* ======================================================================
   k_recurse()  -  Execute recursive program                              */

void k_recurse(u_char* code_ptr, int num_args) {
  /* Set up to run recursive code */

  k_call("", num_args, code_ptr, 0);

  /* Execute program */

  k_run_program();

  /* Ensure that we reassess trace mode in the lower layer */
  if (k_exit_cause == K_EXIT_RECURSIVE)
    k_exit_cause = K_TOGGLE_TRACER;
}

/* ======================================================================
   k_recurse_object()  -  Execute recursive CLASS object program          */

void k_recurse_object(u_char* code_ptr, int num_args, OBJDATA* objdata) {
  /* Set up to run recursive code */

  k_call("", num_args, code_ptr, 0);
  process.program.objdata = objdata;
  k_run_program(); /* Execute program */

  /* Ensure that we reassess trace mode in the lower layer */
  if (k_exit_cause == K_EXIT_RECURSIVE)
    k_exit_cause = K_TOGGLE_TRACER;
}

/* ======================================================================
   Unwind the evaluation stack at error or on killing process             */

Private void unwind_stack() {
  if (e_stack_depth) {
    while (e_stack != e_stack_base) {
      k_dismiss();
    }
  }
}

/* ======================================================================
   k_release_vars()  -  Unwind var stack prior to return from long call   */

Private void k_release_vars() {
  int i;
  DESCRIPTOR* p;

  if (process.program.vars != NULL) {
    /* Release memory for all variables at this level */

    for (i = 0, p = process.program.vars; i < process.program.no_vars;
         i++, p++) {
      /* Cancel debugger watch */
      if (p == watch_descr)
        watch_descr = NULL;

      /* Release all memory hung off descriptors */
      k_release(p);
    }

    k_free((void*)process.program.vars);
    process.program.vars = NULL;
  }
}

/* ======================================================================
   raise_event()  -  Raise event in one/all processes                     */

bool raise_event(int16_t event, /* Event to raise */
                 int16_t user)  /* User number. -ve to raise in all users */
{
  bool status = FALSE;
  USER_ENTRY* uptr;
  int16_t u;

  StartExclusive(SHORT_CODE, 65);

  for (u = 1; u <= sysseg->max_users; u++) {
    uptr = UPtr(u);
    if (uptr->uid) {
      if ((uptr->uid == user) || (user < 0)) {
        uptr->events |= event;
        if (event & (EVT_LOGOUT | EVT_TERMINATE | EVT_LICENCE)) {
          uptr->flags |= USR_LOGOUT;
        }
        status = TRUE;
        if (user >= 0)
          break;
      }
    }
  }

  EndExclusive(SHORT_CODE);

  return status;
}

/* ======================================================================
   process_events()  -  Process events from USER_ENTRY events word        */

void process_events() {
  int16_t events;
  static u_int16_t event_mask = 0xFFFF;
  u_int16_t defered_events;
  int32_t saved_status;
  int32_t saved_os_error;
  int32_t saved_inmat;
  bool saved_suppress_como;
  bool saved_capturing;
  bool saved_hush;
  int32_t saved_dsp_line;
  bool saved_dsp_paginate;
  STRING_CHUNK* str;
  DESCRIPTOR* ipc_descr; /* SYSCOM IPC.F file variable... */
  FILE_VAR* fvar;        /* ...its FVAR and... */
  DH_FILE* dh_file;      /* ...its DH_FILE structure */
  char id[16 + 1];

  /* Take a copy of the event flags and clear all events */

  StartExclusive(SHORT_CODE, 24);
  events = my_uptr->events & event_mask;
  defered_events = my_uptr->events & ~event_mask;
  my_uptr->events &= ~events;
  EndExclusive(SHORT_CODE);

  if (events & (EVT_LOGOUT | EVT_LICENCE)) /* Terminate process immediately */
  {
    if (events & EVT_LICENCE) {
      tio_printf("\n\nLicence expired\n\n");
      Sleep(3000);
    }
    k_exit_cause = K_LOGOUT;
    return; /* Ignore any other events */
  }

  if (events & EVT_TERMINATE) /* Terminate process gracefully */
  {
    k_exit_cause = K_TERMINATE;
    return; /* Ignore any other events */
  }

  if (events & EVT_STATUS) /* Status dump */
  {
    dump_status();
  }

  if (events & EVT_UNLOAD) /* Unload inactive cached object code */
  {
    unload_all();
  }

  if (events & EVT_BREAK) /* Clear break inhibit counter */
  {
    process.break_inhibits = 0;
  }

  if (events & EVT_HSM_ON) /* Enable HSM in this process */
  {
    hsm_on();
  }

  if (events & EVT_HSM_DUMP) /* Return HSM data */
  {
    ipc_descr = Element(process.syscom, SYSCOM_IPC);
    if ((ipc_descr->type == FILE_REF) &&
        ((fvar = ipc_descr->data.fvar) != NULL) &&
        ((dh_file = fvar->access.dh.dh_file) != NULL)) {
      str = hsm_dump();
      sprintf(id, "H%d", (int)process.user_no);
      dh_write(dh_file, id, strlen(id), str);
      s_free(str);
    }
  }

  if (events & EVT_PDUMP) /* Force process dump */
  {
    pdump();
  }

  if (events & EVT_FLUSH_CACHE) /* Flush DH cache */
  {
    flush_dh_cache();
  }

  if (events & EVT_MESSAGE) /* Send immediate message */
  {
    /* Save items from process structure that must not be trampled on by
      the recursive code.                                               */

    saved_status = process.status;
    saved_os_error = process.os_error;
    saved_inmat = process.inmat;
    saved_suppress_como = tio.suppress_como;
    tio.suppress_como = TRUE;
    saved_capturing = capturing;
    capturing = FALSE;
    saved_hush = tio.hush;
    tio.hush = FALSE;
    saved_dsp_line = tio.dsp.line;
    saved_dsp_paginate = (tio.dsp.flags & PU_PAGINATE) != 0;
    tio.dsp.flags &= ~PU_PAGINATE;

    event_mask &= ~EVT_MESSAGE;
    k_recurse(pcode_message, 0);
    event_mask |= EVT_MESSAGE;

    /* Now restore all the things we saved */

    process.status = saved_status;
    process.os_error = saved_os_error;
    process.inmat = saved_inmat;
    tio.suppress_como = saved_suppress_como;
    capturing = saved_capturing;
    tio.hush = saved_hush;
    tio.dsp.line = saved_dsp_line;
    if (saved_dsp_paginate)
      tio.dsp.flags |= PU_PAGINATE;
  }

  if (events & EVT_REBUILD_LLT) {
    rebuild_llt();
  }

  my_uptr->events |= defered_events;
}

/* ======================================================================
   account()  -  Return account name pointer                              */

char* account() {
  DESCRIPTOR* syscom_descr;
  static char account_name[MAX_ACCOUNT_NAME_LEN + 1];

  /* Find WHO in SYSCOM */

  syscom_descr = Element(process.syscom, SYSCOM_WHO);
  (void)k_get_c_string(syscom_descr, account_name, MAX_ACCOUNT_NAME_LEN);
  return account_name;
}

/* ======================================================================
   show_stack()  -  Stack report                                          */

void show_stack() {
  struct PROGRAM* prg;
  int32_t offset;
  int16_t i;
  int line;

  prg = &(process.program);
  offset = pc - c_base;
  do {
    line = k_line_no(offset, prg->saved_c_base);
    if (line < 0) {
      tio_printf("%s (%08X)\n", ProgramName(prg->saved_c_base), offset);
    } else {
      tio_printf("%s %d (%08X)\n", ProgramName(prg->saved_c_base), line,
                 offset);
    }

    /* Local gosub return pointers
           Back up to point to GOSUB rather than to return address */

    for (i = prg->gosub_depth - 1; i >= 0; i--) {
      offset = prg->gosub_stack[i] - 1; /* Back up to GOSUB (etc) */
      line = k_line_no(offset, prg->saved_c_base);
      if (line < 0)
        tio_printf("  (%08X)\n", offset);
      else
        tio_printf("  %d (%08X)\n", line, offset);
    }

    if ((prg = prg->prev) == NULL)
      break;

    offset = prg->saved_pc_offset - 1; /* Back up into CALL */
  } while (1);
}

/* ======================================================================
   dump_status()  -  Handle status dump event

   F1 = userno VM pid VM flags
   F2 = command
   F3 = program stack
           {name {SM offset TM line ...}VM name etc...}
   F4 = Lock wait : user VM filepath VM id
   F5 = account
*/

Private void ev_printf(char* template_string, ...);
Private STRING_CHUNK* ev_head;
Private STRING_CHUNK* ev_tail;

Private void dump_status() {
  DESCRIPTOR* ipc_descr; /* SYSCOM IPC.F file variable... */
  FILE_VAR* fvar;        /* ...its FVAR and... */
  DH_FILE* dh_file;      /* ...its DH_FILE structure */
  char id[16 + 1];
  struct PROGRAM* prg;
  int32_t offset;
  int16_t i;
  STRING_CHUNK* str;
  RLOCK_ENTRY* lptr;
  FILE_ENTRY* fptr;

  ev_head = NULL;
  ev_tail = NULL;

  ipc_descr = Element(process.syscom, SYSCOM_IPC);
  if ((ipc_descr->type != FILE_REF) ||
      ((fvar = ipc_descr->data.fvar) == NULL) ||
      ((dh_file = fvar->access.dh.dh_file) == NULL))
    return;

  /* Be brutal - Lock everything in sight */

  StartExclusive(FILE_TABLE_LOCK, 57);
  StartExclusive(REC_LOCK_SEM, 57);
  StartExclusive(GROUP_LOCK_SEM, 57);
  StartExclusive(SHORT_CODE, 57);

  /* Field 1  -  User (process) information */

  ev_printf("%d%c%d%c%d%c", (int)process.user_no, /* Q_M process number */
            VALUE_MARK, (int)(my_uptr->pid),      /* OS process number */
            VALUE_MARK, (int)(my_uptr->flags),    /* Process flags */
            FIELD_MARK);

  /* Field 2  -  Command */

  str = Element(process.syscom, SYSCOM_LAST_COMMAND)->data.str.saddr;
  while (str != NULL) {
    ev_printf("%.*s", (int)(str->bytes), str->data);
    str = str->next;
  }
  ev_printf("%c", FIELD_MARK);

  /* Field 3  -  Call stack */

  if (c_base != NULL) {
    prg = &(process.program);

    /* Set up current location.
      The event processor has been called from some opcode, usually a jump.
      At this point, PC will probably point one byte beyond the opcode.
      Back it up by one byte.                                               */

    offset = pc - c_base - 1;
    do {
      ev_printf("%s%c%d%c%d", ProgramName(prg->saved_c_base), SUBVALUE_MARK,
                offset, TEXT_MARK, k_line_no(offset, prg->saved_c_base));

      /* Local gosub return pointers
          Back up to point to GOSUB rather than to return address */

      for (i = prg->gosub_depth - 1; i >= 0; i--) {
        offset = prg->gosub_stack[i] - 1; /* Back up to GOSUB (etc) */
        ev_printf("%c%d%c%d", SUBVALUE_MARK, offset, TEXT_MARK,
                  k_line_no(offset, prg->saved_c_base));
      }

      if ((prg = prg->prev) == NULL)
        break;

      offset = prg->saved_pc_offset - 1; /* Back up into CALL */
      ev_printf("%c", VALUE_MARK);
    } while (1);
  }

  ev_printf("%c", FIELD_MARK);

  /* Field 4  -  Lock wait data */

  if ((i = my_uptr->lockwait_index) != 0) {
    if (i > 0) /* Waiting for record lock */
    {
      lptr = RLPtr(i);
      ev_printf("%d%c%s%c%.*s", lptr->owner, VALUE_MARK,
                FPtr(lptr->file_id)->pathname, VALUE_MARK, lptr->id_len,
                lptr->id);
    } else /* Waiting for file lock */
    {
      fptr = FPtr(-i);
      ev_printf("%d%c%s%c", abs(fptr->file_lock), VALUE_MARK, fptr->pathname,
                VALUE_MARK);
    }
  }

  /* Field 5  -  Account name */

  ev_printf("%c%s", FIELD_MARK, account());

  EndExclusive(SHORT_CODE);
  EndExclusive(GROUP_LOCK_SEM);
  EndExclusive(REC_LOCK_SEM);
  EndExclusive(FILE_TABLE_LOCK);

  sprintf(id, "S%d", (int)process.user_no);
  dh_write(dh_file, id, strlen(id), ev_head);
  s_free(ev_head);
}

Private void ev_printf(char* template_string, ...) {
  char s[500];
  va_list arg_ptr;
  int16_t len;
  int16_t bytes_to_move;
  int16_t bytes_remaining;
  char* p;

  if (ev_head == NULL) /* First call */
  {
    ev_head = s_alloc(512, &bytes_remaining);
    ev_head->ref_ct = 1;
    ev_head->string_len = 0;
    ev_tail = ev_head;
  } else
    bytes_remaining = ev_tail->alloc_size - ev_tail->bytes;

  va_start(arg_ptr, template_string);

  len = vsprintf(s, template_string, arg_ptr);
  p = s;
  while (len > 0) {
    /* Allocate new chunk if the current one is full */

    if (bytes_remaining == 0) {
      ev_head->string_len += ev_tail->bytes;
      ev_tail->next = s_alloc(512, &bytes_remaining);
      ev_tail = ev_tail->next;
    }

    /* Copy what will fit into current chunk */

    bytes_to_move = min(bytes_remaining, len);
    memcpy(ev_tail->data + ev_tail->bytes, p, bytes_to_move);
    p += bytes_to_move;
    ev_tail->bytes += bytes_to_move;
    ev_head->string_len += bytes_to_move;
    len -= bytes_to_move;
    bytes_remaining -= bytes_to_move;
  }

  va_end(arg_ptr);
}

/* ======================================================================
   SIGCHLD handler                                                        */

void sigchld_handler(int signum) {
  int pid;
  int status;
  int stacked_errno;

  stacked_errno = errno;
  do {
    pid = waitpid(-1, &status, WNOHANG);
  } while (pid > 0);
  errno = stacked_errno;
}

/* ======================================================================
   SIGUSR1 handler                                                        */

void sigusr1_handler(int signum) {
  return;
}

/* ======================================================================
   Fatal signal handler                                                   */

void fatal_signal_handler(int signum) {
  set_old_tty_modes();
  log_printf("Fault type %d. PC = %08lX (%02X %02X) in %s\n", signum,
             op_pc - c_base, *op_pc, *(op_pc + 1), ProgramName(c_base));

  printf("Errno : %08X\n", OSError);

  {
    int i;
    DESCRIPTOR* descr;

    /* Show area around top of e-stack */

    for (i = 4; i >= -4; i--) {
      descr = e_stack + i;
//#warning "Casting to int64_t may not be the right solution for this."
#ifndef __LP64__ /* 09Jan22 gwb: use int64_t for 64 bit builds. */
      printf("%2d %08X: %02X %02X %08X %08X\n", i, (int32_t)descr, descr->type,
             descr->flags, descr->data.dbg.w1, descr->data.dbg.w2);
#else
      printf("%2d %08lX: %02X %02X %08X %08X\n", i, (int64_t)descr, descr->type,
             descr->flags, descr->data.dbg.w1, descr->data.dbg.w2);
#endif
      if (descr == e_stack_base)
        break;
    }
  }

  signal(signum, SIG_DFL);
  raise(signum);
}

/* ======================================================================
   suspend_updates()  -  Pause while suspend in progress                  */

void suspend_updates() {
  if (!(process.program.flags & PF_IN_TRIGGER)) {
    while (sysseg->flags & SSF_SUSPEND)
      Sleep(1000);
  }
}

/* ======================================================================
   ReleaseLicence()  -  Free a user table entry
   Caller must own the SHORT_CODE semaphore.                              */

void ReleaseLicence(USER_ENTRY* uptr) {
  int16_t i;
  int16_t uid;

  uid = uptr->uid;

  *(UMap(uptr->uid)) = 0;
  uptr->uid = 0;
  uptr->puid = 0;

  /* Also, clear parent user id from any phantoms started by this process */

  for (i = 1; i <= sysseg->max_users; i++) {
    uptr = UPtr(i);
    if (uptr->puid == uid)
      uptr->puid = 0;
  }
}

/* END-CODE */
