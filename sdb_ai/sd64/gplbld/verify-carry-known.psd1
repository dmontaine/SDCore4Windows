# What the verify-carry suites cannot measure on Windows (RELEASE_1.1 143), read by verify-carry.ps1.
# Two tables.  An entry carries its reason, and the evidence for it is the run that showed it.
#
#   NotRun  'suite' = 'reason'   the whole suite cannot run in an ordinary account.  Measured 18 Oct 2026 by running every new
#                                suite once on the W1.1-3 install (a launcher plumbing run, not a verdict on any feature):
#                                each one below stopped on a Linux mechanism, not on a missing feature.  Printed as NOT RUN
#                                in the table, and a run with any NOT RUN suite is never reported as the whole carry.
#   Rows    'suite' = @{ 'start of the row label, as the suite prints it after [FAIL]' = 'reason' }
#                                a row that is a Linux mechanism the launcher (verify-carry-run.py) does not emulate: a
#                                pty, the TZ variable, sd.conf plus a restart, strace, a symlink, a user id, a /tmp literal.
#                                A row that fails because the feature is wrong is a defect, not an entry.  Empty until the
#                                first run on a carried build shows which rows these are.
@{
    NotRun = @{
        # The Linux sandbox's administrator: SDSYS sessions (adm), a recompiled CPROC and fixture accounts.
        'classinit'    = 'loads sandbox-stmt-q3.py: SDSYS sessions, a fixture account and a CPROC recompiled in the sandbox; none exists in an ordinary account'
        'nameindex'    = 'loads sandbox-stmt-q3.py: SDSYS sessions, a fixture account and a CPROC recompiled in the sandbox; none exists in an ordinary account'
        'q4'           = 'loads sandbox-stmt-q3.py: SDSYS sessions, a fixture account and a CPROC recompiled in the sandbox; none exists in an ordinary account'
        'q5'           = 'loads sandbox-stmt-q3.py: SDSYS sessions, a fixture account and a CPROC recompiled in the sandbox; none exists in an ordinary account'
        'restricted'   = 'loads sandbox-stmt-q3.py: SDSYS sessions, a fixture account and a CPROC recompiled in the sandbox; none exists in an ordinary account'
        'stmt-q3'      = 'reads and recompiles <sys>/gpl.bp/cproc as SDSYS, builds fixture accounts and starts sd -internal; none exists in an ordinary account'
        'inhibit-q8'   = 'reads and recompiles <sys>/gpl.bp/cproc as SDSYS and starts sd -internal; none exists in an ordinary account'
        'listu-a5'     = 'reads and recompiles <sys>/gpl.bp/cproc as SDSYS and starts sd -internal; none exists in an ordinary account'
        # S.63 (per-account OS gates) is on the HOLD list and is not carried.
        'ospath'       = 'loads sandbox-gates.py (S.63 per-account OS gates, HOLD list, not carried) and needs SDSYS sessions'
        'prof'         = 'loads sandbox-gates.py (S.63 per-account OS gates, HOLD list, not carried) and needs SDSYS sessions'
        'resetall'     = 'loads sandbox-gates.py (S.63 per-account OS gates, HOLD list, not carried) and needs SDSYS sessions'
        'stacked'      = 'loads sandbox-gates.py (S.63 per-account OS gates, HOLD list, not carried) and needs SDSYS sessions'
        # A Linux call that does not exist in Python on Windows, or a daemon restart with a changed sd.conf.
        'getdev'       = 'os.mkfifo: a named pipe, Linux only (AttributeError at the start of the run)'
        'lock-b6'      = 'sets DEADLOCK=2 NUMLOCKS=10 in sd.conf and restarts the daemon, then stops "SD NOT STARTED" when it sees no change; the installed service does not read the box copy'
        # sd -internal is forced to the real SDSYS and needs an elevated session; these suites write their programs into the
        # box's sys directory, which is the caller's own account, so the two would not meet.
        'audit-b9b'    = 'starts sd -internal: forced to the real SDSYS, elevated only; the suite writes its programs into the box account'
        'cmd-a9'       = 'starts sd -internal (forced to the real SDSYS, elevated only) and deletes <sys>/stacks, which here is the caller account'
        'epoch'        = 'starts sd -internal (forced to the real SDSYS, elevated only); also needs TZ zone names and the zoneinfo database, which Python on Windows lacks'
        'inputraw'     = 'starts sd -internal: forced to the real SDSYS, elevated only; the suite writes its programs into the box account'
        'noecho'       = 'starts sd -internal: forced to the real SDSYS, elevated only; the suite writes its programs into the box account'
        'opensock'     = 'starts sd -internal: forced to the real SDSYS, elevated only; the suite writes its programs into the box account'
        'selectv-mode' = 'starts sd -internal: forced to the real SDSYS, elevated only; the suite writes its programs into the box account'
        'sortwide'     = 'starts sd -internal (SORTNEXT, SORTDATA are restricted): forced to the real SDSYS, elevated only; the suite writes its programs into the box account'
        'sselectv'     = 'starts sd -internal: forced to the real SDSYS, elevated only; the suite writes its programs into the box account'
        'txnstatus'    = 'starts sd -internal: forced to the real SDSYS, elevated only; the suite writes its programs into the box account'
    }
    Rows = @{
    }
}
