/* local_sdsys_probe.c - the ADMIT side of SDSYS's local route.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 * START-HISTORY:
 * 22 Sep 26 Windows port - written.  RELEASE_1.1 101.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * ***THIS IS THE MIRROR OF local_connect_test.c AND THE TWO ARE A PAIR.***
 * That one proves SDSYS is REFUSED to a caller who is not SDSYS, unelevated.
 * This one proves SDSYS is ADMITTED to a caller who IS SDSYS, elevated - the
 * only claim in RELEASE_1.1 101 that nothing else measures.  Neither is worth
 * much alone: a route that admits everybody passes the first test's treatment
 * and this one outright, and a route that admits nobody passes the first test's
 * control.  Run both.
 *
 * WHAT IT ASSERTS, IN ORDER, AND EACH STEP IS A DIFFERENT CLAIM:
 *
 *   1  SDConnectLocal("SDSYS") is ADMITTED.  That is local.session AND the
 *      process owner being SDSYS AND kernel(K$ADMINISTRATOR,-1), all three,
 *      in APISRVR's vb.account.
 *   2  WHO names SDSYS.  Admission alone does not prove WHICH account was
 *      entered - vb.account has a revert.to.old.account path that leaves a
 *      session open somewhere else - so the account is read back rather than
 *      assumed.
 *   3  An ADMINISTRATOR-ONLY VERB SUCCEEDS.  This is the one that separates
 *      "entered the account" from "holds the administrator flag", and they are
 *      NOT the same claim: the flag is seeded by kernel.c from IsElevated()
 *      AND connection_type # CN_SOCKET AND IsInteractive(), and whether
 *      IsInteractive() answers true for a ConnectLocal CHILD is exactly what
 *      this probe exists to find out.  If it is false the session still enters
 *      SDSYS and step 3 fails on its own.
 *
 * ***THE VERB IS "MODIFY.ACCOUNT" WITH NO ARGUMENTS, AND THAT IS A DELIBERATE
 * CHOICE RATHER THAN A CONVENIENT ONE.***  MODIFYA's FIRST statement is the
 * K$ADMINISTRATOR test - it stops with sysmsg(2001), "Command requires
 * administrator privileges" - and with no account name the very next thing it
 * does is print its syntax block and stop.  So the two outcomes are one line
 * apart, distinguishable in the output, and NOTHING IS CHANGED either way: no
 * account is read, no group is touched, no record is written.  A verb that
 * needed an argument would have to name a real account to get past the parser.
 *
 * ***AND IT IS ANCHORED ON THE SUCCESS WORDING, NOT ON THE ABSENCE OF THE
 * FAILURE ONE.***  PROJECT_STATUS.md 0: a pattern the failure path also carries
 * is not a check.  "Command Syntax" appears only when MODIFYA got past the
 * privilege test; 2001's text appears only when it did not; both are tested,
 * and a reply carrying NEITHER is a third outcome and is refused as such,
 * because that means the verb did not run at all.
 *
 * ***IT REFUSES TO RUN AS THE WRONG PRINCIPAL, OUT LOUD.***  A pass from an
 * unelevated session, or from a session that is not SDSYS's, would be measuring
 * a different route and is the vacuous pass the instrument rules forbid.  This
 * binary cannot read its own token portably here, so the CALLER states who it
 * is and the wrapper (gplbld/verify-sdsyslocal.ps1) is what actually checks -
 * see its header.  What this does is echo what it was told, so a transcript
 * always says which principal the verdict belongs to.
 *
 * Exit codes, distinct so a shell can tell the outcomes apart and so "refused"
 * can never read as a pass:
 *   0  admitted, WHO named SDSYS, and the administrator verb ran
 *   1  SDSYS was REFUSED - the route did not admit an elevated SDSYS caller
 *   2  admitted, but WHO named some OTHER account
 *   3  the session opened but a command returned nothing
 *   4  admitted and in SDSYS, but the administrator verb was REFUSED (2001) -
 *      the flag is absent, which is IsInteractive() answering false for a
 *      ConnectLocal child, and is the interesting failure
 *   5  the administrator verb replied something this probe cannot classify
 *   6  no principal was named on the command line
 * END-DESCRIPTION
 */

#include <stdio.h>
#include <string.h>
#include "sdclilib.h"

/* Case-insensitive substring search.  strcasestr() is not in C11 and MSYS2's
   headers hide it under _GNU_SOURCE, so it is written out rather than having
   the build depend on which feature macros happen to be set. */
static int contains_nocase(const char* haystack, const char* needle) {
  size_t nlen;
  size_t i;

  if ((haystack == NULL) || (needle == NULL))
    return 0;

  nlen = strlen(needle);
  if (nlen == 0)
    return 1;

  for (i = 0; haystack[i] != '\0'; i++) {
    size_t j = 0;

    while ((needle[j] != '\0') && (haystack[i + j] != '\0')) {
      char a = haystack[i + j];
      char b = needle[j];

      if ((a >= 'a') && (a <= 'z')) a = (char)(a - 'a' + 'A');
      if ((b >= 'a') && (b <= 'z')) b = (char)(b - 'a' + 'A');
      if (a != b)
        break;
      j++;
    }

    if (needle[j] == '\0')
      return 1;
  }

  return 0;
}

int main(int argc, char** argv) {
  int err;
  char* value;
  int saw_syntax;
  int saw_refusal;

  /* REFUSE THE NULL CASE OUT LOUD - CLAUDE.md's instrument rule.  With no
     principal named, a transcript would not say whose session produced the
     verdict, and this probe's whole meaning is "an ELEVATED SDSYS caller". */

  if (argc != 2) {
    printf("usage: %s <principal>\n\n", argv[0]);
    printf("  <principal> is who this is running as, for the transcript -\n");
    printf("  normally the output of \"whoami\".  It is ECHOED, not trusted:\n");
    printf("  gplbld/verify-sdsyslocal.ps1 is what checks that the caller is\n");
    printf("  the Windows SDSYS account and that the session is elevated.\n\n");
    printf("  Run it there rather than by hand.\n");
    return 6;
  }

  printf("local_sdsys_probe: the ADMIT side of SDSYS's local route\n");
  printf("  principal (as stated by the caller) : %s\n", argv[1]);
  printf("  transport                           : SDConnectLocal - pipes and a child sd.exe, no socket\n");
  printf("  account                             : SDSYS\n\n");

  /* --- 1: admission ---------------------------------------------------- */

  printf("connecting to SDSYS (this MUST be admitted) ...\n");

  if (!SDConnectLocal("SDSYS")) {
    printf("  REFUSED: %s\n", SDError());
    printf("\nFAIL: SDSYS was refused over SDConnectLocal.\n");
    printf("APISRVR's vb.account wants all three of: the session arrived by\n");
    printf("request 25, the process owner is the Windows SDSYS account, and\n");
    printf("kernel(K$ADMINISTRATOR,-1).  sdsys/audit names which one failed -\n");
    printf("look for \"branch=4 sdsys.not.local.elevated\".\n");
    return 1;
  }

  printf("  admitted\n");

  /* --- 2: which account? ----------------------------------------------- */

  value = SDExecute("WHO", &err);
  if (value == NULL) {
    printf("  WHO returned nothing, err %d: %s\n", err, SDError());
    SDDisconnectAll();
    return 3;
  }

  printf("  WHO -> %s", value);
  if ((value[0] != '\0') && (value[strlen(value) - 1] != '\n'))
    printf("\n");

  if (!contains_nocase(value, "SDSYS")) {
    printf("\nFAIL: admitted, but WHO does not name SDSYS.\n");
    printf("vb.account has a revert.to.old.account path that leaves the session\n");
    printf("open in the account it started in, so \"connected\" is not \"in SDSYS\".\n");
    SDFree(value);
    SDDisconnectAll();
    return 2;
  }

  SDFree(value);

  /* --- 3: is this session an ADMINISTRATOR? ----------------------------- */

  printf("\nrunning an administrator-only verb (MODIFY.ACCOUNT, no arguments) ...\n");

  value = SDExecute("MODIFY.ACCOUNT", &err);
  if (value == NULL) {
    printf("  MODIFY.ACCOUNT returned nothing, err %d: %s\n", err, SDError());
    SDDisconnectAll();
    return 3;
  }

  printf("  --- it said ---\n%s", value);
  if ((value[0] != '\0') && (value[strlen(value) - 1] != '\n'))
    printf("\n");
  printf("  --- end ---\n");

  /* BOTH WORDINGS ARE TESTED, and a reply carrying neither is its own
     outcome.  Matching only the success text would report a pass for an empty
     reply; matching only the failure text would report a pass for anything
     unexpected.  PROJECT_STATUS.md 0. */

  saw_syntax  = contains_nocase(value, "Command Syntax");
  saw_refusal = contains_nocase(value, "administrator privileges");

  SDFree(value);
  SDDisconnectAll();

  if (saw_refusal && !saw_syntax) {
    printf("\nFAIL: the session entered SDSYS but is NOT an administrator.\n");
    printf("That is message 2001, MODIFYA's first statement.  USR_ADMIN is\n");
    printf("seeded in kernel.c from IsElevated() AND connection_type # CN_SOCKET\n");
    printf("AND IsInteractive(); a ConnectLocal child is CN_PIPE and inherits\n");
    printf("its parent's token, so IsInteractive() is the term to measure.\n");
    return 4;
  }

  if (!saw_syntax) {
    printf("\nFAIL: the reply carries neither the syntax block nor message 2001,\n");
    printf("so this probe cannot say whether the verb ran.  Read the text above\n");
    printf("before believing anything else in this run.\n");
    return 5;
  }

  if (saw_refusal) {
    printf("\nFAIL: the reply carries BOTH the syntax block and message 2001.\n");
    printf("A step where the positive pattern and a disqualifier both match is\n");
    printf("not a pass - PROJECT_STATUS.md 0.\n");
    return 5;
  }

  printf("\nPASS: SDSYS admitted over SDConnectLocal, WHO named SDSYS, and the\n");
  printf("administrator verb ran.  The local route carries an administrator\n");
  printf("session, so IsInteractive() answers true for a ConnectLocal child.\n");
  return 0;
}
