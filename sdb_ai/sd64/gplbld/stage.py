#
# stage.py - assemble the staging tree for a Windows install
#
# command line: python3 gplbld/stage.py [--stage DIR] [--msys DIR] [--force]
# eg  cd sdb_ai/sd64 && make sd && python3 gplbld/stage.py --stage ../../stage
#
# Produces two directories, which are what an install consists of:
#
#   <stage>/ProgramFiles/   ->  C:\Program Files\SD\
#   <stage>/ProgramData/    ->  C:\ProgramData\SD\
#
# THE usr/bin LAYOUT IS NOT COSMETIC.  The executables go in usr\bin, mirroring
# MSYS2's own tree, because shipping msys-2.0.dll beside sd.exe relocates the
# entire POSIX namespace: the runtime derives its root by stripping TWO path
# components from the directory holding the DLL.  Measured, not guessed - see
# the trap in PROJECT_STATUS.md 6.  So DLLs in C:\Program Files\SD\usr\bin put
# the root at C:\Program Files\SD\, and everything POSIX stays inside SD's own
# directory.  Put them one level up, in C:\Program Files\SD\bin, and the root
# becomes C:\Program Files\ - which would mean creating C:\Program Files\dev.
#
# etc\fstab then maps /dev/shm back out to C:\ProgramData\SD\shm.  It has to
# leave Program Files: shm_open() creates files under /dev/shm, so every SD
# user needs write access to it, and Program Files is read-only to ordinary
# users by design.  Without /dev/shm the runtime warns and POSIX shared memory
# fails, which is the whole IPC layer (5.1).
#
# and <stage>/MANIFEST.txt, which is deliberately outside both of them so that
# packaging never picks it up.  Diff two manifests to see what an install
# gained or lost between builds.
#
# This script does not build.  Run "make sd" first; it checks for the artefacts
# and stops if they are missing.  It does not install either - it only lays out
# a tree that the Inno Setup script packages.  See PROJECT_STATUS.md 5.9.
#
# WITH --bootstrap IT ALSO RUNS THE BOOTSTRAP, and that is what makes the tree
# installable.  Staged cold, gcat, cat, gpl.bp.out, bp.out and pcode.out are
# empty, so the end user has to run the sequence in PROJECT_STATUS.md 3 - which
# needs Python, and needs gplbld/ inside the data tree that the
# data-tree-holds-data-only decision forbids.  It could not have worked anyway:
# gplbld/ was not staged at all, so the inputs were simply missing.  Running the
# bootstrap here and shipping the result means the end user needs neither Python
# nor a compiler, and installing is a file copy.  See PROJECT_STATUS.md 5.16.
#
# WHY THIS IS A WHITELIST.  Everything copied is named in SDSYS_SHIP or
# SDSYS_EMPTY below.  Nothing is copied because it happened to be in the source
# tree.  That is the point of the script rather than an implementation detail:
# the Linux installer did "cp -R" over whole directories, which is how gplsrc
# came to sit in the installed database for years without anyone asking why.
# If SD turns out to need something that is not on these lists, an install made
# from this tree fails and we learn what the dependency is.  Add it here
# deliberately, with a reason, or fix the dependency.
#
# The MSYS2 DLLs are the exception, and they are computed rather than listed -
# see dll_closure().  A hand-maintained list of DLLs goes stale silently and
# the symptom is exit code 53 with no message at all (PROJECT_STATUS.md 6).
#

import argparse
import os
import re
import shutil
import subprocess
import sys

# The bootstrap's own elevation test, imported rather than copied - gplbld is
# sys.path[0] whenever this script is run.  One test, one place: if the way
# elevation is measured ever changes, both callers change with it.
from bootstrap import is_elevated

# ---------------------------------------------------------------------------
# What goes into C:\Program Files\SD\
# ---------------------------------------------------------------------------

# Built by "make sd" into sd64/bin.  The DLLs these need are worked out by
# dll_closure() and land beside them, because Windows searches an executable's
# own directory before PATH - which is the only reliable answer to the two PATH
# traps in PROJECT_STATUS.md 6, one of which is Git for Windows shipping a
# rival msys-2.0.dll.
PROGRAM_FILES_BIN = [
    'sd.exe',
    'sdconv.exe',
    'sdfix.exe',
    'sdidx.exe',
    'sdwind.exe',
    'sdtic.exe',
    'sdclilib.dll',             # native UCRT64, needs no MSYS2 runtime
    'libsdclilib.dll.a',        # import library, for building clients
    'sdsvc.exe',                # native UCRT64, the service that starts SD
]

# Scanned for imports.  The client DLL and the service are deliberately not in
# this list: both are the separate native toolchain (5.3) and depend on nothing
# but Windows system DLLs, which was confirmed rather than assumed - objdump on
# sdsvc.exe, 15 Aug 2026, names only ADVAPI32, KERNEL32 and the UCRT
# api-ms-win-crt-* set, and no msys-2.0.dll.
DLL_SCAN = [
    'sd.exe', 'sdconv.exe', 'sdfix.exe', 'sdidx.exe', 'sdwind.exe', 'sdtic.exe',
]

# Where a DLL may legitimately come from.  Anything resolved outside these is
# taken to be a Windows system DLL and is reported, not copied.  libsodium is
# in /usr/local/bin because it is built from source (PROJECT_STATUS.md 2).
DLL_SEARCH = [
    os.path.join('usr', 'bin'),
    os.path.join('usr', 'local', 'bin'),
]

# ---------------------------------------------------------------------------
# What goes into C:\ProgramData\SD\sdsys\  - the SDSYS account
# ---------------------------------------------------------------------------

# Copied from sd64/sdsys.  Each entry says why it ships, because the next
# person to read this list will be deciding whether to remove something.
SDSYS_SHIP = [
    ('gpl.bp',        'BASIC source; SECOND.COMPILE compiles the lot of it'),
    ('syscom',        'include records the compile needs'),
    # 15 Aug 26 - THESE TWO DESCRIPTIONS WERE THE WRONG WAY ROUND, and they are
    # the first thing read by anyone adding a verb.  voc_template is the
    # ADMINISTRATIVE superset that becomes SDSYS's own VOC; newvoc is the
    # smaller set CREATEA copies into each new account (CREATEA:520).  The
    # difference is deliberate access control - CREATE.ACCOUNT, DELETE.ACCOUNT,
    # accounts and FIRST.COMPILE are in voc_template and NOT in newvoc, so an
    # ordinary account cannot reach them at all.  A new administrative verb
    # therefore goes in voc_template ONLY; putting it in newvoc hands it to
    # every account SD creates.
    # 17 Aug 26 - AND THAT RULE STILL HOLDS AFTER THE VOC TIERS, which is why
    # CREATEA gives an ADMINISTRATOR account its nine administration verbs by
    # reading them OUT of voc_template rather than by moving them into newvoc.
    # The tier lists in newvoc (TIER.OMIT.STANDARD, TIER.ADD.ADMINISTRATOR) fail
    # safe only in that direction: a lost or empty omit list is read as "no
    # policy" and gives the full VOC, which is harmless while newvoc holds
    # nothing administrative and hands out CREATE.ACCOUNT the moment it does.
    # PROJECT_STATUS.md section 8.
    ('newvoc',        'the VOC a newly created account is given'),
    ('voc_template',  "the administrative superset; becomes SDSYS's own VOC"),
    ('messages',      'sysmsg() text'),
    ('sd.voclib',     'library routines'),
    ('accounts',      'holds the SDSYS record; the bootstrap adds to it'),
    # 25 Aug 26 - bp IS NO LONGER ON THIS LIST.  SD ships NOTHING into SDSYS's
    # own BP now; see SDSYS_EMPTY and SDSYS_PRESERVE below.  The 24 Aug note
    # that stood here is kept there, with what became of the five programs.
    # 25 Aug 26 - CHANGELOG IS NO LONGER ON THIS LIST.  It used to ship into
    # the data tree, which the installer never overwrote, so a user's changelog
    # was frozen at their install date - in the one file whose entire job is
    # telling them what changed.  Owner ruled it moves to {app}, where Inno
    # replaces it on upgrade and removes it on uninstall with no custom code at
    # all, so it is right whatever the data-tree upgrade below does.  It is
    # copied to ProgramFiles further down; the SOURCE stays at sdsys/changelog
    # because that is where every session has edited it for months and moving
    # it would break the standing instruction's muscle memory for no gain.
    ('licence',       'GPL-3.0'),
    ('contrib',       'contributor list, reachable as CONFIG CONTRIB'),
]

# Created empty, and filled by the bootstrap when --bootstrap is given.  Their
# README placeholders are not shipped - that would put files in a database.
SDSYS_EMPTY = [
    ('gpl.bp.out',  'compiled objects from SECOND.COMPILE'),
    # 25 Aug 26 - bp AND bp.out ARE BOTH CREATED EMPTY AND BOTH PRESERVED, and
    # the pair is the whole point.
    #
    # WHAT CHANGED.  Until today SD shipped five programs into SDSYS's own BP -
    # PCL and PCL.GRID (printer control), U0032 and U50BB (user exits), VFS.CLS
    # (a template VFS class module).  Owner's ruling, 25 Aug 2026: they are not
    # needed in this version, and VFS is not a supported feature, so shipping a
    # template for one is worse than shipping nothing.  gpl.bp/PCL is the PCL
    # that is actually compiled and catalogued; sdsys/bp/PCL was a second,
    # divergent copy of it.
    #
    # THE DIRECTORY STILL HAS TO EXIST.  voc_template/bp is an F-pointer, so
    # every account's VOC resolves BP through it, and sd.iss ACLs
    # sdsys\bp through secure-sysdirs.ps1.  Created, then, but empty.
    #
    # AND BOTH ARE PRESERVED, WHICH IS WHAT THE CYCLE OF 25 Aug 2026 FORCED.
    # bp.out was on the upgrade REPLACE list while staging empty, and stage.py
    # refused the build for it - correctly: an upgrade would have deleted the
    # installed objects and copied nothing back.  Now that SD ships nothing
    # into either, anything in them on a live machine was put there by the
    # site, which makes them the user's.  That is exactly the argument that
    # keeps 'cat' - the private catalogue - on the preserve list.
    ('bp',          "SDSYS's own BP - SD ships nothing into it; the site may"),
    ('bp.out',      'its compiled objects; nothing compiles into it at install'),
    ('gcat',        'global catalogue; the bootstrap touches $CPROC here first'),
    ('cat',         'private catalogue'),
    ('pcode.out',   'pcode_bld.py output'),
    ('$hold',       'spooler hold file'),
    ('prt',         'print queue'),
    ('bin',         'NOT the executables - the pcode library lives here, see below'),
    # 17 Aug 26 - THE CREDENTIAL STORE, AND NOTHING CREATED IT UNTIL NOW.  The
    # comment below used to list $cred among the files "the bootstrap and the
    # running system create for themselves", and that was simply wrong: sd -i
    # creates VOC, voc.dic, accounts.dic, $map and dict.dic and no more, and
    # CRED_SET opens $cred without creating it.  So SET.PASSWORD failed on
    # every install ever made with "Cannot open the $cred register", which
    # nobody saw because no VOC pointed at SET.PASSWORD until 17 Aug 2026.
    # A directory file, the same shape as accounts - an empty directory is
    # one.  secure-cred.ps1 locks it once the tree ACL is on.
    ('$cred',       'credential store: per-account salt and Argon2 verifier'),
    # 17 Aug 26 - SHELL PERMISSION, PROJECT_STATUS.md 7 step 7.  Both are
    # directory files and BOTH have to be here, because WRITE_INSTALL_DICTS
    # OPENPATHs the dictionary rather than creating it - the bootstrap would
    # skip the entries with "ERROR OPENING FILE" and the file would ship with
    # no dictionary, so LIST and ED would not resolve a field.
    #
    # os.users SHIPS EMPTY AND THAT IS THE SAFE DIRECTION: no record means no
    # account has shell access, which is the behaviour before this existed.
    # It is the opposite of the tier lists, where a missing record means the
    # FULL VOC (CREATEA) - do not copy that convention here.
    #
    # secure-osusers.ps1 locks it once the tree ACL is on, read-only to
    # sdusers.  Without that lock any SD user could add their own name, and
    # the file would be decoration rather than a control - which is exactly
    # what happened to $cred above.
    ('os.users',     'accounts permitted SH and/or OS.EXECUTE'),
    ('os.users.dic', 'its dictionary; WRITE_INSTALL_DICTS fills it'),
    # 22 Aug 26 - THE BATCH COMMAND LIST, PROJECT_STATUS.md 7 step 9.  Same
    # three properties as os.users above and for the same reasons: both files
    # here because WRITE_INSTALL_DICTS opens the dictionary rather than
    # creating it; SHIPS EMPTY, so no account may run anything from the
    # command line until an administrator says so; and locked read-only to
    # sdusers afterwards, by the same secure-osusers.ps1.
    #
    # LOGIN reads it from the USER'S OWN process, which is why they must be
    # able to read it and must never be able to write it - a user who can add
    # a line grants themselves the command line.
    ('batch.jobs',     'commands each account may run from the command line'),
    ('batch.jobs.dic', 'its dictionary; WRITE_INSTALL_DICTS fills it'),
]

# sd64/terminfo is generated by "make terminfo" and is not tracked, so it is
# staged from wherever it was built.  terminfo.src ships with it so that sdtic
# can add a terminal type on an installed system; it is 64K.
TERMINFO_DIRS = [('terminfo', 'compiled terminfo, 100 files')]
TERMINFO_FILES = [('terminfo.src', 'source, so sdtic is usable after install')]

# ---------------------------------------------------------------------------
# What an UPGRADE must not touch.  Owner's ruling, 25 Aug 2026: preserve the
# user's own files, replace all the shipped ones.  write_upgrade_iss() below
# turns this into the installer's [InstallDelete] and [Files] entries.
#
# THE REPLACE LIST IS COMPUTED FROM THE LISTS ABOVE MINUS THIS ONE, AND THAT
# IS THE SAFETY PROPERTY, not an implementation detail.  Only a name this file
# deliberately puts in the tree can ever be a candidate for deletion.
# Everything the BOOTSTRAP and the RUNNING SYSTEM create - voc, voc.dic,
# dict.dic, accounts.dic, $map, $map.dic, $ipc, errlog, stacks, dir_dict - is
# in neither list, so an upgrade cannot reach it however this file is edited.
# A preserve list applied to os.listdir() would have had the opposite default:
# a directory nobody had thought of would be deleted.
#
# $cred IS THE ONE THAT MUST NOT BE MISSED.  Losing it is not "reinstall and
# carry on" - every account becomes unreachable over ssh and the API, which is
# the state a silent install produced once and which took two sessions to
# diagnose.  A straight port of the Linux deletesd.sh, which preserves only
# ACCOUNTS and the config, would do exactly that.
#
# THREE NAMES HERE ARE WIDER THAN THE RULING'S OWN WORDING, deliberately, and
# they are flagged rather than folded in silently.  The ruling named $cred,
# accounts, os.users, cat, batch.jobs, prt and sd.conf.  os.users.dic and
# batch.jobs.dic are added because a dictionary belongs with the file it
# describes, and $hold because the spooler hold file is the user's own saved
# report output - replacing it would throw away work.
# ---------------------------------------------------------------------------
# Which sdsys directories are a VERBATIM copy of the source tree.
#
# assert-current.ps1 reads this with --list-mirrors, and it is the whole of
# what makes a DELETION visible.  That script walks source -> install and asks
# "is this file installed"; nothing walked the other way, so a file the install
# has and source no longer does was invisible and a deletion-only commit
# reported the tree current.  It had already happened twice, silently.
#
# THE NAIVE FIX CRIES WOLF FOR EVER, which is why the gap sat open: walking the
# whole install and flagging anything not in source flags gcat, gpl.bp.out,
# voc, errlog, every account and the entire runtime.  A guard that always fires
# is worse than the gap it closes.  A directory qualifies here only if the
# install NEVER writes into it, so "installed but not in source" can only mean
# a deletion that has not shipped.
#
# MEASURED 25 Aug 2026 AGAINST A REAL INSTALL, not reasoned about.  Comparing
# each SDSYS_SHIP directory in C:\ProgramData\SD\sdsys against sdb_ai/sd64/sdsys
# gave, for installed-files-not-in-source:
#
#     gpl.bp 0/198   syscom 0/15   newvoc 0/394   voc_template 0/424
#     messages 0/1909   sd.voclib 0/10   bp 0/5      accounts 17/18
#
# ***accounts IS THE ONE THAT DISQUALIFIES ITSELF AND IT IS NOT ON THIS LIST.***
# It ships holding the SDSYS record and then accumulates every account the user
# creates - the 17 were "don" and sixteen test accounts from the b38 runs.
# Listing it would report a stale tree on every machine that had ever created
# an account, which is every machine.
#
# licence and contrib are FILES rather than directories, so there is nothing
# to walk; section B's source -> install pass already covers a file.
SDSYS_MIRROR = [
    ('gpl.bp',       'BASIC source; nothing writes it at runtime'),
    ('syscom',       'include records'),
    ('newvoc',       'read by CREATEA; never written'),
    ('voc_template', 'read by CREATEA and UPDATE.ACCOUNT; never written'),
    ('messages',     'sysmsg text'),
    ('sd.voclib',    'library routines'),
    ('bp',           "SDSYS's own BP - five utility programs"),
]

# Names this file USED to put in the data tree and no longer does.  An upgrade
# deletes them; a first install never creates them, so there is nothing else to
# do.  DELETE-ONLY, and the one place write_upgrade_iss() emits half a pair on
# purpose - there is deliberately nothing to copy back.
#
# IT EXISTS SO THAT RETIRING A FILE IS A ONE-LINE CHANGE rather than a note in
# the changelog asking the user to delete something by hand.  A name here must
# NOT also be on a ship list; that contradiction is checked, because the two
# halves would fight over the same path on every upgrade.
SDSYS_RETIRED = [
    ('changelog', 'moved to {app} on 25 Aug 26 - see the note on SDSYS_SHIP'),
]

# The same thing for C:\Program Files\SD.  A script this file used to copy
# there and no longer does.
#
# ***{app} IS NOT SELF-CLEANING AND THE COMMENT IN sd.iss USED TO SAY IT WAS.***
# Inno's [Files] copies and overwrites; it does NOT remove a file that is absent
# from the new version - that is the whole reason [InstallDelete] exists.  So a
# retired script sits in C:\Program Files\SD until somebody uninstalls, and the
# exposure is a stale .ps1 that nothing invokes but that an administrator can
# still find and run.
#
# THESE ENTRIES ARE NOT GATED ON AN UPGRADE, unlike SDSYS_RETIRED.  A retired
# name can only be present if a previous version put it there, so on a first
# install the delete matches nothing and costs nothing - and gating it would
# mean trusting DataTreeWasAbsent to answer a question about {app}, which is a
# different directory with a different lifecycle.
#
# EMPTY IS THE CORRECT STATE TODAY, measured 25 Aug 2026: every .ps1 in
# C:\Program Files\SD is still named in this file.  assert-current section B4
# is what will say when that stops being true.
PF_RETIRED = [
]

SDSYS_PRESERVE = [
    ('$cred',          'the credential register - every account password'),
    ('accounts',       'the account register; ships with SDSYS and then grows'),
    ('cat',            'the private catalogue - what the user catalogued'),
    ('os.users',       'SD account to Windows account links'),
    ('os.users.dic',   'its dictionary; goes with the file it describes'),
    ('batch.jobs',     'which commands each account may run'),
    ('batch.jobs.dic', 'its dictionary; goes with the file it describes'),
    ('prt',            'the print queue'),
    ('$hold',          "the spooler hold file - the user's saved output"),
    # 25 Aug 26 - see the note at their SDSYS_EMPTY entries.  SD ships nothing
    # into either, so anything in them belongs to the site.  bp.out being on
    # the replace list while staging empty is what stage.py refused on
    # 25 Aug 2026, and it was right to.
    ('bp',             "SDSYS's own BP - programs the site wrote"),
    ('bp.out',         'their compiled objects'),
]

# Directories the bootstrap and the running system create for themselves, listed
# so nobody adds them to SDSYS_EMPTY on the assumption they were forgotten:
#   stacks  dir_dict  voc  voc.dic  dict.dic  accounts.dic  $map  $map.dic
#   $ipc  errlog
# $cred is NOT among them and never was - see SDSYS_EMPTY above.

# Empty account roots.  Three siblings under one root is what makes a single
# icacls with inheritance enough (PROJECT_STATUS.md 5.8).  "shm" is the fourth,
# and it is the target of the fstab mapping above rather than an account.
PROGRAM_DATA_DIRS = ['user_accounts', 'group_accounts', 'shm']

# Where the binaries sit inside C:\Program Files\SD\.  Two components, so the
# MSYS2 POSIX root lands on C:\Program Files\SD\ - see the header.
PF_BIN_SUBDIR = os.path.join('usr', 'bin')

# Where the data tree lives once installed.  The bootstrap is run against the
# staging directory rather than here - a build must not depend on, or write to,
# the build machine's own installed system - so the SDSYS account record comes
# out holding the staging path and is rewritten to this afterwards.  That is
# safe because accounts/sdsys is the ONLY place an absolute path is embedded,
# and stage.py proves it rather than trusting it: see check_no_stage_paths().
PRODUCTION_SDSYS = r'C:\ProgramData\SD\sdsys'

# Field 1 of an accounts record is the account's directory.
#
# accounts is a DIRECTORY-type SD file, so each record is a plain text file and
# its field marks are NEWLINES, not the \xfe field mark used inside a DH file.
# Splitting on \xfe finds nothing, leaves the whole record as field 1, and
# rewriting it then flattens the record to one line - silently discarding every
# field after the path, the account's Windows group among them.  Verified
# against the bytes on disk rather than assumed, after doing exactly that once.
FM = '\n'

# /dev/shm must be writable by every SD user, so it cannot live under Program
# Files.  Cygwin reads <root>\etc\fstab, and a bind entry moves it.
FSTAB = ('# Generated by gplbld/stage.py.  See PROJECT_STATUS.md 5.8.\n'
         '#\n'
         '# /dev/shm must be writable by every SD user - shm_open() creates\n'
         '# files in it - and Program Files is not.  Without this mapping the\n'
         '# runtime warns that /dev/shm is missing and all POSIX shared memory\n'
         '# fails, which is the whole IPC layer.\n'
         'C:/ProgramData/SD/shm /dev/shm ntfs binary 0 0\n')

SD_CONF = """[sd]
SDSYS=C:\\ProgramData\\SD\\sdsys
GRPSIZE=2
NUMUSERS=20
SORTMEM=4096
ERRLOG=50
APILOGIN=1
# APIPORT is the port SD listens on for API (SDClient) connections.  4243 is
# the number the Linux build uses.
#
# 21 Aug 26 Windows port - ON BY DEFAULT, AND IT NOW FACES THE NETWORK.
# Owner's decision, 21 Aug 2026: the API is reached AT THE PORT and the ssh
# tunnel is no longer part of the design, so a port nobody can reach is not a
# posture - it is a broken feature.  gplsrc/sdwind.c binds every interface.
#
# THIS IS THE THIRD TIME THIS DEFAULT HAS MOVED and the reasons are worth
# keeping, because two of them were right when they were written:
#
#   17 Aug  on   - the API is the point of the port (5.15)
#   20 Aug  off  - AN API SESSION RUNS AS LocalSystem.  Measured that day by
#                  verify-apiadmin.ps1: a PROGRAMMER-tier account, over a
#                  remote API connection, OPENED AND WROTE $cred - the
#                  credential store - and reported itself nt_authority\\system.
#                  Shipping that on by default put a privilege escalation from
#                  "holds an SD credential" to "is SYSTEM" on every install.
#   21 Aug  on   - that specific escalation is CLOSED.  The containment gate
#                  in op_dio2.c makes the account the session stands in its
#                  root, and kernel.c no longer grants USR_ADMIN to a socket
#                  session.  Re-measured the same day, from inside a real
#                  remote API session: $cred refused with ER_PERM (3035), and
#                  OS.EXECUTE refused by name.  22 PASS + 1 N/A of 23.
#
# WHAT IS STILL OPEN, so this is a judgement and not a clean bill: the
# session's TOKEN is still LocalSystem - sdwind fork()s it and Windows has no
# setuid.  What changed is its REACH, not its identity.
#
# WHAT GUARDS THE PORT.  A caller must complete a SCRAM-SHA-256 exchange
# against a credential in $cred - which an account only has once a password
# has been set for it - then be a member of sdapi, then pass the account's
# group check.  The firewall rule is gplbld/api-firewall.ps1, and narrowing
# WHO may reach the port is done there rather than here: one bind address in a
# config file is a way to get this wrong by accident in either direction.
#
# TO TURN IT OFF, comment the line below out.  Changing it takes effect when
# SD is next started, not when a session begins.
APIPORT=4243
# NETDIRS says which directories OUTSIDE ITS OWN ACCOUNT a session that arrived
# over the API may reach.  IT IS COMMENTED OUT ON PURPOSE and the empty value is
# the strict one: with nothing here, an API session can open files in the
# account it is standing in, and nothing else.
#
# 21 Aug 26 Windows port - WHY IT EXISTS.  Until now a session arriving over the
# API could open any file on the machine, including SDSYS/$cred, the credential
# store - measured, from a remote client, holding nothing but an ordinary
# account's password.  Sessions at the keyboard and over ssh are unaffected by
# this parameter; only API sessions are confined.
#
# THE SHIPPED SDSYS FILES A NORMAL ACCOUNT NEEDS ARE ALWAYS REACHABLE and do not
# have to be listed - the VOC entries every account has (messages, syscom, the
# dictionaries, sd.voclib) keep working.  $cred, gcat, os.users and the account
# register are never reachable, and cannot be added here.
#
# LIST A DIRECTORY HERE ONLY IF YOUR DATA LIVES OUTSIDE AN ACCOUNT - a shared
# data directory that VOC F-records point at, typically.  Separate several with
# a SEMICOLON, because a Windows pathname contains a colon:
#
#     NETDIRS=D:\\shared\\data;E:\\archive
#
# A directory named here is reachable by EVERY API session in every account, so
# it is a decision about the machine and not about one account.
#
# Changing it takes effect when SD is next started, not when a session begins.
# NETDIRS=
USRDIR=C:\\ProgramData\\SD\\user_accounts
GRPDIR=C:\\ProgramData\\SD\\group_accounts
SH=C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NoLogo
SH1=C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
"""

# 25 Aug 26 - THE STAND-ALONE VARIANT, DERIVED FROM SD_CONF AND NEVER WRITTEN
# OUT SEPARATELY.
#
# A stand-alone install opens no network port at all, which is a real state
# rather than a firewall rule: gplsrc/sdwind.c open_api_listener() returns -1
# for "no listener" when the port is <= 0, and its own comment says "a system
# whose sd.conf has no APIPORT opens no port at all".  So APIPORT must be
# absent, not set to 0 and not left to the firewall.
#
# WHY A replace() AND NOT A SECOND STRING.  SD_CONF is ~90 lines of settings and
# reasoning that the two installs share completely.  A second literal would be a
# second copy to keep in step, and everything this repository has learned about
# two copies of one fact says it drifts - the four rewordings of the installer's
# own disclosure page are the same lesson.  The two differ in ONE line, so one
# line is what is expressed here.
#
# THE REPLACEMENT IS ASSERTED, NOT ASSUMED.  If SD_CONF's APIPORT line is ever
# reworded, a silent no-op replace would ship a stand-alone system with the API
# listening - the exact thing the wizard page promises it does not do.  So
# sd_conf_standalone() refuses rather than returning something plausible.
APIPORT_LINE = 'APIPORT=4243'

STANDALONE_APIPORT = """\
# 25 Aug 26 - NOT SET, AND THAT IS WHAT MAKES THIS A STAND-ALONE SYSTEM.
# With no APIPORT, SD opens no socket at all - see gplsrc/sdwind.c,
# open_api_listener().  The SD API is therefore unavailable on this machine and
# there is no firewall rule that could make it available.
#
# Setting it turns the API on the next time SD starts, but nothing else here is
# set up for it: no firewall rule was created and no account was joined to the
# sdapi group, because a stand-alone install does neither.
# APIPORT=4243"""


def _active_apiport(text):
    """The APIPORT lines that are SETTINGS, not comments about settings.

    LINE-WISE, AND THAT IS THE POINT.  The first version of this tested
    `APIPORT_LINE in out` and the commented-out replacement CONTAINS that
    substring - so the guard fired on its own success and refused every build.
    It is the trap CLAUDE.md names: a check has to anchor on something only the
    real outcome produces, not on a string the other outcome also carries.
    """
    return [l for l in text.split('\n') if l.strip() == APIPORT_LINE]


def sd_conf_standalone():
    """SD_CONF with APIPORT commented out.  Refuses if the line is not there."""
    if len(_active_apiport(SD_CONF)) != 1:
        die('SD_CONF must contain exactly one active %r line - the stand-alone '
            'sd.conf is derived from it by commenting that line out, and a '
            'silent miss would ship a stand-alone install with the API '
            'listening, which is the one thing its wizard page promises it '
            'does not do' % APIPORT_LINE)
    out = SD_CONF.replace(APIPORT_LINE + '\n', STANDALONE_APIPORT + '\n', 1)
    if _active_apiport(out):
        die('the stand-alone sd.conf still carries an active %r line'
            % APIPORT_LINE)
    return out


# ---------------------------------------------------------------------------


def check_no_stage_paths(stage, sdsys, allowed):
    r"""After the bootstrap, no file in the staged tree may mention the staging
    directory except the ones we know rewrite cleanly.

    This is the invariant the whole pre-bootstrap idea rests on.  Bootstrapping
    here rather than at C:\ProgramData\SD\sdsys means anything that recorded
    an absolute path recorded the WRONG one, and only accounts/sdsys is known
    to do that.  "Known" was a sweep somebody did once, which is exactly the
    kind of claim that quietly stops being true - so it is checked on every
    build instead.  If this fires, do not add the file to `allowed` without
    working out whether the path can be rewritten as safely.
    """
    needles = [stage, os.path.abspath(stage)]
    needles += [n.replace(os.sep, '/') for n in list(needles)]
    needles = sorted({n.lower() for n in needles if n})

    offenders = []
    for base, _dirs, names in os.walk(sdsys):
        for n in names:
            path = os.path.join(base, n)
            if os.path.relpath(path, sdsys).replace(os.sep, '/') in allowed:
                continue
            try:
                with open(path, 'rb') as f:
                    blob = f.read().decode('latin-1').replace('\\', '/').lower()
            except (IOError, OSError):
                continue
            if any(nd in blob for nd in needles):
                offenders.append(os.path.relpath(path, sdsys))
    return offenders


def check_bootstrap_complete(sdsys):
    r"""Refuse a staged tree whose bootstrap stopped after the seed phase.

    THIS EXISTS BECAUSE AN EXIT CODE OF 0 WAS NOT ENOUGH.  On 16 Aug 2026 an
    installer was built from a tree in exactly this state, installed, and
    nothing noticed until a session was tried on it a day later: every static
    file was present and correct, so the tree looked whole, but gcat held the
    4 objects bbcmp.py compiles to seed the bootstrap instead of 132, and
    gcat/$CPROC was the 0-byte placeholder bootstrap.py touches so that
    read_config()'s access() check passes before anything is catalogued.  SD
    cannot start a session on such a tree: it dies "Unable to load '$CPROC'
    object code" with an access violation, which reads as a corrupt binary.

    assert-current.ps1 CANNOT COVER THIS.  It compares an install against
    SOURCE, and gcat, gpl.bp.out and voc are build products with no source
    counterpart, so it exited 0 over the broken tree.  The check has to be
    here, at the moment the tree is built, against what the bootstrap created.

    Counting the whole tree is a poor instrument - the shortfall was 3,139
    files against 3,475, which reads as rounding.  These five do not.
    """
    def n(sub):
        d = os.path.join(sdsys, sub)
        return len(os.listdir(d)) if os.path.isdir(d) else 0

    cproc = os.path.join(sdsys, 'gcat', '$CPROC')
    cproc_sz = os.path.getsize(cproc) if os.path.isfile(cproc) else -1

    faults = []
    if cproc_sz <= 0:
        faults.append('gcat/$CPROC is %s - the bootstrap touches it empty and '
                      'the LAST step overwrites it, so this is the decisive one'
                      % ('absent' if cproc_sz < 0 else '0 bytes'))
    if not os.path.isfile(os.path.join(sdsys, 'gcat', '$LOGIN')):
        faults.append('gcat/$LOGIN is absent - nothing could log in')
    if n('gcat') < 100:
        faults.append('gcat holds %d entries, expected ~132' % n('gcat'))
    if n('gpl.bp.out') < 150:
        faults.append('gpl.bp.out holds %d objects, expected ~190' % n('gpl.bp.out'))
    if not os.path.isdir(os.path.join(sdsys, 'voc')):
        faults.append("VOC is absent - 'sd -i' did not complete")
    return faults


def retarget_sdsys_account(sdsys, production):
    """Point the SDSYS accounts record at a directory, and return the old one.

    Field 1 of an accounts record is the account directory, and IT IS WHERE
    gpl.bp AND gpl.bp.out RESOLVE TO once a session has logged in.  So this is
    called TWICE: at the staged tree before the bootstrap, or the bootstrap
    compiles somebody else's sources, and at the production path afterwards, so
    the install does not carry a build path.  Rewriting one field is the entire
    cost of pre-bootstrapping - see PROJECT_STATUS.md 5.16.

    The tracked record ships holding /usr/local/sdsys, the Linux development
    tree, which is what made the first call necessary: on this machine the
    bootstrap silently compiled 190 programs there and catalogued them into the
    staged gcat, and on a clean machine that path does not exist at all.
    """
    rec = os.path.join(sdsys, 'accounts', 'sdsys')
    if not os.path.isfile(rec):
        die('there is no accounts/sdsys record in %s' % sdsys)
    with open(rec, 'rb') as f:
        fields = f.read().decode('latin-1').split(FM)
    was = fields[0]
    fields[0] = production
    with open(rec, 'wb') as f:
        f.write(FM.join(fields).encode('latin-1'))
    return was


class Staged(object):
    """Records what was written, so the manifest and the summary agree with the
    tree rather than with what the script meant to do."""

    def __init__(self):
        self.files = []

    def add(self, root, path):
        self.files.append((os.path.relpath(path, root).replace('\\', '/'),
                           os.path.getsize(path)))

    def scan(self, root, path):
        for base, _dirs, names in os.walk(path):
            for n in sorted(names):
                self.add(root, os.path.join(base, n))


def die(msg):
    sys.exit('stage: ' + msg)


def imports_of(objdump, path):
    """Direct DLL imports of one PE file.  objdump -p is used rather than ldd
    because it reads the import table instead of loading the binary: it gives
    the same answer on a machine that could not run it, and it does not depend
    on the loader's search order."""
    out = subprocess.run([objdump, '-p', path], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, universal_newlines=True)
    return re.findall(r'^\tDLL Name:\s*(\S+)', out.stdout, re.M)


def dll_closure(objdump, binaries, msys_root):
    """Walk imports transitively.  Direct imports are not enough: sd.exe names
    five DLLs, but msys-intl-8, msys-iconv-2 and msys-gcc_s-seh-1 arrive only
    through the DLLs it does name, and missing one of those is exit code 53
    with no message."""
    search = [os.path.join(msys_root, d) for d in DLL_SEARCH]
    for d in search:
        if not os.path.isdir(d):
            die('no such directory %s - is --msys right?' % d)

    found, system, pending, seen = {}, set(), list(binaries), set()
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        for name in imports_of(objdump, path):
            if name.lower() in found or name.lower() in system:
                continue
            for d in search:
                cand = os.path.join(d, name)
                if os.path.isfile(cand):
                    found[name.lower()] = cand
                    pending.append(cand)
                    break
            else:
                system.add(name.lower())        # Windows supplies it
    return found, system


def copy_tree(src, dst, staged, stage_root):
    shutil.copytree(src, dst)
    staged.scan(stage_root, dst)


# RAW STRINGS, and not as a style preference.  This text is full of Windows
# paths, and "C:\\Program Files" in an ordinary literal is \\P - an invalid
# escape, which is a SyntaxWarning today and an error in a later Python.
# "C:\\temp" would be worse: \\t is a tab and it fails silently.  CLAUDE.md has
# the rule; this block is where it bites, because the strings are prose.
#
# AND THE OPENING QUOTE HAS NO "\" AFTER IT, which it did for about a minute.
# In an ordinary literal '''\ swallows the newline; in a RAW one it is a
# literal backslash, so the generated file began with a bare "\" line and ISCC
# answered 'Unrecognized parameter name "\"' on line 1.  Caught by compiling
# the generated file, which is the only thing that would have.
UPGRADE_HEADER = r'''; upgrade.iss - GENERATED BY gplbld/stage.py.  DO NOT EDIT AND DO NOT COMMIT.
;
; The entries that let a NEW installer refresh an EXISTING data tree in place.
; sd.iss includes this file; ISCC fails if it is absent, which is deliberate.
;
; THE RULE, owner 25 Aug 2026: preserve the user's own files, replace all the
; shipped ones.  The [Files] entry in sd.iss with Check: DataTreeAbsent lays
; down the whole tree on a FIRST install; everything here runs only on the
; other branch, Check: DataTreeUpgrade.
;
; WHY THIS FILE IS GENERATED RATHER THAN WRITTEN.  The list of shipped names
; is SDSYS_SHIP + SDSYS_EMPTY + the terminfo pair in stage.py, minus
; SDSYS_PRESERVE.  Hand-copying it here would give two lists that must agree,
; and the one that goes stale silently deletes a user's data - the same
; reasoning that made the MSYS2 DLL closure computed rather than listed.
;
; DELETE AND COPY ARE EMITTED AS A PAIR, ALWAYS.  An [InstallDelete] with no
; matching [Files] entry removes a working installation's catalogue and puts
; nothing back, so stage.py refuses to emit either half on its own.
;
; ONE BLOCK HERE IS NOT ABOUT THE DATA TREE AND IS NOT GATED: the PF_RETIRED
; entries, which delete a script that C:\Program Files\SD used to hold and
; stage.py no longer ships.  Inno overwrites {app} on an upgrade but never
; removes a file absent from the new version, so without these one sits there
; until somebody uninstalls.  Ungated because a retired name can only be
; present if a previous version put it there.
;
; NOT TOUCHED HERE, AND IT IS BY CONSTRUCTION RATHER THAN BY A RULE: anything
; the bootstrap or the running system created - voc, voc.dic, dict.dic,
; accounts.dic, $map, $map.dic, $ipc, errlog, stacks, dir_dict - is named in
; no list in stage.py, so nothing below can reach it.  VOC is updated by
; running UPDATE.ACCOUNT on each account, which is what that verb is for.
'''

UPGRADE_COLD = '''\
; upgrade.iss - GENERATED BY gplbld/stage.py from a tree that was NOT
; bootstrapped, so there are no upgrade entries and this file refuses to build.
;
; A cold tree has an empty gcat, gpl.bp.out, bp.out and pcode.out.  Emitting
; the upgrade entries from it would produce an installer that DELETES a working
; installation's catalogue and copies nothing back.  Emitting nothing instead
; would produce an installer that silently cannot upgrade, which is the quieter
; and worse failure - so it stops here.
;
; Re-stage with --bootstrap.  cycle.ps1 already does.
#error stage.py was run without --bootstrap; this tree cannot build an installer
'''


def write_upgrade_iss(stage, sdsys, bootstrapped):
    r"""Emit <stage>\upgrade.iss - the in-place data-tree upgrade entries.

    Returns (path, replace, preserve).  See UPGRADE_HEADER for the reasoning;
    what is here is the mechanism and the four things it refuses to do.
    """
    path = os.path.join(stage, 'upgrade.iss')

    if not bootstrapped:
        with open(path, 'w', encoding='ascii', newline='\n') as f:
            f.write(UPGRADE_COLD)
        return path, [], []

    preserve = [n for n, _why in SDSYS_PRESERVE]
    declared = ([n for n, _why in SDSYS_SHIP] +
                [n for n, _why in SDSYS_EMPTY] +
                [n for n, _why in TERMINFO_DIRS] +
                [n for n, _why in TERMINFO_FILES])

    # A PRESERVE NAME THAT MATCHES NOTHING IS THE DANGEROUS TYPO, not a
    # harmless one: the name it was meant to protect drops into the replace
    # list and an upgrade deletes it.  Both directions are checked because
    # they fail differently - a name absent from the tree means the stage is
    # wrong, a name absent from the lists means this file is.
    absent = [n for n in preserve if not os.path.exists(os.path.join(sdsys, n))]
    if absent:
        die('SDSYS_PRESERVE names %s, which the staged tree does not have - '
            'refusing to emit an upgrade that would not protect it'
            % ', '.join(absent))
    unknown = [n for n in preserve if n not in declared]
    if unknown:
        die('SDSYS_PRESERVE names %s, which no ship list declares - the '
            'replace list is computed from those lists, so this entry '
            'protects nothing' % ', '.join(unknown))

    retired = [n for n, _why in SDSYS_RETIRED]
    clash = [n for n in retired if n in declared or n in preserve]
    if clash:
        die('SDSYS_RETIRED names %s, which a ship or preserve list also names '
            '- an upgrade would delete and re-create the same path'
            % ', '.join(clash))

    replace = [n for n in declared if n not in preserve]
    if not replace:
        die('the upgrade replace list came out empty - nothing would be '
            'refreshed and the installer would silently not upgrade')

    # An empty source directory means [Files] copies nothing while
    # [InstallDelete] has already removed the installed one.  Refuse the pair.
    hollow = [n for n in replace
              if os.path.isdir(os.path.join(sdsys, n))
              and not os.listdir(os.path.join(sdsys, n))]
    if hollow:
        die('these are on the upgrade replace list but are EMPTY in the '
            'staged tree, so an upgrade would delete them and copy nothing '
            'back: %s' % ', '.join(hollow))

    dels, files = [], []
    for name in replace:
        if os.path.isdir(os.path.join(sdsys, name)):
            dels.append(r'Name: "{#DataDir}\sdsys\%s"; Type: filesandordirs; '
                        r'Check: DataTreeUpgrade' % name)
            files.append(r'Source: "{#Stage}\ProgramData\sdsys\%s\*"; '
                         r'DestDir: "{#DataDir}\sdsys\%s"; Flags: '
                         r'recursesubdirs createallsubdirs uninsneveruninstall; '
                         r'Check: DataTreeUpgrade' % (name, name))
        else:
            dels.append(r'Name: "{#DataDir}\sdsys\%s"; Type: files; '
                        r'Check: DataTreeUpgrade' % name)
            files.append(r'Source: "{#Stage}\ProgramData\sdsys\%s"; '
                         r'DestDir: "{#DataDir}\sdsys"; '
                         r'Flags: uninsneveruninstall; Check: DataTreeUpgrade'
                         % name)

    # The retired names, delete-only.  filesandordirs covers both shapes
    # because a retired entry may have been either, and the path is gone by
    # the time anybody reads this list to find out which.
    for name, why in SDSYS_RETIRED:
        dels.append(r'; retired: %s' % why)
        dels.append(r'Name: "{#DataDir}\sdsys\%s"; Type: filesandordirs; '
                    r'Check: DataTreeUpgrade' % name)

    # And the same for {app}, UNGATED - see the note on PF_RETIRED.
    for name, why in PF_RETIRED:
        dels.append(r'; retired from {app}: %s' % why)
        dels.append(r'Name: "{app}\%s"; Type: files' % name)

    with open(path, 'w', encoding='ascii', newline='\n') as f:
        f.write(UPGRADE_HEADER)
        f.write('\n[InstallDelete]\n')
        f.write('\n'.join(dels) + '\n')
        f.write('\n[Files]\n')
        f.write('\n'.join(files) + '\n')

    return path, replace, preserve


def main():
    ap = argparse.ArgumentParser(
        description='Assemble the staging tree for a Windows install.')
    ap.add_argument('--stage', default='stage',
                    help='directory to build (default: stage)')
    ap.add_argument('--msys', default=r'C:\msys64',
                    help=r'MSYS2 installation (default: C:\msys64)')
    ap.add_argument('--force', action='store_true',
                    help='delete an existing staging directory first')
    ap.add_argument('--bootstrap', action='store_true',
                    help='run the bootstrap against the staged tree, so the '
                         'install needs neither Python nor a compiler')
    ap.add_argument('--list-mirrors', action='store_true',
                    help='print the sdsys directories that are a verbatim '
                         'copy of source, one per line, and exit')
    args = ap.parse_args()

    # ANSWERED BEFORE ANY OTHER CHECK, DELIBERATELY.  assert-current.ps1 asks
    # this on every run, including on a tree that has not been built - it is a
    # question about the LISTS in this file, not about the machine - so it must
    # not need bin/sd.exe, terminfo/, MSYS2, elevation or even the right
    # working directory.  Every die() below would otherwise turn a guard that
    # should have answered into a guard that refuses.
    if args.list_mirrors:
        for name, _why in SDSYS_MIRROR:
            print(name)
        return 0

    # bootstrap.py refuses an unelevated window, and by the time it gets the
    # chance this script has already copied several thousand files.  Ask the
    # same question before doing any of that work.  Staging on its own needs no
    # elevation at all, so only --bootstrap is gated.
    if args.bootstrap and not is_elevated():
        die('--bootstrap needs an ELEVATED window: it ends in "sd -internal"\n'
            '  steps that SDSYS refuses to an unelevated session\n'
            '  (PROJECT_STATUS.md section 5.6).  Start the shell with "Run as\n'
            '  administrator", or drop --bootstrap to stage a cold tree.')

    if not os.path.isdir('gplsrc') or not os.path.isdir('sdsys'):
        die('run this from sd64 - gplsrc and sdsys are not here')

    objdump = os.path.join(args.msys, 'usr', 'bin', 'objdump.exe')
    if not os.path.isfile(objdump):
        die('no objdump at %s - is --msys right?' % objdump)

    missing = [f for f in PROGRAM_FILES_BIN if not os.path.isfile(
        os.path.join('bin', f))]
    if missing:
        die('bin/ is missing %s - run "make sd" first'
            % ', '.join(sorted(missing)))
    if not os.path.isdir('terminfo'):
        die('terminfo/ has not been generated - run "make terminfo" first')

    stage = args.stage
    if os.path.exists(stage):
        if not args.force:
            die('%s exists - pass --force to replace it' % stage)
        shutil.rmtree(stage)

    pf = os.path.join(stage, 'ProgramFiles')
    pfbin = os.path.join(pf, PF_BIN_SUBDIR)
    pd = os.path.join(stage, 'ProgramData')
    sdsys = os.path.join(pd, 'sdsys')
    os.makedirs(pfbin)
    os.makedirs(sdsys)
    staged = Staged()

    # --- C:\Program Files\SD\ ---------------------------------------------

    for f in PROGRAM_FILES_BIN:
        dst = os.path.join(pfbin, f)
        shutil.copy2(os.path.join('bin', f), dst)
        staged.add(stage, dst)

    dlls, system = dll_closure(
        objdump, [os.path.join('bin', f) for f in DLL_SCAN], args.msys)
    for name in sorted(dlls):
        dst = os.path.join(pfbin, os.path.basename(dlls[name]))
        shutil.copy2(dlls[name], dst)
        staged.add(stage, dst)

    fstab = os.path.join(pf, 'etc', 'fstab')
    os.makedirs(os.path.dirname(fstab))
    with open(fstab, 'w', encoding='latin-1', newline='\n') as f:
        f.write(FSTAB)
    staged.add(stage, fstab)

    # Scripts the installer runs.  They ship as FILES rather than as inline
    # [Run] parameters because an inline parameter is exactly where the OpenSSH
    # brace bug hid for its whole life (PROJECT_STATUS.md 6) - a file can be
    # read and parse-checked on its own.  Missing one is a build failure, not a
    # warning: the installer would otherwise silently skip the step.
    here = os.path.dirname(os.path.abspath(__file__))
    # sd-elevate.ps1 and its helper are the exception to "scripts the INSTALLER
    # runs": SD runs these, at every entry to SDSYS.  They ship here rather
    # than in the data tree on purpose - the helper is executed with full
    # privilege, and the data tree is writable by every member of sdusers, so
    # shipping it there would let one SD user rewrite what another user's
    # elevated helper runs.  gpl.bp/ELEVATE reaches them with
    # kernel(K$WINPATH), because they are "/" to SD and "C:\Program Files\SD"
    # to PowerShell, which cannot open the first.
    for script in ('deny-logon.ps1', 'install-ssh.ps1', 'allow-ssh-groups.ps1',
                   'sync-route-groups.ps1',
                   'ssh-firewall.ps1',
                   # 25 Aug 26 - ssh-preflight.ps1 decides whether SD may
                   # install here at all, and it is the one script the
                   # installer runs BEFORE any file is written.  sd.iss
                   # therefore also embeds it with Flags: dontcopy and
                   # extracts it in InitializeSetup; this entry is what puts a
                   # copy in C:\Program Files\SD so an administrator can re-run
                   # the check by hand afterwards.  It SHIPS, so assert-current
                   # watches it like the rest of these - do NOT add it to that
                   # script's $neverShipped list.
                   'ssh-preflight.ps1',
                   # 21 Aug 26 - the API faces the network now, so who may
                   # reach the port is a firewall rule SD owns.  Shipped, so
                   # it is watched by assert-current like the rest of these -
                   # do NOT add it to that script's $neverShipped list.
                   'api-firewall.ps1',
                   'adopt-account.ps1', 'install-service.ps1',
                   # 22 Aug 26 - the POST-INSTALL CHECK, offered as a
                   # checkbox on the installer's last page.  It ships, so
                   # assert-current watches it like the rest of these - do
                   # NOT add it to that script's $neverShipped list.  It is
                   # deliberately NOT one of the verify-*.ps1 development
                   # scripts, none of which can run on a user's machine:
                   # they compare the install against the SOURCE TREE.
                   'check-install.ps1',
                   # 22 Aug 26 - the finishing step: the password session
                   # and the check, in that order, in one window, launched
                   # from DeinitializeSetup once the wizard has gone.
                   'finish-install.ps1',
                   'secure-audit.ps1', 'secure-cred.ps1', 'secure-log.ps1',
                   'secure-psdir.ps1', 'secure-osusers.ps1',
                   'secure-gcat.ps1',
                   # 23 Aug 26 - section 7 step 15.  gcat decides WHICH
                   # catalogued program runs; this locks what the interpreter
                   # running it IS.  Both ship or neither is worth much.
                   'secure-pcode.ps1',
                   # 24 Aug 26 - section 7 step 15, the owner's ruling.  The
                   # rest of the inherited sdusers:(M) list - accounts, $map,
                   # messages, newvoc, bp, cat and sd.conf.  NOT $ipc, which
                   # every session writes.  sd.iss names the seven; this only
                   # has to put the mechanism where SecureSysdirs can run it.
                   'secure-sysdirs.ps1',
                   'secure-accounts.ps1', 'secure-account-dirs.ps1',
                   # 25 Aug 26 - the dictionary step for an UPGRADE.  A first
                   # install gets its dictionaries from the staged tree, which
                   # the build's own bootstrap already wrote; an upgrade keeps
                   # the user's data tree, dictionaries included, so a release
                   # that edits FILES_DICTS would never reach it.  This runs
                   # gpl.bp/WRITE_INSTALL_DICTS, which MERGES record by record
                   # rather than replacing the file - see its header.  It
                   # SHIPS, so assert-current watches it like the rest of
                   # these - do NOT add it to that script's $neverShipped list.
                   'upgrade-dicts.ps1',
                   'sd-elevate.ps1', 'sd-elevate-helper.ps1'):
        src = os.path.join(here, script)
        if not os.path.exists(src):
            raise SystemExit('missing %s - the installer needs it' % src)
        dst = os.path.join(pf, script)
        shutil.copy2(src, dst)
        staged.add(stage, dst)

    # 25 Aug 26 - THE CHANGELOG LIVES HERE NOW, NOT IN THE DATA TREE.  See the
    # note on SDSYS_SHIP above for why.  It is copied rather than left to a
    # wildcard so that a missing changelog is a build failure, the same way a
    # missing installer script is: shipping a release whose changelog silently
    # did not make it is the failure this file is meant to prevent.
    changelog = os.path.join('sdsys', 'changelog')
    if not os.path.isfile(changelog):
        die('sdsys/changelog is missing - it ships to {app} by standing '
            'instruction (CLAUDE.md)')
    dst = os.path.join(pf, 'changelog')
    shutil.copy2(changelog, dst)
    staged.add(stage, dst)

    # 25 Aug 26 - FILES_DICTS SHIPS TO {app}, AND ONLY TO {app}.
    #
    # It is the tracked source for all eight dictionaries, 76 records keyed
    # "<file>^<record>".  The dictionaries themselves are not tracked, because
    # this repository holds no binary bits and a dictionary is more efficient
    # as a DYNAMIC file - so they are created and loaded during the install
    # (owner, 25 Aug 2026).  gpl.bp/WRITE_INSTALL_DICTS is what turns one into
    # the other, and upgrade-dicts.ps1 runs it on an upgrade.
    #
    # IT MUST NOT GO INTO THE DATA TREE.  WRITE_INSTALL_DICTS reads it as
    # @sdsys:"/gplbld/FILES_DICTS", so it has to be there WHILE IT RUNS and
    # gone afterwards - a build input, not data.  bootstrap.py places and
    # removes it at build time (BOOTSTRAP_ONLY) and upgrade-dicts.ps1 does the
    # same on the target, each in a finally.  Shipping it into sdsys instead
    # would put gplbld/ permanently inside the data tree, which is the thing
    # the data-tree-holds-data-only decision forbids.
    #
    # THE {app}\gplbld PREFIX IS KEPT rather than flattened, so the path the
    # installer copies FROM and the path the program reads are the same shape
    # and a reader can see they correspond.
    fd_src = os.path.join('gplbld', 'FILES_DICTS')
    if not os.path.isdir(fd_src):
        die('gplbld/FILES_DICTS is missing - it is the source for every '
            'dictionary and upgrade-dicts.ps1 cannot run without it')
    fd_dst = os.path.join(pf, 'gplbld', 'FILES_DICTS')
    copy_tree(fd_src, fd_dst, staged, stage)
    print('  FILES_DICTS: %d dictionary records staged to ProgramFiles\\gplbld'
          % len(os.listdir(fd_dst)))

    # --- C:\ProgramData\SD\ -----------------------------------------------

    conf = os.path.join(pd, 'sd.conf')
    with open(conf, 'w', encoding='latin-1', newline='\r\n') as f:
        f.write(SD_CONF)
    staged.add(stage, conf)

    # The stand-alone variant, staged beside it under its own name.  sd.iss
    # ships ONE of the two with DestName: sd.conf, gated on the wizard's mode
    # page, so this name never reaches an installed machine.
    sconf = os.path.join(pd, 'sd-standalone.conf')
    with open(sconf, 'w', encoding='latin-1', newline='\r\n') as f:
        f.write(sd_conf_standalone())
    staged.add(stage, sconf)
    print('  sd.conf: full (APIPORT=4243) and stand-alone (APIPORT unset) staged')

    for d in PROGRAM_DATA_DIRS:
        os.makedirs(os.path.join(pd, d))

    for name, _why in SDSYS_SHIP:
        src = os.path.join('sdsys', name)
        if not os.path.exists(src):
            die('sdsys/%s is on the ship list but is not in the tree' % name)
        dst = os.path.join(sdsys, name)
        if os.path.isdir(src):
            copy_tree(src, dst, staged, stage)
        else:
            shutil.copy2(src, dst)
            staged.add(stage, dst)

    for name, _why in SDSYS_EMPTY:
        os.makedirs(os.path.join(sdsys, name))

    for name, _why in TERMINFO_DIRS:
        copy_tree(name, os.path.join(sdsys, name), staged, stage)
    for name, _why in TERMINFO_FILES:
        dst = os.path.join(sdsys, name)
        shutil.copy2(name, dst)
        staged.add(stage, dst)

    # --- bootstrap ---------------------------------------------------------

    if args.bootstrap:
        # A configuration of its own, kept OUTSIDE both install roots so it is
        # never packaged, naming the staging tree rather than the production
        # path.  The build must not read or write the build machine's own
        # installed system.
        bconf = os.path.join(stage, 'bootstrap-sd.conf')
        with open(bconf, 'w', encoding='latin-1', newline='\r\n') as f:
            f.write(SD_CONF.replace('SDSYS=' + PRODUCTION_SDSYS,
                                    'SDSYS=' + os.path.abspath(sdsys)))

        # The account directory has to name the staged tree BEFORE the
        # bootstrap logs in - see retarget_sdsys_account().
        shipped = retarget_sdsys_account(sdsys, os.path.abspath(sdsys))
        print('  accounts/sdsys pointed at the staged tree')
        print('    was %s' % shipped)

        print('bootstrapping the staged tree')
        r = subprocess.run(
            [sys.executable,
             os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          'bootstrap.py'),
             '--sysdir', os.path.abspath(sdsys),
             '--sd', os.path.abspath(os.path.join(pfbin, 'sd.exe')),
             '--conf', bconf])
        if r.returncode != 0:
            die('the bootstrap failed; the staged tree is not installable')

        # AND JUDGE IT ON WHAT IT CREATED, not on that exit code - see
        # check_bootstrap_complete().  A seed-only tree has been packaged and
        # installed once already.
        faults = check_bootstrap_complete(sdsys)
        if faults:
            print('  the bootstrap reported success but did not finish:')
            for f in faults:
                print('    %s' % f)
            die('refusing to stage a tree no session could start in - '
                'see check_bootstrap_complete() and PROJECT_STATUS.md 6')
        print('  checked: the bootstrap completed')

        os.remove(bconf)

        was = retarget_sdsys_account(sdsys, PRODUCTION_SDSYS)
        print('  accounts/sdsys retargeted')
        print('    from %s' % was)
        print('    to   %s' % PRODUCTION_SDSYS)

        offenders = check_no_stage_paths(stage, sdsys,
                                         allowed={'accounts/sdsys', 'errlog'})
        if offenders:
            print('  these staged files still name the staging directory:')
            for o in sorted(offenders)[:20]:
                print('    %s' % o)
            die('the staged tree would carry build paths into an install - '
                'see check_no_stage_paths() and PROJECT_STATUS.md 5.16')
        print('  checked: nothing else embeds the build path')

        # errlog is the bootstrap's own diagnostic output, not install data.
        el = os.path.join(sdsys, 'errlog')
        if os.path.isfile(el):
            os.remove(el)

        # The tree gained a great deal; rebuild the record from what is there.
        staged.files = []
        staged.scan(stage, pf)
        staged.scan(stage, pd)

    # --- the in-place data-tree upgrade ------------------------------------
    #
    # Written beside MANIFEST.txt, OUTSIDE both install roots, for the same
    # reason: it is build input for ISCC and must never be packaged.

    up, replace, preserve = write_upgrade_iss(stage, sdsys, args.bootstrap)
    print('wrote %s' % up)
    if args.bootstrap:
        print('  an upgrade REPLACES  %s' % ' '.join(replace))
        print('  an upgrade PRESERVES %s' % ' '.join(preserve))
        print('  an upgrade REMOVES   %s (retired from sdsys)'
              % ' '.join(n for n, _w in SDSYS_RETIRED))
        print('  every install REMOVES %s (retired from {app})'
              % (' '.join(n for n, _w in PF_RETIRED) or '(nothing)'))
        print('  and cannot reach voc, $map, errlog or anything else the')
        print('  bootstrap and SD create - they are on no list here')
    else:
        print('  COLD TREE - this file stops ISCC. Re-stage with --bootstrap.')

    # --- manifest and summary ---------------------------------------------

    staged.files.sort()
    total = sum(size for _p, size in staged.files)
    with open(os.path.join(stage, 'MANIFEST.txt'), 'w',
              encoding='latin-1', newline='\n') as f:
        for path, size in staged.files:
            f.write('%10d  %s\n' % (size, path))

    print('staged %s' % os.path.abspath(stage))
    if not args.bootstrap:
        print('  NOT bootstrapped - this tree is not installable on its own.')
        print('  Pass --bootstrap unless you meant to build a cold tree.')
    print('  %d files, %.1f MB' % (len(staged.files), total / 1048576.0))
    print('  binaries in %s, so the POSIX root is the SD directory'
          % os.path.join('ProgramFiles', PF_BIN_SUBDIR))
    print('  MSYS2 DLLs copied: %s'
          % ' '.join(sorted(os.path.basename(p) for p in dlls.values())))
    print('  supplied by Windows, not copied: %s' % ' '.join(sorted(system)))
    # Embedded Python was dropped on 13 Aug 2026 (PROJECT_STATUS.md 5.15), which
    # is what removed the only dependency this script could not resolve - the
    # 195 MB standard library that msys-python3.12.dll would have needed.  If a
    # python DLL ever reappears in the closure, that question is back.
    python_dlls = [n for n in dlls if 'python' in n]
    if python_dlls:
        print('  WARNING: %s is in the closure, but embedded Python was'
              % ' '.join(sorted(python_dlls)))
        print('           removed in 5.15.  Something re-enabled it, and the')
        print('           standard library is not staged.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
