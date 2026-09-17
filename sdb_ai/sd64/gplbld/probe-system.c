/* probe-system.c - RELEASE_1.1 37: can the SD runtime's system() run anything
 * on the INSTALLED tree, where sdwind.c:300 uses it to start "sd -cleanup"?
 *
 * 17 Sep 26 Windows port.  Cygwin's system() is "/bin/sh -c <cmd>".  The
 * install ships sd.exe and sdwind.exe in usr\bin and NO sh.exe (measured: the
 * directory listing has neither sh nor bash), so unless /bin/sh resolves to
 * something, every system() in sdwind fails - and sdwind.c:300 does not test
 * its return, so "the daemon found a lost user and ran cleanup" and "the
 * daemon found a lost user and ran nothing" print the same nothing.
 *
 * Prints, under the runtime it loaded (must be SD's, as probe-killzero.c):
 *   where /bin/sh and /usr/bin/sh resolve to and whether they exist
 *   system("echo alive") - rc, errno, and whether "alive" appeared
 *   system("'<dir>/sd' -help") in sdwind's exact quoting shape - rc, errno
 *
 * Build from gplbld in MSYS2's MSYS bash:
 *   gcc -O2 -Wall -o probe-system.exe probe-system.c
 * Run with C:\Program Files\SD\usr\bin first on PATH.
 * Exit 0 printed; 2 wrong runtime.
 */
#include <windows.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/cygwin.h>
#include <sys/wait.h>

static void where(const char* posix) {
  char win[MAX_PATH] = "?";
  cygwin_conv_path(CCP_POSIX_TO_WIN_A, posix, win, sizeof win);
  printf("  %-12s -> %s  %s\n", posix, win, access(posix, X_OK) == 0 ? "EXISTS, executable" : "ABSENT");
}

static void try_system(const char* cmd) {
  int rc;
  errno = 0;
  printf("  system(%s)\n", cmd);
  fflush(stdout);
  rc = system(cmd);
  printf("    rc %d (0x%x) errno %d%s\n", rc, rc, errno,
         rc == -1 ? " = could not start a shell at all" :
         (WIFEXITED(rc) && WEXITSTATUS(rc) == 127) ? " = shell exit 127: command or shell not found" : "");
}

int main(int argc, char** argv) {
  char dll[MAX_PATH] = "?", dir[MAX_PATH], cmd[MAX_PATH + 40];
  HMODULE m = GetModuleHandleA("msys-2.0.dll");
  char* slash;
  (void)argc; (void)argv;
  if (m) GetModuleFileNameA(m, dll, sizeof dll);
  printf("probe-system\n  runtime   : %s\n", dll);
  if (strstr(dll, "\\SD\\usr\\bin\\") == NULL) {
    printf("REFUSED: not SD's runtime - put C:\\Program Files\\SD\\usr\\bin first on PATH.\n");
    return 2;
  }
  where("/bin/sh");
  where("/usr/bin/sh");
  where("/bin/sd");
  where("/usr/bin/sd");
  try_system("echo alive");
  /* sdwind.c:300's own shape: the exe directory, single-quoted, then -cleanup.
     -help is used here so that nothing is cleaned by a probe. */
  strcpy(dir, dll);
  slash = strrchr(dir, '\\');
  if (slash) *slash = '\0';
  {
    char posix[MAX_PATH];
    cygwin_conv_path(CCP_WIN_A_TO_POSIX, dir, posix, sizeof posix);
    snprintf(cmd, sizeof cmd, "'%s/sd' -help", posix);
  }
  try_system(cmd);
  return 0;
}
