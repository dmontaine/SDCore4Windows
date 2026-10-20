/* APIPKT.H
 * The length test for a packet the API server reads
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
 * 20 Oct 26 Windows port - carried from SD Core for Linux 1c2d0af (S.71), RELEASE_1.1 163.  Same file, same numbers; the only
 *               difference is in op_tio.c, which says what "before the user has logged in" means here (api_before_login()).
 * 20 Oct 26 dm  S.71: created.  op_readpkt() and process_client_input() (op_tio.c) read a 4-byte length from the client and then that
 *               many bytes, with no limit: 'garb' read as 1,651,663,207, so a client that sent four bytes made the server allocate
 *               and read for 27 minutes.  The owner's number (20 Oct 26): 65,536 before the user has logged in, the largest string
 *               after.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * A packet from the client is a 4-byte length that counts the whole packet, itself included, then a 2-byte request code (sdclilib.c
 * write_packet(): PKT_HDR_BYTES 6) and the body.  The same shape is used for the reply to an INPUT prompt.
 *
 * api_packet_length_ok() says whether a declared length can be a packet:
 *
 *   - not under 6, the header itself (this also refuses every negative value);
 *   - not over API_PKT_MAX_PRELOGIN (65,536) while no user has logged in.  Everything the server may be sent before that - the SCRAM
 *     messages - is under 4 KB;
 *   - not over API_PKT_MAX_STRING + 10 afterwards: the largest SD string (sddefs.h MAX_STRING_SIZE) plus the packet's header, so no
 *     packet that holds a legal SD string is refused.  (Linux's comment says this is also SD_MAX_PACKET_BYTES in sdclilib.c; here that
 *     constant is 256 MB, the most the client library accepts FROM a server, so it is a different limit and the server side keeps
 *     Linux's number.)
 *
 * It is a header of its own so that a small C program can test it without the kernel (gplbld/test-apipkt-units.py).
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#ifndef APIPKT_H
#define APIPKT_H

#include <stdint.h>

#define API_PKT_HDR_BYTES 6
#define API_PKT_MAX_PRELOGIN 65536
#define API_PKT_MAX_STRING 1073741822 /* = MAX_STRING_SIZE in sddefs.h; op_tio.c refuses to compile if they differ */

static inline int api_packet_length_ok(int32_t declared, int before_login) {
  if (declared < API_PKT_HDR_BYTES)
    return 0;
  if (before_login)
    return declared <= API_PKT_MAX_PRELOGIN;
  return declared <= (int32_t)API_PKT_MAX_STRING + 10;
}

#endif

/* END-CODE */
