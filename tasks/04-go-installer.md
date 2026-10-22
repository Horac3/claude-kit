# Task 04: package phase 2, port the installer to Go

> **How to run:** in the claude-kit repo, after 1.5.0 is released and its CI (including the Windows `go` job) has
> been green for a while, send: `Read DEVELOPMENT.md, then tasks/04-go-installer.md. Plan first.`

**Goal:** `claude-kit init/update` work without bash. Hooks and scripts installed *into* projects still use bash
(Claude Code on Windows runs them through Git Bash), so this only removes bash from **installing**.

**Non-negotiable:** the bash `install.sh` stays the reference until the Go port matches it exactly.
`TestInitMatchesInstallSh` becomes a table of scenarios, run against both installers, and must be green before the
switch.

## Scope
Port `install.sh` (~420 lines) to `internal/install`:
- stack and package-manager detection, root-first workspace scripts, and empty-means-SKIP behaviour (1.4.0)
- `--frontend`, `--dry-run`, `--update`, and the `via=` route
- kit vs project files, the hash manifest (same file format, so old manifests keep working), `.kit-new` on
  conflicts, obsolete-file reports, append-only `.gitignore` and `.gitattributes`
- `gen_settings` via `encoding/json`: same keys and order, compared as parsed JSON, not as text
- `gen_commands` with the same quoting

## Steps
1. Turn the integration test into a scenario table, using the existing `tests/run.sh` cases as the list:
   go, ts (pnpm, npm, yarn, bun), both, empty repo with `--stack`, pre-existing `CLAUDE.md`, modified kit file then
   update, obsolete file, dry run, `--frontend` on go, workspace root-only lint. Each scenario asserts that
   install.sh and the Go installer produce identical trees (manifest compared field by field).
2. Port behind a hidden `CLAUDE_KIT_ENGINE=go` switch until every scenario passes on Linux, macOS and Windows.
3. Flip the default to the Go engine, and keep `CLAUDE_KIT_ENGINE=bash` for one minor release as a fallback.
4. In the next minor release, drop the embedded bash path from the binary. Keep `install.sh` in the repo for the
   git-clone route, tested against the same scenarios.

## Done when
- Scenario table green on all three OSes for both engines, `tests/run.sh` green, shellcheck clean.
- `claude-kit init` works on Windows without Git Bash (the hooks still need it at runtime; say so in the output).
- CHANGELOG, DEVELOPMENT invariant 0 updated, and the version bumped (minor).
