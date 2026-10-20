/* sdsamepath.h - are two paths the same file on NTFS?  For the open-file test of sdidx and sdfix.
 *
 * START-HISTORY:
 * 19 Oct 26 Windows port - written for RELEASE_1.1 159.  The tools asked "is this file open in SD" with strcasecmp() of
 *           the path they were given against the path in SD's table of open files.  That fails where the two spell the
 *           SAME file in two POSIX forms.  The MSYS runtime turns a Windows path into a POSIX one by matching its
 *           mounts, and it matches the ROOT prefix case-sensitively: SD Core Solo keeps its accounts inside the root
 *           (<home>), the daemon records /user_accounts/sduser/voc, and a path typed C:\USERS\DON\SDCORESOLO\... came
 *           back as /cygdrive/c/USERS/DON/SDCORESOLO/..., which no case-folding of the other string can equal (measured
 *           with a probe in a root laid out like Solo's; the Solo verify showed sdidx -q and -d and sdfix -F running on a
 *           file a session held open).  Both sides are therefore turned into the Windows spelling and compared there,
 *           ignoring case.  Table entries that already begin with a drive letter (C:/.../sdsys/$ipc) are used as they are.
 * END-HISTORY
 */

#ifndef SDSAMEPATH_H
#define SDSAMEPATH_H

#include <ctype.h>
#include <limits.h>
#include <string.h>
#include <strings.h>
#include <sys/cygwin.h>

/* The path as Windows spells it: backslashes, drive letter first.  0 if it cannot be converted. */

static int sd_win_form(const char *p, char *out, size_t size) {
  char *q;

  if (isalpha((unsigned char)p[0]) && (p[1] == ':')) {
    if (strlen(p) >= size)
      return 0;
    strcpy(out, p);
  } else if (cygwin_conv_path(CCP_POSIX_TO_WIN_A, p, out, size) != 0) {
    return 0;
  }
  for (q = out; *q != '\0'; q++) {
    if (*q == '/')
      *q = '\\';
  }
  return 1;
}

/* 1 if A and B name the same file, ignoring case; the two spellings are compared first as given and then as Windows spells them */

static int sd_same_file_path(const char *a, const char *b) {
  char wa[PATH_MAX + 1];
  char wb[PATH_MAX + 1];

  if (strcasecmp(a, b) == 0)
    return 1;
  if (!sd_win_form(a, wa, sizeof(wa)) || !sd_win_form(b, wb, sizeof(wb)))
    return 0;
  return (strcasecmp(wa, wb) == 0);
}

#endif
