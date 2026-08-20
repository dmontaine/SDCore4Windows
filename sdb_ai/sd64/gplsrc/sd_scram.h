/* sd_scram.h
 * SCRAM-SHA-256 primitives for the API login exchange.
 * Copyright (c) 2026 The SD Developers, All Rights Reserved
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 * START-HISTORY:
 * 19 Aug 26 Windows port - written for the API SCRAM exchange.
 *           docs/SCRAM_AUTH.md
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Every argument and every return is a NUL-terminated base64 string, except
 * the password given to sd_scram_pbkdf2(), which is plain text.  See the
 * header comment of sd_scram.c for why.
 *
 * Every function that returns char* returns malloc'd memory the CALLER MUST
 * FREE with free() - not sodium_free(), which sd_KeyFromPW() needs because it
 * allocates through sodium_malloc() and this file does not.
 *
 * A NULL return means failure, always, with no partial results and nothing
 * left for the caller to interpret.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef SD_SCRAM_H
#define SD_SCRAM_H

/* base64(SHA256(decode(b64_in))) */
char* sd_scram_sha256(const char* b64_in);

/* base64(HMAC-SHA256(decode(b64_key), msg)).  The key is base64, the message
   is PLAIN TEXT - SCRAM only ever signs message text, and SD BASIC has no
   base64 encoder to hand it anything else.  See sd_scram.c. */
char* sd_scram_hmac(const char* b64_key, const char* msg);

/* base64(PBKDF2-HMAC-SHA256(password, decode(b64_salt), iterations, dk_len)) */
char* sd_scram_pbkdf2(const char* password, const char* b64_salt,
                      long iterations, long dk_len);

/* base64 of n_bytes cryptographically random bytes */
char* sd_scram_random(long n_bytes);

/* base64(decode(b64_a) XOR decode(b64_b)); lengths must match */
char* sd_scram_xor(const char* b64_a, const char* b64_b);

/* 1 equal, 0 different, -1 malformed.  Constant time over the compared bytes.
   A caller deciding whether to admit a login must treat -1 as "no". */
int sd_scram_ct_equal(const char* b64_a, const char* b64_b);

#endif

/* END-CODE */
