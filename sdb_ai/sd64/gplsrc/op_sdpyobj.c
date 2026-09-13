/* op_sdpyobj.c - the SD_PYOBJ opcode: SD's named Python objects.
 *
 * PROJECT_STATUS.md 5.27.  Restored 12 Sep 2026 at the SAME OPCODE, 0xCFFE,
 * which was retired in place on 13 Aug 2026 precisely so this could happen
 * without renumbering every opcode after it and invalidating all compiled
 * pcode.
 *
 * ***WHAT CHANGED UNDERNEATH AND WHAT DID NOT.***  The BASIC surface is
 * unchanged - same opcode, same keys in keys.h, same three-string-and-a-key
 * call, same error numbers in err.h - so the 20 PY_* programs are the ones
 * they always were.  What changed is that no Python is loaded here: each key
 * becomes one request on a pipe to sdpy.exe, a native process (5.3, 5.27).
 *
 * ***THE ARGUMENT ORDER IS REVERSED AND IT IS EASY TO GET WRONG.***
 * SDPYOBJ(a, b, c, key) pushes a, b, c then key, so after the key is popped
 * the first getarg() returns c.  Therefore, in this file:
 *
 *      Arg1 = the BASIC third argument = THE OBJECT NAME, always
 *      Arg2 = the BASIC second argument = a key, or another object's name
 *      Arg3 = the BASIC first argument = a value, used only by DictVset
 *
 * Checked against all fourteen call sites at 489b18e^ rather than assumed from
 * one.
 *
 * ***AND EVERY ARGUMENT IS A NUL-TERMINATED C STRING HERE.***  That is this
 * layer's limit, not the pipe's: sdpy.exe and sdpy_client.c both carry
 * explicit lengths and move any byte, but getarg() below hands up C strings,
 * so a value containing NUL is truncated before it reaches the pipe.  Marks
 * (0xFE/0xFD/0xFC) pass through perfectly well; NUL does not.  The same
 * sentence is already true of SDEXT - see the SCRAM note in keys.h.
 *
 * START-HISTORY:
 * 12 Sep 26 Windows port - written for the helper process, 5.27.  The file it
 *           replaces loaded Python into sd.exe and was removed at 489b18e.
 * END-HISTORY
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "err.h"
#include "keys.h"
#include "sdpy_client.h"

#include <stdlib.h>
#include <string.h>

extern SDPY* sdpy_session(int* err_code);   /* sdpy_session.c */

Private char* getarg(void);
Private char* freeArg(char* Arg);

/* One exchange with the helper.
 *
 * RETURNS the helper's status, or SD_PyErr_NoHelper if there was no exchange.
 * *payload / *plen are the reply body, valid until the next call.
 *
 * ***A TRANSPORT FAILURE IS NOT A PYTHON ERROR.***  sdpy_call returns -1 when
 * the pipe broke, which means the helper died mid-call; answering with a
 * Python error number would tell the caller that Python had an opinion about
 * their request when it never saw it. */
Private int py_call(const char* verb,
                    const char* a1, const char* a2, const char* a3,
                    char** payload, size_t* plen) {
  SDPY* s;
  int err_code = 0;
  int status = 0;

  if (payload != NULL) *payload = NULL;
  if (plen != NULL) *plen = 0;

  s = sdpy_session(&err_code);
  if (s == NULL)
    return err_code != 0 ? err_code : SD_PyErr_NoHelper;

  if (sdpy_call(s, verb,
                a1, a1 ? strlen(a1) : 0,
                a2, a2 ? strlen(a2) : 0,
                a3, a3 ? strlen(a3) : 0,
                &status, payload, plen) != 0)
    return SD_PyErr_NoHelper;

  return status;
}

/* Return an integer result to BASIC and set STATUS(). */
Private void py_return_int(int status) {
  process.status = status;
  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = (int32_t)status;
}

/* Return a string result to BASIC and set STATUS().
 *
 * On failure the value is the EMPTY STRING and the reason is in STATUS(),
 * which is what every PY_* header documents: "on success returned string or
 * empty string on failure".  The helper's payload on an error path is a
 * traceback meant for a human; handing it back as the VALUE would make a
 * failed call look like a successful one that returned prose. */
Private void py_return_str(int status, char* payload, size_t plen) {
  process.status = status;
  if (status != 0 || payload == NULL) {
    k_put_c_string("", e_stack);
  } else {
    /* k_put_string carries a length, so a value containing marks survives. */
    k_put_string(payload, (int)plen, e_stack);
  }
  e_stack++;
}

/* ======================================================================
   op_sdpyobj()  -  SD_PYOBJ(arg1, arg2, arg3, key)

      Stack:
        +=============================++=============================+
        +       STACK On Entry        ++       STACK On Exit         +
        +=============================++=============================+
estack> +    next available descr     ++    next available descr     +
        +=============================++=============================+
        +  descriptor w/ integer key  ++  Addr to descr for RTNVAL   +
        +=============================++=============================+
        + Addr to descriptor for Arg1 ++
        +=============================++
        + Addr to descriptor for Arg2 ++
        +=============================++
        + Addr to descriptor for Arg3 ++
        +=============================++                             */

void op_sdpyobj() {
  int16_t key;
  char* Arg1 = NULL;      /* the object name - see the header */
  char* Arg2 = NULL;      /* a key, or another object's name */
  char* Arg3 = NULL;      /* a value */
  char* payload = NULL;
  size_t plen = 0;
  int status;
  DESCRIPTOR* descr;

  process.status = 0;

  descr = e_stack - 1;
  GetInt(descr);
  key = (int16_t)(descr->data.value);
  k_pop(1);

  Arg1 = getarg();
  Arg2 = getarg();
  Arg3 = getarg();

  switch (key) {
    case SD_PyDictCrte:
      py_return_int(py_call("DICTCRTE", NULL, NULL, Arg1, &payload, &plen));
      break;

    case SD_PyDictClr:
      py_return_int(py_call("DICTCLR", NULL, NULL, Arg1, &payload, &plen));
      break;

    case SD_PyDictVset:
      py_return_int(py_call("DICTVSET", Arg3, Arg2, Arg1, &payload, &plen));
      break;

    case SD_PyDictVget:
      status = py_call("DICTVGET", NULL, Arg2, Arg1, &payload, &plen);
      py_return_str(status, payload, plen);
      break;

    case SD_PyDictIDel:
      py_return_int(py_call("DICTIDEL", NULL, Arg2, Arg1, &payload, &plen));
      break;

    case SD_PyDictKeys:
      status = py_call("DICTKEYS", NULL, NULL, Arg1, &payload, &plen);
      py_return_str(status, payload, plen);
      break;

    case SD_PyDictValues:
      status = py_call("DICTVALUES", NULL, NULL, Arg1, &payload, &plen);
      py_return_str(status, payload, plen);
      break;

    case SD_PYStrSet:
      py_return_int(py_call("STRSET", Arg2, NULL, Arg1, &payload, &plen));
      break;

    case SD_PYStrGet:
      status = py_call("STRGET", NULL, NULL, Arg1, &payload, &plen);
      py_return_str(status, payload, plen);
      break;

    case SD_PYDelObj:
      py_return_int(py_call("DELOBJ", NULL, NULL, Arg1, &payload, &plen));
      break;

    case SD_PyObjLen:
      /* The helper answers with the length as text; BASIC wants a number. */
      status = py_call("OBJLEN", NULL, NULL, Arg1, &payload, &plen);
      if (status == 0 && payload != NULL) {
        process.status = 0;
        InitDescr(e_stack, INTEGER);
        (e_stack++)->data.value = (int32_t)strtol(payload, NULL, 10);
      } else {
        py_return_int(status);
      }
      break;

    case SD_PyObjType:
      status = py_call("OBJTYPE", NULL, NULL, Arg1, &payload, &plen);
      py_return_str(status, payload, plen);
      break;

    case SD_PyListCrte:
      py_return_int(py_call("LISTCRTE", NULL, NULL, Arg1, &payload, &plen));
      break;

    case SD_PyListGet:
      status = py_call("LISTGET", NULL, NULL, Arg1, &payload, &plen);
      py_return_str(status, payload, plen);
      break;

    case SD_PyListAppd:
      py_return_int(py_call("LISTAPPD", NULL, Arg2, Arg1, &payload, &plen));
      break;

    case SD_PyListClr:
      py_return_int(py_call("LISTCLR", NULL, NULL, Arg1, &payload, &plen));
      break;

    default:
      py_return_int(SD_EXT_KEY_ERR);
      break;
  }

  Arg1 = freeArg(Arg1);
  Arg2 = freeArg(Arg2);
  Arg3 = freeArg(Arg3);
}

/* Lift one string argument off the stack into a buffer this file owns.
 * Patterned on op_sdext.c's handling of the same problem. */
Private char* getarg(void) {
  DESCRIPTOR* descr;
  STRING_CHUNK* str;
  int32_t myval_len;
  char* buf;

  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  myval_len = (str == NULL) ? 0 : str->string_len;

  buf = (char*)k_alloc(108, myval_len + 1);
  if (buf == NULL)
    k_error(sysmsg(10005));            /* Insufficient memory - never returns */

  if (myval_len == 0)
    buf[0] = '\0';
  else
    (void)k_get_c_string(descr, buf, myval_len);

  /* dismiss, not pop: a string may be a linked list of chunks and pop would
     leak them.  After this e_stack points at the descriptor that will receive
     the return value. */
  k_dismiss();
  return buf;
}

Private char* freeArg(char* Arg) {
  if (Arg != NULL)
    k_free(Arg);
  return NULL;
}

/* END-CODE */
