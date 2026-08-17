/* probe_child.c - MSYS2/Cygwin side of the step 11 transport probe.
 *
 * Answers one question: does select() tell the truth about a pipe descriptor
 * that CYGWIN ITSELF set up from an inherited standard handle, where it
 * demonstrably lies about one injected with cygwin_attach_handle_to_fd()?
 *
 * It measures BOTH in the same run, so the known-bad case is the control.  A
 * descriptor that reports "not ready" on an empty pipe and "ready" once data
 * arrives is answering honestly; one that reports "ready" both times is the
 * always-ready behaviour that stops SDConnectLocal today.
 *
 * Results go to a FILE, not stdout - stdout is the pipe under test.
 *
 * Build:  /c/msys64/usr/bin/gcc -Wall -o probe_child.exe probe_child.c
 */

#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <sys/select.h>
#include <sys/time.h>
#include <windows.h>

extern int cygwin_attach_handle_to_fd(char *name, int fd, HANDLE handle,
                                      mode_t bin, DWORD myaccess);

/* 200ms is long enough that a slow-but-honest select is not mistaken for a
   not-ready answer, and short enough that four of them are unnoticeable. */
static int ready(int fd) {
  fd_set r;
  struct timeval tv;
  int n;

  FD_ZERO(&r);
  FD_SET(fd, &r);
  tv.tv_sec = 0;
  tv.tv_usec = 200000;
  n = select(fd + 1, &r, NULL, NULL, &tv);
  return (n > 0 && FD_ISSET(fd, &r));
}

int main(int argc, char **argv) {
  FILE *log;
  HANDLE h;
  int afd = -1;
  int inherited_empty, inherited_data;
  int attached_empty = -1, attached_data = -1;

  if (argc < 3) return 90;                 /* argv[1] pipe name, argv[2] log */

  log = fopen(argv[2], "w");
  if (log == NULL) return 91;

  /* --- phase 1: the two descriptors with NOTHING written to either --- */

  inherited_empty = ready(0);              /* fd 0 = inherited standard handle */

  h = CreateFileA(argv[1], GENERIC_READ | GENERIC_WRITE, 0, NULL,
                  OPEN_EXISTING, 0, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    fprintf(log, "child: CreateFile on %s failed, %lu\n", argv[1],
            (unsigned long)GetLastError());
  } else {
    /* The access argument MUST match the handle - gplsrc/win32pipe.c and
       PROJECT_STATUS.md 7 step 11.  Passing GENERIC_READ here succeeds and
       then fails read() with EBADF. */
    afd = cygwin_attach_handle_to_fd(argv[1], -1, h, 1,
                                     GENERIC_READ | GENERIC_WRITE);
    if (afd < 0) fprintf(log, "child: attach failed\n");
    else         attached_empty = ready(afd);
  }

  /* --- let the parent put a byte into each --- */
  sleep(3);

  /* --- phase 2: the same two descriptors with data waiting --- */

  inherited_data = ready(0);
  if (afd >= 0) attached_data = ready(afd);

  fprintf(log, "inherited(fd 0)  empty=%d  data=%d\n",
          inherited_empty, inherited_data);
  fprintf(log, "attached(fd %d)  empty=%d  data=%d\n",
          afd, attached_empty, attached_data);

  /* Prove the honest one is not merely honest but usable. */
  if (inherited_data) {
    char buf[64];
    ssize_t n = read(0, buf, sizeof(buf) - 1);
    if (n > 0) { buf[n] = '\0'; fprintf(log, "inherited read: [%s]\n", buf); }
    else       { fprintf(log, "inherited read returned %d\n", (int)n); }
  }

  fclose(log);
  return 0;
}
