# SD Core for Windows — source tree

The source of SD Core for Windows, a native Windows port of SD, the multivalue
String Database. The repository's top-level `README.md` describes the product.

SD is a multivalue database in the Pr1me Information tradition. It contains open
source code from OpenQM and ScarletDME, code written by the SD developers after
their fork from ScarletDME ([sdb64](https://codeberg.org/stringdatabase/sdb64)),
and the Windows port made in this project.

The tree contains no binaries. Everything is built from source.

| | |
|---|---|
| `sd64/gplsrc/` | the C source of the server, `sd.exe`, and the client library |
| `sd64/sdsys/` | the SDSYS system account as shipped: `gpl.bp` (the SD BASIC system programs), `messages`, `newvoc`, `voc_template`, and the `changelog` |
| `sd64/gplbld/` | the build: the Python tooling that compiles the SD BASIC system programs, the Inno Setup installer script `sd.iss`, the PowerShell scripts the installer places on the machine, and `cycle.ps1`, which builds and installs everything |
| `sd64/Makefile` | builds the C half — `make sd`, run from `sd64` |
| `sd64/examples/` | example programs, including embedded Python |
| `sd64/terminfo.src/` | terminal definitions |
| `sd64/bin/`, `sd64/gplobj/` | build output, not tracked |

See `sd64/sdsys/changelog` for the changes in each version.
