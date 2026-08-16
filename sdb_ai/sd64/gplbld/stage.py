#
# stage.py - assemble the staging tree for a Windows install
#
# command line: python3 gplbld/stage.py [--stage DIR] [--msys DIR] [--force]
# eg  cd sdb_ai/sd64 && make sd && python3 gplbld/stage.py --stage ../../stage
#
# Produces two directories, which are what an install consists of:
#
#   <stage>/ProgramFiles/   ->  C:\Program Files\SD\
#   <stage>/ProgramData/    ->  C:\ProgramData\SD\
#
# THE usr/bin LAYOUT IS NOT COSMETIC.  The executables go in usr\bin, mirroring
# MSYS2's own tree, because shipping msys-2.0.dll beside sd.exe relocates the
# entire POSIX namespace: the runtime derives its root by stripping TWO path
# components from the directory holding the DLL.  Measured, not guessed - see
# the trap in PROJECT_STATUS.md 6.  So DLLs in C:\Program Files\SD\usr\bin put
# the root at C:\Program Files\SD\, and everything POSIX stays inside SD's own
# directory.  Put them one level up, in C:\Program Files\SD\bin, and the root
# becomes C:\Program Files\ - which would mean creating C:\Program Files\dev.
#
# etc\fstab then maps /dev/shm back out to C:\ProgramData\SD\shm.  It has to
# leave Program Files: shm_open() creates files under /dev/shm, so every SD
# user needs write access to it, and Program Files is read-only to ordinary
# users by design.  Without /dev/shm the runtime warns and POSIX shared memory
# fails, which is the whole IPC layer (5.1).
#
# and <stage>/MANIFEST.txt, which is deliberately outside both of them so that
# packaging never picks it up.  Diff two manifests to see what an install
# gained or lost between builds.
#
# This script does not build.  Run "make sd" first; it checks for the artefacts
# and stops if they are missing.  It does not install either - it only lays out
# a tree that the Inno Setup script packages.  See PROJECT_STATUS.md 5.9.
#
# WITH --bootstrap IT ALSO RUNS THE BOOTSTRAP, and that is what makes the tree
# installable.  Staged cold, gcat, cat, GPL.BP.OUT, BP.OUT and PCODE.OUT are
# empty, so the end user has to run the sequence in PROJECT_STATUS.md 3 - which
# needs Python, and needs gplbld/ inside the data tree that the
# data-tree-holds-data-only decision forbids.  It could not have worked anyway:
# gplbld/ was not staged at all, so the inputs were simply missing.  Running the
# bootstrap here and shipping the result means the end user needs neither Python
# nor a compiler, and installing is a file copy.  See PROJECT_STATUS.md 5.16.
#
# WHY THIS IS A WHITELIST.  Everything copied is named in SDSYS_SHIP or
# SDSYS_EMPTY below.  Nothing is copied because it happened to be in the source
# tree.  That is the point of the script rather than an implementation detail:
# the Linux installer did "cp -R" over whole directories, which is how gplsrc
# came to sit in the installed database for years without anyone asking why.
# If SD turns out to need something that is not on these lists, an install made
# from this tree fails and we learn what the dependency is.  Add it here
# deliberately, with a reason, or fix the dependency.
#
# The MSYS2 DLLs are the exception, and they are computed rather than listed -
# see dll_closure().  A hand-maintained list of DLLs goes stale silently and
# the symptom is exit code 53 with no message at all (PROJECT_STATUS.md 6).
#

import argparse
import os
import re
import shutil
import subprocess
import sys

# The bootstrap's own elevation test, imported rather than copied - gplbld is
# sys.path[0] whenever this script is run.  One test, one place: if the way
# elevation is measured ever changes, both callers change with it.
from bootstrap import is_elevated

# ---------------------------------------------------------------------------
# What goes into C:\Program Files\SD\
# ---------------------------------------------------------------------------

# Built by "make sd" into sd64/bin.  The DLLs these need are worked out by
# dll_closure() and land beside them, because Windows searches an executable's
# own directory before PATH - which is the only reliable answer to the two PATH
# traps in PROJECT_STATUS.md 6, one of which is Git for Windows shipping a
# rival msys-2.0.dll.
PROGRAM_FILES_BIN = [
    'sd.exe',
    'sdconv.exe',
    'sdfix.exe',
    'sdidx.exe',
    'sdwind.exe',
    'sdtic.exe',
    'sdclilib.dll',             # native UCRT64, needs no MSYS2 runtime
    'libsdclilib.dll.a',        # import library, for building clients
    'sdsvc.exe',                # native UCRT64, the service that starts SD
]

# Scanned for imports.  The client DLL and the service are deliberately not in
# this list: both are the separate native toolchain (5.3) and depend on nothing
# but Windows system DLLs, which was confirmed rather than assumed - objdump on
# sdsvc.exe, 15 Aug 2026, names only ADVAPI32, KERNEL32 and the UCRT
# api-ms-win-crt-* set, and no msys-2.0.dll.
DLL_SCAN = [
    'sd.exe', 'sdconv.exe', 'sdfix.exe', 'sdidx.exe', 'sdwind.exe', 'sdtic.exe',
]

# Where a DLL may legitimately come from.  Anything resolved outside these is
# taken to be a Windows system DLL and is reported, not copied.  libsodium is
# in /usr/local/bin because it is built from source (PROJECT_STATUS.md 2).
DLL_SEARCH = [
    os.path.join('usr', 'bin'),
    os.path.join('usr', 'local', 'bin'),
]

# ---------------------------------------------------------------------------
# What goes into C:\ProgramData\SD\sdsys\  - the SDSYS account
# ---------------------------------------------------------------------------

# Copied from sd64/sdsys.  Each entry says why it ships, because the next
# person to read this list will be deciding whether to remove something.
SDSYS_SHIP = [
    ('GPL.BP',        'BASIC source; SECOND.COMPILE compiles the lot of it'),
    ('SYSCOM',        'include records the compile needs'),
    # 15 Aug 26 - THESE TWO DESCRIPTIONS WERE THE WRONG WAY ROUND, and they are
    # the first thing read by anyone adding a verb.  VOC_TEMPLATE is the
    # ADMINISTRATIVE superset that becomes SDSYS's own VOC; NEWVOC is the
    # smaller set CREATEA copies into each new account (CREATEA:520).  The
    # difference is deliberate access control - CREATE.ACCOUNT, DELETE.ACCOUNT,
    # ACCOUNTS and FIRST.COMPILE are in VOC_TEMPLATE and NOT in NEWVOC, so an
    # ordinary account cannot reach them at all.  A new administrative verb
    # therefore goes in VOC_TEMPLATE ONLY; putting it in NEWVOC hands it to
    # every account SD creates.
    ('NEWVOC',        'the VOC a newly created account is given'),
    ('VOC_TEMPLATE',  "the administrative superset; becomes SDSYS's own VOC"),
    ('MESSAGES',      'sysmsg() text'),
    ('SD.VOCLIB',     'library routines'),
    ('ACCOUNTS',      'holds the SDSYS record; the bootstrap adds to it'),
    ('BP',            'SDSYS BP - see the note in the header about tests'),
    ('changelog',     'ships with the system by standing instruction'),
    ('licence',       'GPL-3.0'),
    ('contrib',       'contributor list, reachable as CONFIG CONTRIB'),
]

# Created empty, and filled by the bootstrap when --bootstrap is given.  Their
# README placeholders are not shipped - that would put files in a database.
SDSYS_EMPTY = [
    ('GPL.BP.OUT',  'compiled objects from SECOND.COMPILE'),
    ('BP.OUT',      'compiled objects from the SDSYS BP'),
    ('gcat',        'global catalogue; the bootstrap touches $CPROC here first'),
    ('cat',         'private catalogue'),
    ('PCODE.OUT',   'pcode_bld.py output'),
    ('$HOLD',       'spooler hold file'),
    ('prt',         'print queue'),
    ('bin',         'NOT the executables - the pcode library lives here, see below'),
]

# sd64/terminfo is generated by "make terminfo" and is not tracked, so it is
# staged from wherever it was built.  terminfo.src ships with it so that sdtic
# can add a terminal type on an installed system; it is 64K.
TERMINFO_DIRS = [('terminfo', 'compiled terminfo, 99 files')]
TERMINFO_FILES = [('terminfo.src', 'source, so sdtic is usable after install')]

# Directories the bootstrap and the running system create for themselves, listed
# so nobody adds them to SDSYS_EMPTY on the assumption they were forgotten:
#   stacks  DIR_DICT  VOC  VOC.DIC  DICT.DIC  ACCOUNTS.DIC  $MAP  $MAP.DIC
#   $IPC  $CRED  $CRED.DIC  errlog

# Empty account roots.  Three siblings under one root is what makes a single
# icacls with inheritance enough (PROJECT_STATUS.md 5.8).  "shm" is the fourth,
# and it is the target of the fstab mapping above rather than an account.
PROGRAM_DATA_DIRS = ['user_accounts', 'group_accounts', 'shm']

# Where the binaries sit inside C:\Program Files\SD\.  Two components, so the
# MSYS2 POSIX root lands on C:\Program Files\SD\ - see the header.
PF_BIN_SUBDIR = os.path.join('usr', 'bin')

# Where the data tree lives once installed.  The bootstrap is run against the
# staging directory rather than here - a build must not depend on, or write to,
# the build machine's own installed system - so the SDSYS account record comes
# out holding the staging path and is rewritten to this afterwards.  That is
# safe because ACCOUNTS/SDSYS is the ONLY place an absolute path is embedded,
# and stage.py proves it rather than trusting it: see check_no_stage_paths().
PRODUCTION_SDSYS = r'C:\ProgramData\SD\sdsys'

# Field 1 of an ACCOUNTS record is the account's directory.
#
# ACCOUNTS is a DIRECTORY-type SD file, so each record is a plain text file and
# its field marks are NEWLINES, not the \xfe field mark used inside a DH file.
# Splitting on \xfe finds nothing, leaves the whole record as field 1, and
# rewriting it then flattens the record to one line - silently discarding every
# field after the path, the account's Windows group among them.  Verified
# against the bytes on disk rather than assumed, after doing exactly that once.
FM = '\n'

# /dev/shm must be writable by every SD user, so it cannot live under Program
# Files.  Cygwin reads <root>\etc\fstab, and a bind entry moves it.
FSTAB = ('# Generated by gplbld/stage.py.  See PROJECT_STATUS.md 5.8.\n'
         '#\n'
         '# /dev/shm must be writable by every SD user - shm_open() creates\n'
         '# files in it - and Program Files is not.  Without this mapping the\n'
         '# runtime warns that /dev/shm is missing and all POSIX shared memory\n'
         '# fails, which is the whole IPC layer.\n'
         'C:/ProgramData/SD/shm /dev/shm ntfs binary 0 0\n')

SD_CONF = """[sd]
SDSYS=C:\\ProgramData\\SD\\sdsys
GRPSIZE=2
NUMUSERS=20
SORTMEM=4096
ERRLOG=50
APILOGIN=1
USRDIR=C:\\ProgramData\\SD\\user_accounts
GRPDIR=C:\\ProgramData\\SD\\group_accounts
SH=C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NoLogo
SH1=C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
"""


# ---------------------------------------------------------------------------


def check_no_stage_paths(stage, sdsys, allowed):
    r"""After the bootstrap, no file in the staged tree may mention the staging
    directory except the ones we know rewrite cleanly.

    This is the invariant the whole pre-bootstrap idea rests on.  Bootstrapping
    here rather than at C:\ProgramData\SD\sdsys means anything that recorded
    an absolute path recorded the WRONG one, and only ACCOUNTS/SDSYS is known
    to do that.  "Known" was a sweep somebody did once, which is exactly the
    kind of claim that quietly stops being true - so it is checked on every
    build instead.  If this fires, do not add the file to `allowed` without
    working out whether the path can be rewritten as safely.
    """
    needles = [stage, os.path.abspath(stage)]
    needles += [n.replace(os.sep, '/') for n in list(needles)]
    needles = sorted({n.lower() for n in needles if n})

    offenders = []
    for base, _dirs, names in os.walk(sdsys):
        for n in names:
            path = os.path.join(base, n)
            if os.path.relpath(path, sdsys).replace(os.sep, '/') in allowed:
                continue
            try:
                with open(path, 'rb') as f:
                    blob = f.read().decode('latin-1').replace('\\', '/').lower()
            except (IOError, OSError):
                continue
            if any(nd in blob for nd in needles):
                offenders.append(os.path.relpath(path, sdsys))
    return offenders


def retarget_sdsys_account(sdsys, production):
    """Point the SDSYS ACCOUNTS record at a directory, and return the old one.

    Field 1 of an ACCOUNTS record is the account directory, and IT IS WHERE
    GPL.BP AND GPL.BP.OUT RESOLVE TO once a session has logged in.  So this is
    called TWICE: at the staged tree before the bootstrap, or the bootstrap
    compiles somebody else's sources, and at the production path afterwards, so
    the install does not carry a build path.  Rewriting one field is the entire
    cost of pre-bootstrapping - see PROJECT_STATUS.md 5.16.

    The tracked record ships holding /usr/local/sdsys, the Linux development
    tree, which is what made the first call necessary: on this machine the
    bootstrap silently compiled 190 programs there and catalogued them into the
    staged gcat, and on a clean machine that path does not exist at all.
    """
    rec = os.path.join(sdsys, 'ACCOUNTS', 'SDSYS')
    if not os.path.isfile(rec):
        die('there is no ACCOUNTS/SDSYS record in %s' % sdsys)
    with open(rec, 'rb') as f:
        fields = f.read().decode('latin-1').split(FM)
    was = fields[0]
    fields[0] = production
    with open(rec, 'wb') as f:
        f.write(FM.join(fields).encode('latin-1'))
    return was


class Staged(object):
    """Records what was written, so the manifest and the summary agree with the
    tree rather than with what the script meant to do."""

    def __init__(self):
        self.files = []

    def add(self, root, path):
        self.files.append((os.path.relpath(path, root).replace('\\', '/'),
                           os.path.getsize(path)))

    def scan(self, root, path):
        for base, _dirs, names in os.walk(path):
            for n in sorted(names):
                self.add(root, os.path.join(base, n))


def die(msg):
    sys.exit('stage: ' + msg)


def imports_of(objdump, path):
    """Direct DLL imports of one PE file.  objdump -p is used rather than ldd
    because it reads the import table instead of loading the binary: it gives
    the same answer on a machine that could not run it, and it does not depend
    on the loader's search order."""
    out = subprocess.run([objdump, '-p', path], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, universal_newlines=True)
    return re.findall(r'^\tDLL Name:\s*(\S+)', out.stdout, re.M)


def dll_closure(objdump, binaries, msys_root):
    """Walk imports transitively.  Direct imports are not enough: sd.exe names
    five DLLs, but msys-intl-8, msys-iconv-2 and msys-gcc_s-seh-1 arrive only
    through the DLLs it does name, and missing one of those is exit code 53
    with no message."""
    search = [os.path.join(msys_root, d) for d in DLL_SEARCH]
    for d in search:
        if not os.path.isdir(d):
            die('no such directory %s - is --msys right?' % d)

    found, system, pending, seen = {}, set(), list(binaries), set()
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        for name in imports_of(objdump, path):
            if name.lower() in found or name.lower() in system:
                continue
            for d in search:
                cand = os.path.join(d, name)
                if os.path.isfile(cand):
                    found[name.lower()] = cand
                    pending.append(cand)
                    break
            else:
                system.add(name.lower())        # Windows supplies it
    return found, system


def copy_tree(src, dst, staged, stage_root):
    shutil.copytree(src, dst)
    staged.scan(stage_root, dst)


def main():
    ap = argparse.ArgumentParser(
        description='Assemble the staging tree for a Windows install.')
    ap.add_argument('--stage', default='stage',
                    help='directory to build (default: stage)')
    ap.add_argument('--msys', default=r'C:\msys64',
                    help=r'MSYS2 installation (default: C:\msys64)')
    ap.add_argument('--force', action='store_true',
                    help='delete an existing staging directory first')
    ap.add_argument('--bootstrap', action='store_true',
                    help='run the bootstrap against the staged tree, so the '
                         'install needs neither Python nor a compiler')
    args = ap.parse_args()

    # bootstrap.py refuses an unelevated window, and by the time it gets the
    # chance this script has already copied several thousand files.  Ask the
    # same question before doing any of that work.  Staging on its own needs no
    # elevation at all, so only --bootstrap is gated.
    if args.bootstrap and not is_elevated():
        die('--bootstrap needs an ELEVATED window: it ends in "sd -internal"\n'
            '  steps that SDSYS refuses to an unelevated session\n'
            '  (PROJECT_STATUS.md section 5.6).  Start the shell with "Run as\n'
            '  administrator", or drop --bootstrap to stage a cold tree.')

    if not os.path.isdir('gplsrc') or not os.path.isdir('sdsys'):
        die('run this from sd64 - gplsrc and sdsys are not here')

    objdump = os.path.join(args.msys, 'usr', 'bin', 'objdump.exe')
    if not os.path.isfile(objdump):
        die('no objdump at %s - is --msys right?' % objdump)

    missing = [f for f in PROGRAM_FILES_BIN if not os.path.isfile(
        os.path.join('bin', f))]
    if missing:
        die('bin/ is missing %s - run "make sd" first'
            % ', '.join(sorted(missing)))
    if not os.path.isdir('terminfo'):
        die('terminfo/ has not been generated - run "make terminfo" first')

    stage = args.stage
    if os.path.exists(stage):
        if not args.force:
            die('%s exists - pass --force to replace it' % stage)
        shutil.rmtree(stage)

    pf = os.path.join(stage, 'ProgramFiles')
    pfbin = os.path.join(pf, PF_BIN_SUBDIR)
    pd = os.path.join(stage, 'ProgramData')
    sdsys = os.path.join(pd, 'sdsys')
    os.makedirs(pfbin)
    os.makedirs(sdsys)
    staged = Staged()

    # --- C:\Program Files\SD\ ---------------------------------------------

    for f in PROGRAM_FILES_BIN:
        dst = os.path.join(pfbin, f)
        shutil.copy2(os.path.join('bin', f), dst)
        staged.add(stage, dst)

    dlls, system = dll_closure(
        objdump, [os.path.join('bin', f) for f in DLL_SCAN], args.msys)
    for name in sorted(dlls):
        dst = os.path.join(pfbin, os.path.basename(dlls[name]))
        shutil.copy2(dlls[name], dst)
        staged.add(stage, dst)

    fstab = os.path.join(pf, 'etc', 'fstab')
    os.makedirs(os.path.dirname(fstab))
    with open(fstab, 'w', encoding='latin-1', newline='\n') as f:
        f.write(FSTAB)
    staged.add(stage, fstab)

    # Scripts the installer runs.  They ship as FILES rather than as inline
    # [Run] parameters because an inline parameter is exactly where the OpenSSH
    # brace bug hid for its whole life (PROJECT_STATUS.md 6) - a file can be
    # read and parse-checked on its own.  Missing one is a build failure, not a
    # warning: the installer would otherwise silently skip the step.
    here = os.path.dirname(os.path.abspath(__file__))
    for script in ('deny-logon.ps1', 'install-ssh.ps1', 'allow-ssh-groups.ps1',
                   'adopt-account.ps1', 'install-service.ps1'):
        src = os.path.join(here, script)
        if not os.path.exists(src):
            raise SystemExit('missing %s - the installer needs it' % src)
        dst = os.path.join(pf, script)
        shutil.copy2(src, dst)
        staged.add(stage, dst)

    # --- C:\ProgramData\SD\ -----------------------------------------------

    conf = os.path.join(pd, 'sd.conf')
    with open(conf, 'w', encoding='latin-1', newline='\r\n') as f:
        f.write(SD_CONF)
    staged.add(stage, conf)

    for d in PROGRAM_DATA_DIRS:
        os.makedirs(os.path.join(pd, d))

    for name, _why in SDSYS_SHIP:
        src = os.path.join('sdsys', name)
        if not os.path.exists(src):
            die('sdsys/%s is on the ship list but is not in the tree' % name)
        dst = os.path.join(sdsys, name)
        if os.path.isdir(src):
            copy_tree(src, dst, staged, stage)
        else:
            shutil.copy2(src, dst)
            staged.add(stage, dst)

    for name, _why in SDSYS_EMPTY:
        os.makedirs(os.path.join(sdsys, name))

    for name, _why in TERMINFO_DIRS:
        copy_tree(name, os.path.join(sdsys, name), staged, stage)
    for name, _why in TERMINFO_FILES:
        dst = os.path.join(sdsys, name)
        shutil.copy2(name, dst)
        staged.add(stage, dst)

    # --- bootstrap ---------------------------------------------------------

    if args.bootstrap:
        # A configuration of its own, kept OUTSIDE both install roots so it is
        # never packaged, naming the staging tree rather than the production
        # path.  The build must not read or write the build machine's own
        # installed system.
        bconf = os.path.join(stage, 'bootstrap-sd.conf')
        with open(bconf, 'w', encoding='latin-1', newline='\r\n') as f:
            f.write(SD_CONF.replace('SDSYS=' + PRODUCTION_SDSYS,
                                    'SDSYS=' + os.path.abspath(sdsys)))

        # The account directory has to name the staged tree BEFORE the
        # bootstrap logs in - see retarget_sdsys_account().
        shipped = retarget_sdsys_account(sdsys, os.path.abspath(sdsys))
        print('  ACCOUNTS/SDSYS pointed at the staged tree')
        print('    was %s' % shipped)

        print('bootstrapping the staged tree')
        r = subprocess.run(
            [sys.executable,
             os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          'bootstrap.py'),
             '--sysdir', os.path.abspath(sdsys),
             '--sd', os.path.abspath(os.path.join(pfbin, 'sd.exe')),
             '--conf', bconf])
        if r.returncode != 0:
            die('the bootstrap failed; the staged tree is not installable')

        os.remove(bconf)

        was = retarget_sdsys_account(sdsys, PRODUCTION_SDSYS)
        print('  ACCOUNTS/SDSYS retargeted')
        print('    from %s' % was)
        print('    to   %s' % PRODUCTION_SDSYS)

        offenders = check_no_stage_paths(stage, sdsys,
                                         allowed={'ACCOUNTS/SDSYS', 'errlog'})
        if offenders:
            print('  these staged files still name the staging directory:')
            for o in sorted(offenders)[:20]:
                print('    %s' % o)
            die('the staged tree would carry build paths into an install - '
                'see check_no_stage_paths() and PROJECT_STATUS.md 5.16')
        print('  checked: nothing else embeds the build path')

        # errlog is the bootstrap's own diagnostic output, not install data.
        el = os.path.join(sdsys, 'errlog')
        if os.path.isfile(el):
            os.remove(el)

        # The tree gained a great deal; rebuild the record from what is there.
        staged.files = []
        staged.scan(stage, pf)
        staged.scan(stage, pd)

    # --- manifest and summary ---------------------------------------------

    staged.files.sort()
    total = sum(size for _p, size in staged.files)
    with open(os.path.join(stage, 'MANIFEST.txt'), 'w',
              encoding='latin-1', newline='\n') as f:
        for path, size in staged.files:
            f.write('%10d  %s\n' % (size, path))

    print('staged %s' % os.path.abspath(stage))
    if not args.bootstrap:
        print('  NOT bootstrapped - this tree is not installable on its own.')
        print('  Pass --bootstrap unless you meant to build a cold tree.')
    print('  %d files, %.1f MB' % (len(staged.files), total / 1048576.0))
    print('  binaries in %s, so the POSIX root is the SD directory'
          % os.path.join('ProgramFiles', PF_BIN_SUBDIR))
    print('  MSYS2 DLLs copied: %s'
          % ' '.join(sorted(os.path.basename(p) for p in dlls.values())))
    print('  supplied by Windows, not copied: %s' % ' '.join(sorted(system)))
    # Embedded Python was dropped on 13 Aug 2026 (PROJECT_STATUS.md 5.15), which
    # is what removed the only dependency this script could not resolve - the
    # 195 MB standard library that msys-python3.12.dll would have needed.  If a
    # python DLL ever reappears in the closure, that question is back.
    python_dlls = [n for n in dlls if 'python' in n]
    if python_dlls:
        print('  WARNING: %s is in the closure, but embedded Python was'
              % ' '.join(sorted(python_dlls)))
        print('           removed in 5.15.  Something re-enabled it, and the')
        print('           standard library is not staged.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
