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
*   SL.S.RATTR       value r + 1 is 'R' if row r is in reverse video
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

$define SL.S.W         1
$define SL.S.H         2
$define SL.S.CLIP      3
$define SL.S.SHADOW    4
$define SL.S.RATTR     5
