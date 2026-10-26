#!/usr/bin/env bash
# claude-kit installer and updater.
#
#   ./install.sh [--stack go|ts|py|both|auto] [--frontend] [--data] [--dry-run] [TARGET_DIR]   first install (default: .)
#      --stack takes one stack or several, comma-separated (go,py). both is go,ts.
#   ./install.sh --update [--frontend] [--data] [--dry-run] [TARGET_DIR]                    pull a newer kit into a project
#
# --frontend adds the frontend layer (frontend rule, /ui, ui-checker, shot.mjs, design-pack.sh) to any stack, e.g. a
# Go service rendering HTML templates. ts and both stacks always have it. It is recorded, so --update keeps it.
# --data adds the data-science layer (data rule, /assumptions, data-pack.sh, docs/data.md). Python projects get it
# automatically when they use a data library (pandas, polars, scikit-learn, …), hold a notebook, or use dbt.
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

stack="auto" mode="install" dry=0 frontend=0 data=0 target="."
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) stack="${2:-}"; shift 2 ;;
    --stack=*) stack="${1#*=}"; shift ;;
    --update) mode="update"; shift ;;
    --dry-run) dry=1; shift ;;
    --frontend) frontend=1; shift ;;
    --data) data=1; shift ;;
    -h | --help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
has_go=0 has_ts=0 has_py=0
[ -f "$target/go.mod" ] || [ -f "$target/go.work" ] && has_go=1
[ -f "$target/package.json" ] && has_ts=1
for f in pyproject.toml setup.py setup.cfg Pipfile environment.yml; do [ -f "$target/$f" ] && has_py=1; done
for f in "$target"/requirements*.txt; do [ -f "$f" ] && has_py=1; done
if [ "$stack" = "auto" ]; then
  stack=""
  [ $has_go -eq 1 ] && stack="go"
  [ $has_ts -eq 1 ] && stack="${stack:+$stack,}ts"
  [ $has_py -eq 1 ] && stack="${stack:+$stack,}py"
  [ "$stack" = "go,ts" ] && stack=both   # the name manifests and messages have always used
  if [ -z "$stack" ]; then
    echo "Could not detect the stack (no go.mod, package.json or Python project file). Re-run with --stack go|ts|py (several: --stack go,py)." >&2
    exit 1
  fi
fi
stacks=",${stack/both/go,ts},"   # membership list, e.g. ",go,py,"
for s in $(printf '%s' "$stack" | tr ',' ' '); do
  case "$s" in go | ts | py | both) ;; *) echo "--stack must be go, ts, py, both or auto (several: comma-separated)" >&2; exit 2 ;; esac
done
has_stack() { case "$stacks" in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# Python runner, from the lockfile: uv, poetry, pdm, pipenv, else the active interpreter (python -m).
py_x="python -m"
if [ -f "$target/uv.lock" ]; then py_x="uv run"
elif [ -f "$target/poetry.lock" ]; then py_x="poetry run"
elif [ -f "$target/pdm.lock" ]; then py_x="pdm run"
elif [ -f "$target/Pipfile" ] || [ -f "$target/Pipfile.lock" ]; then py_x="pipenv run"
fi
py_conf() { grep -qE "$1" "$target/pyproject.toml" 2>/dev/null; }   # py_conf <regex>: pyproject.toml has it
py_deps() { # py_deps <name>: the package is listed in pyproject.toml or a requirements file
  local f
  for f in "$target/pyproject.toml" "$target"/requirements*.txt "$target/Pipfile" "$target/environment.yml"; do
    [ -f "$f" ] && grep -qiE "(^|[^[:alnum:]_.-])$1([^[:alnum:]_.-]|$)" "$f" && return 0
  done
  return 1
}
py_has_ruff() { py_conf '^\[tool\.ruff' || [ -f "$target/ruff.toml" ] || [ -f "$target/.ruff.toml" ] || py_deps ruff; }
py_has_pytest() {
  py_conf '^\[tool\.pytest' || [ -f "$target/pytest.ini" ] || [ -f "$target/conftest.py" ] ||
    [ -d "$target/tests" ] || [ -d "$target/test" ] || py_deps pytest
}

pm=pnpm
if [ -f "$target/pnpm-lock.yaml" ] || [ -f "$target/pnpm-workspace.yaml" ]; then pm=pnpm
elif [ -f "$target/bun.lock" ] || [ -f "$target/bun.lockb" ]; then pm=bun
elif [ -f "$target/yarn.lock" ]; then pm=yarn
elif [ -f "$target/package-lock.json" ]; then pm=npm
fi
[ "$mode" = "update" ] && [ -n "$(meta pm)" ] && pm="$(meta pm)"
[ "$mode" = "update" ] && [ "$(meta frontend)" = 1 ] && frontend=1
has_stack ts && frontend=1   # stacks with TypeScript always get the frontend layer
[ "$mode" = "update" ] && [ "$(meta data)" = 1 ] && data=1
# Python projects that do data work get the data layer: a data library, a notebook, or a dbt project.
if [ "$mode" = "install" ] && has_stack py && [ "$data" -eq 0 ]; then
  for lib in pandas polars numpy scipy scikit-learn sklearn statsmodels duckdb pyspark dbt-core jupyter jupyterlab \
    matplotlib seaborn plotly xgboost lightgbm torch tensorflow; do
    py_deps "$lib" && { data=1; break; }
  done
  if [ "$data" -eq 0 ] && [ -n "$(find "$target" -maxdepth 3 \( -name .git -o -name node_modules -o -name .venv -o -name venv \) -prune \
    -o \( -name '*.ipynb' -o -name dbt_project.yml \) -print 2>/dev/null | head -1)" ]; then data=1; fi
fi

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

  # Python: the runner comes from the lockfile; each tool only when the project configures or depends on it.
  local x="$py_x" py_tc="" py_lint="" py_test="" py_one="" py_fmt=""
  if py_has_ruff; then py_lint="$x ruff check ."; py_fmt="$x ruff format --check ."; fi
  if py_conf '^\[tool\.mypy' || [ -f "$target/mypy.ini" ] || [ -f "$target/.mypy.ini" ] ||
    grep -q '^\[mypy' "$target/setup.cfg" 2>/dev/null; then py_tc="$x mypy ."
  elif py_conf '^\[tool\.pyright' || [ -f "$target/pyrightconfig.json" ]; then py_tc="$x pyright"; fi
  if py_has_pytest; then py_test="$x pytest -q"; py_one="$x pytest -q -k \"\$1\""; fi

  # Combine the selected stacks: each target runs every stack's command (&&); empty ones are skipped.
  local tc="" lint="" test="" one="" fmt="" n=0 s
  join_and() { if [ -z "$1" ]; then echo "$2"; elif [ -z "$2" ]; then echo "$1"; else and_then "$1" "$2"; fi; }
  for s in go ts py; do has_stack "$s" && n=$((n + 1)); done
  pick() { # pick <stack> <target>
    case "$1:$2" in
      go:tc) echo "$go_tc" ;; go:lint) echo "$go_lint" ;; go:test) echo "$go_test" ;; go:one) echo "$go_one" ;; go:fmt) echo "$go_fmt" ;;
      ts:tc) echo "$ts_tc" ;; ts:lint) echo "$ts_lint" ;; ts:test) echo "$ts_test" ;; ts:one) echo "$ts_one" ;; ts:fmt) echo "$ts_fmt" ;;
      py:tc) echo "$py_tc" ;; py:lint) echo "$py_lint" ;; py:test) echo "$py_test" ;; py:one) echo "$py_one" ;; py:fmt) echo "$py_fmt" ;;
    esac
  }
  local o
  for s in go ts py; do
    has_stack "$s" || continue
    tc="$(join_and "$tc" "$(pick "$s" tc)")"; lint="$(join_and "$lint" "$(pick "$s" lint)")"
    test="$(join_and "$test" "$(pick "$s" test)")"; fmt="$(join_and "$fmt" "$(pick "$s" fmt)")"
    o="$(pick "$s" one)"
    [ -z "$o" ] && continue
    if [ $n -eq 1 ]; then one="$o"; else one="${one:+$one; }($o)"; fi
  done
  q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
  cat <<EOF
# claude-kit check commands (project-owned: edit freely; /kickoff verifies them).
# Read by .claude/kit/check.sh. Each value runs with bash -c; in CHECK_TEST_ONE, \$1 is the pattern.
# Leave a value empty to skip that target.
# Stack: $stack$(has_stack ts && printf ' · package manager: %s' "$pm")$(has_stack py && printf ' · python runner: %s' "$py_x")
EOF
  echo "CHECK_TYPECHECK=$(q "$tc")"
  echo "CHECK_LINT=$(q "$lint")"
  if has_stack go; then
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
  if has_stack go; then
    allow+=("Bash(go build *)" "Bash(go vet *)" "Bash(go test *)" "Bash(go list *)" "Bash(go env *)"
      "Bash(go version)" "Bash(go doc *)" "Bash(gofmt -l *)" "Bash(golangci-lint run *)")
    ask+=("Bash(go get *)" "Bash(go mod *)" "Bash(go install *)" "Bash(go generate *)" "Bash(go run *)" "Bash(gofmt -w *)")
  fi
  if has_stack ts; then
    local x
    case "$pm" in pnpm) x="pnpm exec" ;; npm) x="npx" ;; yarn) x="yarn" ;; bun) x="bunx" ;; esac
    allow+=("Bash($x tsc --noEmit *)" "Bash($x vitest run *)" "Bash($pm ls *)" "Bash($pm why *)")
    ask+=("Bash($pm add *)" "Bash($pm install *)" "Bash($pm remove *)" "Bash($pm update *)"
      "Bash($pm run *)" "Bash($pm dlx *)" "Bash(npx *)" "Bash($x prettier --write *)")
  fi
  if [ "$frontend" -eq 1 ]; then
    allow+=("Bash(node .claude/kit/shot.mjs *)" "Bash(npx -y impeccable detect *)" "Bash(npx impeccable detect *)"
      "Bash(.claude/kit/design-pack.sh)" "Bash(.claude/kit/design-pack.sh --list)")
    has_stack ts || ask+=("Bash(npx *)")
  fi
  if [ "$data" -eq 1 ]; then
    allow+=("Bash(.claude/kit/data-pack.sh)" "Bash(.claude/kit/data-pack.sh --list)")
  fi
  if has_stack py; then
    allow+=("Bash($py_x pytest *)" "Bash($py_x ruff check *)" "Bash($py_x ruff format --check *)"
      "Bash($py_x mypy *)" "Bash($py_x pyright *)" "Bash(python --version)" "Bash(python3 --version)")
    case "$py_x" in
      "uv run") ask+=("Bash(uv add *)" "Bash(uv remove *)" "Bash(uv sync *)" "Bash(uv lock *)" "Bash(uv pip *)") ;;
      "poetry run") ask+=("Bash(poetry add *)" "Bash(poetry remove *)" "Bash(poetry install *)" "Bash(poetry lock *)") ;;
      "pdm run") ask+=("Bash(pdm add *)" "Bash(pdm remove *)" "Bash(pdm install *)") ;;
      "pipenv run") ask+=("Bash(pipenv install *)" "Bash(pipenv uninstall *)") ;;
    esac
    ask+=("Bash(pip install *)" "Bash(pip3 install *)" "Bash(python -m pip install *)")
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
echo "claude-kit $KIT_VERSION → $target  (mode: $mode, stack: $stack$(has_stack ts && printf ', pm: %s' "$pm")$(! has_stack ts && [ "$frontend" -eq 1 ] && printf ' + frontend')$([ "$data" -eq 1 ] && printf ' + data'))"
[ "$dry" -eq 1 ] && echo "(dry run: nothing will be written)"
if [ "$mode" = "update" ] && [ ! -f "$manifest" ]; then
  echo "No manifest at .claude/kit/manifest: this looks like a first install. Run without --update." >&2
  exit 1
fi

# kit files: common + stack rules
while IFS= read -r -d '' f; do
  install_kit_file "$f" "${f#"$KIT_DIR/kit/"}"
done < <(find "$KIT_DIR/kit" -type f -print0 | sort -z)
for s in go ts py; do
  if has_stack "$s"; then
    while IFS= read -r -d '' f; do
      install_kit_file "$f" "${f#"$KIT_DIR/stacks/$s/"}"
    done < <(find "$KIT_DIR/stacks/$s" -type f -print0 | sort -z)
  fi
done
if [ "$data" -eq 1 ]; then
  while IFS= read -r -d '' f; do
    install_kit_file "$f" "${f#"$KIT_DIR/stacks/data/"}"
  done < <(find "$KIT_DIR/stacks/data" -type f -print0 | sort -z)
fi
if ! has_stack ts && [ "$frontend" -eq 1 ]; then
  while IFS= read -r -d '' f; do
    rel="${f#"$KIT_DIR/stacks/ts/"}"
    if is_frontend_file "$rel"; then install_kit_file "$f" "$rel"; fi
  done < <(find "$KIT_DIR/stacks/ts" -type f -print0 | sort -z)
fi

# project files
for f in CLAUDE.md docs/progress.md docs/decisions.md docs/requirements.md; do
  install_project_file "$KIT_DIR/scaffold/$f" "$f"
done
[ "$data" -eq 1 ] && install_project_file "$KIT_DIR/scaffold/docs/data.md" "docs/data.md"
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
    echo "data=$data"
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
