/* probe-lowmsys.c - trivial MSYS2 program: does the runtime initialise at Low
 * integrity, and do fork and a pipe (its shared-state users) work there?
 * Reports its own integrity level so the launch mode is measured, not assumed.
 *
 * RELEASE_1.1 43.  Build in MSYS2's MSYS bash:
 *   gcc -O2 -Wall -o probe-lowmsys.exe probe-lowmsys.c
 * Run at Low, unelevated, with msys-2.0.dll on PATH:
 *   probe-cygshared.exe --low <absolute Windows path to probe-lowmsys.exe>
 *
 * MEASURED 16 Sep 2026, twice: integrity 0x1000, fork ok (child status 7),
 * pipe ok, exit 0.  The fopen into the current user's LocalLow failed EACCES
 * (errno 13) at Low - not investigated; the relay writes no files.  The path
 * is this dev box's user profile; change it on another machine.
 *
 * WHY THAT PASS WAS NOT ENOUGH - MEASURED THE SAME DAY.  Nothing else of the
 * C:\msys64 runtime was alive, so the Low process CREATED the runtime's object
 * directory itself.  The relay never has that luck: sd, a LocalSystem MSYS2
 * process of the same runtime, holds it already.  Reproduction, unelevated:
 *   1. probe-lowmsys.exe --sleep          (Medium; stays alive 6 s)
 *   2. while it lives: probe-cygshared.exe --low <this exe>
 * Step 2 dies: "fatal error - NtCreateDirectoryObject(\BaseNamedObjects\
 * msys-2.0S5-<key>): 0xC0000022", exit 0xC0000142 - the same exit the
 * owner-elevated probe-relaydrop trials got for all three Low launches.
 */
#include <windows.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static DWORD il(void)
{
    HANDLE t;
    BYTE b[256];
    DWORD l, rid = 0;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t)) {
        if (GetTokenInformation(t, TokenIntegrityLevel, b, sizeof b, &l)) {
            PSID s = ((TOKEN_MANDATORY_LABEL *)b)->Label.Sid;
            rid = *GetSidSubAuthority(s, *GetSidSubAuthorityCount(s) - 1);
        }
        CloseHandle(t);
    }
    return rid;
}

int main(int argc, char **argv)
{
    int p[2];
    int stay = argc == 2 && strcmp(argv[1], "--sleep") == 0;
    printf("msyshello: started, pid %d, integrity 0x%lx\n", (int)getpid(), (unsigned long)il());
    FILE *f = fopen("C:/Users/Don/AppData/LocalLow/msyshello.txt", "w");
    printf("msyshello: fopen LocalLow %s (errno %d)\n", f ? "ok" : "FAILED", f ? 0 : errno);
    if (f) { fprintf(f, "written at integrity 0x%lx\n", (unsigned long)il()); fclose(f); }
    fflush(stdout);
    pid_t c = fork();
    if (c == 0) _exit(7);
    int st = -1;
    if (c > 0) waitpid(c, &st, 0);
    int pr = pipe(p);
    printf("msyshello: fork=%d child status=%d pipe=%d\n", (int)c,
           c > 0 && WIFEXITED(st) ? WEXITSTATUS(st) : -1, pr);
    fflush(stdout);
    if (stay)
        sleep(6); /* hold the runtime's objects while a Low launch is tried */
    return (c > 0 && WIFEXITED(st) && WEXITSTATUS(st) == 7 && pr == 0) ? 0 : 1;
}
