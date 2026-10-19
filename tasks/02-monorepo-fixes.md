# Task 02: monorepo fixes found while adopting the kit in keeper

> **How to run:** in the **claude-kit** repo, send:
> `Read DEVELOPMENT.md, then tasks/02-monorepo-fixes.md, and carry it out. Plan first.`

Found by installing 1.2.0 into a real pnpm monorepo (keeper: 13 packages, lint at the root only, integration tests
that need Postgres, Redis and S3). Follow the repo's invariants in `DEVELOPMENT.md`. Write tests first, keep bash 3.2
compatibility (CI runs macOS bash 3.2), and keep shellcheck clean.

## Bugs

1. **Lint is a false green in workspaces.** `gen_commands` emits `pnpm -r --if-present run lint`. `pnpm -r` skips the
   workspace root, so when lint exists only at the root (`"lint": "eslint ."`) it runs nothing and exits 0.
   I reproduced it on a 2-package workspace: exit 0, nothing ran.
   **Fix:** for each target, prefer the **root** script when the root `package.json` defines it (`pnpm run <script>`;
   keeper's root `typecheck`/`test` already recurse). Fall back to `pnpm -r --if-present run <script>` only when the
   root has no such script. If neither the root nor any package has the script, leave the value empty, so the target
   shows SKIP instead of a false PASS. Do the same for npm, yarn and bun.
2. **The single-test command calls a binary that isn't there.** `CHECK_TEST_ONE='pnpm exec vitest run -t "$1"'` runs
   at the root, where vitest usually isn't installed in a workspace.
   **Fix:** in workspaces use `pnpm -r --if-present run test -t "$1"`. pnpm forwards the extra arguments to each
   package's script (verified); for a script like `pnpm generate && vitest run` they land on the last command, i.e.
   vitest.
3. **`check.sh` can report PASS when nothing ran.** Add a guard: if the command exits 0 but its log is empty or shows
   that no package matched (pnpm: "No projects matched", or "None of the selected packages has a … script"), report
   `SKIP <target> (nothing ran)` instead of PASS. Test it with a fake command.

## Improvements

4. **A test split for integration tests.** Document the pattern in `HOW_TO_USE.md` §11 (Customise): a project-owned
   helper that runs the integration-test packages only when their services answer, and exits non-zero with an
   `Error: … NOT tested …` line otherwise. Use keeper's `.claude/project/test.sh` as the example, made generic:
   service ports and package names are variables. Partial runs must never be green.
5. **`/decide` should follow the existing decision-log format.** In `skills/decide/SKILL.md`, if `docs/decisions.md`
   already uses another entry style (e.g. `## <Topic> (step N)`), match it instead of `D-NNN`.
   `skills/kickoff/existing.md` step E should record the detected style in a project rule.
6. **The existing-project `/kickoff` should notice oversized handoffs.** If "Handoff notes" in `docs/progress.md` is
   over ~60 lines, propose moving older handoffs **verbatim** to `docs/progress-archive.md` (by script, never retyped),
   and adding `## Log` if missing.
7. **Wrong paths in `examples/keepsake/.claude/rules/retention.md`.** `packages/domain/**/*purge*` does not match
   files inside a `purge/` folder. Use folder globs (`**/retention/**`, `**/purge/**`). In `payments.md`, add
   `**/checkout/**`.
   - If task 01 or open item 1 has already replaced the Keepsake example with a fictional one, apply the same lesson
     there.
   - Add a sentence to the README: glob a rule's folders, not only file names.
8. **A `--frontend` flag.** It adds the TypeScript stack's frontend layer (`frontend.md`, `/ui`, `ui-checker`,
   `shot.mjs`, `design-pack.sh`) to any stack, e.g. a Go service rendering HTML templates. Record it in the manifest
   so `--update` keeps it.

## Tests to add (first)

- Root-only lint in a pnpm workspace makes `commands.env` use `pnpm run lint`.
- A package-only script in a workspace makes it use `pnpm -r --if-present run <x>`.
- A script that exists nowhere leaves the value empty, and `check.sh` shows SKIP.
- `check.sh` with a command that exits 0 but prints "No projects matched" shows SKIP, not PASS.
- A workspace gets `CHECK_TEST_ONE` with `pnpm -r --if-present run test -t`.
- `--frontend` with `--stack go` installs the frontend files; `--update` keeps them.

## Done when

- `tests/run.sh` and shellcheck are green, and CI (Ubuntu and macOS bash 3.2) is green after push.
- Bump `VERSION` (minor) and update `CHANGELOG.md`. In `DEVELOPMENT.md`, record the "verified on a real monorepo"
  note and tick these items.
- Propose commits, and commit after approval.
