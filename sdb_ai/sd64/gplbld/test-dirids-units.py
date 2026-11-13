#!/usr/bin/env python3
"""test-dirids-units.py - a directory file's SELECT gives back the record id that was written, when the id holds a byte 128-255 that is
not valid UTF-8 (op_dio4.c os_name_to_id(), dir_select(); RELEASE_1.1 273, verify-carry-file-b8 row 34).

  python sdb_ai/sd64/gplbld/test-dirids-units.py
  python sdb_ai/sd64/gplbld/test-dirids-units.py --selftest

It CUTS os_name_to_id() out of gplsrc/op_dio4.c (from the signature to the closing brace at the start of a line), compiles it with MSYS2
gcc (the server's runtime, whose file names are the thing under test) beside a main(), and for each id below: creates a file of that name
in a scratch folder, lists the folder with readdir(), decodes the listed name, and opens the decoded name again.  Each row prints the id,
the bytes readdir() gave, the bytes after the decode, and whether the decoded id reopens the file.  The ids go in as hex in the
environment, never on a command line, which MSYS2 would glob.

  a row holds when the decoded name is byte-identical to the id written, the reopen succeeds, and exactly one file was listed

W0 (text): dir_select() calls os_name_to_id(name) straight after copying dp->d_name, before the %-escape decode.
Exit 0 every row held, 1 a row failed, 2 no MSYS2 bash.  --selftest mutates the C text (each must match once), rebuilds, and needs a red row.
Written 13 Nov 2026.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "gplsrc", "op_dio4.c")
BASH = "C:/msys64/usr/bin/bash.exe"
BS = chr(92)

MAIN = r'''
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#define Private static
%s
static void hex(const char* s) { for (; *s; s++) printf("%%02X", (unsigned char)*s); }
int main(void) {
  const char* dir = getenv("DI_DIR");
  const char* h = getenv("DI_ID");
  char id[256], path[1024], name[1024];
  int n = 0, fd;
  DIR* d;
  struct dirent* e;
  if (dir == NULL || h == NULL || strlen(h) %% 2 || strlen(h) / 2 >= sizeof(id)) return 3;
  for (n = 0; h[2 * n]; n++) { unsigned v; sscanf(h + 2 * n, "%%2x", &v); id[n] = (char)v; }
  id[n] = '\0';
  snprintf(path, sizeof path, "%%s/%%s", dir, id);
  fd = open(path, O_CREAT | O_WRONLY, 0600);
  if (fd < 0) { printf("CREATE FAILED\n"); return 4; }
  close(fd);
  d = opendir(dir);
  n = 0;
  while (d != NULL && (e = readdir(d)) != NULL) {
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
    n++;
    strcpy(name, e->d_name);
    printf("listed "); hex(name); printf("\n");
    os_name_to_id(name);
    printf("decoded "); hex(name); printf("\n");
    snprintf(path, sizeof path, "%%s/%%s", dir, name);
    fd = open(path, O_RDONLY);
    printf("reopen %%s\n", fd >= 0 ? "ok" : "FAILED");
    if (fd >= 0) close(fd);
  }
  if (d != NULL) closedir(d);
  printf("count %%d\n", n);
  return 0;
}
'''

# (what it is, the id's bytes)
ROWS = [("byte 233 (the suite's caf+233)", b"caf\xe9"), ("byte 247 (the suite's top+247)", b"top\xf7"),
        ("byte 128, the low end", b"a\x80"), ("byte 191", b"a\xbf"), ("byte 192", b"a\xc0"), ("byte 255, the high end", b"a\xff"),
        ("two such bytes together", b"\xe9\xf7x"),
        ("CONTROL: UTF-8 e-acute (195 169) is left as it is", b"caf\xc3\xa9"),
        ("CONTROL: a three-byte UTF-8 character (the euro sign) is left as it is", b"x\xe2\x82\xac"),
        ("CONTROL: a plain id", b"plain")]


def cut(text, head):
    i = text.find(head)
    if i < 0:
        return None
    j = text.find("\n}\n", i)
    return text[i:j + 3] if j >= 0 else None


def to_msys(p):
    p = p.replace(BS, "/")
    return "/" + p[0].lower() + p[2:] if len(p) > 1 and p[1] == ":" else p


def build(work, text, exe):
    f = cut(text, "Private void os_name_to_id(char* name) {")
    if f is None:
        return False, "os_name_to_id() was not found in op_dio4.c (null case)"
    open(os.path.join(work, "d.c"), "w", newline="\n").write(MAIN % f)
    r = subprocess.run([BASH, "-lc", 'cd "%s" && gcc -O2 -Wall -o "%s" d.c' % (to_msys(work), to_msys(exe))],
                       capture_output=True, text=True, env=dict(os.environ, MSYSTEM="MSYS"))
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def w0(text):
    i = text.find("Private bool dir_select(FILE_VAR* fvar, int16_t list_no) {")
    body = text[i:text.find("\n}\n", i)] if i >= 0 else ""
    a = body.find("strcpy(name, dp->d_name);")
    b = body.find("os_name_to_id(name);")
    c = body.find("if (map_dir_ids && (strchr(name, '%') != NULL))")
    return 0 <= a < b < c


def rows(exe, text, work, quiet=False):
    bad = 0
    held = w0(text)
    bad += 0 if held else 1
    if not quiet:
        print("  [%s] W0 dir_select() decodes the listed name with os_name_to_id() before the %%-escape decode" % ("PASS" if held else "FAIL"))
    for k, (what, idb) in enumerate(ROWS):
        d = os.path.join(work, "r%d" % k)
        os.mkdir(d)
        # RUN FROM AN MSYS2 LOGIN SHELL, because that is the mode SD's own sessions were measured in (13 Nov 2026: the suite's zzb8d
        # holds U+F0E9 and U+F0F7).  Started straight from Python the same program stores byte 233 as U+00E9 instead, and the UTF-8
        # e-acute id then opens the SAME file - see RELEASE_1.1 273 for that open question.
        r = subprocess.run([BASH, "-lc", 'cd "%s" && DI_DIR="%s" DI_ID=%s "%s"' % (to_msys(d), to_msys(d), idb.hex().upper(), to_msys(exe))],
                           capture_output=True, text=True, env=dict(os.environ, MSYSTEM="MSYS"))
        lines = dict(l.split(" ", 1) for l in r.stdout.splitlines() if " " in l)
        listed, decoded, reopen, count = lines.get("listed", ""), lines.get("decoded", ""), lines.get("reopen", ""), lines.get("count", "")
        ok = r.returncode == 0 and count == "1" and decoded == idb.hex().upper() and reopen == "ok"
        bad += 0 if ok else 1
        if not quiet:
            print("  [%s] %s: wrote %s, readdir gave %s, decoded %s, reopen %s, files listed %s" %
                  ("PASS" if ok else "FAIL", what, idb.hex().upper(), listed or "NOTHING", decoded or "NOTHING", reopen or "NOTHING",
                   count or "NOTHING (null case)") + ("" if r.returncode == 0 else ", exit %d" % r.returncode))
    return bad


MUTANTS = [
    ("the U+F0C0-U+F0FF half is not decoded", "((p[1] == 0x82) || (p[1] == 0x83))", "(p[1] == 0x82)"),
    ("the U+F080-U+F0BF half is not decoded", "((p[1] == 0x82) || (p[1] == 0x83))", "(p[1] == 0x83)"),
    ("the high bit of the byte is lost", "((p[1] & 0x01) << 6) | (p[2] & 0x3F) | 0x80)", "((p[1] & 0x01) << 6) | (p[2] & 0x3F))"),
    ("bit 6 is lost", "((p[1] & 0x01) << 6) | (p[2] & 0x3F) | 0x80)", "(p[2] & 0x3F) | 0x80)"),
    ("any three-byte lead is decoded, so the euro sign's E2 82 AC is taken for a byte", "(p[0] == 0xEF) &&", "(p[0] >= 0xE0) &&"),
    ("dir_select() does not call it", "        os_name_to_id(name); /* 13 Nov 26: RELEASE_1.1 273 */\n", ""),
]


def main():
    print("test-dirids-units: source %s" % SRC)
    if not os.path.isfile(BASH):
        print("NO TREE: no MSYS2 bash at %s" % BASH)
        return 2
    text = open(SRC, encoding="latin-1", newline="").read()
    work = tempfile.mkdtemp(prefix="dirids-")
    try:
        exe = os.path.join(work, "d.exe")
        ok, msg = build(work, text, exe)
        if not ok:
            print("BUILD FAILED: " + msg)
            return 1
        live = os.path.join(work, "live")
        os.mkdir(live)
        bad = rows(exe, text, live)
        print("%d rows failed" % bad)
        if bad:
            return 1
        if "--selftest" in sys.argv[1:]:
            holes = 0
            for i, (name, old, new) in enumerate(MUTANTS):
                if text.count(old) != 1:
                    print("  [FAIL] %s: the text to mutate matches %d times" % (name, text.count(old)))
                    holes += 1
                    continue
                mt = text.replace(old, new, 1)
                mexe = os.path.join(work, "m%d.exe" % i)
                ok, msg = build(work, mt, mexe)
                mwork = os.path.join(work, "m%d" % i)
                os.mkdir(mwork)
                caught = (not ok) or rows(mexe, mt, mwork, quiet=True) > 0
                print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, "" if caught else ": NOT CAUGHT"))
                holes += 0 if caught else 1
            print("self-test: %d mutants, %d not caught" % (len(MUTANTS), holes))
            return 1 if holes else 0
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
