// Package claudekit carries the kit's files inside the claude-kit binary.
//
// The installer (install.sh) and everything it installs are embedded, so a single binary, delivered by
// `go install`, a GitHub release, or npm, installs exactly what a git clone of this repository would.
// The `all:` prefix is required: without it, go:embed silently skips the `.claude` folders.
package claudekit

import "embed"

// Files holds install.sh, VERSION and the kit, stacks and scaffold trees, rooted at the repository root.
//
//go:embed install.sh VERSION all:kit all:stacks all:scaffold
var Files embed.FS
