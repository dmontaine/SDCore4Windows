/* SDAI_MAIN.C
 * sd-ai.exe, the in-SD model helper of SD Core for Windows: the decisions, one request, the pipe, the service.
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
 * 13 Nov 26 Windows port - New (RELEASE_1.1 246; the owner, 13 Nov 2026: "python not being an integral part of windows argues for the c
 *           helper").  The Python helper gplbld/sd-ai (from Linux b1d496df) rewritten in C, function for function: the decisions, their order,
 *           the providers, the wire formats, the limits, hygiene, the settings and their checks are Linux's, and every line on the pipe is the
 *           byte string the Python helper wrote (json.dumps with ensure_ascii and ", " / ": ").  Needs no Python: the AI no longer depends on the
 *           installer's Python box.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *   sd-ai.exe --service                                      the service itself (sd-ai's binPath; install-aihelper.ps1 registers it)
 *   sd-ai.exe --one [--state DIR] [--providers FILE]         one request on standard input/output (what the service starts per connection)
 *   sd-ai.exe --listen PIPE [--state DIR] [--providers FILE] the service's loop in the foreground, on another pipe (the tests)
 *   sd-ai.exe show | provider ... | key ... | ...             the administrator's client (sdai_ctl.c; Linux's sd-ai-ctl)
 *
 * The Windows service sd-ai, running as the virtual account NT SERVICE\sd-ai, listens on the pipe \\.\pipe\sd-ai and starts ONE short-lived
 * process of this program per connection (Linux: sd-ai.socket, Accept=true).  That process has the connection as its standard input and
 * output: ONE JSON line in, ONE JSON line out.  Nothing else in SD connects outward; nothing else reads the keys.
 *
 * REQUEST:  {"v":1,"op":"ask","system":"...","prompt":"...","maxtokens":1024[,"history":[{"q":"...","a":"..."}, ...]]}   or  {"v":1,"op":"status"}
 * REPLY:    {"t": "ok", "text": "...", "in": N, "out": N, "provider": "anthropic", "truncated": false, "replaced": N}
 *           {"t": "err", "code": "nogate|noadmin|disabled|nomodel|nokey|nolist|toobig|limit|net|timeout|refused|busy|declined|badreply|badreq|badconf", "msg": "..."}
 *           {"t": "status", ...}      {"t": "models", "provider": .., "models": [...]}
 * THE SETTINGS (set, keyset, keyclear, models) are the administrator's ONLY, by the caller's token read from the pipe.
 *
 * WHAT IT DECIDES, IN THIS ORDER (a caller learns nothing about the settings until the gate has let them through):
 *   1 THE GATE: the caller read from the pipe (sdai_win.c) must be a member of sdaiusers, read live; SDSYS, elevated, may ask without it (S.163).
 *   2 disabled when no provider is selected (the delivered state); nomodel; nokey.
 *   3 toobig (the request), limit (requests per hour and tokens per day, per caller, in a locked file).
 *   4 ONE HTTPS call to the selected provider's URL (sdai_https.c): certificate and host name verified, TLS 1.2 or later, no insecure mode, no
 *     redirect, no proxy, the key sent only there; one retry on 429 / 5xx; at most 4 MB read.  The reply is cut to ASCII, newline and tab.
 * NOTHING IS WRITTEN TO THE AUDIT TRAIL HERE: SD writes "ai request ..." BEFORE it asks.  The one line this program writes per request, to
 * sd-ai.log in the state directory, has the caller's SID, the provider, the status and the sizes - never the text, never the key.
 *
 * END-DESCRIPTION
 */

#include "sdai.h"

#include <aclapi.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define VERSION 1
#define SERVICE_NAME L"sd-ai"
#define PIPE_NAME L"\\\\.\\pipe\\sd-ai"
#define PIPE_CLIENT_MASK 0x00120183 /* read, write, attributes, the owner; NOT FILE_APPEND_DATA (FILE_CREATE_PIPE_INSTANCE): win32ai.c's AI_ACCESS */
#define MAX_INSTANCES 16            /* Linux's MaxConnections=16 */
#define PIPE_BUFFER 65536
#define WATCHDOG_MS ((5 + 300 + 5) * 1000) /* limit.timeout is at most 300: past this a request process is stuck and ends (Linux: alarm) */
#define MODELS_MAX 500
#define ERRTEXT_MAX 160
#define CONTEXT_MAX 4000
#define HISTORY_MAX 3

static const char* NAMED[] = {"anthropic", "openai", "google", "deepseek"};
static const char* PROVIDERS[] = {"anthropic", "openai", "google", "deepseek", "custom"};
static const char* LIMIT_NAMES[] = {"requests-hour", "tokens-day", "timeout", "bytes-request", "bytes-reply", "max-tokens"};
static const long long LIMIT_DEFAULTS[] = {20, 100000, 30, 65536, 65536, 1024};
enum { L_REQ_HOUR, L_TOK_DAY, L_TIMEOUT, L_BYTES_REQ, L_BYTES_REPLY, L_MAX_TOKENS, N_LIMITS };

static wchar_t* g_state;
static wchar_t* g_providers;

/* ---------------------------------------------------------------- refusals and small text helpers */

static char r_code[24];
static char r_msg[1024];

static int refuse(const char* code, const char* fmt, ...) {
  va_list ap;
  snprintf(r_code, sizeof r_code, "%s", code);
  va_start(ap, fmt);
  vsnprintf(r_msg, sizeof r_msg, fmt, ap);
  va_end(ap);
  return -1;
}

static int is_alnum(int c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'); }

static int py_space(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0x0b || c == 0x0c || (c >= 0x1c && c <= 0x1f); }

static char* py_strip(const char* s) { /* str.strip() of ASCII text: a new string */
  size_t a = 0, b = strlen(s);
  char* o;
  while (a < b && py_space((unsigned char)s[a]))
    a++;
  while (b > a && py_space((unsigned char)s[b - 1]))
    b--;
  o = (char*)malloc(b - a + 1);
  if (o == NULL)
    ExitProcess(9);
  memcpy(o, s + a, b - a);
  o[b - a] = '\0';
  return o;
}

static int blank(const char* s, size_t n) {
  size_t i;
  for (i = 0; i < n; i++)
    if (!py_space((unsigned char)s[i]))
      return 0;
  return 1;
}

static int in_list(const char* s, const char** list, int n) {
  int i;
  for (i = 0; i < n; i++)
    if (strcmp(s, list[i]) == 0)
      return 1;
  return 0;
}

static int chars_in(const char* s, const char* extra) { /* every character a letter, a digit or one of extra */
  for (; *s; s++)
    if (!is_alnum((unsigned char)*s) && strchr(extra, *s) == NULL)
      return 0;
  return 1;
}

static int match_model(const char* s) { /* ^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,99}$ */
  size_t n = strlen(s);
  return n >= 1 && n <= 100 && is_alnum((unsigned char)s[0]) && chars_in(s, "._:/@+-");
}

static int match_version(const char* s) { size_t n = strlen(s); return n >= 1 && n <= 40 && chars_in(s, "._-"); }

static int match_name(const char* s) { size_t n = strlen(s); return n >= 1 && n <= 40 && is_alnum((unsigned char)s[0]) && chars_in(s, " ._-"); }

static int match_key(const char* s, size_t n) {
  size_t i;
  if (n < 8 || n > 512)
    return 0;
  for (i = 0; i < n; i++)
    if ((unsigned char)s[i] < 0x21 || (unsigned char)s[i] > 0x7e)
      return 0;
  return 1;
}

static int context_chars(const char* s, size_t n) {
  size_t i;
  for (i = 0; i < n; i++)
    if (s[i] != '\n' && ((unsigned char)s[i] < 0x20 || (unsigned char)s[i] > 0x7e))
      return 0;
  return 1;
}

/* URL_RE = ^https://([A-Za-z0-9][A-Za-z0-9.-]{0,252})(:[0-9]{1,5})?(/[A-Za-z0-9._~/+,:-]{0,500})?$ - no query string, no % escape. */
static int url_parse(const char* u, char* host, size_t hn, int* port, int* has_port, const char** path) {
  const char* p;
  const char* h;
  size_t n = 0;
  if (strncmp(u, "https://", 8) != 0)
    return 0;
  h = p = u + 8;
  if (!is_alnum((unsigned char)*p))
    return 0;
  while (is_alnum((unsigned char)*p) || *p == '.' || *p == '-')
    p++;
  n = (size_t)(p - h);
  if (n > 253 || n + 1 > hn)
    return 0;
  memcpy(host, h, n);
  host[n] = '\0';
  *has_port = 0;
  *port = 443;
  if (*p == ':') {
    const char* d = ++p;
    long v = 0;
    while (*p >= '0' && *p <= '9')
      v = v * 10 + (*p++ - '0');
    if (p == d || p - d > 5)
      return 0;
    *port = (int)v;
    *has_port = 1;
  }
  *path = p;
  if (*p == '\0')
    return 1;
  if (*p != '/' || strlen(p) > 501)
    return 0;
  return chars_in(p, "._~/+,:-");
}

/* A local drive path written with forward slashes (C:/...), no .. part: ^[A-Za-z]:/[A-Za-z0-9._/+-]{1,200}$ */
static int plain_path(const char* v) {
  size_t n = strlen(v);
  const char* s;
  if (n < 4 || n > 203 || !((v[0] >= 'A' && v[0] <= 'Z') || (v[0] >= 'a' && v[0] <= 'z')) || v[1] != ':' || v[2] != '/' || !chars_in(v + 3, "._/+-"))
    return 0;
  for (s = v + 2; s != NULL; s = strchr(s + 1, '/')) {
    if (strncmp(s + 1, "..", 2) == 0 && (s[3] == '/' || s[3] == '\0'))
      return 0;
  }
  return 1;
}

/* ---------------------------------------------------------------- key=value lists */

typedef struct {
  size_t n, cap;
  char** k;
  char** v;
} kvlist;

static const char* kv_get(const kvlist* l, const char* k) {
  size_t i;
  for (i = 0; i < l->n; i++)
    if (strcmp(l->k[i], k) == 0)
      return l->v[i];
  return NULL;
}

static const char* kv_str(const kvlist* l, const char* k, const char* dflt) {
  const char* v = kv_get(l, k);
  return v ? v : dflt;
}

static void kv_set(kvlist* l, const char* k, const char* v) {
  size_t i;
  for (i = 0; i < l->n; i++)
    if (strcmp(l->k[i], k) == 0) {
      l->v[i] = _strdup(v);
      return;
    }
  if (l->n == l->cap) {
    l->cap = l->cap ? l->cap * 2 : 16;
    l->k = (char**)realloc(l->k, l->cap * sizeof(char*));
    l->v = (char**)realloc(l->v, l->cap * sizeof(char*));
    if (l->k == NULL || l->v == NULL)
      ExitProcess(9);
  }
  l->k[l->n] = _strdup(k);
  l->v[l->n++] = _strdup(v);
}

static void kv_del(kvlist* l, const char* k) {
  size_t i;
  for (i = 0; i < l->n; i++)
    if (strcmp(l->k[i], k) == 0) {
      memmove(l->k + i, l->k + i + 1, (l->n - i - 1) * sizeof(char*));
      memmove(l->v + i, l->v + i + 1, (l->n - i - 1) * sizeof(char*));
      l->n--;
      return;
    }
}

static void kv_copy(kvlist* to, const kvlist* from) {
  size_t i;
  memset(to, 0, sizeof *to);
  for (i = 0; i < from->n; i++)
    kv_set(to, from->k[i], from->v[i]);
}

static void kv_prefix(kvlist* to, const kvlist* from, const char* prefix) { /* {k[len(prefix):]: v for k, v in from if k.startswith(prefix)} */
  size_t i, n = strlen(prefix);
  memset(to, 0, sizeof *to);
  for (i = 0; i < from->n; i++)
    if (strncmp(from->k[i], prefix, n) == 0)
      kv_set(to, from->k[i] + n, from->v[i]);
}

/* The lines of an ASCII text file as Python's text mode reads them (\r\n, \r and \n all end a line).  0 read, 1 not there, -1 not readable
   (*why the class Python would have named). */
static int text_lines(const wchar_t* path, char*** lines, int* count, const char** why) {
  char* data;
  size_t n, i, start = 0;
  int rc = read_file(path, 4 * 1024 * 1024, &data, &n);
  *count = 0;
  *lines = NULL;
  if (rc != 0) {
    *why = "PermissionError";
    return rc;
  }
  for (i = 0; i < n; i++)
    if ((unsigned char)data[i] > 0x7f) {
      *why = "UnicodeDecodeError";
      return -1;
    }
  *lines = (char**)calloc(n + 2, sizeof(char*));
  if (*lines == NULL)
    ExitProcess(9);
  for (i = 0; i <= n; i++) {
    if (i == n || data[i] == '\n' || data[i] == '\r') {
      if (i == n && i == start)
        break;
      data[i == n ? n : i] = '\0';
      (*lines)[(*count)++] = data + start;
      if (i < n && data[i] == '\r' && i + 1 < n && data[i + 1] == '\n')
        i++;
      start = i + 1;
    }
  }
  return 0;
}

static int skip_line(const char* line) {
  const char* s = line;
  if (blank(line, strlen(line)))
    return 1;
  while (py_space((unsigned char)*s))
    s++;
  return *s == '#';
}

static void split_kv(kvlist* l, const char* line) {
  char* c = _strdup(line);
  char* eq = strchr(c, '=');
  char *k, *v;
  *eq = '\0';
  k = py_strip(c);
  v = py_strip(eq + 1);
  kv_set(l, k, v);
}

/* key=value lines (blank lines and # comments allowed); a line with no = is a damaged file, not something to skip.  Missing is empty. */
static int parse_kv(const wchar_t* path, const char* base, kvlist* out) {
  char** lines;
  int count, i, rc;
  const char* why = "";
  memset(out, 0, sizeof *out);
  rc = text_lines(path, &lines, &count, &why);
  if (rc == 1)
    return 0;
  if (rc < 0)
    return refuse("badconf", "cannot read %s: %s", base, why);
  for (i = 0; i < count; i++) {
    if (skip_line(lines[i]))
      continue;
    if (strchr(lines[i], '=') == NULL)
      return refuse("badconf", "%s line %d has no =", base, i + 1);
    split_kv(out, lines[i]);
  }
  return 0;
}

/* ---------------------------------------------------------------- the providers and the selected one */

typedef struct {
  char name[16];
  kvlist p;
} provider_t;

static provider_t table[4];
static int ntable;

static int check_connection(const kvlist* p, const char* what) {
  char host[260];
  int port, has_port;
  const char* path;
  const char* v;
  if (!url_parse(kv_str(p, "url", ""), host, sizeof host, &port, &has_port, &path))
    return refuse("badconf", "%s: url must be https://host[:port]/path with plain characters", what);
  if (host[strlen(host) - 1] == '-' || strstr(host, "..") != NULL || (has_port && (port < 1 || port > 65535)))
    return refuse("badconf", "%s: bad host or port", what);
  v = kv_get(p, "format");
  if (v == NULL || (strcmp(v, "anthropic") != 0 && strcmp(v, "openai") != 0))
    return refuse("badconf", "%s: format must be one of anthropic, openai", what);
  v = kv_get(p, "auth");
  if (v == NULL || (strcmp(v, "bearer") != 0 && strcmp(v, "x-api-key") != 0))
    return refuse("badconf", "%s: auth must be one of bearer, x-api-key", what);
  v = kv_get(p, "maxparam");
  if (v == NULL || (strcmp(v, "max_tokens") != 0 && strcmp(v, "max_completion_tokens") != 0))
    return refuse("badconf", "%s: maxparam must be one of max_tokens, max_completion_tokens", what);
  v = kv_str(p, "version", "");
  if (v[0] != '\0' && !match_version(v))
    return refuse("badconf", "%s: version has characters a header value may not have", what);
  if (!match_name(kv_str(p, "name", "x")))
    return refuse("badconf", "%s: name", what);
  return 0;
}

/* The shipped table: [name] sections of key=value lines, only the named providers, every value checked. */
static int read_providers(void) {
  char** lines;
  int count, i, rc, cur = -1;
  const char* why;
  char what[256];
  ntable = 0;
  rc = text_lines(g_providers, &lines, &count, &why);
  if (rc == 1)
    return refuse("badconf", "the providers file is missing");
  if (rc < 0)
    return refuse("badconf", "cannot read the providers file");
  for (i = 0; i < count; i++) {
    char* s;
    size_t n;
    if (skip_line(lines[i]))
      continue;
    s = py_strip(lines[i]);
    n = strlen(s);
    if (n >= 3 && s[0] == '[' && s[n - 1] == ']') {
      size_t j;
      int ok = 1, k;
      for (j = 1; j + 1 < n; j++)
        if (s[j] < 'a' || s[j] > 'z')
          ok = 0;
      if (ok) {
        s[n - 1] = '\0';
        for (k = 0; k < ntable; k++)
          if (strcmp(table[k].name, s + 1) == 0)
            ok = 0;
        if (!ok || !in_list(s + 1, NAMED, 4))
          return refuse("badconf", "providers file: section %s is not a shipped provider or is repeated", s + 1);
        cur = ntable++;
        snprintf(table[cur].name, sizeof table[cur].name, "%s", s + 1);
        memset(&table[cur].p, 0, sizeof table[cur].p);
        continue;
      }
    }
    if (cur < 0 || strchr(lines[i], '=') == NULL)
      return refuse("badconf", "providers file line %d", i + 1);
    split_kv(&table[cur].p, lines[i]);
  }
  for (i = 0; i < ntable; i++) {
    snprintf(what, sizeof what, "providers file [%s]", table[i].name);
    if (check_connection(&table[i].p, what) < 0)
      return -1;
    if (!match_model(kv_str(&table[i].p, "model", "x")))
      return refuse("badconf", "providers file [%s]: model has characters a model name may not have", table[i].name);
  }
  if (ntable != 4)
    return refuse("badconf", "providers file does not describe exactly anthropic, openai, google, deepseek");
  return 0;
}

static const kvlist* table_get(const char* name) {
  int i;
  for (i = 0; i < ntable; i++)
    if (strcmp(table[i].name, name) == 0)
      return &table[i].p;
  return NULL;
}

/* 1 with the provider's name, its connection details and its model; 0 when AI is off (no provider selected); -1 refused. */
static int selected(const kvlist* conf, const char** name, kvlist* p, const char** model) {
  const char* n = kv_str(conf, "provider", "");
  char key[64];
  const char* m;
  if (n[0] == '\0')
    return 0;
  if (!in_list(n, PROVIDERS, 5))
    return refuse("badconf", "provider is not one of anthropic, openai, google, deepseek, custom");
  if (strcmp(n, "custom") == 0) {
    kv_prefix(p, conf, "custom.");
    if (check_connection(p, "the custom provider") < 0)
      return -1;
    if (kv_get(p, "name") == NULL)
      kv_set(p, "name", "Custom");
  } else
    kv_copy(p, table_get(n));
  *name = n;
  snprintf(key, sizeof key, "model.%s", n);
  m = kv_str(conf, key, "");
  *model = (m[0] != '\0') ? m : kv_str(p, "model", "");
  return 1;
}

/* Python's int() of a text: white space round it, a sign, digits (an underscore between two of them). */
static int py_int_text(const char* s, long long* out) {
  char* t = py_strip(s);
  const char* p = t;
  int neg = 0, digits = 0;
  long long v = 0;
  if (*p == '+' || *p == '-')
    neg = (*p++ == '-');
  for (; *p; p++) {
    if (*p == '_' && digits && p[1] >= '0' && p[1] <= '9')
      continue;
    if (*p < '0' || *p > '9')
      return 0;
    if (v < 100000000000000000LL)
      v = v * 10 + (*p - '0');
    else
      v = 9000000000000000000LL; /* past every range here */
    digits++;
  }
  if (!digits)
    return 0;
  *out = neg ? -v : v;
  return 1;
}

static int int_setting(const kvlist* conf, int which, long long* out) {
  char key[64];
  char dflt[32];
  long long v;
  snprintf(key, sizeof key, "limit.%s", LIMIT_NAMES[which]);
  snprintf(dflt, sizeof dflt, "%lld", LIMIT_DEFAULTS[which]);
  if (!py_int_text(kv_str(conf, key, dflt), &v))
    return refuse("badconf", "limit.%s is not a number", LIMIT_NAMES[which]);
  if (v < 1 || v > ((which == L_TIMEOUT) ? 300 : 1000000000LL))
    return refuse("badconf", "limit.%s out of range", LIMIT_NAMES[which]);
  *out = v;
  return 0;
}

static int all_limits(const kvlist* conf, long long* lim) {
  int i;
  for (i = 0; i < N_LIMITS; i++)
    if (int_setting(conf, i, &lim[i]) < 0)
      return -1;
  return 0;
}

static int ca_file(const kvlist* conf, const char** ca) {
  const char* v = kv_str(conf, "ca-file", "");
  *ca = NULL;
  if (v[0] == '\0')
    return 0;
  if (!plain_path(v))
    return refuse("badconf", "ca-file is not a plain drive path written with /");
  *ca = v;
  return 0;
}

static wchar_t* state_path(const char* a, const char* b) {
  wchar_t* d = wjoin(g_state, a);
  wchar_t* p;
  if (b == NULL)
    return d;
  p = wjoin(d, b);
  free(d);
  return p;
}

/* ---------------------------------------------------------------- the key and the limits */

/* The DPAPI entropy of a provider's key: "sd-ai key <provider>", so a blob made for one provider is not read as another's.  The Python helper's
   key_entropy(), so its blobs open here. */
static void key_entropy(char* out, size_t n, const char* name) { snprintf(out, n, "sd-ai key %s", name); }

static int read_key(const char* name, char** key) {
  wchar_t* path = state_path("keys", name);
  char entropy[64];
  char* blob;
  size_t n;
  BYTE* raw;
  DWORD rn;
  char* s;
  if (!path_exists(path))
    return refuse("nokey", "no key has been set for this provider");
  if (!private_file(path))
    return refuse("nokey", "the key file is not private");
  if (read_file(path, 65536, &blob, &n) != 0)
    return refuse("nokey", "the key file cannot be read");
  key_entropy(entropy, sizeof entropy, name);
  if (!dpapi((BYTE*)blob, (DWORD)n, entropy, 0, &raw, &rn))
    return refuse("nokey", "the key file cannot be opened by this helper");
  s = (char*)malloc(rn + 1);
  if (s == NULL)
    ExitProcess(9);
  memcpy(s, raw, rn);
  s[rn] = '\0';
  SecureZeroMemory(raw, rn);
  free(raw);
  {
    size_t i;
    for (i = 0; i < rn; i++) /* raw.decode("ascii") */
      if ((unsigned char)s[i] > 0x7f || s[i] == '\0')
        return refuse("nokey", "the key file does not hold a key");
  }
  *key = py_strip(s);
  SecureZeroMemory(s, rn);
  free(s);
  if (!match_key(*key, strlen(*key)))
    return refuse("nokey", "the key file does not hold a key");
  return 0;
}

static double now_secs(void) {
  FILETIME ft;
  ULARGE_INTEGER u;
  GetSystemTimeAsFileTime(&ft);
  u.LowPart = ft.dwLowDateTime;
  u.HighPart = ft.dwHighDateTime;
  return (double)(u.QuadPart - 116444736000000000ULL) / 1e7;
}

/* The per-caller counters under an exclusive lock.  count: check the limits and, if they hold, record the request; add_tokens: add a finished
   request's tokens.  Requests are kept as the times of the last hour, tokens as the total of the UTC day.  The file is named by the caller's SID. */
static int counters(const char* sid, const long long* lim, long long add_tokens, int count) {
  char name[220];
  wchar_t* path;
  HANDLE h;
  char* raw;
  DWORD got = 0, size;
  double now = now_secs();
  double reqs[4096];
  int nreq = 0, i, ok = 1;
  char day[32] = "";
  char today[32];
  long long tokens = 0;
  jval* j;
  time_t tt = (time_t)now;
  struct tm* g = gmtime(&tt);
  sbuf out;
  snprintf(name, sizeof name, "u%s", sid);
  path = state_path("state", name);
  h = lock_open(path);
  if (h == INVALID_HANDLE_VALUE)
    return refuse("limit", "the counters cannot be kept, so no request is made");
  size = GetFileSize(h, NULL);
  if (size == INVALID_FILE_SIZE || size > 1024 * 1024)
    size = 0;
  raw = (char*)calloc(size + 1, 1);
  if (raw == NULL)
    ExitProcess(9);
  SetFilePointer(h, 0, NULL, FILE_BEGIN);
  if (size > 0 && !ReadFile(h, raw, size, &got, NULL))
    got = 0;
  j = json_parse(raw, got);
  if (got == 0)
    j = json_parse("{}", 2);
  if (j == NULL || j->t != J_OBJ)
    ok = 0;
  if (ok) {
    jval* r = json_get(j, "requests");
    jval* d = json_get(j, "day");
    jval* t = json_get(j, "tokens");
    if (r != NULL) {
      if (r->t != J_ARR)
        ok = 0;
      for (i = 0; ok && (size_t)i < r->n; i++) {
        if (r->items[i]->t != J_NUM)
          ok = 0;
        else if (now - r->items[i]->num < 3600 && nreq < 4096)
          reqs[nreq++] = r->items[i]->num;
      }
    }
    if (ok && d != NULL && d->t == J_STR)
      snprintf(day, sizeof day, "%s", d->s);
    if (ok && t != NULL) {
      if (t->t == J_NUM)
        tokens = t->ival;
      else
        ok = 0;
    }
  }
  if (!ok) {
    nreq = 0;
    day[0] = '\0';
    tokens = 0;
  }
  strftime(today, sizeof today, "%Y-%m-%d", g);
  if (strcmp(day, today) != 0) {
    snprintf(day, sizeof day, "%s", today);
    tokens = 0;
  }
  if (count) {
    if (nreq >= lim[L_REQ_HOUR]) {
      lock_close(h);
      return refuse("limit", "the hourly limit of %lld requests is used up", lim[L_REQ_HOUR]);
    }
    if (tokens >= lim[L_TOK_DAY]) {
      lock_close(h);
      return refuse("limit", "the daily limit of %lld tokens is used up", lim[L_TOK_DAY]);
    }
    if (nreq < 4096)
      reqs[nreq++] = now;
  }
  if (add_tokens)
    tokens += add_tokens;
  sb_init(&out);
  sb_puts(&out, "{\"requests\": [");
  for (i = 0; i < nreq; i++)
    sb_printf(&out, "%s%.6f", i ? ", " : "", reqs[i]);
  sb_puts(&out, "], \"day\": ");
  sb_jstrz(&out, day);
  sb_printf(&out, ", \"tokens\": %lld}", tokens);
  SetFilePointer(h, 0, NULL, FILE_BEGIN);
  SetEndOfFile(h);
  {
    DWORD w = 0;
    WriteFile(h, out.p, (DWORD)out.n, &w, NULL);
  }
  lock_close(h);
  return 0;
}

/* ---------------------------------------------------------------- reply hygiene */

/* ASCII, newline and tab only: typographic quotes, dashes, spaces and bullets become their plain forms, a carriage return goes, anything else
   becomes ? (counted). */
static void hygiene(const char* s, size_t n, sbuf* out, long long* replaced) {
  size_t i = 0;
  *replaced = 0;
  while (i < n) {
    unsigned char c = (unsigned char)s[i];
    unsigned cp;
    int k;
    if (c < 0x80) {
      cp = c;
      k = 1;
    } else if ((c & 0xE0) == 0xC0 && i + 1 < n) {
      cp = ((c & 0x1F) << 6) | (s[i + 1] & 0x3F);
      k = 2;
    } else if ((c & 0xF0) == 0xE0 && i + 2 < n) {
      cp = ((c & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F);
      k = 3;
    } else if ((c & 0xF8) == 0xF0 && i + 3 < n) {
      cp = ((c & 0x07) << 18) | ((s[i + 1] & 0x3F) << 12) | ((s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F);
      k = 4;
    } else {
      cp = 0xFFFD;
      k = 1;
    }
    i += (size_t)k;
    if (cp == '\n' || cp == '\t' || (cp >= 0x20 && cp < 0x7f)) {
      char ch = (char)cp;
      sb_add(out, &ch, 1);
    } else if (cp == '\r')
      continue;
    else {
      switch (cp) {
        case 0x2018: case 0x2019: case 0x201A: sb_puts(out, "'"); break;
        case 0x201C: case 0x201D: case 0x201E: sb_puts(out, "\""); break;
        case 0x2013: case 0x2014: case 0x2212: sb_puts(out, "-"); break;
        case 0x2026: sb_puts(out, "..."); break;
        case 0x00A0: case 0x2009: case 0x202F: sb_puts(out, " "); break;
        case 0x2022: case 0x00B7: sb_puts(out, "*"); break;
        default:
          sb_puts(out, "?");
          (*replaced)++;
      }
    }
  }
}

static size_t codepoints(const char* s, size_t n) {
  size_t i, k = 0;
  for (i = 0; i < n; i++)
    if (((unsigned char)s[i] & 0xC0) != 0x80)
      k++;
  return k;
}

/* ---------------------------------------------------------------- the provider call */

typedef struct {
  const char* q;
  size_t qn;
  const char* a;
  size_t an;
} exchange_t;

static void add_message(sbuf* b, int* first, const char* role, const char* text, size_t n) {
  if (!*first)
    sb_puts(b, ", ");
  *first = 0;
  sb_puts(b, "{\"role\": ");
  sb_jstrz(b, role);
  sb_puts(b, ", \"content\": ");
  sb_jstr(b, text, n);
  sb_puts(b, "}");
}

static void history_messages(sbuf* b, int* first, const exchange_t* h, int nh) {
  int i;
  for (i = 0; i < nh; i++) {
    add_message(b, first, "user", h[i].q, h[i].qn);
    if (blank(h[i].a, h[i].an))
      add_message(b, first, "assistant", "(no answer)", 11);
    else
      add_message(b, first, "assistant", h[i].a, h[i].an);
  }
}

static void auth_headers(sbuf* h, const kvlist* p, const char* key) {
  if (strcmp(kv_str(p, "auth", ""), "bearer") == 0)
    sb_printf(h, "Authorization: Bearer %s\r\n", key);
  else
    sb_printf(h, "x-api-key: %s\r\n", key);
  if (strcmp(kv_str(p, "format", ""), "anthropic") == 0) {
    const char* v = kv_str(p, "version", "");
    sb_printf(h, "anthropic-version: %s\r\n", v[0] ? v : "2023-06-01");
  }
}

typedef struct {
  char host[260];
  int port;
  char path[520];
} target_t;

static void target_of(const kvlist* p, target_t* t) {
  int has_port;
  const char* path;
  size_t i;
  url_parse(kv_str(p, "url", ""), t->host, sizeof t->host, &t->port, &has_port, &path);
  for (i = 0; t->host[i]; i++) /* urlsplit's hostname is lower case */
    if (t->host[i] >= 'A' && t->host[i] <= 'Z')
      t->host[i] = (char)(t->host[i] - 'A' + 'a');
  snprintf(t->path, sizeof t->path, "%s", (*path != '\0') ? path : "/");
}

/* The request's headers and body for the provider's wire format; history (a follow-up) goes as messages before the prompt. */
static void build_request(const kvlist* p, const char* key, const char* model, const char* system, size_t sn, const char* prompt, size_t pn,
                          long long maxtokens, const exchange_t* h, int nh, sbuf* hdr, sbuf* body) {
  const char* maxparam = kv_str(p, "maxparam", "max_tokens");
  int first = 1;
  sb_init(hdr);
  sb_init(body);
  sb_puts(hdr, "Content-Type: application/json\r\nAccept: application/json\r\nUser-Agent: sd-ai/1\r\n");
  auth_headers(hdr, p, key);
  sb_puts(body, "{\"model\": ");
  sb_jstrz(body, model);
  sb_puts(body, ", ");
  sb_jstrz(body, maxparam);
  sb_printf(body, ": %lld, \"messages\": [", maxtokens);
  if (strcmp(kv_str(p, "format", ""), "anthropic") == 0) {
    history_messages(body, &first, h, nh);
    add_message(body, &first, "user", prompt, pn);
    sb_puts(body, "]");
    if (sn > 0) {
      sb_puts(body, ", \"system\": [{\"type\": \"text\", \"text\": ");
      sb_jstr(body, system, sn);
      if (codepoints(system, sn) >= 4096) /* a long fixed system text (the guide) is cached by the provider */
        sb_puts(body, ", \"cache_control\": {\"type\": \"ephemeral\"}");
      sb_puts(body, "}]");
    }
  } else {
    if (sn > 0)
      add_message(body, &first, "system", system, sn);
    history_messages(body, &first, h, nh);
    add_message(body, &first, "user", prompt, pn);
    sb_puts(body, "]");
  }
  sb_puts(body, "}");
}

/* Python's int() of a JSON value: a number truncated, a bool, a text of digits; anything else is not a number. */
static int py_int(const jval* v, long long* out) {
  if (v == NULL)
    return 0;
  switch (v->t) {
    case J_NUM: *out = v->ival; return 1;
    case J_TRUE: *out = 1; return 1;
    case J_FALSE: *out = 0; return 1;
    case J_STR: return py_int_text(v->s, out);
    default: return 0;
  }
}

static int jeq(const jval* v, const char* s) { return v != NULL && v->t == J_STR && strcmp(v->s, s) == 0; }

#define SHAPE() refuse("badreply", "the provider's answer has a shape this helper does not know")

static int parse_reply(const char* fmt, const char* raw, size_t n, sbuf* text, long long* tin, long long* tout, int* trunc) {
  jval* j = json_parse(raw, n);
  jval *u, *v;
  long long a, b, c;
  sb_init(text);
  if (j == NULL)
    return refuse("badreply", "the provider's answer is not JSON");
  if (j->t != J_OBJ)
    return refuse("badreply", "the provider's answer is not an object");
  if (jeq(json_get(j, "type"), "error") || (json_get(j, "error") != NULL && strcmp(fmt, "openai") == 0))
    return refuse("refused", "the provider returned an error");
  if (strcmp(fmt, "anthropic") == 0) {
    jval* content;
    if (jeq(json_get(j, "stop_reason"), "refusal"))
      return refuse("declined", "the model declined the request");
    content = json_get(j, "content");
    if (content == NULL)
      return SHAPE();
    if (content->t == J_ARR) {
      size_t i;
      for (i = 0; i < content->n; i++) {
        jval* blk = content->items[i];
        if (blk->t == J_OBJ && jeq(json_get(blk, "type"), "text")) {
          jval* t = json_get(blk, "text");
          if (t == NULL)
            continue;
          if (t->t != J_STR)
            return SHAPE();
          sb_add(text, t->s, t->slen);
        }
      }
    } else if (content->t != J_STR && content->t != J_OBJ)
      return SHAPE();
    u = json_get(j, "usage");
    a = b = c = 0;
    if (u != NULL) {
      if (u->t != J_OBJ)
        return SHAPE();
      v = json_get(u, "input_tokens");
      if (v != NULL && !py_int(v, &a))
        return SHAPE();
      v = json_get(u, "cache_creation_input_tokens");
      if (json_truthy(v) && !py_int(v, &b))
        return SHAPE();
      v = json_get(u, "cache_read_input_tokens");
      if (json_truthy(v) && !py_int(v, &c))
        return SHAPE();
      *tin = a + b + c;
      v = json_get(u, "output_tokens");
      *tout = 0;
      if (v != NULL && !py_int(v, tout))
        return SHAPE();
    } else
      *tin = *tout = 0;
    *trunc = jeq(json_get(j, "stop_reason"), "max_tokens");
    return 0;
  } else {
    jval *ch, *m, *ct;
    v = json_get(j, "choices");
    if (v == NULL || v->t != J_ARR || v->n == 0)
      return SHAPE();
    ch = v->items[0];
    if (ch->t != J_OBJ)
      return SHAPE();
    m = json_get(ch, "message");
    if (m == NULL || m->t != J_OBJ)
      return SHAPE();
    if (json_truthy(json_get(m, "refusal")) || jeq(json_get(ch, "finish_reason"), "content_filter"))
      return refuse("declined", "the model declined the request");
    ct = json_get(m, "content");
    u = json_get(j, "usage");
    *tin = *tout = 0;
    if (u != NULL) {
      if (u->t != J_OBJ)
        return SHAPE();
      v = json_get(u, "prompt_tokens");
      if (v != NULL && !py_int(v, tin))
        return SHAPE();
      v = json_get(u, "completion_tokens");
      if (v != NULL && !py_int(v, tout))
        return SHAPE();
    }
    *trunc = jeq(json_get(ch, "finish_reason"), "length");
    if (json_truthy(ct)) {
      if (ct->t != J_STR)
        return refuse("badreply", "the reply text is not text");
      sb_add(text, ct->s, ct->slen);
    }
    return 0;
  }
}

/* https_call with the network failures turned into refusals, and an answer that is far too large refused. */
static int call_once(const kvlist* p, const char* method, const char* path, const char* headers, const char* body, size_t blen, const char* ca,
                     double left, const long long* lim, http_resp* r) {
  target_t t;
  int ms = (int)(left * 1000.0);
  int rc;
  target_of(p, &t);
  rc = https_call(t.host, t.port, method, path, headers, body, blen, ca, ms > 0 ? ms : 1, r);
  switch (rc) {
    case HC_CERT: return refuse("net", "the provider's certificate was not accepted");
    case HC_TLS: return refuse("net", "the TLS connection failed");
    case HC_TIMEOUT: return refuse("timeout", "no answer in %lld seconds", lim[L_TIMEOUT]);
    case HC_NET: return refuse("net", "the provider could not be reached");
  }
  if (r->len > RAW_CAP)
    return refuse("badreply", "the provider's answer is far too large");
  return 0;
}

/* A short, safe excerpt of the provider's own explanation of a refusal (S.170): the key, if repeated, replaced; ASCII; one line; 160 characters. */
static void provider_words(const char* raw, size_t n, const char* key, char* out, size_t on) {
  jval* j = json_parse(raw, n);
  jval* msg = NULL;
  sbuf a, h;
  long long rep;
  size_t i, k = 0;
  int sp = 1;
  out[0] = '\0';
  if (j == NULL || j->t != J_OBJ)
    return;
  {
    jval* e = json_get(j, "error");
    if (e != NULL && e->t == J_OBJ)
      msg = json_get(e, "message");
    else if (e != NULL && e->t == J_STR)
      msg = e;
    if (!json_truthy(msg) && json_is_str(json_get(j, "message")))
      msg = json_get(j, "message");
  }
  if (!json_is_str(msg))
    return;
  sb_init(&a);
  if (key != NULL && key[0] != '\0') {
    const char* s = msg->s;
    size_t kl = strlen(key);
    const char* f;
    while ((f = strstr(s, key)) != NULL) {
      sb_add(&a, s, (size_t)(f - s));
      sb_puts(&a, "<key>");
      s = f + kl;
    }
    sb_puts(&a, s);
  } else
    sb_add(&a, msg->s, msg->slen);
  sb_init(&h);
  hygiene(a.p, a.n, &h, &rep);
  for (i = 0; i < h.n && k + 1 < on && k < ERRTEXT_MAX; i++) { /* " ".join(msg.split()) */
    char c = h.p[i];
    if (py_space((unsigned char)c)) {
      sp = 1;
      continue;
    }
    if (sp && k > 0) {
      if (k + 2 >= on || k + 1 >= ERRTEXT_MAX)
        break;
      out[k++] = ' ';
    }
    sp = 0;
    out[k++] = c;
  }
  out[k] = '\0';
}

static int check_status(const http_resp* r, const char* key) {
  char words[ERRTEXT_MAX + 4];
  char tail[ERRTEXT_MAX + 8] = "";
  if (r->status >= 300 && r->status < 400)
    return refuse("refused", "the provider answered with a redirect, which is not followed");
  if (r->status == 401 || r->status == 403)
    return refuse("refused", "the provider did not accept the key");
  provider_words(r->body, r->len, key, words, sizeof words);
  if (words[0] != '\0')
    snprintf(tail, sizeof tail, ": %s", words);
  if (r->status == 429 || r->status >= 500)
    return refuse("busy", "the provider is busy or failing (HTTP %d)%s", r->status, tail);
  if (r->status != 200)
    return refuse("refused", "the provider refused the request (HTTP %d)%s", r->status, tail);
  return 0;
}

/* The call, with one bounded retry on 429 and 5xx. */
static int ask(const kvlist* conf, const kvlist* p, const char* model, const char* key, const char* system, size_t sn, const char* prompt, size_t pn,
               long long maxtokens, const long long* lim, const exchange_t* h, int nh, sbuf* text, long long* tin, long long* tout, int* trunc) {
  sbuf hdr, body;
  const char* ca;
  target_t t;
  double deadline;
  int attempt;
  build_request(p, key, model, system, sn, prompt, pn, maxtokens, h, nh, &hdr, &body);
  if (ca_file(conf, &ca) < 0)
    return -1;
  target_of(p, &t);
  deadline = now_secs() + (double)lim[L_TIMEOUT];
  for (attempt = 1; attempt <= 2; attempt++) {
    double left = deadline - now_secs();
    http_resp r;
    if (left <= 0)
      return refuse("timeout", "no answer in %lld seconds", lim[L_TIMEOUT]);
    if (call_once(p, "POST", t.path, hdr.p, body.p, body.n, ca, left, lim, &r) < 0)
      return -1;
    if ((r.status == 429 || r.status == 500 || r.status == 502 || r.status == 503 || r.status == 504) && attempt == 1) {
      double wait = 1.0;
      if (r.has_retry_after) {
        char* end;
        double w = strtod(r.retry_after, &end);
        if (end != r.retry_after && blank(end, strlen(end)))
          wait = (w < 0.5) ? 0.5 : (w > 5.0 ? 5.0 : w);
      }
      if (now_secs() + wait < deadline) {
        SleepEx((DWORD)(wait * 1000.0), FALSE);
        continue;
      }
    }
    SecureZeroMemory(hdr.p, hdr.n);
    if (check_status(&r, key) < 0)
      return -1;
    return parse_reply(kv_str(p, "format", ""), r.body, r.len, text, tin, tout, trunc);
  }
  return refuse("busy", "the provider is busy");
}

/* ---------------------------------------------------------------- the provider's list of models (S.170) */

static int models_path(const kvlist* p, char* out, size_t on) {
  target_t t;
  size_t n;
  static const char* tails[] = {"/chat/completions", "/messages"};
  int i;
  target_of(p, &t);
  n = strlen(t.path);
  for (i = 0; i < 2; i++) {
    size_t k = strlen(tails[i]);
    if (n >= k && strcmp(t.path + n - k, tails[i]) == 0) {
      snprintf(out, on, "%.*s/models", (int)(n - k), t.path);
      return 1;
    }
  }
  return 0;
}

static int str_order(const void* a, const void* b) { return strcmp(*(const char* const*)a, *(const char* const*)b); }

static int list_models(const kvlist* conf, const char* name, const kvlist* p, const char* key, const long long* lim, char*** out, int* nout) {
  char path[600];
  sbuf hdr;
  const char* ca;
  http_resp r;
  jval *j, *data;
  char** ids;
  int n = 0, i, k;
  const char* pname = kv_str(p, "name", name);
  if (!models_path(p, path, sizeof path))
    return refuse("nolist", "%s has no list of models this helper knows how to ask for: type the model's name", pname);
  sb_init(&hdr);
  sb_puts(&hdr, "Accept: application/json\r\nUser-Agent: sd-ai/1\r\n");
  auth_headers(&hdr, p, key);
  if (strcmp(kv_str(p, "format", ""), "anthropic") == 0)
    strcat(path, "?limit=1000"); /* Anthropic pages its list (20 by default) */
  if (ca_file(conf, &ca) < 0)
    return -1;
  if (call_once(p, "GET", path, hdr.p, NULL, 0, ca, (double)lim[L_TIMEOUT], lim, &r) < 0)
    return -1;
  if (r.status == 404)
    return refuse("nolist", "%s gives no list of models: type the model's name", pname);
  if (check_status(&r, key) < 0)
    return -1;
  j = json_parse(r.body, r.len);
  data = json_get(j, "data");
  if (j == NULL || j->t != J_OBJ || data == NULL || !(data->t == J_ARR || data->t == J_OBJ || data->t == J_STR))
    return refuse("badreply", "the provider's list of models has a shape this helper does not know");
  ids = (char**)calloc((data->t == J_ARR ? data->n : 0) + 1, sizeof(char*));
  if (ids == NULL)
    ExitProcess(9);
  for (i = 0; data->t == J_ARR && (size_t)i < data->n; i++) {
    jval* d = data->items[i];
    jval* id = json_get(d, "id");
    const char* m;
    if (d->t != J_OBJ || !json_is_str(id) || strlen(id->s) != id->slen)
      continue;
    m = id->s;
    if (strncmp(m, "models/", 7) == 0) /* Google names its models models/<name>; requests take the name alone */
      m += 7;
    if (!match_model(m))
      continue;
    ids[n++] = (char*)m;
  }
  qsort(ids, (size_t)n, sizeof(char*), str_order);
  for (i = 0, k = 0; i < n; i++) /* a set: no name twice */
    if (k == 0 || strcmp(ids[k - 1], ids[i]) != 0)
      ids[k++] = ids[i];
  *out = ids;
  *nout = (k > MODELS_MAX) ? MODELS_MAX : k;
  return 0;
}

/* ---------------------------------------------------------------- the standing text, status */

/* The standing text and whose it is: the administrator's (state\context), else the shipped default beside the providers file, else none.
   A file that is not plain, is over CONTEXT_MAX or holds anything but printable ASCII and line feeds is "bad" and gives no text. */
static void read_context(char** text, const char** whose) {
  wchar_t* paths[2];
  const char* names[2] = {"own", "default"};
  int i;
  wchar_t* dir = wdirname(g_providers);
  paths[0] = wjoin(g_state, "context");
  paths[1] = wjoin(dir, "ai-context");
  *text = "";
  for (i = 0; i < 2; i++) {
    char* data;
    size_t n, k, w = 0;
    int rc;
    if (!path_exists(paths[i])) {
      DWORD e = GetLastError();
      if (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND)
        continue;
      *whose = "bad";
      return;
    }
    if (!path_plain_file(paths[i])) {
      *whose = "bad";
      return;
    }
    rc = read_file(paths[i], CONTEXT_MAX + 2, &data, &n);
    if (rc != 0 || n > CONTEXT_MAX + 1) {
      *whose = "bad";
      return;
    }
    for (k = 0; k < n; k++) {
      if ((unsigned char)data[k] > 0x7f) {
        *whose = "bad";
        return;
      }
      if (data[k] == '\r' && k + 1 < n && data[k + 1] == '\n')
        continue; /* \r\n becomes \n */
      data[w++] = data[k];
    }
    while (w > 0 && data[w - 1] == '\n')
      w--;
    data[w] = '\0';
    if (w > CONTEXT_MAX || !context_chars(data, w)) {
      *whose = "bad";
      return;
    }
    *text = data;
    *whose = names[i];
    return;
  }
  *whose = "none";
}

static char* title_case(const char* s) { /* str.title() of a provider's name */
  char* t = _strdup(s);
  int start = 1;
  char* p;
  for (p = t; *p; p++) {
    if (*p >= 'a' && *p <= 'z' && start)
      *p = (char)(*p - 'a' + 'A');
    else if (*p >= 'A' && *p <= 'Z' && !start)
      *p = (char)(*p - 'A' + 'a');
    start = !((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z'));
  }
  return t;
}

static int key_file_exists(const char* name) { return path_isfile(state_path("keys", name)); }

static void status_reply(const kvlist* conf, const caller_t* c, sbuf* out) {
  const char* name = NULL;
  const char* model = NULL;
  kvlist p;
  int sel, first = 1, gate, admin, i;
  long long lim[N_LIMITS];
  sel = selected(conf, &name, &p, &model);
  if (sel < 0) {
    sb_puts(out, "{\"t\": \"err\", \"code\": ");
    sb_jstrz(out, r_code);
    sb_puts(out, ", \"msg\": ");
    sb_jstrz(out, r_msg);
    sb_puts(out, "}");
    return;
  }
  admin = (c != NULL) && is_admin(c);
  if (admin && all_limits(conf, lim) < 0) { /* Python raised from inside the dictionary: the whole status is the refusal */
    sb_puts(out, "{\"t\": \"err\", \"code\": ");
    sb_jstrz(out, r_code);
    sb_puts(out, ", \"msg\": ");
    sb_jstrz(out, r_msg);
    sb_puts(out, "}");
    return;
  }
  gate = may_ask(c);
  sb_puts(out, "{");
  sb_key(out, &first, "t");
  sb_jstrz(out, "status");
  sb_key(out, &first, "provider");
  sb_jstrz(out, sel ? name : "");
  sb_key(out, &first, "model");
  sb_jstrz(out, sel ? model : "");
  sb_key(out, &first, "gate");
  sb_puts(out, gate ? "true" : "false");
  sb_key(out, &first, "key");
  sb_puts(out, (sel && key_file_exists(name)) ? "true" : "false");
  if (gate || admin) {
    char* text;
    const char* whose;
    read_context(&text, &whose);
    sb_key(out, &first, "context");
    sb_jstrz(out, text);
    sb_key(out, &first, "context-from");
    sb_jstrz(out, whose);
  }
  if (admin) {
    int f2 = 1;
    sb_key(out, &first, "providers");
    sb_puts(out, "{");
    for (i = 0; i < 5; i++) {
      const char* n = PROVIDERS[i];
      kvlist d;
      char mk[64];
      int f3 = 1;
      static const char* fields[] = {"url", "format", "auth", "version", "maxparam"};
      int k;
      if (strcmp(n, "custom") == 0)
        kv_prefix(&d, conf, "custom.");
      else
        kv_copy(&d, table_get(n));
      sb_key(out, &f2, n);
      sb_puts(out, "{");
      sb_key(out, &f3, "name");
      sb_jstrz(out, kv_str(&d, "name", title_case(n)));
      for (k = 0; k < 5; k++) {
        sb_key(out, &f3, fields[k]);
        sb_jstrz(out, kv_str(&d, fields[k], ""));
      }
      snprintf(mk, sizeof mk, "model.%s", n);
      sb_key(out, &f3, "model");
      sb_jstrz(out, kv_str(conf, mk, ""));
      sb_key(out, &f3, "default");
      sb_jstrz(out, strcmp(n, "custom") == 0 ? "" : kv_str(&d, "model", ""));
      sb_key(out, &f3, "key");
      sb_puts(out, key_file_exists(n) ? "true" : "false");
      sb_puts(out, "}");
    }
    sb_puts(out, "}");
    sb_key(out, &first, "ca-file");
    sb_jstrz(out, kv_str(conf, "ca-file", ""));
    sb_key(out, &first, "limits");
    sb_puts(out, "{");
    f2 = 1;
    for (i = 0; i < N_LIMITS; i++) {
      sb_key(out, &f2, LIMIT_NAMES[i]);
      sb_printf(out, "%lld", lim[i]);
    }
    sb_puts(out, "}");
  }
  sb_puts(out, "}");
}

/* ---------------------------------------------------------------- the settings (the administrator only) */

static int str_cmp(const void* a, const void* b) { return strcmp(*(const char* const*)a, *(const char* const*)b); }

static int write_text(const wchar_t* path, const char* text, size_t n) { /* a temporary file beside it, flushed, then replaced */
  size_t pl = wcslen(path);
  wchar_t* tmp = (wchar_t*)calloc(pl + 8, sizeof(wchar_t));
  HANDLE h;
  DWORD w = 0;
  if (tmp == NULL)
    ExitProcess(9);
  wcscpy(tmp, path);
  wcscat(tmp, L".new");
  h = CreateFileW(tmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE)
    return 0;
  if (!WriteFile(h, text, (DWORD)n, &w, NULL) || w != n || !FlushFileBuffers(h)) {
    CloseHandle(h);
    DeleteFileW(tmp);
    return 0;
  }
  CloseHandle(h);
  return replace_file(tmp, path);
}

/* ai.conf from the list, whole and atomic.  Empty values are left out, except provider= (empty is AI off, said so on purpose). */
static int write_conf(const kvlist* conf) {
  const char** keys = (const char**)calloc(conf->n + 1, sizeof(char*));
  sbuf b;
  size_t i;
  if (keys == NULL)
    ExitProcess(9);
  for (i = 0; i < conf->n; i++)
    keys[i] = conf->k[i];
  qsort(keys, conf->n, sizeof(char*), str_cmp);
  sb_init(&b);
  sb_puts(&b, "# ai.conf - the settings of the AI helper, written by sd-ai for the administrator (set.ai.*, the AI choice page).  Not for hand editing.\n");
  for (i = 0; i < conf->n; i++) {
    const char* v = kv_get(conf, keys[i]);
    if (v[0] != '\0' || strcmp(keys[i], "provider") == 0)
      sb_printf(&b, "%s=%s\n", keys[i], v);
  }
  if (!write_text(state_path("ai.conf", NULL), b.p, b.n))
    return refuse("badconf", "ai.conf could not be written");
  return 0;
}

/* The key of one provider, encrypted for this account (DPAPI) in a private file of its own, replaced whole.  Never echoed, never logged. */
static int write_key(const char* name, const char* key) {
  char entropy[64];
  char tmpname[64];
  BYTE* blob;
  DWORD bn, w = 0;
  wchar_t* tmp;
  HANDLE h;
  key_entropy(entropy, sizeof entropy, name);
  if (!dpapi((const BYTE*)key, (DWORD)strlen(key), entropy, 1, &blob, &bn))
    return refuse("nokey", "the key could not be encrypted for this helper");
  snprintf(tmpname, sizeof tmpname, ".%s.new", name);
  tmp = state_path("keys", tmpname);
  h = private_create(tmp);
  if (h == INVALID_HANDLE_VALUE)
    return refuse("nokey", "the key could not be written");
  if (!WriteFile(h, blob, bn, &w, NULL) || w != bn || !FlushFileBuffers(h)) {
    CloseHandle(h);
    DeleteFileW(tmp);
    return refuse("nokey", "the key could not be written");
  }
  CloseHandle(h);
  if (!replace_file(tmp, state_path("keys", name)))
    return refuse("nokey", "the key could not be written");
  return 0;
}

/* S.160: the administrator's standing text, replaced whole, or removed by an empty value (the shipped default again).  Checked BEFORE it is written. */
static int set_context(const jval* v, sbuf* out) {
  sbuf t;
  size_t i;
  wchar_t* path = state_path("context", NULL);
  if (!json_is_str(v))
    return refuse("badreq", "the standing text is text");
  sb_init(&t);
  for (i = 0; i < v->slen; i++) {
    if (v->s[i] == '\r' && i + 1 < v->slen && v->s[i + 1] == '\n')
      continue;
    sb_add(&t, v->s + i, 1);
  }
  while (t.n > 0 && t.p[t.n - 1] == '\n')
    t.p[--t.n] = '\0';
  if (t.n == 0) {
    DeleteFileW(path);
    sb_puts(out, "{\"t\": \"ok\", \"context\": \"default\"}");
    return 0;
  }
  if (codepoints(t.p, t.n) > CONTEXT_MAX || !context_chars(t.p, t.n))
    return refuse("badreq", "the standing text is at most %d characters of printable ASCII and line feeds", CONTEXT_MAX);
  sb_add(&t, "\n", 1);
  if (!write_text(path, t.p, t.n))
    return refuse("badconf", "the standing text could not be written");
  sb_puts(out, "{\"t\": \"ok\", \"context\": \"own\"}");
  return 0;
}

static const char* req_str(const jval* req, const char* k, int* ok) { /* req.get(k, "") that must be text */
  jval* v = json_get(req, k);
  if (v == NULL)
    return "";
  if (v->t != J_STR) {
    *ok = 0;
    return "";
  }
  return v->s;
}

static int readable(const char* path) {
  HANDLE h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE)
    return 0;
  CloseHandle(h);
  return 1;
}

/* set, keyset and keyclear: what the AI choice page and set.ai do.  Only the administrator gets here.  Every value is checked as it is checked at
   the time of use, and the whole result BEFORE it is written, so a request can never leave a file the helper then refuses to read. */
static int admin_op_locked(const jval* req, sbuf* out) {
  kvlist conf, nw, p;
  const char* op = json_get(req, "op")->s;
  jval* what;
  const char *n, *m;
  long long lim[N_LIMITS];
  int ok = 1;
  if (parse_kv(state_path("ai.conf", NULL), "ai.conf", &conf) < 0)
    return -1;
  if (strcmp(op, "keyset") == 0 || strcmp(op, "keyclear") == 0) {
    jval* pv = json_get(req, "provider");
    jval* kv;
    if (!json_is_str(pv) || !in_list(pv->s, PROVIDERS, 5))
      return refuse("badreq", "provider must be one of anthropic, openai, google, deepseek, custom");
    if (strcmp(op, "keyclear") == 0) {
      DeleteFileW(state_path("keys", pv->s));
      sb_puts(out, "{\"t\": \"ok\", \"key\": \"clear\"}");
      return 0;
    }
    kv = json_get(req, "key");
    if (!json_is_str(kv) || !match_key(kv->s, kv->slen))
      return refuse("badreq", "a key is 8 to 512 printable characters with no space");
    if (write_key(pv->s, kv->s) < 0)
      return -1;
    sb_puts(out, "{\"t\": \"ok\", \"key\": \"set\"}");
    return 0;
  }
  what = json_get(req, "what");
  if (jeq(what, "context"))
    return set_context(json_get(req, "value"), out);
  kv_copy(&nw, &conf);
  if (jeq(what, "provider")) {
    jval* v = json_get(req, "value");
    if (!json_is_str(v) || (v->slen != 0 && !in_list(v->s, PROVIDERS, 5)))
      return refuse("badreq", "provider must be one of anthropic, openai, google, deepseek, custom, or empty to turn the AI off");
    kv_set(&nw, "provider", v->s);
  } else if (jeq(what, "model")) {
    jval* pv = json_get(req, "provider");
    jval* v = json_get(req, "value");
    char k[64];
    if (!json_is_str(pv) || !in_list(pv->s, PROVIDERS, 5) || !json_is_str(v) || (v->slen != 0 && (strlen(v->s) != v->slen || !match_model(v->s))))
      return refuse("badreq", "a provider and a model name of letters, digits and . _ : / @ + - (empty clears it)");
    snprintf(k, sizeof k, "model.%s", pv->s);
    kv_set(&nw, k, v->s);
  } else if (jeq(what, "custom")) {
    static const char* f[] = {"name", "url", "format", "auth", "version", "maxparam"};
    int i;
    memset(&p, 0, sizeof p);
    for (i = 0; i < 6; i++)
      kv_set(&p, f[i], req_str(req, f[i], &ok));
    if (!ok)
      return refuse("badreq", "the custom connection is text");
    if (check_connection(&p, "the custom provider") < 0)
      return -1;
    for (i = 0; i < 6; i++) {
      char k[64];
      snprintf(k, sizeof k, "custom.%s", f[i]);
      kv_set(&nw, k, kv_get(&p, f[i]));
    }
  } else if (jeq(what, "custom-clear")) {
    size_t i;
    if (strcmp(kv_str(&conf, "provider", ""), "custom") == 0)
      return refuse("badreq", "custom is the selected provider: select another first");
    for (i = nw.n; i > 0; i--)
      if (strncmp(nw.k[i - 1], "custom.", 7) == 0)
        kv_del(&nw, nw.k[i - 1]);
  } else if (jeq(what, "ca")) {
    jval* v = json_get(req, "value");
    if (!json_is_str(v) || (v->slen != 0 && (!plain_path(v->s) || !path_isfile(u2w(v->s)) || !readable(v->s))))
      return refuse("badreq", "ca-file is empty (the Windows certificate store) or a drive path written with / of a file this helper can read");
    kv_set(&nw, "ca-file", v->s);
  } else if (jeq(what, "limit")) {
    jval* nv = json_get(req, "name");
    jval* v = json_get(req, "value");
    int known = json_is_str(nv) && in_list(nv->s, LIMIT_NAMES, N_LIMITS);
    char k[64];
    if (!known || !json_is_str(v) || v->slen < 1 || v->slen > 10 || !chars_in(v->s, "") || strspn(v->s, "0123456789") != v->slen)
      return refuse("badreq", "a limit is one of requests-hour, tokens-day, timeout, bytes-request, bytes-reply, max-tokens and a whole number");
    snprintf(k, sizeof k, "limit.%s", nv->s);
    kv_set(&nw, k, v->s);
  } else
    return refuse("badreq", "what is one of provider, model, custom, custom-clear, ca, limit, context");
  if (selected(&nw, &n, &p, &m) < 0) /* the whole result must be one the helper will read: custom complete before it is selected */
    return -1;
  if (all_limits(&nw, lim) < 0)
    return -1;
  if (write_conf(&nw) < 0)
    return -1;
  sb_puts(out, "{\"t\": \"ok\"}");
  return 0;
}

static int admin_op(const jval* req, sbuf* out) {
  HANDLE lock;
  int rc;
  if (read_providers() < 0)
    return -1;
  lock = lock_open(state_path("conf.lock", NULL));
  if (lock == INVALID_HANDLE_VALUE)
    return refuse("badconf", "the settings are locked by another request");
  rc = admin_op_locked(req, out);
  lock_close(lock);
  return rc;
}

/* ---------------------------------------------------------------- one request */

typedef struct {
  sbuf js;
  const char* status; /* the code, or t */
  char in[24];
  char out[24];
  const char* prov;
} reply_t;

static void reply_err(reply_t* r, const char* code, const char* msg) {
  sb_init(&r->js);
  sb_puts(&r->js, "{\"t\": \"err\", \"code\": ");
  sb_jstrz(&r->js, code);
  sb_puts(&r->js, ", \"msg\": ");
  sb_jstrz(&r->js, msg);
  sb_puts(&r->js, "}");
  r->status = _strdup(code);
  r->prov = "-";
}

static void reply_refused(reply_t* r) { reply_err(r, r_code, r_msg); }

static void reply_js(reply_t* r, sbuf* js, const char* t, const char* prov) {
  r->js = *js;
  r->status = t;
  r->prov = prov;
}

static int read_history(const jval* req, exchange_t* h, int* nh) {
  jval* v = json_get(req, "history");
  size_t i;
  *nh = 0;
  if (v == NULL || v->t == J_NULL)
    return 0;
  if (v->t != J_ARR || v->n > HISTORY_MAX)
    return refuse("badreq", "history is a list of at most %d exchanges", HISTORY_MAX);
  for (i = 0; i < v->n; i++) {
    jval* e = v->items[i];
    jval *q, *a;
    size_t k;
    int other = 0;
    if (e->t == J_OBJ)
      for (k = 0; k < e->n; k++)
        if (strcmp(e->keys[k], "q") != 0 && strcmp(e->keys[k], "a") != 0)
          other = 1;
    q = json_get(e, "q");
    a = json_get(e, "a");
    if (e->t != J_OBJ || other || !json_is_str(q) || !json_is_str(a) || blank(q->s, q->slen))
      return refuse("badreq", "an exchange of the history is {\"q\": text, \"a\": text}");
    h[*nh].q = q->s;
    h[*nh].qn = q->slen;
    h[*nh].a = a->s;
    h[(*nh)++].an = a->slen;
  }
  return 0;
}

static int conf_and_table(kvlist* conf) {
  if (parse_kv(state_path("ai.conf", NULL), "ai.conf", conf) < 0)
    return -1;
  return read_providers();
}

/* One request line to one reply.  c is the caller read off the pipe (NULL when it could not be read). */
static void handle(const char* line, size_t n, const caller_t* c, reply_t* r) {
  jval* req = json_parse(line, n);
  jval *v, *opv;
  const char* op;
  kvlist conf, p;
  const char *name, *model;
  long long lim[N_LIMITS];
  char* key;
  memset(r, 0, sizeof *r);
  strcpy(r->in, "-");
  strcpy(r->out, "-");
  v = json_get(req, "v");
  opv = json_get(req, "op");
  op = json_is_str(opv) ? opv->s : "";
  if (req == NULL || req->t != J_OBJ || v == NULL || !((v->t == J_NUM && v->num == VERSION) || v->t == J_TRUE) ||
      !(strcmp(op, "ask") == 0 || strcmp(op, "status") == 0 || strcmp(op, "set") == 0 || strcmp(op, "keyset") == 0 || strcmp(op, "keyclear") == 0 ||
        strcmp(op, "models") == 0)) {
    reply_err(r, "badreq", "not a request this helper understands");
    return;
  }
  if (strcmp(op, "models") == 0) {
    /* S.170: the provider's list of models, for the administrator choosing one.  The administrator's alone, as the settings are: it spends the key. */
    jval* pv;
    char** ids;
    int nids, i;
    sbuf js;
    const char* pname;
    kvlist sel;
    if (c == NULL || !is_admin(c)) {
      reply_err(r, "noadmin", "only the administrator may ask for the list of models");
      return;
    }
    if (conf_and_table(&conf) < 0) {
      reply_refused(r);
      return;
    }
    pv = json_get(req, "provider");
    if (json_truthy(pv))
      pname = json_is_str(pv) ? pv->s : "";
    else
      pname = kv_str(&conf, "provider", "");
    if (!in_list(pname, PROVIDERS, 5)) {
      refuse("badreq", "provider must be one of anthropic, openai, google, deepseek, custom");
      reply_refused(r);
      return;
    }
    kv_copy(&sel, &conf);
    kv_set(&sel, "provider", pname);
    if (selected(&sel, &name, &p, &model) < 0 || read_key(pname, &key) < 0 || all_limits(&conf, lim) < 0 ||
        list_models(&conf, pname, &p, key, lim, &ids, &nids) < 0) {
      reply_refused(r);
      return;
    }
    sb_init(&js);
    sb_puts(&js, "{\"t\": \"models\", \"provider\": ");
    sb_jstrz(&js, pname);
    sb_puts(&js, ", \"models\": [");
    for (i = 0; i < nids; i++) {
      if (i)
        sb_puts(&js, ", ");
      sb_jstrz(&js, ids[i]);
    }
    sb_puts(&js, "]}");
    reply_js(r, &js, "models", pname);
    return;
  }
  if (strcmp(op, "set") == 0 || strcmp(op, "keyset") == 0 || strcmp(op, "keyclear") == 0) {
    sbuf js;
    if (c == NULL || !is_admin(c)) {
      reply_err(r, "noadmin", "only the administrator may change the AI settings");
      return;
    }
    sb_init(&js);
    if (admin_op(req, &js) < 0) {
      reply_refused(r);
      return;
    }
    reply_js(r, &js, "ok", "-");
    return;
  }
  if (!may_ask(c)) {
    if (strcmp(op, "ask") == 0 || c == NULL) {
      reply_err(r, "nogate", "this account may not use the AI");
      return;
    }
  }
  if (conf_and_table(&conf) < 0) {
    reply_refused(r);
    return;
  }
  if (strcmp(op, "status") == 0) {
    sbuf js;
    sb_init(&js);
    status_reply(&conf, c, &js);
    reply_js(r, &js, strncmp(js.p, "{\"t\": \"err\"", 11) == 0 ? "badconf" : "status", "-");
    if (strncmp(js.p, "{\"t\": \"err\"", 11) == 0)
      r->status = _strdup(r_code);
    return;
  }
  {
    jval *pr, *sy, *mt;
    exchange_t hist[HISTORY_MAX];
    int nh, trunc = 0, sel, i;
    long long maxtokens, tin = 0, tout = 0, replaced, hbytes = 0;
    sbuf text, clean, js;
    const char* system = "";
    size_t sn = 0;
    if (all_limits(&conf, lim) < 0) {
      reply_refused(r);
      return;
    }
    sel = selected(&conf, &name, &p, &model);
    if (sel < 0) {
      reply_refused(r);
      return;
    }
    if (sel == 0) {
      reply_err(r, "disabled", "no AI provider is selected");
      return;
    }
    if (model[0] == '\0') {
      refuse("nomodel", "no model has been chosen for %s", kv_str(&p, "name", name));
      reply_refused(r);
      return;
    }
    if (!match_model(model)) {
      reply_err(r, "badconf", "the model name has characters a model name may not have");
      return;
    }
    if (read_key(name, &key) < 0) {
      reply_refused(r);
      return;
    }
    pr = json_get(req, "prompt");
    sy = json_get(req, "system");
    if (sy != NULL) {
      if (sy->t != J_STR) {
        reply_err(r, "badreq", "a prompt is required");
        return;
      }
      system = sy->s;
      sn = sy->slen;
    }
    if (!json_is_str(pr) || blank(pr->s, pr->slen)) {
      reply_err(r, "badreq", "a prompt is required");
      return;
    }
    if (read_history(req, hist, &nh) < 0) {
      reply_refused(r);
      return;
    }
    for (i = 0; i < nh; i++)
      hbytes += (long long)(hist[i].qn + hist[i].an);
    if ((long long)(pr->slen + sn) + hbytes > lim[L_BYTES_REQ]) {
      refuse("toobig", "the request is over %lld bytes", lim[L_BYTES_REQ]);
      reply_refused(r);
      return;
    }
    mt = json_get(req, "maxtokens");
    if (mt == NULL)
      maxtokens = lim[L_MAX_TOKENS];
    else if (!py_int(mt, &maxtokens)) {
      reply_err(r, "badreq", "maxtokens is not a number");
      return;
    }
    if (maxtokens > lim[L_MAX_TOKENS])
      maxtokens = lim[L_MAX_TOKENS];
    if (maxtokens < 1)
      maxtokens = 1;
    if (counters(c->sid, lim, 0, 1) < 0) {
      reply_refused(r);
      return;
    }
    if (ask(&conf, &p, model, key, system, sn, pr->s, pr->slen, maxtokens, lim, hist, nh, &text, &tin, &tout, &trunc) < 0) {
      SecureZeroMemory(key, strlen(key));
      reply_refused(r);
      return;
    }
    SecureZeroMemory(key, strlen(key));
    if (counters(c->sid, lim, tin + tout, 0) < 0) {
      reply_refused(r);
      return;
    }
    sb_init(&clean);
    hygiene(text.p, text.n, &clean, &replaced);
    if ((long long)clean.n > lim[L_BYTES_REPLY]) {
      refuse("toobig", "the reply is over %lld bytes", lim[L_BYTES_REPLY]);
      reply_refused(r);
      return;
    }
    sb_init(&js);
    sb_puts(&js, "{\"t\": \"ok\", \"text\": ");
    sb_jstr(&js, clean.p, clean.n);
    sb_printf(&js, ", \"in\": %lld, \"out\": %lld, \"provider\": ", tin, tout);
    sb_jstrz(&js, name);
    sb_printf(&js, ", \"truncated\": %s, \"replaced\": %lld}", trunc ? "true" : "false", replaced);
    reply_js(r, &js, "ok", name);
    snprintf(r->in, sizeof r->in, "%lld", tin);
    snprintf(r->out, sizeof r->out, "%lld", tout);
  }
}

/* ---------------------------------------------------------------- serve one connection (--one) */

static volatile LONG answered = 0;
static HANDLE g_out = INVALID_HANDLE_VALUE;

static int write_all(HANDLE h, const char* p, size_t n) {
  while (n > 0) {
    DWORD w = 0;
    if (!WriteFile(h, p, (DWORD)((n > 65536) ? 65536 : n), &w, NULL) || w == 0)
      return 0;
    p += w;
    n -= w;
  }
  return 1;
}

static DWORD WINAPI watchdog(LPVOID arg) {
  static const char line[] = "{\"t\": \"err\", \"code\": \"timeout\", \"msg\": \"no answer in time\"}\n";
  (void)arg;
  SleepEx(WATCHDOG_MS, FALSE);
  if (InterlockedCompareExchange(&answered, 1, 0) == 0) {
    write_all(g_out, line, sizeof line - 1);
    FlushFileBuffers(g_out);
  }
  ExitProcess(4);
  return 0;
}

static void log_line(const caller_t* c, const reply_t* r) {
  char line[600];
  time_t t = time(NULL);
  struct tm* lt = localtime(&t);
  char ts[32];
  HANDLE h = GetStdHandle(STD_ERROR_HANDLE);
  DWORD w;
  strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", lt);
  snprintf(line, sizeof line, "%s sd-ai: sid=%s provider=%s status=%s in=%s out=%s\n", ts, c ? c->sid : "None", r->prov, r->status, r->in, r->out);
  if (h != NULL && h != INVALID_HANDLE_VALUE)
    WriteFile(h, line, (DWORD)strlen(line), &w, NULL);
}

static int serve(HANDLE hin, HANDLE hout) {
  size_t limit = 65536 * 2 + 65536;
  sbuf buf;
  char chunk[65536];
  char* nl = NULL;
  reply_t r;
  caller_t c;
  int have_caller;
  g_out = hout;
  sb_init(&buf);
  while (buf.n <= limit) {
    DWORD got = 0;
    if (!ReadFile(hin, chunk, sizeof chunk, &got, NULL) || got == 0)
      break;
    sb_add(&buf, chunk, got);
    nl = (char*)memchr(buf.p, '\n', buf.n);
    if (nl != NULL)
      break;
  }
  have_caller = caller_from_pipe(hin, &c);
  if (nl == NULL) {
    memset(&r, 0, sizeof r);
    strcpy(r.in, "-");
    strcpy(r.out, "-");
    if (buf.n > limit)
      reply_err(&r, "toobig", "the request is far too large");
    else
      reply_err(&r, "badreq", "no request line");
  } else {
    HANDLE dog = CreateThread(NULL, 0, watchdog, NULL, 0, NULL);
    if (dog != NULL)
      CloseHandle(dog);
    handle(buf.p, (size_t)(nl - buf.p), have_caller ? &c : NULL, &r);
    if (InterlockedCompareExchange(&answered, 1, 0) != 0) {
      SleepEx(INFINITE, FALSE); /* the watchdog has answered and is ending the process */
    }
  }
  sb_add(&r.js, "\n", 1);
  write_all(hout, r.js.p, r.js.n);
  FlushFileBuffers(hout); /* until the client has read it: a pipe's buffered bytes would go with the handle otherwise */
  log_line(have_caller ? &c : NULL, &r);
  return 0;
}

/* ---------------------------------------------------------------- the pipe and the service (Linux: systemd's socket) */

static volatile LONG stopping = 0;
static const wchar_t* g_pipe = PIPE_NAME;

/* The pipe's security: owner this account (the kernel refuses a pipe owned by anyone else), SYSTEM and this account full, sdusers and
   Administrators PIPE_CLIENT_MASK, nothing for anyone else.  P: no inherited entries. */
static int pipe_sa(SECURITY_ATTRIBUTES* sa, char* why, size_t wn) {
  char me[192], sd[1024];
  BYTE sdusers[SECURITY_MAX_SID_SIZE];
  PSECURITY_DESCRIPTOR psd = NULL;
  wchar_t* w;
  if (!own_sid(me, sizeof me, NULL)) {
    snprintf(why, wn, "the account of this helper cannot be read");
    return 0;
  }
  snprintf(sd, sizeof sd, "O:%sD:P(A;;GA;;;SY)(A;;GA;;;%s)", me, me);
  if (account_sid(L"sdusers", sdusers, sizeof sdusers)) {
    char t[192];
    LPSTR s = NULL;
    if (ConvertSidToStringSidA((PSID)sdusers, &s)) {
      snprintf(t, sizeof t, "(A;;0x%08X;;;%s)", PIPE_CLIENT_MASK, s);
      strcat(sd, t);
      LocalFree(s);
    }
  }
  {
    char t[64];
    snprintf(t, sizeof t, "(A;;0x%08X;;;BA)", PIPE_CLIENT_MASK);
    strcat(sd, t);
  }
  w = u2w(sd);
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(w, SDDL_REVISION_1, &psd, NULL)) {
    snprintf(why, wn, "the pipe's access list cannot be made");
    return 0;
  }
  sa->nLength = sizeof *sa;
  sa->lpSecurityDescriptor = psd;
  sa->bInheritHandle = FALSE;
  return 1;
}

/* One instance.  first: FILE_FLAG_FIRST_PIPE_INSTANCE - if anyone else already made a pipe of this name, this fails and the service will not run. */
static HANDLE create_pipe(const wchar_t* name, int first, SECURITY_ATTRIBUTES* sa) {
  DWORD open_mode = PIPE_ACCESS_DUPLEX | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0);
  DWORD pipe_mode = PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS;
  return CreateNamedPipeW(name, open_mode, pipe_mode, MAX_INSTANCES, PIPE_BUFFER, PIPE_BUFFER, 0, sa);
}

static HANDLE g_job = NULL;
static HANDLE* children = NULL;
static size_t nchildren = 0, capchildren = 0;

static HANDLE make_job(void) { /* a job that ends every request process when it is closed (the service stopping) */
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
  HANDLE job = CreateJobObjectW(NULL, NULL);
  if (job == NULL)
    return NULL;
  memset(&info, 0, sizeof info);
  info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info, sizeof info)) {
    CloseHandle(job);
    return NULL;
  }
  return job;
}

static void reap(void) {
  size_t i, k = 0;
  for (i = 0; i < nchildren; i++) {
    if (WaitForSingleObject(children[i], 0) == WAIT_OBJECT_0)
      CloseHandle(children[i]);
    else
      children[k++] = children[i];
  }
  nchildren = k;
}

static void quote_arg(sbuf* b, const wchar_t* w) {
  char* u = w2u(w);
  sb_puts(b, " \"");
  sb_puts(b, u);
  sb_puts(b, "\"");
  free(u);
}

/* A new process of this program (--one) with the connected instance as its standard input and output and the log as its standard error;
   ONLY those two handles are inherited (the handle list).  Suspended until it is in the job. */
static int spawn(HANDLE pipe) {
  wchar_t self[MAX_PATH * 2];
  sbuf cmd;
  wchar_t* wcmd;
  HANDLE logh;
  wchar_t* logp = state_path("sd-ai.log", NULL);
  SECURITY_ATTRIBUTES lsa;
  STARTUPINFOEXW si;
  PROCESS_INFORMATION pi;
  SIZE_T asz = 0;
  HANDLE inherit[2];
  int ok;
  if (GetModuleFileNameW(NULL, self, MAX_PATH * 2) == 0)
    return 0;
  lsa.nLength = sizeof lsa;
  lsa.lpSecurityDescriptor = NULL;
  lsa.bInheritHandle = TRUE;
  logh = CreateFileW(logp, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, &lsa, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (logh == INVALID_HANDLE_VALUE)
    logh = NULL;
  SetHandleInformation(pipe, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  sb_init(&cmd);
  {
    char* u = w2u(self);
    sb_printf(&cmd, "\"%s\" --one --state", u);
    free(u);
  }
  quote_arg(&cmd, g_state);
  sb_puts(&cmd, " --providers");
  quote_arg(&cmd, g_providers);
  wcmd = u2w(cmd.p);
  memset(&si, 0, sizeof si);
  si.StartupInfo.cb = sizeof si;
  si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  si.StartupInfo.hStdInput = pipe;
  si.StartupInfo.hStdOutput = pipe;
  si.StartupInfo.hStdError = logh;
  inherit[0] = pipe;
  inherit[1] = logh;
  InitializeProcThreadAttributeList(NULL, 1, 0, &asz);
  si.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(asz);
  ok = si.lpAttributeList != NULL && InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &asz) &&
       UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherit, (logh ? 2 : 1) * sizeof(HANDLE), NULL, NULL);
  if (ok)
    ok = CreateProcessW(self, wcmd, NULL, NULL, TRUE, CREATE_SUSPENDED | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT, NULL, NULL,
                        &si.StartupInfo, &pi);
  if (si.lpAttributeList != NULL) {
    DeleteProcThreadAttributeList(si.lpAttributeList);
    free(si.lpAttributeList);
  }
  if (logh != NULL)
    CloseHandle(logh);
  free(wcmd);
  if (!ok)
    return 0;
  if (g_job != NULL)
    AssignProcessToJobObject(g_job, pi.hProcess);
  ResumeThread(pi.hThread);
  CloseHandle(pi.hThread);
  if (nchildren == capchildren) {
    capchildren = capchildren ? capchildren * 2 : 32;
    children = (HANDLE*)realloc(children, capchildren * sizeof(HANDLE));
    if (children == NULL)
      ExitProcess(9);
  }
  children[nchildren++] = pi.hProcess;
  return 1;
}

static SECURITY_ATTRIBUTES g_sa;
static HANDLE g_cur = INVALID_HANDLE_VALUE;

/* The first instance, or why not.  ONE instance always waits; the next is made BEFORE the connected one is let go, so there is never a moment
   with no instance of ours (another user could otherwise make the name). */
static int listener_open(char* why, size_t wn) {
  if (!pipe_sa(&g_sa, why, wn))
    return 0;
  g_job = make_job();
  g_cur = create_pipe(g_pipe, 1, &g_sa);
  if (g_cur == INVALID_HANDLE_VALUE) {
    char* u = w2u(g_pipe);
    snprintf(why, wn, "the pipe %s could not be made (error %lu): another program may hold the name", u, GetLastError());
    free(u);
    return 0;
  }
  return 1;
}

static void listener_run(void) {
  while (!stopping) {
    HANDLE nxt = INVALID_HANDLE_VALUE;
    BOOL ok = ConnectNamedPipe(g_cur, NULL);
    if (!ok && GetLastError() != ERROR_PIPE_CONNECTED) {
      CloseHandle(g_cur);
      g_cur = INVALID_HANDLE_VALUE;
      while (g_cur == INVALID_HANDLE_VALUE && !stopping) {
        g_cur = create_pipe(g_pipe, 0, &g_sa);
        if (g_cur == INVALID_HANDLE_VALUE)
          SleepEx(100, FALSE);
      }
      continue;
    }
    if (stopping)
      break;
    reap();
    while (nxt == INVALID_HANDLE_VALUE && !stopping) {
      nxt = create_pipe(g_pipe, 0, &g_sa); /* every instance in use (ERROR_PIPE_BUSY): wait for a request to end */
      if (nxt == INVALID_HANDLE_VALUE) {
        SleepEx(50, FALSE);
        reap();
      }
    }
    if (!spawn(g_cur)) {
      const char m[] = "sd-ai: a request process could not be started\n";
      DWORD w;
      HANDLE e = GetStdHandle(STD_ERROR_HANDLE);
      if (e != NULL && e != INVALID_HANDLE_VALUE)
        WriteFile(e, m, sizeof m - 1, &w, NULL);
    }
    CloseHandle(g_cur); /* this process's handle; the child holds its own */
    g_cur = nxt;
  }
  if (g_cur != INVALID_HANDLE_VALUE)
    CloseHandle(g_cur);
  if (g_job != NULL)
    CloseHandle(g_job); /* ends any request still running */
}

static void listener_stop(void) { /* set the flag, then connect to our own pipe once so that ConnectNamedPipe returns */
  HANDLE h;
  InterlockedExchange(&stopping, 1);
  h = CreateFileW(g_pipe, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
  if (h != INVALID_HANDLE_VALUE)
    CloseHandle(h);
}

static SERVICE_STATUS_HANDLE g_svc;
static SERVICE_STATUS g_status;

static void set_state(DWORD s, DWORD code) {
  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_status.dwCurrentState = s;
  g_status.dwControlsAccepted = (s == SERVICE_RUNNING) ? (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN) : 0;
  g_status.dwWin32ExitCode = code;
  g_status.dwWaitHint = 10000;
  g_status.dwCheckPoint = (s == SERVICE_RUNNING || s == SERVICE_STOPPED) ? 0 : g_status.dwCheckPoint + 1;
  SetServiceStatus(g_svc, &g_status);
}

static DWORD WINAPI svc_handler(DWORD control, DWORD etype, LPVOID edata, LPVOID ctx) {
  (void)etype;
  (void)edata;
  (void)ctx;
  if (control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_SHUTDOWN) {
    set_state(SERVICE_STOP_PENDING, 0);
    listener_stop();
    return NO_ERROR;
  }
  return (control == SERVICE_CONTROL_INTERROGATE) ? NO_ERROR : ERROR_CALL_NOT_IMPLEMENTED;
}

static void WINAPI svc_main(DWORD argc, LPWSTR* argv) {
  char why[600];
  (void)argc;
  (void)argv;
  g_svc = RegisterServiceCtrlHandlerExW(SERVICE_NAME, svc_handler, NULL);
  if (g_svc == NULL)
    return;
  set_state(SERVICE_START_PENDING, 0);
  CreateDirectoryW(state_path("keys", NULL), NULL);
  CreateDirectoryW(state_path("state", NULL), NULL);
  if (!listener_open(why, sizeof why)) {
    char m[700];
    snprintf(m, sizeof m, "sd-ai could not start: %s", why);
    event_log(m);
    set_state(SERVICE_STOPPED, ERROR_EXCEPTION_IN_SERVICE);
    return;
  }
  set_state(SERVICE_RUNNING, 0);
  listener_run();
  set_state(SERVICE_STOPPED, 0);
}

#ifdef SDAI_TESTS
/* THE TEST BUILD ONLY (-DSDAI_TESTS, test-aihelper-units.py): write_key and read_key on their own, as the Python guard imported them. */
static int test_key(int argc, wchar_t** wargv) {
  char* op = w2u(wargv[2]);
  char* prov;
  g_state = wargv[3];
  prov = w2u(wargv[4]);
  if (strcmp(op, "write") == 0 && argc >= 6) {
    char* k = w2u(wargv[5]);
    if (write_key(prov, k) < 0) {
      printf("refused: %s: %s\n", r_code, r_msg);
      return 1;
    }
    printf("ok\n");
    return 0;
  }
  if (strcmp(op, "read") == 0) {
    char* k;
    if (read_key(prov, &k) < 0) {
      printf("refused: %s: %s\n", r_code, r_msg);
      return 1;
    }
    printf("key: %s\n", k);
    return 0;
  }
  return 2;
}
#endif

static void say_err(const char* s) {
  HANDLE e = GetStdHandle(STD_ERROR_HANDLE);
  DWORD w;
  if (e != NULL && e != INVALID_HANDLE_VALUE)
    WriteFile(e, s, (DWORD)strlen(s), &w, NULL);
}

static wchar_t* no_trailing_slash(wchar_t* p) {
  size_t n = wcslen(p);
  while (n > 3 && (p[n - 1] == L'\\' || p[n - 1] == L'/'))
    p[--n] = L'\0';
  return p;
}

/* wmain (-municode), not CommandLineToArgvW: that is SHELL32's, and SHELL32 brings USER32 with it (see sdai_https.c). */
int wmain(int argc, wchar_t** wargv) {
  int i;
  const wchar_t* mode = NULL;
  wchar_t pd[MAX_PATH];
  wchar_t self[MAX_PATH * 2];
  char** argv;

  if (wargv == NULL)
    return 2;
  if (argc < 2 || !(wcscmp(wargv[1], L"--one") == 0 || wcscmp(wargv[1], L"--service") == 0 || wcscmp(wargv[1], L"--listen") == 0 ||
                    wcscmp(wargv[1], L"--state") == 0 || wcscmp(wargv[1], L"--providers") == 0
#ifdef SDAI_TESTS
                    || wcscmp(wargv[1], L"--test-key") == 0
#endif
                    )) {
    argv = (char**)calloc((size_t)argc + 1, sizeof(char*));
    if (argv == NULL)
      return 2;
    for (i = 0; i < argc; i++)
      argv[i] = w2u(wargv[i]);
    return ctl_main(argc, argv);
  }
#ifdef SDAI_TESTS
  if (wcscmp(wargv[1], L"--test-key") == 0 && argc >= 5)
    return test_key(argc, wargv);
#endif

  if (GetEnvironmentVariableW(L"ProgramData", pd, MAX_PATH) == 0)
    wcscpy(pd, L"C:\\ProgramData");
  g_state = wjoin(pd, "SD\\ai");
  GetModuleFileNameW(NULL, self, MAX_PATH * 2);
  g_providers = wjoin(wdirname(self), "ai-providers"); /* in the program folder, with this program: no SD account can change where a key is sent */

  for (i = 1; i < argc; i++) {
    if (wcscmp(wargv[i], L"--state") == 0 && i + 1 < argc)
      g_state = no_trailing_slash(wargv[++i]);
    else if (wcscmp(wargv[i], L"--providers") == 0 && i + 1 < argc)
      g_providers = wargv[++i];
    else if ((wcscmp(wargv[i], L"--one") == 0 || wcscmp(wargv[i], L"--service") == 0) && mode == NULL)
      mode = wargv[i];
    else if (wcscmp(wargv[i], L"--listen") == 0 && i + 1 < argc && mode == NULL && _wcsnicmp(wargv[i + 1], L"\\\\.\\pipe\\", 9) == 0) {
      mode = wargv[i];
      g_pipe = wargv[++i];
    } else {
      mode = L"bad";
      break;
    }
  }
  if (mode != NULL && wcscmp(mode, L"--one") == 0)
    return serve(GetStdHandle(STD_INPUT_HANDLE), GetStdHandle(STD_OUTPUT_HANDLE));
  if (mode != NULL && wcscmp(mode, L"--service") == 0) {
    SERVICE_TABLE_ENTRYW st[2];
    st[0].lpServiceName = (LPWSTR)SERVICE_NAME;
    st[0].lpServiceProc = svc_main;
    st[1].lpServiceName = NULL;
    st[1].lpServiceProc = NULL;
    if (!StartServiceCtrlDispatcherW(st)) {
      char m[160];
      snprintf(m, sizeof m, "sd-ai: --service is for the service control manager (error %lu)\n", GetLastError());
      say_err(m);
      return 2;
    }
    return 0;
  }
  if (mode != NULL && wcscmp(mode, L"--listen") == 0) {
    char why[600];
    if (!listener_open(why, sizeof why)) {
      char m[700];
      snprintf(m, sizeof m, "sd-ai: %s\n", why);
      say_err(m);
      return 3;
    }
    listener_run();
    return 0;
  }
  say_err("usage: sd-ai --service | --one | --listen \\\\.\\pipe\\NAME   [--state DIR] [--providers FILE]\n");
  return 2;
}

/* END-CODE */
