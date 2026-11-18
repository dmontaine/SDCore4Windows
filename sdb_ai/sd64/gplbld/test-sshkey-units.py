#!/usr/bin/env python3
"""test-sshkey-units.py - ssh key sign-in is off as delivered for the accounts SD makes (from Linux 1557e270, S.62 LC3), read off the source.

  python gplbld/test-sshkey-units.py
  python gplbld/test-sshkey-units.py --selftest

FREE CHECK: no install, no sd, no administrator.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

THE RULE (the owner's decision of 17 Nov 2026, built on Linux first: "key sign-in is FORBIDDEN as delivered ... a documented loosening for the
administrator", and only the accounts SD itself made lose it).  One Windows group, sdsshnokey, means "may NOT sign in by key":
  - CREATE.ACCOUNT (!create_account) puts a Windows user it MAKES in it (or one a restore takes over), unless SSH-KEY-ON (CA$SSH.KEY, exactly 1);
    an ATTACHed user (the installing user) never; the group is looked for before anything is made; a group or other account is refused (10087,
    10081); the state line is 15171, read off the group, and not said for an attached user; the audit gates= list names ssh-key-on.
  - MODIFY.ACCOUNT NAME SSH-KEY-ON | SSH-KEY-OFF (slot KY, after AI): out of / into the group, refused with 15170 for a user SD did not make
    (!is_sd_user), audited "modify.account ssh-key-on account=NAME", said with 15171.
  - sshd: allow-ssh-groups.ps1 writes "Match Group sdsshnokey,<host>\\sdsshnokey User *,!sdsys,... / PubkeyAuthentication no" as the LAST lines
    of SD's block (so it is the file's first Match), and nothing else in SD's block sets PubkeyAuthentication.  NOT sdsshonly, which carries the
    deny-logon rights no verb may lift.
  - the installer makes the group EMPTY ("net localgroup sdsshnokey /add" in [Run], nothing joins it there), so an upgrade changes no account;
    the uninstaller removes it only with the accounts (OfferAccountRemoval), never with the route groups (RemoveSdGroups).
  - tool.gates (a 'nokey' gate row, a 'key' column, 'na' for a user SD did not make), tool.mygates ('own'), the backup manifest (ssh.key; a
    restore without it leaves key sign-in off), DELETE.ACCOUNT (a kept user leaves the group last).

***IT READS THE SOURCE AS TEXT, AND RUNS allow-ssh-groups.ps1's EDITING FUNCTIONS ON A SAMPLE sshd_config IN WINDOWS POWERSHELL.***  It cannot say
that sshd honours the arm for a real member, nor that create.account joins the group at run time: those are a VM sitting's.  --selftest requires
each mutation to be caught and to match its text exactly once.
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.dirname(HERE)
FILES = {
    "createacc": "sdsys/syscom/createacc.h",
    "create_account": "sdsys/gpl.bp/create_account",
    "createa": "sdsys/gpl.bp/createa",
    "modifya": "sdsys/gpl.bp/modifya",
    "tk_gate_info": "sdsys/gpl.bp/tk_gate_info",
    "tk_gates": "sdsys/gpl.bp/tk_gates",
    "tool_gates": "sdsys/gpl.bp/tool_gates",
    "tool_mygates": "sdsys/gpl.bp/tool_mygates",
    "acc_os_info": "sdsys/gpl.bp/acc_os_info",
    "restorea": "sdsys/gpl.bp/restorea",
    "delacc": "sdsys/gpl.bp/delacc",
    "iss": "gplbld/sd.iss",
    "allow": "gplbld/allow-ssh-groups.ps1",
    "m15170": "sdsys/messages/15170",
    "m15171": "sdsys/messages/15171",
}


def basic(src):
    """A BASIC program with its comment lines and ;* tails taken out."""
    return "\n".join(re.sub(r"\s*;\*.*$", "", ln) for ln in src.split("\n") if not ln.lstrip().startswith("*"))


def pascal(src):
    """sd.iss with its { } and (* *) comments and ; lines taken out (enough to tell code from prose here)."""
    s = re.sub(r"\(\*.*?\*\)", "", src, flags=re.S)
    s = re.sub(r"\{[^}]*\}", "", s)
    return "\n".join(ln for ln in s.split("\n") if not ln.lstrip().startswith(";"))


def section(text, start, end):
    i = text.find(start)
    if i < 0:
        return ""
    j = text.find(end, i + len(start))
    return text[i:j] if j > i else text[i:]


HARNESS = r"""
$ErrorActionPreference = 'Stop'
$src = '%SRC%'
foreach ($l in (Get-Content -LiteralPath $src)) { if ($l -match '^\$(begin|end)\s*=') { Invoke-Expression $l } }
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { Invoke-Expression $f.Extent.Text }
$stock = @('Port 22', 'PasswordAuthentication yes', 'Match Group administrators', '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys')
$new = @(Add-OurBlock $stock @('sdssh', 'BOX\sdssh') 'C:\Program Files\SD\usr\bin\sd.exe')
$i = 0
foreach ($l in $new) { $i++; Write-Output ('LINE~' + $i + '~' + $l) }
$back = @(Remove-OurBlock $new)
Write-Output ('INVERSE~' + (($back -join "`n") -eq ($stock -join "`n")))
$bare = @(Add-OurBlock $stock @('sdssh'))
Write-Output ('BARE~' + (($bare | Where-Object { $_ -match '^Match Group sdsshnokey,' }).Count))
"""


def run_allow(allow_text):
    """Run Add-OurBlock / Remove-OurBlock from the given allow-ssh-groups.ps1 text; returns (lines, inverse, bare_count) or None."""
    ps = os.path.join(os.environ.get("SystemRoot", "C:/Windows"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    if not os.path.isfile(ps):
        return None
    tmp = tempfile.mkdtemp(prefix="sshkey-")
    src = os.path.join(tmp, "allow.ps1")
    with open(src, "w", encoding="utf-8", newline="") as f:
        f.write(allow_text)
    h = os.path.join(tmp, "harness.ps1")
    with open(h, "w", encoding="utf-8") as f:
        f.write(HARNESS.replace("%SRC%", src.replace("\\", "/")))
    env = dict(os.environ)
    env["COMPUTERNAME"] = "BOX"
    r = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", h], capture_output=True, text=True, timeout=120, env=env)
    lines, inverse, bare = [], None, None
    for ln in r.stdout.splitlines():
        if ln.startswith("LINE~"):
            lines.append(ln.split("~", 2)[2])
        elif ln.startswith("INVERSE~"):
            inverse = ln.split("~", 1)[1] == "True"
        elif ln.startswith("BARE~"):
            bare = int(ln.split("~", 1)[1] or "0")
    if inverse is None:
        return ("error", (r.stdout + r.stderr)[-600:])
    return (lines, inverse, bare)


def checks(s, dynamic=True):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    ca = basic(s["createacc"])
    ck("K1 createacc.h defines CA$SSH.KEY as 46, and no other CA$ setting is 46",
       re.search(r"\$define CA\$SSH\.KEY\s+46\b", ca) and len(re.findall(r"\$define CA\$[A-Z.]+\s+46\b", ca)) == 1)

    a = basic(s["create_account"])
    ck("K2 !create_account takes the request only from exactly 1", "ssh.key.want = (settings<CA$SSH.KEY> = 1)" in a)
    pre = "if not(attach) and not(ssh.key.want) then\n       files.grp.name = 'sdsshnokey'\n       gosub check.files.group\n       if files.bad then goto exit.create"
    made = a.find("Is the user a valid os user?")
    ck("K3 ...looks for sdsshnokey before the Windows user is made, unless attached or ssh-key-on", pre in a and 0 <= a.find(pre) < (made if made >= 0 else 10 ** 9) or (pre in a and a.find(pre) < a.find("case upcase(acc.uname) = 'ROOT'")))
    grp = a[a.find("case acc.type = 'GROUP'"):a.find("case acc.type = 'OTHER'")]
    oth = a[a.find("case acc.type = 'OTHER'"):]
    oth = oth[:oth.find("pathname = trim(settings<CA$PATH>)")]
    ck("K4 ...refuses it for a group account (10087) and an other account (10081) before anything is made",
       "if ssh.key.want then\n       @system.return.code = -ER$ARGS\n       err = 10087:@vm:acc.name" in grp
       and "if ssh.key.want then\n       @system.return.code = -ER$ARGS\n       err = 10081:@vm:acc.name:@vm:2" in oth)
    # 18 Nov 26 (round 6, D3, P-7694): set.access is in the USER arm in Linux's shape: files.grp.name = 'sdsshnokey', then leave.route.group for a reused
    # user given ssh-key-on, else join.files.group; each stops the account on a failure (route.stat), and both subroutines say 10081 with the status
    acc = section(a, "   case acc.type = \"USER\"\n", "      gosub create.group\n")
    join = ("      if not(attach) then\n         files.grp.name = 'sdsshnokey'\n         if ssh.key.want then\n            if reuse.sd.user then\n"
            "               gosub leave.route.group\n               if route.stat # 0 then goto exit.create\n            end\n         end else\n"
            "            gosub join.files.group\n            if route.stat # 0 then goto exit.create\n         end\n      end")
    jfg = section(a, "\njoin.files.group:", "\n   return\n")
    lrg = section(a, "\nleave.route.group:", "\n   return\n\n")
    ck("K5 ...joins a Windows user it made (not an attached one) to sdsshnokey unless ssh-key-on, and takes a reused one out with ssh-key-on",
       join in acc and 'route.stat = os_group("ADDMEM", files.grp.name, acc.uname)' in jfg and 'route.stat = os_group("DELMEM", files.grp.name, acc.uname)' in lrg)
    ck("K6 ...a failed join stops the account with 10081, as a route does",
       re.search(r'route\.stat = os_group\("ADDMEM", files\.grp\.name, acc\.uname\)\n\s*if route\.stat # 0 then\n\s*@system\.return\.code = -ER\$FAILED\n\s*err = 10081', jfg) is not None)
    ck("K7 ...and NOT sdsshonly: the deny-logon group's join is still only ADDMEM sdsshonly, and ssh-key-on never touches it",
       a.count('"sdsshonly"') == 1 and "sdsshnokey" not in a[a.find('os_group("ADDMEM", "sdsshonly"') - 200:a.find('os_group("ADDMEM", "sdsshonly"') + 60])
    ck("K8 ...the state line 15171 is read off the group ('no' for a member) and not said for an attached user",
       "if not(attach) then crt sysmsg(15171, acc.name, if is_grp_member(acc.uname, 'sdsshnokey') then 'no' else 'yes')" in a)

    c = basic(s["createa"])
    more = c[c.find("\nmore.args:\n"):]
    ck("K9 create.account takes SSH-KEY-ON as CA$SSH.KEY = 1, and not SSH-KEY-OFF", "case upcase(token) = 'SSH-KEY-ON'\n            settings<CA$SSH.KEY> = 1" in more and "SSH-KEY-OFF" not in more)
    ck("K10 ...its audit gates= list and its usage name it", "if settings<CA$SSH.KEY> = 1 then gates<-1> = 'ssh-key-on'" in c and "{ssh-key-on}" in c)

    m = basic(s["modifya"])
    wa = re.search(r"word\.arr = convert\(',', @fm, '([^']*)'\)", m)
    sa = re.search(r"slot\.arr = convert\(',', @fm, '([^']*)'\)", m)
    words = wa.group(1).split(",") if wa else []
    slots = sa.group(1).split(",") if sa else []
    pair = [slots[words.index(w)] if w in words and len(slots) == len(words) else None for w in ("SSH-KEY-ON", "SSH-KEY-OFF")]
    ck("K11 modify.account knows SSH-KEY-ON and SSH-KEY-OFF in one slot of their own (KY), carried out right after AI-ON / AI-OFF",
       pair == ["KY", "KY"] and slots.count("KY") == 2 and "AI-OFF" in words and words.index("SSH-KEY-ON") == words.index("AI-OFF") + 1, "%s" % pair)
    ck("K12 ...each word reaches set.sshkey with the right want",
       # 18 Nov 26 (round 6, D3): Linux's do.action form, `case action = 'X'` ... gosub set.sshkey, return
       re.search(r"case action = 'SSH-KEY-ON'\s*\n\s*key\.want = @true\s*\n\s*gosub set\.sshkey\s*\n\s*return\n", m) is not None
       and re.search(r"case action = 'SSH-KEY-OFF'\s*\n\s*key\.want = @false\s*\n\s*gosub set\.sshkey\s*\n\s*return\n", m) is not None)
    ss = section(m, "\nset.sshkey:", "\n   return\n\n")
    ss_all = m[m.find("\nset.sshkey:"):]
    ss_all = ss_all[:ss_all.find("\nset.ai:")] if "\nset.ai:" in ss_all else ss_all      # 18 Nov 26 (D3): set.ai follows set.sshkey, as Linux's
    made_at = ss_all.find("key.made = is_sd_user(files.user)")
    refuse_at = ss_all.find("crt sysmsg(15170, acc.name, files.user)")
    change_at = ss_all.find("gosub change.files.group")
    ck("K13 ...set.sshkey refuses a user SD did not make (!is_sd_user) with 15170 BEFORE anything changes",
       0 <= made_at < refuse_at < change_at and "if not(key.made) then" in ss_all, "made %d refuse %d change %d" % (made_at, refuse_at, change_at))
    ck("K14 ...a group (10087) or other account (10081) is refused first", ss.find("if group.name[1,4] # 'sdu_' then") >= 0 and "crt sysmsg(10087, acc.name)" in ss)
    ck("K15 ...the group is joined for OFF and left for ON (the opposite of the route words), read back by change.files.group",
       "cg.group = 'sdsshnokey'\n   cg.want = not(key.want)\n   gosub change.files.group" in ss_all)
    ck("K16 ...audited as modify.account ssh-key-on|ssh-key-off account=NAME, and said with 15171 ('no' while a member)",
       "void kernel(K$AUDIT, 'modify.account ' : downcase(action) : ' account=' : acc.name)\n   crt sysmsg(15171, acc.name, if cg.now then 'no' else 'yes')" in ss_all)
    ck("K17 ...SSH-KEY-OFF on a machine without the group names it (10024)", "crt sysmsg(10024, 'sdsshnokey')" in ss_all)
    ck("K18 ...the usage and the error list name both words", "modify.account <account> ssh-key-on | ssh-key-off" in m and "ssh-key-on, ssh-key-off" in m)

    gi = s["tk_gate_info"]
    row = re.search(r'rows<-1> = "ssh-key\|([^"]*)"', gi)
    parts = ("ssh-key|" + row.group(1)).split("|") if row else []
    ck("K19 tk_gate_info has the ssh-key gate: kind nokey, group sdsshnokey, words ssh-key-on / ssh-key-off, off as delivered, beyond SD, built",
       len(parts) == 15 and parts[2:5] == ["ssh-key-on", "ssh-key-off", "nokey"] and parts[6] == "sdsshnokey" and parts[9] == "off" and parts[10] == "KY"
       and parts[13] == "1" and parts[14] == "built", "%s" % parts)
    tg = basic(s["tk_gates"])
    ck("K20 $tk_gates reads it ON when NOT in the group, and 'na' unless a USER account whose Windows user SD made",
       "case gi<TK.G.KIND> = 'nokey'\n            state = 'na'\n            if atype = 'USER' then\n               k.made = is_sd_user(user)\n               if status() = 0 and k.made then state = (if is_grp_member(user, gi<TK.G.GROUP>) then 0 else 1)" in tg)
    tm = basic(s["tool_mygates"])
    ck("K21 tool.mygates shows 'own' for a Windows user SD did not make and ON when not in the group",
       "case gkind<k> = 'nokey'\n            s = 'own'\n            k.made = is_sd_user(@logname)\n            if status() = 0 and k.made then s = (if is_grp_member(@logname, ggrp<k>) then 0 else 1)" in tm
       and "nowtxt = 'own'" in tm)
    tgs = basic(s["tool_gates"])
    ck("K22 tool.gates heads the column 'key' and says why a user SD did not make is a dash",
       "case gid = 'ssh-key'\n         hd = 'key'" in tgs and "case ast<av, k> = 'na' and gids<k> = 'ssh-key' and aty<av> = 'USER'" in tgs)
    ck("K23 ...nineteen cells fit: the name column is 10 wide and the first cell is at mat.x + 18",
       "X0 = mat.x + 18" in tgs and "fmt(anm<av>, '10L')" in tgs and "fmt('Account', '10L')" in tgs)

    ao = basic(s["acc_os_info"])
    ck("K24 the backup manifest carries ssh.key: 1 when NOT in sdsshnokey (a user account only)",
       "if m then sshkey = 0" in ao and "info<-1> = 'ssh.key: ' : sshkey" in ao and ao.find("info<-1> = 'ssh.key: '") > ao.find("if typ = 'USER' then\n      info<-1> = 'route.ssh: '"))
    r = basic(s["restorea"])
    ck("K25 RESTORE.ACCOUNT asks for ssh-key-on only on an explicit 1 (a manifest without it restores key sign-in OFF)",
       "case sec.keys<s.idx,kp> = 'ssh.key'  ; m.ssh.key = kv" in r and "if m.ssh.key = '1' then settings<CA$SSH.KEY> = 1" in r and "m.ssh.key = ''" in r)
    d = basic(s["delacc"])
    ck("K26 DELETE.ACCOUNT takes a kept Windows user out of sdsshnokey, after sdusers",
       "strip.group = 'sdusers' ; gosub strip.membership\n               strip.group = 'sdsshnokey' ; gosub strip.membership" in d)

    iss = s["iss"]
    code = pascal(iss)
    ck("K27 the installer makes the group in [Run], with nothing else there putting anybody in it",
       'Parameters: "localgroup sdsshnokey /add /comment:' in iss and not re.search(r'localgroup sdsshnokey ""', iss)
       and not re.search(r"sdsshnokey[^\n]*(ADDMEM|Add-LocalGroupMember)", iss))
    rsg = section(code, "procedure RemoveSdGroups;", "\nend;")
    oar = section(code, "procedure OfferAccountRemoval;", "\nend;")
    ck("K28 the uninstaller does NOT remove it with the route groups (a deny group that is missing matches nobody)",
       rsg != "" and "sdsshnokey" not in rsg and "localgroup sdsshonly /delete" in rsg)
    ck("K29 ...it removes it only after the accounts were removed (OfferAccountRemoval, Code = 0)",
       re.search(r"if Code = 0 then\s*\n\s*Exec\(ExpandConstant\('\{sys\}\\net\.exe'\), 'localgroup sdsshnokey /delete'", iss) is not None and "sdsshnokey /delete" in oar)

    al = s["allow"]
    ck("K30 allow-ssh-groups.ps1's key arm is Match Group sdsshnokey (both spellings) naming out sdsys and sdradmin, and PubkeyAuthentication no",
       "'Match Group sdsshnokey,' + $h + '\\sdsshnokey User *,!sdsys,!' + $h + '\\sdsys,!sdradmin,!' + $h + '\\sdradmin'" in al
       and "'    PubkeyAuthentication no')" in al)
    if dynamic:
        res = run_allow(al)
        if res is None:
            ck("K31 the editing functions ran in Windows PowerShell", False, "no Windows PowerShell")
        elif res[0] == "error":
            ck("K31 the editing functions ran in Windows PowerShell", False, res[1])
        else:
            lines, inverse, bare = res
            b = lines.index("# --- BEGIN SD ssh-only model - PROJECT_STATUS.md 5.6.2 ---") if "# --- BEGIN SD ssh-only model - PROJECT_STATUS.md 5.6.2 ---" in lines else -1
            e = lines.index("# --- END SD ssh-only model ---") if "# --- END SD ssh-only model ---" in lines else -1
            arm = "Match Group sdsshnokey,box\\sdsshnokey User *,!sdsys,!box\\sdsys,!sdradmin,!box\\sdradmin"
            firstm = next((i for i, l in enumerate(lines) if re.match(r"^\s*Match\b", l)), -1)
            ck("K31 written: the arm is the last two lines inside SD's block, after DisableForwarding, and is the first Match of the file",
               b >= 0 and e == b + 6 and lines[e - 2] == arm and lines[e - 1] == "    PubkeyAuthentication no" and lines[e - 3] == "DisableForwarding yes" and firstm == e - 2,
               "%s" % lines)
            ck("K32 ...nothing else in SD's block sets PubkeyAuthentication, and the global lines stay before every Match",
               b >= 0 and sum(1 for l in lines[b:e + 1] if "PubkeyAuthentication" in l) == 1 and lines.index([l for l in lines if l.startswith("AllowGroups ")][0]) < firstm)
            ck("K33 ...the block is still removed exactly (apply then remove is the original), and the arm is in the arm without ForceCommand too",
               inverse is True and bare == 1, "inverse %s bare %s" % (inverse, bare))

    ck("K34 the two messages: 15170 names the account and the Windows user and says nothing was changed; 15171 takes the account and the state",
       "%1" in s["m15170"] and "%2" in s["m15170"] and "Windows user" in s["m15170"] and "nothing was changed" in s["m15170"]
       and s["m15171"].strip() == "Account %1 may sign in over ssh with a key: %2")
    return rows


def load():
    out = {}
    for k, rel in FILES.items():
        p = os.path.join(SD, rel)
        if not os.path.isfile(p):
            print("test-sshkey-units: CANNOT RUN - %s is missing" % p, file=sys.stderr)
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
    ("create_account", "any non-blank value is a request", "ssh.key.want = (settings<CA$SSH.KEY> = 1)", "ssh.key.want = (settings<CA$SSH.KEY> # '')"),
    ("create_account", "the group is not looked for first", "     if not(attach) and not(ssh.key.want) then\n       files.grp.name = 'sdsshnokey'", "     if @false then\n       files.grp.name = 'sdsshnokey'"),
    ("create_account", "an attached user is put in the group", "      if not(attach) then\n         files.grp.name = 'sdsshnokey'", "      if @true then\n         files.grp.name = 'sdsshnokey'"),      # 18 Nov 26 (D3): Linux's shape
    ("create_account", "a made user is not put in it", "         end else\n            gosub join.files.group\n            if route.stat # 0 then goto exit.create\n         end\n      end", "         end else\n            null\n         end\n      end"),
    ("create_account", "a group account may ask for keys", "* 17 Nov 26 Windows port - from Linux 1557e270 (S.62 LC3): nor key sign-in, which belongs to a Windows user, for the same reason.\n     if ssh.key.want then", "* 17 Nov 26 Windows port - from Linux 1557e270 (S.62 LC3): nor key sign-in, which belongs to a Windows user, for the same reason.\n     if @false then"),
    ("create_account", "the state line reads the group the right way up", "then 'no' else 'yes')  ;* Account %1 may sign in over ssh with a key: %2", "then 'yes' else 'no')  ;* Account %1 may sign in over ssh with a key: %2"),
    ("createa", "the audit line forgets it", "if settings<CA$SSH.KEY> = 1 then gates<-1> = 'ssh-key-on'", "if @false then gates<-1> = 'ssh-key-on'"),
    ("createa", "SSH-KEY-ON is not a word", "case upcase(token) = 'SSH-KEY-ON'", "case upcase(token) = 'SSH-KEYS-ON'"),
    ("modifya", "the two words in different slots", "AI,AI,KY,KY,", "AI,AI,KY,KZ,"),
    ("modifya", "a user SD did not make is not refused", "   if not(key.made) then\n      @system.return.code = -ER$FAILED\n      crt sysmsg(15170", "   if @false then\n      @system.return.code = -ER$FAILED\n      crt sysmsg(15170"),
    ("modifya", "ON joins the group", "   cg.want = not(key.want)", "   cg.want = key.want"),
    ("modifya", "nothing is audited", "   void kernel(K$AUDIT, 'modify.account ' : downcase(action) : ' account=' : acc.name)\n   crt sysmsg(15171", "   crt sysmsg(15171"),
    ("tk_gate_info", "the gate is delivered on", "|next ssh connection|off|KY|", "|next ssh connection|on|KY|"),
    ("tk_gates", "a user SD did not make is shown as on", "               if status() = 0 and k.made then state = (if is_grp_member(user, gi<TK.G.GROUP>) then 0 else 1)", "               state = (if is_grp_member(user, gi<TK.G.GROUP>) then 0 else 1)"),
    ("tool_mygates", "own is never shown", "            s = 'own'\n            k.made", "            s = 0\n            k.made"),
    ("tool_gates", "the name stays 15 wide", "s = fmt(anm<av>, '10L')", "s = fmt(anm<av>, '15L')"),
    ("acc_os_info", "the manifest says 1 for a member", "if m then sshkey = 0", "if m then sshkey = 1"),
    ("restorea", "a manifest without it restores keys on", "if m.ssh.key = '1' then settings<CA$SSH.KEY> = 1", "if m.ssh.key # '0' then settings<CA$SSH.KEY> = 1"),
    ("delacc", "a kept user stays in the group", "               strip.group = 'sdsshnokey' ; gosub strip.membership\n", ""),
    ("iss", "the group is never made", 'Parameters: "localgroup sdsshnokey /add /comment:', 'Parameters: "localgroup sdsshnokeyx /add /comment:'),
    ("iss", "the installer puts the installing user in it", 'Filename: "{sys}\\net.exe"; Parameters: "localgroup sdusers ""{username}"" /add"; \\', 'Filename: "{sys}\\net.exe"; Parameters: "localgroup sdsshnokey ""{username}"" /add"; \\'),
    ("iss", "the uninstall drops it with the route groups", "  Exec(Net, 'localgroup sdsshonly /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);\nend;", "  Exec(Net, 'localgroup sdsshonly /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);\n  Exec(Net, 'localgroup sdsshnokey /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);\nend;"),
    ("allow", "the arm allows keys", "'    PubkeyAuthentication no')", "'    PubkeyAuthentication yes')"),
    ("allow", "the arm is not written", "'DisableForwarding yes') + @(Get-KeyArm) + @($end)\n    }\n    else", "'DisableForwarding yes') + @($end)\n    }\n    else"),
    ("allow", "the arm names the deny-logon group", "('Match Group sdsshnokey,' + $h + '\\sdsshnokey User", "('Match Group sdsshonly,' + $h + '\\sdsshonly User"),
    ("m15171", "the state line loses its account", "Account %1 may sign in over ssh with a key: %2", "Account may sign in over ssh with a key: %2"),
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
        caught = [n for n, ok, _ in checks(t, dynamic=(key == "allow")) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + "; ".join(caught[:2])[:110] if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    print("\n%d of %d mutants caught, %d missed" % (len(MUTANTS) - holes, len(MUTANTS), holes))
    return 1 if holes else 0


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    s = load()
    rows = checks(s)
    bad = report(rows)
    print("\ntest-sshkey-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
