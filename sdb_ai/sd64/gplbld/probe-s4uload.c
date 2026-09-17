/* probe-s4uload.c - RELEASE_1.1 43 open point (f): does LsaLogonUser's S4U
 * mint hold up when fifty API connections arrive at once?
 *
 * 17 Sep 26 Windows port.  The relay is one process per connection, and each
 * connection's sd - LocalSystem - mints the bare relay account's token with an
 * S4U LsaLogonUser (win32relay.c -> win32_s4u_logon) before spawning it.
 * probe-relayscale measured fifty relay PROCESSES starting and living at once;
 * nothing has put the MINT under concurrency, and it is the one call in the
 * chain that goes through LSA.  This measures it, as LocalSystem, against the
 * real account, in the three shapes that matter and with a leak check:
 *
 *   SERIAL   n mints one after another, token closed each time - the latency
 *            floor and the proof the account mints at all.
 *   THREADS  n threads released together by one event, each minting once and
 *            HOLDING its token until every thread has minted (fifty sessions
 *            alive at once, as fifty live connections would be), then all
 *            closed.  Isolates LSA's behaviour from process start-up.
 *   PROCS    n copies of this program started back to back, each minting once
 *            (--mint) - the product's own shape, one sd per connection.
 *   LEAK     the count of logon sessions (LsaEnumerateLogonSessions) before
 *            the run, at THREADS' peak with fifty tokens held, and after every
 *            token is closed.  A mint leaves a logon session behind for as long
 *            as any handle to its token is open; when the last closes it must
 *            go, or fifty connections an hour would exhaust LSA.
 *
 * Every mint prints its status: 0 with the elapsed ms, or the NTSTATUS and
 * sub-status.  STATUS_INSUFFICIENT_RESOURCES, STATUS_TOO_MANY_SESSIONS or any
 * other non-zero under load is the falsifier; so is a session count that does
 * not return to its baseline.  The null case is refused: the caller must hold
 * SeTcb and the account must mint once before any load is attempted.
 *
 *   probe-s4uload.exe --run  <account> <dir> <n>    the SYSTEM driver; writes
 *                                                    <dir>\s4uload.log
 *   probe-s4uload.exe --mint <account> <outfile>    one mint, one line (PROCS)
 *
 * Build NATIVE, from gplbld in an MSYS2 UCRT64 bash:
 *   gcc -O2 -Wall -o probe-s4uload.exe probe-s4uload.c -lsecur32 -ladvapi32
 * Driven by probe-s4uload.ps1 as a SYSTEM scheduled task (SeTcb).
 * Exit 0 answered and nothing falsified, 1 falsified, 2 could not run.
 *
 * MEASURED 17 Sep 2026, owner-elevated, as SYSTEM, against the installed
 * sdrelay, n = 50: ANSWERED, nothing falsified.  SERIAL 0.4/0.5/0.6 ms
 * (min/avg/max).  THREADS 50: 50 ok, wall 15 ms, per-mint 12.5/17.6/19.6 ms -
 * LSA queues them, refuses none.  PROCS 50: 50/50, wall 219 ms, per-mint
 * 1.0/1.4/2.5 ms; PROCS 100: 100/100, wall 359 ms, per-mint 1.1/6.3/12.8 ms -
 * process start dominates.  Logon sessions 20 before, 70 at the peak with 50
 * tokens held (exactly +50), 20 after every token closed: no leak.  Unelevated
 * control: --mint refuses 0xC0000041 (LsaRegisterLogonProcess without SeTcb).
 */
#include <windows.h>
#include <ntsecapi.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static FILE* lg = NULL;

static void say(const char* fmt, ...) {
  va_list ap;
  char line[1024];
  va_start(ap, fmt);
  vsnprintf(line, sizeof line, fmt, ap);
  va_end(ap);
  if (lg) { fputs(line, lg); fputc('\n', lg); fflush(lg); }
  puts(line);
  fflush(stdout);
}

static int has_privilege(const char* priv) {
  HANDLE t; LUID want; BYTE buf[4096]; DWORD len = 0, i; int found = 0;
  if (!LookupPrivilegeValueA(NULL, priv, &want)) return 0;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t)) return 0;
  if (GetTokenInformation(t, TokenPrivileges, buf, sizeof buf, &len)) {
    TOKEN_PRIVILEGES* tp = (TOKEN_PRIVILEGES*)buf;
    for (i = 0; i < tp->PrivilegeCount; i++)
      if (tp->Privileges[i].Luid.LowPart == want.LowPart &&
          tp->Privileges[i].Luid.HighPart == want.HighPart) found = 1;
  }
  CloseHandle(t);
  return found;
}

/* ======================================================================
   The mint - win32_s4u_logon()'s incantation (win32s4u.c), verbatim in
   substance: trusted connection, MSV1_0 S4U, Network logon, one contiguous
   block, Length excluding the terminator.  Returns the token or NULL, with
   the NTSTATUS pair and the elapsed ms.                                    */
typedef struct { NTSTATUS st, sub; double ms; } MINT_RESULT;

static HANDLE s4u_mint(const char* account, MINT_RESULT* r) {
  LSA_HANDLE hlsa = NULL; LSA_OPERATIONAL_MODE mode;
  LSA_STRING lsaname, origin, pkgname; ULONG pkg = 0, s4ulen;
  MSV1_0_S4U_LOGON* s4u; BYTE* tail; TOKEN_SOURCE source;
  void* prof = NULL; ULONG proflen = 0; LUID luid; QUOTA_LIMITS quota;
  HANDLE tok = NULL; wchar_t wuser[256], wdom[256];
  char domain[MAX_COMPUTERNAME_LENGTH + 1]; DWORD dl = sizeof domain;
  LARGE_INTEGER f, t0, t1;

  r->st = 0; r->sub = 0; r->ms = 0;
  QueryPerformanceFrequency(&f);
  QueryPerformanceCounter(&t0);

  if (!GetComputerNameA(domain, &dl)) { r->st = (NTSTATUS)0xC0000001; return NULL; }
  lsaname.Buffer = (char*)"s4uload"; lsaname.Length = 7; lsaname.MaximumLength = 8;
  r->st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (r->st != 0) return NULL;
  pkgname.Buffer = (char*)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(pkgname.Buffer); pkgname.MaximumLength = (USHORT)(pkgname.Length + 1);
  r->st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (r->st != 0) { LsaDeregisterLogonProcess(hlsa); return NULL; }
  MultiByteToWideChar(CP_ACP, 0, account, -1, wuser, 256);
  MultiByteToWideChar(CP_ACP, 0, domain, -1, wdom, 256);
  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) + (wcslen(wuser) + 1) * sizeof(wchar_t) +
                   (wcslen(wdom) + 1) * sizeof(wchar_t));
  s4u = (MSV1_0_S4U_LOGON*)calloc(1, s4ulen);
  if (!s4u) { LsaDeregisterLogonProcess(hlsa); r->st = (NTSTATUS)0xC000009A; return NULL; }
  s4u->MessageType = MsV1_0S4ULogon;
  tail = (BYTE*)s4u + sizeof(MSV1_0_S4U_LOGON);
  wcscpy((wchar_t*)tail, wuser);
  s4u->UserPrincipalName.Buffer = (wchar_t*)tail;
  s4u->UserPrincipalName.Length = (USHORT)(wcslen(wuser) * sizeof(wchar_t));
  s4u->UserPrincipalName.MaximumLength = (USHORT)(s4u->UserPrincipalName.Length + sizeof(wchar_t));
  tail += s4u->UserPrincipalName.MaximumLength;
  wcscpy((wchar_t*)tail, wdom);
  s4u->DomainName.Buffer = (wchar_t*)tail;
  s4u->DomainName.Length = (USHORT)(wcslen(wdom) * sizeof(wchar_t));
  s4u->DomainName.MaximumLength = (USHORT)(s4u->DomainName.Length + sizeof(wchar_t));
  origin.Buffer = (char*)"s4uload"; origin.Length = 7; origin.MaximumLength = 8;
  memcpy(source.SourceName, "s4uload\0", 8);
  AllocateLocallyUniqueId(&source.SourceIdentifier);
  r->st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen, NULL, &source,
                       &prof, &proflen, &luid, &tok, &quota, &r->sub);
  free(s4u);
  if (prof) LsaFreeReturnBuffer(prof);
  LsaDeregisterLogonProcess(hlsa);
  QueryPerformanceCounter(&t1);
  r->ms = (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / (double)f.QuadPart;
  if (r->st != 0) { if (tok) CloseHandle(tok); return NULL; }
  return tok;
}

/* Logon sessions LSA knows about right now. -1 if it would not say. */
static long logon_sessions(void) {
  ULONG n = 0; PLUID list = NULL;
  if (LsaEnumerateLogonSessions(&n, &list) != 0) return -1;
  if (list) LsaFreeReturnBuffer(list);
  return (long)n;
}

/* ======================================================================
   THREADS                                                                */
typedef struct {
  const char* account; HANDLE go; HANDLE minted; LONG* remaining;
  MINT_RESULT r; HANDLE tok; DWORD start_ms, end_ms;
} WORKER;

static DWORD WINAPI worker(LPVOID p) {
  WORKER* w = (WORKER*)p;
  WaitForSingleObject(w->go, INFINITE);
  w->start_ms = GetTickCount();
  w->tok = s4u_mint(w->account, &w->r);
  w->end_ms = GetTickCount();
  if (InterlockedDecrement(w->remaining) == 0) SetEvent(w->minted);
  return 0;
}

static int run_threads(const char* account, int n, long* peak_sessions) {
  WORKER* w = (WORKER*)calloc((size_t)n, sizeof *w);
  HANDLE* th = (HANDLE*)calloc((size_t)n, sizeof(HANDLE));
  HANDLE go = CreateEvent(NULL, TRUE, FALSE, NULL);
  HANDLE minted = CreateEvent(NULL, TRUE, FALSE, NULL);
  LONG remaining = n; int i, ok = 0, fail = 0; double mn = 1e9, mx = 0, sum = 0;
  DWORD t0, t1;
  for (i = 0; i < n; i++) {
    w[i].account = account; w[i].go = go; w[i].minted = minted; w[i].remaining = &remaining;
    th[i] = CreateThread(NULL, 0, worker, &w[i], 0, NULL);
  }
  t0 = GetTickCount();
  SetEvent(go);                                  /* all n released together */
  WaitForSingleObject(minted, 120000);           /* until the last has minted */
  t1 = GetTickCount();
  *peak_sessions = logon_sessions();             /* n tokens held right now */
  for (i = 0; i < n; i++) {
    WaitForSingleObject(th[i], 5000); CloseHandle(th[i]);
    if (w[i].tok) { ok++; if (w[i].r.ms < mn) mn = w[i].r.ms; if (w[i].r.ms > mx) mx = w[i].r.ms; sum += w[i].r.ms; }
    else { fail++; say("  THREADS mint %d FAILED: status 0x%08lx sub 0x%08lx", i, (unsigned long)w[i].r.st, (unsigned long)w[i].r.sub); }
  }
  say("  THREADS %d: ok %d, failed %d, wall %lu ms, per-mint min %.1f avg %.1f max %.1f ms, sessions at peak %ld",
      n, ok, fail, (unsigned long)(t1 - t0), ok ? mn : 0, ok ? sum / ok : 0, mx, *peak_sessions);
  for (i = 0; i < n; i++) if (w[i].tok) CloseHandle(w[i].tok);
  CloseHandle(go); CloseHandle(minted); free(th); free(w);
  return fail == 0 && ok == n;
}

/* ======================================================================
   PROCS - n copies of this program, --mint each, results in files         */
static int run_procs(const char* self, const char* account, const char* dir, int n) {
  PROCESS_INFORMATION* pi = (PROCESS_INFORMATION*)calloc((size_t)n, sizeof *pi);
  HANDLE* hs = (HANDLE*)calloc((size_t)n, sizeof(HANDLE));
  int i, launched = 0, ok = 0, fail = 0, silent = 0; double mn = 1e9, mx = 0, sum = 0;
  DWORD t0, t1;
  char cmd[MAX_PATH * 3], out[MAX_PATH];
  t0 = GetTickCount();
  for (i = 0; i < n; i++) {
    STARTUPINFOA si; ZeroMemory(&si, sizeof si); si.cb = sizeof si;
    snprintf(out, sizeof out, "%s\\mint-%03d.txt", dir, i);
    snprintf(cmd, sizeof cmd, "\"%s\" --mint %s \"%s\"", self, account, out);
    if (CreateProcessA(self, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, dir, &si, &pi[i])) {
      launched++; hs[i] = pi[i].hProcess; CloseHandle(pi[i].hThread);
    } else {
      say("  PROCS launch %d FAILED: CreateProcess %lu", i, (unsigned long)GetLastError()); hs[i] = NULL;
    }
  }
  for (i = 0; i < n; i++) if (hs[i]) { WaitForSingleObject(hs[i], 120000); CloseHandle(hs[i]); }
  t1 = GetTickCount();
  for (i = 0; i < n; i++) {
    FILE* f; char line[256] = {0}; unsigned long st = 0, sub = 0; double ms = 0;
    snprintf(out, sizeof out, "%s\\mint-%03d.txt", dir, i);
    f = fopen(out, "r");
    if (!f || !fgets(line, sizeof line, f)) { silent++; if (f) fclose(f); continue; }
    fclose(f);
    if (sscanf(line, "MINT ok %lf", &ms) == 1) { ok++; if (ms < mn) mn = ms; if (ms > mx) mx = ms; sum += ms; }
    else if (sscanf(line, "MINT fail 0x%lx sub 0x%lx", &st, &sub) == 2) { fail++; say("  PROCS mint %d FAILED: status 0x%08lx sub 0x%08lx", i, st, sub); }
    else { silent++; say("  PROCS mint %d wrote something else: %s", i, line); }
    DeleteFileA(out);
  }
  say("  PROCS %d: launched %d, ok %d, failed %d, no answer %d, wall %lu ms (launch+mint+exit), per-mint min %.1f avg %.1f max %.1f ms",
      n, launched, ok, fail, silent, (unsigned long)(t1 - t0), ok ? mn : 0, ok ? sum / ok : 0, mx);
  free(pi); free(hs);
  return launched == n && ok == n && fail == 0 && silent == 0;
}

/* ====================================================================== */
static int mode_mint(const char* account, const char* outfile) {
  MINT_RESULT r; HANDLE tok = s4u_mint(account, &r);
  FILE* f = fopen(outfile, "w");
  if (!f) return 2;
  if (tok) { fprintf(f, "MINT ok %.2f\n", r.ms); CloseHandle(tok); }
  else fprintf(f, "MINT fail 0x%08lx sub 0x%08lx\n", (unsigned long)r.st, (unsigned long)r.sub);
  fclose(f);
  return tok ? 0 : 1;
}

static int mode_run(const char* self, const char* account, const char* dir, int n) {
  char logpath[MAX_PATH]; MINT_RESULT r; HANDLE tok; int i, falsified = 0;
  long s_before, s_peak = -1, s_after, s_after2;
  double mn = 1e9, mx = 0, sum = 0;

  snprintf(logpath, sizeof logpath, "%s\\s4uload.log", dir);
  lg = fopen(logpath, "w");
  say("probe-s4uload RUN");
  say("  account           : %s", account);
  say("  n                 : %d", n);
  say("  SeTcbPrivilege    : %s", has_privilege("SeTcbPrivilege") ? "yes" : "NO");
  if (!has_privilege("SeTcbPrivilege")) { say("REFUSED: not LocalSystem (no SeTcb) - S4U cannot mint here."); return 2; }

  s_before = logon_sessions();
  say("  logon sessions    : %ld before anything", s_before);

  /* The null case: one mint must work before load means anything. */
  tok = s4u_mint(account, &r);
  if (!tok) { say("REFUSED: the account does not mint at all - status 0x%08lx sub 0x%08lx (0xC000006A wrong password? 0xC0000064 no such user, 0xC0000072 disabled, 0xC000015B logon type not granted)",
                  (unsigned long)r.st, (unsigned long)r.sub); return 2; }
  CloseHandle(tok);
  say("  first mint        : ok, %.1f ms", r.ms);

  say("== SERIAL, %d mints, token closed each time", n);
  for (i = 0; i < n; i++) {
    tok = s4u_mint(account, &r);
    if (!tok) { say("  SERIAL mint %d FAILED: status 0x%08lx sub 0x%08lx", i, (unsigned long)r.st, (unsigned long)r.sub); falsified = 1; continue; }
    CloseHandle(tok);
    if (r.ms < mn) mn = r.ms;
    if (r.ms > mx) mx = r.ms;
    sum += r.ms;
  }
  say("  SERIAL %d: min %.1f avg %.1f max %.1f ms", n, mn, sum / n, mx);
  s_after = logon_sessions();
  say("  logon sessions    : %ld after SERIAL (before %ld)", s_after, s_before);

  say("== THREADS, %d minting at once, tokens held until all have minted", n);
  if (!run_threads(account, n, &s_peak)) falsified = 1;
  Sleep(500);
  s_after = logon_sessions();
  say("  logon sessions    : %ld after THREADS closed every token (peak %ld, before %ld)", s_after, s_peak, s_before);

  say("== PROCS, %d processes each minting once - the product's shape", n);
  if (!run_procs(self, account, dir, n)) falsified = 1;
  say("== PROCS, %d processes", 2 * n);
  if (!run_procs(self, account, dir, 2 * n)) falsified = 1;
  Sleep(1000);
  s_after2 = logon_sessions();
  say("  logon sessions    : %ld after PROCS (before %ld)", s_after2, s_before);

  /* THE LEAK ROW.  Sessions may lag a moment behind handle closes, so a
     small margin; a run that leaves fifty behind has leaked. */
  say("== VERDICT");
  say("  mints under load  : %s", falsified ? "SOME FAILED (above)" : "every one succeeded");
  say("  sessions at peak  : %ld, i.e. %ld more than baseline with %d tokens held", s_peak, s_peak - s_before, n);
  if (s_after2 > s_before + 5) { say("  LEAK: %ld logon sessions remain over the baseline after every token closed", s_after2 - s_before); falsified = 1; }
  else say("  leak              : none - %ld sessions after, %ld before", s_after2, s_before);
  say(falsified ? "RUN DONE - FALSIFIED" : "RUN DONE - ANSWERED, nothing falsified");
  if (lg) fclose(lg);
  return falsified ? 1 : 0;
}

int main(int argc, char* argv[]) {
  char self[MAX_PATH];
  GetModuleFileNameA(NULL, self, sizeof self);
  if (argc == 4 && strcmp(argv[1], "--mint") == 0) return mode_mint(argv[2], argv[3]);
  if (argc == 5 && strcmp(argv[1], "--run") == 0) {
    int n = atoi(argv[4]);
    if (n < 1 || n > 500) { printf("n must be 1..500\n"); return 2; }
    return mode_run(self, argv[2], argv[3], n);
  }
  printf("usage: probe-s4uload.exe --run <account> <dir> <n> | --mint <account> <outfile>\n");
  return 2;
}
