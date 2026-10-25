/* NETFILES.C
 * Files on another SD server (SDNet, S.65 stage 1): the kernel side of the NET_FILE file variable type
 * Copyright (c) 2026 SD Core for Linux
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
 * 17 Oct 26 dm  S.65 slice 3c: written.  The first netfiles.c (plan G4 removed it, 1,227 lines, ports and passwords of its own) is not this
 *               one: this holds NO socket code.  Every operation goes to the catalogued BASIC handler $netfile (sdsys/gpl.bp/netfile, slice
 *               3b), which holds the connections in named COMMON and speaks the API through the class !sdclient.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 *  net_path_is_net    Is a path from get_voc_file_reference() the encoded form of a file on another server?
 *  net_open           OPEN of such a file: the NET gate, then the handler (NF$OPEN)
 *  net_close          The file variable goes: CLOSE tells the server, any other release queues the handle
 *  net_read           READ, MATREAD
 *  net_readv          READV (and the record-exists test, field 0)
 *  net_fileinfo       FILEINFO() keys the file variable does not answer itself
 *  net_select         SELECT, SELECTV: every record id of the remote file in one string (slice 3d)
 *  net_refuse        Any other statement given the file variable: message 12506
 *  net_close_all      LOGTO: every connection and every handle of the process
 *  net_message        The text of the last error
 *
 * THE ENCODED PATH.  gpl.bp/_voc_ref answers an N pointer (VOC field 1 N, field 2 the server name, field 3 the file name on the server) with
 * the "pathname" char(1) 'N' char(1) server char(1) file.  A real path never holds char(1), so every other consumer of
 * get_voc_file_reference() (CALL "file", OPENSEQ, DELETESEQ ...) finds no such path and refuses.  Only open_file() with map_name TRUE (OPEN
 * by name) looks for it; OPENPATH and OPENTEMP do not.
 *
 * HOW THE HANDLER IS RUN.  As call_trigger() runs a trigger: the six arguments (operation, a, b, c, then ADDRs to two local descriptors for
 * out and rc) go on the e-stack, k_call("$netfile") finds the program in the global catalogue by name (so the $internal flag it carries is
 * trusted), PF_IS_TRIGGER makes its RETURN leave k_run_program(), and the answer is read from the two descriptors.  rc is a dynamic array:
 * <1> 0 done, 2 the ELSE branch, 3 an error; <2> the message number and <3> to <5> its arguments (message text with %1 to %4: sysmsg() in
 * BASIC, net_set_message() here); <6> the remote STATUS().  netfile.h in sdsys/gpl.bp is the other half of this contract: a number there
 * is the same number here (NF_x below).
 *
 * THE HANDLER IS BASIC AND MAY RUN ONLY WHERE BASIC MAY.  k_release() reaches dio_close() from unwinding, from kill_process() after the
 * e-stack has been freed and from scope exit; a nested k_run_program() there would clear an exit already under way.  So net_close() runs
 * the handler only for a CLOSE statement (explicit_close, set by op_close()) and otherwise puts the handle on a queue that the next
 * handler call sends first (net_flush_pending()), so that a program that opens files in a loop and lets them go does not run out of the
 * 100 handles a process may hold.
 *
 * WHAT A HANDLER CALL DOES TO THE CALLER.  k_call() may allocate a new e-stack and free the old one: no DESCRIPTOR* into the e-stack may be
 * used after a call (the callers find their operands again by e_stack).  process.status, process.os_error and process.op_flags are changed
 * by the BASIC that runs; every function here sets process.status itself afterwards and gives process.op_flags back as it was.
 *
 * ERRORS.  The statement's ON ERROR is process.op_flags & P_ON_ERROR AT ENTRY of net_read, net_readv, net_fileinfo and net_refuse (the
 * callers set it for the call, op_dio3.c).  Those four raise the error themselves with the handler's message unless it is set; with it
 * set they return the negative status and the message stays in net_message().  net_open() never raises (open_file() does, with
 * net_message()).  Statuses: ER_PERM (3035) for a refusal of the gate, the accounts list or the credential, ER_NETWORK (7000) for every
 * other error and for a refused statement; the ELSE branch is the remote STATUS() when the server sent one (3000, 3003, 3006), else
 * ER_RNF for a record and ER_FNF for a file.
 *
 * THE GATE.  net_open() asks, before the handler is loaded, whether the session is the administrator or holds the NET gate (K_NET); an
 * $internal program is NOT exempt (the S.63 lesson).  The handler asks again and repeats the rest (definition, accounts list, stored
 * credential and pin, limits): it is the one that can say why.
 *
 * LOGTO.  The handles belong to the account that opened them.  net_close_all() starts a new epoch (a file variable from an earlier epoch
 * is stale: it is never sent and never closed on the server, so that its handle number cannot close somebody else's file) and, if this
 * process ever opened a remote file, sends NF$CLOSEALL.  LOGTO is BASIC (cproc): it reaches this through a kernel key (see the report of
 * slice 3c); nothing here hooks the end of a process, because the OS closes the socket and the named COMMON goes with the process.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "header.h"

/* The operation codes and results of the handler: sdsys/gpl.bp/netfile.h (keep the two in step) */
#define NF_OPEN 1
#define NF_CLOSE 2
#define NF_READ 3
#define NF_READV 4
#define NF_SELECT 6
#define NF_FILEINFO 7
#define NF_CLOSEALL 8

#define NF_RC_OK 0
#define NF_RC_ELSE 2
#define NF_RC_ERROR 3

/* Messages 12465 and 12506 are the handler's own (gate, read only); 12499 is its "no remote file is open with handle %1".  12512 and
   12513 are the kernel's. */
#define MSG_NO_GATE 12465
#define MSG_NOT_LISTED 12466
#define MSG_NO_CREDENTIAL 12501
#define MSG_BAD_HANDLE 12499
#define MSG_READ_ONLY 12506
#define MSG_HANDLER 12512
#define MSG_BAD_POINTER 12513

#define NET_ARG_MAX 120     /* Longest message argument kept (the handler cuts them at 100) */
#define NET_RC_BUF 1024     /* Room for rc: six fields, three of them message arguments */
#define NET_FILE_MAX 63     /* Longest remote file name (the shape _voc_ref, set.server and the handler agree on) */
#define NET_FILE_NAME_MAX (NET_FILE_MAX + 5) /* The name in the pointer's path: the file name, or "dict " and the file name (slice 3d) */

typedef struct {
  int result;                      /* NF_RC_x */
  int msg;                         /* rc<2> */
  char arg[3][NET_ARG_MAX + 1];    /* rc<3> to rc<5> */
  int status;                      /* rc<6> */
} NET_RC;

Private char net_msg[512] = "";
Private u_int16_t net_epoch = 0;            /* Moved on by net_close_all(); a NET_FILE of another epoch is stale */
Private bool net_used = FALSE;              /* This process has had a remote file open (so the handler holds something to close) */
Private int16_t net_pending[NET_MAX_HANDLES]; /* Handles whose file variable went where BASIC could not be run: sent at the next call */
Private int net_pending_ct = 0;

/* ======================================================================
   net_message()  -  The text of the last error of this module            */

const char* net_message() {
  return net_msg;
}

/* ======================================================================
   net_path_is_net()  -  Is this the encoded path of a file on another server?  */

bool net_path_is_net(const char* path) {
  return (path != NULL) && ((u_char)path[0] == 1);
}

/* ======================================================================
   net_set_message()  -  net_msg = message msg_no with %1 to %3 replaced.
   The message numbers 12457 to 12511 are written for BASIC (%1 to %4, in any order); this does the same substitution for C.  The text
   is cut to the size of net_msg and anything a terminal would act on is made a question mark.                                        */

Private char net_printable(char c) {
  return (((u_char)c < 32) || ((u_char)c > 126)) ? '?' : c;
}

Private void net_set_message(int msg_no, const char* a1, const char* a2, const char* a3) {
  char tmpl[sizeof(net_msg)];
  const char* arg[3];
  const char* p;
  const char* s;
  char* q = net_msg;
  char* end = net_msg + sizeof(net_msg) - 1;

  arg[0] = (a1 != NULL) ? a1 : "";
  arg[1] = (a2 != NULL) ? a2 : "";
  arg[2] = (a3 != NULL) ? a3 : "";

  snprintf(tmpl, sizeof(tmpl), "%s", sysmsg(msg_no)); /* sysmsg() has one buffer: copy it before anything else asks */

  for (p = tmpl; (*p != '\0') && (q < end); p++) {
    if ((p[0] == '%') && (p[1] >= '1') && (p[1] <= '3')) {
      for (s = arg[p[1] - '1']; (*s != '\0') && (q < end); s++)
        *(q++) = net_printable(*s);
      p++;
    } else {
      *(q++) = net_printable(*p);
    }
  }
  *q = '\0';
}

/* ======================================================================
   net_raise()  -  Give the statement its error.  entry is process.op_flags as the caller set it.  Without ON ERROR the error is raised
   here and does not return.                                                                                                         */

Private int net_raise(int status, u_int16_t entry) {
  process.status = status;
  if (!(entry & P_ON_ERROR)) {
    process.op_flags = 0;
    k_error("%s", net_msg);
  }
  return status;
}

/* ======================================================================
   net_gate_ok()  -  May this session open a file on another server?  The administrator, or an account holding the NET gate (K_NET).  */

Private bool net_gate_ok() {
  return ((my_uptr->flags & USR_ADMIN) != 0) || ((my_uptr->gates & UG_NET) != 0);
}

/* ======================================================================
   net_push_string()  -  A string argument on the e-stack (any bytes; len 0 is the null string)  */

Private void net_push_string(const char* s, int len) {
  k_put_string((char*)s, len, e_stack);
  e_stack++;
}

/* ======================================================================
   net_parse_rc()  -  Read the answer of the handler from rc_descr.  FALSE if it is not an answer.  Fields are cut at a field mark; a
   message argument is cut at NET_ARG_MAX.                                                                                         */

Private int net_field(const char* buf, int fno, char* out, int outsize) {
  const char* p = buf;
  const char* q;
  int n;

  while (--fno > 0) {
    p = strchr(p, (u_char)FIELD_MARK);
    if (p == NULL) {
      out[0] = '\0';
      return 0;
    }
    p++;
  }
  q = strchr(p, (u_char)FIELD_MARK);
  n = (q == NULL) ? (int)strlen(p) : (int)(q - p);
  if (n > outsize - 1)
    n = outsize - 1;
  memcpy(out, p, n);
  out[n] = '\0';
  return n;
}

Private bool net_parse_rc(DESCRIPTOR* rc_descr, NET_RC* rc) {
  char buf[NET_RC_BUF];
  char num[24];

  if ((rc_descr->type != STRING) && (rc_descr->type != INTEGER))
    return FALSE;

  (void)k_get_c_string(rc_descr, buf, sizeof(buf) - 1); /* a long answer is cut: the fields that matter are first */

  if (net_field(buf, 1, num, sizeof(num)) == 0)
    return FALSE;
  rc->result = atoi(num);
  if ((rc->result != NF_RC_OK) && (rc->result != NF_RC_ELSE) && (rc->result != NF_RC_ERROR))
    return FALSE;

  (void)net_field(buf, 2, num, sizeof(num));
  rc->msg = atoi(num);
  (void)net_field(buf, 3, rc->arg[0], sizeof(rc->arg[0]));
  (void)net_field(buf, 4, rc->arg[1], sizeof(rc->arg[1]));
  (void)net_field(buf, 5, rc->arg[2], sizeof(rc->arg[2]));
  (void)net_field(buf, 6, num, sizeof(num));
  rc->status = atoi(num);
  return TRUE;
}

/* ======================================================================
   net_call_raw()  -  Run the handler once: $netfile(op, a, b, c, out, rc).  The string arguments are copied (any bytes); out is left in
   *out for the caller, which must release it.  TRUE if the handler ran to its RETURN and gave an answer in *rc; otherwise FALSE with
   net_msg set (12512) and *out released.  Does not send the queued closes (net_call() does that first).                              */

Private bool net_call_raw(int op, const char* a, int alen, const char* b, int blen, const char* c, int clen, NET_RC* rc, DESCRIPTOR* out) {
  DESCRIPTOR rc_descr;
  OBJECT_HEADER* hdr;
  bool returned;
  bool usable;

  memset(rc, 0, sizeof(*rc));
  out->type = UNASSIGNED;
  rc_descr.type = UNASSIGNED;

  /* The program is looked for first so that a tree that has not catalogued it says so, rather than stopping the process with "cannot
     find program".  load_object() finds it in its list after the first time. */
  if (load_object("$netfile", FALSE) == NULL) {
    net_set_message(MSG_HANDLER, "the program $netfile is not in the global catalogue", "", "");
    return FALSE;
  }

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = op;
  net_push_string(a, alen);
  net_push_string(b, blen);
  net_push_string(c, clen);
  InitDescr(e_stack, ADDR); /* out */
  (e_stack++)->data.d_addr = out;
  InitDescr(e_stack, ADDR); /* rc */
  (e_stack++)->data.d_addr = &rc_descr;

  /* As call_trigger() does, with the program found by name.  k_call() counts a reference to the object; k_return() gives it back only
     for a program that is not PF_IS_TRIGGER, so the count is given back here when the program has returned. */
  k_call("$netfile", 6, NULL, 0);
  hdr = (OBJECT_HEADER*)c_base;
  process.program.flags |= PF_IS_TRIGGER;
  k_run_program();
  returned = (k_exit_cause == K_EXIT_RECURSIVE);
  k_exit_cause = 0;

  if (returned && (--(hdr->ext_hdr.prog.refs) == 0) && (hdr->id < 0))
    unload_object((void*)hdr); /* an expired object that nobody else is running, as k_return() would */

  usable = returned && net_parse_rc(&rc_descr, rc);
  k_release(&rc_descr);

  if (!usable) {
    k_release(out);
    out->type = UNASSIGNED;
    net_set_message(MSG_HANDLER, returned ? "it gave no answer that can be read" : "it did not run to its end", "", "");
    return FALSE;
  }

  return TRUE;
}

/* ======================================================================
   net_flush_pending()  -  Send NF$CLOSE for the handles whose file variable was released where BASIC could not be run.  Each handle comes
   off the queue before it is sent, so a failure part way loses at most that one; what the server says is of no interest.               */

Private void net_flush_pending() {
  char hs[16];
  NET_RC rc;
  DESCRIPTOR out;
  int h;

  while (net_pending_ct > 0) {
    h = net_pending[--net_pending_ct];
    snprintf(hs, sizeof(hs), "%d", h);
    if (net_call_raw(NF_CLOSE, hs, (int)strlen(hs), "", 0, "", 0, &rc, &out))
      k_release(&out);
  }
}

/* ======================================================================
   net_stale()  -  Is this file variable no longer a usable remote file (closed, or opened before the last net_close_all())?  */

Private bool net_stale(FILE_VAR* fvar) {
  return (fvar->type != NET_FILE) || (fvar->access.net.handle <= 0) || (fvar->access.net.epoch != net_epoch);
}

/* ======================================================================
   net_error_status()  -  The negative status for an error the handler reported  */

Private int net_error_status(const NET_RC* rc) {
  switch (rc->msg) {
    case MSG_NO_GATE:
    case MSG_NOT_LISTED:
    case MSG_NO_CREDENTIAL:
      return -ER_PERM;
  }
  return -ER_NETWORK;
}

/* ======================================================================
   net_answer()  -  What the handler's answer means for the statement: 0 done (out holds the value; the caller releases it), a positive
   status for the ELSE branch, a negative one for an error with net_msg set.  out is released unless 0 is returned.                  */

Private int net_answer(bool ran, const NET_RC* rc, int else_status, DESCRIPTOR* out) {
  if (!ran)
    return -ER_NETWORK; /* net_call_raw() set the message and released out */

  switch (rc->result) {
    case NF_RC_OK:
      return 0;

    case NF_RC_ELSE:
      k_release(out);
      return (rc->status > 0) ? rc->status : else_status;
  }

  k_release(out);
  if (rc->msg > 0)
    net_set_message(rc->msg, rc->arg[0], rc->arg[1], rc->arg[2]);
  else
    net_set_message(MSG_HANDLER, "it reported an error without a message", "", "");
  return net_error_status(rc);
}

/* ======================================================================
   net_op()  -  An operation on the open remote file: NF$READ, NF$READV, NF$FILEINFO.  b and c are the handler's arguments (the handle
   is a).  Returns as net_answer().  Leaves process.op_flags as it found it.                                                        */

Private int net_op(FILE_VAR* fvar, int op, const char* b, int blen, const char* c, int clen, int else_status, DESCRIPTOR* out) {
  u_int16_t entry = process.op_flags;
  char hs[16];
  NET_RC rc;
  bool ran;
  int status;

  out->type = UNASSIGNED;

  if (net_stale(fvar)) {
    snprintf(hs, sizeof(hs), "%d", (int)fvar->access.net.handle);
    net_set_message(MSG_BAD_HANDLE, hs, "", "");
    return -ER_NETWORK;
  }
  snprintf(hs, sizeof(hs), "%d", (int)fvar->access.net.handle);

  net_flush_pending();
  ran = net_call_raw(op, hs, (int)strlen(hs), b, blen, c, clen, &rc, out);
  process.op_flags = entry;
  status = net_answer(ran, &rc, else_status, out);
  return status;
}

/* ======================================================================
   net_take_string()  -  The string in a descriptor handed over (the descriptor keeps nothing).  A number is made a string; anything else
   is nothing.                                                                                                                       */

Private STRING_CHUNK* net_take_string(DESCRIPTOR* d) {
  STRING_CHUNK* s;

  if ((d->type != STRING) && (d->type != INTEGER) && (d->type != FLOATNUM))
    return NULL;
  if (d->type != STRING)
    k_get_string(d);
  s = d->data.str.saddr;
  d->data.str.saddr = NULL;
  return s;
}

/* ======================================================================
   net_open()  -  OPEN of a file on another server.  encoded_path is char(1) 'N' char(1) server char(1) file (_voc_ref made it).
   Returns 0 with fvar a NET_FILE (no file table entry: file_id is still -1; read only and non-transactional), a positive status for the
   ELSE branch (the server has no such file: 3003), or a negative one with net_message() set.  Does not raise: open_file() does.        */

Private int net_open_work(FILE_VAR* fvar, const char* encoded_path) {
  char server[NET_SERVER_LEN + 1];
  char file[NET_FILE_NAME_MAX + 1];
  char safe[NET_SERVER_LEN + 1];
  char audit[96];
  const char* p;
  const char* q;
  size_t n;
  size_t i;
  u_int16_t entry = process.op_flags;
  NET_RC rc;
  DESCRIPTOR out;
  bool ran;
  int status;
  int handle;
  char hs[24];

  net_msg[0] = '\0';

  /* The pointer: char(1) 'N' char(1) server char(1) file.  _voc_ref checks the shapes; this checks only that the pieces are there and fit,
     and the handler checks the shapes again. */
  if ((encoded_path == NULL) || ((u_char)encoded_path[0] != 1) || (encoded_path[1] != 'N') || ((u_char)encoded_path[2] != 1)) {
    net_set_message(MSG_BAD_POINTER, "it does not begin N", "", "");
    return -ER_NAM;
  }
  p = encoded_path + 3;
  q = strchr(p, 1);
  if (q == NULL) {
    net_set_message(MSG_BAD_POINTER, "it names no file", "", "");
    return -ER_NAM;
  }
  n = (size_t)(q - p);
  if ((n < 1) || (n > NET_SERVER_LEN)) {
    net_set_message(MSG_BAD_POINTER, "the server name is empty or too long", "", "");
    return -ER_NAM;
  }
  memcpy(server, p, n);
  server[n] = '\0';
  p = q + 1;
  n = strlen(p);
  if ((n < 1) || (n > NET_FILE_NAME_MAX) || (strchr(p, 1) != NULL)) {
    net_set_message(MSG_BAD_POINTER, "the file name is empty, too long or has a second separator", "", "");
    return -ER_NAM;
  }
  memcpy(file, p, n);
  file[n] = '\0';

  /* The server name as it may be written in the audit trail and a message: lower case letters and digits only */
  for (i = 0; server[i] != '\0'; i++) {
    safe[i] = (((server[i] >= 'a') && (server[i] <= 'z')) || ((server[i] >= '0') && (server[i] <= '9'))) ? server[i] : '?';
  }
  safe[i] = '\0';

  /* THE GATE, before anything is loaded or called.  An $internal program is not exempt. */
  if (!net_gate_ok()) {
    net_set_message(MSG_NO_GATE, account(), safe, "");
    snprintf(audit, sizeof(audit), "netfile refused server=%s reason=gate", safe);
    audit_message(audit);
    return -ER_PERM;
  }

  net_flush_pending();
  ran = net_call_raw(NF_OPEN, server, (int)strlen(server), file, (int)strlen(file), "", 0, &rc, &out);
  process.op_flags = entry;

  status = net_answer(ran, &rc, ER_FNF, &out);
  if (status != 0)
    return status;

  /* The handle: a whole number from 1 to NET_MAX_HANDLES, in out as a string or a number */
  handle = 0;
  if ((out.type == STRING) || (out.type == INTEGER)) {
    (void)k_get_c_string(&out, hs, sizeof(hs) - 1);
    handle = atoi(hs);
    for (i = 0; hs[i] != '\0'; i++) {
      if ((hs[i] < '0') || (hs[i] > '9'))
        handle = 0; /* "3x", "-1" and the like are not a handle */
    }
  }
  k_release(&out);
  if ((handle < 1) || (handle > NET_MAX_HANDLES)) {
    net_set_message(MSG_HANDLER, "it gave no handle for the file", "", "");
    return -ER_NETWORK;
  }

  /* A NET_FILE: no file table entry, no lock, no transaction.  The first two words of the union are zeroed so that they read as a NULL
     access.dir.trg for any code that looks at a directory file's trigger without asking the type. */
  memset(&fvar->access, 0, sizeof(fvar->access));
  fvar->access.net.handle = (int16_t)handle;
  fvar->access.net.epoch = net_epoch;
  strcpy(fvar->access.net.server, server);
  fvar->file_id = -1;
  fvar->flags |= FV_RDONLY | FV_NON_TXN;
  fvar->type = NET_FILE;
  net_used = TRUE;

  return 0;
}

int net_open(FILE_VAR* fvar, const char* encoded_path) {
  int status = net_open_work(fvar, encoded_path);

  process.status = status; /* the BASIC that ran may have left anything here */
  return status;
}

/* ======================================================================
   net_close()  -  The file variable of a remote file is being freed (dio_close()).  Never fails the caller and never raises.
   A CLOSE statement (explicit_close) tells the server now.  Any other release - scope exit, an error unwinding, kill_process() - happens
   where BASIC must not be run, so the handle is queued and sent by the next call into this module.  The handle is cleared at once, so a
   second call for the same variable does nothing.  A file variable of an earlier epoch (net_close_all()) is not sent at all: its handle
   number may belong to another file now.                                                                                         */

void net_close(FILE_VAR* fvar) {
  int16_t handle;
  char hs[16];
  NET_RC rc;
  DESCRIPTOR out;
  u_int16_t entry = process.op_flags;

  if ((fvar == NULL) || (fvar->type != NET_FILE))
    return;

  handle = fvar->access.net.handle;
  if (net_stale(fvar))
    return;
  fvar->access.net.handle = 0;

  if (explicit_close) {
    explicit_close = FALSE; /* op_close() clears it after the release; if the handler stops the process first it must not stay set */
    net_flush_pending();
    snprintf(hs, sizeof(hs), "%d", (int)handle);
    if (net_call_raw(NF_CLOSE, hs, (int)strlen(hs), "", 0, "", 0, &rc, &out))
      k_release(&out);
    process.op_flags = entry;
  } else if (net_pending_ct < NET_MAX_HANDLES) {
    net_pending[net_pending_ct++] = handle;
  } /* else the queue is full: the handle stays open on the server until net_close_all() or the end of the process */
}

/* ======================================================================
   net_close_all()  -  LOGTO, and anything else that ends the session's use of the servers: every connection and handle is dropped.
   The new epoch makes every NET_FILE still held by a program stale.  The handler is called only if this process ever opened a remote
   file, so a LOGTO that never saw one costs a counter.                                                                               */

void net_close_all() {
  NET_RC rc;
  DESCRIPTOR out;
  u_int16_t entry = process.op_flags;

  net_epoch++;
  net_pending_ct = 0;

  if (!net_used)
    return;

  net_used = FALSE; /* the next successful open makes it TRUE again */
  if (net_call_raw(NF_CLOSEALL, "", 0, "", 0, "", 0, &rc, &out))
    k_release(&out);
  process.op_flags = entry;
}

/* ======================================================================
   net_read()  -  READ and MATREAD of a remote file.  0: the record is in *rec (a string chain the caller owns; NULL for a null record).
   Positive: the ELSE branch (ER_RNF, or the status the server sent, 3000 for an empty id).  Negative: an error, raised here unless ON
   ERROR.  *rec is left alone unless 0 is returned.                                                                                  */

int net_read(FILE_VAR* fvar, char* id, int16_t id_len, STRING_CHUNK** rec) {
  u_int16_t entry = process.op_flags;
  DESCRIPTOR out;
  int status;

  if (id_len < 1)
    return ER_IID; /* an empty or over-long id: the ELSE branch, as the handler would answer for an empty one */

  status = net_op(fvar, NF_READ, id, id_len, "", 0, ER_RNF, &out);
  process.op_flags = entry;
  if (status < 0)
    return net_raise(status, entry);
  if (status > 0)
    return status;

  *rec = net_take_string(&out);
  k_release(&out);
  return 0;
}

/* ======================================================================
   net_readv()  -  READV of a remote file.  As net_read(), with the value of field `field` in *out.  Field 0 asks only whether the record
   exists: 0 is "it does" and *out is a null string.                                                                                  */

int net_readv(FILE_VAR* fvar, char* id, int16_t id_len, int32_t field, STRING_CHUNK** value) {
  u_int16_t entry = process.op_flags;
  DESCRIPTOR out;
  char fs[24];
  int status;

  if (id_len < 1)
    return ER_IID;

  snprintf(fs, sizeof(fs), "%ld", (long)field);
  status = net_op(fvar, NF_READV, id, id_len, fs, (int)strlen(fs), ER_RNF, &out);
  process.op_flags = entry;
  if (status < 0)
    return net_raise(status, entry);
  if (status > 0)
    return status;

  *value = net_take_string(&out);
  k_release(&out);
  return 0;
}

/* ======================================================================
   net_fileinfo()  -  FILEINFO(file, key) for the keys the file variable does not answer itself (op_fileinfo() does those).  The value
   comes back as a string chain (NULL for a null string).  The handler answers keys 0, 1 and 2 and refuses every other (12507); the
   refusal is raised here, whatever op_flags says (FILEINFO has no ON ERROR).                                                         */

STRING_CHUNK* net_fileinfo(FILE_VAR* fvar, int key) {
  u_int16_t entry = process.op_flags;
  DESCRIPTOR out;
  char ks[24];
  STRING_CHUNK* s;
  int status;

  snprintf(ks, sizeof(ks), "%d", key);
  status = net_op(fvar, NF_FILEINFO, ks, (int)strlen(ks), "", 0, 0, &out);
  process.op_flags = entry;
  if (status < 0) {
    (void)net_raise(status, 0);
    return NULL;
  }
  if (status > 0)
    return NULL;

  s = net_take_string(&out);
  k_release(&out);
  return s;
}

/* ======================================================================
   net_select()  -  SELECT / SELECTV of a remote file: every record id the server holds, in *ids (a string of ids with field marks between,
   NULL for an empty file) and how many in *count.  0 on success, a positive status for the ELSE branch, a negative one for an error, raised
   here unless the statement has ON ERROR (process.op_flags & P_ON_ERROR at the call, as for net_read()).  The whole list comes in one
   piece, the way the server's own SELECT and READLIST give it; *ids and *count are set only on success.                                    */

int net_select(FILE_VAR* fvar, STRING_CHUNK** ids, int32_t* count) {
  u_int16_t entry = process.op_flags;
  DESCRIPTOR out;
  STRING_CHUNK* s;
  STRING_CHUNK* c;
  int status;
  int32_t n = 0;
  int16_t i;

  status = net_op(fvar, NF_SELECT, "", 0, "", 0, ER_FNF, &out);
  process.op_flags = entry;
  if (status < 0)
    return net_raise(status, entry);
  if (status > 0)
    return status;

  s = net_take_string(&out);
  k_release(&out);
  if (s != NULL) {
    n = 1;
    for (c = s; c != NULL; c = c->next) {
      for (i = 0; i < c->bytes; i++) {
        if (c->data[i] == FIELD_MARK)
          n++;
      }
    }
  }
  *ids = s;
  *count = n;
  return 0;
}

/* ======================================================================
   net_refuse()  -  Any statement but OPEN, CLOSE, READ, MATREAD, READV and FILEINFO, given a remote file: nothing is sent and nothing
   is touched.  Message 12506 names the server and the statement (in lower case, as the handler names them).  Returns the negative status
   (ER_NETWORK) if the statement has ON ERROR (process.op_flags & P_ON_ERROR at the call); without it the error is raised and this does
   not return.  It runs no BASIC, so nothing on the e-stack moves.                                                                    */

int net_refuse(FILE_VAR* fvar, const char* what) {
  u_int16_t entry = process.op_flags;
  char op[48];
  size_t i;
  const char* server = "";

  if ((fvar != NULL) && (fvar->type == NET_FILE))
    server = fvar->access.net.server;

  for (i = 0; (what != NULL) && (what[i] != '\0') && (i < sizeof(op) - 1); i++)
    op[i] = ((what[i] >= 'A') && (what[i] <= 'Z')) ? (char)(what[i] - 'A' + 'a') : what[i];
  op[i] = '\0';

  net_set_message(MSG_READ_ONLY, server, op, "");
  return net_raise(-ER_NETWORK, entry);
}

/* END-CODE */
