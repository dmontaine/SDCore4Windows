/* qmcompat.c - the one QM entry point that is not a plain alias.
 *
 * Modifications Copyright (c) 2026 Donald Montaine
 * Distributed under the GNU Lesser General Public License, version 3 or
 * later (LGPL-3.0-or-later). See LICENSE and GPLv3.txt for the full terms.
 *
 * Linking exception:
 *
 * As a special exception, the copyright holders of this library give you
 * permission to link this library with independent modules to produce an
 * executable, regardless of the license terms of these independent modules,
 * and to copy and distribute the resulting executable under terms of your
 * choice, provided that you also meet, for each linked independent module,
 * the terms and conditions of the license of that module. An independent
 * module is a module which is not derived from or based on this library. If
 * you modify this library, you may extend this exception to your version of
 * the library, but you are not obligated to do so. If you do not wish to do
 * so, delete this exception statement from your version.
 */

#include "sdclilib.h"

/* 19 Aug 26 - QMConnectLocal is the only one of the original library's 49
   entry points with no sdclilib counterpart, so it is the only one that
   cannot be aliased in qmclilib.def.  In SD it starts a local server
   process and talks to it over a pipe; that path is Linux-only, and this port
   is Winsock-only by design - see "Windows port behavior" in the 64-bit
   README.

   IT IS STILL EXPORTED, as a stub, and that is the whole point of the file.
   An application that merely IMPORTS the symbol will not start at all if the
   export is missing, even on a run that never calls it - the loader resolves
   the entire import table up front.  Trading "this program cannot start" for
   a single failing call is worth a five-line function.

   Returns FALSE, as the original does when it cannot reach a local server.
   A caller that checks the return value therefore behaves as it would against
   a real QM installation with no local server running, and should fall back
   to QMConnect, which is what a remote test wants anyway.

   QMError() is deliberately not set: sdclilib keeps its per-session error
   buffer private to sdclilib.c and exposes no setter, and reaching into it
   from here would mean forking the source, which this project exists to
   avoid.  A caller reading QMError() after this returns sees the previous
   message rather than a new one. */

SD_API int QMConnectLocal(char* account) {
  (void)account;
  return 0;
}
