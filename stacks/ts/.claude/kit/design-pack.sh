#!/usr/bin/env bash
# claude-kit design pack: installs a curated set of third-party frontend design skills and MCP servers
# into THIS project. Nothing is vendored into the kit; everything comes from its upstream source.
#
#   .claude/kit/design-pack.sh                     show the plan for the core pack (nothing is installed)
#   .claude/kit/design-pack.sh core motion --apply install the named packs
#   .claude/kit/design-pack.sh --list              describe every pack
#
# Packs:
#   core      impeccable (taste + critique/audit/polish + DESIGN.md generator) and Vercel web-design-guidelines
#   motion    Emil Kowalski's animation/design-engineering skills (a focused subset)
#   taste     Leonxlnx taste-skill (design-taste-frontend). Overlaps with impeccable: pick one as the main voice
#   shadcn    shadcn MCP server: browse and install registry components (only for shadcn/ui projects)
#   devtools  Chrome DevTools MCP: live browser, console, network, performance traces
#
# Run it from a terminal (or with `!` in Claude Code), not by asking Claude: third-party installers may
# change .claude/settings.json and add hooks, which the kit's guards deliberately stop Claude from doing.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd)}"
cd "$root" || exit 1

apply=0 list=0
declare -a packs=()
for a in "$@"; do
  case "$a" in
    --apply) apply=1 ;;
    --list) list=1 ;;
    core | motion | taste | shadcn | devtools) packs+=("$a") ;;
    all) packs=(core motion shadcn devtools) ;;
    -h | --help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a (try --list)" >&2; exit 2 ;;
  esac
done
[ ${#packs[@]} -eq 0 ] && packs=(core)

dlx="npx"
if [ -f pnpm-lock.yaml ] || [ -f pnpm-workspace.yaml ]; then dlx="pnpm dlx"; fi
[ -f bun.lock ] || [ -f bun.lockb ] && dlx="bunx"
SKILLS="npx -y skills@latest add"
FLAGS="-a claude-code -y --copy"

# Empty arrays are expanded as ${a[@]+"${a[@]}"}: plain "${a[@]}" is an unbound-variable error under set -u in bash < 4.4.
declare -a CMDS=() MANUAL=() NOTES=()
add() { CMDS+=("$1"); }
manual() { MANUAL+=("$1"); }
note() { NOTES+=("$1"); }

for p in "${packs[@]}"; do
  case "$p" in
    core)
      add "npx -y impeccable install --providers=claude --scope=project"
      add "$SKILLS vercel-labs/agent-skills --skill web-design-guidelines $FLAGS"
      manual "/plugin install frontend-design@claude-plugins-official    (Anthropic's frontend-design skill; run inside Claude Code)"
      note "impeccable adds /impeccable <command> (craft, shape, critique, audit, polish, document, …) and a hook that scans UI edits."
      note "web-design-guidelines fetches Vercel's rule list from GitHub on each run; /ui runs it in a subagent so the rules stay out of your context."
      ;;
    motion)
      add "$SKILLS emilkowalski/skills --skill emil-design-eng review-animations apple-design break-ui $FLAGS"
      note "motion: emil-design-eng (motion craft), review-animations, apple-design (Apple interface and motion principles for the web), break-ui (worst-case data)."
      ;;
    taste)
      add "$SKILLS https://github.com/Leonxlnx/taste-skill --skill design-taste-frontend $FLAGS"
      note "taste overlaps with impeccable and frontend-design. Several always-on taste skills can give conflicting direction: keep one as the main voice."
      ;;
    shadcn)
      if [ -f components.json ]; then
        add "$dlx shadcn@latest mcp init --client claude"
      else
        note "shadcn: skipped, no components.json (this project does not use shadcn/ui)."
      fi
      ;;
    devtools)
      add "claude mcp add chrome-devtools --scope project -- npx -y chrome-devtools-mcp@latest --isolated"
      note "devtools: an interactive browser for debugging. For routine visual checks, the kit's ui-checker (shot.mjs) is cheaper."
      ;;
  esac
done

if [ $list -eq 1 ]; then sed -n '9,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0; fi

echo "claude-kit design pack: ${packs[*]}"
echo "Shell commands:"
for c in ${CMDS[@]+"${CMDS[@]}"}; do echo "  $c"; done
if [ ${#MANUAL[@]} -gt 0 ]; then
  echo "Inside Claude Code:"
  for m in "${MANUAL[@]}"; do echo "  $m"; done
fi
for n in ${NOTES[@]+"${NOTES[@]}"}; do echo "  · $n"; done

if [ $apply -eq 0 ]; then
  echo
  echo "Nothing installed. Re-run with --apply to install. Third-party skills run with full agent permissions:"
  echo "read them before use (they land in .claude/skills/ and are listed in skills-lock.json)."
  exit 0
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
  [ -n "$(git status --porcelain -- .claude .mcp.json 2>/dev/null)" ]; then
  echo "Uncommitted changes under .claude/ or .mcp.json. Commit them first so you can review exactly what the installers change." >&2
  exit 1
fi

rc=0
for c in ${CMDS[@]+"${CMDS[@]}"}; do
  echo "→ $c"
  bash -c "$c" || { echo "  failed (exit $?)"; rc=1; }
done
echo
echo "Review what changed, then commit (including skills-lock.json, which pins the versions):"
git status --short -- .claude .mcp.json skills-lock.json 2>/dev/null | sed 's/^/  /'
[ ${#MANUAL[@]} -gt 0 ] && { echo "Then, inside Claude Code:"; for m in "${MANUAL[@]}"; do echo "  $m"; done; }
exit $rc
