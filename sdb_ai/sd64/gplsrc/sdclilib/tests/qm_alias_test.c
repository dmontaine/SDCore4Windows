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

/* qm_alias_test.c - proves the QM export names work, which is the entire
   reason this 32-bit project exists.  The smoke test inherited from the
   64-bit project exercises the library through its SD names and would pass
   just as well if every QM alias were missing.

   Two things are checked, and they are different things.  That a QM name
   RESOLVES is settled at load time: if any alias were absent this program
   would not start.  That a QM name reaches the RIGHT code has to be checked
   at run time, and is done twice over - by comparing the addresses behind the
   two names, and by checking that the results are what the SD functions
   would return.  An export table can be wrong in ways that still load. */

#include <stdio.h>
#include <string.h>
#include "qmclilib.h"
#include "sdclilib.h"

int main(void) {
  char source[] = "one|two|three";
  char delimiter[] = "|";
  char subject[] = "a-b-a";
  char *value;
  int attempt;

  /* An alias is one export-table entry pointing at another's code, so the two
     names must be the same address.  A forwarding wrapper would not be.

     Compared as function pointers rather than through (void *), which ISO C
     does not define a conversion for and -Wpedantic duly warns about.  No
     cast is needed anyway: each pair is declared with the same prototype in
     qmclilib.h and sdclilib.h, so the pointers are already the same type. */
  if (QMDcount != SDDcount)
    return 1;
  if (QMConnect != SDConnect)
    return 2;
  if (QMCall != SDCall)
    return 3;

  if (QMDcount(source, delimiter) != 3)
    return 4;

  value = QMField(source, delimiter, 2, 1);
  if (value == NULL || strcmp(value, "two") != 0)
    return 5;
  QMFree(value);

  /* Allocated by the QM name, released by the SD one: same allocator, one
     library, not two layers with separate state. */
  value = QMChange(subject, "a", "z", 0, 0);
  if (value == NULL || strcmp(value, "z-b-z") != 0)
    return 6;
  SDFree(value);

  if (QMConnected())
    return 7;

  /* The stub in qmcompat.c.  It must fail rather than do something, and it
     must not take the process down on the way. */
  if (QMConnectLocal("QM.SYS"))
    return 8;

  /* Winsock startup, failure reporting and cleanup, reached entirely through
     QM names.  Port 1 on loopback is expected to refuse the connection. */
  for (attempt = 0; attempt < 3; attempt++) {
    if (QMConnect("127.0.0.1", 1, "test", "test", "test")) {
      QMDisconnect();
    } else if (QMError()[0] == '\0') {
      return 9;
    }
  }

  QMDisconnectAll();

  puts("qmclilib alias test passed");
  return 0;
}
