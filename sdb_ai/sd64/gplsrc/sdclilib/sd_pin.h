/* sd_pin.h - first-use pinning of the server's TLS certificate (client side).
 *
 * 30 Sep 26 SD Core Solo, SOLO 24 (agreed with the Linux Solo agent, who built
 * theirs first).  What the user and the master see must be the SAME on both
 * systems, so the VALUE, the STORE FORMAT and the WORDS match Linux's:
 *
 *   the value  SHA-256 of the server's WHOLE certificate in DER form, as 64
 *              lower-case hex digits (not the key alone, not the PEM text)
 *   the store  $SD_KNOWN_SERVERS if set, else %USERPROFILE%\.sdcore\known_servers;
 *              one line per server, "<host>:<port> <64 hex digits>", host in
 *              lower case as typed; a different port is a different server
 *   the rule   first connection to a host:port records it; the same certificate
 *              later connects; a different one is REFUSED, store untouched; a
 *              store that cannot be opened or written REFUSES (never an
 *              unpinned connection); no auto-update, no prompt - the remedy is
 *              removing the line
 *
 * This file has no OpenSSL in it so its rules can be tested on their own. */

#ifndef SD_PIN_H
#define SD_PIN_H

#include <stddef.h>

#define SD_PIN_HEX_LEN 64

/* 1 = the certificate is known or has just been recorded: connect.
   0 = refuse, with the complete user-facing text in errmsg.
   host is the name as the caller typed it (lower-cased here). */
int sd_pin_check(const char* host, int port, const char* hex64, char* errmsg,
                 size_t errlen);

#endif
