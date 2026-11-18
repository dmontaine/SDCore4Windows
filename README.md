# SD Core for Windows

SD, the multivalue String Database, for Windows — one of four SD Core versions
(Linux and Windows, each multi-user and single-user) that behave the same.

SD is a multivalue database in the Pr1me Information tradition, descended from
OpenQM and ScarletDME through [sdb64](https://codeberg.org/stringdatabase/sdb64).
SD Core for Windows follows [SD Core for Linux](https://github.com/dmontaine/SDCore4Linux),
the version the other three follow, and differs from it only where the
operating system requires it — a Windows service, a Windows installer, and
Windows security in place of the Linux users, groups and permissions.

**Current release: W1.1-3** (10 Oct 2026), distributed as a zip on SourceForge,
paired with SD Core for Linux L1.1-3. The next release of all four SD Core
versions is 2.0-0. See `sdb_ai/sd64/sdsys/changelog` for what each contains.

SD Core is English only: it has no support for other languages or locales.

## What you get

- **A single installer**, `sd-setup-W1.1-3.exe`. Nothing to compile and no
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

Windows 11, 64-bit.

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

- [SDCore4Linux](https://github.com/dmontaine/SDCore4Linux) — SD Core for
  Linux, the version the other three follow.
- [SDCore4LinuxSolo](https://github.com/dmontaine/SDCore4LinuxSolo) — SD Core
  Solo for Linux, a single-user Linux edition.
- [SDCore4WindowsSolo](https://github.com/dmontaine/SDCore4WindowsSolo) — a
  single-user Windows edition.

## Licence

Most of SD is licensed under the GPL v3.0; the install and delete scripts are
licensed under the Blue Oak Model License 1.0.0. The header of each source file
says which applies; see `sdb_ai/LICENSE`.
