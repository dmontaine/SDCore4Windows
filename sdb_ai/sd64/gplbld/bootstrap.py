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
#   * The empty gcat/$CPROC placeholder is what lets "sd -start" run before
#     anything is catalogued.  read_config() only does access(path, 0) on it,
#     so an empty file satisfies the check and the last step overwrites it with
#     the real object.  There is no ordering deadlock here, however much it
#     looks like one.
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
import shutil
import subprocess
import sys
import tempfile

# Run by bbcmp.py before there is a compiler.  Order matters: BBPROC is the
# bootstrap paragraph processor, BCOMP the compiler it needs, PATHTKN the
# pathname tokeniser both rely on.
BBCMP_FIRST = ['BBPROC', 'BCOMP', 'PATHTKN']

# BUILTIN\Administrators by RID, never by name - the same choice, for the same
# reason, as SD_ADMIN_GID in gplsrc/linuxlb.c.  Cygwin maps a built-in SID to
# its RID, so S-1-5-32-544 is always gid 544, while the NAME is translated on a
# localised Windows.
SD_ADMIN_GID = 544

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

    Field 1 of accounts/SDSYS is the account directory, and once a session has
    logged in it is what gpl.bp and gpl.bp.out resolve to - the gcat comes from
    the config file, the sources do not.  The tracked record ships naming
    /usr/local/sdsys, the Linux development tree, and on 15 Aug 2026 a run
    against it compiled 190 programs THERE and catalogued them into the staged
    tree: a staged gcat holding 13 Aug objects, with no symptom until somebody
    installed it.  Cheap to check, expensive to find.
    """
    rec = os.path.join(sysdir, 'accounts', 'SDSYS')
    if not os.path.isfile(rec):
        die('no accounts/SDSYS record in %s' % sysdir)
    with open(rec, 'rb') as f:
        acctdir = f.read().decode('latin-1').split(FM)[0]
    if not os.path.isdir(acctdir) or not os.path.samefile(acctdir, sysdir):
        die('accounts/SDSYS names %s, but this bootstrap is for\n'
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


def sd(sdexe, env, args, expect_fail=False):
    """Run one SD command.

    Input is piped, never redirected from a file: SD's input layer cannot read
    a password from a regular file and a "<" redirect stops dead after the
    prompt (PROJECT_STATUS.md 6).  Nothing here needs a password, but the
    session must still be fed something and closed, or a prompt reached with no
    input left spins at full CPU for ever - also section 6.
    """
    cmd = [sdexe] + args
    print('    $ ' + ' '.join(cmd))
    sys.stdout.flush()

    # Output goes to a FILE, never a pipe.  "sd -start" spawns sdwind, which
    # inherits stdout and stderr, so anything capturing them through a pipe
    # blocks until the *daemon* exits rather than until sd -start does - and
    # the daemon is meant to keep running.  It looks exactly like a hang.
    # PROJECT_STATUS.md 6.  A file handle is inherited just as happily and
    # blocks nobody.
    with tempfile.TemporaryFile() as tf:
        r = subprocess.run(cmd, env=env, input=b'\n',
                           stdout=tf, stderr=subprocess.STDOUT)
        tf.seek(0)
        out = tf.read().decode('latin-1').replace('\r', '')
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
        open(os.path.join(gcat, '$CPROC'), 'ab').close()

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
            sd(sdexe, env,
               ['-internal', 'RUN', 'GPL.BP', 'WRITE_INSTALL_DICTS', 'NO.PAGE'])

            print('  compiling the system (THIRD.COMPILE)')
            out = sd(sdexe, env, ['-internal', 'THIRD.COMPILE'])
            # THIRD.COMPILE compiles dictionary I-types and prints no
            # "n error(s)" summary, so only the warning check applies.
            check_compile(out, 'THIRD.COMPILE', require_summary=False)

            print('  writing the real gcat/$CPROC')
            sd(sdexe, env, ['-internal', 'BASIC', 'GPL.BP', 'CPROC'])
        finally:
            print('  stopping SD')
            sd(sdexe, env, ['-stop'], expect_fail=True)

    finally:
        # Remove the build inputs whether the bootstrap worked or not, so a
        # failed run cannot leave gplbld/ sitting in a data tree.
        for d in placed:
            shutil.rmtree(d, ignore_errors=True)

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
