# Credits

claude-kit stands on other people's work. This page credits it.

## Integrated or recommended tools

The kit does **not** bundle any of these. `design-pack.sh` runs their upstream installers in your project, `ui-checker`
runs `npx impeccable detect`, and `shot.mjs` uses packages you add to your own project. Licences were checked on 2026-10-19
against each project's LICENSE file; re-check them before relying on this table.

| Project | What it does for the kit | Licence |
|---|---|---|
| [Impeccable](https://github.com/pbakaus/impeccable) | Design vocabulary, critique/audit/polish skills and `DESIGN.md` generation (design pack, core); `impeccable detect` scans for generic "AI-made" design in `ui-checker` | Apache-2.0 |
| [Vercel agent-skills](https://github.com/vercel-labs/agent-skills) (`web-design-guidelines`) | Reviews UI code against Vercel's interface guidelines (design pack, core) | MIT (declared in its README; the repository has no LICENSE file) |
| [Emil Kowalski skills](https://github.com/emilkowalski/skills) | Animation craft, animation review, Apple design principles, worst-case-data UI testing (design pack, motion) | MIT |
| [taste-skill](https://github.com/Leonxlnx/taste-skill) | Layout, type and spacing taste (design pack, taste) | MIT |
| [shadcn/ui](https://github.com/shadcn-ui/ui) | MCP server for browsing and installing registry components (design pack, shadcn); runs through npx, nothing copied | MIT |
| [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp) | Live browser with console, network and performance traces (design pack, devtools); runs through npx, nothing copied | Apache-2.0 |
| [Anthropic frontend-design plugin](https://github.com/anthropics/claude-code) | Aesthetic-direction skill; each user installs it as a Claude Code plugin | Proprietary (Anthropic Commercial Terms). Never copy it into a repository |
| [awesome-design-md](https://github.com/VoltAgent/awesome-design-md) | The `DESIGN.md` convention and reference files; linked only | MIT |
| [Playwright](https://github.com/microsoft/playwright) | Screenshots and layout checks in `shot.mjs` (your project's own dependency) | Apache-2.0 |
| [axe-core / @axe-core/playwright](https://github.com/dequelabs/axe-core) | Accessibility checks in `shot.mjs` (your project's own dependency) | MPL-2.0 |

When the design pack copies skills or agents into a project, it also writes their upstream `LICENSE` (and `NOTICE`)
and lists them in the project's `THIRD_PARTY_NOTICES.md`, so a public project can commit them with the required notices.

## Built on

- Claude Code's documented extension points: [skills](https://code.claude.com/docs/en/skills.md),
  [subagents](https://code.claude.com/docs/en/sub-agents.md), [hooks](https://code.claude.com/docs/en/hooks-guide.md),
  path-scoped rules, and the status line.
- The author's own Claude Code setup on a TypeScript monorepo, generalised into this kit.

## Discovered through

Two short-form videos about Claude Code design skills pointed the way to several of the tools above:

- Mark Pyvovarov ([@markpyvovarov](https://www.instagram.com/markpyvovarov/) on Instagram).
- <!-- TODO(credit): second video creator's name and handle are unknown; add them here. --> A second creator, not yet identified.
