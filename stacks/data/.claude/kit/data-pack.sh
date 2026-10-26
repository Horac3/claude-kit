#!/usr/bin/env bash
# claude-kit data pack: installs a curated set of third-party data-science skills into THIS project.
# Nothing is vendored into the kit; everything comes from its upstream source, with its licence.
#
#   .claude/kit/data-pack.sh                         show the plan for the core pack (nothing is installed)
#   .claude/kit/data-pack.sh core notebooks --apply  install the named packs
#   .claude/kit/data-pack.sh --list                  describe every pack
#
# Packs:
#   core       Anthropic's data skills: explore-data, statistical-analysis, validate-data, sql-queries,
#              data-visualization, data-context-extractor (Apache-2.0)
#   eda        K-Dense exploratory-data-analysis (profiles, missingness/leakage audits) and scientific-visualization (MIT)
#   notebooks  OpenAI jupyter-notebook: templates and a helper that writes clean .ipynb files (Apache-2.0)
#   ml         ml-pipeline-workflow (wshobson, MIT) and shap for explaining models (K-Dense, MIT)
#   dbt        dbt Labs skills for analytics engineering (Apache-2.0); only when dbt_project.yml exists
#   duckdb     MotherDuck's DuckDB SQL skill (MIT); only when duckdb is a dependency
#
# Run it from a terminal (or with `!` in Claude Code), not by asking Claude: third-party installers may
# change .claude/ and add files, which the kit's guards deliberately stop Claude from doing.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd)}"
cd "$root" || exit 1

apply=0 list=0
declare -a packs=()
# shellcheck disable=SC2034  # apply is read by pack-lib.sh
for a in "$@"; do
  case "$a" in
    --apply) apply=1 ;;
    --list) list=1 ;;
    core | eda | notebooks | ml | dbt | duckdb) packs+=("$a") ;;
    all) packs=(core eda notebooks ml dbt duckdb) ;;
    -h | --help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a (try --list)" >&2; exit 2 ;;
  esac
done
[ ${#packs[@]} -eq 0 ] && packs=(core)

# Shared plan/apply/licence machinery. Installed next to this script; in the kit repo it lives under kit/.
lib="$here/pack-lib.sh"; [ -f "$lib" ] || lib="$here/../../../../kit/.claude/kit/pack-lib.sh"
# shellcheck source=../../../../kit/.claude/kit/pack-lib.sh
. "$lib"

depends_on() { # depends_on <package>: listed in pyproject.toml, a requirements file, Pipfile or environment.yml
  local f
  for f in pyproject.toml requirements*.txt Pipfile environment.yml; do
    [ -f "$f" ] && grep -qiE "(^|[^[:alnum:]_.-])$1([^[:alnum:]_.-]|$)" "$f" && return 0
  done
  return 1
}
has_dbt_project() { [ -f dbt_project.yml ] || [ -n "$(find . -maxdepth 3 -name dbt_project.yml -not -path './.git/*' 2>/dev/null | head -1)" ]; }

for p in "${packs[@]}"; do
  case "$p" in
    core)
      add "$SKILLS anthropics/knowledge-work-plugins --skill explore-data statistical-analysis validate-data sql-queries data-visualization data-context-extractor $FLAGS" anthropics/knowledge-work-plugins
      note "core: explore-data profiles a table or file; validate-data reviews an analysis before you share it; data-context-extractor turns your team's data knowledge into a project skill (pair it with docs/data.md)."
      note "Each auto-invoked skill adds its one-line description to every session (about 50-100 tokens each). Install what you use."
      ;;
    eda)
      add "$SKILLS K-Dense-AI/scientific-agent-skills --skill exploratory-data-analysis scientific-visualization $FLAGS" K-Dense-AI/scientific-agent-skills
      note "eda: overlaps with core's explore-data. Keep both only if you want K-Dense's report scaffolds and leakage audit; its scripts need Python 3.11+."
      ;;
    notebooks)
      add "$SKILLS openai/skills --skill jupyter-notebook $FLAGS" openai/skills skills/.curated/jupyter-notebook/LICENSE.txt
      ;;
    ml)
      add "$SKILLS wshobson/agents --skill ml-pipeline-workflow $FLAGS" wshobson/agents
      add "$SKILLS K-Dense-AI/scientific-agent-skills --skill shap $FLAGS" K-Dense-AI/scientific-agent-skills
      ;;
    dbt)
      if has_dbt_project; then
        add "$SKILLS dbt-labs/dbt-agent-skills --skill using-dbt-for-analytics-engineering running-dbt-commands adding-dbt-unit-test answering-natural-language-questions-with-dbt $FLAGS" dbt-labs/dbt-agent-skills
      else
        note "dbt: skipped, no dbt_project.yml (this project does not use dbt)."
      fi
      ;;
    duckdb)
      if depends_on duckdb; then
        add "$SKILLS motherduckdb/agent-skills --skill motherduck-duckdb-sql $FLAGS" motherduckdb/agent-skills
      else
        note "duckdb: skipped, duckdb is not a dependency of this project."
      fi
      ;;
  esac
done
manual "/plugin install document-skills@anthropic-agent-skills    (Anthropic's docx/xlsx/pptx/pdf skills, for reports and decks; run inside Claude Code)"

if [ $list -eq 1 ]; then sed -n '9,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0; fi

pack_run data
