# SD Core for Windows

A native Windows port of SD, the multivalue String Database, for multi-user
servers and workstations.

SD is a multivalue database in the Pr1me Information tradition, descended from
OpenQM and ScarletDME through [sdb64](https://codeberg.org/stringdatabase/sdb64),
which runs on Linux only. SD Core for Windows is SD rebuilt for Windows: a
Windows service, a Windows installer, and Windows security in place of the
Linux users, groups and permissions it relied on.

**Current release: W1.1-1** (29 Sep 2026), distributed as a zip on SourceForge.
It replaces W1.1-0, which carried non-English language support that should not
have been in it; SD Core is English only. See `sdb_ai/sd64/sdsys/changelog` for
what has changed.

## What you get

- **A single installer**, `sd-setup-W1.1-1.exe`. Nothing to compile and no
  dependencies to resolve; SD carries its own runtime beside `sd.exe`.
- **Fixed install locations** — programs in `C:\Program Files\SD`, data and
  configuration in `C:\ProgramData\SD` (the SDSYS account and
  `user_accounts`).
- **Many SD accounts**, created and maintained by an administrator working in
  the SDSYS account, which is entered only by an elevated sign-in.
- **Remote access** over ssh (Windows' own OpenSSH server, configured so that
  sessions land inside SD) and over the client API (TLS 1.3, SCRAM login). The
  installer asks which to open.
- **Optional Python**, installed from python.org's installer shipped in the
  release zip, for SD's embedded Python.

The installer needs an elevated session (it prompts for one) and cannot be run
silently. It refuses to start, and changes nothing, if another ssh server is
already installed or Windows' ssh server has been reconfigured.

## Requirements

Windows 10 or 11, 64-bit.

## Documentation

Installation guide, SD BASIC and TCL references, and the administrator's guide
are in the separate
[SDCore4WindowsDocs](https://github.com/dmontaine/SDCore4WindowsDocs)
repository.

## Building from source

This repository contains no binaries; everything is built from source.

- **C server and client library** — MSYS2 (the server against the MSYS2 POSIX
  runtime, the client library against native UCRT64). `make sd` from
  `sdb_ai/sd64`.
- **SD BASIC system programs** — compiled by the Python tooling in
  `sdb_ai/sd64/gplbld`.
- **Installer** — Inno Setup, from `sdb_ai/sd64/gplbld/sd.iss`.

`sdb_ai/sd64/gplbld/cycle.ps1` does all three and then installs the result.

## Related repositories

- [SDCore4WindowsSolo](https://github.com/dmontaine/SDCore4WindowsSolo) — a
  single-user edition that installs under one Windows user's home directory.
- [SDCore4Linux](https://github.com/dmontaine/SDCore4Linux) — SD Core for
  Linux, which tracks this project.

## Licence

SD, including the API, is licensed under the GPL v3.0. The install and delete
scripts are licensed under the Blue Oak Model License 1.0.0. The header of each
source file says which applies; see `sdb_ai/LICENSE`.
