# Templates

- `CLAUDE.md` is a template for the root of a project that lives in an SD account. Copy it, fill in every `{{...}}`, delete its first paragraph's instruction. It stays under 200 lines (Claude Code asks for that), carries the project's facts and rules, and leaves the knowledge of SD to the `sd-core` skill.
- `mcp.json.example` shows the shape of a project-scope `.mcp.json` for a **future** SD door. **IT DOES NOT WORK TODAY.** There is no `sd-mcp`: the external door (`sdctl`, S.69 row 2) is not built. And on an installed system `ssh agent@host sd-mcp` would not start it even if it existed: the ssh block ForceCommands every SD account into an interactive `sd` and discards the command the client asked for. Do not copy this file into a project as `.mcp.json` until the door exists and the ssh dispatcher has been changed to run it.

Packaging facts the two files rely on, and where they came from, are in `../PACKAGING.md`.
