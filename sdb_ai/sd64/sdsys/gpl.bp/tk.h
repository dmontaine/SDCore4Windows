* TK.H
* The full-screen toolkit's shared base (S.75, plan .claude/plan-fullscreen-toolkit.md): the layout and the two tables every app uses.
* Copyright (c) 2026, SD Core for Linux.  This program is free software; you can redistribute
* it and/or modify it under the terms of the GNU General Public License, version 3 or later.
*
* START-HISTORY:
* 10 Nov 26 Windows port - level with Linux e3490a7f; TK.C.AI (slot 11), which the 25 Oct carry left out, is back: the AI routines are carried and find the AI unusable (no helper here, RELEASE_1.1 173).
* 25 Oct 26 Windows port - from Linux 04f1eaa - the toolkit base and tool.keys (S.75 TK-0.1 to TK-1)
* 22 Oct 26 dm  New (TK-0.1: the frame, the key table and the function-key row).
* 26 Oct 26 dm  faults: TK.MAXW and TK.MAXH, the largest window a page is given (a session at 200 by 9999 spent minutes opening the screen).
* 28 Oct 26 dm  S.88 L1, the layout service ($tk_layout): ctx slots 12 to 26 (the floor, the body, the mode, the frame-cache epoch, the panes), the body's
*               origin (TK.XBODY, TK.YBODY), the smallest floor an app may declare (TK.LEASTW, TK.LEASTH) and the pane declaration's attributes (TK.P.*).
*               No slot before 12 moved.
* 30 Oct 26 dm  S.88 F0a: ctx slot 27 (TK.C.BAR), the menu bar's record of what it drew.  No slot before 27 moved.
* 1 Nov 26 dm   S.97 stage 1: ctx slot 28 (TK.C.AIROW), the row the AI line takes from the body, and key-table value 10 (TK.K.AI), an action offered to the AI.  Nothing before them moved.
* 1 Nov 26 dm   S.97 stage 4: TK.K.AI may be 2 (offered, and it makes or compiles something).  No slot moved.
* END-HISTORY
*
* THE MINIMUM WINDOW is 140 columns by 43 lines (the owner's ruling of 20 Oct 2026).  The 43rd line is the function-key row, outside the window below its border.
* THE MAXIMUM WINDOW is 500 columns by 300 lines (26 Oct 2026, task faults).  The library keeps the screen as one value to a row of a single dynamic array, and every
* row written copies the array, so opening a screen costs time that grows with the SQUARE of the height: measured on a closed pipe, tool.keys opened a 140 by 400 window
* in 0.5 s, 140 by 1600 in 5.6 s, 140 by 3200 in 21.5 s and a 200 by 9999 window (what the sandbox suites' plain sessions set so that nothing pages) did not draw in 40 s
* at full CPU.  $tk_open refuses a window above this size, before it takes the screen, in the words of message 11951; 500 by 300 opens in about a second.
*
*   It is also the REFERENCE layout: the size every pane declaration is written for (TK.P.*), and every app's floor unless it declares another to $tk_open.
*
* THE FOOT OF THE SCREEN, counted from the last row of the layout (the layout is the window when it is bigger than the app's floor, the floor when it is smaller; never
* bigger than TK.MAXW by TK.MAXH):
*      row H-1   the function keys      (YKEYS)
*      row H-2   the border             (YBORD)
*      row H-3   the status line        (YSTAT)   [pane]  message
*   and row 0 is the menu bar, whose right end holds the app's name and the audience (an app that has a menu draws the menu first).
*
* THE CONTEXT ctx is one dynamic array made by $tk_open and given to every other routine:
$define TK.MINW        140
$define TK.MINH        43
$define TK.MAXW        500
$define TK.MAXH        300
$define TK.C.W         1       ;* the layout's width: the window's, or the app's floor (TK.C.FLOORW, TK.MINW unless declared) when it is smaller
$define TK.C.H         2       ;* the layout's height
$define TK.C.UTF8      3       ;* 1 when the terminal says UTF-8 (the screen was opened with line drawing)
$define TK.C.TRAP      4       ;* the break setting before the app took it, for $tk_close to give back
$define TK.C.APP       5       ;* the app's name, for the right end of row 0
$define TK.C.AUD       6       ;* the audience as the person reads it: "administrator", or "name@account"
$define TK.C.YSTAT     7       ;* the row of the status line
$define TK.C.YBORD     8       ;* the row of the border
$define TK.C.YKEYS     9       ;* the row of the function keys
$define TK.C.GEN       10      ;* a number the app raises to have $tk_frame write all of the frame again (after the screen was cleared or repainted under it)
$define TK.C.AI        11      ;* 1 when the AI line is drawn on row YSTAT - 1 (set by $tk_ai 'init'; the AI is on for this account and the helper has a provider, model and key), else null
*   Slots 12 to 26 are the layout service's ($tk_layout, 28 Oct 2026).  $tk_open fills them; $tk_layout 'refresh' makes them the window's again after a resize.
$define TK.C.FLOORW    12      ;* the app's floor: the smallest window it is laid out for (TK.MINW unless the app declared another to $tk_open)
$define TK.C.FLOORH    13
$define TK.C.WINW      14      ;* the window ($sl_window) when the layout was last made
$define TK.C.WINH      15
$define TK.C.XBODY     16      ;* the body: the cells between the menu bar (row 0) and the status line, less a column at each side
$define TK.C.YBODY     17
$define TK.C.BODYW     18
$define TK.C.BODYH     19      ;* YSTAT - YBODY rows: the body ends on the row above the status line (the AI line's row when the AI is on, as the pages have always drawn)
$define TK.C.MODE      20      ;* full: every pane has at least its declared size; compact: the layout is smaller than 140 by 43 and a pane was made smaller or collapsed
$define TK.C.EPOCH     21      ;* the frame cache's epoch: a new number from each $tk_open, cleared by $tk_close; $tk_frame forgets what it wrote when it differs
$define TK.C.YMENU     22      ;* the row of the menu bar (0)
$define TK.C.PANES     23      ;* the pane declaration given to $tk_layout 'declare': a value to a pane, a subvalue to an attribute (TK.P.*)
$define TK.C.RECTS     24      ;* each pane's rectangle, a value to a pane in the order declared: x, y, w, h, shown (subvalues; shown 0 for a collapsed pane)
$define TK.C.CHANGED   25      ;* 1 when the last 'open', 'refresh' or 'declare' changed the frame, the body or a pane's rectangle, else 0
$define TK.C.PANEERR   26      ;* null, or why the last 'declare' was refused (the panes it holds are then none)
*   Slots 27 and up are the menu bar's ($tk_menubar, 30 Oct 2026, S.88 F0a).  No slot before 27 moved.
$define TK.C.BAR       27      ;* what $tk_menubar last drew on row 0: the width, the generation, the epoch, the pane and the menus; it draws again only when this differs
*   Slot 28 is the AI line's on a page of the toolkit ($tk_aipage, 1 Nov 2026, S.97 stage 1).
$define TK.C.AIROW     28      ;* 1 when the page has given the AI line a row: $tk_aipage 'init' sets it when the AI is usable, and $tk_layout then takes the LAST row of the body for the line (BODYH is one less; the stretching panes give the row up), else null and the page is laid out as it always was
*   Slot 29 is the focus marks' ($tk_frame, 1 Nov 2026, S.99: the owner's [*] / [-] of 19 Oct, the IDE's, on the pages).
$define TK.C.FOCI      29      ;* the panes that can take the focus: a value to each, the layout pane's id (TK.P.ID) and, as the second subvalue, the name the page gives $tk_frame for it; null: no marks
*
* THE BODY'S ORIGIN.  ONE NUMBER EACH: a menu bar of its own on row 0 that pushes every body down a row is TK.YBODY 2 (and the reference body below is a row shorter).
$define TK.XBODY       1       ;* the body starts in column 1 and ends a column short of the right edge: BODYW = W - 2 * TK.XBODY
$define TK.YBODY       1       ;* the first row of the body: BODYH = YSTAT - TK.YBODY
* THE SMALLEST FLOOR an app may declare to $tk_open: under 100 by 30 there is ED (plan section 12).  A floor is never larger than TK.MAXW by TK.MAXH.
$define TK.LEASTW      100
$define TK.LEASTH      30
*
* THE PANE DECLARATION given to $tk_layout 'declare': one FIELD to a pane, its VALUES these attributes.  Every size is the pane's size in the REFERENCE layout, 140 by 43
* (body 138 by 39): what the page draws today.  A larger layout gives the growth to the panes that stretch, by weight; a smaller one (an app whose floor is under 140 by 43)
* takes rows and columns from the panes that stretch, then from the fixed ones, down to their least size, and then collapses whole panes, the highest priority number first.
* The body is split into BANDS stacked from the top (band 1 first); a band into COLUMNS side by side (column 1 at the left); a column into the panes of that band and column,
* stacked in the order they are declared.  A band is as tall as its tallest column; a column as wide as its widest pane.
$define TK.P.ID        1       ;* the pane's id: a plain word, unique in the declaration
$define TK.P.BAND      2       ;* its band, 1 up
$define TK.P.COL       3       ;* its column in the band, 1 up (null 1)
$define TK.P.H         4       ;* its height in the reference layout, border rows included
$define TK.P.W         5       ;* its width in the reference layout
$define TK.P.GAP       6       ;* the columns left empty before its column (the first pane of a column says it; null 0)
$define TK.P.VKIND     7       ;* fixed (null) or stretch: whether it takes rows the layout has beyond the reference
$define TK.P.VWT       8       ;* the weight of a stretching pane's share of the rows (null 1)
$define TK.P.HKIND     9       ;* fixed (null) or stretch: the same for columns
$define TK.P.HWT       10      ;* the weight of its column's share of the columns (null 1)
$define TK.P.MINH      11      ;* the least height it may be given in a smaller layout (null: its height)
$define TK.P.MINW      12      ;* the least width (null: its width)
$define TK.P.PRIO      13      ;* collapse priority: null or 0 never collapses; otherwise the highest number collapses first
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
$define TK.K.MENU      6       ;* the menu title with its & mark ('&File'); null: the action is in no menu (op 'menu' sets it)
$define TK.K.ENTRY     7       ;* the entry text with its & mark ('&Save'); the key it shows is DERIVED from the table, never typed
$define TK.K.WHY       8       ;* why the action is not available now (op 'why' sets it, and ON to 0); null: available
$define TK.K.ROW       9       ;* 0: bound but not on the function-key row (a second key for one action); null or 1: on the row
$define TK.K.AI        10      ;* 1: the action may be OFFERED to the AI (op 'ai' sets it, per action; null is not offered, the default); 2: offered, and it does more than navigate (S.97 stage 4: Reject is the default, its argument reaches the page).  The AI can only press the page's own keys, so every confirm box and gate applies unchanged
