#!/usr/bin/env python3
"""test-remotesdsys-units.py - remote administration over ssh (RELEASE_1.1 202), the SD side, as invariants read off the source.  Free: no install,
no elevation, no sd.

    python gplbld/test-remotesdsys-units.py [--selftest]

13 Nov 26 Windows port - written for RELEASE_1.1 202 (Linux S.106's remote.sdsys in the Windows form; design .claude/design-remote-admin-20261113.md).
13 Nov 26 Windows port - RELEASE_1.1 202, Linux parity: B10 (RUN's REMOTE.SSH and REMOTE.API words; REMOTE.API's restart answered N through the DATA
queue), R6 (RADMIN sends both), L3 seven names; mutants for each.

WHAT IT READS: gpl.bp REMOTESDSYS (the verb and the broker's job runner), RADMIN (the remote session's commands), RADMIN_OPEN, and the hunks
of LOGIN, CPROC, CREATEA, MODIFYA and DELACC that keep the account SDRADMIN where it belongs; the VOC entry, the nine messages, stage.py,
sd.iss and finish-install.ps1.  IT RUNS NOTHING, SO IT CANNOT SAY THAT AN ACCOUNT IS MADE OR A DOOR OPENS: that is the VM witness.  What a
text check is for here is ORDER and ABSENCE: the administrator test before anything; RUN only in the broker's job, with the job's definition
deleted before a word is read; the password read once from standard input, given to the verb through the DATA queue and cleared, never in
an audit line; the remote session's identity tested before it does anything; LOGIN's gate after the case statement so every arm meets it;
the gates zeroed; the installer asking, unticked, and the uninstaller removing.  An edit that moves one of those still compiles.

--selftest breaks each invariant the way an edit plausibly would and requires the owning check to notice; a mutant nothing catches fails.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "verb": os.path.join(GPL, "remotesdsys"),
    "radmin": os.path.join(GPL, "radmin"),
    "open": os.path.join(GPL, "radmin_open"),
    "login": os.path.join(GPL, "login"),
    "cproc": os.path.join(GPL, "cproc"),
    "createa": os.path.join(GPL, "createa"),
    "modifya": os.path.join(GPL, "modifya"),
    "delacc": os.path.join(GPL, "delacc"),
    "voc": os.path.join(SDSYS, "voc_template", "remote.sdsys"),
    "stage": os.path.join(HERE, "stage.py"),
    "iss": os.path.join(HERE, "sd.iss"),
    "finish": os.path.join(HERE, "finish-install.ps1"),
}
NEWVOC = os.path.join(SDSYS, "newvoc", "remote.sdsys")
MSGS = ["12800", "12928", "12929", "12601", "12847", "12839", "12838", "12600", "12704"]   # 12601 is Linux 11929, off its +1005 slot (12934 is the AI's); 12600 not 12732, which the IDE retired 30 Oct 26


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1", newline="") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    raw["newvoc_has"] = "1" if os.path.exists(NEWVOC) else ""
    for m in MSGS:
        p = os.path.join(SDSYS, "messages", m)
        try:
            with open(p, "rb") as f:
                raw["msg" + m] = f.read().decode("latin-1")
        except OSError:
            raw["msg" + m] = ""
    return raw


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = line.find(";*")
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def block(text, label):
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def ordered(text, parts):
    """Each part found AFTER the one before it (so a part may repeat); the positions, -1 from the first one not found."""
    pos, at = [], 0
    for p in parts:
        k = text.find(p, at) if at >= 0 else -1
        pos.append(k)
        at = k + len(p) if k >= 0 else -1
    return all(x >= 0 for x in pos), pos


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    v = strip_bas(raw["verb"])
    r = strip_bas(raw["radmin"])
    o = strip_bas(raw["open"])
    lg = strip_bas(raw["login"])
    cp = strip_bas(raw["cproc"])
    ck("B0", "NULL CASE: every file read is there and not short (a check on nothing would pass)",
       len(v) > 4000 and len(r) > 2500 and len(o) > 200 and len(lg) > 20000 and len(cp) > 50000 and raw["iss"] and raw["stage"] and raw["finish"], "%d %d %d" % (len(v), len(r), len(o)))
    ck("B1", "REMOTE.SDSYS is an internal program catalogued as $remotesdsys; SDSYS's VOC has it (V CA $remotesdsys) and the shared VOC (newvoc) does not",
       re.search(r"^\$internal\s*\nprogram \$remote\.sdsys\s*\n\$catalog \$remotesdsys\b", v, re.M) is not None and raw["voc"] == "V\nCA\n$remotesdsys\n" and raw["newvoc_has"] == "", repr(raw["voc"]))
    ok, pos = ordered(v, ["   prompt ''", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      stop sysmsg(2001)", "call @parser(PARSER$RESET"])
    ck("B2", "the administrator test (2001) is the first thing the verb does, before a word is parsed", ok, str(pos))
    ok, pos = ordered(v, ["job = kernel(K$JOB.MARK, 0)", "in.job = (job[1, 7] = 'radmin-')", "if action = 'run' then\n      if not(in.job) then\n         @system.return.code = -ER$ARGS\n         stop sysmsg(12928)", "      gosub run.request"])
    ck("B3", "RUN is refused (the usage, 12928) unless kernel(K$JOB.MARK) names a radmin- job - the broker's one-shot job - and only then runs the request", ok and v.count("gosub run.request") == 1, str(pos))
    rr = block(v, "run.request")
    ok, pos = ordered(rr, ["void ospath(jobs.def, OS$DELETE)", "call @parser(PARSER$GET.TOKEN, token.type, run.verb, keyword)"])
    ck("B4", "RUN deletes the job's definition (the consumer closes the door) before it reads a word of the request", ok and "jobs.def = @sdsys[1, index(@sdsys, @ds, count(@sdsys, @ds)) - 1] : @ds : 'sd-jobs' : @ds : job" in rr, str(pos))
    sec = rr[rr.find("input secret HIDDEN"):] if "input secret HIDDEN" in rr else ""
    ok, pos = ordered(sec, ["input secret HIDDEN", "data secret\n", "data secret\n", "data 'n'", "            secret = ''\n            execute run.sentence", "run.rc = @system.return.code\n            cleardata\n         end"])
    ck("B5", "THE PASSWORD: read once from standard input with INPUT ... HIDDEN, put in the DATA queue twice and 'n' once, the variable cleared BEFORE the verb runs, the queue cleared after; "
       "it is in no audit line and no command line", ok and rr.count("data secret") == 2 and rr.count("input secret") == 1 and not re.search(r"K\$AUDIT[^\n]*secret", v) and not re.search(r"execute[^\n]*secret", v)
       and "secret" not in rr[rr.find("run.sentence = run.verb"):rr.find("begin case")], str(pos))
    ck("B6", "RUN runs only the seven verbs, refuses the words sdsys, sdradmin and shared and any word outside lower-case letters, digits, dot, dash and underscore, and its exit status says whether the verb failed",
       "run.ok = (run.verb = 'create.account' or run.verb = 'delete.account' or run.verb = 'modify.account' or run.verb = 'modify.password' or run.verb = 'remote.sdsys' or run.verb = 'remote.ssh' or run.verb = 'remote.api')" in rr
       and "if w = 'sdsys' or w = 'sdradmin' or w = 'shared' then run.ok = @false" in rr and "convert('abcdefghijklmnopqrstuvwxyz0123456789._-', '', w) # ''" in rr
       and "void kernel(K$EXIT.STATUS, (if run.rc < 0 then 1 else 0))" in rr and "data 'Y'" in block(v, "run.request"), "")
    on = block(v, "on.request")
    ok, pos = ordered(on, ["if in.job then", "stop sysmsg(12847, 'remote.sdsys on')", "gosub make.account", "helper.args = '-On'"])
    ma = block(v, "make.account")
    ck("B7", "ON is never the broker's (12847 in a job, before anything); the account is made by !create_account with no route and no gate words, then remote-admin.ps1 -On",
       ok and "call !create_account('USER', 'sdradmin', settings, err)" in ma and "settings<CA$ROUTE.SSH> = 0" in ma and "settings<CA$ROUTE.API> = 0" in ma
       and not re.search(r"CA\$(OS\.SH|OS\.EXECUTE|VOC\.EDIT|BP\.EDIT|DICT\.EDIT|NET|FILES|SHARED\.WRITE)\b", ma), str(pos))
    off = block(v, "off.request")
    ok, pos = ordered(off, ["helper.args = '-Off'", "if in.job then helper.args := ' -KeepBroker'", "gosub run.helper", "if upcase(users<i, K$USERS.UNAME>) = 'SDRADMIN' then", "z = logout(users<i, K$USERS.UID> + 0, @false)"])
    ck("B8", "OFF: remote-admin.ps1 -Off (with -KeepBroker only in the broker's own job), then every SDRADMIN session is logged out", ok, str(pos))
    rh = block(v, "run.helper")
    ck("B9", "the helper is run straight through OS.EXECUTE only in the broker's job (an elevated SDSYS with no helper of its own), through SDSYS's elevated helper otherwise",
       re.search(r"if in\.job then\s*\n\s*os\.execute hcmd", rh) is not None and "both = ps_script_out(hcmd : @fm : 'exit $LASTEXITCODE', @true)" in rh and "kernel(K$WINPATH, '/remote-admin.ps1')" in rh, "")
    ra = rr[rr.find("      case run.verb = 'remote.api'"):] if "      case run.verb = 'remote.api'" in rr else ""
    ra = ra[:ra.find("\n      case ", 10)] if ra.find("\n      case ", 10) > 0 else ra
    ok, pos = ordered(ra, ["case run.verb = 'remote.api'", "         data 'N'\n", "         execute run.sentence\n", "         run.rc = @system.return.code\n         cleardata\n"])
    ck("B10", "the doors (Linux parity): RUN takes REMOTE.SSH with ON, OFF or no word and REMOTE.API with ON, LOCAL, OFF or no word, one word at most; REMOTE.API's restart question is answered N "
       "(Enter's answer at the console: no restart, no session ended) through the DATA queue before the verb, never Y, and the queue is cleared after",
       ok and ra.count("data ") == 1 and not re.search(r"data\s+'[yY]", ra)
       and "   if run.verb = 'remote.ssh' then\n      if dcount(run.words, @fm) > 1 or (run.words # '' and run.words<1> # 'on' and run.words<1> # 'off') then run.ok = @false" in rr
       and "   if run.verb = 'remote.api' then\n      if dcount(run.words, @fm) > 1 or (run.words # '' and run.words<1> # 'on' and run.words<1> # 'local' and run.words<1> # 'off') then run.ok = @false" in rr
       and rr.find("   if run.verb = 'remote.api' then") < rr.find("   if not(run.ok) then"), str(pos))
    # 13 Nov 26 (RELEASE_1.1 282, owner): ON is SDSYS's, at its console, and asks no SDSYS password - the installer no longer offers it, so
    # the prompt RELEASE_1.1 280 added for the installer's run is gone; -On refuses anyone but SDSYS (exit 4) and says where to run it.
    ok, pos = ordered(on, ["helper.args = '-On'", "gosub run.helper", "gosub show.helper"])
    ck("B11", "ON asks no SDSYS password (RELEASE_1.1 282): -On is run once and its lines shown; no HIDDEN input in ON, no -SdsysPassword anywhere in the verb",
       ok and "input" not in on.lower().replace("helper.args = '-on'", "") and "-SdsysPassword" not in v and "sdsys.pw" not in v, str(pos))

    ck("R1", "RADMIN is an internal program catalogued as $radmin, and the remote session's identity (SDRADMIN, in sdradmin, over ssh, not elevated) is tested first, refused 2001",
       re.search(r"^\$internal\s*\nprogram \$radmin\s*\n\$catalog \$radmin\b", r, re.M) is not None
       and ordered(r, ["   prompt ''", "if upcase(@logname) # 'SDRADMIN' or downcase(@who) # 'sdradmin' or env('SSH_CONNECTION') = '' or kernel(K$ADMINISTRATOR, -1) then\n      stop sysmsg(2001)", "words = trim(@sentence)"])[0], "")
    ck("R2", "RADMIN checks every word's characters before it uses one, and refuses REMOTE.SDSYS ON (12847)",
       "convert('abcdefghijklmnopqrstuvwxyz0123456789._-', '', w) # ''" in r and "if words<1> = 'on' then stop sysmsg(12847, 'remote.sdsys on')" in r
       and r.find("convert('abcdefghijklmnopqrstuvwxyz0123456789._-'") < r.find("need.secret = @false"), "")
    ok, pos = ordered(r, ["input pw1 HIDDEN", "input pw2 HIDDEN", "if pw1 = '' or pw1 # pw2 then", "if not(pw_complex(pw1)) then", "req<-1> = 'secret=' : downcase(oconv(pw1, 'MX0C'))", "pw1 = ''\n   end\n   req<-1> = 'end'"])
    ck("R3", "THE PASSWORD in the remote session: typed hidden twice, compared, checked by !pw_complex, then hex in the request and the variable cleared; never in the audit line or the client's command line",
       ok and not re.search(r"K\$AUDIT[^\n]*(pw1|pw2|req\b|secret)", r) and not re.search(r"cmd = [^\n]*(pw1|secret)", r), str(pos))
    ok, pos = ordered(r, ["ps.dir = @sdsys : @ds : 'pstmp'", "write req to ps.f, req.id on error", "req = ''", "os.execute cmd capturing reply", "delete ps.f, req.id"])
    ck("R4", "the request goes into SDSYS's pstmp under this session's name, the client is run with its NAME, and the file is deleted after whatever happened",
       ok and "kernel(K$WINPATH, '/sd-radmin-client.ps1')" in r and "req.id = '$RADMIN.' : @userno : '.' : nonce" in r, str(pos))
    ck("R5", "the answer: out= lines printed, refused= as 12838, timeout= and noanswer= as 12839, no answer at all as 12839; the audit line says the status",
       "crt sysmsg(12838, l[9, 999])" in r and "crt sysmsg(12839, 'still running after 180 seconds')" in r and "crt sysmsg(12839, l[10, 999])" in r and "crt sysmsg(12839, 'no answer')" in r
       and "void kernel(K$AUDIT, 'remote.admin ' : verb : ' words=' : convert(@fm, ',', words) : ' status=' : job.rc)" in r, "")
    ck("R6", "RADMIN sends REMOTE.SSH and REMOTE.API with the word typed, or none (Linux parity); it asks them nothing",
       re.search(r"case verb = 'remote\.ssh' or verb = 'remote\.api'\s*\n\s*null\b", r) is not None, "")
    ck("O1", "!radmin_open reads <ProgramData>\\SD\\remote-admin\\state, from the parent of @sdsys, and is true only for 'on' (anything unreadable is off)",
       "state.dir = @sdsys[1, index(@sdsys, @ds, n) - 1] : @ds : 'remote-admin'" in o and "if trim(state.rec<1>) = 'on' then open = @true" in o and "open = @false" in o and "$catalog !radmin_open" in raw["open"], "")

    gate = lg[lg.find("   if initial.account = 'sdradmin' then"):]
    m = re.search(r"\n         void kernel\(K\$ADMINISTRATOR, 0\)\n(?:[^\n]*\n){0,12}?   end case\n\s*\n   if initial\.account = 'sdradmin' then\n", lg)
    after = lg.find("\n   audit.account = initial.account\n", m.end()) if m else -1
    ok = m is not None and after > m.end() and "goto terminate.connection" in lg[m.end():after]
    pos = [m.start() if m else -1, after]
    ck("L1", "LOGIN's gate for sdradmin is AFTER the case statement (every arm meets it) and before the account is recorded: the Windows account SDRADMIN, not started elevated, over ssh, "
       "remote administration open; any one refuses (12600); K$ADMINISTRATOR cleared",
       ok and ordered(gate, ["case upcase(@logname) # 'SDRADMIN'", "case kernel(K$OS.ELEVATED, 0)", "case env('SSH_CONNECTION') = ''", "case not(radmin_open(0))", "void kernel(K$ADMINISTRATOR, 0)",
                             "if radmin.why # '' then\n         display sysmsg(12600)", "goto terminate.connection", "radmin.login = @true"])[0], str(pos))
    zs = lg.find("   if radmin.login then\n      acc.rec<ACC$SH> = ''")
    gz = lg[zs:zs + 400] if zs >= 0 else ""
    ck("L2", "the remote session holds none of the gates, whatever its register record says: this session's copy of the record says shut for sh, os.execute, sd.accounts, net, "
       "shared write, voc, bp and dict editing ('' each) and shared read ('no') BEFORE the one place that loads them",
       all(("acc.rec<ACC$%s> = ''" % g) in gz for g in ("SH", "OS.EXEC", "SD.ACCOUNTS", "NET", "SHARED.WRITE", "VOC.EDIT", "BP.EDIT", "DICT.EDIT")) and "acc.rec<ACC$SHARED.READ> = 'no'" in gz
       and 0 < zs < lg.find("   void kernel(K$SH,      upcase(trim(acc.rec<ACC$SH>)) = 'YES')") and not re.search(r"write[uv]? acc\.rec\b", lg), str(zs))
    ck("L3", "the remote session's seven administration names in its VOC are $radmin (V CA $radmin), written at sign-in and only for that session",
       "radmin.rec = 'V' : @fm : 'CA' : @fm : '$radmin'" in lg
       and "radmin.names = 'create.account' : @fm : 'delete.account' : @fm : 'modify.account' : @fm : 'modify.password' : @fm : 'remote.sdsys'\n      radmin.names := @fm : 'remote.ssh' : @fm : 'remote.api'\n      for radmin.i = 1 to dcount(radmin.names, @fm)" in lg
       and re.search(r"if radmin\.login then\s*\n\s*radmin\.rec = ", lg) is not None, "")
    ck("L4", "the remote session says what it is (12800, the client address) on a terminal only, and the audit says where from; no password is asked of it (require.credential is for elevated sessions)",
       "display sysmsg(12800, radmin.from)" in lg and "void kernel(K$AUDIT, 'remote administration login from=' : radmin.from)" in lg
       and "if kernel(K$ADMINISTRATOR,-1) and kernel(K$TTY,0) # '' and batch.command = '' then\n         gosub require.credential" in lg, "")
    lt = block(cp, "int.logto")
    ck("C1", "LOGTO is refused to SDRADMIN (12847) and audited", re.search(r"if upcase\(@logname\) = 'SDRADMIN' then\s*\n\s*display sysmsg\(12847, 'logto'\)", lt) is not None
       and "reason=remote administration session" in lt, "")
    ck("A1", "the console verbs keep their hands off SDRADMIN: CREATE.ACCOUNT refuses the name, MODIFY.ACCOUNT refuses it and refuses to ADD it to a group, DELETE.ACCOUNT refuses it while remote administration is open (12704 each)",
       re.search(r"if downcase\(trim\(acc\.name\)\) = 'sdradmin' then\s*\n\s*stop sysmsg\(12704\)", raw["createa"]) is not None
       and raw["createa"].find("if downcase(trim(acc.name)) = 'sdradmin' then") < raw["createa"].find("   settings = ''\n   if upcase(acc.type) = 'OTHER'")
       and re.search(r"if acc\.name = 'SDRADMIN' then\s*\n\s*stop sysmsg\(12704\)", raw["modifya"]) is not None
       and "if upcase(action) = 'ADD' and upcase(user.name) = 'SDRADMIN' then" in raw["modifya"]
       and re.search(r"if acc\.name = 'sdradmin' then\s*\n\s*if radmin_open\(0\) then stop sysmsg\(12704\)", raw["delacc"]) is not None, "")
    msg_ok = all(raw["msg" + m] and raw["msg" + m].endswith("\n") and raw["msg" + m].count("\n") == 1 and "\r" not in raw["msg" + m] for m in MSGS)
    used = set(re.findall(r"sysmsg\((\d+)", v + r + o)) | set(re.findall(r"sysmsg\((12\d\d\d)", lg + cp))
    missing = sorted(u for u in used if not os.path.exists(os.path.join(SDSYS, "messages", u)))
    ck("M1", "the nine messages are there, one line each with an LF and no CR, and every message these programs show exists", msg_ok and not missing and "%1" in raw["msg12800"] and "%2" in raw["msg12929"], " ".join(missing))
    iss = raw["iss"]
    # 13 Nov 26 (RELEASE_1.1 282, owner: "should we always install remote ssh admin off ... It's just an available feature that can be
    # turned on"): the installer neither asks nor opens it.  The uninstaller still takes it away.
    ck("I1", "the installer does not offer remote administration (no page, no -RemoteAdmin to the finishing window); the uninstaller still runs remote-admin.ps1 -Remove after the jobs",
       "RemoteAdminPage" not in iss and "RemoteAdminChosen" not in iss and "' -RemoteAdmin'" not in iss
       and re.search(r"RemoveScheduledJobs;\s*\n\s*RemoveRemoteAdmin;", iss) is not None and "'\" -Remove'" in iss.replace(" + '\" -Remove'", "'\" -Remove'"), "")
    fi = raw["finish"]
    ck("I2", "finish-install.ps1 takes no -RemoteAdmin and never runs REMOTE.SDSYS",
       "$RemoteAdmin" not in fi and "'REMOTE.SDSYS'" not in fi, "")
    ck("I3", "stage.py ships remote-admin.ps1, sd-radmin.ps1 and sd-radmin-client.ps1 to the program folder", "'remote-admin.ps1', 'sd-radmin.ps1', 'sd-radmin-client.ps1'," in raw["stage"], "")
    return rows


def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:60]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


def setkey(key, val):
    def f(raw):
        r = dict(raw)
        r[key] = val
        return r
    return f


MUTANTS = [
    ("the shared VOC gets the verb", "B1", setkey("newvoc_has", "1")),
    ("the administrator test moves after the parse", "B2", sub("verb", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      stop sysmsg(2001)  ;* Command requires administrator privileges\n   end\n", "")),
    ("RUN is let in outside a job", "B3", sub("verb", "   if action = 'run' then\n      if not(in.job) then", "   if action = 'run' then\n      if 0 then")),
    ("any job may RUN", "B3", sub("verb", "in.job = (job[1, 7] = 'radmin-')", "in.job = (job # '')")),
    ("the definition is not consumed", "B4", sub("verb", "   void ospath(jobs.def, OS$DELETE)\n", "")),
    ("the password is given three times", "B5", sub("verb", "            data secret\n            data secret\n", "            data secret\n            data secret\n            data secret\n")),
    ("the password is kept until after the verb", "B5", sub("verb", "            secret = ''\n            execute run.sentence", "            execute run.sentence\n            secret = ''")),
    ("the queue is not cleared", "B5", sub("verb", "            run.rc = @system.return.code\n            cleardata\n", "            run.rc = @system.return.code\n")),
    ("the password is audited", "B5", sub("verb", "   void kernel(K$AUDIT, 'remote.sdsys run verb=' : run.verb : ' status=' : run.rc)", "   void kernel(K$AUDIT, 'remote.sdsys run verb=' : run.verb : ' status=' : run.rc : secret)")),
    ("RUN runs another verb", "B6", sub("verb", "or run.verb = 'remote.api')", "or run.verb = 'remote.api' or run.verb = 'logto')")),
    ("RUN takes sdsys as a word", "B6", sub("verb", "      if w = 'sdsys' or w = 'sdradmin' or w = 'shared' then run.ok = @false\n", "")),
    ("RUN does not run remote.ssh", "B6", sub("verb", " or run.verb = 'remote.ssh' or run.verb = 'remote.api')", " or run.verb = 'remote.api')")),
    ("RUN's remote.ssh takes any word", "B10", sub("verb", "and run.words<1> # 'on' and run.words<1> # 'off') then run.ok = @false", "and 0) then run.ok = @false")),
    ("RUN's remote.api takes two words", "B10", sub("verb", "      if dcount(run.words, @fm) > 1 or (run.words # '' and run.words<1> # 'on' and run.words<1> # 'local'", "      if 0 or (run.words # '' and run.words<1> # 'on' and run.words<1> # 'local'")),
    ("remote.api's restart is answered yes", "B10", sub("verb", "      case run.verb = 'remote.api'\n         data 'N'\n", "      case run.verb = 'remote.api'\n         data 'Y'\n")),
    ("remote.api's answer is left in the queue", "B10", sub("verb", "         data 'N'\n         execute run.sentence\n         run.rc = @system.return.code\n         cleardata\n", "         data 'N'\n         execute run.sentence\n         run.rc = @system.return.code\n")),
    ("remote.api runs with nothing queued", "B10", sub("verb", "      case run.verb = 'remote.api'\n         data 'N'\n", "      case run.verb = 'remote.api'\n")),
    ("ON is allowed in the job", "B7", sub("verb", "   if in.job then\n      @system.return.code = -ER$ARGS\n      stop sysmsg(12847, 'remote.sdsys on')", "   if 0 then\n      @system.return.code = -ER$ARGS\n      stop sysmsg(12847, 'remote.sdsys on')")),
    ("SDRADMIN is made with ssh and API", "B7", sub("verb", "   settings<CA$ROUTE.API> = 0\n", "   settings<CA$ROUTE.API> = 1\n")),
    ("SDRADMIN is made with a shell", "B7", sub("verb", "   settings<CA$START> = 'terminal'\n", "   settings<CA$START> = 'terminal'\n   settings<CA$OS.SH> = 1\n")),
    ("OFF leaves the sessions", "B8", sub("verb", "         z = logout(users<i, K$USERS.UID> + 0, @false)\n", "")),
    ("the job asks the console's helper", "B9", sub("verb", "   if in.job then\n      os.execute hcmd", "   if 0 then\n      os.execute hcmd")),
    ("ON asks for SDSYS's password again", "B11", sub("verb", "   helper.args = '-On'\n   gosub run.helper\n   gosub show.helper\n", "   helper.args = '-On'\n   gosub run.helper\n   display 'Windows password for SDSYS: ' :\n   input sdsys.pw HIDDEN\n   gosub show.helper\n")),
    ("anybody may send", "R1", sub("radmin", " or env('SSH_CONNECTION') = '' or kernel(K$ADMINISTRATOR, -1) then", " or kernel(K$ADMINISTRATOR, -1) then")),
    ("a word is not checked", "R2", sub("radmin", "convert('abcdefghijklmnopqrstuvwxyz0123456789._-', '', w) # ''", "0")),
    ("ON is sent", "R2", sub("radmin", "         if words<1> = 'on' then stop sysmsg(12847, 'remote.sdsys on')", "         null")),
    ("the password is not checked for strength", "R3", sub("radmin", "      if not(pw_complex(pw1)) then", "      if 0 then")),
    ("the password goes on the client's command line", "R3", sub("radmin", "' -Request ' : q : ps.dir : @ds : req.id : q", "' -Request ' : q : ps.dir : @ds : req.id : q : ' ' : pw1")),
    ("the password is audited in the session", "R3", sub("radmin", "' status=' : job.rc)", "' status=' : job.rc : pw1)")),
    ("the request file is left", "R4", sub("radmin", "   delete ps.f, req.id   ;*", "   null   ;*")),
    ("a refusal is not shown", "R5", sub("radmin", "            crt sysmsg(12838, l[9, 999])", "            null")),
    ("the state file is believed when it says anything", "O1", sub("open", "if trim(state.rec<1>) = 'on' then open = @true", "open = @true")),
    ("the gate is inside case 1 only", "L1", sub("login", "   if initial.account = 'sdradmin' then\n      radmin.why = ''", "   if 0 then\n      radmin.why = ''")),
    ("an elevated SDRADMIN lands", "L1", sub("login", "         case kernel(K$OS.ELEVATED, 0)\n            radmin.why = 'SDRADMIN in an elevated session'\n", "")),
    ("a local SDRADMIN lands", "L1", sub("login", "         case env('SSH_CONNECTION') = ''\n            radmin.why = 'SDRADMIN not over ssh'\n", "")),
    ("SDRADMIN lands while remote administration is shut", "L1", sub("login", "         case not(radmin_open(0))\n            radmin.why = 'remote administration is off'\n", "")),
    ("the remote session keeps OS.EXECUTE", "L2", sub("login", "acc.rec<ACC$OS.EXEC> = '' ; ", "")),
    ("the remote session keeps shared read", "L2", sub("login", "acc.rec<ACC$SHARED.READ> = 'no'", "acc.rec<ACC$SHARED.READ> = ''")),
    ("the remote session sends remote.api nowhere", "R6", sub("radmin", "      case verb = 'remote.ssh' or verb = 'remote.api'", "      case verb = 'remote.ssh'")),
    ("LOGIN points only the five names", "L3", sub("login", "      radmin.names := @fm : 'remote.ssh' : @fm : 'remote.api'\n", "")),
    ("the VOC names point elsewhere", "L3", sub("login", "radmin.rec = 'V' : @fm : 'CA' : @fm : '$radmin'", "radmin.rec = 'V' : @fm : 'CA' : @fm : '$createa'")),
    ("the session is not announced", "L4", sub("login", "         display sysmsg(12800, radmin.from)", "         null")),
    ("SDRADMIN may LOGTO", "C1", sub("cproc", "   if upcase(@logname) = 'SDRADMIN' then\n      display sysmsg(12847, 'logto')", "   if 0 then\n      display sysmsg(12847, 'logto')")),
    ("MODIFY.ACCOUNT reaches SDRADMIN", "A1", sub("modifya", "   if acc.name = 'SDRADMIN' then\n      stop sysmsg(12704)", "   if 0 then\n      stop sysmsg(12704)")),
    ("DELETE.ACCOUNT takes SDRADMIN while open", "A1", sub("delacc", "      if radmin_open(0) then stop sysmsg(12704)", "      null")),
    ("a message is missing", "M1", setkey("msg12838", "")),
    ("the installer asks about remote administration again", "I1", sub("iss", "  PythonPage.Values[0] := False;\nend;", "  PythonPage.Values[0] := False;\n  RemoteAdminPage := CreateInputOptionPage(PythonPage.ID, 'Remote administration', '', '', False, False);\nend;")),
    ("Setup hands the finishing window -RemoteAdmin again", "I1", sub("iss", "          ' -AttachCode ' + IntToStr(AttachCode);\n", "          ' -AttachCode ' + IntToStr(AttachCode) + ' -RemoteAdmin';\n")),
    ("the uninstaller leaves remote administration", "I1", sub("iss", "    RemoveScheduledJobs;\n    RemoveRemoteAdmin;\n", "    RemoveScheduledJobs;\n")),
    ("the finishing window opens remote administration again", "I2", sub("finish", "# 13 Nov 26 - RELEASE_1.1 282: the install no longer opens remote administration", "if ($RemoteAdmin) { $null = 'REMOTE.SDSYS' }\n# 13 Nov 26 - RELEASE_1.1 282: the install no longer opens remote administration")),
    ("a script does not ship", "I3", sub("stage", "'remote-admin.ps1', 'sd-radmin.ps1', 'sd-radmin-client.ps1',", "'remote-admin.ps1', 'sd-radmin.ps1',")),
]


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:200]))
        bad += 0 if ok else 1
    return bad


def selftest(raw):
    base = [r[0] for r in checks(raw) if not r[2]]
    if base:
        print("selftest: the unchanged tree fails %s, so a mutant's own failure cannot be told from the tree's; run the plain check first" % base)
        return 1
    holes = 0
    for name, want, mut in MUTANTS:
        try:
            m = mut(raw)
        except KeyError as exc:
            print("  [FAIL] selftest: %s  <- %s" % (name, exc))
            holes += 1
            continue
        failed = sorted({r[0] for r in checks(m) if not r[2]})
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        holes += 0 if hit else 1
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS), holes))
    return 1 if holes else 0


def main(argv):
    raw = load()
    print("test-remotesdsys-units: tree %s" % SDSYS)
    if not raw["verb"] or not raw["login"]:
        print("test-remotesdsys-units: CANNOT RUN - %s or %s is not there" % (FILES["verb"], FILES["login"]))
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-remotesdsys-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
