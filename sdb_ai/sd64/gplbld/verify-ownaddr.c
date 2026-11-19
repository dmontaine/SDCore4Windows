/* verify-ownaddr.c - drive sd_own_address_in() / sd_own_address() for test-ownaddr-units.py (S.264, 18 Nov 2026; carried to
 * Windows Core 18 Nov 26, RELEASE_1.1 344, unchanged).
 *
 *   verify-ownaddr ADDR OWN1 [OWN2 ...]    prints "result=N" for sd_own_address_in(ADDR, OWN...)
 *   verify-ownaddr --live ADDR             prints "result=N" for sd_own_address(ADDR) on this machine's interfaces
 */
#include <stdio.h>
#include <string.h>

#include "sd_ownaddr.h"

int main(int argc, char** argv) {
  if ((argc == 3) && (strcmp(argv[1], "--live") == 0)) {
    printf("result=%d\n", sd_own_address(argv[2]));
    return 0;
  }
  if (argc < 2) {
    fprintf(stderr, "usage: verify-ownaddr ADDR OWN... | --live ADDR\n");
    return 2;
  }
  printf("result=%d\n", sd_own_address_in(argv[1], (const char* const*)(argv + 2), argc - 2));
  return 0;
}
