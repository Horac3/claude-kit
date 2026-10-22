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
tests/run.sh                 self-tests (181); KIT_TEST_TS=1 adds a real pnpm + vitest project (fails if pnpm is missing)
go.mod, kitfs.go             Go module github.com/horac3/claude-kit; kitfs.go embeds install.sh, VERSION, kit/, stacks/, scaffold/
cmd/claude-kit/              the CLI: init, update, pack design, version. Unpacks the embedded kit to a temp dir and runs
                             install.sh / design-pack.sh with bash (Git Bash on Windows). main_test.go proves `init`
                             installs exactly what install.sh installs.
npm/claude-kit/              npm launcher package (bin/claude-kit.js runs the platform binary)
npm/build.mjs                builds the launcher + 6 platform packages from GoReleaser's dist/artifacts.json
.goreleaser.yaml             6 binaries (linux/darwin/windows × amd64/arm64), archives, checksums
.github/workflows/ci.yml     shellcheck; tests on Ubuntu (+ TS) and macOS bash 3.2; Go vet/test on Ubuntu, macOS, Windows
.github/workflows/release.yml  on tag vX.Y.Z = VERSION: tests, GoReleaser release, npm publish with provenance, smoke test
```

`install.sh` generates `.claude/settings.json` and `.claude/kit/commands.env` per stack and package manager, in `gen_settings` and `gen_commands`.

## Invariants: do not break these

0. **One installer, every route.** `install.sh` is the only install logic. The Go binary and the npm launcher run
   it (embedded); they must never reimplement or diverge from it. `TestInitMatchesInstallSh` enforces this. Phase 2
   (`tasks/04`) may port it to Go, but only by keeping that equivalence test green against the bash version first.
   Never `go:embed` without the `all:` prefix: the `.claude` folders would silently drop out.

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
   - With `--apply` it writes each copied skill's or agent's upstream `LICENSE` (and `NOTICE`) and never overwrites an existing one.
   - In `THIRD_PARTY_NOTICES.md` it owns only the block between the `claude-kit:third-party` markers. Re-runs keep one entry per item, updated in place, and leave everything outside the block byte for byte.
   - It stays bash 3.2-safe (CI runs it on macOS): no associative arrays, and possibly-empty arrays are expanded as `${a[@]+"${a[@]}"}`.

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
| Licence notices written at install time | Upstream installers copy skills and agents without their LICENSE files, so a public project would redistribute MIT/Apache files without the required notices. The SPDX id comes from matching the licence text, not the GitHub API, which is rate-limited when unauthenticated. |
| Design pack is opt-in | Each model-invocable skill adds its description to every session (core adds 3, all about 8). Taste skills overlap, so keep one main voice. |
| Bash only (Git Bash or WSL on Windows) | One implementation to test. `.gitattributes` forces LF so scripts survive Windows clones; `install.sh` appends the same rule to each project, because CRLF hooks fail open under Linux bash. |

## Verified vs not verified

**Verified:**
- All 148 self-tests pass on Windows Git Bash (151 with `KIT_TEST_TS=1`, 2026-10-19). Under WSL (kali) the 116 that do not need Go or Node pass; the suite assumes `go` and `node` are installed.
- `shellcheck -S warning` (0.11.0) is clean on every script for 1.3.0.
- Real `design-pack.sh core motion --apply` (network, 2026-10-19): 6 skills and 4 agents installed, each with a correct licence entry.
- Windows: an install committed under `core.autocrlf=true` and re-cloned keeps LF hooks, and the guard blocks under WSL (kali) bash.
- 1.4.0: all 167 self-tests pass on Windows Git Bash, and shellcheck is clean.
- **Verified on a real monorepo (1.4.0):** installing 1.2.0 into keeper (pnpm, 13 packages, lint only at the root,
  integration tests needing Postgres, Redis and S3) exposed the false-green lint, the root `vitest` in `CHECK_TEST_ONE`,
  and PASS when nothing ran (task 02). The fixes were checked against real pnpm on a workspace. `pnpm -r --if-present run lint` with
  no package script prints only `Scope: N of M workspace projects` and exits 0, so `check.sh` ignores that line.
  pnpm forwards `-t <pattern>` to each package's script.
- Headless runs of real Claude Code against an installed project: the guard blocked `rm` and the file survived; agents, rules and the SessionStart hook loaded; `test-runner` ran `check.sh`; `ui-checker` caught every planted defect.
- `context.sh` against a real repo (go-chi/chi): hotspots, drift of 150 commits, and a dangling path were all detected.
- A real `npx skills add` install of Vercel's and Emil Kowalski's skills; `claude mcp add ... --scope project` writes `.mcp.json`.

**Not verified:**
- **Impeccable's installer.** The build sandbox couldn't reach impeccable.style. Its `detect` CLI did work.
- **macOS's bash 3.2.** `install.sh` uses arrays and `${var//}`, which should be fine, but it hasn't been run. Git for Windows' MSYS bash (as opposed to Cygwin bash) is also untested.
- **`/kickoff` and `/remap` end to end with a human.** They are interactive, so only their scripts and structure are tested.
- **The forked skills' `model:` override** (`/decide` on the Plan agent with opus, `/remap` on sonnet). It behaves as the docs describe, but hasn't been observed in a live run.

## Open items (in priority order)

0. **Done: monorepo fixes** (`tasks/02-monorepo-fixes.md`, 1.4.0):
   - [x] 1 root-first workspace scripts, empty when no package has the script
   - [x] 2 workspace `CHECK_TEST_ONE` via package scripts
   - [x] 3 `check.sh` SKIP when nothing ran
   - [x] 4 integration-test split pattern (HOW_TO_USE §11)
   - [x] 5 `/decide` follows the existing decision-log style
   - [x] 6 handoff archive in existing-project `/kickoff`
   - [x] 7 folder globs in example rules, plus a README note
   - [x] 8 `--frontend`
   - [ ] CI green on Ubuntu and macOS bash 3.2: confirm on the first push of 1.4.0

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
5. ~~Verify Impeccable's installer.~~ Verified on 2026-10-19 (`design-pack.sh core motion --apply`). It copies `.claude/skills/impeccable/`
   plus 4 agents (`.claude/agents/impeccable-*.md`), and writes SessionStart, PostToolUse (Edit|Write) and Stop hooks to
   **`.claude/settings.local.json`**, which is gitignored. Its hooks are therefore per machine: teammates who clone the repo don't get them.
6. ~~Licence notices, CREDITS.md and the kit's LICENSE (`tasks/01-licensing-and-credits.md`).~~ Done in 1.3.0. Still open:
   the second video creator's credit (`TODO(credit)` in `CREDITS.md`).
7. **Publish the package (1.5.0).** Everything is built and tested except the real publish:
   - Everything publishes under the npm user scope `@never9to5ive` (the maintainer's npm account): the launcher
     `@never9to5ive/claude-kit` and six `@never9to5ive/claude-kit-<os>-<arch>` packages. Unscoped `claude-kit` is not
     usable: npm rejects names that differ from an existing package (`claudekit`) only by punctuation.
   - First release: a granular access token (read and write, bypass 2FA, short expiry) as the `NPM_TOKEN` repo secret.
     Then move to trusted publishing on all seven packages and drop the token: npm removes direct publishing from
     2FA-bypass tokens around January 2027.
   - Tag `v1.5.0` from `main` after merging. `go install …@v1.5.0` works from the tag.
   - Not yet verified: a real `npm publish` with provenance, the macOS and Windows binaries running on real machines,
     and the Windows `go test` job. The release workflow ends with an npx smoke test.
8. **Package phase 2: port `install.sh` to Go** (`tasks/04-go-installer.md`). Removes the bash requirement for installing.
9. **Skills uplift** (`tasks/05-skills-uplift.md`): NestJS rule, backend rules, reviewer upgrade, TypeScript additions,
   `/kickoff` spec mining, `/decide` pre-mortem, and the `pack go` / `pack payments` packs.
10. **Maybe:** a `--stack` value for other languages (Python, Kotlin) with their own rule files and `commands.env` defaults.

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
