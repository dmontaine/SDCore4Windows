/* sdpy.c - the Python helper process.  PROJECT_STATUS.md section 5.27.
 *
 * ***WHY A SEPARATE PROCESS.***  Section 5.3: the MSYS2 runtime that sd.exe is
 * built against and the native runtime python.org ships never meet in one
 * process - "long" is 8 bytes on one side and 4 on the other.  The owner ruled
 * the helper over a shim DLL on 11 Sep 2026 with that cost stated.  So this is
 * a NATIVE UCRT64 binary, built the way the client DLLs are, and the runtime
 * boundary is a pipe rather than a linker flag.
 *
 * ***IT LINKS THE STABLE ABI, AND THAT IS MEASURED RATHER THAN HOPED.***
 * gplbld/probe-pylimited.c, 12 Sep 2026: built -lpython3 with Py_LIMITED_API at
 * a 3.13 floor, it bound python3.dll AND the concrete python314.DLL behind it
 * and ran 3.14.7 - read back from the loader, not assumed from the link line.
 * It also ran as LocalSystem (probe-pysystem.ps1, same day), which is the
 * identity an API session has.  One binary therefore serves every Python at or
 * above the floor, and the floor is a compile-time choice.
 *
 * ======================================================================
 * THE PROTOCOL
 *
 * ***LENGTH-PREFIXED, NOT LINE-BASED, AND THIS IS THE ONE DECISION THAT IS
 * EXPENSIVE TO CHANGE LATER.***  The payloads are arbitrary SD strings:
 * PY_RUNSTRING carries a whole Python program, and dictionary values carry
 * @fm/@vm marks and can carry NUL.  A line protocol would corrupt exactly the
 * values it exists to move, and do it SILENTLY.
 *
 *   request    VERB n1 n2 n3 \n  followed by n1+n2+n3 raw bytes
 *   response   status n \n       followed by n raw bytes
 *
 * "status" is 0 for success or an SD error code from gplsrc/err.h, so the
 * numbers PY_* already document - "status() - 0 on success, error code as
 * defined in ERR.H" - travel rather than being re-invented.
 *
 * ======================================================================
 * WHAT THIS DOES THAT THE REMOVED EMBEDDED VERSION COULD NOT
 *
 * 1. ***IT RETURNS THE TRACEBACK.***  The old surface returned an int: a
 *    failing script gave the caller -12004 and nothing else.  Here sys.stderr
 *    is captured, so PyErr_Print() writes the real traceback into the buffer
 *    and it comes back as the payload.
 *
 * 2. ***IT CAPTURES print().***  This is not a nicety, it is a correctness
 *    requirement of the shape: stdout IS the protocol channel, so a script
 *    that printed would corrupt the frame stream.  sys.stdout is redirected
 *    before any user code can run.
 *
 * 3. ***ONE NAMESPACE, SHARED BOTH WAYS.***  The old code used __main__'s
 *    dict.  Here SD's named objects and the scripts' globals are the same
 *    dict, so PY_STRSET('greeting', 'hello') then PY_RUNSTRING('print(greeting)')
 *    works, and SD's names cannot collide with an imported module's.
 *
 * 4. ***A VERSIONED HANDSHAKE.***  HELLO must come first and must agree, so a
 *    stale helper left on a machine cannot quietly answer a newer SD.
 *
 * 5. The flag argument is gone.  Every one of the six SDEXT call sites passed
 *    @FALSE and nothing ever passed TRUE; carrying it forward would have been
 *    politeness to a field with no meaning.
 *
 * ***WHAT IT DELIBERATELY DOES NOT DO: THE PERMISSION GATE.***  Section 8
 * constraint 4 - Python's os.system never reaches os_permitted(), and all 20
 * PY_* carry $internal so a gate called from inside one passes for every user.
 * That gate belongs where the helper is STARTED, on SD's side, and is not
 * faked here.  This process refuses to run on a terminal, which stops it being
 * a casual Python shell, and that is the whole of its own claim.
 *
 * Exit 0 clean shutdown, 1 protocol error, 2 could not start.
 */

#define Py_LIMITED_API 0x030D0000

#include <Python.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <io.h>
#include <fcntl.h>

/* From gplsrc/err.h - the numbers PY_* already document. */
#define SD_PyEr_NotInit      -12001
#define SD_PyEr_Dict         -12002
#define SD_PyEr_Excpt        -12004
#define SD_PyErr_ObjNOF     -12014
#define SD_PyErr_NamSpcErr  -12013
#define SD_PyErr_NotStr     -12019
#define SD_PyErr_DelObj     -12020
#define SD_PyErr_UniToStr    -12009  /* unicode -> Latin failed on the way out */
#define SD_PyErr_EnLatin    -12018  /* Latin -> unicode failed on the way in  */
#define SD_PyEr_Key          -12007  /* key not in the dictionary */
#define SD_PyEr_ObToStr      -12008  /* object would not convert to a string */
#define SD_PyErr_DictExsts  -12012  /* a name is already in use */
#define SD_PyErr_DictSet    -12015
#define SD_PyErr_DictDel    -12016
#define SD_PyErr_NotDict    -12017
#define SD_PyErr_CreStr     -12031
#define SD_PyErr_LstItem    -12033
#define SD_PyErr_NotList    -12034

#define SDPY_PROTOCOL "SDPY1"
#define MAX_PAYLOAD (64 * 1024 * 1024)

static PyObject* g_ns = NULL;      /* the one namespace, SD names and globals */
static PyObject* g_cap = NULL;     /* io.StringIO capturing stdout and stderr */
static int g_hello = 0;            /* HELLO seen and agreed */

/* ---------------------------------------------------------------- framing */

static int read_exact(char* buf, size_t n) {
  size_t got = 0;
  while (got < n) {
    size_t r = fread(buf + got, 1, n - got, stdin);
    if (r == 0)
      return 0;
    got += r;
  }
  return 1;
}

static void respond(int status, const char* payload, size_t len) {
  printf("%d %zu\n", status, len);
  if (len != 0)
    fwrite(payload, 1, len, stdout);
  fflush(stdout);
}

static void respond_str(int status, const char* s) {
  respond(status, s, s == NULL ? 0 : strlen(s));
}

/* --------------------------------------------------------------- capturing */

/* ======================================================================
 * ***THE PAYLOAD ENCODING IS LATIN-1, AND THAT IS NOT A STYLE CHOICE.***
 *
 * An SD string is BYTES.  Its marks are 0xFE, 0xFD and 0xFC (@fm, @vm, @sm),
 * which are not valid UTF-8 - so PyUnicode_FromString would REJECT exactly the
 * dynamic arrays this exists to carry, and it stops at the first NUL besides.
 * Latin-1 maps 0x00-0xFF onto U+0000-U+00FF one for one, so every byte SD can
 * hold survives the round trip and the length is carried explicitly.
 *
 * The removed code already knew this and its error names are the evidence:
 * SD_PyErr_EnLatin "error encoding latin string to unicode" and
 * SD_PyErr_UniToStr "error encoding unicode python string to to Latin".
 * Re-derived here rather than inherited - the first version of this file used
 * UTF-8 and would have failed on the first value containing a mark.
 * ====================================================================== */

static PyObject* sd_bytes_to_str(const char* p, size_t len) {
  return PyUnicode_DecodeLatin1(p, (Py_ssize_t)len, "strict");
}

/* Read everything Python has printed since the last drain, and empty the
 * buffer.  Returned as a NEW reference to a bytes object, or NULL. */
static PyObject* drain_capture(void) {
  PyObject* val;
  PyObject* enc;
  if (g_cap == NULL)
    return NULL;
  val = PyObject_CallMethod(g_cap, "getvalue", NULL);
  if (val == NULL) {
    PyErr_Clear();
    return NULL;
  }
  /* truncate(0) then seek(0) - the order matters, and the other way round
   * leaves the old bytes in place padded with NULs. */
  {
    PyObject* t = PyObject_CallMethod(g_cap, "truncate", "i", 0);
    Py_XDECREF(t);
    t = PyObject_CallMethod(g_cap, "seek", "i", 0);
    Py_XDECREF(t);
    PyErr_Clear();
  }
  /* "replace" rather than "strict": a script is free to print a character
   * Latin-1 cannot hold, and losing the whole traceback because of one of them
   * would be the worst possible moment to be strict. */
  enc = PyUnicode_AsEncodedString(val, "latin-1", "replace");
  Py_DECREF(val);
  if (enc == NULL) {
    PyErr_Clear();
    return NULL;
  }
  return enc;
}

/* Respond with whatever Python printed, at the given status. */
static void respond_capture(int status) {
  PyObject* enc = drain_capture();
  if (enc == NULL) {
    respond(status, "", 0);
    return;
  }
  respond(status, PyBytes_AsString(enc), (size_t)PyBytes_Size(enc));
  Py_DECREF(enc);
}

/* An exception is pending: print it into the capture buffer so the CALLER
 * gets the traceback, not just a number.  PyErr_Print clears the error. */
static void respond_python_error(int status) {
  if (PyErr_Occurred())
    PyErr_Print();
  respond_capture(status);
}

/* --------------------------------------------------------------- lifecycle */

static int start_interpreter(void) {
  PyObject* io_mod;
  PyObject* sys_mod;
  PyObject* builtins;

  Py_Initialize();
  if (!Py_IsInitialized())
    return 0;

  /* ***REDIRECT BEFORE ANY USER CODE CAN RUN.***  stdout is the protocol
   * channel; one print() into it would desynchronise every frame after it. */
  io_mod = PyImport_ImportModule("io");
  if (io_mod == NULL)
    return 0;
  g_cap = PyObject_CallMethod(io_mod, "StringIO", NULL);
  Py_DECREF(io_mod);
  if (g_cap == NULL)
    return 0;

  sys_mod = PyImport_ImportModule("sys");
  if (sys_mod == NULL)
    return 0;
  if (PyObject_SetAttrString(sys_mod, "stdout", g_cap) != 0 ||
      PyObject_SetAttrString(sys_mod, "stderr", g_cap) != 0) {
    Py_DECREF(sys_mod);
    return 0;
  }
  Py_DECREF(sys_mod);

  g_ns = PyDict_New();
  if (g_ns == NULL)
    return 0;
  builtins = PyImport_ImportModule("builtins");
  if (builtins == NULL)
    return 0;
  if (PyDict_SetItemString(g_ns, "__builtins__", builtins) != 0) {
    Py_DECREF(builtins);
    return 0;
  }
  Py_DECREF(builtins);
  return 1;
}

static void stop_interpreter(void) {
  Py_CLEAR(g_ns);
  Py_CLEAR(g_cap);
  if (Py_IsInitialized())
    Py_Finalize();
}

/* ------------------------------------------------------------------- verbs */

/* exec(compile(src, "<sdpy>", "exec"), ns, ns).
 *
 * NOT PyRun_String: section 8's survey of the stable ABI found PyRun_String
 * and PyRun_File are the only two CPython calls the removed code used that
 * have NO stable-ABI equivalent.  builtins.compile and builtins.exec are
 * reachable through PyObject_CallMethod and are the re-expression that entry
 * recommends. */
static void verb_runstr(const char* src, size_t srclen) {
  PyObject* builtins;
  PyObject* code;
  PyObject* res;
  PyObject* text;

  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return; }

  builtins = PyImport_ImportModule("builtins");
  if (builtins == NULL) { respond_python_error(SD_PyEr_Excpt); return; }

  text = sd_bytes_to_str(src, srclen);
  if (text == NULL) {
    Py_DECREF(builtins);
    respond_python_error(SD_PyEr_Excpt);
    return;
  }
  code = PyObject_CallMethod(builtins, "compile", "Oss", text, "<sdpy>", "exec");
  Py_DECREF(text);
  if (code == NULL) {
    Py_DECREF(builtins);
    respond_python_error(SD_PyEr_Excpt);   /* a SyntaxError, with its line */
    return;
  }

  res = PyObject_CallMethod(builtins, "exec", "OOO", code, g_ns, g_ns);
  Py_DECREF(code);
  Py_DECREF(builtins);
  if (res == NULL) {
    respond_python_error(SD_PyEr_Excpt);
    return;
  }
  Py_DECREF(res);
  respond_capture(0);          /* whatever the script printed */
}

/* Look a named SD object up in the namespace.  Borrowed reference or NULL. */
static PyObject* lookup(const char* name) {
  if (g_ns == NULL || name == NULL || *name == '\0')
    return NULL;
  return PyDict_GetItemString(g_ns, name);
}

static void verb_strset(const char* name, const char* value, size_t vlen) {
  PyObject* s;
  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return; }
  if (name == NULL || *name == '\0') { respond_str(SD_PyErr_NamSpcErr, ""); return; }
  s = sd_bytes_to_str(value == NULL ? "" : value, value == NULL ? 0 : vlen);
  if (s == NULL) { respond_python_error(SD_PyErr_EnLatin); return; }
  if (PyDict_SetItemString(g_ns, name, s) != 0) {
    Py_DECREF(s);
    respond_python_error(SD_PyErr_NamSpcErr);
    return;
  }
  Py_DECREF(s);
  respond(0, "", 0);
}

static void verb_strget(const char* name) {
  PyObject* obj;
  PyObject* enc;
  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return; }
  obj = lookup(name);
  if (obj == NULL) { respond_str(SD_PyErr_ObjNOF, ""); return; }
  /* Strict on the way out: a value SD cannot hold must be reported, not
   * silently mangled into one it can. */
  enc = PyUnicode_AsEncodedString(obj, "latin-1", "strict");
  if (enc == NULL) {
    PyErr_Clear();
    respond_str(SD_PyErr_UniToStr, "");
    return;
  }
  respond(0, PyBytes_AsString(enc), (size_t)PyBytes_Size(enc));
  Py_DECREF(enc);
}

static void verb_objtype(const char* name) {
  PyObject* obj;
  PyObject* builtins;
  PyObject* ty;
  PyObject* nm;
  PyObject* enc;

  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return; }
  obj = lookup(name);
  if (obj == NULL) { respond_str(SD_PyErr_ObjNOF, ""); return; }

  builtins = PyImport_ImportModule("builtins");
  if (builtins == NULL) { respond_python_error(SD_PyEr_Excpt); return; }
  ty = PyObject_CallMethod(builtins, "type", "O", obj);
  Py_DECREF(builtins);
  if (ty == NULL) { respond_python_error(SD_PyEr_Excpt); return; }
  nm = PyObject_GetAttrString(ty, "__name__");
  Py_DECREF(ty);
  if (nm == NULL) { respond_python_error(SD_PyEr_Excpt); return; }
  enc = PyUnicode_AsUTF8String(nm);
  Py_DECREF(nm);
  if (enc == NULL) { PyErr_Clear(); respond_str(SD_PyEr_Excpt, ""); return; }
  respond(0, PyBytes_AsString(enc), (size_t)PyBytes_Size(enc));
  Py_DECREF(enc);
}

static void verb_objlen(const char* name) {
  PyObject* obj;
  Py_ssize_t n;
  char buf[32];
  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return; }
  obj = lookup(name);
  if (obj == NULL) { respond_str(SD_PyErr_ObjNOF, ""); return; }
  n = PyObject_Length(obj);
  if (n < 0) { respond_python_error(SD_PyEr_Excpt); return; }
  (void)snprintf(buf, sizeof(buf), "%zd", n);
  respond_str(0, buf);
}

/* ======================================================================
 * THE DICT AND LIST FAMILIES
 *
 * ***THE SEPARATOR IS @fm (0xFE), AND THE OLD DOCUMENTATION SAID OTHERWISE.***
 * Every PY_DICTGETKEYS-style header at 489b18e^ reads "tab separated list",
 * and the C beside it joined with PyUnicode_FromString("thorn") - U+00FE,
 * which IS @fm - with the tab version commented out one line above.  The code
 * was right and the header was stale, the same shape as the CREATE.ACCOUNT
 * grammar SD Core for Linux filed as bug 4.  Measured at 489b18e^, not
 * inherited.
 *
 * ***AND A LIMIT WORTH KNOWING RATHER THAN HIDING: a key or value that itself
 * contains @fm makes an ambiguous list.***  The old code had the same hole and
 * nothing said so.  It is inherent to a mark-joined string, it is not fixable
 * inside this format, and DCOUNT on the result is what a caller would notice
 * it with.
 * ====================================================================== */

#define SD_FM 0xFE

/* A growing byte buffer, because the result is BYTES with a length and must
 * not go anywhere near a C string: the items can contain NUL. */
typedef struct { char* p; size_t len; size_t cap; int bad; } buf_t;

static void buf_add(buf_t* b, const char* s, size_t n) {
  if (b->bad) return;
  if (b->len + n + 1 > b->cap) {
    size_t want = (b->cap ? b->cap : 256);
    char* np;
    while (want < b->len + n + 1) want *= 2;
    np = (char*)realloc(b->p, want);
    if (np == NULL) { b->bad = 1; return; }
    b->p = np;
    b->cap = want;
  }
  memcpy(b->p + b->len, s, n);
  b->len += n;
}

static int is_instance_of(PyObject* obj, const char* type_name) {
  PyObject* builtins;
  PyObject* ty;
  int r;
  builtins = PyImport_ImportModule("builtins");
  if (builtins == NULL) return -1;
  ty = PyObject_GetAttrString(builtins, type_name);
  Py_DECREF(builtins);
  if (ty == NULL) return -1;
  r = PyObject_IsInstance(obj, ty);
  Py_DECREF(ty);
  return r;
}

/* Join a Python sequence into an @fm-marked SD string and respond with it. */
static void respond_joined(PyObject* seq) {
  Py_ssize_t n;
  Py_ssize_t i;
  buf_t b;
  b.p = NULL; b.len = 0; b.cap = 0; b.bad = 0;

  n = PySequence_Size(seq);
  if (n < 0) { respond_python_error(SD_PyEr_Excpt); return; }

  /* ***AN EMPTY COLLECTION IS NOT AN ERROR, AND THIS IS A DELIBERATE CHANGE.***
   * The removed code returned SD_PyErr_NoItems (-12030) for an empty list or
   * dict, so every caller had to special-case a state that is perfectly
   * normal.  Here it is status 0 and an empty payload, which DCOUNT reads as
   * 0 without any special casing.  Recorded because it diverges from what the
   * PY_* headers documented. */
  for (i = 0; i < n; i++) {
    PyObject* item = PySequence_GetItem(seq, i);
    PyObject* s;
    PyObject* enc;
    if (item == NULL) { free(b.p); respond_python_error(SD_PyErr_LstItem); return; }
    s = PyObject_Str(item);
    Py_DECREF(item);
    if (s == NULL) { free(b.p); respond_python_error(SD_PyErr_CreStr); return; }
    enc = PyUnicode_AsEncodedString(s, "latin-1", "replace");
    Py_DECREF(s);
    if (enc == NULL) { PyErr_Clear(); free(b.p); respond_str(SD_PyErr_UniToStr, ""); return; }
    if (i != 0) { char fm = (char)SD_FM; buf_add(&b, &fm, 1); }
    buf_add(&b, PyBytes_AsString(enc), (size_t)PyBytes_Size(enc));
    Py_DECREF(enc);
  }
  if (b.bad) { free(b.p); respond_str(SD_PyErr_CreStr, ""); return; }
  respond(0, b.len ? b.p : "", b.len);
  free(b.p);
}

static void verb_dictcrte(const char* name) {
  PyObject* d;
  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return; }
  if (name == NULL || *name == '\0') { respond_str(SD_PyErr_NamSpcErr, ""); return; }
  if (lookup(name) != NULL) { respond_str(SD_PyErr_DictExsts, ""); return; }
  d = PyDict_New();
  if (d == NULL) { respond_python_error(SD_PyEr_Dict); return; }
  if (PyDict_SetItemString(g_ns, name, d) != 0) {
    Py_DECREF(d);
    respond_python_error(SD_PyErr_NamSpcErr);
    return;
  }
  Py_DECREF(d);
  respond(0, "", 0);
}

/* LISTCRTE HAS NO PY_* EQUIVALENT AND THAT LOOKS LIKE A GAP RATHER THAN A
 * DECISION: the removed API could append to a list, clear one and read one,
 * but could only CREATE one by running a script that said "x = []".  Added
 * for symmetry with the dictionary; nothing is obliged to use it. */
static void verb_listcrte(const char* name) {
  PyObject* l;
  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return; }
  if (name == NULL || *name == '\0') { respond_str(SD_PyErr_NamSpcErr, ""); return; }
  if (lookup(name) != NULL) { respond_str(SD_PyErr_DictExsts, ""); return; }
  l = PyList_New(0);
  if (l == NULL) { respond_python_error(SD_PyEr_Excpt); return; }
  if (PyDict_SetItemString(g_ns, name, l) != 0) {
    Py_DECREF(l);
    respond_python_error(SD_PyErr_NamSpcErr);
    return;
  }
  Py_DECREF(l);
  respond(0, "", 0);
}

/* Resolve a named object and check its type.  Returns a borrowed reference, or
 * NULL having already responded with the right error. */
static PyObject* need(const char* name, const char* type_name, int wrong_type_err) {
  PyObject* obj;
  int is;
  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return NULL; }
  obj = lookup(name);
  if (obj == NULL) { respond_str(SD_PyErr_ObjNOF, ""); return NULL; }
  if (type_name == NULL) return obj;
  is = is_instance_of(obj, type_name);
  if (is < 0) { respond_python_error(SD_PyEr_Excpt); return NULL; }
  if (is == 0) { respond_str(wrong_type_err, ""); return NULL; }
  return obj;
}

static void verb_dictclr(const char* name) {
  PyObject* d = need(name, "dict", SD_PyErr_NotDict);
  PyObject* r;
  if (d == NULL) return;
  r = PyObject_CallMethod(d, "clear", NULL);
  if (r == NULL) { respond_python_error(SD_PyEr_Excpt); return; }
  Py_DECREF(r);
  respond(0, "", 0);
}

static void verb_dictkeys(const char* name) {
  PyObject* d = need(name, "dict", SD_PyErr_NotDict);
  PyObject* keys;
  if (d == NULL) return;
  keys = PyDict_Keys(d);
  if (keys == NULL) { respond_python_error(SD_PyEr_Excpt); return; }
  respond_joined(keys);
  Py_DECREF(keys);
}

static void verb_dictvalues(const char* name) {
  PyObject* d = need(name, "dict", SD_PyErr_NotDict);
  PyObject* vals;
  if (d == NULL) return;
  vals = PyDict_Values(d);
  if (vals == NULL) { respond_python_error(SD_PyEr_Excpt); return; }
  respond_joined(vals);
  Py_DECREF(vals);
}

static void verb_dictvset(const char* name, const char* key, size_t keylen,
                          const char* value, size_t vallen) {
  PyObject* d = need(name, "dict", SD_PyErr_NotDict);
  PyObject* k;
  PyObject* v;
  int rc;
  if (d == NULL) return;
  k = sd_bytes_to_str(key, keylen);
  v = sd_bytes_to_str(value, vallen);
  if (k == NULL || v == NULL) {
    Py_XDECREF(k); Py_XDECREF(v);
    respond_python_error(SD_PyErr_EnLatin);
    return;
  }
  rc = PyDict_SetItem(d, k, v);
  Py_DECREF(k); Py_DECREF(v);
  if (rc != 0) { respond_python_error(SD_PyErr_DictSet); return; }
  respond(0, "", 0);
}

static void verb_dictvget(const char* name, const char* key, size_t keylen) {
  PyObject* d = need(name, "dict", SD_PyErr_NotDict);
  PyObject* k;
  PyObject* v;
  PyObject* s;
  PyObject* enc;
  if (d == NULL) return;
  k = sd_bytes_to_str(key, keylen);
  if (k == NULL) { respond_python_error(SD_PyErr_EnLatin); return; }
  v = PyObject_GetItem(d, k);
  Py_DECREF(k);
  if (v == NULL) { PyErr_Clear(); respond_str(SD_PyEr_Key, ""); return; }
  s = PyObject_Str(v);
  Py_DECREF(v);
  if (s == NULL) { respond_python_error(SD_PyEr_ObToStr); return; }
  enc = PyUnicode_AsEncodedString(s, "latin-1", "strict");
  Py_DECREF(s);
  if (enc == NULL) { PyErr_Clear(); respond_str(SD_PyErr_UniToStr, ""); return; }
  respond(0, PyBytes_AsString(enc), (size_t)PyBytes_Size(enc));
  Py_DECREF(enc);
}

static void verb_dictidel(const char* name, const char* key, size_t keylen) {
  PyObject* d = need(name, "dict", SD_PyErr_NotDict);
  PyObject* k;
  int rc;
  if (d == NULL) return;
  k = sd_bytes_to_str(key, keylen);
  if (k == NULL) { respond_python_error(SD_PyErr_EnLatin); return; }
  if (PyObject_GetItem(d, k) == NULL) {
    PyErr_Clear();
    Py_DECREF(k);
    respond_str(SD_PyEr_Key, "");          /* absent is -12007, not -12016 */
    return;
  }
  rc = PyObject_DelItem(d, k);
  Py_DECREF(k);
  if (rc != 0) { respond_python_error(SD_PyErr_DictDel); return; }
  respond(0, "", 0);
}

static void verb_listappd(const char* name, const char* objname) {
  PyObject* l = need(name, "list", SD_PyErr_NotList);
  PyObject* item;
  if (l == NULL) return;
  /* APPENDS A NAMED OBJECT, not a literal - that is the old signature,
   * SDPYOBJ("", objname, listname, SD_PyListAppd). */
  item = lookup(objname);
  if (item == NULL) { respond_str(SD_PyErr_ObjNOF, ""); return; }
  if (PyList_Append(l, item) != 0) { respond_python_error(SD_PyErr_LstItem); return; }
  respond(0, "", 0);
}

static void verb_listclr(const char* name) {
  PyObject* l = need(name, "list", SD_PyErr_NotList);
  PyObject* r;
  if (l == NULL) return;
  r = PyObject_CallMethod(l, "clear", NULL);
  if (r == NULL) { respond_python_error(SD_PyEr_Excpt); return; }
  Py_DECREF(r);
  respond(0, "", 0);
}

static void verb_listget(const char* name) {
  PyObject* l = need(name, "list", SD_PyErr_NotList);
  if (l == NULL) return;
  respond_joined(l);
}

static void verb_delobj(const char* name) {
  if (!Py_IsInitialized()) { respond_str(SD_PyEr_NotInit, ""); return; }
  if (lookup(name) == NULL) { respond_str(SD_PyErr_ObjNOF, ""); return; }
  if (PyDict_DelItemString(g_ns, name) != 0) {
    respond_python_error(SD_PyErr_DelObj);
    return;
  }
  respond(0, "", 0);
}

/* -------------------------------------------------------------------- main */

int main(void) {
  char header[128];

  /* Binary on both channels: a payload may contain \n, and Windows text mode
   * would rewrite it on the way out and mis-count it on the way in. */
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
  setvbuf(stdout, NULL, _IOFBF, 65536);

  /* ***REFUSE A TERMINAL.***  This is spoken to by SD over a pipe.  Started by
   * hand it would be a Python shell holding whatever rights its parent had,
   * which is not a thing to leave lying about even though the real gate is
   * SD-side (section 8, constraint 4). */
  if (_isatty(_fileno(stdin))) {
    fprintf(stderr, "sdpy: refusing to run on a terminal - it is driven by SD over a pipe.\n");
    return 2;
  }

  for (;;) {
    char verb[32];
    long n1, n2, n3;
    char* a1;
    char* a2;
    char* a3;
    int nread;

    if (fgets(header, (int)sizeof(header), stdin) == NULL)
      break;                                  /* parent closed the pipe */

    verb[0] = '\0';
    n1 = n2 = n3 = 0;
    nread = sscanf(header, "%31s %ld %ld %ld", verb, &n1, &n2, &n3);
    if (nread < 1) {
      respond_str(1, "malformed request header");
      continue;
    }
    if (n1 < 0 || n2 < 0 || n3 < 0 ||
        n1 > MAX_PAYLOAD || n2 > MAX_PAYLOAD || n3 > MAX_PAYLOAD) {
      respond_str(1, "payload length out of range");
      return 1;                               /* the stream is not trustworthy */
    }

    a1 = (char*)calloc((size_t)n1 + 1, 1);
    a2 = (char*)calloc((size_t)n2 + 1, 1);
    a3 = (char*)calloc((size_t)n3 + 1, 1);
    if (a1 == NULL || a2 == NULL || a3 == NULL) {
      free(a1); free(a2); free(a3);
      respond_str(1, "out of memory");
      return 1;
    }
    if ((n1 && !read_exact(a1, (size_t)n1)) ||
        (n2 && !read_exact(a2, (size_t)n2)) ||
        (n3 && !read_exact(a3, (size_t)n3))) {
      free(a1); free(a2); free(a3);
      return 1;                               /* truncated frame */
    }

    /* ***HELLO FIRST, AND IT MUST AGREE.***  A stale helper left on a machine
     * must not quietly answer a newer SD. */
    if (strcmp(verb, "HELLO") == 0) {
      if (strcmp(a1, SDPY_PROTOCOL) != 0) {
        respond_str(1, "protocol mismatch: this helper speaks " SDPY_PROTOCOL);
        free(a1); free(a2); free(a3);
        return 1;
      }
      g_hello = 1;
      respond_str(0, SDPY_PROTOCOL);
    } else if (!g_hello) {
      respond_str(1, "HELLO expected first");
    } else if (strcmp(verb, "PING") == 0) {
      respond_str(0, "PONG");
    } else if (strcmp(verb, "QUIT") == 0) {
      respond(0, "", 0);
      free(a1); free(a2); free(a3);
      break;
    } else if (strcmp(verb, "INIT") == 0) {
      if (Py_IsInitialized()) {
        respond_str(0, "");                   /* already up: not an error */
      } else if (start_interpreter()) {
        respond_str(0, Py_GetVersion());
      } else {
        stop_interpreter();
        respond_str(SD_PyEr_Dict, "interpreter did not start");
      }
    } else if (strcmp(verb, "ISINIT") == 0) {
      respond_str(0, Py_IsInitialized() ? "1" : "0");
    } else if (strcmp(verb, "FIN") == 0) {
      stop_interpreter();
      respond(0, "", 0);
    } else if (strcmp(verb, "RUNSTR") == 0) {
      verb_runstr(a1, (size_t)n1);
    } else if (strcmp(verb, "STRSET") == 0) {
      verb_strset(a3, a1, (size_t)n1);        /* SDPYOBJ order: value, key, name */
    } else if (strcmp(verb, "STRGET") == 0) {
      verb_strget(a3);
    } else if (strcmp(verb, "OBJTYPE") == 0) {
      verb_objtype(a3);
    } else if (strcmp(verb, "OBJLEN") == 0) {
      verb_objlen(a3);
    } else if (strcmp(verb, "DELOBJ") == 0) {
      verb_delobj(a3);
    /* The dict and list families.  Argument order is the old SDPYOBJ one:
     * a1 = value, a2 = key or object name, a3 = the named collection. */
    } else if (strcmp(verb, "DICTCRTE") == 0) {
      verb_dictcrte(a3);
    } else if (strcmp(verb, "DICTCLR") == 0) {
      verb_dictclr(a3);
    } else if (strcmp(verb, "DICTKEYS") == 0) {
      verb_dictkeys(a3);
    } else if (strcmp(verb, "DICTVALUES") == 0) {
      verb_dictvalues(a3);
    } else if (strcmp(verb, "DICTVSET") == 0) {
      verb_dictvset(a3, a2, (size_t)n2, a1, (size_t)n1);
    } else if (strcmp(verb, "DICTVGET") == 0) {
      verb_dictvget(a3, a2, (size_t)n2);
    } else if (strcmp(verb, "DICTIDEL") == 0) {
      verb_dictidel(a3, a2, (size_t)n2);
    } else if (strcmp(verb, "LISTCRTE") == 0) {
      verb_listcrte(a3);
    } else if (strcmp(verb, "LISTAPPD") == 0) {
      verb_listappd(a3, a2);
    } else if (strcmp(verb, "LISTCLR") == 0) {
      verb_listclr(a3);
    } else if (strcmp(verb, "LISTGET") == 0) {
      verb_listget(a3);
    } else {
      respond_str(1, "unknown verb");
    }

    free(a1); free(a2); free(a3);
  }

  stop_interpreter();
  return 0;
}
