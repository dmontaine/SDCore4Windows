#!/usr/bin/env python3
"""test-tooljobs-units.py - the scheduled jobs page's administrator half (S.102 stage 4): TOOL.JOBS's Jobs view (`gpl.bp/tool_jobs`) and its verb SET.JOB (`gpl.bp/set_job`), as
invariants read off the source.  Free: no install, no elevation, no sd.

    python C:\\Users\\Don\\Projects\\SDCore4Windows\\sdb_ai\\sd64\\gplbld\\test-tooljobs-units.py
    python C:\\Users\\Don\\Projects\\SDCore4Windows\\sdb_ai\\sd64\\gplbld\\test-tooljobs-units.py --selftest [--from=N]

10 Nov 26 Windows port - from Linux d049d8bb (S.102 stage 4), carry area 14.  The checks are Linux's; the helper is gplbld/sd-jobs.ps1 (Task Scheduler) in place of
sd-elevate (systemd), set.job reaches it through !ps_script_out (no os.execute at all: V1, V15), its shell lines are the words after the helper's path (hargs: V3), its
success lines start "sd-jobs: " (V6), the messages are Linux's + 1005, and the help record names the Administrator page 17-scheduled-jobs.  sandbox-tool-jobs.py is not
carried: nothing here runs set.job against the helper's dry run (test-jobs-helper-units.ps1 runs the helper alone).

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the BASIC as text, with comments and (where it says so) quoted strings removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A JOB IS
SCHEDULED OR THAT THE PAGE SENDS WHAT IT SHOWS***: that is an installed system's witness (the real set.job and the real Task Scheduler).  What a text check is for: the
properties that keep the page a FRONT END and the verb a thin door to the job helper -
  PAGE  administrator first; it writes, deletes and executes nothing itself; it may run only set.batch and set.job, through $tk_run; every change is sent only after a $tk_confirm box answered
        Run whose sentence is the very variable it runs; a delete makes the person type the job's name; the time goes as hh.mm (no colon passes $tk_run); the job ids are the helper's own
        four; a damaged job is not run; the AI line is offered no job action; the help record exists.
  VERB  administrator first, before anything is run; the helper is SD's own sd-jobs.ps1 and every line asks it one of its own verbs; !ps_script_out only in run.cmd;
        the name and the schedule are checked before the helper is asked; add refuses an existing job and change a missing one BEFORE job-set; a change is judged on the helper's own
        success line AND its status (the lines sd-jobs.ps1 really prints); every change asked for is audited, in lower case; the ids are the helper's; set.job is in SDSYS's VOC only.
  REVIEW (2 Nov 26) set.job writes, deletes and executes nothing itself (V15); run refuses a damaged job before job-run (V16); C refuses a name the form could never send (P15);
        the Command menu's "Allow or stop allowing" is not offered in the Jobs view (P16).
--selftest breaks each invariant the way an edit plausibly would and requires a check to notice it (mutants from M_S102S4 on: `--from=N` starts at mutant N).
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_jobs"),
    "verb": os.path.join(GPL, "set_job"),
    "voc": os.path.join(SDSYS, "voc_template", "set.job"),
    "help": os.path.join(SDSYS, "helptext", "tool.jobs.jobs"),
    "elev": os.path.join(HERE, "sd-jobs.ps1"),
}
NEWVOC = os.path.join(SDSYS, "newvoc", "set.job")
MSGDIR = os.path.join(SDSYS, "messages")
MSGS = (12196, 12229, 12251, 12255, 12307, 12324, 12337, 12338, 12794, 12797)      # Linux's 11191 ... 11792, + 1005
IDS = ["backup-all", "update-accounts"]          # check-masters and sync-masters went with S.96 M6 (2 Nov 26)


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    raw["newvoc_has"] = "1" if os.path.exists(NEWVOC) else ""
    for n in MSGS:
        try:
            with open(os.path.join(MSGDIR, str(n)), encoding="latin-1") as f:
                raw["msg%d" % n] = f.read()
        except OSError:
            raw["msg%d" % n] = None
    return raw


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        q, cut = "", -1
        for i, ch in enumerate(line):
            if q:
                if ch == q:
                    q = ""
            elif ch in "'\"":
                q = ch
            elif ch == ";" and line[i + 1:i + 2] == "*":
                cut = i
                break
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def no_strings(code):
    return re.sub(r"'[^'\n]*'|\"[^\"\n]*\"", "''", code)


def block(text, label):
    """An internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def checks(raw):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    page, verb, elev = strip_bas(raw["page"]), strip_bas(raw["verb"]), raw["elev"]
    pn, vn = no_strings(page), no_strings(verb)
    ck("P0 the page, the verb and the helper are there to read (a check of nothing is a failure)", len(page) > 5000 and len(verb) > 2000 and "'job-run' {" in elev, (len(page), len(verb)))

    # ---- the page
    op = page.find("call $tk_open('tool.jobs', 'admin'")
    first = min([i for i in (page.find("openpath"), page.find("$tk_run(")) if i >= 0] or [len(page)])
    ck("P1 the page opens the base for the administrator before it reads or runs anything", 0 <= op < first, (op, first))
    bad = [w for w in ("write ", "writev ", "writeu ", "delete ", "execute ", "os.execute", "openseq", "osopen", "oswrite", "osdelete", "writeseq", "matwrite")
           if re.search(r"(^|[\s;])" + re.escape(w), pn, re.M)]
    ck("P2 the page writes, deletes and executes nothing itself (no write, delete, execute, os.execute or sequential file statement)", not bad, bad)
    ck("P3 the page may run only set.batch and set.job, and every $tk_run is given that list",
       re.search(r"^\s*allow = 'set\.batch set\.job'", page, re.M) is not None and len(re.findall(r"\$tk_run\(", page)) == len(re.findall(r"\$tk_run\(allow,", page)) == 2, "")
    rl = page.find("call $tk_run(allow, 'set.job', jout, jst, jrerr)")
    ck("P4 the list is read by set.job with nothing after it (no argument, no change), in read.jobs", rl > 0 and rl in range(page.find("read.jobs:"), page.find("keep.tops:")), rl)
    rs = block(page, "run.sent")
    ck("P5 the one $tk_run that changes something runs the variable sent, in run.sent", "call $tk_run(allow, sent, out, st, err)" in rs, "")
    unconfirmed = []
    for lab in ("change", "job.confirm", "job.delete", "job.run"):
        b = block(page, lab)
        c, r, g = b.find("call $tk_confirm(sent,"), b.find("if res = 'run' then"), b.find("gosub run.sent")
        if not (0 <= c < r < g) or b.count("gosub run.sent") != 1 or re.search(r"\n\s*sent = ", b[c:]) is not None:
            unconfirmed.append(lab)
    others = [lab for lab in re.findall(r"^([a-z][a-z.0-9]*):\s*$", page, re.M) if "gosub run.sent" in block(page, lab) and lab not in ("change", "job.confirm", "job.delete", "job.run")]
    ck("P6 every change is sent only after a $tk_confirm of that very sentence was answered Run (change, job.confirm, job.delete, job.run; no other routine sends one; sent is not set again after the box)",
       not unconfirmed and not others, (unconfirmed, others))
    ck("P7 a delete asks for the job's name to be typed in the box", "call $tk_confirm(sent, el, fname, res, cmsg)" in block(page, "job.delete"), "")
    jc = block(page, "job.confirm")
    ck("P8 the sentence of N and C is 'set.job add|change NAME JOB' and the schedule with the time as hh.mm (no colon passes $tk_run)",
       "sent = 'set.job ' : fmode : ' ' : fname : ' ' : fjob : ' ' : change(fsch, ':', '.')" in jc, "")
    jf = block(page, "job.form")
    ck("P9 the form checks the name, refuses an existing name for N, checks the job id and the schedule before the box; the answers are taken in lower case",
       all(s in jf for s in ("gosub name.ok", "case not(nok)", "case fmode = 'add' and jn > 0 and index(@fm : jnm : @fm, @fm : fname : @fm, 1) > 0", "case jx = 0", "case sw = ''", "downcase(trim(fv<1>))")), "")
    ids = re.search(r"^\s*JOBIDS = (.+)$", page, re.M)
    cmds = re.search(r"^\s*JOBCMDS = (.+)$", page, re.M)
    hel = dict(re.findall(r"^\s+'([a-z-]+)'\s+\{ return '([^']+)' \}", elev, re.M))
    pids = re.findall(r"'([^']+)'", ids.group(1)) if ids else []
    pcmds = re.findall(r"'([^']+)'", cmds.group(1)) if cmds else []
    ck("P10 the page's job ids and their commands are the job helper's own two, in the same pairs", pids == IDS and hel == dict(zip(pids, pcmds)), (pids, pcmds, hel))
    ck("P11 a damaged job is not run (job.run refuses it before the box)", re.search(r"if jbad<ji> # '' then\s*\n\s*msg = 'a damaged job cannot be run", block(page, "job.run")) is not None, "")
    ai = re.findall(r"\$tk_keys\('ai', keys, '([a-z]+)'", page)
    ck("P12 the AI line is offered only the pane switch, the output pane and refresh: no job action", sorted(ai) == ["output", "pane", "refresh"], ai)
    hm = raw["help"].split("\n")
    ck("P13 the page asks for tool.jobs.jobs in the Jobs view and the help record has a title and the page 17-scheduled-jobs (the Administrator page; Linux's is 23)", "hkey = 'tool.jobs.jobs'" in page and len(hm) >= 3 and hm[0].strip() and hm[1] == "17-scheduled-jobs", hm[:2])
    nk = block(page, "name.ok")
    ck("P14 the page's name rule is the helper's: 1 to 32, a letter first, a-z 0-9 and the dash, no dash at the end",
       all(s in nk for s in ("len(jname) < 1 or len(jname) > 32", "index('abcdefghijklmnopqrstuvwxyz', jname[1, 1], 1) = 0", "jname[len(jname), 1] = '-'", "convert('abcdefghijklmnopqrstuvwxyz0123456789-', '', jname)"))
       and "^[a-z]([a-z0-9-]{0,30}[a-z0-9])?$" in elev, "")

    # ---- the verb
    adm = vn.find("if not(kernel(K$ADMINISTRATOR, -1)) then")
    ex = [m.start() for m in re.finditer(r"ps_script_out\(script, @true\)", vn)]
    ck("V1 set.job asks for the administrator before anything is run; the helper is run only by run.cmd, through !ps_script_out, and os.execute is not used",
       0 <= adm < min(ex or [0]) and len(ex) == 1 and ex[0] in range(vn.find("run.cmd:"), len(vn)) and "os.execute" not in vn, (adm, ex))
    ck("V2 the helper is SD's own sd-jobs.ps1 (K$WINPATH of /sd-jobs.ps1, beside sd.exe's tree, not the data tree), refused if it cannot be named or holds a quote",
       "helper = kernel(K$WINPATH, '/sd-jobs.ps1')" in verb and "if helper = '' or index(helper, q, 1) then" in verb
       and "script = '& ' : q : helper : q : ' ' : hargs : '; exit $LASTEXITCODE'" in verb, "")
    asg = re.findall(r"^\s*hargs = (.+)$", verb, re.M)
    ck("V3 every helper line the verb builds is one of the helper's own verbs followed by checked words", asg and all(re.match(r"'job-(set|delete|run|list|state)( '|'$)", a) for a in asg), asg)
    top = verb[:verb.find("\nname.ok:")]                                      # the main line, up to the first internal subroutine
    n1, s1, l1, a1, c1, js = (top.find(p) for p in ("gosub name.ok", "gosub sched.ok", "gosub read.list", "if action = 'add' and there then", "if action = 'change' and not(there) then",
                                                     "hargs = 'job-set '"))
    ck("V4 the name, then the schedule, then the list; add refuses an existing name and change a missing one, all before job-set", 0 <= n1 < s1 < l1 < a1 < js and l1 < c1 < js, (n1, s1, l1, a1, c1, js))
    d1, r1 = top.find("hargs = 'job-delete ' : jname"), top.find("hargs = 'job-run ' : jname")
    ck("V5 delete and run are asked only after the name passed", 0 <= n1 < d1 and n1 < r1 and "if not(ok) then stop sysmsg(12229" in top, (n1, d1, r1))
    wants = re.findall(r"want = '([^']*)'", top)
    helper_says = ('"${Prog}: job $n is scheduled: $($s.Sched)"' in elev and '"${Prog}: job $n started"' in elev and '"${Prog}: job $n deleted"' in elev
                   and "$Prog = 'sd-jobs'" in elev)
    ck("V6 the verb anchors on the helper's own success lines (job NAME is scheduled / deleted / started), which sd-jobs.ps1 really prints",
       wants == ["sd-jobs: job ", "sd-jobs: job ", "sd-jobs: job "] and "' is scheduled: '" in top and "' deleted'" in top and "' started'" in top and helper_says, wants)
    ck("V7 a success needs the helper's line AND status 0; a failure says 12337", "if out<i>[1, len(want)] = want then done = @true" in top and "if rc # 0 then done = @false" in top
       and "if not(done) then crt sysmsg(12337, rc)" in top, "")
    au = top.find("void kernel(K$AUDIT, aud)")
    ck("V8 every change asked of the helper is audited after it ran, in lower case, with its result", 0 < top.find("gosub run.cmd") < au and "aud = 'set.job ' : action : ' name=' : jname" in top
       and "' result=' : (if done then 'done' else 'failed status=' : rc)" in top and "words = downcase(trim(@sentence))" in top, "")
    vids = re.search(r"if job # '([a-z-]+)' and job # '([a-z-]+)' then", verb)
    ck("V9 the verb's job ids are the helper's two (check-masters and sync-masters went with S.96 M6, 2 Nov 26)", vids is not None and list(vids.groups()) == IDS, vids.groups() if vids else None)
    so = block(verb, "sched.ok")
    ck("V10 the schedule may hold only a-z, 0-9, the colon and blanks (after hh.mm is made hh:mm), so nothing else reaches the shell line", "sched = change(sched, '.', ':')" in so
       and "convert('abcdefghijklmnopqrstuvwxyz0123456789: ', '', sched) # '' then return" in so and so.find("change(sched, '.', ':')") < so.find("convert("), "")
    nv = block(verb, "name.ok")
    lines_of = lambda t: [ln.strip() for ln in t.split("\n") if ln.strip()]
    ck("V11 the verb's name rule is the page's", len(nv) > 100 and lines_of(nv.replace("ok = @false", "X").replace("ok = @true", "Y")) == lines_of(nk.replace("nok = 0", "X").replace("nok = 1", "Y")), "")
    ck("V12 set.job is in SDSYS's VOC only (voc_template, not newvoc)", raw["voc"] == "V\nCA\n$set_job\n" and not raw["newvoc_has"], repr(raw["voc"]))
    miss = [n for n in MSGS if not raw["msg%d" % n]]
    upper = [n for n in MSGS if raw["msg%d" % n] and re.search(r"SET\.JOB|Set\.job", raw["msg%d" % n])]
    ck("V13 the verb's ten messages exist, and the command word in them is lower case", not miss and not upper, (miss, upper))
    used = set(int(x) for x in re.findall(r"sysmsg\((\d+)", verb + page) if 12000 <= int(x) <= 12999)
    ck("V14 every message of the verb is used by it", set(MSGS) <= used, sorted(set(MSGS) - used))

    # ---- 2 Nov 26, the review of stage 4
    bad = [w for w in ("write ", "writev ", "writeu ", "delete ", "execute ", "openseq", "openpath", "osopen", "oswrite", "osdelete", "writeseq", "writeblk", "matwrite", "create.file")
           if re.search(r"(^|[\s;])" + re.escape(w), vn, re.M)]
    ck("V15 set.job writes, deletes and executes nothing itself ($internal: the kernel would trust an OPENSEQ by pathname): no write, delete, execute, sequential or OS file "
       "statement, no os.execute, and its one !ps_script_out call is run.cmd's", not bad and "os.execute" not in vn and len(re.findall(r"ps_script_out\(script, @true\)", vn)) == 1, bad)
    rb = top[top.find("if action = 'run' then"):top.find("hargs = 'job-run ' : jname")]
    ck("V16 run reads the list first and refuses a job it shows as damaged (12338) before job-run is asked", "gosub read.list" in rb and "if llines<lp>[1, 8] = 'damaged ' then" in rb
       and "stop sysmsg(12338, jname)" in rb and rb.find("gosub read.list") < rb.find("stop sysmsg(12338"), rb[:200])
    jcb = block(page, "job.change")
    nm_, fm_ = jcb.find("gosub name.ok"), jcb.find("gosub job.form")
    ck("P15 C refuses a job whose name is not a job name before the form (a damaged file of any name is listed; the form could never pass)",
       0 <= nm_ < fm_ and re.search(r"if not\(nok\) then[^\n]*\n\s*msg = 'This file is not a job: neither the page nor set\.job can remove it; an administrator removes it from C:\\ProgramData\\SD\\sd-jobs: ' : fname\s*\n\s*return", jcb[nm_:fm_]) is not None, (nm_, fm_))
    ck("P16 the Command menu's 'Allow or stop allowing' (the change action) belongs to the account view's two panes, not to Jobs",
       re.search(r"\$tk_keys\('add', keys, 'enter', 'change', 'change', 'Accounts' : @sm : 'Commands', 1\)", page) is not None
       and len(re.findall(r"\$tk_keys\('add', keys, '[^']*', '[^']*', 'change',", page)) == 1, "")
    return rows


M_S102S4 = 0          # the first mutant of S.102 stage 4 (every mutant here is this sitting's)
M_REVIEW = 26         # the first mutant of the review of stage 4 (2 Nov 26): --selftest --from=26


def mutants(raw):
    out = []

    def mut(name, key, old, new):
        if old not in raw[key]:
            out.append((name, None))
            return
        r = dict(raw)
        r[key] = raw[key].replace(old, new, 1)
        out.append((name, r))

    mut("P1 the page opens for anyone", "page", "call $tk_open('tool.jobs', 'admin'", "call $tk_open('tool.jobs', 'user'")
    mut("P2 the page writes a file itself", "page", "   jread = 1\n", "   jread = 1\n   write '' on fx, 'x'\n")
    mut("P3 the page may run sh", "page", "allow = 'set.batch set.job'", "allow = 'set.batch set.job sh'")
    mut("P5 run.sent runs a fixed sentence", "page", "call $tk_run(allow, sent, out, st, err)", "call $tk_run(allow, 'set.job', out, st, err)")
    mut("P6 run now without the box", "page", "   el<-1> = 'The page does not wait for it: F5 shows when it has finished, under Last run.'\n   call $tk_confirm(sent, el, '', res, cmsg)\n",
        "   el<-1> = 'The page does not wait for it: F5 shows when it has finished, under Last run.'\n   res = 'run' ; cmsg = ''\n")
    mut("P6 the sentence is changed after the box", "page", "   call $tk_confirm(sent, el, '', res, cmsg)\n   if res = 'run' then\n      gosub run.sent\n      gosub read.jobs\n      if fmode",
        "   call $tk_confirm(sent, el, '', res, cmsg)\n   sent = sent : ' x'\n   if res = 'run' then\n      gosub run.sent\n      gosub read.jobs\n      if fmode")
    mut("P7 a delete asks no name", "page", "call $tk_confirm(sent, el, fname, res, cmsg)", "call $tk_confirm(sent, el, '', res, cmsg)")
    mut("P8 the time is sent with its colon", "page", "fjob : ' ' : change(fsch, ':', '.')", "fjob : ' ' : fsch")
    mut("P9 N does not refuse an existing name", "page", "         case fmode = 'add' and jn > 0 and index(@fm : jnm : @fm, @fm : fname : @fm, 1) > 0\n", "         case 0\n")
    mut("P10 the page offers a fifth job", "page", ": @fm : 'update-accounts'", ": @fm : 'update-accounts' : @fm : 'shell'")
    mut("P11 a damaged job is run", "page", "   if jbad<ji> # '' then\n      msg = 'a damaged job cannot be run", "   if 0 then\n      msg = 'a damaged job cannot be run")
    mut("P12 the AI line is offered run now", "page", "   call $tk_keys('ai', keys, 'refresh', '', '', '', '')\n", "   call $tk_keys('ai', keys, 'refresh', '', '', '', '')\n   call $tk_keys('ai', keys, 'jrun', '', '', '', '')\n")
    mut("P14 the page accepts a trailing dash", "page", "   if jname[len(jname), 1] = '-' then return\n   if convert('abcdefghijklmnopqrstuvwxyz0123456789-', '', jname) # '' then return\n   nok = 1",
        "   if convert('abcdefghijklmnopqrstuvwxyz0123456789-', '', jname) # '' then return\n   nok = 1")
    mut("V1 set.job runs for anyone", "verb", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n", "   if 0 then\n")
    mut("V2 a helper path holding a quote is used", "verb", "   if helper = '' or index(helper, q, 1) then\n", "   if helper = '' then\n")
    mut("V3 a helper line of the caller's own", "verb", "      hargs = 'job-delete ' : jname\n", "      hargs = jname\n")
    mut("V4 add does not ask whether the job exists", "verb", "      if action = 'add' and there then\n", "      if 0 then\n")
    mut("V4 the schedule is not checked", "verb", "      gosub sched.ok\n      if not(ok) then stop sysmsg(12255)", "      ok = 1\n      if not(ok) then stop sysmsg(12255)")
    mut("V5 run takes any name", "verb", "   if not(ok) then stop sysmsg(12229, jname[1, 40])", "   if 0 then stop sysmsg(12229, jname[1, 40])")
    mut("V6 run is judged on a word the refusal also prints", "verb", "want = 'sd-jobs: job ' : jname : ' started'", "want = 'sd-jobs: '")
    mut("V7 the helper's status is not asked", "verb", "   if rc # 0 then done = @false\n", "")
    mut("V8 a change is not audited", "verb", "   void kernel(K$AUDIT, aud)\n", "")
    mut("V9 the verb takes a fifth job", "verb", "and job # 'update-accounts' then", "and job # 'update-accounts' and job # 'shell' then")
    mut("V10 the schedule may hold a semicolon", "verb", "convert('abcdefghijklmnopqrstuvwxyz0123456789: ', '', sched)", "convert('abcdefghijklmnopqrstuvwxyz0123456789:; ', '', sched)")
    mut("V12 set.job ships to every account", "newvoc_has", "", "1")
    mut("V13 a message names SET.JOB in capitals", "msg12196", "set.job {add", "SET.JOB {add")
    # 2 Nov 26, the review of stage 4 (M_REVIEW on)
    mut("V15 set.job writes a file by pathname", "verb", "   gosub run.cmd\n   gosub show.out\n   done = @false\n",
        "   openseq '/tmp/x' to f else null\n   gosub run.cmd\n   gosub show.out\n   done = @false\n")
    mut("V16 run asks the helper about a damaged job", "verb", "            stop sysmsg(12338, jname)", "            null")
    # 10 Nov 26 Windows port: the helper run without !ps_script_out (os.execute in the main line)
    mut("V1 set.job runs a shell line of its own", "verb", "   gosub run.cmd\n   gosub show.out\n   done = @false\n",
        "   os.execute 'x'\n   gosub run.cmd\n   gosub show.out\n   done = @false\n")
    mut("P15 C opens the form for any name", "page", "   fname = jnm<ji>\n   jname = fname\n   gosub name.ok\n   if not(nok) then                                             ;* a damaged file",
        "   fname = jnm<ji>\n   jname = fname\n   gosub name.ok\n   if 0 then                                             ;* a damaged file")
    mut("P16 Allow or stop allowing is offered in the Jobs view", "page", "'change', 'Accounts' : @sm : 'Commands', 1)", "'change', '', 1)")
    return out


def main():
    raw = load()
    if "--selftest" in sys.argv:
        frm = next((int(a.split("=", 1)[1]) for a in sys.argv[1:] if a.startswith("--from=")), 0)
        base = checks(raw)
        if not all(ok for _, ok, _ in base):
            print("test-tooljobs-units --selftest: CANNOT RUN - the unmutated sources already fail:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        ms = mutants(raw)
        bad = 0
        for i, (name, r) in enumerate(ms):
            if i < frm:
                continue
            if r is None:
                print("  [NOT APPLIED] %d %s" % (i, name))
                bad += 1
                continue
            caught = [n.split(" ")[0] for n, ok, _ in checks(r) if not ok]
            print("  [%s] %d %s%s" % ("caught" if caught else "MISSED", i, name, "  (%s)" % ", ".join(caught[:4]) if caught else ""))
            bad += 0 if caught else 1
        print("test-tooljobs-units --selftest: %d mutant(s) from %d, %d not caught" % (len(ms) - frm, frm, bad))
        return 1 if bad else 0
    for k in ("page", "verb", "elev"):
        if not raw[k]:
            print("test-tooljobs-units: CANNOT RUN - %s is missing" % FILES[k])
            return 2
    res = checks(raw)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail)[:400] + ")"))
        fails += 0 if ok else 1
    print("test-tooljobs-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
