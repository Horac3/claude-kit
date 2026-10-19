# Changelog

## 1.2.1 — 2026-10-19
- `install.sh` appends `eol=lf` rules for `.claude/**/*.sh` and `.claude/kit/commands.env` to the project's `.gitattributes`
  (append-only). Hooks checked out with CRLF crash under Linux/WSL bash and exit 0, which silently disabled the guards.
  Existing projects get the rules on `--update`. A checkout that already has CRLF scripts keeps them until they are checked
  out again: commit `.gitattributes`, delete `.claude/hooks/*.sh` and `.claude/kit/*.sh`, then `git checkout -- .claude`.
- Self-tests run on Windows Git Bash: the no-jq fallback tests use wrapper scripts instead of symlinks.
- `design-pack.sh`: no longer aborts on macOS bash 3.2 when a pack has nothing to run (e.g. `shadcn` without
  `components.json`); empty arrays under `set -u` are expanded safely.
- CI for the kit: shellcheck, and `tests/run.sh` on Ubuntu (with the pnpm + vitest test) and on macOS's bash 3.2.
  `KIT_TEST_TS=1` without pnpm now fails instead of silently skipping.

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
