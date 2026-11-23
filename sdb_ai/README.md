# SD Core for Windows — source tree

The source of SD Core for Windows, a multivalue database. It follows SD
Core for Linux, the version the other SD Core versions follow. The repository's
top-level `README.md` describes the product and how to build and install it.

SD is a multivalue database in the Pr1me Information tradition. It contains open
source code from OpenQM and ScarletDME, code written by the SD developers after
their fork from ScarletDME ([sdb64](https://codeberg.org/stringdatabase/sdb64)),
and the changes made in this project.

The tree contains no binaries. Everything is built from source; `cycle.ps1`
builds it and makes the installer.

| | |
|---|---|
| `sd64/gplsrc/` | the C source of the server, `sd.exe`, and the client library |
| `sd64/sdsys/` | the SDSYS system account as shipped: `gpl.bp` (the SD BASIC system programs), `messages`, `newvoc`, `voc_template`, and the `changelog` |
| `sd64/gplbld/` | the build: the Python tooling that compiles the SD BASIC system programs, the Inno Setup installer script `sd.iss`, the PowerShell scripts the installer places on the machine, and `cycle.ps1`, which builds and installs everything |
| `sd64/Makefile` | builds the C half — `make sd`, run from `sd64` |
| `sd64/agent-pack/` | the SD BASIC guide and knowledge pack for an AI agent; the installer copies `guide/` and `pack/` into the installation |
| `sd64/examples/` | example programs, including embedded Python |
| `sd64/terminfo.src/` | terminal definitions |
| `sd64/bin/`, `sd64/gplobj/` | build output, not tracked |

See `sd64/sdsys/changelog` for the changes in each version.
