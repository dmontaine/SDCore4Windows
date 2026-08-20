/* smoke_test.c - local string functions, no server required.
 *
 * Modifications Copyright (c) 2026 Donald Montaine
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
