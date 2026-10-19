#!/usr/bin/env bash
# claude-kit installer and updater.
#
#   ./install.sh [--stack go|ts|both|auto] [--dry-run] [TARGET_DIR]    first install (default target: .)
#   ./install.sh --update [--dry-run] [TARGET_DIR]                     pull a newer kit into a project
#
# Two kinds of files:
#   kit files      (.claude/skills, agents, hooks, rules/kit, kit/*.sh) belong to the kit. On --update they are
#                  replaced only if you have not modified them; otherwise the new version lands next to yours as
#                  <file>.kit-new for you to merge.
#   project files  (CLAUDE.md, docs/*, .claude/settings.json, .claude/kit/commands.env) belong to the project.
#                  They are created once and never overwritten. If the kit's template changes, you get
#                  <file>.kit-new to compare against.
# The installer never deletes anything. Files the kit no longer ships are reported, not removed.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_VERSION="$(tr -d '[:space:]' <"$KIT_DIR/VERSION")"

stack="auto" mode="install" dry=0 target="."
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) stack="${2:-}"; shift 2 ;;
    --stack=*) stack="${1#*=}"; shift ;;
    --update) mode="update"; shift ;;
    --dry-run) dry=1; shift ;;
    -h | --help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) target="$1"; shift ;;
  esac
done

[ -d "$target" ] || { echo "target directory not found: $target" >&2; exit 1; }
target="$(cd "$target" && pwd)"
[ "$target" = "$KIT_DIR" ] && { echo "refusing to install the kit into itself" >&2; exit 1; }

manifest="$target/.claude/kit/manifest"

# ---------- helpers ----------
if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | cut -c1-16; }
else
  hash_file() { shasum -a 256 "$1" | cut -c1-16; }
fi
recorded() { # recorded <kind> <rel> -> hash from the previous manifest
  [ -f "$manifest" ] || return 0
  awk -F '\t' -v k="$1" -v p="$2" '$1 == k && $3 == p {print $2; exit}' "$manifest"
}
meta() { [ -f "$manifest" ] && sed -n "s/^$1=//p" "$manifest" | head -n 1 || true; }

declare -a NEW_MANIFEST=() REPORT=()
counts_add=0 counts_upd=0 counts_same=0 counts_conf=0 counts_keep=0
note() { REPORT+=("$1"); }
put() { # put <src> <dst>
  if [ "$dry" -eq 1 ]; then return 0; fi
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
  case "$2" in *.sh) chmod +x "$2" ;; esac
}

install_kit_file() { # <src> <rel>
  local src="$1" rel="$2" dst="$target/$2" new cur rec
  new="$(hash_file "$src")"
  NEW_MANIFEST+=("kit	$new	$rel")
  if [ ! -e "$dst" ]; then
    put "$src" "$dst"; counts_add=$((counts_add + 1)); note "  add      $rel"; return
  fi
  cur="$(hash_file "$dst")"
  if [ "$cur" = "$new" ]; then counts_same=$((counts_same + 1)); return; fi
  rec="$(recorded kit "$rel")"
  if [ -n "$rec" ] && [ "$cur" = "$rec" ]; then
    put "$src" "$dst"; counts_upd=$((counts_upd + 1)); note "  update   $rel"
  else
    put "$src" "$dst.kit-new"; counts_conf=$((counts_conf + 1))
    note "  MERGE    $rel  (yours is modified; new version at $rel.kit-new)"
  fi
}

install_project_file() { # <generated src> <rel>
  local src="$1" rel="$2" dst="$target/$2" new rec
  new="$(hash_file "$src")"
  NEW_MANIFEST+=("proj	$new	$rel")
  if [ ! -e "$dst" ]; then
    put "$src" "$dst"; counts_add=$((counts_add + 1)); note "  add      $rel"; return
  fi
  if [ "$(hash_file "$dst")" = "$new" ]; then counts_same=$((counts_same + 1)); return; fi
  rec="$(recorded proj "$rel")"
  if [ "$mode" = "install" ] && [ -z "$rec" ]; then
    put "$src" "$dst.kit-new"; counts_keep=$((counts_keep + 1))
    note "  keep     $rel  (exists; kit template at $rel.kit-new for reference)"
  elif [ "$rec" != "$new" ]; then
    put "$src" "$dst.kit-new"; counts_keep=$((counts_keep + 1))
    note "  keep     $rel  (kit template changed; compare with $rel.kit-new)"
  else
    counts_keep=$((counts_keep + 1))
  fi
}

# ---------- stack and package manager ----------
if [ "$mode" = "update" ] && [ "$stack" = "auto" ]; then
  prev="$(meta stack)"; [ -n "$prev" ] && stack="$prev"
fi
has_go=0 has_ts=0
[ -f "$target/go.mod" ] || [ -f "$target/go.work" ] && has_go=1
[ -f "$target/package.json" ] && has_ts=1
if [ "$stack" = "auto" ]; then
  if [ $has_go -eq 1 ] && [ $has_ts -eq 1 ]; then stack=both
  elif [ $has_go -eq 1 ]; then stack=go
  elif [ $has_ts -eq 1 ]; then stack=ts
  else
    echo "Could not detect the stack (no go.mod or package.json). Re-run with --stack go|ts|both." >&2
    exit 1
  fi
fi
case "$stack" in go | ts | both) ;; *) echo "--stack must be go, ts, both or auto" >&2; exit 2 ;; esac

pm=pnpm
if [ -f "$target/pnpm-lock.yaml" ] || [ -f "$target/pnpm-workspace.yaml" ]; then pm=pnpm
elif [ -f "$target/bun.lock" ] || [ -f "$target/bun.lockb" ]; then pm=bun
elif [ -f "$target/yarn.lock" ]; then pm=yarn
elif [ -f "$target/package-lock.json" ]; then pm=npm
fi
[ "$mode" = "update" ] && [ -n "$(meta pm)" ] && pm="$(meta pm)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT   # only the installer's own temp dir

# ---------- generated project files ----------
has_script() { [ -f "$target/package.json" ] && grep -Eq "\"$1\"[[:space:]]*:" "$target/package.json"; }

gen_commands() {
  local go_tc="go build ./... && go vet ./..."
  local go_lint='if command -v golangci-lint >/dev/null 2>&1; then golangci-lint run ./...; else out="$(gofmt -l .)"; if [ -n "$out" ]; then echo "gofmt needed:"; echo "$out"; exit 1; fi; fi'
  local go_test="go test ./..."
  local go_one='go test ./... -run "$1"'
  local go_fmt='gofmt -l .'
  local run exec ws=0 ts_tc ts_lint ts_test ts_one ts_fmt
  case "$pm" in
    pnpm) exec="pnpm exec"; [ -f "$target/pnpm-workspace.yaml" ] && ws=1
          if [ $ws -eq 1 ]; then run="pnpm -r --if-present run"; else run="pnpm run --if-present"; fi ;;
    npm)  exec="npx --no-install"; run="npm run --if-present" ;;
    yarn) exec="yarn"; run="yarn run" ;;
    bun)  exec="bunx"; run="bun run" ;;
  esac
  if [ $ws -eq 1 ] || has_script typecheck; then ts_tc="$run typecheck"; else ts_tc="$exec tsc --noEmit"; fi
  if [ $ws -eq 1 ] || has_script lint; then ts_lint="$run lint"; else ts_lint=""; fi
  if [ $ws -eq 1 ] || has_script test; then ts_test="$run test"; else ts_test="$exec vitest run"; fi
  ts_one="$exec vitest run -t \"\$1\""
  ts_fmt="$exec prettier --check ."

  local tc lint test one fmt
  case "$stack" in
    go)   tc="$go_tc"; lint="$go_lint"; test="$go_test"; one="$go_one"; fmt="$go_fmt" ;;
    ts)   tc="$ts_tc"; lint="$ts_lint"; test="$ts_test"; one="$ts_one"; fmt="$ts_fmt" ;;
    both) tc="($go_tc) && ($ts_tc)"; lint="($go_lint)${ts_lint:+ && ($ts_lint)}"
          test="($go_test) && ($ts_test)"; one="($go_one); ($ts_one)"; fmt="($go_fmt) && ($ts_fmt)" ;;
  esac
  q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
  cat <<EOF
# claude-kit check commands (project-owned: edit freely; /kickoff verifies them).
# Read by .claude/kit/check.sh. Each value runs with bash -c; in CHECK_TEST_ONE, \$1 is the pattern.
# Leave a value empty to skip that target.
# Stack: $stack$( [ "$stack" != go ] && printf ' · package manager: %s' "$pm")
EOF
  echo "CHECK_TYPECHECK=$(q "$tc")"
  echo "CHECK_LINT=$(q "$lint")"
  if [ "$stack" != ts ]; then
    echo "# go test -race needs cgo and a C compiler: run it in CI or Docker, not here."
  fi
  echo "CHECK_TEST=$(q "$test")"
  echo "CHECK_TEST_ONE=$(q "$one")"
  echo "CHECK_FORMAT=$(q "$fmt")"
  echo "# Max failure lines shown to Claude per target (full log always in .claude/kit/logs/)."
  echo "CHECK_MAX_LINES=60"
}

json_items() { # json_items <indent> items... -> "a",\n"b"
  local ind="$1"; shift
  local first=1 it
  for it in "$@"; do
    [ $first -eq 1 ] || printf ',\n'
    printf '%s"%s"' "$ind" "$it"; first=0
  done
}

gen_settings() {
  local -a allow=(
    "Bash(.claude/kit/check.sh)" "Bash(.claude/kit/check.sh *)"
    "Bash(bash .claude/kit/check.sh *)" "Bash(./.claude/kit/check.sh *)"
    "Bash(git status)" "Bash(git status *)" "Bash(git diff)" "Bash(git diff *)"
    "Bash(git log *)" "Bash(git show *)" "Bash(git branch --show-current)"
    "Bash(git ls-files *)" "Bash(git rev-parse *)" "Bash(git blame *)"
  )
  local -a ask=(
    "Bash(git add *)" "Bash(git commit *)" "Bash(git push *)" "Bash(git rebase *)" "Bash(git merge *)"
    "Bash(git cherry-pick *)" "Bash(git switch *)" "Bash(git checkout *)" "Bash(docker *)" "Bash(docker-compose *)"
  )
  local -a deny=(
    "Bash(rm *)" "Bash(rmdir *)" "Bash(unlink *)" "Bash(shred *)"
    "Bash(git rm *)" "Bash(git clean *)" "Bash(git reset --hard *)" "Bash(git checkout -- *)"
    "Bash(git restore *)" "Bash(git push --force *)" "Bash(git push -f *)"
    "Bash(git branch -D *)" "Bash(git stash drop *)" "Bash(git stash clear *)"
    "Bash(find * -delete *)" "Read(./.env)" "Read(./.env.*)" "Read(**/.env)"
  )
  if [ "$stack" != ts ]; then
    allow+=("Bash(go build *)" "Bash(go vet *)" "Bash(go test *)" "Bash(go list *)" "Bash(go env *)"
      "Bash(go version)" "Bash(go doc *)" "Bash(gofmt -l *)" "Bash(golangci-lint run *)")
    ask+=("Bash(go get *)" "Bash(go mod *)" "Bash(go install *)" "Bash(go generate *)" "Bash(go run *)" "Bash(gofmt -w *)")
  fi
  if [ "$stack" != go ]; then
    local x
    case "$pm" in pnpm) x="pnpm exec" ;; npm) x="npx" ;; yarn) x="yarn" ;; bun) x="bunx" ;; esac
    allow+=("Bash($x tsc --noEmit *)" "Bash($x vitest run *)" "Bash($pm ls *)" "Bash($pm why *)")
    ask+=("Bash($pm add *)" "Bash($pm install *)" "Bash($pm remove *)" "Bash($pm update *)"
      "Bash($pm run *)" "Bash($pm dlx *)" "Bash(npx *)" "Bash($x prettier --write *)")
  fi
  cat <<EOF
{
  "\$schema": "https://json.schemastore.org/claude-code-settings.json",
  "model": "opusplan",
  "permissions": {
    "allow": [
$(json_items '      ' "${allow[@]}")
    ],
    "ask": [
$(json_items '      ' "${ask[@]}")
    ],
    "deny": [
$(json_items '      ' "${deny[@]}")
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/guard-bash.sh\"" }]
      },
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [{ "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/guard-files.sh\"" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/session-context.sh\"" }]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "bash \"\${CLAUDE_PROJECT_DIR:-.}/.claude/kit/statusline.sh\""
  }
}
EOF
}

# ---------- run ----------
echo "claude-kit $KIT_VERSION → $target  (mode: $mode, stack: $stack$( [ "$stack" != go ] && printf ', pm: %s' "$pm"))"
[ "$dry" -eq 1 ] && echo "(dry run: nothing will be written)"
if [ "$mode" = "update" ] && [ ! -f "$manifest" ]; then
  echo "No manifest at .claude/kit/manifest: this looks like a first install. Run without --update." >&2
  exit 1
fi

# kit files: common + stack rules
while IFS= read -r -d '' f; do
  install_kit_file "$f" "${f#"$KIT_DIR/kit/"}"
done < <(find "$KIT_DIR/kit" -type f -print0 | sort -z)
for s in go ts; do
  if [ "$stack" = "$s" ] || [ "$stack" = both ]; then
    while IFS= read -r -d '' f; do
      install_kit_file "$f" "${f#"$KIT_DIR/stacks/$s/"}"
    done < <(find "$KIT_DIR/stacks/$s" -type f -print0 | sort -z)
  fi
done

# project files
for f in CLAUDE.md docs/progress.md docs/decisions.md docs/requirements.md; do
  install_project_file "$KIT_DIR/scaffold/$f" "$f"
done
gen_settings >"$tmp/settings.json";   install_project_file "$tmp/settings.json" ".claude/settings.json"
gen_commands >"$tmp/commands.env";    install_project_file "$tmp/commands.env" ".claude/kit/commands.env"

# files the kit used to ship but no longer does: report only
if [ -f "$manifest" ]; then
  while IFS=$'\t' read -r kind _ rel; do
    case "$kind" in kit | proj) ;; *) continue ;; esac
    found=0
    for e in "${NEW_MANIFEST[@]}"; do [ "${e##*	}" = "$rel" ] && { found=1; break; }; done
    [ $found -eq 0 ] && note "  obsolete $rel  (no longer shipped; remove it yourself if unused)"
  done <"$manifest"
fi

# .gitignore: append-only
gi="$target/.gitignore"
for line in ".claude/settings.local.json" ".claude/kit/logs/" "CLAUDE.local.md" "*.kit-new"; do
  if ! { [ -f "$gi" ] && grep -qxF "$line" "$gi"; }; then
    [ "$dry" -eq 1 ] || printf '%s\n' "$line" >>"$gi"
    note "  ignore   $line  (.gitignore)"
  fi
done

# manifest (the kit's own bookkeeping file)
if [ "$dry" -eq 0 ]; then
  mkdir -p "$(dirname "$manifest")"
  {
    echo "# claude-kit manifest: written by install.sh, used by --update. Do not edit."
    echo "version=$KIT_VERSION"
    echo "stack=$stack"
    echo "pm=$pm"
    printf '%s\n' "${NEW_MANIFEST[@]}"
  } >"$manifest"
fi

[ ${#REPORT[@]} -gt 0 ] && printf '%s\n' "${REPORT[@]}"
echo "done: $counts_add added, $counts_upd updated, $counts_same unchanged, $counts_keep project files kept, $counts_conf to merge"
if [ "$counts_conf" -gt 0 ] || ls "$target"/*.kit-new "$target"/.claude/*.kit-new "$target"/docs/*.kit-new >/dev/null 2>&1; then
  echo "Review the *.kit-new files, merge what you want, then delete them yourself."
fi
if [ "$mode" = "install" ]; then
  cat <<EOF

Next:
  1. command -v jq || install jq (optional; hooks fall back to python3/node)
  2. cd "$target" && claude
  3. Run /kickoff  (maps the code, fills CLAUDE.md, verifies .claude/kit/commands.env, drafts the roadmap)
  4. /clear, then /next — one roadmap step per conversation.
EOF
fi
