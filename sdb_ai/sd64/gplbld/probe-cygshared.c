/* probe-cygshared.c - native UCRT64, run UNELEVATED as an ordinary user.
 * Question: are the MSYS2 runtime's named shared sections - which every MSYS2
 * process on the machine uses, including the SD service's LocalSystem ones -
 * openable for WRITE by a different, unprivileged account?  If yes, an MSYS2
 * relay under a bare account would share writable state with LocalSystem, a
 * channel Linux's nobody relay does not have.
 * Opens handles only: never maps, never writes.  Prints every object it tried.
 *
 * RELEASE_1.1 43 (relay runtime choice) and 53 (the finding).  Build NATIVE,
 * from gplbld in an MSYS2 UCRT64 bash:
 *   gcc -O2 -Wall -municode -o probe-cygshared.exe probe-cygshared.c -lntdll -ladvapi32
 * Run unelevated:  probe-cygshared.exe          (as yourself, Medium)
 *                  probe-cygshared.exe --low    (same account, Low integrity)
 *                  probe-cygshared.exe --low <exe>   (run another program at Low)
 *
 * MEASURED 16 Sep 2026 as ace\Don: Medium - 6 of 8 sections open for WRITE,
 * including shared.5 in the directory holding S-1-5-18.1 (LocalSystem's, so
 * inferred to be the SD service's runtime).  Low - 0 of 8 for WRITE, READ
 * still allowed.  --low probe-lowmsys.exe ran an MSYS2 program at 0x1000.
 */
#include <windows.h>
#include <winternl.h>
#include <sddl.h>
#include <stdio.h>
#include <wchar.h>

typedef struct { UNICODE_STRING Name; UNICODE_STRING TypeName; } ODI;
NTSTATUS NTAPI NtOpenDirectoryObject(PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES);
NTSTATUS NTAPI NtQueryDirectoryObject(HANDLE, PVOID, ULONG, BOOLEAN, BOOLEAN, PULONG, PULONG);

static void owner_of(HANDLE h, wchar_t *out, size_t n)
{
    BYTE buf[4096];
    DWORD len;
    swprintf(out, n, L"?");
    if (GetKernelObjectSecurity(h, OWNER_SECURITY_INFORMATION, buf, sizeof buf, &len)) {
        PSID o; BOOL d; LPWSTR s;
        if (GetSecurityDescriptorOwner(buf, &o, &d) && ConvertSidToStringSidW(o, &s)) {
            swprintf(out, n, L"%ls", s);
            LocalFree(s);
        }
    }
}

static int opened_write = 0, sections = 0;

/* inside an msys directory every object counts; outside, only msys-named ones */
static int scan_in(const wchar_t *dir, const wchar_t *winprefix, int inside);

static int scan(const wchar_t *dir) { return scan_in(dir, L"Global\\", 0); }

static int scan_in(const wchar_t *dir, const wchar_t *winprefix, int inside)
{
    UNICODE_STRING us;
    OBJECT_ATTRIBUTES oa;
    HANDLE hd;
    RtlInitUnicodeString(&us, dir);
    InitializeObjectAttributes(&oa, &us, 0, NULL, NULL);
    NTSTATUS st = NtOpenDirectoryObject(&hd, 0x0001 /*QUERY*/, &oa);
    if (st) { wprintf(L"[%ls] cannot open directory 0x%lx\n", dir, st); return 0; }
    BYTE buf[65536];
    ULONG ctx = 0, ret;
    int seen = 0;
    while (NtQueryDirectoryObject(hd, buf, sizeof buf, TRUE, FALSE, &ctx, &ret) == 0) {
        ODI *e = (ODI *)buf;
        if (!e->Name.Buffer) continue;
        if (!inside && !wcsstr(e->Name.Buffer, L"msys")) continue;
        seen++;
        wchar_t full[512], win[512];
        swprintf(full, 512, L"%ls\\%ls", dir, e->Name.Buffer);
        swprintf(win, 512, L"%ls%ls", winprefix, e->Name.Buffer);
        int isdir = wcsncmp(e->TypeName.Buffer, L"Directory", 9) == 0;
        int issec = wcsncmp(e->TypeName.Buffer, L"Section", 7) == 0;
        if (isdir || issec || !inside)
            wprintf(L"[%ls] %-10.*ls %ls\n", dir, e->TypeName.Length / 2, e->TypeName.Buffer, e->Name.Buffer);
        if (isdir) {
            wchar_t sub[512];
            swprintf(sub, 512, L"%ls\\", win);
            seen += scan_in(full, sub, 1);
            continue;
        }
        if (issec) {
            HANDLE r, w;
            wchar_t own[128] = L"?";
            sections++;
            r = OpenFileMappingW(FILE_MAP_READ, FALSE, win);
            DWORD re = r ? 0 : GetLastError();
            w = OpenFileMappingW(FILE_MAP_WRITE, FALSE, win);
            DWORD we = w ? 0 : GetLastError();
            if (r) { owner_of(r, own, 128); CloseHandle(r); }
            if (w) { CloseHandle(w); opened_write++; }
            wprintf(L"      open READ %ls (err %lu)  open WRITE %ls (err %lu)  owner %ls\n",
                    r ? L"YES" : L"no", re, w ? L"YES" : L"no", we, own);
        }
    }
    CloseHandle(hd);
    return seen;
}

static const wchar_t *my_il(void)
{
    static wchar_t out[32];
    HANDLE t;
    BYTE b[256];
    DWORD l;
    swprintf(out, 32, L"?");
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &t)) {
        if (GetTokenInformation(t, TokenIntegrityLevel, b, sizeof b, &l)) {
            PSID s = ((TOKEN_MANDATORY_LABEL *)b)->Label.Sid;
            DWORD rid = *GetSidSubAuthority(s, *GetSidSubAuthorityCount(s) - 1);
            swprintf(out, 32, L"0x%lx%ls", rid, rid == 0x1000 ? L" (Low)" : rid == 0x2000 ? L" (Medium)" : L"");
        }
        CloseHandle(t);
    }
    return out;
}

/* Relaunch this exe under a Low-integrity copy of the caller's own token - no
   privilege needed for that, which is why it can be measured unelevated. */
static int relaunch_low(const wchar_t *other)
{
    HANDLE t, d;
    wchar_t exe[MAX_PATH], cmd[2 * MAX_PATH + 16];
    PSID low = NULL;
    TOKEN_MANDATORY_LABEL tml;
    STARTUPINFOW si = { sizeof si };
    PROCESS_INFORMATION pi;
    if (other) {
        swprintf(exe, MAX_PATH, L"%ls", other);
        swprintf(cmd, 2 * MAX_PATH + 16, L"\"%ls\"", exe);
    } else {
        GetModuleFileNameW(NULL, exe, MAX_PATH);
        swprintf(cmd, 2 * MAX_PATH + 16, L"\"%ls\" --inner", exe);
    }
    wprintf(L"launching at Low: %ls\n", cmd);
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ADJUST_DEFAULT | TOKEN_ASSIGN_PRIMARY, &t) ||
        !DuplicateTokenEx(t, 0, NULL, SecurityImpersonation, TokenPrimary, &d) ||
        !ConvertStringSidToSidW(L"S-1-16-4096", &low)) {
        wprintf(L"COULD NOT RUN: token setup %lu\n", GetLastError());
        return 2;
    }
    tml.Label.Attributes = SE_GROUP_INTEGRITY;
    tml.Label.Sid = low;
    if (!SetTokenInformation(d, TokenIntegrityLevel, &tml, sizeof tml + GetLengthSid(low)) ||
        !CreateProcessAsUserW(d, exe, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        wprintf(L"COULD NOT RUN: Low relaunch %lu\n", GetLastError());
        return 2;
    }
    fflush(stdout);
    WaitForSingleObject(pi.hProcess, 30000);
    DWORD code = 99;
    GetExitCodeProcess(pi.hProcess, &code);
    return (int)code;
}

int wmain(int argc, wchar_t **argv)
{
    wchar_t user[128];
    DWORD n = 128;
    if (argc >= 2 && wcscmp(argv[1], L"--low") == 0) {
        int rc = relaunch_low(argc >= 3 ? argv[2] : NULL);
        wprintf(L"Low child exit code: %d (0x%x)\n", rc, (unsigned)rc);
        return rc;
    }
    GetUserNameW(user, &n);
    wprintf(L"running as %ls, integrity %ls\n", user, my_il());
    int total = scan(L"\\BaseNamedObjects");
    wprintf(L"objects seen: %d, sections tried: %d, opened for WRITE: %d\n", total,
            sections, opened_write);
    if (total == 0) {
        wprintf(L"COULD NOT RUN: no MSYS2 objects found - nothing measured\n");
        return 2;
    }
    return 0;
}
