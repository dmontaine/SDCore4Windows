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
 *
 *    A path component that is a string may hold several names separated by
 *    slashes; an integer (or a string of digits met in an array) selects an
 *    array element.  The components are one path whatever the way it was
 *    written: c{'a','b'}, c{'a'}{'b'} and c{'a/b'} are the same element.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "err.h"

#define CF_NEW 1
#define CF_COPY 2
#define CF_GET 3
#define CF_SET 4
#define CF_DEL 5
#define CF_EXISTS 6
#define CF_ENUM 7

#define COLL_ALLOC_TAG 160

/* One name in a path, after splitting on slashes */
typedef struct {
  char* p;       /* Points into the buffer that holds the whole component */
  int32_t len;
  bool numeric;  /* All digits, or an integer component */
  int32_t num;
  char buf[16];  /* Text of an integer component */
} COLL_SEG;

Private COLL_HEADER* coll_new(bool is_array);
Private COLL_HEADER* coll_copy(COLL_HEADER* src);
Private void coll_free_entry(COLL_ENTRY* e);
Private bool coll_find(COLL_HEADER* h, char* name, int32_t len, int32_t* pos);
Private void coll_insert(COLL_HEADER* h, int32_t pos);
Private void coll_remove(COLL_HEADER* h, int32_t pos);
Private COLL_HEADER* need_coll(DESCRIPTOR* d);
Private char* chunks_to_buffer(STRING_CHUNK* s, int32_t* len);
Private int split_path(DESCRIPTOR* comps, int n, COLL_SEG** segs_out, char*** bufs_out);
Private int walk(COLL_HEADER* root, COLL_SEG* seg, int nseg, bool create, COLL_HEADER** parent, int32_t* pos, bool* exists);
Private DESCRIPTOR value_of(COLL_ENTRY* e);

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
  int32_t func;
  int32_t n;
  int32_t i;
  int32_t pos;
  bool exists;
  int nseg;
  int rc;
  COLL_ENTRY* ent;

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

    case CF_GET:
    case CF_EXISTS:
    case CF_DEL:
    case CF_SET:
      /* Value to store, for SET */
      descr = e_stack - 1;
      if (func == CF_SET) {
        if (descr->type == ADDR)
          k_get_value(descr);
        descr = e_stack - 2;
      }
      GetInt(descr);
      n = descr->data.value;
      comps = descr - n;
      if (func == CF_SET) {
        descr = e_stack - 3 - n; /* ADDR to the collection variable */
        while (descr->type == ADDR)
          descr = descr->data.d_addr;
        root = need_coll(descr);
      } else if (func == CF_DEL) {
        descr = e_stack - 2 - n;
        while (descr->type == ADDR)
          descr = descr->data.d_addr;
        root = need_coll(descr);
      } else {
        root = need_coll(e_stack - 2 - n);
      }

      nseg = split_path(comps, n, &segs, &bufs);
      if (nseg < 0) {
        for (i = 0; i < n; i++)
          if (bufs[i] != NULL)
            k_free(bufs[i]);
        k_free(segs);
        k_free(bufs);
        k_error(sysmsg(12127), "");
      }

      process.status = 0;
      parent = NULL;
      pos = 0;
      exists = FALSE;
      rc = walk(root, segs, nseg, (func == CF_SET), &parent, &pos, &exists);
      if (rc < 0) {
        char shown[64];
        int32_t m = (segs[0].len < 60) ? segs[0].len : 60;
        memcpy(shown, segs[0].p, m);
        shown[m] = '\0';
        for (i = 0; i < n; i++)
          k_free(bufs[i]);
        k_free(segs);
        k_free(bufs);
        k_error(sysmsg(rc == -2 ? 12128 : 12127), shown);
      }

      switch (func) {
        case CF_GET:
          if (rc == 0 && exists) {
            /* Take the value before dropping the collection, which may be the
               last reference to it */
            result = value_of(&parent->e[pos]);
            for (i = 0; i < n + 1; i++)
              k_dismiss();
            k_dismiss(); /* The collection */
            *(e_stack++) = result;
          } else {
            process.status = ER_NOT_FOUND;
            for (i = 0; i < n + 1; i++)
              k_dismiss();
            k_dismiss();
            InitDescr(&result, STRING);
            result.data.str.saddr = NULL;
            *(e_stack++) = result;
          }
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

        case CF_SET:
          descr = e_stack - 1; /* The value */
          if (!exists) {
            coll_insert(parent, pos);
            ent = &parent->e[pos];
            if (!parent->is_array) {
              ent->name = (char*)k_alloc(COLL_ALLOC_TAG, segs[nseg - 1].len + 1);
              memcpy(ent->name, segs[nseg - 1].p, segs[nseg - 1].len);
              ent->name[segs[nseg - 1].len] = '\0';
              ent->name_len = segs[nseg - 1].len;
            }
          } else {
            ent = &parent->e[pos];
            k_release(&ent->d);
          }
          if (descr->type == UNASSIGNED) {
            InitDescr(&ent->d, STRING);
            ent->d.data.str.saddr = NULL;
          } else {
            ent->d = *descr;
            ent->d.flags = 0;
            IncrRefCt(&ent->d);
          }
          ent->tag = CT_PLAIN;
          k_dismiss(); /* The value */
          for (i = 0; i < n + 1; i++)
            k_dismiss();
          k_pop(1); /* The ADDR */
          break;
      }

      for (i = 0; i < n; i++)
        k_free(bufs[i]);
      k_free(segs);
      k_free(bufs);
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
      coll_insert(cur, p);
      ent = &cur->e[p];
      ent->name = (char*)k_alloc(COLL_ALLOC_TAG, seg[i].len + 1);
      memcpy(ent->name, seg[i].p, seg[i].len);
      ent->name[seg[i].len] = '\0';
      ent->name_len = seg[i].len;
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
  } else {
    r = e->d;
    r.flags = 0;
    IncrRefCt(&r);
  }
  return r;
}

/* END-CODE */
