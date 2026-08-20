/* verify-scramclient.c
 *
 * Checks the CLIENT-side SCRAM primitives against the RFC 7677 section 3
 * vectors.  docs/SCRAM_AUTH.md, phase 4.
 *
 * IT INCLUDES gplsrc/sdclilib/scram_client.h RATHER THAN RESTATING IT, so the
 * constants below test the code that ships.  A second implementation written
 * to agree with the first would prove only that one person made the same
 * assumption twice.  gplbld/verify-scram.c does the same thing for the server
 * primitives in gplsrc/sd_scram.c.
 *
 * IT NEEDS NO SERVER, NO INSTALL AND NO ELEVATION.  Run it first whenever a
 * login fails and it is not obvious which side is wrong: if this passes, the
 * client's arithmetic is right and the disagreement is elsewhere.
 *
 * Build and run, from an MSYS2 shell in sdb_ai/sd64/gplbld:
 *
 *   gcc -Wall -Wextra -O2 -o verify-scramclient.exe verify-scramclient.c \
 *       -I../gplsrc/sdclilib -lbcrypt && ./verify-scramclient.exe
 *
 * The 32-bit build is the one that matters for mvDeveloper, and it is worth
 * running both - the whole reason PBKDF2 was chosen over Argon2 is that the
 * client is a 32-bit process:
 *
 *   i686-w64-mingw32-gcc ... (or the mingw32 toolchain's gcc)
 */

#include <stdio.h>
#include <string.h>

#include "scram_client.h"

static int failures = 0;
static int checks = 0;

static void check_str(const char* what, const char* expected, const char* got) {
    checks++;
    if (strcmp(expected, got) == 0) {
        printf("  [PASS] %-16s %s\n", what, got);
    } else {
        printf("  [FAIL] %-16s\n         expected %s\n         got      %s\n",
               what, expected, got);
        failures++;
    }
}

static void check_int(const char* what, int expected, int got) {
    checks++;
    if (expected == got) {
        printf("  [PASS] %-16s %d\n", what, got);
    } else {
        printf("  [FAIL] %-16s expected %d, got %d\n", what, expected, got);
        failures++;
    }
}

int main(void) {
    /* RFC 7677 section 3.  Recomputed independently on 19 Aug 2026 for the
       server side and in agreement, so a failure here is this implementation
       and not a mistranscribed constant. */
    static const char* PASSWORD = "pencil";
    static const char* SALT_B64 = "W22ZaJ0SNY7soEsUEjb6gQ==";
    static const unsigned long ITERATIONS = 4096;

    static const char* CLIENT_FIRST_BARE = "n=user,r=rOprNGfwEbeRWgbNEkqO";
    static const char* SERVER_FIRST =
        "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,"
        "s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096";
    static const char* CLIENT_FINAL_BARE =
        "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0";

    unsigned char salt[64];
    size_t salt_len = 0;
    char auth_message[512];
    SCRAM_KEYS keys;
    unsigned char rnd1[18];
    unsigned char rnd2[18];
    char round[SCRAM_B64_LEN];
    unsigned char back[64];
    size_t back_len = 0;

    printf("verify-scramclient - RFC 7677 section 3, client side\n\n");

    printf("== base64, both directions\n");
    /* 18 bytes is what the nonce uses, and the reason it is 18: a multiple of
       three, so the encoding carries no '=' padding and every character is
       inside RFC 5802's printable set. */
    memset(back, 0, sizeof(back));
    memcpy(back, "abcdefghijklmnopqr", 18);
    check_int("encode 18 bytes", 1,
              scram_b64_encode(back, 18, round, sizeof(round)));
    check_int("no '=' padding", 0, strchr(round, '=') != NULL);
    check_int("decode round trip", 1,
              scram_b64_decode(round, back, sizeof(back), &back_len));
    check_int("round trip length", 18, (int)back_len);
    check_int("round trip bytes", 0, memcmp(back, "abcdefghijklmnopqr", 18));

    /* The decoder is strict on purpose: a salt that fails to decode means the
       server sent nonsense, and the login must fail rather than proceed on a
       half-decoded value. */
    check_int("reject bad char", 0,
              scram_b64_decode("AAAA!AAA", back, sizeof(back), &back_len));
    check_int("reject short", 0,
              scram_b64_decode("AAA", back, sizeof(back), &back_len));
    check_int("reject mid padding", 0,
              scram_b64_decode("AA=AAAAA", back, sizeof(back), &back_len));
    check_int("reject empty", 0,
              scram_b64_decode("", back, sizeof(back), &back_len));
    /* One byte of output needs a buffer of one byte; asking it to write three
       into two must fail rather than run over. */
    check_int("reject small buffer", 0,
              scram_b64_decode("AAAAAAAA", back, 2, &back_len));

    printf("\n== the salt decodes to what the vectors assume\n");
    check_int("salt decodes", 1,
              scram_b64_decode(SALT_B64, salt, sizeof(salt), &salt_len));
    check_int("salt length", 16, (int)salt_len);

    printf("\n== AuthMessage\n");
    snprintf(auth_message, sizeof(auth_message), "%s,%s,%s",
             CLIENT_FIRST_BARE, SERVER_FIRST, CLIENT_FINAL_BARE);
    printf("  %s\n", auth_message);

    printf("\n== derivation (PBKDF2 at %lu iterations)\n", ITERATIONS);
    if (!scram_client_keys(PASSWORD, salt, salt_len, ITERATIONS,
                           auth_message, &keys)) {
        printf("  [FAIL] scram_client_keys() failed outright\n");
        return 1;
    }

    check_str("SaltedPassword",  "xKSVEDI6tPlSysH6mUQZOeeOp01r6B3fcJbodRPcYV0=", keys.salted);
    check_str("StoredKey",       "WG5d8oPm3OtcPnkdi4Uo7BkeZkBFzpcXkuLmtbsT4qY=", keys.stored);
    check_str("ServerKey",       "wfPLwcE6nTWhTAmQ7tl2KeoiWGPlZqQxSrmfPwDl2dU=", keys.server_key);
    check_str("ClientProof",     "dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=", keys.proof);
    check_str("ServerSignature", "6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=", keys.server_sig);

    printf("\n== a wrong password must not reproduce the proof\n");
    {
        SCRAM_KEYS wrong;
        check_int("derives", 1,
                  scram_client_keys("pencil2", salt, salt_len, ITERATIONS,
                                    auth_message, &wrong));
        check_int("proof differs", 0, strcmp(wrong.proof, keys.proof) == 0);
        check_int("server sig differs", 0,
                  strcmp(wrong.server_sig, keys.server_sig) == 0);
    }

    printf("\n== the comparison used on the server signature\n");
    check_int("equal matches", 1, scram_equal(keys.server_sig, keys.server_sig));
    check_int("different rejected", 0, scram_equal(keys.server_sig, keys.proof));
    check_int("length mismatch rejected", 0, scram_equal("abc", "abcd"));

    printf("\n== nonce source\n");
    /* Not a randomness test - it cannot be one at this size.  It catches the
       failure that matters: a generator that is not wired up and returns the
       same buffer, or zeros, every time. */
    check_int("random 1", 1, scram_random(rnd1, sizeof(rnd1)));
    check_int("random 2", 1, scram_random(rnd2, sizeof(rnd2)));
    check_int("two draws differ", 0, memcmp(rnd1, rnd2, sizeof(rnd1)) == 0);
    {
        unsigned char zero[18];
        memset(zero, 0, sizeof(zero));
        check_int("not all zero", 0, memcmp(rnd1, zero, sizeof(rnd1)) == 0);
    }

    printf("\n%d of %d checks passed\n", checks - failures, checks);
    if (failures) {
        printf("FAILED\n");
        return 1;
    }
    printf("OK\n");
    return 0;
}
