# screen library (sl_), stage 2 first cut - design note

12 Oct 2026. Written before the menu, kept to what SED needs plus the obvious next widgets.
Background: PROJECT_STATUS.md S.1 (stage 1: a pure BASIC renderer is fast enough).
First users: SED's menu bar and quit box. Tests: gplbld/sandbox-sed-menu.py.

## layers

1. keys - `$sl_key(timeout, name)`: ONE place that turns the terminal's key bytes into names (up
   down left right home end pgup pgdn ins del bs tab btab enter esc f1..f12 ctrl-a..ctrl-z, or the
   printable character). Built on KEYCODE(), so terminfo decides what a sequence means; a lone Esc
   is told from a sequence by KEYCODE()'s 0.2 s wait. Null = timeout or input ended. Mouse: SGR 1006
   reports reach KEYIN intact (S.1 stage 1) - a later `mouse` name plus position fields in a context;
   nothing decodes them yet. SED itself still reads raw bytes (its own binding tables) and only calls
   the library once a menu is open - see "not moved onto the library".
2. regions - `$sl_region(op, scr, x, y, w, h, saved)`: save what is under a rectangle, put it back.
3. theme - `$sl_attr(name, seq)`: the one table of attributes (normal, highlight, bar, hotkey,
   hotkey.end, frame, disabled). Only reverse video and underline, so it reads on a monochrome
   terminal; hotkey letters are underlined. A colour theme replaces this routine's table only.
   'disabled' is not yet different from normal (a monochrome terminal has no dim).
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
draws it back. Text and reverse video only; richer cells are repainted by the caller. (A
double-buffered renderer, S.1, would own the shadow itself; the argument shape does not change.)

## layout and resize

Character cells, from 0, as in `@(x, y)`. `SL.S.CLIP` is the clip rectangle: `$sl_region` skips rows
outside the screen; per-cell clipping is not done yet (widgets are sized to fit: a message box
is clamped to the screen width, a menu shifts left if it would overflow). Size comes from
@crtwide / @crthigh which the caller passes in `scr`. Resize hook (documented, not built): on a
size change the caller re-reads the size, rebuilds `scr` and sends every widget `init` then `draw`;
the widgets hold nothing that depends on the old size once re-initialised.

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
- scroll bar: `draw` from top/total/visible, no keys of its own.
- tab strip: like the menu bar with an always-open single level; `key` left/right -> `handled`, the form shows the page.
- message / confirm box and input prompt: exist now (`$sl_msgbox`, `$sl_prompt`).

## what SED could not move onto the library

SED's text area, its status lines and its own prompt line (`get.string`, with history, kill and
Emacs line editing driven by SED's key bindings) stay SED's: they need SED's binding tables and
SED's image buffer, which the library does not know. SED reads raw bytes with its own tables
(the library's `$sl_key` would have to learn SED's rebindable keys). SED feeds the library a shadow
of its image buffer; `ced_edit` is left on its own drawing code.

## not done yet (deliberately)

mouse; acsc/Unicode box drawing (boxes are + - |); colour; a renderer owning the shadow; disabled/
checked/submenu items; scrolling drop-downs longer than the screen; per-cell clipping; the form; user
programs calling `$sl_` routines (they need `$internal` and `sd -internal` to compile: settled by the `screen`
statement, see SCOPE below); F10 is
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
layer (`tio_printf`, `@(IT$...)` codes), raw mode and SIGWINCH in `linuxio.c`, and a ring buffer fed by
`do_input()` on SIGIO. newt, tickit, ncurses and notcurses initialise the tty themselves (termios, alternate
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
`test-screencmd-units.py` checks the verb table, the routines and their headers agree. Stage 3 (forms,
below) is being built. Everything marked "proposed" is written in the conditional, with what would falsify it.

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
  repaints from the shadow after it. The kernel's `SAVE.SCREEN` / `RESTORE.SCREEN` do nothing on a
  Linux terminal (`linuxio.c:752`, they only work in an SDTerm client); once the shadow exists they could
  be made to use it, which would also give the debugger's pop-ups back their screen - not proposed yet.
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
| `set` | `screen set f, id {value v} {text t} {items i} {enabled b}` | - | `!screen_set` |
| `focus` | `screen focus f, id` | - | `!screen_focus` |

A zero-value keyword (`fill`, `multi`, `mask`, `on`) is a flag: the subroutine is given 1, else null.
`items` are values (or a comma list, as `buttons` already is); a menu item is label @sm shortcut @sm
code, as `$sl_menu` takes it today. `attr` names an attribute (`'reverse'`, `'bold'`, later colours).

`run` is the simple modal form; `wait` is the event-loop form for a program that must react between key
strokes (validate on leaving a field, fill one list from another) without callbacks - BASIC cannot hand
one in. The program loops: `screen wait f returning ev` then `begin case` on the event type
(`button`, `change`, `select`, `key`, `timeout`) and the widget id.

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
| 3 | the form (a collection) and its container; label, frame, entry, check, radio, list, button; focus ring; `run`, `get`, `set`, `focus`, `values` - BEING BUILT | large | the 25-line program above, field by field; Tab / Shift-Tab; default and cancel buttons |
| 4 | `wait` (events), `combo`, tabs, scroll bar, status line, progress | medium | event order; a combo over a form; scrolling lists |
| 5 | colour themes, mouse (SGR 1006 already reaches KEYIN), resize (SIGWINCH) | medium | attributes; clicks; a resized pty |
| 6 | editor and viewer widgets; `ced_edit` and the debugger on the library; table, tree | large | the editors' existing suites (`sandbox-ced.py`) |
| 7 | carry to Solo (bcomp, the library, 12172-12175), then the Windows agent when Core is declared stable | small each | their own suites |

What would falsify the plan: (a) stage 1's per-cell shadow making a BASIC repaint slower than ~16 ms at
160x48 with colour (S.1 measured monochrome rows only); (b) collection reads and writes (about thirty a
key at a form's widest) being too slow for a key to feel instant - measure it at stage 3 with the 25-line
form; (c) the focus ring needing a widget to see keys before its parent, which the `unhandled` convention
cannot express (the first worker's own doubt).

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
   takes the else branch. Proposed, untested.
6. Cursor after a transient dialogue: nothing in SD reads the cursor position, so it is left at the
   box's last cell. After `open` the library owns it. A save/restore pair from terminfo (`sc`/`rc`) is
   possible for terminals that have it - not proposed.
7. Carry-over: the statement is compiled by `bcomp`, so Solo and Windows get it with the compiler;
   message numbers 12172-12175 are Linux's range, the Windows agent allocates its own. Nothing is sent
   to them until the owner declares Core stable (the standing order).
