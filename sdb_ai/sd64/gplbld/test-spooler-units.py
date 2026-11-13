"""test-spooler-units.py - sd.conf's SPOOLER is the printer SD prints to when SETPTR names none, and it never reaches PowerShell unquoted.

WHY IT EXISTS (RELEASE_1.1 219, 12 Nov 2026; owner: parity decides).  On Linux SPOOLER is the lp command a job is handed to.  Windows prints
with PowerShell's Out-Printer, so here SPOOLER is a printer NAME: spool_print_job() (gplsrc/linuxprt.c) passes it as Out-Printer -Name when
the print unit has no printer of its own.  The text is put into a PowerShell command line, so it must go through ps_quote() exactly as an
AT name does; anything else would let a line in sd.conf run a command.

WHAT IT CHECKS.  S1 spool_print_job() reads pcfg.spooler only as ps_quote(qprinter, sizeof(qprinter), pcfg.spooler); S2 that read is in
the branch taken when the print unit has no printer name (SETPTR's AT name still wins); S3 config.table says SPOOLER is live, and no row
is still marked inert for it.  Free: reads files.  --selftest breaks a copy of each in memory and each check must go red.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, '..'))
LINUXPRT = os.path.join(SD64, 'gplsrc', 'linuxprt.c')
TABLE = os.path.join(SD64, 'sdsys', 'config.table')


def read(p):
    with open(p, encoding='latin-1') as f:
        return f.read()


def body_of(src, name):
    m = re.search(r'\n(?:void|int|bool)\s+' + re.escape(name) + r'\s*\([^)]*\)\s*\{', src)
    if not m:
        return ''
    i, depth = m.end(), 1
    while i < len(src) and depth:
        depth += {'{': 1, '}': -1}.get(src[i], 0)
        i += 1
    return src[m.end():i]


def checks(prt, table):
    out = []
    body = body_of(prt, 'spool_print_job')
    uses = re.findall(r'[^\n]*pcfg\.spooler[^\n]*', body)
    reads = [u for u in uses if 'pcfg.spooler[0]' not in u]
    s1 = bool(body) and len(reads) == 1 and 'ps_quote(qprinter, sizeof(qprinter), pcfg.spooler)' in reads[0]
    out.append(('S1 spool_print_job reads SPOOLER only through ps_quote into qprinter', s1, 'uses: %s' % [u.strip() for u in uses]))
    m = re.search(r'if \(pu->printer_name != NULL && pu->printer_name\[0\] != \'\\0\'\) \{.*?\} else if \(pcfg\.spooler\[0\] != \'\\0\'\) \{', body, re.S)
    out.append(('S2 SPOOLER is used only when the print unit names no printer (AT wins)', m is not None, ''))
    rows = [l for l in table.splitlines() if l.startswith('SPOOLER|')]
    s3 = len(rows) == 1 and rows[0].split('|')[6] == 'live'
    out.append(('S3 config.table has one SPOOLER row and it is live', s3, 'rows: %s' % [r[:60] for r in rows]))
    return out


def run(prt, table, quiet=False):
    res = checks(prt, table)
    bad = [r for r in res if not r[1]]
    if not quiet:
        print('linuxprt.c : %s' % LINUXPRT)
        print('config.table: %s' % TABLE)
        for name, ok, why in res:
            print('  [%s] %s%s' % ('PASS' if ok else 'FAIL', name, '' if ok else '  ' + why))
    return bad


def selftest(prt, table):
    mutants = [
        ('S1', 'SPOOLER put in the command unquoted', lambda p, t: (p.replace('ps_quote(qprinter, sizeof(qprinter), pcfg.spooler) < 0', 'snprintf(qprinter, sizeof(qprinter), "%s", pcfg.spooler) < 0', 1), t)),
        ('S2', 'SPOOLER chosen before the AT name', lambda p, t: (p.replace('} else if (pcfg.spooler[0] != \'\\0\') {', '} if (pcfg.spooler[0] != \'\\0\') {', 1), t)),
        ('S3', 'config.table marks SPOOLER inert again', lambda p, t: (p, t.replace('SPOOLER|text||||session|live|', 'SPOOLER|text||||session|inert|', 1))),
    ]
    missed = 0
    for want, label, fn in mutants:
        p2, t2 = fn(prt, table)
        if (p2, t2) == (prt, table):
            print('  [MISSED] %s: the mutation changed nothing' % label)
            missed += 1
            continue
        names = [r[0][:2] for r in run(p2, t2, quiet=True)]
        ok = want in names
        missed += 0 if ok else 1
        print('  [%s] %s -> %s' % ('caught' if ok else 'MISSED', label, names))
    print('selftest: %d of %d mutants caught' % (len(mutants) - missed, len(mutants)))
    return 1 if missed else 0


if __name__ == '__main__':
    if not (os.path.isfile(LINUXPRT) and os.path.isfile(TABLE)):
        print('test-spooler-units: NO TREE - %s or %s missing' % (LINUXPRT, TABLE))
        sys.exit(2)
    prt, table = read(LINUXPRT), read(TABLE)
    if '--selftest' in sys.argv[1:]:
        if run(prt, table, quiet=True):
            print('selftest: the real files fail, so mutants prove nothing')
            sys.exit(1)
        sys.exit(selftest(prt, table))
    bad = run(prt, table)
    print('test-spooler-units: %s' % ('PASSED - 3 checks' if not bad else 'FAILED - %d of 3' % len(bad)))
    sys.exit(1 if bad else 0)
