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
 *   DON    the caller is a member of sdu_don      -> MUST be admitted
 *   SDSYS  ACC$GROUP is "sdsys", not a Windows    -> MUST be refused
 *          group and never has been (section 6)
 *
 * Only the pair means anything.  Two earlier attempts at a control/treatment
 * test elsewhere in this project proved nothing for exactly this reason.
 *
 * Build and run it with "make check-local" in gplsrc/sdclilib.
 *
 * Exit codes are distinct so a shell can tell the outcomes apart:
 *   0  both as expected
 *   1  DON was refused          - the grant check is too strict, or the
 *                                 transport is broken.  Read SDError().
 *   2  SDSYS was admitted       - the grant check did not run.  The test that
 *                                 passed above it is therefore meaningless.
 *   3  the session opened but could not execute a command
 */

#include <stdio.h>
#include <string.h>
#include "sdclilib.h"

int main(void) {
  int err;
  char* value;

  /* --- treatment: an account the caller is granted --------------------- */

  printf("connecting to DON ...\n");

  if (!SDConnectLocal("DON")) {
    printf("  REFUSED: %s\n", SDError());
    printf("\nFAIL: DON was refused.  Either the named pipe never carried a\n");
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
    printf("check cannot have run.  That makes the DON result above worthless\n");
    printf("as evidence - it would have succeeded either way.\n");
    SDDisconnectAll();
    return 2;
  }

  printf("  refused: %s\n", SDError());

  SDDisconnectAll();

  printf("\nPASS: DON admitted, SDSYS refused.\n");
  printf("The grant check ran, and SDConnectLocal carried a session.\n");
  return 0;
}
