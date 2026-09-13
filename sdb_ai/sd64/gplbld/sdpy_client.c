/* sdpy_client.c - SD's side of the Python helper pipe.  PROJECT_STATUS.md 5.27.
 *
 * ***THIS FILE IS COMPILED INTO sd.exe, SO IT IS MSYS2 CODE.***  sdpy.exe is
 * NATIVE (UCRT64, linked against python.org's python3.dll).  Section 5.3 says
 * the two runtimes never meet in one process - and they do not meet here
 * either: nothing of Python appears in this file, no Python header is
 * included, and the only thing crossing the boundary is BYTES ON A PIPE.
 *
 * ***THAT IS THE CLAIM THE HELPER SHAPE RESTS ON AND IT IS THE ONE THIS FILE
 * EXISTS TO TEST.***  The ruling says the runtimes must not share a process;
 * it does not say they can talk, and nothing had ever demonstrated it.
 * test-sdpyclient.c is built with the MSYS2 compiler and drives the UCRT64
 * binary, which is the same crossing sd.exe will make.
 *
 * ***WIN32 PIPES RATHER THAN fork()/exec().***  MSYS2 emulates fork at
 * considerable cost and with its own failure modes, and the child is a native
 * program that knows nothing about the emulation.  CreateProcess hands it
 * exactly two handles and nothing else to misunderstand.
 *
 * The protocol is sdpy.c's:
 *   request    VERB n1 n2 n3 \n  then n1+n2+n3 raw bytes
 *   response   status n \n       then n raw bytes
 */

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sdpy_client.h"

struct SDPY {
  HANDLE proc;
  HANDLE to_child;    /* we write requests here */
  HANDLE from_child;  /* we read responses here */
  char*  buf;         /* response payload, reused */
  size_t cap;
};

static void fail(char* err, size_t errlen, const char* what) {
  if (err != NULL && errlen != 0)
    (void)snprintf(err, errlen, "%s (GetLastError=%lu)", what, (unsigned long)GetLastError());
}

static int write_all(HANDLE h, const void* p, size_t n) {
  const char* q = (const char*)p;
  while (n != 0) {
    DWORD wrote = 0;
    if (!WriteFile(h, q, (DWORD)n, &wrote, NULL) || wrote == 0)
      return 0;
    q += wrote;
    n -= wrote;
  }
  return 1;
}

static int read_all(HANDLE h, void* p, size_t n) {
  char* q = (char*)p;
  while (n != 0) {
    DWORD got = 0;
    if (!ReadFile(h, q, (DWORD)n, &got, NULL) || got == 0)
      return 0;
    q += got;
    n -= got;
  }
  return 1;
}

/* The response header is short and ends at '\n'.  Read it a byte at a time:
 * reading ahead would swallow the front of the payload that follows it. */
static int read_header(HANDLE h, char* line, size_t cap) {
  size_t i = 0;
  while (i + 1 < cap) {
    char c;
    DWORD got = 0;
    if (!ReadFile(h, &c, 1, &got, NULL) || got == 0)
      return 0;
    if (c == '\n') { line[i] = '\0'; return 1; }
    line[i++] = c;
  }
  return 0;
}

SDPY* sdpy_start(const char* exe, char* err, size_t errlen) {
  SDPY* s;
  SECURITY_ATTRIBUTES sa;
  HANDLE child_in = NULL, child_out = NULL;
  HANDLE our_write = NULL, our_read = NULL;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  char* cmd;
  int status = 0;
  char* payload = NULL;
  size_t plen = 0;

  if (err != NULL && errlen != 0) err[0] = '\0';

  s = (SDPY*)calloc(1, sizeof(SDPY));
  if (s == NULL) { fail(err, errlen, "out of memory"); return NULL; }

  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;
  sa.lpSecurityDescriptor = NULL;

  if (!CreatePipe(&child_in, &our_write, &sa, 0)) {
    fail(err, errlen, "CreatePipe for the child's stdin failed");
    free(s); return NULL;
  }
  if (!CreatePipe(&our_read, &child_out, &sa, 0)) {
    fail(err, errlen, "CreatePipe for the child's stdout failed");
    CloseHandle(child_in); CloseHandle(our_write); free(s); return NULL;
  }
  /* OUR ends must not be inherited, or the child holds a copy of the write end
   * of its own output pipe and a read never sees EOF when it dies. */
  SetHandleInformation(our_write, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(our_read, HANDLE_FLAG_INHERIT, 0);

  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  si.hStdInput = child_in;
  si.hStdOutput = child_out;
  si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

  /* CreateProcess may modify the command line, so it gets a writable copy. */
  cmd = (char*)malloc(strlen(exe) + 3);
  if (cmd == NULL) {
    fail(err, errlen, "out of memory");
    CloseHandle(child_in); CloseHandle(child_out);
    CloseHandle(our_write); CloseHandle(our_read); free(s); return NULL;
  }
  (void)sprintf(cmd, "\"%s\"", exe);

  if (!CreateProcessA(exe, cmd, NULL, NULL, TRUE, CREATE_NO_WINDOW,
                      NULL, NULL, &si, &pi)) {
    fail(err, errlen, "CreateProcess could not start the helper");
    free(cmd);
    CloseHandle(child_in); CloseHandle(child_out);
    CloseHandle(our_write); CloseHandle(our_read); free(s); return NULL;
  }
  free(cmd);
  CloseHandle(pi.hThread);
  /* The child has its own copies now; ours would otherwise hold the pipe
   * open after it exits. */
  CloseHandle(child_in);
  CloseHandle(child_out);

  s->proc = pi.hProcess;
  s->to_child = our_write;
  s->from_child = our_read;

  /* ***THE HANDSHAKE IS PART OF STARTING, NOT AN OPTIONAL FIRST CALL.***  A
   * helper that does not agree on the protocol is not a helper we have. */
  if (sdpy_call(s, "HELLO", SDPY_PROTOCOL, strlen(SDPY_PROTOCOL),
                NULL, 0, NULL, 0, &status, &payload, &plen) != 0) {
    if (err != NULL && errlen != 0)
      (void)snprintf(err, errlen, "the helper started but did not answer HELLO");
    sdpy_stop(s);
    return NULL;
  }
  if (status != 0) {
    if (err != NULL && errlen != 0)
      (void)snprintf(err, errlen, "the helper refused HELLO: %.*s",
                     (int)plen, payload ? payload : "");
    sdpy_stop(s);
    return NULL;
  }
  return s;
}

int sdpy_call(SDPY* s, const char* verb,
              const char* a1, size_t n1,
              const char* a2, size_t n2,
              const char* a3, size_t n3,
              int* status, char** payload, size_t* plen) {
  char header[128];
  int hlen;
  long len = 0;
  int st = 0;

  if (s == NULL || verb == NULL) return -1;
  if (status != NULL) *status = 0;
  if (payload != NULL) *payload = NULL;
  if (plen != NULL) *plen = 0;

  hlen = snprintf(header, sizeof(header), "%s %zu %zu %zu\n", verb, n1, n2, n3);
  if (hlen <= 0) return -1;

  if (!write_all(s->to_child, header, (size_t)hlen)) return -1;
  if (n1 && !write_all(s->to_child, a1, n1)) return -1;
  if (n2 && !write_all(s->to_child, a2, n2)) return -1;
  if (n3 && !write_all(s->to_child, a3, n3)) return -1;

  if (!read_header(s->from_child, header, sizeof(header))) return -1;
  if (sscanf(header, "%d %ld", &st, &len) != 2) return -1;
  if (len < 0) return -1;

  if ((size_t)len + 1 > s->cap) {
    char* nb = (char*)realloc(s->buf, (size_t)len + 1);
    if (nb == NULL) return -1;
    s->buf = nb;
    s->cap = (size_t)len + 1;
  }
  if (len && !read_all(s->from_child, s->buf, (size_t)len)) return -1;
  if (s->buf != NULL) s->buf[len] = '\0';   /* convenient, never relied on */

  if (status != NULL) *status = st;
  if (payload != NULL) *payload = s->buf;
  if (plen != NULL) *plen = (size_t)len;
  return 0;
}

void sdpy_stop(SDPY* s) {
  if (s == NULL) return;
  if (s->to_child != NULL) {
    int st;
    char* p;
    size_t n;
    /* Ask first.  Closing the pipe would also end it, but QUIT lets the
     * helper finalise the interpreter rather than be torn down mid-call. */
    (void)sdpy_call(s, "QUIT", NULL, 0, NULL, 0, NULL, 0, &st, &p, &n);
    CloseHandle(s->to_child);
  }
  if (s->from_child != NULL) CloseHandle(s->from_child);
  if (s->proc != NULL) {
    if (WaitForSingleObject(s->proc, 5000) != WAIT_OBJECT_0)
      TerminateProcess(s->proc, 1);
    CloseHandle(s->proc);
  }
  free(s->buf);
  free(s);
}
