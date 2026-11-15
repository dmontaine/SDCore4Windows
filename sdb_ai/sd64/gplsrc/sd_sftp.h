/* SD_SFTP.H
 * File transfer over the ssh login (RECEIVE / SEND): the transfer server inside sd.
 * Copyright (c) 2026 The SD Developers, All Rights Reserved.  GNU General Public License version 3 or later, as the rest of SD.
 *
 * START-HISTORY:
 * 15 Nov 26 Windows port - RELEASE_1.1 299: SD_SFTP_SUBSYSTEM is the stock Windows Subsystem command, "sftp-server.exe" (see below).
 *               OS DEVIATION, flag it in every parity audit: the string differs, the mechanism and the outcome do not.
 * 15 Nov 26 dm  S.242 stage 3: new.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * SD_SFTP_SUBSYSTEM is the name gplbld/ssh-forcecommand.sh gives the sftp subsystem in the ordinary Match arm (its SFTP_CMD).
 * Nothing exists at that path.  sshd hands it to the arm's ForceCommand (sd) as SSH_ORIGINAL_COMMAND, and that exact string,
 * with no terminal and SSH_CONNECTION set, is how sd knows an sftp request from a login.  gplbld/test-sftp-units.py holds the
 * two spellings together.
 *
 * END-DESCRIPTION
 */

#ifndef SD_SFTP_H
#define SD_SFTP_H

/* 15 Nov 26 Windows port - RELEASE_1.1 299.  WINDOWS FORM: SD's ForceCommand is GLOBAL here (allow-ssh-groups.ps1: "every ssh session
   lands in SD", owner 15 Aug 2026), not in a Match arm, so sshd_config needs no Subsystem line of SD's own: an sftp request already
   reaches sd.exe through ForceCommand, with SSH_ORIGINAL_COMMAND the command of the machine's own "Subsystem sftp" line.  That line
   is the stock one - ssh-preflight.ps1 refuses to install over an sshd_config anybody else has changed - and the stock command is
   sftp-server.exe.  A reading, not yet measured: the VM witness of row 299 checks what Win32-OpenSSH actually passes. */
#define SD_SFTP_SUBSYSTEM "sftp-server.exe"

/* The slot a session opens with RECEIVE or SEND (USER_ENTRY.xfer_dir) */
#define XFER_NONE 0
#define XFER_IN   1 /* RECEIVE: files come in, to <account>/xfer.in */
#define XFER_OUT  2 /* SEND: files go out, from <account>/xfer.out */

#define XFS_OVERWRITE 0x01 /* USER_ENTRY.xfer_flags: RECEIVE OVERWRITE, an incoming name may replace a file that is there */

void xfer_detect(int argc);                             /* sd.c main(), first: is this process an sftp request? */
void k_xfer(DESCRIPTOR* descr, DESCRIPTOR* result);     /* op_kernel.c: KERNEL(K$XFER, ...) */

#endif
