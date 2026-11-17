#!/usr/bin/env python3
"""test-netdirs-units.py - NETDIRS made stricter, from Linux 1557e270 (S.62, the owner's decision of 17 Nov 2026), read off the source.

  python gplbld/test-netdirs-units.py
  python gplbld/test-netdirs-units.py --selftest

FREE CHECK: no install, no sd, no administrator.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

WHAT IT CHECKS (the C with its comments taken out where a rule is about code)
  D1  delivered empty: the sd.conf stage.py writes has no live NETDIRS= line, only the commented one
  D2  the value is bounded: MAX_NETDIRS_LEN 191 (what a 199-character sd.conf line leaves after "NETDIRS="), and a longer value OR A LINE
      THAT DID NOT FIT in the line buffer is refused by name before the copy (it used to be cut at 191, the rest read as a line)
  D3  CONFIG() does not offer NETDIRS (Linux: "Not offered to CONFIG(), not changed by set.config"); set.config's fixed list names it
  G1  os_path_ok_for_account(): os_gate_open() first, the account's own directory (account_path_own()) and the SD.ACCOUNTS gate next,
      path_in_netdirs() LAST; account_path_permitted() is account_path_own() then path_in_netdirs(); nothing else calls path_in_netdirs()
  G2  path_in_netdirs(): an empty list answers no at once; a candidate holding "." or ".." is a no BEFORE the list is read or compared; a
      matching entry is admitted only while no registered account overlaps it (the register read again at each admission)
  G3  the comparison is path_within(): case-insensitive (NTFS) and ending at a component boundary
  E1  an entry is ignored when not absolute, not an existing directory, a drive root or "/", overlapping the system directory, sd.conf's
      directory, USRDIR, GRPDIR or a registered account (an unreadable register refuses), or after the first 16; an over-long element is
      discarded whole, never cut
  E2  start_sd() calls netdirs_report() after audit_rotate(), which names each ignored entry in the error log, and the session judges again
  T1  config.table has a NETDIRS row, kind text, write no, saying CONFIG cannot read it
WHAT IT CANNOT SAY: that a session is admitted or refused at run time - a VM or an install sitting's.  --selftest requires each mutation to be
caught and to match its text exactly once.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.dirname(HERE)
FILES = {
    "dio2": "gplsrc/op_dio2.c",
    "opsh": "gplsrc/op_sh.c",
    "configc": "gplsrc/config.c",
    "syssegh": "gplsrc/sysseg.h",
    "syssegc": "gplsrc/sysseg.c",
    "opconfig": "gplsrc/op_config.c",
    "table": "sdsys/config.table",
    "stage": "gplbld/stage.py",
    "confset": "gplbld/sd-confset.ps1",
}


def ccode(src):
    s = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"(?m)//.*$", "", s)


def func(code, header):
    """The body of the C function whose definition starts with HEADER, to its closing brace at column 0."""
    i = code.find(header)
    if i < 0:
        return ""
    j = code.find("\n}", i)
    return code[i:j + 2] if j > i else ""


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    stage = s["stage"]
    ck("D1 delivered empty: the sd.conf stage.py writes has the line commented out and no live NETDIRS=",
       "# NETDIRS=" in stage and not re.search(r"(?m)^NETDIRS=", stage))

    ck("D2 MAX_NETDIRS_LEN is 191", re.search(r"#define MAX_NETDIRS_LEN 191\b", ccode(s["syssegh"])) is not None)
    cc = ccode(s["configc"])
    ck("D2b ...read_config() knows whether a line fitted in its buffer (a line end still waiting is taken, CR LF or LF)",
       "line_whole = TRUE;" in cc and "line_whole = FALSE;" in cc and re.search(r"int c = getc\(fu\);\s*if \(c == '\\r'\)\s*c = getc\(fu\);", cc) is not None)
    ck("D2c ...and NETDIRS refuses a line that did not fit or a value over the limit, by name, before it is copied",
       re.search(r'else if \(strncmp\(rec, "NETDIRS=", 8\) == 0\) \{\s*if \(!line_whole \|\| \(strlen\(rec \+ 8\) > MAX_NETDIRS_LEN\)\) \{\s*sprintf\(errmsg, "NETDIRS value is longer than %d characters\.",', cc) is not None)

    oc = ccode(s["opconfig"])
    ck("D3 CONFIG() does not offer NETDIRS", '"NETDIRS"' not in oc)
    ck("D3b ...and set.config leaves it alone (sd-confset.ps1's fixed list)", "'NETDIRS'" in s["confset"])

    sh = ccode(s["opsh"])
    ok = func(sh, "bool os_path_ok_for_account(const char *name) {")
    order = [ok.find(t) for t in ("os_gate_open()", "account_path_own(resolved, TRUE)", "path_in_enterable_account(resolved)", "path_in_netdirs(cand)")]
    ck("G1 os_path_ok_for_account(): the OS gate, the account's own directory, SD.ACCOUNTS, and NETDIRS LAST",
       all(o >= 0 for o in order) and order == sorted(order) and "account_path_permitted" not in ok, "%s" % order)
    d2 = ccode(s["dio2"])
    app = func(d2, "bool account_path_permitted(char* path,")
    ck("G1b account_path_permitted() is the account's own directory first, then NETDIRS",
       0 <= app.find("account_path_own(path, for_write)") < app.find("path_in_netdirs(cand)"))
    own = func(d2, "bool account_path_own(char* path,")
    ck("G1c account_path_own() reads no NETDIRS", own != "" and "netdirs" not in own.lower())
    callers = re.findall(r"path_in_netdirs\(", d2 + sh)
    ck("G1d path_in_netdirs() is called from those two places only (and defined once)", len(callers) == 3, "%d" % len(callers))
    pin = func(d2, "bool path_in_netdirs(char* cand) {")
    a = pin.find("if (sysseg->netdirs[0] == '\\0')")
    b = pin.find("has_parent_ref(cand) || netdir_dot_component(cand)")
    c = pin.find("netdirs_load(FALSE)")
    d = pin.find("path_within(cand, netdirs_root[i]) && (netdir_account_clash(netdirs_root[i], NULL, 0) == 0)")
    ck("G2 path_in_netdirs(): empty list no; '.'/'..' refused before the list is read; an entry admits only while no account overlaps it",
       0 <= a < b < c < d, "%s" % [a, b, c, d])
    dot = func(d2, "Private bool netdir_dot_component(char* p) {")
    ck("G2b ...the dot test finds both '.' and '..' at a component boundary", "(q[1] == '\\0') || (q[1] == '/') || ((q[1] == '.')" in dot)
    pw = func(d2, "Private bool path_within(char* cand, char* root) {")
    ck("G3 the comparison ignores case and ends at a component boundary", "strncasecmp(cand, root, root_len)" in pw
       and "return ((cand[root_len] == '\\0') || (cand[root_len] == '/'));" in pw)

    ld = func(d2, "Private void netdirs_load(bool report) {")
    rules = ["!os_root_absolute(item)", "!S_ISDIR(st.st_mode)", "os_root_whole_machine(root)", "netdir_overlap(root, sysdir)",
             "netdir_overlap(root, confdir)", "netdir_resolved(pcfg.usrdir, other) && netdir_overlap(root, other)",
             "netdir_resolved(pcfg.grpdir, other) && netdir_overlap(root, other)", "netdir_account_clash(root, which, sizeof(which))",
             "netdirs_count >= MAX_NETDIRS"]
    ck("E1 an entry is judged by every rule: absolute, an existing directory, not a drive root, clear of SDSYS, sd.conf's directory, USRDIR, GRPDIR and every account, at most 16",
       all(r in ld for r in rules), "%s" % [r for r in rules if r not in ld])
    ck("E1b ...a register that cannot be read refuses the entry, and an entry passes only with no reason against it",
       'if (clash < 0)\n          strcpy(why, "the account register cannot be read");' in ld and "if (why[0] != '\\0')\n        netdir_note(report, item, why);\n      else\n        strcpy(netdirs_root[netdirs_count++], root);" in ld)
    ck("E1c ...MAX_NETDIRS is 16, and an element longer than a pathname is discarded, never copied",
       re.search(r"#define MAX_NETDIRS 16\b", d2) is not None and re.search(r"if \(n > MAX_PATHNAME_LEN\) \{\s*snprintf\(item, sizeof\(item\), \"%\.40s\.\.\.\", p\);\s*netdir_note", ld) is not None)
    clash = func(d2, "Private int netdir_account_clash(char* root, char* which, size_t which_len) {")
    ck("E1d ...the account test reads the register (line 1, @SDSYS expanded) and says -1 when it cannot open it",
       "if ((d = opendir(regdir)) == NULL)\n    return -1;" in clash and 'strncasecmp(body, "@SDSYS", 6) == 0' in clash and "netdir_overlap(root, norm)" in clash)
    sc = ccode(s["syssegc"])
    st = func(sc, "bool start_sd() {")
    ck("E2 start_sd() names the ignored entries once, after audit_rotate(); a session judges again",
       0 <= st.find("audit_rotate();") < st.find("netdirs_report();") and "netdirs_load(TRUE);\n  netdirs_count = -1;" in d2)

    table = {ln.split("|")[0]: ln.split("|") for ln in s["table"].split("\n") if ln and not ln.startswith("#")}
    t = table.get("NETDIRS", [])
    ck("T1 config.table: NETDIRS is text, write no, and says CONFIG cannot read it", len(t) >= 10 and t[1] == "text" and t[8] == "no" and "Not readable with the CONFIG function" in t[7], "%s" % t)
    return rows


def load():
    out = {}
    for k, rel in FILES.items():
        p = os.path.join(SD, rel)
        if not os.path.isfile(p):
            print("test-netdirs-units: CANNOT RUN - %s is missing" % p, file=sys.stderr)
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
    ("syssegh", "the limit is 1023 again", "#define MAX_NETDIRS_LEN 191", "#define MAX_NETDIRS_LEN 1023"),
    ("configc", "a line too long is cut, not refused", "if (!line_whole || (strlen(rec + 8) > MAX_NETDIRS_LEN)) {", "if (strlen(rec + 8) > MAX_NETDIRS_LEN) {"),
    ("opconfig", "CONFIG offers it again", "  else if (!strcmp(param, \"NETFILES\"))", "  else if (!strcmp(param, \"NETDIRS\"))\n    k_put_c_string((char*)(sysseg->netdirs), &result);\n  else if (!strcmp(param, \"NETFILES\"))"),
    ("opsh", "NETDIRS is asked before SD.ACCOUNTS", "  if (account_path_own(resolved, TRUE))\n    return TRUE;", "  if (account_path_permitted(resolved, TRUE))\n    return TRUE;"),
    ("dio2", "a dotted candidate is compared", "has_parent_ref(cand) || netdir_dot_component(cand)", "has_parent_ref(cand)"),
    ("dio2", "an account made later does not close the entry", "path_within(cand, netdirs_root[i]) && (netdir_account_clash(netdirs_root[i], NULL, 0) == 0)", "path_within(cand, netdirs_root[i])"),
    ("dio2", "a relative entry is taken", "      if (!os_root_absolute(item))\n        strcpy(why, \"it is not an absolute path\");\n      else if", "      if"),
    ("dio2", "USRDIR may be listed", "netdir_resolved(pcfg.usrdir, other) && netdir_overlap(root, other)", "netdir_resolved(pcfg.usrdir, other) && FALSE"),
    ("dio2", "an unreadable register admits", "  if ((d = opendir(regdir)) == NULL)\n    return -1;\n  while ((clash == 0)", "  if ((d = opendir(regdir)) == NULL)\n    return 0;\n  while ((clash == 0)"),
    ("dio2", "no limit on the count", "#define MAX_NETDIRS 16", "#define MAX_NETDIRS 64"),
    ("dio2", "the comparison minds case", "  if (strncasecmp(cand, root, root_len) != 0)", "  if (strncmp(cand, root, root_len) != 0)"),
    ("syssegc", "nothing is named at start", "  netdirs_report();\n", ""),
    ("stage", "the delivered sd.conf lists a directory", "# NETDIRS=\nUSRDIR=", "NETDIRS=C:\\\\data\nUSRDIR="),
    ("table", "CONFIG is said to read it", "empty keeps it to its account. Not readable with the CONFIG function.", "empty keeps it to its account."),
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
    print("\ntest-netdirs-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
