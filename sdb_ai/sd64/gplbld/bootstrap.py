#
# bootstrap.py - bring a fresh SDSYS tree up to a working system
#
# command line: python3 gplbld/bootstrap.py --sysdir DIR --sd PATH [--conf PATH]
#
# This is the sequence in PROJECT_STATUS.md section 3, which until now existed
# only as prose there and as line numbers in installsdai.sh.  Prose cannot be
# run, and this is the one part of the install nobody had exercised (section 4).
#
# WHY IT IS RUN AT BUILD TIME.  gplbld/stage.py used to stage gcat, cat,
# gpl.bp.out, bp.out and pcode.out empty, which left the end user to run all of
# this on their own machine - needing Python, and needing gplbld/ in the data
# tree, which the data-tree-holds-data-only decision forbids.  So the bootstrap
# happens here, on the build machine, and the installer ships the result.  The
# end user then needs neither Python nor a compiler.  See PROJECT_STATUS.md
# 5.16, which also records the rule that settled it: where Linux parity and the
# Inno installer conflict, the installer wins.
#
# TWO STEPS LOOK WRONG AND ARE NOT, and both cost a previous session real time:
#
#   * The empty gcat/$cproc placeholder is what lets "sd -start" run before
#     anything is catalogued.  read_config() only does access(path, 0) on it,
#     so an empty file satisfies the check and the last step overwrites it with
#     the real object.  There is no ordering deadlock here, however much it
#     looks like one.
#     14 Sep 26 - LOWER CASE, RELEASE_1.1 5 stage 3a, and the case matters even
#     on NTFS: a file written over an existing one keeps the OLD name's case,
#     so an upper-case placeholder would leave the real object named $CPROC.
#
#   * "sd -start" comes before "sd -i", not after.
#
# NO PASSWORD IS NEEDED OR SET.  On a fresh tree SDSYS has no credential yet,
# and LOGIN admits an administrator to an account with no verifier, with a
# warning.  That is what lets the whole sequence run unattended.  Setting the
# SDSYS password is the installer's job and must be its LAST step - see
# PROJECT_STATUS.md 7 step 3.
#
# IT NEEDS AN ELEVATED WINDOW, AND IT SAYS SO BEFORE IT STARTS.  The four
# "sd -internal" steps below name SDSYS for themselves in sd.c, and since
# 14 Aug 2026 LOGIN refuses SDSYS to a session that is not elevated
# (PROJECT_STATUS.md 5.6), so unelevated the run dies in the middle of a slow
# build rather than at the door.  Note that line 195 below already records the
# PREVIOUS login change breaking this same sequence, unnoticed for the same
# reason: nobody re-runs the bootstrap, so it rots silently.
#

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

# Run by bbcmp.py before there is a compiler.  Order matters: BBPROC is the
# bootstrap paragraph processor, BCOMP the compiler it needs, PATHTKN the
# pathname tokeniser both rely on.
BBCMP_FIRST = ['bbproc', 'bcomp', 'pathtkn']

# BUILTIN\Administrators by RID, never by name - the same choice, for the same
# reason, as SD_ADMIN_GID in gplsrc/linuxlb.c.  Cygwin maps a built-in SID to
# its RID, so S-1-5-32-544 is always gid 544, while the NAME is translated on a
# localised Windows.
SD_ADMIN_GID = 544

# 20 Sep 26 - RELEASE_1.1 82 (D2').  LOGIN admits an "sd -internal" session only
# against a one-shot marker file in the SDSYS directory, and deletes it on
# admission.  sd() below writes one immediately before EVERY internal session
# (this script runs four) and removes it afterwards in case sd never consumed it.
# Set by main() once the SDSYS directory is known; None means "not set", and sd()
# then writes nothing - which is exactly how a session started before main() has
# resolved the tree would fail, loudly, at the gate.
#
# THE CONTRACT WITH LOGIN is shared with gplbld/internal-marker.ps1 and checked by
# test-internalgate-units.py: the file is named $internal, line 1 is "<writer>
# pid=<pid> <time>", ASCII, no BOM, and LOGIN refuses one older than 10 minutes.
INTERNAL_MARKER_DIR = None

# Field mark in a stored record, as gplbld/stage.py also has it.
FM = '\n'

# Copied into the sysdir for the bootstrap and removed afterwards.  gpl.bp/
# WRITE_INSTALL_DICTS reads its input as @sdsys:"/gplbld/FILES_DICTS", so the
# file has to be inside the data tree while it runs - and must not still be
# there when the tree ships.  This is the whole of the "gplbld in the data
# tree" problem: it is a build input, not data.
BOOTSTRAP_ONLY = [('FILES_DICTS', os.path.join('gplbld', 'FILES_DICTS'))]


def die(msg):
    sys.exit('bootstrap: ' + msg)


def is_elevated():
    """Is this process running with an elevated token?

    The same question gplsrc/linuxlb.c IsElevated() asks, asked the same way.
    UAC hands an unelevated administrator a filtered token carrying
    BUILTIN\\Administrators as "group used for deny only", and Cygwin omits a
    deny-only group from getgroups(), so the gid's ABSENCE is the elevation
    test.  Measured with this Python on 15 Aug 2026: an ordinary session
    reports no 544.

    MSYS2 Python is a Cygwin build - os.name is "posix" and there is no
    ctypes.windll to ask Windows with - so the group route is the only one
    available there, and it is also the one that agrees with the C.  A native
    Windows Python has no getgroups() at all and asks Windows instead.
    """
    if os.name == 'nt':
        import ctypes
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    return SD_ADMIN_GID in os.getgroups()


def check_account_record(sysdir):
    """Refuse to bootstrap a tree whose SDSYS account points somewhere else.

    Field 1 of accounts/sdsys is the account directory, and once a session has
    logged in it is what gpl.bp and gpl.bp.out resolve to - the gcat comes from
    the config file, the sources do not.  The tracked record ships naming
    /usr/local/sdsys, the Linux development tree, and on 15 Aug 2026 a run
    against it compiled 190 programs THERE and catalogued them into the staged
    tree: a staged gcat holding 13 Aug objects, with no symptom until somebody
    installed it.  Cheap to check, expensive to find.
    """
    rec = os.path.join(sysdir, 'accounts', 'sdsys')
    if not os.path.isfile(rec):
        die('no accounts/sdsys record in %s' % sysdir)
    with open(rec, 'rb') as f:
        acctdir = f.read().decode('latin-1').split(FM)[0]
    if not os.path.isdir(acctdir) or not os.path.samefile(acctdir, sysdir):
        die('accounts/sdsys names %s, but this bootstrap is for\n'
            '  %s.  Field 1 is the SDSYS account directory, and gpl.bp and\n'
            '  gpl.bp.out resolve through it, so the compile would read and\n'
            '  write there instead.  gplbld/stage.py sets this before calling;\n'
            '  set it yourself if you are running bootstrap.py by hand.'
            % (acctdir or '(empty)', sysdir))


def run(cmd, **kw):
    """Run a build tool, failing loudly.  Output is shown rather than captured:
    when this goes wrong the compiler's own message is the useful part."""
    print('    $ ' + ' '.join(str(c) for c in cmd))
    r = subprocess.run(cmd, **kw)
    if r.returncode != 0:
        die('%s failed with %d' % (cmd[0], r.returncode))
    return r


# 4 Nov 26 - THE STAGED sd.exe IS STARTED THROUGH cmd.exe, NOT DIRECTLY.
#
# It loads the msys-2.0.dll staged beside it, while this script runs under
# MSYS2's own copy in C:\msys64.  On the second Windows development machine
# (WIN, Windows 25H2 build 26200, MSYS2 runtime 3.6.12) an MSYS2 program that
# starts a program loading a SECOND copy of the runtime gets exit 127 with no
# output - so "sd -start" failed at once and cycle.ps1 stopped at step 2.  The
# reference machine (ACE, 26H2 build 26300, runtime 3.6.9) does not.  Measured
# on WIN with P:\setupdevbox\cross-root-test.ps1 (a copy of true.exe beside its
# own msys-2.0.dll): 127 from MSYS2's bash in the Remote Desktop session AND in
# session 0, 127 with runtime 3.6.9-2 as well as 3.6.12, 0 from Git Bash, from
# PowerShell, and through cmd.exe.  The cause is not found; the Windows build
# is the remaining difference.  A native program in between makes sd.exe a
# fresh process, which is how the installed service starts it anyway, so the
# hop is taken on every machine rather than only where it is needed.
#
# THE WORDS GO ON A cmd.exe COMMAND LINE, so each is held to characters cmd
# gives no meaning to.  Every caller passes plain words (-start, -internal,
# SECOND.COMPILE, gpl.bp ...); one that does not is refused by name rather than
# quoted and hoped for.  SD_CONFIG is handed over in Windows form by this script
# rather than left to MSYS2's guess at which variables are paths.
_HOP_SAFE = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
                '0123456789:._-/' + chr(92))


def _cygpath(flag, path):
    r = subprocess.run(['cygpath', flag, path], stdout=subprocess.PIPE)
    out = r.stdout.decode('latin-1').strip()
    if r.returncode != 0 or not out:
        die('cygpath %s %s failed (exit %d)' % (flag, path, r.returncode))
    return out


def native_hop(sdexe, env, args):
    """The command and environment that start sd.exe through cmd.exe."""
    if os.name == 'nt':
        return [sdexe] + list(args), env
    words = [_cygpath('-w', sdexe)] + list(args)
    bad = [w for w in words if not w or set(w) - _HOP_SAFE]
    if bad:
        die('cannot pass %r through cmd.exe safely - it holds a character\n'
            '  cmd.exe would interpret.  Every sd() caller passes plain words;\n'
            '  see native_hop() before adding one that does not.' % bad[0])
    env = dict(env)
    if env.get('SD_CONFIG', '').startswith('/'):
        env['SD_CONFIG'] = _cygpath('-w', env['SD_CONFIG'])
    comspec = _cygpath('-u', os.path.join(
        env.get('SYSTEMROOT') or env.get('SystemRoot') or 'C:' + chr(92) + 'Windows',
        'System32', 'cmd.exe'))
    # //d //c, NOT /d /c: MSYS2 rewrites a "/x" argument to a native program
    # as a drive path, and a doubled slash is its documented escape.  With "/c"
    # cmd.exe got no command, started interactively, read the "\n" sd() feeds,
    # and exited 0 - sd.exe never ran and the exit code said success (found by
    # the first test of this hop, 4 Nov 2026).
    return [comspec, '//d', '//c'] + words, env


# 4 Nov 26 - RELEASE_1.1 193, PART 2: THE STAGED RUNTIME IS GIVEN "/c/..." FOR
# THE BOOTSTRAP ONLY.  Started as a fresh process (native_hop), the staged
# sd.exe builds its mount table from the STAGED etc/fstab, which has no cygdrive
# line, so drives are /cygdrive/c/... there - and SDSYS in the bootstrap's
# sd.conf, and field 1 of accounts/sdsys, say /c/Users/....  First cycle with
# the hop: "Global catalogue missing or corrupt" (config.c, access() on
# <sysdir>/gcat/$cproc, which existed).  Measured with a copy of the staged
# runtime: "ls /c/..." not found, "/cygdrive/c/..." and "C:/..." found.
# Started as MSYS2 python's child, as it was on ACE, it saw "/c/" paths, so
# MSYS2's own cygdrive line is added for the bootstrap and the file is put back
# byte for byte afterwards (created and removed where the tree ships none, as
# Solo's does not): nothing the bootstrap writes changes, and the shipped
# fstab - so the installed product - is untouched.
CYGDRIVE_LINE = b'none / cygdrive binary,posix=0,noacl,user 0 0\n'


def add_bootstrap_cygdrive(sdexe):
    """Add MSYS2's cygdrive line to the staged fstab; return what undoes it."""
    if os.name == 'nt':
        return None
    etc = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(sdexe))), 'etc')
    fstab = os.path.join(etc, 'fstab')
    made_etc = not os.path.isdir(etc)
    original = None
    if os.path.exists(fstab):
        with open(fstab, 'rb') as f:
            original = f.read()
        if b' cygdrive ' in original:
            print('  staged fstab already has a cygdrive line - left as it is')
            return None
    if made_etc:
        os.makedirs(etc)
    body = original or b''
    if body and not body.endswith(b'\n'):
        body += b'\n'
    with open(fstab, 'wb') as f:
        f.write(body + b'# bootstrap.py - for the bootstrap only, removed after\n'
                + CYGDRIVE_LINE)
    print('  staged fstab: cygdrive "/" added for the bootstrap (%s, %s)'
          % (fstab, 'was %d bytes' % len(original) if original is not None
             else 'created'))
    return (fstab, original, etc if made_etc else None)


def restore_bootstrap_fstab(undo):
    """Put the staged fstab back exactly as it was, and prove it."""
    if undo is None:
        return
    fstab, original, made_etc = undo
    if original is None:
        os.remove(fstab)
        if made_etc:
            os.rmdir(made_etc)
        if os.path.exists(fstab):
            die('could not remove the bootstrap-only %s' % fstab)
        print('  staged fstab: removed again (the tree ships none)')
        return
    with open(fstab, 'wb') as f:
        f.write(original)
    with open(fstab, 'rb') as f:
        if f.read() != original:
            die('%s is not back to its original bytes - the staged tree\n'
                '  would ship the bootstrap-only cygdrive line' % fstab)
    print('  staged fstab: restored, %d bytes, identical' % len(original))


def sd(sdexe, env, args, expect_fail=False):
    """Run one SD command.

    Input is piped, never redirected from a file: SD's input layer cannot read
    a password from a regular file and a "<" redirect stops dead after the
    prompt (PROJECT_STATUS.md 6).  Nothing here needs a password, but the
    session must still be fed something and closed, or a prompt reached with no
    input left spins at full CPU for ever - also section 6.
    """
    cmd, env = native_hop(sdexe, env, args)
    print('    $ ' + ' '.join([sdexe] + args))
    if cmd[0] != sdexe:
        print('      (started as: %s)' % ' '.join(cmd))
    sys.stdout.flush()

    # RELEASE_1.1 82 (D2'): the one-shot marker LOGIN needs for an internal
    # session, written now and removed afterwards whether or not sd consumed it.
    marker = None
    if args and args[0].lower() == '-internal' and INTERNAL_MARKER_DIR:
        marker = os.path.join(INTERNAL_MARKER_DIR, '$internal')
        with open(marker, 'w', encoding='ascii', newline='\n') as mf:
            mf.write('bootstrap.py pid=%d %s\n'
                     % (os.getpid(), time.strftime('%Y-%m-%dT%H:%M:%S')))

    # Output goes to a FILE, never a pipe.  "sd -start" spawns sdwind, which
    # inherits stdout and stderr, so anything capturing them through a pipe
    # blocks until the *daemon* exits rather than until sd -start does - and
    # the daemon is meant to keep running.  It looks exactly like a hang.
    # PROJECT_STATUS.md 6.  A file handle is inherited just as happily and
    # blocks nobody.
    try:
        with tempfile.TemporaryFile() as tf:
            r = subprocess.run(cmd, env=env, input=b'\n',
                               stdout=tf, stderr=subprocess.STDOUT)
            tf.seek(0)
            out = tf.read().decode('latin-1').replace('\r', '')
    finally:
        if marker and os.path.exists(marker):
            os.remove(marker)
    for line in out.splitlines():
        print('      | ' + line)
    if r.returncode != 0 and not expect_fail:
        die('sd %s failed with %d' % (' '.join(args), r.returncode))
    return out


def main():
    ap = argparse.ArgumentParser(
        description='Bootstrap a fresh SDSYS tree into a working system.')
    ap.add_argument('--sysdir', required=True,
                    help='the SDSYS directory to bootstrap')
    ap.add_argument('--sd', required=True, help='path to sd.exe')
    ap.add_argument('--conf', help='configuration file; SD_CONFIG is set '
                                   'to this for every SD command')
    args = ap.parse_args()

    # Checked before anything is copied, compiled or started - the failure it
    # replaces arrived several minutes in, at SECOND.COMPILE, as a compile
    # summary that never appeared.  Do NOT answer this by letting -INTERNAL
    # skip the elevation gate: that restores exactly the bypass the
    # 13 Aug 2026 session removed (PROJECT_STATUS.md 5.6).
    if not is_elevated():
        die('this needs an ELEVATED window, and this one is not.\n'
            '  The "sd -internal" steps name SDSYS for themselves, and SDSYS\n'
            '  is refused to a session that is not elevated - sysmsg(10002),\n'
            '  PROJECT_STATUS.md section 5.6.\n'
            '  Start the shell with "Run as administrator" and run this again.')

    sysdir = os.path.abspath(args.sysdir)
    sdexe = os.path.abspath(args.sd)
    here = os.path.dirname(os.path.abspath(__file__))

    if not os.path.isdir(sysdir):
        die('no such sysdir: %s' % sysdir)
    if not os.path.isfile(sdexe):
        die('no such sd executable: %s' % sdexe)
    check_account_record(sysdir)

    # RELEASE_1.1 82 (D2'): from here on every "-internal" session sd() starts
    # writes LOGIN's one-shot marker into THIS tree's SDSYS directory.
    global INTERNAL_MARKER_DIR
    INTERNAL_MARKER_DIR = sysdir

    env = dict(os.environ)
    if args.conf:
        env['SD_CONFIG'] = os.path.abspath(args.conf)

    # --- build inputs the data tree must not keep --------------------------

    # FILES_DICTS is an SD directory-type file, so it is a directory of records
    # rather than a single file.  Both shapes are handled: the list says what
    # the bootstrap needs, not what form it happens to take.
    placed = []
    for name, relsrc in BOOTSTRAP_ONLY:
        src = os.path.join(os.path.dirname(here), relsrc)
        if not os.path.exists(src):
            die('%s is needed for the bootstrap and is not in the tree' % relsrc)
        dstdir = os.path.join(sysdir, os.path.dirname(relsrc))
        if not os.path.isdir(dstdir):
            os.makedirs(dstdir)
        dst = os.path.join(dstdir, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
        placed.append(dstdir)

    # RELEASE_1.1 193 part 2 - see CYGDRIVE_LINE.  Undone in the finally below.
    fstab_undo = add_bootstrap_cygdrive(sdexe)

    try:
        print('  compiling the bootstrap compiler')
        bbcmp = os.path.join(here, 'bbcmp.py')
        for name in BBCMP_FIRST:
            run([sys.executable, bbcmp, sysdir,
                 'gpl.bp/' + name, 'gpl.bp.out/' + name])

        print('  building the pcode library')
        run([sys.executable, os.path.join(here, 'pcode_bld.py'), sysdir])

        # read_config() only checks that this exists.  The real object is
        # written by the last step.
        gcat = os.path.join(sysdir, 'gcat')
        if not os.path.isdir(gcat):
            os.makedirs(gcat)
        open(os.path.join(gcat, '$cproc'), 'ab').close()

        # Clear anything a previous run left behind before starting.  A failed
        # bootstrap leaves the shared segment up, so the next attempt gets
        # "SD is already started" and stops - and an abandoned segment also
        # holds record locks, which makes a later run wait for ever at no CPU
        # (PROJECT_STATUS.md 6).  A build has to be re-runnable after a
        # failure, so this is not optional tidiness.
        print('  clearing any previous server')
        sd(sdexe, env, ['-stop'], expect_fail=True)

        print('  starting SD')
        sd(sdexe, env, ['-start'])

        try:
            print('  bootstrap pass 1')

            # "sd -i" does its work and then dies on signal 6 rather than
            # exiting cleanly - it has no more input and no session to return
            # to.  Its exit status therefore says nothing, so this step is
            # judged on what it produced instead.  installsdai.sh sidestepped
            # the same thing by commenting the line out (line 603).
            sd(sdexe, env, ['-i'], expect_fail=True)

            for name in ('voc', 'voc.dic', 'accounts.dic', '$map', 'dict.dic'):
                if not os.path.exists(os.path.join(sysdir, name)):
                    die('sd -i did not create %s; pass 1 really did fail'
                        % name)

            print('  compiling the system (SECOND.COMPILE)')
            # Must be -internal, not -ASDSYS: BCOMP gates the $internal
            # directive on K$INTERNAL *and* K$ADMINISTRATOR, so standing in
            # SDSYS is not enough (PROJECT_STATUS.md 6).
            out = sd(sdexe, env, ['-internal', 'SECOND.COMPILE'])
            check_compile(out, 'SECOND.COMPILE')

            # These two were plain "sd RUN ..." and "sd THIRD.COMPILE" in the
            # sequence recorded in PROJECT_STATUS.md 3.  That stopped working
            # on 13 Aug 2026, when plain sd with no account named began asking
            # "Account:" instead of putting an administrator straight into
            # SDSYS - they sat at the prompt and the connection was
            # terminated.  Nobody noticed because nobody had re-run the
            # bootstrap since.  -internal means SDSYS, and needs no password
            # while SDSYS has no credential.
            print('  writing the install dictionaries')
            out = sd(sdexe, env,
                     ['-internal', 'RUN', 'gpl.bp', 'write_install_dicts',
                      'NO.PAGE'])
            # 29 Sep 26 - RELEASE_1.1 114, from SD Core Solo's SOLO 12.  JUDGED
            # ON ITS OWN SUCCESS LINE.  This step printed "Invalid runfile
            # pathname" from a staging path over 128 characters and the
            # bootstrap carried on to exit 0, so a tree shipped with no
            # dictionaries.  sd exits 0 either way; the program ends by
            # printing COMPLETE, and its failures say so.
            wid_lines = [l.strip() for l in out.splitlines()]
            # 02 Oct 26 - RELEASE_1.1 115 item 4.  The last four are the
            # program's own failure lines (write_install_dicts:30, 47, 96,
            # 126), the list SD Core for Linux's installer already stops on;
            # upgrade-dicts.ps1 stops on the same four.
            wid_bad = [w for w in ('Invalid runfile', 'ERROR OPENING',
                                   'PROCESS ABORTED', 'READLIST EMPTY',
                                   'NO DIRECTORY RECORDS FOUND',
                                   'CANNOT READ TRANSFER_FILE',
                                   'ERROR CANNOT OPEN',
                                   'requires administrator privileges')
                       if w.lower() in out.lower()]
            if 'COMPLETE' not in wid_lines or wid_bad:
                die('write_install_dicts did not complete (%s) - its output is '
                    'above' % (', '.join(wid_bad) or 'no COMPLETE line'))
            print('  checked: write_install_dicts printed COMPLETE')

            print('  compiling the system (THIRD.COMPILE)')
            out = sd(sdexe, env, ['-internal', 'THIRD.COMPILE'])
            # THIRD.COMPILE compiles dictionary I-types and prints no
            # "n error(s)" summary, so only the warning check applies.
            check_compile(out, 'THIRD.COMPILE', require_summary=False)

            print('  writing the real gcat/$cproc')
            sd(sdexe, env, ['-internal', 'BASIC', 'gpl.bp', 'cproc'])

            # 9 Nov 26 - THE SOURCE IS NEVER INSTALLED (owner: "the gpl.bp and c
            # source should never be installed just distributed with the
            # installer").  stage.py deletes the gpl.bp directory after this
            # (SDSYS_BUILD_SEED); this removes SDSYS's VOC record for it, which
            # BBPROC made from voc_template and every compile above needed.  Last,
            # after the final BASIC gpl.bp.  Anchored on DELETE's success wording;
            # "not found" would mean the bootstrap never made it, which is a fault.
            print('  removing the gpl.bp source pointer from VOC')
            out = sd(sdexe, env, ['-internal', 'DELETE', 'VOC', 'gpl.bp'])
            if not re.search(r'(?m)^1 record\(s\) deleted\s*$', out):
                die('DELETE VOC gpl.bp did not print "1 record(s) deleted":\n%s' % out)
            print('  checked: DELETE VOC gpl.bp printed 1 record(s) deleted')
        finally:
            print('  stopping SD')
            sd(sdexe, env, ['-stop'], expect_fail=True)

    finally:
        # Remove the build inputs whether the bootstrap worked or not, so a
        # failed run cannot leave gplbld/ sitting in a data tree.
        for d in placed:
            shutil.rmtree(d, ignore_errors=True)
        # Last, after the final "sd -stop", so no session of the bootstrap
        # outlives the line it was started with.
        restore_bootstrap_fstab(fstab_undo)

    print('bootstrapped %s' % sysdir)
    return 0


def check_compile(out, what, require_summary=True):
    """An undefined $define is a WARNING at compile time and an abort at run
    time, in a program that may not run until much later - the ERRGEN trap in
    PROJECT_STATUS.md 6.  "0 error(s)" is therefore not enough on its own, and
    a build that lets one through ships a system that breaks in use."""
    bad = [l for l in out.splitlines() if 'is not assigned a value' in l]
    if bad:
        for l in bad[:10]:
            print('      !! ' + l.strip())
        die('%s produced "not assigned a value" warnings, which mean a missing '
            'include - see the ERRGEN trap in PROJECT_STATUS.md section 6'
            % what)
    if require_summary and 'error(s)' not in out:
        die('%s produced no compiler summary at all; something is wrong' % what)
    for line in out.splitlines():
        s = line.strip()
        if s.endswith('error(s)') and not s.startswith('0 '):
            die('%s reported "%s"' % (what, s))


if __name__ == '__main__':
    sys.exit(main())
