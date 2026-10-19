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
# Empty command list: "${arr[@]}" on an empty array is an unbound-variable error under set -u in bash < 4.4.
expect_exit 0 "design pack with nothing to run (empty arrays, bash 3.2)" .claude/kit/design-pack.sh shadcn

echo "== design pack: licence notices"
D="$WORK/dpack"; mkdir -p "$D"; cd "$D" || exit 1
git init -q -b main && git config user.email t@t && git config user.name t
echo '{"name":"x","scripts":{"test":"vitest run"}}' >package.json
"$KIT/install.sh" "$D" >/dev/null 2>&1
git add -A && git commit -qm init
# Fake npx/claude: create the skill folders an install would copy, with no network.
FB="$WORK/fakebin"; mkdir -p "$FB"
cat >"$FB/npx" <<'EOF'
#!/bin/sh
mk() {
  mkdir -p ".claude/skills/$1"; echo "# $1" >".claude/skills/$1/SKILL.md"
  if [ -n "${FAKE_UPSTREAM_LICENSE:-}" ] && [ ! -f ".claude/skills/$1/LICENSE" ]; then
    echo "upstream-provided" >".claude/skills/$1/LICENSE"
  fi
}
skills=0
for a in "$@"; do
  case "$a" in
    impeccable) mk impeccable; mkdir -p .claude/agents; echo "# agent" >.claude/agents/impeccable-documenter.md ;;
    --skill) skills=1 ;;
    -*) skills=0 ;;
    *) if [ "$skills" = 1 ]; then mk "$a"; fi ;;
  esac
done
if [ -n "${FAKE_AGENT:-}" ]; then mkdir -p .claude/agents; echo "# agent" >".claude/agents/$FAKE_AGENT.md"; fi
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' >"$FB/claude"
chmod +x "$FB/npx" "$FB/claude"
FX="$WORK/licfx"   # <owner>__<repo>/<file>, as KIT_LICENSE_FIXTURES expects
mkdir -p "$FX/pbakaus__impeccable" "$FX/vercel-labs__agent-skills" "$FX/Leonxlnx__taste-skill"
printf '                                 Apache License\n                           Version 2.0, January 2004\n\n   Copyright [yyyy] [name of copyright owner]\n' >"$FX/pbakaus__impeccable/LICENSE"
printf 'Impeccable\nCopyright 2025 Paul Bakaus\n' >"$FX/pbakaus__impeccable/NOTICE"
printf 'MIT License\n\nCopyright (c) 2025 Vercel, Inc.\n\nPermission is hereby granted, free of charge, to any person\n' >"$FX/vercel-labs__agent-skills/LICENSE"
printf 'Custom terms: be nice.\n' >"$FX/Leonxlnx__taste-skill/LICENSE"
# emilkowalski__skills is deliberately missing: its fetch must fail.
dp() { PATH="$FB:$PATH" CLAUDE_PROJECT_DIR="$D" KIT_LICENSE_FIXTURES="${FXDIR:-$FX}" .claude/kit/design-pack.sh "$@" 2>&1; }
TPN="$D/THIRD_PARTY_NOTICES.md"
lic_entries() { grep -c "<!-- skill:$1 -->" "$TPN"; }

out="$(dp core)"
contains "$out" "THIRD_PARTY_NOTICES.md" "dry run mentions licence notices"
[ ! -e "$TPN" ] && [ ! -d .claude/skills/impeccable ] && [ -z "$(git status --porcelain)" ] &&
  ok "dry run writes nothing" || ko "dry run writes nothing" "$(git status --porcelain)"

out="$(dp core --apply)"; rc=$?
[ $rc -eq 0 ] && ok "core --apply exits 0 with all licences fetched" || ko "core --apply exits 0" "$out"
grep -q "Apache License" .claude/skills/impeccable/LICENSE 2>/dev/null && ok "copied skill gets upstream LICENSE" || ko "copied skill gets LICENSE"
grep -q "Paul Bakaus" .claude/skills/impeccable/NOTICE 2>/dev/null && ok "Apache skill also gets NOTICE" || ko "Apache skill gets NOTICE"
[ ! -e .claude/skills/web-design-guidelines/NOTICE ] && ok "MIT skill gets no NOTICE" || ko "MIT skill gets no NOTICE"
[ "$(grep -cxF '<!-- claude-kit:third-party:start -->' "$TPN" 2>/dev/null)" = 1 ] &&
  [ "$(grep -cxF '<!-- claude-kit:third-party:end -->' "$TPN")" = 1 ] &&
  ok "THIRD_PARTY_NOTICES.md created with one marker block" || ko "notices marker block" "$(cat "$TPN" 2>/dev/null)"
grep "<!-- skill:web-design-guidelines -->" "$TPN" | grep -q "MIT.*Copyright (c) 2025 Vercel, Inc." &&
  ok "SPDX: MIT fixture detected, copyright line recorded" || ko "SPDX MIT" "$(cat "$TPN")"
grep "<!-- skill:impeccable -->" "$TPN" | grep -q "Apache-2.0" && ok "SPDX: Apache fixture detected" || ko "SPDX Apache" "$(cat "$TPN")"
grep "<!-- skill:impeccable -->" "$TPN" | grep -q "yyyy" && ko "Apache template copyright line skipped" || ok "Apache template copyright line skipped"
grep -q "frontend-design" "$TPN" && grep -q "Used at runtime, not redistributed" "$TPN" &&
  ok "notices cover runtime tools and the proprietary plugin" || ko "notices runtime + plugin" "$(cat "$TPN")"
contains "$out" "THIRD_PARTY_NOTICES.md" "closing message says to commit the notices"
grep "<!-- agent:impeccable-documenter -->" "$TPN" | grep -q 'Apache-2.0.*licence text in `.claude/skills/impeccable/LICENSE`' &&
  ok "copied agent points to its upstream's LICENSE copy" || ko "agent entry" "$(cat "$TPN")"
git add -A && git commit -qm "core pack"

out="$(dp taste --apply)"
grep "<!-- skill:design-taste-frontend -->" "$TPN" | grep -q "unknown — check https://github.com/Leonxlnx/taste-skill" &&
  ok "SPDX: unrecognised licence text is unknown" || ko "SPDX unknown" "$(cat "$TPN")"
git add -A && git commit -qm "taste pack"
# A command that adds only an agent (its skill already exists) fetches one licence copy next to the agents.
out="$(FAKE_AGENT=lonely-agent dp taste --apply)"
grep -q "Custom terms" .claude/agents/LICENSE-Leonxlnx-taste-skill 2>/dev/null &&
  grep "<!-- agent:lonely-agent -->" "$TPN" | grep -q 'licence text in `.claude/agents/LICENSE-Leonxlnx-taste-skill`' &&
  ok "agent without a sibling skill gets its own licence copy" || ko "agent-only licence copy" "$(cat "$TPN")"
git add -A && git commit -qm "lonely agent"

# Re-install one skill: it is new again, so its entry is rewritten in place, and an upstream LICENSE is kept.
rm -rf .claude/skills/web-design-guidelines; git add -A && git commit -qm "drop wdg"
out="$(FAKE_UPSTREAM_LICENSE=1 dp core --apply)"
[ "$(cat .claude/skills/web-design-guidelines/LICENSE)" = "upstream-provided" ] &&
  ok "existing LICENSE in a skill is not overwritten" || ko "existing LICENSE kept" "$out"
[ "$(lic_entries web-design-guidelines)" = 1 ] && [ "$(lic_entries impeccable)" = 1 ] && [ "$(lic_entries design-taste-frontend)" = 1 ] &&
  ok "re-running keeps exactly one entry per skill" || ko "one entry per skill" "$(cat "$TPN")"
grep "<!-- skill:web-design-guidelines -->" "$TPN" | grep -q "unknown" && ok "re-installed skill's entry updated in place" || ko "entry updated in place" "$(cat "$TPN")"
git add -A && git commit -qm "core again"

# A failed fetch warns, records "add manually", exits non-zero, and does not stop the other skills.
rm -rf .claude/skills/web-design-guidelines; git add -A && git commit -qm "drop wdg again"
out="$(dp core motion --apply)"; rc=$?
[ $rc -ne 0 ] && ok "missing licence makes the run exit non-zero" || ko "missing licence exits non-zero" "$out"
contains "$out" "emilkowalski/skills" "missing licence warning names the repo"
grep "<!-- skill:emil-design-eng -->" "$TPN" | grep -q "licence not fetched — add manually" &&
  ok "missing licence recorded as add manually" || ko "add manually entry" "$(cat "$TPN")"
[ ! -e .claude/skills/emil-design-eng/LICENSE ] && ok "nothing written when the fetch fails" || ko "no LICENSE on failed fetch"
grep -q "MIT License" .claude/skills/web-design-guidelines/LICENSE 2>/dev/null && ok "other skills still processed" || ko "other skills still processed" "$out"
git add -A && git commit -qm "motion pack"

# Content outside the markers is preserved byte for byte (including a missing final newline).
{ printf 'Hand-written intro.\n\n'; cat "$TPN"; printf '\nHand-written footer, no final newline'; } >"$TPN.tmp" && mv "$TPN.tmp" "$TPN"
git add -A && git commit -qm "hand edits"
IFS= read -r -d '' before <"$TPN"
out="$(dp devtools --apply)"
IFS= read -r -d '' after <"$TPN"
S='<!-- claude-kit:third-party:start -->' E='<!-- claude-kit:third-party:end -->'
[ "${before%%"$S"*}" = "${after%%"$S"*}" ] && [ "${before#*"$E"}" = "${after#*"$E"}" ] &&
  ok "content outside the markers preserved byte for byte" || ko "outside content preserved" "$(cat "$TPN")"
grep -q "<!-- mcp:chrome-devtools -->" "$TPN" && ok "configured MCP server listed as runtime-only" || ko "MCP runtime entry" "$(cat "$TPN")"
git add -A && git commit -qm "devtools"

# An existing notices file without markers gets the block appended; its content stays first, unchanged.
printf '# Notices\n\nleft-pad: MIT' >"$TPN"; git add -A && git commit -qm "own notices"
out="$(dp devtools --apply)"
IFS= read -r -d '' after <"$TPN"
case "$after" in
  "# Notices"$'\n\n'"left-pad: MIT"$'\n'*"$S"*) ok "notices file without markers: block appended" ;;
  *) ko "block appended to unmarked file" "$after" ;;
esac
git add -A && git commit -qm "devtools on own notices"

# Upstream without a LICENSE file (vercel-labs/agent-skills): use the licence its README declares, write no LICENSE.
mkdir -p "$WORK/licfx2/vercel-labs__agent-skills"
printf '# Agent Skills

## License

MIT
' >"$WORK/licfx2/vercel-labs__agent-skills/README.md"
rm -rf .claude/skills/web-design-guidelines; git add -A && git commit -qm "drop wdg for readme"
out="$(FXDIR="$WORK/licfx2" dp core --apply)"; rc=$?
[ $rc -eq 0 ] && grep "<!-- skill:web-design-guidelines -->" "$TPN" | grep -q "MIT (declared in the upstream README" &&
  [ ! -e .claude/skills/web-design-guidelines/LICENSE ] &&
  ok "no upstream LICENSE: README-declared licence recorded, nothing invented" || ko "README licence fallback" "$out"
cd "$WORK" || exit 1

echo "== installer: workspace commands"
W="$WORK/pnpmws"; mkdir -p "$W/packages/a" "$W/packages/b"; cd "$W" || exit 1; git init -q
printf 'packages:\n  - "packages/*"\n' >pnpm-workspace.yaml
printf '{\n  "name": "root",\n  "private": true,\n  "scripts": {\n    "lint": "eslint ."\n  }\n}\n' >package.json
printf '{ "name": "a", "scripts": { "test": "vitest run" } }\n' >packages/a/package.json
printf '{ "name": "b", "devDependencies": { "typecheck": "1.0.0" } }\n' >packages/b/package.json
"$KIT/install.sh" "$W" >/dev/null 2>&1
env_file="$(cat .claude/kit/commands.env)"
contains "$env_file" "CHECK_LINT='pnpm run lint'" "root-only lint runs at the root"
contains "$env_file" "CHECK_TEST='pnpm -r --if-present run test'" "package-only test runs recursively"
contains "$env_file" "CHECK_TYPECHECK=''" "script that exists nowhere is left empty"
contains "$env_file" "CHECK_TEST_ONE='pnpm -r --if-present run test -t \"\$1\"'" "workspace test-one runs through package scripts"
contains "$(.claude/kit/check.sh typecheck 2>&1)" "SKIP typecheck" "empty target shows SKIP"
N="$WORK/npmws"; mkdir -p "$N/packages/a"; cd "$N" || exit 1; git init -q
printf '{ "name": "root", "workspaces": ["packages/*"], "scripts": { "test": "npm test --workspaces" } }\n' >package.json
echo '{}' >package-lock.json
printf '{ "name": "a", "scripts": { "lint": "eslint ." } }\n' >packages/a/package.json
"$KIT/install.sh" "$N" >/dev/null 2>&1
env_file="$(cat .claude/kit/commands.env)"
contains "$env_file" "CHECK_TEST='npm run test'" "npm workspace: root script preferred"
contains "$env_file" "CHECK_LINT='npm run lint --workspaces --if-present'" "npm workspace: package script runs in workspaces"

echo "== check runner: nothing ran"
cd "$W" || exit 1
fake="$WORK/fakebin"; mkdir -p "$fake"
printf '#!/bin/sh\necho "Scope: 2 of 3 workspace projects"\n' >"$fake/pnpm"; chmod +x "$fake/pnpm"
cat >>.claude/kit/commands.env <<'EOF'
CHECK_LINT='pnpm -r --if-present run lint'
CHECK_TEST='echo "No projects matched the filters in /x"'
CHECK_FORMAT='true'
EOF
out="$(PATH="$fake:$PATH" .claude/kit/check.sh lint 2>&1)"
contains "$out" "SKIP lint (nothing ran)" "runner that only prints its scope shows SKIP"
out="$(.claude/kit/check.sh test 2>&1)"
contains "$out" "SKIP test (nothing ran)" "\"No projects matched\" shows SKIP, not PASS"
out="$(.claude/kit/check.sh format 2>&1)"
contains "$out" "PASS format" "silent non-runner command (go vet, gofmt -l) still passes"

echo "== installer: --frontend"
F="$WORK/gohtml"; mkdir -p "$F"; cd "$F" || exit 1; git init -q
printf 'module example.com/web\n\ngo 1.22\n' >go.mod
out="$("$KIT/install.sh" --frontend "$F" 2>&1)"
for f in .claude/rules/kit/frontend.md .claude/skills/ui/SKILL.md .claude/agents/ui-checker.md \
  .claude/kit/shot.mjs .claude/kit/design-pack.sh; do
  [ -f "$f" ] && ok "--frontend installs $f" || ko "--frontend installs $f" "$out"
done
[ ! -f .claude/rules/kit/typescript.md ] && ok "--frontend does not add the TypeScript rule" || ko "--frontend adds no TS rule"
grep -q '^frontend=1' .claude/kit/manifest && ok "manifest records frontend" || ko "manifest records frontend"
grep -qF 'Bash(node .claude/kit/shot.mjs *)' .claude/settings.json && ok "--frontend allows shot.mjs" || ko "--frontend allows shot.mjs"
out="$("$K2/install.sh" --update "$F" 2>&1)"
[ -f .claude/skills/ui/SKILL.md ] && ! printf '%s' "$out" | grep -qE "obsolete .*(ui|shot|frontend|design-pack)" && grep -q '^frontend=1' .claude/kit/manifest &&
  ok "--update keeps the frontend layer" || ko "--update keeps the frontend layer" "$out"

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
elif [ "${KIT_TEST_TS:-0}" = 1 ]; then
  ko "KIT_TEST_TS=1 needs pnpm on PATH"
fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
