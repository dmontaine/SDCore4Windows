* TKPUB.H
* The constants of the public full-screen toolkit (S.130), for a program that calls the !tk routines:  $include tkpub.h
* Copyright (c) 2026, SD Core for Linux.  This program is free software; you can redistribute
* it and/or modify it under the terms of the GNU General Public License, version 3 or later.
*
* START-HISTORY:
* 3 Nov 26 dm  New (S.130).  A copy of the names and values of gpl.bp/tk.h that a program needs; test-tkpublic-units.py keeps every one equal to tk.h's.
* END-HISTORY
*
* THE ROUTINES (each is called with CALL, ALWAYS with the number of arguments shown; a call with fewer stops with "Argument count mismatch"):
*    call !tkopen(app, ctx, err, floorw, floorh)               take the screen; ctx is the context below; err is null, or the message to print
*    call !tkclose(ctx)                                        give the screen back, on EVERY way out
*    call !tkkeys(op, keys, a, b, c, d, e)                     the key table (the function-key row, the help list, the menus and your key loop are all made from it)
*    call !tkframe(ctx, keys, pane, msg)                       the status line, the border, the function-key row, the focus marks
*    call !tkmenubar(op, ctx, keys, pane, a, b, c)             the menu bar, the finder (F2), the context menu (Shift-F10 and the right button)
*    call !tklayout(op, ctx, arg, ret)                         the body and the panes: declare, pane, body, refresh (after the key 'resize')
*    call !tkconfirm(sentence, lines, typed, res, msg, boxtitle, btns)    the box that shows a sentence and asks Run or Cancel; Cancel is the default
*    call !tkform(op, ctx, a, b, c)                            a form of several labelled entries: open, run, say, close
*    call !tkpickrec(ctx, mode, file, id, res, newtext)        pick a file and a record, or one entry of a list you give
*    call !tkout(op, ctx, a, b, c)                             the output pane: what the program printed and refused
*    call !tkwrap(text, width, out)                            a sentence cut into pieces that fit a width
* Each takes the ops of the internal routine it wraps; the descriptions are in the program's own header (sdsys/gpl.bp/tk*) and in the User guide.
*
* WHAT THE LIBRARY IS NOT.  It runs with the rights and the gates of the session that calls it and adds none.  It runs no command, writes no record and opens no file for
* writing; a handler for a key or a menu entry is your own CASE, with your own gates.  The AI line and the administrator pages are not part of it.
*
$define TK.MINW        140
$define TK.MINH        43
$define TK.MAXW        500
$define TK.MAXH        300
* THE CONTEXT ctx, one dynamic array made by !tkopen:
$define TK.C.W         1
$define TK.C.H         2
$define TK.C.UTF8      3
$define TK.C.TRAP      4
$define TK.C.APP       5
$define TK.C.AUD       6
$define TK.C.YSTAT     7
$define TK.C.YBORD     8
$define TK.C.YKEYS     9
$define TK.C.GEN       10
$define TK.C.FLOORW    12
$define TK.C.FLOORH    13
$define TK.C.WINW      14
$define TK.C.WINH      15
$define TK.C.XBODY     16
$define TK.C.YBODY     17
$define TK.C.BODYW     18
$define TK.C.BODYH     19
$define TK.C.MODE      20
$define TK.C.EPOCH     21
$define TK.C.YMENU     22
$define TK.C.PANES     23
$define TK.C.RECTS     24
$define TK.C.CHANGED   25
$define TK.C.PANEERR   26
$define TK.C.BAR       27
$define TK.C.FOCI      29
* Slots 11 and 28 belong to the AI line, which this library does not draw: it clears them on every call.
$define TK.XBODY       1
$define TK.YBODY       1
$define TK.LEASTW      100
$define TK.LEASTH      30
* THE PANE DECLARATION given to !tklayout 'declare': one FIELD to a pane, its VALUES these attributes (sizes are in the reference layout, 140 by 43, body 138 by 39).
$define TK.P.ID        1
$define TK.P.BAND      2
$define TK.P.COL       3
$define TK.P.H         4
$define TK.P.W         5
$define TK.P.GAP       6
$define TK.P.VKIND     7
$define TK.P.VWT       8
$define TK.P.HKIND     9
$define TK.P.HWT       10
$define TK.P.MINH      11
$define TK.P.MINW      12
$define TK.P.PRIO      13
* THE KEY TABLE, one dynamic array, a key to a field; the values of a field:
$define TK.K.KEY       1
$define TK.K.LABEL     2
$define TK.K.ACT       3
$define TK.K.PANES     4
$define TK.K.ON        5
$define TK.K.MENU      6
$define TK.K.ENTRY     7
$define TK.K.WHY       8
$define TK.K.ROW       9
