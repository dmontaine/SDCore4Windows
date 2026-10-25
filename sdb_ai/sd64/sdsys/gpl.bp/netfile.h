* NETFILE.H
* The operation codes, result codes and limits of the remote file handler $netfile (S.65)
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
* 17 Oct 26 dm  S.65 slice 3b: written.  The kernel (slice 3c) mirrors NF$ OPEN .. STATE and NF$RC.* in C, the way call_trigger() mirrors the
*               trigger's arguments; keep the two in step, a number here is a number there.
* END-HISTORY
*
* START-DESCRIPTION:
*
*    call $netfile(op, a, b, c, out, rc)
*
*    op                 a             b            c        out (on success)                 notes
*    NF$OPEN       1    server name   remote file  -        the handle (1 to NF$MAX.HANDLES)
*    NF$CLOSE      2    handle        -            -        -
*    NF$READ       3    handle        record id    -        the record
*    NF$READV      4    handle        record id    field    the field's value                read whole, then cut: the class has no readv
*    NF$RECORDLOCKED 5  handle        record id    -        0 not locked, else the class's code  (-3 -2 -1 another user holds a
*                                                            file, update or read lock; 1 2 3 this session holds a read, update or file lock)
*    NF$SELECT     6    handle        -            -        every record id, field marks between
*    NF$FILEINFO   7    handle        key          -        the value                         keys 0, 1, 2 only in stage 1
*    NF$CLOSEALL   8    -             -            -        -                                 every connection of the process
*    NF$WRITE      9 \
*    NF$DELETE    10  \ handle ...                                                             REFUSED in stage 1: read only
*    NF$CLEARFILE 11  /
*    NF$LOCK      12 /
*    NF$STATE     13    -             -            -        counters and the connections      for tests; no network, no gate
*
*    rc  is a dynamic array.  rc<1> is the result: NF$RC.OK (0), NF$RC.ELSE (2: the record or the file was not found, the ELSE branch)
*        or NF$RC.ERROR (3: an error, ON ERROR).  rc<2> is the message number, rc<3> to rc<5> its arguments (sysmsg(rc<2>, rc<3>, rc<4>,
*        rc<5>)); rc<6> is the remote STATUS() for NF$RC.ELSE (3000 empty id, 3003 file not found, 3006 record not found) and for an
*        error the server itself reported.  All six arguments are always passed; a, b and c may be null.
*
* END-DESCRIPTION
*
* START-CODE

$define NF$OPEN            1
$define NF$CLOSE           2
$define NF$READ            3
$define NF$READV           4
$define NF$RECORDLOCKED    5
$define NF$SELECT          6
$define NF$FILEINFO        7
$define NF$CLOSEALL        8
$define NF$WRITE           9
$define NF$DELETE         10
$define NF$CLEARFILE      11
$define NF$LOCK           12
$define NF$STATE          13

$define NF$RC.OK           0
$define NF$RC.ELSE         2
$define NF$RC.ERROR        3

$define NF$MAX.SERVERS    10       ;* servers one process may hold a connection to (the plan, 4.6)
$define NF$MAX.HANDLES   100       ;* remote files one process may have open at once

* END-CODE
