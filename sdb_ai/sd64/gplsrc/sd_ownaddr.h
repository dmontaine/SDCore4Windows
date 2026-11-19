/* sd_ownaddr.h
 * Is an address one of THIS machine's own (S.264)?
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
 * 18 Nov 26 Windows port - RELEASE_1.1 344, from Linux 02507803 (S.264); unchanged.
 * 18 Nov 26 dm  S.264 - written.  Checked by gplbld/test-ownaddr-units.py through gplbld/verify-ownaddr.c.
 * END-HISTORY
 */

#ifndef SD_OWNADDR_H
#define SD_OWNADDR_H

/* sd_own_address(addr)  1 when ADDR (IPv4 dotted, IPv6, or IPv4-mapped IPv6 "::ffff:a.b.c.d") is the address of one of this
   machine's interfaces (getifaddrs), 0 when it is not, -1 when ADDR is not an address or the interfaces could not be read.  A
   caller treats -1 as "not one of ours" (the refusal direction is the caller's to choose). */
int sd_own_address(const char* addr);

/* the same, with the machine's interface addresses given (OWN, N_OWN strings) instead of read: for the unit test */
int sd_own_address_in(const char* addr, const char* const* own, int n_own);

#endif
