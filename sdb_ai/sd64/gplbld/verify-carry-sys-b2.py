#!/usr/bin/env python3
#
# sandbox-sys-b2.py - 1.2-0 bundle B-2 (openQM SYSTEM() / FILEINFO() / GETPU() key values).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-sys-b2.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 17 Oct 26 dm  FILEINFO key 1021 is FL$WHO, the manual's list of user numbers; the text form is 1100 (QM4 Fixes 62).
# 12 Oct 26 dm  B-1 changed what key 1053 answers: the larger of NUMUSERS and USERPOOL (1023 by default), not NUMUSERS.
#               The 1053 row compares it with that, and with USERPOOL read through config().
# 12 Oct 26 dm  Part 2: FILEINFO keys 1022-1040 as the manual numbers them (FL$COLLECTION moved from 1022 to 1035) and
#               SYSTEM keys 33, 1019, 1033-1035, 1037, 1038, 1040, 1044, 1051-1054, 1057, 1058, 1065, 1070, 1076-1078,
#               1080-1082.  A helper subroutine is catalogued for the keys that need a caller.
# 11 Oct 26 dm  Written for 1.2-0 bundle B-2: SYSTEM(35) users, SYSTEM(1016) users available, SYSTEM(1045) start
#               time as a Unix epoch value, SYSTEM(1047) a GUID.
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets.  Every row's expression uses only the
# key under test and a CONTROL key SD already had (1013, the user limit), so a row cannot pass by printing nothing.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

# (label, BASIC statements one per line leaving the value in x, wanted regular expression for the whole bracket)
CASES = [
    ("CONTROL: SYSTEM(1013) is the user limit, a positive number", "x = system(1013) > 0", r"1"),
    ("35: at least this session is counted", "x = system(35) >= 1", r"1"),
    ("35 and 1016 add up to the user limit", "x = (system(35) + system(1016)) = system(1013)", r"1"),
    ("1045: started after 2020 and not in the future (Unix epoch)",
     "t = system(1045)\nx = (t > 1577836800) and (t <= system(1005) - 732 * 86400 + 86400)", r"1"),
    ("1045 is not later than this session's login time, taken from key 1030 (same clock, days from 1967)",
     "x = (system(1045) <= system(1030) - 732 * 86400 + 86400)", r"1"),
    ("1047: a GUID has 36 characters", "x = len(system(1047))", r"36"),
    ("1047: in the 8-4-4-4-12 shape", "g = system(1047)\nx = (g[9,1]:g[14,1]:g[19,1]:g[24,1])", r"----"),
    ("1047: two calls give two values", "x = (system(1047) # system(1047))", r"1"),
]

# ---- part 2, 12 Oct 26: the FILEINFO() keys 1022-1040 and more SYSTEM() keys, numbered as the openQM 4 manual numbers
# them.  FILEINFO rows begin with the files they need: f a dynamic file, d a directory file, c a collection file.
FILES = ("$include keys.h\nexecute 'DELETE.FILE zzb2f' capturing j\nexecute 'CREATE.FILE zzb2f' capturing j\n"
         "open 'zzb2f' to f else stop 'no f'\n"
         "execute 'DELETE.FILE zzb2d' capturing j\nexecute 'CREATE.FILE zzb2d DIRECTORY' capturing j\n"
         "open 'zzb2d' to d else stop 'no d'\n"
         "execute 'DELETE.FILE zzb2c' capturing j\nexecute 'CREATE.FILE zzb2c COLLECTION' capturing j\n"
         "open 'zzb2c' to c else stop 'no c'\n")
SECOND = ("execute 'DELETE.FILE zzb2g' capturing j\nexecute 'CREATE.FILE zzb2g' capturing j\n"
          "open 'zzb2g' to g else stop 'no g'\n")

CASES += [
    ("CONTROL: FL$TYPE of a dynamic file and a directory file", FILES + "x = fileinfo(f, FL$TYPE):fileinfo(d, FL$TYPE)", r"34"),
    ("1035: FL$COLLECTION is the manual's number and tells a collection file from the others",
     FILES + "x = FL$COLLECTION:'|':fileinfo(f, FL$COLLECTION):fileinfo(d, FL$COLLECTION):fileinfo(c, FL$COLLECTION)", r"1035\|001"),
    ("1022: FL$NETFILE is 0 for every file, a collection file included (1022 was SD's FL$COLLECTION)",
     FILES + "x = FL$NETFILE:'|':fileinfo(f, FL$NETFILE):fileinfo(c, FL$NETFILE):fileinfo(d, 1022)", r"1022\|000"),
    ("1023 (113): FL$SEQTYPE is 2 for a character device, 0 for a plain file and for a file that is not sequential",
     FILES + "write 'abc' on d, 'seq1'\nopenseq '/dev/null' to q1 else stop 'no q1'\nopenseq 'zzb2d', 'seq1' to q2 else stop 'no q2'\n"
     "x = FL$SEQTYPE:'|':fileinfo(q1, FL$SEQTYPE):'|':fileinfo(q2, FL$SEQTYPE):'|':fileinfo(f, FL$SEQTYPE)", r"1023\|2\|0\|0"),
    # 15 Oct 26: 1031 is the id of the last record written with CREATING.SEQKEY - 0 in a hashed file that has not used it - so the
    # third value of the six is 0 and no longer null (the others stay null)
    ("1024, 1027, 1028, 1034, 1036: no replication, ECS, encoding, forced casing or owner: null; 1031, the sequential key: 0 in an unused hashed file",
     FILES + "x = fileinfo(f, FL$REPLICATED):'|':fileinfo(f, FL$ECS.MAP.NAME):'|':fileinfo(d, FL$ENCODING):'|':fileinfo(f, FL$SEQ.KEY):'|':"
     "fileinfo(f, FL$ID.CASING):'|':fileinfo(f, FL$OWNER)", r"\|\|\|0\|\|"),
    ("1025, 1026, 1029, 1033, 1037, 1040: no id translation switch, ECS, distributed file, SYNC, temporary file or constraint: 0",
     FILES + "x = fileinfo(d, FL$NOMAP):fileinfo(f, FL$ECS):fileinfo(f, FL$LAST.PART):fileinfo(f, FL$SYNC):fileinfo(f, FL$TEMP):"
     "fileinfo(f, FL$CONSTRAINTS)", r"000000"),
    ("1030: FL$INDEX.SCAN is true for a dynamic file and false for a directory file", FILES + "x = fileinfo(f, FL$INDEX.SCAN):fileinfo(d, FL$INDEX.SCAN)", r"10"),
    ("1032: FL$NON.TXN is 0 for an ordinary open (FCONTROL, which sets it, is for internal programs)", FILES + "x = fileinfo(f, FL$NON.TXN)", r"0"),
    ("1038: FL$TXN.UPDATE is true for the file written in the transaction and not for another, false after COMMIT",
     FILES + SECOND + "x = fileinfo(f, FL$TXN.UPDATE)\nbegin transaction\n   recordlocku f, 'k1'\n   write 'a' on f, 'k1'\n"
     "   x := fileinfo(f, FL$TXN.UPDATE):fileinfo(g, FL$TXN.UPDATE)\ncommit\nend transaction\nx := fileinfo(f, FL$TXN.UPDATE)", r"0100"),
    ("1039 (498): FL$LOCKS lists the caller's locks in this file only, RU and RL with their record ids, and none after RELEASE",
     FILES + SECOND + "readu r1 from f, 'k1' else null\nreadl r2 from f, 'k2' else null\nreadu r3 from g, 'k3' else null\nl = fileinfo(f, FL$LOCKS)\n"
     "u = upcase(l)   ;* the lock table holds ids in upper case, as GETLOCKS() shows them\n"
     "x = dcount(l, @fm):'|':(index(u, 'RU':@vm:'K1', 1) > 0):(index(u, 'RL':@vm:'K2', 1) > 0):'|':change(upcase(fileinfo(g, FL$LOCKS)), @vm, ':')\n"
     "release\nx := '|[':fileinfo(f, FL$LOCKS):']'", r"2\|11\|RU:K3\|\[\]"),
    ("1039: a file lock is FX with no record id", FILES + "filelock f\nx = change(fileinfo(f, FL$LOCKS), @vm, ':')\nfileunlock f\nx := '|[':fileinfo(f, FL$LOCKS):']'", r"FX:\|\[\]"),
    # SYSTEM() keys that need no file
    ("33 (308) and 1076: the name of the program that called the subroutine, and the CALL depth one deeper in it",
     "d0 = system(1076)\ncall zzb2s1(a, d1)\nx = a:'|':(d1 - d0)", r"(?i).*zzb2\d\d\|1"),   # an uncatalogued program is named by its pathname
    ("13, 16 and 22: the timeslice key is 1, the command level is @LEVEL, the user number is @USERNO and key 18",
     "x = system(13):'|':(system(16) = @level):(system(22) = @userno):(system(22) = system(18))", r"1\|111"),
    ("1033: COMO is active only between COMO ON and COMO OFF; 1034 is 0 (it cannot be suspended)",
     "x = system(1033)\nexecute 'COMO ON zzb2como' capturing j\nx := system(1033)\nexecute 'COMO OFF' capturing j\nx := system(1033):system(1034)", r"0100"),
    ("1035 is the Unix epoch now and not before SD started; 1019 is the zone's offset from UTC, the difference between the local clock (1005) and it",
     "t = system(1035)\nx = (t >= system(1045)) and (t - system(1045) < 7200)\nx := abs(system(1019) - ((system(1005) - 732 * 86400) - t)) <= 1", r"11"),
    ("1038: the login time as an epoch value is not later than now, is within an hour of it, and agrees with 1030 and the zone offset",
     "l = system(1038)\nx = (l <= system(1035)) and (system(1035) - l < 3600)\nx := abs(l - (system(1030) - 732 * 86400 - system(1019))) <= 1", r"11"),
    ("1081 (epoch ms) is 1000 times 1035 to within 3 seconds; 1082 (ms since midnight) is a time of day",
     "x = (system(1081) > 1700000000000) and (abs(system(1081) / 1000 - system(1035)) < 3)\nm = system(1082)\nx := (m > 0) and (m < 86400000)", r"11"),
    ("1034, 1040, 1044, 1051, 1080: 0 (no suspended COMO, a case sensitive file system, no ECS, no USB installation, no Proc)",
     "x = system(1034):system(1040):system(1044):system(1051):system(1080)", r"00000"),
    ("1052, 1057, 1058: a process with no phantoms has no children and no parent",
     "x = system(1052):'|':system(1057):'|[':system(1058):']'", r"0\|0\|\[\]"),
    ("1053 is the highest user number - the user limit, or USERPOOL when that is larger (B-1); 1054 lists no packages",
     "u = system(1013)\np = config('USERPOOL')\nx = (system(1053) = (if p > u then p else u)):'|[':system(1054):']'", r"1\|\[\]"),
    ("1070: the PRECISION in force", "precision 7\nx = system(1070)", r"7"),
    ("1077 and 1078: as many group names as group numbers, and the effective group (SYSTEM(30)) is among the numbers",
     "x = (dcount(system(1077), @fm) = dcount(system(1078), @fm)):(index(@fm:system(1078):@fm, @fm:system(30):@fm, 1) > 0)", r"11"),
    ("1037 (66): every open file and the users that have it open - this file is there with this user",
     FILES + "q = system(1037)\nx = 0\nfor i = 1 to dcount(q, @fm)\n   if index(q<i,2>, 'zzb2f', 1) then x = (q<i,3> = system(22))\nnext i", r"1"),
    ("1065 (294): the transaction cache has the write and the delete as numbers, the file number, the id and W or D, and is null outside one",
     FILES + "write 'z' on f, 'k2'\nbegin transaction\n   recordlocku f, 'k1'\n   write 'a' on f, 'k1'\n   recordlocku f, 'k2'\n   delete f, 'k2'\n"
     "   x = change(change(system(1065), @fm, '|'), @vm, ':')\ncommit\nend transaction\nx := '|[':system(1065):']'",
     r"\d+:\d+:k1:W\|\d+:\d+:k2:D\|\[\]"),
]

# ---- part 2b: STATUS / OSPATH / GETPU.  The sandbox runs in a time zone of its own (see main), so the local-time rows
# cannot pass on a machine that happens to be on UTC.
CASES += [
    ("THE ZONE TOOK EFFECT: SYSTEM(1019) is the 5 h 45 min of Nepal (without this the local-time rows below mean nothing)",
     "x = system(1019)", r"20700"),
    ("FL$STATUS (the STATUS statement's array) has 35 fields and field 27 is the pathname, the same as field 20 (585)",
     FILES + "fi = fileinfo(f, FL$STATUS)\nx = dcount(fi, @fm):'|':(fi<27> = fi<20>):(index(fi<20>, 'zzb2f', 1) > 0)", r"35\|11"),
    ("...fields 15 and 16 are the modification time and date in the LOCAL zone, field 35 the same instant as an epoch (96)",
     FILES + "write 'a' on f, 'k1'\nfi = fileinfo(f, FL$STATUS)\nlocal = (fi<16> - 732) * 86400 + fi<15>\n"
     "x = (abs(fi<35> - system(1035)) < 600):(abs(local - (fi<35> + system(1019))) <= 1)", r"11"),
    ("...fields 13, 14 and 34 are the same for the access", FILES + "fi = fileinfo(f, FL$STATUS)\nlocal = (fi<14> - 732) * 86400 + fi<13>\n"
     "x = abs(local - (fi<34> + system(1019))) <= 1", r"1"),
    ("...a directory file's array says it is one (field 21 is 4)", FILES + "fi = fileinfo(d, FL$STATUS)\nx = fi<21>:'|':dcount(fi, @fm)", r"4\|35"),
    ("1021-1025 (18): GETPU's form feed is CR FF, the encoding and font are null, the font size 0 (1020, the form queue, was removed 27 Oct 26)",
     "$include keys.h\nx = (getpu(PU$FORM.FEED, 0) = char(13):char(12)):'[':getpu(PU$ENCODING, 0):getpu(PU$FONT, 0):']':getpu(PU$FONT.SIZE, 0)",
     r"1\[\]0"),
    ("1024 (214): GETPU(PU$PATHNAME) is the file the print unit is writing while it is open, and null once it is closed",
     "$include keys.h\nexecute 'SETPTR 0,80,60,0,0,3,AS zzb2job,BRIEF' capturing j\nprinter on\nprint 'hello'\np = getpu(PU$PATHNAME, 0)\n"
     "printer close\nx = (index(p, 'zzb2job', 1) > 0):'|':getpu(PU$PATHNAME, 0)", r"1\|"),
]

# 17 Oct 26, QM4 Fixes 62: key 1021 is FL$WHO, the openQM form - the user numbers of the sessions that hold the file open,
# a field mark between them - and the text form SD's messages use ("12 (don)") is FL$HOLDERS, 1100.  A phantom (zzb2hold)
# holds zzb2f open for a few seconds.  The rows use the number 1021 as well as the name, so that they say what the old build
# answered and not only that FL$WHO was undefined there.
WAIT_HOLDER = ("t = 0\nloop\n   if fileinfo(f, 1021) # '' then exit\n   sleep 1\n   t += 1\nuntil t > 30 repeat\n")
CASES += [
    ("1021 (62): FL$WHO is the manual's number and is null when no other session has the file open",
     FILES + "x = FL$WHO:'|[':fileinfo(f, FL$WHO):']'", r"1021\|\[\]"),
    ("...and the caller is in the list when it has the file open through a second file variable, not when through the one",
     FILES + "x = (fileinfo(f, 1021) = @userno):'|':(fileinfo(f, 1021) = '')\nopen 'zzb2f' to f2 else stop 'no f2'\n"
     "x := '|':(fileinfo(f, 1021) = @userno):(fileinfo(f2, 1021) = @userno)", r"0\|1\|11"),
    ("...another session that has it open is in it as a bare user number, and the text form is at 1100 (62)",
     FILES + "execute 'PHANTOM NO.MSG RUN bp zzb2hold' capturing o\nuid = @system.return.code\n" + WAIT_HOLDER +
     "x = fileinfo(f, 1021):'|':fileinfo(f, FL$HOLDERS):'|':uid:'|':FL$HOLDERS\nexecute 'LOGOUT ':uid capturing j\nsleep 1",
     r"(\d+)\|\1 \(.+\)\|\1\|1100"),
    ("...two such sessions are two numbers with a field mark between, in either order",
     FILES + "execute 'PHANTOM NO.MSG RUN bp zzb2hold' capturing o\nu1 = @system.return.code\n"
     "execute 'PHANTOM NO.MSG RUN bp zzb2hold' capturing o\nu2 = @system.return.code\n"
     "t = 0\nloop\n   if dcount(fileinfo(f, 1021), @fm) = 2 then exit\n   sleep 1\n   t += 1\nuntil t > 30 repeat\n"
     "l = fileinfo(f, 1021)\nx = dcount(l, @fm):'|':(index(@fm:l:@fm, @fm:u1:@fm, 1) > 0):(index(@fm:l:@fm, @fm:u2:@fm, 1) > 0):'|':(u1 # u2)\n"
     "execute 'LOGOUT ':u1 capturing j\nexecute 'LOGOUT ':u2 capturing j\nsleep 1",
     r"2\|11\|1"),
]

# OSPATH() is an internal function in SD (a user program cannot call it), so these run as internal programs, through
# `sd -internal`, the way sandbox-nocase.py does.  Their values are printed as I00[...] and so on.
ICASES = [
    ("20 (432): OSPATH(path, OS$INFO) is the same array for an operating system path - 35 fields, the full path twice, 5 for a file and 4 for a directory",
     "$include keys.h\ni = ospath('/etc/passwd', OS$INFO)\nj = ospath('/tmp', OS$INFO)\n"
     "x = OS$INFO:'|':dcount(i, @fm):'|':(i<20> = '/etc/passwd'):(i<27> = i<20>):'|':i<21>:j<21>:'|':(i<6> > 0):'|[':ospath('/nonexistent/zzb2', OS$INFO):']'",
     r"20\|35\|11\|54\|1\|\[\]"),
    ("...and its modification time is local like the file one", "$include keys.h\ni = ospath('/etc/passwd', OS$INFO)\n"
     "x = abs(((i<16> - 732) * 86400 + i<15>) - (i<35> + system(1019))) <= 1", r"1"),
    ("337: a hashed file's modification epoch (STATUS field 35) is the later of its primary and overflow subfiles' own times, read from the system. "
     "(NOT a red/green row: a rewrite touches both subfiles, so no case was found where only the overflow changes and the old code, which read the primary, agrees)",
     "execute 'DELETE.FILE zzb2big' capturing j\nexecute 'CREATE.FILE zzb2big DYNAMIC GROUP.SIZE 1' capturing j\nopen 'zzb2big' to f else stop 'no f'\n"
     "write str('a', 6000) on f, 'big1'\nwrite str('b', 6000) on f, 'big1'\np = fileinfo(f, 2)\nm0 = ospath(p : '/%0', 7)\nm1 = ospath(p : '/%1', 7)\n"
     "fi = fileinfo(f, 1013)\nx = ((m0 > 0) and (m1 > 0)):(fi<35> = if m0 > m1 then m0 else m1)\nexecute 'DELETE.FILE zzb2big' capturing j", r"11"),
    ("293: OS$FULLPATHX does what OS$FULLPATH (4) does - SD keeps the case already - and is key 4",
     "$include keys.h\na = ospath('/tmp/../tmp/Zzb2', OS$FULLPATHX)\nb = ospath('/tmp/../tmp/Zzb2', 4)\nx = OS$FULLPATHX:'|':(a = b):(a # '')", r"4\|11"),
]

CASES.append(
    ("1052, 1057, 1058: a phantom is the parent's one child and the parent's list holds its user number; the child sees its parent and no children",
     "execute 'DELETE.FILE zzb2p' capturing j\nexecute 'CREATE.FILE zzb2p' capturing j\nopen 'zzb2p' to p else stop 'no p'\n"
     "execute 'PHANTOM NO.MSG RUN bp zzb2ph' capturing o\nuid = @system.return.code\n"
     "t = 0\nloop\n   read r from p, 'ph' then exit\n   sleep 1\n   t += 1\nuntil t > 30 repeat\n"   # the phantom enters the user table a moment after PHANTOM returns
     "x = system(1052):'|':(system(1058) = uid):'|'\n"
     "x := (field(r, '|', 1) = system(22)):(field(r, '|', 2) = 0)\nt = 0\nloop\n   sleep 1\n   t += 1\nuntil system(1052) = 0 or t > 30 repeat\n"
     "x := '|':system(1052)\nexecute 'DELETE.FILE zzb2p' capturing j", r"1\|1\|11\|0"),
)

CASES.append(
    ("326: a catalogued $SYSTEM subroutine answers a key SD does not know, and is given the key as the number it was; known keys still answer themselves",
     "x = system(7001):'|':system(7002):'|':(system(1013) > 0):'|':system(32773)", r"K7001\|K7002\|1\|K32773"),
)

# A subroutine the cases call: who called it, and how deep in the CALL chain it is.  And the user-added SYSTEM() key
# handler, which answers 'K' and the key it was given.
SUBS = {"zzb2s1": "   subroutine zzb2s1(a, d)\n   a = system(33)\n   d = system(1076)\n   return\nend\n"}
# The handler is catalogued globally under the name $system - the source record is "system" and the $ is the global
# catalogue prefix (CATALOG bp system GLOBAL $); a $ in a SUBROUTINE name does not compile, and LOCAL refuses the prefix.
GLOBAL_SUBS = {"system": "   subroutine zzb2usr(result, key)\n   result = 'K':key\n   return\nend\n"}
# A program a phantom runs: it says what it sees of its parent, then lives for a few seconds.
PHANTOM_PROGS = {"zzb2ph": "   open 'zzb2p' to p else stop\n   write system(1057):'|':system(1052) on p, 'ph'\n   sleep 6\nend\n",
                 "zzb2hold": "   open 'zzb2f' to f else stop\n   sleep 25\nend\n"}   # 17 Oct 26: holds zzb2f open (FL$WHO rows)


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
    say("sandbox-sys-b2: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def isess(box, *cmds):
    """The same, in internal mode (sd -internal), where the restricted functions such as OSPATH() compile."""
    say("    > [sd -internal] %d commands" % len(cmds))
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"),
                       env=env, capture_output=True, text=True, errors="replace", timeout=300)
    out = ANSI.sub("", p.stdout + p.stderr)
    return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\[[0-9;]*[A-Za-z]", "", out.split(":TERM 200,9999", 1)[-1])


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-sys-b2.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-sys-b2: sandbox %s" % box)
    # A zone no machine is likely to be in (+05:45, no summer time), so rows about the LOCAL clock differ from UTC ones
    # whatever the machine uses; every subprocess below, the sandbox's sd included, inherits it.
    os.environ["TZ"] = "Asia/Kathmandu"
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-sys-b2: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for sub, src in SUBS.items():
        names.append(sub)
        with open(os.path.join(sysd, "bp", sub), "w") as f:
            f.write(src)
        cmds += ["BASIC bp %s" % sub, "CATALOG bp %s LOCAL" % sub]
    for sub, src in GLOBAL_SUBS.items():
        names.append(sub)
        with open(os.path.join(sysd, "bp", sub), "w") as f:
            f.write(src)
        cmds += ["BASIC bp %s" % sub, "CATALOG bp %s GLOBAL $" % sub]
    for prog, src in PHANTOM_PROGS.items():
        names.append(prog)
        with open(os.path.join(sysd, "bp", prog), "w") as f:
            f.write(src)
        cmds += ["BASIC bp %s" % prog]
    for i, (_, body, _w) in enumerate(CASES):
        nm = "zzb2%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write("   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'C%02d[':x:']'\nend\n" % i)
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    cmds += ["DELETE.CATALOG %s LOCAL" % sub for sub in SUBS]
    cmds += ["DELETE.CATALOG $%s" % sub for sub in GLOBAL_SUBS]
    cmds += ["DELETE.FILE zzb2f", "DELETE.FILE zzb2d", "DELETE.FILE zzb2c", "DELETE.FILE zzb2g"]
    try:
        out = sess(box, *cmds)
        say("\n--- the keys ------------------------------------------------------------------")
        for i, (label, _body, want) in enumerate(CASES):
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            row("%s: wanted /%s/" % (label, want), got is not None and re.fullmatch(want, got) is not None,
                "got %r" % got if m else "no output")
        say("\n--- internal programs (OSPATH) --------------------------------------------------")
        icmds = []
        for i, (_, body, _w) in enumerate(ICASES):
            nm = "zzb2i%02d" % i
            names.append(nm)
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write("$internal\n   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'I%02d[':x:']'\nend\n" % i)
            icmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
        iout = isess(box, *icmds)
        for i, (label, _body, want) in enumerate(ICASES):
            m = re.search(r"(?m)^I%02d\[(.*)\]\s*$" % i, iout)
            got = m.group(1) if m else None
            row("%s: wanted /%s/" % (label, want), got is not None and re.fullmatch(want, got) is not None,
                "got %r" % got if m else "no output: " + iout[-300:])
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-sys-b2: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
