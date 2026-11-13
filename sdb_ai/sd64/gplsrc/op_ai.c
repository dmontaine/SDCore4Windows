/* OP_AI.C
 * The kernel's side of the in-SD AI helper (S.69 step 2; plan .claude/plan-ai-step2.md).
 * Copyright (c) 2026, SD Core for Linux.  This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License, version 3 or later.
 *
 * START-HISTORY:
 * 13 Nov 26 Windows port - from Linux b1d496df (RELEASE_1.1 246; design .claude/design-ai-helper-20261113.md 3.6).  Carried whole: the
 *               arguments, the JSON escaping, the audit line before the connection, the limits and the answers are Linux's.  The transport
 *               differs and only it: Linux's Unix socket and poll() became win32ai.c's named pipe (\\.\pipe\sd-ai, the service sd-ai),
 *               opened at identification level, its server's owner checked before a byte is sent, read only after PeekNamedPipe says
 *               there is something (a pipe in the MSYS2 descriptor table is "always ready" to select(), win32peer.h).  SD_AI_SOCKET is
 *               SD_AI_PIPE here, taken only when it begins \\.\pipe\.  A pipe that is not the service's (squatted) writes one more audit
 *               line, "ai refused reason=pipe.owner", and answers nohelper.
 * 8 Nov 26 dm   A status reply is waited for up to AI_STATUS_MS (8 s), not 2 s: on the test VPS the helper's new process took 2.7 s to answer an administrator's
 *               status, SD had hung up (the helper's BrokenPipeError in the journal) and tool.ai said the helper was not running.
 * 23 Oct 26 dm  New.
 * 3 Nov 26 dm   Follow-up questions (the owner: "Add, shown in preview"): K$AI.START takes  system : FM : maxtokens : VM : n : FM : q1 : FM : a1 ... : FM : prompt, the n (1 to 3)
 *               earlier exchanges the person chose to carry; they go to the helper as "history" and count in bytes.out, and the audit line then says followup=n.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * KERNEL(K$AI.START, system : FM : maxtokens : FM : prompt)   sends one request to the helper (gplbld/sd-ai) on its pipe and returns at once.
 *   A FOLLOW-UP (3 Nov 26) is  system : FM : maxtokens : VM : n : FM : q1 : FM : a1 : ... : FM : qn : FM : an : FM : prompt  with n from 1 to 3: the earlier questions and answers, sent
 *   as "history" before the prompt.  Only $tk_ai builds one, after the person chose Follow up and saw all of it in the preview.
 * KERNEL(K$AI.POLL, 0)       asks whether the answer is in.
 * KERNEL(K$AI.CANCEL, 0)     gives the request up.
 * KERNEL(K$AI.STATUS, 0)     asks the helper for its status line (provider, model, key set, whether THIS caller is in the AI group) and waits at most AI_STATUS_MS.
 *
 *   Answers are strings:   START   OK   |  ERR : FM : busy | toobig | internal | nohelper | bad
 *                          POLL    W (waiting)  |  D : FM : the helper's reply line (JSON)  |  E : FM : nohelper | timeout | toobig | closed | none
 *                          CANCEL  OK
 *                          STATUS  D : FM : the helper's status line  |  E : FM : nohelper | timeout | internal
 *
 * THIS IS A TRANSPORT AND NOTHING ELSE.  It decides nothing about who may use the AI: the helper does, from the caller's token it reads off the pipe
 * (ImpersonateNamedPipeClient at identification level; Linux: SO_PEERCRED), so a caller that skips this file and talks to the pipe itself gets the same
 * answer.  What this file adds is what only the kernel can promise:
 *   - only a $internal program may call it (the library and the verbs; an account's own program cannot), and a call from any other program is refused with ERR internal;
 *   - the request that can be sent is an ask and nothing else (the helper's administrator operations are not reachable from here), built here from the three
 *     arguments: every byte of text is escaped, and a byte above 127 becomes ? (English only; nothing is sent that is not plain ASCII);
 *   - THE AUDIT LINE IS WRITTEN HERE, BEFORE THE CONNECTION IS MADE:  ai request account=<account> program=<the running program> bytes.out=<n>  (audit_message stamps
 *     the user and the process itself), so a crash or a refusal still leaves the record, and no caller can choose what is written;
 *   - one request at a time per process, a total limit of 340 seconds, a reply of at most 512 KB, and nothing left open when the request is over;
 *   - (Windows) the pipe's owner must be the service's account NT SERVICE\sd-ai before anything is sent (win32ai.c): the pipe namespace is global.
 * The pipe is \\.\pipe\sd-ai; SD_AI_PIPE in the environment names another (the tests; the product never sets it, and it can only point a session at a pipe
 * of its own user's choosing: the owner check is for the real name, and the helper at the other end of the real one still asks who is calling).
 *
 * END-DESCRIPTION
 */

#include <errno.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include <unistd.h>

#include "sd.h"
#include "header.h"
#include "keys.h"
#include "win32ai.h"

#define AI_DEFAULT_PIPE "\\\\.\\pipe\\sd-ai"
#define AI_PIPE_PREFIX "\\\\.\\pipe\\"
#define AI_PIPE_NAME_MAX 200
#define AI_REQ_MAX 262144 /* system + prompt, in bytes, as the caller gave them */
#define AI_REPLY_MAX 524288
#define AI_DEADLINE 340 /* seconds, from the start of a request */
#define AI_CONNECT_MS 2000
#define AI_STATUS_MS 8000 /* the most a status reply is waited for: the helper is a new Python process per request (8 Nov 26: 2.7 s on a small VPS, past the old 2 s) */
#define AI_HIST_MAX 3 /* earlier exchanges a follow-up may carry (the helper takes no more) */

Private struct {
  int slot; /* 13 Nov 26 Windows port: a win32ai.c slot, not a descriptor */
  bool active;
  char* buf;
  size_t len;
  size_t cap;
  time_t started;
} ai = {-1, 0, NULL, 0, 0, 0};

Private void ai_reset(void) {
  if (ai.slot >= 0)
    win32_ai_close(ai.slot);
  ai.slot = -1;
  ai.active = 0;
  if (ai.buf != NULL)
    free(ai.buf);
  ai.buf = NULL;
  ai.len = ai.cap = 0;
}

/* The pipe, and whether its owner is to be checked: the real name always is; SD_AI_PIPE (tests) names a pipe of the user's own choosing. */
Private const char* ai_pipe_path(int* check_owner) {
  const char* p = getenv("SD_AI_PIPE");

  if ((p != NULL) && (*p != '\0') && (strlen(p) < AI_PIPE_NAME_MAX) && (strncasecmp(p, AI_PIPE_PREFIX, strlen(AI_PIPE_PREFIX)) == 0)) {
    *check_owner = 0;
    return p;
  }
  *check_owner = 1;
  return AI_DEFAULT_PIPE;
}

/* Connect to the helper's pipe.  -1 when there is no helper to talk to, or the pipe is not the helper's (which is audited). */
Private int ai_connect(void) {
  int check_owner = 1;
  const char* path = ai_pipe_path(&check_owner);
  int slot;

  slot = win32_ai_open(path, check_owner, AI_CONNECT_MS);
  if (slot == WIN32_AI_NOTOURS) {
    audit_message("ai refused reason=pipe.owner");
    return -1;
  }
  return (slot >= 0) ? slot : -1;
}

/* Send all of buf; 0 if the helper does not take it within two seconds a piece. */
Private bool ai_send_all(int slot, const char* buf, size_t len) {
  return win32_ai_write(slot, buf, (int)len, AI_CONNECT_MS) != 0;
}

/* Append to out the JSON string for in[0..n): quotes, backslash and control characters escaped, a byte above 127 written as ?.  Returns the new length. */
Private size_t ai_json_string(char* out, size_t pos, const char* in, size_t n) {
  static const char hex[] = "0123456789abcdef";
  size_t i;

  out[pos++] = '"';
  for (i = 0; i < n; i++) {
    u_char c = (u_char)in[i];
    if (c == '"' || c == '\\') {
      out[pos++] = '\\';
      out[pos++] = (char)c;
    } else if (c == '\n') {
      out[pos++] = '\\';
      out[pos++] = 'n';
    } else if (c == '\t') {
      out[pos++] = '\\';
      out[pos++] = 't';
    } else if (c < 32 || c == 127) {
      out[pos++] = '\\';
      out[pos++] = 'u';
      out[pos++] = '0';
      out[pos++] = '0';
      out[pos++] = hex[c >> 4];
      out[pos++] = hex[c & 15];
    } else if (c >= 128) {
      out[pos++] = '?';
    } else {
      out[pos++] = (char)c;
    }
  }
  out[pos++] = '"';
  return pos;
}

Private void ai_answer(const char* a, const char* b, DESCRIPTOR* result) {
  char* s;
  size_t n = strlen(a) + 1 + ((b != NULL) ? strlen(b) : 0) + 1;

  s = (char*)malloc(n);
  if (s == NULL) {
    k_put_c_string("E\376none", result);
    return;
  }
  strcpy(s, a);
  if (b != NULL) {
    size_t l = strlen(s);
    s[l] = (char)FIELD_MARK;
    strcpy(s + l + 1, b);
  }
  k_put_c_string(s, result);
  free(s);
}

Private void ai_start(DESCRIPTOR* descr, DESCRIPTOR* result) {
  char* arg;
  char* system;
  char* prompt;
  char* maxt;
  char* p;
  char* req;
  const char* pname;
  size_t cap;
  size_t pos;
  int n;
  int maxtokens = 0;
  int nhist;
  int i;
  size_t hbytes;
  char* hist[2 * AI_HIST_MAX];
  char audit[200];

  if (ai.active) {
    ai_answer("ERR", "busy", result);
    return;
  }
  arg = (char*)malloc(AI_REQ_MAX + 64);
  if (arg == NULL) {
    ai_answer("ERR", "bad", result);
    return;
  }
  n = k_get_c_string(descr, arg, AI_REQ_MAX + 32);
  if (n < 0 || n > AI_REQ_MAX) {
    free(arg);
    ai_answer("ERR", "toobig", result);
    return;
  }
  arg[n] = '\0';
  /* system : FM : maxtokens : FM : prompt.  The prompt is last so that a mark byte inside it cannot move a field: the first two marks cut, the rest is the prompt. */
  system = arg;
  p = strchr(system, FIELD_MARK);
  if (p == NULL) {
    free(arg);
    ai_answer("ERR", "bad", result);
    return;
  }
  *p = '\0';
  maxt = p + 1;
  p = strchr(maxt, FIELD_MARK);
  if (p == NULL) {
    free(arg);
    ai_answer("ERR", "bad", result);
    return;
  }
  *p = '\0';
  prompt = p + 1;
  maxtokens = atoi(maxt);
  if (maxtokens < 1)
    maxtokens = 1;
  if (maxtokens > 100000)
    maxtokens = 100000;
  /* A follow-up: maxtokens VM n, then n questions and n answers, each a field, before the prompt (which stays last: a mark in it moves nothing) */
  nhist = 0;
  hbytes = 0;
  p = strchr(maxt, VALUE_MARK);
  if (p != NULL) {
    nhist = atoi(p + 1);
    if (nhist < 1 || nhist > AI_HIST_MAX) {
      free(arg);
      ai_answer("ERR", "bad", result);
      return;
    }
    for (i = 0; i < 2 * nhist; i++) {
      hist[i] = prompt;
      p = strchr(prompt, FIELD_MARK);
      if (p == NULL) {
        free(arg);
        ai_answer("ERR", "bad", result);
        return;
      }
      *p = '\0';
      hbytes += strlen(hist[i]);
      prompt = p + 1;
    }
  }

  /* THE AUDIT LINE: before anything is sent, from the kernel's own state.  It names the account and the program that called, and the size; never the text. */
  /* The audit line gives the name a person knows: a catalogued program is named $name and one run from a file by its whole path, so the $ and the directory are left off. */
  pname = ProgramName(c_base);
  if (strrchr(pname, '/') != NULL)
    pname = strrchr(pname, '/') + 1;
  if (*pname == '$')
    pname++;
  if (nhist > 0)
    snprintf(audit, sizeof(audit), "ai request account=%s program=%s bytes.out=%d followup=%d", account(), pname, (int)(strlen(system) + strlen(prompt) + hbytes), nhist);
  else
    snprintf(audit, sizeof(audit), "ai request account=%s program=%s bytes.out=%d", account(), pname, (int)(strlen(system) + strlen(prompt)));
  audit_message(audit);

  cap = (6 * (strlen(system) + strlen(prompt) + hbytes)) + 256 + (32 * nhist);
  req = (char*)malloc(cap);
  if (req == NULL) {
    free(arg);
    ai_answer("ERR", "bad", result);
    return;
  }
  pos = 0;
  pos += (size_t)sprintf(req + pos, "{\"v\":1,\"op\":\"ask\",\"system\":");
  pos = ai_json_string(req, pos, system, strlen(system));
  pos += (size_t)sprintf(req + pos, ",\"prompt\":");
  pos = ai_json_string(req, pos, prompt, strlen(prompt));
  if (nhist > 0) {
    pos += (size_t)sprintf(req + pos, ",\"history\":[");
    for (i = 0; i < nhist; i++) {
      pos += (size_t)sprintf(req + pos, "%s{\"q\":", (i == 0) ? "" : ",");
      pos = ai_json_string(req, pos, hist[2 * i], strlen(hist[2 * i]));
      pos += (size_t)sprintf(req + pos, ",\"a\":");
      pos = ai_json_string(req, pos, hist[2 * i + 1], strlen(hist[2 * i + 1]));
      req[pos++] = '}';
    }
    req[pos++] = ']';
  }
  pos += (size_t)sprintf(req + pos, ",\"maxtokens\":%d}\n", maxtokens);
  free(arg);

  ai.slot = ai_connect();
  if (ai.slot < 0) {
    free(req);
    ai_answer("ERR", "nohelper", result);
    return;
  }
  if (!ai_send_all(ai.slot, req, pos)) {
    free(req);
    ai_reset();
    ai_answer("ERR", "nohelper", result);
    return;
  }
  free(req);
  ai.active = 1;
  ai.started = time(NULL);
  ai.len = 0;
  ai_answer("OK", NULL, result);
}

Private void ai_poll(DESCRIPTOR* result) {
  int avail;
  int want;
  int n;
  char* nl;

  if (!ai.active) {
    ai_answer("E", "none", result);
    return;
  }
  if ((time(NULL) - ai.started) > AI_DEADLINE) {
    ai_reset();
    ai_answer("E", "timeout", result);
    return;
  }
  for (;;) {
    avail = win32_ai_avail(ai.slot); /* 13 Nov 26 Windows port: Linux's poll(POLLIN, 0) */
    if (avail <= 0)
      break;
    if ((ai.cap - ai.len) < 4096) {
      size_t ncap = (ai.cap == 0) ? 16384 : (ai.cap * 2);
      char* nb;
      if (ncap > (AI_REPLY_MAX + 16384)) {
        ai_reset();
        ai_answer("E", "toobig", result);
        return;
      }
      nb = (char*)realloc(ai.buf, ncap);
      if (nb == NULL) {
        ai_reset();
        ai_answer("E", "toobig", result);
        return;
      }
      ai.buf = nb;
      ai.cap = ncap;
    }
    want = (int)(ai.cap - ai.len - 1);
    if (want > avail)
      want = avail;
    n = win32_ai_read(ai.slot, ai.buf + ai.len, want);
    if (n > 0) {
      ai.len += (size_t)n;
      ai.buf[ai.len] = '\0';
      if (strchr(ai.buf, '\n') != NULL)
        break;
      continue;
    }
    break; /* end of file or an error: judged below from what was read */
  }
  if (ai.buf != NULL && ai.len > 0) {
    ai.buf[ai.len] = '\0';
    nl = strchr(ai.buf, '\n');
    if (nl != NULL) {
      *nl = '\0';
      ai_answer("D", ai.buf, result);
      ai_reset();
      return;
    }
  }
  /* no complete line yet: still waiting, unless the helper has hung up (Linux: POLLHUP with no POLLIN; here the pipe is broken and empty) */
  if (win32_ai_avail(ai.slot) < 0) {
    ai_reset();
    ai_answer("E", "closed", result);
    return;
  }
  ai_answer("W", NULL, result);
}

/* The helper's status line: a request of its own, answered or given up within AI_STATUS_MS. */
Private void ai_status(DESCRIPTOR* result) {
  static const char req[] = "{\"v\":1,\"op\":\"status\"}\n";
  char buf[65536];
  size_t len = 0;
  int slot;
  int avail;
  int want;
  int n;
  char* nl;
  int waited = 0;

  slot = ai_connect();
  if (slot < 0) {
    ai_answer("E", "nohelper", result);
    return;
  }
  if (!ai_send_all(slot, req, sizeof(req) - 1)) {
    win32_ai_close(slot);
    ai_answer("E", "nohelper", result);
    return;
  }
  while (waited < AI_STATUS_MS && len < sizeof(buf) - 1) {
    avail = win32_ai_avail(slot);
    if (avail < 0)
      break;
    if (avail == 0) {
      usleep(100000);
      waited += 100;
      continue;
    }
    want = (int)(sizeof(buf) - 1 - len);
    if (want > avail)
      want = avail;
    n = win32_ai_read(slot, buf + len, want);
    if (n <= 0)
      break;
    len += (size_t)n;
    buf[len] = '\0';
    if (strchr(buf, '\n') != NULL)
      break;
  }
  win32_ai_close(slot);
  buf[len] = '\0';
  nl = strchr(buf, '\n');
  if (nl == NULL) {
    ai_answer("E", (len == 0) ? "timeout" : "nohelper", result);
    return;
  }
  *nl = '\0';
  ai_answer("D", buf, result);
}

/* The four calls.  result is the descriptor op_kernel() will put on the stack; descr is the argument. */
void k_ai(int action, DESCRIPTOR* descr, DESCRIPTOR* result) {
  if (!(process.program.flags & HDR_INTERNAL)) {
    ai_answer("ERR", "internal", result);
    return;
  }
  switch (action) {
    case K_AI_START:
      ai_start(descr, result);
      break;
    case K_AI_POLL:
      ai_poll(result);
      break;
    case K_AI_CANCEL:
      ai_reset();
      ai_answer("OK", NULL, result);
      break;
    case K_AI_STATUS:
      ai_status(result);
      break;
    default:
      ai_answer("ERR", "bad", result);
      break;
  }
}

/* END-CODE */
