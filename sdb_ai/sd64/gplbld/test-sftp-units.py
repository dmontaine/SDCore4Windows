#!/usr/bin/env python3
"""test-sftp-units.py - S.242 stage 3: the file transfer server inside sd, read as TEXT.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-sftp-units.py [--selftest]

No sudo, no install, no sd.  It reads gplsrc/sd_sftp.c and .h, the places that wire it in (sd.c, kernel.c, kernel.h, sysseg.h,
keys.h, op_kernel.c, gpl.src, gpl.bp/int$keys.h), the command processor gpl.bp/xfersrv, gplbld/ssh-forcecommand.sh and the
messages 15076 to 15094, with comments taken out, and holds the ORDER and the SHAPE of the rules:

    - sd is the transfer server only for no argument, no terminal and SSH_ORIGINAL_COMMAND exactly the Subsystem path the ssh
      arm writes; the channel leaves descriptors 0 and 1 before anything else in main() runs;
    - KERNEL(K$XFER) is for $internal programs; a slot is opened only where XFER is 1 and only by a terminal session; the
      server's operations only run in a transfer process;
    - the server finds a slot of the same user and account, live, whose process is there;
    - one directory, opened without following a link; no call in the file follows a path; a name is a record id as it stands;
    - an incoming file is checked (order, plain text, XFERFILE, XFERSLOT) BEFORE its bytes are written, goes to a part file,
      and gets its name without replacing unless the slot says overwrite; a RECEIVE slot gives nothing out, a SEND slot takes
      nothing in; remove and rename reach only this connection's own files;
    - gpl.bp/xfersrv asks XFER, the person, the register (suspended, a user account, xfer-on exactly 'YES'), then the slot, in
      that order, reads the register itself, never the VOC, and audits a refusal before it tells the client.

IT CANNOT SAY THAT ANYTHING IS REFUSED OR THAT A BYTE ARRIVES: that is gplbld/sandbox-sftp.py, which runs the real OpenSSH
client against a sandbox.  --selftest requires each mutation to be caught and to match its text exactly once.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.join(HERE, os.pardir)
FILES = {
    "sftp_c": "gplsrc/sd_sftp.c",
    "sftp_h": "gplsrc/sd_sftp.h",
    "sd_c": "gplsrc/sd.c",
    "kernel_c": "gplsrc/kernel.c",
    "kernel_h": "gplsrc/kernel.h",
    "sysseg_h": "gplsrc/sysseg.h",
    "keys_h": "gplsrc/keys.h",
    "op_kernel": "gplsrc/op_kernel.c",
    "gplsrc": "gpl.src",
    "intkeys": "sdsys/gpl.bp/int$keys.h",
    "xfersrv": "sdsys/gpl.bp/xfersrv",
    # 15 Nov 26 Windows port (RELEASE_1.1 299): Linux's ssh-forcecommand.sh is Windows' allow-ssh-groups.ps1 (a GLOBAL ForceCommand, no
    # Match arm), and the Subsystem command is the machine's stock one, which ssh-preflight.ps1 records and guarantees.
    "forcecmd": "gplbld/allow-ssh-groups.ps1",
    "preflight": "gplbld/ssh-preflight.ps1",
}
MESSAGES = list(range(15076, 15095))
FIELDS = ["xfer_dir", "xfer_flags", "xfer_files", "xfer_opened", "xfer_last", "xfer_bytes"]


def basic(src):
    """A BASIC program with its comment lines and ;* tails taken out."""
    return "\n".join(re.sub(r"\s*;\*.*$", "", ln) for ln in src.split("\n") if not ln.lstrip().startswith("*"))


def ccode(src):
    return re.sub(r"/\*.*?\*/", "", src, flags=re.S)


def fn(c, name):
    """The text of a C function, from its first line to its closing brace."""
    m = re.search(r"\n(?:Private\s+)?[A-Za-z_][\w \*]*\b%s\([^;{}]*\)\s*\{\n" % re.escape(name), c)
    if not m:
        return ""
    end = c.find("\n}\n", m.end())
    return c[m.start():end + 3] if end >= 0 else ""


def order(text, *needles):
    """Every needle is in the text, each after the one before."""
    at = -1
    for n in needles:
        p = text.find(n, at + 1)
        if p < 0:
            return False
        at = p
    return True


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    c = ccode(s["sftp_c"])
    h = ccode(s["sftp_h"])

    # --- the name sd answers to ---------------------------------------------------------------------------------------
    sub = re.search(r'#define SD_SFTP_SUBSYSTEM "([^"]+)"', h)
    # 15 Nov 26 Windows port: the name is the stock Subsystem command (ssh-preflight.ps1's record of sshd_config_default's four effective
    # directives), and SD's ForceCommand is written outside any Match block, so it covers the sftp subsystem of every account.
    arm = re.search(r"^#\s+Subsystem\s+sftp\s+(\S+)\s*$", s["preflight"], re.M)
    glob = "('ForceCommand \"' + $sdexe + '\"')" in s["forcecmd"] and "if ($lines[$i] -match '^\\s*Match\\b') { $at = $i; break }" in s["forcecmd"]
    ck("S1 the Subsystem command sd recognises (sd_sftp.h) is the stock one ssh-preflight.ps1 guarantees, and allow-ssh-groups.ps1's ForceCommand sits before the first Match (global)",
       sub and arm and sub.group(1) == arm.group(1) and glob, "%r / %r / global %s" % (sub and sub.group(1), arm and arm.group(1), glob))

    det = fn(c, "xfer_detect")
    ck("S2 xfer_detect() answers only for no argument, both ssh variables, the EXACT path and no terminal, in one test that returns",
       re.search(r"if \(\(argc != 1\) \|\| \(cmd == NULL\) \|\| \(conn == NULL\) \|\| \(strcmp\(cmd, SD_SFTP_SUBSYSTEM\) != 0\) \|\| isatty\(0\)\)\s+return;", det)
       and 'getenv("SSH_ORIGINAL_COMMAND")' in det and 'getenv("SSH_CONNECTION")' in det)
    ck("S3 ...and moves the channel off descriptors 0 and 1 (which get /dev/null) BEFORE it marks the process as the server",
       order(det, "fcntl(0, F_DUPFD_CLOEXEC", "fcntl(1, F_DUPFD_CLOEXEC", "dup2(nul, 0)", "dup2(nul, 1)", "is_xfer = TRUE;",
             "connection_type = CN_NONE;", 'strcpy(command_processor, "$xfersrv");'))
    main = fn(ccode(s["sd_c"]), "main")
    ck("S4 main() calls xfer_detect(argc) before it logs, reads the configuration or the command line",
       order(main, "xfer_detect(argc);", "openlog", "sd_init(argc, argv);", "comlin(argc, argv)") and main.count("xfer_detect(") == 1)

    # --- the key --------------------------------------------------------------------------------------------------------
    kh = ccode(s["keys_h"])
    ik = basic(s["intkeys"])
    ck("S5 K_XFER is 173 in keys.h and K$XFER is 173 in int$keys.h, and no other key has the number",
       re.search(r"#define K_XFER\s+173\b", kh) and len(re.findall(r"#define K_\w+\s+173\b", kh)) == 1
       and re.search(r"\$define K\$XFER\s+173\b", ik) and len(re.findall(r"\$define K\$[\w.]+\s+173\b", ik)) == 1)
    ck("S6 op_kernel.c gives K_XFER to k_xfer()", re.search(r"case K_XFER:\s+k_xfer\(descr, &result\);\s+break;", ccode(s["op_kernel"])))
    kx = fn(c, "k_xfer")
    ck("S7 k_xfer() refuses a program that is not $internal before it reads its argument",
       order(kx, "if (!(process.program.flags & HDR_INTERNAL)) {", "k_get_c_string(descr, arg"))
    op = kx[kx.find('strcmp(arg, "open")'):kx.find('strcmp(arg, "close")')]
    ck("S8 'open' refuses where XFER is not 1, then a process that is not a terminal session, before it writes the slot",
       order(op, "if (pcfg.xfer != 1)", "else if (is_xfer || is_phantom || is_sdApiSrvr || (connection_type == CN_NONE))",
             "my_uptr->xfer_dir = (u_int8_t)n;") and "XFS_OVERWRITE) && (n == XFER_IN)" in op)
    ck("S9 the server's operations (find, serve, refuse) come after the test that this process IS a transfer server; the slot's own do not",
       order(kx, 'strcmp(arg, "open")', 'strcmp(arg, "close")', 'strcmp(arg, "state")', "if (!is_xfer) {", 'strcmp(arg, "find")',
             'strcmp(arg, "serve")', 'strcmp(arg, "refuse")'))
    fd = kx[kx.find('strcmp(arg, "find")'):kx.find('strcmp(arg, "serve")')]
    ck("S10 'find' wants XFER 1, another process's cell, the same Linux user, the account named, a holder that is there and a LIVE slot",
       "(pcfg.xfer != 1)" in fd and "(u == my_uptr)" in fd and "strcmp(uname, process.username) != 0" in fd
       and "stricmp(acct, f2) != 0" in fd and "!xfer_holder_there(u->pid)" in fd and "xfer_slot_state(u, now, NULL) != XS_LIVE" in fd)
    sv = kx[kx.find('strcmp(arg, "serve")'):kx.find('strcmp(arg, "refuse")')]
    ck("S11 'serve' wants a slot found, opens the one directory without following a link, and writes the disconnect to the audit trail itself",
       order(sv, "(sx.h_index == 0)", "open(f2, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)", "S_ISDIR(dst.st_mode)", "sx_serve();",
             'sx_audit("xfer disconnect dir=%s why=%s'))

    # --- the wall -------------------------------------------------------------------------------------------------------
    nm = fn(c, "sx_name_ok")
    ck("S12 a name is refused if it starts with . or ~, holds a control character, DEL, a byte 248-255 or a character a directory file maps",
       "(name[0] == '.') || (name[0] == '~')" in nm and "(c < 32) || (c == 127) || (c >= 248)" in nm
       and "strchr(df_restricted_chars, (char)c) != NULL" in nm and "(n < 1) || (n > MAX_ID_LEN)" in nm)
    pa = fn(c, "sx_path")
    ck("S13 sx_path() refuses a NUL first, a '..' before it counts the part, and a second part",
       order(pa, "memchr(p, 0, (size_t)n) != NULL", "(p[i] == '.') && (p[i + 1] == '.'))\n      return -1;", "if (++comps > 1)\n      return -2;",
             "return sx_name_ok(name) ? 1 : -1;"))
    follows = re.findall(r"(?<![\w.>])(fopen|stat|lstat|rename|unlink|link|mkdir|rmdir|symlink|readlink|chmod|chown|truncate|creat|opendir|access|realpath)\(", c)
    opens = re.findall(r"(?<![\w.>])open\(([^;]*);", c)
    ck("S14 nothing in sd_sftp.c takes a path by name: the only open() calls are /dev/null and the one directory",
       follows == [] and len(opens) == 2 and '"/dev/null"' in opens[0] and opens[1].startswith("f2, O_RDONLY | O_DIRECTORY | O_NOFOLLOW"),
       "%r %r" % (follows, opens))
    oats = re.findall(r"openat\(([^;]*);", c)
    ck("S15 every openat() is on the directory's descriptor and either names '.' or does not follow a link (%d calls)" % len(oats),
       len(oats) >= 4 and all(o.startswith("sx.dirfd, ") and (o.startswith('sx.dirfd, ".", O_RDONLY | O_DIRECTORY') or "O_NOFOLLOW" in o) for o in oats),
       repr(oats))
    fsa = re.findall(r"fstatat\(([^;]*);", c)
    ck("S16 every fstatat() is AT_SYMLINK_NOFOLLOW; unlinkat, renameat, renameat2 and linkat are all on the directory's descriptor",
       fsa and all("AT_SYMLINK_NOFOLLOW" in f for f in fsa)
       and all(x.startswith("sx.dirfd, ") for x in re.findall(r"(?:unlinkat|renameat2?|linkat)\(([^;]*);", c)))

    # --- a file coming in -----------------------------------------------------------------------------------------------
    ro = fn(c, "rq_open")
    ins = ro[ro.find("if (sx.dir == XFER_IN) {"):ro.find("if ((pflags & (FXF_WRITE | FXF_APPEND")]
    ck("S17 an open in a RECEIVE slot refuses read, append or no-create, a kind not taken, a name that is there (always a link or a "
       "directory; a file unless the slot says overwrite) and a full slot, BEFORE the part file is made",
       order(ins, "if (!(pflags & FXF_WRITE) || (pflags & FXF_READ))", "if ((pflags & FXF_APPEND) || !(pflags & FXF_CREAT))",
             "if (!sx_kind_ok(name))", "if ((what != 0) && (!(sx.flags & XFS_OVERWRITE) || (what == 2) || (pflags & FXF_EXCL)))",
             "xfer_bytes >= ((int64_t)pcfg.xferslot * 1024)", 'snprintf(h->part, sizeof(h->part), ".part.%d.%d"',
             "openat(sx.dirfd, h->part, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, default_access)"))
    ck("S18 ...and a name that is not one (sx_path) is refused before the slot's direction is even looked at",
       order(ro, "what = sx_path(p, plen, name);", "if (what <= 0) {", "if (sx.dir == XFER_IN) {"))
    rw = fn(c, "rq_write")
    ck("S19 a write is checked - a write handle, not refused before, in order, plain text, XFERFILE, XFERSLOT - BEFORE a byte reaches the disk",
       order(rw, "if (h->kind != HK_WRITE)", "if (h->dead)", "if (offset != (u_int64_t)h->size) {", "if (!sx_plain(data, n)) {",
             "if ((h->size + n) > ((int64_t)pcfg.xferfile * 1024)) {", "xfer_bytes + h->size + n) > ((int64_t)pcfg.xferslot * 1024)) {",
             "put = write(h->fd, data + done", "EVP_DigestUpdate(h->md, data, (size_t)n)", "h->size += n;")
       and rw.count("sx_drop_part(h);") >= 4)
    pl = fn(c, "sx_plain")
    ck("S20 plain text: no NUL and no byte 248 to 255", "if ((*p == 0) || (*p >= 248))\n      return FALSE;" in pl)
    rc = fn(c, "rq_close")
    ck("S21 an incoming file gets its name only at its close, through sx_place(), after the slot's total is looked at again; a refused one fails",
       order(rc, "if (h->dead) {", "xfer_bytes + size) > ((int64_t)pcfg.xferslot * 1024))", "EVP_DigestFinal_ex(h->md, digest, &dlen)",
             "if (!sx_place(h->part, name)) {", 'sx_audit("xfer file dir=in bytes=%lld sha256=%s name=%s"', "sx_own_add(name);", "sx_count(1, size);"))
    sp = fn(c, "sx_place")
    ck("S22 sx_place() replaces only under XFS_OVERWRITE and never a link or a directory; otherwise RENAME_NOREPLACE, or a hard link",
       order(sp, "if (sx.flags & XFS_OVERWRITE) {", "if (sx_exists(to, NULL) == 2)\n      return FALSE;", "return renameat(sx.dirfd, from, sx.dirfd, to) == 0;",
             "renameat2(sx.dirfd, from, sx.dirfd, to, RENAME_NOREPLACE)", "linkat(sx.dirfd, from, sx.dirfd, to, 0)") and sp.count("renameat(") == 1)
    dp = fn(c, "sx_free_handle")
    ck("S23 a handle given up while a file was coming in deletes its part file (sx_drop_part unlinks it)",
       "if (h->kind == HK_WRITE)\n    sx_drop_part(h);" in dp and "unlinkat(sx.dirfd, h->part, 0)" in fn(c, "sx_drop_part"))

    # --- a file going out, and the rest ------------------------------------------------------------------------------------
    outs = ro[ro.find("if ((pflags & (FXF_WRITE | FXF_APPEND"):]
    ck("S24 an open in a SEND slot refuses every writing flag, does not follow a link and takes a plain file only",
       order(outs, "if ((pflags & (FXF_WRITE | FXF_APPEND | FXF_CREAT | FXF_TRUNC | FXF_EXCL)) || !(pflags & FXF_READ))",
             "openat(sx.dirfd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)", "!S_ISREG(st.st_mode)"))
    rr = fn(c, "rq_read")
    ck("S25 a read is of a read handle, and what was read is plain text before it is sent",
       order(rr, "if (h->kind != HK_READ)", "pread(h->fd, buf, want, (off_t)offset)", "if (!sx_plain(buf, (int32_t)got)) {", "return o_send();"))
    rm, rn = fn(c, "rq_remove"), fn(c, "rq_rename")
    ck("S26 remove and rename are for a RECEIVE slot and a file this connection took, tested before anything is unlinked or placed",
       order(rm, "(sx.dir != XFER_IN) || (sx_path(p, plen, name) != 1) || ((own = sx_own_find(name)) < 0)", "unlinkat(sx.dirfd, name, 0)")
       and order(rn, "(sx.dir != XFER_IN) || (sx_path(op, olen, from) != 1) || ((own = sx_own_find(from)) < 0)", "if (sx_path(np, nlen, to) != 1) {",
                 "if (!sx_kind_ok(to))", "((what != 0) && !(sx.flags & XFS_OVERWRITE)) || !sx_place(from, to)"))
    srv = fn(c, "sx_serve")
    ck("S27 the conversation: a length is checked before it is waited for, INIT comes first and once and is answered 3, a refusing "
       "server answers every request with its reason, and the slot is asked before each request",
       order(srv, "if ((len < 1) || (len > SX_MAX_PACKET)) {", "if (!sx_need((int32_t)len + 4))", "if (type == FXP_INIT) {", "o_u32(3);",
             "if (!started) {", "if (sx.refusing) {", "o_status(id, FX_PERMISSION_DENIED, sx.refuse_text);", "if (!sx_alive())", "switch (type) {")
       and re.search(r"case FXP_MKDIR:\s+case FXP_RMDIR:\s+ok = o_status\(id, FX_PERMISSION_DENIED", srv)
       and re.search(r"default:\s+ok = o_status\(id, FX_OP_UNSUPPORTED", srv))
    al = fn(c, "sx_alive")
    ck("S28 the connection goes on only while this process is not logged out, the cell is the one found (number, process, direction, "
       "opening time), its process is there and its slot is live",
       order(al, "my_uptr->events & (EVT_LOGOUT | EVT_TERMINATE)", "(h->uid != sx.h_uid) || (h->pid != sx.h_pid) || (h->xfer_dir != sx.dir) || (h->xfer_opened != sx.h_opened)",
             "!xfer_holder_there(sx.h_pid)", "switch (xfer_slot_state(h, now, NULL)) {") and "if (!sx_alive())\n      return FALSE;" in fn(c, "sx_need"))
    ss = fn(c, "xfer_slot_state")
    ck("S29 a slot ends at XFERMAX whatever happens, at XFERWAIT while no connection has come, at XFERIDLE after the last activity",
       order(ss, "if ((pcfg.xfermax > 0) && (age >= pcfg.xfermax))\n    return XS_MAX;", "if (u->xfer_last == 0) {", "if (age >= pcfg.xferwait)\n      return XS_WAIT;",
             "if (idle >= pcfg.xferidle)\n      return XS_IDLE;"))
    audits = re.findall(r'sx_audit\("([^"]*)"', c)
    ck("S30 every audit line this file writes begins 'xfer ' and is lower case up to its first '=' (%d lines)" % len(audits),
       len(audits) >= 10 and all(a.startswith("xfer ") and a.split("=")[0] == a.split("=")[0].lower() for a in audits), repr(audits))

    # --- the wiring -------------------------------------------------------------------------------------------------------
    sh = ccode(s["sysseg_h"])
    ik_ = fn(ccode(s["kernel_c"]), "init_kernel")
    ck("S31 the user table has the six slot fields, before file_map, and init_kernel() clears all six in the cell it takes",
       all(re.search(r"\b%s;" % f, sh) for f in FIELDS) and all(sh.find(f + ";") < sh.find("file_map[1];") for f in FIELDS)
       and all("my_uptr->%s = 0;" % f in ik_ for f in FIELDS))
    ck("S32 kernel.h declares is_xfer FALSE and the two descriptors -1; the server is 'sftp' in the user table; gpl.src builds sd_sftp",
       "Public bool is_xfer init(FALSE);" in s["kernel_h"] and "Public int xfer_fd_in init(-1);" in s["kernel_h"]
       and "Public int xfer_fd_out init(-1);" in s["kernel_h"] and 'if (is_xfer)\n        strcpy((char*)(my_uptr->ttyname), "sftp");' in ik_
       and "\nsd_sftp\n" in s["gplsrc"])

    # --- the command processor --------------------------------------------------------------------------------------------
    x = basic(s["xfersrv"])
    ck("S33 xfersrv is $internal, catalogued $xfersrv, a command processor, and its first statement ends a second entry",
       order(x, "$internal", "program xfersrv", "$catalog $xfersrv", "$flags cproc", "if kernel(K$CPROC.LEVEL,0) then goto exit.xfersrv",
             "void kernel(K$CPROC.LEVEL,1)"))
    ck("S34 ...asks, in this order: XFER, root or sdsys, sdusers, the hold, inhibit.login, the register, a user account, its group, "
       "suspended, xfer-on, the slot, and only then serves",
       order(x, "if config('XFER') # 1 then", "if acct = 'root' or acct = 'sdsys' then", "if not(is_grp_member(lgn, 'sdusers')) then",
             "call !acc_hold('TEST', hold.info, hold.err)", "call !login_inhibit('TEST', inhibit.info, inhibit.err)",
             "openpath @sdsys:@ds:'accounts' to acc.f else", "read acc.rec from acc.f, acct else", "if acc.rec<ACC$GROUP>[1,4] # 'sdu_' then",
             "if not(is_grp_member(lgn, acc.rec<ACC$GROUP>)) then", "if upcase(trim(acc.rec<ACC$SUSPENDED>)) = 'SUSPENDED' then",
             "if upcase(trim(acc.rec<ACC$XFER>)) # 'YES' then", "ans = kernel(K$XFER, 'find' : @fm : acct)", "if ans<1> # 'OK' then",
             "ans = kernel(K$XFER, 'serve' : @fm : acc.path : @ds : dir.name)"))
    refusals = len(re.findall(r"\n\s+goto refuse\b", x))
    ck("S35 ...every refusal (%d) goes to the one place that writes the audit line BEFORE it tells the client" % refusals,
       refusals >= 13 and order(x, "\nrefuse:", "void kernel(K$AUDIT, 'xfer refused reason=' : reason", "void kernel(K$XFER, 'refuse' : @fm : refusal)",
                                "\nexit.xfersrv:") and x.count("kernel(K$XFER, 'refuse'") == 1)
    ck("S36 ...the account is the one named after the Linux user, the directory a fixed name under the register's path, and no VOC is read",
       "lgn = kernel(K$USERNAME, 0)" in x and "acct = downcase(lgn)" in x and "acc.path = parse.pathname.tokens(acc.rec<ACC$PATH>)" in x
       and "dir.name = 'xfer.in'" in x and "dir.name = 'xfer.out'" in x and not re.search(r"(?i)\bvoc\b", x) and x.count("openpath ") == 1)

    # --- the messages -------------------------------------------------------------------------------------------------------
    missing = [n for n in MESSAGES if not s["msg"].get(n, "").strip()]
    used_c = sorted(int(n) for n in re.findall(r"#define XM_\w+\s+(\d+)", c))
    used_b = sorted(set(int(n) for n in re.findall(r"sysmsg\((15\d\d\d)", x)))      # 15 Nov 26 Windows port: Linux's 14xxx are 15xxx here (+1000)
    ck("S37 messages 15076 to 15094 exist; every one the C names (%d) and the program names (%d) is among them, and each is named by one of the two"
       % (len(used_c), len(used_b)), not missing and set(used_c) | set(used_b) == set(MESSAGES) and len(set(used_c)) == len(used_c),
       "missing %r, unused %r" % (missing, sorted(set(MESSAGES) - set(used_c) - set(used_b))))
    ck("S38 no message tells a person to type a command in capitals (receive, send, modify.account are lower case)",
       not any(re.search(r"\b(RECEIVE|SEND|MODIFY\.ACCOUNT|OVERWRITE)\b", s["msg"].get(n, "")) for n in MESSAGES))
    return rows


def load():
    out = {}
    for k, rel in FILES.items():
        p = os.path.join(SD, rel)
        if not os.path.isfile(p):
            print("REFUSING - no %s" % os.path.realpath(p), file=sys.stderr)
            sys.exit(2)
        with open(p, encoding="latin-1") as f:
            out[k] = f.read()
    out["msg"] = {}
    for n in MESSAGES:
        p = os.path.join(SD, "sdsys", "messages", str(n))
        if os.path.isfile(p):
            with open(p, encoding="latin-1") as f:
                out["msg"][n] = f.read()
    return out


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


MUTANTS = [
    ("sftp_h", "sd answers to another path than the ssh arm writes", '"/usr/local/sdsys/bin/sd-sftp"', '"/usr/lib/openssh/sftp-server"'),
    ("sftp_c", "any SSH_ORIGINAL_COMMAND that starts with the path", "(strcmp(cmd, SD_SFTP_SUBSYSTEM) != 0)", "(strncmp(cmd, SD_SFTP_SUBSYSTEM, 5) != 0)"),
    ("sftp_c", "a terminal session can be the server", " || isatty(0))\n    return;", ")\n    return;"),
    ("sftp_c", "the server is marked before the channel is moved", "  is_xfer = TRUE;\n  connection_type = CN_NONE;", "  connection_type = CN_NONE;"),
    ("sd_c", "main() logs before it looks", "  xfer_detect(argc);\n", ""),
    ("keys_h", "the key has another number in C", "#define K_XFER               173", "#define K_XFER               174"),
    ("sftp_c", "a program that is not $internal may use the key", "  if (!(process.program.flags & HDR_INTERNAL)) {\n    xfer_answer", "  if (0) {\n    xfer_answer"),
    ("sftp_c", "a slot opens with XFER 0", "    if (pcfg.xfer != 1)\n      xfer_answer(result, \"ERR%coff\", FIELD_MARK);\n    else if", "    if"),
    ("sftp_c", "a phantom may open a slot", "is_xfer || is_phantom || is_sdApiSrvr || (connection_type == CN_NONE)", "is_xfer || is_sdApiSrvr || (connection_type == CN_NONE)"),
    ("sftp_c", "any session may run the server's side", "  if (!is_xfer) {\n    xfer_answer(result, \"ERR%cserver\", FIELD_MARK);\n    return;\n  }\n", ""),
    ("sftp_c", "another user's slot is found", "(strcmp(uname, process.username) != 0) || ", ""),
    ("sftp_c", "a slot in another account is found", " || (stricmp(acct, f2) != 0)", ""),
    ("sftp_c", "a slot that ran out of time is found", "      if (xfer_slot_state(u, now, NULL) != XS_LIVE) {\n        expired = TRUE;\n        continue;\n      }\n", ""),
    ("sftp_c", "the directory may be a link", "open(f2, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)", "open(f2, O_RDONLY | O_DIRECTORY | O_CLOEXEC)"),
    ("sftp_c", "a name may start with a dot", "  if ((name[0] == '.') || (name[0] == '~'))\n    return FALSE;\n", "  if (name[0] == '~')\n    return FALSE;\n"),
    ("sftp_c", "a mark byte is a name", "(c < 32) || (c == 127) || (c >= 248)", "(c < 32) || (c == 127)"),
    ("sftp_c", "a slash is a name", "    if (strchr(df_restricted_chars, (char)c) != NULL)\n      return FALSE;\n", ""),
    ("sftp_c", "'..' is counted as a part", "    if (((j - i) == 2) && (p[i] == '.') && (p[i + 1] == '.'))\n      return -1;\n", ""),
    ("sftp_c", "a sub-directory is reached", "    if (++comps > 1)\n      return -2;\n", "    ++comps;\n"),
    ("sftp_c", "the part file follows a link", "O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, default_access", "O_WRONLY | O_CREAT | O_CLOEXEC, default_access"),
    ("sftp_c", "a file is stat'ed through a link", "fstatat(sx.dirfd, name, st, AT_SYMLINK_NOFOLLOW)", "fstatat(sx.dirfd, name, st, 0)"),
    ("sftp_c", "a file is opened by its path", "h->fd = openat(sx.dirfd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);", "h->fd = open(name, O_RDONLY | O_NONBLOCK | O_CLOEXEC);"),
    ("sftp_c", "a RECEIVE slot gives a file out", "    if (!(pflags & FXF_WRITE) || (pflags & FXF_READ))\n", "    if (!(pflags & FXF_WRITE))\n"),
    ("sftp_c", "a file that is there is replaced without overwrite", "(what != 0) && (!(sx.flags & XFS_OVERWRITE) || (what == 2) || (pflags & FXF_EXCL))", "(what == 2) || ((what != 0) && (pflags & FXF_EXCL))"),
    ("sftp_c", "a link is replaced under overwrite", "    if (sx_exists(to, NULL) == 2)\n      return FALSE; ", "    "),
    ("sftp_c", "the placing replaces", "renameat2(sx.dirfd, from, sx.dirfd, to, RENAME_NOREPLACE) == 0", "renameat2(sx.dirfd, from, sx.dirfd, to, 0) == 0"),
    ("sftp_c", "bytes are written before they are read", "  if (!sx_plain(data, n)) {\n    sx_audit(\"xfer refused reason=not plain text bytes=%lld name=%s\", (long long)h->size, h->name);\n    sx_drop_part(h);\n    return o_status(id, FX_FAILURE, sx_msg(XM_NOT_TEXT, h->name, NULL));\n  }\n", ""),
    ("sftp_c", "a NUL is plain text", "if ((*p == 0) || (*p >= 248))", "if (*p >= 248)"),
    ("sftp_c", "a hole may be written", "  if (offset != (u_int64_t)h->size) {\n    sx_drop_part(h);\n    return o_status(id, FX_FAILURE, sx_msg(XM_ORDER, NULL, NULL));\n  }\n", ""),
    ("sftp_c", "XFERFILE is not asked", "if ((h->size + n) > ((int64_t)pcfg.xferfile * 1024)) {", "if (0) {"),
    ("sftp_c", "XFERSLOT is not asked at a write", "if (((int64_t)UPtr(sx.h_index)->xfer_bytes + h->size + n) > ((int64_t)pcfg.xferslot * 1024)) {", "if (0) {"),
    ("sftp_c", "a refused file is still placed", "  if (h->dead) {\n    sx_free_handle(h);\n    return o_status(id, FX_FAILURE, NULL);\n  }\n", ""),
    ("sftp_c", "a part file is left behind", "  if (h->kind == HK_WRITE)\n    sx_drop_part(h); ", "  "),
    ("sftp_c", "a SEND slot takes a write", "(pflags & (FXF_WRITE | FXF_APPEND | FXF_CREAT | FXF_TRUNC | FXF_EXCL)) || !(pflags & FXF_READ)", "!(pflags & FXF_READ)"),
    ("sftp_c", "what goes out is not read first", "  if (!sx_plain(buf, (int32_t)got)) {", "  if (0) {"),
    ("sftp_c", "any file may be removed", "(sx_path(p, plen, name) != 1) || ((own = sx_own_find(name)) < 0)) {", "(sx_path(p, plen, name) != 1) || ((own = 0) < 0)) {"),
    ("sftp_c", "a file may be renamed in a SEND slot", "  if ((sx.dir != XFER_IN) || (sx_path(op, olen, from) != 1)", "  if ((sx_path(op, olen, from) != 1)"),
    ("sftp_c", "a request of any length is waited for", "    if ((len < 1) || (len > SX_MAX_PACKET)) {\n      sx.why = \"protocol\";\n      break;\n    }\n", ""),
    ("sftp_c", "the slot is not asked before a request", "    if (!sx_alive())\n      break;\n\n    switch (type) {", "    switch (type) {"),
    ("sftp_c", "a killed holder still holds", " ||\n      !xfer_holder_there(sx.h_pid)) {", ") {"),
    ("sftp_c", "XFERMAX is not asked", "  if ((pcfg.xfermax > 0) && (age >= pcfg.xfermax))\n    return XS_MAX;\n", ""),
    ("sftp_c", "an audit line in capitals", 'sx_audit("xfer remove name=%s", name);', 'sx_audit("xfer REMOVE name=%s", name);'),
    ("kernel_c", "a cell keeps the last process's slot", "    my_uptr->xfer_dir = 0;\n", ""),
    ("gplsrc", "sd_sftp is not built", "sd_sftp\n", ""),
    ("xfersrv", "the system switch is not asked", "   if config('XFER') # 1 then", "   if @false then"),
    ("xfersrv", "a blank xfer field is yes", "if upcase(trim(acc.rec<ACC$XFER>)) # 'YES' then", "if upcase(trim(acc.rec<ACC$XFER>)) = 'NO' then"),
    ("xfersrv", "a group account is taken", "   if acc.rec<ACC$GROUP>[1,4] # 'sdu_' then", "   if @false then"),
    ("xfersrv", "a suspended account is taken", "   if upcase(trim(acc.rec<ACC$SUSPENDED>)) = 'SUSPENDED' then", "   if @false then"),
    ("xfersrv", "the slot is looked for before the register is read", "   ans = kernel(K$XFER, 'find' : @fm : acct)\n   if ans<1> # 'OK' then", "   if ans<1> # 'OK' then"),
    ("xfersrv", "sdsys has a transfer", "   if acct = 'root' or acct = 'sdsys' then", "   if acct = 'root' then"),
    ("xfersrv", "a refusal is not audited", "   void kernel(K$AUDIT, 'xfer refused reason=' : reason : ' from=' : peer : ' user=' : lgn)\n", ""),
    ("xfersrv", "the directory comes from the VOC", "   ans = kernel(K$XFER, 'serve' : @fm : acc.path : @ds : dir.name)", "   open 'voc' to voc.f then readv dir.name from voc.f, dir.name, 2 else null\n   ans = kernel(K$XFER, 'serve' : @fm : dir.name)"),
    ("xfersrv", "a second entry runs again", "   if kernel(K$CPROC.LEVEL,0) then goto exit.xfersrv", "   if @false then goto exit.xfersrv"),
]


def selftest():
    s = load()
    if any(not ok for _, ok, _ in checks(s)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        report(checks(s))
        return 2
    start = 0
    for a in sys.argv[1:]:
        if a.startswith("--from="):
            start = int(a.split("=", 1)[1])
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text once (from mutant %d) ---" % start)
    for key, name, old, new in MUTANTS[start:]:
        if s[key].count(old) != 1:
            print("  [FAIL] %s: the text matches %d times in %s, not once" % (name, s[key].count(old), key))
            holes += 1
            continue
        t = dict(s)
        t[key] = s[key].replace(old, new)
        caught = [n.split()[0] for n, ok, _ in checks(t) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + ", ".join(caught[:3]) if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    print("%d mutants, %d not caught" % (len(MUTANTS) - start, holes))
    return 1 if holes else 0


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    s = load()
    print("test-sftp-units: the file transfer server (S.242 stage 3), read from %s" % os.path.realpath(SD))
    for k, rel in FILES.items():
        print("  input %-10s %s (%d bytes)" % (k, rel, len(s[k])))
    print("  input messages   sdsys/messages/15076 to 15094 (%d found)" % len(s["msg"]))
    rows = checks(s)
    if len(rows) < 38:
        print("REFUSING - only %d checks ran" % len(rows), file=sys.stderr)
        return 2
    bad = report(rows)
    print("%d passed, %d failed" % (len(rows) - bad, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
