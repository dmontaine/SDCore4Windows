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
   sh()  -  Execute shell command                                         */

Private void sh(bool capture) {
  DESCRIPTOR *descr;
  STRING_CHUNK *str;
  int bytes;

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

  char dflt_sh[] = "/bin/bash -i";
  char dflt_sh1[] = "/bin/bash -c";

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
