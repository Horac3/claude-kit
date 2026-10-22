#!/usr/bin/env bash
# claude-kit installer and updater.
#
#   ./install.sh [--stack go|ts|both|auto] [--frontend] [--dry-run] [TARGET_DIR]   first install (default: .)
#   ./install.sh --update [--frontend] [--dry-run] [TARGET_DIR]                    pull a newer kit into a project
#
# --frontend adds the frontend layer (frontend rule, /ui, ui-checker, shot.mjs, design-pack.sh) to any stack, e.g. a
# Go service rendering HTML templates. ts and both stacks always have it. It is recorded, so --update keeps it.
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
# How this run was started: git (a clone of the repo), go (go install / release binary) or npm (npx @horac3/claude-kit).
# The claude-kit binary sets it; it is recorded in the manifest so the update hint matches the route.
KIT_VIA="${CLAUDE_KIT_VIA:-git}"
case "$KIT_VIA" in git | go | npm) ;; *) KIT_VIA=git ;; esac

stack="auto" mode="install" dry=0 frontend=0 target="."
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) stack="${2:-}"; shift 2 ;;
    --stack=*) stack="${1#*=}"; shift ;;
    --update) mode="update"; shift ;;
    --dry-run) dry=1; shift ;;
    --frontend) frontend=1; shift ;;
    -h | --help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) target="$1"; shift ;;
  esac
done

[ -d "$target" ] || { echo "target directory not found: $target" >&2; exit 1; }
target="$(cd "$target" && pwd)"
[ "$target" = "$KIT_DIR" ] && { echo "refusing to install the kit into itself" >&2; exit 1; }

manifest="$target/.claude/kit/manifest"

# ---------- helpers ----------
update_hint() {
  case "$KIT_VIA" in
    npm) echo "npx @horac3/claude-kit@latest update" ;;
    go) echo "go install github.com/horac3/claude-kit/cmd/claude-kit@latest && claude-kit update" ;;
    *) echo "git -C \"$KIT_DIR\" pull && \"$KIT_DIR/install.sh\" --update" ;;
  esac
}
# Hash from stdin: with a filename, GNU sha256sum prefixes "\" when the path has a backslash (Windows paths).
if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum <"$1" | cut -c1-16; }
else
  hash_file() { shasum -a 256 <"$1" | cut -c1-16; }
fi
recorded() { # recorded <kind> <rel> -> hash from the previous manifest
  [ -f "$manifest" ] || return 0
  awk -F '\t' -v k="$1" -v p="$2" '$1 == k && $3 == p {print $2; exit}' "$manifest"
}
same_hash() { # same_hash <hash> <recorded> -> also accepts the legacy "\"+15 hex form (pre-1.5.0, Windows)
  [ "$1" = "$2" ] && return 0
  case "$2" in "\\"?*) [ "$(printf '%s' "$1" | cut -c1-15)" = "${2#?}" ] ;; *) return 1 ;; esac
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
  if [ -n "$rec" ] && same_hash "$cur" "$rec"; then
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
  elif ! same_hash "$new" "$rec"; then
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
[ "$mode" = "update" ] && [ "$(meta frontend)" = 1 ] && frontend=1
[ "$stack" != go ] && frontend=1   # ts and both stacks always get the frontend layer

# The frontend part of the TypeScript stack, installable on its own with --frontend.
is_frontend_file() {
  case "$1" in
    .claude/rules/kit/frontend.md | .claude/skills/ui/* | .claude/agents/ui-checker.md | \
      .claude/kit/shot.mjs | .claude/kit/design-pack.sh) return 0 ;;
  esac
  return 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT   # only the installer's own temp dir

# ---------- generated project files ----------
script_in() { # script_in <package.json> <name>: the file's "scripts" block defines <name>
  [ -f "$1" ] && sed -n '/"scripts"[[:space:]]*:/,/}/p' "$1" | grep -Eq "\"$2\"[[:space:]]*:"
}
has_script() { script_in "$target/package.json" "$1"; }
pkg_has_script() { # a workspace package (not the root) defines the script
  local f
  while IFS= read -r f; do
    script_in "$f" "$1" && return 0
  done < <(find "$target" -mindepth 2 -maxdepth 5 \( -name node_modules -o -name .git \) -prune -o -name package.json -print 2>/dev/null)
  return 1
}
at_root() { # at_root <script> [args]: the root package's script
  local s="$1"; shift
  case "$pm" in npm) echo "npm run $s${1:+ -- $*}" ;; *) echo "$pm run $s${1:+ $*}" ;; esac
}
recursive() { # recursive <script> [args]: the script in every workspace package that has it
  local s="$1"; shift
  case "$pm" in
    pnpm) echo "pnpm -r --if-present run $s${1:+ $*}" ;;
    npm)  echo "npm run $s --workspaces --if-present${1:+ -- $*}" ;;
    yarn) if [ -f "$target/.yarnrc.yml" ]; then echo "yarn workspaces foreach -A run $s${1:+ $*}"
          else echo "yarn workspaces run $s${1:+ $*}"; fi ;;
    bun)  echo "bun run --filter '*' $s${1:+ $*}" ;;
  esac
}
ws_script() { # ws_script <script>: prefer the root script (pnpm -r skips the root), else recurse, else nothing
  if has_script "$1"; then at_root "$1"; elif pkg_has_script "$1"; then recursive "$1"; fi
}
and_then() { if [ -n "$2" ]; then echo "($1) && ($2)"; else echo "$1"; fi; }

gen_commands() {
  local go_tc="go build ./... && go vet ./..."
  local go_lint='if command -v golangci-lint >/dev/null 2>&1; then golangci-lint run ./...; else out="$(gofmt -l .)"; if [ -n "$out" ]; then echo "gofmt needed:"; echo "$out"; exit 1; fi; fi'
  local go_test="go test ./..."
  local go_one='go test ./... -run "$1"'
  local go_fmt='gofmt -l .'
  local run exec ws=0 ts_tc ts_lint ts_test ts_one ts_fmt
  case "$pm" in
    pnpm) exec="pnpm exec"; run="pnpm run --if-present"; [ -f "$target/pnpm-workspace.yaml" ] && ws=1 ;;
    npm)  exec="npx --no-install"; run="npm run --if-present" ;;
    yarn) exec="yarn"; run="yarn run" ;;
    bun)  exec="bunx"; run="bun run" ;;
  esac
  [ "$pm" != pnpm ] && grep -q '"workspaces"[[:space:]]*:' "$target/package.json" 2>/dev/null && ws=1
  if [ $ws -eq 1 ]; then
    # Workspace: a value stays empty (SKIP) when neither the root nor any package defines the script.
    ts_tc="$(ws_script typecheck)"; ts_lint="$(ws_script lint)"; ts_test="$(ws_script test)"
    # vitest is rarely installed at a workspace root: pass the filter to each package's test script instead.
    if pkg_has_script test; then ts_one="$(recursive test '-t "$1"')"
    elif has_script test; then ts_one="$(at_root test '-t "$1"')"
    else ts_one=""; fi
  else
    if has_script typecheck; then ts_tc="$run typecheck"; else ts_tc="$exec tsc --noEmit"; fi
    if has_script lint; then ts_lint="$run lint"; else ts_lint=""; fi
    if has_script test; then ts_test="$run test"; else ts_test="$exec vitest run"; fi
    ts_one="$exec vitest run -t \"\$1\""
  fi
  ts_fmt="$exec prettier --check ."

  local tc lint test one fmt
  case "$stack" in
    go)   tc="$go_tc"; lint="$go_lint"; test="$go_test"; one="$go_one"; fmt="$go_fmt" ;;
    ts)   tc="$ts_tc"; lint="$ts_lint"; test="$ts_test"; one="$ts_one"; fmt="$ts_fmt" ;;
    both) tc="$(and_then "$go_tc" "$ts_tc")"; lint="$(and_then "$go_lint" "$ts_lint")"
          test="$(and_then "$go_test" "$ts_test")"; one="($go_one)${ts_one:+; ($ts_one)}"
          fmt="$(and_then "$go_fmt" "$ts_fmt")" ;;
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
    "Bash(.claude/kit/context.sh *)" "Bash(bash .claude/kit/context.sh *)"
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
  if [ "$frontend" -eq 1 ]; then
    allow+=("Bash(node .claude/kit/shot.mjs *)" "Bash(npx -y impeccable detect *)" "Bash(npx impeccable detect *)"
      "Bash(.claude/kit/design-pack.sh)" "Bash(.claude/kit/design-pack.sh --list)")
    [ "$stack" = go ] && ask+=("Bash(npx *)")
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
echo "claude-kit $KIT_VERSION → $target  (mode: $mode, stack: $stack$( [ "$stack" != go ] && printf ', pm: %s' "$pm")$( [ "$stack" = go ] && [ "$frontend" -eq 1 ] && printf ' + frontend'))"
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
if [ "$stack" = go ] && [ "$frontend" -eq 1 ]; then
  while IFS= read -r -d '' f; do
    rel="${f#"$KIT_DIR/stacks/ts/"}"
    if is_frontend_file "$rel"; then install_kit_file "$f" "$rel"; fi
  done < <(find "$KIT_DIR/stacks/ts" -type f -print0 | sort -z)
fi

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

append_line() { # append_line <file> <line>: append-only, skips lines already present
  local f="$1" line="$2"
  [ -f "$f" ] && grep -qxF "$line" "$f" && return 1
  if [ "$dry" -eq 0 ]; then
    [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ] && printf '\n' >>"$f"   # file lacks a final newline
    printf '%s\n' "$line" >>"$f"
  fi
  return 0
}

# .gitignore: append-only
for line in ".claude/settings.local.json" ".claude/kit/logs/" "CLAUDE.local.md" "*.kit-new"; do
  append_line "$target/.gitignore" "$line" && note "  ignore   $line  (.gitignore)"
done

# .gitattributes: append-only. Hooks checked out with CRLF (core.autocrlf on Windows) crash under
# Linux/WSL bash and exit 0, which silently disables the guards.
for line in ".claude/**/*.sh text eol=lf" ".claude/kit/commands.env text eol=lf"; do
  append_line "$target/.gitattributes" "$line" && note "  eol=lf   ${line%% *}  (.gitattributes)"
done

# manifest (the kit's own bookkeeping file)
if [ "$dry" -eq 0 ]; then
  mkdir -p "$(dirname "$manifest")"
  {
    echo "# claude-kit manifest: written by install.sh, used by --update. Do not edit."
    echo "version=$KIT_VERSION"
    echo "stack=$stack"
    echo "pm=$pm"
    echo "frontend=$frontend"
    echo "via=$KIT_VIA"
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
Update later with: $(update_hint)
EOF
fi
