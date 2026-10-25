/* OP_XML.C
 * XML text: XPARSE(), XBUILD() and XPATH()
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
 * 20 Oct 26 dm  New.  The owner's CSV / JSON / XML task: a BASIC parser for XML that gives a data collection, a builder that gives the text
 *               back, and XPath 1.0 (a subset) over the collection.  Through OP.XFUN (XF_XPARSE, XF_XBUILD, XF_XPATH).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *    An XML element is a data collection (an object) with the members
 *        name        the tag, prefix and all ("svg:rect")
 *        attributes  an object: the attributes by name (an attribute is a string; xmlns and xmlns:p are attributes like the rest)
 *        text        the text directly inside the element (entities read, CDATA sections included, line ends made line feeds)
 *        children    an array of the child elements, in the order of the document
 *    and a member that would be empty is left out.  Text that is between two child elements is white space and is let go when the element
 *    has a child element; text that stands alone is kept as it is.  Comments, processing instructions, the XML declaration and a
 *    DOCTYPE are read past and kept nowhere.  An entity other than the five (lt gt amp quot apos) and character references (&#10; &#xA;)
 *    is an error: no DTD is read, so there is nothing to expand and nothing that can be made to grow.
 *
 *    XPARSE(text {, mode})            the root element; a null string with STATUS() 1020 and INMAT() the place on an error
 *    XBUILD(element {, mode {, indent}})   the text; a null string with STATUS() 1019 when the element cannot be written
 *    XPATH(x, query)                  XPath 1.0 over an element: the nodes found as an array (an element as its collection, an attribute or
 *                                     text as a string), or the number, string or truth value when the query is one
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "sd.h"
#include "header.h"
#include "err.h"
#include "keys.h"

#define XTAG 164
#define X_MAX_DEPTH 500

/* the XPARSE() and XBUILD() modes are in keys.h */

typedef struct {
  char* b;
  int32_t len;
  int32_t cap;
} XB;

Private void xb_init(XB* f) {
  f->cap = 128;
  f->len = 0;
  f->b = (char*)k_alloc(XTAG, f->cap);
  f->b[0] = '\0';
}

Private void xb_add(XB* f, const char* s, int32_t n) {
  if (f->len + n + 1 > f->cap) {
    int32_t nc = f->cap * 2;
    char* nb;

    while (nc < f->len + n + 1)
      nc *= 2;
    nb = (char*)k_alloc(XTAG, nc);
    memcpy(nb, f->b, f->len);
    k_free(f->b);
    f->b = nb;
    f->cap = nc;
  }
  memcpy(f->b + f->len, s, n);
  f->len += n;
  f->b[f->len] = '\0';
}

Private void xb_addc(XB* f, char c) {
  xb_add(f, &c, 1);
}

Private void xb_free(XB* f) {
  if (f->b != NULL)
    k_free(f->b);
  f->b = NULL;
}

Private void push_xnull(void) {
  DESCRIPTOR r;

  InitDescr(&r, STRING);
  r.data.str.saddr = NULL;
  *(e_stack++) = r;
}

Private COLL_ENTRY* xobj_slot(COLL_HEADER* h, const char* name, int32_t len) {
  int32_t pos;
  COLL_ENTRY* e;

  if (coll_find(h, (char*)name, len, &pos)) {
    e = &h->e[pos];
    k_release(&e->d);
    InitDescr(&e->d, STRING);
    e->d.data.str.saddr = NULL;
    e->tag = CT_PLAIN;
    return e;
  }
  coll_insert(h, pos);
  e = &h->e[pos];
  e->name = (char*)k_alloc(XTAG, len + 1);
  memcpy(e->name, name, len);
  e->name[len] = '\0';
  e->name_len = len;
  return e;
}

Private COLL_ENTRY* xarr_slot(COLL_HEADER* h) {
  coll_insert(h, h->count);
  return &h->e[h->count - 1];
}

Private void xset_coll(COLL_ENTRY* e, COLL_HEADER* h) {
  k_release(&e->d);
  InitDescr(&e->d, COLL);
  e->d.data.coll = h;
  e->tag = CT_PLAIN;
}

Private void xset_str(COLL_ENTRY* e, const char* s, int32_t len) {
  k_release(&e->d);
  e->d = coll_str_descr((char*)s, len);
  e->tag = CT_PLAIN;
}

/* ======================================================================
   XPARSE()                                                               */

typedef struct {
  char* s;
  int32_t n;
  int32_t pos;
  int32_t err;
  int mode;
} XP;

Private bool xp_fail(XP* p) {
  if (p->err == 0)
    p->err = p->pos + 1;
  return FALSE;
}

Private bool x_name_start(unsigned char c) {
  return isalpha(c) || c == '_' || c == ':' || c >= 0x80;
}

Private bool x_name_char(unsigned char c) {
  return x_name_start(c) || isdigit(c) || c == '-' || c == '.';
}

Private bool x_ws(char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

Private void xp_skip_ws(XP* p) {
  while (p->pos < p->n && x_ws(p->s[p->pos]))
    p->pos++;
}

Private bool xp_starts(XP* p, const char* lit) {
  int32_t l = (int32_t)strlen(lit);

  return p->pos + l <= p->n && memcmp(p->s + p->pos, lit, l) == 0;
}

/* a code point as UTF-8 (a byte for 0 - 127) */
Private void x_utf8(XB* b, uint32_t cp) {
  char t[4];

  if (cp < 0x80) {
    t[0] = (char)cp;
    xb_add(b, t, 1);
  } else if (cp < 0x800) {
    t[0] = (char)(0xC0 | (cp >> 6));
    t[1] = (char)(0x80 | (cp & 0x3F));
    xb_add(b, t, 2);
  } else if (cp < 0x10000) {
    t[0] = (char)(0xE0 | (cp >> 12));
    t[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
    t[2] = (char)(0x80 | (cp & 0x3F));
    xb_add(b, t, 3);
  } else {
    char u[4];

    u[0] = (char)(0xF0 | (cp >> 18));
    u[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    u[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    u[3] = (char)(0x80 | (cp & 0x3F));
    xb_add(b, u, 4);
  }
}

/* An entity or character reference at p->pos (the &); appends what it stands for */
Private bool xp_entity(XP* p, XB* out) {
  int32_t i = p->pos + 1;
  int32_t start = i;

  while (i < p->n && p->s[i] != ';' && i - start < 12)
    i++;
  if (i >= p->n || p->s[i] != ';')
    return xp_fail(p);
  if (p->s[start] == '#') {
    uint32_t cp = 0;
    int32_t k;

    if (start + 1 < i && (p->s[start + 1] == 'x' || p->s[start + 1] == 'X')) {
      for (k = start + 2; k < i; k++) {
        char c = p->s[k];

        cp <<= 4;
        if (c >= '0' && c <= '9')
          cp |= c - '0';
        else if (c >= 'a' && c <= 'f')
          cp |= c - 'a' + 10;
        else if (c >= 'A' && c <= 'F')
          cp |= c - 'A' + 10;
        else
          return xp_fail(p);
        if (cp > 0x10FFFF)
          return xp_fail(p);
      }
      if (i == start + 2)
        return xp_fail(p);
    } else {
      for (k = start + 1; k < i; k++) {
        if (p->s[k] < '0' || p->s[k] > '9')
          return xp_fail(p);
        cp = cp * 10 + (p->s[k] - '0');
        if (cp > 0x10FFFF)
          return xp_fail(p);
      }
      if (i == start + 1)
        return xp_fail(p);
    }
    if (cp == 0)
      return xp_fail(p);
    x_utf8(out, cp);
  } else {
    int32_t l = i - start;

    if (l == 2 && memcmp(p->s + start, "lt", 2) == 0)
      xb_addc(out, '<');
    else if (l == 2 && memcmp(p->s + start, "gt", 2) == 0)
      xb_addc(out, '>');
    else if (l == 3 && memcmp(p->s + start, "amp", 3) == 0)
      xb_addc(out, '&');
    else if (l == 4 && memcmp(p->s + start, "quot", 4) == 0)
      xb_addc(out, '"');
    else if (l == 4 && memcmp(p->s + start, "apos", 4) == 0)
      xb_addc(out, '\'');
    else
      return xp_fail(p);
  }
  p->pos = i + 1;
  return TRUE;
}

Private bool xp_name(XP* p, char** out, int32_t* len) {
  int32_t st = p->pos;

  if (p->pos >= p->n || !x_name_start((unsigned char)p->s[p->pos]))
    return xp_fail(p);
  while (p->pos < p->n && x_name_char((unsigned char)p->s[p->pos]))
    p->pos++;
  *len = p->pos - st;
  *out = (char*)k_alloc(XTAG, *len + 1);
  memcpy(*out, p->s + st, *len);
  (*out)[*len] = '\0';
  return TRUE;
}

/* Read past comments, processing instructions and a DOCTYPE; false on one that does not end */
Private bool xp_skip_misc(XP* p, bool allow_doctype) {
  for (;;) {
    xp_skip_ws(p);
    if (xp_starts(p, "<!--")) {
      int32_t i = p->pos + 4;

      while (i + 2 < p->n && !(p->s[i] == '-' && p->s[i + 1] == '-' && p->s[i + 2] == '>'))
        i++;
      if (i + 2 >= p->n)
        return xp_fail(p);
      p->pos = i + 3;
    } else if (xp_starts(p, "<?")) {
      int32_t i = p->pos + 2;

      while (i + 1 < p->n && !(p->s[i] == '?' && p->s[i + 1] == '>'))
        i++;
      if (i + 1 >= p->n)
        return xp_fail(p);
      p->pos = i + 2;
    } else if (allow_doctype && xp_starts(p, "<!DOCTYPE")) {
      int32_t depth = 0;
      int32_t i = p->pos + 9;
      char q = 0;

      while (i < p->n) {
        char c = p->s[i];

        if (q) {
          if (c == q)
            q = 0;
        } else if (c == '"' || c == '\'') {
          q = c;
        } else if (c == '[') {
          depth++;
        } else if (c == ']') {
          depth--;
        } else if (c == '>' && depth <= 0) {
          break;
        }
        i++;
      }
      if (i >= p->n)
        return xp_fail(p);
      p->pos = i + 1;
    } else {
      return TRUE;
    }
  }
}

Private void x_trim_buf(XB* b) {
  int32_t st = 0;

  while (b->len > 0 && x_ws(b->b[b->len - 1]))
    b->len--;
  while (st < b->len && x_ws(b->b[st]))
    st++;
  if (st > 0) {
    memmove(b->b, b->b + st, b->len - st);
    b->len -= st;
  }
  b->b[b->len] = '\0';
}

Private bool xp_element(XP* p, COLL_ENTRY* out, int depth);

Private bool xp_element(XP* p, COLL_ENTRY* out, int depth) {
  char* name;
  int32_t nlen;
  COLL_HEADER* el;
  COLL_HEADER* attrs = NULL;
  COLL_HEADER* kids = NULL;
  COLL_ENTRY* slot;
  XB text;
  bool had_child = FALSE;
  bool ok = FALSE;

  if (depth > X_MAX_DEPTH)
    return xp_fail(p);
  if (p->pos >= p->n || p->s[p->pos] != '<')
    return xp_fail(p);
  p->pos++;
  if (!xp_name(p, &name, &nlen))
    return FALSE;
  el = coll_new(FALSE);
  xset_coll(out, el);
  slot = xobj_slot(el, "name", 4);
  xset_str(slot, name, nlen);
  xb_init(&text);

  for (;;) { /* the attributes */
    int32_t before = p->pos;

    xp_skip_ws(p);
    if (p->pos >= p->n) {
      xp_fail(p);
      goto done;
    }
    if (p->s[p->pos] == '>' || p->s[p->pos] == '/')
      break;
    if (p->pos == before) { /* an attribute must be set apart from the name or the attribute before it */
      xp_fail(p);
      goto done;
    }
    {
      char* an;
      int32_t al;
      XB val;
      char q;
      int32_t pos;

      if (!xp_name(p, &an, &al))
        goto done;
      xp_skip_ws(p);
      if (p->pos >= p->n || p->s[p->pos] != '=') {
        k_free(an);
        xp_fail(p);
        goto done;
      }
      p->pos++;
      xp_skip_ws(p);
      if (p->pos >= p->n || (p->s[p->pos] != '"' && p->s[p->pos] != '\'')) {
        k_free(an);
        xp_fail(p);
        goto done;
      }
      q = p->s[p->pos++];
      xb_init(&val);
      while (p->pos < p->n && p->s[p->pos] != q) {
        char c = p->s[p->pos];

        if (c == '<') {
          k_free(an);
          xb_free(&val);
          xp_fail(p);
          goto done;
        }
        if (c == '&') {
          if (!xp_entity(p, &val)) {
            k_free(an);
            xb_free(&val);
            goto done;
          }
        } else {
          char sp = ' ';

          if (c == '\t' || c == '\n' || c == '\r') {
            if (c == '\r' && p->pos + 1 < p->n && p->s[p->pos + 1] == '\n')
              p->pos++;
            xb_add(&val, &sp, 1);
          } else {
            xb_addc(&val, c);
          }
          p->pos++;
        }
      }
      if (p->pos >= p->n) {
        k_free(an);
        xb_free(&val);
        xp_fail(p);
        goto done;
      }
      p->pos++;
      if (attrs == NULL) {
        attrs = coll_new(FALSE);
        slot = xobj_slot(el, "attributes", 10);
        xset_coll(slot, attrs);
      }
      if (coll_find(attrs, an, al, &pos)) {
        k_free(an);
        xb_free(&val);
        xp_fail(p);
        goto done;
      }
      slot = xobj_slot(attrs, an, al);
      xset_str(slot, val.b, val.len);
      k_free(an);
      xb_free(&val);
    }
  }

  if (p->s[p->pos] == '/') { /* <a/> */
    if (p->pos + 1 >= p->n || p->s[p->pos + 1] != '>') {
      xp_fail(p);
      goto done;
    }
    p->pos += 2;
    ok = TRUE;
    goto done;
  }
  p->pos++; /* the > */

  for (;;) { /* the content */
    if (p->pos >= p->n) {
      xp_fail(p);
      goto done;
    }
    if (p->s[p->pos] == '<') {
      if (xp_starts(p, "</")) {
        char* en;
        int32_t el2;

        p->pos += 2;
        if (!xp_name(p, &en, &el2))
          goto done;
        if (el2 != nlen || memcmp(en, name, nlen) != 0) {
          k_free(en);
          xp_fail(p);
          goto done;
        }
        k_free(en);
        xp_skip_ws(p);
        if (p->pos >= p->n || p->s[p->pos] != '>') {
          xp_fail(p);
          goto done;
        }
        p->pos++;
        break;
      } else if (xp_starts(p, "<!--") || xp_starts(p, "<?")) {
        if (!xp_skip_misc(p, FALSE))
          goto done;
      } else if (xp_starts(p, "<![CDATA[")) {
        int32_t i = p->pos + 9;

        while (i + 2 < p->n && !(p->s[i] == ']' && p->s[i + 1] == ']' && p->s[i + 2] == '>'))
          i++;
        if (i + 2 >= p->n) {
          xp_fail(p);
          goto done;
        }
        xb_add(&text, p->s + p->pos + 9, i - (p->pos + 9));
        p->pos = i + 3;
      } else {
        if (kids == NULL) {
          kids = coll_new(TRUE);
          slot = xobj_slot(el, "children", 8);
          xset_coll(slot, kids);
        }
        slot = xarr_slot(kids);
        had_child = TRUE;
        if (!xp_element(p, slot, depth + 1))
          goto done;
      }
    } else if (p->s[p->pos] == '&') {
      if (!xp_entity(p, &text))
        goto done;
    } else {
      char c = p->s[p->pos];

      if (c == '\r') {
        if (p->pos + 1 < p->n && p->s[p->pos + 1] == '\n')
          p->pos++;
        xb_addc(&text, '\n');
      } else {
        xb_addc(&text, c);
      }
      p->pos++;
    }
  }
  ok = TRUE;

done:
  if (ok) {
    if (p->mode & XML_TRIM)
      x_trim_buf(&text);
    {
      int32_t i;
      bool blank = TRUE;

      for (i = 0; i < text.len; i++)
        if (!x_ws(text.b[i]))
          blank = FALSE;
      if (text.len > 0 && !(had_child && blank)) {
        slot = xobj_slot(el, "text", 4);
        xset_str(slot, text.b, text.len);
      }
    }
  }
  xb_free(&text);
  k_free(name);
  return ok;
}

Private bool x_get_text(DESCRIPTOR* d, char** text, int32_t* len) {
  DESCRIPTOR* v = d;

  while (v->type == ADDR)
    v = v->data.d_addr;
  k_get_string(v);
  *text = coll_chunks_to_buffer(v->data.str.saddr, len);
  return TRUE;
}

void x_xparse() {
  DESCRIPTOR* mode_d = e_stack - 1;
  char* text;
  int32_t tlen;
  XP p;
  COLL_ENTRY root;
  DESCRIPTOR result;
  int32_t skip = 0;

  GetInt(mode_d);
  p.mode = mode_d->data.value;
  x_get_text(e_stack - 2, &text, &tlen);
  p.s = text;
  p.n = tlen;
  p.pos = 0;
  p.err = 0;
  process.status = 0;
  memset(&root, 0, sizeof root);
  InitDescr(&root.d, STRING);
  root.d.data.str.saddr = NULL;
  if (tlen >= 3 && (unsigned char)text[0] == 0xEF && (unsigned char)text[1] == 0xBB && (unsigned char)text[2] == 0xBF)
    skip = 3;
  p.pos = skip;
  if (xp_skip_misc(&p, TRUE) && p.pos < p.n && p.s[p.pos] == '<' && xp_element(&p, &root, 0) && xp_skip_misc(&p, FALSE) && p.pos >= p.n) {
    result = root.d;
  } else {
    k_release(&root.d);
    process.status = ER_PARSE_ERROR;
    process.inmat = p.err ? p.err : p.pos + 1;
    InitDescr(&result, STRING);
    result.data.str.saddr = NULL;
  }
  k_free(text);
  k_pop(1);
  k_dismiss();
  *(e_stack++) = result;
}

/* ======================================================================
   XBUILD()                                                               */

typedef struct {
  XB out;
  int mode;
  char indent[17];
  int32_t ilen;
  bool bad;
  char** scope;   /* the prefixes declared: "" for the default, then the name; a stack */
  int nscope;
  int capscope;
} XW;

Private void xw_escape(XB* out, const char* s, int32_t n, bool attr) {
  int32_t i;

  for (i = 0; i < n; i++) {
    switch (s[i]) {
      case '&':
        xb_add(out, "&amp;", 5);
        break;
      case '<':
        xb_add(out, "&lt;", 4);
        break;
      case '>':
        xb_add(out, "&gt;", 4);
        break;
      case '"':
        if (attr)
          xb_add(out, "&quot;", 6);
        else
          xb_addc(out, '"');
        break;
      case '\n':
        if (attr)
          xb_add(out, "&#10;", 5);
        else
          xb_addc(out, '\n');
        break;
      case '\r':
        xb_add(out, "&#13;", 5);
        break;
      case '\t':
        if (attr)
          xb_add(out, "&#9;", 4);
        else
          xb_addc(out, '\t');
        break;
      default:
        if ((unsigned char)s[i] < 0x20 && s[i] != '\n' && s[i] != '\t') {
          /* a control character has no XML 1.0 form: a space */
          xb_addc(out, ' ');
        } else {
          xb_addc(out, s[i]);
        }
    }
  }
}

Private bool xw_valid_name(const char* s, int32_t n) {
  int32_t i;

  if (n == 0 || !x_name_start((unsigned char)s[0]))
    return FALSE;
  for (i = 1; i < n; i++)
    if (!x_name_char((unsigned char)s[i]))
      return FALSE;
  return TRUE;
}

/* The text of a member's value, or false if it is a collection */
Private bool xw_text(COLL_ENTRY* e, char** s, int32_t* len) {
  DESCRIPTOR t;

  if (e->tag == CT_NULL || e->d.type == UNASSIGNED) {
    *s = (char*)k_alloc(XTAG, 1);
    (*s)[0] = '\0';
    *len = 0;
    return TRUE;
  }
  if (e->d.type == COLL)
    return FALSE;
  if (e->tag == CT_BOOL) {
    *s = (char*)k_alloc(XTAG, 6);
    strcpy(*s, e->d.data.value ? "true" : "false");
    *len = (int32_t)strlen(*s);
    return TRUE;
  }
  t = e->d;
  t.flags = 0;
  IncrRefCt(&t);
  k_get_string(&t);
  *s = coll_chunks_to_buffer(t.data.str.saddr, len);
  k_release(&t);
  return TRUE;
}

Private bool xw_declared(XW* w, const char* prefix, int32_t plen) {
  int i;

  if (plen == 3 && memcmp(prefix, "xml", 3) == 0)
    return TRUE;
  for (i = w->nscope - 1; i >= 0; i--)
    if ((int32_t)strlen(w->scope[i]) == plen && memcmp(w->scope[i], prefix, plen) == 0)
      return TRUE;
  return FALSE;
}

/* a prefixed name needs its prefix declared by an xmlns:prefix on the element or one around it */
Private bool xw_prefix_ok(XW* w, const char* name, int32_t len, bool is_attr) {
  const char* colon = memchr(name, ':', len);

  if (w->mode & XML_NOCHECK)
    return TRUE;
  if (colon == NULL)
    return TRUE;
  if (is_attr && len >= 5 && memcmp(name, "xmlns", 5) == 0)
    return TRUE;
  return xw_declared(w, name, (int32_t)(colon - name));
}

Private void xw_push_scope(XW* w, const char* p, int32_t plen) {
  if (w->nscope >= w->capscope) {
    int nc = w->capscope ? w->capscope * 2 : 8;
    char** ns = (char**)k_alloc(XTAG, nc * sizeof(char*));

    if (w->nscope)
      memcpy(ns, w->scope, w->nscope * sizeof(char*));
    if (w->scope != NULL)
      k_free(w->scope);
    w->scope = ns;
    w->capscope = nc;
  }
  w->scope[w->nscope] = (char*)k_alloc(XTAG, plen + 1);
  memcpy(w->scope[w->nscope], p, plen);
  w->scope[w->nscope][plen] = '\0';
  w->nscope++;
}

Private void xw_pop_scope(XW* w, int to) {
  while (w->nscope > to) {
    w->nscope--;
    k_free(w->scope[w->nscope]);
  }
}

Private void xw_newline(XW* w, int depth) {
  int i;

  xb_addc(&w->out, '\n');
  for (i = 0; i < depth; i++)
    xb_add(&w->out, w->indent, w->ilen);
}

Private bool xw_element(XW* w, COLL_ENTRY* e, int depth) {
  COLL_HEADER* h;
  COLL_ENTRY* ne;
  COLL_ENTRY* ae;
  COLL_ENTRY* te;
  COLL_ENTRY* ce;
  char* name;
  int32_t nlen, i, pos;
  int scope_mark = w->nscope;
  bool has_kids = FALSE;
  bool has_text = FALSE;
  char* tx = NULL;
  int32_t tl = 0;

  if (depth > X_MAX_DEPTH || e->d.type != COLL || e->d.data.coll->is_array || e->tag != CT_PLAIN)
    return FALSE;
  h = e->d.data.coll;
  if (!coll_find(h, "name", 4, &pos))
    return FALSE;
  ne = &h->e[pos];
  if (!xw_text(ne, &name, &nlen))
    return FALSE;
  if (!xw_valid_name(name, nlen)) {
    k_free(name);
    return FALSE;
  }
  ae = coll_find(h, "attributes", 10, &pos) ? &h->e[pos] : NULL;
  te = coll_find(h, "text", 4, &pos) ? &h->e[pos] : NULL;
  ce = coll_find(h, "children", 8, &pos) ? &h->e[pos] : NULL;

  /* the namespaces this element declares come first, so the name and the attributes can use them */
  if (ae != NULL && ae->d.type == COLL && !ae->d.data.coll->is_array) {
    COLL_HEADER* a = ae->d.data.coll;

    for (i = 0; i < a->count; i++) {
      if (a->e[i].name_len == 5 && memcmp(a->e[i].name, "xmlns", 5) == 0)
        xw_push_scope(w, "", 0);
      else if (a->e[i].name_len > 6 && memcmp(a->e[i].name, "xmlns:", 6) == 0)
        xw_push_scope(w, a->e[i].name + 6, a->e[i].name_len - 6);
    }
  }
  if (!xw_prefix_ok(w, name, nlen, FALSE)) {
    k_free(name);
    xw_pop_scope(w, scope_mark);
    return FALSE;
  }
  xb_addc(&w->out, '<');
  xb_add(&w->out, name, nlen);
  if (ae != NULL && ae->d.type == COLL && !ae->d.data.coll->is_array) {
    COLL_HEADER* a = ae->d.data.coll;

    for (i = 0; i < a->count; i++) {
      char* v;
      int32_t vl;

      if (!xw_valid_name(a->e[i].name, a->e[i].name_len) || !xw_prefix_ok(w, a->e[i].name, a->e[i].name_len, TRUE) ||
          !xw_text(&a->e[i], &v, &vl)) {
        k_free(name);
        xw_pop_scope(w, scope_mark);
        return FALSE;
      }
      xb_addc(&w->out, ' ');
      xb_add(&w->out, a->e[i].name, a->e[i].name_len);
      xb_add(&w->out, "=\"", 2);
      xw_escape(&w->out, v, vl, TRUE);
      xb_addc(&w->out, '"');
      k_free(v);
    }
  }
  if (te != NULL) {
    if (!xw_text(te, &tx, &tl)) {
      k_free(name);
      xw_pop_scope(w, scope_mark);
      return FALSE;
    }
    has_text = (tl > 0);
  }
  has_kids = (ce != NULL && ce->d.type == COLL && ce->d.data.coll->is_array && ce->d.data.coll->count > 0);
  if (!has_text && !has_kids) {
    xb_add(&w->out, "/>", 2);
  } else {
    xb_addc(&w->out, '>');
    if (has_text)
      xw_escape(&w->out, tx, tl, FALSE);
    if (has_kids) {
      COLL_HEADER* k = ce->d.data.coll;

      for (i = 0; i < k->count; i++) {
        if (w->mode & XML_PRETTY)
          xw_newline(w, depth + 1);
        if (!xw_element(w, &k->e[i], depth + 1)) {
          if (tx != NULL)
            k_free(tx);
          k_free(name);
          xw_pop_scope(w, scope_mark);
          return FALSE;
        }
      }
      if (w->mode & XML_PRETTY)
        xw_newline(w, depth);
    }
    xb_add(&w->out, "</", 2);
    xb_add(&w->out, name, nlen);
    xb_addc(&w->out, '>');
  }
  if (tx != NULL)
    k_free(tx);
  k_free(name);
  xw_pop_scope(w, scope_mark);
  return TRUE;
}

void x_xbuild() {
  DESCRIPTOR* ind_d = e_stack - 1;
  DESCRIPTOR* mode_d = e_stack - 2;
  DESCRIPTOR* src = e_stack - 3;
  XW w;
  DESCRIPTOR result;
  DESCRIPTOR* root = src;
  int32_t il = 0;
  char* ib = NULL;

  memset(&w, 0, sizeof w);
  GetInt(mode_d);
  w.mode = mode_d->data.value;
  strcpy(w.indent, "  ");
  w.ilen = 2;
  k_get_string(ind_d);
  if (ind_d->data.str.saddr != NULL) {
    int32_t ix;

    ib = coll_chunks_to_buffer(ind_d->data.str.saddr, &il);
    if (il > 0 && il <= 16) {
      bool ws = TRUE;

      for (ix = 0; ix < il; ix++)
        if (ib[ix] != ' ' && ib[ix] != '\t')
          ws = FALSE;
      if (ws) {
        memcpy(w.indent, ib, il);
        w.ilen = il;
      }
    }
    k_free(ib);
  }
  process.status = 0;
  xb_init(&w.out);
  while (root->type == ADDR)
    root = root->data.d_addr;
  if (root->type != COLL) {
    process.status = ER_BUILD_ERROR;
    result = coll_str_descr(NULL, 0);
  } else {
    COLL_ENTRY view;

    memset(&view, 0, sizeof view);
    view.d = *root;
    if (w.mode & XML_DECL)
      xb_add(&w.out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>", 38);
    if ((w.mode & XML_DECL) && (w.mode & XML_PRETTY))
      xb_addc(&w.out, '\n');
    if (xw_element(&w, &view, 0)) {
      if (w.mode & XML_PRETTY)
        xb_addc(&w.out, '\n');
      result = coll_str_descr(w.out.b, w.out.len);
    } else {
      process.status = ER_BUILD_ERROR;
      result = coll_str_descr(NULL, 0);
    }
  }
  xw_pop_scope(&w, 0);
  if (w.scope != NULL)
    k_free(w.scope);
  xb_free(&w.out);
  k_dismiss();
  k_pop(1);
  k_dismiss();
  *(e_stack++) = result;
}

/* ======================================================================
   XPATH()  -  XPath 1.0 over the collection

   The document is first made into a table of nodes (the document, elements, attributes and texts) numbered in document order, so that
   a node set is a sorted list of numbers and the parent, sibling and following axes are table walks.  The expression is read as it is
   evaluated, by recursive descent, over values that are node sets, numbers, strings or truth values as XPath says.  Not done: the
   namespace axis, processing instructions and comments (the parser keeps neither), variables, id(), lang(), translate() and the
   functions of node sets that XML names have no use for here.                                                                       */

typedef struct {
  int type; /* 0 document, 1 element, 2 attribute, 3 text */
  COLL_ENTRY* e;
  char* name;   /* element and attribute: not owned (the collection's own), */
  int32_t nlen;
  char* val;    /* attribute and text: owned */
  int32_t vlen;
  int parent;
  int* kids;    /* elements and the text, in order */
  int nkids, capkids;
  int* attrs;
  int nattrs, capattrs;
} XNODE;

typedef struct {
  XNODE* n;
  int cnt, cap;
  COLL_ENTRY* root;
} XDOC;

Private int xd_new(XDOC* d, int type, int parent) {
  XNODE* nn;

  if (d->cnt >= d->cap) {
    int nc = d->cap ? d->cap * 2 : 64;
    XNODE* nb = (XNODE*)k_alloc(XTAG, nc * sizeof(XNODE));

    if (d->cnt)
      memcpy(nb, d->n, d->cnt * sizeof(XNODE));
    if (d->n != NULL)
      k_free(d->n);
    d->n = nb;
    d->cap = nc;
  }
  nn = &d->n[d->cnt];
  memset(nn, 0, sizeof *nn);
  nn->type = type;
  nn->parent = parent;
  return d->cnt++;
}

Private void xd_add(int** arr, int* n, int* cap, int v) {
  if (*n >= *cap) {
    int nc = *cap ? *cap * 2 : 4;
    int* nb = (int*)k_alloc(XTAG, nc * sizeof(int));

    if (*n)
      memcpy(nb, *arr, *n * sizeof(int));
    if (*arr != NULL)
      k_free(*arr);
    *arr = nb;
    *cap = nc;
  }
  (*arr)[(*n)++] = v;
}

Private void xd_free(XDOC* d) {
  int i;

  for (i = 0; i < d->cnt; i++) {
    if (d->n[i].val != NULL)
      k_free(d->n[i].val);
    if (d->n[i].kids != NULL)
      k_free(d->n[i].kids);
    if (d->n[i].attrs != NULL)
      k_free(d->n[i].attrs);
  }
  if (d->n != NULL)
    k_free(d->n);
  d->n = NULL;
  d->cnt = d->cap = 0;
}

Private bool xd_build(XDOC* d, COLL_ENTRY* e, int parent, int depth) {
  COLL_HEADER* h;
  int self, pos;
  COLL_ENTRY* m;

  if (depth > X_MAX_DEPTH || e->d.type != COLL || e->d.data.coll->is_array)
    return FALSE;
  h = e->d.data.coll;
  self = xd_new(d, 1, parent);
  d->n[self].e = e;
  /* the name is kept in a buffer of the node's own (val), which xd_free lets go */
  if (coll_find(h, "name", 4, &pos) && h->e[pos].d.type == STRING) {
    d->n[self].val = coll_chunks_to_buffer(h->e[pos].d.data.str.saddr, &d->n[self].vlen);
  } else {
    d->n[self].val = (char*)k_alloc(XTAG, 1);
    d->n[self].val[0] = '\0';
    d->n[self].vlen = 0;
  }
  d->n[self].name = d->n[self].val;
  d->n[self].nlen = d->n[self].vlen;
  xd_add(&d->n[parent].kids, &d->n[parent].nkids, &d->n[parent].capkids, self);
  if (coll_find(h, "attributes", 10, &pos) && h->e[pos].d.type == COLL && !h->e[pos].d.data.coll->is_array) {
    COLL_HEADER* a = h->e[pos].d.data.coll;
    int i;

    for (i = 0; i < a->count; i++) {
      int an = xd_new(d, 2, self);

      d->n[an].e = &a->e[i];
      d->n[an].name = a->e[i].name;
      d->n[an].nlen = a->e[i].name_len;
      xw_text(&a->e[i], &d->n[an].val, &d->n[an].vlen);
      xd_add(&d->n[self].attrs, &d->n[self].nattrs, &d->n[self].capattrs, an);
    }
  }
  if (coll_find(h, "text", 4, &pos) && h->e[pos].d.type != COLL) {
    int tn = xd_new(d, 3, self);

    xw_text(&h->e[pos], &d->n[tn].val, &d->n[tn].vlen);
    xd_add(&d->n[self].kids, &d->n[self].nkids, &d->n[self].capkids, tn);
  }
  m = coll_find(h, "children", 8, &pos) ? &h->e[pos] : NULL;
  if (m != NULL && m->d.type == COLL && m->d.data.coll->is_array) {
    int i;

    for (i = 0; i < m->d.data.coll->count; i++)
      if (!xd_build(d, &m->d.data.coll->e[i], self, depth + 1))
        return FALSE;
  }
  return TRUE;
}

/* The element nodes keep their name in a buffer of their own (the name pointer of an element points into val-less storage allocated
   above); freeing is by xd_free through name for elements.  To keep the free simple the element's name buffer is stored in val. */

typedef struct {
  int t; /* 1 node set, 2 number, 3 string, 4 boolean */
  int* ns;
  int n;
  double num;
  char* s;
  int32_t slen;
  int b;
} XV;

Private void xv_free(XV* v) {
  if (v->ns != NULL)
    k_free(v->ns);
  if (v->s != NULL)
    k_free(v->s);
  v->ns = NULL;
  v->s = NULL;
  v->n = 0;
}

typedef struct {
  XDOC* d;
  const char* q;
  int32_t qn;
  int32_t pos;
  int err;
  int depth;
} XQ;

Private bool xq_fail(XQ* x) {
  if (x->err == 0)
    x->err = x->pos + 1;
  return FALSE;
}

Private void xq_ws(XQ* x) {
  while (x->pos < x->qn && x_ws(x->q[x->pos]))
    x->pos++;
}

/* the string value of a node */
Private void xn_string(XDOC* d, int id, XB* out, int depth) {
  XNODE* nd = &d->n[id];
  int i;

  if (nd->type == 2 || nd->type == 3) {
    xb_add(out, nd->val, nd->vlen);
    return;
  }
  if (depth > X_MAX_DEPTH)
    return;
  for (i = 0; i < nd->nkids; i++)
    xn_string(d, nd->kids[i], out, depth + 1);
}

Private void xv_set_string(XV* v, const char* s, int32_t len) {
  v->t = 3;
  v->s = (char*)k_alloc(XTAG, len + 1);
  memcpy(v->s, s, len);
  v->s[len] = '\0';
  v->slen = len;
}

Private double xs_to_num(const char* s, int32_t len) {
  char tmp[64];
  char* end;
  int32_t a = 0, b = len;
  double r;

  while (a < b && x_ws(s[a]))
    a++;
  while (b > a && x_ws(s[b - 1]))
    b--;
  if (b - a <= 0 || b - a > 60)
    return NAN;
  memcpy(tmp, s + a, b - a);
  tmp[b - a] = '\0';
  r = strtod(tmp, &end);
  if (*end != '\0' || end == tmp || (!isdigit((unsigned char)tmp[0]) && tmp[0] != '-' && tmp[0] != '.'))
    return NAN;
  return r;
}

Private void xv_as_string(XDOC* d, XV* v, XB* out) {
  switch (v->t) {
    case 1:
      if (v->n > 0)
        xn_string(d, v->ns[0], out, 0);
      break;
    case 2: {
      char t[64];

      if (isnan(v->num))
        strcpy(t, "NaN");
      else if (isinf(v->num))
        strcpy(t, v->num > 0 ? "Infinity" : "-Infinity");
      else if (v->num == floor(v->num) && fabs(v->num) < 1e15)
        sprintf(t, "%.0f", v->num);
      else
        sprintf(t, "%.15g", v->num);
      xb_add(out, t, (int32_t)strlen(t));
      break;
    }
    case 3:
      xb_add(out, v->s, v->slen);
      break;
    case 4:
      xb_add(out, v->b ? "true" : "false", v->b ? 4 : 5);
      break;
  }
}

Private double xv_as_num(XDOC* d, XV* v) {
  if (v->t == 2)
    return v->num;
  if (v->t == 4)
    return v->b ? 1 : 0;
  {
    XB b;
    double r;

    xb_init(&b);
    xv_as_string(d, v, &b);
    r = xs_to_num(b.b, b.len);
    xb_free(&b);
    return r;
  }
}

Private bool xv_as_bool(XV* v) {
  switch (v->t) {
    case 1:
      return v->n > 0;
    case 2:
      return v->num != 0 && !isnan(v->num);
    case 3:
      return v->slen > 0;
    default:
      return v->b != 0;
  }
}

Private bool xq_expr(XQ* x, XV* ctxset, int ctx, int pos, int size, XV* out);

Private void xq_nodeset_add(XV* v, int id) {
  int i;

  for (i = 0; i < v->n; i++)
    if (v->ns[i] == id)
      return;
  v->ns = (int*)(v->ns ? realloc(v->ns, (v->n + 1) * sizeof(int)) : malloc(sizeof(int)));
  v->ns[v->n++] = id;
}

Private int xi_cmp(const void* a, const void* b) {
  return *(const int*)a - *(const int*)b;
}

Private void xv_sort(XV* v) {
  int i, j = 0;

  if (v->n > 1)
    qsort(v->ns, v->n, sizeof(int), xi_cmp);
  for (i = 0; i < v->n; i++)
    if (i == 0 || v->ns[i] != v->ns[i - 1])
      v->ns[j++] = v->ns[i];
  v->n = j;
}

/* the nodes an axis gives from a node, in document order (a reverse axis is put right way round before positions are counted) */
Private void x_axis(XDOC* d, int node, const char* axis, XV* out, int depth);

Private void x_descend(XDOC* d, int node, XV* out, int depth) {
  XNODE* nd = &d->n[node];
  int i;

  if (depth > X_MAX_DEPTH)
    return;
  for (i = 0; i < nd->nkids; i++) {
    xq_nodeset_add(out, nd->kids[i]);
    x_descend(d, nd->kids[i], out, depth + 1);
  }
}

Private void x_axis(XDOC* d, int node, const char* axis, XV* out, int depth) {
  XNODE* nd = &d->n[node];
  int i, p;

  (void)depth;
  if (strcmp(axis, "child") == 0) {
    for (i = 0; i < nd->nkids; i++)
      xq_nodeset_add(out, nd->kids[i]);
  } else if (strcmp(axis, "descendant") == 0) {
    x_descend(d, node, out, 0);
  } else if (strcmp(axis, "descendant-or-self") == 0) {
    xq_nodeset_add(out, node);
    x_descend(d, node, out, 0);
  } else if (strcmp(axis, "self") == 0) {
    xq_nodeset_add(out, node);
  } else if (strcmp(axis, "parent") == 0) {
    if (nd->type != 0 && nd->parent >= 0)
      xq_nodeset_add(out, nd->parent);
  } else if (strcmp(axis, "ancestor") == 0 || strcmp(axis, "ancestor-or-self") == 0) {
    if (axis[8] == '-')
      xq_nodeset_add(out, node);
    p = nd->parent;
    while (nd->type != 0 && p >= 0) {
      xq_nodeset_add(out, p);
      if (d->n[p].type == 0)
        break;
      p = d->n[p].parent;
    }
  } else if (strcmp(axis, "attribute") == 0) {
    for (i = 0; i < nd->nattrs; i++)
      xq_nodeset_add(out, nd->attrs[i]);
  } else if (strcmp(axis, "following-sibling") == 0 || strcmp(axis, "preceding-sibling") == 0) {
    if (nd->type == 1 || nd->type == 3) {
      XNODE* par = &d->n[nd->parent];
      bool before = (axis[0] == 'p');
      bool seen = FALSE;

      for (i = 0; i < par->nkids; i++) {
        if (par->kids[i] == node)
          seen = TRUE;
        else if (before ? !seen : seen)
          xq_nodeset_add(out, par->kids[i]);
      }
    }
  } else if (strcmp(axis, "following") == 0) {
    int cur = node;

    while (d->n[cur].type != 0 && d->n[cur].parent >= 0) {
      XNODE* par = &d->n[d->n[cur].parent];
      bool seen = FALSE;

      if (d->n[cur].type == 2) {
        cur = d->n[cur].parent;
        continue;
      }
      for (i = 0; i < par->nkids; i++) {
        if (par->kids[i] == cur)
          seen = TRUE;
        else if (seen) {
          xq_nodeset_add(out, par->kids[i]);
          x_descend(d, par->kids[i], out, 0);
        }
      }
      cur = d->n[cur].parent;
    }
  } else if (strcmp(axis, "preceding") == 0) {
    int id;

    for (id = 1; id < node; id++) {
      int a = node;
      bool anc = FALSE;

      while (d->n[a].type != 0 && d->n[a].parent >= 0) {
        a = d->n[a].parent;
        if (a == id)
          anc = TRUE;
      }
      if (!anc && d->n[id].type != 2)
        xq_nodeset_add(out, id);
    }
  }
  xv_sort(out);
}

typedef struct {
  char name[40];
  int32_t nl;
  bool wild;     /* * */
  int kind;      /* 0 a name or *, 1 text(), 2 node() */
} XTEST;

Private bool x_test_match(XDOC* d, int id, const char* axis, XTEST* t) {
  XNODE* nd = &d->n[id];
  bool attr_axis = strcmp(axis, "attribute") == 0;

  if (t->kind == 2)
    return TRUE;
  if (t->kind == 1)
    return nd->type == 3;
  if (attr_axis) {
    if (nd->type != 2)
      return FALSE;
  } else if (nd->type != 1) {
    return FALSE;
  }
  if (t->wild)
    return TRUE;
  return nd->nlen == t->nl && memcmp(nd->name, t->name, t->nl) == 0;
}

Private bool xq_primary(XQ* x, XV* set, int ctx, int pos, int size, XV* out);

/* A predicate [ expr ] applied to the nodes in cur (in axis order): those for which it is true, or whose position it equals */
Private bool xq_predicate(XQ* x, XV* cur) {
  int32_t start;
  int i, keep = 0;
  int32_t after = -1;
  int* res;

  x->pos++; /* [ */
  start = x->pos;
  res = (int*)k_alloc(XTAG, (cur->n + 1) * sizeof(int));
  if (cur->n == 0) { /* still step over the predicate to find its end */
    XV tmp;

    memset(&tmp, 0, sizeof tmp);
    {
      XV dummy;
      int dctx = 0;

      memset(&dummy, 0, sizeof dummy);
      if (!xq_expr(x, &dummy, dctx, 1, 1, &tmp)) {
        k_free(res);
        return FALSE;
      }
    }
    xv_free(&tmp);
    xq_ws(x);
    if (x->pos >= x->qn || x->q[x->pos] != ']') {
      k_free(res);
      return xq_fail(x);
    }
    x->pos++;
    cur->n = 0;
    k_free(res);
    return TRUE;
  }
  for (i = 0; i < cur->n; i++) {
    XV r;
    bool t;

    x->pos = start;
    memset(&r, 0, sizeof r);
    if (!xq_expr(x, cur, cur->ns[i], i + 1, cur->n, &r)) {
      k_free(res);
      return FALSE;
    }
    if (r.t == 2)
      t = (r.num == (double)(i + 1));
    else
      t = xv_as_bool(&r);
    xv_free(&r);
    if (t)
      res[keep++] = cur->ns[i];
    after = x->pos;
  }
  xq_ws(x);
  x->pos = after >= 0 ? after : x->pos;
  xq_ws(x);
  if (x->pos >= x->qn || x->q[x->pos] != ']') {
    k_free(res);
    return xq_fail(x);
  }
  x->pos++;
  memcpy(cur->ns, res, keep * sizeof(int));
  cur->n = keep;
  k_free(res);
  return TRUE;
}

/* one location step from every node of in; the results in out */
Private bool xq_step(XQ* x, XV* in, XV* out) {
  char axis[24];
  XTEST t;
  int i;
  int32_t st;
  bool have_axis = FALSE;
  XV acc;

  memset(&acc, 0, sizeof acc);
  strcpy(axis, "child");
  xq_ws(x);
  if (x->pos < x->qn && x->q[x->pos] == '.') {
    if (x->pos + 1 < x->qn && x->q[x->pos + 1] == '.') {
      x->pos += 2;
      for (i = 0; i < in->n; i++)
        x_axis(x->d, in->ns[i], "parent", out, 0);
    } else {
      x->pos++;
      for (i = 0; i < in->n; i++)
        xq_nodeset_add(out, in->ns[i]);
    }
    xv_sort(out);
    return TRUE;
  }
  if (x->pos < x->qn && x->q[x->pos] == '@') {
    strcpy(axis, "attribute");
    x->pos++;
    have_axis = TRUE;
  } else {
    /* name:: ? */
    int32_t k = x->pos;

    while (k < x->qn && (isalpha((unsigned char)x->q[k]) || x->q[k] == '-'))
      k++;
    if (k + 1 < x->qn && x->q[k] == ':' && x->q[k + 1] == ':' && k - x->pos < 20) {
      memcpy(axis, x->q + x->pos, k - x->pos);
      axis[k - x->pos] = '\0';
      x->pos = k + 2;
      have_axis = TRUE;
    }
  }
  (void)have_axis;
  xq_ws(x);
  memset(&t, 0, sizeof t);
  if (x->pos < x->qn && x->q[x->pos] == '*') {
    t.wild = TRUE;
    x->pos++;
  } else {
    st = x->pos;
    while (x->pos < x->qn && x_name_char((unsigned char)x->q[x->pos]))
      x->pos++;
    if (x->pos == st)
      return xq_fail(x);
    t.nl = x->pos - st;
    if (t.nl >= 39)
      return xq_fail(x);
    memcpy(t.name, x->q + st, t.nl);
    t.name[t.nl] = '\0';
    if (x->pos + 1 < x->qn && x->q[x->pos] == '(' && x->q[x->pos + 1] == ')') {
      if (strcmp(t.name, "text") == 0)
        t.kind = 1;
      else if (strcmp(t.name, "node") == 0)
        t.kind = 2;
      else
        return xq_fail(x);
      x->pos += 2;
    }
  }
  for (i = 0; i < in->n; i++) {
    XV cur;
    int j;
    int32_t save;
    bool ok = TRUE;

    memset(&cur, 0, sizeof cur);
    {
      XV all;

      memset(&all, 0, sizeof all);
      x_axis(x->d, in->ns[i], axis, &all, 0);
      for (j = 0; j < all.n; j++)
        if (x_test_match(x->d, all.ns[j], axis, &t))
          xq_nodeset_add(&cur, all.ns[j]);
      xv_free(&all);
    }
    /* reverse axes count positions backwards */
    if (strcmp(axis, "ancestor") == 0 || strcmp(axis, "ancestor-or-self") == 0 || strcmp(axis, "preceding") == 0 ||
        strcmp(axis, "preceding-sibling") == 0 || strcmp(axis, "parent") == 0) {
      int a = 0, b = cur.n - 1;

      while (a < b) {
        int tmp = cur.ns[a];

        cur.ns[a++] = cur.ns[b];
        cur.ns[b--] = tmp;
      }
    }
    save = x->pos;
    xq_ws(x);
    while (x->pos < x->qn && x->q[x->pos] == '[') {
      if (!xq_predicate(x, &cur)) {
        ok = FALSE;
        break;
      }
      xq_ws(x);
    }
    if (ok && i < in->n - 1)
      x->pos = save;
    if (!ok) {
      xv_free(&cur);
      return FALSE;
    }
    for (j = 0; j < cur.n; j++)
      xq_nodeset_add(out, cur.ns[j]);
    xv_free(&cur);
  }
  if (in->n == 0) { /* read past the predicates of a step with nothing to step from */
    xq_ws(x);
    while (x->pos < x->qn && x->q[x->pos] == '[') {
      XV none;

      memset(&none, 0, sizeof none);
      if (!xq_predicate(x, &none))
        return FALSE;
      xq_ws(x);
    }
  }
  xv_sort(out);
  return TRUE;
}

/* the steps of a path after its first; cur is replaced */
Private bool xq_steps(XQ* x, XV* cur) {
  for (;;) {
    XV nxt;

    xq_ws(x);
    memset(&nxt, 0, sizeof nxt);
    if (x->pos + 1 < x->qn && x->q[x->pos] == '/' && x->q[x->pos + 1] == '/') {
      XV all;
      int i;

      x->pos += 2;
      memset(&all, 0, sizeof all);
      for (i = 0; i < cur->n; i++)
        x_axis(x->d, cur->ns[i], "descendant-or-self", &all, 0);
      xv_sort(&all);
      xv_free(cur);
      *cur = all;
      if (!xq_step(x, cur, &nxt))
        return FALSE;
    } else if (x->pos < x->qn && x->q[x->pos] == '/') {
      x->pos++;
      if (!xq_step(x, cur, &nxt))
        return FALSE;
    } else {
      return TRUE;
    }
    xv_free(cur);
    *cur = nxt;
  }
}

Private bool xq_literal_string(XQ* x, XV* out) {
  char q = x->q[x->pos];
  int32_t st = ++x->pos;

  while (x->pos < x->qn && x->q[x->pos] != q)
    x->pos++;
  if (x->pos >= x->qn)
    return xq_fail(x);
  xv_set_string(out, x->q + st, x->pos - st);
  x->pos++;
  return TRUE;
}

Private bool xq_args(XQ* x, XV* set, int ctx, int pos, int size, XV* a, int* n) {
  *n = 0;
  xq_ws(x);
  if (x->pos < x->qn && x->q[x->pos] == ')') {
    x->pos++;
    return TRUE;
  }
  for (;;) {
    if (*n >= 3 || !xq_expr(x, set, ctx, pos, size, &a[*n]))
      return xq_fail(x);
    (*n)++;
    xq_ws(x);
    if (x->pos < x->qn && x->q[x->pos] == ',') {
      x->pos++;
      continue;
    }
    if (x->pos < x->qn && x->q[x->pos] == ')') {
      x->pos++;
      return TRUE;
    }
    return xq_fail(x);
  }
}

Private void xv_num(XV* v, double n) {
  v->t = 2;
  v->num = n;
}

Private void xv_bool(XV* v, int b) {
  v->t = 4;
  v->b = b;
}

Private bool xq_call(XQ* x, const char* fn, XV* set, int ctx, int pos, int size, XV* out) {
  XV a[3];
  int n, i;
  XB s0, s1;
  bool ok = TRUE;

  memset(a, 0, sizeof a);
  if (!xq_args(x, set, ctx, pos, size, a, &n))
    return FALSE;
  xb_init(&s0);
  xb_init(&s1);
  if (strcmp(fn, "position") == 0) {
    xv_num(out, pos);
  } else if (strcmp(fn, "last") == 0) {
    xv_num(out, size);
  } else if (strcmp(fn, "count") == 0 && n == 1 && a[0].t == 1) {
    xv_num(out, a[0].n);
  } else if (strcmp(fn, "true") == 0) {
    xv_bool(out, 1);
  } else if (strcmp(fn, "false") == 0) {
    xv_bool(out, 0);
  } else if (strcmp(fn, "not") == 0 && n == 1) {
    xv_bool(out, !xv_as_bool(&a[0]));
  } else if (strcmp(fn, "boolean") == 0 && n == 1) {
    xv_bool(out, xv_as_bool(&a[0]));
  } else if (strcmp(fn, "string") == 0) {
    if (n == 0) {
      if (ctx >= 0)
        xn_string(x->d, ctx, &s0, 0);
    } else {
      xv_as_string(x->d, &a[0], &s0);
    }
    xv_set_string(out, s0.b, s0.len);
  } else if (strcmp(fn, "number") == 0) {
    if (n == 0) {
      if (ctx >= 0)
        xn_string(x->d, ctx, &s0, 0);
      xv_num(out, xs_to_num(s0.b, s0.len));
    } else {
      xv_num(out, xv_as_num(x->d, &a[0]));
    }
  } else if (strcmp(fn, "string-length") == 0) {
    if (n == 0) {
      if (ctx >= 0)
        xn_string(x->d, ctx, &s0, 0);
    } else {
      xv_as_string(x->d, &a[0], &s0);
    }
    xv_num(out, s0.len);
  } else if (strcmp(fn, "normalize-space") == 0) {
    XB o;
    int32_t k;
    bool pend = FALSE;

    if (n == 0) {
      if (ctx >= 0)
        xn_string(x->d, ctx, &s0, 0);
    } else {
      xv_as_string(x->d, &a[0], &s0);
    }
    xb_init(&o);
    for (k = 0; k < s0.len; k++) {
      if (x_ws(s0.b[k])) {
        pend = (o.len > 0);
      } else {
        if (pend)
          xb_addc(&o, ' ');
        pend = FALSE;
        xb_addc(&o, s0.b[k]);
      }
    }
    xv_set_string(out, o.b, o.len);
    xb_free(&o);
  } else if ((strcmp(fn, "contains") == 0 || strcmp(fn, "starts-with") == 0 || strcmp(fn, "substring-before") == 0 ||
              strcmp(fn, "substring-after") == 0) && n == 2) {
    const char* hit = NULL;
    int32_t k;

    xv_as_string(x->d, &a[0], &s0);
    xv_as_string(x->d, &a[1], &s1);
    if (s1.len == 0) {
      hit = s0.b;
    } else {
      for (k = 0; k + s1.len <= s0.len; k++)
        if (memcmp(s0.b + k, s1.b, s1.len) == 0) {
          hit = s0.b + k;
          break;
        }
    }
    if (fn[0] == 'c') {
      xv_bool(out, hit != NULL);
    } else if (fn[0] == 's' && fn[1] == 't') {
      xv_bool(out, s0.len >= s1.len && memcmp(s0.b, s1.b, s1.len) == 0);
    } else if (fn[10] == 'b') {
      if (hit == NULL)
        xv_set_string(out, "", 0);
      else
        xv_set_string(out, s0.b, (int32_t)(hit - s0.b));
    } else {
      if (hit == NULL)
        xv_set_string(out, "", 0);
      else
        xv_set_string(out, hit + s1.len, s0.len - (int32_t)(hit - s0.b) - s1.len);
    }
  } else if (strcmp(fn, "concat") == 0 && n >= 1) {
    for (i = 0; i < n; i++)
      xv_as_string(x->d, &a[i], &s0);
    xv_set_string(out, s0.b, s0.len);
  } else if (strcmp(fn, "name") == 0 || strcmp(fn, "local-name") == 0) {
    int id = ctx;

    if (n == 1 && a[0].t == 1)
      id = a[0].n ? a[0].ns[0] : -1;
    if (id >= 0 && (x->d->n[id].type == 1 || x->d->n[id].type == 2)) {
      const char* nm = x->d->n[id].name;
      int32_t nl = x->d->n[id].nlen;

      if (fn[0] == 'l') {
        const char* c = memchr(nm, ':', nl);

        if (c != NULL) {
          nl -= (int32_t)(c + 1 - nm);
          nm = c + 1;
        }
      }
      xv_set_string(out, nm, nl);
    } else {
      xv_set_string(out, "", 0);
    }
  } else if (strcmp(fn, "sum") == 0 && n == 1 && a[0].t == 1) {
    double t = 0;

    for (i = 0; i < a[0].n; i++) {
      XB b;

      xb_init(&b);
      xn_string(x->d, a[0].ns[i], &b, 0);
      t += xs_to_num(b.b, b.len);
      xb_free(&b);
    }
    xv_num(out, t);
  } else if ((strcmp(fn, "floor") == 0 || strcmp(fn, "ceiling") == 0 || strcmp(fn, "round") == 0) && n == 1) {
    double v = xv_as_num(x->d, &a[0]);

    xv_num(out, fn[0] == 'f' ? floor(v) : fn[0] == 'c' ? ceil(v) : floor(v + 0.5));
  } else {
    ok = xq_fail(x);
  }
  for (i = 0; i < 3; i++)
    xv_free(&a[i]);
  xb_free(&s0);
  xb_free(&s1);
  return ok;
}

Private bool xq_primary(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  char c;

  xq_ws(x);
  if (x->pos >= x->qn)
    return xq_fail(x);
  c = x->q[x->pos];
  if (c == '(') {
    x->pos++;
    if (!xq_expr(x, set, ctx, pos, size, out))
      return FALSE;
    xq_ws(x);
    if (x->pos >= x->qn || x->q[x->pos] != ')')
      return xq_fail(x);
    x->pos++;
    if (out->t == 1) { /* a parenthesised node set may be followed by predicates and steps */
      xq_ws(x);
      while (x->pos < x->qn && x->q[x->pos] == '[') {
        if (!xq_predicate(x, out))
          return FALSE;
        xq_ws(x);
      }
      if (!xq_steps(x, out))
        return FALSE;
    }
    return TRUE;
  }
  if (c == '\'' || c == '"')
    return xq_literal_string(x, out);
  if (isdigit((unsigned char)c) || (c == '.' && x->pos + 1 < x->qn && isdigit((unsigned char)x->q[x->pos + 1]))) {
    char tmp[64];
    int32_t st = x->pos;

    while (x->pos < x->qn && (isdigit((unsigned char)x->q[x->pos]) || x->q[x->pos] == '.'))
      x->pos++;
    if (x->pos - st >= 60)
      return xq_fail(x);
    memcpy(tmp, x->q + st, x->pos - st);
    tmp[x->pos - st] = '\0';
    xv_num(out, strtod(tmp, NULL));
    return TRUE;
  }
  /* a function call: name ( */
  if (isalpha((unsigned char)c)) {
    int32_t k = x->pos;

    while (k < x->qn && (isalnum((unsigned char)x->q[k]) || x->q[k] == '-'))
      k++;
    {
      int32_t k2 = k;

      while (k2 < x->qn && x_ws(x->q[k2]))
        k2++;
      if (k2 < x->qn && x->q[k2] == '(' && !(k - x->pos == 4 && memcmp(x->q + x->pos, "text", 4) == 0) &&
          !(k - x->pos == 4 && memcmp(x->q + x->pos, "node", 4) == 0)) {
        char fn[32];

        if (k - x->pos >= 31)
          return xq_fail(x);
        memcpy(fn, x->q + x->pos, k - x->pos);
        fn[k - x->pos] = '\0';
        x->pos = k2 + 1;
        return xq_call(x, fn, set, ctx, pos, size, out);
      }
    }
  }
  /* a path */
  {
    XV cur;

    memset(&cur, 0, sizeof cur);
    if (c == '/') {
      xq_nodeset_add(&cur, 0);
      if (x->pos + 1 < x->qn && x->q[x->pos + 1] == '/') {
        XV all;

        memset(&all, 0, sizeof all);
        x->pos += 2;
        x_axis(x->d, 0, "descendant-or-self", &all, 0);
        xv_free(&cur);
        cur = all;
        {
          XV nxt;

          memset(&nxt, 0, sizeof nxt);
          if (!xq_step(x, &cur, &nxt)) {
            xv_free(&cur);
            return FALSE;
          }
          xv_free(&cur);
          cur = nxt;
        }
      } else {
        x->pos++;
        xq_ws(x);
        if (x->pos < x->qn && (isalpha((unsigned char)x->q[x->pos]) || x->q[x->pos] == '*' || x->q[x->pos] == '@' || x->q[x->pos] == '.' ||
                                x->q[x->pos] == '_')) {
          XV nxt;

          memset(&nxt, 0, sizeof nxt);
          if (!xq_step(x, &cur, &nxt)) {
            xv_free(&cur);
            return FALSE;
          }
          xv_free(&cur);
          cur = nxt;
        }
      }
    } else {
      XV nxt;

      if (ctx >= 0)
        xq_nodeset_add(&cur, ctx);
      memset(&nxt, 0, sizeof nxt);
      if (!xq_step(x, &cur, &nxt)) {
        xv_free(&cur);
        return FALSE;
      }
      xv_free(&cur);
      cur = nxt;
    }
    if (!xq_steps(x, &cur)) {
      xv_free(&cur);
      return FALSE;
    }
    cur.t = 1;
    *out = cur;
    return TRUE;
  }
}

/* comparison of two values by XPath 1.0 rules; op 1 = 2 != 3 < 4 <= 5 > 6 >= */
Private bool xv_compare(XDOC* d, XV* a, XV* b, int op) {
  int i, j;

  if (a->t == 1 || b->t == 1) {
    XV* ns = (a->t == 1) ? a : b;
    XV* other = (a->t == 1) ? b : a;
    bool flip = (a->t != 1);

    if (other->t == 4) {
      bool l = xv_as_bool(ns), r = xv_as_bool(other);

      return (op == 1) ? l == r : (op == 2) ? l != r : FALSE;
    }
    for (i = 0; i < ns->n; i++) {
      XB sb;
      bool hit = FALSE;

      xb_init(&sb);
      xn_string(d, ns->ns[i], &sb, 0);
      if (other->t == 1) {
        for (j = 0; j < other->n && !hit; j++) {
          XB ob;

          xb_init(&ob);
          xn_string(d, other->ns[j], &ob, 0);
          if (op <= 2) {
            bool same = (sb.len == ob.len && memcmp(sb.b, ob.b, sb.len) == 0);

            hit = (op == 1) ? same : !same;
          } else {
            double l = xs_to_num(sb.b, sb.len), r = xs_to_num(ob.b, ob.len);

            hit = (op == 3) ? l < r : (op == 4) ? l <= r : (op == 5) ? l > r : l >= r;
          }
          xb_free(&ob);
        }
      } else if (other->t == 2 || op > 2) {
        double l = xs_to_num(sb.b, sb.len), r = xv_as_num(d, other);

        if (flip) {
          double t = l;

          l = r;
          r = t;
        }
        hit = (op == 1) ? l == r : (op == 2) ? l != r : (op == 3) ? l < r : (op == 4) ? l <= r : (op == 5) ? l > r : l >= r;
      } else {
        XB ob;
        bool same;

        xb_init(&ob);
        xv_as_string(d, other, &ob);
        same = (sb.len == ob.len && memcmp(sb.b, ob.b, sb.len) == 0);
        hit = (op == 1) ? same : !same;
        xb_free(&ob);
      }
      xb_free(&sb);
      if (hit)
        return TRUE;
    }
    return FALSE;
  }
  if (op <= 2) {
    bool same;

    if (a->t == 4 || b->t == 4) {
      same = xv_as_bool(a) == xv_as_bool(b);
    } else if (a->t == 2 || b->t == 2) {
      same = xv_as_num(d, a) == xv_as_num(d, b);
    } else {
      XB sa, sb;

      xb_init(&sa);
      xb_init(&sb);
      xv_as_string(d, a, &sa);
      xv_as_string(d, b, &sb);
      same = (sa.len == sb.len && memcmp(sa.b, sb.b, sa.len) == 0);
      xb_free(&sa);
      xb_free(&sb);
    }
    return (op == 1) ? same : !same;
  }
  {
    double l = xv_as_num(d, a), r = xv_as_num(d, b);

    return (op == 3) ? l < r : (op == 4) ? l <= r : (op == 5) ? l > r : l >= r;
  }
}

Private bool x_kw(XQ* x, const char* kw) {
  int32_t l = (int32_t)strlen(kw);

  xq_ws(x);
  if (x->pos + l <= x->qn && memcmp(x->q + x->pos, kw, l) == 0 &&
      (x->pos + l >= x->qn || !(isalnum((unsigned char)x->q[x->pos + l]) || x->q[x->pos + l] == '-' || x->q[x->pos + l] == '_'))) {
    x->pos += l;
    return TRUE;
  }
  return FALSE;
}

Private bool xq_unary(XQ* x, XV* set, int ctx, int pos, int size, XV* out);

Private bool xq_union(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  if (!xq_unary(x, set, ctx, pos, size, out))
    return FALSE;
  for (;;) {
    XV r;
    int i;

    xq_ws(x);
    if (x->pos < x->qn && x->q[x->pos] == '|') {
      x->pos++;
      memset(&r, 0, sizeof r);
      if (!xq_unary(x, set, ctx, pos, size, &r) || out->t != 1 || r.t != 1)
        return xq_fail(x);
      for (i = 0; i < r.n; i++)
        xq_nodeset_add(out, r.ns[i]);
      xv_sort(out);
      xv_free(&r);
    } else {
      return TRUE;
    }
  }
}

Private bool xq_unary(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  xq_ws(x);
  if (x->pos < x->qn && x->q[x->pos] == '-') {
    XV r;

    x->pos++;
    memset(&r, 0, sizeof r);
    if (!xq_unary(x, set, ctx, pos, size, &r))
      return FALSE;
    xv_num(out, -xv_as_num(x->d, &r));
    xv_free(&r);
    return TRUE;
  }
  return xq_primary(x, set, ctx, pos, size, out);
}

Private bool xq_mul(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  if (!xq_union(x, set, ctx, pos, size, out))
    return FALSE;
  for (;;) {
    XV r;
    char op = 0;

    xq_ws(x);
    if (x->pos < x->qn && x->q[x->pos] == '*' && out->t != 1 + 100)
      op = '*', x->pos++;
    else if (x_kw(x, "div"))
      op = '/';
    else if (x_kw(x, "mod"))
      op = '%';
    else
      return TRUE;
    memset(&r, 0, sizeof r);
    if (!xq_union(x, set, ctx, pos, size, &r))
      return FALSE;
    {
      double l = xv_as_num(x->d, out), rr = xv_as_num(x->d, &r), v;

      v = (op == '*') ? l * rr : (op == '/') ? l / rr : fmod(l, rr);
      xv_free(out);
      xv_free(&r);
      xv_num(out, v);
    }
  }
}

Private bool xq_add(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  if (!xq_mul(x, set, ctx, pos, size, out))
    return FALSE;
  for (;;) {
    XV r;
    char op;

    xq_ws(x);
    if (x->pos < x->qn && (x->q[x->pos] == '+' || x->q[x->pos] == '-')) {
      op = x->q[x->pos++];
    } else {
      return TRUE;
    }
    memset(&r, 0, sizeof r);
    if (!xq_mul(x, set, ctx, pos, size, &r))
      return FALSE;
    {
      double l = xv_as_num(x->d, out), rr = xv_as_num(x->d, &r);

      xv_free(out);
      xv_free(&r);
      xv_num(out, op == '+' ? l + rr : l - rr);
    }
  }
}

Private bool xq_rel(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  if (!xq_add(x, set, ctx, pos, size, out))
    return FALSE;
  for (;;) {
    XV r;
    int op = 0;

    xq_ws(x);
    if (x->pos + 1 < x->qn && x->q[x->pos] == '<' && x->q[x->pos + 1] == '=') {
      op = 4;
      x->pos += 2;
    } else if (x->pos + 1 < x->qn && x->q[x->pos] == '>' && x->q[x->pos + 1] == '=') {
      op = 6;
      x->pos += 2;
    } else if (x->pos < x->qn && x->q[x->pos] == '<') {
      op = 3;
      x->pos++;
    } else if (x->pos < x->qn && x->q[x->pos] == '>') {
      op = 5;
      x->pos++;
    } else {
      return TRUE;
    }
    memset(&r, 0, sizeof r);
    if (!xq_add(x, set, ctx, pos, size, &r))
      return FALSE;
    {
      bool v = xv_compare(x->d, out, &r, op);

      xv_free(out);
      xv_free(&r);
      xv_bool(out, v);
    }
  }
}

Private bool xq_eq(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  if (!xq_rel(x, set, ctx, pos, size, out))
    return FALSE;
  for (;;) {
    XV r;
    int op = 0;

    xq_ws(x);
    if (x->pos + 1 < x->qn && x->q[x->pos] == '!' && x->q[x->pos + 1] == '=') {
      op = 2;
      x->pos += 2;
    } else if (x->pos < x->qn && x->q[x->pos] == '=') {
      op = 1;
      x->pos++;
    } else {
      return TRUE;
    }
    memset(&r, 0, sizeof r);
    if (!xq_rel(x, set, ctx, pos, size, &r))
      return FALSE;
    {
      bool v = xv_compare(x->d, out, &r, op);

      xv_free(out);
      xv_free(&r);
      xv_bool(out, v);
    }
  }
}

Private bool xq_and(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  if (!xq_eq(x, set, ctx, pos, size, out))
    return FALSE;
  while (x_kw(x, "and")) {
    XV r;
    bool v;

    memset(&r, 0, sizeof r);
    if (!xq_eq(x, set, ctx, pos, size, &r))
      return FALSE;
    v = xv_as_bool(out) && xv_as_bool(&r);
    xv_free(out);
    xv_free(&r);
    xv_bool(out, v);
  }
  return TRUE;
}

Private bool xq_expr(XQ* x, XV* set, int ctx, int pos, int size, XV* out) {
  if (++x->depth > 100)
    return xq_fail(x);
  if (!xq_and(x, set, ctx, pos, size, out)) {
    x->depth--;
    return FALSE;
  }
  while (x_kw(x, "or")) {
    XV r;
    bool v;

    memset(&r, 0, sizeof r);
    if (!xq_and(x, set, ctx, pos, size, &r)) {
      x->depth--;
      return FALSE;
    }
    v = xv_as_bool(out) || xv_as_bool(&r);
    xv_free(out);
    xv_free(&r);
    xv_bool(out, v);
  }
  x->depth--;
  return TRUE;
}

void x_xpath() {
  XDOC doc;
  XQ x;
  XV res;
  char* qtext;
  int32_t qlen;
  DESCRIPTOR* src = e_stack - 2;
  DESCRIPTOR* root = src;
  DESCRIPTOR result;
  int d0;

  process.status = 0;
  k_get_string(e_stack - 1);
  qtext = coll_chunks_to_buffer((e_stack - 1)->data.str.saddr, &qlen);
  while (root->type == ADDR)
    root = root->data.d_addr;
  memset(&doc, 0, sizeof doc);
  d0 = xd_new(&doc, 0, -1);
  (void)d0;
  {
    COLL_ENTRY view;
    bool ok;

    if (root->type != COLL) {
      ok = FALSE;
    } else {
      memset(&view, 0, sizeof view);
      view.d = *root;
      doc.root = &view;
      ok = xd_build(&doc, &view, 0, 0);
    }
    if (!ok) {
      xd_free(&doc);
      k_free(qtext);
      process.status = ER_PARSE_ERROR;
      k_dismiss();
      k_dismiss();
      push_xnull();
      return;
    }
    x.d = &doc;
    x.q = qtext;
    x.qn = qlen;
    x.pos = 0;
    x.err = 0;
    x.depth = 0;
    memset(&res, 0, sizeof res);
    if (!xq_expr(&x, NULL, 1, 1, 1, &res) || (xq_ws(&x), x.pos < x.qn)) { /* the context is the root element; "/" is the document */
      xv_free(&res);
      xd_free(&doc);
      k_free(qtext);
      process.status = ER_QUERY_ERROR;
      process.inmat = x.err ? x.err : x.pos + 1;
      k_dismiss();
      k_dismiss();
      push_xnull();
      return;
    }
    if (res.t == 1) {
      COLL_HEADER* out = coll_new(TRUE);
      int i;

      for (i = 0; i < res.n; i++) {
        XNODE* nd = &doc.n[res.ns[i]];
        COLL_ENTRY* slot = xarr_slot(out);

        if (nd->type == 1) {
          k_release(&slot->d);
          InitDescr(&slot->d, COLL);
          slot->d.data.coll = coll_copy(nd->e->d.data.coll);
        } else if (nd->type == 2 || nd->type == 3) {
          xset_str(slot, nd->val, nd->vlen);
        } else { /* the document: its root element */
          k_release(&slot->d);
          InitDescr(&slot->d, COLL);
          slot->d.data.coll = coll_copy(doc.n[1].e->d.data.coll);
        }
      }
      InitDescr(&result, COLL);
      result.data.coll = out;
    } else if (res.t == 2) {
      if (res.num == floor(res.num) && fabs(res.num) < 2147483647.0) {
        InitDescr(&result, INTEGER);
        result.data.value = (int32_t)res.num;
      } else {
        InitDescr(&result, FLOATNUM);
        result.data.float_value = res.num;
      }
    } else if (res.t == 4) {
      InitDescr(&result, INTEGER);
      result.data.value = res.b ? 1 : 0;
      result.flags = DF_JSON;
    } else {
      result = coll_str_descr(res.s, res.slen);
    }
    xv_free(&res);
  }
  xd_free(&doc);
  k_free(qtext);
  k_dismiss();
  k_dismiss();
  *(e_stack++) = result;
}

/* END-CODE */
