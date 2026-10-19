# Changelog

## 1.3.0 — 2026-10-19
Fixes found by installing 1.2.0 into a real pnpm monorepo (13 packages, lint at the root only).
- **Workspaces no longer report a false green.** For each target, `commands.env` uses the root script when the root
  `package.json` has one (`pnpm run lint`; `pnpm -r` skips the root). It falls back to a recursive run only for
  scripts that live in packages, and stays empty (SKIP) when no package has the script. Applies to pnpm, npm, yarn and bun.
  Only new installs get this. To pick it up, compare `commands.env` with `commands.env.kit-new` after `--update`.
- Workspace `CHECK_TEST_ONE` passes `-t "$1"` to each package's test script instead of calling a root `vitest`
  that usually isn't installed there.
- `check.sh` reports `SKIP <target> (nothing ran)` instead of PASS when a command exits 0 but ran nothing
  ("No projects matched", "None of the selected packages has a … script", or a script runner that printed only its scope).
- `--frontend`: adds the frontend layer (`frontend.md`, `/ui`, `ui-checker`, `shot.mjs`, `design-pack.sh`) to any stack,
  e.g. a Go service rendering HTML templates. Recorded in the manifest, so `--update` keeps it. `frontend.md` now also
  matches `*.tmpl`, `*.gohtml` and `*.templ`.
- `/decide` follows the entry style `docs/decisions.md` already uses. Existing-project `/kickoff` records that style in a
  project rule and offers to archive oversized handoff notes verbatim to `docs/progress-archive.md`.
- Docs: integration-test split pattern (`.claude/project/test.sh`) in HOW_TO_USE §11; glob a rule's folders, not only
  file names (example rules fixed).

## 1.2.0 — 2026-10-19
- `design-pack.sh` (ts/both stacks): opt-in installer for curated third-party design skills from their upstreams:
  core (Impeccable, Vercel web-design-guidelines, Anthropic frontend-design plugin), motion (Emil Kowalski subset),
  taste (taste-skill), shadcn (MCP), devtools (Chrome DevTools MCP). Dry run by default; refuses to run with uncommitted
  `.claude/` changes; versions pinned in `skills-lock.json`.
- `ui-checker` runs `npx impeccable detect` (deterministic generic-design scan) at desktop and mobile widths.
- `DESIGN.md` is the visual source of truth for the frontend rule, `/ui`, and `ui-checker`; `/ui` offers to create one.
- `/ui` runs Vercel's web-design-guidelines review in a subagent when installed.

## 1.1.0 — 2026-10-19
- `/kickoff` existing-project mode (`skills/kickoff/existing.md`): reads git history, other AI tools' rule files,
  docs and ADRs before exploring; briefs parallel Explore agents to verify, not rediscover; slims a pre-existing
  CLAUDE.md with a backup and a section-by-section mapping table; links ADRs; builds the roadmap from work in flight;
  proposes characterisation tests before touching thin-tested hotspots.
- `context.sh`: deterministic layout / existing-docs / history / drift summaries.
- `/remap`: incremental refresh of `docs/architecture.md` from git drift since its `mapped-at` commit, in a forked context.
- Session hook warns when the architecture map is stale; `/handoff` flags structural changes for `/remap`.
- Frontend layer for ts/both stacks: `frontend.md` path-scoped rule, `/ui` skill, `ui-checker` subagent, and
  `shot.mjs` (Playwright screenshots at desktop and mobile widths, overflow, tap-target, console, request, and axe checks).

## 1.0.0 — 2026-10-19
- Initial kit: 8 skills (kickoff, next, tdd, fix, handoff, review, decide, commit), 4 subagents
  (test-runner, reviewer, researcher, debugger), guard and session hooks, filtered check runner,
  status line, always-on and path-scoped rules for Go, TypeScript, Docker and hexagonal domains.
- Installer with stack and package-manager detection and hash-based safe updates.
