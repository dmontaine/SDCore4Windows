/* SDAI.H
 * sd-ai.exe, the AI helper of SD Core for Windows: what its five files share.
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
 * 13 Nov 26 Windows port - New (RELEASE_1.1 246, the owner's ruling of 13 Nov 2026: "python not being an integral part of windows argues for the
 *           c helper"; design .claude/design-ai-helper-20261113.md 3.5 option A).  Replaces the Python helper gplbld/sd-ai and its client
 *           gplbld/sd-ai-ctl, whose behaviour (Linux b1d496df with the Windows facts) is kept, decision for decision and byte for byte on the pipe.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * sdai_main.c   the decisions (gate, settings, providers, limits, the call, hygiene), one request, the pipe loop, the service, main()
 * sdai_ctl.c    the administrator's client (Linux's sd-ai-ctl): sd-ai.exe show | provider ... | key ... and the rest
 * sdai_win.c    Windows: the caller read off the pipe, the gate group, DPAPI, private files, atomic replace, locks, the event log
 * sdai_https.c  the one outward call: TCP, the static OpenSSL, the Windows root store or the ca-file, HTTP/1.1
 * sdai_json.c   a bounded JSON reader and a writer that writes what Python's json.dumps writes
 *
 * Native UCRT64 with OpenSSL linked statically (the Makefile's sd-ai target, like sdtlsrelay): no MSYS2 runtime and no Python.
 * windows.h and NO SD header, as every native program here.
 *
 * END-DESCRIPTION
 */

#ifndef SDAI_H
#define SDAI_H

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stddef.h>
#include <stdarg.h>

/* ---------------------------------------------------------------- JSON (sdai_json.c) */

typedef enum { J_NULL, J_FALSE, J_TRUE, J_NUM, J_STR, J_ARR, J_OBJ } jtype;

typedef struct jval jval;
struct jval {
  jtype t;
  double num;       /* J_NUM */
  int isint;        /* J_NUM written with no fraction or exponent */
  long long ival;   /* J_NUM: the whole value when isint (clamped), else num truncated */
  char* s;          /* J_STR: UTF-8, NUL-terminated (slen bytes; a \u0000 escape is kept as a NUL) */
  size_t slen;
  size_t n;         /* J_ARR, J_OBJ: the number of members */
  jval** items;
  char** keys;      /* J_OBJ: the names, UTF-8 */
};

jval* json_parse(const char* text, size_t len);        /* NULL: not JSON (or past the depth and node bounds) */
jval* json_get(const jval* obj, const char* key);       /* the LAST member of that name (Python's dict); NULL when absent or obj is not an object */
int json_truthy(const jval* v);                         /* Python's bool() of the value */
int json_is_str(const jval* v);

typedef struct {
  char* p;
  size_t n;
  size_t cap;
} sbuf;

void sb_init(sbuf* b);
void sb_add(sbuf* b, const char* s, size_t n);
void sb_puts(sbuf* b, const char* s);
void sb_printf(sbuf* b, const char* fmt, ...);
void sb_jstr(sbuf* b, const char* s, size_t n);         /* a JSON string as json.dumps(ensure_ascii=True) writes it */
void sb_jstrz(sbuf* b, const char* s);
void sb_key(sbuf* b, int* first, const char* key);      /* ", " unless first, then "key": (Python's separators) */
void json_pretty(sbuf* b, const jval* v, int level);    /* json.dumps(v, indent=1, sort_keys=True) */

/* ---------------------------------------------------------------- Windows (sdai_win.c) */

typedef struct {
  char sid[192];      /* S-1-... */
  BYTE psid[SECURITY_MAX_SID_SIZE];
  int elevated;       /* TokenElevation */
  int admins;         /* Administrators ENABLED in the token (only so when elevated) */
} caller_t;

wchar_t* u2w(const char* s);                             /* UTF-8 to a new wide string */
char* w2u(const wchar_t* s);                             /* wide to a new UTF-8 string */
wchar_t* wjoin(const wchar_t* dir, const char* name);   /* dir\name, name ASCII or UTF-8 */
wchar_t* wdirname(const wchar_t* path);

int own_sid(char* out, size_t n, PSID* psid);           /* this process's account (in the service: NT SERVICE\sd-ai) */
int caller_from_pipe(HANDLE h, caller_t* c);            /* 1 read; 0 not a readable caller, or a service account */
int account_sid(const wchar_t* name, BYTE* sid, DWORD n);
int in_group(const BYTE* sid, const wchar_t* group);    /* the caller's own SID a direct member of the local group, read now; every doubt 0 */
int is_sdsys(const caller_t* c);
int is_admin(const caller_t* c);
int may_ask(const caller_t* c);

int dpapi(const BYTE* in, DWORD n, const char* entropy, int protect, BYTE** out, DWORD* outn);
int private_file(const wchar_t* path);                  /* a plain file whose list allows only this account and SYSTEM */
HANDLE private_create(const wchar_t* path);             /* a new file, protected list of this account and SYSTEM, for writing */
int replace_file(const wchar_t* tmp, const wchar_t* path);
int read_file(const wchar_t* path, size_t max, char** data, size_t* n);   /* 0 read, 1 not there, -1 cannot read */
int path_exists(const wchar_t* path);                   /* os.path.lexists */
int path_isfile(const wchar_t* path);                   /* os.path.isfile */
int path_plain_file(const wchar_t* path);               /* a file, not a link or other reparse point */
HANDLE lock_open(const wchar_t* path);                  /* an exclusive lock on byte 0 (msvcrt.locking: ten seconds, then no) */
void lock_close(HANDLE h);
void event_log(const char* text);

/* ---------------------------------------------------------------- HTTPS (sdai_https.c) */

#define HC_OK 0
#define HC_NET 1      /* the provider could not be reached */
#define HC_TLS 2      /* the TLS connection failed */
#define HC_CERT 3     /* the provider's certificate was not accepted */
#define HC_TIMEOUT 4  /* no answer in time */

#define CONNECT_TIMEOUT_MS 5000
#define RAW_CAP (4 * 1024 * 1024)   /* the most of a provider's answer that is read at all */

typedef struct {
  int status;
  char retry_after[64];
  int has_retry_after;
  char* body;
  size_t len;          /* at most RAW_CAP + 1: one byte over says "far too large" */
} http_resp;

int https_call(const char* host, int port, const char* method, const char* path, const char* headers, const char* body, size_t blen,
               const char* ca_file, int timeout_ms, http_resp* r);

/* ---------------------------------------------------------------- the client (sdai_ctl.c) */

int ctl_main(int argc, char** argv);

#endif

/* END-CODE */
