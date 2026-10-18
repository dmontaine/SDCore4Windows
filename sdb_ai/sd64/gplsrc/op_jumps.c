/* OP_JUMPS.C
 * Jump opcodes
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
 * 18 Oct 26 Windows port - from Linux a0a1ad6 (17 Oct 26): CALL "file name", the Pick style call (QM4 Fixes 208; the owner's ruling: the file is a VOC name only,
 *           no operating system path): pick_style_runfile(); op_call() and op_callv() share call_name_to_load().
 * 18 Oct 26 Windows port - from Linux bafe928 (17 Oct 26): TRY / CATCH: exception GROUPS (a handler named a.b catches a.b.c, openQM manual "Exception Groups"), a
 *           transaction begun inside the TRY clause is rolled back when an exception is thrown out of it, and the kernel
 *           can throw the SYS.* exceptions (exc_sys_throw(), called by k_error()) - QM4 Fixes 354.
 * 18 Oct 26 Windows port - from Linux fa146d9 (16 Oct 26): op_chkcat(): a name beginning with a hyphen is global, like the other prefixes (QM4 Fixes 217).
 * 29 Sep 26 RELEASE_1.1 114 - op_run() takes a runfile path up to
 *           MAX_PATHNAME_LEN, not MAX_PROGRAM_NAME_LEN (from Solo's SOLO 12)
 * 14 Sep 26 Windows port - call names are canonical LOWER case: the five
 *           UpperCaseString() calls became LowerCaseString(), and
 *           valid_call_name() accepts lower case only.  RELEASE_1.1_FIXES.md 5,
 *           stage 3a.
 * 31 Dec 23 SD launch - prior history suppressed
 * 18 Oct 26 Windows port - from Linux 1298f82 (12 Oct 26): valid_call_name(): the limit is the lower of 128 and MAXIDLEN
 *           (openQM item 241), 63 at the default.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Opcodes:
 * op_call()      CALL      Call catalogued subroutine
 * op_callv()     CALLV     Call catalogued subroutine, variable arg list
 * op_chkcat()    CHKCAT    Check catalogue for named subroutine
 * op_enter()     ENTER     Pick style ENTER
 * op_gosub()     GOSUB     Local subroutine call
 * op_jmp()       JMP       Unconditional jump
 * op_jng()       JNG       Jump if negative
 * op_jnz()       JNZ       Jump if non-zero
 * op_jpg()       JPG       Jump to start of next page
 * op_jpo()       JPO       Jump if strictly positive
 * op_jpz()       JPZ       Jump if positive or zero
 * op_jze()       JZE       Jump if zero
 * op_ongosub()   ONGOSUB   Computed local subroutine call
 * op_ongosubp()  ONGOSUBP  Computed local subroutine call (Pick style)
 * op_ongoto()    ONGOTO    Computed jump
 * op_ongotop()   ONGOTOP   Computed jump (Pick style)
 * op_return()    RETURN    Return from GOSUB or CALL
 * op_returnto()  RETURNTO  Jump to label if from GOSUB, return if from CALL
 * op_run()       RUN
 *
 * Local functions:
 * computed_jump()          Common path for ONGOTO and ONGOSUB
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "syscom.h"
#include "tio.h"
#include "locks.h"
#include "options.h"

#include <time.h>
#include <strings.h>

/* Modified by Composer AI - 2026/06/10.
   k_error() longjmps back to the kernel command loop and never returns,
   but the analyzer cannot see this across translation units. Redeclare
   it with the noreturn attribute so that paths following a k_error()
   call (e.g. the switch default case in op_loadobj) are not reported
   as using uninitialized values. */
void k_error(char msg[], ...) __attribute__((noreturn));
/* -------------------- */

extern time_t clock_time;

Private void computed_jump(bool save_link, bool pick_style);

/* ======================================================================
   refresh_link()  -  FORCE.RELOAD: replace a superseded object in a link

   depth is the position of the call name / link variable below the top of
   the e-stack. The load may use the e-stack, so the descriptor is found
   again before it is changed.                                            */

Private void refresh_link(int depth) {
  DESCRIPTOR* d;
  void* obj;

  d = e_stack - depth;
  while (d->type == ADDR)
    d = d->data.d_addr;
  if (d->type == SUBR && object_is_stale(d->data.subr.object)) {
    obj = refresh_subr_object(d->data.subr.object);
    d = e_stack - depth;
    while (d->type == ADDR)
      d = d->data.d_addr;
    d->data.subr.object = obj;
  }
}

/* ======================================================================
   pick_style_runfile()  -  The Pick style CALL "file name" (17 Oct 26, QM4
   Fixes 208; the owner's ruling: VOC file names only)

   call_name is the lower-cased string of the CALL, "file name": the name of a
   file as the VOC has it, a space, and the name of a compiled program in the
   file's object directory, which is the file with .out added (.OUT if the
   program was compiled from a file whose VOC id has capitals, as BASIC makes
   it). The path of that directory comes from get_voc_file_reference(), the
   lookup OPEN makes, so a file this account could not OPEN cannot be named
   here, a Q-pointer follows the gates of S.63, and there is no operating
   system path form. The result is the object's pathname, the kind of name
   RUN gives k_call(); load_object() opens it. Returns FALSE when the string
   is not of that form or names no such file.

   The program name may not begin with one of the global catalogue prefixes
   ($ ! * _): those names belong to the catalogue and its rules, not to a file.
   STATUS() is left as it was.                                              */

Private bool pick_style_runfile(char* call_name, char* runfile) {
  char file[MAX_PROGRAM_NAME_LEN + 1];
  char prog[MAX_PROGRAM_NAME_LEN + 1];
  char mapped[2 * MAX_PROGRAM_NAME_LEN + 2];
  char voc_name[MAX_PROGRAM_NAME_LEN + 8];
  char path[MAX_PATHNAME_LEN + 1];
  char* sp;
  char* p;
  int32_t saved_status;
  size_t path_len;
  int pass;
  bool found = FALSE;

  sp = strchr(call_name, ' ');
  if (sp == NULL)
    return FALSE;
  *sp = '\0';
  strcpy(file, call_name);
  strcpy(prog, sp + 1);
  *sp = ' ';

  /* Exactly two names: no further spaces, no path separators, neither empty */

  if ((file[0] == '\0') || (prog[0] == '\0') || (strchr(prog, ' ') != NULL))
    return FALSE;
  if ((strchr(file, DS) != NULL) || (strchr(prog, DS) != NULL))
    return FALSE;
  if (strchr("*$!_", prog[0]) != NULL)
    return FALSE;
  for (p = file; *p != '\0'; p++) {
    if ((strchr("abcdefghijklmnopqrstuvwxyz0123456789.%$-_", *p) == NULL))
      return FALSE;
  }
  if (!valid_call_name(prog))
    return FALSE;

  saved_status = process.status;

  /* The object directory is the VOC entry file.out, or FILE.OUT when the file was named with capitals */

  for (pass = 0; (pass < 2) && !found; pass++) {
    strcpy(voc_name, file);
    if (pass == 1)
      UpperCaseString(voc_name);
    strcat(voc_name, (pass == 0) ? ".out" : ".OUT");
    path[0] = '\0';
    found = get_voc_file_reference(voc_name, FALSE, path, NULL) && (path[0] != '\0');
  }

  process.status = saved_status;
  if (!found)
    return FALSE;

  (void)map_t1_id(prog, (int16_t)strlen(prog), mapped);
  path_len = strlen(path);
  if (path_len + 1 + strlen(mapped) > MAX_PATHNAME_LEN)
    return FALSE;
  memcpy(runfile, path, path_len);
  runfile[path_len] = DS;
  strcpy(runfile + path_len + 1, mapped);
  return TRUE;
}

/* ======================================================================
   call_name_to_load()  -  The name op_call() and op_callv() hand to k_call()
   for a CALL whose name is the string in descr.  call_name receives the
   name as written, in lower case, for the profiler; runfile is room for a
   pathname. A name with a space in it is the Pick style form; any other must
   be a call name, and one beginning with $ only internal code may call.  An
   illegal name aborts, as it always has.                                  */

Private char* call_name_to_load(DESCRIPTOR* descr, char* call_name, char* runfile) {
  if (k_get_c_string(descr, call_name, MAX_PROGRAM_NAME_LEN) <= 0) {
    k_illegal_call_name();
  }

  LowerCaseString(call_name); /* RELEASE_1.1 5 stage 3a: canonical case */

  if (strchr(call_name, ' ') != NULL) {
    if (!pick_style_runfile(call_name, runfile))
      k_illegal_call_name();
    return runfile;
  }

  if (!valid_call_name(call_name))
    k_illegal_call_name();

  if (call_name[0] == '$') /* Only callable by internal mode code */
  {
    if (!(process.program.flags & HDR_INTERNAL))
      k_illegal_call_name();
  }

  return call_name;
}

/* ======================================================================
   op_call()  -  Call catalogued routine                                  */

void op_call() {
  DESCRIPTOR* descr;
  int16_t num_args;
  char call_name[MAX_PROGRAM_NAME_LEN + 1];
  char runfile[MAX_PATHNAME_LEN + 1];
  char* load_name;

  num_args = *(pc++);

  if (Option(OptForceReload))
    refresh_link(num_args + 1);

  descr = e_stack - (num_args + 1);
  while (descr->type == ADDR)
    descr = descr->data.d_addr;

  switch (descr->type) {
    case STRING:
      load_name = call_name_to_load(descr, call_name, runfile);
      ProfEvent(PROF_CALL, call_name, (int)strlen(call_name)); /* the application event profiler (16 Oct 26) */
      k_call(load_name, num_args, NULL, 1);

      /* 0407 We need to find the name descriptor again as k_call() may
         have moved it while expanding the e_stack. The arguments have
         been moved into the subroutine's own variable space so the
         desciptor we need is at the top of the stack.                   */

      descr = e_stack - 1;
      while (descr->type == ADDR)
        descr = descr->data.d_addr;

      /* Convert descriptor to become a SUBR.  Convert type, copy string
         pointer, set object address.                                     */

      descr->type = SUBR; /* Preserve flags (e.g. DF_SYSTEM) */
      descr->data.subr.saddr = s_make_contiguous(descr->data.str.saddr, NULL);

      descr->data.subr.object = c_base;
      ((OBJECT_HEADER*)c_base)->ext_hdr.prog.refs++;
      break;

    case SUBR:
      if ((prof_mask & PROF_CALL) && (descr->data.subr.saddr != NULL)) /* the application event profiler (16 Oct 26): a linked call */
        prof_event(PROF_CALL, descr->data.subr.saddr->data, descr->data.subr.saddr->bytes);
      k_call("", num_args, (u_char*)(descr->data.subr.object), 1);
      ((OBJECT_HEADER*)c_base)->ext_hdr.prog.refs++;
      break;

    default:
      k_error(sysmsg(1129));
  }

  k_dismiss(); /* Dismiss call name */

  return;
}

/* ======================================================================
   op_callv()  -  Call catalogued routine with variable argument list     */

void op_callv() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Addr to args matrix           |                             |
     |--------------------------------|-----------------------------|
     |  Argument count                |                             |
     |--------------------------------|-----------------------------|
     |  Subroutine name               |                             |
     |================================|=============================|
 */

  DESCRIPTOR* subr_descr;
  DESCRIPTOR* descr;
  int16_t num_args;
  char call_name[MAX_PROGRAM_NAME_LEN + 1];
  char runfile[MAX_PATHNAME_LEN + 1];
  char* load_name;
  ARRAY_HEADER* ahdr;
  int16_t i;

  if (Option(OptForceReload))
    refresh_link(3);

  /* Get array header address for argument matrix */

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  ahdr = descr->data.ahdr_addr;

  /* Get argument count */

  descr = e_stack - 2;
  GetInt(descr);
  num_args = (int16_t)(descr->data.value);
  if ((num_args < 0) || (num_args > 255))
    k_error(sysmsg(1131));

  if (num_args > ahdr->rows * ((ahdr->cols) ? (ahdr->cols) : 1)) {
    k_error(sysmsg(1132));
  }

  /* Get subroutine name descriptor before we dismiss it. This is always
    an ADDR so dismissing it does no harm.                              */

  subr_descr = e_stack - 3;
  while (subr_descr->type == ADDR)
    subr_descr = subr_descr->data.d_addr;

  /* Dismiss stack items */

  k_pop(2);    /* Dismiss arg matrix pointer and arg count */
  k_dismiss(); /* Dismiss call name */

  /* Put arguments onto stack */

  for (i = 1; i <= num_args; i++) {
    descr = Element(ahdr, i);
    InitDescr(e_stack, ADDR);
    (e_stack++)->data.d_addr = descr;
    while (descr->type == ADDR)
      descr = descr->data.d_addr;
    descr->flags |= DF_ARGSET; /* Monitor change */
  }

  switch (subr_descr->type) {
    case STRING:
      load_name = call_name_to_load(subr_descr, call_name, runfile);
      ProfEvent(PROF_CALL, call_name, (int)strlen(call_name)); /* the application event profiler (16 Oct 26) */
      k_call(load_name, num_args, NULL, 0);

      /* Convert descriptor to become a SUBR.  Convert type, copy string
         pointer, set object address.                                     */

      subr_descr->type = SUBR; /* Preserve flags (e.g. DF_SYSTEM) */
      subr_descr->data.subr.saddr = subr_descr->data.str.saddr;

      subr_descr->data.subr.object = c_base;
      ((OBJECT_HEADER*)c_base)->ext_hdr.prog.refs++;
      break;

    case SUBR:
      if ((prof_mask & PROF_CALL) && (subr_descr->data.subr.saddr != NULL)) /* the application event profiler (16 Oct 26): a linked call */
        prof_event(PROF_CALL, subr_descr->data.subr.saddr->data, subr_descr->data.subr.saddr->bytes);
      k_call("", num_args, (u_char*)(subr_descr->data.subr.object), 0);
      ((OBJECT_HEADER*)c_base)->ext_hdr.prog.refs++;
      break;

    default:
      k_error(sysmsg(1129));
  }

  return;
}

/* ======================================================================
   op_chkcat()  -  Check catalogue for named subroutine                   */

void op_chkcat() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Name to locate                | 0 = Not found               |
     |                                | 1 = Locally catalogued      |
     |                                | 2 = Privately catalogued    |
     |                                | 3 = Gloablly catalogued     |
     |================================|=============================|

 */

  DESCRIPTOR* descr;
  char call_name[MAX_PROGRAM_NAME_LEN + 1];
  char mapped_name[MAX_PROGRAM_NAME_LEN * 2 + 1];
  char pathname[MAX_PATHNAME_LEN + MAX_PROGRAM_NAME_LEN + 1];
  int mode = 0;
  DESCRIPTOR pathname_descr;

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;

  descr = e_stack - 1; /* Replace e-stack item, not final descr */
  if (k_get_c_string(descr, call_name, MAX_PROGRAM_NAME_LEN) > 0) {
    LowerCaseString(call_name); /* RELEASE_1.1 5 stage 3a: canonical case */
    (void)map_t1_id(call_name, strlen(call_name), mapped_name);

    if (strchr("*$_!-", call_name[0]) == NULL) { /* No prefix (16 Oct 26: the hyphen is one, QM4 Fixes 217) */
      /* Try local catalogue (mode 1) */

      /* Push arguments onto e-stack */

      k_put_c_string(call_name, e_stack++);
      InitDescr(e_stack, ADDR); /* File path name (output) */
      (e_stack++)->data.d_addr = &pathname_descr;
      pathname_descr.type = UNASSIGNED;

      k_recurse(pcode_voc_cat, 2); /* Execute recursive code */

      /* Extract result string */
      if (pathname_descr.data.str.saddr != NULL)
        mode = 1;
      k_release(&pathname_descr);

      if (mode == 0) {
        /* Try private catalogue */
        /* converted to snprintf() -gwb 22Feb20 */
        /* Fix for Issue #12 - 11Jan22 */
        if (snprintf(pathname, (MAX_PATHNAME_LEN + MAX_PROGRAM_NAME_LEN) + 1, "%s%c%s",
                     private_catalogue, DS,
                     mapped_name) >= (MAX_PATHNAME_LEN + 1)) {
          /* TODO: this should also be logged with more detail */
          k_error("Overflowed path/filename length in op_chkcat())!");
          /* TODO: this should trigger some kind of error condition */
        }
        if (access(pathname, 0) == 0)
          mode = 2;
      }
    }

    if (mode == 0) {
      /* Try global catalog */
      /* converted to snprintf() -gwb 22Feb20 */
      /* Fix for Issue #12 - 11Jan22*/
      if (snprintf(pathname, (MAX_PATHNAME_LEN + MAX_PROGRAM_NAME_LEN) + 1, "%s%cgcat%c%s",
                   sysseg->sysdir, DS, DS,
                   mapped_name) >= (MAX_PATHNAME_LEN + 1)) {
        /* TODO: this should also be logged with more detail */
        k_error("Overflowed path/filename length in op_chkcat()!");
        /* TODO: this should trigger some kind of error condition. */
      }
      if (access(pathname, 0) == 0)
        mode = 3;
    }
  }

  k_dismiss(); /* Dismiss call name */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = mode;
}

/* ======================================================================
   op_enter()  -  Pick style ENTER                                        */

void op_enter() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Program name or SUBR link     |                             |
     |================================|=============================|
 */

  DESCRIPTOR* descr;
  char call_name[MAX_PROGRAM_NAME_LEN + 1];

  descr = e_stack - 1;
  k_get_value(descr);

  switch (descr->type) {
    case SUBR:
      /* Convert SUBR reference back to a STRING */
      InitDescr(descr, STRING);
      --(((OBJECT_HEADER*)(descr->data.subr.object))->ext_hdr.prog.refs);
      descr->data.str.saddr = descr->data.subr.saddr;

      /* **** FALL THROUGH **** */
      /* Modified by Composer AI - 2026/06/10.
         Fall-through is intentional (see comment above); make it
         explicit for the compiler. */
      __attribute__((fallthrough));
      /* -------------------- */

    case STRING:
      if (k_get_c_string(descr, call_name, MAX_PROGRAM_NAME_LEN) <= 0) {
        k_illegal_call_name();
      }
      break;

    default:
      k_error(sysmsg(1129));
  }

  LowerCaseString(call_name); /* RELEASE_1.1 5 stage 3a: canonical case */

  if (!valid_call_name(call_name))
    k_illegal_call_name();
  if (call_name[0] == '$') /* Only callable by internal mode code */
  {
    if (!(process.program.flags & HDR_INTERNAL))
      k_illegal_call_name();
  }

  k_dismiss(); /* Dismiss call name */

  if (my_uptr->lockwait_index)
    clear_lockwait();

  /* Cast off all programs down to but not including one with
    the HDR_IS_CPROC flag set.                               */

  while (!(process.program.flags & HDR_IS_CPROC)) {
    k_return();
  }

  class_main_ok = TRUE; /* a class module is run through its MAIN subroutine (Fixes item 484) */
  k_call(call_name, 0, NULL, 0);

  return;
}

/* ======================================================================
   op_gosub()  -  Enter local subroutine                                  */

void op_gosub() {
  if (my_uptr->events)
    process_events();

  if (process.program.gosub_depth == MAX_GOSUB_DEPTH) {
    k_error(sysmsg(1133));
  }
  process.program.gosub_stack[process.program.gosub_depth++] = pc - c_base + 3;
  pc = c_base +
       (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
}

/* ======================================================================
   op_jfalse()  -  Jump if false                                          */

void op_jfalse() {
  DESCRIPTOR* descr;
  register bool jumping;

  if (my_uptr->events)
    process_events();

  descr = e_stack - 1;
  GetBool(descr);
  jumping = (descr->data.value == 0);
  k_pop(1);

  if (jumping) {
    pc = c_base +
         (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
  } else
    pc += 3;
}

/* ======================================================================
   op_jmp()  -  Unconditional jump                                        */

void op_jmp() {
  if (my_uptr->events)
    process_events();

  pc = c_base +
       (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
}

/* ======================================================================
   op_jng()  -  Jump if negative                                          */

void op_jng() {
  DESCRIPTOR* descr;
  register bool jumping;

  if (my_uptr->events)
    process_events();

  descr = e_stack - 1;

again:
  switch (descr->type) {
    case INTEGER:
      jumping = (descr->data.value < 0);
      break;

    case FLOATNUM:
      jumping = (descr->data.float_value < 0.0);
      break;

    default:
      GetNum(descr);
      goto again;
  }

  k_pop(1);

  if (jumping) {
    pc = c_base +
         (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
  } else
    pc += 3;
}

/* ======================================================================
   op_jnz()  -  Jump if non-zero                                          */

void op_jnz() {
  DESCRIPTOR* descr;
  register bool jumping;

  if (my_uptr->events)
    process_events();

  descr = e_stack - 1;

again:
  switch (descr->type) {
    case INTEGER:
      jumping = (descr->data.value != 0);
      break;

    case FLOATNUM:
      jumping = (descr->data.float_value != 0.0);
      break;

    default:
      GetNum(descr);
      goto again;
  }

  k_pop(1);

  if (jumping) {
    pc = c_base +
         (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
  } else
    pc += 3;
}

/* ======================================================================
   op_jpo()  -  Jump if strictly positive                                 */

void op_jpo() {
  DESCRIPTOR* descr;
  register bool jumping;

  if (my_uptr->events)
    process_events();

  descr = e_stack - 1;

again:
  switch (descr->type) {
    case INTEGER:
      jumping = (descr->data.value > 0);
      break;

    case FLOATNUM:
      jumping = (descr->data.float_value > 0.0);
      break;

    default:
      GetNum(descr);
      goto again;
  }

  k_pop(1);

  if (jumping) {
    pc = c_base +
         (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
  } else
    pc += 3;
}

/* ======================================================================
   op_jpz()  -  Jump if positive or zero                                  */

void op_jpz() {
  DESCRIPTOR* descr;
  register bool jumping;

  if (my_uptr->events)
    process_events();

  descr = e_stack - 1;

again:
  switch (descr->type) {
    case INTEGER:
      jumping = (descr->data.value >= 0);
      break;

    case FLOATNUM:
      jumping = (descr->data.float_value >= 0.0);
      break;

    default:
      GetNum(descr);
      goto again;
  }

  k_pop(1);

  if (jumping) {
    pc = c_base +
         (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
  } else
    pc += 3;
}

/* ======================================================================
   op_jtrue()  -  Jump if true                                            */

void op_jtrue() {
  DESCRIPTOR* descr;
  register bool jumping;

  if (my_uptr->events)
    process_events();

  descr = e_stack - 1;
  GetBool(descr);
  jumping = (descr->data.value != 0);
  k_pop(1);

  if (jumping) {
    pc = c_base +
         (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
  } else
    pc += 3;
}

/* ======================================================================
   op_jze()  -  Jump if zero                                              */

void op_jze() {
  DESCRIPTOR* descr;
  register bool jumping;

  if (my_uptr->events)
    process_events();

  descr = e_stack - 1;

again:
  switch (descr->type) {
    case INTEGER:
      jumping = (descr->data.value == 0);
      break;

    case FLOATNUM:
      jumping = (descr->data.float_value == 0.0);
      break;

    default:
      GetNum(descr);
      goto again;
  }

  k_pop(1);

  if (jumping) {
    pc = c_base +
         (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
  } else
    pc += 3;
}

/* ======================================================================
   op_loadobj()  -  Load object code but do not execute                   */

void op_loadobj() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Addr to subr name             | Program flags               |
     |================================|=============================|
 */

  DESCRIPTOR* descr;
  char call_name[MAX_PROGRAM_NAME_LEN + 1];
  /* Modified by Composer AI - 2026/06/10.
     hdr was used uninitialized on the path where the switch default
     case is taken. Initialize to NULL at declaration. */
  /* struct OBJECT_HEADER* hdr; */
  struct OBJECT_HEADER* hdr = NULL;
  /* -------------------- */

  /* Find subroutine name - Always an ADDR */

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;

  switch (descr->type) {
    case STRING:
      if (k_get_c_string(descr, call_name, MAX_PROGRAM_NAME_LEN) <= 0) {
        k_illegal_call_name();
      }

      LowerCaseString(call_name); /* RELEASE_1.1 5 stage 3a: canonical case */

      if (!valid_call_name(call_name))
        k_illegal_call_name();

      if (call_name[0] == '$') /* Only callable by internal mode code */
      {
        if (!(process.program.flags & HDR_INTERNAL))
          k_illegal_call_name();
      }

      hdr = (OBJECT_HEADER*)load_object(call_name, FALSE);
      if (hdr == NULL)
        k_error(sysmsg(1134), call_name);
      hdr->ext_hdr.prog.refs++;

      /* Convert descriptor to become a SUBR.  Convert type, copy string
         pointer, set object address. We need to re-evaluate the descriptor
         address as the call to load_object() could move the e-stack.      */

      descr = e_stack - 1;
      while (descr->type == ADDR)
        descr = descr->data.d_addr;

      descr->type = SUBR; /* Preserve flags (e.g. DF_SYSTEM) */
      descr->data.subr.saddr = s_make_contiguous(descr->data.str.saddr, NULL);
      descr->data.subr.object = (u_char*)hdr;
      break;

    case SUBR:
      hdr = (OBJECT_HEADER*)(descr->data.subr.object);
      break;

    default:
      k_error(sysmsg(1129));
  }

  k_dismiss(); /* Dismiss call name */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = hdr->flags;
}

/* ======================================================================
   op_ongosub()  -  Computed gosub                                        */

void op_ongosub() {
  computed_jump(TRUE, FALSE);
}

/* ======================================================================
   op_ongosubp()  -  Computed gosub (Pick style)                          */

void op_ongosubp() {
  computed_jump(TRUE, TRUE);
}

/* ======================================================================
   op_ongoto()  -  Computed goto                                          */

void op_ongoto() {
  computed_jump(FALSE, FALSE);
}

/* ======================================================================
   op_ongotop()  -  Computed goto (Pick style)                            */

void op_ongotop() {
  computed_jump(FALSE, TRUE);
}

/* ======================================================================
   op_inputtrap()  -  INPUTTRAP  (14 Oct 26, openQM 408)

   Stack: the characters to trap (deepest), the mode (0 GOTO, 1 GOSUB; the stub the compiler planted does the jumping, so the
   kernel does not need it) and the number of labels.  The offset of the stub follows the opcode.  A null string of characters
   cancels the trap.  The trap belongs to this program (struct PROGRAM): a subroutine it calls starts without one.        */

void op_inputtrap() {
  DESCRIPTOR* descr;
  int32_t stub;
  int32_t count;
  char chars[sizeof(process.program.itrap_chars)];

  stub = *pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16);
  pc += 3;

  descr = e_stack - 1; /* Label count */
  GetInt(descr);
  count = descr->data.value;
  k_pop(1);

  descr = e_stack - 1; /* Mode (not needed here) */
  k_pop(1);

  descr = e_stack - 1; /* Characters */
  chars[0] = '\0';
  if (k_get_c_string(descr, chars, (int)sizeof(chars) - 1) < 0)
    chars[sizeof(chars) - 1] = '\0'; /* More than 16: the first 16 are used */
  k_pop(1);

  strcpy(process.program.itrap_chars, chars);
  process.program.itrap_n = (int16_t)count;
  process.program.itrap_stub = (chars[0] != '\0') ? stub : 0;
  process.program.itrap_hit = 0;
}

/* ======================================================================
   op_itrapchk()  -  after INPUT @ / INPUTFIELD: take INPUTTRAP's jump if _INPUTAT found a trapped character.  The byte after
   the opcode is 1 when the statement had a THEN / ELSE clause, whose status is on the stack and is dropped when the jump is taken. */

void op_itrapchk() {
  u_char has_status;

  has_status = *(pc++);

  if (process.program.itrap_hit != 0 && process.program.itrap_stub != 0) {
    if (has_status)
      k_pop(1);
    pc = c_base + process.program.itrap_stub; /* itrap_hit is cleared by the stub, K_INPUT_TRAP_HIT */
  } else {
    process.program.itrap_hit = 0;
  }
}

/* ======================================================================
   op_return()  -  Return from CALL or GOSUB                              */

void op_return() {
  if (my_uptr->events)
    process_events();

  if (process.program.gosub_depth) /* Returning from local call (GOSUB) */
  {
    pc = c_base + process.program.gosub_stack[--process.program.gosub_depth];
  } else /* Returning from a CALL */
  {
    k_return();
  }
}

/* ======================================================================
   op_returnto()  -  Return from GOSUB to specific address                */

void op_returnto() {
  if (my_uptr->events)
    process_events();

  if (process.program.gosub_depth) /* Returning from local call (GOSUB) */
  {
    --process.program.gosub_depth;
    pc = c_base +
         (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
  } else /* Returning from a CALL */
  {
    k_return();
  }
}

/* ======================================================================
   op_run()  -  Enter runfile                                             */

void op_run() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Runfile name                  |                             |
     |================================|=============================|
 */

  DESCRIPTOR* descr;
  /* 29 Sep 26 - RELEASE_1.1 114 (SD Core Solo's SOLO 12): a runfile name is a
     PATH (CPROC builds it from fileinfo(fl$path)), so it gets a path's length.
     It was MAX_PROGRAM_NAME_LEN, 128, and RUN of anything under a long folder
     failed "Invalid runfile pathname".  object.c bounds its header copy.   */
  char runfile_name[MAX_PATHNAME_LEN + 1];

  descr = e_stack - 1;
  if (k_get_c_string(descr, runfile_name, MAX_PATHNAME_LEN) < 1) {
    k_error(sysmsg(1135));
  }
  k_dismiss();

  class_main_ok = TRUE; /* a class module is run through its MAIN subroutine (Fixes item 484) */
  k_call(runfile_name, 0, NULL, 0);

  return;
}

/* ======================================================================
   computed_jump()  -  Common path for op_ongoto() and op_ongosub()       */

Private void computed_jump(
    bool save_link,
    bool pick_style) /* Affects action of out of range index value */
{
  DESCRIPTOR* descr;
  int16_t num_labels;
  int32_t n;

  num_labels = *(pc++);
  if (num_labels == 0) {
    num_labels = (int16_t)(*pc | (((int32_t) * (pc + 1)) << 8));
    pc += 2;
  }

  descr = e_stack - 1;
  GetInt(descr);
  n = descr->data.value;
  k_dismiss();

  if (pick_style) {
    if ((n < 1) || (n > num_labels)) {
      pc += num_labels * 3;
      return;
    }
  } else {
    if (n < 1)
      n = 1;
    else if (n > num_labels)
      n = num_labels;
  }

  if (save_link) {
    if (process.program.gosub_depth == MAX_GOSUB_DEPTH)
      k_error(sysmsg(1133));

    process.program.gosub_stack[process.program.gosub_depth++] =
        pc - c_base + (num_labels * 3);
  }

  pc += (n - 1) * 3;
  pc = c_base +
       (*pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16));
}

/* ======================================================================
   valid_call_name()  -  Validate a subroutine name                       */

bool valid_call_name(char* p) {
  char c;
  int limit;
  /* 14 Sep 26 Windows port - LOWER CASE ONLY, RELEASE_1.1 5 stage 3a.  Every
     caller converts the name with LowerCaseString() immediately before this
     test, so an upper-case letter here means a caller that missed the flip -
     and NTFS would otherwise hide it by opening gcat case-blind.  Refusing it
     makes such a site fail loudly as an illegal call name.                   */
  char valid_chars[] = "abcdefghijklmnopqrstuvwxyz0123456789.%$-_";
  char leading_chars[] = "*$!_";

  /* !!CALLNAME!! */

  /* 12 Oct 26 dm  openQM item 241: the longest call name is the lower of
     MAX_PROGRAM_NAME_LEN (128) and MAXIDLEN, which is 63 unless the
     administrator raised it, so nothing changes until then.  The same limit
     is written in catalog, bcomp and apisrvr (BASIC).  sdclilib.c keeps the
     fixed MAX_CALL_NAME_LEN: a client cannot read the server's MAXIDLEN.     */
  limit = sysseg->maxidlen;
  if (limit > MAX_PROGRAM_NAME_LEN)
    limit = MAX_PROGRAM_NAME_LEN;
  if (limit < MAX_CALL_NAME_LEN)
    limit = MAX_CALL_NAME_LEN;

  if (strlen(p) > limit)
    return FALSE;

  c = *(p++);
  if (c == '\0')
    return FALSE;

  if ((strchr(valid_chars, c) == NULL) && (strchr(leading_chars, c) == NULL)) {
    return FALSE;
  }

  while ((c = *(p++)) != '\0') {
    if (strchr(valid_chars, c) == NULL)
      return FALSE;
  }

  return TRUE;
}

/* ======================================================================
   TRY / CATCH / THROW  (12 Oct 26 dm, openQM 355 CAUGHT() and the
   TRY/CATCH construct it belongs to)

   The compiler lays a TRY construct out as

            TRY      Lt          push a handler frame; Lt is the table
            ...                  the statements of the TRY clause
            ENDTRY   Lt          leave the clause normally: pop the frame
            JMP      Lx
       Lh1: ...                  the statements of the first CATCH clause
            JMP      Lx
       Lh2: ...                  and so on for each CATCH clause
            JMP      Lx
       Lt:  LDSTR    <table>     NOT executed: TRY reads it, and the frame
                                 holds the address of the next instruction
            LDSTR    <names of clause 1>
            EXC      MATCH       does the exception being handled have one?
            JTRUE    Lh1
            ...
            EXC      RETHROW     none of them (cannot happen): carry on up
       Lx:

   The table is one string of entries separated by value marks. Each entry
   is a digit, the sum of the qualifier flags EXC_DUMPING and
   EXC_SAVE_STACK, then the exception name in upper case. THROW looks for a
   frame whose table holds the name (or SYS$ANY), then for one holding
   SYS$UNHANDLED, unwinds the call stack to that frame's program level and
   continues at the dispatch code after its table.

   A throw does not reach past a command processor (EXECUTE), a trigger, a
   recursive call or a dictionary expression: such a level ends the search,
   so an exception thrown inside it and not handled inside it is unhandled.

   An exception name is a path of components separated by periods, and a
   handler covers the name it spells and every name beneath it: CATCH
   account takes ACCOUNT.INVALID and ACCOUNT.INVALID.CLOSED, CATCH sys.locks
   takes SYS.LOCKS.DEADLOCK. Whole components only: CATCH acc takes neither
   (exc_covers()). Within one TRY the first clause that covers the name is
   used, as the clauses are written.

   A transaction begun inside the TRY clause and still active when an
   exception is thrown out of it is rolled back (txn_rollback_to()); one that
   was already active when the TRY was entered is left alone.

   SYSTEM EXCEPTIONS.  Many run time errors that would abort the program are
   thrown as exceptions in the SYS group when something can catch them: an
   unassigned variable is SYS.PROGRAM.DATATYPE.UNASSIGNED, a deadlock is
   SYS.LOCKS.DEADLOCK. k_error() (k_error.c) holds the table that gives a
   message its name; it calls exc_sys_can_catch() and then exc_sys_throw(),
   which sets up the exception as THROW does, with the abort message as the
   data, and long jumps back to the dispatch loop (k_resume_exception() in
   kernel.c, to the resume point k_run_program() keeps). With no handler
   anywhere that can be reached the error aborts exactly as it always did.

   Leaving a TRY clause by GOTO, EXIT or CONTINUE is not allowed (the openQM
   rule too): the frame stays until its program level returns. A RETURN from
   a GOSUB that was called inside the clause is allowed, and so is a RETURN
   from a CALL; the frames of the returning level are dropped.            */

#define MAX_TRY_FRAMES 64
#define MAX_EXC_NAME_LEN 63
#define EXC_LDSTR 0x12 /* OP_LDSTR: the table is loaded by an ordinary LDSTR */

#define EXC_THROW 1
#define EXC_CAUGHT 2
#define EXC_MATCH 3
#define EXC_RETHROW 4

#define EXC_DUMPING 1    /* Qualifier DUMPING */
#define EXC_SAVE_STACK 2 /* Qualifier SAVING.STACK */

#define EXC_BARRIER                                                          \
  (HDR_IS_CPROC | HDR_RECURSIVE | HDR_ITYPE | HDR_IS_CLASS | PF_IS_TRIGGER)

typedef struct {
  int call_depth;     /* process.call_depth when the TRY was entered */
  int16_t recursion;  /* recursion_depth then */
  int16_t gosub_depth; /* GOSUB depth of that program level then */
  int32_t e_depth;    /* Evaluation stack depth then */
  int txn_depth;      /* Transaction nesting depth then */
  int32_t catch_pc;   /* Offset in that level's object of the dispatch code */
  int32_t table_pc;   /* ...of the handler table (what ENDTRY names) */
  const u_char* table;
  int table_len;
} TRY_FRAME;

Private TRY_FRAME try_frame[MAX_TRY_FRAMES];
Private int try_top = 0;

Private char exc_name[MAX_EXC_NAME_LEN + 1] = "";
Private char* exc_data = NULL;
Private char* exc_origin = NULL;
Private char* exc_stack = NULL;
Private bool exc_unhandled = FALSE; /* Caught by a SYS$UNHANDLED handler */

extern int txn_depth; /* txn.c: transactions begun and not yet ended */

Private bool exc_covers(const char* handler, int hlen, const char* thrown);
Private void exc_op_throw(void);
Private void exc_op_caught(void);
Private void exc_op_match(void);
Private void exc_raise(bool rethrow);
Private void exc_set_origin(void);
Private void exc_save_stack(void);
Private int try_find(const char* name, int modes, int* flags);
Private bool exc_table_find(const u_char* tab, int len, const char* name,
                            int modes, int* flags);

/* ======================================================================
   try_level_gone()  -  A program level has been given up (called by
   k_return() once process.call_depth has been reduced): drop its frames. */

void try_level_gone() {
  while ((try_top > 0) && (try_frame[try_top - 1].call_depth > process.call_depth))
    try_top--;
}

/* ======================================================================
   try_prune()  -  Drop frames of this level that a RETURN from a GOSUB
   made inside their clause has left behind.                              */

Private void try_prune() {
  while ((try_top > 0) &&
         (try_frame[try_top - 1].call_depth == process.call_depth) &&
         (try_frame[try_top - 1].gosub_depth > process.program.gosub_depth))
    try_top--;
}

/* ======================================================================
   try_floor()  -  The lowest program level a throw may unwind to          */

Private int try_floor() {
  struct PROGRAM* p;
  int d;

  p = &process.program;
  d = process.call_depth;
  while (p != NULL) {
    if (p->flags & EXC_BARRIER)
      return d;
    p = p->prev;
    d--;
  }
  return 1;
}

/* ======================================================================
   op_try()  -  Establish exception handlers                              */

void op_try() {
  int32_t t;
  u_char* tab;
  TRY_FRAME* f;

  t = *pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16);
  pc += 3;

  tab = c_base + t;
  if (*tab != EXC_LDSTR)
    k_error(sysmsg(12099));

  try_prune();
  if (try_top >= MAX_TRY_FRAMES)
    k_error(sysmsg(12098), MAX_TRY_FRAMES);

  f = &try_frame[try_top++];
  f->call_depth = process.call_depth;
  f->recursion = recursion_depth;
  f->gosub_depth = process.program.gosub_depth;
  f->e_depth = (int32_t)(e_stack - e_stack_base);
  f->txn_depth = txn_depth;
  f->table_pc = t;
  f->table_len = *(tab + 1);
  f->table = tab + 2;
  f->catch_pc = t + 2 + f->table_len;
}

/* ======================================================================
   op_endtry()  -  Leave a TRY clause normally                            */

void op_endtry() {
  int32_t t;
  int i;
  TRY_FRAME* f;

  t = *pc | (((int32_t) * (pc + 1)) << 8) | (((int32_t) * (pc + 2)) << 16);
  pc += 3;

  try_prune();
  for (i = try_top - 1; i >= 0; i--) {
    f = &try_frame[i];
    if ((f->call_depth < process.call_depth) || (f->recursion != recursion_depth))
      break;
    if (f->table_pc == t) {
      try_top = i; /* This frame and any left above it */
      break;
    }
  }
}

/* ======================================================================
   op_exc()  -  THROW, CAUGHT() and the dispatch code of a CATCH           */

void op_exc() {
  int op;

  op = *(pc++);
  switch (op) {
    case EXC_THROW:
      exc_op_throw();
      break;

    case EXC_CAUGHT:
      exc_op_caught();
      break;

    case EXC_MATCH:
      exc_op_match();
      break;

    case EXC_RETHROW:
      exc_raise(TRUE);
      break;

    default:
      k_error("Illegal EXC sub-opcode x%02X", op);
  }
}

/* ======================================================================
   exc_covers()  -  Does a handler (hlen characters, not null terminated)
   take the exception called thrown? It does if it spells the name or a
   leading run of whole components of it (a.b takes a.b and a.b.c, not
   a.bc). Case is not significant.                                        */

Private bool exc_covers(const char* handler, int hlen, const char* thrown) {
  if (strncasecmp(handler, thrown, hlen) != 0)
    return FALSE;
  return (thrown[hlen] == '\0') || (thrown[hlen] == '.');
}

/* ======================================================================
   exc_table_find()  -  Is there a handler for name in a handler table?
   Returns the flags of the entry that applies: the named one, else the
   SYS$ANY one when bit 1 of modes is set, else the SYS$UNHANDLED one when
   bit 2 is.                                                              */

Private bool exc_table_find(const u_char* tab, int len, const char* name,
                            int modes, int* flags) {
  const u_char* p;
  const u_char* q;
  const u_char* end;
  int n;
  int any = -1;
  int unhandled = -1;

  p = tab;
  end = tab + len;
  while (p < end) {
    q = p;
    while ((q < end) && (*q != (u_char)VALUE_MARK)) /* VALUE_MARK is a signed char */
      q++;
    n = (int)(q - p) - 1; /* Length of the name; p[0] is the flag digit */
    if (n > 0) {
      if (exc_covers((const char*)p + 1, n, name)) {
        *flags = p[0] - '0';
        return TRUE;
      }
      if ((n == 7) && (strncasecmp((const char*)p + 1, "SYS$ANY", 7) == 0))
        any = p[0] - '0';
      else if ((n == 13) &&
               (strncasecmp((const char*)p + 1, "SYS$UNHANDLED", 13) == 0))
        unhandled = p[0] - '0';
    }
    p = q + 1;
  }

  if ((modes & 1) && (any >= 0)) {
    *flags = any;
    return TRUE;
  }
  if ((modes & 2) && (unhandled >= 0)) {
    *flags = unhandled;
    return TRUE;
  }
  return FALSE;
}

/* ======================================================================
   try_find()  -  The innermost frame with a handler for name that a throw
   from here can reach. Returns its index, or -1.                         */

Private int try_find(const char* name, int modes, int* flags) {
  int floor;
  int i;
  TRY_FRAME* f;

  try_prune();
  floor = try_floor();
  for (i = try_top - 1; i >= 0; i--) {
    f = &try_frame[i];
    if ((f->recursion != recursion_depth) || (f->call_depth < floor))
      break;
    if (exc_table_find(f->table, f->table_len, name, modes, flags))
      return i;
  }
  return -1;
}

/* ======================================================================
   exc_set_origin()  -  @EXCEPTION.ORIGIN: program name, field mark, line
   number (-1 where the program has no cross reference table)              */

Private void exc_set_origin() {
  char s[MAX_PROGRAM_NAME_LEN + 32];
  int line = -1;

  if (exc_origin != NULL) {
    free(exc_origin);
    exc_origin = NULL;
  }
  if (c_base != NULL) {
    line = k_line_no((int32_t)(pc - c_base) - 1, c_base);
    snprintf(s, sizeof(s), "%s%c%d", ProgramName(c_base), FIELD_MARK, line);
    exc_origin = strdup(s);
  }
}

/* ======================================================================
   exc_save_stack()  -  @EXCEPTION.STACK: the call stack as SYSTEM(1002)
   gives it                                                               */

Private void exc_save_stack() {
  STRING_CHUNK* str = NULL;
  struct PROGRAM* prg;
  int32_t offset;
  int i;
  DESCRIPTOR d;

  if (exc_stack != NULL) {
    free(exc_stack);
    exc_stack = NULL;
  }
  if (c_base == NULL)
    return;

  ts_init(&str, 1024);
  prg = &(process.program);
  offset = pc - c_base;
  do {
    ts_printf("%s%c%d%c%d", ProgramName(prg->saved_c_base), VALUE_MARK,
              (int)offset, SUBVALUE_MARK, k_line_no(offset, prg->saved_c_base));

    for (i = prg->gosub_depth - 1; i >= 0; i--) {
      offset = prg->gosub_stack[i] - 1; /* Back up to GOSUB (etc) */
      ts_printf("%c%d%c%d", VALUE_MARK, (int)offset, SUBVALUE_MARK,
                k_line_no(offset, prg->saved_c_base));
    }

    if ((prg = prg->prev) == NULL)
      break;

    offset = prg->saved_pc_offset - 1; /* Back up into CALL */
    ts_printf("%c", FIELD_MARK);
  } while (1);
  ts_terminate();

  InitDescr(&d, STRING);
  d.data.str.saddr = str;
  exc_stack = alloc_c_string(&d);
  k_release(&d);
}

/* ======================================================================
   exc_op_throw()  -  THROW name {, data}                                 */

Private void exc_op_throw() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Data (null if none)        |                             |
     |-----------------------------|-----------------------------|
     |  Exception name             |                             |
     |=============================|=============================|
 */

  DESCRIPTOR* descr;
  char name[MAX_EXC_NAME_LEN + 1];
  char* data;
  int n;

  descr = e_stack - 1;
  GetString(descr);
  data = alloc_c_string(descr);
  k_dismiss();

  descr = e_stack - 1;
  GetString(descr);
  n = k_get_c_string(descr, name, MAX_EXC_NAME_LEN);
  k_dismiss();

  if (n < 0) {
    free(data);
    k_error(sysmsg(12097), MAX_EXC_NAME_LEN);
  }
  if (n == 0) {
    free(data);
    k_error(sysmsg(12096));
  }

  strcpy(exc_name, name);
  if (exc_data != NULL)
    free(exc_data);
  exc_data = data;
  exc_set_origin();
  if (exc_stack != NULL) {
    free(exc_stack);
    exc_stack = NULL;
  }

  exc_raise(FALSE);
}

/* ======================================================================
   exc_raise()  -  Find the handler for the exception in exc_name and go
   to it. rethrow is TRUE when carrying an exception on (the state, origin
   and qualifiers are those of the original throw).                        */

Private void exc_raise(bool rethrow) {
  int idx;
  int flags = 0;
  bool unhandled = FALSE;
  TRY_FRAME f;
  DESCRIPTOR* restored;

  idx = try_find(exc_name, 1, &flags); /* Named or SYS$ANY */
  if (idx < 0) {
    idx = try_find(exc_name, 2, &flags); /* SYS$UNHANDLED */
    unhandled = TRUE;
  }
  if (idx < 0) {
    if ((exc_data != NULL) && (*exc_data != '\0'))
      k_error(sysmsg(12095), exc_name, exc_data);
    k_error(sysmsg(12094), exc_name);
  }

  f = try_frame[idx];
  exc_unhandled = unhandled;

  if (!rethrow) {
    /* The qualifiers act when the exception is thrown, before the call
       stack is unwound.                                                  */
    if (flags & EXC_SAVE_STACK)
      exc_save_stack();
    if (flags & EXC_DUMPING)
      pdump();
  }

  /* Give up the program levels above the frame's, as STOP does */

  while (process.call_depth > f.call_depth) {
    restored = e_stack_base + process.program.e_stack_depth;
    while (e_stack > restored)
      k_dismiss();
    k_return();
  }

  txn_rollback_to(f.txn_depth); /* Transactions begun inside the TRY clause */

  restored = e_stack_base + f.e_depth;
  while (e_stack > restored)
    k_dismiss();

  process.for_init = FALSE;
  process.op_flags = 0;
  process.program.gosub_depth = f.gosub_depth;
  try_top = idx; /* The frame and every one above it */
  pc = c_base + f.catch_pc;
}

/* ======================================================================
   exc_op_caught()  -  CAUGHT(name, modes)                                */

Private void exc_op_caught() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Modes                      | Result                      |
     |-----------------------------|-----------------------------|
     |  Exception name             |                             |
     |=============================|=============================|
 */

  DESCRIPTOR* descr;
  char name[MAX_EXC_NAME_LEN + 1];
  int modes;
  int flags;
  int n;
  bool found;

  descr = e_stack - 1;
  GetInt(descr);
  modes = (int)descr->data.value;
  k_pop(1);

  descr = e_stack - 1;
  GetString(descr);
  n = k_get_c_string(descr, name, MAX_EXC_NAME_LEN);
  k_dismiss();

  found = (n > 0) && (try_find(name, modes, &flags) >= 0);

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = found;
}

/* ======================================================================
   exc_op_match()  -  Does the exception being handled appear in a list of
   names (value mark delimited, upper case)? The dispatch code of a CATCH
   uses this to choose the clause.                                        */

Private void exc_op_match() {
  DESCRIPTOR* descr;
  char* list;
  char* p;
  char* q;
  bool found = FALSE;

  descr = e_stack - 1;
  GetString(descr);
  list = alloc_c_string(descr);
  k_dismiss();

  p = list;
  do {
    q = strchr(p, VALUE_MARK);
    if (q != NULL)
      *q = '\0';
    if (strcasecmp(p, "SYS$ANY") == 0)
      found = !exc_unhandled;
    else if (strcasecmp(p, "SYS$UNHANDLED") == 0)
      found = exc_unhandled;
    else
      found = exc_covers(p, (int)strlen(p), exc_name);
    p = q + 1;
  } while (!found && (q != NULL));

  free(list);

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = found;
}

/* ======================================================================
   exc_sys_can_catch()  -  Would a throw of this exception from here find a
   handler (named, SYS$ANY or SYS$UNHANDLED) it can reach?  k_error() asks
   before it prints anything, so an error that is going to be caught leaves
   the terminal alone.                                                    */

bool exc_sys_can_catch(const char* name) {
  int flags;

  if ((try_top == 0) || !k_can_resume())
    return FALSE;
  return try_find(name, 3, &flags) >= 0;
}

/* ======================================================================
   exc_sys_throw()  -  Throw a system exception for a run time error.
   text is the abort message, which becomes @EXCEPTION.DATA. Returns only if
   nothing can catch it; otherwise the dispatch loop goes on at the handler
   and the opcode that failed is given up.                                */

void exc_sys_throw(const char* name, const char* text) {
  if (!exc_sys_can_catch(name))
    return;

  strncpy(exc_name, name, MAX_EXC_NAME_LEN);
  exc_name[MAX_EXC_NAME_LEN] = '\0';
  if (exc_data != NULL)
    free(exc_data);
  exc_data = strdup(text);
  exc_set_origin();
  if (exc_stack != NULL) {
    free(exc_stack);
    exc_stack = NULL;
  }

  /* A process waiting for a lock gives the wait up, as it does on an abort */

  if (my_uptr->lockwait_index)
    clear_lockwait();

  exc_raise(FALSE);
  k_resume_exception(); /* Does not return */
}

/* ======================================================================
   exc_value()  -  @EXCEPTION (0), @EXCEPTION.DATA (1), @EXCEPTION.ORIGIN
   (2) and @EXCEPTION.STACK (3), read through SYSTEM() keys 9012-9015     */

void exc_value(int which, DESCRIPTOR* descr) {
  char* s = "";

  switch (which) {
    case 0:
      s = exc_name;
      break;
    case 1:
      if (exc_data != NULL)
        s = exc_data;
      break;
    case 2:
      if (exc_origin != NULL)
        s = exc_origin;
      break;
    case 3:
      if (exc_stack != NULL)
        s = exc_stack;
      break;
  }
  k_put_c_string(s, descr);
}

/* END-CODE */
