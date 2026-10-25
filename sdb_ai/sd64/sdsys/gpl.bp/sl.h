* SL.H
* Screen library: the layout of the widget record and the screen context.
* Copyright (c) 2026, SD Core for Linux.  This program is free software; you can redistribute
* it and/or modify it under the terms of the GNU General Public License, version 3 or later.
*
* The widget record w is one dynamic array.  Fields 1 to 9 are the same for every widget;
* from SL.W.D (10) on a widget uses fields as it needs.
*
*   SL.W.TYPE   the widget's name: menu, msgbox, prompt ...
*   SL.W.X, SL.W.Y, SL.W.W, SL.W.H   its place and size in terminal cells (from 0)
*   SL.W.FLAGS  values: 'focusable', 'focused', 'visible', 'disabled'
*   SL.W.VALUE  what the widget returns (selected item code, text, button number ...)
*   SL.W.S1, SL.W.S2   state of the widget (selected item, cursor position ...)
*
* The screen context scr is one dynamic array:
*
*   SL.S.W, SL.S.H   size of the screen being used
*   SL.S.CLIP        x0, y0, x1, y1 as values: nothing is drawn outside it
*   SL.S.SHADOW      value r + 1 is the text of terminal row r (what the program believes is shown)
*   SL.S.RATTR       value r + 1 is 'R' if row r is in reverse video (SED's screen: whole rows only)
*   SL.S.ATTRS       value r + 1 is one style code per cell of row r (a screen the library owns; null on
*                    SED's, which only knows RATTR).  The codes are SL.CODES below, one for each style that
*                    $sl_theme names (n normal, r reverse, u underline, x both, b bold, w window, h highlight,
*                    a bar, s barsel, k hotkey, j hotkey.bar, e field, d disabled, y desktop, t text,
*                    g header, and the syntax styles c comment, q string, o constant, v keyword, p type,
*                    l preproc, z special, f error, i todo - what $sl_syntax gives the editor);
*                    $sl_attr turns a style name into its code and the theme says what each looks like.
*   SL.S.CUR         the library's cursor: value 1 is x, value 2 is y (where the program's next output goes)
*   SL.S.CURON       1 when the cursor is shown
*   SL.S.OWNED       1 for the screen SCREEN OPEN made; 0 for a transient blank one
*   SL.S.MOUSE       1 while SCREEN OPEN has switched mouse reporting on (SCREEN CLOSE switches it off)
*   SL.S.BCLIP, SL.S.NARROW   while $sl_form has narrowed SL.S.CLIP to the visible part of a container for the
*                    widget it is calling (18 Oct 26): NARROW is 1 and BCLIP is the clip that was in force before, the
*                    program's own.  A widget that opens a pop-up (the combo box's list, the memo's find line) lifts
*                    the clip to BCLIP while the pop-up is on the screen, so that it is not cut at the container's edge.
*   SL.S.SYNC        1 when the terminal is KNOWN to show exactly what SHADOW and ATTRS say (19 Oct 26): SCREEN OPEN with CLEAR made it
*                    so, and $sl_repaint makes it so again.  Null for a screen opened without CLEAR (the library believes it blank and
*                    the terminal may not be: whatever the program printed earlier is there) and for SED's own.
*   SL.S.DIFF        1 while $sl_form draws on a screen whose SYNC is 1 (it sets it on entry and clears it before it returns):
*                    $sl_put then leaves out text the terminal already shows in the same styles, so that a form drawn again, or a
*                    widget redrawn for a change that is in two of its rows, writes only what changed.  Every other statement
*                    (SCREEN TEXT, BOX ...) writes what it is told, as before: a program may have printed over it.
*
* Everything the library draws goes through $sl_put, which writes this shadow as well as the terminal, so a
* pop-up can save what is under it and put it back.
*
$define SL.W.TYPE      1
$define SL.W.X         2
$define SL.W.Y         3
$define SL.W.W         4
$define SL.W.H         5
$define SL.W.FLAGS     6
$define SL.W.VALUE     7
$define SL.W.S1        8
$define SL.W.S2        9
$define SL.W.D        10

* The style codes, in the order of $sl_theme's list of names (a new style goes on the end of both)
* 22 Oct 26: the last sixteen (ACDEFHIJKLMNOQRS) are the USER styles user1 to user16, spare slots that $sl_theme('slot') hands to a control that asks for its own
* colours (the COLOR clause); a theme leaves them plain and keeps what a control put in them
$define SL.CODES       'nruxbwhasjkedytgcqovplzfimGPTBACDEFHIJKLMNOQRS'

$define SL.S.W         1
$define SL.S.H         2
$define SL.S.CLIP      3
$define SL.S.SHADOW    4
$define SL.S.RATTR     5
$define SL.S.ATTRS     6
$define SL.S.CUR       7
$define SL.S.CURON     8
$define SL.S.OWNED     9
$define SL.S.MOUSE     10
$define SL.S.BCLIP     11
$define SL.S.NARROW    12
$define SL.S.SYNC      13
$define SL.S.DIFF      14
*
* The answer of $sl_caption (where a control and its label go inside the widget's rectangle), one value to a field (22 Oct 26)
$define SL.CAP.W       1       ;* the width of the rectangle
$define SL.CAP.H       2       ;* its height: 1, or 2 when the label is above or below the control
$define SL.CAP.CX      3       ;* the column of the control, from the left of the rectangle
$define SL.CAP.CY      4       ;* the row of the control
$define SL.CAP.LX      5       ;* the column of the label
$define SL.CAP.LY      6       ;* the row of the label
