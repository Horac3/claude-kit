# Changelog

## 1.5.0 — 2026-10-22
- **Install with npm or Go.** A `claude-kit` binary carries the whole kit and the tested installer inside it:
  `npx claude-kit init` / `update` / `pack design` / `version`, or `go install github.com/horac3/claude-kit/cmd/claude-kit@latest`,
  or a release binary. All routes install byte-identical files (checked in CI by a Go test against `install.sh`, and
  for npm by a packed-tarball install during development). The git-clone route is unchanged.
- npm ships the Go binary as six per-platform optional packages (`@horac3/claude-kit-<os>-<arch>`); npm installs only
  the matching one, with no install scripts. The launcher explains missing platforms and alternatives.
- Releases: one `vX.Y.Z` tag (must equal `VERSION`) runs the tests, GoReleaser (Linux, macOS, Windows × amd64/arm64,
  checksums, GitHub Release), then npm publish with provenance and a post-publish smoke test. Re-runs skip versions
  already published.
- The manifest records the install route (`via=git|go|npm`); the installer's closing message shows the matching update command.
- On Windows the binary finds Git Bash itself (skipping WSL's `System32\bash.exe`); `CLAUDE_KIT_BASH` overrides.
- CI: Go vet and tests on Ubuntu, macOS and Windows (Windows non-blocking until proven stable: the first Windows run in CI; Windows was tested by hand in 1.2.1).

## 1.4.0 — 2026-10-19
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

## 1.3.0 — 2026-10-19
- `design-pack.sh --apply` writes licence notices for what the upstream installers copy. Each new skill folder gets its
  upstream `LICENSE` (and `NOTICE` for Apache-2.0), and new agent files point to a licence copy. Existing files are never
  overwritten. `THIRD_PARTY_NOTICES.md` lists every item with its upstream URL, SPDX id and copyright line, plus the
  runtime-only MCP servers and a never-commit note for Anthropic's proprietary `frontend-design` plugin. The kit edits
  only its marked block, and re-runs update entries in place.
- When an upstream has no LICENSE file (currently `vercel-labs/agent-skills`), the licence its README declares is
  recorded and no LICENSE is written. A licence that can't be fetched is marked "add manually" and the run exits non-zero.
- The dry run mentions the notices; the closing message says to commit them with the skills and `skills-lock.json`.
- The pack refuses to run when `THIRD_PARTY_NOTICES.md` has uncommitted changes.
- Docs: `CREDITS.md`, licence guidance in the README and HOW_TO_USE §8.2, and a troubleshooting row. Impeccable's
  installer is verified: its hooks go to `.claude/settings.local.json`, not `settings.json`.

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
