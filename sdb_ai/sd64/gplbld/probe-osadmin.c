/* probe-osadmin.c - what do IsAdmin() and IsElevated() answer for an
 *                   UNELEVATED administrator?
 *
 * 29 Aug 26 Windows port.  Built and run by probe-osadmin.ps1.  It is an
 * INSTRUMENT, not a verifier: there is nothing here to pass or fail, and a
 * person reads what it prints.  probe-console.c and probe-s4u.c are the same
 * shape and say why that distinction matters.
 *
 * ---------------------------------------------------------------------------
 * WHAT IT DECIDES.  PROJECT_STATUS.md "START HERE" step 1, which everything in
 * PRE_RELEASE_FIXES 56 clause 2 waits on.  The restored access model needs
 * LOGIN to tell two questions apart:
 *
 *     "is this SESSION already elevated"   - an administrator who opened an
 *                                            elevated terminal goes to SDSYS
 *     "is this PERSON an administrator"    - an unelevated one lands in their
 *                                            own personal account instead
 *
 * START HERE says "no existing key answers the first" and, crucially, "do not
 * assume IsAdmin() is False unelevated" - this project has already been caught
 * once by IsAdmin() answering TRUE where it was expected to answer FALSE (every
 * API session, until op_kernel.c:456 grew its CN_SOCKET guard).
 *
 * SO IT IS MEASURED RATHER THAN READ OFF THE SOURCE.  linuxlb.c's header
 * already records a 14 Aug 26 measurement saying getgroups() no, getgrouplist()
 * yes.  That is the answer this probe expects, and expecting an answer is
 * exactly the condition under which this file's rules say to go and measure it:
 * the whole of clause 2's design rests on the two calls disagreeing.
 *
 * ---------------------------------------------------------------------------
 * IT MEASURES THE PRIMITIVES, NOT THE KERNEL KEYS, AND THAT IS DELIBERATE.
 *
 * The obvious probe - a BASIC program in SDSYS reading kernel(K$ADMINISTRATOR,
 * -1) - CANNOT ANSWER THIS QUESTION, and would return a confident wrong answer.
 * K$ADMINISTRATOR is a settable flag (op_kernel.c:395) and LOGIN:615 SETS IT TO
 * 1 for anybody who reached SDSYS, which today is every administrator whether
 * they elevated or not (LOGIN:513).  A probe run from an SD prompt therefore
 * reads 1 in BOTH legs and would be reported as "no discriminator exists".
 * The seeded value - kernel.c:240, IsElevated() && connection_type != CN_SOCKET
 * - survives only as far as LOGIN's own "begin case", and nothing in an account
 * can see it.  Measuring the primitive is measuring what that seed is made of.
 *
 * BUILT WITH THE MSYS2 COMPILER ON PURPOSE, and run from an ordinary Windows
 * console rather than from an MSYS2 shell.  sd.exe is an MSYS2-runtime binary
 * launched from PowerShell or cmd (PROJECT_STATUS.md 5.4), and the question is
 * precisely what that runtime makes of a UAC-filtered token, so building this
 * with the UCRT64 compiler would measure a process SD is not.
 *
 * ---------------------------------------------------------------------------
 * THE NULL CASE IS THE WHOLE RISK HERE AND IT IS REFUSED OUT LOUD.  Run by a
 * user who is not an administrator at all, the naive probe prints
 * "IsAdmin() = FALSE" - which is word for word the answer somebody hoping for
 * a clean discriminator wants to see, and it would be recorded as the finding.
 * So: 544 absent from getgrouplist() is a REFUSAL (exit 2), not a reading.
 * Same for an empty group list, which scores FALSE for the same reason.
 *
 * START-CODE
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>

/* The same number sddefs.h uses, and by number for the same reason: the name
   "Administrators" is localised, S-1-5-32-544 is not.  Spelled out here rather
   than included, because sddefs.h drags in the whole of sd.h.               */
#define PROBE_ADMIN_GID 544

#define NL "\n"

/* Print a gid list on one line, wrapping so a long one stays readable.  The
   list itself is printed, not just the verdict drawn from it - PROJECT_STATUS
   "an instrument shows what it DID".                                        */
static void print_gids(const gid_t* list, int count) {
  int i;

  printf("  gids  =");
  for (i = 0; i < count; i++) {
    if (i > 0 && (i % 12) == 0)
      printf(NL "         ");
    printf(" %lu", (unsigned long)list[i]);
  }
  printf(NL);
}

static int has_gid(const gid_t* list, int count, gid_t want) {
  int i;

  for (i = 0; i < count; i++) {
    if (list[i] == want)
      return 1;
  }
  return 0;
}

int main(int argc, char* argv[]) {
  struct passwd* pw;
  gid_t* gl = NULL; /* getgrouplist() - the ACCOUNT's groups  */
  gid_t* gg = NULL; /* getgroups()    - THIS TOKEN's groups   */
  int gl_count = 0;
  int gg_count = 0;
  int is_admin = 0;
  int is_elevated = 0;
  int i;

  printf("probe-osadmin - PRE_RELEASE_FIXES 56, START HERE step 1" NL);
  printf("=======================================================" NL NL);

  /* --- 0. What this process actually is -------------------------------- */

  printf("0. The inputs this run used" NL);
  printf("  argv    =");
  for (i = 0; i < argc; i++)
    printf(" %s", argv[i]);
  printf(NL);
  printf("  getuid()      = %lu" NL, (unsigned long)getuid());
  printf("  geteuid()     = %lu" NL, (unsigned long)geteuid());
  printf("  admin gid     = %d   (BUILTIN\\Administrators, by number)" NL,
         PROBE_ADMIN_GID);
  printf("  isatty(0)     = %d" NL, isatty(0));

  /* connection_type is not readable from here and does not need to be: this is
     a console process started from a shell, which is the one case both kernel
     sites treat as "not CN_SOCKET".  Said out loud rather than assumed, because
     the socket case is the one that has already produced a wrong answer.    */
  printf("  connection    = console process, so NOT CN_SOCKET." NL);
  printf("                  The API/socket case is guarded at kernel.c:240" NL);
  printf("                  and op_kernel.c:456 and is NOT what this measures." NL NL);

  pw = getpwuid(getuid());
  if (pw == NULL) {
    printf("REFUSED: getpwuid(getuid()) returned NULL - no account to ask" NL);
    printf("about.  IsAdmin() fails closed on this path and would report" NL);
    printf("FALSE, which is indistinguishable from the answer being sought." NL);
    printf("ANSWER: undetermined - the probe did not reach the question." NL);
    return 2;
  }

  printf("  pw_name       = %s" NL, pw->pw_name);
  printf("  pw_gid        = %lu" NL NL, (unsigned long)pw->pw_gid);

  /* --- 1. getgrouplist(), which is IsAdmin() --------------------------- */

  printf("1. getgrouplist() - \"is the ACCOUNT an administrator\"  [IsAdmin()]" NL);

  gl_count = 0;
  getgrouplist(pw->pw_name, pw->pw_gid, NULL, &gl_count);
  if (gl_count <= 0) {
    printf("  count = %d" NL, gl_count);
    printf(NL "REFUSED: the sizing call reported no groups.  IsAdmin() returns" NL);
    printf("FALSE here, and a FALSE that means \"nothing was read\" reads" NL);
    printf("exactly like a FALSE that means \"not an administrator\"." NL);
    printf("ANSWER: undetermined - the probe did not reach the question." NL);
    return 2;
  }

  gl = (gid_t*)malloc(gl_count * sizeof(gid_t));
  if (gl == NULL) {
    printf(NL "REFUSED: out of memory sizing the account group list." NL);
    return 2;
  }

  if (getgrouplist(pw->pw_name, pw->pw_gid, gl, &gl_count) < 0) {
    printf(NL "REFUSED: the second getgrouplist() call failed." NL);
    free(gl);
    return 2;
  }

  printf("  count = %d" NL, gl_count);
  print_gids(gl, gl_count);
  is_admin = has_gid(gl, gl_count, PROBE_ADMIN_GID);
  printf("  %d present: %s" NL, PROBE_ADMIN_GID, is_admin ? "YES" : "NO");
  printf("  IsAdmin()   = %s" NL NL, is_admin ? "TRUE" : "FALSE");

  /* --- 2. getgroups(), which is IsElevated() --------------------------- */

  printf("2. getgroups() - \"may THIS PROCESS act as one\"      [IsElevated()]" NL);

  gg_count = getgroups(0, NULL);
  if (gg_count <= 0) {
    printf("  count = %d" NL, gg_count);
    printf(NL "REFUSED: the token carries no groups.  IsElevated() returns" NL);
    printf("FALSE here for want of data, not for want of elevation." NL);
    printf("ANSWER: undetermined - the probe did not reach the question." NL);
    free(gl);
    return 2;
  }

  gg = (gid_t*)malloc(gg_count * sizeof(gid_t));
  if (gg == NULL) {
    printf(NL "REFUSED: out of memory sizing the token group list." NL);
    free(gl);
    return 2;
  }

  if (getgroups(gg_count, gg) < 0) {
    printf(NL "REFUSED: the second getgroups() call failed." NL);
    free(gl);
    free(gg);
    return 2;
  }

  printf("  count = %d" NL, gg_count);
  print_gids(gg, gg_count);
  is_elevated = has_gid(gg, gg_count, PROBE_ADMIN_GID);
  printf("  %d present: %s" NL, PROBE_ADMIN_GID, is_elevated ? "YES" : "NO");
  printf("  IsElevated()= %s" NL NL, is_elevated ? "TRUE" : "FALSE");

  /* --- 3. The null case this probe exists to refuse -------------------- */

  if (!is_admin) {
    printf("3. REFUSED - THIS ACCOUNT IS NOT AN ADMINISTRATOR." NL NL);
    printf("  %s is not in gid %d, so there is no unelevated" NL,
           pw->pw_name, PROBE_ADMIN_GID);
    printf("  administrator here to measure.  \"IsAdmin() = FALSE\" above is" NL);
    printf("  a fact about this account and NOT the answer to step 1 - and it" NL);
    printf("  is word for word what step 1 is hoping to see, which is why this" NL);
    printf("  refuses rather than reporting it." NL NL);
    printf("  Run this as an administrator, from a shell you have NOT elevated." NL);
    printf("ANSWER: undetermined - the probe did not reach the question." NL);
    free(gl);
    free(gg);
    return 2;
  }

  if (is_elevated && !is_admin) {
    /* Unreachable given the refusal above; kept because the contradiction is
       worth naming if the two lists ever do disagree that way.              */
    printf("3. CONTRADICTION - the token holds %d and the account does not." NL,
           PROBE_ADMIN_GID);
    printf("ANSWER: undetermined - the two calls disagree impossibly." NL);
    free(gl);
    free(gg);
    return 2;
  }

  /* --- 4. The reading ---------------------------------------------------- */

  printf("3. THE DIFFERENCE BETWEEN THE TWO LISTS IS THE MEASUREMENT" NL NL);

  if (is_elevated) {
    printf("  Both calls hold %d." NL, PROBE_ADMIN_GID);
    printf("  THIS IS AN ELEVATED ADMINISTRATOR." NL NL);
  } else {
    printf("  getgrouplist() holds %d and getgroups() does not." NL,
           PROBE_ADMIN_GID);
    printf("  THIS IS AN UNELEVATED ADMINISTRATOR - the case step 1 asks" NL);
    printf("  about.  UAC hands an unelevated administrator a filtered token" NL);
    printf("  carrying Administrators \"for deny only\", and the MSYS2 runtime" NL);
    printf("  omits a deny-only group from getgroups()." NL NL);
  }

  printf("4. WHAT SD's KERNEL KEYS THEREFORE ANSWER FOR A SESSION STARTED" NL);
  printf("   FROM THIS SHELL" NL NL);
  printf("  K$OS.ADMINISTRATOR  = %s" NL, is_admin ? "TRUE" : "FALSE");
  printf("      op_kernel.c:456, IsAdmin() && connection_type != CN_SOCKET" NL);
  printf("      \"is the PERSON an administrator\" - asked of Windows every" NL);
  printf("      time, and a LOGTO does not move it." NL NL);
  printf("  K$ADMINISTRATOR     = %s   AS SEEDED AT PROCESS START" NL,
         is_elevated ? "TRUE" : "FALSE");
  printf("      kernel.c:240, IsElevated() && connection_type != CN_SOCKET" NL NL);
  printf("      READ THAT ONE ONLY BEFORE LOGIN HAS RUN.  LOGIN:615 sets it" NL);
  printf("      to 1 for anybody who reached SDSYS, so a BASIC probe in an" NL);
  printf("      account reads 1 in both legs and measures nothing.  It still" NL);
  printf("      holds the seed at LOGIN's own \"begin case\" (:420), which is" NL);
  printf("      where clause 2's :513 branch has to make its decision." NL NL);

  printf("ANSWER: this shell is an %s administrator." NL,
         is_elevated ? "ELEVATED" : "UNELEVATED");
  printf("        IsAdmin() = %s, IsElevated() = %s." NL,
         is_admin ? "TRUE" : "FALSE", is_elevated ? "TRUE" : "FALSE");

  free(gl);
  free(gg);
  return 0;
}

/* END-CODE */
