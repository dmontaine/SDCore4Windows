# screen library (sl_), stage 2 first cut - design note

> **Windows port (18 Oct 2026).** This is Linux's design note at its commit bb0881d, carried as written. The screen library, the SCREEN
> statement, the debugger on the library and the removal of the AccuTerm, SDTerm and SDConsole support are in this tree (area 6a and
> 6c of the Linux carry). SED, CED and the IDE are NOT (area 6b, held until the S.64 edit guard exists), so the sections that describe
> them are for reference. Message ids: Linux id + 1005. The tests the note names (`sandbox-*.py`) drive a pseudo-terminal, which Python
> on Windows does not have; nothing here has been run yet.

12 Oct 2026; updated 13 Oct 2026 (see the 13 Oct sections). Written before the menu, kept to what SED needs plus the obvious next widgets.
Background: PROJECT_STATUS.md S.1 (stage 1: a pure BASIC renderer is fast enough).
First users: SED's menu bar and quit box. Tests: gplbld/sandbox-sed-menu.py.

## layers

1. keys - `$sl_key(timeout, name)`: ONE place that turns the terminal's key bytes into names (up
   down left right home end pgup pgdn ins del bs tab btab enter esc f1..f12 ctrl-a..ctrl-z, or the
   printable character). Built on KEYCODE(), so terminfo decides what a sequence means; a lone Esc
   is told from a sequence by KEYCODE()'s 0.2 s wait. Null = timeout or input ended. Mouse: SGR 1006
   reports reach KEYIN intact (S.1 stage 1). Since 12 Oct `_keycode` binds ESC [ < to K$MOUSE and `$sl_key`
   reads the rest into `$sl_mouse` and answers `mouse`. SED itself still reads raw bytes (its own binding tables) and only calls
   the library once a menu is open - see "not moved onto the library".
2. regions - `$sl_region(op, scr, x, y, w, h, saved)`: save what is under a rectangle, put it back.
3. theme - `$sl_attr(name, seq)`: the one table of attributes (normal, highlight, bar, hotkey,
   hotkey.end, frame, disabled). Only reverse video and underline, so it reads on a monochrome
   terminal; hotkey letters are underlined. A colour theme replaces this routine's table only.
   'disabled' is not different from normal on the mono theme (no dim); colour themes give it their own style (see the 13 Oct sections).
4. widgets - `$sl_menu` (menu bar + drop-downs with shortcuts), `$sl_msgbox`, `$sl_prompt`.

## the model we follow

Turbo Vision / Win-style widget records driven by one verb set, rather than newt's form/component
objects or ncurses panel/menu/form: SD BASIC has no objects across calls, and a dynamic array per
widget with one entry point per widget type maps onto that directly. From newt we take the
form-owns-focus-ring idea and the "run a form, get back which component ended it" result; from
ncurses-menu the item = label + description(shortcut) + user data shape (our `label @sm shortcut @sm code`).
Differences: no callbacks (BASIC cannot hand one in; a widget returns `unhandled` plus the key instead);
no separate window objects (the caller owns the screen, see "the hard fact").

## the widget contract

Every widget is `call $sl_<type>(op, w, scr, key, ret)`:

- `w` the widget record, one dynamic array, layout in `sl.h`: fields 1-9 common (type, x, y, w, h,
  flags, value, state 1, state 2), field 10 up the widget's own. The CALLER holds it between calls;
  all state is in `w`, so a form holds many by keeping them in an array of records.
- `scr` the screen context (sl.h): size, clip rectangle, `shadow` (text of every row) and `rattr`
  (reverse rows).
- ops: `init` (compute geometry/state from the fields the caller set), `draw`, `focus` (key = 1
  gain, 0 lose), `key` (feed one named key), `close` (undraw, restore what was under it), and, for
  modal use, `run` (draw + key loop + close).
- `key` answers in `ret<1>`: `handled`, `unhandled` (ret<2> = the key, passed back to the caller or
  the form), `done` (ret<2> = the value) or `cancel`. A widget never swallows a key it has no use for.
- form (later, `$sl_form`): holds widget records, a focus ring (Tab / Shift-Tab / arrows by position),
  default button (Enter on a non-button when no widget handled it), Esc = cancel; it feeds the key
  to the focused widget first, and only on `unhandled` moves focus or acts. Because a widget only
  knows `draw/focus/key/close`, a form needs no widget-specific code.
- end of input (null key) always cancels, so a dead terminal cannot loop.

## state: arguments and dynamic arrays, not COMMON or CLASS

State lives in `w` and is passed by reference. COMMON would make two widgets of one type
share state; a CLASS module (the compiler has them) would be the natural home for a form, but
instances are objects bound to one program, `$`-named catalogued routines cannot be called
from user programs yet, and every widget would need its own class. A dynamic array record is the
simplest thing that a form, a saved dialog definition or a test driver can all build. Revisit when
user programs can call library routines.

## the hard fact: the terminal cannot be read back

A drop-down covers text; closing it must restore it. SD cannot ask the terminal what is on it. So
the library never owns the screen: the CALLER hands in `scr` with the shadow (value r+1 = text of
terminal row r) and `rattr`. `$sl_region('save')` copies the rectangle from the shadow, `'restore'`
draws it back. Text and reverse video only; richer cells are repainted by the caller. (This is the
first cut's rule, for a caller of the `$sl_` routines. Since the `screen` statement the library owns the
shadow itself once `screen open` is done, with a style code on every cell - see the SCOPE part below;
the argument shape is the same.)

## layout and resize

Character cells, from 0, as in `@(x, y)`. `SL.S.CLIP` is the clip rectangle: `$sl_region` skips rows
outside the screen; `$sl_put` clips cell by cell to the screen and to `SL.S.CLIP` (SCREEN CLIP sets it; widgets are still sized to fit: a message box
is clamped to the screen width, a menu shifts left if it would overflow). Size comes from
@crtwide / @crthigh which the caller passes in `scr`. Resize is built (13 Oct 26, see "Resize" below): a
program that owns the screen gets a `resize` event; a caller of the `$sl_` routines re-reads the size,
rebuilds `scr` and sends every widget `init` then `draw`. The widgets hold nothing that depends on the
old size once re-initialised.

## widgets expected later, and how each fits

- label: `draw` only, never focusable.
- frame: `draw` a box with title; children are the form's, not the frame's.
- button: `draw` caption, `key` enter/space -> `done` with its code; hotkey letter from `&`.
- entry field: the `$sl_prompt` code with x/w and scroll state in S1/S2; masked variant by a flag.
- check box: `key` space toggles `value`, `handled`.
- radio group: values in the record; up/down change the selected, `value` is the selected index.
- pick (list) box: items as values, S1 = top, S2 = selected, `key` up/down/pgup/pgdn/home/end, enter -> `done`.
- drop-down (combo): entry field + a pick box opened over the text with `$sl_region`.
- status line: `draw` only, text in a field.
- progress bar: `draw` with value; no keys.
- scroll bar: built as a standalone widget on 13 Oct (see below); lists, memos and tables draw their own column with `$sl_scrollbar`.
- tab strip: like the menu bar with an always-open single level; `key` left/right -> `handled`, the form shows the page.
- message / confirm box and input prompt: exist now (`$sl_msgbox`, `$sl_prompt`).

## what SED could not move onto the library

SED's text area, its status lines and its own prompt line (`get.string`, with history, kill and
Emacs line editing driven by SED's key bindings) stay SED's: they need SED's binding tables and
SED's image buffer, which the library does not know. SED reads raw bytes with its own tables
(the library's `$sl_key` would have to learn SED's rebindable keys). SED feeds the library a shadow
of its image buffer for its menus. Since 13 Oct SED's syntax colour comes from the library's engine
(`$sl_syntax`: one style code per character of each row), but SED still draws its own rows.

`ced_edit` and the debugger were left on their own drawing code in the first cut and are on the
library since 13 Oct 26 (owner: "use the TUI on ced and debugger"): the element list of `ced_edit` is
a table widget and its questions are dialogues; the debugger draws with the library's styles and
`$sl_put`, its help is `$sl_msgbox`, and its full screen is the terminal's alternate screen.

## not done yet (deliberately)

(Written for the first cut and brought up to date 13 Oct 26. Built since: mouse, colour, the form, borders, menu
flags, submenus, the tree, the standalone scroll bar, per-cell clipping (`$sl_put` always cut at the screen's edge;
`SCREEN CLIP AT x,y SIZE w,h` sets `SL.S.CLIP`, `SCREEN CLIP` alone takes it off), resize, `ced_edit` and the
debugger on the library, and a library-owned shadow once `screen open` is done.) Still not built, each one by choice:
scrolling drop-downs longer than the screen; SED's own text area and prompt line on the library; the editor widget as a
separate widget (the memo covers its functions); a shadow that also holds what `print` and `crt` write (the shadow is
the library's only). The evaluation of each is in "Revisited 13 Oct 26" at the end. User programs calling `$sl_`
routines need `$internal` and `sd -internal` to compile: settled by the `screen` statement, see SCOPE below. F10 is
bound by SED's table from `ESC [ 2 1 ~` (xterm, Linux console), not read from terminfo.

## evaluation: a C library as a back end (decision: NO, stay with BASIC over tio)

Evidence by looking on this machine (Ubuntu): installed runtime packages libncurses6/libncursesw6 6.6,
libnewt0.52 0.52.25, libslang2 2.3.3; NO `-dev` headers for any, no pkg-config, none of libtickit,
notcurses, termbox2 installed. Licences below are FROM MEMORY except where noted; none checked from a
licence file here (no source trees present).

| library | licence (memory) | combinable with GPL v3? | model |
|---|---|---|---|
| ncurses / panel / menu / form | X11/MIT-style | yes | owns the screen (curscr) |
| newt (Red Hat) | LGPL-2 (v2 only?) | LGPL-2.0 linking into GPLv3: needs a second look, newt's file headers say "GPL"/"LGPL v2" - check | owns terminal, uses slang |
| slang | GPL-2-or-later (or Artistic) | yes (2+) | owns terminal |
| libtickit | MIT | yes | owns terminal, event loop |
| libtickit-widgets | MIT (memory; small, may not be packaged) | yes | tickit window tree |
| notcurses | Apache-2.0 | Apache-2 is GPL-3 compatible, not GPL-2 | owns terminal, heavy |
| termbox2 | MIT | yes | cell buffer + event, owns the tty |

Flag for a second look: newt (LGPL-2.x, version clause not confirmed from a file); everything else
combines with GPLv3 on the memory above.

**Who owns the terminal.** SD already does: its terminfo compiler (`sdtic`, terminfo/), tio output
layer (`tio_printf`, `@(IT$...)` codes), raw mode in `linuxio.c`, and a ring buffer fed by
`do_input()` on SIGIO. (An earlier version of this note also named SIGWINCH here. That was wrong, found
12 Oct 26: nothing in `gplsrc` reads the window size or catches SIGWINCH - see "resize" under SCOPE.) newt, tickit, ncurses and notcurses initialise the tty themselves (termios, alternate
screen, their own input read, own idea of cursor position and attributes). Running them beside tio
means two writers and two readers on one fd: cursor/attribute tracking in tio goes wrong, and input
bytes could be eaten by the library while SD's ring buffer holds them. A safe integration would
have to be: (a) hand the tty to the library only for a modal call, then restore tio's modes and
force a full repaint (the editor's image buffer is lost anyway), after draining SD's ring buffer
so no typeahead is stolen; or (b) render into an offscreen buffer (notcurses/termbox2 can) and have
SD write it out - not what those libraries are built for; or (c) use only the key parser. Only (c)
is cheap, and `keycode()` already does it with SD's own terminfo. It also has to work with phantoms and
the API server (no tty at all: the library would fail at init; BASIC code just prints), ssh sessions
(works, the tty is the pty), TERM values SD's terminfo does not know (SD uses its own tree
`terminfo/`; a C library would use the system's - the two may disagree) and `sd -internal`.

**Packaging.** `installsdcore.sh` builds from source and today installs `libsodium-dev libssl-dev
python3-dev` (Debian/Ubuntu apt line 438; Fedora dnf line 450). A C back end adds a -dev package to
that list: Debian/Ubuntu `libncurses-dev` | `libnewt-dev` | `libtickit-dev` (Debian has libtickit 0.4;
not in Ubuntu main to my memory) | `libnotcurses-dev` | `libtermbox2-dev`; Fedora `ncurses-devel` |
`newt-devel` | `libtickit-devel` (not in Fedora to my memory) | `notcurses-devel` | `termbox2-devel`.
Exact change if the owner ever wants it: append the package to both package lists, add `-l<lib>`
to the Makefile `L_FLAGS`, and a build-time check. I did NOT edit any of these.

**Exposing it to BASIC.** `op_sdext.c` (opcode OP_SDEXT 0xCFFF, `gplsrc/opcodes.h:618`) is the
existing thin-C hook (`sdext_py.c`, `sdext_eguid.c`): one subroutine entry taking a command string
and arguments, so a library would be one `SDEXT`-style entry `sl_c(cmd, args, result)` - no new
opcode, which is good because the opcode slots are full. The widget set would be a thin command layer
on top.

**Plain BASIC over tio.** No dependency, the S.1 stage 1 measurement says a full repaint of 160x48
is 0.11 ms of CPU, the widgets here are ~200 lines each, and BASIC code works in a phantom (it just
does not draw). The cost is that we write and maintain each widget ourselves.

**Recommendation:** stay with BASIC over tio (as built). A C library earns its place only if the tty
conflict is solved, and every honest solution (a modal hand-over) discards what tio knows and ties
SD to the system's terminfo. Main risk of this recommendation: the amount of BASIC to write for the
later widgets (list box, text field with history, forms) and its speed when a form redraws; the
mitigation is the S.1 diff renderer behind the same `scr` argument. No prototype of a C route was
built.

---

# SCOPE: the whole library as BASIC commands (12 Oct 2026, second sitting)

Everything above is the first cut (SED's needs). This part scopes the rest.

**Built and tested (`sandbox-screen.py`, through user programs on the pty):** the compiler mechanism and
the verbs `msgbox open close clear text box cursor refresh size key menu menubar pick ask` (stages 0 to 2);
`test-screencmd-units.py` checks the verb table, the routines and their headers agree. Stages 0 to 4 are
built, and the 13 Oct additions (memo editing, menu flags and submenus, borders, tree, standalone scroll
bar, table sorting and row marks) are built and tested in `sandbox-screen.py`; none is merged to Dev yet. Everything marked "proposed" is written in the conditional, with what would falsify it.

## owner rulings this rests on

- A full form toolkit: buttons, entry fields, radio buttons, check boxes, pick lists, and the rest.
- Exposed to end users as BASIC commands, not as `call $sl_x`: a user program (not `sd -internal`)
  draws a menu, a message box, an entry field with BASIC. All 512 opcode slots are used, so the compiler
  turns a statement into a CALL of a catalogued subroutine (no opcode).
- Open source only; no new dependency without the owner; BASIC over SD's own tio, no C library (above).
  English only, lower case everywhere SD writes a command word, GPL v3.

## the shape: one statement, a table of verbs

```
screen <verb> {value {, value}} {KEYWORD value {, value}} ... {returning <variable>} {then ... else ...}
```

- ONE new statement word, `screen`. The verbs and keywords are rows of a table in bcomp, not
  reserved words, so a program that uses `menu`, `form`, `title`, `buttons` as variables is unaffected,
  and the only name taken from the program's namespace is `screen`, which a program can still use as a
  variable (tested: `screen = 5`, `screen<2> = 'a'`, `title title` as keyword and variable).
- Positional values come first (the object: a text, a form, a list), keyword clauses follow in ANY
  order, each keyword with a fixed number of values (`at x,y`, `size w,h`, `title t`). A keyword left
  out is passed as null: the subroutine decides its default.
- `returning v` receives the answer. `then` is taken when the user finished normally (a button, a
  choice, Return), `else` when not (Esc, the end of the input, no terminal at all - a phantom or the
  API). Both optional: `screen msgbox 'Done.'` is a statement on its own.
- One verb = one catalogued subroutine `!screen_<verb>(positionals, keyword values in table order,
  ret, status)`. That is also the call a program can write by hand.
- Statements, not functions, because a command has many optional parts and two results (the answer
  and whether the user finished or cancelled). A function (`screenkey(2)`) fits only the one-value
  reads; if wanted they are DEFFUN-style calls through the same table (the compiler already compiles
  user functions as a CALL with a hidden return argument), a later item, not needed to start.

## the screen: owned by the library once `screen open` is done

The first cut leaves the shadow (the text the terminal shows) to the caller, because SED owns its image
buffer. A user program cannot be asked to build one, so the commands keep it in a COMMON block
(`$sl_scr`): width, height, one text string and one attribute string per row, the cursor, the clip.

- `screen open` takes the screen (optionally clears it, hides the cursor); `screen close` gives it back.
  Until `open`, a dialogue is TRANSIENT: it works, but has no text to put back under itself, so it puts
  back blanks (tested, documented, not a defect) and leaves the cursor at its last cell. Text the
  program wants kept under a dialogue is drawn with `screen text`, which records it.
- Every library draw goes through one routine (`$sl_put`) that writes the shadow and the terminal, with
  per-cell attributes (n normal, r reverse, u underline, b bold, h highlight, then colour pairs), so a
  pop-up saves "what is under me" from the shadow and a form needs no repaint code of its own. S.1
  measured the diff renderer: a full 160x48 repaint is 0.11 ms of CPU in BASIC.
- The program's own `print @(x,y)` is not in the shadow (curses has the same rule); `screen refresh`
  repaints from the shadow after it. The kernel's `SAVE.SCREEN` / `RESTORE.SCREEN` do nothing (since
  13 Oct 26 on any terminal: they asked the terminal to keep the picture, which only AccuTerm and SDTerm
  could, and both are no longer supported); the debugger uses the terminal's alternate screen and the
  library's own shadow instead.
- Existing widgets (`$sl_menu`, `$sl_msgbox`, `$sl_prompt`) draw with `display`; moving them to `$sl_put`
  is stage 1. SED keeps handing its own shadow in, so it does not change.

## the vocabulary (proposed; `built` marks the one that exists)

**A form is a data collection** (decided 12 Oct while building stage 3, replacing the first idea of a
dynamic array passed by reference). A collection is one reference-counted object however many variables
hold it (`d = c` shares, `COLLECTION(c)` copies, and a subroutine given one changes the caller's), so
`screen form ... returning f` makes it and every later verb takes `f` BY VALUE and changes the program's
form with nothing handed back: no by-reference positional is needed in the compiler. A widget is a
collection inside the form's `widgets` array (`f{'widgets', 3}{'value'}`), elements named in lower case
(`type id x y w h value text items ...`); JBUILD writes a whole form out as JSON, JPARSE reads it back,
so a screen can be kept as a record. The first widgets (menu, msgbox, SED's prompt) stay dynamic arrays:
they are modal dialogues, not members of a form. Both obey the one contract
`call $sl_x(op, w, scr, key, ret)`; the type of `w` is the widget's own.

| verb | form | answer (`returning`) | routine |
|---|---|---|---|
| `open` | `screen open {clear} {nocursor} {minsize w,h}` | - ; else when no terminal or too small | `!screen_open` |
| `close` | `screen close` | - | `!screen_close` |
| `clear` | `screen clear {at x,y} {size w,h} {attr a}` | - | `!screen_clear` |
| `text` | `screen text s at x,y {attr a} {width n}` | - | `!screen_text` |
| `box` | `screen box at x,y size w,h {title t} {style s} {attr a} {fill}` | - | `!screen_box` |
| `cursor` | `screen cursor {at x,y} {on \| off}` | - | `!screen_cursor` |
| `refresh` | `screen refresh` | - | `!screen_refresh` |
| `size` | `screen size` | width @fm height | `!screen_size` |
| `key` | `screen key {timeout s}` | key name; else on timeout / end of input | `!screen_key` |
| `msgbox` | `screen msgbox text {title t} {buttons b} {default n} {at x,y}` | button number (0 = Esc) | `!screen_msgbox` |
| `menu` | `screen menu items {at x,y} {default n}` | item code; else on Esc | `!screen_menu` |
| `menubar` | `screen menubar menus {row r} {draw}` | item code of the chosen entry | `!screen_menubar` |
| `pick` | `screen pick items {title t} {at x,y} {size w,h} {default n} {multi}` | index (or list of indexes) | `!screen_pick` |
| `ask` | `screen ask prompt {value v} {width n} {title t} {at x,y} {mask}` | the text; else on Esc | `!screen_ask` |
| `form` | `screen form {title t} {at x,y} {size w,h} returning f` | the new form (a collection) | `!screen_form` |
| `label` | `screen label f, id, text at x,y {attr a}` | - | `!screen_label` |
| `frame` | `screen frame f, id at x,y size w,h {title t}` | - | `!screen_frame` |
| `entry` | `screen entry f, id at x,y width n {value v} {mask} {maxlen n}` | - | `!screen_entry` |
| `check` | `screen check f, id, text at x,y {value 0\|1}` | - | `!screen_check` |
| `radio` | `screen radio f, id, items at x,y {value n} {across}` | - | `!screen_radio` |
| `list` | `screen list f, id, items at x,y size w,h {value n} {multi}` | - | `!screen_list` |
| `combo` | `screen combo f, id, items at x,y width n {value v}` | - | `!screen_combo` |
| `button` | `screen button f, id, text at x,y {default} {cancel}` | - | `!screen_button` |
| `status` | `screen status f, id, text` | - | `!screen_status` |
| `progress` | `screen progress f, id at x,y width n {value n}` | - | `!screen_progress` |
| `run` | `screen run f` | id of the button that ended it; else on Esc or a cancel button | `!screen_run` |
| `values` | `screen values f` | a collection id -> value of every entry, check, radio and list | `!screen_values` |
| `wait` | `screen wait f {timeout s}` | event: type @vm id @vm data; else on timeout | `!screen_wait` |
| `get` | `screen get f, id` | the widget's value | `!screen_get` |
| `set` | `screen set f, id {value v} {text t} {items i} {enabled b} {readonly b} {visible b}` | - | `!screen_set` |
| `focus` | `screen focus f, id` | - | `!screen_focus` |
| `theme` | `screen theme name` | the name of the theme in force; else when refused | `!screen_theme` |
| `style` | `screen style name, fg, bg, flags` | - ; else when refused | `!screen_style` |
| `tabs` | `screen tabs f, id, labels at x,y {value n}` | - | `!screen_tabs` |
| `page` | `screen page f, n` | - | `!screen_page` |
| `memo` | `screen memo f, id, text at x,y size w,h {readonly} {wrap}` | - | `!screen_memo` |
| `table` | `screen table f, id, columns, rows at x,y size w,h {value n}` | - | `!screen_table` |
| `tree` | `screen tree f, id, nodes {at x,y} {size w,h} {value n} {expanded}` | - | `!screen_tree` |
| `scrollbar` | `screen scrollbar f, id, total {at x,y} {size w,h} {visible} {value n}` | - | `!screen_scrollbar` |

A zero-value keyword (`fill`, `multi`, `mask`, `on`) is a flag: the subroutine is given 1, else null.
`items` are values (or a comma list, as `buttons` already is); a menu item is label @sm shortcut @sm
code, as `$sl_menu` takes it today. `attr` names an attribute (`'reverse'`, `'bold'`, later colours).

`run` is the simple modal form; `wait` is the event-loop form for a program that must react between key
strokes (validate on leaving a field, fill one list from another) without callbacks - BASIC cannot hand
one in. The program loops: `screen wait f returning ev` then `begin case` on the event type
(`button`, `change`, `select`, `key`, `timeout`) and the widget id.

Stage 4's `wait`, as designed (proposed): the first call shows the form (what is under it is saved) and it
STAYS on the screen between calls; each call returns one event in `ev` (field 1 the type, 2 the widget id,
3 its data) and the program acts on it. THEN for an event the form produced - `button` (id), `change`
(id, value: a check box, radio group or list changed), `focus` (the new id, the one before) and `key` (a
key the form had no use for: a function key, a Ctrl key); ELSE for `cancel` (Esc: the form does not close
by itself here, the program decides), `timeout` and `end` (the input ended). `screen set` redraws a widget
of a form that is shown, and `screen hide f` puts the screen back. An entry reports no event for each key
typed (that would wake the program per character): the program asks for the text with `get` on a `focus`
or `button` event.

## a complete example (25 lines, proposed)

```
   screen open clear else crt 'This needs a terminal.' ; stop
   cities = 'Albany':@vm:'Boston':@vm:'Chicago':@vm:'Denver'
   screen form title 'Customer' at 10,3 size 56,16 returning f
   screen label  f, 'l1', 'Name:'          at 2,2
   screen entry  f, 'name'                 at 12,2 width 30 value 'Smith'
   screen check  f, 'vip', '&VIP customer' at 12,4 value 1
   screen label  f, 'l2', 'Type:'          at 2,6
   screen radio  f, 'kind', 'Retail':@vm:'Wholesale':@vm:'Staff' at 12,6 value 2
   screen label  f, 'l3', 'City:'          at 2,10
   screen list   f, 'city', cities         at 12,10 size 20,4
   screen button f, 'ok',     '&OK'        at 18,14 default
   screen button f, 'cancel', '&Cancel'    at 28,14 cancel
   loop
      screen run f returning pressed else exit       ;* Esc or the Cancel button
      screen get f, 'name' returning name
      if name = '' then
         screen msgbox 'The name is required.' title 'Customer'
         screen focus f, 'name'
         continue                                    ;* the form is run again with what was typed
      end
      screen get f, 'vip'  returning vip
      screen get f, 'kind' returning kind
      screen get f, 'city' returning city
      gosub save.customer
      exit
   repeat
   screen close
```

## naming and protecting existing programs

- `screen` is the only new statement word (not in `statements`, `restricted.statements`, the intrinsic
  tables or `reserved.names`; nothing in gpl.bp or syscom uses it as a statement). A statement is
  recognised only where `proc.statement` already decides "statement" (`bcomp` "proc.statement"): a NAME
  followed by a NAME decides it at once, and any look-ahead that is not an assignment token falls through
  to the statement table. `screen = ...`, `screen<n> = ...`, `screen[n,m] = ...`, `screen := ...`,
  `screen += ...` and `screen(n) = ...` are assignments by the existing look-ahead, so a program that has
  a variable called `screen` compiles as before (tested for `=` and `<n> =`). Before this change
  `screen 'x'` was a compile error, so no working program changes meaning.
- Keywords (`title`, `at`, `size`, `buttons`, `default`, `returning` ...) live in the verb's row, not in
  the global tables. While a `screen` statement is being compiled they are added to `reserved.names<2>`
  (as `execute` does for `capturing`, `returning`), so an expression stops before them. A program's own
  variable of the same name still works as a value (`title title`, tested).
- Verb names are lower case in the table's output, the compile messages (12172-12175) and the docs.

## the compiler mechanism (built; `st.screen` in `gpl.bp/bcomp`)

1. `SCREEN` is added to `statements` and `st.screen` to the `on i gosub` list, in step (both lists are
   alphabetical by convention and the position must match).
2. `screen.names` / `screen.defs` (top of bcomp): the verb, the catalogued subroutine
   (`!screen_msgbox`), the number of positional values, and the keyword list `TITLE:1`, `BUTTONS:1` ...
   (value counts). A verb is a row; no code per verb.
3. `st.screen` pushes the call target with `emit.direct.call.reference` (the call `st.call` uses), the
   positional values with `expr` + `OP.VALUE`, then each keyword clause: the value goes into a hidden
   variable `__300 + slot` (`emit.temp.ref`, `expr`, `OP.STOR`), so the clauses may be written in any
   order. It then loads the slots in table order (the hidden variable, or `OP.LDNULL` if the clause was not
   written), the `returning` variable (`simple.lvar.reference`, or hidden `__398`), the status
   (hidden `__399`), `OP.CALL n`, and pushes `__399` for `back.end`.
4. THEN / ELSE: `back.end` with `opcode = -1`, `thenelse.stack = 2` (optional): THEN on status 0, ELSE
   on non-zero, the same machinery as `read`; with neither clause it pops the status.
5. The subroutine is a `$internal` source catalogued `!screen_<verb>` (the pattern of `ced_sub` /
   `!ced`), so a user program can call it and it can call `$sl_*` itself. The bootstrap compiles every
   file in `gpl.bp`: no VOC entry, no registration.
6. Traps met: `opcode` and `j.index` are overwritten by a nested statement (as for `while`/`until`, not
   hit here: the clause values are expressions); the hidden variables must be set before the CALL
   argument load (done: they are stored as the clauses are parsed); `err` after `expr` must return
   (done); a message added for the compile errors needs a file in `sdsys/messages` (12172-12175); the
   statement table must not be sorted by hand, only extended in step; `bbcmp.py` (the bootstrap compiler
   for the `_*` pcode routines) is NOT involved - it never sees a user statement.
7. Added in stage 1: flags (`KEYWORD:F` in the table: no value follows, the subroutine is given 1) and
   `test-screencmd-units.py` (the table, each routine's argument list and `$catalog` line, and the
   statement form in its header agree; `--selftest` changes a copy five ways). Not needed after all: a
   positional passed BY REFERENCE (a form is a collection, shared). Not built: a keyword that takes a
   word list (`style single`); `at` as a pair that may be left out (the null pair is passed, and the
   routine decides).

## spike result

`sandbox-screen.py`, 25 rows, all green on a fresh sandbox build (bootstrap compiled every program with
no errors): the statement compiles in a plain (non-internal) session; the box is drawn with title, text
and two buttons from a comma list, DEFAULT 2 puts the reverse video on the second; Return gives THEN with
2, `y` THEN with 1, Esc ELSE with 0; the clauses written in the other order and with `@vm` buttons give
the same box; with no clauses the next statement runs; a field mark ends a line; variables named
`screen`, `title`, `buttons`, `default`, `returning` still work and are not changed by the call; four
compile errors are refused with their messages. Cost: about 130 lines in bcomp (of which the table is
10), one 40-line routine, no opcode, no kernel change.

## staged plan (riskiest first; estimates are mine, small < medium < large)

| stage | what | size | test (through a USER program, on the pty) |
|---|---|---|---|
| 0 | compiler mechanism + `msgbox` - DONE | small | `sandbox-screen.py` 25 rows |
| 1 | the owned screen: `$sl_put` with per-cell attributes, `open`/`close`/`clear`/`text`/`box`/`cursor`/`refresh`/`size`/`key`; move msgbox, menu and prompt onto it; the cursor rule - DONE | medium | text drawn, a dialogue over it, the text back row for row and attribute for attribute; cursor (61 rows) |
| 2 | modal dialogues: `menu`, `menubar`, `pick`, `ask`, `msgbox at` - DONE | medium | each verb: choose, cancel, keys, background restored cell for cell (106 rows with stage 1; ten mutants, see PROJECT_STATUS) |
| 3 | the form (a collection) and its container; label, frame, entry, check, radio, list, button; focus ring; `run`, `get`, `set`, `focus`, `values` - DONE | large | the 25-line program above, field by field; Tab / Shift-Tab; default and cancel buttons |
| 4 | `wait` (events), `combo`, tabs, scroll bar, status line, progress - DONE (tabs and the scroll bar painter 12 Oct, third sitting; the standalone scroll bar widget 13 Oct) | medium | event order; a combo over a form; scrolling lists |
| 5 | colour themes - DONE; mouse - DONE (xterm SGR 1006; `_keycode` binds ESC [ <); resize - DONE 13 Oct (the kernel reads the window size; see "Resize" above) | medium | attributes; clicks; a resized pty |
| 6 | text area and viewer (`memo`, with selection, undo and find: 13 Oct), `table` (sorting, row marks, column resize, sideways scroll: 13 Oct), `tree` (13 Oct) - DONE; `ced_edit` and the debugger on the library - DONE 13 Oct (`sandbox-ced.py` 134, `sandbox-dbgui.py` 21); an editor widget as a separate widget - not built | large | the editors' existing suites (`sandbox-ced.py`) |
| 7 | carry to Solo (bcomp, the library, 12172-12175), then the Windows agent when Core is declared stable | small each | their own suites |

What would falsify the plan: (a) stage 1's per-cell shadow making a BASIC repaint slower than ~16 ms at
160x48 with colour (S.1 measured monochrome rows only); (b) collection reads and writes (about thirty a
key at a form's widest) being too slow for a key to feel instant - measure it at stage 3 with the 25-line
form; (c) the focus ring needing a widget to see keys before its parent, which the `unhandled` convention
cannot express (the first worker's own doubt).

## themes, tabs, the text area, the table (12 Oct 26, third sitting; built unless it says otherwise)

**Themes.** A widget names a STYLE and never a colour. Every cell of the shadow keeps the one-character code
of its style (`SL.CODES` in `sl.h`, 16 of them: the raw `n r u x` and the named `b w h a s k j e d y t g` - bold, window,
highlight, bar, barsel, hotkey, hotkey.bar, field, disabled, desktop, text, header). A THEME (`$sl_theme`) says what
each code looks like: a foreground, a background and any of bold, dim, reverse, underline. The codes do not change
with the theme, so a theme can be switched with a screen on the glass and the screen repainted from the shadow.
`mono` is the default and looks exactly as the library did before (reverse video and underline only: it reads on any
terminal, and it is all SED ever uses); `classic` and `blue` use colour. `screen theme name` chooses one (ELSE when
the terminal has no `setf`/`setb`, when there is no terminal, or when there is no such theme), `screen style name, fg, bg,
flags` changes one style of the theme in force, `screen close` puts the theme back to mono. Colour goes through SD's own
`@(-37, n)` / `@(-38, n)` (terminfo `setf`/`setb`, the Pick colour order black blue green cyan red magenta brown
white): eight colours, bold for bright, because xterm's `setf` is right for 0-7 only.
- *Found 12 Oct:* the shipped `linux` and `ansi` terminfo entries had `setaf`/`setab` but no `setf`/`setb`, so
  `@(-37)` printed nothing on the entry that every `xterm-256color` session falls back to (login). `terminfo.src`
  now carries xterm's mapping in both. `TERM COLOUR` therefore works there too (a visible change: changelog).
- *The bottom right cell* is written like any other where the terminal has `xenl` (xterm, linux, vt100) and left
  alone where it scrolls when it is written (`ansi`): one cell of the desktop colour is missing there.
- *Objections raised in the sitting and how they were settled.* (1) "A palette in the widgets would tie them to
  colours": they name styles. (2) "Colour should be the default on a terminal that has it": NOT settled - the default
  stays `mono`, so nothing changes for a program that never asks; a site-wide default chosen by the administrator
  is the owner's question (below). (3) "The colour numbers differ from ANSI": the API has names only.

**Tabs and pages.** `screen tabs` is a strip (`[General] Address  Notes `); the chosen tab is the PAGE the form shows.
`screen page f, n` is a cursor, not a keyword on every widget: the widgets added after it belong to page n, `screen page
f, 0` ends it. A widget on another page is not drawn, cannot have the focus and takes no key, but still answers `get`, `set`
and `values`. No form without a strip is affected. A strip gives a `change` event in `screen wait`. *What would
falsify it:* a form with two strips (the first one wins); pages inside pages (not supported).

**The text area.** `screen memo` is one widget for both an editor and a viewer (`readonly`): lines are fields of
the value, no wrapping (it pans sideways), the last column is a scroll bar, Page Up/Down scroll a page less a line with
the cursor keeping its screen row. Built 13 Oct: `wrap` (SCREEN MEMO ... WRAP; SCREEN SET ... WRAP b) wraps long lines at the width.
Selection (Ctrl-G marks, Ctrl-X cut, Ctrl-C or Ctrl-O copy, Ctrl-V paste; the clipboard is shared between
memos), undo and redo (Ctrl-Z, Ctrl-Y; 100 steps, a run of typing is one step), find (Ctrl-F or Ctrl-T prompts,
Ctrl-B prompts and finds backwards, Ctrl-N finds the next; ignores case; wraps) and word movement (Ctrl-P back,
Ctrl-U on: Ctrl-B and Ctrl-F were these until 14 Oct 26, when they became SED's find keys). A readonly viewer can
select, copy and find. `SYNTAX name` colours the text as a language of `$sl_syntax` (the theme's syntax styles; `dark`, `light`,
`classic` and `blue` have them, `mono` none) and `LNUM` puts line numbers down the left (13 Oct, later the same day; `part_memo3`).
Still not built: a separate editor widget (`ced_edit` is on the library since 13 Oct, as a table and dialogues, not as a memo).

**The scroll bar** is a routine (`$sl_scrollbar`) that returns the column of characters for a list, memo or table;
the thumb is proportional (it was one cell). The standalone scroll bar widget is built 13 Oct (`screen scrollbar`): vertical or horizontal,
keys, mouse, `change` events.

**The table** (`screen table f, id, columns, rows`): a heading row, columns with a width and L/R/C, one current row, a
scroll bar; `change` events as for a list. Built 13 Oct: F3 sorts by the current column (up, down, natural order; numbers by value) and a click on a
heading sorts; MULTI (space marks rows, `*` shows them; GET and Return give the original row numbers);
Left and Right choose the column and scroll sideways; `<` and `>` narrow and widen the current column.

**The mouse (built, xterm only).** `screen open` asks for modes 1000, 1002 and 1006 (buttons, drag, wheel, SGR form;
`nomouse` opts out) and `screen close` turns them off; a terminal that does not know them, the Linux console, ignores
the request. Before this `_keycode` rang the bell on `ESC [ <`, found no key that began with it and left `0;12;5M` as typed
text, so it binds `ESC [ <` to `K$MOUSE` (a shared kernel key number, already allocated; no new one). `$sl_key` reads the
rest and answers `mouse`; `$sl_mouse` holds the event (kind, button, x, y, mods). A form finds the LAST ADDED visible
focusable widget under the pointer (it is drawn on top), gives it the focus, and sends op `mouse`; each widget decides
(`unhandled` / `handled` / `done`, as for a key), so the form needs no widget-specific code beyond the hit test. Only the
press of the left button and the wheel act. *Settled in the build:* a click on a list or table row selects it and a second
click on the same row is Return (no timing: BASIC has no clock finer than a second); dialogues that run their own loops
(message box, menu, pick, ask, a combo's open list) take clicks in those loops; a click outside a menu, pick list or open
combo list cancels it, outside a form or an input box it is ignored. *Objection raised and not resolved:* a program that
dies with reporting on (break, error) leaves the terminal reporting, and the mouse then types at the prompt; the kernel
sends no mode reset when a program ends (it never sends `smkx` / `rmkx` either). The proper fix is a kernel hook, which is
the owner's to ask for; the documentation says what to do (`reset`).

**Resize - BUILT 13 Oct 26 as option (B), on the owner's "B. is fine, do it".** What follows is the analysis that led to
it, kept for the reasons: before it, SD never read the window size - there was no `TIOCGWINSZ` or `SIGWINCH` anywhere in
`gplsrc`, and `@crtwide` / `@crthigh` were terminfo's 120 x 36 unless `TERM w,h` was typed or `LOGIN` found `COLUMNS` /
`LINES` in the environment. Now the kernel reads the pty's size at start-up and in the SIGWINCH handler (`linuxio.c`,
`op_tio.c` `tio_check_resize`), kernel key 92 (`K$WINSIZE`) returns it, `LOGIN` prefers it to terminfo's default, the
library's `$sl_key` reports `resize`, and `screen wait` gives a `resize` event. Options considered, in the order I
would have taken them, all conditional:
(B) the kernel reads the pty's size at start-up and on SIGWINCH into the display size, and `LOGIN` prefers it to terminfo's
default: right for every session, but `@crtwide` changes for all of them, so it is a behaviour change to be agreed;
(C) the same read, but only through a `SYSTEM()` / `KERNEL()` key that the library calls from `screen open` and `screen key`,
and SIGWINCH only sets a flag: nothing else changes, at the price that only library programs see the real size;
(A) no kernel change and the library asks nothing: a program keeps using `TERM w,h`. Falsified if the owner wants
`@crtwide` left at terminfo's value for compatibility with scripts - then (C) is the only one left.

## 13 Oct 26 additions (built and tested in `sandbox-screen.py`; merged to Dev 13 Oct, `2ca25c7`)

**Menus.** An item carries flags in subvalue 4: `D` disabled (drawn in the style `bar.disabled`, skipped by the
cursor), `C` checked (a `*` in the first cell). A submenu is a menu whose title begins with `>` and is not on the
bar; an item whose code is that title opens it beside the item. Three levels deep. New theme style `bar.disabled`
(code `m`).

**Tree.** `screen tree f, id, nodes {at x,y} {size w,h} {value n} {expanded}`. A node is a label, a depth
(subvalue) and a code (subvalue). Right and Left open and close a node or move to a child or parent; space toggles;
a letter jumps; Return gives a `done` event; `change` events as for a list.

**Scroll bar.** `screen scrollbar f, id, total {at x,y} {size w,h} {visible} {value n}`. Vertical or horizontal;
keys, mouse, `change` events.

**Borders.** `screen open ... lines` draws forms, boxes and dialogues with Unicode line-drawing characters. The
stand-ins CHAR(14) to CHAR(19) from `$sl_line` are turned into the terminal's bytes by `$sl_put`. Otherwise plain
`+ - |`. Reset by `screen close` and by the clean-up routine.

## risks and open questions for the owner

1. **The statement word.** `screen` (proposed) versus a name of its own such as `tui`, or one word per
   widget (`msgbox`, `menu`, `form` ...). One word keeps the namespace clean and the grammar regular
   (a table row per verb); several words read shorter.
2. **Library-owned screen.** The library keeps the shadow once `screen open` is done; before that a
   dialogue puts back blanks. The alternative is for every dialogue to open the screen implicitly,
   which would erase the program's output on the first call.
3. **Forms as statements that build a collection** (decided in the build, 12 Oct) rather than a dynamic
   array: a collection is shared by reference, so no compiler support for by-reference values was
   needed, and JBUILD / JPARSE give a stored screen definition for nothing. A form built from a JSON record
   instead of statements (`f = jparse(record)`) then works as it stands, once the widgets' elements are
   documented; open: do you want that documented as a feature?
4. **`ask` or `input`.** `screen input` would clash in the reader's mind with `input`; `ask` is not an SD
   word. Open.
5. Phantom / API sessions: every verb answers ELSE (status 1) and draws nothing; an `open` in a phantom
   takes the else branch. Tested by `sandbox-screen.py` on 13 Oct (see the decisions below).
6. Cursor after a transient dialogue: nothing in SD reads the cursor position, so it is left at the
   box's last cell. After `open` the library owns it. A save/restore pair from terminfo (`sc`/`rc`) is
   possible for terminals that have it - not proposed.
7. Carry-over: the statement is compiled by `bcomp`, so Solo and Windows get it with the compiler;
   message numbers 12172-12175 are Linux's range; here they are 12172-12175 (Linux id + 1005). Nothing is sent
   to them until the owner declares Core stable (the standing order).
8. **Resize.** SD never reads the window size (see the section above). Which of (A), (B), (C) - or none yet? (B) changes
   `@crtwide` for every session, which is why it is yours to say.
9. **A default theme.** A program that never calls `screen theme` gets `mono`. Should an administrator be able to set
   another default for the site (a setting in `sd.conf` or a VOC record) so that colour terminals get colour without
   every program asking? Not proposed until you say.

## Decisions taken 13 Oct 2026 on the open questions

Taken by the agent under the owner's instruction to decide what gives the product the most depth. Each is open
to the owner's veto.

(a) The statement word stays `screen`.
(b) The owned screen stays explicit (`screen open`); a dialogue before it puts back blanks.
(c) Forms are collections built by statements. A form made from a JSON record with `jparse` works, and is a
documented feature once the widgets' elements are listed (they are in each widget's header comment).
(d) The prompt dialogue stays `ask`.
(e) Phantom and API sessions answer ELSE and draw nothing (tested by the suite).

## Revisited 13 Oct 26: the things left unbuilt "by choice"

Asked: would any of them give users more function or a better experience? Two probes were run on a sandbox built
from `6a2cb02` plus the doc edits (`probe-sed-small.py`, a pty at 100 columns; the output is in the session's
scratchpad, not kept in the tree): SED on 24, 14 and 12 rows (12 is the least SED accepts), F10 then the Edit and
Tools menus, and SED on a 24-row pty that is then resized to 40 rows and to 14. What each result means, best first.

**The owner's answers, the same day:** 1 fix; 2 "sed should have a default size of 120x36, the sd default terminal size"
(chosen from three options: always 120x36); 3 fix; 4 fix; 5 "on by default"; 6 no; 7 no; 8 "give me more information
about this". **What was built:** 1 in `sl_menu` (rows `part_menutall` in `sandbox-screen.py`); 2 as a fixed layout and a
refusal of a smaller window (message 11197; `sed` "Get screen characteristics"; rows in `sandbox-sed-menu.py`) - which also
removes 1's SED case, so item 1 is tested on a user program; 3 and 5 in `sed` (UNDO AND REDO, THE MOUSE; messages 11194-11196;
the new suite `sandbox-sed-edit.py`, 67 rows, red 49 of 67 on the SED before); 4 in `sl_memo`, `screen_memo` and `bcomp`
(rows `part_memo3`). 6 and 7 are not built, by the owner's word. 8 is not built; what it would be is in the closing notes
of the session that asked. The text below is the evaluation as it stood when the question was asked, and its item 2 is
superseded by the owner's choice.

1. **A drop-down taller than the screen is cut off - BUILT 13 Oct (a defect, measured).** `$sl_menu` `open.geom` clamps the
   drop-down's width and, for a pop-up or a submenu, its top, but never its height: a bar menu of N items is N rows
   from row 1. On 24 rows every item of SED's Edit (17 items, 3 separators) and Tools (14) menus shows. On 14 rows the
   Edit menu shows 11 of 17 items and Tools 11 of 14; on 12 rows 10 of 17 and 10 of 14, and the menu paints over the
   status lines. From the code (not observed): the cursor still moves over the items that are not drawn. Fix in the library (cap the rows to the space, scroll with the arrows, a marker at the cut edge); SED, and any
   `screen menu` / `screen menubar` program on a small window or a split tmux pane, gets it. Small; a pty row at 12
   and 14 rows is the test (red today).
2. **SED does not follow the window - BUILD (a defect, measured; exposed by the 13 Oct window-size change).** SED
   reads `@crthigh` and `@crtwide` once, at `sed:303-317`, and sizes its arrays from them. After the pty went from 24
   to 40 rows SED kept its 24-row layout (status lines on rows 22-23, 16 blank rows below). After it went to 14 rows the
   status line was off the screen and the text was corrupted (`xyalpha one two t3ree`: after the typed `x` and `y` a
   `3`, probably the column number of the status line, appeared inside the first line). Before 13 Oct a window of another size was wrong from the first
   line; now a window dragged mid-session breaks SED. SED needs a re-layout routine called when the size changes
   (`kernel(K$WINSIZE)` read before each paint: cheap) and `redim` of `image`, `simage` and the row arrays. The
   debugger reads the size once, at start (`debug:593`); it is modal and short, so lower priority. Medium.
3. **Undo in SED - BUILD (a missing function, stated in the changelog: "SED still has no undo").** The memo has 100
   steps with typing grouped (`part_memo2`); SED has none, and Ctrl-K and Ctrl-X are one key away from the text a user
   was keeping. The syntax-colour hooks of 13 Oct (`syn.dirty`, `sed:3118`, `3558`, `3604`, `3618`) sit at the places
   where text changes (`insert.line`, the line delete, the region kill), so a journal of (line, text before, text
   after) hooks in at the same points. Not the memo's code: SED's text is in
   chunks, not a field list. Medium; the risk is a primitive that is missed, which a mutation test per primitive finds.
4. **Syntax colour and line numbers in the `screen memo` - BUILD, small.** `$sl_syntax` exists and `$sl_put` takes a style
   for every cell, so `screen memo f, id, text ... syntax 'sd.basic'` and `lnum` are a keyword each and a draw change in
   `sl_memo`. It gives any program that shows or edits source, JSON or a config file the colour SED has, and it is the
   one missing part of a BASIC-written IDE. Check: the memo's draw time with the engine on, at 160x48.
5. **SED's mouse - OPT-IN ONLY, low.** The library already reads the mouse (`$sl_mouse`) and `_keycode` binds the report,
   but a program that asks the terminal to report the mouse takes away the terminal's own text selection and copy (shift
   brings it back), and a program that dies leaves the reporting on (documented in the Mouse section above). Click to
   place the cursor and the wheel to scroll are worth having for people who want them: a word in `&sed.options&`
   (MOUSE), off by default. Per "The core direction" this is the delivered-off, administrator-loosens shape.
6. **SED's text area on the library memo - NO.** SED has buffers, a split window, a kill ring, macros, overlay,
   rebindable keys and a prompt line with history; the memo has none of them. Moving SED would lose features or rebuild
   the memo into SED. The gains people would feel (undo, resize, mouse, colour in a widget) are items 2 to 5, done in
   SED's own text area.
7. **A shadow that also holds `print` and `crt` - NO, for now.** The kernel writes the bytes of `print` and `crt` straight
   to the terminal (`tio_display_string` -> `write_console`); `@(x,y)` and the colour codes are already escape sequences by
   then. A shadow would be a terminal emulator in the kernel: parse cursor addressing, SGR, clears, wrapping, tabs and
   scrolling for every terminal definition SD ships, and decide what to do with a sequence it does not understand.
   What it would give: `SAVE.SCREEN()` / `RESTORE.SCREEN` working again (they do nothing since AccuTerm went), a pop-up
   over text a program wrote with `print`, and a resize that keeps it. What it costs: a large kernel change with a
   failure that looks like a stray character. The way out for a program is `screen text` (12a says so), and nothing
   else on this list needs the shadow.
8. **An IDE - AFTER 1 to 4, and the owner's call.** The widgets exist (tree for the files, memo with colour for the
   source, table for the compiler's errors, menu bar, status). The compile with error lines, the run and the debugger
   exist too (SED's Tools menu, `debug`). What an IDE would add over SED is a project tree and an error list beside
   the text; about two to three thousand lines of BASIC and a split-pane layout. Worth deciding after 2 and 4, because
   both are what it would stand on.
Not changed by this: scrolling pick lists (`screen pick` already scrolls), a separate editor widget (the memo is it).

### The IDE, written out (13 Oct 26: the owner asked for "more information about this"; BUILT 14 Oct 26, see the next paragraph)

**Built 14 Oct 26 (owner: "go ahead and build the ide").** `gpl.bp/ide` (`$ide`, VOC verb `ide`, messages 11198-11230), one
user-level program on the `screen` statement: a form of tree, tabs, memo (`syntax`, `lnum`), table and a default button,
the menu bar above it and a status line under it. Stages 1 and 2 were built together: open, save (asks if the record
changed on disk), compile with the table that jumps (Return, F4), catalogue, run, debug, find in the records of a file,
a tab for each open record (text and cursor kept per tab), new record, close with the save question, quit, theme, help,
and the layout follows the window (`resize` rebuilds the form from the state). Measured: 100 keystrokes in a 2,000-line
record with `sd.basic` colour took 3.2 s including 20 ms of idle per key - about 30 ms a key, so the falsifier above
(memo too slow) did not hold; the colour is still worked out from line 1 at each paint. `sandbox-ide.py`, 63 rows, red
56 of 63 with the program taken out of the sandbox. **Decisions and what they cost:** (a) Return in the tree and the
table is the form's `activate` event: a form the program marks with `f{'activate'} = 1` gives Return in a tree or a
table to the program (the id and the value) instead of pressing a default button or moving the focus on. The first
build used a visible default button ("Open"); a hidden one does not work (`default.action` skips a button that is not
on the page), and the owner asked for the button to go; (b) the status line is refreshed on the 1-second timeout of `screen wait`, because the
memo consumes its own keys and returns nothing to the program for them (so a star appears within a second, not at the
key); (c) no record locks are held while a record is open - the check at saving is the protection, which is weaker
than SED's READU and says so in the changelog; (d) the tree lists at most 2000 records of a file (a `select` of a
larger file is slow and the widget is not paged); (e) the tree is rebuilt, not edited, when a file is opened or
closed, so the cursor is put back by code. **Not built:** a project tree of files outside the VOC, completion,
replace across records, a mouse click on the menu bar (it is outside the form), splitters.

**What it would be.** One SD BASIC program (a verb, `ide` say) on the screen library, in three panes and a bar: a
**tree** of the account (its files from the VOC, and the records of each: `bp` first), the **editor** (a `screen memo` with
`syntax` and `lnum`, tabs for several records open), and an **output pane** at the bottom (the compiler's messages as a
`screen table` of line, error, with a click or Return jumping the editor to the line); a status line; and a menu bar
(File, Edit, Search, Build, Run, Debug, Window). Build is `basic file record` through `execute ... capturing`, Catalogue
the same, Run is `run`, Debug hands the terminal to `debug` (which takes the alternate screen), Search in files is `scan`.
The account is the project: no project files.

**What is already there.** Tree, memo (selection, undo, find, wrap, now colour and line numbers), table, tabs, scroll bar, menu
bar, dialogues, forms, mouse, the `resize` event, themes, and the programs it would call. SED already edits, compiles with the
errors put into the text, and runs.

**What is missing.** (a) A layout that follows the window: the panes' sizes are numbers in `screen` statements, so the program
lays them out again on a `resize` event (the library gives the event; the layout is the program's to write; no splitter widget
is needed to start, a pane's size is a variable). (b) The memo is not SED: no macros, no buffers, no kill ring, no replace
with query. The IDE's editor would be the memo, and SED stays for those who want its keys. (c) Running a program that
draws on its own screen: leave the library's screen (`screen close`), run it, come back, as the debugger does. (d) The memo's
colour is worked out from line 1 at each paint (cost grows with the text): a check-pointed state in the memo before it holds
long programs. (e) Completion and inline help are not on this list.

**Stages.** 1: the shell - bar, tree, memo with colour, open and save, build with the error table that jumps - one long sitting,
about a thousand lines and a suite of its own (~80 rows, as `sandbox-ced.py`). 2: run, catalogue, debug, search in files,
a tab for each open record. 3: resize layout, settings, polish. Each stage is usable on its own.

**What would make it not worth it.** SED already has the menus, the colour, the compile with errors and (now) undo and the
mouse; the IDE's gain over it is the tree, the error list and the output beside the text, in one program. A site that is
happy with SED loses nothing. **What would falsify the plan:** the memo too slow to repaint a 2,000-line program with colour
at each key (measure it first: a program of that size in a `screen memo` with `syntax 'sd.basic'`, 100 keystrokes), or
`execute ... capturing` not giving the compiler's lines in a form the table can use (it does for SED's error tags).

**Sequential order.** Core first; Solo and Windows only when the owner says Core is stable. The IDE is not bound by SED's
120 by 36: it follows the window.
