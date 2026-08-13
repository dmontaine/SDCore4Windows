#include <stdio.h>
#include <string.h>
#include "sdclilib.h"

int main(void) {
  char source[] = "one|two|three";
  char delimiter[] = "|";
  char *value;
  int err;
  int attempt;

  if (SDDcount(source, delimiter) != 3)
    return 1;
  value = SDField(source, delimiter, 2, 1);
  if (value == NULL || strcmp(value, "two") != 0)
    return 2;
  SDFree(value);

  /* A command attempted without a session must return a safe empty string,
     not read from an uninitialised network buffer. */
  value = SDExecute("NOOP", &err);
  if (value == NULL || value[0] != '\0')
    return 3;
  SDFree(value);

  /* Exercise Winsock startup, error propagation, socket close, and cleanup.
     Port 1 on loopback is expected to refuse a connection. */
  for (attempt = 0; attempt < 3; attempt++) {
    if (SDConnect("127.0.0.1", 1, "test", "test", "test")) {
      SDDisconnect();
    } else if (SDError()[0] == '\0') {
      return 4;
    }
  }

  /* Must be harmless when no sessions are connected. */
  SDDisconnectAll();

  puts("sdclilib smoke test passed");
  return 0;
}
