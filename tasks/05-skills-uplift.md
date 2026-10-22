# Task 05: skills uplift (NestJS, backend rules, reviewer, TypeScript, packs)

> **How to run:** in the claude-kit repo, on its own branch, send:
> `Read DEVELOPMENT.md, then tasks/05-skills-uplift.md. Plan first; do parts A–C, then D–E.`

This comes from a review of external skill collections on 2026-10-22. Follow `DEVELOPMENT.md`'s invariants:
- the always-loaded context stays small
- situational guidance goes in path-scoped rules or files that load on demand
- user workflows use `disable-model-invocation`
- tests come first
- everything stays bash 3.2 compatible

**Licences:**
- **jeffallan/claude-skills, samber/cc-skills-golang and VoltAgent:** MIT, with licence files.
- **Kadajett/agent-nestjs-skills:** declares MIT in `SKILL.md`, but has no licence file.
- **Backend from First Principles:** no licence, so **ideas only**.

**Write everything in our own words. Never paste upstream text.** Credit every source in `CREDITS.md` under
"Ideas adapted from".

## A. NestJS rule (kit-native)
- **Install trigger:** add `stacks/ts/.claude/rules/kit/nestjs.md` when the project's `package.json` (root or any
  workspace package) depends on `@nestjs/core`. Record it in the manifest so `update` keeps it. The installer decides;
  test both cases.
- **Load trigger:** `paths:` covers `**/*.module.ts`, `**/*.controller.ts`, `**/*.service.ts`, `**/*.guard.ts`,
  `**/*.interceptor.ts`, `**/*.filter.ts`, `**/*.pipe.ts`, `**/*.processor.ts`, and `**/main.ts`.
- **Length:** about 30 lines. Deeper material goes in `kit/.claude/rules/kit/nestjs/` reference files that the rule
  points to, read only when needed. These are rules, not a skill, so they cost nothing until a Nest file is touched.
- **Content, adapted from Kadajett's impact-ranked rules** (structure and DI first), **with these deliberate reversals:**
  - **Errors:** services throw *domain* errors. One exception filter maps them to a single HTTP error format (problem
    details). Never throw `HttpException` from services or the domain. Kadajett says the opposite; we don't follow it,
    because it ties business logic to the web layer.
  - **Testing:** in-memory fakes of ports via `overrideProvider`, not mocked repositories. Vitest plus `unplugin-swc`;
    real infrastructure only in integration tests.
  - **Validation:** one approach per project, Zod pipes or class-validator with `whitelist` and `forbidNonWhitelisted`.
    Validate once, at the edge.
- **Keep from Kadajett:**
  - provider scopes (request-scoped providers make whole dependency chains per-request)
  - symbol or abstract-class injection tokens for ports
  - no service locator (`moduleRef.get` in business code)
  - circular dependencies (`forwardRef` is a smell)
  - feature modules that export only what others need
  - async errors never left as unhandled promises
  - guards on every route, deny by default
  - output serialisation with no internal fields
  - transactions owned by the use case
  - N+1 queries
  - config validated at startup
  - `enableShutdownHooks()`
  - health checks
  - BullMQ processors that are idempotent, with retries, backoff and the job ID as the dedupe key
- **Domain stays framework-free:** no `@Injectable()` in the domain. Adapters are Nest providers bound to domain ports.
  Cross-reference `hexagonal.md` instead of repeating it.
- **Verify:** install into a scratch NestJS project (`@nestjs/core` in `package.json`); the rule is present. Install
  into a TS project without Nest; it's absent.

## B. Backend rules (kit-native, any language)
Four path-scoped rules in `kit/.claude/rules/kit/`, each 20–30 lines of checklists in our own words.
Ideas come from Backend from First Principles, chapters 01, 02, 04, 07, 08, 10, 12–18 and 23.
- **`api.md`** (handlers, controllers, routes, `**/http/**`, `**/api/**`):
  - status codes; PUT vs PATCH; pagination
  - one error format (RFC 9457 problem details)
  - an idempotency key on POSTs that create money movements or orders
  - an object-level authorisation check in every handler (can this caller touch *this* ID?)
  - versioning; never leak internal IDs or stack traces
- **`jobs.md`** (`**/jobs/**`, `**/workers/**`, `**/queue*/**`, `**/*processor*`, `**/consumers/**`):
  - idempotent handlers; retries with backoff and jitter, and a cap
  - visibility timeout longer than the work
  - a dead-letter queue; poison-message handling
  - the outbox pattern for "write to the DB and publish"
  - ordering assumptions stated explicitly
- **`data.md`** (`**/migrations/**`, `**/repositories/**`, `**/*.sql`, `**/prisma/**`, `**/db/**`):
  - expand/contract (two-phase) migrations; no destructive migration in the same release as the code change
  - an index for every column queried in a WHERE or JOIN; avoid N+1 queries
  - short transactions with clear lock scope; retry on deadlock
  - pool sizing; money as integer minor units
- **`runtime.md`** (`**/main.go`, `**/cmd/**`, `**/main.ts`, `**/config/**`, `**/server.*`):
  - validate config at startup and fail fast
  - liveness vs readiness checks
  - graceful shutdown (stop accepting work, drain, close pools)
  - a timeout and deadline on every outbound call
  - structured logs with request IDs and no personal data
  - metrics for latency (p50, p95, p99) and errors
- **Security additions to the reviewer (part C),** not a new file: injection, password hashing (argon2id or bcrypt),
  rate limiting, CSRF for cookie sessions, broken object-level and function-level authorisation, secrets in logs,
  SSRF on outbound URLs.

## C. Reviewer upgrade (kit-native)
Adopt surgeon-reviewer's *method* (VoltAgent, MIT) inside the existing `kit/.claude/agents/reviewer.md`.
Don't add a second reviewer.
- Read the diff first and state its intent. Trace callers and callees only as far as needed to confirm or rule out
  a suspicion.
- Try to **disprove** every candidate finding before reporting it. Report only the ones that survive, each with the
  concrete input or sequence that triggers it.
- Tiers: **WILL BREAK** (wrong behaviour, data or money loss, reachable security hole) · **WILL COST** (N+1 queries,
  unbounded growth, missing index, timezone assumptions) · **WILL ROT** (drifting duplicates, hidden coupling,
  invariants held only by convention). No style findings.
- Verdict: `SHIP` · `SHIP WITH FIXES (<tiers>)` · `DO NOT SHIP`. Update `/review` and `/next`, which read the verdict,
  to match.
- Keep the existing checks (requirements, architecture rules, TDD discipline, privacy). Fold them into the tiers.

## D. TypeScript additions (kit-native)
Add to `stacks/ts/.claude/rules/kit/typescript.md`, staying under ~30 lines in total:
- `satisfies` for checked object literals
- branded types for IDs and money
- `as const` objects instead of `enum`
- no `as` cast without a one-line reason
- `import type` for type-only imports

Idea source: jeffallan typescript-pro (MIT).

## E. Skill and command additions (kit-native)
- **Spec mining in `/kickoff`:** in `kit/.claude/skills/kickoff/existing.md` step F, when the user picks work in an
  area with no requirements, draft them from the real code as `FR-AREA-NN` entries with given/when/then. Mark each
  draft "observed, unconfirmed" until the user confirms it. Idea source: jeffallan spec-miner (MIT).
- **Pre-mortem in `/decide`:** an optional mode, `/decide --premortem <decision>`, that adds "it's six months later
  and this failed: the three most likely reasons" and "the strongest argument against the recommendation" before
  the decision. Idea source: jeffallan the-fool (MIT).

## F. Packs through `claude-kit pack` (opt-in, upstream installs, licence notices)
Generalise `design-pack.sh` into one pack mechanism: `claude-kit pack <name> [--apply|--list]`. Keep `pack design`
working, and keep the existing notices, dry-run default and refuse-if-dirty behaviour.
- **`pack go`:** samber/cc-skills-golang (MIT, evaluated, maintained), installed with
  `npx skills add samber/cc-skills-golang --skill <list> -a claude-code -y --copy`.
  - Default (8): golang-error-handling, golang-concurrency, golang-context, golang-safety, golang-testing,
    golang-database, golang-security, golang-observability.
  - Library skills are offered only when `go.mod` requires the library: cobra → golang-spf13-cobra,
    viper → golang-spf13-viper, testify → golang-stretchr-testify, uber/fx → golang-uber-fx, wire → golang-google-wire,
    samber/{lo,mo,do,oops,ro,hot,slog-*} → the matching golang-samber-* skill.
  - Print the token cost: each auto-invoked skill adds its description to every session.
- **`pack payments`:** a kit-written, review-only `webhook-reviewer` agent (tools: Read, Grep, Glob, Bash; no edits),
  with its ideas adapted from VoltAgent webhook-engineer (MIT). It covers:
  - signature verification on the raw body, with a constant-time comparison
  - a timestamp tolerance against replays
  - acknowledging only after the event is durably stored
  - deduplication by event ID
  - out-of-order events handled against a state machine
  - retries with backoff and jitter, and a dead-letter queue
  - reconciliation against the provider's API
  - mobile-money and card-specific notes: callback plus reconciliation, never trusting the client
- The installer gets a test for each pack's dry-run plan and its `go.mod`-based library detection, using fake `npx`
  as in task 01's tests.

## Done when
- `tests/run.sh` green, including new cases for:
  - NestJS detection (root and workspace package)
  - each new rule's `paths:` globs, which must match real files in a fixture tree
  - pack plans and library detection
- `go test ./...` and shellcheck green.
- README "What gets installed" table, HOW_TO_USE §8 (packs) and §11, CREDITS.md and CHANGELOG updated. Version bumped (minor).
- Note anything not verified in DEVELOPMENT.md's "Verified vs not verified".
