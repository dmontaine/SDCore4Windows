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

/* remote_connect_test.c - SDConnect over the API port, and with it $CRED
 *
 * PROJECT_STATUS.md section 7 step 6.  This is the first thing that exercises
 * the remote transport, step 6a's $CRED check and step 6c's ACC$GROUP check
 * at the same time; until it runs, all three are built and unproven.
 *
 * IT NEEDS A RUNNING, INSTALLED SD WITH APIPORT SET, which is why it is not
 * part of "make check" - and APIPORT defaults to OFF, so a fresh install will
 * refuse the connection outright and rightly.  gplbld/verify-apiport.ps1 sets
 * the whole thing up and runs this; read that before running this by hand.
 * Run it only after gplbld/assert-current.ps1 exits 0 (CLAUDE.md).
 *
 * THREE CELLS, AND THE TWO CONTROLS ARE THE WHOLE POINT.  An accepted
 * connection proves nothing on its own - a credential check that never
 * executed would accept it too, and so would a grant check that never ran.
 * Step 11 established this the expensive way.
 *
 *   right password, granted account   -> MUST be admitted   (treatment)
 *   WRONG password, same account      -> MUST be refused    (proves $CRED ran)
 *   right password, SDSYS             -> MUST be refused    (proves the
 *                                        ACC$GROUP check ran; ACCOUNTS/SDSYS
 *                                        names "sdsys", never a Windows group)
 *
 * The wrong-password cell is the one with no precedent anywhere in this
 * project: SDConnectLocal sends no password at all, so nothing has ever
 * reached !CRED_VERIFY through the API.  If it is admitted, the treatment
 * above it means nothing whatever.
 *
 * Exit codes are distinct so a shell can tell the outcomes apart:
 *   0  all three as expected
 *   1  the right credentials were REFUSED - transport, $CRED or the grant
 *      check.  Read the SDError() text printed with it.
 *   2  the WRONG password was ADMITTED - $CRED did not run.  Everything else
 *      this test reports is worthless.
 *   3  SDSYS was ADMITTED - the ACC$GROUP check did not run.
 *   4  a session opened but could not execute a command
 *   5  wrong arguments
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sdclilib.h"

static void show_error(const char* what) {
  printf("  %s: %s\n", what, SDError());
}

int main(int argc, char** argv) {
  const char *host, *user, *pass, *account;
  int port, err;
  char* value;

  if (argc < 6) {
    printf("usage: %s <host> <port> <user> <password> <account>\n", argv[0]);
    return 5;
  }
  host    = argv[1];
  port    = atoi(argv[2]);
  user    = argv[3];
  pass    = argv[4];
  account = argv[5];

  printf("API port %s:%d\n\n", host, port);

  /* 19 Aug 26 Windows port - WHICH REQUEST TYPES ACTUALLY WENT OUT.
     docs/SCRAM_AUTH.md phase 4.  A successful login does NOT prove the client
     spoke SCRAM: the server still accepts the old request 24, so a client that
     had fallen back to it would be admitted exactly as readily.  With
     SD_CLIENT_DEBUG set, SDDebug(1) logs every packet's type to that path, and
     gplbld/verify-apiport.ps1 then asserts 47 and 48 are present and 24 is not.
     Off unless the variable is set, so an ordinary run is unaffected. */
  if (getenv("SD_CLIENT_DEBUG") != NULL)
    SDDebug(1);

  /* --- treatment: the right credentials, an account the user is granted -- */

  printf("connecting as %s to %s with the right password ...\n", user, account);

  if (!SDConnect((char*)host, port, (char*)user, (char*)pass, (char*)account)) {
    show_error("REFUSED");
    printf("\nFAIL: correct credentials were refused.\n");
    printf("Is sdwind listening?  APIPORT must be set in the INSTALLED\n");
    printf("sd.conf under ProgramData, and SD restarted - read_config() runs\n");
    printf("only when the shared segment is created, so a running system does\n");
    printf("not pick it up.  If the port is open, the refusal came from\n");
    printf("!CRED_VERIFY or from the ACC$GROUP test.\n");
    return 1;
  }

  printf("  admitted\n");

  /* Prove the session is real rather than merely open, and say which account
     it landed in - WHO is cheap and needs no data. */

  value = SDExecute("WHO", &err);
  if (value == NULL) {
    printf("  WHO returned nothing, err %d: %s\n", err, SDError());
    SDDisconnectAll();
    return 4;
  }
  printf("  WHO -> %s", value);
  if ((value[0] != '\0') && (value[strlen(value) - 1] != '\n'))
    printf("\n");
  SDFree(value);
  SDDisconnect();

  /* --- control 1: the wrong password.  THIS IS THE FIRST TEST OF $CRED. --- */

  printf("\nconnecting with a WRONG password (this MUST be refused) ...\n");

  if (SDConnect((char*)host, port, (char*)user, (char*)"!wrong-password!",
                (char*)account)) {
    printf("  ADMITTED\n");
    printf("\nFAIL: a wrong password was accepted, so !CRED_VERIFY did not\n");
    printf("run.  APILOGIN may be 0 in the installed sd.conf, which skips the\n");
    printf("password by design.  The admitted result above is worthless.\n");
    SDDisconnectAll();
    return 2;
  }

  show_error("refused");

  /* --- control 2: SDSYS, which no API session may enter ----------------- */

  printf("\nconnecting to SDSYS (this MUST be refused) ...\n");

  if (SDConnect((char*)host, port, (char*)user, (char*)pass, (char*)"SDSYS")) {
    printf("  ADMITTED\n");
    printf("\nFAIL: SDSYS was admitted through the API.  ACCOUNTS/SDSYS names\n");
    printf("the group \"sdsys\", which is not a Windows group, so the\n");
    printf("ACC$GROUP check cannot have run.\n");
    SDDisconnectAll();
    return 3;
  }

  show_error("refused");

  SDDisconnectAll();

  printf("\nPASS: right password admitted, wrong password refused, SDSYS refused.\n");
  printf("The remote transport carried a session, $CRED ran, and so did the\n");
  printf("ACC$GROUP check.\n");
  return 0;
}
