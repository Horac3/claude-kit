# How to use claude-kit

This guide takes you from nothing to a working Claude Code project in about 15 minutes, then shows the
day-to-day loop. For the design (why it works this way) see the [README](README.md).

**Contents**

1. [Before you start](#1-before-you-start)
2. [Get the kit](#2-get-the-kit)
3. [Install it into a project](#3-install-it-into-a-project)
4. [Open the project in Claude Code and trust it](#4-open-the-project-in-claude-code-and-trust-it)
5. [Commit the setup](#5-commit-the-setup)
6. [Run `/kickoff` once](#6-run-kickoff-once)
7. [The daily loop: one step per conversation](#7-the-daily-loop-one-step-per-conversation)
8. [Other commands](#8-other-commands)
9. [Read the status line](#9-read-the-status-line)
10. [When a guard blocks something](#10-when-a-guard-blocks-something)
11. [Customise it](#11-customise-it)
12. [Update the kit](#12-update-the-kit)
13. [Troubleshooting](#13-troubleshooting)
14. [Uninstall](#14-uninstall)
15. [FAQ](#15-faq)

---

## 1. Before you start

You need:

| Requirement | Check | Notes |
|---|---|---|
| Claude Code | `claude --version` | Any recent version. |
| bash | `bash --version` | macOS and Linux have it. On Windows, use **Git Bash** or **WSL**. |
| git | `git --version` | The project should be a git repository. |
| Go and/or Node | `go version` / `node --version` | Whatever your project already uses. Node 18+ also lets you install with `npx`; Go lets you install with `go install`. |
| jq *(optional)* | `jq --version` | The hooks use jq if it's there, then fall back to python3, node, or a built-in parser. |
| golangci-lint *(optional, Go)* | `golangci-lint --version` | Used for lint if installed; otherwise lint is a `gofmt -l` check. |

The kit works with **Go**, **TypeScript/JavaScript** (pnpm, npm, yarn, or bun), or **both in one repo**.

## 2. Get the kit

Pick whichever route suits your machine. They install exactly the same files; CI checks this.

| Route | Command | You need |
|---|---|---|
| **npm** (nothing to keep installed) | `npx @horac3/claude-kit <command>` | Node 18+ |
| **Go** | `go install github.com/horac3/claude-kit/cmd/claude-kit@latest` | Go, with `$(go env GOPATH)/bin` on your PATH |
| **Binary** | Download your platform's archive from [Releases](https://github.com/horac3/claude-kit/releases), check it against `checksums.txt`, and put `claude-kit` on your PATH | Nothing extra |
| **Git clone** | `git clone https://github.com/horac3/claude-kit.git ~/claude-kit` | Nothing extra |

All routes need bash to run (on Windows, Git Bash). The rest of this guide shows the `claude-kit` command.
With npm, put `npx` in front (`npx @horac3/claude-kit init`). With a git clone, use `~/claude-kit/install.sh`,
and `--update` instead of `update`.

> **Pin a version** for a team or CI: `npx @horac3/claude-kit@1.5.0 init`, or `go install …/cmd/claude-kit@v1.5.0`.

> **Windows and git clones:** clone with LF line endings so the scripts run in Git Bash. The repo's
> `.gitattributes` handles this. If you cloned before it existed, run `git config core.autocrlf false` and clone again.
> The `claude-kit` binary finds Git Bash by itself; set `CLAUDE_KIT_BASH` to point at a different `bash.exe`.

## 3. Install it into a project

**Preview first.** `--dry-run` shows what would happen and writes nothing:

```bash
claude-kit init --dry-run ~/code/my-project
```

**Then install:**

```bash
claude-kit init ~/code/my-project       # or, inside the project: claude-kit init
```

The installer works out the stack from `go.mod` / `package.json` and the package manager from your lockfile:

```
claude-kit 1.0.0 → /home/you/code/my-project  (mode: install, stack: go)
  add      .claude/agents/debugger.md
  add      .claude/hooks/guard-bash.sh
  …
  add      CLAUDE.md
  add      docs/progress.md
  add      .claude/settings.json
  add      .claude/kit/commands.env
  ignore   .claude/kit/logs/  (.gitignore)
  eol=lf   .claude/**/*.sh  (.gitattributes)
done: 29 added, 0 updated, 0 unchanged, 0 project files kept, 0 to merge
```

Options:

| Flag | Use it when |
|---|---|
| `--stack go\|ts\|both` | Auto-detection is wrong, or the repo is empty (no `go.mod` or `package.json` yet). |
| `--frontend` | A non-TypeScript project renders UI (e.g. a Go service with HTML templates) and you want `/ui`, `ui-checker` and the frontend rule. `--update` keeps it. |
| `--dry-run` | You want to see the plan without writing anything. |
| `claude-kit update` | The kit is already installed and you want a newer version (see [step 12](#12-update-the-kit)). With a git clone: `install.sh --update`. |

**Already have a `CLAUDE.md` or `.claude/settings.json`?** They are **never overwritten**. The kit's
version is written next to yours as `CLAUDE.md.kit-new` / `settings.json.kit-new` so you can merge
what you want. The installer never deletes anything.

## 4. Open the project in Claude Code and trust it

```bash
cd ~/code/my-project
claude
```

The first time, Claude Code asks whether you **trust this folder**. Accept it. Until you do, the
project's hooks, permissions, and status line are **switched off**. That includes the safety guards.

Check that everything loaded:

- **Status line:** you should see something like `Opus · ctx 3% · $0.00 · main* · Step 1: …` at the bottom.
- **Hooks:** run `/hooks` and look for `guard-bash.sh` and `guard-files.sh` under PreToolUse, and `session-context.sh` under SessionStart.
- **Commands:** type `/` and look for `/kickoff`, `/next`, `/tdd`, `/fix`, `/review`, `/decide`, `/commit`, `/handoff`.

## 5. Commit the setup

The kit is meant to be committed, so everyone on the project (and every machine you use) gets the same setup:

```bash
git add CLAUDE.md docs/ .claude/ .gitignore .gitattributes
git commit -m "chore: add claude-kit"
```

Do **not** commit `.claude/settings.local.json`, `CLAUDE.local.md`, or `.claude/kit/logs/`. The
installer already added them to `.gitignore`.

## 6. Run `/kickoff` once

Start a **fresh** Claude Code conversation and make `/kickoff` the first message. You can add a
one-line description of the product:

```
/kickoff A booking API for small clinics: patients book, clinics confirm, SMS reminders.
```

`/kickoff` runs on Opus. It checks whether the repo is **new** (fewer than about 10 source files) or **existing**, and adapts.
Expect a few questions along the way.

**New project:**

1. **Asks you a short round of questions:** product, users, constraints, architecture rules, commit scopes.
2. **Fills in `CLAUDE.md`**, replacing every `TODO(kickoff)` and keeping the file under ~120 lines.
3. **Drafts requirements** with you in `docs/requirements.md`.
4. **Checks your commands** and **drafts the roadmap** (below).

**Existing project.** It gathers context before asking you anything:

1. **Reads what's already known.** That means git history (recent commits, the most-changed files, active branches, TODO clusters, open issues if `gh` is set up), your README and CONTRIBUTING, ADR titles, and rule files for other AI tools (`AGENTS.md`, `.cursorrules`, Copilot instructions, …).
   A script gathers most of this, so it costs very little.
2. **Maps the code** with parallel helper agents into `docs/architecture.md`, and flags anywhere the code contradicts the docs.
3. **Asks only about gaps and contradictions,** and what you want to work on next.
4. **Handles your existing `CLAUDE.md` carefully.** If you already had one, it backs it up to `docs/CLAUDE.md.pre-kit`.
   Then it shows you a table of where each section goes (kept, moved to a rule file that loads only for matching paths, moved to a doc, or dropped because a kit rule already says it). It changes nothing until you approve.
5. **Builds the roadmap from work in flight** and writes requirements only for what you choose to do next.
   If a step touches a heavily-changed file with few tests, it suggests pinning current behaviour with tests first.

**Both then:**
- **Checks your commands** by running `.claude/kit/check.sh all`, and fixes `.claude/kit/commands.env` until typecheck, lint, and test either pass or fail for real reasons.
- **Drafts a roadmap** in `docs/progress.md`. Each step is one conversation's worth of work (1–5 behaviours).
  If you have requirements, put them in `docs/requirements.md` first (the template is there) and
  `/kickoff` groups them into steps. Otherwise it drafts requirements with you.

Review the roadmap when it's shown, approve it, then commit:

```bash
git add -A && git commit -m "docs: kickoff — CLAUDE.md, roadmap, architecture map"
```

Kickoff ends with: `Kickoff complete. Run /clear, then /next to start step 1: <title>.`

## 7. The daily loop: one step per conversation

This is the core habit. **One roadmap step = one conversation.** Progress is stored in
`docs/progress.md`, not in chat history, so clearing the conversation loses nothing.

```
/clear  →  /next  →  approve plan  →  build (test-first)  →  /review  →  /commit  →  /handoff  →  /clear
```

### 7.1 Start: `/next`

```
/next
```

(or `/next 4` to pick a specific step)

Claude reads the current step and handoff notes (already pre-loaded, no extra tool calls), checks
`git status`, and **enters plan mode on Opus**. You get a short plan:

- the step and its requirement IDs
- the behaviours it will test, in order
- the files it will touch
- the commits it will make
- any open questions

**Read the plan. Push back now.** It's the cheapest moment to change direction. When it looks right, approve it.

### 7.2 Build

After you approve, the session switches to **Sonnet** (that's what `opusplan` does) and builds
test-first. For each behaviour:

1. **Red:** writes one failing test and shows you it fails for the right reason.
2. **Green:** writes the minimum code to pass it.
3. **Refactor:** tidies up with all tests green.

You'll see Claude hand work to subagents. That's deliberate, and it keeps your conversation small and cheap:

| You'll see | What it's doing |
|---|---|
| `test-runner` | Running checks on Haiku and returning a 5-line verdict instead of the full log. |
| `Explore` | Searching the codebase on Haiku. |
| `debugger` | Root-causing a failure that wasn't obvious, without filling your context with the investigation. |
| `researcher` | Looking up library docs for the exact version in your lockfile. |

### 7.3 Review: `/review`

When the behaviours are done, Claude runs `/review` (you can also run it yourself at any time). A
separate Opus reviewer checks the diff against `CLAUDE.md`, the rules, and the requirements, and ends with
`VERDICT: ship` or `VERDICT: fix first (n blocking)`. Blocking findings get fixed, test-first.

### 7.4 Commit: `/commit`

`/commit` groups the changes into Conventional Commits (`feat(scope): …`, `test(scope): …`, …) and
runs `git commit` for each. **Claude Code's permission prompt is your confirmation.** Say no to any
commit you don't want. Nothing is pushed.

### 7.5 Hand off: `/handoff`

`/handoff` updates `docs/progress.md`: it ticks the step `[x]` (or `[~]` if unfinished), rewrites
**Current step** and **Handoff notes** (what's done, the exact next action, traps to watch for), and adds a log line.

Claude finishes with one line telling you what to do next:

```
Step 3 complete. Run /clear, then /next to continue with step 4: Delivery window purge.
```

### 7.6 Clear and repeat

```
/clear
/next
```

`/clear` is free. The next conversation starts small, on the right model, with the handoff already in context.

### If the conversation gets long mid-step

When the status line turns **red (70% context)**, don't push on. Say *"hand off"* or run `/handoff`.
It writes a `[~]` handoff with the precise next action. Then `/clear` and `/next` resume exactly there.
Prefer this to `/compact`, which spends tokens re-reading the whole conversation to summarise it.

## 8. Other commands

Use these on their own, outside the `/next` loop:

| Command | Example | What happens |
|---|---|---|
| `/tdd <behaviour or IDs>` | `/tdd FR-AUTH-03` | One or more Red → Green → Refactor cycles, then a table of behaviours and proposed commits. |
| `/fix <bug>` | `/fix booking confirm returns 500 when clinic has no SMS number` | Reproduce with a failing test → root-cause (with `debugger` if needed) → minimal fix → full suite. |
| `/review [focus]` | `/review focus on authz` | Opus review of uncommitted changes, in a separate context. |
| `/decide <question>` | `/decide Postgres advisory locks vs a Redis lock for the purge job` | Opus weighs the options in a separate context and returns a decision record. Approve it to append to `docs/decisions.md`. |
| `/commit [note]` | `/commit` | Grouped Conventional Commits; you confirm each. |
| `/handoff` | `/handoff` | Write state to `docs/progress.md` now. |
| `/remap [area\|full]` | `/remap` | Refresh `docs/architecture.md` from what changed in git since it was last mapped. Run it when the session start says the map is stale, or after a big restructure. |
| `/ui <screen>` *(TS projects)* | `/ui booking form with date picker and confirmation` | A short design brief, then a test-first build, then a screenshot check at desktop and mobile widths by the `ui-checker` subagent. See [§8.1](#81-frontend-work-ui). |

### 8.1 Frontend work: `/ui`

In TypeScript projects the kit adds frontend rules (accessibility, the four data states, design tokens, mobile-first),
a `/ui` command, and a `ui-checker` subagent that actually **looks** at the page. Other stacks get the same layer
with `install.sh --frontend`. A Go project then needs a small `package.json` (`npm init -y`) to hold Playwright.

One-time setup in the project (the subagent needs a browser):

```bash
pnpm add -D -E playwright @axe-core/playwright   # or npm i -D -E / yarn add -D -E / bun add -d --exact
pnpm exec playwright install chromium
```

Then start your dev server and run, for example:

```
/ui pricing page with three plans and a monthly/yearly toggle
```

Claude writes a 5–8 line brief (purpose, layout, states, components to reuse) and builds it test-first.
Then it asks `ui-checker` to screenshot the page. The subagent runs `node .claude/kit/shot.mjs <url>`, looks at the images, and reports:

```
VERDICT: fix first (2)
- [blocking] horizontal overflow at 390px — pricing table — let the table scroll inside its container
- [blocking] "Choose plan" contrast too low on the highlighted card — use the on-primary token
```

Blocking items are fixed and re-checked, for at most 3 rounds. The screenshots stay in `.claude/kit/logs/shots/`
for you to look at. They never enter your main conversation, so visual review doesn't inflate your context.
You can run the screenshot script yourself too: `node .claude/kit/shot.mjs http://localhost:5173 --dark --full`.

`ui-checker` also runs `npx -y impeccable detect`. It's a free, deterministic scan for generic "AI-made" design: purple
gradients, gradient text, overused fonts like Inter, buzzword copy, and low contrast. It needs nothing installed beyond `npx`.

### 8.2 Add the design pack (optional)

For stronger design taste, install curated third-party design skills into the project. Run this in your terminal,
not through Claude, because the installers may add hooks (Impeccable writes them to `.claude/settings.local.json`):

```bash
git add -A && git commit -m "wip"                # the script refuses to run with uncommitted .claude/ changes
.claude/kit/design-pack.sh                       # see the plan for the core pack
.claude/kit/design-pack.sh core --apply          # Impeccable + Vercel web-design-guidelines
.claude/kit/design-pack.sh motion --apply        # optional: Emil Kowalski's animation skills (subset)
# same thing through the binary, from the project folder: claude-kit pack design core --apply
```

Then, inside Claude Code, add Anthropic's skill: `/plugin install frontend-design@claude-plugins-official`.

Review what was added (`git status`), read the new `.claude/skills/*` and `.claude/agents/*`, and commit them together with
`skills-lock.json`, `THIRD_PARTY_NOTICES.md`, and the per-skill `LICENSE` and `NOTICE` files. The upstream installers copy
skills without their licences, so the script fetches each one and lists them in `THIRD_PARTY_NOTICES.md`; a public repo needs
those notices. The script only edits the marked block in that file, so your own entries outside it are safe.
**Never commit Anthropic's `frontend-design` plugin files:** the plugin is proprietary, and each person installs it themselves.
The README's [Design pack](README.md#design-pack-optional-ts-projects) section explains what each tool does and why some are left out.

**Give the project a `DESIGN.md`.** Once the pack is installed, ask for `/impeccable document`, or copy a reference from
[awesome-design-md](https://github.com/VoltAgent/awesome-design-md) and adapt it. From then on `/ui`, the frontend rule and
`ui-checker` all follow it, so the visual language stays the same from session to session without being re-explained.

Useful built-in Claude Code commands that fit this workflow: `/context` (what is using your context), `/usage`
(token use and cost), `/rewind` (undo to a checkpoint), `/hooks` (inspect hooks).

## 9. Read the status line

```
Sonnet · ctx 34% · $0.42 · main* · Step 4: Delivery window purge
```

| Part | Meaning |
|---|---|
| `Sonnet` | The model answering right now (Opus while planning, Sonnet while building). |
| `ctx 34%` | How full the context window is. **Green** < 50%. **Yellow** 50–69%: finish the current cycle. **Red** ≥ 70%: `/handoff` now. |
| `$0.42` | Estimated session cost (API pricing; on a subscription it's an indicator only). |
| `main*` | Git branch; `*` means uncommitted changes. |
| `Step 4: …` | The current step from `docs/progress.md`. |

## 10. When a guard blocks something

The kit blocks commands that delete or discard work (`rm`, `git clean`, `git reset --hard`,
`git restore`, force pushes, `find -delete`, `docker volume prune`, …), anything touching `.env`
files, hand edits to lockfiles, and edits to its own hooks and settings. Claude sees a message like:

```
Blocked by claude-kit: deleting files is never done by Claude (matched: 'rm ')
```

Claude is told not to retry a variant. It explains what it wanted to do and why.
**If you agree, run the command yourself:** type `!` in front of it in Claude Code, or use a terminal:

```
! rm -rf dist
```

The guards prevent accidents. They are not a security sandbox.

## 11. Customise it

Everything is plain files. Here's where each kind of change belongs:

| You want to… | Edit | Notes |
|---|---|---|
| Change how typecheck / lint / test run | `.claude/kit/commands.env` | Yours to edit. `$1` in `CHECK_TEST_ONE` is the test name. Leave a value empty to skip that check. |
| Add project rules | `CLAUDE.md` | Keep it short: it loads every turn. |
| Add rules for part of the codebase | `.claude/rules/<topic>.md` with `paths:` frontmatter | Loads only when Claude touches matching files. Don't put your files in `rules/kit/`. |
| Personal notes not for the team | `CLAUDE.local.md` | Gitignored. |
| Personal permissions | `.claude/settings.local.json` | Gitignored; merges with the shared settings. |
| Allow or deny more commands for the team | `.claude/settings.json` | Yours. Claude itself is blocked from editing it; you edit it. |
| Change a kit skill, agent, or rule | Edit it in place | Fine, but on update you'll get the new version as `.kit-new` to merge by hand. |

Example path-scoped rule, `.claude/rules/payments.md`:

```markdown
---
paths:
  - "**/payments/**"
  - "**/*payment*"
---

# Payments
- Money is integer minor units + ISO currency code. Never floats.
- Payment state is confirmed by provider callback plus reconciliation, never by the frontend.
```

More examples: [`examples/tally/`](examples/tally/) (a fictional project). Glob a rule's folders as well as file names:
`**/*invoice*` does not match files inside an `invoices/` folder, so add `**/invoices/**`.

**Integration tests that need services.** If some packages need Postgres, Redis or S3 to test, don't let
`CHECK_TEST` silently skip them. Put a helper in a project-owned folder, for example `.claude/project/test.sh`.
It always runs the unit tests and runs the integration packages only when their services answer. Otherwise it fails
with a line saying what was **not** tested, so a partial run is never green:

```bash
#!/usr/bin/env bash
# .claude/project/test.sh: unit tests always; integration tests only when their services answer.
set -u
SERVICES="postgres:localhost:5432 redis:localhost:6379 s3:localhost:9000"   # name:host:port
INTEGRATION_PACKAGES="@acme/db @acme/storage"                              # pnpm package names

filters=""; for p in $INTEGRATION_PACKAGES; do filters="$filters --filter !$p"; done
# shellcheck disable=SC2086
pnpm -r $filters --if-present run test "$@" || exit 1

down=""
for s in $SERVICES; do
  name="${s%%:*}" rest="${s#*:}"
  (exec 3<>"/dev/tcp/${rest%%:*}/${rest#*:}") 2>/dev/null || down="$down $name"
done
if [ -n "$down" ]; then
  echo "Error: integration packages NOT tested ($INTEGRATION_PACKAGES): not reachable:$down." >&2
  echo "Start them (e.g. docker compose up -d) and re-run." >&2
  exit 1
fi
filters=""; for p in $INTEGRATION_PACKAGES; do filters="$filters --filter $p"; done
# shellcheck disable=SC2086
pnpm -r $filters --if-present run test "$@"
```

Then point the kit at it in `commands.env`: `CHECK_TEST='bash .claude/project/test.sh'`. The kit never touches `.claude/project/`.

## 12. Update the kit

Get the newer kit, then preview and apply:

```bash
# npm: npx always fetches the version you name
npx @horac3/claude-kit@latest update --dry-run ~/code/my-project
npx @horac3/claude-kit@latest update ~/code/my-project

# Go / binary: install the newer binary first
go install github.com/horac3/claude-kit/cmd/claude-kit@latest
claude-kit update --dry-run ~/code/my-project
claude-kit update ~/code/my-project

# git clone
git -C ~/claude-kit pull
~/claude-kit/install.sh --update ~/code/my-project
```

You don't need to remember which route you used: the end of every install prints the matching update
command, and `.claude/kit/manifest` records it as `via=npm|go|git`. Check what you have with `claude-kit version`.

What happens to each file:

| File | Result |
|---|---|
| Kit file you haven't touched | Updated in place. |
| Kit file you edited | **Kept.** The new version is written as `<file>.kit-new`; merge it by hand. |
| Project file (`CLAUDE.md`, `docs/*`, `settings.json`, `commands.env`) | **Never overwritten.** If the template changed, you get `<file>.kit-new` to compare. |
| File the new kit no longer ships | Reported as `obsolete`. Delete it yourself if you don't need it. |

After merging, delete the `*.kit-new` files (they're gitignored, so they can't be committed by accident).
Then review with `git diff` and commit: `chore: update claude-kit to 1.x.y`. See [CHANGELOG.md](CHANGELOG.md) for what changed.

## 13. Troubleshooting

| Symptom | Fix |
|---|---|
| No status line, hooks not firing, permission prompts for everything | The folder isn't trusted. Run `claude` interactively in the project and accept the trust dialog. |
| `/hooks` doesn't list the guards | `.claude/settings.json` existed before install. Merge the `hooks` and `statusLine` blocks from `settings.json.kit-new`. |
| `check.sh: missing .claude/kit/commands.env` | Re-run the installer. It only adds files that are missing. |
| `check.sh` fails with "command not found" | The command in `commands.env` doesn't match your repo (wrong package manager, no `typecheck` script). Fix it there, or run `/kickoff` step 4 again by asking Claude to verify the check commands. |
| Tests pass in your terminal but `check.sh` says FAIL | Read `.claude/kit/logs/<target>.log`. `check.sh` runs with `CI=1` and no colour, which some tools treat differently. |
| `shot.mjs: the project has no playwright package` | Run the one-time setup in [§8.1](#81-frontend-work-ui). |
| `design-pack.sh` says a download failed | The installer needs internet access to its upstream (GitHub, npm, impeccable.style). Retry, or run that one command by hand. The other packs are unaffected. |
| `design-pack.sh` says "could not fetch the licence" and exits non-zero | The skills were installed, but their upstream `LICENSE` couldn't be downloaded (offline, or the repo moved its licence). `THIRD_PARTY_NOTICES.md` marks them "licence not fetched — add manually". Copy the LICENSE from the upstream repo into that skill folder (or next to the agent) and update the entry before committing. |
| `shot.mjs: could not start Chromium` | Run `pnpm exec playwright install chromium`, or point `CHROMIUM_PATH` at an installed Chrome or Chromium. |
| Session start says the architecture map is stale | Run `/remap`. It updates only the parts that changed. |
| `bad interpreter` or `$'\r': command not found` (Windows) | The scripts have CRLF line endings. Re-clone the kit with LF endings (see [step 2](#2-get-the-kit)) and re-run the installer. |
| A legitimate command gets blocked | Run it yourself with `!`. If the pattern is too broad for your project, open an issue with the command. |
| `/next` says the tree is dirty | It stops before touching anything. Commit, stash, or tell it how to proceed. |
| Costs feel high | Check `/context`. Usual causes are a long conversation (hand off sooner), switching models mid-conversation, or reading whole large files. |

## 14. Uninstall

The installer never deletes, so uninstalling is manual. These are the kit's files:

```bash
# Review this list first: git rm keeps everything in history, so you can always get it back.
git rm -r .claude/skills/{kickoff,next,tdd,fix,handoff,review,decide,commit,remap} \
          .claude/agents/{test-runner,reviewer,researcher,debugger}.md \
          .claude/skills/ui .claude/agents/ui-checker.md \
          .claude/hooks .claude/kit .claude/rules/kit
```

Then remove the `hooks` and `statusLine` blocks from `.claude/settings.json`. Keep or delete `CLAUDE.md`
and `docs/` as you like: they're your project's documents now.

## 15. FAQ

**Do I have to use test-driven development?**
The `/next` and `/tdd` flows assume it. To relax it, edit the "Tests" section of
`.claude/rules/kit/working-rules.md` and `/tdd`. They become modified kit files, so updates will arrive as `.kit-new`.

**Does it work in a monorepo?**
Yes. pnpm workspaces are detected and the commands use `pnpm -r --if-present run …`. Put
package-specific rules in path-scoped rule files (`paths: ["apps/api/**"]`).

**My project is Python, Rust, or Kotlin.**
Install with the closest `--stack` (or `--stack go` for a neutral setup), then set your real commands
in `.claude/kit/commands.env` and add a path-scoped rule file for the language. Everything else
(skills, agents, hooks, the loop) is language-independent.

**Why not just use one long conversation?**
Every message re-sends the whole conversation. A three-hour session pays for its entire history on every
turn, and compaction loses detail. One step per conversation, with the state in a file, is cheaper and
more reliable.

**Why does it block `Write` on existing files?**
`Write` replaces a whole file. On a tracked file, a truncated or stale rewrite silently loses code. `Edit`
changes only what it means to change. New and untracked files can still be written.

**Can I use a different main model?**
Yes: set `"model"` in `.claude/settings.json` (e.g. `"sonnet"` for cost, `"opus"` for hard projects). Keep the
rule of switching models only right after `/clear`.
