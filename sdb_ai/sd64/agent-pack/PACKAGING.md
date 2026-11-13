# Packaging facts for the skill, CLAUDE.md and .mcp.json, as verified

S.69 row 1. The AI integration evaluation (`.claude/ai-integration-evaluation.md`, O1) listed the packaging details as UNVERIFIED because only search summaries had been read. They were read from the official pages on 19 Oct 2026 (WebFetch of `code.claude.com/docs/en/skills`, `.../mcp` and `.../memory`; the answers below are those of the fetch tool's summary of each page, which said where it had not read the end of a long page). What follows is what was found, and what was not.

## Skills (`/docs/en/skills`)

- A skill is a folder with `SKILL.md`. Project skills live in `.claude/skills/<name>/SKILL.md`, personal ones in `~/.claude/skills/<name>/SKILL.md`, a plugin's in `<plugin>/skills/<name>/SKILL.md`. If names collide, enterprise beats personal beats project.
- `SKILL.md` has YAML front matter between `---` markers, **the opening `---` the first line of the file or the whole file is treated as content**. Every field is optional; only `description` is recommended; unrecognised fields are ignored without an error.
- Fields found: `name` (defaults to the directory name; no zero-width, control, private-use or bidi characters, no leading or trailing blanks, no `<` or `>`; `anthropic-skills` and `synced` are reserved), `description`, `when_to_use` (appended to the description), `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `allowed-tools` (pre-approves tools for the invoking turn), `disallowed-tools`, `model`, `effort`, `context`, `agent`, `background`, `hooks`, `shell`, `paths`, `metadata`, `license`, `compatibility` (up to 500 characters).
- **`description` plus `when_to_use` are truncated at 1,536 characters in the skill listing; the key use case goes first.** They are always in context; the body is loaded only when the skill is invoked or Claude decides the request matches.
- Supporting files are **not** loaded automatically: `SKILL.md` has to link them, with Markdown links, saying what each holds and when to read it. The page gives `references/` only as a naming example, not as a special folder. Scripts bundled with a skill are run, not read.
- `SKILL.md` body: the page recommends under 500 lines (a tip, not a limit). After compaction each invoked skill keeps its first 5,000 tokens, with a combined budget of 25,000.
- **This skill sets only `name`, `description` and `when_to_use`.** `gplbld/test-pack-units.py` check 9 fails on any other field: `allowed-tools` and `hooks` would widen what an AI may do, and that is a decision for the user who installs the skill, not for this folder.

## CLAUDE.md (`/docs/en/memory`)

- A project's file is `./CLAUDE.md` or `./.claude/CLAUDE.md`; a personal one `~/.claude/CLAUDE.md`; a private per-project one `./CLAUDE.local.md`. Files in the working directory and every directory above it load at launch; files in subdirectories load when Claude reads something there.
- **Target under 200 lines per file**; longer files cost context and reduce adherence. `@path/to/file` imports are expanded at launch and do not reduce the context cost (imported files load at launch too). External imports (outside the working directory) ask for approval once.
- CLAUDE.md is *context*, not enforcement; the page says to use a PreToolUse hook to block an action regardless of what Claude decides. It is also where "facts Claude should hold in every session" belong; a multi-step procedure or something that matters for one part of the code belongs in a skill. That is how this pack divides the work: the template holds the project's facts and rules, the skill holds the procedure and the reference.

## .mcp.json (`/docs/en/mcp`)

- Project scope is `.mcp.json` at the project root with a top-level `mcpServers` object. The page's own project example is an HTTP server; the page has **no stdio example for a project `.mcp.json`** (its stdio example is a plugin-root file with `command`, `args` and `env`). `"type": "stdio"` can be set explicitly. An entry with a `url` and no `type` is read as stdio and skipped with a configuration error.
- `${VAR}` and `${VAR:-default}` expand in `command`, `args`, `env`, `url` and `headers`; an unset variable with no default loads the server with the text unexpanded and a warning.
- A project-scoped server asks for approval in interactive sessions; in `claude -p`, Agent SDK and cloud sessions it loads **without asking**.
- `claude mcp add [options] <name> -- <command> [args...]`; scopes `local` (default, `~/.claude.json`), `project` (`.mcp.json`) and `user`.
- **Not documented, and not claimed here:** an ssh-based stdio server. `ssh -T user@host sd-mcp` as the `command` and `args` follows the general stdio pattern but is an inference. The example file is for that reason a shape, and `templates/README.md` says it does not work today.

## Not verified

- That Claude Code loads `references/` files on request in practice (the page says `SKILL.md` must link them; the skill does).
- The effect of a description that is the full 1,536 characters on triggering: nothing here measured when a model loads the skill. The benchmark of O1 (30 tasks with and without the guide) is not built.
- The `.mcp.json` example was not loaded by Claude Code.
