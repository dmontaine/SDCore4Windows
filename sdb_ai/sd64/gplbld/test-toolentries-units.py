#!/usr/bin/env python3
"""test-toolentries-units.py - TOOL.ENTRIES, the master files page (S.96 M1a-M2), as invariants read off the source.

  python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-toolentries-units.py
  python .../test-toolentries-units.py --selftest
  python .../test-toolentries-units.py --selftest --from=113     (only the mutants from M_FIELD1 on: field 1 on one record only, 3 Nov 26; T24b)
  python .../test-toolentries-units.py --selftest --from=85      (only the mutants from M_GLOBAL on: G, the global change, and U, its undo, 3 Nov 26; T24-T28)
  python .../test-toolentries-units.py --selftest --from=118     (only the Windows mutants, M_WINDOWS: W1, W2, W3)

No elevation, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 3 Nov 26.

WINDOWS PORT, 10 Nov 26 (from Linux at 074397f6; RELEASE_1.1 201).  Message ids are Linux's + 1005.  What differs, and why:
  - an absolute path is a drive letter or @ds (abs.pat), not a leading /: the rows that pin the absolute-path test say so (T5b, T5e, T14, T21, T25).
  - the register's ids are upper case: T7 and the "SDSYS is listed" mutant read upcase(id).
  - THE RELOG STATE IS NOT CARRIED (Linux T23, T23b, T23c and their ten mutants, and G's relog mutant): there is no sdsys user or POSIX group here (Linux
    S.103 is not carried), so sdsys.state answers yes and nothing refuses; W1 holds that instead.
  - T13 (registered in regress.sh / regress-map.txt) is not carried: neither file exists here; a free guard is registered by its name (check-free-tier.ps1).
  - T19's kernel half (op_sh.c's resolve_name refusing a link that leads nowhere) is not carried: op_sh.c here resolves names by fullpath() and has no such
    test; the page's own half of T19 is kept.
  - B is not built (run.in has no debug here): W2 holds that do.debug says so and returns before anything; T20 and T22 still hold the code kept behind it.

***WHAT THIS IS AND WHAT IT IS NOT.*** It reads sdsys/gpl.bp/tool_entries, the VOC record and the two help records as TEXT.  IT CANNOT SAY THE PAGE SHOWS THE RIGHT GATES OR THE RIGHT
ENTRIES: that is sandbox-tool-entries.py.  What it holds is the shape the design depends on and a hand edit could break unnoticed: the page is the administrator's and asks for that
first; it changes no record itself (since M2 the ONLY write is the temporary Q-pointer in SDSYS's VOC that lets the IDE reach an account's file, the ONLY delete takes that pointer away
and the ONLY execute gives the terminal to the IDE; no command, confirm box or master-file operation anywhere in it); THE OWNER'S POINTER RULE for E and N (3 Nov 26): the file to be edited
is judged by the kernel's geometry, from a register and an account VOC read afresh, BEFORE the pointer is written, and what the pointer opens is judged again before the IDE is given it;
the only files it opens are the register and, by the pathname the register gives, an account's VOC; an account's VOC is read when the cursor comes to it and every VOC is read only by
the find the person asks for; the gates are the three register fields in the order v d b; SDSYS is not in the list; the long lists are cut at MAXV.

***AND THE CHECKS ARE THEMSELVES CHECKED.*** --selftest makes the changes that would plausibly break the page and requires each to be CAUGHT.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.abspath(os.path.join(HERE, os.pardir))
PAGE = os.path.join(SD64, "sdsys", "gpl.bp", "tool_entries")
VOCREC = os.path.join(SD64, "sdsys", "voc_template", "tool.entries")
HELP = os.path.join(SD64, "sdsys", "helptext")
IDE = os.path.join(SD64, "sdsys", "gpl.bp", "ide")
OPSH = os.path.join(SD64, "gplsrc", "op_sh.c")
CPROC = os.path.join(SD64, "sdsys", "gpl.bp", "cproc")
BASIC = os.path.join(SD64, "sdsys", "gpl.bp", "basic")
OPDIO1 = os.path.join(SD64, "gplsrc", "op_dio1.c")


def code(src):
    out = []
    for i, line in enumerate(src.splitlines(), 1):
        s = line.strip()
        if s and not s.startswith("*"):
            cut = s.find(";*")
            out.append((i, (s[:cut] if cut >= 0 else s).rstrip()))
    return out


def unquote(s):
    """The line with the inside of its string literals taken out: the prose a page shows says 'write' and 'modify.account' and must not be read as code."""
    out, q = [], ""
    for ch in s:
        if q:
            if ch == q:
                q = ""
                out.append(ch)
        elif ch in "'\"":
            q = ch
            out.append(ch)
        else:
            out.append(ch)
    return "".join(out)


def section(lines, start, end):
    a = next((n for n, s in lines if s.startswith(start)), None)
    if a is None:
        return []
    b = next((n for n, s in lines if n > a and s.startswith(end)), None)
    return [(n, s) for n, s in lines if n >= a and (b is None or n < b)]


def checks(src, voc, helps):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    lines = code(src)
    txt = "\n".join(s for n, s in lines)
    ck("T1 NULL CASE: the page, its VOC record and both help records are there and not empty", len(lines) > 300 and voc and all(helps.values()), "%d lines" % len(lines))
    ck("T2 the VOC record is V / CA / $tool_entries (SDSYS's template only) and the page is internal and catalogued as $tool_entries",
       voc == "V\nCA\n$tool_entries\n" and "program $tool_entries" in txt and "$catalog $tool_entries" in txt and txt.count("$internal") == 1)
    first_open = next((n for n, s in lines if re.search(r"\bopenpath\b", s)), 10 ** 9)
    adm = next((n for n, s in lines if "call $tk_open('tool.entries', 'admin', ctx, err)" in s), None)
    refused = next((n for n, s in lines if n > (adm or 0) and s == "stop"), None)
    ck("T3 it opens the toolkit for the ADMINISTRATOR first and stops on a refusal, before any file is opened",
       adm is not None and refused is not None and adm < refused < first_open, "admin %s stop %s first openpath %s" % (adm, refused, first_open))
    forbidden = [(n, s) for n, s in lines if re.search(r"(^|[\s;(])(writev|writeu|deletes|chain|perform|osexecute|os\.execute)\s", unquote(s) + " ")
                 or re.search(r"\$tk_run|\$tk_confirm|K\$MASTERS|!acc_|sd-elevate|modify\.account|set\.batch|run\.in", unquote(s))]
    GC_ALLOWED = ("call $tk_confirm(dsent, dlines, eid, res, cmsg, sysmsg(12958))",          # M3: D's one confirm box, held by T18
                  "call $tk_confirm(gsent, glines, '', res, cmsg, sysmsg(12959))",           # G's preview (T24)
                  "call $tk_confirm(usent, ulines, '', res, cmsg)",                          # the box that shows create.file of the undo file
                  "call $tk_confirm(usent, ulines, '', res, cmsg, sysmsg(12960))",           # U's box (T27)
                  "writeu gnew on gf, eid on error",                                         # G's one data write (T26)
                  "writeu ur on gf, uid on error")                                           # U's one put-back (T27)
    forbidden = [(n, s) for n, s in forbidden if s not in GC_ALLOWED]
    writes = [s for n, s in lines if re.search(r"(^|[\s;(])write\s", unquote(s) + " ")]
    deletes = [s for n, s in lines if re.search(r"(^|[\s;(])delete\s", unquote(s) + " ")]
    execs = [s for n, s in lines if re.search(r"(^|[\s;(])execute\s", unquote(s) + " ")]
    ck("T4 WHAT IT MAY CHANGE (M2, M3, M4; G and U of 3 Nov 26): the writes are the temporary pointer in SDSYS's VOC (`write qrec on svf, qn on error`) and the undo file's (its header twice "
       "in a run and once in an undo, the record as it was before each change, the restored marker); the data writes are G's WRITEU and U's WRITEU, nothing else; the deletes take the pointer away "
       "(`delete svf, qn`), sweep the user number's own leftovers at the start (`delete svf, sw.id`), delete D's one record through the file edit.record judged (`delete tf, eid`) and, "
       "for a program, its compiled program through the .out file object.judge judged (`delete dof, doid`, M6a), and drop the undo record of a write that failed; the "
       "executes give the terminal to the IDE (`execute sent`), compile through run.in (`execute csent capturing cout`), debug through it and make the undo file (`execute MKUNDO`); "
       "no chain, perform, OS command, command runner, master-file operation or account verb anywhere in the page, and no confirm box but D's, G's, U's and the undo file's",
       not forbidden and writes == ["write qrec on svf, qn on error", "write ghdr on uf, 'last' on error", "write ghdr on uf, 'last' on error null",
                                    "write ea : @fm : gkw : @fm : (if efl = '' then 'voc' else efl) : @fm : eid : @fm : digest(gnew, 0, 'MD5') : @fm : grec on uf, gun on error",
                                    "write ur2 on uf, un.i on error null", "write uh on uf, 'last' on error null"]
       and deletes == ["delete svf, sw.id", "delete svf, qn", "delete tf, eid on error delok = @false", "delete dof, doid on error dores = 'failed'", "delete uf, gun"]
       and execs == ["execute csent capturing cout", "execute dbsent", "execute sent", "execute MKUNDO trapping aborts capturing mkout"]
       and len([s for n, s in lines if re.search(r"(^|[\s;(])writeu\s", unquote(s) + " ")]) == 2,
       "%s %s %s %s" % (forbidden[:3], writes, deletes, execs))
    opens = [s for n, s in lines if re.search(r"\bopenpath\b", s)]
    kinds = sorted(set("register" if "@sdsys:@ds:'accounts'" in s else ("voc" if re.search(r"(apath<[a-z0-9]+>|ap\.f) ?:@ds ?: ?'voc'", s.replace(" : ", ":")) else ("dict" if re.match(r"openpath dp to df2? then", s)
                       else ("prog" if re.match(r"openpath (op2 to ofv|pp to pfv|pp2 to pf2) then", s) or s == "openpath dop to dof else return"
                             else ("global" if s == "openpath tp to gf else" else s)))) for s in opens))
    ck("T5 the only files it opens by pathname are the register, an account's VOC by the pathname the register gives and, by a path of one of that VOC's file pointers, a dictionary, a program "
       "file or the .out file beside it (thirteen opens: the list; the VOC, the dictionaries, the .out file and the program files in collect.account; the entry under the cursor in the VOC, in "
       "a dictionary and in a program file; the register and the account's VOC again in edit.record, for E and N; and D's .out file of a program, M6a); the other opens are SDSYS's own VOC (the pointer) and the file "
       "that pointer leads to, which is judged before the IDE is given it",
       kinds == ["dict", "global", "prog", "register", "voc"] and len(opens) == 16 and txt.count("close ") >= 16      # G (3 Nov 26): the register and the VOC again in gc.account / gc.file, and the file gc.file judged (T25)
       and len(re.findall(r"^open 'voc' to svf else$", txt, re.M)) == 1 and len(re.findall(r"^open 'voc' to svf then$", txt, re.M)) == 2
       and len(re.findall(r"^open dfl, qn to tf else$", txt, re.M)) == 1, "%s %d" % (kinds, len(opens)))
    cap = "\n".join(s for n, s in section(lines, "collect.account:", "dclassify:"))
    ck("T5b a dictionary path that is not absolute is made from the ACCOUNT's directory, never the current one; the dictionaries are those the VOC's file pointers name (field 3); an item matches in its id OR its heading",
       "dp = parse.pathname.tokens(dpaths<fi>)" in cap and "if not(dp matches abs.pat) then dp = apath<ca> : @ds : dp" in cap and "upcase(trim(r<1>))[1, 1] = 'F' and trim(r<3>) # ''" in cap
       and "index(upcase(did), upcase(pat), 1) > 0 or index(upcase(dhead), upcase(pat), 1) > 0" in cap and "kind = 1 then" in cap)
    kd = "\n".join(s for n, s in section(lines, "do.kind:", "on.mouse:"))
    ck("T5c K cycles the kind (1, 2, 3 and round to 1) and takes the filter and the find off", "kind += 1\nif kind > 3 then kind = 1" in kd and "fnd = '' ; filt = ''" in kd and re.search(r"^kind = 1$", txt, re.M) is not None)
    ck("T5e the programs (M1c): a program file is found as tool.catalog finds it - a directory file named bp, or ending .bp, or with an F entry of the same name and .out beside it, and never a "
       "file whose name ends .out itself; its path has its tokens expanded and is the account's when relative; it must be a DIRECTORY file; a program is built when its lower-case id is among the "
       "ids of the .out file; the file's own path is asked for the > mark",
       "if not(len(tl) > 4 and tl[len(tl) - 3, 4] = '.out') then" in cap and "if tl = 'bp' then isp = 1" in cap and "if len(tl) > 3 and tl[len(tl) - 2, 3] = '.bp' then isp = 1" in cap
       and "read orr from vf, id : '.out' else orr = ''" in cap and "pp = parse.pathname.tokens(ppaths<fi>)" in cap and "if not(pp matches abs.pat) then pp = apath<ca> : @ds : pp" in cap
       and "if fileinfo(pfv, FL$TYPE) = FL$TYPE.DIR then" in cap and "onames = downcase(onames)" in cap and "locate downcase(pid) in onames<1> setting op3 then built = 'yes'" in cap
       and "op2 = pp : '.out'" in cap and "if popaths<fi> # '' then" in cap
       and "poutf = is.out" in cap and "ins poutf before cout<lp>" in cap)
    ck("T5d THE OWNER'S RULE (3 Nov 26): no pointer may lead the master to edit something in one account from another.  A target OUTSIDE the account being listed (asked of the kernel's own "
       "geometry, K$PATH.IN, which resolves .. and links; tokens expanded and the path made absolute from the account) is marked > - for a dictionary item that the ITEM lives elsewhere, "
       "for a VOC file pointer, a Q-pointer to another account or a remote item that the POINTER leads elsewhere - in a column of its own in every list; the pointer record itself stays an "
       "ordinary entry of the account; and the page follows no pointer to change anything (T4)",
       "is.out = (if kernel(K$PATH.IN, apath<ca> : @fm : tp) then 0 else 1)" in txt and "doutf = is.out" in cap and "ins doutf before cout<lp>" in cap and "ins coutf before cout<lp>" in cap
       and "coutf = (if downcase(trim(r<2>)) = downcase(anm<ca>) then 0 else 1)" in txt and re.search(r"case cty = 'R'\ncoutf = 1", txt) is not None and txt.count("fmt('>', '2L')") == 4
       and txt.count("(if hout<k> then '>' else '')") == 2 and txt.count("(if eout<k> then '>' else '')") == 2 and "sdsys" not in "\n".join(s for n, s in section(lines, "out.test:", "dclassify:")))
    ra = section(lines, "read.all:", "read.entries:")
    find_opens = [n for n, s in lines if "for a = 1 to an" in s]
    rf = section(lines, "run.find:", "classify:")
    ck("T6 LAZY: read.all reads the VOC of the selected account only (one gosub read.entries) and runs the find only when a find is set; the loop over every account is in run.find alone",
       "\n".join(s for n, s in ra).count("gosub read.entries") == 1 and any(s == "if fnd # '' then gosub run.find" for n, s in ra)
       and len(find_opens) == 1 and rf and rf[0][0] < find_opens[0] and txt.count("gosub run.find") == 2 and "gosub run.find" in "\n".join(s for n, s in section(lines, "do.find:", "on.mouse:")),
       "calls of run.find: %d" % txt.count("gosub run.find"))
    ck("T7 SDSYS is not in the list (the register's ids are upper case on Windows); the gates are the register's voc-edit, dict-edit, bp-edit in the order v d b (each 'YES' after trim and upcase); "
       "the sdsys column is asked of sdsys.state",
       "if upcase(id) # 'SDSYS' then" in txt
       and re.search(r"gset = \(if upcase\(trim\(arec<ACC\$VOC\.EDIT>\)\) = 'YES' then 'v' else '-'\)\s+gset := \(if upcase\(trim\(arec<ACC\$DICT\.EDIT>\)\) = 'YES' then 'd' else '-'\)\s+gset := \(if upcase\(trim\(arec<ACC\$BP\.EDIT>\)\) = 'YES' then 'b' else '-'\)", txt)
       and "sg.grp = trim(arec<ACC$GROUP>)\ngosub sdsys.state\nins sdw before asds<lp>" in txt)
    ck("T8 both long reads are cut at MAXV (the entries and the hits) and the page says so", txt.count(">= MAXV") == 4 and txt.count("only the first ' : MAXV : ' are listed") == 3)       # collect.account's three reads and the find; the entries' foot, the hits' foot and the status line of a find
    ck("T9 the filter and the find ask with screen ask, take the AI's argument as the default, and each clears the other",
       txt.count("screen ask ptxt width 40 value ai.arg") == 2 and txt.count("value ai.arg") == 2 and "filt = trim(ft)\nfnd = ''" in txt and "fnd = trim(ft)\nfilt = ''" in txt)
    keyrows = re.findall(r"call \$tk_keys\('add', keys, '([^']+)'", txt)
    ck("T10 sixteen key rows: f1 enter f6 / f k e n d c b g u f5 ctrl-q esc (F6 the box key since S.176, where Tab was), and the AI is offered only what changes what is shown (pane filter find kind refresh), never an edit, a delete, a compile, a debug, a global change or its undo",
       keyrows == ["f1", "enter", "f6", "/", "f", "k", "e", "n", "d", "c", "b", "g", "u", "f5", "ctrl-q", "esc"] and re.findall(r"call \$tk_keys\('ai', keys, '([^']+)'", txt) == ["pane", "filter", "find", "kind", "refresh"], "%s" % keyrows)
    er = "\n".join(s for n, s in section(lines, "edit.record:", "sweep.pointers:"))
    ho = "\n".join(s for n, s in section(lines, "hand.over:", "do.filter:"))
    de = "\n".join(s for n, s in section(lines, "do.edit:", "do.delete:"))
    dd = "\n".join(s for n, s in section(lines, "do.delete:", "do.build:"))
    db = "\n".join(s for n, s in section(lines, "do.build:", "do.debug:"))
    dg = "\n".join(s for n, s in section(lines, "do.debug:", "do.new:"))
    dr = "\n".join(s for n, s in section(lines, "delete.reached:", "compile.reached:"))
    cr = "\n".join(s for n, s in section(lines, "compile.reached:", "hand.over:"))
    dn = "\n".join(s for n, s in section(lines, "do.new:", "edit.record:"))

    def at(t, s=er):
        return s.find(t)
    i_ck, i_guard, i_w = at("if not(kernel(K$PATH.IN, ap.f : @fm : tp)) then"), at("if qold # qrec then"), at("write qrec on svf, qn on error")
    i_open, i_ck2, i_aud, i_hand = at("open dfl, qn to tf else"), at("in.ok = kernel(K$PATH.IN, ap.f : @fm : rp)"), at("void kernel(K$AUDIT, 'master edit account="), at("gosub hand.over")
    ck("T14 THE POINTER RULE for E and N (owner, 3 Nov 26): the register and the account's VOC are read AGAIN in edit.record; the file to be edited is judged by the kernel's geometry "
       "(the VOC file of the account, or the DICTIONARY path of the file pointer with its tokens expanded and made the account's when relative) BEFORE any pointer is written; an entry "
       "SDSYS's VOC already holds under that name that the page did not make is never overwritten; what the pointer opens is judged again (FL$PATH) before the IDE is given it; both refusals "
       "take the pointer away again; the audit line comes after both tests and before the hand-over",
       0 <= i_ck < i_guard < i_w < i_open < i_ck2 < i_aud < i_hand and "read arec from acc.f, ea else arec = ''" in er and "openpath ap.f : @ds : 'voc' to rvf else" in er
       and "tp = ap.f : @ds : 'voc'" in er and "tp = parse.pathname.tokens(trim(fr<3>))" in er and "if not(tp matches abs.pat) then tp = ap.f : @ds : tp" in er
       and "rp = fileinfo(tf, FL$PATH)" in er and er.count("gosub drop.pointer") == 5 and "if upcase(trim(fr<1>))[1, 1] # 'F' or trim(fr<3>) = '' then" in er
       and "in.ok = kernel(K$PATH.IN, ap.f : @fm : rp)" in er and "if in.ok then in.ok = kernel(K$PATH.IN, ap.f : @fm : rp : @ds : '%0')" in er
       and "if in.ok then in.ok = kernel(K$PATH.IN, ap.f : @fm : rp : @ds : '%1')" in er and "rt = fileinfo(tf, FL$TYPE)" in er and "if rt # rtw then" in er
       and "rtw = (if isprog then FL$TYPE.DIR else FL$TYPE.DH)" in er and at("if rt # rtw then", er) < i_aud and at("if not(in.ok) then", er) < i_aud
       and at("read arec from acc.f", er) < i_ck and "ap.f = parse.pathname.tokens(arec<1>)" in er and i_ck < at("gosub check.word") < i_w,
       "ck %d guard %d write %d open %d ck2 %d audit %d hand %d" % (i_ck, i_guard, i_w, i_open, i_ck2, i_aud, i_hand))
    ck("T15 the pointer and the sentence: the pointer is an F pointer holding THE PATH THAT WAS CHECKED (never a Q-pointer into the account's VOC, which is followed again at every open, "
       "after the check: the review of 3 Nov 26), both parts the dictionary for an item and no dictionary part for the VOC, named zm<user number>.<account>.<file> from words that passed "
       "check.word (a-z 0-9 . _ -, 1 to 63; and not creating.seqkey, which the IDE reads as a keyword); the sentence is 'ide' (with dict for an item) and the pointer's name and the id; "
       "hand.over refuses any other first word, takes the pointer away straight after the IDE ends and takes it away only if it is the one the page made",
       "qrec = 'F' : @fm : tp : @fm : (if efl = '' then '' else tp)" in er and "qn = 'zm' : @userno : '.' : ea : '.' : qf" in er and "ok2 = (okname and eid # 'creating.seqkey')" in er
       and "'Q'" not in er and "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'" in txt
       and "okname = (len(cw) > 0 and len(cw) <= 63)" in txt and er.count("gosub check.word") == 3 and "if not(ok1 and ok2 and okname) then" in er
       and "sent = 'ide ' : (if efl = '' then '' else 'dict ') : qn : ' ' : eid" in er
       and "if field(sent, ' ', 1) # 'ide' then" in ho and ho.find("execute sent\ngosub drop.pointer") > ho.find("if field(sent, ' ', 1) # 'ide' then")
       and "if qold = qrec then\ndelete svf, qn\nend" in txt)
    ck("T16 E and N keys: E edits the row under the cursor (a hit in the account it was found in), only from Entries; N refuses while a find is on and asks the id first; "
       "a new item or program needs a row to take the file from; the id is lower-cased and trimmed",
       "if pane # 2 then" in de and "if kind = 3 then" not in de and "ea = hacc<ec> ; eid = hid<ec> ; efl = hfile<ec>" in de and "ea = anm<ac> ; eid = enm<ec> ; efl = efile<ec>" in de and "enw = 0" in de
       and "if kind = 3 then" in dn and "if fnd # '' then" in dn and "efl = efile<ec>" in dn and "eid = downcase(trim(nt))" in dn and "enw = 1" in dn
       and "case nm = 'e'\ngosub do.edit" in txt and "case nm = 'n'\ngosub do.new" in txt)
    def at2(t):
        return dr.find(t)
    i_lk, i_cf, i_cancel, i_del, i_bad, i_daud = (at2("readu dold from tf, eid locked"), at2("call $tk_confirm(dsent, dlines, eid, res, cmsg, sysmsg(12958))"), at2("if res # 'run' then"),
                                                   at2("delete tf, eid on error delok = @false"), at2("if not(delok) then"), at2("void kernel(K$AUDIT, 'master delete account="))
    i_branch = at("if emode = 'delete' then\ngosub delete.reached\nreturn\nend")
    ck("T18 D (M3) goes E's whole way and only then deletes: do.delete takes the row as E does (Entries only, every kind - the programs too since M6a -, a hit in its own account) and calls edit.record with "
       "emode 'delete'; edit.record branches to delete.reached AFTER both refusals of the opened file and BEFORE E's audit line, and keeps tf open only for D; delete.reached takes the "
       "record's update lock (a held lock refuses), asks the confirm box with the id to be TYPED and the title 'Delete this record?' (12958), does nothing unless the answer is run, deletes "
       "through tf, gives the pointer back on each of its five ways out (M6a: the program's object refused is the fifth), and writes 'master delete' only after a delete that worked",
       "if pane # 2 then" in dd and "if kind = 3 then" not in dd and "ea = hacc<ec> ; eid = hid<ec> ; efl = hfile<ec>" in dd and "ea = anm<ac> ; eid = enm<ec> ; efl = efile<ec>" in dd
       and "emode = 'delete'\ngosub edit.record" in dd and "emode = 'edit'\ngosub edit.record" in de and "emode = 'edit'\ngosub edit.record" in dn
       and at("if not(in.ok) then") < i_branch < i_aud and at("if rt # rtw then") < i_branch and "if emode # 'delete' then close tf" in er and "\nclose tf\n" not in er
       and 0 <= i_lk < i_cf < i_cancel < i_del < i_bad < i_daud and dr.count("gosub drop.pointer") == 5 and dr.count("close tf") == 5
       and 0 <= at2("dmsg = 'deleted ' : eid : ' from ' : dwhere") < at2("gosub read.all") and "msg = dmsg" in dr
       and "case nm = 'd'\ngosub do.delete" in txt and "call $tk_keys('menu', keys, 'delete', '&Entry', '&Delete the record', '', '')" in txt,
       "branch %d audit %d lock %d confirm %d cancel %d delete %d bad %d daudit %d" % (i_branch, i_aud, i_lk, i_cf, i_cancel, i_del, i_bad, i_daud))
    ide = code(helps.get("__ide__", ""))
    itxt = "\n".join(s for n, s in ide)
    imb = "\n".join(s for n, s in section(ide, "master.build:", "catalog.verified:"))
    idc = "\n".join(s for n, s in section(ide, "do.compile:", "master.build:"))
    irc = "\n".join(s for n, s in section(ide, "run.cmd:", "case cmd = 'menu'"))
    ck("T19 THE PROGRAMS (M4; the owner's mechanism C of 2 Nov 26: what must run inside an account goes through run.in).  The page: E and N take a program (no refusal of kind 3), "
       "edit.record judges the program file's DATA path (field 2) by the pointer rule, makes a data-only pointer, wants a DIRECTORY file, judges the program's own file and refuses a "
       "name that is a link leading nowhere, all before the compile branch and the audit; the IDE's sentence ends /in=account,file; C (do.build, programs only) goes through edit.record "
       "with emode 'compile', which gives the pointer back and calls compile.reached; that builds `run.in <account> basic <file> <id>` from checked words only, judges the compiler's "
       "success line, then audits 'master compile'.  The IDE: /in= is taken off the sentence and names the pointer file; do.compile of a tab of it runs run.in in the account and "
       "judges the success line, any other tab still runs basic; run.cmd sends Catalog, Run and Debug of such a tab to master.build BEFORE its case, which catalogues through run.in "
       "and refuses Run and Debug",
       "isprog = (kind = 3)" in er and "tp = parse.pathname.tokens(trim(fr<2>))" in er and "if isprog then qrec = 'F' : @fm : tp" in er and "if isprog then dfl = ''" in er
       and "if isprog and in.ok then in.ok = kernel(K$PATH.IN, ap.f : @fm : rp : @ds : eid)" in er
       and 0 <= at("if not(in.ok) then") < at("if emode = 'compile' then") < i_aud
       and "if emode = 'compile' then\ngosub drop.pointer\ngosub compile.reached\nreturn\nend" in er
       and "if isprog then sent = 'ide ' : qn : ' ' : eid : ' /in=' : ea : ',' : efl" in er
       and "if kind # 3 then" in db and "emode = 'compile'\ngosub edit.record" in db and "ea = hacc<ec> ; eid = hid<ec> ; efl = hfile<ec>" in db and "case nm = 'c'\ngosub do.build" in txt
       and "csent = 'run.in ' : ea : ' basic ' : efl : ' ' : eid" in cr and "cok = (index(cout, 'Compiled 1 program(s) with no errors', 1) > 0)" in cr
       and 0 <= cr.find("execute csent capturing cout") < cr.find("void kernel(K$AUDIT, 'master compile account=")
       and "if downcase(in.last[1, 4]) = '/in=' then" in itxt and "in.ptr = downcase(field(sent.in, ' ', 2))" in itxt
       and "if in.good and convert('abcdefghijklmnopqrstuvwxyz0123456789._-', '', in.acct : in.file) # '' then in.good = @false" in itxt
       and "if in.ptr # '' and c.file = in.ptr then" in idc and "execute 'run.in ' : in.acct : ' basic ' : in.file : ' ' : c.id : c.opt capturing c.out" in idc
       and "c.ok = (index(c.out, 'Compiled 1 program(s) with no errors', 1) > 0)" in idc and "execute 'basic ' : qp.f : ' ' : qp.i : c.opt capturing c.out" in idc
       and "if bn<cb> = in.ptr and (cmd = 'catalog' or cmd = 'run' or cmd = 'debug' or cmd = 'debug1') then\ngosub master.build\nreturn" in irc
       and "execute 'run.in ' : in.acct : ' catalog ' : in.file : ' ' : c.id capturing co" in imb and "is not run from here" in imb and "execute 'catalog" not in imb,
       "ide %d chars, mb %d, dc %d, rc %d" % (len(itxt), len(imb), len(idc), len(irc)))
    drr = "\n".join(s for n, s in section(lines, "debug.reached:", "hand.over:"))
    ck("T20 DEBUG (M5): B (do.debug, programs only, a hit in its own account) goes through edit.record with emode 'debug', whose branch gives the pointer back and calls "
       "debug.reached after both refusals and before E's audit; debug.reached compiles for the debugger through run.in (compile.in.account, ' debugging'), shows a failed compile "
       "and debugs nothing, else audits 'master debug' and gives the terminal to `run.in <account> debug <file> <id>`, then takes the page back through retake.page (the editor's "
       "way back too).  The IDE: Debug and Debug from the first line of a master tab compile with debugging (do.compile, so through run.in) and execute run.in debug in the account, "
       "never the debug verb here",
       "if kind # 3 then" in dg and "emode = 'debug'\ngosub edit.record" in dg and "ea = hacc<ec> ; eid = hid<ec> ; efl = hfile<ec>" in dg and "case nm = 'b'\ngosub do.debug" in txt
       and 0 <= at("if not(in.ok) then") < at("if emode = 'debug' then\ngosub drop.pointer\ngosub debug.reached\nreturn\nend") < i_aud
       and "copt = ' debugging'\ngosub compile.in.account" in drr
       and 0 <= drr.find("if not(cok) then") < drr.find("void kernel(K$AUDIT, 'master debug account=") < drr.find("execute dbsent") < drr.find("gosub retake.page")
       and "dbsent = 'run.in ' : ea : ' debug ' : efl : ' ' : eid" in drr and "execute sent\ngosub drop.pointer\ngosub retake.page" in ho
       and "c.opt = ' debugging'\ngosub do.compile\nif c.ok then" in imb and "execute 'run.in ' : in.acct : ' debug ' : in.file : ' ' : c.id trapping aborts" in imb
       and "execute 'debug" not in imb,
       "dg %d drr %d imb %d" % (len(dg), len(drr), len(imb)))
    oj = "\n".join(s for n, s in section(lines, "object.judge:", "compile.reached:"))
    dro = "\n".join(s for n, s in section(lines, "delete.reached:", "object.judge:"))

    def at3(t):
        return dro.find(t)

    def at4(t):
        return oj.find(t)
    ck("T21 D OF A PROGRAM (M6a): edit.record reads the account's VOC record <file>.out again at the keypress (D's object, found by NAME); delete.reached asks object.judge AFTER the "
       "update lock and BEFORE the box, and a refusal gives the pointer back and deletes nothing; object.judge takes the .out file the VOC names (tokens expanded, made the account's) "
       "else the one beside the program file, judges it by the POINTER RULE (K$PATH.IN) BEFORE it opens it, then judges what it opened and the object's own file (lower-case id) "
       "before it reads it; the object is deleted only after the program's delete worked, through that file; 'master delete ... kind=bp ... object=' is written after; the box says "
       "a catalogue entry is left (no run.in, no DECATALOG, no DELETE.CATALOG is run)",
       "if isprog then read dorr from rvf, efl : '.out' else dorr = ''" in er and er.find("read dorr from rvf") < er.find("close rvf")
       and 0 <= at3("readu dold from tf, eid locked") < at3("gosub object.judge") < at3("call $tk_confirm(dsent, dlines, eid, res, cmsg, sysmsg(12958))")
       and "dohave = 0\nif isprog then\ngosub object.judge\nif not(dook) then\nclose tf\ngosub drop.pointer\nreturn\nend" in dro
       and "dop = parse.pathname.tokens(trim(dorr<2>))" in oj and "if not(dop matches abs.pat) then dop = ap.f : @ds : dop" in oj and "dop = tp : '.out'" in oj
       and "doid = downcase(eid)" in oj
       and 0 <= at4("if not(kernel(K$PATH.IN, ap.f : @fm : dop)) then") < at4("openpath dop to dof else return") < at4("dorp = fileinfo(dof, FL$PATH)")
       < at4("do.in = kernel(K$PATH.IN, ap.f : @fm : dorp)") < at4("if do.in then do.in = kernel(K$PATH.IN, ap.f : @fm : dorp : @ds : doid)") < at4("if not(do.in) then") < at4("read dox from dof, doid")
       and "if fileinfo(dof, FL$TYPE) # FL$TYPE.DIR then" in oj
       and 0 <= at3("delete tf, eid on error delok = @false") < at3("if delok then\ndores = 'deleted'\ndelete dof, doid on error dores = 'failed'") < at3("' object=' : dores")
       and "dkind = 'bp'" in dro and "A catalog entry of the program is left" in dro
       and not re.search(r"run\.in|decatalog|delete\.catalog'", unquote(oj + "\n" + dro)),
       "oj %d dro %d" % (len(oj), len(dro)))
    ibk = "\n".join(s for n, s in section(ide, "bk.arm:", "bk.take:"))
    runin = code(helps.get("__cproc__", ""))
    rin = "\n".join(s for n, s in section(runin, "int.runin:", "int.if:"))

    def at5(t):
        return imb.find(t)
    ck("T22 THE EDITOR'S BREAKPOINTS THROUGH run.in (S.98 H2 on a master tab): master.build's Debug arms /idebrk/ (bk.arm) after the compile worked and BEFORE it gives the terminal to "
       "`run.in <account> debug`, and takes the marks back (bk.take) after it; bk.arm names the source by what the kernel opened through the tab's pointer (FL$PATH, which the kernel "
       "makes absolute and real: fullpath in open_file), the compiler stores the source by its FL$PATH too, so the two paths are the same file's; and run.in (int.runin, "
       "revert.account) neither deletes a common nor touches /idebrk/, so the hand-over survives the account switch (the debugger is the same process)",
       0 <= at5("c.opt = ' debugging'\ngosub do.compile\nif c.ok then\ngosub bk.arm") < at5("execute 'run.in ' : in.acct : ' debug ' : in.file : ' ' : c.id trapping aborts\ngosub bk.take\ngosub retake.screen")
       and "open c.file to bk.fv then" in ibk and "ibk.path = fileinfo(bk.fv, FL$PATH) : @ds : c.id" in ibk
       and "source.path = fileinfo(src.f, fl$path) : @ds" in helps.get("__basic__", "")
       and re.search(r"^\s*fullpath\(pathname, mapped_name\);", helps.get("__opdio1__", ""), re.M) is not None
       and len(rin) > 2000 and "revert.account:" in rin and "delete.common" not in rin and "ibk." not in rin and "idebrk" not in rin,
       "imb %d ibk %d rin %d" % (len(imb), len(ibk), len(rin)))
    sw = "\n".join(s for n, s in section(lines, "sweep.pointers:", "drop.pointer:"))
    ck("T17 a pointer left by a session killed inside the IDE is swept when the page starts: right after the start's audit line, before anything is read, only names that begin "
       "zm<this user number>. and only an F or a Q record",
       "void kernel(K$AUDIT, 'tool start app=tool.entries')\ngosub sweep.pointers\n" in txt and txt.find("gosub sweep.pointers") < txt.find("gosub read.all")
       and "sw.pre = 'zm' : @userno : '.'" in sw and "if sw.id[1, len(sw.pre)] = sw.pre then" in sw and "if sw.r<1> = 'F' or sw.r<1> = 'Q' then" in sw)
    ck("T11 four panes declared once (accounts, entries, means, help), the two lists named as the boxes that take the focus, and each list has its [?]",
       txt.count("call $tk_layout('declare'") == 1 and all(("d<%d> = '%s'" % (i + 1, nm)) in txt for i, nm in enumerate(("accounts", "entries", "means", "help")))
       and "ctx<TK.C.FOCI> = 'accounts' : @sm : 'Accounts' : @vm : 'entries' : @sm : 'Entries'" in txt and txt.count("call $tk_help('mark'") == 2)
    asked = sorted(set(re.findall(r"'(tool\.entries\.[a-z]+)'", txt)))
    ck("T12 the help keys the page asks for (tool.entries.accounts and .entries) are the two shipped records, each with a title, a document that exists in the administrator guide and a body",
       asked == ["tool.entries.accounts", "tool.entries.entries"] and all(len(helps[k].split("\n")) >= 3 and helps[k].split("\n")[1] == "administrator-19-the-master-files" for k in asked), "%s" % asked)
    # T13 (regress.sh registration) and T23, T23b, T23c (the relog state) are Linux's and are not carried: see the header.
    st = "\n".join(s for n, s in section(lines, "sdsys.state:", "draw.accounts:"))
    ck("W1 (Windows) THE SDSYS COLUMN: sdsys.state answers yes and nothing else (no sdsys user or POSIX group here, Linux S.103 not carried); read.all asks it; no group is "
       "asked of the kernel or of the group file anywhere in the page, nothing refuses an account in a relog state (Linux's 11981 is not carried), and the accounts help says yes",
       st.startswith("sdsys.state:\nsdw = 'yes'\nreturn") and txt.count("gosub sdsys.state") == 1
       and "K$IN.GROUP" not in txt and "is_grp_member(" not in txt.replace("deffun is_grp_member(user,group) calling '!is_grp_member'", "")
       and "sdw = 'relog'" not in txt and "sysmsg(12986" not in txt and "always yes" in helps.get("tool.entries.accounts", "") and "relog" not in helps.get("tool.entries.accounts", ""), st[:120])
    dbg = section(lines, "do.debug:", "do.new:")
    ck("W2 (Windows) B IS NOT BUILT: do.debug says so and returns before anything else (run.in has no debug here), and the entries help says so",
       len(dbg) > 3 and dbg[1][1].startswith("msg = 'B is not built on Windows") and dbg[2][1] == "return"
       and "B is not built on Windows" in helps.get("tool.entries.entries", ""), "%s" % (dbg[:3],))
    ck("W3 (Windows) an absolute path is a drive letter with either slash or one that starts with @ds (as _voc_ref tells them), defined once before anything is read, and every "
       "'made the account's when relative' test asks it",
       "abs.pat = \"'\" : @ds : \"'0X\" : @vm : \"1A':\\'0X\" : @vm : \"1A':/'0X\"" in txt and txt.count("abs.pat = ") == 1 and txt.count("matches abs.pat") == 10
       and "[1, 1] # '/'" not in txt and 0 <= txt.find("abs.pat = ") < txt.find("call $tk_open('tool.entries', 'admin', ctx, err)"), "%d uses" % txt.count("matches abs.pat"))

    # ---- 3 Nov 26, S.97 / S.96: G, the global change, and U, its undo (the owner's answers of 3 Nov 26, then "Yes, add undo")
    dgl = "\n".join(s for n, s in section(lines, "do.global:", "after.global:"))
    gp = "\n".join(s for n, s in section(lines, "gc.pass:", "gc.audit:"))
    ga = "\n".join(s for n, s in section(lines, "gc.account:", "gc.file:"))
    gfi = "\n".join(s for n, s in section(lines, "gc.file:", "gc.prog:"))
    gpr = "\n".join(s for n, s in section(lines, "gc.prog:", "gc.row:"))
    grw = "\n".join(s for n, s in section(lines, "gc.row:", "gc.new:"))
    gnw = "\n".join(s for n, s in section(lines, "gc.new:", "check.undo:"))
    duf = "\n".join(s for n, s in section(lines, "undo.file:", "read.undo.info:"))
    dun = "\n".join(s for n, s in section(lines, "do.undo:", "undo.audit:"))
    bk = "\n".join(s for n, s in section(lines, "build.keys:", "read.all:"))
    hent = helps.get("tool.entries.entries", "")
    ck("T24 G (3 Nov 26): the set is EXACTLY the rows shown - a filter or a find must be on, a list cut at MAXV is refused, the rows are the hits (account, file, id) or the filtered "
       "entries of the account; the field is a number 1 to GMAXF or, for a dictionary item, heading; set or replace; the texts printable ASCII; ONE preview box with no name typed and "
       "the title 12959; the undo file is made or checked AFTER Run and BEFORE anything is written, and cleared for this run only; the key is g and U's row is enabled only while "
       "a run has not been undone; neither is offered to the AI; the help explains both",
       ordered(dgl, "if fnd = '' and filt = '' then", "return", "if gtr then", "return", "gacc<gi> = hacc<gi>", "gfl<gi> = hfile<gi>", "gid<gi> = hid<gi>",
               "gacc<gi> = anm<ac>", "gfl<gi> = efile<gi>", "gid<gi> = enm<gi>", "gw = 0\ngosub gc.pass", "call $tk_confirm(gsent, glines, '', res, cmsg, sysmsg(12959))",
               "if res # 'run' then", "gosub undo.file\nif not(uok) then", "clearfile uf", "write ghdr on uf, 'last' on error", "gw = 1\ngosub gc.pass")
       and "case kind = 2 and ft = 'heading'" in dgl and "if gfld < 1 or gfld > GMAXF then" in dgl and dgl.count("gosub check.print") == 3
       and "if pc < 32 or pc > 126 then pok = 0" in txt and "gtr = htrunc" in dgl and "gtr = etrunc" in dgl
       and "case nm = 'g'\ngosub do.global" in txt and "case nm = 'u'\ngosub do.undo" in txt
       and "call $tk_keys('add', keys, 'u', 'undo', 'undo', '', (if un.have and un.state # 'undone' then 1 else 0))" in bk
       and "'global'" not in "".join(re.findall(r"call \$tk_keys\('ai'[^\n]*", txt)) and "'undo'" not in "".join(re.findall(r"call \$tk_keys\('ai'[^\n]*", txt))
       and "UNDOF = '&entries.undo&'" in txt and "MKUNDO = 'create.file &entries.undo&'" in txt and "call $tk_ownfile(uf, UNDOF, uck, ucw)" in txt
       and ordered(duf, "open UNDOF to uf then", "gosub check.undo", "call $tk_confirm(usent, ulines, '', res, cmsg)", "if res # 'run' then", "execute MKUNDO", "gosub check.undo")
       and "G " in hent and "&entries.undo&" in hent and "U " in hent, dgl[:100])
    ck("T24b FIELD 1, the type (owner, 3 Nov 26: \"Exclude field 1 from batch actions, allow it on a single item with a confirm warning\"): G refuses field 1 when more than one "
       "record is shown, with its own words and BEFORE the preview; on one record the preview keeps the old and new value of field 1 and the box carries a WARNING line naming them "
       "before Run is asked; the help says so",
       ordered(dgl, "if gfld = 1 and gn > 1 then", "msg = 'field 1 is the type of the record: G changes it on one record only", "return", "end",
               "gw = 0\ngosub gc.pass", "if gfld = 1 then", "WARNING: this changes the TYPE of ' : gid<1> : ' (field 1): \"' : g1old : '\" -> \"' : g1new : '\"",
               "call $tk_confirm(gsent, glines, '', res, cmsg, sysmsg(12959))")
       and ordered(grw, "if not(gw) then", "g1old = grec<1>", "g1new = gnew<1>", "gdig<gi> = digest(grec, 0, 'MD5')")
       and "field 1" in hent, "")
    adm = txt.find("call $tk_open('tool.entries', 'admin', ctx, err)")
    ck("T28 THE ADMINISTRATOR COMES FIRST: the page's administrator check (and its stop) comes before the undo file is read, the key table built or anything is written; G and U are "
       "reached only through on.key of the page that passed it",
       0 <= adm < txt.find("\nstop\n", adm) < txt.find("gosub read.undo.info") < txt.find("gosub build.keys") and txt.find("open UNDOF") > adm
       and txt.count("gosub do.global") == 1 and txt.count("gosub do.undo") == 1, "")
    ck("T25 THE POINTER RULE for G and U (owner, 3 Nov 26): each account is judged afresh (the register read again; Windows: no relog state) and each file BEFORE it is "
       "opened for writing: the path (tokens expanded, made the account's) by K$PATH.IN, then what the kernel opened (FL$PATH) and, for a hashed file, its two subfiles, then its "
       "type; a row is reached only through a file that passed (gfok); a program's own file is judged too and its words checked before run.in; U goes the same way (gc.account, "
       "gc.file, gc.prog) before its READU; a refusal is counted and the pass goes on (no exit in the pass)",
       ordered(ga, "read arec from acc.f, gcura else arec = ''", "if arec = '' then", "return", "ap.f = parse.pathname.tokens(arec<1>)", "gaok = 1")
       and ordered(gfi, "tp = parse.pathname.tokens(trim(fr<2>))", "tp = parse.pathname.tokens(trim(fr<3>))", "if not(tp matches abs.pat) then tp = ap.f : @ds : tp",
                   "gin = kernel(K$PATH.IN, ap.f : @fm : tp)", "if gin then", "openpath tp to gf else", "rp = fileinfo(gf, FL$PATH)", "gin = kernel(K$PATH.IN, ap.f : @fm : rp)",
                   "if gin then gin = kernel(K$PATH.IN, ap.f : @fm : rp : @ds : '%0')", "if gin then gin = kernel(K$PATH.IN, ap.f : @fm : rp : @ds : '%1')",
                   "if not(gin) then", "return", "if rt # (if gkd = 3 then FL$TYPE.DIR else FL$TYPE.DH) then", "return", "gfok = 1")
       and ordered(gp, "gosub gc.account", "if not(gaok) then", "gosub gc.file", "if gfok then\ngosub gc.row") and re.search(r"\bexit\b", gp) is None
       and ordered(gpr, "gosub check.word", "gosub check.word", "gosub check.word", "if not(ok1 and ok2 and okname) then", "return",
                   "if not(kernel(K$PATH.IN, ap.f : @fm : rp : @ds : eid)) then", "return", "gpok = 1")
       and ordered(grw, "if gkd = 3 then\ngosub gc.prog\nif not(gpok) then") and grw.find("gosub gc.prog") < grw.find("readu")
       and ordered(dun, "gosub gc.account", "if not(gaok) then", "gosub gc.file", "if not(gfok) then", "gosub gc.prog", "if not(gpok) then", "readu cur from gf, uid locked"), "")
    ck("T26 THE ORDER OF A WRITE: the preview reads (READ, never READU) and returns before anything is written; the run takes the record with READU (another session's lock refuses), works "
       "the change out, refuses a record that is no longer what the preview read (its digest), writes the record AS IT WAS to the undo file FIRST, then WRITEU, drops that undo record "
       "if the WRITEU failed, releases the lock, and only then compiles a program by run.in (judged on the compiler's success line); one 'master global' audit line per account",
       ordered(grw, "if gw then\nreadu grec from gf, eid locked", "end else\nread grec from gf, eid then ghave = 1", "if glk then", "gosub gc.new", "if not(gw) then",
               "gdig<gi> = digest(grec, 0, 'MD5')", "return", "if ('S' : digest(grec, 0, 'MD5')) # ('S' : gdig<gi>) then", "release gf, eid", "return",
               "gun += 1", "on uf, gun on error", "writeu gnew on gf, eid on error", "delete uf, gun", "release gf, eid", "if grs = 'failed' then return", "if gkd = 3 then",
               "gosub compile.in.account", "if not(cok) then")
       and "digest(gnew, 0, 'MD5') : @fm : grec on uf, gun on error" in grw
       and "void kernel(K$AUDIT, 'master global account=' : gan<gk> : ' kind=' : gkw : ' changed=' : gnc<gk> : ' refused=' : gnr<gk> : ' failed=' : gnf<gk>)" in txt
       and gp.count("gosub gc.audit") == 2 and "gnew = change(grec, gfrom, gto)" in gnw and "gfno = 4" in gnw, "")
    ck("T27 U: offered only for a run not undone (read.undo.info reads the header this page wrote); the box is Run / Cancel titled 12960; a record is put back only if it is STILL "
       "byte for byte what the run wrote (its digest), else it is left and counted, never overwritten; READU, a held one left; the restored marker stops a second U putting it back; "
       "a program put back is compiled again by run.in; one 'entries undo' audit line per account; the header says undone only when nothing was held, refused or failed",
       ordered(dun, "gosub read.undo.info", "if not(un.have) then", "return", "if un.state = 'undone' then", "return", "gosub check.undo",
               "call $tk_confirm(usent, ulines, '', res, cmsg, sysmsg(12960))", "if res # 'run' then", "if uemd = 'restored' then", "readu cur from gf, uid locked",
               "case lk", "case not(got)", "case ('S' : digest(cur, 0, 'MD5')) # ('S' : uemd)", "u.since += 1", "release gf, uid", "case 1", "writeu ur on gf, uid on error",
               "release gf, uid", "write ur2 on uf, un.i on error null", "gosub compile.in.account", "if u.any then gosub undo.audit",
               "if u.lock = 0 and u.err = 0 and u.ref = 0 then", "uh<7> = 'undone'")
       and "void kernel(K$AUDIT, 'entries undo account=' : gcura : ' records=' : u.acct)" in txt
       and "if uh<1> = 'entries-undo' then" in txt and "if gkd = 3 then\ncopt = ''\ngosub compile.in.account" in dun and "'entries-undo' : @fm : date()" in dgl, "")
    return out


def ordered(text, *needles):
    """Every needle found, each after the one before it."""
    pos = -1
    for nd in needles:
        p = text.find(nd, pos + 1)
        if p < 0:
            return False
        pos = p
    return True


def load():
    with open(PAGE, encoding="utf-8", errors="replace") as f:
        src = f.read()
    with open(VOCREC, encoding="utf-8") as f:
        voc = f.read()
    helps = {}
    for k in ("tool.entries.accounts", "tool.entries.entries"):
        p = os.path.join(HELP, k)
        helps[k] = open(p, encoding="utf-8").read() if os.path.isfile(p) else ""
    with open(IDE, encoding="utf-8", errors="replace") as f:
        helps["__ide__"] = f.read()          # M4: the IDE's half of the hand-over (T19); a mutant of kind "ide" changes it
    with open(OPSH, encoding="utf-8", errors="replace") as f:
        helps["__opsh__"] = f.read()         # M4: the kernel's resolve_name refuses a link that leads nowhere (T19); kind "opsh"
    for key, path in (("__cproc__", CPROC), ("__basic__", BASIC), ("__opdio1__", OPDIO1)):
        with open(path, encoding="utf-8", errors="replace") as f:
            helps[key] = f.read()            # M6a T22: run.in keeps /idebrk/, the compiler and the IDE name the source by FL$PATH, the kernel makes it real; kinds "cproc" "basic" "opdio1"
    return src, voc, helps


MUTANTS = [
    ("the page writes", "src", "                  gosub classify\n                  locate id in ckey<1> by 'AL' setting lp else\n", "                  gosub classify\n                  delete vf, id\n                  locate id in ckey<1> by 'AL' setting lp else\n"),
    ("the page runs a command", "src", "   void kernel(K$AUDIT, 'tool start app=tool.entries')\n", "   void kernel(K$AUDIT, 'tool start app=tool.entries')\n   execute 'x'\n"),
    ("the page is not the administrator's", "src", "call $tk_open('tool.entries', 'admin', ctx, err)\n", "call $tk_open('tool.entries', '', ctx, err)\n"),     # the start's open (retake.page's has a comment after it, 9 Nov 26)
    ("the find runs at the start", "src", "   if fnd # '' then gosub run.find\n", "   gosub run.find\n"),
    ("the dict gate reads the programs field", "src", "gset := (if upcase(trim(arec<ACC$DICT.EDIT>)) = 'YES' then 'd' else '-')", "gset := (if upcase(trim(arec<ACC$BP.EDIT>)) = 'YES' then 'd' else '-')"),
    ("SDSYS is listed", "src", "         if upcase(id) # 'SDSYS' then", "         if upcase(id) # '' then"),
    ("the find is not cut", "src", "            if hn >= MAXV then", "            if 0 then"),
    ("another key row", "src", "   call $tk_keys('add', keys, 'f5', 'refresh', 'refresh', '', 1)\n", "   call $tk_keys('add', keys, 'f5', 'refresh', 'refresh', '', 1)\n   call $tk_keys('add', keys, 'd', 'delete', 'delete', '', 1)\n"),
    ("a third file is opened", "src", "   openpath @sdsys:@ds:'accounts' to acc.f then\n", "   openpath @sdsys:@ds:'batch.jobs' to bj.f then\n      close bj.f\n   end\n   openpath @sdsys:@ds:'accounts' to acc.f then\n"),
    ("a dictionary item is matched by its id only", "src", " or index(upcase(dhead), upcase(pat), 1) > 0)", ")"),
    ("a relative dictionary path is not made from the account", "src", "      if not(dp matches abs.pat) then dp = apath<ca> : @ds : dp\n", ""),
    ("the tokens of a dictionary path are not expanded", "src", "      dp = parse.pathname.tokens(dpaths<fi>)", "      dp = dpaths<fi>"),
    ("the outside test is lost", "src", "is.out = (if kernel(K$PATH.IN, apath<ca> : @fm : tp) then 0 else 1)", "is.out = 0"),
    ("the outside test is a text prefix", "src", "is.out = (if kernel(K$PATH.IN, apath<ca> : @fm : tp) then 0 else 1)", "is.out = (if tp[1, len(apath<ca>)] = apath<ca> then 0 else 1)"),
    ("dictionary items are not marked", "src", "                        ins doutf before cout<lp>\n", ""),
    ("a Q-pointer to another account is not marked", "src", "         coutf = (if downcase(trim(r<2>)) = downcase(anm<ca>) then 0 else 1)\n", "         coutf = 0\n"),
    ("a remote item is not marked", "src", "      case cty = 'R'\n         coutf = 1\n", ""),
    ("K keeps the filter", "src", "   if kind > 3 then kind = 1\n   fnd = '' ; filt = ''\n", "   if kind > 3 then kind = 1\n"),
    ("K stops at the dictionaries", "src", "   if kind > 3 then kind = 1\n", "   if kind > 2 then kind = 1\n"),
    ("a .out file is a program file", "src", "               if not(len(tl) > 4 and tl[len(tl) - 3, 4] = '.out') then\n", "               if 1 then\n"),
    ("the .out file beside a program file is not looked for", "src", "            op2 = pp : '.out'", "            op2 = ''"),
    ("a program is built only if its case matches", "src", "         onames = downcase(onames)\n", ""),
    ("a program file that is not a directory is read", "src", "            if fileinfo(pfv, FL$TYPE) = FL$TYPE.DIR then\n", "            if 1 then\n"),
    ("a program file outside the account is not marked", "src", "                           ins poutf before cout<lp>\n", "                           ins 0 before cout<lp>\n"),
    ("a dictionary is written", "src", "                  read dr from df2, eid then\n", "                  read dr from df2, eid then\n                     write dr to df2, eid\n"),
    ("the outside test of E is lost", "src", "   if not(kernel(K$PATH.IN, ap.f : @fm : tp)) then\n", "   if 0 then\n"),
    ("the outside test of E is a text prefix", "src", "   if not(kernel(K$PATH.IN, ap.f : @fm : tp)) then\n", "   if tp[1, len(ap.f)] # ap.f then\n"),
    ("the pointer's target is not judged again", "src", "   in.ok = kernel(K$PATH.IN, ap.f : @fm : rp)\n", "   in.ok = 1\n"),
    ("the subfiles are not judged", "src", "   if in.ok then in.ok = kernel(K$PATH.IN, ap.f : @fm : rp : @ds : '%0')\n", ""),
    ("a file that is not hashed is handed over", "src", "   if rt # rtw then\n", "   if 0 then\n"),
    ("a program file need not be a directory file", "src", "   rtw = (if isprog then FL$TYPE.DIR else FL$TYPE.DH)", "   rtw = (if isprog then rt else FL$TYPE.DH)"),
    ("the pointer is a Q-pointer into the account's VOC again", "src", "qrec = 'F' : @fm : tp : @fm : (if efl = '' then '' else tp)", "qrec = 'Q' : @fm : ea : @fm : qf"),
    ("creating.seqkey is handed to the IDE", "src", "   ok2 = (okname and eid # 'creating.seqkey')", "   ok2 = okname"),
    ("no sweep at the start", "src", "   gosub sweep.pointers\n", ""),
    ("the sweep takes every user's pointers", "src", "   sw.pre = 'zm' : @userno : '.'\n", "   sw.pre = 'zm'\n"),
    ("a foreign entry of SDSYS's VOC is overwritten", "src", "      if qold # qrec then\n", "      if 0 then\n"),
    ("the pointer is left after the IDE", "src", "   execute sent\n   gosub drop.pointer\n", "   execute sent\n"),
    ("the page runs anything", "src", "   if field(sent, ' ', 1) # 'ide' then\n", "   if 0 then\n"),
    ("the data path is judged for an item", "src", "that has a dictionary'\n            return\n         end\n         tp = parse.pathname.tokens(trim(fr<3>))\n", "that has a dictionary'\n            return\n         end\n         tp = parse.pathname.tokens(trim(fr<2>))\n"),
    ("E refuses the programs again", "src", "   if pane # 2 then\n      msg = 'Tab to the entries first, then E'\n      return\n   end\n",
     "   if pane # 2 then\n      msg = 'Tab to the entries first, then E'\n      return\n   end\n   if kind = 3 then\n      return\n   end\n"),
    ("a program's own file is not judged", "src", "   if isprog and in.ok then in.ok = kernel(K$PATH.IN, ap.f : @fm : rp : @ds : eid)", "   in.ok = in.ok"),
    ("the program pointer reaches a dictionary", "src", "   if isprog then qrec = 'F' : @fm : tp ", "   if isprog then qrec = qrec "),
    ("C compiles without the checks", "src", "   emode = 'compile'\n   gosub edit.record\n", "   gosub compile.reached\n"),
    ("C is judged on nothing", "src", "   cok = (index(cout, 'Compiled 1 program(s) with no errors', 1) > 0)", "   cok = 1"),
    ("the IDE compiles a master tab here in SDSYS", "ide", "   if in.ptr # '' and c.file = in.ptr then\n", "   if 0 then\n"),
    ("the IDE runs a master tab", "ide", "(cmd = 'catalog' or cmd = 'run' or cmd = 'debug' or cmd = 'debug1')", "(cmd = 'catalog')"),
    ("the IDE catalogues a master tab here in SDSYS", "ide", "execute 'run.in ' : in.acct : ' catalog ' : in.file : ' ' : c.id capturing co", "execute 'catalog ' : in.file : ' ' : c.id capturing co"),
    ("the IDE takes an account name with any character", "ide", "      if in.good and convert('abcdefghijklmnopqrstuvwxyz0123456789._-', '', in.acct : in.file) # '' then in.good = @false\n", ""),
    ("N works during a find", "src", "   if fnd # '' then\n      msg = 'Esc takes the find off first: a new record is made in the account selected in Accounts'\n      return\n   end\n", ""),
    ("the register is not read again", "src", "   read arec from acc.f, ea else arec = ''\n", "   arec = 'x'\n"),
    ("the pointer holds an unchecked path", "src", "qrec = 'F' : @fm : tp : @fm : (if efl = '' then '' else tp)", "qrec = 'F' : @fm : ap.f : @fm : (if efl = '' then '' else tp)"),
    ("the audit line is lost", "src", "   void kernel(K$AUDIT, 'master edit account=' : ea : ' kind=' : akind : ' file=' : qf : ' id=' : eid : ' new=' : enw)\n", ""),
    ("a slash is a word character", "src", "   good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'\n   for cwq", "   good = 'abcdefghijklmnopqrstuvwxyz0123456789._-/'\n   for cwq"),
    ("E works in Accounts", "src", "   if pane # 2 then\n      msg = 'Tab to the entries first, then E'\n      return\n   end\n", ""),
    ("the pointer is left when SD cannot follow it", "src", "   open dfl, qn to tf else\n      gosub drop.pointer\n", "   open dfl, qn to tf else\n"),
    ("D deletes without the id typed", "src", "call $tk_confirm(dsent, dlines, eid, res, cmsg, sysmsg(12958))", "call $tk_confirm(dsent, dlines, '', res, cmsg, sysmsg(12958))"),
    ("D deletes on Cancel", "src", "   if res # 'run' then\n      close tf", "   if 0 then\n      close tf"),
    ("D ignores another session's lock", "src", "   readu dold from tf, eid locked\n", "   read dold from tf, eid locked\n"),
    ("D has no branch (it would audit an edit and open the IDE)", "src", "   if emode = 'delete' then\n      gosub delete.reached\n      return\n   end\n", ""),
    ("D deletes through a second open", "src", "   if emode # 'delete' then close tf", "   close tf"),
    ("the pointer is left after a delete", "src", "   delete tf, eid on error delok = @false\n   close tf\n   gosub drop.pointer\n", "   delete tf, eid on error delok = @false\n   close tf\n"),
    ("the delete's message is made after the redraw", "src", "   dmsg = 'deleted ' : eid : ' from ' : dwhere\n", ""),
    ("D refuses the programs again", "src", "   nrows = (if fnd # '' then hn else en)\n   if ec < 1 or ec > nrows then\n      msg = 'there is no entry here to delete'",
     "   if kind = 3 then\n      return\n   end\n   nrows = (if fnd # '' then hn else en)\n   if ec < 1 or ec > nrows then\n      msg = 'there is no entry here to delete'"),
    # M6a: D of a program and its compiled program
    ("the .out file of D is not judged", "src", "   if not(kernel(K$PATH.IN, ap.f : @fm : dop)) then\n", "   if 0 then\n"),
    ("the object's own file is not judged", "src", "   if do.in then do.in = kernel(K$PATH.IN, ap.f : @fm : dorp : @ds : doid)", "   do.in = do.in"),
    ("what the .out open reached is not judged", "src", "   do.in = kernel(K$PATH.IN, ap.f : @fm : dorp)\n", "   do.in = 1\n"),
    ("D of a program has no object test", "src", "   if isprog then\n      gosub object.judge", "   if 0 then\n      gosub object.judge"),
    ("the object is deleted when the program was not", "src", "      if delok then\n         dores = 'deleted'", "      if 1 then\n         dores = 'deleted'"),
    ("the object is not deleted", "src", "         delete dof, doid on error dores = 'failed'\n", ""),
    ("the .out the VOC names is not read", "src", "      if isprog then read dorr from rvf, efl : '.out' else dorr = ''", "      dorr = ''"),
    ("the object's id keeps the case", "src", "   doid = downcase(eid)\n", "   doid = eid\n"),
    ("a program's delete is audited as a dictionary item", "src", "      dkind = 'bp'\n", "      dkind = 'dict'\n"),
    ("the catalog entry is not mentioned", "src", "A catalog entry of the program is left", "The program goes"),
    ("D of a program runs DECATALOG", "src", "   dores = 'none'\n", "   dores = 'none'\n   execute 'run.in ' : ea : ' decatalog ' : eid capturing dcx\n"),
    # M6a T22: the editor's breakpoints handed to a debugger run through run.in
    ("a master tab's debug arms nothing", "ide", "         gosub bk.arm\n         bk.first = @false\n         gosub leave.screen\n         execute 'run.in '",
     "         bk.first = @false\n         gosub leave.screen\n         execute 'run.in '"),
    ("a master tab's marks are not taken back", "ide", "c.id trapping aborts\n         gosub bk.take\n         gosub retake.screen\n      end\n      bk.first = @false\n      return",
     "c.id trapping aborts\n         gosub retake.screen\n      end\n      bk.first = @false\n      return"),
    ("the hand-over names the pointer, not the file", "ide", "ibk.path = fileinfo(bk.fv, FL$PATH) : @ds : c.id", "ibk.path = c.file : @ds : c.id"),
    ("run.in deletes the named common", "cproc", "   ri.account = ri.acct\n   ri.active = 1\n", "   ri.account = ri.acct\n   delete.common 'idebrk'\n   ri.active = 1\n"),
    ("the compiler stores the path as typed", "basic", "   source.path = fileinfo(src.f, fl$path) : @ds", "   source.path = src.name : @ds"),
    ("the kernel stores the path as given", "opdio1", "  fullpath(pathname, mapped_name);\n", "  strcpy(pathname, mapped_name);\n"),
    ("B debugs without the checks", "src", "   emode = 'debug'\n   gosub edit.record\n", "   gosub debug.reached\n"),
    ("B debugs after a failed compile", "src", "   copt = ' debugging'\n   gosub compile.in.account\n   if not(cok) then\n", "   copt = ' debugging'\n   gosub compile.in.account\n   if 0 then\n"),
    ("the IDE debugs a master tab here in SDSYS", "ide", "execute 'run.in ' : in.acct : ' debug ' : in.file : ' ' : c.id trapping aborts", "execute 'debug ' : in.file : ' ' : c.id trapping aborts"),
    ("the voc record is in newvoc form", "voc", "V\nCA\n$tool_entries\n", "V\nCA\n$tool_jobs\n"),
    ("a help record loses its document", "help", "19-the-master-files", "00-nothing"),
    # (Linux's ten relog mutants, M_RELOG, are not carried: see the header)
    # ---- 3 Nov 26, S.97 / S.96: G and U.  THE FIRST NEW MUTANT IS M_GLOBAL
    ("G changes every row of the account with no filter", "src", "   if fnd = '' and filt = '' then\n      msg = 'G changes", "   if 0 then\n      msg = 'G changes"),
    ("G takes a list cut at MAXV", "src", "   if gtr then\n", "   if 0 then\n"),
    ("G is offered to the AI", "src", "   call $tk_keys('ai', keys, 'refresh', '', '', '', '')\n", "   call $tk_keys('ai', keys, 'refresh', '', '', '', '')\n   call $tk_keys('ai', keys, 'global', '', '', '', '')\n"),
    ("G asks for a typed name", "src", "call $tk_confirm(gsent, glines, '', res, cmsg, sysmsg(12959))", "call $tk_confirm(gsent, glines, 'yes', res, cmsg, sysmsg(12959))"),
    ("G writes with no undo file", "src", "   gosub undo.file\n   if not(uok) then\n", "   uok = 1\n   if not(uok) then\n"),
    ("the pointer rule of G is lost", "src", "   if not(gin) then\n", "   if 0 then\n"),
    ("what G opened is not judged", "src", "      gin = kernel(K$PATH.IN, ap.f : @fm : rp)\n", "      gin = 1\n"),
    ("the subfiles G opened are not judged", "src", "         if gin then gin = kernel(K$PATH.IN, ap.f : @fm : rp : @ds : '%0')\n", ""),
    ("G's path is judged as text", "src", "   gin = kernel(K$PATH.IN, ap.f : @fm : tp)\n", "   gin = (tp[1, len(ap.f)] = ap.f)\n"),
    ("a program's own file is not judged by G", "src", "   if not(kernel(K$PATH.IN, ap.f : @fm : rp : @ds : eid)) then\n      gpw", "   if 0 then\n      gpw"),
    ("G stops at the first account with a refusal", "src", "         if gk > 0 and gw then gosub gc.audit\n", "         if gk > 0 and gw then gosub gc.audit\n         if gk > 0 and gnr<gk> + gnf<gk> > 0 then exit\n"),
    ("G ignores another session's lock", "src", "      readu grec from gf, eid locked\n", "      read grec from gf, eid locked\n"),
    ("G writes a record that changed since the preview", "src", "   if ('S' : digest(grec, 0, 'MD5')) # ('S' : gdig<gi>) then\n", "   if 0 then\n"),
    ("G writes the data before the undo record", "src",
     "   gun += 1\n   write ea : @fm : gkw : @fm : (if efl = '' then 'voc' else efl) : @fm : eid : @fm : digest(gnew, 0, 'MD5') : @fm : grec on uf, gun on error\n"
     "      gun -= 1\n      release gf, eid\n      grs = 'failed'\n      grw = 'the undo file could not be written (status ' : status() : ')'\n      return\n   end\n"
     "   writeu gnew on gf, eid on error\n      grs = 'failed'\n      grw = 'the file refused the write (status ' : status() : ')'\n      delete uf, gun                                            ;* the old record of a write that did not happen is not kept\n      gun -= 1\n   end\n",
     "   writeu gnew on gf, eid on error\n      grs = 'failed'\n      grw = 'the file refused the write (status ' : status() : ')'\n   end\n"
     "   gun += 1\n   write ea : @fm : gkw : @fm : (if efl = '' then 'voc' else efl) : @fm : eid : @fm : digest(gnew, 0, 'MD5') : @fm : grec on uf, gun on error\n"
     "      gun -= 1\n   end\n"),
    ("the undo keeps the new record", "src", "digest(gnew, 0, 'MD5') : @fm : grec on uf, gun on error", "digest(gnew, 0, 'MD5') : @fm : gnew on uf, gun on error"),
    ("a changed program is not compiled", "src", "   grs = 'done'\n   if gkd = 3 then\n", "   grs = 'done'\n   if 0 then\n"),
    ("G has no audit line", "src", "   void kernel(K$AUDIT, 'master global account=' : gan<gk>", "   void kernel(K$AUDIT, 'master x account=' : gan<gk>"),
    ("U puts back a record changed since the run", "src", "         case ('S' : digest(cur, 0, 'MD5')) # ('S' : uemd)\n", "         case 0\n"),
    ("U ignores another session's lock", "src", "      readu cur from gf, uid locked\n", "      read cur from gf, uid locked\n"),
    ("U skips the pointer rule", "src", "      if not(gfok) then\n         u.ref += 1\n", "      if 0 then\n         u.ref += 1\n"),
    ("U is offered after the run was undone", "src", "(if un.have and un.state # 'undone' then 1 else 0)", "(if un.have then 1 else 0)"),
    ("a second U puts a record back again", "src", "      if uemd = 'restored' then\n", "      if 0 then\n"),
    ("U never marks the run undone", "src", "         uh<7> = 'undone'\n", ""),
    ("U has no audit line", "src", "   void kernel(K$AUDIT, 'entries undo account='", "   void kernel(K$AUDIT, 'entries x account='"),
    ("a program put back is not compiled", "src", "               if gkd = 3 then\n                  copt = ''\n", "               if 0 then\n                  copt = ''\n"),
    ("the undo file is not asked of $tk_ownfile", "src", "   call $tk_ownfile(uf, UNDOF, uck, ucw)\n", "   uck = 1\n"),
    ("the undo file is read before the administrator check", "src", "   call $tk_open('tool.entries', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n",
     "   gosub read.undo.info\n   call $tk_open('tool.entries', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n"),
    ("the help does not explain G", "helpe", "&entries.undo&", "the undo file"),
    # ---- 3 Nov 26, the owner's field 1 answer: THE FIRST IS M_FIELD1
    ("G changes field 1 on many records", "src", "   if gfld = 1 and gn > 1 then\n", "   if 0 then\n"),
    ("G's field 1 test comes after the preview", "src", "      if gfld = 1 and gn > 1 then\n", "      if gfld = 1 and gn > 1 and gw = 1 then\n"),
    ("field 1 on one record has no warning", "src", "   if gfld = 1 then\n      glines<-1> = ''\n", "   if 0 then\n      glines<-1> = ''\n"),
    ("the warning does not say the old value", "src", "g1old = grec<1>", "g1old = ''"),
    ("the help does not explain field 1", "helpe", "field 1", "the type"),
    # ---- 10 Nov 26, Windows: THE FIRST IS M_WINDOWS
    ("the SDSYS column asks a group again", "src", "sdsys.state:\n   sdw = 'yes'\n   return\n", "sdsys.state:\n   sdw = 'n/a'\n   if is_grp_member('sdsys', sg.grp) then sdw = 'yes'\n   return\n"),
    ("the accounts help explains relog again", "help", "on Windows it is always yes", "it says relog when the session does not hold the group"),
    ("B debugs on Windows", "src", "   msg = 'B is not built on Windows: run.in does not debug in another account.  Debug the program in its own account'\n   return\n", ""),
    ("an absolute path is a leading slash only", "src", "   abs.pat = \"'\" : @ds : \"'0X\" : @vm : \"1A':\\'0X\" : @vm : \"1A':/'0X\"\n", "   abs.pat = \"'/'0X\"\n"),
    ("one relative path is not made the account's", "src", "         if not(pp matches abs.pat) then pp = apath<ca> : @ds : pp\n", "         if pp[1, 1] # '/' then pp = apath<ca> : @ds : pp\n"),
]
M_FIELD1 = next(i for i, m in enumerate(MUTANTS) if m[0] == "G changes field 1 on many records")
M_GLOBAL = next(i for i, m in enumerate(MUTANTS) if m[0] == "G changes every row of the account with no filter")
M_WINDOWS = next(i for i, m in enumerate(MUTANTS) if m[0] == "the SDSYS column asks a group again")


def selftest():
    src, voc, helps = load()
    if any(not ok for _, ok, _ in checks(src, voc, helps)):
        print("selftest: the unmutated source already fails; fix that first")
        return 1
    missed = 0
    start = 0                                    # --from=N runs the mutants from number N on (M_RELOG is the first of 2 Nov 26)
    for a in sys.argv[1:]:
        if a.startswith("--from="):
            start = int(a.split("=", 1)[1])
    ran = 0
    for i, (name, kind, old, new) in enumerate(MUTANTS):
        if i < start:
            continue
        ran += 1
        s, v, h = src, voc, dict(helps)
        if kind == "src":
            if s.count(old) != 1:
                print("  [CANNOT] %-48s the text occurs %d times" % (name, s.count(old)))
                missed += 1
                continue
            s = s.replace(old, new)
        elif kind == "voc":
            v = v.replace(old, new)
        elif kind in ("ide", "opsh", "cproc", "basic", "opdio1"):
            key = "__%s__" % kind
            if h[key].count(old) != 1:
                print("  [CANNOT] %-48s the text occurs %d times in %s" % (name, h[key].count(old), kind))
                missed += 1
                continue
            h[key] = h[key].replace(old, new)
        elif kind == "helpe":
            h["tool.entries.entries"] = h["tool.entries.entries"].replace(old, new)
        else:
            h["tool.entries.accounts"] = h["tool.entries.accounts"].replace(old, new)
        caught = [n for n, ok, _ in checks(s, v, h) if not ok]
        if caught:
            print("  [caught] %-48s by %s" % (name, ", ".join(c.split()[0] for c in caught[:4])))
        else:
            print("  [MISSED] %-48s" % name)
            missed += 1
    print("selftest: %d mutants run (from %d of %d), %d missed or not applied" % (ran, start, len(MUTANTS), missed))
    return 0 if missed == 0 and ran > 0 else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    try:
        src, voc, helps = load()
    except OSError as e:
        print("cannot read the source: %s" % e)
        return 2
    res = checks(src, voc, helps)
    failed = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    print("test-toolentries-units: %d checks, %d failed" % (len(res), failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
