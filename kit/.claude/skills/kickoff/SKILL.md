---
name: kickoff
description: One-time project setup after installing claude-kit — map the codebase, fill in CLAUDE.md, verify the check commands, and draft the roadmap in docs/progress.md.
argument-hint: "[short product description]"
disable-model-invocation: true
model: opus
effort: high
---

Set this project up for the claude-kit workflow. Run this as the first message of a fresh session.
Product description from the user (may be empty): $ARGUMENTS

## Snapshot
```!
echo "--- top level"; ls -A 2>/dev/null | head -40
echo "--- manifests"; ls go.mod go.work package.json pnpm-workspace.yaml pnpm-lock.yaml package-lock.json yarn.lock bun.lock* Makefile Taskfile.yml docker-compose*.yml compose*.yml 2>/dev/null
echo "--- tracked files"; git ls-files 2>/dev/null | wc -l
echo "--- commands.env"; grep -E '^CHECK_' .claude/kit/commands.env 2>/dev/null
echo "--- CLAUDE.md placeholders"; grep -n 'TODO(kickoff)' CLAUDE.md 2>/dev/null | head -20
true
```

## 1. Map existing code (skip for an empty repo)
If there is real code, launch up to 3 `Explore` subagents in parallel (entry points and wiring;
domain and data model; tests, build and deploy). Ask each for ≤150 words with file paths.
Write the result to `docs/architecture.md` (≤120 lines): purpose, layout tree (2 levels), how a request
flows, where the domain lives, how tests run, how it deploys, known debt. Future sessions read this
instead of re-exploring.

## 2. Interview (one round)
Ask the user, in one AskUserQuestion batch where possible, only what the code and docs cannot tell you:
product in two sentences, launch market and constraints, non-negotiable architecture rules, commit
scopes, anything Claude must never do in this repo. Skip questions already answered by `$ARGUMENTS` or files.

## 3. Fill CLAUDE.md
Replace every `TODO(kickoff)` in `CLAUDE.md` using Edit. Hard limit: CLAUDE.md stays under ~120 lines.
Anything long or used only sometimes goes in `docs/` (read on demand) or a path-scoped rule in
`.claude/rules/<topic>.md` with `paths:` frontmatter (loads only when matching files are touched).
Do not repeat what `.claude/rules/kit/` already says.

## 4. Verify the check commands
Run `.claude/kit/check.sh all` via `test-runner`. If a command is wrong for this repo (package manager,
monorepo layout, missing linter), fix `.claude/kit/commands.env` and re-run until each target is
PASS, FAIL for real reasons, or deliberately empty (SKIP).

## 5. Draft the roadmap
If `docs/requirements.md` has requirements, group them into roadmap steps in `docs/progress.md`.
Each step: one conversation's work (1–5 behaviours), ordered by dependency, riskiest domain logic early,
format `- [ ] N. <title> — <requirement IDs>`. Otherwise draft requirements with the user first, using the
template in `docs/requirements.md`. Set "Current step" to step 1. Show the roadmap and wait for approval.

## 6. Finish
List files created or changed, then say:
`Kickoff complete. Run /clear, then /next to start step 1: <title>.`
