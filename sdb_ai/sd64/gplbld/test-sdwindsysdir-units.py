#!/usr/bin/env python3
"""
test-sdwindsysdir-units.py - sdwind takes the system directory from the configuration file, and stops when it cannot (RELEASE_1.1 249).

    python sdb_ai/sd64/gplbld/test-sdwindsysdir-units.py

Linux W.11 F1 (12615e80): the root daemon stopped taking the system directory from the shared segment, which any member of
sdusers can write.  sdwind (LocalSystem here) now reads SDSYS= from the [sd] section of the configuration file
(own_sysdir(), sdwind.c) before it touches anything else, and exits 3 with a line on stderr when there is none.

This guard compiles sdwind as the Makefile links it (MSYS2 gcc, into a scratch folder) and runs it with SD_CONFIG pointing at
scratch files that must each be REFUSED: no such file; a file with no [sd] section; SDSYS= only in another section; an [sd]
section whose SDSYS= is empty.  Each must exit 3 and print the refusal, before the daemon attaches to anything.
THE SUCCESS PATH IS NOT RUN HERE ON PURPOSE: past own_sysdir() the daemon attaches to the shared segment, and on a machine
with SD installed that is the live one.  It is witnessed by SD starting at all after the cycle (sdwind is what the service
starts).  As a control, the source is checked to call own_sysdir() before signal() and to open errlog from own_sysdir_path.
Exit 0 all held, 1 a check failed, 2 no MSYS2 gcc (NO TREE).

13 Nov 26 - written with the sdwind change.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
SRC = os.path.join(SD64, 'gplsrc')
BASH = 'C:/msys64/usr/bin/bash.exe'
OBJS = ['sdwind', 'sdsem', 'win32sem', 'win32peer', 'exepath', 'inipath']
FLAGS = ('-std=gnu17 -Wall -Wformat=2 -Wno-format-nonliteral -D_FILE_OFFSET_BITS=64 -Igplsrc -I/usr/local/include -DGPL -g '
         '-O2 -fwrapv -fno-strict-aliasing -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fstack-protector-strong')

if not os.path.isfile(BASH):
    print('NO TREE: no MSYS2 bash at', BASH); sys.exit(2)

def msys(p):
    p = p.replace('\\', '/')
    return '/' + p[0].lower() + p[2:] if len(p) > 1 and p[1] == ':' else p

fails = 0
src = open(os.path.join(SRC, 'sdwind.c'), encoding='latin-1').read()
main = src[src.find('int main()'):]
order_ok = 0 <= main.find('own_sysdir()') < main.find('signal(SIGTERM')
log_ok = re.search(r'snprintf\(buff, BUFF_SIZE, "%s%cerrlog", own_sysdir_path, DS\)', src) is not None
for label, ok in (('own_sysdir() runs before anything else in main()', order_ok),
                  ('the error log is opened from own_sysdir_path, bounded', log_ok)):
    print('%s  %s' % ('ok  ' if ok else 'FAIL', label)); fails += not ok

work = tempfile.mkdtemp(prefix='sdwindsys-')
try:
    exe = os.path.join(work, 'sdwind.exe')
    cmd = 'cd "%s" && ' % msys(SD64)
    cmd += ' && '.join('gcc %s -c gplsrc/%s.c -o "%s/%s.o"' % (FLAGS, o, msys(work), o) for o in OBJS)
    cmd += ' && gcc -lc %s -ladvapi32 -liphlpapi -o "%s"' % (' '.join('"%s/%s.o"' % (msys(work), o) for o in OBJS), msys(exe))
    r = subprocess.run([BASH, '-lc', cmd], capture_output=True, text=True, env=dict(os.environ, MSYSTEM='MSYS'))
    print('build   : exit %d, %s' % (r.returncode, exe))
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:]); sys.exit(1)

    cases = [
        ('no configuration file', None),
        ('no [sd] section', '[other]\nSDSYS=C:\\x\n'),
        ('SDSYS= only in another section', '[sd]\nNUMUSERS=20\n[other]\nSDSYS=C:\\x\n'),
        ('an empty SDSYS=', '[sd]\nSDSYS=\n'),
    ]
    for label, text in cases:
        conf = os.path.join(work, 'sd.conf.%d' % len(label))
        if text is not None:
            open(conf, 'w').write(text)
        env = dict(os.environ, SD_CONFIG=conf)
        try:
            p = subprocess.run([exe], capture_output=True, text=True, env=env, timeout=20)
            rc, err = p.returncode, p.stderr.strip()
        except subprocess.TimeoutExpired:
            rc, err = 'TIMEOUT', ''
        ok = (rc == 3) and ('cannot find the system directory' in err)
        print('%s  %-34s SD_CONFIG=%s -> exit %s, stderr: %s' % ('ok  ' if ok else 'FAIL', label, conf, rc, err[:90]))
        fails += not ok
finally:
    shutil.rmtree(work, ignore_errors=True)

print('sdwindsysdir: %s' % ('every case held' if fails == 0 else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
