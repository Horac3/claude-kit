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

---

## The loop

```
/kickoff        once per project: map the code, fill CLAUDE.md, verify checks, draft the roadmap
  /clear
/next           plan the next step (Opus, plan mode) → approve → build test-first (Sonnet)
  /tdd          Red → Green → Refactor, one behaviour per cycle   (used inside /next, or standalone)
  /fix          bug → reproducing test → root cause → minimal fix
  /review       reviewer subagent on Opus, in its own context
  /commit       Conventional Commits, grouped; the permission prompt is your confirmation
  /handoff      writes Current step + Handoff notes into docs/progress.md
  /clear        free; the next /next picks up exactly where you left off
/decide <q>     an irreversible or cross-cutting decision, thought through on Opus in a fork → ADR
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
.claude/kit/manifest               kit      — hashes for safe updates
.claude/hooks/guard-bash.sh        kit      — blocks rm, git clean/reset --hard/restore, force push, find -delete, .env reads…
.claude/hooks/guard-files.sh       kit      — blocks .env, lockfiles, .git/, AGENTS.md, the guard config, Write over tracked files
.claude/hooks/session-context.sh   kit
.claude/skills/{kickoff,next,tdd,fix,handoff,review,decide,commit}/SKILL.md   kit
.claude/agents/{test-runner,reviewer,researcher,debugger}.md                  kit
.claude/rules/kit/working-rules.md   always     safety, working loop, test rules
.claude/rules/kit/model-routing.md   always     the table above + token rules
.claude/rules/kit/hexagonal.md       on demand  **/domain/**, **/ports/**, **/adapters/**, **/core/**
.claude/rules/kit/docker.md          on demand  Dockerfiles, compose files (nginx-proxy pattern)
.claude/rules/kit/go.md              on demand  **/*.go            (go and both stacks)
.claude/rules/kit/typescript.md      on demand  **/*.ts(x), package.json, tsconfig   (ts and both stacks)
```

The installer also adds `.claude/settings.local.json`, `.claude/kit/logs/`, `CLAUDE.local.md` and `*.kit-new` to `.gitignore`.
It only appends to that file.

**Kit files** belong to the kit. **Project files** are yours from the moment they are created.
Your own rules go in `.claude/rules/<topic>.md`, outside `kit/`, and the kit never touches them.
Give them `paths:` frontmatter so they load only when relevant (see `examples/keepsake/.claude/rules/`).

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

## Requirements

- bash and git. macOS, Linux, or Windows through Git Bash or WSL.
- Optional: `jq`. The hooks fall back to python3, then node, then a regex parser.
- Go projects: `golangci-lint` is used if installed; otherwise lint falls back to a `gofmt -l` check.
  `go test -race` needs cgo and a C compiler, so the kit leaves it to CI or Docker.

## Migrating an existing project (e.g. Keepsake)

1. `~/claude-kit/install.sh ~/code/keepsake`. Your `CLAUDE.md`, `.claude/settings.json` and `docs/progress.md` are kept,
   and the kit's versions arrive as `*.kit-new` for reference.
2. Your old `.claude/skills/{next,tdd}` and `agents/{test-runner,reviewer}` have the same names as the kit's, so the kit's
   versions arrive as `.kit-new` and you choose which to keep. The kit's versions are generalised and add `check.sh`, `/handoff`, and injection.
3. Slim `CLAUDE.md`. `examples/keepsake/` shows the result: generic sections removed (they now live in `rules/kit/`),
   retention and payments moved to path-scoped rules. The always-loaded context shrinks by about 20% even with the added rules.
4. Merge hooks and the status line from `.claude/settings.json.kit-new` into your `settings.json`.
5. Set `.claude/kit/commands.env` to `pnpm -r --if-present run typecheck|lint|test`.

## Developing the kit

```
tests/run.sh                # installer, update flow, guards (40+ cases), session hook, check runner, status line
KIT_TEST_TS=1 tests/run.sh  # also builds a real pnpm + vitest project (needs network)
```

Bump `VERSION` and add a line to `CHANGELOG.md` with each change, so projects can see what `--update` brings.
