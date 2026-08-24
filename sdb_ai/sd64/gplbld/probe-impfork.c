/* probe-impfork.c - the two things step 14 cannot decide without them.
 *
 * 24 Aug 26 Windows port.  Built and run by probe-impfork.ps1.
 * PROJECT_STATUS.md section 7 step 14, after run b28.
 *
 * WHY THIS EXISTS AND WHY IT IS NOT AN EDIT TO probe-impersonate.c.  That
 * probe's result is cited in PROJECT_STATUS as the evidence shape (b) rests
 * on, so it stays exactly as it was and stays re-runnable.  This one asks two
 * further questions, and carries probe-impersonate's whole measurement as its
 * own control so the comparison is inside a single run.
 *
 * ---------------------------------------------------------------------------
 * QUESTION 1 - THE ONE PROJECT_STATUS ASKS FOR.  Does impersonation still
 * govern open() IN A fork()ed AND exec()d CYGWIN CHILD?
 *
 * probe-impersonate measured a STANDALONE program started by schtasks, i.e.
 * with cmd.exe - not a Cygwin process - as its parent, so the MSYS2 runtime
 * initialised itself from its own process token.  An API session is neither:
 * sdwind.c:491 fork()s and execl()s it, so the runtime's idea of the user is
 * inherited through Cygwin's own child startup rather than derived afresh.
 * That difference is untested, and step 14 names re-testing it as the cheapest
 * thing that could overturn shape (b).
 *
 * ---------------------------------------------------------------------------
 * QUESTION 2 - AND IT IS ABOUT b28's INSTRUMENT, NOT ABOUT SD.  When a file is
 * CREATED while impersonating, whose name goes on it?
 *
 * verify-apiidentity's ownership probe read Get-Acl.Owner on a record written
 * by the API session, found NT AUTHORITY\SYSTEM, and concluded that the
 * K$ASSUME.USER switch has no effect.  Its control was that a record written
 * by a LOCAL elevated session read GITORLI\don instead.
 *
 * ***THAT CONTROL DOES NOT SEPARATE THE TWO EXPLANATIONS.*** In both readings
 * the owner equals the identity of the PROCESS that wrote it - the local
 * session's process is don's, the API session's process is the service's.  So
 * it is equally consistent with:
 *
 *   (i)  the impersonation is not in effect at all, or
 *   (ii) the impersonation IS in effect - open() is governed, access is the
 *        user's - but the runtime stamps a NEW file's owner from its own
 *        cached idea of the user, which fork() carried in from the service
 *        and which ImpersonateLoggedOnUser does not touch.
 *
 * If (ii) holds, b28 measured the runtime's owner-stamping and not the
 * session's effective token, and step 14's conclusion has to be rewritten.
 * ONE RUN SEPARATES THEM: impersonate, then in the SAME breath try to open a
 * file the user may not read AND create a file, and report both.
 *
 *   forbidden refused + created file owned by SYSTEM -> (ii).  Access is
 *       governed; ownership is not the instrument it was taken for.
 *   forbidden OPENED  + created file owned by SYSTEM -> (i).  b28 stands and
 *       shape (b) buys nothing in a forked child.
 *
 * THE RUNTIME'S OWN UID IS PRINTED THROUGHOUT, before, during and after the
 * switch.  getuid()/geteuid() answer from the cached user that mechanism (ii)
 * is about, so if they do not move while the THREAD TOKEN does, that is the
 * mechanism visible directly rather than inferred.
 *
 * ---------------------------------------------------------------------------
 * CONTROLS, and they are most of the file.  Per leg:
 *
 *   control A, before impersonating   both opens must SUCCEED, or a refusal
 *                                     later says nothing about the token
 *   control B, after RevertToSelf     the forbidden open must SUCCEED again,
 *                                     or the refusal may have been a lock or
 *                                     a bad path
 *   ownership control                 a file is created BEFORE impersonating
 *                                     too.  Without it, "owned by SYSTEM"
 *                                     could mean the fixture forces it.
 *   configuration control             the parent runs the identical
 *                                     measurement DIRECTLY after the child
 *                                     has finished, reproducing
 *                                     probe-impersonate's configuration with
 *                                     this binary and these fixtures.  A
 *                                     difference between the two rows is then
 *                                     the fork, and nothing else.
 *
 * A leg whose controls do not hold is reported VOID and does not reach a
 * verdict.  CLAUDE.md: a test that passes because it did nothing must fail.
 *
 * ORDERING IS DELIBERATE: the CHILD runs FIRST, while this process has never
 * impersonated, so nothing the parent did can be carried into it.
 *
 * BUILT WITH THE MSYS2 gcc, not UCRT64 - the runtime is the subject.
 *
 * ---------------------------------------------------------------------------
 * QUESTION 4, ADDED 24 Aug 26 - THE CLASS FIX, AND IT IS THE LAST UNKNOWN IN
 * STEP 14's DECISION.  Q3 settled that fork() is the one thing that drops the
 * impersonation.  That leaves the owner choosing between re-impersonating
 * after each fork (narrow: fixes the LOGTO group check, leaves PHANTOM and SH
 * dropping it silently) and cygwin_internal(CW_SET_EXTERNAL_TOKEN) (class:
 * covers all of them), which PROJECT_STATUS records as "unproven here".
 *
 * Q4 proves or disproves it, WITHOUT TOUCHING sd.exe - this file is on
 * assert-current's $neverShipped list, so the leg costs no cycle.  It measures
 * TWO forms, because the bare call may be a no-op by design: it REGISTERS a
 * token for the runtime to adopt at its next user-context change, and
 * register-then-seteuid is the sequence Cygwin's own sshd and su use.
 * Measuring only the bare call could report "the class fix does not work"
 * when what was measured is "the call alone changes nothing".
 *
 * Its control is a PLAIN fork taken first, which must LOSE the identity; if
 * it does not, the run has not reproduced the defect and the leg is VOID.
 *
 * ---------------------------------------------------------------------------
 * EXIT CODES.  2 usage, 3 VOID, 4 a required call failed, and on a completed
 * measurement 8 + 1 if access was governed + 2 if ownership tracked the
 * impersonated user + 4 if the external token carried it across fork() in
 * either form.  So 8..15, decoded in words by the parent.  R_EXTTOK and
 * R_CALL are both 4 and do not collide: R_CALL is only ever returned bare,
 * without R_BASE.
 */

/* WIN32_LEAN_AND_MEAN keeps windows.h from dragging in winsock.h, which
   conflicts with the POSIX <sys/socket.h> the Q3 sequence needs.  Mixing the
   two header families is the usual way this file type fails to build. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ntsecapi.h>
#include <aclapi.h>
#include <sddl.h>    /* ConvertSidToStringSidA - implicit here is an error */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <dirent.h>
#include <signal.h>
#include <pwd.h>
/* cygwin_internal() and CW_SET_EXTERNAL_TOKEN - Q4's whole subject.  It is
   the MSYS2 runtime's own header, so it goes AFTER windows.h: it needs the
   Win32 HANDLE type the external-token call is given. */
#include <sys/cygwin.h>

#ifndef O_BINARY
#define O_BINARY 0
#endif

#define R_USAGE 2
#define R_VOID  3
#define R_CALL  4
#define R_BASE  8
#define R_ACCESS 1
#define R_OWNER  2
/* Bit 4 was free: completed codes were 8..11 and R_USAGE/R_VOID/R_CALL are
   only ever returned bare, without R_BASE.  Q4 sets it when the external
   token carried the impersonation across fork() in EITHER form. */
#define R_EXTTOK 4

static void say(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
  printf("\n");
  fflush(stdout);
}

static const char *winerr(DWORD e) {
  static char buf[256];
  DWORD n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
                           FORMAT_MESSAGE_IGNORE_INSERTS,
                           NULL, e, 0, buf, sizeof(buf) - 1, NULL);
  if (n == 0) {
    snprintf(buf, sizeof(buf), "error %lu", (unsigned long)e);
    return buf;
  }
  while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = '\0';
  return buf;
}

/* DOMAIN\name for a SID, or a printable reason it could not be resolved.
   Callers must not put two of these in one printf - one static buffer. */
static const char *sid_name(PSID sid) {
  static char out[256];
  char name[128], dom[128];
  DWORD nlen = sizeof(name), dlen = sizeof(dom);
  SID_NAME_USE use;

  out[0] = '\0';
  if (sid == NULL) {
    snprintf(out, sizeof(out), "(no SID)");
    return out;
  }
  if (!LookupAccountSidA(NULL, sid, name, &nlen, dom, &dlen, &use)) {
    LPSTR s = NULL;
    if (ConvertSidToStringSidA(sid, &s)) {
      snprintf(out, sizeof(out), "(unresolved SID %s)", s);
      LocalFree(s);
    } else {
      snprintf(out, sizeof(out), "(LookupAccountSid failed: %s)",
               winerr(GetLastError()));
    }
    return out;
  }
  snprintf(out, sizeof(out), "%s\\%s", dom, name);
  return out;
}

static const char *token_user(HANDLE tok) {
  static char out[256];
  BYTE buf[512];
  DWORD len = 0;

  if (!GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &len)) {
    snprintf(out, sizeof(out), "(GetTokenInformation failed: %s)",
             winerr(GetLastError()));
    return out;
  }
  snprintf(out, sizeof(out), "%s", sid_name(((TOKEN_USER *)buf)->User.Sid));
  return out;
}

/* The owner recorded on an object, read with the Windows API rather than
   inferred.  Returns a printable name; sets *ok to 0 if it could not be read,
   so an unreadable owner is never silently treated as a mismatch. */
static const char *file_owner(const char *path, int *ok) {
  static char out[256];
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  DWORD rc;

  *ok = 0;
  rc = GetNamedSecurityInfoA(path, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
                             &owner, NULL, NULL, NULL, &sd);
  if (rc != ERROR_SUCCESS) {
    snprintf(out, sizeof(out), "(cannot read owner of %s: %s)", path,
             winerr(rc));
    return out;
  }
  snprintf(out, sizeof(out), "%s", sid_name(owner));
  *ok = 1;
  if (sd != NULL) LocalFree(sd);
  return out;
}

/* Try to open a path and say plainly what happened.  1 opened, 0 refused. */
static int try_open(const char *what, const char *path) {
  int fd = open(path, O_RDONLY | O_BINARY);
  if (fd >= 0) {
    close(fd);
    say("    %-36s OPENED", what);
    return 1;
  }
  say("    %-36s refused - errno %d (%s)", what, errno, strerror(errno));
  return 0;
}

/* Create a file with the SAME call SD uses - POSIX open(), through the MSYS2
   runtime - not CreateFile.  The runtime is the subject.  1 created. */
static int try_create(const char *what, const char *path) {
  int fd;
  unlink(path); /* a leftover would be owned by whoever made it last */
  fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_BINARY, 0600);
  if (fd >= 0) {
    if (write(fd, "x\n", 2) != 2)
      say("    %-36s created but the write was short", what);
    close(fd);
    say("    %-36s CREATED", what);
    return 1;
  }
  say("    %-36s not created - errno %d (%s)", what, errno, strerror(errno));
  return 0;
}

static void show_uids(const char *when) {
  say("    runtime uid %-24s uid=%ld euid=%ld", when, (long)getuid(),
      (long)geteuid());
}

/* ==========================================================================
   Q3 - DOES THE SWITCH SURVIVE WHAT A SESSION DOES NEXT?

   Q1 and Q2 create their file IMMEDIATELY after impersonating.  A real API
   session does not: APISRVR sends the SCRAM response over the socket, reads
   the next request, runs vb.account (which reads VOC, may execute ON.LOGTO,
   and switches account), then vb.open, then vb.write.  b28 plus this probe's
   Q1/Q2 say the thread is NOT impersonating by the time that write lands, and
   nothing in gplsrc reverts it - so something the session does in between
   drops it, and the runtime is the only candidate left.

   THIS IS A BISECT, NOT A GUESS.  Each operation below is something that flow
   actually performs.  After EVERY one the thread token is read back AND a file
   is created, so the step where the two stop agreeing with the target names
   the culprit.  Both instruments are kept because they can disagree: the token
   readback is what Windows thinks, the file owner is what the runtime did.

   A step that changes nothing is as much a result as one that does, so every
   row is printed whether or not it moved.
   ========================================================================== */

#define Q3_OPS 14

static char q3_note[Q3_OPS][192];
static char q3_who[Q3_OPS][256];
static int  q3_state[Q3_OPS];   /* 1 impersonating, 0 not, -1 unreadable */
static int  q3_made[Q3_OPS];
static char q3_path[Q3_OPS][MAX_PATH];
static int  q3_count = 0;

static int q3_sock_a = -1, q3_sock_b = -1;

/* The LSA connection the S4U token came from, handed in by measure() so step
   12 can close it the way win32s4u.c does. */
static LSA_HANDLE q3_hlsa = NULL;

static const char *q3_label(int i) {
  switch (i) {
    case 0:  return "baseline (nothing yet)";
    case 1:  return "usleep(1000)";
    case 2:  return "stat() a directory";
    case 3:  return "open/read/close a file";
    case 4:  return "opendir/readdir";
    case 5:  return "chdir() - the account switch";
    case 6:  return "getcwd()";
    case 7:  return "getpwuid(getuid())";
    case 8:  return "getpwnam(target)";
    case 9:  return "socket send/recv - the request loop";
    case 10: return "select() on that socket";
    case 11: return "raise(SIGUSR1) with a handler";
    /* STEP 12 IS THE ONE THE PRODUCT DOES AND NEITHER PROBE DID.
       win32s4u.c's exit_assume: runs on the SUCCESS path too (ok = 1 falls
       into it) and deregisters the LSA connection the S4U token came from.
       Both probes leak hlsa instead, so this is a real difference between the
       instrument and the thing it models - exactly where a probe that works
       and a product that does not can diverge.  It goes BEFORE fork because
       fork is already known to be destructive and would mask it. */
    case 12: return "LsaDeregisterLogonProcess (win32s4u)";
    case 13: return "fork() + waitpid";
    default: return "(no such step)";
  }
}

static volatile sig_atomic_t q3_signalled = 0;
static void q3_onsig(int sig) { (void)sig; q3_signalled = 1; }

/* A connected loopback TCP pair.  MSYS2 emulates AF_UNIX over TCP anyway
   (linuxio.c:748), and the API session's fd 0 is a real TCP socket, so this is
   the faithful shape.  0 on success. */
static int q3_make_pair(void) {
  int lis = -1;
  struct sockaddr_in sa;
  socklen_t len = sizeof(sa);

  if ((lis = socket(AF_INET, SOCK_STREAM, 0)) < 0) return -1;
  memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET;
  sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  sa.sin_port = 0;
  if (bind(lis, (struct sockaddr *)&sa, sizeof(sa)) < 0) goto fail;
  if (listen(lis, 1) < 0) goto fail;
  if (getsockname(lis, (struct sockaddr *)&sa, &len) < 0) goto fail;
  if ((q3_sock_a = socket(AF_INET, SOCK_STREAM, 0)) < 0) goto fail;
  if (connect(q3_sock_a, (struct sockaddr *)&sa, sizeof(sa)) < 0) goto fail;
  if ((q3_sock_b = accept(lis, NULL, NULL)) < 0) goto fail;
  close(lis);
  return 0;
fail:
  if (lis >= 0) close(lis);
  if (q3_sock_a >= 0) { close(q3_sock_a); q3_sock_a = -1; }
  return -1;
}

/* Perform one operation and say what it ACTUALLY did, not what it meant to -
   a step that silently no-opped would otherwise read as "this is harmless". */
static void q3_do(int i, const char *user, const char *dir, const char *file,
                  char *note, size_t n) {
  switch (i) {
    case 0:
      snprintf(note, n, "nothing - this row is the control");
      break;
    case 1:
      usleep(1000);
      snprintf(note, n, "slept 1000us");
      break;
    case 2: {
      struct stat st;
      if (stat(dir, &st) == 0)
        snprintf(note, n, "stat ok, mode 0%o", (unsigned)(st.st_mode & 07777));
      else
        snprintf(note, n, "stat failed - errno %d (%s)", errno, strerror(errno));
      break;
    }
    case 3: {
      int fd = open(file, O_RDONLY | O_BINARY);
      if (fd >= 0) {
        char b[64];
        ssize_t got = read(fd, b, sizeof(b));
        close(fd);
        snprintf(note, n, "read %ld bytes", (long)got);
      } else {
        snprintf(note, n, "open failed - errno %d (%s)", errno, strerror(errno));
      }
      break;
    }
    case 4: {
      DIR *d = opendir(dir);
      int cnt = 0;
      if (d != NULL) {
        while (readdir(d) != NULL) cnt++;
        closedir(d);
        snprintf(note, n, "listed %d entries", cnt);
      } else {
        snprintf(note, n, "opendir failed - errno %d (%s)", errno, strerror(errno));
      }
      break;
    }
    case 5:
      if (chdir(dir) == 0) snprintf(note, n, "chdir into the writable fixture");
      else snprintf(note, n, "chdir failed - errno %d (%s)", errno, strerror(errno));
      break;
    case 6: {
      char cwd[MAX_PATH];
      if (getcwd(cwd, sizeof(cwd)) != NULL) snprintf(note, n, "cwd is %.150s", cwd);
      else snprintf(note, n, "getcwd failed - errno %d", errno);
      break;
    }
    case 7: {
      struct passwd *pw = getpwuid(getuid());
      snprintf(note, n, "getpwuid -> %s", pw ? pw->pw_name : "(null)");
      break;
    }
    case 8: {
      struct passwd *pw = getpwnam(user);
      snprintf(note, n, "getpwnam(%s) -> %s", user,
               pw ? pw->pw_name : "(null - not in the runtime's user db)");
      break;
    }
    case 9: {
      if (q3_sock_a < 0 && q3_make_pair() != 0) {
        snprintf(note, n, "could not make a loopback pair - errno %d", errno);
        break;
      }
      if (send(q3_sock_a, "ping", 4, 0) != 4) {
        snprintf(note, n, "send failed - errno %d (%s)", errno, strerror(errno));
      } else {
        char b[8];
        ssize_t got = recv(q3_sock_b, b, sizeof(b), 0);
        snprintf(note, n, "sent 4, received %ld", (long)got);
      }
      break;
    }
    case 10: {
      fd_set rfds;
      struct timeval tv;
      int r;
      if (q3_sock_a < 0) { snprintf(note, n, "no socket - step 9 did not run"); break; }
      FD_ZERO(&rfds);
      FD_SET(q3_sock_b, &rfds);
      tv.tv_sec = 0; tv.tv_usec = 1000;
      r = select(q3_sock_b + 1, &rfds, NULL, NULL, &tv);
      snprintf(note, n, "select returned %d", r);
      break;
    }
    case 11: {
      void (*old)(int) = signal(SIGUSR1, q3_onsig);
      q3_signalled = 0;
      raise(SIGUSR1);
      usleep(2000);   /* Cygwin delivers on its own signal thread */
      snprintf(note, n, "handler %s", q3_signalled ? "ran" : "DID NOT run");
      if (old != SIG_ERR) signal(SIGUSR1, old);
      break;
    }
    case 12: {
      if (q3_hlsa == NULL) {
        snprintf(note, n, "no LSA handle to deregister - nothing was done");
      } else {
        NTSTATUS ds = LsaDeregisterLogonProcess(q3_hlsa);
        q3_hlsa = NULL;   /* not usable again either way */
        snprintf(note, n, "deregistered, NTSTATUS 0x%08lx", (unsigned long)ds);
      }
      break;
    }
    case 13: {
      pid_t p = fork();
      if (p == 0) _exit(0);
      if (p < 0) {
        snprintf(note, n, "fork failed - errno %d (%s)", errno, strerror(errno));
      } else {
        int st = 0;
        waitpid(p, &st, 0);
        snprintf(note, n, "forked pid %ld, reaped", (long)p);
      }
      break;
    }
    default:
      snprintf(note, n, "(no such step)");
      break;
  }
}

/* Runs WHILE IMPERSONATING.  Records only; the owners are read afterwards, by
   q3_report(), because reading a DACL is itself something the switch could
   refuse and that would confound the reading. */
static void q3_run(const char *user, const char *writedir, const char *file) {
  char keepcwd[MAX_PATH];
  int i;

  if (getcwd(keepcwd, sizeof(keepcwd)) == NULL) keepcwd[0] = '\0';
  q3_count = 0;

  for (i = 0; i < Q3_OPS; i++) {
    HANDLE th = NULL;

    q3_do(i, user, writedir, file, q3_note[i], sizeof(q3_note[i]));

    /* What Windows thinks.  ERROR_NO_TOKEN is the switch being GONE, and it is
       told apart from a token that cannot be read for some other reason. */
    if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &th)) {
      snprintf(q3_who[i], sizeof(q3_who[i]), "%s", token_user(th));
      q3_state[i] = 1;
      CloseHandle(th);
    } else if (GetLastError() == ERROR_NO_TOKEN) {
      snprintf(q3_who[i], sizeof(q3_who[i]), "(no thread token - NOT impersonating)");
      q3_state[i] = 0;
    } else {
      snprintf(q3_who[i], sizeof(q3_who[i]), "(OpenThreadToken failed: %s)",
               winerr(GetLastError()));
      q3_state[i] = -1;
    }

    /* What the runtime DID.  Created with the same POSIX open() as SD's. */
    snprintf(q3_path[i], sizeof(q3_path[i]), "%s\\q3-%02d", writedir, i);
    unlink(q3_path[i]);
    {
      int fd = open(q3_path[i], O_WRONLY | O_CREAT | O_EXCL | O_BINARY, 0600);
      if (fd >= 0) { q3_made[i] = 1; close(fd); }
      else         { q3_made[i] = 0; }
    }
    q3_count++;
  }

  if (keepcwd[0] != '\0') { if (chdir(keepcwd) != 0) { /* reported below */ } }
}

/* Called AFTER RevertToSelf. */
static void q3_report(const char *want) {
  int i, lost = -1;

  say("Q3 - DOES THE SWITCH SURVIVE WHAT A SESSION DOES NEXT?");
  say("  target is %s.  Each row: the op, then the thread token and the owner", want);
  say("  of a file created straight after it.");
  say("");
  say("   # operation                            token after      owner of file made after");
  say("   - ------------------------------------ ---------------- -------------------------");

  for (i = 0; i < q3_count; i++) {
    int ok = 0;
    const char *owner = q3_made[i] ? file_owner(q3_path[i], &ok) : "(not created)";
    char shortwho[32];

    if (q3_state[i] == 1) {
      snprintf(shortwho, sizeof(shortwho), "%.31s",
               (strcmp(q3_who[i], want) == 0) ? "target" : q3_who[i]);
    } else if (q3_state[i] == 0) {
      snprintf(shortwho, sizeof(shortwho), "NONE");
    } else {
      snprintf(shortwho, sizeof(shortwho), "unreadable");
    }

    say("  %2d %-36s %-16s %s", i, q3_label(i), shortwho, owner);

    if (lost < 0 && q3_made[i] && ok && strcmp(owner, want) != 0) lost = i;
    if (lost < 0 && q3_state[i] != 1) lost = i;
  }
  say("");
  for (i = 0; i < q3_count; i++) say("   %2d %-36s %s", i, q3_label(i), q3_note[i]);
  say("");

  if (lost < 0) {
    say("  THE SWITCH SURVIVED EVERY STEP.  Nothing a session does here drops");
    say("  it, so the thing that drops it in a real API session is NOT in this");
    say("  list - and the next move is (b), reporting ImpersonatingUser() from");
    say("  inside a live session, which costs a cycle.");
  } else {
    say("  *** THE SWITCH IS LOST AT STEP %d: %s ***", lost, q3_label(lost));
    say("  That step is the culprit, and it is reachable without touching");
    say("  sd.exe.  Everything before it held.");
  }
  say("");
}

/* ==========================================================================
   Q4 - CAN THE RUNTIME BE MADE TO CARRY THE TOKEN ACROSS fork()?

   Q3 settled that fork() is the ONE thing that drops the impersonation.
   PROJECT_STATUS section 7 step 14 turns that into a choice that is the
   owner's, and one half of it is unmeasured:

     NARROW  re-impersonate after each fork().  Fixes the LOGTO group check
             and leaves PHANTOM (op_kernel.c:735) and SH (op_sh.c:379)
             dropping it silently, exactly as they do today.
     CLASS   cygwin_internal(CW_SET_EXTERNAL_TOKEN) - the runtime carries the
             token itself, so every fork() is covered.  Recorded as "unproven
             here", and it is the ONLY unknown left in the decision.

   THIS LEG SETTLES THE CLASS OPTION AND IT DOES NOT TOUCH sd.exe, so it costs
   no cycle: probe-impfork.c is on assert-current's $neverShipped list.

   TWO FORMS ARE MEASURED, BECAUSE ONE OF THEM MAY BE A NO-OP BY DESIGN.
   CW_SET_EXTERNAL_TOKEN REGISTERS a token for the runtime to adopt at its
   next user-context change; it is not itself documented to perform one.  The
   sequence Cygwin's own sshd and su use is register-THEN-seteuid.  Measuring
   only the bare call could therefore report "the class fix does not work"
   when what was actually measured is "the call alone changes nothing", and
   that is precisely the false verdict CLAUDE.md's instrument rule is about.

     form 1   CW_SET_EXTERNAL_TOKEN, then fork
     form 2   CW_SET_EXTERNAL_TOKEN, then seteuid(target), then fork

   THE CONTROL IS ROW 1 AND IT IS WHAT MAKES THE LEG A MEASUREMENT.  Before
   either form is tried, a PLAIN fork is taken while impersonating.  It must
   LOSE the identity.  If it does not, this run has not reproduced the defect
   at all, and a later row reading "survived" would be evidence of nothing -
   so the leg is declared VOID rather than passing.  A test that passes
   because it did nothing must fail.

   EVERY ROW READS BOTH INSTRUMENTS, not one: the thread token Windows
   reports, AND the owner of a file created through the runtime in the same
   breath.  Step 14 needs the second because the first can hold while the file
   layer still writes as the service - that was b28's whole confusion - so a
   form only counts as carrying the identity when BOTH say the target.
   ========================================================================== */

#define Q4_ROWS 7
static char q4_note[Q4_ROWS][256];
static char q4_who[Q4_ROWS][256];
static char q4_uids[Q4_ROWS][96];
static char q4_path[Q4_ROWS][MAX_PATH];
static int  q4_state[Q4_ROWS];      /* 1 token read, 0 none, -1 unreadable */
static int  q4_made[Q4_ROWS];
static int  q4_count = 0;
static uid_t q4_target_uid = (uid_t)-1;
static int  q4_seteuid_rc = -2;     /* -2 = not attempted */
static int  q4_seteuid_errno = 0;
/* The euid AT THE MOMENT seteuid() was called.  If the target equals it, the
   call had nothing to do: Cygwin returns 0 from a fast path without touching
   the user context, so the runtime never adopts the registered token and
   form 2 is UNMEASURED rather than failed.  Without this the --q4check mode -
   which necessarily targets its own uid - would report a confident "lost"
   for a form it never exercised. */
static uid_t q4_euid_at_seteuid = (uid_t)-1;

static const char *q4_label(int i) {
  switch (i) {
    case 0: return "impersonated, nothing else done";
    case 1: return "fork() + waitpid   <- CONTROL, must lose it";
    case 2: return "re-impersonated";
    case 3: return "CW_SET_EXTERNAL_TOKEN registered";
    case 4: return "fork() + waitpid   <- FORM 1 ANSWER";
    case 5: return "re-registered, then seteuid(target)";
    case 6: return "fork() + waitpid   <- FORM 2 ANSWER";
    default: return "(no such row)";
  }
}

/* One row: what Windows says this thread is, what the runtime says the user
   is, and who owns a file created through the runtime in the same breath. */
static void q4_snap(int i, const char *writedir) {
  HANDLE th = NULL;
  int fd;

  if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &th)) {
    snprintf(q4_who[i], sizeof(q4_who[i]), "%s", token_user(th));
    q4_state[i] = 1;
    CloseHandle(th);
  } else if (GetLastError() == ERROR_NO_TOKEN) {
    snprintf(q4_who[i], sizeof(q4_who[i]), "(no thread token - NOT impersonating)");
    q4_state[i] = 0;
  } else {
    snprintf(q4_who[i], sizeof(q4_who[i]), "(OpenThreadToken failed: %s)",
             winerr(GetLastError()));
    q4_state[i] = -1;
  }

  snprintf(q4_uids[i], sizeof(q4_uids[i]), "uid %ld euid %ld",
           (long)getuid(), (long)geteuid());

  snprintf(q4_path[i], sizeof(q4_path[i]), "%s\\q4-%02d", writedir, i);
  unlink(q4_path[i]);
  fd = open(q4_path[i], O_WRONLY | O_CREAT | O_EXCL | O_BINARY, 0600);
  if (fd >= 0) { q4_made[i] = 1; close(fd); }
  else         { q4_made[i] = 0; }

  if (i + 1 > q4_count) q4_count = i + 1;
}

static void q4_fork(char *note, size_t n) {
  pid_t p;
  fflush(stdout);   /* or the child duplicates whatever is still buffered */
  p = fork();
  if (p == 0) _exit(0);
  if (p < 0) {
    snprintf(note, n, "fork FAILED - errno %d (%s)", errno, strerror(errno));
  } else {
    int st = 0;
    waitpid(p, &st, 0);
    snprintf(note, n, "forked pid %ld, reaped", (long)p);
  }
}

/* Does row i hold the target on BOTH instruments? */
static int q4_holds(int i, const char *want) {
  int ok = 0;
  char owner[256];

  if (q4_state[i] != 1) return 0;
  if (strcmp(q4_who[i], want) != 0) return 0;
  if (!q4_made[i]) return 0;
  snprintf(owner, sizeof(owner), "%s", file_owner(q4_path[i], &ok));
  if (!ok) return 0;
  return strcmp(owner, want) == 0;
}

/* Runs while this process is NOT impersonating - it takes and drops the
   impersonation itself, so it is self-contained and cannot leave the caller
   in a state it did not start in. */
static void q4_run(HANDLE tok, const char *user, const char *writedir) {
  struct passwd *pw;
  uid_t orig_euid = geteuid();
  uintptr_t rc;

  q4_count = 0;

  /* ---- row 0: the baseline the whole leg is measured against ---------- */
  if (!ImpersonateLoggedOnUser(tok)) {
    snprintf(q4_note[0], sizeof(q4_note[0]),
             "ImpersonateLoggedOnUser FAILED: %s", winerr(GetLastError()));
    q4_snap(0, writedir);
    return;
  }
  snprintf(q4_note[0], sizeof(q4_note[0]), "impersonated");
  q4_snap(0, writedir);

  /* ---- row 1: THE CONTROL.  A plain fork, which must lose it ---------- */
  q4_fork(q4_note[1], sizeof(q4_note[1]));
  q4_snap(1, writedir);

  /* ---- row 2: back to a known state before form 1 --------------------- */
  if (!ImpersonateLoggedOnUser(tok))
    snprintf(q4_note[2], sizeof(q4_note[2]),
             "re-impersonate FAILED: %s", winerr(GetLastError()));
  else
    snprintf(q4_note[2], sizeof(q4_note[2]), "re-impersonated");
  q4_snap(2, writedir);

  /* ---- row 3: FORM 1 - register the token, do nothing else ------------ */
  errno = 0;
  rc = cygwin_internal(CW_SET_EXTERNAL_TOKEN, tok, CW_TOKEN_IMPERSONATION);
  snprintf(q4_note[3], sizeof(q4_note[3]),
           "cygwin_internal(CW_SET_EXTERNAL_TOKEN, handle %p, type %d) "
           "returned %ld, errno %d",
           (void *)tok, (int)CW_TOKEN_IMPERSONATION, (long)rc, errno);
  q4_snap(3, writedir);

  /* ---- row 4: the answer for form 1 ----------------------------------- */
  q4_fork(q4_note[4], sizeof(q4_note[4]));
  q4_snap(4, writedir);

  /* ---- row 5: FORM 2 - register, then seteuid, which is what actually
     asks the runtime to adopt what was registered ------------------------ */
  if (q4_state[4] != 1) ImpersonateLoggedOnUser(tok);   /* form 1 may have lost it */

  pw = getpwnam(user);
  if (pw == NULL) {
    snprintf(q4_note[5], sizeof(q4_note[5]),
             "getpwnam(%s) returned NULL - seteuid NOT attempted, so form 2 "
             "is unmeasured rather than failed", user);
  } else {
    q4_target_uid = pw->pw_uid;
    errno = 0;
    rc = cygwin_internal(CW_SET_EXTERNAL_TOKEN, tok, CW_TOKEN_IMPERSONATION);
    errno = 0;
    q4_euid_at_seteuid = geteuid();
    q4_seteuid_rc = seteuid(q4_target_uid);
    q4_seteuid_errno = errno;
    snprintf(q4_note[5], sizeof(q4_note[5]),
             "re-registered (returned %ld), seteuid(%ld) from euid %ld "
             "returned %d, errno %d%s",
             (long)rc, (long)q4_target_uid, (long)q4_euid_at_seteuid,
             q4_seteuid_rc, q4_seteuid_errno,
             (q4_target_uid == q4_euid_at_seteuid)
               ? "  <- SAME uid: nothing to change, form 2 not exercised" : "");
  }
  q4_snap(5, writedir);

  /* ---- row 6: the answer for form 2 ----------------------------------- */
  q4_fork(q4_note[6], sizeof(q4_note[6]));
  q4_snap(6, writedir);

  /* PUT THE PROCESS BACK.  seteuid changes PROCESS state, not this thread's,
     so leaving it set would follow the run out of this function and into
     anything the caller does afterwards. */
  if (q4_seteuid_rc == 0 && seteuid(orig_euid) != 0)
    say("  Q4: WARNING - seteuid back to %ld failed, errno %d",
        (long)orig_euid, errno);
  RevertToSelf();
}

/* Returns 1 if EITHER form carried the identity across fork() on both
   instruments; 0 otherwise, including every VOID path. */
static int q4_report(const char *want) {
  int i, base_ok, ctrl_lost, form1, form2, form2_measured;

  say("Q4 - CAN cygwin_internal(CW_SET_EXTERNAL_TOKEN) CARRY IT ACROSS fork()?");
  say("  This is the CLASS half of step 14's decision, and the only part of");
  say("  that decision still unmeasured.  target is %s.", want);
  say("");

  if (q4_count == 0) {
    say("  *** VOID: the leg did not run at all. ***");
    say("");
    return 0;
  }

  say("   # what was done                              token after      owner of file made after");
  say("   - ---------------------------------------- ---------------- -------------------------");
  for (i = 0; i < q4_count; i++) {
    int ok = 0;
    char owner[256];
    char shortwho[32];

    snprintf(owner, sizeof(owner), "%s",
             q4_made[i] ? file_owner(q4_path[i], &ok) : "(not created)");
    if (q4_state[i] == 1)
      snprintf(shortwho, sizeof(shortwho), "%.31s",
               (strcmp(q4_who[i], want) == 0) ? "target" : q4_who[i]);
    else if (q4_state[i] == 0)
      snprintf(shortwho, sizeof(shortwho), "NONE");
    else
      snprintf(shortwho, sizeof(shortwho), "unreadable");

    say("  %2d %-40s %-16s %s", i, q4_label(i), shortwho, owner);
  }
  say("");
  for (i = 0; i < q4_count; i++)
    say("   %2d %s", i, q4_note[i]);
  say("");
  say("  the runtime's own uids per row (mechanism (ii) visible directly):");
  for (i = 0; i < q4_count; i++)
    say("   %2d %-40s %s", i, q4_label(i), q4_uids[i]);
  say("");

  /* ---- the null cases, refused out loud ------------------------------- */
  base_ok   = q4_holds(0, want);
  ctrl_lost = !q4_holds(1, want);

  if (!base_ok) {
    say("  *** VOID: row 0 did not hold the target on both instruments. ***");
    say("      Nothing was impersonated to begin with, so no later row is a");
    say("      claim about carrying an identity across fork().");
    say("");
    return 0;
  }
  if (!ctrl_lost) {
    say("  *** VOID: the CONTROL fork did not lose the identity. ***");
    say("      This run has not reproduced the defect, so a later row reading");
    say("      'survived' would be evidence of nothing.  Q3 and this leg");
    say("      disagree within one run - read Q3's table before trusting");
    say("      either.");
    say("");
    return 0;
  }
  say("  controls hold: row 0 impersonated, and the plain fork at row 1 lost");
  say("  it - so this run reproduces the defect the class fix is meant to fix.");
  say("");

  form1 = q4_holds(4, want);
  form2 = q4_holds(6, want);

  /* WAS FORM 2 ACTUALLY EXERCISED?  Three ways it can look like a result
     without being one, and the third is the subtle one. */
  form2_measured = 1;
  if (q4_seteuid_rc == -2)                          form2_measured = 0;
  else if (q4_seteuid_rc != 0)                      form2_measured = 0;
  else if (q4_target_uid == q4_euid_at_seteuid)     form2_measured = 0;

  say("  FORM 1  CW_SET_EXTERNAL_TOKEN alone, then fork : %s",
      form1 ? "CARRIED" : "lost");
  if (q4_seteuid_rc == -2)
    say("  FORM 2  register + seteuid, then fork          : NOT MEASURED - "
        "seteuid was never attempted");
  else if (q4_seteuid_rc != 0)
    say("  FORM 2  register + seteuid, then fork          : NOT MEASURED - "
        "seteuid REFUSED (errno %d), which is not the same as lost",
        q4_seteuid_errno);
  else if (q4_target_uid == q4_euid_at_seteuid)
    say("  FORM 2  register + seteuid, then fork          : NOT MEASURED - "
        "the target uid (%ld) was ALREADY the euid, so seteuid had nothing "
        "to change and the runtime never adopted the token",
        (long)q4_target_uid);
  else
    say("  FORM 2  register + seteuid, then fork          : %s",
        form2 ? "CARRIED" : "lost");
  say("");

  form2 = form2 && form2_measured;

  if (form1 || form2) {
    say("  *** THE CLASS FIX IS AVAILABLE. ***  The runtime carried the");
    say("  impersonation across fork() by %s.",
        form1 ? "the bare CW_SET_EXTERNAL_TOKEN call"
              : "CW_SET_EXTERNAL_TOKEN followed by seteuid()");
    say("  That covers PHANTOM (op_kernel.c:735) and SH (op_sh.c:379) as well");
    say("  as the LOGTO group check, which the narrow fix does not.  It is now");
    say("  a decision between two WORKING options rather than one working and");
    say("  one unproven.");
    if (!form1 && form2) {
      say("");
      say("  AND THE SHAPE MATTERS TO WHOEVER BUILDS IT: the bare call did");
      say("  NOT carry it.  seteuid() is what makes the runtime adopt the");
      say("  registered token, so the fix is the PAIR, not the one call this");
      say("  file's step 14 entry names.  seteuid also moves the POSIX euid,");
      say("  which the uid table above shows and which today stays SYSTEM.");
    }
  } else if (!form2_measured) {
    say("  *** NOT AN ANSWER: FORM 1 LOST IT AND FORM 2 WAS NEVER EXERCISED.");
    say("  The bare call is measured and did not carry the identity.  Form 2");
    say("  is the one the Cygwin sources' own callers use, and the line above");
    say("  says why this run did not reach it.  DO NOT record the class option");
    say("  as disproved on this run - it has been half measured.");
    say("  What it takes to finish: a target whose uid DIFFERS from the");
    say("  runtime's euid, which is the elevated S4U path against a real");
    say("  second account, not --q4check.");
  } else {
    say("  THE CLASS FIX DID NOT WORK HERE, IN EITHER FORM, AND BOTH WERE");
    say("  GENUINELY EXERCISED.  On this evidence step 14's decision collapses");
    say("  to the NARROW fix - re-impersonating after each fork() - and the");
    say("  class option should be struck rather than left open as 'unproven'.");
    say("  READ THE ROWS BEFORE ACTING ON THAT: a call that returned an error");
    say("  above is a different finding from one that returned success and");
    say("  changed nothing.");
  }
  say("");
  return (form1 || form2) ? 1 : 0;
}

/* ==========================================================================
   The measurement.  One function, run twice in different configurations, so
   the two rows cannot drift apart.

   tag         how this run was started, printed so the row names itself
   Returns R_VOID / R_CALL, or R_BASE|flags on a completed measurement.
   ========================================================================== */
static int measure(const char *tag, const char *user, const char *allowed,
                   const char *forbidden, const char *writedir) {
  LSA_STRING lsaname, pkgname;
  LSA_HANDLE hlsa = NULL;
  LSA_OPERATIONAL_MODE mode = 0;
  ULONG pkg = 0;
  MSV1_0_S4U_LOGON *s4u = NULL;
  ULONG s4ulen;
  BYTE *tail;
  WCHAR *wuser, *wdom;
  int wuserlen, wdomlen;
  char dom[MAX_COMPUTERNAME_LENGTH + 1];
  DWORD domlen = sizeof(dom);
  LSA_STRING origin;
  TOKEN_SOURCE src;
  NTSTATUS st, sub = 0;
  void *profile = NULL;
  ULONG proflen = 0;
  LUID logonid;
  HANDLE tok = NULL, thread_tok = NULL;
  QUOTA_LIMITS quota;
  SECURITY_IMPERSONATION_LEVEL lvl;
  DWORD got = 0;
  int a_allowed, a_forbidden, m_allowed, m_forbidden, b_forbidden;
  int made_before, made_during;
  int own_ok_before = 0, own_ok_during = 0;
  char before_path[MAX_PATH], during_path[MAX_PATH];
  char owner_before[256], owner_during[256], thread_who[256];
  int access_governed, owner_tracked;
  int exttok = 0;
  int result;

  say("===========================================================");
  say(" MEASUREMENT - %s", tag);
  say("===========================================================");
  say("  pid %ld, parent pid %ld", (long)getpid(), (long)getppid());
  {
    HANDLE me;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &me)) {
      say("  process token   : %s", token_user(me));
      CloseHandle(me);
    } else {
      say("  process token   : (OpenProcessToken failed: %s)",
          winerr(GetLastError()));
    }
  }
  show_uids("at entry");
  say("");

  if (snprintf(before_path, sizeof(before_path), "%s\\made-before", writedir) >=
      (int)sizeof(before_path)) {
    say("  the writable fixture path is too long"); return R_CALL;
  }
  if (snprintf(during_path, sizeof(during_path), "%s\\made-during", writedir) >=
      (int)sizeof(during_path)) {
    say("  the writable fixture path is too long"); return R_CALL;
  }

  /* ---- control A ------------------------------------------------------ */
  say("CONTROL A - before impersonating, as this process's own identity");
  a_allowed   = try_open("allowed file", allowed);
  a_forbidden = try_open("forbidden file", forbidden);
  made_before = try_create("file created BEFORE impersonating", before_path);
  if (!a_allowed || !a_forbidden) {
    say("");
    say("*** VOID: control A did not hold. ***");
    say("    Both files must open BEFORE impersonating, or a refusal later");
    say("    says nothing about the thread token.  Nothing here is a result.");
    return R_VOID;
  }
  if (!made_before) {
    say("");
    say("*** VOID: the writable fixture is not writable by this process. ***");
    say("    The ownership leg has no control without it.  Nothing here is a");
    say("    result.");
    return R_VOID;
  }
  say("  control A holds: both open, and the writable fixture accepts a file.");
  say("");

  /* ---- S4U logon, as probe-s4u.c and probe-impersonate.c do it --------- */
  say("S4U LOGON for %s", user);
  lsaname.Buffer = (PCHAR)"probe-impf";
  lsaname.Length = (USHORT)strlen(lsaname.Buffer);
  lsaname.MaximumLength = lsaname.Length + 1;

  st = LsaRegisterLogonProcess(&lsaname, &hlsa, &mode);
  if (st != 0) {
    say("  LsaRegisterLogonProcess refused: NTSTATUS 0x%08lx",
        (unsigned long)st);
    say("  This must run as LocalSystem - SeTcbPrivilege is the discriminator.");
    say("  probe-impfork.ps1 does that with schtasks /RU SYSTEM.");
    return R_CALL;
  }
  say("  LsaRegisterLogonProcess: TRUSTED connection");

  pkgname.Buffer = (PCHAR)MSV1_0_PACKAGE_NAME;
  pkgname.Length = (USHORT)strlen(pkgname.Buffer);
  pkgname.MaximumLength = pkgname.Length + 1;
  st = LsaLookupAuthenticationPackage(hlsa, &pkgname, &pkg);
  if (st != 0) {
    say("  LsaLookupAuthenticationPackage failed: 0x%08lx", (unsigned long)st);
    return R_CALL;
  }

  /* ONE CONTIGUOUS BLOCK, both strings in its tail - LSA copies the whole
     buffer into its own process.  Length EXCLUDES the terminator and
     MaximumLength INCLUDES it; setting them equal gives a call that reads
     correctly and fails.  Both traps are recorded in probe-impersonate.c. */
  if (GetComputerNameA(dom, &domlen) == 0) {
    say("  GetComputerNameA failed: %s", winerr(GetLastError()));
    return R_CALL;
  }
  say("  domain (this machine): %s", dom);

  wuserlen = MultiByteToWideChar(CP_ACP, 0, user, -1, NULL, 0);
  wdomlen  = MultiByteToWideChar(CP_ACP, 0, dom, -1, NULL, 0);
  if (wuserlen <= 0 || wdomlen <= 0) {
    say("  cannot widen the account name: %s", winerr(GetLastError()));
    return R_CALL;
  }

  s4ulen = (ULONG)(sizeof(MSV1_0_S4U_LOGON) +
                   (size_t)wuserlen * sizeof(WCHAR) +
                   (size_t)wdomlen * sizeof(WCHAR));
  s4u = (MSV1_0_S4U_LOGON *)calloc(1, s4ulen);
  if (s4u == NULL) { say("  out of memory"); return R_CALL; }

  tail  = (BYTE *)s4u + sizeof(MSV1_0_S4U_LOGON);
  wuser = (WCHAR *)tail;
  wdom  = (WCHAR *)(tail + (size_t)wuserlen * sizeof(WCHAR));
  MultiByteToWideChar(CP_ACP, 0, user, -1, wuser, wuserlen);
  MultiByteToWideChar(CP_ACP, 0, dom,  -1, wdom,  wdomlen);

  s4u->MessageType = MsV1_0S4ULogon;
  s4u->Flags       = 0;
  s4u->UserPrincipalName.Length        = (USHORT)((wuserlen - 1) * sizeof(WCHAR));
  s4u->UserPrincipalName.MaximumLength = (USHORT)(wuserlen * sizeof(WCHAR));
  s4u->UserPrincipalName.Buffer        = wuser;
  s4u->DomainName.Length               = (USHORT)((wdomlen - 1) * sizeof(WCHAR));
  s4u->DomainName.MaximumLength        = (USHORT)(wdomlen * sizeof(WCHAR));
  s4u->DomainName.Buffer               = wdom;

  origin.Buffer        = (PCHAR)"probe-impf";
  origin.Length        = (USHORT)strlen(origin.Buffer);
  origin.MaximumLength = (USHORT)(origin.Length + 1);

  memcpy(src.SourceName, "probeimf", 8);
  if (!AllocateLocallyUniqueId(&src.SourceIdentifier)) {
    say("  AllocateLocallyUniqueId failed: %s", winerr(GetLastError()));
    return R_CALL;
  }

  st = LsaLogonUser(hlsa, &origin, Network, pkg, s4u, s4ulen, NULL, &src,
                    &profile, &proflen, &logonid, &tok, &quota, &sub);
  if (st != 0 || tok == NULL) {
    say("  LsaLogonUser failed: 0x%08lx (sub 0x%08lx)", (unsigned long)st,
        (unsigned long)sub);
    return R_CALL;
  }
  say("  token for       : %s", token_user(tok));

  if (GetTokenInformation(tok, TokenImpersonationLevel, &lvl, sizeof(lvl),
                          &got)) {
    say("  impersonation   : %s",
        lvl == SecurityImpersonation  ? "Impersonation" :
        lvl == SecurityIdentification ? "Identification" : "other");
    if (lvl != SecurityImpersonation) {
      say("");
      say("*** VOID: the token is not at Impersonation level. ***");
      say("    ImpersonateLoggedOnUser would succeed and change nothing.");
      return R_VOID;
    }
  }
  say("");

  /* ---- the measurement ------------------------------------------------ */
  say("MEASUREMENT - while impersonating %s", user);
  if (!ImpersonateLoggedOnUser(tok)) {
    say("  ImpersonateLoggedOnUser failed: %s", winerr(GetLastError()));
    return R_CALL;
  }

  /* Readback, not a return code - probe-s4u.c's convention, and the reason
     its result could be trusted. */
  thread_who[0] = '\0';
  if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &thread_tok)) {
    snprintf(thread_who, sizeof(thread_who), "%s", token_user(thread_tok));
    say("  thread token now: %s   <- readback, not a return code", thread_who);
    CloseHandle(thread_tok);
  } else {
    say("  OpenThreadToken failed: %s", winerr(GetLastError()));
    say("");
    say("*** VOID: the thread token could not be read back. ***");
    say("    Without it there is no evidence the switch happened at all.");
    RevertToSelf();
    return R_VOID;
  }

  /* THE RUNTIME'S OWN IDEA OF THE USER, asked while the thread token says
     somebody else.  If this does not move, mechanism (ii) in the header is
     visible directly rather than inferred. */
  show_uids("while impersonating");

  m_allowed   = try_open("allowed file", allowed);
  m_forbidden = try_open("forbidden file", forbidden);
  made_during = try_create("file created WHILE impersonating", during_path);

  /* Q3 runs LAST of the impersonated work, so it cannot disturb Q1/Q2 above -
     their result stays exactly what the committed run produced. */
  say("");
  q3_hlsa = hlsa;   /* step 12 closes it, as win32s4u.c does on success */
  q3_run(user, writedir, allowed);

  RevertToSelf();
  say("");

  /* ---- control B ------------------------------------------------------ */
  say("CONTROL B - after RevertToSelf");
  show_uids("after reverting");
  b_forbidden = try_open("forbidden file", forbidden);
  if (!b_forbidden) {
    say("");
    say("*** VOID: control B did not hold. ***");
    say("    The forbidden file did not open again after reverting, so the");
    say("    refusal above may have been a lock or a bad path.");
    return R_VOID;
  }
  say("  control B holds: reverting restored access.");
  say("");

  /* ---- owners, read AFTER reverting so the read itself cannot be the
     thing that was refused --------------------------------------------- */
  say("OWNERSHIP - read after reverting, so no read is refused by the switch");
  snprintf(owner_before, sizeof(owner_before), "%s",
           made_before ? file_owner(before_path, &own_ok_before)
                       : "(not created)");
  snprintf(owner_during, sizeof(owner_during), "%s",
           made_during ? file_owner(during_path, &own_ok_during)
                       : "(not created)");
  say("  created BEFORE impersonating : %s", owner_before);
  say("  created WHILE impersonating  : %s", owner_during);
  say("  thread token at that moment  : %s", thread_who);
  say("");

  /* Q4 runs LAST of all the impersonated work - after control B, and after
     the owners above have been read - so nothing it does can disturb a
     reading this file has already committed to.  Same reasoning as Q3's
     placement, and it matters more here because Q4 calls seteuid(). */
  q4_run(tok, user, writedir);

  {
    char want[256];
    snprintf(want, sizeof(want), "%s\\%s", dom, user);
    q3_report(want);
    exttok = q4_report(want);
  }

  /* ---- verdict -------------------------------------------------------- */
  access_governed = (!m_forbidden && m_allowed);
  owner_tracked   = 0;

  say("VERDICT - %s", tag);
  say("  Q1 ACCESS");
  say("    allowed file while impersonating   : %s",
      m_allowed ? "opened" : "REFUSED");
  say("    forbidden file while impersonating : %s",
      m_forbidden ? "OPENED" : "refused");
  if (access_governed) {
    say("    -> IMPERSONATION GOVERNS open() here.");
  } else if (m_forbidden) {
    say("    -> IMPERSONATION DOES NOT GOVERN open() here.  The runtime opened");
    say("       a file the impersonated user may not read.");
  } else {
    say("    -> INCONCLUSIVE: the allowed file was refused too, so the target");
    say("       may have no access to either path.  Check the fixtures.");
  }
  say("");

  say("  Q2 OWNERSHIP OF A FILE CREATED THROUGH THE RUNTIME");
  if (!made_during) {
    say("    NOT MEASURED: the file could not be created while impersonating.");
    say("    That is itself a reading - the user may not write the fixture -");
    say("    but it is not an answer about ownership.");
  } else if (!own_ok_during || !own_ok_before) {
    say("    NOT MEASURED: an owner could not be read.  See the lines above;");
    say("    a name that could not be resolved is not a mismatch.");
  } else if (strcmp(owner_before, owner_during) != 0) {
    owner_tracked = 1;
    say("    The two owners DIFFER, so ownership tracks the writing identity.");
    say("    b28's instrument means what it was taken to mean.");
  } else {
    say("    The two owners are THE SAME (%s) although the thread token was", owner_before);
    say("    %s at the moment of creation.", thread_who);
    say("    -> OWNERSHIP DOES NOT TRACK THE THREAD TOKEN.  The runtime stamps");
    say("       a new file from its own cached user, which fork() carried in.");
  }
  say("");

  /* THE COMBINATION IS THE POINT, so it is stated rather than left to be
     assembled by a reader of two separate verdicts. */
  say("  WHAT THE COMBINATION MEANS FOR b28");
  if (access_governed && !owner_tracked && made_during) {
    say("    ACCESS GOVERNED and OWNERSHIP BLIND.  This is mechanism (ii):");
    say("    verify-apiidentity read the runtime's owner-stamping, not the");
    say("    session's effective token, and its control could not have");
    say("    separated the two.  Step 14's conclusion needs rewriting and the");
    say("    ownership probe needs replacing with an ACCESS one.");
  } else if (!access_governed && !owner_tracked) {
    say("    ACCESS NOT GOVERNED and OWNERSHIP BLIND.  b28's reading stands:");
    say("    the switch does not reach the file layer in this configuration.");
    say("    cygwin_internal(CW_SET_EXTERNAL_TOKEN) is the next thing to try");
    say("    before shape (b) is abandoned for shape (a).");
  } else if (access_governed && owner_tracked) {
    say("    ACCESS GOVERNED and OWNERSHIP TRACKING.  Both instruments agree");
    say("    here, so the difference from b28 is the API session itself and");
    say("    not the runtime - look at APISRVR and the hook, not at Cygwin.");
  } else {
    say("    Mixed or unmeasured - read the two blocks above rather than");
    say("    taking a one-line answer from here.");
  }
  say("");

  result = R_BASE;
  if (access_governed) result |= R_ACCESS;
  if (owner_tracked)   result |= R_OWNER;
  if (exttok)          result |= R_EXTTOK;
  say("  exit code %d = 8 base + %d access + %d ownership + %d external token",
      result, access_governed ? R_ACCESS : 0, owner_tracked ? R_OWNER : 0,
      exttok ? R_EXTTOK : 0);
  say("");
  return result;
}

/* Decode an exit code into words, so no reader has to do the arithmetic. */
static void explain(const char *tag, int code) {
  if (code == R_USAGE)      { say("  %-28s : usage error", tag); return; }
  if (code == R_VOID)       { say("  %-28s : VOID - controls did not hold", tag); return; }
  if (code == R_CALL)       { say("  %-28s : a required call failed", tag); return; }
  /* R_EXTTOK and R_CALL are both 4, which is safe ONLY because R_CALL is
     returned bare and is matched above, before this range check: a completed
     run always carries R_BASE, so the smallest code reaching here is 8. */
  if (code < R_BASE || code > (R_BASE | R_ACCESS | R_OWNER | R_EXTTOK)) {
    say("  %-28s : did not complete (exit %d)", tag, code);
    return;
  }
  say("  %-28s : access %s, ownership %s, external token %s", tag,
      (code & R_ACCESS) ? "GOVERNED" : "not governed",
      (code & R_OWNER)  ? "tracks the token" : "blind to the token",
      (code & R_EXTTOK) ? "CARRIES ACROSS fork()" : "does not carry");
}

int main(int argc, char *argv[]) {
  const char *user, *allowed, *forbidden, *writedir;
  char self[MAX_PATH];
  ssize_t n;
  pid_t pid;
  int child_status = 0, child_code = -1, direct_code;

  /* --- SELF-TEST for the owner reader, so its first exercise is not the
     elevated run.  The ownership leg only executes after a successful S4U
     logon, which needs SeTcbPrivilege, so without this mode a broken
     GetNamedSecurityInfoA would be discovered by spending the measurement.
     CLAUDE.md: use the check that CATCHES THE BREAK. ------------------- */
  if (argc == 3 && strcmp(argv[1], "--ownercheck") == 0) {
    int ok = 0;
    const char *who = file_owner(argv[2], &ok);
    say("owner of %s", argv[2]);
    say("  -> %s", who);
    say("  readable: %s", ok ? "yes" : "NO");
    return ok ? 0 : 1;
  }

  /* --- SELF-TEST for the Q3 sequence.  Q3 only executes after a successful
     S4U logon, so without this mode its first exercise would be the elevated
     run - the same blind spot the --ownercheck mode exists to close.  This
     runs the identical sequence WITHOUT impersonating, which proves the
     operations execute, the socket/fork/signal legs work, the files get made
     and their owners get read.  It is a MECHANICS CHECK, NOT A MEASUREMENT,
     and it says so: every row must show this process's own identity, and
     q3_report must therefore declare the switch lost at step 0 - which also
     proves the detection fires rather than merely never firing. ---------- */
  if (argc == 5 && strcmp(argv[1], "--q3check") == 0) {
    char want[256];
    char dom2[MAX_COMPUTERNAME_LENGTH + 1];
    DWORD dl = sizeof(dom2);
    say("--q3check: MECHANICS ONLY, NOT A MEASUREMENT.");
    say("  Nothing is impersonated, so every row must read this process's own");
    say("  identity and step 0 must be reported as the loss point.");
    say("");
    if (!GetComputerNameA(dom2, &dl)) { say("GetComputerNameA failed"); return R_CALL; }
    q3_run(argv[2], argv[4], argv[3]);
    snprintf(want, sizeof(want), "%s\\%s", dom2, argv[2]);
    q3_report(want);
    return 0;
  }

  /* --- SELF-TEST for the Q4 sequence, and the same reason as the two above:
     Q4 only executes after a successful S4U logon, so without this its first
     exercise would be the elevated run.  This process impersonates ITSELF
     with a duplicate of its own token, which needs no privilege, and then
     runs the identical sequence.  It proves the cygwin_internal call is
     reachable and what it returns, that the rows record, that fork/seteuid
     execute, and that the control detection fires.

     IT IS EXPLICITLY NOT AN ANSWER TO Q4.  Impersonating yourself is a
     degenerate case - every owner is this account whatever the token does -
     so a "CARRIED" here would be about the machinery, not about the class
     fix.  It says so in its own output rather than leaving that to a
     reader. ------------------------------------------------------------- */
  if (argc == 3 && strcmp(argv[1], "--q4check") == 0) {
    HANDLE me = NULL, imp = NULL;
    struct passwd *self_pw;
    const char *self_name;
    char want[256];

    say("--q4check: MECHANICS ONLY, NOT A MEASUREMENT.");
    say("  Nothing elevates and no S4U logon happens.  This process");
    say("  impersonates ITSELF, so every owner below is this account whatever");
    say("  the token does.  A 'CARRIED' verdict here is about the machinery");
    say("  and is NOT an answer to Q4.");
    say("");
    say("  writable dir    : %s   <- as received", argv[2]);

    if (!OpenProcessToken(GetCurrentProcess(),
                          TOKEN_DUPLICATE | TOKEN_QUERY, &me)) {
      say("  OpenProcessToken failed: %s", winerr(GetLastError()));
      return R_CALL;
    }
    snprintf(want, sizeof(want), "%s", token_user(me));
    self_pw   = getpwuid(getuid());
    self_name = self_pw ? self_pw->pw_name : "";
    say("  impersonating   : %s   <- readback from our own process token", want);
    say("  getpwuid name   : %s   <- what seteuid() will be given",
        self_pw ? self_name : "(getpwuid failed - form 2 will be unmeasured)");

    if (!DuplicateTokenEx(me, TOKEN_ALL_ACCESS, NULL, SecurityImpersonation,
                          TokenImpersonation, &imp)) {
      say("  DuplicateTokenEx failed: %s", winerr(GetLastError()));
      CloseHandle(me);
      return R_CALL;
    }
    CloseHandle(me);
    say("");

    q4_run(imp, self_name, argv[2]);
    q4_report(want);
    CloseHandle(imp);
    return 0;
  }

  /* --- the forked child does one measurement and says nothing else ----- */
  if (argc == 6 && strcmp(argv[1], "--child") == 0) {
    return measure("FORKED AND EXEC'D CYGWIN CHILD - the API session's shape",
                   argv[2], argv[3], argv[4], argv[5]);
  }

  if (argc < 5) {
    say("usage: probe-impfork <user> <allowed-file> <forbidden-file> <writable-dir>");
    return R_USAGE;
  }
  user = argv[1]; allowed = argv[2]; forbidden = argv[3]; writedir = argv[4];

  say("probe-impfork - PROJECT_STATUS.md section 7 step 14, after b28");
  say("  Q1  does impersonation govern open() in a fork()ed, exec()d child?");
  say("  Q2  when a file is CREATED while impersonating, whose name is on it?");
  say("  Q3  which of the things a session does next drops the switch?");
  say("  Q4  can CW_SET_EXTERNAL_TOKEN carry it across fork()?  <- the CLASS");
  say("      half of step 14's decision, and the only part still unmeasured");
  say("");
  say("INPUTS AS RECEIVED");
  say("  target user     : %s", user);
  say("  allowed file    : %s", allowed);
  say("  forbidden file  : %s", forbidden);
  say("  writable dir    : %s", writedir);

  /* REFUSE THE NULL CASE OUT LOUD.  Two identical fixture paths would make
     every comparison below trivially true. */
  if (strcmp(allowed, forbidden) == 0) {
    say("");
    say("*** VOID: the allowed and forbidden paths are the same file. ***");
    return R_VOID;
  }

  n = readlink("/proc/self/exe", self, sizeof(self) - 1);
  if (n > 0) {
    self[n] = '\0';
    say("  this program    : %s   (from /proc/self/exe)", self);
  } else {
    snprintf(self, sizeof(self), "%s", argv[0]);
    say("  this program    : %s   (from argv[0] - /proc/self/exe failed)", self);
  }
  say("");

  /* --- the child FIRST, before this process has ever impersonated ------ */
  say("Forking.  The child runs first, so nothing this process does can");
  say("reach it.  It re-execs this same binary, which is what makes it a");
  say("fork()ed AND exec()d Cygwin child rather than merely a fork.");
  say("");
  fflush(stdout); /* or fork duplicates whatever is still buffered */

  pid = fork();
  if (pid < 0) {
    say("*** fork() failed: %s ***", strerror(errno));
    return R_CALL;
  }
  if (pid == 0) {
    execl(self, "probe-impfork", "--child", user, allowed, forbidden, writedir,
          (char *)NULL);
    /* Only reached if exec failed - and it must not be mistaken for a result. */
    fprintf(stdout, "*** execl failed: %s ***\n", strerror(errno));
    fflush(stdout);
    _exit(R_CALL);
  }

  if (waitpid(pid, &child_status, 0) < 0) {
    say("*** waitpid failed: %s ***", strerror(errno));
    return R_CALL;
  }
  if (WIFEXITED(child_status)) {
    child_code = WEXITSTATUS(child_status);
  } else if (WIFSIGNALED(child_status)) {
    say("*** the child died on signal %d - nothing it printed is a result ***",
        WTERMSIG(child_status));
    child_code = -1;
  }
  say("child pid %ld exited %d", (long)pid, child_code);
  say("");

  /* --- then the same measurement HERE: the configuration control ------- */
  say("Now the identical measurement in THIS process, which cmd.exe started -");
  say("probe-impersonate's configuration, same binary, same fixtures.  A");
  say("difference between the two rows is the fork and nothing else.");
  say("");
  direct_code = measure("DIRECT - started by cmd.exe, as probe-impersonate was",
                        user, allowed, forbidden, writedir);

  say("===========================================================");
  say(" SUMMARY");
  say("===========================================================");
  explain("forked and exec'd child", child_code);
  explain("direct (control)", direct_code);
  say("");

  if (child_code < R_BASE || direct_code < R_BASE) {
    say("  ONE OR BOTH LEGS DID NOT COMPLETE.  Read them above; the comparison");
    say("  below is not made from an incomplete leg.");
    return R_VOID;
  }

  if (child_code == direct_code) {
    say("  THE FORK MAKES NO DIFFERENCE.  Both configurations behave the same,");
    say("  so step 14's suspicion of the fork()ed child is answered NO and the");
    say("  explanation for b28 is whatever the shared row above says it is.");
  } else {
    say("  THE FORK CHANGES THE ANSWER.  The two rows differ, and the only");
    say("  difference between them is how the process was started.  That is");
    say("  the finding step 14 asked for.");
  }
  say("");
  return child_code;
}

/* END-CODE */
