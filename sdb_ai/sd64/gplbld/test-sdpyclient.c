/* test-sdpyclient.c - drive sdpy.exe from MSYS2 code, which is the crossing
 * sd.exe will make.  PROJECT_STATUS.md section 5.27.
 *
 * ***THE POINT IS THE TOOLCHAIN, NOT THE VERBS.***  sdpy.c already has 53 rows
 * driving it from PowerShell.  What none of those touch is the thing section
 * 5.27 actually rests on: that an MSYS2 process can start a NATIVE child and
 * exchange bytes with it.  The ruling says the two runtimes must not share a
 * process.  It never said they could talk, and nothing had shown it.
 *
 * So this is built with /usr/bin/gcc - the compiler sd.exe is built with - and
 * it drives the UCRT64 binary.  If it passes, the shape works.
 *
 * Exit 0 every check passed, 1 a check failed, 2 could not run.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sdpy_client.h"

static int passed = 0;
static int failed = 0;

static void row(const char* name, int ok, const char* detail) {
  if (ok) { passed++; printf("  [PASS] %s\n", name); }
  else    { failed++; printf("  [FAIL] %s\n         %s\n", name, detail ? detail : ""); }
}

int main(int argc, char** argv) {
  SDPY* s;
  char err[512];
  int st;
  char* p;
  size_t n;
  const char* exe;
  char detail[1024];

  if (argc < 2) {
    printf("usage: test-sdpyclient <path to sdpy.exe>\n");
    return 2;
  }
  exe = argv[1];

  printf("test-sdpyclient: MSYS2 parent, native child\n");
  printf("  helper : %s\n\n", exe);

  s = sdpy_start(exe, err, sizeof(err));
  if (s == NULL) {
    printf("  [FAIL] the helper started and answered HELLO\n         %s\n", err);
    printf("\ntest-sdpyclient: 0 passed, 1 failed\n");
    return 1;
  }
  row("an MSYS2 process starts the native helper and HELLO agrees", 1, NULL);

  if (sdpy_call(s, "PING", NULL, 0, NULL, 0, NULL, 0, &st, &p, &n) != 0) {
    row("PING crosses the runtime boundary", 0, "transport failed");
  } else {
    (void)snprintf(detail, sizeof(detail), "status %d, payload '%.*s'", st, (int)n, p);
    row("PING crosses the runtime boundary", st == 0 && n == 4 && memcmp(p, "PONG", 4) == 0, detail);
  }

  if (sdpy_call(s, "INIT", NULL, 0, NULL, 0, NULL, 0, &st, &p, &n) != 0) {
    row("INIT starts an interpreter in the child", 0, "transport failed");
  } else {
    (void)snprintf(detail, sizeof(detail), "status %d", st);
    row("INIT starts an interpreter in the child", st == 0 && n > 0, detail);
    printf("         python: %.*s\n", (int)(n > 60 ? 60 : n), p);
  }

  if (sdpy_call(s, "RUNSTR", "print('from msys2')", 19, NULL, 0, NULL, 0,
                &st, &p, &n) != 0) {
    row("a script runs and its output comes back", 0, "transport failed");
  } else {
    (void)snprintf(detail, sizeof(detail), "status %d, '%.*s'", st, (int)n, p);
    row("a script runs and its output comes back",
        st == 0 && n > 0 && strstr(p, "from msys2") != NULL, detail);
  }

  /* ***THE ROW THAT MATTERS MOST.***  An SD string is bytes: @fm is 0xFE, and
   * a value can contain NUL.  If anything on either side of this pipe treats a
   * payload as a C string, this is where it shows. */
  {
    static const char marky[] = { 'a', (char)0xFE, 'b', (char)0xFD, 'c',
                                  (char)0xFC, 'd', '\0', 'e', '\n', 'f' };
    const size_t mlen = sizeof(marky);
    int ok;

    if (sdpy_call(s, "STRSET", marky, mlen, NULL, 0, "marks", 5,
                  &st, &p, &n) != 0 || st != 0) {
      row("a value with marks and a NUL is accepted across the boundary", 0,
          "STRSET failed");
    } else {
      row("a value with marks and a NUL is accepted across the boundary", 1, NULL);
    }

    if (sdpy_call(s, "STRGET", NULL, 0, NULL, 0, "marks", 5, &st, &p, &n) != 0) {
      row("and it round-trips BYTE FOR BYTE", 0, "transport failed");
    } else {
      ok = (st == 0 && n == mlen && memcmp(p, marky, mlen) == 0);
      (void)snprintf(detail, sizeof(detail),
                     "status %d, sent %zu bytes, got %zu", st, mlen, n);
      row("and it round-trips BYTE FOR BYTE", ok, detail);
    }
  }

  /* A failing script must come back as a traceback, not as a dead pipe. */
  if (sdpy_call(s, "RUNSTR", "raise ValueError('x')", 21, NULL, 0, NULL, 0,
                &st, &p, &n) != 0) {
    row("a raising script returns a traceback, not a broken pipe", 0, "transport failed");
  } else {
    (void)snprintf(detail, sizeof(detail), "status %d, '%.*s'", st, (int)n, p);
    row("a raising script returns a traceback, not a broken pipe",
        st == -12004 && strstr(p, "ValueError") != NULL, detail);
  }

  /* ...and the stream is still usable afterwards. */
  if (sdpy_call(s, "PING", NULL, 0, NULL, 0, NULL, 0, &st, &p, &n) != 0) {
    row("the pipe is still in step after a failure", 0, "transport failed");
  } else {
    (void)snprintf(detail, sizeof(detail), "status %d, '%.*s'", st, (int)n, p);
    row("the pipe is still in step after a failure",
        st == 0 && n == 4 && memcmp(p, "PONG", 4) == 0, detail);
  }

  sdpy_stop(s);
  row("sdpy_stop() shuts the helper down without hanging", 1, NULL);

  printf("\ntest-sdpyclient: %d passed, %d failed\n", passed, failed);
  return failed ? 1 : 0;
}
