#!/usr/bin/env python3
"""test-carry1557-units.py - the smaller items of Linux 1557e270 (S.62, audit round 1 passes 2 and 3) carried to SD Core for Windows, read off the source.

  python gplbld/test-carry1557-units.py
  python gplbld/test-carry1557-units.py --selftest

FREE CHECK: no install, no sd, no administrator.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

  C1  a phantom child that cannot start writes "phantom: cannot start a phantom ..." to the error log (log_message) and ENDS (_exit); it never
      calls k_error(), whose longjmp() left the forked child running as a second copy of the session
  C2  the API's TLS refusal is Linux's words: "API connection refused: cannot derive the TLS directory beside %s"
  C3  tool.remote's read.all and tool.config's read.report say 15150 ("Reading the settings (a few seconds)...", Linux's 14150) before the wait
  C4  CNAME refuses a new name that differs from the old only in case (compared folded) and asks all three spellings with no exemption: a
      case-only rename lost the record on the case-blind VOC
  C5  LOGTO: the ONE exemption from the suspended test is an internal-mode session holding the administrator flag, and it comes first; the
      suspended test refuses everyone else (10107, reason=suspended) before the group test
  C6  backup.account, restore.account, settings.report and tool.jobs have Linux's VOC descriptions (tool.jobs: the Task Scheduler for systemd)
It cannot say any of it runs: that is an install's.  --selftest requires each mutation to be caught and to match its text exactly once.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.dirname(HERE)
FILES = {
    "kernel": "gplsrc/op_kernel.c",
    "linuxio": "gplsrc/linuxio.c",
    "remote": "sdsys/gpl.bp/tool_remote",
    "config": "sdsys/gpl.bp/tool_config",
    "m15150": "sdsys/messages/15150",
    "cname": "sdsys/gpl.bp/cname",
    "cproc": "sdsys/gpl.bp/cproc",
    "vbackup": "sdsys/voc_template/backup.account",
    "vrestore": "sdsys/voc_template/restore.account",
    "vreport": "sdsys/voc_template/settings.report",
    "vjobs": "sdsys/voc_template/tool.jobs",
}


def ccode(src):
    s = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"(?m)//.*$", "", s)


def basic(src):
    return "\n".join(re.sub(r"\s*;\*.*$", "", ln) for ln in src.split("\n") if not ln.lstrip().startswith("*"))


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    k = ccode(s["kernel"])
    ph = k[k.find("void op_phantom()"):]
    child = ph[ph.find("if (cpid == 0) {"):ph.find("} else if (cpid == -1) {")]
    ck("C1 a phantom child that cannot start says why in the error log and ends; it calls no k_error()",
       child != "" and "k_error(" not in child and child.count("_exit(1);") == 3 and child.count("log_message(") == 4
       and 'snprintf(phantom_msg, sizeof(phantom_msg), "phantom: cannot start a phantom from %s - %s", path, strerror(errno));' in child)
    ck("C2 the TLS refusal says what api_tls_dir() does, in Linux's words",
       'syslog(LOG_ERR, "API connection refused: cannot derive the TLS directory beside %s",' in ccode(s["linuxio"]) and "no usable data directory" not in ccode(s["linuxio"]))
    r = basic(s["remote"])
    ra = r[r.find("\nread.all:"):]
    c = basic(s["config"])
    rr = c[c.find("\nread.report:"):]
    ck("C3 tool.remote and tool.config say 15150 on the status line before the wait",
       s["m15150"].strip() == "Reading the settings (a few seconds)..." and 0 <= ra.find("msg = sysmsg(15150)") < ra.find("call $tk_frame(ctx, keys, panes<view>, msg)")
       and 0 <= rr.find("msg = sysmsg(15150)") < rr.find("call !settings_os(os.lines, rerr)"))
    cn = basic(s["cname"])
    ck("C4 CNAME refuses a case-only rename (folded comparison) and asks every spelling of the new name with no exemption",
       "if new.file.name = downcase(old.file.name) then\n      stop sysmsg(6151, new.file.name)" in cn
       and "for clash.i = 1 to 3\n      readvu s from voc.f, clash.ids<clash.i>, 0 then\n         stop sysmsg(6151, clash.ids<clash.i>)" in cn
       and "# old.file.name then" not in cn)
    cp = basic(s["cproc"])
    la = cp[cp.find("\nlogto.authorised:"):]
    ex = la.find("if kernel(K$INTERNAL,-1) and kernel(K$ADMINISTRATOR,-1) then\n      logto.ok = @true\n      return")
    su = la.find("if upcase(trim(acc.record<ACC$SUSPENDED>, ' ', 'B')) = 'SUSPENDED' then\n      display sysmsg(10107, new.account)")
    gr = la.find("if not(is_grp_member(@logname,acc.record<ACC$GROUP>)) then")
    ck("C5 LOGTO: the internal administrator session is the one exemption, then the suspended refusal for everyone, then the group",
       0 <= ex < su < gr and la[:su].count("logto.ok = @true") == 1, "%s" % [ex, su, gr])
    want = {"vbackup": "Verb to back up accounts to a zip file (administrator)", "vrestore": "Verb to restore an account from a backup zip file (administrator)",
            "vreport": "Verb to write a reference report of the system's settings (administrator)",
            "vjobs": "Verb - Scheduled jobs: the administrator's own jobs that the Task Scheduler runs, and the commands each account may run from the command line (administrator)"}
    bad = [k2 for k2, t in want.items() if s[k2].split("\n")[0] != t or s[k2].split("\n")[1] != "CA"]
    ck("C6 the four VOC descriptions are Linux's (the Task Scheduler for systemd)", not bad, "%s" % bad)
    return rows


def load():
    out = {}
    for k, rel in FILES.items():
        p = os.path.join(SD, rel)
        if not os.path.isfile(p):
            print("test-carry1557-units: CANNOT RUN - %s is missing" % p, file=sys.stderr)
            sys.exit(2)
        with open(p, encoding="latin-1", newline="") as f:
            out[k] = f.read().replace("\r\n", "\n")
    return out


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


MUTANTS = [
    ("kernel", "the exec failure goes back to k_error", '      log_message(phantom_msg);\n', '      k_error(phantom_msg);\n'),
    ("kernel", "the child does not end after a long path", '      log_message("phantom: cannot start a phantom - the path of sd is too long");\n      _exit(1);', '      log_message("phantom: cannot start a phantom - the path of sd is too long");'),
    ("linuxio", "the old words", "cannot derive the TLS directory beside %s", "no usable data directory in %s"),
    ("remote", "tool.remote says the verbs' line", "msg = sysmsg(15150)", "msg = sysmsg(12950)"),
    ("config", "tool.config says nothing first", "   msg = sysmsg(15150)                                          ;* the status line says so first", "   msg = msg"),
    ("cname", "the old name is compared as found", "if new.file.name = downcase(old.file.name) then", "if new.file.name = old.file.name then"),
    ("cproc", "an administrator enters a suspended account", "   if kernel(K$INTERNAL,-1) and kernel(K$ADMINISTRATOR,-1) then\n      logto.ok = @true", "   if kernel(K$ADMINISTRATOR,-1) then\n      logto.ok = @true"),
    ("vjobs", "systemd on Windows", "jobs that the Task Scheduler runs", "jobs that systemd runs"),
    ("vbackup", "no description", "Verb to back up accounts to a zip file (administrator)", "V"),
]


def selftest():
    s = load()
    if any(not ok for _, ok, _ in checks(s)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        report(checks(s))
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text exactly once ---")
    for key, name, old, new in MUTANTS:
        if s[key].count(old) != 1:
            print("  [FAIL] %s: the text matches %d times in %s, not once" % (name, s[key].count(old), key))
            holes += 1
            continue
        t = dict(s)
        t[key] = s[key].replace(old, new)
        caught = [n for n, ok, _ in checks(t) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + "; ".join(caught[:2])[:110] if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    print("\n%d of %d mutants caught, %d missed" % (len(MUTANTS) - holes, len(MUTANTS), holes))
    return 1 if holes else 0


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    rows = checks(load())
    bad = report(rows)
    print("\ntest-carry1557-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
