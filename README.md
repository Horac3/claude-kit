# claude-kit

A drop-in Claude Code setup for Go and TypeScript projects. It focuses on four things:

- **Token economy.** A small always-loaded context, rules that load only when relevant files are touched, and test output filtered before Claude sees it.
- **Model routing.** Opus plans, Sonnet builds, and Haiku runs checks. Escalation happens through subagents, never by switching the main model mid-conversation.
- **Clean handoffs.** One roadmap step per conversation. State lives in `docs/progress.md`, so `/clear` costs nothing and nothing is lost.
- **Safety by hooks, not hope.** Deleting or discarding work is blocked deterministically, even in compound commands.

```
git clone <your-remote>/claude-kit ~/claude-kit
~/claude-kit/install.sh ~/code/my-project        # auto-detects go / ts / both
cd ~/code/my-project && claude                    # then: /kickoff
```

**New here? Follow the step-by-step guide: [HOW_TO_USE.md](HOW_TO_USE.md).**
Working on the kit itself? Start with [DEVELOPMENT.md](DEVELOPMENT.md).

---

## The loop

```
/kickoff        once per project: gather context, map the code, fill or slim CLAUDE.md, verify checks, draft the roadmap
  /clear
/next           plan the next step (Opus, plan mode) → approve → build test-first (Sonnet)
  /tdd          Red → Green → Refactor, one behaviour per cycle   (used inside /next, or standalone)
  /fix          bug → reproducing test → root cause → minimal fix
  /review       reviewer subagent on Opus, in its own context
  /commit       Conventional Commits, grouped; the permission prompt is your confirmation
  /handoff      writes Current step + Handoff notes into docs/progress.md
  /clear        free; the next /next picks up exactly where you left off
/decide <q>     an irreversible or cross-cutting decision, thought through on Opus in a fork → ADR
/remap          refresh docs/architecture.md from git changes since it was last mapped
/ui <screen>    (TS projects) design brief → test-first build → screenshot check by a subagent
```

The status line shows `model · ctx % · cost · branch · current step`. Context turns **yellow at 50%**
(finish the cycle) and **red at 70%** (`/handoff` now, then `/clear` + `/next`).

## Model routing

The main session runs `opusplan`: Opus while in plan mode, Sonnet once you approve. Everything else is routed by delegation:

| Work | Who | Model · effort |
|---|---|---|
| Plan a step, weigh architecture | main session, plan mode | Opus |
| Implement, TDD cycles | main session, `/tdd` | Sonnet · medium |
| Typecheck, lint, test | `test-runner` subagent | Haiku · low |
| "Where is X / how does Y flow" | built-in `Explore` subagent | Haiku |
| Library / API docs | `researcher` subagent | Sonnet · low |
| Non-obvious failure | `debugger` subagent | Sonnet · high |
| End-of-step review | `reviewer` via `/review` | Opus · high |
| Big decisions | `/decide` (forked) | Opus · high |
| Refresh the codebase map | `/remap` (forked) | Sonnet · medium |
| Look at UI screenshots | `ui-checker` subagent | Sonnet · medium |
| One-time project setup | `/kickoff` (first message of a fresh session) | Opus · high |

**Why never switch the main model mid-conversation:** the prompt cache is per model. If you switch
from Sonnet to Opus with 80k tokens of context, Opus re-reads all 80k uncached. A subagent starts
with a clean, small context instead. Switch only right after `/clear`, when the context is empty.
Skills that pin a model (`/kickoff`, `/tdd`) are designed to run at the start of a session or on the model already active.

## Where the tokens go (and how the kit cuts them)

| Mechanism | What it saves |
|---|---|
| `check.sh` filters output | A failing Go suite with 200 log lines reaches Claude as ~9 lines: verdict, failing test, assertion. Repeated lines are collapsed and output is capped at 60 lines. The full log stays in `.claude/kit/logs/`. |
| `test-runner` on Haiku | Even the filtered output stays in the subagent. The main context gets a 5-line report. |
| Path-scoped rules | Go, TypeScript, Docker, and domain rules load only when Claude touches matching files. A Go session never pays for TypeScript rules. |
| User-only skills | `/next`, `/tdd`, `/review` and the rest use `disable-model-invocation`, so they cost zero tokens until you type them. Only `/handoff` is in Claude's listing, because Claude needs to be able to hand off on its own. |
| `!` injection in skills | `/next`, `/commit`, and `/review` pre-load `git status`, the log, and the current step before Claude starts, which saves several tool round-trips. |
| SessionStart hook | About 5 lines (branch, current step, next action) instead of Claude reading `progress.md` to orient itself. After compaction it re-injects the same lines. |
| `/handoff` + `/clear` | `/compact` reads the whole conversation to summarise it, while `/clear` is free. Handoff notes in a file are cheaper and more reliable than a summary. |
| `docs/architecture.md` | `/kickoff` maps the codebase once, so later sessions read about 120 lines instead of re-exploring. |
| `context.sh` | The shell gathers layout, existing docs and AI-tool rules, ADR titles, git hotspots, active branches, TODO density and drift. Claude reads a summary of a few dozen lines instead of spending tool calls finding them. |
| `/remap` on drift | It updates only the parts of the map whose directories changed since the `mapped-at` commit, in a forked context. The session hook says when the map is stale (15 or more structural changes, or 60 or more commits). |
| `ui-checker` subagent | Screenshots are images and cost tokens. The subagent looks at them and returns about 20 lines of findings, so the main conversation never holds an image. |

## What gets installed

```
CLAUDE.md                          project  — lean template, filled by /kickoff (<120 lines)
docs/progress.md                   project  — roadmap · Current step · Handoff notes · Log
docs/decisions.md                  project  — append-only ADR log
docs/requirements.md               project  — FR-AREA-NN template
.claude/settings.json              project  — opusplan, permissions, hooks, status line (per stack)
.claude/kit/commands.env           project  — your typecheck/lint/test commands (per stack, per package manager)
.claude/kit/check.sh               kit      — filtered check runner
.claude/kit/statusline.sh          kit
.claude/kit/context.sh             kit      — layout, existing docs/rules, git history, drift (used by /kickoff, /remap, the session hook)
.claude/kit/manifest               kit      — hashes for safe updates
.claude/hooks/guard-bash.sh        kit      — blocks rm, git clean/reset --hard/restore, force push, find -delete, .env reads…
.claude/hooks/guard-files.sh       kit      — blocks .env, lockfiles, .git/, AGENTS.md, the guard config, Write over tracked files
.claude/hooks/session-context.sh   kit
.claude/skills/{kickoff,next,tdd,fix,handoff,review,decide,commit,remap}/SKILL.md   kit
.claude/skills/kickoff/existing.md                                                  kit  — loaded only for existing codebases
.claude/agents/{test-runner,reviewer,researcher,debugger}.md                        kit
.claude/skills/ui/SKILL.md · agents/ui-checker.md · kit/shot.mjs · kit/design-pack.sh   kit  — ts and both stacks
.claude/rules/kit/working-rules.md   always     safety, working loop, test rules
.claude/rules/kit/model-routing.md   always     the table above + token rules
.claude/rules/kit/hexagonal.md       on demand  **/domain/**, **/ports/**, **/adapters/**, **/core/**
.claude/rules/kit/docker.md          on demand  Dockerfiles, compose files (nginx-proxy pattern; see Opinionated defaults)
.claude/rules/kit/go.md              on demand  **/*.go            (go and both stacks)
.claude/rules/kit/typescript.md      on demand  **/*.ts(x), package.json, tsconfig   (ts and both stacks)
.claude/rules/kit/frontend.md        on demand  **/*.{tsx,jsx,vue,svelte,css,scss,html}  (ts and both stacks)
```

The installer also adds `.claude/settings.local.json`, `.claude/kit/logs/`, `CLAUDE.local.md` and `*.kit-new` to `.gitignore`,
and `eol=lf` rules for `.claude/**/*.sh` and `commands.env` to `.gitattributes`. Without the second, a Windows checkout with
`core.autocrlf` gives the hooks CRLF line endings, and Linux/WSL bash then fails on them and exits 0, which silently disables the guards.
It only appends to those files.

**Kit files** belong to the kit. **Project files** are yours from the moment they are created.
Your own rules go in `.claude/rules/<topic>.md`, outside `kit/`, and the kit never touches them.
Give them `paths:` frontmatter so they load only when relevant (see `examples/tally/.claude/rules/`).

## Design pack (optional, TS projects)

The kit's frontend layer handles discipline: tokens, the four data states, accessibility, and a screenshot check by a subagent.
For **taste**, it relies on the best third-party design skills rather than reinventing them. `design-pack.sh` installs a
curated set into the project from their upstream sources. Nothing is vendored, and versions are pinned in `skills-lock.json`.

```bash
.claude/kit/design-pack.sh                    # show the plan (installs nothing)
.claude/kit/design-pack.sh core --apply       # install
.claude/kit/design-pack.sh --list             # all packs: core, motion, taste, shadcn, devtools
```

| Tool | Pack | Why it's in (or not) |
|---|---|---|
| [Impeccable](https://github.com/pbakaus/impeccable) | core | Teaches the agent design vocabulary and anti-patterns: `/impeccable shape · critique · audit · polish · document` (writes `DESIGN.md`). Its `impeccable detect` CLI is a deterministic scanner for generic "AI-made" design (purple gradients, gradient text, overused fonts, buzzwords, contrast). The kit's `ui-checker` runs it even without the pack. |
| [Vercel web-design-guidelines](https://github.com/vercel-labs/agent-skills) | core | Reviews UI code against 100+ interface rules. `/ui` runs it in a subagent, because it fetches a long rule list. |
| [Anthropic frontend-design](https://github.com/anthropics/claude-code) | core | Official skill for a bold, intentional aesthetic direction. A Claude Code plugin: `/plugin install frontend-design@claude-plugins-official`. |
| [Emil Kowalski skills](https://github.com/emilkowalski/skills) | motion | Animation craft, animation review, Apple's interface and motion principles for the web, and worst-case-data UI testing. A 4-skill subset of 15. |
| [taste-skill](https://github.com/Leonxlnx/taste-skill) | taste | Premium-reference layout, type and spacing taste. Overlaps with Impeccable and frontend-design, so it's opt-in. Keep one main "taste" voice. |
| [shadcn MCP](https://ui.shadcn.com/docs/mcp) | shadcn | Browse and install registry components, rather than having Claude hand-roll them. Only added when `components.json` exists. |
| [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp) | devtools | An interactive browser with console, network and performance traces, for debugging. For routine visual checks, the kit's `shot.mjs` is cheaper. |
| [DESIGN.md](https://github.com/VoltAgent/awesome-design-md) | convention | Not an install. A `DESIGN.md` at the repo root is treated as the source of truth by the frontend rule, `/ui` and `ui-checker`. Generate one with `/impeccable document`, or start from a reference in awesome-design-md. |
| [Playwright](https://playwright.dev) | built in | The kit's `shot.mjs` uses it for screenshots, overflow, tap-target and axe checks. |
| Image-to-code ([screenshot-to-code](https://github.com/abi/screenshot-to-code)) | skipped | A standalone web app, not an agent skill. Claude already reads screenshots and mockups directly. |

**Token note.** Every skill Claude can invoke automatically adds its description to every session. The core pack adds 3,
and the full set about 8. That's why the packs are opt-in and the motion pack installs a subset. Third-party skills run with
full agent permissions, so read them before committing. Run the script yourself (or with `!`): installers such as Impeccable
add hooks to `.claude/settings.json`, which the kit's guards deliberately stop Claude from editing.

## Updating

```
cd ~/claude-kit && git pull
~/claude-kit/install.sh --update ~/code/my-project            # add --dry-run to preview
```

- A kit file you **haven't modified** is updated in place.
- A kit file you **have modified** is left alone; the new version is written next to it as `<file>.kit-new`.
- A project file is **never overwritten**. If the kit's template for it changed, you get `<file>.kit-new` to compare.
- A file the kit **no longer ships** is reported as obsolete. Nothing is ever deleted, so you remove leftovers yourself.

## Safety layers

1. **Deny list in `settings.json`.** Covers simple commands such as `rm …` and `git clean …`.
2. **`guard-bash.sh` (PreToolUse).** Catches what the deny list misses: `cd x && rm -rf y`, `xargs rm`, `git -C sub clean`, `bash -c "rm …"`, and push refspecs like `+main` or `:branch`.
   It strips quoted strings and heredoc bodies first, so `git commit -m "clean up rm usage"` still goes through. A PreToolUse deny holds even in bypass-permissions mode.
3. **`guard-files.sh`.** Protects secrets, lockfiles, `.git/`, `AGENTS.md`, the hooks and settings themselves, and stops Write from rewriting any tracked file (Edit only).
4. **Rules.** `working-rules.md` tells Claude to stop and ask instead of retrying a variant.

The guards are there to prevent accidents; they are not a sandbox against a determined adversary. When you genuinely need a
destructive command, run it yourself: type `!` before it in Claude Code, or use a terminal.

## Opinionated defaults (all configurable)

A few defaults come from the author's own setup. Change them if they don't fit your project:

| Default | Where | How to change |
|---|---|---|
| Production containers join an external `nginx-proxy` network with `VIRTUAL_HOST` / `LETSENCRYPT_*` and `expose`, never `ports` | `.claude/rules/kit/docker.md` | Edit or replace that bullet with your own deployment pattern (Traefik, Kubernetes, a PaaS). |
| `go test -race` (and other cgo/native builds) run only in CI or Docker, because the author's machine has no C compiler | `.claude/rules/kit/go.md`, `.claude/rules/kit/docker.md` | If you have a C compiler, delete those lines and add `-race` to `CHECK_TEST` in `.claude/kit/commands.env`. |
| Every `rm` (and `rmdir`, `unlink`, `shred`) is blocked, even on build output | `.claude/hooks/guard-bash.sh` (first `check` line) and the `Bash(rm *)` entries in `.claude/settings.json` `permissions.deny` | Edit both yourself; Claude is blocked from editing hooks and settings. Or keep the block and run deletes with `!`. |

Editing a kit file is safe: `--update` sees that it is modified, leaves your version in place and writes the new kit version
next to it as `<file>.kit-new`.

## Requirements

- bash and git. macOS, Linux, or Windows through Git Bash or WSL.
- Optional: `jq`. The hooks fall back to python3, then node, then a regex parser.
- Go projects: `golangci-lint` is used if installed; otherwise lint falls back to a `gofmt -l` check.
  `go test -race` needs cgo and a C compiler, so the kit leaves it to CI or Docker.

## Existing projects

`/kickoff` notices when a repo already has code and switches to an existing-project procedure
(`skills/kickoff/existing.md`, loaded only in that case):

1. **Reads what is already known, cheapest first.** It starts with git history (recent commits, hotspots, active branches, TODO clusters, open issues through `gh`).
   Then it reads instruction files written for other AI tools (`AGENTS.md`, `.cursorrules`, `.cursor/rules`, Copilot instructions, `GEMINI.md`), the README and CONTRIBUTING, and ADR titles.
2. **Maps the code with parallel Haiku `Explore` agents.** They are briefed with the layout, hotspots and what the docs already claim, so they verify and fill gaps rather than start cold, and they report any place where the code contradicts the docs.
   The result is `docs/architecture.md`, stamped with a `mapped-at` commit.
3. **Asks only about gaps and contradictions,** plus what you want to work on next.
4. **Slims a pre-existing `CLAUDE.md` instead of replacing it.** It first backs it up to `docs/CLAUDE.md.pre-kit`.
   Then it shows a table of every original section and where it went: dropped as a duplicate of a kit rule, moved to a path-scoped rule, moved to a reference doc, or kept. No rule disappears without a row in that table.
5. **Links existing ADRs** from `docs/decisions.md` instead of copying them.
6. **Builds the roadmap from work already in flight** (branches, commit themes, TODOs, issues) and writes requirements only for the work you pick.
   Before changing a hotspot that has thin tests, it proposes a characterisation-test step first.

Afterwards, `/remap` keeps the map current from `git diff` since the `mapped-at` commit. It also reports paths named in
`CLAUDE.md` or the map that no longer exist.

### Migrating from your own Claude Code setup

1. `~/claude-kit/install.sh ~/code/my-project`. Your `CLAUDE.md`, `.claude/settings.json` and `docs/progress.md` are kept,
   and the kit's versions arrive as `*.kit-new` for reference.
2. Your old `.claude/skills/{next,tdd}` and `agents/{test-runner,reviewer}` have the same names as the kit's, so the kit's
   versions arrive as `.kit-new` and you choose which to keep. The kit's versions are generalised and add `check.sh`, `/handoff`, and injection.
3. Run `/kickoff` to slim `CLAUDE.md` (step 4 above). `examples/tally/` (a fictional project) shows the result: generic sections removed (they now live in `rules/kit/`),
   invoice and payment rules moved to path-scoped rules, so they load only when those files are touched.
4. Merge hooks and the status line from `.claude/settings.json.kit-new` into your `settings.json`.
5. Set `.claude/kit/commands.env` to `pnpm -r --if-present run typecheck|lint|test`.

## Developing the kit

```
tests/run.sh                # installer, update flow, guards (40+ cases), session hook, check runner, status line,
                            # context gatherer, drift and staleness detection
KIT_TEST_TS=1 tests/run.sh  # also builds a real pnpm + vitest project (needs network)
```

Bump `VERSION` and add a line to `CHANGELOG.md` with each change, so projects can see what `--update` brings.
