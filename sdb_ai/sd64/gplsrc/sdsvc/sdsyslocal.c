/* sdsyslocal.c - "ssh -t <user>@localhost sd-sdsys": the SD service's door to an SDSYS session
 *
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
 * 18 Nov 26 Windows port - written.  RELEASE_1.1 339, the Windows reading of Linux's root door (sd-elevate sdsys-session, 38cfb301);
 *           .claude/localsdsys/DESIGN.md section 4.2.  NOT RUN: compiled and linked only; the VM witness (W0 first) measures it.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHY THE SERVICE.  An SDSYS process needs SDSYS's token, and without SDSYS's Windows password only an S4U logon makes one, which
 * takes SeTcb; starting a process with it takes SeAssignPrimaryToken.  LocalSystem has both, and the SD service is the one
 * LocalSystem process SD has that lives as long as SD does (sdrunin.c's reasoning).
 *
 * WHO ASKS.  Any SD user may open the pipe (its DACL: LocalSystem all, sdusers read and write); nothing is believed of what the asker
 * says except the window size and the terminal type.  Before anything is started, in this order, each failure a reason word:
 *   1. the request line arrives whole within SL_REQUEST_MS and nothing after it                       bad-request
 *   2. P = GetNamedPipeClientProcessId - the kernel's answer, not the asker's - opened and HELD open
 *      until the session ends, so its pid cannot be given to another process under the checks           no-login
 *   3. the token of the thread that wrote the request (ImpersonateNamedPipeClient at identification
 *      level, then RevertToSelf; a revert that fails ends the service): its user and logon id            no-login
 *   4. P's own primary token has the same user and the same logon id: the pipe's client IS P             other-session
 *   5. the request parsed strictly (win32sdsysask.h)                                                   bad-request
 *   6. sdl_ssh_evidence(P) (win32localsdsys.c): the ssh list, the account, the logon, the ancestry to
 *      sshd, sshd's own Accepted record, a loopback peer and its connection still open                   its own word
 *   7. the user it names is the user of step 3, and P is still running                                   other-session, no-session
 * Then: an S4U logon of SDSYS (win32s4ulogon.c), made primary and checked ELEVATED (not-elevated); a pseudo console of the asker's
 * size; a job with KILL_ON_JOB_CLOSE (not one process: an SDSYS session starts the elevated helper and PowerShell); the process
 * "<dir of sdsvc.exe>\sd.exe -SDSYSLOCAL <P>" made suspended, put in the job, then let run (a start that fails: not-started).
 * That process's own kernel asks the same questions about P again (sdl_ssh_self), and LOGIN then asks SDSYS's SD password.
 *
 * WHAT IS LOGGED.  Every refusal and every start is ONE line of sdsvc.log naming the word, the pid and the user; a refusal sends the
 * asker "REFUSED <word>" and closes.  SD's audit trail does not see a refusal here: SD never ran (Linux T0745 Q11).
 *
 * THE RELAY.  The pseudo console's output goes to the asker from a thread of its own, which reads until the output ends even when
 * the asker has gone, so that ClosePseudoConsole is never left waiting on a full pipe.  The asker's frames (keys, sizes) are read
 * here and given to the pseudo console.  The session ends when the SDSYS process exits (the pseudo console is closed, its last
 * output reaches the asker, then the pipe is let go) or when the asker goes (the job is terminated).
 *
 * NOTHING HERE IS FATAL TO THE SERVICE except a RevertToSelf that fails.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* CreatePseudoConsole and PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE are declared from Windows 10 1809 (RS5); SD's floor is Windows 11. */
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x0A000006
#endif

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <userenv.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>

#include "../win32localsdsys.h"
#include "../win32sdsysask.h"
#include "../win32s4u.h"
#include "sdsyslocal.h"

#define SL_INSTANCES 2
#define SL_REQUEST_MS 10000   /* the request line must arrive within this */
#define SL_WRITE_MS 60000     /* a write of the screen to the asker that takes longer ends the session */
#define SL_FLUSH_MS 3000      /* the last screen, read by the asker before the pipe is let go */
#define SL_EXIT_MS 5000       /* the SDSYS process, terminated, given this to be gone */
#define SL_DRAIN_MS 5000      /* the output thread, after the pseudo console is closed, given this to end */
#define SL_STOP_MS 8000
#define SL_IO 4096
#define SL_FRAMES (2 * (3 + SDASK_KEYS_MAX) + 16)
#define SL_USERS_GROUP "sdusers"
#define SL_ACCOUNT "SDSYS"

/* What an SD user may do to the pipe: read and write data, read its owner and attributes.  Not FILE_CREATE_PIPE_INSTANCE, WRITE_DAC
   or WRITE_OWNER. */
#define SL_PIPE_GRANT (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)

typedef struct {
  HANDLE pipe;            /* the asker's pipe (overlapped) */
  HANDLE asker;           /* P, held open */
  DWORD asker_pid;
  HANDLE job;
  HANDLE proc;
  HANDLE thread;          /* its first thread, suspended until the asker has been told STARTED */
  DWORD pid;
  HPCON pc;
  HANDLE in_write;        /* the keys, into the pseudo console */
  HANDLE out_read;        /* the screen, out of it */
  HANDLE out_thread;
  volatile LONG asker_gone;
  char who[260];
} SL_SESSION;

static BOOL sl_running = FALSE;
static HANDLE sl_stop_event = NULL;
static HANDLE sl_threads[SL_INSTANCES];
static HANDLE sl_pipes[SL_INSTANCES];
static int sl_nthreads = 0;
static char sl_pipe_name[MAX_PATH];
static char sl_sd_exe[MAX_PATH];
static PSECURITY_DESCRIPTOR sl_pipe_sd = NULL;
static PACL sl_pipe_acl = NULL;
static BYTE sl_own_sid[SECURITY_MAX_SID_SIZE];
static BYTE sl_users_sid[SECURITY_MAX_SID_SIZE];

static void sl_nolog(const char* fmt, ...) {
  (void)fmt;
}

static sdsyslocal_log_fn sl_log = sl_nolog;

static void say(char* why, size_t whylen, const char* fmt, ...) {
  va_list ap;

  if ((why == NULL) || (whylen == 0))
    return;
  va_start(ap, fmt);
  vsnprintf(why, whylen, fmt, ap);
  va_end(ap);
}

/* ======================================================================
   The request                                                              */

/* digits only, 1 to 3 of them, lo..SDASK_MAX_SIZE; 0 when not */
static int sl_size(const char* w, int lo) {
  int v = 0;
  int n;

  if ((w == NULL) || (*w == '\0'))
    return 0;
  for (n = 0; w[n] != '\0'; n++) {
    if ((n >= 3) || (w[n] < '0') || (w[n] > '9'))
      return 0;
    v = (v * 10) + (w[n] - '0');
  }
  return ((v >= lo) && (v <= SDASK_MAX_SIZE)) ? v : 0;
}

int sdsyslocal_parse(const char* line, int* cols, int* rows, char* term, size_t tlen) {
  char copy[SDASK_LINE_MAX + 1];
  char* f[3];
  char* p;
  int i;

  *cols = 0;
  *rows = 0;
  if (tlen > 0)
    term[0] = '\0';
  if ((line == NULL) || (strlen(line) >= sizeof(copy)) || (strncmp(line, SDASK_MAGIC, strlen(SDASK_MAGIC)) != 0))
    return -1;
  strcpy(copy, line + strlen(SDASK_MAGIC));
  p = copy;
  for (i = 0; i < 3; i++) {
    f[i] = p;
    p = strchr(p, ' ');
    if (i < 2) {
      if (p == NULL)
        return -1;
      *(p++) = '\0';
    } else if (p != NULL) {
      return -1;
    }
  }
  if (!sdask_term_ok(f[2]) || (strlen(f[2]) >= tlen))
    return -1;
  *cols = sl_size(f[0], SDASK_MIN_COLS);
  *rows = sl_size(f[1], SDASK_MIN_ROWS);
  if ((*cols == 0) || (*rows == 0))
    return -1;
  strcpy(term, f[2]);
  return 0;
}

/* ======================================================================
   The pipe's I/O                                                           */

/* One overlapped read or write on h, given ms (INFINITE allowed) to finish, and ended at once by the stop event. */
static BOOL sl_io(HANDLE h, HANDLE ev, BOOL writing, void* buf, DWORD len, DWORD* done, DWORD ms) {
  OVERLAPPED ov;
  HANDLE waits[2];
  BOOL ok;
  DWORD w;

  *done = 0;
  ZeroMemory(&ov, sizeof(ov));
  ov.hEvent = ev;
  ResetEvent(ev);
  ok = writing ? WriteFile(h, buf, len, NULL, &ov) : ReadFile(h, buf, len, NULL, &ov);
  if (!ok && (GetLastError() != ERROR_IO_PENDING))
    return FALSE;
  waits[0] = ev;
  waits[1] = sl_stop_event;
  w = WaitForMultipleObjects(2, waits, FALSE, ms);
  if (w != WAIT_OBJECT_0) {
    CancelIoEx(h, &ov);
    (void)GetOverlappedResult(h, &ov, done, TRUE);
    *done = 0;
    return FALSE;
  }
  return GetOverlappedResult(h, &ov, done, FALSE);
}

static BOOL sl_write_all(HANDLE h, HANDLE ev, const char* buf, DWORD len, DWORD ms) {
  DWORD n;

  while (len > 0) {
    if (!sl_io(h, ev, TRUE, (void*)buf, len, &n, ms) || (n == 0))
      return FALSE;
    buf += n;
    len -= n;
  }
  return TRUE;
}

static DWORD WINAPI sl_flush_thread(LPVOID arg) {
  FlushFileBuffers((HANDLE)arg);
  return 0;
}

/* What was written reaches the asker before the pipe is let go: DisconnectNamedPipe throws away what it has not read (sdrunin.c,
   measured by test-runindebug-units.py N7). */
static void sl_flush(HANDLE h) {
  HANDLE t = CreateThread(NULL, 0, sl_flush_thread, (LPVOID)h, 0, NULL);

  if (t == NULL)
    return;
  if (WaitForSingleObject(t, SL_FLUSH_MS) == WAIT_TIMEOUT) {
    CancelSynchronousIo(t);
    WaitForSingleObject(t, 1000);
  }
  CloseHandle(t);
}

static BOOL sl_answer(HANDLE h, HANDLE ev, const char* fmt, ...) {
  char line[SDASK_ANSWER_MAX];
  va_list ap;
  int len;

  va_start(ap, fmt);
  len = vsnprintf(line, sizeof(line) - 1, fmt, ap);
  va_end(ap);
  if ((len < 0) || (len >= (int)sizeof(line) - 1))
    len = (int)sizeof(line) - 2;
  line[len++] = '\n';
  return sl_write_all(h, ev, line, (DWORD)len, 2000);
}

/* ======================================================================
   Who asks                                                                 */

/* User SID and logon id of a token, and DOMAIN\name for the log.  1 or 0. */
static int sl_token_user(HANDLE tok, BYTE* sid, LUID* logon, char* who, size_t wholen) {
  BYTE ubuf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  TOKEN_STATISTICS ts;
  char name[128];
  char dom[128];
  DWORD nl = sizeof(name);
  DWORD dl = sizeof(dom);
  SID_NAME_USE use;
  LPSTR text = NULL;
  DWORD n = 0;

  if (!GetTokenInformation(tok, TokenUser, ubuf, sizeof(ubuf), &n) ||
      !CopySid(SECURITY_MAX_SID_SIZE, (PSID)sid, ((TOKEN_USER*)ubuf)->User.Sid))
    return 0;
  n = 0;
  if (!GetTokenInformation(tok, TokenStatistics, &ts, sizeof(ts), &n))
    return 0;
  *logon = ts.AuthenticationId;
  if (who != NULL) {
    if (LookupAccountSidA(NULL, (PSID)sid, name, &nl, dom, &dl, &use))
      snprintf(who, wholen, "%s\\%s", dom, name);
    else if (ConvertSidToStringSidA((PSID)sid, &text)) {
      snprintf(who, wholen, "%s", text);
      LocalFree(text);
    }
  }
  return 1;
}

/* Steps 2 to 4 of the description.  0 and the client's SID and logon id, or -1 and *word. */
static int sl_client(HANDLE h, SL_SESSION* s, BYTE* sid, LUID* logon, const char** word, char* why, size_t whylen) {
  HANDLE tok = NULL;
  HANDLE ptok = NULL;
  BYTE psid[SECURITY_MAX_SID_SIZE];
  LUID plogon;
  ULONG pid = 0;

  *word = "no-login";
  if (!GetNamedPipeClientProcessId(h, &pid) || (pid == 0)) {
    say(why, whylen, "the pipe's client process could not be named (error %lu)", (unsigned long)GetLastError());
    return -1;
  }
  s->asker_pid = (DWORD)pid;
  s->asker = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, (DWORD)pid);
  if (s->asker == NULL) {
    say(why, whylen, "the pipe's client process could not be opened (error %lu)", (unsigned long)GetLastError());
    return -1;
  }

  if (ImpersonateNamedPipeClient(h)) {
    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok))
      tok = NULL;
    if (!RevertToSelf()) {
      /* Never go on as somebody else in a LocalSystem process. */
      sl_log("sdsys local: RevertToSelf failed (error %lu) - the service ends", (unsigned long)GetLastError());
      ExitProcess(1);
    }
  }
  if (tok == NULL) {
    say(why, whylen, "the asker's token could not be read");
    return -1;
  }
  if (!sl_token_user(tok, sid, logon, s->who, sizeof(s->who))) {
    CloseHandle(tok);
    say(why, whylen, "the asker's token could not be read");
    return -1;
  }
  CloseHandle(tok);

  if (!OpenProcessToken(s->asker, TOKEN_QUERY, &ptok)) {
    say(why, whylen, "the client process's token could not be opened (error %lu)", (unsigned long)GetLastError());
    return -1;
  }
  if (!sl_token_user(ptok, psid, &plogon, NULL, 0)) {
    CloseHandle(ptok);
    say(why, whylen, "the client process's token could not be read");
    return -1;
  }
  CloseHandle(ptok);
  if (!EqualSid((PSID)sid, (PSID)psid) || (logon->LowPart != plogon.LowPart) || (logon->HighPart != plogon.HighPart)) {
    *word = "other-session";
    say(why, whylen, "the pipe was written by another user or logon than process %lu's", (unsigned long)pid);
    return -1;
  }
  return 0;
}

/* ======================================================================
   The SDSYS process                                                        */

static int env_dropped(const WCHAR* var) {
  static const WCHAR* drop[] = {L"TERM",           L"LINES",         L"COLUMNS",    L"SD_SESSION", L"SD_PHANTOM_NONCE",
                                L"SSH_ORIGINAL_COMMAND", L"SSH_CONNECTION", L"SSH_CLIENT", L"SSH_TTY",   NULL};
  const WCHAR* eq;
  size_t len;
  int i;

  if (var[0] == L'=')
    return 0; /* the per-drive current directories: kept as they are */
  if ((eq = wcschr(var, L'=')) == NULL)
    return 1;
  len = (size_t)(eq - var);
  for (i = 0; drop[i] != NULL; i++) {
    if ((wcslen(drop[i]) == len) && (_wcsnicmp(var, drop[i], len) == 0))
      return 1;
  }
  return 0;
}

/* SDSYS's own environment block, less the variables above, plus TERM.  malloc'd, or NULL. */
static WCHAR* sl_env(const void* src, const char* term) {
  WCHAR add[SDASK_TERM_MAX + 8];
  const WCHAR* p;
  WCHAR* out;
  WCHAR* q;
  size_t total = 1;
  size_t n;

  if (swprintf(add, SDASK_TERM_MAX + 8, L"TERM=%hs", term) < 0)
    return NULL;
  total += wcslen(add) + 1;
  for (p = (const WCHAR*)src; (p != NULL) && (*p != L'\0'); p += wcslen(p) + 1) {
    if (!env_dropped(p))
      total += wcslen(p) + 1;
  }
  if ((out = (WCHAR*)malloc(total * sizeof(WCHAR))) == NULL)
    return NULL;
  q = out;
  for (p = (const WCHAR*)src; (p != NULL) && (*p != L'\0'); p += wcslen(p) + 1) {
    if (!env_dropped(p)) {
      n = wcslen(p) + 1;
      memcpy(q, p, n * sizeof(WCHAR));
      q += n;
    }
  }
  n = wcslen(add) + 1;
  memcpy(q, add, n * sizeof(WCHAR));
  q += n;
  *q = L'\0';
  return out;
}

/* The screen: everything the pseudo console writes, to the asker while it is there, read to the end whatever happens. */
static DWORD WINAPI sl_out_thread(LPVOID arg) {
  SL_SESSION* s = (SL_SESSION*)arg;
  HANDLE ev = CreateEventA(NULL, TRUE, FALSE, NULL);
  char buf[SL_IO];
  DWORD n;

  for (;;) {
    n = 0;
    if (!ReadFile(s->out_read, buf, sizeof(buf), &n, NULL) || (n == 0))
      break; /* the pseudo console is closed */
    if ((ev == NULL) || InterlockedCompareExchange(&s->asker_gone, 0, 0))
      continue;
    if (!sl_write_all(s->pipe, ev, buf, n, SL_WRITE_MS))
      InterlockedExchange(&s->asker_gone, 1);
  }
  if (ev != NULL)
    CloseHandle(ev);
  return 0;
}

static void sl_end(SL_SESSION* s) {
  DWORD code = 0;

  if (s->job != NULL)
    TerminateJobObject(s->job, 1);
  if (s->proc != NULL)
    WaitForSingleObject(s->proc, SL_EXIT_MS);
  if (s->thread != NULL)
    CloseHandle(s->thread);
  s->thread = NULL;
  if ((s->out_thread == NULL) && (s->out_read != NULL)) {
    /* Nobody reads the screen (the start failed before the thread): its pipe goes first, so the close cannot wait on it. */
    CloseHandle(s->out_read);
    s->out_read = NULL;
  }
  if (s->pc != NULL)
    ClosePseudoConsole(s->pc); /* the output thread is still reading, so this is not left waiting on a full pipe */
  s->pc = NULL;
  if (s->out_thread != NULL) {
    if (WaitForSingleObject(s->out_thread, SL_DRAIN_MS) == WAIT_TIMEOUT) {
      CancelSynchronousIo(s->out_thread);
      WaitForSingleObject(s->out_thread, 1000);
    }
    CloseHandle(s->out_thread);
  }
  if (s->out_read != NULL)
    CloseHandle(s->out_read);
  if (s->in_write != NULL)
    CloseHandle(s->in_write);
  if (s->proc != NULL) {
    GetExitCodeProcess(s->proc, &code);
    CloseHandle(s->proc);
    sl_log("sdsys local: the SDSYS session pid %lu for pid %lu user %s ended (exit %lu)", (unsigned long)s->pid,
           (unsigned long)s->asker_pid, s->who, (unsigned long)code);
  }
  if (s->job != NULL)
    CloseHandle(s->job);
  if (s->asker != NULL)
    CloseHandle(s->asker);
  s->out_thread = NULL;
  s->out_read = NULL;
  s->in_write = NULL;
  s->proc = NULL;
  s->job = NULL;
  s->asker = NULL;
}

/* Every check has passed: SDSYS, elevated, in a pseudo console of the asker's size, in a job.  1, or 0 with *word and why. */
static int sl_start(SL_SESSION* s, int cols, int rows, const char* term, const char** word, char* why, size_t whylen) {
  HANDLE imp = NULL;
  HANDLE prim = NULL;
  HANDLE in_read = NULL;
  HANDLE out_write = NULL;
  TOKEN_ELEVATION el;
  STARTUPINFOEXW six;
  PROCESS_INFORMATION pi;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION jl;
  COORD size;
  HRESULT hr;
  SIZE_T alen = 0;
  void* env = NULL;
  WCHAR* newenv = NULL;
  WCHAR exe[MAX_PATH];
  WCHAR dir[MAX_PATH];
  WCHAR cmd[MAX_PATH + 64];
  WCHAR* slash;
  DWORD n = 0;
  int ok = 0;

  *word = "not-started";
  ZeroMemory(&six, sizeof(six));
  ZeroMemory(&pi, sizeof(pi));
  six.StartupInfo.cb = sizeof(six);

  /* SDSYS, by S4U (SeTcb: this service only), made primary, and ELEVATED or nothing. */
  imp = (HANDLE)win32_s4u_logon(SL_ACCOUNT);
  if (imp == NULL) {
    say(why, whylen, "the account %s could not be logged on by S4U", SL_ACCOUNT);
    return 0;
  }
  if (!DuplicateTokenEx(imp, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation, TokenPrimary, &prim)) {
    say(why, whylen, "DuplicateTokenEx failed (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  if (!GetTokenInformation(prim, TokenElevation, &el, sizeof(el), &n) || !el.TokenIsElevated) {
    *word = "not-elevated";
    say(why, whylen, "the S4U logon of %s is not elevated", SL_ACCOUNT);
    goto done;
  }

  /* The pseudo console: keys in through one pipe, the screen out through the other. */
  if (!CreatePipe(&in_read, &s->in_write, NULL, 0) || !CreatePipe(&s->out_read, &out_write, NULL, 0)) {
    say(why, whylen, "the pseudo console's pipes could not be made (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  size.X = (SHORT)cols;
  size.Y = (SHORT)rows;
  hr = CreatePseudoConsole(size, in_read, out_write, 0, &s->pc);
  if (FAILED(hr)) {
    s->pc = NULL;
    say(why, whylen, "CreatePseudoConsole failed (0x%08lx)", (unsigned long)hr);
    goto done;
  }
  InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
  six.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, alen);
  if ((six.lpAttributeList == NULL) || !InitializeProcThreadAttributeList(six.lpAttributeList, 1, 0, &alen)) {
    if (six.lpAttributeList != NULL)
      HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
    six.lpAttributeList = NULL;
    say(why, whylen, "the attribute list could not be made (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  if (!UpdateProcThreadAttribute(six.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, s->pc, sizeof(HPCON), NULL,
                                 NULL)) {
    say(why, whylen, "the pseudo console could not be given to the process (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  /* The standard handles are the pseudo console's: USESTDHANDLES with none, or a child takes its parent's (memory, 14 Nov 26). */
  six.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  six.StartupInfo.hStdInput = NULL;
  six.StartupInfo.hStdOutput = NULL;
  six.StartupInfo.hStdError = NULL;
  six.StartupInfo.lpDesktop = (WCHAR*)L"winsta0\\default"; /* as sdrunin.c, whose S4U child was measured to start with it */

  /* SDSYS's own environment, less what the ssh login or another session set, plus TERM. */
  if (!CreateEnvironmentBlock(&env, prim, FALSE))
    env = NULL;
  if ((newenv = sl_env(env, term)) == NULL) {
    say(why, whylen, "the environment could not be made");
    goto done;
  }

  /* The job: the session's end ends every process in it. */
  if ((s->job = CreateJobObjectA(NULL, NULL)) == NULL) {
    say(why, whylen, "the job could not be made (error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  ZeroMemory(&jl, sizeof(jl));
  jl.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION;
  if (!SetInformationJobObject(s->job, JobObjectExtendedLimitInformation, &jl, sizeof(jl))) {
    say(why, whylen, "the job's limits could not be set (error %lu)", (unsigned long)GetLastError());
    goto done;
  }

  /* "<dir of sdsvc.exe>\sd.exe" -SDSYSLOCAL <P>.  Its working directory is sd.exe's own; LOGIN changes to the account's. */
  if (MultiByteToWideChar(CP_ACP, 0, sl_sd_exe, -1, exe, MAX_PATH) == 0) {
    say(why, whylen, "sd.exe's path could not be made");
    goto done;
  }
  wcscpy(dir, exe);
  if ((slash = wcsrchr(dir, L'\\')) != NULL)
    *slash = L'\0';
  if (swprintf(cmd, MAX_PATH + 64, L"\"%ls\" -SDSYSLOCAL %lu", exe, (unsigned long)s->asker_pid) < 0) {
    say(why, whylen, "the command line is too long");
    goto done;
  }
  if (!CreateProcessAsUserW(prim, exe, cmd, NULL, NULL, FALSE,
                            CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT, newenv, dir,
                            &six.StartupInfo, &pi)) {
    say(why, whylen, "the SDSYS process could not be started (CreateProcessAsUser error %lu)", (unsigned long)GetLastError());
    goto done;
  }
  if (!AssignProcessToJobObject(s->job, pi.hProcess)) {
    say(why, whylen, "the SDSYS process could not be put in its job (error %lu); it was not let run",
        (unsigned long)GetLastError());
    TerminateProcess(pi.hProcess, 1);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    goto done;
  }
  /* Still suspended: sl_go() lets it run once the asker has been told STARTED, so no screen byte can come before that line. */
  s->proc = pi.hProcess;
  s->thread = pi.hThread;
  s->pid = pi.dwProcessId;
  ok = 1;

done:
  /* The pseudo console holds its own copies of its ends of the two pipes. */
  if (in_read != NULL)
    CloseHandle(in_read);
  if (out_write != NULL)
    CloseHandle(out_write);
  if (six.lpAttributeList != NULL) {
    DeleteProcThreadAttributeList(six.lpAttributeList);
    HeapFree(GetProcessHeap(), 0, six.lpAttributeList);
  }
  if (newenv != NULL)
    free(newenv);
  if (env != NULL)
    DestroyEnvironmentBlock(env);
  if (prim != NULL)
    CloseHandle(prim);
  if (imp != NULL)
    CloseHandle(imp);
  return ok;
}

/* The asker has been told STARTED: the screen's thread, then the SDSYS process let run.  1, or 0 with why. */
static int sl_go(SL_SESSION* s, char* why, size_t whylen) {
  s->out_thread = CreateThread(NULL, 0, sl_out_thread, (LPVOID)s, 0, NULL);
  if (s->out_thread == NULL) {
    say(why, whylen, "the screen's thread could not be made (error %lu); the SDSYS process was not let run",
        (unsigned long)GetLastError());
    return 0;
  }
  if (ResumeThread(s->thread) == (DWORD)-1) {
    say(why, whylen, "the SDSYS process could not be let run (error %lu)", (unsigned long)GetLastError());
    return 0;
  }
  CloseHandle(s->thread);
  s->thread = NULL;
  return 1;
}

/* ======================================================================
   The relay                                                                */

/* The asker's frames in buf[0..*len): each whole one given to the pseudo console, a part kept.  0, or -1 when a frame is not one. */
static int sl_frames(SL_SESSION* s, unsigned char* buf, DWORD* len) {
  DWORD used = 0;
  DWORD n;
  DWORD k;
  int cols;
  int rows;
  COORD size;

  while (used < *len) {
    unsigned char* f = buf + used;
    DWORD have = *len - used;

    if (f[0] == SDASK_FRAME_KEYS) {
      if (have < 3)
        break;
      k = ((DWORD)f[1] << 8) | f[2];
      if ((k == 0) || (k > SDASK_KEYS_MAX))
        return -1;
      if (have < 3 + k)
        break;
      n = 0;
      if (!WriteFile(s->in_write, f + 3, k, &n, NULL) || (n != k))
        return -1;
      used += 3 + k;
    } else if (f[0] == SDASK_FRAME_SIZE) {
      if (have < 5)
        break;
      cols = (f[1] << 8) | f[2];
      rows = (f[3] << 8) | f[4];
      if ((cols < SDASK_MIN_COLS) || (cols > SDASK_MAX_SIZE) || (rows < SDASK_MIN_ROWS) || (rows > SDASK_MAX_SIZE))
        return -1;
      size.X = (SHORT)cols;
      size.Y = (SHORT)rows;
      (void)ResizePseudoConsole(s->pc, size);
      used += 5;
    } else {
      return -1;
    }
  }
  if (used > 0) {
    memmove(buf, buf + used, *len - used);
    *len -= used;
  }
  return 0;
}

/* Until the SDSYS process exits, the asker goes, or the service stops. */
static void sl_relay(SL_SESSION* s) {
  OVERLAPPED ov;
  HANDLE ev = CreateEventA(NULL, TRUE, FALSE, NULL);
  HANDLE waits[4];
  unsigned char fbuf[SL_FRAMES];
  DWORD flen = 0;
  DWORD room;
  DWORD n;
  DWORD w;
  BOOL pend = FALSE;
  BOOL child_done = FALSE;

  if (ev == NULL) {
    InterlockedExchange(&s->asker_gone, 1);
    return;
  }
  for (;;) {
    if (!pend) {
      room = sizeof(fbuf) - flen;
      if (room > SL_IO)
        room = SL_IO;
      ZeroMemory(&ov, sizeof(ov));
      ov.hEvent = ev;
      ResetEvent(ev);
      if (!ReadFile(s->pipe, fbuf + flen, room, NULL, &ov) && (GetLastError() != ERROR_IO_PENDING)) {
        InterlockedExchange(&s->asker_gone, 1);
        break;
      }
      pend = TRUE;
    }
    waits[0] = ev;
    waits[1] = s->proc;
    waits[2] = sl_stop_event;
    waits[3] = s->out_thread;
    w = WaitForMultipleObjects(4, waits, FALSE, INFINITE);
    if (w == WAIT_OBJECT_0) {               /* the asker typed, resized, or went */
      pend = FALSE;
      if (!GetOverlappedResult(s->pipe, &ov, &n, FALSE) || (n == 0)) {
        InterlockedExchange(&s->asker_gone, 1);
        break;
      }
      flen += n;
      if (sl_frames(s, fbuf, &flen) != 0) {
        sl_log("sdsys local: the asker pid %lu user %s sent what is not a frame; the session ends", (unsigned long)s->asker_pid,
               s->who);
        InterlockedExchange(&s->asker_gone, 1);
        break;
      }
    } else if (w == WAIT_OBJECT_0 + 1) {    /* the SDSYS process has exited */
      child_done = TRUE;
      break;
    } else if (w == WAIT_OBJECT_0 + 3) {    /* the screen ended without the process: end it */
      break;
    } else {                                /* the service is stopping, or the wait failed */
      break;
    }
  }
  if (pend) {
    CancelIoEx(s->pipe, &ov);
    (void)GetOverlappedResult(s->pipe, &ov, &n, TRUE);
  }
  CloseHandle(ev);

  if (child_done && (s->pc != NULL)) {
    /* The last screen: the pseudo console closed, its output read to the end, then given time to reach the asker. */
    ClosePseudoConsole(s->pc);
    s->pc = NULL;
    if (WaitForSingleObject(s->out_thread, SL_DRAIN_MS) == WAIT_TIMEOUT)
      CancelSynchronousIo(s->out_thread);
    if (!InterlockedCompareExchange(&s->asker_gone, 0, 0))
      sl_flush(s->pipe);
  }
}

/* ======================================================================
   One asker                                                                */

static void sl_refuse(HANDLE h, HANDLE ev, SL_SESSION* s, const char* word, const char* why) {
  sl_log("sdsys local: refused %s for pid %lu user %s: %s", word, (unsigned long)s->asker_pid, s->who, why);
  sl_answer(h, ev, "%s%s", SDASK_REFUSED, word);
  sl_flush(h);
}

static void sl_serve_one(HANDLE h, HANDLE ev) {
  char line[SDASK_LINE_MAX + 1];
  char why[400];
  char name[64];
  char sidtext[SDL_SID_MAX];
  char term[SDASK_TERM_MAX + 1];
  BYTE sid[SECURITY_MAX_SID_SIZE];
  LUID logon;
  LPSTR mine = NULL;
  SL_SESSION s;
  ULONGLONG until = GetTickCount64() + SL_REQUEST_MS;
  const char* word = "";
  DWORD got = 0;
  DWORD n;
  DWORD code = 0;
  char* nl = NULL;
  int cols;
  int rows;

  memset(&s, 0, sizeof(s));
  s.pipe = h;
  snprintf(s.who, sizeof(s.who), "?");

  /* 1. The request, one line, read whole and bounded.  ImpersonateNamedPipeClient needs something read first. */
  while (got < SDASK_LINE_MAX) {
    ULONGLONG now = GetTickCount64();

    if ((now >= until) || !sl_io(h, ev, FALSE, line + got, SDASK_LINE_MAX - got, &n, (DWORD)(until - now)) || (n == 0)) {
      ULONG cpid = 0;

      /* Nothing whole arrived: nobody to answer, but the refusal is still a line of the log. */
      (void)GetNamedPipeClientProcessId(h, &cpid);
      sl_log("sdsys local: refused bad-request for pid %lu user ?: no request line arrived within %d seconds",
             (unsigned long)cpid, SL_REQUEST_MS / 1000);
      return;
    }
    got += n;
    line[got] = '\0';
    if ((nl = memchr(line, '\n', got)) != NULL)
      break;
  }

  /* 2 to 4. */
  if (sl_client(h, &s, sid, &logon, &word, why, sizeof(why)) != 0) {
    sl_refuse(h, ev, &s, word, why);
    goto out;
  }
  /* 1 and 5. */
  if ((nl == NULL) || ((DWORD)(nl - line) + 1 != got) || (strlen(line) != got)) {
    sl_refuse(h, ev, &s, "bad-request", "the request is not one line, or more was sent before the answer");
    goto out;
  }
  *nl = '\0';
  if (sdsyslocal_parse(line, &cols, &rows, term, sizeof(term)) != 0) {
    sl_refuse(h, ev, &s, "bad-request", "the request line is not one this service takes");
    goto out;
  }
  /* 6. Every question about P, asked of the operating system by this process. */
  if (sdl_ssh_evidence((unsigned long)s.asker_pid, name, sizeof(name), sidtext, sizeof(sidtext), &word) != 0) {
    sl_refuse(h, ev, &s, word, "sdl_ssh_evidence");
    goto out;
  }
  /* 7. The user it names is the pipe client's, and P is still there (held open since step 2). */
  if (!ConvertSidToStringSidA((PSID)sid, &mine) || (strcmp(mine, sidtext) != 0)) {
    if (mine != NULL)
      LocalFree(mine);
    sl_refuse(h, ev, &s, "other-session", "the evidence names another user than the pipe's client");
    goto out;
  }
  LocalFree(mine);
  if (!GetExitCodeProcess(s.asker, &code) || (code != STILL_ACTIVE)) {
    sl_refuse(h, ev, &s, "no-session", "the asking process has ended");
    goto out;
  }

  /* Every check has passed: start it. */
  if (!sl_start(&s, cols, rows, term, &word, why, sizeof(why))) {
    sl_refuse(h, ev, &s, word, why);
    goto out;
  }
  if (!sl_answer(h, ev, "%s%lu", SDASK_STARTED, (unsigned long)s.pid)) {
    sl_log("sdsys local: not started for pid %lu user %s: the asker went before it was told; the suspended SDSYS process pid %lu "
           "is ended", (unsigned long)s.asker_pid, s.who, (unsigned long)s.pid);
    goto out;
  }
  if (!sl_go(&s, why, sizeof(why))) {
    sl_log("sdsys local: not started for pid %lu user %s: %s", (unsigned long)s.asker_pid, s.who, why);
    goto out;
  }
  sl_log("sdsys local: started the SDSYS session pid %lu for pid %lu user %s (%s), %dx%d %s", (unsigned long)s.pid,
         (unsigned long)s.asker_pid, s.who, name, cols, rows, term);
  sl_relay(&s);

out:
  sl_end(&s);
}

static DWORD WINAPI sl_thread(LPVOID arg) {
  int slot = (int)(INT_PTR)arg;
  HANDLE h = sl_pipes[slot];
  HANDLE ev;
  HANDLE waits[2];
  OVERLAPPED ov;
  DWORD n;
  DWORD w;
  BOOL connected;

  if ((ev = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL)
    return 1;
  waits[0] = ev;
  waits[1] = sl_stop_event;

  while (WaitForSingleObject(sl_stop_event, 0) != WAIT_OBJECT_0) {
    ZeroMemory(&ov, sizeof(ov));
    ov.hEvent = ev;
    ResetEvent(ev);
    connected = ConnectNamedPipe(h, &ov);
    if (!connected) {
      switch (GetLastError()) {
        case ERROR_PIPE_CONNECTED:
          connected = TRUE;
          break;
        case ERROR_IO_PENDING:
          w = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
          if (w == WAIT_OBJECT_0) {
            connected = GetOverlappedResult(h, &ov, &n, FALSE);
          } else {
            CancelIoEx(h, &ov);
            (void)GetOverlappedResult(h, &ov, &n, TRUE);
          }
          break;
        case ERROR_NO_DATA:
          break;
        default:
          Sleep(100);
          break;
      }
    }
    if (connected && (WaitForSingleObject(sl_stop_event, 0) != WAIT_OBJECT_0))
      sl_serve_one(h, ev);
    DisconnectNamedPipe(h);
  }
  CloseHandle(ev);
  return 0;
}

/* ======================================================================
   Starting and stopping                                                    */

static void sl_release(void) {
  int i;

  for (i = 0; i < SL_INSTANCES; i++) {
    if ((sl_pipes[i] != NULL) && (sl_pipes[i] != INVALID_HANDLE_VALUE))
      CloseHandle(sl_pipes[i]);
    sl_pipes[i] = NULL;
  }
  if (sl_stop_event != NULL)
    CloseHandle(sl_stop_event);
  sl_stop_event = NULL;
  if (sl_pipe_sd != NULL)
    LocalFree(sl_pipe_sd);
  if (sl_pipe_acl != NULL)
    LocalFree(sl_pipe_acl);
  sl_pipe_sd = NULL;
  sl_pipe_acl = NULL;
}

static BOOL sl_sids(void) {
  HANDLE tok;
  BYTE buf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  char dom[256];
  DWORD n;
  DWORD dl = sizeof(dom);
  SID_NAME_USE use;
  BOOL ok;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
    return FALSE;
  ok = GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &n) &&
       CopySid(sizeof(sl_own_sid), (PSID)sl_own_sid, ((TOKEN_USER*)buf)->User.Sid);
  CloseHandle(tok);
  if (!ok)
    return FALSE;
  n = sizeof(sl_users_sid);
  return LookupAccountNameA(NULL, SL_USERS_GROUP, (PSID)sl_users_sid, &n, dom, &dl, &use);
}

int sdsyslocal_start(const char* pipe_name, const char* sd_exe, sdsyslocal_log_fn log) {
  EXPLICIT_ACCESSA ea[2];
  SECURITY_ATTRIBUTES sa;
  int i;

  sl_log = (log != NULL) ? log : sl_nolog;
  if (sl_running)
    return 0;
  if ((pipe_name == NULL) || (sd_exe == NULL) || (strlen(pipe_name) >= sizeof(sl_pipe_name)) ||
      (strlen(sd_exe) >= sizeof(sl_sd_exe))) {
    sl_log("sdsys local: not started - no pipe name or sd.exe");
    return -1;
  }
  strcpy(sl_pipe_name, pipe_name);
  strcpy(sl_sd_exe, sd_exe);
  ZeroMemory(sl_pipes, sizeof(sl_pipes));
  sl_nthreads = 0;

  if (!sl_sids()) {
    sl_log("sdsys local: not started - this process's SID or the group %s could not be read", SL_USERS_GROUP);
    sl_release();
    return -1;
  }

  /* The pipe: this process's own user all (LocalSystem - and the only one that may make another instance of the name), SD's
     users read and write.  Nobody else is in it. */
  ZeroMemory(ea, sizeof(ea));
  ea[0].grfAccessPermissions = FILE_ALL_ACCESS;
  ea[0].Trustee.ptstrName = (LPSTR)sl_own_sid;
  ea[1].grfAccessPermissions = SL_PIPE_GRANT;
  ea[1].Trustee.ptstrName = (LPSTR)sl_users_sid;
  for (i = 0; i < 2; i++) {
    ea[i].grfAccessMode = SET_ACCESS;
    ea[i].grfInheritance = NO_INHERITANCE;
    ea[i].Trustee.TrusteeForm = TRUSTEE_IS_SID;
    ea[i].Trustee.TrusteeType = TRUSTEE_IS_UNKNOWN;
  }
  sl_pipe_sd = LocalAlloc(LPTR, SECURITY_DESCRIPTOR_MIN_LENGTH);
  if ((SetEntriesInAclA(2, ea, NULL, &sl_pipe_acl) != ERROR_SUCCESS) || (sl_pipe_sd == NULL) ||
      !InitializeSecurityDescriptor(sl_pipe_sd, SECURITY_DESCRIPTOR_REVISION) ||
      !SetSecurityDescriptorDacl(sl_pipe_sd, TRUE, sl_pipe_acl, FALSE) ||
      !SetSecurityDescriptorControl(sl_pipe_sd, SE_DACL_PROTECTED, SE_DACL_PROTECTED) ||
      !SetSecurityDescriptorOwner(sl_pipe_sd, (PSID)sl_own_sid, FALSE)) {
    sl_log("sdsys local: not started - the pipe's security descriptor could not be built (error %lu)",
           (unsigned long)GetLastError());
    sl_release();
    return -1;
  }
  if ((sl_stop_event = CreateEventA(NULL, TRUE, FALSE, NULL)) == NULL) {
    sl_release();
    return -1;
  }
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sl_pipe_sd;
  sa.bInheritHandle = FALSE;
  for (i = 0; i < SL_INSTANCES; i++) {
    sl_pipes[i] = CreateNamedPipeA(sl_pipe_name,
                                   PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | ((i == 0) ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0),
                                   PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, SL_INSTANCES,
                                   65536, 65536, 0, &sa);
    if (sl_pipes[i] == INVALID_HANDLE_VALUE) {
      sl_log("sdsys local: not started - %s could not be made (error %lu%s)", sl_pipe_name, (unsigned long)GetLastError(),
             (i == 0) ? "; another process may hold the name" : "");
      sl_pipes[i] = NULL;
      sl_release();
      return -1;
    }
  }
  for (i = 0; i < SL_INSTANCES; i++) {
    sl_threads[i] = CreateThread(NULL, 0, sl_thread, (LPVOID)(INT_PTR)i, 0, NULL);
    if (sl_threads[i] == NULL)
      break;
    sl_nthreads++;
  }
  if (sl_nthreads == 0) {
    sl_release();
    return -1;
  }
  sl_running = TRUE;
  sl_log("sdsys local: serving %s with %d instance(s); the SDSYS process is %s -SDSYSLOCAL <pid>", sl_pipe_name, sl_nthreads,
         sl_sd_exe);
  return 0;
}

void sdsyslocal_stop(void) {
  int i;

  if (!sl_running)
    return;
  SetEvent(sl_stop_event);
  if (WaitForMultipleObjects((DWORD)sl_nthreads, sl_threads, TRUE, SL_STOP_MS) == WAIT_TIMEOUT)
    sl_log("sdsys local: a serving thread did not end in %d seconds", SL_STOP_MS / 1000);
  for (i = 0; i < sl_nthreads; i++)
    CloseHandle(sl_threads[i]);
  sl_nthreads = 0;
  sl_running = FALSE;
  sl_release();
  sl_log("sdsys local: stopped");
}

/* END-CODE */
