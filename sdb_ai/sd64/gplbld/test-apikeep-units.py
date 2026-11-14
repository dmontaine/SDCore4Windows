#
# test-apikeep-units.py - free-tier guard for RELEASE_1.1 283 in sd.iss: the API's
# open/closed state across an uninstall that keeps sd.conf, then an install.
#
# command line: python gplbld/test-apikeep-units.py
# Exits 0 if every check passes and every mutant is caught, 1 otherwise.  Reads sd.iss
# only; needs no build, install or elevation.  A READ OF THE SCRIPT, NOT A RUN OF IT:
# what the installer then does on a real machine is witnessed in the VM sitting.
#
# THE RULE (Linux 58e60670; owner 14 Nov 2026: "If closed they stay closed, if open they
# stay open").  The uninstaller removes the API's firewall rule, so an API that was open
# to other computers came back blocked.  Now the uninstaller notes an OPEN rule in HKLM64
# (administrators only: a note in the data tree could be written by any SD user) before
# it removes the rule; a reinstall that finds sd.conf with a listener puts the open rule
# back; the note is removed by that install or by an uninstall that leaves no sd.conf.
#
# EACH MUTANT BREAKS ONE PIECE IN MEMORY and the checks must go red.  The live file is
# never written.

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ISS = os.path.join(HERE, 'sd.iss')


def body(text, header):
    """From a procedure/function header line to its 'end;' at column 0."""
    m = re.search(r'^' + re.escape(header) + r'.*?^end;', text, re.S | re.M)
    return m.group(0) if m else ''


def checks(t):
    """Return a list of failure names for this text of sd.iss."""
    bad = []
    note_open = body(t, 'function ApiNoteSaysOpen')
    clear = body(t, 'procedure ApiNoteClear')
    save = body(t, 'procedure SaveApiAccessNote')
    keep = body(t, 'function KeepApiFirewallOpen')
    early = body(t, 'procedure ApiRuleBeforeService')
    cur = body(t, 'procedure CurUninstallStepChanged')

    def need(name, ok):
        if not ok:
            bad.append(name)

    need('the note key is under SOFTWARE\\SD\\SetupNotes',
         "Result := 'SOFTWARE\\SD\\SetupNotes';" in t)
    need('reading the note uses HKLM64', 'RegQueryStringValue(HKLM64, ApiNoteKey' in note_open)
    need('only the exact word open counts', re.search(r"\(V = 'open'\)", note_open) is not None)
    need('clearing the note uses HKLM64', 'RegDeleteValue(HKLM64, ApiNoteKey' in clear)
    need('saving writes HKLM64', 'RegWriteStringValue(HKLM64, ApiNoteKey' in save)
    need('saving writes only when the rule is open', "if GetApiRuleScope = 'open' then" in save)
    need('saving clears the note otherwise', 'ApiNoteClear' in save.split('else', 1)[-1])
    need('no plain HKLM touches the note', not re.search(r'Reg\w+\(HKLM,\s*ApiNoteKey', t))
    need('put-back runs api-firewall.ps1 -Open', "api-firewall.ps1') + '\" -Open';" in keep)
    need('put-back never restricts or removes', '-Restrict' not in keep and '-Remove' not in keep)
    need('put-back failure text carries ELEVATED', 'ELEVATED' in keep)

    # ApiRuleBeforeService: the third arm, after the true-upgrade arm, and the note is spent.
    i_up = early.find('else if TrueUpgrade then')
    i_keep = early.find('else if ApiNoteSaysOpen and ApiConfHasListener then')
    need('the install arm needs the note AND a listener in sd.conf', i_keep >= 0)
    need('the install arm comes after the true-upgrade arm', 0 <= i_up < i_keep)
    need('the install arm calls the put-back', 'EarlyApiFw := KeepApiFirewallOpen;' in early)
    need('the note is spent on any install', re.search(r'^  ApiNoteClear;', early, re.M) is not None)

    # The uninstall: note first, rule removal second; the clear when no sd.conf is left.
    i_save = cur.find('SaveApiAccessNote;')
    i_rem = cur.find('RemoveApiFirewall;')
    need('the uninstall notes the rule before removing it', 0 <= i_save < i_rem)
    need('a missing data tree clears the note',
         re.search(r'RemoveSdUsersGroup;\s*ApiNoteClear;', cur) is not None)
    need('the note is cleared when sd.conf is gone after the answers',
         re.search(r"RecordDatabaseChoice\([^)]*\);\s*\{[^}]*\}\s*if not FileExists\(AddBackslash\(DataPath\) \+ 'sd.conf'\) then\s*ApiNoteClear;", cur) is not None)
    # The ssh half (Linux 2026-11-14T2030: "kept configuration: nothing is closed, nothing is opened, nothing is asked").
    def task_check(name):
        m = re.search(r'^Name: "' + re.escape(name) + r'";.*?\n(?:.*\\\n)*?.*Check: ([^\n]*)', t, re.M)
        return m.group(1) if m else ''

    for nm in ('sshserver\\sshremote', 'sshremoteshut', 'sshremoteopen'):
        need('the ssh access box %s is hidden on a kept-configuration reinstall' % nm,
             'not KeptConfReinstall' in task_check(nm))
    need('the ssh SERVER box is not an access question and stays',
         task_check('sshserver').strip() == 'SshServerAbsent')
    need('a kept-configuration reinstall is not a true upgrade and has an sd.conf',
         'Result := (not TrueUpgrade) and (not ApiConfAbsent);' in body(t, 'function KeptConfReinstall'))
    need('the ssh rule is left alone on a true upgrade or over a server SD did not just install',
         'Result := TrueUpgrade or (KeptConfReinstall and (not SshWasAbsent));' in body(t, 'function SshScopeKept'))
    need('ApplySshFirewall is called only when the rule is not kept',
         re.search(r'if not SshScopeKept then\s*begin\s*SshFw := ApplySshFirewall;', t) is not None)
    need('the sshd confinement is still put back on that path (not gated by the kept rule)',
         re.search(r'if not TrueUpgrade then\s*begin\s*SshLimit := ApplyAllowGroups;', t) is not None)
    return bad


MUTANTS = [
    ('one ssh access box is still shown on a kept-configuration reinstall',
     lambda t: t.replace('Check: (not SshServerAbsent) and SshCurrentlyOpen and (not KeptConfReinstall)',
                         'Check: (not SshServerAbsent) and SshCurrentlyOpen')),
    ('the ssh child box is still shown',
     lambda t: t.replace('Check: SshServerAbsent and (not KeptConfReinstall)', 'Check: SshServerAbsent')),
    ('the ssh server box is hidden too (an unasked server install)',
     lambda t: t.replace('Flags: checkablealone unchecked; \\\n    Check: SshServerAbsent\n',
                         'Flags: checkablealone unchecked; \\\n    Check: SshServerAbsent and (not KeptConfReinstall)\n')),
    ('the firewall call is gated on a true upgrade only (a hidden box would close an open port)',
     lambda t: t.replace('if not SshScopeKept then\n    begin\n      SshFw := ApplySshFirewall;',
                         'if not TrueUpgrade then\n    begin\n      SshFw := ApplySshFirewall;')),
    ('a server this install adds is no longer scoped',
     lambda t: t.replace('(KeptConfReinstall and (not SshWasAbsent))', '(KeptConfReinstall)')),
    ('the sshd confinement is skipped on a kept configuration',
     lambda t: t.replace('if not TrueUpgrade then\n    begin\n      SshLimit := ApplyAllowGroups;',
                         'if not SshScopeKept then\n    begin\n      SshLimit := ApplyAllowGroups;')),
    ('the note is written with plain HKLM (redirected, and wrong)',
     lambda t: t.replace('RegWriteStringValue(HKLM64, ApiNoteKey', 'RegWriteStringValue(HKLM, ApiNoteKey')),
    ('any non-empty note counts as open',
     lambda t: t.replace("(V = 'open')", "(V <> '')")),
    ('the put-back no longer needs a listener in sd.conf',
     lambda t: t.replace('else if ApiNoteSaysOpen and ApiConfHasListener then', 'else if ApiNoteSaysOpen then')),
    ('the rule is removed before the note is taken',
     lambda t: t.replace('    SaveApiAccessNote;\n    RemoveApiFirewall;', '    RemoveApiFirewall;\n    SaveApiAccessNote;')),
    ('the install leaves the note behind',
     lambda t: t.replace('  ApiNoteClear;\n  EarlyApiFwDone := True;', '  EarlyApiFwDone := True;')),
    ('a deleted configuration leaves the note',
     lambda t: re.sub(r"if not FileExists\(AddBackslash\(DataPath\) \+ 'sd.conf'\) then\s*ApiNoteClear;", '', t)),
    ('a missing tree leaves the note',
     lambda t: t.replace('    RemoveSdUsersGroup;\n    ApiNoteClear;', '    RemoveSdUsersGroup;')),
    ('the put-back restricts instead of opening',
     lambda t: t.replace("api-firewall.ps1') + '\" -Open';", "api-firewall.ps1') + '\" -Restrict';")),
    ('the save writes whatever scope it read',
     lambda t: t.replace("if GetApiRuleScope = 'open' then", "if GetApiRuleScope <> '' then")),
]


def main():
    if not os.path.isfile(ISS):
        print('NO TREE: %s is not here' % ISS)
        return 2
    with open(ISS, 'r', encoding='utf-8', errors='replace', newline='') as f:
        text = f.read()
    print('sd.iss: %s  (%d bytes)' % (ISS, len(text)))
    fails = 0
    bad = checks(text)
    if bad:
        for b in bad:
            print('FAIL  %s' % b)
        fails += len(bad)
    else:
        print('PASS  every structural check on the live sd.iss')
    for name, mut in MUTANTS:
        m = mut(text)
        if m == text:
            print('FAIL  mutant did not apply (anchor drifted): %s' % name)
            fails += 1
            continue
        caught = checks(m)
        if caught:
            print('PASS  mutant caught (%d check%s red): %s' % (len(caught), '' if len(caught) == 1 else 's', name))
        else:
            print('FAIL  mutant NOT caught: %s' % name)
            fails += 1
    print('')
    if fails == 0:
        print('apikeep units: ALL PASS (%d mutants, all caught)' % len(MUTANTS))
        return 0
    print('apikeep units: %d FAILED' % fails)
    return 1


if __name__ == '__main__':
    sys.exit(main())
