#!/usr/bin/env python3
"""test-toolconfig-units.py - TOOL.CONFIG and SET.CONFIG held to the C they describe (Windows RELEASE_1.1 218).

    python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-toolconfig-units.py [--selftest]

Ordinary unelevated prompt; no install, no SD.  Exit 0 all passed, 1 a check failed, 2 a file is missing.

The Windows carry (10 Nov 2026) of Linux's test-toolconfig-units.py (S.75 A6), cut to the checks whose failure would be silent
on this port:
  T1  sdsys/config.table names exactly the parameters gplsrc/config.c accepts in [sd] (STARTUP is refused by name here);
  T2  every range in the table is config.c's rangecheck, and every write=yes row is range-checked;
  T3  every default the table states for a number is the value config.c sets before it reads the file;
  T4  every parameter but BACKUPDIR and SDSYS is readable with CONFIG() (op_config.c), and the buffer takes the longest name;
  T5  the page reads the table and the file the kernel read (K$INIPATH), runs only set.config, and writes one audit line;
  T6  the verb: administrator only, its messages 12936-12942 exist, it runs sd-confset.ps1 through !ps_script_out, anchors on the
      helper's own success line, and audits once on both paths;
  T7  the VOC entries, the help topic, the staging (config.table shipped, sd-confset.ps1 installed) and the installer's lock;
  T8  the guide (SDCore4WindowsDocs Administrator 07) describes the page and the verb, when that checkout is beside this one.
--selftest breaks a copy of each subject in memory and requires the check that guards it to go red.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
DOCS = os.environ.get("SD_DOCS_CHECKOUT") or os.path.join(SD64, "..", "..", "..", "SDCore4WindowsDocs")

FILES = {
    "table": "sdsys/config.table",
    "page": "sdsys/gpl.bp/tool_config",
    "verb": "sdsys/gpl.bp/setconfig",
    "vocpage": "sdsys/voc_template/tool.config",
    "vocverb": "sdsys/voc_template/set.config",
    "help": "sdsys/helptext/tool.config.page",
    "configc": "gplsrc/config.c",
    "opconfig": "gplsrc/op_config.c",
    "stage": "gplbld/stage.py",
    "iss": "gplbld/sd.iss",
    "helper": "gplbld/sd-confset.ps1",
}
HEADERS = ["gplsrc/config.h", "gplsrc/dh.h", "gplsrc/sddefs.h", "gplsrc/sysseg.h"]
MSGS = list(range(12936, 12943))
REFUSED = {"STARTUP"}
UNREADABLE = {"BACKUPDIR", "SDSYS"}


def read(rel):
    with open(os.path.join(SD64, rel), "rb") as f:
        return f.read().decode("ascii", "replace")


def load():
    raw = {}
    for k, rel in FILES.items():
        p = os.path.join(SD64, rel)
        print("  %-8s %s" % (k, p))
        if not os.path.exists(p):
            print("test-toolconfig-units: %s is missing" % p)
            sys.exit(2)
        raw[k] = read(rel)
    raw["headers"] = "\n".join(read(h) for h in HEADERS)
    for n in MSGS:
        p = os.path.join(SD64, "sdsys", "messages", str(n))
        raw["msg%d" % n] = read("sdsys/messages/%d" % n) if os.path.exists(p) else None
    doc = os.path.join(DOCS, "Administrator", "markdown", "07-sd-admin-configuration.md")
    print("  doc      %s" % os.path.abspath(doc))
    raw["doc"] = open(doc, "rb").read().decode("utf-8", "replace") if os.path.exists(doc) else None
    return raw


def table_rows(t):
    return [ln.split("|") for ln in t.splitlines() if ln and not ln.startswith("#")]


def sd_block(c):
    a = c.index('if (!strcmp(section, "SD")) {')
    b = c.index("Unrecognized configuration parameter", a) if "Unrecognized configuration parameter" in c[a:] else c.index("Unrecognised configuration parameter", a)
    return c[a:b]


def parser_keys(c):
    return sorted(set(re.findall(r'(?:sscanf\(rec, |strncmp\(rec, )"([A-Z0-9]+)=', sd_block(c))))


def macro(h, name):
    m = re.search(r"#define %s (\d+)" % name, h)
    return int(m.group(1)) if m else None


def c_ranges(c, h):
    out = {}
    for k, lo, hi in re.findall(r'rangecheck\("([A-Z0-9]+)", [^,]+, ([A-Z_0-9]+), ([A-Z_0-9]+), errmsg\)', c):
        lo = int(lo) if lo.isdigit() else macro(h, lo)
        hi = int(hi) if hi.isdigit() else macro(h, hi)
        out[k] = (lo, hi)
    return out


NOCOMMENT = {"numfiles": "NUMFILES", "numlocks": "NUMLOCKS", "maxidlen": "MAXIDLEN", "max_users": "NUMUSERS"}


def c_defaults(c, h):
    out = {}
    for v, k in re.findall(r"pcfg\.\w+ = (-?[0-9.]+);\s*/\* ([A-Z0-9_]+):", c):
        out[k] = v
    for v, k in re.findall(r"cfg->\w+ = (-?[0-9.]+);\s*/\* ([A-Z0-9_]+):", c):
        out[k] = v
    for f, v in re.findall(r"cfg->(\w+) = (\d+);", c[:c.index("while")] if "while" in c else c):
        if f in NOCOMMENT:
            out.setdefault(NOCOMMENT[f], v)
    if "cfg->userpool = MIN_HI_USER_NO;" in c:
        out["USERPOOL"] = str(macro(h, "MIN_HI_USER_NO"))
    if "cfg->fds_limit = SHRT_MAX;" in c:
        out["FDS"] = "32767"
    if "SORTMEM" in out:
        out["SORTMEM"] = str(int(out["SORTMEM"]) // 1024)
    for f, k in (("grpdir", "GRPDIR"), ("usrdir", "USRDIR")):
        m = re.search(r'strncpy\(pcfg\.%s,"((?:[^"\\]|\\.)*)"' % f, c)
        if m:
            out[k] = m.group(1).replace("\\\\", "\\")
    return out


def readable(o):
    """The names CONFIG() answers: op_config() only, up to op_pconfig() (which sets the session's copy and names some again)."""
    a = o.index("void op_config()")
    b = o.index("void op_pconfig()") if "void op_pconfig()" in o else len(o)
    return sorted(set(re.findall(r'!strcmp\(param, "([A-Z0-9]+)"\)', o[a:b])))


def strip_bas(s):
    return "\n".join(ln.split(";*")[0] for ln in s.splitlines() if not ln.lstrip().startswith("*"))


def run(raw, quiet=False):
    res = {}

    def ck(cid, what, ok, detail=""):
        res[cid] = bool(ok)
        if not quiet:
            print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", cid, what, ("" if ok else "  -- " + str(detail))))

    rows = table_rows(raw["table"])
    tk = [r[0] for r in rows]
    good = all(len(r) == 10 for r in rows)
    ck("T0", "the table has rows of ten fields (%d rows) - refuses the null case" % len(rows), len(rows) > 40 and good)
    if not good:
        return res
    pk = parser_keys(raw["configc"])
    want = sorted(set(pk) - REFUSED)
    ck("T1", "the table names exactly config.c's [sd] parameters (%d), none it refuses" % len(want),
       sorted(tk) == want and tk == sorted(tk) and REFUSED <= set(pk) and "STARTUP is no longer supported" in raw["configc"],
       (sorted(set(tk) ^ set(want)), tk == sorted(tk)))
    rng = c_ranges(raw["configc"], raw["headers"])
    bad = [r[0] for r in rows if ((r[3], r[4]) != ("", "") or r[0] in rng) and (r[0] not in rng or (int(r[3]), int(r[4])) != rng[r[0]])]
    nyes = [r[0] for r in rows if r[8] == "yes" and r[0] not in rng]
    ck("T2", "every range is config.c's rangecheck (%d) and every write=yes row is range-checked" % len(rng),
       len(rng) > 15 and not bad and not nyes and [r[0] for r in rows if r[8] == "yes"].__len__() == 14, (bad, nyes))
    dfl = c_defaults(raw["configc"], raw["headers"])
    checked, wrong = 0, []
    for r in rows:
        if r[0] in dfl and r[2] != "":
            checked += 1
            a, b = r[2], dfl[r[0]]
            same = (float(a) == float(b)) if r[1] in ("int", "flag", "bits", "float") else (a == b)
            if not same:
                wrong.append((r[0], a, b))
    ck("T3", "every default the table states is config.c's (%d compared)" % checked, checked >= 25 and not wrong, wrong)
    rd = readable(raw["opconfig"])
    missing = sorted(set(tk) - set(rd) - UNREADABLE)
    longest = max(len(k) for k in tk)
    m = re.search(r"char param\[(\d+) \+ 1\];[^\n]*\n(?:.*\n){0,40}?.*k_get_c_string\(descr, param, (\d+)\) < 1", raw["opconfig"])
    ck("T4", "every parameter but BACKUPDIR and SDSYS is readable with CONFIG(), whose buffer takes %d characters" % longest,
       not missing and not (UNREADABLE & set(rd)) and m and int(m.group(1)) >= longest and int(m.group(2)) >= longest, (missing, m and m.groups()))

    pg = strip_bas(raw["page"])
    ck("T5", "the page: the table from @sdsys, the file from K$INIPATH, set.config the one command, one audit line, the help topic",
       "openseq @sdsys : @ds : 'config.table' readonly to tf then" in pg and "conf.path = kernel(K$INIPATH, 0)" in pg
       and "/etc/" not in pg and "root helper" not in pg and "allow = 'set.config'" in pg and pg.count("K$AUDIT") == 1
       and "call $tk_run(allow, sent, out, stat, err)" in pg and pg.count("$tk_run") == 1
       and "if stat = 0 and ('S' : trim(now.f)) = ('S' : nv) then" in pg and "'tool.config.page'" in pg)
    vb = strip_bas(raw["verb"])
    used = sorted(set(int(n) for n in re.findall(r"sysmsg\((\d+)", vb)))
    ck("T6", "the verb: administrator only, messages %d-%d present, sd-confset.ps1 through !ps_script_out, success is the helper's own line, one audit"
       % (MSGS[0], MSGS[-1]),
       "if not(kernel(K$ADMINISTRATOR, -1)) then" in vb and used == [2001] + MSGS and all(raw["msg%d" % n] for n in MSGS)
       and "kernel(K$WINPATH, '/sd-confset.ps1')" in vb and "ps_script_out(script, @true)" in vb
       and "anchor = 'SD-CONFSET OK ' : pname : ' ' : pval : ' '" in vb and "if stat # 0 or not(done) or why # '' then" in vb
       and vb.count("K$AUDIT") == 1 and vb.count("gosub write.audit") == 2
       and "void kernel(K$AUDIT, 'set.config key=' : downcase(pname) : ' value=' : pval : ' status=' : st)" in vb
       and "os.execute" not in vb.lower(), used)
    hp = raw["help"]
    ck("T7", "VOC entries, help topic, staging and the installer's lock",
       raw["vocpage"] == "V\nCA\n$tool_config\n" and raw["vocverb"] == "V\nCA\n$setconfig\n"
       and hp.splitlines()[:2] == ["The configuration", "administrator-07-sd-admin-configuration"]
       and all(s in hp for s in ("E changes the parameter under the cursor", "set.config", "sd.conf.bak", "Only 14 tuning parameters", "by hand"))
       and "/etc/" not in hp and "root" not in hp
       and "('config.table'," in raw["stage"] and "'sd-confset.ps1'," in raw["stage"]
       and "LockOsUsersPath(Ps, Script, ConfTable, Code)" in raw["iss"] and "{#DataDir}\\sdsys\\config.table" in raw["iss"])
    if raw["doc"] is None:
        print("  [SKIP] T8 the guide: no SDCore4WindowsDocs checkout beside this one")
    else:
        d = raw["doc"]
        ck("T8", "the guide describes tool.config, set.config, the 14, the .bak and the status words",
           all(s in d for s in ("tool.config", "set.config cleanup 600", "sd.conf.bak", "set.config key=cleanup value=600 status=ok", "`Change`"))
           and all(("`%s`" % k) in d for k in [r[0] for r in rows if r[8] == "yes"]) and "/etc/sd.conf" not in d)
    return res


def sub(raw, key, old, new, count=1):
    r = dict(raw)
    if r[key] is None or old not in r[key]:
        return None
    r[key] = r[key].replace(old, new, count)
    return r


def selftest(raw):
    mutants = [
        ("a parameter missing from the table", "T1", sub(raw, "table", "CLEANUP|int|300|30|3600|restart|live|", "XCLEANUP|int|300|30|3600|restart|live|")),
        ("STARTUP listed as a parameter", "T1", sub(raw, "table", "APIPORT|", "STARTUP|text||||restart|live|x|no|y\nAPIPORT|")),
        ("a range that is not config.c's", "T2", sub(raw, "table", "GRPSIZE|int|1|1|8|", "GRPSIZE|int|1|1|16|")),
        ("a write=yes row with no rangecheck", "T2", sub(raw, "table", "|session|live|How many compiled programs one session keeps in memory at once; 0 sets no limit.|no|",
                                                          "|session|live|How many compiled programs one session keeps in memory at once; 0 sets no limit.|yes|")),
        ("a default that is not config.c's", "T3", sub(raw, "table", "GRPSIZE|int|1|", "GRPSIZE|int|4|")),
        ("Linux's account directory as the default", "T3", sub(raw, "table", "USRDIR|path|C:\\ProgramData\\SD\\user_accounts|", "USRDIR|path|/home/sd/user_accounts|")),
        ("CONFIG() loses a name", "T4", sub(raw, "opconfig", '!strcmp(param, "NETREPLY")', '!strcmp(param, "NETREPLX")')),
        ("CONFIG()'s buffer back to 8", "T4", sub(raw, "opconfig", "char param[16 + 1];", "char param[8 + 1];")),
        ("the page reads /etc/sd.conf", "T5", sub(raw, "page", "conf.path = kernel(K$INIPATH, 0)", "conf.path = '/etc/sd.conf'")),
        ("the page may run another command", "T5", sub(raw, "page", "allow = 'set.config'", "allow = 'set.config sh'")),
        ("the page claims success on the status alone", "T5", sub(raw, "page", "if stat = 0 and ('S' : trim(now.f)) = ('S' : nv) then", "if stat = 0 then")),
        ("the verb drops the administrator check", "T6", sub(raw, "verb", "if not(kernel(K$ADMINISTRATOR, -1)) then", "if @false then")),
        ("the verb trusts the status alone", "T6", sub(raw, "verb", "if stat # 0 or not(done) or why # '' then", "if stat # 0 then")),
        ("the verb anchors on its own argument", "T6", sub(raw, "verb", "anchor = 'SD-CONFSET OK ' : pname : ' ' : pval : ' '", "anchor = pname")),
        ("a message missing", "T6", dict(raw, msg12940=None)),
        ("the verb audits only success", "T6", sub(raw, "verb", "      st = 'refused'\n      gosub write.audit\n", "      st = 'refused'\n")),
        ("the help topic names the root helper", "T7", sub(raw, "help", "SDSYS's elevated helper", "The root helper")),
        ("config.table not shipped", "T7", sub(raw, "stage", "('config.table',", "('config.tablex',")),
        ("config.table not locked", "T7", sub(raw, "iss", "LockOsUsersPath(Ps, Script, ConfTable, Code)", "LockOsUsersPath(Ps, Script, VocRm, Code)")),
    ]
    if raw["doc"] is not None:
        mutants.append(("the guide loses the .bak", "T8", sub(raw, "doc", "sd.conf.bak", "sd.conf.old", -1)))
        mutants.append(("the guide keeps Linux's path", "T8", sub(raw, "doc", "`C:\\ProgramData\\SD\\sd.conf`", "`/etc/sd.conf`")))
    base = run(raw, quiet=True)
    if not all(base.values()):
        print("SELFTEST: the real files do not pass; fix them first")
        return 1
    fails = 0
    for what, cid, m in mutants:
        if m is None:
            print("  [FAIL] mutant '%s': its text is not in the file, so it tests nothing" % what)
            fails += 1
            continue
        r = run(m, quiet=True)
        caught = not r.get(cid, True)
        print("  [%s] mutant '%s' turns %s red" % ("PASS" if caught else "FAIL", what, cid))
        fails += 0 if caught else 1
    print("SELFTEST: %d of %d mutants caught" % (len(mutants) - fails, len(mutants)))
    return 1 if fails else 0


def main():
    print("test-toolconfig-units: subjects under %s" % SD64)
    raw = load()
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest(raw))
    res = run(raw)
    if not res:
        print("test-toolconfig-units: VOID - no check ran")
        sys.exit(1)
    bad = [k for k, v in res.items() if not v]
    if bad:
        print("test-toolconfig-units: FAILED - %s" % ", ".join(bad))
        sys.exit(1)
    print("test-toolconfig-units: PASSED - %d checks" % len(res))
    sys.exit(0)


if __name__ == "__main__":
    main()
