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
 * 29 Sep 26 RELEASE_1.1 114 - op_run() takes a runfile path up to
 *           MAX_PATHNAME_LEN, not MAX_PROGRAM_NAME_LEN (from Solo's SOLO 12)
 * 14 Sep 26 Windows port - call names are canonical LOWER case: the five
 *           UpperCaseString() calls became LowerCaseString(), and
 *           valid_call_name() accepts lower case only.  RELEASE_1.1_FIXES.md 5,
 *           stage 3a.
 * 31 Dec 23 SD launch - prior history suppressed
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
   op_call()  -  Call catalogued routine                                  */

void op_call() {
  DESCRIPTOR* descr;
  int16_t num_args;
  char call_name[MAX_PROGRAM_NAME_LEN + 1];

  num_args = *(pc++);

  descr = e_stack - (num_args + 1);
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

      k_call(call_name, num_args, NULL, 1);

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
  ARRAY_HEADER* ahdr;
  int16_t i;

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
      if (k_get_c_string(subr_descr, call_name, MAX_PROGRAM_NAME_LEN) <= 0) {
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

      k_call(call_name, num_args, NULL, 0);

      /* Convert descriptor to become a SUBR.  Convert type, copy string
         pointer, set object address.                                     */

      subr_descr->type = SUBR; /* Preserve flags (e.g. DF_SYSTEM) */
      subr_descr->data.subr.saddr = subr_descr->data.str.saddr;

      subr_descr->data.subr.object = c_base;
      ((OBJECT_HEADER*)c_base)->ext_hdr.prog.refs++;
      break;

    case SUBR:
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

    if (strchr("*$_!", call_name[0]) == NULL) { /* No prefix */
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
  /* 14 Sep 26 Windows port - LOWER CASE ONLY, RELEASE_1.1 5 stage 3a.  Every
     caller converts the name with LowerCaseString() immediately before this
     test, so an upper-case letter here means a caller that missed the flip -
     and NTFS would otherwise hide it by opening gcat case-blind.  Refusing it
     makes such a site fail loudly as an illegal call name.                   */
  char valid_chars[] = "abcdefghijklmnopqrstuvwxyz0123456789.%$-_";
  char leading_chars[] = "*$!_";

  /* !!CALLNAME!! */

  if (strlen(p) > MAX_CALL_NAME_LEN)
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
  int nlen;
  int any = -1;
  int unhandled = -1;

  nlen = (int)strlen(name);
  p = tab;
  end = tab + len;
  while (p < end) {
    q = p;
    while ((q < end) && (*q != (u_char)VALUE_MARK)) /* VALUE_MARK is a signed char */
      q++;
    n = (int)(q - p) - 1; /* Length of the name; p[0] is the flag digit */
    if (n > 0) {
      if ((n == nlen) && (strncasecmp((const char*)p + 1, name, n) == 0)) {
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
      found = (strcasecmp(p, exc_name) == 0);
    p = q + 1;
  } while (!found && (q != NULL));

  free(list);

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = found;
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
