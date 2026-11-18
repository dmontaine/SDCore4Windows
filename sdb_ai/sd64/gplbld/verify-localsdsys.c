/* verify-localsdsys.c - drives win32localsdsys.c's pure parts and its file reader for test-localsdsys-units.py (RELEASE_1.1 339).
 *
 *   verify-localsdsys name <text>          -> "ok" or "bad"            (sdl_name_ok)
 *   verify-localsdsys read <path>          -> "<n> <why>" then one "name sid" a line   (sdl_read with check_acl 0: the scratch
 *                                             files are the caller's, not SYSTEM's; the owner and grants are the witness's)
 *
 * Built by the test with the UCRT64 compiler into a scratch folder, linked with gplsrc/win32localsdsys.c; never shipped.
 *
 * START-HISTORY:
 * 18 Nov 26 Windows port - written for RELEASE_1.1 339 (Linux 38cfb301's verify-localsdsys.c, the Windows reading).
 * END-HISTORY
 */

#include <stdio.h>
#include <string.h>

#include "win32localsdsys.h"

int main(int argc, char** argv) {
  if (argc == 3 && strcmp(argv[1], "name") == 0) {
    printf("%s\n", sdl_name_ok(argv[2]) ? "ok" : "bad");
    return 0;
  }
  if (argc == 3 && strcmp(argv[1], "read") == 0) {
    sdl_list l;
    const char* why = "";
    int i, n = sdl_read(argv[2], 0, &l, &why);
    printf("%d %s\n", n, why[0] ? why : "-");
    for (i = 0; n > 0 && i < l.n; i++)
      printf("%s %s\n", l.name[i], l.sid[i]);
    return 0;
  }
  fprintf(stderr, "usage: verify-localsdsys name <text> | read <path>\n");
  return 2;
}
