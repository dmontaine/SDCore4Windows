/* thread_smoke.c - threads against sdclilib.dll with no server (25 Oct 26, Linux 375cbe7's thread safety, sheet 456).
 *
 * What it proves, with nothing listening on port 1:
 *   - a thread that fails to connect still has ITS OWN error text after another thread has connected and failed (the failed slot is held
 *     for its thread, not given back for the next connect to clear);
 *   - 32 threads connecting, failing and disconnecting at once never see a connected session, an empty error, or each other's slots;
 *   - when those threads have ended their held slots are free again (fiber local storage callback), so a thread can make 1100 more attempts
 *     without meeting "Too many sessions".
 * Measured 25 Oct 26: the library before the change failed it (A lost its own error, bad=503); the library after passes.
 *
 * Build (UCRT64 gcc, from the directory that holds sdclilib.dll and libsdclilib.dll.a):
 *   gcc -O1 -Wall -o thread_smoke.exe tests/thread_smoke.c -L. -lsdclilib
 * Run from that directory (so the DLL is found): thread_smoke.exe   Exit 0 and "ALL OK" when it holds.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int SDConnect(char* host, int port, char* username, char* password, char* account);
char* SDError(void);
int SDConnected(void);
void SDDisconnect(void);
void SDDisconnectAll(void);

static HANDLE evA_done, evB_done;
static char errA[600], errB[600];
static volatile LONG bad = 0;

static DWORD WINAPI thA(void* p) {
  (void)p;
  int ok = SDConnect("", 4247, "u", "p", "a");           /* Invalid host name */
  SetEvent(evA_done);
  WaitForSingleObject(evB_done, 10000);                   /* B has now connected (and failed) on its own */
  snprintf(errA, sizeof(errA), "%s", SDError());
  if (ok) InterlockedIncrement(&bad);
  return 0;
}

static DWORD WINAPI thB(void* p) {
  (void)p;
  WaitForSingleObject(evA_done, 10000);                   /* A has failed and holds its slot */
  int ok = SDConnect("127.0.0.1", 1, "u", "p", "a");      /* refused */
  snprintf(errB, sizeof(errB), "%s", SDError());
  SetEvent(evB_done);
  if (ok) InterlockedIncrement(&bad);
  return 0;
}

static DWORD WINAPI churn(void* p) {
  int i;
  (void)p;
  for (i = 0; i < 100; i++) {
    int ok = SDConnect("127.0.0.1", 1, "u", "p", "a");
    char* e = SDError();
    if (ok || e == NULL || e[0] == 0) InterlockedIncrement(&bad);
    if (SDConnected()) InterlockedIncrement(&bad);
    if (i % 3 == 0) SDDisconnect();                        /* gives the held slot back */
  }
  return 0;
}

int main(void) {
  HANDLE h[2], t[32];
  int i, n = 0;
  evA_done = CreateEvent(NULL, TRUE, FALSE, NULL);
  evB_done = CreateEvent(NULL, TRUE, FALSE, NULL);
  h[0] = CreateThread(NULL, 0, thA, NULL, 0, NULL);
  h[1] = CreateThread(NULL, 0, thB, NULL, 0, NULL);
  WaitForMultipleObjects(2, h, TRUE, 20000);
  printf("A error: [%s]\nB error: [%s]\n", errA, errB);
  if (strstr(errA, "Invalid host name") == NULL) { puts("FAIL A lost its own error"); bad++; }
  if (strstr(errB, "Winsock error") == NULL) { puts("FAIL B has no winsock error"); bad++; }
  for (i = 0; i < 32; i++) t[i] = CreateThread(NULL, 0, churn, NULL, 0, NULL);
  WaitForMultipleObjects(32, t, TRUE, 120000);
  for (i = 0; i < 32; i++) CloseHandle(t[i]);
  /* all threads have ended: their held slots must be free again, so MAX_SESSIONS (1024) is not exhausted */
  for (i = 0; i < 1100; i++) {
    int ok = SDConnect("", 4247, "u", "p", "a");
    char* e = SDError();
    if (ok || strstr(e, "Too many") != NULL) { printf("stopped at %d ok=%d err=[%s]\n", i, ok, e); n++; break; }
    SDDisconnect();
  }
  if (n) { puts("FAIL slots leaked"); bad++; }
  SDDisconnectAll();
  printf("bad=%ld\n", (long)bad);
  puts(bad == 0 ? "ALL OK" : "FAILED");
  return bad != 0;
}
