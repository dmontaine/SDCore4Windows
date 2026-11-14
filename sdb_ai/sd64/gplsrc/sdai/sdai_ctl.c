/* SDAI_CTL.C
 * sd-ai.exe as the administrator's client of the AI helper (Linux's sd-ai-ctl).
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
 * 13 Nov 26 Windows port - New (RELEASE_1.1 246): the Python client gplbld/sd-ai-ctl (from Linux b1d496df) and its wrapper sd-ai-ctl.ps1 in
 *           C, in the helper's own program: the same words, the same lines printed, the same exit codes.  No Python, so no "error: nopython:".
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *   sd-ai.exe [--pipe NAME] show [--json]
 *   sd-ai.exe [--pipe NAME] provider anthropic | openai | google | deepseek | custom | none
 *   sd-ai.exe [--pipe NAME] model PROVIDER NAME            (NAME - clears it: the provider's starting model is used again)
 *   sd-ai.exe [--pipe NAME] custom NAME URL FORMAT AUTH VERSION MAXPARAM      (VERSION - for none)
 *   sd-ai.exe [--pipe NAME] custom-clear
 *   sd-ai.exe [--pipe NAME] ca PATH                         (PATH - for the Windows certificate store; a drive path written with /, C:/...)
 *   sd-ai.exe [--pipe NAME] limit NAME NUMBER
 *   sd-ai.exe [--pipe NAME] key PROVIDER                    (read from the console and not shown; from standard input when it is not a console)
 *   sd-ai.exe [--pipe NAME] key PROVIDER --handover FILE    (the key is the first line of FILE, which is removed whatever happens)
 *   sd-ai.exe [--pipe NAME] key-clear PROVIDER
 *   sd-ai.exe [--pipe NAME] context HEX | -
 *   sd-ai.exe [--pipe NAME] models PROVIDER
 *
 * Run as SDSYS (or another elevated Windows administrator): the helper refuses everyone else by the account it reads from the pipe, so there is
 * no password here.  THE KEY IS NEVER AN ARGUMENT and never printed.  Exit 0 done, 1 the helper refused (its code and words printed), 2 the
 * helper could not be reached or the command line is wrong.
 *
 * WINDOWS FACTS: EVERYTHING IS PRINTED ON STANDARD OUTPUT (SD runs this through PowerShell 5.1, which would wrap standard error in error
 * records where set.ai reads "error:" and "ok").  The pipe of the real name is checked before anything is sent: its owner must be
 * NT SERVICE\sd-ai, because a key sent to a pipe someone else made would be theirs.  --handover replaces Linux's "< file".  The pipe is
 * opened at identification level with the narrow access win32ai.c asks for.
 *
 * END-DESCRIPTION
 */

#include "sdai.h"

#include <aclapi.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_PIPE "\\\\.\\pipe\\sd-ai"
#define SERVICE_ACCOUNT L"NT SERVICE\\sd-ai"
#define PIPE_CLIENT_MASK 0x00120183
#define TIMEOUT_MS 60000

static const char* PROVIDERS[] = {"anthropic", "openai", "google", "deepseek", "custom"};

static void say(const char* s) {
  HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
  DWORD w;
  size_t n = strlen(s);
  if (h == NULL || h == INVALID_HANDLE_VALUE)
    return;
  WriteFile(h, s, (DWORD)n, &w, NULL);
  WriteFile(h, "\n", 1, &w, NULL);
}

static void sayf(const char* fmt, ...) {
  char buf[4096];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof buf, fmt, ap);
  va_end(ap);
  say(buf);
}

static int usage(void) {
  say("usage: sd-ai-ctl [--pipe NAME] show [--json] | provider NAME|none | model PROVIDER NAME|- | custom NAME URL FORMAT AUTH VERSION|- MAXPARAM |\n"
      "                 custom-clear | ca PATH|- | limit NAME NUMBER | key PROVIDER [--handover FILE] | key-clear PROVIDER | context HEX|- | models PROVIDER");
  return 2;
}

static int is_provider(const char* s) {
  int i;
  for (i = 0; i < 5; i++)
    if (strcmp(s, PROVIDERS[i]) == 0)
      return 1;
  return 0;
}

/* Is the pipe's owner the service account?  Every doubt is no. */
static int owned_by_service(HANDLE h) {
  BYTE want[SECURITY_MAX_SID_SIZE];
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  int ok;
  if (!account_sid(SERVICE_ACCOUNT, want, sizeof want))
    return 0;
  if (GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, &sd) != ERROR_SUCCESS)
    return 0;
  ok = owner != NULL && IsValidSid(owner) && EqualSid(owner, (PSID)want);
  if (sd != NULL)
    LocalFree(sd);
  return ok;
}

static int blank_text(const char* s, size_t n) {
  size_t i;
  for (i = 0; i < n; i++)
    if (s[i] != ' ' && s[i] != '\t' && s[i] != '\n' && s[i] != '\r' && s[i] != '\v' && s[i] != '\f')
      return 0;
  return 1;
}

/* One request, one reply.  NULL with *why when the helper could not be reached ("OSError") or its answer is not JSON ("JSONDecodeError"). */
static jval* talk(const char* path, const char* req, size_t rn, int check_owner, const char** why) {
  wchar_t* wp = u2w(path);
  HANDLE h = CreateFileW(wp, PIPE_CLIENT_MASK, 0, NULL, OPEN_EXISTING, SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL);
  DWORD mode = PIPE_READMODE_BYTE | PIPE_NOWAIT;
  ULONGLONG deadline = GetTickCount64() + TIMEOUT_MS;
  size_t done = 0;
  sbuf buf;
  char* nl;
  jval* j;
  free(wp);
  *why = "OSError";
  if (h == INVALID_HANDLE_VALUE)
    return NULL;
  if ((check_owner && !owned_by_service(h)) || !SetNamedPipeHandleState(h, &mode, NULL, NULL)) {
    CloseHandle(h);
    return NULL;
  }
  while (done < rn) {
    DWORD w = 0;
    DWORD want = (DWORD)(((rn - done) > 4096) ? 4096 : (rn - done));
    if (!WriteFile(h, req + done, want, &w, NULL)) {
      CloseHandle(h);
      return NULL;
    }
    done += w;
    if (w == 0) {
      if (GetTickCount64() > deadline) {
        CloseHandle(h);
        return NULL;
      }
      SleepEx(10, FALSE);
    }
  }
  sb_init(&buf);
  while (memchr(buf.p, '\n', buf.n) == NULL) {
    DWORD avail = 0, got = 0;
    char chunk[65536];
    if (!PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL))
      break; /* the helper has closed its end */
    if (avail == 0) {
      if (GetTickCount64() > deadline) {
        CloseHandle(h);
        return NULL;
      }
      SleepEx(50, FALSE);
      continue;
    }
    if (!ReadFile(h, chunk, (avail > sizeof chunk) ? (DWORD)sizeof chunk : avail, &got, NULL))
      break;
    sb_add(&buf, chunk, got);
  }
  CloseHandle(h);
  nl = (char*)memchr(buf.p, '\n', buf.n);
  if (blank_text(buf.p, buf.n))
    return NULL;
  j = json_parse(buf.p, nl ? (size_t)(nl - buf.p) : buf.n);
  if (j == NULL || j->t != J_OBJ) {
    *why = "JSONDecodeError";
    return NULL;
  }
  return j;
}

static const char* sget(const jval* o, const char* k) {
  jval* v = json_get(o, k);
  return json_is_str(v) ? v->s : "";
}

static int bget(const jval* o, const char* k) { return json_truthy(json_get(o, k)); }

/* Python's "%s" of a value the reply holds: None, True, a number or the text. */
static void pystr(const jval* v, char* out, size_t n) {
  if (v == NULL || v->t == J_NULL)
    snprintf(out, n, "None");
  else if (v->t == J_TRUE)
    snprintf(out, n, "True");
  else if (v->t == J_FALSE)
    snprintf(out, n, "False");
  else if (v->t == J_NUM)
    snprintf(out, n, "%lld", v->ival);
  else if (v->t == J_STR)
    snprintf(out, n, "%s", v->s);
  else
    snprintf(out, n, "?");
}

static void show(const jval* reply, int as_json) {
  const jval* prov;
  const jval* lim;
  int i;
  if (as_json) {
    sbuf b;
    sb_init(&b);
    json_pretty(&b, reply, 0);
    say(b.p);
    return;
  }
  sayf("AI provider in use by every account: %s", sget(reply, "provider")[0] ? sget(reply, "provider") : "none (the AI is off)");
  prov = json_get(reply, "providers");
  if (prov == NULL) {
    sayf("  model %s, key %s, your account's gate %s", sget(reply, "model")[0] ? sget(reply, "model") : "-", bget(reply, "key") ? "set" : "not set",
         bget(reply, "gate") ? "on" : "off");
    return;
  }
  for (i = 0; i < 5; i++) {
    const jval* p = json_get(prov, PROVIDERS[i]);
    char ver[80] = "";
    char model[260];
    if (sget(p, "version")[0])
      snprintf(ver, sizeof ver, ", version %s", sget(p, "version"));
    sayf("  [%s] %-9s %-10s %s  (%s, %s%s, size field %s)", strcmp(sget(reply, "provider"), PROVIDERS[i]) == 0 ? "x" : " ", PROVIDERS[i], sget(p, "name"),
         sget(p, "url")[0] ? sget(p, "url") : "(not set)", sget(p, "format")[0] ? sget(p, "format") : "-", sget(p, "auth")[0] ? sget(p, "auth") : "-", ver,
         sget(p, "maxparam")[0] ? sget(p, "maxparam") : "-");
    if (sget(p, "model")[0])
      snprintf(model, sizeof model, "%s", sget(p, "model"));
    else if (sget(p, "default")[0])
      snprintf(model, sizeof model, "%s (default)", sget(p, "default"));
    else
      snprintf(model, sizeof model, "(not set)");
    sayf("      model: %s   key: %s", model, bget(p, "key") ? "set" : "(not set)");
  }
  sayf("  ca-file: %s", sget(reply, "ca-file")[0] ? sget(reply, "ca-file") : "(the Windows certificate store)");
  {
    sbuf b;
    const char** keys;
    size_t k, m;
    lim = json_get(reply, "limits");
    sb_init(&b);
    sb_puts(&b, "  limits: ");
    m = (lim != NULL && lim->t == J_OBJ) ? lim->n : 0;
    keys = (const char**)calloc(m + 1, sizeof(char*));
    for (k = 0; k < m; k++)
      keys[k] = lim->keys[k];
    for (k = 1; k < m; k++) { /* sorted by name */
      size_t x = k;
      while (x > 0 && strcmp(keys[x - 1], keys[x]) > 0) {
        const char* t = keys[x];
        keys[x] = keys[x - 1];
        keys[x - 1] = t;
        x--;
      }
    }
    for (k = 0; k < m; k++) {
      char v[64];
      pystr(json_get(lim, keys[k]), v, sizeof v);
      sb_printf(&b, "%s%s=%s", k ? ", " : "", keys[k], v);
    }
    say(b.p);
  }
  {
    const char* from = sget(reply, "context-from");
    const char* whose = strcmp(from, "own") == 0 ? "the administrator's" : strcmp(from, "default") == 0 ? "the shipped default"
                                                                      : strcmp(from, "none") == 0      ? "none"
                                                                      : strcmp(from, "bad") == 0       ? "unusable (none is sent)"
                                                                                                       : "unknown";
    jval* ct = json_get(reply, "context");
    size_t len = 0, i2;
    if (json_is_str(ct))
      for (i2 = 0; i2 < ct->slen; i2++)
        if (((unsigned char)ct->s[i2] & 0xC0) != 0x80)
          len++;
    sayf("  standing text: %s, %d characters", whose, (int)len);
  }
}

/* The key from the AI page's hand-over file (its first line), and the file removed whatever happens.  "" when it cannot be read.  A byte that is
   not ASCII becomes U+FFFD, as Python's errors="replace" made it, so the helper refuses such a key rather than take a changed one. */
static char* handover_key(const char* path) {
  wchar_t* w = u2w(path);
  char* data = NULL;
  size_t n = 0, i;
  sbuf k;
  sb_init(&k);
  if (read_file(w, 65536, &data, &n) == 0) {
    for (i = 0; i < n && data[i] != '\n' && data[i] != '\r'; i++) {
      if ((unsigned char)data[i] > 0x7f)
        sb_puts(&k, "\xEF\xBF\xBD");
      else
        sb_add(&k, data + i, 1);
    }
    SecureZeroMemory(data, n);
  }
  DeleteFileW(w);
  free(w);
  return k.p;
}

static char* read_key_console(const char* provider) {
  HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
  DWORD mode;
  sbuf k;
  sb_init(&k);
  if (in != NULL && in != INVALID_HANDLE_VALUE && GetConsoleMode(in, &mode)) {
    wchar_t wb[1024];
    DWORD got = 0;
    HANDLE out = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    char prompt[128];
    DWORD w;
    snprintf(prompt, sizeof prompt, "Key for %s (not shown): ", provider);
    if (out != INVALID_HANDLE_VALUE)
      WriteFile(out, prompt, (DWORD)strlen(prompt), &w, NULL);
    SetConsoleMode(in, (mode | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT) & ~ENABLE_ECHO_INPUT);
    if (ReadConsoleW(in, wb, 1023, &got, NULL)) {
      char* u;
      wb[got] = L'\0';
      while (got > 0 && (wb[got - 1] == L'\n' || wb[got - 1] == L'\r'))
        wb[--got] = L'\0';
      u = w2u(wb);
      sb_puts(&k, u);
      SecureZeroMemory(u, strlen(u));
      free(u);
      SecureZeroMemory(wb, sizeof wb);
    }
    SetConsoleMode(in, mode);
    if (out != INVALID_HANDLE_VALUE) {
      WriteFile(out, "\r\n", 2, &w, NULL);
      CloseHandle(out);
    }
    return k.p;
  }
  { /* not a console: the first line of standard input */
    char c;
    DWORD got;
    while (ReadFile(in, &c, 1, &got, NULL) && got == 1 && c != '\n')
      sb_add(&k, &c, 1);
    while (k.n > 0 && k.p[k.n - 1] == '\r')
      k.p[--k.n] = '\0';
    return k.p;
  }
}

/* Restore the console's echo if Ctrl+C ends the program while a key is being typed: the console is SD's session's afterwards. */
static DWORD saved_mode;
static int have_saved = 0;
static BOOL WINAPI on_ctrl(DWORD t) {
  (void)t;
  if (have_saved)
    SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), saved_mode);
  return FALSE;
}

static int hexval(int c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

/* bytes.fromhex(...).decode("ascii"): pairs of hexadecimal digits, white space allowed between pairs, every byte ASCII. */
static int from_hex(const char* s, sbuf* out) {
  while (*s) {
    int a, b;
    char c;
    if (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r' || *s == '\v' || *s == '\f') {
      s++;
      continue;
    }
    a = hexval((unsigned char)s[0]);
    b = (s[1] != '\0') ? hexval((unsigned char)s[1]) : -1;
    if (a < 0 || b < 0 || a * 16 + b > 0x7f)
      return 0;
    c = (char)(a * 16 + b);
    sb_add(out, &c, 1);
    s += 2;
  }
  return 1;
}

static void kstr(sbuf* b, int* first, const char* k, const char* v) {
  sb_key(b, first, k);
  sb_jstrz(b, v);
}

int ctl_main(int argc, char** argv) {
  char path[600];
  char** args = argv + 1;
  int n = argc - 1;
  const char* cmd;
  char** rest;
  int nr;
  int check_owner;
  sbuf req;
  int first = 1;
  jval* reply;
  const char* why;
  const char* env;
  char envbuf[600];
  char* key = NULL;

  SetConsoleCtrlHandler(on_ctrl, TRUE);
  env = (GetEnvironmentVariableA("SD_AI_PIPE", envbuf, sizeof envbuf) > 0) ? envbuf : NULL; /* the tests; the product never sets it */
  snprintf(path, sizeof path, "%s", (env != NULL && env[0] != '\0') ? env : DEFAULT_PIPE);
  if (n >= 2 && strcmp(args[0], "--pipe") == 0) {
    snprintf(path, sizeof path, "%s", args[1]);
    args += 2;
    n -= 2;
  }
  if (_strnicmp(path, "\\\\.\\pipe\\", 9) != 0)
    return usage();
  check_owner = _stricmp(path, DEFAULT_PIPE) == 0;
#ifdef SDAI_TESTS
  /* THE TEST BUILD ONLY (-DSDAI_TESTS): the owner check on a test pipe too, so that test-aihelper-units.py can see it refuse one not NT SERVICE\sd-ai's */
  if (GetEnvironmentVariableA("SD_AI_TEST_CHECK_OWNER", envbuf, sizeof envbuf) > 0)
    check_owner = 1;
#endif
  if (n < 1)
    return usage();
  cmd = args[0];
  rest = args + 1;
  nr = n - 1;

  sb_init(&req);
  sb_puts(&req, "{\"v\": 1"); /* json.dumps(req): {"v": 1, "op": ...} */
  first = 0;
  if (strcmp(cmd, "show") == 0 && (nr == 0 || (nr == 1 && strcmp(rest[0], "--json") == 0))) {
    kstr(&req, &first, "op", "status");
  } else if (strcmp(cmd, "provider") == 0 && nr == 1) {
    kstr(&req, &first, "op", "set");
    kstr(&req, &first, "what", "provider");
    kstr(&req, &first, "value", strcmp(rest[0], "none") == 0 ? "" : rest[0]);
  } else if (strcmp(cmd, "model") == 0 && nr == 2) {
    kstr(&req, &first, "op", "set");
    kstr(&req, &first, "what", "model");
    kstr(&req, &first, "provider", rest[0]);
    kstr(&req, &first, "value", strcmp(rest[1], "-") == 0 ? "" : rest[1]);
  } else if (strcmp(cmd, "custom") == 0 && nr == 6) {
    kstr(&req, &first, "op", "set");
    kstr(&req, &first, "what", "custom");
    kstr(&req, &first, "name", rest[0]);
    kstr(&req, &first, "url", rest[1]);
    kstr(&req, &first, "format", rest[2]);
    kstr(&req, &first, "auth", rest[3]);
    kstr(&req, &first, "version", strcmp(rest[4], "-") == 0 ? "" : rest[4]);
    kstr(&req, &first, "maxparam", rest[5]);
  } else if (strcmp(cmd, "custom-clear") == 0 && nr == 0) {
    kstr(&req, &first, "op", "set");
    kstr(&req, &first, "what", "custom-clear");
  } else if (strcmp(cmd, "ca") == 0 && nr == 1) {
    kstr(&req, &first, "op", "set");
    kstr(&req, &first, "what", "ca");
    kstr(&req, &first, "value", strcmp(rest[0], "-") == 0 ? "" : rest[0]);
  } else if (strcmp(cmd, "limit") == 0 && nr == 2) {
    kstr(&req, &first, "op", "set");
    kstr(&req, &first, "what", "limit");
    kstr(&req, &first, "name", rest[0]);
    kstr(&req, &first, "value", rest[1]);
  } else if (strcmp(cmd, "context") == 0 && nr == 1) {
    /* S.160: the standing text, as HEX (one word a command line carries whole), or - for the shipped default */
    sbuf text;
    sb_init(&text);
    if (strcmp(rest[0], "-") != 0 && !from_hex(rest[0], &text)) {
      say("sd-ai-ctl: the standing text is given as hexadecimal ASCII");
      return 2;
    }
    kstr(&req, &first, "op", "set");
    kstr(&req, &first, "what", "context");
    sb_key(&req, &first, "value");
    sb_jstr(&req, text.p, text.n);
  } else if (strcmp(cmd, "models") == 0 && nr == 1) {
    kstr(&req, &first, "op", "models"); /* S.170: the provider's own list, one name to a line */
    kstr(&req, &first, "provider", rest[0]);
  } else if (strcmp(cmd, "key-clear") == 0 && nr == 1) {
    kstr(&req, &first, "op", "keyclear");
    kstr(&req, &first, "provider", rest[0]);
  } else if (strcmp(cmd, "key") == 0 && nr == 3 && strcmp(rest[1], "--handover") == 0) {
    key = handover_key(rest[2]); /* removed first, whatever follows */
    if (!is_provider(rest[0])) {
      say("sd-ai-ctl: the provider is one of anthropic, openai, google, deepseek, custom");
      return 2;
    }
    kstr(&req, &first, "op", "keyset");
    kstr(&req, &first, "provider", rest[0]);
    kstr(&req, &first, "key", key);
  } else if (strcmp(cmd, "key") == 0 && nr == 1) {
    if (!is_provider(rest[0])) {
      say("sd-ai-ctl: the provider is one of anthropic, openai, google, deepseek, custom");
      return 2;
    }
    if (GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), &saved_mode))
      have_saved = 1;
    key = read_key_console(rest[0]);
    have_saved = 0;
    kstr(&req, &first, "op", "keyset");
    kstr(&req, &first, "provider", rest[0]);
    kstr(&req, &first, "key", key);
  } else
    return usage();
  sb_puts(&req, "}\n");
  if (key != NULL)
    SecureZeroMemory(key, strlen(key));

  reply = talk(path, req.p, req.n, check_owner, &why);
  SecureZeroMemory(req.p, req.n);
  if (reply == NULL) {
    sayf("sd-ai-ctl: the AI helper could not be reached (%s)", why);
    return 2;
  }
  if (strcmp(sget(reply, "t"), "err") == 0) {
    char code[64], msg[1200];
    pystr(json_get(reply, "code"), code, sizeof code);
    pystr(json_get(reply, "msg"), msg, sizeof msg);
    sayf("error: %s: %s", code, msg);
    return 1;
  }
  if (strcmp(cmd, "show") == 0)
    show(reply, nr == 1);
  else if (strcmp(cmd, "models") == 0) {
    jval* m = json_get(reply, "models");
    size_t i, k = (m != NULL && m->t == J_ARR) ? m->n : 0;
    sayf("models: %d", (int)k);
    for (i = 0; i < k; i++)
      if (json_is_str(m->items[i]))
        sayf("  %s", m->items[i]->s);
  } else if (strcmp(cmd, "key") == 0)
    sayf("The key for %s is set.", rest[0]);
  else if (strcmp(cmd, "key-clear") == 0)
    sayf("The key for %s is cleared.", rest[0]);
  else
    say("ok");
  return 0;
}

/* END-CODE */
