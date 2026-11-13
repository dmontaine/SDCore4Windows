#!/usr/bin/env python3
#
# termscreen.py - a small VT100 screen, so a test can read what a full-screen SD program DREW rather than the
# stream of bytes it wrote.  No dependencies.
#
#   from termscreen import Screen
#   s = Screen(100, 20)
#   s.feed(output_text)
#   s.lines()          the rows now on the screen, trailing spaces removed
#   s.before_clear     the rows as they were just before the LAST clear of the whole screen - which, for a
#                      program that clears the screen as it exits, is the program's last screen
#   s.reverse(row)     the text drawn in reverse video on that row (the selected line of a menu)
#
# It understands what SD's terminfo entries for the xterm type send: cursor positioning (CSI r;c H), clear
# screen (CSI 2 J), erase in line and display, cursor moves, delete / insert character, the attribute switch
# (only reverse video is kept), carriage return, newline (with scrolling), backspace and tab.  Everything else
# (modes, colours, the keypad switch) is read and ignored.  START-HISTORY:
# 12 Oct 26 dm  New, for sandbox-ced.py.
# END-HISTORY

import re

CSI = re.compile(r"\x1b\[([0-9;?]*)([ -/]*)([@-~])")


class Screen:
    def __init__(self, cols=100, rows=24):
        self.cols = cols
        self.rows = rows
        self.grid = [[" "] * cols for _ in range(rows)]
        self.rev = [[False] * cols for _ in range(rows)]
        self.r = 0
        self.c = 0
        self.reverse_on = 0            # the current style: bit 1 reverse, bit 2 underline (the grid keeps it per cell)
        self.cursor_visible = True
        self.before_clear = None
        self.clears = 0

    def _blank_row(self):
        return [" "] * self.cols, [False] * self.cols

    def resize(self, cols, rows):
        """The window was resized: what is shown stays where it is, cut off if the window got smaller and padded with blanks
        if it got bigger (a terminal does not reflow a full-screen program's picture), and the cursor stays inside it."""
        for i in range(len(self.grid)):
            self.grid[i] = (self.grid[i][:cols] + [" "] * cols)[:cols]
            self.rev[i] = (self.rev[i][:cols] + [0] * cols)[:cols]
        self.cols = cols
        while len(self.grid) < rows:
            g, v = self._blank_row()
            self.grid.append(g)
            self.rev.append(v)
        del self.grid[rows:]
        del self.rev[rows:]
        self.rows = rows
        self.r = min(self.r, rows - 1)
        self.c = min(self.c, cols - 1)

    def _scroll(self):
        self.grid.pop(0)
        self.rev.pop(0)
        g, v = self._blank_row()
        self.grid.append(g)
        self.rev.append(v)

    def _put(self, ch):
        if self.c >= self.cols:
            self.c = 0
            self._newline()
        self.grid[self.r][self.c] = ch
        self.rev[self.r][self.c] = self.reverse_on
        self.c += 1

    def _newline(self):
        if self.r == self.rows - 1:
            self._scroll()
        else:
            self.r += 1

    def lines(self):
        return ["".join(row).rstrip() for row in self.grid]

    def reverse(self, row):
        return "".join(ch for ch, v in zip(self.grid[row], self.rev[row]) if v & 1).strip()

    def underline(self, row):
        """The text drawn underlined on that row."""
        return "".join(ch for ch, v in zip(self.grid[row], self.rev[row]) if v & 2).strip()

    def attrs(self, row):
        """One code per cell of the row, as the screen library names them: n normal, r reverse, u underline, x both."""
        return "".join("nrux"[v & 3] for v in self.rev[row])

    def style(self, row, col):
        """The look of one cell: (foreground, background, flags).  The colours are the ANSI numbers 0 to 7 (black, red, green,
        yellow, blue, magenta, cyan, white: NOT the Pick order the library's names use) or None for the terminal's own; flags
        is a string of r reverse, u underline, b bold."""
        v = self.rev[row][col]
        fg = ((v >> 8) & 15) - 1
        bg = ((v >> 12) & 15) - 1
        flags = ("r" if v & 1 else "") + ("u" if v & 2 else "") + ("b" if v & 4 else "")
        return (fg if fg >= 0 else None, bg if bg >= 0 else None, flags)

    def text_where(self, row, fg=False, bg=False, flags=None):
        """The text of the cells on that row whose look matches: fg / bg an ANSI number or None for the terminal's own
        (False: do not ask), flags the exact flag string (None: do not ask)."""
        out = []
        for c in range(self.cols):
            f, b, fl = self.style(row, c)
            if fg is not False and f != fg:
                continue
            if bg is not False and b != bg:
                continue
            if flags is not None and fl != flags:
                continue
            out.append(self.grid[row][c])
        return "".join(out)

    def _csi(self, params, final):
        nums = [int(p) if p.isdigit() else None for p in params.split(";")] if params and not params.startswith("?") else []
        n1 = nums[0] if nums and nums[0] is not None else None
        if params.startswith("?"):
            if params == "?25" and final in "lh":
                self.cursor_visible = (final == "h")
            if params in ("?1047", "?1049", "?47") and final in "lh":
                # the ALTERNATE screen: h keeps the main one aside and shows a blank one, l gives the main one back
                if final == "h" and getattr(self, "_main", None) is None:
                    self._main = ([row[:] for row in self.grid], [row[:] for row in self.rev], self.r, self.c)
                    for i in range(len(self.grid)):
                        self.grid[i] = [" "] * self.cols
                        self.rev[i] = [0] * self.cols
                    self.alt_entered = getattr(self, "alt_entered", 0) + 1
                elif final == "l" and getattr(self, "_main", None) is not None:
                    self.grid, self.rev, self.r, self.c = self._main
                    self._main = None
            return   # the other modes (keypad, margins): not drawing
        if final in "Hf":
            row = (nums[0] if len(nums) > 0 and nums[0] else 1) - 1
            col = (nums[1] if len(nums) > 1 and nums[1] else 1) - 1
            self.r = min(max(row, 0), self.rows - 1)
            self.c = min(max(col, 0), self.cols - 1)
        elif final == "J":
            mode = n1 if n1 is not None else 0
            if mode == 2:
                self.before_clear = self.lines()
                self.clears += 1
                for i in range(self.rows):
                    self.grid[i], self.rev[i] = self._blank_row()
            elif mode == 0:
                if self.r == 0 and self.c == 0:
                    # 2 Nov 26 (S.98 H3): the clear of the linux, vt100 and vt220 entries is CSI H CSI J: an erase to the end of the screen from the top left cell is a whole clear
                    self.before_clear = self.lines()
                    self.clears += 1
                for j in range(self.c, self.cols):
                    self.grid[self.r][j] = " "
                    self.rev[self.r][j] = False
                for i in range(self.r + 1, self.rows):
                    self.grid[i], self.rev[i] = self._blank_row()
        elif final == "K":
            mode = n1 if n1 is not None else 0
            lo, hi = (self.c, self.cols) if mode == 0 else ((0, self.c + 1) if mode == 1 else (0, self.cols))
            for j in range(lo, hi):
                self.grid[self.r][j] = " "
                self.rev[self.r][j] = False
        elif final == "A":
            self.r = max(self.r - (n1 or 1), 0)
        elif final == "B":
            self.r = min(self.r + (n1 or 1), self.rows - 1)
        elif final == "C":
            self.c = min(self.c + (n1 or 1), self.cols - 1)
        elif final == "D":
            self.c = max(self.c - (n1 or 1), 0)
        elif final == "G":
            self.c = min(max((n1 or 1) - 1, 0), self.cols - 1)
        elif final == "d":
            self.r = min(max((n1 or 1) - 1, 0), self.rows - 1)
        elif final == "P":
            k = n1 or 1
            row, rv = self.grid[self.r], self.rev[self.r]
            del row[self.c:self.c + k]
            del rv[self.c:self.c + k]
            row.extend([" "] * (self.cols - len(row)))
            rv.extend([False] * (self.cols - len(rv)))
        elif final == "@":
            k = n1 or 1
            row, rv = self.grid[self.r], self.rev[self.r]
            row[self.c:self.c] = [" "] * k
            rv[self.c:self.c] = [False] * k
            del row[self.cols:]
            del rv[self.cols:]
        elif final == "m":
            codes = [x for x in params.split(";")] if params else ["0"]
            for code in codes:
                if code in ("", "0"):
                    self.reverse_on = 0
                elif code == "27":
                    self.reverse_on &= ~1
                elif code == "7":
                    self.reverse_on |= 1
                elif code == "24":
                    self.reverse_on &= ~2
                elif code == "4":
                    self.reverse_on |= 2
                elif code == "1":
                    self.reverse_on |= 4
                elif code == "22":
                    self.reverse_on &= ~4
                elif code.isdigit() and 30 <= int(code) <= 37:
                    self.reverse_on = (self.reverse_on & ~0xF00) | ((int(code) - 30 + 1) << 8)
                elif code == "39":
                    self.reverse_on &= ~0xF00
                elif code.isdigit() and 40 <= int(code) <= 47:
                    self.reverse_on = (self.reverse_on & ~0xF000) | ((int(code) - 40 + 1) << 12)
                elif code == "49":
                    self.reverse_on &= ~0xF000

    def feed(self, text):
        # An escape sequence can be cut by the end of what one read gave: the start of it is kept for the next feed
        # (without this a lone ESC at the end of a chunk was skipped with the next character and the rest printed as text)
        text = getattr(self, "_pend", "") + text
        self._pend = ""
        i = 0
        n = len(text)
        while i < n:
            ch = text[i]
            if ch == "\x1b":
                m = CSI.match(text, i)
                if m:
                    self._csi(m.group(1), m.group(3))
                    i = m.end()
                    continue
                if re.match(r"\x1b(\[[0-9;?<>]*)?$", text[i:]) or (text[i:] in ("\x1b(", "\x1b)")):
                    self._pend = text[i:]
                    break
                # ESC 7 / 8 (save / restore cursor), ESC = and ESC > (keypad), ESC ( B and the like
                if i + 1 < n and text[i + 1] in "()":
                    i += 3
                else:
                    i += 2
                continue
            if ch == "\r":
                self.c = 0
            elif ch == "\n":
                self._newline()
            elif ch == "\b":
                self.c = max(self.c - 1, 0)
            elif ch == "\t":
                self.c = min((self.c // 8 + 1) * 8, self.cols - 1)
            elif ch == "\x07" or ch == "\x0e" or ch == "\x0f":
                pass
            elif ch < " ":
                pass
            else:
                self._put(ch)
            i += 1


if __name__ == "__main__":
    s = Screen(20, 4)
    s.feed("\x1b[H\x1b[2Jhello\x1b[2;3Hxy\x1b[7mREV\x1b[27m\x1b[3;1Hz\x1b[Kq")
    assert s.lines() == ["hello", "  xyREV", "zq", ""], s.lines()
    assert s.reverse(1) == "REV", s.reverse(1)
    s.feed("\x1b[2J")
    assert s.before_clear == ["hello", "  xyREV", "zq", ""], s.before_clear
    # underline, both together, the style kept per cell, and the cursor state
    s.feed("\x1b[H\x1b[4mUL\x1b[24m\x1b[7mRV\x1b[4mBO\x1b[m..")
    assert s.underline(0) == "ULBO" and s.reverse(0) == "RVBO", (s.underline(0), s.reverse(0))
    assert s.attrs(0)[:8] == "uurrxxnn", s.attrs(0)[:8]
    # colours (ANSI numbers), bold, and a reset that clears all of it
    s.feed("\x1b[H\x1b[2J\x1b[31;44mAB\x1b[1mC\x1b[39mD\x1b[49mE\x1b[0mF")
    assert s.style(0, 0) == (1, 4, ""), s.style(0, 0)
    assert s.style(0, 2) == (1, 4, "b"), s.style(0, 2)
    assert s.style(0, 3) == (None, 4, "b"), s.style(0, 3)
    assert s.style(0, 4) == (None, None, "b"), s.style(0, 4)
    assert s.style(0, 5) == (None, None, ""), s.style(0, 5)
    assert s.text_where(0, fg=1, bg=4) == "ABC", s.text_where(0, fg=1, bg=4)
    assert s.text_where(0, bg=None, flags="").strip() == "F", s.text_where(0, bg=None, flags="")
    s.feed("\x1b[H\x1b[2J")
    assert s.cursor_visible
    s.feed("\x1b[?25l")
    assert not s.cursor_visible
    s.feed("\x1b[?25h")
    assert s.cursor_visible
    # a resize keeps what is there, cut or padded, and the cursor inside
    s.feed("\x1b[H\x1b[2Jabcdef\x1b[2;1Hxyz")
    s.resize(4, 3)
    assert s.lines() == ["abcd", "xyz", ""] and s.rows == 3 and s.cols == 4, s.lines()
    s.resize(8, 5)
    assert s.lines() == ["abcd", "xyz", "", "", ""] and len(s.grid[0]) == 8, s.lines()
    # 2 Nov 26 (S.98 H3): the console's clear is CSI H CSI J (an erase to the end from the top left cell): counted as a clear; the same erase from any other cell is not
    t = Screen(10, 3)
    t.feed("\x1b[H\x1b[2Jone\x1b[2;1Htwo")
    t.feed("\x1b[2;2H\x1b[J")
    assert t.clears == 1 and t.lines() == ["one", "t", ""], (t.clears, t.lines())
    t.feed("\x1b[H\x1b[J")
    assert t.clears == 2 and t.before_clear == ["one", "t", ""] and t.lines() == ["", "", ""], (t.clears, t.before_clear, t.lines())
    print("termscreen: self-test passed")
