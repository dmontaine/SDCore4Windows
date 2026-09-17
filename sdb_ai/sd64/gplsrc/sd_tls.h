/* SD_TLS.H
 * TLS for the SD API transport
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
 * START-HISTORY:
 * 16 Sep 26 Windows port - RELEASE_1.1 43: the relay is a NATIVE program,
 *           sdtlsrelay/sdtlsrelay.c, spawned by sd as a bare account at Low
 *           integrity (win32relay.c).  The relay <-> sd frame protocol and the
 *           account name are declared here so both processes read one copy.
 * 15 Sep 26 Windows port - adopted from SD Core for Linux S.19 (its branch
 *           s19-tls @ 0d58171), RELEASE_1.1 41.  Every API connection is TLS
 *           1.3, and the SCRAM login is bound to the TLS session (RFC 9266
 *           tls-exporter), so the session is encrypted and a man in the
 *           middle cannot complete a login even though the client does not
 *           verify a certificate.  The constants here are THE WIRE CONTRACT
 *           SHARED WITH LINUX and must not drift: a Windows client talks to a
 *           Linux server and the other way round.  gplsrc/sdclilib/sd_tls.h
 *           carries the native client's copy of the same constants;
 *           gplbld/test-tlsconsts-units.py keeps the two equal.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * sd_tls.c     settings both ends share, the handshake, the binding, and the
 *              POSIX client (linked into sd, for BASIC's SKT$TLS sockets)
 * sd_tlssrv.c  the server's relay process (linked into sd only)
 *
 * The NATIVE client library has its own sd_tls.c in gplsrc/sdclilib: it is
 * Win32 code (Winsock, no signals, no fcntl), built with the UCRT64 and
 * mingw32 compilers and linked with a static OpenSSL, so it never sees the
 * MSYS2 runtime.  Same API, same constants, different I/O primitives.
 *
 * WHY A RELAY PROCESS AND NOT SSL_read() IN linuxio.c: an API session reads
 * its socket from a SIGIO handler (linuxio.c io_handler -> do_input), and
 * OpenSSL may not be called from a signal handler.  poll() also cannot see
 * bytes OpenSSL has already decrypted.  The relay owns the network socket and
 * the TLS state; sd keeps its descriptors 0 and 1, now one end of a local
 * socketpair, and none of its I/O code changes.
 *
 * END-DESCRIPTION
 */

#ifndef SD_TLS_H
#define SD_TLS_H

#include <stddef.h>

/* NO bool IN THIS HEADER, AND NO <stdbool.h>.  SD's own headers define bool
   as their own type (sdclilib.h declares SDDebug(int16_t) and defines it with
   bool), and <stdbool.h> would redefine it for every file that includes this
   one - measured on Linux 15 Sep 2026: sdclilib.c stopped compiling.  So the
   calls that answer yes or no return int: non-zero yes, zero no. */

#define SD_TLS_BINDING_BYTES 32                /* RFC 9266 section 2 */
#define SD_TLS_BINDING_LABEL "EXPORTER-Channel-Binding"
#define SD_TLS_GS2_HEADER    "p=tls-exporter,,"
#define SD_TLS_HANDSHAKE_MS  10000
#define SD_TLS_IDENTITY_FILE "api.pem"
/* The identity directory, under the data directory (the one holding sd.conf):
   C:\ProgramData\SD\sd-tls.  gplbld/secure-tls.ps1 creates it at install with
   SYSTEM and Administrators only; sd_tlssrv.c refuses it otherwise. */
#define SD_TLS_IDENTITY_DIR  "sd-tls"

/* ---- shared (sd_tls.c) ------------------------------------------------ */

/* Arguments are SSL_CTX* / SSL*, passed as void* so that including this
   header does not require the OpenSSL headers. */
int sd_tls_restrict_ctx(void* ctx);
int sd_tls_handshake(void* ssl, int fd, int timeout_ms, int server,
                     char* errmsg, size_t errlen);
int sd_tls_export_binding(void* ssl, unsigned char* out);
char* sd_tls_cbind_attr(const unsigned char* binding);   /* malloc'd */
void sd_tls_error_text(const char* what, char* errmsg, size_t errlen);

/* ---- client (sd_tls.c) ------------------------------------------------ */

typedef struct SD_TLS_CLIENT SD_TLS_CLIENT;

SD_TLS_CLIENT* sd_tls_client_start(int fd, int timeout_ms,
                                   char* errmsg, size_t errlen);
int sd_tls_client_read(SD_TLS_CLIENT* c, void* buf, int len);
int sd_tls_client_pending(SD_TLS_CLIENT* c);   /* decrypted bytes held */
int sd_tls_client_write(SD_TLS_CLIENT* c, const void* buf, int len);
const unsigned char* sd_tls_client_binding(SD_TLS_CLIENT* c);
int sd_tls_client_peer_sha256(SD_TLS_CLIENT* c, unsigned char* out);
const char* sd_tls_client_version(SD_TLS_CLIENT* c);
void sd_tls_client_end(SD_TLS_CLIENT* c);

/* ---- server (sd_tlssrv.c) --------------------------------------------- */

int sd_tls_relay_start(const char* identity_dir, int timeout_ms,
                       char* errmsg, size_t errlen);
const unsigned char* sd_tls_server_binding(void);      /* NULL: no TLS */

/* ---- Windows (win32tls.c, includes windows.h and no SD header) -------- */

/* Non-zero when every allow ACE on the object grants only SYSTEM (S-1-5-18)
   or BUILTIN\Administrators (S-1-5-32-544).  Anything else - an inherited
   sdusers Modify, a stray grant - is a refusal, and why says which SID. */
int win32_admin_only(const char* path, char* why, size_t whylen);

/* ---- The Windows relay: sd_tlssrv.c <-> sdtlsrelay/sdtlsrelay.c ------- */

/* RELEASE_1.1 43.  The relay is a NATIVE program (the MSYS2 runtime cannot
   start at Low while sd holds it), spawned per connection by sd - LocalSystem
   - as the bare local account below, every privilege removed, integrity Low.
   It inherits exactly two handles: the accepted connection and one end of the
   socketpair sd keeps as descriptors 0 and 1.  Over the socketpair, BEFORE
   any network byte is parsed:

     sd    -> relay   u32 big-endian length, then that many PEM bytes: the
                      server identity, which the relay cannot read itself
                      (SYSTEM and Administrators only).  Linux reads it as
                      root before dropping to nobody; a spawn cannot inherit
                      an open file the way a fork does, so the bytes travel.
     relay -> sd      one status byte.  SD_RELAY_OK is followed by the
                      SD_TLS_BINDING_BYTES channel binding - Linux's 32-byte
                      preamble, one byte later.  Anything else is followed by
                      a u16 big-endian length and that much text, then EOF;
                      the numbers are the Linux relay's exit codes, and the
                      relay exits with the same one.

   Then bytes flow: decrypted network -> socketpair, socketpair -> network. */
#define SD_RELAY_EXE          "sdtlsrelay.exe"    /* beside sd.exe, like sdpy */
#define SD_RELAY_ACCOUNT      "sdrelay"           /* install-service.ps1 */
#define SD_RELAY_IDENTITY_MAX 65536
#define SD_RELAY_OK             0
#define SD_RELAY_EXIT_IDENTITY  2
#define SD_RELAY_EXIT_PRIVILEGE 3    /* unused here: the drop is sd's, before the spawn */
#define SD_RELAY_EXIT_HANDSHAKE 4
#define SD_RELAY_EXIT_BINDING   5
#define SD_RELAY_EXIT_USAGE     6    /* bad argv or handles: a bug, not a peer */

/* win32relay.c (windows.h, no SD header).  Mint the account's token, strip
   it, drop it to Low, and start exe (beside sd.exe) with the two Cygwin
   descriptors as its only inherited handles.  Non-zero on success, with
   *proc an opaque handle for win32_relay_exit_code(); zero with why on
   failure.  The relay's argv is: <net handle> <sp handle> <timeout ms>.   */
int win32_relay_spawn(const char* account, int net_fd, int sp_fd,
                      int timeout_ms, void** proc, char* why, size_t whylen);
/* The exit code if the relay has ended, or -1 while it runs; releases the
   handle either way (the caller asks once, at the end of the preamble).     */
int win32_relay_exit_code(void* proc, int wait_ms);

#endif
