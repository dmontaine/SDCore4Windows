#!/usr/bin/env python3
#
# sandbox-crypt.py - encryption layers 2 and 3: SDSALT / SDKEY / SDRANDKEY for any program.  No install, no sudo.
#
#   SDBOX_KEYSET=<n> python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-crypt.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 18 Oct 26 dm  Written for encryption layer 2 (.claude/plan-encryption-layers.md): SDSALT(), SDKEY(passphrase, salt),
#               SDRANDKEY() and the way they meet SDENCRYPT / SDDECRYPT.
# 18 Oct 26 dm  PART 2, encryption layer 3: the XE conversion (both ways, against libsodium outside SD, with tokens made here), the key
#               ring and !KEYSET / !KEYCLEAR / !KEYLIST, what LIST / SORT / WITH / COUNT / I-types / an index / COPY do with an encrypted
#               field, LOGTO and a phantom, the ENCRYPT.KEY verb on a pipe and on a terminal, and a search of the whole sandbox for the
#               passphrase and the key.  It runs after part 1 in the same sandbox, using sandbox-stmt-q3.py's fixture accounts.
# 18 Oct 26 dm  Cold-start rows: each is the first libsodium call of a session of its own.  The rows of one session share a libsodium
#               that an early SDSALT() started, so SDKEY() as a process's first call (sodium_malloc() before sodium_init(): an assertion
#               that kills the process) passed unseen.
# END-HISTORY
#
# THE INSTRUMENT is the value a BASIC program printed between brackets (as sandbox-func-b4.py).  A row that compares two
# keys prints 1 or 0 and wants 1 or 0, so that the key itself does not have to be known to the table; the ONE row that
# pins a key (the fixed vector) wants a value computed OUTSIDE SD, by libsodium loaded through ctypes with the limits
# written out in this file (2 passes, 64 MiB, argon2id) - so a change of the limits in the C source fails it.
# EVERY RELATION HAS ITS CONTROL: a derived key is checked to differ for a different salt and passphrase (the
# "equal" row alone would pass for a function that returned a constant); the "refused" rows wait for the empty string AND
# the status, and a good call after a refusal must read STATUS() 0 again.  A program that does not compile prints
# nothing, so the compile-refusal rows want NO output line, with the same shape written correctly as the control.

import base64
import ctypes
import ctypes.util
import hashlib
import importlib.util
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

# the reference key: libsodium, outside SD.  passphrase "correct horse battery staple", salt = bytes 0..15
REF_PW = b"correct horse battery staple"
REF_SALT = bytes(range(16))
REF_SALT_B64 = base64.b64encode(REF_SALT).decode()
OPSLIMIT, MEMLIMIT, ALG_ARGON2ID13 = 2, 67108864, 2


def reference_key():
    path = ctypes.util.find_library("sodium")
    if not path:
        return None
    lib = ctypes.CDLL(path)
    if lib.sodium_init() < 0:
        return None
    out = ctypes.create_string_buffer(32)
    rc = lib.crypto_pwhash(out, ctypes.c_ulonglong(32), REF_PW, ctypes.c_ulonglong(len(REF_PW)), REF_SALT,
                           ctypes.c_ulonglong(OPSLIMIT), ctypes.c_size_t(MEMLIMIT), ctypes.c_int(ALG_ARGON2ID13))
    return base64.b64encode(out.raw).decode() if rc == 0 else None


B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="

# Prefix of every case: a salt and two keys made from it.
PRE = ("salt = sdsalt()\n"
       "   k1 = sdkey('first passphrase', salt)\n"
       "   k2 = sdkey('second passphrase', salt)\n")

# (label, BASIC statements one per line leaving the value in x, wanted).  wanted None = the program must NOT compile.
CASES = [
    # ---- SDSALT, SDRANDKEY ------------------------------------------------------------------------------------------
    ("SDSALT is 24 characters (base64 of 16 bytes) and STATUS() is 0 after it",
     "s = sdsalt()\n   x = len(s):'|':status()", "24|0"),
    ("SDSALT uses only base64 characters",
     "s = sdsalt() ; x = 1\n   for i = 1 to len(s) ; if index('%s', s[i,1], 1) = 0 then x = 0\n   next i" % B64, "1"),
    ("SDSALT gives a different salt each time (CONTROL for the equality rows below)",
     "x = (sdsalt() # sdsalt())", "1"),
    ("SDRANDKEY is 44 characters and STATUS() is 0 after it",
     "k = sdrandkey()\n   x = len(k):'|':status()", "44|0"),
    ("SDRANDKEY uses only base64 characters",
     "k = sdrandkey() ; x = 1\n   for i = 1 to len(k) ; if index('%s', k[i,1], 1) = 0 then x = 0\n   next i" % B64, "1"),
    ("SDRANDKEY gives a different key each time",
     "x = (sdrandkey() # sdrandkey())", "1"),
    ("SDRANDKEY ends in the one '=' that base64 of 32 bytes ends in",
     "k = sdrandkey()\n   x = k[44,1]:'|':count(k, '=')", "=|1"),
    # ---- SDKEY -------------------------------------------------------------------------------------------------------
    ("SDKEY is 44 characters and STATUS() is 0",
     PRE + "   x = len(k1):'|':status()", "44|0"),
    ("SDKEY: the same passphrase and salt give the same key",
     PRE + "   x = (sdkey('first passphrase', salt) = k1)", "1"),
    ("SDKEY: the same salt and a different passphrase give a different key (CONTROL)",
     PRE + "   x = (k1 # k2)", "1"),
    ("SDKEY: the same passphrase and a different salt give a different key (CONTROL)",
     PRE + "   x = (sdkey('first passphrase', sdsalt()) # k1)", "1"),
    ("SDKEY: a passphrase that differs only in case gives a different key",
     PRE + "   x = (sdkey('FIRST PASSPHRASE', salt) # k1)", "1"),
    ("SDKEY: a trailing space is part of the passphrase",
     PRE + "   x = (sdkey('first passphrase ', salt) # k1)", "1"),
    ("SDKEY: a number is the passphrase it prints as",
     "salt = sdsalt()\n   x = (sdkey(12345, salt) = sdkey('12345', salt))", "1"),
    ("SDKEY: a passphrase holding a value mark is accepted and differs from the same text without it",
     PRE + "   a = sdkey('ab':@vm:'cd', salt) ; x = (a # sdkey('abcd', salt)):'|':len(a):'|':status()", "1|44|0"),
    ("SDKEY: 65536 characters are accepted",
     "salt = sdsalt()\n   k = sdkey(str('a', 65536), salt)\n   x = len(k):'|':status()", "44|0"),
    ("SDKEY: the fixed vector - the key libsodium makes outside SD (argon2id, 2 passes, 64 MiB)",
     "x = sdkey('%s', '%s')" % (REF_PW.decode(), REF_SALT_B64), "REFERENCE"),
    ("SDKEY: a key made by SDKEY is accepted by SDENCRYPT and SDDECRYPT as a base64 key",
     PRE + "   c = sdencrypt('salary 41250', k1, 202)\n   x = sddecrypt(c, k1, 202):'|':status()", "salary 41250|0"),
    # ---- the salt and passphrase refusals ----------------------------------------------------------------------------
    ("SDKEY: an empty salt gives the null string and STATUS() 10206",
     "x = 'old'\n   x = sdkey('pw', '')\n   x = len(x):'|':status()", "0|10206"),
    ("SDKEY: a salt that is not base64 gives the null string and 10206",
     "x = sdkey('pw', '!!!!!!!!!!!!!!!!!!!!!!!!'):'|':status()", "|10206"),
    ("SDKEY: a salt for 15 bytes (20 characters) gives 10206",
     "x = sdkey('pw', 'AAAAAAAAAAAAAAAAAAAA'):'|':status()", "|10206"),
    ("SDKEY: a salt for 32 bytes (44 characters) gives 10206",
     "x = sdkey('pw', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='):'|':status()", "|10206"),
    ("SDKEY: a salt of 100 characters gives 10206",
     "x = sdkey('pw', str('A', 100)):'|':status()", "|10206"),
    ("SDKEY: the right-length salt (CONTROL for the three rows above) gives a key",
     "x = len(sdkey('pw', 'AAAAAAAAAAAAAAAAAAAAAA==')):'|':status()", "44|0"),
    ("SDKEY: an empty passphrase gives the null string and STATUS() 10207",
     "x = sdkey('', sdsalt()):'|':status()", "|10207"),
    ("SDKEY: 65537 characters give the null string and 10207",
     "x = sdkey(str('a', 65537), sdsalt()):'|':status()", "|10207"),
    ("SDKEY: a refusal is not sticky - the next good call reads STATUS() 0 and gives a key",
     "s = sdsalt()\n   z = sdkey('', s)\n   w = status()\n   y = sdkey('pw', s)\n   x = w:'|':status():'|':len(y)", "10207|0|44"),
    ("SDKEY: a failed call leaves the target empty, not what it held",
     "x = 'old value'\n   x = sdkey('pw', 'bad')\n   x = '[':x:']':len(x)", "[]0"),
    # ---- meeting SDENCRYPT / SDDECRYPT --------------------------------------------------------------------------------
    ("SDENCRYPT: the ciphertext is not the plaintext, and encrypting twice gives two different values (a fresh nonce)",
     PRE + "   p = 'salary 41250'\n   c1 = sdencrypt(p, k1, 202) ; c2 = sdencrypt(p, k1, 202)\n"
     "   x = (c1 # p):'|':(c1 # c2):'|':(index(c1, 'salary', 1) = 0)", "1|1|1"),
    ("SDDECRYPT: both ciphertexts return the plaintext",
     PRE + "   p = 'salary 41250'\n   c1 = sdencrypt(p, k1, 202) ; c2 = sdencrypt(p, k1, 202)\n"
     "   x = sddecrypt(c1, k1, 202):'|':sddecrypt(c2, k1, 202)", "salary 41250|salary 41250"),
    ("SDDECRYPT: a key from another passphrase is refused with 10201 and gives the null string",
     PRE + "   c = sdencrypt('salary 41250', k1, 202)\n   x = len(sddecrypt(c, k2, 202)):'|':status()", "0|10201"),
    ("SDDECRYPT: the right key after the refusal works (CONTROL)",
     PRE + "   c = sdencrypt('salary 41250', k1, 202)\n   z = sddecrypt(c, k2, 202)\n   x = sddecrypt(c, k1, 202):'|':status()",
     "salary 41250|0"),
    ("SDDECRYPT: ciphertext with one character changed in the middle is refused with 10201",
     PRE + "   c = sdencrypt('salary 41250', k1, 202)\n   m = int(len(c) / 2)\n   ch = if c[m,1] = 'A' then 'B' else 'A'\n"
     "   t = c[1, m - 1]:ch:c[m + 1, len(c)]\n   x = (t # c):'|':len(sddecrypt(t, k1, 202)):'|':status()", "1|0|10201"),
    ("SDDECRYPT: ciphertext cut short is refused",
     PRE + "   c = sdencrypt('salary 41250', k1, 202)\n   x = len(sddecrypt(c[1, 20], k1, 202)):'|':(status() # 0)", "0|1"),
    ("SDENCRYPT: a passphrase passed straight as the key is still refused with 10204 (CONTROL)",
     "x = len(sdencrypt('salary', 'first passphrase', 202)):'|':status()", "0|10204"),
    ("SDENCRYPT: a base64 key with encoding 201 (hex) is refused with 10204 - a derived key is for 202",
     PRE + "   x = len(sdencrypt('salary', k1, 201)):'|':status()", "0|10204"),
    ("SDRANDKEY: a random key works as a key for 202",
     "k = sdrandkey()\n   c = sdencrypt('abc def', k, 202)\n   x = sddecrypt(c, k, 202):'|':status()", "abc def|0"),
    ("SDRANDKEY: two random keys do not decrypt each other's ciphertext",
     "k = sdrandkey() ; j = sdrandkey()\n   c = sdencrypt('abc def', k, 202)\n   x = len(sddecrypt(c, j, 202)):'|':status()", "0|10201"),
    ("SDENCRYPT: a value holding every kind of mark and a high-bit byte survives the round trip",
     PRE + "   p = 'a':@fm:'b':@vm:'c':@sm:'d':@tm:'e':@im:char(200):'z'\n   c = sdencrypt(p, k1, 202)\n"
     "   x = (sddecrypt(c, k1, 202) = p):'|':(index(c, @fm, 1) + index(c, @vm, 1) + index(c, @sm, 1))", "1|0"),
    ("SDENCRYPT: a 40000 character value survives the round trip",
     PRE + "   p = str('0123456789', 4000)\n   c = sdencrypt(p, k1, 202)\n   x = (sddecrypt(c, k1, 202) = p):'|':status()", "1|0"),
    ("SDENCRYPT: an empty value is refused with 10200 (as before)",
     PRE + "   x = len(sdencrypt('', k1, 202)):'|':status()", "0|10200"),
    # ---- compile ------------------------------------------------------------------------------------------------------
    ("CONTROL: SDSALT() with its brackets and nothing in them compiles", "x = len(sdsalt())", "24"),
    ("SDSALT(1) does not compile", "x = sdsalt(1)", ("ERR", "Right bracket not found where expected")),
    ("SDRANDKEY(1) does not compile", "x = sdrandkey(1)", ("ERR", "Right bracket not found where expected")),
    ("SDKEY with one argument does not compile", "x = sdkey('pw')", ("ERR", "Comma not found where expected")),
    ("SDKEY with three arguments does not compile", "x = sdkey('pw', sdsalt(), 3)", ("ERR", "Right bracket not found where expected")),
    ("a function call can be an argument of another: SDKEY('pw', SDSALT()) is a key",
     "x = len(sdkey('pw', sdsalt())):'|':status()", "44|0"),
    ("the same call twice in one expression: SDSALT() # SDSALT() is true (the compiler keeps its rows apart)",
     "x = (sdkey('pw', sdsalt()) # sdkey('pw', sdsalt()))", "1"),
]

# COLD START.  Each of these is the FIRST libsodium call of its own sd process (a session of its own).  The rows above all run in
# one session, where an earlier SDSALT() has already started libsodium: SDKEY() as the first call used to kill the process with a
# libsodium assertion (sodium_malloc() before sodium_init()), and nothing above could see it.  (found 18 Oct 26 by the XE work)
COLD = [
    ("COLD: SDKEY as the first libsodium call of the process gives the key libsodium makes outside SD",
     "x = sdkey('%s', '%s')" % (REF_PW.decode(), REF_SALT_B64), "REFERENCE"),
    ("COLD: SDKEY as the first call, with a salt that is refused, gives the null string and 10206 (not a dead process)",
     "x = sdkey('pw', 'bad'):'|':status()", "|10206"),
    ("COLD: SDSALT as the first call is 24 characters", "x = len(sdsalt()):'|':status()", "24|0"),
    ("COLD: SDRANDKEY as the first call is 44 characters", "x = len(sdrandkey()):'|':status()", "44|0"),
    ("COLD: SDENCRYPT as the first call, with a key from SDRANDKEY, round-trips",
     "k = sdrandkey()\n   x = sddecrypt(sdencrypt('cold value', k, 202), k, 202)", "cold value"),
    # layer 3: the conversion allocates (sodium_malloc) before it looks at the ring
    ("COLD: ICONV XE as the first libsodium call of the process, with no key, gives the null string and 10208",
     "x = len(iconv('cold value', 'XE')):'|':status()", "0|10208"),
    ("COLD: ICONV XE as the first call with a code that is a mistake gives the null string and 2",
     "x = len(iconv('cold value', 'XEfoo')):'|':status()", "0|2"),
    ("COLD: OCONV XE as the first call, with no key, leaves the value and gives 10210 (not an encrypted value)",
     "x = oconv('cold value', 'XE'):'|':status()", "cold value|10210"),
]

# Files the canary must not reach.  The passphrase is built at run time, so the program source does not hold it.
CANARY_A, CANARY_B = "Canary", "Phrase-7f3a91"
CONTROL_FRAG = "zzcryptsourcefrag"


def say(s=""):
    print(s)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def bail(msg):
    say("sandbox-crypt: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=1800)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def grep_tree(root, needle):
    """Files under root holding needle (bytes).  The sandbox's own tree/ (a copy of the source) is not data."""
    hits = []
    skip = os.path.join(root, "tree")
    nb = needle.encode("latin-1")
    for d, dirs, files in os.walk(root):
        if d == root and "tree" in dirs:
            dirs.remove("tree")
        for f in files:
            pth = os.path.join(d, f)
            try:
                if os.path.islink(pth) or os.path.getsize(pth) > 64 * 1024 * 1024:
                    continue
                with open(pth, "rb") as fh:
                    if nb in fh.read():
                        hits.append(pth)
            except OSError:
                pass
    return hits


# ======================================================================================================================================
# PART 2 - layer 3: the XE conversion, the key ring, !KEYSET / !KEYCLEAR / !KEYLIST and the ENCRYPT.KEY verb
#
# THE ORACLE IS libsodium OUTSIDE SD, loaded through ctypes: a value SD encrypts is taken apart here (version, key id, nonce, secretbox)
# and opened with the key worked out here; a value made HERE, with chosen nonces, is what SD is asked to decrypt.  So the format is held
# from both sides, and the fixture records of the query rows are tokens this script made - SD has never seen their plaintext until the
# conversion shows it.  Every row about what a query does with an encrypted field says what it DOES, not what would be nice (a WITH on a
# value cannot match; a SORT is of ciphertext; an index holds ciphertext): they are the documented limits, held so that a change shows.
# ======================================================================================================================================

SODIUM = None


def sodium():
    global SODIUM
    if SODIUM is None:
        SODIUM = ctypes.CDLL(ctypes.util.find_library("sodium"))
        SODIUM.sodium_init()
    return SODIUM


def pwhash_key(passphrase, salt16):
    """The 32 byte key SDKEY() must give: argon2id, 2 passes, 64 MiB."""
    lib = sodium()
    out = ctypes.create_string_buffer(32)
    rc = lib.crypto_pwhash(out, ctypes.c_ulonglong(32), passphrase, ctypes.c_ulonglong(len(passphrase)), salt16,
                           ctypes.c_ulonglong(OPSLIMIT), ctypes.c_size_t(MEMLIMIT), ctypes.c_int(ALG_ARGON2ID13))
    if rc != 0:
        raise RuntimeError("crypto_pwhash failed")
    return out.raw


def key_id(key32):
    return hashlib.sha256(key32).digest()[:4]


def mk_token(key32, plain, nonce, version=1, kid=None):
    """An encrypted value as the conversion writes it: base64 of version | key id | nonce | secretbox."""
    lib = sodium()
    c = ctypes.create_string_buffer(16 + len(plain))
    lib.crypto_secretbox_easy(c, plain, ctypes.c_ulonglong(len(plain)), nonce, key32)
    return base64.b64encode(bytes([version]) + (kid if kid is not None else key_id(key32)) + nonce + c.raw[:16 + len(plain)]).decode()


def open_token(key32, token):
    """The plaintext bytes of a token, or None; also None when the shape is wrong."""
    try:
        raw = base64.b64decode(token, validate=True)
    except Exception:
        return None
    if len(raw) < 29 + 16 or raw[0] != 1:
        return None
    nonce, c = raw[5:29], raw[29:]
    m = ctypes.create_string_buffer(max(1, len(c) - 16))
    rc = sodium().crypto_secretbox_open_easy(m, c, ctypes.c_ulonglong(len(c)), nonce, key32)
    return m.raw[:len(c) - 16] if rc == 0 else None


def parts(token):
    raw = base64.b64decode(token, validate=True)
    return raw[0], raw[1:5], raw[5:29], raw[29:]


def mutate_char(token, pos):
    ch = token[pos]
    return token[:pos] + ("B" if ch == "A" else "A") + token[pos + 1:]


PW = REF_PW.decode()
SALT = REF_SALT_B64
DEF_KEY = "call !keyset('salary', sdkey('%s', '%s'), id)" % (PW, SALT)

L3_PROGS = {
    # the conversion both ways, with the key HERE knows: SD's own values are taken apart by this script
    "zzxe1": "\n".join([
        "   k = sdkey('%s', '%s')" % (PW, SALT),
        "   crt 'KEY[':k:']'",
        "   call !keyset('', k, id1)",
        "   crt 'ID1[':id1:'|':status():']'",
        "   p = 'salary 41250'",
        "   c1 = iconv(p, 'XE') ; s1 = status()",
        "   c2 = iconv(p, 'XE')",
        "   crt 'C1[':c1:']'",
        "   crt 'C2[':c2:']'",
        "   crt 'S1[':s1:']'",
        "   crt 'DIFF[':(c1 # c2):']'",
        "   crt 'R1[':oconv(c1, 'XE'):'|':status():']'",
        "   crt 'R2[':oconv(c2, 'xe;Default'):'|':status():']'",
        "   m = 'a':@fm:'b':@vm:'c':@sm:'d':@tm:'e':@im:'f':char(200):'z'",
        "   cm = iconv(m, 'XE')",
        "   crt 'MARKS[':(oconv(cm, 'XE') = m):'|':(index(cm, @fm, 1) + index(cm, @vm, 1) + index(cm, @sm, 1) + index(cm, @tm, 1) + index(cm, @im, 1)):']'",
        "   big = str('0123456789', 3000)",
        "   cb = iconv(big, 'XE')",
        "   crt 'BIG[':(oconv(cb, 'XE') = big):'|':len(cb):']'",
        "   crt 'NUM[':oconv(iconv(12345, 'XE'), 'XE'):']'",
        "   crt 'NULLI[':len(iconv('', 'XE')):'|':status():']'",
        "   crt 'NULLO[':len(oconv('', 'XE')):'|':status():']'",
        "   crt 'CHAIN[':oconv(c1, 'XE':@vm:'MCU'):']'",
        "end", ""]),
    # tokens made by this script, to be decrypted
    "zzxe2": "\n".join([
        "   " + DEF_KEY,
        "   for i = 1 to 7",
        "      t = field(@sentence, ' ', 3 + i)",
        "      x = oconv(t, 'XE;salary')",
        "      xs = if x = t then '<same>' else change(change(x, @fm, '<F>'), @vm, '<V>')",
        "      crt 'T':i:'[':xs:'|':status():']'",
        "   next i",
        "   x = oconv('not base64 !!!', 'XE;salary')",
        "   crt 'T8[':x:'|':status():']'",
        "   x = oconv('QUJD', 'XE;salary')",
        "   crt 'T9[':x:'|':status():']'",
        "   x = oconv(123456, 'XE;salary')",
        "   crt 'T10[':x:'|':status():']'",
        "end", ""]),
    # no key in the ring, a mistake in the code, and a key under another name
    "zzxe3": "\n".join([
        "   x = iconv('secret', 'XE;nokey')",
        "   crt 'NI[':len(x):'|':status():']'",
        "   t = field(@sentence, ' ', 4)",
        "   x = oconv(t, 'XE;nokey')",
        "   crt 'NO[':(x = t):'|':status():']'",
        "   codes = 'XEfoo':@fm:'XE;bad!name':@fm:'XE;':str('a', 32):@fm:'XX':@fm:'X':@fm:'XE;a b'",
        "   for i = 1 to 6",
        "      code = codes<i>",
        "      x = iconv('secret', code)",
        "      crt 'BI':i:'[':len(x):'|':status():']'",
        "      x = oconv('secret', code)",
        "      crt 'BO':i:'[':x:'|':status():']'",
        "   next i",
        "   call !keyset('wk', sdkey('other passphrase', '%s'), id)" % SALT,
        "   x = oconv(t, 'XE;wk')",
        "   crt 'WK[':(x = t):'|':status():']'",
        "   x = oconv(t, 'XE;nokey')",
        "   crt 'NO2[':(x = t):'|':status():']'",
        "   x = iconv('secret', 'XE;nokey')",
        "   crt 'NI2[':len(x):'|':status():']'",
        "end", ""]),
    # names folded to lower case, a second key under a name, the same key again, two names, clearing
    "zzxe4": "\n".join([
        "   salt = '%s'" % SALT,
        "   ka = sdkey('pass A', salt) ; kb = sdkey('pass B', salt)",
        "   call !keyset('Mixed.Case_1', ka, ida)",
        "   crt 'IDA[':ida:'|':status():']'",
        "   c1 = iconv('v1', 'XE;mixed.case_1')",
        "   crt 'C1[':c1:']'",
        "   call !keyset('mixed.case_1', kb, idb)",
        "   c2 = iconv('v2', 'XE;MIXED.CASE_1')",
        "   crt 'C2[':c2:']'",
        "   crt 'ROT[':oconv(c1, 'XE;mixed.case_1'):'|':oconv(c2, 'XE;mixed.case_1'):']'",
        "   call !keylist(l)",
        "   crt 'L1[':change(change(l, @fm, '/'), @vm, '|'):']'",
        "   call !keyset('mixed.case_1', ka, id3)",
        "   c3 = iconv('v3', 'XE;mixed.case_1')",
        "   crt 'C3[':c3:']'",
        "   call !keylist(l)",
        "   crt 'L2[':change(change(l, @fm, '/'), @vm, '|'):']'",
        "   call !keyset('other', kb, ido)",
        "   c4 = iconv('v4', 'XE;other')",
        "   crt 'C4[':c4:']'",
        "   x = oconv(c1, 'XE;other')",
        "   crt 'XO[':(x = c1):'|':status():']'",
        "   call !keyclear('MIXED.case_1', n)",
        "   crt 'CLR[':n:']'",
        "   x = oconv(c1, 'XE;mixed.case_1')",
        "   crt 'AFTER[':(x = c1):'|':status():']'",
        "   x = oconv(c4, 'XE;other')",
        "   crt 'OTHER[':x:'|':status():']'",
        "   call !keyclear('nosuch', n)",
        "   crt 'CLRNONE[':n:'|':status():']'",
        "   call !keyclear('bad!name', n)",
        "   crt 'CLRBAD[':len(n):'|':status():']'",
        "   call !keylist(l)",
        "   crt 'L3[':change(change(l, @fm, '/'), @vm, '|'):']'",
        "   call !keyset(str('n', 31), ka, id31)",
        "   crt 'N31[':len(id31):'|':status():']'",
        "   call !keyset(str('n', 32), ka, id32)",
        "   crt 'N32[':len(id32):'|':status():']'",
        "   call !keyset('', ka, idd)",
        "   crt 'DEFAULT[':len(idd):'|':status():']'",
        "   x = oconv(iconv('named default', 'XE'), 'XE;default')",
        "   crt 'DEFNAME[':x:']'",
        "   call !keyclear('', n)",
        "   crt 'CLRDEF[':n:']'",
        "end", ""]),
    # what !KEYSET refuses, and a ring that did not change
    "zzxe5": "\n".join([
        "   salt = '%s'" % SALT,
        "   ka = sdkey('pass A', salt)",
        "   call !keyset('good', ka, id0)",
        "   call !keylist(l) ; n0 = dcount(l, @fm)",
        "   call !keyset('bad!', ka, id)",
        "   crt 'BADNAME[':len(id):'|':status():']'",
        "   call !keyset('x', 'short', id)",
        "   crt 'SHORT[':len(id):'|':status():']'",
        "   call !keyset('x', str('!', 44), id)",
        "   crt 'NOTB64[':len(id):'|':status():']'",
        "   call !keyset('x', '', id)",
        "   crt 'EMPTYKEY[':len(id):'|':status():']'",
        "   call !keylist(l)",
        "   crt 'UNCHANGED[':(dcount(l, @fm) = n0):'|':dcount(l, @fm):']'",
        "   call !keyclear('*', n)",
        "   crt 'ALL[':n:']'",
        "   for i = 1 to 16",
        "      call !keyset('full':i, sdrandkey(), id)",
        "      if id = '' then crt 'FAILED':i:'[':status():']'",
        "   next i",
        "   call !keylist(l)",
        "   crt 'N16[':dcount(l, @fm):']'",
        "   call !keyset('seventeen', sdrandkey(), id)",
        "   crt 'X17[':len(id):'|':status():']'",
        "   call !keylist(l)",
        "   crt 'STILL16[':dcount(l, @fm):']'",
        "   call !keyclear('full3', n)",
        "   call !keyset('seventeen', sdrandkey(), id)",
        "   crt 'OK17[':len(id):'|':status():']'",
        "   call !keyclear('*', n)",
        "   crt 'CLEARALL[':n:']'",
        "   call !keylist(l)",
        "   crt 'EMPTY[':len(l):']'",
        "end", ""]),
    # the query fixture: records of tokens made by this script (arguments 1-3 the salaries, 4-6 the secrets), and the dictionary
    "zzxemk": "\n".join([
        "   open 'zzenc' to f else crt 'NOFILE' ; stop",
        "   open 'DICT zzenc' to d else crt 'NODICT' ; stop",
        "   write 'Ann':@fm:field(@sentence, ' ', 4):@fm:field(@sentence, ' ', 7):@vm:field(@sentence, ' ', 8) on f, 'r1'",
        "   write 'Bob':@fm:field(@sentence, ' ', 5):@fm:field(@sentence, ' ', 9) on f, 'r2'",
        "   write 'Cy':@fm:field(@sentence, ' ', 6) on f, 'r3'",
        "   write 'Di' on f, 'r4'",
        "   write 'D':@fm:'1':@fm:'':@fm:'Name':@fm:'10L':@fm:'S' on d, 'NAME'",
        "   write 'D':@fm:'2':@fm:'XE;salary':@fm:'Salary':@fm:'70L':@fm:'S' on d, 'SALW'",
        "   write 'D':@fm:'2':@fm:'':@fm:'Raw':@fm:'70L':@fm:'S' on d, 'RAW'",
        "   write 'I':@fm:'OCONV(RAW,\"XE;salary\")':@fm:'':@fm:'Dec':@fm:'30L':@fm:'S' on d, 'DEC'",
        "   write 'I':@fm:'SALW * 2':@fm:'':@fm:'Dbl':@fm:'10R':@fm:'S' on d, 'DOUBLE'",
        "   write 'D':@fm:'3':@fm:'XE;salary':@fm:'Sec':@fm:'30L':@fm:'M' on d, 'SEC'",
        "   write 'D':@fm:'3':@fm:'':@fm:'SecRaw':@fm:'70L':@fm:'M' on d, 'SECRAW'",
        "   crt 'MADE'",
        "end", ""]),
    # a LIST over a big file does one OCONV per value: how long do 20,000 of each take (seconds, the TIME() clock)
    "zzxeperf": "\n".join([
        "   call !keyset('', sdkey('%s', '%s'), id)" % (PW, SALT),
        "   c = iconv('salary 41250', 'XE')",
        "   t0 = time()",
        "   for i = 1 to 20000",
        "      x = oconv(c, 'XE')",
        "   next i",
        "   crt 'DEC[':(time() - t0):'|':(x = 'salary 41250'):']'",
        "   t0 = time()",
        "   for i = 1 to 20000",
        "      y = iconv('salary 41250', 'XE')",
        "   next i",
        "   crt 'ENC[':(time() - t0):'|':(oconv(y, 'XE') = 'salary 41250'):']'",
        "end", ""]),
    "zzxeset": "   " + DEF_KEY + "\n   crt 'SET[':id:'|':status():']'\nend\n",
    "zzxewrong": "   call !keyset('salary', sdkey('a different passphrase', '%s'), id)\n   crt 'SET[':id:'|':status():']'\nend\n" % SALT,
    "zzxecmp": "\n".join([
        "   open 'zzenc' to f else crt 'NOFILE' ; stop",
        "   open 'zzenc2' to g else crt 'NOFILE2' ; stop",
        "   for each id in 'r1':@fm:'r2':@fm:'r3':@fm:'r4'",
        "      read a from f, id else a = '~'",
        "      read b from g, id else b = '!'",
        "      crt 'CP:':id:'[':(a = b):'|':(a # ''):']'",
        "   next id",
        "end", ""]),
    "zzxering": "   call !keylist(l)\n   crt 'RING[':change(change(l, @fm, '/'), @vm, '|'):'] WHO[':@who:']'\nend\n",
}

# administrator programs, for the phantom rows (a phantom cannot be started in an ordinary fixture account of the sandbox)
PH_PARENT = "\n".join([
    "   open 'zzphlog' to g else crt 'NOLOG' ; stop",
    "   delete g, 'out'",
    "   " + DEF_KEY,
    "   call !keylist(l)",
    "   crt 'PARENT[':dcount(l, @fm):']'",
    "   execute 'PHANTOM NO.MSG RUN bp zzphp' capturing j",
    "   line = '' ; done = @false ; waited = 0",
    "   loop",
    "      read line from g, 'out' else line = ''",
    "      if index(line, 'DONE', 1) then done = @true",
    "   until done or waited >= 40 do",
    "      sleep 1",
    "      waited = waited + 1",
    "   repeat",
    "   crt 'PHANTOM[':line:']'",
    "end", ""])
PH_CHILD = "\n".join([
    "   open 'zzphlog' to g else stop",
    "   call !keylist(l)",
    "   out = 'RING=':dcount(l, @fm)",
    "   x = iconv('secret', 'XE;salary')",
    "   out := ',IC=':len(x):':':status()",
    "   call !keyset('salary', sdkey('phantom passphrase', '%s'), id)" % SALT,
    "   y = iconv('inside the phantom', 'XE;salary')",
    "   out := ',RT=':oconv(y, 'XE;salary')",
    "   out := ',DONE'",
    "   write out on g, 'out'",
    "end", ""])


def tg(lines, name):
    """The first NAME[...] value of a program's output lines, or None."""
    t = q3_tag(lines, name)
    return t[0] if t else None


q3_tag = None


def part2(box, ref):
    """Layer 3, on the sandbox part 1 used (running)."""
    global q3_tag
    say("\n======================================================================================================================")
    say("PART 2 - the XE conversion, the key ring, !KEYSET / !KEYCLEAR / !KEYLIST, ENCRYPT.KEY")
    spec = importlib.util.spec_from_file_location("q3", os.path.join(HERE, "sandbox-stmt-q3.py"))
    q3 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(q3)
    q3_tag = q3.tag
    q3.BOX = box
    q3.SYS = os.path.join(box, "sys")
    q3.SD = os.path.join(q3.SYS, "bin", "sd")
    q3.USER_PROGS = L3_PROGS
    plain, adm = q3.plain, q3.adm
    # the audit trail: SD appends to sys/audit and never creates it (an installed system has it, append-only); here it is an empty file
    # the sandbox user can append to, so that "nothing secret reached the audit trail" is a search of something
    if not os.path.exists(os.path.join(q3.SYS, "audit")):
        os.close(os.open(os.path.join(q3.SYS, "audit"), os.O_CREAT | os.O_WRONLY, 0o666))
    KEY = base64.b64decode(ref)
    ID = key_id(KEY)
    zzaa = os.path.join(box, "user_accounts", "zzaa")
    q3.prepare()
    q3.build_account("zzaa")
    q3.build_account("zzab")
    verb = plain("zzaa", ["encrypt.key list"])
    row("G0: the verb ENCRYPT.KEY is in an ordinary account's VOC (newvoc) and answers LIST with an empty ring",
        q3.has(verb, r"The key ring is empty\."), repr(verb[-3:]))

    def run(prog, *args, account="zzaa"):
        return plain(account, ["RUN bp %s %s" % (prog, " ".join(args)) if args else "RUN bp %s" % prog])

    # ------------------------------------------------------------------------------------------------------------ A
    say("\n--- A. the conversion both ways, held against libsodium outside SD ------------------------------------------")
    o = run("zzxe1")
    k = tg(o, "KEY")
    row("A0: the program ran and SD's key is the one libsodium makes outside it (so every token below is checkable here)",
        k == ref and tg(o, "ID1") == ID.hex() + "|0", "KEY %r ID1 %r" % (k, tg(o, "ID1")))
    c1, c2 = tg(o, "C1"), tg(o, "C2")
    p1 = b"salary 41250"
    ok_shape = False
    detail = ""
    try:
        ver, kid, nonce, body = parts(c1)
        ok_shape = (ver == 1 and kid == ID and len(nonce) == 24 and len(body) == 16 + len(p1))
        detail = "version %s id %s nonce %d body %d" % (ver, kid.hex(), len(nonce), len(body))
    except Exception as e:
        detail = "not base64: %r (%s)" % (c1, e)
    row("A1: ICONV XE gives base64 of version 1 | key id (first 4 bytes of SHA-256 of the key) | 24 byte nonce | 16 byte tag and the bytes",
        ok_shape, detail)
    row("A2: ... and the value opens with the key, outside SD, to the plaintext that went in", c1 is not None and open_token(KEY, c1) == p1,
        "opened %r" % (open_token(KEY, c1) if c1 else None))
    row("A3: encrypting the same value twice gives two different values (a fresh nonce), both of which open (CONTROL for A2)",
        c1 != c2 and c2 is not None and open_token(KEY, c2) == p1 and tg(o, "DIFF") == "1", "C1 %r C2 %r" % (c1, c2))
    row("A4: STATUS() after the encrypt is 0", tg(o, "S1") == "0", repr(tg(o, "S1")))
    row("A5: OCONV XE gives the plaintext back, status 0; the code and the key name are case blind (xe;Default)",
        tg(o, "R1") == "salary 41250|0" and tg(o, "R2") == "salary 41250|0", "%r %r" % (tg(o, "R1"), tg(o, "R2")))
    row("A6: the value is printable, with no field, value, subvalue, text or item mark in it",
        c1 is not None and re.fullmatch(r"[A-Za-z0-9+/=]+", c1) is not None and tg(o, "MARKS") is not None and tg(o, "MARKS").endswith("|0"),
        "marks in it: %r" % tg(o, "MARKS"))
    row("A7: a value holding every mark and a high byte comes back whole", (tg(o, "MARKS") or "").startswith("1|"), repr(tg(o, "MARKS")))
    row("A8: a 30,000 character value comes back whole and its token is the 40,060 characters base64 of 29 + 16 + 30,000 bytes make",
        tg(o, "BIG") == "1|40060", repr(tg(o, "BIG")))
    row("A9: a number is encrypted as the text it prints as", tg(o, "NUM") == "12345", repr(tg(o, "NUM")))
    row("A10: the null string stays null both ways, status 0 (an empty field is still empty)",
        tg(o, "NULLI") == "0|0" and tg(o, "NULLO") == "0|0", "%r %r" % (tg(o, "NULLI"), tg(o, "NULLO")))
    row("A11: XE chains with another conversion (decrypt, then MCU)", tg(o, "CHAIN") == "SALARY 41250", repr(tg(o, "CHAIN")))
    o = run("zzxeperf")
    dec_t, enc_t = (tg(o, "DEC") or "?|?").split("|"), (tg(o, "ENC") or "?|?").split("|")
    row("A12: cost: 20,000 decryptions took %s s and 20,000 encryptions %s s (the limit here is 15 s each; the figures are the point)" % (dec_t[0], enc_t[0]),
        dec_t[0].isdigit() and enc_t[0].isdigit() and int(dec_t[0]) < 15 and int(enc_t[0]) < 15 and dec_t[1] == "1" and enc_t[1] == "1", repr((dec_t, enc_t)))

    say("\n--- B. tokens made HERE, with chosen nonces, decrypted by SD and refused when they are not right -----------------")
    rng = random.Random(18102026)

    def nonce():
        return bytes(rng.randrange(256) for _ in range(24))

    other_key = pwhash_key(b"another key", REF_SALT)
    t_ok = mk_token(KEY, b"made by python", nonce())
    t_v2 = mk_token(KEY, b"version two", nonce(), version=2)
    t_other = mk_token(other_key, b"someone else's", nonce())
    t_tamper = mutate_char(mk_token(KEY, b"tampered with", nonce()), 60)
    t_short = base64.b64encode(bytes([1]) + ID + nonce()).decode()
    t_empty = mk_token(KEY, b"", nonce())
    t_marks = mk_token(KEY, b"x\xfey\xfdz", nonce())
    o = run("zzxe2", t_ok, t_v2, t_other, t_tamper, t_short, t_empty, t_marks)
    for n_, (want, why) in enumerate([
            ("made by python|0", "a token this script made with the same key is decrypted"),
            ("<same>|10210", "version 2 is not an encrypted value of this format (10210) and the value is left as it is"),
            ("<same>|10209", "a token under another key is 'wrong key' (10209) - distinct from 'not encrypted' - and left as it is"),
            ("<same>|10212", "one character changed in the body is 'damaged' (10212): the tag is checked, never a wrong decryption"),
            ("<same>|10210", "a token cut off after the nonce is not an encrypted value (10210)"),
            ("|0", "a valid token for the empty plaintext decrypts to the null string"),
            ("x<F>y<V>z|0", "a plaintext with a field mark and a value mark inside comes back whole")], 1):
        row("B%d: %s" % (n_, why), tg(o, "T%d" % n_) == want, "got %r" % tg(o, "T%d" % n_))
    row("B8: text that is not base64 is left as it is: 10210", tg(o, "T8") == "not base64 !!!|10210", repr(tg(o, "T8")))
    row("B9: valid base64 that is too short for a header and a tag: 10210", tg(o, "T9") == "QUJD|10210", repr(tg(o, "T9")))
    row("B10: a number is read as the text it prints as: 10210", tg(o, "T10") == "123456|10210", repr(tg(o, "T10")))

    say("\n--- C. no key, a mistake in the code, a key under another name --------------------------------------------------")
    o = plain("zzaa", ["RUN bp zzxe3 " + t_ok])
    row("C1: ICONV with no key in the ring answers the null string and 10208 - never the plaintext", tg(o, "NI") == "0|10208", repr(tg(o, "NI")))
    row("C2: OCONV with no key leaves the stored value as it is, 10208 (a LIST shows the ciphertext, not a blank)", tg(o, "NO") == "1|10208", repr(tg(o, "NO")))
    for i_, code in enumerate(["XEfoo", "XE;bad!name", "XE;" + "a" * 32, "XX", "X", "XE;a b"], 1):
        row("C3.%d: the code %r is a bad conversion (2) both ways, and ICONV answers the null string, not the plaintext" % (i_, code),
            tg(o, "BI%d" % i_) == "0|2" and tg(o, "BO%d" % i_) == "secret|2", "BI %r BO %r" % (tg(o, "BI%d" % i_), tg(o, "BO%d" % i_)))
    row("C4: a key under ANOTHER name (wk) is 'no key' for the name nokey - and a token under the wrong key name is 10209 for wk",
        tg(o, "WK") == "1|10209" and tg(o, "NO2") == "1|10208" and tg(o, "NI2") == "0|10208", "%r %r %r" % (tg(o, "WK"), tg(o, "NO2"), tg(o, "NI2")))

    say("\n--- D. names, a second key under a name, the same key again, clearing, what !KEYSET refuses ----------------------")
    ka = pwhash_key(b"pass A", REF_SALT)
    kb = pwhash_key(b"pass B", REF_SALT)
    o = plain("zzaa", ["RUN bp zzxe4"])
    row("D1: a name given in mixed case is folded: the key is found under the lower case name; !KEYSET answers the key id (8 hex digits)",
        tg(o, "IDA") == key_id(ka).hex() + "|0" and tg(o, "ROT") == "v1|v2", "IDA %r ROT %r" % (tg(o, "IDA"), tg(o, "ROT")))
    c1_, c2_, c3_, c4_ = tg(o, "C1"), tg(o, "C2"), tg(o, "C3"), tg(o, "C4")
    ids = lambda t: parts(t)[1] if t else None
    row("D2: the first value is made under key A, the value after a second key B under the same name under key B (the newest encrypts)",
        c1_ and c2_ and ids(c1_) == key_id(ka) and ids(c2_) == key_id(kb) and open_token(ka, c1_) == b"v1" and open_token(kb, c2_) == b"v2",
        "C1 id %s C2 id %s" % (ids(c1_), ids(c2_)))
    row("D3: ... and BOTH still decrypt under that name (a key can be changed without losing the old values)", tg(o, "ROT") == "v1|v2", repr(tg(o, "ROT")))
    ia, ib = key_id(ka).hex(), key_id(kb).hex()
    row("D4: !KEYLIST: oldest first, name | key id | 1 for the key new values use (B), 0 for the older one (A); never a key",
        tg(o, "L1") == "mixed.case_1|%s|0/mixed.case_1|%s|1" % (ia, ib), repr(tg(o, "L1")))
    row("D5: the same key set again under the name makes it the newest again, takes no new slot, and new values use it",
        tg(o, "L2") == "mixed.case_1|%s|0/mixed.case_1|%s|1" % (ib, ia) and c3_ and ids(c3_) == key_id(ka) and open_token(ka, c3_) == b"v3",
        "L2 %r" % tg(o, "L2"))
    row("D6: a token under key A is 'wrong key' (10209) under the name other, which holds only key B; a token under B opens there",
        tg(o, "XO") == "1|10209" and c4_ and open_token(kb, c4_) == b"v4" and tg(o, "OTHER") == "v4|0", "XO %r OTHER %r" % (tg(o, "XO"), tg(o, "OTHER")))
    row("D7: !KEYCLEAR removes every key of a name (2), case blind; the value is then 'no key' (10208); the other name's key stays",
        tg(o, "CLR") == "2" and tg(o, "AFTER") == "1|10208" and tg(o, "L3") == "other|%s|1" % ib, "CLR %r AFTER %r L3 %r" % (tg(o, "CLR"), tg(o, "AFTER"), tg(o, "L3")))
    row("D8: clearing a name that is not there is 0 keys and not an error; a bad name gives the null string and 10213",
        tg(o, "CLRNONE") == "0|0" and tg(o, "CLRBAD") == "0|10213", "%r %r" % (tg(o, "CLRNONE"), tg(o, "CLRBAD")))
    row("D9: a name of 31 characters is accepted (8 hex digits, 0), 32 is refused (10213)", tg(o, "N31") == "8|0" and tg(o, "N32") == "0|10213", "%r %r" % (tg(o, "N31"), tg(o, "N32")))
    row("D10: the null name is 'default', which a bare XE and XE;default use; clearing the null name clears it",
        tg(o, "DEFAULT") == "8|0" and tg(o, "DEFNAME") == "named default" and tg(o, "CLRDEF") == "1", "%r %r %r" % (tg(o, "DEFAULT"), tg(o, "DEFNAME"), tg(o, "CLRDEF")))
    o = plain("zzaa", ["RUN bp zzxe5"])
    row("D11: !KEYSET refuses a bad name (10213), a key of the wrong length (10204), 44 characters that are not base64 (10203) and an "
        "empty key (10204) - each with the null string for the id", tg(o, "BADNAME") == "0|10213" and tg(o, "SHORT") == "0|10204"
        and tg(o, "NOTB64") == "0|10203" and tg(o, "EMPTYKEY") == "0|10204", repr([tg(o, x) for x in ("BADNAME", "SHORT", "NOTB64", "EMPTYKEY")]))
    row("D12: ... and the ring is as it was after the refusals", (tg(o, "UNCHANGED") or "").startswith("1|"), repr(tg(o, "UNCHANGED")))
    row("D13: the ring holds 16 keys: the 17th is refused with 10211 and the null string, the ring stays 16; after one is cleared it is accepted",
        tg(o, "ALL") == "1" and tg(o, "N16") == "16" and tg(o, "X17") == "0|10211" and tg(o, "STILL16") == "16" and tg(o, "OK17") == "8|0"
        and not [ln for ln in o if ln.startswith("FAILED")], repr([tg(o, x) for x in ("ALL", "N16", "X17", "STILL16", "OK17")]))
    row("D14: !KEYCLEAR('*') empties the ring (16 went) and !KEYLIST is then the null string", tg(o, "CLEARALL") == "16" and tg(o, "EMPTY") == "0",
        "%r %r" % (tg(o, "CLEARALL"), tg(o, "EMPTY")))

    say("\n--- E. a query verb, with the key, without it, and with the wrong one ---------------------------------------------")
    sal = [b"41250", b"39000", b"52000"]
    toks = None
    for _ in range(5000):
        cand = [mk_token(KEY, p, nonce()) for p in sal]
        by_tok = sorted(range(3), key=lambda i: cand[i])
        by_num = sorted(range(3), key=lambda i: int(sal[i]))
        if by_tok != by_num and not any(p.decode() in t for p in sal for t in cand):
            toks = cand
            break
    if toks is None:
        bail("could not make three tokens whose ciphertext order differs from the numeric order")
    sec = [b"sec A", b"sec B", b"sec C"]
    stoks = [mk_token(KEY, p, nonce()) for p in sec]
    plain("zzaa", ["CREATE.FILE zzenc DYNAMIC"])
    mk = run("zzxemk", *(toks + stoks))
    row("E0: the fixture file and dictionary were made from tokens this script made", q3.has(mk, r"^MADE$"), repr(mk[-3:]))
    t1, t2, t3 = toks
    order = ["r4"] + [("r1", "r2", "r3")[i] for i in sorted(range(3), key=lambda i: toks[i])]
    names_ = {"r1": "Ann", "r2": "Bob", "r3": "Cy", "r4": "Di"}
    plains = {"r1": "41250", "r2": "39000", "r3": "52000"}
    cipher = {"r1": t1, "r2": t2, "r3": t3}

    def rows_of(lines):
        got = {}
        for ln in lines:
            m = re.match(r"^(r\d)\s+(\S+)\s*(.*?)\s*$", ln)
            if m:
                got[m.group(1)] = (m.group(2), m.group(3))
        return got

    # with the right key
    o = plain("zzaa", ["RUN bp zzxeset", "LIST zzenc NAME SALW RAW"])
    got = rows_of(o)
    want = {k_: (names_[k_], plains[k_] + " " + cipher[k_]) if k_ != "r4" else ("Di", "") for k_ in names_}
    row("E1: LIST with the key held shows the salaries decrypted (the RAW column beside them is the stored token, unchanged)",
        all(got.get(k_, (None, None))[1].split()[:2] == want[k_][1].split()[:2] for k_ in plains) and got.get("r4", (None, None))[0] == "Di",
        repr(got))
    # without the key and with the wrong one: the stored ciphertext, in full
    for label, cmds in (("without the key", ["LIST zzenc NAME SALW RAW"]), ("with a key that is not the one", ["RUN bp zzxewrong", "LIST zzenc NAME SALW RAW"])):
        o = plain("zzaa", cmds)
        got = rows_of(o)
        row("E2: LIST %s shows the stored ciphertext (never a blank, never a number): the SALW column equals the RAW column" % label,
            all(got.get(k_, (None, ""))[1].split() == [cipher[k_], cipher[k_]] for k_ in plains) and got.get("r4", (None, None))[0] == "Di",
            repr(got))
    # sort
    o = plain("zzaa", ["RUN bp zzxeset", "SORT zzenc BY SALW NAME SALW"])
    seen = [m.group(1) for ln in o for m in [re.match(r"^(r\d)\s", ln)] if m]
    numeric = ["r4"] + [("r1", "r2", "r3")[i] for i in sorted(range(3), key=lambda i: int(sal[i]))]
    row("E3: SORT BY the encrypted field sorts the CIPHERTEXT (null first, then token order), not the salaries - held with the key in the ring",
        seen == order and seen != numeric, "saw %s, ciphertext order %s, numeric order %s" % (seen, order, numeric))
    # with
    o = plain("zzaa", ["RUN bp zzxeset", 'LIST zzenc WITH SALW = "41250" NAME', 'LIST zzenc WITH RAW = "%s" NAME' % t1, 'LIST zzenc WITH SALW = "" NAME',
                       'COUNT zzenc WITH SALW # ""'])
    blocks, cur_ids = [], []
    for ln in o:
        m = re.match(r"^(r\d)\s", ln)
        if m:
            cur_ids.append(m.group(1))
        m = re.match(r"^(\d+) record\(s\) listed", ln)
        if m:
            blocks.append((int(m.group(1)), cur_ids))
            cur_ids = []
    row("E4: WITH SALW = '41250' finds NOTHING even with the key held (the literal is encrypted with a fresh nonce): the documented limit",
        len(blocks) == 3 and blocks[0] == (0, []), repr(blocks))
    row("E4b: ... and the same query on the stored token (CONTROL: WITH RAW = the token) finds r1, so the query machinery itself works",
        len(blocks) == 3 and blocks[1] == (1, ["r1"]), repr(blocks))
    row("E4c: WITH SALW = '' (the null string) finds the one empty record, r4 - the tell-tale that the field is empty",
        len(blocks) == 3 and blocks[2] == (1, ["r4"]), repr(blocks))
    row("E4d: COUNT of the records whose field is not empty is 3", q3.has(o, r"^3 record\(s\) counted"), repr(o[-2:]))
    # I-types
    o = plain("zzaa", ["RUN bp zzxeset", "LIST zzenc NAME DEC", "LIST zzenc DOUBLE"])
    got = rows_of(o)
    row("E5: an I-type that says OCONV(RAW, 'XE;salary') shows the salaries decrypted when the key is held",
        all(got.get(k_, (None, ""))[1].split()[:1] == [plains[k_]] for k_ in plains), repr(got))
    row("E6: an I-type that multiplies the converted field (SALW * 2) works on the stored ciphertext: an error, and no number - the "
        "plaintext is never an operand", q3.has(o, r"Non-numeric where numeric required") and not any("82500" in ln for ln in o), repr(o[-3:]))
    o = plain("zzaa", ["LIST zzenc NAME DEC"])
    got = rows_of(o)
    row("E7: the same I-type without the key shows the stored token (the first 30 characters: its column is 30 wide and wraps)",
        all(got.get(k_, (None, ""))[1].split()[:1] == [cipher[k_][:30]] for k_ in plains), repr(got))
    # multivalued
    o = plain("zzaa", ["RUN bp zzxeset", "LIST zzenc NAME SEC"])
    txt = "\n".join(o)
    row("E8: a multivalued encrypted field shows each value decrypted on its own line, with the key (sec A and sec B for r1, sec C for r2)",
        all(s_.decode() in txt for s_ in sec), txt[:400])
    o = plain("zzaa", ["LIST zzenc NAME SEC"])
    txt = "\n".join(o).replace("\n", "").replace(" ", "")
    row("E8b: ... and without the key each value is its stored token (wrapped in the column; read back together they are the token)",
        all(s_ in txt for s_ in stoks), txt[:200])
    # totals
    o = plain("zzaa", ["RUN bp zzxeset", "LIST zzenc NAME SALW TOTAL SALW"])
    row("E9: TOTAL of an encrypted field adds the ciphertext, which is 0: the plaintext sum (132250) is never shown",
        not any("132250" in ln for ln in o), repr(o[-4:]))
    # index
    plain("zzaa", ["RUN bp zzxeset", "CREATE.INDEX zzenc SALW", "BUILD.INDEX zzenc SALW"])
    blob = b""
    for dp, _d, fs in os.walk(os.path.join(zzaa, "zzenc")):
        for f_ in fs:
            with open(os.path.join(dp, f_), "rb") as fh:
                blob += fh.read()
    row("E10: an index built on the field WHILE THE KEY WAS HELD holds the ciphertext: the file has the token and no salary; "
        "CONTROL: it has the names, so the search is looking at the right bytes",
        t1.encode() in blob and all(p_ not in blob for p_ in sal) and b"Ann" in blob, "token %s, names %s" % (t1.encode() in blob, b"Ann" in blob))
    # copy
    plain("zzaa", ["CREATE.FILE zzenc2 DYNAMIC", "COPY FROM zzenc TO zzenc2 ALL"])
    o = run("zzxecmp")
    row("E11: COPY moves the ciphertext untouched, with no key in the ring: r1 to r4 are byte for byte the same in both files",
        all(tg(o, "CP:r%d" % i) == "1|1" for i in (1, 2, 3, 4)), repr([tg(o, "CP:r%d" % i) for i in (1, 2, 3, 4)]))

    say("\n--- F. the ring is the process's: LOGTO clears it, a phantom does not have it -----------------------------------")
    o = plain("zzaa", ["RUN bp zzxeset", "RUN bp zzxering", "LOGTO zzab", "RUN bp zzxering", "RUN bp zzxeset", "RUN bp zzxering", "LOGTO zzaa", "RUN bp zzxering"])
    rings = q3_tag(o, "RING")
    row("F1: the ring holds the key before LOGTO (CONTROL), is EMPTY in the new account, holds a key set there, and is EMPTY again back "
        "in the first account",
        len(rings) == 4 and rings[0] == "salary|%s|1] WHO[zzaa" % ID.hex() and rings[1] == "] WHO[zzab"
        and rings[2] == "salary|%s|1] WHO[zzab" % ID.hex() and rings[3] == "] WHO[zzaa", repr(rings))
    q3.put(os.path.join(q3.SYS, "bp", "zzphk"), PH_PARENT)
    q3.put(os.path.join(q3.SYS, "bp", "zzphp"), PH_CHILD)
    adm(["CREATE.FILE zzphlog DYNAMIC"])
    out = adm(["BASIC bp zzphk zzphp"])
    row("F2: the phantom programs compiled", q3.has(out, r"^Compiled 2 program\(s\) with no errors"), repr(out[-3:]))
    o = adm(["RUN bp zzphk"])
    ph = tg(o, "PHANTOM") or ""
    row("F3: a phantom started by a session that holds a key starts with an EMPTY ring (the parent held one), and ICONV there is 'no key' "
        "(10208) with the null string", tg(o, "PARENT") == "1" and "RING=0" in ph and "IC=0:10208" in ph, "parent %r, phantom %r" % (tg(o, "PARENT"), ph))
    row("F4: ... and the phantom can set its own key and use it (a round trip inside it)", "RT=inside the phantom" in ph, repr(ph))

    say("\n--- G. ENCRYPT.KEY: the verb, its hidden prompt, and nothing on disk ------------------------------------------------")
    pwv = b"verb passphrase one"
    kv = pwhash_key(pwv, REF_SALT)
    o = plain("zzaa", ["encrypt.key set salary %s" % SALT, pwv.decode(), "encrypt.key list", "LIST zzenc NAME SALW"])
    txt = "\n".join(o)
    row("G1: ENCRYPT.KEY SET asks for a passphrase and answers the key id of the key libsodium makes from it and the salt",
        "Key salary is set (key id %s)" % key_id(kv).hex() in txt, txt[:300])
    row("G2: ENCRYPT.KEY LIST names the key and its id and says it is the one new values use; it does not show a key",
        re.search(r"(?m)^salary\s+key id %s\s+\(new values are encrypted with this key\)" % key_id(kv).hex(), txt) is not None
        and base64.b64encode(kv).decode() not in txt, txt[:400])
    o = plain("zzaa", ["encrypt.key set salary %s" % SALT, REF_PW.decode(), "LIST zzenc NAME SALW"])
    got = rows_of(o)
    row("G3: the key ENCRYPT.KEY makes from the reference passphrase and salt opens the fixture's tokens: LIST shows the salaries",
        all(got.get(k_, (None, ""))[1].split()[:1] == [plains[k_]] for k_ in plains), repr(got))
    o = plain("zzaa", ["encrypt.key bogus", "encrypt.key set", "encrypt.key set a", "encrypt.key set a %s confirm extra" % SALT, "encrypt.key clear a b",
                       "encrypt.key list extra"])
    usage = [ln for ln in o if ln.startswith("Usage: encrypt.key")]
    row("G4: a command that is not one of the three forms prints the usage (6 of 6)", len(usage) == 6, repr(o))
    o = plain("zzaa", ["encrypt.key set bad!name %s" % SALT, "encrypt.key set okname notasalt", "encrypt.key list"])
    row("G5: a bad name and a bad salt are refused BEFORE the prompt: the next line is a command and not a passphrase (the ring is empty)",
        q3.has(o, r"The key name is not valid") and q3.has(o, r"The salt is not one that sdsalt\(\) makes") and q3.has(o, r"^The key ring is empty\."), repr(o))
    o = plain("zzaa", ["encrypt.key set a %s confirm" % SALT, "one", "two", "encrypt.key list"])
    row("G6: CONFIRM with two different passphrases sets no key", q3.has(o, r"The two passphrases are different") and q3.has(o, r"^The key ring is empty\."), repr(o))
    o = plain("zzaa", ["encrypt.key set a %s" % SALT, "", "encrypt.key list"])
    row("G7: an empty passphrase sets no key", q3.has(o, r"No passphrase was typed") and q3.has(o, r"^The key ring is empty\."), repr(o))
    o = plain("zzaa", ["encrypt.key set a %s" % SALT, "first", "encrypt.key set a %s" % SALT, "second", "encrypt.key set b %s" % SALT, "third",
                       "encrypt.key list", "encrypt.key clear a", "encrypt.key list", "encrypt.key clear", "encrypt.key list"])
    txt = "\n".join(o)
    k1_, k2_, k3_ = (key_id(pwhash_key(p_, REF_SALT)).hex() for p_ in (b"first", b"second", b"third"))
    lists = [(n_, i_, bool(c_)) for n_, i_, c_ in re.findall(r"(?m)^(\w+)\s+key id ([0-9a-f]{8})(\s+\(new values.*\))?\s*$", txt)]
    row("G8: two keys under a name and one under another: the first list shows all three, the newer of a name marked; CLEAR a takes the two "
        "(2 key(s)); CLEAR with no name takes the rest; the last list is empty",
        lists[:3] == [("a", k1_, False), ("a", k2_, True), ("b", k3_, True)] and q3.has(o, r"^2 key\(s\) removed")
        and q3.has(o, r"^1 key\(s\) removed") and lists[3:] == [("b", k3_, True)] and txt.rstrip().endswith("The key ring is empty."), repr(lists))
    # the pty: the passphrase is typed at a hidden prompt, and appears nowhere
    canary = "Pty-Canary-Passphrase-4471"
    kc = pwhash_key(canary.encode(), REF_SALT)
    kc_b64 = base64.b64encode(kc).decode()
    sys.path.insert(0, HERE)
    from ptydrive import PtySession
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"), TERM="xterm")
    env.pop("SDTEST_ADMIN", None)
    s = PtySession([q3.SD, "-azzaa"], zzaa, env, 120, 30)
    s.settle(1.5)
    s.type("TERM xterm\r")
    s.type("TERM 120,30\r")
    s.type("COMO ON zzcomo\r", idle=0.8)
    s.type("encrypt.key set pty %s confirm\r" % SALT, idle=1.0)
    s.type(canary + "\r", idle=1.0)
    s.type(canary + "\r", idle=1.5)
    s.type("encrypt.key list\r", idle=0.8)
    s.type("COMO OFF\r", idle=0.8)
    screen_txt = "\n".join(s.screen.lines())
    raw = s.raw
    s.type("OFF\r", idle=0.5)
    s.finish()
    row("G9: on a terminal the passphrase is never shown: the typed canary is nowhere in the bytes SD and the terminal wrote",
        canary.encode() not in raw and "Passphrase" in screen_txt, "raw has it: %s; screen: %s" % (canary.encode() in raw, screen_txt[-300:]))
    row("G10: the key id on the screen is that of the key derived outside SD from the canary and the salt",
        ("key id %s" % key_id(kc).hex()) in screen_txt, screen_txt[-400:])
    ctl = grep_tree(box, "encrypt.key set pty")
    row("G11: CONTROL: the search finds the command that WAS typed (in the command stack), so the next two rows are looking at the right "
        "places", len(ctl) >= 1, "no file holds it")
    au = grep_tree(box, "encrypt.key set name=pty")
    row("G11b: CONTROL: the audit trail is inside what is searched: it holds the line the verb wrote ('encrypt.key set name=pty'), and that "
        "line has the name and nothing secret", len(au) >= 1, "no file holds the audit line")
    hp = grep_tree(box, canary)
    row("G12: the canary passphrase is in no file of the sandbox - not $COMO, the command stack, the audit trail, the errlog, a work file",
        not hp, "found in %s" % hp[:3])
    hk = grep_tree(box, kc_b64)
    row("G13: the key made from it (base64) is in no file either", not hk, "found in %s" % hk[:3])
    comos = [os.path.join(dp, f_) for dp, _d, fs in os.walk(zzaa) for f_ in fs if "como" in dp.lower() or "como" in f_.lower()]
    row("G14: CONTROL: a $COMO file for this session exists in the account (the run was recorded, and the canary is not in it)",
        len(comos) >= 1, "no como file under %s" % zzaa)
    plain("zzaa", ["encrypt.key clear"])


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-crypt.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-crypt: sandbox %s (SDBOX_KEYSET %s)" % (box, os.environ.get("SDBOX_KEYSET", "0")))
    ref = reference_key()
    if ref is None:
        bail("libsodium could not be loaded through ctypes: the fixed-vector row has no reference")
    say("sandbox-crypt: reference key for the fixed vector (libsodium via ctypes): %s" % ref)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=1800)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-crypt: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    if "--part2" in sys.argv:        # layer 3 only, on a sandbox that part 1 has not touched or that already holds part 2's fixtures
        part2(box, ref)
        say("\nsandbox-crypt: %d passed, %d failed (PART 2 ONLY: not a verdict on the suite)" % (passed, failed))
        sys.exit(0 if failed == 0 else 1)

    cmds, names = [], []
    for i, (_, body, _w) in enumerate(CASES):
        nm = "zzcr%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write("   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'C%02d[':x:']'\nend\n" % i)
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    # the canary program: derives a key from a passphrase built at run time and prints it, so the key is known to this script
    canary = "zzcrcan"
    names.append(canary)
    with open(os.path.join(sysd, "bp", canary), "w") as f:
        f.write("   * %s\n   pw = '%s':'-':'%s'\n   k = sdkey(pw, sdsalt())\n   c = sdencrypt('plain canary value', k, 202)\n"
                "   crt 'KEY[':k:']'\n   crt 'PW[':pw:']'\nend\n" % (CONTROL_FRAG, CANARY_A, CANARY_B))
    cmds += ["BASIC bp %s" % canary, "RUN bp %s" % canary]
    try:
        out = sess(box, *cmds)
        say("\n--- the functions -------------------------------------------------------------")
        starts = [(mm.start(), mm.group(1)) for mm in re.finditer(r"(?m)^:BASIC bp (zzcr\d+)\s*$", out)]
        segs = {}
        for (a, nm), (b, _n2) in zip(starts, starts[1:] + [(len(out), "")]):
            segs[int(nm[4:])] = out[a:b]
        row("the compile output of every case was found in the session (%d programs)" % len(CASES), len(segs) == len(CASES),
            "found %d" % len(segs))
        for i, (label, _body, want) in enumerate(CASES):
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            if want == "REFERENCE":
                want = ref
            if isinstance(want, tuple):
                # a compile refusal: the compiler's own output for THIS program must say "with errors" and give the reason
                # wanted - a program that did not compile because the function is unknown (the tree before the change) says
                # something else - and the program must not have run
                seg = segs.get(i, "")
                reason = re.search(want[1], seg)
                row("%s (compiler says /%s/)" % (label, want[1]), m is None and "with errors" in seg and reason is not None,
                    "ran and printed %r" % got if m else "compiler output: %s" % " / ".join(seg.split("\n")[1:6]))
            else:
                row("%s: wanted %r" % (label, want), got == want, "got %r" % got if m else "no output")
        say("\n--- cold start: the first libsodium call of a process ------------------------------")
        for j, (label, body, want) in enumerate(COLD):
            nm = "zzcrcold%d" % j
            names.append(nm)
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write("   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'COLD[':x:']'\nend\n")
            cout = sess(box, "BASIC bp %s" % nm, "RUN bp %s" % nm)
            m = re.search(r"(?m)^COLD\[(.*)\]\s*$", cout)
            got = m.group(1) if m else None
            if want == "REFERENCE":
                want = ref
            row("%s: wanted %r" % (label, want), got == want, "got %r" % got if m else "no output; the session said: %s" % cout.strip()[-200:])
        say("\n--- key hygiene: nothing is written to disk ---------------------------------------")
        mk = re.search(r"(?m)^KEY\[(.*)\]\s*$", out)
        mp = re.search(r"(?m)^PW\[(.*)\]\s*$", out)
        key = mk.group(1) if mk else None
        pw = mp.group(1) if mp else None
        row("the canary program ran and printed a 44 character key and its passphrase",
            key is not None and len(key) == 44 and pw == "%s-%s" % (CANARY_A, CANARY_B), "key %r pw %r" % (key, pw))
        if key and pw:
            ctl = grep_tree(box, CONTROL_FRAG)
            row("CONTROL: the search finds a string that IS on disk (the canary program's source)", len(ctl) >= 1, "no file holds it")
            hits_pw = grep_tree(box, pw)
            row("the passphrase appears in no file of the sandbox (audit trail, errlog, como, work files)", not hits_pw, "found in %s" % hits_pw[:3])
            hits_key = grep_tree(box, key)
            row("the derived key appears in no file of the sandbox", not hits_key, "found in %s" % hits_key[:3])
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    part2(box, ref)

    say("\nsandbox-crypt: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
