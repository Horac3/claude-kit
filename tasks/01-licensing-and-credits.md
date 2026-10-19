# Task 01: licence notices for the design pack, CREDITS.md, and the kit's own LICENSE

> **How to run this:** open the repo in VS Code, start Claude Code, and send:
> `Read DEVELOPMENT.md, then tasks/01-licensing-and-credits.md, and carry out the task. Plan first.`

You are working on **claude-kit** itself (see `DEVELOPMENT.md` for layout and invariants). Follow the repo's own
rules: never delete or overwrite user files, test-first for behaviour changes, `tests/run.sh` and shellcheck green
before every commit, Conventional Commits.

## Why

`design-pack.sh` installs third-party skills into a user's project with `npx skills add … --copy` and
`npx impeccable install`. We verified that the copied skill folders contain **only `SKILL.md` and reference files,
no LICENSE**, and `skills-lock.json` records the source but not the licence. Our guide tells users to commit those
folders. A public project would then redistribute MIT and Apache-2.0 files without the required notices.

The kit itself redistributes no third-party code (it runs upstream installers), so it has no obligation. Crediting
the projects we integrate is still the right thing for a public repo.

Licences, verified on 2026-10-19:

| Project | Source | Licence | How the kit uses it |
|---|---|---|---|
| Impeccable | github.com/pbakaus/impeccable | Apache-2.0 | design pack install (copied into project); `npx impeccable detect` at runtime |
| Vercel agent-skills (web-design-guidelines) | github.com/vercel-labs/agent-skills | MIT | design pack install (copied) |
| Emil Kowalski skills | github.com/emilkowalski/skills | MIT | design pack install (copied) |
| taste-skill | github.com/Leonxlnx/taste-skill | MIT | design pack install (copied) |
| shadcn/ui (MCP) | github.com/shadcn-ui/ui | MIT | run via npx at runtime (not copied) |
| Chrome DevTools MCP | github.com/ChromeDevTools/chrome-devtools-mcp | Apache-2.0 | run via npx at runtime (not copied) |
| Anthropic frontend-design plugin | github.com/anthropics/claude-code | Proprietary ("All rights reserved", Anthropic Commercial Terms) | user installs it as a plugin; **must never be copied into a repo** |
| awesome-design-md | github.com/VoltAgent/awesome-design-md | MIT | linked only (DESIGN.md convention) |
| Playwright | github.com/microsoft/playwright | Apache-2.0 | user's own npm dependency, used by shot.mjs |
| axe-core / @axe-core/playwright | github.com/dequelabs/axe-core | MPL-2.0 | user's own npm dependency, used by shot.mjs |

Re-check any licence you rely on (the repo's LICENSE file) rather than trusting this table blindly.

## Deliverables

### 1. `stacks/ts/.claude/kit/design-pack.sh`: write licence notices for copied skills

- **Detect what each install added.** Before each install command, snapshot the directory names under
  `.claude/skills/`; after it, diff to find the skill folders that command created. Map each command to its upstream
  `owner/repo`. They are known per pack: impeccable → `pbakaus/impeccable`, web-design-guidelines →
  `vercel-labs/agent-skills`, motion → `emilkowalski/skills`, taste → `Leonxlnx/taste-skill`.
  Do not guess from names.
- **For each new skill folder:**
  - Fetch the upstream licence: try `LICENSE`, `LICENSE.md`, `LICENSE.txt` at
    `https://raw.githubusercontent.com/<owner>/<repo>/HEAD/<name>`. For Apache-2.0 repos, also fetch `NOTICE` if it exists.
  - Write it as `<skill folder>/LICENSE` (and `NOTICE`) **only if the file does not already exist**. Never overwrite.
  - If the fetch fails, write nothing, print a clear warning naming the skill and repo, and record it as
    "licence not fetched — add manually" in the notices file. Exit non-zero at the end.
- **Maintain `THIRD_PARTY_NOTICES.md` at the project root.**
  - The kit owns only the block between `<!-- claude-kit:third-party:start -->` and `<!-- claude-kit:third-party:end -->`.
    Create the file if it's missing; if the file exists without markers, append the block. Never touch content outside it.
  - Re-running must be idempotent: one entry per skill, updated in place, no duplicates.
  - Each copied skill gets its name, path, upstream URL, SPDX id, and the first `Copyright …` line from its LICENSE (if any).
  - A separate subsection, "Used at runtime, not redistributed", lists the MCP servers the pack configured
    (shadcn, chrome-devtools).
  - A note for the frontend-design plugin: proprietary, installed per user as a plugin, never commit it.
  - Get the SPDX id without a GitHub token: match the LICENSE text (the `MIT License` heading, or `Apache License` with
    `Version 2.0`, and so on). Fall back to `unknown — check <url>`. Avoid the GitHub API (unauthenticated rate limits).
- **Make it testable offline.** Put the fetch behind one function, and let tests point it at a fixtures directory
  through an environment variable (e.g. `KIT_LICENSE_FIXTURES=<dir>` containing `<owner>__<repo>/LICENSE`). No network
  in `tests/run.sh`.
- Update the closing message so it says to commit `THIRD_PARTY_NOTICES.md` and the per-skill `LICENSE` files
  together with the skills and `skills-lock.json`.
- The dry-run output (no `--apply`) should mention that notices will be written.

### 2. `CREDITS.md` at the kit repo root

- **Integrated or recommended tools:** the table above, with what each does for the kit and its licence. Make clear
  the kit does not bundle them.
- **Built on:** Claude Code's documented features (skills, subagents, hooks, rules, status line), plus the kit's
  origin (the author's own Claude Code setup). Keep this short and factual.
- **Discovered through:** two short-form videos about Claude Code design skills, one by Mark Pyvovarov
  (@markpyvovarov on Instagram).
  - The second creator's handle is unknown: **ask the user for it**, and leave a clearly marked `TODO(credit)` if
    they don't know.
- Link `CREDITS.md` from the README, near the design-pack table.

### 3. The kit's own `LICENSE`

Ask the user to confirm the licence before adding it. MIT is the suggestion; the copyright holder is
`Horace Lwanda`, year 2026. The README should state the licence in one line.

### 4. Docs

- **`HOW_TO_USE.md` §8.2:** after installing, review and commit `THIRD_PARTY_NOTICES.md` and the per-skill `LICENSE`
  files. Never commit Anthropic's plugin files. Add a troubleshooting row for "licence not fetched".
- **README design-pack section:** one sentence on licence handling, plus the link to `CREDITS.md`.
- **`DEVELOPMENT.md`:**
  - Extend invariant 7: the design pack writes licence notices, never overwrites, and keeps the notices block idempotent.
  - Add the decision row ("licence notices written at install time, because upstream copies lack LICENSE files").
  - Tick this task off in "Open items".
- **`CHANGELOG.md` + `VERSION`:** bump to 1.3.0.

## Tests (write them first, in `tests/run.sh`)

Use a fake `npx` on `PATH` (a small shell function or script) that just creates skill folders, so no network is needed:

1. A new skill folder gets `LICENSE` from fixtures, and an Apache fixture also gets `NOTICE`.
2. An existing `LICENSE` in a skill folder is **not** overwritten.
3. `THIRD_PARTY_NOTICES.md` is created with the marker block. Running twice leaves exactly one entry per skill.
4. Content outside the markers in an existing `THIRD_PARTY_NOTICES.md` is preserved byte for byte.
5. A missing fixture produces a warning, the "add manually" entry, and a non-zero exit, and the other skills are still processed.
6. SPDX detection: an MIT fixture → `MIT`; an Apache fixture → `Apache-2.0`; unrecognised text → `unknown`.
7. The dry run mentions notices and writes nothing.

Then run `tests/run.sh` and shellcheck:

```
shellcheck -S warning -x install.sh tests/run.sh kit/.claude/hooks/*.sh kit/.claude/kit/*.sh stacks/ts/.claude/kit/*.sh
```

Both must be clean.

## Done when

- All tests pass, shellcheck is clean, and `KIT_TEST_TS=1 tests/run.sh` passes if network is available.
- If network is available: a real `design-pack.sh core motion --apply` in a scratch project produces `LICENSE` files
  and a correct `THIRD_PARTY_NOTICES.md`. Report the result.
- Proposed commits, for example:
  - `test(design-pack): cover licence notices`
  - `feat(design-pack): write upstream licence notices for copied skills`
  - `docs: add CREDITS.md and licence guidance`
  - `chore: add MIT licence` (only after the user confirms)
  - `chore: release 1.3.0`

Commit after the user approves the list.
