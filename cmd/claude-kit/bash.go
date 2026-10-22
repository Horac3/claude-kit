package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// findBash locates a bash that can run the kit's scripts.
//
// CLAUDE_KIT_BASH overrides the search. On Windows, Git Bash is preferred and WSL's launcher
// (C:\Windows\System32\bash.exe) is skipped: it runs inside Linux and cannot see Windows paths as given.
func findBash() (string, error) {
	if b := os.Getenv("CLAUDE_KIT_BASH"); b != "" {
		return b, nil
	}
	if runtime.GOOS != "windows" {
		if b, err := exec.LookPath("bash"); err == nil {
			return b, nil
		}
		return "", errors.New("bash not found on PATH (the kit's installer and hooks need bash)")
	}
	for _, c := range windowsBashCandidates() {
		if c == "" || isWSLLauncher(c) {
			continue
		}
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			return c, nil
		}
	}
	return "", errors.New("Git Bash not found. Install Git for Windows (https://git-scm.com/download/win), " +
		"which Claude Code on Windows also needs, or set CLAUDE_KIT_BASH to a bash.exe")
}

func windowsBashCandidates() []string {
	var out []string
	if b, err := exec.LookPath("bash"); err == nil {
		out = append(out, b)
	}
	// git.exe lives in <Git>\cmd or <Git>\mingw64\bin; bash.exe in <Git>\bin.
	if g, err := exec.LookPath("git"); err == nil {
		root := filepath.Dir(filepath.Dir(g))
		out = append(out, filepath.Join(root, "bin", "bash.exe"), filepath.Join(filepath.Dir(root), "bin", "bash.exe"))
	}
	for _, env := range []string{"ProgramFiles", "ProgramW6432", "ProgramFiles(x86)", "LOCALAPPDATA"} {
		if base := os.Getenv(env); base != "" {
			out = append(out, filepath.Join(base, "Git", "bin", "bash.exe"), filepath.Join(base, "Programs", "Git", "bin", "bash.exe"))
		}
	}
	return out
}

func isWSLLauncher(p string) bool {
	return strings.Contains(strings.ToLower(filepath.Clean(p)), `\windows\system32\`)
}

// bashPath turns a native path into one Git Bash accepts (C:\x\y → C:/x/y). A no-op elsewhere.
func bashPath(p string) string {
	if runtime.GOOS == "windows" {
		return filepath.ToSlash(p)
	}
	return p
}

// bashArgs converts path-like arguments the same way (the target directory may be a native Windows path).
func bashArgs(args []string) []string {
	if runtime.GOOS != "windows" {
		return args
	}
	out := make([]string, len(args))
	for i, a := range args {
		if !strings.HasPrefix(a, "-") && strings.ContainsAny(a, `\:`) {
			a = filepath.ToSlash(a)
		}
		out[i] = a
	}
	return out
}
