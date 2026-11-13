# The agent account: a real wall for an AI agent, with no code

**Words used:** `ssh`, `bp-on`, `dict-on`, `none`, `suspended`, `sd-on`, `sh-on`, `os-on`

An agent that works on an SD project needs a place to work and a limit on what it can reach. Prompts, tool scopes and promises inside the agent's own software protect against mistakes and against instructions injected into data it reads. They do not stop an agent that holds a user's sign-in: it can open an interactive `sd` as that user and do anything the user can. **The wall is the operating system.** This recipe gives the agent a Windows user and an SD account of its own and nothing else, so what it can reach is what Windows and SD's gates allow that user.

It needs no code from this project and no change to an installed system. It does need a person who can sign in to Windows as SDSYS at the machine. Everything marked [unverified] below was read from the administrator documentation and the source and was not run end to end for this recipe. (This is the Windows form of SD Core for Linux's recipe: there the agent signs in with an ssh key; SD Core for Windows signs every ssh session in with the account's name and password, never a key.)

## Before you start

- The agent is **never you**. Do not give it your password, a shared password or a window that is already signed in.
- Decide what the agent is for (one project, one set of programs) and which files are its own. Everything else stays where it is, under other accounts the agent is not a member of.
- Decide which gates it needs. As delivered a new account has **every gate off**. Each word you add widens what an instruction hidden in a record could make the agent do, so add the fewest.

## Steps (signed in to Windows as SDSYS, in SD)

1. **Make the account.** For an agent that writes and compiles programs and nothing more:

   ```
   create.account user proj-agent ssh bp-on
   ```

   `ssh` gives the remote route; `bp-on` lets the account compile and catalogue (without it even `basic` is refused). It asks for a password for the new Windows user and `no.query` does not suppress that, so this cannot be scripted. [unverified: the prompt is documented in Administrator page 01, not run here]
   Leave `sh-on`, `os-on`, `sd-on`, `voc-on`, `dict-on`, `net-on`, `files-on` and `shared-write-on` off. Add `dict-on` only if the agent must create dictionary items, and say why in the project's record.

2. **Keep its password where only the agent's software reads it.** The agent signs in over ssh with `proj-agent` and that password. SD's ssh setup forces every session of an SD account into `sd` for that account, so the sign-in gives a session in SD and no command prompt. [unverified: read from `gplbld/allow-ssh-groups.ps1` and Administrator page 05, not run against this recipe]

3. **Give it a workspace.** Its own account directory is its workspace: a `bp` file for source, and whatever test files it creates. Populate it with **copies** of what it needs to read. If it must see real data, put that data in a group account of its own and add the agent as a member (`create.account group proj-shared no.query`, then `modify.account proj-shared add proj-agent`); the agent can then `logto` that account and the gates still apply there. [unverified] Do not use `sd-on` or `os-on` to reach data: they open paths, not one project.

4. **Tell it how to work.** Install the skill (`agent-pack/skill/sd-core/` into the project's `.claude/skills/sd-core/`) and put `agent-pack/templates/CLAUDE.md` in the project root, filled in. They carry the rules; they are not the wall. The installer puts the guide and the knowledge pack of the INSTALLED version under `C:\ProgramData\SD\sdsys\agent-pack\guide` and `...\pack` (text, writable by the administrators only); the agent's own account cannot read that path from inside SD (a path outside the account needs `os-on`, and you are not giving it that), so copy the two folders to the machine where the agent runs rather than opening a gate for it.

5. **Prove the wall before you trust it.** As the agent, run the probes of `guide/sd-basic-guide.md` part B2 in its account. Each one must be refused with the wording the guide quotes: the `sh` verb, `os.execute`, a path outside the account, a write to the VOC, a restricted statement, `$internal`. If any succeeds, a gate is open that you did not mean to open: find it with `modify.account` before the agent does any work.

6. **Keep the hand-over human.** The agent proposes; a person reads `bp/NAME` and copies it into the production account. The agent never has write access to production files, so it cannot promote its own work.

7. **Watch it.** Its logins and refusals are in the audit trail under its own user name, not yours. [unverified: the trail is `C:\ProgramData\SD\sdsys\audit`; read from the source]

8. **Take it back.** `modify.account proj-agent none` removes the ssh route; `modify.account proj-agent suspended` suspends the account; changing the Windows user's password stops the sign-in at the door. All three are the administrator's and take effect for the next session.

## What this does not give you

- **No scopes inside the account.** The agent can read, change and delete everything in its own account and in a group account it belongs to. That is why the production data is elsewhere.
- **No audit of content.** The trail names what the agent did, not what it saw.
- **No MCP door.** `sdctl` and `sd-mcp` are not built; the `.mcp.json` example in `templates/` shows the shape and does not work today. Over ssh the agent is driving `sd` itself, with commands piped to it.
- **No protection against a prompt that persuades the agent to ask you for more.** When it asks you to switch a gate on, the answer is yours, and the safe default is no.

## A checklist to keep in the project

- [ ] the agent has its own Windows user and SD account, and none of my sign-ins
- [ ] the gates on its account are the ones the project needs: `modify.account proj-agent` shows them
- [ ] the refusal probes of step 5 were run and every one was refused
- [ ] the project's production files are in accounts the agent is not a member of
- [ ] a person reviews everything before it reaches production
