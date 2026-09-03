# TCL verbs in SD, against OpenQM 2.6.6

Supplied by the repository owner, 14 Aug 2026. Usage is the same as OpenQM
2.6.6 unless noted.

**Read this before adding, renaming or removing a verb.** The structural fact
it records is the one that keeps being rediscovered:

> **SD has accounts, not accounts and users.** `CREATE.USER`, `DELETE.USER`,
> `ADMIN.USER`, `LIST.USERS` and `PASSWORD` are all deliberately absent.
> Everything is handled by `CREATE.ACCOUNT` and `DELETE.ACCOUNT`.

That is why `CREATE.ACCOUNT` provisions the Windows account itself rather than
expecting one to exist, and why the `CREATUSR` configuration gate — which asked
permission to do the second half of the only thing the verb does — was removed
on 14 Aug 2026. See PROJECT_STATUS.md §5.6.1 and §7.

**THE NAMES BELOW ARE WRITTEN IN UPPER CASE AND ARE STORED IN LOWER CASE.**
Since 18 Aug 2026 the VOC ids are `list`, `create.account` and so on
(PROJECT_STATUS.md §5.12 (b)); this table is left in upper case because it is a
comparison against OpenQM 2.6.6, which spells them that way. **It makes no
difference to what you type** — SD tries a name as typed, then lower, then
upper. What it changes is what SD prints back: `CT VOC LIST` answers
`VOC list`. The file-pointer entries moved on 19 Aug 2026 as far as `bp`,
`bp.out`, `gpl.bp` and `gpl.bp.out`; `VOC`, `NEWVOC`, `ACCOUNTS`, `MESSAGES`,
`SYSCOM` and `QFILE` are still upper case and are next, §5.12 (b).

**Verbs use `.` as the separator, never `_`** — `CREATE.ACCOUNT`, not
`CREATE_ACCOUNT`. Underscored names in `sdsys/gpl.bp` such as `CREATE_USER`,
`OS_GROUP` and `SET_PASSWD` are *subroutines*, catalogued globally as
`!create_user` and so on; they are not verbs and are not reachable from TCL.

## Available in SD

| Verb | Description |
|---|---|
| `*` | Comment |
| `$ECHO` | Paragraph tracing |
| `!` | Synonym for `SH` |
| `ABORT` | Abort processing and return to command prompt |
| `ALIAS` | Create a temporary alias for a command |
| `ANALYSE.FILE` | Analyse structure and usage of dynamic file |
| `ANALYZE.FILE` | Synonym for `ANALYSE.FILE` |
| `AUTOLOGOUT` | Set inactivity timer |
| `BASIC` | Compile QMBasic programs |
| `BELL` | Enable or disable audible alarm |
| `BUILD.INDEX` | Build an alternate key index |
| `CATALOG` | Synonym for `CATALOGUE` |
| `CATALOGUE` | Add program to system catalogue |
| `CD` | Synonym for `COMPILE.DICT` |
| `CLEARDATA` | Synonym for `CLEAR.DATA` |
| `CLEARINPUT` | Synonym for `CLEAR.INPUT` |
| `CLEARPROMPTS` | Synonym for `CLEAR.PROMPTS` |
| `CLEARSELECT` | Synonym for `CLEAR.SELECT` |
| `CLEAN.ACCOUNT` | Remove records from `$HOLD`, `$COMO` and `$SAVEDLISTS` |
| `CLEAR.ABORT` | Clear the abort status in an `ON.ABORT` paragraph |
| `CLEAR.DATA` | Clear the data queue |
| `CLEAR.FILE` | Remove all records from a file |
| `CLEAR.INPUT` | Clear keyboard type-ahead |
| `CLEAR.LOCKS` | Release task locks |
| `CLEAR.PROMPTS` | Clear inline prompt responses |
| `CLEAR.SELECT` | Clear one or all select lists |
| `CLEAR.STACK` | Clear the command stack |
| `CLR` | Clear display |
| `CNAME` | Rename a file or record within a file |
| `COMO` | Activate or deactivate command output files |
| `COMPILE.DICT` | Compile I-types in a dictionary |
| `CONFIG` | Display configuration parameters |
| `CONFIGURE.FILE` | Change file configuration parameters |
| `COPY` | Copy records |
| `COPY.LIST` | Copy a saved select list |
| `COPYP` | Copy command, Pick syntax |
| `COUNT` | Count records |
| `CREATE.FILE` | Create a file |
| `CREATE.INDEX` | Create an alternate key index |
| `CS` | Synonym for `CLR` |
| `CT` | Display records from a file |
| `DATA` | Add text to the data queue for associated verb or program |
| `DATE` | Display the date and time |
| `DATE.FORMAT` | Selects default date format |
| `DEBUG` | Debug QMBasic program |
| `DELETE` | Delete records from a file |
| `DELETE.CATALOG` | Synonym for `DELETE.CATALOGUE` |
| `DELETE.CATALOGUE` | Delete a program from the system catalogue |
| `DELETE.COMMON` | Delete a named common block |
| `DELETE.FILE` | Delete a file |
| `DELETE.INDEX` | Delete an alternate key index |
| `DELETE.LIST` | Delete a saved select list |
| `DISPLAY` | Display text |
| `DUMP` | Display records from a file in hexadecimal and character format |
| `ECHO` | Disable or enable keyboard echo |
| `ED` | Line editor |
| `EDIT` | Synonym for `ED` |
| `EDIT.LIST` | Edit a saved select list |
| `FORMAT` | Apply conventional formatting to a QMBasic program |
| `FORM.LIST` | Create a select list from a file record |
| `FSTAT` | Collect and report file statistics |
| `GENERATE` | Generate a QMBasic include record from a dictionary |
| `GET.LIST` | Retrieve a previously saved select list |
| `GET.STACK` | Restore a saved command stack |
| `GO` | Jump to a label within a paragraph |
| `HSM` | Hot Spot Monitor performance monitoring tool |
| `HUSH` | Disable or enable display output |
| `IF` | Conditional execution in paragraphs |
| `LIST` | List records from a file |
| `LIST.COMMON` | List named common blocks |
| `LIST.DIFF` | Form difference of two saved select lists |
| `LIST.FILES` | List details of open files |
| `LIST.INDEX` | List details of an alternate key index |
| `LIST.INTER` | Form intersection of two saved select lists |
| `LIST.ITEM` | List records from a file in internal format |
| `LIST.LABEL` | List records from a file in address label format |
| `LIST.LOCKS` | List task lock status |
| `LIST.READU` | List file, read and update locks |
| `LIST.UNION` | Form union of two saved select lists |
| `LIST.VARS` | List user `@`-variables |
| `LISTF` | List all files defined in the VOC |
| `LISTFL` | List all local files defined in the VOC |
| `LISTFR` | List all remote files defined in the VOC |
| `LISTK` | List all keywords defined in the VOC |
| `LISTPA` | List all paragraphs defined in the VOC |
| `LISTPH` | List all phrases defined in the VOC |
| `LISTQ` | List all indirect file references in the VOC |
| `LISTR` | List all remote items defined in the VOC |
| `LISTS` | List all sentences defined in the VOC |
| `LISTU` | List users currently in QM |
| `LISTV` | List all verbs defined in the VOC |
| `LOCK` | Set a task lock |
| `LOGMSG` | Write a message to the error log |
| `LOGOUT` | Terminate a phantom process |
| `LOGTO` | Change to an alternative account |
| `LOOP` / `REPEAT` | Defines loop within paragraph |
| `MAKE.INDEX` | Create and build an alternate key index |
| `MAP` | Display a list of the catalogue contents |
| `MERGE.LIST` | Create a select list by merging two other lists |
| `MESSAGE` | Send a message to selected other users |
| `MODIFY` | Modify records in a file |
| `NLS` | Set or report national language support values |
| `NSELECT` | Remove items from a select list |
| `OFF` | Synonym for `QUIT` |
| `OPTION` | Set, clear or display options |
| `PAUSE` | Display "Press return to continue" prompt |
| `PDEBUG` | Runs the phantom debugger |
| `PDUMP` | Generate a process dump file |
| `PHANTOM` | Initiate a background process |
| `PRINTER` | Administer print units |
| `PSTAT` | Report process status |
| `QSELECT` | Construct a select list from the content of selected records |
| `QUIT` | Terminate session or revert to lower command level |
| `RELEASE` | Release record or file locks |
| `RENAME` | Synonym for `CNAME` |
| `REPORT.SRC` | Display `@SYSTEM.RETURN.CODE` at command prompt |
| `REPORT.STYLE` | Sets the default style for query processor reports |
| `RUN` | Run a compiled QMBasic program |
| `SAVE.LIST` | Save a select list |
| `SAVE.STACK` | Save the command stack |
| `SEARCH` | Search file for records containing string(s) |
| `SELECT` | Select records meeting criteria |
| `SET` | Set a user `@`variable |
| `SET.DATE` | Set SD processing date |
| `SET.DEVICE` | Attach a tape device |
| `SET.EXIT.STATS` | Set final exit status value |
| `SET.FILE` | Set a Q-pointer to a remote file |
| `SET.TRIGGER` | Set, remove or display trigger function for a dynamic file |
| `SETPTR` | Set print unit characteristics |
| `SH` | Execute shell command |
| `SHOW` | Build select list interactively |
| `SLEEP` | Suspend process until specified time |
| `SORT` | List records sorted by record key |
| `SORT.ITEM` | List records sorted by record key in internal format |
| `SORT.LABEL` | List records in address label format, sorted by record key |
| `SP.CLOSE` | Close a print unit previously in "keep open" mode |
| `SP.OPEN` | Open a print unit in "keep open" mode |
| `SP.VIEW` | View and print records from `$HOLD` or other files |
| `SPOOL` | Send record(s) to the printer |
| `SSELECT` | Select records meeting criteria, sorting list by record key |
| `STATUS` | Display list of active phantom processes |
| `STOP` | Terminate an active paragraph |
| `SUM` | Report total of named fields |
| `TERM` | Set or display terminal window size |
| `TIME` | Display date and time |
| `UNLOCK` | Unlock a record or file |
| `UPDATE.ACCOUNTS` | Update VOC items from NEWVOC |
| `WHO` | Display user number and account name |
| `WHERE` | Display pathname of current account |

## Administrators only

| Verb | Description |
|---|---|
| `CREATE.ACCOUNT` | Make a new SD account |
| `DELETE.ACCOUNT` | Delete an SD account |

Since 14 Aug 2026 "administrator" means a Windows administrator
(PROJECT_STATUS.md §5.6.1). `CREATE.ACCOUNT` gained an `ADMINISTRATOR` keyword
on the same day:

```
CREATE.ACCOUNT USER <name> {ADMINISTRATOR} {NO.QUERY}
```

Without it the account is a standard Windows local user; with it the account is
added to Windows `Administrators` and therefore administers SD.

### How an account reaches the machine — 21 Aug 2026

An SD account reaches this machine **over ssh or through an API client**. The
console and Remote Desktop belong to Windows administrators: every account
`CREATE.ACCOUNT` makes joins `sdsshonly`, which is denied
`SeDenyInteractiveLogonRight` and `SeDenyRemoteInteractiveLogonRight`, and no
verb lifts that. `RDPACCOUNT`, which briefly did, was removed on 21 Aug 2026 —
it was named for Remote Desktop but Windows grades both denials together, so it
handed over the keyboard as well.

The two remaining routes are per account, and each is one Windows local group:

| Route | Group | Read by | Default for a new account |
|---|---|---|---|
| ssh | `sdssh` | sshd `AllowGroups` | **on** |
| API | `sdapi` | `APISRVR`, after the SCRAM proof | **off** |

```
MODIFY.ACCOUNT <account> SSH | NO.SSH
MODIFY.ACCOUNT <account> API | NO.API
```

Both are live at the next connection — sshd re-reads its configuration per
connection and `APISRVR` asks Windows per login, so neither waits on a Windows
sign-out the way a token-based check would.

Do not confuse these with `GRANT` / `REVOKE` / `LIST.GRANTS`, which answer a
different question: *who may use this account*, rather than *how may this person
reach the machine*.

## Not available — CRYPTO source was not in the original GPL release

`CREATE.KEY`, `DELETE.KEY`, `ENCRYPT.FILE`, `GRANT.KEY`, `LIST.KEYS`,
`RESET.MASTER.KEY`, `REVOKE.KEY`

Note this is about *file* encryption. It says nothing about the account
password machinery, which is SD's own and uses libsodium (PROJECT_STATUS.md
§5.6).

## Removed from SD, 23 Aug 2026

`PROC`, `SED` and `UPDATE.RECORD`, on the repository owner's decision.  PROC was
not a verb but a VOC record TYPE - an item of type `PQ` was interpreted by
`$PROC` - and a `PQ` item now reports that PROC is not supported rather than
running.  `SED` was the full-screen editor and `UPDATE.RECORD` the full-screen
record editor.

`ED`, the LINE editor, is unaffected and is the editor this system uses.  So is
`LIST`, `COUNT`, `SELECT` and everything else the QUERY processor runs - `$QPROC`
is a different program from `$PROC` despite the name.

## In OpenQM 2.6.6, deliberately not in SD

`ACCOUNT.RESTORE`, `ACCOUNT-SAVE`, `ADMIN.USER`, `BLOCK.PRINT`, `BLOCK.TERM`,
`CREATE.USER`, `DELETE.USER`, `FIND.ACCOUNT`, `FILE.SAVE`, `HELP`,
`LIST.USERS`, `LISTM`, `LISTPQ`, `LOGIN.PORT`, `MED`, `PASSWORD`, `PTERM`,
`RESTORE.ACCOUNTS`, `SECURITY`, `SEL.RESTORE`, `SET.ENCRYPTION.KEY.NAME`,
`SETPORT`, `SET.QUEUE`, `SP.ASSIGN`, `T.ATT`, `T.DET`, `T.DUMP`, `T.EOD`,
`T.FWD`, `T.LOAD`, `T.RDLBL`, `T.READ`, `T.REW`, `T.STAT`, `T.WEOF`,
`UPDATE.LICENCE`

The `T.*` set is tape handling. The user-management set —  `CREATE.USER`,
`DELETE.USER`, `ADMIN.USER`, `LIST.USERS`, `PASSWORD`, `SECURITY` — is the
group that matters for this port, and its absence is the design, not an
omission.
