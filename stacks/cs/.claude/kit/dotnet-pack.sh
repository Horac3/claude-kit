#!/usr/bin/env bash
# claude-kit dotnet pack: installs a curated set of third-party C#/.NET skills into THIS project.
# Nothing is vendored into the kit; everything comes from its upstream source, with its licence.
#
#   .claude/kit/dotnet-pack.sh                         show the plan for the core pack (nothing is installed)
#   .claude/kit/dotnet-pack.sh core api --apply        install the named packs
#   .claude/kit/dotnet-pack.sh --list                  describe every pack
#
# Packs:
#   core          modern C# standards, nullable reference types, concurrency, project structure, NuGet/CPM (Aaron Stannard, MIT)
#   api           minimal APIs, versioning, OpenAPI, errors, auth, HttpClient, resilience, caching (Mukesh Murugan, MIT)
#   architecture  architecture advisor, clean architecture, vertical slices, DDD (Mukesh Murugan, MIT)
#   data          EF Core patterns and database performance (Aaron Stannard, MIT)
#   testing       Testcontainers, Verify snapshots, CRAP coverage analysis (Aaron Stannard, MIT)
#   performance   type design for performance, AOT and trimming, serialization (Aaron Stannard, MIT)
#   ops           OpenTelemetry, SDK container publishing (Aaron Stannard) and CI/CD (Mukesh Murugan), MIT
#   aspire        .NET Aspire config, service defaults, integration tests, Mailpit (Aaron Stannard, MIT); only with Aspire
#   akka          Akka.NET practices, testing, hosting, management (Aaron Stannard, MIT); only with Akka.NET
#   desktop       Avalonia and desktop MVVM (Mukesh Murugan, MIT); only with Avalonia, WPF, WinForms, MAUI or the MVVM Toolkit
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
    core | api | architecture | data | testing | performance | ops | aspire | akka | desktop) packs+=("$a") ;;
    all) packs=(core api architecture data testing performance ops aspire akka desktop) ;;
    -h | --help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a (try --list)" >&2; exit 2 ;;
  esac
done
[ ${#packs[@]} -eq 0 ] && packs=(core)

# Shared plan/apply/licence machinery. Installed next to this script; in the kit repo it lives under kit/.
lib="$here/pack-lib.sh"; [ -f "$lib" ] || lib="$here/../../../../kit/.claude/kit/pack-lib.sh"
# shellcheck source=../../../../kit/.claude/kit/pack-lib.sh
. "$lib"

AARON=Aaronontheweb/dotnet-skills
MUKESH=codewithmukesh/dotnet-claude-kit

uses() { # uses <regex>: a project file or central props file (up to three folders down) matches
  find . -maxdepth 4 \( -name .git -o -name node_modules -o -name bin -o -name obj \) -prune -o \
    \( -name '*.csproj' -o -name 'Directory.Packages.props' -o -name 'Directory.Build.props' \) -type f -print 2>/dev/null |
    tr '\n' '\0' | xargs -0 grep -l -E "$1" 2>/dev/null | head -1 | grep -q .
}

for p in "${packs[@]}"; do
  case "$p" in
    core)
      add "$SKILLS $AARON --skill modern-csharp-coding-standards csharp-nullable-reference-types csharp-concurrency-patterns dotnet-project-structure package-management $FLAGS" "$AARON"
      note "core: the kit's csharp rule already covers the basics; these skills add depth when Claude works on those topics."
      note "Each auto-invoked skill adds its one-line description to every session (about 50-100 tokens each). Install what you use."
      ;;
    api)
      add "$SKILLS $MUKESH --skill minimal-api api-versioning openapi error-handling authentication httpclient-factory resilience caching $FLAGS" "$MUKESH"
      note "api: written for .NET 10 minimal APIs; on older target frameworks check each suggestion against your SDK."
      ;;
    architecture)
      add "$SKILLS $MUKESH --skill architecture-advisor clean-architecture vertical-slice ddd $FLAGS" "$MUKESH"
      note "architecture: pick one style per project and record it with /decide; the kit's hexagonal rule still applies to ports and adapters."
      ;;
    data)
      add "$SKILLS $AARON --skill efcore-patterns database-performance $FLAGS" "$AARON"
      ;;
    testing)
      add "$SKILLS $AARON --skill testcontainers-integration-tests snapshot-testing crap-analysis $FLAGS" "$AARON"
      note "testing: Testcontainers needs Docker where the tests run; snapshot-testing uses the Verify library."
      ;;
    performance)
      add "$SKILLS $AARON --skill type-design-performance aot-trimming serialization $FLAGS" "$AARON"
      ;;
    ops)
      add "$SKILLS $AARON --skill opentelemetry-net-instrumentation sdk-container-publishing $FLAGS" "$AARON"
      add "$SKILLS $MUKESH --skill ci-cd $FLAGS" "$MUKESH"
      ;;
    aspire)
      if uses 'Aspire\.'; then
        add "$SKILLS $AARON --skill aspire-configuration aspire-service-defaults aspire-integration-testing mailpit-integration $FLAGS" "$AARON"
      else
        note "aspire: skipped, no project references .NET Aspire."
      fi
      ;;
    akka)
      if uses 'Akka\.'; then
        add "$SKILLS $AARON --skill akka-net-best-practices akka-net-testing-patterns akka-hosting-actor-patterns akka-net-management akka-net-aspire-configuration $FLAGS" "$AARON"
      else
        note "akka: skipped, no project references Akka.NET."
      fi
      ;;
    desktop)
      if uses 'Avalonia|CommunityToolkit\.Mvvm|<UseWPF>true|<UseWindowsForms>true|<UseMaui>true'; then
        add "$SKILLS $MUKESH --skill avalonia desktop-mvvm $FLAGS" "$MUKESH"
      else
        note "desktop: skipped, no Avalonia, WPF, WinForms, MAUI or MVVM Toolkit project."
      fi
      ;;
  esac
done
note "Alternative to the Aaron Stannard packs: all of his skills and agents as one plugin, per user, inside Claude Code: /plugin marketplace add Aaronontheweb/dotnet-skills, then /plugin install dotnet-skills@dotnet-skills."

if [ $list -eq 1 ]; then sed -n '9,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0; fi

pack_run dotnet
