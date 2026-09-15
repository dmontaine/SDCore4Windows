/* SD_TLS.H  (native client library)
 * TLS 1.3 for the SD API client, Windows/Winsock side.
 * Copyright (c) String Database
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
 * 15 Sep 26 Windows port - written for RELEASE_1.1 41 (Linux S.19).  The
 *           native client DLLs (sdclilib/sdclient 64-bit, qmclilib/qmclient
 *           32-bit) speak TLS to the API server.  Same wire contract as the
 *           server (gplsrc/sd_tls.c) and as Linux; different implementation,
 *           as the owner permitted (15 Sep 2026): Winsock, no signals, no
 *           fcntl, and OpenSSL STATIC-LINKED so the DLL stays single-file and
 *           copyable (VENDORING.md).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * THE WIRE CONSTANTS BELOW MUST EQUAL gplsrc/sd_tls.h EXACTLY - a Windows
 * client talks to a Linux server and the other way round.
 * gplbld/test-tlsconsts-units.py keeps the two copies equal.
 *
 * OpenSSL is confined to sd_tls.c: this header names no OpenSSL type, so the
 * rest of the client library (which includes windows.h, hence wincrypt.h) is
 * never exposed to the OpenSSL headers and the two do not clash over
 * X509_NAME and friends.
 *
 * END-DESCRIPTION
 */

#ifndef SD_TLS_H
#define SD_TLS_H

#include <winsock2.h>
#include <stddef.h>

#define SD_TLS_BINDING_BYTES 32                /* RFC 9266 section 2 */
#define SD_TLS_BINDING_LABEL "EXPORTER-Channel-Binding"
#define SD_TLS_GS2_HEADER    "p=tls-exporter,,"
#define SD_TLS_HANDSHAKE_MS  10000

typedef struct SD_TLS_CLIENT SD_TLS_CLIENT;

/* TLS 1.3 client handshake on an already-connected socket.  No certificate
   check: the SCRAM login bound to this session is what authenticates the
   server (sd_tls.c description).  NULL on failure, with errmsg filled. */
SD_TLS_CLIENT* sd_tls_client_start(SOCKET fd, int timeout_ms,
                                   char* errmsg, size_t errlen);

/* > 0 bytes, 0 the server closed, < 0 an error. */
int sd_tls_client_read(SD_TLS_CLIENT* c, void* buf, int len);

/* Decrypted bytes OpenSSL already holds, invisible to select(). */
int sd_tls_client_pending(SD_TLS_CLIENT* c);

/* The whole buffer (non-zero) or 0. */
int sd_tls_client_write(SD_TLS_CLIENT* c, const void* buf, int len);

/* This end's 32-byte tls-exporter binding. */
const unsigned char* sd_tls_client_binding(SD_TLS_CLIENT* c);

/* base64("p=tls-exporter,," + binding) - SCRAM's c= value.  malloc'd. */
char* sd_tls_cbind_attr(const unsigned char* binding);

/* close_notify, then free.  The caller closes the socket. */
void sd_tls_client_end(SD_TLS_CLIENT* c);

#endif
