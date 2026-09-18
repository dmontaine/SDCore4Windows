/* probe-groupmember.c - drive win32_group_has_member() from the command line.
 *
 * 17 Sep 26 Windows port, RELEASE_1.1 55.  The C behind K$GROUP.MEMBER
 * answers THREE ways - member, not a member, could not tell - and the whole
 * fix depends on the third never collapsing into the second (a lookup that
 * failed read as "not granted" is what cost seven runs).  Nothing in the tree
 * exercises that C except an authenticated API session on a cycled install,
 * so test-groupmember-units.py builds this driver against the live
 * gplsrc/win32group.c and asks it real questions about real groups.
 *
 * Launched:  probe-groupmember.exe <user> <group>
 *            a single "-" for either argument means the empty string, which
 *            is the refusal row and cannot be typed on every shell.
 *
 * Prints ONE line, and it carries the inputs as well as the answer, because a
 * result that does not say what was asked is not a measurement:
 *
 *   user=<u> group=<g> told=<0|1> member=<0|1> why=<reason or ->
 *
 * told is the function's return value: 1 the question was answered and member
 * is the answer, 0 it could not be answered and member MUST NOT be read.  It
 * prints member on the told=0 line anyway, so the guard can check the
 * documented "set to 0 before the guards" promise rather than assume it.
 *
 * Exit 0 whenever the line was printed.  This is an instrument, not a check:
 * the verdicts are the guard's.
 */

#include <stdio.h>
#include <string.h>

#include "win32group.h"

int main(int argc, char** argv) {
  const char* user;
  const char* group;
  char why[512];
  int member = -99;   /* a value the function must overwrite on every path */
  int told;

  if (argc != 3) {
    fprintf(stderr, "usage: probe-groupmember <user|-> <group|->\n");
    return 2;
  }
  user = (strcmp(argv[1], "-") == 0) ? "" : argv[1];
  group = (strcmp(argv[2], "-") == 0) ? "" : argv[2];
  why[0] = '\0';

  told = win32_group_has_member(user, group, &member, why, sizeof why);

  printf("user=%s group=%s told=%d member=%d why=%s\n", user, group, told,
         member, (why[0] != '\0') ? why : "-");
  return 0;
}

/* END-CODE */
