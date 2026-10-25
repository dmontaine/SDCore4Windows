* TK.H
* The full-screen toolkit's shared base (S.75, plan .claude/plan-fullscreen-toolkit.md): the layout and the two tables every app uses.
* Copyright (c) 2026, SD Core for Linux.  This program is free software; you can redistribute
* it and/or modify it under the terms of the GNU General Public License, version 3 or later.
*
* START-HISTORY:
* 25 Oct 26 Windows port - from Linux 04f1eaa - the toolkit base and tool.keys (S.75 TK-0.1 to TK-1)
* 22 Oct 26 dm  New (TK-0.1: the frame, the key table and the function-key row).
* END-HISTORY
*
* THE MINIMUM WINDOW is 140 columns by 43 lines (the owner's ruling of 20 Oct 2026).  The 43rd line is the function-key row, outside the window below its border.
*
* THE FOOT OF THE SCREEN, counted from the last row of the layout (the layout is the window when it is bigger than the minimum, the minimum when it is smaller):
*      row H-1   the function keys      (YKEYS)
*      row H-2   the border             (YBORD)
*      row H-3   the status line        (YSTAT)   [pane]  message
*   and row 0 is the menu bar, whose right end holds the app's name and the audience (an app that has a menu draws the menu first).
*
* THE CONTEXT ctx is one dynamic array made by $tk_open and given to every other routine:
$define TK.MINW        140
$define TK.MINH        43
$define TK.C.W         1       ;* the layout's width: the window's, or TK.MINW when it is smaller
$define TK.C.H         2       ;* the layout's height
$define TK.C.UTF8      3       ;* 1 when the terminal says UTF-8 (the screen was opened with line drawing)
$define TK.C.TRAP      4       ;* the break setting before the app took it, for $tk_close to give back
$define TK.C.APP       5       ;* the app's name, for the right end of row 0
$define TK.C.AUD       6       ;* the audience as the person reads it: "administrator", or "name@account"
$define TK.C.YSTAT     7       ;* the row of the status line
$define TK.C.YBORD     8       ;* the row of the border
$define TK.C.YKEYS     9       ;* the row of the function keys
$define TK.C.GEN       10      ;* a number the app raises to have $tk_frame write all of the frame again (after the screen was cleared or repainted under it)
*
* THE GATE TABLE ($tk_gate_info, plan section 2.4) returns one gate as a dynamic array, a field to a value:
$define TK.G.ID        1       ;* the gate's id, the column name of the gate screen: sh, os, sd, voc ...
$define TK.G.TITLE     2       ;* what a person calls it
$define TK.G.ON        3       ;* the modify.account word that turns it on (null for a planned gate)
$define TK.G.OFF       4       ;* the word that turns it off
$define TK.G.KIND      5       ;* register (a field of the account's register record) or group (membership of a Linux group)
$define TK.G.FIELD     6       ;* the ACC$ name of the register field (kind register)
$define TK.G.GROUP     7       ;* the Linux group (kind group)
$define TK.G.KEY       8       ;* the kernel key that holds it in a session, or null when only the register or a group holds it
$define TK.G.WHEN      9       ;* when a change reaches a person
$define TK.G.DEFAULT   10      ;* off or on, as delivered
$define TK.G.SLOT      11      ;* modify.account refuses two words of one slot that set it to different states (12796)
$define TK.G.ALLOWS    12      ;* one plain sentence: what ON allows
$define TK.G.STILL     13      ;* one plain sentence: what OFF still allows
$define TK.G.BEYOND    14      ;* 1 when the gate reaches beyond SD, to the operating system, the network or other servers
$define TK.G.STATUS    15      ;* built or planned
*
* THE KEY TABLE is one dynamic array, a key to a field; the values of a field are:
$define TK.K.KEY       1       ;* the key as $sl_key names it: f1, tab, ctrl-q ...
$define TK.K.LABEL     2       ;* what the function-key row says it does: help, sort ...
$define TK.K.ACT       3       ;* the action id the app acts on
$define TK.K.PANES     4       ;* sub-values: the panes that use the key; null is every pane
$define TK.K.ON        5       ;* 0 takes the key out of the row (and of the action lookup); null or 1 leaves it in
