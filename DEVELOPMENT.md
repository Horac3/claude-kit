# DEVELOPMENT.md — working on claude-kit itself

This is the handoff for whoever (human or Claude) works on the kit. Read it first, then the README.
`HOW_TO_USE.md` is the user guide. This file is about building and maintaining the kit.

## What the kit is

claude-kit is a Claude Code setup you install into Go and TypeScript projects, designed around four goals:

- **Token economy:** a small always-loaded context, rules that load only for matching paths, and filtered tool output.
- **Model routing by delegation:** `opusplan` in the main session, with Haiku, Sonnet and Opus subagents for checks, search, debugging and review. Never switch the main model mid-conversation.
- **Handoff through files:** one roadmap step per conversation, with state in `docs/progress.md`; `/clear` between steps.
- **Safety enforced by hooks:** deleting or discarding work is blocked deterministically.

It started from the author's own setup on a TypeScript monorepo. `examples/tally/` is a fictional project showing the result of migrating to the kit.

## Layout

```
install.sh                   installer and updater (bash). Hash manifest in the target: .claude/kit/manifest
kit/.claude/                 installed into every project (kit-owned, updatable)
  skills/                    kickoff (+ existing.md), next, tdd, fix, handoff, review, decide, commit, remap
  agents/                    test-runner (haiku), reviewer (opus), researcher (sonnet), debugger (sonnet)
  hooks/                     lib.sh, guard-bash.sh, guard-files.sh, session-context.sh
  kit/                       check.sh (filtered check runner), context.sh (repo summaries), statusline.sh
  rules/kit/                 working-rules.md, model-routing.md (always); hexagonal.md, docker.md (path-scoped)
stacks/go/.claude/           go.md rule
stacks/ts/.claude/           typescript.md, frontend.md rules; /ui skill; ui-checker agent; shot.mjs; design-pack.sh
scaffold/                    project-owned files created once: CLAUDE.md, docs/{progress,decisions,requirements}.md
examples/tally/              fictional project showing a migrated CLAUDE.md and path-scoped rules
tests/run.sh                 self-tests (121); KIT_TEST_TS=1 adds a real pnpm + vitest project (fails if pnpm is missing)
.github/workflows/ci.yml     shellcheck; tests on Ubuntu (+ TS) and macOS bash 3.2
```

`install.sh` generates `.claude/settings.json` and `.claude/kit/commands.env` per stack and package manager, in `gen_settings` and `gen_commands`.

## Invariants: do not break these

1. **The installer never deletes and never overwrites user changes.**
   - Kit files are replaced only if their hash matches the manifest; otherwise the new version is written as `<file>.kit-new`.
   - Project files are never overwritten.
   - `.gitignore` is only appended to.
   - Obsolete files are reported, not removed.
2. **Hooks have no hard dependencies.** `lib.sh` uses jq, falls back to python3, then node, then a regex parser. Keep it that way.
3. **`guard-bash.sh` strips quoted strings and heredoc bodies before matching**, so commit messages that mention `rm` or `clean` still pass. `bash -c "..."` and `eval` are checked unstripped. Every new pattern needs block *and* allow tests.
4. **The always-loaded context stays small.** That means `CLAUDE.md` template, `working-rules.md` and `model-routing.md`.
   - Anything situational goes into a path-scoped rule, a skill, or a supporting file. `kickoff/existing.md`, for example, loads only for existing repos.
   - User workflows use `disable-model-invocation: true`, so they cost nothing until invoked. Only `/handoff` is model-invocable.
5. **Verbose output stays out of the main context.**
   - `check.sh` filters and caps output (60 lines) and keeps full logs in `.claude/kit/logs/`.
   - Screenshots are viewed only by the `ui-checker` subagent.
   - Long third-party rule fetches (Vercel guidelines) run in a subagent.
6. **Skill `!` injection blocks must not fail.** A non-zero exit aborts the whole skill, so end them with `true` or a pipe to `head`.
7. **Third-party design tools are installed from upstream by `design-pack.sh`, never vendored.** It is a dry run by default and refuses to run with uncommitted `.claude/` changes.

## Decisions (and why)

| Decision | Why |
|---|---|
| Install script, not a Claude Code plugin | Needs to ship CLAUDE.md, settings, rules and docs, which plugins can't. Kit and project files must also be editable per repo. |
| `opusplan` default; delegate rather than switch models | The prompt cache is per model, so switching mid-session re-reads the whole context uncached. |
| `check.sh` as the single check entry point | One permission rule, deterministic filtering, and the same command for Go and TS. |
| `context.sh` gathers repo facts with shell | Git history, layout, docs and drift cost dozens of lines, not dozens of tool calls. |
| `architecture.md` carries `<!-- mapped-at: <sha> -->` | `/remap` and the session hook compute drift from it. Stale means 15 or more structural changes, or 60 or more commits. |
| Existing CLAUDE.md is slimmed, never replaced | Backup to `docs/CLAUDE.md.pre-kit` plus a section mapping table; no rule may disappear silently. |
| `Write` on tracked files is blocked | Full rewrites silently lose code. Edit only; new or untracked files are fine. |
| `shot.mjs` turns `isMobile` off | Mobile emulation widens the layout viewport to fit content, which hides horizontal overflow (found in testing). |
| `impeccable detect` in `ui-checker` | A deterministic scan for generic "AI-made" design patterns that costs no model tokens. Verified on a test page: 7 findings. |
| Design pack is opt-in | Each model-invocable skill adds its description to every session (core adds 3, all about 8). Taste skills overlap, so keep one main voice. |
| Bash only (Git Bash or WSL on Windows) | One implementation to test. `.gitattributes` forces LF so scripts survive Windows clones; `install.sh` appends the same rule to each project, because CRLF hooks fail open under Linux bash. |

## Verified vs not verified

**Verified:**
- All 120 self-tests pass on Windows Git Bash (2026-10-19). Under WSL (kali) the 116 that do not need Go or Node pass; the suite assumes `go` and `node` are installed.
- `shellcheck -S warning` was clean on every script for 1.2.0; not re-run for 1.2.1 (not installed on the Windows machine).
- Windows: an install committed under `core.autocrlf=true` and re-cloned keeps LF hooks, and the guard blocks under WSL (kali) bash.
- Headless runs of real Claude Code against an installed project: the guard blocked `rm` and the file survived; agents, rules and the SessionStart hook loaded; `test-runner` ran `check.sh`; `ui-checker` caught every planted defect.
- `context.sh` against a real repo (go-chi/chi): hotspots, drift of 150 commits, and a dangling path were all detected.
- A real `npx skills add` install of Vercel's and Emil Kowalski's skills; `claude mcp add ... --scope project` writes `.mcp.json`.

**Not verified:**
- **Impeccable's installer.** The build sandbox couldn't reach impeccable.style. Its `detect` CLI did work.
- **macOS's bash 3.2.** `install.sh` uses arrays and `${var//}`, which should be fine, but it hasn't been run. Git for Windows' MSYS bash (as opposed to Cygwin bash) is also untested.
- **`/kickoff` and `/remap` end to end with a human.** They are interactive, so only their scripts and structure are tested.
- **The forked skills' `model:` override** (`/decide` on the Plan agent with opus, `/remap` on sonnet). It behaves as the docs describe, but hasn't been observed in a live run.

## Open items (in priority order)

1. **Public-repo cleanup.**
   - Done: `examples/keepsake/` replaced by the fictional `examples/tally/`; MIT `LICENSE` added; README migration section generalised;
     clone URL in `HOW_TO_USE.md` set to `github.com/Horac3/claude-kit`.
   - The old Keepsake files are still in git history (commits up to `abc621e`). Before publishing, either push a fresh
     history (squash into a new root commit) or rewrite it with `git filter-repo --path examples/keepsake --invert-paths`.
2. ~~Label the opinionated defaults as configurable in the README.~~ Done: README "Opinionated defaults" table
   (nginx-proxy, `go test -race` in CI only, every `rm` blocked).
3. **Test on macOS** (bash 3.2). Windows Git Bash and WSL were tested in 1.2.1. If Windows-native users matter, consider `install.ps1`.
4. ~~Add CI.~~ Done in 1.2.1 (`.github/workflows/ci.yml`), but **not yet observed running**: check the first run on GitHub,
   especially the macOS bash 3.2 job, which is the first real 3.2 test (it covers open item 3).
5. **Verify Impeccable's installer** on a networked machine, and note any hook it adds to settings.
6. **Maybe:** a `--stack` value for other languages (Python, Kotlin) with their own rule files and `commands.env` defaults.

## How to work on the kit

```bash
tests/run.sh                                   # always, before and after a change
KIT_TEST_TS=1 tests/run.sh                     # when touching check.sh or TS defaults (needs network)
shellcheck -S warning -x install.sh tests/run.sh kit/.claude/hooks/*.sh kit/.claude/kit/*.sh stacks/ts/.claude/kit/*.sh
```

- Add a test with every behaviour change, the same TDD discipline the kit enforces. Guard changes need block and allow cases.
- Bump `VERSION` and add a `CHANGELOG.md` entry for every user-visible change; `--update` users rely on it.
- To try a change for real: install into a scratch repo (`./install.sh /tmp/x`), then run `claude` there.
  Headless checks are possible with `claude -p "..." --allowedTools ...`. Untrusted folders ignore project permissions, so pass tools explicitly.
- Before editing skills, agents or hooks, check field names against the current docs at https://code.claude.com/docs/en/skills.md, `/sub-agents.md` and `/hooks-guide.md`. Unknown frontmatter fields are silently ignored.
- Commits use Conventional Commits. This repo dogfoods its own rules: don't delete files, and run checks before every commit.
