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
programs calling `$sl_` routines (they need `$internal` and `sd -internal` to compile); F10 is
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
