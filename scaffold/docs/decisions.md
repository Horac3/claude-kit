# Decisions

Append-only log. Newest at the bottom. `/decide` drafts entries in this shape; supersede an entry by
adding a new one that references it, never by editing history.

## D-001: Use claude-kit workflow
Date: TODO(kickoff)
Status: accepted
Context: Sessions need consistent rules, cheap context, and clean handoffs between conversations and models.
Decision: Follow the claude-kit loop: `/next` per roadmap step, test-first, `opusplan` with delegated
subagents, state in `docs/progress.md`.
Consequences: Every conversation starts with `/next` and ends with `/handoff`.
Revisit if: the overhead outweighs the benefit for this project.
