# CLAUDE.md — Tally (fictional example)

Loaded every session; keep it under ~120 lines. Generic rules (safety, TDD, testing, commits, model
routing, Docker, hexagonal, TypeScript) live in `.claude/rules/kit/` and are not repeated here.
Invoice and payment rules are path-scoped in `.claude/rules/` and load when those files are touched.

Read on demand, only the parts the task needs:
- `docs/progress.md`: roadmap, current step, handoff notes. The session's source of truth.
- `docs/requirements.md`: functional requirements (FR-…). Grep by ID.
- `docs/decisions.md`: decision log; later entries override earlier ones.

## Product
Invoicing for freelancers: track time and expenses per client, turn them into invoices, send them as PDF
by email, and get paid by card or bank transfer. The core domain concept is `Invoice`; a draft becomes
immutable once issued.

## Stack
- pnpm monorepo. `apps/web`: React + Vite. `apps/api`: NestJS on Fastify. `apps/worker`: BullMQ jobs
  (PDF rendering, reminder emails, payment reconciliation).
- Packages: `domain` (pure TS), `contracts` (Zod), `database` (Prisma), `pdf`, `config`.
- PostgreSQL + Prisma, Redis + BullMQ, S3-compatible storage for PDFs. Vitest everywhere.

## Commands
Checks: `.claude/kit/check.sh all|typecheck|lint|test|test-one "<name>"` via the `test-runner` subagent.
Configured in `.claude/kit/commands.env` (`pnpm -r --if-present run …`).

## Architecture rules (non-negotiable)
1. Ports and adapters for storage, payments, email, and PDF rendering.
2. An issued invoice is immutable. Corrections are credit notes, never edits.
3. Money is integer minor units plus an ISO currency code, end to end.
4. PDF generation and emails are asynchronous via the queue and are idempotent and retryable.

## Commit scopes
`domain`, `api`, `worker`, `web`, `contracts`, `database`, `pdf`, `infra`.

## Workflow
- Start every conversation with `/next`. One roadmap step per conversation; `/clear` between steps.
- Plan in plan mode (Opus via `opusplan`), build on Sonnet, delegate checks to `test-runner`, review with `/review`.
- Hand off with `/handoff` before context reaches ~60%.

## Compact instructions
When compacting, keep: the current step and its FR IDs, test status, files changed, decisions made,
and the next action. Drop: full test logs and file contents already committed.
