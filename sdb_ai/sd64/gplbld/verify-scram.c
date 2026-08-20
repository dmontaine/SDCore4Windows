/* verify-scram.c
 * Checks gplsrc/sd_scram.c against the RFC 7677 test vectors.
 *
 * Build and run from this directory, in an MSYS2 shell:
 *
 *   gcc -Wall -Wextra -O2 -o verify-scram.exe verify-scram.c \
 *       ../gplsrc/sd_scram.c -I../gplsrc -I/usr/local/include \
 *       -L/usr/local/lib -lsodium && ./verify-scram.exe
 *
 * Exit 0 all vectors reproduced, 1 a mismatch, 2 could not run.
 *
 * WHY THIS EXISTS SEPARATELY FROM THE SERVER.  sd_scram.c deliberately touches
 * no SD state, so it can be compiled on its own and checked without building
 * sd.exe, creating a shared segment or starting a listener.  Every later phase
 * of the SCRAM work rests on these six functions, so they are worth being able
 * to test in two seconds rather than after a full build.
 *
 * THE VECTORS ARE RFC 7677 SECTION 3, and they were recomputed independently
 * from the RFC's inputs on 19 Aug 2026 before being written down here - the
 * published proof and signature agree with what the algorithm produces, so a
 * failure below is this implementation and not a mistranscribed constant.
 *
 * docs/SCRAM_AUTH.md
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sodium.h>

#include "sd_scram.h"

/* RFC 7677 section 3 */
#define V_PASSWORD  "pencil"
#define V_SALT      "W22ZaJ0SNY7soEsUEjb6gQ=="
#define V_ITER      4096

#define V_SALTED    "xKSVEDI6tPlSysH6mUQZOeeOp01r6B3fcJbodRPcYV0="
#define V_STOREDKEY "WG5d8oPm3OtcPnkdi4Uo7BkeZkBFzpcXkuLmtbsT4qY="
#define V_SERVERKEY "wfPLwcE6nTWhTAmQ7tl2KeoiWGPlZqQxSrmfPwDl2dU="
#define V_PROOF     "dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
#define V_SIGNATURE "6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="

#define CLIENT_FIRST_BARE \
    "n=user,r=rOprNGfwEbeRWgbNEkqO"
#define SERVER_FIRST \
    "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0," \
    "s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
#define CLIENT_FINAL_NO_PROOF \
    "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0"

static int failures = 0;
static int checks = 0;

static void check(const char* name, const char* got, const char* want) {
    checks++;
    if (got == NULL) {
        printf("  FAIL  %-16s returned NULL\n", name);
        failures++;
        return;
    }
    if (strcmp(got, want) != 0) {
        printf("  FAIL  %-16s\n          got  %s\n          want %s\n",
               name, got, want);
        failures++;
        return;
    }
    printf("  ok    %-16s %s\n", name, got);
}

static void check_int(const char* name, int got, int want) {
    checks++;
    if (got != want) {
        printf("  FAIL  %-16s got %d, want %d\n", name, got, want);
        failures++;
        return;
    }
    printf("  ok    %-16s %d\n", name, got);
}

int main(void) {
    char* salted;
    char* client_key;
    char* stored_key;
    char* server_key;
    char* client_sig;
    char* proof;
    char* server_sig;
    char* recovered;
    char* recovered_hash;
    char* nonce;
    char* nonce2;
    char auth[512];

    if (sodium_init() == -1) {
        fprintf(stderr, "libsodium failed to initialise\n");
        return 2;
    }

    snprintf(auth, sizeof(auth), "%s,%s,%s",
             CLIENT_FIRST_BARE, SERVER_FIRST, CLIENT_FINAL_NO_PROOF);

    puts("RFC 7677 section 3 vectors");

    salted = sd_scram_pbkdf2(V_PASSWORD, V_SALT, V_ITER, 32);
    check("SaltedPassword", salted, V_SALTED);
    if (salted == NULL)
        return 1;

    client_key = sd_scram_hmac(salted, "Client Key");
    stored_key = sd_scram_sha256(client_key);
    check("StoredKey", stored_key, V_STOREDKEY);

    server_key = sd_scram_hmac(salted, "Server Key");
    check("ServerKey", server_key, V_SERVERKEY);

    client_sig = sd_scram_hmac(stored_key, auth);
    proof = sd_scram_xor(client_key, client_sig);
    check("ClientProof", proof, V_PROOF);

    server_sig = sd_scram_hmac(server_key, auth);
    check("ServerSignature", server_sig, V_SIGNATURE);

    /* The server's half: recover ClientKey from the proof and check its hash
       against the stored key.  This is the actual verification path, so it is
       worth exercising rather than assuming it follows from the above. */
    puts("\nServer-side verification");
    recovered = sd_scram_xor(proof, client_sig);
    check("recovered key", recovered, client_key);
    recovered_hash = sd_scram_sha256(recovered);
    check_int("ct_equal accept", sd_scram_ct_equal(recovered_hash, stored_key), 1);

    /* A wrong password must not verify.  Cheap, and it catches an
       implementation that returns a constant. */
    {
        char* wrong = sd_scram_pbkdf2("pencil2", V_SALT, V_ITER, 32);
        char* wrong_ck = sd_scram_hmac(wrong, "Client Key");
        char* wrong_sk = sd_scram_sha256(wrong_ck);
        check_int("ct_equal reject", sd_scram_ct_equal(wrong_sk, stored_key), 0);
        free(wrong);
        free(wrong_ck);
        free(wrong_sk);
    }

    puts("\nGuards");
    check_int("bad base64", sd_scram_ct_equal("!!!not base64!!!", stored_key), -1);
    check_int("length mismatch", sd_scram_ct_equal("AAAA", stored_key), -1);
    check_int("xor mismatch NULL", sd_scram_xor("AAAA", stored_key) == NULL, 1);
    check_int("zero iterations", sd_scram_pbkdf2(V_PASSWORD, V_SALT, 0, 32) == NULL, 1);
    check_int("empty password", sd_scram_pbkdf2("", V_SALT, V_ITER, 32) == NULL, 1);
    check_int("absurd iterations",
              sd_scram_pbkdf2(V_PASSWORD, V_SALT, 99999999L, 32) == NULL, 1);

    /* 18 bytes is the client nonce length the exchange uses; two calls must
       not agree, or the nonce is not doing its job. */
    nonce = sd_scram_random(18);
    nonce2 = sd_scram_random(18);
    check_int("nonce length", nonce != NULL && strlen(nonce) == 24, 1);
    check_int("nonce differs", (nonce && nonce2 && strcmp(nonce, nonce2) != 0), 1);
    check_int("zero bytes NULL", sd_scram_random(0) == NULL, 1);

    printf("\n%d checks, %d failed\n", checks, failures);

    free(salted);
    free(client_key);
    free(stored_key);
    free(server_key);
    free(client_sig);
    free(proof);
    free(server_sig);
    free(recovered);
    free(recovered_hash);
    free(nonce);
    free(nonce2);

    return failures == 0 ? 0 : 1;
}
