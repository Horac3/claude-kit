package main

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"

	claudekit "github.com/horac3/claude-kit"
)

const repoRoot = "../.."

// Every file in kit/, stacks/ and scaffold/ (including the .claude folders) must be embedded.
func TestEmbedContainsEveryKitFile(t *testing.T) {
	var want []string
	for _, dir := range []string{"kit", "stacks", "scaffold"} {
		err := filepath.WalkDir(filepath.Join(repoRoot, dir), func(p string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}
			rel, _ := filepath.Rel(repoRoot, p)
			want = append(want, filepath.ToSlash(rel))
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
	for _, f := range append(want, "install.sh", "VERSION") {
		if _, err := fs.Stat(claudekit.Files, f); err != nil {
			t.Errorf("not embedded: %s", f)
		}
	}
	if _, err := fs.Stat(claudekit.Files, "kit/.claude/hooks/guard-bash.sh"); err != nil {
		t.Fatal("the .claude folders are not embedded (missing all: prefix?)")
	}
}

func TestExtractMakesScriptsExecutable(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows has no execute bits; Git Bash runs the scripts regardless")
	}
	dst := t.TempDir()
	if err := extract(claudekit.Files, dst); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"install.sh", "kit/.claude/hooks/guard-bash.sh", "kit/.claude/kit/check.sh"} {
		st, err := os.Stat(filepath.Join(dst, filepath.FromSlash(f)))
		if err != nil {
			t.Fatal(err)
		}
		if st.Mode().Perm()&0o100 == 0 {
			t.Errorf("%s is not executable: %v", f, st.Mode())
		}
	}
	st, _ := os.Stat(filepath.Join(dst, "kit/.claude/skills/next/SKILL.md"))
	if st.Mode().Perm()&0o111 != 0 {
		t.Errorf("SKILL.md should not be executable")
	}
}

func TestVersionMatchesVERSIONFile(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join(repoRoot, "VERSION"))
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if code := run([]string{"version"}, &out, &out); code != 0 {
		t.Fatalf("exit %d", code)
	}
	if !strings.HasPrefix(out.String(), "claude-kit "+strings.TrimSpace(string(raw))) {
		t.Errorf("version output %q does not start with VERSION %q", out.String(), raw)
	}
}

func TestUnknownCommandAndPack(t *testing.T) {
	var out bytes.Buffer
	if code := run([]string{"frobnicate"}, &out, &out); code != 2 {
		t.Errorf("unknown command: exit %d, want 2", code)
	}
	if code := run([]string{"pack", "nope"}, &out, &out); code != 2 {
		t.Errorf("unknown pack: exit %d, want 2", code)
	}
	if code := run([]string{"init", "--update"}, &out, &out); code != 2 {
		t.Errorf("init --update: exit %d, want 2", code)
	}
}

func TestWSLLauncherIsSkipped(t *testing.T) {
	if !isWSLLauncher(`C:\Windows\System32\bash.exe`) {
		t.Error("System32 bash.exe should be treated as the WSL launcher")
	}
	if isWSLLauncher(`C:\Program Files\Git\bin\bash.exe`) {
		t.Error("Git Bash must not be treated as the WSL launcher")
	}
}

// The binary must install exactly what a git clone's install.sh installs (apart from the recorded route).
func TestInitMatchesInstallSh(t *testing.T) {
	if testing.Short() {
		t.Skip("integration test")
	}
	bash, err := findBash()
	if err != nil {
		t.Skip("bash not available: ", err)
	}
	viaClone := newProject(t)
	viaBinary := newProject(t)

	// Same bash and path form the binary uses, so this also holds on Windows (Git Bash).
	sh := exec.Command(bash, bashPath(filepath.Join(repoRoot, "install.sh")), bashPath(viaClone))
	sh.Env = withoutVia(os.Environ())
	if out, err := sh.CombinedOutput(); err != nil {
		t.Fatalf("install.sh: %v\n%s", err, out)
	}
	t.Setenv("CLAUDE_KIT_VIA", "")
	if code := run([]string{"init", viaBinary}, os.Stdout, os.Stderr); code != 0 {
		t.Fatalf("claude-kit init: exit %d", code)
	}

	a, b := snapshot(t, viaClone), snapshot(t, viaBinary)
	if len(a) != len(b) {
		t.Fatalf("file count differs: install.sh %d, claude-kit %d\n%v\n%v", len(a), len(b), keys(a), keys(b))
	}
	for name, content := range a {
		other, ok := b[name]
		if !ok {
			t.Errorf("missing from claude-kit install: %s", name)
			continue
		}
		if name == ".claude/kit/manifest" {
			content = strings.Replace(content, "via=git", "via=go", 1)
		}
		if content != other {
			t.Errorf("content differs: %s%s", name, lineDiff(content, other))
		}
	}
	if !strings.Contains(b[".claude/kit/manifest"], "via=go") {
		t.Error("manifest should record via=go")
	}

	// A second run with update changes nothing.
	if code := run([]string{"update", viaBinary}, os.Stdout, os.Stderr); code != 0 {
		t.Fatalf("claude-kit update: exit %d", code)
	}
	after := snapshot(t, viaBinary)
	for name, content := range b {
		if after[name] != content {
			t.Errorf("update changed %s", name)
		}
	}
}

func newProject(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	for _, args := range [][]string{{"init", "-q"}} {
		c := exec.Command("git", args...)
		c.Dir = dir
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "go.mod"), []byte("module example.com/x\n\ngo 1.22\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func snapshot(t *testing.T, root string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && d.Name() == ".git" {
			return filepath.SkipDir
		}
		if d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(root, p)
		data, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		out[filepath.ToSlash(rel)] = string(data)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func keys(m map[string]string) []string {
	var k []string
	for name := range m {
		k = append(k, name)
	}
	sort.Strings(k)
	return k
}

func withoutVia(env []string) []string {
	var out []string
	for _, e := range env {
		if !strings.HasPrefix(e, "CLAUDE_KIT_VIA=") {
			out = append(out, e)
		}
	}
	return out
}

// lineDiff lists the lines only one side has (at most 10 each), so a CI failure says what differs.
func lineDiff(a, b string) string {
	only := func(x, y string) []string {
		seen := map[string]bool{}
		for _, l := range strings.Split(y, "\n") {
			seen[l] = true
		}
		var out []string
		for _, l := range strings.Split(x, "\n") {
			if !seen[l] && len(out) < 10 {
				out = append(out, l)
			}
		}
		return out
	}
	return fmt.Sprintf("\n  install.sh only: %q\n  claude-kit only: %q", only(a, b), only(b, a))
}
