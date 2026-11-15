#!/usr/bin/env python3
"""test-xfergates-units.py - S.242 stage 1: the two switches of file transfer over the ssh login, read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-xfergates-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-xfergates-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

THE RULE (owner, 14 Nov 2026: file transfer is in this release and, like every door, DELIVERED OFF).  Two switches, both off:
  - the system's, XFER in sd.conf: config.c sets 0 before it reads the file, reads XFER=n and refuses anything but 0 or 1; CONFIG() reads it and
    PCONFIG does not set it (the transfer server reads sd.conf itself);
  - the account's, register field 22 ACC$XFER (fields 20 and 21 are Solo's MCP fields): blank means no; MODIFY.ACCOUNT XFER-ON / XFER-OFF and
    CREATE.ACCOUNT XFER-ON write it, for a USER account only (15075 refuses a group or other account BEFORE anything is changed or made); the
    result line is 15074; a backup's manifest carries it as "xfer: 1|0" and RESTORE.ACCOUNT gives it back only on an explicit 1.
The limits XFERFILE / XFERSLOT / XFERWAIT / XFERIDLE / XFERMAX / XFERKIND have the owner's defaults (10 MB, 100 MB, 60 minutes) in config.c and
config.table alike.

***IT READS THE SOURCE AS TEXT.***  It cannot say that MODIFY.ACCOUNT writes the field or refuses a group account at run time (a sandbox has
fixture accounts for that: sandbox-tool-gates.py's helper path), nor that anything honours the switches: nothing does until stage 3, the
transfer server.  --selftest requires each mutation to be caught and to match its text exactly once.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.join(HERE, os.pardir)
FILES = {
    "keys": "sdsys/syscom/keys.h",
    "createacc": "sdsys/syscom/createacc.h",
    "modifya": "sdsys/gpl.bp/modifya",
    "createa": "sdsys/gpl.bp/createa",
    "create_account": "sdsys/gpl.bp/create_account",
    "acc_os_info": "sdsys/gpl.bp/acc_os_info",
    "restorea": "sdsys/gpl.bp/restorea",
    "config_c": "gplsrc/config.c",
    "config_h": "gplsrc/config.h",
    "op_config": "gplsrc/op_config.c",
    "table": "sdsys/config.table",
    "m14074": "sdsys/messages/15074",
    "m14075": "sdsys/messages/15075",
}

# name, default, min, max (config.c and config.table must agree)
LIMITS = [("XFER", "0", "0", "1"), ("XFERFILE", "10240", "1", "1048576"), ("XFERSLOT", "102400", "1", "4194304"),
          ("XFERWAIT", "600", "10", "3600"), ("XFERIDLE", "120", "10", "3600"), ("XFERMAX", "3600", "0", "86400")]


def basic(src):
    """A BASIC program with its comment lines and ;* tails taken out."""
    return "\n".join(re.sub(r"\s*;\*.*$", "", ln) for ln in src.split("\n") if not ln.lstrip().startswith("*"))


def ccode(src):
    return re.sub(r"/\*.*?\*/", "", src, flags=re.S)


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    keys = basic(s["keys"])
    fields = {m.group(1): int(m.group(2)) for m in re.finditer(r"\$define (ACC\$[A-Z.]+)\s+(\d+)", keys)}
    ck("X1 keys.h defines ACC$XFER as field 22, no other ACC$ field is 22, and none of Core's takes Solo's 20 or 21",
       fields.get("ACC$XFER") == 22 and sum(1 for v in fields.values() if v == 22) == 1 and not any(v in (20, 21) for v in fields.values()),
       repr({k: v for k, v in fields.items() if v >= 19}))
    ca = basic(s["createacc"])
    ck("X2 createacc.h defines CA$XFER as 45, and no other CA$ setting is 45",
       re.search(r"\$define CA\$XFER\s+45\b", ca) and len(re.findall(r"\$define CA\$[A-Z.]+\s+45\b", ca)) == 1)

    m = basic(s["modifya"])
    wa = re.search(r"word\.arr = convert\(',', @fm, '([^']*)'\)", m)
    sa = re.search(r"slot\.arr = convert\(',', @fm, '([^']*)'\)", m)
    words = wa.group(1).split(",") if wa else []
    slots = sa.group(1).split(",") if sa else []
    pair = [slots[words.index(w)] if w in words and len(slots) == len(words) else None for w in ("XFER-ON", "XFER-OFF")]
    ck("X3 modify.account knows XFER-ON and XFER-OFF, in one slot of their own (XF), so the two refuse each other",
       pair == ["XF", "XF"] and slots.count("XF") == 2, "%s" % pair)
    # 15 Nov 26 Windows port (RELEASE_1.1 299): Windows' do.action is "case upcase(action) = ..." with one statement a line (its RECOVERY-ON shape);
    # the check reads the same three steps in either layout.
    def sets(word, want):
        return re.search(r"case (?:upcase\()?action\)? = '%s'\s*\n\s*os\.field = ACC\$XFER\s*(?:;|\n)\s*os\.want\s*= @%s\s*\n\s*gosub os\.set" % (word, want), m) is not None
    ck("X4 ...each sets ACC$XFER through os.set, on and off",
       sets("XFER-ON", "true") and sets("XFER-OFF", "false"))
    osset = m[m.find("\nos.set:\n"):]
    head = osset[:osset.find("readu acc.new")]
    excl = re.search(r"if group\.name\[1,4\] # 'sdu_'([^\n]*) then", head)
    ck("X5 ...os.set refuses it for any account that is not a user account (ACC$XFER is not among the fields a group may take), with 15075, before the register is read for update",
       excl and "ACC$XFER" not in excl.group(1) and "if os.field = ACC$XFER then\n         crt sysmsg(15075, acc.name)" in head.replace("end else if", "if"),
       excl.group(1) if excl else "no user-account test")
    ck("X6 ...and says the result with 15074, from the field it wrote", "crt sysmsg(15074, acc.name, if upcase(trim(acc.new<ACC$XFER>)) = 'YES' then 'yes' else 'no')" in osset)
    ck("X7 ...and the usage and the error list name both words", "modify.account <account> xfer-on | xfer-off" in m and "xfer-on, xfer-off" in m)

    c = basic(s["createa"])
    more = c[c.find("\nmore.args:\n"):]
    ck("X8 create.account takes XFER-ON as CA$XFER = 1, and not XFER-OFF (it restates the default)",
       "case upcase(token) = 'XFER-ON'\n            settings<CA$XFER> = 1" in more and "XFER-OFF" not in more)
    ck("X9 ...and its audit line names it", "if settings<CA$XFER> = 1 then gates<-1> = 'xfer-on'" in c)

    a = basic(s["create_account"])
    ck("X10 !create_account takes the request only from exactly 1", "xfer.want = (settings<CA$XFER> = 1)" in a)
    grp = a[a.find("case acc.type = 'GROUP'"):a.find("case acc.type = 'OTHER'")]
    oth = a[a.find("case acc.type = 'OTHER'"):]
    oth = oth[:oth.find("pathname = trim(settings<CA$PATH>)")]
    refusal = "if xfer.want then\n       @system.return.code = -ER$ARGS\n       err = 15075:@vm:acc.name\n       goto exit.create"
    ck("X11 ...refuses it for a group account and for an other account (15075) before anything is made", refusal in grp and refusal in oth and a.count(refusal) == 2)
    w = a.find("acc.rec<ACC$XFER> = if xfer.want then 'yes' else 'no'")
    ck("X12 ...writes the field for a user account, 'no' unless asked, and says it with 15074",
       w >= 0 and a.count("acc.rec<ACC$XFER> =") == 1 and "crt sysmsg(15074, acc.name, acc.rec<ACC$XFER>)" in a)

    ck("X13 the manifest carries xfer: 1 only when the field says yes", "info<-1> = 'xfer: ':(if upcase(trim(acc.rec<ACC$XFER>)) = 'YES' then 1 else 0)" in basic(s["acc_os_info"]))
    r = basic(s["restorea"])
    ck("X14 RESTORE.ACCOUNT reads the key and asks for xfer-on only on an explicit 1 (a manifest without it restores the account off)",
       "case sec.keys<s.idx,kp> = 'xfer'        ; m.xfer = kv" in r and "settings<CA$XFER> = (if m.xfer = '1' then 1 else '')" in r and "m.xfer = ''" in r)

    cc = ccode(s["config_c"])
    ck("X15 config.c sets XFER to 0 before it reads sd.conf (delivered off)", "pcfg.xfer = 0;" in cc and cc.find("pcfg.xfer = 0;") < cc.find('"XFER=%d"'))
    dflt_ok, rng_ok, read_ok = [], [], []
    for name, d, lo, hi in LIMITS:
        f = name.lower()
        dflt_ok.append(("pcfg.%s = %s;" % (f, d)) in cc)
        rng_ok.append(('rangecheck("%s", pcfg.%s, %s, %s, errmsg)' % (name, f, lo, hi)) in cc)
        read_ok.append(('sscanf(rec, "%s=%%d", &n) == 1)\n        pcfg.%s = n;' % (name, f)) in cc)
    ck("X16 config.c has the owner's defaults (10 MB, 100 MB, 60 minutes), reads each limit and range-checks it", all(dflt_ok) and all(rng_ok) and all(read_ok),
       "defaults %s ranges %s reads %s" % (dflt_ok, rng_ok, read_ok))
    ck("X17 XFERKIND is a bounded text, blank by default (any plain-text file)",
       "pcfg.xferkind[0] = '\\0';" in cc and "strncpy(pcfg.xferkind, rec + 9, sizeof(pcfg.xferkind) - 1);" in cc and "char xferkind[" in s["config_h"])
    oc = ccode(s["op_config"])
    getter = oc[:oc.find("pcfg.yearbase;")]
    setter = oc[oc.find("pcfg.yearbase;") + 1:]
    ck("X18 CONFIG() reads every one of them and PCONFIG sets none", all(('"%s"' % n) in getter for n, _, _, _ in LIMITS) and '"XFERKIND"' in getter and "XFER" not in setter)

    table = {ln.split("|")[0]: ln.split("|") for ln in s["table"].split("\n") if ln and not ln.startswith("#")}
    tab_ok = [(n in table and table[n][2:5] == [d, lo, hi] and table[n][8] == "no") for n, d, lo, hi in LIMITS]
    ck("X19 config.table has each limit with config.c's default and range, and none of them may be changed by the page (write no)",
       all(tab_ok) and "XFERKIND" in table and table["XFERKIND"][8] == "no", repr(tab_ok))

    ck("X20 the two messages exist and take the account (and 15074 the state)",
       "%1" in s["m14074"] and "%2" in s["m14074"] and "%1" in s["m14075"] and "%2" not in s["m14075"] and "nothing was changed" in s["m14075"])
    return rows


def load():
    out = {}
    for k, rel in FILES.items():
        p = os.path.join(SD, rel)
        if not os.path.isfile(p):
            print("CANNOT RUN - %s is missing" % p, file=sys.stderr)
            sys.exit(2)
        with open(p, encoding="latin-1") as f:
            out[k] = f.read()
    return out


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


MUTANTS = [
    ("modifya", "XFER-ON and XFER-OFF in different slots", ",RC,RC,XF,XF,", ",RC,RC,XF,XG,"),
    ("modifya", "XFER-ON clears the field", "case action = 'XFER-ON'\n         os.field = ACC$XFER ; os.want = @true", "case action = 'XFER-ON'\n         os.field = ACC$XFER ; os.want = @false"),
    ("modifya", "a group account may take it", "os.field # ACC$PINS then", "os.field # ACC$PINS and os.field # ACC$XFER then"),
    ("modifya", "the refusal says the recovery message", "crt sysmsg(15075, acc.name)", "crt sysmsg(12776, acc.name)"),
    ("createa", "XFER-OFF is also taken", "         case upcase(token) = 'XFER-ON'\n", "         case upcase(token) = 'XFER-OFF'\n            settings<CA$XFER> = ''\n         case upcase(token) = 'XFER-ON'\n"),
    ("create_account", "any non-blank value is a request", "xfer.want = (settings<CA$XFER> = 1)", "xfer.want = (settings<CA$XFER> # '')"),
    ("create_account", "an other account is not refused", "* 14 Nov 26 dm - S.242: nor file transfer (15075), as for a group account.\n     if xfer.want then", "* 14 Nov 26 dm - S.242: nor file transfer (15075), as for a group account.\n     if @false then"),
    ("create_account", "a new account starts on", "acc.rec<ACC$XFER> = if xfer.want then 'yes' else 'no'", "acc.rec<ACC$XFER> = 'yes'"),
    ("acc_os_info", "the manifest says 1 for a blank field", "if upcase(trim(acc.rec<ACC$XFER>)) = 'YES' then 1 else 0", "if upcase(trim(acc.rec<ACC$XFER>)) # 'NO' then 1 else 0"),
    ("restorea", "the restore forgets it", "settings<CA$XFER> = (if m.xfer = '1' then 1 else '')", "settings<CA$XFER> = ''"),
    ("keys", "the field takes Solo's 20", "$define ACC$XFER         22", "$define ACC$XFER         20"),
    ("config_c", "XFER is delivered on", "pcfg.xfer = 0;", "pcfg.xfer = 1;"),
    ("config_c", "XFER is not range-checked", '      !rangecheck("XFER", pcfg.xfer, 0, 1, errmsg) ||', ""),
    ("config_c", "the file limit is 100 MB", "pcfg.xferfile = 10240;", "pcfg.xferfile = 102400;"),
    ("op_config", "PCONFIG may set XFER", '  } else if (!strcmp(param, "YEARBASE")) {', '  } else if (!strcmp(param, "XFER")) {\n    pcfg.xfer = descr->data.value;\n  } else if (!strcmp(param, "YEARBASE")) {'),
    ("table", "the page may change XFER", "|no|A door: 1 opens file transfer", "|yes|A door: 1 opens file transfer"),
]


def selftest():
    s = load()
    if any(not ok for _, ok, _ in checks(s)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        report(checks(s))
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text once ---")
    for key, name, old, new in MUTANTS:
        if s[key].count(old) != 1:
            print("  [FAIL] %s: the text matches %d times in %s, not once" % (name, s[key].count(old), key))
            holes += 1
            continue
        t = dict(s)
        t[key] = s[key].replace(old, new)
        caught = [n.split()[0] for n, ok, _ in checks(t) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + ", ".join(caught[:3]) if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    print("%d mutants, %d not caught" % (len(MUTANTS), holes))
    return 1 if holes else 0


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    s = load()
    print("test-xfergates-units: the file transfer switches (S.242 stage 1), read from %s" % os.path.realpath(SD))
    for k, rel in FILES.items():
        print("  input %-15s %s (%d bytes)" % (k, rel, len(s[k])))
    rows = checks(s)
    bad = report(rows)
    print("%d passed, %d failed" % (len(rows) - bad, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
