/* OBJPROG.C
 * Object programming opcodes.
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
 * 18 Oct 26 Windows port - from Linux 7aba47d (16 Oct 26): A name map of 32 entries or more is looked up through a hash index (QM4 Fixes item 13): next_named_entry().
 * 18 Oct 26 Windows port - from Linux 7f7a4fd (16 Oct 26): RESTRICTED names (QM4 gaps): find_name_map_entry() skips one the running object is not in the inheritance tree of.
 * 14 Sep 26 Windows port - op_object() lowers the class catalogue name, as
 *           op_call() does.  The property name in op_objref() stays upper:
 *           it is an identifier, not a catalogue name.  RELEASE_1.1_FIXES.md 5,
 *           stage 3a.
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Opcodes:
 *   op_object     Instantiate object
 *   op_objinfo    Object information
 *   op_objmap     Create the name map
 *   op_objref     Resolve an object reference
 *   op_get        Retrieve a property value or execute a public function
 *   op_set        Set a property value or execute a public subroutine
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "keys.h"
#include "header.h"
#include "stdarg.h"


Private bool find_name_map_entry(int16_t mode,
                                 OBJDATA* objdata,
                                 char* name,
                                 bool dismiss_obj);
Private bool find_undefined_name_handler(int16_t mode,
                                         OBJDATA* objdata,
                                         char* name,
                                         bool dismiss_obj);
Private DESCRIPTOR* resolve_index(DESCRIPTOR* array_descr,
                                  DESCRIPTOR* indx_descr,
                                  int16_t dims);
Private OBJECT_NAME_MAP* next_named_entry(OBJDATA* o,
                                          const char* name,
                                          int32_t* cursor);
Private void free_name_index(OBJDATA* o);

/* ======================================================================
   The name map index (QM4 Fixes item 13, 16 Oct 26)

   An object's name map is a packed list in its object code, searched for
   every property or method reference.  A map of NAME_INDEX_MIN entries or
   more gets a hash index the first time a name is sought in it; a smaller
   one is still scanned.  next_named_entry() returns the entries called
   `name` one at a time in map order, as the scan did, so a RESTRICTED entry
   the caller may not see is skipped for the next entry of that name.
   *cursor is 0 for the first call and is left for the next.              */

Private u_int32_t name_hash(const char* s) {
  u_int32_t h = 2166136261u;

  while (*s)
    h = (h ^ (u_char)(*s++)) * 16777619u;
  return h;
}

Private void free_name_index(OBJDATA* o) {
  NAME_INDEX* ix = o->name_index;

  if (ix != NULL) {
    k_free(ix->bucket);
    k_free(ix->next);
    k_free(ix->entry);
    k_free(ix);
    o->name_index = NULL;
  }
  o->name_count = -1;
}

Private void build_name_index(OBJDATA* o) {
  OBJECT_NAME_MAP* p;
  NAME_INDEX* ix;
  int32_t n = 0;
  int32_t i;
  int32_t b;
  int32_t* tail;

  for (p = o->name_map; p != NULL; p = NextNameMapEntry(p))
    n++;
  o->name_count = n;
  o->name_index = NULL;
  if (n < NAME_INDEX_MIN)
    return;

  ix = (NAME_INDEX*)k_alloc(126, sizeof(NAME_INDEX));
  if (ix == NULL)
    return; /* No memory: the map is scanned, as before */
  ix->nbuckets = n * 2 + 1;
  ix->bucket = (int32_t*)k_alloc(127, sizeof(int32_t) * ix->nbuckets);
  ix->next = (int32_t*)k_alloc(128, sizeof(int32_t) * n);
  ix->entry = (OBJECT_NAME_MAP**)k_alloc(129, sizeof(OBJECT_NAME_MAP*) * n);
  tail = (int32_t*)k_alloc(129, sizeof(int32_t) * ix->nbuckets);
  if (ix->bucket == NULL || ix->next == NULL || ix->entry == NULL || tail == NULL) {
    k_free(ix->bucket);
    k_free(ix->next);
    k_free(ix->entry);
    k_free(tail);
    k_free(ix);
    return;
  }
  for (b = 0; b < ix->nbuckets; b++)
    ix->bucket[b] = tail[b] = -1;

  /* Chain each hash value's entries in map order: append at the tail */
  for (i = 0, p = o->name_map; p != NULL; p = NextNameMapEntry(p), i++) {
    b = (int32_t)(name_hash(p->name) % (u_int32_t)ix->nbuckets);
    ix->entry[i] = p;
    ix->next[i] = -1;
    if (tail[b] < 0)
      ix->bucket[b] = i;
    else
      ix->next[tail[b]] = i;
    tail[b] = i;
  }
  k_free(tail);
  o->name_index = ix;
}

Private OBJECT_NAME_MAP* next_named_entry(OBJDATA* o,
                                          const char* name,
                                          int32_t* cursor) {
  OBJECT_NAME_MAP* p;
  NAME_INDEX* ix;
  int32_t i;

  if (o->name_map == NULL)
    return NULL;
  if (o->name_count < 0)
    build_name_index(o);

  if ((ix = o->name_index) == NULL) { /* Small map: scan, from entry number *cursor */
    for (i = 0, p = o->name_map; p != NULL; p = NextNameMapEntry(p), i++) {
      if (i >= *cursor && !strcmp(p->name, name)) {
        *cursor = i + 1;
        return p;
      }
    }
    return NULL;
  }

  /* *cursor is the number of the last entry returned plus one */
  i = (*cursor == 0) ? ix->bucket[name_hash(name) % (u_int32_t)ix->nbuckets] : ix->next[*cursor - 1];
  for (; i >= 0; i = ix->next[i]) {
    if (!strcmp(ix->entry[i]->name, name)) {
      *cursor = i + 1;
      return ix->entry[i];
    }
  }
  return NULL;
}

/* ======================================================================
   restricted_visible()  -  RESTRICTED names (16 Oct 26)

   A name its class declared RESTRICTED is seen only by an object in the inheritance tree of the object that holds the name: the
   object whose method is running now is that object, or inherits it, directly or through others.  The main program, an
   unrelated class and a sibling that shares a parent are outside it.                                                    */

Private bool object_inherits(OBJDATA* x, OBJDATA* owner) {
  OBJDATA* o;

  if (x == owner)
    return TRUE;
  for (o = x->inherits; o != NULL; o = o->next_inherited) {
    if (object_inherits(o, owner))
      return TRUE;
  }
  return FALSE;
}

Private bool restricted_visible(OBJDATA* owner) {
  return (process.program.objdata != NULL) && object_inherits(process.program.objdata, owner);
}

/* ======================================================================
   op_disinh()  -  DISINHERIT                                             */

void op_disinh() {
  /* Stack:

      |=============================|=============================|
      |            BEFORE           |           AFTER             |
      |=============================|=============================|
  top |  Object                     |                             |
      |=============================|=============================|
  */

  DESCRIPTOR* descr;
  OBJDATA* inh_objdata; /* Inherited OBJ structure */
  OBJDATA* obj;

  if (!(process.program.flags & HDR_IS_CLASS))
    k_error("DISINHERIT not in class.");

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  if (descr->type != OBJ)
    k_error(sysmsg(3460)); /* Object variable required */ /* TODO: Magic numbers are bad, mmkay? */

  inh_objdata = descr->data.objdata;

  /* Scan inheritance chain */

  if (process.program.objdata->inherits == NULL) {
    if (process.program.objdata->inherits == inh_objdata) {
      process.program.objdata->inherits = inh_objdata->next_inherited;
      free_object(inh_objdata);
    }
  } else {
    for (obj = process.program.objdata->inherits; obj->next_inherited != NULL;
         obj = obj->next_inherited) {
      if (obj->next_inherited == inh_objdata) {
        obj->next_inherited = inh_objdata->next_inherited;
        free_object(inh_objdata);
        break;
      }
    }
  }

  k_dismiss();
}

/* ======================================================================
   op_inherit()  -  Establish inherited object                            */

void op_inherit() {
  /* Stack:

      |=============================|=============================|
      |            BEFORE           |           AFTER             |
      |=============================|=============================|
  top |  Object                     |                             |
      |=============================|=============================|
  */

  DESCRIPTOR* descr;
  OBJDATA* objdata;     /* Our own OBJ structure */
  OBJDATA* inh_objdata; /* Inherited OBJ structure */
  OBJDATA* obj;

  if (!(process.program.flags & HDR_IS_CLASS))
    k_error("INHERIT not in class.");

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  if (descr->type != OBJ)
    k_error(sysmsg(3460)); /* Object variable required */ /* TODO: Magic numbers are bad, mmkay? */

  inh_objdata = descr->data.objdata;

  /* Add to inheritance chain */

  objdata = process.program.objdata;
  if (objdata->inherits == NULL) {
    objdata->inherits = inh_objdata;
  } else {
    for (obj = objdata->inherits; obj->next_inherited != NULL;
         obj = obj->next_inherited) {
    }
    obj->next_inherited = inh_objdata;
  }
  inh_objdata->ref_ct++;
  k_dismiss();
}

/* ======================================================================
   op_object()  -  Create an object                                       */

void op_object() {
  /* Stack:

      |=============================|=============================|
      |            BEFORE           |           AFTER             |
      |=============================|=============================|
  top |  Arguments                  |  Object reference           |
      |-----------------------------|-----------------------------|
      |  Class catalogue name       |                             |
      |=============================|=============================|
  */

  DESCRIPTOR* descr;
  int16_t num_args;
  char call_name[MAX_PATHNAME_LEN + 1];
  bool is_path;
  OBJDATA* objdata;
  u_char* object_code;

  num_args = *(pc++); /* User defined arguments - Currently always 0 */

  descr = e_stack - (num_args + 1);
  while (descr->type == ADDR)
    descr = descr->data.d_addr;

  if (k_get_c_string(descr, call_name, MAX_PATHNAME_LEN) <= 0) {
    k_illegal_call_name();
  }

  /* An internal program ($classmain) may name the class by the pathname of its runfile, as RUN does (16 Oct 26, Fixes item 484).
     A path is used as it is; a catalogue name is lower case and must be a valid call name, as before.                          */
  is_path = (process.program.flags & HDR_INTERNAL) && (strchr(call_name, DS) != NULL);
  if (!is_path) {
    LowerCaseString(call_name); /* RELEASE_1.1 5 stage 3a: canonical case */

    if (!valid_call_name(call_name))
      k_illegal_call_name();
  }

  object_code = (u_char*)load_object(call_name, FALSE);
  if (object_code == NULL)
    k_error(sysmsg(1134), call_name);

  if (!(((OBJECT_HEADER*)object_code)->flags & HDR_IS_CLASS)) {
    k_error(sysmsg(3451), call_name); /* %s is not a CLASS module */ /* TODO: Magic numbers are bad, mmkay? */
  }

  /* Create OBJDATA structure */

  objdata = create_objdata(object_code);
  ((OBJECT_HEADER*)object_code)->ext_hdr.prog.refs++;

  /* Replace the e-stack entry for the class catalogue call name with an
     OBJ descriptor that references this object.                         */

  descr = e_stack - (num_args + 1); /* 0488 load_object() may move e-stack */
  k_release(descr);
  InitDescr(descr, OBJ);
  descr->data.objdata = objdata;

  /* Set "key" for instantiation */

  object_key = 0;

  /* Although we could run the instantiation as a normal subroutine by
     using k_call(), property routines are run as recursives and a single
     program module can only ever be entirely a recursive. Therefore, we
     must run the instantiation as a recursive too.                       */

  k_recurse_object(object_code, num_args, objdata);

  return;
}

/* ======================================================================
   op_objinfo()  -  Return information about object                       */

void op_objinfo() {
  /* Stack:

      |=============================|=============================|
      |            BEFORE           |           AFTER             |
      |=============================|=============================|
  top |  Key                        |  Returned information       |
      |=============================|=============================|
      |  Addr to object variable    |                             |
      |=============================|=============================|
  */

  DESCRIPTOR* descr;
  int key;
  DESCRIPTOR result;
  OBJECT_HEADER* objprog;

  descr = e_stack - 1;
  GetInt(descr);
  key = descr->data.value;

  descr = e_stack - 2;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;

  InitDescr(&result, INTEGER);
  if (key == OI_ISOBJ) {
    result.data.value = descr->type == OBJ;
  } else {
    if (descr->type != OBJ)
      k_error("Variable is not an object.");

    switch (key) {
      case OI_CLASS:
        objprog = (OBJECT_HEADER*)(descr->data.objdata->objprog);
        k_put_c_string(ProgramName(objprog), &result);
        break;

      default:
        result.data.value = 0;
        break;
    }
  }

  k_pop(1);
  k_dismiss();
  *(e_stack++) = result;
}

/* ======================================================================
   op_objmap()  -  OBJMAP: Create object name map                         */

void op_objmap() {
  OBJDATA* objdata;
  u_int16_t name_map_len;
  objdata = process.program.objdata;

  name_map_len = *pc | (((u_int16_t)*(pc + 1)) << 8);
  pc += 2;

  free_name_index(objdata); /* Whatever map it had before */
  objdata->name_map = (name_map_len != 0) ? ((OBJECT_NAME_MAP*)pc) : NULL;
  pc += name_map_len;
}

/* ======================================================================
   op_objref()  -  OBJREF object data reference                           */

void op_objref() {
  /* Stack:

      |=============================|=============================|
      |            BEFORE           |           AFTER             |
      |=============================|=============================|
  top |  Property name              |  Reference                  |
      |-----------------------------|-----------------------------|
      |  Object variable            |                             |
      |=============================|=============================|
  */

  u_char mode; /* 0 = SET, 1 = GET */
  DESCRIPTOR* descr;
  char name[64 + 1];
  OBJDATA* objdata;

  mode = *(pc++);

  /* Get name */

  descr = e_stack - 1;
  k_get_c_string(descr, name, 64);
  UpperCaseString(name);
  k_dismiss();

  /* Get object */

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  if (descr->type != OBJ)
    k_error("Invalid object reference");
  objdata = descr->data.objdata;

  /* Scan name table */

  if (!find_name_map_entry(mode, objdata, name, TRUE)) {
    /* If there is an UNDEFINED handler, set up an OBJCDX descriptor to
       reference this.                                                  */

    if (!find_undefined_name_handler(mode, objdata, name, TRUE)) {
      k_error("Unrecognised property/method name (%s).", name);
    }
  }

  return;
}

/* ======================================================================
   create_objdata()                                                       */

OBJDATA* create_objdata(u_char* obj) {
  OBJDATA* objdata;

  objdata = (OBJDATA*)k_alloc(112, sizeof(OBJDATA));
  /* Modified by Composer AI - 2026/06/10.
     k_alloc() is malloc() and can return NULL; guard before writing. */
  if (objdata == NULL) {
    k_error("Insufficient memory for object data");
    return NULL; /* Not reached - k_error() aborts */
  }
  /* -------------------- */
  objdata->ref_ct = 1;
  objdata->objprog = obj;
  objdata->name_map = NULL;
  objdata->name_count = -1;
  objdata->name_index = NULL;
  objdata->obj_vars = NULL;
  objdata->inherits = NULL;
  objdata->next_inherited = NULL;
  objdata->destructor_run = FALSE;
  return objdata;
}

/* ======================================================================
   find_name_map_entry()                                                  */

Private bool find_name_map_entry(int16_t mode,
                                 OBJDATA* objdata,
                                 char* name,
                                 bool dismiss_obj) {
  OBJDATA* scanobj;
  OBJDATA* nextobj;
  OBJECT_NAME_MAP* p;
  int16_t var;
  int16_t key;
  u_char arg_ct;
  DESCRIPTOR* var_descr;
  int32_t cursor;

  scanobj = objdata;
  nextobj = objdata->inherits;

  do {
    cursor = 0;
    while ((p = next_named_entry(scanobj, name, &cursor)) != NULL) /* Found it */
    {
      /* RESTRICTED (16 Oct 26): a name the class declared RESTRICTED is not there for an object outside its inheritance tree */
      if (IsRestricted(p) && !restricted_visible(scanobj))
        continue;

      var = PublicVar(p);

      if (mode == 0) /* PUT / Method subroutine */
      {
        key = SetKey(p);
        arg_ct = p->set_arg_ct;
      } else /* GET / Method function */
      {
        key = GetKey(p);
        arg_ct = p->get_arg_ct;
      }

      if (key == 0) /* Bind to public variable */
      {
        if (var == 0)
          k_error("Illegal reference to property (%s).", name);

        if (var < 0) {
          if (mode == 0)
            return FALSE; /* Hide read-only if PUT */
          var = -var;
        }

        var_descr = Element(scanobj->obj_vars, var);
        if (dismiss_obj)
          k_dismiss();
        InitDescr(e_stack, ADDR);
        (e_stack++)->data.d_addr = var_descr;
      } else /* Create OBJCODE reference */
      {
        if (dismiss_obj)
          k_dismiss();
        InitDescr(e_stack, OBJCD);
        e_stack->data.objcode.objdata = scanobj;
        e_stack->data.objcode.key = key;
        e_stack->data.objcode.arg_ct = arg_ct;
        e_stack++;
      }

      return TRUE;
    }

    /* If this object has an inheritance chain, scan that before going
       on down our own inheritance chain.                              */

    if (scanobj->inherits != NULL) {
      if (find_name_map_entry(mode, scanobj->inherits, name, dismiss_obj)) {
        return TRUE;
      }
    }

    if (nextobj == NULL)
      return FALSE;
    scanobj = nextobj;
    nextobj = scanobj->next_inherited;
  } while (1);
}

/* ======================================================================
   find_undefined_name_handler()                                          */

Private bool find_undefined_name_handler(int16_t mode,
                                         OBJDATA* objdata,
                                         char* name,
                                         bool dismiss_obj) {
  OBJDATA* scanobj;
  OBJDATA* nextobj;
  OBJECT_NAME_MAP* p;
  int16_t key;
  int32_t cursor;
  /* u_char arg_ct; variable set but not used */

  scanobj = objdata;
  nextobj = objdata->inherits;

  do {
    cursor = 0;
    while ((p = next_named_entry(scanobj, "UNDEFINED", &cursor)) != NULL) /* Found it */
    {
      if (mode == 0) {/* PUT / Method subroutine */
        key = SetKey(p);
        /* arg_ct = p->set_arg_ct; varable set but never used */
      } else {/* GET / Method function */
        key = GetKey(p);
        /* arg_ct = p->get_arg_ct; variable set but never used */
      }

      if (key != 0) { /* Create OBJCODE reference */
        if (dismiss_obj)
          k_dismiss();
        InitDescr(e_stack, OBJCDX);
        e_stack->n1 = key;
        e_stack->data.objundef.objdata = scanobj;
        e_stack->data.objundef.undefined_name =
            (char*)k_alloc(113, strlen(name) + 1);
        strcpy(e_stack->data.objundef.undefined_name, name);
        e_stack++;
        return TRUE;
      }
    }

    /* If this object has an inheritance chain, scan that before going
       on down our own inheritance chain.                              */

    if (scanobj->inherits != NULL) {
      if (find_undefined_name_handler(mode, scanobj->inherits, name,
                                      dismiss_obj)) {
        return TRUE;
      }
    }

    if (nextobj == NULL)
      return FALSE;
    scanobj = nextobj;
    nextobj = scanobj->next_inherited;
  } while (1);
}

/* ======================================================================
   op_get()  -  Resolve a property retrieval reference                    */

void op_get() {
  /* Stack:

      |=============================|=============================|
      |            BEFORE           |           AFTER             |
      |=============================|=============================|
  top |  Args (variable number)     | Resolved value              |
      |-----------------------------|-----------------------------|
      |  OBJCD                      |                             |
      |=============================|=============================|

  The opcode is followed by a single byte containing the argument count.

  If the caller has referenced a public property with no Get routine, the
  OBJCD descriptor will be an ADDR to that property variable.             */

  DESCRIPTOR* descr;
  int16_t arg_ct;
  int16_t obj_arg_ct;
  int stack_depth;
  int16_t i;
  DESCRIPTOR* p;

  arg_ct = *(pc++);

  descr = e_stack - (arg_ct + 1);
  switch (descr->type) {
    case OBJCD: /* Property has a Get routine */
      obj_arg_ct = descr->data.objcode.arg_ct;
      if ((obj_arg_ct & 0x80) ? (arg_ct > (obj_arg_ct & 0x7F))
                              : (arg_ct != obj_arg_ct)) {
        k_error(sysmsg(1026)); /* Argument count mismatch in object reference */
        /* TODO: Magic numbers are bad, mmkay? */
      }

      object_key = descr->data.objcode.key;

      if (prof_mask & PROF_OBJECT) /* a public routine or property of a class module: the application event profiler (16 Oct 26) */
      {
        const char* prof_class = ((OBJECT_HEADER*)(descr->data.objcode.objdata->objprog))->ext_hdr.prog.program_name;

        prof_event(PROF_OBJECT, prof_class, (int)strlen(prof_class));
      }
      k_call("", arg_ct, (u_char*)(descr->data.objcode.objdata->objprog), 1);
      process.program.objdata = descr->data.objcode.objdata;
      k_dismiss();
      stack_depth = e_stack - e_stack_base; /* 0489 */
      k_run_program();                      /* Execute program */

      /* Ensure that we reassess trace mode in the lower layer */
      if (k_exit_cause == K_EXIT_RECURSIVE)
        k_exit_cause = K_TOGGLE_TRACER;

      if (e_stack - e_stack_base != stack_depth + 1) /* 0489 */
      {
        k_error("Object did not return a property value.");
      }
      break;

    case OBJCDX: /* Calling undefined name handler */
      if (arg_ct >=
          ((OBJECT_HEADER*)(descr->data.objundef.objdata->objprog))->args) {
        k_error(sysmsg(1026)); /* Argument count mismatch in object reference */
        /* TODO: Magic numbers are bad, mmkay? */
      }

      object_key = descr->n1;

      /* We need to insert a new first argument */
      for (i = 0, p = e_stack; i < arg_ct; i++, p--)
        *p = *(p - 1);
      e_stack++;
      k_put_c_string(descr->data.objundef.undefined_name, p);

      k_call("", arg_ct + 1, (u_char*)(descr->data.objcode.objdata->objprog),
             1);
      process.program.objdata = descr->data.objcode.objdata;
      k_dismiss();
      stack_depth = e_stack - e_stack_base; /* 0489 */
      k_run_program();                      /* Execute program */

      /* Ensure that we reassess trace mode in the lower layer */
      if (k_exit_cause == K_EXIT_RECURSIVE)
        k_exit_cause = K_TOGGLE_TRACER;

      if (e_stack - e_stack_base != stack_depth + 1) { /* 0489 */
        k_error("Object did not return a property value.");
      }
      break;

    default:
      p = descr;
      while (p->type == ADDR)
        p = p->data.d_addr;

      switch (p->type) {
        case ARRAY:
          i = (p->data.ahdr_addr->cols != 0) + 1;
          if (arg_ct != i)
            k_error(
                sysmsg(1026)); /* Argument count mismatch in object reference */
               /* TODO: Magic numbers are bad, mmkay? */
          /* Revise ADDR to point to array element */
          descr->data.d_addr = resolve_index(p, e_stack - 1, arg_ct);
          for (i = 0; i < arg_ct; i++)
            k_dismiss();
          break;

        default:
          if (arg_ct != 0)
            k_error(sysmsg(1026)); /* Argument count mismatch in object reference */
            /* TODO: Magic numbers are bad, mmkay? */
      }

      k_get_value(descr);
      break;
  }
}

/* ======================================================================
   op_set()  -  Save a property value                                     */

void op_set() {
  /* Stack:

      |=============================|=============================|
      |            BEFORE           |           AFTER             |
      |=============================|=============================|
  top |  Args (variable number)     | Resolved value              |
      |-----------------------------|-----------------------------|
      |  OBJCD                      |                             |
      |=============================|=============================|

  The opcode is followed by a single byte containing the argument count.
  There is always at least one argument (the value to save).

  If the caller has referenced a public property with no SET routine, the
  OBJCD descriptor will be an ADDR to that property variable.             */

  DESCRIPTOR* descr;
  int16_t arg_ct;
  int16_t obj_arg_ct;
  int16_t i;
  DESCRIPTOR* p;

  arg_ct = *(pc++);

  descr = e_stack - (arg_ct + 1);
  switch (descr->type) {
    case OBJCD: /* Property has a SET routine */
      obj_arg_ct = descr->data.objcode.arg_ct;
      if ((obj_arg_ct & 0x80) ? (arg_ct > (obj_arg_ct & 0x7F))
                              : (arg_ct != obj_arg_ct)) {
        k_error(sysmsg(1026)); /* Argument count mismatch in object reference */
      }

      object_key = descr->data.objcode.key;

      if (prof_mask & PROF_OBJECT) /* a public property being set: the application event profiler (16 Oct 26) */
      {
        const char* prof_class = ((OBJECT_HEADER*)(descr->data.objcode.objdata->objprog))->ext_hdr.prog.program_name;

        prof_event(PROF_OBJECT, prof_class, (int)strlen(prof_class));
      }
      k_call("", arg_ct, (u_char*)(descr->data.objcode.objdata->objprog), 1);
      process.program.objdata = descr->data.objcode.objdata;
      k_dismiss();
      k_run_program(); /* Execute program */

      /* Ensure that we reassess trace mode in the lower layer */
      if (k_exit_cause == K_EXIT_RECURSIVE)
        k_exit_cause = K_TOGGLE_TRACER;
      break;

    case OBJCDX: /* Calling undefined name handler */
      if (arg_ct >=
          ((OBJECT_HEADER*)(descr->data.objundef.objdata->objprog))->args) {
        k_error(sysmsg(1026)); /* Argument count mismatch in object reference */
        /* TODO: Magic numbers are bad, mmkay? */
      }

      object_key = descr->n1;

      /* We need to insert a new first argument */
      for (i = 0, p = e_stack; i < arg_ct; i++, p--)
        *p = *(p - 1);
      e_stack++;
      k_put_c_string(descr->data.objundef.undefined_name, p);

      k_call("", arg_ct + 1, (u_char*)(descr->data.objcode.objdata->objprog),
             1);
      process.program.objdata = descr->data.objcode.objdata;
      k_dismiss();
      k_run_program(); /* Execute program */

      /* Ensure that we reassess trace mode in the lower layer */
      if (k_exit_cause == K_EXIT_RECURSIVE)
        k_exit_cause = K_TOGGLE_TRACER;
      break;

    default: /* Property is a public variable */
      while (descr->type == ADDR)
        descr = descr->data.d_addr;

      switch (descr->type) {
        case ARRAY:
          i = (descr->data.ahdr_addr->cols != 0) + 2;
          if (arg_ct != i)
            k_error(sysmsg(1026)); /* Argument count mismatch in object reference */
            /* TODO: Magic numbers are bad, mmkay? */
          descr = resolve_index(descr, e_stack - 2, arg_ct - 1);
          break;

        default:
          if (arg_ct != 1)
            k_error(
                sysmsg(1026)); /* Argument count mismatch in object reference */
                /* TODO: Magic numbers are bad, mmkay? */
      }

      k_release(descr);      /* Release old value and... */
      *descr = *(--e_stack); /* ...Move new value */
      for (i = 0; i < arg_ct; i++)
        k_dismiss();
      break;
  }
}

/* ======================================================================
   free_object()  -  Decrement reference count and possibly free OBJDATA  */

void free_object(OBJDATA* objdata) {
  OBJECT_NAME_MAP* p;
  int16_t key;
  OBJDATA* inh;
  ARRAY_HEADER* ahdr;

  if (objdata->ref_ct == 1) {
    /* Free inherited objects
       Remove objects one by one from the head of the inheritance chain,
       updating the chain to point to the next inherited object so that
       we can survive errors during the disinheritance process. The worst
       case should be that an abort (which always represents an
       application error) might leave an object stranded in memory with
       no references to it.                                               */

    while ((inh = objdata->inherits) != NULL) {
      objdata->inherits = inh->next_inherited;
      free_object(inh);
    }

    /* Scan the name map looking for a DESTROY.OBJECT item */

    if (!(objdata->destructor_run)) {
      int32_t cursor = 0;

      if ((p = next_named_entry(objdata, "DESTROY.OBJECT", &cursor)) != NULL) /* Found it */
      {
        /* Mark the object destructor routine as having been run so that
           an abort in the destructor does not cause us to run it again. */

        objdata->destructor_run = TRUE;

        key = SetKey(p);
        if ((key != 0) && (PublicVar(p) == 0) && (p->set_arg_ct == 0)) {
          object_key = key;
          k_recurse_object((u_char*)(objdata->objprog), 0, objdata);
        }
      }
    }

    --(((OBJECT_HEADER*)(objdata->objprog))->ext_hdr.prog.refs);

    ahdr = objdata->obj_vars;
    if (--(ahdr->ref_ct) == 0)
      free_array(ahdr);

    free_name_index(objdata);
    k_free(objdata);
  } else
    (objdata->ref_ct)--;
}

/* ====================================================================== */

Private DESCRIPTOR* resolve_index(
    DESCRIPTOR* array_descr, /* The matrix being accessed */
    DESCRIPTOR* index_descr, /* The top index on the e-stack */
    int16_t dims)          /* Expected dimensionality */
{
  ARRAY_HEADER* ahdr;
  int32_t rows;
  int32_t cols;
  int32_t row;
  int32_t col;
  int32_t indx;

  ahdr = array_descr->data.ahdr_addr;
  rows = ahdr->rows;
  cols = ahdr->cols;

  if (cols == 0) /* One dimensional matrix */
  {
    GetInt(index_descr);

    indx = index_descr->data.value;
    if ((indx < 0) || (indx > ahdr->rows) ||
        (indx == 0 && (ahdr->flags & AH_PICK_STYLE))) {
      k_index_error(array_descr);
    }
  } else /* Two dimensional matrix */
  {
    GetInt(index_descr);
    col = index_descr->data.value;

    index_descr--;
    GetInt(index_descr);
    row = index_descr->data.value;

    if ((row == 0) || (col == 0)) {
      if (ahdr->flags & AH_PICK_STYLE)
        k_index_error(array_descr);
      indx = 0;
    } else {
      if ((row <= 0) || (row > rows) || (col <= 0) || (col > cols)) {
        k_index_error(array_descr);
      }
      indx = ((row - 1) * cols) + col;
    }
  }

  return Element(ahdr, indx);
}

/* END-CODE */
