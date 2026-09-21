/* api_identity_probe.c - can an API session open ONE NAMED FILE, the real
 * client library's own way - not a hand-rolled reimplementation of the wire
 * protocol?
 *
 * RELEASE_1.1 84 (RELEASE_1.1_FIXES.md).  verify-apiidentity.ps1 currently
 * proves OS-level ACL enforcement of an impersonated API session by sending
 * the wire protocol's request 4 (vb.open, SrvrOpen in sdclient.h:54) through
 * a hand-written Python reimplementation, scram-probe.py - built because
 * .NET's SslStream could not do the RFC 9266 channel binding the TLS+SCRAM
 * handshake needs (RELEASE_1.1 41, 42).
 *
 * sdclilib ALREADY EXPORTS SDOpen(), AND IT SENDS THE EXACT SAME REQUEST -
 * checked by reading the source, not assumed: sdclilib.c's SDOpen() calls
 * message_pair(SrvrOpen, filename, strlen(filename)), and SrvrOpen is 4
 * (sdclient.h:54, "Open file").  So a probe built on it needs no protocol
 * reimplementation at all - it is the same request scram-probe.py sends,
 * through the library real applications actually link against.
 *
 * WHAT THIS DOES NOT REPRODUCE: the wire-level server_error/status PAIR
 * scram-probe.py's OPEN line carries.  sdclilib keeps server_error as an
 * internal struct field (sdclilib.c:412) with no public getter, and the one
 * exposed status function, SDStatus(), returns sd_status - which SDOpen
 * never sets (checked: no assignment to it anywhere in SDOpen's body).  So a
 * refusal here is reported as SDError()'s text alone, which is what an
 * ordinary application actually sees.  A caller wired to scram-probe.py's
 * exact "REFUSED server_error N status N: text" shape would need its regex
 * changed, not just its probe swapped - this is named so nobody wires this
 * in expecting a byte-for-byte replacement.
 *
 * DELIBERATELY NARROW, LIKE api_admin_probe.c beside it: it opens exactly
 * the one file it is given and prints what happened.  The caller owns the
 * assertion about whether that outcome was the right one.
 *
 * NOT WIRED INTO ANY VERIFIER YET.  Built and compile-checked this session
 * (gcc -std=c11 -Wall -Wextra -Wpedantic, zero warnings); verify-apiidentity.ps1's
 * fixture-driving steps still call scram-probe.py.  See RELEASE_1.1 84 for why
 * the swap is not done in the same pass: this agent had no elevation and no
 * test account credentials, so the one path that needs both - a successful
 * open on a real fixture - could not be run before being submitted.
 *
 * THE CONNECT HALF WAS RUN LIVE, THOUGH, AGAINST THE REAL sdwind ON THIS
 * MACHINE (127.0.0.1:4243, 20 Sep 2026) - not assumed, not simulated.  With
 * deliberately wrong credentials it printed "REFUSED: Invalid username or
 * password" and exited 1, exactly the CONNECT branch below.  That exercises
 * the whole TLS+SCRAM handshake scram-probe.py exists to work around - the
 * RFC 9266 channel binding .NET's SslStream cannot do - through the REAL
 * client library, successfully.  What is NOT witnessed is only the one leg
 * that needs a valid session: SDOpen() against an authenticated connection.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sdclilib.h"

static void show_error(const char* what) {
  printf("  %s: %s\n", what, SDError());
}

int main(int argc, char** argv) {
  const char *host, *user, *pass, *account, *filename;
  int port, fno;

  if (argc < 7) {
    printf("usage: %s <host> <port> <user> <password> <account> <filename>\n",
           argv[0]);
    return 5;
  }
  host     = argv[1];
  port     = atoi(argv[2]);
  user     = argv[3];
  pass     = argv[4];
  account  = argv[5];
  filename = argv[6];

  printf("API %s:%d, account %s, as %s, file %s\n", host, port, account, user, filename);

  if (!SDConnect((char*)host, port, (char*)user, (char*)pass,
                 (char*)account)) {
    show_error("REFUSED");
    printf("\nPROBE.CONNECT=NO\n");
    return 1;
  }
  printf("PROBE.CONNECT=YES\n");

  /* A REFUSAL IS A VALID, MEASURED OUTCOME - NOT A PROBE FAILURE.  The two
     text lines below are what the caller parses; the exit code alone does
     not distinguish "opened" from "refused", exactly as api_admin_probe.c
     does not use its exit code to carry the session's own answer. */
  fno = SDOpen((char*)filename);
  if (fno <= 0) {
    printf("OPEN %s: REFUSED: %s\n", filename, SDError());
    SDDisconnectAll();
    return 0;
  }

  printf("OPEN %s: OPENED fileno %d\n", filename, fno);
  SDClose(fno);

  SDDisconnect();
  SDDisconnectAll();
  return 0;
}
