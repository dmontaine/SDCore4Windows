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
$define SL.CODES       'nruxbwhasjkedytgcqovplzfimGPTB'

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
