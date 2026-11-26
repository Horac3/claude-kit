---
name: handover
description: Write HANDOVER.md so another engineer can take over ownership of this project (status, architecture, run, deploy, runbooks, open work, questions for the owner). For person-to-person handover; for session-to-session notes use /handoff.
argument-hint: "[successor name or focus area]"
disable-model-invocation: true
effort: high
---

Prepare a handover so another engineer can run, deploy, support and extend this project without the current
owner. Successor or focus (may be empty): $ARGUMENTS

## Repo facts (gathered by script)
```!
echo "## Uncommitted"; git status --short 2>/dev/null | head -40
echo "## Unpushed"; git log --oneline @{u}..HEAD 2>/dev/null | head -20
echo "## Local branches without upstream"; git for-each-ref --format='%(refname:short) %(upstream)' refs/heads 2>/dev/null | awk 'NF==1' | head -20
echo "## Stashes"; git stash list 2>/dev/null | head -10
.claude/kit/context.sh layout 2>/dev/null | head -60
.claude/kit/context.sh existing 2>/dev/null | head -40
.claude/kit/context.sh history 30 2>/dev/null | head -60
true
```

## Rules
- **Only state what you can verify** from code, config, scripts, CI files, migrations, git history and the
  project docs. Where something can't be determined, write `TODO (owner): <what is missing>`. Never guess.
- **Never copy secrets.** No keys, passwords, tokens or connection strings. Name the variable and where its value
  lives (e.g. "server `.env`; value in the team vault"). Do not read `.env` files; use `.env.example` and code.
- **Change no code.** The only file you write is `HANDOVER.md` at the repo root. If it already exists and is tracked,
  update it with Edit, section by section.
- Cite file paths for every important claim. Plain English for an engineer new to the codebase; no filler.
- Reuse what the kit already keeps rather than re-deriving it: `docs/architecture.md`, `docs/decisions.md`,
  `docs/progress.md`, `docs/requirements.md` when present. If the architecture map is stale, say so and suggest `/remap`.
- Explore with parallel `Explore` subagents for large repos, and keep their raw output out of the main context.
- Run the suite through `test-runner` (or `.claude/kit/check.sh`) only if it runs without external credentials.
  Otherwise record why it could not run.

## HANDOVER.md sections
1. **⚠️ Before handover:** uncommitted or unpushed work, branches without upstream, stashes, failing tests.
2. **Summary:** what it does in business terms (2–3 sentences), who depends on it, status (live / pilot / in development).
3. **Architecture:** stack, modules and what each owns, data flow for the key journeys. A Mermaid diagram if it helps.
4. **External integrations:** per provider: purpose, adapter location, auth method, sandbox vs production config, quirks.
5. **Data:** databases, key entities, migration approach, queues and jobs (names, schedules, retry and backoff).
6. **Configuration:** every environment variable: name, purpose, required, a non-secret example.
7. **Run locally:** exact commands from clone to running, including seeding and tests.
8. **Deploy and rollback:** build and deploy path, environments, health checks, rollback, reversing a migration.
9. **Runbook:** likely incidents found in the code (e.g. stuck pending states, missing or duplicate callbacks, provider
   outage, reconciliation mismatch, queue backlog). Each as symptom → where to look → fix.
10. **Reliability and safety:** idempotency, retries, circuit breakers, locking, tenant isolation, logging, monitoring. Note gaps.
11. **Known issues and debt:** TODO/FIXME/HACK, risky areas, missing tests, outdated dependencies.
12. **Decision log:** key design choices and why. Link `docs/decisions.md` entries; mark inferred reasons `TODO (owner): confirm`.
13. **Open work:** in-progress branches, half-finished features, recent commits that suggest work in flight.
14. **Questions for the owner:** a numbered list of everything you could not determine.

## Return (≤ 8 lines)
```
HANDOVER.md written (<n> sections)
Blocking before handover: <list or "none">
Tests: <pass | fail | not run: reason>
Questions for owner: <n>   TODOs: <n>
```
Do not commit unless the user asks.
