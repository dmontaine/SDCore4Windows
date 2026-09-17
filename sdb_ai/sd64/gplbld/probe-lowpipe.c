/* probe-lowpipe.c - can the RELAY create the handover named pipe at all?
 *
 * 17 Sep 26 Windows port, RELEASE_1.1 55 slice 4.  The parity build has the
 * relay be the SERVER of the pipe the authenticated session is handed, because
 * the front exits and a pipe instance dies with its last server handle.  The
 * relay runs as the bare account "sdrelay" with EVERY PRIVILEGE REMOVED and at
 * LOW INTEGRITY (RELEASE_1.1 43, win32relay.c).
 *
 * NOTHING HAS MEASURED WHETHER SUCH A TOKEN CAN CreateNamedPipe.
 * probe-relaycutover ran the relay as the ordinary caller at MEDIUM with the
 * caller's privileges, so its PASS says nothing about this.  Building slice 4
 * on the assumption would risk the whole topology: if Low cannot create the
 * pipe, the FRONT must create it and hand the relay the server handle at spawn
 * instead, which is a different design, not a bug fix.
 *
 * WHY THIS IS UNELEVATED, AND WHAT IT THEREFORE DOES NOT SAY.  Lowering your
 * OWN token's integrity and removing your OWN token's privileges need no
 * privilege - only minting ANOTHER account's token needs SeTcb.  So this runs
 * the child as the SAME USER, at Low, with zero privileges, which is the part
 * of the relay's token that could plausibly forbid a named pipe.  It does NOT
 * reproduce the bare account, its fresh S4U logon session, or session 0.  If
 * this says NO, slice 4's topology is wrong and that is decided.  If it says
 * YES, the remaining risk is the account/logon-session part, which only an
 * owner-elevated run or the cycle itself can close - so a YES here is "not
 * ruled out", not "proved on the install".
 *
 * Launched:  probe-lowpipe.exe                run the parent (drop and spawn)
 *            probe-lowpipe.exe --child <name> the child under test
 *
 * The parent runs the child TWICE and prints both, because a failure with no
 * control is not a measurement:
 *   CONTROL  the child as it is now - Medium, the caller's privileges.  This
 *            must SUCCEED, or the child's own code is what failed and the Low
 *            run says nothing.
 *   LOW      the same child under a token with every privilege REMOVED and
 *            integrity set to Low, re-read from the token to prove the drop
 *            happened rather than was merely requested.
 *
 * The child reports its OWN integrity and privilege count before it tries
 * anything, so a run where the drop silently did not happen cannot be read as
 * a Low run that worked.  It then:
 *   1. builds a SID-scoped DACL (the caller's SID only) - the shape the relay
 *      would use, since a security descriptor is memory and needs no right
 *   2. CreateNamedPipeA, single instance, duplex, overlapped
 *   3. re-opens its own pipe as a CLIENT to prove the instance is real and not
 *      merely a handle that was returned
 * Exit 0 all three, 2 could not set up, 3 the create failed, 4 the client
 * open failed, 5 the drop did not take.
 *
 * Build NATIVE, from gplbld in an MSYS2 UCRT64 bash (no msys-2.0):
 *   gcc -O2 -Wall -o probe-lowpipe.exe probe-lowpipe.c -ladvapi32
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <stdio.h>
#include <string.h>

#define PIPE_PREFIX "\\\\.\\pipe\\sd-api-"

static void win_err(const char* what) {
  DWORD e = GetLastError();
  char* text = NULL;
  FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                     FORMAT_MESSAGE_IGNORE_INSERTS,
                 NULL, e, 0, (LPSTR)&text, 0, NULL);
  printf("    %s FAILED: error %lu %s\n", what, (unsigned long)e,
         text ? text : "");
  if (text)
    LocalFree(text);
}

/* The token's integrity SID as text, and its privilege count.  Printed by the
   child BEFORE it tries anything: a Low run that was not actually Low is the
   vacuous pass this probe exists to refuse. */
static void report_token(void) {
  HANDLE tok = NULL;
  BYTE buf[8192];
  DWORD len = 0;
  char* sidtext = NULL;
  DWORD privs = 0;
  const char* label = "?";

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
    win_err("OpenProcessToken");
    return;
  }
  if (GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof buf, &len)) {
    TOKEN_MANDATORY_LABEL* tml = (TOKEN_MANDATORY_LABEL*)buf;
    if (ConvertSidToStringSidA(tml->Label.Sid, &sidtext)) {
      if (strcmp(sidtext, "S-1-16-4096") == 0)
        label = "Low";
      else if (strcmp(sidtext, "S-1-16-8192") == 0)
        label = "Medium";
      else if (strcmp(sidtext, "S-1-16-12288") == 0)
        label = "High";
      else if (strcmp(sidtext, "S-1-16-16384") == 0)
        label = "System";
    }
  }
  len = 0;
  if (GetTokenInformation(tok, TokenPrivileges, buf, sizeof buf, &len))
    privs = ((TOKEN_PRIVILEGES*)buf)->PrivilegeCount;

  printf("    token: integrity %s (%s), %lu privilege(s)\n", label,
         sidtext ? sidtext : "?", (unsigned long)privs);
  if (sidtext)
    LocalFree(sidtext);
  CloseHandle(tok);
}

/* Non-zero when this process's token is Low with no privilege left - what the
   LOW run claims to be.  The child uses it to refuse a mislabelled run. */
static int is_low_and_bare(void) {
  HANDLE tok = NULL;
  BYTE buf[8192];
  DWORD len = 0;
  char* sidtext = NULL;
  int low = 0;
  int bare = 0;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
    return 0;
  if (GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof buf, &len)) {
    TOKEN_MANDATORY_LABEL* tml = (TOKEN_MANDATORY_LABEL*)buf;
    if (ConvertSidToStringSidA(tml->Label.Sid, &sidtext)) {
      low = strcmp(sidtext, "S-1-16-4096") == 0;
      LocalFree(sidtext);
    }
  }
  len = 0;
  if (GetTokenInformation(tok, TokenPrivileges, buf, sizeof buf, &len))
    bare = ((TOKEN_PRIVILEGES*)buf)->PrivilegeCount == 0;
  CloseHandle(tok);
  return low && bare;
}

/* This process's user SID as text - the DACL the relay would build names the
   party allowed to open the client end. */
static int my_sid(char* out, size_t outlen) {
  HANDLE tok = NULL;
  BYTE buf[1024];
  DWORD len = 0;
  char* text = NULL;
  int ok = 0;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
    return 0;
  if (GetTokenInformation(tok, TokenUser, buf, sizeof buf, &len) &&
      ConvertSidToStringSidA(((TOKEN_USER*)buf)->User.Sid, &text)) {
    if (strlen(text) < outlen) {
      strcpy(out, text);
      ok = 1;
    }
    LocalFree(text);
  }
  CloseHandle(tok);
  return ok;
}

/* ====================================================================== */

static int child(const char* name, int expect_low) {
  char sid[256];
  char sddl[512];
  SECURITY_ATTRIBUTES sa;
  PSECURITY_DESCRIPTOR sd = NULL;
  HANDLE pipe;
  HANDLE cli;
  int rc = 0;

  printf("  CHILD %s\n", name);
  report_token();
  if (expect_low && !is_low_and_bare()) {
    printf("    REFUSED: this run was meant to be Low with 0 privileges and "
           "is not - the drop did not take, so nothing below would measure "
           "what it claims\n");
    return 5;
  }

  if (!my_sid(sid, sizeof sid)) {
    win_err("TokenUser");
    return 2;
  }
  /* D:(A;;GA;;;<me>) - the caller only.  The relay's real DACL names
     LocalSystem, the party that opens the client end; the question here is
     whether a Low token may create a pipe carrying an explicit DACL at all,
     and that is the same question either way. */
  if (snprintf(sddl, sizeof sddl, "D:(A;;GA;;;%s)", sid) >= (int)sizeof sddl) {
    printf("    SDDL too long\n");
    return 2;
  }
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(sddl, SDDL_REVISION_1,
                                                            &sd, NULL)) {
    win_err("ConvertStringSecurityDescriptor");
    return 2;
  }
  printf("    DACL: %s\n", sddl);

  sa.nLength = sizeof sa;
  sa.lpSecurityDescriptor = sd;
  sa.bInheritHandle = FALSE;

  pipe = CreateNamedPipeA(name, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                          PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                          1, 65536, 65536, 0, &sa);
  if (pipe == INVALID_HANDLE_VALUE) {
    win_err("CreateNamedPipe");
    LocalFree(sd);
    return 3;
  }
  printf("    CreateNamedPipe OK (single instance, duplex, overlapped)\n");

  /* A handle is not an instance until something can connect to it. */
  cli = CreateFileA(name, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING,
                    0, NULL);
  if (cli == INVALID_HANDLE_VALUE) {
    win_err("CreateFile(client end)");
    rc = 4;
  } else {
    printf("    client end opened: the instance is real\n");
    CloseHandle(cli);
  }
  CloseHandle(pipe);
  LocalFree(sd);
  return rc;
}

/* ====================================================================== */

/* Run this executable again with --child, optionally under a token dropped to
   Low with every privilege removed.  Neither needs a privilege: they are this
   process's own token. */
static int run_child(const char* name, int drop, DWORD* code) {
  char self[MAX_PATH];
  char cmd[MAX_PATH + 256];
  HANDLE tok = NULL;
  HANDLE dup = NULL;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  BYTE buf[8192];
  DWORD len = 0;
  PSID low = NULL;
  TOKEN_MANDATORY_LABEL tml;
  int ok = 0;

  ZeroMemory(&si, sizeof si);
  ZeroMemory(&pi, sizeof pi);
  si.cb = sizeof si;

  if (GetModuleFileNameA(NULL, self, sizeof self) == 0) {
    win_err("GetModuleFileName");
    return 0;
  }
  snprintf(cmd, sizeof cmd, "\"%s\" --child %s%s", self, name,
           drop ? " --expect-low" : "");

  if (!drop) {
    if (!CreateProcessA(self, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
      win_err("CreateProcess(control)");
      return 0;
    }
  } else {
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_DUPLICATE | TOKEN_QUERY,
                          &tok)) {
      win_err("OpenProcessToken");
      return 0;
    }
    if (!DuplicateTokenEx(tok, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation,
                          TokenPrimary, &dup)) {
      win_err("DuplicateTokenEx");
      goto done;
    }
    /* Every privilege REMOVED, not disabled - win32relay.c's rule. */
    if (GetTokenInformation(dup, TokenPrivileges, buf, sizeof buf, &len)) {
      TOKEN_PRIVILEGES* tp = (TOKEN_PRIVILEGES*)buf;
      DWORD i;
      for (i = 0; i < tp->PrivilegeCount; i++)
        tp->Privileges[i].Attributes = SE_PRIVILEGE_REMOVED;
      if (tp->PrivilegeCount > 0 &&
          !AdjustTokenPrivileges(dup, FALSE, tp, 0, NULL, NULL)) {
        win_err("AdjustTokenPrivileges");
        goto done;
      }
    }
    if (!ConvertStringSidToSidA("S-1-16-4096", &low)) {
      win_err("ConvertStringSidToSid(Low)");
      goto done;
    }
    tml.Label.Attributes = SE_GROUP_INTEGRITY;
    tml.Label.Sid = low;
    if (!SetTokenInformation(dup, TokenIntegrityLevel, &tml,
                             (DWORD)(sizeof tml + GetLengthSid(low)))) {
      win_err("SetTokenInformation(Low)");
      goto done;
    }
    if (!CreateProcessAsUserA(dup, self, cmd, NULL, NULL, TRUE, 0, NULL, NULL,
                              &si, &pi)) {
      win_err("CreateProcessAsUser(Low)");
      goto done;
    }
  }

  WaitForSingleObject(pi.hProcess, 30000);
  GetExitCodeProcess(pi.hProcess, code);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  ok = 1;

done:
  if (low)
    LocalFree(low);
  if (dup)
    CloseHandle(dup);
  if (tok)
    CloseHandle(tok);
  return ok;
}

int main(int argc, char** argv) {
  char name[128];
  DWORD control = 0xFFFFFFFF;
  DWORD lowrun = 0xFFFFFFFF;
  int expect_low = 0;
  int i;

  setvbuf(stdout, NULL, _IONBF, 0);

  if (argc >= 3 && strcmp(argv[1], "--child") == 0) {
    for (i = 3; i < argc; i++)
      if (strcmp(argv[i], "--expect-low") == 0)
        expect_low = 1;
    return child(argv[2], expect_low);
  }

  printf("probe-lowpipe: can a Low-integrity, zero-privilege process create "
         "the handover pipe?\n");
  printf("  (RELEASE_1.1 55 slice 4.  Unelevated, same user - see the header "
         "for what that does NOT say.)\n\n");

  snprintf(name, sizeof name, "%sprobe-%lu-control", PIPE_PREFIX,
           (unsigned long)GetCurrentProcessId());
  printf("CONTROL run (Medium, this process's privileges) - must SUCCEED, or "
         "the child's own code is what failed\n");
  if (!run_child(name, 0, &control)) {
    printf("\nRESULT: could not run the control at all\n");
    return 2;
  }
  printf("  exit %lu\n\n", (unsigned long)control);

  snprintf(name, sizeof name, "%sprobe-%lu-low", PIPE_PREFIX,
           (unsigned long)GetCurrentProcessId());
  printf("LOW run (integrity Low, every privilege REMOVED)\n");
  if (!run_child(name, 1, &lowrun)) {
    printf("\nRESULT: could not run the Low child at all\n");
    return 2;
  }
  printf("  exit %lu\n\n", (unsigned long)lowrun);

  if (control != 0) {
    printf("RESULT: INCONCLUSIVE - the CONTROL failed (exit %lu), so the Low "
           "run measures nothing\n", (unsigned long)control);
    return 2;
  }
  if (lowrun == 0) {
    printf("RESULT: YES - a Low, zero-privilege process created the pipe with "
           "an explicit DACL and a client opened it.  Slice 4's topology (the "
           "RELAY is the server) is not ruled out by the token.  The bare "
           "account and its session-0 logon session are still untested.\n");
    return 0;
  }
  printf("RESULT: NO - the Low run exited %lu.  Slice 4 must instead have the "
         "FRONT create the pipe and hand the relay the server handle at "
         "spawn.\n", (unsigned long)lowrun);
  return 1;
}
/* END-CODE */
