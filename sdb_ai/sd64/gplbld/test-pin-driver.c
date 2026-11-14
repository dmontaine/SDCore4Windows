/* test-pin-driver.c - a command-line face on sd_pin_check() for test-pin-units.ps1.
 *
 *   test-pin-driver <host> <port> <64 hex digits>
 *
 * The store is whatever SD_KNOWN_SERVERS names (or the default under
 * USERPROFILE), set by the caller.  Prints exactly one line:
 *   PIN: OK                    the certificate is known or was just recorded
 *   PIN: REFUSED <full text>   the connection would not be made
 * Never links OpenSSL: the rules under test are sd_pin.c's alone. */

#include <stdio.h>
#include <stdlib.h>

#include "../gplsrc/sdclilib/sd_pin.h"

int main(int argc, char** argv) {
  char err[1024];

  if (argc != 4) {
    printf("PIN: USAGE test-pin-driver <host> <port> <hex>\n");
    return 2;
  }
  err[0] = '\0';
  if (sd_pin_check(argv[1], atoi(argv[2]), argv[3], err, sizeof(err))) {
    printf("PIN: OK\n");
    return 0;
  }
  printf("PIN: REFUSED %s\n", err);
  return 1;
}
