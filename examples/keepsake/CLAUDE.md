# CLAUDE.md — Keepsake Books (working name)

Loaded every session; keep it under ~120 lines. Generic rules (safety, TDD, testing, commits, model
routing, Docker, hexagonal, TypeScript) live in `.claude/rules/kit/` and are not repeated here.
Retention and payment rules are path-scoped in `.claude/rules/` and load when those files are touched.

Read on demand, only the parts the task needs:
- `docs/progress.md`: roadmap, current step, handoff notes. The session's source of truth.
- `docs/requirements.md`: functional requirements (FR-…). Grep by ID.
- `docs/design-direction.md`: layout library, themes, formats (A4/A5), page tiers, text limits.
- `docs/decisions.md`: decision log; later entries override `docs/original-design.md`.

## Product
Users pick a template, upload photos, write their stories, customise the design, and get a print-ready
PDF (later: a printed book). Use cases: couples, baby yearbook, graduation, family. The core domain
concept is `Publication` (not "magazine"). Brand undecided, so the package scope is `@app/*`.
Deliberately premium. Launch market: Malawi first, built to open internationally later.

## Stack
- pnpm monorepo. `apps/web`: React + Vite; the page is positioned DOM, dragging uses pointer handlers
  (no Fabric.js, decision 17c). `apps/api`: NestJS on Fastify. `apps/renderer`: Nest standalone + BullMQ worker.
- Packages: `domain` (pure TS), `contracts` (Zod), `database` (Prisma + PrismaService), `fonts`, `rendering`,
  `template-engine`, `config`.
- PostgreSQL + Prisma, Redis + BullMQ, self-hosted S3-compatible storage (Malawi). Vitest everywhere.
- PDF engine: PDFKit (step 12 spike), behind a port.

## Commands
Checks: `.claude/kit/check.sh all|typecheck|lint|test|test-one "<name>"` via the `test-runner` subagent.
Configured in `.claude/kit/commands.env` (`pnpm -r --if-present run …`).

## Architecture rules (non-negotiable)
1. Ports and adapters for storage, payments, email, and the renderer.
2. Templates are immutable; a publication is an independent copy.
3. The publication document (JSONB, validated with Zod inside repositories) is the source of truth.
   The editor only represents it.
4. Pages use physical units (mm) with bleed, safe margin, and gutter. Template layout is `single` or `spread`.
   Saddle stitch = multiple of 4 pages, perfect bind = multiple of 2. Outputs: reader PDF and print PDF
   (imposed, bleed, crop marks).
5. PDF generation is asynchronous via the queue and runs on immutable versions.
6. Large files go browser → storage via signed URLs (resumable/multipart), never through the API.
7. Every expensive operation is idempotent, observable, and retryable.
8. Fonts: self-hosted OFL fonts from `google/fonts`, pinned by commit, referenced by font ID, hashed in a
   manifest. Fail loudly on a missing font or glyph.

## Compliance
Malawi Data Protection Act 2024 first. `region` on users and projects, versioned consent records,
processor register, rights requests (30-day SLA), breach log (72-hour rule).
No face detection or AI features without separate, explicit opt-in.

## Commit scopes
`domain`, `api`, `renderer`, `web`, `contracts`, `database`, `fonts`, `rendering`, `template-engine`, `infra`.

## Workflow
- Start every conversation with `/next`. One roadmap step per conversation; `/clear` between steps.
- Plan in plan mode (Opus via `opusplan`), build on Sonnet, delegate checks to `test-runner`, review with `/review`.
- Hand off with `/handoff` before context reaches ~60%.

## Compact instructions
When compacting, keep: the current step and its FR IDs, test status, files changed, decisions made,
and the next action. Drop: full test logs and file contents already committed.
