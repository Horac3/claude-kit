#!/usr/bin/env bash
# claude-kit self-tests: installer, update flow, guard hooks, session hook, check runner, statusline.
# Usage: tests/run.sh            (needs bash, git, go; node+pnpm for the TS check test, skipped otherwise)
set -uo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
expect_exit() { # expect_exit <code> <desc> <cmd...>
  local want="$1" desc="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc"; else ko "$desc (exit $got, want $want)" "$out"; fi
}
contains() { # contains <haystack> <needle> <desc>
  if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else ko "$3" "$(printf '%s' "$1" | head -20)"; fi
}

echo "== installer: go project"
P="$WORK/goproj"; mkdir -p "$P"; cd "$P" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
cat >go.mod <<'EOF'
module example.com/demo

go 1.22
EOF
mkdir -p internal/calc
cat >internal/calc/calc.go <<'EOF'
package calc

// Add returns a + b.
func Add(a, b int) int { return a + b }
EOF
cat >internal/calc/calc_test.go <<'EOF'
package calc

import "testing"

func TestAdd(t *testing.T) {
	if got := Add(2, 3); got != 5 {
		t.Fatalf("Add(2,3) = %d, want 5", got)
	}
}
EOF
git add -A && git commit -qm init
out="$("$KIT/install.sh" "$P" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "install exits 0" || ko "install exits 0" "$out"
contains "$out" "stack: go" "detects go stack"
for f in CLAUDE.md docs/progress.md .claude/settings.json .claude/kit/commands.env .claude/kit/manifest \
  .claude/skills/next/SKILL.md .claude/agents/test-runner.md .claude/hooks/guard-bash.sh \
  .claude/rules/kit/go.md .claude/rules/kit/model-routing.md; do
  [ -f "$P/$f" ] && ok "installed $f" || ko "installed $f"
done
[ ! -f "$P/.claude/rules/kit/typescript.md" ] && ok "no TS rule in a Go project" || ko "no TS rule in a Go project"
if command -v jq >/dev/null; then
  jq -e '.hooks.PreToolUse | length == 2' "$P/.claude/settings.json" >/dev/null && ok "settings.json valid, hooks wired" || ko "settings.json valid"
  jq -e '.permissions.allow | index("Bash(go test *)")' "$P/.claude/settings.json" >/dev/null && ok "go permissions present" || ko "go permissions present"
fi
grep -qxF '.claude/kit/logs/' .gitignore && ok ".gitignore updated" || ko ".gitignore updated"
grep -qxF '.claude/**/*.sh text eol=lf' .gitattributes && ok "kit scripts forced to LF (.gitattributes)" || ko "kit scripts forced to LF"

echo "== check runner"
out="$(.claude/kit/check.sh all 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "check.sh all passes on green project" || ko "check.sh all passes" "$out"
contains "$out" "PASS test" "reports PASS test"
cat >internal/calc/calc_test.go <<'EOF'
package calc

import "testing"

func TestAdd(t *testing.T) {
	for i := 0; i < 200; i++ {
		t.Logf("noise line %d", i)
	}
	if got := Add(2, 2); got != 5 {
		t.Fatalf("Add(2,2) = %d, want 5", got)
	}
}
EOF
out="$(.claude/kit/check.sh test 2>&1)"; rc=$?
[ $rc -ne 0 ] && ok "check.sh test fails on red test" || ko "check.sh test fails on red"
contains "$out" "want 5" "failure line surfaced"
lines=$(printf '%s\n' "$out" | wc -l)
[ "$lines" -le 70 ] && ok "failure output capped ($lines lines vs $(wc -l <.claude/kit/logs/test.log) in log)" || ko "failure output capped ($lines lines)"
out="$(.claude/kit/check.sh test-one TestAdd 2>&1)"
contains "$out" "FAIL test-one" "test-one runs a single test"
git checkout -q internal/calc/calc_test.go

echo "== guard-bash"
gb() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" |
  CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/guard-bash.sh"; }
for c in "rm -rf dist" "cd x && rm -f a.txt" "sudo rm a" "git clean -fd" "git reset --hard HEAD~1" \
  "git checkout -- src/a.go" "git restore ." "git push --force origin main" "git push -f" "git push origin +main" \
  "git push origin :feature" "git branch -D old" "git stash drop" "git -C sub clean -xfd" \
  "find . -name '*.tmp' -delete" "find . -exec rm {} \\;" "ls | xargs rm" "git rm file.go" \
  "docker compose down -v" "docker volume prune -f" "cat .env" "grep KEY .env.local" \
  "bash -c \"rm -rf /tmp/x\"" "truncate -s 0 file"; do
  expect_exit 2 "blocks: $c" gb "$c"
done
for c in "go test ./..." "git status --short" "git commit -m \"refactor: clean up rm usage\"" \
  "git log --oneline -5" "cat .env.example" "grep -rn process.env src" "pnpm -r test" \
  "echo 'git reset --hard is forbidden'" "git diff --stat" "npm run format" "firm the logic" \
  $'git commit -F - <<\'EOF\'\nchore: drop rm -rf from scripts\nEOF' "docker compose up -d" "go build ./cmd/rmtool"; do
  expect_exit 0 "allows: ${c%%$'\n'*}" gb "$c"
done

echo "== guard-files"
gf() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" |
  CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/guard-files.sh"; }
expect_exit 2 "blocks Write .env"              gf Write "$P/.env"
expect_exit 2 "blocks Edit .env.production"    gf Edit "$P/.env.production"
expect_exit 0 "allows .env.example"            gf Write "$P/.env.example"
expect_exit 2 "blocks go.sum"                  gf Edit "$P/go.sum"
expect_exit 2 "blocks AGENTS.md"               gf Write "$P/AGENTS.md"
expect_exit 2 "blocks hook edits"              gf Edit "$P/.claude/hooks/guard-bash.sh"
expect_exit 2 "blocks settings.json"           gf Edit "$P/.claude/settings.json"
expect_exit 2 "blocks Write over tracked file" gf Write "$P/internal/calc/calc.go"
expect_exit 0 "allows Edit of tracked file"    gf Edit "$P/internal/calc/calc.go"
expect_exit 0 "allows Write of new file"       gf Write "$P/internal/calc/new.go"
expect_exit 0 "allows Edit of commands.env"    gf Edit "$P/.claude/kit/commands.env"

echo "== guard fallbacks without jq"
nojq="$WORK/nojq"; mkdir -p "$nojq"
# Wrapper scripts rather than symlinks: Git Bash on Windows cannot create symlinks without Developer Mode.
for b in bash cat sed awk grep tr head git python3 dirname wc; do
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v $b)" >"$nojq/$b"; chmod +x "$nojq/$b"
done
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' | PATH="$nojq" CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/guard-bash.sh" 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "guard works with python3 only" || ko "guard works with python3 only" "$out"
rm -f "$nojq/python3"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"git clean -fd"}}' | PATH="$nojq" CLAUDE_PROJECT_DIR="$P" bash "$P/.claude/hooks/guard-bash.sh" 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "guard works with no JSON tool at all" || ko "guard works with no JSON tool" "$out"

echo "== session-context"
cat >docs/progress.md <<'EOF'
# Progress

## Roadmap
- [x] 1. Scaffold
- [~] 2. Retention policy — FR-RET-01

## Current step
Step 2: Retention policy
Requirements: FR-RET-01
Status: in progress — 1 of 3 behaviours done

## Handoff notes
- Done: purge date for drafts
- Next action: write test for delivered-window purge date in internal/retention/policy_test.go
- Watch out: clock is injected

## Log
EOF
out="$(printf '{"source":"compact"}' | CLAUDE_PROJECT_DIR="$P" bash .claude/hooks/session-context.sh)"
contains "$out" "Step 2: Retention policy" "injects current step"
contains "$out" "Next action: write test" "injects next action"
contains "$out" "compacted" "compact reminder"
n=$(printf '%s\n' "$out" | wc -l); [ "$n" -le 8 ] && ok "session context stays small ($n lines)" || ko "session context small ($n lines)"

echo "== statusline"
out="$(printf '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":72},"cost":{"total_cost_usd":0.4321},"workspace":{"project_dir":"%s","current_dir":"%s"}}' "$P" "$P" | bash .claude/kit/statusline.sh)"
contains "$out" "Sonnet" "statusline shows model"
contains "$out" "/handoff now" "statusline warns at 72%"
contains "$out" "\$0.43" "statusline shows cost"
contains "$out" "Step 2: Retention policy" "statusline shows step"

echo "== update flow"
K2="$WORK/kit2"; cp -R "$KIT" "$K2"; rm -rf "$K2/.git"
echo "1.0.1" >"$K2/VERSION"
printf '\n- New rule from kit 1.0.1.\n' >>"$K2/kit/.claude/rules/kit/working-rules.md"
printf '\n<!-- kit 1.0.1 -->\n' >>"$K2/kit/.claude/skills/tdd/SKILL.md"
printf '\n<!-- kit 1.0.1 template -->\n' >>"$K2/scaffold/CLAUDE.md"
printf '\nLocal tweak.\n' >>"$P/.claude/skills/tdd/SKILL.md"           # user-modified kit file
printf '\nProject content.\n' >>"$P/CLAUDE.md"                         # project file
out="$("$K2/install.sh" --update "$P" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "update exits 0" || ko "update exits 0" "$out"
grep -q "New rule from kit 1.0.1" "$P/.claude/rules/kit/working-rules.md" && ok "unmodified kit file updated" || ko "unmodified kit file updated" "$out"
grep -q "Local tweak" "$P/.claude/skills/tdd/SKILL.md" && ok "modified kit file kept" || ko "modified kit file kept"
[ -f "$P/.claude/skills/tdd/SKILL.md.kit-new" ] && ok "modified kit file gets .kit-new" || ko ".kit-new for modified kit file" "$out"
grep -q "Project content" "$P/CLAUDE.md" && ok "CLAUDE.md never overwritten" || ko "CLAUDE.md never overwritten"
[ -f "$P/CLAUDE.md.kit-new" ] && ok "changed template offered as CLAUDE.md.kit-new" || ko "CLAUDE.md.kit-new" "$out"
grep -q '^version=1.0.1' "$P/.claude/kit/manifest" && ok "manifest records new version" || ko "manifest version"
rm "$K2/kit/.claude/agents/debugger.md"
out="$("$K2/install.sh" --update "$P" 2>&1)"
[ -f "$P/.claude/agents/debugger.md" ] && ok "obsolete file not deleted" || ko "obsolete file not deleted"
contains "$out" "obsolete .claude/agents/debugger.md" "obsolete file reported"
out="$("$K2/install.sh" --update --dry-run "$P" 2>&1)"
contains "$out" "dry run" "dry run supported"
[ "$(grep -cxF '.claude/**/*.sh text eol=lf' "$P/.gitattributes")" = 1 ] && ok ".gitattributes not duplicated on update" || ko ".gitattributes not duplicated"

echo "== installer: pre-existing CLAUDE.md is kept"
Q="$WORK/existing"; mkdir -p "$Q"; cd "$Q" || exit 1; git init -q
echo '{"name":"x","scripts":{"test":"vitest run"}}' >package.json
echo "# My rules" >CLAUDE.md
printf '*.png binary' >.gitattributes   # no trailing newline
"$KIT/install.sh" "$Q" >/dev/null 2>&1
[ "$(cat CLAUDE.md)" = "# My rules" ] && ok "existing CLAUDE.md untouched" || ko "existing CLAUDE.md untouched"
grep -qxF '*.png binary' .gitattributes && grep -qxF '.claude/**/*.sh text eol=lf' .gitattributes &&
  ok "existing .gitattributes appended to, not merged" || ko "existing .gitattributes appended" "$(cat .gitattributes)"
[ -f CLAUDE.md.kit-new ] && ok "template offered alongside" || ko "template offered alongside"
[ -f .claude/rules/kit/typescript.md ] && ok "ts stack detected" || ko "ts stack detected"
grep -q "pnpm run --if-present test" .claude/kit/commands.env && ok "uses existing test script" || ko "uses existing test script" "$(cat .claude/kit/commands.env)"

[ -f .claude/skills/ui/SKILL.md ] && [ -f .claude/agents/ui-checker.md ] && [ -f .claude/kit/shot.mjs ] &&
  ok "ts project gets frontend layer" || ko "ts project gets frontend layer"
[ ! -f "$P/.claude/skills/ui/SKILL.md" ] && ok "go project has no frontend layer" || ko "go project has no frontend layer"
node --check .claude/kit/shot.mjs 2>/dev/null && ok "shot.mjs parses" || ko "shot.mjs parses"
out="$(.claude/kit/design-pack.sh core motion shadcn 2>&1)"
contains "$out" "impeccable install" "design pack plans impeccable"
contains "$out" "--skill web-design-guidelines" "design pack plans vercel guidelines"
contains "$out" "no components.json" "design pack skips shadcn without components.json"
contains "$out" "Nothing installed" "design pack is a dry run by default"

echo "== context gatherer (existing project)"
E="$WORK/legacy"; mkdir -p "$E/internal/billing" "$E/cmd/api" "$E/docs/adr"; cd "$E" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
printf 'module example.com/legacy\n\ngo 1.22\n' >go.mod
for i in 1 2 3 4 5 6 7 8 9 10 11; do printf 'package billing\n\n// TODO: tidy %s\nfunc F%s() {}\n' $i $i >internal/billing/f$i.go; done
printf 'package main\n\nfunc main() {}\n' >cmd/api/main.go
printf '# Legacy\nRun with make.\n' >README.md
printf '# Use Postgres\nWe chose Postgres.\n' >docs/adr/0001-use-postgres.md
printf 'Always use tabs.\nNever touch generated code.\n' >.cursorrules
printf '# Old CLAUDE\n- rule one\n' >CLAUDE.md
git add -A && git commit -qm "initial legacy"
for i in 1 2 3; do echo "// change $i" >>internal/billing/f1.go; git commit -qam "billing: change $i"; done
"$KIT/install.sh" "$E" >/dev/null 2>&1
C=.claude/kit/context.sh
[ "$($C mode)" = existing ] && ok "detects existing project" || ko "detects existing project" "$($C mode)"
out="$($C existing)"
contains "$out" ".cursorrules" "finds other AI-tool rules"
contains "$out" "CLAUDE.md.kit-new present" "notices pre-existing CLAUDE.md"
contains "$out" "Use Postgres" "lists ADR titles"
contains "$out" "README.md" "lists project docs"
out="$($C history 5)"
contains "$out" "internal/billing/f1.go (4 commits)" "finds hotspots"
contains "$out" "billing: change 3" "lists recent commits"
contains "$out" "TODO / FIXME" "reports TODO density"
out="$($C layout)"
contains "$out" "internal/" "layout lists directories"
[ "$(cd "$WORK/goproj" && .claude/kit/context.sh mode)" = greenfield ] && ok "small project is greenfield" || ko "small project is greenfield"
grep -q 'existing.md' .claude/skills/kickoff/SKILL.md && [ -f .claude/skills/kickoff/existing.md ] && ok "kickoff ships existing-project procedure" || ko "kickoff existing.md"

echo "== drift and staleness"
sha="$(git rev-parse --short HEAD)"
printf '<!-- mapped-at: %s 2026-01-01 -->\n# Architecture\n- Billing: `internal/billing/`\n- Legacy worker: `internal/worker/run.go`\n' "$sha" >docs/architecture.md
[ -z "$($C stale)" ] && ok "fresh map is silent" || ko "fresh map is silent"
mkdir -p internal/payments
for i in $(seq 1 16); do printf 'package payments\n' >internal/payments/p$i.go; done
git add -A && git commit -qm "add payments"
out="$($C drift)"
contains "$out" "internal/payments: 16 added" "drift groups structural changes"
contains "$out" "internal/worker/run.go" "drift flags dangling paths"
contains "$($C stale)" "run /remap" "stale map detected"
out="$(printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$E" bash .claude/hooks/session-context.sh)"
contains "$out" "run /remap" "session hook surfaces stale map"
[ -f .claude/skills/remap/SKILL.md ] && ok "remap skill installed" || ko "remap skill installed"

if [ "${KIT_TEST_TS:-0}" = 1 ] && command -v pnpm >/dev/null; then
  echo "== check runner: real TypeScript project (pnpm + vitest)"
  T="$WORK/tsproj"; mkdir -p "$T/src"; cd "$T" || exit 1; git init -q
  cat >package.json <<'EOF'
{ "name": "ts-demo", "private": true, "type": "module",
  "scripts": { "typecheck": "tsc --noEmit", "test": "vitest run" },
  "devDependencies": { "typescript": "5.6.3", "vitest": "2.1.8" } }
EOF
  echo '{"compilerOptions":{"strict":true,"module":"ESNext","moduleResolution":"Bundler","target":"ES2022","noEmit":true,"skipLibCheck":true},"include":["src"]}' >tsconfig.json
  echo 'export const add = (a: number, b: number): number => a + b;' >src/add.ts
  printf "import { expect, test } from 'vitest';\nimport { add } from './add';\ntest('adds', () => { expect(add(2, 2)).toBe(5); });\n" >src/add.test.ts
  pnpm install --silent >/dev/null 2>&1
  "$KIT/install.sh" "$T" >/dev/null 2>&1
  out="$(.claude/kit/check.sh all 2>&1)"; rc=$?
  contains "$out" "PASS typecheck" "tsc typecheck passes"
  contains "$out" "FAIL test" "vitest failure detected"
  contains "$out" "expected 4 to be 5" "vitest assertion surfaced"
  printf '%s\n' "$out" | sed 's/^/       | /'
fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
