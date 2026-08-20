/* scram_client.h
 *
 * SCRAM-SHA-256 client primitives for sdclilib.  docs/SCRAM_AUTH.md, phase 4.
 *
 * WHY A HEADER OF static FUNCTIONS RATHER THAN A .c FILE.  The client library
 * ships as ONE binary that can be copied next to an application - that is the
 * property the 32-bit qmclilib.dll build exists to preserve, and it is why
 * everything here comes from Windows itself rather than from a library that
 * would have to travel with it.  Source may be split; the binary may not.
 * Including this once from sdclilib.c gives one copy of each function.
 *
 * AND IT IS A HEADER SO THE VECTOR TEST DRIVES THE REAL CODE.
 * gplbld/verify-scramclient.c includes this same file and checks it against
 * the RFC 7677 section 3 vectors.  A second implementation written to agree
 * with this one would prove nothing; this way the constants test what ships.
 * It is the arrangement gplsrc/sd_scram.c and gplbld/verify-scram.c already
 * use on the server side.
 *
 * EVERYTHING COMES FROM bcrypt.dll, WHICH IS PART OF WINDOWS.
 * BCryptDeriveKeyPBKDF2, BCryptGenRandom and HMAC-SHA256 through
 * BCRYPT_ALG_HANDLE_HMAC_FLAG.  Base64 is implemented here rather than taken
 * from crypt32's CryptBinaryToStringA: it is thirty lines, it removes a second
 * system dependency, and CryptBinaryToStringA's line-wrapping and CRLF
 * behaviour is a configuration detail nobody should have to remember.
 *
 * THE SERVER RUNS PBKDF2 ONCE, AT SET.PASSWORD.  The client runs it at every
 * login, so the 600,000 iterations are entirely the client's cost.  That is
 * the asymmetry the KDF choice was made on - see SCRAM_AUTH.md, "PBKDF2, not
 * Argon2".
 */

#ifndef SCRAM_CLIENT_H
#define SCRAM_CLIENT_H

#include <windows.h>
#include <bcrypt.h>
#include <string.h>

#ifndef STATUS_SUCCESS
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
#endif

#define SCRAM_HASH_LEN 32              /* SHA-256, and SCRAM's key length */
#define SCRAM_B64_LEN  64              /* 32 bytes -> 44 chars + NUL, rounded */

/* Everything a client-final needs, all base64.  The intermediates are kept
   because the vector test checks them: knowing WHICH step diverged is the
   difference between a five minute fix and an afternoon. */
typedef struct {
    char salted[SCRAM_B64_LEN];      /* SaltedPassword  */
    char stored[SCRAM_B64_LEN];      /* StoredKey       */
    char server_key[SCRAM_B64_LEN];  /* ServerKey       */
    char proof[SCRAM_B64_LEN];       /* ClientProof     */
    char server_sig[SCRAM_B64_LEN];  /* ServerSignature */
} SCRAM_KEYS;

static const char scram_b64_alphabet[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/* ---------------------------------------------------------------------- */
/* Answers 0 if the output buffer is too small, which every caller checks.  */
static int scram_b64_encode(const unsigned char* in, size_t n,
                            char* out, size_t out_sz) {
    size_t need = ((n + 2) / 3) * 4 + 1;
    size_t i = 0;
    size_t o = 0;

    if (out == NULL || out_sz < need)
        return 0;

    while (i < n) {
        unsigned long v = (unsigned long)in[i++] << 16;
        int pad = 2;

        if (i < n) { v |= (unsigned long)in[i++] << 8; pad--; }
        if (i < n) { v |= (unsigned long)in[i++];      pad--; }

        out[o++] = scram_b64_alphabet[(v >> 18) & 0x3F];
        out[o++] = scram_b64_alphabet[(v >> 12) & 0x3F];
        out[o++] = (pad > 1) ? '=' : scram_b64_alphabet[(v >> 6) & 0x3F];
        out[o++] = (pad > 0) ? '=' : scram_b64_alphabet[v & 0x3F];
    }
    out[o] = '\0';
    return 1;
}

/* Strict: rejects any character outside the alphabet, misplaced padding and a
   length that is not a multiple of four.  A salt that fails to decode is a
   server sending nonsense, and the login must fail rather than proceed on a
   half-decoded value. */
static int scram_b64_decode(const char* in, unsigned char* out,
                            size_t out_sz, size_t* out_len) {
    size_t n;
    size_t i;
    size_t o = 0;
    unsigned long v = 0;
    int have = 0;
    int pad = 0;

    if (in == NULL || out == NULL)
        return 0;

    n = strlen(in);
    if (n == 0 || (n % 4) != 0)
        return 0;

    for (i = 0; i < n; i++) {
        const char* p;
        char c = in[i];

        if (c == '=') {
            /* Padding is legal only in the last two positions. */
            if (i < n - 2)
                return 0;
            pad++;
            continue;
        }
        if (pad)                       /* data after padding */
            return 0;

        p = strchr(scram_b64_alphabet, c);
        if (p == NULL || c == '\0')
            return 0;

        v = (v << 6) | (unsigned long)(p - scram_b64_alphabet);
        if (++have == 4) {
            if (o + 3 > out_sz)
                return 0;
            out[o++] = (unsigned char)((v >> 16) & 0xFF);
            out[o++] = (unsigned char)((v >> 8) & 0xFF);
            out[o++] = (unsigned char)(v & 0xFF);
            v = 0;
            have = 0;
        }
    }

    if (pad == 1) {
        if (have != 3) return 0;
        v <<= 6;
        if (o + 2 > out_sz) return 0;
        out[o++] = (unsigned char)((v >> 16) & 0xFF);
        out[o++] = (unsigned char)((v >> 8) & 0xFF);
    } else if (pad == 2) {
        if (have != 2) return 0;
        v <<= 12;
        if (o + 1 > out_sz) return 0;
        out[o++] = (unsigned char)((v >> 16) & 0xFF);
    } else if (pad != 0 || have != 0) {
        return 0;
    }

    if (out_len != NULL)
        *out_len = o;
    return 1;
}

/* ---------------------------------------------------------------------- */
static int scram_random(unsigned char* out, size_t n) {
    return BCryptGenRandom(NULL, out, (ULONG)n,
                           BCRYPT_USE_SYSTEM_PREFERRED_RNG) == STATUS_SUCCESS;
}

/* One helper for both, because the only difference is the HMAC flag and
   whether a key is handed to BCryptCreateHash.  Keeping them together means
   the cleanup path is written once. */
static int scram_digest(const unsigned char* key, size_t key_len,
                        const unsigned char* msg, size_t msg_len,
                        unsigned char out[SCRAM_HASH_LEN]) {
    BCRYPT_ALG_HANDLE alg = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    int ok = 0;

    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL,
            key != NULL ? BCRYPT_ALG_HANDLE_HMAC_FLAG : 0) != STATUS_SUCCESS)
        return 0;

    if (BCryptCreateHash(alg, &hash, NULL, 0,
                         (PUCHAR)key, (ULONG)key_len, 0) != STATUS_SUCCESS)
        goto done;

    /* A zero-length message is legal and BCryptHashData accepts it, but
       passing a NULL pointer is not - guard rather than rely on it. */
    if (msg_len > 0 &&
        BCryptHashData(hash, (PUCHAR)msg, (ULONG)msg_len, 0) != STATUS_SUCCESS)
        goto done;

    if (BCryptFinishHash(hash, out, SCRAM_HASH_LEN, 0) != STATUS_SUCCESS)
        goto done;

    ok = 1;

done:
    if (hash != NULL) BCryptDestroyHash(hash);
    if (alg != NULL)  BCryptCloseAlgorithmProvider(alg, 0);
    return ok;
}

static int scram_sha256(const unsigned char* in, size_t n,
                        unsigned char out[SCRAM_HASH_LEN]) {
    return scram_digest(NULL, 0, in, n, out);
}

static int scram_hmac256(const unsigned char* key, size_t key_len,
                         const char* msg,
                         unsigned char out[SCRAM_HASH_LEN]) {
    /* key must be non-NULL for the HMAC path to be selected; a NULL key here
       would silently compute a plain hash and the login would fail with no
       hint as to why. */
    if (key == NULL)
        return 0;
    return scram_digest(key, key_len, (const unsigned char*)msg,
                        msg == NULL ? 0 : strlen(msg), out);
}

static int scram_pbkdf2(const char* password,
                        const unsigned char* salt, size_t salt_len,
                        unsigned long iterations,
                        unsigned char* out, size_t out_len) {
    BCRYPT_ALG_HANDLE alg = NULL;
    int ok = 0;

    if (password == NULL || salt == NULL || iterations == 0)
        return 0;

    /* HMAC flag: PBKDF2's pseudorandom function is HMAC-SHA-256, not SHA-256.
       Without it BCryptDeriveKeyPBKDF2 fails rather than quietly producing a
       different answer, but the flag is the whole of the difference. */
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL,
                                    BCRYPT_ALG_HANDLE_HMAC_FLAG) != STATUS_SUCCESS)
        return 0;

    ok = BCryptDeriveKeyPBKDF2(alg,
                               (PUCHAR)password, (ULONG)strlen(password),
                               (PUCHAR)salt, (ULONG)salt_len,
                               (ULONGLONG)iterations,
                               out, (ULONG)out_len, 0) == STATUS_SUCCESS;

    BCryptCloseAlgorithmProvider(alg, 0);
    return ok;
}

/* ----------------------------------------------------------------------
   The whole client-side derivation, with no I/O in it.

   SaltedPassword  = PBKDF2(password, salt, i, 32)
   ClientKey       = HMAC(SaltedPassword, "Client Key")
   StoredKey       = SHA256(ClientKey)
   ServerKey       = HMAC(SaltedPassword, "Server Key")
   ClientSignature = HMAC(StoredKey, AuthMessage)
   ClientProof     = ClientKey XOR ClientSignature
   ServerSignature = HMAC(ServerKey, AuthMessage)

   ServerSignature is computed HERE, before the server has answered, so the
   caller has something to compare against rather than something to believe.
   Returning it is what makes checking it the easy path.                    */
static int scram_client_keys(const char* password,
                             const unsigned char* salt, size_t salt_len,
                             unsigned long iterations,
                             const char* auth_message,
                             SCRAM_KEYS* keys) {
    unsigned char salted[SCRAM_HASH_LEN];
    unsigned char client_key[SCRAM_HASH_LEN];
    unsigned char stored_key[SCRAM_HASH_LEN];
    unsigned char server_key[SCRAM_HASH_LEN];
    unsigned char signature[SCRAM_HASH_LEN];
    unsigned char proof[SCRAM_HASH_LEN];
    int i;
    int ok = 0;

    if (password == NULL || auth_message == NULL || keys == NULL)
        return 0;

    memset(keys, 0, sizeof(*keys));

    if (!scram_pbkdf2(password, salt, salt_len, iterations,
                      salted, sizeof(salted)))
        goto done;
    if (!scram_hmac256(salted, sizeof(salted), "Client Key", client_key))
        goto done;
    if (!scram_sha256(client_key, sizeof(client_key), stored_key))
        goto done;
    if (!scram_hmac256(salted, sizeof(salted), "Server Key", server_key))
        goto done;
    if (!scram_hmac256(stored_key, sizeof(stored_key), auth_message, signature))
        goto done;

    for (i = 0; i < SCRAM_HASH_LEN; i++)
        proof[i] = (unsigned char)(client_key[i] ^ signature[i]);

    if (!scram_hmac256(server_key, sizeof(server_key), auth_message, signature))
        goto done;

    if (!scram_b64_encode(salted,     sizeof(salted),     keys->salted,     SCRAM_B64_LEN) ||
        !scram_b64_encode(stored_key, sizeof(stored_key), keys->stored,     SCRAM_B64_LEN) ||
        !scram_b64_encode(server_key, sizeof(server_key), keys->server_key, SCRAM_B64_LEN) ||
        !scram_b64_encode(proof,      sizeof(proof),      keys->proof,      SCRAM_B64_LEN) ||
        !scram_b64_encode(signature,  sizeof(signature),  keys->server_sig, SCRAM_B64_LEN))
        goto done;

    ok = 1;

done:
    /* SecureZeroMemory, not memset: the compiler is entitled to delete a
       memset whose result is never read, and these are the values worth
       clearing.  The base64 forms in *keys are the caller's to manage. */
    SecureZeroMemory(salted, sizeof(salted));
    SecureZeroMemory(client_key, sizeof(client_key));
    SecureZeroMemory(stored_key, sizeof(stored_key));
    SecureZeroMemory(server_key, sizeof(server_key));
    SecureZeroMemory(signature, sizeof(signature));
    SecureZeroMemory(proof, sizeof(proof));

    if (!ok && keys != NULL)
        SecureZeroMemory(keys, sizeof(*keys));
    return ok;
}

/* Constant time, for the server-signature comparison.  The value being
   compared is not secret, but the habit is, and this is two lines. */
static int scram_equal(const char* a, const char* b) {
    size_t i;
    size_t la;
    unsigned char diff = 0;

    if (a == NULL || b == NULL)
        return 0;

    la = strlen(a);
    if (la != strlen(b))
        return 0;

    for (i = 0; i < la; i++)
        diff |= (unsigned char)(a[i] ^ b[i]);

    return diff == 0;
}

#endif /* SCRAM_CLIENT_H */
