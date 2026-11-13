# agent-pack: what an AI agent needs to work in SD Core for Windows

S.69 rows 1 and 1b of SD Core for Linux's AI plan, carried to Windows on 13 Nov 2026 (RELEASE_1.1 253a). Documents, a generator and free checks. **Only two parts of this directory are installed, and only as text:** `guide/` and `pack/` are copied by the installer to `C:\ProgramData\SD\sdsys\agent-pack\guide` and `...\pack`, writable by the administrators only. The skill, the templates, the recipe, the generator and these notes are not installed. Nothing here is compiled into SD, nothing in SD reads it, and nothing here calls a model, holds a key, opens a gate or changes ssh. An ordinary account cannot read the installed copy from inside SD (a path outside the account needs `os-on`); it is there for the administrator to copy to the machine where an agent runs.

| path | what | made by |
|---|---|---|
| `guide/sd-basic-guide.md` | the SD BASIC dialect guide: language, system, walls, 20+ worked programs | by hand; its blocks were compiled and run on SD Core for Linux, whose language code this tree shares |
| `pack/` | the generated knowledge pack: one chunk per TCL verb, query keyword, VOC type, dictionary type and conversion, BASIC statement, function, `$mode`, option, message, account word, setting and key group, with the source and line of each | `mkpack.py`, from THIS tree; guarded by `gplbld/test-pack-units.py` |
| `core-start.md` | the "start here" text embedded in the pack's core | by hand |
| `skill/sd-core/` | a Claude Code skill: `SKILL.md` by hand, `references/` (the guide and the pack) generated | `mkpack.py --write` |
| `templates/` | a CLAUDE.md template for a project that lives in an SD account; an `.mcp.json` shape that does NOT work yet | by hand |
| `recipe/agent-account.md` | the zero-code recipe: give the agent its own Windows user and SD account so the operating system is the wall | by hand |
| `PACKAGING.md` | the packaging facts verified from the official pages | by hand |

Regenerate after a change to a verb, a message, a bcomp table, a docs section the pack quotes, the shipped dictionaries, the guide or the stamp, from `sdb_ai\sd64`:

```
python agent-pack\mkpack.py --write
python gplbld\test-pack-units.py
```

The generator takes the tree and the docs checkout as arguments (`--tree DIR --docs DIR --out DIR --skill DIR --product NAME`). It reads the docs repository beside this one (`SDCore4WindowsDocs`) and exits 2, saying so, when the checkout is missing.

Line numbers in `src=path:line#hash` are locators that may lag after an edit elsewhere in the same file; the hash of the cited line is the identity and is what the check holds.
