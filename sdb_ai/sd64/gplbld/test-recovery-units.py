#!/usr/bin/env python3
"""test-recovery-units.py - the editors' recovery copy (S.88, plan 2.9, defect D2; the owner's answer to Q2 of 28 Oct 2026: "Build it, ship it off"), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-recovery-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-recovery-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
28 Oct 26 dm  New with the recovery copy.
28 Oct 26 dm  The TUI phase 2 review's findings (R10-R13, 11 mutants): a second Open of an untitled copy no longer wipes the first; a tab that found a copy it does not own
              looks again and writes its own when that copy is gone, and says so once (12783); an empty untitled tab taken away drops its copy; the IDE's break setting
              goes through $tk_brk at every way in and out.
28 Oct 26 dm  The editor merge's stage B: open.record reads under the record's lock (lock.take) and gives the lock back on Cancel (lock.free); R8f, R8j and the
              Cancel mutant follow it.
28 Oct 26 dm  The store moved to the person's Linux home (the owner's approval of 28 Oct): R7b (any account with a register record; the home from SD_USER_HOME,
              never root; the account's name one directory name), R7d / R7d2 (the directories made and trusted one at a time from the home down), R7h (a moved
              copy keeps its date), R7i / R7j / R7k (the store, then the first version's directory), R14 (the first version's copies offered once, moved with the
              switch on), R15 (nothing written in the account); R8b allows the countdown's idle.count before rc.tick; 14 new mutants, 4 replaced.  The C test of
              the home is test-userhome-units.py.
28 Oct 26 dm  Review fix (finding 3 of the L2 review): R14 follows 'find' leaving a first-version copy in the account with the switch OFF (it deleted it before the person
              had answered); the mutant "an old copy is removed with the switch off" is new, the "moved into the account" one is rewritten for the new initial value.
30 Oct 26 dm  The first version's code is removed from edit_recovery (the owner deferred to Opus's recommendation, 29 Oct): R7b, R7h, R7i, R7j and R7k lose their old-copy parts,
              R14 now says the first version's names are gone and R15 that nothing is written in the account; the six old-copy mutants are replaced by two.
30 Oct 26 dm  Stage E2: the tab of an operating system file is made in path.tab.make (open.path's tail, shared with New): R8j asks it, not open.path, for rc.init.tab; two mutants.
10 Nov 26 Windows port - carried from Linux 7bc274b9 (RELEASE_1.1 197).  Four rows read the Windows shape of the same code: R3b modify.account's
              `case upcase(action) = ...` arms set os.field and os.want on two lines and fall out of the case (no return); R3d bounds os.set at tier.set:,
              which follows it here (the suspend arms' audit lines come later in the file); R5b the user account's fields are written in create_account's
              `if acc.type = "USER" then` block; R6 acc_os_info's gate keys are in its `if typ = 'USER' then` block.
END-HISTORY

WHAT IT HOLDS.  The switch is register field 19 (ACC$RECOVERY), OFF AS DELIVERED: blank means no, CREATE.ACCOUNT writes 'no' unless RECOVERY-ON was typed, and there is
no upgrade walk.  SDSYS turns it on per account (MODIFY.ACCOUNT RECOVERY-ON / RECOVERY-OFF, slot RC, audited by os.set's one line, which never holds any text but
the word and the account).  A USER account only, refused elsewhere with 12776, in MODIFY.ACCOUNT and in CREATE.ACCOUNT before anything is made.  The backup manifest
carries it (recovery: 1 / 0, USER arm) and RESTORE.ACCOUNT gives it back only for an explicit 1.

!edit_recovery (gpl.bp/edit_recovery) keeps the copies: since 28 Oct 26 in the person's Linux home, <home>/.local/state/sd/recovery/<account>, the home from the
password database (SDEXT SD_USER_HOME; never $HOME, never root), every directory from the home down trusted only when it is a real directory of that user's that
nobody else can write (made under umask 077 when missing), and the account's own one used only when the kernel's SD_FILE_PRIVATE (lstat, owner, no group or other
bits) says so - any account with a register record, the administrator too (it was a USER account and its own person only, in <account>/$recovery; a copy left there
is offered, moved into the store when the switch is on and removed from the account only then - with the switch off it stays until the person's answer); a copy is
written under umask 077, unlinked first when what is at its name is not a private file, removed when the write fails, when it is not private afterwards or when it
does not read back identical; a copy is offered only when its magic, account, length and SHA-256 hold and it is the record asked for.  It writes no audit line and
reaches nothing outside the directory (no OPENSEQ, no OS.EXECUTE).

The IDE: rc.tick returns at once when the switch is off (so nothing at all is written: the delivered state); it runs after a second of quiet, at the end of the
input, at Ctrl-Q y in the cursor lock and before the screen is handed to a program.  A save that wrote drops the copy, Close drops it after the person's answer,
a normal quit drops all; a record is offered its copy BEFORE a tab is made, Cancel makes no tab, Enter is Use the copy (which writes nothing), and no routine of the
copy writes to a file variable of the IDE.  A copy the tab does not own is looked for before the first write and is never written over; the person is told once
(12783), it is looked for again every RC.LOOK seconds, and once it is gone the tab writes its own.  Each recovered untitled tab is put in the editor as soon as it
is made (a second Open used to write the empty startup buffer over the first), and an empty untitled tab that is taken away drops the copy it owns.  The IDE's
break setting is kept by $tk_brk (save at the start and when it takes the screen back, close at every way out and when it hands the screen to a program).

***IT READS THE SOURCE AS TEXT.***  That a hang-up leaves a 0600 file holding the text, that nothing is written with the switch off, and that the copy comes back
when the record is opened are rows of sandbox-recovery.py (a private SD), which this check cannot replace.  --selftest requires each mutation to match its text
exactly once and to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.join(HERE, os.pardir, "sdsys")
FILES = {
    "keys": os.path.join(SDSYS, "syscom", "keys.h"),
    "cah": os.path.join(SDSYS, "syscom", "createacc.h"),
    "modifya": os.path.join(SDSYS, "gpl.bp", "modifya"),
    "createa": os.path.join(SDSYS, "gpl.bp", "createa"),
    "create_account": os.path.join(SDSYS, "gpl.bp", "create_account"),
    "acc_os_info": os.path.join(SDSYS, "gpl.bp", "acc_os_info"),
    "restorea": os.path.join(SDSYS, "gpl.bp", "restorea"),
    "edit_recovery": os.path.join(SDSYS, "gpl.bp", "edit_recovery"),
    "ide": os.path.join(SDSYS, "gpl.bp", "ide"),
}
MSGS = range(12775, 12784)


def strip(src):
    """the code without comment lines and trailing ;* comments"""
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def between(text, start, end):
    a = text.find(start)
    if a < 0:
        return ""
    b = text.find(end, a + len(start))
    return text[a:] if b < 0 else text[a:b]


def label(text, name):
    """the body of internal subroutine `name:` up to the next label at the start of a line"""
    m = re.search(r"^%s:\n" % re.escape(name), text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    n = re.search(r"^[a-z][a-z0-9.]*:\s*$", rest, re.M)
    return rest[:n.start()] if n else rest


def ordered(text, *parts):
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def checks(src, msgs):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    kh = src["keys"]
    defs = re.findall(r"\$define\s+(ACC\$[A-Z.]+)\s+(\d+)\b", kh)
    nums = [n for _, n in defs]
    ck("R1 keys.h defines ACC$RECOVERY as register field 19, and no other ACC$ name has 19",
       ("ACC$RECOVERY", "19") in defs and nums.count("19") == 1, "%s" % [d for d in defs if d[1] == "19"])
    ch = src["cah"]
    ck("R2 createacc.h defines CA$RECOVERY as 44, and no other name has 44",
       re.search(r"\$define\s+CA\$RECOVERY\s+44\b", ch) is not None and len(re.findall(r"\$define\s+\S+\s+44\b", ch)) == 1, "")

    mo = strip(src["modifya"])
    m_words = re.search(r"word\.arr = convert\(',', @fm, '([^']*)'\)", mo)
    m_slots = re.search(r"slot\.arr = convert\(',', @fm, '([^']*)'\)", mo)
    words = m_words.group(1).split(",") if m_words else []
    slots = m_slots.group(1).split(",") if m_slots else []
    ok3 = ("RECOVERY-ON" in words and "RECOVERY-OFF" in words and words.index("RECOVERY-OFF") == words.index("RECOVERY-ON") + 1 and len(words) == len(slots)
           and slots[words.index("RECOVERY-ON")] == slots[words.index("RECOVERY-OFF")] == "RC" and slots.count("RC") == 2)
    ck("R3 modify.account: RECOVERY-ON and RECOVERY-OFF are in the word list one after the other and share a slot (RC) that no other word has", ok3, "")
    ck("R3b ...do.action: RECOVERY-ON sets ACC$RECOVERY wanted true and RECOVERY-OFF false, both through os.set (one register write, under the lock, one audit line)",
       # 10 Nov 26 Windows port: `case upcase(action) = ...`, os.field and os.want on two lines, and the arm ends at the next case (Linux: one line, then return)
       re.search(r"case upcase\(action\) = 'RECOVERY-ON'\s*\n\s*os\.field = ACC\$RECOVERY\s*\n\s*os\.want\s+= @true\s*\n\s*gosub os\.set\s*\n\s*case ", mo) is not None
       and re.search(r"case upcase\(action\) = 'RECOVERY-OFF'\s*\n\s*os\.field = ACC\$RECOVERY\s*\n\s*os\.want\s+= @false\s*\n\s*gosub os\.set\s*\n\s*case ", mo) is not None, "")
    osb = mo[mo.find("\nos.set:\n"):]
    osb = osb[:osb.find("\ntier.set:\n")] if "\ntier.set:\n" in osb else osb   # 10 Nov 26 Windows port: os.set ends where tier.set begins
    refuse = osb[:osb.find("   return\n   end\n") + 1] if "\nos.set:\n" in mo else ""
    ck("R3c ...os.set refuses it for any account whose group is not sdu_ (ACC$RECOVERY is NOT among the fields let through on a group account) and says why with 12776, "
       "before the register is read for update",
       "if group.name[1,4] # 'sdu_' and" in refuse and "ACC$RECOVERY" not in refuse.split(" then\n")[0]
       and ordered(osb, "if group.name[1,4] # 'sdu_' and", "if os.field = ACC$RECOVERY then", "crt sysmsg(12776, acc.name)", "end else", "crt sysmsg(10105, acc.name)", "return",
                   "readu acc.new from acc.f, acc.name"), "")
    ck("R3d ...the state line 12775 names only the recovery field and comes after the one audit line, which holds the word and the account and nothing else",
       ordered(osb, "void kernel(K$AUDIT, 'modify.account ' : downcase(action) : ' account=' : acc.name)", "if os.field = ACC$RECOVERY then",
               "crt sysmsg(12775, acc.name, if upcase(trim(acc.new<ACC$RECOVERY>)) = 'YES' then 'yes' else 'no')", "return")
       and osb.count("K$AUDIT") == 1, "")
    usage = between(mo, "\nshow.usage:\n", "\n   return\n")
    ck("R3e ...the usage and the list of actions name recovery-on and recovery-off, in lower case",
       "modify.account <account> recovery-on | recovery-off'" in usage and "recovery-on, recovery-off," in mo, "")

    ca = strip(src["createa"])
    more = ca[ca.find("\nmore.args:\n"):]
    ck("R4 create.account: RECOVERY-ON sets CA$RECOVERY to 1 (nothing else sets it); RECOVERY-OFF, which restates the delivered state, is not a word of this verb; "
       "the syntax line names {recovery-on} and the audit gates= list names recovery-on",
       re.search(r"case upcase\(token\) = 'RECOVERY-ON'\s*\n\s*settings<CA\$RECOVERY> = 1\s*\n", more) is not None
       and len(re.findall(r"(?<!if )settings<CA\$RECOVERY>\s*=", ca)) == 1 and "RECOVERY-OFF" not in ca
       and "{pins-on} {recovery-on} {no.query}" in ca and "if settings<CA$RECOVERY> = 1 then gates<-1> = 'recovery-on'" in ca, "")

    cr = strip(src["create_account"])
    grp = between(cr, "   case acc.type = 'GROUP'\n", "   case acc.type = 'OTHER'\n")
    oth = between(cr, "   case acc.type = 'OTHER'\n", "pathname = trim(settings<CA$PATH>)")
    refuse_txt = "if recovery.want then\n       @system.return.code = -ER$ARGS\n       err = 12776:@vm:acc.name\n       goto exit.create\n     end"
    ck("R5 !create_account: a request is exactly 1; a group account and an other account are refused with 12776 in their own arms, before anything is made",
       "recovery.want = (settings<CA$RECOVERY> = 1)" in cr and refuse_txt in grp and refuse_txt in oth
       and cr.find("recovery.want = (settings<CA$RECOVERY> = 1)") < cr.find(refuse_txt) < cr.find("gosub make.account"), "")
    user = between(cr, '   if acc.type = "USER" then\n      acc.rec<ACC$SH>', '   end else\n')   # 10 Nov 26 Windows port: the user account's block
    ck("R5b ...a user account's record says 'yes' or 'no' explicitly ('no' unless asked: OFF AS DELIVERED), no other arm writes the field, and the state line 12775 is said",
       "acc.rec<ACC$RECOVERY> = if recovery.want then 'yes' else 'no'" in user and cr.count("acc.rec<ACC$RECOVERY>") == 2
       and "crt sysmsg(12775, acc.name, acc.rec<ACC$RECOVERY>)" in cr, "")

    ai = strip(src["acc_os_info"])
    ck("R6 the backup manifest has recovery: 1 only when the register says yes, in the USER arm only",
       "info<-1> = 'recovery: ':(if upcase(trim(acc.rec<ACC$RECOVERY>)) = 'YES' then 1 else 0)" in between(ai, "   if typ = 'USER' then\n      info<-1> = 'os.sh: '", "\n   end\n")   # 10 Nov 26 Windows port: the gate keys' block
       and ai.count("'recovery: '") == 1, "")
    ra = strip(src["restorea"])
    ck("R6b RESTORE.ACCOUNT reads the key and asks for the switch only when the manifest says exactly 1 (a manifest that has none: off)",
       "case sec.keys<s.idx,kp> = 'recovery'    ; m.recovery = kv" in ra and "settings<CA$RECOVERY> = (if m.recovery = '1' then 1 else '')" in ra
       and ra.find("m.recovery = ''") < ra.find("m.recovery = kv"), "")

    er_raw = src["edit_recovery"]
    er = strip(er_raw)
    where = label(er, "where")
    ck("R7 !edit_recovery is $internal, catalogued as !edit_recovery and holds no audit line, no OPENSEQ, no OS.EXECUTE and no EXECUTE",
       er.lstrip().startswith("$internal") and "\n$catalog !edit_recovery\n" in er and "subroutine edit_recovery(op, rfile, rid, text, res)" in er
       and "K$AUDIT" not in er and not re.search(r"\b(openseq|os\.execute|execute|perform)\b", er, re.I), "")
    ck("R7b WHO (28 Oct 26, the store in the person's home): the account must have a register record; the Linux user this process runs as (K$USERNAME) is never empty "
       "or root; the account's name is one directory name (letters, digits, . _ -, not starting with .); rc.mine needs the home SD_USER_HOME trusts, and nothing about "
       "the account's group (any kind of account, the administrator too); rc.on needs rc.mine AND field 19 = yes",
       ordered(where, "rc.mine = 0", "rc.on = 0", "rc.home = ''", "rc.dir = ''", "rc.user = downcase(trim(kernel(K$USERNAME, 0)))", "if arec = '' then return",
               "if rc.user = '' or rc.user = 'root' then return", "if rc.acct = '' or rc.acct[1, 1] = '.' then return",
               "if convert(ACCT.CHARS, '', rc.acct) # '' then return", "rc.home = SDEXT('', @FALSE, SD_USER_HOME)", "if rc.home = '' then return",
               "rc.rel = STORE : '/' : rc.acct", "rc.dir = rc.home : '/' : rc.rel", "rc.mine = 1", "if upcase(trim(arec<ACC$RECOVERY>)) = 'YES' then rc.on = 1", "return")
       and "ACCT.CHARS = 'abcdefghijklmnopqrstuvwxyz0123456789._-'" in er and "STORE = '.local/state/sd/recovery'" in er
       and where.count("rc.mine = 1") == 1 and where.count("rc.on = 1") == 1 and "'sdu_'" not in where[where.find("rc.home = SDEXT"):], "")
    wr = label(er, "do.write")
    ck("R7c WRITE refuses ('off') unless rc.on, and the directory is made and checked private before it is opened",
       ordered(wr, "res = 'off'", "if not(rc.on) then return", "gosub make.dir", "if not(dir.ok) then return", "openpath rc.dir to rf else return", "mark.mapping rf, off"), "")
    md = label(er, "make.dir")
    ck("R7d ...the store's directories are made one at a time from the home down, each ONLY when SD_USER_HOME does not already trust it and nothing is there (something there "
       "that it does not trust stops it), under umask 077 (63) put back at once, and each is asked again before the next; the private check of the account's own follows",
       ordered(md, "dir.ok = @false", "if rc.home = '' then return", "for md.i = 1 to md.n", "md.path = rc.home : '/' : md.rel",
               "if SDEXT(md.rel, @FALSE, SD_USER_HOME) # md.path then", "if ospath(md.path, OS$EXISTS) then return", "rc.um = umask(63)", "void ospath(md.path, OS$MKDIR)",
               "if umask(rc.um) then null", "if SDEXT(md.rel, @FALSE, SD_USER_HOME) # md.path then return", "next md.i", "gosub check.dir"), "")
    cd = label(er, "check.dir")
    ck("R7d2 check.dir trusts the store only when SD_USER_HOME answers EXACTLY its path (every directory from the home down a real one of this user's that nobody else can write) "
       "AND SD_FILE_PRIVATE says it is this user's alone (0700)",
       ordered(cd, "dir.ok = @false", "if rc.home = '' then return", "if SDEXT(rc.rel, @FALSE, SD_USER_HOME) # rc.dir then return", "gosub private.dir")
       and label(er, "private.dir").strip().startswith("dir.ok = (SDEXT(rc.dir : @FM : 'DIR', @TRUE, SD_FILE_PRIVATE) = '1')"), "")
    ck("R7e ...what is at the copy's name is unlinked unless it is a private file; the copy is written under umask 077 ON ERROR and the umask put back before anything else; a failed write is removed",
       ordered(wr, "gosub check.file", "if not(file.ok) then", "delete rf, rc.slot on error null", "rc.um = umask(63)", "write rec to rf, rc.slot on error rc.written = @false",
               "if umask(rc.um) then null", "if not(rc.written) then", "delete rf, rc.slot on error null", "res = 'write'"), "")
    ck("R7f ...after the write the copy must be a private file (removed, 'mode', otherwise) and read back identical (removed, 'verify', otherwise); only then is res empty",
       ordered(wr, "res = 'write'", "gosub check.file", "if not(file.ok) then", "delete rf, rc.slot on error null", "res = 'mode'", "read chk from rf, rc.slot else chk = ''",
               "if chk # rec then", "delete rf, rc.slot on error null", "res = 'verify'", "res = ''"), "")
    ck("R7g the private tests are the kernel's lstat-based SD_FILE_PRIVATE, DIR for the directory and FILE for a copy, each compared with the text '1'",
       "dir.ok = (SDEXT(rc.dir : @FM : 'DIR', @TRUE, SD_FILE_PRIVATE) = '1')" in er and "file.ok = (SDEXT(rc.path : @FM : 'FILE', @TRUE, SD_FILE_PRIVATE) = '1')" in er, "")
    ck("R7h a copy carries its own check: the magic, the account, the length and the SHA-256 of the text, all written and all tested before a copy is believed",
       "rec = MAGIC : @fm : rc.acct : @fm : rfile : @fm : rid : @fm : wr.date : @fm : wr.time : @fm : len(text) : @fm : downcase(digest(text, 0, 'SHA256')) : @fm : text" in wr
       and ordered(wr, "wr.date = date()", "wr.time = int(time())", "rec = MAGIC")
       and ordered(label(er, "parse.copy"), "cp.ok = 0", "if rec<1> # MAGIC then return", "if rec<2> # rc.acct then return", "if len(cp.text) # cp.len + 0 then",
                   "if downcase(digest(cp.text, 0, 'SHA256')) # rec<8> then", "cp.ok = 1"), "")
    fd = label(er, "do.find")
    ck("R7i FIND needs rc.mine, the trusted directory and a private file BEFORE it reads, and answers only for a whole copy of the very record asked for, and for nothing else "
       "(the first version's directory is not looked at since 30 Oct 26)",
       ordered(fd, "res = ''", "if not(rc.mine) then return", "gosub check.dir", "if dir.ok then", "gosub check.file", "if file.ok then",
               "read rec from rf, rc.slot", "gosub parse.copy", "if cp.ok and cp.file = rfile and cp.id = rid then", "text = cp.text", "res = 1", "return"), "")
    dr = label(er, "do.drop")
    dl = label(er, "do.list")
    ld = label(er, "list.dir")
    ck("R7j DROP and LIST need rc.mine and a checked directory (the store's); DROP removes only a private file; LIST takes an id once",
       ordered(dr, "if not(rc.mine) then return", "gosub check.dir", "if dir.ok then", "gosub check.file", "if file.ok then", "delete rf, rc.slot")
       and ordered(dl, "if not(rc.mine) then return", "gosub check.dir", "if dir.ok then gosub list.dir")
       and ordered(ld, "gosub check.file", "if file.ok then", "locate cp.id in ls.ids<1,1> setting ls.pos else", "ls.ids<1, -1> = cp.id"), "")   # <1,1>: in <1> LOCATE walks fields (S.185)
    ck("R7k the copies are read and written in image mode (MARK.MAPPING OFF) wherever a copy's bytes are read or written",
       "mark.mapping rf, off" in wr and "mark.mapping rf, off" in fd and "mark.mapping rf, off" in ld, "")

    # ---- 28 Oct 26: the store in the person's home; 30 Oct 26: the first version's copies are not looked for at all --------------------------------------------------------
    ck("R14 THE FIRST VERSION'S CODE IS GONE (30 Oct 26): its names for a copy were 65 characters, which a directory file refused, so no copy of it can exist; nothing names "
       "'$recovery', rc.old, old.find or an old-copy variable (of., od., ol.)",
       "$recovery" not in er and "rc.old" not in er and "old.find" not in er and not re.search(r"\b(of|od|ol)\.", er), "")
    ck("R15 NOTHING IS WRITTEN IN THE ACCOUNT: do.write is reached only from the op, the one gosub private.dir is check.dir's (with SD_USER_HOME's way down), and no path is built from "
       "the account's directory (ACC$PATH is not read)",
       er.count("gosub do.write") == 1 and er.count("SD_USER_HOME") == 4 and er.count("gosub private.dir") == 1 and "ACC$PATH" not in er,
       "%d %d %d" % (er.count("gosub do.write"), er.count("SD_USER_HOME"), er.count("gosub private.dir")))

    ide = strip(src["ide"])
    tick = label(ide, "rc.tick")
    ck("R8 the IDE asks the switch once at the start; rc.tick does NOTHING (its first statement returns) when it is off - the delivered state writes nothing anywhere",
       "call !edit_recovery('on', '', '', '', rc.on)" in ide and tick.lstrip().startswith("if not(rc.on) then return"), "")
    loop_end = between(ide, "case ev<1> = 'end'", "case 1\n")
    ck("R8b rc.tick runs at the end of the input (a hang-up), after a second of quiet, at Ctrl-Q y in the cursor lock and before the screen is handed to a program",
       re.search(r"case ev<1> = 'end'\s*\n\s*gosub rc\.tick\s*\n\s*done = @true", ide) is not None
       and re.search(r"case ev<1> = 'timeout'\s*\n(?:\s*gosub idle\.count[^\n]*\n)?\s*gosub rc\.tick", loop_end) is not None
       and re.search(r"case edata = 'guardquit'\s*\n\s*gosub rc\.tick\s*\n\s*done = @true", ide) is not None
       and label(ide, "leave.screen").lstrip().startswith("gosub rc.tick"), "")
    ck("R8c rc.tick: a buffer without changes loses its copy; a changed one is written only when its text differs from the copy it owns, and a copy it does not own is "
       "looked for (find) BEFORE any write and never written over",
       ordered(tick, "gosub is.dirty", "if not(dirty) then", "gosub rc.drop.tab", "end else", "rt.write = @true", "if rq = rk.now then", "if bx{k} = rt.text then rt.write = @false",
               "end else", "call !edit_recovery('find', rk.file, rk.id, rt.other, rr)", "if rr # '' then", "rt.write = @false", "if rt.write then",
               "call !edit_recovery('write', rk.file, rk.id, rt.text, rr)")
       and tick.count("call !edit_recovery('write'") == 1, "")
    sv = label(ide, "save.one")
    ck("R8d a save drops the copy only AFTER the write succeeded (after the ON ERROR branch and the lock is given back)",
       ordered(sv, "write sv.out on fv, sv.id on error", "return", "release fv, sv.id", "sv.ok = @true", "ri = sv.i", "gosub rc.drop.tab", "msg = sysmsg(12207"), "")
    cl = label(ide, "close.current")
    qt = label(ide, "do.quit")
    ck("R8e Close drops the copy after the person's answer (Cancel returns first); a normal quit drops every copy only when nothing was cancelled",
       ordered(cl, "if dirty then", "case 1", "return", "end case", "ri = cb", "gosub rc.drop.tab", "del bn<cb>")
       and ordered(qt, "if not(abort) then", "for ri = 1 to nbuf", "gosub rc.drop.tab", "next ri", "done = @true"), "")
    orc = label(ide, "open.record")
    ck("R8f opening a record offers its copy BEFORE the tab is made, Cancel opens nothing (and gives back the lock the open took: stage B, 28 Oct 26), and only 'use' "
       "puts the copy's text in the buffer (the disk record stays the saved text)",
       ordered(orc, "gosub lock.take", "if not(lk.exists) then", "gosub rc.offer", "case rc.choice = 'use'", "case rc.choice = 'cancel'", "gosub lock.free", "return",
               "rc.disk = rec", "gosub rc.offer", "if rc.choice = 'cancel' then", "gosub lock.free", "return", "nbuf += 1",
               "bx{k} = rec", "if rc.choice = 'use' then tb.shown = rc.text", "bx{k} = tb.shown", "gosub rc.init.tab"), "")
    an = label(ide, "add.new.record")
    ck("R8g a new record that has a copy is offered it too, before its tab; Cancel makes no tab and do.new stops",
       ordered(an, "an.made = @false", "gosub rc.offer", "if rc.choice = 'cancel' then return", "nbuf += 1", "gosub rc.init.tab", "an.made = @true")
       and re.search(r"gosub add\.new\.record\s*\n\s*if not\(an\.made\) then return", ide) is not None, "")
    of = label(ide, "rc.offer")
    ck("R8h the question: three buttons, Enter (default 1) is Use the copy, Esc is Cancel; Use writes nothing, Delete removes the copy, a copy equal to the disk record is removed unasked",
       "buttons 'Use the copy,Delete the copy,Cancel' default 1 returning rc.b else rc.b = 3" in of
       and ordered(of, "call !edit_recovery('find', rc.file, rc.id, rc.text, rc.res)", "if rc.res = '' then return", "if rc.has.disk and rc.text = rc.disk then",
                   "call !edit_recovery('drop'", "case rc.b = 1", "rc.choice = 'use'", "case rc.b = 2", "call !edit_recovery('drop'", "case 1", "rc.choice = 'cancel'")
       and "write" not in between(of, "case rc.b = 1", "case rc.b = 2"), "")
    rc_all = "".join(label(ide, n) for n in ("rc.init.tab", "rc.took", "rc.key", "rc.drop.tab", "rc.tick", "rc.offer", "rc.untitled"))
    ck("R8i no routine of the copy writes a record, opens a file or audits: the record is written only by the person's save",
       len(rc_all) > 2000 and not re.search(r"(?:^|\bthen|\belse)\s*(write|writeu|writev|open|openpath|openseq|delete)\s", rc_all, re.M) and "K$AUDIT" not in rc_all,
       "%d characters" % len(rc_all))
    ck("R8j every tab the IDE makes starts owning no copy (open.record, add.untitled, add.new.record and, since stage E, path.tab.make - the tail of open.path that New with an operating system "
       "name uses too, 30 Oct 26 - call rc.init.tab; open.path itself makes its tab only by calling path.tab.make), and a bare IDE offers the untitled copies (not one that starts on an operating "
       "system file: path0)",
       "gosub rc.init.tab" in orc and "gosub rc.init.tab" in label(ide, "add.untitled") and "gosub rc.init.tab" in an and "gosub rc.init.tab" in label(ide, "path.tab.make")
       and "gosub path.tab.make" in label(ide, "open.path") and "nbuf += 1" not in label(ide, "open.path")
       and ide.count("gosub rc.init.tab") == 4
       and "if id0 = '' and not(seq0) and sel0 = '' and path0 = '' then gosub rc.untitled" in ide, "")

    # ---- 28 Oct 26: the TUI phase 2 review's findings
    rcu = label(ide, "rc.untitled")
    opn = between(rcu, "case rc.b = 1", "case rc.b = 2")
    ck("R10 a bare IDE's Open puts the copy's text in a NEW tab, the tab takes the copy, and the editor is made to hold that tab at once (load.current) - before the next "
       "question, so that the next Open's stash.current does not write the empty startup buffer over it; nothing in Open deletes a copy",
       ordered(opn, "gosub drop.clean.untitled", "gosub add.untitled", "bx{k} = rc.text", "gosub set.token.mode", "gosub rc.took", "gosub load.current", "rc.got = @true")
       and "!edit_recovery('drop'" not in opn
       and ordered(label(ide, "add.untitled"), "gosub stash.current", "nbuf += 1"), "")
    ck("R11 rc.tick: a copy the tab does not own is looked for again after RC.LOOK seconds (not once for ever): found, the tab writes nothing, the next look is set, and the person "
       "is told once (12783); not found, the key is forgotten and the tab writes its own copy",
       ordered(tick, "rt.seen = @false", "if rx # '' then rt.seen = (rx<1, 1> = rk.file and rx<1, 2> = rk.id)", "if rt.seen and rt.now < rx<1, 3> + 0 then", "rt.write = @false",
               "end else", "call !edit_recovery('find', rk.file, rk.id, rt.other, rr)", "if rr # '' then", "rt.write = @false", "bx{k} = rk.now : @vm : rt.now + RC.LOOK",
               "if not(rt.seen) then", "msg = sysmsg(12783, bf.name, bf.id)", "end else", "bx{k} = ''", "if rt.write then")
       and re.search(r"^\s*RC\.LOOK = \d+\s*$", ide, re.M) is not None, "")
    dcu = label(ide, "drop.clean.untitled")
    ck("R12 an untitled tab with no text that is taken away (a record opened or made in its place) drops the copy it owns first",
       ordered(dcu, "if bx{k} = '' then", "ri = cb", "gosub rc.drop.tab", "del bn<cb>"), "")
    main_exit = between(ide, "until done", "* ======")
    ck("R13 the break setting: read, kept by $tk_brk ('save') and only then turned off at the start; given back by $tk_brk ('close') on the four ways out (a window too small, "
       "no screen, the end, the screen handed to a program) and never by hand; read and kept again when the screen is taken back",
       ordered(ide, "saved.trap = pterm(PT$BREAK, -1)", "call $tk_brk('save', saved.trap)", "void pterm(PT$BREAK, @false)", "break off", "call $sl_need(")
       and ordered(ide, "if need.msg # '' then", "call $tk_brk('close', saved.trap)", "stop", "if not(opened) then", "call $tk_brk('close', saved.trap)", "stop")
       and ordered(main_exit, "screen close", "call $tk_brk('close', saved.trap)", "stop")
       and ordered(label(ide, "leave.screen"), "gosub rc.tick", "screen close", "call $tk_brk('close', saved.trap)")
       and ordered(label(ide, "retake.quiet"), "saved.trap = pterm(PT$BREAK, -1)", "call $tk_brk('save', saved.trap)", "void pterm(PT$BREAK, @false)", "break off", "gosub open.screen")
       and ide.count("call $tk_brk('close', saved.trap)") == 4 and ide.count("call $tk_brk('save', saved.trap)") == 2
       and not re.search(r"^\s*break on\s*$", ide, re.M) and "pterm(PT$BREAK, saved.trap)" not in ide, "")

    mt = {n: msgs.get(n) for n in MSGS}
    ck("R9 messages 12775-12783 exist, one line each, and none names a command word in capitals",
       all(t is not None and t.count("\n") == 1 and t.endswith("\n") for t in mt.values())
       and not any(re.search(r"RECOVERY-O|MODIFY\.ACCOUNT|CREATE\.ACCOUNT", t or "") for t in mt.values()), "%s" % [n for n, t in mt.items() if t is None])
    return rows


def load():
    src = {}
    for k, p in FILES.items():
        with open(p, encoding="latin-1") as f:
            src[k] = f.read()
    msgs = {}
    for n in MSGS:
        p = os.path.join(SDSYS, "messages", str(n))
        if os.path.isfile(p):
            with open(p, encoding="latin-1") as f:
                msgs[n] = f.read()
    return src, msgs


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


# (file, name, old, new): each must match its file's text once and be caught
MUTANTS = [
    ("keys", "the field number is shared with ACC$PINS", "$define ACC$RECOVERY     19", "$define ACC$RECOVERY     18"),
    ("modifya", "the recovery words take the dict slot", "DICT,DICT,RC,RC,NET", "DICT,DICT,DICT,DICT,NET"),
    ("modifya", "RECOVERY-ON writes no", "            os.field = ACC$RECOVERY\n            os.want  = @true\n", "            os.field = ACC$RECOVERY\n            os.want  = @false\n"),   # 10 Nov 26 Windows port: two lines
    ("modifya", "a group account may have it", "and os.field # ACC$PINS then", "and os.field # ACC$PINS and os.field # ACC$RECOVERY then"),
    ("modifya", "the state line is not said", "      crt sysmsg(12775, acc.name, if upcase(trim(acc.new<ACC$RECOVERY>)) = 'YES' then 'yes' else 'no')", "      null"),
    ("createa", "recovery-on is not on the audit line", "   if settings<CA$RECOVERY> = 1 then gates<-1> = 'recovery-on'", "   null"),
    ("createa", "RECOVERY-OFF is taken too", "         case upcase(token) = 'RECOVERY-ON'\n", "         case upcase(token) = 'RECOVERY-OFF'\n            null\n         case upcase(token) = 'RECOVERY-ON'\n"),
    ("create_account", "a new user account is on unless asked", "acc.rec<ACC$RECOVERY> = if recovery.want then 'yes' else 'no'", "acc.rec<ACC$RECOVERY> = 'yes'"),
    # 10 Nov 26 Windows port: the comment above the group arm's refusal names the carry, not Linux's 28 Oct line
    ("create_account", "a group account is not refused", "(S.88 plan 2.9, D2): nor a recovery copy: it is kept in the account's directory, where every member can rename entries (12776).\n     if recovery.want then",
     "(S.88 plan 2.9, D2): nor a recovery copy: it is kept in the account's directory, where every member can rename entries (12776).\n     if @false then"),
    ("acc_os_info", "the manifest says 1 for a blank field", "(if upcase(trim(acc.rec<ACC$RECOVERY>)) = 'YES' then 1 else 0)", "(if upcase(trim(acc.rec<ACC$RECOVERY>)) # 'NO' then 1 else 0)"),
    ("restorea", "a manifest without the key restores it on", "(if m.recovery = '1' then 1 else '')", "(if m.recovery # '0' then 1 else '')"),
    # 28 Oct 26: the store in the person's home
    ("edit_recovery", "root gets copies", "   if rc.user = '' or rc.user = 'root' then return", "   if rc.user = '' then return"),
    ("edit_recovery", "an account name with a slash is a path in the store", "   if convert(ACCT.CHARS, '', rc.acct) # '' then return", "   null"),
    ("edit_recovery", "the store is $HOME's", "   rc.home = SDEXT('', @FALSE, SD_USER_HOME)", "   rc.home = env('HOME')"),
    ("edit_recovery", "the store is the account's directory again", "   rc.dir = rc.home : '/' : rc.rel\n", "   rc.dir = apath : '/$recovery'\n"),
    ("edit_recovery", "a session with no trusted home still has copies", "   if rc.home = '' then return\n   rc.rel = STORE", "   rc.rel = STORE"),
    ("edit_recovery", "the store is trusted without asking the way down", "   if SDEXT(rc.rel, @FALSE, SD_USER_HOME) # rc.dir then return\n", ""),
    ("edit_recovery", "a directory that is there and not trusted is used", "         if ospath(md.path, OS$EXISTS) then return             ;* there, and not to be trusted\n", ""),
    ("edit_recovery", "a made directory is not asked again", "         if SDEXT(md.rel, @FALSE, SD_USER_HOME) # md.path then return\n", ""),
    ("edit_recovery", "the first version's directory is named again", "   rc.dir = ''\n   rc.acct", "   rc.dir = ''\n   rc.old = apath : '/$recovery'\n   rc.acct"),
    ("edit_recovery", "a second write is reached from a path of the account", "   gosub do.write\n", "   gosub do.write\n   gosub do.write\n"),
    ("edit_recovery", "a list holds an id twice", "                  locate cp.id in ls.ids<1,1> setting ls.pos else", "                  locate cp.id in ls.ids<1> setting ls.pos else"),
    ("edit_recovery", "the switch is not asked", "   if upcase(trim(arec<ACC$RECOVERY>)) = 'YES' then rc.on = 1\n", "   rc.on = 1\n"),
    ("edit_recovery", "a write does not need the switch", "   res = 'off'\n   if not(rc.on) then return\n", "   res = 'off'\n"),
    ("edit_recovery", "the directory is made with the session's umask", "         rc.um = umask(63)\n         void ospath(md.path, OS$MKDIR)", "         rc.um = umask(-1)\n         void ospath(md.path, OS$MKDIR)"),
    ("edit_recovery", "the directory is not checked", "   gosub make.dir\n   if not(dir.ok) then return\n", "   gosub make.dir\n"),
    ("edit_recovery", "the copy is written with the session's umask", "   rc.um = umask(63)\n   rc.written = @true\n", "   rc.um = umask(-1)\n   rc.written = @true\n"),
    ("edit_recovery", "a link at the name is written through", "   if not(file.ok) then\n      delete rf, rc.slot on error null\n   end\n", ""),
    ("edit_recovery", "a failed write leaves part of a file", "      delete rf, rc.slot on error null        ;* a full disk can leave part of a file: it is not a copy\n", ""),
    ("edit_recovery", "a copy that reads back different is kept", "   if chk # rec then", "   if @false then"),
    ("edit_recovery", "the copy is not checked private after the write", "      res = 'mode'\n", "      res = ''\n"),
    ("edit_recovery", "the digest is not tested", "   if downcase(digest(cp.text, 0, 'SHA256')) # rec<8> then", "   if @false then"),
    ("edit_recovery", "find reads without the file test", "      gosub check.file\n      if file.ok then\n         openpath rc.dir to rf then\n            mark.mapping rf, off\n            read rec",
     "      file.ok = 1\n      if file.ok then\n         openpath rc.dir to rf then\n            mark.mapping rf, off\n            read rec"),
    ("edit_recovery", "find answers for another record", "            if cp.ok and cp.file = rfile and cp.id = rid then", "            if cp.ok then"),
    ("edit_recovery", "an audit line holds the text", "   close rf\n   res = ''\n   return", "   close rf\n   void kernel(K$AUDIT, 'recovery ' : text)\n   res = ''\n   return"),
    ("ide", "the tick writes with the switch off", "rc.tick:\n   if not(rc.on) then return\n", "rc.tick:\n"),
    ("ide", "the hang-up writes nothing", "            case ev<1> = 'end'\n               gosub rc.tick ", "            case ev<1> = 'end'\n               null "),
    ("ide", "a copy somebody else left is written over", "               if rr # '' then\n                  rt.write = @false\n", "               if rr # '' then\n                  null\n"),
    ("ide", "a save drops the copy before it writes", "   ri = sv.i\n   gosub rc.drop.tab                            ;* 28 Oct 26 (D2): the text is in the record now; its recovery copy goes\n", ""),
    ("ide", "Cancel opens the record anyway", "      if rc.choice = 'cancel' then\n         gosub lock.free\n         return\n      end\n   end\n   gosub stash.current", "   end\n   gosub stash.current"),
    ("ide", "Enter deletes the copy", "buttons 'Use the copy,Delete the copy,Cancel' default 1", "buttons 'Use the copy,Delete the copy,Cancel' default 2"),
    ("ide", "Use the copy writes it to the record", "         rc.choice = 'use'\n", "         rc.choice = 'use'\n         write rc.text on fv, rc.id\n"),
    ("ide", "a quit that was cancelled drops the copies", "   if not(abort) then\n      for ri = 1 to nbuf", "   if @true then\n      for ri = 1 to nbuf"),
    # 28 Oct 26: the TUI phase 2 review's findings
    ("ide", "the editor still holds the startup buffer between two Opens", "               gosub load.current\n               rc.got = @true\n", "               rc.got = @true\n"),
    ("ide", "a foreign copy is looked for once only", "            if rt.seen and rt.now < rx<1, 3> + 0 then\n", "            if rt.seen then\n"),
    ("ide", "the tab is never protected again", "                  bx{k} = ''                                      ;* none there (or no longer)", "                  null                                      ;* none there (or no longer)"),
    ("ide", "the person is not told", "                     msg = sysmsg(12783, bf.name, bf.id)", "                     null"),
    ("ide", "the next look is never set", "                  bx{k} = rk.now : @vm : rt.now + RC.LOOK\n", "                  bx{k} = rk.now\n"),
    ("ide", "an emptied untitled tab leaves its copy", "         ri = cb\n         gosub rc.drop.tab\n         del bn<cb>\n", "         del bn<cb>\n"),
    ("ide", "the IDE does not keep its break setting", "   saved.trap = pterm(PT$BREAK, -1)\n   call $tk_brk('save', saved.trap)\n   void pterm(PT$BREAK, @false)\n   break off\n\n",
     "   saved.trap = pterm(PT$BREAK, -1)\n   void pterm(PT$BREAK, @false)\n   break off\n\n"),
    ("ide", "the end gives the setting back by hand", "   screen close\n   call $tk_brk('close', saved.trap)           ;* the setting back",
     "   screen close\n   break on\n   void pterm(PT$BREAK, saved.trap)           ;* the setting back"),
    ("ide", "the screen is handed to a program with the setting still held", "   call $tk_brk('close', saved.trap)     ;* 28 Oct 26: the program run", "   null     ;* 28 Oct 26: the program run"),
    ("ide", "the screen is taken back without keeping the setting", "   call $tk_brk('save', saved.trap)\n   void pterm(PT$BREAK, @false)\n   break off\n   gosub open.screen",
     "   void pterm(PT$BREAK, @false)\n   break off\n   gosub open.screen"),
    ("ide", "a too small window leaves the setting held", "      call $tk_brk('close', saved.trap)        ;* the setting back and BREAK ON", "      break on        ;* the setting back and BREAK ON"),
    # 30 Oct 26 (stage E2): the tab of an operating system file is made in path.tab.make
    ("ide", "the operating system file's tab owns whatever copy the last tab had", "   gosub rc.init.tab\n   ts.kind = 'path'\n   ts.dict = ''\n   ts.slot = op.s\n", "   ts.kind = 'path'\n   ts.dict = ''\n   ts.slot = op.s\n"),
    ("ide", "open.path makes the tab itself again", "   tused<op.s> = 1\n   gosub path.tab.make\n   return", "   tused<op.s> = 1\n   nbuf += 1\n   return"),
]


def selftest():
    src, msgs = load()
    if any(not ok for _, ok, _ in checks(src, msgs)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text once ---")
    for fk, name, old, new in MUTANTS:
        if src[fk].count(old) != 1:
            print("  [FAIL] %s: the text matches %d times in %s, not once" % (name, src[fk].count(old), fk))
            holes += 1
            continue
        mut = dict(src)
        mut[fk] = src[fk].replace(old, new)
        caught = [n.split(" ")[0] for n, ok, _ in checks(mut, msgs) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + ", ".join(caught[:3]) if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    # a message removed is a mutant of the message files
    m2 = dict(msgs)
    m2.pop(12776, None)
    caught = [n.split(" ")[0] for n, ok, _ in checks(src, m2) if not ok]
    print("  [%s] message 12776 is missing%s" % ("pass" if caught else "FAIL", ": caught by " + ", ".join(caught) if caught else ": NOT CAUGHT"))
    holes += 0 if caught else 1
    total = len(MUTANTS) + 1
    print("\n%d of %d mutants caught, %d missed" % (total - holes, total, holes))
    return 1 if holes else 0


def main():
    missing = [p for p in FILES.values() if not os.path.isfile(p)]
    if missing:
        print("test-recovery-units: CANNOT RUN - not readable: %s" % missing, file=sys.stderr)
        return 2
    if "--selftest" in sys.argv[1:]:
        return selftest()
    src, msgs = load()
    rows = checks(src, msgs)
    bad = report(rows)
    print("\nNOT MEASURED HERE: that a hang-up leaves a 0600 copy holding the text, that the switch off writes nothing, that the copy comes back.  That is sandbox-recovery.py.")
    print("test-recovery-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
