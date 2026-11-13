#!/usr/bin/env python3
#
# ptydrive.py - run a program on a pseudo-terminal, type to it, and read its screen.  No dependencies.
#
#   from ptydrive import PtySession
#   s = PtySession([sd, ...], cwd, env, cols=100, rows=20)
#   s.type("TERM xterm\r")            bytes typed as they are; \r is Return
#   s.settle()                        wait until the program has stopped writing
#   s.screen.lines()                  what is on the screen now
#
# WHY A PTY AND NOT A PIPE.  SD reads a piped stdin a byte at a time with no timeout (linuxio.c keyin()), so an
# Esc typed into a pipe is taken for the start of a key sequence and swallowed with the byte after it; only a
# terminal gives the timeout that tells a lone Esc from Esc-O-A.  A terminal also has a line discipline in the
# way - Ctrl-C, Ctrl-S, Ctrl-Q and Ctrl-X are keys to the editor, and the tty driver would eat several of them
# if SD left it in a mode that handles them - and a pipe cannot show that.
#
# START-HISTORY:
# 12 Oct 26 dm  New, for sandbox-ced.py (the CED editor's keys).
# END-HISTORY

import errno
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time
import codecs

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from termscreen import Screen  # noqa: E402


class PtySession:
    idle_cap = None                     # see keeps_writing()

    def keeps_writing(self):
        """The program from here on writes a few bytes every second even when nothing is happening (the IDE does), so a settle
        that asks for a second or more of silence would never see it and would run to its limit, 20 s each time.  Asked idles are
        capped at 0.7 s for this session (9 Nov 26, S.191: ide-kinds, 805 s to 292 s, the same 64 rows).  Call it after sign-on,
        just before the program starts: the sign-on's own pauses are longer and the prompt does not write."""
        self.idle_cap = 0.7

    def __init__(self, argv, cwd, env, cols=100, rows=24, utf8=False):
        """utf8 True: what the program writes is decoded as UTF-8, so a three-byte character is one cell of the emulated
        screen, as on a UTF-8 terminal (the default is one cell to a byte, which is what every older suite relies on)."""
        self.cols = cols
        self.rows = rows
        self.dec = codecs.getincrementaldecoder("utf-8")("replace") if utf8 else None
        self.raw = b""
        self.screen = Screen(cols, rows)
        self.exited = False
        self.status = None
        pid, fd = pty.fork()
        if pid == 0:                      # the child: become the program
            try:
                # the window size is set BEFORE the program starts: SD asks the tty how big it is when it starts (13 Oct 26), and
                # setting it afterwards from the parent could lose the race
                fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
                os.chdir(cwd)
                os.execve(argv[0], argv, env)
            finally:
                os._exit(127)
        self.pid = pid
        self.fd = fd
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def resize(self, cols, rows, idle=0.6):
        """Resize the terminal window, as dragging its corner does: the kernel tells the program with SIGWINCH.  The emulator keeps
        what it shows (termscreen.Screen.resize) and then takes what the program writes in answer."""
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self.cols = cols
        self.rows = rows
        self.screen.resize(cols, rows)
        self.settle(idle)

    def _pump(self, wait):
        """Read what is ready, up to `wait` seconds for the first byte.  Returns the bytes read."""
        got = b""
        if self.exited:
            return got
        r, _, _ = select.select([self.fd], [], [], wait)
        while r:
            try:
                data = os.read(self.fd, 65536)
            except OSError as e:
                if e.errno == errno.EIO:
                    self.exited = True
                    break
                raise
            if not data:
                self.exited = True
                break
            got += data
            r, _, _ = select.select([self.fd], [], [], 0)
        if got:
            self.raw += got
            self.screen.feed(self.dec.decode(got) if self.dec else got.decode("latin-1"))
        return got

    def settle(self, idle=0.35, limit=20.0):
        """Wait until the program has written nothing for `idle` seconds (or exited, or `limit` passes)."""
        if self.idle_cap is not None:
            idle = min(idle, self.idle_cap)
        end = time.time() + limit
        while time.time() < end and not self.exited:
            if not self._pump(idle):
                return
        return

    def type(self, data, settle=True, idle=0.35):
        if isinstance(data, str):
            data = data.encode("latin-1")
        if self.exited or self.fd < 0:
            return
        try:
            os.write(self.fd, data)
        except OSError:                 # the program has gone: there is nobody to type to
            self.exited = True
            return
        if settle:
            self.settle(idle)

    def _reap(self, limit):
        end = time.time() + limit
        while time.time() < end:
            try:
                pid, st = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                return True
            if pid:
                self.status = st
                return True
            time.sleep(0.1)
        return False

    def finish(self, limit=10.0):
        """Let the program go.  One that is still running is HUNG UP, as closing a terminal window does, so that
        SD ends cleanly and gives its record locks back; a kill is the last resort (and leaves them locked)."""
        end = time.time() + limit
        while time.time() < end and not self.exited:
            self._pump(0.2)
            if self._reap(0.0):
                self.exited = True
        if not self.exited:
            try:
                os.close(self.fd)               # the master side closes: the session leader gets SIGHUP
            except OSError:
                pass
            self.fd = -1
            if self._reap(8.0):
                self.exited = True
        if not self.exited:
            os.kill(self.pid, signal.SIGKILL)
            self._reap(5.0)
            self.killed = True
        if self.fd >= 0:
            try:
                os.close(self.fd)
            except OSError:
                pass
        return self.status
