/* probe-relayssl.c - RELEASE_1.1 43, option 2's two falsified-ifs, in one
 * unelevated measurement.  Built and driven by probe-relayssl.ps1.
 *
 * THE DECISION.  Owner, 16 Sep 26: implement option 2 - the TLS relay becomes a
 * RELOCATED MSYS2 program at Low integrity, per connection, so that
 * gplsrc/sd_tlssrv.c stays ONE source shared with Linux.  probe-relocrt measured
 * that a relocated msys-2.0.dll starts at Low beside sd; probe-relocattr measured
 * that it gets its own object-directory key.  Neither touched OpenSSL, and the
 * relay is nothing without it.
 *
 * THE TWO FALSIFIED-IFS THIS ANSWERS, both recorded in PROJECT_STATUS HANDOFF 78:
 *   (i)  "the relay's OpenSSL cannot be built against the relocated runtime"
 *   (ii) "the second msys-2.0.dll cannot be staged without colliding with sd's
 *        on PATH"
 * They are really one question, because msys-ssl-3.dll imports msys-crypto-3.dll
 * AND msys-2.0.dll, so the whole closure has to resolve to the relay's own
 * directory rather than to the copy beside sd.exe.
 *
 * WHY THE MODULE-PATH CHECK IS THE POINT, NOT A DETAIL.  Windows searches the
 * APPLICATION's directory first, so this is EXPECTED to work - and a probe that
 * only reported "OpenSSL started" would print exactly the same thing if it had
 * quietly loaded sd's runtime instead.  That is the trap CLAUDE.md calls
 * anchoring on a string the failure also carries.  So the exe asks the LOADER
 * where each module actually came from and REFUSES (exit 3) unless all three sit
 * in its own directory.  A pass therefore cannot be a collision.
 *
 * Build, from gplbld in MSYS2's MSYS bash:
 *   gcc -O2 -Wall -o probe-relayssl.exe probe-relayssl.c -lssl -lcrypto
 *
 * Exit 0 = ran at the expected integrity, loaded all three modules from its OWN
 *          directory, and OpenSSL works (TLS 1.3 server context + RNG)
 * Exit 2 = could not run
 * Exit 3 = it loaded a runtime or an OpenSSL DLL from somewhere else - a
 *          COLLISION, which is falsified-if (ii)
 * Exit 4 = OpenSSL itself failed - falsified-if (i)
 */
/* NOCRYPT keeps wincrypt.h out, which #defines X509_NAME and makes openssl's
   x509.h fail to parse.  The PRODUCT does not get to do this: gplsrc/win32tls.c
   records the standing rule that windows.h and the SD/OpenSSL headers may not
   share a translation unit, and the relay's Windows half must be its own .c with
   a Windows-free interface, exactly as win32tls.c is.  A probe is one file. */
#define NOCRYPT
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <openssl/ssl.h>
#include <openssl/rand.h>
#include <openssl/opensslv.h>
#include <openssl/crypto.h>

static unsigned long integrity(void) {
  HANDLE t;
  BYTE b[256];
  DWORD l, rid = 0;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t)) {
    if (GetTokenInformation(t, TokenIntegrityLevel, b, sizeof b, &l)) {
      PSID s = ((TOKEN_MANDATORY_LABEL*)b)->Label.Sid;
      rid = *GetSidSubAuthority(s, *GetSidSubAuthorityCount(s) - 1);
    }
    CloseHandle(t);
  }
  return rid;
}

/* Where did the LOADER actually get this module?  Not where we hoped. */
static int module_path(const char* name, char* out, size_t n) {
  HMODULE h = GetModuleHandleA(name);
  if (h == NULL)
    return 0;
  if (GetModuleFileNameA(h, out, (DWORD)n) == 0)
    return 0;
  return 1;
}

static void dirname_of(const char* path, char* out, size_t n) {
  size_t i;
  strncpy(out, path, n - 1);
  out[n - 1] = '\0';
  for (i = strlen(out); i > 0; i--) {
    if (out[i - 1] == '\\' || out[i - 1] == '/') {
      out[i - 1] = '\0';
      return;
    }
  }
  out[0] = '\0';
}

int main(void) {
  static const char* mods[3] = { "msys-2.0.dll", "msys-ssl-3.dll",
                                 "msys-crypto-3.dll" };
  char self[MAX_PATH], selfdir[MAX_PATH];
  char p[MAX_PATH], d[MAX_PATH];
  int i, foreign = 0, missing = 0;
  SSL_CTX* ctx;
  unsigned char rnd[16];

  if (GetModuleFileNameA(NULL, self, sizeof self) == 0) {
    printf("relayssl: COULD NOT RUN - GetModuleFileName failed\n");
    return 2;
  }
  dirname_of(self, selfdir, sizeof selfdir);

  printf("relayssl: started, pid %lu, integrity 0x%lx\n",
         (unsigned long)GetCurrentProcessId(), integrity());
  printf("relayssl: own directory : %s\n", selfdir);

  /* ---- (ii) the collision question, asked of the loader ---------------- */
  for (i = 0; i < 3; i++) {
    if (!module_path(mods[i], p, sizeof p)) {
      printf("relayssl: MODULE %-18s NOT LOADED\n", mods[i]);
      missing++;
      continue;
    }
    dirname_of(p, d, sizeof d);
    if (strcasecmp(d, selfdir) == 0) {
      printf("relayssl: module %-18s OWN dir   %s\n", mods[i], p);
    } else {
      printf("relayssl: module %-18s FOREIGN   %s\n", mods[i], p);
      foreign++;
    }
  }

  /* ---- (i) does OpenSSL actually work here ----------------------------- */
  printf("relayssl: OpenSSL version: %s\n", OpenSSL_version(OPENSSL_VERSION));
  ctx = SSL_CTX_new(TLS_server_method());
  if (ctx == NULL) {
    printf("relayssl: SSL_CTX_new FAILED\n");
    return 4;
  }
  if (!SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION) ||
      !SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION)) {
    printf("relayssl: cannot pin TLS 1.3\n");
    SSL_CTX_free(ctx);
    return 4;
  }
  if (RAND_bytes(rnd, sizeof rnd) != 1) {
    printf("relayssl: RAND_bytes FAILED - no entropy at this integrity\n");
    SSL_CTX_free(ctx);
    return 4;
  }
  SSL_CTX_free(ctx);
  printf("relayssl: TLS 1.3 server context OK, RNG OK\n");

  if (missing > 0) {
    printf("relayssl: REFUSED - %d module(s) never loaded; nothing was proved\n",
           missing);
    return 2;
  }
  if (foreign > 0) {
    printf("relayssl: COLLISION - %d module(s) came from outside this directory\n",
           foreign);
    return 3;
  }
  printf("relayssl: ALL THREE MODULES CAME FROM THIS DIRECTORY\n");
  return 0;
}
