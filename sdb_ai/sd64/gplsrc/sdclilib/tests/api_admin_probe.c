/* api_admin_probe.c - what privilege does a REMOTE API session actually hold?
 *
 * PROJECT_STATUS.md section 8.  APISRVR says in two places that an API session
 * "cannot have" elevation - at its K$ADMINISTRATOR note and again where it
 * refuses SDSYS - and the account gating there is reasoned on that basis.
 *
 * THE CLAIM LOOKS FALSE ON WINDOWS, and this is the client half of finding
 * out.  sdwind runs as a service (SERVICE_START_NAME LocalSystem, measured
 * 20 Aug 2026) and accept_api_session() fork()s and exec()s "sd -n -q", so the
 * session inherits LOCALSYSTEM'S TOKEN rather than the client's.  Measured the
 * same day from outside: the forked sd.exe's owner is unreadable to an
 * unelevated query, exactly as sdwind's is, while an ordinary interactive
 * sd.exe reads back as the user.
 *
 * What that leaves open is whether the SD session can USE it, which cannot be
 * seen from outside the process.  So this connects as an ordinary account and
 * runs a command, and gplbld/verify-apiadmin.ps1 runs the SAME command from a
 * local session and compares.  The comparison is the measurement; this program
 * only carries one half of it.
 *
 * IT IS DELIBERATELY GENERAL - it executes whatever command it is given and
 * prints the reply verbatim.  A probe that knew what it expected would be a
 * demonstration; the caller owns the assertion.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sdclilib.h"

static void show_error(const char* what) {
  printf("  %s: %s\n", what, SDError());
}

int main(int argc, char** argv) {
  const char *host, *user, *pass, *account, *command;
  int port, err;
  char* value;

  if (argc < 7) {
    printf("usage: %s <host> <port> <user> <password> <account> <command>\n",
           argv[0]);
    return 5;
  }
  host    = argv[1];
  port    = atoi(argv[2]);
  user    = argv[3];
  pass    = argv[4];
  account = argv[5];
  command = argv[6];

  printf("API %s:%d, account %s, as %s\n", host, port, account, user);

  if (!SDConnect((char*)host, port, (char*)user, (char*)pass,
                 (char*)account)) {
    show_error("REFUSED");
    printf("\nPROBE.CONNECT=NO\n");
    printf("The account needs a $cred record and must pass the ACC$GROUP\n");
    printf("test.  gplbld/verify-apiadmin.ps1 sets both up and passes them in.\n");
    return 1;
  }

  printf("PROBE.CONNECT=YES\n");

  value = SDExecute((char*)command, &err);
  if (value == NULL) {
    printf("PROBE.EXECUTE=NO err %d: %s\n", err, SDError());
    SDDisconnectAll();
    return 4;
  }

  /* Verbatim, and on its own lines.  The caller greps for PROBE.* markers the
     BASIC half prints, so anything added here would have to be parsed around. */
  printf("PROBE.EXECUTE=YES\n");
  printf("---- begin session output ----\n");
  printf("%s", value);
  if ((value[0] != '\0') && (value[strlen(value) - 1] != '\n'))
    printf("\n");
  printf("---- end session output ----\n");

  SDFree(value);
  SDDisconnect();
  SDDisconnectAll();
  return 0;
}
