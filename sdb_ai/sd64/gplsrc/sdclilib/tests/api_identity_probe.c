/* api_identity_probe.c - does an API session open the files it should, and
 * write records under its OWN name, the real client library's own way - not a
 * hand-rolled reimplementation of the wire protocol?
 *
 * RELEASE_1.1 84 (PROJECT_STATUS.md).  verify-apiidentity.ps1 used to drive
 * gplbld/scram-probe.py, a hand-written Python reimplementation of SCRAM+TLS
 * built because .NET's SslStream could not do the RFC 9266 channel binding
 * the TLS+SCRAM handshake needs (RELEASE_1.1 41, 42).  This is that probe
 * re-expressed on sdclilib, the library real applications actually link
 * against: SDConnect() does the whole TLS+SCRAM login AND the account attach
 * (sdclilib.c:1241 sends SrvrAccount after the login), so it needs no
 * protocol reimplementation - the same requests, through the shipped library.
 *
 * ONE SESSION, THE SAME REQUESTS IN THE SAME ORDER scram-probe.py sent: the
 * login+attach (SDConnect), a vb.open per fixture (SDOpen), then - only if
 * asked - the ownership vb.write (SDWrite), read back with SDRead to prove it
 * landed for THIS session rather than trusting a void return.  The session is
 * over when the probe exits; the caller reads each OPEN/WRITE line and, for
 * the decisive ownership test, the record's owner off disk afterwards.
 *
 * WHAT THIS DOES NOT REPRODUCE, AND WHY THE CALLER WAS REWIRED FOR IT.
 * scram-probe.py printed "REFUSED server_error N status N: text" because it
 * read the wire fields directly.  sdclilib keeps server_error as an internal
 * struct field (sdclilib.c:412) with no public getter, and SDStatus() returns
 * sd_status, which SDOpen never sets (sdclilib.c:2642 - no assignment to it in
 * SDOpen's body).  So a refusal here is reported as SDError()'s text alone,
 * which is what an ordinary application actually sees, and the verifier's
 * Get-ProbeOpen anchors on "OPEN NAME: REFUSED: text" rather than on the wire
 * numbers.  The BOOLEAN outcome (opened / refused / not-seen) is unchanged,
 * and that is all the decisive checks read; see RELEASE_1.1 84.
 *
 * A REFUSAL IS A MEASURED OUTCOME, NOT A PROBE FAILURE.  Like api_admin_probe.c
 * beside it, this exits 0 once a session was established and the requests were
 * sent - the OPEN/WRITE lines carry the answers.  It exits non-zero only when
 * it could not run at all (bad usage, or SDConnect refused: there is then no
 * session to measure).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sdclilib.h"

#define MAX_OPEN 32

struct opened {
  const char* name;
  int fno;
};

static struct opened opened_files[MAX_OPEN];
static int opened_count = 0;

/* Open NAME once, remembering the file number so a later --write of the same
   file reuses it.  Prints the verdict line and returns the fno, or 0. */
static int open_once(const char* name) {
  int i, fno;
  for (i = 0; i < opened_count; i++) {
    if (strcmp(opened_files[i].name, name) == 0 && opened_files[i].fno > 0)
      return opened_files[i].fno;
  }
  fno = SDOpen((char*)name);
  if (fno > 0) {
    printf("OPEN %s: OPENED fileno %d\n", name, fno);
    if (opened_count < MAX_OPEN) {
      opened_files[opened_count].name = name;
      opened_files[opened_count].fno = fno;
      opened_count++;
    }
  } else {
    /* SDOpen sets server_error to SV_ERROR on a refusal, so GetResponse has
       already fetched the server's text into SDError() - it is fresh here. */
    printf("OPEN %s: REFUSED: %s\n", name, SDError());
  }
  return fno;
}

int main(int argc, char** argv) {
  const char *host, *user, *pass, *account;
  int port, i;

  if (argc < 6) {
    printf("usage: %s <host> <port> <user> <password> <account>"
           " [--open NAME]... [--write FILE ID TEXT]\n", argv[0]);
    return 5;
  }
  host    = argv[1];
  port    = atoi(argv[2]);
  user    = argv[3];
  pass    = argv[4];
  account = argv[5];

  printf("api-identity-probe: %s:%d, account %s, as %s\n",
         host, port, account, user);

  /* SDConnect is login + account attach in one call.  A failure here is not a
     probe fault - it is the answer to "could this user get a bound session",
     and its text is what the caller inspects (message 5277, "could not take
     your Windows identity", is the K$ASSUME.USER finding, not a broken test). */
  if (!SDConnect((char*)host, port, (char*)user, (char*)pass,
                 (char*)account)) {
    printf("PROBE.CONNECT=NO\n");
    printf("REFUSED: %s\n", SDError());
    SDDisconnectAll();
    return 1;
  }
  printf("PROBE.CONNECT=YES\n");
  printf("account %s: entered\n", account);

  for (i = 6; i < argc; i++) {
    if (strcmp(argv[i], "--open") == 0) {
      if (i + 1 >= argc) {
        printf("usage: --open needs a NAME\n");
        SDDisconnectAll();
        return 5;
      }
      (void)open_once(argv[i + 1]);
      i += 1;
    } else if (strcmp(argv[i], "--write") == 0) {
      const char *file, *id, *text;
      int fno, rerr;
      char* got;
      if (i + 3 >= argc) {
        printf("usage: --write needs FILE ID TEXT\n");
        SDDisconnectAll();
        return 5;
      }
      file = argv[i + 1];
      id   = argv[i + 2];
      text = argv[i + 3];
      i += 3;

      fno = open_once(file);
      if (fno <= 0) {
        printf("WRITE %s %s: NOT SENT - %s did not open\n", file, id, file);
        continue;
      }
      /* SDWrite returns void; it sets sd_status/aborts only on some failures,
         and does not clear SDError() on success, so SDError() cannot tell a
         clean write from a stale message.  The write is CONFIRMED instead by
         reading the record back in this same session: err 0 means the record
         now exists and the API session can read its own write - exactly the
         property under test.  Byte-for-byte equality is NOT required: a
         directory-file record may be stored with its own line handling, and
         the DECISIVE test is the record's owner on disk, read by the caller. */
      SDWrite(fno, (char*)id, (char*)text);
      got = SDRead(fno, (char*)id, &rerr);
      if (got != NULL && rerr == 0) {
        printf("WRITE %s %s: WRITTEN\n", file, id);
      } else {
        printf("WRITE %s %s: REFUSED: err %d: %s\n", file, id, rerr, SDError());
      }
      if (got != NULL) SDFree(got);
    } else {
      printf("unknown argument: %s\n", argv[i]);
      SDDisconnectAll();
      return 5;
    }
  }

  for (i = 0; i < opened_count; i++) {
    if (opened_files[i].fno > 0) SDClose(opened_files[i].fno);
  }
  SDDisconnect();
  SDDisconnectAll();
  return 0;
}
