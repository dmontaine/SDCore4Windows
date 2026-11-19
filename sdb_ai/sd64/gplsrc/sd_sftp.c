/* SD_SFTP.C
 * File transfer over the ssh login (RECEIVE / SEND): the transfer server inside sd, and the slot a session opens for it.
 * Copyright (c) 2026 The SD Developers, All Rights Reserved
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
 * 15 Nov 26 dm  S.242 stage 3 - written.  The check of its text is gplbld/test-sftp-units.py, the suite that runs it against the real
 *               OpenSSH client is gplbld/sandbox-sftp.py.
 * 19 Nov 26 Windows port - RELEASE_1.1 348: Linux fe151086 (S.242) carried unchanged; Windows' OpenSSH hands the same SSH_ORIGINAL_COMMAND.
 * 19 Nov 26 dm  S.242 - sx_is_subsystem(): the path followed only by blanks is the Subsystem request too.  OpenSSH 9.6 (Ubuntu 24.04)
 *               passes "/usr/local/sdsys/bin/sd-sftp " with a trailing space, and every sftp login there started an ordinary session
 *               (the client: "Received message too long"); found by witness-s242.py on an Ubuntu 24.04 install.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHO RUNS THIS.  An sftp client that signs in over ssh as an ordinary SD user is given sd by the ForceCommand of the ordinary Match arm
 * (gplbld/ssh-forcecommand.sh), with SSH_ORIGINAL_COMMAND set to the arm's Subsystem path (SD_SFTP_SUBSYSTEM) and no terminal.
 * xfer_detect(), called first in main(), sees that and nothing else: the process then signs in as an ordinary SD process (a user table
 * cell, so LISTU shows it and LOGOUT ends it), runs the command processor $xfersrv in place of $cproc, and never runs a command.
 * $xfersrv (gpl.bp/xfersrv) reads the register and decides; this file speaks the protocol (SFTP version 3) on the two descriptors
 * xfer_detect() moved away from 0 and 1, so that nothing SD prints can reach the client as protocol.
 *
 * THE SLOT.  Nothing is transferred unless a signed-in session of the same Linux user, in the same account, has opened a slot with
 * RECEIVE or SEND (KERNEL(K$XFER, 'open')).  The slot is six fields of that session's user table cell, not a file: a file in the
 * account could be written by the account's own programs.  It ends with the session, with 'close', or by time (XFERWAIT before the
 * first connection, XFERIDLE after the last activity - a connection, a write, a read or a file closed - and XFERMAX in all).
 * WHAT THE CELL DOES NOT DECIDE: XFER (sd.conf, read by this process), the account's xfer-on (the register, read by $xfersrv) and the
 * limits (sd.conf).  A process that wrote a slot into the shared segment would have gained only what typing RECEIVE gives.
 *
 * THE WALL.  "/" is one directory, <account>/xfer.in for RECEIVE and <account>/xfer.out for SEND, opened once (not followed if it is a
 * link) and every name is resolved against that descriptor and never followed: no "..", no sub-directory, no absolute path, no link.
 * A name is one that is a directory file's record id as it stands (sx_name_ok).  An incoming file is written to .part.<pid>.<n>, read
 * as it arrives (a NUL or a byte 248-255 refuses it: "plain text by content"), counted against XFERFILE and XFERSLOT, and given
 * its name only when the client closes it - never over a file that is there unless the slot was opened with OVERWRITE.  A RECEIVE slot
 * gives nothing out and a SEND slot takes nothing in.  Rename and remove reach only a file this connection has just taken.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE /* renameat2() */
#endif

#include <openssl/evp.h> /* before sd.h: descr.h defines SOCK, a name OpenSSL's headers use */

#include "sd.h"
#include "header.h"
#include "config.h"
#include "keys.h"
#include "sd_sftp.h"

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <strings.h>
#include <sys/stat.h>
#include <time.h>

#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1 << 0)
#endif

/* SFTP version 3 (draft-ietf-secsh-filexfer-02) */
#define FXP_INIT       1
#define FXP_VERSION    2
#define FXP_OPEN       3
#define FXP_CLOSE      4
#define FXP_READ       5
#define FXP_WRITE      6
#define FXP_LSTAT      7
#define FXP_FSTAT      8
#define FXP_SETSTAT    9
#define FXP_FSETSTAT   10
#define FXP_OPENDIR    11
#define FXP_READDIR    12
#define FXP_REMOVE     13
#define FXP_MKDIR      14
#define FXP_RMDIR      15
#define FXP_REALPATH   16
#define FXP_STAT       17
#define FXP_RENAME     18
#define FXP_READLINK   19
#define FXP_SYMLINK    20
#define FXP_STATUS     101
#define FXP_HANDLE     102
#define FXP_DATA       103
#define FXP_NAME       104
#define FXP_ATTRS      105

#define FX_OK                0
#define FX_EOF               1
#define FX_NO_SUCH_FILE      2
#define FX_PERMISSION_DENIED 3
#define FX_FAILURE           4
#define FX_OP_UNSUPPORTED    8

#define FXF_READ   0x01
#define FXF_WRITE  0x02
#define FXF_APPEND 0x04
#define FXF_CREAT  0x08
#define FXF_TRUNC  0x10
#define FXF_EXCL   0x20

#define ATTR_SIZE        0x01
#define ATTR_UIDGID      0x02
#define ATTR_PERMISSIONS 0x04
#define ATTR_ACMODTIME   0x08

#define SX_MAX_PACKET  (256 * 1024 + 1024) /* the largest request taken: OpenSSH's own limit is 256 kb */
#define SX_IN_SIZE     (SX_MAX_PACKET + 4)
#define SX_OUT_SIZE    (128 * 1024)
#define SX_MAX_DATA    65536               /* the most one READ answers */
#define SX_MAX_HANDLES 8
#define SX_DIR_BATCH   40                  /* names in one answer to READDIR */
#define SX_OWN_MAX     1024                /* names this connection has taken, which it may rename or remove */
#define SX_REFUSE_SECS 10                  /* how long a refusing server stays to say no */

/* Messages (sdsys/messages).  Each is sent to the client as the text of an SFTP status. */
#define XM_BAD_NAME   15081
#define XM_EXISTS     15082
#define XM_NOT_TEXT   15083
#define XM_FILE_BIG   15084
#define XM_SLOT_FULL  15085
#define XM_KIND       15086
#define XM_IN_ONLY    15087
#define XM_OUT_ONLY   15088
#define XM_NOT_HERE   15089
#define XM_NOT_OWN    15090
#define XM_ORDER      15091
#define XM_HANDLES    15094

/* The state of a slot */
#define XS_NONE 0
#define XS_LIVE 1
#define XS_WAIT 2 /* ended: no connection came within XFERWAIT */
#define XS_IDLE 3 /* ended: nothing happened for XFERIDLE */
#define XS_MAX  4 /* ended: XFERMAX */

/* Kinds of handle */
#define HK_FREE  0
#define HK_WRITE 1
#define HK_READ  2
#define HK_DIR   3

struct SXH {
  int kind;
  int fd;
  DIR* dir;
  char name[MAX_ID_LEN + 1]; /* the name the client asked for */
  char part[48];             /* HK_WRITE: the name the bytes are written under until the file is closed */
  int64_t size;              /* HK_WRITE: bytes taken; HK_READ: bytes given */
  EVP_MD_CTX* md;            /* HK_WRITE: SHA-256 of the bytes taken */
  bool dead;                 /* HK_WRITE: refused part way; the part is gone and the close will say failure */
};

Private struct {
  int dirfd;        /* the one directory */
  int dir;          /* XFER_IN or XFER_OUT */
  int flags;        /* XFS_... as the slot had them when found */
  int16_t h_index;  /* the holder's user table cell, 0 = none found */
  int16_t h_uid;    /* ...and what it held when found: a cell given to another process is another slot */
  int32_t h_pid;
  int64_t h_opened;
  u_char* in;       /* requests: bytes pos to have are unread */
  int32_t pos;
  int32_t have;
  u_char* out;      /* the answer being built */
  int32_t olen;
  u_char* rp;       /* the request being read */
  int32_t rleft;
  bool rbad;
  const char* why;  /* why the connection ended */
  int32_t files;    /* files taken or given by this connection */
  int64_t bytes;
  int32_t refused;  /* requests refused */
  struct SXH h[SX_MAX_HANDLES];
  char** own;
  int n_own;
  int part_seq;
  bool refusing;    /* the server only says no (xfer_refuse) */
  time_t deadline;
  const char* refuse_text;
} sx;

Private char sx_msgbuf[1024];

/* ======================================================================
   xfer_detect()  -  Is this process an sftp request?  Called first in main().

   Three things together and nothing else: no argument (the ForceCommand is sd alone), no terminal on descriptor 0, and
   SSH_ORIGINAL_COMMAND exactly the Subsystem path with SSH_CONNECTION set.  `ssh host <that path>` gives sshd's forced command the
   same variables, and so does a person who sets them by hand: both reach the same server, as the same user, behind the same gates.

   The channel is moved off descriptors 0 and 1, which are given /dev/null, BEFORE anything else runs: from here on no message, banner
   or run-time error SD prints can be read by the client as protocol.  Descriptor 2 is left: ssh shows it to the person.        */

/* 19 Nov 26 dm - S.242: the Subsystem path, followed by nothing or by spaces and tabs only.  OpenSSH 9.6 (Ubuntu 24.04) runs a
   Subsystem given in a Match block as the path and its empty argument list joined by a space ("subsystem: exec() /usr/local/sdsys/
   bin/sd-sftp "), and that is the SSH_ORIGINAL_COMMAND the forced command sees; OpenSSH 10 (Debian 13) sends the path alone.  Blanks
   carry no argument, so the rule is still "this path and nothing else": any other character after the path is not a match.        */
Private int sx_is_subsystem(const char* cmd) {
  size_t n = strlen(SD_SFTP_SUBSYSTEM);

  if (strncmp(cmd, SD_SFTP_SUBSYSTEM, n) != 0)
    return 0;
  for (cmd += n; *cmd != '\0'; cmd++) {
    if ((*cmd != ' ') && (*cmd != '\t'))
      return 0;
  }
  return 1;
}

void xfer_detect(int argc) {
  const char* cmd = getenv("SSH_ORIGINAL_COMMAND");
  const char* conn = getenv("SSH_CONNECTION");
  int nul;
  int n;

  if ((argc != 1) || (cmd == NULL) || (conn == NULL) || !sx_is_subsystem(cmd) || isatty(0))
    return;

  xfer_fd_in = fcntl(0, F_DUPFD_CLOEXEC, 10);
  xfer_fd_out = fcntl(1, F_DUPFD_CLOEXEC, 10);
  nul = open("/dev/null", O_RDWR);
  if ((xfer_fd_in < 0) || (xfer_fd_out < 0) || (nul < 0) || (dup2(nul, 0) < 0) || (dup2(nul, 1) < 0)) {
    fprintf(stderr, "sd: file transfer could not start\n");
    exit(1);
  }
  if (nul > 2)
    close(nul);

  is_xfer = TRUE;
  connection_type = CN_NONE;
  strcpy(command_processor, "$xfersrv");

  /* Where the connection came from, for LISTU and the audit trail: the first word of SSH_CONNECTION */
  n = (int)strcspn(conn, " ");
  if (n > MAX_SOCKET_ADDR_STR_LEN - 1)
    n = MAX_SOCKET_ADDR_STR_LEN - 1;
  memcpy(ip_addr, conn, n);
  ip_addr[n] = '\0';
}

/* ======================================================================
   xfer_slot_state()  -  Is the slot in this cell open, and for how long yet?                                                   */

Private int xfer_slot_state(USER_ENTRY* u, time_t now, int32_t* left) {
  int64_t age;
  int64_t idle;
  int64_t rem;

  if (left != NULL)
    *left = 0;
  if (u->xfer_dir == XFER_NONE)
    return XS_NONE;

  age = (int64_t)now - u->xfer_opened;
  if ((pcfg.xfermax > 0) && (age >= pcfg.xfermax))
    return XS_MAX;

  if (u->xfer_last == 0) { /* no connection yet */
    if (age >= pcfg.xferwait)
      return XS_WAIT;
    rem = pcfg.xferwait - age;
  } else {
    idle = (int64_t)now - u->xfer_last;
    if (idle >= pcfg.xferidle)
      return XS_IDLE;
    rem = pcfg.xferidle - idle;
  }

  if ((pcfg.xfermax > 0) && ((pcfg.xfermax - age) < rem))
    rem = pcfg.xfermax - age;
  if (left != NULL)
    *left = (int32_t)rem;
  return XS_LIVE;
}

/* Is the process that holds the slot still there?  A session that was killed keeps its user table cell, and its slot, until
   it is reaped: the slot of a process that has gone is no slot.                                                             */

Private bool xfer_holder_there(int32_t pid) {
  return (pid > 0) && ((kill((pid_t)pid, 0) == 0) || (errno != ESRCH));
}

Private const char* xfer_state_word(int st) {
  switch (st) {
    case XS_LIVE:
      return "live";
    case XS_WAIT:
      return "wait";
    case XS_IDLE:
      return "idle";
    case XS_MAX:
      return "max";
  }
  return "none";
}

/* ======================================================================
   Small helpers                                                                                                                */

Private void sx_audit(const char* fmt, ...) {
  char buf[900];
  va_list ap;

  va_start(ap, fmt);
  vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  audit_message(buf);
}

/* The text of message n with %1 and %2 filled in.  One buffer: use the answer before asking again. */
Private char* sx_msg(int n, const char* a1, const char* a2) {
  char* t = sysmsg(n);
  char* q = sx_msgbuf;
  char* end = sx_msgbuf + sizeof(sx_msgbuf) - 1;
  const char* a;

  while ((*t != '\0') && (q < end)) {
    if ((*t == '%') && ((t[1] == '1') || (t[1] == '2'))) {
      a = (t[1] == '1') ? a1 : a2;
      if (a != NULL) {
        while ((*a != '\0') && (q < end))
          *(q++) = *(a++);
      }
      t += 2;
    } else {
      *(q++) = *(t++);
    }
  }
  *q = '\0';
  return sx_msgbuf;
}

/* A name SD takes: a directory file's record id that is its own file name (op_dio3.c map_t1_id() would leave it as it is).
   So: 1 to MAX_ID_LEN bytes, not starting with '.' or '~', no control character, DEL or mark (248-255), and none of the
   characters a directory file writes as %x.  That shuts out "..", every path, and this server's own .part names.            */

Private bool sx_name_ok(const char* name) {
  size_t n = strlen(name);
  size_t i;
  u_char c;

  if ((n < 1) || (n > MAX_ID_LEN))
    return FALSE;
  if ((name[0] == '.') || (name[0] == '~'))
    return FALSE;
  for (i = 0; i < n; i++) {
    c = (u_char)name[i];
    if ((c < 32) || (c == 127) || (c >= 248))
      return FALSE;
    if (strchr(df_restricted_chars, (char)c) != NULL)
      return FALSE;
  }
  return TRUE;
}

/* XFERKIND: blank takes any name; else the name must end in a dot and one of the listed extensions (case aside). */

Private bool sx_kind_ok(const char* name) {
  const char* ext = strrchr(name, '.');
  const char* p = pcfg.xferkind;
  size_t n;
  bool any = FALSE;

  while (*p != '\0') {
    while ((*p == ',') || (*p == ' ') || (*p == '.'))
      p++;
    n = strcspn(p, ", ");
    if (n > 0) {
      any = TRUE;
      if ((ext != NULL) && (strlen(ext + 1) == n) && (strncasecmp(ext + 1, p, n) == 0))
        return TRUE;
    }
    p += n;
  }
  return !any;
}

/* Plain text by content (owner, 14 Nov 2026): no NUL and no byte SD keeps as a mark. */

Private bool sx_plain(const u_char* p, int32_t n) {
  while (n-- > 0) {
    if ((*p == 0) || (*p >= 248))
      return FALSE;
    p++;
  }
  return TRUE;
}

/* sx_path()  -  What a path the client sent names.  0 = the directory itself, 1 = a file in it (name, checked),
   -1 = refused (a "..", or a name SD does not take), -2 = nowhere (there are no sub-directories).                              */

Private int sx_path(const u_char* p, int32_t n, char* name) {
  int32_t i = 0;
  int32_t j;
  int comps = 0;

  if (memchr(p, 0, (size_t)n) != NULL)
    return -1;

  while (i < n) {
    while ((i < n) && (p[i] == '/'))
      i++;
    for (j = i; (j < n) && (p[j] != '/'); j++) {
    }
    if (j == i)
      break;
    if (((j - i) == 1) && (p[i] == '.')) {
      i = j;
      continue;
    }
    if (((j - i) == 2) && (p[i] == '.') && (p[i + 1] == '.'))
      return -1;
    if (++comps > 1)
      return -2;
    if ((j - i) > MAX_ID_LEN)
      return -1;
    memcpy(name, p + i, (size_t)(j - i));
    name[j - i] = '\0';
    i = j;
  }

  if (comps == 0)
    return 0;
  return sx_name_ok(name) ? 1 : -1;
}

/* ======================================================================
   The connection: is it still to go on?  Asked before every request and every second while waiting for one.                   */

Private bool sx_alive(void) {
  USER_ENTRY* h;
  time_t now = time(NULL);

  if (my_uptr->events & (EVT_LOGOUT | EVT_TERMINATE)) { /* LOGOUT n, or SD stopping */
    sx.why = "logout";
    return FALSE;
  }

  if (sx.refusing) {
    if (now >= sx.deadline) {
      sx.why = "refused";
      return FALSE;
    }
    return TRUE;
  }

  h = UPtr(sx.h_index);
  if ((h->uid != sx.h_uid) || (h->pid != sx.h_pid) || (h->xfer_dir != sx.dir) || (h->xfer_opened != sx.h_opened) ||
      !xfer_holder_there(sx.h_pid)) {
    sx.why = "closed"; /* the session closed the slot, or ended (a killed session keeps its cell until it is reaped) */
    return FALSE;
  }

  switch (xfer_slot_state(h, now, NULL)) {
    case XS_LIVE:
      return TRUE;
    case XS_MAX:
      sx.why = "max";
      break;
    default:
      sx.why = "idle";
      break;
  }
  return FALSE;
}

/* Something happened on the slot: the idle time starts again. */

Private void sx_touch(void) {
  if (!sx.refusing)
    UPtr(sx.h_index)->xfer_last = (int64_t)time(NULL);
}

/* ======================================================================
   Reading requests                                                                                                             */

/* Have n unread bytes in the buffer.  FALSE = the connection is over (sx.why says why). */

Private bool sx_need(int32_t n) {
  struct pollfd pfd;
  ssize_t got;
  int rc;

  while ((sx.have - sx.pos) < n) {
    if ((sx.pos > 0) && (((SX_IN_SIZE - sx.pos) < n) || (sx.have == SX_IN_SIZE))) { /* make room: move what is unread to the front */
      memmove(sx.in, sx.in + sx.pos, (size_t)(sx.have - sx.pos));
      sx.have -= sx.pos;
      sx.pos = 0;
    }

    pfd.fd = xfer_fd_in;
    pfd.events = POLLIN;
    pfd.revents = 0;
    rc = poll(&pfd, 1, 1000);
    if (rc < 0) {
      if (errno == EINTR)
        continue;
      sx.why = "error";
      return FALSE;
    }
    if (!sx_alive())
      return FALSE;
    if (rc == 0)
      continue;

    got = read(xfer_fd_in, sx.in + sx.have, (size_t)(SX_IN_SIZE - sx.have));
    if (got < 0) {
      if ((errno == EINTR) || (errno == EAGAIN))
        continue;
      sx.why = "error";
      return FALSE;
    }
    if (got == 0) {
      sx.why = "eof"; /* the client has gone */
      return FALSE;
    }
    sx.have += (int32_t)got;
  }
  return TRUE;
}

Private u_int32_t g_u32(void) {
  u_int32_t v;

  if (sx.rleft < 4) {
    sx.rbad = TRUE;
    sx.rleft = 0;
    return 0;
  }
  v = ((u_int32_t)sx.rp[0] << 24) | ((u_int32_t)sx.rp[1] << 16) | ((u_int32_t)sx.rp[2] << 8) | (u_int32_t)sx.rp[3];
  sx.rp += 4;
  sx.rleft -= 4;
  return v;
}

Private u_int64_t g_u64(void) {
  u_int64_t hi = g_u32();
  u_int64_t lo = g_u32();

  return (hi << 32) | lo;
}

/* A string of the request: a pointer into the buffer and its length (0 and rbad when the request is short). */

Private const u_char* g_str(int32_t* len) {
  u_int32_t n = g_u32();
  const u_char* p = sx.rp;

  if (sx.rbad || (n > (u_int32_t)sx.rleft)) {
    sx.rbad = TRUE;
    sx.rleft = 0;
    *len = 0;
    return sx.rp;
  }
  sx.rp += n;
  sx.rleft -= (int32_t)n;
  *len = (int32_t)n;
  return p;
}

/* ======================================================================
   Writing answers                                                                                                              */

Private void o_begin(int type) {
  sx.olen = 4;
  sx.out[sx.olen++] = (u_char)type;
}

Private void o_u32(u_int32_t v) {
  if (sx.olen + 4 > SX_OUT_SIZE)
    return;
  sx.out[sx.olen++] = (u_char)(v >> 24);
  sx.out[sx.olen++] = (u_char)(v >> 16);
  sx.out[sx.olen++] = (u_char)(v >> 8);
  sx.out[sx.olen++] = (u_char)v;
}

Private void o_u64(u_int64_t v) {
  o_u32((u_int32_t)(v >> 32));
  o_u32((u_int32_t)v);
}

Private void o_str(const void* p, int32_t n) {
  if (sx.olen + 4 + n > SX_OUT_SIZE)
    n = 0;
  o_u32((u_int32_t)n);
  memcpy(sx.out + sx.olen, p, (size_t)n);
  sx.olen += n;
}

Private void o_cstr(const char* s) {
  o_str(s, (int32_t)strlen(s));
}

Private bool o_send(void) {
  u_int32_t n = (u_int32_t)(sx.olen - 4);
  int32_t done = 0;
  ssize_t put;
  struct pollfd pfd;

  sx.out[0] = (u_char)(n >> 24);
  sx.out[1] = (u_char)(n >> 16);
  sx.out[2] = (u_char)(n >> 8);
  sx.out[3] = (u_char)n;

  while (done < sx.olen) {
    put = write(xfer_fd_out, sx.out + done, (size_t)(sx.olen - done));
    if (put < 0) {
      if (errno == EINTR)
        continue;
      if (errno == EAGAIN) {
        pfd.fd = xfer_fd_out;
        pfd.events = POLLOUT;
        (void)poll(&pfd, 1, 1000);
        if (!sx_alive())
          return FALSE;
        continue;
      }
      sx.why = "eof";
      return FALSE;
    }
    done += (int32_t)put;
  }
  return TRUE;
}

Private bool o_status(u_int32_t id, u_int32_t code, const char* text) {
  if (code != FX_OK && code != FX_EOF)
    sx.refused++;
  o_begin(FXP_STATUS);
  o_u32(id);
  o_u32(code);
  o_cstr((text != NULL) ? text : "");
  o_cstr("");
  return o_send();
}

Private void o_attrs(const struct stat* st) {
  o_u32(ATTR_SIZE | ATTR_UIDGID | ATTR_PERMISSIONS | ATTR_ACMODTIME);
  o_u64((u_int64_t)st->st_size);
  o_u32((u_int32_t)st->st_uid);
  o_u32((u_int32_t)st->st_gid);
  o_u32((u_int32_t)st->st_mode);
  o_u32((u_int32_t)st->st_atime);
  o_u32((u_int32_t)st->st_mtime);
}

/* The line `ls -l` would print, which a version 3 client shows as it is. */

Private void sx_longname(const struct stat* st, const char* name, char* out, size_t len) {
  char mode[11];
  char when[32];
  struct tm tmv;
  time_t t = st->st_mtime;
  int i;
  static const char bits[] = "rwxrwxrwx";

  mode[0] = S_ISDIR(st->st_mode) ? 'd' : '-';
  for (i = 0; i < 9; i++)
    mode[i + 1] = (st->st_mode & (0400 >> i)) ? bits[i] : '-';
  mode[10] = '\0';
  if ((localtime_r(&t, &tmv) == NULL) || (strftime(when, sizeof(when), "%b %e %H:%M", &tmv) == 0))
    strcpy(when, "?");
  snprintf(out, len, "%s %4lu %-8lu %-8lu %10lld %s %s", mode, (unsigned long)st->st_nlink, (unsigned long)st->st_uid,
           (unsigned long)st->st_gid, (long long)st->st_size, when, name);
}

/* ======================================================================
   Handles                                                                                                                      */

Private int sx_new_handle(void) {
  int i;

  for (i = 0; i < SX_MAX_HANDLES; i++) {
    if (sx.h[i].kind == HK_FREE) {
      memset(&sx.h[i], 0, sizeof(struct SXH));
      sx.h[i].fd = -1;
      return i;
    }
  }
  return -1;
}

Private struct SXH* sx_handle(void) {
  int32_t n;
  const u_char* p = g_str(&n);
  u_int32_t i;

  if (sx.rbad || (n != 4))
    return NULL;
  i = ((u_int32_t)p[0] << 24) | ((u_int32_t)p[1] << 16) | ((u_int32_t)p[2] << 8) | (u_int32_t)p[3];
  if ((i >= SX_MAX_HANDLES) || (sx.h[i].kind == HK_FREE))
    return NULL;
  return &sx.h[i];
}

Private bool o_handle(u_int32_t id, int i) {
  u_char hb[4];

  hb[0] = 0;
  hb[1] = 0;
  hb[2] = 0;
  hb[3] = (u_char)i;
  o_begin(FXP_HANDLE);
  o_u32(id);
  o_str(hb, 4);
  return o_send();
}

/* Give up a file that was being taken: the bytes written so far are deleted. */

Private void sx_drop_part(struct SXH* h) {
  if (h->fd >= 0) {
    close(h->fd);
    h->fd = -1;
  }
  if (h->part[0] != '\0') {
    (void)unlinkat(sx.dirfd, h->part, 0);
    h->part[0] = '\0';
  }
  if (h->md != NULL) {
    EVP_MD_CTX_free(h->md);
    h->md = NULL;
  }
  h->dead = TRUE;
}

Private void sx_free_handle(struct SXH* h) {
  if (h->kind == HK_WRITE)
    sx_drop_part(h); /* a file never closed by the client is not kept */
  if (h->dir != NULL)
    closedir(h->dir);
  else if (h->fd >= 0)
    close(h->fd);
  memset(h, 0, sizeof(struct SXH));
}

/* The names this connection has taken, which are the only ones it may rename or remove */

Private int sx_own_find(const char* name) {
  int i;

  for (i = 0; i < sx.n_own; i++) {
    if (strcmp(sx.own[i], name) == 0)
      return i;
  }
  return -1;
}

Private void sx_own_add(const char* name) {
  if ((sx_own_find(name) >= 0) || (sx.n_own >= SX_OWN_MAX))
    return;
  if ((sx.own[sx.n_own] = strdup(name)) != NULL)
    sx.n_own++;
}

Private void sx_own_drop(int i) {
  free(sx.own[i]);
  sx.own[i] = sx.own[--sx.n_own];
}

/* The holder's count of what the slot has moved, which more than one connection may add to */

Private void sx_count(int32_t files, int64_t bytes) {
  USER_ENTRY* h = UPtr(sx.h_index);

  StartExclusive(SHORT_CODE, 214);
  if ((h->uid == sx.h_uid) && (h->xfer_opened == sx.h_opened)) {
    h->xfer_files += files;
    h->xfer_bytes += bytes;
    if (h->xfer_files < 0)
      h->xfer_files = 0;
    if (h->xfer_bytes < 0)
      h->xfer_bytes = 0;
    h->xfer_last = (int64_t)time(NULL);
  }
  EndExclusive(SHORT_CODE);
  sx.files += files;
  sx.bytes += bytes;
}

/* Is a file of this name in the directory?  0 no, 1 a plain file, 2 something else (a link, a directory, a device). */

Private int sx_exists(const char* name, struct stat* st) {
  struct stat local;

  if (st == NULL)
    st = &local;
  if (fstatat(sx.dirfd, name, st, AT_SYMLINK_NOFOLLOW) != 0)
    return 0;
  return S_ISREG(st->st_mode) ? 1 : 2;
}

/* Give a finished file its name.  Never over a file that is there, unless the slot says OVERWRITE. */

Private bool sx_place(const char* from, const char* to) {
  if (sx.flags & XFS_OVERWRITE) {
    if (sx_exists(to, NULL) == 2)
      return FALSE; /* a link or a directory is not replaced */
    return renameat(sx.dirfd, from, sx.dirfd, to) == 0;
  }
  if (renameat2(sx.dirfd, from, sx.dirfd, to, RENAME_NOREPLACE) == 0)
    return TRUE;
  if ((errno != EINVAL) && (errno != ENOSYS))
    return FALSE;
  /* a file system with no RENAME_NOREPLACE: a hard link fails if the name is there */
  if (linkat(sx.dirfd, from, sx.dirfd, to, 0) != 0)
    return FALSE;
  (void)unlinkat(sx.dirfd, from, 0);
  return TRUE;
}

/* ======================================================================
   The requests                                                                                                                 */

/* A request for a file is refused: the reason goes to the audit trail (a client may show the person only "Failure") and to the
   client as the text of the status.                                                                                           */

Private bool sx_no(u_int32_t id, u_int32_t code, int msg, const char* a1, const char* a2, const char* reason, const char* name) {
  sx_audit("xfer refused reason=%s name=%s", reason, name);
  return o_status(id, code, sx_msg(msg, a1, a2));
}

Private bool rq_open(u_int32_t id) {
  int32_t plen;
  const u_char* p = g_str(&plen);
  u_int32_t pflags = g_u32();
  char name[MAX_ID_LEN + 1];
  char kb[16];
  struct SXH* h;
  struct stat st;
  int i;
  int what;

  if (sx.rbad)
    return o_status(id, FX_FAILURE, NULL);

  what = sx_path(p, plen, name);
  if (what <= 0) { /* a path, a "..", the directory itself, or a name SD does not take */
    snprintf(name, sizeof(name), "%.*s", (plen > 200) ? 200 : (int)plen, (const char*)p);
    return sx_no(id, (what == -2) ? FX_NO_SUCH_FILE : FX_PERMISSION_DENIED, XM_BAD_NAME, name, NULL, "not a name sd takes", name);
  }

  if (sx.dir == XFER_IN) {
    /* A file comes in: written from its start, whole, under a name of our own until it is closed */
    if (!(pflags & FXF_WRITE) || (pflags & FXF_READ))
      return sx_no(id, FX_PERMISSION_DENIED, XM_IN_ONLY, NULL, NULL, "receive slot gives nothing out", name);
    if ((pflags & FXF_APPEND) || !(pflags & FXF_CREAT))
      return sx_no(id, FX_OP_UNSUPPORTED, XM_ORDER, NULL, NULL, "not sent whole", name);
    if (!sx_kind_ok(name))
      return sx_no(id, FX_PERMISSION_DENIED, XM_KIND, name, pcfg.xferkind, "not a kind of file taken", name);
    what = sx_exists(name, NULL);
    if ((what != 0) && (!(sx.flags & XFS_OVERWRITE) || (what == 2) || (pflags & FXF_EXCL)))
      return sx_no(id, FX_FAILURE, XM_EXISTS, name, NULL, "name is there", name);
    if ((int64_t)UPtr(sx.h_index)->xfer_bytes >= ((int64_t)pcfg.xferslot * 1024)) {
      snprintf(kb, sizeof(kb), "%d", (int)pcfg.xferslot);
      return sx_no(id, FX_FAILURE, XM_SLOT_FULL, name, kb, "slot over xferslot", name);
    }

    if ((i = sx_new_handle()) < 0)
      return o_status(id, FX_FAILURE, sx_msg(XM_HANDLES, NULL, NULL));
    h = &sx.h[i];
    snprintf(h->part, sizeof(h->part), ".part.%d.%d", (int)getpid(), ++sx.part_seq);
    h->fd = openat(sx.dirfd, h->part, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, default_access);
    if (h->fd < 0) {
      h->part[0] = '\0';
      return o_status(id, FX_FAILURE, strerror(errno));
    }
    h->md = EVP_MD_CTX_new();
    if ((h->md == NULL) || (EVP_DigestInit_ex(h->md, EVP_sha256(), NULL) != 1)) {
      sx_drop_part(h);
      return o_status(id, FX_FAILURE, NULL);
    }
    strcpy(h->name, name);
    h->kind = HK_WRITE;
    sx_touch();
    return o_handle(id, i);
  }

  /* A file goes out: read only */
  if ((pflags & (FXF_WRITE | FXF_APPEND | FXF_CREAT | FXF_TRUNC | FXF_EXCL)) || !(pflags & FXF_READ))
    return sx_no(id, FX_PERMISSION_DENIED, XM_OUT_ONLY, NULL, NULL, "send slot takes nothing in", name);
  if ((i = sx_new_handle()) < 0)
    return o_status(id, FX_FAILURE, sx_msg(XM_HANDLES, NULL, NULL));
  h = &sx.h[i];
  h->fd = openat(sx.dirfd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if ((h->fd < 0) || (fstat(h->fd, &st) != 0) || !S_ISREG(st.st_mode)) {
    if (h->fd >= 0)
      close(h->fd);
    h->fd = -1;
    return o_status(id, FX_NO_SUCH_FILE, NULL);
  }
  strcpy(h->name, name);
  h->kind = HK_READ;
  sx_touch();
  return o_handle(id, i);
}

Private bool rq_write(u_int32_t id) {
  struct SXH* h = sx_handle();
  u_int64_t offset = g_u64();
  int32_t n;
  const u_char* data = g_str(&n);
  char kb[16];
  int32_t done = 0;
  ssize_t put;

  if (sx.rbad || (h == NULL))
    return o_status(id, FX_FAILURE, NULL);
  if (h->kind != HK_WRITE)
    return o_status(id, FX_PERMISSION_DENIED, sx_msg(XM_OUT_ONLY, NULL, NULL));
  if (h->dead)
    return o_status(id, FX_FAILURE, NULL);

  /* From the start and in order: a hole would be bytes nobody read, and there is no resume */
  if (offset != (u_int64_t)h->size) {
    sx_drop_part(h);
    return o_status(id, FX_FAILURE, sx_msg(XM_ORDER, NULL, NULL));
  }
  if (!sx_plain(data, n)) {
    sx_audit("xfer refused reason=not plain text bytes=%lld name=%s", (long long)h->size, h->name);
    sx_drop_part(h);
    return o_status(id, FX_FAILURE, sx_msg(XM_NOT_TEXT, h->name, NULL));
  }
  if ((h->size + n) > ((int64_t)pcfg.xferfile * 1024)) {
    sx_audit("xfer refused reason=file over xferfile name=%s", h->name);
    sx_drop_part(h);
    snprintf(kb, sizeof(kb), "%d", (int)pcfg.xferfile);
    return o_status(id, FX_FAILURE, sx_msg(XM_FILE_BIG, h->name, kb));
  }
  if (((int64_t)UPtr(sx.h_index)->xfer_bytes + h->size + n) > ((int64_t)pcfg.xferslot * 1024)) {
    sx_audit("xfer refused reason=slot over xferslot name=%s", h->name);
    sx_drop_part(h);
    snprintf(kb, sizeof(kb), "%d", (int)pcfg.xferslot);
    return o_status(id, FX_FAILURE, sx_msg(XM_SLOT_FULL, h->name, kb));
  }

  while (done < n) {
    put = write(h->fd, data + done, (size_t)(n - done));
    if (put < 0) {
      if (errno == EINTR)
        continue;
      put = errno;
      sx_drop_part(h);
      return o_status(id, FX_FAILURE, strerror((int)put));
    }
    done += (int32_t)put;
  }
  (void)EVP_DigestUpdate(h->md, data, (size_t)n);
  h->size += n;
  sx_touch();
  return o_status(id, FX_OK, NULL);
}

Private bool rq_read(u_int32_t id) {
  struct SXH* h = sx_handle();
  u_int64_t offset = g_u64();
  u_int32_t want = g_u32();
  u_char* buf;
  ssize_t got;

  if (sx.rbad || (h == NULL))
    return o_status(id, FX_FAILURE, NULL);
  if (h->kind != HK_READ)
    return o_status(id, FX_PERMISSION_DENIED, sx_msg(XM_IN_ONLY, NULL, NULL));
  if (want > SX_MAX_DATA)
    want = SX_MAX_DATA;

  o_begin(FXP_DATA);
  o_u32(id);
  buf = sx.out + sx.olen + 4;
  got = pread(h->fd, buf, want, (off_t)offset);
  if (got < 0)
    return o_status(id, FX_FAILURE, strerror(errno));
  if (got == 0)
    return o_status(id, FX_EOF, NULL);
  /* The same rule both ways: what goes out is plain text too */
  if (!sx_plain(buf, (int32_t)got)) {
    sx_audit("xfer refused reason=not plain text dir=out name=%s", h->name);
    return o_status(id, FX_FAILURE, sx_msg(XM_NOT_TEXT, h->name, NULL));
  }
  o_u32((u_int32_t)got);
  sx.olen += (int32_t)got;
  h->size += got;
  sx_touch();
  return o_send();
}

Private bool rq_close(u_int32_t id) {
  struct SXH* h = sx_handle();
  u_char digest[EVP_MAX_MD_SIZE];
  unsigned int dlen = 0;
  char hex[2 * EVP_MAX_MD_SIZE + 1];
  char name[MAX_ID_LEN + 1];
  char kb[16];
  unsigned int i;
  int64_t size;
  bool ok;

  if (sx.rbad || (h == NULL))
    return o_status(id, FX_FAILURE, NULL);

  if (h->kind == HK_READ) {
    if (h->size > 0) {
      sx_audit("xfer file dir=out bytes=%lld name=%s", (long long)h->size, h->name);
      sx_count(1, h->size);
    }
    sx_free_handle(h);
    return o_status(id, FX_OK, NULL);
  }

  if (h->kind == HK_DIR) {
    sx_free_handle(h);
    return o_status(id, FX_OK, NULL);
  }

  /* An incoming file: it gets its name now */
  strcpy(name, h->name);
  size = h->size;
  if (h->dead) {
    sx_free_handle(h);
    return o_status(id, FX_FAILURE, NULL);
  }
  if (((int64_t)UPtr(sx.h_index)->xfer_bytes + size) > ((int64_t)pcfg.xferslot * 1024)) { /* another connection filled the slot */
    sx_audit("xfer refused reason=slot over xferslot name=%s", name);
    sx_free_handle(h);
    snprintf(kb, sizeof(kb), "%d", (int)pcfg.xferslot);
    return o_status(id, FX_FAILURE, sx_msg(XM_SLOT_FULL, name, kb));
  }

  ok = (EVP_DigestFinal_ex(h->md, digest, &dlen) == 1) && (close(h->fd) == 0);
  h->fd = -1;
  if (!ok) { /* the last bytes did not reach the disk */
    sx_audit("xfer refused reason=write failed name=%s", name);
    sx_free_handle(h);
    return o_status(id, FX_FAILURE, NULL);
  }
  if (!sx_place(h->part, name)) {
    sx_audit("xfer refused reason=name is there name=%s", name);
    sx_free_handle(h); /* deletes the part */
    return o_status(id, FX_FAILURE, sx_msg(XM_EXISTS, name, NULL));
  }
  h->part[0] = '\0'; /* it has its name: nothing to delete */
  sx_free_handle(h);

  for (i = 0; i < dlen; i++)
    snprintf(hex + (2 * i), 3, "%02x", digest[i]);
  hex[2 * dlen] = '\0';
  sx_audit("xfer file dir=in bytes=%lld sha256=%s name=%s", (long long)size, hex, name);
  sx_own_add(name);
  sx_count(1, size);
  return o_status(id, FX_OK, NULL);
}

Private bool rq_stat(u_int32_t id) {
  int32_t plen;
  const u_char* p = g_str(&plen);
  char name[MAX_ID_LEN + 1];
  struct stat st;
  int what;

  if (sx.rbad)
    return o_status(id, FX_FAILURE, NULL);
  what = sx_path(p, plen, name);
  if (what == -1)
    return o_status(id, FX_PERMISSION_DENIED, NULL);
  if (what == -2)
    return o_status(id, FX_NO_SUCH_FILE, NULL);
  if (what == 0) {
    if (fstat(sx.dirfd, &st) != 0)
      return o_status(id, FX_FAILURE, NULL);
  } else if (sx_exists(name, &st) != 1) {
    return o_status(id, FX_NO_SUCH_FILE, NULL);
  }
  o_begin(FXP_ATTRS);
  o_u32(id);
  o_attrs(&st);
  return o_send();
}

Private bool rq_fstat(u_int32_t id) {
  struct SXH* h = sx_handle();
  struct stat st;

  if (sx.rbad || (h == NULL) || (fstat((h->kind == HK_DIR) ? sx.dirfd : h->fd, &st) != 0))
    return o_status(id, FX_FAILURE, NULL);
  o_begin(FXP_ATTRS);
  o_u32(id);
  o_attrs(&st);
  return o_send();
}

/* SETSTAT and FSETSTAT: a client that keeps times or modes (put -p) asks for them after a file.  Nothing is changed -
   SD decides the mode of a file in an account - and the request is answered as done, so that the transfer is not failed. */

Private bool rq_setstat(u_int32_t id) {
  int32_t plen;
  const u_char* p = g_str(&plen);
  char name[MAX_ID_LEN + 1];
  int what;

  if (sx.rbad)
    return o_status(id, FX_FAILURE, NULL);
  what = sx_path(p, plen, name);
  if (what == -1)
    return o_status(id, FX_PERMISSION_DENIED, NULL);
  if ((what == -2) || ((what == 1) && (sx_exists(name, NULL) != 1) && (sx_own_find(name) < 0)))
    return o_status(id, FX_NO_SUCH_FILE, NULL);
  return o_status(id, FX_OK, NULL);
}

Private bool rq_fsetstat(u_int32_t id) {
  struct SXH* h = sx_handle();

  if (sx.rbad || (h == NULL))
    return o_status(id, FX_FAILURE, NULL);
  return o_status(id, FX_OK, NULL);
}

Private bool rq_opendir(u_int32_t id) {
  int32_t plen;
  const u_char* p = g_str(&plen);
  char name[MAX_ID_LEN + 1];
  struct SXH* h;
  int what;
  int i;
  int fd;

  if (sx.rbad)
    return o_status(id, FX_FAILURE, NULL);
  what = sx_path(p, plen, name);
  if (what == -1)
    return o_status(id, FX_PERMISSION_DENIED, NULL);
  if (what != 0)
    return o_status(id, FX_NO_SUCH_FILE, NULL);
  if ((i = sx_new_handle()) < 0)
    return o_status(id, FX_FAILURE, sx_msg(XM_HANDLES, NULL, NULL));
  h = &sx.h[i];
  fd = openat(sx.dirfd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if ((fd < 0) || ((h->dir = fdopendir(fd)) == NULL)) {
    if (fd >= 0)
      close(fd);
    return o_status(id, FX_FAILURE, NULL);
  }
  h->kind = HK_DIR;
  return o_handle(id, i);
}

Private bool rq_readdir(u_int32_t id) {
  struct SXH* h = sx_handle();
  struct dirent* de;
  struct stat st;
  char longname[MAX_ID_LEN + 128];
  int32_t count_at;
  u_int32_t count = 0;

  if (sx.rbad || (h == NULL) || (h->kind != HK_DIR))
    return o_status(id, FX_FAILURE, NULL);

  o_begin(FXP_NAME);
  o_u32(id);
  count_at = sx.olen;
  o_u32(0);
  /* Only plain files with a name SD takes: no link, no directory, none of this server's own part files */
  while ((count < SX_DIR_BATCH) && ((de = readdir(h->dir)) != NULL)) {
    if (!sx_name_ok(de->d_name) || (sx_exists(de->d_name, &st) != 1))
      continue;
    sx_longname(&st, de->d_name, longname, sizeof(longname));
    o_cstr(de->d_name);
    o_cstr(longname);
    o_attrs(&st);
    count++;
  }
  if (count == 0)
    return o_status(id, FX_EOF, NULL);
  sx.out[count_at] = 0;
  sx.out[count_at + 1] = 0;
  sx.out[count_at + 2] = 0;
  sx.out[count_at + 3] = (u_char)count;
  return o_send();
}

Private bool rq_realpath(u_int32_t id) {
  int32_t plen;
  const u_char* p = g_str(&plen);
  char name[MAX_ID_LEN + 2];
  int what;

  if (sx.rbad)
    return o_status(id, FX_FAILURE, NULL);
  name[0] = '/';
  what = sx_path(p, plen, name + 1);
  if (what == -1)
    return o_status(id, FX_PERMISSION_DENIED, NULL);
  if (what == -2)
    return o_status(id, FX_NO_SUCH_FILE, NULL);
  if (what == 0)
    name[1] = '\0';
  o_begin(FXP_NAME);
  o_u32(id);
  o_u32(1);
  o_cstr(name);
  o_cstr(name);
  o_u32(0); /* no attributes */
  return o_send();
}

/* REMOVE and RENAME reach only a file this connection has just taken (a client that sends under a working name and renames it,
   or clears up after itself), in a RECEIVE slot.                                                                              */

Private bool rq_remove(u_int32_t id) {
  int32_t plen;
  const u_char* p = g_str(&plen);
  char name[MAX_ID_LEN + 1];
  struct stat st;
  int own;

  if (sx.rbad)
    return o_status(id, FX_FAILURE, NULL);
  if ((sx.dir != XFER_IN) || (sx_path(p, plen, name) != 1) || ((own = sx_own_find(name)) < 0)) {
    snprintf(name, sizeof(name), "%.*s", (plen > 200) ? 200 : (int)plen, (const char*)p);
    return sx_no(id, FX_PERMISSION_DENIED, XM_NOT_OWN, NULL, NULL, "not a file this connection sent", name);
  }
  if ((sx_exists(name, &st) != 1) || (unlinkat(sx.dirfd, name, 0) != 0))
    return o_status(id, FX_NO_SUCH_FILE, NULL);
  sx_own_drop(own);
  sx_count(-1, -(int64_t)st.st_size);
  sx_audit("xfer remove name=%s", name);
  return o_status(id, FX_OK, NULL);
}

Private bool rq_rename(u_int32_t id) {
  int32_t olen;
  const u_char* op = g_str(&olen);
  int32_t nlen;
  const u_char* np = g_str(&nlen);
  char from[MAX_ID_LEN + 1];
  char to[MAX_ID_LEN + 1];
  int own;
  int what;

  if (sx.rbad)
    return o_status(id, FX_FAILURE, NULL);
  if ((sx.dir != XFER_IN) || (sx_path(op, olen, from) != 1) || ((own = sx_own_find(from)) < 0)) {
    snprintf(from, sizeof(from), "%.*s", (olen > 200) ? 200 : (int)olen, (const char*)op);
    return sx_no(id, FX_PERMISSION_DENIED, XM_NOT_OWN, NULL, NULL, "not a file this connection sent", from);
  }
  if (sx_path(np, nlen, to) != 1) {
    snprintf(to, sizeof(to), "%.*s", (nlen > 200) ? 200 : (int)nlen, (const char*)np);
    return sx_no(id, FX_PERMISSION_DENIED, XM_BAD_NAME, to, NULL, "not a name sd takes", to);
  }
  if (!sx_kind_ok(to))
    return sx_no(id, FX_PERMISSION_DENIED, XM_KIND, to, pcfg.xferkind, "not a kind of file taken", to);
  if (sx_exists(from, NULL) != 1)
    return o_status(id, FX_NO_SUCH_FILE, NULL);
  what = sx_exists(to, NULL);
  if (((what != 0) && !(sx.flags & XFS_OVERWRITE)) || !sx_place(from, to))
    return sx_no(id, FX_FAILURE, XM_EXISTS, to, NULL, "name is there", to);
  sx_own_drop(own);
  sx_own_add(to);
  sx_touch();
  sx_audit("xfer rename to=%s from=%s", to, from);
  return o_status(id, FX_OK, NULL);
}

/* ======================================================================
   sx_serve()  -  The conversation, until it ends.  sx.why says why it did.                                                    */

Private void sx_serve(void) {
  u_int32_t len;
  u_int32_t id;
  int type;
  bool started = FALSE;
  bool ok = TRUE;
  int i;

  sx.why = "eof";
  while (ok) {
    if (!sx_need(4))
      break;
    len = ((u_int32_t)sx.in[sx.pos] << 24) | ((u_int32_t)sx.in[sx.pos + 1] << 16) | ((u_int32_t)sx.in[sx.pos + 2] << 8) |
          (u_int32_t)sx.in[sx.pos + 3];
    if ((len < 1) || (len > SX_MAX_PACKET)) {
      sx.why = "protocol";
      break;
    }
    if (!sx_need((int32_t)len + 4))
      break;
    sx.rp = sx.in + sx.pos + 4;
    sx.rleft = (int32_t)len;
    sx.rbad = FALSE;
    sx.pos += (int32_t)len + 4;
    if (sx.pos == sx.have) {
      sx.pos = 0;
      sx.have = 0;
    }

    type = *(sx.rp++);
    sx.rleft--;

    if (type == FXP_INIT) {
      if (started) {
        sx.why = "protocol";
        break;
      }
      started = TRUE;
      o_begin(FXP_VERSION);
      o_u32(3); /* version 3 and no extension */
      ok = o_send();
      continue;
    }
    if (!started) {
      sx.why = "protocol";
      break;
    }

    id = g_u32();
    if (sx.rbad) {
      sx.why = "protocol";
      break;
    }

    if (sx.refusing) { /* every request is told why there is no transfer */
      ok = o_status(id, FX_PERMISSION_DENIED, sx.refuse_text);
      continue;
    }
    if (!sx_alive())
      break;

    switch (type) {
      case FXP_OPEN:
        ok = rq_open(id);
        break;
      case FXP_CLOSE:
        ok = rq_close(id);
        break;
      case FXP_READ:
        ok = rq_read(id);
        break;
      case FXP_WRITE:
        ok = rq_write(id);
        break;
      case FXP_LSTAT:
      case FXP_STAT:
        ok = rq_stat(id);
        break;
      case FXP_FSTAT:
        ok = rq_fstat(id);
        break;
      case FXP_SETSTAT:
        ok = rq_setstat(id);
        break;
      case FXP_FSETSTAT:
        ok = rq_fsetstat(id);
        break;
      case FXP_OPENDIR:
        ok = rq_opendir(id);
        break;
      case FXP_READDIR:
        ok = rq_readdir(id);
        break;
      case FXP_REMOVE:
        ok = rq_remove(id);
        break;
      case FXP_RENAME:
        ok = rq_rename(id);
        break;
      case FXP_REALPATH:
        ok = rq_realpath(id);
        break;
      case FXP_MKDIR:
      case FXP_RMDIR:
        ok = o_status(id, FX_PERMISSION_DENIED, sx_msg(XM_NOT_HERE, NULL, NULL));
        break;
      default: /* links, extensions, anything newer */
        ok = o_status(id, FX_OP_UNSUPPORTED, sx_msg(XM_NOT_HERE, NULL, NULL));
        break;
    }
  }

  /* Whatever the client left open: a file half sent is deleted */
  for (i = 0; i < SX_MAX_HANDLES; i++) {
    if (sx.h[i].kind != HK_FREE)
      sx_free_handle(&sx.h[i]);
  }
}

/* Part files left by a server that was killed: remove those whose process has gone. */

Private void sx_sweep_parts(void) {
  DIR* d;
  struct dirent* de;
  int fd = openat(sx.dirfd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  int pid;
  int seq;

  if ((fd < 0) || ((d = fdopendir(fd)) == NULL)) {
    if (fd >= 0)
      close(fd);
    return;
  }
  while ((de = readdir(d)) != NULL) {
    if ((sscanf(de->d_name, ".part.%d.%d", &pid, &seq) == 2) && (pid > 1) && (kill(pid, 0) != 0) && (errno == ESRCH))
      (void)unlinkat(sx.dirfd, de->d_name, 0);
  }
  closedir(d);
}

Private bool sx_buffers(void) {
  if (sx.in == NULL)
    sx.in = (u_char*)malloc(SX_IN_SIZE);
  if (sx.out == NULL)
    sx.out = (u_char*)malloc(SX_OUT_SIZE);
  if (sx.own == NULL)
    sx.own = (char**)calloc(SX_OWN_MAX, sizeof(char*));
  sx.pos = 0;
  sx.have = 0;
  return (sx.in != NULL) && (sx.out != NULL) && (sx.own != NULL);
}

/* ======================================================================
   k_xfer()  -  KERNEL(K$XFER, arg), from a $internal program only.  arg is  op {<FM> ...} ; every answer is a string whose first
   field is OK or ERR.

     open <FM> dir <FM> flags   An ordinary session opens its slot (dir 1 in, 2 out; flags 1 = overwrite).  OK, or ERR <FM> off
                                (XFER is 0) | session (not a terminal session) | bad.
     close                      ...and closes it.  OK <FM> files <FM> bytes.
     state                      OK <FM> dir <FM> flags <FM> state <FM> seconds left <FM> files <FM> bytes <FM> connected,
                                state being none, live, wait, idle or max (the last three: ended, for that reason).
     name <FM> text             Is the text a name the server takes (sx_name_ok) of a kind XFERKIND allows?  OK, or ERR <FM> name.
     find <FM> account          The transfer server looks for an open slot of its own Linux user in that account.
                                OK <FM> dir <FM> flags <FM> holder's user number, or ERR <FM> none | expired | server.
     serve <FM> directory       The transfer server runs the conversation in that directory, for the slot found.
                                OK <FM> why <FM> files <FM> bytes <FM> refusals, or ERR <FM> server | slot | dir | memory.
     refuse <FM> text           The transfer server tells the client why there is no transfer.  OK.                            */

Private void xfer_answer(DESCRIPTOR* result, const char* fmt, ...) {
  char buf[400];
  va_list ap;

  va_start(ap, fmt);
  vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  k_put_c_string(buf, result);
}

void k_xfer(DESCRIPTOR* descr, DESCRIPTOR* result) {
  static char arg[MAX_PATHNAME_LEN + 600];
  char* f2;
  char* f3;
  USER_ENTRY* u;
  time_t now = time(NULL);
  int32_t left;
  int st;
  int n;
  int16_t i;
  bool expired = FALSE;
  char uname[MAX_USERNAME_LEN + 1];
  char acct[MAX_ACCOUNT_NAME_LEN + 1];
  struct stat dst;

  if (!(process.program.flags & HDR_INTERNAL)) {
    xfer_answer(result, "ERR%cinternal", FIELD_MARK);
    return;
  }
  n = k_get_c_string(descr, arg, (int)sizeof(arg) - 1);
  if (n < 0) {
    xfer_answer(result, "ERR%cbad", FIELD_MARK);
    return;
  }
  arg[n] = '\0';
  f2 = strchr(arg, FIELD_MARK);
  f3 = NULL;
  if (f2 != NULL) {
    *(f2++) = '\0';
    if ((f3 = strchr(f2, FIELD_MARK)) != NULL)
      *(f3++) = '\0';
  }

  if (strcmp(arg, "open") == 0) {
    n = (f2 != NULL) ? atoi(f2) : 0;
    if (pcfg.xfer != 1)
      xfer_answer(result, "ERR%coff", FIELD_MARK);
    else if (is_xfer || is_phantom || is_sdApiSrvr || (connection_type == CN_NONE))
      xfer_answer(result, "ERR%csession", FIELD_MARK);
    else if ((n != XFER_IN) && (n != XFER_OUT))
      xfer_answer(result, "ERR%cbad", FIELD_MARK);
    else {
      my_uptr->xfer_dir = XFER_NONE;
      my_uptr->xfer_flags = (u_int8_t)(((f3 != NULL) && (atoi(f3) & XFS_OVERWRITE) && (n == XFER_IN)) ? XFS_OVERWRITE : 0);
      my_uptr->xfer_opened = (int64_t)now;
      my_uptr->xfer_last = 0;
      my_uptr->xfer_files = 0;
      my_uptr->xfer_bytes = 0;
      my_uptr->xfer_dir = (u_int8_t)n;
      xfer_answer(result, "OK");
    }
    return;
  }

  if (strcmp(arg, "close") == 0) {
    xfer_answer(result, "OK%c%d%c%lld", FIELD_MARK, (int)my_uptr->xfer_files, FIELD_MARK, (long long)my_uptr->xfer_bytes);
    my_uptr->xfer_dir = XFER_NONE;
    my_uptr->xfer_flags = 0;
    return;
  }

  if (strcmp(arg, "state") == 0) {
    st = xfer_slot_state(my_uptr, now, &left);
    xfer_answer(result, "OK%c%d%c%d%c%s%c%d%c%d%c%lld%c%d", FIELD_MARK, (int)my_uptr->xfer_dir, FIELD_MARK, (int)my_uptr->xfer_flags,
                FIELD_MARK, xfer_state_word(st), FIELD_MARK, (int)left, FIELD_MARK, (int)my_uptr->xfer_files, FIELD_MARK,
                (long long)my_uptr->xfer_bytes, FIELD_MARK, (my_uptr->xfer_last != 0) ? 1 : 0);
    return;
  }

  if (strcmp(arg, "name") == 0) { /* is this a name the server takes?  One rule, asked by SEND before it copies a record out */
    xfer_answer(result, ((f2 != NULL) && sx_name_ok(f2) && sx_kind_ok(f2)) ? "OK" : "ERR%cname", FIELD_MARK);
    return;
  }

  /* The rest is the transfer server's */
  if (!is_xfer) {
    xfer_answer(result, "ERR%cserver", FIELD_MARK);
    return;
  }

  if (strcmp(arg, "find") == 0) {
    sx.h_index = 0;
    if ((f2 == NULL) || (pcfg.xfer != 1)) {
      xfer_answer(result, "ERR%cnone", FIELD_MARK);
      return;
    }
    for (i = 1; i <= sysseg->max_users; i++) {
      u = UPtr(i);
      if ((u->uid == 0) || (u == my_uptr) || (u->xfer_dir == XFER_NONE))
        continue;
      memcpy(uname, (char*)(u->username), sizeof(uname));
      uname[MAX_USERNAME_LEN] = '\0';
      memcpy(acct, (char*)(u->account), sizeof(acct));
      acct[MAX_ACCOUNT_NAME_LEN] = '\0';
      if ((strcmp(uname, process.username) != 0) || (stricmp(acct, f2) != 0) || !xfer_holder_there(u->pid))
        continue;
      if (xfer_slot_state(u, now, NULL) != XS_LIVE) {
        expired = TRUE;
        continue;
      }
      sx.h_index = i;
      sx.h_uid = u->uid;
      sx.h_pid = u->pid;
      sx.h_opened = u->xfer_opened;
      sx.dir = u->xfer_dir;
      sx.flags = u->xfer_flags;
      xfer_answer(result, "OK%c%d%c%d%c%d", FIELD_MARK, sx.dir, FIELD_MARK, sx.flags, FIELD_MARK, (int)sx.h_uid);
      return;
    }
    xfer_answer(result, "ERR%c%s", FIELD_MARK, expired ? "expired" : "none");
    return;
  }

  if (strcmp(arg, "serve") == 0) {
    if ((sx.h_index == 0) || (f2 == NULL)) {
      xfer_answer(result, "ERR%cslot", FIELD_MARK);
      return;
    }
    if (!sx_buffers()) {
      xfer_answer(result, "ERR%cmemory", FIELD_MARK);
      return;
    }
    /* The one directory: not followed if it is a link, and a directory */
    sx.dirfd = open(f2, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if ((sx.dirfd < 0) || (fstat(sx.dirfd, &dst) != 0) || !S_ISDIR(dst.st_mode)) {
      if (sx.dirfd >= 0)
        close(sx.dirfd);
      xfer_answer(result, "ERR%cdir", FIELD_MARK);
      return;
    }
    signal(SIGPIPE, SIG_IGN); /* a client that has gone is an end of file, not the end of this process */
    sx.refusing = FALSE;
    sx.files = 0;
    sx.bytes = 0;
    sx.refused = 0;
    if (sx.dir == XFER_IN)
      sx_sweep_parts();
    sx_touch();
    sx_serve();
    close(sx.dirfd);
    sx.h_index = 0;
    /* Written here and not by $xfersrv: a forced logout ends the program before its next statement */
    sx_audit("xfer disconnect dir=%s why=%s files=%d bytes=%lld refusals=%d", (sx.dir == XFER_IN) ? "in" : "out", sx.why,
             (int)sx.files, (long long)sx.bytes, (int)sx.refused);
    xfer_answer(result, "OK%c%s%c%d%c%lld%c%d", FIELD_MARK, sx.why, FIELD_MARK, (int)sx.files, FIELD_MARK, (long long)sx.bytes,
                FIELD_MARK, (int)sx.refused);
    return;
  }

  if (strcmp(arg, "refuse") == 0) {
    if (!sx_buffers()) {
      xfer_answer(result, "ERR%cmemory", FIELD_MARK);
      return;
    }
    signal(SIGPIPE, SIG_IGN);
    sx.refuse_text = (f2 != NULL) ? f2 : "";
    /* ssh shows descriptor 2 to the person: the reason, in words, whatever their client does with a status */
    fprintf(stderr, "sd: %s\n", sx.refuse_text);
    fflush(stderr);
    sx.refusing = TRUE;
    sx.deadline = now + SX_REFUSE_SECS;
    sx_serve();
    sx.refusing = FALSE;
    xfer_answer(result, "OK");
    return;
  }

  xfer_answer(result, "ERR%cbad", FIELD_MARK);
}

/* END-CODE */
