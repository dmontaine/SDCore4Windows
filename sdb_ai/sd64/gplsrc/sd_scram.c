/* sd_scram.c
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
 * EVERY BINARY VALUE HERE IS BASE64, in and out, and that is not a stylistic
 * choice.  These values are binary - 32-byte keys, nonces, salts - and they
 * reach BASIC through SDEXT, which passes arguments as NUL-terminated C
 * strings and returns through k_put_c_string().  Raw binary cannot survive
 * that round trip.  It would also be unsafe if it could: SD BASIC strings are
 * delimited by mark characters (0xFE, 0xFD, 0xFC) and a 32-byte digest
 * contains one roughly one time in nine, so a raw digest in a dynamic-array
 * field would corrupt field extraction intermittently and unreproducibly.
 * !SD_KEY_FROM_PW already returns base64 for the same reason.
 *
 * TWO ARGUMENTS ARE TEXT RATHER THAN BASE64, and both are text in the protocol
 * too: the password given to sd_scram_pbkdf2(), and the message signed by
 * sd_scram_hmac().  Neither is binary, so base64 would encode nothing, and
 * requiring it would have forced a base64 encoder into SD BASIC - which has
 * none - purely to feed this file.  The rule is therefore "binary is base64",
 * not "everything is base64".
 *
 * NOTHING HERE TOUCHES SD STATE.  No k_error(), no process.status, no e_stack.
 * The functions take C strings, return malloc'd C strings, and answer NULL on
 * any failure.  op_sdext.c maps that onto SD's error reporting.  The point of
 * the separation is that gplbld/verify-scram.c can compile this file directly
 * against libsodium and check it against the RFC 7677 test vectors without
 * building or running a server.
 *
 * PBKDF2 IS IMPLEMENTED HERE because libsodium does not provide it - it offers
 * Argon2 and scrypt.  docs/SCRAM_AUTH.md records why PBKDF2 is nonetheless the
 * right choice for this protocol: the derivation has to run on a 32-bit client
 * (mvDeveloper), where Argon2's memory-hardness cannot be configured high
 * enough to be worth having.  The construction below is RFC 8018 section 5.2
 * over libsodium's HMAC-SHA256.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <stdlib.h>
#include <string.h>
#include <sodium.h>

#include "sd_scram.h"

/* Sanity bounds.  These exist so that a malformed or hostile argument arriving
   from BASIC cannot turn into an allocation failure or a hang inside the
   iteration loop.  They are far above anything the protocol asks for. */
#define SCRAM_MAX_ITERATIONS 10000000L
#define SCRAM_MAX_BYTES      4096L

#define SHA256_LEN 32U

/* ====================================================================== */

static char* b64_encode(const unsigned char* bin, size_t len) {
    size_t cap;
    char* b64;

    cap = sodium_base64_ENCODED_LEN(len, sodium_base64_VARIANT_ORIGINAL);
    b64 = (char*)malloc(cap);
    if (b64 == NULL)
        return NULL;

    sodium_bin2base64(b64, cap, bin, len, sodium_base64_VARIANT_ORIGINAL);
    return b64;
}

/* Caller frees.  Answers NULL on anything that is not valid base64, which is
   deliberate - a decode failure here means a malformed protocol message, and
   the exchange should fail rather than proceed on a guess. */
static unsigned char* b64_decode(const char* b64, size_t* out_len) {
    size_t in_len;
    size_t cap;
    unsigned char* bin;

    if (b64 == NULL)
        return NULL;

    in_len = strlen(b64);
    cap = (in_len / 4) * 3 + 3;
    bin = (unsigned char*)malloc(cap);
    if (bin == NULL)
        return NULL;

    if (sodium_base642bin(bin, cap, b64, in_len, NULL, out_len, NULL,
                          sodium_base64_VARIANT_ORIGINAL) != 0) {
        free(bin);
        return NULL;
    }

    return bin;
}

/* libsodium's one-shot crypto_auth_hmacsha256() requires a 32-byte key.  The
   streaming form takes any key length, which PBKDF2 needs (the key is the
   password) and which SCRAM needs for AuthMessage signing. */
static void hmac_sha256(const unsigned char* key, size_t key_len,
                        const unsigned char* msg, size_t msg_len,
                        unsigned char out[SHA256_LEN]) {
    crypto_auth_hmacsha256_state state;

    crypto_auth_hmacsha256_init(&state, key, key_len);
    crypto_auth_hmacsha256_update(&state, msg, msg_len);
    crypto_auth_hmacsha256_final(&state, out);
    sodium_memzero(&state, sizeof(state));
}

/* RFC 8018 section 5.2.  For SCRAM dk_len is always the hash length, so the
   outer loop runs once; it is written in full anyway because a truncated
   implementation that happens to work for one length is a trap for whoever
   reuses it. */
static int pbkdf2_sha256(const unsigned char* pw, size_t pw_len,
                         const unsigned char* salt, size_t salt_len,
                         unsigned long iterations,
                         unsigned char* out, size_t dk_len) {
    unsigned char* block;
    unsigned char u[SHA256_LEN];
    unsigned char t[SHA256_LEN];
    unsigned long j;
    size_t k;
    size_t done = 0;
    uint32_t counter = 1;

    if (iterations < 1)
        return -1;

    block = (unsigned char*)malloc(salt_len + 4);
    if (block == NULL)
        return -1;

    while (done < dk_len) {
        size_t take;

        memcpy(block, salt, salt_len);
        block[salt_len + 0] = (unsigned char)((counter >> 24) & 0xFF);
        block[salt_len + 1] = (unsigned char)((counter >> 16) & 0xFF);
        block[salt_len + 2] = (unsigned char)((counter >> 8) & 0xFF);
        block[salt_len + 3] = (unsigned char)(counter & 0xFF);

        hmac_sha256(pw, pw_len, block, salt_len + 4, u);
        memcpy(t, u, SHA256_LEN);

        for (j = 1; j < iterations; j++) {
            hmac_sha256(pw, pw_len, u, SHA256_LEN, u);
            for (k = 0; k < SHA256_LEN; k++)
                t[k] ^= u[k];
        }

        take = dk_len - done;
        if (take > SHA256_LEN)
            take = SHA256_LEN;
        memcpy(out + done, t, take);
        done += take;
        counter++;
    }

    sodium_memzero(u, sizeof(u));
    sodium_memzero(t, sizeof(t));
    free(block);
    return 0;
}

/* ======================================================================
   sd_scram_sha256()  -  base64(SHA256(base64_decode(b64_in)))            */

char* sd_scram_sha256(const char* b64_in) {
    unsigned char* bin;
    size_t bin_len;
    unsigned char digest[SHA256_LEN];
    char* result;

    if (sodium_init() == -1)
        return NULL;

    bin = b64_decode(b64_in, &bin_len);
    if (bin == NULL)
        return NULL;

    crypto_hash_sha256(digest, bin, bin_len);
    free(bin);

    result = b64_encode(digest, SHA256_LEN);
    sodium_memzero(digest, sizeof(digest));
    return result;
}

/* ======================================================================
   sd_scram_hmac()  -  base64(HMAC-SHA256(decode(b64_key), msg))

   THE KEY IS BASE64 AND THE MESSAGE IS PLAIN TEXT, which looks inconsistent
   until you notice that SCRAM never signs binary.  The four HMACs the protocol
   asks for are over "Client Key", "Server Key" and the AuthMessage, and an
   AuthMessage is SCRAM message text - printable ASCII throughout, since every
   value inside it is already base64.  The keys, by contrast, are always raw
   32-byte values.

   Taking the message as text rather than base64 is what lets the BASIC caller
   exist at all: SD BASIC has no base64 encoder, so demanding base64 here would
   have forced a seventh primitive whose only purpose was feeding this one.   */

char* sd_scram_hmac(const char* b64_key, const char* msg) {
    unsigned char* key;
    size_t key_len;
    unsigned char mac[SHA256_LEN];
    char* result;

    if (sodium_init() == -1)
        return NULL;

    if (msg == NULL)
        return NULL;

    key = b64_decode(b64_key, &key_len);
    if (key == NULL)
        return NULL;

    hmac_sha256(key, key_len, (const unsigned char*)msg, strlen(msg), mac);

    sodium_memzero(key, key_len);
    free(key);

    result = b64_encode(mac, SHA256_LEN);
    sodium_memzero(mac, sizeof(mac));
    return result;
}

/* ======================================================================
   sd_scram_pbkdf2()  -  base64(PBKDF2-HMAC-SHA256(password, salt, i, n))

   The password arrives as plain text rather than base64: it is what the user
   typed, it reaches here from a terminal prompt or from QMConnect, and both
   deliver characters.  Everything else in this file is base64 because it is
   binary; this one is not binary.                                        */

char* sd_scram_pbkdf2(const char* password, const char* b64_salt,
                      long iterations, long dk_len) {
    unsigned char* salt;
    size_t salt_len;
    unsigned char* dk;
    char* result;

    if (sodium_init() == -1)
        return NULL;

    if (password == NULL || password[0] == '\0')
        return NULL;
    if (iterations < 1 || iterations > SCRAM_MAX_ITERATIONS)
        return NULL;
    if (dk_len < 1 || dk_len > SCRAM_MAX_BYTES)
        return NULL;

    salt = b64_decode(b64_salt, &salt_len);
    if (salt == NULL)
        return NULL;
    if (salt_len == 0) {
        free(salt);
        return NULL;
    }

    dk = (unsigned char*)malloc((size_t)dk_len);
    if (dk == NULL) {
        free(salt);
        return NULL;
    }

    if (pbkdf2_sha256((const unsigned char*)password, strlen(password),
                      salt, salt_len, (unsigned long)iterations,
                      dk, (size_t)dk_len) != 0) {
        free(salt);
        free(dk);
        return NULL;
    }

    free(salt);
    result = b64_encode(dk, (size_t)dk_len);
    sodium_memzero(dk, (size_t)dk_len);
    free(dk);
    return result;
}

/* ======================================================================
   sd_scram_random()  -  base64 of n cryptographically random bytes       */

char* sd_scram_random(long n_bytes) {
    unsigned char* buf;
    char* result;

    if (sodium_init() == -1)
        return NULL;

    if (n_bytes < 1 || n_bytes > SCRAM_MAX_BYTES)
        return NULL;

    buf = (unsigned char*)malloc((size_t)n_bytes);
    if (buf == NULL)
        return NULL;

    randombytes_buf(buf, (size_t)n_bytes);
    result = b64_encode(buf, (size_t)n_bytes);

    sodium_memzero(buf, (size_t)n_bytes);
    free(buf);
    return result;
}

/* ======================================================================
   sd_scram_xor()  -  base64(a XOR b), for ClientProof and its recovery

   Lengths must match.  A mismatch is a protocol error rather than something
   to pad or truncate around, so it answers NULL.                          */

char* sd_scram_xor(const char* b64_a, const char* b64_b) {
    unsigned char* a;
    unsigned char* b;
    size_t a_len;
    size_t b_len;
    size_t i;
    char* result;

    if (sodium_init() == -1)
        return NULL;

    a = b64_decode(b64_a, &a_len);
    if (a == NULL)
        return NULL;

    b = b64_decode(b64_b, &b_len);
    if (b == NULL) {
        free(a);
        return NULL;
    }

    if (a_len != b_len || a_len == 0) {
        free(a);
        free(b);
        return NULL;
    }

    for (i = 0; i < a_len; i++)
        a[i] ^= b[i];

    result = b64_encode(a, a_len);

    sodium_memzero(a, a_len);
    free(a);
    free(b);
    return result;
}

/* ======================================================================
   sd_scram_ct_equal()  -  constant-time compare of two base64 values

   Returns 1 equal, 0 different, -1 on a decode failure or length mismatch.
   The caller must treat -1 as "not equal" - it is separated only so that a
   malformed message can be told from a wrong one in diagnostics.

   sodium_memcmp() rather than memcmp(): this compares a value derived from
   the client's proof against the stored key, and an early-exit comparison
   leaks how much of it matched.  The old !CRED_VERIFY compared its verifier
   with BASIC's "=", which had the same weakness.                          */

int sd_scram_ct_equal(const char* b64_a, const char* b64_b) {
    unsigned char* a;
    unsigned char* b;
    size_t a_len;
    size_t b_len;
    int same;

    if (sodium_init() == -1)
        return -1;

    a = b64_decode(b64_a, &a_len);
    if (a == NULL)
        return -1;

    b = b64_decode(b64_b, &b_len);
    if (b == NULL) {
        free(a);
        return -1;
    }

    if (a_len != b_len || a_len == 0) {
        free(a);
        free(b);
        return -1;
    }

    same = (sodium_memcmp(a, b, a_len) == 0) ? 1 : 0;

    free(a);
    free(b);
    return same;
}

/* END-CODE */
