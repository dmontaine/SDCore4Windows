/* OP_SH.C
 * Shell command execution
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
 * 19 Aug 26 Windows port - OS.EXECUTE is gated.  It was open to every user
 *           from a program while SH was refused at the prompt.
 *           PROJECT_STATUS.md section 4 / section 7 step 7.
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "syscom.h"
#include "tio.h"
#include "config.h"
#include <signal.h>

#include <sys/wait.h>

/* Modified by Composer AI - 2026/06/10.
   k_error() never returns, but the analyzer cannot see that across
   translation units. */
void k_error(char msg[], ...) __attribute__((noreturn));
/* -------------------- */

void set_term(bool trap_break);
void set_old_tty_modes(void);
void set_new_tty_modes(void);
void op_capture(void);

Private void sh(bool capture);
Private bool os_permitted(void);
Private void sh_execute(char *command);
Private int clparse(char *p, char *argv[], int maxargs);

int ChildPipe = -1;
bool in_sh = FALSE; /* 0562 Doing SH command? */

#define MAX_SH_COMMAND_LENGTH 32000
Private char *cmd_str = NULL;

/* ======================================================================
   op_sh()  -  Launch a DOS command                                       */

void op_sh() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Command to execute         |                             |
     |=============================|=============================|
 */

  sh(FALSE);
}

/* ======================================================================
   op_shcap  -  Launch SH command, capturing output                       */

void op_shcap() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  ADDR to capture variable   |                             |
     |-----------------------------|-----------------------------|
     |  Command to execute         |                             |
     |=============================|=============================|
 */

  DESCRIPTOR temp;

  /* Swap top two stack items so that the command is on top */

  temp = *(e_stack - 1);
  *(e_stack - 1) = *(e_stack - 2);
  *(e_stack - 2) = temp;

  sh(TRUE);
}

/* ======================================================================
   os_permitted()  -  May this session reach the operating system?         */

/* 19 Aug 26 Windows port - PROJECT_STATUS.md section 4, and the C half of
 * section 7 step 7.
 *
 * THE HOLE THIS CLOSES, measured with its control on the 15:30:36 install:
 * from ONE unelevated session standing in DON, "SH echo ..." at the prompt
 * answered "don is not permitted to use the operating system shell", while a
 * program compiled in that same user's own BP running
 * "os.execute 'cmd /c echo ...' capturing cap" captured the output and ran.
 * Same user, same session - the visible route refused and the real one open.
 *
 * CPROC's os.command: gate is not on this path and cannot be.  OS.EXECUTE is
 * its own BASIC statement - BCOMP:9643, OP.SH / OP.SHCAP, both landing in
 * sh() - so neither kernel(K$ADMINISTRATOR,-1) nor !valid_shell_cmd is
 * anywhere near it.  This is the one place both forms pass through.
 *
 * THREE WAYS IN, AND THE FIRST IS WHAT KEEPS "SH" WORKING.
 *
 *  1. HDR_INTERNAL.  The SH verb reaches the OS by CPROC itself doing
 *     os.execute, so by the time control arrives here the verb and the
 *     statement are the same code and C cannot tell them apart.  CPROC is
 *     $internal and has ALREADY applied the finer rule - OS.USERS field 1 -
 *     so trusting the marker here leaves SH exactly as it was.  IT CANNOT BE
 *     FORGED: BCOMP:2864 honours $INTERNAL only for a session that is itself
 *     internal AND elevated, so an ordinary user cannot compile a program
 *     that carries it.
 *  2. An elevated session, exactly as SH allows one.  An administrator at the
 *     console has to keep this whatever the file says, or an empty OS.USERS
 *     locks the machine's own administrator out of it.
 *  3. OS.USERS field 2, "OS.EX".  Field 1 is SH and field 2 is this one;
 *     until now field 2 was stored, dictionaried and read by nobody.
 *
 * MISSING FILE OR MISSING RECORD MEANS NO.  That is the behaviour before this
 * existed and it is the safe direction.  It is the OPPOSITE of the tier lists
 * in NEWVOC, where a missing record means the FULL VOC - do not carry that
 * convention across.
 *
 * THE ACL ON OS.USERS IS THE WHOLE OF THE PROTECTION.  gplbld/secure-osusers.ps1
 * makes it read-only to sdusers; without that a user grants themselves this in
 * one line and the gate below is decoration.
 */

Private bool os_permitted(void) {
  char path[MAX_PATHNAME_LEN + 1];
  char buff[128];
  int fu;
  int n;
  char* p;
  char* q;

  if (process.program.flags & HDR_INTERNAL)
    return TRUE;

  if (my_uptr->flags & USR_ADMIN)
    return TRUE;

  if (process.username[0] == '\0')
    return FALSE;

  if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s%cos.users%c%s", sysseg->sysdir,
               DS, DS, process.username) >= (MAX_PATHNAME_LEN + 1))
    return FALSE;

  fu = open(path, O_RDONLY);
  if (fu < 0)
    return FALSE;
  n = read(fu, buff, sizeof(buff) - 1);
  close(fu);
  if (n <= 0)
    return FALSE;
  buff[n] = '\0';

  /* OS.USERS is a DIRECTORY file, so a record is a file and a field mark is a
     newline.  Field 1 is SH; field 2 is the one this reads.                */

  p = strchr(buff, '\n');
  if (p == NULL)
    return FALSE;
  p++;

  for (q = p; (*q != '\0') && (*q != '\n') && (*q != '\r'); q++) {
  }
  *q = '\0';

  while (*p == ' ')
    p++;
  while ((q > p) && (q[-1] == ' '))
    *(--q) = '\0';

  return (stricmp(p, "yes") == 0);
}

/* ======================================================================
   sh()  -  Execute shell command                                         */

Private void sh(bool capture) {
  DESCRIPTOR *descr;
  STRING_CHUNK *str;
  int bytes;

  /* Before the stack is touched, so a refusal leaves it as it was found. */
  if (!os_permitted())
    k_error(sysmsg(10054), process.username);

  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  bytes = (str != NULL) ? str->string_len : 0;
  if (bytes > MAX_SH_COMMAND_LENGTH) {
    process.status = ER_LENGTH;
    k_dismiss();
  } else {
    if (cmd_str != NULL)
      k_free(cmd_str); /* From an earlier k_error() */

    cmd_str = k_alloc(111, bytes + MAX_PATHNAME_LEN + 10); /* Allow for strcat on Windows */
    k_get_c_string(descr, cmd_str, bytes);
    k_dismiss();

    if (capture) {
      /* Set up capture mechanism */

      if (capturing) /* This is a nested EXECUTE...CAPTURING structure */
      {
        process.program.flags |= PF_CAPTURING;

        if (capture_head != NULL) /* Stack data already captured */
        {
          process.program.saved_capture_head = capture_head;
          process.program.saved_capture_tail = capture_tail;
        }
      }

      capture_head = NULL;
      capturing = TRUE;
      stack_display_pu();
    }

    sh_execute(cmd_str);
    k_free(cmd_str);
    cmd_str = NULL;

    if (capture) {
      op_capture(); /* Use op_capture() to save the command output */
    }
  }
}

/* ======================================================================
   sh_execute()  -  Execute SH command                                    */

Private void sh_execute(char *command) {
#define PIPE_BUFFER_SIZE 2048
  char buffer[PIPE_BUFFER_SIZE];
  bool saved_trap_break_char;
  bool saved_pagination;
  bool use_output_pipe;
  /* Modified by Composer AI - 2026/06/10.
     Initialize pipe fd pairs so paths that skip pipe() do not read
     indeterminate values; use -1 for unused slots. */
  /* int ChildToSDPipe[2]; */
  int ChildToSDPipe[2] = {-1, -1};
  bool use_input_pipe;
  /* int SDToChildPipe[2]; */
  int SDToChildPipe[2] = {-1, -1};
  /* -------------------- */
  char *argv[10];
  int cpid;
  int16_t i;
  int bytes;
  int child_status;

  /* 14 Aug 26 Windows port - the shell is PowerShell, not bash.

     These were "/bin/bash -i" and "/bin/bash -c".  That is a Linux-ism twice
     over: bash is not on a Windows machine, and an installed SD does not ship
     one - gplbld/stage.py stages the SD executables and the MSYS2 DLLs, and no
     shell at all.  So /bin/bash resolved inside C:\Program Files\SD\ and every
     OS.EXECUTE failed on an installed system while working perfectly in a
     development tree, where MSYS2's own bash happens to exist.

     The path is derived from SystemRoot rather than written as C:\Windows,
     because the system drive is not guaranteed.  It must contain no spaces:
     clparse() splits on them and does not honour quotes, which is why
     PowerShell is named by its real location rather than through a wrapper.

     Note these are copies, not string literals - clparse() calls strtok() on
     whatever it is given and writes into it.                                */

  char dflt_sh[MAX_PATHNAME_LEN + 64];
  char dflt_sh1[MAX_PATHNAME_LEN + 64];
  char psh[MAX_PATHNAME_LEN + 1];
  const char *sysroot;
  char *pp;

  sysroot = getenv("SystemRoot");
  if ((sysroot == NULL) || (*sysroot == '\0'))
    sysroot = "C:/Windows";

  snprintf(psh, sizeof(psh),
           "%s/System32/WindowsPowerShell/v1.0/powershell.exe", sysroot);

  /* SystemRoot arrives as C:\WINDOWS.  Fold the separators so the whole path
     is one spelling; sdrealpath() accepts either, but consistency here keeps
     the value that gets logged and reported readable.                       */

  for (pp = psh; *pp != '\0'; pp++) {
    if (*pp == '\\')
      *pp = '/';
  }

  snprintf(dflt_sh, sizeof(dflt_sh), "%s -NoProfile -NoLogo", psh);
  snprintf(dflt_sh1, sizeof(dflt_sh1), "%s -NoProfile -NonInteractive -Command",
           psh);

  saved_trap_break_char = trap_break_char;
  saved_pagination = (tio.dsp.flags & PU_PAGINATE) != 0;

  process.status = 0;
  process.os_error = 0;

  flush_dh_cache();

  /* Turn off pagination.  Much as it would be nice, we get thoroughly
    confused about whether input is for the executed command or a response
    to the end of page prompt.                                             */

  tio.dsp.flags &= ~PU_PAGINATE;

  set_old_tty_modes();
  in_sh = TRUE; /* 0562 */

  /* If the user entered SD from the operating system command prompt, we
    can simply let the child process take over our stdout and stderr.
    If they have come in from a network or we need to capture the output
    for some reason, we must use a pipe. Although it sounds simpler always
    to use the pipe, this has some impact on the executed commands if they
    check the device type of the standard file handles.                     */

  use_output_pipe = capturing                          /* Trap output for EXECUTE CAPTURING */
                    || (connection_type != CN_CONSOLE) /* Not a direct connection */
                    || (tio.como_file >= 0);           /* Real como file */

  /* Similarly, on the input side, we need to use a pipe to feed the shell
    process if the real source of input is a socket. This allows us to
    perform input editing and avoids the shell moaning that stdin is not
    suitable.                                                             */

  use_input_pipe = (connection_type == CN_SOCKET);

  if (use_output_pipe && pipe(ChildToSDPipe)) {
    k_error("Cannot create child output pipe");
  }

  if (use_input_pipe && pipe(SDToChildPipe)) {
    /* Modified by Composer AI - 2026/06/10.
       Close the output pipe if input pipe creation fails. */
    if (use_output_pipe) {
      close(ChildToSDPipe[0]);
      close(ChildToSDPipe[1]);
    }
    /* -------------------- */
    k_error("Cannot create child input pipe");
  }

  /* 0420 Disable sigchld handler
    We need to do this to prevent the handler catching termination of
    the child process created below to execute this command.           */

  signal(SIGCHLD, SIG_DFL);

  cpid = fork();
  if (cpid == 0) /* Child process */
  {
    if (use_output_pipe) {
      dup2(ChildToSDPipe[1], 1);
      dup2(ChildToSDPipe[1], 2);
    }

    if (use_input_pipe) {
      dup2(SDToChildPipe[0], 0);
    }

    for (i = 3; i < 1024; i++)
      close(i);

    /* 15 Aug 26 Windows port - MARK THE SHELL AS SD's CHILD, so that a second
       sd cannot be started from inside it.  Owner's rule, 15 Aug 2026:
       somebody who shells out of SD with SH must not be able to run sd again.
       sd.c refuses when it sees this.

       IT IS A GUARD, NOT A BOUNDARY, and the difference matters.  The variable
       lives in the user's own shell, so the user can clear it.

       AND THE SHELL IS REALLY THERE - corrected 15 Aug 2026, having first
       claimed otherwise.  ForceCommand puts an ssh session into SD rather than
       a prompt, but SH hands one back, so "an SD account has no shell" is
       false and nothing here should rest on it.  What this guard buys is the
       accident and the casual case, which is what SH actually produces.  The
       owner's answer to the rest is at the application level: SD can lock a
       user into a menu system, and then SH is not reachable to begin with.
       Restricting SH itself would be the other way, and is not decided.

       Set in the CHILD, after the fork, so SD's own environment is untouched
       and the phantom and client paths - which fork elsewhere - never see it. */
    {
      static char sd_session_env[] = "SD_SESSION=1";
      putenv(sd_session_env);
    }

    if (command[0] == '\0') /* Interactive shell */
    {
      clparse((pcfg.sh[0] != '\0') ? pcfg.sh : dflt_sh, argv, 10);
    } else /* Single command */
    {
      i = clparse((pcfg.sh1[0] != '\0') ? pcfg.sh1 : dflt_sh1, argv, 9);
      argv[i] = command;
      argv[i + 1] = NULL;
    }

    execv(argv[0], argv);
  } else if (cpid == -1) /* Error */
  {
    /* Modified by Composer AI - 2026/06/10.
       fork() failed; close any pipes that were opened. */
    if (use_output_pipe) {
      close(ChildToSDPipe[0]);
      close(ChildToSDPipe[1]);
    }
    if (use_input_pipe) {
      close(SDToChildPipe[0]);
      close(SDToChildPipe[1]);
    }
    /* -------------------- */
    k_error("Failed to start");
  } else /* Parent process */
  {
    if (use_input_pipe) {
      ChildPipe = SDToChildPipe[1];
      close(SDToChildPipe[0]);
    }

    if (use_output_pipe) {
      close(ChildToSDPipe[1]);

      while ((bytes = read(ChildToSDPipe[0], buffer, PIPE_BUFFER_SIZE)) > 0) {
        tio_display_string(buffer, bytes, TRUE, FALSE);
      }

      close(ChildToSDPipe[0]);
    }

    waitpid(cpid, &child_status, 0);
    process.os_error = WEXITSTATUS(child_status); /* 0420 */

    /* 0420 Re-enable sigchld handler and clear any backlog */

    signal(SIGCHLD, sigchld_handler);
    while (waitpid(-1, &child_status, WNOHANG) > 0) {
    }

    if (use_input_pipe) {
      ChildPipe = -1;
      close(SDToChildPipe[1]);
    }
  }

  set_new_tty_modes();
  in_sh = FALSE; /* 0562 */

  if (saved_pagination)
    tio.dsp.flags |= PU_PAGINATE;
  else
    tio.dsp.flags &= ~PU_PAGINATE;
  set_term(saved_trap_break_char);
}

/* ======================================================================
   clparse()  -  Parse a command line into an argv array                  */

Private int clparse(char *p, char *argv[], int maxargs) {
  int argc; /* resolves CWE-197 */

  /* Although this works for our purposes, it isn't perfect. It really
    should handle quotes and \ escapes.                                */

  for (argc = 0; argc < maxargs; argc++) {
    if ((argv[argc] = strtok(p, " ")) == NULL)
      break;
    p = NULL;
  }

  return argc;
}

/* END-CODE */
