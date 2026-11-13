#!/usr/bin/env python3
"""
test-gcatacl-units.py - win32_gcat_writable() (gplsrc/win32gcat.c) judges real access lists the way RELEASE_1.1 249 says.

    python sdb_ai/sd64/gplbld/test-gcatacl-units.py

Linux W.11 F2 (12615e80) refuses a global catalogue object that others or the group sdusers can write.  On Windows the
rights are a DACL, and win32gcat.c reads it.  This guard compiles a small probe around the real win32gcat.c with MSYS2's
gcc (the server's toolchain), makes scratch files, gives each an access list with icacls, and asks the probe about each:

    only SYSTEM, Administrators and this account          -> 0 (not writable by others)
    Users given (W), Authenticated Users (M), Everyone (F)  -> 1
    Everyone and Users given (RX) only                    -> 0 (reading is not writing)
    Users given (D) only (delete)                         -> 1
    sdusers given (RX) / (W), when the group exists       -> 0 / 1
    a file that does not exist                            -> 1 (fail closed)
    a file with no DACL at all (icacls /reset is not that; made with the probe's own --null-dacl) -> 1

THE CONTROL: the same probe built from a COPY of win32gcat.c whose sid_is_other() always answers 0 must call the Users (W)
file not writable; if it does not, the guard proves nothing and fails.  The copy is in a scratch folder; the tracked file is
compared by SHA-256 before and after.  Runs unelevated: this account keeps Full on its own scratch files, and it is a
single account, which the rule does not judge.  Exit 0 all held, 1 a check failed, 2 no MSYS2 gcc or no icacls (NO TREE).

13 Nov 26 - written with win32gcat.c (RELEASE_1.1 249).
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), 'gplsrc')
GCAT_C = os.path.join(SRC, 'win32gcat.c')
BASH = 'C:/msys64/usr/bin/bash.exe'

print('source  :', GCAT_C)
if not os.path.isfile(GCAT_C):
    print('NO TREE: no win32gcat.c'); sys.exit(2)
if not os.path.isfile(BASH) or shutil.which('icacls') is None:
    print('NO TREE: MSYS2 bash (%s) or icacls is missing' % BASH); sys.exit(2)

PROBE = r'''
#include <windows.h>
#include <aclapi.h>
#include <stdio.h>
#include <string.h>
#include "win32gcat.h"
int main(int argc, char **argv) {
  if (argc == 3 && strcmp(argv[1], "--null-dacl") == 0) {   /* give the file a NULL DACL, then judge it */
    if (SetNamedSecurityInfoA(argv[2], SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | UNPROTECTED_DACL_SECURITY_INFORMATION,
                              NULL, NULL, NULL, NULL) != ERROR_SUCCESS) { printf("SETFAIL\n"); return 3; }
    printf("%d\n", win32_gcat_writable(argv[2])); return 0;
  }
  printf("%d\n", win32_gcat_writable(argv[1]));
  return 0;
}
'''

def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()

def to_msys(p):
    p = p.replace('\\', '/')
    return '/' + p[0].lower() + p[2:] if len(p) > 1 and p[1] == ':' else p

def build(src_dir, out_exe):
    cmd = 'cd "%s" && gcc -O2 -Wall -I"%s" -o "%s" probe.c "%s" -ladvapi32' % (
        to_msys(work), to_msys(src_dir), to_msys(out_exe), to_msys(os.path.join(src_dir, 'win32gcat.c')))
    r = subprocess.run([BASH, '-lc', cmd], capture_output=True, text=True, env=dict(os.environ, MSYSTEM='MSYS'))
    if r.returncode != 0:
        print('BUILD FAILED:', r.stdout, r.stderr); sys.exit(1)

def icacls(path, *args):
    r = subprocess.run(['icacls', path] + list(args), capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip().splitlines()[0] if (r.stdout + r.stderr).strip() else ''

def ask(exe, *args):
    r = subprocess.run([exe] + list(args), capture_output=True, text=True)
    return r.stdout.strip()

before = sha(GCAT_C)
work = tempfile.mkdtemp(prefix='gcatacl-')
fails = 0
try:
    open(os.path.join(work, 'probe.c'), 'w').write(PROBE)
    exe = os.path.join(work, 'probe.exe')
    build(SRC, exe)
    me = os.environ.get('USERNAME', '')
    print('probe   :', exe, '  this account:', me)

    def case(label, grants, expect):
        global fails
        f = os.path.join(work, 'obj_%d' % abs(hash(label)))
        open(f, 'w').write('x')
        base = ['/inheritance:r', '/grant:r', '*S-1-5-18:F', '/grant:r', '*S-1-5-32-544:F', '/grant:r', '%s:F' % me]
        rc, msg = icacls(f, *(base + [a for g in grants for a in ('/grant:r', g)]))
        if rc != 0:
            print('FAIL  %-44s icacls refused: %s' % (label, msg)); fails += 1; return
        got = ask(exe, f)
        ok = got == str(expect)
        print('%s  %-44s grants %-34s -> %s (want %d)' % ('ok  ' if ok else 'FAIL', label, ' '.join(grants) or '(none)', got, expect))
        if not ok:
            fails += 1
        return f

    case('administrators, SYSTEM and this account only', [], 0)
    users_w = case('Users may write', ['*S-1-5-32-545:(W)'], 1)
    case('Authenticated Users may modify', ['*S-1-5-11:(M)'], 1)
    case('Everyone full', ['*S-1-1-0:F'], 1)
    case('Everyone and Users read and execute only', ['*S-1-1-0:(RX)', '*S-1-5-32-545:(RX)'], 0)
    case('Users may delete only', ['*S-1-5-32-545:(D)'], 1)
    if subprocess.run(['net', 'localgroup', 'sdusers'], capture_output=True).returncode == 0:
        case('sdusers read and execute only', ['sdusers:(RX)'], 0)
        case('sdusers may write', ['sdusers:(W)'], 1)
    else:
        print('skip  sdusers cases: there is no local group sdusers on this machine')

    got = ask(exe, os.path.join(work, 'no-such-file'))
    print('%s  %-44s -> %s (want 1)' % ('ok  ' if got == '1' else 'FAIL', 'a file that does not exist', got)); fails += got != '1'

    nf = os.path.join(work, 'obj_null'); open(nf, 'w').write('x')
    got = ask(exe, '--null-dacl', nf)
    print('%s  %-44s -> %s (want 1)' % ('ok  ' if got == '1' else 'FAIL', 'a file with no DACL at all', got)); fails += got != '1'

    # THE CONTROL: a copy that never recognises another user must miss the Users (W) file
    mdir = os.path.join(work, 'mutant'); os.mkdir(mdir)
    text = open(GCAT_C, encoding='latin-1').read()
    shutil.copy(os.path.join(SRC, 'win32gcat.h'), mdir)
    mut = text.replace('static int sid_is_other(PSID sid) {', 'static int sid_is_other(PSID sid) { return 0;', 1)
    if mut == text:
        print('FAIL  the mutant could not be made (sid_is_other() not found)'); fails += 1
    else:
        open(os.path.join(mdir, 'win32gcat.c'), 'w', encoding='latin-1').write(mut)
        mexe = os.path.join(work, 'mutant.exe')
        build(mdir, mexe)
        got = ask(mexe, users_w) if users_w else ''
        ok = got == '0'
        print('%s  %-44s -> %s (want 0: the guard can tell)' % ('ok  ' if ok else 'FAIL', 'CONTROL: mutant on the Users (W) file', got))
        fails += not ok
finally:
    for root, dirs, files in os.walk(work):
        for n in files:
            icacls(os.path.join(root, n), '/reset')
    shutil.rmtree(work, ignore_errors=True)

after = sha(GCAT_C)
if after != before:
    print('FAIL  win32gcat.c changed during the run'); fails += 1
print('win32gcat.c sha256 %s (unchanged: %s)' % (after[:16], after == before))
print('gcatacl: %s' % ('every case held' if fails == 0 else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
