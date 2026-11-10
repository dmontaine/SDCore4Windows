* IDEBRK.H
* The IDE's hand-over of breakpoints to the debugger (S.98 H2)
* Copyright (c) 2026, SD Core for Linux.  This program is free software; you can redistribute
* it and/or modify it under the terms of the GNU General Public License, version 3 or later.
*
* START-HISTORY:
* 1 Nov 26 dm  New.
* END-HISTORY
*
* START-DESCRIPTION:
*
*   The named common /idebrk/ is what the IDE (gpl.bp/ide) and the debugger (gpl.bp/debug) say to each other when F7 starts a debugging run:
*
*     ibk.mode   IBK.K.IDLE   nothing is handed over (the value of a common block before anything sets it: 0)
*                IBK.K.ARMED  the IDE has armed a run; the debugger has not yet looked at it
*                IBK.K.LIVE   the debugger took the hand-over at its first stop; ibk.out is what it last wrote back
*     ibk.path   the pathname of the source record the IDE compiled, as the compiler stores it in the object (directory, then the record id)
*     ibk.in     the lines (field marks between them, ascending) the person marked in the editor
*     ibk.go     1: with at least one line set, the program runs on from its first stop to the first one (F7); 0: the debugger stays at the first stop (Debug from the first line)
*     ibk.out    the lines that have a breakpoint now, written back by the debugger after every command and when it ends the program
*     ibk.bad    the lines of ibk.in the debugger did not set (no statement begins there, or past the 20 a program can have)
*     ibk.alt    1 while the debugger holds the terminal's alternate screen (so the IDE can give it back if the debugger dies)
*
*   Nothing here is read for any other purpose: the debugger compares ibk.path with the source path of the program it stops in, and the IDE and the debugger
*   take no file, no program name and no command from it.  The common lives and dies with the process.
*
*   Every read of ibk.mode is ibk.mode + 0 (a common block starts as 0, and BASIC does not short-circuit AND and OR).  No constant here spells a variable of the common in
*   another case (SD BASIC folds case in names: a constant IBK.MODE and ibk.mode would be one variable).
*
* END-DESCRIPTION
*
* START-CODE

$define IBK.K.IDLE      0
$define IBK.K.ARMED     1
$define IBK.K.LIVE      2

   common /idebrk/ ibk.mode,
                   ibk.path,
                   ibk.in,
                   ibk.go,
                   ibk.out,
                   ibk.bad,
                   ibk.alt

* END-CODE
