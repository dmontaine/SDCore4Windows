/* SDAI_JSON.C
 * sd-ai.exe: a bounded JSON reader, and a writer that writes what Python's json.dumps writes.
 * Copyright (c) String Database
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
 * START-HISTORY:
 * 13 Nov 26 Windows port - New (RELEASE_1.1 246): the C helper replaces the Python one.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * THE READER FACES THE INTERNET (a provider's answer, up to 4 MB) and SD (a request line).  It takes what Python's json.loads takes of a
 * UTF-8 text, and refuses what it refuses: input that is not valid UTF-8, a control character inside a string, anything after the value but
 * white space.  Its own bounds: AT MOST JSON_DEPTH nesting and JSON_NODES values, past which the text is "not JSON" - a legitimate answer has
 * a handful of levels and a few thousand values; a hostile one cannot make this process deep or large.  NaN and Infinity are refused
 * (Python takes them; no provider sends them).  A lone \u surrogate becomes U+FFFD.
 *
 * THE WRITER is Python's json.dumps with ensure_ascii=True and the default separators ", " and ": ": SD's BASIC parses these lines and the
 * Python helper wrote them so, so the C helper's lines are the same bytes.
 *
 * END-DESCRIPTION
 */

#include "sdai.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JSON_DEPTH 200
#define JSON_NODES 500000

typedef struct {
  const unsigned char* p;
  const unsigned char* end;
  int nodes;
  int bad;
} jparser;

static void* xalloc(size_t n) {
  void* p = calloc(1, n ? n : 1);
  if (p == NULL)
    ExitProcess(9); /* out of memory in a one-request process: the request is lost, nothing else */
  return p;
}

static void* xrealloc(void* p, size_t n) {
  void* q = realloc(p, n ? n : 1);
  if (q == NULL)
    ExitProcess(9);
  return q;
}

static jval* jnew(jparser* ps, jtype t) {
  jval* v;
  if (++ps->nodes > JSON_NODES) {
    ps->bad = 1;
    return NULL;
  }
  v = (jval*)xalloc(sizeof(jval));
  v->t = t;
  return v;
}

static void skip_ws(jparser* ps) {
  while (ps->p < ps->end && (*ps->p == ' ' || *ps->p == '\t' || *ps->p == '\n' || *ps->p == '\r'))
    ps->p++;
}

/* One UTF-8 sequence at s (valid as Python's decoder sees it); its length, or 0. */
static int utf8_len(const unsigned char* s, const unsigned char* end, unsigned* cp) {
  unsigned c = s[0];
  int n, i;
  unsigned v;
  if (c < 0x80) {
    *cp = c;
    return 1;
  }
  if (c >= 0xC2 && c <= 0xDF) {
    n = 2;
    v = c & 0x1F;
  } else if (c >= 0xE0 && c <= 0xEF) {
    n = 3;
    v = c & 0x0F;
  } else if (c >= 0xF0 && c <= 0xF4) {
    n = 4;
    v = c & 0x07;
  } else
    return 0;
  if (end - s < n)
    return 0;
  for (i = 1; i < n; i++) {
    if ((s[i] & 0xC0) != 0x80)
      return 0;
    v = (v << 6) | (s[i] & 0x3F);
  }
  if ((n == 3 && v < 0x800) || (n == 4 && (v < 0x10000 || v > 0x10FFFF)) || (v >= 0xD800 && v <= 0xDFFF))
    return 0;
  *cp = v;
  return n;
}

static void put_utf8(sbuf* b, unsigned cp) {
  char t[4];
  if (cp < 0x80) {
    t[0] = (char)cp;
    sb_add(b, t, 1);
  } else if (cp < 0x800) {
    t[0] = (char)(0xC0 | (cp >> 6));
    t[1] = (char)(0x80 | (cp & 0x3F));
    sb_add(b, t, 2);
  } else if (cp < 0x10000) {
    t[0] = (char)(0xE0 | (cp >> 12));
    t[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
    t[2] = (char)(0x80 | (cp & 0x3F));
    sb_add(b, t, 3);
  } else {
    t[0] = (char)(0xF0 | (cp >> 18));
    t[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    t[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    t[3] = (char)(0x80 | (cp & 0x3F));
    sb_add(b, t, 4);
  }
}

static int hex4(const unsigned char* s, unsigned* out) {
  unsigned v = 0;
  int i;
  for (i = 0; i < 4; i++) {
    unsigned c = s[i];
    v <<= 4;
    if (c >= '0' && c <= '9')
      v |= c - '0';
    else if (c >= 'a' && c <= 'f')
      v |= c - 'a' + 10;
    else if (c >= 'A' && c <= 'F')
      v |= c - 'A' + 10;
    else
      return 0;
  }
  *out = v;
  return 1;
}

/* A string at ps->p (the opening quote); its bytes in out. */
static int parse_string(jparser* ps, sbuf* out) {
  ps->p++;
  for (;;) {
    unsigned cp;
    int n;
    if (ps->p >= ps->end)
      return 0;
    if (*ps->p == '"') {
      ps->p++;
      return 1;
    }
    if (*ps->p < 0x20)
      return 0; /* json.loads (strict) refuses a control character inside a string */
    if (*ps->p == '\\') {
      unsigned char e;
      if (ps->end - ps->p < 2)
        return 0;
      e = ps->p[1];
      ps->p += 2;
      switch (e) {
        case '"': sb_add(out, "\"", 1); break;
        case '\\': sb_add(out, "\\", 1); break;
        case '/': sb_add(out, "/", 1); break;
        case 'b': sb_add(out, "\b", 1); break;
        case 'f': sb_add(out, "\f", 1); break;
        case 'n': sb_add(out, "\n", 1); break;
        case 'r': sb_add(out, "\r", 1); break;
        case 't': sb_add(out, "\t", 1); break;
        case 'u':
          if (ps->end - ps->p < 4 || !hex4(ps->p, &cp))
            return 0;
          ps->p += 4;
          if (cp >= 0xD800 && cp <= 0xDBFF) {
            unsigned lo;
            if (ps->end - ps->p >= 6 && ps->p[0] == '\\' && ps->p[1] == 'u' && hex4(ps->p + 2, &lo) && lo >= 0xDC00 && lo <= 0xDFFF) {
              ps->p += 6;
              cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            } else
              cp = 0xFFFD;
          } else if (cp >= 0xDC00 && cp <= 0xDFFF)
            cp = 0xFFFD;
          put_utf8(out, cp);
          break;
        default:
          return 0;
      }
      continue;
    }
    n = utf8_len(ps->p, ps->end, &cp);
    if (n == 0)
      return 0;
    sb_add(out, (const char*)ps->p, (size_t)n);
    ps->p += n;
  }
}

static jval* parse_value(jparser* ps, int depth);

static jval* parse_number(jparser* ps) {
  const unsigned char* s = ps->p;
  int isint = 1;
  char tmp[400];
  size_t n;
  jval* v;
  if (ps->p < ps->end && *ps->p == '-')
    ps->p++;
  if (ps->p >= ps->end)
    return NULL;
  if (*ps->p == '0')
    ps->p++;
  else if (*ps->p >= '1' && *ps->p <= '9') {
    while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9')
      ps->p++;
  } else
    return NULL;
  if (ps->p < ps->end && *ps->p == '.') {
    const unsigned char* d = ++ps->p;
    while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9')
      ps->p++;
    if (ps->p == d)
      return NULL;
    isint = 0;
  }
  if (ps->p < ps->end && (*ps->p == 'e' || *ps->p == 'E')) {
    const unsigned char* d;
    ps->p++;
    if (ps->p < ps->end && (*ps->p == '+' || *ps->p == '-'))
      ps->p++;
    d = ps->p;
    while (ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9')
      ps->p++;
    if (ps->p == d)
      return NULL;
    isint = 0;
  }
  n = (size_t)(ps->p - s);
  if (n >= sizeof tmp)
    n = sizeof tmp - 1; /* a number of hundreds of digits: its value is whatever its first 399 characters say */
  memcpy(tmp, s, n);
  tmp[n] = '\0';
  v = jnew(ps, J_NUM);
  if (v == NULL)
    return NULL;
  v->isint = isint;
  v->num = strtod(tmp, NULL);
  if (isint) {
    v->ival = strtoll(tmp, NULL, 10); /* clamped at the range by strtoll */
  } else {
    if (v->num >= 9.2e18)
      v->ival = 9223372036854775807LL;
    else if (v->num <= -9.2e18)
      v->ival = -9223372036854775807LL;
    else
      v->ival = (long long)v->num;
  }
  return v;
}

static int lit(jparser* ps, const char* w) {
  size_t n = strlen(w);
  if ((size_t)(ps->end - ps->p) < n || memcmp(ps->p, w, n) != 0)
    return 0;
  ps->p += n;
  return 1;
}

static jval* parse_value(jparser* ps, int depth) {
  jval* v;
  if (depth > JSON_DEPTH) {
    ps->bad = 1;
    return NULL;
  }
  skip_ws(ps);
  if (ps->p >= ps->end)
    return NULL;
  switch (*ps->p) {
    case '{': {
      size_t cap = 0;
      v = jnew(ps, J_OBJ);
      if (v == NULL)
        return NULL;
      ps->p++;
      skip_ws(ps);
      if (ps->p < ps->end && *ps->p == '}') {
        ps->p++;
        return v;
      }
      for (;;) {
        sbuf k;
        jval* m;
        skip_ws(ps);
        if (ps->p >= ps->end || *ps->p != '"')
          return NULL;
        sb_init(&k);
        if (!parse_string(ps, &k))
          return NULL;
        skip_ws(ps);
        if (ps->p >= ps->end || *ps->p != ':')
          return NULL;
        ps->p++;
        m = parse_value(ps, depth + 1);
        if (m == NULL)
          return NULL;
        if (v->n == cap) {
          cap = cap ? cap * 2 : 8;
          v->items = (jval**)xrealloc(v->items, cap * sizeof(jval*));
          v->keys = (char**)xrealloc(v->keys, cap * sizeof(char*));
        }
        v->keys[v->n] = k.p;
        v->items[v->n++] = m;
        skip_ws(ps);
        if (ps->p < ps->end && *ps->p == ',') {
          ps->p++;
          continue;
        }
        if (ps->p < ps->end && *ps->p == '}') {
          ps->p++;
          return v;
        }
        return NULL;
      }
    }
    case '[': {
      size_t cap = 0;
      v = jnew(ps, J_ARR);
      if (v == NULL)
        return NULL;
      ps->p++;
      skip_ws(ps);
      if (ps->p < ps->end && *ps->p == ']') {
        ps->p++;
        return v;
      }
      for (;;) {
        jval* m = parse_value(ps, depth + 1);
        if (m == NULL)
          return NULL;
        if (v->n == cap) {
          cap = cap ? cap * 2 : 8;
          v->items = (jval**)xrealloc(v->items, cap * sizeof(jval*));
        }
        v->items[v->n++] = m;
        skip_ws(ps);
        if (ps->p < ps->end && *ps->p == ',') {
          ps->p++;
          continue;
        }
        if (ps->p < ps->end && *ps->p == ']') {
          ps->p++;
          return v;
        }
        return NULL;
      }
    }
    case '"': {
      sbuf s;
      sb_init(&s);
      if (!parse_string(ps, &s))
        return NULL;
      v = jnew(ps, J_STR);
      if (v == NULL)
        return NULL;
      v->s = s.p;
      v->slen = s.n;
      return v;
    }
    case 't':
      return lit(ps, "true") ? jnew(ps, J_TRUE) : NULL;
    case 'f':
      return lit(ps, "false") ? jnew(ps, J_FALSE) : NULL;
    case 'n':
      return lit(ps, "null") ? jnew(ps, J_NULL) : NULL;
    default:
      return parse_number(ps);
  }
}

jval* json_parse(const char* text, size_t len) {
  jparser ps;
  jval* v;
  ps.p = (const unsigned char*)text;
  ps.end = ps.p + len;
  ps.nodes = 0;
  ps.bad = 0;
  v = parse_value(&ps, 0);
  if (v == NULL || ps.bad)
    return NULL;
  skip_ws(&ps);
  if (ps.p != ps.end)
    return NULL;
  return v;
}

jval* json_get(const jval* obj, const char* key) {
  size_t i;
  if (obj == NULL || obj->t != J_OBJ)
    return NULL;
  for (i = obj->n; i > 0; i--) {
    if (strcmp(obj->keys[i - 1], key) == 0)
      return obj->items[i - 1];
  }
  return NULL;
}

int json_truthy(const jval* v) {
  if (v == NULL)
    return 0;
  switch (v->t) {
    case J_NULL:
    case J_FALSE: return 0;
    case J_TRUE: return 1;
    case J_NUM: return v->num != 0.0;
    case J_STR: return v->slen > 0;
    default: return v->n > 0;
  }
}

int json_is_str(const jval* v) { return v != NULL && v->t == J_STR; }

/* ---------------------------------------------------------------- the writer */

void sb_init(sbuf* b) {
  b->cap = 64;
  b->n = 0;
  b->p = (char*)xalloc(b->cap);
}

void sb_add(sbuf* b, const char* s, size_t n) {
  if (b->n + n + 1 > b->cap) {
    while (b->n + n + 1 > b->cap)
      b->cap *= 2;
    b->p = (char*)xrealloc(b->p, b->cap);
  }
  memcpy(b->p + b->n, s, n);
  b->n += n;
  b->p[b->n] = '\0';
}

void sb_puts(sbuf* b, const char* s) { sb_add(b, s, strlen(s)); }

void sb_printf(sbuf* b, const char* fmt, ...) {
  va_list ap;
  int n;
  char small[512];
  va_start(ap, fmt);
  n = vsnprintf(small, sizeof small, fmt, ap);
  va_end(ap);
  if (n < 0)
    return;
  if ((size_t)n < sizeof small) {
    sb_add(b, small, (size_t)n);
    return;
  }
  {
    char* big = (char*)xalloc((size_t)n + 1);
    va_start(ap, fmt);
    vsnprintf(big, (size_t)n + 1, fmt, ap);
    va_end(ap);
    sb_add(b, big, (size_t)n);
    free(big);
  }
}

/* json.dumps(s, ensure_ascii=True): " \ \b \f \n \r \t by name, everything else outside space..tilde as \u (lower-case hex, a pair above U+FFFF). */
void sb_jstr(sbuf* b, const char* s, size_t n) {
  const unsigned char* p = (const unsigned char*)s;
  const unsigned char* end = p + n;
  sb_add(b, "\"", 1);
  while (p < end) {
    unsigned cp;
    int k = utf8_len(p, end, &cp);
    if (k == 0) {
      cp = 0xFFFD;
      k = 1;
    }
    p += k;
    switch (cp) {
      case '"': sb_add(b, "\\\"", 2); break;
      case '\\': sb_add(b, "\\\\", 2); break;
      case '\b': sb_add(b, "\\b", 2); break;
      case '\f': sb_add(b, "\\f", 2); break;
      case '\n': sb_add(b, "\\n", 2); break;
      case '\r': sb_add(b, "\\r", 2); break;
      case '\t': sb_add(b, "\\t", 2); break;
      default:
        if (cp >= 0x20 && cp <= 0x7E) {
          char c = (char)cp;
          sb_add(b, &c, 1);
        } else if (cp < 0x10000) {
          sb_printf(b, "\\u%04x", cp);
        } else {
          unsigned v = cp - 0x10000;
          sb_printf(b, "\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
        }
    }
  }
  sb_add(b, "\"", 1);
}

void sb_jstrz(sbuf* b, const char* s) { sb_jstr(b, s, strlen(s)); }

void sb_key(sbuf* b, int* first, const char* key) {
  if (!*first)
    sb_add(b, ", ", 2);
  *first = 0;
  sb_jstrz(b, key);
  sb_add(b, ": ", 2);
}

static void put_number(sbuf* b, const jval* v) {
  char t[64];
  int prec;
  if (v->isint) {
    sb_printf(b, "%lld", v->ival);
    return;
  }
  for (prec = 1; prec <= 17; prec++) { /* Python's repr: the shortest text that reads back as the same double */
    snprintf(t, sizeof t, "%.*g", prec, v->num);
    if (strtod(t, NULL) == v->num)
      break;
  }
  if (strchr(t, '.') == NULL && strchr(t, 'e') == NULL && strchr(t, 'n') == NULL && strchr(t, 'i') == NULL)
    strcat(t, ".0");
  sb_puts(b, t);
}

static void indent(sbuf* b, int level) {
  int i;
  for (i = 0; i < level; i++)
    sb_add(b, " ", 1);
}

static int key_order(const void* a, const void* b) {
  const char* const* x = (const char* const*)a;
  const char* const* y = (const char* const*)b;
  return strcmp(x[0], y[0]); /* UTF-8 byte order is code point order: Python's sort_keys */
}

void json_pretty(sbuf* b, const jval* v, int level) {
  size_t i;
  switch (v->t) {
    case J_NULL: sb_puts(b, "null"); return;
    case J_TRUE: sb_puts(b, "true"); return;
    case J_FALSE: sb_puts(b, "false"); return;
    case J_NUM: put_number(b, v); return;
    case J_STR: sb_jstr(b, v->s, v->slen); return;
    case J_ARR:
      if (v->n == 0) {
        sb_puts(b, "[]");
        return;
      }
      sb_puts(b, "[\n");
      for (i = 0; i < v->n; i++) {
        indent(b, level + 1);
        json_pretty(b, v->items[i], level + 1);
        sb_puts(b, (i + 1 < v->n) ? ",\n" : "\n");
      }
      indent(b, level);
      sb_puts(b, "]");
      return;
    case J_OBJ: {
      const char** pairs;
      if (v->n == 0) {
        sb_puts(b, "{}");
        return;
      }
      pairs = (const char**)xalloc(v->n * 2 * sizeof(char*));
      for (i = 0; i < v->n; i++) {
        pairs[2 * i] = v->keys[i];
        pairs[2 * i + 1] = (const char*)v->items[i];
      }
      qsort(pairs, v->n, 2 * sizeof(char*), key_order);
      sb_puts(b, "{\n");
      for (i = 0; i < v->n; i++) {
        indent(b, level + 1);
        sb_jstrz(b, pairs[2 * i]);
        sb_puts(b, ": ");
        json_pretty(b, (const jval*)pairs[2 * i + 1], level + 1);
        sb_puts(b, (i + 1 < v->n) ? ",\n" : "\n");
      }
      free(pairs);
      indent(b, level);
      sb_puts(b, "}");
      return;
    }
  }
}

/* END-CODE */
