/* Modifications Copyright (c) 2026 Donald Montaine
 *
 * This library is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at
 * your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser
 * General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <https://www.gnu.org/licenses/>.
 *
 * Linking exception (additional permission under GNU LGPL version 3
 * section 7): as a special exception, the copyright holders give you
 * permission to link this library with independent modules to produce an
 * executable, regardless of the license terms of these independent modules,
 * and to copy and distribute the resulting executable under terms of your
 * choice, provided that you also meet, for each linked independent module,
 * the terms and conditions of the license of that module.  An independent
 * module is a module which is not derived from or based on this library.
 */

/* local_connect_test.c - SDConnectLocal, and with it the grant check
 *
 * PROJECT_STATUS.md section 7 step 11, and the first evidence of any kind for
 * step 6c.
 *
 * THIS ONE NEEDS A RUNNING, INSTALLED SD, which is why it is not part of
 * "make check".  The other two tests in this directory deliberately need no
 * server; this one spawns sd.exe through the installed client library and
 * therefore measures the INSTALLED tree, not the build tree.  Run it only
 * after gplbld/assert-current.ps1 exits 0, or the result describes a system
 * that no longer exists (CLAUDE.md).
 *
 * RUN IT UNELEVATED, as an ordinary user.  SDConnectLocal sends no password:
 * vb.local.login in GPL.BP/APISRVR takes the identity from the process owner,
 * which is the whole point of the local transport and is what the grant check
 * below is testing against.
 *
 * THE CONTROL IS THE POINT, and it is why this tests two accounts rather than
 * one.  A connection that succeeds proves nothing on its own: a grant check
 * that was never reached would also let it through.  So:
 *
 *   <account>  the caller is a member of its sdu_ group  -> MUST be admitted
 *   SDSYS      ACC$GROUP is "sdsys", not a Windows        -> MUST be refused
 *              group and never has been (section 6)
 *
 * Only the pair means anything.  Two earlier attempts at a control/treatment
 * test elsewhere in this project proved nothing for exactly this reason.
 *
 * Build and run it by hand with "make check-local LOCALACCT=<account>" in
 * gplsrc/sdclilib.  It is ALSO a standing suite step since 4 Sep 2026 -
 * gplbld/verify-localconnect.ps1 drives it from VerifyInstall1, which is
 * unelevated, and "make sd" builds it so it is always there to run
 * (PRE_RELEASE_FIXES 163).
 *
 * Exit codes are distinct so a shell can tell the outcomes apart:
 *   0  both as expected
 *   1  the account was refused  - the grant check is too strict, or the
 *                                 transport is broken.  Read SDError().
 *   2  SDSYS was admitted       - the grant check did not run.  The test that
 *                                 passed above it is therefore meaningless.
 *   3  the session opened but could not execute a command
 *   4  no account given         - see main().  A run with no treatment would
 *                                 test only the control and read as a pass.
 */

#include <stdio.h>
#include <string.h>
#include "sdclilib.h"

/* 04 Sep 26 - THE TREATMENT ACCOUNT IS AN ARGUMENT, AND IT USED TO BE THE
   LITERAL "DON".  PRE_RELEASE_FIXES 163.  That was fine while this was run by
   hand on one machine and fatal the moment it became a standing suite step: a
   hardcoded name passes here and fails on every other machine, which is
   PRE_RELEASE 54's fixed-prefix trap wearing different clothes.

   THE CONTROL STAYS HARDCODED AS SDSYS, DELIBERATELY.  It is not a second
   sample of the same thing - it is the account whose ACC$GROUP names a Windows
   group that does not exist, so it is the one account whose refusal proves the
   grant check ran.  Making it a parameter would let a caller supply two
   accounts that are both admitted and still read as a pass.                  */

int main(int argc, char** argv) {
  int err;
  char* value;
  const char* acct;

  /* REFUSE THE NULL CASE OUT LOUD - CLAUDE.md's instrument rule.  With no
     account there is no treatment, and a run that tested only the control
     would report "SDSYS was refused" and look like a pass.                   */

  if (argc != 2) {
    printf("usage: %s <account>\n\n", argv[0]);
    printf("  <account> is an SD account the CALLER is granted - normally\n");
    printf("  their own.  SDConnectLocal sends no password; the identity\n");
    printf("  comes from the process owner, so run this UNELEVATED.\n");
    printf("  SDSYS is the built-in control and is not a parameter.\n");
    return 4;
  }

  acct = argv[1];

  /* --- treatment: an account the caller is granted --------------------- */

  printf("connecting to %s ...\n", acct);

  if (!SDConnectLocal((char*)acct)) {
    printf("  REFUSED: %s\n", SDError());
    printf("\nFAIL: %s was refused.  Either the named pipe never carried a\n", acct);
    printf("session - see whether cygwin_attach_handle_to_fd() honoured the\n");
    printf("descriptor numbers, PROJECT_STATUS.md section 7 step 11 - or the\n");
    printf("grant check refused a member of sdu_don.\n");
    return 1;
  }

  printf("  admitted\n");

  /* Prove the session is real rather than merely open.  WHO is cheap, needs
     no data, and names the account, so it also shows WHICH account we are in. */

  value = SDExecute("WHO", &err);
  if (value == NULL) {
    printf("  WHO returned nothing, err %d: %s\n", err, SDError());
    SDDisconnectAll();
    return 3;
  }

  printf("  WHO -> %s", value);
  if ((value[0] != '\0') && (value[strlen(value) - 1] != '\n'))
    printf("\n");
  SDFree(value);
  SDDisconnect();

  /* --- control: an account nobody may enter through the API ------------ */

  printf("\nconnecting to SDSYS (this MUST be refused) ...\n");

  if (SDConnectLocal("SDSYS")) {
    printf("  ADMITTED\n");
    printf("\nFAIL: SDSYS was admitted through the API.  ACCOUNTS/SDSYS names\n");
    printf("the group \"sdsys\", which does not exist on Windows, so the grant\n");
    printf("check cannot have run.  That makes the %s result above worthless\n", acct);
    printf("as evidence - it would have succeeded either way.\n");
    SDDisconnectAll();
    return 2;
  }

  printf("  refused: %s\n", SDError());

  SDDisconnectAll();

  printf("\nPASS: %s admitted, SDSYS refused.\n", acct);
  printf("The grant check ran, and SDConnectLocal carried a session.\n");
  return 0;
}
