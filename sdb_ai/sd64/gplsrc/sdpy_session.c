/* sdpy_session.c - one Python helper per SD session, and the gate that decides
 * whether this session may have one at all.  PROJECT_STATUS.md 5.27 and
 * section 8 constraint 4.
 *
 * ======================================================================
 * ***THE GATE IS THE POINT OF THIS FILE.  READ CONSTRAINT 4 BEFORE CHANGING
 * IT.***
 *
 * Python's os.system never reaches os_permitted() (op_sh.c:156), so an
 * interpreter is a way round the "API access does not give os.execute access"
 * rule unless something stops it earlier.  Constraint 4 measured why the
 * obvious place does not work:
 *
 *   - all 20 PY_* carry $internal,
 *   - $internal sets HDR_INTERNAL (gpl.bp/BCOMP:2875),
 *   - os_permitted() returns TRUE on HDR_INTERNAL BEFORE it reads the
 *     username (op_sh.c:170),
 *
 * ...so a gate called from inside a PY_* passes for EVERY user, always.  The
 * entry's own word for that is decoration.
 *
 * ***SO THE GATE IS HERE, AT THE MOMENT THE PROCESS IS STARTED***, and it
 * asks os_permitted()'s SECOND AND THIRD tests without its first: an
 * administrator always may, otherwise the os.users lookup decides.
 *
 * ***13 Sep 26 - THIS PARAGRAPH USED TO SAY "where process.program is not yet
 * an $internal wrapper and the real user is still visible", AND THAT WAS
 * FALSE.  RELEASE_1.1 23.***  The opcode that reaches sdpy_session() is
 * executed BY !PY_INITIALIZE, whose header flags (0x22, HDR_INTERNAL set) are
 * ORed into process.program.flags by k_call().  So sd_os_permitted(), which
 * then called the whole of os_permitted(), took test 1 and answered TRUE for
 * every user - the gate below was decoration for exactly the reason the
 * paragraph above gives.  Skipping test 1 is now done in op_sh.c
 * (os_user_permitted()), not by choosing a moment: there is no moment inside
 * a PY_* call at which the wrapper is not in process.program.
 *
 * ***AND IT IS CHECKED ONCE PER SESSION, NOT ONCE PER CALL, BECAUSE THE
 * PROCESS IS THE PRIVILEGE.***  Once a helper exists, everything reachable
 * through it is reachable; re-testing on each verb would suggest a revocation
 * that does not exist.  A session that has been refused is refused for as long
 * as it lives, and that is recorded rather than silently retried.
 * ====================================================================== */

#include "sd.h"
#include "header.h"
#include "err.h"
#include "keys.h"
#include "exepath.h"
#include "sdpy_client.h"

#include <stdio.h>
#include <string.h>
/* cygwin_conv_path, for helper_path()'s POSIX -> native conversion.  This file
 * is MSYS2 code by construction - it is compiled into sd.exe - so the header
 * is present; sdpy.exe, which is native, includes nothing from here. */
#include <sys/cygwin.h>

/* One per session.  sd.exe is one process per session, so a file static IS
 * session scope here - the same reasoning that makes the helper per-session in
 * 5.27, and the reason SD's named Python objects cannot leak between users. */
static SDPY* session_helper = NULL;
static int   helper_refused = 0;      /* the gate said no; do not ask again */
/* Which refusal it was, so every later call in this session gives the SAME
 * answer as the first.  RELEASE_1.1 21. */
static int   helper_refused_code = 0;
static char  helper_error[512] = "";

/* op_sh.c.  A WRAPPER round the shell gate, not a second copy of it: Python's
 * os.system never reaches op_sh.c:156, so a session that may not use the shell
 * must not get an interpreter either, and two implementations of that rule
 * would drift silently in the permissive direction. */
extern bool sd_os_permitted(PRIV_WHY* why);

/* Where sdpy.exe lives: BESIDE sd.exe, found with exe_directory().
 *
 * ***NOT "<sysdir>/bin".***  exepath.c exists because both places that
 * launched another SD process built that path, and the Windows layout (5.8)
 * splits binaries into C:\Program Files\SD\usr\bin while pcode stays with
 * SDSYS - so <sysdir>/bin holds no executable at all.  Both call sites failed
 * SILENTLY and both worked in development, where <sysdir>/bin does hold the
 * binaries.  The first version of this function made the same mistake.
 *
 * ***AND THE THIRD MISTAKE IN THAT FAMILY WAS THE PATH FORM - 12 Sep 26,
 * RELEASE_1.1 20, MEASURED ON AN INSTALL.***  exe_directory() answers a POSIX
 * path, because it reads /proc/self/exe, which is the MSYS2 runtime's own
 * interface; exepath.c's header says so and names GetModuleFileName() as "the
 * native answer".  Its other three callers hand the result to execl() and
 * system(), which are POSIX and translate it.  THIS caller does not: the path
 * goes to sdpy_client.c's CreateProcessA, a NATIVE call that never sees the
 * MSYS2 mount table.
 *
 * So every PY_* answered -12040 on a correct install with a healthy helper
 * beside sd.exe.  MEASURED, with a control, by building the two legs with the
 * same MSYS2 gcc sd.exe uses:
 *
 *   CreateProcessA("/c/Program Files/SD/usr/bin/sdpy.exe")  FAILED, error 3
 *   CreateProcessA("C:\\Program Files\\SD\\usr\\bin\\sdpy.exe")  STARTED
 *
 * The conversion is done HERE, at the boundary, rather than in exe_directory()
 * - that function has three POSIX callers which are correct as they are, and
 * changing it would break them to fix this. */
static const char* helper_path(void) {
  static char path[MAX_PATHNAME_LEN + 1] = "";
  char bindir[MAX_PATHNAME_LEN + 1];
  char posix[MAX_PATHNAME_LEN + 1];

  if (path[0] == '\0') {
    int n;
    if (!exe_directory(bindir, sizeof(bindir)))
      return "";                      /* the caller reports "did not start" */
    n = snprintf(posix, sizeof(posix), "%s%csdpy.exe", bindir, DS);
    /* ***A TRUNCATED PATH IS A SILENTLY WRONG PATH.***  It would name some
     * other file, or nothing, and the failure would arrive as "the helper did
     * not start" with a plausible-looking path in the message.  Refuse it
     * instead - the same class of quiet wrongness exepath.c was written for. */
    if (n < 0 || (size_t)n >= sizeof(posix)) {
      path[0] = '\0';
      return "";
    }
    /* POSIX -> native, for the native CreateProcessA downstream.  A failure
     * here is refused out loud the same way a truncation is, rather than
     * passing the untranslated path on to fail less legibly later. */
    if (cygwin_conv_path(CCP_POSIX_TO_WIN_A, posix, path, sizeof(path)) != 0) {
      path[0] = '\0';
      return "";
    }
  }
  return path;
}

/* ***THE GATE.***  TRUE if this session may start a helper.
 *
 * os_permitted()'s own first test is the one that must NOT be reused: it
 * short-circuits on HDR_INTERNAL, which every PY_* carries - and the caller
 * IS inside a PY_* wrapper when this runs (see the banner).  sd_os_permitted()
 * therefore asks os_user_permitted(), tests 2 and 3 only, since 13 Sep 26. */
static int may_start_helper(PRIV_WHY* why) {
  if (why != NULL) *why = PRIV_ANSWERED;
  if (my_uptr == NULL)
    return 0;
  if ((my_uptr->flags & USR_ADMIN) != 0)
    return 1;                          /* an administrator always may */
  return sd_os_permitted(why) ? 1 : 0;
}

/* Return the session's helper, starting it on first use.
 *
 * REFUSAL AND FAILURE ARE DIFFERENT AND THE CALLER IS TOLD WHICH - IN THE
 * CODE, since 12 Sep 26.  Not permitted is SD_PyErr_NotPermitted (-12041),
 * undetermined is SD_PyErr_PrivUnknown (-12042), and a helper that would not
 * start keeps SD_PyErr_NoHelper (-12040).  Confusing them would tell an
 * administrator that Python is broken when it is a permission, or tell an
 * ordinary user they lack a right when the binary is missing.
 *
 * ***THIS COMMENT USED TO CLAIM THE CALLER WAS TOLD, AND IT WAS NOT.***  All
 * three returned -12040 and the difference lived only in helper_error, whose
 * accessor had no caller - RELEASE_1.1 21.  The sentence was true of the
 * intent and false of the code, which is the kind of comment that stops the
 * next reader looking. */
SDPY* sdpy_session(int* err_code) {
  char err[512];

  if (err_code != NULL) *err_code = 0;

  if (session_helper != NULL)
    return session_helper;

  /* ***THE REMEMBERED ANSWER MUST BE THE SAME ANSWER.***  This path returned a
   * bare SD_PyErr_NoHelper while the first refusal returned the real reason,
   * so the SECOND PY_* in a session contradicted the first - and since a
   * session is refused for as long as it lives, that is every call after the
   * first.  It was invisible while all three reasons were -12040.  Splitting
   * the codes without this line would have created the more confusing defect
   * it was meant to cure. */
  if (helper_refused) {
    if (err_code != NULL) *err_code = helper_refused_code;
    return NULL;
  }

  {
    /* ***THE TRI-STATE IS CARRIED, NOT FLATTENED.***  PRE_RELEASE 96 exists
     * because "not permitted" and "could not determine" are different answers
     * and collapsing them loses the one an administrator needs to act on.
     * Both refuse - a helper is not started on an undetermined answer - but
     * they say different things. */
    PRIV_WHY why = PRIV_ANSWERED;
    if (!may_start_helper(&why)) {
      helper_refused = 1;
      /* ***THE CODE CARRIES THE DISTINCTION NOW, NOT JUST THE TEXT.***
       * RELEASE_1.1 21: all three of these returned SD_PyErr_NoHelper and the
       * sentence below was the only thing that told them apart - written into
       * a buffer nothing read.  A caller gets the difference in the one
       * integer the PY_* contract already carries. */
      if (why == PRIV_ANSWERED) {
        (void)snprintf(helper_error, sizeof(helper_error),
                       "this session may not start Python: it is not permitted to use the operating system");
        helper_refused_code = SD_PyErr_NotPermitted;
      } else {
        (void)snprintf(helper_error, sizeof(helper_error),
                       "this session may not start Python: the permission could not be determined (%s)",
                       priv_why_text(why));
        helper_refused_code = SD_PyErr_PrivUnknown;
        /* 13 Sep 26 - AND SAY SO IN THE LOG, as op_sh.c:277 does for
           OS.EXECUTE.  PRE_RELEASE 96's rule: an undetermined answer refuses
           but must not be silent, and helper_error above is read by nobody
           (RELEASE_1.1 21).  Same helper, same wording, one log line. */
        priv_log_undetermined("Python helper start", why);
      }
      if (err_code != NULL) *err_code = helper_refused_code;
      return NULL;
    }
  }

  session_helper = sdpy_start(helper_path(), err, sizeof(err));
  if (session_helper == NULL) {
    helper_refused = 1;               /* do not retry a missing binary per call */
    /* Both halves are bounded: the reason and the path are each worth having,
     * and either one alone has sent somebody looking in the wrong place. */
    (void)snprintf(helper_error, sizeof(helper_error),
                   "the Python helper did not start: %.200s (%.200s)",
                   err, helper_path());
    helper_refused_code = SD_PyErr_NoHelper;
    if (err_code != NULL) *err_code = helper_refused_code;
    return NULL;
  }
  return session_helper;
}

/* Is there a helper already?  ASKS NOTHING AND STARTS NOTHING.
 *
 * PY_IS_INITIALIZED needs this: "is Python running" asked of a session that
 * has no helper is answered no, and answering it by STARTING one would make
 * the question change the world it is asking about. */
int sdpy_session_running(void) {
  return session_helper != NULL;
}

/* The last refusal or failure, for a caller that wants to say why.  Never
 * NULL; empty when nothing has gone wrong. */
const char* sdpy_session_error(void) {
  return helper_error;
}

/* Called when the session ends.  The helper would die with its parent anyway -
 * the pipe closes - but QUIT lets it finalise the interpreter rather than be
 * torn down in the middle of a call. */
void sdpy_session_end(void) {
  if (session_helper != NULL) {
    sdpy_stop(session_helper);
    session_helper = NULL;
  }
  helper_refused = 0;
  helper_refused_code = 0;
  helper_error[0] = '\0';
}
