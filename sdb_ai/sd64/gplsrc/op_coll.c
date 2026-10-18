/* OP_COLL.C
 * Data collections (13 Oct 2026, 1.2-0, openQM compatibility)
 *
 * A data collection is an arbitrarily nested set of name / value pairs.  The
 * value of an element is a number, a string, another collection or an array
 * (a collection whose elements are numbered rather than named).  Collections
 * are reference counted: copying the variable makes another reference to the
 * same collection and COLLECTION(c) makes an independent copy.
 *
 * START-HISTORY:
 * 18 Oct 26 Windows port - from Linux 3d67141 (13 Oct 26): New. COLLECTION(), element get, set and delete, ELEMENT.EXISTS()
 *               and ENUMERATE().
 * 18 Oct 26 Windows port - from Linux 2e043bc (13 Oct 26): Arrays: MAT(), MAT(matrix {, max}), MAT target = MAT c{path},
 *               INMAT(c{path}), INS value AS c{path}, and asterisk paths.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *    op_coll        One opcode for every collection operation.  The top of the
 *                   stack is a function number:
 *
 *    CF_NEW      COLLECTION()                   [fn]               -> coll
 *    CF_COPY     COLLECTION(c)                  [c, fn]            -> coll
 *    CF_GET      c{path}                        [c, p1..pn, n, fn] -> value
 *    CF_SET      c{path} = value                [ADDR, p1..pn, n, value, fn]
 *    CF_DEL      DEL c{path}                    [ADDR, p1..pn, n, fn]
 *    CF_EXISTS   ELEMENT.EXISTS(c, path)        [c, p1..pn, n, fn] -> 0 / 1
 *    CF_ENUM     ENUMERATE(c)                   [c, fn]            -> names
 *    CF_MATNEW   MAT()                          [fn]               -> array
 *    CF_MATCOPY  MAT(matrix, max)               [ADDR, max, fn]    -> array
 *    CF_MATGET   MAT target = MAT c{path}       [ADDR, array, fn]
 *    CF_INMAT    INMAT(c{path})                 [array, fn]        -> count
 *    CF_INS      INS value AS c{path}           [value, ADDR, p1..pn, n, fn]
 *    CF_JPARSE   JPARSE(string, mode)           [string, mode, fn] -> coll
 *    CF_JBUILD   JBUILD(coll, mode)             [coll, mode, fn]   -> string
 *    CF_JBOOLEAN JBOOLEAN(x)                    [x, fn]            -> boolean
 *    CF_JNULL    JNULL()                        [fn]               -> null
 *    CF_JTYPE    JTYPE(x)                       [x, fn]            -> text
 *    CF_SETOP    c{path} += value (and -= *= /= :=)
 *                                               [ADDR, p1..pn, n, value, op, fn]
 *
 *    A boolean or a JSON null is an ordinary integer 0 or 1, or null string,
 *    that carries the DF_JSON flag.  An element of a collection that is
 *    set from one is kept as a boolean or a null, and reads back with the
 *    flag, so JBUILD() writes true, false or null.
 *
 *    A path component that is a string may hold several names separated by
 *    slashes; an integer (or a string of digits met in an array) selects an
 *    array element.  The components are one path whatever the way it was
 *    written: c{'a','b'}, c{'a'}{'b'} and c{'a/b'} are the same element.
 *    In a GET a component of * stands for every element of an array and the
 *    result is a dynamic array: values for the first *, subvalues for a
 *    second.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "err.h"
#include "keys.h"
#include <ctype.h>

/* The JPARSE() and JBUILD() mode bits, as keys.h names them */
#define JP_NULL_BIT JP_NULL
#define JP_UNQUOTED_NAME_BIT JP_UNQUOTED_NAME
#define JB_INVALID_BIT JB_INVALID
#define JB_NULL_BIT JB_NULL
#define JB_NUM_BIT JB_NUM
#define JB_SQUOTE_NAME_BIT JB_SQUOTE_NAME
#define JB_NOQUOTE_NAME_BIT JB_NOQUOTE_NAME
#define JB_SQUOTE_VALUE_BIT JB_SQUOTE_VALUE
#define JB_NOQUOTE_VALUE_BIT JB_NOQUOTE_VALUE
#define JB_PRETTY_BIT JB_PRETTY

#define CF_NEW 1
#define CF_COPY 2
#define CF_GET 3
#define CF_SET 4
#define CF_DEL 5
#define CF_EXISTS 6
#define CF_ENUM 7
#define CF_MATNEW 8
#define CF_MATCOPY 9
#define CF_MATGET 10
#define CF_INMAT 11
#define CF_INS 12
#define CF_JPARSE 13
#define CF_JBUILD 14
#define CF_JBOOLEAN 15
#define CF_JNULL 16
#define CF_JTYPE 17
#define CF_SETOP 18

#define COLL_ALLOC_TAG 160
#define JSON_MAX_DEPTH 500

/* One name in a path, after splitting on slashes */
typedef struct {
  char* p;       /* Points into the buffer that holds the whole component */
  int32_t len;
  bool numeric;  /* All digits, or an integer component */
  int32_t num;
  char buf[16];  /* Text of an integer component */
} COLL_SEG;

/* A growing buffer for the dynamic array an asterisk path returns */
typedef struct {
  char* b;
  int32_t len;
  int32_t cap;
} COLL_BUF;

Private COLL_HEADER* coll_new(bool is_array);
Private COLL_HEADER* coll_copy(COLL_HEADER* src);
Private void coll_free_entry(COLL_ENTRY* e);
Private bool coll_find(COLL_HEADER* h, char* name, int32_t len, int32_t* pos);
Private void coll_insert(COLL_HEADER* h, int32_t pos);
Private void coll_remove(COLL_HEADER* h, int32_t pos);
Private COLL_HEADER* need_coll(DESCRIPTOR* d);
Private COLL_HEADER* need_array(DESCRIPTOR* d);
Private char* chunks_to_buffer(STRING_CHUNK* s, int32_t* len);
Private int split_path(DESCRIPTOR* comps, int n, COLL_SEG** segs_out, char*** bufs_out);
Private int walk(COLL_HEADER* root, COLL_SEG* seg, int nseg, bool create, COLL_HEADER** parent, int32_t* pos, bool* exists);
Private DESCRIPTOR value_of(COLL_ENTRY* e);
Private void set_entry_name(COLL_ENTRY* ent, COLL_SEG* seg);
Private void free_path(COLL_SEG* segs, char** bufs, int n);
Private bool matrix_span(DESCRIPTOR* d, ARRAY_HEADER** hdr, int32_t* first, int32_t* count);
Private void buf_add(COLL_BUF* b, char* s, int32_t len);
Private void buf_value(COLL_BUF* b, COLL_ENTRY* e);
Private void star_get(COLL_BUF* b, COLL_HEADER* cur, COLL_SEG* seg, int nseg, int i, int star);
Private DESCRIPTOR json_parse(char* text, int32_t len, int mode);
Private DESCRIPTOR json_build(COLL_HEADER* root, int mode);
Private void fill_entry(COLL_ENTRY* ent, DESCRIPTOR* v);
Private DESCRIPTOR str_descr(char* s, int32_t len);

void op_add(void);
void op_sub(void);
void op_mul(void);
void op_div(void);
void op_cat(void);

/* ======================================================================
   coll_deref()  -  Drop a reference, freeing the collection at zero      */

void coll_deref(COLL_HEADER* h) {
  int32_t i;

  if (h == NULL)
    return;
  if (--(h->ref_ct) > 0)
    return;

  for (i = 0; i < h->count; i++)
    coll_free_entry(&h->e[i]);
  if (h->e != NULL)
    k_free(h->e);
  k_free(h);
}

/* ======================================================================
   op_coll()                                                              */

void op_coll() {
  DESCRIPTOR* descr;
  DESCRIPTOR result;
  COLL_HEADER* root;
  COLL_HEADER* parent;
  COLL_SEG* segs = NULL;
  char** bufs = NULL;
  DESCRIPTOR* comps;
  DESCRIPTOR* value = NULL;
  DESCRIPTOR* rootd;
  int32_t func;
  int32_t n;
  int32_t i;
  int32_t pos;
  int32_t max;
  int32_t setop = 0;
  int32_t first;
  int32_t count;
  ARRAY_HEADER* ahdr;
  bool exists;
  bool star;
  int nseg;
  int rc;
  int drop;
  COLL_ENTRY* ent;
  COLL_BUF cb;

  descr = e_stack - 1;
  GetInt(descr);
  func = descr->data.value;
  k_pop(1);

  switch (func) {
    case CF_NEW:
      InitDescr(&result, COLL);
      result.data.coll = coll_new(FALSE);
      *(e_stack++) = result;
      break;

    case CF_MATNEW:
      InitDescr(&result, COLL);
      result.data.coll = coll_new(TRUE);
      *(e_stack++) = result;
      break;

    case CF_COPY:
      root = need_coll(e_stack - 1);
      InitDescr(&result, COLL);
      result.data.coll = coll_copy(root);
      k_dismiss();
      *(e_stack++) = result;
      break;

    case CF_ENUM:
      root = need_coll(e_stack - 1);
      InitDescr(&result, STRING);
      result.data.str.saddr = NULL;
      ts_init(&result.data.str.saddr, 64);
      for (i = 0; i < root->count; i++) {
        if (i)
          ts_copy_byte(FIELD_MARK);
        if (root->is_array) {
          ts_printf("%d", (int)(i + 1));
        } else {
          ts_copy(root->e[i].name, root->e[i].name_len);
        }
      }
      ts_terminate();
      k_dismiss();
      *(e_stack++) = result;
      break;

    case CF_INMAT:
      /* A name that is not there reads as a null string: no elements */
      descr = e_stack - 1;
      while (descr->type == ADDR)
        descr = descr->data.d_addr;
      InitDescr(&result, INTEGER);
      if (descr->type == STRING && descr->data.str.saddr == NULL)
        result.data.value = 0;
      else
        result.data.value = need_coll(descr)->count;
      k_dismiss();
      *(e_stack++) = result;
      break;

    case CF_MATCOPY:
      descr = e_stack - 1;
      GetInt(descr);
      max = descr->data.value;
      descr = e_stack - 2;
      while (descr->type == ADDR)
        descr = descr->data.d_addr;
      if (!matrix_span(descr, &ahdr, &first, &count))
        k_error("A dimensioned matrix is required by MAT()");
      if (max > 0 && count > max)
        count = max;
      InitDescr(&result, COLL);
      root = coll_new(TRUE);
      result.data.coll = root;
      for (i = 0; i < count; i++) {
        coll_insert(root, i);
        ent = &root->e[i];
        descr = Element(ahdr, first + i);
        if (descr->type == ADDR) {
          InitDescr(&ent->d, STRING);
          ent->d.data.str.saddr = NULL;
        } else {
          fill_entry(ent, descr);
        }
      }
      k_pop(2); /* The matrix is an ADDR and the maximum an integer */
      *(e_stack++) = result;
      break;

    case CF_MATGET:
      root = need_array(e_stack - 1);
      descr = e_stack - 2;
      while (descr->type == ADDR)
        descr = descr->data.d_addr;
      if (!matrix_span(descr, &ahdr, &first, &count))
        k_error("A dimensioned matrix is required by MAT");
      if (count > root->count)
        count = root->count;
      for (i = 0; i < count; i++) {
        descr = Element(ahdr, first + i);
        Release(descr);
        *descr = value_of(&root->e[i]);
      }
      k_dismiss();
      k_pop(1); /* The matrix, an ADDR */
      break;

    case CF_JNULL:
      InitDescr(&result, STRING);
      result.data.str.saddr = NULL;
      result.flags = DF_JSON;
      *(e_stack++) = result;
      break;

    case CF_JBOOLEAN:
      descr = e_stack - 1;
      if (descr->type == ADDR)
        k_get_value(descr);
      switch (descr->type) {
        case INTEGER:
          n = (descr->data.value != 0);
          break;
        case FLOATNUM:
          n = (descr->data.float_value != 0.0);
          break;
        case STRING:
          /* Null, 0 and false (in any case) are false; any other text is true */
          if (descr->data.str.saddr == NULL) {
            n = 0;
          } else {
            char* jb = chunks_to_buffer(descr->data.str.saddr, &count);
            n = !(strcmp(jb, "0") == 0 || strcasecmp(jb, "false") == 0);
            k_free(jb);
          }
          break;
        default:
          n = 1;
      }
      k_dismiss();
      InitDescr(&result, INTEGER);
      result.data.value = n;
      result.flags = DF_JSON;
      *(e_stack++) = result;
      break;

    case CF_JTYPE:
      descr = e_stack - 1;
      if (descr->type == ADDR)
        k_get_value(descr);
      {
        const char* tn;
        switch (descr->type) {
          case INTEGER:
            tn = ((descr->flags & DF_JSON) && (descr->data.value == 0 || descr->data.value == 1)) ? "boolean" : "number";
            break;
          case FLOATNUM:
            tn = "number";
            break;
          case STRING:
            tn = ((descr->flags & DF_JSON) && descr->data.str.saddr == NULL) ? "null" : "string";
            break;
          case COLL:
            tn = descr->data.coll->is_array ? "array" : "collection";
            break;
          default:
            tn = "other";
        }
        result = str_descr((char*)tn, (int32_t)strlen(tn));
      }
      k_dismiss();
      *(e_stack++) = result;
      break;

    case CF_JPARSE:
      descr = e_stack - 1;
      GetInt(descr);
      max = descr->data.value; /* The mode */
      descr = e_stack - 2;
      GetString(descr);
      {
        int32_t jlen;
        char* jbuf = chunks_to_buffer(descr->data.str.saddr, &jlen);
        result = json_parse(jbuf, jlen, (int)max);
        k_free(jbuf);
      }
      k_pop(1);
      k_dismiss();
      *(e_stack++) = result;
      break;

    case CF_JBUILD:
      descr = e_stack - 1;
      GetInt(descr);
      max = descr->data.value; /* The mode */
      root = need_coll(e_stack - 2);
      result = json_build(root, (int)max);
      k_pop(1);
      k_dismiss();
      *(e_stack++) = result;
      break;

    case CF_GET:
    case CF_EXISTS:
    case CF_DEL:
    case CF_SET:
    case CF_SETOP:
    case CF_INS:
      /* Find the pieces on the stack, whichever way round this function has them */
      drop = 0;
      value = NULL;
      if (func == CF_SETOP) {
        descr = e_stack - 1;
        GetInt(descr);
        setop = descr->data.value; /* 1 add, 2 subtract, 3 multiply, 4 divide, 5 concatenate */
        k_pop(1);
      }
      if (func == CF_SET || func == CF_SETOP) {
        value = e_stack - 1;
        if (value->type == ADDR)
          k_get_value(value);
        descr = e_stack - 2;
        drop = 1; /* The value is dismissed with the rest */
      } else {
        descr = e_stack - 1;
      }
      GetInt(descr);
      n = descr->data.value;
      comps = descr - n;
      rootd = comps - 1; /* The collection, or an ADDR to the variable that holds it */
      if (func == CF_INS) {
        value = rootd - 1; /* INS compiles the value first */
        if (value->type == ADDR)
          k_get_value(value);
      }
      while (rootd->type == ADDR)
        rootd = rootd->data.d_addr;
      root = need_coll(rootd);

      nseg = split_path(comps, n, &segs, &bufs);
      if (nseg < 0) {
        free_path(segs, bufs, n);
        k_error(sysmsg(12127), "");
      }

      star = FALSE;
      for (i = 0; i < nseg; i++)
        if (segs[i].len == 1 && segs[i].p[0] == '*')
          star = TRUE;
      if (star && func != CF_GET) {
        free_path(segs, bufs, n);
        k_error(sysmsg(12127), "*");
      }

      process.status = 0;
      parent = NULL;
      pos = 0;
      exists = FALSE;

      if (star) {
        /* ELEMENT.EXISTS and the rest never reach here; this is a GET */
        int stars = 0;
        for (i = 0; i < nseg; i++)
          if (segs[i].len == 1 && segs[i].p[0] == '*')
            stars++;
        if (stars > 2) {
          free_path(segs, bufs, n);
          k_error(sysmsg(12127), "*");
        }
        cb.b = (char*)k_alloc(COLL_ALLOC_TAG, 64);
        cb.len = 0;
        cb.cap = 64;
        star_get(&cb, root, segs, nseg, 0, 0);
        InitDescr(&result, STRING);
        result.data.str.saddr = NULL;
        if (cb.len > 0) {
          ts_init(&result.data.str.saddr, cb.len + 1);
          ts_copy(cb.b, cb.len);
          ts_terminate();
        }
        k_free(cb.b);
        for (i = 0; i < n + 1; i++)
          k_dismiss();
        k_dismiss(); /* The collection */
        *(e_stack++) = result;
        free_path(segs, bufs, n);
        break;
      }

      rc = walk(root, segs, nseg, (func == CF_SET || func == CF_SETOP || func == CF_INS), &parent, &pos, &exists);
      if (rc < 0) {
        char shown[64];
        int32_t m = (segs[0].len < 60) ? segs[0].len : 60;
        memcpy(shown, segs[0].p, m);
        shown[m] = '\0';
        free_path(segs, bufs, n);
        k_error(sysmsg(rc == -2 ? 12128 : 12127), shown);
      }

      switch (func) {
        case CF_GET:
          if (rc == 0 && exists) {
            /* Take the value before dropping the collection, which may be the
               last reference to it */
            result = value_of(&parent->e[pos]);
          } else {
            process.status = ER_NOT_FOUND;
            InitDescr(&result, STRING);
            result.data.str.saddr = NULL;
          }
          for (i = 0; i < n + 1; i++)
            k_dismiss();
          k_dismiss(); /* The collection */
          *(e_stack++) = result;
          break;

        case CF_EXISTS:
          for (i = 0; i < n + 1; i++)
            k_dismiss();
          k_dismiss();
          InitDescr(&result, INTEGER);
          result.data.value = (rc == 0 && exists) ? 1 : 0;
          *(e_stack++) = result;
          break;

        case CF_DEL:
          if (rc == 0 && exists) {
            coll_remove(parent, pos);
          } else {
            process.status = ER_NOT_FOUND;
          }
          for (i = 0; i < n + 1; i++)
            k_dismiss();
          k_pop(1); /* The ADDR */
          break;

        case CF_SETOP:
          /* Work the new value out from the old one with the ordinary operator, then store it */
          if (!exists) {
            coll_insert(parent, pos);
            ent = &parent->e[pos];
            if (!parent->is_array)
              set_entry_name(ent, &segs[nseg - 1]);
          } else {
            ent = &parent->e[pos];
          }
          {
            DESCRIPTOR cur = value_of(ent);
            DESCRIPTOR val = *value;
            DESCRIPTOR res;

            IncrRefCt(&val);
            cur.flags = 0;
            val.flags = 0;
            *(e_stack++) = cur;
            *(e_stack++) = val;
            switch (setop) {
              case 1: op_add(); break;
              case 2: op_sub(); break;
              case 3: op_mul(); break;
              case 4: op_div(); break;
              default: op_cat(); break;
            }
            res = *(--e_stack);
            k_release(&ent->d);
            fill_entry(ent, &res);
            k_release(&res);
          }
          k_dismiss(); /* The value */
          for (i = 0; i < n + 1; i++)
            k_dismiss();
          k_pop(1); /* The ADDR */
          break;

        case CF_SET:
        case CF_INS:
          if (!exists || (func == CF_INS && parent->is_array)) {
            /* A new element; in an array INS opens a gap, so the rest move up */
            coll_insert(parent, pos);
            ent = &parent->e[pos];
            if (!parent->is_array)
              set_entry_name(ent, &segs[nseg - 1]);
          } else {
            ent = &parent->e[pos];
            k_release(&ent->d);
          }
          fill_entry(ent, value);
          if (func == CF_SET) {
            k_dismiss(); /* The value */
            for (i = 0; i < n + 1; i++)
              k_dismiss();
            k_pop(1); /* The ADDR */
          } else {
            for (i = 0; i < n + 1; i++)
              k_dismiss();
            k_pop(1);   /* The ADDR */
            k_dismiss(); /* The value, which is below it */
          }
          break;
      }
      (void)drop;

      free_path(segs, bufs, n);
      break;

    default:
      k_error("Invalid data collection function %d", (int)func);
  }
}

/* ======================================================================
   need_coll()  -  The collection a descriptor refers to                   */

Private COLL_HEADER* need_coll(DESCRIPTOR* d) {
  while (d->type == ADDR)
    d = d->data.d_addr;
  if (d->type != COLL)
    k_error(sysmsg(12126));
  return d->data.coll;
}

Private COLL_HEADER* need_array(DESCRIPTOR* d) {
  COLL_HEADER* h = need_coll(d);

  if (!h->is_array)
    k_error(sysmsg(12130));
  return h;
}

/* ======================================================================
   matrix_span()  -  The elements of a dimensioned matrix

   Gives the header, the offset of element 1 and the number of elements,
   row by row for a two dimensional one.  False if d is not a matrix.      */

Private bool matrix_span(DESCRIPTOR* d, ARRAY_HEADER** hdr, int32_t* first, int32_t* count) {
  PMATRIX_HEADER* pm;

  switch (d->type) {
    case ARRAY:
      *hdr = d->data.ahdr_addr;
      if ((*hdr)->flags & AH_PICK_STYLE) {
        *first = 0;
        *count = (*hdr)->used_elements;
      } else {
        *first = 1; /* Element 0 is not part of the matrix */
        *count = (*hdr)->used_elements - 1;
      }
      return TRUE;

    case PMATRIX:
      pm = d->data.pmatrix;
      *hdr = pm->com_descr->data.ahdr_addr;
      *first = pm->base_offset;
      *count = (pm->cols == 0) ? pm->rows : pm->cols * pm->rows;
      return TRUE;
  }
  return FALSE;
}

/* ======================================================================
   coll_new() and coll_copy()                                             */

Private COLL_HEADER* coll_new(bool is_array) {
  COLL_HEADER* h;

  h = (COLL_HEADER*)k_alloc(COLL_ALLOC_TAG, sizeof(COLL_HEADER));
  h->ref_ct = 1;
  h->is_array = is_array;
  h->count = 0;
  h->alloc = 0;
  h->e = NULL;
  return h;
}

/* A copy is independent: nested collections are copied too */

Private COLL_HEADER* coll_copy(COLL_HEADER* src) {
  COLL_HEADER* h;
  int32_t i;
  COLL_ENTRY* s;
  COLL_ENTRY* t;

  h = coll_new(src->is_array);
  for (i = 0; i < src->count; i++) {
    coll_insert(h, i);
    s = &src->e[i];
    t = &h->e[i];
    if (s->name != NULL) {
      t->name = (char*)k_alloc(COLL_ALLOC_TAG, s->name_len + 1);
      memcpy(t->name, s->name, s->name_len + 1);
      t->name_len = s->name_len;
    }
    t->tag = s->tag;
    if (s->d.type == COLL) {
      InitDescr(&t->d, COLL);
      t->d.data.coll = coll_copy(s->d.data.coll);
    } else {
      t->d = s->d;
      t->d.flags = 0;
      IncrRefCt(&t->d);
    }
  }
  return h;
}

Private void coll_free_entry(COLL_ENTRY* e) {
  if (e->name != NULL)
    k_free(e->name);
  e->name = NULL;
  k_release(&e->d);
}

Private void set_entry_name(COLL_ENTRY* ent, COLL_SEG* seg) {
  ent->name = (char*)k_alloc(COLL_ALLOC_TAG, seg->len + 1);
  memcpy(ent->name, seg->p, seg->len);
  ent->name[seg->len] = '\0';
  ent->name_len = seg->len;
}

/* ======================================================================
   coll_find()  -  Binary search of an object's sorted names               */

Private bool coll_find(COLL_HEADER* h, char* name, int32_t len, int32_t* pos) {
  int32_t lo = 0;
  int32_t hi = h->count - 1;
  int32_t mid;
  int32_t m;
  int c;

  while (lo <= hi) {
    mid = (lo + hi) / 2;
    m = (h->e[mid].name_len < len) ? h->e[mid].name_len : len;
    c = memcmp(h->e[mid].name, name, m);
    if (c == 0)
      c = (h->e[mid].name_len < len) ? -1 : (h->e[mid].name_len > len) ? 1 : 0;
    if (c == 0) {
      *pos = mid;
      return TRUE;
    }
    if (c < 0)
      lo = mid + 1;
    else
      hi = mid - 1;
  }
  *pos = lo;
  return FALSE;
}

/* Open a blank entry at pos */

Private void coll_insert(COLL_HEADER* h, int32_t pos) {
  COLL_ENTRY* e;

  if (h->count >= h->alloc) {
    int32_t na = (h->alloc) ? h->alloc * 2 : 4;
    e = (COLL_ENTRY*)k_alloc(COLL_ALLOC_TAG, na * sizeof(COLL_ENTRY));
    if (h->count)
      memcpy(e, h->e, h->count * sizeof(COLL_ENTRY));
    if (h->e != NULL)
      k_free(h->e);
    h->e = e;
    h->alloc = na;
  }
  if (pos < h->count)
    memmove(&h->e[pos + 1], &h->e[pos], (h->count - pos) * sizeof(COLL_ENTRY));
  h->count++;
  memset(&h->e[pos], 0, sizeof(COLL_ENTRY));
  InitDescr(&h->e[pos].d, STRING);
  h->e[pos].d.data.str.saddr = NULL;
}

Private void coll_remove(COLL_HEADER* h, int32_t pos) {
  coll_free_entry(&h->e[pos]);
  if (pos < h->count - 1)
    memmove(&h->e[pos], &h->e[pos + 1], (h->count - pos - 1) * sizeof(COLL_ENTRY));
  h->count--;
}

/* ======================================================================
   chunks_to_buffer()  -  A string as a contiguous buffer (caller frees)   */

Private char* chunks_to_buffer(STRING_CHUNK* s, int32_t* len) {
  char* buf;
  int32_t total = 0;
  STRING_CHUNK* c;
  int32_t at = 0;

  for (c = s; c != NULL; c = c->next)
    total += c->bytes;
  buf = (char*)k_alloc(COLL_ALLOC_TAG, total + 1);
  for (c = s; c != NULL; c = c->next) {
    memcpy(buf + at, c->data, c->bytes);
    at += c->bytes;
  }
  buf[total] = '\0';
  *len = total;
  return buf;
}

Private void free_path(COLL_SEG* segs, char** bufs, int n) {
  int i;

  if (bufs != NULL) {
    for (i = 0; i < n; i++)
      if (bufs[i] != NULL)
        k_free(bufs[i]);
    k_free(bufs);
  }
  if (segs != NULL)
    k_free(segs);
}

/* ======================================================================
   split_path()  -  The n path components as a list of names

   Returns the number of names, or -1 if there are none or one is empty.
   *bufs_out holds n buffers, one per component, that the names point into;
   the caller frees them and *segs_out.                                   */

Private int split_path(DESCRIPTOR* comps, int n, COLL_SEG** segs_out, char*** bufs_out) {
  COLL_SEG* segs;
  char** bufs;
  int32_t total = 0;
  int nseg = 0;
  int i;
  int32_t len;
  int32_t j;
  int32_t start;
  DESCRIPTOR* d;
  char* b;

  bufs = (char**)k_alloc(COLL_ALLOC_TAG, (n + 1) * sizeof(char*));
  for (i = 0; i < n; i++)
    bufs[i] = NULL;

  /* Upper bound on the names: every byte could be a slash */
  for (i = 0; i < n; i++) {
    d = &comps[i];
    if (d->type != INTEGER) {
      GetString(d);
      total += (d->data.str.saddr != NULL) ? d->data.str.saddr->string_len + 1 : 1;
    } else {
      total += 1;
    }
  }
  segs = (COLL_SEG*)k_alloc(COLL_ALLOC_TAG, (total + 1) * sizeof(COLL_SEG));

  for (i = 0; i < n; i++) {
    d = &comps[i];
    if (d->type == INTEGER) {
      COLL_SEG* sg = &segs[nseg++];
      sprintf(sg->buf, "%d", (int)d->data.value);
      sg->p = sg->buf;
      sg->len = (int32_t)strlen(sg->buf);
      sg->numeric = TRUE;
      sg->num = d->data.value;
      bufs[i] = (char*)k_alloc(COLL_ALLOC_TAG, 1);
      continue;
    }
    b = chunks_to_buffer(d->data.str.saddr, &len);
    bufs[i] = b;
    start = 0;
    for (j = 0; j <= len; j++) {
      if (j == len || b[j] == '/') {
        COLL_SEG* sg;
        int32_t k;
        if (j == start) { /* An empty name, as in '' or 'a//b' */
          *segs_out = segs;
          *bufs_out = bufs;
          return -1;
        }
        sg = &segs[nseg++];
        sg->p = b + start;
        sg->len = j - start;
        sg->numeric = (sg->len > 0 && sg->len < 10);
        sg->num = 0;
        for (k = 0; k < sg->len && sg->numeric; k++) {
          if (sg->p[k] < '0' || sg->p[k] > '9')
            sg->numeric = FALSE;
          else
            sg->num = sg->num * 10 + (sg->p[k] - '0');
        }
        start = j + 1;
      }
    }
  }

  *segs_out = segs;
  *bufs_out = bufs;
  return (nseg > 0) ? nseg : -1;
}

/* ======================================================================
   walk()  -  Follow a path

   On return 0: *parent is the collection holding the last name and *pos the
   position of the element (*exists) or where it would go (not *exists).
   Elements that are missing on the way are made when create is set.
   Returns -1 for a bad name or array position, -2 when the way goes through
   something that is not a collection.                                     */

Private int walk(COLL_HEADER* root, COLL_SEG* seg, int nseg, bool create, COLL_HEADER** parent, int32_t* pos, bool* exists) {
  COLL_HEADER* cur = root;
  COLL_ENTRY* ent;
  int i;
  int32_t p;
  bool found;

  for (i = 0; i < nseg; i++) {
    bool last = (i == nseg - 1);

    if (cur->is_array) {
      if (!seg[i].numeric && !(seg[i].len > 1 && seg[i].p[0] == '-'))
        return -1;
      p = seg[i].num;
      if (seg[i].p[0] == '-') /* A negative position appends */
        p = cur->count + 1;
      if (p < 1)
        return -1;
      found = (p <= cur->count);
      if (!found && !(create && last && p == cur->count + 1)) {
        if (create)
          return -1; /* Undefined elements are not allowed */
        *parent = cur;
        *pos = p - 1;
        *exists = FALSE;
        return 0;
      }
      p--;
    } else {
      found = coll_find(cur, seg[i].p, seg[i].len, &p);
    }

    if (last) {
      *parent = cur;
      *pos = p;
      *exists = found;
      return 0;
    }

    if (!found) {
      if (!create) {
        *parent = cur;
        *pos = p;
        *exists = FALSE;
        return 0;
      }
      if (cur->is_array)
        return -1; /* Only the last name may add an element to an array */
      coll_insert(cur, p);
      ent = &cur->e[p];
      set_entry_name(ent, &seg[i]);
      InitDescr(&ent->d, COLL);
      ent->d.data.coll = coll_new(FALSE);
    }

    ent = &cur->e[p];
    if (ent->d.type != COLL) {
      if (!create) {
        *parent = cur;
        *pos = p;
        *exists = FALSE;
        return 0;
      }
      return -2;
    }
    cur = ent->d.data.coll;
  }

  return -1;
}

/* ======================================================================
   value_of()  -  An element's value as a stack item (a new reference)     */

Private DESCRIPTOR value_of(COLL_ENTRY* e) {
  DESCRIPTOR r;

  if (e->tag == CT_NULL) {
    InitDescr(&r, STRING);
    r.data.str.saddr = NULL;
    r.flags = DF_JSON;
  } else {
    r = e->d;
    r.flags = (e->tag == CT_BOOL) ? DF_JSON : 0;
    IncrRefCt(&r);
  }
  return r;
}

/* Put a value into an entry as a new reference.  A JSON boolean or null (see
   DF_JSON) is kept as one; an unassigned variable is a null string.       */

Private void fill_entry(COLL_ENTRY* ent, DESCRIPTOR* v) {
  ent->tag = CT_PLAIN;
  if (v->type == UNASSIGNED) {
    InitDescr(&ent->d, STRING);
    ent->d.data.str.saddr = NULL;
    return;
  }
  if (v->flags & DF_JSON) {
    if (v->type == INTEGER && (v->data.value == 0 || v->data.value == 1))
      ent->tag = CT_BOOL;
    else if (v->type == STRING && v->data.str.saddr == NULL)
      ent->tag = CT_NULL;
  }
  ent->d = *v;
  ent->d.flags = 0;
  IncrRefCt(&ent->d);
}

/* ======================================================================
   Asterisk paths

   star_get() follows seg[i] onward from cur.  Every element an asterisk
   covers is followed in turn and the results are put one after another in
   the buffer, with a value mark between those of the first asterisk and a
   subvalue mark between those of the second.  A way that does not lead to
   a value gives a null string in its place.                               */

Private void buf_add(COLL_BUF* b, char* s, int32_t len) {
  if (b->len + len + 1 > b->cap) {
    int32_t nc = b->cap * 2;
    char* nb;
    while (nc < b->len + len + 1)
      nc *= 2;
    nb = (char*)k_alloc(COLL_ALLOC_TAG, nc);
    memcpy(nb, b->b, b->len);
    k_free(b->b);
    b->b = nb;
    b->cap = nc;
  }
  memcpy(b->b + b->len, s, len);
  b->len += len;
}

/* The text of an element that holds a value */

Private void buf_value(COLL_BUF* b, COLL_ENTRY* e) {
  DESCRIPTOR t;
  char* s;
  int32_t len;

  if (e->tag == CT_NULL || e->d.type == COLL || e->d.type == UNASSIGNED)
    return;
  t = e->d;
  t.flags = 0;
  IncrRefCt(&t);
  GetString(&t);
  if (t.data.str.saddr != NULL) {
    s = chunks_to_buffer(t.data.str.saddr, &len);
    buf_add(b, s, len);
    k_free(s);
  }
  k_release(&t);
}

Private void star_get(COLL_BUF* b, COLL_HEADER* cur, COLL_SEG* seg, int nseg, int i, int star) {
  int32_t k;
  int32_t p;
  bool last = (i == nseg - 1);
  COLL_ENTRY* ent;
  char mark;

  if (seg[i].len == 1 && seg[i].p[0] == '*') {
    if (!cur->is_array)
      return;
    mark = (star == 0) ? VALUE_MARK : SUBVALUE_MARK;
    for (k = 0; k < cur->count; k++) {
      if (k)
        buf_add(b, &mark, 1);
      ent = &cur->e[k];
      if (last)
        buf_value(b, ent);
      else if (ent->d.type == COLL)
        star_get(b, ent->d.data.coll, seg, nseg, i + 1, star + 1);
    }
    return;
  }

  if (cur->is_array) {
    if (!seg[i].numeric || seg[i].num < 1 || seg[i].num > cur->count)
      return;
    p = seg[i].num - 1;
  } else if (!coll_find(cur, seg[i].p, seg[i].len, &p)) {
    return;
  }
  ent = &cur->e[p];
  if (last)
    buf_value(b, ent);
  else if (ent->d.type == COLL)
    star_get(b, ent->d.data.coll, seg, nseg, i + 1, star);
}

/* ======================================================================
   JSON

   json_parse() turns text into a collection (an object becomes a
   collection, an array an array; true and false are kept as booleans and
   null as a null, so that JBUILD() writes them back as they came).  On
   failure it returns a null string, sets STATUS to ER_PARSE_ERROR and
   INMAT() to the position of the character where it went wrong.

   Spaces, tabs, returns, line feeds and all five mark characters between
   elements are ignored.  Names and strings may be in double or single
   quotes.  \uXXXX is the byte XX when it is 255 or less, so a mark or
   an 8 bit character written by JBUILD() comes back as it was, and UTF-8
   above that.  A number that is a whole number within 32 bits is an integer;
   any other is a floating point number.                                   */

#include <errno.h>
#include <math.h>
#include <stdlib.h>

typedef struct {
  unsigned char* s;
  int32_t len;
  int32_t pos;
  int mode;
} JP;

Private bool jp_value(JP* jp, COLL_ENTRY* out, int depth);

Private void jp_ws(JP* jp) {
  unsigned char c;

  while (jp->pos < jp->len) {
    c = jp->s[jp->pos];
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || (c >= 0xFB))
      jp->pos++;
    else
      break;
  }
}

Private int jp_hex4(JP* jp, int32_t at) {
  int v = 0;
  int i;
  char c;

  if (at + 4 > jp->len)
    return -1;
  for (i = 0; i < 4; i++) {
    c = jp->s[at + i];
    v <<= 4;
    if (c >= '0' && c <= '9')
      v |= c - '0';
    else if (c >= 'a' && c <= 'f')
      v |= c - 'a' + 10;
    else if (c >= 'A' && c <= 'F')
      v |= c - 'A' + 10;
    else
      return -1;
  }
  return v;
}

/* Decode a quoted string.  The caller frees *out. */

Private bool jp_string(JP* jp, char** out, int32_t* outlen) {
  char quote = (char)jp->s[jp->pos];
  char* b = (char*)k_alloc(COLL_ALLOC_TAG, jp->len - jp->pos + 8);
  int32_t n = 0;
  unsigned char c;
  int cp;
  int lo;

  jp->pos++;
  while (jp->pos < jp->len) {
    c = jp->s[jp->pos];
    if (c == (unsigned char)quote) {
      jp->pos++;
      b[n] = '\0';
      *out = b;
      *outlen = n;
      return TRUE;
    }
    if (c != '\\') {
      b[n++] = c;
      jp->pos++;
      continue;
    }
    jp->pos++;
    if (jp->pos >= jp->len)
      break;
    c = jp->s[jp->pos];
    switch (c) {
      case '"': b[n++] = '"'; jp->pos++; break;
      case '\'': b[n++] = '\''; jp->pos++; break;
      case '\\': b[n++] = '\\'; jp->pos++; break;
      case '/': b[n++] = '/'; jp->pos++; break;
      case 'b': b[n++] = '\b'; jp->pos++; break;
      case 'f': b[n++] = '\f'; jp->pos++; break;
      case 'n': b[n++] = '\n'; jp->pos++; break;
      case 'r': b[n++] = '\r'; jp->pos++; break;
      case 't': b[n++] = '\t'; jp->pos++; break;
      case 'u':
        cp = jp_hex4(jp, jp->pos + 1);
        if (cp < 0) {
          k_free(b);
          return FALSE;
        }
        jp->pos += 5;
        if (cp >= 0xD800 && cp <= 0xDBFF && jp->pos + 1 < jp->len && jp->s[jp->pos] == '\\' && jp->s[jp->pos + 1] == 'u') {
          lo = jp_hex4(jp, jp->pos + 2);
          if (lo >= 0xDC00 && lo <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            jp->pos += 6;
          }
        }
        if (cp <= 0xFF) {
          b[n++] = (char)cp; /* A byte, so marks and 8 bit data round trip */
        } else if (cp <= 0x7FF) {
          b[n++] = (char)(0xC0 | (cp >> 6));
          b[n++] = (char)(0x80 | (cp & 0x3F));
        } else if (cp <= 0xFFFF) {
          b[n++] = (char)(0xE0 | (cp >> 12));
          b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F));
          b[n++] = (char)(0x80 | (cp & 0x3F));
        } else {
          b[n++] = (char)(0xF0 | (cp >> 18));
          b[n++] = (char)(0x80 | ((cp >> 12) & 0x3F));
          b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F));
          b[n++] = (char)(0x80 | (cp & 0x3F));
        }
        break;
      default:
        k_free(b);
        return FALSE;
    }
  }
  k_free(b);
  return FALSE; /* No closing quote */
}

Private DESCRIPTOR str_descr(char* s, int32_t len) {
  DESCRIPTOR d;

  InitDescr(&d, STRING);
  d.data.str.saddr = NULL;
  if (len > 0) {
    ts_init(&d.data.str.saddr, len + 1);
    ts_copy(s, len);
    ts_terminate();
  }
  return d;
}

/* How many bytes of s are a JSON number, 0 if none */

Private int32_t json_number_len(unsigned char* s, int32_t len, bool* is_int) {
  int32_t i = 0;

  *is_int = TRUE;
  if (i < len && s[i] == '-')
    i++;
  if (i >= len || s[i] < '0' || s[i] > '9')
    return 0;
  if (s[i] == '0') {
    i++;
  } else {
    while (i < len && s[i] >= '0' && s[i] <= '9')
      i++;
  }
  if (i < len && s[i] == '.') {
    i++;
    if (i >= len || s[i] < '0' || s[i] > '9')
      return 0;
    while (i < len && s[i] >= '0' && s[i] <= '9')
      i++;
    *is_int = FALSE;
  }
  if (i < len && (s[i] == 'e' || s[i] == 'E')) {
    i++;
    if (i < len && (s[i] == '+' || s[i] == '-'))
      i++;
    if (i >= len || s[i] < '0' || s[i] > '9')
      return 0;
    while (i < len && s[i] >= '0' && s[i] <= '9')
      i++;
    *is_int = FALSE;
  }
  return i;
}

Private bool jp_value(JP* jp, COLL_ENTRY* out, int depth) {
  unsigned char c;
  COLL_HEADER* h;
  COLL_ENTRY* ent;
  char* str;
  int32_t slen;
  int32_t p;
  int32_t n;
  bool is_int;
  bool found;
  char tmp[64];

  if (depth > JSON_MAX_DEPTH)
    return FALSE;
  jp_ws(jp);
  if (jp->pos >= jp->len)
    return FALSE;
  c = jp->s[jp->pos];

  if (c == '{' || c == '[') {
    bool obj = (c == '{');
    unsigned char close = obj ? '}' : ']';

    h = coll_new(!obj);
    InitDescr(&out->d, COLL);
    out->d.data.coll = h;
    out->tag = CT_PLAIN;
    jp->pos++;
    jp_ws(jp);
    if (jp->pos < jp->len && jp->s[jp->pos] == close) {
      jp->pos++;
      return TRUE;
    }
    for (;;) {
      jp_ws(jp);
      if (jp->pos >= jp->len)
        return FALSE;
      if (obj) {
        c = jp->s[jp->pos];
        if (c == '"' || c == '\'') {
          if (!jp_string(jp, &str, &slen))
            return FALSE;
        } else if ((jp->mode & JP_UNQUOTED_NAME_BIT) && (isalpha(c) || c == '_' || c == '$')) {
          int32_t st = jp->pos;
          while (jp->pos < jp->len && (isalnum(jp->s[jp->pos]) || jp->s[jp->pos] == '_' || jp->s[jp->pos] == '$' ||
                                       jp->s[jp->pos] == '.' || jp->s[jp->pos] == '-'))
            jp->pos++;
          slen = jp->pos - st;
          str = (char*)k_alloc(COLL_ALLOC_TAG, slen + 1);
          memcpy(str, jp->s + st, slen);
          str[slen] = '\0';
        } else {
          return FALSE;
        }
        jp_ws(jp);
        if (jp->pos >= jp->len || jp->s[jp->pos] != ':') {
          k_free(str);
          return FALSE;
        }
        jp->pos++;
        found = coll_find(h, str, slen, &p);
        if (found) {
          ent = &h->e[p];
          k_release(&ent->d);
          InitDescr(&ent->d, STRING);
          ent->d.data.str.saddr = NULL;
        } else {
          coll_insert(h, p);
          ent = &h->e[p];
          ent->name = str;
          ent->name_len = slen;
          str = NULL;
        }
        if (str != NULL)
          k_free(str);
      } else {
        coll_insert(h, h->count);
        ent = &h->e[h->count - 1];
      }
      if (!jp_value(jp, ent, depth + 1))
        return FALSE;
      jp_ws(jp);
      if (jp->pos >= jp->len)
        return FALSE;
      c = jp->s[jp->pos];
      if (c == ',') {
        jp->pos++;
        continue;
      }
      if (c == close) {
        jp->pos++;
        return TRUE;
      }
      return FALSE;
    }
  }

  if (c == '"' || c == '\'') {
    if (!jp_string(jp, &str, &slen))
      return FALSE;
    out->d = str_descr(str, slen);
    out->tag = CT_PLAIN;
    k_free(str);
    return TRUE;
  }

  if (c == '-' || (c >= '0' && c <= '9')) {
    n = json_number_len(jp->s + jp->pos, jp->len - jp->pos, &is_int);
    if (n == 0 || n > 60)
      return FALSE;
    memcpy(tmp, jp->s + jp->pos, n);
    tmp[n] = '\0';
    jp->pos += n;
    out->tag = CT_PLAIN;
    if (is_int) {
      errno = 0;
      long v = strtol(tmp, NULL, 10);
      if (errno == 0 && v >= -2147483647L && v <= 2147483647L) {
        InitDescr(&out->d, INTEGER);
        out->d.data.value = (int32_t)v;
        return TRUE;
      }
    }
    InitDescr(&out->d, FLOATNUM);
    out->d.data.float_value = strtod(tmp, NULL);
    return TRUE;
  }

  if (jp->len - jp->pos >= 4 && memcmp(jp->s + jp->pos, "true", 4) == 0) {
    jp->pos += 4;
    InitDescr(&out->d, INTEGER);
    out->d.data.value = 1;
    out->tag = CT_BOOL;
    return TRUE;
  }
  if (jp->len - jp->pos >= 5 && memcmp(jp->s + jp->pos, "false", 5) == 0) {
    jp->pos += 5;
    InitDescr(&out->d, INTEGER);
    out->d.data.value = 0;
    out->tag = CT_BOOL;
    return TRUE;
  }
  if (jp->len - jp->pos >= 4 && memcmp(jp->s + jp->pos, "null", 4) == 0) {
    jp->pos += 4;
    InitDescr(&out->d, STRING);
    out->d.data.str.saddr = NULL;
    out->tag = (jp->mode & JP_NULL_BIT) ? CT_PLAIN : CT_NULL;
    return TRUE;
  }
  return FALSE;
}

Private DESCRIPTOR json_parse(char* text, int32_t len, int mode) {
  JP jp;
  COLL_ENTRY top;
  DESCRIPTOR result;

  jp.s = (unsigned char*)text;
  jp.len = len;
  jp.pos = 0;
  jp.mode = mode;
  memset(&top, 0, sizeof top);
  InitDescr(&top.d, STRING);
  top.d.data.str.saddr = NULL;

  jp_ws(&jp);
  if (jp.pos < jp.len && (jp.s[jp.pos] == '{' || jp.s[jp.pos] == '[') && jp_value(&jp, &top, 0)) {
    jp_ws(&jp);
    if (jp.pos == jp.len) {
      process.status = 0;
      result = top.d;
      return result;
    }
  }

  /* Failed: give back what was built, say where */
  k_release(&top.d);
  process.status = ER_PARSE_ERROR;
  process.inmat = jp.pos + 1;
  InitDescr(&result, STRING);
  result.data.str.saddr = NULL;
  return result;
}

/* ----------------------------------------------------------------------
   json_build()  -  A collection as JSON text

   Compact: no spaces.  Names are in the collection's order.  A string
   goes out in quotes unless JB_NUM is set and it is a number, or JB_NULL
   is set and it is empty.  Every mark, control character and byte of 8 bits
   or more inside a string is written as \u00XX, which is both valid JSON
   and what JPARSE() reads back as the same byte.  A value with no JSON
   form (a file variable, say) makes the whole build fail, or is a null
   when JB_INVALID is set.                                                */

Private bool jb_value(COLL_BUF* b, COLL_ENTRY* e, int mode, int depth);

Private void jb_str(COLL_BUF* b, unsigned char* s, int32_t len, int quote) {
  int32_t i;
  char t[8];
  unsigned char c;

  if (quote)
    buf_add(b, (char*)&quote, 1);
  for (i = 0; i < len; i++) {
    c = s[i];
    if (quote && c == (unsigned char)quote) {
      t[0] = '\\';
      t[1] = (char)c;
      buf_add(b, t, 2);
    } else if (c == '\\') {
      buf_add(b, "\\\\", 2);
    } else if (c == '\b') {
      buf_add(b, "\\b", 2);
    } else if (c == '\f') {
      buf_add(b, "\\f", 2);
    } else if (c == '\n') {
      buf_add(b, "\\n", 2);
    } else if (c == '\r') {
      buf_add(b, "\\r", 2);
    } else if (c == '\t') {
      buf_add(b, "\\t", 2);
    } else if (c < 0x20 || c >= 0x80) {
      sprintf(t, "\\u%04x", c);
      buf_add(b, t, 6);
    } else {
      buf_add(b, (char*)&s[i], 1);
    }
  }
  if (quote)
    buf_add(b, (char*)&quote, 1);
}

Private bool jb_value(COLL_BUF* b, COLL_ENTRY* e, int mode, int depth) {
  char t[64];
  char* s;
  int32_t len;
  int32_t i;
  bool is_int;
  int vq;
  int nq;
  int n;
  COLL_HEADER* h;
  DESCRIPTOR d;

  if (depth > JSON_MAX_DEPTH)
    return FALSE;

  if (e->tag == CT_NULL) {
    buf_add(b, "null", 4);
    return TRUE;
  }
  if (e->tag == CT_BOOL) {
    if (e->d.data.value)
      buf_add(b, "true", 4);
    else
      buf_add(b, "false", 5);
    return TRUE;
  }

  switch (e->d.type) {
    case INTEGER:
      sprintf(t, "%d", (int)e->d.data.value);
      buf_add(b, t, (int32_t)strlen(t));
      return TRUE;

    case FLOATNUM:
      if (isnan(e->d.data.float_value) || isinf(e->d.data.float_value))
        return FALSE;
      sprintf(t, "%.15g", e->d.data.float_value);
      if (strtod(t, NULL) != e->d.data.float_value)
        sprintf(t, "%.17g", e->d.data.float_value);
      buf_add(b, t, (int32_t)strlen(t));
      return TRUE;

    case STRING:
      s = chunks_to_buffer(e->d.data.str.saddr, &len);
      if ((mode & JB_NULL_BIT) && len == 0) {
        buf_add(b, "null", 4);
      } else if ((mode & JB_NUM_BIT) && len > 0 && json_number_len((unsigned char*)s, len, &is_int) == len) {
        buf_add(b, s, len);
      } else {
        vq = (mode & JB_NOQUOTE_VALUE_BIT) ? 0 : (mode & JB_SQUOTE_VALUE_BIT) ? '\'' : '"';
        jb_str(b, (unsigned char*)s, len, vq);
      }
      k_free(s);
      return TRUE;

    case COLL:
      h = e->d.data.coll;
      buf_add(b, h->is_array ? "[" : "{", 1);
      nq = (mode & JB_NOQUOTE_NAME_BIT) ? 0 : (mode & JB_SQUOTE_NAME_BIT) ? '\'' : '"';
      for (i = 0; i < h->count; i++) {
        if (i)
          buf_add(b, ",", 1);
        if (mode & JB_PRETTY_BIT) { /* One element to a line, two spaces for each level */
          buf_add(b, "\n", 1);
          for (n = 0; n <= depth; n++)
            buf_add(b, "  ", 2);
        }
        if (!h->is_array) {
          jb_str(b, (unsigned char*)h->e[i].name, h->e[i].name_len, nq);
          buf_add(b, (mode & JB_PRETTY_BIT) ? ": " : ":", (mode & JB_PRETTY_BIT) ? 2 : 1);
        }
        if (!jb_value(b, &h->e[i], mode, depth + 1))
          return FALSE;
      }
      if ((mode & JB_PRETTY_BIT) && h->count) {
        buf_add(b, "\n", 1);
        for (n = 0; n < depth; n++)
          buf_add(b, "  ", 2);
      }
      buf_add(b, h->is_array ? "]" : "}", 1);
      return TRUE;

    default:
      (void)d;
      if (mode & JB_INVALID_BIT) {
        buf_add(b, "null", 4);
        return TRUE;
      }
      return FALSE;
  }
}

Private DESCRIPTOR json_build(COLL_HEADER* root, int mode) {
  COLL_BUF cb;
  COLL_ENTRY top;
  DESCRIPTOR result;
  bool ok;

  cb.b = (char*)k_alloc(COLL_ALLOC_TAG, 256);
  cb.len = 0;
  cb.cap = 256;

  /* The root as an entry, without taking a reference */
  memset(&top, 0, sizeof top);
  InitDescr(&top.d, COLL);
  top.d.data.coll = root;
  ok = jb_value(&cb, &top, mode, 0);

  if (!ok) {
    k_free(cb.b);
    process.status = ER_BUILD_ERROR;
    InitDescr(&result, STRING);
    result.data.str.saddr = NULL;
    return result;
  }
  process.status = 0;
  result = str_descr(cb.b, cb.len);
  k_free(cb.b);
  return result;
}

/* ======================================================================
   Records of a data collection file

   The file is an ordinary hashed file whose records are JSON text.  READ
   turns the text into a collection and WRITE the collection into text.

   coll_record_in()   STRING -> COLL, in place.  False if the text is not a
                      JSON object or array, d unchanged.
   coll_record_text() COLL -> STRING of JSON text, in place (False and d
                      unchanged if the collection cannot be built).  A STRING
                      is checked to be JSON an object or array and left as it
                      is; False if it is not.                              */

bool coll_record_in(DESCRIPTOR* d) {
  DESCRIPTOR r;
  char* b;
  int32_t len;
  int32_t saved_inmat = process.inmat;

  if (d->type != STRING)
    return FALSE;
  b = chunks_to_buffer(d->data.str.saddr, &len);
  r = json_parse(b, len, 0);
  k_free(b);
  process.inmat = saved_inmat;
  if (r.type != COLL)
    return FALSE;
  k_release(d);
  *d = r;
  return TRUE;
}

bool coll_record_text(DESCRIPTOR* d) {
  DESCRIPTOR r;
  char* b;
  int32_t len;
  int32_t saved_inmat = process.inmat;

  if (d->type == COLL) {
    r = json_build(d->data.coll, 0);
    if (process.status == ER_BUILD_ERROR)
      return FALSE;
    k_release(d);
    *d = r;
    return TRUE;
  }
  if (d->type != STRING)
    return FALSE;
  b = chunks_to_buffer(d->data.str.saddr, &len);
  r = json_parse(b, len, 0);
  k_free(b);
  process.inmat = saved_inmat;
  if (r.type != COLL)
    return FALSE;
  k_release(&r);
  return TRUE;
}

/* ======================================================================
   OCONV(s, 'HU') and ICONV(s, 'HU')  -  percent encoding

   Everything but letters, digits and - . _ ~ is written as %xx with
   lower case hex digits, so a URL can be a name in a collection without its
   slashes being taken for a path.  ICONV undoes it; a % not followed by two
   hex digits, and a +, are left as they are.                              */

int32_t url_encode_top() {
  DESCRIPTOR* d = e_stack - 1;
  DESCRIPTOR result;
  COLL_BUF cb;
  char* s;
  int32_t len;
  int32_t i;
  unsigned char c;
  char t[4];

  k_get_string(d);
  if (d->data.str.saddr == NULL)
    return 0;
  s = chunks_to_buffer(d->data.str.saddr, &len);
  cb.b = (char*)k_alloc(COLL_ALLOC_TAG, len * 3 + 8);
  cb.len = 0;
  cb.cap = len * 3 + 8;
  for (i = 0; i < len; i++) {
    c = (unsigned char)s[i];
    if (isalnum(c) || c == '-' || c == '.' || c == '_' || c == '~') {
      cb.b[cb.len++] = (char)c;
    } else {
      sprintf(t, "%%%02x", c);
      memcpy(cb.b + cb.len, t, 3);
      cb.len += 3;
    }
  }
  result = str_descr(cb.b, cb.len);
  k_free(cb.b);
  k_free(s);
  k_dismiss();
  *(e_stack++) = result;
  return 0;
}

int32_t url_decode_top() {
  DESCRIPTOR* d = e_stack - 1;
  DESCRIPTOR result;
  char* s;
  char* o;
  int32_t len;
  int32_t i;
  int32_t n = 0;

  k_get_string(d);
  if (d->data.str.saddr == NULL)
    return 0;
  s = chunks_to_buffer(d->data.str.saddr, &len);
  o = (char*)k_alloc(COLL_ALLOC_TAG, len + 1);
  for (i = 0; i < len; i++) {
    if (s[i] == '%' && i + 2 < len && isxdigit((unsigned char)s[i + 1]) && isxdigit((unsigned char)s[i + 2])) {
      char hx[3];
      hx[0] = s[i + 1];
      hx[1] = s[i + 2];
      hx[2] = '\0';
      o[n++] = (char)strtol(hx, NULL, 16);
      i += 2;
    } else {
      o[n++] = s[i];
    }
  }
  result = str_descr(o, n);
  k_free(o);
  k_free(s);
  k_dismiss();
  *(e_stack++) = result;
  return 0;
}

/* END-CODE */
