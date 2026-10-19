# Changelog

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
