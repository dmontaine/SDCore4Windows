/* OP_SH.C
 * Shell command execution
 * Copyright (c) 2007 Ladybridge Systems, All Rights Reserved
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 * 
 * START-HISTORY:
 * 25 Oct 26 Windows port - from Linux 2a68b2f (24 Oct 26) W.11 F9: every privilege and gate test reads the process's own words (MY_ADMIN, MY_PRIV, MY_GATE: sysseg.h), not the user
 *           table entry; the register and the shared account are under sd_sysdir().
 * 25 Oct 26 Windows port - from Linux fc4030a (S.66): the shared account.  shared_root_get() (the account's directory from its register record, a hit
 *           kept, a miss retried once a minute, SUSPENDED not looked at), path_in_shared(), path_resolved_in_shared(), shared_write_ok(),
 *           edit_refusal_for_canon() and edit_refusal_for_name() (administrator, then shared.write, then the S.64 kind), shared_ref_ok()
 *           (K_SHARED_REF), shared_once() (K_SHARED_ONCE) and edit_refused_message().  edit_ok_for_path() uses the name form.
 * 23 Oct 26 Windows port - from Linux d7cda81 and b6186cc (17 Oct 26), S.64, the edit gates: edit_kind_of_path(), edit_permitted(), edit_ok_for_path(),
 *           edit_os_path_refusal(name, include_leaf), edit_leaf_counts() and the private catalogue as a program file.  Linux resolves with
 *           getcwd / realpath and "/" only; here the name is resolved by fullpath() and folded by path_view_for_edit() / path_fold()
 *           (op_dio2.c), which know the drive letter, the case and the two namespaces.  RELEASE_1.1 170.
 * 23 Oct 26 Windows port - from Linux 215ce2c (13 Oct 26), S.63, on the owner's two answers of 23 Oct: the SH and OS.EXECUTE
 *           grants are the ACCOUNT's (USR_SH, USR_OS_EXEC, loaded at account entry from ACC$SH / ACC$OS.EXEC), not the
 *           person's os.users record, which the kernel no longer reads; every session, a local console included, is held
 *           to its own account's files unless it holds OS.EXECUTE (os_path_ok_for_account, account_path_permitted in
 *           op_dio2.c); K_PATH_OK lets an $internal program ask the same question for the user.  RELEASE_1.1 170.
 * 17 Sep 26 Windows port - sd_powershell_path() lifted out of sh_execute()
 *           so linuxprt.c's spooler finds PowerShell the same way
 *           (RELEASE_1.1 54).
 * 13 Sep 26 Windows port - os_permitted() split: tests 2 and 3 are now
 *           os_user_permitted(), and sd_os_permitted() - the Python gate -
 *           calls THAT, without the HDR_INTERNAL test.  The gate ran inside
 *           the $internal PY_* wrapper and passed every user.  RELEASE_1.1 23.
 * 05 Sep 26 Windows port - SH1 carries -ExecutionPolicy Bypass.  Without it
 *           every shipped .ps1 SD runs is refused on a stock Windows client,
 *           whose default policy is Restricted.  PRE_RELEASE_FIXES 173.
 *           SH1's clparse bound is 8 rather than 9 in the same change: this
 *           branch appends two argv entries, so 9 could write one past the
 *           end of a ten-pointer array.  PRE_RELEASE_FIXES 174.
 * 19 Aug 26 Windows port - OS.EXECUTE is gated.  It was open to every user
 *           from a program while SH was refused at the prompt.
 *           PROJECT_STATUS.md section 4 / section 7 step 7.
 * 17 Oct 26 dm S.64 part 2 (Linux): the private catalogue directory (the value of $PRIVATE.CATALOGUE, "cat" by default, resolved against
 *           the account directory, never by the bare name) is a PROGRAM FILE; edit_os_path_refusal() takes include_leaf.
 * 18 Oct 26 Windows port - from Linux 5315c65 - S.65 slice 3e: edit_kind_of_net_name(): which S.64 kind (VOC, dictionary, program file) the name of a file on another SD
 *           server says it is; a "dict " prefix is a dictionary. net_gate() and K_EDIT_OK / K_EDIT_KIND use it through the file variable.
 * 17 Oct 26 Windows port - from Linux 5315c65 - S.64 part 2: the private catalogue directory (the value of $PRIVATE.CATALOGUE, "cat" by default, resolved against
 *           the account directory as the OS resolves it, never by the bare name) is a PROGRAM FILE: edit_kind_of_path() answers
 *           EDIT_PROG for it and edit_os_path_refusal() for it and for anything below it. The scan of a last component moved to
 *           edit_kind_of_name(), because edit_os_path_refusal() classifies bare components. edit_os_path_refusal() takes
 *           include_leaf: OPENSEQ, DELETESEQ and a print file name a plain file as the final component, and that name is a
 *           record, not a program file. edit_leaf_counts() decides it for OSCOPY's target and OSPATH's delete (a directory or
 *           anything that is not a plain file counts).
 * 17 Oct 26 dm S.64: edit_kind_of_path(), edit_permitted() and edit_ok_for_path(): which of a VOC, a dictionary and a
 *           program file a pathname is, and whether the session may save a change to it (the gates voc.edit, dict.edit
 *           and bp.edit, loaded at sign-on into the user table's gates word). op_dio3.c asks them before a write, a
 *           delete or a clear; K_EDIT_OK and K_EDIT_KIND let a $internal program ask the same question.
 * 13 Oct 26 dm S.63: os_permitted() is back, and the gate now reaches OS paths. OS.EXECUTE and the SH
 *           verb are refused (10053, 10054, the Windows port's wording) to an account that has not been
 *           given them; OPENSEQ and OPENPATH by pathname are refused (ER_PERM) outside the account's own
 *           directory unless it holds OS.EXECUTE; K_PATH_OK lets an $internal program (SED) ask the same
 *           question on the user's behalf. SH and OS.EXECUTE are OFF by default and SDSYS switches them
 *           (owner, 13 Oct 2026: the tiers were to go and the gates to stay).
 * 18 Sep 26 dm Teardown (S.27): os_permitted() and its refusal are gone.
 *           OS.EXECUTE and the SH verb now run at the account's own Linux
 *           permissions - the euid drop already made a session the account's
 *           OS user, and SD keeps no second wall (owner's teardown of the
 *           tier model, 18 Sep 2026).
 * 10 Sep 26 dm  Parity audit: the SH1 clparse bound is 8, so a long configured
 *               SH1 cannot write past argv (the Windows port's PRE_RELEASE 174).
 * 09 Sep 26 dm PRE_RELEASE 23 commit 2: os_permitted() also honours USR_OS_EXEC,
 *           the per-account ACC$OS.EXEC grant loaded at account entry, so an
 *           administrator can give a named non-admin account OS.EXECUTE.
 * 09 Sep 26 dm PRE_RELEASE 23 commit 1: os_permitted() gates OS.EXECUTE to a
 *           $internal program or an administrator (owner's model, 9 Sep 26:
 *           "os.execute and shell are off for anyone but administrators").
 *           op_sh() was previously ungated.  The per-account ACC$OS.EXEC grant
 *           that widens this to named non-admins is commit 2.
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"
#include "syscom.h"
#include "tio.h"
#include "config.h"
#include <signal.h>
#include <time.h>

#include <sys/wait.h>

/* Modified by Composer AI - 2026/06/10.
   k_error() never returns, but the analyzer cannot see that across
   translation units. */
void k_error(char msg[], ...) __attribute__((noreturn));
/* -------------------- */

void set_term(bool trap_break);
void set_old_tty_modes(void);
void set_new_tty_modes(void);
void op_capture(void);

Private void sh(bool capture);
Private bool os_permitted(PRIV_WHY* why);
Private bool os_user_permitted(PRIV_WHY* why);
Private void sh_execute(char *command);
Private int clparse(char *p, char *argv[], int maxargs);

int ChildPipe = -1;
bool in_sh = FALSE; /* 0562 Doing SH command? */

#define MAX_SH_COMMAND_LENGTH 32000
Private char *cmd_str = NULL;

/* ======================================================================
   op_sh()  -  Launch a DOS command                                       */

void op_sh() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  Command to execute         |                             |
     |=============================|=============================|
 */

  sh(FALSE);
}

/* ======================================================================
   op_shcap  -  Launch SH command, capturing output                       */

void op_shcap() {
  /* Stack:

     |=============================|=============================|
     |            BEFORE           |           AFTER             |
     |=============================|=============================|
 top |  ADDR to capture variable   |                             |
     |-----------------------------|-----------------------------|
     |  Command to execute         |                             |
     |=============================|=============================|
 */

  DESCRIPTOR temp;

  /* Swap top two stack items so that the command is on top */

  temp = *(e_stack - 1);
  *(e_stack - 1) = *(e_stack - 2);
  *(e_stack - 2) = temp;

  sh(TRUE);
}

/* ======================================================================
   sd_os_permitted()  -  os_permitted() for callers outside this file.

   12 Sep 26 Windows port - PROJECT_STATUS.md 5.27 and section 8 constraint 4.

   ***THIS EXISTS SO THE PYTHON GATE ASKS THE SAME QUESTION AS THE SHELL GATE,
   RATHER THAN A SECOND COPY OF IT.***  sdpy_session.c decides whether a
   session may start a Python helper, and constraint 4's whole point is that
   the answer must be the OS-access answer: Python's os.system never reaches
   op_sh.c:156, so a session that may not use the shell must not get an
   interpreter either.  Two implementations of one rule would drift, and the
   drift would be silent and in the permissive direction.

   os_permitted() itself stays Private - including its PRIV_WHY tri-state,
   which test-privwhy-units guards - and this is a wrapper, not a copy.

   ***13 Sep 26 - IT ASKS os_user_permitted(), NOT os_permitted(), AND THE
   DIFFERENCE IS THE WHOLE GATE.  RELEASE_1.1 23.***  This used to return
   os_permitted(why), with a comment saying the caller "must not be inside a
   $internal program when it asks" and that starting the helper from the
   opcode rather than from BASIC made that so.  IT DID NOT.  The opcode is
   executed BY the $internal wrapper: k_call() ORs the callee's header flags
   into process.program.flags (kernel.c:1006), !PY_INITIALIZE's flags word is
   0x22 = HDR_INTERNAL | HDR_IS_FUNCTION, and os_permitted()'s first test
   answered TRUE before reading the username - for every user.  The os.users
   branch, the reason the gate exists, was unreachable.  Section 8 constraint
   4 had specified "the second and third tests without the first" in as many
   words; this is that, and test-privwhy-units now refuses a wrapper that goes
   through test 1 again. */

bool sd_os_permitted(PRIV_WHY* why) {
  return os_user_permitted(why);
}

/* ======================================================================
   os_permitted()  -  May this session reach the operating system?         */

/* 19 Aug 26 Windows port - PROJECT_STATUS.md section 4, and the C half of
 * section 7 step 7.
 *
 * THE HOLE THIS CLOSES, measured with its control on the 15:30:36 install:
 * from ONE unelevated session standing in DON, "SH echo ..." at the prompt
 * answered "don is not permitted to use the operating system shell", while a
 * program compiled in that same user's own BP running
 * "os.execute 'cmd /c echo ...' capturing cap" captured the output and ran.
 * Same user, same session - the visible route refused and the real one open.
 *
 * CPROC's os.command: gate is not on this path and cannot be.  OS.EXECUTE is
 * its own BASIC statement - BCOMP:9643, OP.SH / OP.SHCAP, both landing in
 * sh() - so neither kernel(K$ADMINISTRATOR,-1) nor !valid_shell_cmd is
 * anywhere near it.  This is the one place both forms pass through.
 *
 * THREE WAYS IN, AND THE FIRST IS WHAT KEEPS "SH" WORKING.
 *
 *  1. HDR_INTERNAL.  The SH verb reaches the OS by CPROC itself doing
 *     os.execute, so by the time control arrives here the verb and the
 *     statement are the same code and C cannot tell them apart.  CPROC is
 *     $internal and has ALREADY applied the finer rule - OS.USERS field 1 -
 *     so trusting the marker here leaves SH exactly as it was.  IT CANNOT BE
 *     FORGED: BCOMP:2864 honours $INTERNAL only for a session that is itself
 *     internal AND elevated, so an ordinary user cannot compile a program
 *     that carries it.
 *  2. An elevated session, exactly as SH allows one.  An administrator at the
 *     console has to keep this whatever the file says, or an empty OS.USERS
 *     locks the machine's own administrator out of it.
 *  3. OS.USERS field 2, "OS.EX".  Field 1 is SH and field 2 is this one;
 *     until now field 2 was stored, dictionaried and read by nobody.
 *
 * MISSING FILE OR MISSING RECORD MEANS NO.  That is the behaviour before this
 * existed and it is the safe direction.  It is the OPPOSITE of the tier lists
 * in NEWVOC, where a missing record means the FULL VOC - do not carry that
 * convention across.
 *
 * THE ACL ON OS.USERS IS THE WHOLE OF THE PROTECTION.  gplbld/secure-osusers.ps1
 * makes it read-only to sdusers; without that a user grants themselves this in
 * one line and the gate below is decoration.
 *
 * 13 Sep 26 Windows port - SPLIT IN TWO, AND THE SPLIT IS THE FIX.
 * RELEASE_1.1 23.  Test 1 stays here; tests 2 and 3 are os_user_permitted()
 * below, so that sd_os_permitted() - the Python gate - can ask them WITHOUT
 * test 1.  Section 8 constraint 4 specified the Python gate as "os_permitted()'s
 * second and third tests without its first", and the wrapper as first written
 * called all three: the SDEXT opcode that starts the helper executes INSIDE
 * !PY_INITIALIZE, which is $internal (flags word 0x22 in the shipped object),
 * so test 1 answered TRUE for every user and the os.users branch was never
 * reached.  One body for tests 2 and 3, two entry points, no copy.
 */

Private bool os_permitted(PRIV_WHY* why) {
  /* 03 Sep 26 Windows port - PRE_RELEASE_FIXES.md 96.  Set once, overwritten
     by whichever exit could not finish.  See linuxlb.h.                    */

  if (why != NULL)
    *why = PRIV_ANSWERED;

  if (process.program.flags & HDR_INTERNAL)
    return TRUE;

  return os_user_permitted(why);
}

/* ======================================================================
   os_user_permitted()  -  Tests 2 and 3 of os_permitted(), on their own.

   The session's OWN standing, with no regard to what program is running:
   an administrator always may, otherwise OS.USERS field 2 decides.  This is
   the question the Python gate has to ask, because by the time it asks,
   process.program is a $internal wrapper whatever the user's standing is.
   sh() never calls this directly - it goes through os_permitted() so that SH
   from CPROC keeps test 1.                                                */

Private bool os_user_permitted(PRIV_WHY* why) {
  /* 23 Oct 26 Windows port - from Linux 215ce2c (S.63), on the owner's answer of 23 Oct.  The grant is the ACCOUNT's,
     not the person's: USR_OS_EXEC is loaded at account entry (LOGIN, CPROC logto) from the register field ACC$OS.EXEC, and
     the person's record file this function used to read is retired.  Nothing is read from disk here, so there is no
     "could not complete" answer to log: the tri-state stays for IsAdmin() and the callers that still take it.
     RELEASE_1.1 170.                                                                                                  */
  if (why != NULL)
    *why = PRIV_ANSWERED;

  return os_gate_open();
}

/* ======================================================================
   os_gate_open()  -  has THIS ACCOUNT been given OS access?  (23 Oct 26, S.63)

   The administrator always has it; anyone else has it only if SDSYS switched OS.EXECUTE on for the account
   (MODIFY.ACCOUNT name OS-ON), which LOGIN and CPROC logto load into the session.  It does NOT look at HDR_INTERNAL,
   because the question is about the account, not the program: an $internal program that acts for the user (SED opening
   a file by pathname) is exempt from the gate itself and must not become the way round it.                          */

bool os_gate_open(void) {
  return MY_PRIV(USR_ADMIN | USR_OS_EXEC);
}

/* os_path_ok_for_account()  -  may this account open this OS pathname?  Yes if it holds the OS gate; otherwise only
   inside its own account, plus the SDSYS entries every VOC names (read only) and the NETDIRS the administrator listed:
   account_path_permitted() in op_dio2.c, which resolves the name as the open would.  A name it cannot resolve is a no.  */

bool os_path_ok_for_account(const char *name) {
  char resolved[MAX_PATHNAME_LEN + 1];

  if (os_gate_open())
    return TRUE;
  if ((name == NULL) || (name[0] == '\0'))
    return FALSE;
  if (!fullpath(resolved, (char *)name))
    return FALSE;
  if (account_path_permitted(resolved, TRUE))
    return TRUE;
  /* 23 Oct 26, Linux 7ceb50d: the SD.ACCOUNTS gate, between the own account and OS.EXECUTE (op_dio2.c) */
  return MY_PRIV(USR_SD_ACCOUNTS) && path_in_enterable_account(resolved);
}

/* os_path_open_ok()  -  the same for a caller: an $internal program is trusted, anyone else is asked. */

bool os_path_open_ok(const char *name) {
  if (process.program.flags & HDR_INTERNAL)
    return TRUE;
  return os_path_ok_for_account(name);
}

/* ======================================================================
   last_component()  -  The final component of a pathname, trailing slashes ignored.  Returns a pointer into PATH and sets
   *LEN to its length, which is 0 for a null name or a bare "/".                                                       */

Private const char *last_component(const char *path, size_t *len) {
  const char *last;
  const char *p;
  size_t n;

  *len = 0;
  if (path == NULL)
    return NULL;
  n = strlen(path);
  while ((n > 0) && (path[n - 1] == '/'))
    n--;
  if (n == 0)
    return NULL;
  last = path;
  for (p = path; p < path + n; p++) {
    if (*p == '/')
      last = p + 1;
  }
  *len = (size_t)((path + n) - last);
  return last;
}

/* ======================================================================
   edit_kind_of_name()  -  Which of the three guarded kinds of file does the LAST COMPONENT of this name say it is?

   17 Oct 26 dm, S.64 (owner, 17 Oct: the gates voc.edit, bp.edit and dict.edit).  By the last component of the pathname
   of the OPEN file, not by the name that was typed, so a Q-pointer or an F-pointer to one is caught (Linux Solo's
   voc_write_refused() does the same for the VOC alone).  Case does not matter; every name SD makes is lower case.
     VOC          voc
     dictionary   anything ending .dic         (voc.dic is the dictionary of the VOC, not the VOC)
     program      bp, bp.out, anything ending .bp or .bp.out
   bp.out is in because an object file written straight into it is the same as compiling one (owner's D3, 17 Oct, said
   "bp or *.bp"; the object directory is part of that meaning and the plan file says so).  A trailing slash is ignored.

   Names only.  edit_os_path_refusal() classifies the bare components of a path with this; the private catalogue is a place,
   not a name, and is added by edit_kind_of_path() for the pathname of a file.                                          */

Private int edit_kind_of_name(const char *path) {
  const char *last;
  size_t n;

  last = last_component(path, &n);
  if (n == 0)
    return EDIT_NONE;

  if ((n == 3) && (strncasecmp(last, "voc", 3) == 0))
    return EDIT_VOC;
  if ((n > 4) && (strncasecmp(last + n - 4, ".dic", 4) == 0))
    return EDIT_DICT;
  if ((n == 2) && (strncasecmp(last, "bp", 2) == 0))
    return EDIT_PROG;
  if ((n == 6) && (strncasecmp(last, "bp.out", 6) == 0))
    return EDIT_PROG;
  if ((n > 3) && (strncasecmp(last + n - 3, ".bp", 3) == 0))
    return EDIT_PROG;
  if ((n > 7) && (strncasecmp(last + n - 7, ".bp.out", 7) == 0))
    return EDIT_PROG;
  return EDIT_NONE;
}

/* ======================================================================
   The private catalogue as a program file (17 Oct 26 dm, S.64 part 2, from the review).

   CATALOG, DELETE.CATALOG and DECATALOG are refused without bp.edit (message 12413) because they change the code a command
   finds, and the catalogue is a plain directory: with nothing here, OPENPATH "cat" and DELETE / CLEARFILE / WRITE on it, a
   Q- or F-pointer to it, OSCOPY into it and OSPATH on it did the same thing with no gate.  So the directory is a program file.

   WHICH DIRECTORY: the one the kernel loads commands from, private_catalogue (set by the K$PRIVATE.CATALOGUE key from the
   $PRIVATE.CATALOGUE entry of the VOC, "cat" when there is none), resolved against the account directory as a pathname is
   resolved by the OS gate.  NOT by the bare name "cat": a data directory that happens to be called cat somewhere else is
   an ordinary file.  The gate follows the configured catalogue, and a catalogue outside the account is still one.

   The private catalogue is a per-process variable, like the account directory, so nothing here is shared between users.    */

/* private_catalogue_dir()  -  the private catalogue directory, resolved and folded (path_fold) into CAT (MAX_PATHNAME_LEN + 1 bytes), without
   a trailing slash.  fullpath() resolves a relative name against the working directory, which is the account's.  FALSE when there is none,
   it cannot be resolved or folded, or it would be the root.                                                                           */
Private bool private_catalogue_dir(char *cat) {
  char resolved[MAX_PATHNAME_LEN + 1];
  size_t n;

  if ((private_catalogue[0] == '\0') || !fullpath(resolved, private_catalogue) || !path_fold(resolved, cat))
    return FALSE;
  n = strlen(cat);
  while ((n > 1) && (cat[n - 1] == '/'))
    cat[--n] = '\0';
  return (n > 1);
}

/* catalogue_position()  -  where is this FOLDED pathname against the private catalogue?  0 elsewhere, 1 the directory itself, 2 something
   below it.  Case does not matter (NTFS).                                                                                              */
Private int catalogue_position(const char *folded) {
  char cat[MAX_PATHNAME_LEN + 1];
  size_t n;

  if (!private_catalogue_dir(cat))
    return 0;
  n = strlen(cat);
  if (strncasecmp(folded, cat, n) != 0)
    return 0;
  if (folded[n] == '\0')
    return 1;
  return (folded[n] == '/') ? 2 : 0;
}

/* path_is_private_catalogue()  -  is this the pathname OF the private catalogue directory (the pathname of an open file)?
   edit_kind_of_path() is asked before every WRITE a session makes to a file it may not be allowed to change, so the test
   that costs something - resolving two paths - is made only when the last component is the catalogue's own name.        */
Private bool path_is_private_catalogue(const char *path) {
  char resolved[MAX_PATHNAME_LEN + 1];
  char folded[MAX_PATHNAME_LEN + 1];
  const char *last;
  const char *cat_last;
  size_t n, cat_n;

  last = last_component(path, &n);
  cat_last = last_component(private_catalogue, &cat_n);
  if ((n == 0) || (cat_n == 0) || (n != cat_n) || (strncasecmp(last, cat_last, n) != 0))
    return FALSE;
  /* Same final name: now by place.  A name that cannot be placed is taken as the catalogue (a gate that fails open on a path it
     cannot read is decoration); only a file of the catalogue's own name reaches here. */
  if (!fullpath(resolved, (char *)path) || !path_fold(resolved, folded))
    return TRUE;
  return catalogue_position(folded) == 1;
}

/* ======================================================================
   edit_kind_of_path()  -  Which of the three guarded kinds of file is this?  The PATHNAME of an open file: by its last
   component (edit_kind_of_name), or the private catalogue directory, which is a program file.                          */

int edit_kind_of_path(const char *path) {
  int kind = edit_kind_of_name(path);

  if ((kind == EDIT_NONE) && path_is_private_catalogue(path))
    return EDIT_PROG;
  return kind;
}

/* ======================================================================
   edit_kind_of_net_name()  -  The same question for the NAME of a file on another SD server (S.65 slice 3e), which is how a remote
   file is told apart: "voc", "<name>.dic", "bp", "bp.out", "<name>.bp", "<name>.bp.out", or "dict <name>" for the dictionary part of
   any file.  The name has no '/' (the handler refuses one), so edit_kind_of_name() sees all of it.  NOT edit_kind_of_path(): its
   private catalogue test resolves a path against this process's directory, which says nothing about a name on another machine.  */

int edit_kind_of_net_name(const char *name) {
  if (strncasecmp(name, "dict ", 5) == 0)
    return EDIT_DICT;
  return edit_kind_of_name(name);
}

/* edit_permitted()  -  may THIS SESSION save a change to a file of that kind?  The administrator may always; anybody else
   needs the gate for the kind, loaded at sign-on (UG_x in the user table's gates word) from the register.            */

bool edit_permitted(int kind) {
  if (MY_ADMIN())
    return TRUE;
  switch (kind) {
    case EDIT_VOC:
      return MY_GATE(UG_VOC_EDIT);
    case EDIT_DICT:
      return MY_GATE(UG_DICT_EDIT);
    case EDIT_PROG:
      return MY_GATE(UG_BP_EDIT);
  }
  return TRUE;
}

/* ======================================================================
   The SHARED ACCOUNT (18 Oct 26 dm, S.66).  A group account named "shared" whose files every account with the shared.read gate opens by
   name (the BASIC lookup, GPL.BP/_VOC_REF and !SHARED_REF, decides that); the KERNEL's half is here: where the shared account is, whether a
   path is inside it, what a session may do to a file inside it, and the acceptance test for a VOC entry that points into it.

   The shared account's directory is found as LOGTO and path_in_enterable_account() find an account: line 1 of the register record
   <sysdir>/accounts/shared, resolved with realpath().  A HIT is kept for the life of the process.  A MISS is not: a session that was
   started before the installer made the account must begin enforcing when it appears, so the try is repeated, but no more often than
   once a minute.  SUSPENDED is NOT looked at here: suspension withdraws the by-name lookup in BASIC and must never unprotect the files.  */

#define SHARED_RETRY_SECONDS 60

/* 25 Oct 26 Windows port: Linux resolved the root with realpath() and compared bytes after "/".  Here the register record holds a Windows
   path (or @SDSYS<rest>), so the root is resolved as an open resolves it (fullpath) and FOLDED into the POSIX namespace (path_fold) once; a
   candidate is folded the same way and compared case-insensitively on a component boundary, as path_within() in op_dio2.c does.  OUT has
   MAX_PATHNAME_LEN + 1 bytes and receives the folded root.  */
bool shared_root_get(char *out) {
  static char root[MAX_PATHNAME_LEN + 1];
  static bool have = FALSE;
  static time_t last_try = 0;
  char path[MAX_PATHNAME_LEN + 1];
  char body[4096];
  char line1[MAX_PATHNAME_LEN + 2];
  char resolved[MAX_PATHNAME_LEN + 1];
  char folded[MAX_PATHNAME_LEN + 1];
  FILE *fp;
  size_t got, n;
  char *p;
  time_t now;

  if (have) {
    strcpy(out, root);
    return TRUE;
  }
  now = time(NULL);
  if ((last_try != 0) && (now >= last_try) && ((now - last_try) < SHARED_RETRY_SECONDS))
    return FALSE;
  last_try = now;

  if (snprintf(path, sizeof(path), "%s%caccounts%cshared", sd_sysdir(), DS, DS) >= (int)sizeof(path))
    return FALSE;
  if ((fp = fopen(path, "r")) == NULL)
    return FALSE;
  got = fread(body, 1, sizeof(body) - 1, fp);
  fclose(fp);
  body[got] = '\0';
  if ((p = strchr(body, '\n')) != NULL)
    *p = '\0';
  n = strlen(body);
  while ((n > 0) && ((body[n - 1] == '\r') || (body[n - 1] == ' ')))
    body[--n] = '\0';
  if (n == 0)
    return FALSE;
  if (strncasecmp(body, "@SDSYS", 6) == 0) {
    if (snprintf(line1, sizeof(line1), "%s%s", sd_sysdir(), body + 6) >= (int)sizeof(line1))
      return FALSE;
  } else if (body[0] == '@') {
    return FALSE; /* some other token: not expanded here, so not trusted */
  } else {
    if (n > MAX_PATHNAME_LEN)
      return FALSE;
    strcpy(line1, body);
  }
  if (!fullpath(resolved, line1) || !path_fold(resolved, folded))
    return FALSE;
  n = strlen(folded);
  while ((n > 1) && (folded[n - 1] == '/'))
    folded[--n] = '\0';
  if (n <= 1)
    return FALSE;

  strcpy(root, folded);
  have = TRUE;
  strcpy(out, root);
  return TRUE;
}

/* shared_within()  -  is the FOLDED pathname CAND at or below the folded ROOT (strictly below when STRICT)? */
static bool shared_within(const char *cand, const char *root, bool strict) {
  size_t len = strlen(root);

  if (strncasecmp(cand, root, len) != 0)
    return FALSE;
  if (cand[len] == '\0')
    return !strict;
  return (cand[len] == '/') && (!strict || (cand[len + 1] != '\0'));
}

/* path_in_shared()  -  is this CANONICAL pathname (the pathname of an open file, as fullpath() left it) the shared account's directory
   or below it?  No system call but the rare root lookup.  A path that cannot be folded is taken as inside (a gate that fails open on a path
   it cannot read is decoration), once the root is known.  */
bool path_in_shared(const char *canon) {
  char root[MAX_PATHNAME_LEN + 1];
  char folded[MAX_PATHNAME_LEN + 1];
  char copy[MAX_PATHNAME_LEN + 1];

  if ((canon == NULL) || !shared_root_get(root))
    return FALSE;
  if (strlen(canon) > MAX_PATHNAME_LEN)
    return TRUE;
  strcpy(copy, canon);
  if (!path_fold(copy, folded))
    return TRUE;
  return shared_within(folded, root, FALSE);
}

/* path_resolved_in_shared()  -  the same for any name: resolved as an open resolves it first.  With the root known, a name that
   cannot be resolved is taken as inside.  */
bool path_resolved_in_shared(const char *name) {
  char root[MAX_PATHNAME_LEN + 1];
  char resolved[MAX_PATHNAME_LEN + 1];

  if (!shared_root_get(root))
    return FALSE;
  if ((name == NULL) || (name[0] == '\0'))
    return FALSE;
  if (!fullpath(resolved, (char *)name))
    return TRUE;
  return path_in_shared(resolved);
}

/* shared_write_ok()  -  may this session save a change to a record of a file in the shared account? */
bool shared_write_ok(void) {
  return MY_ADMIN() || MY_GATE(UG_SHARED_WRITE);
}

/* edit_refusal_for_canon()  -  the kind that refuses THIS SESSION's write to a file with this canonical pathname, else EDIT_NONE.
   The order matters: the administrator; then shared.write for anything inside the shared account; then the S.64 kind (VOC, dictionary,
   program file).  So a write to a shared dictionary needs shared.write AND dict.edit, and the refusal names the first that is missing.  */
int edit_refusal_for_canon(const char *canon) {
  int kind;

  if (MY_ADMIN())
    return EDIT_NONE;
  if (path_in_shared(canon) && !shared_write_ok())
    return EDIT_SHARED_WRITE;
  kind = edit_kind_of_path(canon);
  if ((kind != EDIT_NONE) && !edit_permitted(kind))
    return kind;
  return EDIT_NONE;
}

/* edit_refusal_for_name()  -  the same for a string from BASIC, which is resolved first. */
int edit_refusal_for_name(const char *name) {
  int kind;

  if (MY_ADMIN())
    return EDIT_NONE;
  if (path_resolved_in_shared(name) && !shared_write_ok())
    return EDIT_SHARED_WRITE;
  kind = edit_kind_of_path(name);
  if ((kind != EDIT_NONE) && !edit_permitted(kind))
    return kind;
  return EDIT_NONE;
}

bool edit_ok_for_path(const char *path) {
  return edit_refusal_for_name(path) == EDIT_NONE;
}

/* edit_refused_message()  -  the message number for a refusing kind (edit_refusal_for_*, create_edit_refusal, the structure refusals). */
int edit_refused_message(int kind) {
  switch (kind) {
    case EDIT_VOC:
    case EDIT_DICT:
    case EDIT_PROG:
      return 12409 + kind;
    case EDIT_SHARED_WRITE:
      return 12518;
    case EDIT_SHARED_STRUCT:
      return 12519;
  }
  return 12410;
}

/* shared_ref_ok()  -  K_SHARED_REF.  May the F-pointer target PATH (field FNO of a VOC entry of the shared account: 2 the data part, 3 the
   dictionary part) be opened by name by another account?  Only a file that exists, strictly BELOW the shared directory, with no
   component below it that is a VOC, a program file or the private catalogue, and no dictionary where a data file is wanted (a
   dictionary only as the last component of field 3).  CATNAME is the shared account's own $PRIVATE.CATALOGUE value; edit_kind_of_path()
   cannot see it, since it compares with the CALLER's catalogue.  No message.  */
bool shared_ref_ok(const char *path, int fno, const char *catname) {
  char root[MAX_PATHNAME_LEN + 1];
  char absp[MAX_PATHNAME_LEN + 1];
  char resolved[MAX_PATHNAME_LEN + 1];
  char comp[MAX_PATHNAME_LEN + 1];
  const char *cat_last;
  const char *p;
  const char *more;
  size_t root_len, cat_n, n;
  int kind;
  bool is_last;

  if ((fno != 2) && (fno != 3))
    return FALSE;
  /* 25 Oct 26 Windows port: the target is resolved as an open resolves it (fullpath) and folded into the root's namespace; it must exist */
  if ((path == NULL) || (path[0] == '\0') || (strlen(path) > MAX_PATHNAME_LEN) || !shared_root_get(root))
    return FALSE;
  if (!fullpath(absp, (char *)path) || !path_fold(absp, resolved))
    return FALSE;
  if (access(absp, F_OK) != 0)
    return FALSE;
  root_len = strlen(root);
  if (!shared_within(resolved, root, TRUE))
    return FALSE;

  cat_last = NULL;
  cat_n = 0;
  if ((catname != NULL) && (catname[0] != '\0'))
    cat_last = last_component(catname, &cat_n);

  for (p = resolved + root_len; *p != '\0';) {
    while (*p == '/')
      p++;
    n = 0;
    while ((p[n] != '\0') && (p[n] != '/'))
      n++;
    if (n == 0)
      break;
    more = p + n;
    while (*more == '/')
      more++;
    is_last = (*more == '\0');
    if (n >= sizeof(comp))
      return FALSE;
    memcpy(comp, p, n);
    comp[n] = '\0';
    kind = edit_kind_of_name(comp);
    if ((fno == 3) && is_last) {
      if (kind != EDIT_DICT)
        return FALSE;
    } else if (kind != EDIT_NONE) {
      return FALSE;
    }
    if (strcasecmp(comp, "cat") == 0)
      return FALSE;
    if ((cat_last != NULL) && (cat_n == n) && (strncasecmp(comp, cat_last, n) == 0))
      return FALSE;
    p += n;
  }
  return TRUE;
}

/* shared_once()  -  K_SHARED_ONCE.  TRUE the first time this process asks about a name, FALSE afterwards.  64 names of up to 63
   characters are remembered; when the table is full the answer is TRUE (more audit, never less).  */
bool shared_once(const char *name) {
  static char seen[64][64];
  static int count = 0;
  char key[64];
  int i;

  if ((name == NULL) || (name[0] == '\0'))
    return TRUE;
  strncpy(key, name, sizeof(key) - 1);
  key[sizeof(key) - 1] = '\0';
  for (i = 0; i < count; i++) {
    if (strcasecmp(seen[i], key) == 0)
      return FALSE;
  }
  if (count >= 64)
    return TRUE;
  strcpy(seen[count++], key);
  return TRUE;
}

/* edit_os_path_refusal()  -  the OS-PATH routes to the same files: OPENSEQ, DELETESEQ, OSRENAME, a print file, OSCOPY.

   A program file's records are files of a directory, so OPENSEQ 'bp','prog' and WRITESEQ change one as WRITE would, past the test
   in op_dio3.c; a dictionary or the VOC can be corrupted the same way.  So the pathname a program gives is looked at for a
   component that names a VOC, a dictionary or a program file: the path is resolved as the OS gate resolves it, and every component
   below the account's own directory is classified (edit_kind_of_name).  Returns EDIT_NONE when the session may go on, or the kind
   it may not change.  Read-only use is not asked: the callers use this where they would write, create, delete or rename.

   INCLUDE_LEAF says whether the FINAL component is classified too.  A caller that names a plain file there - OPENSEQ, DELETESEQ and
   a print file make or remove a regular file, never a directory - passes FALSE: the final name is a record of whatever file holds
   it, and a record called x.bp in an ordinary directory file is not a program file (the kernel judges the file, not the record).
   A caller whose final component may itself be a directory - the target of OSCOPY, which can be a directory, OSPATH deleting or
   making one - passes TRUE.  CREATE.FILE and OPENTEMP pass FALSE: the name they make is the new file, and a new file called bp or
   x.dic is what CREATE.FILE makes without the gate; it is what they put INSIDE a guarded directory that is refused.  Every
   directory below the final component is classified either way.

   The private catalogue directory, and anything below it, is a program file as well (see edit_kind_of_path), whichever of its
   own names the final component has; the catalogue itself counts only when INCLUDE_LEAF.

   NOT COVERED, and said in the documentation: an account that holds OS.EXECUTE or SH reaches the files from the shell as it
   always could, so a path outside the account's own directory is not looked at for such an account.  For one that reaches another
   account's directory through SD.ACCOUNTS the whole resolved path is searched (the other account's own catalogue is not known to
   this process and is not recognised).  A path that cannot be resolved is refused.                                           */

int edit_os_path_refusal(const char *name, bool include_leaf) {
  char resolved[MAX_PATHNAME_LEN + 1];
  char relbuf[MAX_PATHNAME_LEN + 1];
  char folded[MAX_PATHNAME_LEN + 1];
  const char *rel;
  char comp[MAX_PATHNAME_LEN + 1];
  const char *p;
  const char *more;
  size_t n;
  int kind;
  int cat_pos;
  bool inside;

  if (MY_ADMIN())
    return EDIT_NONE;
  if ((name == NULL) || (name[0] == '\0'))
    return EDIT_NONE;
  /* 23 Oct 26 Windows port: Linux resolved with getcwd / realpath and "/" only.  Here the name is resolved as an open resolves it
     (fullpath) and folded into one namespace with the account root by path_view_for_edit() (op_dio2.c).  */
  if (!fullpath(resolved, (char *)name))
    return EDIT_VOC; /* cannot tell: refuse (a gate that fails open on a path it cannot read is decoration) */
  inside = path_view_for_edit(resolved, relbuf, sizeof(relbuf));
  if (relbuf[0] == '\0')
    return EDIT_VOC; /* cannot be folded, or still holds "..": refuse */

  if (inside) {
    rel = relbuf; /* inside the account's own directory: look below it */
  } else if (MY_PRIV(USR_OS_EXEC)) {
    return EDIT_NONE; /* OS.EXECUTE: the whole machine, and a shell; not covered */
  } else {
    rel = relbuf; /* another account's directory through SD.ACCOUNTS: the whole path */
  }

  /* 17 Oct 26 dm, S.64 part 2: the private catalogue is a program file, found by PLACE (resolved, as the loader reaches it) and not by its name */
  cat_pos = path_fold(resolved, folded) ? catalogue_position(folded) : 0;
  if (((cat_pos == 2) || ((cat_pos == 1) && include_leaf)) && !edit_permitted(EDIT_PROG))
    return EDIT_PROG;

  for (p = rel; *p != '\0';) {
    while (*p == '/')
      p++;
    n = 0;
    while ((p[n] != '\0') && (p[n] != '/'))
      n++;
    more = p + n;
    while (*more == '/')
      more++;
    if ((n > 0) && (n < sizeof(comp)) && (include_leaf || (*more != '\0'))) {
      memcpy(comp, p, n);
      comp[n] = '\0';
      kind = edit_kind_of_name(comp);
      if ((kind != EDIT_NONE) && !edit_permitted(kind))
        return kind;
    }
    p += n;
  }
  return EDIT_NONE;
}

/* edit_leaf_counts()  -  for a caller that DELETES, or COPIES INTO, an OS pathname whose final name may be a plain file or a directory
   (OSCOPY's target, OSPATH's delete): does that final name need classifying (include_leaf TRUE)?  Only if it is there and is not a plain
   file.  A plain file called x.bp or x.dic is a record of whatever directory holds it, not a program file or a dictionary; a name not
   made yet becomes a plain file when copied to, and there is nothing to delete.  A link, which could be to a directory, counts.      */

bool edit_leaf_counts(const char *name) {
  struct stat sb;
  char resolved[MAX_PATHNAME_LEN + 1];

  if ((name == NULL) || (name[0] == '\0') || !fullpath(resolved, (char *)name) || (lstat(resolved, &sb) != 0))
    return FALSE;
  return !S_ISREG(sb.st_mode);
}

/* ======================================================================
   sh()  -  Execute shell command                                         */

Private void sh(bool capture) {
  DESCRIPTOR *descr;
  STRING_CHUNK *str;
  int bytes;
  PRIV_WHY why; /* 03 Sep 26 - PRE_RELEASE_FIXES.md 96 */

  /* Before the stack is touched, so a refusal leaves it as it was found. */
  /* 03 Sep 26 Windows port - PRE_RELEASE_FIXES.md 96.  10054 names the user
     and says they are not permitted; when the check could not COMPLETE that
     sentence is a guess.  The refusal is unchanged - it must stay, and it must
     stay fail-closed - but the log now separates "os.users says no" from
     "os.users could not be read".                                          */
  if (!os_permitted(&why)) {
    if (why != PRIV_ANSWERED)
      priv_log_undetermined("OS.EXECUTE", why);
    k_error(sysmsg(10054), process.username);
  }

  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  bytes = (str != NULL) ? str->string_len : 0;
  if (bytes > MAX_SH_COMMAND_LENGTH) {
    process.status = ER_LENGTH;
    k_dismiss();
  } else {
    if (cmd_str != NULL)
      k_free(cmd_str); /* From an earlier k_error() */

    cmd_str = k_alloc(111, bytes + MAX_PATHNAME_LEN + 10); /* Allow for strcat on Windows */
    k_get_c_string(descr, cmd_str, bytes);
    k_dismiss();

    if (capture) {
      /* Set up capture mechanism */

      if (capturing) /* This is a nested EXECUTE...CAPTURING structure */
      {
        process.program.flags |= PF_CAPTURING;

        if (capture_head != NULL) /* Stack data already captured */
        {
          process.program.saved_capture_head = capture_head;
          process.program.saved_capture_tail = capture_tail;
        }
      }

      capture_head = NULL;
      capturing = TRUE;
      stack_display_pu();
    }

    sh_execute(cmd_str);
    k_free(cmd_str);
    cmd_str = NULL;

    if (capture) {
      op_capture(); /* Use op_capture() to save the command output */
    }
  }
}

/* ======================================================================
   sh_execute()  -  Execute SH command                                    */

/* ======================================================================
   sd_powershell_path()  -  Where Windows PowerShell is, as a POSIX path

   17 Sep 26 Windows port - lifted out of sh_execute() for linuxprt.c
   (RELEASE_1.1 54), unchanged in substance.

   The path is derived from SystemRoot rather than written as C:\Windows,
   because the system drive is not guaranteed.  It contains no spaces, which
   sh_execute() relies on: clparse() splits on them and does not honour
   quotes, which is why PowerShell is named by its real location rather than
   through a wrapper.  SystemRoot arrives as C:\WINDOWS; the separators are
   folded so the whole path is one spelling - sdrealpath() accepts either,
   but consistency keeps the value that gets logged and reported readable.  */

void sd_powershell_path(char *buf, int len) {
  const char *sysroot;
  char *pp;

  sysroot = getenv("SystemRoot");
  if ((sysroot == NULL) || (*sysroot == '\0'))
    sysroot = "C:/Windows";

  snprintf(buf, (size_t)len,
           "%s/System32/WindowsPowerShell/v1.0/powershell.exe", sysroot);

  for (pp = buf; *pp != '\0'; pp++) {
    if (*pp == '\\')
      *pp = '/';
  }
}

Private void sh_execute(char *command) {
#define PIPE_BUFFER_SIZE 2048
  char buffer[PIPE_BUFFER_SIZE];
  bool saved_trap_break_char;
  bool saved_pagination;
  bool use_output_pipe;
  /* Modified by Composer AI - 2026/06/10.
     Initialize pipe fd pairs so paths that skip pipe() do not read
     indeterminate values; use -1 for unused slots. */
  /* int ChildToSDPipe[2]; */
  int ChildToSDPipe[2] = {-1, -1};
  bool use_input_pipe;
  /* int SDToChildPipe[2]; */
  int SDToChildPipe[2] = {-1, -1};
  /* -------------------- */
  char *argv[10];
  int cpid;
  int16_t i;
  int bytes;
  int child_status;

  /* 14 Aug 26 Windows port - the shell is PowerShell, not bash.

     These were "/bin/bash -i" and "/bin/bash -c".  That is a Linux-ism twice
     over: bash is not on a Windows machine, and an installed SD does not ship
     one - gplbld/stage.py stages the SD executables and the MSYS2 DLLs, and no
     shell at all.  So /bin/bash resolved inside C:\Program Files\SD\ and every
     OS.EXECUTE failed on an installed system while working perfectly in a
     development tree, where MSYS2's own bash happens to exist.

     The path is derived from SystemRoot rather than written as C:\Windows,
     because the system drive is not guaranteed.  It must contain no spaces:
     clparse() splits on them and does not honour quotes, which is why
     PowerShell is named by its real location rather than through a wrapper.

     Note these are copies, not string literals - clparse() calls strtok() on
     whatever it is given and writes into it.                                */

  char dflt_sh[MAX_PATHNAME_LEN + 64];
  char dflt_sh1[MAX_PATHNAME_LEN + 96]; /* 05 Sep 26 - see the SH1 note below */
  char psh[MAX_PATHNAME_LEN + 1];

  /* 17 Sep 26 - the derivation moved to sd_powershell_path() below so that
     linuxprt.c's print spooler (RELEASE_1.1 54) finds PowerShell the same
     way; the comments that explained it moved with it. */
  sd_powershell_path(psh, sizeof(psh));

  snprintf(dflt_sh, sizeof(dflt_sh), "%s -NoProfile -NoLogo", psh);

  /* 05 Sep 26 Windows port - -ExecutionPolicy Bypass ON SH1 ONLY.
     PRE_RELEASE_FIXES 173, owner's ruling the day it was found.

     WITHOUT IT EVERY SHIPPED .ps1 SD RUNS IS REFUSED ON A STOCK WINDOWS
     CLIENT.  The client default policy is Restricted; SH1 is what os.execute
     uses, and gpl.bp/elevate builds "& '<app>/sd-elevate.ps1' ..." for it, so
     "logto sdsys" died with "running scripts is disabled on this system" on a
     machine that was not this one.  APNDPATH, EDIT, REMOTEAPI and REMOTESSH
     all reach shipped scripts the same way.

     THE SAME SWITCH FOR THE SAME REASON IS ALREADY IN sdsvc.c AND AT MORE
     THAN THIRTY SITES IN gplbld/sd.iss.  Only this path was missed, and no
     verify run could see it: this development machine's LocalMachine policy is
     RemoteSigned rather than the shipped default, and the whole suite runs
     there.

     SH - the interactive branch above - deliberately does NOT get it.  It
     opens a prompt for a person and runs no shipped script, so bypassing
     policy for it would widen a default SD does not need.

     The buffer grew with the string.  psh can be MAX_PATHNAME_LEN and the
     suffix is now 60 characters, which left three bytes of headroom at +64;
     snprintf truncates safely, but a truncated SH1 loses "-Command" and would
     be a silent and very confusing failure.  config.h's own history records
     this class of overrun costing a session already.                       */

  snprintf(dflt_sh1, sizeof(dflt_sh1),
           "%s -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command",
           psh);

  saved_trap_break_char = trap_break_char;
  saved_pagination = (tio.dsp.flags & PU_PAGINATE) != 0;

  process.status = 0;
  process.os_error = 0;

  flush_dh_cache();

  /* Turn off pagination.  Much as it would be nice, we get thoroughly
    confused about whether input is for the executed command or a response
    to the end of page prompt.                                             */

  tio.dsp.flags &= ~PU_PAGINATE;

  set_old_tty_modes();
  in_sh = TRUE; /* 0562 */

  /* If the user entered SD from the operating system command prompt, we
    can simply let the child process take over our stdout and stderr.
    If they have come in from a network or we need to capture the output
    for some reason, we must use a pipe. Although it sounds simpler always
    to use the pipe, this has some impact on the executed commands if they
    check the device type of the standard file handles.                     */

  use_output_pipe = capturing                          /* Trap output for EXECUTE CAPTURING */
                    || (connection_type != CN_CONSOLE) /* Not a direct connection */
                    || (tio.como_file >= 0);           /* Real como file */

  /* Similarly, on the input side, we need to use a pipe to feed the shell
    process if the real source of input is a socket. This allows us to
    perform input editing and avoids the shell moaning that stdin is not
    suitable.                                                             */

  use_input_pipe = (connection_type == CN_SOCKET);

  if (use_output_pipe && pipe(ChildToSDPipe)) {
    k_error("Cannot create child output pipe");
  }

  if (use_input_pipe && pipe(SDToChildPipe)) {
    /* Modified by Composer AI - 2026/06/10.
       Close the output pipe if input pipe creation fails. */
    if (use_output_pipe) {
      close(ChildToSDPipe[0]);
      close(ChildToSDPipe[1]);
    }
    /* -------------------- */
    k_error("Cannot create child input pipe");
  }

  /* 0420 Disable sigchld handler
    We need to do this to prevent the handler catching termination of
    the child process created below to execute this command.           */

  signal(SIGCHLD, SIG_DFL);

  cpid = fork();
  if (cpid == 0) /* Child process */
  {
    if (use_output_pipe) {
      dup2(ChildToSDPipe[1], 1);
      dup2(ChildToSDPipe[1], 2);
    }

    if (use_input_pipe) {
      dup2(SDToChildPipe[0], 0);
    }

    for (i = 3; i < 1024; i++)
      close(i);

    /* 15 Aug 26 Windows port - MARK THE SHELL AS SD's CHILD, so that a second
       sd cannot be started from inside it.  Owner's rule, 15 Aug 2026:
       somebody who shells out of SD with SH must not be able to run sd again.
       sd.c refuses when it sees this.

       IT IS A GUARD, NOT A BOUNDARY, and the difference matters.  The variable
       lives in the user's own shell, so the user can clear it.

       AND THE SHELL IS REALLY THERE - corrected 15 Aug 2026, having first
       claimed otherwise.  ForceCommand puts an ssh session into SD rather than
       a prompt, but SH hands one back, so "an SD account has no shell" is
       false and nothing here should rest on it.  What this guard buys is the
       accident and the casual case, which is what SH actually produces.  The
       owner's answer to the rest is at the application level: SD can lock a
       user into a menu system, and then SH is not reachable to begin with.
       Restricting SH itself would be the other way, and is not decided.

       Set in the CHILD, after the fork, so SD's own environment is untouched
       and the phantom and client paths - which fork elsewhere - never see it. */
    {
      static char sd_session_env[] = "SD_SESSION=1";
      putenv(sd_session_env);
    }

    if (command[0] == '\0') /* Interactive shell */
    {
      clparse((pcfg.sh[0] != '\0') ? pcfg.sh : dflt_sh, argv, 10);
    } else /* Single command */
    {
      /* 05 Sep 26 Windows port - 8, NOT 9.  PRE_RELEASE_FIXES 174.
         clparse returns AT MOST maxargs, and this branch then writes argv[i]
         and argv[i+1].  argv holds 10 pointers, so a maxargs of 9 could write
         argv[10] - one past the end - for any configured SH1 of nine or more
         space-separated tokens.  Two slots are reserved here, so the bound is
         8.  Not reachable from the default, which is six tokens since 173
         above; reachable from a config file, which is why it is a defect and
         not a tidy-up.  The interactive branch keeps 10: it appends nothing. */
      i = clparse((pcfg.sh1[0] != '\0') ? pcfg.sh1 : dflt_sh1, argv, 8);
      argv[i] = command;
      argv[i + 1] = NULL;
    }

    execv(argv[0], argv);

    /* 17 Sep 26 Windows port - RELEASE_1.1 55.  execv() RETURNS ONLY ON
       FAILURE, and until now the child simply FELL THROUGH into the parent's
       code below - a forked child running the parent's cleanup, closing the
       parent's pipes and reporting to the parent's caller.  Found while
       chasing something else; it is a defect in its own right.

       127 IS THE VALUE ON PURPOSE: it is the convention every caller of
       os.error() already reads as "could not run the command", and
       gpl.bp/is_grp_member's old three-way test was written against it.
       No log line from here - this is a forked Cygwin child about to exec and
       audit_message() takes ERRLOG_SEM and writes a file, so a child that
       deadlocked on it would hang the session.  The reason belongs to the
       caller, which still has errno's effect visible in the status.        */
    _exit(127);
  } else if (cpid == -1) /* Error */
  {
    /* Modified by Composer AI - 2026/06/10.
       fork() failed; close any pipes that were opened. */
    if (use_output_pipe) {
      close(ChildToSDPipe[0]);
      close(ChildToSDPipe[1]);
    }
    if (use_input_pipe) {
      close(SDToChildPipe[0]);
      close(SDToChildPipe[1]);
    }
    /* -------------------- */
    k_error("Failed to start");
  } else /* Parent process */
  {
    if (use_input_pipe) {
      ChildPipe = SDToChildPipe[1];
      close(SDToChildPipe[0]);
    }

    if (use_output_pipe) {
      close(ChildToSDPipe[1]);

      while ((bytes = read(ChildToSDPipe[0], buffer, PIPE_BUFFER_SIZE)) > 0) {
        tio_display_string(buffer, bytes, TRUE, FALSE);
      }

      close(ChildToSDPipe[0]);
    }

    waitpid(cpid, &child_status, 0);
    process.os_error = WEXITSTATUS(child_status); /* 0420 */

    /* 0420 Re-enable sigchld handler and clear any backlog */

    signal(SIGCHLD, sigchld_handler);
    while (waitpid(-1, &child_status, WNOHANG) > 0) {
    }

    if (use_input_pipe) {
      ChildPipe = -1;
      close(SDToChildPipe[1]);
    }
  }

  set_new_tty_modes();
  in_sh = FALSE; /* 0562 */

  if (saved_pagination)
    tio.dsp.flags |= PU_PAGINATE;
  else
    tio.dsp.flags &= ~PU_PAGINATE;
  set_term(saved_trap_break_char);
}

/* ======================================================================
   clparse()  -  Parse a command line into an argv array                  */

Private int clparse(char *p, char *argv[], int maxargs) {
  int argc; /* resolves CWE-197 */

  /* Although this works for our purposes, it isn't perfect. It really
    should handle quotes and \ escapes.                                */

  for (argc = 0; argc < maxargs; argc++) {
    if ((argv[argc] = strtok(p, " ")) == NULL)
      break;
    p = NULL;
  }

  return argc;
}

/* END-CODE */
