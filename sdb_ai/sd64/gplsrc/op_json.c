/* OP_JSON.C
 * JSON beyond JPARSE() and JBUILD(): merge (RFC 7396), patch (RFC 6902), path queries (JSONPath, RFC 9535) and validation (JSON Schema)
 * Copyright (c) 2026 SD Core for Linux
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
 * 20 Oct 26 dm  New.  The owner's CSV / JSON / XML task.  JMERGE(), JPATCH(), JPATH() and JVALIDATE(), each on data collections (or on JSON
 *               text, which is parsed first), all through OP.XFUN (XF_JMERGE ... XF_JVALIDATE).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *    JMERGE(target, patch)     RFC 7396: the merge patch applied to a copy of the target.  A name in the patch whose value is a JSON null
 *                              takes the name out of the target; an object merges; anything else replaces.  The target is not changed.
 *    JPATCH(c, ops)            RFC 6902: ops is an array of {"op": add | remove | replace | move | copy | test, "path": "/a/0/b", "from":,
 *                              "value":} applied in order to a copy of c.  A path is a JSON Pointer (RFC 6901), so an array's elements are
 *                              numbered from 0 and "-" is the place after the last.  All or nothing: a null string, STATUS() 1023 and INMAT()
 *                              the number (from 1) of the operation that failed.
 *    JPATH(c, query)           JSONPath (RFC 9535): $ . .. [ ] names, * wildcard, indexes from 0 (negative from the end), slices,
 *                              unions, and filters [?@.price < 10 && @.tag == 'x'] with == != < <= > >=, && || !, tests of existence,
 *                              and the functions length(), count(), match() and search().  The matches, copied, as an array.  A query that
 *                              is not well formed: a null string, STATUS() 1024 and INMAT() the place it went wrong.
 *    JVALIDATE(c, schema)      JSON Schema (2020-12, the keywords listed in v_check): an array of the faults found, each {path, keyword,
 *                              message}; an empty array is a valid document.  $ref reaches into the same schema only.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <regex.h>
#include <string.h>
#include "sd.h"
#include "header.h"
#include "err.h"
#include "keys.h"

#define JTAG 163
#define J_MAX_DEPTH 200
#define J_MAX_ERRORS 100

typedef enum { JK_NULL, JK_BOOL, JK_INT, JK_FLOAT, JK_STRING, JK_OBJECT, JK_ARRAY } JKIND;

/* A small growing buffer */
typedef struct {
  char* b;
  int32_t len;
  int32_t cap;
} JB;

Private void jb_init(JB* f) {
  f->cap = 128;
  f->len = 0;
  f->b = (char*)k_alloc(JTAG, f->cap);
  f->b[0] = '\0';
}

Private void jb_add(JB* f, const char* s, int32_t n) {
  if (f->len + n + 1 > f->cap) {
    int32_t nc = f->cap * 2;
    char* nb;

    while (nc < f->len + n + 1)
      nc *= 2;
    nb = (char*)k_alloc(JTAG, nc);
    memcpy(nb, f->b, f->len);
    k_free(f->b);
    f->b = nb;
    f->cap = nc;
  }
  memcpy(f->b + f->len, s, n);
  f->len += n;
  f->b[f->len] = '\0';
}

Private void jb_free(JB* f) {
  if (f->b != NULL)
    k_free(f->b);
  f->b = NULL;
}

/* ----------------------------------------------------------------------
   Values                                                                 */

Private JKIND jkind(COLL_ENTRY* e) {
  if (e->tag == CT_NULL)
    return JK_NULL;
  if (e->tag == CT_BOOL)
    return JK_BOOL;
  switch (e->d.type) {
    case INTEGER:
      return JK_INT;
    case FLOATNUM:
      return JK_FLOAT;
    case COLL:
      return e->d.data.coll->is_array ? JK_ARRAY : JK_OBJECT;
    default:
      return JK_STRING;
  }
}

Private double jnum(COLL_ENTRY* e) {
  return (e->d.type == INTEGER) ? (double)e->d.data.value : e->d.data.float_value;
}

/* The bytes of a string value, in a buffer the caller frees */
Private char* jstr(COLL_ENTRY* e, int32_t* len) {
  if (e->d.type != STRING) {
    *len = 0;
    return (char*)k_alloc(JTAG, 1);
  }
  return coll_chunks_to_buffer(e->d.data.str.saddr, len);
}

Private COLL_ENTRY* new_null_entry(COLL_ENTRY* e) {
  memset(e, 0, sizeof *e);
  InitDescr(&e->d, STRING);
  e->d.data.str.saddr = NULL;
  return e;
}

/* dst becomes a copy of src (its name is not touched).  What dst held is let go. */
Private void jcopy(COLL_ENTRY* dst, COLL_ENTRY* src) {
  k_release(&dst->d);
  dst->tag = src->tag;
  if (src->d.type == COLL) {
    InitDescr(&dst->d, COLL);
    dst->d.data.coll = coll_copy(src->d.data.coll);
  } else {
    dst->d = src->d;
    dst->d.flags = 0;
    IncrRefCt(&dst->d);
  }
}

Private void jrelease(COLL_ENTRY* e) {
  k_release(&e->d);
  new_null_entry(e);
}

/* Deep equality in the JSON sense: 1 and 1.0 are the same number, true is not 1, null is not an empty string */
Private bool jeq(COLL_ENTRY* a, COLL_ENTRY* b) {
  JKIND ka = jkind(a), kb = jkind(b);
  int32_t i;

  if ((ka == JK_INT || ka == JK_FLOAT) && (kb == JK_INT || kb == JK_FLOAT))
    return jnum(a) == jnum(b);
  if (ka != kb)
    return FALSE;
  switch (ka) {
    case JK_NULL:
      return TRUE;
    case JK_BOOL:
      return a->d.data.value == b->d.data.value;
    case JK_STRING: {
      int32_t la, lb;
      char* sa = jstr(a, &la);
      char* sb = jstr(b, &lb);
      bool same = (la == lb && memcmp(sa, sb, la) == 0);

      k_free(sa);
      k_free(sb);
      return same;
    }
    case JK_ARRAY:
    case JK_OBJECT: {
      COLL_HEADER* ha = a->d.data.coll;
      COLL_HEADER* hb = b->d.data.coll;

      if (ha->count != hb->count)
        return FALSE;
      for (i = 0; i < ha->count; i++) {
        if (ka == JK_OBJECT && (ha->e[i].name_len != hb->e[i].name_len || memcmp(ha->e[i].name, hb->e[i].name, ha->e[i].name_len) != 0))
          return FALSE;
        if (!jeq(&ha->e[i], &hb->e[i]))
          return FALSE;
      }
      return TRUE;
    }
    default:
      return FALSE;
  }
}

/* A named place in an object; a new one is a null string */
Private COLL_ENTRY* jobj_slot(COLL_HEADER* h, const char* name, int32_t len) {
  int32_t pos;
  COLL_ENTRY* e;

  if (coll_find(h, (char*)name, len, &pos)) {
    e = &h->e[pos];
    jrelease(e);
    return e;
  }
  coll_insert(h, pos);
  e = &h->e[pos];
  e->name = (char*)k_alloc(JTAG, len + 1);
  memcpy(e->name, name, len);
  e->name[len] = '\0';
  e->name_len = len;
  return e;
}

Private COLL_ENTRY* jarr_slot(COLL_HEADER* h, int32_t pos) {
  coll_insert(h, pos);
  return &h->e[pos];
}

Private void set_str(COLL_ENTRY* e, const char* s, int32_t len) {
  k_release(&e->d);
  e->d = coll_str_descr((char*)s, len);
  e->tag = CT_PLAIN;
}

Private void set_coll(COLL_ENTRY* e, COLL_HEADER* h) {
  k_release(&e->d);
  InitDescr(&e->d, COLL);
  e->d.data.coll = h;
  e->tag = CT_PLAIN;
}

/* ----------------------------------------------------------------------
   An argument: a data collection, or JSON text that is parsed to one      */

typedef struct {
  COLL_ENTRY e; /* a view of the collection: a reference is NOT taken for a collection that was given */
  bool owned;   /* parsed here; to be released */
} JARG;

Private bool jarg_get(DESCRIPTOR* d, JARG* a) {
  DESCRIPTOR* v = d;
  char* text;
  int32_t tlen;
  DESCRIPTOR parsed;

  while (v->type == ADDR)
    v = v->data.d_addr;
  memset(a, 0, sizeof *a);
  new_null_entry(&a->e);
  if (v->type == COLL) {
    InitDescr(&a->e.d, COLL);
    a->e.d.data.coll = v->data.coll;
    a->owned = FALSE;
    return TRUE;
  }
  k_get_string(v);
  text = coll_chunks_to_buffer(v->data.str.saddr, &tlen);
  parsed = coll_json_parse(text, tlen, 0);
  k_free(text);
  if (parsed.type != COLL)
    return FALSE; /* process.status is ER_PARSE_ERROR */
  a->e.d = parsed;
  a->owned = TRUE;
  return TRUE;
}

Private void jarg_free(JARG* a) {
  if (a->owned)
    k_release(&a->e.d);
}

Private void push_null(void) {
  DESCRIPTOR r;

  InitDescr(&r, STRING);
  r.data.str.saddr = NULL;
  *(e_stack++) = r;
}

/* ======================================================================
   JMERGE()  -  RFC 7396                                                  */

Private void merge_into(COLL_ENTRY* target, COLL_ENTRY* patch, int depth) {
  COLL_HEADER* th;
  COLL_HEADER* ph;
  int32_t i, pos;

  if (jkind(patch) != JK_OBJECT || depth > J_MAX_DEPTH) {
    jcopy(target, patch);
    return;
  }
  if (jkind(target) != JK_OBJECT) {
    k_release(&target->d);
    set_coll(target, coll_new(FALSE));
  }
  th = target->d.data.coll;
  ph = patch->d.data.coll;
  for (i = 0; i < ph->count; i++) {
    COLL_ENTRY* pe = &ph->e[i];

    if (pe->tag == CT_NULL) {
      if (coll_find(th, pe->name, pe->name_len, &pos))
        coll_remove(th, pos);
    } else {
      COLL_ENTRY* te;

      if (coll_find(th, pe->name, pe->name_len, &pos)) {
        te = &th->e[pos];
      } else {
        te = jobj_slot(th, pe->name, pe->name_len);
      }
      merge_into(te, pe, depth + 1);
    }
  }
}

void x_jmerge() {
  JARG t, p;
  COLL_ENTRY root;
  DESCRIPTOR result;

  process.status = 0;
  if (!jarg_get(e_stack - 2, &t)) {
    k_dismiss();
    k_dismiss();
    push_null();
    return;
  }
  if (!jarg_get(e_stack - 1, &p)) {
    jarg_free(&t);
    k_dismiss();
    k_dismiss();
    push_null();
    return;
  }
  new_null_entry(&root);
  jcopy(&root, &t.e);
  merge_into(&root, &p.e, 0);
  result = root.d;
  jarg_free(&t);
  jarg_free(&p);
  k_dismiss();
  k_dismiss();
  *(e_stack++) = result;
}

/* ======================================================================
   JPATCH()  -  RFC 6902 with JSON Pointers (RFC 6901)                    */

typedef struct {
  char** tok;
  int32_t* len;
  int n;
} PTR;

Private void ptr_free(PTR* p) {
  int i;

  for (i = 0; i < p->n; i++)
    k_free(p->tok[i]);
  if (p->tok != NULL)
    k_free(p->tok);
  if (p->len != NULL)
    k_free(p->len);
  p->tok = NULL;
  p->len = NULL;
  p->n = 0;
}

/* A pointer: "" is the whole document, otherwise /token/token with ~1 for a slash and ~0 for a tilde */
Private bool ptr_parse(const char* s, int32_t len, PTR* p) {
  int32_t i, start;
  int n = 0;

  p->tok = NULL;
  p->len = NULL;
  p->n = 0;
  if (len == 0)
    return TRUE;
  if (s[0] != '/')
    return FALSE;
  for (i = 0; i < len; i++)
    if (s[i] == '/')
      n++;
  p->tok = (char**)k_alloc(JTAG, n * sizeof(char*));
  p->len = (int32_t*)k_alloc(JTAG, n * sizeof(int32_t));
  start = 1;
  for (i = 1; i <= len; i++) {
    if (i == len || s[i] == '/') {
      char* t = (char*)k_alloc(JTAG, i - start + 1);
      int32_t k = 0, j;

      for (j = start; j < i; j++) {
        if (s[j] == '~' && j + 1 < i && s[j + 1] == '1') {
          t[k++] = '/';
          j++;
        } else if (s[j] == '~' && j + 1 < i && s[j + 1] == '0') {
          t[k++] = '~';
          j++;
        } else if (s[j] == '~') {
          k_free(t);
          ptr_free(p);
          return FALSE;
        } else {
          t[k++] = s[j];
        }
      }
      t[k] = '\0';
      p->tok[p->n] = t;
      p->len[p->n] = k;
      p->n++;
      start = i + 1;
    }
  }
  return TRUE;
}

/* An array index token: digits, no leading zero unless it is 0.  -1 if it is not one. */
Private int32_t ptr_index(const char* t, int32_t len) {
  int32_t i, v = 0;

  if (len < 1 || len > 9 || (len > 1 && t[0] == '0'))
    return -1;
  for (i = 0; i < len; i++) {
    if (t[i] < '0' || t[i] > '9')
      return -1;
    v = v * 10 + (t[i] - '0');
  }
  return v;
}

/* The entry a pointer names, or NULL */
Private COLL_ENTRY* ptr_get(COLL_ENTRY* root, PTR* p, int upto) {
  COLL_ENTRY* cur = root;
  int i;

  for (i = 0; i < upto; i++) {
    JKIND k = jkind(cur);
    COLL_HEADER* h;
    int32_t pos;

    if (k == JK_OBJECT) {
      h = cur->d.data.coll;
      if (!coll_find(h, p->tok[i], p->len[i], &pos))
        return NULL;
      cur = &h->e[pos];
    } else if (k == JK_ARRAY) {
      h = cur->d.data.coll;
      pos = ptr_index(p->tok[i], p->len[i]);
      if (pos < 0 || pos >= h->count)
        return NULL;
      cur = &h->e[pos];
    } else {
      return NULL;
    }
  }
  return cur;
}

/* add: put a copy of val at the place the pointer names */
Private bool patch_add(COLL_ENTRY* root, PTR* p, COLL_ENTRY* val) {
  COLL_ENTRY* parent;
  COLL_HEADER* h;
  JKIND k;
  int32_t pos;

  if (p->n == 0) {
    jcopy(root, val);
    return TRUE;
  }
  parent = ptr_get(root, p, p->n - 1);
  if (parent == NULL)
    return FALSE;
  k = jkind(parent);
  h = parent->d.data.coll;
  if (k == JK_OBJECT) {
    COLL_ENTRY* e = jobj_slot(h, p->tok[p->n - 1], p->len[p->n - 1]);

    jcopy(e, val);
    return TRUE;
  }
  if (k == JK_ARRAY) {
    COLL_ENTRY* e;

    if (p->len[p->n - 1] == 1 && p->tok[p->n - 1][0] == '-') {
      pos = h->count;
    } else {
      pos = ptr_index(p->tok[p->n - 1], p->len[p->n - 1]);
      if (pos < 0 || pos > h->count)
        return FALSE;
    }
    e = jarr_slot(h, pos);
    jcopy(e, val);
    return TRUE;
  }
  return FALSE;
}

Private bool patch_remove(COLL_ENTRY* root, PTR* p) {
  COLL_ENTRY* parent;
  COLL_HEADER* h;
  int32_t pos;

  if (p->n == 0)
    return FALSE;
  parent = ptr_get(root, p, p->n - 1);
  if (parent == NULL)
    return FALSE;
  if (jkind(parent) == JK_OBJECT) {
    h = parent->d.data.coll;
    if (!coll_find(h, p->tok[p->n - 1], p->len[p->n - 1], &pos))
      return FALSE;
    coll_remove(h, pos);
    return TRUE;
  }
  if (jkind(parent) == JK_ARRAY) {
    h = parent->d.data.coll;
    pos = ptr_index(p->tok[p->n - 1], p->len[p->n - 1]);
    if (pos < 0 || pos >= h->count)
      return FALSE;
    coll_remove(h, pos);
    return TRUE;
  }
  return FALSE;
}

/* The text of an operation's member as a pointer; false if it is missing or not a string */
Private bool op_ptr(COLL_HEADER* op, const char* key, PTR* p) {
  int32_t pos, len;
  char* s;
  bool ok;

  if (!coll_find(op, (char*)key, (int32_t)strlen(key), &pos) || jkind(&op->e[pos]) != JK_STRING)
    return FALSE;
  s = jstr(&op->e[pos], &len);
  ok = ptr_parse(s, len, p);
  k_free(s);
  return ok;
}

Private COLL_ENTRY* op_member(COLL_HEADER* op, const char* key) {
  int32_t pos;

  return coll_find(op, (char*)key, (int32_t)strlen(key), &pos) ? &op->e[pos] : NULL;
}

/* One operation: 0 done, otherwise it failed */
Private int patch_one(COLL_ENTRY* root, COLL_ENTRY* opent) {
  COLL_HEADER* op;
  COLL_ENTRY* oe;
  COLL_ENTRY* val;
  PTR path, from;
  char* ops;
  int32_t oplen;
  int rc = 1;

  if (jkind(opent) != JK_OBJECT)
    return 1;
  op = opent->d.data.coll;
  oe = op_member(op, "op");
  if (oe == NULL || jkind(oe) != JK_STRING)
    return 1;
  if (!op_ptr(op, "path", &path))
    return 1;
  ops = jstr(oe, &oplen);
  val = op_member(op, "value");

  if (oplen == 3 && memcmp(ops, "add", 3) == 0) {
    if (val != NULL && patch_add(root, &path, val))
      rc = 0;
  } else if (oplen == 6 && memcmp(ops, "remove", 6) == 0) {
    if (patch_remove(root, &path))
      rc = 0;
  } else if (oplen == 7 && memcmp(ops, "replace", 7) == 0) {
    COLL_ENTRY* target;

    if (val != NULL) {
      if (path.n == 0) {
        jcopy(root, val);
        rc = 0;
      } else if ((target = ptr_get(root, &path, path.n)) != NULL) {
        jcopy(target, val);
        rc = 0;
      }
    }
  } else if (oplen == 4 && memcmp(ops, "test", 4) == 0) {
    COLL_ENTRY* target = ptr_get(root, &path, path.n);

    if (target != NULL && val != NULL && jeq(target, val))
      rc = 0;
  } else if ((oplen == 4 && memcmp(ops, "move", 4) == 0) || (oplen == 4 && memcmp(ops, "copy", 4) == 0)) {
    if (op_ptr(op, "from", &from)) {
      COLL_ENTRY* src = ptr_get(root, &from, from.n);

      if (src != NULL) {
        bool is_move = (ops[0] == 'm');
        bool prefix = FALSE;

        /* a location cannot be moved into one of its own children */
        if (is_move && from.n < path.n) {
          int i;

          prefix = TRUE;
          for (i = 0; i < from.n; i++)
            if (from.len[i] != path.len[i] || memcmp(from.tok[i], path.tok[i], from.len[i]) != 0)
              prefix = FALSE;
        }
        if (!prefix) {
          COLL_ENTRY tmp;

          new_null_entry(&tmp);
          jcopy(&tmp, src);
          if (is_move && !patch_remove(root, &from)) {
            /* the source was the root: nothing to remove it from */
          } else if (patch_add(root, &path, &tmp)) {
            rc = 0;
          }
          k_release(&tmp.d);
        }
      }
      ptr_free(&from);
    }
  }
  k_free(ops);
  ptr_free(&path);
  return rc;
}

void x_jpatch() {
  JARG c, ops;
  COLL_ENTRY root;
  COLL_HEADER* oh;
  int32_t i;
  DESCRIPTOR result;
  int32_t failed = 0;

  process.status = 0;
  if (!jarg_get(e_stack - 2, &c)) {
    k_dismiss();
    k_dismiss();
    push_null();
    return;
  }
  if (!jarg_get(e_stack - 1, &ops) || jkind(&ops.e) != JK_ARRAY) {
    if (process.status == 0)
      process.status = ER_PATCH_ERROR;
    jarg_free(&c);
    k_dismiss();
    k_dismiss();
    push_null();
    return;
  }
  new_null_entry(&root);
  jcopy(&root, &c.e);
  oh = ops.e.d.data.coll;
  for (i = 0; i < oh->count; i++) {
    if (patch_one(&root, &oh->e[i]) != 0) {
      failed = i + 1;
      break;
    }
  }
  if (failed) {
    k_release(&root.d);
    process.status = ER_PATCH_ERROR;
    process.inmat = failed;
    result = coll_str_descr(NULL, 0);
  } else {
    result = root.d;
  }
  jarg_free(&c);
  jarg_free(&ops);
  k_dismiss();
  k_dismiss();
  *(e_stack++) = result;
}

/* ======================================================================
   JPATH()  -  JSONPath

   The query is read into a list of segments, each with a list of selectors, and a filter into a tree of tests; both are walked over
   the document.  An entry the walk finds is a pointer into the document, which is not changed while the query runs.            */

typedef struct JEXPR JEXPR;
typedef struct JSEG JSEG;

typedef enum { SEL_NAME, SEL_INDEX, SEL_SLICE, SEL_WILD, SEL_FILTER } SELTYPE;

typedef struct {
  SELTYPE type;
  char* name;
  int32_t name_len;
  int32_t index;
  int32_t start, end, step;
  bool has_start, has_end;
  JEXPR* filter;
} JSEL;

struct JSEG {
  bool descendant;
  JSEL* sel;
  int nsel;
};

typedef struct {
  JSEG* seg;
  int nseg;
  bool absolute; /* $ or @ */
} JQUERY;

typedef enum { EX_OR, EX_AND, EX_NOT, EX_CMP, EX_TEST, EX_LIT, EX_QUERY, EX_FUNC } EXTYPE;

struct JEXPR {
  EXTYPE type;
  JEXPR* a;
  JEXPR* b;
  int op; /* EX_CMP: 1 == 2 != 3 < 4 <= 5 > 6 >= */
  JQUERY q;
  /* a literal */
  int lit; /* 1 null 2 bool 3 number 4 string */
  int boolean;
  double num;
  char* str;
  int32_t slen;
  /* a function */
  char fname[16];
  JEXPR* args[2];
  int nargs;
};

typedef struct {
  const char* s;
  int32_t n;
  int32_t pos;
  int32_t err;
  int depth;
} JPARSEQ;

Private void q_free(JQUERY* q);

Private void ex_free(JEXPR* e) {
  if (e == NULL)
    return;
  ex_free(e->a);
  ex_free(e->b);
  ex_free(e->args[0]);
  ex_free(e->args[1]);
  q_free(&e->q);
  if (e->str != NULL)
    k_free(e->str);
  k_free(e);
}

Private void q_free(JQUERY* q) {
  int i, j;

  for (i = 0; i < q->nseg; i++) {
    for (j = 0; j < q->seg[i].nsel; j++) {
      if (q->seg[i].sel[j].name != NULL)
        k_free(q->seg[i].sel[j].name);
      ex_free(q->seg[i].sel[j].filter);
    }
    if (q->seg[i].sel != NULL)
      k_free(q->seg[i].sel);
  }
  if (q->seg != NULL)
    k_free(q->seg);
  q->seg = NULL;
  q->nseg = 0;
}

Private JEXPR* ex_new(EXTYPE t) {
  JEXPR* e = (JEXPR*)k_alloc(JTAG, sizeof(JEXPR));

  memset(e, 0, sizeof *e);
  e->type = t;
  return e;
}

Private void qp_ws(JPARSEQ* p) {
  while (p->pos < p->n && (p->s[p->pos] == ' ' || p->s[p->pos] == '\t' || p->s[p->pos] == '\n' || p->s[p->pos] == '\r'))
    p->pos++;
}

Private bool qp_fail(JPARSEQ* p) {
  if (p->err == 0)
    p->err = p->pos + 1;
  return FALSE;
}

/* A quoted string, ' or ", with the usual escapes; the caller frees *out */
Private bool qp_string(JPARSEQ* p, char** out, int32_t* outlen) {
  char q = p->s[p->pos];
  JB b;

  p->pos++;
  jb_init(&b);
  while (p->pos < p->n && p->s[p->pos] != q) {
    char c = p->s[p->pos];

    if (c == '\\' && p->pos + 1 < p->n) {
      char d = p->s[p->pos + 1];

      p->pos += 2;
      switch (d) {
        case 'n':
          jb_add(&b, "\n", 1);
          break;
        case 't':
          jb_add(&b, "\t", 1);
          break;
        case 'r':
          jb_add(&b, "\r", 1);
          break;
        case 'b':
          jb_add(&b, "\b", 1);
          break;
        case 'f':
          jb_add(&b, "\f", 1);
          break;
        case 'u': {
          int v = 0, k;

          for (k = 0; k < 4 && p->pos < p->n; k++, p->pos++) {
            char h = p->s[p->pos];

            v <<= 4;
            if (h >= '0' && h <= '9')
              v |= h - '0';
            else if (h >= 'a' && h <= 'f')
              v |= h - 'a' + 10;
            else if (h >= 'A' && h <= 'F')
              v |= h - 'A' + 10;
            else {
              jb_free(&b);
              return qp_fail(p);
            }
          }
          {
            char ch = (char)(v & 0xFF); /* a byte, as JPARSE() reads \u00XX */

            jb_add(&b, &ch, 1);
          }
          break;
        }
        default:
          jb_add(&b, &d, 1);
          break;
      }
    } else {
      jb_add(&b, &c, 1);
      p->pos++;
    }
  }
  if (p->pos >= p->n) {
    jb_free(&b);
    return qp_fail(p);
  }
  p->pos++;
  *out = b.b;
  *outlen = b.len;
  return TRUE;
}

Private bool qp_int(JPARSEQ* p, int32_t* v) {
  int32_t i = p->pos;
  bool neg = FALSE;
  int64 acc = 0;

  if (i < p->n && p->s[i] == '-') {
    neg = TRUE;
    i++;
  }
  if (i >= p->n || p->s[i] < '0' || p->s[i] > '9')
    return FALSE;
  while (i < p->n && p->s[i] >= '0' && p->s[i] <= '9') {
    acc = acc * 10 + (p->s[i] - '0');
    if (acc > 2000000000)
      return FALSE;
    i++;
  }
  *v = (int32_t)(neg ? -acc : acc);
  p->pos = i;
  return TRUE;
}

Private bool qp_query(JPARSEQ* p, JQUERY* q, bool in_filter);
Private bool qp_or(JPARSEQ* p, JEXPR** out);

Private bool qp_name_char(char c, bool first) {
  return isalpha((unsigned char)c) || c == '_' || (unsigned char)c >= 0x80 || (!first && isdigit((unsigned char)c));
}

Private void seg_add(JQUERY* q, bool descendant, JSEL* sels, int nsel) {
  JSEG* ns = (JSEG*)k_alloc(JTAG, (q->nseg + 1) * sizeof(JSEG));

  if (q->nseg)
    memcpy(ns, q->seg, q->nseg * sizeof(JSEG));
  if (q->seg != NULL)
    k_free(q->seg);
  q->seg = ns;
  q->seg[q->nseg].descendant = descendant;
  q->seg[q->nseg].sel = sels;
  q->seg[q->nseg].nsel = nsel;
  q->nseg++;
}

/* The selectors of one bracket [ ... ] */
Private bool qp_bracket(JPARSEQ* p, JSEL** out, int* nout) {
  JSEL* sels = NULL;
  int n = 0, cap = 0;

  p->pos++; /* the [ */
  for (;;) {
    JSEL s;

    memset(&s, 0, sizeof s);
    qp_ws(p);
    if (p->pos >= p->n)
      return qp_fail(p);
    if (p->s[p->pos] == '\'' || p->s[p->pos] == '"') {
      s.type = SEL_NAME;
      if (!qp_string(p, &s.name, &s.name_len))
        return FALSE;
    } else if (p->s[p->pos] == '*') {
      s.type = SEL_WILD;
      p->pos++;
    } else if (p->s[p->pos] == '?') {
      s.type = SEL_FILTER;
      p->pos++;
      if (++p->depth > 20 || !qp_or(p, &s.filter))
        return qp_fail(p);
      p->depth--;
    } else {
      int32_t v;
      int32_t save = p->pos;

      s.type = SEL_INDEX;
      s.step = 1;
      if (qp_int(p, &v)) {
        s.start = v;
        s.has_start = TRUE;
      }
      qp_ws(p);
      if (p->pos < p->n && p->s[p->pos] == ':') {
        s.type = SEL_SLICE;
        p->pos++;
        qp_ws(p);
        if (qp_int(p, &v)) {
          s.end = v;
          s.has_end = TRUE;
        }
        qp_ws(p);
        if (p->pos < p->n && p->s[p->pos] == ':') {
          p->pos++;
          qp_ws(p);
          if (qp_int(p, &v))
            s.step = v;
        }
      } else if (!s.has_start) {
        p->pos = save;
        return qp_fail(p);
      } else {
        s.index = s.start;
      }
    }
    if (n >= cap) {
      JSEL* ns = (JSEL*)k_alloc(JTAG, (cap ? cap * 2 : 4) * sizeof(JSEL));

      if (n)
        memcpy(ns, sels, n * sizeof(JSEL));
      if (sels != NULL)
        k_free(sels);
      sels = ns;
      cap = cap ? cap * 2 : 4;
    }
    sels[n++] = s;
    qp_ws(p);
    if (p->pos < p->n && p->s[p->pos] == ',') {
      p->pos++;
      continue;
    }
    if (p->pos < p->n && p->s[p->pos] == ']') {
      p->pos++;
      break;
    }
    return qp_fail(p);
  }
  *out = sels;
  *nout = n;
  return TRUE;
}

/* $ or @ and then the segments */
Private bool qp_query(JPARSEQ* p, JQUERY* q, bool in_filter) {
  memset(q, 0, sizeof *q);
  if (p->pos >= p->n || (p->s[p->pos] != '$' && p->s[p->pos] != '@'))
    return qp_fail(p);
  q->absolute = (p->s[p->pos] == '$');
  p->pos++;
  for (;;) {
    JSEL* sels = NULL;
    int nsel = 0;
    bool desc = FALSE;

    if (!in_filter)
      qp_ws(p);
    if (p->pos >= p->n)
      break;
    if (p->s[p->pos] == '.') {
      p->pos++;
      if (p->pos < p->n && p->s[p->pos] == '.') {
        desc = TRUE;
        p->pos++;
      }
      if (p->pos < p->n && p->s[p->pos] == '[') {
        if (!qp_bracket(p, &sels, &nsel))
          return FALSE;
      } else if (p->pos < p->n && p->s[p->pos] == '*') {
        sels = (JSEL*)k_alloc(JTAG, sizeof(JSEL));
        memset(sels, 0, sizeof(JSEL));
        sels[0].type = SEL_WILD;
        nsel = 1;
        p->pos++;
      } else if (p->pos < p->n && qp_name_char(p->s[p->pos], TRUE)) {
        int32_t st = p->pos;

        while (p->pos < p->n && qp_name_char(p->s[p->pos], FALSE))
          p->pos++;
        sels = (JSEL*)k_alloc(JTAG, sizeof(JSEL));
        memset(sels, 0, sizeof(JSEL));
        sels[0].type = SEL_NAME;
        sels[0].name_len = p->pos - st;
        sels[0].name = (char*)k_alloc(JTAG, sels[0].name_len + 1);
        memcpy(sels[0].name, p->s + st, sels[0].name_len);
        sels[0].name[sels[0].name_len] = '\0';
        nsel = 1;
      } else {
        return qp_fail(p);
      }
    } else if (p->s[p->pos] == '[') {
      if (!qp_bracket(p, &sels, &nsel))
        return FALSE;
    } else {
      break;
    }
    seg_add(q, desc, sels, nsel);
  }
  return TRUE;
}

/* ---- filter expressions ---- */

Private bool qp_comparable(JPARSEQ* p, JEXPR** out) {
  char c;
  JEXPR* e;

  qp_ws(p);
  if (p->pos >= p->n)
    return qp_fail(p);
  c = p->s[p->pos];
  if (c == '@' || c == '$') {
    e = ex_new(EX_QUERY);
    if (!qp_query(p, &e->q, TRUE)) {
      ex_free(e);
      return FALSE;
    }
    *out = e;
    return TRUE;
  }
  if (c == '\'' || c == '"') {
    e = ex_new(EX_LIT);
    e->lit = 4;
    if (!qp_string(p, &e->str, &e->slen)) {
      ex_free(e);
      return FALSE;
    }
    *out = e;
    return TRUE;
  }
  if (c == '-' || isdigit((unsigned char)c)) {
    bool is_int;
    int32_t n = coll_number_len((unsigned char*)p->s + p->pos, p->n - p->pos, &is_int);
    char tmp[64];

    if (n <= 0 || n > 60)
      return qp_fail(p);
    memcpy(tmp, p->s + p->pos, n);
    tmp[n] = '\0';
    e = ex_new(EX_LIT);
    e->lit = 3;
    e->num = strtod(tmp, NULL);
    p->pos += n;
    *out = e;
    return TRUE;
  }
  if (isalpha((unsigned char)c)) {
    int32_t st = p->pos;
    int32_t nl;

    while (p->pos < p->n && (isalnum((unsigned char)p->s[p->pos]) || p->s[p->pos] == '_'))
      p->pos++;
    nl = p->pos - st;
    if (nl == 4 && memcmp(p->s + st, "true", 4) == 0) {
      e = ex_new(EX_LIT);
      e->lit = 2;
      e->boolean = 1;
      *out = e;
      return TRUE;
    }
    if (nl == 5 && memcmp(p->s + st, "false", 5) == 0) {
      e = ex_new(EX_LIT);
      e->lit = 2;
      e->boolean = 0;
      *out = e;
      return TRUE;
    }
    if (nl == 4 && memcmp(p->s + st, "null", 4) == 0) {
      e = ex_new(EX_LIT);
      e->lit = 1;
      *out = e;
      return TRUE;
    }
    if (p->pos < p->n && p->s[p->pos] == '(' && nl < 15) {
      e = ex_new(EX_FUNC);
      memcpy(e->fname, p->s + st, nl);
      e->fname[nl] = '\0';
      p->pos++;
      qp_ws(p);
      if (p->pos < p->n && p->s[p->pos] != ')') {
        for (;;) {
          if (e->nargs >= 2 || !qp_comparable(p, &e->args[e->nargs])) {
            ex_free(e);
            return qp_fail(p);
          }
          e->nargs++;
          qp_ws(p);
          if (p->pos < p->n && p->s[p->pos] == ',') {
            p->pos++;
            continue;
          }
          break;
        }
      }
      if (p->pos >= p->n || p->s[p->pos] != ')') {
        ex_free(e);
        return qp_fail(p);
      }
      p->pos++;
      *out = e;
      return TRUE;
    }
  }
  return qp_fail(p);
}

Private bool qp_basic(JPARSEQ* p, JEXPR** out) {
  JEXPR* l;
  int op = 0;

  qp_ws(p);
  if (p->pos < p->n && p->s[p->pos] == '!') {
    JEXPR* e = ex_new(EX_NOT);

    p->pos++;
    if (!qp_basic(p, &e->a)) {
      ex_free(e);
      return FALSE;
    }
    *out = e;
    return TRUE;
  }
  if (p->pos < p->n && p->s[p->pos] == '(') {
    p->pos++;
    if (!qp_or(p, &l))
      return FALSE;
    qp_ws(p);
    if (p->pos >= p->n || p->s[p->pos] != ')') {
      ex_free(l);
      return qp_fail(p);
    }
    p->pos++;
    *out = l;
    return TRUE;
  }
  if (!qp_comparable(p, &l))
    return FALSE;
  qp_ws(p);
  if (p->pos + 1 < p->n) {
    char a = p->s[p->pos], b = p->s[p->pos + 1];

    if (a == '=' && b == '=') {
      op = 1;
      p->pos += 2;
    } else if (a == '!' && b == '=') {
      op = 2;
      p->pos += 2;
    } else if (a == '<' && b == '=') {
      op = 4;
      p->pos += 2;
    } else if (a == '>' && b == '=') {
      op = 6;
      p->pos += 2;
    } else if (a == '<') {
      op = 3;
      p->pos += 1;
    } else if (a == '>') {
      op = 5;
      p->pos += 1;
    }
  }
  if (op) {
    JEXPR* e = ex_new(EX_CMP);

    e->op = op;
    e->a = l;
    if (!qp_comparable(p, &e->b)) {
      ex_free(e);
      return FALSE;
    }
    *out = e;
    return TRUE;
  }
  {
    JEXPR* e = ex_new(EX_TEST);

    e->a = l; /* a query, or a function such as match() */
    *out = e;
    return TRUE;
  }
}

Private bool qp_and(JPARSEQ* p, JEXPR** out) {
  JEXPR* l;

  if (!qp_basic(p, &l))
    return FALSE;
  for (;;) {
    qp_ws(p);
    if (p->pos + 1 < p->n && p->s[p->pos] == '&' && p->s[p->pos + 1] == '&') {
      JEXPR* e = ex_new(EX_AND);

      p->pos += 2;
      e->a = l;
      if (!qp_basic(p, &e->b)) {
        ex_free(e);
        return FALSE;
      }
      l = e;
    } else {
      break;
    }
  }
  *out = l;
  return TRUE;
}

Private bool qp_or(JPARSEQ* p, JEXPR** out) {
  JEXPR* l;

  if (!qp_and(p, &l))
    return FALSE;
  for (;;) {
    qp_ws(p);
    if (p->pos + 1 < p->n && p->s[p->pos] == '|' && p->s[p->pos + 1] == '|') {
      JEXPR* e = ex_new(EX_OR);

      p->pos += 2;
      e->a = l;
      if (!qp_and(p, &e->b)) {
        ex_free(e);
        return FALSE;
      }
      l = e;
    } else {
      break;
    }
  }
  *out = l;
  return TRUE;
}

/* ---- evaluation ---- */

typedef struct {
  COLL_ENTRY** v;
  int32_t n;
  int32_t cap;
} NL;

Private void nl_add(NL* l, COLL_ENTRY* e) {
  if (l->n >= l->cap) {
    int32_t nc = l->cap ? l->cap * 2 : 16;
    COLL_ENTRY** nv = (COLL_ENTRY**)k_alloc(JTAG, nc * sizeof(COLL_ENTRY*));

    if (l->n)
      memcpy(nv, l->v, l->n * sizeof(COLL_ENTRY*));
    if (l->v != NULL)
      k_free(l->v);
    l->v = nv;
    l->cap = nc;
  }
  l->v[l->n++] = e;
}

Private void nl_free(NL* l) {
  if (l->v != NULL)
    k_free(l->v);
  l->v = NULL;
  l->n = l->cap = 0;
}

typedef struct {
  COLL_ENTRY* root;
} JCTX;

Private void run_query(JCTX* cx, JQUERY* q, COLL_ENTRY* start, NL* out);
Private bool ex_true(JCTX* cx, JEXPR* e, COLL_ENTRY* cur);

/* the descendants of e and e, in document order */
Private void descend(COLL_ENTRY* e, NL* out, int depth) {
  int32_t i;

  nl_add(out, e);
  if (depth > J_MAX_DEPTH)
    return;
  if (e->d.type == COLL && e->tag == CT_PLAIN) {
    COLL_HEADER* h = e->d.data.coll;

    for (i = 0; i < h->count; i++)
      descend(&h->e[i], out, depth + 1);
  }
}

Private void select_from(JCTX* cx, JSEL* s, COLL_ENTRY* x, NL* out) {
  COLL_HEADER* h;
  int32_t i, pos;

  if (x->d.type != COLL)
    return;
  h = x->d.data.coll;
  switch (s->type) {
    case SEL_NAME:
      if (!h->is_array && coll_find(h, s->name, s->name_len, &pos))
        nl_add(out, &h->e[pos]);
      break;
    case SEL_INDEX:
      if (h->is_array) {
        int32_t k = s->index < 0 ? h->count + s->index : s->index;

        if (k >= 0 && k < h->count)
          nl_add(out, &h->e[k]);
      }
      break;
    case SEL_WILD:
      for (i = 0; i < h->count; i++)
        nl_add(out, &h->e[i]);
      break;
    case SEL_SLICE:
      if (h->is_array && s->step != 0) {
        int32_t len = h->count, st = s->step;
        int32_t lo, hi, a, b;

        if (st > 0) {
          a = s->has_start ? s->start : 0;
          b = s->has_end ? s->end : len;
        } else {
          a = s->has_start ? s->start : len - 1;
          b = s->has_end ? s->end : -len - 1;
        }
        a = (a >= 0) ? a : len + a;
        b = (b >= 0) ? b : len + b;
        if (st > 0) {
          lo = a < 0 ? 0 : (a > len ? len : a);
          hi = b < 0 ? 0 : (b > len ? len : b);
          for (i = lo; i < hi; i += st)
            nl_add(out, &h->e[i]);
        } else {
          hi = a < -1 ? -1 : (a > len - 1 ? len - 1 : a);
          lo = b < -1 ? -1 : (b > len - 1 ? len - 1 : b);
          for (i = hi; lo < i; i += st)
            nl_add(out, &h->e[i]);
        }
      }
      break;
    case SEL_FILTER:
      for (i = 0; i < h->count; i++)
        if (ex_true(cx, s->filter, &h->e[i]))
          nl_add(out, &h->e[i]);
      break;
  }
}

Private void run_query(JCTX* cx, JQUERY* q, COLL_ENTRY* start, NL* out) {
  NL cur, nxt;
  int i, j;
  int32_t k;

  memset(&cur, 0, sizeof cur);
  memset(&nxt, 0, sizeof nxt);
  nl_add(&cur, q->absolute ? cx->root : start);
  for (i = 0; i < q->nseg; i++) {
    JSEG* sg = &q->seg[i];

    nxt.n = 0;
    for (k = 0; k < cur.n; k++) {
      if (sg->descendant) {
        NL d;
        int32_t m;

        memset(&d, 0, sizeof d);
        descend(cur.v[k], &d, 0);
        for (m = 0; m < d.n; m++)
          for (j = 0; j < sg->nsel; j++)
            select_from(cx, &sg->sel[j], d.v[m], &nxt);
        nl_free(&d);
      } else {
        for (j = 0; j < sg->nsel; j++)
          select_from(cx, &sg->sel[j], cur.v[k], &nxt);
      }
    }
    {
      NL t = cur;

      cur = nxt;
      nxt = t;
    }
  }
  for (k = 0; k < cur.n; k++)
    nl_add(out, cur.v[k]);
  nl_free(&cur);
  nl_free(&nxt);
}

/* a value in a comparison */
typedef struct {
  int kind; /* 0 nothing, 1 null, 2 bool, 3 number, 4 string, 5 structure */
  int b;
  double num;
  char* s;
  int32_t slen;
  COLL_ENTRY* node;
} JV;

Private void jv_free(JV* v) {
  if (v->s != NULL)
    k_free(v->s);
  v->s = NULL;
}

Private void jv_from_entry(JV* v, COLL_ENTRY* e) {
  memset(v, 0, sizeof *v);
  switch (jkind(e)) {
    case JK_NULL:
      v->kind = 1;
      break;
    case JK_BOOL:
      v->kind = 2;
      v->b = e->d.data.value != 0;
      break;
    case JK_INT:
    case JK_FLOAT:
      v->kind = 3;
      v->num = jnum(e);
      break;
    case JK_STRING:
      v->kind = 4;
      v->s = jstr(e, &v->slen);
      break;
    default:
      v->kind = 5;
      v->node = e;
  }
}

Private void ex_value(JCTX* cx, JEXPR* e, COLL_ENTRY* cur, JV* v);

Private void ex_value(JCTX* cx, JEXPR* e, COLL_ENTRY* cur, JV* v) {
  memset(v, 0, sizeof *v);
  switch (e->type) {
    case EX_LIT:
      v->kind = e->lit;
      v->b = e->boolean;
      v->num = e->num;
      if (e->lit == 4) {
        v->s = (char*)k_alloc(JTAG, e->slen + 1);
        memcpy(v->s, e->str, e->slen);
        v->slen = e->slen;
      }
      break;
    case EX_QUERY: {
      NL nl;

      memset(&nl, 0, sizeof nl);
      run_query(cx, &e->q, cur, &nl);
      if (nl.n == 1)
        jv_from_entry(v, nl.v[0]);
      nl_free(&nl);
      break;
    }
    case EX_FUNC:
      if (strcmp(e->fname, "length") == 0 && e->nargs == 1) {
        JV a;

        ex_value(cx, e->args[0], cur, &a);
        if (a.kind == 4) {
          v->kind = 3;
          v->num = a.slen;
        } else if (a.kind == 5) {
          v->kind = 3;
          v->num = a.node->d.data.coll->count;
        }
        jv_free(&a);
      } else if (strcmp(e->fname, "count") == 0 && e->nargs == 1 && e->args[0]->type == EX_QUERY) {
        NL nl;

        memset(&nl, 0, sizeof nl);
        run_query(cx, &e->args[0]->q, cur, &nl);
        v->kind = 3;
        v->num = nl.n;
        nl_free(&nl);
      } else if (strcmp(e->fname, "value") == 0 && e->nargs == 1 && e->args[0]->type == EX_QUERY) {
        ex_value(cx, e->args[0], cur, v);
      } else if ((strcmp(e->fname, "match") == 0 || strcmp(e->fname, "search") == 0) && e->nargs == 2) {
        JV a, b;
        regex_t re;
        int rc = 1;

        ex_value(cx, e->args[0], cur, &a);
        ex_value(cx, e->args[1], cur, &b);
        v->kind = 2;
        if (a.kind == 4 && b.kind == 4) {
          JB pat;

          jb_init(&pat);
          if (e->fname[0] == 'm')
            jb_add(&pat, "^(", 2);
          jb_add(&pat, b.s, b.slen);
          if (e->fname[0] == 'm')
            jb_add(&pat, ")$", 2);
          if (regcomp(&re, pat.b, REG_EXTENDED | REG_NOSUB) == 0) {
            rc = regexec(&re, a.s, 0, NULL, 0);
            regfree(&re);
          }
          jb_free(&pat);
        }
        v->b = (rc == 0);
        jv_free(&a);
        jv_free(&b);
      }
      break;
    default:
      break;
  }
}

Private bool jv_eq(JV* a, JV* b) {
  if (a->kind != b->kind)
    return FALSE;
  switch (a->kind) {
    case 0:
    case 1:
      return TRUE;
    case 2:
      return a->b == b->b;
    case 3:
      return a->num == b->num;
    case 4:
      return a->slen == b->slen && memcmp(a->s, b->s, a->slen) == 0;
    case 5:
      return jeq(a->node, b->node);
  }
  return FALSE;
}

/* a < b for two numbers or two strings, false otherwise */
Private bool jv_lt(JV* a, JV* b) {
  if (a->kind == 3 && b->kind == 3)
    return a->num < b->num;
  if (a->kind == 4 && b->kind == 4) {
    int32_t m = a->slen < b->slen ? a->slen : b->slen;
    int c = memcmp(a->s, b->s, m);

    return c < 0 || (c == 0 && a->slen < b->slen);
  }
  return FALSE;
}

Private bool ex_true(JCTX* cx, JEXPR* e, COLL_ENTRY* cur) {
  switch (e->type) {
    case EX_OR:
      return ex_true(cx, e->a, cur) || ex_true(cx, e->b, cur);
    case EX_AND:
      return ex_true(cx, e->a, cur) && ex_true(cx, e->b, cur);
    case EX_NOT:
      return !ex_true(cx, e->a, cur);
    case EX_CMP: {
      JV a, b;
      bool r = FALSE;

      ex_value(cx, e->a, cur, &a);
      ex_value(cx, e->b, cur, &b);
      switch (e->op) {
        case 1:
          r = jv_eq(&a, &b);
          break;
        case 2:
          r = !jv_eq(&a, &b);
          break;
        case 3:
          r = jv_lt(&a, &b);
          break;
        case 4:
          r = jv_lt(&a, &b) || jv_eq(&a, &b);
          break;
        case 5:
          r = jv_lt(&b, &a);
          break;
        case 6:
          r = jv_lt(&b, &a) || jv_eq(&a, &b);
          break;
      }
      jv_free(&a);
      jv_free(&b);
      return r;
    }
    case EX_TEST: {
      JEXPR* q = e->a;

      if (q->type == EX_QUERY) {
        NL nl;
        bool r;

        memset(&nl, 0, sizeof nl);
        run_query(cx, &q->q, cur, &nl);
        r = nl.n > 0;
        nl_free(&nl);
        return r;
      } else {
        JV v;
        bool r;

        ex_value(cx, q, cur, &v);
        r = (v.kind == 2 && v.b);
        jv_free(&v);
        return r;
      }
    }
    default:
      return FALSE;
  }
}

void x_jpath() {
  JARG c;
  char* qtext;
  int32_t qlen;
  JPARSEQ p;
  JQUERY q;
  JCTX cx;
  NL nl;
  COLL_HEADER* out;
  int32_t i;
  DESCRIPTOR result;

  process.status = 0;
  k_get_string(e_stack - 1);
  qtext = coll_chunks_to_buffer((e_stack - 1)->data.str.saddr, &qlen);
  if (!jarg_get(e_stack - 2, &c)) {
    k_free(qtext);
    k_dismiss();
    k_dismiss();
    push_null();
    return;
  }
  p.s = qtext;
  p.n = qlen;
  p.pos = 0;
  p.err = 0;
  p.depth = 0;
  qp_ws(&p);
  if (!qp_query(&p, &q, FALSE) || (qp_ws(&p), p.pos < p.n) || !q.absolute) {
    q_free(&q);
    process.status = ER_QUERY_ERROR;
    process.inmat = p.err ? p.err : p.pos + 1;
    k_free(qtext);
    jarg_free(&c);
    k_dismiss();
    k_dismiss();
    push_null();
    return;
  }
  cx.root = &c.e;
  memset(&nl, 0, sizeof nl);
  run_query(&cx, &q, &c.e, &nl);
  out = coll_new(TRUE);
  for (i = 0; i < nl.n; i++) {
    COLL_ENTRY* slot = jarr_slot(out, out->count);

    jcopy(slot, nl.v[i]);
  }
  nl_free(&nl);
  q_free(&q);
  k_free(qtext);
  jarg_free(&c);
  InitDescr(&result, COLL);
  result.data.coll = out;
  k_dismiss();
  k_dismiss();
  *(e_stack++) = result;
}

/* ======================================================================
   JVALIDATE()  -  JSON Schema

   Keywords that are checked: type, enum, const, minimum, maximum, exclusiveMinimum, exclusiveMaximum, multipleOf, minLength, maxLength,
   pattern, minItems, maxItems, uniqueItems, prefixItems, items, contains, minContains, maxContains, required, properties,
   patternProperties, additionalProperties, propertyNames, minProperties, maxProperties, dependentRequired, allOf, anyOf, oneOf, not,
   if / then / else, $ref (into this schema, "#" or "#/...") and a true or false for a whole schema.  Every other keyword, "format"
   included, is an annotation and is let be.  A length is a number of bytes: SD holds no character sets.                         */

typedef struct {
  COLL_HEADER* errs;
  COLL_ENTRY* rootschema;
  int count;
  int depth;
  bool cut;
} VCTX;

Private bool v_check(VCTX* cx, COLL_ENTRY* inst, COLL_ENTRY* schema, JB* path);

Private void v_err(VCTX* cx, JB* path, const char* keyword, const char* msg) {
  COLL_HEADER* eo;
  COLL_ENTRY* slot;

  if (cx->count >= J_MAX_ERRORS) {
    cx->cut = TRUE;
    return;
  }
  cx->count++;
  eo = coll_new(FALSE);
  slot = jobj_slot(eo, "path", 4);
  set_str(slot, path->b, path->len);
  slot = jobj_slot(eo, "keyword", 7);
  set_str(slot, keyword, (int32_t)strlen(keyword));
  slot = jobj_slot(eo, "message", 7);
  set_str(slot, msg, (int32_t)strlen(msg));
  slot = jarr_slot(cx->errs, cx->errs->count);
  set_coll(slot, eo);
}

Private COLL_ENTRY* sk(COLL_ENTRY* schema, const char* key) {
  if (jkind(schema) != JK_OBJECT)
    return NULL;
  return op_member(schema->d.data.coll, key);
}

Private void path_push_name(JB* path, const char* name, int32_t len) {
  int32_t i;

  jb_add(path, "/", 1);
  for (i = 0; i < len; i++) {
    if (name[i] == '~')
      jb_add(path, "~0", 2);
    else if (name[i] == '/')
      jb_add(path, "~1", 2);
    else
      jb_add(path, name + i, 1);
  }
}

Private void path_push_index(JB* path, int32_t i) {
  char t[16];

  sprintf(t, "/%d", (int)i);
  jb_add(path, t, (int32_t)strlen(t));
}

Private bool type_is(COLL_ENTRY* inst, const char* t, int32_t tl) {
  JKIND k = jkind(inst);

  if (tl == 4 && memcmp(t, "null", 4) == 0)
    return k == JK_NULL;
  if (tl == 7 && memcmp(t, "boolean", 7) == 0)
    return k == JK_BOOL;
  if (tl == 6 && memcmp(t, "string", 6) == 0)
    return k == JK_STRING;
  if (tl == 5 && memcmp(t, "array", 5) == 0)
    return k == JK_ARRAY;
  if (tl == 6 && memcmp(t, "object", 6) == 0)
    return k == JK_OBJECT;
  if (tl == 6 && memcmp(t, "number", 6) == 0)
    return k == JK_INT || k == JK_FLOAT;
  if (tl == 7 && memcmp(t, "integer", 7) == 0)
    return k == JK_INT || (k == JK_FLOAT && jnum(inst) == floor(jnum(inst)));
  return FALSE;
}

/* does the instance satisfy the schema, leaving no trace of its errors? */
Private bool v_trial(VCTX* cx, COLL_ENTRY* inst, COLL_ENTRY* schema, JB* path) {
  COLL_HEADER* saved = cx->errs;
  int saved_count = cx->count;
  bool ok;
  DESCRIPTOR t;

  cx->errs = coll_new(TRUE);
  cx->count = 0;
  ok = v_check(cx, inst, schema, path);
  InitDescr(&t, COLL);
  t.data.coll = cx->errs;
  ok = ok && (cx->errs->count == 0);
  k_release(&t);
  cx->errs = saved;
  cx->count = saved_count;
  return ok;
}

Private bool v_ref(VCTX* cx, COLL_ENTRY* ref, COLL_ENTRY** target) {
  int32_t len;
  char* s = jstr(ref, &len);
  PTR p;
  bool ok = FALSE;

  *target = NULL;
  if (len >= 1 && s[0] == '#') {
    if (len == 1) {
      *target = cx->rootschema;
      ok = TRUE;
    } else if (s[1] == '/' && ptr_parse(s + 1, len - 1, &p)) {
      *target = ptr_get(cx->rootschema, &p, p.n);
      ok = (*target != NULL);
      ptr_free(&p);
    }
  }
  k_free(s);
  return ok;
}

Private bool v_check(VCTX* cx, COLL_ENTRY* inst, COLL_ENTRY* schema, JB* path) {
  COLL_ENTRY* kw;
  JKIND ik = jkind(inst);
  int32_t i, j;
  int start_count = cx->count;
  char msg[256];

  if (cx->depth > 64)
    return TRUE;
  cx->depth++;
  if (jkind(schema) == JK_BOOL) {
    if (!schema->d.data.value)
      v_err(cx, path, "false", "no value is allowed here");
    cx->depth--;
    return cx->count == start_count;
  }
  if (jkind(schema) != JK_OBJECT) {
    cx->depth--;
    return TRUE;
  }

  if ((kw = sk(schema, "$ref")) != NULL && jkind(kw) == JK_STRING) {
    COLL_ENTRY* tgt;

    if (!v_ref(cx, kw, &tgt))
      v_err(cx, path, "$ref", "a $ref that is not \"#\" or \"#/...\" into this schema cannot be followed");
    else
      v_check(cx, inst, tgt, path);
  }

  if ((kw = sk(schema, "type")) != NULL) {
    bool ok = FALSE;

    if (jkind(kw) == JK_STRING) {
      int32_t tl;
      char* t = jstr(kw, &tl);

      ok = type_is(inst, t, tl);
      k_free(t);
    } else if (jkind(kw) == JK_ARRAY) {
      for (i = 0; i < kw->d.data.coll->count && !ok; i++) {
        int32_t tl;
        char* t = jstr(&kw->d.data.coll->e[i], &tl);

        ok = type_is(inst, t, tl);
        k_free(t);
      }
    } else {
      ok = TRUE;
    }
    if (!ok)
      v_err(cx, path, "type", "the value is not of the type the schema asks for");
  }

  if ((kw = sk(schema, "enum")) != NULL && jkind(kw) == JK_ARRAY) {
    bool ok = FALSE;

    for (i = 0; i < kw->d.data.coll->count && !ok; i++)
      ok = jeq(inst, &kw->d.data.coll->e[i]);
    if (!ok)
      v_err(cx, path, "enum", "the value is not one of those the schema lists");
  }
  if ((kw = sk(schema, "const")) != NULL && !jeq(inst, kw))
    v_err(cx, path, "const", "the value is not the one the schema asks for");

  if (ik == JK_INT || ik == JK_FLOAT) {
    double x = jnum(inst);

    if ((kw = sk(schema, "minimum")) != NULL && (jkind(kw) == JK_INT || jkind(kw) == JK_FLOAT) && x < jnum(kw))
      v_err(cx, path, "minimum", "the number is below the minimum");
    if ((kw = sk(schema, "maximum")) != NULL && (jkind(kw) == JK_INT || jkind(kw) == JK_FLOAT) && x > jnum(kw))
      v_err(cx, path, "maximum", "the number is above the maximum");
    if ((kw = sk(schema, "exclusiveMinimum")) != NULL && (jkind(kw) == JK_INT || jkind(kw) == JK_FLOAT) && x <= jnum(kw))
      v_err(cx, path, "exclusiveMinimum", "the number is not above the exclusive minimum");
    if ((kw = sk(schema, "exclusiveMaximum")) != NULL && (jkind(kw) == JK_INT || jkind(kw) == JK_FLOAT) && x >= jnum(kw))
      v_err(cx, path, "exclusiveMaximum", "the number is not below the exclusive maximum");
    if ((kw = sk(schema, "multipleOf")) != NULL && (jkind(kw) == JK_INT || jkind(kw) == JK_FLOAT) && jnum(kw) > 0) {
      double q = x / jnum(kw);

      if (fabs(q - floor(q + 0.5)) > 1e-9)
        v_err(cx, path, "multipleOf", "the number is not a multiple of the schema's");
    }
  }

  if (ik == JK_STRING) {
    int32_t len;
    char* s = jstr(inst, &len);

    if ((kw = sk(schema, "minLength")) != NULL && (jkind(kw) == JK_INT) && len < kw->d.data.value)
      v_err(cx, path, "minLength", "the string is shorter than the minimum length");
    if ((kw = sk(schema, "maxLength")) != NULL && (jkind(kw) == JK_INT) && len > kw->d.data.value)
      v_err(cx, path, "maxLength", "the string is longer than the maximum length");
    if ((kw = sk(schema, "pattern")) != NULL && jkind(kw) == JK_STRING) {
      int32_t pl;
      char* pat = jstr(kw, &pl);
      regex_t re;

      if (regcomp(&re, pat, REG_EXTENDED | REG_NOSUB) == 0) {
        if (regexec(&re, s, 0, NULL, 0) != 0)
          v_err(cx, path, "pattern", "the string does not match the pattern");
        regfree(&re);
      } else {
        v_err(cx, path, "pattern", "the schema's pattern is not a regular expression");
      }
      k_free(pat);
    }
    k_free(s);
  }

  if (ik == JK_ARRAY) {
    COLL_HEADER* h = inst->d.data.coll;
    int32_t prefix = 0;

    if ((kw = sk(schema, "minItems")) != NULL && jkind(kw) == JK_INT && h->count < kw->d.data.value)
      v_err(cx, path, "minItems", "the array has fewer items than the minimum");
    if ((kw = sk(schema, "maxItems")) != NULL && jkind(kw) == JK_INT && h->count > kw->d.data.value)
      v_err(cx, path, "maxItems", "the array has more items than the maximum");
    if ((kw = sk(schema, "uniqueItems")) != NULL && jkind(kw) == JK_BOOL && kw->d.data.value) {
      bool dup = FALSE;

      for (i = 0; i < h->count && !dup; i++)
        for (j = i + 1; j < h->count && !dup; j++)
          dup = jeq(&h->e[i], &h->e[j]);
      if (dup)
        v_err(cx, path, "uniqueItems", "the array holds the same item twice");
    }
    if ((kw = sk(schema, "prefixItems")) != NULL && jkind(kw) == JK_ARRAY) {
      prefix = kw->d.data.coll->count;
      for (i = 0; i < prefix && i < h->count; i++) {
        int32_t keep = path->len;

        path_push_index(path, i);
        v_check(cx, &h->e[i], &kw->d.data.coll->e[i], path);
        path->len = keep;
        path->b[keep] = '\0';
      }
    }
    if ((kw = sk(schema, "items")) != NULL) {
      if (jkind(kw) == JK_ARRAY) { /* the older form of prefixItems */
        for (i = 0; i < kw->d.data.coll->count && i < h->count; i++) {
          int32_t keep = path->len;

          path_push_index(path, i);
          v_check(cx, &h->e[i], &kw->d.data.coll->e[i], path);
          path->len = keep;
          path->b[keep] = '\0';
        }
      } else {
        for (i = prefix; i < h->count; i++) {
          int32_t keep = path->len;

          path_push_index(path, i);
          v_check(cx, &h->e[i], kw, path);
          path->len = keep;
          path->b[keep] = '\0';
        }
      }
    }
    if ((kw = sk(schema, "contains")) != NULL) {
      int32_t matches = 0;
      int32_t minc = 1, maxc = -1;
      COLL_ENTRY* mk;

      for (i = 0; i < h->count; i++)
        if (v_trial(cx, &h->e[i], kw, path))
          matches++;
      if ((mk = sk(schema, "minContains")) != NULL && jkind(mk) == JK_INT)
        minc = mk->d.data.value;
      if ((mk = sk(schema, "maxContains")) != NULL && jkind(mk) == JK_INT)
        maxc = mk->d.data.value;
      if (matches < minc || (maxc >= 0 && matches > maxc))
        v_err(cx, path, "contains", "the array does not hold the number of matching items the schema asks for");
    }
  }

  if (ik == JK_OBJECT) {
    COLL_HEADER* h = inst->d.data.coll;
    COLL_ENTRY* props = sk(schema, "properties");
    COLL_ENTRY* pprops = sk(schema, "patternProperties");
    COLL_ENTRY* addl = sk(schema, "additionalProperties");

    if ((kw = sk(schema, "required")) != NULL && jkind(kw) == JK_ARRAY) {
      for (i = 0; i < kw->d.data.coll->count; i++) {
        int32_t nl, pos;
        char* n = jstr(&kw->d.data.coll->e[i], &nl);

        if (!coll_find(h, n, nl, &pos)) {
          snprintf(msg, sizeof msg, "the property \"%.60s\" is required", n);
          v_err(cx, path, "required", msg);
        }
        k_free(n);
      }
    }
    if ((kw = sk(schema, "minProperties")) != NULL && jkind(kw) == JK_INT && h->count < kw->d.data.value)
      v_err(cx, path, "minProperties", "the object has fewer properties than the minimum");
    if ((kw = sk(schema, "maxProperties")) != NULL && jkind(kw) == JK_INT && h->count > kw->d.data.value)
      v_err(cx, path, "maxProperties", "the object has more properties than the maximum");
    if ((kw = sk(schema, "dependentRequired")) != NULL && jkind(kw) == JK_OBJECT) {
      for (i = 0; i < kw->d.data.coll->count; i++) {
        int32_t pos;

        if (coll_find(h, kw->d.data.coll->e[i].name, kw->d.data.coll->e[i].name_len, &pos) && jkind(&kw->d.data.coll->e[i]) == JK_ARRAY) {
          COLL_HEADER* need = kw->d.data.coll->e[i].d.data.coll;

          for (j = 0; j < need->count; j++) {
            int32_t nl, p2;
            char* n = jstr(&need->e[j], &nl);

            if (!coll_find(h, n, nl, &p2)) {
              snprintf(msg, sizeof msg, "the property \"%.60s\" is required when \"%.60s\" is present", n, kw->d.data.coll->e[i].name);
              v_err(cx, path, "dependentRequired", msg);
            }
            k_free(n);
          }
        }
      }
    }
    for (i = 0; i < h->count; i++) {
      COLL_ENTRY* member = &h->e[i];
      bool matched = FALSE;
      int32_t pos;
      int32_t keep = path->len;

      if (props != NULL && jkind(props) == JK_OBJECT && coll_find(props->d.data.coll, member->name, member->name_len, &pos)) {
        matched = TRUE;
        path_push_name(path, member->name, member->name_len);
        v_check(cx, member, &props->d.data.coll->e[pos], path);
        path->len = keep;
        path->b[keep] = '\0';
      }
      if (pprops != NULL && jkind(pprops) == JK_OBJECT) {
        for (j = 0; j < pprops->d.data.coll->count; j++) {
          regex_t re;

          if (regcomp(&re, pprops->d.data.coll->e[j].name, REG_EXTENDED | REG_NOSUB) == 0) {
            if (regexec(&re, member->name, 0, NULL, 0) == 0) {
              matched = TRUE;
              path_push_name(path, member->name, member->name_len);
              v_check(cx, member, &pprops->d.data.coll->e[j], path);
              path->len = keep;
              path->b[keep] = '\0';
            }
            regfree(&re);
          }
        }
      }
      if (!matched && addl != NULL) {
        path_push_name(path, member->name, member->name_len);
        if (jkind(addl) == JK_BOOL) {
          if (!addl->d.data.value) {
            snprintf(msg, sizeof msg, "the property \"%.60s\" is not allowed", member->name);
            v_err(cx, path, "additionalProperties", msg);
          }
        } else {
          v_check(cx, member, addl, path);
        }
        path->len = keep;
        path->b[keep] = '\0';
      }
      if ((kw = sk(schema, "propertyNames")) != NULL) {
        COLL_ENTRY nm;

        new_null_entry(&nm);
        set_str(&nm, member->name, member->name_len);
        if (!v_trial(cx, &nm, kw, path)) {
          snprintf(msg, sizeof msg, "the property name \"%.60s\" is not allowed", member->name);
          v_err(cx, path, "propertyNames", msg);
        }
        k_release(&nm.d);
      }
    }
  }

  if ((kw = sk(schema, "allOf")) != NULL && jkind(kw) == JK_ARRAY) {
    for (i = 0; i < kw->d.data.coll->count; i++)
      v_check(cx, inst, &kw->d.data.coll->e[i], path);
  }
  if ((kw = sk(schema, "anyOf")) != NULL && jkind(kw) == JK_ARRAY) {
    bool ok = FALSE;

    for (i = 0; i < kw->d.data.coll->count && !ok; i++)
      ok = v_trial(cx, inst, &kw->d.data.coll->e[i], path);
    if (!ok)
      v_err(cx, path, "anyOf", "the value matches none of the schemas of anyOf");
  }
  if ((kw = sk(schema, "oneOf")) != NULL && jkind(kw) == JK_ARRAY) {
    int matches = 0;

    for (i = 0; i < kw->d.data.coll->count; i++)
      if (v_trial(cx, inst, &kw->d.data.coll->e[i], path))
        matches++;
    if (matches != 1)
      v_err(cx, path, "oneOf", matches ? "the value matches more than one schema of oneOf" : "the value matches none of the schemas of oneOf");
  }
  if ((kw = sk(schema, "not")) != NULL && v_trial(cx, inst, kw, path))
    v_err(cx, path, "not", "the value matches the schema it must not match");
  if ((kw = sk(schema, "if")) != NULL) {
    COLL_ENTRY* th = sk(schema, "then");
    COLL_ENTRY* el = sk(schema, "else");

    if (v_trial(cx, inst, kw, path)) {
      if (th != NULL)
        v_check(cx, inst, th, path);
    } else if (el != NULL) {
      v_check(cx, inst, el, path);
    }
  }
  cx->depth--;
  return cx->count == start_count;
}

void x_jvalidate() {
  JARG c, sch;
  VCTX cx;
  JB path;
  DESCRIPTOR result;

  process.status = 0;
  if (!jarg_get(e_stack - 2, &c)) {
    k_dismiss();
    k_dismiss();
    push_null();
    return;
  }
  if (!jarg_get(e_stack - 1, &sch)) {
    jarg_free(&c);
    k_dismiss();
    k_dismiss();
    push_null();
    return;
  }
  cx.errs = coll_new(TRUE);
  cx.rootschema = &sch.e;
  cx.count = 0;
  cx.depth = 0;
  cx.cut = FALSE;
  jb_init(&path);
  v_check(&cx, &c.e, &sch.e, &path);
  jb_free(&path);
  InitDescr(&result, COLL);
  result.data.coll = cx.errs;
  jarg_free(&c);
  jarg_free(&sch);
  k_dismiss();
  k_dismiss();
  *(e_stack++) = result;
}

/* END-CODE */
