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
* 18 Oct 26 dm  S.65 slice 3e: NF$WRITE .. NF$LOCK are real for a write-mode handle; NF$WRITEU 14, NF$DELETEU 15, NF$RELEASE 16 and NF$RC.LOCKED 4
*               added; rc<6> is signed; rc<7> reports the mode.  netfiles.c mirrors the new numbers as NF_WRITEU, NF_DELETEU, NF_RELEASE, NF_RC_LOCKED.
* 20 Oct 26 dm  S.72: NF$FILELOCK 18 and NF$FILEUNLOCK 19 (QMNet parity, tier B); rc<8>, the server's reply STATUS() for NF$RECORDLOCKED and NF$FILEUNLOCK (tier A).
*               netfiles.c mirrors them as NF_FILELOCK and NF_FILEUNLOCK.
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
*    NF$WRITE      9    handle        record id    record   -                                 releases the session's lock on the record
*    NF$WRITEU    14    handle        record id    record   -                                 keeps the lock
*    NF$DELETE    10    handle        record id    -        -                                 an absent record is OK; releases the lock
*    NF$DELETEU   15    handle        record id    -        -                                 keeps the lock
*    NF$CLEARFILE 11    handle        -            -        -
*    NF$LOCK      12    handle        record id    l or u   -                                 l shared, u update; the no-wait form only.  The
*                                                            caller loops if it wants to wait.  NF$RC.LOCKED when another user holds it
*    NF$RELEASE   16    handle or 0   record id    -        -                                 b null = every lock on the file; a = 0 = every lock
*                                                            of the session on every connected server that has a write-mode handle open
*    NF$FILELOCK  18    handle        -            -        -                                 the NO-WAIT form only (the wait flag of request 32 is always 0: the
*                                                            server never blocks).  NF$RC.LOCKED when another user holds the file lock or a record lock
*                                                            in the file (rc<6> is the holder).  Refused like NF$LOCK for a read-mode handle   (S.72)
*    NF$FILEUNLOCK 19   handle        -            -        -                                 rc<8> is the server's answer: 0 the lock was this session's and is
*                                                            free, 3011 (ER$LCK) another user's, still held, 3012 (ER$NLK) nobody's.  Refused for a read-mode
*                                                            handle; never refused for the definition's mode read again (it changes no data), as NF$RELEASE   (S.72)
*    The six changing operations above (all but NF$RELEASE) are REFUSED (message 12506, nothing sent) for a handle whose server definition
*    says mode read, which is the delivered default; only SDSYS makes a server write (set.server).  14, 15 and 16 are new in slice 3e.
*    NF$STATE     13    -             -            -        counters and the connections      for tests; no network, no gate
*
*    rc  is a dynamic array.  rc<1> is the result: NF$RC.OK (0), NF$RC.ELSE (2: the record or the file was not found, the ELSE branch),
*        NF$RC.ERROR (3: an error, ON ERROR) or NF$RC.LOCKED (4: NF$LOCK only, the record is held by another user; rc<6> is the holder's user
*        number, -1 for a full lock table, -2 for a deadlock).  rc<2> is the message number, rc<3> to rc<5> its arguments (sysmsg(rc<2>, rc<3>,
*        rc<4>, rc<5>)); rc<6> is the remote STATUS() as a SIGNED whole number: for NF$RC.ELSE 3000 empty id, 3003 file not found, 3006 record
*        not found, and for an error the status the server itself reported (-3023 for a record not locked under MUSTLOCK, -3018 for a file the
*        server cannot write).  rc<7> is 1 on a successful NF$OPEN of a handle whose server is in write mode, and absent otherwise.  rc<8> (S.72)
*        is the server's reply STATUS(), and is read for exactly two operations: NF$RECORDLOCKED (the user number of the lock's owner on the
*        server, 0 when nothing is held) and NF$FILEUNLOCK (0, 3011 or 3012); every other success leaves it null, because the server sends
*        whatever the last statement left in STATUS().  All six arguments are always passed; a, b and c may be null.
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
$define NF$WRITEU         14       ;* slice 3e: 14 to 16 are new; 17 and 20 are not used (17 is kept for a possible combined lock-and-read)
$define NF$DELETEU        15
$define NF$RELEASE        16
$define NF$FILELOCK       18       ;* S.72: the file lock, no-wait only
$define NF$FILEUNLOCK     19       ;* S.72: give the file lock back

$define NF$RC.OK           0
$define NF$RC.ELSE         2
$define NF$RC.ERROR        3
$define NF$RC.LOCKED       4       ;* NF$LOCK only: another user holds the record

$define NF$MAX.SERVERS    10       ;* servers one process may hold a connection to (the plan, 4.6)
$define NF$MAX.HANDLES   100       ;* remote files one process may have open at once

* END-CODE
