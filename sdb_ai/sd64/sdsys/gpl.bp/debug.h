* DEBUG.H
* Debugger include file
* Copyright (c) 2006 Ladybridge Systems, All Rights Reserved

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
* 
* START-HISTORY:
* 13 Nov 26 Windows port - dbg.relay at the end of the common block (so no earlier variable moves): run.in's debug, RELEASE_1.1 253(b).
* 10 Nov 26 Windows port - level with Linux e3490a7f: ai.ok (24 Oct) before dbg.store, and S.98 H1/H3's styles and stops after it, as Linux has them.
* 1 Nov 26 dm  S.98 H1: the styles and the two stops of the new display are at the end of the common block, so no earlier variable moves.
* 26 Oct 26 Windows port - from Linux fa146d9 (QM4 Fixes 193, 550): data.lines, expand.np and MAX.DATA.AREA.LINES.  The carry of `debug` in a8d06eb0 took the program and left this
*           file out, so the bootstrap warned MAX.DATA.AREA.LINES and NEW.LINES "not assigned a value".
* 25 Aug 26 Windows port - removed FVAR.NET, mirroring NET_FILE going from
*           DESCR.H.  SDNet was removed on 18 Aug 26.
* 19 Jan 04  0.6.1 SD launch. Earlier history details suppressed.
* END-HISTORY
*
*  START-DESCRIPTION:

* *************************************************************************
* ******                           WARNING                           ******
* ******                                                             ******
* ******   Changes to this file may need to be reflected by changes  ******
* ******   the DEBUGGER.H C include file.                            ******
* ******                                                             ******
* *************************************************************************

* END-DESCRIPTION

* START-CODE

$define INITIAL.PROGRAMS      10    ;* Initial size of program matrices
$define INITIAL.CHUNKS        50    ;* Initial size of source chunk matrices
$define CHUNK.LOAD           100    ;* Lines per chunk
$define MAX.BREAKPOINTS       20    ;* Also in op_debug.c
$define DATA.AREA.LINES        5    ;* The data area's usual height; WINDOW n (5 to 15) changes it
$define MAX.DATA.AREA.LINES   15

   common /$debug/ debug.initialised,
                   data.lines,                 ;* Height of the data area in full screen mode (0 until the first entry)
                   expand.np,                  ;* The ^ command: show non-printing characters as ^nnn
                   full.screen,                ;* Full screen mode?
                   title.attr,
                   source.attr,
                   highlight.source.attr,
                   breakpoint.source.attr,
                   command.attr,
                   debug.screen.image,
                   debug.command.stack,
                   debug.overlay,
                   debug.data.area(MAX.DATA.AREA.LINES), ;* The data area

                   array.name,
                   array.offset,               ;* Position of rolling display
                   rows,
                   cols,
                   last.display,               ;* Last display command
                   src.pos,                    ;* Position for SRC n,m command
                   src.incr,                   ;* ...and line count

                   banned,
                   replacements,

                   chunk(INITIAL.CHUNKS),
                   next.chunk(INITIAL.CHUNKS),
                   free.chunk,                 ;* Free chunk chain head

                   program.id(INITIAL.PROGRAMS),    ;* Id (compile time)
                   program.name(INITIAL.PROGRAMS),  ;* Program name
                   program.src(INITIAL.PROGRAMS),   ;* The pathname of the program's source record (1 Nov 26: the AI's wall asks where the source it would send comes from)
                   head(INITIAL.PROGRAMS),
                   lines(INITIAL.PROGRAMS),
                   symbols(INITIAL.PROGRAMS),
                   equates(INITIAL.PROGRAMS),       ;* The equate and $DEFINE tokens of a $MODE DEBUG.EQUATES program: names @VM.. @FM values @VM..
                   program.flags(INITIAL.PROGRAMS),  ;* Header flags
                   last.program,

                   breakpoints,    ;* Stored as programindex.line, FM delimited
                   watch.var.name,              ;* Name of watched variable
                   watch.var.no,                ;* ... its variable number (14 Oct 26, WATCH var op value)
                   watch.index,                 ;* ... the element number of a matrix element, else 0
                   watch.op,                    ;* The condition's operator, null for an unconditional WATCH
                   watch.val,                   ;* ... and its value
                   watch.op.new,                ;* Parsed from the WATCH command, taken into watch.op when it is armed
                   watch.val.new,
                   arm.no,                      ;* Passed to arm.watch
                   arm.index,

                   system.variables,
                   basic.chars,                 ;* Valid characters in names
                   rebind.string,               ;* Codes to rebind keys
                   mouse.on,                    ;* Enable mouse string
                   mouse.off,                   ;* Disable mouse string

                   debugger.uid,                ;* Other side for phantom debugger

                   ai.ok,                       ;* 24 Oct 26: the AI command is available (the AI is usable for the account and the display is full screen); set once, in initialise

                   dbg.store,                   ;* 31 Oct 26 (W.11 F10b): the phantom debugger's private store, a directory file made by !pdbg_store (PDEBUG and PDBG open it; DEBUG uses it)

                   data.attr,                   ;* 1 Nov 26 (S.98 H1): the styles of the messages, of the Autos pane and its title, of the status line and of the line numbers
                   auto.attr,
                   head.attr,
                   rev.attr,
                   num.attr,
                   auto.here,                   ;* ...and the stops the Autos pane keys on, as program index:line: this one and the one before (0 when there is none)
                   auto.prev,
                   alt.able,                    ;* 2 Nov 26 (S.98 H3): the terminal has an alternate screen (smcup and rmcup); set once, in initialise. Without one a full-screen debugger takes the main screen for the length of a stop

                   dbg.relay                    ;* 13 Nov 26 Windows port (RELEASE_1.1 253(b)): '' or, while !RUNIN_DEBUG runs, the account run.in debugs in: the program is in ANOTHER process whose screen shares this terminal, so the full screen and the program's screen (F4, V) are as for a program in this session, and nothing that process names is opened here

* Event codes (additive)

$define DE$WATCH            1     ;* Watch variable has changed
$define DE$BREAKPOINT       2     ;* At breakpoint

* Debug actions

$define BRK$RUN             0     ;* Free run
$define BRK$STEP            1     ;* Step n debug elements
$define BRK$STEP.LINE       2     ;* Step n lines
$define BRK$LINE            3     ;* Run to line n
$define BRK$PARENT          4     ;* Run to parent
$define BRK$PARENT.PROGRAM  5     ;* Run to parent program
$define BRK$TRACE           6     ;* Return to debugged program in trace mode
$define BRK$ADD.LINE        7     ;* Add a new breakpoint line
$define BRK$CLEAR           8     ;* Clear all breakpoints
$define BRK$CLR.LINE        9     ;* Clear breakpoint line
$define BRK$GOTO.LINE       10    ;* Continue execution at given line

* File types from DESCR.H
$define FVAR.DIRECTORY      1
$define FVAR.DYNAMIC        2
$define FVAR.SEQ            3

* END-CODE
