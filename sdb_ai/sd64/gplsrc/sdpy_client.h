/* sdpy_client.h - SD's side of the Python helper pipe.  PROJECT_STATUS.md 5.27.
 *
 * NOTHING OF PYTHON APPEARS HERE, DELIBERATELY.  This header is included by
 * MSYS2 code inside sd.exe; the helper it talks to is a native binary linked
 * against python.org's python3.dll.  Section 5.3 keeps the two runtimes out of
 * one process, and the only thing that crosses is bytes on a pipe.
 */

#ifndef SDPY_CLIENT_H
#define SDPY_CLIENT_H

#include <stddef.h>

/* Must match sdpy.c's SDPY_PROTOCOL.  A mismatch is refused at startup rather
 * than discovered on the first call that behaves oddly. */
#define SDPY_PROTOCOL "SDPY1"

typedef struct SDPY SDPY;

/* Start the helper and complete the handshake.  Returns NULL on failure, with
 * a reason in err.  The caller owns the result until sdpy_stop(). */
SDPY* sdpy_start(const char* exe, char* err, size_t errlen);

/* One request, one response.
 *
 * Returns 0 if the exchange HAPPENED and -1 if the transport failed; those are
 * different things and the caller must not confuse them.  *status carries the
 * helper's own answer - 0, or an SD error code from err.h - and *payload
 * points at storage owned by the SDPY, valid until the next call.
 *
 * Every argument is a pointer AND a length: SD strings are bytes, they contain
 * @fm/@vm/@sm and can contain NUL, and nothing here may treat them as C
 * strings. */
int sdpy_call(SDPY* s, const char* verb,
              const char* a1, size_t n1,
              const char* a2, size_t n2,
              const char* a3, size_t n3,
              int* status, char** payload, size_t* plen);

/* QUIT, then close the pipes and reap the process.  Safe on NULL. */
void sdpy_stop(SDPY* s);

#endif /* SDPY_CLIENT_H */
