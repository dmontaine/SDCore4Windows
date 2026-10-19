# What the verify-carry suites cannot measure on Windows (RELEASE_1.1 143), read by verify-carry.ps1.
# Two tables.  An entry carries its reason, and the evidence for it is the run that showed it.
#
#   NotRun  'suite' = 'reason'   the whole suite cannot run in an ordinary account.  Measured 18 Oct 2026 by running every new
#                                suite once on the W1.1-3 install (a launcher plumbing run, not a verdict on any feature):
#                                each one below stopped on a Linux mechanism, not on a missing feature.  Printed as NOT RUN
#                                in the table, and a run with any NOT RUN suite is never reported as the whole carry.
#   Rows    'suite' = @{ 'start of the row label, as the suite prints it after [FAIL]' = 'reason' }
#                                a row that is a Linux mechanism the launcher (verify-carry-run.py) does not emulate or a
#                                difference the owner permitted: a pty, the TZ variable, sd.conf plus a restart, a /tmp
#                                literal, an administrator-only verb, a CR LF line end.  A row that fails because the
#                                feature is wrong is a defect, not an entry.  Filled 18 Oct 2026 from the first two runs on a
#                                carried build (`vi1-core2.dec`); each reason was read in the run's own output.  A prefix
#                                matches every row that starts with it, so keep prefixes as long as the label allows.
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
        # The public FCONTROL function and the FC$ tokens are Linux 400500c, part of the held QMClient chain: not carried.
        'fcontrol'     = 'FCONTROL(fvar, FC$...) is the public FCONTROL (Linux 400500c, QMClient chain, held): the probes do not compile'
        'crlf'         = 'its first leg uses FCONTROL(fvar, FC$CRLF, ...), the public FCONTROL (held): the probe does not compile'
        # A job sent to the Windows default printer: SETPTR mode 1 or 6 here is Out-Printer on a real, paper-printing printer.
        # Found 18 Oct 2026 when the owner's printer printed pages saying "hello" (option-q17, two jobs per run) and "line one"
        # (oq2, one job per run).  Linux's sandbox has no printer.  They stay out until a null printer exists to point them at.
        'option-q17'   = 'SPOOL.COMMAND rows print a page saying "hello" on the Windows default printer (SETPTR mode 1, Out-Printer)'
        'oq2'          = 'row 56 sends a job to the Windows default printer (SETPTR mode 1 and mode 6, Out-Printer): it prints "line one" on paper'
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
        # A line ends with CR LF here unless a mode is chosen: the owner PERMITTED this default on 18 Oct 2026 (Linux mail T1930,
        # deviation 15 of the areas 2-5 list).  The suites count bytes, and Linux's default is LF only.
        'audit-b9' = @{
            '259 THE ROW: SEEK -3 from the end'    = 'WRITESEQ ends a line with CR LF, so the last three bytes are d CR LF and READSEQ gives d, not ld (the SEEK itself worked: ok = 1)'
            '259 a positive offset from the end'   = 'WRITESEQ ends a line with CR LF, so the last three bytes are d CR LF and READSEQ gives d, not ld (the SEEK itself worked: ok = 1)'
        }
        'dirtrig' = @{
            'a pre-write trigger that changes the data: the capitals' = 'the record on disk is ABC CR LF: a directory file write ends its line with CR LF here (the capitals are right)'
            'a pre-delete trigger that returns a code refuses'        = 'STATUS 3022 is right; the byte check of the surviving record sees keep CR LF where Linux has keep LF'
            'the user''s record named %header% is on disk under'      = 'the suite finds the record by its bytes, mine LF; here it is mine CR LF'
            'WRITESEQ to a record of the file'                        = 'the trigger is not called (right); the byte check sees line CR LF where Linux has line LF'
        }
        'func-q1' = @{
            'SEND writes the string and a newline'      = 'SEND ends its line with CR LF on the console here; the probe reads the line end as one character'
            'SEND of an expression with colons'         = 'SEND ends its line with CR LF on the console here; the probe reads the line end as one character'
            'VOCPATH with DICT in front'                = 'the VOC dictionary lives in SDSYS, outside the ordinary account, so its path is told to an administrator only (the K$PATH.OK stand-in)'
        }
        # Administrator-only verbs: the ordinary account's VOC has no LIST.READU, CONFIG and the like (the tier split).
        'cll' = @{
            'the option on: the lock is still held'         = 'the probe runs LIST.READU, which is not in an ordinary account''s VOC (an administrator verb here)'
            'an EXECUTEd program sees its own lock'        = 'the probe runs LIST.READU, which is not in an ordinary account''s VOC (an administrator verb here)'
            'back from the EXECUTE the caller'             = 'the probe runs LIST.READU, which is not in an ordinary account''s VOC (an administrator verb here)'
        }
        'conf-b1' = @{
            '106: PWDELAY is set and read back'   = 'sets the value with the CONFIG verb, which is not in an ordinary account''s VOC (an administrator verb here)'
            '313:'                                = 'sets MAXRLOCK with the CONFIG verb, which is not in an ordinary account''s VOC (an administrator verb here)'
            '90:'                                 = 'sets DHCACHE with the CONFIG verb, which is not in an ordinary account''s VOC (an administrator verb here)'
            '91:'                                 = 'the @TTY startup half of Linux 1298f82 is not carried: SD has no STARTUP process here (RELEASE_1.1 119)'
            '551:'                                = 'writes USERPOOL into sd.conf and restarts the daemon; the installed service never reads the box copy'
            'USERPOOL='                           = 'writes the parameter into sd.conf and restarts the daemon; the installed service never reads the box copy'
            'LGNWAIT='                            = 'writes the parameter into sd.conf and restarts the daemon; the installed service never reads the box copy'
            'DHCACHE='                            = 'writes the parameter into sd.conf and restarts the daemon; the installed service never reads the box copy'
            'MAXRLOCK='                           = 'writes the parameter into sd.conf and restarts the daemon; the installed service never reads the box copy'
            'PWDELAY='                            = 'writes the parameter into sd.conf and restarts the daemon; the installed service never reads the box copy'
            '46:'                                 = 'writes LGNWAIT into sd.conf and restarts the daemon; the installed service never reads the box copy'
            '241:'                                = 'writes MAXIDLEN into sd.conf and restarts the daemon; the installed service never reads the box copy'
        }
        # The first debugger rows of Linux fa146d9 (every variable with /*, a token as the value of SET) are not carried: the Linux
        # debug program is on the screen library (area 6, held) and this port's is not.
        'dbgcoll' = @{
            '/* shows every variable'             = 'the /* command of the debugger on the screen library (Linux fa146d9, area 6) is not carried'
            '...the integer'                      = 'follows the /* row: the /* command is not carried'
            '...a collection, with its element'   = 'follows the /* row: the /* command is not carried'
            '...and the loop variable'            = 'follows the /* row: the /* command is not carried'
        }
        'dbgequ' = @{
            'a token that stands for a number'    = 'a token as the value of a debugger SET (Linux fa146d9, QM4 Fixes 239) is not carried: the debug program is not on the screen library here'
            'a $DEFINE token may be the value'    = 'a token as the value of a debugger SET (Linux fa146d9, QM4 Fixes 239) is not carried: the debug program is not on the screen library here'
            'a token that stands for a string'    = 'a token as the value of a debugger SET (Linux fa146d9, QM4 Fixes 239) is not carried: the debug program is not on the screen library here'
            'a token that stands for CHAR(n)'     = 'a token as the value of a debugger SET (Linux fa146d9, QM4 Fixes 239) is not carried: the debug program is not on the screen library here'
            '...and the variable has'             = 'follows the SET row: a token as the value of a debugger SET is not carried'
        }
        'collfile' = @{
            'EDIT is the same editor'             = 'EDIT needs a terminal to draw on and the piped session has none ("edit needs a terminal to draw on")'
        }
        'lang-a15' = @{
            '64: OPENPATH ... NON.TRANSACTIONAL'  = 'the probe opens the literal path /tmp, which is not a directory SD can open here'
        }
        'option-a4' = @{
            'CONTROL: a backslash opens a quoted string' = 'OPTION BACKSLASH.NOT.QUOTE is accepted and does nothing here: a backslash is a path separator and the parser never splits at one (deviation 1 of the area 1 mail)'
        }
        'proc-a5' = @{
            'one user (this session)'             = 'counts every logged-in user: a phantom left by an earlier suite or a console session of the owner makes it 2; it passes when run alone'
        }
        'sys-b2' = @{
            '1024, 1027, 1028, 1034, 1036:'       = 'FILEINFO 1031 (CREATING.SEQKEY, Linux d6a86a7 and 400500c of the held QMClient chain) is not carried: the key answers a null string'
            '1034, 1040, 1044, 1051, 1080:'       = 'SYSTEM(1040) answers 1 here: Windows file names are not case sensitive (deviation 8 of the areas 2-5 list)'
            'THE ZONE TOOK EFFECT'                = 'the MSYS2 runtime reads POSIX TZ strings (EST5EDT) and the Windows zone but not Olson names such as Asia/Kathmandu (measured 18 Oct: UTC)'
            '326: a catalogued $SYSTEM'           = 'the suite makes a GLOBAL catalogue entry (CATALOG ... GLOBAL $) from its own account and the subroutine was not called; global entries are an administrator''s'
            '20 (432): OSPATH(path, OS$INFO)'     = 'needs an elevated session ("This command needs an elevated session"): sd -internal'
            '...and its modification time is local' = 'follows the OSPATH row: needs an elevated session (sd -internal)'
            '337:'                                = 'needs an elevated session ("This command needs an elevated session"): sd -internal'
            '293:'                                = 'needs an elevated session ("This command needs an elevated session"): sd -internal'
        }
    }
}
