// Command claude-kit installs and updates the claude-kit Claude Code setup in a project.
//
// Phase 1 of the Go CLI: the kit's files and its tested bash installer are embedded in this binary. Each command
// unpacks them to a temporary folder and runs install.sh (or a pack script) with bash, so every install route
// (git clone, go install, release binary, npm) produces identical results.
package main

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"runtime/debug"
	"strings"

	claudekit "github.com/horac3/claude-kit"
)

const usage = `claude-kit: a Claude Code setup for Go, TypeScript and Python projects.

Usage:
  claude-kit init   [--stack go|ts|py|both|auto] [--frontend] [--data] [--dry-run] [DIR]
                                                     install into a project (default: .); --stack go,py for several
  claude-kit update [--frontend] [--data] [--dry-run] [DIR]   update an installed project
  claude-kit pack design [core|motion|taste|shadcn|devtools|all] [--apply|--list]
                                                     optional third-party design skills
  claude-kit pack data [core|eda|notebooks|ml|dbt|duckdb|all] [--apply|--list]
                                                     optional third-party data-science skills
  claude-kit version
  claude-kit help

The installer never deletes or overwrites your changes; see https://github.com/horac3/claude-kit.
`

// version is set at release time with -ldflags "-X main.version=..."; otherwise the embedded VERSION is used.
var version = ""

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return 2
	}
	cmd, rest := args[0], args[1:]
	switch cmd {
	case "help", "-h", "--help":
		fmt.Fprint(stdout, usage)
		return 0
	case "version", "--version", "-v":
		fmt.Fprintf(stdout, "claude-kit %s\n", kitVersion())
		return 0
	case "init", "install":
		for _, a := range rest {
			if a == "--update" {
				fmt.Fprintln(stderr, "claude-kit: use `claude-kit update` instead of `init --update`")
				return 2
			}
		}
		return runScript(stderr, "install.sh", rest, "")
	case "update":
		return runScript(stderr, "install.sh", append([]string{"--update"}, rest...), "")
	case "pack":
		return runPack(rest, stdout, stderr)
	default:
		fmt.Fprintf(stderr, "claude-kit: unknown command %q\n\n%s", cmd, usage)
		return 2
	}
}

func runPack(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stdout, "Available packs:\n  design   third-party frontend design skills (Impeccable, Vercel guidelines, …)\n"+
			"  data     third-party data-science skills (Anthropic data skills, notebooks, EDA, ML, dbt, DuckDB)\n"+
			"Run: claude-kit pack design --list   or   claude-kit pack data --list\n")
		return 0
	}
	scripts := map[string]string{
		"design": "stacks/ts/.claude/kit/design-pack.sh",
		"data":   "stacks/data/.claude/kit/data-pack.sh",
	}
	script, ok := scripts[args[0]]
	if !ok {
		fmt.Fprintf(stderr, "claude-kit: unknown pack %q (available: design, data)\n", args[0])
		return 2
	}
	dir, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(stderr, "claude-kit: %v\n", err)
		return 1
	}
	return runScript(stderr, script, args[1:], dir)
}

// runScript unpacks the embedded kit and runs one of its scripts with bash.
// projectDir, when set, is passed as CLAUDE_PROJECT_DIR (the pack scripts work on the current project).
func runScript(stderr io.Writer, script string, args []string, projectDir string) int {
	bash, err := findBash()
	if err != nil {
		fmt.Fprintf(stderr, "claude-kit: %v\n", err)
		return 1
	}
	tmp, err := os.MkdirTemp("", "claude-kit-")
	if err != nil {
		fmt.Fprintf(stderr, "claude-kit: %v\n", err)
		return 1
	}
	defer os.RemoveAll(tmp) // only the temporary copy of the kit this process created

	if err := extract(claudekit.Files, tmp); err != nil {
		fmt.Fprintf(stderr, "claude-kit: unpacking the kit: %v\n", err)
		return 1
	}

	cmdArgs := append([]string{bashPath(filepath.Join(tmp, filepath.FromSlash(script)))}, bashArgs(args)...)
	c := exec.Command(bash, cmdArgs...)
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	c.Env = append(os.Environ(), "CLAUDE_KIT_VIA="+via())
	if projectDir != "" {
		c.Env = append(c.Env, "CLAUDE_PROJECT_DIR="+bashPath(projectDir))
	}
	if err := c.Run(); err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			return exit.ExitCode()
		}
		fmt.Fprintf(stderr, "claude-kit: running %s: %v\n", script, err)
		return 1
	}
	return 0
}

// via reports the install route for the manifest: the npm launcher sets CLAUDE_KIT_VIA=npm, otherwise "go".
func via() string {
	if v := os.Getenv("CLAUDE_KIT_VIA"); v == "npm" {
		return v
	}
	return "go"
}

// extract writes every embedded file under dst, keeping the repository layout.
// Shell scripts are made executable; nothing outside dst is touched.
func extract(src fs.FS, dst string) error {
	return fs.WalkDir(src, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		target := filepath.Join(dst, filepath.FromSlash(p))
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, err := fs.ReadFile(src, p)
		if err != nil {
			return err
		}
		mode := os.FileMode(0o644)
		if path.Ext(p) == ".sh" {
			mode = 0o755
		}
		return os.WriteFile(target, data, mode)
	})
}

func kitVersion() string {
	if version != "" {
		return strings.TrimPrefix(version, "v")
	}
	v, err := fs.ReadFile(claudekit.Files, "VERSION")
	if err != nil {
		return "unknown"
	}
	s := strings.TrimSpace(string(v))
	if info, ok := debug.ReadBuildInfo(); ok {
		for _, kv := range info.Settings {
			if kv.Key == "vcs.revision" && len(kv.Value) >= 7 {
				s += " (" + kv.Value[:7] + ")"
			}
		}
	}
	return s
}
