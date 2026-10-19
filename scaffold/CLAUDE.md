# CLAUDE.md — TODO(kickoff): project name

Loaded every session, so every line costs tokens on every turn. Keep this under ~120 lines.
Generic rules live in `.claude/rules/kit/` (loaded automatically; Go/TS/Docker/domain rules load
only when matching files are touched). Do not repeat them here.

Read on demand, only the parts the task needs:
- `docs/progress.md`: roadmap, current step, handoff notes. The session's source of truth.
- `docs/requirements.md`: functional requirements with IDs. Grep by ID; do not read it whole.
- `docs/decisions.md`: decision log. Check before contradicting an earlier choice.
- `docs/architecture.md`: codebase map (written by /kickoff). Read before exploring.

## Product
TODO(kickoff): two or three sentences — what it does, for whom, the core domain concept, launch market.

## Stack
TODO(kickoff): languages, frameworks, datastores, queues, infra. One line each. Name the layout
(e.g. `cmd/`, `internal/`, or `apps/*`, `packages/*`).

## Commands
All checks go through `.claude/kit/check.sh` (configured in `.claude/kit/commands.env`), ideally via the
`test-runner` subagent: `all` · `typecheck` · `lint` · `test` · `test-one "<pattern>"`.
TODO(kickoff): dev server, migrations, codegen, or other commands Claude needs (only if any).

## Architecture rules (non-negotiable)
TODO(kickoff): numbered, one line each. The project-specific rules only, e.g. which packages may import
what, where validation happens, how payments are confirmed, what must be idempotent.

## Commit scopes
TODO(kickoff): the allowed `<scope>` values for Conventional Commits, e.g. `domain`, `api`, `web`, `infra`.

## Project-specific working rules
TODO(kickoff): anything Claude must or must never do in this repo that `.claude/rules/kit/` does not cover.
Delete this section if there is nothing.

## Workflow
- Start every conversation with `/next`. One roadmap step per conversation; `/clear` between steps.
- Plan in plan mode (Opus via `opusplan`), build on Sonnet, delegate checks to `test-runner`, review with `/review`.
- Hand off with `/handoff` before context reaches ~60%.

## Compact instructions
When compacting, keep: the current step and its requirement IDs, test status (pass/fail and failing
test names), files changed, decisions made, and the exact next action. Drop: full test logs, file
contents already written to disk, exploration that did not lead anywhere.
