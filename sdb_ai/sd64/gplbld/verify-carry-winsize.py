#!/usr/bin/env python3
#
# sandbox-winsize.py - the size SD gives a display: the default for a session with no terminal, TERM DEFAULT, TERM w,h and
# the sign-on answer, and what a real terminal still decides for itself.  No install, no sudo.
#
#   SDBOX_KEYSET=n python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-winsize.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built, which is how the same script is run against an OLD tree to
# prove it can fail.  Exit 0 every row passed, 1 a row failed, 2 it could not run.  The sandbox is stopped when the
# suite ends; remove its directory afterwards (each run leaves ~14,000 files).
#
# WINDOWS (RELEASE_1.1 272): verify-carry-winsize.py is Linux's sandbox-winsize.py at SDCore4Linux b1d496df (last changed
# by 1d587a48), run by verify-carry.ps1 -Suite winsize through verify-carry-run.py, which stands in for sandbox-fromtree.py
# and for <box>/sys/bin/sd.  Every line changed for Windows carries "Windows:" and its reason; nothing else is changed.
#   1. The pseudo-terminal is gplbld/probe-winpty.py's PtySession: Linux's ptydrive.py (byte copy probe-ptydrive.py) run under
#      MSYS2's Python joined to SD's own runtime, driving the INSTALLED sd.exe.  Its finish() never kills.
#   2. The size probe (PROG) is not $internal and is compiled in the ordinary session: on Windows $internal compiles only for
#      an SD administrator in internal mode (bcomp, the INTERNAL directive) and "sd -internal" is elevated-only and lands in
#      SDSYS (sd.c, -INTERNAL calls check_admin()).  kernel(K$WINSIZE) is reachable only from an internal program, so PROG
#      prints winsize=<NOT-INTERNAL> and the rows that read K$WINSIZE FAIL rather than pass on an empty field - until an
#      elevated SDSYS stand-in (row 254's adm()) compiles Linux's PROG unchanged.
#
# START-HISTORY:
# 13 Nov 26 dm  Windows port - carried (RELEASE_1.1 272); the two changes above.
# 27 Oct 26 dm  S.87 batch 5: the two terminfo.src count rows follow the removal of the old Prime and other terminals (30 entries say cols#140; three 132-column entries are left).
# 18 Oct 26 dm  New, with the 140 by 42 default (plan-terminal-140x42.md, phase 1 and phase 6).
# END-HISTORY
#
# WHAT IT MEASURES.  The default for a session with NO terminal is 140 wide by 42 deep (it was 120 by 36): @CRTWIDE,
# @CRTHIGH, the display print unit's width and length (GETPU), the page a LIST fills before it asks, and what the
# compiled terminfo entries say.  A REAL terminal still decides its own size (a pseudo-terminal of 80 by 24 gives an 80 by
# 24 display), so those rows are controls that must not move.  TERM DEFAULT gives 140 by 42 on either.  TERM w,h and the
# first line typed at the sign-on (the sandbox's own TERM 200,9999) are honoured above 140 and below 80, up to the
# verb's own limits; there is no other ceiling.
#
# THE INSTRUMENT.  The program that reads the sizes (zzws...) prints a line that begins SIZE and nothing else does, so
# a row that finds no such line fails; a row never matches the echo of the command it typed.  The no-terminal sessions
# are run with `sd` on a pipe, NOT through sandbox-fromtree.py's `sess`, which types TERM 200,9999 first and so would
# hide the default.  LINES and COLUMNS are taken out of the environment of every pipe session except the one row that
# sets them on purpose.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
# Windows: Linux's ptydrive needs pty, termios and fcntl, which native Python lacks; probe-winpty.py gives the same
# PtySession (a hyphenated file name, so it is loaded by path).
import importlib.util  # noqa: E402
_wspec = importlib.util.spec_from_file_location("probe_winpty", os.path.join(HERE, "probe-winpty.py"))
_winpty = importlib.util.module_from_spec(_wspec)
_wspec.loader.exec_module(_winpty)
PtySession = _winpty.PtySession

TOOL = os.path.join(HERE, "sandbox-fromtree.py")
SD64 = os.path.dirname(HERE)
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
PROG = "zzws" + RUN                 # prints the sizes
TIPROG = "zzwt" + RUN               # prints what terminfo says
MKPROG = "zzwm" + RUN               # makes the file LIST pages
LF = "zzwl" + RUN                   # the file
passed = failed = 0

DEF_W, DEF_H = 140, 43     # 2 Nov 26: 43 (owner: "Change to 43"; tio.h, int$keys.h, terminfo.src)
SIZE_RE = re.compile(r"(?m)^SIZE wide=(\d+) high=(\d+) winsize=<([^>]*)> pulen=(\d+) puwid=(\d+)")


def say(s=""):
    print(s)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def bail(msg):
    say("sandbox-winsize: CANNOT RUN - " + msg)
    sys.exit(2)


def sdenv(box, term=None, extra=None):
    e = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    e.pop("LINES", None)
    e.pop("COLUMNS", None)
    if term:
        e["TERM"] = term
    if extra:
        e.update(extra)
    return e


def sess(box, *cmds):
    """The sandbox's scripted session; it types TERM 200,9999 first (the sign-on answer).  For compiling and setting up."""
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    return ANSI.sub("", p.stdout + p.stderr)


def isess(box, *cmds):
    """The same, in internal mode (sd -internal), where kernel() may be called."""
    # Windows: not called - sd -internal is elevated-only here and lands in SDSYS, not in the box's account (see the header).
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"),
                       env=sdenv(box), capture_output=True, text=True, errors="replace", timeout=300)
    return ANSI.sub("", p.stdout + p.stderr)


def pipe(box, cmds, term=None, extra=None):
    """What `sd` does on a pipe: no terminal, so nothing to ask the size of.  Nothing is typed first."""
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd")], input="".join(c + "\n" for c in cmds) + "OFF\n",
                       cwd=os.path.join(box, "user_accounts"), env=sdenv(box, term, extra),
                       capture_output=True, text=True, errors="replace", timeout=180)
    return ANSI.sub("", p.stdout + p.stderr)


def sizes(text):
    """Every SIZE line in the text, as (wide, high, winsize, pulen, puwid)."""
    return [(int(m.group(1)), int(m.group(2)), m.group(3), int(m.group(4)), int(m.group(5))) for m in SIZE_RE.finditer(text)]


def wh(t):
    return None if t is None else (t[0], t[1], t[3], t[4])


class Term:
    """One run of SD on a pseudo-terminal of a given size: type to it, read its screen."""

    def __init__(self, box, cols, rows, term="xterm"):
        self.cols, self.rows = cols, rows
        env = sdenv(box, term, {"LC_ALL": "C", "LANG": "C"})
        self.s = PtySession([os.path.join(box, "sys", "bin", "sd")], os.path.join(box, "user_accounts"), env, cols, rows)
        self.s.settle(1.0)
        self.s.type("TERM %s\r" % term)

    def run(self, cmd, idle=0.8):
        self.s.type(cmd + "\r", idle=idle)
        return self.s.screen.lines()

    def sizes(self):
        return sizes("\n".join(self.s.screen.lines()))

    def end(self):
        self.s.type("\rOFF\r", idle=0.5)
        self.s.finish()


# Windows: not $internal and no kernel() call - PROG is compiled in the ordinary session (see the header).  The winsize field
# is NOT-INTERNAL, never empty, so the row that wants an empty K$WINSIZE on a pipe cannot pass on the stand-in.
SIZES_SRC = """$include syscom keys.h
   w = 'NOT-INTERNAL'
   crt 'SIZE wide=' : @crtwide : ' high=' : @crthigh : ' winsize=<' : w : '> pulen=' : getpu(PU$LENGTH, -1) : ' puwid=' : getpu(PU$WIDTH, -1)
end
"""
SIZES_SRC_LINUX = """$internal
$include syscom keys.h
   w = kernel(92, '')
   crt 'SIZE wide=' : @crtwide : ' high=' : @crthigh : ' winsize=<' : w : '> pulen=' : getpu(PU$LENGTH, -1) : ' puwid=' : getpu(PU$WIDTH, -1)
end
"""
TERMINFO_SRC = """   crt 'TI cols=<' : terminfo('cols') : '> lines=<' : terminfo('lines') : '>'
end
"""
MAKE_SRC = """   execute 'DELETE.FILE %(f)s' capturing j0
   execute 'CREATE.FILE %(f)s' capturing j1
   open '%(f)s' to f else stop 'no file'
   for i = 1 to 150
      write 'rec ' : i on f, 'k' : fmt(i, 'R%%3')
   next i
   crt 'MK DONE'
end
""" % {"f": LF}


def first_page(out):
    """The lines of the first page of a LIST of LF on a pipe: from the line that echoes the command (the verb's own
    heading follows it) up to the line before the pager's question.  None if either end is missing."""
    L = out.splitlines()
    start = next((i for i, l in enumerate(L) if l.startswith("LIST " + LF)), None)
    if start is None:
        return None
    stop = next((i for i, l in enumerate(L) if i > start and l.startswith("Action (")), None)
    if stop is None:
        return None
    return stop - start


def terminfo_of(box, name):
    out = pipe(box, ["TERM " + name, "RUN bp " + TIPROG])
    m = re.search(r"(?m)^TI cols=<(\d*)> lines=<(\d*)>", out)
    return None if m is None else (m.group(1), m.group(2))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-winsize.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-winsize: sandbox %s" % box)
    say("sandbox-winsize: tree    %s" % SD64)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-winsize: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    for nm, body in ((PROG, SIZES_SRC), (TIPROG, TERMINFO_SRC), (MKPROG, MAKE_SRC)):
        with open(os.path.join(sysd, "bp", nm), "w") as fh:
            fh.write(body)
    try:
        say("\n--- setup ---------------------------------------------------------------------------------------")
        # Windows: PROG is compiled in the same ordinary session as the other two (not by isess: see the header).
        out = sess(box, "BASIC bp " + TIPROG, "BASIC bp " + MKPROG, "BASIC bp " + PROG, "RUN bp " + MKPROG)
        iout = ""
        row("setup: the three programs compiled with no errors", len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out + iout)) == 3, (out + iout)[-500:])
        row("setup: the file LIST pages was made", "MK DONE" in out, out[-300:])
        if "MK DONE" not in out:
            bail("the fixture was not made:\n" + out[-600:])

        say("\n--- no terminal: the default is %d by %d ---------------------------------------------------------" % (DEF_W, DEF_H))
        for term in (None, "xterm", "linux", "vt100", "dumb"):
            t = sizes(pipe(box, ["RUN bp " + PROG], term))
            row("a session on a pipe (TERM=%s) starts at %d by %d: @CRTWIDE, @CRTHIGH and the display's width and length" % (term or "unset", DEF_W, DEF_H),
                len(t) == 1 and wh(t[0]) == (DEF_W, DEF_H, DEF_H, DEF_W), repr(t))
        t = sizes(pipe(box, ["RUN bp " + PROG], "xterm"))
        row("... and the kernel has no window size to give (a pipe has no tty): K$WINSIZE is null", len(t) == 1 and t[0][2] == "", repr(t))
        t = sizes(pipe(box, ["RUN bp " + PROG], "xterm", {"COLUMNS": "90", "LINES": "33"}))
        row("control: LINES and COLUMNS in the environment still decide a session with no terminal (90 by 33)",
            len(t) == 1 and wh(t[0]) == (90, 33, 33, 90), repr(t))
        t = sizes(pipe(box, ["RUN bp " + PROG], "xterm", {"COLUMNS": "200", "LINES": "70"}))
        row("... and are honoured above the default (200 by 70)", len(t) == 1 and wh(t[0]) == (200, 70, 70, 200), repr(t))
        n = first_page(pipe(box, ["LIST " + LF, "", "", ""], "xterm"))
        row("LIST fills %d lines before it asks Action (Abort/Quit/Next/Suppress pagination): the page is the %d-line display less the question's row" % (DEF_H - 1, DEF_H),
            n == DEF_H - 1, "the first page was %r lines" % n)
        n = first_page(pipe(box, ["TERM 120,36", "LIST " + LF, "", "", ""], "xterm"))
        row("control: after TERM 120,36 the page is 35 lines again (the old default, still available)", n == 35, "the first page was %r lines" % n)

        say("\n--- TERM DEFAULT and TERM w,h on a pipe ------------------------------------------------------------")
        t = sizes(pipe(box, ["TERM 40,12", "RUN bp " + PROG, "TERM DEFAULT", "RUN bp " + PROG], "xterm"))
        row("TERM 40,12 is honoured below 80 (and below the old default)", len(t) == 2 and wh(t[0]) == (40, 12, 12, 40), repr(t))
        row("TERM DEFAULT puts it back to %d by %d" % (DEF_W, DEF_H), len(t) == 2 and wh(t[1]) == (DEF_W, DEF_H, DEF_H, DEF_W), repr(t))
        t = sizes(pipe(box, ["TERM 300,70", "RUN bp " + PROG, "TERM 20,10", "RUN bp " + PROG, "TERM 200,9999", "RUN bp " + PROG,
                             "TERM 32767,32767", "RUN bp " + PROG], "xterm"))
        row("TERM 300,70 is honoured above the default", len(t) == 4 and wh(t[0]) == (300, 70, 70, 300), repr(t))
        row("TERM 20,10 is honoured at the verb's own least size", len(t) == 4 and wh(t[1]) == (20, 10, 10, 20), repr(t))
        row("TERM 200,9999 (the sign-on answer the sandbox types) is honoured, depth and all: there is no ceiling",
            len(t) == 4 and wh(t[2]) == (200, 9999, 9999, 200), repr(t))
        row("TERM 32767,32767 is honoured at the verb's own greatest size", len(t) == 4 and wh(t[3]) == (32767, 32767, 32767, 32767), repr(t))
        out = pipe(box, ["TERM 99,25", "TERM 19,9", "RUN bp " + PROG, "TERM 33000,50", "RUN bp " + PROG], "xterm")
        t = sizes(out)
        row("control: TERM 19,9 is refused by the verb (width 20 to 32767) and the size stays what it was",
            "Width must be in range 20 to 32767" in out and len(t) == 2 and wh(t[0]) == (99, 25, 25, 99), repr(t) + out[-300:])
        row("control: TERM 33000,50 is refused too and the size stays",
            len(t) == 2 and wh(t[1]) == (99, 25, 25, 99) and out.count("Width must be in range 20 to 32767") == 2, repr(t))
        out = pipe(box, ["TERM 99,25", "TERM 100,5", "RUN bp " + PROG], "xterm")
        row("control: TERM 100,5 is refused by the verb (depth 10 to 32767)",
            "Depth must be in range 10 to 32767" in out and wh(sizes(out)[0] if sizes(out) else None) == (99, 25, 25, 99), out[-300:])
        out = sess(box, "RUN bp " + PROG)
        t = sizes(out)
        row("the sign-on answer: sandbox-fromtree.py's first line TERM 200,9999 is honoured (a session that says its size is believed)",
            len(t) == 1 and wh(t[0]) == (200, 9999, 9999, 200), repr(t))

        say("\n--- a real terminal still decides for itself ---------------------------------------------------------")
        for (c, r) in ((80, 24), (100, 30), (140, 42), (200, 60)):
            t = Term(box, c, r)
            t.run("RUN bp " + PROG)
            s = t.sizes()
            row("a pseudo-terminal of %d by %d gives a %d by %d display, and K$WINSIZE says so" % (c, r, c, r),
                len(s) == 1 and wh(s[0]) == (c, r, r, c) and re.fullmatch(r"%d\D%d" % (c, r), s[0][2]) is not None, repr(s))
            t.end()
        t = Term(box, 80, 24)
        t.run("TERM DEFAULT")
        t.run("RUN bp " + PROG)
        s = t.sizes()
        row("on an 80 by 24 window TERM DEFAULT gives %d by %d (it is the defaults, not the window); the window's own size is still K$WINSIZE's answer" % (DEF_W, DEF_H),
            len(s) == 1 and wh(s[0]) == (DEF_W, DEF_H, DEF_H, DEF_W) and re.fullmatch(r"80\D24", s[0][2]) is not None, repr(s))
        t.run("TERM 300,70")
        t.run("RUN bp " + PROG)
        s = t.sizes()
        row("... and TERM 300,70 on that window is honoured above it", len(s) == 2 and wh(s[1]) == (300, 70, 70, 300), repr(s))
        t.run("TERM 40,12")
        t.run("RUN bp " + PROG)
        s = t.sizes()
        row("... and TERM 40,12 below it", len(s) == 3 and wh(s[2]) == (40, 12, 12, 40), repr(s))
        t.end()
        t = Term(box, 80, 24)
        t.s.type("TERM 200,9999\r")
        t.run("RUN bp " + PROG)
        s = t.sizes()
        row("a sign-on answer TERM 200,9999 on an 80 by 24 window is honoured (no ceiling on a pseudo-terminal either)",
            len(s) == 1 and wh(s[0]) == (200, 9999, 9999, 200), repr(s))
        t.end()
        t = Term(box, 80, 24)
        L = t.run("LIST " + LF)
        row("control: LIST on an 80 by 24 window pages to the window: the question is on the last row",
            L[23].startswith("Action ("), "\n".join(l.rstrip() for l in L[18:24]))
        t.end()

        say("\n--- the terminfo entries ---------------------------------------------------------------------------")
        for name in ("xterm", "vt100", "ansi"):
            ti = terminfo_of(box, name)
            row("terminfo %s says %d columns by %d lines" % (name, DEF_W, DEF_H), ti == (str(DEF_W), str(DEF_H)), repr(ti))
        ti = terminfo_of(box, "linux")
        row("control: terminfo linux names no size at all, so a session on it takes DEFAULT.WIDTH and DEFAULT.DEPTH (the pipe rows above)", ti == ("", ""), repr(ti))
        ti = terminfo_of(box, "dumb")
        row("terminfo dumb (an entry that names a width and no length) says %d columns" % DEF_W, ti is not None and ti[0] == str(DEF_W), repr(ti))
        ti = terminfo_of(box, "vt100-w")
        row("control: vt100-w, a 132-column terminal, keeps its 132 columns", ti is not None and ti[0] == "132", repr(ti))
        ti = terminfo_of(box, "ms-vt100")
        row("control: ms-vt100 keeps the 25 lines it names", ti is not None and ti[1] == "25", repr(ti))
        with open(os.path.join(SD64, "terminfo.src")) as fh:
            src = fh.read()
        # 44 entries said cols#140 when the default moved; 30 after S.87 batch 5 and 21 after batch 18 (28 Oct 26) removed nine more old terminals
        row("terminfo.src: no entry says cols#120 any more", "cols#120" not in src and src.count("cols#140") >= 21, "%d x cols#120, %d x cols#140" % (src.count("cols#120"), src.count("cols#140")))
        # five until 27 Oct 26 (S.87 batch 5), when two of them (pt100w, pt250w, old Prime terminals) were removed
        row("terminfo.src: lines#36 is left only on the three 132-column entries", len(re.findall(r"lines#36", src)) == len(re.findall(r"cols#132,[^\n]*lines#36", src)) == 3,
            "%d x lines#36" % len(re.findall(r"lines#36", src)))

        say("\n--- the source says the same -----------------------------------------------------------------------")
        with open(os.path.join(SD64, "sdsys", "gpl.bp", "int$keys.h")) as fh:
            ik = fh.read()
        row("int$keys.h: DEFAULT.WIDTH %d and DEFAULT.DEPTH %d" % (DEF_W, DEF_H),
            re.search(r"\$define DEFAULT\.WIDTH\s+%d\b" % DEF_W, ik) is not None and re.search(r"\$define DEFAULT\.DEPTH\s+%d\b" % DEF_H, ik) is not None)
        with open(os.path.join(SD64, "sdsys", "gpl.bp", "term")) as fh:
            tv = fh.read()
        row("term: the help text names %d x %d and no longer 120 x 36" % (DEF_W, DEF_H), ("(%d x %d;" % (DEF_W, DEF_H)) in tv and "(120 x 36;" not in tv)
    finally:
        say("\n--- cleanup ---------------------------------------------------------------------------------------")
        sess(box, "DELETE.FILE " + LF)
        for nm in (PROG, TIPROG, MKPROG):
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        subprocess.run([sys.executable, TOOL, box, "stop"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\nsandbox-winsize: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
