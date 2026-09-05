/* OP_KERNEL.C
 * Kernel opcodes.
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
 * 31 Dec 23 SD launch - prior history suppressed
 * 28 Jul 24 mab remove op_cnctport() / CONNECT.PORT not supported
 * 17 Aug 26 Windows port - K_SET_USERNAME added, gated on HDR_INTERNAL;
 *           op_login() fails closed now that login_user() is gone.
 * 29 Aug 26 Windows port - K_OS_ADMINISTRATOR added, with kernel.c's
 *           CN_SOCKET guard.  PRE_RELEASE_FIXES 56.
 * 05 Sep 26 Windows port - K_INTERACTIVE added.  How the session ARRIVED,
 *           where the two above ask who and what.  PRE_RELEASE_FIXES 167.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "revstamp.h"
#include "header.h"
#include "tio.h"
#include "debug.h"
#include "keys.h"
#include "syscom.h"
#include "config.h"
#include "options.h"
#include "dh_int.h"
#include "locks.h"
/* 23 Aug 26 Windows port - K_ASSUME_USER, PROJECT_STATUS.md 7 step 14. */
#include "win32s4u.h"

#include <sys/wait.h>
/* 16 Aug 26 Windows port - cygwin_conv_path(), for K_WINPATH.  sysseg.c
   includes this too, for CW_CYGWIN_PID_TO_WINPID.                        */
#include <sys/cygwin.h>

Public bool case_sensitive;

/* 03 Sep 26 Windows port - IsAdmin()'s ad-hoc declaration is gone; it and
   IsElevated() are in linuxlb.h now, which sd.h already includes.  They took a
   signature change for PRE_RELEASE_FIXES.md 96 and three private copies of a
   prototype are three places for one to be missed.                         */
bool recover_users(void);
void set_date(int32_t);

Private bool run_exe(char *exe_name, char *cmd_line);

/* ======================================================================
   op_kernel()  -  KERNEL()  -  Miscellaneous kernel functions            */

void op_kernel() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Qualifier                     |  Result                     |
     |--------------------------------|-----------------------------|
     |  Action key                    |                             |
     |================================|=============================|
     
   Keys:
     K$INTERNAL           Set or clear internal mode
     K$INTERNAL.QUERY     Query internal mode
     K$PAGINATE           Test or modify pagination flag
     K$FLAGS              Test/return program header flags
     K$DATE.FORMAT        European date format?
     K$CRTWIDE            Return display width
     K$CRTHIGH            Return display lines per page
     K$SET.DATE           Set current date
     K$IS.PHANTOM         Is this a phantom process
     K$TERM.TYPE          Terminal type name
     K$USERNAME           User name
     K$DATE.CONV          Set default date conversion
     K$PPID               Get parent process id
     K$USERS              Get user list
     K$INIPATH            Get ini file pathname
     K$FORCED.ACCOUNT     Force entry to named account unless set in $LOGINS
     K$SDNET              Get/set SDNet status flag
     K$CPROC.LEVEL        Get/set command processor level
     K$SUPPRESS.COMO      Supress/resume como file output
     K$ADMINISTRATOR      Get/set administrator rights
     K$SECURE             Secure system?
     K$GET.OPTIONS        Get options flags
     K$SET.OPTIONS        Set options flags
     K$PRIVATE.CATALOGUE  Set private catalogue pathname
     K$CLEANUP            Clean up defunct users
     K$COMMAND.OPTIONS    Get command line option flags
     K$CASE.SENSITIVE     REMOVE.TOKEN() cases sensitivity
     K$SET.LANGUAGE       Set language for message handler
     K$COLLATION          Set/clear sort collation data
     K$GET.SDNET.CONNECTIONS  Get details of open SDNet connections
     K$INVALIDATE.OBJECT  Invalidate object cache
     K$MESSAGE            Enable/disable message reception
     K$SET.EXIT.CAUSE     Set k_exit_cause
     K$COLLATION.NAME     Set primary collation map name
     K$AK.COLLATION       Select AK collation map
     K$EXIT.STATUS        Set exit status
     K$AUTOLOGOUT         Set/retrieve autologout period
     K$MAP.DIR.IDS        Enable/disable dir file id mapping
     K$AUDIT              Append a record to the audit trail
 */

  DESCRIPTOR *descr;
  int action;
  DESCRIPTOR result;
  int32_t n;
  char s[(MAX_PATHNAME_LEN * 2) + 1];
  int16_t i;
  int16_t j;
  char *p;
  int32_t *q;
  USER_ENTRY *uptr;
  STRING_CHUNK *str;

  InitDescr(&result, INTEGER);
  result.data.value = 0;

  descr = e_stack - 2;
  GetInt(descr);
  action = descr->data.value;

  descr = e_stack - 1;
  k_get_value(descr);

  switch (action) {
    case K_INTERNAL:
      GetInt(descr);
      if (descr->data.value < 0)
        result.data.value = internal_mode;
      else
        internal_mode = (descr->data.value != 0);

      break;

/* 20240219 mab always run in secure mode */
    case K_SECURE:
      GetInt(descr);
      if (descr->data.value < 0) {
//        if (is_nt)
          result.data.value = TRUE;
//        else
//          result.data.value = ((sysseg->flags & SSF_SECURE) != 0);
//      } else {
//        if (descr->data.value)
//          sysseg->flags |= SSF_SECURE;
//        else
//          sysseg->flags &= ~SSF_SECURE;
      }

      break;

    case K_LPTRHIGH: /* Same as SYSTEM(3) */
      if (process.program.flags & PF_PRINTER_ON)
        result.data.value = tio.lptr_0.lines_per_page;
      else
        result.data.value = tio.dsp.lines_per_page;

      break;

    case K_LPTRWIDE: /* Same as SYSTEM(2) */
      if (process.program.flags & PF_PRINTER_ON)
        result.data.value = tio.lptr_0.width;
      else
        result.data.value = tio.dsp.width;

      break;

    case K_PAGINATE:
      if ((n = descr->data.value) < 0) { /* Enquiry */
        result.data.value = (tio.dsp.flags & PU_PAGINATE) != 0;
      } else { /* Set pagination state */
        if (n) {
          tio.dsp.flags |= PU_PAGINATE;
          tio.dsp.line = 0;
        } else {
          tio.dsp.flags &= ~PU_PAGINATE;
        }
      }
      break;

    case K_FLAGS:
      GetInt(descr);
      n = descr->data.value;
      if (n)
        result.data.value = ((process.program.flags & n) != 0);
      else
        result.data.value = process.program.flags;
      break;

    case K_DATE_FORMAT:
      GetInt(descr);
      n = descr->data.value;
      if (n >= 0)
        european_dates = (n != 0);
      result.data.value = european_dates;
      break;

    case K_CRTHIGH:
      result.data.value = tio.dsp.lines_per_page;
      break;

    case K_CRTWIDE:
      result.data.value = tio.dsp.width;
      break;

    case K_SET_DATE:
      GetInt(descr);
      set_date(descr->data.value);
      break;

    case K_IS_PHANTOM:
      result.data.value = is_phantom;
      break;

    case K_TERM_TYPE:
      k_get_string(descr);
      if (descr->data.str.saddr != NULL) {
        k_get_c_string(descr, s, 32);
        settermtype(s);
      }
      k_put_c_string(tio.term_type, &result);
      break;

    case K_USERNAME:
      k_put_c_string(process.username, &result);
      break;

/* 17 Aug 26 Windows port - SET the session's user name.  APISRVR needs it:
   the API authenticates against $CRED in BASIC now (section 7 step 6a), and
   the identity that follows from it - process.username and my_uptr->username,
   which is what @logname, K$USERNAME and THE AUDIT TRAIL all read - lives
   here in C with no route from BASIC.  op_login() used to set it as a side
   effect of checking /etc/shadow, which does not exist on this platform.

   GATED ON HDR_INTERNAL, exactly as K_ADMINISTRATOR is, and for the same
   reason: section 7 step 4 stamps the audit trail from my_uptr in C so that
   the BASIC caller cannot claim to be somebody else.  An ungated setter would
   hand that back.  Ordinary BASIC cannot reach KERNEL at all - BCOMP rejects
   it - and APISRVR carries $internal (line 59).

   A separate key rather than making K_USERNAME settable: see keys.h.       */
    case K_SET_USERNAME:
      {
        char uname[MAX_USERNAME_LEN + 1];

        if ((k_get_c_string(descr, uname, MAX_USERNAME_LEN) > 0) &&
            (process.program.flags & HDR_INTERNAL)) {
          strcpy(process.username, uname);
          strcpy((char *)(my_uptr->username), uname);
        }
      }
      /* Report the name as it actually stands, so a refused caller is simply
         told what it still is rather than getting an error.                 */
      k_put_c_string(process.username, &result);
      break;

    /* 23 Aug 26 Windows port - PROJECT_STATUS.md 7 step 14, shape (b).
       Become the user this session has just authenticated as.

       IT ANSWERS 1 OR 0 AND NOTHING ELSE, and 0 must be treated as fatal by
       the caller: a session that carries on believing it is the user while
       holding LocalSystem's token is worse than one that never started.
       APISRVR refuses the login on 0.

       $internal ONLY, like K_SET_USERNAME above.  The gate is what stops an
       ordinary BASIC program asking to become somebody else - it would fail
       anyway for want of SeTcbPrivilege in an interactive session, but a
       refusal that depends on a privilege the process happens not to hold is
       not a control.

       NO WAY BACK IS OFFERED TO BASIC.  RevertUserIdentity() exists in
       win32s4u.c and is deliberately not reachable from here: the session
       becomes the user once, at the point SCRAM succeeds, and stays that way
       until it ends.  A verb that could drop back to LocalSystem would undo
       the whole of this step.                                               */
    case K_ASSUME_USER:
      {
        char uname[MAX_USERNAME_LEN + 1];

        result.data.value = 0;
        if ((k_get_c_string(descr, uname, MAX_USERNAME_LEN) > 0) &&
            (process.program.flags & HDR_INTERNAL)) {
          if (AssumeUserIdentity(uname))
            result.data.value = 1;
        }
      }
      break;

/* 24 Aug 26 Windows port - PROJECT_STATUS.md 7 step 14 (b).  TWO FIELDS, and
   the pair is the whole point: field 1 is the identity Windows says this
   thread is running as, field 2 is whether SD still holds an S4U token for it.
   Reading either alone is what made step 14 hard to see - the old
   ImpersonatingUser() returned only the belief and would have reported "still
   impersonating" at the moment the identity was gone.

   Field 1 empty with field 2 = 1 is the defect: SD thinks it is the user and
   the thread is not.                                                        */
    case K_IMPERSONATING:
      {
        char who[256];
        char both[300];

        if (!ImpersonatingUser(who, sizeof(who)))
          who[0] = '\0';
        snprintf(both, sizeof(both), "%s%c%d", who, FIELD_MARK,
                 HoldingUserToken());
        k_put_c_string(both, &result);
      }
      break;

    case K_DATE_CONV:
      if ((result.data.value = (k_get_c_string(descr, s, 32))) > 0) {
        strcpy(default_date_conversion, s);
      }
      k_put_c_string(default_date_conversion, &result);
      break;

    case K_PPID:
      result.data.value = my_uptr->puid;
      break;

    case K_USERS:
      InitDescr(&result, STRING);
      result.data.str.saddr = NULL;
      ts_init(&(result.data.str.saddr), 128);
      GetInt(descr);
      n = descr->data.value; /* User number or zero for all */
      for (i = 1; i <= sysseg->max_users; i++) {
        uptr = UPtr(i);
        if (((n == 0) && (uptr->uid > 0)) || ((n != 0) && (uptr->uid == n))) {
          if (result.data.str.saddr != NULL)
            ts_copy_byte(FIELD_MARK);

          ts_printf("%d%c%d%c%s%c%d%c%d%c%s%c%s%c%d", (int)(uptr->uid), VALUE_MARK, (int)(uptr->pid), VALUE_MARK, 
                    uptr->ip_addr, VALUE_MARK, (int)(uptr->flags), VALUE_MARK, uptr->puid, VALUE_MARK,
                    uptr->username, VALUE_MARK, uptr->ttyname, VALUE_MARK, uptr->login_time);
          if (n)
            break;
        }
      }
      ts_terminate();
      break;

    case K_INIPATH:
      k_put_c_string(config_path, &result);
      break;

    case K_FORCED_ACCOUNT:
      k_put_c_string(forced_account, &result);
      break;

    case K_SDNET:
      if (descr->data.value < 0)
        result.data.value = ((my_uptr->flags & USR_SDNET) != 0);
      else if (descr->data.value)
        my_uptr->flags |= USR_SDNET;
      else
        my_uptr->flags &= ~USR_SDNET;
      break;

    case K_CPROC_LEVEL:
      if (descr->data.value > 0)
        cproc_level = (int16_t)(descr->data.value);
      result.data.value = cproc_level;
      break;
      

    case K_SUPPRESS_COMO:
      if ((n = descr->data.value) < 0) { /* Enquiry */
        result.data.value = (tio.suppress_como);
      } else { /* Set suppression state */
        tio.suppress_como = (n != 0);
      }
      break;
/* 20240219 mab rebrand VBSRVR to APISRVR */
    case K_IS_SDAPISRVR:
      result.data.value = is_sdApiSrvr;
      break;

    case K_ADMINISTRATOR:
      GetInt(descr);
      n = descr->data.value;
      if (n >= 0) { /* Setting / clearing */
        /* 13 Aug 26 Windows port - this had a hole at each end.  Any positive
           argument granted the flag, so a BASIC program could make itself an
           administrator and every test of it was decorative; and the
           "|| IsAdmin()" meant an argument of zero re-granted rather than
           cleared whenever the caller was an OS administrator, so the flag
           could not be given up at all.

           Only a program compiled $internal may change it now - which is
           LOGIN and CPROC, the two that own entry to an account.  Ordinary
           BASIC cannot reach KERNEL at all (BCOMP rejects it), and would not
           carry HDR_INTERNAL if it could.  A refused attempt is not an error:
           the result below reports the flag as it actually stands, so a
           caller that tried to grant itself rights is simply told it has
           none.  See PROJECT_STATUS.md section 5.6.                        */

        if (process.program.flags & HDR_INTERNAL) {
          if (n > 0)
            my_uptr->flags |= USR_ADMIN;
          else
            my_uptr->flags &= ~USR_ADMIN;
        }
      }
      result.data.value = (my_uptr->flags & USR_ADMIN) != 0;
      break;

    /* 29 Aug 26 Windows port - PRE_RELEASE_FIXES 56, the owner's access model.
       Is the SIGNED-IN PERSON an administrator?  The case above is the session
       flag and this is the person; keys.h has the two side by side, and the
       names are close enough that reading them together is worth the minute.

       WHY IT EXISTS.  The model makes entering SDSYS the only source of
       administrator rights, and LOGIN the place it happens - so "may this
       person be in SDSYS" carries far more weight than it did when SDSYS was
       somewhere you stepped into.  Measured 29 Aug 26: nothing asked that
       question anywhere.  elevate('START') gates on Start-Process -Verb RunAs
       succeeding (gplbld/sd-elevate.ps1:120), which gives an administrator a
       CONSENT prompt and a standard user a CREDENTIAL prompt - so a
       non-administrator holding an administrator's password reached SDSYS,
       and the trail then named the person who did NOT consent, because
       @logname and audit_message() still read the signed-in user.

       IsAdmin() ASKS getgrouplist(), WHICH IS THE RIGHT HALF OF THE PAIR.
       linuxlb.c has both: getgrouplist() is "is this ACCOUNT an
       administrator", getgroups() is "is this PROCESS elevated".  This gate
       wants the first - an administrator who has not elevated is still an
       administrator, and elevation is what the UAC prompt is for.

       THE CN_SOCKET GUARD IS NOT OPTIONAL AND IS THE WHOLE REASON THIS IS NOT
       A ONE-LINE CASE.  IsAdmin() reads getpwuid(getuid()) - the REAL uid.  An
       API session is fork()ed by the LocalSystem service and AssumeUserIdentity()
       (win32s4u.c) changes only the EFFECTIVE uid, so getuid() stays SYSTEM,
       whose token carries BUILTIN\Administrators, and IsAdmin() would answer
       TRUE for every remote client.  That is the identical shape of the hole
       kernel.c:240 closed on 21 Aug 26, where IsElevated() was true for every
       API session for exactly the same reason; this copies its guard rather
       than inventing a second discriminator that could drift away from it. */

    /* 03 Sep 26 Windows port - PRE_RELEASE_FIXES.md 96.  THIS ONE FEEDS A
       SENTENCE THAT IS WRITTEN DOWN AS FACT.  K$OS.ADMINISTRATOR reaches
       CPROC:2697, which prints 10002 and then writes CPROC:2699
       "LOGTO REFUSED account=SDSYS reason=not an administrator" into the audit
       trail an investigation reads - a reason nobody established, when the
       tier register may say otherwise.  The answer returned is unchanged and
       still fails closed; what is new is that the log now says which of the
       two happened.                                                        */

    case K_OS_ADMINISTRATOR: {
      PRIV_WHY why;
      bool is_admin = IsAdmin(&why);

      if (why != PRIV_ANSWERED)
        priv_log_undetermined("K$OS.ADMINISTRATOR", why);

      result.data.value =
          (is_admin && (connection_type != CN_SOCKET)) ? TRUE : FALSE;
    } break;

    /* 05 Sep 26 Windows port - PRE_RELEASE_FIXES.md 167.  HOW DID THIS SESSION
       ARRIVE?  keys.h has the three-way table this completes.

       WHY IT EXISTS.  Owner's ruling, 5 Sep 2026: remote ssh and API access is
       TOTALLY DENIED to administrators - administration happens at the console
       or through a remote-control product or single-user remote desktop.  That
       is a refusal of the SESSION, not a narrowing of its rights, so LOGIN
       needs to ask the question before it chooses an account.  Nothing in the
       BASIC layer could ask it before this key.

       BOTH TERMS, BECAUSE THE RULING NAMES BOTH ROUTES.  IsInteractive() reads
       S-1-5-4 from the token and answers for ssh, RDP, the console and an
       unattended scheduled task.  It cannot answer for the API: an API session
       is fork()ed by the LocalSystem service and AssumeUserIdentity() changes
       only the EFFECTIVE uid, so the token walked here is the service's, not
       the caller's - the identical trap K_OS_ADMINISTRATOR's CN_SOCKET guard
       above exists for.  CN_SOCKET is the reliable discriminator there, and
       using the SAME one keeps the two keys from drifting apart.

       FAIL-CLOSED, AND THE UNDETERMINED CASE IS A REFUSAL.  IsInteractive()
       returns FALSE when it could not read the token at all; that answers
       "no desktop", which costs a local administrator a login they can retry
       and costs a remote one nothing they were entitled to.  The log line says
       which, so the refusal does not state a reason nobody established -
       PRE_RELEASE 96's rule.                                                */

    case K_INTERACTIVE: {
      PRIV_WHY why;
      bool has_desktop = IsInteractive(&why);

      if (why != PRIV_ANSWERED)
        priv_log_undetermined("K$INTERACTIVE", why);

      result.data.value =
          (has_desktop && (connection_type != CN_SOCKET)) ? TRUE : FALSE;
    } break;

    case K_FILESTATS:
      GetInt(descr);
      if (descr->data.value) { /* Reset counters */
        memset((char *)&(sysseg->global_stats), 0, sizeof(struct FILESTATS));
        sysseg->global_stats.reset = sdtime();
      } else {
        InitDescr(&result, STRING);
        result.data.str.saddr = NULL;
        ts_init(&(result.data.str.saddr), 5 * FILESTATS_COUNTERS);
        for (i = 0, q = (int32_t *)&(sysseg->global_stats.reset); i < FILESTATS_COUNTERS; i++, q++) {
          ts_printf("%d\xfe", *q);
        }
        (void)ts_terminate();
      }
      break;

    case K_TTY:
      k_put_c_string((char *)(my_uptr->ttyname), &result);
      break;

    case K_GET_OPTIONS:
      for (i = 0; i < NumOptions; i++)
        s[i] = option_flags[i] + '0';

      s[NumOptions] = '\0';
      k_put_c_string(s, &result);
      break;

    case K_SET_OPTIONS:
      j = k_get_c_string(descr, s, 200);
      for (i = 0; (i < j) && (i < NumOptions); i++)
        SetOption(i, s[i] == '1');

      break;

    case K_PRIVATE_CATALOGUE:
      j = k_get_c_string(descr, private_catalogue, MAX_PATHNAME_LEN);
      break;

    case K_CLEANUP:
      result.data.value = recover_users();
      break;

    case K_OBJKEY:
      result.data.value = object_key;
      break;

    case K_COMMAND_OPTIONS:
      result.data.value = command_options;
      break;

    case K_CASE_SENSITIVE:
      GetInt(descr);
      if (descr->data.value < 0)
        result.data.value = case_sensitive;
      else
        case_sensitive = (descr->data.value != 0);
      break;

    case K_SET_LANGUAGE:
      k_get_c_string(descr, s, 3);
      result.data.value = load_language(s);
      break;

    case K_HSM:
      GetInt(descr);
      switch (descr->data.value) {
        case 0: /* Disable */
          hsm = FALSE;
          break;
        case 1: /* Enable */
          hsm_on();
          break;
        case 2: /* Return data */
          InitDescr(&result, STRING);
          result.data.str.saddr = hsm_dump();
          break;
      }
      break;

    case K_COLLATION:
      k_get_string(descr);
      if (descr->data.str.saddr == NULL) {
        primary_collation = NULL;
        collation = NULL;
      } else {
        str = s_make_contiguous(descr->data.str.saddr, NULL);
        descr->data.str.saddr = str;
        memcpy(primary_collation_map, str->data, 256);
        primary_collation = primary_collation_map;
        collation = primary_collation_map;
      }
      break;

/* 18 Aug 26 Windows port - SDNET IS GONE and this returns an empty list.  The
   key is KEPT rather than deleted so that the numbering in INT$KEYS.H does not
   move and so a caller gets an empty answer instead of falling into the default
   case.  Nothing in GPL.BP calls it now: LISTSRVR went with the feature.
   PROJECT_STATUS.md section 8.                                              */
    case K_GET_SDNET_CONNECTIONS:
      InitDescr(&result, STRING);
      result.data.str.saddr = NULL;
      break;

    case K_INVALIDATE_OBJECT:
      invalidate_object();
      break;

    case K_MESSAGE:
      GetInt(descr);
      n = descr->data.value;
      if (n == 0)
        my_uptr->flags |= USR_MSG_OFF;
      else if (n > 0)
        my_uptr->flags &= ~USR_MSG_OFF;
      result.data.value = (my_uptr->flags & USR_MSG_OFF) == 0;
      break;

    case K_SET_EXIT_CAUSE:
      GetInt(descr);
      k_exit_cause = descr->data.value;
      break;

    case K_COLLATION_NAME:
      setsdstring(&collation_map_name, descr);
      break;

    case K_AK_COLLATION:
      if (descr->type == STRING) {
        str = descr->data.str.saddr;
        collation = (str == NULL) ? NULL : str->data;
      } else
        collation = primary_collation;
      break;

    case K_EXIT_STATUS:
      GetInt(descr);
      exit_status = descr->data.value;
      break;

    case K_CASE_MAP:
      GetString(descr);
      if ((str = descr->data.str.saddr) == NULL)
        set_default_character_maps();
      else {
        uc_chars[(u_char)(str->data[1])] = str->data[0];
        lc_chars[(u_char)(str->data[0])] = str->data[1];
        char_types[(u_char)(str->data[0])] |= CT_ALPHA | CT_GRAPH;
        char_types[(u_char)(str->data[1])] |= CT_ALPHA | CT_GRAPH;
      }
      break;

    case K_AUTOLOGOUT:
      GetInt(descr);
      if (descr->data.value >= 0)
        autologout = descr->data.value;
      result.data.value = autologout;
      break;

    case K_MAP_DIR_IDS:
      GetInt(descr);
      if (descr->data.value >= 0)
        map_dir_ids = (descr->data.value != 0);
      result.data.value = map_dir_ids;
      break;

    case K_IN_GROUP:
      k_get_c_string(descr, s, 64);
      result.data.value = in_group(s);
      break;

    case K_BREAK_HANDLER:
      k_get_c_string(descr, s, 64);
      setstring(&process.program.break_handler, s);
      break;

    case K_RUNEXE:
      k_get_c_string(descr, s, sizeof(s) - 1);
      p = strchr(s, ' ');
      if (p != NULL) {
        *(p++) = '\0';
      }
      result.data.value = run_exe(s, p);
      break;

    /* 16 Aug 26 Windows port - PROJECT_STATUS.md 7 step 4.  The caller passes
       what happened and NOT who did it: audit_message() stamps the identity
       from my_uptr, which no BASIC program can reach.  Returns 0 always -
       there is no failure a caller could sensibly act on, and the login path
       must not be stopped by an unwritable audit file.                     */

    case K_AUDIT:
      k_get_c_string(descr, s, sizeof(s) - 1);
      audit_message(s);
      break;

    /* 16 Aug 26 Windows port - the POSIX name of a file as Windows spells it.
       BASIC has had no way to make one: OS$FULLPATH returns a POSIX path
       whatever its comment claims, and !ps_script works around the lack by
       naming its file relative to a working directory both sides share
       (PROJECT_STATUS.md 5.8).  That trick does not stretch to handing a
       pathname to Start-Process, which is a Windows program and cannot open
       /usr/bin/....  Answers an empty string rather than a guess if the
       runtime cannot convert - a wrong pathname here launches the wrong
       thing, and exepath.c makes the same choice for the same reason.     */

    case K_WINPATH:
      k_get_c_string(descr, s, sizeof(s) - 1);
      {
        char win[MAX_PATHNAME_LEN + 1];

        if (cygwin_conv_path(CCP_POSIX_TO_WIN_A, s, win, sizeof(win)) == 0)
          k_put_c_string(win, &result);
        else
          k_put_c_string("", &result);
      }
      break;

    /* 16 Aug 26 Windows port - this session's pid AS WINDOWS COUNTS IT.
       getpid() answers with the MSYS2 runtime's own number, which is not what
       Get-Process or Task Manager use - the daemon that called itself pid 87
       was 14712 to Windows (sysseg.c, win_pid()).  The elevated helper watches
       its owning session with Get-Process, so it needs the Windows number;
       given the runtime's, it would decide the session had gone at once, or
       worse, watch an unrelated process that happened to hold it.
       Answers 0 if the runtime cannot translate.                          */

    case K_WINPID:
      result.data.value =
          (int32_t)cygwin_internal(CW_CYGWIN_PID_TO_WINPID, getpid());
      break;

    default:
      k_error("Illegal KERNEL() action key (%d)", action);
  }

  k_dismiss();
  *(e_stack - 1) = result;
}

/* ======================================================================
   op_lgnport()  -  Login a serial port process                           */

void op_lgnport() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top | Account name                   |  Successful? (true/false)   |
     |--------------------------------|-----------------------------|
     | Port name{:params}             |                             |
     |================================|=============================|
 */

  bool status = FALSE;

  process.status = ER_UNSUPPORTED;

  k_dismiss();
  k_dismiss();

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;
}

/* ======================================================================
   op_option()  -  OPTION() function                                      */

void op_option() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Option number                 |  Option state               |
     |================================|=============================|
 */

  DESCRIPTOR *descr;
  int opt;

  descr = e_stack - 1;
  GetInt(descr);
  opt = descr->data.value;
  if ((opt >= 0) && (opt < NumOptions))
    descr->data.value = Option(opt);
  else
    descr->data.value = 0;
}

/* ======================================================================
   op_phantom()  -  PHANTOM  -  Start new process                         */

void op_phantom() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |                                |  SD user id, zero if fails  |
     |================================|=============================|
 */

  int16_t i;
  USER_ENTRY *uptr;
  int16_t phantom_user_index;
  int16_t phantom_uid = 0;
  char path[MAX_PATHNAME_LEN + 1];
  char option[15 + 1];
  int cpid;

  /* Reserve a user table entry for the phantom process */

  StartExclusive(SHORT_CODE, 38);
  phantom_user_index = 0;
  for (i = 1; i <= sysseg->max_users; i++) {
    uptr = UPtr(i);
    if (uptr->uid == 0) /* Spare cell */
    {
      phantom_uid = assign_user_no(i);
      uptr->uid = phantom_uid;
      uptr->puid = process.user_no;
      strcpy((char *)(uptr->username), (char *)(my_uptr->username));
      phantom_user_index = i;
      break;
    }
  }
  EndExclusive(SHORT_CODE);

  if (phantom_user_index == 0)
    goto exit_op_phantom;

  /* Construct command for CreateProcess */

  cpid = fork();
  if (cpid == 0) { /* Child process */
    //0387   close(0);
    //0387   close(1);
    //0387   close(2);
    for (i = 3; i < 1024; i++)
      close(i); /* 0401 */

    daemon(1, 1);
    /* converted to snprintf() -gwb 22Feb20 */
    if (snprintf(path, MAX_PATHNAME_LEN + 1, "%s/bin/sd", sysseg->sysdir) >= (MAX_PATHNAME_LEN + 1)) {
      /* TODO: this should also be logged with more detail */
      k_error("Overflowed path/filename length in op_phantom()!");
      goto exit_op_phantom;
    }
    sprintf(option, "-p%d", phantom_user_index);
    execl(path, path, option, NULL);
  } else if (cpid == -1) { /* Error */
    *(UMap(uptr->uid)) = 0;
    uptr->uid = 0; /* Release reserved user cell */
    uptr->puid = 0;
    phantom_uid = 0;
  } else { /* Parent process */
    waitpid(cpid, NULL, WNOHANG);
  }

exit_op_phantom:
  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = phantom_uid;
}

/* ======================================================================
   op_chgphant()  -  Make process a "chargeable" phantom                  */

void op_chgphant() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |                                |  1 = ok, 0 = error          |
     |================================|=============================|
 */

  bool status = TRUE;

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;
}


/* ======================================================================
   op_login()  -  LOGIN()  -  Perform login for socket based process      */

void op_login() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Password                      |  1 = ok, 0 = error          |
     |--------------------------------|-----------------------------|
     |  User name                     |                             |
     |================================|=============================|
 */

  bool ok;
  DESCRIPTOR *descr;
  char username[32 + 1];
  char password[32 + 1];

  /* Get password */

  descr = e_stack - 1;
  (void)k_get_c_string(descr, password, 32);
  k_dismiss();

  /* Get username */

  descr = e_stack - 1;
  (void)k_get_c_string(descr, username, 32);
  k_dismiss();

  InitDescr(e_stack, INTEGER);

/* 17 Aug 26 Windows port - FAILS CLOSED, and the opcode is kept only because
   opcodes.h is positional (section 6: retire in place, never delete a line -
   and BCOMP's int.intrinsics and its "on i goto" list are matched to it by
   position, so removing the intrinsic is a two-sided edit for no gain).

   login_user() is gone.  It read /etc/shadow, which MSYS2 does not have, so
   with APILOGIN=1 - what sd.conf ships - every API login was already refused;
   its other path trusted getpeereid() on an AF_UNIX socket that MSYS2 emulates
   over TCP loopback, and then called setgid()/setuid(), which mean nothing
   here and which section 7 step 6d says to drop anyway.  The API authenticates
   against $CRED in APISRVR now and sets its identity with K$SET.USERNAME.

   Anything still calling login() is therefore using a route that was broken
   and is now absent, so FALSE is the honest answer rather than a silent one. */
  ok = FALSE;
/* 20240219 mab move to only allow AF_UNIX socket types                                                           */
/*   As part of this mod:                                                                                         */
/*     if config APILOGIN = 0 (ignor)                                                                             */
/*       we pull username, user id and group id from peer in start_connection                                     */
/*       If these are populated, we ignore the passed user name (either came in as a local user using the API     */
/*       or as a remote user using ssh and the API) Either way we have already gone through username and password */
/*       verification                                                                                             */
/*     if config APILOGIN = 1 (require)                                                                           */
/*       require valid username and password from api connection                                                  */
 
  if (ok) {
    if (pcfg.api_login){
      strcpy((char *)(my_uptr->username), username);
      strcpy(process.username, username);
    }else{
      /* APILOGIN = 0 process.username was assigned in login.user */
      strcpy((char *)(my_uptr->username), process.username);
    }
  }
  (e_stack++)->data.value = ok;
}

/* ======================================================================
   op_logout()  -  LOGOUT()  -  Logout phantom process                    */

void op_logout() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Immediate flag                |  1 = ok, 2 = reaped,        |
     |                                |  0 = error                  |
     |--------------------------------|-----------------------------|
     |  User number                   |                             |
     |================================|=============================|

 04 Sep 26 Windows port - PRE_RELEASE_FIXES.md 16.  ***2 IS NEW AND IT IS A
 DIFFERENT OUTCOME, NOT A WARMER 1.***  Raising EVT_TERMINATE at a process
 that no longer exists sets USR_LOGOUT and nothing ever clears it, so LISTU
 reads "(logout pending)" for ever and the file the dead session held stays
 locked.  When the process is gone the slot is REAPED instead, and the caller
 has to be able to tell the two apart because they need different words on
 screen: "asked it to go" against "it was already gone and has been cleared".
 Reporting a reap as a logout would be this file's own instrument rule broken.

 ***2 IS TRUTHY, WHICH IS WHY IT IS SAFE.***  Every existing caller writes
 "if not(logout(...))" or takes the value as a flag, and 2 reads as true
 there exactly as 1 does.  A new number was chosen over a second return
 argument for that reason.
 */

  DESCRIPTOR *descr;
  int user;
  int status = 0;
  bool immediate;

  /* Get immediate flag */

  descr = e_stack - 1;
  GetBool(descr);
  immediate = (descr->data.value != 0);
  k_pop(1);

  /* Get user number */

  descr = e_stack - 1;
  GetInt(descr);
  user = descr->data.value;

  if (user == 0) {
    k_exit_cause = (immediate) ? K_LOGOUT : K_TERMINATE;
    status = 1;
  } else if (reap_lost_user((int16_t)user)) {
    /* THE PROCESS WAS ALREADY GONE.  PRE_RELEASE_FIXES.md 16.  Its slot, and
       every file, record, group and task lock it still held, have been
       released.  Tried BEFORE raise_event() deliberately: raising an event at
       a process that cannot receive it is what sets USR_LOGOUT and leaves
       "(logout pending)" standing for ever, so asking the question in the
       other order would still leave the flag behind on the way past. */
    status = 2;
  } else {
    log_printf(sysmsg(1027), user); /* Force logout initiated for user %d */
    status = raise_event((immediate) ? EVT_LOGOUT : EVT_TERMINATE, user);
  }

  descr->data.value = status;
  return;
}

/* ======================================================================
   op_events()  -  EVENTS()                                               */

void op_events() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |  Event flag values, 0 = query  | Event flag values           |
     |  -ve = unset event             |                             |
     |--------------------------------|-----------------------------|
     |  User number (-ve = all)       |                             |
     |================================|=============================|

 Negative user number is not meaningful for query.
 STATUS() = 0 if user found, non-zero if user not found
 */

  DESCRIPTOR *descr;
  int32_t flags;
  int user;
  USER_ENTRY *uptr;
  int16_t i;

  /* Get flag values */

  descr = e_stack - 1;
  GetInt(descr);
  flags = descr->data.value;

  /* Get user number */

  descr = e_stack - 2;
  GetInt(descr);
  user = descr->data.value;
  k_pop(1);

  process.status = 1;

  StartExclusive(SHORT_CODE, 46);
  for (i = 1; i <= sysseg->max_users; i++) {
    uptr = UPtr(i);
    if ((uptr->uid == user) || (user < 0)) {
      if (flags > 0)
        uptr->events |= flags;
      else if (flags < 0)
        uptr->events &= ~-flags;
      descr->data.value = uptr->events;
      process.status = 0;
      if (user > 0)
        break;
    }
  }
  EndExclusive(SHORT_CODE);
}

/* ======================================================================
   op_setflags()  -  SETFLAGS opcode  - Set opcode_flags                  */

void op_setflags() {
  register u_int16_t flags;

  flags = *(pc++);
  flags |= *(pc++) << 8;

  process.op_flags |= flags;
}

/* ======================================================================
   op_userno()  -  USERNO  -  Get user number                             */

void op_userno() {
  /* Stack:

     |================================|=============================|
     |            BEFORE              |           AFTER             |
     |================================|=============================|
 top |                                |  User no                    |
     |================================|=============================|
 */

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = process.user_no;
}

/* ======================================================================
   run_exe()  -  Run executable from SD session                           */

Private bool run_exe(char *exe_name, char *cmd_line) {
  //* NIX implementation to follow
  process.status = ER_FAILED;
  return FALSE;
}

/* END-CODE */
