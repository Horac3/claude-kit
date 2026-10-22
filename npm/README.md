# claude-kit

A drop-in Claude Code setup for Go and TypeScript projects: a small always-loaded context, model routing by
delegation, file-based handoffs between conversations, and safety rules enforced by hooks.

```bash
npx claude-kit init          # install into the current project (auto-detects go / ts / both)
npx claude-kit@latest update # pull a newer kit into an installed project
npx claude-kit pack design   # optional third-party design skills (dry run; add --apply)
```

This npm package is a launcher for a prebuilt Go binary. npm installs only the binary that matches your
platform (Linux, macOS and Windows on x64 and arm64), and runs no install scripts.

**Requirements:** bash (on Windows, Git for Windows, which Claude Code on Windows also needs).

Other ways to install the same thing:
- `go install github.com/horac3/claude-kit/cmd/claude-kit@latest`
- a binary from [GitHub Releases](https://github.com/horac3/claude-kit/releases)
- `git clone https://github.com/horac3/claude-kit && claude-kit/install.sh <project>`

Documentation: [README](https://github.com/horac3/claude-kit#readme) ·
[How to use](https://github.com/horac3/claude-kit/blob/main/HOW_TO_USE.md) · MIT licence.
